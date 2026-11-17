-- Just enough of the WoW API to load Markdown Notepad outside the game and drive its windows.
--
-- run_tests.py sets VALID_METHODS (each widget type's methods, from the Ketho WoW API
-- annotations) before running this. With it, a widget only has the methods the real API has:
-- calling any other one fails, as it would in game. Without it, unknown methods do nothing.
--
-- The mock EditBox can be typed into, as a player would (MOCK.Type, MOCK.Backspace, ...). How
-- the real one stores a typed | (doubled or not) and what Backspace takes next to an escape
-- sequence aren't documented, so MOCK.pipeMode and MOCK.backspaceMode pick each behavior and
-- the tests try them all.

MOCK = {
  now = 1000,
  printed = {},
  popups = {},
  widgets = {},
  events = {},
  keys = {},
  pipeMode = "escape",      -- "escape": a typed | is stored as ||; "raw": as |
  backspaceMode = "token",  -- "token": Backspace takes a whole character or ||; "byte": one byte
}
local VALID = VALID_METHODS

local function noop() end

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 400, 300
local CHAR_WIDTH, LINE_HEIGHT = 7, 14

local impl = {}     -- implemented methods, by widget type (with inheritance below)
local parents = {
  Frame = "Region", Button = "Frame", EditBox = "Frame", ScrollFrame = "Frame", Slider = "Frame",
  SimpleHTML = "Frame", GameTooltip = "Frame", Texture = "Region", FontString = "Region", Region = nil,
  Font = nil,
}
for kind in pairs(parents) do impl[kind] = {} end
impl.Region = {}
impl.Font = {}

local function lookup(kind, key)
  while kind do
    local f = impl[kind] and impl[kind][key]
    if f then return f end
    kind = parents[kind]
  end
end

local BACKDROP_METHODS = {
  SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true, GetBackdrop = true,
  ApplyBackdrop = true, ClearBackdrop = true, OnBackdropLoaded = true, OnBackdropSizeChanged = true,
}

local meta = {}
local function metaFor(kind)
  if meta[kind] then return meta[kind] end
  meta[kind] = {
    __index = function(obj, key)
      if type(key) ~= "string" or not key:match("^%u") then return nil end -- a field, not a method
      local valid = true
      if VALID then
        local methods = VALID[kind]
        valid = (methods and methods[key]) or (rawget(obj, "_backdrop") and BACKDROP_METHODS[key]) or false
      end
      if not valid then return nil end
      return lookup(kind, key) or noop
    end,
  }
  return meta[kind]
end

local function new(kind, parent, name, template)
  local o = setmetatable({
    _kind = kind, _parent = parent, _shown = true, _scripts = {}, _points = {}, _alpha = 1,
    _text = "", _enabled = true, _level = 1,
  }, metaFor(kind))
  if template and tostring(template):find("BackdropTemplate") then o._backdrop = true end
  if name then _G[name] = o end
  table.insert(MOCK.widgets, o)
  return o
end
MOCK.new = new

local function fire(obj, script, ...)
  local handler = obj._scripts[script]
  if handler then return handler(obj, ...) end
end
MOCK.FireScript = fire

------------------------------------------------------------------------------------------------
-- Regions and frames
------------------------------------------------------------------------------------------------

local R, F = impl.Region, impl.Frame

function R:SetPoint(point, rel, relPoint, x, y) table.insert(self._points, { point, rel, relPoint, x, y }) end
function R:ClearAllPoints() self._points = {} end
function R:SetAllPoints(rel) self._points = { { "TOPLEFT", rel }, { "BOTTOMRIGHT", rel } } end
function R:GetPoint(i)
  local p = self._points[i or 1]
  if not p then return nil end
  local rel = p[2]
  if type(rel) == "number" or rel == nil then return p[1], UIParent, p[1], p[2] or 0, p[3] or 0 end
  return p[1], rel, p[3] or p[1], p[4] or 0, p[5] or 0
end
function R:GetNumPoints() return #self._points end
local function setSize(self, w, h)
  local changed = (w and w ~= self._w) or (h and h ~= self._h)
  if w then self._w = w end
  if h then self._h = h end
  if changed and self._scripts.OnSizeChanged then fire(self, "OnSizeChanged", self:GetWidth(), self:GetHeight()) end
