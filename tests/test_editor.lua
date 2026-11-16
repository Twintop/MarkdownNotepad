-- CodeEditor.lua, typed into as a player would: random sessions of typing, Backspace, Delete,
-- clicks, selections typed over, pastes, and toolbar actions, each checked against the same
-- edit made to a plain string. Every way the real EditBox might handle | and Backspace is tried.

local M, A = ns.Markup, ns.Actions
local eq = T.eq

-- the offset of the UTF-8 character p is in
local function align(s, p)
  while p > 0 and p < #s do
    local b = s:byte(p + 1)
    if b < 128 or b >= 192 then break end
    p = p - 1
  end
  return p
end

local ACTIONS = {
  { "bold", A.Wrap, "**", "**", "bold" },
  { "code", A.Wrap, "`", "`", "code" },
  { "heading", A.Heading, 2 },
  { "bullets", A.List, "bullet" },
  { "numbers", A.List, "ordered" },
  { "tasks", A.List, "task" },
  { "quote", A.Quote },
  { "indent", A.Indent, false },
  { "outdent", A.Indent, true },
  { "link", A.Link },
  { "code block", A.CodeBlock },
  { "rule", A.Block, "---" },
  { "insert", A.Insert, "{rt1}" },
  { "footnote", A.Footnote },
}

