-- =========================================================================
-- Core/Init.lua
-- Event bus, Ace3 / LibSharedMedia / LibDBIcon bootstrap, SavedVariables
-- lifecycle, Minimap button, AddonCompartment hooks, and slash commands.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

-- -------------------------------------------------------------------------
-- Library References via LibStub
-- -------------------------------------------------------------------------
ns.Libs = {}
if LibStub then
    ns.Libs.AceTimer          = LibStub("AceTimer-3.0", true)
    ns.Libs.AceComm           = LibStub("AceComm-3.0", true)
    ns.Libs.AceSerializer     = LibStub("AceSerializer-3.0", true)
    ns.Libs.LSM               = LibStub("LibSharedMedia-3.0", true)
    ns.Libs.LDB               = LibStub("LibDataBroker-1.1", true)
    ns.Libs.LDBIcon           = LibStub("LibDBIcon-1.0", true)
    ns.Libs.LibDeflate        = LibStub("LibDeflate", true)
    ns.Libs.LibSerialize      = LibStub("LibSerialize", true)
    ns.Libs.AceGUI            = LibStub("AceGUI-3.0", true)
    ns.Libs.AceConfig         = LibStub("AceConfig-3.0", true)
    ns.Libs.AceConfigDialog   = LibStub("AceConfigDialog-3.0", true)
    ns.Libs.AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
end

if ns.Libs.AceTimer then
    ns.Libs.AceTimer:Embed(ns)
end

-- -------------------------------------------------------------------------
-- Event Dispatcher & Internal Message Bus
-- -------------------------------------------------------------------------
ns.eventFrame = CreateFrame("Frame")
ns.events = {}
ns.messages = {}
ns.onlinePeers = {} -- [charKey] = { name, shortName, class, level, zone, subzone, mapID, x, y, hpPct, manaPct, inCombat, lockouts, lastSeen, version }

local function Dispatch(handlers, ...)
    if not handlers then return end
    for i = 1, #handlers do
        local fn = handlers[i]
        if fn then
            xpcall(fn, CallErrorHandler, ...)
        end
    end
end

ns.eventFrame:SetScript("OnEvent", function(_, event, ...)
    Dispatch(ns.events[event], event, ...)
end)

