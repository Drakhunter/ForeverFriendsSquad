-- =========================================================================
-- UI/ThemeEngine.lua
-- Modern Dark UI Theme Manager & LibSharedMedia-3.0 Font/Texture Resolver.
-- Target Client: World of Warcraft: Forever (Interface: 16001)
-- =========================================================================
local addonName, ns = ...

ns.UI = ns.UI or {}

function ns.GetActiveTheme()
    local key = (ns.db and ns.db.ui and ns.db.ui.theme) or "OBSIDIAN"
    return ns.THEMES[key] or ns.THEMES.OBSIDIAN
end

function ns.SetTheme(themeKey)
    if not ns.THEMES[themeKey] then return end
    if ns.db and ns.db.ui then
        ns.db.ui.theme = themeKey
    end
    ns.SendMessage("THEME_CHANGED", themeKey)
    if ns.RefreshMainFrameTheme then
        ns.RefreshMainFrameTheme()
    end
    if ns.QoL and ns.QoL.UpdateHUD then
        ns.QoL:UpdateHUD()
    end
end

function ns.GetFontPath()
    local fontName = (ns.db and ns.db.ui and ns.db.ui.font) or "Friz Quadrata TT"
    if ns.Libs and ns.Libs.LSM then
        local path = ns.Libs.LSM:Fetch("font", fontName, true)
        if path and path ~= "" then return path end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

function ns.GetStatusbarTexture()
    local sbName = (ns.db and ns.db.ui and ns.db.ui.statusbar) or "Blizzard"
    if ns.Libs and ns.Libs.LSM then
        local path = ns.Libs.LSM:Fetch("statusbar", sbName, true)
        if path and path ~= "" then return path end
    end
    return "Interface\\Buttons\\WHITE8X8"
end

function ns.UI.ApplySurface(frame, bgRGBA, borderRGBA, edgeSize)
    if not frame or not frame.SetBackdrop then return end
    local hasBorder = (borderRGBA ~= nil) and (edgeSize == nil or edgeSize > 0)
    local actualEdge = hasBorder and (edgeSize or 1) or 0

    if hasBorder then
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = actualEdge,
        })
        frame:SetBackdropBorderColor(borderRGBA[1], borderRGBA[2], borderRGBA[3], borderRGBA[4] or 1)
    else
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
        })
    end

    if bgRGBA then
        frame:SetBackdropColor(bgRGBA[1], bgRGBA[2], bgRGBA[3], bgRGBA[4] or 1)
    else
        frame:SetBackdropColor(0, 0, 0, 0)
    end
end
