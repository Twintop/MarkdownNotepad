-- The editor window: the notes in a sidebar, the note's title and scope, the formatting toolbar,
-- the text editor, and the preview.

local _, ns = ...
local L, A, W, R = ns.Localization, ns.Actions, ns.Widgets, ns.Render
local Notes = ns.Notes

local E = {}
ns.Editor = E

local SIDEBAR_WIDTH = 200
local ROW_HEIGHT = 20
local PREVIEW_DELAY = 0.25
local AUTOSAVE_DELAY = 2 -- seconds after the last change

local function Settings() return ns.settings end

------------------------------------------------------------------------------------------------
-- Dialogs
------------------------------------------------------------------------------------------------

StaticPopupDialogs.MARKDOWNNOTEPAD_UNSAVED = {
  text = L["UnsavedPrompt"],
  button1 = L["Save"],
  button2 = L["Cancel"],
  button3 = L["DontSave"],
  OnAccept = function(_, data)
    E:Save()
    data.continue()
  end,
  OnAlt = function(_, data) data.continue() end,
  showAlert = true,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

StaticPopupDialogs.MARKDOWNNOTEPAD_DELETE = {
  text = L["DeletePrompt"],
  button1 = L["Delete"],
  button2 = L["Cancel"],
  OnAccept = function(_, data) E:DeleteNote(data.id) end,
  showAlert = true,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

------------------------------------------------------------------------------------------------
-- The toolbar
------------------------------------------------------------------------------------------------

local function Wrap(left, right, placeholder)
  return function(ed) ed:Apply(A.Wrap, left, right or left, placeholder) end
end

local function Insert(str, selA, selB)
  return function(ed) ed:Apply(A.Insert, str, selA, selB) end
end

local function Block(block, selA, selB)
  return function(ed) ed:Apply(A.Block, block, selA, selB) end
end

local function Alert(kind)
  return Block("> [!" .. kind .. "]\n> ")
end

-- each button: its label, tooltip title, tooltip text, and what it does to the editor. false
-- puts a gap between groups of buttons.
local TOOLS = {
  { "H1", L["ToolHeading1"], "# ", function(ed) ed:Apply(A.Heading, 1) end },
  { "H2", L["ToolHeading2"], "## ", function(ed) ed:Apply(A.Heading, 2) end },
  { "H3", L["ToolHeading3"], "### ", function(ed) ed:Apply(A.Heading, 3) end },
  false,
  { "B", L["ToolBold"], "**bold** (Ctrl-B)", Wrap("**", "**", L["PlaceholderBold"]) },
  { "I", L["ToolItalic"], "*italic* (Ctrl-I)", Wrap("*", "*", L["PlaceholderItalic"]) },
  { "S", L["ToolStrikethrough"], "~~struck~~", Wrap("~~", "~~", L["PlaceholderStruck"]) },
  { "==", L["ToolHighlight"], "==highlighted==", Wrap("==", "==", L["PlaceholderHighlighted"]) },
  { "`", L["ToolCode"], "`code`", Wrap("`", "`", L["PlaceholderCode"]) },
  { "```", L["ToolCodeBlock"], "```", function(ed) ed:Apply(A.CodeBlock) end },
  false,
  { "•", L["ToolBulletedList"], "- ", function(ed) ed:Apply(A.List, "bullet") end },
  { "1.", L["ToolNumberedList"], "1. ", function(ed) ed:Apply(A.List, "ordered") end },
  { "[ ]", L["ToolTaskList"], "- [ ] ", function(ed) ed:Apply(A.List, "task") end },
  { ">", L["ToolQuote"], "> ", function(ed) ed:Apply(A.Quote) end },
  { "---", L["ToolRule"], "---", Block("---") },
  { L["ToolTableLabel"], L["ToolTable"], "| a | b |", Block(A.TABLE, 2, 8) },
  false,
  { L["ToolLinkLabel"], L["ToolLink"], "[text](url) (Ctrl-K)", function(ed) ed:Apply(A.Link) end },
  { L["ToolImageLabel"], L["ToolImage"], L["ToolImageTooltip"],
    Insert("![](Interface\\\\Icons\\\\INV_Misc_QuestionMark 32x32)", 4, 43) },
  { L["ToolIconsLabel"] .. " ▾", L["ToolIcons"], L["ToolIconsTooltip"], "icons" },
  { L["ToolMoreLabel"] .. " ▾", L["ToolMore"], L["ToolMoreTooltip"], "more" },
}

local MORE = {
  { L["MoreNoteLink"], function(ed) ed:Apply(A.NoteLink) end },
  { L["MoreSpellLink"], Insert("[Name](spell:ID)", 13, 15) },
  { L["MoreItemLink"], Insert("[Name](item:ID)", 12, 14) },
  { L["MoreSpellIcon"], Insert("![](spell:ID)", 10, 12) },
  { L["MoreAtlas"], Insert("![](atlas:name)", 10, 14) },
  false,
  { L["MoreAlertNote"], Alert("NOTE") },
  { L["MoreAlertTip"], Alert("TIP") },
  { L["MoreAlertImportant"], Alert("IMPORTANT") },
  { L["MoreAlertWarning"], Alert("WARNING") },
  { L["MoreAlertCaution"], Alert("CAUTION") },
  false,
  { L["MoreFootnote"], function(ed) ed:Apply(A.Footnote) end },
  { L["MoreDefinition"], Block("Term\n: Definition", 0, 4) },
}

local SHORTCODES = { ":check:", ":x:", ":question:", ":warning:", ":tank:", ":healer:", ":dps:", ":gold:", ":silver:", ":copper:" }

------------------------------------------------------------------------------------------------
-- Building the window
------------------------------------------------------------------------------------------------

function E:Create()
  local settings = Settings()
  local f = CreateFrame("Frame", "MarkdownNotepadEditor", UIParent, "BackdropTemplate")
  self.frame = f
  W.Backdrop(f, W.colors.bg, W.colors.border)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:Hide()
  W.SetResizeBounds(f, 720, 380)
  W.RestorePosition(f, settings.editor, 1000, 620)
  tinsert(UISpecialFrames, "MarkdownNotepadEditor")
  local function SavePosition() W.SavePosition(f, settings.editor) end

  -- title bar
  local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
  titleBar:SetPoint("TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", -1, -1)
  titleBar:SetHeight(26)
  titleBar:SetBackdrop({ bgFile = W.WHITE })
  titleBar:SetBackdropColor(unpack(W.colors.panel))
  W.Movable(f, titleBar, SavePosition)
  local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", 10, 0)
  title:SetText(L["MarkdownNotepad"])
  local close = W.GlyphButton(titleBar, "×", 20, function() f:Hide() end, L["Close"])
  close:SetPoint("RIGHT", -3, 0)

  -- footer: the version, and the links (as in TwintopQOL's and TwintopInsanityBar's windows)
  local footer = self:BuildFooter(f)
  W.Movable(f, footer, SavePosition)
  W.ResizeGrip(f, function()
    SavePosition()
    E:LayoutToolbar()
  end)

  -- status bar
  local status = CreateFrame("Frame", nil, f, "BackdropTemplate")
  status:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 1)
  status:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 1)
  status:SetHeight(24)
  status:SetBackdrop({ bgFile = W.WHITE })
  status:SetBackdropColor(unpack(W.colors.panel))
  self.status = status
  self.statusText = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.statusText:SetPoint("LEFT", 10, 0)
  self.statusText:SetTextColor(unpack(W.colors.muted))

  local settingsButton = W.Button(status, L["Settings"], function(b) E:ToggleSettings(b) end)
  settingsButton:SetPoint("RIGHT", -4, 0)
  self.previewToggle = W.Button(status, L["Preview"], function() E:SetPreviewShown(not settings.showPreview) end,
    { tooltip = L["Preview"], tooltipText = L["PreviewTooltip"] })
  self.previewToggle:SetPoint("RIGHT", settingsButton, "LEFT", -4, 0)
  self.sidebarToggle = W.Button(status, L["Notes"], function() E:SetSidebarShown(not settings.showSidebar) end,
    { tooltip = L["Notes"], tooltipText = L["NotesTooltip"] })
  self.sidebarToggle:SetPoint("RIGHT", self.previewToggle, "LEFT", -4, 0)

  -- sidebar
  local side = CreateFrame("Frame", nil, f, "BackdropTemplate")
  side:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -1)
  side:SetPoint("BOTTOMLEFT", status, "TOPLEFT", 0, 1)
  side:SetWidth(SIDEBAR_WIDTH)
  side:SetBackdrop({ bgFile = W.WHITE })
  side:SetBackdropColor(unpack(W.colors.panel))
  self.sidebar = side
  self:BuildSidebar(side)

  -- the note: title, scope, and buttons; then the toolbar; then the editor and preview
  local main = CreateFrame("Frame", nil, f)
  main:SetPoint("BOTTOMRIGHT", status, "TOPRIGHT", 0, 1)
  self.main, self.titleBar = main, titleBar
  self:BuildHeader(main)
  self:BuildToolbar(main)
  self:BuildContent(main)

  f:SetScript("OnUpdate", function() E:OnUpdate() end)
  f:SetScript("OnHide", function()
    E:Autosave()
    if E.settingsPopup then E.settingsPopup:Hide() end
    if E.iconPopup then E.iconPopup:Hide() end
    if E.morePopup then E.morePopup:Hide() end
  end)

  ns:On("NOTE_SAVED", function() E:RefreshList() end)
  ns:On("NOTE_DELETED", function(id)
    if E.current.id == id then E:LoadNote(nil) end
    E:RefreshList()
  end)
  ns:On("VIEWERS_CHANGED", function() E:UpdateButtons() end)

  self:SetSidebarShown(settings.showSidebar)
  self:SetPreviewShown(settings.showPreview)
  self:ApplySettings()
  self:OpenFirstNote()
