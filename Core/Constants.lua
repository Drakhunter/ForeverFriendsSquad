-- =========================================================================
-- Core/Constants.lua
-- Protocol definitions, modern UI theme palettes, class colors, and
-- comprehensive default SavedVariables schema.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

ns.ADDON_NAME = addonName
ns.DISPLAY_NAME = "ForeverFriends"
ns.VERSION = "1.0.0"
ns.COMM_PREFIX = "FFSQD1"
ns.PROTOCOL_VERSION = 1

-- -------------------------------------------------------------------------
-- Modern UI Theme Presets
-- -------------------------------------------------------------------------
ns.THEMES = {
    OBSIDIAN = {
        key = "OBSIDIAN",
        label = "Obsidian Cyan (Modern Dark)",
        bg = { 0.06, 0.07, 0.09, 0.96 },
        panel = { 0.09, 0.10, 0.13, 0.95 },
        card = { 0.12, 0.14, 0.18, 0.90 },
        cardHover = { 0.16, 0.19, 0.25, 0.95 },
        header = { 0.04, 0.05, 0.07, 0.98 },
        border = { 0.20, 0.23, 0.29, 1.00 },
        accent = { 0.22, 0.74, 0.97, 1.00 },      -- #38bdf8 Sky Cyan
        accentSoft = { 0.22, 0.74, 0.97, 0.18 },
        accentHex = "38bdf8",
        text = { 0.95, 0.96, 0.98, 1.00 },
        textMuted = { 0.60, 0.65, 0.73, 1.00 },
        success = { 0.20, 0.83, 0.60, 1.00 },     -- #34d399
        warning = { 0.98, 0.75, 0.14, 1.00 },     -- #fbbf24
        danger = { 0.97, 0.35, 0.35, 1.00 },      -- #f87171
    },
    EMERALD_SLATE = {
        key = "EMERALD_SLATE",
        label = "Smaragd Schiefer (Emerald)",
        bg = { 0.05, 0.08, 0.07, 0.96 },
        panel = { 0.08, 0.11, 0.10, 0.95 },
        card = { 0.11, 0.15, 0.14, 0.90 },
        cardHover = { 0.14, 0.20, 0.18, 0.95 },
        header = { 0.04, 0.06, 0.05, 0.98 },
        border = { 0.18, 0.27, 0.23, 1.00 },
        accent = { 0.20, 0.83, 0.60, 1.00 },      -- #34d399 Emerald
        accentSoft = { 0.20, 0.83, 0.60, 0.18 },
        accentHex = "34d399",
        text = { 0.94, 0.97, 0.95, 1.00 },
        textMuted = { 0.58, 0.68, 0.63, 1.00 },
        success = { 0.20, 0.83, 0.60, 1.00 },
        warning = { 0.98, 0.75, 0.14, 1.00 },
        danger = { 0.97, 0.35, 0.35, 1.00 },
    },
    CLASSIC_GOLD = {
        key = "CLASSIC_GOLD",
        label = "Forever Gold (Royal Amber)",
        bg = { 0.07, 0.06, 0.05, 0.96 },
        panel = { 0.10, 0.09, 0.08, 0.95 },
        card = { 0.14, 0.12, 0.10, 0.90 },
        cardHover = { 0.19, 0.16, 0.13, 0.95 },
        header = { 0.05, 0.04, 0.03, 0.98 },
        border = { 0.32, 0.26, 0.18, 1.00 },
        accent = { 0.96, 0.76, 0.26, 1.00 },      -- #f5c242 Gold
        accentSoft = { 0.96, 0.76, 0.26, 0.18 },
        accentHex = "f5c242",
        text = { 0.97, 0.94, 0.88, 1.00 },
        textMuted = { 0.70, 0.64, 0.54, 1.00 },
        success = { 0.25, 0.85, 0.55, 1.00 },
        warning = { 0.98, 0.75, 0.14, 1.00 },
        danger = { 0.97, 0.35, 0.35, 1.00 },
    },
    MIDNIGHT_VIOLET = {
        key = "MIDNIGHT_VIOLET",
        label = "Mitternacht Violett (Arcane)",
        bg = { 0.06, 0.05, 0.09, 0.96 },
        panel = { 0.09, 0.08, 0.14, 0.95 },
        card = { 0.13, 0.11, 0.19, 0.90 },
        cardHover = { 0.17, 0.15, 0.25, 0.95 },
        header = { 0.04, 0.03, 0.07, 0.98 },
        border = { 0.25, 0.21, 0.35, 1.00 },
        accent = { 0.66, 0.55, 0.98, 1.00 },      -- #a78bfa Violet
        accentSoft = { 0.66, 0.55, 0.98, 0.18 },
        accentHex = "a78bfa",
        text = { 0.96, 0.95, 0.99, 1.00 },
        textMuted = { 0.64, 0.60, 0.75, 1.00 },
        success = { 0.20, 0.83, 0.60, 1.00 },
        warning = { 0.98, 0.75, 0.14, 1.00 },
        danger = { 0.97, 0.35, 0.35, 1.00 },
    },
    CRIMSON_SHADOW = {
        key = "CRIMSON_SHADOW",
        label = "Blutmond (Crimson Dark)",
        bg = { 0.08, 0.05, 0.06, 0.96 },
        panel = { 0.12, 0.08, 0.09, 0.95 },
        card = { 0.16, 0.11, 0.12, 0.90 },
        cardHover = { 0.22, 0.14, 0.16, 0.95 },
        header = { 0.06, 0.03, 0.04, 0.98 },
        border = { 0.32, 0.18, 0.20, 1.00 },
        accent = { 0.96, 0.35, 0.42, 1.00 },      -- #f43f5e Rose/Crimson
        accentSoft = { 0.96, 0.35, 0.42, 0.18 },
        accentHex = "f43f5e",
        text = { 0.98, 0.94, 0.95, 1.00 },
        textMuted = { 0.72, 0.60, 0.63, 1.00 },
        success = { 0.20, 0.83, 0.60, 1.00 },
        warning = { 0.98, 0.75, 0.14, 1.00 },
        danger = { 0.97, 0.35, 0.35, 1.00 },
    },
}

