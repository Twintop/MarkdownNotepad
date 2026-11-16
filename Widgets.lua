-- The small set of flat, dark widgets the editor and the pinned notes are built from. They're
-- drawn with plain textures and backdrops instead of Blizzard's templates, which look different
-- (or don't exist) from one game version to the next.

local ADDON, ns = ...
local W = {}
ns.Widgets = W

local WHITE = "Interface\\Buttons\\WHITE8X8"
W.WHITE = WHITE
W.MONO_FONT = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Fonts\\JetBrainsMono-Regular.ttf"
W.IMAGES = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Images\\"

local C = {
  bg       = { 0.055, 0.055, 0.065, 0.97 },
  panel    = { 0.085, 0.085, 0.095, 1 },
  inset    = { 0.035, 0.035, 0.045, 1 },
  border   = { 0.20, 0.20, 0.23, 1 },
  button   = { 0.14, 0.14, 0.16, 1 },
  hover    = { 0.21, 0.21, 0.25, 1 },
  pressed  = { 0.09, 0.09, 0.11, 1 },
  active   = { 0.18, 0.16, 0.08, 1 },
  accent   = { 1.00, 0.82, 0.00, 1 },
  focus    = { 0.55, 0.45, 0.10, 1 },
  select   = { 0.25, 0.50, 0.90, 0.30 },
  text     = { 0.90, 0.90, 0.90, 1 },
  muted    = { 0.55, 0.55, 0.60, 1 },
}
W.colors = C

local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

function W.Backdrop(frame, bg, border)
  frame:SetBackdrop(BACKDROP)
  frame:SetBackdropColor(unpack(bg or C.bg))
  frame:SetBackdropBorderColor(unpack(border or C.border))
end

-- the monospace font, for the editor and for the symbols on the small buttons
W.glyphFont = CreateFont("MarkdownNotepadGlyphFont")
W.glyphFont:SetFont(W.MONO_FONT, 13, "")
W.glyphFont:SetTextColor(unpack(C.text))

function W.Tooltip(owner, title, text, anchor)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_TOP")
  GameTooltip:SetText(title, 1, 1, 1)
  if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
  GameTooltip:Show()
end

local function HideTooltip()
  GameTooltip:Hide()
end

------------------------------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------------------------------

local function PaintButton(b)
  local bg
  if not b:IsEnabled() then bg = C.button
  elseif b.isDown then bg = C.pressed
  elseif b.isOver then bg = C.hover
  elseif b.active then bg = C.active
  else bg = b.bg or C.button end
  b:SetBackdropColor(unpack(bg))
  b:SetBackdropBorderColor(unpack(b.active and C.focus or C.border))
  local text = b:IsEnabled() and (b.textColor or C.text) or C.muted
  b.label:SetTextColor(unpack(text))
end

local buttonMethods = {}

function buttonMethods:SetActive(active)
  self.active = active and true or nil
  PaintButton(self)
end

function buttonMethods:SetLabel(text)
  self.label:SetText(text)
  if self.autoWidth then self:SetWidth(math.ceil(self.label:GetStringWidth()) + self.autoWidth) end
end

function buttonMethods:SetTooltip(title, text)
  self.tipTitle, self.tipText = title, text
end

-- A flat button. opts: width (else it fits its label), height, font (a font object or its name),
-- tooltip and tooltipText, bg (its color when idle).
function W.Button(parent, label, onClick, opts)
  opts = opts or {}
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  for k, v in pairs(buttonMethods) do b[k] = v end
  W.Backdrop(b, C.button, C.border)
  b.bg = opts.bg
  b.label = b:CreateFontString(nil, "OVERLAY")
  b.label:SetFontObject(opts.font or "GameFontHighlightSmall")
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetWordWrap(false)
  b:SetHeight(opts.height or 20)
  if opts.width then b:SetWidth(opts.width) else b.autoWidth = opts.padding or 14 end
  b:SetLabel(label)
  b.tipTitle, b.tipText = opts.tooltip, opts.tooltipText
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    HideTooltip()
    if onClick then onClick(self, button) end
  end)
  b:SetScript("OnEnter", function(self)
    self.isOver = true
    PaintButton(self)
    if self.tipTitle then W.Tooltip(self, self.tipTitle, self.tipText) end
  end)
  b:SetScript("OnLeave", function(self)
    self.isOver = nil
    PaintButton(self)
    HideTooltip()
  end)
  b:SetScript("OnMouseDown", function(self) self.isDown = true; PaintButton(self) end)
  b:SetScript("OnMouseUp", function(self) self.isDown = nil; PaintButton(self) end)
  b:SetScript("OnEnable", PaintButton)
  b:SetScript("OnDisable", PaintButton)
  PaintButton(b)
  return b
