BuffBar = BuffBar or {}
local addon   = BuffBar
addon.AddZone = {}
local AddZone = addon.AddZone

local SLOT_GAP   = 2
local PADDING    = 4
local GRIP_WIDTH = 10

local function SlotSize() return (BuffBarDB and BuffBarDB.iconSize) or 28 end

local function TryAccept()
    local kind, itemID = GetCursorInfo()
    if kind == "item" and itemID then
        addon:AddItem(itemID)
        ClearCursor()
    end
end

function AddZone:Initialize()
    local frame = CreateFrame("Button", "BuffBarAddZone", addon.Bar.frame)
    frame:SetSize(SlotSize(), SlotSize())
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp")

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    local plus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    plus:SetPoint("CENTER")
    plus:SetText("+")
    plus:SetTextColor(0.5, 0.5, 0.5)

    frame:SetScript("OnReceiveDrag", TryAccept)
    frame:SetScript("OnClick",       TryAccept)

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("BuffBar")
        GameTooltip:AddLine("Drag a consumable here to track it.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click a tracked slot to use the item.", 1, 1, 1, true)
        GameTooltip:AddLine("Drag a slot to reorder; drag far outside to remove.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Middle-click any icon to open settings.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
        plus:SetTextColor(1, 1, 1)
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
        plus:SetTextColor(0.5, 0.5, 0.5)
    end)

    self.frame = frame
    self:Reposition()
end

function AddZone:Reposition(visibleCount)
    if not self.frame then return end
    local orient = BuffBarDB.orientation or "horizontal"
    local sz     = SlotSize()
    self.frame:SetSize(sz, sz)
    -- visibleCount is the number of slots currently displayed (may be < #items
    -- when "Hide when active" is on). Falls back to the full DB count.
    local n      = visibleCount or #BuffBarDB.items
    local slotsW = n * sz + math.max(0, n - 1) * SLOT_GAP
    local addGap = (n > 0) and SLOT_GAP or 0
    -- AddZone is only ever visible while unlocked, so the grip space is always
    -- present in the offset calculation.
    local lead   = PADDING + GRIP_WIDTH + SLOT_GAP
    local offset = lead + slotsW + addGap

    self.frame:ClearAllPoints()
    if orient == "horizontal" then
        self.frame:SetPoint("LEFT", addon.Bar.frame, "LEFT", offset, 0)
    else
        self.frame:SetPoint("TOP", addon.Bar.frame, "TOP", 0, -offset)
    end
end
