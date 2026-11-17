-- Pinned notes: a note rendered in a window of its own, that stays on screen while you play.
--
-- Unlocked, the window has a title bar (its title, and edit, lock, settings, and close) and a
-- size grip, and is moved and used like any window. Locked, it's only the rendered note on a
-- background: it can't be moved or resized, and clicks go through it to the game, until Alt is
-- held over it. Each window's place, size, and settings are kept per character, with which
-- notes are pinned, so they come back at the next login.

local _, ns = ...
local L, W, R = ns.Localization, ns.Widgets, ns.Render
local Notes = ns.Notes

local V = {}
ns.Viewer = V

local open = {}   -- the windows showing, by note id
local pool = {}   -- closed windows, to use again
local FADE_SPEED = 6
local BAR_HEIGHT = 22

-- a pinned note's settings, starting from the defaults for new pinned notes
local function State(id)
  local states = ns.charDB.viewers
  local state = states[id]
  if not state then
    local d = ns.settings.viewer
    state = { bgAlpha = d.bgAlpha, fade = d.fade, fadeAlpha = d.fadeAlpha, width = d.width, height = d.height }
    states[id] = state
  end
  -- click-through was a setting of its own before a locked window let clicks through
  if state.clickThrough then state.locked, state.clickThrough = true, nil end
  return state
end

------------------------------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------------------------------

local function SavePosition(f)
  W.SavePosition(f, f.state)
end

local function Apply(f)
  local state = f.state
  f:SetBackdropColor(0.02, 0.02, 0.03, state.bgAlpha or 0.6)
  f.locked = state.locked
  f.interactive = nil -- Update sets the mouse up again
  f.hovered = nil

  -- Unlocked, the note starts below the title bar, which is always there. Locked, the bar shows
  -- only while Alt is held, over the top of the note, so the note has that space.
  f.scroll:ClearAllPoints()
  f.scroll:SetPoint("TOPLEFT", 10, f.locked and -8 or -(BAR_HEIGHT + 6))
  f.scroll:SetPoint("BOTTOMRIGHT", -14, 8)

  -- the lock button: the padlock in color while locked, gray while not
  local lock = f.lockButton
  local locked = f.locked and true or false
  lock:SetActive(locked)
  lock.icon:SetDesaturated(not locked)
  lock.icon:SetAlpha(locked and 1 or 0.55)
  if locked then
    lock:SetTooltip(L["Unlock"], L["ViewerLockedTooltip"])
  else
    lock:SetTooltip(L["Lock"], L["ViewerUnlockedTooltip"])
  end
end

-- Unlocked, the title bar and size grip are always there. Locked, the bar shows while Alt is
-- held over the window, and the hint says to hold it the rest of the time the mouse is over it.
local function UpdateChrome(f)
  local locked = f.locked and true or false
  f.bar:SetShown(not locked or (f.hovered and f.interactive) or false)
  f.grip:SetShown(not locked)
  f.hint:SetShown(locked and f.hovered and not f.interactive or false)
  f:SetBackdropBorderColor(1, 1, 1, f.hovered and 0.15 or 0)
end

-- Whether the cursor is over f, from where the cursor and f are. IsMouseOver alone won't do: a
-- locked window doesn't take the mouse, so the game may not count it as under it, and then
-- holding Alt could never make it usable again.
local function CursorOver(f)
  if f:IsMouseOver() then return true end
  local left, right, top, bottom = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
  if not (left and right and top and bottom) then return false end
  local x, y = GetCursorPosition()
  local scale = f:GetEffectiveScale()
  x, y = x / scale, y / scale
  return x >= left and x <= right and y >= bottom and y <= top
end

local function OnUpdate(f, elapsed)
  local state = f.state
  local popup = V.settingsPopup
  local hovered = CursorOver(f) or (popup and popup:IsShown() and popup.viewer == f) or false

  -- A locked window lets clicks through to the game until Alt is held over it. Its mouse wheel
  -- and scroll bar work all the time: they don't take clicks from the world.
  local interactive = not state.locked or (hovered and IsAltKeyDown()) or false
  if interactive ~= f.interactive then
    f.interactive = interactive
    f:EnableMouse(interactive)
    f.html:EnableMouse(interactive)
    f.hovered = nil
  end
  if hovered ~= f.hovered then
    f.hovered = hovered
    UpdateChrome(f)
  end

  local target = (state.fade and not hovered) and (state.fadeAlpha or 0.3) or 1
  local alpha = f:GetAlpha()
  if math.abs(alpha - target) > 0.01 then
    f:SetAlpha(alpha + (target - alpha) * math.min(1, elapsed * FADE_SPEED))
  elseif alpha ~= target then
    f:SetAlpha(target)
  end

  if f.relayout then
    f.relayout = nil
    R:SetMarkdown(f.html, f.text)
  end