function ns.RegisterEvent(event, handler)
    if not event or type(handler) ~= "function" then return end
    if not ns.events[event] then
        ns.events[event] = {}
        pcall(ns.eventFrame.RegisterEvent, ns.eventFrame, event)
    end
    local list = ns.events[event]
    for i = 1, #list do
        if list[i] == handler then return end
    end
    list[#list + 1] = handler
end

function ns.UnregisterEvent(event, handler)
    local list = ns.events[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then
            table.remove(list, i)
        end
    end
    if #list == 0 then
        ns.events[event] = nil
        pcall(ns.eventFrame.UnregisterEvent, ns.eventFrame, event)
    end
end

function ns.RegisterMessage(message, handler)
    if not message or type(handler) ~= "function" then return end
    ns.messages[message] = ns.messages[message] or {}
    local list = ns.messages[message]
    for i = 1, #list do
        if list[i] == handler then return end
    end
    list[#list + 1] = handler
end

function ns.SendMessage(message, ...)
    Dispatch(ns.messages[message], message, ...)
end

-- -------------------------------------------------------------------------
-- Local Character Record Initialization
-- -------------------------------------------------------------------------
function ns.EnsureCurrentCharacterRecord()
    if not ns.db then return nil end
    ns.db.characters = ns.db.characters or {}
    local key = ns.GetPlayerKey()
    local rec = ns.db.characters[key] or {}

    rec.key = key
    rec.name = ns.GetPlayerShortName()
    rec.realm = ns.GetPlayerRealm()
    rec.class = ns.GetPlayerClass()
    rec.level = ns.GetPlayerLevel()
    rec.faction = ns.GetPlayerFaction()
    rec.money = ns.SafeNumber(GetMoney and GetMoney(), rec.money or 0)
    rec.bags = rec.bags or {}
    rec.bank = rec.bank or {}
    rec.equip = rec.equip or {}
    rec.professions = rec.professions or {}
    rec.quests = rec.quests or {}
    rec.stats = rec.stats or {
        deaths = 0,
        repairCopper = 0,
        questsCompleted = 0,
        highRolls = 0,
        onesRolled = 0,
    }
    rec.updatedAt = time()

    ns.db.characters[key] = rec
    return rec
end

-- -------------------------------------------------------------------------
-- Minimap Button (LibDataBroker-1.1 + LibDBIcon-1.0)
-- -------------------------------------------------------------------------
local function SetupMinimapButton()
    if not ns.Libs.LDB then return end

    local ldbObj = ns.Libs.LDB:NewDataObject("ForeverFriends", {
        type = "data source",
        text = "ForeverFriends",
        icon = "Interface\\AddOns\\" .. addonName .. "\\Media\\logo",
        OnClick = function(_, button)
            if button == "RightButton" then
                if ns.OpenSettingsTab then
                    ns.OpenSettingsTab()
                elseif ns.ToggleMainFrame then
                    ns.ToggleMainFrame("SETTINGS")
                end
            elseif button == "MiddleButton" then
                if ns.InviteSquadMembers then
                    ns.InviteSquadMembers()
                end
            else
                if IsShiftKeyDown() then
                    if ns.Sync and ns.Sync.BroadcastFullState then
                        ns.Sync:BroadcastFullState(true)
                    end
                else
                    if ns.ToggleMainFrame then
                        ns.ToggleMainFrame()
                    end
                end
            end
        end,
        OnTooltipShow = function(tooltip)
            if not tooltip or not tooltip.AddLine then return end
            local theme = ns.GetActiveTheme and ns.GetActiveTheme() or ns.THEMES.OBSIDIAN
            tooltip:AddLine("|cff" .. theme.accentHex .. "ForeverFriends|r |cff94a3b8— Squad Hub|r")
            tooltip:AddLine(" ")

            local count = 0
            for _, peer in pairs(ns.onlinePeers or {}) do
                if (time() - (peer.lastSeen or 0)) < 180 then
                    count = count + 1
                    local nameStr = ns.ColorByClass(peer.shortName or peer.name, peer.class)
                    local zoneStr = ns.SafeString(peer.zone, "Unbekannt")
                    tooltip:AddDoubleLine(
                        string.format("%s |cff94a3b8(Lv %d)|r", nameStr, ns.SafeNumber(peer.level, 1)),
                        "|cffe2e8f0" .. zoneStr .. "|r"
                    )
                end
            end

            if count == 0 then
                tooltip:AddLine("|cff94a3b8Keine Freunde aktiv im Sync-Radar (Solo)|r")
            end

            tooltip:AddLine(" ")
            tooltip:AddDoubleLine("|cffffd100Linksklick:|r", "|cffffffffSquad Hub öffnen/schließen|r")
            tooltip:AddDoubleLine("|cffffd100Rechtsklick:|r", "|cffffffffEinstellungen öffnen|r")
            tooltip:AddDoubleLine("|cffffd100Mittelklick:|r", "|cffffffffStammgruppe einladen|r")
            tooltip:AddDoubleLine("|cffffd100Shift + Klick:|r", "|cffffffffSofort-Sync senden|r")
        end,
    })

    ns.ldbObject = ldbObj

    if ns.Libs.LDBIcon and ns.db and ns.db.ui and ns.db.ui.minimap then
        ns.Libs.LDBIcon:Register("ForeverFriends", ldbObj, ns.db.ui.minimap)
    end
end

function ns.UpdateMinimapButtonVisibility()
    if not ns.Libs.LDBIcon or not ns.db or not ns.db.ui or not ns.db.ui.minimap then return end
    if ns.db.ui.minimap.hide then
        ns.Libs.LDBIcon:Hide("ForeverFriends")
    else
        ns.Libs.LDBIcon:Show("ForeverFriends")
    end
end

-- -------------------------------------------------------------------------
-- Native Minimap Addon Compartment Callbacks (Interface 16001)
-- -------------------------------------------------------------------------
function ForeverFriends_OnAddonCompartmentClick(_, buttonName)
    if buttonName == "RightButton" then
        if ns.ToggleMainFrame then
            ns.ToggleMainFrame("SETTINGS")
        end
    else
        if ns.ToggleMainFrame then
            ns.ToggleMainFrame()
        end
    end
end

function ForeverFriends_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_LEFT")
    GameTooltip:SetText("ForeverFriends [Squad Hub]", 0.22, 0.74, 0.97)
    GameTooltip:AddLine("Linksklick: Squad Hub öffnen", 0.9, 0.9, 0.9)
    GameTooltip:AddLine("Rechtsklick: Einstellungen öffnen", 0.9, 0.9, 0.9)
    GameTooltip:Show()
end

function ForeverFriends_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-- -------------------------------------------------------------------------
-- ADDON_LOADED & PLAYER_ENTERING_WORLD Lifecycle
-- -------------------------------------------------------------------------
local function OnAddonLoaded(event, loadedAddon)
    if loadedAddon ~= addonName then return end
    ns.UnregisterEvent(event, OnAddonLoaded)

    ForeverFriendsDB = ForeverFriendsDB or {}
    ForeverFriendsCharDB = ForeverFriendsCharDB or {}

    ns.MergeDefaults(ForeverFriendsDB, ns.DEFAULTS)
    ns.db = ForeverFriendsDB
    ns.charDB = ForeverFriendsCharDB

    -- One-time migration: ensure Auto-Invite via chat keyword is disabled by default
    if ns.db.qol and not ns.db.qol.migratedAutoInviteDefaultOff then
        ns.db.qol.autoInviteEnabled = false
        ns.db.qol.migratedAutoInviteDefaultOff = true
    end

    SetupMinimapButton()
    ns.SendMessage("ADDON_INITIALIZED")
end

ns.RegisterEvent("ADDON_LOADED", OnAddonLoaded)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
    if not ns.db then return end
    ns.EnsureCurrentCharacterRecord()
    ns.SendMessage("PLAYER_READY")
end)

-- -------------------------------------------------------------------------
-- Slash Commands (/ff, /squad, /foreverfriends)
-- -------------------------------------------------------------------------
SLASH_FOREVERFRIENDS1 = "/ff"
SLASH_FOREVERFRIENDS2 = "/squad"
SLASH_FOREVERFRIENDS3 = "/foreverfriends"

SlashCmdList["FOREVERFRIENDS"] = function(msg)
    local raw = strtrim(ns.SafeString(msg, ""))
    local cmd, rest = raw:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "open" or cmd == "show" then
        if ns.ToggleMainFrame then ns.ToggleMainFrame() end
    elseif cmd == "inv" or cmd == "invite" then
        if ns.InviteSquadMembers then ns.InviteSquadMembers() end
    elseif cmd == "sync" then
        if ns.Sync and ns.Sync.BroadcastFullState then
            ns.Sync:BroadcastFullState(true)
        end
    elseif cmd == "sos" or cmd == "helpme" then
        if ns.Radar and ns.Radar.SendSOSAlert then
            ns.Radar:SendSOSAlert(rest ~= "" and rest or "Brauche Hilfe an meiner Position!")
        end
    elseif cmd == "hud" then
        if ns.db and ns.db.ui and ns.db.ui.hud then
            ns.db.ui.hud.enabled = not ns.db.ui.hud.enabled
            ns.Print("Squad-HUD: " .. (ns.db.ui.hud.enabled and "|cff34d399Aktiviert|r" or "|cfff87171Deaktiviert|r"))
            if ns.QoL and ns.QoL.UpdateHUD then ns.QoL:UpdateHUD() end
        end
    elseif cmd == "add" and rest ~= "" then
        ns.AddToSquadRoster(rest)
    elseif cmd == "config" or cmd == "settings" or cmd == "options" then
        if ns.ToggleMainFrame then ns.ToggleMainFrame("SETTINGS") end
    elseif cmd == "reset" or cmd == "resetpos" then
        if ns.db and ns.db.ui then
            ns.db.ui.point = "CENTER"
            ns.db.ui.relPoint = "CENTER"
            ns.db.ui.x = 0
            ns.db.ui.y = 0
            ns.db.ui.scale = 1.0
            if ns.MainFrame then
                ns.MainFrame:ClearAllPoints()
                ns.MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                ns.MainFrame:SetScale(1.0)
            end
            ns.Print("Fensterposition und Skalierung wurden zurückgesetzt.")
        end
    else
        ns.Print("Befehle:")
        print("  |cff38bdf8/ff|r — Squad Hub Fenster öffnen/schließen")
        print("  |cff38bdf8/ff inv|r — Ganze Stammgruppe einladen")
        print("  |cff38bdf8/ff sync|r — Inventar, Berufe, Quests & Position sofort synchronisieren")
        print("  |cff38bdf8/ff sos [Nachricht]|r — Notruf-Ping mit Karten-Koordinaten an Freunde senden")
        print("  |cff38bdf8/ff add <Name>|r — Freund fest zur Stammgruppe hinzufügen")
        print("  |cff38bdf8/ff hud|r — Kompaktes Gruppen-HUD ein-/ausblenden")
        print("  |cff38bdf8/ff config|r — Einstellungen öffnen")
        print("  |cff38bdf8/ff reset|r — Fensterposition & Skalierung zurücksetzen")
    end
end