end

-- a square button showing one symbol from the monospace font
function W.GlyphButton(parent, glyph, size, onClick, tooltip, tooltipText)
  local b = W.Button(parent, glyph, onClick, {
    width = size, height = size, font = W.glyphFont, tooltip = tooltip, tooltipText = tooltipText,
  })
  return b
end

-- A footer button, as in TwintopQOL's and TwintopInsanityBar's windows: an icon, its label, a
-- 1px border, and a hover tint. `background` is the gray of its background; `border` is the
-- color of its border and tint ({ r, g, b }), or nil for gray.
function W.FooterButton(parent, label, icon, background, border, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(120, 20)
  b:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = WHITE,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  b:SetBackdropColor(background, background, background, 1)
  b:RegisterForClicks("AnyUp")

  local highlight = b:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  if border then
    b:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    highlight:SetColorTexture(border[1], border[2], border[3], 0.15)
  else
    b:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    highlight:SetColorTexture(1, 1, 1, 0.1)
  end

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(14, 14)
  b.icon:SetPoint("LEFT", 8, 0)
  b.icon:SetTexture(icon)

  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER", 8, 0)
  b.label:SetText(label)

  b:SetScript("OnClick", onClick)
  return b
end

-- a square button showing a texture (as b.icon)
function W.IconButton(parent, texture, size, onClick, tooltip, tooltipText)
  local b = W.Button(parent, "", onClick, { width = size, height = size, tooltip = tooltip, tooltipText = tooltipText })
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("CENTER")
  b.icon:SetSize(size - 4, size - 4)
  b.icon:SetTexture(texture)
  return b
end

-- a flat check box with its label; get() and set(value) read and write the setting
function W.Check(parent, label, get, set, tooltip)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(18)
  local box = CreateFrame("Frame", nil, b, "BackdropTemplate")
  box:SetSize(14, 14)
  box:SetPoint("LEFT", 0, 0)
  W.Backdrop(box, C.inset, C.border)
  local check = box:CreateTexture(nil, "OVERLAY")
  check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  check:SetPoint("CENTER", 1, 0)
  check:SetSize(18, 18)
  local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT", box, "RIGHT", 6, 0)
  text:SetJustifyH("LEFT")
  text:SetText(label)
  b:SetWidth(20 + text:GetStringWidth())
  b.text = text
  function b:Refresh() check:SetShown(get() and true or false) end
  b:SetScript("OnClick", function(self)
    set(not get())
    self:Refresh()
  end)
  b:SetScript("OnEnter", function(self)
    box:SetBackdropBorderColor(unpack(C.focus))
    if tooltip then W.Tooltip(self, label, tooltip) end
  end)
  b:SetScript("OnLeave", function()
    box:SetBackdropBorderColor(unpack(C.border))
    HideTooltip()
  end)
  b:Refresh()
  return b
end

-- A labeled horizontal slider, showing its value as fmt(value) formats it.
function W.Slider(parent, label, minValue, maxValue, step, get, set, fmt, width)
  fmt = fmt or tostring
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width or 200, 32)
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  title:SetPoint("TOPLEFT", 0, 0)
  title:SetText(label)
  local value = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  value:SetPoint("TOPRIGHT", 0, 0)

  local s = CreateFrame("Slider", nil, f, "BackdropTemplate")
  s:SetOrientation("HORIZONTAL")
  s:SetHeight(8)
  s:SetPoint("BOTTOMLEFT", 0, 4)
  s:SetPoint("BOTTOMRIGHT", 0, 4)
  W.Backdrop(s, C.inset, C.border)
  s:SetThumbTexture(WHITE)
  local thumb = s:GetThumbTexture()
  thumb:SetSize(8, 14)
  thumb:SetVertexColor(unpack(C.accent))
  s:SetMinMaxValues(minValue, maxValue)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / step + 0.5) * step
    value:SetText(fmt(v))
    if not f.refreshing then set(v) end
  end)
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(math.max(minValue, math.min(maxValue, self:GetValue() + delta * step)))
  end)
  f.slider = s
  function f:Refresh()
    self.refreshing = true
    s:SetValue(get())
    value:SetText(fmt(get()))
    self.refreshing = nil
  end
  f:Refresh()
  return f