end

-- Discord's blurple, for its button's border
local BLURPLE = { 0.345, 0.396, 0.949 }

-- the strip along the bottom: the version on the left; News, GitHub Issues, Ko-fi, and Discord
-- on the right
function E:BuildFooter(f)
  local footer = CreateFrame("Frame", nil, f, "BackdropTemplate")
  footer:SetPoint("BOTTOMLEFT", 1, 1)
  footer:SetPoint("BOTTOMRIGHT", -1, 1)
  footer:SetHeight(24)
  footer:SetBackdrop({ bgFile = W.WHITE })
  footer:SetBackdropColor(unpack(W.colors.panel))

  local divider = W.Divider(footer, "ARTWORK")
  divider:SetHeight(1)
  divider:SetPoint("BOTTOMLEFT", footer, "TOPLEFT")
  divider:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT")

  local version = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  version:SetPoint("LEFT", 8, 0)
  version:SetTextColor(0.6, 0.6, 0.6, 1)
  version:SetText(ns.fullVersion)

  -- right to left, as TwintopQOL's are; the first leaves room for the size grip
  local discord = W.FooterButton(footer, L["FooterDiscord"], W.IMAGES .. "discord64.png", 0, BLURPLE, function()
    ns:ShowUrl(L["FooterDiscord"], L["FooterDiscordUrl"])
  end)
  discord:SetPoint("RIGHT", -20, 0)
  local kofi = W.FooterButton(footer, L["FooterKofi"], W.IMAGES .. "kofi.png", 0, nil, function()
    ns:ShowUrl(L["FooterKofi"], L["FooterKofiUrl"])
  end)
  kofi:SetPoint("RIGHT", discord, "LEFT", -6, 0)
  local github = W.FooterButton(footer, L["FooterGitHubIssues"], W.IMAGES .. "GitHub_Invertocat_White64.png", 0, nil, function()
    ns:ShowUrl(L["FooterGitHubIssues"], L["GitHubIssuesUrl"])
  end)
  github:SetPoint("RIGHT", kofi, "LEFT", -6, 0)
  local news = W.FooterButton(footer, L["FooterNews"], W.IMAGES .. "newspaper.png", 0.1, nil, function()
    ns.News:Toggle()
  end)
  news:SetPoint("RIGHT", github, "LEFT", -6, 0)

  self.footer = footer
  return footer
