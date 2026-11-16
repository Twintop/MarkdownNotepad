# Markdown Notepad

Notes for *World of Warcraft*, written in Markdown and rendered in game with
[LibSimpleHTMLMarkdown](https://github.com/Twintop/LibSimpleHTMLMarkdown).

Found a bug, or have an idea? [Open an issue](https://github.com/Twintop/MarkdownNotepad/issues).

## Features

- **An editor** with a monospace font (JetBrains Mono), line numbers, syntax coloring, undo and
  redo, and a live preview beside it that you can hide. The window moves and resizes, and the
  divider between the editor and the preview drags.
- **A toolbar** that formats the selection or inserts at the cursor: headings, bold, italic,
  strikethrough, highlight, code, code blocks, lists, task lists, quotes, rules, tables, links,
  images, raid target and role icons, alerts, footnotes, definitions, and links to other notes.
- **Account or character notes.** Every note is saved account-wide, so any character can open
  any note. An account note is listed for all your characters; a character note is listed for
  the character it belongs to, and your other characters find it under *Other characters*.
- **Pinned notes**: any note in a window of its own that stays on screen while you play. Unlocked,
  it has a title bar (its title, and edit, lock, settings, and close) to move it by, and a size
  grip. Locked with the padlock, it's only the rendered note on a background: it stays in place,
  and clicks go through it to the game. The mouse wheel still scrolls it; hold Alt over it to use
  it, or right-click *Unpin* in the editor for its settings. Each one has its own background
  opacity, and can fade when the mouse isn't over it. Pinned notes come back at your next login.
- **Game links**: shift-click a spell or item while you type (or drag one onto the editor) to
  insert `[Fireball](spell:133)`, which shows the game's tooltip. `[Raid plan](note:Raid Plan)`
  links to another note.
- **Save Copy** saves a note, with any changes you haven't saved, as a new note ("Title (copy)")
  and edits that one; the note you started from keeps what it had at its last save.
- Unsaved changes are kept through a logout or `/reload`.
- Along the bottom of the editor: the version, and **News** (what's new, which also opens by
  itself the first time a new version runs), **GitHub Issues**, **Ko-fi**, and **Discord**.

## Using it

Open the editor with `/mdn`, a key binding (*Key Bindings > AddOns*), or the AddOn compartment
on the minimap.

| Command | Does |
| --- | --- |
| `/mdn` | Show or hide the editor |
| `/mdn new` | Start a new note |
| `/mdn edit <title>` | Open a note in the editor |
| `/mdn show <title>` | Pin a note on screen |
| `/mdn hide` | Close every pinned note |
| `/mdn unlock` | Make every pinned note movable and clickable again |
| `/mdn list` | List your notes |
| `/mdn reset` | Put the windows back in the middle of the screen |
| `/mdn news` | Show what's new |

| Key | Does |
| --- | --- |
| Ctrl-S | Save |
| Ctrl-Shift-S | Save a copy |
| Ctrl-Z, Ctrl-Y | Undo, redo |
| Ctrl-B, Ctrl-I, Ctrl-K | Bold, italic, link |
| Tab, Shift-Tab | Indent, outdent (nests list items) |
| Enter in a list | Starts the next item; on an empty item, ends the list |

## Development

`tests/run_tests.py` tests the text model and the formatting actions, replays random typing
sessions through the editor against a reference, and loads the whole AddOn against a mock of
the WoW API to drive its windows. It needs Python and [lupa](https://pypi.org/project/lupa/)
(`pip install lupa`). With the Ketho WoW API extension for VS Code installed, the mock accepts
only widget methods the real API has.

Text shown to players is in `Localization/`: `enUS.lua` has every string in English, under a
key the code looks it up by (`L["SaveCopy"]`), and each locale's file replaces the ones it
translates. The tests check that every key the code uses has an English text, and that every
English text is used.

LibSimpleHTMLMarkdown is embedded in `Libs/`. `build/README.md` covers the checks every push
runs, updating the library, and releasing.

The editor font is JetBrains Mono, under the SIL Open Font License (`Media/Fonts/JetBrainsMono-OFL.txt`).
