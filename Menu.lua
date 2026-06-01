BuffBar = BuffBar or {}
local addon = BuffBar
addon.Menu   = {}
local Menu   = addon.Menu

local HELP_TEXT =
    "|cff7fd5ffHow to use|r\n" ..
    "  - Drag a consumable from your bag onto the |cffffd700+|r slot to start tracking it\n" ..
    "  - |cffffffffRight-click|r a slot to consume one of that item (any mode)\n" ..
    "  - |cffffffffMiddle-click|r any icon to open this settings window (works even when locked)\n" ..
    "  - When |cffffffffunlocked|r: left-drag a slot to reorder; drag it far outside the bar to remove\n" ..
    "  - When unlocked, |cffffffffdrag the grip|r (the dotted handle on the left) to move the bar\n" ..
    "  - Use the |cffffffffLock bar|r button at the top of this menu to hide the grip and + button\n" ..
    "  - The slot stays full-color while the buff is up, fades when missing\n" ..
    "  - Bag count shows in the corner, remaining time shows next to the icon\n\n" ..
    "|cff7fd5ffSlash commands|r\n" ..
    "  /bb         open this menu\n" ..
    "  /buffbar    same as /bb\n" ..
    "  /bb lock    lock the bar in place\n" ..
    "  /bb unlock  unlock for moving\n" ..
    "  /bb clear   remove every tracked item"

local SIDEBAR_W = 120
local TAB_H     = 30

-- Confirmation popup for "Clear all items" so it can't be triggered by an
-- accidental click. Registered once at file-load time.
StaticPopupDialogs["BUFFBAR_CONFIRM_CLEAR"] = {
    text         = "Remove ALL tracked items from BuffBar?",
    button1      = YES,
    button2      = NO,
    OnAccept     = function()
        if InCombatLockdown() then
            addon:Print("Cannot clear in combat.")
            return
        end
        BuffBarDB.items = {}
        BuffBar.Bar:Rebuild()
        addon:Print("Cleared all tracked items.")
    end,
    timeout       = 0,
    whileDead     = true,
    hideOnEscape  = true,
    preferredIndex = 3,   -- avoids tainted-popup interactions
}

Menu.tabs     = {}
Menu.contents = {}

-- Forward declarations
local SelectTab, CreateTab, CreateConfigContent, CreateHelpContent

-- ─── tab styling ──────────────────────────────────────────────────────────────

local function StyleTab(btn, active)
    if active then
        btn.bg:SetColorTexture(0.20, 0.25, 0.35, 1)
        btn.text:SetTextColor(1, 0.82, 0)   -- gold
        btn.accent:Show()
    else
        btn.bg:SetColorTexture(0.08, 0.08, 0.08, 1)
        btn.text:SetTextColor(0.85, 0.85, 0.85)
        btn.accent:Hide()
    end
end

CreateTab = function(parent, label, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SIDEBAR_W, TAB_H)
    btn:SetPoint("TOPLEFT", 0, -((index - 1) * TAB_H))

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    btn.bg = bg

    -- thin gold accent strip on the left when active (Blizzard-style)
    local accent = btn:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:SetColorTexture(1, 0.82, 0, 1)
    accent:Hide()
    btn.accent = accent

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", 12, 0)
    text:SetText(label)
    btn.text = text

    btn:SetScript("OnClick", function() SelectTab(index) end)
    btn:SetScript("OnEnter", function()
        if Menu.currentTab ~= index then
            bg:SetColorTexture(0.14, 0.14, 0.14, 1)
        end
    end)
    btn:SetScript("OnLeave", function()
        if Menu.currentTab ~= index then
            bg:SetColorTexture(0.08, 0.08, 0.08, 1)
        end
    end)

    StyleTab(btn, false)
    Menu.tabs[index] = btn
    return btn
end

SelectTab = function(index)
    Menu.currentTab = index
    for i, tab in ipairs(Menu.tabs) do
        StyleTab(tab, i == index)
    end
    for i, content in ipairs(Menu.contents) do
        if i == index then content:Show() else content:Hide() end
    end
end

-- ─── content panels ───────────────────────────────────────────────────────────