local function session(seed, pipeMode, backspaceMode, highlight, steps)
  MOCK.pipeMode, MOCK.backspaceMode = pipeMode, backspaceMode
  local label = ("seed %d, pipes %s, backspace %s, coloring %s"):format(seed, pipeMode, backspaceMode, tostring(highlight))
  local rng = T.rng(seed)
  local ed = ns.CodeEditor.Create(UIParent)
  local eb = ed.editBox
  ed:SetHighlight(highlight)
  ed:SetText("")
  eb:SetFocus()

  -- the reference: the text, and the selection (a cursor when they're equal)
  local ref, selA, selB = "", 0, 0
  local history, full = {}, false

  local function replace(a, b, str)
    ref = ref:sub(1, a) .. str .. ref:sub(b + 1)
    selA = a + #str
    selB = selA
    if str == "\n" and a == b then
      local continued, at = A.ContinueList(ref, selA)
      if continued then ref, selA, selB = continued, at, at end
    end
  end

  local function randomRange()
    local a, b = align(ref, rng(#ref + 1) - 1), align(ref, rng(#ref + 1) - 1)
    if a > b then a, b = b, a end
    return a, b
  end

  local function select(a, b)
    eb:SetCursorPosition(M.ToDisplay(ed.display, b))
    if a ~= b then eb:HighlightText(M.ToDisplay(ed.display, a), M.ToDisplay(ed.display, b)) end
    selA, selB = a, b
  end

  for step = 1, steps do
    local op, desc = rng(100), nil
    if op <= 44 then
      local ch = T.randomText(rng, 1)
      desc = ("type %q"):format(ch)
      MOCK.Type(eb, ch)
      replace(selA, selB, ch)
    elseif op <= 58 then
      desc = "backspace"
      MOCK.Backspace(eb)
      if selA ~= selB then replace(selA, selB, "")
      elseif selA > 0 then replace(M.PrevChar(ref, selA), selA, "") end
    elseif op <= 64 then
      desc = "delete"
      MOCK.Delete(eb)
      if selA ~= selB then replace(selA, selB, "")
      elseif selA < #ref then replace(selA, M.NextChar(ref, selA), "") end
    elseif op <= 76 then
      -- a click between any two characters, which can be either side of a color code
      local chars = MOCK.characters(eb:GetText())
      local k = rng(#chars + 1) - 1
      local pos = k == 0 and 0 or chars[k][2]
      desc = "click at " .. pos
      eb:SetCursorPosition(pos)
      selA = M.ToPlain(ed.display, pos)
      selB = selA
    elseif op <= 84 then
      local a, b = randomRange()
      local ch = T.randomText(rng, 1)
      desc = ("select %d-%d and type %q"):format(a, b, ch)
      select(a, b)
      MOCK.Type(eb, ch)
      replace(a, b, ch)
    elseif op <= 91 then
      local text = T.randomText(rng, rng(8))
      -- pasted raw, "|r" and "|c..." would be read as color codes; that's a known limit
      if pipeMode == "raw" then text = text:gsub("|", "/") end
      desc = ("paste %q"):format(text)
      MOCK.Paste(eb, text)
      replace(selA, selB, text)
    else
      local action = ACTIONS[rng(#ACTIONS)]
      local a, b = randomRange()
      desc = ("%s on %d-%d"):format(action[1], a, b)
      select(a, b)
      ed:Apply(action[2], unpack(action, 3))
      ref, selA, selB = action[2](ref, a, b, unpack(action, 3))
    end
    history[#history + 1] = desc
    if #ed.undo >= ns.CodeEditor.UNDO_LIMIT then full = true end
    if ed:GetText() ~= ref then
      error(("%s: after step %d (%s)\n  steps: %s\n  editor:   %q\n  expected: %q\n  display: %q"):format(
        label, step, desc, table.concat(history, ", ", math.max(1, #history - 8)), ed:GetText(), ref, eb:GetText()), 0)
    end
    eq(M.Decode(eb:GetText()), ref, label .. ": the display shows the text")
    eq(ed:GetCursor(), selB, ("%s: the cursor after step %d (%s)"):format(label, step, desc))
  end

  local final = ref
  while #ed.undo > 0 do ed:Undo() end
  -- once the undo history is full, its oldest steps are let go
  if not full then eq(ed:GetText(), "", label .. ": undoing everything") end
  while #ed.redo > 0 do ed:Redo() end
  eq(ed:GetText(), final, label .. ": redoing everything")
  ed.frame:Hide()
end

for _, pipeMode in ipairs({ "escape", "raw" }) do
  for _, backspaceMode in ipairs({ "token", "byte" }) do
    for _, highlight in ipairs({ true, false }) do
      T.test(("typing (pipes %s, backspace %s, coloring %s)"):format(pipeMode, backspaceMode, tostring(highlight)), function()
        for seed = 1, FUZZ_SESSIONS or 12 do session(seed, pipeMode, backspaceMode, highlight, FUZZ_STEPS or 160) end
      end)
    end
  end
end

T.test("typing a list", function()
  MOCK.pipeMode, MOCK.backspaceMode = "escape", "token"
  local ed = ns.CodeEditor.Create(UIParent)
  ed:SetText("")
  ed.editBox:SetFocus()
  -- Enter on the empty third item ends the list, leaving an empty line; the next Enter is a
  -- plain line break
  MOCK.Type(ed.editBox, "- one\ntwo\n\n\nafter")
  eq(ed:GetText(), "- one\n- two\n\nafter")
  ed:SetText("1. a\n")
  ed.editBox:SetCursorPosition(#ed.display)
  MOCK.Type(ed.editBox, "b\n")
  eq(ed:GetText(), "1. a\nb\n")  -- "b" isn't an item, so its new line isn't one either
end)

T.test("typing among repeated letters keeps the cursor in place", function()
  local ed = ns.CodeEditor.Create(UIParent)
  ed:SetText("hello")
  ed.editBox:SetFocus()
  ed.editBox:SetCursorPosition(3)
  MOCK.Type(ed.editBox, "lx")
  eq(ed:GetText(), "hellxlo") -- the x follows the typed l, not the run of them
  ed:SetText("aaa")
  ed.editBox:SetCursorPosition(2)
  MOCK.Backspace(ed.editBox)
  eq(ed:GetCursor(), 1)
end)

T.test("one undo takes back a burst of typing", function()
  local ed = ns.CodeEditor.Create(UIParent)
  ed:SetText("")
  ed.editBox:SetFocus()
  MOCK.Type(ed.editBox, "hello")
  MOCK.now = MOCK.now + 5
  MOCK.Type(ed.editBox, "world")
  ed:Undo()
  eq(ed:GetText(), "hello")
  ed:Undo()
  eq(ed:GetText(), "")
  ed:Redo()
  ed:Redo()
  eq(ed:GetText(), "helloworld")
end)

T.test("game links become markdown links", function()
  local CE = ns.CodeEditor
  eq(CE.LinkToMarkdown("|cff71d5ff|Hspell:133:0|h[Fireball]|h|r"), "[Fireball](spell:133)")
  eq(CE.LinkToMarkdown("|cffffffff|Hitem:6948::::::::80:::::|h[Hearthstone]|h|r"), "[Hearthstone](item:6948)")
  eq(CE.LinkToMarkdown("plain words"), "plain words")
end)
