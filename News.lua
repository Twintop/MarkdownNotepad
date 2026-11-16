-- The News window: what's new in each version (NewsContent.lua), rendered from its markdown. It
-- opens by itself the first time a new version runs, unless the player turned that off. As
-- TwintopQOL's does, with this AddOn's look.

local _, ns = ...
local L, W, R = ns.Localization, ns.Widgets, ns.Render

local N = {}
ns.News = N

local frame

-- links in the news: #123 is that issue on GitHub; anything else works as it does in a note
local function OnHyperlinkClick(html, link, text)
  if link:match("^#%d+$") then
    ns:ShowUrl(L["NewsHyperlinkIssueOnGitHub"]:format(link), L["GitHubIssuesUrl"] .. link:sub(2))
  else
    R.OnHyperlinkClick(html, link, text)
  end
end

local function CreateMainFrame()
  if frame then return end

  frame = CreateFrame("Frame", "MarkdownNotepadNews", UIParent, "BackdropTemplate")
  W.Backdrop(frame, W.colors.bg, W.colors.border)
  frame:SetSize(750, 505)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  W.Movable(frame)
  tinsert(UISpecialFrames, "MarkdownNotepadNews") -- Escape closes it

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText(L["NewsHeader"])

  local closeX = W.GlyphButton(frame, "×", 20, function() N:Hide() end, L["Close"])
  closeX:SetPoint("TOPRIGHT", -6, -6)

  local close = W.Button(frame, L["Close"], function() N:Hide() end, { width = 100, height = 22 })
  close:SetPoint("BOTTOMRIGHT", -10, 8)

  local showAgain = W.Check(frame, L["NewsCheckboxShowOnNewVersion"],
    function() return ns.db.news.enabled end,
    function(value) ns.db.news.enabled = value end,
    L["NewsCheckboxShowOnNewVersionTooltip"])
  showAgain:SetPoint("BOTTOMLEFT", 12, 10)
  frame.showAgain = showAgain

  -- the reader: the news rendered in a scroll frame
  local scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", 14, -40)
  scroll:SetPoint("BOTTOMRIGHT", -24, 40)
  local html = CreateFrame("SimpleHTML", nil, scroll)
  html:SetSize(700, 1)
  scroll:SetScrollChild(html)
  R:Setup(html)
  html:SetScript("OnHyperlinkClick", OnHyperlinkClick)
  W.ScrollBar(scroll, 48)
  scroll:SetScript("OnSizeChanged", function(_, width)
    html:SetWidth(width)
    R:SetMarkdown(html, ns.NewsContent or "")
  end)
  frame.html = html
  R:SetMarkdown(html, ns.NewsContent or "")
end

------------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------------

function N:Hide()
  if frame then frame:Hide() end
end

-- opens the window, marking the running version as seen
function N:Show()
  CreateMainFrame()
  ns.db.news.lastUpdate = ns.fullVersion
  frame.showAgain:Refresh()
  frame:Show()
  frame:Raise()
end

function N:Toggle()
  if frame and frame:IsShown() then self:Hide() else self:Show() end
end

-- shows the window when a version the player hasn't seen is running
function N:Init()
  if ns.db.news.enabled and ns.db.news.lastUpdate ~= ns.fullVersion then self:Show() end
end

ns:On("LOGIN", function()
  -- Wait out the login sequence, which closes UISpecialFrames (this window among them).
  C_Timer.After(0, function()
    C_Timer.After(1, function() N:Init() end)
  end)
end)
