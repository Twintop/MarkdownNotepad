"""Tests for Markdown Notepad, run outside the game under Lua 5.1.

    python tests/run_tests.py

Needs Python 3.8+ and lupa (pip install lupa), which bundles Lua 5.1, the Lua version WoW runs.

  * test_markup.lua: the text model (Markup.lua) and the formatting actions (Actions.lua).
  * test_editor.lua: random typing sessions through the editor (CodeEditor.lua), each step
    checked against the same edit made to a plain string. FUZZ_SESSIONS (12) and FUZZ_STEPS
    (160) set how many sessions of how many steps each way of typing gets.
  * test_smoke.lua: the whole AddOn, loaded in TOC order with the library it embeds in Libs/,
    against a mock of the WoW API (mock_wow.lua), and driven through its windows. test_reload.lua
    then loads it again with the saved variables it ended with.
  * The files and localization checks: every file the TOC loads exists, every image and font the
    code names is in Media/, and every string the code looks up has an English text.

With the Ketho WoW API annotations (the VS Code extension, or the Annotations/Core folder the
WOW_API_ANNOTATIONS variable names) the mock's widgets have only the methods the real ones do, so
calling a misspelled or missing method fails the test.
"""
import glob
import os
import re
import sys

try:
    from lupa import lua51
except ImportError:
    sys.exit("lupa is missing: pip install lupa")

TESTS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TESTS)
ADDON = "MarkdownNotepad"
WIDGETS = ["Frame", "Button", "EditBox", "ScrollFrame", "Slider", "SimpleHTML", "GameTooltip",
           "Texture", "FontString", "Font"]

HARNESS = r"""
T = { results = {} }
local function repr(v)
  if type(v) == "string" then return ("%q"):format(v) end
  return tostring(v)
end
function T.test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  table.insert(T.results, { name = name, ok = ok, err = err })
end
function T.eq(actual, expected, label)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(label or "value", repr(expected), repr(actual)), 2)
  end
end
function T.ok(value, label)
  if not value then error((label or "check") .. " failed", 2) end
end
-- a small seeded random number generator, the same everywhere: rng(n) is 1 to n
function T.rng(seed)
  local state = seed * 7919 + 17
  return function(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return math.floor(state / 65536) % n + 1
  end
end
-- random markdown-ish text, heavy on the characters that matter
local ALPHABET = { "a", "b", " ", " ", "\n", "|", "|", "*", "_", "`", "#", "-", ">", "[", "]", "(", ")",
  "!", "~", "=", ":", "{", "}", "1", ".", "c", "r", "f", "\195\169", "&", ";", "<", ">", "\\", "^" }
function T.randomText(rng, n)
  local out = {}
  for i = 1, n do out[i] = ALPHABET[rng(#ALPHABET)] end
  return table.concat(out)
end
"""


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def widget_methods():
    """Each widget type's methods, with the ones it inherits, from the Ketho annotations: the
    Annotations/Core folder WOW_API_ANNOTATIONS names (as CI sets it), or the newest VS Code extension's."""
    roots = sorted(glob.glob(os.path.expanduser("~/.vscode/extensions/ketho.wow-api-*/Annotations/Core")))
    if os.environ.get("WOW_API_ANNOTATIONS"):
        roots = [os.environ["WOW_API_ANNOTATIONS"]]
    if not roots or not os.path.isdir(roots[-1]):
        return None, None
    core = roots[-1]
    files = glob.glob(os.path.join(core, "Widget", "**", "*.lua"), recursive=True)
    files.append(os.path.join(core, "Blizzard_APIDocumentationGenerated", "BaseDocumentation.lua"))
    parents, methods = {}, {}
    for path in files:
        if not os.path.exists(path):
            continue
        for line in read(path).splitlines():
            m = re.match(r"---@class\s+([\w.]+)\s*(?::\s*(.+))?", line)
            if m:
                parents.setdefault(m.group(1), [p.strip() for p in (m.group(2) or "").split(",") if p.strip()])
            m = re.match(r"function\s+(\w+)[:.](\w+)\s*\(", line)
            if m:
                methods.setdefault(m.group(1), set()).add(m.group(2))

    def resolve(name, seen):
        if name in seen:
            return set()
        seen.add(name)
        found = set(methods.get(name, ()))
        for parent in parents.get(name, ()):
            found |= resolve(parent, seen)
        return found

    return {kind: resolve(kind, set()) for kind in WIDGETS}, core


def toc_files():
    files = []
    for line in read(os.path.join(ROOT, ADDON + ".toc")).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def toc_metadata():
    """The TOC's ## fields, for the mock's GetAddOnMetadata."""
    fields = {}
    for line in read(os.path.join(ROOT, ADDON + ".toc")).splitlines():
        m = re.match(r"##\s*([\w-]+)\s*:\s*(.*?)\s*$", line)
        if m:
            fields[m.group(1)] = m.group(2)
    return fields


def runtime(valid):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)
    lua.globals().TOC_METADATA = lua.table_from(toc_metadata())
    if valid is not None:
        table = lua.table()
        for kind, names in valid.items():
            table[kind] = lua.table_from({name: True for name in names})
        lua.globals().VALID_METHODS = table
    lua.execute(read(os.path.join(TESTS, "mock_wow.lua")))
    return lua


def load_chunk(lua, path, *args):
    """Runs a file as the game does: as a chunk, given the AddOn's name and namespace."""
    loader = lua.eval("function(source, name, ...) local f = assert(loadstring(source, '@' .. name)); return f(...) end")
    loader(read(path), os.path.relpath(path, os.path.dirname(ROOT)), *args)


