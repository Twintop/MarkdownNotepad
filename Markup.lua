-- The text model behind the editor.
--
-- The editor's EditBox never holds a note's markdown as it is. It holds a "display" string: the
-- markdown with each | doubled, so the EditBox shows the | instead of reading it as the start of a
-- UI escape sequence, and (with syntax coloring on) |cAARRGGBB ... |r codes around the markdown's
-- syntax. The editor keeps the markdown itself (the "plain" text), and maps each change the player
-- makes to the display back onto it. These functions do that mapping and build the display.
--
-- Offsets are 0-based byte counts, as the EditBox's cursor positions are: offset n is the place
-- after the first n bytes. Only Lua's string library is used, so tests/run_tests.py can run this
-- file outside the game.

local _, ns = ...
local M = {}
ns.Markup = M

local byte, find, sub, gsub, lower = string.byte, string.find, string.sub, string.gsub, string.lower
local concat = table.concat

local PIPE = 124

-- U+E000, a private use character: CodeEditor inserts it to find the selection. A player can't
-- type it, so seeing one in an edit means it's ours.
M.SENTINEL = "\238\128\128"

------------------------------------------------------------------------------------------------
-- Display <-> plain offsets
------------------------------------------------------------------------------------------------

-- the escape sequence (or character) that starts at byte i of a display string: its length in
-- bytes, and how many bytes of plain text it stands for
local function token(s, i)
  if byte(s, i) ~= PIPE then return 1, 1 end
  local n = byte(s, i + 1)
  if n == PIPE then return 2, 1 end                                          -- || is a |
  if n == 114 then return 2, 0 end                                           -- |r
  if n == 99 and find(s, "^%x%x%x%x%x%x%x%x", i + 2) then return 10, 0 end -- |cAARRGGBB
  return 1, 1                                                                -- a lone |
end
M.token = token

-- The plain offset for display offset `off`. An offset inside an escape sequence (between the two
-- bytes of a ||, or inside a color code) maps to the plain offset before it, or after it when
-- `ceil` is set.
function M.ToPlain(s, off, ceil)
  local pos, plain = 0, 0
  while pos < off do
    local pipe = find(s, "|", pos + 1, true)
    if not pipe or pipe > off then return plain + (off - pos) end
    plain = plain + (pipe - 1 - pos)
    pos = pipe - 1
    local len, width = token(s, pipe)
    if pos + len > off then return ceil and plain + width or plain end
    pos, plain = pos + len, plain + width
  end
  return plain
end

-- The first display offset for plain offset `p`: before any color codes at that place.
function M.ToDisplay(s, p)
  local pos, plain, len = 0, 0, #s
  while plain < p do
    local pipe = find(s, "|", pos + 1, true)
    if not pipe then
      pos = pos + (p - plain)
      return pos < len and pos or len
    end
    local run = pipe - 1 - pos
    if plain + run >= p then return pos + (p - plain) end
    plain, pos = plain + run, pipe - 1
    local tlen, width = token(s, pipe)
    pos, plain = pos + tlen, plain + width
  end
  return pos
end

-- the start of the escape sequence that display offset `off` is inside, or `off` itself when
-- it's between two
function M.TokenStart(s, off)
  local pos = 0
  while pos < off do
    local pipe = find(s, "|", pos + 1, true)
    if not pipe or pipe > off then return off end
    local len = token(s, pipe)
    if pipe - 1 + len > off then return pipe - 1 end
    pos = pipe - 1 + len
  end
  return off
end

-- Turns text that was typed or pasted into the EditBox into plain text: || becomes |, color codes
-- are dropped (a copy of colored text carries them), and so are carriage returns, tabs (as four
-- spaces, as Markdown reads them), our sentinel, and other control characters.
function M.Decode(s)
  if find(s, "|", 1, true) then
    local out, n, pos, len = {}, 0, 1, #s
    while pos <= len do
      local pipe = find(s, "|", pos, true)
      if not pipe then n = n + 1; out[n] = sub(s, pos); break end
      if pipe > pos then n = n + 1; out[n] = sub(s, pos, pipe - 1) end
      local tlen, width = token(s, pipe)
      if width == 1 then n = n + 1; out[n] = "|" end
      pos = pipe + tlen
    end
    s = concat(out)
  end
  if find(s, "[%z\1-\9\11-\31\127\238]") then
    s = gsub(s, "\r\n?", "\n")
    s = gsub(s, "\t", "    ")
    s = gsub(s, M.SENTINEL, "")
    s = gsub(s, "[%z\1-\9\11-\31\127]", "")
  end
  return s
