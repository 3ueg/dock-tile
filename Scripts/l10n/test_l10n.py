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


if __name__ == "__main__":
    unittest.main()
