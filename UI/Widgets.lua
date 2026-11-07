-- =========================================================================
-- UI/Widgets.lua
-- Reusable modern flat/glass widgets: Buttons, SearchBars, Pill Filters,
-- Custom Sliders, Checkboxes, and Virtualized ScrollLists.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

ns.UI = ns.UI or {}
local UI = ns.UI

-- -------------------------------------------------------------------------
-- Modern Flat Button
-- -------------------------------------------------------------------------
function UI.CreateButton(parent, text, width, height, onClick, isPrimary)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 110, height or 26)
    btn.isPrimary = isPrimary

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text or "")
    btn.label = label

    function btn:RefreshStyle()
        local theme = ns.GetActiveTheme()
        if self.isPrimary or self.isActive then
            UI.ApplySurface(self, theme.accentSoft, theme.accent, 1)
            self.label:SetTextColor(1, 1, 1, 1)
        else
            UI.ApplySurface(self, theme.card, theme.border, 1)
            self.label:SetTextColor(theme.text[1], theme.text[2], theme.text[3], 1)
        end
    end

    btn:SetScript("OnEnter", function(self)
        local theme = ns.GetActiveTheme()
        UI.ApplySurface(self, theme.cardHover, theme.accent, 1)
    end)

    btn:SetScript("OnLeave", function(self)
        self:RefreshStyle()
    end)

    btn:SetScript("OnClick", function(self, button)
        if onClick then onClick(self, button) end
    end)

    btn:RefreshStyle()
    return btn
end

-- -------------------------------------------------------------------------
-- Search Box with Placeholder & Clear Button
-- -------------------------------------------------------------------------
function UI.CreateSearchBox(parent, width, height, placeholder, onTextChanged)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width or 220, height or 26)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(8, 22, 0, 0)

    local theme = ns.GetActiveTheme()
    UI.ApplySurface(box, theme.header, theme.border, 1)

    local ph = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", box, "LEFT", 8, 0)
    ph:SetText(placeholder or "Suchen...")
    box.placeholder = ph

    local clearBtn = CreateFrame("Button", nil, box)
    clearBtn:SetSize(16, 16)
    clearBtn:SetPoint("RIGHT", box, "RIGHT", -4, 0)
    local clearTxt = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clearTxt:SetPoint("CENTER", 0, 0)
    clearTxt:SetText("|cff94a3b8x|r")
    clearBtn:Hide()

    clearBtn:SetScript("OnClick", function()
        box:SetText("")
        box:ClearFocus()
    end)

    box:SetScript("OnEditFocusGained", function(self)
        local t = ns.GetActiveTheme()
        self:SetBackdropBorderColor(t.accent[1], t.accent[2], t.accent[3], 1)
    end)

    box:SetScript("OnEditFocusLost", function(self)
        local t = ns.GetActiveTheme()
        self:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
    end)

    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    box:SetScript("OnTextChanged", function(self)
        local txt = self:GetText() or ""
        if txt == "" then
            ph:Show()
            clearBtn:Hide()
        else
            ph:Hide()
            clearBtn:Show()
        end
        if onTextChanged then
            onTextChanged(txt)
        end
    end)

    return box
end

-- -------------------------------------------------------------------------
-- Modern Checkbox Toggle
-- -------------------------------------------------------------------------
function UI.CreateCheckBox(parent, labelText, tooltipText, getValue, setValue)
    local container = CreateFrame("Button", nil, parent)
    container:SetSize(280, 24)

    local box = CreateFrame("Frame", nil, container, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT", container, "LEFT", 0, 0)

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    box.fill = fill

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText or "")
    container.label = label

    function container:RefreshValue()
        local val = getValue and getValue() or false
        local theme = ns.GetActiveTheme()
        if val then
            UI.ApplySurface(box, theme.accentSoft, theme.accent, 1)
            fill:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3], 1)
            fill:Show()
        else
            UI.ApplySurface(box, theme.header, theme.border, 1)
            fill:Hide()
        end
    end

    container:SetScript("OnClick", function(self)
        local cur = getValue and getValue() or false
        if setValue then setValue(not cur) end
        self:RefreshValue()
    end)

    if tooltipText and tooltipText ~= "" then
        container:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        container:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    container:RefreshValue()
    return container
end