end
function R:SetWidth(w) setSize(self, w, nil) end
function R:SetHeight(h) setSize(self, nil, h) end
function R:SetSize(w, h) setSize(self, w, h) end
-- MOCK.unresolved: the game hasn't laid the frames out yet, so one sized only by its anchors
-- reads 0 wide and high. Clearing it is the layout that follows, without an OnSizeChanged.
function R:GetWidth() return self._w or (MOCK.unresolved and 0 or DEFAULT_WIDTH) end
function R:GetHeight() return self._h or (MOCK.unresolved and 0 or DEFAULT_HEIGHT) end
function R:GetSize() return self:GetWidth(), self:GetHeight() end
function R:GetLeft() return 0 end
function R:GetTop() return DEFAULT_HEIGHT end
function R:GetRight() return self:GetLeft() + self:GetWidth() end
function R:GetBottom() return self:GetTop() - self:GetHeight() end
function R:GetEffectiveScale() return 1 end
function R:GetScale() return 1 end
function R:Show()
  if not self._shown then self._shown = true; fire(self, "OnShow") end
end
function R:Hide()
  if self._shown then self._shown = false; fire(self, "OnHide") end
end
function R:SetShown(shown) if shown then self:Show() else self:Hide() end end
function R:IsShown() return self._shown end
function R:IsVisible()
  local o = self
  while o do
    if not o._shown then return false end
    o = o._parent
  end
  return true
end
function R:GetParent() return self._parent end
function R:SetParent(p) self._parent = p end
function R:SetAlpha(a) self._alpha = a end
function R:GetAlpha() return self._alpha end
-- MOCK.mouseOver is the frame under the mouse. A frame that doesn't take the mouse isn't counted,
-- the worst the real IsMouseOver might do; MOCK.cursorPos still puts the cursor over it.
function R:IsMouseOver() return MOCK.mouseOver == self and self._mouse ~= false end
function R:GetObjectType() return self._kind end

function F:SetScript(script, handler) self._scripts[script] = handler end
function F:GetScript(script) return self._scripts[script] end
function F:HasScript() return true end
function F:HookScript(script, handler)
  local old = self._scripts[script]
  if old then
    self._scripts[script] = function(...) old(...); handler(...) end
  else
    self._scripts[script] = handler
  end
end
function F:CreateTexture() return new("Texture", self) end
function F:CreateFontString(_, _, template)
  local fs = new("FontString", self)
  if template then fs._font = template end
  return fs
end
function F:RegisterEvent(event)
  MOCK.events[event] = MOCK.events[event] or {}
  MOCK.events[event][self] = true
end
function F:UnregisterEvent(event)
  if MOCK.events[event] then MOCK.events[event][self] = nil end
end
function F:GetFrameLevel() return self._level end
function F:SetFrameLevel(level) self._level = level end
function F:EnableMouse(on) self._mouse = on and true or false end
function F:IsMouseEnabled() return self._mouse ~= false end
function F:EnableMouseWheel(on) self._wheel = on and true or false end
function F:IsMouseWheelEnabled() return self._wheel or false end
function F:GetName() return nil end

-- textures and font strings
local T, FS = impl.Texture, impl.FontString
function T:SetTexture(path) self._texture = path end
function T:GetTexture() return self._texture end
function T:SetColorTexture(...) self._color = { ... } end
function T:SetDesaturated(on) self._desat = on end

local function visibleLength(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "x"):gsub("||", "|")
  local _, n = s:gsub("[^\128-\191]", "")
  return n
end

function FS:SetText(t) self._text = t and tostring(t) or "" end
function FS:GetText() return self._text end
function FS:SetFormattedText(fmt, ...) self._text = fmt:format(...) end
function FS:GetStringWidth()
  local widest = 0
  for line in (self._text .. "\n"):gmatch("(.-)\n") do widest = math.max(widest, visibleLength(line) * CHAR_WIDTH) end
  return widest
end
function FS:GetStringHeight()
  if self._text == "" then return 0 end
  local width, rows = self._w or 0, 0
  for line in (self._text .. "\n"):gmatch("(.-)\n") do
    local len = visibleLength(line) * CHAR_WIDTH
    rows = rows + ((width > 0 and len > 0) and math.max(1, math.ceil(len / width)) or 1)
  end
  return rows * LINE_HEIGHT
end
function FS:SetFontObject(font) self._font = font end
function FS:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end

-- buttons
local B = impl.Button
function B:Enable() if not self._enabled then self._enabled = true; fire(self, "OnEnable") end end
function B:Disable() if self._enabled then self._enabled = false; fire(self, "OnDisable") end end
function B:SetEnabled(on) if on then self:Enable() else self:Disable() end end
function B:IsEnabled() return self._enabled end
function B:SetFontString(fs) self._fs = fs end
function B:GetFontString() return self._fs end
function B:SetText(t) if self._fs then self._fs:SetText(t) end end
function B:Click(button)
  if self._enabled then fire(self, "OnClick", button or "LeftButton") end
