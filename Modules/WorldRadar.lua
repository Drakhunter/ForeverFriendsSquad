-- =========================================================================
-- Modules/WorldRadar.lua
-- Priority 3 (World & Navigation): Out-of-Group World Map Friend Pins,
-- Adaptive GPS Sync, Death/Gank Detection, and Interactive SOS Toast Banner.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

local Radar = {}
ns.Radar = Radar

local mapPins = {}
local lastAttackerName = nil
local lastAttackerIsPlayer = false
local toastFrame = nil
local lastBroadcastTime = 0
local lastMapID = 0
local lastZone = ""
local lastX, lastY = 0, 0

-- -------------------------------------------------------------------------
-- Native Party / Raid Local Reader (0 Network Packets for Group Members!)
-- Reads HP, Mana, Zone, and Map Coordinates directly from the WoW Client API
-- for any friend who is currently in your Party or Raid.
-- -------------------------------------------------------------------------
function Radar:UpdateLocalGroupMembers()
    if not IsInGroup or not IsInGroup() then return false end
    local isRaid = IsInRaid and IsInRaid()
    local count = isRaid and (GetNumGroupMembers and GetNumGroupMembers() or 0) or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0)
    local updatedAny = false
    local now = time()

    for i = 1, count do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        if UnitExists and UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
            local short = ns.GetUnitName(unit)
            if short ~= "" and short ~= "Unbekannt" and not ns.IsSelfName(short) then
                local charKey = ns.NormalizeCharKey(short)
                local peer = ns.onlinePeers[charKey] or {}

                local _, classFile = UnitClass and UnitClass(unit)
                local lvl = UnitLevel and UnitLevel(unit)
                local fac = UnitFactionGroup and select(1, UnitFactionGroup(unit))

                local hpCur = ns.SafeNumber(UnitHealth and UnitHealth(unit), 100)
                local hpMax = math.max(1, ns.SafeNumber(UnitHealthMax and UnitHealthMax(unit), 100))
                local hpPct = math.floor((hpCur / hpMax) * 100 + 0.5)

                local mCur = ns.SafeNumber(UnitPower and UnitPower(unit, 0), 100)
                local mMax = math.max(1, ns.SafeNumber(UnitPowerMax and UnitPowerMax(unit, 0), 100))
                local manaPct = math.floor((mCur / mMax) * 100 + 0.5)

                local mapID = (C_Map and C_Map.GetBestMapForUnit and ns.SafeNumber(C_Map.GetBestMapForUnit(unit), 0)) or peer.mapID or 0
                local x, y = peer.x or 0, peer.y or 0
                if mapID > 0 and C_Map and C_Map.GetPlayerMapPosition then
                    local okPos, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
                    if okPos and pos and not ns.IsSecret(pos) and pos.GetXY then
                        local px, py = pos:GetXY()
                        x = ns.SafeNumber(px, x)
                        y = ns.SafeNumber(py, y)
                    end
                end

                local zoneName = peer.zone
                if mapID > 0 and C_Map and C_Map.GetMapInfo then
                    local okMap, mInfo = pcall(C_Map.GetMapInfo, mapID)
                    if okMap and mInfo and not ns.IsSecret(mInfo) and mInfo.name then
                        zoneName = ns.SafeString(mInfo.name, zoneName)
                    end
                end

                peer.key = charKey
                peer.name = short
                peer.shortName = short
                peer.class = ns.SafeString(classFile, peer.class or "WARRIOR")
                if lvl and not ns.IsSecret(lvl) and lvl > 0 then peer.level = lvl end
                peer.faction = ns.NormalizeFaction(fac or peer.faction or ns.GetPlayerFaction())
                peer.zone = zoneName or "In Gruppe"
                peer.mapID = mapID
                peer.x = x
                peer.y = y
                peer.hpPct = hpPct
                peer.manaPct = manaPct
                peer.inCombat = ns.SafeBoolean(UnitAffectingCombat and UnitAffectingCombat(unit))
                peer.isDead = ns.SafeBoolean(UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit))
                peer.lastSeen = now
                ns.onlinePeers[charKey] = peer
                updatedAny = true
            end
        end
    end

    if updatedAny and ns.QoL and ns.QoL.UpdateHUD then
        ns.QoL:UpdateHUD()
    end
    return updatedAny
