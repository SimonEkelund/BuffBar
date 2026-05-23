BuffBar = BuffBar or {}
local addon = BuffBar
addon.Bar   = {}
local Bar   = addon.Bar

local SLOT_GAP   = 2
local PADDING    = 4
local GRIP_WIDTH = 10
local POOL_SIZE  = 20

-- Reads the current per-slot pixel size from saved variables. Used everywhere
-- the old `SLOT_SIZE` constant used to appear so the user can change icon size
-- at runtime via the menu slider.
local function SlotSize()
    return (BuffBarDB and BuffBarDB.iconSize) or 28
end

Bar.slots = {}

-- ─── helpers ──────────────────────────────────────────────────────────────────

local function FormatDuration(t)
    -- Round UP so 4m53s shows as "5m", drops to "4m" only at 4m00s.
    if     t >= 3600 then return string.format("%dh", math.ceil(t / 3600))
    elseif t >= 60   then return string.format("%dm", math.ceil(t / 60))
    else                   return string.format("%ds", math.ceil(t))
    end
end

-- ─── slot scripts ─────────────────────────────────────────────────────────────

local function SlotOnUpdate(self, elapsed)
    self._tick = (self._tick or 0) + elapsed
    if self._tick < 0.2 then return end
    self._tick = 0
    Bar:RefreshSlot(self)
end

-- Snapshot all current player buffs BEFORE the secure click runs.
-- We record name → expirationTime so we can detect both NEW buffs and
-- REFRESHED buffs (when expiration jumps forward) — this matters for food
-- where Well Fed is often already up when you sit down to re-eat.
-- (Consume action is RIGHT-click — see SlotPostClick below.)
local function SlotPreClick(self, button)
    if button ~= "RightButton" or not self.itemID then return end
    if self.weaponSlot then return end
    local snapshot = {}
    for i = 1, 40 do
        local name, _, _, _, _, expiration = UnitBuff("player", i)
        if not name then break end
        snapshot[name] = expiration or 0
    end
    self._buffSnapshot = snapshot
    self._snapshotTime = GetTime()
end

local function SlotPostClick(self, button, down)
    -- Click handling is now uniform across lock states:
    --   * Right-click → consume (the secure type2 macro does this, set in
    --     Rebuild and always active when the slot has data)
    --   * Removal     → drag-far-from-bar (SlotOnDragStop), unlocked only
    -- PostClick is a no-op here; it stays defined for symmetry/future use.
end

-- ─── drag-to-sort / drag-to-remove ───────────────────────────────────────────

local REMOVE_DIST = 60   -- pixels outside bar bounds that trigger a removal

local dragProxy   -- lazy-created floating icon that follows the cursor

local function GetDragProxy()
    if dragProxy then return dragProxy end
    local f = CreateFrame("Frame", "BuffBarDragProxy", UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(100)
    f:EnableMouse(false)
    f:Hide()

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon = icon

    -- Colour-shifts to signal "remove" (red) or "valid drop" (blue).
    local tint = f:CreateTexture(nil, "OVERLAY")
    tint:SetAllPoints()
    tint:SetColorTexture(1, 1, 1, 0.2)
    f.tint = tint

    f:SetScript("OnUpdate", function()
        local mx, my = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mx / s, my / s)
        Bar:_DragUpdate()
    end)
    dragProxy = f
    return f
end

local function SlotOnDragStart(self)
    if BuffBarDB.locked or InCombatLockdown() then return end
    Bar._dragSrc = self.slotIndex
    local proxy = GetDragProxy()
    proxy:SetSize(SlotSize(), SlotSize())
    proxy.icon:SetTexture(self.icon:GetTexture())
    proxy:Show()
    self.icon:SetAlpha(0.35)
end

local function SlotOnDragStop(self)
    if dragProxy then dragProxy:Hide() end
    self.icon:SetAlpha(1.0)
    for _, btn in ipairs(Bar.slots) do
        if btn.dropHL then btn.dropHL:Hide() end
    end

    local src = Bar._dragSrc
    Bar._dragSrc = nil
    if not src or InCombatLockdown() then return end

    if Bar:_CursorFarFromBar() then
        addon:RemoveItem(src)
        return
    end

    local dst = Bar:_SlotIndexAtCursor()
    if dst and dst ~= src then
        local items = BuffBarDB.items
        local item  = table.remove(items, src)
        table.insert(items, dst, item)
        Bar:Rebuild()
    end
