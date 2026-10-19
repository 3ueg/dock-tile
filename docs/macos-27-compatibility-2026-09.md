# macOS 27 compatibility review — 2026-09-29

Dock Tile 2.0.2 on macOS 27.0 "Golden Gate", with Xcode 27.0 and the 27 SDK. Version strings are
as the tools print them: `sw_vers` gives 27.0 build **26A428**, and `xcodebuild -version` gives
Xcode 27.0 build **27A266a**. The prefixes look off by one because Apple moved to year-based
numbering. The dev Mac was upgraded from 26.6.2 on **2026-09-22**, per `InstallHistory.plist`.
That was the day after 2.0.2 shipped, so every September perf and leak measurement was taken on
26, not 27.

**Scope.** "Compatibility check" is read here as three things: (1) does the app build and behave
correctly on macOS 27; (2) what it takes to *ship* a build made with the 27 toolchain; and
(3) housekeeping the upgrade surfaced. New macOS 27 features Dock Tile could adopt are out of
scope; see "Not proposed now".

## Verdict

**Nothing is broken, and nothing blocks users on 27.** The app builds clean under Xcode 27, the
whole unit suite passes, and every platform touchpoint checked on this Mac behaves as it did on
26. The work splits into three groups:

1. **Hands-on checks.** Some 27 behaviour changes can only be judged by looking at the running
   app. The biggest is the new Dock "Running in Background" indicator.
2. **Toolchain move.** CI and Release still build with **Xcode 26.2**, so users run a binary
   linked against the 26 SDK. Moving to Xcode 27 is the real compatibility step.
3. **Housekeeping.** Stale items the upgrade is a good moment to clear.

## Checked on this Mac (2026-09-29)

| Area | Result | How |
|---|---|---|
| Build, Xcode 27 / SDK 27 | Succeeds, 0 errors. **3 new warnings**, all `NSColor.quinaryLabel` → `quinaryLabelColor`. The other 7 warnings already existed under Xcode 26.2 | Clean Debug build compared with the last CI log |
| Unit tests | `** TEST SUCCEEDED **`: 665 passed, 7 skipped. The skips are the Dock-integration tests, which skip by design | Suite run with the command in CLAUDE.md |
| Icon compile on 27 | Passes: `fixtureCompilesToValidCar` and `builderOutputCompilesToValidCar` run the real compiler plus `assetutil` | Unit suite |
| `assetutil` output | Still reports all three `IconImageStack` appearances (Aqua, DarkAqua, Tintable) in the shape `IconCompiler` validates | `assetutil --info` on a prod helper |
| Helper generated on 27 | Prod helper `Utils` was rebuilt 2026-09-24 (post-upgrade). It is ad-hoc signed, carries `com.apple.provenance`, passes `codesign --verify`, and **runs** (pid launched `--background-launch`). A field report of provenance-tagged ad-hoc binaries being killed at launch does not reach our flow | `codesign`, `xattr`, `pgrep` |
| Helper seals | All 5 (2 prod, 3 dev) verify | `codesign --verify` |
| Dock plist schema | Our `persistent-apps` entries have exactly the same keys as Apple's own Mail entry, so no schema drift | Read `com.apple.dock.plist` |
| Login launcher (SMAppService) | Agent plist carries no quarantine xattr. launchd ran it at login and it exited 0. Relocation strips quarantine recursively (`xattr -dr`), so 27's new rule against quarantined launchd plists is covered | `launchctl print`, `xattr` |
| Dock Lock (CGEvent tap) | Enabled in prod; "Event tap installed" logged 2026-09-24 on 27. Accessibility grant survived the upgrade, whereas DockDoor lost its grant | Prod diagnostics log |
| Smart Add signal | `kMDItemUseCount` / `kMDItemLastUsedDate` still written after the upgrade | `mdls` |
| Dev diagnostics log | No failures | `diagnostics.log` |
| Private API | None: `CoreDock` appears only in a comment. All OS gates are `#available(macOS 26, *)`, so every Tahoe path, including declarative icons, is live on 27 | grep |
| Menu item images | Unaffected: no menu item sets an image | grep |
| Shipped architecture | `/Applications/Dock Tile.app` main binary is **arm64 only** | `lipo -archs` |