end

-- Check if there is at least one online friend/guildmate who is NOT already in our Party/Raid
function Radar:HasOutOfGroupRecipient()
    if IsInGuild and IsInGuild() and ns.db and ns.db.sync and ns.db.sync.useGuild then
        return true
    end
    local onlineFriends = (ns.Sync and ns.Sync.GetConfirmedOnlineFriends and ns.Sync:GetConfirmedOnlineFriends()) or {}
    for _, shortName in pairs(onlineFriends) do
        local inGroup = (UnitInParty and UnitInParty(shortName)) or (UnitInRaid and UnitInRaid(shortName))
        if not inGroup then
            return true
        end
    end
    return false
end

-- -------------------------------------------------------------------------
-- Player Vitals & GuildMap-Style GPS Broadcast (Zero Idle Polling!)
-- -------------------------------------------------------------------------
local function GetPlayerVitals()
    local hpCur = ns.SafeNumber(UnitHealth and UnitHealth("player"), 100)
    local hpMax = math.max(1, ns.SafeNumber(UnitHealthMax and UnitHealthMax("player"), 100))
    local hpPct = math.floor((hpCur / hpMax) * 100 + 0.5)

    local pType = UnitPowerType and UnitPowerType("player")
    local manaPct = 100
    if pType == 0 then
        local mCur = ns.SafeNumber(UnitPower and UnitPower("player", 0), 100)
        local mMax = math.max(1, ns.SafeNumber(UnitPowerMax and UnitPowerMax("player", 0), 100))
        manaPct = math.floor((mCur / mMax) * 100 + 0.5)
    end

    local inCombat = ns.SafeBoolean(UnitAffectingCombat and UnitAffectingCombat("player"))
    local isDead = ns.SafeBoolean(UnitIsDeadOrGhost and UnitIsDeadOrGhost("player"))
    return hpPct, manaPct, inCombat, isDead
end

function Radar:BroadcastGPS(whisperTarget, force)
    if not ns.Sync or not ns.db or not ns.db.radar or not ns.db.radar.enabled then return end

    local isTargeted = (whisperTarget ~= nil and whisperTarget ~= "")
    if not force and not isTargeted then
        -- GuildMap Rule 1: Never poll GPS while in combat or inside dungeon/raid instances
        if ns.Sync:IsPlayerInCombat() then return end
        if IsInInstance and select(1, IsInInstance()) then return end
        -- GuildMap Rule 2: If nobody outside our Party/Raid is reachable, Party/Raid already reads our position locally!
        if not self:HasOutOfGroupRecipient() then return end
    end

    local zone, subzone, mapID, x, y = ns.GetPlayerLocationData()
    x = x or 0
    y = y or 0

    if not force and not isTargeted then
        -- GuildMap Rule 3: Zero traffic when standing still / idle!
        -- Only broadcast if the map/zone changed OR player moved by at least 0.8% of map width
        local dx = x - (lastX or 0)
        local dy = y - (lastY or 0)
        local distSq = (dx * dx) + (dy * dy)
        local zoneChanged = (mapID ~= lastMapID) or (zone ~= lastZone)
        if not zoneChanged and distSq < 0.000064 then
            return -- Standing still -> 0 packets sent!
        end
    end

    local hpPct, manaPct, inCombat, isDead = GetPlayerVitals()
    local lockouts = (ns.QoL and ns.QoL.GetActiveLockoutCount and ns.QoL:GetActiveLockoutCount()) or 0

    lastMapID = mapID
    lastZone = zone
    lastX, lastY = x, y
    lastBroadcastTime = GetTime()

    ns.Sync:Broadcast("GPS", {
        zone = zone,
        subzone = subzone,
        mapID = mapID,
        x = tonumber(string.format("%.4f", x)) or 0,
        y = tonumber(string.format("%.4f", y)) or 0,
        hp = hpPct,
        mp = manaPct,
        cb = inCombat and 1 or 0,
        dead = isDead and 1 or 0,
        lo = lockouts,
    }, "NORMAL", whisperTarget)
