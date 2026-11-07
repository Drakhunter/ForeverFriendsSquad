-- =========================================================================
-- UI/SettingsPanel.lua
-- Comprehensive In-Window Customization Tab + AceConfig-3.0 / LibSharedMedia
-- Options Registration.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

local UI = ns.UI

-- -------------------------------------------------------------------------
-- In-Window Modern Settings Tab
-- -------------------------------------------------------------------------
function ns.BuildSettingsView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()

    local controls = {}
    local function addControl(ctrl)
        if ctrl and ctrl.RefreshValue then
            controls[#controls + 1] = ctrl
        end
        return ctrl
    end

    -- Section 1: Theme Selection Bar
    local themeLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    themeLabel:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -14)
    themeLabel:SetText("Farbschema (Theme):")

    local themeButtons = {}
    local tx = 16
    for _, key in ipairs(ns.THEME_ORDER) do
        local tInfo = ns.THEMES[key]
        local shortLabel = tInfo.label:match("^([^(]+)") or key
        local btn = UI.CreateButton(view, strtrim(shortLabel), 132, 24, function()
            ns.SetTheme(key)
            for _, b in ipairs(themeButtons) do
                b.isActive = (b.themeKey == key)
                b:RefreshStyle()
            end
        end)
        btn.themeKey = key
        btn:SetPoint("TOPLEFT", view, "TOPLEFT", tx, -34)
        tx = tx + 138
        themeButtons[#themeButtons + 1] = btn
    end

    -- Section 2: Sliders (Left Column & Right Column)
    local scaleSlider = addControl(UI.CreateSlider(
        view, "Hauptfenster Skalierung", 0.65, 1.50, 0.05, 210,
        function() return (ns.db and ns.db.ui and ns.db.ui.scale) or 1.0 end,
        function(v)
            if ns.db and ns.db.ui then
                ns.db.ui.scale = v
                if ns.MainFrame then ns.MainFrame:SetScale(v) end
            end
        end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    ))
    scaleSlider:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -72)

    local alphaSlider = addControl(UI.CreateSlider(
        view, "Fenster-Deckkraft (Alpha)", 0.55, 1.00, 0.05, 210,
        function() return (ns.db and ns.db.ui and ns.db.ui.alpha) or 0.96 end,
        function(v)
            if ns.db and ns.db.ui then
                ns.db.ui.alpha = v
                if ns.MainFrame then ns.MainFrame:SetAlpha(v) end
            end
        end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    ))
    alphaSlider:SetPoint("TOPLEFT", view, "TOPLEFT", 248, -72)

    local hudScaleSlider = addControl(UI.CreateSlider(
        view, "Squad-HUD Skalierung", 0.60, 1.50, 0.05, 210,
        function() return (ns.db and ns.db.ui and ns.db.ui.hud and ns.db.ui.hud.scale) or 1.0 end,
        function(v)
            if ns.db and ns.db.ui and ns.db.ui.hud then
                ns.db.ui.hud.scale = v
                if ns.QoL and ns.QoL.UpdateHUD then ns.QoL:UpdateHUD() end
            end
        end,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
    ))
    hudScaleSlider:SetPoint("TOPLEFT", view, "TOPLEFT", 480, -72)

    -- Section 3: Addon-Only Sync Transport Info & Auto-Invite Keywords
    local chLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chLabel:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -124)
    chLabel:SetText("Sync-Transport (100% geheimer Addon-Only Kanal — belegt keinen /1..10 Chat):")

    local syncModeBadge = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    syncModeBadge:SetPoint("TOPLEFT", view, "TOPLEFT", 16, -145)
    syncModeBadge:SetText("|cff34d399Aktiv: Addon-Kanal (Party / Raid / Gilde / Online-Freunde)|r")

    local chCleanBtn = UI.CreateButton(view, "Alten Chat-Kanal verlassen", 165, 24, function()
        if ns.Sync and ns.Sync.LeaveCustomChannel then
            ns.Sync:LeaveCustomChannel()
        end
        ns.Print("Alte nummerierte Sync-Kanäle wurden verlassen. Das Addon nutzt ausschließlich den unsichtbaren Addon-Kanal.")
    end)
    chCleanBtn:SetPoint("TOPLEFT", view, "TOPLEFT", 190, -142)

    local kwLabel = view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    kwLabel:SetPoint("TOPLEFT", view, "TOPLEFT", 356, -124)
    kwLabel:SetText("Auto-Invite Stichwörter (Komma-getrennt):")

    local kwInput = UI.CreateSearchBox(view, 210, 24, "inv, +, invite, 123", nil)
    kwInput:SetPoint("TOPLEFT", view, "TOPLEFT", 356, -142)

    local kwSaveBtn = UI.CreateButton(view, "Speichern", 96, 24, function()
        if ns.db and ns.db.qol then
            ns.db.qol.autoInviteKeywords = strtrim(kwInput:GetText() or "inv, +")
            ns.Print("Auto-Invite Stichwörter gespeichert: |cff34d399" .. ns.db.qol.autoInviteKeywords .. "|r")
        end
        kwInput:ClearFocus()
    end)
    kwSaveBtn:SetPoint("LEFT", kwInput, "RIGHT", 8, 0)

    -- Section 4: Module & Feature Checkboxes (2 Clean Columns)
    local leftChecks = {
        {
            label = "Inventar-Bestände im Item-Tooltip anzeigen",
            tip = "Zeigt beim Überfahren eines Items sofort an, wer in deiner Stammgruppe (inkl. Bank & Twinks) wie viele davon besitzt.",
            get = function() return ns.db and ns.db.inventory and ns.db.inventory.showTooltip end,
            set = function(v) if ns.db then ns.db.inventory.showTooltip = v end end,
        },
        {
            label = "Im Tooltip anzeigen, wer ein Item herstellen kann",
            tip = "Zeigt den Namen und Beruf deiner Freunde an, wenn jemand das Rezept für das Item beherrscht.",
            get = function() return ns.db and ns.db.inventory and ns.db.inventory.tooltipShowCraftableBy end,
            set = function(v) if ns.db then ns.db.inventory.tooltipShowCraftableBy = v end end,
        },
        {
            label = "Quick-Trade Leiste im Handelsfenster einblenden",
            tip = "Blendet beim Handeln eine Schnellleiste für Wunschlisten-Items, Tränke, Gesundheitssteine & Magier-Wasser ein.",
            get = function() return ns.db and ns.db.inventory and ns.db.inventory.enableTradeHelper end,
            set = function(v) if ns.db then ns.db.inventory.enableTradeHelper = v end end,
        },
        {
            label = "Berufe beim Öffnen automatisch scannen & teilen",
            tip = "Synchronisiert deine gelernten Rezepte automatisch mit deinen Freunden, sobald du ein Berufsfenster öffnest.",
            get = function() return ns.db and ns.db.inventory and ns.db.inventory.scanProfessionsAutomatically end,
            set = function(v) if ns.db then ns.db.inventory.scanProfessionsAutomatically = v end end,
        },
        {
            label = "Live-Benachrichtigung bei Quest-Abschluss von Freunden",
            tip = "Gibt eine kurze Meldung aus, wenn ein Freund eine gemeinsame Quest fertiggestellt hat.",
            get = function() return ns.db and ns.db.quests and ns.db.quests.showObjectiveNotifications end,
            set = function(v) if ns.db then ns.db.quests.showObjectiveNotifications = v end end,
        },
        {
            label = "Freunde als Pins auf der Weltkarte anzeigen (Solo & Party)",
            tip = "Zeigt alle aktiven Freunde klassenfarbig auf der Weltkarte an – auch wenn ihr nicht in einer Gruppe seid!",
            get = function() return ns.db and ns.db.radar and ns.db.radar.showWorldMapPins end,
            set = function(v)
                if ns.db then
                    ns.db.radar.showWorldMapPins = v
                    if ns.Radar then ns.Radar:RefreshWorldMapPins() end
                end
            end,
        },
        {
            label = "Todes- & Gank-Alarme mit Karten-Wegpunkt empfangen",
            tip = "Blendet ein klickbares Banner ein, wenn ein Freund stirbt oder einen SOS-Notruf sendet.",
            get = function() return ns.db and ns.db.radar and ns.db.radar.receiveDeathAlerts end,
            set = function(v) if ns.db then ns.db.radar.receiveDeathAlerts = v end end,
        },
    }

    local rightChecks = {
        {
            label = "Kompaktes Squad-HUD auf dem Bildschirm anzeigen",
            tip = "Zeigt ein kleines, frei verschiebbares Status-Fenster mit deinen aktiven Freunden, Gebiet & Lebenspunkten.",
            get = function() return ns.db and ns.db.ui and ns.db.ui.hud and ns.db.ui.hud.enabled end,
            set = function(v)
                if ns.db then
                    ns.db.ui.hud.enabled = v
                    if ns.QoL then ns.QoL:UpdateHUD() end
                end
            end,
        },
        {
            label = "Squad-HUD Position sperren (Lock)",
            tip = "Verhindert versehentliches Verschieben des kleinen Squad-HUDs.",
            get = function() return ns.db and ns.db.ui and ns.db.ui.hud and ns.db.ui.hud.locked end,
            set = function(v) if ns.db then ns.db.ui.hud.locked = v end end,
        },
        {
            label = "Auto-Invite bei Stichwort im Whisper / Gildenchat",
            tip = "Lädt Freunde automatisch in deine Gruppe ein, wenn sie dir eines der Stichwörter (z. B. 'inv' oder '+') schreiben.",
            get = function() return ns.db and ns.db.qol and ns.db.qol.autoInviteEnabled end,
            set = function(v) if ns.db then ns.db.qol.autoInviteEnabled = v end end,
        },
        {
            label = "Gruppeneinladungen von Stammgruppe automatisch annehmen",
            tip = "Nimmt Einladungen von Freunden auf deiner Stammgruppen-/Freundesliste sofort automatisch an.",
            get = function() return ns.db and ns.db.qol and ns.db.qol.autoAcceptInviteFromSquad end,
            set = function(v) if ns.db then ns.db.qol.autoAcceptInviteFromSquad = v end end,
        },
        {
            label = "Beim Händler Ausrüstung automatisch reparieren",
            tip = "Repariert deine Ausrüstung beim Öffnen eines Händlers automatisch und zählt die Kosten für die Statistik.",
            get = function() return ns.db and ns.db.stats and ns.db.stats.autoRepairFromOwnGold end,
            set = function(v) if ns.db then ns.db.stats.autoRepairFromOwnGold = v end end,
        },
        {
            label = "Gilden-Addon-Kanal für Synchronisation nutzen",
            tip = "Synchronisiert Daten unsichtbar über den geheimen Gilden-Addon-Kanal (belegt keinen Chat-Slot).",
            get = function() return ns.db and ns.db.sync and ns.db.sync.useGuild end,
            set = function(v)
                if ns.db and ns.db.sync then
                    ns.db.sync.useGuild = v
                end
            end,
        },
        {
            label = "Minimap-Button anzeigen (LibDBIcon)",
            tip = "Blendet das ForeverFriends-Symbol an der Minimap ein oder aus.",
            get = function() return not (ns.db and ns.db.ui and ns.db.ui.minimap and ns.db.ui.minimap.hide) end,
            set = function(v)
                if ns.db and ns.db.ui and ns.db.ui.minimap then
                    ns.db.ui.minimap.hide = not v
                    ns.UpdateMinimapButtonVisibility()
                end
            end,
        },
    }

    local startY = -182
    for i, item in ipairs(leftChecks) do
        local cb = addControl(UI.CreateCheckBox(view, item.label, item.tip, item.get, item.set))
        cb:SetPoint("TOPLEFT", view, "TOPLEFT", 16, startY - (i - 1) * 30)
    end

    for i, item in ipairs(rightChecks) do
        local cb = addControl(UI.CreateCheckBox(view, item.label, item.tip, item.get, item.set))
        cb:SetPoint("TOPLEFT", view, "TOPLEFT", 368, startY - (i - 1) * 30)
    end

    -- Bottom Action Buttons (AceConfig Dialog, Test Alert, Reset Positions)
    local aceBtn = UI.CreateButton(view, "Erweiterte Ace3 / Schriftart-Optionen", 240, 28, function()
        if ns.Libs.AceConfigDialog then
            ns.Libs.AceConfigDialog:Open("ForeverFriends")
        end
    end, true)
    aceBtn:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 16, 14)

    local testToastBtn = UI.CreateButton(view, "Test-Alarm Banner zeigen", 175, 28, function()
        if ns.Radar and ns.Radar.ShowAlertToast then
            local zone, subzone, mapID, x, y = ns.GetPlayerLocationData()
            ns.Radar:ShowAlertToast({
                kind = "SOS",
                senderName = ns.GetPlayerShortName(),
                class = ns.GetPlayerClass(),
                zone = zone,
                subzone = subzone,
                mapID = mapID,
                x = x,
                y = y,
                msg = "Test-Alarm (Banner kann per Drag & Drop verschoben werden)",
            })
        end
    end)
    testToastBtn:SetPoint("LEFT", aceBtn, "RIGHT", 10, 0)

    local resetBtn = UI.CreateButton(view, "Positionen & Skalierung zurücksetzen", 230, 28, function()
        if SlashCmdList["FOREVERFRIENDS"] then
            SlashCmdList["FOREVERFRIENDS"]("reset")
            view:RefreshData()
        end
    end)
    resetBtn:SetPoint("LEFT", testToastBtn, "RIGHT", 10, 0)

    function view:RefreshData()
        if not ns.db then return end
        local curTheme = (ns.db.ui and ns.db.ui.theme) or "OBSIDIAN"
        for _, b in ipairs(themeButtons) do
            b.isActive = (b.themeKey == curTheme)
            b:RefreshStyle()
        end
        kwInput:SetText((ns.db.qol and ns.db.qol.autoInviteKeywords) or "inv, +, invite, 123")
        for _, ctrl in ipairs(controls) do
            ctrl:RefreshValue()
        end
    end

    return view
