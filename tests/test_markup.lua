-- Markup.lua and Actions.lua: the text model and the formatting actions.

local M, A = ns.Markup, ns.Actions
local eq, ok = T.eq, T.ok

------------------------------------------------------------------------------------------------
-- escaping and decoding
------------------------------------------------------------------------------------------------

T.test("Escape and Decode", function()
  eq(M.Escape("a|b||c"), "a||b||||c")
  eq(M.Decode("a||b"), "a|b")
  eq(M.Decode("a|b"), "a|b")
  eq(M.Decode("|cffff0000red|r and |cFF00ff00green|r"), "red and green")
  eq(M.Decode("||cffff0000"), "|cffff0000")
  eq(M.Decode("x\r\ny\rz"), "x\ny\nz")
  eq(M.Decode("\tindented"), "    indented")
  eq(M.Decode("a" .. M.SENTINEL .. "b"), "ab")
  eq(M.Decode("bell\7 and nul\0 gone"), "bell and nul gone")
  eq(M.Decode("é and ü stay"), "é and ü stay")
end)

T.test("Lines", function()
  local lines, n = M.Lines("a\nb\n")
  eq(n, 3); eq(lines[1], "a"); eq(lines[2], "b"); eq(lines[3], "")
  lines, n = M.Lines("")
  eq(n, 1); eq(lines[1], "")
end)

T.test("Diff", function()
  local p, ae, be = M.Diff("hello world", "hello brave world")
  eq(p, 6); eq(ae, 6); eq(be, 12)
  p, ae, be = M.Diff("aaa", "aaaa")
  eq(p, 3); eq(ae, 3); eq(be, 4)
  p, ae, be = M.Diff("abc", "abc")
  eq(p, 3); eq(ae, 3); eq(be, 3)
  -- long strings use the chunked comparison
  local long = string.rep("x", 1000)
  p, ae, be = M.Diff(long .. "A" .. long, long .. "BB" .. long)
  eq(p, 1000); eq(ae, 1001); eq(be, 1002)
end)

T.test("DiffAt places a change among repeated characters by the cursor", function()
  -- an l typed at "hel|lo": a diff alone puts it after the second l
  local p, ae, be = M.Diff("hello", "helllo")
  eq(p, 4)
  p, ae, be = M.DiffAt("hello", "helllo", 4)
  eq(p, 3); eq(ae, 3); eq(be, 4)
  -- Backspace at "aa|a"
  p, ae, be = M.DiffAt("aaa", "aa", 1)
  eq(p, 1); eq(ae, 2); eq(be, 1)
  -- a cursor that doesn't fit the change falls back to Diff
  p, ae, be = M.DiffAt("abc", "abXc", 0)
  eq(p, 2); eq(ae, 2); eq(be, 3)
end)

T.test("PrevChar and NextChar step over UTF-8 characters", function()
  local s = "aé"   -- a, then two bytes
  eq(M.PrevChar(s, 3), 1)
  eq(M.PrevChar(s, 1), 0)
  eq(M.NextChar(s, 1), 3)
  eq(M.NextChar(s, 0), 1)
  eq(M.NextChar(s, 3), 3)
end)

------------------------------------------------------------------------------------------------
-- syntax coloring
------------------------------------------------------------------------------------------------

local C = M.colors
local function colored(kind, s) return "|c" .. C[kind] .. s .. "|r" end

T.test("Render without coloring only escapes", function()
  eq(M.Render("| a | b |", false), "|| a || b ||")
end)

T.test("Render colors the syntax", function()
  M.shortcodes[":check:"] = true
  eq(M.Render("# Heading", true), colored("heading", "# Heading"))
  eq(M.Render("####### not a heading", true), "####### not a heading")
  eq(M.Render("#hashtag", true), "#hashtag")
  eq(M.Render("a **b** c", true), "a " .. colored("strong", "**b**") .. " c")
  eq(M.Render("a *b* c", true), "a " .. colored("em", "*b*") .. " c")
  eq(M.Render("snake_case_name", true), "snake_case_name")
  eq(M.Render("2 * 3 * 4", true), "2 * 3 * 4")
  eq(M.Render("`a|b`", true), colored("code", "`a||b`"))
  eq(M.Render("- item", true), colored("marker", "- ") .. "item")
  eq(M.Render("- [x] done", true), colored("marker", "- [x]") .. " done") -- one run, one color
  eq(M.Render("> quote", true), colored("marker", "> ") .. colored("quote", "quote"))
  eq(M.Render("---", true), colored("rule", "---"))
  eq(M.Render("[t](u)", true), colored("link", "[t]") .. colored("url", "(u)"))
  eq(M.Render("{rt1} {nope}", true), colored("icon", "{rt1}") .. " {nope}")
  eq(M.Render(":check: :nope:", true), colored("icon", ":check:") .. " :nope:")
  eq(M.Render("| a | b |", true),
    colored("marker", "||") .. " a " .. colored("marker", "||") .. " b " .. colored("marker", "||"))
  eq(M.Render("|---|---|", true), colored("marker", "||---||---||"))
  eq(M.Render("```\n**not bold**\n```", true),
    colored("fence", "```") .. "\n" .. colored("code", "**not bold**") .. "\n" .. colored("fence", "```"))
end)