ns.THEME_ORDER = {
    "OBSIDIAN",
    "EMERALD_SLATE",
    "CLASSIC_GOLD",
    "MIDNIGHT_VIOLET",
    "CRIMSON_SHADOW",
}

-- -------------------------------------------------------------------------
-- Class Colors (Hex & RGB Fallback)
-- -------------------------------------------------------------------------
ns.CLASS_COLORS = {
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43, hex = "c79c6e" },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73, hex = "f58cba" },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45, hex = "abd473" },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41, hex = "fff569" },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00, hex = "ffffff" },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23, hex = "c41f3b" },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87, hex = "0070de" },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92, hex = "40c7eb" },
    WARLOCK     = { r = 0.53, g = 0.53, b = 0.93, hex = "8787ed" },
    MONK        = { r = 0.00, g = 1.00, b = 0.59, hex = "00ff96" },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04, hex = "ff7d0a" },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79, hex = "a330c9" },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50, hex = "33937f" },
}

-- -------------------------------------------------------------------------
-- Default SavedVariables Schema
-- -------------------------------------------------------------------------
ns.DEFAULTS = {
    -- 1. UI Appearance, Scaling & Window Layout
    ui = {
        theme = "OBSIDIAN",
        scale = 1.0,
        alpha = 0.96,
        locked = false,
        font = "Friz Quadrata TT",
        fontSize = 12,
        statusbar = "Blizzard",
        width = 920,
        height = 600,
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 0,
        activeTab = "INVENTORY",
        filterFaction = "ALL",
        filterChar = "ALL",
        minimap = {
            hide = false,
            minimapPos = 215,
        },
        hud = {
            enabled = true,
            locked = false,
            scale = 1.0,
            alpha = 0.90,
            showOutOfGroup = true,
            showManaBars = true,
            showLockouts = true,
            point = "TOPLEFT",
            relPoint = "TOPLEFT",
            x = 24,
            y = -140,
        },
        toast = {
            enabled = true,
            locked = false,
            scale = 1.0,
            playSound = true,
            point = "TOP",
            relPoint = "TOP",
            x = 0,
            y = -110,
        },
    },

    -- 2. Sync & Transport Configuration
    sync = {
        enabled = true,
        useCustomChannel = false,
        channelName = "ForeverSquadSync",
        channelPassword = "",
        hideChannelSystemMessages = true,
        usePartyRaid = true,
        useGuild = true,
        onlyTrustedRoster = false,      -- If true, only sync with players added to Squad Roster or BNet/Friends
        gpsIntervalMoving = 4,          -- Seconds between GPS broadcasts while moving
        gpsIntervalIdle = 12,           -- Seconds between GPS broadcasts while idle
        autoBroadcastInventory = true,  -- Sync inventory changes automatically (debounced)
        autoBroadcastQuests = true,     -- Sync quest progress changes automatically
    },

    -- 3. Module 1 (Punkt 2 - Mandatory): Inventory, Bank, Gold, Twinks & Professions
    inventory = {
        enabled = true,
        showTooltip = true,
        tooltipShowOwnChars = true,
        tooltipShowSquadChars = true,
        tooltipShowCraftableBy = true,
        tooltipShowZeroCount = false,
        tooltipMaxLines = 12,
        scanBankAutomatically = true,
        scanProfessionsAutomatically = true,
        enableTradeHelper = true,
        autoTradeTrusted = false,
    },

    -- 4. Module 2 (Punkt 1 - Wichtig): Quest & Leveling Sync
    quests = {
        enabled = true,
        showObjectiveNotifications = true,
        announceQuestCompleted = true,
        autoShareNewQuests = false,
        showQuestTooltip = true,
        filterCurrentZoneOnly = false,
    },

    -- 5. Module 3 (Punkt 4 - Wichtig): World Map Radar & Emergency Alerts
    radar = {
        enabled = true,
        showWorldMapPins = true,
        pinScale = 1.0,
        showPinNames = true,
        broadcastDeaths = true,
        receiveDeathAlerts = true,
        autoWaypointOnSOS = false,
    },

    -- 6. Module 4 (Punkt 3 - Nice to have): Group QoL, Auto-Invite, Lockouts & Buffs
    qol = {
        enabled = true,
        autoInviteEnabled = false,
        autoInviteKeywords = "inv, +, invite, 123",
        autoInviteFriendsOnly = true,
        autoAcceptInviteFromSquad = false,
        trackInstanceLockouts = true,
        buffCheckReportToParty = false,
    },

    -- 7. Module 5 (Punkt 5): Squad Statistics & Hall of Fame
    stats = {
        enabled = true,
        trackDeaths = true,
        trackRepairs = true,
        trackRolls = true,
        trackQuests = true,
        autoRepairFromOwnGold = false,
    },

    -- 8. Persistent Data Stores (Account-wide + Synced Friend Data)
    squadRoster = {},       -- [shortNameOrFullKey] = { note = "", trusted = true, addedAt = timestamp }
    wishlist = {},          -- [itemID] = { itemID, name, icon, neededCount, requestedBy }
    characters = {},        -- Local account characters: [charKey] = { name, realm, class, level, faction, money, bags={}, bank={}, equip={}, bagFree=0, bagTotal=0, professions={}, quests={}, stats={}, updatedAt }
    squadCharacters = {},   -- Synced friend characters: [charKey] = { owner, name, realm, class, level, faction, money, bags={}, bank={}, equip={}, professions={}, quests={}, stats={}, updatedAt }
    instanceHistory = {},   -- Rolling timestamps of entered instances for 5/hr tracker
}
