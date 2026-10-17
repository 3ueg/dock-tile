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


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("sync-keys").set_defaults(run=cmd_sync_keys)
    export = sub.add_parser("export")
    export.add_argument("--lang")
    export.set_defaults(run=cmd_export)
    imp = sub.add_parser("import")
    imp.add_argument("lang")
    imp.set_defaults(run=cmd_import)
    sub.add_parser("check").set_defaults(run=cmd_check)
    args = parser.parse_args(argv)
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