end

local function CreateWindow()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  W.Backdrop(f, { 0.02, 0.02, 0.03, 0.6 }, { 1, 1, 1, 0 })
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  W.SetResizeBounds(f, 140, 60)
  W.Movable(f, f, function() SavePosition(f) end)

  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", 10, -8)
  scroll:SetPoint("BOTTOMRIGHT", -14, 8)
  local html = CreateFrame("SimpleHTML", nil, scroll)
  html:SetSize(200, 1)
  scroll:SetScrollChild(html)
  R:Setup(html, true)
  -- dragging the text moves the window too
  html:RegisterForDrag("LeftButton")
  html:SetScript("OnDragStart", function() if not f.locked then f:StartMoving() end end)
  html:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    SavePosition(f)
  end)
  W.ScrollBar(scroll, 40)
  scroll:SetScript("OnSizeChanged", function(_, width)
    html:SetWidth(width)
    f.relayout = true
  end)
  f.scroll, f.html = scroll, html

  -- the title bar: the title, and the buttons
  local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(BAR_HEIGHT)
  bar:SetBackdrop({ bgFile = W.WHITE })
  bar:SetBackdropColor(0, 0, 0, 0.75)
  bar:SetFrameLevel(f:GetFrameLevel() + 10)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() if not f.locked then f:StartMoving() end end)
  bar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    SavePosition(f)
  end)
  local close = W.GlyphButton(bar, "×", 18, function() V:Close(f.noteId) end, L["Close"],
    L["ViewerCloseTooltip"])
  close:SetPoint("RIGHT", -2, 0)
  local settings = W.GlyphButton(bar, "≡", 18, function(b) V:ToggleSettings(f, b) end, L["Settings"])
  settings:SetPoint("RIGHT", close, "LEFT", -2, 0)
  local lock = W.IconButton(bar, "Interface\\LFGFrame\\UI-LFG-ICON-LOCK", 18, function() V:ToggleLock(f) end)
  lock:SetPoint("RIGHT", settings, "LEFT", -2, 0)
  f.lockButton = lock
  local edit = W.Button(bar, L["Edit"], function()
    ns.Editor:Show()
    ns.Editor:RequestLoad(f.noteId)
  end, { height = 18, tooltip = L["Edit"], tooltipText = L["ViewerEditTooltip"] })
  edit:SetPoint("RIGHT", lock, "LEFT", -2, 0)
  f.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("LEFT", 8, 0)
  f.title:SetPoint("RIGHT", edit, "LEFT", -6, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)
  f.bar = bar
  bar:Hide()

  f.grip = W.ResizeGrip(f, function() SavePosition(f) end)
  f.grip:Hide()

  -- what a locked window says while the mouse is over it (it doesn't take the mouse itself, so
  -- clicks still go through it)
  local hint = CreateFrame("Frame", nil, f, "BackdropTemplate")
  hint:SetBackdrop({ bgFile = W.WHITE })
  hint:SetBackdropColor(0, 0, 0, 0.75)
  hint:SetFrameLevel(f:GetFrameLevel() + 10)
  hint:SetPoint("TOP", 0, -2)
  local hintText = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hintText:SetPoint("CENTER")
  hintText:SetText(L["ViewerHoldAlt"])
  hint:SetSize(math.ceil(hintText:GetStringWidth()) + 16, 18)
  hint:Hide()
  f.hint = hint

  f:SetScript("OnUpdate", OnUpdate)
  return f
end

------------------------------------------------------------------------------------------------
-- Pinning and unpinning
------------------------------------------------------------------------------------------------

function V:IsOpen(id)
  return id ~= nil and open[id] ~= nil
end

-- shows the note's text, after it was saved
function V:Refresh(id)
  local f, note = open[id], Notes:Get(id)
  if not (f and note) then return end
  f.text = note.text
  f.title:SetText(note.title)
  R:SetMarkdown(f.html, note.text)
end