end

-- sliders
local S = impl.Slider
function S:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function S:GetMinMaxValues() return self._min or 0, self._max or 0 end
function S:SetValue(v)
  v = math.max(self._min or v, math.min(self._max or v, v))
  local changed = v ~= self._value
  self._value = v
  if changed then fire(self, "OnValueChanged", v, false) end
end
function S:GetValue() return self._value or 0 end
function S:SetThumbTexture(t) self._thumb = self._thumb or new("Texture", self) end
function S:GetThumbTexture() return self._thumb end

-- scroll frames
local SF = impl.ScrollFrame
function SF:SetScrollChild(child) self._child = child; child._parent = self end
function SF:GetScrollChild() return self._child end
function SF:SetVerticalScroll(v) self._scroll = v; fire(self, "OnVerticalScroll", v) end
function SF:GetVerticalScroll() return self._scroll or 0 end
function SF:GetVerticalScrollRange()
  local child = self._child
  if not child then return 0 end
  return math.max(0, child:GetHeight() - self:GetHeight())
end

-- SimpleHTML
local H = impl.SimpleHTML
function H:SetText(t) self._text = t end
function H:GetText() return self._text end
function H:GetContentHeight() return 120 end

-- fonts
local Fo = impl.Font
function Fo:SetFont(file, size, flags) self._file, self._size, self._flags = file, size, flags; return true end
function Fo:GetFont() return self._file or "Fonts\\FRIZQT__.TTF", self._size or 12, self._flags or "" end

-- tooltips
local GT = impl.GameTooltip
function GT:SetText(t) self._text = t end
function GT:AddLine(t) self._lines = (self._lines or 0) + 1 end
function GT:SetHyperlink(link) self._link = link end

------------------------------------------------------------------------------------------------
-- The EditBox
------------------------------------------------------------------------------------------------

local EB = impl.EditBox
local function changed(self, userInput) fire(self, "OnTextChanged", userInput) end
local function cursorMoved(self)
  local before = self._text:sub(1, self._cursor)
  local _, row = before:gsub("\n", "")
  fire(self, "OnCursorChanged", 0, -row * LINE_HEIGHT, 2, LINE_HEIGHT)
end

function EB:SetText(t)
  self._text = t or ""
  self._cursor = #self._text
  self._hs, self._he = nil, nil
  changed(self, false)
  cursorMoved(self)