end

function E:BuildSidebar(side)
  local search = W.Input(side, L["Search"])
  search:SetPoint("TOPLEFT", 8, -8)
  search:SetPoint("TOPRIGHT", -8, -8)
  search:HookScript("OnTextChanged", function(box)
    E.filter = box:GetText()
    E:RefreshList()
  end)

  local new = W.Button(side, "+ " .. L["NewNote"], function() E:NewNote() end, { height = 22 })
  new:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
  new:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -6)

  local scroll = CreateFrame("ScrollFrame", nil, side)
  scroll:SetPoint("TOPLEFT", new, "BOTTOMLEFT", 0, -6)
  scroll:SetPoint("BOTTOMRIGHT", -12, 6)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(SIDEBAR_WIDTH - 20, 1)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnSizeChanged", function(_, width) child:SetWidth(width) end)
  W.ScrollBar(scroll, ROW_HEIGHT * 3)
  self.listChild, self.rows = child, {}
end

function E:BuildHeader(main)
  local header = CreateFrame("Frame", nil, main)
  header:SetPoint("TOPLEFT", 8, -8)
  header:SetPoint("TOPRIGHT", -8, -8)
  header:SetHeight(24)
  self.header = header

  local delete = W.Button(header, L["Delete"], function() E:ConfirmDelete() end,
    { height = 24, tooltip = L["Delete"], tooltipText = L["DeleteTooltip"] })
  delete:SetPoint("RIGHT", 0, 0)
  self.pinButton = W.Button(header, L["Pin"], function(b, button)
    -- right-click: the pinned window's settings, which a click-through window can't be reached for
    local window = ns.Viewer:GetWindow(E.current.id)
    if button == "RightButton" and window then
      ns.Viewer:ToggleSettings(window, b)
    else
      E:TogglePin()
    end
  end, { height = 24, width = 64 })
  self.pinButton:SetPoint("RIGHT", delete, "LEFT", -4, 0)
  self.copyButton = W.Button(header, L["SaveCopy"], function() E:SaveCopy() end, {
    height = 24, tooltip = L["SaveCopy"],
    tooltipText = L["SaveCopyTooltip"],
  })
  self.copyButton:SetPoint("RIGHT", self.pinButton, "LEFT", -4, 0)
  self.saveButton = W.Button(header, L["Save"], function() E:Save() end,
    { height = 24, width = 64, tooltip = L["Save"], tooltipText = "Ctrl-S" })
  self.saveButton:SetPoint("RIGHT", self.copyButton, "LEFT", -4, 0)
  self.scopeButton = W.Button(header, L["Account"], function() E:ToggleScope() end, { height = 24, width = 130 })
  self.scopeButton:SetPoint("RIGHT", self.saveButton, "LEFT", -8, 0)

  local titleBox = W.Input(header, L["TitlePlaceholder"], 24)
  titleBox:SetPoint("LEFT", 0, 0)
  titleBox:SetPoint("RIGHT", self.scopeButton, "LEFT", -6, 0)
  titleBox:SetFontObject("GameFontNormal")
  titleBox:SetMaxLetters(120)
  titleBox:HookScript("OnTextChanged", function(_, userInput)
    if userInput then E:UpdateDirty() end
  end)
  titleBox:SetScript("OnEnterPressed", function() E.editor:Focus() end)
  titleBox:SetScript("OnTabPressed", function() E.editor:Focus() end)
  titleBox:SetScript("OnKeyDown", function(_, key)
    if key == "S" and IsControlKeyDown() then
      if IsShiftKeyDown() then E:SaveCopy() else E:Save() end
    end
  end)
  self.titleBox = titleBox
end

