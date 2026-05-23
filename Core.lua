BuffBar = BuffBar or {}
local addon = BuffBar

addon.pendingItems = {}
addon.combatQueue = {}

local defaults = {
    items          = {},
    point          = { "CENTER", "UIParent", "CENTER", 0, -200 },
    locked         = false,
    orientation    = "horizontal",
    showCount      = true,
    showDuration   = true,
    showRedOverlay = false,
    hideWhenActive = false,
    alpha          = 1.0,
    iconSize       = 28,
    showLabel      = true,
    instancesOnly  = false,
    font           = "Fonts\\FRIZQT__.TTF",
    activeProfile  = "Default",
    profiles       = nil,            -- created on first run, see ensureProfiles
}

-- The set of top-level BuffBarDB keys that belong to a profile snapshot.
-- Anything not in this list (activeProfile, profiles itself) stays global.
local PROFILE_KEYS = {
    "items", "point", "locked", "orientation",
    "showCount", "showDuration", "showRedOverlay", "hideWhenActive",
    "alpha", "iconSize", "showLabel", "instancesOnly", "font",
}

-- Words we DROP from the item name before picking a label.
local LABEL_FILLER = {
    ["of"]=1, ["the"]=1, ["and"]=1, ["a"]=1, ["an"]=1,
    ["elixir"]=1, ["flask"]=1, ["potion"]=1, ["stone"]=1, ["oil"]=1,
    ["scroll"]=1, ["tome"]=1,
    ["greater"]=1, ["major"]=1, ["lesser"]=1, ["minor"]=1, ["super"]=1,
    ["heavy"]=1, ["light"]=1, ["solid"]=1, ["dense"]=1,
    ["adamantite"]=1, ["fel"]=1, ["arcane"]=1, ["brilliant"]=1,
    ["sharpening"]=1, ["weighted"]=1, ["weightstone"]=1,
    ["wizard"]=1, ["mojo"]=1,
    ["smoked"]=1, ["spicy"]=1, ["roasted"]=1, ["grilled"]=1,
    ["enchanted"]=1, ["refreshing"]=1, ["sagefish"]=1, ["crawdad"]=1,
    -- roman numerals (scroll ranks) — drop so "Scroll of Strength V" → "Str"
    ["i"]=1, ["ii"]=1, ["iii"]=1, ["iv"]=1, ["v"]=1, ["vi"]=1, ["vii"]=1,
    ["viii"]=1, ["ix"]=1, ["x"]=1,
}

-- Stat / theme keywords → their canonical short labels.
-- Checked BEFORE the filler-strip+truncate fallback so common consumables
-- get crisp 3-4 letter tags ("Str", "Agi", "Prot") instead of just truncations.
local STAT_LABEL = {
    strength    = "Str",
    agility     = "Agi",
    stamina     = "Stam",
    intellect   = "Int",
    spirit      = "Spi",
    protection  = "Prot",
    fortification = "Fort",
    fortitude   = "Fort",
    defense     = "Def",
    armor       = "Armor",
    battle      = "Battle",
    guardian    = "Guard",
    mongoose    = "Mong",
    demonslaying = "Demon",
    giants      = "Giant",
    sages       = "Sage",
    shadowpower = "Shad",
    firepower   = "Fire",
    frostpower  = "Frost",
    healing     = "Heal",
    mana        = "Mana",
    ironshield  = "Iron",
    well        = "Food",        -- "Well Fed"
    fed         = "Food",
    food        = "Food",
    drink       = "Drink",
    rage        = "Rage",
    earthen     = "Earth",
    sapper      = "Sapper",
    poison      = "Poison",
    swiftness   = "Swift",
}

