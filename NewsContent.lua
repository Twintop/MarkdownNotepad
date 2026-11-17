local _, ns = ...

-- Changelog shown by the News window (News.lua renders it). Markdown; newest release first.
ns.NewsContent = [====[

# 1.0.1-release (2026-11-17)

## Notes

- **Autosave**: your changes are saved a moment after you stop typing, and when you open another note, close the editor, or log out. Turn off *Autosave* in Settings to save only when you press Save, as before.
- **Line breaks as you typed them**: each line break in a note shows in the preview and pinned notes, and a blank line is an empty line, so pasted plain text looks as it did. Turn off *Keep line breaks* in Settings for Markdown's own rule, where lines join into one paragraph unless one ends with two spaces.
- With autosave on, **Save Copy** saves the note before copying it.
- The welcome note, if you haven't changed it, gets this version's text, written for line breaks that show.

## Fixes

- On WoW Forever, the editor and preview now show the first time the editor opens, instead of an empty window until a note was pinned.
- Updated LibSimpleHTMLMarkdown, the library that renders notes, to 1.0.5.

# 1.0.0-release (2026-11-16)

Initial release of the addon!

## Notes

- Write notes in Markdown, and see them rendered beside the editor as you type.
- Notes are saved for your whole account, so any character can open any of them. An **account** note is listed for all your characters; a **character** note is listed for the character it belongs to, and your other characters find it under *Other characters*.
- **Save Copy** saves a note, with changes you haven't saved, as a new note.
- Changes you haven't saved are kept through a logout or `/reload`.

## The editor

- A monospace font, line numbers, syntax coloring, and undo (Ctrl-Z) and redo (Ctrl-Y).
- A toolbar that formats what you select, or inserts at the cursor: headings, bold, italic, lists, quotes, tables, links, images, raid target and role icons, alerts, and more.
- Shift-click a spell or item while you type to link it.
- Enter in a list starts the next item; Tab and Shift-Tab indent and outdent.

## Pinned notes

- **Pin** a note to keep it on screen while you play, in a window of its own with a title bar to move it by. Each pinned note has its own background opacity, and can fade when the mouse isn't over it.
- Lock it with the padlock in its title bar, and it's only the note on a background: it stays in place, and clicks go through it to the game. The mouse wheel still scrolls it; hold Alt over it to use it again.
- Pinned notes come back at your next login.

Type `/mdn help` for the commands.
]====]
