-- =========================================================================
-- UI/MainFrame.lua
-- Modern, Movable & Drag-Scalable Squad Hub Window with 6 Feature Views:
-- 1. Inventar & Bank (Twinks + Freunde + Wunschliste)
-- 2. Berufe & Rezepte (Wer kann was herstellen?)
-- 3. Quests & Leveling (Live-Questfortschritt & Teilen)
-- 4. Weltkarte & Gruppe (GPS-Radar, Stammgruppen-Roster, Buff-Check, IDs)
-- 5. Ruhmeshalle (Tode, Repkosten, 100er/1er Rolls)
-- 6. Einstellungen (Themes, Skalierung, Sync, Module & Customizing)
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

local UI = ns.UI
local mainFrame = nil

local TABS = {
    { id = "INVENTORY",   label = "Inventar & Bank",   badge = "Prio 1" },
    { id = "PROFESSIONS", label = "Berufe & Rezepte",  badge = "Prio 1" },
    { id = "QUESTS",      label = "Quests & Leveling", badge = "Prio 2" },
    { id = "RADAR",       label = "Welt & Gruppe",     badge = "Prio 3" },
    { id = "STATS",       label = "Ruhmeshalle",       badge = "Fun"    },
    { id = "SETTINGS",    label = "Einstellungen",     badge = "UI"     },
}

