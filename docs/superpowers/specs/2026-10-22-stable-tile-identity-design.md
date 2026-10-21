# Stable inspector identity — design

**Date:** 2026-10-22 · **Branch:** `feature/customise-inspector` · **Status:** STOPPED at Task 1 (2026-10-22): the best-case spike missed the bar — see
`performance-measurement.md` "Best case for a stable inspector identity". Revised after
three plan gates (Needs answers ×3 → Karthik's five answers below; the third gate's two technical items resolved by the author, not re-gated)

## Intent

Remove the Customise inspector's switching cost against v2.4.0 by keeping the inspector alive across
tile switches instead of rebuilding it per tile. Nothing a user can see or rely on may change.

## Why (measured)

Same Mac, same session, same dev data, optimised builds (`performance-measurement.md`, "Against the
release"). 12 switches per run, Animation Hitches hangs:

| | v2.4.0 | branch, inspector closed | branch, inspector open |
|---|---|---|---|
| Tile sequence, frozen | 1.93 / 1.94 s | 1.92 / 1.85 s | 3.44 / 3.14 s |
| Settings sequence, frozen | 1.63 / 1.66 s | 1.72 / 1.57 s | 2.47 / 2.43 s |
| Memory after 200 switches | 105 MB | 99 MB | 141–144 MB (~340 MB peak < 10 s) |

Closed matches the release; the regression is the open inspector. `inspectorColumn` in
`DockTileConfigurationView` is keyed `.id(selectedConfig.id)`, so each tile switch destroys and
rebuilds the whole inspector, its symbol/emoji grid included. Apple: "whenever the identity changes,
the state is replaced" and "a stable identifier also helps performance, since SwiftUI doesn't need
to continually create storage for the view and churn through updating the graph" (WWDC21
*Demystify SwiftUI*).

## Decisions

1. **Scope (Karthik, 2026-10-22): the inspector only.** Tile Detail keeps its `.id` and its save path
   untouched. Making Tile Detail cheaper is a separate, later plan (see "Follow-up" below).
2. **Pass bar (Karthik, 2026-10-22): back to v2.4.0, tile switching only.** With the inspector open,
   the tile sequence's frozen time (mean of three interleaved runs) must be ≤ v2.4.0's mean + 150 ms
   with a mean hang count ≤ v2.4.0's + 2, and memory after 200 switches ≤ v2.4.0's + 10 MB, all
   measured in one session against tag `v2.4.0` built the same way. Inspector closed, and the Settings
   sequence, must be no worse than the pre-change branch by the same margins. The Settings sequence
   with the inspector open stays ~0.8 s per 12 switches above v2.4.0 — a known, recorded cost of the
   inspector hiding and showing, out of scope here (Karthik's call).
3. **Best case first (replaces an attribution step the gate showed blind).** Build HEAD with only the
   inspector's `.id` removed and race it against v2.4.0 and HEAD before any refactor. If even that
   misses the bar, stop and report — nothing further is built (Karthik's call); the Tile Detail
   follow-up is the next decision. Debug `sample` busy time cannot see this gap
   (`performance-measurement.md`), so it is not used to decide.
4. **Per-tile inspector state lives on the tile's session, not in the view.** `searchText`,
   `customColor` and the two scroll positions move to a small observable owned by `TileEditSession`.
   The store already creates one session per tile, so a new tile brings fresh state in the same
   update — no reset after the fact, no ordering question, no delayed write into the next tile.
   **Reset on reopen (Karthik's call):** closing the inspector resets that state (done at close so the reopened view is built fresh in one pass), so closing and
   reopening on the same tile starts with an empty search and at the top, as today.
5. **The search field is re-keyed per session** (`.id(ObjectIdentifier(session.inspector))`): a
   focused field editor or an IME composition never crosses to the next tile. The colour strip is
   not re-keyed: the system colour panel holds the bindings it captured when opened, so later drags
   go to the old tile's session today and after this change alike.
6a. **Named visible change:** keyboard or VoiceOver focus on an inspector control now stays on that
   control across a tile switch (today the rebuilt inspector drops it). Accepted as a consequence
   of stable identity; checked by hand.
6. **A tile switch is never logged as an edit.** The inspector's per-field `onChange` logs become one
   handler over the whole config that logs only when the old and new config are the same tile.
7. **Unchanged on purpose:** the inspector starts each tile as a rebuilt one does today — search
   empty, custom colour `.blue`, inspector and picker scrolled to the top.
8. **If the full change misses the bar** after the best case passed, all of its tasks are reverted
   (no orphaned refactors) and the numbers reported.

## Constraints

Swift 6 strict concurrency; macOS 15 floor (`ScrollPosition` is macOS 15+); no new app-target files;
tests under `DockTileTests/` auto-join; Tile Detail's save path and `.id` untouched.

## Follow-up: Tile Detail (not this plan)

The first plan gate (2026-10-22) found these risks in removing Tile Detail's `.id`; a later plan must
answer them before any code:
- Delayed writes (`asyncAfter` for `hasAppearedOnce`, the main-queue hop that bumps `saveGeneration`,
  the `configurations` sync) land in the NEXT tile's `@State` once state outlives the tile.
- `performDockAction` reads `isCurrentlyInDock` and writes view state after `await`; an id guard is
  wrong after A→B→A (a fresh session for A) and can surface Remove from Dock right after an Add.
  Guard on session identity, and capture `wasInDock` before the `Task`.
- A reset in `onChange(of: session.id)` runs after one body pass with the old tile's state (button
  label/prominence, spinner) and costs a second layout pass; per-session state (as Decision 4 here)
  avoids it.
- A post-switch flush from the parent breaks "Tile Detail owns the only save path", can run before
  the replacement, and double-saves on the way to Settings; `deleteTile` must clear the flag.
- Per-field `onChange`s write non-verbose (production) log lines on a switch.
- The name field's editor and IME state, VoiceOver focus, and ⌘-click deselect (same id, new session).
