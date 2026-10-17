# Multi-Language Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Dock Tile UI in Simplified Chinese, Japanese, German, Russian and French as machine-first translations, with an in-app invitation and a no-tooling GitHub review path for native speakers.

**Architecture:** The String Catalog (`Localizable.xcstrings`) stays the single runtime source; a Python script (`Scripts/l10n/l10n.py`) is its only writer for non-English entries and round-trips each language to a Markdown review sheet (`docs/l10n/<lang>.md`) that reviewers edit with GitHub's pencil icon. Machine entries carry catalog state `needs_review`, reviewed ones `translated`. The app side is one pure seam (`TranslationInvite`) deciding when the running localization is a machine-first one, driving a one-time alert and an About row.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Swift Testing; Python 3 (stdlib only) + `unittest`; GitHub Actions; GA4 Admin API.

**Spec:** [docs/superpowers/specs/2026-10-17-multi-language-support-design.md](../specs/2026-10-17-multi-language-support-design.md)

## Global Constraints

- Deployment target macOS 15.0; the macOS 15 CI leg (`test-macos-15`) must stay green. Nothing here is macOS-26-only.
- Languages are exactly `en-GB` (source), `en-AU`, `en-US`, `zh-Hans`, `ja`, `de`, `ru`, `fr`. Catalog states: machine = `needs_review`, reviewed = `translated`.
- Every user-facing string goes through `AppStrings` + `Localizable.xcstrings` (`NSLocalizedString(key, value:, comment:)` shape — the script's parser depends on it). Keys are dotted lowerCamel (`translation.invite.title`).
- The catalog is edited by `Scripts/l10n/l10n.py` (non-English, and `sync-keys` for English) or, for an English value fix, textually in place. Never load-and-redump it by any other route. The script writes `json.dumps(indent=2, ensure_ascii=False)` + trailing newline, which is the file's existing style, and preserves key order.
- Glossary rules (Task 8) bind every machine pass: keep `%@` / `%d` / `%lld` placeholders exactly, keep `…`, keep ⌘ glyphs and SF Symbol names, never translate Dock Tile / Finder / Spotlight / Sparkle, Dock → 程序坞 in zh-Hans and Dock elsewhere.
- Analytics event parameters: `ui_language` (never `language` — GA4 has an automatic dimension of that name) and the existing `source`.
- New **app-target** Swift files need `project.pbxproj` entries (four lines, modelled on `AppRelocation.swift`'s `AAREL00A`/`AAREL00B`); new `DockTileTests/` files auto-join.
- Tests never write `UserDefaults.standard`. Prefer `#require`; assert exact values.
- Work on branch `feat/localization` in a worktree (superpowers:using-git-worktrees). Commits are their own Bash call (the commit hook rejects any command containing `git commit` plus a bare `-n`). End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. When the worktree is removed, delete its `DerivedData/DockTile-<hash>`.
- Test commands, referred to below as **TEST(<Suite>)**:
  `xcodebuild test -project DockTile.xcodeproj -scheme DockTile -configuration Debug -destination 'platform=macOS' -only-testing:DockTileTests/<Suite> CODE_SIGNING_ALLOWED=NO`
  **TEST(all)** = the same with `-only-testing:DockTileTests`.
  **PYTEST** = `python3 -I -m unittest discover -s Scripts/l10n -p 'test_*.py' -v` (run from the repo root).
- Website is out of scope: nothing under `website/` changes.

## Review Focus

1. **A machine translation drops or alters a format placeholder** (`%@` → `％@`, or omitted) — `String(format:)` would crash or print garbage at runtime. Pinned by `formatSpecifiersMatchSource` in Task 4.
2. **A string value containing a pipe or a newline** (alert messages) breaks the Markdown table or comes back mangled. Pinned by the escaping round-trip tests in Task 5.
3. **A reviewer edits the Key column, or a key is deleted from code after the sheet was generated** — the import must stop with a named key, never silently add a stray entry. Pinned by `importRejectsUnknownKey` in Task 5. A reviewer typing `Reviewed` with a capital must still count. Pinned by `statusIsCaseInsensitive` in Task 5.
4. **A Mac whose language the app does not ship (Korean)** must fall back to en-GB: no alert, no About row, English UI. The seam side (`en-GB`, bare `en`, `nil`) is pinned by `TranslationInviteTests` in Task 7; the bundle side (what macOS actually picks) depends on `CFBundleDevelopmentRegion = en-GB` from Task 0 and is proven by hand with `AppleLanguages "(ko)"` in Task 9.
5. **German strings overflow fixed-width rows** (Settings toggles, Tile Detail action button, Smart Add cards). No unit test can see this; Task 9 is the hands-on check with window-ID captures, and it fixes only what truncates.
6. **Every helper tile shows up as "Dock Tile" in ⌘Tab and Finder** if a localized `InfoPlist.strings` ever ships (it overrides the helper's rewritten `CFBundleName`). Pinned by `catalogShipsAndInfoPlistStringsDoesNot` in Task 0.

---

### Task 0: Put the String Catalog in the app target (it never was)

**Why first:** `project.pbxproj` references neither `.xcstrings` file, so no build has ever carried an `.lproj`. Every later task assumes the catalog ships.

**Files:**
- Modify: `DockTile.xcodeproj/project.pbxproj` (4 lines modelled on `GoogleService-Info.plist`'s `AAGSI01`/`AAGSI02` at lines 43, 150, 280, 564; `developmentRegion` at line 519; `knownRegions` at lines 521–524)
- Modify: `DockTile/Resources/Info.plist:5-6` (`CFBundleDevelopmentRegion`)
- Create: `DockTileTests/Unit/Constants/LocalizationCatalogTests.swift` (Task 4 extends it)

**Interfaces:**
- Produces: `en-GB.lproj`, `en-AU.lproj`, `en-US.lproj` in every build; `LocalizationCatalogTests` suite file.

- [ ] **Step 1: Write the failing test**

```swift
//
//  LocalizationCatalogTests.swift
//  DockTileTests
//
//  Guards the String Catalog against the regressions a machine-first translation pipeline invites.
//  Reads the repo through #filePath like AppStringsTests; reads the built product through Bundle.main
//  (the test host IS the dev app).
//

import Testing
import Foundation
@testable import Dock_Tile

@Suite("Localization catalog")
struct LocalizationCatalogTests {
    @Test("The catalog ships in the bundle; InfoPlist.strings deliberately does not")
    func catalogShipsAndInfoPlistStringsDoesNot() {
        // Until 2026-10-17 neither .xcstrings was in the target — no .lproj ever shipped.
        #expect(Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                subdirectory: nil, localization: "en-GB") != nil)
        // A localized InfoPlist.strings overrides Info.plist for Launch Services, and helper
        // bundles are copies with CFBundleName rewritten to the tile's name — shipping it would
        // make every tile read "Dock Tile" in ⌘Tab and Finder. It stays out on purpose.
        #expect(Bundle.main.url(forResource: "InfoPlist", withExtension: "strings") == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: TEST(LocalizationCatalogTests)
Expected: FAIL on the first expectation (`nil`), because no `.lproj` exists.

- [ ] **Step 3: Register `Localizable.xcstrings` (and only it)** — add one line after each of these four `GoogleService-Info.plist` lines in `project.pbxproj` (PBXBuildFile, PBXFileReference, the Resources group's children, the Resources build phase):

```
		AALOC01 /* Localizable.xcstrings in Resources */ = {isa = PBXBuildFile; fileRef = AALOC02 /* Localizable.xcstrings */; };
		AALOC02 /* Localizable.xcstrings */ = {isa = PBXFileReference; lastKnownFileType = text.json.xcstrings; path = Localizable.xcstrings; sourceTree = "<group>"; };
				AALOC02 /* Localizable.xcstrings */,
				AALOC01 /* Localizable.xcstrings in Resources */,
```

Do NOT register `InfoPlist.xcstrings` (see the test comment).

- [ ] **Step 4: Make en-GB the development region** so a Mac set to an unshipped language falls back to the catalog's source language (today's `en` will have no `.lproj`):

(Line numbers below are pre-Step-3; Step 3's inserts shift them by +3. Locate with `grep -n 'developmentRegion\|knownRegions' DockTile.xcodeproj/project.pbxproj`.)
`developmentRegion = en;` → `developmentRegion = "en-GB";`
`knownRegions`:
```
			knownRegions = (
				en,
				Base,
				"en-GB",
				"en-AU",
				"en-US",
			);
```
`DockTile/Resources/Info.plist:6`: `<string>en</string>` → `<string>en-GB</string>`.

- [ ] **Step 5: Build and verify the lprojs exist and carry the US spellings**

Run: `xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug build`
Expected: `BUILD SUCCEEDED`.
Run: `xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug -showBuildSettings | grep ' BUILT_PRODUCTS_DIR'` and note `<BUILT_PRODUCTS_DIR>`.
Run: `ls "<BUILT_PRODUCTS_DIR>/Dock Tile Dev.app/Contents/Resources" | grep lproj`
Expected: exactly `en-AU.lproj`, `en-GB.lproj`, `en-US.lproj`.
Run: `plutil -p "<BUILT_PRODUCTS_DIR>/Dock Tile Dev.app/Contents/Resources/en-US.lproj/Localizable.strings" | grep -c Customize`
Expected: a number ≥ 1 (the US spelling now ships for the first time).
Run: `ls "<BUILT_PRODUCTS_DIR>/Dock Tile Dev.app/Contents/Resources/en-GB.lproj"`
Expected: `Localizable.strings` only — no `InfoPlist.strings`.

- [ ] **Step 6: Run the tests**

Run: TEST(LocalizationCatalogTests) then TEST(AppStringsTests)
Expected: both `TEST SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add DockTile.xcodeproj/project.pbxproj DockTile/Resources/Info.plist DockTileTests/Unit/Constants/LocalizationCatalogTests.swift
git commit -m "fix(l10n): ship the String Catalog — it was never in the app target

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: MIT licence for the code (brand carved out)

**Files:**
- Create: `LICENSE`, `TRADEMARKS.md`
- Modify: `README.md` (append a `## License` section after `## Testing`)

**Interfaces:**
- Produces: a licence the review invitation (Task 10) can point to.

**Copyright holder:** the GitHub username `k97`, and nothing else. Never write a personal or full name anywhere in this repo (the owner's standing instruction, 2026-10-17); the Info.plist and InfoPlist.xcstrings copyright strings carry no name on purpose.

- [ ] **Step 1: Write `LICENSE`** (pure MIT text, nothing appended, so GitHub's detector classifies it)

```
MIT License

Copyright (c) 2026 k97

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Write `TRADEMARKS.md`** (MIT licenses copyright, not trademarks; this says so where a contributor will look)

```markdown
# Trademarks and brand assets

The MIT licence in `LICENSE` covers Dock Tile's source code. It does not grant any right to use
the **Dock Tile** name, the Dock Tile logo (`DockTile/Resources/DockTileGlyph.png`, the SVG sources
under `website/public/assets/`), the app icon (`DockTile/Resources/AppIcon.icon`), or the Happy
Machines Company and Spades Audio marks to identify other software or services. Forks must ship
under a different name and icon.
```

- [ ] **Step 3: Append to `README.md`**

```markdown
## License

Dock Tile's source code is released under the [MIT License](LICENSE). The Dock Tile name, logo
and app icon are not licensed for use by other software — see [TRADEMARKS.md](TRADEMARKS.md). The
vendored icon compiler under `Vendor/actool/` declares MIT in its `Cargo.toml` (upstream ships no
LICENSE file; see `Vendor/actool/DOCKTILE-README.md`).
```

- [ ] **Step 4: Verify**

Run: `head -1 LICENSE`
Expected: exactly `MIT License`.
After the branch is pushed (any later task): `gh api repos/k97/dock-tile --jq .license.spdx_id`
Expected: `MIT`. (GitHub detects the licence on the default branch, so this reads `null` until the branch merges — check it once more after the merge.)

- [ ] **Step 5: Commit**

```bash
git add LICENSE TRADEMARKS.md README.md
git commit -m "chore: license the code under MIT, brand assets excluded

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `l10n.py` catalog I/O + `sync-keys`, and backfill the 68 missing keys

**Files:**
- Create: `Scripts/l10n/l10n.py`
- Create: `Scripts/l10n/test_l10n.py`
- Modify: `DockTile/Resources/Localizable.xcstrings` (via the script, plus hand edits of en-US values)

**Interfaces:**
- Produces (Python, consumed by Task 5): `load_catalog(path) -> dict`, `save_catalog(catalog, path)`, `languages(catalog) -> list[str]`, `value_of(entry, lang) -> tuple[str, str] | None` (value, state), `parse_appstrings(source) -> list[tuple[key, value, comment]]`, `sync_keys(catalog, calls) -> tuple[added: list[str], warnings: list[str]]`, `insert_in_order(mapping, key, entry)`, constants `CATALOG`, `APPSTRINGS`, `SHEETS`, `SOURCE = "en-GB"`, `ENGLISH = ("en-GB", "en-AU", "en-US")`.

- [ ] **Step 1: Write the failing tests**

`Scripts/l10n/test_l10n.py`:

```python
"""Unit tests for Scripts/l10n/l10n.py. Run from the repo root:
    python3 -I -m unittest discover -s Scripts/l10n -p 'test_*.py' -v
"""
import json
import tempfile
import unittest
from pathlib import Path

import l10n


def catalog_with(**entries):
    """Build an in-memory catalog: key -> {lang: (value, state)}."""
    strings = {}
    for key, locs in entries.items():
        strings[key] = {"comment": f"c-{key}", "extractionState": "manual",
                        "localizations": {lang: {"stringUnit": {"state": state, "value": value}}
                                          for lang, (value, state) in locs.items()}}
    return {"sourceLanguage": "en-GB", "strings": strings, "version": "1.0"}


SWIFT = '''
enum AppStrings {
    static let a = NSLocalizedString("alpha.one", value: "One", comment: "first")
    static let b = NSLocalizedString(
        "beta.two",
        value: "Say \\"hi\\"\\nnow",
        comment: "multi-line call"
    )
    static let c = NSLocalizedString("gamma.colour", value: "Pick a colour", comment: "uk spelling")
}
'''


class CatalogIO(unittest.TestCase):
    def test_save_matches_existing_style_and_preserves_order(self):
        cat = catalog_with(**{"b.key": {"en-GB": ("B", "translated")}, "a.key": {"en-GB": ("A…", "translated")}})
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "L.xcstrings"
            l10n.save_catalog(cat, path)
            text = path.read_text(encoding="utf-8")
        self.assertTrue(text.startswith('{\n  "sourceLanguage": "en-GB",\n  "strings": {\n    "b.key": {'))
        self.assertIn('"value": "A…"', text)          # raw UTF-8, no \\u escapes
        self.assertTrue(text.endswith("}\n"))
        self.assertEqual(list(json.loads(text)["strings"]), ["b.key", "a.key"])

    def test_languages_and_value_of(self):
        cat = catalog_with(k={"en-GB": ("v", "translated"), "de": ("w", "needs_review")})
        self.assertEqual(l10n.languages(cat), ["de", "en-GB"])
        self.assertEqual(l10n.value_of(cat["strings"]["k"], "de"), ("w", "needs_review"))
        self.assertIsNone(l10n.value_of(cat["strings"]["k"], "ja"))


class AppStringsParsing(unittest.TestCase):
    def test_parses_single_and_multi_line_calls_and_unescapes(self):
        calls = l10n.parse_appstrings(SWIFT)
        self.assertEqual(calls[0], ("alpha.one", "One", "first"))
        self.assertEqual(calls[1], ("beta.two", 'Say "hi"\nnow', "multi-line call"))
        self.assertEqual(len(calls), 3)

    def test_unparseable_call_is_an_error(self):
        with self.assertRaises(SystemExit):
            l10n.parse_appstrings('NSLocalizedString("x", comment: "no value")')


class SyncKeys(unittest.TestCase):
    def test_adds_missing_keys_in_order_with_english_variants(self):
        cat = catalog_with(**{"alpha.one": {"en-GB": ("One", "translated")},
                              "delta.four": {"en-GB": ("Four", "translated")}})
        added, warnings = l10n.sync_keys(cat, l10n.parse_appstrings(SWIFT))
        self.assertEqual(added, ["beta.two", "gamma.colour"])
        self.assertEqual(list(cat["strings"]), ["alpha.one", "beta.two", "delta.four", "gamma.colour"])
        entry = cat["strings"]["beta.two"]
        self.assertEqual(entry["comment"], "multi-line call")
        self.assertEqual(entry["extractionState"], "manual")
        for lang in ("en-GB", "en-AU", "en-US"):
            self.assertEqual(l10n.value_of(entry, lang), ('Say "hi"\nnow', "translated"))
        self.assertEqual(warnings, ["gamma.colour: 'Pick a colour' may need an en-US spelling"])

    def test_existing_keys_are_untouched(self):
        cat = catalog_with(**{"alpha.one": {"en-GB": ("Original", "translated")}})
        added, _ = l10n.sync_keys(cat, [("alpha.one", "Changed in code", "c")])
        self.assertEqual(added, [])
        self.assertEqual(l10n.value_of(cat["strings"]["alpha.one"], "en-GB"), ("Original", "translated"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: PYTEST
Expected: `ModuleNotFoundError: No module named 'l10n'`

- [ ] **Step 3: Write `Scripts/l10n/l10n.py` (catalog I/O + sync-keys; export/import/check come in Task 5)**

```python
#!/usr/bin/env python3
"""Dock Tile localization round trip: String Catalog <-> per-language Markdown review sheets.

    python3 -I Scripts/l10n/l10n.py sync-keys            # AppStrings.swift keys -> catalog (English)
    python3 -I Scripts/l10n/l10n.py export [--lang L]    # catalog -> docs/l10n/<L>.md
    python3 -I Scripts/l10n/l10n.py import L             # docs/l10n/<L>.md -> catalog
    python3 -I Scripts/l10n/l10n.py check                # exit 1 when a sheet is stale or missing

The catalog (DockTile/Resources/Localizable.xcstrings) is the runtime source of truth; the sheets
under docs/l10n/ are derived from it and are what reviewers edit on GitHub. This script is the only
writer of non-English catalog entries. It preserves the catalog's key order and its JSON style
(indent 2, raw UTF-8, trailing newline). Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "DockTile" / "Resources" / "Localizable.xcstrings"
APPSTRINGS = ROOT / "DockTile" / "Constants" / "AppStrings.swift"
SHEETS = ROOT / "docs" / "l10n"
SOURCE = "en-GB"
ENGLISH = ("en-GB", "en-AU", "en-US")
LANGUAGE_NAMES = {"zh-Hans": "简体中文", "ja": "日本語", "de": "Deutsch", "ru": "Русский", "fr": "Français"}
UK_SPELLINGS = ("customis", "colour", "favourite", "organis", "centre", "recognis", "licence", "grey",
                "initialis", "behaviour", "cancelled", "catalogue", "dialogue", "analyse", "minimis")
STATE_FOR_STATUS = {"reviewed": "translated", "machine": "needs_review"}
STATUS_FOR_STATE = {"translated": "reviewed", "needs_review": "machine", "new": "todo"}


# --- catalog ---------------------------------------------------------------------------------

def load_catalog(path: Path = CATALOG) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save_catalog(catalog: dict, path: Path = CATALOG) -> None:
    path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def languages(catalog: dict) -> list[str]:
    found: set[str] = set()
    for entry in catalog["strings"].values():
        found.update(entry.get("localizations", {}))
    return sorted(found)


def value_of(entry: dict, lang: str) -> tuple[str, str] | None:
    unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit")
    return (unit["value"], unit.get("state", "translated")) if unit else None


def insert_in_order(mapping: dict, key: str, entry: dict) -> None:
    """Insert `key` into an insertion-ordered dict at its ASCII position, in place."""
    items = list(mapping.items())
    mapping.clear()
    placed = False
    for k, v in items:
        if not placed and k > key:
            mapping[key] = entry
            placed = True
        mapping[k] = v
    if not placed:
        mapping[key] = entry


# --- AppStrings.swift ------------------------------------------------------------------------

CALL = re.compile(
    r'NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*value:\s*"((?:[^"\\]|\\.)*)"\s*,'
    r'\s*comment:\s*"((?:[^"\\]|\\.)*)"\s*\)', re.S)
SWIFT_ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}


def swift_unescape(text: str) -> str:
    return re.sub(r"\\(.)", lambda m: SWIFT_ESCAPES.get(m.group(1), m.group(1)), text)


def parse_appstrings(source: str) -> list[tuple[str, str, str]]:
    calls = [(k, swift_unescape(v), swift_unescape(c)) for k, v, c in CALL.findall(source)]
    total = source.count("NSLocalizedString(")
    if len(calls) != total:
        raise SystemExit(f"parsed {len(calls)} NSLocalizedString calls but the file has {total}; "
                         "a call does not match the (key, value:, comment:) shape")
    return calls


def sync_keys(catalog: dict, calls: list[tuple[str, str, str]]) -> tuple[list[str], list[str]]:
    strings = catalog["strings"]
    added: list[str] = []
    warnings: list[str] = []
    for key, value, comment in calls:
        if key in strings:
            continue
        entry = {"comment": comment, "extractionState": "manual",
                 "localizations": {lang: {"stringUnit": {"state": "translated", "value": value}}
                                   for lang in ENGLISH}}
        insert_in_order(strings, key, entry)
        added.append(key)
        if any(w in value.lower() for w in UK_SPELLINGS):
            warnings.append(f"{key}: '{value}' may need an en-US spelling")
    return added, warnings


# --- commands --------------------------------------------------------------------------------

def cmd_sync_keys(args: argparse.Namespace) -> int:
    catalog = load_catalog()
    added, warnings = sync_keys(catalog, parse_appstrings(APPSTRINGS.read_text(encoding="utf-8")))
    save_catalog(catalog)
    print(f"added {len(added)} keys")
    for key in added:
        print("  +", key)
    for warning in warnings:
        print("  warning:", warning)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("sync-keys").set_defaults(run=cmd_sync_keys)
    args = parser.parse_args(argv)
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: PYTEST
Expected: `OK` with 6 tests.

- [ ] **Step 5: Backfill the catalog**

Run: `python3 -I Scripts/l10n/l10n.py sync-keys`
Expected: `added 68 keys`, each listed, followed by zero or more `warning:` lines.

Run: `git diff --stat DockTile/Resources/Localizable.xcstrings`
Expected: insertions only (the new entries), no deletions, no reordering of existing lines. If existing lines show as changed, STOP: the style assumption is wrong — compare `git diff` and fix `save_catalog` before continuing.

- [ ] **Step 6: Fix en-US spellings the warnings named**

For every `warning:` line, open the key's entry in `Localizable.xcstrings` and edit the **en-US** `value` textually to US spelling (e.g. `Customise` → `Customize`, `colour` → `color`). Leave en-GB/en-AU as they are. Also read the 68 added en-US values once by eye for UK spellings the list misses.

- [ ] **Step 7: Run the existing localization tests**

Run: TEST(AppStringsTests)
Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add Scripts/l10n/l10n.py Scripts/l10n/test_l10n.py DockTile/Resources/Localizable.xcstrings
git commit -m "feat(l10n): catalog sync script; backfill 68 AppStrings keys into the String Catalog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Move the remaining hardcoded strings into `AppStrings`

**Files:**
- Modify: `DockTile/Constants/AppStrings.swift` (`enum Alert`, `enum Menu`, `enum SmartAdd`)
- Modify: `DockTile/Views/DockTileDetailView.swift:177`
- Modify: `DockTile/App/AppDelegate.swift:351,362,383`
- Modify: `DockTile/App/HelperAppDelegate.swift:364`
- Modify: `DockTile/Managers/SmartAddEngine.swift:101-120`
- Modify: `DockTileTests/Unit/Constants/AppStringsTests.swift` (`allStringsReturnValues`)
- Modify: `DockTile/Resources/Localizable.xcstrings` (via `sync-keys`)

**Interfaces:**
- Produces: `AppStrings.Alert.deleteTileMessage`, `AppStrings.Menu.noAppsConfigured`, `AppStrings.Menu.noConfiguration`, `AppStrings.SmartAdd.identityBrowse` / `identityWatch` / `identityShip` / `identityChat` / `identityWork` / `identityTogether`.

- [ ] **Step 1: Write the failing test** — add to `allStringsReturnValues` in `AppStringsTests.swift`, after the existing Alert expectations:

```swift
        #expect(!AppStrings.Alert.deleteTileMessage.isEmpty)
        #expect(!AppStrings.Menu.noAppsConfigured.isEmpty)
        #expect(!AppStrings.Menu.noConfiguration.isEmpty)
        #expect(AppStrings.SmartAdd.identityBrowse == "Browse")
        #expect(AppStrings.SmartAdd.identityWatch == "Watch")
        #expect(AppStrings.SmartAdd.identityShip == "Ship")
        #expect(AppStrings.SmartAdd.identityChat == "Chat")
        #expect(AppStrings.SmartAdd.identityWork == "Work")
        #expect(AppStrings.SmartAdd.identityTogether == "Together")
```

- [ ] **Step 2: Run to verify it fails**

Run: TEST(AppStringsTests)
Expected: build error `type 'AppStrings.Alert' has no member 'deleteTileMessage'`.

- [ ] **Step 3: Add the accessors** in `AppStrings.swift`

Inside `enum Alert`:
```swift
        static let deleteTileMessage = NSLocalizedString(
            "alert.deleteTile.message",
            value: "This will permanently delete the tile and remove it from the dock.",
            comment: "Delete-tile confirmation message"
        )
```
Inside `enum Menu`:
```swift
        static let noAppsConfigured = NSLocalizedString(
            "menu.noAppsConfigured",
            value: "No apps configured",
            comment: "Dock menu: disabled row when the tile has no apps"
        )
        static let noConfiguration = NSLocalizedString(
            "menu.noConfiguration",
            value: "No configuration",
            comment: "Dock menu: disabled row when the tile's config cannot be found"
        )
```
Inside `enum SmartAdd`:
```swift
        // Suggested tile names. They become the Dock tile's label, so they are localized.
        static let identityBrowse = NSLocalizedString("smartAdd.identity.browse", value: "Browse", comment: "Smart Add: suggested tile name for browsers")
        static let identityWatch = NSLocalizedString("smartAdd.identity.watch", value: "Watch", comment: "Smart Add: suggested tile name for video apps")
        static let identityShip = NSLocalizedString("smartAdd.identity.ship", value: "Ship", comment: "Smart Add: suggested tile name for developer tools")
        static let identityChat = NSLocalizedString("smartAdd.identity.chat", value: "Chat", comment: "Smart Add: suggested tile name for social apps")
        static let identityWork = NSLocalizedString("smartAdd.identity.work", value: "Work", comment: "Smart Add: suggested tile name for productivity apps")
        static let identityTogether = NSLocalizedString("smartAdd.identity.together", value: "Together", comment: "Smart Add: suggested tile name for apps opened together")
```

- [ ] **Step 4: Replace the literals**

`DockTileDetailView.swift:177`: `Text("This will permanently delete the tile and remove it from the dock.")` → `Text(AppStrings.Alert.deleteTileMessage)`.

`AppDelegate.swift`: `title: "Configure..."` → `title: AppStrings.Menu.configure`; `title: "No apps configured"` → `title: AppStrings.Menu.noAppsConfigured`; `title: "No configuration"` → `title: AppStrings.Menu.noConfiguration`.

`HelperAppDelegate.swift:364`: `title: "No configuration"` → `title: AppStrings.Menu.noConfiguration`.

`SmartAddEngine.swift`: `Identity(name: "Together", …)` → `Identity(name: AppStrings.SmartAdd.identityTogether, …)`; and in `identity`: `"Browse"` → `AppStrings.SmartAdd.identityBrowse`, `"Watch"` → `identityWatch`, `"Ship"` → `identityShip`, `"Chat"` → `identityChat`, `"Work"` → `identityWork`.

- [ ] **Step 5: Sync the catalog and confirm no other literals remain**

Run: `python3 -I Scripts/l10n/l10n.py sync-keys`
Expected: `added 9 keys`.

Run: `grep -rn --include='*.swift' -E 'title: "[A-Z]|Text\("[A-Za-z]' DockTile | grep -v AppStrings`
Expected: no output (the remaining `Text("✨")`, `Text("+\(…)")`, `Toggle("", …)` literals are glyphs/numbers and untouched).

- [ ] **Step 6: Run the tests**

Run: TEST(AppStringsTests) then TEST(SmartAddEngineTests)
Expected: both `TEST SUCCEEDED` (the Smart Add identity assertions still read "Browse" etc. because the test host runs in English).

- [ ] **Step 7: Commit**

```bash
git add DockTile/Constants/AppStrings.swift DockTile/Views/DockTileDetailView.swift DockTile/App/AppDelegate.swift DockTile/App/HelperAppDelegate.swift DockTile/Managers/SmartAddEngine.swift DockTileTests/Unit/Constants/AppStringsTests.swift DockTile/Resources/Localizable.xcstrings
git commit -m "feat(l10n): route the last hardcoded UI strings through AppStrings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `LocalizationCatalogTests` — code ↔ catalog ↔ languages guard

**Files:**
- Modify: `DockTileTests/Unit/Constants/LocalizationCatalogTests.swift` (created in Task 0; keep its existing test, add the members below inside the same `struct`)

**Interfaces:**
- Produces: `LocalizationCatalogTests.languages` (the pinned language list; Task 8 extends it to eight).

- [ ] **Step 1: Write the tests** — add inside `struct LocalizationCatalogTests`, after `catalogShipsAndInfoPlistStringsDoesNot`:

```swift
    /// Every localization the app ships. Pinned so dropping or adding one is a deliberate edit here.
    static let languages: Set<String> = ["en-AU", "en-GB", "en-US"]
    static let source = "en-GB"

    static let repoRoot: String = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // file → Constants → Unit → DockTileTests
        return url.path
    }()

    static func catalog() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: URL(fileURLWithPath: repoRoot + "/DockTile/Resources/Localizable.xcstrings"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["strings"] as? [String: [String: Any]])
    }

    static func localizations(_ entry: [String: Any]) -> [String: String] {
        guard let locs = entry["localizations"] as? [String: [String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for (lang, loc) in locs {
            if let unit = loc["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
                out[lang] = value
            }
        }
        return out
    }

    static func codeKeys() throws -> Set<String> {
        let path = repoRoot + "/DockTile/Constants/AppStrings.swift"
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"NSLocalizedString\(\s*"([^"]+)""#)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return Set(matches.compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
    }

    /// `%@`, `%d`, `%lld`, `%1$@`, `%.1f` … in order of appearance.
    static func specifiers(_ value: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[0-9.]*(?:ll|l|h)?[@dfsux]"#)
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
    }

    @Test("Every key AppStrings references exists in the catalog")
    func codeKeysExistInCatalog() throws {
        let missing = try Self.codeKeys().subtracting(try Self.catalog().keys)
        #expect(missing.isEmpty, "run: python3 -I Scripts/l10n/l10n.py sync-keys — missing \(missing.sorted())")
    }

    @Test("The catalog's language set is exactly the pinned one")
    func languageSetIsPinned() throws {
        var found: Set<String> = []
        for entry in try Self.catalog().values { found.formUnion(Self.localizations(entry).keys) }
        #expect(found == Self.languages)
    }

    @Test("Every language has every key, with a non-empty value")
    func everyLanguageHasEveryKey() throws {
        var gaps: [String] = []
        for (key, entry) in try Self.catalog() {
            let locs = Self.localizations(entry)
            for lang in Self.languages where (locs[lang] ?? "").isEmpty { gaps.append("\(lang):\(key)") }
        }
        #expect(gaps.isEmpty, "\(gaps.sorted())")
    }

    @Test("Format placeholders survive translation in every language")
    func formatSpecifiersMatchSource() throws {
        var broken: [String] = []
        for (key, entry) in try Self.catalog() {
            let locs = Self.localizations(entry)
            let expected = Self.specifiers(locs[Self.source] ?? "").sorted()
            for (lang, value) in locs where Self.specifiers(value).sorted() != expected {
                broken.append("\(lang):\(key)")
            }
        }
        #expect(broken.isEmpty, "\(broken.sorted())")
    }

    @Test("The specifier scanner sees the shapes the app uses")
    func specifierScanner() {
        #expect(Self.specifiers("Version %@") == ["%@"])
        #expect(Self.specifiers("%lld apps in %@") == ["%lld", "%@"])
        #expect(Self.specifiers("%2$@ before %1$@") == ["%2$@", "%1$@"])
        #expect(Self.specifiers("100% done") == [])
    }
```

- [ ] **Step 2: Run the suite**

Run: TEST(LocalizationCatalogTests)
Expected: `TEST SUCCEEDED`, 6 tests (Task 0's plus these five). (After Tasks 2–3 the catalog has every code key and only the three English languages. If `codeKeysExistInCatalog` fails, Task 2's sync was incomplete: run `sync-keys` again and look at the listed keys.)

- [ ] **Step 3: Prove the guard can fail**

Textually edit one en-US value in `Localizable.xcstrings` to drop a `%@` (`about.version`'s `"Version %@"` → `"Version"`), run TEST(LocalizationCatalogTests), expect `formatSpecifiersMatchSource` to FAIL naming `en-US:about.version`, then `git checkout DockTile/Resources/Localizable.xcstrings`.

- [ ] **Step 4: Commit**

```bash
git add DockTileTests/Unit/Constants/LocalizationCatalogTests.swift
git commit -m "test(l10n): guard code keys, language set and format placeholders in the catalog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `export` / `import` / `check` review-sheet round trip + CI step + reviewer README

**Files:**
- Modify: `Scripts/l10n/l10n.py`
- Modify: `Scripts/l10n/test_l10n.py`
- Create: `docs/l10n/README.md`
- Modify: `.github/workflows/ci.yml` (`build-and-test` job, after `Checkout`)

**Interfaces:**
- Consumes: Task 2's catalog functions.
- Produces (consumed by Tasks 8, 10): `Row(key, english, translation, status, context)`, `encode_cell(str) -> str`, `decode_cell(str) -> str`, `sheet_rows(catalog, lang) -> list[Row]`, `render_sheet(catalog, lang) -> str`, `parse_sheet(text) -> list[Row]`, `apply_sheet(catalog, lang, rows) -> list[str]` (changed keys), `sheet_languages(catalog) -> list[str]`, CLI `export [--lang L]`, `import L`, `check`.

- [ ] **Step 1: Write the failing tests** — append to `test_l10n.py` before `if __name__`:

```python
class Cells(unittest.TestCase):
    def test_pipe_newline_and_backslash_round_trip(self):
        for value in ("a | b", "line one\nline two", "C:\\path", "mixed \\| \\n"):
            self.assertEqual(l10n.decode_cell(l10n.encode_cell(value)), value)
        self.assertNotIn("\n", l10n.encode_cell("x\ny"))
        self.assertEqual(l10n.encode_cell("a|b"), "a\\|b")


def sample_catalog():
    return catalog_with(**{
        "about.title": {"en-GB": ("About", "translated"), "de": ("Über", "needs_review")},
        "alert.msg": {"en-GB": ("Keep | this\nline", "translated")},
        "menu.quit": {"en-GB": ("Quit", "translated"), "de": ("Beenden", "translated")},
    })


class Sheets(unittest.TestCase):
    def sample(self):
        return sample_catalog()

    def test_render_marks_status_from_state(self):
        text = l10n.render_sheet(self.sample(), "de")
        self.assertTrue(text.startswith("# Dock Tile — Deutsch (de)\n"))
        self.assertIn("| `about.title` | About | Über | machine | c-about.title |", text)
        self.assertIn("| `alert.msg` | Keep \\| this\\nline |  | todo | c-alert.msg |", text)
        self.assertIn("| `menu.quit` | Quit | Beenden | reviewed | c-menu.quit |", text)

    def test_export_import_is_identity(self):
        cat = self.sample()
        rows = l10n.parse_sheet(l10n.render_sheet(cat, "de"))
        self.assertEqual([r.key for r in rows], ["about.title", "alert.msg", "menu.quit"])
        self.assertEqual(rows[1].english, "Keep | this\nline")
        changed = l10n.apply_sheet(cat, "de", rows)
        self.assertEqual(changed, [])
        self.assertEqual(l10n.render_sheet(cat, "de"), l10n.render_sheet(self.sample(), "de"))

    def test_import_maps_status_to_state_and_fills_todo(self):
        cat = self.sample()
        rows = l10n.parse_sheet(l10n.render_sheet(cat, "de"))
        rows[0].status = "reviewed"            # confirmed without editing
        rows[1].translation = "Diese | Zeile\nbehalten"
        changed = l10n.apply_sheet(cat, "de", rows)
        self.assertEqual(changed, ["about.title", "alert.msg"])
        self.assertEqual(l10n.value_of(cat["strings"]["about.title"], "de"), ("Über", "translated"))
        self.assertEqual(l10n.value_of(cat["strings"]["alert.msg"], "de"), ("Diese | Zeile\nbehalten", "needs_review"))
        self.assertEqual(list(cat["strings"]["alert.msg"]["localizations"]), ["de", "en-GB"])

    def test_statusIsCaseInsensitive(self):
        text = l10n.render_sheet(self.sample(), "de").replace("| machine |", "| Reviewed |")
        rows = l10n.parse_sheet(text)
        self.assertEqual(rows[0].status, "reviewed")

    def test_importRejectsUnknownKey(self):
        cat = self.sample()
        rows = [l10n.Row("ghost.key", "x", "y", "machine", "")]
        with self.assertRaises(SystemExit) as ctx:
            l10n.apply_sheet(cat, "de", rows)
        self.assertEqual(ctx.exception.code, 2)
        self.assertNotIn("ghost.key", cat["strings"])

    def test_sheet_languages_excludes_english(self):
        self.assertEqual(l10n.sheet_languages(self.sample()), ["de"])


class Check(unittest.TestCase):
    """`check` fails on what a reviewer can break or a maintainer can forget — never on a sheet
    that is merely ahead of the catalog (reviewer edits awaiting import)."""

    def sample(self):
        return sample_catalog()

    def test_reviewer_edits_ahead_of_catalog_pass(self):
        cat = self.sample()
        rows = l10n.parse_sheet(l10n.render_sheet(cat, "de"))
        rows[0].translation = "Info"
        rows[0].status = "reviewed"
        self.assertEqual(l10n.lint_rows(rows, cat, "de"), [])

    def test_stale_sheet_is_flagged_by_check_but_not_by_lint(self):
        cat = self.sample()
        rows = l10n.parse_sheet(l10n.render_sheet(cat, "de"))
        cat["strings"]["about.title"]["localizations"]["en-GB"]["stringUnit"]["value"] = "About Dock Tile"
        cat["strings"]["zeta.new"] = {"localizations": {"en-GB": {"stringUnit": {"state": "translated", "value": "New"}}}}
        self.assertEqual(l10n.stale_rows(rows, cat, "de"), ["about.title: English column is stale — run export",
                                                            "zeta.new: missing from the de sheet — run export"])
        self.assertEqual(l10n.lint_rows(rows, cat, "de"), [])     # import still accepts the reviewer's rows

    def test_unknown_key_lost_placeholder_and_dropped_term_are_flagged(self):
        cat = catalog_with(**{"about.version": {"en-GB": ("Version %@ of Dock Tile…", "translated")}})
        rows = [l10n.Row("about.version", "Version %@ of Dock Tile…", "Version von DockTile", "machine", ""),
                l10n.Row("ghost.key", "x", "y", "machine", "")]
        self.assertEqual(l10n.lint_rows(rows, cat, "de"), [
            "about.version: placeholders differ from English (['%@'] vs [])",
            "about.version: 'Dock Tile' must stay verbatim",
            "about.version: '…' must stay verbatim",
            "ghost.key: unknown key",
        ])

    def test_protected_terms_follow_apple_renames_per_language(self):
        cat = catalog_with(**{"menu.showInFinder": {"en-GB": ("Show in Finder", "translated")}})
        ok = [l10n.Row("menu.showInFinder", "Show in Finder", "在访达中显示", "machine", "")]
        verbatim = [l10n.Row("menu.showInFinder", "Show in Finder", "在 Finder 中显示", "machine", "")]
        german = [l10n.Row("menu.showInFinder", "Show in Finder", "Im Finder zeigen", "machine", "")]
        self.assertEqual(l10n.lint_rows(ok, cat, "zh-Hans"), [])
        self.assertEqual(l10n.lint_rows(verbatim, cat, "zh-Hans"), ["menu.showInFinder: 'Finder' must appear as '访达'"])
        self.assertEqual(l10n.lint_rows(german, cat, "de"), [])
```

- [ ] **Step 2: Run to verify they fail**

Run: PYTEST
Expected: `AttributeError: module 'l10n' has no attribute 'decode_cell'` (and siblings).

- [ ] **Step 3: Add the sheet layer to `l10n.py`** — insert after the `sync_keys` function and before `# --- commands`:

```python
# --- review sheets ---------------------------------------------------------------------------

@dataclass
class Row:
    key: str
    english: str
    translation: str
    status: str
    context: str


def encode_cell(text: str) -> str:
    return text.replace("\\", "\\\\").replace("|", "\\|").replace("\n", "\\n")


def decode_cell(text: str) -> str:
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "|": "|", "\\": "\\"}.get(m.group(1), "\\" + m.group(1)), text)


def sheet_rows(catalog: dict, lang: str) -> list[Row]:
    rows: list[Row] = []
    for key, entry in catalog["strings"].items():
        source = value_of(entry, SOURCE)
        if source is None:
            continue
        target = value_of(entry, lang)
        context = entry.get("comment", "")
        if target is None or not target[0]:
            rows.append(Row(key, source[0], "", "todo", context))
        else:
            rows.append(Row(key, source[0], target[0], STATUS_FOR_STATE.get(target[1], "machine"), context))
    return rows


def render_sheet(catalog: dict, lang: str) -> str:
    name = LANGUAGE_NAMES.get(lang, lang)
    head = [
        f"# Dock Tile — {name} ({lang})",
        "",
        "How to review: [docs/l10n/README.md](README.md). Edit the **Translation** column, set",
        '**Status** to `reviewed` for every row you checked (changed or not), then "Propose changes".',
        "Status values: `machine` (not yet checked by a person), `reviewed`, `todo` (no translation yet).",
        "Keep `%@`-style placeholders exactly as they are. `\\n` means a line break, `\\|` a pipe.",
        "",
        "| Key | English | Translation | Status | Context |",
        "|---|---|---|---|---|",
    ]
    body = [f"| `{r.key}` | {encode_cell(r.english)} | {encode_cell(r.translation)} | {r.status} | {encode_cell(r.context)} |"
            for r in sheet_rows(catalog, lang)]
    return "\n".join(head + body) + "\n"


SPLIT = re.compile(r"(?<!\\)\|")


def parse_sheet(text: str) -> list[Row]:
    rows: list[Row] = []
    for line in text.splitlines():
        if not line.startswith("| `"):
            continue
        cells = [c.strip() for c in SPLIT.split(line)[1:-1]]
        if len(cells) != 5:
            raise SystemExit(f"malformed row (expected 5 cells): {line}")
        rows.append(Row(cells[0].strip("`"), decode_cell(cells[1]), decode_cell(cells[2]),
                        cells[3].lower(), decode_cell(cells[4])))
    return rows


def apply_sheet(catalog: dict, lang: str, rows: list[Row]) -> list[str]:
    strings = catalog["strings"]
    changed: list[str] = []
    for row in rows:
        if row.key not in strings:
            print(f"unknown key in sheet: {row.key} — a reviewer edited the Key column, or the key "
                  "was removed from code; fix the sheet, then import again", file=sys.stderr)
            sys.exit(2)
        if not row.translation:
            continue
        unit = {"stringUnit": {"state": STATE_FOR_STATUS.get(row.status, "needs_review"), "value": row.translation}}
        locs = strings[row.key].setdefault("localizations", {})
        if locs.get(lang) == unit:
            continue
        if lang in locs:
            locs[lang] = unit
        else:
            insert_in_order(locs, lang, unit)
        changed.append(row.key)
    return changed


def sheet_languages(catalog: dict) -> list[str]:
    return [lang for lang in languages(catalog) if not lang.startswith("en")]


# --- lint (what check and import refuse) -------------------------------------------------------

SPECIFIER = re.compile(r"%(?:\d+\$)?[0-9.]*(?:ll|l|h)?[@dfsux]")
# Terms that must appear in every translation: verbatim, unless Apple itself renames them in that
# language (Finder is 访达 and Spotlight 聚焦 in Simplified Chinese — see GLOSSARY.md).
PROTECTED_TERMS: dict[str, dict[str, str]] = {
    "Dock Tile": {}, "Sparkle": {}, "…": {}, "⌘": {},
    "Finder": {"zh-Hans": "访达"},
    "Spotlight": {"zh-Hans": "聚焦"},
}


def specifiers(text: str) -> list[str]:
    return sorted(SPECIFIER.findall(text))


def lint_rows(rows: list[Row], catalog: dict, lang: str) -> list[str]:
    """Problems a REVIEWER can introduce: an edited key, a lost placeholder, a dropped protected
    term. Both `check` and `import` refuse these. A translation that merely differs from the
    catalog is not a problem — that is a reviewer's edit awaiting import."""
    strings = catalog["strings"]
    problems: list[str] = []
    for row in rows:
        if row.key not in strings:
            problems.append(f"{row.key}: unknown key")
            continue
        if not row.translation:
            continue
        expected, got = specifiers(row.english), specifiers(row.translation)
        if expected != got:
            problems.append(f"{row.key}: placeholders differ from English ({expected} vs {got})")
        for term, renames in PROTECTED_TERMS.items():
            wanted = renames.get(lang, term)
            if term in row.english and wanted not in row.translation:
                problems.append(f"{row.key}: '{term}' must stay verbatim" if wanted == term
                                else f"{row.key}: '{term}' must appear as '{wanted}'")
    return problems


def stale_rows(rows: list[Row], catalog: dict, lang: str) -> list[str]:
    """Problems a MAINTAINER can cause by forgetting `export`: an English column that no longer
    matches the catalog, or a catalog key the sheet lacks. Only `check` reports these — `import`
    must still accept such a sheet, or a merged reviewer PR could be told to run the very command
    that overwrites it."""
    strings = catalog["strings"]
    problems: list[str] = []
    seen = {row.key for row in rows}
    for row in rows:
        entry = strings.get(row.key)
        source = value_of(entry, SOURCE) if entry else None
        if source and row.english != source[0]:
            problems.append(f"{row.key}: English column is stale — run export")
    for key, entry in strings.items():
        if key not in seen and value_of(entry, SOURCE):
            problems.append(f"{key}: missing from the {lang} sheet — run export")
    return problems
```

Then extend the commands section:

```python
def cmd_export(args: argparse.Namespace) -> int:
    catalog = load_catalog()
    SHEETS.mkdir(parents=True, exist_ok=True)
    for lang in ([args.lang] if args.lang else sheet_languages(catalog)):
        (SHEETS / f"{lang}.md").write_text(render_sheet(catalog, lang), encoding="utf-8")
        print("wrote", SHEETS / f"{lang}.md")
    return 0


def cmd_import(args: argparse.Namespace) -> int:
    catalog = load_catalog()
    path = SHEETS / f"{args.lang}.md"
    rows = parse_sheet(path.read_text(encoding="utf-8"))
    problems = lint_rows(rows, catalog, args.lang)          # reviewer-class only — never staleness
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    changed = apply_sheet(catalog, args.lang, rows)
    save_catalog(catalog)
    path.write_text(render_sheet(catalog, args.lang), encoding="utf-8")   # re-render: refreshes a stale English column too
    print(f"{args.lang}: {len(changed)} entries updated")
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    """Green on a sheet that is ahead of the catalog (reviewer edits pending import); red on a
    missing or stale sheet, an unknown key, a lost placeholder or a dropped protected term."""
    catalog = load_catalog()
    problems: list[str] = []
    for lang in sheet_languages(catalog):
        path = SHEETS / f"{lang}.md"
        if not path.exists():
            problems.append(f"{lang}: no review sheet — run: python3 -I Scripts/l10n/l10n.py export")
            continue
        rows = parse_sheet(path.read_text(encoding="utf-8"))
        problems += [f"{lang}: {p}" for p in lint_rows(rows, catalog, lang) + stale_rows(rows, catalog, lang)]
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print("review sheets consistent with the catalog")
    return 0
```

and register them in `main` after the `sync-keys` line:

```python
    export = sub.add_parser("export")
    export.add_argument("--lang")
    export.set_defaults(run=cmd_export)
    imp = sub.add_parser("import")
    imp.add_argument("lang")
    imp.set_defaults(run=cmd_import)
    sub.add_parser("check").set_defaults(run=cmd_check)
```

- [ ] **Step 4: Run the tests**

Run: PYTEST
Expected: `OK`, 17 tests.

Run: `python3 -I Scripts/l10n/l10n.py check`
Expected: `review sheets consistent with the catalog` (no non-English language exists yet, so nothing to check), exit 0.

- [ ] **Step 5: Write `docs/l10n/README.md`**

```markdown
# Translating Dock Tile

Dock Tile's non-English translations are **machine-first**: a language model wrote the first
draft, and native speakers fix it. You do not need Xcode, a clone, or any JSON — only a GitHub
account and the pencil icon.

## Review a language (5 minutes to start, no coding)

1. Open your language's sheet: [简体中文](zh-Hans.md) · [日本語](ja.md) · [Deutsch](de.md) ·
   [Русский](ru.md) · [Français](fr.md).
2. Press the pencil icon (top right of the file). Fix anything in the **Translation** column.
   Set **Status** to `reviewed` for every row you checked, even rows you did not change.
3. Optional: rewrite the `translation.reviewLine` row in your language to say who reviewed it,
   for example `由 @yourhandle 校对`. The app shows that line in About.
4. Press **Propose changes**, then **Create pull request**. That is all.

Rules of thumb: keep `%@`, `%d` and `%lld` exactly where they are (the app fills them in);
`\n` in a cell is a line break and `\|` is a pipe; follow Apple's own macOS wording for the
language (what System Settings calls things) — see [GLOSSARY.md](GLOSSARY.md). Too much? Comment
on the language's issue under the `translation` label instead and describe the fix.

Credit: your handle goes in the About pane's Translation row and in the release notes.

## Maintainer workflow

| When | Run |
|---|---|
| Added or changed an `AppStrings` key | `python3 -I Scripts/l10n/l10n.py sync-keys` then `… export` |
| A reviewer's PR was merged | `python3 -I Scripts/l10n/l10n.py import <lang>` and commit the catalog |
| Starting a new language | `… export --lang <code>`, fill the Translation column (status `machine`), `… import <code>`, add the code to `LocalizationCatalogTests.languages` and to `knownRegions` in `project.pbxproj` |
| Before pushing | `python3 -I Scripts/l10n/l10n.py check` (CI runs it too) |

The catalog (`DockTile/Resources/Localizable.xcstrings`) is the runtime source of truth; the sheets
here are derived from it. Machine entries carry state `needs_review` (yellow in Xcode), reviewed
ones `translated`. Both ship. A reviewer's pull request leaves a sheet *ahead* of the catalog until
you import it — CI's `check` is green in that state and red only on a stale export, an unknown
key, a lost placeholder or a dropped glossary term. `InfoPlist.xcstrings` is deliberately not in
the app target: a localized `InfoPlist.strings` would override every helper tile's name.
```

- [ ] **Step 6: Add the CI step** in `.github/workflows/ci.yml`, in `build-and-test`, directly after the `Checkout` step:

```yaml
      - name: Localization sheets in sync
        run: |
          python3 -I -m unittest discover -s Scripts/l10n -p 'test_*.py'
          python3 -I Scripts/l10n/l10n.py check
```

- [ ] **Step 7: Commit**

```bash
git add Scripts/l10n/l10n.py Scripts/l10n/test_l10n.py docs/l10n/README.md .github/workflows/ci.yml
git commit -m "feat(l10n): review-sheet export/import/check round trip, reviewer guide, CI check

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: About pane Translation row, sheet link, analytics events

**Files:**
- Modify: `DockTile/Constants/AppStrings.swift` (new `enum Translation`)
- Modify: `DockTile/Views/AboutView.swift` (`AboutLinks` + a new `Section`)
- Modify: `DockTile/Managers/AnalyticsService.swift` (`AnalyticsEvent`)
- Create: `DockTile/Managers/TranslationInvite.swift` (seam only in this task; manager in Task 7)
- Modify: `DockTile.xcodeproj/project.pbxproj` (4 lines)
- Modify: `DockTileTests/Unit/Constants/AppStringsTests.swift`, the existing `AboutLinksTests` suite (`grep -rl AboutLinksTests DockTileTests`)
- Create: `DockTileTests/Unit/Managers/TranslationInviteTests.swift`
- Modify: `DockTile/Resources/Localizable.xcstrings` (via `sync-keys`)

**Interfaces:**
- Produces: `AppStrings.Translation.title` / `.reviewLine` / `.helpImprove` / `.inviteTitle` / `.inviteMessage`; `AboutLinks.repository`, `AboutLinks.translationSheet(localization:) -> URL`; `AnalyticsEvent.translationInviteShown` (`"translation_invite_shown"`), `.translationHelpTapped` (`"translation_help_tapped"`); `TranslationInvite.showsTranslationRow(localization:) -> Bool`, `TranslationInvite.runningLocalization: String?`.

- [ ] **Step 1: Write the failing tests**

`DockTileTests/Unit/Managers/TranslationInviteTests.swift`:
```swift
import Testing
@testable import Dock_Tile

@Suite("Translation invite seams")
struct TranslationInviteTests {
    @Test("The About row shows only for a non-English localization",
          arguments: [("zh-Hans", true), ("ja", true), ("de", true), ("en-GB", false), ("en-US", false),
                      ("en", false), ("", false)])
    func rowVisibility(localization: String, shows: Bool) {
        #expect(TranslationInvite.showsTranslationRow(localization: localization) == shows)
    }

    @Test("No localization means no row")
    func nilLocalization() {
        #expect(TranslationInvite.showsTranslationRow(localization: nil) == false)
    }
}
```

In `AboutLinksTests`:
```swift
    @Test("The review-sheet link opens the language's sheet on GitHub")
    func translationSheetLink() {
        #expect(AboutLinks.translationSheet(localization: "zh-Hans").absoluteString
                == "https://github.com/k97/dock-tile/blob/main/docs/l10n/zh-Hans.md")
    }
```

In `AppStringsTests.allStringsReturnValues`:
```swift
        #expect(AppStrings.Translation.title == "Translation")
        #expect(!AppStrings.Translation.reviewLine.isEmpty)
        #expect(AppStrings.Translation.helpImprove == "Help Improve…")
        #expect(!AppStrings.Translation.inviteTitle.isEmpty)
        #expect(!AppStrings.Translation.inviteMessage.isEmpty)
```

- [ ] **Step 2: Run to verify they fail**

Run: TEST(TranslationInviteTests)
Expected: build error `cannot find 'TranslationInvite' in scope`.

- [ ] **Step 3: Create `DockTile/Managers/TranslationInvite.swift`**

```swift
//
//  TranslationInvite.swift
//  Dock Tile
//
//  Decides when the app is showing a machine-first translation and should invite a native speaker
//  to review it. Pure seams (guarded by TranslationInviteTests); the manager that shows the alert
//  lives below them.
//

import AppKit

enum TranslationInvite {
    /// The localization macOS chose for this bundle (`Bundle.main.preferredLocalizations.first`),
    /// e.g. "zh-Hans". A Mac whose language the app does not ship resolves to "en-GB" (the
    /// development region), so an unsupported language never sees the invitation.
    nonisolated static var runningLocalization: String? { Bundle.main.preferredLocalizations.first }

    nonisolated static func showsTranslationRow(localization: String?) -> Bool {
        guard let localization, !localization.isEmpty else { return false }
        return !localization.hasPrefix("en")
    }

    nonisolated static func shouldInvite(localization: String?, alreadyShown: Bool) -> Bool {
        !alreadyShown && showsTranslationRow(localization: localization)
    }
}
```

- [ ] **Step 4: Register the file in `project.pbxproj`** — add one line directly after each of the four `AppRelocation.swift` lines (`grep -n 'AppRelocation.swift' DockTile.xcodeproj/project.pbxproj` shows them: PBXBuildFile, PBXFileReference, the Managers group's children, Sources build phase):

```
		AATRI00B /* TranslationInvite.swift in Sources */ = {isa = PBXBuildFile; fileRef = AATRI00A /* TranslationInvite.swift */; };
		AATRI00A /* TranslationInvite.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TranslationInvite.swift; sourceTree = "<group>"; };
				AATRI00A /* TranslationInvite.swift */,
				AATRI00B /* TranslationInvite.swift in Sources */,
```

- [ ] **Step 5: Add the strings** — new group in `AppStrings.swift`, after `enum SmartAdd`:

```swift
    // MARK: - Translation (review invitation)

    enum Translation {
        static let title = NSLocalizedString(
            "translation.title",
            value: "Translation",
            comment: "About: translation row label (shown only when the UI runs in a non-English language)"
        )
        static let reviewLine = NSLocalizedString(
            "translation.reviewLine",
            value: "Machine translated. Not yet checked by a native speaker.",
            comment: "About: translation row description. Reviewers replace this in their language with who reviewed it, e.g. 'Reviewed by @handle'."
        )
        static let helpImprove = NSLocalizedString(
            "translation.helpImprove",
            value: "Help Improve…",
            comment: "Button: opens the language's review sheet on GitHub"
        )
        static let inviteTitle = NSLocalizedString(
            "translation.invite.title",
            value: "Dock Tile now speaks your language",
            comment: "One-time alert title on first launch in a machine-translated language"
        )
        static let inviteMessage = NSLocalizedString(
            "translation.invite.message",
            value: "This translation was made by a machine and has not yet been checked by a native speaker. If something reads wrong, you can fix it on GitHub — no coding needed.",
            comment: "One-time alert message inviting translation review"
        )
    }
```

- [ ] **Step 6: Add the links and the events**

In `AboutLinks` (`AboutView.swift`), after `spades`:
```swift
    static let repository = URL(string: "https://github.com/k97/dock-tile")!
    /// The language's review sheet on GitHub — its pencil icon is the whole reviewer toolchain.
    /// Not UTM-tagged: GitHub is not one of our sites.
    static func translationSheet(localization: String) -> URL {
        URL(string: "https://github.com/k97/dock-tile/blob/main/docs/l10n/\(localization).md") ?? repository
    }
```

In `AnalyticsEvent`, after `relocationMoveFailed`:
```swift
    case translationInviteShown = "translation_invite_shown"
    case translationHelpTapped = "translation_help_tapped"
```

- [ ] **Step 7: Add the About section** — in `AboutPaneView.body`, between the Support `Section` (Send Feedback / Copy Diagnostics) and the `Section` with `studioRow`:

```swift
                    if let localization = TranslationInvite.runningLocalization,
                       TranslationInvite.showsTranslationRow(localization: localization) {
                        Section {
                            LabeledContent {
                                Button(AppStrings.Translation.helpImprove) {
                                    DiagnosticsLog.shared.ui("About → Help Improve translation")
                                    AnalyticsService.shared.log(.translationHelpTapped,
                                                                ["source": "about", "ui_language": localization])
                                    NSWorkspace.shared.open(AboutLinks.translationSheet(localization: localization))
                                }
                            } label: {
                                Text(AppStrings.Translation.title)
                                Text(AppStrings.Translation.reviewLine)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
```

- [ ] **Step 8: Sync the catalog and run the tests**

Run: `python3 -I Scripts/l10n/l10n.py sync-keys`
Expected: `added 5 keys`.

Run: TEST(TranslationInviteTests), TEST(AppStringsTests), TEST(AnalyticsServiceTests), TEST(LocalizationCatalogTests), and the `AboutLinksTests` suite.
Expected: all `TEST SUCCEEDED`.

- [ ] **Step 9: Commit**

```bash
git add DockTile/Constants/AppStrings.swift DockTile/Views/AboutView.swift DockTile/Managers/AnalyticsService.swift DockTile/Managers/TranslationInvite.swift DockTile.xcodeproj/project.pbxproj DockTileTests/Unit/Constants/AppStringsTests.swift DockTileTests/Unit/Managers/TranslationInviteTests.swift DockTile/Resources/Localizable.xcstrings
git add -u DockTileTests
git commit -m "feat(l10n): About pane Translation row with the GitHub review link

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: One-time review invitation alert

**Files:**
- Modify: `DockTile/Managers/TranslationInvite.swift` (append the manager)
- Modify: `DockTile/Constants/UserDefaultsKeys.swift`
- Modify: `DockTile/App/AppDelegate.swift` (the deferred launch block, after `AppRelocationManager.shared.checkOnLaunch()`)
- Modify: `DockTileTests/Unit/Managers/TranslationInviteTests.swift`

**Interfaces:**
- Consumes: Task 6's seams, strings, events, link.
- Produces: `TranslationInviteManager.shared.checkOnLaunch()`, `UserDefaultsKeys.translationInviteShown`.

- [ ] **Step 1: Write the failing test** — append to `TranslationInviteTests`:

```swift
    @Test("Invite once, and only where the row shows",
          arguments: [("zh-Hans", false, true), ("zh-Hans", true, false), ("en-GB", false, false),
                      ("ja", false, true), ("ja", true, false)])
    func inviteDecision(localization: String, alreadyShown: Bool, invites: Bool) {
        #expect(TranslationInvite.shouldInvite(localization: localization, alreadyShown: alreadyShown) == invites)
    }

    @Test("A Mac the app does not localize (Korean resolves to en-GB) is never invited")
    func unsupportedLanguageResolvesToEnglish() {
        #expect(TranslationInvite.shouldInvite(localization: "en-GB", alreadyShown: false) == false)
        #expect(TranslationInvite.shouldInvite(localization: nil, alreadyShown: false) == false)
    }
```

- [ ] **Step 2: Run to verify it passes already** (the seam exists since Task 6)

Run: TEST(TranslationInviteTests)
Expected: `TEST SUCCEEDED`. The seam is pinned; the rest of this task is wiring that no unit test reaches. Step 6 proves only the silent English path; the alert's buttons and link are first exercised by hand in Task 9 Step 1, once a non-English localization exists.

- [ ] **Step 3: Add the UserDefaults key** in `UserDefaultsKeys.swift`, after `relocationPromptSuppressed`:

```swift
    /// The one-time "Dock Tile now speaks your language" review invitation has been shown. Main-app
    /// domain; stamped BEFORE the alert appears so a crash in the alert can never loop it.
    static let translationInviteShown = "translationInviteShown"
```

- [ ] **Step 4: Append the manager** to `TranslationInvite.swift`:

```swift
@MainActor
final class TranslationInviteManager {
    static let shared = TranslationInviteManager()
    private init() {}

    /// Main-app only; the caller (`configureAsMainApp`) already skips it under tests. Runs after the
    /// relocation nudge so a Downloads-run Mac sees the move prompt first.
    func checkOnLaunch() {
        guard !AppEnvironment.isHelper else { return }
        let localization = TranslationInvite.runningLocalization
        let shown = UserDefaults.standard.bool(forKey: UserDefaultsKeys.translationInviteShown)
        guard TranslationInvite.shouldInvite(localization: localization, alreadyShown: shown) else { return }
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.translationInviteShown)
        let language = localization ?? "unknown"
        DiagnosticsLog.shared.log("translation", "Inviting review of the \(language) translation")
        AnalyticsService.shared.log(.translationInviteShown, ["ui_language": language])

        let alert = NSAlert()
        alert.messageText = AppStrings.Translation.inviteTitle
        alert.informativeText = AppStrings.Translation.inviteMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppStrings.Translation.helpImprove)
        alert.addButton(withTitle: AppStrings.Button.notNow)
        // App-modal like the relocation nudge: it fires from the launch block, before any sheet host.
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DiagnosticsLog.shared.ui("Translation invite → Help Improve")
        AnalyticsService.shared.log(.translationHelpTapped, ["source": "alert", "ui_language": language])
        NSWorkspace.shared.open(AboutLinks.translationSheet(localization: language))
    }
}
```

- [ ] **Step 5: Wire it** in `AppDelegate.swift`, inside the `DispatchQueue.main.asyncAfter` block, right after `AppRelocationManager.shared.checkOnLaunch()`:

```swift
            // Invite native speakers to review a machine-first translation: one alert, once, only
            // when the UI runs in a non-English localization. After the relocation nudge on purpose.
            TranslationInviteManager.shared.checkOnLaunch()
```

- [ ] **Step 6: Build and verify by hand** (no language exists yet, so prove the English path is silent and the gate works)

Run: `xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

Run: `xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug -showBuildSettings | grep ' BUILT_PRODUCTS_DIR'` and note the directory (call it `<BUILT_PRODUCTS_DIR>` below and in Tasks 8–9).
Run: `codesign --verify "<BUILT_PRODUCTS_DIR>/Dock Tile Dev.app"` then `open "<BUILT_PRODUCTS_DIR>/Dock Tile Dev.app"`.
Expected: no alert (English). `defaults read com.docktile.dev.app translationInviteShown` → `does not exist` (nothing stamped in English).

- [ ] **Step 7: Commit**

```bash
git add DockTile/Managers/TranslationInvite.swift DockTile/Constants/UserDefaultsKeys.swift DockTile/App/AppDelegate.swift DockTileTests/Unit/Managers/TranslationInviteTests.swift
git commit -m "feat(l10n): one-time review invitation on first launch in a translated language

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Glossary, the five languages, machine pass, import

**Files:**
- Create: `docs/l10n/GLOSSARY.md`
- Create: `docs/l10n/zh-Hans.md`, `docs/l10n/ja.md`, `docs/l10n/de.md`, `docs/l10n/ru.md`, `docs/l10n/fr.md` (via `export`, then filled)
- Modify: `DockTile/Resources/Localizable.xcstrings` (via `import`)
- Modify: `DockTile.xcodeproj/project.pbxproj` (`knownRegions`)
- Modify: `DockTileTests/Unit/Constants/LocalizationCatalogTests.swift` (`languages`)

**Interfaces:**
- Consumes: Task 5's CLI.
- Produces: the shipped catalog with eight languages; sheets reviewers will edit.

- [ ] **Step 1: Write `docs/l10n/GLOSSARY.md`**

```markdown
# Glossary and rules for every translation pass

Machine passes and human reviewers both follow this file. When in doubt, use the word Apple's
own macOS uses for the same thing in that language. Apple's strings are readable without
switching the system language:

    plutil -p /System/Library/ExtensionKit/Extensions/DesktopSettings.appex/Contents/Resources/Localizable.loctable | grep -A1 '"<key>"'

(the table is keyed by language code: `zh_CN`, `ja`, `de`, `ru`, `fr`; "程序坞" appears 20 times
for `zh_CN` on macOS 27, and Japanese keeps "Dock").

## Never translated
Dock Tile (the product) · Sparkle · Happy Machines Company · Spades Audio · SF Symbol names ·
`%@` `%d` `%lld` placeholders (keep them, in order) · `…` (keep the ellipsis character) · ⌘ ⌥ ⇧
glyphs · "Ghost Mode" stays in Latin letters with the local word in brackets on first use only if
the string has room, otherwise untranslated. Apple's own app names follow Apple: Finder and
Spotlight are renamed in Simplified Chinese (table below) and kept everywhere else. `l10n.py`
enforces this list (`PROTECTED_TERMS`).

## Apple's terms (verified against Apple's loctables on macOS 27, see the command above)
| English | zh-Hans | ja | de | ru | fr |
|---|---|---|---|---|---|
| Dock | 程序坞 | Dock | Dock | Dock | Dock |
| Finder | 访达 | Finder | Finder | Finder | Finder |
| Spotlight | 聚焦 | Spotlight | Spotlight | Spotlight | Spotlight |
| tile (ours) | 磁贴 | タイル | Kachel | плитка | tuile |
| popover (ours) | 弹出面板 | ポップオーバー | Popover | всплывающая панель | fenêtre contextuelle |
| Applications folder | 应用程序 | アプリケーション | Programme | Программы | Applications |
| Accessibility (permission) | 辅助功能 | アクセシビリティ | Bedienungshilfen | Универсальный доступ | Accessibilité |
| Login Items | 登录项 | ログイン項目 | Anmeldeobjekte | Объекты входа | Ouverture |
| App Switcher (⌘Tab) | 应用程序切换器 | アプリケーションスイッチャー | App-Umschalter | переключатель приложений | sélecteur d'applications |
| Light / Dark (appearance) | 浅色 / 深色 | ライト / ダーク | Hell / Dunkel | Светлое / Тёмное | Clair / Sombre |

## Register
de: **du** (Apple's German since macOS 10.15) · fr: **vous** · ru: **вы** (lower case) ·
ja: です/ます · zh-Hans: 你 (not 您).

## Length
German and Russian run ~30% longer than English. Prefer the shorter natural phrasing for button
titles and toggle labels; keep sentences for descriptions. Never abbreviate a word Apple spells out.

## Punctuation
zh-Hans and ja use full-width punctuation (，。：) and no space before or after Latin words only
where Apple does; fr uses a narrow no-break space before `:` `;` `!` `?`; ru uses « » quotes;
de uses „ “ quotes.
```

- [ ] **Step 2: Create the five sheets**

Run, one per language: `python3 -I Scripts/l10n/l10n.py export --lang zh-Hans` (then `ja`, `de`, `ru`, `fr`).
Expected: five files under `docs/l10n/`, every row status `todo`, Translation column empty.

- [ ] **Step 3: Machine pass — fill each sheet's Translation column**

For each of the five sheets, in order zh-Hans, ja, de, ru, fr: read `GLOSSARY.md`, then work through the file in blocks of ~40 rows, writing the translation into the third column and setting Status to `machine` on every row you fill. Rules that are not negotiable: the row's placeholders (`%@` etc.) appear in the translation exactly as in the English; `\n` and `\|` are kept as the two-character sequences; the Key and Context columns are never edited; `translation.reviewLine` is translated as a sentence that says the text was machine-translated and not yet checked (reviewers rewrite it later); `smartAdd.identity.*` are one-word tile names that fit a Dock label; button titles are short. Leave no row `todo`.

- [ ] **Step 4: Import, then pin the languages**

Run, one per language: `python3 -I Scripts/l10n/l10n.py import zh-Hans` (then `ja`, `de`, `ru`, `fr`).
Expected: each prints `<lang>: N entries updated` with N equal to the catalog's key count, and the sheet is rewritten normalised.

Edit `LocalizationCatalogTests.languages` to:
```swift
    static let languages: Set<String> = ["en-AU", "en-GB", "en-US", "zh-Hans", "ja", "de", "ru", "fr"]
```

Edit `knownRegions` in `project.pbxproj` (Task 0 already added the three English regions) to:
```
			knownRegions = (
				en,
				Base,
				"en-GB",
				"en-AU",
				"en-US",
				"zh-Hans",
				ja,
				de,
				ru,
				fr,
			);
```
(`knownRegions` is bookkeeping Xcode maintains when a language is added in its UI; the catalog compiler emits every localization the file contains regardless. Step 5's `.lproj` listing is the proof, not this edit.)

- [ ] **Step 5: Run the guards**

Run: TEST(LocalizationCatalogTests)
Expected: `TEST SUCCEEDED`. If `formatSpecifiersMatchSource` or `everyLanguageHasEveryKey` fails, the message names `lang:key`; fix that cell in the sheet, re-`import`, re-run.

Run: `python3 -I Scripts/l10n/l10n.py check`
Expected: `review sheets consistent with the catalog`.

Run: `xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug build` then `ls "<BUILT_PRODUCTS_DIR>/Dock Tile Dev.app/Contents/Resources" | grep lproj`
Expected: `de.lproj en-AU.lproj en-GB.lproj en-US.lproj fr.lproj ja.lproj ru.lproj zh-Hans.lproj`.

- [ ] **Step 6: Commit**

```bash
git add docs/l10n DockTile/Resources/Localizable.xcstrings DockTile.xcodeproj/project.pbxproj DockTileTests/Unit/Constants/LocalizationCatalogTests.swift
git commit -m "feat(l10n): machine-first Simplified Chinese, Japanese, German, Russian and French

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Hands-on layout check in German and Simplified Chinese

**Files:**
- Possibly modify: whichever view truncates (expected candidates: `GeneralSettingsView.swift`, `DockLockSettingsView.swift`, `PopoverAppearanceView.swift`, `SmartAddSheet.swift`, `DockTileDetailView.swift`)

**Interfaces:** none.

- [ ] **Step 1: Rebuild signed and launch in German**

Run: `xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug build` (no `CODE_SIGNING_ALLOWED=NO`), then `codesign --verify "<BUILT_PRODUCTS_DIR>/Dock Tile Dev.app"`.
Run: `defaults write com.docktile.dev.app AppleLanguages "(de)"` then `open "<BUILT_PRODUCTS_DIR>/Dock Tile Dev.app"`.
Expected: the one-time alert appears in German with "Help Improve…" and "Not Now" translated. Press Not Now.

- [ ] **Step 2: Capture every pane by window ID** (never a screen rect — `.claude/rules/driving-the-dev-build.md`)

Select, in turn, a tile (Tile Detail), Settings → General, Popover, Dock Lock, About, and press + for Smart Add. For each, `Scripts/dev-capture.sh` into the scratchpad and read the image. Look for: ellipsised toggle labels, a wrapped action button in the title band, Smart Add card names that clip, About row text overlapping its button.

- [ ] **Step 3: Repeat in Simplified Chinese**

Run: `defaults write com.docktile.dev.app AppleLanguages "(zh-Hans)"`, relaunch, repeat Step 2. Also confirm the About pane's Translation row reads the Chinese `translation.reviewLine` and its button opens `https://github.com/k97/dock-tile/blob/main/docs/l10n/zh-Hans.md`.

- [ ] **Step 3b: Prove the unsupported-language fallback (Review Focus 4)**

Run: `defaults write com.docktile.dev.app AppleLanguages "(ko)"`, relaunch.
Expected: the UI is English (en-GB spellings: "Customise"), no invitation alert, no Translation row in About, and `defaults read com.docktile.dev.app translationInviteShown` still reports the value Task 9 Step 1 left (it must not have been re-stamped by this launch — delete the key before this step to make that observable, then expect `does not exist` after it).

- [ ] **Step 4: Fix only what truncates**

For a clipped label: `.fixedSize(horizontal: false, vertical: true)` on that `Text` so it wraps; for a clipped button title: shorten the translation in the sheet (preferred) and re-`import`. Do not widen windows or restructure rows. Re-capture after each fix.

- [ ] **Step 5: Restore and verify**

Run: `defaults delete com.docktile.dev.app AppleLanguages` and `defaults delete com.docktile.dev.app translationInviteShown`.
Run: TEST(all)
Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit** (only if Step 4 changed anything)

```bash
git add -u DockTile docs/l10n DockTile/Resources/Localizable.xcstrings
git commit -m "fix(l10n): wrap labels that truncated in German and Chinese

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Rules, README, release materials, GitHub + GA4 setup commands

**Files:**
- Modify: `.claude/rules/localization-macos.md` (rewrite)
- Modify: `CLAUDE.md` (the Localization bullet)
- Modify: `README.md` (`## Translations` section before `## Development`)
- Create: `docs/l10n/release-announcement.md`
- Create: `docs/l10n/issues/umbrella.md`, `docs/l10n/issues/language.md`

**Interfaces:** none (documentation and release-time commands).

- [ ] **Step 1: Rewrite `.claude/rules/localization-macos.md`**

```markdown
# Localization (macOS App)

## Languages

| Locale | Role |
|---|---|
| `en-GB` | Source language and fallback for every unsupported language |
| `en-AU`, `en-US` | Spelling variants (Customise/Customize, Colour/Color) |
| `zh-Hans`, `ja`, `de`, `ru`, `fr` | **Machine-first**, reviewed by native speakers from the user base |

Chosen from GA4 (2026-10-17): non-English Macs were 45% of monthly actives; zh-Hans is the only
cohort above 10 users. Adding a language costs one `export --lang`, one machine pass, one `import`.

## Architecture

- **Format**: String Catalog `Localizable.xcstrings`, in the app target since 2026-10-17 — **it never
  was before**, so no `.lproj` shipped and en-US/en-AU spellings never reached a user. `InfoPlist.xcstrings`
  stays OUT of the target on purpose: a localized `InfoPlist.strings` overrides `Info.plist` for Launch
  Services, and every helper is a copy with `CFBundleName` rewritten to the tile's name, so shipping it
  would make every tile read "Dock Tile" in ⌘Tab and Finder (`catalogShipsAndInfoPlistStringsDoesNot`).
- **Development region is `en-GB`** (= the catalog's `sourceLanguage`), so a Mac set to an unshipped
  language falls back to en-GB, not to a nonexistent `en.lproj`.
- **Accessors**: `DockTile/Constants/AppStrings.swift`, always `NSLocalizedString(key, value:, comment:)`
  in that three-argument shape — `Scripts/l10n/l10n.py` parses it and refuses any other shape.
- **The catalog is the runtime source; the review sheets `docs/l10n/<lang>.md` are derived.**
  `l10n.py` is the only writer of non-English entries and of new keys (`sync-keys`). Machine
  entries carry state `needs_review`, reviewed ones `translated`; both compile and ship (verified
  with `xcstringstool compile`, 2026-10-17). `LocalizationCatalogTests` pins the language set,
  code-key ⊆ catalog, per-language completeness and format-placeholder parity.
- **Invitation**: `TranslationInvite` seams (`TranslationInviteTests`) show the About Translation
  row and a one-time alert only when `Bundle.main.preferredLocalizations.first` is non-English — an
  unsupported language resolves to en-GB, so it is never invited. Events `translation_invite_shown`
  / `translation_help_tapped` carry `ui_language` (never `language`, GA4's automatic dimension).

## Workflow

| When | Run |
|---|---|
| New or changed `AppStrings` key | `python3 -I Scripts/l10n/l10n.py sync-keys`, fix any en-US spelling it warns about, then `export` |
| Reviewer PR merged | `python3 -I Scripts/l10n/l10n.py import <lang>`, commit the catalog |
| Before pushing | `python3 -I Scripts/l10n/l10n.py check` (CI runs it with the Python tests). Green while a reviewer's sheet is *ahead* of the catalog; red on a stale export, unknown key, lost placeholder or dropped glossary term |

Editing `.xcstrings` by hand is allowed only to fix an **English** value, textually in place
(anchored on the neighbouring key, matching the file's `json.dumps(indent=2)` style). Never
load-and-redump it by any other route than `l10n.py`, which preserves key order. Xcode's catalog
editor rewrites the whole file in its own style (`"key" : value`, sorted) — harmless to the round
trip, but a noisy diff; prefer not to open it there.

## Usage

```swift
Button(AppStrings.Button.customise) { ... }  // correct
Button("Customise") { ... }                   // wrong — never hardcode
```

Categories: `Button.*`, `Label.*`, `Menu.*`, `Navigation.*`, `Section.*`, `Empty.*`, `Error.*`,
`SmartAdd.*`, `Translation.*`, `Log.*` (logs are NOT localised).

## Testing a language by hand

```bash
defaults write com.docktile.dev.app AppleLanguages "(de)"        # or zh-Hans, ja, ru, fr, en-US
defaults delete com.docktile.dev.app AppleLanguages              # reset
defaults delete com.docktile.dev.app translationInviteShown      # see the one-time alert again
```

Capture windows by ID (driving-the-dev-build.md). German and Russian run ~30% long: check toggle
labels, the title-band action button, Smart Add cards. Glossary and register rules:
`docs/l10n/GLOSSARY.md`; reviewer guide: `docs/l10n/README.md`.
```

- [ ] **Step 2: Update `CLAUDE.md`'s Localization bullet** to:

```markdown
- [Localization](/.claude/rules/localization-macos.md) — String Catalogs, en-GB source + en-US/en-AU, machine-first zh-Hans/ja/de/ru/fr reviewed via `docs/l10n/` sheets, `Scripts/l10n/l10n.py` round trip
```

- [ ] **Step 3: Add `## Translations` to `README.md`** before `## Development`:

```markdown
## Translations

Dock Tile ships in English, 简体中文, 日本語, Deutsch, Русский and Français. The non-English
translations are machine-first and reviewed by native speakers. Spotted a mistake? Fixing it takes
five minutes in the browser — see [docs/l10n/README.md](docs/l10n/README.md).
```

- [ ] **Step 4: Write `docs/l10n/release-announcement.md`** (English skeleton; translate each paragraph into its own language following the glossary — the paragraph for zh-Hans is written in Chinese, and so on):

```markdown
# Release-notes paragraphs for the localization release

Paste each paragraph into the GitHub release notes under a `### Now in your language` heading.
The website and Sparkle read release notes from GitHub.

**English.** Dock Tile now speaks 简体中文, 日本語, Deutsch, Русский and Français. These
translations were made by a machine and have not yet been checked by native speakers. If you read
one of these languages and something sounds wrong, you can fix it in five minutes in your browser —
no coding — at https://github.com/k97/dock-tile/blob/main/docs/l10n/README.md. Reviewers are
credited in the app.

**简体中文.** <the same paragraph in Simplified Chinese>

**日本語.** <the same paragraph in Japanese>

**Deutsch.** <the same paragraph in German, "du" register>

**Русский.** <the same paragraph in Russian>

**Français.** <the same paragraph in French, "vous" register>
```

(Replace every `<…>` with the translated paragraph before committing — a placeholder here is a plan failure.)

- [ ] **Step 5: Write the GitHub issue bodies**

`docs/l10n/issues/umbrella.md`:
```markdown
Dock Tile ships machine-first translations in 简体中文, 日本語, Deutsch, Русский and Français.
Native speakers: please check your language. It takes a GitHub account and the pencil icon, no
coding — guide: https://github.com/k97/dock-tile/blob/main/docs/l10n/README.md

One issue per language is linked below. Reviewers are credited in the app's About pane and in
the release notes. To request another language, comment here with the macOS language name.
```

`docs/l10n/issues/language.md` (used once per language, `LANG` and `CODE` substituted):
```markdown
Help review the LANG translation (`docs/l10n/CODE.md`).

1. Open https://github.com/k97/dock-tile/blob/main/docs/l10n/CODE.md and press the pencil icon.
2. Fix the **Translation** column; set **Status** to `reviewed` on every row you checked.
3. Rewrite the `translation.reviewLine` row in LANG to say who reviewed it (your handle).
4. **Propose changes** → **Create pull request**.

Prefer to just tell us? Comment here with the key and the better wording. Glossary:
https://github.com/k97/dock-tile/blob/main/docs/l10n/GLOSSARY.md
```

- [ ] **Step 6: Record the release-time commands** at the end of `docs/l10n/README.md` under `## Maintainer workflow` (the outer fence below is four backticks only so this plan renders; the README gets the inner `### One-time setup…` heading and its single bash block):

````markdown
### One-time setup before the first localized release

```bash
# GA4: register the ui_language event parameter (forward-only; do it BEFORE tagging)
TOKEN=$(gcloud auth print-access-token --account=ga4-fetch@dock-tile.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/analytics.edit)
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  https://analyticsadmin.googleapis.com/v1beta/properties/542196919/customDimensions \
  -d '{"parameterName":"ui_language","displayName":"UI language","description":"Localization the app UI was running in","scope":"EVENT"}'

# GitHub: label + umbrella issue + one issue per language
gh label create translation --color 0E8A16 --description "Translation review"
gh issue create --title "Translations: help review the machine-first languages" \
  --label translation,"help wanted" --body-file docs/l10n/issues/umbrella.md
for pair in "简体中文:zh-Hans" "日本語:ja" "Deutsch:de" "Русский:ru" "Français:fr"; do
  lang=${pair%%:*}; code=${pair##*:}
  sed -e "s/LANG/$lang/g" -e "s/CODE/$code/g" docs/l10n/issues/language.md > /tmp/body.md
  gh issue create --title "Review the $lang translation" --label translation,"help wanted" --body-file /tmp/body.md
done
```
````

- [ ] **Step 7: Verify docs are consistent**

Run: `grep -rn 'insert textually\|never load-and-redump\|Editing .xcstrings outside Xcode' .claude/rules CLAUDE.md`
Expected: only the rewritten rule's "textually in place … only to fix an English value" sentence; no stale instruction elsewhere.

Run: `python3 -I Scripts/l10n/l10n.py check` and TEST(all)
Expected: in sync; `TEST SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add .claude/rules/localization-macos.md CLAUDE.md README.md docs/l10n
git commit -m "docs(l10n): localization rule, reviewer guide, release announcement and setup commands

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-review

- **Spec coverage**: catalog in the target + en-GB region + InfoPlist exclusion (Task 0); languages + machine-first (Task 8); sheet round trip + states + relaxed `check` (Task 5); 68 missing keys (Task 2); hardcoded strings incl. Smart Add names (Task 3); credits via `translation.reviewLine` (Tasks 6, 8); glossary with a runnable Apple-terms lookup (Task 8); About row + link + events (Task 6); one-time alert (Task 7); `ui_language` registration, labels, issues, release notes (Task 10); guards (Tasks 0, 4, 5, 6, 7); hands-on layout + Korean fallback (Task 9); licence + trademarks (Task 1); rule rewrite (Task 10). Website: untouched.
- **Placeholders**: the only `<…>` are in Task 10 Step 4's skeleton, with an explicit instruction that they must be replaced before committing, and `<BUILT_PRODUCTS_DIR>` / `<key>`, which name values the step tells the implementer how to obtain.
- **Type consistency**: `showsTranslationRow` / `shouldInvite` / `runningLocalization` (Tasks 6, 7, 10); `translationSheet(localization:)` (Tasks 6, 7); `Row`, `render_sheet`, `parse_sheet`, `apply_sheet`, `lint_rows` (reviewer-class, used by `import` and `check`), `stale_rows` (maintainer-class, `check` only), `specifiers`, `PROTECTED_TERMS` (per-language renames), `sheet_languages` (Tasks 5, 8); `LocalizationCatalogTests` created in Task 0 and extended in Task 4 (`languages` pinned there, widened in Task 8); event raw values match the spec.
- **Review Focus**: 1 → Task 4 `formatSpecifiersMatchSource` + Task 5 `lint_rows`; 2 → Task 5 `Cells`; 3 → Task 5 `importRejectsUnknownKey` + `statusIsCaseInsensitive` + `Check`; 4 → Tasks 6/7 `TranslationInviteTests` + Task 0 region + Task 9 Step 3b; 5 → Task 9 hands-on; 6 → Task 0 `catalogShipsAndInfoPlistStringsDoesNot`.
- **Plan gate (2026-10-17, independent reviewer)**: returned Needs answers on five points; all five are resolved above — the catalog registration (Task 0), the `en-GB` development region + Korean hands-on (Tasks 0, 9), the `check` semantics that keep reviewer PRs green (Task 5), the licence holder set to the GitHub username `k97` plus `TRADEMARKS.md` (Task 1), and the modal alert kept as the approved design with the alternatives recorded in the spec.