function V:Open(id)
  local note = Notes:Get(id)
  if not note then return end
  local f = open[id]
  if not f then
    f = table.remove(pool) or CreateWindow()
    open[id] = f
    f.noteId, f.state = id, State(id)
    if f.state.point then
      W.RestorePosition(f, f.state, 340, 280)
    else
      -- a newly pinned note: a little offset from the last, so they don't stack exactly
      local count = 0
      for _ in pairs(open) do count = count + 1 end
      local offset = ((count - 1) % 6) * 24
      f:ClearAllPoints()
      f:SetPoint("CENTER", UIParent, "CENTER", 200 + offset, 60 - offset)
      f:SetSize(f.state.width or 340, f.state.height or 280)
    end
    Apply(f)
    f:SetAlpha(1)
    f:Show()
  end
  f.state.open = true
  f:Raise()
  self:Refresh(id)
  ns:Fire("VIEWERS_CHANGED")
  return f
end

function V:Close(id)
  local f = open[id]
  if not f then return end
  f:Hide()
  open[id] = nil
  f.noteId, f.state = nil, nil
  table.insert(pool, f)
  local state = ns.charDB.viewers[id]
  if state then state.open = nil end
  if self.settingsPopup and self.settingsPopup.viewer == f then self.settingsPopup:Hide() end
  ns:Fire("VIEWERS_CHANGED")
end

function V:CloseAll()
  for id in pairs(open) do self:Close(id) end
end

-- the lock button: locks a window in place, or unlocks it
function V:ToggleLock(f)
  f.state.locked = not f.state.locked or nil
  Apply(f)
  local popup = self.settingsPopup
  if popup and popup:IsShown() and popup.viewer == f then popup:Refresh() end
end

-- the window showing a note, if it's pinned
function V:GetWindow(id)
  return id and open[id]
end

-- makes every pinned note movable and clickable again (/mdn unlock)
function V:UnlockAll()
  local count = 0
  for _, f in pairs(open) do
    if f.state.locked then count = count + 1 end
    f.state.locked = nil
    Apply(f)
  end
  return count
end

function V:ResetPositions()
  for id, state in pairs(ns.charDB.viewers) do
    state.point = nil
    local f = open[id]
    if f then
      f:ClearAllPoints()
      f:SetPoint("CENTER")
    end
  end
end

------------------------------------------------------------------------------------------------
-- A pinned note's settings
------------------------------------------------------------------------------------------------

function V:ToggleSettings(f, owner)
  local p = self.settingsPopup
  if not p then
    p = W.Popup()
    self.settingsPopup = p
    local function state() return p.viewer and p.viewer.state or {} end
    local function apply() if p.viewer then Apply(p.viewer) end end
    local percent = function(v) return math.floor(v * 100 + 0.5) .. "%" end
    local controls, y = {}, -10
    local function place(control, height)
      control:SetPoint("TOPLEFT", 12, y)
      controls[#controls + 1] = control
      y = y - height
    end
    place(W.Slider(p, L["BackgroundOpacity"], 0, 1, 0.05, function() return state().bgAlpha or 0.6 end,
      function(v) state().bgAlpha = v; apply() end, percent, 216), 38)
    place(W.Check(p, L["ViewerFade"], function() return state().fade end,
      function(v) state().fade = v end), 26)
    place(W.Slider(p, L["FadedOpacity"], 0, 1, 0.05, function() return state().fadeAlpha or 0.3 end,
      function(v) state().fadeAlpha = v end, percent, 216), 38)
    place(W.Check(p, L["ViewerLockInPlace"], function() return state().locked end,
      function(v) state().locked = v or nil; apply() end, L["ViewerLockInPlaceTooltip"]), 26)
    p:SetSize(240, -y + 4)
    function p:Refresh()
      for _, control in ipairs(controls) do control:Refresh() end
    end
  end
  p.viewer = f
  p:Toggle(owner, "TOPRIGHT", "BOTTOMRIGHT", 0, -4)
end

------------------------------------------------------------------------------------------------

ns:On("NOTE_SAVED", function(id) V:Refresh(id) end)

ns:On("NOTE_DELETED", function(id)
  V:Close(id)
  ns.charDB.viewers[id] = nil
end)

-- the notes this character had pinned come back; settings for deleted notes are dropped
ns:On("LOGIN", function()
  for id, state in pairs(ns.charDB.viewers) do
    if not Notes:Get(id) then
      ns.charDB.viewers[id] = nil
    elseif state.open then
      V:Open(id)
    end
  end
end)