-- Pick the most useful short label for an item name.
-- 1. Any word that matches STAT_LABEL → canonical abbreviation.
-- 2. Else the last non-filler word, truncated to maxLen.
-- 3. Else the last word.
-- 4. Else first maxLen chars of the whole name.
function addon:ShortLabel(name, maxLen)
    if not name or name == "" then return "" end
    maxLen = maxLen or 6

    -- 1. Stat keyword
    for word in name:gmatch("%S+") do
        local k = STAT_LABEL[word:lower()]
        if k then return k end
    end

    -- 2. Last non-filler word
    local pick
    for word in name:gmatch("%S+") do
        if not LABEL_FILLER[word:lower()] then pick = word end
    end

    -- 3. Last word at all
    if not pick then
        for word in name:gmatch("%S+") do pick = word end
    end

    pick = pick or name
    if #pick > maxLen then pick = pick:sub(1, maxLen) end
    return pick
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, vv in pairs(v) do t[k] = deepCopy(vv) end
    return t
end

local function ensureDefaults()
    BuffBarDB = BuffBarDB or {}
    for k, v in pairs(defaults) do
        if BuffBarDB[k] == nil then
            BuffBarDB[k] = deepCopy(v)
        end
    end
    -- First time the addon runs under profile support: snapshot the user's
    -- current settings into a profile called "Default" so they don't lose
    -- what they already had configured.
    if not BuffBarDB.profiles then
        BuffBarDB.profiles      = {}
        BuffBarDB.activeProfile = BuffBarDB.activeProfile or "Default"
        local snap = {}
        for _, key in ipairs(PROFILE_KEYS) do
            snap[key] = deepCopy(BuffBarDB[key])
        end
        BuffBarDB.profiles[BuffBarDB.activeProfile] = snap
    end
end

-- ─── profile management ───────────────────────────────────────────────────────

function addon:ProfileList()
    local names = {}
    if BuffBarDB.profiles then
        for name in pairs(BuffBarDB.profiles) do
            table.insert(names, name)
        end
        table.sort(names)
    end
    return names
end

function addon:ActiveProfile()
    return BuffBarDB.activeProfile or "Default"
end

-- Save the CURRENT live settings into the named profile (overwrites).
function addon:SaveProfile(name)
    name = name or self:ActiveProfile()
    BuffBarDB.profiles = BuffBarDB.profiles or {}
    local snap = {}
    for _, k in ipairs(PROFILE_KEYS) do
        snap[k] = deepCopy(BuffBarDB[k])
    end
    BuffBarDB.profiles[name] = snap
    BuffBarDB.activeProfile  = name
    self:Print("Saved profile '" .. name .. "'.")
end

-- Replace the live settings with a saved snapshot, then re-apply the bar.
function addon:LoadProfile(name)
    if InCombatLockdown() then
        self:Print("Cannot switch profile in combat.")
        return
    end
    local p = BuffBarDB.profiles and BuffBarDB.profiles[name]
    if not p then
        self:Print("No profile named '" .. tostring(name) .. "'.")
        return
    end
    for _, k in ipairs(PROFILE_KEYS) do
        if p[k] ~= nil then BuffBarDB[k] = deepCopy(p[k]) end
    end
    BuffBarDB.activeProfile = name
    -- Re-apply everything that changed
    if BuffBar.Bar.frame then
        local pt = BuffBarDB.point
        if pt then
            BuffBar.Bar.frame:ClearAllPoints()
            BuffBar.Bar.frame:SetPoint(pt[1], UIParent, pt[3], pt[4], pt[5])
        end
        BuffBar.Bar.frame:SetAlpha(BuffBarDB.alpha or 1.0)
    end
    BuffBar.Bar:Rebuild()
    BuffBar.Bar:ApplyFont()
    BuffBar.Bar:UpdateVisibility()
    self:Print("Loaded profile '" .. name .. "'.")
end

-- Create a new profile, optionally copying from the current settings.
function addon:CreateProfile(name)
    if not name or name == "" then return end
    BuffBarDB.profiles = BuffBarDB.profiles or {}
    if BuffBarDB.profiles[name] then
        self:Print("Profile '" .. name .. "' already exists.")
        return
    end
    -- New profile copies whatever is live right now
    local snap = {}
    for _, k in ipairs(PROFILE_KEYS) do
        snap[k] = deepCopy(BuffBarDB[k])
    end
    BuffBarDB.profiles[name] = snap
    BuffBarDB.activeProfile  = name
    self:Print("Created profile '" .. name .. "' (active).")
