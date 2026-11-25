-- wb_Notes minimap button. Left-click shows or hides the notes window.
-- Drag the button to move it around the minimap edge (position is saved).
-- /wbnotes minimap  hides or shows the button.

local ICON = 134327 -- same icon as the addon list

local btn = CreateFrame("Button", "WBNotesMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:SetMovable(true)
btn:EnableMouse(true)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local bg = btn:CreateTexture(nil, "BACKGROUND")
bg:SetSize(20, 20)
bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
bg:SetPoint("TOPLEFT", 7, -5)

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetTexture(ICON)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetPoint("TOPLEFT", 7, -6)

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

btn:Hide()

local function UpdatePosition()
  local angle = math.rad(WBN_DB.minimapAngle or 200)
  local radius = (Minimap:GetWidth() / 2) + 5
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  WBN_DB.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
  UpdatePosition()
end

btn:SetScript("OnDragStart", function(self)
  icon:SetTexCoord(0, 1, 0, 1)
  self:SetScript("OnUpdate", OnDragUpdate)
end)
btn:SetScript("OnDragStop", function(self)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  self:SetScript("OnUpdate", nil)
end)

btn:SetScript("OnClick", function()
  WBNotes_Toggle()
end)

btn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("wb_Notes")
  GameTooltip:AddLine("Click to show or hide notes", 1, 1, 1)
  GameTooltip:AddLine("Drag to move this button", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function ApplyShown()
  btn:SetShown(not WBN_DB.minimapHidden)
end

-- Add "/wbnotes minimap" on top of the existing slash command.
local baseSlash = SlashCmdList.WBNOTES
SlashCmdList.WBNOTES = function(msg)
  if (msg or ""):lower():match("^%s*minimap") then
    WBN_DB.minimapHidden = not WBN_DB.minimapHidden
    ApplyShown()
    print("wb_Notes: minimap button " .. (WBN_DB.minimapHidden and "hidden" or "shown") .. ".")
  else
    baseSlash(msg)
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  WBN_DB = WBN_DB or {}
  UpdatePosition()
  ApplyShown()
end)
