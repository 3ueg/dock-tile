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