-- Helper: create a Blizzard-styled labelled checkbox.
local function MakeCheck(parent, name, label, anchor, onClick)
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor.frame or parent, anchor.point or "TOPLEFT",
                anchor.x or 0, anchor.y or 0)
    local text = _G[cb:GetName() .. "Text"] or cb.Text or cb.text
    if text then
        text:SetText(label)
        text:ClearAllPoints()
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    end
    cb:SetScript("OnClick", onClick)
    return cb
end

-- Fonts come from two sources:
--   1. The 4 fonts that always ship with the WoW client.
--   2. Every font any OTHER addon has registered with LibSharedMedia-3.0.
--      That's the same library WeakAuras / ElvUI / Details! use, so installing
--      any of those gives BuffBar access to their bundled fonts automatically.
--
-- We re-collect on every dropdown open so newly-installed addons appear after
-- /reload without needing BuffBar code changes.
local function CollectFonts()
    local fonts = {
        { name = "Friz Quadrata  (Blizzard default)", path = "Fonts\\FRIZQT__.TTF" },
        { name = "Arial Narrow",                       path = "Fonts\\ARIALN.TTF"   },
        { name = "Skurri",                             path = "Fonts\\SKURRI.TTF"   },
        { name = "Morpheus",                           path = "Fonts\\MORPHEUS.TTF" },
    }
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and LSM.List then
        local seen = {}
        for _, f in ipairs(fonts) do seen[f.path] = true end
        for _, fontName in ipairs(LSM:List("font")) do
            local path = LSM:Fetch("font", fontName)
            if path and not seen[path] then
                seen[path] = true
                table.insert(fonts, { name = fontName, path = path })
            end
        end
    end
    return fonts
end

-- Helper: create a labelled Blizzard-style dropdown for selecting from a list.
-- `choices` is the FONT_CHOICES-style list, `getValue` returns the saved value,
-- `onSelect(value)` is called when the user picks an entry.
-- `choicesFn` is a function that returns the up-to-date list of choices each
-- time the dropdown opens — so newly-loaded addons that register fonts via
-- LibSharedMedia after our menu was first built still appear.
local function MakeDropdown(parent, name, label, anchor, choicesFn, getValue, onSelect)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", anchor.frame or parent, anchor.point or "TOPLEFT",
                   anchor.x or 0, anchor.y or 0)
    title:SetText(label)
    title:SetTextColor(0.95, 0.95, 0.95)

    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(dd, 260)

    local function currentLabel()
        local v = getValue()
        for _, c in ipairs(choicesFn()) do
            if c.path == v then return c.name end
        end
        return v or ""
    end
    UIDropDownMenu_SetText(dd, currentLabel())

    UIDropDownMenu_Initialize(dd, function(_, level)
        for _, c in ipairs(choicesFn()) do
            local info  = UIDropDownMenu_CreateInfo()
            info.text   = c.name
            info.value  = c.path
            info.func   = function(self)
                UIDropDownMenu_SetSelectedValue(dd, self.value)
                UIDropDownMenu_SetText(dd, self:GetText())
                onSelect(self.value)
            end
            info.checked = (getValue() == c.path)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    dd._title   = title
    dd._refresh = function() UIDropDownMenu_SetText(dd, currentLabel()) end
    return dd
end

-- Helper: create a Blizzard-styled labelled slider wrapped in its own framed
-- panel so the slider bar is visible against the dark window background.
-- Returns the WRAPPER frame (so callers can anchor relative to its bottom).
-- The slider itself is exposed as wrapper.slider for SetValue() calls.
local function MakeSlider(parent, name, label, minV, maxV, step, anchor, fmt, onChange)
    local wrap = CreateFrame("Frame", nil, parent)
    wrap:SetSize(320, 46)
    wrap:SetPoint("TOPLEFT", anchor.frame or parent, anchor.point or "TOPLEFT",
                  anchor.x or 0, anchor.y or 0)

    -- subtle panel so the slider track stands out
    local bg = wrap:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.04)

    local s = CreateFrame("Slider", name, wrap, "OptionsSliderTemplate")
    s:SetWidth(220)
    s:SetHeight(16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetPoint("LEFT", wrap, "LEFT", 12, -4)

    local title = _G[s:GetName() .. "Text"]
    if title then title:SetText(label) end
    local lo    = _G[s:GetName() .. "Low"]
    if lo then lo:SetText(tostring(minV)) end
    local hi    = _G[s:GetName() .. "High"]
    if hi then hi:SetText(tostring(maxV)) end

    -- Live value readout to the right of the slider
    local val = wrap:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    val:SetPoint("LEFT", s, "RIGHT", 14, 0)
    wrap.valueText = val

    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor((v / step) + 0.5) * step
        val:SetText(fmt and fmt:format(v) or tostring(v))
        onChange(v)
    end)
    wrap.slider = s
    return wrap
