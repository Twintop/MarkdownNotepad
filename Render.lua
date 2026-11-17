-- Rendering markdown into SimpleHTML frames, for the editor's preview and the pinned notes, and
-- what their links do when clicked.

local ADDON, ns = ...
local L = ns.Localization
local R = {}
ns.Render = R

-- LibSimpleHTMLMarkdown's defaults, with a bullet that reads better than *
local renderer = ns.LSHM and ns.LSHM:New({
  list_marker = "|TInterface\\COMMON\\Indicator-Yellow.PNG:0|t",
})

local fonts = {
  p  = CreateFont("MarkdownNotepadHTMLFont"),
  h1 = CreateFont("MarkdownNotepadHTMLFontH1"),
  h2 = CreateFont("MarkdownNotepadHTMLFontH2"),
  h3 = CreateFont("MarkdownNotepadHTMLFontH3"),
}
local SCALE = { p = 1, h1 = 1.75, h2 = 1.4, h3 = 1.15 }
local COLORS = {
  p  = { 0.92, 0.92, 0.92 },
  h1 = { 1.00, 0.82, 0.00 },
  h2 = { 1.00, 0.82, 0.00 },
  h3 = { 0.45, 0.80, 1.00 },
}

local frames = setmetatable({}, { __mode = "k" }) -- every SimpleHTML set up here, and its text

local function FontSize()
  return ns.settings and ns.settings.renderFontSize or 13
end

-- Notes keep the line breaks typed in them, as chat does, unless the setting is off. (The news
-- is written in Markdown, whose lines join into paragraphs.)
local KEEP_BREAKS = { hard_breaks = true }
local function KeepBreaks(html)
  return html.mdnNote and not (ns.settings and ns.settings.keepLineBreaks == false)
end

-- sizes the fonts to the setting, and renders every frame again at the new size
function R:UpdateFonts()
  local size = FontSize()
  local file = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  for tag, font in pairs(fonts) do
    font:SetFont(file, math.floor(size * SCALE[tag] + 0.5), "")
    font:SetShadowOffset(1, -1)
    font:SetShadowColor(0, 0, 0, 0.9)
    font:SetSpacing(tag == "p" and 2 or 0)
  end
  self:RenderAll()
end

-- renders every frame again, after a setting changed
function R:RenderAll()
  for html, text in pairs(frames) do self:SetMarkdown(html, text) end
end
R:UpdateFonts()
ns:On("LOGIN", function() R:UpdateFonts() end)

-- the HTML for text: the library's, or the text as plain paragraphs without it. keepBreaks
-- shows every line break in the text.
function R.ToHTML(text, keepBreaks)
  if renderer then return renderer:ToHTML(text, keepBreaks and KEEP_BREAKS or nil) end
  local escaped = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("|", "||"):gsub("\n", "<br/>")
  return "<html><body><p>" .. escaped .. "</p></body></html>"
end

-- gets a SimpleHTML frame ready to show markdown; note for a frame showing notes
function R:Setup(html, note)
  html.mdnNote = note and true or nil
  for tag, font in pairs(fonts) do
    html:SetFontObject(tag, font)
    html:SetTextColor(tag, unpack(COLORS[tag]))
  end
  html:SetHyperlinkFormat("|cff3399ff|H%s|h%s|h|r")
  if html.SetHyperlinksEnabled then html:SetHyperlinksEnabled(true) end
  html:SetScript("OnHyperlinkClick", R.OnHyperlinkClick)
  html:SetScript("OnHyperlinkEnter", R.OnHyperlinkEnter)
  html:SetScript("OnHyperlinkLeave", R.OnHyperlinkLeave)
end