-- -------------------------------------------------------------------------
-- Modern Slider with Live Value Label
-- -------------------------------------------------------------------------
function UI.CreateSlider(parent, labelText, minVal, maxVal, step, width, getValue, setValue, formatFn)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or 220, 40)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    label:SetText(labelText or "")

    local valText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -18)
    slider:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -18)
    slider:SetHeight(12)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step or 0.05)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end

    local theme = ns.GetActiveTheme()
    UI.ApplySurface(slider, theme.header, theme.border, 1)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(12, 16)
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumb:SetVertexColor(theme.accent[1], theme.accent[2], theme.accent[3], 1)
    slider:SetThumbTexture(thumb)
    slider.thumb = thumb

    local updating = false
    function container:RefreshValue()
        updating = true
        local v = getValue and getValue() or minVal
        slider:SetValue(v)
        valText:SetText(formatFn and formatFn(v) or tostring(v))
        local t = ns.GetActiveTheme()
        thumb:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 1)
        updating = false
    end

    slider:SetScript("OnValueChanged", function(_, value)
        if updating then return end
        local rounded = math.floor((value / (step or 0.05)) + 0.5) * (step or 0.05)
        valText:SetText(formatFn and formatFn(rounded) or tostring(rounded))
        if setValue then setValue(rounded) end
    end)

    container:RefreshValue()
    return container
end

-- -------------------------------------------------------------------------
-- Virtualized MouseWheel Scroll List (Clean & Clipped)
-- -------------------------------------------------------------------------
function UI.CreateScrollList(parent, rowHeight, numRows, createRowFn, bindRowFn)
    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:EnableMouseWheel(true)
    if listFrame.SetClipsChildren then
        listFrame:SetClipsChildren(true)
    end
    listFrame.rowHeight = rowHeight or 34
    listFrame.numRows = numRows or 12
    listFrame.offset = 0
    listFrame.data = {}
    listFrame.rows = {}

    local track = CreateFrame("Frame", nil, listFrame)
    track:SetWidth(6)
    track:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, -4)
    track:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -2, 4)
    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0.04, 0.05, 0.07, 0.85)
    listFrame.track = track

    local theme = ns.GetActiveTheme()
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(6)
    thumb:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.85)
    listFrame.thumb = thumb

    for i = 1, listFrame.numRows do
        local row = createRowFn(listFrame, i)
        row:SetHeight(listFrame.rowHeight - 2)
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 4, -((i - 1) * listFrame.rowHeight) - 4)
        row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -12, -((i - 1) * listFrame.rowHeight) - 4)
        listFrame.rows[i] = row
    end

    local emptyText = listFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER", 0, 0)
    emptyText:SetText("Keine Einträge gefunden.")
    emptyText:Hide()
    listFrame.emptyText = emptyText

    function listFrame:SetData(newData, emptyLabel)
        self.data = newData or {}
        if emptyLabel then self.emptyText:SetText(emptyLabel) end
        local maxOffset = math.max(0, #self.data - self.numRows)
        if self.offset > maxOffset then self.offset = maxOffset end
        self:Refresh()
    end

    function listFrame:Refresh()
        local total = #self.data
        local maxOffset = math.max(0, total - self.numRows)
        if self.offset > maxOffset then self.offset = maxOffset end
        if self.offset < 0 then self.offset = 0 end

        if total == 0 then
            self.emptyText:Show()
        else
            self.emptyText:Hide()
        end

        for i = 1, self.numRows do
            local idx = self.offset + i
            local row = self.rows[i]
            local item = self.data[idx]
            if item then
                bindRowFn(row, item, idx)
                row:Show()
            else
                row:Hide()
            end
        end

        -- Update scrollbar thumb
        local t = ns.GetActiveTheme()
        self.thumb:SetColorTexture(t.accent[1], t.accent[2], t.accent[3], 0.85)
        local trackHeight = math.max(20, self.track:GetHeight() or 300)
        if total <= self.numRows then
            self.thumb:Hide()
            self.track:Hide()
        else
            self.track:Show()
            local ratio = self.numRows / total
            local thumbH = math.max(24, trackHeight * ratio)
            local scrollPct = self.offset / maxOffset
            local yOff = (trackHeight - thumbH) * scrollPct
            self.thumb:SetHeight(thumbH)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOP", self.track, "TOP", 0, -yOff)
            self.thumb:Show()
        end
    end

    listFrame:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - (delta * 2)
        self:Refresh()
    end)

    return listFrame
end

