# Multi-Language Support — Design

**Date:** 2026-10-17 · **Status:** approved in conversation (goal, approach and review process), awaiting spec review
**Evidence:** GA4 read of 2026-10-17 (below). Analytics access and property IDs: `.claude/rules/analytics.md`.

## Intent

Ship Dock Tile's UI in the languages its users' Macs actually run, starting with Simplified
Chinese, with translations that are **machine-first and reviewed by native speakers from the user
base**. The app invites those users itself, and reviewing needs no clone, no Xcode and no JSON.

Decisions taken with k97 (2026-10-17):

| Question | Decision |
|---|---|
| Why now | Non-English Macs went from ~10% of monthly active users (Jun/Jul) to **45%** (Sep, Oct). Chinese and Japanese cohorts activate worse than English (45% / 25% vs 59%). |
| Languages (first release) | **zh-Hans, ja, de, ru, fr** — the five non-English cohorts with ≥6 active users. More are cheap to add later (one `export`, one machine pass). |
| Translation source | **Machine-first, reviewed by natives (option 3).** An LLM pass fills every language; the app invites native speakers to review; credit is the payment. |
| Review mechanism | **GitHub web editor on a per-language Markdown review sheet** (`docs/l10n/<lang>.md`). A script round-trips sheet ↔ String Catalog. Fallback: comment on the language's GitHub issue. No Crowdin/Weblate, no Google Form. |
| Invitation | In-app: a one-time alert on first launch in a machine-first language + a permanent "Translation" row in About, both only when the running localization is not English. Plus one paragraph per language in the release notes, and a `translation` label + issues on GitHub. |
| Licence | **MIT for the code**; the Dock Tile name, logo and app icon are excluded. A public repo inviting contributions without a licence leaves them in legal limbo. |
| Website | **Out of scope.** The site stays en-AU/GB/US by design; a Chinese site is separate work with SEO consequences. |
| Machine-entry state | Catalog state `needs_review` (verified 2026-10-17: `xcstringstool compile` emits `needs_review` and `new` entries, so they ship; Xcode shows them yellow). Reviewed = `translated`. |
| Invitation surface | A one-time **modal alert at launch** (same `runModal` pattern as the relocation nudge) plus the About row. Considered and rejected: About row + release notes only (nobody opens About, so nobody is invited); a non-modal banner in the main window (a new UI surface and more code for a one-time message). |
| Who is "the machine" | The implementing agent fills the review sheets, reading the glossary and each string's comment. Considered: Apple's Translation framework (macOS 15, needs on-device models and a UI session, no glossary) and DeepL (API key, no UI context). Both would translate strings blind to where they appear. |
| Apple's XLIFF round trip | Rejected as the simpler path: `xcodebuild -exportLocalizations` produces XLIFF, which a reviewer cannot edit with GitHub's pencil icon; the catalog is `extractionState: manual`, so Xcode's automatic sync does not apply either. The Markdown sheet IS the reviewer interface, so the script has to exist regardless. |
| Licence rationale | MIT because it is the shortest, GitHub-detectable, the licence the vendored compiler declares, and the norm for indie Mac apps (Maccy, Rectangle, Ice). Apache-2.0's patent grant buys nothing for a GUI utility; copyleft would not stop the redistribution already happening. MIT licenses copyright, not trademarks, so the name and logo stay protected regardless; `TRADEMARKS.md` states that plainly. The copyright holder is the GitHub username `k97`, the only name the repo uses for its author. (A surname nobody recognised had been sitting in `InfoPlist.xcstrings` since commit `495b16d`, 2026-02-05; removed 2026-10-17.) |

## Findings from the plan gate (2026-10-17) that change the design

- **The String Catalog has never been in the app target.** `project.pbxproj` references neither
  `.xcstrings` file; the built dev app and the installed 2.2.2 release carry zero `.lproj` folders.
  Every string has always resolved to its `value:` default, and the en-US/en-AU spellings have
  never reached a user (`AppStringsTests` parses the JSON file, so it could not notice). The first
  task registers `Localizable.xcstrings`; from then on a US-locale Mac sees "Customize"/"Color".