function E:BuildToolbar(main)
  local toolbar = CreateFrame("Frame", nil, main)
  toolbar:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -6)
  toolbar:SetPoint("TOPRIGHT", self.header, "BOTTOMRIGHT", 0, -6)
  toolbar:SetHeight(22)
  toolbar:SetScript("OnSizeChanged", function() E:LayoutToolbar() end)
  self.toolbar, self.toolItems = toolbar, {}
  for _, tool in ipairs(TOOLS) do
    if not tool then
      table.insert(self.toolItems, { gap = true })
    else
      local label, tip, tipText, action = tool[1], tool[2], tool[3], tool[4]
      local button = W.Button(toolbar, label, function(b)
        if action == "icons" then
          E:ToggleIconPopup(b)
        elseif action == "more" then
          E:ToggleMorePopup(b)
        else
          action(E.editor)
        end
      end, { height = 22, font = W.glyphFont, padding = 16, tooltip = tip, tooltipText = tipText })
      table.insert(self.toolItems, { button = button })
    end
  end
end

-- the toolbar's buttons, flowing onto more rows when the window is narrow
function E:LayoutToolbar()
  local width = self.toolbar:GetWidth()
  if not width or width <= 0 then return end
  self.toolbarWidth = width
  local x, y, gap, rowHeight = 0, 0, 3, 22
  for _, item in ipairs(self.toolItems) do
    if item.gap then
      if x > 0 then x = x + 8 end
    else
      local b = item.button
      local bw = b:GetWidth()
      if x > 0 and x + bw > width then x, y = 0, y + rowHeight + gap end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", self.toolbar, "TOPLEFT", x, -y)
      x = x + bw + gap
    end
  end
  self.toolbar:SetHeight(y + rowHeight)
end

function E:BuildContent(main)
  local settings = Settings()
  local content = CreateFrame("Frame", nil, main)
  content:SetPoint("TOPLEFT", self.toolbar, "BOTTOMLEFT", 0, -6)
  content:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", -8, 8)
  content:SetScript("OnSizeChanged", function() E:LayoutContent() end)
  self.content = content

  local ed = ns.CodeEditor.Create(content)
  self.editor = ed
  ed.onChange = function(_, loaded)
    if not loaded then E:UpdateDirty() end
    E:SchedulePreview(loaded)
  end
  ed.onCursor = function(line, column)
    E.cursorLine, E.cursorColumn = line, column
    E:UpdateStatus()
  end
  ed.onShortcut = function(key)
    if key == "S" then
      if IsShiftKeyDown() then E:SaveCopy() else E:Save() end
    elseif key == "B" then ed:Apply(A.Wrap, "**", "**", L["PlaceholderBold"])
    elseif key == "I" then ed:Apply(A.Wrap, "*", "*", L["PlaceholderItalic"])
    elseif key == "K" then ed:Apply(A.Link)
    end
  end

  -- the divider between the editor and the preview, dragged to share the width between them
  local splitter = CreateFrame("Button", nil, content)
  splitter:SetWidth(8)
  local line = splitter:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOP")
  line:SetPoint("BOTTOM")
  line:SetWidth(1)
  line:SetColorTexture(unpack(W.colors.border))
  local glow = splitter:CreateTexture(nil, "HIGHLIGHT")
  glow:SetAllPoints()
  glow:SetColorTexture(1, 1, 1, 0.06)
  splitter:SetScript("OnMouseDown", function(s) s.dragging = true end)
  splitter:SetScript("OnMouseUp", function(s) s.dragging = nil end)
  splitter:SetScript("OnUpdate", function(s)
    if not s.dragging then return end
    if not IsMouseButtonDown("LeftButton") then s.dragging = nil return end
    local left, width = content:GetLeft(), content:GetWidth()
    if not left or not width or width <= 0 then return end
    local x = GetCursorPosition() / content:GetEffectiveScale()
    local split = (x - left) / width
    settings.split = math.max(0.2, math.min(0.8, split))
    E:LayoutContent()
  end)
  self.splitter = splitter

  local preview = CreateFrame("Frame", nil, content, "BackdropTemplate")
  W.Backdrop(preview, W.colors.inset, W.colors.border)
  local scroll = CreateFrame("ScrollFrame", nil, preview)
  scroll:SetPoint("TOPLEFT", 10, -8)
  scroll:SetPoint("BOTTOMRIGHT", -16, 8)
  local html = CreateFrame("SimpleHTML", nil, scroll)
  html:SetSize(200, 1)
  scroll:SetScrollChild(html)
  R:Setup(html, true)
  W.ScrollBar(scroll, 48)
  scroll:SetScript("OnSizeChanged", function() E:FitPreview() end)
  self.preview, self.previewScroll, self.previewHTML = preview, scroll, html
end

-- The layout follows the frames' sizes: OnSizeChanged lays them out again, and so does OnUpdate
-- whenever a size has changed since. OnSizeChanged alone isn't enough: it can come while the
-- size still reads 0, and on the Forever client the editor and preview never appeared.
function E:CheckLayout()
  if self.toolbar:GetWidth() ~= self.toolbarWidth then self:LayoutToolbar() end
  if self.content:GetWidth() ~= self.contentWidth then self:LayoutContent() end
  if self.preview:IsShown() then self:FitPreview() end
end

-- the preview wraps at its width; SetMarkdown lays it out again at a new one
function E:FitPreview()
  local width = self.previewScroll:GetWidth()
  if not width or width <= 0 or width == self.previewWidth then return end
  self.previewWidth = width
  self.previewHTML:SetWidth(width)
  self:SchedulePreview()
