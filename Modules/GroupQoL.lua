-- =========================================================================
-- Modules/GroupQoL.lua
-- Priority 4 (Nice to Have): 1-Click Squad Invite, Keyword Auto-Invite,
-- 5/hr Instance Lockout Tracker, Smart Buff-Check, and Floating Squad HUD.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

local QoL = {}
ns.QoL = QoL

local hudFrame = nil
local lastInstanceName = nil

-- -------------------------------------------------------------------------
-- 1-Click Squad Invite & Keyword Auto-Invite
-- -------------------------------------------------------------------------
local function SafeInvite(name, requireConfirmedOnline)
    local short = ns.ShortName(name)
    if short == "" or short == "Unbekannt" or ns.IsSelfName(short) then return false end
    if UnitInParty and UnitInParty(short) then return false end
    if UnitInRaid and UnitInRaid(short) then return false end

    if requireConfirmedOnline and ns.Sync and ns.Sync.GetConfirmedOnlineFriends then
        local onlineMap = ns.Sync:GetConfirmedOnlineFriends()
        local fullOnlineName = onlineMap[short:lower()]
        if not fullOnlineName then
            return false
        end
        short = fullOnlineName
    end

    if C_PartyInfo and C_PartyInfo.InviteUnit then
        pcall(C_PartyInfo.InviteUnit, short)
        return true
    elseif InviteUnit then
        pcall(InviteUnit, short)
        return true
    end
    return false
end

function ns.InviteSquadMembers()
    local invited = {}
    local count = 0

    for _, peer in pairs(ns.onlinePeers or {}) do
        if (time() - (peer.lastSeen or 0)) < 180 then
            local short = peer.shortName or ns.ShortName(peer.name)
            local lower = short:lower()
            if not ns.IsSelfName(short) and not invited[lower] and SafeInvite(short, false) then
                invited[lower] = true
                count = count + 1
            end
        end
    end

    for rosterName, info in pairs(ns.db and ns.db.squadRoster or {}) do
        if info and info.trusted ~= false then
            local short = ns.ShortName(rosterName)
            local lower = short:lower()
            if not ns.IsSelfName(short) and not invited[lower] and SafeInvite(short, true) then
                invited[lower] = true
                count = count + 1
            end
        end
    end

    if count > 0 then
        ns.Print(string.format("Gruppeneinladung an |cff34d399%d|r Online-Freunde gesendet.", count))
    else
        ns.Print("Alle bekannten Online-Freunde sind bereits in deiner Gruppe (oder niemand sonst ist online).")
    end
end

local function MatchesInviteKeyword(msg)
    if not ns.db or not ns.db.qol or not ns.db.qol.autoInviteEnabled then return false end
    local text = strtrim(ns.SafeString(msg, "")):lower()
    if text == "" or #text > 24 then return false end

    local rawKeywords = ns.SafeString(ns.db.qol.autoInviteKeywords, "inv, +, invite, 123")
    for kw in rawKeywords:gmatch("([^,]+)") do
        local clean = strtrim(kw):lower()
        if clean ~= "" and text == clean then
            return true
        end
    end
    return false
end

local function HandlePotentialInviteRequest(msg, sender)
    if ns.IsSecret(msg) or ns.IsSecret(sender) then return end
    if not MatchesInviteKeyword(msg) then return end

    local short = ns.ShortName(sender)
    if short == "" or short == "Unbekannt" or short:lower() == ns.GetPlayerShortName():lower() then return end

    if ns.db and ns.db.qol and ns.db.qol.autoInviteFriendsOnly then
        if not ns.IsSquadOrFriend(sender) then
            return
        end
    end

    if SafeInvite(short, false) then
        ns.Print("Auto-Invite ausgelöst für: |cff34d399" .. short .. "|r")
    end
end

-- -------------------------------------------------------------------------
-- Instance Lockout Tracker (5 Instances per Hour)
-- -------------------------------------------------------------------------
function QoL:PruneInstanceHistory()
    if not ns.db then return end
    ns.db.instanceHistory = ns.db.instanceHistory or {}
    local now = time()
    for i = #ns.db.instanceHistory, 1, -1 do
        local entry = ns.db.instanceHistory[i]
        local ts = type(entry) == "table" and entry.ts or tonumber(entry) or 0
        if (now - ts) > 3600 then
            table.remove(ns.db.instanceHistory, i)
        end
    end
