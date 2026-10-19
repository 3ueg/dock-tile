# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.4.0] - 2026-10-19

Existing tiles keep their symbol or emoji. App Grid is the starting look for new tiles, and any
tile can switch to it in Customise Tile.

### Added

- **tiles:** Add the App Grid tile face: the Dock icon shows the tile's own apps in a folder-style grid on the system glass, like an iOS folder. One app fills the tile, two to four sit in a 2 × 2 grid, and five or more in a 3 × 3 grid of the first nine installed apps ([1473405](https://github.com/k97/dock-tile/commit/1473405))
- **tiles:** Show each app in an App Grid tile the way macOS draws that app in the current icon style (Default, Dark, Clear or Tinted), instead of its colour icon in every style ([bc53fb7](https://github.com/k97/dock-tile/commit/bc53fb7))
- **customise:** Redesign Customise Tile as a large preview beside an inspector, with an App Grid / Symbol / Emoji style picker whose options follow the chosen style ([be80f55](https://github.com/k97/dock-tile/commit/be80f55))
- **customise:** Remember a tile's last symbol and last emoji, with their icon sizes, so switching between the Symbol and Emoji styles no longer resets your choice ([fa7b988](https://github.com/k97/dock-tile/commit/fa7b988))
- **window:** Make the main window resizable between 782 and 1200 points wide ([1452c9c](https://github.com/k97/dock-tile/commit/1452c9c))

### Fixed

- **tiles:** Fix tiles in the sidebar and on Tile Detail looking different from the Dock under the Clear icon style; they now show the Dock's own rendering once the tile is updated ([bc53fb7](https://github.com/k97/dock-tile/commit/bc53fb7))
- **icons:** Fix an app installed as a link, such as Safari on macOS 27, drawing its icon with an alias arrow ([cabb11b](https://github.com/k97/dock-tile/commit/cabb11b))
- **login:** Fix the app carrying the development build's login item alongside its own; each build now ships only its own ([ee67b4c](https://github.com/k97/dock-tile/commit/ee67b4c))
- **localization:** Fix the wording of the Japanese Smart Add banner and the Russian Dock Lock note ([ee67b4c](https://github.com/k97/dock-tile/commit/ee67b4c))

## [2.3.1] - 2026-10-18

See the [GitHub release](https://github.com/k97/dock-tile/releases/tag/v2.3.1).

## [2.3.0] - 2026-10-18

See the [GitHub release](https://github.com/k97/dock-tile/releases/tag/v2.3.0).

## [2.2.2] - 2026-10-17

See the [GitHub release](https://github.com/k97/dock-tile/releases/tag/v2.2.2).

## [2.2.1] - 2026-10-17

See the [GitHub release](https://github.com/k97/dock-tile/releases/tag/v2.2.1).

## [2.2.0] - 2026-10-14

See the [GitHub release](https://github.com/k97/dock-tile/releases/tag/v2.2.0).

## [2.1.0] - 2026-10-13

See the [GitHub release](https://github.com/k97/dock-tile/releases/tag/v2.1.0).

## [2.0.3] - 2026-10-03

See the [GitHub release](https://github.com/k97/dock-tile/releases/tag/v2.0.3).

## [2.0.2] - 2026-09-21

Your existing tiles are rebuilt automatically the first time 2.0.2 launches, with one Dock restart,
so every fix below reaches them without any action from you.

### Changed

- **popover:** Open large tiles about a third faster and with consistent timing, by keeping app icons cached in the tile instead of asking macOS for them on every click ([5cd4aff](https://github.com/k97/dock-tile/commit/5cd4aff))
- **app:** Keep the main window responsive while a tile is being added or updated; icon compilation and code signing no longer freeze it for about a second per tile ([3274278](https://github.com/k97/dock-tile/commit/3274278))
- **settings:** Shrink the settings file from megabytes to kilobytes by no longer storing a copy of every app's icon; older files still load and slim down on their next save ([ea75c54](https://github.com/k97/dock-tile/commit/ea75c54))
- **window:** Fade a soft scrim in under the title band while scrolling, so content no longer collides with the pane title ([d770f77](https://github.com/k97/dock-tile/commit/d770f77))

### Fixed

- **install:** Fix "Move to Applications" failing for every install from the disk image; the app is now copied into place, the disk image is ejected afterwards, and an already-installed copy is reused instead of trashed ([49f82b6](https://github.com/k97/dock-tile/commit/49f82b6))
- **popover:** Fix a tile's memory growing by 3–5 MB on every click and never coming back, caused by a macOS 26 Liquid Glass leak that Dock Tile triggered by creating a new popover each time ([962bf44](https://github.com/k97/dock-tile/commit/962bf44))
- **dock:** Fix the app no longer noticing a tile dragged out of the Dock after the first Dock change of a session, which left the tile marked visible with nothing pinned ([e3c491e](https://github.com/k97/dock-tile/commit/e3c491e))
- **popover:** Fix the Animation "None" setting and the system Reduce Motion preference being ignored when a popover appears ([6dcc142](https://github.com/k97/dock-tile/commit/6dcc142))
- **popover:** Fix a click listener being left running after a popover closed by clicking elsewhere, which woke the tile on every click anywhere on the Mac ([6dcc142](https://github.com/k97/dock-tile/commit/6dcc142))
- **popover:** Fix app icons staying in the old appearance after changing macOS's "Icon and widget style" while a tile is running ([6ba1d46](https://github.com/k97/dock-tile/commit/6ba1d46))
- **tiles:** Fix a tile being corrupted if Update was pressed while the app was rebuilding that tile in the background ([eaa93c6](https://github.com/k97/dock-tile/commit/eaa93c6))
- **dock:** Fix hiding a tile during a background rebuild marking it hidden while it stayed in the Dock; the action now reports that the tile is busy ([a635f3a](https://github.com/k97/dock-tile/commit/a635f3a))
- **customise:** Fix dragging in the colour picker queuing a full settings save for every movement, which made the drag stutter ([d203c1e](https://github.com/k97/dock-tile/commit/d203c1e))
- **customise:** Fix Customise overwriting a tile's Dock visibility with the value from when the editor was opened ([eaa93c6](https://github.com/k97/dock-tile/commit/eaa93c6))
- **diagnostics:** Fix multi-line entries in Copy Diagnostics surviving the one-hour trim forever ([1e5a6a9](https://github.com/k97/dock-tile/commit/1e5a6a9))

[Unreleased]: https://github.com/k97/dock-tile/compare/v2.4.0...HEAD
[2.4.0]: https://github.com/k97/dock-tile/compare/v2.3.1...v2.4.0
[2.3.1]: https://github.com/k97/dock-tile/compare/v2.3.0...v2.3.1
[2.3.0]: https://github.com/k97/dock-tile/compare/v2.2.2...v2.3.0
[2.2.2]: https://github.com/k97/dock-tile/compare/v2.2.1...v2.2.2
[2.2.1]: https://github.com/k97/dock-tile/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/k97/dock-tile/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/k97/dock-tile/compare/v2.0.3...v2.1.0
[2.0.3]: https://github.com/k97/dock-tile/compare/v2.0.2...v2.0.3
[2.0.2]: https://github.com/k97/dock-tile/compare/v2.0.1...v2.0.2