end

CreateConfigContent = function(parent, sidebar)
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 4, 0)
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 6)

    -- ─── Vital action buttons at the top of the tab ──────────────────
    -- Lock / Unlock toggle (top-left)
    local lockBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    lockBtn:SetSize(130, 24)
    lockBtn:SetPoint("TOPLEFT", 8, -6)
    lockBtn._updateText = function()
        lockBtn:SetText(BuffBarDB.locked and "Unlock bar" or "Lock bar")
    end
    lockBtn._updateText()
    lockBtn:SetScript("OnClick", function()
        BuffBarDB.locked = not BuffBarDB.locked
        -- Rebuild (not just ApplyLockState) so secure attributes on each slot
        -- are updated to reflect the new lock state (edit vs play mode).
        BuffBar.Bar:Rebuild()
        lockBtn._updateText()
    end)
    Menu.lockBtn = lockBtn

    -- Save profile button (between Lock and Reset)
    local saveBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    saveBtn:SetSize(130, 24)
    saveBtn:SetPoint("LEFT", lockBtn, "RIGHT", 8, 0)
    saveBtn._updateText = function()
        saveBtn:SetText("Save profile")
    end
    saveBtn._updateText()
    saveBtn:SetScript("OnClick", function()
        addon:SaveProfile(addon:ActiveProfile())
        if Menu.profileRefresh then Menu.profileRefresh() end
    end)
    saveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Save current settings to '" ..
            (addon:ActiveProfile() or "Default") .. "'")
        GameTooltip:Show()
    end)
    saveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Menu.saveBtn = saveBtn

    -- ─── Layout section ──────────────────────────────────────────────
    local lh = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lh:SetPoint("TOPLEFT", lockBtn, "BOTTOMLEFT", -2, -10)
    lh:SetText("Layout")
    lh:SetTextColor(1, 0.82, 0)

    Menu.verticalCheck = MakeCheck(content, "BuffBarVerticalCheck",
        "Stack icons vertically",
        { frame = lh, point = "BOTTOMLEFT", x = 0, y = -8 },
        function(self)
            if InCombatLockdown() then
                addon:Print("Cannot switch orientation in combat.")
                self:SetChecked(BuffBarDB.orientation == "vertical")
                return
            end
            BuffBarDB.orientation = self:GetChecked() and "vertical" or "horizontal"
            BuffBar.Bar:Rebuild()
        end)

    Menu.centeredCheck = MakeCheck(content, "BuffBarCenteredCheck",
        "Keep icons centered (row shrinks symmetrically)",
        { frame = Menu.verticalCheck, point = "BOTTOMLEFT", x = 0, y = -4 },
        function(self)
            BuffBarDB.centered = self:GetChecked() and true or false
            BuffBar.Bar:ApplyLockState()
            BuffBar.Bar:RefreshAll()
        end)

    -- ─── Display section ─────────────────────────────────────────────
    local dh = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dh:SetPoint("TOPLEFT", Menu.centeredCheck, "BOTTOMLEFT", 0, -14)
    dh:SetText("Display")
    dh:SetTextColor(1, 0.82, 0)

    Menu.countCheck = MakeCheck(content, "BuffBarCountCheck",
        "Show item count from bag",
        { frame = dh, point = "BOTTOMLEFT", x = 0, y = -8 },
        function(self)
            BuffBarDB.showCount = self:GetChecked() and true or false
            BuffBar.Bar:RefreshAll()
        end)

    Menu.durationCheck = MakeCheck(content, "BuffBarDurationCheck",
        "Show remaining buff time",
        { frame = Menu.countCheck, point = "BOTTOMLEFT", x = 0, y = -4 },
        function(self)
            BuffBarDB.showDuration = self:GetChecked() and true or false
            BuffBar.Bar:RefreshAll()
        end)

    Menu.redCheck = MakeCheck(content, "BuffBarRedCheck",
        "Show red overlay when buff is missing",
        { frame = Menu.durationCheck, point = "BOTTOMLEFT", x = 0, y = -4 },
        function(self)
            BuffBarDB.showRedOverlay = self:GetChecked() and true or false
            BuffBar.Bar:RefreshAll()
        end)

    Menu.hideActiveCheck = MakeCheck(content, "BuffBarHideActiveCheck",
        "Hide icon while buff is active",
        { frame = Menu.redCheck, point = "BOTTOMLEFT", x = 0, y = -4 },
        function(self)
            BuffBarDB.hideWhenActive = self:GetChecked() and true or false
            BuffBar.Bar:ApplyLockState()
            BuffBar.Bar:RefreshAll()
        end)

    Menu.labelCheck = MakeCheck(content, "BuffBarLabelCheck",
        "Show short name under each icon",
        { frame = Menu.hideActiveCheck, point = "BOTTOMLEFT", x = 0, y = -4 },
        function(self)
            BuffBarDB.showLabel = self:GetChecked() and true or false
            BuffBar.Bar:ApplyLockState()   -- relayout positions text correctly
            BuffBar.Bar:RefreshAll()
        end)

    Menu.instanceCheck = MakeCheck(content, "BuffBarInstanceCheck",
        "Only show in dungeons and raids",
        { frame = Menu.labelCheck, point = "BOTTOMLEFT", x = 0, y = -4 },
        function(self)
            BuffBarDB.instancesOnly = self:GetChecked() and true or false
            BuffBar.Bar:UpdateVisibility()
        end)

    -- Appearance header
    local sh = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sh:SetPoint("TOPLEFT", Menu.instanceCheck, "BOTTOMLEFT", 0, -18)
    sh:SetText("Appearance")
    sh:SetTextColor(1, 0.82, 0)

    -- Font dropdown first (top of the section) so its option list opens
    -- downward with room to show every entry without being clipped.
    Menu.fontDropdown = MakeDropdown(content, "BuffBarFontDropdown",
        "Font",
        { frame = sh, point = "BOTTOMLEFT", x = 0, y = -4 },
        CollectFonts,
        function() return BuffBarDB.font end,
        function(path)
            BuffBarDB.font = path
            BuffBar.Bar:ApplyFont()
        end)

    Menu.alphaSlider = MakeSlider(content, "BuffBarAlphaSlider",
        "Bar transparency", 0.1, 1.0, 0.05,
        { frame = Menu.fontDropdown, point = "BOTTOMLEFT", x = 20, y = -10 },
        "%.2f",
        function(v)
            BuffBarDB.alpha = v
            if BuffBar.Bar.frame then BuffBar.Bar.frame:SetAlpha(v) end
        end)

    Menu.sizeSlider = MakeSlider(content, "BuffBarSizeSlider",
        "Icon size", 16, 64, 2,
        { frame = Menu.alphaSlider, point = "BOTTOMLEFT", x = 0, y = -14 },
        "%dpx",
        function(v)
            BuffBarDB.iconSize = v
            BuffBar.Bar:ApplyLockState()
            BuffBar.Bar:RefreshAll()
        end)

    -- Reset (top-right) — confirms then wipes every tracked item.
    local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 24)
    resetBtn:SetPoint("TOPRIGHT", -8, -6)
    resetBtn:SetText("Reset")
    resetBtn:SetScript("OnClick", function()
        StaticPopup_Show("BUFFBAR_CONFIRM_CLEAR")
    end)

    content:Hide()
    return content