end

function Radar:OnReceiveGPS(charKey, peer, data)
    if type(data) ~= "table" then return end
    peer.zone = ns.SafeString(data.zone, peer.zone or "Unbekannt")
    peer.subzone = ns.SafeString(data.subzone, peer.subzone or "")
    peer.mapID = ns.SafeNumber(data.mapID, peer.mapID or 0)
    peer.x = ns.SafeNumber(data.x, peer.x or 0)
    peer.y = ns.SafeNumber(data.y, peer.y or 0)
    peer.hpPct = ns.SafeNumber(data.hp, 100)
    peer.manaPct = ns.SafeNumber(data.mp, 100)
    peer.inCombat = (data.cb == 1 or data.cb == true)
    peer.isDead = (data.dead == 1 or data.dead == true)
    peer.lockouts = ns.SafeNumber(data.lo, peer.lockouts or 0)
    peer.lastSeen = time()

    if WorldMapFrame and WorldMapFrame:IsShown() then
        self:RefreshWorldMapPins()
    end
    if ns.QoL and ns.QoL.UpdateHUD then
        ns.QoL:UpdateHUD()
    end
end

-- -------------------------------------------------------------------------
-- World Map Canvas Pin Overlay (Works Solo & Out-of-Group!)
-- -------------------------------------------------------------------------
local function GetWorldMapCanvas()
    if WorldMapFrame and WorldMapFrame.GetCanvas then
        local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
        if ok and canvas then return canvas end
    end
    if WorldMapDetailFrame then
        return WorldMapDetailFrame
    end
    return nil
end

local function GetDisplayedMapID()
    if WorldMapFrame and WorldMapFrame.GetMapID then
        local ok, mapID = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
        if ok and mapID then return ns.SafeNumber(mapID, 0) end
    end
    if C_Map and C_Map.GetBestMapForUnit then
        return ns.SafeNumber(C_Map.GetBestMapForUnit("player"), 0)
    end
    return 0
end