-- every | in a display is part of ||, a color code, or |r, and color codes don't nest
local function wellFormed(display)
  local i, open = 1, false
  while true do
    local pipe = display:find("|", i, true)
    if not pipe then break end
    local len, width = M.token(display, pipe)
    local seq = display:sub(pipe, pipe + len - 1)
    if seq == "||" then
      -- fine
    elseif seq == "|r" then
      if not open then return false, "a |r closes nothing at " .. pipe end
      open = false
    elseif len == 10 then
      if open then return false, "a color opens inside another at " .. pipe end
      open = true
    else
      return false, "a lone | at " .. pipe
    end
    i = pipe + len
  end
  if open then return false, "a color is never closed" end
  return true
end

local SAMPLES = {
  "", "plain", "a|b", "||", "|c", "|r", "|cffff0000not a color|r",
  "# Title\n\nSome **bold** and *italic* and `code|pipe`.\n\n- [ ] task\n- [x] done\n1. one\n2. two",
  "| Spell | Cost |\n|-------|-----:|\n| Fire\\|ball | 2% |",
  "> [!NOTE]\n> quoted **text**\n>\n> > nested",
  "```lua\nlocal x = '|cff'\n```\nafter", "~~~\n|\n~~~", "````\n```\n````",
  "![](spell:133) [Fireball](spell:133) <https://example.org> www.example.org &amp; &copy;",
  "Term\n: Definition\n\n[^1]: a note\n[ref]: https://x.y",
  "{rt1}{skull} :check: ==mark== ~~del~~ ***both***",
  "é ü 中文 | ü",
}