end

-- A reusable popup with a multiline EditBox + scroll. Used for both Export
-- (pre-filled, read-only feel — text is auto-selected on open so Ctrl+C
-- copies the whole thing) and Import (empty, user pastes).
local textDlg
local function OpenTextDialog(title, body, initialText, mode, onAccept)
    if not textDlg then
        local dlg = CreateFrame("Frame", "BuffBarTextDialog", UIParent,
                                "BasicFrameTemplateWithInset")
        tinsert(UISpecialFrames, "BuffBarTextDialog")
        dlg:SetSize(460, 340)
        dlg:SetPoint("CENTER")
        -- Sit above the settings window (which uses DIALOG strata) so the
        -- export/import popup is never hidden behind it.
        dlg:SetFrameStrata("FULLSCREEN_DIALOG")
        dlg:SetToplevel(true)
        dlg:SetMovable(true)
        dlg:EnableMouse(true)
        dlg:RegisterForDrag("LeftButton")
        dlg:SetScript("OnDragStart", dlg.StartMoving)
        dlg:SetScript("OnDragStop",  dlg.StopMovingOrSizing)
        dlg:Hide()

        dlg.titleFS = _G[dlg:GetName() .. "TitleText"] or dlg.TitleText

        local body = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", 14, -32)
        body:SetPoint("TOPRIGHT", -14, -32)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetWordWrap(true)
        dlg.body = body

        local scroll = CreateFrame("ScrollFrame", "BuffBarTextDialogScroll",
                                   dlg, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -64)
        scroll:SetPoint("BOTTOMRIGHT", -34, 44)

        -- Dark click-through backdrop so the empty edit area is visible AND
        -- doesn't swallow clicks meant for the EditBox below it.
        local bgFrame = CreateFrame("Frame", nil, dlg)
        bgFrame:SetAllPoints(scroll)
        bgFrame:SetFrameLevel(scroll:GetFrameLevel() - 1)
        bgFrame:EnableMouse(false)
        local bg = bgFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.4)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetMaxLetters(0)
        edit:SetFontObject("GameFontHighlight")
        edit:SetAutoFocus(false)
        edit:EnableMouse(true)
        edit:SetSize(400, 220)        -- explicit size = real clickable area
        edit:SetTextInsets(4, 4, 4, 4)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        -- Clicking anywhere in the scroll area focuses the edit box so users
        -- don't have to find the exact text line.
        scroll:EnableMouse(true)
        scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
        scroll:SetScrollChild(edit)
        dlg.edit = edit

        local closeBtn = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
        closeBtn:SetSize(100, 22)
        closeBtn:SetPoint("BOTTOMRIGHT", -14, 14)
        closeBtn:SetText("Close")
        closeBtn:SetScript("OnClick", function() dlg:Hide() end)
        dlg.closeBtn = closeBtn

        local primaryBtn = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
        primaryBtn:SetSize(100, 22)
        primaryBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
        dlg.primaryBtn = primaryBtn

        textDlg = dlg
    end

    if textDlg.titleFS then textDlg.titleFS:SetText(title or "") end
    textDlg.body:SetText(body or "")
    textDlg.edit:SetText(initialText or "")

    if mode == "export" then
        -- Read mode: pre-select everything for one-shot Ctrl+C copy
        textDlg.primaryBtn:Hide()
        textDlg.closeBtn:SetText("Close")
        textDlg.edit:HighlightText()
        textDlg.edit:SetFocus()
    else
        -- Write mode (Import): empty edit, primary button accepts
        textDlg.primaryBtn:Show()
        textDlg.primaryBtn:SetText("Import")
        textDlg.primaryBtn:SetScript("OnClick", function()
            local text = textDlg.edit:GetText() or ""
            textDlg:Hide()
            if onAccept then onAccept(text) end
        end)
        textDlg.closeBtn:SetText("Cancel")
        textDlg.edit:SetFocus()
    end

    textDlg:Show()
    textDlg:Raise()      -- bring above any sibling DIALOG-strata frames
