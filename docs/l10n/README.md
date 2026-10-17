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