## What changed in 27 that touches Dock Tile

Sources are at the end. Tags: **[V]** read on an Apple page, **[S]** secondary or field report.

- **Dock "Running in Background" state [V].** If an app's processes keep running after it quits,
  the Dock shows a light-gray dot and adds a **Stop Running in Background** menu item. The first
  time, the user gets a notification. There is a new per-app toggle under *General → Login Items
  & Extensions → Background App Activity*. Apple's guidance exempts helpers launched by an app
  that stays in the Dock. Our shape is new: the main app launches LSUIElement helpers that
  outlive it, and at login an SMAppService agent spawns them and exits. **Highest-risk item;
  needs a live test.** Keyboard Maestro hit this pattern [S].
- **Liquid Glass transparency slider [S].** One system slider now controls the Dock, sidebars,
  toolbars and popovers; `NSGlassTintAmount` in the global domain looks like its backing value.
  The real popover follows it automatically. The Popover-settings preview only imitates popover
  chrome, so it may drift.
- **Sharper icon generation [V].** Icon Composer 2.0 adds refractivity, outside specular and
  deeper shadows for "2027 operating systems". Apple says documents in the original format
  still work on every OS. Xcode 26's actool reportedly **crashes** on 2.0-format files [S].
- **Behaviour changes for SDK-27-linked apps [V].** These take effect only once our release
  links the 27 SDK:
  - Menu item images hidden by default. Not used here.
  - `NSOpenPanel.allowedContentTypes` now also updates `canChooseFiles` / `canChooseDirectories`.
    **We use it** for the "add app or folder" picker; see B2.
  - Exclusive gesture recognizers. Not used here.
  - `NSTitlebarAccessoryViewController` drawing. Not used here.
  - `@State` is now a macro, and assigning it in `init` alongside a default breaks. **We
    compile clean**, so this does not reach us.
- **SwiftUI fix [S].** "Control-related view modifiers unexpectedly affect sheet and popover
  content." Worth re-measuring the 36×16 switch rule on 27.
- **Popover sizing [S].** On 27, an NSPopover anchored at a default size, whose SwiftUI content
  then grows, overflows the screen. The cure is `sizingOptions = .preferredContentSize`, which
  we already use.
- **NSPopover glass leak.** It no longer reproduces on 27.0, but no fix is mentioned in any 26.x
  or 27 release notes.
  - Re-tested 2026-09-29 in a parallel session (commit `5a6a511`; see
    [macos-26-popover-glass-leak.md](macos-26-popover-glass-leak.md)).
  - **Decision (k97): keep the one-popover-per-helper workaround**, un-gated. macOS 26 users
    still need it, and it costs nothing on 27.
- **Managed Macs [V].** On supervised Macs with an MDM App Settings allow/deny list, Endpoint
  Security **denies ad-hoc-signed binaries**, so our helpers would not launch there. No code fix
  exists short of Developer-ID-signing helpers, which can't be done on user machines. Document it.
- **Toolchain [V].**
  - Xcode 27 runs only on Apple silicon with macOS 26.6+, ships Swift 6.4, and supports macOS
    deployment targets 12–27, so 15.0 is fine.
  - ld64 is removed.
  - GitHub now keys macOS images by Xcode major: the **`xcode-27`** label runs macOS 27 with
    Xcode 27.0 as default. There is no `macos-27` label, and `macos-26` carries Xcode 26.0.1–26.6
    with no 27.
