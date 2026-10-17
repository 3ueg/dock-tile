# Dock Tile — Deutsch (de)

How to review: [docs/l10n/README.md](README.md). Edit the **Translation** column, set
**Status** to `reviewed` for every row you checked (changed or not), then "Propose changes".
Status values: `machine` (not yet checked by a person), `reviewed`, `todo` (no translation yet).
Keep `%@`-style placeholders exactly as they are. `\n` means a line break, `\|` a pipe.

| Key | English | Translation | Status | Context |
|---|---|---|---|---|
| `alert.applyPopover.message` | Dock Tile will rebuild your pinned tiles with the new popover look and briefly restart the Dock. Your other Dock items won't be affected. |  | todo | Confirmation message warning the Dock will restart when applying popover settings |
| `alert.applyPopover.title` | Apply to your Dock tiles? |  | todo | Confirmation title before rebuilding tiles to apply popover appearance settings |
| `alert.deleteTile.message` | This will permanently delete the tile and remove it from the dock. |  | todo | Delete-tile confirmation message |
| `alert.missingApps.message` | Some apps in your tiles can't be found on this Mac. Remove them from your tiles? |  | todo | Alert message offering to remove uninstalled apps from tiles |
| `alert.missingApps.title` | Some apps are no longer installed |  | todo | Alert title when apps referenced by tiles can't be found on disk |
| `alert.missingAppsScan.foundMessage` | These apps can't be found on this Mac: |  | todo | Intro line of the manual scan results dialog; a list of tiles/apps follows |
| `alert.missingAppsScan.noneMessage` | Every app in your tiles is currently installed. |  | todo | Message of the manual scan dialog when nothing is missing |
| `alert.missingAppsScan.noneTitle` | No Missing Apps |  | todo | Title of the manual scan dialog when every tile app is installed |
| `alert.relocate.blockingMessage` | Dock Tile can't create or update this tile because it's running from a temporary, read-only location. This happens when the app is launched from Downloads. Move Dock Tile to your Applications folder and try again. |  | todo | Message shown when a tile action is blocked because the app is translocated |
| `alert.relocate.checkbox` | Don't ask again |  | todo | Checkbox to suppress future move-to-Applications nudges |
| `alert.relocate.message` | Dock Tile is running from outside your Applications folder. macOS may run it from a temporary, read-only location, which can stop new tiles from being created. Move it to Applications to make sure everything works. |  | todo | Message of the launch-time nudge to move the app to Applications |
| `alert.relocate.title` | Move Dock Tile to Applications? |  | todo | Title of the prompt asking the user to move the app into the Applications folder |
| `alert.restartDock.checkbox` | Don't show this again |  | todo | Checkbox label to suppress future Dock restart alerts |
| `alert.restartDock.message` | Dock Tile restarts the Dock to apply changes. This happens whenever you add, update, or remove tiles. Your current Dock items won't be affected. |  | todo | Alert message explaining Dock restart |
| `alert.restartDock.title` | Dock Restart Required |  | todo | Alert title when Dock restart is required |
| `app.name` | Dock Tile |  | todo | App display name |
| `button.add` | Add |  | todo | Add button label in file picker |
| `button.addToDock` | Add to Dock |  | todo | Button to add tile to Dock |
| `button.applyToTiles` | Apply |  | todo | Confirm button that rebuilds tiles to apply popover settings |
| `button.back` | Back |  | todo | Back button label |
| `button.cancel` | Cancel |  | todo | Cancel button in alerts |
| `button.checkForUpdates` | Check for Updates… |  | todo | Button that triggers a manual Sparkle update check |
| `button.checkNow` | Check Now |  | todo | Settings → Software Update: button that triggers a manual Sparkle update check |
| `button.confirm` | Confirm |  | todo | Confirm button for alert dialogs |
| `button.createNewTile` | Create New Tile |  | todo | Smart Add sheet — neutral button that starts a blank tile instead of a suggestion |
| `button.customise` | Customise |  | todo | Button to open customization view |
| `button.delete` | Delete |  | todo | Delete button |
| `button.done` | Done |  | todo | Done button |
| `button.duplicate` | Duplicate |  | todo | Duplicate button in context menu |
| `button.keep` | Keep |  | todo | Button to keep uninstalled apps in tiles (dismiss the removal prompt) |
| `button.moveToApplications` | Move to Applications |  | todo | Button that moves the app into the Applications folder |
| `button.newTile` | New Tile |  | todo | Button to create first tile on empty state |
| `button.notNow` | Not Now |  | todo | Dismiss button for the non-blocking move-to-Applications nudge |
| `button.openAccessibilitySettings` | Open Accessibility Settings… |  | todo | Button that opens the Accessibility pane in System Settings (Reduce Motion) |
| `button.openLoginItems` | Open Login Items Settings… |  | todo | Button that opens System Settings Login Items for approval |
| `button.remove` | Remove |  | todo | Remove button |
| `button.removeAll` | Remove All |  | todo | Button to remove all missing apps from tiles at once |
| `button.removeFromDock` | Remove from Dock |  | todo | Button to remove tile from Dock |
| `button.resetToDefaults` | Reset to Defaults |  | todo | Button that restores popover appearance settings to their defaults |
| `button.reviewInTiles` | Review in Tiles |  | todo | Button that navigates to the first tile containing a missing app |
| `button.save` | Save |  | todo | Primary toolbar button that commits the popover appearance settings |
| `button.saving` | Applying… |  | todo | Loading label on the Save button while applying settings to Dock tiles |
| `button.scanForMissingApps` | Scan |  | todo | Settings button that scans tiles for moved/uninstalled apps |
| `button.update` | Update |  | todo | Update button when tile is already in Dock |
| `button.useThisTile` | Use This Tile |  | todo | Smart Add sheet — button that creates a pre-filled tile from a suggestion |
| `empty.createFirstTile` | Create Your First Tile |  | todo | Header text for empty state |
| `empty.detail` | Detail |  | todo | Placeholder text in detail view |
| `empty.noApps` | No apps configured |  | todo | Empty state text when no apps configured |
| `empty.noTiles` | No Tiles |  | todo | Empty state text in sidebar |
| `error.appTranslocated` | Dock Tile is running from a temporary, read-only location and can't create tiles. Move it to your Applications folder and try again. |  | todo | Error when the app is translocated and cannot generate helper bundles |
| `error.bundleBuildInProgress` | This tile is already being rebuilt. Wait for that to finish, then try again. |  | todo | Error when a second build is requested for a tile whose helper bundle is already being built |
| `error.failedToCodeSign` | Failed to code sign helper bundle |  | todo | Error when code signing fails |
| `error.failedToCopyBundle` | Failed to copy bundle |  | todo | Error when bundle copy fails |
| `error.failedToReadInfoPlist` | Failed to read Info.plist |  | todo | Error when Info.plist cannot be read |
| `error.failedToWriteInfoPlist` | Failed to write Info.plist |  | todo | Error when Info.plist cannot be written |
| `error.mainAppNotFound` | Main Dock Tile.app not found |  | todo | Error when main app bundle cannot be found |
| `filePicker.message` | Select one or more applications or folders to add |  | todo | Message in file picker dialog |
| `label.background` | Background |  | todo | Customise Tile: background row label |
| `label.background.colour` | Colour |  | todo | Customise Tile: Colour background chip |
| `label.background.colour.accessibility` | Colour, filled with your colour |  | todo | VoiceOver label for the Colour chip |
| `label.background.hint.colour` | Filled with your colour |  | todo | Customise Tile: hint under Background when Colour |
| `label.background.hint.mono` | White in Light Mode, black in Dark Mode |  | todo | Customise Tile: hint under Background when Mono |
| `label.background.hint.mono.static` | White tile with a coloured symbol |  | todo | Customise Tile: hint under Background when Mono on macOS 15 (static white tile) |
| `label.background.mono` | Mono |  | todo | Customise Tile: Mono background chip |
| `label.background.mono.accessibility` | Mono, white in Light Mode and black in Dark Mode |  | todo | VoiceOver label for the Mono chip |
| `label.background.mono.static.accessibility` | Mono, a white tile with a coloured symbol |  | todo | VoiceOver label for the Mono chip on macOS 15 |
| `label.colour` | Colour |  | todo | Label for colour picker section |
| `label.colour.hint.deepened` | Deepened slightly so the symbol stays clear |  | todo | Customise Tile: colour hint when the fill was darkened for contrast |
| `label.colour.hint.emoji` | Emoji keep their own colours |  | todo | Customise Tile: colour hint, Mono emoji tile (row disabled) |
| `label.colour.hint.fills` | Fills the tile |  | todo | Customise Tile: colour hint, Colour tile |
| `label.colour.hint.toned` | Toned for Light and Dark |  | todo | Customise Tile: colour hint, Mono tile |
| `label.colour.hint.toned.static` | Toned to stay clear on white |  | todo | Customise Tile: colour hint, Mono tile on macOS 15 |
| `label.iconSize` | Icon Size |  | todo | Compact label for the icon size stepper (side-by-side with icon weight) |
| `label.iconWeight` | Icon Weight |  | todo | Label for the SF Symbol weight picker |
| `label.iconWeightInfo` | Weight applies to symbols only. Emoji aren’t affected. |  | todo | Popover/help note explaining that the icon weight setting affects symbols but not emoji |
| `label.iconWeightInfo.accessibility` | About Icon Weight |  | todo | VoiceOver label for the icon weight info button |
| `label.missingAppsScan` | Missing Apps |  | todo | Settings row title for the missing-app scan |
| `label.missingAppsScanDescription` | Check your tiles for apps that have been moved or uninstalled. |  | todo | Settings row description for the missing-app scan |
| `label.notInstalled` | Not installed |  | todo | Badge/kind text shown for an app whose bundle is no longer on disk |
| `label.popover.animation` | Animation |  | todo | Label for the popover animation segmented control |
| `label.popover.highlightOnHover` | Highlight on Hover |  | todo | Toggle label — show a background fill on the hovered item |
| `label.popover.layout` | Layout |  | todo | Label for the Grid/List preview toggle in popover settings |
| `label.popover.listAlwaysLabelled` | List view always shows labels |  | todo | Hint shown beside the disabled Show Labels control when previewing List |
| `label.popover.showLabels` | Show Labels |  | todo | Toggle label — show app names under grid icons |
| `label.popover.size` | Popover Size |  | todo | Label for the popover size segmented control |
| `label.popover.spacing` | Spacing |  | todo | Label for the popover item spacing segmented control |
| `label.popover.tileSize` | Tile Size |  | todo | Label for the icon/cell size control inside the popover |
| `label.preview.dark` | Dark |  | todo | Customise Tile: caption under the Dark Mode preview |
| `label.preview.light` | Light |  | todo | Customise Tile: caption under the Light Mode preview |
| `label.shareAnalytics` | Share anonymous usage data |  | todo | Label for the analytics opt-out toggle in Settings |
| `label.shareAnalyticsDescription` | Help improve Dock Tile by sending anonymous usage and crash reports. No personal data is collected. |  | todo | Explanation under the analytics toggle |
| `label.addAppsAndFolders` | Add Apps & Folders |  | todo | Tooltip on the Add button in Tile Detail's In This Tile section |
| `label.appSwitcherNeedsShowTile` | Turn on Show Tile first — this only applies while the tile is in the Dock. |  | todo | Tooltip on the disabled Show in App Switcher toggle when the tile is hidden |
| `label.showInAppSwitcher` | Show in App Switcher |  | todo | Label for app switcher toggle |
| `label.showTile` | Show Tile |  | todo | Label for show tile toggle |
| `label.softwareUpdate` | Software Update |  | todo | Title of the software-update row in General settings |
| `label.softwareUpdateDescription` | You’re using version %@. Dock Tile checks for updates automatically. |  | todo | Description under the software-update row; %@ is the current version |
| `label.startAtLogin` | Start tiles at login |  | todo | Label for the start-at-login toggle in Settings |
| `label.startAtLoginDescription` | Keep your tiles ready in the Dock so they respond instantly after you restart your Mac. |  | todo | Explanation under the start-at-login toggle |
| `label.symbolColour` | Symbol Colour |  | todo | Customise Tile: colour row label for a Mono tile |
| `label.tileIcon` | Tile Icon |  | todo | Label for tile icon section |
| `label.tileIconSize` | Tile Icon Size |  | todo | Label for tile icon size |
| `label.tileName` | Tile Name |  | todo | Label for tile name field |
| `layout.grid` | Grid |  | todo | Grid layout option |
| `layout.list` | List |  | todo | List layout option |
| `itemMenu.forceQuit` | Force Quit |  | todo | Popover item context menu: force quit (shown while Option is held) |
| `itemMenu.getInfo` | Get Info |  | todo | Popover item context menu: open Finder's Get Info window |
| `itemMenu.hide` | Hide |  | todo | Popover item context menu: hide the running app |
| `itemMenu.open` | Open |  | todo | Popover item context menu: open the app or folder |
| `itemMenu.quickLook` | Quick Look |  | todo | Popover item context menu: preview the item with Quick Look |
| `itemMenu.quit` | Quit |  | todo | Popover item context menu: quit the running app |
| `itemMenu.share` | Share… |  | todo | Popover item context menu: open the share sheet for a folder |
| `itemMenu.showInFinder` | Show in Finder |  | todo | Popover item context menu: reveal the item in Finder |
| `menu.configure` | Configure... |  | todo | Menu item to configure tile (opens main app) |
| `menu.configureTile` | Configure Tile |  | todo | Tooltip for gear icon in popover |
| `menu.copyDiagnostics` | Copy Diagnostics |  | todo | File menu item that copies recent diagnostic logs to the clipboard |
| `menu.newTile` | New Dock Tile |  | todo | Menu item to create a new tile |
| `menu.noAppsConfigured` | No apps configured |  | todo | Dock menu: disabled row when the tile has no apps |
| `menu.noConfiguration` | No configuration |  | todo | Dock menu: disabled row when the tile's config cannot be found |
| `menu.openInFinder` | Open in Finder |  | todo | Menu item to open in Finder |
| `menu.options` | Options |  | todo | Section divider in menu |
| `menu.settings` | Settings… |  | todo | App menu item that opens the inline Settings pane (⌘,) |
| `navigation.customiseTile` | Customise Tile |  | todo | Navigation title for customise tile view |
| `popover.option.animation.default` | Default |  | todo | Animation tier — default |
| `popover.option.animation.fast` | Fast |  | todo | Animation tier — fast |
| `popover.option.animation.none` | None |  | todo | Animation tier — none |
| `popover.option.comfortable` | Comfortable |  | todo | Spacing tier — comfortable |
| `popover.option.compact` | Compact |  | todo | Spacing tier — compact |
| `popover.option.large` | Large |  | todo | Size tier — large |
| `popover.option.medium` | Medium |  | todo | Size tier — medium |
| `popover.option.small` | Small |  | todo | Size tier — small |
| `popover.option.spacious` | Spacious |  | todo | Spacing tier — spacious |
| `search.emojis` | Search emojis |  | todo | Search placeholder for emojis |
| `search.symbols` | Search symbols |  | todo | Search placeholder for symbols |
| `settings.dockLock` | Dock Lock |  | todo | Section header for the Dock Lock feature in Settings |
| `settings.dockLock.accessibilityGranted` | Accessibility access granted |  | todo | Status shown when Accessibility permission is granted |
| `settings.dockLock.accessibilityNeeded` | Accessibility access required |  | todo | Status shown when Accessibility permission is missing |
| `settings.dockLock.accessibilityNeededDetail` | Dock Tile needs Accessibility access to keep the Dock in place. Turn on Dock Tile in System Settings. |  | todo | Explanation of why Accessibility access is needed |
| `settings.dockLock.anchor` | Keep Dock on |  | todo | Label for the anchor display picker |
| `settings.dockLock.defaultDisplay` | Default (follow macOS) |  | todo | First option in the anchor picker — no lock, macOS default behaviour |
| `settings.dockLock.description` | Stop the Dock from jumping between screens on multi-display setups. It stays on the display you choose. |  | todo | Explanation under the Dock Lock toggle |
| `settings.dockLock.lockedTo` | Dock is locked to %@ |  | todo | Indicator confirming the display the Dock is pinned to |
| `settings.dockLock.mainDisplay` | Main |  | todo | Suffix marking the main display in the anchor picker |
| `settings.dockLock.moveFailed` | Couldn't move the Dock to %@. Make sure that display isn't mirrored, then try again. |  | todo | Error shown when the Dock could not be relocated |
| `settings.dockLock.moving` | Moving Dock to %@… |  | todo | Progress message shown while the Dock is being relocated |
| `settings.dockLock.note` | Works with the Dock at the bottom, left, or right. Keeping it on a screen reserves a few pixels at that edge on your other displays. |  | todo | Footnote describing Dock Lock behaviour and trade-off |
| `settings.dockLock.openSettings` | Open System Settings… |  | todo | Button that opens the Accessibility pane in System Settings |
| `settings.dockLock.primer.body` | Dock Lock keeps the Dock on the display you choose. To do that, Dock Tile needs Accessibility access so it can stop macOS from moving the Dock to your other screens. |  | todo | Explanation in the permission primer |
| `settings.dockLock.primer.continue` | Continue |  | todo | Primary button in the permission primer that triggers the macOS dialog |
| `settings.dockLock.primer.notNow` | Not Now |  | todo | Secondary button in the permission primer that cancels enabling Dock Lock |
| `settings.dockLock.primer.reassurance` | Next, macOS will ask you to turn on Dock Tile in System Settings. You can turn this off any time. |  | todo | Reassurance line in the permission primer about what happens next |
| `settings.dockLock.primer.title` | Allow Accessibility Access |  | todo | Title of the permission primer shown before requesting Accessibility |
| `settings.dockLock.retry` | Try Again |  | todo | Button to retry a failed Dock relocation |
| `settings.dockLock.singleDisplay` | Connect a second display to use Dock Lock. With one screen the Dock stays exactly where macOS puts it. |  | todo | Note shown when only one display is connected |
| `settings.dockLock.toggle` | Lock Dock to one display |  | todo | Label for the Dock Lock enable toggle |
| `settings.general` | General |  | todo | Title of the General settings pane |
| `settings.login.registrationFailed` | Couldn’t turn this on — macOS refused the registration. %@ |  | todo | Shown under the Start tiles at login toggle when SMAppService registration failed; %@ is the system error |
| `settings.login.requiresApproval` | Approve Dock Tile in Login Items to finish enabling this. |  | todo | Shown when macOS is holding the login item for user approval |
| `settings.popover` | Popover |  | todo | Section header and pane title for popover appearance settings |
| `settings.popover.configure` | Configure |  | todo | Label for the Grid/List panel switcher in popover settings |
| `settings.popover.configure.subtitle` | Each layout's settings are saved independently |  | todo | Subtitle explaining that Grid and List popover settings are stored separately |
| `settings.popover.footer` | These settings apply to every tile's popover. List view always shows labels. Animation follows your system Reduce Motion setting. |  | todo | Explanatory footer under the popover settings form |
| `settings.popover.reduceMotion` | Animation is off because Reduce Motion is on in System Settings. |  | todo | Caption shown under Animation when the system Reduce Motion setting forces it off |
| `settings.popover.section.tiles` | Tiles |  | todo | Section header for the per-item controls inside the popover settings |
| `sidebar.section.settings` | Settings |  | todo | Sidebar section header for the inline app settings panes |
| `sidebar.section.tiles` | Tiles |  | todo | Sidebar section header for the list of dock tiles |
| `sidebar.title` | Dock Tile |  | todo | Navigation title for sidebar |
| `smartAdd.identity.browse` | Browse |  | todo | Smart Add: suggested tile name for browsers |
| `smartAdd.identity.chat` | Chat |  | todo | Smart Add: suggested tile name for social apps |
| `smartAdd.identity.ship` | Ship |  | todo | Smart Add: suggested tile name for developer tools |
| `smartAdd.identity.together` | Together |  | todo | Smart Add: suggested tile name for apps opened together |
| `smartAdd.identity.watch` | Watch |  | todo | Smart Add: suggested tile name for video apps |
| `smartAdd.identity.work` | Work |  | todo | Smart Add: suggested tile name for productivity apps |
| `smartAdd.privacyFootnote` | Learned on your Mac. Never leaves your device. |  | todo | Footer note stating Smart Add suggestions are computed on-device only |
| `smartAdd.provenanceBanner` | Created by Smart Add from your recent apps. Rename it, restyle it or edit the apps — then add it to your Dock. |  | todo | Banner shown atop Tile Detail when a tile was just created by Smart Add |
| `smartAdd.reason.byCategory` | By category |  | todo | Reason chip — apps grouped by their app category |
| `smartAdd.reason.mostUsed` | Most used this week |  | todo | Reason chip — the most-used cluster this week |
| `smartAdd.reason.openedTogether` | Opened together |  | todo | Reason chip — apps repeatedly opened in the same session |
| `smartAdd.settings.sectionHeader` | Smart Add |  | todo | General settings section header for the Smart Add toggle |
| `smartAdd.settings.toggleDescription` | Learned on your Mac. Never leaves your device. |  | todo | General: Smart Add toggle description |
| `smartAdd.settings.toggleTitle` | Suggest tiles from my apps |  | todo | General: Smart Add toggle title |
| `smartAdd.title` | Add a Tile |  | todo | Header title of the Smart Add suggestion sheet |
| `subtitle.chooseColour` | Choose a background colour for your tile |  | todo | Subtitle for colour picker section |
| `subtitle.configureToAdd` | Configure to add apps |  | todo | Subtitle in empty state (grid view only) |
| `subtitle.iconSize` | Adjust the size of your icon within the tile |  | todo | Subtitle for icon size section |
| `tab.emoji` | Emoji |  | todo | Emoji tab label |
| `tab.symbol` | Symbol |  | todo | Symbol tab label |
| `title.deleteTile` | Delete Tile |  | todo | Alert title for delete confirmation |
| `tooltip.createNewTile` | Create new tile |  | todo | Tooltip when add button is enabled |
| `tooltip.editFirst` | Edit current tile before creating another |  | todo | Tooltip when add button is disabled |
| `button.addATile` | Add a Tile… |  | todo | Sidebar + / empty state: opens the Add a Tile dialog |
| `sidebar.dockTileSection` | Dock Tile |  | todo | Sidebar section holding About |
| `settings.addingTiles` | Adding Tiles |  | todo | General: section holding the Smart Add toggle and the Add a Tile row |
| `about.title` | About |  | todo | About pane title |
| `about.version` | Version %@ |  | todo | About: version line |
| `about.website` | Website |  | todo | About: website row label |
| `about.feedbackTitle` | Found a bug or have an idea? |  | todo | About: feedback card title |
| `about.feedbackBody` | Feedback goes straight to the developer. Diagnostics attach a log of what the app and its tiles did — nothing personal. |  | todo | About: feedback card body |
| `about.sendFeedback` | Send Feedback… |  | todo | About: opens the feedback email |
| `about.alsoFrom` | Also from Happy Machines |  | todo | About: studio section header |
| `about.studioTitle` | Made by Happy Machines Company |  | todo | About: studio row title |
| `about.studioSubtitle` | A tiny product studio building nifty Mac apps that each fix one thing well. |  | todo | About: studio row subtitle |
| `about.spadesTitle` | Spades Audio |  | todo | About: sibling product row title |
| `about.spadesSubtitle` | Per-app volume, EQ and output control for your Mac, from the menu bar. |  | todo | About: sibling product subtitle |
| `about.learnMore` | Learn More… |  | todo | About: opens spadesaudio.com |
| `menu.aboutDockTile` | About Dock Tile |  | todo | App menu |
| `popover.editing.remove` | Remove |  | todo | Context menu / remove badge in the tile editor |
| `section.inThisTile` | In This Tile |  | todo | Tile Detail: apps section header |
| `label.editorHint` | Hover to remove · Drag to reorder |  | todo | Tile Detail: apps section caption |
| `tooltip.deleteTile` | Delete Tile |  | todo | Tile Detail: trash button tooltip |
| `smartAdd.blankTitle` | Create a blank tile |  | todo | Add a Tile: blank row title |
| `smartAdd.blankSubtitle` | Name it, pick an icon and add apps yourself. |  | todo | Add a Tile: blank row subtitle |
| `smartAdd.orStartFrom` | or start from what you use |  | todo | Add a Tile: rule between blank row and suggestions |
| `smartAdd.noSuggestions` | No suggestions yet — Dock Tile learns from the apps you open. You can turn this off in General. |  | todo | Add a Tile: empty suggestions note |
| `label.addAppsTooltip` | Add apps or folders to this tile |  | todo | Tooltip on the + Add button above the tile editor's popover preview. |
| `empty.createFirstTileDescription` | Group apps and folders behind one Dock icon. Start blank, or from a tile suggested from the apps you use. |  | todo | Zero-tiles description |
| `popover.editing.noAppsTitle` | No apps yet |  | todo | Tile editor: empty popover preview, title line. |
| `popover.editing.noAppsSubtitle` | Use Add to choose what opens from this tile. |  | todo | Tile editor: empty popover preview, subtitle line. |
| `about.diagnosticsBody` | A log of what the app and its tiles did. Attach it to an email when something looks wrong — it contains nothing personal. |  | todo | About: Copy Diagnostics row description. |
| `about.feedbackRowBody` | Feedback goes straight to the developer. |  | todo | About: Send Feedback row description. |
| `about.diagnosticsTitle` | Diagnostics |  | todo | About: Copy Diagnostics row label. |
| `button.copy` | Copy |  | todo | Generic Copy button label. |
| `tooltip.openSettings` | Settings |  | todo | Tooltip for the settings toolbar button |
| `translation.helpImprove` | Help Improve… |  | todo | Button: opens the language's review sheet on GitHub |
| `translation.invite.message` | This translation was made by a machine and has not yet been checked by a native speaker. If something reads wrong, you can fix it on GitHub — no coding needed. |  | todo | One-time alert message inviting translation review |
| `translation.invite.title` | Dock Tile now speaks your language |  | todo | One-time alert title on first launch in a machine-translated language |
| `translation.reviewLine` | Machine translated. Not yet checked by a native speaker. |  | todo | About: translation row description. Reviewers replace this in their language with who reviewed it, e.g. 'Reviewed by @handle'. |
| `translation.title` | Translation |  | todo | About: translation row label (shown only when the UI runs in a non-English language) |