end

function Bar:_DragUpdate()
    local overIdx = self:_SlotIndexAtCursor()
    local far     = self:_CursorFarFromBar()
    local proxy   = dragProxy
    if not proxy or not proxy:IsShown() then return end

    if far then
        proxy.tint:SetColorTexture(1, 0.15, 0.15, 0.55)
    elseif overIdx and overIdx ~= self._dragSrc then
        proxy.tint:SetColorTexture(0.2, 0.65, 1, 0.45)
    else
        proxy.tint:SetColorTexture(1, 1, 1, 0.2)
    end

    for _, btn in ipairs(self.slots) do
        if btn.dropHL then
            local show = btn.slotIndex == overIdx and overIdx ~= self._dragSrc
            if show then btn.dropHL:Show() else btn.dropHL:Hide() end
        end
    end
end

function Bar:_SlotIndexAtCursor()
    local mx, my = GetCursorPosition()
    local s  = UIParent:GetEffectiveScale()
    local cx, cy = mx / s, my / s
    for _, btn in ipairs(self.slots) do
        if btn.itemID and btn.slotIndex and btn:IsShown() then
            local l, r = btn:GetLeft(), btn:GetRight()
            local b, t = btn:GetBottom(), btn:GetTop()
            if l and cx >= l and cx <= r and cy >= b and cy <= t then
                return btn.slotIndex
            end
        end
    end
end

function Bar:_CursorFarFromBar()
    local mx, my = GetCursorPosition()
    local s  = UIParent:GetEffectiveScale()
    local cx, cy = mx / s, my / s
    local f  = self.frame
    local l, r = f:GetLeft(), f:GetRight()
    local b, t = f:GetBottom(), f:GetTop()
    if not l then return false end
    local d = REMOVE_DIST
    return cx < l - d or cx > r + d or cy < b - d or cy > t + d
end

-- ─── slot creation ────────────────────────────────────────────────────────────

local function CreateSlot(i)
    local btn = CreateFrame("Button", "BuffBarSlot"..i,
                            Bar.frame, "SecureActionButtonTemplate")
    -- SlotSize is dynamic; we re-apply it in LayoutSlots so the user-chosen
    -- icon size from the menu slider is always reflected.
    btn:SetSize(SlotSize(), SlotSize())
    -- Register for BOTH up and down — TBC Anniversary client respects the
    -- ActionButtonUseKeyDown CVar, which causes the secure dispatch to fire
    -- on either down OR up depending on the user's setting. Registering both
    -- guarantees the click is captured regardless.
    btn:RegisterForClicks("AnyUp", "AnyDown")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetAllPoints()
    overlay:SetColorTexture(0.85, 0.1, 0.1, 0.45)
    overlay:Hide()
    btn.overlay = overlay

    -- Blue highlight shown on the slot that would receive a dragged slot.
    local dropHL = btn:CreateTexture(nil, "OVERLAY")
    dropHL:SetAllPoints()
    dropHL:SetColorTexture(0.2, 0.65, 1, 0.45)
    dropHL:Hide()
    btn.dropHL = dropHL

    local countFS = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    countFS:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.countFS = countFS

    -- Timer text BELOW the icon
    local durFS = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    durFS:SetPoint("TOP", btn, "BOTTOM", 0, -1)
    btn.durFS = durFS

    -- Short label under the icon (auto-shortened item name)
    local labelFS = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    labelFS:SetTextColor(0.95, 0.95, 0.95)
    btn.labelFS = labelFS

    btn:SetScript("OnUpdate",  SlotOnUpdate)
    btn:SetScript("PreClick",  SlotPreClick)
    btn:SetScript("PostClick", SlotPostClick)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", SlotOnDragStart)
    btn:SetScript("OnDragStop",  SlotOnDragStop)
    btn:Hide()
    return btn
end

-- ─── bar initialization ───────────────────────────────────────────────────────