- **Dependencies [V].**
  - Sparkle is at **2.10.0**: macOS 12 minimum, a macOS 27 delta-compression fix, and it inherits
    the installer hardening from 2.9.2 and 2.9.6. We are on 2.9.0.
  - Firebase is at **12.19.2**. It requires Xcode 26.2+, fixes a name clash with Xcode 27's
    FoundationModels, and has an open issue where `upload-symbols` ignores `xcode-select`
    (#16616). We are on 11.15.
- **Intel [V].** macOS 27 is Apple-silicon-only, and Rosetta for apps ends with 28. **Our shipped
  binary is arm64-only**, a pre-existing state noted here only because it affects Intel users
  still on 15 or 26.

## Proposal

### Phase A — Hands-on checks on 27 (k97, ~30 min, no code)

Run these on the dev build. The Debug product is rebuilt and signed as of this review.

1. **Running in Background.** With Ghost-mode tiles pinned and their helpers running:
   - ⌘Q the main app and look at the Dock. Is there a gray dot on the main app or on any tile?
     Was there a notification? Is Dock Tile listed under *Background App Activity*?
   - Then log out and back in (the login-spawn path) and look again.
   - If flagged, the options are (a) quit helpers when the main app quits (bad: tiles must stay
     live) or (b) launch helpers through the SMAppService agent only, as Keyboard Maestro
     did. Pick after seeing the actual behaviour.
2. **Add-app picker (B2 pre-check).** Tile Detail → + must still allow choosing **both** an
   `.app` and a folder. Today's dev build is the SDK-27 build, so it shows the new behaviour
   now.
3. **Popover on 27.** Test 3 Dock edges (bottom, left, right) × magnification off/on, with one
   grid tile and one list tile.
   - **Pass:** in every case the popover opens fully on-screen, clear of the icon, with no panel
     content cut off.
   - Record a failure with the `Popover anchor … edge=` line from the dev diagnostics log.
4. **Switch size.** Read the AX frames per architecture.md. Tile Detail and Popover switches
   should still be 36×16, and General / Dock Lock form toggles unchanged.
5. **Icons.** Look at the tiles beside Apple's icons in Default, Dark, Clear and Tinted. Note
   only whether ours now look dated next to the sharper system icons; that feeds a future
   feature decision, not a fix.
6. **Transparency slider.** Set the slider to each end.
   - **Pass:** the real popover's app labels stay readable, and the Popover-settings preview
     stays close to the real popover.
   - This is a judgement call; a failure only becomes a polish ticket, never a blocker.
7. **Glass leak on 27 — DONE** (parallel session, commit `5a6a511`).
   - The repro in `fresh` mode no longer leaks on 27.0: 22 → 24 MB over 8 opens, with no
     glass/IOSurface class growth.
   - The IOSurface region climb **plateaus at 28**, with bytes constant, so it is not a leak.
   - Prod helpers sit at 33–34 MB after 3.5 days.
   - Trap for future re-tests: `NSGlassView` no longer exists on 27, so compare all matching
     heap classes at 1 vs 8 opens.

**Verification for every code phase (B, C, D):**
- Run the test command in CLAUDE.md `## Verification`.
- Then rebuild Debug **without** `CODE_SIGNING_ALLOWED=NO`, and confirm `codesign --verify` on
  `Dock Tile Dev.app` passes before launching it.
- A phase is not done until both are green.

### Phase B — Code hygiene (one small PR)

1. **`quinaryLabel` → `quinaryLabelColor`** at three sites:
   `CustomiseTileView.swift:162`, `CustomiseTileView.swift:170` and `DockTileDetailView.swift:443`.
   **Land it in the same PR as Phase C**: this Mac has no Xcode 26, so whether Xcode 26.2 (today's
   CI) knows the new Swift name is unverified. Landing it alone could break the release build.
   → **verify:** the Xcode 27 Debug build log has 0 `quinaryLabel` warnings, and CI on
   `xcode-27` is green.
2. **NSOpenPanel** (`DockTileDetailView.swift:721-723`). Set `allowedContentTypes` **before**
   `canChooseFiles` / `canChooseDirectories`, so the explicit flags win under SDK-27 semantics.
   Only needed if A2 shows a problem; otherwise leave it.
3. **Pre-existing warnings**, so the next new one stands out:
   - `HelperAppDelegate.swift:401`: non-Sendable `NSWorkspace` captured.
   - `HelperAppDelegate.swift:467-468`: dead `?? .distantPast` on a non-optional `Date`.
   - `DiagnosticsLog.swift:539` and `:578`: captured `self` in concurrent code.
   - `PopoverAppearanceView.swift:573`: main-actor `naturalInset` read from a `nonisolated` seam.
     This one becomes an error under Swift 7.
   - Two test warnings.

   → **verify:** `grep -c "warning:"` over own-code lines of a clean Xcode 27 build log returns 0.

### Phase C — Move CI and Release to Xcode 27 (the compatibility step)

1. **Switch runners.** Use `runs-on: xcode-27` in `ci.yml` and `release.yml`.
   - Select one explicit Xcode (27.0, or 27.1 once it is out of beta) and **fail loudly** if
     it's missing.
   - Delete the Xcode 16.x fallback chain: 16.x can no longer build this code, so falling back
     to it hides the real error.
   - **Assumption to check first**, against the `xcode-27` runner readme: the workflows rely on
     `xcpretty` (ci.yml:148, 192; release.yml:115), Homebrew (`create-dmg`, `xz`), rustup/cargo,
     and the `/Applications/Xcode_27.x.app` path. Add explicit installs for anything absent.
   - → **verify:** the CI log's `xcodebuild -version` step prints 27.x, and the run is green
     (build + tests).
2. **`DEVELOPER_DIR` for dSYM upload.** Export it before Crashlytics `upload-symbols` (Firebase
   #16616).
   - → **verify:** that step is `continue-on-error`, so a green run proves nothing. Read its log
     for the upload-success line on the first release.
3. **No Xcode-26 canary job.** It would conflict with B1 if the new colour name is SDK-27-only,
   and it would test an Xcode-26 build rather than the shipped binary on the 26 runtime anyway.
   - Risk accepted: an SDK-27-linked binary on macOS 26 keeps 26 behaviour, because
     linked-on-or-after switches only take effect on the OS that ships them.
   - The first 2.0.3 update on a 26 Mac, if one is available, is the spot check.
4. **Local release check before tagging.** Confirm on this Mac that the Release configuration
   built with Xcode 27 signs, notarises and passes `codesign --verify --deep --strict`, with the
   nested `docktile-actool` and Sparkle pieces signed individually (per ci-release.md's `--deep`
   warning).
   - → **verify:** `Scripts/build-release.sh --sign --notarize` exits 0.
5. **Docs.** Update `.claude/rules/ci-release.md:10` ("`macos-26` beta runners") and the
   runner/readme comments in `ci.yml` and `release.yml`. Add Xcode 27 as the build toolchain
   in CLAUDE.md's Commands section.

### Phase D — Dependencies (separate PRs, after C)

1. **Sparkle 2.9.0 → 2.10.0.** Security hardening plus a macOS 27 delta fix; the macOS 12
   minimum is below our 15.
   - Bump the SwiftPM pin **and** the hardcoded `SPARKLE_VERSION="2.9.0"` in
     `release.yml:371`, which fetches `sign_update`.
   - Also update the "Sparkle 2.9.0" text in ci-release.md.
   - Check the nested-signing steps still cover every Sparkle executable.
   - → **verify:** the release log prints `Downloading Sparkle 2.10.0 tools`, and the appcast
     EdDSA signature validates (OpenSSL check per ci-release.md).
   - → **also verify:** a 2.0.2 install on this Mac offered the new build updates through
     Sparkle and relaunches.
2. **Firebase 11.15 → 12.19.x.** Not urgent, since 11.15 builds and runs on 27, but 13.0 is
   next and the jump only grows. Do it on its own branch; the first CI run will miss the
   package cache.
   - → **verify:** CI is green; the next release's dSYM upload log shows success; the release
     app launches and `AnalyticsService.configure` logs no error.

### Phase E — Housekeeping backlog

- **Memwatch (issue #16).** k97 decided to **keep it until ~2026-11-29**; see the
  "Temporary" section of performance-measurement.md.
  - Do not uninstall or `git rm` it as part of this plan.
  - `DevToolingExclusionTests` fails if `project.pbxproj` ever references it. Keep that in mind
    if Phase C touches build phases.
- **The Release bundle ships the dev launcher plist too**
  (`com.docktile.dev.app.tilelauncher.plist`). It is harmless, since it is never registered,
  but exclude it per configuration.
- *(Optional, not a macOS 27 item.)* **Test targets use `SWIFT_VERSION = 5.0`**, so tests are
  not concurrency-checked. Moving them to 6 may surface test-only fixes.
- **Delete** the stale worktree `.claude/worktrees/main-window-makeover` and its DerivedData,
  the `perf/2026-09-fixes` branch, and `.superpowers/sdd/2026-09-19-performance-fixes/`.
- **Record** "validated on macOS 27.0 (26A428)" in the rules once Phase A is done.
- **MDM note** for the website FAQ or support replies: ad-hoc helpers are blocked on supervised
  Macs with App Settings lists.

### Not proposed now

- **Adopting Icon Composer 2 features** (refractivity etc.) in generated tiles. That is a
  feature: it needs the vendored compiler to understand the new keys, and it would break
  Xcode-26 builds. Revisit after Phase C, and only if A5 says the tiles look dated. Also:
  **don't re-save `AppIcon.icon` in Icon Composer 2 before Phase C** — Xcode 26's actool
  crashes on the new format.
- **Removing or `#available`-gating the glass-leak workaround.** k97 decided to keep it:
  the deployment target is 15, macOS 26 still leaks, and it costs nothing on 27.

## Who runs Dock Tile: the data (added 2026-09-29)

Source: GA4 property 542196919 (app stream only), read with the `ga4-fetch` service account.

| Signal | Value |
|---|---|
| Active users since 2026-06-18 | 188 |
| macOS version, **September** | 26.x ≈ 81 · **27.x ≈ 43** · **15.x = 3 (~2.5 %)**. A user who upgraded mid-month is counted under both |
| macOS 15 users since June | 11 (15.1 → 15.7.9) |
| Mac models since June | **100 % Apple silicon**: M1 (MacBookPro17/18, MacBookAir10,1, Macmini9,1, iMac21,1) through Mac17,x, plus Apple-silicon VMs. **Zero Intel identifiers** |
| App versions | 1.8.5 (92) · 2.0.1 (47) · 1.8.8 (25) · 2.0.2 (18) · a long tail |

**The Intel number is circular.** The shipped binary is arm64-only, so an Intel Mac can
download it but never launch it, and never reports to analytics. Analytics cannot measure
Intel demand. The pre-launch signals don't separate it either:
- GitHub DMG downloads (~374 total) include Sparkle updates, because the appcast points at the
  same GitHub assets.
- No GitHub issue mentions Intel, x86 or "can't open".
- The website's GA4 property (`G-PP04F8Z0EP`, with a `download_click` event) is **not visible
  to the service account**. Even if it were, browsers freeze the reported macOS at 10.15.7 and
  never report the CPU.

**What customers were told (as of 2026-09-29).** The website said "Requires macOS 26 or
later" while the binary and the appcast said 15. **Fixed in 2.0.3** (`f3a6153`, `6e1dc9b`): the
site now says "Requires macOS 15 or later", and `MacOSFloorGuardTests` keeps the deployment
target, appcast, macOS 15 CI leg and website in agreement.

**Still open:** the site never mentions **Apple silicon**. An Intel Mac on macOS 15 or 26 meets
the stated requirement, downloads, and gets macOS's generic "not supported on this Mac". That
failure is invisible to us. See D2.

## Decisions (k97, 2026-10-13)

### D1. Keep macOS 15 — DECIDED, with a measured review

**Decision:** keep the macOS 15 floor, likely until macOS 28 ships, and revisit when the cost
of carrying it rises. This is already the shipped state as of 2.0.3: deployment target 15.0,
appcast `minimumSystemVersion 15.0`, website "macOS 15 or later", and a macOS 15 CI leg.

#### Floor review: the cost of carrying macOS 15 (measured 2026-10-13)

| Cost | Now | How to re-measure |
|---|---|---|
| **Users on 15**, share of monthly active | Aug 6.3 % (6) → Sep 3.0 % (4) → Oct 1.3 % (1, partial month) | `python3 Scripts/analytics/macos-share.py` |
| **CI time**, macOS 15 leg | 42 s per run (`test-without-building`); the Dock render check runs only on demand | `gh run view <id> --json jobs` |
| **Code forks** on macOS 26 | 18 sites in 7 app files, plus the frozen legacy icon subsystem (`IconStyleManager` detection, 4-variant bake, `switchIcon`, byte-compare self-heal) | `grep -rnE '#available\(macOS 26\|isDeclarative' DockTile` |
| **Features degraded on 15** | 1: popover item menu's *Get Info* is macOS 26+ only | Feature plans that say "26+ only" |
| **15-only bugs** | 1 since September: the oversized tile, which cost the whole 2.0.3 cycle (~10 commits: fix, CI leg, render check, floor guard, website) | GitHub issues and feedback tagged macOS 15 |

**Verdict today: low.** The big cost was one-time and is paid; the CI leg and floor guard now
exist. The recurring cost is 42 s of CI, one degraded menu item, and keeping the legacy path
frozen.

**Revisit triggers.** Raise the floor to 26 when **any** of these happens:
1. **macOS 28 ships** (expected Sept 2027). 15 becomes N−3, beyond Apple's "one or two older"
   guidance.
2. **macOS 15 share stays below 2 % for two full consecutive months** in `macos-share.py`.
   October will likely be the first such month.
3. **A planned feature needs a macOS 26+ API with no reasonable fallback**, or a second feature
   ends up degraded on 15.
4. **A second macOS-15-only bug** reaches a user within a quarter.
5. **GitHub deprecates the `macos-15` runner image**, so the floor could no longer be tested.

**When a trigger fires, the floor raise is one edit plus the guard's list:**
- Set `MACOSX_DEPLOYMENT_TARGET = 26.0`. `MacOSFloorGuardTests` then names the appcast,
  website and CI-leg edits.
- Delete the legacy icon path; its rules name this as the deletion trigger.
- Leave the last 15-compatible appcast item at `minimumSystemVersion 15.0`. Sparkle keeps
  macOS 15 users on it and tells them on a manual check that their system is too old.
- Add a "last version for macOS 15" FAQ row.

### D2. Apple silicon only — DECIDED; disclosure and measurement pending

**Decision (confirmed): stay arm64-only.** The reasons:
- Intel Macs stop at macOS 26, and Apple ends Rosetta after 27. Apple's own 2026-09-09 guidance
  says to set the architecture to arm64 only.
- Universal would also need a universal `docktile-actool`: two cargo targets plus `lipo`, and
  Rust demoted `x86_64-apple-darwin` to Tier 2.
- It would also need a `macos-26-intel` CI job, and there is no Intel hardware here to verify
  it on.

The gap is disclosure, not code. This is website work, so it belongs in a separate session per
CLAUDE.md:
1. **Say it everywhere a requirement appears:** "Requires a Mac with Apple silicon and macOS
   15 or later". Update the hero, download caption, FAQ (3 locales), and schema.org
   (`processorRequirements`). **`MacOSFloorGuardTests` parses these requirement strings**, so
   rerun it after the edit; extend its pattern if the new wording no longer matches.
2. **Detect and explain where possible.** On Chromium browsers,
   `navigator.userAgentData.getHighEntropyValues(['architecture'])` reliably returns `x86` or
   `arm`. For `x86`, show a friendly "Dock Tile needs a Mac with Apple silicon" note beside the
   download. Safari and Firefox can't be detected: Safari's WebGL string is a generic "Apple
   GPU" and its UA is frozen. They rely on the text from step 1.
3. **Measure the audience you can't see today.** Add a coarse `cpu_arch` parameter
   (`arm` / `x86` / `unknown`) to the existing `download_click` event and register it as a
   custom dimension. Grant `ga4-fetch` Viewer on the website property so it can be read. This
   is one coarse bucket, not fingerprinting; mention it in the privacy policy.
4. Optional: `<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>` (Sparkle 2.9+).
   It changes nothing for users today, since no Intel client can run the app, so it is not
   worth doing on its own.

### D3. Order

2.0.3 shipped as a macOS 15 fix release; CI and Release still build with Xcode 26.2. Remaining
order: A → B+C together (the next release: the Xcode 27 build, still macOS 15+) → D → E. The
floor raise waits for a D1 trigger. Keeping the toolchain move and any floor raise in separate
releases means a regression can be traced to one change.

## Backward compatibility: the architecture to keep (industry standard)

1. **Build with the newest SDK; deploy to the oldest supported OS.** Gate every newer API with
   `if #available(macOS 27, *)` and always provide a fallback.
   - Apple weak-links symbols newer than the deployment target, so the check is what makes a
     back-deployed binary safe.
   - Don't hold the SDK back to avoid new behaviour.
2. **Treat an SDK bump as a behaviour change in its own release.** Frameworks keep old
   behaviour for apps linked against an old SDK ("linked-on-or-after", TN2456) and switch the
   moment you relink.
   - Examples from 27: menu images, NSOpenPanel flags, and `UIDesignRequiresCompatibility` being
     ignored (not used here).
   - That is why Phase C ships alone as 2.0.3, after the Phase A hands-on checks.
3. **One seam per OS-divergent capability, chosen at one composition point.** Dock Tile already
   does this: `IconPipeline.isDeclarative`.
   - The rule for new 27-only features: a protocol, or a struct-of-closures client, with an
     `@available(macOS 27, *)` implementation.
   - Selected once, not `#available` scattered through managers. View-level modifier gates like
     `ToolbarSpacer` are fine where they are.
   - Stored properties can't be availability-gated, which is another reason to keep the switch
     in one place.
   - Put the decision in a pure, unit-tested function, per this repo's regression-guard
     convention.
4. **Quarantine the legacy path, with a named deletion trigger.** The macOS 15 icon path already
   follows this ("frozen, delete when the floor rises past 26"). D1's review triggers decide
   when.
5. **Test what you claim, on the floor and on the latest OS.** The floor (15) is covered since
   2.0.3: CI builds once on `macos-26` (`build-for-testing`) and runs the same products on
   `macos-15` (`test-without-building`). This repo has proven that pattern.
   - Phase C moves the build job to `xcode-27`, which runs macOS 27, so the latest OS gets
     covered too.
   - **Unverified:** whether the `macos-15` and `macos-26` images, which carry no Xcode 27, can
     run an Xcode-27-built test bundle. Spike it in Phase C before dropping the Xcode-26 build.
     If they can't, keep one Xcode-26 build feeding the macOS 15 leg until the floor rises.
6. **Publish the support policy, and enforce it through Sparkle.** For example: "Dock Tile
   supports the current and previous macOS on Apple silicon. When support ends, the last
   compatible version stays downloadable."
   - Enforce it with a per-item `sparkle:minimumSystemVersion` (already emitted by
     `generate-appcast-entry.sh`), and never delete old appcast items.

## Open items

1. **D2 disclosure — done 2026-10-19** on branch `website/apple-silicon-requirement`. The hero
   eyebrow, both meta rows, the FAQ (3 locales, so FAQPage JSON-LD too) and schema.org
   `processorRequirements` now say Apple silicon.
   - **Measurement dropped (k97, 2026-10-19).** With arm64-only decided, the size of the
     Intel audience would change nothing, so neither the `cpu_arch` parameter nor `ga4-fetch`
     access to the website property is needed.
   - Revisit only if Intel support is ever reconsidered, or to compare download clicks against
     app first opens.
2. **Phases A–C** as above. Phase C's test-bundle spike is in architecture point 5.

## Sources

- macOS 27 release notes: https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes
- Xcode 27 release notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes · support matrix https://developer.apple.com/support/xcode/
- Running in Background: https://support.apple.com/en-us/125671 · https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac · KM field report https://forum.keyboardmaestro.com/t/macos-27-app-stuck-in-dock-permanently-running-in-background/51842
- MDM ad-hoc blocking: https://support.apple.com/guide/deployment/dep001044b08/web
- Mac compatibility: https://support.apple.com/en-us/127255
- Liquid Glass slider: https://9to5mac.com/2026/09/22/macos-27-gives-you-more-control-over-liquid-glass/ · WWDC26 AppKit session https://developer.apple.com/videos/play/wwdc2026/289/
- Popover growth on 27: https://github.com/nateritter/status-glance/pull/1
- Provenance/ad-hoc report (not reproduced here): https://github.com/1jehuang/jcode/issues/1233
- Accessibility regressions in peers: https://github.com/ejbills/DockDoor/issues/1612 · https://github.com/o-oltyan/dock-locker/pull/3 · https://github.com/espanso/espanso/issues/2813
- Icon Composer 2 format and old-actool crash: https://github.com/silashsieh/TrailMate/pull/49 · https://github.com/Sunnshiine/workout-app/issues/425
- Runners: https://github.blog/changelog/2026-09-10-xcode-27-runner-image-now-runs-on-macos-27/ · https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md · https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
- Swift 6.4: https://www.swift.org/blog/swift-6.4-released/
- Sparkle 2.10.0: https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0
- Firebase release notes: https://firebase.google.com/support/release-notes/ios · upload-symbols issue https://github.com/firebase/firebase-ios-sdk/issues/16616
- Apple deployment-target guidance: https://developer.apple.com/documentation/xcode/running-code-on-a-specific-version · linked-on-or-after TN2456 https://developer.apple.com/library/archive/technotes/tn2456/_index.html · UIDesignRequiresCompatibility https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility
- Rosetta/Intel: https://support.apple.com/en-us/102527 · https://developer.apple.com/news/?id=w5ngl9k2 · https://developer.apple.com/news/?id=k1mtkt1k · Rust x86_64 Tier 2 https://blog.rust-lang.org/2025/08/19/demoting-x86-64-apple-darwin-to-tier-2-with-host-tools
- Sparkle publishing (min/max OS, incompatible-system alert): https://sparkle-project.org/documentation/publishing/ · hardwareRequirements in 2.9.0 https://github.com/sparkle-project/Sparkle/releases/tag/2.9.0
- Peer support policies: https://github.com/rxhanson/Rectangle · https://github.com/waydabber/BetterDisplay · https://github.com/MonitorControl/MonitorControl · https://github.com/jordanbaird/Ice · Tsai on dropping old OSes https://mjtsai.com/blog/2026/09/03/preparing-to-update-to-golden-gate/
- Browser architecture detection: https://developer.mozilla.org/en-US/docs/Web/API/NavigatorUAData/getHighEntropyValues · support https://caniuse.com/mdn-api_navigator_useragentdata
