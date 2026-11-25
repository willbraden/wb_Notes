-- wb_Notes markdown: a tiny markdown renderer (copy of the one in wb_SidePanel, so wb_Notes
-- works on its own).
--
-- Supported: # / ## / ### headings, - or * bullets (indent with 2 spaces), 1. numbered,
-- - [ ] / - [x] tasks, **bold**, *italic*, `code`, > quotes, --- divider.
-- Drawn as a stack of rows with real textures and buttons (this client won't render
-- texture codes inside formatted text).
--
-- API:
--   local MD = WBNotes_Markdown
--   local blocks = MD.Parse(text, trusted) -- trusted: allow WoW color codes in text
--   local view = MD.NewView(parent)        -- a Frame
--   view:Render(textOrBlocks, width)       -- lays out rows, sets its own height
--   view.OnTick = function(lineNumber) end -- a task box was clicked
--   view.lineTop[lineNumber]               -- y offset of a line after Render

local MD = {}

-- Body font: the same font and size as the objective tracker's lines, so notes sit
-- next to the stock tracker without looking bigger or smaller.
local bodyFont = CreateFont("WBNotesBodyFont")
do
  local ref = ObjectiveTrackerLineFont or ObjectiveFont or GameFontHighlight
  bodyFont:CopyFontObject(ref)
  local face, size, flags = ref:GetFont()
  bodyFont:SetFont(face or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, flags or "")
end
MD.BodyFont = bodyFont

-- Stock UI art from the game's objective tracker.
MD.art = {
  primary   = { atlas = "UI-QuestTracker-Primary-Objective-Header" },   -- "All Objectives" bar: window title bar
  secondary = { atlas = "UI-QuestTracker-Secondary-Objective-Header" }, -- "Quests" bar: markdown headings
  collapse  = { atlas = "UI-QuestTrackerButton-Secondary-Collapse" },   -- fold button, section open
  expand    = { atlas = "UI-QuestTrackerButton-Secondary-Expand" },     -- fold button, section folded
}

function MD.ApplyArt(tex, spec)
  if not spec then return false end
  tex:SetVertexColor(1, 1, 1, 1)
  if spec.atlas then
    tex:SetAtlas(spec.atlas)
  elseif spec.file then
    tex:SetTexture(spec.file)
    if spec.coords and #spec.coords == 8 then tex:SetTexCoord(unpack(spec.coords)) else tex:SetTexCoord(0, 1, 0, 1) end
  else
    return false
  end
  return true
end

local function Esc(s) return (s:gsub("|", "||")) end

local function Inline(s)
  s = s:gsub("`([^`]+)`", "|cff8fd3ff%1|r")
  s = s:gsub("%*%*(.-)%*%*", "|cffffffff%1|r")
  s = s:gsub("__(.-)__", "|cffffffff%1|r")
  s = s:gsub("%*([^%*]+)%*", "|cffa8a8a8%1|r")
  s = s:gsub("%f[%w_]_([^_]+)_%f[^%w_]", "|cffa8a8a8%1|r")
  return s
end