- **`InfoPlist.xcstrings` stays OUT of the target, deliberately.** A localized `InfoPlist.strings`
  overrides `Info.plist` for Launch Services, and every helper bundle is a copy of the main app
  with its `CFBundleName`/`CFBundleDisplayName` rewritten to the tile's name — shipping the file
  would make every tile read "Dock Tile" in ⌘Tab and Finder. Nothing in it needs localizing
  ("Dock Tile" is the same in every language; the copyright line stays English). Guarded by a
  test that the host bundle has no `InfoPlist.strings`.
- **Development region becomes `en-GB`** (`CFBundleDevelopmentRegion` and the pbxproj
  `developmentRegion`), matching the catalog's `sourceLanguage`. Today it is `en`, for which no
  `.lproj` will exist, so a Mac set to an unshipped language (Korean) would have no defined
  fallback. Verified by hand with `AppleLanguages "(ko)"`: English UI, no invitation.
- **CI `check` must not fail a reviewer's pull request.** A reviewer's edit makes the sheet run
  *ahead* of the catalog until the maintainer imports it; that is the designed state, not an
  error. So `check` fails only on what a reviewer can break or a maintainer can forget: unknown
  keys, an English column that no longer matches the catalog (stale export), a key missing from
  the sheet (stale export), lost `%@` placeholders, and protected glossary terms missing from a
  translation (per language: Finder must read 访达 in zh-Hans). A translation that differs from the
  catalog passes. **`import` refuses only the reviewer-class problems** (unknown key, placeholder,
  term) and accepts a stale sheet, re-rendering it afterwards — otherwise a merged reviewer PR
  could be answered with "run export", which overwrites the very edits it brought.
- **Glossary terms are verified against Apple's own strings**, not by switching the system
  language: `plutil -p /System/Library/ExtensionKit/Extensions/DesktopSettings.appex/Contents/
  Resources/Localizable.loctable` lists every language's Desktop & Dock strings (程序坞 appears 20
  times for zh_CN on macOS 27).
- Xcode's catalog editor rewrites the file in its own style (`"key" : value`, sorted). The script
  reads either style and writes its own; opening the file in Xcode costs a noisy diff, nothing
  more. Prefer not to.

## Evidence (GA4 app stream, 2026-06-01 → 2026-10-17; dimension = the Mac's system language)

| Month | Active users | English-locale share |
|---|---:|---:|
| Jun | 15 | 87% |
| Jul | 29 | 90% |
| Aug | 85 | 71% |
| Sep | 104 | 55% |
| Oct (partial) | 80 | 55% |

Cohorts (active users, whole window): zh-Hans 29 · ru 9 · de 8 · ja 8 · fr 6 · it 5 · pt-BR 4 ·
ko 3 active but 19 new (16 never had an engaged session). Activation (first_open →
tile_added_to_dock): en 59%, zh 45%, ja 25% (n=8), de/fr/ru/it 75–100% (tiny n). 46% of Chinese
actives since September still run 1.8.5 (vs 14% of English) — likely a third-party Chinese
download site; those users will not see any of this. Country is not the signal (en-de, en-cn,
en-tr users chose English). Total N is 237, so cohort percentages are indicative only.

## Model

**The String Catalog stays the single runtime source.** `Localizable.xcstrings`, `sourceLanguage`
en-GB, localizations en-GB / en-AU / en-US (existing) + zh-Hans / ja / de / ru / fr. Every UI string
keeps going through `AppStrings` (`NSLocalizedString(key, value:, comment:)`), unchanged.