end

local CreateProfileContent
CreateProfileContent = function(parent, sidebar)
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 4, 0)
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 6)

    -- "Active" header
    local active = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    active:SetPoint("TOPLEFT", 6, -6)
    active:SetTextColor(1, 0.82, 0)
    local function setActiveText()
        active:SetText("Active profile:  |cffffffff" .. addon:ActiveProfile() .. "|r")
    end
    setActiveText()

    -- Switch profile dropdown
    local switchLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    switchLabel:SetPoint("TOPLEFT", active, "BOTTOMLEFT", 0, -16)
    switchLabel:SetText("Switch to profile:")

    local switchDD = CreateFrame("Frame", "BuffBarProfileSwitchDD",
                                 content, "UIDropDownMenuTemplate")
    switchDD:SetPoint("TOPLEFT", switchLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(switchDD, 220)

    local function refreshDropdownText()
        UIDropDownMenu_SetText(switchDD, addon:ActiveProfile())
    end
    refreshDropdownText()

    UIDropDownMenu_Initialize(switchDD, function(_, level)
        for _, n in ipairs(addon:ProfileList()) do
            local info  = UIDropDownMenu_CreateInfo()
            info.text   = n
            info.value  = n
            info.checked = (addon:ActiveProfile() == n)
            info.func   = function(self)
                addon:LoadProfile(self.value)
                refreshDropdownText()
                setActiveText()
                Menu:Refresh()           -- sync Configuration tab widgets
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Create new profile
    local createLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    createLabel:SetPoint("TOPLEFT", switchDD, "BOTTOMLEFT", 16, -14)
    createLabel:SetText("Create new profile (copies current settings):")

    local input = CreateFrame("EditBox", "BuffBarNewProfileInput",
                              content, "InputBoxTemplate")
    input:SetSize(180, 22)
    input:SetPoint("TOPLEFT", createLabel, "BOTTOMLEFT", 8, -6)
    input:SetAutoFocus(false)
    input:SetMaxLetters(32)

    local createBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    createBtn:SetSize(80, 22)
    createBtn:SetPoint("LEFT", input, "RIGHT", 10, 0)
    createBtn:SetText("Create")
    local function doCreate()
        local name = input:GetText() or ""
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return end
        addon:CreateProfile(name)
        input:SetText("")
        input:ClearFocus()
        refreshDropdownText()
        setActiveText()
        Menu:Refresh()
    end
    createBtn:SetScript("OnClick", doCreate)
    input:SetScript("OnEnterPressed", doCreate)
    input:SetScript("OnEscapePressed", function() input:ClearFocus() end)

    -- Delete current
    local deleteLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    deleteLabel:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -8, -20)
    deleteLabel:SetText("Delete the active profile:")

    local deleteBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    deleteBtn:SetSize(180, 22)
    deleteBtn:SetPoint("TOPLEFT", deleteLabel, "BOTTOMLEFT", 8, -6)
    deleteBtn:SetText("Delete '" .. addon:ActiveProfile() .. "'")
    local function refreshDeleteText()
        deleteBtn:SetText("Delete '" .. addon:ActiveProfile() .. "'")
    end
    deleteBtn:SetScript("OnClick", function()
        StaticPopupDialogs["BUFFBAR_CONFIRM_DELETE_PROFILE"] = {
            text         = "Delete profile '" .. addon:ActiveProfile() .. "'?",
            button1      = YES,
            button2      = NO,
            OnAccept     = function()
                addon:DeleteProfile(addon:ActiveProfile())
                refreshDropdownText()
                refreshDeleteText()
                setActiveText()
                Menu:Refresh()
            end,
            timeout      = 0,
            whileDead    = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("BUFFBAR_CONFIRM_DELETE_PROFILE")
    end)

    -- Export / Import buttons
    local exportBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    exportBtn:SetSize(100, 22)
    exportBtn:SetPoint("TOPLEFT", deleteBtn, "BOTTOMLEFT", 0, -22)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local name = addon:ActiveProfile()
        local text = addon:SerializeProfile(name)
        if not text then return end
        OpenTextDialog(
            "Export profile",
            "Copy the text below and share it. The recipient pastes it into Import.",
            text,
            "export")
    end)

    local importBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    importBtn:SetSize(100, 22)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        OpenTextDialog(
            "Import profile",
            "Paste an exported BuffBar profile text below, then click Import.",
            "",
            "import",
            function(text)
                -- Parse first so we can reject bad input WITHOUT prompting
                local data, err = addon:DeserializeProfile(text)
                if not data then
                    addon:Print("Import failed: " .. tostring(err))
                    return
                end
                local activeName = addon:ActiveProfile()
                StaticPopupDialogs["BUFFBAR_CONFIRM_IMPORT"] = {
                    text = "|cffff5555WARNING|r\n\n"
                        .. "Importing will overwrite the active profile\n"
                        .. "'|cffffd700" .. activeName .. "|r'\n\n"
                        .. "with the pasted data. Continue?",
                    button1 = YES,
                    button2 = NO,
                    OnAccept = function()
                        BuffBarDB.profiles = BuffBarDB.profiles or {}
                        BuffBarDB.profiles[activeName] = data
                        addon:LoadProfile(activeName)
                        Menu:Refresh()
                        addon:Print("Imported into profile '" .. activeName .. "'.")
                    end,
                    timeout      = 0,
                    whileDead    = true,
                    hideOnEscape = true,
                    preferredIndex = 3,
                }
                StaticPopup_Show("BUFFBAR_CONFIRM_IMPORT")
            end)
    end)

    content.refresh = function()
        setActiveText()
        refreshDropdownText()
        refreshDeleteText()
    end
    Menu.profileRefresh = content.refresh

    content:Hide()
    return content
