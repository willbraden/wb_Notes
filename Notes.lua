-- wb_Notes: a standalone notes window. Plain text that saves as you type, shown with
-- light markdown formatting when you're not editing. Click the note to edit, Esc (or
-- click away) to go back to the formatted view. Ctrl+Z / Ctrl+Y to undo / redo.
--
-- Supported: # / ## / ### headings, - or * bullets (indent with 2 spaces), 1. numbered,
-- - [ ] / - [x] tasks (click the box to tick it), **bold**, *italic*, `code`,
-- > quotes, and --- for a divider line.
--
-- The window floats over the game: drag the title to move, drag the corner to resize.
-- It doesn't touch the game view or the rest of the UI. Notes are account-wide.
-- Type /wbnotes (or set a keybind) to show or hide it.

local MD = WBNotes_Markdown

BINDING_HEADER_WBNOTES = "wb_Notes"
BINDING_NAME_WBNOTES_TOGGLE = "Show or hide notes"

local function BuildNotes(content)
  local HEAD_FONTS = { GameFontNormalHuge or GameFontNormalLarge, GameFontNormalLarge, GameFontNormal }

  -- Scrollbar: the thin modern one the chat window uses, if this client has it;
  -- otherwise the classic panel scrollbar.
  local scroll, BAR_ROOM
  if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
    local ok, f = pcall(CreateFrame, "ScrollFrame", "WBNotesScroll", content, "ScrollFrameTemplate")
    if ok and f and f.ScrollBar then
      scroll, BAR_ROOM = f, 16
    end
  end
  if not scroll then
    scroll, BAR_ROOM = CreateFrame("ScrollFrame", "WBNotesScroll", content, "UIPanelScrollFrameTemplate"), 24
  end
  scroll:SetPoint("TOPLEFT", 0, -2)
  scroll:SetPoint("BOTTOMRIGHT", -BAR_ROOM, 0) -- room for the scrollbar

  -- Jump-to-top button: the chat window's jump-to-bottom button, turned 180 degrees.
  local topBtn = CreateFrame("Button", nil, content)
  do
    local src = ChatFrame1 and ChatFrame1.ScrollToBottomButton
    local w, h = 20, 20
    if src and src.GetSize then
      local sw, sh = src:GetSize()
      if sw and sw > 0 then w, h = math.min(sw, 24), math.min(sh, 24) end
    end
    topBtn:SetSize(w, h)
    -- Copy one of the source button's textures and rotate it 180 degrees.
    local function Rotated(layer, srcTex, fallback)
      local t = topBtn:CreateTexture(nil, layer)
      t:SetAllPoints()
      local atlas = srcTex and srcTex.GetAtlas and srcTex:GetAtlas()
      if atlas and atlas ~= "" then
        t:SetAtlas(atlas)
      elseif srcTex and srcTex:GetTexture() then
        t:SetTexture(srcTex:GetTexture())
        t:SetTexCoord(srcTex:GetTexCoord())
      else
        t:SetTexture(fallback)
      end
      local ulx, uly, llx, lly, urx, ury, lrx, lry = t:GetTexCoord()
      t:SetTexCoord(lrx, lry, urx, ury, llx, lly, ulx, uly)
      return t
    end
    local up = Rotated("ARTWORK", src and src:GetNormalTexture(), "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Up")
    local down = Rotated("ARTWORK", src and src:GetPushedTexture(), "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Down")
    down:Hide()
    local hl = Rotated("HIGHLIGHT", src and src:GetHighlightTexture(), "Interface\\ChatFrame\\UI-Common-MouseHilight")
    hl:SetBlendMode("ADD")
    topBtn:SetScript("OnMouseDown", function() up:Hide(); down:Show() end)
    topBtn:SetScript("OnMouseUp", function() down:Hide(); up:Show() end)
  end
  topBtn:SetScript("OnClick", function() scroll:SetVerticalScroll(0) end)
  topBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Jump to top")
    GameTooltip:Show()
  end)
  topBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- The button tops the scrollbar strip, with the scrollbar under it.
  local topW, topH = topBtn:GetSize()
  local modernBar = BAR_ROOM == 16
  local bar = scroll.ScrollBar or _G["WBNotesScrollScrollBar"]
  topBtn:SetPoint("TOP", scroll, "TOPRIGHT", BAR_ROOM / 2, 0)
  if modernBar then
    bar:ClearAllPoints()
    bar:SetPoint("TOP", scroll, "TOPRIGHT", BAR_ROOM / 2, -(topH + 2))
    bar:SetPoint("BOTTOM", scroll, "BOTTOMRIGHT", BAR_ROOM / 2, 0)
  end

  -- Flashing, like the chat window's jump button when there's new text below.
  local flash = topBtn:CreateAnimationGroup()
  flash:SetLooping("BOUNCE")
  local pulse = flash:CreateAnimation("Alpha")
  pulse:SetFromAlpha(0.5) -- matches the dimmed strip
  pulse:SetToAlpha(0.15)
  pulse:SetDuration(0.7)
  pulse:SetSmoothing("IN_OUT")

  -- Edit mode: scrollbar and button always shown.
  -- Default mode: scrolling wakes the strip; after a short pause it fades to half
  -- opacity. If you're scrolled down, the jump-to-top button flashes.
  local IDLE, FADE, DIM = 2, 0.4, 0.5
  local token = 0
  local function AtTop() return scroll:GetVerticalScroll() <= 1 end
  local function Scrollable() return (scroll:GetVerticalScrollRange() or 0) > 1 end
  local function FadeOut(f, t)
    if not f:IsShown() then return end
    UIFrameFadeOut(f, FADE, f:GetAlpha(), 0)
    C_Timer.After(FADE + 0.05, function() if t == token then f:Hide() end end)
  end
  local function Settle(t) -- runs after the idle pause
    if t ~= token or not WBN_DB.transparent then return end
    if bar and bar:IsShown() then UIFrameFadeOut(bar, FADE, bar:GetAlpha(), DIM) end
    if modernBar and not AtTop() and not WBN_DB.folded then
      topBtn:SetAlpha(DIM)
      topBtn:Show()
      flash:Play()
    else
      FadeOut(topBtn, t) -- at the top there's nothing to jump to
    end
  end
  local function Wake()
    token = token + 1
    flash:Stop()
    if WBN_DB.transparent then
      local show = Scrollable()
      if bar then
        if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(bar) end
        bar:SetAlpha(1); bar:SetShown(show)
      end
      if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(topBtn) end
      topBtn:SetAlpha(1); topBtn:SetShown(modernBar and show and not AtTop())
      local t = token
      C_Timer.After(IDLE, function() Settle(t) end)
    else
      if bar then bar:SetAlpha(1); bar:Show() end
      topBtn:SetAlpha(1); topBtn:SetShown(modernBar)
    end
  end
  content.WakeScroll = Wake
  scroll:HookScript("OnVerticalScroll", Wake)
  scroll:HookScript("OnMouseWheel", Wake) -- also wakes it when already at an end

  -- Edit mode: raw text.
  local edit = CreateFrame("EditBox", "WBNotesEdit", scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(MD.BodyFont)
  edit:SetTextInsets(19, 19, 2, 2) -- lines up with the formatted text
  edit:SetMaxLetters(0)
  edit:SetWidth(250)
  edit:SetText(WBN_DB.notes or "")
  edit.cursorOffset, edit.cursorHeight = 0, 0
  edit:Hide()

  -- View mode: formatted (shared renderer, same as other wb_ panel addons).
  local view = MD.NewView(scroll)
  view.padX = 17 -- body text inset; heading bars span the full width like the title bar
  view:EnableMouse(true)
  WBN_DB.collapsed = WBN_DB.collapsed or {}
  view.collapsed = WBN_DB.collapsed -- folded headings are remembered
  local width = 250
  local HINT = MD.Parse("Click to write a note.\n\nFormatting: # heading, - bullet, - [ ] task, **bold**, *italic*, `code`, > quote, --- divider")
  for _, b in ipairs(HINT) do if b.text then b.text = "|cff666666" .. b.text .. "|r" end end

  local function Refresh()
    local blocks = MD.Parse(WBN_DB.notes)
    view:Render(#blocks > 0 and blocks or HINT, width)
  end

  -- Undo / redo. Typing is grouped: a snapshot is taken after a short pause.
  local history, pos, MAX = {}, 0, 200
  local applying = false
  local typingToken = 0
  local function Snapshot()
    local text = WBN_DB.notes or ""
    if history[pos] and history[pos].text == text then return end
    for i = #history, pos + 1, -1 do history[i] = nil end
    history[#history + 1] = { text = text, cursor = edit:GetCursorPosition() }
    if #history > MAX then table.remove(history, 1) end
    pos = #history
  end
  local function Apply(h)
    applying = true
    WBN_DB.notes = h.text
    edit:SetText(h.text)
    edit:SetCursorPosition(math.min(h.cursor or #h.text, #h.text))
    applying = false
  end
  local function Undo()
    typingToken = typingToken + 1
    Snapshot() -- keep any typing that hasn't been grouped yet
    if pos > 1 then pos = pos - 1; Apply(history[pos]) end
  end
  local function Redo()
    if pos < #history then pos = pos + 1; Apply(history[pos]) end
  end
  edit:SetScript("OnKeyDown", function(_, key)
    local mod = IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())
    if not mod then return end
    -- Run after this key's own text input (if any), so a stray letter can't sneak in.
    if key == "Z" then
      local redo = IsShiftKeyDown()
      C_Timer.After(0, redo and Redo or Undo)
    elseif key == "Y" then
      C_Timer.After(0, Redo)
    end
  end)

  local editing = false
  local function ShowView()
    editing = false
    edit:Hide()
    Refresh()
    view:Show()
    scroll:SetScrollChild(view)
    scroll:SetVerticalScroll(0)
  end
  local function ShowEdit()
    if editing then return end
    editing = true
    view:Hide()
    edit:SetText(WBN_DB.notes or "")
    edit:Show()
    scroll:SetScrollChild(edit)
    Snapshot()
    edit:SetFocus()
    edit:SetCursorPosition(#edit:GetText())
  end

  -- Autosave on every edit.
  edit:SetScript("OnTextChanged", function(self, userInput)
    if userInput and not applying then
      WBN_DB.notes = self:GetText()
      typingToken = typingToken + 1
      local t = typingToken
      C_Timer.After(0.7, function() if t == typingToken then Snapshot() end end)
    end
    if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, scroll) end
  end)
  edit:SetScript("OnCursorChanged", function(self, x, y, w, h)
    if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, x, y, w, h) end
  end)
  edit:SetScript("OnUpdate", function(self, elapsed)
    if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, scroll) end
  end)
  edit:SetScript("OnEscapePressed", edit.ClearFocus)
  edit:SetScript("OnEditFocusLost", ShowView)

  -- Tick a task box from the formatted view.
  view.OnTick = function(n)
    local lines, i = {}, 0
    for raw in ((WBN_DB.notes or "") .. "\n"):gmatch("(.-)\n") do
      i = i + 1
      local line = raw
      if i == n then
        line = line:gsub("%[([ xX])%]", function(m) return m == " " and "[x]" or "[ ]" end, 1)
      end
      lines[#lines + 1] = line
    end
    Snapshot()
    WBN_DB.notes = table.concat(lines, "\n")
    Snapshot()
    Refresh()
  end

  -- Click the note (anywhere but a task box) to edit.
  view:SetScript("OnMouseUp", ShowEdit)
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseUp", ShowEdit)

  -- Track width changes (panel resize).
  scroll:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then
      width = w
      edit:SetWidth(w)
      if not editing then Refresh() end
    end
  end)

  -- Default mode: heavier text shadow so it reads over the game.
  content.SetShadowText = function(on)
    view.shadow = on
    edit:SetTextColor(1, 1, 1)
    edit:SetShadowColor(0, 0, 0, 1)
    if on then edit:SetShadowOffset(2, -2) else edit:SetShadowOffset(1, -1) end
    if not editing then Refresh() end
  end


  -- Default mode also makes the notes click-through: mouse clicks go to the game.
  -- Task boxes, fold buttons and the mouse wheel still work.
  content.SetPassThrough = function(on)
    if on and editing then edit:ClearFocus() end -- drops back to the formatted view
    scroll:EnableMouse(not on)
    scroll:EnableMouseWheel(true) -- wheel scrolls the notes even when click-through
    view:EnableMouse(not on)
    view.passThrough = on
    if not editing then Refresh() end
  end

  -- Don't keep grabbing your keyboard after the panel closes.
  content:HookScript("OnHide", function() edit:ClearFocus() end)

  ShowView()
end


---------------------------------------------------------------- window

local win = CreateFrame("Frame", "WBNotesFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
win:SetFrameStrata("MEDIUM")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:SetResizable(true)
local TITLE_H = 34 -- window height when folded: just the title bar
local function SetMinHeight(h)
  if win.SetResizeBounds then win:SetResizeBounds(200, h, 800, 1000)
  elseif win.SetMinResize then win:SetMinResize(200, h); win:SetMaxResize(800, 1000) end
end
SetMinHeight(150)
win:SetBackdrop({
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
})
win:SetBackdropColor(0.06, 0.06, 0.08, 0.94)
win:SetBackdropBorderColor(0.25, 0.25, 0.3, 1)
win:Hide()

-- Title bar: drag to move.
local titleBar = CreateFrame("Frame", nil, win)
titleBar:SetPoint("TOPLEFT", 1, -1)
titleBar:SetPoint("TOPRIGHT", -1, -1)
titleBar:SetHeight(32) -- stock "All Objectives" header is 32 tall
titleBar:EnableMouse(true)
titleBar:RegisterForDrag("LeftButton")
local tbg = titleBar:CreateTexture(nil, "BACKGROUND")
-- The stock header art draws past its 32px frame; let ours do the same.
tbg:SetPoint("TOPLEFT", 0, 4)
tbg:SetPoint("BOTTOMRIGHT", 0, -4)
if not MD.ApplyArt(tbg, MD.art.primary) then tbg:SetColorTexture(1, 1, 1, 0.05) end
local title = titleBar:CreateFontString(nil, "OVERLAY")
title:SetFontObject(ObjectiveTrackerHeaderFont or GameFontNormalMed2 or GameFontNormalLarge)
title:SetPoint("LEFT", 30, 0)
title:SetText("Notes")

local function SavePos()
  local point, _, rel, x, y = win:GetPoint(1)
  WBN_DB.pos = { point, rel, x, y }
  WBN_DB.w = win:GetWidth()
  if not WBN_DB.folded then WBN_DB.h = win:GetHeight() end -- keep the open height while folded
end
titleBar:SetScript("OnDragStart", function() win:StartMoving() end)
titleBar:SetScript("OnDragStop", function() win:StopMovingOrSizing(); SavePos() end)

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)
close:SetScript("OnClick", function() win:Hide() end)

local content -- the notes area, created below
local grip -- resize grip, created below

-- Mode button (padlock). Locked = Default mode: no window background, click-through,
-- notes read over the game. Unlocked = Edit mode: solid window you can click into,
-- move and resize. (Saved as WBN_DB.transparent; true = Default mode.)
local LOCKED = "Interface\\Buttons\\LockButton-Locked-Up"
local UNLOCKED = "Interface\\Buttons\\LockButton-Unlocked-Up"
local transBtn = CreateFrame("Button", nil, titleBar)
transBtn:SetSize(18, 19) -- same size as the stock tracker's header buttons
-- The lock art has empty space around it; crop that off so the lock fills the button.
local LOCK_CROP = { 0.17, 0.83, 0.17, 0.83 }
local lockTex = transBtn:CreateTexture(nil, "ARTWORK")
lockTex:SetAllPoints()
local lockHl = transBtn:CreateTexture(nil, "HIGHLIGHT")
lockHl:SetAllPoints()
lockHl:SetAtlas("UI-QuestTrackerButton-Red-Highlight") -- stock header button hover
lockHl:SetBlendMode("ADD")

-- Fold button: collapses the whole note to just the title bar, like the stock tracker.
local foldBtn = CreateFrame("Button", nil, titleBar)
foldBtn:SetSize(18, 19) -- stock tracker minimize button: size and art below
local FOLD = {
  collapse = { "UI-QuestTrackerButton-Collapse-All", "UI-QuestTrackerButton-Collapse-All-Pressed" },
  expand   = { "UI-QuestTrackerButton-Expand-All", "UI-QuestTrackerButton-Expand-All-Pressed" },
}
local foldTex = foldBtn:CreateTexture(nil, "ARTWORK")
foldTex:SetAllPoints()
local foldHl = foldBtn:CreateTexture(nil, "HIGHLIGHT")
foldHl:SetAllPoints()
foldHl:SetAtlas("UI-QuestTrackerButton-Red-Highlight")
foldHl:SetBlendMode("ADD")
local function SetFoldArt(pressed)
  local set = WBN_DB.folded and FOLD.expand or FOLD.collapse
  if foldTex:SetAtlas(set[pressed and 2 or 1]) == false then
    foldTex:SetAtlas(set[1]) -- no pressed art: keep the normal one
  end
end
foldBtn:SetScript("OnMouseDown", function() SetFoldArt(true) end)
foldBtn:SetScript("OnMouseUp", function() SetFoldArt(false) end)
transBtn:SetPoint("RIGHT", foldBtn, "LEFT", -4, 0)

local function ApplyFold()
  local folded = WBN_DB.folded
  SetFoldArt(false)
  content:SetShown(not folded)
  if content.WakeScroll and not folded then content.WakeScroll() end
  grip:SetShown(not folded and not WBN_DB.transparent)
  -- Pin the top edge so the title bar stays put while the height changes.
  local l, t = win:GetLeft(), win:GetTop()
  if l and t then
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    WBN_DB.pos = { "TOPLEFT", "BOTTOMLEFT", l, t }
  end
  if folded then
    SetMinHeight(TITLE_H)
    win:SetHeight(TITLE_H)
  else
    win:SetHeight(WBN_DB.h or 400)
    SetMinHeight(150)
  end
end

foldBtn:SetScript("OnClick", function()
  WBN_DB.folded = not WBN_DB.folded
  ApplyFold()
end)
foldBtn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine(WBN_DB.folded and "Expand notes" or "Collapse notes")
  GameTooltip:Show()
end)
foldBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function ApplyTransparent()
  local on = WBN_DB.transparent
  if on then
    win:SetBackdropColor(0, 0, 0, 0)
    win:SetBackdropBorderColor(0, 0, 0, 0)
  else
    win:SetBackdropColor(0.06, 0.06, 0.08, 0.94)
    win:SetBackdropBorderColor(0.25, 0.25, 0.3, 1)
  end
  lockTex:SetTexture(on and LOCKED or UNLOCKED)
  lockTex:SetTexCoord(unpack(LOCK_CROP))
  close:SetShown(not on)
  grip:SetShown(not on and not WBN_DB.folded)
  -- Inside the bar art; in solid mode, clear of the close button.
  foldBtn:ClearAllPoints()
  foldBtn:SetPoint("RIGHT", titleBar, "RIGHT", on and -22 or -34, 0)
  if content.WakeScroll then content.WakeScroll() end
  titleBar:EnableMouse(not on) -- no dragging; the toggle button stays clickable
  if content.SetPassThrough then content.SetPassThrough(on) end
  title:SetShadowColor(0, 0, 0, 1)
  title:SetShadowOffset(1, -1) -- stock shadow; the header bar gives it contrast
  if content.SetShadowText then content.SetShadowText(on) end
end

transBtn:SetScript("OnClick", function()
  WBN_DB.transparent = not WBN_DB.transparent
  ApplyTransparent()
end)
transBtn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  if WBN_DB.transparent then
    GameTooltip:AddLine("Edit mode")
    GameTooltip:AddLine("Unlock to edit, move and resize the notes", 1, 1, 1)
  else
    GameTooltip:AddLine("Done editing")
    GameTooltip:AddLine("Lock the notes in place and let clicks through to the game", 1, 1, 1)
  end
  GameTooltip:Show()
end)
transBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Resize grip in the bottom-right corner.
grip = CreateFrame("Button", nil, win)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing(); SavePos() end)

