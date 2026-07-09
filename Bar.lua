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
    -- Bag count at click time. DetectNewBuff refuses to rebind unless this
    -- DROPS — proof the click actually consumed the item. Without that gate,
    -- any random proc (trinket, weapon, Battle Shout refresh…) landing inside
    -- the 25s window after a stray right-click hijacks the slot's binding.
    self._snapCount = GetItemCount(self.itemID) or 0
end

local function SlotPostClick(self, button, down)
    -- Click handling per button:
    --   * Right-click  → consume (secure type2 macro, set in Rebuild)
    --   * Left-drag    → reorder / remove (unlocked only, SlotOnDragStop)
    --   * Middle-click → open settings (F5) — works even when locked, so you
    --     never have to type /bb. Middle isn't bound to any secure action, so
    --     handling it here has no protected side effects. Fire once (on down).
    if button == "MiddleButton" and down then
        if BuffBar.Menu and BuffBar.Menu.Toggle then
            BuffBar.Menu:Toggle()
        end
    end
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

    -- Insecure overlay that swallows all mouse input while the slot is
    -- alpha-hidden. An alpha-0 frame STILL receives clicks, and right-click is
    -- the secure /use binding — so without this, camera right-clicks over an
    -- invisible slot silently consume the item. Show/Hide on this frame is
    -- combat-safe because it is not protected (the secure button is).
    local blocker = CreateFrame("Frame", nil, btn)
    blocker:SetAllPoints(btn)
    blocker:SetFrameLevel(btn:GetFrameLevel() + 10)
    blocker:EnableMouse(true)
    blocker:Hide()
    btn.blocker = blocker

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
    -- A corrupted saved point would make SetPoint throw DURING login init,
    -- killing the rest of the addon's setup — the bar then never appears at
    -- all. Validate and fall back to the default position instead.
    local p = BuffBarDB.point
    if type(p) ~= "table" or type(p[1]) ~= "string"
       or type(p[4]) ~= "number" or type(p[5]) ~= "number" then
        p = { "CENTER", "UIParent", "CENTER", 0, -200 }
        BuffBarDB.point = p
    end
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
        -- StartMoving on a frame with secure children is blocked in combat
        -- (confirmed ADDON_ACTION_BLOCKED in the error log) — don't try.
        if BuffBarDB.locked or InCombatLockdown() then return end
        grip._moving = true
        frame:StartMoving()
    end)
    grip:SetScript("OnDragStop", function()
        if not grip._moving then return end
        grip._moving = nil
        frame:StopMovingOrSizing()
        local pt, _, rel, x, y = frame:GetPoint(1)
        BuffBarDB.point = { pt, "UIParent", rel, math.floor(x), math.floor(y) }
    end)
    grip:SetScript("OnEnter", function(g)
        GameTooltip:SetOwner(g, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to move")
        GameTooltip:AddLine("Lock the bar from /bb settings", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Middle-click any icon to open settings", 0.7, 0.7, 0.7)
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
        -- Deduped: many events can request a rebuild during one fight
        -- (bag updates, item-info arrivals) — one post-combat rebuild covers
        -- them all.
        if not self._rebuildQueued then
            self._rebuildQueued = true
            table.insert(addon.combatQueue, function()
                Bar._rebuildQueued = nil
                Bar:Rebuild()
            end)
        end
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

            local name, link, _, _, _, _, subType, _, _, icon = GetItemInfo(entry.itemID)
            if icon then
                btn.icon:SetTexture(icon)
            else
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                addon.pendingItems[entry.itemID] = true
            end
            btn.labelFS:SetText(addon:ShortLabel(name or ""))

            -- Mark food slots so the eating-countdown placeholder (F3) knows
            -- which icons to show the eat timer on, independent of how the food
            -- was eaten (bar icon, bag, keybind, …). _sitTime is read straight
            -- from the item tooltip ("spend at least N seconds eating"), so the
            -- countdown is exact per food — defaulting to 10s if not yet cached.
            btn._isFood = (subType == "Food & Drink")
            if btn._isFood then
                btn._sitTime = addon:GetFoodSitTime(entry.itemID) or 10
            else
                btn._sitTime = nil
            end

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
    -- Every tracked item gets a FIXED slot here - positions depend only on how
    -- many items you track, never on buff state. "Hide when active" is applied as
    -- an ALPHA fade in RefreshSlot instead of pulling the icon out of the row, so
    -- a buff that fades mid-combat reappears instantly with NO secure re-layout
    -- (which is blocked in combat and was why icons didn't come back in raids).
    local orient     = BuffBarDB.orientation or "horizontal"
    local lead       = LeadingOffset(BuffBarDB.locked)
    local sz         = SlotSize()
    local showLabel  = BuffBarDB.showLabel ~= false
    local visIdx     = 0
    for _, btn in ipairs(self.slots) do
        if btn.itemID ~= nil then
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
            -- Respect hideWhenActive here too (LayoutSlots only runs out of
            -- combat, where a real Hide is legal) — otherwise every rebuild
            -- would flash hidden icons back on for a tick.
            if BuffBarDB.hideWhenActive and BuffBarDB.locked
               and self:IsBuffActive(btn) then
                btn:Hide()
            else
                btn:Show()
            end
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
    -- LayoutSlots (called below) shows/hides/moves the slot buttons, which are
    -- SECURE frames. WoW blocks that during combat lockdown and aborts the
    -- whole layout, collapsing the bar. Never touch them in combat — defer the
    -- entire re-layout until combat ends. (Deduped so we queue at most once.)
    if InCombatLockdown() then
        if not self._applyQueued then
            self._applyQueued = true
            table.insert(addon.combatQueue, function()
                Bar._applyQueued = nil
                Bar:ApplyLockState()
            end)
        end
        return
    end

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

    -- Pin a reference point across layouts so the icons never jump when you
    -- lock/unlock or when a buff hides:
    --   * Left-align  → pin the LEADING EDGE (first slot stays put, the row
    --                   shrinks from the right).
    --   * Center      → pin the row's CENTRE (icons stay centred and the row
    --                   shortens symmetrically toward the middle).
    -- We measure the reference from the CURRENT on-screen geometry (previous
    -- lead + previous visible count) before resizing, then reposition so that
    -- same reference lands in the same screen spot.
    local centered     = BuffBarDB.centered == true
    local prevLead     = LeadingOffset(self._lastLocked == nil and locked or self._lastLocked)
    local prevN        = self._lastN or n
    local prevSlotsLen = prevN * sz + math.max(0, prevN - 1) * SLOT_GAP
    local prevHalf     = centered and (prevSlotsLen / 2) or 0
    local newHalf      = centered and (slotsLen / 2) or 0

    local barLeft, barTop = self.frame:GetLeft(), self.frame:GetTop()
    local refMain, refCross
    if barLeft and barTop then
        if orient == "horizontal" then
            refMain  = barLeft + prevLead + prevHalf
            refCross = barTop
        else
            refMain  = barTop - prevLead - prevHalf
            refCross = barLeft
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

    -- Re-anchor so the pinned reference keeps its screen position
    if refMain and refCross then
        local newBarLeft, newBarTop
        if orient == "horizontal" then
            newBarLeft = refMain - newLead - newHalf
            newBarTop  = refCross
        else
            newBarTop  = refMain + newLead + newHalf
            newBarLeft = refCross
        end
        -- This position is SAVED — one bad geometry read (loading screen,
        -- scale change) must never strand the bar off-screen permanently.
        -- Clamp so at least a slot-sized corner always stays visible.
        local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
        newBarLeft = math.max(60 - mainLen, math.min(newBarLeft, sw - 60))
        newBarTop  = math.max(40, math.min(newBarTop, sh))
        self.frame:ClearAllPoints()
        self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            math.floor(newBarLeft), math.floor(newBarTop))
        BuffBarDB.point = { "TOPLEFT", "UIParent", "BOTTOMLEFT",
            math.floor(newBarLeft), math.floor(newBarTop) }
    end

    self._lastN = n

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

-- Hide a slot AND gate its clickability in one place. The two must never
-- disagree: an invisible slot that still takes clicks wastes consumables.
--
-- Two mechanisms depending on combat state:
--   * OUT of combat: really Hide() the secure button. Zero mouse footprint —
--     right-click camera panning works across the empty spot. (A mouse-
--     enabled blocker would eat the drag, which is why it's combat-only.)
--   * IN combat: Hide() on a secure frame is blocked, so fall back to
--     alpha 0 + the insecure click-blocker. Costs camera-drag over those
--     few icon-sized spots mid-fight, but guarantees no accidental /use.
-- PrepareForCombat() converts hidden slots to the combat form right before
-- lockdown starts (PLAYER_REGEN_DISABLED).
local function SetSlotInert(btn, inert)
    if InCombatLockdown() then
        btn:SetAlpha(inert and 0 or 1)
        if btn.blocker then
            if inert then btn.blocker:Show() else btn.blocker:Hide() end
        end
    else
        btn:SetAlpha(1)
        if btn.blocker then btn.blocker:Hide() end
        btn:SetShown(not inert)
    end
end

-- Called on PLAYER_REGEN_DISABLED, while secure Show/Hide is still legal:
-- convert really-hidden slots to shown-but-alpha-0 (+blocker) so they can
-- reappear mid-fight the moment their buff fades. Without this they'd be
-- stuck hidden until combat ends (the original raid bug).
function Bar:PrepareForCombat()
    for _, btn in ipairs(self.slots) do
        if btn.itemID and not btn:IsShown() then
            btn:SetAlpha(0)
            if btn.blocker then btn.blocker:Show() end
            btn:Show()
        end
    end
end

function Bar:RefreshSlot(btn)
    -- No IsShown() gate: a really-hidden slot (out-of-combat hideWhenActive)
    -- must still be re-evaluated so it re-Shows when its buff fades.
    if not btn.itemID then return end

    local showCount    = BuffBarDB.showCount    ~= false
    local showDuration = BuffBarDB.showDuration ~= false
    local showLabel    = BuffBarDB.showLabel    ~= false

    if showLabel then btn.labelFS:Show() else btn.labelFS:Hide() end

    -- Bag count (number of items / oil bottles you hold)
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
    local now     = GetTime()
    local buffUp  = active and expiration and (expiration - now) > 0

    -- Eating placeholder (F3): while the player is eating and Well Fed hasn't
    -- landed yet, count down the seconds left until you become Well Fed
    -- (eatStart + the food's required sit time, read from its tooltip). Set
    -- globally in DetectNewBuff, so this works no matter how the food was eaten.
    -- The real buff takes over the instant it lands (then hides if "Hide when
    -- active" is on); if you stand up early the countdown clears on its own.
    if btn._isFood and not buffUp and self._eatStart and self._eatUntil
       and now < self._eatUntil then
        local rem = (self._eatStart + (btn._sitTime or 10)) - now
        if rem < 0 then rem = 0 end
        -- Always shown, even when "show duration" is off — this is a transient
        -- "keep sitting" prompt, not the normal buff timer, so it deliberately
        -- writes over that setting until Well Fed lands.
        btn.durFS:SetText(FormatDuration(rem))
        btn.durFS:SetTextColor(1, 1, 1)
        btn.overlay:Hide()
        btn.icon:SetDesaturated(false)
        SetSlotInert(btn, false)        -- eat countdown is always visible
        return
    end

    if btn.weaponSlot or btn.spellName then
        if buffUp then
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
            -- "Hide when active": fade the icon out instead of removing it from
            -- the row (alpha is combat-safe; a secure Hide()/re-layout is not).
            -- Only while LOCKED - unlocked keeps everything visible for editing.
            -- SetSlotInert also raises the click-blocker so the invisible
            -- secure button can't consume the item on a stray right-click.
            SetSlotInert(btn, BuffBarDB.hideWhenActive and BuffBarDB.locked or false)
        else
            btn.durFS:SetText("")
            if showRed then btn.overlay:Show() else btn.overlay:Hide() end
            btn.icon:SetDesaturated(true)
            SetSlotInert(btn, false)   -- buff missing -> always visible
        end
    else
        btn.durFS:SetText("")
        SetSlotInert(btn, false)      -- count-based items are never auto-hidden
        if cnt == 0 then
            if showRed then btn.overlay:Show() else btn.overlay:Hide() end
            btn.icon:SetDesaturated(true)
        else
            btn.overlay:Hide()
            btn.icon:SetDesaturated(false)
        end
    end
end

-- Briefly highlight a slot so the user can SEE where an already-tracked item
-- lives (used when an add is rejected as a duplicate — e.g. an imported profile
-- already had the rune and the icon was a faint "?" they didn't notice).
function Bar:FlashSlot(index)
    local btn = self.slots and self.slots[index]
    if not btn or not btn.dropHL or not btn:IsShown() then return end
    btn.dropHL:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(1.2, function()
            if btn.dropHL then btn.dropHL:Hide() end
        end)
    end
end

-- A compact string describing which slots WOULD be visible right now, using the
-- same predicate as LayoutSlots. We only pay for a full re-layout when this
-- actually changes (a buff came up / dropped), instead of on every aura tick.
function Bar:_VisibleSignature()
    local hideActive = BuffBarDB.hideWhenActive
    local parts = {}
    for _, btn in ipairs(self.slots) do
        if btn.itemID then
            local hidden = hideActive and self:IsBuffActive(btn)
            parts[#parts + 1] = (btn.slotIndex or 0) .. (hidden and "h" or "v")
        end
    end
    return table.concat(parts, ",")
end

function Bar:RefreshAll()
    -- Layout no longer depends on buff state (positions are fixed per tracked
    -- item), so no secure re-layout is ever needed here - that deferred
    -- re-layout was exactly what left faded buffs hidden in raids until
    -- /reload. Iterate by itemID, NOT IsShown: really-hidden slots must be
    -- repainted too so they come back when their buff drops.
    for _, btn in ipairs(self.slots) do
        if btn.itemID then self:RefreshSlot(btn) end
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
-- checkbox toggle. Deferred during combat — Show/Hide on a frame with secure
-- children isn't allowed mid-fight — and re-run the moment combat ends, so a
-- bar that SHOULD be hidden never lingers on screen (invisible-but-clickable
-- slots have eaten consumables before).
function Bar:UpdateVisibility()
    if not self.frame then return end
    if InCombatLockdown() then
        if not self._visQueued then
            self._visQueued = true
            table.insert(addon.combatQueue, function()
                Bar._visQueued = nil
                Bar:UpdateVisibility()
            end)
        end
        return
    end
    -- Manual hide takes priority over everything else.
    if BuffBarDB.hidden then
        self.frame:Hide()
        return
    end
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

-- Transient "you are currently eating/drinking" buffs. These land the instant
-- you start eating (a few seconds long) and must NEVER be what a food slot
-- binds to — we want the real "Well Fed" buff that arrives ~10s later. Without
-- this blacklist the slot would briefly track "Food", then flip to red/expired
-- the moment you stand up.
local EATING_BUFFS = {
    ["Food"]        = true,
    ["Drink"]       = true,
    ["Food & Drink"] = true,
    ["Refreshment"] = true,
}

function Bar:DetectNewBuff()
    local now = GetTime()

    -- Global eat-window detection (F3), independent of HOW you started eating.
    -- If a transient eating aura is on the player, work out when eating BEGAN
    -- (expiration - duration of the aura) so any food slot can count down to
    -- Well Fed — even if you ate from the bag/a keybind and never touched the
    -- BuffBar icon. Both are cleared the moment the aura is gone.
    local eatUntil, eatStart = nil, nil
    for i = 1, 40 do
        local name, _, _, _, duration, expiration = UnitBuff("player", i)
        if not name then break end
        if EATING_BUFFS[name] and expiration and expiration > now then
            if not eatUntil or expiration > eatUntil then
                eatUntil = expiration
                -- Exact start when the aura reports a duration; otherwise fall
                -- back to the first moment we noticed eating (stable across ticks).
                if duration and duration > 0 then
                    eatStart = expiration - duration
                else
                    eatStart = self._eatStart or now
                end
            end
        end
    end
    self._eatUntil = eatUntil
    self._eatStart = eatStart

    for _, btn in ipairs(self.slots) do
        if not btn._buffSnapshot or not btn.slotIndex then
            -- skip
        elseif (now - (btn._snapshotTime or 0)) > SNAPSHOT_WINDOW then
            -- Window expired
            btn._buffSnapshot = nil
            btn._snapshotTime = nil
        elseif (GetItemCount(btn.itemID or 0) or 0) >= (btn._snapCount or 0) then
            -- Click didn't consume the item (blocked, on cooldown, already
            -- active, or a plain misclick) — NEVER rebind off procs that just
            -- happen to land now. Keep the window open: the bag update can
            -- lag a tick behind the aura event for a real consume.
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
                if fresh and selfCast and not EATING_BUFFS[name]
                   and expiration and expiration > bestExp then
                    bestName = name
                    bestExp  = expiration
                end
            end

            -- A slot that binds to "Well Fed" is definitely a food slot, even
            -- if GetItemInfo's subtype check missed it.
            if bestName == "Well Fed" then btn._isFood = true end

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