**Every `AppStrings` key must exist in the catalog.** Today 68 of 214 do not (they exist only as the
`value:` default in code — Popover Appearance, Dock Lock, Start at Login, settings sidebar,
relocation alerts). Invisible in English, but a new language has no slot for them. A script
(`sync-keys`) backfills them from `AppStrings.swift`, and a Swift test keeps code and catalog equal
from then on.

**Remaining hardcoded strings move into `AppStrings`:** the delete-confirmation message
(`DockTileDetailView`), the Dock menu's "Configure..." / "No apps configured" / "No configuration"
(`AppDelegate`, `HelperAppDelegate` — `menu.configure` already exists and is simply unused there),
and the Smart Add identity names Browse / Watch / Ship / Chat / Work / Together
(`SmartAddEngine`, these become Dock tile labels).

**Review sheets are derived, never hand-maintained.** `Scripts/l10n/l10n.py` owns the round trip:

| Command | Does |
|---|---|
| `sync-keys` | Parses `AppStrings.swift`; adds every missing key to the catalog with the en-GB/en-AU/en-US value = the code default, inserted in key order; warns on UK spellings that need an en-US override. |
| `export [--lang L]` | Writes `docs/l10n/<L>.md` for every non-English language in the catalog (or the one given, which is how a language is started). |
| `import <L>` | Reads the sheet back into the catalog: `reviewed` → `translated`, `machine` → `needs_review`, empty translation → untouched. Unknown key → exit 2. Re-exports the sheet to normalise it. |
| `check` | Exit 1 when a sheet is missing, names an unknown key, has a stale English column, lacks a catalog key, loses a placeholder, or drops a protected term. A sheet that is merely ahead of the catalog (reviewer edits pending import) passes. Runs in CI on every push and PR. |

The script loads and saves the catalog with `json` (`indent=2`, `ensure_ascii=False`, trailing
newline), which is the file's existing style, and **preserves key order** (new keys are inserted in
ASCII order among existing ones). It is the only writer of non-English entries. The "insert
textually, never redump" rule in `localization-macos.md` becomes "only the script redumps".

**Sheet format** (one file per language, keys in catalog order):

```
# Dock Tile — 简体中文 (zh-Hans)

How to review: [docs/l10n/README.md](README.md). Edit the **Translation** column, set **Status**
to `reviewed` for every row you checked (changed or not), then "Propose changes".

| Key | English | Translation | Status | Context |
|---|---|---|---|---|
| `about.title` | About | 关于 | machine | About pane title |
```

Status is `machine`, `reviewed` or `todo` (no translation yet). Cells encode a newline as the two
characters `\n` and a pipe as `\|`. The reviewer's interface is this table and GitHub's pencil icon;
the machine's interface is the same table.