T.test("Render keeps the text, and makes well-formed displays", function()
  local rng = T.rng(1)
  local texts = {}
  for _, s in ipairs(SAMPLES) do texts[#texts + 1] = s end
  for _ = 1, 400 do texts[#texts + 1] = T.randomText(rng, rng(80)) end
  for _, text in ipairs(texts) do
    for _, highlight in ipairs({ true, false }) do
      local display = M.Render(text, highlight)
      eq(M.Decode(display), text, "Decode(Render(text))")
      local good, why = wellFormed(display)
      ok(good, ("display of %q: %s"):format(text, tostring(why)))
    end
  end
end)

T.test("ToPlain and ToDisplay agree", function()
  local rng = T.rng(2)
  local texts = {}
  for _, s in ipairs(SAMPLES) do texts[#texts + 1] = s end
  for _ = 1, 200 do texts[#texts + 1] = T.randomText(rng, rng(60)) end
  for _, text in ipairs(texts) do
    local display = M.Render(text, true)
    for p = 0, #text do
      local d = M.ToDisplay(display, p)
      eq(M.ToPlain(display, d), p, ("ToPlain(ToDisplay(%d)) in %q"):format(p, text))
      -- the bytes before d decode to the first p bytes of the text
      eq(M.Decode(display:sub(1, d)), text:sub(1, p), "the display up to ToDisplay")
    end
    local last = 0
    for d = 0, #display do
      local floor, ceil = M.ToPlain(display, d), M.ToPlain(display, d, true)
      ok(floor >= last, "ToPlain never goes back")
      ok(ceil >= floor and ceil <= floor + 1, "ceil is floor, or one more inside ||")
      last = floor
    end
    eq(M.ToPlain(display, #display), #text, "the end maps to the end")
  end
end)

------------------------------------------------------------------------------------------------
-- actions
------------------------------------------------------------------------------------------------

local function act(expectText, expectS, expectE, text, s, e)
  eq(text, expectText, "text")
  eq(s, expectS, "selection start")
  eq(e, expectE, "selection end")
end

T.test("Wrap", function()
  act("hello **world**", 8, 13, A.Wrap("hello world", 6, 11, "**", "**"))
  act("a**bold**b", 3, 7, A.Wrap("ab", 1, 1, "**", "**", "bold"))
  act("a b c", 2, 3, A.Wrap("a **b** c", 2, 7, "**", "**"))     -- the selection holds the markers
  act("a b c", 2, 3, A.Wrap("a **b** c", 4, 5, "**", "**"))     -- the markers are around it
  act("x **word** y", 4, 8, A.Wrap("x word y", 1, 7, "**", "**")) -- spaces stay outside
  act("ab", 1, 1, A.Wrap("a****b", 3, 3, "**", "**"))           -- an empty pair comes out
end)

T.test("Heading", function()
  act("# Title", 2, 2, A.Heading("Title", 0, 0, 1))
  act("Title", 1, 1, A.Heading("# Title", 3, 3, 1))
  act("## Title", 4, 4, A.Heading("# Title", 3, 3, 2))
  act("## ", 3, 3, A.Heading("", 0, 0, 2))
  act("# #hashtag", 2, 2, A.Heading("#hashtag", 0, 0, 1))
  act("a\n# b\n# c", 2, 9, A.Heading("a\nb\nc", 2, 5, 1))
end)

T.test("Lists", function()
  act("- a\n- b\n\n- c", 0, 12, A.List("a\nb\n\nc", 0, 6, "bullet"))
  act("a\nb\n\nc", 0, 6, A.List("- a\n- b\n\n- c", 0, 12, "bullet"))
  act("1. a\n2. b", 0, 9, A.List("a\nb", 0, 3, "ordered"))
  act("1. a\n2. b", 0, 9, A.List("- a\n- b", 0, 7, "ordered"))
  act("- [ ] x", 6, 6, A.List("x", 0, 0, "task"))
  act("  - x", 4, 4, A.List("  x", 2, 2, "bullet"))
  -- a selection that ends just after a line break leaves the next line alone
  act("- a\nb", 0, 3, A.List("a\nb", 0, 2, "bullet"))
end)

T.test("Quote", function()
  act("> a\n>\n> b", 0, 9, A.Quote("a\n\nb", 0, 4))
  act("a\n\nb", 0, 4, A.Quote("> a\n>\n> b", 0, 9))
end)

T.test("Indent and outdent", function()
  act("  - a", 5, 5, A.Indent("- a", 3, 3))
  act("a  b", 3, 3, A.Indent("ab", 1, 1))
  act("- a", 3, 3, A.Indent("  - a", 5, 5, true))
  act("  a\n  b", 0, 7, A.Indent("a\nb", 0, 3))
end)

T.test("Blocks", function()
  act("text\n\n---\n", 10, 10, A.Block("text", 4, 4, "---"))
  act("---\n", 4, 4, A.Block("", 0, 0, "---"))
  act("a\n\n---\n\nb", 7, 7, A.Block("a\n\nb", 2, 2, "---"))
  act("x\n\n```\ncode\n```\n\ny", 7, 11, A.CodeBlock("x\ncode\ny", 2, 6))
  act("```\n\n```\n", 4, 4, A.CodeBlock("", 0, 0))
  local text, s, e = A.Block("", 0, 0, A.TABLE, 2, 8)
  eq(text:sub(s + 1, e), "Column")
end)

T.test("Links", function()
  act("[go](url)", 5, 8, A.Link("go", 0, 2))
  act("[text](url)", 1, 5, A.Link("", 0, 0))
  act("[text](https://x.y)", 1, 5, A.Link("https://x.y", 0, 11))
  local text, s, e = A.NoteLink("Raid", 0, 4)
  eq(text, "[Raid](note:Raid)")
  eq(text:sub(s + 1, e), "Raid")
  eq(s, 12)
end)

T.test("ContinueList", function()
  act("- a\n- ", 6, 6, A.ContinueList("- a\n", 4))
  act("", 0, 0, A.ContinueList("- \n", 3))
  act("1. a\n2. ", 8, 8, A.ContinueList("1. a\n", 5))
  act("- [x] done\n- [ ] ", 17, 17, A.ContinueList("- [x] done\n", 11))
  act("> q\n> ", 6, 6, A.ContinueList("> q\n", 4))
  act("  - nested\n  - ", 15, 15, A.ContinueList("  - nested\n", 11))
  act("- a\n- b", 6, 6, A.ContinueList("- a\nb", 4))  -- Enter in the middle of an item
  eq(A.ContinueList("plain\n", 6), nil)
  eq(A.ContinueList("# heading\n", 10), nil)
end)

T.test("Footnote", function()
  local text, s = A.Footnote("Text", 4, 4)
  eq(text, "Text[^1]\n\n[^1]: ")
  eq(s, #text)
  text = A.Footnote("A[^1]\n\n[^1]: x", 1, 1)
  eq(text, "A[^2][^1]\n\n[^1]: x\n\n[^2]: ")
end)