end

-- A one-line text box. Escape and Enter leave it; placeholder is shown while it's empty.
function W.Input(parent, placeholder, height)
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  W.Backdrop(e, C.inset, C.border)
  e:SetAutoFocus(false)
  e:SetFontObject("GameFontHighlight")
  e:SetTextInsets(6, 6, 0, 0)
  e:SetHeight(height or 22)
  e:SetMaxLetters(200)
  e.placeholder = e:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  e.placeholder:SetPoint("LEFT", 6, 0)
  e.placeholder:SetText(placeholder or "")
  local function UpdatePlaceholder(self)
    self.placeholder:SetShown(not self:HasFocus() and self:GetText() == "")
  end
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  e:SetScript("OnEditFocusGained", function(self)
    self:SetBackdropBorderColor(unpack(C.focus))
    UpdatePlaceholder(self)
  end)
  e:SetScript("OnEditFocusLost", function(self)
    self:SetBackdropBorderColor(unpack(C.border))
    self:HighlightText(0, 0)
    UpdatePlaceholder(self)
  end)
  e:HookScript("OnTextChanged", UpdatePlaceholder)
  return e
end

------------------------------------------------------------------------------------------------
-- Scrolling
------------------------------------------------------------------------------------------------

-- A thin scroll bar to the right of scroll, and mouse wheel scrolling. It hides itself while
-- everything fits.
function W.ScrollBar(scroll, wheelStep)
  local bar = CreateFrame("Slider", nil, scroll:GetParent())
  bar:EnableMouse(true) -- even when the frame it's in lets clicks through
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(6)
  bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 3, 0)
  bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 3, 0)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.04)
  bar:SetThumbTexture(WHITE)
  local thumb = bar:GetThumbTexture()
  thumb:SetWidth(6)
  thumb:SetVertexColor(1, 1, 1, 0.22)
  bar:SetMinMaxValues(0, 0)
  bar:SetValue(0)
  bar:SetScript("OnValueChanged", function(_, v)
    if not bar.updating then scroll:SetVerticalScroll(v) end
  end)
  bar:SetScript("OnEnter", function() thumb:SetVertexColor(1, 1, 1, 0.4) end)
  bar:SetScript("OnLeave", function() thumb:SetVertexColor(1, 1, 1, 0.22) end)

  local function Update()
    local range = scroll:GetVerticalScrollRange() or 0
    local height = scroll:GetHeight() or 0
    bar.updating = true
    bar:SetMinMaxValues(0, range)
    bar:SetValue(math.min(scroll:GetVerticalScroll(), range))
    bar.updating = nil
    if range > 0.5 and height > 0 then
      thumb:SetHeight(math.max(18, bar:GetHeight() * height / (height + range)))
      bar:Show()
    else
      bar:Hide()
    end
  end
  bar.Update = Update
  scroll:HookScript("OnScrollRangeChanged", Update)
  scroll:HookScript("OnVerticalScroll", Update)
  scroll:HookScript("OnSizeChanged", Update)

  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    local v = self:GetVerticalScroll() - delta * (wheelStep or 40)
    self:SetVerticalScroll(math.max(0, math.min(v, range)))
  end)
  Update()
  return bar
