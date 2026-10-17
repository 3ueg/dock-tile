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