end

function E:LayoutContent()
  local width = self.content:GetWidth()
  if not width or width <= 0 then return end
  self.contentWidth = width
  local ef = self.editor.frame
  ef:ClearAllPoints()
  ef:SetPoint("TOPLEFT")
  ef:SetPoint("BOTTOMLEFT")
  if Settings().showPreview then
    ef:SetWidth(math.floor((width - 8) * Settings().split))
    self.splitter:ClearAllPoints()
    self.splitter:SetPoint("TOPLEFT", ef, "TOPRIGHT")
    self.splitter:SetPoint("BOTTOMLEFT", ef, "BOTTOMRIGHT")
    self.preview:ClearAllPoints()
    self.preview:SetPoint("TOPLEFT", self.splitter, "TOPRIGHT")
    self.preview:SetPoint("BOTTOMRIGHT")
    self.splitter:Show()
    self.preview:Show()
  else
    ef:SetPoint("BOTTOMRIGHT")
    self.splitter:Hide()
    self.preview:Hide()
  end
end

function E:SetSidebarShown(shown)
  Settings().showSidebar = shown
  self.sidebar:SetShown(shown)
  self.main:ClearAllPoints()
  if shown then
    self.main:SetPoint("TOPLEFT", self.sidebar, "TOPRIGHT", 0, 0)
  else
    self.main:SetPoint("TOPLEFT", self.titleBar, "BOTTOMLEFT", 0, -1)
  end
  self.main:SetPoint("BOTTOMRIGHT", self.status, "TOPRIGHT", 0, 1)
  self.sidebarToggle:SetActive(shown)
  if shown then self:RefreshList() end
end

function E:SetPreviewShown(shown)
  Settings().showPreview = shown
  self.previewToggle:SetActive(shown)
  self:LayoutContent()
  if shown then self:SchedulePreview(true) end
end

------------------------------------------------------------------------------------------------
-- The note list
------------------------------------------------------------------------------------------------

local function RowOnEnter(row)
  if row.note then
    row.pin:Show()
    local note = row.note
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(note.title, 1, 1, 1)
    local scope = note.scope == "character"
      and L["CharacterNoteOwner"]:format(Notes:CharacterLabel(note.owner or "?")) or L["AccountNote"]
    GameTooltip:AddLine(scope, 0.8, 0.8, 0.8)
    if note.modified then
      GameTooltip:AddLine(L["SavedAt"]:format(date("%Y-%m-%d %H:%M", note.modified)), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
  end
end

local function RowOnLeave(row)
  if not row:IsMouseOver() then row.pin:Hide() end
  GameTooltip:Hide()
end

function E:GetRow(i)
  local row = self.rows[i]
  if row then return row end
  row = CreateFrame("Button", nil, self.listChild)
  row:SetHeight(ROW_HEIGHT)
  row.selected = row:CreateTexture(nil, "BACKGROUND")
  row.selected:SetAllPoints()
  row.selected:SetColorTexture(unpack(W.colors.select))
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.05)
  row.arrow = row:CreateFontString(nil, "OVERLAY")
  row.arrow:SetFontObject(W.glyphFont)
  row.arrow:SetPoint("LEFT", 4, 0)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetJustifyH("LEFT")
  row.text:SetWordWrap(false)
  row.text:SetPoint("RIGHT", -22, 0)
  row.pin = W.GlyphButton(row, "↗", 18, function() ns.Viewer:Open(row.note.id) end,
    L["Pin"], L["RowPinTooltip"])
  row.pin:SetPoint("RIGHT", -1, 0)
  row.pin:Hide()
  row.pin:HookScript("OnLeave", function() if not row:IsMouseOver() then row.pin:Hide() end end)
  row:SetScript("OnEnter", RowOnEnter)
  row:SetScript("OnLeave", RowOnLeave)
  row:SetScript("OnClick", function(r)
    if r.note then
      E:RequestLoad(r.note.id)
    elseif r.key then
      local collapsed = Settings().collapsed
      collapsed[r.key] = not collapsed[r.key] or nil
      E:RefreshList()
    end
  end)
  self.rows[i] = row
  return row
end