end

-- -------------------------------------------------------------------------
-- AceConfig-3.0 + LibSharedMedia-3.0 Registration
-- -------------------------------------------------------------------------
local function SetupAceConfig()
    local AC = ns.Libs.AceConfig
    local ACD = ns.Libs.AceConfigDialog
    local LSM = ns.Libs.LSM
    if not AC or not ACD then return end

    local themeValues = {}
    for _, k in ipairs(ns.THEME_ORDER) do
        themeValues[k] = ns.THEMES[k].label
    end

    local options = {
        type = "group",
        name = "ForeverFriends [Squad Hub]",
        args = {
            openHub = {
                type = "execute",
                name = "Squad Hub Fenster öffnen (/ff)",
                order = 1,
                func = function()
                    if ns.ToggleMainFrame then ns.ToggleMainFrame() end
                end,
            },
            syncNow = {
                type = "execute",
                name = "Sofort-Sync senden (/ff sync)",
                order = 2,
                func = function()
                    if ns.Sync then ns.Sync:BroadcastFullState(true) end
                end,
            },
            uiGroup = {
                type = "group",
                name = "UI, Skalierung & Medien (LibSharedMedia)",
                inline = true,
                order = 10,
                args = {
                    theme = {
                        type = "select",
                        name = "Farbschema (Theme)",
                        order = 1,
                        values = themeValues,
                        get = function() return ns.db.ui.theme end,
                        set = function(_, val) ns.SetTheme(val) end,
                    },
                    scale = {
                        type = "range",
                        name = "Fenster-Skalierung",
                        order = 2,
                        min = 0.65,
                        max = 1.50,
                        step = 0.05,
                        isPercent = true,
                        get = function() return ns.db.ui.scale end,
                        set = function(_, val)
                            ns.db.ui.scale = val
                            if ns.MainFrame then ns.MainFrame:SetScale(val) end
                        end,
                    },
                    alpha = {
                        type = "range",
                        name = "Fenster-Deckkraft",
                        order = 3,
                        min = 0.55,
                        max = 1.00,
                        step = 0.05,
                        isPercent = true,
                        get = function() return ns.db.ui.alpha end,
                        set = function(_, val)
                            ns.db.ui.alpha = val
                            if ns.MainFrame then ns.MainFrame:SetAlpha(val) end
                        end,
                    },
                    font = {
                        type = "select",
                        name = "Schriftart (LibSharedMedia-3.0)",
                        order = 4,
                        dialogControl = LSM and "LSM30_Font" or nil,
                        values = function() return LSM and LSM:HashTable("font") or { ["Friz Quadrata TT"] = "Friz Quadrata TT" } end,
                        get = function() return ns.db.ui.font end,
                        set = function(_, val) ns.db.ui.font = val end,
                    },
                    statusbar = {
                        type = "select",
                        name = "Statusleisten-Textur (LibSharedMedia-3.0)",
                        order = 5,
                        dialogControl = LSM and "LSM30_Statusbar" or nil,
                        values = function() return LSM and LSM:HashTable("statusbar") or { ["Blizzard"] = "Blizzard" } end,
                        get = function() return ns.db.ui.statusbar end,
                        set = function(_, val)
                            ns.db.ui.statusbar = val
                            if ns.QoL then ns.QoL:UpdateHUD() end
                        end,
                    },
                    pinScale = {
                        type = "range",
                        name = "Weltkarten-Pin Größe",
                        order = 6,
                        min = 0.60,
                        max = 1.80,
                        step = 0.10,
                        isPercent = true,
                        get = function() return ns.db.radar.pinScale end,
                        set = function(_, val)
                            ns.db.radar.pinScale = val
                            if ns.Radar then ns.Radar:RefreshWorldMapPins() end
                        end,
                    },
                },
            },
            syncGroup = {
                type = "group",
                name = "Synchronisation & Kanäle",
                inline = true,
                order = 20,
                args = {
                    channelName = {
                        type = "input",
                        name = "Versteckter Sync-Kanalname",
                        order = 1,
                        get = function() return ns.db.sync.channelName end,
                        set = function(_, val)
                            local old = ns.db.sync.channelName
                            ns.db.sync.channelName = strtrim(val or "ForeverSquadSync")
                            if ns.Sync then
                                ns.Sync:LeaveCustomChannel(old)
                                ns.Sync:EnsureCustomChannel()
                            end
                        end,
                    },
                    channelPassword = {
                        type = "input",
                        name = "Kanal-Passwort (optional)",
                        order = 2,
                        get = function() return ns.db.sync.channelPassword end,
                        set = function(_, val)
                            ns.db.sync.channelPassword = val or ""
                            if ns.Sync then ns.Sync:EnsureCustomChannel() end
                        end,
                    },
                    onlyTrustedRoster = {
                        type = "toggle",
                        name = "Nur mit expliziten Freunden / Stammgruppe synchronisieren",
                        width = "full",
                        order = 3,
                        get = function() return ns.db.sync.onlyTrustedRoster end,
                        set = function(_, val) ns.db.sync.onlyTrustedRoster = val end,
                    },
                },
            },
        },
    }

    pcall(AC.RegisterOptionsTable, AC, "ForeverFriends", options)
    pcall(ACD.AddToBlizOptions, ACD, "ForeverFriends", "ForeverFriends")
end

ns.RegisterMessage("ADDON_INITIALIZED", function()
    SetupAceConfig()
end)