end

-- | doubled, so an EditBox or FontString shows the text as it is
function M.Escape(s)
  return (gsub(s, "|", "||"))
end

-- The part of two strings that differs: a and b share their first `p` bytes and everything after
-- byte aEnd of a (which is everything after byte bEnd of b).
function M.Diff(a, b)
  local la, lb = #a, #b
  local max = la < lb and la or lb
  local step = 128
  local p = 0
  while p + step <= max and sub(a, p + 1, p + step) == sub(b, p + 1, p + step) do p = p + step end
  while p < max and byte(a, p + 1) == byte(b, p + 1) do p = p + 1 end
  local s, maxS = 0, max - p
  while s + step <= maxS and sub(a, la - s - step + 1, la - s) == sub(b, lb - s - step + 1, lb - s) do s = s + step end
  while s < maxS and byte(a, la - s) == byte(b, lb - s) do s = s + 1 end
  return p, la - s, lb - s
end

-- Diff, for an edit the EditBox's cursor ends: after typing, pasting, Backspace, or Delete, the
-- cursor is at the end of what was put in. Among repeated characters a diff alone can't tell
-- where the change was (typing an l in "hel|lo" could have been at either l), and the cursor
-- settles it. When the cursor doesn't fit the change, this is Diff.
function M.DiffAt(a, b, cursor)
  local la, lb = #a, #b
  local aEnd = cursor and cursor - (lb - la)
  if not aEnd or cursor < 0 or cursor > lb or aEnd < 0 or aEnd > la or sub(b, cursor + 1) ~= sub(a, aEnd + 1) then
    return M.Diff(a, b)
  end
  local max = cursor < aEnd and cursor or aEnd
  local step, p = 128, 0
  while p + step <= max and sub(a, p + 1, p + step) == sub(b, p + 1, p + step) do p = p + step end
  while p < max and byte(a, p + 1) == byte(b, p + 1) do p = p + 1 end
  return p, aEnd, cursor
end

-- the start of the UTF-8 character that ends at offset `off`, and the end of the one that starts there
function M.PrevChar(s, off)
  if off <= 0 then return 0 end
  local i = off
  while i > 1 do
    local b = byte(s, i)
    if b < 128 or b >= 192 then break end
    i = i - 1
  end
  return i - 1
end

function M.NextChar(s, off)
  local len = #s
  if off >= len then return len end
  local i = off + 2
  while i <= len do
    local b = byte(s, i)
    if b < 128 or b >= 192 then break end
    i = i + 1
  end
  return i - 1
end

-- the lines of s, without their line breaks; text ending in a line break ends with an empty line
function M.Lines(s)
  local lines, n, pos = {}, 0, 1
  while true do
    local nl = find(s, "\n", pos, true)
    n = n + 1
    if not nl then lines[n] = sub(s, pos); break end
    lines[n] = sub(s, pos, nl - 1)
    pos = nl + 1
  end
  return lines, n
end

------------------------------------------------------------------------------------------------
-- Syntax coloring
------------------------------------------------------------------------------------------------

-- AARRGGBB for each kind of syntax. The emphasis and code colors follow LibSimpleHTMLMarkdown's
-- defaults, so the editor and the preview agree.
M.colors = {
  heading  = "ffffd100",
  marker   = "ffd08770",
  strong   = "ff00dddd",
  em       = "ff00dd00",
  strongem = "ff80ffd0",
  strike   = "ff808080",
  mark     = "ffffff66",
  code     = "ff66bbbb",
  fence    = "ff4a8a8a",
  link     = "ff3399ff",
  url      = "ff6a8fbf",
  image    = "ffc586c0",
  icon     = "ffc586c0",
  entity   = "ffc586c0",
  html     = "ff8c8c8c",
  quote    = "ffb0b0b0",
  alert    = "ffab7df8",
  footnote = "ff00dddd",
  rule     = "ff8c8c8c",
}

-- raid target names LibSimpleHTMLMarkdown reads in {braces}
local RAID_ICONS = {}
for _, name in ipairs({ "star", "circle", "coin", "diamond", "triangle", "moon", "square", "cross", "x", "skull" }) do
  RAID_ICONS[name] = true
end
for i = 1, 8 do RAID_ICONS["rt" .. i] = true end

-- :shortcode: names that have an icon; Core fills this from the library's config
M.shortcodes = {}