local function AcquireMapPin(index, canvas)
    local pin = mapPins[index]
    if not pin then
        pin = CreateFrame("Button", "ForeverFriendsMapPin" .. index, canvas, "BackdropTemplate")
        pin:SetSize(18, 18)
        pin:SetFrameStrata("HIGH")
        pin:SetFrameLevel(2500)
        pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        pin:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })

        local inner = pin:CreateTexture(nil, "ARTWORK")
        inner:SetPoint("TOPLEFT", 2, -2)
        inner:SetPoint("BOTTOMRIGHT", -2, 2)
        inner:SetTexture("Interface\\Buttons\\WHITE8X8")
        pin.inner = inner

        local label = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOP", pin, "BOTTOM", 0, -2)
        label:SetShadowColor(0, 0, 0, 1)
        label:SetShadowOffset(1, -1)
        pin.label = label

        pin:SetScript("OnEnter", function(self)
            local p = self.peerData
            if not p then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local r, g, b = ns.GetClassColor(p.class)
            GameTooltip:SetText(string.format("%s (Lv %d)", p.shortName or p.name, p.level or 1), r, g, b)
            GameTooltip:AddLine(string.format("%s%s", p.zone or "Unbekannt", (p.subzone and p.subzone ~= "") and (" — " .. p.subzone) or ""), 0.9, 0.9, 0.9)
            if p.x and p.y and p.x > 0 then
                GameTooltip:AddLine(string.format("Koordinaten: %.1f, %.1f", p.x * 100, p.y * 100), 0.22, 0.74, 0.97)
            end
            GameTooltip:AddLine(string.format("LP: %d%%%s", p.hpPct or 100, p.inCombat and " |cfff87171(Im Kampf!)|r" or ""), 0.8, 0.9, 0.8)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffffd100Linksklick:|r Wegpunkt setzen", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("|cffffd100Rechtsklick:|r In Gruppe einladen", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)

        pin:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        pin:SetScript("OnClick", function(self, button)
            local p = self.peerData
            if not p then return end
            if button == "RightButton" then
                if C_PartyInfo and C_PartyInfo.InviteUnit then
                    C_PartyInfo.InviteUnit(p.shortName or p.name)
                elseif InviteUnit then
                    InviteUnit(p.shortName or p.name)
                end
                ns.Print("Einladung gesendet an: " .. ns.ColorByClass(p.shortName or p.name, p.class))
            else
                ns.SetMapWaypoint(p.mapID, p.x, p.y, p.shortName or p.name)
            end
        end)

        mapPins[index] = pin
    end

    if pin:GetParent() ~= canvas then
        pin:SetParent(canvas)
    end
    return pin
end

function Radar:RefreshWorldMapPins()
    for _, pin in ipairs(mapPins) do
        pin:Hide()
    end

    if not ns.db or not ns.db.radar or not ns.db.radar.enabled or not ns.db.radar.showWorldMapPins then
        return
    end
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end

    local canvas = GetWorldMapCanvas()
    local viewedMapID = GetDisplayedMapID()
    if not canvas or viewedMapID <= 0 then return end

    local width = ns.SafeNumber(canvas:GetWidth(), 0)
    local height = ns.SafeNumber(canvas:GetHeight(), 0)
    if width <= 0 or height <= 0 then return end

    local scale = ns.SafeNumber(ns.db.radar.pinScale, 1.0)
    local showNames = ns.db.radar.showPinNames ~= false
    local now = time()
    local pinIdx = 0

    for _, peer in pairs(ns.onlinePeers or {}) do
        if (now - (peer.lastSeen or 0)) < 600 and peer.mapID == viewedMapID and peer.x and peer.y and peer.x > 0 and peer.y > 0 then
            pinIdx = pinIdx + 1
            local pin = AcquireMapPin(pinIdx, canvas)
            pin.peerData = peer
            pin:SetSize(16 * scale, 16 * scale)

            local r, g, b = ns.GetClassColor(peer.class)
            pin.inner:SetVertexColor(r, g, b, 1.0)
            if peer.isDead then
                pin:SetBackdropBorderColor(0.97, 0.35, 0.35, 1.0)
            elseif peer.inCombat then
                pin:SetBackdropBorderColor(0.98, 0.75, 0.14, 1.0)
            else
                pin:SetBackdropBorderColor(0.05, 0.07, 0.10, 1.0)
            end

            if showNames then
                pin.label:SetText(ns.ColorByClass(peer.shortName or peer.name, peer.class))
                pin.label:Show()
            else
                pin.label:Hide()
            end

            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", peer.x * width, -peer.y * height)
            pin:Show()
        end
    end
end

-- -------------------------------------------------------------------------
-- Emergency / Death / Gank Toast Alert Banner
-- -------------------------------------------------------------------------
local function EnsureToastBanner()
    if toastFrame then return toastFrame end

    local cfg = (ns.db and ns.db.ui and ns.db.ui.toast) or ns.DEFAULTS.ui.toast
    toastFrame = CreateFrame("Button", "ForeverFriendsAlertToast", UIParent, "BackdropTemplate")
    toastFrame:SetSize(380, 62)
    toastFrame:SetPoint(cfg.point or "TOP", UIParent, cfg.relPoint or "TOP", cfg.x or 0, cfg.y or -110)
    toastFrame:SetFrameStrata("DIALOG")
    toastFrame:SetScale(cfg.scale or 1.0)
    toastFrame:SetMovable(true)
    toastFrame:EnableMouse(true)
    toastFrame:RegisterForDrag("LeftButton")
    toastFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    toastFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    toastFrame:SetBackdropColor(0.07, 0.06, 0.08, 0.96)
    toastFrame:SetBackdropBorderColor(0.97, 0.35, 0.35, 1.0)

    local icon = toastFrame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(38, 38)
    icon:SetPoint("LEFT", toastFrame, "LEFT", 12, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture("Interface\\Icons\\Ability_Creature_Cursed_02")
    toastFrame.icon = icon

    local title = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetPoint("RIGHT", toastFrame, "RIGHT", -12, 0)
    title:SetJustifyH("LEFT")
    toastFrame.title = title

    local sub = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetPoint("RIGHT", toastFrame, "RIGHT", -12, 0)
    sub:SetJustifyH("LEFT")
    toastFrame.sub = sub

    toastFrame:SetScript("OnDragStart", function(self)
        if not (ns.db and ns.db.ui and ns.db.ui.toast and ns.db.ui.toast.locked) then
            self:StartMoving()
        end
    end)
    toastFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.db and ns.db.ui and ns.db.ui.toast then
            local p, _, rp, x, y = self:GetPoint()
            ns.db.ui.toast.point = p
            ns.db.ui.toast.relPoint = rp
            ns.db.ui.toast.x = x
            ns.db.ui.toast.y = y
        end
    end)

    toastFrame:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            self:Hide()
            return
        end
        if self.alertData and self.alertData.mapID and self.alertData.x then
            ns.SetMapWaypoint(self.alertData.mapID, self.alertData.x, self.alertData.y, self.alertData.senderName)
        end
        self:Hide()
    end)

    toastFrame:Hide()
    return toastFrame