end

function QoL:GetActiveLockoutCount()
    if not ns.db then return 0, nil end
    self:PruneInstanceHistory()
    local list = ns.db.instanceHistory or {}
    local oldest = nil
    for _, entry in ipairs(list) do
        local ts = type(entry) == "table" and entry.ts or tonumber(entry)
        if ts and (not oldest or ts < oldest) then
            oldest = ts
        end
    end
    local nextFreeIn = oldest and math.max(0, 3600 - (time() - oldest)) or nil
    return #list, nextFreeIn
end

local function CheckInstanceEntry()
    if not ns.db or not ns.db.qol or not ns.db.qol.trackInstanceLockouts then return end
    if not IsInInstance then return end
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        local instName = ns.SafeString(GetInstanceInfo and select(1, GetInstanceInfo()), "Instanz")
        if instName ~= lastInstanceName then
            lastInstanceName = instName
            QoL:PruneInstanceHistory()
            local now = time()
            local list = ns.db.instanceHistory
            local lastEntry = list[#list]
            if not lastEntry or (now - (lastEntry.ts or 0)) > 45 or lastEntry.name ~= instName then
                list[#list + 1] = { name = instName, ts = now }
                local count = #list
                ns.Print(string.format("Instanz betreten: |cffffd100%s|r — Lockout-Zähler: |cff38bdf8%d/5|r in den letzten 60 Min.", instName, count))
            end
        end
    else
        lastInstanceName = nil
    end
end

-- -------------------------------------------------------------------------
-- Smart Group Buff & Ready Check
-- -------------------------------------------------------------------------
function QoL:RunBuffCheck()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end

    local classPresent = {}
    local memberBuffs = {}

    for _, unit in ipairs(units) do
        if UnitExists and UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            local name = ns.GetUnitName(unit) or ns.SafeString(UnitName(unit), unit)
            local _, classFile = UnitClass(unit)
            classFile = ns.SafeString(classFile, "")
            classPresent[classFile] = true

            local buffs = {}
            for b = 1, 40 do
                local auraName = nil
                if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
                    local aura = C_UnitAuras.GetBuffDataByIndex(unit, b)
                    if aura and not ns.IsSecret(aura) then
                        auraName = ns.SafeString(aura.name, nil)
                    end
                elseif UnitBuff then
                    auraName = ns.SafeString(UnitBuff(unit, b), nil)
                end
                if not auraName or auraName == "" then break end
                buffs[auraName:lower()] = true
            end
            memberBuffs[#memberBuffs + 1] = {
                name = name,
                class = classFile,
                buffs = buffs,
            }
        end
    end

    local missingReport = {}
    local function hasAny(bTable, patterns)
        for auraName in pairs(bTable) do
            for _, pat in ipairs(patterns) do
                if auraName:find(pat, 1, true) then return true end
            end
        end
        return false
    end

    for _, m in ipairs(memberBuffs) do
        local missing = {}
        if classPresent["PRIEST"] and not hasAny(m.buffs, { "seelenstärke", "fortitude" }) then
            missing[#missing + 1] = "Ausdauer"
        end
        if classPresent["MAGE"] and not hasAny(m.buffs, { "intelligenz", "intellect", "brillanz", "brilliance" }) then
            if m.class ~= "WARRIOR" and m.class ~= "ROGUE" then
                missing[#missing + 1] = "Intelligenz"
            end
        end
        if classPresent["DRUID"] and not hasAny(m.buffs, { "wildnis", "wild" }) then
            missing[#missing + 1] = "MdW"
        end
        if classPresent["PALADIN"] and not hasAny(m.buffs, { "segen", "blessing" }) then
            missing[#missing + 1] = "Segen"
        end

        if #missing > 0 then
            missingReport[#missingReport + 1] = string.format("%s: fehlt %s", ns.ColorByClass(m.name, m.class), table.concat(missing, ", "))
        end
    end

    if #missingReport == 0 then
        ns.Print("|cff34d399Buff-Check:|r Alle Gruppenmitglieder sind vollständig gebufft!")
    else
        ns.Print("|cfffbbf24Buff-Check — Fehlende Gruppenbuffs:|r")
        for _, line in ipairs(missingReport) do
            print("  - " .. line)
        end
    end
end

-- -------------------------------------------------------------------------
-- Movable & Scalable Floating Squad HUD Widget
-- -------------------------------------------------------------------------
local function StartHudDrag()
    if hudFrame and not (ns.db and ns.db.ui and ns.db.ui.hud and ns.db.ui.hud.locked) then
        hudFrame:StartMoving()
    end
end

local function StopHudDrag()
    if not hudFrame then return end
    hudFrame:StopMovingOrSizing()
    if ns.db and ns.db.ui and ns.db.ui.hud then
        local p, _, rp, x, y = hudFrame:GetPoint()
        ns.db.ui.hud.point = p
        ns.db.ui.hud.relPoint = rp
        ns.db.ui.hud.x = x
        ns.db.ui.hud.y = y
    end
end

local function EnsureHUDFrame()
    if hudFrame then return hudFrame end
    local cfg = (ns.db and ns.db.ui and ns.db.ui.hud) or ns.DEFAULTS.ui.hud

    hudFrame = CreateFrame("Frame", "ForeverFriendsHUD", UIParent, "BackdropTemplate")
    hudFrame:SetSize(220, 120)
    hudFrame:SetPoint(cfg.point or "TOPLEFT", UIParent, cfg.relPoint or "TOPLEFT", cfg.x or 24, cfg.y or -140)
    hudFrame:SetScale(cfg.scale or 1.0)
    hudFrame:SetAlpha(cfg.alpha or 0.90)
    hudFrame:SetClampedToScreen(true)
    hudFrame:SetMovable(true)
    hudFrame:EnableMouse(true)
    hudFrame:RegisterForDrag("LeftButton")

    hudFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    hudFrame:SetBackdropColor(0.06, 0.07, 0.09, 0.92)
    hudFrame:SetBackdropBorderColor(0.20, 0.23, 0.29, 1.0)

    local header = CreateFrame("Frame", nil, hudFrame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(22)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", StartHudDrag)
    header:SetScript("OnDragStop", StopHudDrag)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    header:SetBackdropColor(0.04, 0.05, 0.07, 0.98)
    hudFrame.header = header

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", header, "LEFT", 8, 0)
    title:SetText("|cff38bdf8Squad Radar|r")
    hudFrame.title = title

    local loText = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    loText:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    hudFrame.loText = loText

    hudFrame:SetScript("OnDragStart", StartHudDrag)
    hudFrame:SetScript("OnDragStop", StopHudDrag)

    hudFrame.rows = {}
    return hudFrame
end

function QoL:UpdateHUD()
    if not ns.db or not ns.db.ui or not ns.db.ui.hud then return end
    local cfg = ns.db.ui.hud
    if not cfg.enabled then
        if hudFrame then hudFrame:Hide() end
        return
    end

    local frame = EnsureHUDFrame()
    frame:SetScale(ns.SafeNumber(cfg.scale, 1.0))
    frame:SetAlpha(ns.SafeNumber(cfg.alpha, 0.90))

    local theme = ns.GetActiveTheme and ns.GetActiveTheme() or ns.THEMES.OBSIDIAN
    frame:SetBackdropBorderColor(theme.border[1], theme.border[2], theme.border[3], 1.0)
    frame.title:SetText("|cff" .. theme.accentHex .. "Squad Radar|r")

    local myLockouts = self:GetActiveLockoutCount()
    if cfg.showLockouts then
        frame.loText:SetText(string.format("|cff94a3b8IDs: %d/5|r", myLockouts))
    else
        frame.loText:SetText("")
    end

    local activePeers = {}
    local now = time()

    for _, peer in pairs(ns.onlinePeers or {}) do
        local pShort = ns.ShortName(peer.shortName or peer.name or "")
        if pShort ~= "" and pShort ~= "Unbekannt" and not ns.IsSelfName(pShort) and (now - (peer.lastSeen or 0)) < 180 then
            activePeers[#activePeers + 1] = peer
        end
    end

    table.sort(activePeers, function(a, b)
        return (a.shortName or "") < (b.shortName or "")
    end)

    for _, row in ipairs(frame.rows) do
        row:Hide()
    end

    if #activePeers == 0 then
        if not cfg.showOutOfGroup then
            frame:Hide()
            return
        end
        local row = frame.rows[1]
        if not row then
            row = CreateFrame("Button", nil, frame)
            row:SetSize(204, 28)
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", StartHudDrag)
            row:SetScript("OnDragStop", StopHudDrag)
            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", 6, 0)
            row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.zoneText:SetPoint("RIGHT", -6, 0)
            frame.rows[1] = row
        end
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -26)
        row.nameText:SetText("|cff64748bWarte auf Freunde...|r")
        row.zoneText:SetText("")
        if row.hpBar then row.hpBar:Hide() end
        if row.hpBg then row.hpBg:Hide() end
        row:Show()
        frame:SetHeight(58)
        frame:Show()
        return
    end

    local yOffset = -26
    for i, peer in ipairs(activePeers) do
        if i > 6 then break end
        local row = frame.rows[i]
        if not row then
            row = CreateFrame("Button", nil, frame)
            row:SetSize(204, 30)
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", StartHudDrag)
            row:SetScript("OnDragStop", StopHudDrag)

            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameText:SetPoint("TOPLEFT", 4, -2)
            row.nameText = nameText

            local zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            zoneText:SetPoint("TOPRIGHT", -4, -2)
            row.zoneText = zoneText

            local hpBg = row:CreateTexture(nil, "BACKGROUND")
            hpBg:SetPoint("BOTTOMLEFT", 4, 3)
            hpBg:SetPoint("BOTTOMRIGHT", -4, 3)
            hpBg:SetHeight(5)
            hpBg:SetColorTexture(0.14, 0.16, 0.20, 0.9)
            row.hpBg = hpBg

            local hpBar = CreateFrame("StatusBar", nil, row)
            hpBar:SetPoint("TOPLEFT", hpBg, "TOPLEFT", 0, 0)
            hpBar:SetPoint("BOTTOMRIGHT", hpBg, "BOTTOMRIGHT", 0, 0)
            hpBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            hpBar:SetMinMaxValues(0, 100)
            row.hpBar = hpBar

            row:SetScript("OnClick", function(self, btn)
                local p = self.peerData
                if not p then return end
                if btn == "RightButton" then
                    SafeInvite(p.shortName or p.name, false)
                else
                    ns.SetMapWaypoint(p.mapID, p.x, p.y, p.shortName or p.name)
                end
            end)

            frame.rows[i] = row
        end

        row.peerData = peer
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, yOffset)
        local pDisp = ns.FormatCharacterDisplay(peer.shortName or peer.name, peer.class, peer.faction, true)
        row.nameText:SetText(string.format("%s |cff94a3b8%d|r", pDisp, peer.level or 1))
        local z = ns.SafeString(peer.zone, "")
        if #z > 14 then z = z:sub(1, 12) .. "..." end
        row.zoneText:SetText("|cff94a3b8" .. z .. "|r")

        if row.hpBg then row.hpBg:Show() end
        if row.hpBar then
            local r, g, b = ns.GetClassColor(peer.class)
            row.hpBar:SetStatusBarColor(r, g, b, 0.9)
            row.hpBar:SetValue(ns.SafeNumber(peer.hpPct, 100))
            row.hpBar:Show()
        end

        row:Show()
        yOffset = yOffset - 32
    end

    frame:SetHeight(math.abs(yOffset) + 6)
    frame:Show()
end

-- -------------------------------------------------------------------------
-- Events
-- -------------------------------------------------------------------------
ns.RegisterMessage("PLAYER_READY", function()
    CheckInstanceEntry()
    QoL:UpdateHUD()
end)

ns.RegisterMessage("PEER_UPDATED", function()
    QoL:UpdateHUD()
end)

ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", CheckInstanceEntry)
ns.RegisterEvent("CHAT_MSG_WHISPER", function(_, msg, sender)
    HandlePotentialInviteRequest(msg, sender)
end)
ns.RegisterEvent("CHAT_MSG_GUILD", function(_, msg, sender)
    HandlePotentialInviteRequest(msg, sender)
end)