**Credits live in the catalog.** A key `translation.reviewLine` whose per-language value is shown
verbatim in About. The machine pass translates its English source ("Machine translated. Not yet
checked by a native speaker."); a reviewer rewrites it in their language ("由 @handle 校对") like any
other row. No generated Swift, no manifest.

**Glossary** `docs/l10n/GLOSSARY.md`: terms that never translate (Dock Tile, Sparkle), terms that
follow Apple's own macOS localization (Dock → 程序坞, Finder → 访达, Spotlight → 聚焦 in zh-Hans;
all three unchanged in ja/de/fr/ru — read from Apple's loctables, see below), register per language
(de "du" as Apple does, fr "vous", ru "вы", ja です/ます, zh-Hans 你), and the rules every pass obeys:
keep `%@`/`%d` placeholders, keep `…`, keep ⌘ glyphs, keep SF Symbol names untouched.

## Invitation (app side)

`TranslationInvite` (new file `DockTile/Managers/TranslationInvite.swift`, pbxproj entry):

- Pure seam `showsTranslationRow(localization: String?) -> Bool`: true when the bundle's chosen
  localization (`Bundle.main.preferredLocalizations.first`, e.g. `"zh-Hans"`) is non-nil and does
  not start with `en`. A Korean user's bundle resolves to en-GB, so they are never invited to review
  a language that does not exist.
- Pure seam `shouldInvite(localization:alreadyShown:)` = `!alreadyShown && showsTranslationRow`.
- `TranslationInviteManager.shared.checkOnLaunch()`: main-app only, skipped under tests, runs in
  the same deferred block as the relocation nudge (after it; two modal alerts in sequence on a
  non-English Mac running from Downloads is accepted). Shows one `NSAlert` (title
  `translation.invite.title`, message `translation.invite.message`, buttons `translation.helpImprove`
  / `button.notNow`), stamps `UserDefaultsKeys.translationInviteShown`, logs
  `translation_invite_shown`; the help button opens the language's sheet and logs
  `translation_help_tapped` with `source: "alert"`.
- About pane: a "Translation" section between Support and "Also from", shown only when
  `showsTranslationRow`. Label `translation.title`, caption `translation.reviewLine`, trailing
  button `translation.helpImprove` → `AboutLinks.translationSheet(localization:)` =
  `https://github.com/k97/dock-tile/blob/main/docs/l10n/<localization>.md`, logging
  `translation_help_tapped` with `source: "about"`.
- Both events carry `ui_language` (the localization). `ui_language`, not `language`: GA4 already
  has an automatic `language` dimension. Register `ui_language` as an EVENT-scope custom dimension
  before the release (registration is forward-only).

## Guards

- `LocalizationCatalogTests` (Swift, reads the repo via `#filePath` like `AppStringsTests`): every
  key referenced in `AppStrings.swift` exists in the catalog; the catalog's language set is exactly
  the pinned eight; every language has every key with a non-empty value; the multiset of format
  specifiers (`%@`, `%d`, `%lld`, `%1$@`…) in every language equals en-GB's (a dropped `%@` would
  crash `String(format:)` at runtime); `translation.reviewLine` exists in every language.
- `TranslationInviteTests`: the two seams, including nil, `"en-GB"`, `"en"`, `"zh-Hans"`, and
  already-shown.
- `AboutLinksTests`: the sheet URL for `"zh-Hans"`.
- `AnalyticsServiceTests` already sweeps `AnalyticsEvent.allCases`; the two new events join it.
- `Scripts/l10n/test_l10n.py` (unittest): export→import is the identity; `reviewed`/`machine` map to
  the right states; cell escaping round-trips newlines and pipes; `sync-keys` adds missing keys in
  order and warns on UK spellings; `check` passes a sheet that is ahead of the catalog and fails a
  stale one, a lost placeholder and a dropped protected term. CI runs it and `check` in
  `build-and-test` before the Xcode build.
- `LocalizationCatalogTests.catalogShipsAndInfoPlistStringsDoesNot`: the host bundle has an
  `en-GB.lproj/Localizable.strings` and no `InfoPlist.strings`.
- Hands-on: run the dev build in German and Simplified Chinese (`defaults write com.docktile.dev.app
  AppleLanguages "(de)"`), capture Settings, Tile Detail, Smart Add and About by window ID, look for
  truncation. Fix layout only where it truncates. Then `(ko)`: English UI, no alert, no About row.

## Release-time process (documented in `docs/l10n/README.md`, run by k97)

1. Register `ui_language` in GA4 (Admin API, `ga4-fetch` SA, `analytics.edit` scope).
2. `gh label create translation`; one umbrella issue + one issue per language from the bodies in
   `docs/l10n/issues/`.
3. Paste `docs/l10n/release-announcement.md` (one paragraph per language, in that language) into
   the GitHub release notes; the website and Sparkle read them from there.
4. Merge reviewer PRs; run `l10n.py import <lang>`; commit; the next release ships it.

## Out of scope

Website localization; right-to-left languages; plural rules (`.stringsdict` — no count strings
today); localized screenshots; Sparkle appcast localization (Sparkle's own UI is already localized
by the framework); the Chinese 1.8.5 redistribution problem (separate investigation).