function E:RefreshList()
  if not self.frame or not self.sidebar:IsShown() then return end
  local collapsed = Settings().collapsed
  local entries = {}
  local function add(entry) entries[#entries + 1] = entry end
  local filtering = self.filter and self.filter ~= ""

  for _, group in ipairs(Notes:Groups(self.filter)) do
    if group.children then
      local count = 0
      for _, sub in ipairs(group.children) do count = count + #sub.notes end
      if count > 0 then
        add({ key = group.key, label = group.label, count = count })
        if not collapsed[group.key] or filtering then
          for _, sub in ipairs(group.children) do
            local key = "owner:" .. sub.owner
            add({ key = key, label = Notes:CharacterLabel(sub.owner), count = #sub.notes, indent = 10 })
            if not collapsed[key] or filtering then
              for _, note in ipairs(sub.notes) do add({ note = note, indent = 22 }) end
            end
          end
        end
      end
    elseif #group.notes > 0 or not filtering then
      add({ key = group.key, label = group.label, count = #group.notes })
      if not collapsed[group.key] or filtering then
        for _, note in ipairs(group.notes) do add({ note = note, indent = 12 }) end
        if #group.notes == 0 then add({ empty = true, indent = 12 }) end
      end
    end
  end

  local y = 0
  for i, entry in ipairs(entries) do
    local row = self:GetRow(i)
    row.note, row.key = entry.note, entry.key
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", 0, -y)
    row.text:ClearAllPoints()
    row.text:SetPoint("RIGHT", -22, 0)
    if entry.note then
      local title = entry.note.title
      if entry.note.id == self.current.id and self.dirty then title = title .. " *" end
      row.text:SetPoint("LEFT", entry.indent, 0)
      row.text:SetFontObject("GameFontHighlightSmall")
      row.text:SetText(title)
      row.arrow:SetText("")
      row.selected:SetShown(entry.note.id == self.current.id)
      row:Enable()
    elseif entry.empty then
      row.text:SetPoint("LEFT", entry.indent, 0)
      row.text:SetFontObject("GameFontDisableSmall")
      row.text:SetText(L["NoNotesYet"])
      row.arrow:SetText("")
      row.selected:Hide()
      row:Disable()
    else
      local open = not collapsed[entry.key] or filtering
      row.arrow:ClearAllPoints()
      row.arrow:SetPoint("LEFT", (entry.indent or 0) + 2, 0)
      row.arrow:SetText(open and "▾" or "▸")
      row.arrow:SetTextColor(unpack(W.colors.muted))
      row.text:SetPoint("LEFT", (entry.indent or 0) + 16, 0)
      row.text:SetFontObject("GameFontNormalSmall")
      row.text:SetText(("%s  |cff808080%d|r"):format(entry.label, entry.count))
      row.selected:Hide()
      row:Enable()
    end
    row.pin:Hide()
    row:Show()
    y = y + ROW_HEIGHT
  end
  for i = #entries + 1, #self.rows do self.rows[i]:Hide() end
  self.listChild:SetHeight(math.max(y, 1))
end

------------------------------------------------------------------------------------------------
-- The note being edited
------------------------------------------------------------------------------------------------

-- E.current is the note in the editor: its id (nil until it's saved) and its scope. The title
-- and text are in the title box and the editor.
E.current = { scope = "account" }

function E:SavedState()
  local note = Notes:Get(self.current.id)
  if note then return note.title, note.text, note.scope end
  return Notes.CleanTitle(""), "", nil
end

function E:UpdateDirty()
  local title, text, scope = self:SavedState()
  local wasDirty = self.dirty
  self.dirty = Notes.CleanTitle(self.titleBox:GetText()) ~= title or self.editor:GetText() ~= text
    or (scope and scope ~= self.current.scope) or false
  if not self.current.id and self.editor:GetText() == "" and self.titleBox:GetText() == "" then self.dirty = false end
  -- every change puts the autosave off until there's been none for a moment
  self.autosaveDue = self.dirty and Settings().autosave and GetTime() + AUTOSAVE_DELAY or nil
  self:UpdateButtons()
  self:UpdateStatus()
  if wasDirty ~= self.dirty then self:RefreshList() end
end

function E:UpdateButtons()
  if not self.frame then return end
  self.saveButton:SetEnabled(self.dirty or not self.current.id)
  self.copyButton:SetEnabled(self.current.id ~= nil) -- a note never saved has nothing to copy
  self.copyButton:SetTooltip(L["SaveCopy"], Settings().autosave and L["SaveCopyAutosaveTooltip"] or L["SaveCopyTooltip"])
  local scope = self.current.scope
  local label
  if scope == "character" then
    local note = Notes:Get(self.current.id)
    local owner = note and note.scope == "character" and note.owner or ns.playerKey
    label = L["CharacterScope"]:format(owner == ns.playerKey and ns.playerName or owner)
  else
    label = L["Account"]
  end
  self.scopeButton:SetLabel(label)
  self.scopeButton:SetWidth(math.max(110, math.ceil(self.scopeButton.label:GetStringWidth()) + 20))
  self.scopeButton:SetTooltip(L["ScopeTooltipTitle"], scope == "character"
    and L["ScopeTooltipCharacter"]
    or L["ScopeTooltipAccount"])
  local pinned = self.current.id and ns.Viewer:IsOpen(self.current.id)
  self.pinButton:SetLabel(pinned and L["Unpin"] or L["Pin"])
  self.pinButton:SetTooltip(pinned and L["Unpin"] or L["Pin"],
    pinned and L["UnpinTooltip"]
    or L["PinTooltip"])
end

function E:UpdateStatus()
  if not self.frame then return end
  local state
  if self.restored then
    state = "|cffffd100" .. L["StatusRestored"] .. "|r"
  elseif self.dirty then
    state = "|cffffd100" .. L["StatusUnsaved"] .. "|r"
  elseif not self.current.id then
    state = L["StatusNewNote"]
  else
    state = L["StatusSaved"]
  end
  local text = self.editor:GetText()
  local _, chars = text:gsub("[^\128-\191]", "")
  self.statusText:SetText(L["StatusLine"]:format(state, self.cursorLine or 1, self.cursorColumn or 1, chars))
end

-- Puts a note in the editor (or an empty new note, for nil). Use RequestLoad to ask about
-- unsaved changes first.
function E:LoadNote(id, draft)
  local note = Notes:Get(id)
  self.current = { id = note and note.id, scope = note and note.scope or Settings().newNoteScope }
  self.titleBox:SetText(note and note.title or "")
  self.titleBox:SetCursorPosition(0)
  self.editor:SetText(note and note.text or "")
  if draft then
    self.titleBox:SetText(draft.title or "")
    self.current.scope = draft.scope or self.current.scope
    self.editor:SetText(draft.text or "")
  end
  Settings().lastNote = self.current.id
  self.restored = draft and true or nil
  self:UpdateDirty()
  self:RefreshList()
  self:SchedulePreview(true)
end

-- does continue() once there are no unsaved changes to lose: saved by autosave, or saved or
-- thrown away, as the player chooses
function E:RequestLeave(continue)
  self:Autosave()
  if not self.dirty then return continue() end
  local title = Notes.CleanTitle(self.titleBox:GetText())
  StaticPopup_Show("MARKDOWNNOTEPAD_UNSAVED", ns.Markup.Escape(title), nil, { continue = continue })
end

function E:RequestLoad(id)
  if id and id == self.current.id then return end
  self:RequestLeave(function() E:LoadNote(id) end)
end

function E:NewNote()
  self:RequestLeave(function()
    E:LoadNote(nil)
    E.titleBox:SetFocus()
  end)
end

-- auto: an autosave, which leaves the title box as it's typed. Putting the cleaned title back
-- would take away a space typed before the next word, or fill an empty box with "Untitled".
function E:Save(auto)
  local title, text, scope = self.titleBox:GetText(), self.editor:GetText(), self.current.scope
  local note
  if self.current.id and Notes:Get(self.current.id) then
    note = Notes:Save(self.current.id, title, text, scope)
  else
    note = Notes:Create(title, text, scope)
    self.current.id = note.id
  end
  self.current.scope = note.scope
  if not auto then self.titleBox:SetText(note.title) end
  Settings().lastNote = note.id
  self.restored = nil
  self:UpdateDirty()
  self:RefreshList()
end

-- With autosave on, saves the changes now: when it's due, a moment after the last one, or
-- before they'd be lost.
function E:Autosave()
  self.autosaveDue = nil
  if self.dirty and Settings().autosave then self:Save(true) end
end

-- Saves what's in the editor as a new note, in the same scope, and edits that one. The note it
-- came from keeps what it had at its last save; with autosave on, that's everything typed.
function E:SaveCopy()
  if not (self.current.id and Notes:Get(self.current.id)) then return end
  self:Autosave()
  local title = Notes:CopyTitle(self.titleBox:GetText())
  local note = Notes:Create(title, self.editor:GetText(), self.current.scope)
  self:LoadNote(note.id)
  -- ready to be renamed
  self.titleBox:SetFocus()
  self.titleBox:HighlightText()
end

function E:ToggleScope()
  self.current.scope = self.current.scope == "character" and "account" or "character"
  self:UpdateDirty()
end

function E:ConfirmDelete()
  local note = Notes:Get(self.current.id)
  if not note then
    -- a note that was never saved: just clear it
    self:LoadNote(nil)
    return
  end
  StaticPopup_Show("MARKDOWNNOTEPAD_DELETE", ns.Markup.Escape(note.title), nil, { id = note.id })
end

function E:DeleteNote(id)
  Notes:Delete(id)
end

function E:TogglePin()
  if self.current.id and ns.Viewer:IsOpen(self.current.id) then
    ns.Viewer:Close(self.current.id)
    return
  end
  if self.dirty or not self.current.id then self:Save() end
  ns.Viewer:Open(self.current.id)
end

-- on opening the window the first time: the unsaved changes kept at the last logout, the note
-- that was open then, or the latest note
function E:OpenFirstNote()
  local draft = ns.db.draft
  ns.db.draft = nil
  if draft and (draft.text ~= "" or draft.title ~= "") then
    self:LoadNote(draft.id and Notes:Get(draft.id) and draft.id or nil, draft)
    return
  end
  local id = Settings().lastNote
  if not Notes:Get(id) then
    id = nil
    local latest
    for _, note in pairs(ns.db.notes) do
      if (note.scope ~= "character" or note.owner == ns.playerKey) and (not latest or note.modified > latest.modified) then
        latest = note
      end
    end
    id = latest and latest.id
  end
  self:LoadNote(id)
end

-- at a logout or /reload, autosave saves the changes; without it, they're kept, and come back
-- when the editor opens
ns:On("LOGOUT", function()
  if not E.frame then return end
  E:Autosave()
  if E.dirty then
    ns.db.draft = {
      id = E.current.id, scope = E.current.scope, title = E.titleBox:GetText(), text = E.editor:GetText(),
    }
  else
    ns.db.draft = nil
  end
end)

------------------------------------------------------------------------------------------------
-- The preview
------------------------------------------------------------------------------------------------

function E:SchedulePreview(now)
  self.previewDue = now and 0 or (GetTime() + PREVIEW_DELAY)
end

function E:OnUpdate()
  self:CheckLayout()
  if self.autosaveDue and GetTime() >= self.autosaveDue then self:Autosave() end
  if self.previewDue and GetTime() >= self.previewDue and Settings().showPreview then
    self.previewDue = nil
    R:SetMarkdown(self.previewHTML, self.editor:GetText())
  end
end

------------------------------------------------------------------------------------------------
-- Popups: icons, more, settings
------------------------------------------------------------------------------------------------

function E:ToggleIconPopup(owner)
  local p = self.iconPopup
  if not p then
    p = W.Popup()
    self.iconPopup = p
    local icons = {}
    for i = 1, 8 do icons[#icons + 1] = { code = "{rt" .. i .. "}", texture = ns.LSHM and ns.LSHM.config["rt" .. i] } end
    for _, code in ipairs(SHORTCODES) do
      icons[#icons + 1] = { code = code, texture = ns.LSHM and ns.LSHM.config[code] }
    end
    local size, perRow = 26, 9
    for i, icon in ipairs(icons) do
      local b = W.Button(p, icon.texture or icon.code, function()
        p:Hide()
        E.editor:Apply(A.Insert, icon.code)
      end, { width = size, height = size, font = "GameFontHighlightLarge", tooltip = icon.code })
      local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
      b:SetPoint("TOPLEFT", 6 + col * (size + 3), -6 - row * (size + 3))
    end
    local rows = math.ceil(#icons / perRow)
    p:SetSize(12 + perRow * (size + 3) - 3, 12 + rows * (size + 3) - 3)
  end
  p:Toggle(owner)
end

function E:ToggleMorePopup(owner)
  local p = self.morePopup
  if not p then
    p = W.Popup()
    self.morePopup = p
    local y = -6
    for _, item in ipairs(MORE) do
      if item then
        local b = W.Button(p, item[1], function()
          p:Hide()
          item[2](E.editor)
        end, { width = 168, height = 20 })
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", 8, 0)
        b:SetPoint("TOPLEFT", 6, y)
        y = y - 22
      else
        y = y - 6
      end
    end
    p:SetSize(180, -y + 4)
  end
  p:Toggle(owner)
end

function E:ApplySettings()
  local settings = Settings()
  self.editor:SetFontSize(settings.editorFontSize)
  self.editor:SetLineNumbers(settings.lineNumbers)
  self.editor:SetHighlight(settings.highlight)
end

function E:ToggleSettings(owner)
  local p = self.settingsPopup
  if not p then
    p = W.Popup()
    self.settingsPopup = p
    local settings = Settings()
    local controls = {}
    local y = -10
    local function heading(text)
      local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetPoint("TOPLEFT", 12, y)
      fs:SetText(text)
      y = y - 18
    end
    local function place(control, height)
      control:SetPoint("TOPLEFT", 12, y)
      controls[#controls + 1] = control
      y = y - height
    end
    local percent = function(v) return math.floor(v * 100 + 0.5) .. "%" end

    heading(L["SettingsEditor"])
    place(W.Slider(p, L["SettingsTextSize"], 9, 24, 1, function() return settings.editorFontSize end, function(v)
      settings.editorFontSize = v
      E.editor:SetFontSize(v)
    end, nil, 236), 38)
    place(W.Check(p, L["SettingsSyntaxColoring"], function() return settings.highlight end, function(v)
      settings.highlight = v
      E.editor:SetHighlight(v)
    end), 22)
    place(W.Check(p, L["SettingsLineNumbers"], function() return settings.lineNumbers end, function(v)
      settings.lineNumbers = v
      E.editor:SetLineNumbers(v)
    end), 22)
    place(W.Check(p, L["SettingsAutosave"], function() return settings.autosave end, function(v)
      settings.autosave = v
      E:UpdateDirty() -- on: the changes so far are saved a moment later
    end, L["SettingsAutosaveTooltip"]), 22)
    place(W.Check(p, L["SettingsNewNotesCharacter"], function() return settings.newNoteScope == "character" end,
      function(v) settings.newNoteScope = v and "character" or "account" end), 30)

    heading(L["SettingsPreview"])
    place(W.Slider(p, L["SettingsTextSize"], 10, 24, 1, function() return settings.renderFontSize end, function(v)
      settings.renderFontSize = v
      R:UpdateFonts()
    end, nil, 236), 38)
    place(W.Check(p, L["SettingsKeepLineBreaks"], function() return settings.keepLineBreaks end, function(v)
      settings.keepLineBreaks = v
      R:RenderAll()
    end, L["SettingsKeepLineBreaksTooltip"]), 30)

    heading(L["SettingsNewlyPinned"])
    local viewer = settings.viewer
    place(W.Slider(p, L["BackgroundOpacity"], 0, 1, 0.05, function() return viewer.bgAlpha end,
      function(v) viewer.bgAlpha = v end, percent, 236), 38)
    place(W.Check(p, L["SettingsFadeThem"], function() return viewer.fade end,
      function(v) viewer.fade = v end), 26)
    place(W.Slider(p, L["FadedOpacity"], 0, 1, 0.05, function() return viewer.fadeAlpha end,
      function(v) viewer.fadeAlpha = v end, percent, 236), 38)

    p:SetSize(260, -y + 4)
    function p:Refresh()
      for _, control in ipairs(controls) do control:Refresh() end
    end
  end
  p:Toggle(owner, "BOTTOMRIGHT", "TOPRIGHT", 0, 4)
end

------------------------------------------------------------------------------------------------

function E:Show()
  if not self.frame then self:Create() end
  self.frame:Show()
  self:LayoutToolbar()
end

function E:Hide()
  if self.frame then self.frame:Hide() end
end

function E:Toggle()
  if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end

function E:ResetPosition()
  Settings().editor = {}
  if self.frame then W.RestorePosition(self.frame, Settings().editor, 1000, 620) end
end