end

-- scrolls so that the band from top to bottom (offsets down the scroll child) is in view
function W.ScrollIntoView(scroll, top, bottom)
  scroll:UpdateScrollChildRect()
  local offset, height = scroll:GetVerticalScroll(), scroll:GetHeight()
  local range = scroll:GetVerticalScrollRange() or 0
  if top < offset then
    scroll:SetVerticalScroll(math.max(0, top))
  elseif bottom > offset + height then
    scroll:SetVerticalScroll(math.min(range, bottom - height))
  end
end

------------------------------------------------------------------------------------------------
-- Windows
------------------------------------------------------------------------------------------------

function W.SetResizeBounds(frame, minW, minH, maxW, maxH)
  maxW, maxH = maxW or 4000, maxH or 4000
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH, maxW, maxH)
  else
    frame:SetMinResize(minW, minH)
    frame:SetMaxResize(maxW, maxH)
  end
end

-- drag `handle` (or the frame itself) to move frame; frame.locked stops it
function W.Movable(frame, handle, onStop)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  handle = handle or frame
  handle:EnableMouse(true)
  handle:RegisterForDrag("LeftButton")
  handle:SetScript("OnDragStart", function()
    if not frame.locked then frame:StartMoving() end
  end)
  handle:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    if onStop then onStop() end
  end)
end

-- the size grip in a frame's bottom right corner
function W.ResizeGrip(frame, onStop)
  frame:SetResizable(true)
  local g = CreateFrame("Button", nil, frame)
  g:SetSize(14, 14)
  g:SetPoint("BOTTOMRIGHT", -2, 2)
  g:SetFrameLevel(frame:GetFrameLevel() + 10)
  g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  g:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and not frame.locked then frame:StartSizing("BOTTOMRIGHT") end
  end)
  g:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    if onStop then onStop() end
  end)
  return g
end

-- keeps a frame's position and size in t
function W.SavePosition(frame, t)
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  if point then t.point = { point, relativePoint, x, y } end
  t.width, t.height = frame:GetSize()
end

function W.RestorePosition(frame, t, defaultWidth, defaultHeight)
  frame:ClearAllPoints()
  local p = t.point
  if p then
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    frame:SetPoint("CENTER")
  end
  frame:SetSize(t.width or defaultWidth, t.height or defaultHeight)
end

-- A panel that closes when the player clicks anywhere outside it (or its owner, the button that
-- opened it), or presses Escape.
function W.Popup(name)
  local p = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  W.Backdrop(p, C.panel, C.border)
  p:SetFrameStrata("DIALOG")
  p:SetClampedToScreen(true)
  p:EnableMouse(true)
  p:Hide()
  if name then tinsert(UISpecialFrames, name) end
  p:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
  p:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
  p:SetScript("OnEvent", function(self)
    if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
  end)
  -- shows the popup by owner, or hides it if it's already showing there
  function p:Toggle(owner, point, relativePoint, x, y)
    if self:IsShown() and self.owner == owner then self:Hide() return end
    self.owner = owner
    self:ClearAllPoints()
    self:SetPoint(point or "TOPLEFT", owner, relativePoint or "BOTTOMLEFT", x or 0, y or -2)
    self:Show()
    if self.Refresh then self:Refresh() end
  end
  return p
end

-- a thin line, for separating parts of a panel
function W.Divider(parent, layer)
  local t = parent:CreateTexture(nil, layer or "BORDER")
  t:SetColorTexture(unpack(C.border))
  return t
end