end

-- ─── profile serialization (export / import) ────────────────────────────────

local function serialize(v)
    local t = type(v)
    if t == "string"  then return string.format("%q", v) end
    if t == "number"  then return tostring(v) end
    if t == "boolean" then return tostring(v) end
    if t == "nil"     then return "nil" end
    if t == "table"   then
        local parts = {}
        for k, val in pairs(v) do
            local key
            if type(k) == "number" then
                key = "[" .. k .. "]"
            elseif type(k) == "string" then
                key = "[" .. string.format("%q", k) .. "]"
            else
                return nil  -- skip unsupported key types
            end
            local s = serialize(val)
            if s then table.insert(parts, key .. "=" .. s) end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return nil
end

function addon:SerializeProfile(name)
    name = name or self:ActiveProfile()
    local p = BuffBarDB.profiles and BuffBarDB.profiles[name]
    if not p then return nil end
    -- Tag the string so we can validate on import
    return "BuffBarProfile:" .. (serialize(p) or "")
end

-- Returns (profileTable, errorString). Refuses anything missing our tag.
-- We accept the BuffBarProfile: tag anywhere in the input and only consume
-- the balanced {...} table that follows it — so the user can paste from a
-- Discord message that includes extra text before or after the snippet and
-- it still imports cleanly.
function addon:DeserializeProfile(text)
    if type(text) ~= "string" then return nil, "no text" end
    local tagStart = text:find("BuffBarProfile:", 1, true)
    if not tagStart then return nil, "missing BuffBarProfile: header" end
    local braceStart = text:find("{", tagStart, true)
    if not braceStart then return nil, "no profile data found" end

    -- Walk forward tracking brace depth. Respect Lua string literals so a
    -- "}" inside a quoted item name doesn't close the table early.
    local depth, braceEnd, inString, escape = 0, nil, false, false
    for i = braceStart, #text do
        local c = text:sub(i, i)
        if escape then
            escape = false
        elseif c == "\\" then
            escape = true
        elseif c == '"' then
            inString = not inString
        elseif not inString then
            if     c == "{" then depth = depth + 1
            elseif c == "}" then
                depth = depth - 1
                if depth == 0 then braceEnd = i; break end
            end
        end
    end
    if not braceEnd then return nil, "unmatched braces" end

    local body = text:sub(braceStart, braceEnd)
    local fn, err = loadstring("return " .. body)
    if not fn then return nil, "parse error: " .. tostring(err) end
    local ok, result = pcall(fn)
    if not ok then return nil, "load error: " .. tostring(result) end
    if type(result) ~= "table" then return nil, "not a table" end
    return result
end

-- Import the given serialized text as a NEW profile. Picks a unique name
-- (suffixed with " (N)") if the desired name is taken. Loads it on success.
function addon:ImportProfile(text, desiredName)
    local data, err = self:DeserializeProfile(text)
    if not data then
        self:Print("Import failed: " .. tostring(err))
        return nil
    end
    BuffBarDB.profiles = BuffBarDB.profiles or {}
    local base = (desiredName and desiredName ~= "" and desiredName) or "Imported"
    local name, n = base, 2
    while BuffBarDB.profiles[name] do
        name = base .. " (" .. n .. ")"
        n = n + 1
    end
    BuffBarDB.profiles[name] = data
    self:LoadProfile(name)
    return name
end

