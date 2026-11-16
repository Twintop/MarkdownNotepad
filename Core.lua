-- Saved data, the notes, and the slash commands.
--
-- Every note is kept in the account-wide MarkdownNotepadDB, so any character can open any note.
-- A note's scope says where it's listed: "account" notes are listed for every character, and
-- "character" notes under the character that owns them (and, for the others, under "Other
-- characters"). Which notes each character has pinned on screen, and where, is kept per
-- character in MarkdownNotepadCharDB.

local ADDON, ns = ...
local L = ns.Localization

MarkdownNotepad = ns -- for the key binding, the AddOn compartment, and /dump

ns.name = ADDON
local GetMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = GetMetadata and GetMetadata(ADDON, "Version") or "?"
-- the version with its release type (0.1.0-alpha), as the footer and the News window show it
local releaseType = GetMetadata and GetMetadata(ADDON, "X-ReleaseType")
ns.fullVersion = releaseType and (ns.version .. "-" .. releaseType) or ns.version
ns.LSHM = LibStub and LibStub("LibSimpleHTMLMarkdown-1.0", true)

function ns.Print(fmt, ...)
  print(L["ChatMessage"]:format(select("#", ...) > 0 and fmt:format(...) or fmt))
end

------------------------------------------------------------------------------------------------
-- Events between the parts of the AddOn
------------------------------------------------------------------------------------------------

local listeners = {}

function ns:On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end

function ns:Fire(event, ...)
  for _, fn in ipairs(listeners[event] or {}) do fn(...) end
end

------------------------------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------------------------------

local DB_DEFAULTS = {
  version = 1,
  nextId = 1,
  notes = {},
  characters = {},
  -- the News window: whether it opens for a new version, and the last version it showed
  news = { enabled = true, lastUpdate = "" },
  settings = {
    editorFontSize = 13,
    renderFontSize = 13,
    highlight = true,
    lineNumbers = true,
    showPreview = true,
    showSidebar = true,
    split = 0.5,
    newNoteScope = "account",
    collapsed = { others = true },
    editor = {},
    viewer = { bgAlpha = 0.6, fade = false, fadeAlpha = 0.3, width = 340, height = 280 },
  },
}

local CHAR_DEFAULTS = {
  viewers = {},
}

local function fill(t, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(t[k]) ~= "table" then t[k] = {} end
      fill(t[k], v)
    elseif t[k] == nil then
      t[k] = v
    end
  end
  return t
end
ns.fill = fill

local function OnAddonLoaded()
  local fresh = MarkdownNotepadDB == nil
  MarkdownNotepadDB = fill(MarkdownNotepadDB or {}, DB_DEFAULTS)
  MarkdownNotepadCharDB = fill(MarkdownNotepadCharDB or {}, CHAR_DEFAULTS)
  ns.db, ns.charDB = MarkdownNotepadDB, MarkdownNotepadCharDB
  ns.settings = ns.db.settings
  ns.welcome = fresh
end

local function OnLogin()
  local name, realm = UnitName("player"), GetNormalizedRealmName and GetNormalizedRealmName()
  realm = realm or (GetRealmName() or ""):gsub("[%s%-]", "")
  ns.playerName = name
  ns.playerKey = name .. "-" .. realm
  local _, class = UnitClass("player")
  ns.db.characters[ns.playerKey] = { name = name, realm = GetRealmName(), class = class }

  if ns.welcome then
    ns.Notes:Create(L["WelcomeNoteTitle"], L["WelcomeNoteText"]:format(L["WelcomeNoteTitle"]), "account")
  end

  -- the library's :shortcode: icons, for the editor's coloring and the icon menu
  if ns.LSHM then
    for key in pairs(ns.LSHM.config) do
      if type(key) == "string" and key:match("^:[%w_%+%-]+:$") then ns.Markup.shortcodes[key] = true end
    end
  else
    ns.Print(L["LibraryMissing"])
  end

  ns:Fire("LOGIN")
end

------------------------------------------------------------------------------------------------
-- Notes
------------------------------------------------------------------------------------------------

local Notes = {}
ns.Notes = Notes

function Notes:Get(id)
  return id and ns.db.notes[id]
end

-- a note title: one line, without the | that would start a UI escape sequence wherever it's shown
function Notes.CleanTitle(title)
  title = (title or ""):gsub("[\r\n|]", " "):match("^%s*(.-)%s*$")
  if title == "" then title = L["Untitled"] end
  return title
end

function Notes:Create(title, text, scope)
  local db = ns.db
  local id = "n" .. db.nextId
  db.nextId = db.nextId + 1
  local now = time()
  db.notes[id] = {
    id = id,
    title = Notes.CleanTitle(title),
    text = text or "",
    scope = scope == "character" and "character" or "account",
    owner = scope == "character" and ns.playerKey or nil,
    created = now,
    modified = now,
  }
  ns:Fire("NOTE_SAVED", id)
  return db.notes[id]
end

-- Saves a note's title, text, and scope. A note made a character note belongs to the character
-- that made it one; a character note that stays one keeps its owner.
function Notes:Save(id, title, text, scope)
  local note = self:Get(id)
  if not note then return end
  note.title = Notes.CleanTitle(title)
  note.text = text or ""
  if scope ~= note.scope then
    note.scope = scope == "character" and "character" or "account"
    note.owner = note.scope == "character" and ns.playerKey or nil
  end
  note.modified = time()
  ns:Fire("NOTE_SAVED", id)
  return note
end

-- a title for a copy of a note titled `title`: "Title (copy)", or "(copy 2)" and on when that's
-- taken. A copy of a copy counts on from the same title instead of adding another "(copy)".
function Notes:CopyTitle(title)
  local base = Notes.CleanTitle(title):gsub("%s*%(copy%s*%d*%)$", "")
  local taken = {}
  for _, note in pairs(ns.db.notes) do taken[note.title:lower()] = true end
  local candidate, n = base .. " (copy)", 2
  while taken[candidate:lower()] do
    candidate = ("%s (copy %d)"):format(base, n)
    n = n + 1
  end
  return candidate
end

function Notes:Delete(id)
  if not ns.db.notes[id] then return end
  ns.db.notes[id] = nil
  ns:Fire("NOTE_DELETED", id)
end

-- "Account", or the name of the character that owns a character note
function Notes:OwnerLabel(note)
  if note.scope ~= "character" then return L["Account"] end
  if note.owner == ns.playerKey then return ns.playerName end
  return note.owner or "?"
end

-- a character's name in its class color
function Notes:CharacterLabel(key)
  local info = ns.db.characters[key]
  local name = key == ns.playerKey and ns.playerName or key
  local color = info and info.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.class]
  if color then return ("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, name) end
  return name
end

local function byTitle(a, b)
  local ta, tb = a.title:lower(), b.title:lower()
  if ta ~= tb then return ta < tb end
  return a.id < b.id
end

-- The notes in the sidebar's groups: account notes, this character's, and each other
-- character's. With a filter, only the notes whose title or text holds it.
function Notes:Groups(filter)
  filter = filter and filter:lower()
  if filter == "" then filter = nil end
  local account, mine, others = {}, {}, {}
  for _, note in pairs(ns.db.notes) do
    if not filter or note.title:lower():find(filter, 1, true) or note.text:lower():find(filter, 1, true) then
      if note.scope ~= "character" then
        account[#account + 1] = note
      elseif note.owner == ns.playerKey then
        mine[#mine + 1] = note
      else
        local owner = note.owner or "?"
        others[owner] = others[owner] or {}
        table.insert(others[owner], note)
      end
    end
  end
  table.sort(account, byTitle)
  table.sort(mine, byTitle)
  local otherList = {}
  for owner, notes in pairs(others) do
    table.sort(notes, byTitle)
    otherList[#otherList + 1] = { owner = owner, notes = notes }
  end
  table.sort(otherList, function(a, b) return a.owner < b.owner end)
  return {
    { key = "account", label = L["Account"], notes = account },
    { key = "character", label = Notes:CharacterLabel(ns.playerKey), notes = mine },
    { key = "others", label = L["OtherCharacters"], children = otherList },
  }
end

-- the note a [link](note:Title) points to: by its title, ignoring case, preferring an account
-- note, then this character's, then another character's
function Notes:FindByTitle(title)
  title = Notes.CleanTitle(title):lower()
  local best, bestRank
  for _, note in pairs(ns.db.notes) do
    if note.title:lower() == title then
      local rank = note.scope ~= "character" and 1 or (note.owner == ns.playerKey and 2 or 3)
      if not best or rank < bestRank or (rank == bestRank and note.id < best.id) then best, bestRank = note, rank end
    end
  end
  return best
end

------------------------------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------------------------------

function ns:ToggleEditor()
  ns.Editor:Toggle()
end

local function ParseTitleArg(rest)
  local note = rest ~= "" and Notes:FindByTitle(rest)
  if not note then ns.Print(L["NoNoteTitled"], ns.Markup.Escape(rest)) end
  return note
end

local HELP = {
  "SlashHelpToggle", "SlashHelpNew", "SlashHelpEdit", "SlashHelpShow", "SlashHelpHide", "SlashHelpUnlock",
  "SlashHelpList", "SlashHelpReset", "SlashHelpNews",
}

SLASH_MARKDOWNNOTEPAD1 = "/mdn"
SLASH_MARKDOWNNOTEPAD2 = "/mdnotes"
SlashCmdList.MARKDOWNNOTEPAD = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "" or cmd == "toggle" then
    ns.Editor:Toggle()
  elseif cmd == "new" then
    ns.Editor:Show()
    ns.Editor:NewNote()
  elseif cmd == "edit" then
    local note = ParseTitleArg(rest)
    if note then ns.Editor:Show(); ns.Editor:LoadNote(note.id) end
  elseif cmd == "show" or cmd == "pin" then
    local note = ParseTitleArg(rest)
    if note then ns.Viewer:Open(note.id) end
  elseif cmd == "hide" then
    ns.Viewer:CloseAll()
  elseif cmd == "news" then
    ns.News:Toggle()
  elseif cmd == "unlock" then
    ns.Print(L["SlashUnlocked"], ns.Viewer:UnlockAll())
  elseif cmd == "list" then
    for _, group in ipairs(Notes:Groups()) do
      local lists = group.children or { { notes = group.notes } }
      for _, sub in ipairs(lists) do
        if #sub.notes > 0 then
          local titles = {}
          for i, note in ipairs(sub.notes) do titles[i] = note.title end
          ns.Print("%s: %s", sub.owner and Notes:CharacterLabel(sub.owner) or group.label, table.concat(titles, ", "))
        end
      end
    end
  elseif cmd == "reset" then
    ns.Editor:ResetPosition()
    ns.Viewer:ResetPositions()
  else
    ns.Print(L["SlashHelpHeader"])
    for _, key in ipairs(HELP) do print("  " .. L[key]) end
  end
end

-- the key binding (Bindings.xml) and the AddOn compartment on the minimap
BINDING_HEADER_MARKDOWNNOTEPAD = L["MarkdownNotepad"]
BINDING_NAME_MARKDOWNNOTEPAD_TOGGLE = L["BindingToggleEditor"]

function MarkdownNotepad_OnAddonCompartmentClick()
  ns.Editor:Toggle()
end

function MarkdownNotepad_OnAddonCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
  GameTooltip:SetText(L["MarkdownNotepad"], 1, 1, 1)
  GameTooltip:AddLine(L["CompartmentTooltip"], 0.8, 0.8, 0.8, true)
  GameTooltip:Show()
end

function MarkdownNotepad_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end

------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    OnAddonLoaded()
    self:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    OnLogin()
  elseif event == "PLAYER_LOGOUT" then
    ns:Fire("LOGOUT")
  end
end)