end

function Radar:ShowAlertToast(alertData)
    if not ns.db or not ns.db.ui or not ns.db.ui.toast or not ns.db.ui.toast.enabled then return end
    local frame = EnsureToastBanner()
    frame.alertData = alertData

    if alertData.kind == "SOS" then
        frame:SetBackdropBorderColor(0.98, 0.75, 0.14, 1.0)
        frame.icon:SetTexture("Interface\\Icons\\Spell_Holy_PrayerOfHealing")
        frame.title:SetText(string.format("|cfffbbf24[SOS NOTRUF]|r %s", ns.ColorByClass(alertData.senderName, alertData.class)))
    else
        frame:SetBackdropBorderColor(0.97, 0.35, 0.35, 1.0)
        frame.icon:SetTexture("Interface\\Icons\\Ability_Creature_Cursed_02")
        frame.title:SetText(string.format("|cfff87171[TODES-ALARM]|r %s ist gefallen!", ns.ColorByClass(alertData.senderName, alertData.class)))
    end

    local coordStr = (alertData.x and alertData.x > 0) and string.format(" (%.1f, %.1f)", alertData.x * 100, alertData.y * 100) or ""
    frame.sub:SetText(string.format("%s%s — |cff38bdf8%s|r |cff94a3b8[Klick für Wegpunkt]|r", alertData.zone or "Unbekannt", coordStr, alertData.msg or ""))

    frame:Show()
    if ns.db.ui.toast.playSound and PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING or 8959)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(10, function()
            if frame and frame.alertData == alertData then
                frame:Hide()
            end
        end)
    end
end

function Radar:SendSOSAlert(customMessage)
    if not ns.Sync then return end
    local zone, subzone, mapID, x, y = ns.GetPlayerLocationData()
    local msg = ns.SafeString(customMessage, "Brauche Hilfe an meiner Position!")
    ns.Sync:Broadcast("ALERT", {
        kind = "SOS",
        zone = zone,
        subzone = subzone,
        mapID = mapID,
        x = x,
        y = y,
        msg = msg,
    }, "ALERT")
    ns.Print(string.format("SOS-Notruf an Stammgruppe gesendet (%s — %.1f, %.1f)!", zone, (x or 0) * 100, (y or 0) * 100))
end