def xml_scripts(path):
    """The Lua files an XML file loads, in order: its <Script file="..."/> entries, and those of
    the XML files it <Include>s."""
    folder = os.path.dirname(path)
    files = []
    for kind, name in re.findall(r'<(Script|Include)\s+file="([^"]+)"', read(path)):
        target = os.path.join(folder, name.replace("\\", "/"))
        files += xml_scripts(target) if kind == "Include" else [target]
    return files


def load_addon(lua, files=None, saved=()):
    """Loads the AddOn's files, the embedded library first, in TOC order. Returns the namespace."""
    for source in saved:
        lua.execute(source)
    lua.execute("ns = {}")
    ns = lua.globals().ns
    for name in (files or toc_files()):
        path = os.path.join(ROOT, name)
        for lua_file in (xml_scripts(path) if name.endswith(".xml") else [path]):
            load_chunk(lua, lua_file, ADDON, ns)
    # a render error raises, instead of becoming the plain text fallback players would see
    lua.execute('local lib = LibStub and LibStub("LibSimpleHTMLMarkdown-1.0", true); if lib then lib.raise_errors = true end')
    return ns


def localization_files():
    return [name for name in toc_files() if name.startswith("Localization/")]


CODE_FILES = ["Core.lua", "Widgets.lua", "Render.lua", "CodeEditor.lua", "Editor.lua", "Viewer.lua", "News.lua"]
DEFINITION = re.compile(r'^L\["([^"]+)"\]\s*=', re.M)


def check_files():
    """Every file the TOC loads exists (WoW warns about each one that doesn't), and so does every
    image and font the code names."""
    missing = [name for name in toc_files() if not os.path.exists(os.path.join(ROOT, name))]
    code = "\n".join(read(os.path.join(ROOT, name)) for name in CODE_FILES)
    media = set(re.findall(r'"([\w-]+\.(?:png|tga|blp|ttf))"', code))
    media |= {os.path.basename(p) for p in re.findall(r'Media\\\\(?:Fonts|Images)\\\\([\w-]+\.\w+)', code)}
    on_disk = set()
    for _, _, files in os.walk(os.path.join(ROOT, "Media")):
        on_disk |= set(files)
    absent = sorted(media - on_disk)
    return [
        ("every file the TOC loads exists", not missing, "missing: %s" % missing),
        ("every image and font the code names is in Media", not absent and media, "not in Media: %s" % absent),
    ]


def check_localization(lua):
    """Every string the code looks up has an English text (enUS.lua, or one of Blizzard's in
    Localization.lua), and every English text is used: looked up as L["Key"], or named as "Key"."""
    defined = set()
    for name in ("Localization.lua", "enUS.lua", "LocalizationPost.lua"):
        defined |= set(DEFINITION.findall(read(os.path.join(ROOT, "Localization", name))))
    code = "\n".join(read(os.path.join(ROOT, name)) for name in CODE_FILES)
    looked_up = set(re.findall(r'L\["([^"]+)"\]', code))
    named = set(re.findall(r'"([A-Za-z0-9]+)"', code))
    value = lua.eval("function(key) return rawget(ns.Localization, key) end")

    missing = sorted(looked_up - defined)
    empty = sorted(key for key in defined if not isinstance(value(key), str))
    unused = sorted(defined - looked_up - named)
    return [
        ("every string the code looks up has an English text", not missing, "no English text for: %s" % missing),
        ("every Blizzard string it borrows exists", not empty, "nil in this client: %s" % empty),
        ("every English text is used", not unused, "never used: %s" % unused),
    ]


def run(lua, test_file):
    load_chunk(lua, os.path.join(TESTS, test_file))
    results = []
    for _, result in lua.globals().T.results.items():
        results.append((result["name"], bool(result["ok"]), result["err"]))
    return results


def main():
    valid, core = widget_methods()
    if valid:
        print("Widget methods from %s" % core)
    else:
        print("The Ketho WoW API annotations aren't installed; the mock accepts any widget method.")

    suites = []

    lua = runtime(valid)
    load_addon(lua, localization_files() + ["Markup.lua", "Actions.lua"])
    suites.append(("test_markup.lua", run(lua, "test_markup.lua")))

    lua = runtime(valid)
    load_addon(lua, localization_files() + ["Markup.lua", "Actions.lua", "Widgets.lua", "CodeEditor.lua"])
    lua.globals().FUZZ_SESSIONS = int(os.environ.get("FUZZ_SESSIONS", 12))
    lua.globals().FUZZ_STEPS = int(os.environ.get("FUZZ_STEPS", 160))
    suites.append(("test_editor.lua", run(lua, "test_editor.lua")))

    lua = runtime(valid)
    load_addon(lua)
    suites.append(("files", check_files()))
    suites.append(("localization", check_localization(lua)))
    smoke = run(lua, "test_smoke.lua")
    suites.append(("test_smoke.lua", smoke))
    saved = [lua.globals().SAVED_DB, lua.globals().SAVED_CHAR]

    if all(saved):
        lua = runtime(valid)
        load_addon(lua, saved=saved)
        suites.append(("test_reload.lua", run(lua, "test_reload.lua")))
    else:
        suites.append(("test_reload.lua", [("after a reload", False, "test_smoke.lua didn't save its variables")]))

    failed = 0
    for suite, results in suites:
        print("\n" + suite)
        for name, ok, err in results:
            print("  %s %s" % ("ok  " if ok else "FAIL", name))
            if not ok:
                failed += 1
                print("       " + str(err).replace("\n", "\n       "))
    total = sum(len(r) for _, r in suites)
    print("\n%d of %d tests passed" % (total - failed, total))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
