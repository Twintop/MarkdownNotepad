-- The editor's formatting actions: the toolbar's quick-add buttons, its shortcuts, Tab, and the
-- list a new line continues.
--
-- Each takes the plain text and a selection, s to e (0-based byte offsets, so text:sub(s + 1, e)
-- is the selected text; s == e is a cursor), and returns the new text and the new selection.
-- Like Markup.lua, this file uses only Lua's string library, so the tests run it outside the game.

local _, ns = ...
local A = {}
ns.Actions = A

local byte, find, sub, match, rep, gsub = string.byte, string.find, string.sub, string.match, string.rep, string.gsub
local concat = table.concat

local NEWLINE = 10

local function replace(text, a, b, str)
  return sub(text, 1, a) .. str .. sub(text, b + 1)
end

-- the n bytes before offset pos ("" when there aren't n)
local function before(text, pos, n)
  if pos < n then return "" end
  return sub(text, pos - n + 1, pos)
end

-- the offset where the line holding offset pos starts
local function lineStart(text, pos)
  local i = pos
  while i > 0 and byte(text, i) ~= NEWLINE do i = i - 1 end
  return i
end

-- the offset where the line holding offset pos ends, before its line break
local function lineEnd(text, pos)
  local nl = find(text, "\n", pos + 1, true)
  return nl and nl - 1 or #text
end

local function split(s)
  local lines, pos = {}, 1
  while true do
    local nl = find(s, "\n", pos, true)
    if not nl then lines[#lines + 1] = sub(s, pos); return lines end
    lines[#lines + 1] = sub(s, pos, nl - 1)
    pos = nl + 1
  end
end

-- the whole lines the selection touches; a selection that ends just after a line break doesn't
-- take in the line after it
local function selectedLines(text, s, e)
  local first = lineStart(text, s)
  local last = lineEnd(text, (e > s and byte(text, e) == NEWLINE) and e - 1 or e)
  return first, last, split(sub(text, first + 1, last))
end

A.lineStart, A.lineEnd = lineStart, lineEnd

-- Replaces each line the selection touches with fn(line). Blank lines are left alone unless
-- `blank` is set, or the selection is in a single (blank) line. A cursor keeps its place in the
-- line's text; a selection selects the lines.
function A.EachLine(text, s, e, fn, blank)
  local first, last, lines = selectedLines(text, s, e)
  local single = #lines == 1
  local out = {}
  for i, line in ipairs(lines) do
    if blank or single or find(line, "%S") then out[i] = fn(line) else out[i] = line end
  end
  local old = sub(text, first + 1, last)
  local new = concat(out, "\n")
  local result = sub(text, 1, first) .. new .. sub(text, last + 1)
  if s == e and single then
    local col = s - first + (#new - #old)
    if col < 0 then col = 0 elseif col > #new then col = #new end
    return result, first + col, first + col
  end
  return result, first, first + #new
end

-- Replaces the selection with str, then selects str's bytes selA to selB (offsets in str), or
-- puts the cursor after str.
function A.Insert(text, s, e, str, selA, selB)
  local result = replace(text, s, e, str)
  if selA then return result, s + selA, s + (selB or selA) end
  return result, s + #str, s + #str
end

-- Wraps the selection in left and right (**bold**), or unwraps it when it's wrapped already.
-- With no selection, inserts the pair around a selected placeholder.
function A.Wrap(text, s, e, left, right, placeholder)
  local sel = sub(text, s + 1, e)
  if not find(sel, "%S") then
    -- the cursor between an empty pair: take the pair out
    if sel == "" and before(text, s, #left) == left and sub(text, s + 1, s + #right) == right then
      return replace(text, s - #left, s + #right, ""), s - #left, s - #left
    end
    placeholder = placeholder or ""
    return replace(text, s, e, left .. placeholder .. right), s + #left, s + #left + #placeholder
  end
  if #sel >= #left + #right and sub(sel, 1, #left) == left and sub(sel, -#right) == right then
    local inner = sub(sel, #left + 1, #sel - #right)
    return replace(text, s, e, inner), s, s + #inner
  end
  if before(text, s, #left) == left and sub(text, e + 1, e + #right) == right then
    return replace(text, s - #left, e + #right, sel), s - #left, e - #left
  end
  -- spaces at the ends of the selection stay outside the delimiters: "**word** ", not "**word **"
  local lead, core, trail = match(sel, "^(%s*)(.-)(%s*)$")
  local at = s + #lead + #left
  return replace(text, s, e, lead .. left .. core .. right .. trail), at, at + #core
end

-- # to ######: sets the selected lines' heading level, or makes them text again when they're
-- that level already
function A.Heading(text, s, e, level)
  local hashes = rep("#", level)
  return A.EachLine(text, s, e, function(line)
    local indent, marks, rest = match(line, "^( ? ? ?)(#+)%s+(.*)$")
    if not marks then indent, marks = match(line, "^( ? ? ?)(#+)$"); rest = "" end
    if marks and #marks <= 6 then
      if #marks == level then return indent .. rest end
      return indent .. hashes .. " " .. rest
    end
    return hashes .. " " .. line
  end)
end

-- a line's indent, its text after any list marker, and the kind of marker it had
local function listItem(line)
  local indent, rest = match(line, "^(%s*)[%-%*%+]%s+%[[ xX]%]%s+(.*)$")
  if indent then return indent, rest, "task" end
  indent, rest = match(line, "^(%s*)[%-%*%+]%s+%[[ xX]%]$")
  if indent then return indent, "", "task" end
  indent, rest = match(line, "^(%s*)[%-%*%+]%s+(.*)$")
  if indent then return indent, rest, "bullet" end
  indent, rest = match(line, "^(%s*)%d+[%.%)]%s+(.*)$")
  if indent then return indent, rest, "ordered" end
  indent, rest = match(line, "^(%s*)(.*)$")
  return indent, rest, nil
end
A.listItem = listItem

-- Makes the selected lines a list: "bullet" (- ), "ordered" (1. 2. 3.), or "task" (- [ ] ).
-- Lines of another kind of list change kind. When every line is that kind already, the markers
-- come off instead.
function A.List(text, s, e, kind)
  local _, _, lines = selectedLines(text, s, e)
  local all = true
  for _, line in ipairs(lines) do
    if find(line, "%S") and select(3, listItem(line)) ~= kind then all = false end
  end
  local n = 0
  return A.EachLine(text, s, e, function(line)
    local indent, rest = listItem(line)
    if all then return indent .. rest end
    n = n + 1
    if kind == "ordered" then return indent .. n .. ". " .. rest end
    if kind == "task" then return indent .. "- [ ] " .. rest end
    return indent .. "- " .. rest
  end)
end

-- Quotes the selected lines (> ), or unquotes them when they're all quoted. Blank lines between
-- them are quoted too, so the quote stays one block.
function A.Quote(text, s, e)
  local _, _, lines = selectedLines(text, s, e)
  local all = true
  for _, line in ipairs(lines) do
    if find(line, "%S") and not find(line, "^%s*>") then all = false end
  end
  return A.EachLine(text, s, e, function(line)
    if all then return (gsub(line, "^(%s*)> ?", "%1", 1)) end
    if line == "" then return ">" end
    return "> " .. line
  end, true)
end

-- Tab and Shift-Tab. Tab indents the selected lines by two spaces (nesting a list item under the
-- one above it); with no selection, it indents a list item's line, or else puts two spaces at the
-- cursor. Shift-Tab takes up to two spaces off the start of each line.
function A.Indent(text, s, e, outdent)
  if outdent then
    return A.EachLine(text, s, e, function(line) return (gsub(line, "^  ?", "", 1)) end)
  end
  if s == e then
    local first = lineStart(text, s)
    local line = sub(text, first + 1, lineEnd(text, s))
    if not select(3, listItem(line)) then return A.Insert(text, s, e, "  ") end
  end
  return A.EachLine(text, s, e, function(line) return "  " .. line end)
end

-- Puts block on lines of its own, with a blank line before and after it (so a --- under a line
-- of text stays a rule instead of turning the text into a heading). selA and selB select part
-- of block; otherwise the cursor goes to the line after it.
function A.Block(text, s, e, block, selA, selB)
  local head, tail = sub(text, 1, s), sub(text, e + 1)
  local pre
  if head == "" or find(head, "\n\n$") or head == "\n" then
    pre = ""
  elseif find(head, "\n$") then
    pre = find(head, "\n%s*\n$") and "" or "\n"
  else
    pre = "\n\n"
  end
  local post
  if tail == "" then
    post = "\n"
  elseif find(tail, "^\n\n") then
    post = ""
  elseif find(tail, "^\n") then
    post = "\n"
  else
    post = "\n\n"
  end
  local result = head .. pre .. block .. post .. tail
  local at = s + #pre
  if selA then return result, at + selA, at + (selB or selA) end
  local cursor = at + #block + (post ~= "" and 1 or 0)
  return result, cursor, cursor
end

-- ``` fences around the selection, or an empty code block with the cursor inside
function A.CodeBlock(text, s, e)
  local sel = sub(text, s + 1, e)
  sel = gsub(sel, "\n$", "")
  return A.Block(text, s, e, "```\n" .. sel .. "\n```", 4, 4 + #sel)
end

-- [text](url): the selection becomes the text, or the url when it looks like one
function A.Link(text, s, e)
  local sel = sub(text, s + 1, e)
  if sel == "" then return A.Insert(text, s, e, "[text](url)", 1, 5) end
  if find(sel, "^https?://") or find(sel, "^www%.") then
    return A.Insert(text, s, e, "[text](" .. sel .. ")", 1, 5)
  end
  return A.Insert(text, s, e, "[" .. sel .. "](url)", #sel + 3, #sel + 6)
end

-- [title](note:title), a link that opens another note
function A.NoteLink(text, s, e)
  local sel = sub(text, s + 1, e)
  if sel == "" or find(sel, "\n") then sel = "Note title" end
  return A.Insert(text, s, e, "[" .. sel .. "](note:" .. sel .. ")", #sel + 8, #sel * 2 + 8)
end

A.TABLE = "| Column | Column |\n| ------ | ------ |\n| Cell   | Cell   |"

-- a footnote: [^n] at the cursor, with the first unused n, and its note started at the end of
-- the text, where the cursor goes
function A.Footnote(text, s, e)
  local n = 1
  while find(text, "[^" .. n .. "]", 1, true) do n = n + 1 end
  local ref = "[^" .. n .. "]"
  local result = replace(text, s, e, ref)
  if find(result, "\n\n$") then
    -- already ends with a blank line
  elseif find(result, "\n$") then
    result = result .. "\n"
  else
    result = result .. "\n\n"
  end
  result = result .. ref .. ": "
  return result, #result, #result
end

-- A new line after a list item starts the next item: the same bullet, the next number, or an
-- open task box; after a quote, the quote goes on. When the item was empty, the new line ends
-- the list instead, and the empty marker comes off. `cursor` is just after the new line break.
-- Returns nil when the line before isn't a list item or quote.
function A.ContinueList(text, cursor)
  if byte(text, cursor) ~= NEWLINE then return end
  local first = lineStart(text, cursor - 1)
  local line = sub(text, first + 1, cursor - 1)
  local marker, rest

  local indent, bullet, box, content = match(line, "^(%s*)([%-%*%+])%s+%[([ xX])%]%s+(.*)$")
  if not indent then
    indent, bullet, box = match(line, "^(%s*)([%-%*%+])%s+%[([ xX])%]%s*$"); content = ""
  end
  if indent then
    marker, rest = indent .. bullet .. " [ ] ", content
  else
    indent, bullet, content = match(line, "^(%s*)([%-%*%+])%s+(.*)$")
    if not indent then indent, bullet = match(line, "^(%s*)([%-%*%+])$"); content = "" end
    if indent then
      marker, rest = indent .. bullet .. " ", content
    else
      local num, delim
      indent, num, delim, content = match(line, "^(%s*)(%d+)([%.%)])%s+(.*)$")
      if not indent then indent, num, delim = match(line, "^(%s*)(%d+)([%.%)])$"); content = "" end
      if indent then
        marker, rest = indent .. (tonumber(num) + 1) .. delim .. " ", content
      else
        local quote
        quote, content = match(line, "^(%s*>[> ]*)(.*)$")
        if not quote then return end
        quote = gsub(quote, "%s*$", "") .. " "
        marker, rest = quote, content
      end
    end
  end

  if not find(rest, "%S") then
    -- an empty item ends the list: clear its marker, and drop the new line break
    local result = sub(text, 1, first) .. sub(text, cursor + 1)
    return result, first, first
  end
  local result = sub(text, 1, cursor) .. marker .. sub(text, cursor + 1)
  return result, cursor + #marker, cursor + #marker
end
