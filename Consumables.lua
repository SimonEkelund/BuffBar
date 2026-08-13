--[[ BuffBar/Consumables.lua - authoritative item -> buff (aura) name data.

     WHY THIS FILE EXISTS
     The addon used to learn an item's buff at runtime by snapshotting your
     auras, using the item, then binding to whatever new buff appeared. That is
     unreliable in a raid: any elixir, proc or raid buff landing in the same
     window could win the "longest duration" test and steal the slot. Real
     example from the saved data: Scroll of Strength V and Scroll of Agility V
     were both bound to "Elixir of the Mongoose", so drinking mongoose hid both
     scroll icons. Food was bound to "Food" (the transient eating aura) instead
     of "Well Fed", so it went red ~30s after every meal.

     Now the buff name comes from DATA first. Runtime detection is only a last
     resort for items nothing here knows about, and it can never overwrite a
     binding that came from this file.

     Three resolution layers, in order:
       1. EXACT[itemID]        - where the buff name differs from the item name
       2. pattern rules        - whole families (scrolls, food, ...)
       3. nil -> caller falls back to GetItemSpell(), then runtime detection
]]

BuffBar = BuffBar or {}
local addon = BuffBar
addon.Consumables = {}
local C = addon.Consumables

-- ─── exact overrides ─────────────────────────────────────────────────────────
-- Only items whose AURA name differs from the ITEM name need to be listed.
-- TBC flasks and elixirs almost all apply an aura with the same name as the
-- item, so they resolve correctly via GetItemSpell and are deliberately absent.
local EXACT = {
    -- Vanilla flasks: the aura drops the "Flask of" prefix.
    [13512] = "Supreme Power",              -- Flask of Supreme Power
    [13511] = "Distilled Wisdom",           -- Flask of Distilled Wisdom
    [13513] = "Chromatic Resistance",       -- Flask of Chromatic Resistance
    -- (Flask of the Titans 13510 keeps its full name - no entry needed.)

    -- Battle/utility potions: aura drops the "Potion" suffix.
    [22838] = "Haste",                      -- Haste Potion
    [22839] = "Destruction",                -- Destruction Potion
    [22828] = "Insane Strength",            -- Insane Strength Potion
    [22837] = "Heroic",                     -- Heroic Potion
    [22849] = "Ironshield",                 -- Ironshield Potion
    [13442] = "Mighty Rage",                -- Mighty Rage Potion
    [5634]  = "Free Action",                -- Free Action Potion
    [20008] = "Living Action",              -- Living Action Potion
    [31677] = "Fel Regeneration",           -- Fel Regeneration Potion

    -- Blasted Lands / Dire Maul consumables (aura == item name, but the
    -- punctuation trips up name matching, so pin them explicitly).
    [8410]  = "R.O.I.D.S.",
    [8411]  = "Lung Juice Cocktail",
    [8412]  = "Ground Scorpok Assay",
    [8423]  = "Gizzard Gum",
    [8424]  = "Cerebral Cortex Compound",
}

-- ─── family patterns ─────────────────────────────────────────────────────────
-- Matched against the ITEM NAME. First match wins. The handler returns the
-- aura name. These cover every rank/variant without needing item IDs, which
-- is why they are preferred over a long ID list.
local PATTERNS = {
    -- "Scroll of Agility V" applies an aura simply called "Agility".
    -- Confirmed against this account's own older saved bindings, which had
    -- 27498 -> "Agility" and 27503 -> "Strength" before auto-detect
    -- overwrote them.
    { "^Scroll of (%a+)", function(stat) return stat end },

    -- Every Well-Fed food applies the same aura, whatever the dish is called.
    { "^Juju ",        function() return nil end },   -- handled by item name
    { "^Sheen of ",    function() return nil end },
    { "^Spirit of ",   function() return nil end },
}

-- Items that apply the shared "Well Fed" aura. Detected by item SUBTYPE so it
-- works for every food in the game, including ones added later.
local WELL_FED = "Well Fed"

-- Transient auras you get WHILE eating/drinking. These are never a valid
-- binding target - binding to them is exactly why food "randomly stopped
-- tracking" (they expire ~30s after the meal while Well Fed runs for 30 min).
C.EATING_AURAS = {
    ["Food"]         = true,
    ["Drink"]        = true,
    ["Food & Drink"] = true,
    ["Refreshment"]  = true,
}

-- ─── queries ─────────────────────────────────────────────────────────────────

-- True when the item is a Well-Fed food. Uses the item's subtype, so it needs
-- the item to be cached; callers re-resolve on GET_ITEM_INFO_RECEIVED.
function C:IsFood(itemID)
    if not itemID then return false end
    local _, _, _, _, _, itemType, subType = GetItemInfo(itemID)
    if subType == "Food & Drink" then return true end
    -- Conjured food/drink reports type Consumable, subtype Food & Drink in
    -- most clients; the check above covers it. Fall back to the item name for
    -- the handful of raid foods classed oddly.
    return false
end

-- The authoritative aura name for an item, or nil if unknown here.
-- Second return value is true when the answer is authoritative, meaning
-- runtime auto-detection must NEVER overwrite it.
function C:BuffFor(itemID)
    if not itemID then return nil, false end

    local exact = EXACT[itemID]
    if exact then return exact, true end

    if self:IsFood(itemID) then return WELL_FED, true end

    local name = GetItemInfo(itemID)
    if not name then return nil, false end

    for _, rule in ipairs(PATTERNS) do
        local cap = name:match(rule[1])
        if cap then
            local resolved = rule[2](cap)
            if resolved then return resolved, true end
            -- Rule matched but defers to the item name (Juju/Zanza style,
            -- where the aura is named exactly like the item).
            return name, true
        end
    end

    -- Flasks and elixirs: the aura is named exactly like the item in TBC.
    if name:find("^Flask of ") or name:find("Elixir") then
        return name, true
    end

    return nil, false
end

-- True if this aura must never be bound to a slot.
function C:IsBlacklisted(auraName)
    return self.EATING_AURAS[auraName] == true
end
