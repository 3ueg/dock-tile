# Performance Measurement

Paid for in the September 2026 perf cycle, where three baseline numbers failed to reproduce.

- **Trust only same-session A/B.** Old code and new code, same tile, same Mac, minutes apart. A
  number from another day is context, never a baseline: 465 ms, 2250 ms and 114 ms all failed to
  reproduce, and one false "regression" was committed on the strength of "same tool".
- **Record the build kind with every number.** Debug vs optimised differs several-fold. Optimised
  recipe and harness: `Scripts/perf/README.md`.
- **Measure helper code without a Dock restart**: swap the optimised executable into a dev tile's
  bundle, `codesign --force --sign -`, relaunch the helper. Back up first, and re-back-up after any
  Update or the restore silently reverts it. Confirm which code runs with `nm | grep <new symbol>`;
  re-sealing changes the md5.
- **Leak check = `footprint` across TEN opens**, not five: opens 1–5 carry one-time costs, 6–10 must
  be flat. Find the retained objects with `leaks --outputGraph` + `heap --diffFrom` before theorising.
- **Not ours:** ~220 MB transient the first time a process shows a popover (glass bring-up, still
  present on macOS 27). A never-clicked helper peaks at 12 MB. See `docs/macos-26-popover-glass-leak.md`.
- **Not a leak either: the IOSurface *region* count.** It climbs over the first opens, then plateaus
  (exactly 28 on a 6-app and a 102-app tile, macOS 27) with constant bytes. Judge by bytes and
  footprint across opens, never by region count.
- **Re-test system bugs class-agnostically on a new macOS.** Class names change between releases: a
  `grep NSGlassView` returns zero on macOS 27 whatever the truth, because the class is gone. Compare
  the counts of EVERY `Glass|Popover|IOSurface|CABackingStore|NSVisualEffect` heap class at 1 vs 8
  opens; a leak is any class that grows.

## Temporary: dev-tile memory watcher (installed 2026-09-21, KEEP until ~2026-11-29)

`Scripts/perf/memwatch.py` samples every running **dev** helper's footprint, IOSurface use and
popover-open count every 10 minutes via a per-user LaunchAgent (`com.docktile.dev.memwatch`), into
`~/Library/Application Support/DockTile-Dev/memwatch.csv`. It exists to prove the 2.0.2 popover-reuse
fix holds over days of real use, which a ten-open test cannot.

**Karthik decided on 2026-09-29 to keep it collecting on his dev Mac for about two more months.**
Do not uninstall it or `git rm` it before then, including as macOS 27 housekeeping. Review it around
2026-11-29, then remove it (issue #16).

**It cannot ship, and must stay that way.** It is a repo script plus a per-user LaunchAgent on one
Mac; nothing in the app target references it, so it is never compiled or bundled (verified against
the shipped 2.0.2 app). `DevToolingExclusionTests` fails if `project.pbxproj` ever references it.
It reads only `DockTile-Dev/` paths and dev helper processes, never production data.

    python3 Scripts/perf/memwatch.py report      # read it
    python3 Scripts/perf/memwatch.py uninstall    # stop; --purge also deletes the CSV

Read its `MB/100 opens` column with care: it counts one-time warm-up as growth, so with few opens it
overstates. The 2026-09-29 review showed "+33.3" for a tile that went 37 → 38 MB across ten opens
after warm-up. Reviewed that day: no defect, fix holds; data is all on macOS 27 (installed 09-22).

Deliberately OUTSIDE the app: no product code to strip from a release, and the tiles are not
perturbed by their own instrumentation. Dev-only — popover-open lines are verbose, so they do not
exist in Release logs. Pass at review: `MB/100 opens` near zero after warm-up. Leaving it installed
indefinitely past the review date is the failure mode this note guards against.

Reading two months of data: dev tiles are rebuilt whenever the dev app changes, so rows span
different code. Match row start times against `git log` before comparing one row with another.
The report groups rows by tile and process ID, and helpers get low IDs at login, so over many
reboots a reused ID can merge two processes into one row: an `uptime` that drops mid-row is the
tell. The open count parses the helpers' "✔ Show popover" log line, so renaming it reads as zero
opens, not as an error.

## Main-window navigation (Customise inspector round, October 2026)

How the sidebar-switch cost was measured, and what the numbers mean. Harness: an optimised build
(`SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule ENABLE_TESTABILITY=NO
ENABLE_DEBUG_DYLIB=NO`, into a scratch DerivedData so the Debug product stays signed), launched with
`open -g … --args -ApplePersistenceIgnoreState YES`, 12 sidebar rows selected through AX at 1 s
intervals, under `xcrun xctrace record --template 'Animation Hitches' --attach <pid>`; the verdict is
the `potential-hangs` table (`xctrace export --xpath …table[@schema="potential-hangs"]`), summed.
Attribution comes from `sample` on the DEBUG build (the optimised one has no app symbols), each
leaf's samples billed to the most specific frame on its path.

- **Noise band first.** Three baseline runs of the same sequence gave 13, 15 and 16 hangs
  (3.42–3.57 s). A difference under ±2 hangs or ±150 ms is nothing. One run had a single 1.9 s hang
  and an otherwise normal shape: the machine, not the code — repeat it.
- **The `hitches` table depends on the window being ON SCREEN.** `open -g` leaves the dev window
  behind the owner's, where CA renders nothing, so every clean run reports "hitches: none"; two runs
  reported 13 and 62 hitches with identical hang totals because the window happened to be visible
  (trains of 8 ms hitches at 120 Hz). Judge by hangs; read hitches only against a run from the same
  minutes.
- **A per-switch cost is the DETAIL column's unless open-vs-closed says otherwise.** Tile switch,
  inspector open vs closed: 674 vs 671 ms busy (Debug). The inspector's own content is not in the
  profile at all; the ~300 ms (optimised) per switch is the detail remade by `.id(selectedConfig.id)`:
  SwiftUI graph update ~190, `NSHostingView` layout ~95, the toolbar torn down and re-tiled 50–130,
  the preview LazyVGrid ~60 (Debug ms). Dropping that `.id` (with an explicit state reset) is the
  only lever left and is a change to Tile Detail, not the inspector — a follow-up, not done.
- **Kept: one change.** `.transaction(value: selection)` disabling animations on the split view:
  Settings sequence, inspector open, 39 hangs / 4.05 s → 12 / 2.95 s; closed 13 / 1.86 s → 15 / 1.75 s
  (noise); tiles unchanged. Plus `LoginItemManager.readStatus()` off the main thread (login XPC
  7–14 → 1 ms per switch).
- **Built, measured, removed (do not rebuild them without a new number):**
  - a skeleton placeholder with a 32 ms settle before the inspector content — tiles 13–15 → 19–20
    hangs; the deferral had nothing to hide and only added a layout pass;
  - stable `ToolbarItem(id:)` on every item — toolbar cost unchanged, because the detail's whole
    `.toolbar {}` is destroyed with the view, ids or not;
  - a 1 s `AppInstallChecker` probe cache for the editor/preview — install probe 15 ms/switch
    without it, 27–30 with it (the per-switch cost is the first probe per item, which a short TTL
    never spans).
- **Memory**: 200 switches with the inspector open, 125 → 127 MB, settled 118 MB. Flat.
