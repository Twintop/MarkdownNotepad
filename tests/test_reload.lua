-- After a /reload: the saved variables test_smoke.lua ended with, loaded again.

local eq, ok = T.eq, T.ok
local Notes, E, V = ns.Notes, ns.Editor, ns.Viewer

T.test("after a reload", function()
  MOCK.Fire("ADDON_LOADED", "MarkdownNotepad")
  MOCK.Fire("PLAYER_LOGIN")
  local welcomes = 0
  for _, note in pairs(ns.db.notes) do
    if note.title == "Welcome to Markdown Notepad" then welcomes = welcomes + 1 end
  end
  eq(welcomes, 1, "the welcome note isn't made again")
  local welcome = Notes:FindByTitle("Welcome to Markdown Notepad")
  eq(welcome.text, ns.Localization["WelcomeNoteText"]:format(welcome.title),
    "1.0.0's welcome note, never changed, gets this version's text")
  eq(ns.db.version, 2)
  ok(V:IsOpen(Notes:FindByTitle("Welcome to Markdown Notepad").id), "the pinned note is back")
  ok(Notes:FindByTitle("Mage things"), "the saved notes are there")
  MOCK.Tick(0)
  MOCK.Tick(1.1)
  ok(not MarkdownNotepadNews, "the news of a version already seen doesn't open again")

  -- The editor opening before the game has worked out its frames' sizes, and no OnSizeChanged
  -- coming once it has, as on the Forever client, where the editor and preview never appeared.
  MOCK.unresolved = true
  E:Show()
  eq(E.editor.frame:GetNumPoints(), 0, "(the editor can't be laid out yet)")
  MOCK.unresolved = false
  MOCK.Tick()
  ok(E.editor.frame:GetNumPoints() > 0, "the editor is laid out once its size is known")
  ok(E.preview:IsShown() and E.preview:GetNumPoints() > 0, "and the preview beside it")
  eq(E.previewHTML:GetWidth(), E.previewScroll:GetWidth(), "the preview wraps at its width")
  eq(E.editor.editBox:GetWidth(), E.editor.scroll:GetWidth(), "and so does the text")
  eq(E.toolItems[1].button:GetNumPoints(), 1, "the toolbar's buttons are placed")

  eq(E.editor:GetText(), "draft | text", "the unsaved changes come back")
  eq(E.titleBox:GetText(), "Draft")
  ok(E.dirty, "still unsaved")
  ok(E.statusText:GetText():find("restored", 1, true), "and the status says they were restored")
  eq(ns.db.draft, nil, "the draft is used up")
  E:Save()
  eq(Notes:FindByTitle("Draft").text, "draft | text")
end)
