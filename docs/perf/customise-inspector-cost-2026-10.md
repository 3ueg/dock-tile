# Customise inspector — measured cost (October 2026)

Moved out of `.claude/rules/performance-measurement.md` (loaded every session) on 2026-10-22; the rule keeps the summary. Harness: `Scripts/perf/nav-bench.sh` (see `Scripts/perf/README.md`).

## Against the release (v2.4.0), 2026-10-22

Same Mac (M3 Max, macOS 27), same session, same dev data; v2.4.0 (= main's app code) and the branch
both built optimised the same way; two runs each, 12 switches per run, Animation Hitches hangs:

| | v2.4.0 | branch, inspector closed | branch, inspector open |
|---|---|---|---|
| Settings sequence, frozen | 1.63 / 1.66 s | 1.72 / 1.57 s | 2.47 / 2.43 s |
| Tile sequence, frozen | 1.93 / 1.94 s | 1.92 / 1.85 s | 3.44 / 3.14 s |
| Memory after 200 switches | 105 MB | 99 MB | 141–144 MB (peak ~340 MB for <10 s) |
| Idle CPU | 0.0% | 0.0% | 0.1% |
| App executable | 13.40 MB | 12.82 MB | (same) |

Closed = the release, within noise. Open costs ~70 ms per Settings switch, ~115 ms per tile switch,
~40 MB steady, and a short ~200 MB peak right after a burst of switches (released within 10 s, not
a leak — sampled at +2/+10/+30/+60 s). The production app (Release build, its own two-tile data) is
a reference only: 1.17 s Settings, 1.49–1.56 s tiles, 88 MB — different build type AND data.

Harness traps found that day: `open -g` on a quit app sometimes restores NO window, and a script
that finds no sidebar must fail, never record an empty trace as "no hangs" (four traces did); the
production app needs `tell application id … to reopen` to create one. `top -l N -pid` hung a run
for hours — read CPU time from `ps -o time=` twice instead. Match the main app with
`pgrep -f "^…/MacOS/Dock Tile( |$)"`: launch arguments follow the executable path.

## Best case for a stable inspector identity (2026-10-22, plan stopped here)

`Scripts/perf/nav-bench.sh` protocol: v2.4.0 (tag) vs HEAD vs a spike = HEAD with ONLY the
inspector's `.id(selectedConfig.id)` removed; optimised builds, interleaved, three runs, means.

| | v2.4.0 | HEAD | spike | bar |
|---|---|---|---|---|
| Tiles, inspector open | 1.99 s / 15.3 hangs | 3.38 s / 16.3 | 2.82 s / 13.7 | ≤ 2.14 s |
| Symbol↔Symbol, open | 2.26 s | 4.07 s (one 1.4 s outlier dropped) | 2.89 s | — |
| Tiles, inspector closed | — | 2.00 s | 2.06 s | no worse |
| Settings, open | — | 2.68 s | 2.63 s | no worse |
| Memory +30 s after 200 switches | 99 MB | 142 MB | 135 MB | ≤ 109 MB |

The rebuild is ~40% of the open inspector's tile-switch cost (~65% symbol↔symbol) and ~7 MB of its
memory; the rest is the inspector existing and updating for each tile. The best case misses the
v2.4.0 bar, so the stable-identity plan was stopped before any refactor (Karthik's rule).
**Correction:** the ~300 MB peak right after a burst of switches is NOT the inspector's — v2.4.0
peaks at 292–298 MB too; all builds settle within 10 s.
Harness trap: dev Dock helpers run copies of the dev app with the same executable name, so the app
must be matched by `Dock Tile Dev\.app/Contents/MacOS/…`, never by the executable alone — the
first race attached to a helper and every run was (correctly) rejected as NO SIDEBAR.

## Where the open inspector's cost goes (SwiftUI template, 2026-10-22)

`xctrace record --template SwiftUI` over the 12-switch `tiles` sequence, optimised HEAD, inspector
open vs closed; `swiftui-updates` table summed per description (exports run to ~6 GB of XML — stream
them, never load them). Summed SwiftUI update time: closed 1.51 s, open 2.59 s (+1.08 s, ~90 ms
per switch). Of the extra: view CREATION +0.52 s (the per-tile `.id` rebuild — the spike above
removes it) and updates +0.55 s. Largest named piece of the rest: the symbol/emoji picker grid
(`LazySubviewPlacements<LazyVGridLayout>` +127 ms, ~7,000 extra `Image Content` updates +86 ms,
`Text Content` +31 ms). The inspector's own bodies (`CustomiseTileView`, pickers, style cards)
cost under 10 ms combined; the rest is spread over many small controls (< 20 ms each) plus
~330 ms SwiftUI leaves unattributed. ~20% of the freeze delta sits outside SwiftUI (AppKit layout
and render), which this template does not split.
**Consequences:** `@Observable` would not help switching (every field changes between tiles; it
helps edits only). Removing the rebuild plus a cheaper picker grid is the one targeted fix, and
even together they are not expected to reach v2.4.0 — the remainder is the cost of a full
Customise panel updating per tile.
