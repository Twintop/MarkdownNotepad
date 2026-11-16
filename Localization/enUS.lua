local _, ns = ...
local L = ns.Localization

-- General strings
L["MarkdownNotepad"] = "Markdown Notepad"
L["ChatMessage"] = "|cFF33BBFFMarkdown Notepad|r: %s"
L["Account"] = "Account"

-- Core.lua
L["OtherCharacters"] = "Other characters"
L["Untitled"] = "Untitled"
L["LibraryMissing"] = "LibSimpleHTMLMarkdown is missing, so notes are shown as plain text."
L["NoNoteTitled"] = "No note is titled \"%s\"."
L["SlashHelpHeader"] = "Commands:"
L["SlashHelpToggle"] = "|cFFFFFF00/mdn|r - show or hide the editor"
L["SlashHelpNew"] = "|cFFFFFF00/mdn new|r - start a new note"
L["SlashHelpEdit"] = "|cFFFFFF00/mdn edit <title>|r - open a note in the editor"
L["SlashHelpShow"] = "|cFFFFFF00/mdn show <title>|r - pin a note on screen"
L["SlashHelpHide"] = "|cFFFFFF00/mdn hide|r - close every pinned note"
L["SlashHelpUnlock"] = "|cFFFFFF00/mdn unlock|r - make every pinned note movable and clickable again"
L["SlashHelpList"] = "|cFFFFFF00/mdn list|r - list your notes"
L["SlashHelpReset"] = "|cFFFFFF00/mdn reset|r - put the windows back in the middle of the screen"
L["SlashHelpNews"] = "|cFFFFFF00/mdn news|r - show what's new"
L["SlashUnlocked"] = "Unlocked %d pinned notes."
L["BindingToggleEditor"] = "Show or hide the editor"
L["CompartmentTooltip"] = "Click to show or hide the editor."