function Radar:OnReceiveAlert(charKey, peer, data)
    if not ns.db or not ns.db.radar or not ns.db.radar.receiveDeathAlerts then return end
    if type(data) ~= "table" then return end

    local alertInfo = {
        kind = ns.SafeString(data.kind, "DEATH"),
        senderName = peer.shortName or ns.ShortName(charKey),
        class = peer.class or "WARRIOR",
        zone = ns.SafeString(data.zone, "Unbekannt"),
        subzone = ns.SafeString(data.subzone, ""),
        mapID = ns.SafeNumber(data.mapID, 0),
        x = ns.SafeNumber(data.x, 0),
        y = ns.SafeNumber(data.y, 0),
        msg = ns.SafeString(data.msg, ""),
    }

    ns.Print(string.format(
        "|cfff87171[%s]|r %s in |cffffd100%s|r (%.1f, %.1f): %s",
        alertInfo.kind == "SOS" and "SOS" or "TOD",
        ns.ColorByClass(alertInfo.senderName, alertInfo.class),
        alertInfo.zone,
        alertInfo.x * 100,
        alertInfo.y * 100,
        alertInfo.msg
    ))

    self:ShowAlertToast(alertInfo)

    if alertInfo.kind == "SOS" and ns.db.radar.autoWaypointOnSOS and alertInfo.mapID > 0 and alertInfo.x > 0 then
        ns.SetMapWaypoint(alertInfo.mapID, alertInfo.x, alertInfo.y, "SOS: " .. alertInfo.senderName)
    end
end

-- -------------------------------------------------------------------------
-- GuildMap-Style Event & Movement Watcher (Zero Idle Network Traffic!)
-- -------------------------------------------------------------------------
ns.RegisterMessage("PLAYER_READY", function()
    if WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", function()
            Radar:UpdateLocalGroupMembers()
            Radar:RefreshWorldMapPins()
        end)
    end

    if ns.ScheduleRepeatingTimer then
        -- Local check every 3s: updates local Party/Raid members (0 network packets!)
        -- and only sends network GPS if actively traveling across the world (>= 15s cooldown).
        ns:ScheduleRepeatingTimer(function()
            if not ns.db or not ns.db.radar or not ns.db.radar.enabled then return end

            -- 1. Always refresh Party/Raid members locally via WoW API (0 network traffic)
            Radar:UpdateLocalGroupMembers()

            -- 2. Only consider network GPS if enough time elapsed (default 15s while moving)
            local moveInterval = math.max(12, ns.SafeNumber(ns.db.sync and ns.db.sync.gpsIntervalMoving, 15))
            if (GetTime() - lastBroadcastTime) >= moveInterval then
                -- BroadcastGPS internally aborts with 0 packets if idle/standing still, in combat, or in instance!
                Radar:BroadcastGPS(nil, false)
            end

            if WorldMapFrame and WorldMapFrame:IsShown() then
                Radar:RefreshWorldMapPins()
            end
        end, 3.0)
    end
end)

ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
    -- Event-driven update when entering a new zone (debounced by 3s)
    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, function()
            Radar:BroadcastGPS(nil, false)
        end)
    end
end)

ns.RegisterEvent("PLAYER_DEAD", function()
    if ns.Stats and ns.Stats.RecordDeath then
        ns.Stats:RecordDeath()
    end

    if not ns.db or not ns.db.radar or not ns.db.radar.enabled or not ns.db.radar.broadcastDeaths then
        return
    end

    local zone, subzone, mapID, x, y = ns.GetPlayerLocationData()
    local killerMsg = "Gestorben"

    if UnitExists and UnitExists("target") and UnitCanAttack and UnitCanAttack("player", "target") then
        local targetName = ns.GetUnitName("target")
        if targetName and targetName ~= "" and targetName ~= "Unbekannt" then
            local isPlayer = UnitIsPlayer and UnitIsPlayer("target")
            killerMsg = (isPlayer and "Gegankt von Spieler: " or "Getötet von: ") .. targetName
        end
    end

    if ns.Sync then
        ns.Sync:Broadcast("ALERT", {
            kind = "DEATH",
            zone = zone,
            subzone = subzone,
            mapID = mapID,
            x = x,
            y = y,
            msg = killerMsg,
        }, "ALERT")
    end
end)