end
function EB:GetText() return self._text end
function EB:GetNumLetters() return #self._text end
function EB:GetCursorPosition() return self._cursor or 0 end
function EB:SetCursorPosition(p)
  self._cursor = math.max(0, math.min(p, #self._text))
  self._hs, self._he = nil, nil
  cursorMoved(self)
end
function EB:HighlightText(s, e)
  s, e = s or 0, e or #self._text
  if e < 0 then e = #self._text end
  if s == e then self._hs, self._he = nil, nil else self._hs, self._he = math.min(s, e), math.max(s, e) end
end
function EB:ClearHighlightText() self._hs, self._he = nil, nil end
function EB:Insert(s)
  local a, b = self._cursor, self._cursor
  if self._hs then a, b = self._hs, self._he end
  self._text = self._text:sub(1, a) .. s .. self._text:sub(b + 1)
  self._cursor = a + #s
  self._hs, self._he = nil, nil
  changed(self, true)
  cursorMoved(self)
end
function EB:SetFocus()
  if not self._focus then
    self._focus = true
    MOCK.focus = self
    fire(self, "OnEditFocusGained")
  end
end
function EB:ClearFocus()
  if self._focus then
    self._focus = false
    if MOCK.focus == self then MOCK.focus = nil end
    fire(self, "OnEditFocusLost")
  end
end
function EB:HasFocus() return self._focus or false end
function EB:IsInIMECompositionMode() return false end
function EB:GetMaxBytes() return 0 end
function EB:GetMaxLetters() return 0 end

-- what the player does at the keyboard, as the EditBox would take it

-- the text's characters: { start offset, end offset, visible }, where || is one visible
-- character, a color code is an invisible one, and a UTF-8 character is one
local function characters(text)
  local out, i, len = {}, 1, #text
  while i <= len do
    local b = text:byte(i)
    local n, visible = 1, true
    if b == 124 then
      local c = text:byte(i + 1)
      if c == 124 then n = 2
      elseif c == 114 then n, visible = 2, false
      elseif c == 99 and text:find("^%x%x%x%x%x%x%x%x", i + 2) then n, visible = 10, false end
    elseif b >= 192 then
      while i + n <= len do
        local cb = text:byte(i + n)
        if cb < 128 or cb >= 192 then break end
        n = n + 1
      end
    end
    out[#out + 1] = { i - 1, i - 1 + n, visible }
    i = i + n
  end
  return out
end

-- the visible character before offset pos (color codes between it and pos stay)
local function prevToken(text, pos)
  local found
  for _, ch in ipairs(characters(text)) do
    if ch[2] > pos then break end
    if ch[3] then found = ch end
  end
  if found then return found[1], found[2] end
end

-- the visible character after offset pos
local function nextToken(text, pos)
  for _, ch in ipairs(characters(text)) do
    if ch[1] >= pos and ch[3] then return ch[1], ch[2] end
  end
end
MOCK.characters = characters

local function replaceRange(self, a, b, s, userInput)
  self._text = self._text:sub(1, a) .. s .. self._text:sub(b + 1)
  self._cursor = a + #s
  self._hs, self._he = nil, nil
  changed(self, userInput ~= false)
  cursorMoved(self)
end

function MOCK.Type(eb, s)
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    fire(eb, "OnKeyDown", ch == "\n" and "ENTER" or ch:upper())
    local typed = ch
    if ch == "|" and MOCK.pipeMode == "escape" then typed = "||" end
    local a, b = eb._cursor, eb._cursor
    if eb._hs then a, b = eb._hs, eb._he end
    replaceRange(eb, a, b, typed)
  end
end

function MOCK.Paste(eb, s)
  fire(eb, "OnKeyDown", "V")
  if MOCK.pipeMode == "escape" then s = s:gsub("|", "||") end
  local a, b = eb._cursor, eb._cursor
  if eb._hs then a, b = eb._hs, eb._he end
  replaceRange(eb, a, b, s)
end

function MOCK.Backspace(eb)
  fire(eb, "OnKeyDown", "BACKSPACE")
  if eb._hs then return replaceRange(eb, eb._hs, eb._he, "") end
  local pos = eb._cursor
  if pos == 0 then return end
  -- "byte" takes one byte of an escape sequence; a UTF-8 character still goes whole
  if MOCK.backspaceMode == "byte" and eb._text:byte(pos) < 128 then return replaceRange(eb, pos - 1, pos, "") end
  local a, b = prevToken(eb._text, pos)
  if a then replaceRange(eb, a, b, "") end
end

function MOCK.Delete(eb)
  fire(eb, "OnKeyDown", "DELETE")
  if eb._hs then return replaceRange(eb, eb._hs, eb._he, "") end
  local text, pos = eb._text, eb._cursor
  if pos >= #text then return end
  if MOCK.backspaceMode == "byte" and text:byte(pos + 1) < 128 then return replaceRange(eb, pos, pos + 1, "") end
  local a, b = nextToken(text, pos)
  if a then replaceRange(eb, a, b, "") end
end

------------------------------------------------------------------------------------------------
-- Globals
------------------------------------------------------------------------------------------------

function CreateFrame(kind, name, parent, template)
  local o = new(kind, parent, name, template)
  return o
end

function CreateFont(name)
  local f = new("Font", nil, name)
  return f
end

UIParent = new("Frame", nil, "UIParent")
WorldFrame = new("Frame", nil, "WorldFrame")
GameTooltip = new("GameTooltip", UIParent, "GameTooltip")
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
OKAY, CANCEL, SAVE, DELETE = "Okay", "Cancel", "Save", "Delete"
CLOSE, EDIT, SEARCH, SETTINGS = "Close", "Edit", "Search", "Settings"
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }

for _, name in ipairs({ "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontHighlight",
  "GameFontHighlightSmall", "GameFontHighlightLarge", "GameFontDisable", "GameFontDisableSmall", "ChatFontNormal" }) do
  CreateFont(name)
end

tinsert, tremove = table.insert, table.remove
strmatch, strfind, strsub = string.match, string.find, string.sub
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetTime() return MOCK.now end
---@diagnostic disable-next-line: undefined-global
time = os.time
---@diagnostic disable-next-line: undefined-global
date = os.date
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  table.insert(MOCK.printed, table.concat(parts, " "))
end
function geterrorhandler() return function(msg) error(msg, 0) end end
function GetLocale() return "enUS" end
function UnitName() return "Tester" end
function UnitClass() return "Mage", "MAGE", 8 end
function GetRealmName() return "Test Realm" end
function GetNormalizedRealmName() return "TestRealm" end
function IsControlKeyDown() return MOCK.keys.ctrl or false end
function IsShiftKeyDown() return MOCK.keys.shift or false end
function IsAltKeyDown() return MOCK.keys.alt or false end
function IsModifiedClick() return MOCK.keys.shift or false end
function IsMouseButtonDown() return false end
-- MOCK.cursorPos is { x, y } on screen; without it the cursor is off every frame
function GetCursorPosition()
  if MOCK.cursorPos then return MOCK.cursorPos[1], MOCK.cursorPos[2] end
  return -1000, -1000
end
function GetCursorInfo()
  if MOCK.cursorInfo then return unpack(MOCK.cursorInfo) end
end
function ClearCursor() MOCK.cursorInfo = nil end
-- the TOC's ## fields, which run_tests.py reads from the real TOC
C_AddOns = { GetAddOnMetadata = function(_, field) return TOC_METADATA and TOC_METADATA[field] end }

-- C_Timer.After: run by MOCK.Tick once their time comes
local timers = {}
C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { due = MOCK.now + seconds, fn = fn } end }
local function RunTimers()
  local i = 1
  while i <= #timers do
    if timers[i].due <= MOCK.now then
      table.remove(timers, i).fn() -- a timer can start another; this loop gets to it
    else
      i = i + 1
    end
  end
end
ChatFrameUtil = { InsertLink = function() return false end }

function hooksecurefunc(t, name, fn)
  if type(t) == "string" then t, name, fn = _G, t, name end
  local old = t[name]
  t[name] = function(...)
    local r = { old(...) }
    fn(...)
    return unpack(r)
  end
end

-- StaticPopup: shows are recorded; MOCK.ClickPopup presses a button, as retail does
function StaticPopup_Show(which, a1, a2, data)
  local dialog = { which = which, text_arg1 = a1, text_arg2 = a2, data = data }
  function dialog.Hide() MOCK.popup = nil end
  MOCK.popup = dialog
  table.insert(MOCK.popups, dialog)
  local info = StaticPopupDialogs[which]
  assert(info, "no StaticPopupDialogs entry for " .. tostring(which))
  if info.OnShow then
    dialog.editBox = new("EditBox", UIParent)
    function dialog.GetEditBox() return dialog.editBox end
    info.OnShow(dialog, data)
  end
  return dialog
end

function MOCK.ClickPopup(index)
  local dialog = assert(MOCK.popup, "no popup is showing")
  local info = StaticPopupDialogs[dialog.which]
  MOCK.popup = nil
  if index == 1 and info.OnAccept then info.OnAccept(dialog, dialog.data, dialog.data2)
  elseif index == 3 and info.OnAlt then info.OnAlt(dialog, dialog.data, "clicked")
  elseif index == 2 and info.OnCancel then info.OnCancel(dialog, dialog.data, "clicked") end
end

function MOCK.Fire(event, ...)
  for frame in pairs(MOCK.events[event] or {}) do fire(frame, "OnEvent", event, ...) end
end

-- runs every visible OnUpdate script, `seconds` later
function MOCK.Tick(seconds)
  seconds = seconds or 0.05
  MOCK.now = MOCK.now + seconds
  RunTimers()
  for _, w in ipairs(MOCK.widgets) do
    if w._scripts.OnUpdate and w:IsVisible() then fire(w, "OnUpdate", seconds) end
  end
end

-- fires a script on every widget that has it
function MOCK.FireAll(script, ...)
  for _, w in ipairs(MOCK.widgets) do
    if w._scripts[script] then fire(w, script, ...) end
  end
end

-- a saved variable as Lua source, as the game writes it
function MOCK.Serialize(v, indent)
  indent = indent or ""
  if type(v) == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = { "{\n" }
    for _, k in ipairs(keys) do
      local key = type(k) == "string" and ("[%q]"):format(k) or ("[" .. tostring(k) .. "]")
      out[#out + 1] = indent .. "  " .. key .. " = " .. MOCK.Serialize(v[k], indent .. "  ") .. ",\n"
    end
    out[#out + 1] = indent .. "}"
    return table.concat(out)
  elseif type(v) == "string" then
    return ("%q"):format(v)
  else
    return tostring(v)
  end
end