end

CreateHelpContent = function(parent, sidebar)
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 4, 0)
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 6)

    local help = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 6, -6)
    help:SetPoint("TOPRIGHT", -6, -6)
    help:SetJustifyH("LEFT")
    help:SetJustifyV("TOP")
    help:SetText(HELP_TEXT)
    help:SetSpacing(2)

    content:Hide()
    return content
end

-- ─── window ───────────────────────────────────────────────────────────────────

function Menu:Initialize()
    if self.frame then return end

    local frame = CreateFrame("Frame", "BuffBarMenu", UIParent, "BasicFrameTemplateWithInset")
    -- Make Escape close the window (standard WoW behaviour for addon panels).
    tinsert(UISpecialFrames, "BuffBarMenu")
    frame:SetSize(560, 620)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()
    self.frame = frame

    local title = _G[frame:GetName() .. "TitleText"] or frame.TitleText
    if title then title:SetText("BuffBar") end

    -- Sidebar (left rail of tabs)
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 4, -26)
    sidebar:SetPoint("BOTTOMLEFT", 4, 4)
    sidebar:SetWidth(SIDEBAR_W)

    local sBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sBg:SetAllPoints()
    sBg:SetColorTexture(0.03, 0.03, 0.03, 0.95)

    -- Tabs
    CreateTab(sidebar, "Configuration", 1)
    CreateTab(sidebar, "Profiles",      2)
    CreateTab(sidebar, "Help",          3)

    -- Content panels
    self.contents[1] = CreateConfigContent(frame, sidebar)
    self.contents[2] = CreateProfileContent(frame, sidebar)
    self.contents[3] = CreateHelpContent(frame, sidebar)

    SelectTab(1)
