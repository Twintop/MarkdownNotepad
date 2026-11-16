-- The text editor: a multi-line EditBox in a scroll frame, with line numbers, syntax coloring,
-- undo, and the formatting actions.
--
-- The EditBox holds the display string Markup.lua describes, and the editor keeps the note's
-- plain markdown. Each time the EditBox's text changes, the change is found (what was taken out
-- and what was put in), mapped onto the plain text, and the display is built again from it.

local _, ns = ...
local M, A, W = ns.Markup, ns.Actions, ns.Widgets

local CE = {}
ns.CodeEditor = CE

local INSET_LEFT, INSET_RIGHT, INSET_TOP, INSET_BOTTOM = 6, 6, 4, 4
local GUTTER_PAD = 6
local UNDO_LIMIT = 200
CE.UNDO_LIMIT = UNDO_LIMIT
local TYPING_PAUSE = 1.5 -- seconds of typing that one undo takes back

local editorFont = CreateFont("MarkdownNotepadEditorFont")
editorFont:SetFont(W.MONO_FONT, 13, "")

local methods = {}

------------------------------------------------------------------------------------------------
-- Building it
------------------------------------------------------------------------------------------------

-- Creates an editor in parent. Callbacks, all optional: ed.onChange(text, loaded) after the text
-- changes (loaded when SetText put it there), ed.onCursor(line, column) when the cursor moves,
-- and ed.onShortcut(key) for Ctrl-<key> presses the editor doesn't handle itself.
function CE.Create(parent)
  local ed = setmetatable({
    plain = "", display = "", undo = {}, redo = {}, rowCache = {}, rowCacheCount = 0,
    highlight = true, lineNumbers = true,
  }, { __index = methods })

  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Backdrop(frame, W.colors.inset, W.colors.border)
  ed.frame = frame

  local gutterBg = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
  gutterBg:SetPoint("TOPLEFT", 1, -1)
  gutterBg:SetPoint("BOTTOMLEFT", 1, 1)
  gutterBg:SetColorTexture(1, 1, 1, 0.035)
  ed.gutterBg = gutterBg

  local scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", 1, -1)
  scroll:SetPoint("BOTTOMRIGHT", -11, 1)
  ed.scroll = scroll

  local eb = CreateFrame("EditBox", nil, scroll)
  eb:SetAllPoints()
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:EnableMouse(true)
  eb:SetMaxLetters(0)
  eb:SetMaxBytes(0)
  eb:SetCountInvisibleLetters(false)
  eb:SetFontObject(editorFont)
  eb:SetTextColor(0.88, 0.88, 0.88)
  eb:SetHighlightColor(0.25, 0.5, 0.9, 0.45)
  scroll:SetScrollChild(eb)
  ed.editBox = eb

  ed.bar = W.ScrollBar(scroll, 48)

  -- the line numbers scroll with the text, in the EditBox's left inset
  local gutter = eb:CreateFontString(nil, "OVERLAY")
  gutter:SetFontObject(editorFont)
  gutter:SetPoint("TOPLEFT", eb, "TOPLEFT", 0, -INSET_TOP)
  gutter:SetJustifyH("RIGHT")
  gutter:SetJustifyV("TOP")
  gutter:SetTextColor(0.38, 0.38, 0.42)
  ed.gutter = gutter

  -- an invisible copy of a line, wrapped at the text's width, to see how many rows it takes
  local measure = frame:CreateFontString(nil, "BACKGROUND")
  measure:SetFontObject(editorFont)
  measure:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  measure:SetJustifyH("LEFT")
  measure:SetWordWrap(true)
  measure:SetNonSpaceWrap(true)
  measure:SetAlpha(0)
  ed.measure = measure

  eb:SetScript("OnTextChanged", function() ed:OnTextChanged() end)
  eb:SetScript("OnCursorChanged", function(_, _, y, _, height)
    ed.cursorTop, ed.cursorBottom = -y, -y + height
    ed.cursorDirty = true
  end)
  eb:SetScript("OnEscapePressed", eb.ClearFocus)
  eb:SetScript("OnTabPressed", function() ed:Apply(A.Indent, IsShiftKeyDown()) end)
  eb:SetScript("OnKeyDown", function(_, key) ed:OnKeyDown(key) end)
  eb:SetScript("OnEditFocusGained", function()
    CE.focused = ed
    frame:SetBackdropBorderColor(unpack(W.colors.focus))
  end)
  eb:SetScript("OnEditFocusLost", function()
    frame:SetBackdropBorderColor(unpack(W.colors.border))
  end)
  eb:SetScript("OnReceiveDrag", function() ed:OnReceiveDrag() end)
  eb:SetScript("OnMouseDown", function() if GetCursorInfo() then ed:OnReceiveDrag() end end)

  -- a click below the text puts the cursor at its end
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseUp", function()
    eb:SetFocus()
    eb:SetCursorPosition(#ed.display)
  end)
  scroll:SetScript("OnReceiveDrag", function() ed:OnReceiveDrag() end)
  scroll:SetScript("OnSizeChanged", function(_, width)
    eb:SetWidth(width)
    ed.layoutDirty = true
  end)

  frame:SetScript("OnUpdate", function() ed:OnUpdate() end)
  frame:SetScript("OnShow", function() ed:Measure() end)

  ed:SetFontSize(13)
  return ed