function MD.Parse(text, trusted)
  local E = trusted and function(s) return s end or Esc
  local blocks, i = {}, 0
  for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
    i = i + 1
    local b
    local hashes, head = line:match("^(#+)%s+(.*)$")
    if hashes then
      b = { kind = "h", level = math.min(#hashes, 3), text = Inline(E(head)), key = #hashes .. ":" .. head }
    elseif line:match("^%s*([-*_])%s*%1%s*%1[-*_%s]*$") then
      b = { kind = "hr" }
    else
      local ind, mark, rest = line:match("^(%s*)[-*+]%s+%[([ xX])%]%s*(.*)$")
      if ind then
        local done = mark ~= " "
        b = { kind = "task", level = math.floor(#ind / 2), done = done,
              text = done and ("|cff808080" .. E(rest) .. "|r") or Inline(E(rest)) }
      else
        local bInd, bRest = line:match("^(%s*)[-*+]%s+(.*)$")
        local nInd, num, nRest = line:match("^(%s*)(%d+)%.%s+(.*)$")
        local quote = line:match("^>%s?(.*)$")
        if bInd then
          b = { kind = "bullet", level = math.floor(#bInd / 2), mark = "•", text = Inline(E(bRest)) }
        elseif nInd then
          b = { kind = "bullet", level = math.floor(#nInd / 2), mark = num .. ".", text = Inline(E(nRest)) }
        elseif quote then
          b = { kind = "quote", text = "|cffa8a8a8" .. Inline(E(quote)) .. "|r" }
        elseif line:match("^%s*$") then
          b = { kind = "blank" }
        else
          b = { kind = "p", text = Inline(E(line)) }
        end
      end
    end
    b.line = i
    blocks[#blocks + 1] = b
  end
  while #blocks > 0 and blocks[#blocks].kind == "blank" do blocks[#blocks] = nil end
  return blocks
end

function MD.NewView(parent)
  -- # matches the tracker's "Quests" header; ## and ### step down from there.
  local H1 = ObjectiveTrackerHeaderFont or GameFontNormalMed2 or GameFontNormalLarge
  local H2 = GameFontNormalMed1 or GameFontNormal
  local HEAD_FONTS = { H1, H1, H2 } -- # and ## match "Quests"; ### is a step smaller
  local view = CreateFrame("Frame", nil, parent)
  view:SetSize(250, 20)
  view.lineTop = {}
  view.collapsed = {}      -- heading key -> true when folded (Notes.lua points this at saved data)
  view.plainHeads = false  -- true: no header bar behind headings (transparent mode)
  view.padX = 0            -- side inset for everything except heading bars, which run full width
  view.shadow = false -- heavier text shadow, for reading over the game
  local rows = {}

  -- Shadow is re-applied after every SetFontObject, which resets it.
  -- light = stock 1px shadow (headings sit on a header bar, like the tracker).
  local function Shade(fs, light)
    fs:SetShadowColor(0, 0, 0, 1)
    if view.shadow and not light then fs:SetShadowOffset(2, -2) else fs:SetShadowOffset(1, -1) end
  end

  local function GetRow(n)
    local r = rows[n]
    if r then return r end
    r = CreateFrame("Frame", nil, view)
    r.text = r:CreateFontString(nil, "OVERLAY", "WBNotesBodyFont")
    r.text:SetJustifyH("LEFT")
    r.text:SetJustifyV("TOP")
    if r.text.SetWordWrap then r.text:SetWordWrap(true) end
    r.mark = r:CreateFontString(nil, "OVERLAY", "WBNotesBodyFont")
    r.mark:SetJustifyH("RIGHT")
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetColorTexture(0.45, 0.45, 0.5, 1)
    r.box = CreateFrame("Button", nil, r)
    r.box:SetSize(14, 14) -- sized to the tracker-size body text
    r.box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    r.box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    r.check = r.box:CreateTexture(nil, "OVERLAY")
    r.check:SetAllPoints()
    r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.box:SetScript("OnClick", function(self) if view.OnTick then view.OnTick(self.line) end end)
    -- Heading bar (stock quest tracker header) with a fold toggle.
    r.hbg = r:CreateTexture(nil, "BACKGROUND")
    r.hbg:SetAllPoints()
    r.hline = r:CreateTexture(nil, "ARTWORK")
    r.hline:SetColorTexture(1, 0.82, 0, 0.6)
    r.hline:SetHeight(1)
    r.hline:SetPoint("BOTTOMLEFT"); r.hline:SetPoint("BOTTOMRIGHT")
    r.head = CreateFrame("Button", nil, r)
    r.head:SetAllPoints()
    r.head:SetScript("OnClick", function(self)
      view.collapsed[self.key] = not view.collapsed[self.key] or nil
      view:Render(view.lastSrc, view.lastWidth)
    end)
    r.fold = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.fold:SetPoint("RIGHT", r, "RIGHT", -18, 0) -- inside the bar art
    r.foldTex = r:CreateTexture(nil, "OVERLAY")
    r.foldTex:SetSize(16, 16)
    r.foldTex:SetPoint("RIGHT", r, "RIGHT", -16, 0) -- inside the bar art
    rows[n] = r
    return r
  end

  function view:Render(src, width)
    width = width or self:GetWidth()
    self:SetWidth(width)
    self.lastSrc, self.lastWidth = src, width
    local blocks = type(src) == "table" and src or MD.Parse(src)
    -- Accordion: drop everything under a folded heading, up to the next heading of the
    -- same or higher rank.
    local shown, foldAt = {}, nil
    for _, b in ipairs(blocks) do
      if b.kind == "h" then
        if not (foldAt and b.level > foldAt) then
          foldAt = nil
          shown[#shown + 1] = b
          if b.key and self.collapsed[b.key] then foldAt = b.level end
        end
      elseif not foldAt then
        shown[#shown + 1] = b
      end
    end
    blocks = shown
    wipe(self.lineTop)
    local y = 2
    for n, b in ipairs(blocks) do
      local r = GetRow(n)
      r:Show()
      r.text:Hide(); r.mark:Hide(); r.bar:Hide(); r.box:Hide()
      r.hbg:Hide(); r.hline:Hide(); r.head:Hide(); r.fold:Hide(); r.foldTex:Hide()
      local h
      if b.kind == "h" and n > 1 then y = y + 6 end
      local pad = b.kind == "h" and 0 or self.padX
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", self, "TOPLEFT", pad, -y)
      r:SetPoint("RIGHT", self, "RIGHT", -pad, 0)
      if b.line then self.lineTop[b.line] = y end
      if b.kind == "blank" then
        h = 8
      elseif b.kind == "hr" then
        h = 13
        r.bar:ClearAllPoints()
        r.bar:SetPoint("LEFT", r, "LEFT", 2, 0)
        r.bar:SetPoint("RIGHT", r, "RIGHT", -2, 0)
        r.bar:SetHeight(1)
        r.bar:Show()
      else
        local left = 2
        local font = bodyFont
        if b.kind == "h" then
          font = HEAD_FONTS[b.level]
        elseif b.kind == "bullet" then
          left = 2 + b.level * 14 + 18
          r.mark:SetText(b.mark)
          r.mark:SetTextColor(1, 0.82, 0)
          Shade(r.mark)
          r.mark:ClearAllPoints()
          r.mark:SetPoint("TOPRIGHT", r, "TOPLEFT", left - 4, 0)
          r.mark:Show()
        elseif b.kind == "task" then
          left = 2 + b.level * 14 + 20
          r.box:ClearAllPoints()
          r.box:SetPoint("TOPLEFT", r, "TOPLEFT", left - 19, 1)
          r.check:SetShown(b.done)
          r.box.line = b.line
          r.box:EnableMouse(true) -- stays clickable even when the window is click-through
          r.box:Show()
        elseif b.kind == "quote" then
          left = 12
        end
        r.text:SetFontObject(font)
        if b.kind == "h" then r.text:SetTextColor(1, 0.82, 0) else r.text:SetTextColor(1, 1, 1) end
        Shade(r.text, b.kind == "h")
        local isHead = b.kind == "h"
        if isHead then left = 30 end
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT", r, "TOPLEFT", left, 0)
        r.text:SetWidth(math.max(20, width - 2 * pad - left - (isHead and 40 or 2)))
        r.text:SetText(b.text)
        r.text:Show()
        h = math.max(r.text:GetStringHeight() or 14, b.kind == "task" and 14 or 0) + 3
        if isHead then
          -- Stock header bar height, text centered on it.
          local th = r.text:GetStringHeight() or 14
          h = math.max(th + 8, 25) -- stock section header is 25 tall
          r.text:SetPoint("TOPLEFT", r, "TOPLEFT", left, -math.floor((h - th) / 2))
          local hasArt = MD.ApplyArt(r.hbg, MD.art.secondary)
          if not hasArt then r.hbg:SetColorTexture(0, 0, 0, 0.35) end
          r.hbg:SetShown(not self.plainHeads)
          r.hline:SetShown(not hasArt or self.plainHeads)
          local folded = self.collapsed[b.key]
          local foldArt = MD.art.collapse and MD.art.expand and (folded and MD.art.expand or MD.art.collapse)
          if foldArt and MD.ApplyArt(r.foldTex, foldArt) then
            r.foldTex:Show()
          else
            r.fold:SetText(folded and "+" or "\226\128\147") -- + or en dash
            Shade(r.fold, true)
            r.fold:Show()
          end
          if b.key then
            r.head.key = b.key
            r.head:ClearAllPoints()
            if self.passThrough then
              -- Click-through window: only the fold button catches clicks.
              r.head:SetPoint("TOPRIGHT")
              r.head:SetPoint("BOTTOMRIGHT")
              r.head:SetWidth(40)
            else
              r.head:SetAllPoints() -- whole bar folds the section
            end
            r.head:EnableMouse(true)
            r.head:Show()
          end
        end
        if b.kind == "quote" then
          r.bar:ClearAllPoints()
          r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 3, 0)
          r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 3, 3)
          r.bar:SetWidth(2)
          r.bar:Show()
        end
      end
      r:SetHeight(h)
      y = y + h
      if b.kind == "h" then y = y + 5 end -- breathing room under a header bar, like the tracker
    end
    for n = #blocks + 1, #rows do rows[n]:Hide() end
    self:SetHeight(y + 6)
  end

  return view
end

WBNotes_Markdown = MD