function addon:DeleteProfile(name)
    if not BuffBarDB.profiles or not BuffBarDB.profiles[name] then return end
    -- Don't allow deleting the last remaining profile
    local remaining = 0
    for _ in pairs(BuffBarDB.profiles) do remaining = remaining + 1 end
    if remaining <= 1 then
        self:Print("Can't delete the last profile.")
        return
    end
    BuffBarDB.profiles[name] = nil
    if BuffBarDB.activeProfile == name then
        -- Fall back to any remaining profile
        for other in pairs(BuffBarDB.profiles) do
            BuffBarDB.activeProfile = other
            break
        end
    end
    self:Print("Deleted profile '" .. name .. "'.")
end

-- ─── helpers ─────────────────────────────────────────────────────────────────

function addon:Print(msg)
    print("|cff7fd5ffBuffBar|r: " .. tostring(msg))
end

function addon:GetBuffState(spellName)
    if not spellName then return false end
    -- UnitBuff returns: name(1), icon(2), count(3), dispelType(4),
    -- duration(5), expirationTime(6), ...  — positions matter!
    for i = 1, 40 do
        local name, _, _, _, duration, expiration = UnitBuff("player", i)
        if not name then break end
        if name == spellName then return true, expiration, duration end
    end
    return false
end

-- For sharpening stones / oils / weightstones: the buff isn't in UnitBuff,
-- it lives in GetWeaponEnchantInfo. The expiration is RELATIVE (ms remaining
-- from "now"), unlike UnitBuff's absolute time — we convert to an absolute
-- timestamp so the rest of the addon can use the same code path.
function addon:GetSlotEnchantState(slot)
    if slot == 5 then return addon:GetChestEnchantState() end
    local hasMH, mhMs, _, _, hasOH, ohMs = GetWeaponEnchantInfo()
    if slot == 16 and hasMH and mhMs and mhMs > 0 then
        local rem = mhMs / 1000
        return true, GetTime() + rem, rem
    elseif slot == 17 and hasOH and ohMs and ohMs > 0 then
        local rem = ohMs / 1000
        return true, GetTime() + rem, rem
    end
    return false
end

-- Items that apply a temporary enchant to the CHEST slot (slot 5). These
-- don't surface in GetWeaponEnchantInfo or UnitBuff — we read the duration
-- from the chest tooltip instead. Add more item IDs here as needed.
local CHEST_ENCHANT_ITEMS = {
    [20223] = true,   -- Lesser Rune of Warding
    [25521] = true,   -- Greater Rune of Warding
}
function addon:IsChestEnchantItem(itemID)
    return CHEST_ENCHANT_ITEMS[itemID] == true
end