end

function Menu:Refresh()
    if self.verticalCheck then
        self.verticalCheck:SetChecked(BuffBarDB.orientation == "vertical")
    end
    if self.centeredCheck then
        self.centeredCheck:SetChecked(BuffBarDB.centered == true)
    end
    if self.lockBtn and self.lockBtn._updateText then
        self.lockBtn._updateText()
    end
    if self.countCheck then
        self.countCheck:SetChecked(BuffBarDB.showCount ~= false)
    end
    if self.durationCheck then
        self.durationCheck:SetChecked(BuffBarDB.showDuration ~= false)
    end
    if self.redCheck then
        self.redCheck:SetChecked(BuffBarDB.showRedOverlay == true)
    end
    if self.hideActiveCheck then
        self.hideActiveCheck:SetChecked(BuffBarDB.hideWhenActive == true)
    end
    if self.labelCheck then
        self.labelCheck:SetChecked(BuffBarDB.showLabel ~= false)
    end
    if self.instanceCheck then
        self.instanceCheck:SetChecked(BuffBarDB.instancesOnly == true)
    end
    if self.alphaSlider and self.alphaSlider.slider then
        self.alphaSlider.slider:SetValue(BuffBarDB.alpha or 1.0)
    end
    if self.sizeSlider and self.sizeSlider.slider then
        self.sizeSlider.slider:SetValue(BuffBarDB.iconSize or 28)
    end
    if self.fontDropdown and self.fontDropdown._refresh then
        self.fontDropdown._refresh()
    end
    if self.profileRefresh then self.profileRefresh() end
end

function Menu:Toggle()
    if not self.frame then self:Initialize() end
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Refresh()
        self.frame:Show()
    end
end