-- Notes area.
content = CreateFrame("Frame", nil, win)
-- Same width as the title bar, so heading bars line up with it.
content:SetPoint("TOPLEFT", 1, -38)
content:SetPoint("BOTTOMRIGHT", -1, 18)

win:SetScript("OnShow", function() WBN_DB.shown = true end)
win:SetScript("OnHide", function() WBN_DB.shown = false end)

function WBNotes_Toggle() win:SetShown(not win:IsShown()) end

SLASH_WBNOTES1 = "/wbnotes"
SlashCmdList.WBNOTES = function(msg)
  if (msg or ""):lower():match("^%s*reset") then
    win:ClearAllPoints()
    win:SetPoint("CENTER")
    win:SetSize(300, 400)
    SavePos()
    win:Show()
  else
    WBNotes_Toggle()
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  WBN_DB = WBN_DB or {}
  -- First run: bring over notes from the side panel, if it's installed and enabled.
  if WBN_DB.notes == nil then
    WBN_DB.notes = (WBSP_DB and WBSP_DB.notes) or ""
  end
  local p = WBN_DB.pos
  win:ClearAllPoints()
  if p then win:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else win:SetPoint("CENTER") end
  win:SetSize(WBN_DB.w or 300, WBN_DB.h or 400)
  WBN_DB.art = nil -- leftover from the old texture search
  if WBN_DB.transparent == nil then WBN_DB.transparent = true end -- new installs start in Default mode
  BuildNotes(content)
  ApplyTransparent()
  ApplyFold()
  if WBN_DB.shown then win:Show() end
end)