local cache, cacheCount = {}, 0
function M.ClearCache() cache, cacheCount = {}, 0 end

local function free(t, s, e)
  for i = s, e do if t[i] then return false end end
  return true
end

local function paint(t, s, e, color)
  for i = s, e do t[i] = color end
end

local function isWordByte(b)
  return b and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b >= 128)
end

local function isSpaceByte(b)
  return b == 32 or b == 9
end

-- paints each match of pattern from `from` on, that no earlier rule painted and `check` accepts
local function rule(line, t, from, pattern, color, check)
  local pos = from
  while true do
    local s, e = find(line, pattern, pos)
    if not s then return end
    if free(t, s, e) and (not check or check(line, s, e)) then
      paint(t, s, e, color)
      pos = e + 1
    else
      pos = s + 1
    end
  end
end

-- emphasis can't end with a space before its closing delimiter, and _ emphasis can't be inside a word
local function closes(n)
  return function(line, s, e) return not isSpaceByte(byte(line, e - n)) end
end
local function closesOutsideWord(n)
  return function(line, s, e)
    return not isSpaceByte(byte(line, e - n)) and not isWordByte(byte(line, s - 1)) and not isWordByte(byte(line, e + 1))
  end
end

local function inline(line, t, from)
  local C = M.colors

  -- code spans: a run of backticks, to the next run of the same length
  local pos = from
  while true do
    local s, e = find(line, "`+", pos)
    if not s then break end
    local n, p2, closed = e - s + 1, e + 1, nil
    while true do
      local s2, e2 = find(line, "`+", p2)
      if not s2 then break end
      if e2 - s2 + 1 == n then closed = e2; break end
      p2 = e2 + 1
    end
    if closed then
      paint(t, s, closed, C.code)
      pos = closed + 1
    else
      pos = e + 1
    end
  end

  rule(line, t, from, "<https?://[^%s<>]+>", C.link)
  rule(line, t, from, "<[%w%.%+%-_]+@[%w%.%-]+>", C.link)
  rule(line, t, from, "<!%-%-.-%-%->", C.html)
  rule(line, t, from, "</?%a[%w%-]*[^<>]*>", C.html)
  rule(line, t, from, "!%b[]%b()", C.image)
  rule(line, t, from, "!%b[]%b[]", C.image)
  rule(line, t, from, "%[%^[^%]%s]+%]", C.footnote)

  -- [text](url): the text in the link color and the destination in the url color
  pos = from
  while true do
    local s, e, mid = find(line, "%b[]()%b()", pos)
    if not s then break end
    if free(t, s, e) then
      paint(t, s, mid - 1, C.link)
      paint(t, mid, e, C.url)
      pos = e + 1
    else
      pos = s + 1
    end
  end
  rule(line, t, from, "%b[]%b[]", C.link)

  rule(line, t, from, "https?://[^%s<>%)%]]+", C.url)
  rule(line, t, from, "www%.[%w%-]+%.[^%s<>%)%]]+", C.url)

  pos = from
  while true do
    local s, e, name = find(line, "{(%a+%d?)}", pos)
    if not s then break end
    if RAID_ICONS[lower(name)] and free(t, s, e) then paint(t, s, e, C.icon) end
    pos = e + 1
  end

  pos = from
  while true do
    local s, e = find(line, ":[%w_%+%-]+:", pos)
    if not s then break end
    if M.shortcodes[sub(line, s, e)] and free(t, s, e) then
      paint(t, s, e, C.icon)
      pos = e + 1
    else
      pos = e  -- the closing : can open the next shortcode
    end
  end

  rule(line, t, from, "&#?%w+;", C.entity)

  rule(line, t, from, "%*%*%*[^%s%*].-%*%*%*", C.strongem, closes(3))
  rule(line, t, from, "___[^%s_].-___", C.strongem, closesOutsideWord(3))
  rule(line, t, from, "%*%*[^%s%*].-%*%*", C.strong, closes(2))
  rule(line, t, from, "__[^%s_].-__", C.strong, closesOutsideWord(2))
  rule(line, t, from, "%*[^%s%*].-%*", C.em, closes(1))
  rule(line, t, from, "_[^%s_].-_", C.em, closesOutsideWord(1))
  rule(line, t, from, "~~[^%s~].-~~", C.strike)
  rule(line, t, from, "==[^%s=].-==", C.mark)
end