-- Shows text in html, and sizes html's height to it (its width is the caller's). An unchanged
-- text at an unchanged width and settings isn't laid out again.
function R:SetMarkdown(html, text)
  text = text or ""
  frames[html] = text
  local width, size, breaks = html:GetWidth(), FontSize(), KeepBreaks(html)
  if html.mdnText == text and html.mdnWidth == width and html.mdnSize == size and html.mdnBreaks == breaks then
    return
  end
  html.mdnText, html.mdnWidth, html.mdnSize, html.mdnBreaks = text, width, size, breaks
  html:SetText(R.ToHTML(text, breaks))
  html:SetHeight(math.max(html:GetContentHeight() or 0, 1))
end

-- lays html out again at its current width
function R:Relayout(html)
  html.mdnWidth = nil
  self:SetMarkdown(html, frames[html] or "")
end

------------------------------------------------------------------------------------------------
-- Links
------------------------------------------------------------------------------------------------

StaticPopupDialogs.MARKDOWNNOTEPAD_URL = {
  text = L["LinkCopyPopup"],
  button1 = L["OK"],
  hasEditBox = true,
  editBoxWidth = 320,
  wide = true,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  OnShow = function(self, data)
    local editBox = (self.GetEditBox and self:GetEditBox()) or self.editBox or self.EditBox
    editBox:SetText(data.url)
    editBox:HighlightText()
    editBox:SetFocus()
  end,
  EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

-- shows a popup with a url selected, ready to copy; title is what it's a link to
function ns:ShowUrl(title, url)
  StaticPopup_Show("MARKDOWNNOTEPAD_URL", title, nil, { url = url })
end

-- the full game link for a spell:, item:, currency:, or achievement: link, for chat
local function GameLink(kind, id)
  id = tonumber(id)
  if not id then return end
  local ok, link = pcall(function()
    if kind == "spell" then
      return (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)) or (GetSpellLink and GetSpellLink(id))
    elseif kind == "item" then
      return select(2, (C_Item and C_Item.GetItemInfo or GetItemInfo)(id))
    elseif kind == "currency" then
      return C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink and C_CurrencyInfo.GetCurrencyLink(id, 0)
    elseif kind == "achievement" then
      return GetAchievementLink and GetAchievementLink(id)
    end
  end)
  return ok and link or nil
end

local function InsertIntoChat(link)
  if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
  if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
end

function R.OnHyperlinkClick(html, link, text)
  local kind, rest = link:match("^(%a+):(.*)$")
  if kind == "note" then
    local note = ns.Notes:FindByTitle(rest)
    if note then
      ns.Viewer:Open(note.id)
    else
      ns.Print(L["NoNoteTitled"], ns.Markup.Escape(rest))
    end
  elseif link:match("^https?://") or link:match("^www%.") or kind == "mailto" then
    ns:ShowUrl(text, link)
  elseif kind and ns.LSHM and ns.LSHM.game_link_types[kind] then
    -- shift-click puts the game's own link into chat, as anywhere else
    if IsModifiedClick("CHATLINK") then
      local full = GameLink(kind, rest:match("^%d+"))
      if full then InsertIntoChat(full) end
    end
  elseif link:match("^#") then
    -- SimpleHTML can't scroll to a heading, so a [link](#heading) does nothing
  end
end

function R.OnHyperlinkEnter(html, link)
  if ns.LSHM and ns.LSHM:ShowLinkTooltip(html, link) then return end
  local kind, rest = link:match("^(%a+):(.*)$")
  if kind == "note" then
    GameTooltip:SetOwner(html, "ANCHOR_CURSOR")
    local note = ns.Notes:FindByTitle(rest)
    GameTooltip:SetText(note and note.title or rest, 1, 1, 1)
    GameTooltip:AddLine(note and L["NoteLinkTooltip"] or L["NoteLinkMissing"], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  elseif kind or link:match("^www%.") then
    GameTooltip:SetOwner(html, "ANCHOR_CURSOR")
    GameTooltip:SetText(link, 0.6, 0.8, 1, 1, true)
    GameTooltip:Show()
  end
end

function R.OnHyperlinkLeave()
  GameTooltip:Hide()
end