-- Hidden tooltip frame we scan for the chest enchant. SetInventoryItem
-- populates the lines, then we look for a "(XX min)" / "(YY sec)" pattern
-- which is how Blizzard renders the temp-enchant's remaining time.
local scanTip
local function GetScanTip()
    if scanTip then return scanTip end
    scanTip = CreateFrame("GameTooltip", "BuffBarScanTip", UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    return scanTip
end

function addon:GetChestEnchantState()
    local tip = GetScanTip()
    tip:ClearLines()
    tip:SetInventoryItem("player", 5)

    for i = 1, tip:NumLines() do
        local fs = _G["BuffBarScanTipTextLeft" .. i]
        if fs then
            local text       = fs:GetText()
            local r, g, b    = fs:GetTextColor()
            -- Blizzard renders enchant lines in pure green (~r=0,g=1,b=0).
            -- Stat lines are white, Use:/Equip: lines are light cyan/blue,
            -- so the green test reliably isolates the actual enchant line
            -- and ignores procs like "for 30 sec" that previously matched.
            local isEnchant = text and g and g > 0.7 and r < 0.4 and b < 0.4
            if isEnchant then
                local h = text:match("(%d+)%s*hour")
                local m = text:match("(%d+)%s*min")
                local s = text:match("(%d+)%s*sec")
                local total = 0
                if h then total = total + tonumber(h) * 3600 end
                if m then total = total + tonumber(m) * 60   end
                if s then total = total + tonumber(s)        end
                if total > 0 then
                    return true, GetTime() + total, total
                end
            end
        end
    end
    return false
end

function addon:HasItem(itemID)
    for _, it in ipairs(BuffBarDB.items) do
        if it.itemID == itemID then return true end
    end
    return false
end

-- ─── item add / remove ───────────────────────────────────────────────────────

-- Try every form GetItemSpell accepts so we maximize the chance of resolving.
function addon:ResolveSpell(itemID)
    local _, link = GetItemInfo(itemID)
    local s = (link and GetItemSpell(link)) or GetItemSpell(itemID)
    return s
end

-- "Apply-to-weapon" items: sharpening stones, weightstones, mana / wizard oils,
-- shaman imbues etc. All sit under itemSubType "Weapon Enchantments" in TBC.
-- We also pattern-match the spell name as a fallback for any odd categorisation.
local APPLY_PATTERNS = { "Enchant Weapon", "Enchant 2H", "Sharpen", "Weighted",
                         "Weightstone", " Oil$", " Mana Oil", " Wizard Oil" }
function addon:IsWeaponApplyItem(itemID)
    local _, _, _, _, _, _, subType = GetItemInfo(itemID)
    if subType == "Weapon Enchantments" then return true end
    local spell = self:ResolveSpell(itemID)
    if spell then
        for _, pat in ipairs(APPLY_PATTERNS) do
            if spell:find(pat) then return true end
        end
    end
    return false
end

-- ─── weapon-slot picker dialog ────────────────────────────────────────────────

local weaponDlg
local function GetWeaponDialog()
    if weaponDlg then return weaponDlg end
    local dlg = CreateFrame("Frame", "BuffBarWeaponDialog", UIParent,
                            "BasicFrameTemplateWithInset")
    dlg:SetSize(340, 140)
    dlg:SetPoint("CENTER")
    dlg:SetFrameStrata("DIALOG")
    dlg:SetMovable(true)
    dlg:EnableMouse(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", dlg.StartMoving)
    dlg:SetScript("OnDragStop",  dlg.StopMovingOrSizing)
    dlg:Hide()

    local title = _G[dlg:GetName() .. "TitleText"] or dlg.TitleText
    if title then title:SetText("BuffBar — choose weapon slot") end

    local label = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOP", 0, -34)
    label:SetWidth(300)
    label:SetJustifyH("CENTER")
    dlg.label = label

    local mh = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    mh:SetSize(110, 24)
    mh:SetPoint("BOTTOMLEFT", 30, 18)
    mh:SetText("Main hand")
    dlg.mh = mh

    local oh = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
    oh:SetSize(110, 24)
    oh:SetPoint("BOTTOMRIGHT", -30, 18)
    oh:SetText("Off hand")
    dlg.oh = oh

    weaponDlg = dlg
    return dlg
end

local function PromptWeaponSlot(itemID, itemName, callback)
    local dlg = GetWeaponDialog()
    dlg.label:SetText(("Which weapon should %s|cffffffff|r apply to?")
        :format(itemName or "this item"))
    dlg.mh:SetScript("OnClick", function() dlg:Hide() callback(16) end)
    dlg.oh:SetScript("OnClick", function() dlg:Hide() callback(17) end)
    dlg:Show()
end

function addon:AddItem(itemID)
    if not itemID then return end
    if self:HasItem(itemID) then
        self:Print("Already tracking that item.")
        return
    end

    -- Chest-enchant items (runes) — auto-assign chest slot, no dialog.
    if self:IsChestEnchantItem(itemID) then
        self:_FinishAdd(itemID, 5)
        return
    end

    -- Weapon-enchant items — ask the user which weapon slot.
    if self:IsWeaponApplyItem(itemID) then
        local itemName = GetItemInfo(itemID) or "item"
        PromptWeaponSlot(itemID, itemName, function(slot)
            self:_FinishAdd(itemID, slot)
        end)
        return
    end

    self:_FinishAdd(itemID, nil)
end

function addon:_FinishAdd(itemID, slot)
    local spellName = self:ResolveSpell(itemID)
    if not spellName then
        addon.pendingItems[itemID] = true
    end
    table.insert(BuffBarDB.items, {
        itemID    = itemID,
        spellName = spellName,
        slot      = slot,    -- nil = consume directly; 16/17 = weapon slot
    })
    if InCombatLockdown() then
        self:Print("Cannot change bar in combat; changes apply after combat.")
        table.insert(self.combatQueue, function() BuffBar.Bar:Rebuild() end)
    else
        BuffBar.Bar:Rebuild()
    end
end

function addon:RemoveItem(index)
    if not BuffBarDB.items[index] then return end
    table.remove(BuffBarDB.items, index)
    if InCombatLockdown() then
        table.insert(self.combatQueue, function() BuffBar.Bar:Rebuild() end)
    else
        BuffBar.Bar:Rebuild()
    end
end

-- ─── events ──────────────────────────────────────────────────────────────────

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UNIT_INVENTORY_CHANGED")     -- weapon temp enchants
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then
        ensureDefaults()
        BuffBar.Bar:Initialize()
        BuffBar.AddZone:Initialize()
        BuffBar.Bar:Rebuild()
        BuffBar.Bar:UpdateVisibility()

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- bags and auras are guaranteed ready here; re-resolve spellNames
        for _, entry in ipairs(BuffBarDB.items) do
            if not entry.spellName then
                entry.spellName = addon:ResolveSpell(entry.itemID)
            end
        end
        if BuffBar.Bar.frame then BuffBar.Bar:Rebuild() end
        BuffBar.Bar:UpdateVisibility()

    elseif event == "BAG_UPDATE_DELAYED" then
        BuffBar.Bar:RefreshAll()

    elseif event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Weapon-enchant changed (oil applied / expired / weapon swapped)
        if event ~= "UNIT_INVENTORY_CHANGED" or a1 == "player" then
            BuffBar.Bar:RefreshAll()
        end

    elseif event == "UNIT_AURA" then
        if a1 == "player" then
            BuffBar.Bar:DetectNewBuff()
            BuffBar.Bar:RefreshAll()
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        if destGUID == UnitGUID("player") and
           (subEvent == "SPELL_AURA_APPLIED" or
            subEvent == "SPELL_AURA_REFRESH" or
            subEvent == "SPELL_AURA_REMOVED" or
            subEvent == "SPELL_AURA_APPLIED_DOSE" or
            subEvent == "SPELL_AURA_REMOVED_DOSE") then
            BuffBar.Bar:DetectNewBuff()
            BuffBar.Bar:RefreshAll()
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        local q = addon.combatQueue
        addon.combatQueue = {}
        for _, fn in ipairs(q) do fn() end

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = a1, a2
        if addon.pendingItems[itemID] and success then
            addon.pendingItems[itemID] = nil
            for _, entry in ipairs(BuffBarDB.items) do
                if entry.itemID == itemID and not entry.spellName then
                    entry.spellName = addon:ResolveSpell(itemID)
                end
            end
            if not InCombatLockdown() then
                BuffBar.Bar:Rebuild()
            end
        end
    end
end)

-- ─── slash commands ───────────────────────────────────────────────────────────

SLASH_BUFFBAR1 = "/bb"
SLASH_BUFFBAR2 = "/buffbar"
SlashCmdList.BUFFBAR = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$") or ""
    if msg == "lock" then
        BuffBarDB.locked = true
        BuffBar.Bar:Rebuild()
        addon:Print("Bar locked.")
    elseif msg == "unlock" then
        BuffBarDB.locked = false
        BuffBar.Bar:Rebuild()
        addon:Print("Bar unlocked. Drag handle to move.")
    elseif msg == "clear" then
        if InCombatLockdown() then addon:Print("Cannot clear in combat.") return end
        BuffBarDB.items = {}
        BuffBar.Bar:Rebuild()
        addon:Print("Cleared all tracked items.")
    else
        -- no args (or unknown args) → open the menu
        BuffBar.Menu:Toggle()
    end
end