-- writes the line with each painted run in its color, and the rest in `base` (or uncolored)
local function emit(line, t, base)
  local out, n, len, i = {}, 0, #line, 1
  while i <= len do
    local color = t[i] or base
    local j = i
    while j < len and (t[j + 1] or base) == color do j = j + 1 end
    local text = gsub(sub(line, i, j), "|", "||")
    n = n + 1
    out[n] = color and ("|c" .. color .. text .. "|r") or text
    i = j + 1
  end
  return concat(out)
end

local function whole(line, color)
  if line == "" then return "" end
  return "|c" .. color .. gsub(line, "|", "||") .. "|r"
end

-- the display for one line outside a code fence
local function renderLine(line)
  local C = M.colors
  if not find(line, "%S") then return gsub(line, "|", "||") end

  -- headings
  local hashes = line:match("^ ? ? ?(#+)%s") or line:match("^ ? ? ?(#+)$")
  if hashes and #hashes <= 6 then return whole(line, C.heading) end
  if find(line, "^ ? ? ?=+%s*$") then return whole(line, C.heading) end

  -- rules (and setext underlines), and table delimiter rows
  local compact = gsub(line, "%s", "")
  if #compact >= 3 and (find(compact, "^%-+$") or find(compact, "^%*+$") or find(compact, "^_+$")) then
    return whole(line, C.rule)
  end
  if find(line, "|", 1, true) and find(line, "%-%-") and find(line, "^[%s|:%-]+$") then
    return whole(line, C.marker)
  end

  -- link and footnote definitions
  local s, e = find(line, "^ ? ? ?%[%^[^%]]+%]:")
  if s then
    local t = {}
    paint(t, s, e, C.footnote)
    inline(line, t, e + 1)
    return emit(line, t)
  end
  s, e = find(line, "^ ? ? ?%[[^%]]+%]:")
  if s then
    local t = {}
    paint(t, s, e, C.link)
    paint(t, e + 1, #line, C.url)
    return emit(line, t)
  end

  local t, from, base = {}, 1, nil

  -- blockquotes, and the alert that can open one
  local qs, qe = find(line, "^ ? ? ?>[> ]*")
  if qs then
    paint(t, qs, qe, C.marker)
    base = C.quote
    from = qe + 1
    local as, ae = find(line, "^%[!%a+%]", from)
    if as then
      paint(t, as, ae, C.alert)
      from = ae + 1
    end
  end

  -- list markers, task boxes, and definitions
  local ms, me = find(line, "^%s*[%-%*%+]%s", from)
  if not ms then ms, me = find(line, "^%s*%d+[%.%)]%s", from) end
  if not ms then ms, me = find(line, "^%s*:%s", from) end
  if ms then
    local mark = find(line, "%S", ms)
    paint(t, mark, me, C.marker)
    from = me + 1
    local ts, te = find(line, "^%s*%[[ xX]%]", from)
    if ts then
      paint(t, ts, te, C.marker)
      from = te + 1
    end
  end

  inline(line, t, from)

  -- table cell separators: the |s nothing else painted, that aren't escaped
  if find(line, "^%s*|") then
    local pos = from
    while true do
      local pipe = find(line, "|", pos, true)
      if not pipe then break end
      if not t[pipe] and byte(line, pipe - 1) ~= 92 then t[pipe] = C.marker end
      pos = pipe + 1
    end
  end

  return emit(line, t, base)
end

local function cachedLine(line)
  local display = cache[line]
  if not display then
    display = renderLine(line)
    if cacheCount > 4000 then M.ClearCache() end
    cache[line] = display
    cacheCount = cacheCount + 1
  end
  return display
end

-- The display string for plain text: syntax colored when `highlight` is set, else only escaped.
function M.Render(plain, highlight)
  if not highlight then return (gsub(plain, "|", "||")) end
  local C = M.colors
  local lines, n = M.Lines(plain)
  local out = {}
  local fenceChar, fenceLen
  for i = 1, n do
    local line = lines[i]
    if fenceChar then
      local run = line:match("^ ? ? ?(" .. fenceChar .. "+)%s*$")
      if run and #run >= fenceLen then
        out[i] = whole(line, C.fence)
        fenceChar = nil
      else
        out[i] = whole(line, C.code)
      end
    else
      local run = line:match("^ ? ? ?(```+)") or line:match("^ ? ? ?(~~~+)")
      if run then
        fenceChar, fenceLen = sub(run, 1, 1), #run
        out[i] = whole(line, C.fence)
      else
        out[i] = cachedLine(line)
      end
    end
  end
  return concat(out, "\n")
end