-- The note made the first time the AddOn loads. %s is its title, for the link to itself.
L["WelcomeNoteTitle"] = "Welcome to Markdown Notepad"
L["WelcomeNoteText"] = [[
# Welcome to Markdown Notepad

Write in **Markdown** on the left, and see it rendered on the right. *Save* keeps the note; it's
listed in the sidebar for every character (an **account** note), or only for this character (a
**character** note).

## Formatting

- **Bold**, *italic*, ~~struck~~, ==highlighted==, and `code`
- [ ] A task, and a done one:
- [x] Install Markdown Notepad
1. Numbered
2. Lists

> [!TIP]
> Select some text and press a toolbar button to format it, or press Ctrl-B, Ctrl-I, or Ctrl-K.

| Shortcut | Does |
| -------- | ---- |
| Ctrl-S   | Save |
| Ctrl-Z   | Undo |

## World of Warcraft

{rt1} {rt2} {rt3} {rt4} :tank: :healer: :dps: :check: :gold:

Shift-click a spell or item while you type to link it: [Hearthstone](item:6948). Link another
note by its title: [this note](note:%s).

Press **Pin** to keep a note on screen while you play. Its title bar has its settings (background
opacity, and fading when the mouse isn't over it) and a padlock: a locked note stays in place and
lets clicks through to the game. Hold Alt over it to use it again.
]]

-- Render.lua
L["LinkCopyPopup"] = "Press Ctrl-C to copy the link to %s."
L["NoteLinkTooltip"] = "Click to pin this note on screen."
L["NoteLinkMissing"] = "There's no note with this title."

-- Editor.lua
L["FooterNews"] = "News"
L["FooterGitHubIssues"] = "GitHub Issues"
L["FooterKofi"] = "Donate on Ko-fi"
L["FooterDiscord"] = "Discord"
L["UnsavedPrompt"] = "Save your changes to \"%s\"?"
L["DontSave"] = "Don't Save"
L["DeletePrompt"] = "Delete \"%s\"? This can't be undone."
L["ToolHeading1"] = "Heading 1"
L["ToolHeading2"] = "Heading 2"
L["ToolHeading3"] = "Heading 3"
L["ToolBold"] = "Bold"
L["ToolItalic"] = "Italic"
L["ToolStrikethrough"] = "Strikethrough"
L["ToolHighlight"] = "Highlight"
L["ToolCode"] = "Code"
L["ToolCodeBlock"] = "Code block"
L["ToolBulletedList"] = "Bulleted list"
L["ToolNumberedList"] = "Numbered list"
L["ToolTaskList"] = "Task list"
L["ToolQuote"] = "Quote"
L["ToolRule"] = "Horizontal rule"
L["ToolTableLabel"] = "Table"
L["ToolTable"] = "Table"
L["ToolLinkLabel"] = "Link"
L["ToolLink"] = "Link"
L["ToolImageLabel"] = "Img"
L["ToolImage"] = "Image"
L["ToolImageTooltip"] = "A texture, by its path. Add a size (32x32) and left, center, or right."
L["ToolIconsLabel"] = "Icons"
L["ToolIcons"] = "Icons"
L["ToolIconsTooltip"] = "Raid target icons, role icons, and other shortcodes."
L["ToolMoreLabel"] = "More"
L["ToolMore"] = "More"
L["ToolMoreTooltip"] = "Links to notes, spells, and items; alerts; footnotes; and definitions."
L["PlaceholderBold"] = "bold text"
L["PlaceholderItalic"] = "italic text"
L["PlaceholderStruck"] = "struck text"
L["PlaceholderHighlighted"] = "highlighted text"
L["PlaceholderCode"] = "code"
L["MoreNoteLink"] = "Link to a note"
L["MoreSpellLink"] = "Spell link"
L["MoreItemLink"] = "Item link"
L["MoreSpellIcon"] = "Spell icon"
L["MoreAtlas"] = "Atlas"
L["MoreAlertNote"] = "Note"
L["MoreAlertTip"] = "Tip"
L["MoreAlertImportant"] = "Important"
L["MoreAlertWarning"] = "Warning"
L["MoreAlertCaution"] = "Caution"
L["MoreFootnote"] = "Footnote"
L["MoreDefinition"] = "Definition"
L["Preview"] = "Preview"
L["PreviewTooltip"] = "Show the rendered note beside the editor."
L["Notes"] = "Notes"
L["NotesTooltip"] = "Show the list of notes."
L["NewNote"] = "New Note"
L["NoNotesYet"] = "No notes yet"
L["AccountNote"] = "Account note"
L["CharacterNoteOwner"] = "Character note: %s"
L["SavedAt"] = "Saved %s"
L["RowPinTooltip"] = "Show this note in its own window."
L["TitlePlaceholder"] = "Title"
L["CharacterScope"] = "Character: %s"
L["ScopeTooltipTitle"] = "Saved for"
L["ScopeTooltipCharacter"] = "A character note is listed for the character it belongs to. Your other characters find it under Other characters."
L["ScopeTooltipAccount"] = "An account note is listed for all your characters. Click to make it a character note."
L["SaveCopy"] = "Save Copy"
L["SaveCopyTooltip"] = "Save this note, with any changes you haven't saved, as a new note, and edit that one. The note you started from stays as it was last saved. (Ctrl-Shift-S)"
L["Pin"] = "Pin"
L["PinTooltip"] = "Save this note and show it in its own window, which stays on screen while you play."
L["Unpin"] = "Unpin"
L["UnpinTooltip"] = "Close this note's window. Right-click for the window's settings."
L["DeleteTooltip"] = "Delete this note."
L["StatusSaved"] = "Saved"
L["StatusUnsaved"] = "Unsaved changes"
L["StatusRestored"] = "Unsaved changes restored"
L["StatusNewNote"] = "New note"
L["StatusLine"] = "%s   ·   Ln %d, Col %d   ·   %d characters"
L["SettingsEditor"] = "Editor"
L["SettingsTextSize"] = "Text size"
L["SettingsSyntaxColoring"] = "Syntax coloring"
L["SettingsLineNumbers"] = "Line numbers"
L["SettingsNewNotesCharacter"] = "New notes are character notes"
L["SettingsPreview"] = "Preview and pinned notes"
L["SettingsNewlyPinned"] = "Newly pinned notes"
L["SettingsFadeThem"] = "Fade when the mouse isn't over them"

-- Editor.lua and Viewer.lua
L["BackgroundOpacity"] = "Background opacity"
L["FadedOpacity"] = "Faded opacity"

-- Viewer.lua
L["ViewerCloseTooltip"] = "Unpin this note. It stays saved."
L["ViewerEditTooltip"] = "Open this note in the editor."
L["ViewerHoldAlt"] = "Hold Alt to use this window"
L["Lock"] = "Lock"
L["Unlock"] = "Unlock"
L["ViewerLockedTooltip"] = "It's locked: it can't be moved or resized, and clicks go through it to the game. Click to unlock it."
L["ViewerUnlockedTooltip"] = "Lock it in place: it can't be moved or resized, and clicks go through it to the game. Hold Alt over it to use it again."
L["ViewerFade"] = "Fade when the mouse isn't over it"
L["ViewerLockInPlace"] = "Lock in place"
L["ViewerLockInPlaceTooltip"] = "A locked window can't be moved or resized, and clicks go through it to the game; the mouse wheel still scrolls it. Hold Alt over it to use its buttons, right-click Unpin in the editor, or type /mdn unlock."

-- News.lua
L["NewsHeader"] = "Markdown Notepad Updates"
L["NewsCheckboxShowOnNewVersion"] = "Show on new version release"
L["NewsCheckboxShowOnNewVersionTooltip"] = "Show this update popup whenever a new version of Markdown Notepad is released."
L["NewsHyperlinkIssueOnGitHub"] = "issue %s on GitHub"