function Bar:Initialize()
    local frame = CreateFrame("Frame", "BuffBarFrame", UIParent)
    frame:SetMovable(true)
    frame:EnableMouse(false)
    frame:SetSize(SlotSize() + PADDING * 2, SlotSize() + PADDING * 2)
    local p = BuffBarDB.point
    frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    self.frame = frame

    -- subtle dark background — only shown while the bar is unlocked so the
    -- player can see the drag target. When locked we hide it entirely so the
    -- icons sit flush on the world with no surrounding "frame".
    local fbg = frame:CreateTexture(nil, "BACKGROUND")
    fbg:SetAllPoints()
    fbg:SetColorTexture(0.05, 0.05, 0.05, 0.6)
    self.bg = fbg

    -- drag grip
    local grip = CreateFrame("Frame", "BuffBarGrip", frame)
    grip:SetSize(GRIP_WIDTH, SlotSize())
    grip:SetPoint("LEFT", frame, "LEFT", PADDING, 0)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
        if not BuffBarDB.locked then frame:StartMoving() end
    end)
    grip:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local pt, _, rel, x, y = frame:GetPoint(1)
        BuffBarDB.point = { pt, "UIParent", rel, math.floor(x), math.floor(y) }
    end)
    grip:SetScript("OnEnter", function(g)
        GameTooltip:SetOwner(g, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to move")
        GameTooltip:AddLine("Lock the bar from /bb settings", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local gbg = grip:CreateTexture(nil, "BACKGROUND")
    gbg:SetAllPoints()
    gbg:SetColorTexture(0.15, 0.15, 0.15, 0.9)

    local gdot = grip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gdot:SetPoint("CENTER")
    gdot:SetText(":")
    gdot:SetTextColor(0.65, 0.65, 0.65)

    self.grip = grip

    -- slot pool
    for i = 1, POOL_SIZE do
        self.slots[i] = CreateSlot(i)
    end
end

-- ─── rebuild ──────────────────────────────────────────────────────────────────

function Bar:Rebuild()
    if InCombatLockdown() then
        table.insert(addon.combatQueue, function() Bar:Rebuild() end)
        return
    end

    local items = BuffBarDB.items
    local n = #items

    for i, btn in ipairs(self.slots) do
        local entry = items[i]
        if entry then
            btn.slotIndex  = i
            btn.itemID     = entry.itemID
            btn.spellName  = entry.spellName
            btn.weaponSlot = entry.slot    -- 16 / 17 / nil

            local name, link, _, _, _, _, _, _, _, icon = GetItemInfo(entry.itemID)
            if icon then
                btn.icon:SetTexture(icon)
            else
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                addon.pendingItems[entry.itemID] = true
            end
            btn.labelFS:SetText(addon:ShortLabel(name or ""))

            -- Only fall back to GetItemSpell if we have nothing yet.
            -- Once auto-detection has bound the real buff name, don't overwrite it.
            if not entry.spellName then
                local resolved = addon:ResolveSpell(entry.itemID)
                if resolved then
                    entry.spellName = resolved
                    btn.spellName   = resolved
                end
            end

            -- Secure click: RIGHT button (type2) always runs /use, regardless
            -- of lock state. Removal is handled by drag-out (see DragStop).
            if name then
                local macro = "/use " .. name
                -- All slot-targeted items use the same two-line macro form:
                -- the first /use puts the item on the cursor, the second
                -- applies it to the equip slot (5 = chest, 16 = main hand,
                -- 17 = off hand).
                if entry.slot then
                    macro = macro .. "\n/use " .. entry.slot
                end
                btn:SetAttribute("type2", "macro")
                btn:SetAttribute("macrotext2", macro)
            else
                btn:SetAttribute("type2", nil)
                btn:SetAttribute("macrotext2", nil)
            end
            -- Wipe any stale attributes from the old left-click binding so
            -- LMB doesn't accidentally consume.
            btn:SetAttribute("type",       nil)
            btn:SetAttribute("type1",      nil)
            btn:SetAttribute("macrotext",  nil)
            btn:SetAttribute("macrotext1", nil)

            btn:Show()
        else
            btn:SetAttribute("type",       nil)
            btn:SetAttribute("type1",      nil)
            btn:SetAttribute("type2",      nil)
            btn:SetAttribute("macrotext",  nil)
            btn:SetAttribute("macrotext1", nil)
            btn:SetAttribute("macrotext2", nil)
            btn.slotIndex  = nil
            btn.itemID     = nil
            btn.spellName  = nil
            btn.weaponSlot = nil
            btn:Hide()
        end
    end

    self:ApplyLockState()
    self:ApplyFont()
    self:RefreshAll()
end

-- Returns the leading offset for the FIRST slot/AddZone along the main axis,
-- based on whether the grip is shown (= unlocked).
local function LeadingOffset(locked)
    if locked then return PADDING end
    return PADDING + GRIP_WIDTH + SLOT_GAP
end

-- True if the buff this slot tracks is currently active on the player.
function Bar:IsBuffActive(btn)
    if btn.weaponSlot then
        return (addon:GetSlotEnchantState(btn.weaponSlot)) and true or false
    elseif btn.spellName then
        return (addon:GetBuffState(btn.spellName)) and true or false
    end
    return false
end

-- Lay out every slot that should be visible, compressing the row so an
-- active-hidden slot in the middle doesn't leave a gap. Returns the visible
-- count so the caller can resize the bar and reposition the AddZone.
function Bar:LayoutSlots()
    local orient     = BuffBarDB.orientation or "horizontal"
    local lead       = LeadingOffset(BuffBarDB.locked)
    local hideActive = BuffBarDB.hideWhenActive
    local sz         = SlotSize()
    local showLabel  = BuffBarDB.showLabel ~= false
    local visIdx     = 0
    for _, btn in ipairs(self.slots) do
        local hasData = btn.itemID ~= nil
        local hideIt  = hasData and hideActive and self:IsBuffActive(btn)
        if hasData and not hideIt then
            visIdx = visIdx + 1
            btn:SetSize(sz, sz)                 -- pick up runtime size changes
            local off = lead + (visIdx - 1) * (sz + SLOT_GAP)
            btn:ClearAllPoints()
            btn.durFS:ClearAllPoints()
            btn.labelFS:ClearAllPoints()
            if orient == "horizontal" then
                btn:SetPoint("LEFT", self.frame, "LEFT", off, 0)
                -- With label on, timer moves ABOVE the icon so the label can
                -- sit below cleanly. Without label, timer stays below.
                if showLabel then
                    btn.durFS:SetPoint("BOTTOM", btn, "TOP", 0, 1)
                    btn.labelFS:SetPoint("TOP", btn, "BOTTOM", 0, -1)
                else
                    btn.durFS:SetPoint("TOP", btn, "BOTTOM", 0, -1)
                end
            else
                btn:SetPoint("TOP", self.frame, "TOP", 0, -off)
                btn.durFS:SetPoint("LEFT", btn, "RIGHT", 3, 0)
                btn.labelFS:SetPoint("TOPLEFT", btn, "TOPRIGHT", 3, 0)
                if showLabel and BuffBarDB.showDuration ~= false then
                    -- label sits below the timer in vertical mode
                    btn.labelFS:ClearAllPoints()
                    btn.labelFS:SetPoint("TOPLEFT", btn.durFS, "BOTTOMLEFT", 0, -1)
                end
            end
            btn:Show()
        elseif hasData then
            btn:Hide()         -- hidden by hideWhenActive, keep data
        end
    end
    return visIdx
end

-- Apply lock/unlock state:
--   * Hide the grip + AddZone when locked (clean look — just the icons)
--   * Resize the bar to fit only what's visible
--   * Reposition the bar so the FIRST SLOT stays at the same screen pixel
--     across toggles (so toggling doesn't make your tracked items "jump")
function Bar:ApplyLockState()
    local locked = BuffBarDB.locked
    local orient = BuffBarDB.orientation or "horizontal"

    -- Bar background + grip first (they affect what LayoutSlots's offsets mean)
    if self.bg then
        if locked then self.bg:Hide() else self.bg:Show() end
    end
    local sz = SlotSize()
    if locked then
        self.grip:Hide()
    else
        self.grip:Show()
        self.grip:ClearAllPoints()
        if orient == "horizontal" then
            self.grip:SetSize(GRIP_WIDTH, sz)
            self.grip:SetPoint("LEFT", self.frame, "LEFT", PADDING, 0)
        else
            self.grip:SetSize(sz, GRIP_WIDTH)
            self.grip:SetPoint("TOP", self.frame, "TOP", 0, -PADDING)
        end
    end

    -- LayoutSlots positions every visible slot (skipping ones hidden by the
    -- hideWhenActive option) and returns how many are actually showing.
    local n = self:LayoutSlots()
    local slotsLen = n * sz + math.max(0, n - 1) * SLOT_GAP

    -- Where does the first slot currently sit, in absolute screen coords?
    -- (We pin THIS point — not the bar's TOPLEFT — so locking/unlocking and
    -- the grip appearing/disappearing don't shift any tracked icons.)
    local prevLead = LeadingOffset(self._lastLocked == nil and locked or self._lastLocked)
    local barLeft, barTop = self.frame:GetLeft(), self.frame:GetTop()
    local contentLeft, contentTop
    if barLeft and barTop then
        if orient == "horizontal" then
            contentLeft = barLeft + prevLead
            contentTop  = barTop
        else
            contentLeft = barLeft
            contentTop  = barTop - prevLead
        end
    end

    -- New bar size along the main axis
    local newLead = LeadingOffset(locked)
    local mainLen = newLead + slotsLen
    if not locked then
        -- Reserve room for the AddZone at the trailing edge
        mainLen = mainLen + (n > 0 and SLOT_GAP or 0) + sz
    end
    mainLen = mainLen + PADDING                          -- trailing padding
    mainLen = math.max(mainLen, sz + PADDING * 2)        -- minimum visible bar

    -- Bar size
    if orient == "horizontal" then
        self.frame:SetSize(mainLen, sz + PADDING * 2)
    else
        self.frame:SetSize(sz + PADDING * 2, mainLen)
    end

    -- Apply alpha (transparency slider)
    self.frame:SetAlpha(BuffBarDB.alpha or 1.0)

    -- Re-anchor so the first slot's screen position is preserved
    if contentLeft and contentTop then
        local newBarLeft, newBarTop
        if orient == "horizontal" then
            newBarLeft = contentLeft - newLead
            newBarTop  = contentTop
        else
            newBarLeft = contentLeft
            newBarTop  = contentTop + newLead
        end
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            math.floor(newBarLeft), math.floor(newBarTop))
        BuffBarDB.point = { "TOPLEFT", "UIParent", "BOTTOMLEFT",
            math.floor(newBarLeft), math.floor(newBarTop) }
    end

    -- AddZone (positioned after the LAST visible slot, not after total #items)
    if addon.AddZone and addon.AddZone.frame then
        if locked then
            addon.AddZone.frame:Hide()
        else
            addon.AddZone.frame:Show()
            if addon.AddZone.Reposition then
                addon.AddZone:Reposition(n)
            end
        end
    end

    self._lastLocked = locked
end

-- ─── visual refresh ───────────────────────────────────────────────────────────

function Bar:RefreshSlot(btn)
    if not btn.itemID or not btn:IsShown() then return end

    local showCount    = BuffBarDB.showCount    ~= false
    local showDuration = BuffBarDB.showDuration ~= false
    local showLabel    = BuffBarDB.showLabel    ~= false

    if showLabel then btn.labelFS:Show() else btn.labelFS:Hide() end

    -- Bag count
    local cnt = GetItemCount(btn.itemID) or 0
    if showCount then
        btn.countFS:SetText(tostring(cnt))
        if cnt == 0 then
            btn.countFS:SetTextColor(1, 0.2, 0.2)
        else
            btn.countFS:SetTextColor(1, 1, 1)
        end
    else
        btn.countFS:SetText("")
    end

    -- Pick the right "is the buff up?" check for this entry:
    --   weaponSlot set  → GetWeaponEnchantInfo (sharpening stones / oils)
    --   spellName set   → UnitBuff name match (elixirs / flasks / food)
    --   neither set     → count-based only (healthstones / mana pots)
    local active, expiration
    if btn.weaponSlot then
        active, expiration = addon:GetSlotEnchantState(btn.weaponSlot)
    elseif btn.spellName then
        active, expiration = addon:GetBuffState(btn.spellName)
    end

    local showRed = BuffBarDB.showRedOverlay == true

    if btn.weaponSlot or btn.spellName then
        if active and expiration and (expiration - GetTime()) > 0 then
            local rem = expiration - GetTime()
            if showDuration then
                btn.durFS:SetText(FormatDuration(rem))
                if rem < 10 then
                    btn.durFS:SetTextColor(1, 0.3, 0.3)
                else
                    btn.durFS:SetTextColor(1, 1, 1)
                end
            else
                btn.durFS:SetText("")
            end
            btn.overlay:Hide()
            btn.icon:SetDesaturated(false)
        else
            btn.durFS:SetText("")
            if showRed then btn.overlay:Show() else btn.overlay:Hide() end
            btn.icon:SetDesaturated(true)
        end
    else
        btn.durFS:SetText("")
        if cnt == 0 then
            if showRed then btn.overlay:Show() else btn.overlay:Hide() end
            btn.icon:SetDesaturated(true)
        else
            btn.overlay:Hide()
            btn.icon:SetDesaturated(false)
        end
    end
end

function Bar:RefreshAll()
    -- When hideWhenActive is on, buff state changes alter the layout — re-run
    -- ApplyLockState so slots compress/expand in real time.
    if BuffBarDB.hideWhenActive then
        self:ApplyLockState()
    end
    for _, btn in ipairs(self.slots) do
        if btn:IsShown() then self:RefreshSlot(btn) end
    end
end

-- Re-apply the user-chosen font path to every text region on every slot.
-- Some addon-bundled fonts only accept certain flag combinations or fail
-- silently — we try a couple of fallbacks and finally Friz Quadrata so the
-- text never disappears, regardless of which font the user picked.
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
function Bar:ApplyFont()
    local fontPath = (BuffBarDB and BuffBarDB.font) or DEFAULT_FONT
    for _, btn in ipairs(self.slots) do
        for _, fs in ipairs({ btn.countFS, btn.durFS, btn.labelFS }) do
            if fs then
                local _, size, flags = fs:GetFont()
                size  = size  or 10
                flags = flags or ""
                local ok = fs:SetFont(fontPath, size, flags)
                if not ok then ok = fs:SetFont(fontPath, size, "OUTLINE") end
                if not ok then ok = fs:SetFont(fontPath, size, "") end
                if not ok then fs:SetFont(DEFAULT_FONT, size, flags) end
            end
        end
    end
end

-- Show or hide the entire bar based on the "instances only" setting and the
-- player's current instance type. Called on PLAYER_ENTERING_WORLD (which
-- fires on login, /reload, and any instance enter/leave) and on the menu
-- checkbox toggle. Skipped silently during combat — Show/Hide on a frame
-- with secure children isn't allowed mid-fight.
function Bar:UpdateVisibility()
    if not self.frame then return end
    if InCombatLockdown() then return end
    if not BuffBarDB.instancesOnly then
        self.frame:Show()
        return
    end
    local _, instanceType = IsInInstance()
    if instanceType == "party" or instanceType == "raid" then
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

-- Called from Core.lua on UNIT_AURA(player) and combat-log aura events.
-- After the user clicks a slot we snapshot their buffs and watch for new ones
-- over a 25-second window. Within that window we keep updating the binding to
-- whichever NEW self-applied buff has the LONGEST remaining duration.
--
-- Why long: food applies a short "Food" buff (~30 s) immediately, then the
-- real "Well Fed" buff (~15-30 min) lands ~10 s later. The first-seen logic
-- would bind to "Food" and then everything turns red as soon as eating ends.
-- By preferring the longest duration and watching for the full window, we
-- correctly converge on the actual food buff.
--
-- Filter `source == "player"` avoids binding to e.g. someone else's PWF that
-- coincidentally lands during the window.
local SNAPSHOT_WINDOW = 25

function Bar:DetectNewBuff()
    local now = GetTime()
    for _, btn in ipairs(self.slots) do
        if not btn._buffSnapshot or not btn.slotIndex then
            -- skip
        elseif (now - (btn._snapshotTime or 0)) > SNAPSHOT_WINDOW then
            -- Window expired
            btn._buffSnapshot = nil
            btn._snapshotTime = nil
        else
            -- Find the best new-or-refreshed self-applied buff
            -- (longest remaining duration). A buff is interesting if:
            --   - it wasn't in the snapshot at all, OR
            --   - it was, but its expiration jumped >1s forward (= refreshed)
            local bestName, bestExp = nil, 0
            for i = 1, 40 do
                local name, _, _, _, _, expiration, source = UnitBuff("player", i)
                if not name then break end
                local snapExp  = btn._buffSnapshot[name]
                local fresh    = (snapExp == nil) or
                                 (expiration and expiration > snapExp + 1)
                local selfCast = (source == "player" or source == nil)
                if fresh and selfCast and expiration and expiration > bestExp then
                    bestName = name
                    bestExp  = expiration
                end
            end

            -- Only update + announce when we actually change the binding.
            if bestName and bestName ~= btn.spellName then
                btn.spellName = bestName
                if BuffBarDB.items[btn.slotIndex] then
                    BuffBarDB.items[btn.slotIndex].spellName = bestName
                end
                addon:Print("Bound buff '" .. bestName ..
                    "' to slot " .. btn.slotIndex)
            end
        end
    end
end
