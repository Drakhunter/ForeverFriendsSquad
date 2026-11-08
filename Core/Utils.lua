-- =========================================================================
-- Core/Utils.lua
-- Client 16001 Secret-Value guards, player identity helpers, currency/time
-- formatting, location queries, and map waypoint helpers.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

local issecretvalue = issecretvalue

-- -------------------------------------------------------------------------
-- Secret-Value Guards (Interface 16001 Best Practice)
-- -------------------------------------------------------------------------
function ns.IsSecret(val)
    return issecretvalue ~= nil and issecretvalue(val) == true
end

function ns.SafeString(val, fallback)
    if val == nil or ns.IsSecret(val) then
        return fallback or ""
    end
    local t = type(val)
    if t == "string" then
        return val
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    end
    return fallback or ""
end

function ns.SafeNumber(val, fallback)
    if val == nil or ns.IsSecret(val) then
        return fallback or 0
    end
    local n = tonumber(val)
    if not n or ns.IsSecret(n) then
        return fallback or 0
    end
    return n
end

function ns.SafeBoolean(val)
    if val == nil or ns.IsSecret(val) then
        return false
    end
    return val == true or val == 1
end

-- -------------------------------------------------------------------------
-- Table Utilities
-- -------------------------------------------------------------------------
function ns.MergeDefaults(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return target end
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            ns.MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

function ns.ShallowCopy(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end

-- -------------------------------------------------------------------------
-- Chat Output & Color Helpers
-- -------------------------------------------------------------------------
function ns.Colorize(hex, text)
    return "|cff" .. (hex or "ffffff") .. ns.SafeString(text, "") .. "|r"
end

function ns.GetClassColor(classFile)
    local key = ns.SafeString(classFile, ""):upper()
    if C_ClassColor and C_ClassColor.GetClassColor and key ~= "" then
        local c = C_ClassColor.GetClassColor(key)
        if c and c.GenerateHexColorMarkup then
            return c.r or 1, c.g or 1, c.b or 1, (c.GenerateHexColor and c:GenerateHexColor():sub(3) or "ffffff")
        end
    end
    local entry = ns.CLASS_COLORS and ns.CLASS_COLORS[key]
    if entry then
        return entry.r, entry.g, entry.b, entry.hex
    end
    return 0.85, 0.88, 0.92, "d9e0eb"
end

function ns.ColorByClass(text, classFile)
    local _, _, _, hex = ns.GetClassColor(classFile)
    return "|cff" .. hex .. ns.SafeString(text, "") .. "|r"
end

function ns.Print(msg, ...)
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, ns.SafeString(msg, ""), ...)
        if ok then msg = formatted end
    end
    local accentHex = (ns.GetActiveTheme and ns.GetActiveTheme().accentHex) or "38bdf8"
    print("|cff" .. accentHex .. "[ForeverFriends]|r " .. ns.SafeString(msg, ""))
end

-- -------------------------------------------------------------------------
-- Player & Character Identity Helpers (WoW: Forever Vorname + Nachname Support)
-- -------------------------------------------------------------------------
function ns.ShortName(fullName)
    local s = strtrim(ns.SafeString(fullName, ""))
    if s == "" then return "Unbekannt" end
    if Ambiguate then
        local ok, amb = pcall(Ambiguate, s, "none")
        if ok and amb and not ns.IsSecret(amb) and type(amb) == "string" and amb ~= "" then
            s = strtrim(amb)
        end
    end
    return strtrim(s:match("^([^%-]+)") or s)
end

function ns.GetUnitName(unit)
    unit = unit or "player"
    if not UnitName then return nil end
    local ok, first, second = pcall(UnitName, unit)
    if not ok or not first or ns.IsSecret(first) then return nil end
    local name = strtrim(ns.SafeString(first, ""))
    if name == "" then return nil end

    -- In WoW: Forever (16001), UnitName returns (firstName, surname) for units!
    if second and not ns.IsSecret(second) and type(second) == "string" then
        local surname = strtrim(second)
        local rawRealm = strtrim(ns.SafeString(GetRealmName and GetRealmName(), ""))
        local normRealm = ns.SafeString(GetNormalizedRealmName and GetNormalizedRealmName(), "")
        if surname ~= "" and surname ~= rawRealm and surname ~= normRealm then
            local suffix = " " .. surname:lower()
            if name:sub(-#suffix):lower() ~= suffix then
                name = name .. " " .. surname
            end
        end
    end

    -- Fallback for "player": check PlayerFrame.name / PlayerName if UnitName only returned first name
    if unit == "player" and not name:find(" ", 1, true) then
        if ns._learnedSelfFullName and ns._learnedSelfFullName:lower():find("^" .. name:lower() .. "%s+") then
            return ns._learnedSelfFullName
        end
        local pfText = (PlayerFrame and PlayerFrame.name and PlayerFrame.name.GetText and PlayerFrame.name:GetText())
            or (_G.PlayerName and _G.PlayerName.GetText and _G.PlayerName:GetText())
        if pfText and not ns.IsSecret(pfText) and type(pfText) == "string" then
            pfText = strtrim(pfText)
            if pfText:find(" ", 1, true) and pfText:lower():find("^" .. name:lower() .. "%s+") then
                ns._learnedSelfFullName = pfText
                return pfText
            end
        end
    elseif unit == "player" and name:find(" ", 1, true) then
        ns._learnedSelfFullName = name
    end

    return name
end

function ns.LearnSelfFullName(candidate)
    local short = ns.ShortName(candidate)
    if short == "" or short == "Unbekannt" or not short:find(" ", 1, true) then return end
    local first = ns.GetPlayerFirstName()
    if first ~= "" and short:lower():find("^" .. first:lower() .. "%s+") then
        ns._learnedSelfFullName = short
    end
end

function ns.GetPlayerShortName()
    return ns.GetUnitName("player") or "Player"
end

function ns.GetPlayerFirstName()
    if UnitName then
        local ok, first = pcall(UnitName, "player")
        if ok and first and not ns.IsSecret(first) then
            local s = strtrim(ns.SafeString(first, ""))
            return s:match("^(%S+)") or s
        end
    end
    return ""
end

function ns.IsSelfName(nameOrKey)
    local short = ns.ShortName(nameOrKey)
    if short == "" or short == "Unbekannt" then return false end
    local lower = short:lower()

    local myFull = ns.GetPlayerShortName():lower()
    if myFull ~= "" and myFull ~= "player" and lower == myFull then
        return true
    end

    local myFirst = ns.GetPlayerFirstName():lower()
    if myFirst ~= "" and myFirst ~= "player" then
        -- Match old 1-word self entries (e.g. "Apperah" when player is "Apperah II")
        if lower == myFirst then
            return true
        end
    end
    return false
end

function ns.GetPlayerRealm()
    local realm = ns.SafeString(GetNormalizedRealmName and GetNormalizedRealmName() or (GetRealmName and GetRealmName()), "")
    realm = realm:gsub("%s+", "")
    return realm
end

function ns.GetPlayerKey()
    local name = ns.GetPlayerShortName()
    local realm = ns.GetPlayerRealm()
    if realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

function ns.NormalizeCharKey(nameOrKey)
    local s = strtrim(ns.SafeString(nameOrKey, ""))
    if s == "" then return "" end
    if s:find("-", 1, true) then
        local n, r = s:match("^([^%-]+)%-(.+)$")
        if n and r then
            return strtrim(n) .. "-" .. r:gsub("%s+", "")
        end
        return s
    end
    local realm = ns.GetPlayerRealm()
    if realm ~= "" then
        return s .. "-" .. realm
    end
    return s
end

function ns.GetPlayerClass()
    if UnitClass then
        local _, classFile = UnitClass("player")
        return ns.SafeString(classFile, "WARRIOR")
    end
    return "WARRIOR"
end

function ns.GetPlayerLevel()
    if UnitLevel then
        return ns.SafeNumber(UnitLevel("player"), 1)
    end
    return 1
end

function ns.NormalizeFaction(f)
    local s = strtrim(ns.SafeString(f, "")):lower()
    if s == "horde" or s == "h" then
        return "Horde"
    elseif s == "alliance" or s == "allianz" or s == "a" then
        return "Alliance"
    end
    return "Neutral"
end

function ns.GetPlayerFaction()
    if UnitFactionGroup then
        local ok, eng = pcall(UnitFactionGroup, "player")
        if ok and eng and not ns.IsSecret(eng) then
            return ns.NormalizeFaction(eng)
        end
    end
    return "Neutral"
end

function ns.GetFactionBadge(faction)
    local f = ns.NormalizeFaction(faction)
    if f == "Horde" then
        return "|cfff87171[H]|r"
    elseif f == "Alliance" then
        return "|cff60a5fa[A]|r"
    end
    return "|cff94a3b8[N]|r"
end

function ns.GetFactionLabel(faction)
    local f = ns.NormalizeFaction(faction)
    if f == "Horde" then
        return "|cfff87171Horde|r"
    elseif f == "Alliance" then
        return "|cff60a5faAllianz|r"
    end
    return "|cff94a3b8Neutral|r"
end

function ns.FormatCharacterDisplay(name, classFile, faction, includeFactionBadge)
    local coloredName = ns.ColorByClass(ns.SafeString(name, "Unbekannt"), classFile)
    if includeFactionBadge == false then
        return coloredName
    end
    local f = ns.NormalizeFaction(faction)
    if f == "Horde" or f == "Alliance" then
        return ns.GetFactionBadge(f) .. " " .. coloredName
    end
    return coloredName
end

-- -------------------------------------------------------------------------
-- Global Faction & Character Filter Engine (Works Across All Hub Tabs)
-- -------------------------------------------------------------------------
ns.globalFilter = {
    faction = "ALL", -- "ALL", "Horde", "Alliance", "SELF_FACTION"
    char    = "ALL", -- "ALL", "SELF_ACTIVE", "SELF_ALL", "FRIENDS_ALL", or "CHAR:<shortLower>"
}

function ns.GetGlobalFilter()
    if ns.db and ns.db.ui then
        ns.globalFilter.faction = ns.db.ui.filterFaction or ns.globalFilter.faction or "ALL"
        ns.globalFilter.char    = ns.db.ui.filterChar or ns.globalFilter.char or "ALL"
    end
    return ns.globalFilter
end

function ns.SetGlobalFilter(factionFilter, charFilter)
    if factionFilter ~= nil then
        ns.globalFilter.faction = factionFilter
        if ns.db and ns.db.ui then ns.db.ui.filterFaction = factionFilter end
    end
    if charFilter ~= nil then
        ns.globalFilter.char = charFilter
        if ns.db and ns.db.ui then ns.db.ui.filterChar = charFilter end
    end
    if ns.SendMessage then
        ns.SendMessage("GLOBAL_FILTER_CHANGED", ns.globalFilter.faction, ns.globalFilter.char)
    end
end

function ns.ResolveCharacterFaction(shortOrKey, explicitFaction)
    local norm = ns.NormalizeFaction(explicitFaction)
    if norm == "Horde" or norm == "Alliance" then
        return norm
    end
    local short = ns.ShortName(shortOrKey)
    if ns.IsSelfName(short) then
        return ns.GetPlayerFaction()
    end
    local lower = short:lower()
    if ns.db then
        for _, c in pairs(ns.db.characters or {}) do
            if ns.ShortName(c.name or c.key):lower() == lower then
                local cf = ns.NormalizeFaction(c.faction)
                if cf ~= "Neutral" then return cf end
            end
        end
        for _, c in pairs(ns.db.squadCharacters or {}) do
            if ns.ShortName(c.name or c.key):lower() == lower then
                local cf = ns.NormalizeFaction(c.faction)
                if cf ~= "Neutral" then return cf end
            end
        end
    end
    for _, p in pairs(ns.onlinePeers or {}) do
        if ns.ShortName(p.shortName or p.name):lower() == lower then
            local pf = ns.NormalizeFaction(p.faction)
            if pf ~= "Neutral" then return pf end
        end
    end
    return ns.GetPlayerFaction()
end

function ns.MatchesGlobalFilter(charRecOrName, explicitIsOwn, explicitFaction)
    local gf = ns.GetGlobalFilter()
    local fFilter = gf.faction or "ALL"
    local cFilter = gf.char or "ALL"

    local name, key, faction, isOwn
    if type(charRecOrName) == "table" then
        name = charRecOrName.shortName or charRecOrName.name or ns.ShortName(charRecOrName.key)
        key = charRecOrName.key or name
        faction = charRecOrName.faction or explicitFaction
        if explicitIsOwn ~= nil then
            isOwn = explicitIsOwn
        elseif charRecOrName.isOwn ~= nil then
            isOwn = charRecOrName.isOwn
        elseif charRecOrName.isMe ~= nil then
            isOwn = charRecOrName.isMe
        else
            local myChars = ns.db and ns.db.characters or {}
            isOwn = (key and myChars[key] ~= nil) or ns.IsSelfName(name)
        end
    else
        name = ns.ShortName(charRecOrName)
        key = ns.NormalizeCharKey(charRecOrName)
        faction = explicitFaction
        if explicitIsOwn ~= nil then
            isOwn = explicitIsOwn
        else
            local myChars = ns.db and ns.db.characters or {}
            isOwn = (myChars[key] ~= nil) or ns.IsSelfName(name)
        end
    end

    local short = ns.ShortName(name)
    local lower = short:lower()
    local resolvedFaction = ns.ResolveCharacterFaction(short, faction)

    -- 1. Check Faction Filter
    if fFilter == "Horde" and resolvedFaction ~= "Horde" then
        return false
    elseif fFilter == "Alliance" and resolvedFaction ~= "Alliance" then
        return false
    elseif (fFilter == "OWN" or fFilter == "SELF_FACTION") and resolvedFaction ~= ns.GetPlayerFaction() then
        return false
    end

    -- 2. Check Character Filter
    if cFilter == "ALL" or cFilter == "" then
        return true
    elseif cFilter == "ACTIVE" or cFilter == "SELF_ACTIVE" then
        return ns.IsSelfName(short)
    elseif cFilter == "OWN_CHARS" or cFilter == "SELF_ALL" then
        return isOwn == true
    elseif cFilter == "FRIENDS_ONLY" or cFilter == "FRIENDS_ALL" then
        return not isOwn and not ns.IsSelfName(short)
    elseif cFilter:sub(1, 5) == "CHAR:" then
        local targetLower = cFilter:sub(6):lower()
        return lower == targetLower
    end

    return true
end

function ns.GetAllKnownCharacters(respectFactionFilter)
    local gf = ns.GetGlobalFilter()
    local fFilter = gf.faction or "ALL"
    local list = {}
    local byLower = {}

    local function upsert(short, classFile, level, faction, isOwn)
        short = ns.ShortName(short)
        if short == "" or short == "Unbekannt" then return end
        local lower = short:lower()
        local resolvedFaction = ns.ResolveCharacterFaction(short, faction)

        if respectFactionFilter then
            if fFilter == "Horde" and resolvedFaction ~= "Horde" then return end
            if fFilter == "Alliance" and resolvedFaction ~= "Alliance" then return end
            if (fFilter == "OWN" or fFilter == "SELF_FACTION") and resolvedFaction ~= ns.GetPlayerFaction() then return end
        end

        local existing = byLower[lower]
        if not existing then
            existing = {
                name = short,
                shortName = short,
                lower = lower,
                class = classFile or "WARRIOR",
                level = ns.SafeNumber(level, 0),
                faction = resolvedFaction,
                isOwn = isOwn == true,
                isActiveSelf = ns.IsSelfName(short),
            }
            byLower[lower] = existing
            list[#list + 1] = existing
        else
            if isOwn then existing.isOwn = true end
            if ns.IsSelfName(short) then existing.isActiveSelf = true end
            if classFile and classFile ~= "" and existing.class == "PRIEST" then
                existing.class = classFile
            end
            if ns.SafeNumber(level, 0) > (existing.level or 0) then
                existing.level = ns.SafeNumber(level, 0)
            end
            if resolvedFaction ~= "Neutral" then
                existing.faction = resolvedFaction
            end
        end
    end

    -- 1. Active character
    upsert(ns.GetPlayerShortName(), ns.GetPlayerClass(), ns.GetPlayerLevel(), ns.GetPlayerFaction(), true)

    -- 2. Own Twinks from SavedVariables
    for key, rec in pairs(ns.db and ns.db.characters or {}) do
        if type(rec) == "table" then
            upsert(rec.name or key, rec.class, rec.level, rec.faction, true)
        end
    end

    -- 3. Synced Friend Characters
    for key, rec in pairs(ns.db and ns.db.squadCharacters or {}) do
        if type(rec) == "table" and not ns.IsSelfName(rec.name or key) then
            upsert(rec.name or key, rec.class, rec.level, rec.faction, false)
        end
    end

    -- 4. Online Peers
    for key, peer in pairs(ns.onlinePeers or {}) do
        if type(peer) == "table" and not ns.IsSelfName(peer.shortName or peer.name or key) then
            upsert(peer.shortName or peer.name or key, peer.class, peer.level, peer.faction, false)
        end
    end

    -- 5. Manual Squad Roster
    for rosterName, info in pairs(ns.db and ns.db.squadRoster or {}) do
        if not ns.IsSelfName(rosterName) then
            upsert(rosterName, info and info.class or "PRIEST", info and info.level or 0, info and info.faction, false)
        end
    end

    table.sort(list, function(a, b)
        if a.isActiveSelf ~= b.isActiveSelf then return a.isActiveSelf end
        if a.isOwn ~= b.isOwn then return a.isOwn end
        return a.shortName < b.shortName
    end)

    return list, byLower
end

-- -------------------------------------------------------------------------
-- Currency & Time Formatting
-- -------------------------------------------------------------------------
function ns.FormatMoney(copper, compact)
    copper = math.max(0, math.floor(ns.SafeNumber(copper, 0)))
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = copper % 100

    if compact then
        if gold >= 1000 then
            return string.format("|cffffd700%.1fk g|r", gold / 1000)
        elseif gold > 0 then
            return string.format("|cffffd700%dg|r |cffc7c7cf%ds|r", gold, silver)
        elseif silver > 0 then
            return string.format("|cffc7c7cf%ds|r |cffeda55f%dc|r", silver, cop)
        else
            return string.format("|cffeda55f%dc|r", cop)
        end
    end

    local parts = {}
    if gold > 0 then
        parts[#parts + 1] = string.format("|cffffd700%dg|r", gold)
    end
    if silver > 0 or gold > 0 then
        parts[#parts + 1] = string.format("|cffc7c7cf%02ds|r", silver)
    end
    parts[#parts + 1] = string.format("|cffeda55f%02dc|r", cop)
    return table.concat(parts, " ")
end

function ns.FormatTimeAgo(timestamp)
    local ts = ns.SafeNumber(timestamp, 0)
    if ts <= 0 then return "Nie" end
    local diff = math.max(0, time() - ts)
    if diff < 15 then
        return "|cff34d399Live|r"
    elseif diff < 60 then
        return string.format("vor %ds", diff)
    elseif diff < 3600 then
        return string.format("vor %dm", math.floor(diff / 60))
    elseif diff < 86400 then
        return string.format("vor %dh", math.floor(diff / 3600))
    else
        return string.format("vor %dd", math.floor(diff / 86400))
    end
end

-- -------------------------------------------------------------------------
-- Location & Map Waypoint Helpers
-- -------------------------------------------------------------------------
function ns.GetPlayerLocationData()
    local zone = ns.SafeString(GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText()), "Unbekannt")
    local subzone = ns.SafeString(GetSubZoneText and GetSubZoneText(), "")
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    mapID = ns.SafeNumber(mapID, 0)
    local x, y = 0, 0

    if mapID > 0 and C_Map and C_Map.GetPlayerMapPosition then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if ok and pos and pos.GetXY then
            local px, py = pos:GetXY()
            if px and py and not ns.IsSecret(px) and not ns.IsSecret(py) then
                x = tonumber(px) or 0
                y = tonumber(py) or 0
            end
        end
    end

    return zone, subzone, mapID, x, y
end

function ns.SetMapWaypoint(mapID, x, y, label)
    mapID = ns.SafeNumber(mapID, 0)
    x = ns.SafeNumber(x, 0)
    y = ns.SafeNumber(y, 0)
    if x > 1 or y > 1 then
        x = x / 100
        y = y / 100
    end

    if mapID <= 0 or x <= 0 or y <= 0 then
        ns.Print("Keine gültigen Kartenkoordinaten für diesen Punkt verfügbar.")
        return false
    end

    if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
        C_Map.SetUserWaypoint(point)
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        ns.Print(string.format("Karten-Wegpunkt gesetzt: |cffffd100%s|r (%.1f, %.1f)", ns.SafeString(label, "Freund"), x * 100, y * 100))
        return true
    else
        ns.Print(string.format("Ziel: |cffffd100%s|r — Koordinaten: %.1f, %.1f (Wegpunkt in Instanz nicht setzbar)", ns.SafeString(label, "Freund"), x * 100, y * 100))
        return false
    end
end

-- -------------------------------------------------------------------------
-- Squad Trust / Friend Verification & Relationship Classification
-- Distinguishes between:
-- 1) Explicit Squad Roster ("SQUAD")
-- 2) WoW / Battle.net Friend List ("FRIEND")
-- 3) Guild Sync Peer ("GUILD")
-- 4) Temporary Party/Raid Member ("GROUP_ONLY")
-- -------------------------------------------------------------------------
ns.dismissedPeers = {} -- [lowerShortName] = true (prevents removed group members from re-appearing in the same session)

function ns.IsDismissedPeer(name)
    local short = ns.ShortName(name)
    if short == "" then return false end
    return ns.dismissedPeers[short:lower()] == true
end

function ns.IsInSquadRoster(name)
    if not ns.db or not ns.db.squadRoster then return false end
    local short = ns.ShortName(name)
    local lower = short:lower()
    if short == "" then return false end
    for k in pairs(ns.db.squadRoster) do
        if ns.ShortName(k):lower() == lower then
            return true
        end
    end
    return false
end

function ns.IsOnWoWFriendList(name)
    local short = ns.ShortName(name)
    local lower = short:lower()
    if lower == "" then return false end

    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        local ok, numFriends = pcall(C_FriendList.GetNumFriends)
        numFriends = ok and ns.SafeNumber(numFriends, 0) or 0
        for i = 1, numFriends do
            local okInfo, info = pcall(C_FriendList.GetFriendInfoByIndex, i)
            if okInfo and info and not ns.IsSecret(info) and info.name and not ns.IsSecret(info.name) then
                if ns.ShortName(info.name):lower() == lower then
                    return true
                end
            end
        end
    end

    if C_BattleNet and C_BattleNet.GetNumFriends and C_BattleNet.GetFriendAccountInfo then
        local ok, numBNet = pcall(C_BattleNet.GetNumFriends)
        numBNet = ok and ns.SafeNumber(numBNet, 0) or 0
        for i = 1, numBNet do
            local okAcc, acc = pcall(C_BattleNet.GetFriendAccountInfo, i)
            if okAcc and acc and not ns.IsSecret(acc) and acc.gameAccountInfo and not ns.IsSecret(acc.gameAccountInfo) then
                local charName = ns.SafeString(acc.gameAccountInfo.characterName, "")
                if charName ~= "" and ns.ShortName(charName):lower() == lower then
                    return true
                end
            end
        end
    end

    return false
end

function ns.GetPeerRelationship(name, peerData)
    local short = ns.ShortName(name)
    local inSquad = ns.IsInSquadRoster(short)
    local isWoWFriend = ns.IsOnWoWFriendList(short)
    local inGroup = (UnitInParty and UnitInParty(short)) or (UnitInRaid and UnitInRaid(short)) or false

    if inSquad then
        return "SQUAD", "|cff34d399[Stammgruppe]|r", true, inGroup
    elseif isWoWFriend then
        return "FRIEND", "|cff38bdf8[Freund]|r", true, inGroup
    elseif inGroup or (peerData and peerData.localGroupOnly) then
        return "GROUP_ONLY", "|cfffbbf24[Nur Gruppe]|r", false, true
    elseif peerData and peerData.distribution == "GUILD" then
        return "GUILD", "|cff94a3b8[Gilde]|r", false, false
    end
    return "OTHER", "|cff94a3b8[Sync]|r", false, inGroup
end

function ns.IsSquadOrFriend(sender)
    local short = ns.ShortName(sender)
    if short == ns.GetPlayerShortName() then return true end
    if ns.IsDismissedPeer(short) then return false end

    if ns.IsInSquadRoster(short) or ns.IsOnWoWFriendList(short) then
        return true
    end

    if UnitInParty and UnitInParty(short) then return true end
    if UnitInRaid and UnitInRaid(short) then return true end

    if not (ns.db and ns.db.sync and ns.db.sync.onlyTrustedRoster) then
        return true
    end

    return false
end

function ns.AddToSquadRoster(name, note)
    if not ns.db then return end
    local short = ns.ShortName(strtrim(ns.SafeString(name, "")))
    if short == "" then return false end
    local lower = short:lower()
    ns.dismissedPeers[lower] = nil
    ns.db.squadRoster = ns.db.squadRoster or {}

    -- Clean up any duplicate case-variant key first
    for k in pairs(ns.db.squadRoster) do
        if ns.ShortName(k):lower() == lower and k ~= short then
            ns.db.squadRoster[k] = nil
        end
    end

    ns.db.squadRoster[short] = {
        name = short,
        note = ns.SafeString(note, ""),
        trusted = true,
        addedAt = time(),
    }

    -- If this peer is already in onlinePeers, mark them as permanent (not localGroupOnly)
    for _, peer in pairs(ns.onlinePeers or {}) do
        if ns.ShortName(peer.shortName or peer.name):lower() == lower then
            peer.localGroupOnly = nil
        end
    end

    ns.Print("Zur Stammgruppe hinzugefügt: |cff34d399" .. short .. "|r")
    if ns.SendMessage then
        ns.SendMessage("ROSTER_UPDATED")
        ns.SendMessage("PEER_UPDATED")
    end
    return true
end

function ns.RemoveFromSquadRoster(name)
    if not ns.db then return end
    local short = ns.ShortName(strtrim(ns.SafeString(name, "")))
    if short == "" then return end
    local lower = short:lower()

    -- Remember dismissal for the current session so random party members don't immediately re-appear
    ns.dismissedPeers[lower] = true

    -- 1. Remove from squadRoster (case-insensitive)
    if ns.db.squadRoster then
        for k in pairs(ns.db.squadRoster) do
            if ns.ShortName(k):lower() == lower or k:lower() == lower then
                ns.db.squadRoster[k] = nil
            end
        end
    end

    -- 2. Remove from live onlinePeers radar table
    for k, peer in pairs(ns.onlinePeers or {}) do
        local pShort = ns.ShortName(peer.shortName or peer.name or k):lower()
        if pShort == lower or k:lower() == lower then
            ns.onlinePeers[k] = nil
        end
    end

    -- 3. Remove from cached squadCharacters database (Inventory, Professions, Quests, Stats)
    if ns.db.squadCharacters then
        for k, rec in pairs(ns.db.squadCharacters) do
            local rShort = ns.ShortName(rec.name or k):lower()
            if rShort == lower or k:lower() == lower then
                ns.db.squadCharacters[k] = nil
            end
        end
    end

    ns.Print("Aus Liste & Datenbank entfernt: |cfff87171" .. short .. "|r")
    if ns.SendMessage then
        ns.SendMessage("ROSTER_UPDATED")
        ns.SendMessage("PEER_UPDATED")
        ns.SendMessage("INVENTORY_UPDATED")
        ns.SendMessage("QUESTS_UPDATED")
        ns.SendMessage("STATS_UPDATED")
    end
end
