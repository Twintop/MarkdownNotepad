# Build tooling

The scripts here need only PowerShell (5.1 or 7). The tests need Python with
[lupa](https://pypi.org/project/lupa/) (`pip install lupa`), and the type check needs lua-language-server.

| Task | Command |
| --- | --- |
| Run the tests | `python tests\run_tests.py` |
| Type-check with LuaLS against the baseline | `.\build\luals-check.ps1` (finds the VS Code extensions; `-UpdateBaseline` rewrites it) |
| Build a release zip locally (into `dist\`) | `.\build\stage.ps1` |
| Same, stamping a version | `.\build\stage.ps1 -Version 1.0.1 -ReleaseType beta01` |

## Tests

`tests\run_tests.py` runs the addon under Lua 5.1, against a mock of the WoW API (`tests\mock_wow.lua`):

- unit tests of the text model (`Markup.lua`) and the formatting actions (`Actions.lua`);
- random typing sessions through the editor, each step checked against the same edit made to a plain string
  (`FUZZ_SESSIONS` and `FUZZ_STEPS` set how many);
- a smoke test that loads the whole addon in TOC order and drives its windows, then loads it again with the saved
  variables it ended with, as a `/reload` would;
- checks that every file the TOC loads exists, that every image and font the code names is in `Media`, and that
  every string the code looks up has an English text.

With Ketho's WoW API annotations (the VS Code extension, or the `Annotations\Core` folder the `WOW_API_ANNOTATIONS`
variable names) the mock's widgets have only the methods the real ones do, so a misspelled method fails a test.

## Pull request checks

`.github\workflows\checks.yml` runs on every pull request and branch push, and `release.yml` calls it before
staging a tag. Each check is its own job:

- **Lua syntax:** `luac5.1 -p` on every tracked Lua file, and every TOC entry exists.
- **Tests:** `tests\run_tests.py`, with Ketho's WoW API annotations pinned in the workflow to the version of the
  VS Code extension.
- **LuaLS:** `luals-check.ps1` with lua-language-server and Ketho's WoW API annotations, pinned in the workflow
  to the versions of the VS Code extensions. It fails on any Error, Warning, or Information diagnostic missing
  from `build\luals\baseline.json`, which matches on file, code, and message, not line.

The LuaLS settings for the check live in `build\luals\config.json`, a copy of the `Lua.*` keys in
`.vscode\settings.json` (which isn't tracked). Change both together. When a fix clears a baseline entry, the
check says so; run `.\build\luals-check.ps1 -UpdateBaseline` and commit the smaller baseline. Add to the
baseline only a warning that can't be fixed in code.

## The library

`Libs\LibSimpleHTMLMarkdown` is LibSimpleHTMLMarkdown, copied from its newest release tag: its `.lua`,
`LICENSE.MD`, and `README.md`, with an XML that loads only the `.lua` (not its demo, showcase, or AceGUI widget).
To update it, copy those three files from the new tag. `Libs\LibStub.lua` is LibStub.

## Releasing

Before tagging, stamp `## Version:` and `## X-ReleaseDate:` in `MarkdownNotepad.toc` and add the release's
section to the top of `NewsContent.lua`; the packager rewrites none of them. Then push a tag whose version matches
the TOC: `1.0.0-release`, `1.0.0-beta01`, or `1.0.0-alpha01`.

The workflow in `.github\workflows\release.yml` runs the checks in `checks.yml`, stages the zip with
`stage.ps1` as a workflow artifact, and hands the checkout to the BigWigs packager. The packager builds the
zip, creates the GitHub release with it attached, and uploads to CurseForge and Wago when the TOC has an
`X-Curse-Project-ID` or `X-Wago-ID` line and the `CF_API_KEY` or `WAGO_API_TOKEN` secret exists. A tag
containing `alpha` or `beta` is a pre-release everywhere. The changelog on every site is the newest release's
section of `NewsContent.lua` (from its first `# ` heading to the next), which the workflow writes to `CHANGELOG.md`.

**Dry run.** Run the workflow by hand (workflow_dispatch): the packager builds the zip with `-d` (no uploads,
no GitHub release) and the zip is attached to the run as the `packager` artifact.
