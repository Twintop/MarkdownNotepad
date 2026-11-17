-- The whole AddOn, loaded as the game loads it, driven through its windows: the editor, its
-- toolbar and popups, saving, scopes, pinned notes, links, and slash commands. The saved
-- variables it ends with are handed to test_reload.lua, as a /reload would.

local eq, ok = T.eq, T.ok
local Notes, E, V, M = ns.Notes, ns.Editor, ns.Viewer, ns.Markup

local function click(button) MOCK.FireScript(button, "OnClick", "LeftButton") end

-- the buttons in a frame, by their label
local function buttons(parent)
  local out = {}
  for _, w in ipairs(MOCK.widgets) do
    if w._kind == "Button" and w._parent == parent and w.label then out[w.label:GetText()] = w end
  end
  return out
end

local function children(parent, kind)
  local out = {}
  for _, w in ipairs(MOCK.widgets) do
    if w._parent == parent and (not kind or w._kind == kind) then out[#out + 1] = w end
  end
  return out
end

local function ctrl(key, target)
  MOCK.keys.ctrl = true
  MOCK.FireScript(target or E.editor.editBox, "OnKeyDown", key)
  MOCK.keys.ctrl = false
end

local function selection(ed)
  local eb = ed.editBox
  local s, e = eb._hs, eb._he
  if not s then return "" end
  return ed:GetText():sub(M.ToPlain(ed.display, s) + 1, M.ToPlain(ed.display, e, true))
end

T.test("loading and logging in", function()
  ok(ns.LSHM and ns.LSHM.minor >= 5, "the library embedded in Libs loaded (hard_breaks is minor 5)")
  MOCK.Fire("ADDON_LOADED", "MarkdownNotepad")
  MOCK.Fire("PLAYER_LOGIN")
  ok(ns.db and ns.charDB, "the saved variables are set up")
  eq(ns.playerKey, "Tester-TestRealm")
  local welcome = Notes:FindByTitle("Welcome to Markdown Notepad")
  ok(welcome, "the welcome note is made")
  eq(welcome.scope, "account")
  if ns.LSHM then ok(M.shortcodes[":check:"], "the library's shortcodes are known") end

  eq(ns.fullVersion, TOC_METADATA.Version .. "-" .. TOC_METADATA["X-ReleaseType"], "the version, with its release type")
  ok(not MarkdownNotepadNews, "the news waits out the login sequence")
  MOCK.Tick(0)
  MOCK.Tick(1.1)
  ok(MarkdownNotepadNews and MarkdownNotepadNews:IsShown(), "then shows what's new in a version not seen yet")
  eq(ns.db.news.lastUpdate, ns.fullVersion, "and marks it seen")
  ns.News:Hide()
end)

T.test("the editor opens on the welcome note", function()
  SlashCmdList.MARKDOWNNOTEPAD("")
  ok(E.frame:IsShown(), "it's shown")
  MOCK.FireAll("OnSizeChanged", 500, 400)
  MOCK.Tick(0.5)
  eq(E.titleBox:GetText(), "Welcome to Markdown Notepad")
  ok(E.editor:GetText():find("# Welcome", 1, true), "its text is in the editor")
  ok(not E.dirty, "nothing to save")
  ok(E.editor.gutter:GetText():find("^1\n2\n"), "the lines are numbered")
  -- (SimpleHTML has no GetText; the mock keeps what was set)
  if ns.LSHM then ok(E.previewHTML._text:find("<h1>", 1, true), "the preview is rendered") end
  ok(E.rows[1] and E.rows[1]:IsShown(), "the note list is filled")
  SlashCmdList.MARKDOWNNOTEPAD("")
  ok(not E.frame:IsShown(), "/mdn hides it again")
  ns:ToggleEditor()
  ok(E.frame:IsShown(), "and the key binding shows it")
  eq(ns.settings.autosave, true, "autosave is on at first")
  -- the tests up to "autosave" save by hand
  ns.settings.autosave = false
end)

T.test("writing and saving a note", function()
  E:NewNote()
  eq(E.editor:GetText(), "")
  E.titleBox:SetText("Raid Plan")
  MOCK.FireScript(E.titleBox, "OnTextChanged", true)
  ok(E.dirty, "a title is a change")
  local eb = E.editor.editBox
  eb:SetFocus()
  MOCK.Type(eb, "# Raid\n- tank: |cff check\nheal")
  MOCK.Tick(0.5)
  ok(E.dirty, "typing is a change")
  ok(E.statusText:GetText():find("Unsaved", 1, true), "the status says so")
  ctrl("S")
  ok(not E.dirty, "Ctrl-S saves")
  local note = Notes:FindByTitle("Raid Plan")
  ok(note, "the note is saved")
  eq(note.text, "# Raid\n- tank: |cff check\n- heal")
  eq(E.current.id, note.id)
end)

T.test("every toolbar button", function()
  local ed = E.editor
  local eb = ed.editBox
  for _, item in ipairs(E.toolItems) do
    if item.button then
      ed:SetText("one two three\nfour")
      eb:SetFocus()
      eb:SetCursorPosition(4)
      eb:HighlightText(4, 7)
      click(item.button)
      local label = item.button.label:GetText()
      if label == "Icons ▾" then
        ok(E.iconPopup:IsShown(), "the icons popup opens")
        local icons = children(E.iconPopup, "Button")
        ok(#icons >= 18, "with the raid icons and shortcodes")
        click(icons[1])
        ok(ed:GetText():find("{rt1}", 1, true), "an icon inserts its code")
        ok(not E.iconPopup:IsShown(), "and closes the popup")
      elseif label == "More ▾" then
        ok(E.morePopup:IsShown(), "the more popup opens")
        for i, b in ipairs(children(E.morePopup, "Button")) do
          ed:SetText("word")
          eb:SetCursorPosition(4)
          if not E.morePopup:IsShown() then click(item.button) end
          click(b)
          ok(ed:GetText() ~= "word", "more item " .. i .. " changes the text")
        end
      else
        ok(ed:GetText() ~= "one two three\nfour", label .. " changes the text")
      end
    end
  end
  -- the image button selects the texture path to change
  local img
  for _, item in ipairs(E.toolItems) do
    if item.button and item.button.label:GetText() == "Img" then img = item.button end
  end
  ed:SetText("")
  eb:SetCursorPosition(0)
  click(img)
  eq(selection(ed), "Interface\\\\Icons\\\\INV_Misc_QuestionMark")
  -- bold, with its shortcut
  ed:SetText("make this bold")
  eb:SetCursorPosition(10)
  eb:HighlightText(10, 14)
  ctrl("B")
  eq(ed:GetText(), "make this **bold**")
  eq(selection(ed), "bold")
  ctrl("Z")
  eq(ed:GetText(), "make this bold", "Ctrl-Z")
  ctrl("Y")
  eq(ed:GetText(), "make this **bold**", "Ctrl-Y")
  E:LayoutToolbar()
end)

T.test("unsaved changes are asked about", function()
  local raid = Notes:FindByTitle("Raid Plan")
  local welcome = Notes:FindByTitle("Welcome to Markdown Notepad")
  E:LoadNote(raid.id)
  local eb = E.editor.editBox
  eb:SetFocus()
  eb:SetCursorPosition(#E.editor.display)
  MOCK.Type(eb, " more")
  ok(E.dirty)
  E:RequestLoad(welcome.id)
  ok(MOCK.popup and MOCK.popup.which == "MARKDOWNNOTEPAD_UNSAVED", "it asks")
  eq(MOCK.popup.text_arg1, "Raid Plan")
  MOCK.ClickPopup(3)
  eq(E.current.id, welcome.id, "Don't Save opens the other note")
  eq(raid.text, "# Raid\n- tank: |cff check\n- heal", "and leaves the first as it was")

  E:LoadNote(raid.id)
  eb:SetCursorPosition(#E.editor.display)
  MOCK.Type(eb, " more")
  E:RequestLoad(welcome.id)
  MOCK.ClickPopup(1)
  eq(raid.text, "# Raid\n- tank: |cff check\n- heal more", "Save saves it first")
  eq(E.current.id, welcome.id)

  E:LoadNote(raid.id)
  eb:SetCursorPosition(#E.editor.display)
  MOCK.Type(eb, "x")
  E:RequestLoad(welcome.id)
  MOCK.ClickPopup(2)
  eq(E.current.id, raid.id, "Cancel stays")
  E:Save()
end)

T.test("account and character notes", function()
  E:NewNote()
  E.titleBox:SetText("Mage things")
  E:ToggleScope()
  ok(E.scopeButton.label:GetText():find("Tester", 1, true), "the scope button names the character")
  E:Save()
  local mine = Notes:FindByTitle("Mage things")
  eq(mine.scope, "character")
  eq(mine.owner, "Tester-TestRealm")
  local alt = Notes:Create("Alt note", "x", "character")
  alt.owner = "Alt-TestRealm"
  local groups = Notes:Groups()
  eq(groups[1].key, "account")
  eq(groups[2].notes[1].title, "Mage things")
  eq(groups[3].children[1].owner, "Alt-TestRealm")
  eq(Notes:FindByTitle("alt NOTE").id, alt.id, "titles are found ignoring case")
  E:RefreshList()
  -- expand Other characters, then filter
  for _, row in ipairs(E.rows) do
    if row:IsShown() and row.key == "others" then click(row) end
  end
  local found
  for _, row in ipairs(E.rows) do
    if row:IsShown() and row.note == alt then found = true end
  end
  ok(found, "another character's notes are listed")
  E.filter = "mage"
  E:RefreshList()
  local shown = 0
  for _, row in ipairs(E.rows) do if row:IsShown() and row.note then shown = shown + 1 end end
  eq(shown, 1, "the search filters the list")
  E.filter = nil
  E:RefreshList()
  E:ToggleScope()
  E:Save()
  eq(mine.scope, "account")
  eq(mine.owner, nil)
end)

T.test("saving a copy", function()
  local original = Notes:FindByTitle("Mage things")
  local savedText = original.text
  E:LoadNote(original.id)
  local copyButton = buttons(E.header)["Save Copy"]
  ok(copyButton:IsEnabled(), "a saved note can be copied")
  local eb = E.editor.editBox
  eb:SetFocus()
  eb:SetCursorPosition(#E.editor.display)
  MOCK.Type(eb, "only in the copy")
  ok(E.dirty)
  click(copyButton)

  local copy = Notes:FindByTitle("Mage things (copy)")
  ok(copy, "the copy is saved")
  eq(copy.text, savedText .. "only in the copy", "with the changes that weren't saved")
  eq(original.text, savedText, "the original keeps what it had at its last save")
  eq(copy.scope, original.scope, "in the same scope")
  eq(E.current.id, copy.id, "the editor moves to the copy")
  ok(not E.dirty, "which has nothing left to save")
  ok(E.titleBox:HasFocus() and E.titleBox._hs == 0, "its title is selected, to rename it")

  -- copying a copy counts on from the same title
  MOCK.keys.shift = true
  ctrl("S")
  MOCK.keys.shift = false
  local second = Notes:FindByTitle("Mage things (copy 2)")
  ok(second, "Ctrl-Shift-S saves another copy, numbered")
  eq(E.current.id, second.id)
  eq(Notes:CopyTitle("Mage things (copy 2)"), "Mage things (copy 3)")
  -- and Ctrl-Shift-S works in the title box too
  MOCK.keys.shift = true
  ctrl("S", E.titleBox)
  MOCK.keys.shift = false
  ok(Notes:FindByTitle("Mage things (copy 3)"), "from the title box too")

  E:NewNote()
  ok(not copyButton:IsEnabled(), "a note that was never saved can't be copied")
  for _, title in ipairs({ "Mage things (copy)", "Mage things (copy 2)", "Mage things (copy 3)" }) do
    Notes:Delete(Notes:FindByTitle(title).id)
  end
end)

T.test("pinning a note", function()
  local raid = Notes:FindByTitle("Raid Plan")
  E:LoadNote(raid.id)
  click(E.pinButton)
  ok(V:IsOpen(raid.id), "Pin opens it")
  eq(E.pinButton.label:GetText(), "Unpin")
  eq(ns.charDB.viewers[raid.id].open, true, "and it's remembered")
  local f = V:Open(raid.id)
  MOCK.FireAll("OnSizeChanged", 300, 200)
  MOCK.Tick()
  if ns.LSHM then ok(f.html._text:find("<h1>", 1, true), "it shows the note") end

  -- unlocked, it's a window like any other
  ok(f.bar:IsShown(), "unlocked, its title bar shows without the mouse over it")
  ok(f.grip:IsShown(), "and so does its size grip")
  eq(f:IsMouseEnabled(), true, "it takes the mouse")
  eq(select(5, f.scroll:GetPoint(1)), -28, "and the note starts below the bar")
  MOCK.mouseOver = f
  MOCK.Tick()
  ok(f.bar:IsShown() and not f.hint:IsShown(), "the mouse over it changes nothing")

  -- the padlock locks it: clicks go through it, until Alt is held over it
  local lock = f.lockButton
  ok(not lock.active and lock.icon._desat, "a gray padlock while it's unlocked")
  click(lock)
  eq(f.state.locked, true, "the padlock locks it")
  ok(lock.active and not lock.icon._desat, "and turns gold")
  eq(lock.tipTitle, "Unlock")
  MOCK.Tick()
  ok(not f.bar:IsShown(), "locked, the title bar goes")
  ok(not f.grip:IsShown(), "and the size grip")
  eq(f:IsMouseEnabled(), false, "and clicks go through it")
  ok(f.scroll:IsMouseWheelEnabled(), "but the mouse wheel still scrolls it")
  eq(select(5, f.scroll:GetPoint(1)), -8, "and the note has the bar's space")
  -- it doesn't take the mouse, so the mock doesn't count it as under the mouse (the worst the
  -- game might do); it's found under the cursor by position
  MOCK.mouseOver = nil
  MOCK.cursorPos = { 100, 100 }
  MOCK.Tick()
  ok(f.hint:IsShown(), "with the cursor over it, it says to hold Alt")
  MOCK.keys.alt = true
  MOCK.Tick()
  ok(f.bar:IsShown(), "holding Alt shows the title bar")
  eq(f:IsMouseEnabled(), true, "and the window takes the mouse")
  ok(not f.hint:IsShown(), "without the hint")
  click(lock)
  eq(f.state.locked, nil, "so its padlock can unlock it")
  MOCK.keys.alt = false
  MOCK.Tick()
  ok(f.bar:IsShown(), "unlocked again, the bar stays without Alt")
  eq(f:IsMouseEnabled(), true)
  MOCK.cursorPos = nil
  MOCK.mouseOver = f

  -- its settings
  local b = buttons(f.bar)
  click(b["≡"])
  ok(V.settingsPopup:IsShown(), "the settings open")
  local sliders = {}
  for _, w in ipairs(MOCK.widgets) do
    if w._kind == "Slider" and w._parent and w._parent._parent == V.settingsPopup then sliders[#sliders + 1] = w end
  end
  sliders[1]:SetValue(0.2)
  eq(f.state.bgAlpha, 0.2, "the background opacity slider")
  local checks = children(V.settingsPopup, "Button")
  eq(#checks, 2, "fade, and lock in place")
  for _, check in ipairs(checks) do click(check) end
  eq(f.state.fade, true)
  eq(f.state.locked, true, "the check box locks it too")
  ok(lock.active, "and the padlock agrees")
  V.settingsPopup:Hide()
  MOCK.mouseOver = nil
  for _ = 1, 40 do MOCK.Tick(0.05) end
  ok(f:GetAlpha() < 0.35, "it fades when the mouse leaves")
  MOCK.cursorPos = { 100, 100 }
  for _ = 1, 40 do MOCK.Tick(0.05) end
  ok(f:GetAlpha() > 0.95, "and comes back with the cursor over it, though it's locked")
  MOCK.cursorPos = nil

  -- the ways back that don't need the window under the mouse
  MOCK.FireScript(E.pinButton, "OnClick", "RightButton")
  ok(V.settingsPopup:IsShown() and V.settingsPopup.viewer == f, "right-clicking Unpin opens the window's settings")
  ok(V:IsOpen(raid.id), "without unpinning it")
  V.settingsPopup:Hide()
  SlashCmdList.MARKDOWNNOTEPAD("unlock")
  eq(f.state.locked, nil, "/mdn unlock unlocks it")
  MOCK.Tick()
  eq(f:IsMouseEnabled(), true, "so it takes the mouse again")
  ok(f.bar:IsShown(), "with its title bar")

  -- saving the note shows the new text
  E.editor:SetText("# Changed")
  E:Save()
  eq(f.text, "# Changed", "the pinned note shows the saved text")

  click(b["Edit"])
  eq(E.current.id, raid.id, "Edit opens it in the editor")
  click(b["×"])
  ok(not V:IsOpen(raid.id), "× unpins it")
  eq(ns.charDB.viewers[raid.id].open, nil)
  eq(E.pinButton.label:GetText(), "Pin")
end)

T.test("a window saved as click-through comes back locked", function()
  local welcome = Notes:FindByTitle("Welcome to Markdown Notepad")
  ns.charDB.viewers[welcome.id] = { clickThrough = true }
  local f = V:Open(welcome.id)
  eq(f.state.locked, true)
  eq(f.state.clickThrough, nil)
  V:Close(welcome.id)
  ns.charDB.viewers[welcome.id] = nil
end)

T.test("links", function()
  local html = E.previewHTML
  ns.Render.OnHyperlinkClick(html, "note:Raid Plan", "Raid Plan")
  ok(V:IsOpen(Notes:FindByTitle("Raid Plan").id), "a note: link pins that note")
  ns.Render.OnHyperlinkClick(html, "note:No Such Note", "x")
  ok(MOCK.printed[#MOCK.printed]:find("No note is titled", 1, true), "an unknown note says so")
  ns.Render.OnHyperlinkClick(html, "https://example.org", "Example")
  eq(MOCK.popup.which, "MARKDOWNNOTEPAD_URL")
  eq(MOCK.popup.editBox:GetText(), "https://example.org", "the url is shown to copy")
  ns.Render.OnHyperlinkEnter(html, "spell:133")
  ns.Render.OnHyperlinkEnter(html, "note:Raid Plan")
  ns.Render.OnHyperlinkEnter(html, "note:Nope")
  ns.Render.OnHyperlinkLeave()
  V:CloseAll()

  -- shift-clicking a spell while typing links it
  local ed = E.editor
  ed:SetText("Cast ")
  ed.editBox:SetFocus()
  ed.editBox:SetCursorPosition(5)
  ChatFrameUtil.InsertLink("|cff71d5ff|Hspell:133:0|h[Fireball]|h|r")
  eq(ed:GetText(), "Cast [Fireball](spell:133)")
  -- and dropping an item on the editor does too
  MOCK.cursorInfo = { "item", 6948, "|cffffffff|Hitem:6948::::|h[Hearthstone]|h|r" }
  ed:OnReceiveDrag()
  eq(ed:GetText(), "Cast [Fireball](spell:133)[Hearthstone](item:6948)")
  eq(MOCK.cursorInfo, nil, "the cursor is cleared")
end)

T.test("settings", function()
  E:ToggleSettings(E.sidebarToggle)
  local p = E.settingsPopup
  ok(p:IsShown())
  for _, check in ipairs(children(p, "Button")) do click(check) end
  eq(ns.settings.highlight, false, "coloring off")
  eq(ns.settings.lineNumbers, false, "line numbers off")
  eq(ns.settings.newNoteScope, "character")
  eq(ns.settings.keepLineBreaks, false, "line breaks as in Markdown")
  eq(ns.settings.autosave, true, "autosave on")
  eq(E.editor.display, M.Escape(E.editor:GetText()), "uncolored, the display is only escaped")
  ok(not E.editor.gutter:IsShown(), "no line numbers")
  for _, check in ipairs(children(p, "Button")) do click(check) end
  eq(ns.settings.highlight, true)
  eq(ns.settings.keepLineBreaks, true)
  eq(ns.settings.autosave, false)
  for _, w in ipairs(MOCK.widgets) do
    if w._kind == "Slider" and w._parent and w._parent._parent == p then w:SetValue(16) end
  end
  eq(ns.settings.editorFontSize, 16)
  eq(ns.settings.renderFontSize, 16)
  p:Hide()
  E:SetPreviewShown(false)
  E:SetPreviewShown(true)
  E:SetSidebarShown(false)
  E:SetSidebarShown(true)
  ns.settings.newNoteScope = "account"
end)

T.test("notes keep their line breaks", function()
  local R, html = ns.Render, E.previewHTML
  R:SetMarkdown(html, "Step 1 is Westfall.\nStep 2 is the Barrens.\n\nAt 3c/3d, jump.")
  ok(html._text:find("Westfall.<br/>Step 2", 1, true), "each line on its own line")
  ok(html._text:find("Barrens.</p><br />", 1, true), "and an empty line after the paragraph")
  ns.settings.keepLineBreaks = false
  R:RenderAll()
  ok(not html._text:find("<br", 1, true), "with the setting off, lines join as in Markdown")
  ns.settings.keepLineBreaks = true
  R:RenderAll()
  ok(html._text:find("Westfall.<br/>Step 2", 1, true), "and on again")
  -- the news is written in Markdown, so its lines join
  local news = CreateFrame("SimpleHTML")
  R:Setup(news)
  R:SetMarkdown(news, "one\ntwo")
  ok(not news._text:find("<br", 1, true), "a frame that isn't a note's joins them")
end)

T.test("the footer and the news", function()
  local footer = buttons(E.footer)
  local function url(label)
    click(footer[label])
    eq(MOCK.popup and MOCK.popup.which, "MARKDOWNNOTEPAD_URL", label .. " shows a link to copy")
    return MOCK.popup.editBox:GetText()
  end
  eq(url("Discord"), "https://discord.gg/eThqxM78xm")
  eq(url("Donate on Ko-fi"), "https://ko-fi.com/twintop")
  ok(url("GitHub Issues"):find("^https://github%.com/.+/issues/$"), "GitHub Issues links to the issues")

  local version
  for _, fs in ipairs(children(E.footer, "FontString")) do
    if fs:GetText() == ns.fullVersion then version = fs end
  end
  ok(version, "the footer shows the version")

  click(footer["News"])
  local news = MarkdownNotepadNews
  ok(news:IsShown(), "News opens the news")
  if ns.LSHM then ok(news.html._text:find(ns.fullVersion, 1, true), "with what's new in this version") end
  local showAgain = children(news, "Button")
  local check
  for _, b in ipairs(showAgain) do if b.text and b.text:GetText() == "Show on new version release" then check = b end end
  click(check)
  eq(ns.db.news.enabled, false, "its check box stops it opening for new versions")
  click(check)
  eq(ns.db.news.enabled, true)
  MOCK.FireScript(news.html, "OnHyperlinkClick", "#12", "#12")
  ok(MOCK.popup.editBox:GetText():find("/issues/12$"), "#12 in the news links to that issue")
  click(footer["News"])
  ok(not news:IsShown(), "News closes it again")
  SlashCmdList.MARKDOWNNOTEPAD("news")
  ok(news:IsShown(), "/mdn news opens it")
  ns.News:Hide()
end)

T.test("slash commands", function()
  local before = #MOCK.printed
  SlashCmdList.MARKDOWNNOTEPAD("list")
  ok(#MOCK.printed > before, "list prints the notes")
  SlashCmdList.MARKDOWNNOTEPAD("show raid plan")
  ok(V:IsOpen(Notes:FindByTitle("Raid Plan").id), "show pins a note")
  SlashCmdList.MARKDOWNNOTEPAD("hide")
  ok(not V:IsOpen(Notes:FindByTitle("Raid Plan").id), "hide unpins them all")
  SlashCmdList.MARKDOWNNOTEPAD("edit Mage things")
  eq(E.titleBox:GetText(), "Mage things")
  SlashCmdList.MARKDOWNNOTEPAD("show nothing by this name")
  SlashCmdList.MARKDOWNNOTEPAD("reset")
  SlashCmdList.MARKDOWNNOTEPAD("help")
  SlashCmdList.MARKDOWNNOTEPAD("new")
  eq(E.current.id, nil)
  MarkdownNotepad_OnAddonCompartmentEnter(nil, UIParent)
  MarkdownNotepad_OnAddonCompartmentLeave()
  MarkdownNotepad_OnAddonCompartmentClick()
  ok(not E.frame:IsShown(), "the compartment toggles the editor")
  MarkdownNotepad_OnAddonCompartmentClick()
end)

T.test("deleting a note", function()
  local raid = Notes:FindByTitle("Raid Plan")
  V:Open(raid.id)
  E:LoadNote(raid.id)
  click(buttons(E.header)["Delete"])
  eq(MOCK.popup.which, "MARKDOWNNOTEPAD_DELETE")
  MOCK.ClickPopup(1)
  eq(Notes:Get(raid.id), nil, "the note is gone")
  ok(not V:IsOpen(raid.id), "its window is closed")
  eq(ns.charDB.viewers[raid.id], nil, "and forgotten")
  eq(E.current.id, nil, "the editor moves to a new note")
end)

T.test("autosave", function()
  local mage = Notes:FindByTitle("Mage things")
  local before = mage.text
  E:LoadNote(mage.id)
  local eb = E.editor.editBox
  eb:SetFocus()
  eb:SetCursorPosition(#E.editor.display)
  MOCK.Type(eb, " one")
  MOCK.Tick(2.5)
  ok(E.dirty, "off, nothing is saved by itself")

  -- turned on in the settings: the changes so far are saved a moment later
  E:ToggleSettings(E.sidebarToggle)
  for _, check in ipairs(children(E.settingsPopup, "Button")) do
    if check.text and check.text:GetText() == "Autosave" then click(check) end
  end
  E.settingsPopup:Hide()
  eq(ns.settings.autosave, true)
  eq(buttons(E.header)["Save Copy"].tipText, "Save this note as a new note, and edit that one. (Ctrl-Shift-S)",
    "Save Copy's tooltip doesn't talk of changes that aren't saved")
  eb:SetFocus()
  MOCK.Tick(1.5)
  MOCK.Type(eb, " two")
  MOCK.Tick(1.5)
  ok(E.dirty, "each change puts the save off")
  MOCK.Tick(0.6)
  ok(not E.dirty, "until there's been none for a moment")
  eq(mage.text, before .. " one two")
  ok(E.statusText:GetText():find("Saved", 1, true), "the status says so")
  ctrl("Z")
  ok(E.editor:GetText() ~= mage.text, "undo goes on past an autosave")
  ctrl("Y")
  eq(E.editor:GetText(), mage.text)

  -- the title box is left as it's typed: a space at its end is for the next word
  E.titleBox:SetFocus()
  E.titleBox:SetText("Mage things ")
  MOCK.FireScript(E.titleBox, "OnTextChanged", true)
  MOCK.Tick(2.1)
  eq(mage.title, "Mage things", "the title is saved")
  eq(E.titleBox:GetText(), "Mage things ", "as it's typed")
  ok(not E.dirty, "with nothing left to save")

  local popups = #MOCK.popups
  eb:SetFocus()
  eb:SetCursorPosition(#E.editor.display)
  MOCK.Type(eb, " three")
  E:RequestLoad(Notes:FindByTitle("Welcome to Markdown Notepad").id)
  eq(#MOCK.popups, popups, "opening another note doesn't ask")
  eq(mage.text, before .. " one two three", "it saves the changes first")
  eq(E.titleBox:GetText(), "Welcome to Markdown Notepad", "and opens the other note")

  -- a new note is saved too, its title box left empty to type in
  E:NewNote()
  eb:SetFocus()
  MOCK.Type(eb, "new words")
  MOCK.Tick(2.1)
  local fresh = Notes:Get(E.current.id)
  ok(fresh, "a new note is saved")
  eq(fresh.title, "Untitled")
  eq(E.titleBox:GetText(), "")
  ok(not E.dirty)

  MOCK.Type(eb, " more")
  E:Hide()
  eq(fresh.text, "new words more", "closing the editor saves")
  E:Show()

  eb:SetFocus()
  eb:SetCursorPosition(#E.editor.display)
  MOCK.Type(eb, " copied")
  click(buttons(E.header)["Save Copy"])
  eq(fresh.text, "new words more copied", "Save Copy saves the note first")
  local copy = Notes:Get(E.current.id)
  eq(copy.title, "Untitled (copy)", "then copies it")
  eq(copy.text, fresh.text)

  eb:SetFocus()
  eb:SetCursorPosition(#E.editor.display)
  MOCK.Type(eb, " at logout")
  MOCK.Fire("PLAYER_LOGOUT")
  eq(copy.text, "new words more copied at logout", "a logout saves")
  eq(ns.db.draft, nil, "with nothing to keep for the next login")
  eq(#MOCK.popups, popups, "and nothing asked")

  Notes:Delete(fresh.id)
  Notes:Delete(copy.id)
  -- the last test keeps unsaved changes
  ns.settings.autosave = false
end)

T.test("unsaved changes are kept at logout", function()
  E:NewNote()
  E.titleBox:SetText("Draft")
  local eb = E.editor.editBox
  eb:SetFocus()
  MOCK.Type(eb, "draft | text")
  local welcome = Notes:FindByTitle("Welcome to Markdown Notepad")
  V:Open(welcome.id)
  MOCK.Fire("PLAYER_LOGOUT")
  eq(ns.db.draft.text, "draft | text")
  eq(ns.db.draft.title, "Draft")
  -- as 1.0.0 left it: its welcome note wrapped at 100 characters, never changed (test_reload.lua
  -- checks it gets this version's text)
  welcome.text = "Write in **Markdown** on the left, and see it rendered on the right. *Save* keeps the note; it's\nlisted"
  welcome.modified = welcome.created
  MarkdownNotepadDB.version = 1
  SAVED_DB ="MarkdownNotepadDB = " .. MOCK.Serialize(MarkdownNotepadDB)
  SAVED_CHAR = "MarkdownNotepadCharDB = " .. MOCK.Serialize(MarkdownNotepadCharDB)
end)