end

------------------------------------------------------------------------------------------------
-- Layout and line numbers
------------------------------------------------------------------------------------------------

-- JetBrains Mono has no Chinese or Korean characters; those clients get their own font
local NO_MONO = { koKR = true, zhCN = true, zhTW = true }

function methods:SetFontSize(size)
  self.fontSize = size
  local locale = GetLocale and GetLocale()
  if NO_MONO[locale] or editorFont:SetFont(W.MONO_FONT, size, "") == false then
    editorFont:SetFont(STANDARD_TEXT_FONT, size, "")
  end
  -- No extra line spacing: a multi-line EditBox draws its text with it, but places its cursor
  -- and selection highlight without it, so they drift up a pixel per line above them. And the
  -- line numbers only line up when all three space their lines alike.
  editorFont:SetSpacing(0)
  for _, region in ipairs({ self.editBox, self.gutter, self.measure }) do
    region:SetFontObject(editorFont)
    region:SetSpacing(0)
  end
  self:Measure()
end

-- the font's character width and row height, which the gutter's width and the row counts use
function methods:Measure()
  local m = self.measure
  m:SetWidth(4000)
  m:SetText("0000000000")
  local width = m:GetStringWidth()
  if width and width > 0 then self.charWidth = width / 10 end
  m:SetText("X")
  local h1 = m:GetStringHeight()
  m:SetText("X\nX")
  local h2 = m:GetStringHeight()
  if h1 and h1 > 0 then
    self.rowHeight = h1
    self.rowStep = (h2 and h2 > h1) and (h2 - h1) or h1
  end
  self.textWidth = nil -- so Layout clears the row counts
  self:Layout()
end