-- -------------------------------------------------------------------------
-- View 1: Shared Inventory, Bank & Wishlist Browser
-- -------------------------------------------------------------------------
local function BuildInventoryView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view.filterMode = "ALL" -- "ALL", "OWN", "SQUAD", "WISHLIST"
    view.searchText = ""

    local searchBox = UI.CreateSearchBox(view, 230, 26, "Item, Kraut, Erz oder Spieler suchen...", function(txt)
        view.searchText = (txt or ""):lower()
        view:RefreshData()
    end)
    searchBox:SetPoint("TOPLEFT", view, "TOPLEFT", 12, -12)

    local filterButtons = {}
    local filters = {
        { key = "ALL",      label = "Alle Items" },
        { key = "OWN",      label = "Meine Twinks" },
        { key = "SQUAD",    label = "Nur Freunde" },
        { key = "WISHLIST", label = "[*] Wunschliste" },
    }

    local xOff = 252
    for _, f in ipairs(filters) do
        local btn = UI.CreateButton(view, f.label, 100, 26, function()
            view.filterMode = f.key
            for _, b in ipairs(filterButtons) do
                b.isActive = (b.filterKey == view.filterMode)
                b:RefreshStyle()
            end
            view:RefreshData()
        end)
        btn.filterKey = f.key
        btn.isActive = (f.key == "ALL")
        btn:RefreshStyle()
        btn:SetPoint("TOPLEFT", view, "TOPLEFT", xOff, -12)
        xOff = xOff + 106
        filterButtons[#filterButtons + 1] = btn
    end

    local goldSummary = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    goldSummary:SetPoint("TOPLEFT", view, "TOPLEFT", 14, -46)
    view.goldSummary = goldSummary

    local hintText = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetPoint("TOPRIGHT", view, "TOPRIGHT", -14, -46)
    hintText:SetText("Rechtsklick: [*] Wunschliste | Shift-Klick: Chat-Link")

    local listFrame = UI.CreateScrollList(view, 36, 11, function(listParent)
        local row = CreateFrame("Button", nil, listParent, "BackdropTemplate")
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local theme = ns.GetActiveTheme()
        UI.ApplySurface(row, theme.card, theme.border, 1)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        nameText:SetWidth(210)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local holdersText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        holdersText:SetPoint("LEFT", nameText, "RIGHT", 10, 0)
        holdersText:SetPoint("RIGHT", row, "RIGHT", -84, 0)
        holdersText:SetJustifyH("LEFT")
        row.holdersText = holdersText

        local totalText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        totalText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        totalText:SetJustifyH("RIGHT")
        row.totalText = totalText

        row:SetScript("OnEnter", function(self)
            local t = ns.GetActiveTheme()
            UI.ApplySurface(self, t.cardHover, t.accent, 1)
            if self.itemData and self.itemData.itemID then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetItemByID then
                    GameTooltip:SetItemByID(self.itemData.itemID)
                elseif self.itemData.link then
                    GameTooltip:SetHyperlink(self.itemData.link)
                else
                    GameTooltip:SetText(self.itemData.name, 1, 1, 1)
                end
                GameTooltip:Show()
            end
        end)

        row:SetScript("OnLeave", function(self)
            local t = ns.GetActiveTheme()
            UI.ApplySurface(self, t.card, t.border, 1)
            GameTooltip:Hide()
        end)

        row:SetScript("OnClick", function(self, button)
            local d = self.itemData
            if not d then return end
            if IsShiftKeyDown() and ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
                local link = d.link or d.name
                ChatEdit_InsertLink(link)
                return
            end
            if button == "RightButton" and ns.db then
                ns.db.wishlist = ns.db.wishlist or {}
                if ns.db.wishlist[d.itemID] then
                    ns.db.wishlist[d.itemID] = nil
                    ns.Print("Von Squad-Wunschliste entfernt: |cffffd100" .. d.name .. "|r")
                else
                    ns.db.wishlist[d.itemID] = {
                        itemID = d.itemID,
                        name = d.name,
                        icon = d.icon,
                        requestedBy = ns.GetPlayerShortName(),
                    }
                    ns.Print("Auf Squad-Wunschliste gesetzt [*]: |cffffd100" .. d.name .. "|r")
                end
                view:RefreshData()
            end
        end)

        return row
    end, function(row, data)
        row.itemData = data
        row.icon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local star = data.isWishlist and "|cfffbbf24[*] |r" or ""
        row.nameText:SetText(star .. data.coloredName)
        row.holdersText:SetText(data.holdersSummary)
        row.totalText:SetText(string.format("|cff34d399%dx|r", data.totalCount))
    end)

    listFrame:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -66)
    listFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -10, 10)
    view.listFrame = listFrame

    function view:RefreshData()
        if not ns.db or not ns.Inventory then return end

        local ownGold = 0
        local squadGold = 0
        local hordeGold = 0
        local allianceGold = 0
        local myChars = ns.db.characters or {}

        local function addGold(c, isOwn)
            if type(c) ~= "table" then return end
            local cName = c.name or ns.ShortName(c.key)
            local cFac = ns.ResolveCharacterFaction(cName, c.faction)
            if not ns.MatchesGlobalFilter(c, isOwn, cFac) then return end
            local m = ns.SafeNumber(c.money, 0)
            if isOwn then
                ownGold = ownGold + m
            else
                squadGold = squadGold + m
            end
            if cFac == "Horde" then
                hordeGold = hordeGold + m
            elseif cFac == "Alliance" then
                allianceGold = allianceGold + m
            end
        end

        for _, c in pairs(myChars) do
            addGold(c, true)
        end
        for key, c in pairs(ns.db.squadCharacters or {}) do
            if not myChars[key] and not ns.IsSelfName(c.name or key) then
                addGold(c, false)
            end
        end

        self.goldSummary:SetText(string.format(
            "Du: %s · Freunde: %s · |cfff87171[H]|r %s · |cff60a5fa[A]|r %s · Gesamt: %s",
            ns.FormatMoney(ownGold, true),
            ns.FormatMoney(squadGold, true),
            ns.FormatMoney(hordeGold, true),
            ns.FormatMoney(allianceGold, true),
            ns.FormatMoney(ownGold + squadGold, true)
        ))

        local seenItems = {}
        local function collectFromChar(c, isOwn)
            if type(c) ~= "table" then return end
            local cName = c.name or ns.ShortName(c.key)
            local cFac = ns.ResolveCharacterFaction(cName, c.faction)
            if not ns.MatchesGlobalFilter(c, isOwn, cFac) then return end
            for id in pairs(c.bags or {}) do seenItems[id] = true end
            for id in pairs(c.bank or {}) do seenItems[id] = true end
            for id in pairs(c.equip or {}) do seenItems[id] = true end
        end

        for _, c in pairs(myChars) do collectFromChar(c, true) end
        for key, c in pairs(ns.db.squadCharacters or {}) do
            if not myChars[key] and not ns.IsSelfName(c.name or key) then
                collectFromChar(c, false)
            end
        end
        for id in pairs(ns.db.wishlist or {}) do seenItems[id] = true end

        local rows = {}
        local q = self.searchText or ""

        for itemID in pairs(seenItems) do
            local ownList, squadList, ownTotal, squadTotal = ns.Inventory:GetItemHolders(itemID, true)
            local isWish = (ns.db.wishlist and ns.db.wishlist[itemID] ~= nil)

            local passMode = true
            if self.filterMode == "OWN" and ownTotal <= 0 then passMode = false end
            if self.filterMode == "SQUAD" and squadTotal <= 0 then passMode = false end
            if self.filterMode == "WISHLIST" and not isWish then passMode = false end

            local totalCount = ownTotal + squadTotal
            if passMode and (totalCount > 0 or isWish) then
                local meta = ns.Inventory:GetItemMetadata(itemID)
                local name = (meta and meta.name) or ("Item #" .. itemID)

                local holderParts = {}
                local holderSearchMatch = false
                for _, h in ipairs(ownList) do
                    if q ~= "" and h.name:lower():find(q, 1, true) then holderSearchMatch = true end
                    holderParts[#holderParts + 1] = string.format("%s: |cffffffff%d|r", ns.FormatCharacterDisplay(h.name, h.class, h.faction, true), h.total)
                end
                for _, h in ipairs(squadList) do
                    if q ~= "" and h.name:lower():find(q, 1, true) then holderSearchMatch = true end
                    holderParts[#holderParts + 1] = string.format("%s: |cff38bdf8%d|r", ns.FormatCharacterDisplay(h.name, h.class, h.faction, true), h.total)
                end

                local passSearch = (q == "") or name:lower():find(q, 1, true) or holderSearchMatch
                if passSearch then
                    local qualityColors = {
                        [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd",
                        [4] = "a335ee", [5] = "ff8000",
                    }
                    local qHex = qualityColors[(meta and meta.quality) or 1] or "ffffff"

                    rows[#rows + 1] = {
                        itemID = itemID,
                        name = name,
                        coloredName = "|cff" .. qHex .. name .. "|r",
                        icon = meta and meta.icon,
                        link = meta and meta.link,
                        holdersSummary = #holderParts > 0 and table.concat(holderParts, " · ") or "|cff94a3b80x auf Lager (Auf Wunschliste)|r",
                        totalCount = totalCount,
                        isWishlist = isWish,
                    }
                end
            end
        end

        table.sort(rows, function(a, b)
            if a.isWishlist ~= b.isWishlist then return a.isWishlist end
            if a.totalCount ~= b.totalCount then return a.totalCount > b.totalCount end
            return a.name < b.name
        end)

        self.listFrame:SetData(rows, "Keine passenden Items im Gruppen-Inventar gefunden.")
    end

    return view
end

-- -------------------------------------------------------------------------
-- View 2: Professions & Recipes Browser
-- -------------------------------------------------------------------------
local function BuildProfessionsView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view.searchText = ""
    view.selectedProf = "ALL"
    view.matsFilter = "ALL" -- "ALL", "DB", "OWN", "ACTIVE"
    view.availableProfessions = {}

    local searchBox = UI.CreateSearchBox(view, 185, 26, "Rezept, Mat oder Spieler...", function(txt)
        view.searchText = (txt or ""):lower()
        view:RefreshData()
    end)
    searchBox:SetPoint("TOPLEFT", view, "TOPLEFT", 12, -12)

    local profDropdown = UI.CreateDropdown(view, 155, 26, function()
        if view.selectedProf == "ALL" then
            return "|cffe2e8f0Beruf: Alle|r"
        end
        return "|cff38bdf8" .. view.selectedProf .. "|r"
    end, function()
        local items = {
            {
                text = "Alle Berufe anzeigen",
                isSelected = (view.selectedProf == "ALL"),
                onClick = function()
                    view.selectedProf = "ALL"
                    view:RefreshData()
                end,
            },
        }
        if #view.availableProfessions > 0 then
            items[#items + 1] = { isHeader = true, text = "Gescannte Berufe" }
            for _, p in ipairs(view.availableProfessions) do
                items[#items + 1] = {
                    text = string.format("|cff38bdf8%s|r |cff94a3b8(%d)|r", p.name, p.count),
                    isSelected = (view.selectedProf == p.name),
                    onClick = function()
                        view.selectedProf = p.name
                        view:RefreshData()
                    end,
                }
            end
        end
        return items
    end)
    profDropdown:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    view.profDropdown = profDropdown

    local MATS_FILTER_LABELS = {
        ALL    = "|cffe2e8f0Mats: Alle Rezepte|r",
        DB     = "|cfffbbf24Mats: In DB / Gruppe|r",
        OWN    = "|cff38bdf8Mats: Eigene Chars|r",
        ACTIVE = "|cff34d399Mats: Aktiver Char|r",
    }

    local matsDropdown = UI.CreateDropdown(view, 185, 26, function()
        return MATS_FILTER_LABELS[view.matsFilter] or MATS_FILTER_LABELS.ALL
    end, function()
        return {
            {
                text = "Alle Rezepte anzeigen",
                isSelected = (view.matsFilter == "ALL"),
                onClick = function()
                    view.matsFilter = "ALL"
                    view:RefreshData()
                end,
            },
            {
                text = "|cfffbbf24Herstellbar (Gesamte DB / Squad)|r",
                isSelected = (view.matsFilter == "DB"),
                onClick = function()
                    view.matsFilter = "DB"
                    view:RefreshData()
                end,
            },
            {
                text = "|cff38bdf8Herstellbar (Eigene Chars / Twinks)|r",
                isSelected = (view.matsFilter == "OWN"),
                onClick = function()
                    view.matsFilter = "OWN"
                    view:RefreshData()
                end,
            },
            {
                text = "|cff34d399Herstellbar (Aktiver Charakter)|r",
                isSelected = (view.matsFilter == "ACTIVE"),
                onClick = function()
                    view.matsFilter = "ACTIVE"
                    view:RefreshData()
                end,
            },
        }
    end)
    matsDropdown:SetPoint("LEFT", profDropdown, "RIGHT", 8, 0)
    view.matsDropdown = matsDropdown

    local scanBtn = UI.CreateButton(view, "Beruf scannen", 145, 26, function()
        if ns.Inventory and ns.Inventory.ScanOpenTradeSkill then
            ns.Inventory:ScanOpenTradeSkill()
            view:RefreshData()
            ns.Print("Berufsfenster inkl. Materialien gescannt & synchronisiert.")
        end
    end, true)
    scanBtn:SetPoint("TOPRIGHT", view, "TOPRIGHT", -14, -12)

    local infoLabel = view:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    infoLabel:SetPoint("TOPLEFT", view, "TOPLEFT", 14, -46)
    infoLabel:SetPoint("TOPRIGHT", view, "TOPRIGHT", -14, -46)
    infoLabel:SetJustifyH("LEFT")
    infoLabel:SetWordWrap(false)
    infoLabel:SetText("Tipp: Maus über ein Rezept halten, um alle benötigten Materialien & Lagerbestände (Du / Twinks / Freunde) zu sehen.")

    local listFrame = UI.CreateScrollList(view, 36, 11, function(listParent)
        local row = CreateFrame("Button", nil, listParent, "BackdropTemplate")
        local theme = ns.GetActiveTheme()
        UI.ApplySurface(row, theme.card, theme.border, 1)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        local recipeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        recipeText:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        recipeText:SetWidth(200)
        recipeText:SetJustifyH("LEFT")
        recipeText:SetWordWrap(false)
        row.recipeText = recipeText

        local profText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        profText:SetPoint("LEFT", recipeText, "RIGHT", 8, 0)
        profText:SetWidth(125)
        profText:SetJustifyH("LEFT")
        profText:SetWordWrap(false)
        row.profText = profText

        local matsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        matsText:SetPoint("LEFT", profText, "RIGHT", 8, 0)
        matsText:SetWidth(140)
        matsText:SetJustifyH("LEFT")
        matsText:SetWordWrap(false)
        row.matsText = matsText

        local crafterText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        crafterText:SetPoint("LEFT", matsText, "RIGHT", 8, 0)
        crafterText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        crafterText:SetJustifyH("RIGHT")
        crafterText:SetWordWrap(false)
        row.crafterText = crafterText

        row:SetScript("OnEnter", function(self)
            local t = ns.GetActiveTheme()
            UI.ApplySurface(self, t.cardHover, t.accent, 1)
            local d = self.recipeData
            if not d then return end

            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if d.itemID and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(d.itemID)
            else
                GameTooltip:SetText(d.recipeName or "Rezept", 1, 1, 1)
            end

            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff" .. t.accentHex .. "ForeverFriends · Rezept & Mats-Check|r")
            GameTooltip:AddDoubleLine("Kann hergestellt werden von:", d.craftersText or "-", 0.75, 0.80, 0.88, 1, 1, 1)

            local eval = d.matsEval
            if eval and eval.details and #eval.details > 0 then
                GameTooltip:AddDoubleLine(
                    "Herstellbar (Gesamt):",
                    string.format("|cff34d399Du: %dx|r · |cff38bdf8Twinks: %dx|r · |cfffbbf24DB: %dx|r", eval.craftableActive, eval.craftableOwn, eval.craftableDB),
                    0.75, 0.80, 0.88, 1, 1, 1
                )
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffe2e8f0Benötigte Materialien:|r")
                for _, mat in ipairs(eval.details) do
                    local colorPrefix = "|cfff87171"
                    if mat.activeHave >= mat.required then
                        colorPrefix = "|cff34d399"
                    elseif mat.ownHave >= mat.required then
                        colorPrefix = "|cff38bdf8"
                    elseif mat.dbHave >= mat.required then
                        colorPrefix = "|cfffbbf24"
                    end

                    local holderNames = {}
                    for _, h in ipairs(mat.ownList or {}) do
                        holderNames[#holderNames + 1] = string.format("%s(%d)", ns.FormatCharacterDisplay(h.name, h.class, h.faction, true), h.total)
                    end
                    for _, h in ipairs(mat.squadList or {}) do
                        holderNames[#holderNames + 1] = string.format("%s(%d)", ns.FormatCharacterDisplay(h.name, h.class, h.faction, true), h.total)
                    end
                    local holderInfo = #holderNames > 0 and (" — " .. table.concat(holderNames, ", ")) or ""

                    GameTooltip:AddDoubleLine(
                        string.format("  %dx %s", mat.required, mat.name),
                        string.format("%s%d / %d|r |cff94a3b8(Du:%d · DB:%d)|r%s", colorPrefix, mat.dbHave, mat.required, mat.activeHave, mat.dbHave, holderInfo),
                        0.90, 0.92, 0.95, 1, 1, 1
                    )
                end
            else
                GameTooltip:AddLine("|cff94a3b8Noch keine Reagenzien-Daten für dieses Rezept gespeichert. Öffne einmal das Berufsfenster im Spiel!|r", 0.6, 0.65, 0.73, true)
            end

            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            local t = ns.GetActiveTheme()
            UI.ApplySurface(self, t.card, t.border, 1)
            GameTooltip:Hide()
        end)

        return row
    end, function(row, data)
        row.recipeData = data
        row.icon:SetTexture(data.icon or "Interface\\Icons\\Trade_Engineering")
        row.recipeText:SetText("|cffffffff" .. data.recipeName .. "|r")
        row.profText:SetText(string.format("|cff38bdf8%s|r |cff94a3b8(%d/%d)|r", data.profName, data.rank or 0, data.maxRank or 0))
        row.matsText:SetText(data.matsBadgeText or "|cff64748bMats: ?|r")
        row.crafterText:SetText(data.craftersText)
    end)

    listFrame:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -66)
    listFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -10, 10)
    view.listFrame = listFrame

    function view:RefreshData()
        if not ns.db then return end
        local q = self.searchText or ""
        local aggregated = {}
        local rows = {}
        local profCounts = {}

        local function formatMatsBadge(eval)
            if not eval then
                return "|cff64748bMats: Beruf öffnen|r"
            end
            if eval.craftableActive >= 1 then
                return string.format("|cff34d399Mats: %dx (Du)|r", eval.craftableActive)
            elseif eval.craftableOwn >= 1 then
                return string.format("|cff38bdf8Mats: %dx (Twinks)|r", eval.craftableOwn)
            elseif eval.craftableDB >= 1 then
                return string.format("|cfffbbf24Mats: %dx (DB/Squad)|r", eval.craftableDB)
            else
                return string.format("|cfff87171Mats fehlen (%d/%d)|r", eval.readyDB or 0, eval.totalReagents or 0)
            end
        end

        local function collectProfessions(charRec, isOwn)
            if type(charRec) ~= "table" or type(charRec.professions) ~= "table" then return end
            local cName = charRec.name or ns.ShortName(charRec.key)
            local cFac = ns.ResolveCharacterFaction(cName, charRec.faction)
            if not ns.MatchesGlobalFilter(charRec, isOwn, cFac) then return end
            local charDisplay = ns.FormatCharacterDisplay(cName, charRec.class, cFac, true)
            for profName, prof in pairs(charRec.professions) do
                if type(prof) == "table" then
                    local recipes = prof.recipes or {}
                    local rCount = 0
                    for _ in pairs(recipes) do rCount = rCount + 1 end
                    profCounts[profName] = math.max(profCounts[profName] or 0, rCount)

                    if view.selectedProf == "ALL" or view.selectedProf == profName then
                        if not next(recipes) and view.matsFilter == "ALL" then
                            rows[#rows + 1] = {
                                recipeName = profName .. " (Berufsübersicht)",
                                profName = profName,
                                rank = prof.rank or 0,
                                maxRank = prof.maxRank or 300,
                                craftersText = charDisplay,
                                matsBadgeText = "|cff64748b-|r",
                                icon = "Interface\\Icons\\Trade_BlackSmithing",
                            }
                        else
                            for rKey, rInfo in pairs(recipes) do
                                local rName = ns.SafeString(rInfo.name, rKey)
                                local aggKey = profName .. "::" .. rName:lower()
                                local item = aggregated[aggKey]
                                if not item then
                                    local eval = (ns.Inventory and ns.Inventory.EvaluateRecipeMaterials and rInfo.reagents)
                                        and ns.Inventory:EvaluateRecipeMaterials(rInfo.reagents)
                                        or nil
                                    item = {
                                        recipeName = rName,
                                        profName = profName,
                                        rank = prof.rank or 0,
                                        maxRank = prof.maxRank or 300,
                                        itemID = rInfo.itemID,
                                        icon = rInfo.icon or "Interface\\Icons\\INV_Scroll_03",
                                        reagents = rInfo.reagents,
                                        matsEval = eval,
                                        matsBadgeText = formatMatsBadge(eval),
                                        crafters = {},
                                        crafterSeen = {},
                                        crafterRawNames = {},
                                    }
                                    aggregated[aggKey] = item
                                elseif not item.reagents and rInfo.reagents then
                                    item.reagents = rInfo.reagents
                                    item.matsEval = ns.Inventory and ns.Inventory:EvaluateRecipeMaterials(rInfo.reagents) or nil
                                    item.matsBadgeText = formatMatsBadge(item.matsEval)
                                end
                                if (prof.rank or 0) > (item.rank or 0) then
                                    item.rank = prof.rank
                                    item.maxRank = prof.maxRank or item.maxRank
                                end
                                if not item.crafterSeen[charDisplay] then
                                    item.crafterSeen[charDisplay] = true
                                    item.crafters[#item.crafters + 1] = charDisplay
                                    item.crafterRawNames[#item.crafterRawNames + 1] = (cName or ""):lower()
                                    item.craftersText = table.concat(item.crafters, ", ")
                                end
                            end
                        end
                    end
                end
            end
        end

        local myChars = ns.db.characters or {}
        for _, c in pairs(myChars) do collectProfessions(c, true) end
        for key, c in pairs(ns.db.squadCharacters or {}) do
            if not myChars[key] and not ns.IsSelfName(c.name or key) then
                collectProfessions(c, false)
            end
        end

        -- Build available professions list for the profession filter dropdown
        local profList = {}
        for pName, cnt in pairs(profCounts) do
            profList[#profList + 1] = { name = pName, count = cnt }
        end
        table.sort(profList, function(a, b) return a.name < b.name end)
        self.availableProfessions = profList
        if self.selectedProf ~= "ALL" and profCounts[self.selectedProf] == nil then
            self.selectedProf = "ALL"
        end
        if self.profDropdown and self.profDropdown.RefreshValue then
            self.profDropdown:RefreshValue()
        end
        if self.matsDropdown and self.matsDropdown.RefreshValue then
            self.matsDropdown:RefreshValue()
        end

        -- Apply search query and Mats availability filter to aggregated recipes
        for _, item in pairs(aggregated) do
            local eval = item.matsEval
            local passMats = true
            if self.matsFilter == "ACTIVE" then
                passMats = (eval ~= nil and (eval.craftableActive or 0) >= 1)
            elseif self.matsFilter == "OWN" then
                passMats = (eval ~= nil and (eval.craftableOwn or 0) >= 1)
            elseif self.matsFilter == "DB" then
                passMats = (eval ~= nil and (eval.craftableDB or 0) >= 1)
            end

            if passMats then
                local passSearch = (q == "")
                    or item.recipeName:lower():find(q, 1, true)
                    or item.profName:lower():find(q, 1, true)

                if not passSearch then
                    for _, rawC in ipairs(item.crafterRawNames or {}) do
                        if rawC:find(q, 1, true) then
                            passSearch = true
                            break
                        end
                    end
                end
                if not passSearch and eval and eval.details then
                    for _, mat in ipairs(eval.details) do
                        if mat.name and mat.name:lower():find(q, 1, true) then
                            passSearch = true
                            break
                        end
                    end
                end

                if passSearch then
                    rows[#rows + 1] = item
                end
            end
        end

        table.sort(rows, function(a, b)
            local aCraft = (a.matsEval and a.matsEval.craftableDB) or -1
            local bCraft = (b.matsEval and b.matsEval.craftableDB) or -1
            if self.matsFilter ~= "ALL" and aCraft ~= bCraft then
                return aCraft > bCraft
            end
            if a.profName ~= b.profName then return a.profName < b.profName end
            return a.recipeName < b.recipeName
        end)

        self.listFrame:SetData(rows, "Keine passenden Rezepte gefunden. Tipp: Öffne einmal dein Berufsfenster im Spiel, um Rezepte & Materialien zu scannen!")
    end

    return view
end

-- -------------------------------------------------------------------------
-- View 3: Live Squad Quest & Leveling Sync
-- -------------------------------------------------------------------------
local function BuildQuestsView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view.searchText = ""
    view.zoneOnly = false

    local searchBox = UI.CreateSearchBox(view, 260, 26, "Quest oder Gebiet suchen...", function(txt)
        view.searchText = txt or ""
        view:RefreshData()
    end)
    searchBox:SetPoint("TOPLEFT", view, "TOPLEFT", 12, -12)

    local zoneToggle = UI.CreateCheckBox(
        view,
        "Nur aktuelles Gebiet anzeigen",
        "Filtert die Questliste auf das Gebiet, in dem du dich gerade befindest.",
        function() return view.zoneOnly end,
        function(val)
            view.zoneOnly = val
            view:RefreshData()
        end
    )
    zoneToggle:SetPoint("TOPLEFT", view, "TOPLEFT", 288, -13)

    local syncBtn = UI.CreateButton(view, "Questlog jetzt abgleichen", 170, 26, function()
        if ns.Quests then
            ns.Quests:ScanQuestLog(false)
            ns.Quests:BroadcastQuests()
            view:RefreshData()
            ns.Print("Questlog gescannt & mit deinen Freunden abgeglichen.")
        end
    end, true)
    syncBtn:SetPoint("TOPRIGHT", view, "TOPRIGHT", -14, -12)

    local listFrame = UI.CreateScrollList(view, 44, 9, function(listParent)
        local row = CreateFrame("Frame", nil, listParent, "BackdropTemplate")
        local theme = ns.GetActiveTheme()
        UI.ApplySurface(row, theme.card, theme.border, 1)

        local titleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -5)
        titleText:SetWidth(290)
        titleText:SetJustifyH("LEFT")
        row.titleText = titleText

        local zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        zoneText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 5)
        zoneText:SetJustifyH("LEFT")
        row.zoneText = zoneText

        local holdersText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        holdersText:SetPoint("TOPLEFT", row, "TOPLEFT", 305, -5)
        holdersText:SetPoint("RIGHT", row, "RIGHT", -95, 0)
        holdersText:SetJustifyH("LEFT")
        row.holdersText = holdersText

        local missingText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        missingText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 305, 5)
        missingText:SetPoint("RIGHT", row, "RIGHT", -95, 0)
        missingText:SetJustifyH("LEFT")
        row.missingText = missingText

        local shareBtn = UI.CreateButton(row, "Teilen", 74, 24, function(self)
            local d = self:GetParent().questData
            if d and ns.Quests then
                ns.Quests:ShareQuest(d.key)
            end
        end)
        shareBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.shareBtn = shareBtn

        return row
    end, function(row, data)
        row.questData = data
        local lvlPrefix = (data.level and data.level > 0) and string.format("|cff94a3b8[%d]|r ", data.level) or ""
        row.titleText:SetText(lvlPrefix .. "|cffffd100" .. data.title .. "|r")
        row.zoneText:SetText("|cff38bdf8" .. (data.zone or "Allgemein") .. "|r")

        local holderParts = {}
        for _, h in ipairs(data.holders or {}) do
            holderParts[#holderParts + 1] = string.format("%s (%s)", ns.FormatCharacterDisplay(h.name, h.class, h.faction, true), h.progressText)
        end
        row.holdersText:SetText(table.concat(holderParts, "  ·  "))

        if data.missingPlayers and #data.missingPlayers > 0 then
            local missNames = {}
            for _, mp in ipairs(data.missingPlayers) do
                missNames[#missNames + 1] = ns.FormatCharacterDisplay(mp.name, mp.class, mp.faction, true)
            end
            row.missingText:SetText("|cfff87171Fehlt noch:|r " .. table.concat(missNames, ", "))
        else
            row.missingText:SetText("|cff34d399Alle aktiven Freunde (gleiche Fraktion) haben diese Quest|r")
        end

        if data.iHaveIt then
            row.shareBtn:Show()
        else
            row.shareBtn:Hide()
        end
    end)

    listFrame:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -48)
    listFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -10, 10)
    view.listFrame = listFrame

    function view:RefreshData()
        if not ns.Quests then return end
        local list = ns.Quests:GetAggregatedQuests(self.searchText, self.zoneOnly)
        self.listFrame:SetData(list, "Keine aktiven Quests für diesen Filter gefunden.")
    end

    return view
end

-- -------------------------------------------------------------------------
-- View 4: World Radar, Squad Roster & Group QoL
-- Distinguishes between permanent Friends/Squad Roster and temporary Group
-- members, and allows removing any entry (online or offline) at any time.
-- -------------------------------------------------------------------------
local function BuildRadarView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()
    view.relFilter = "ALL" -- "ALL", "FRIENDS_ONLY", "GROUP_ONLY"

    local nameInput = UI.CreateSearchBox(view, 165, 26, "Freund-Name eingeben...", nil)
    nameInput:SetPoint("TOPLEFT", view, "TOPLEFT", 12, -12)

    local addBtn = UI.CreateButton(view, "+ Stammgruppe", 112, 26, function()
        local txt = strtrim(nameInput:GetText() or "")
        if txt ~= "" and not ns.IsSelfName(txt) then
            ns.AddToSquadRoster(txt)
            nameInput:SetText("")
            nameInput:ClearFocus()
            view:RefreshData()
        end
    end, true)
    addBtn:SetPoint("LEFT", nameInput, "RIGHT", 6, 0)

    local REL_LABELS = {
        ALL          = "|cffe2e8f0Zeige: Alle|r",
        FRIENDS_ONLY = "|cff34d399Nur Freunde / Stamm|r",
        GROUP_ONLY   = "|cfffbbf24Nur aktuelle Gruppe|r",
    }
    local relDropdown = UI.CreateDropdown(view, 155, 26, function()
        return REL_LABELS[view.relFilter] or REL_LABELS.ALL
    end, function()
        return {
            {
                text = "Alle anzeigen (Freunde & Gruppe)",
                isSelected = (view.relFilter == "ALL"),
                onClick = function()
                    view.relFilter = "ALL"
                    view:RefreshData()
                end,
            },
            {
                text = "|cff34d399Nur Stammgruppe & Freundesliste|r",
                isSelected = (view.relFilter == "FRIENDS_ONLY"),
                onClick = function()
                    view.relFilter = "FRIENDS_ONLY"
                    view:RefreshData()
                end,
            },
            {
                text = "|cfffbbf24Nur aktuelle Gruppe (inkl. Randoms)|r",
                isSelected = (view.relFilter == "GROUP_ONLY"),
                onClick = function()
                    view.relFilter = "GROUP_ONLY"
                    view:RefreshData()
                end,
            },
        }
    end)
    relDropdown:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    view.relDropdown = relDropdown

    local inviteAllBtn = UI.CreateButton(view, "Stamm Einladen", 104, 26, function()
        if ns.InviteSquadMembers then ns.InviteSquadMembers() end
    end)
    inviteAllBtn:SetPoint("LEFT", relDropdown, "RIGHT", 8, 0)

    local buffCheckBtn = UI.CreateButton(view, "Buffs", 56, 26, function()
        if ns.QoL and ns.QoL.RunBuffCheck then ns.QoL:RunBuffCheck() end
    end)
    buffCheckBtn:SetPoint("LEFT", inviteAllBtn, "RIGHT", 6, 0)

    local sosBtn = UI.CreateButton(view, "SOS!", 58, 26, function()
        if ns.Radar and ns.Radar.SendSOSAlert then
            ns.Radar:SendSOSAlert("Brauche Hilfe an meiner Position!")
        end
    end)
    sosBtn:SetPoint("TOPRIGHT", view, "TOPRIGHT", -14, -12)

    local lockoutInfo = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lockoutInfo:SetPoint("TOPLEFT", view, "TOPLEFT", 14, -46)
    view.lockoutInfo = lockoutInfo

    local listFrame = UI.CreateScrollList(view, 40, 10, function(listParent)
        local row = CreateFrame("Frame", nil, listParent, "BackdropTemplate")
        local theme = ns.GetActiveTheme()
        UI.ApplySurface(row, theme.card, theme.border, 1)

        local statusDot = row:CreateTexture(nil, "OVERLAY")
        statusDot:SetSize(10, 10)
        statusDot:SetPoint("LEFT", row, "LEFT", 10, 0)
        statusDot:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.statusDot = statusDot

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", statusDot, "RIGHT", 8, 0)
        nameText:SetWidth(220)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        row.nameText = nameText

        local locText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        locText:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
        locText:SetWidth(165)
        locText:SetJustifyH("LEFT")
        locText:SetWordWrap(false)
        row.locText = locText

        local vitalsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        vitalsText:SetPoint("LEFT", locText, "RIGHT", 6, 0)
        vitalsText:SetWidth(105)
        vitalsText:SetJustifyH("LEFT")
        vitalsText:SetWordWrap(false)
        row.vitalsText = vitalsText

        -- Always-available Remove ('×') button on the far right (works for both online & offline entries!)
        local delBtn = UI.CreateButton(row, "×", 26, 24, function(self)
            local d = self:GetParent().peerData
            if d and (d.shortName or d.name) then
                ns.RemoveFromSquadRoster(d.shortName or d.name)
                view:RefreshData()
            end
        end)
        delBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        delBtn:SetScript("OnEnter", function(self)
            local t = ns.GetActiveTheme()
            UI.ApplySurface(self, t.danger, t.border, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Aus Liste & Datenbank entfernen", 1, 0.35, 0.35)
            GameTooltip:AddLine("Entfernt diesen Charakter aus der Stammgruppe, dem Radar sowie den gecachten Inventar-/Quest-Daten.", 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        delBtn:SetScript("OnLeave", function(self)
            self:RefreshStyle()
            GameTooltip:Hide()
        end)
        row.delBtn = delBtn

        -- Action button 1 (Invite to group OR '+ Stamm' if not yet in squadRoster)
        local invBtn = UI.CreateButton(row, "Einladen", 68, 24, function(self)
            local d = self:GetParent().peerData
            if not d or not d.shortName then return end
            if d.inGroup and not d.isSquadRoster then
                -- Already in group, so button promotes them to permanent Squad Roster!
                ns.AddToSquadRoster(d.shortName)
                view:RefreshData()
            elseif d.isOnline then
                if C_PartyInfo and C_PartyInfo.InviteUnit then
                    pcall(C_PartyInfo.InviteUnit, d.shortName)
                elseif InviteUnit then
                    pcall(InviteUnit, d.shortName)
                end
            end
        end)
        invBtn:SetPoint("RIGHT", delBtn, "LEFT", -5, 0)
        row.invBtn = invBtn

        -- Map Waypoint Pin button
        local pinBtn = UI.CreateButton(row, "Pin", 46, 24, function(self)
            local d = self:GetParent().peerData
            if d and d.mapID and d.x then
                ns.SetMapWaypoint(d.mapID, d.x, d.y, d.shortName or d.name)
            end
        end)
        pinBtn:SetPoint("RIGHT", invBtn, "LEFT", -5, 0)
        row.pinBtn = pinBtn

        return row
    end, function(row, data)
        row.peerData = data
        if data.isOnline then
            row.statusDot:SetVertexColor(0.20, 0.83, 0.60, 1)
        else
            row.statusDot:SetVertexColor(0.45, 0.50, 0.58, 1)
        end

        local lvlStr = (data.level and data.level > 0) and string.format(" |cff94a3b8Lv%d|r", data.level) or ""
        local relBadge = data.relBadge and (" " .. data.relBadge) or ""
        row.nameText:SetText(ns.FormatCharacterDisplay(data.shortName or data.name, data.class, data.faction, true) .. lvlStr .. relBadge)

        row.delBtn:Show()

        if data.isOnline then
            local coord = (data.x and data.x > 0) and string.format(" |cff38bdf8(%.1f, %.1f)|r", data.x * 100, data.y * 100) or ""
            row.locText:SetText((data.zone or "Online") .. coord)
            row.vitalsText:SetText(string.format("LP: %d%% · IDs: %d/5", data.hpPct or 100, data.lockouts or 0))
            if data.mapID and data.x and data.x > 0 then
                row.pinBtn:Show()
            else
                row.pinBtn:Hide()
            end

            if data.inGroup and not data.isSquadRoster then
                row.invBtn.label:SetText("+ Merken")
                row.invBtn:Show()
            elseif not data.inGroup then
                row.invBtn.label:SetText("Einladen")
                row.invBtn:Show()
            else
                row.invBtn:Hide()
            end
        else
            row.locText:SetText("|cff64748bOffline|r")
            row.vitalsText:SetText(ns.FormatTimeAgo(data.lastSeen))
            row.pinBtn:Hide()
            row.invBtn:Hide()
        end
    end)

    listFrame:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -66)
    listFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -10, 10)
    view.listFrame = listFrame

    function view:RefreshData()
        local loCount, nextFree = 0, nil
        if ns.QoL and ns.QoL.GetActiveLockoutCount then
            loCount, nextFree = ns.QoL:GetActiveLockoutCount()
        end
        local freeStr = nextFree and string.format(" (Nächste ID frei in %d Min.)", math.ceil(nextFree / 60)) or ""

        self.lockoutInfo:SetText(string.format(
            "Deine Instanz-IDs: |cff38bdf8%d/5|r%s  ·  Legende: |cff34d399[Stammgruppe]|r / |cff38bdf8[Freund]|r vs. |cfffbbf24[Nur Gruppe]|r  ·  |cfff87171[×]|r = Aus Liste entfernen",
            loCount, freeStr
        ))

        if self.relDropdown and self.relDropdown.RefreshValue then
            self.relDropdown:RefreshValue()
        end

        local entries = {}
        local seenShorts = {}
        local now = time()
        local confirmedOnline = (ns.Sync and ns.Sync.GetConfirmedOnlineFriends and ns.Sync:GetConfirmedOnlineFriends()) or {}

        local function tryPushEntry(rawEntry)
            local short = rawEntry.shortName
            local relKind, relBadge, isFriendOrSquad, inGroup = ns.GetPeerRelationship(short, rawEntry.peerRef)
            rawEntry.relKind = relKind
            rawEntry.relBadge = relBadge
            rawEntry.isFriendOrSquad = isFriendOrSquad
            rawEntry.isSquadRoster = ns.IsInSquadRoster(short)
            rawEntry.inGroup = inGroup

            if self.relFilter == "FRIENDS_ONLY" and not isFriendOrSquad then
                return
            elseif self.relFilter == "GROUP_ONLY" and not inGroup then
                return
            end

            if ns.MatchesGlobalFilter(rawEntry, false, rawEntry.faction) then
                entries[#entries + 1] = rawEntry
            end
        end

        -- 1. Live onlinePeers
        for _, peer in pairs(ns.onlinePeers or {}) do
            local short = ns.ShortName(peer.shortName or peer.name)
            local lower = short:lower()
            if lower ~= "" and lower ~= "unbekannt" and not ns.IsSelfName(short) and not ns.IsDismissedPeer(short) then
                seenShorts[lower] = true
                local pFac = ns.ResolveCharacterFaction(short, peer.faction)
                tryPushEntry({
                    peerRef = peer,
                    name = peer.name,
                    shortName = short,
                    class = peer.class or "WARRIOR",
                    faction = pFac,
                    level = peer.level or 1,
                    zone = peer.zone,
                    mapID = peer.mapID,
                    x = peer.x,
                    y = peer.y,
                    hpPct = peer.hpPct or 100,
                    lockouts = peer.lockouts or 0,
                    lastSeen = peer.lastSeen or 0,
                    isOnline = ((now - (peer.lastSeen or 0)) < 600) or (confirmedOnline[lower] ~= nil),
                })
            end
        end

        -- 2. Saved Squad Roster members (even if offline)
        for rosterName in pairs(ns.db and ns.db.squadRoster or {}) do
            local short = ns.ShortName(rosterName)
            local lower = short:lower()
            if lower ~= "" and not ns.IsSelfName(short) and not seenShorts[lower] then
                seenShorts[lower] = true
                local rFac = ns.ResolveCharacterFaction(short)
                local cachedChar = nil
                for _, sc in pairs(ns.db and ns.db.squadCharacters or {}) do
                    if ns.ShortName(sc.name or sc.key):lower() == lower then
                        cachedChar = sc
                        break
                    end
                end
                tryPushEntry({
                    name = short,
                    shortName = short,
                    class = (cachedChar and cachedChar.class) or "PRIEST",
                    faction = rFac,
                    level = (cachedChar and cachedChar.level) or 0,
                    isOnline = (confirmedOnline[lower] ~= nil),
                    lastSeen = (cachedChar and cachedChar.updatedAt) or 0,
                })
            end
        end

        -- 3. Any other cached squadCharacters in DB (so you can see and delete old cached characters too!)
        for key, sc in pairs(ns.db and ns.db.squadCharacters or {}) do
            local short = ns.ShortName(sc.name or key)
            local lower = short:lower()
            if lower ~= "" and lower ~= "unbekannt" and not ns.IsSelfName(short) and not seenShorts[lower] and not ns.IsDismissedPeer(short) then
                seenShorts[lower] = true
                local sFac = ns.ResolveCharacterFaction(short, sc.faction)
                tryPushEntry({
                    name = short,
                    shortName = short,
                    class = sc.class or "WARRIOR",
                    faction = sFac,
                    level = sc.level or 0,
                    isOnline = (confirmedOnline[lower] ~= nil),
                    lastSeen = sc.updatedAt or 0,
                })
            end
        end

        table.sort(entries, function(a, b)
            -- Sort Friends/Squad Roster above temporary group members
            if a.isFriendOrSquad ~= b.isFriendOrSquad then return a.isFriendOrSquad end
            if a.isOnline ~= b.isOnline then return a.isOnline end
            return (a.shortName or "") < (b.shortName or "")
        end)

        self.listFrame:SetData(entries, "Keine Einträge für diesen Filter. Füge oben deine Freunde per Namen zur Stammgruppe hinzu!")
    end

    return view
end

-- -------------------------------------------------------------------------
-- View 5: Squad Hall of Fame / Statistics
-- -------------------------------------------------------------------------
local function BuildStatsView(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetAllPoints()

    local headerNote = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    headerNote:SetPoint("TOPLEFT", view, "TOPLEFT", 14, -16)
    headerNote:SetText("Ewige Stammgruppen-Bestenliste — Automatisch synchronisiert zwischen euren Charakteren:")

    local listFrame = UI.CreateScrollList(view, 38, 11, function(listParent)
        local row = CreateFrame("Frame", nil, listParent, "BackdropTemplate")
        local theme = ns.GetActiveTheme()
        UI.ApplySurface(row, theme.card, theme.border, 1)

        local rankText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rankText:SetPoint("LEFT", row, "LEFT", 10, 0)
        rankText:SetWidth(28)
        row.rankText = rankText

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", rankText, "RIGHT", 6, 0)
        nameText:SetWidth(180)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local deathsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        deathsText:SetPoint("LEFT", nameText, "RIGHT", 10, 0)
        deathsText:SetWidth(100)
        deathsText:SetJustifyH("LEFT")
        row.deathsText = deathsText

        local repairText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        repairText:SetPoint("LEFT", deathsText, "RIGHT", 10, 0)
        repairText:SetWidth(145)
        repairText:SetJustifyH("LEFT")
        row.repairText = repairText

        local questsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        questsText:SetPoint("LEFT", repairText, "RIGHT", 10, 0)
        questsText:SetWidth(115)
        questsText:SetJustifyH("LEFT")
        row.questsText = questsText

        local rollsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rollsText:SetPoint("RIGHT", row, "RIGHT", -12, 0)
        rollsText:SetJustifyH("RIGHT")
        row.rollsText = rollsText

        return row
    end, function(row, data, idx)
        row.rankText:SetText("|cff94a3b8#" .. idx .. "|r")
        row.nameText:SetText(ns.FormatCharacterDisplay(data.name, data.class, data.faction, true))
        row.deathsText:SetText(string.format("|cfff87171Tode: %d|r", data.deaths))
        row.repairText:SetText("Rep: " .. ns.FormatMoney(data.repairCopper, true))
        row.questsText:SetText(string.format("|cff34d399Quests: %d|r", data.questsCompleted))
        row.rollsText:SetText(string.format("|cffffd100100er: %d|r · |cff94a3b81er: %d|r", data.highRolls, data.onesRolled))
    end)

    listFrame:SetPoint("TOPLEFT", view, "TOPLEFT", 10, -44)
    listFrame:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -10, 10)
    view.listFrame = listFrame

    function view:RefreshData()
        if not ns.db then return end
        local list = {}
        local seen = {}

        local function addChar(c, isOwn)
            if type(c) ~= "table" or not c.key or seen[c.key] then return end
            local cFac = ns.ResolveCharacterFaction(c.name or c.key, c.faction)
            if not ns.MatchesGlobalFilter(c, isOwn, cFac) then return end
            seen[c.key] = true
            local st = c.stats or {}
            list[#list + 1] = {
                name = c.name or ns.ShortName(c.key),
                class = c.class or "WARRIOR",
                faction = cFac,
                deaths = ns.SafeNumber(st.deaths, 0),
                repairCopper = ns.SafeNumber(st.repairCopper, 0),
                questsCompleted = ns.SafeNumber(st.questsCompleted, 0),
                highRolls = ns.SafeNumber(st.highRolls, 0),
                onesRolled = ns.SafeNumber(st.onesRolled, 0),
            }
        end

        for _, c in pairs(ns.db.characters or {}) do addChar(c, true) end
        for _, c in pairs(ns.db.squadCharacters or {}) do addChar(c, false) end

        table.sort(list, function(a, b)
            if a.questsCompleted ~= b.questsCompleted then return a.questsCompleted > b.questsCompleted end
            return a.deaths > b.deaths
        end)

        self.listFrame:SetData(list, "Noch keine Statistiken aufgezeichnet.")
    end

    return view
end

-- -------------------------------------------------------------------------
-- Main Window Construction (Movable, Scalable, Themeable, Taint-Free)
-- -------------------------------------------------------------------------
local function EnsureMainFrame()
    if mainFrame then return mainFrame end
    local cfg = (ns.db and ns.db.ui) or ns.DEFAULTS.ui

    mainFrame = CreateFrame("Frame", "ForeverFriendsMainFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(cfg.width or 920, cfg.height or 600)
    mainFrame:SetPoint(cfg.point or "CENTER", UIParent, cfg.relPoint or "CENTER", cfg.x or 0, cfg.y or 0)
    mainFrame:SetScale(ns.SafeNumber(cfg.scale, 1.0))
    mainFrame:SetAlpha(ns.SafeNumber(cfg.alpha, 0.96))
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetToplevel(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")

    mainFrame:SetScript("OnDragStart", function(self)
        if not (ns.db and ns.db.ui and ns.db.ui.locked) then
            self:StartMoving()
        end
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.db and ns.db.ui then
            local p, _, rp, x, y = self:GetPoint()
            ns.db.ui.point = p
            ns.db.ui.relPoint = rp
            ns.db.ui.x = x
            ns.db.ui.y = y
        end
    end)

    -- Top Header Bar
    local header = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(42)
    mainFrame.header = header

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", header, "LEFT", 12, 0)
    logo:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Media\\logo")
    logo:SetTexCoord(0.04, 0.96, 0.04, 0.96)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    mainFrame.title = title

    local onlineDot = header:CreateTexture(nil, "OVERLAY")
    onlineDot:SetSize(8, 8)
    onlineDot:SetPoint("LEFT", title, "RIGHT", 16, 0)
    onlineDot:SetColorTexture(0.20, 0.83, 0.60, 1.0)
    mainFrame.onlineDot = onlineDot

    local onlineBadge = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    onlineBadge:SetPoint("LEFT", onlineDot, "RIGHT", 6, 0)
    mainFrame.onlineBadge = onlineBadge

    -- Close Button
    local closeBtn = UI.CreateButton(header, "×", 28, 26, function()
        mainFrame:Hide()
    end)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)

    -- Lock/Unlock Window Button
    local lockBtn = UI.CreateButton(header, "", 76, 26, function(self)
        if ns.db and ns.db.ui then
            ns.db.ui.locked = not ns.db.ui.locked
            self.label:SetText(ns.db.ui.locked and "Gesperrt" or "Frei")
        end
    end)
    lockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    lockBtn.label:SetText(cfg.locked and "Gesperrt" or "Frei")
    mainFrame.lockBtn = lockBtn

    -- Quick Scale - / + Buttons in Header
    local scalePlusBtn = UI.CreateButton(header, "A+", 30, 26, function()
        if ns.db and ns.db.ui then
            local s = math.min(1.50, (ns.db.ui.scale or 1.0) + 0.05)
            ns.db.ui.scale = s
            mainFrame:SetScale(s)
        end
    end)
    scalePlusBtn:SetPoint("RIGHT", lockBtn, "LEFT", -6, 0)

    local scaleMinusBtn = UI.CreateButton(header, "A-", 30, 26, function()
        if ns.db and ns.db.ui then
            local s = math.max(0.65, (ns.db.ui.scale or 1.0) - 0.05)
            ns.db.ui.scale = s
            mainFrame:SetScale(s)
        end
    end)
    scaleMinusBtn:SetPoint("RIGHT", scalePlusBtn, "LEFT", -4, 0)

    -- Quick Sync Button in Header
    local syncNowBtn = UI.CreateButton(header, "Sync Senden", 96, 26, function()
        if ns.Sync and ns.Sync.BroadcastFullState then
            ns.Sync:BroadcastFullState(true)
        end
        mainFrame:RefreshActiveView()
    end, true)
    syncNowBtn:SetPoint("RIGHT", scaleMinusBtn, "LEFT", -8, 0)

    -- Left Navigation Sidebar
    local sidebar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 1, -43)
    sidebar:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(182)
    mainFrame.sidebar = sidebar

    -- Main Content Container
    local content = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 1, 0)
    content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -1, 1)
    if content.SetClipsChildren then
        content:SetClipsChildren(true)
    end
    mainFrame.content = content

    -- Global Faction & Character Filter Bar (shared across all data tabs)
    local filterBar = CreateFrame("Frame", nil, content, "BackdropTemplate")
    filterBar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    filterBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    filterBar:SetHeight(36)
    mainFrame.filterBar = filterBar

    local facLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    facLabel:SetPoint("LEFT", filterBar, "LEFT", 12, 0)
    facLabel:SetText("Fraktion:")

    local FACTION_BTNS = {
        { id = "ALL",      label = "Alle",          width = 48 },
        { id = "Horde",    label = "|cfff87171[H]|r Horde",   width = 74 },
        { id = "Alliance", label = "|cff60a5fa[A]|r Allianz", width = 78 },
        { id = "OWN",      label = "Eigene",        width = 58 },
    }
    filterBar.factionButtons = {}
    local prevFacBtn
    for _, fb in ipairs(FACTION_BTNS) do
        local fBtn = UI.CreateButton(filterBar, fb.label, fb.width, 22, function()
            ns.SetGlobalFilter(fb.id, nil)
        end)
        if not prevFacBtn then
            fBtn:SetPoint("LEFT", facLabel, "RIGHT", 6, 0)
        else
            fBtn:SetPoint("LEFT", prevFacBtn, "RIGHT", 4, 0)
        end
        fBtn.factionId = fb.id
        filterBar.factionButtons[fb.id] = fBtn
        prevFacBtn = fBtn
    end

    local charLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charLabel:SetPoint("LEFT", prevFacBtn, "RIGHT", 14, 0)
    charLabel:SetText("Charakter:")

    local charDropdown = UI.CreateDropdown(filterBar, 225, 22, function()
        local f = ns.GetGlobalFilter()
        local cf = f.char or "ALL"
        if cf == "ALL" then
            return "|cffe2e8f0Alle Charaktere|r"
        elseif cf == "ACTIVE" then
            return ns.FormatCharacterDisplay(ns.GetPlayerShortName(), ns.GetPlayerClass(), ns.GetPlayerFaction(), true) .. " |cff94a3b8(Aktiv)|r"
        elseif cf == "OWN_CHARS" then
            return "|cff38bdf8Nur eigene Charaktere (Twinks)|r"
        elseif cf == "FRIENDS_ONLY" then
            return "|cff34d399Nur Freunde (Stammgruppe)|r"
        elseif cf:sub(1, 5) == "CHAR:" then
            local targetShort = cf:sub(6)
            for _, c in ipairs(ns.GetAllKnownCharacters(false)) do
                if c.shortName:lower() == targetShort:lower() then
                    return ns.FormatCharacterDisplay(c.shortName, c.class, c.faction, true)
                end
            end
            return targetShort
        end
        return "Alle Charaktere"
    end, function()
        local f = ns.GetGlobalFilter()
        local cur = f.char or "ALL"
        local items = {
            {
                text = "Alle Charaktere anzeigen",
                isSelected = (cur == "ALL"),
                onClick = function() ns.SetGlobalFilter(nil, "ALL") end,
            },
            {
                text = "Nur aktiver Charakter (" .. ns.FormatCharacterDisplay(ns.GetPlayerShortName(), ns.GetPlayerClass(), ns.GetPlayerFaction(), true) .. ")",
                isSelected = (cur == "ACTIVE"),
                onClick = function() ns.SetGlobalFilter(nil, "ACTIVE") end,
            },
            {
                text = "|cff38bdf8Alle eigenen Charaktere (Twinks)|r",
                isSelected = (cur == "OWN_CHARS"),
                onClick = function() ns.SetGlobalFilter(nil, "OWN_CHARS") end,
            },
            {
                text = "|cff34d399Nur Freunde (Stammgruppe)|r",
                isSelected = (cur == "FRIENDS_ONLY"),
                onClick = function() ns.SetGlobalFilter(nil, "FRIENDS_ONLY") end,
            },
        }

        local known = ns.GetAllKnownCharacters(true)
        local ownAdded, friendAdded = false, false
        for _, c in ipairs(known) do
            if c.isOwn and not ownAdded then
                ownAdded = true
                items[#items + 1] = { isHeader = true, text = "Eigene Charaktere" }
            elseif not c.isOwn and not friendAdded then
                friendAdded = true
                items[#items + 1] = { isHeader = true, text = "Freunde & Stammgruppe" }
            end
            local val = "CHAR:" .. c.shortName
            local lvlInfo = (c.level and c.level > 0) and string.format(" |cff64748bLv %d|r", c.level) or ""
            items[#items + 1] = {
                text = ns.FormatCharacterDisplay(c.shortName, c.class, c.faction, true) .. lvlInfo,
                isSelected = (cur:lower() == val:lower()),
                onClick = function() ns.SetGlobalFilter(nil, val) end,
            }
        end
        return items
    end)
    charDropdown:SetPoint("LEFT", charLabel, "RIGHT", 6, 0)
    filterBar.charDropdown = charDropdown

    local resetFilterBtn = UI.CreateButton(filterBar, "Reset", 50, 22, function()
        ns.SetGlobalFilter("ALL", "ALL")
    end)
    resetFilterBtn:SetPoint("RIGHT", filterBar, "RIGHT", -10, 0)
    filterBar.resetFilterBtn = resetFilterBtn

    function filterBar:RefreshFilterState()
        local f = ns.GetGlobalFilter()
        for id, btn in pairs(self.factionButtons) do
            btn.isActive = (f.faction == id)
            btn:RefreshStyle()
        end
        if self.charDropdown and self.charDropdown.RefreshLabel then
            self.charDropdown:RefreshLabel()
        end
        if (f.faction ~= "ALL") or (f.char ~= "ALL") then
            self.resetFilterBtn:Show()
        else
            self.resetFilterBtn:Hide()
        end
    end

    -- Host frame below the global filter bar for all data tabs
    local viewHost = CreateFrame("Frame", nil, content)
    viewHost:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -36)
    viewHost:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    mainFrame.viewHost = viewHost

    -- Corner Drag-Scale Handle (Bottom-Right)
    local scaler = CreateFrame("Button", nil, mainFrame)
    scaler:SetSize(18, 18)
    scaler:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
    scaler:SetFrameLevel(mainFrame:GetFrameLevel() + 20)
    local scalerTex = scaler:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scalerTex:SetPoint("BOTTOMRIGHT", -2, 2)
    scalerTex:SetText("◢")

    scaler:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Fenster skalieren", 1, 1, 1)
        GameTooltip:AddLine("Ziehen mit gedrückter Maustaste, um das gesamte UI stufenlos zu skalieren.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    scaler:SetScript("OnLeave", function() GameTooltip:Hide() end)
    scaler:SetScript("OnMouseDown", function(self)
        if ns.db and ns.db.ui and ns.db.ui.locked then return end
        self.startX = select(1, GetCursorPosition())
        self.startScale = mainFrame:GetScale() or 1.0
        self:SetScript("OnUpdate", function(s)
            local curX = select(1, GetCursorPosition())
            local delta = (curX - (s.startX or curX)) / 600
            local newScale = math.max(0.65, math.min(1.50, (s.startScale or 1.0) + delta))
            newScale = math.floor(newScale * 20 + 0.5) / 20
            mainFrame:SetScale(newScale)
            if ns.db and ns.db.ui then
                ns.db.ui.scale = newScale
            end
        end)
    end)
    scaler:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if mainFrame.views and mainFrame.views.SETTINGS and mainFrame.views.SETTINGS.RefreshData then
            mainFrame.views.SETTINGS:RefreshData()
        end
    end)

    -- Create Views & Navigation Buttons
    mainFrame.tabButtons = {}
    mainFrame.views = {
        INVENTORY   = BuildInventoryView(viewHost),
        PROFESSIONS = BuildProfessionsView(viewHost),
        QUESTS      = BuildQuestsView(viewHost),
        RADAR       = BuildRadarView(viewHost),
        STATS       = BuildStatsView(viewHost),
    }
    if ns.BuildSettingsView then
        mainFrame.views.SETTINGS = ns.BuildSettingsView(content)
    end

    for i, tabInfo in ipairs(TABS) do
        local btn = UI.CreateButton(sidebar, "", 166, 34, function()
            mainFrame:SelectTab(tabInfo.id)
        end)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -12 - (i - 1) * 40)
        btn.label:ClearAllPoints()
        btn.label:SetPoint("LEFT", btn, "LEFT", 10, 0)
        btn.label:SetText(tabInfo.label)

        local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        badge:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        badge:SetText(tabInfo.badge)
        btn.badge = badge
        btn.tabId = tabInfo.id

        mainFrame.tabButtons[tabInfo.id] = btn
    end

    local footerInfo = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerInfo:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 10, 12)
    footerInfo:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -10, 12)
    footerInfo:SetJustifyH("LEFT")
    footerInfo:SetText("ForeverFriends v" .. ns.VERSION .. "\nWoW: Forever (16001)\n/ff · /squad")

    function mainFrame:SelectTab(tabId)
        tabId = tabId or "INVENTORY"
        if ns.db and ns.db.ui then
            ns.db.ui.activeTab = tabId
        end
        if self.filterBar then
            if tabId == "SETTINGS" then
                self.filterBar:Hide()
                self.viewHost:Hide()
            else
                self.filterBar:Show()
                self.viewHost:Show()
                self.filterBar:RefreshFilterState()
            end
        end
        for id, view in pairs(self.views) do
            if id == tabId then
                view:Show()
                if view.RefreshData then view:RefreshData() end
            else
                view:Hide()
            end
        end
        for id, btn in pairs(self.tabButtons) do
            btn.isActive = (id == tabId)
            btn:RefreshStyle()
        end
    end

    function mainFrame:RefreshActiveView()
        local onlineCount = 0
        local now = time()
        local myShortLower = ns.GetPlayerShortName():lower()
        for _, peer in pairs(ns.onlinePeers or {}) do
            local pShort = ns.ShortName(peer.shortName or peer.name or ""):lower()
            if pShort ~= "" and pShort ~= "unbekannt" and pShort ~= myShortLower and (now - (peer.lastSeen or 0)) < 600 then
                onlineCount = onlineCount + 1
            end
        end
        if onlineCount > 0 then
            self.onlineDot:SetColorTexture(0.20, 0.83, 0.60, 1.0)
            self.onlineBadge:SetText(string.format("|cff34d399%d Freunde aktiv|r", onlineCount))
        else
            self.onlineDot:SetColorTexture(0.45, 0.50, 0.58, 1.0)
            self.onlineBadge:SetText("|cff94a3b80 Freunde aktiv|r")
        end

        if self.filterBar and self.filterBar:IsShown() then
            self.filterBar:RefreshFilterState()
        end

        local active = (ns.db and ns.db.ui and ns.db.ui.activeTab) or "INVENTORY"
        local view = self.views[active]
        if view and view:IsShown() and view.RefreshData then
            view:RefreshData()
        end
    end

    function mainFrame:ApplyTheme()
        local theme = ns.GetActiveTheme()
        UI.ApplySurface(self, theme.bg, theme.border, 1)
        UI.ApplySurface(self.header, theme.header, theme.border, 1)
        UI.ApplySurface(self.sidebar, theme.panel, theme.border, 1)
        UI.ApplySurface(self.content, theme.bg, theme.border, 1)
        if self.filterBar then
            UI.ApplySurface(self.filterBar, theme.panel, theme.border, 1)
            self.filterBar:RefreshFilterState()
        end
        self.title:SetText("|cff" .. theme.accentHex .. "ForeverFriends|r |cffe2e8f0Squad Hub|r")

        for _, btn in pairs(self.tabButtons) do
            btn:RefreshStyle()
        end
        self:RefreshActiveView()
    end

    ns.MainFrame = mainFrame
    ns.RefreshMainFrameTheme = function()
        if mainFrame then mainFrame:ApplyTheme() end
    end

    mainFrame:ApplyTheme()
    mainFrame:SelectTab((ns.db and ns.db.ui and ns.db.ui.activeTab) or "INVENTORY")
    mainFrame:Hide()
    return mainFrame
end

function ns.ToggleMainFrame(forceTab)
    local frame = EnsureMainFrame()
    if forceTab then
        frame:Show()
        frame:SelectTab(forceTab)
        frame:RefreshActiveView()
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        frame:RefreshActiveView()
    end
end

local function OnDataUpdated()
    if mainFrame and mainFrame:IsShown() then
        mainFrame:RefreshActiveView()
    end
end

ns.RegisterMessage("INVENTORY_UPDATED", OnDataUpdated)
ns.RegisterMessage("PROFESSIONS_UPDATED", OnDataUpdated)
ns.RegisterMessage("QUESTS_UPDATED", OnDataUpdated)
ns.RegisterMessage("PEER_UPDATED", OnDataUpdated)
ns.RegisterMessage("STATS_UPDATED", OnDataUpdated)
ns.RegisterMessage("ROSTER_UPDATED", OnDataUpdated)
ns.RegisterMessage("GLOBAL_FILTER_CHANGED", OnDataUpdated)
