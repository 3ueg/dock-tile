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
| Accessibility (permission) | 无障碍 | アクセシビリティ | Bedienungshilfen | Универсальный доступ | Accessibilité |
| Login Items | 登录项 | ログイン項目 | Anmeldeobjekte | Объекты входа | Ouverture |
| App Switcher (⌘Tab) | App切换器 | アプリスイッチャー | App-Umschalter | Переключатель приложений | Sélecteur d’app |
| Light / Dark (appearance) | 浅色 / 深色 | ライト / ダーク | Hell / Dunkel | Светлое / Темное | Clair / Sombre |

Sources: Applications folder from `SystemFolderLocalizations`; Accessibility from the
Accessibility settings pane; Login Items from `LoginItems.appex`; App Switcher from
`MouseExtension.appex`; Light / Dark from `Appearance.appex`. Apple's Russian writes "Темное"
without ё; follow it.

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