function methods:Layout()
  self.layoutDirty = nil
  local eb = self.editBox
  local width = self.scroll:GetWidth() or 0
  if width > 0 then eb:SetWidth(width) end

  local gutterWidth = 0
  if self.lineNumbers then
    local digits = math.max(2, #tostring(self.lineCount or 1))
    gutterWidth = math.ceil(digits * (self.charWidth or 8)) + GUTTER_PAD * 2
    self.gutter:SetWidth(gutterWidth - GUTTER_PAD)
  end
  self.gutterWidth = gutterWidth
  self.gutter:SetShown(self.lineNumbers)
  self.gutterBg:SetShown(self.lineNumbers)
  self.gutterBg:SetWidth(math.max(gutterWidth, 1))
  eb:SetTextInsets(gutterWidth + INSET_LEFT, INSET_RIGHT, INSET_TOP, INSET_BOTTOM)

  local textWidth = width - gutterWidth - INSET_LEFT - INSET_RIGHT
  if textWidth ~= self.textWidth then
    self.textWidth = textWidth
    self.rowCache, self.rowCacheCount = {}, 0
  end
  self.measure:SetWidth(math.max(textWidth, 1))
  self.gutterText = nil
  self:UpdateGutter()
end

-- the rows a line takes once the EditBox wraps it
function methods:Rows(line)
  local rows = self.rowCache[line]
  if rows then return rows end
  local m = self.measure
  m:SetText(M.Escape(line))
  local height = m:GetStringHeight() or 0
  if height <= 0 then return 1 end -- not laid out yet; measured again when shown
  rows = math.max(1, math.floor((height - self.rowHeight) / self.rowStep + 0.5) + 1)
  if self.rowCacheCount > 3000 then self.rowCache, self.rowCacheCount = {}, 0 end
  self.rowCache[line] = rows
  self.rowCacheCount = self.rowCacheCount + 1
  return rows
end

-- Numbers each line, with an empty row in the gutter for each extra row the line wraps onto, so
-- the numbers stay beside their lines.
function methods:UpdateGutter()
  if not self.lineNumbers then return end
  local lines, n = M.Lines(self.plain)
  if n ~= self.lineCount then
    local before = math.max(2, #tostring(self.lineCount or 1))
    self.lineCount = n
    if math.max(2, #tostring(n)) ~= before then return self:Layout() end
  end
  local parts, k = {}, 0
  local measuring = self.rowStep and (self.textWidth or 0) > 0
  for i = 1, n do
    k = k + 1
    parts[k] = i
    local line = lines[i]
    if measuring and line ~= "" then
      for _ = 2, self:Rows(line) do
        k = k + 1
        parts[k] = ""
      end
    end
  end
  local text = table.concat(parts, "\n")
  if text ~= self.gutterText then
    self.gutterText = text
    self.gutter:SetText(text)
  end
end

function methods:SetLineNumbers(on)
  self.lineNumbers = on and true or false
  self:Layout()
end

function methods:SetHighlight(on)
  self.highlight = on and true or false
  local cursor = self:GetCursor()
  self:Render(cursor, cursor)
end

function methods:OnUpdate()
  if self.layoutDirty then self:Layout() end
  if self.cursorDirty then
    self.cursorDirty = nil
    if self.editBox:HasFocus() and self.cursorTop then
      W.ScrollIntoView(self.scroll, self.cursorTop, self.cursorBottom + INSET_BOTTOM)
    end
    if self.onCursor then
      local cursor = self:GetCursor()
      local before = self.plain:sub(1, cursor)
      local _, breaks = before:gsub("\n", "")
      local lineText = before:match("[^\n]*$")
      local _, column = lineText:gsub("[^\128-\191]", "")
      self.onCursor(breaks + 1, column + 1)
    end
  end
end

------------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------------

function methods:GetText()
  return self.plain
end

-- the cursor's plain offset
function methods:GetCursor()
  local pos = self.editBox:GetCursorPosition() or 0
  return M.ToPlain(self.display, math.min(pos, #self.display))
end

-- Shows text, as when a note is opened: the cursor at the start, and nothing to undo.
function methods:SetText(text)
  self.plain = text or ""
  self.undo, self.redo, self.lastKind = {}, {}, nil
  self:Render(0, 0)
  self.scroll:SetVerticalScroll(0)
  self:Changed(true)
end

function methods:Focus()
  self.editBox:SetFocus()
end

function methods:Changed(loaded)
  if self.onChange then self.onChange(self.plain, loaded) end
end

-- Builds the display for the plain text and puts it in the EditBox, if it isn't there already.
-- With s (and e), sets the cursor (and selection) by plain offsets.
function methods:Render(s, e)
  local eb = self.editBox
  local display = M.Render(self.plain, self.highlight)
  if display ~= eb:GetText() then
    self.internal = true
    eb:SetText(display)
    local actual = eb:GetText()
    if actual ~= display and self.highlight then
      -- the EditBox didn't keep the color codes as given; show the text uncolored instead
      self.highlight = false
      display = M.Render(self.plain, false)
      eb:SetText(display)
      actual = eb:GetText()
    end
    self.internal = nil
    self.display = actual
  else
    self.display = display
  end
  if s then
    e = e or s
    self.internal = true
    eb:SetCursorPosition(M.ToDisplay(self.display, e))
    if e ~= s then eb:HighlightText(M.ToDisplay(self.display, s), M.ToDisplay(self.display, e)) end
    self.internal = nil
  end
  self:UpdateGutter()
end

-- Sets new plain text, with the selection s to e, as one step that Undo takes back. `kind` is
-- "type" for typing, which Undo takes back a burst at a time; `at` is where the change started
-- and `len` how much it put in.
function methods:Commit(text, s, e, kind, at, len)
  if text == self.plain then
    self:Render(s, e)
    return
  end
  local now = GetTime()
  local merge = kind == "type" and self.lastKind == "type" and self.undo[1]
    and now - (self.lastTime or 0) < TYPING_PAUSE and at == self.lastEnd
  if not merge then
    table.insert(self.undo, { text = self.plain, cursor = at or s })
    if #self.undo > UNDO_LIMIT then table.remove(self.undo, 1) end
  end
  self.redo = {}
  self.lastKind, self.lastTime, self.lastEnd = kind, now, at and at + (len or 0)
  self.plain = text
  self:Render(s, e)
  self:Changed()
end

-- the EditBox's text changed: map the change onto the plain text
function methods:OnTextChanged()
  if self.internal then return end
  local eb = self.editBox
  if eb.IsInIMECompositionMode and eb:IsInIMECompositionMode() then return end
  local new, old = eb:GetText(), self.display
  if new == old then return end

  local p, oldEnd, newEnd = M.DiffAt(old, new, eb:GetCursorPosition())
  -- A typed | can match the first byte of a color code that followed it: the change starts
  -- where that code does, so the | is part of what was put in. (After Backspace or Delete,
  -- a | left over from a || that lost one byte is what's left, not something new.)
  local deleting = self.lastKey == "BACKSPACE" or self.lastKey == "DELETE"
  if not deleting then p = M.TokenStart(old, p) end
  local ps = M.ToPlain(old, p, false)
  local pe = oldEnd > p and M.ToPlain(old, oldEnd, true) or ps
  local inserted = M.Decode(new:sub(p + 1, newEnd))
  local plain = self.plain

  if ps == pe and inserted == "" then
    -- The edit only took part of an escape sequence, as Backspace next to a color code can.
    -- Take out the character the key was meant for.
    if oldEnd > p then
      if self.lastKey == "DELETE" then pe = M.NextChar(plain, ps) else ps = M.PrevChar(plain, ps) end
    end
    if ps == pe then
      self:Render(ps, ps)
      return
    end
  end

  local text = plain:sub(1, ps) .. inserted .. plain:sub(pe + 1)
  local cursor = ps + #inserted
  local kind = "edit"
  if pe == ps and #inserted <= 4 and not inserted:find("[%s]") then kind = "type" end
  if inserted == "\n" and pe == ps then
    local continued, at = A.ContinueList(text, cursor)
    if continued then text, cursor = continued, at end
  end
  self:Commit(text, cursor, cursor, kind, ps, #inserted)
end

-- Where the selection is, by plain offsets. The EditBox can't say, so put a marker character
-- in place of the selection and see where it went, then put the text back.
function methods:GetSelection()
  local eb = self.editBox
  if eb:GetText() ~= self.display then self:OnTextChanged() end
  local before = eb:GetText()
  self.internal = true
  eb:Insert(M.SENTINEL)
  local after = eb:GetText()
  local cursor = eb:GetCursorPosition() or 0
  if after ~= before then eb:SetText(before) end
  self.internal = nil
  local at = after:find(M.SENTINEL, 1, true)
  if not at then
    local c = M.ToPlain(before, math.min(cursor, #before))
    return c, c
  end
  local s = at - 1
  local e = s + (#before - (#after - #M.SENTINEL))
  return M.ToPlain(before, s, false), M.ToPlain(before, e, true)
end

-- runs an Actions function on the text and selection: fn(text, s, e, ...)
function methods:Apply(fn, ...)
  local eb = self.editBox
  if not eb:HasFocus() then eb:SetFocus() end
  local s, e = self:GetSelection()
  local text, newS, newE = fn(self.plain, s, e, ...)
  self:Commit(text, newS, newE, "action", s)
end

function methods:Undo()
  local state = table.remove(self.undo)
  if not state then return end
  table.insert(self.redo, { text = self.plain, cursor = state.cursor })
  self.plain, self.lastKind = state.text, nil
  self:Render(state.cursor, state.cursor)
  self:Changed()
end

function methods:Redo()
  local state = table.remove(self.redo)
  if not state then return end
  table.insert(self.undo, { text = self.plain, cursor = state.cursor })
  self.plain, self.lastKind = state.text, nil
  self:Render(state.cursor, state.cursor)
  self:Changed()
end

function methods:OnKeyDown(key)
  self.lastKey = key
  if not IsControlKeyDown() then return end
  if key == "Z" then
    if IsShiftKeyDown() then self:Redo() else self:Undo() end
  elseif key == "Y" then
    self:Redo()
  elseif self.onShortcut then
    self.onShortcut(key)
  end
end

------------------------------------------------------------------------------------------------
-- Game links
------------------------------------------------------------------------------------------------

-- A chat link, as a markdown link: |cff..|Hspell:133:0|h[Fireball]|h|r becomes [Fireball](spell:133),
-- which LibSimpleHTMLMarkdown shows with the game's tooltip.
function CE.LinkToMarkdown(link)
  local kind, data, label = link:match("|H(%a+):([^|]*)|h(.-)|h")
  if not kind then return M.Decode(link) end
  label = label:gsub("^%[(.*)%]$", "%1")
  local id = data:match("^%-?%d+")
  if not id then return label end
  return "[" .. label .. "](" .. kind .. ":" .. id .. ")"
end

function methods:InsertGameLink(link)
  self:Apply(A.Insert, CE.LinkToMarkdown(link))
end

-- a spell or item dropped on the editor becomes a link to it
function methods:OnReceiveDrag()
  local kind, id, info, extra = GetCursorInfo()
  local text
  if kind == "item" and info then
    text = CE.LinkToMarkdown(info)
  elseif kind == "spell" then
    local spellID = extra or id
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
      or (GetSpellInfo and GetSpellInfo(spellID))
    if name then text = "[" .. name .. "](spell:" .. spellID .. ")" end
  end
  if not text then return end
  ClearCursor()
  self:Apply(A.Insert, text)
end

-- Shift-clicking a spell or item while an editor has focus links it, as it would in chat.
local function OnInsertLink(link)
  local ed = CE.focused
  if link and ed and ed.editBox:IsVisible() and ed.editBox:HasFocus() then
    ed:InsertGameLink(link)
  end
end
if ChatFrameUtil and ChatFrameUtil.InsertLink then
  hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
elseif ChatEdit_InsertLink then
  hooksecurefunc("ChatEdit_InsertLink", OnInsertLink)
end