-- -------------------------------------------------------------------------
-- Modern Theme-Aware Dropdown Picker (Supports Scroll & Section Headers)
-- -------------------------------------------------------------------------
function UI.CreateDropdown(parent, width, height, getLabelFn, buildItemsFn)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 190, height or 24)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", btn, "LEFT", 8, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    btn.label = label

    local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetText("|cff94a3b8v|r")
    btn.arrow = arrow

    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(math.max(width or 190, 235))
    menu:SetFrameStrata("TOOLTIP")
    menu:SetToplevel(true)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    if menu.SetClipsChildren then menu:SetClipsChildren(true) end
    menu:Hide()
    btn.menu = menu

    menu.rows = {}
    menu.items = {}
    menu.offset = 0
    local MAX_VISIBLE = 14
    local ROW_H = 22

    local function RenderMenuRows()
        local theme = ns.GetActiveTheme()
        UI.ApplySurface(menu, theme.header, theme.accent, 1)
        local total = #menu.items
        local visibleCount = math.max(1, math.min(total, MAX_VISIBLE))
        local maxOffset = math.max(0, total - MAX_VISIBLE)
        if menu.offset > maxOffset then menu.offset = maxOffset end
        if menu.offset < 0 then menu.offset = 0 end

        menu:SetHeight(visibleCount * ROW_H + 8)

        for i = 1, MAX_VISIBLE do
            local row = menu.rows[i]
            if not row then
                row = CreateFrame("Button", nil, menu, "BackdropTemplate")
                row:SetHeight(ROW_H)
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * ROW_H)
                row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * ROW_H)

                local txt = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                txt:SetPoint("LEFT", row, "LEFT", 6, 0)
                txt:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                txt:SetJustifyH("LEFT")
                txt:SetWordWrap(false)
                row.txt = txt

                row:SetScript("OnEnter", function(self)
                    if self.item and not self.item.isHeader then
                        local t = ns.GetActiveTheme()
                        UI.ApplySurface(self, t.cardHover, nil, 0)
                    end
                end)
                row:SetScript("OnLeave", function(self)
                    if self.item and self.item.isSelected then
                        local t = ns.GetActiveTheme()
                        UI.ApplySurface(self, t.accentSoft, nil, 0)
                    else
                        self:SetBackdrop(nil)
                    end
                end)
                row:SetScript("OnClick", function(self)
                    if self.item and not self.item.isHeader then
                        menu:Hide()
                        if self.item.onClick then
                            self.item.onClick(self.item.value)
                        elseif self.item.onSelect then
                            self.item.onSelect(self.item.value)
                        end
                        btn:RefreshValue()
                    end
                end)
                menu.rows[i] = row
            end

            local item = menu.items[menu.offset + i]
            row.item = item
            if item then
                local itemText = item.text or item.label or ""
                if item.isHeader then
                    row:SetBackdrop(nil)
                    row.txt:SetText("|cff94a3b8— " .. itemText .. " —|r")
                else
                    if item.isSelected then
                        UI.ApplySurface(row, theme.accentSoft, nil, 0)
                        row.txt:SetText("|cff34d399>|r " .. itemText)
                    else
                        row:SetBackdrop(nil)
                        row.txt:SetText("  " .. itemText)
                    end
                end
                row:Show()
            else
                row:Hide()
            end
        end
    end

    menu:SetScript("OnMouseWheel", function(_, delta)
        menu.offset = menu.offset - delta
        RenderMenuRows()
    end)

    function btn:RefreshValue()
        local theme = ns.GetActiveTheme()
        UI.ApplySurface(self, theme.card, theme.border, 1)
        if getLabelFn then
            self.label:SetText(getLabelFn() or "Auswählen...")
        end
    end
    btn.RefreshLabel = btn.RefreshValue

    btn:SetScript("OnEnter", function(self)
        local t = ns.GetActiveTheme()
        UI.ApplySurface(self, t.cardHover, t.accent, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:RefreshValue()
    end)
    btn:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            menu:SetScale(btn:GetEffectiveScale() / (UIParent:GetEffectiveScale() or 1))
            menu.items = (buildItemsFn and buildItemsFn()) or {}
            menu.offset = 0
            RenderMenuRows()
            menu:Show()
        end
    end)
    btn:SetScript("OnHide", function()
        menu:Hide()
    end)

    btn:RefreshValue()
    return btn
end
