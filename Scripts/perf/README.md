# Performance harness

Tools behind `docs/performance-baseline-2026-09.md`. Record with every number: machine, macOS,
build (Debug / optimised / Release helper), config size, power source, thermal state.

## Main-thread blocks for any flow
    xcrun xctrace record --template 'Time Profiler' --attach <pid> --time-limit 60s --output /tmp/x.trace
    # …perform the flow…
    Scripts/perf/analyze.sh /tmp/x.trace 40

## Popover open (helper)
    open -b <helper bundle id>        # toggles: a second call closes it
First open after ≥10 min idle is the number that matters; opens seconds apart are ~5–10× faster.

## Memory abandoned per open
    footprint <helper pid> | grep -E "Footprint:|IOSurface"   # before
    # five open/close cycles
    footprint <helper pid> | grep -E "Footprint:|IOSurface"   # after, and again 10 min later

## Launch
    swift Scripts/perf/launch_timer.swift "<App.app>"          # three runs, discard the first

## Pointer / key input (guarded)
    swift Scripts/perf/safe_input.swift hover <pid> 6
    swift Scripts/perf/safe_input.swift drag  <pid> x1 y1 x2 y2 4

## Release-grade main-app numbers without touching production data
Build the Debug configuration optimised into its own folder:
    xcodebuild -project DockTile.xcodeproj -scheme DockTile -configuration Debug \
      -derivedDataPath /tmp/dd-opt SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule \
      ENABLE_TESTABILITY=NO ENABLE_DEBUG_DYLIB=NO build
Delete `/tmp/dd-opt` afterwards. NEVER load a raw copy of the production config in the dev app —
see `make_test_config.py` for why. To measure on release-sized data, with the dev app QUIT:
    python3 Scripts/perf/make_test_config.py /tmp/rel-test.json
    cp -p ~/Library/Preferences/com.docktile.dev.configs.json /tmp/dev-config.swap-backup.json
    md5 -q ~/Library/Preferences/com.docktile.dev.configs.json      # note it
    cp /tmp/rel-test.json ~/Library/Preferences/com.docktile.dev.configs.json
    # launch, confirm the log says "visible but never pinned — not hiding" for every tile, measure, quit
    cp -p /tmp/dev-config.swap-backup.json ~/Library/Preferences/com.docktile.dev.configs.json
    md5 -q ~/Library/Preferences/com.docktile.dev.configs.json      # must match the noted value

## Sidebar navigation (hangs, memory) — `nav-bench.sh` + `nav-hangsum.sh`
Dev app only. One run = 12 sidebar switches at 1 s under the Animation Hitches template:
    Scripts/perf/nav-bench.sh "<app>" <label> <inspectorShown true|false> tiles|symbols|settings
    Scripts/perf/nav-hangsum.sh <label>          # refuses a run that did not drive 12/12 switches
    Scripts/perf/nav-bench.sh "<app>" <label> true mem   # 200 switches, footprint at +10 s and +30 s
Output goes to `$NAV_BENCH_OUT` (default `$TMPDIR/nav-bench`). Protocol for an A/B: build each side
optimised as above into its own scratch DerivedData (an old tag from a `git worktree`, copying
`Vendor/actool/target/release/docktile-actool` into it first), run the builds interleaved, three
runs each, decide on the mean; rerun a run with a lone >1 s hang. Rows are by index (2, 3, 4 =
the first three tiles): check the `rows:` line each run prints — test runs add and remove dev tiles.
Delete the scratch worktrees and DerivedData afterwards.

## Production safety
`prod_fingerprint.sh` prints the production config's checksum, each production helper bundle's
mtime and signature state, the production tiles' Dock entries, and the running production helper
pids. Run it at the start and end of every task; identical output is the proof that development
did not touch live tiles. It changing means something regenerated, re-sealed or re-seated a real
tile — stop and investigate before continuing.

## Rules
Never send raw keystrokes (the harness has no keyboard mode on purpose). Drive the app with Accessibility `set value` (focus the field through
Accessibility first or SwiftUI ignores it), `click`, `set selected`, single-`to` form only.
