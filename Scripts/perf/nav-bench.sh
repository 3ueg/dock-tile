#!/bin/zsh
# Main-window navigation benchmark for the DEV app (com.docktile.dev.app, dev data only).
#
#   nav-bench.sh <app path> <label> <inspectorShown true|false> <settings|tiles|symbols|mem>
#
# settings/tiles/symbols: an Animation Hitches trace over 12 sidebar switches at 1 s intervals,
#   saved as $NAV_BENCH_OUT/<label>.trace with a log $NAV_BENCH_OUT/<label>.log. Summarise it with
#   nav-hangsum.sh <label>, which refuses a run that did not drive all 12 switches.
# mem: 200 fast switches, footprint every 50, then +10 s and +30 s after the last switch, then idle
#   CPU over 10 s (two `ps` reads). Output in the log.
#
# Sequences (rows of the dev sidebar — check the printed names; test runs add and remove tiles):
#   tiles    = rows 2,3,4 ×4      symbols = rows 2,4 ×6      settings = 6,4,7,4,10,4 ×2
#   mem      = 2,3,4,6,7,8,10,4,2,7,3,6 repeated to 200+
#
# Never run against the production app; writes only com.docktile.dev.app's inspectorShown.
# Exit 2 = invalid run (no app, no window, no sidebar). An empty trace is NOT "no hangs".
APP=$1; LABEL=$2; FLAG=$3; MODE=$4
OUT=${NAV_BENCH_OUT:-${TMPDIR:-/tmp}/nav-bench}
mkdir -p "$OUT"
LOG="$OUT/$LABEL.log"
: > "$LOG"
say() { echo "[$LABEL] $*" | tee -a "$LOG"; }
quitapp() { osascript -e 'tell application id "com.docktile.dev.app" to quit' >/dev/null 2>&1; sleep 3; }

if [[ -z "$MODE" || ! -d "$APP" ]]; then say "usage or app missing — run invalid"; exit 2; fi
case $MODE in
  tiles)    ROWS=(2 3 4 2 3 4 2 3 4 2 3 4) ;;
  symbols)  ROWS=(2 4 2 4 2 4 2 4 2 4 2 4) ;;
  settings) ROWS=(6 4 7 4 10 4 6 4 7 4 10 4) ;;
  mem)      ROWS=(2 3 4 6 7 8 10 4 2 7 3 6) ;;
  *) say "unknown mode $MODE — run invalid"; exit 2 ;;
esac

quitapp
defaults write com.docktile.dev.app inspectorShown -bool "$FLAG"
open -g "$APP" --args -ApplePersistenceIgnoreState YES
sleep 8
PID=$(pgrep -f "Dock Tile Dev\.app/Contents/MacOS/Dock Tile Dev( |$)" | head -1)   # the .app path: dev Dock helpers share the executable name
[[ -z "$PID" ]] && { say "app did not launch — run invalid"; exit 2; }

# A background launch sometimes restores no window; a reopen creates it.
OPEN_PATH="outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of splitter group 1 of group 1 of window 1"
CLOSED_PATH="outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1"
P=""
for attempt in 1 2 3 4 5 6; do
  for cand in "$OPEN_PATH" "$CLOSED_PATH"; do
    osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to get count of rows of $cand" >/dev/null 2>&1 && { P=$cand; break 2; }
  done
  osascript -e 'tell application id "com.docktile.dev.app" to reopen' >/dev/null 2>&1
  sleep 3
done
[[ -z "$P" ]] && { say "NO SIDEBAR — run invalid"; quitapp; exit 2; }
NAMES=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to get value of static text 1 of UI element 1 of every row of $P" 2>/dev/null)
say "rows: $NAMES"

sel() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set selected of row $1 of $P to true" >/dev/null 2>&1; }
fp() { footprint "$PID" 2>/dev/null | grep -m1 phys_footprint | awk '{print $2}'; }
cpusecs() { ps -p "$PID" -o time= | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }

sel 4; sleep 2
if [[ $MODE == mem ]]; then
  say "launched footprint=$(fp) MB"
  n=0
  for loop in $(seq 1 17); do
    for r in $ROWS; do
      sel $r; sleep 0.25; n=$((n + 1))
      ps -p "$PID" >/dev/null || { say "DEAD at switch $n"; exit 1; }
      (( n % 50 == 0 )) && { sleep 2; say "switches=$n footprint=$(fp) MB"; }
    done
  done
  sel 4
  sleep 10; say "+10s footprint=$(fp) MB"
  sleep 20; say "+30s footprint=$(fp) MB"
  A=$(cpusecs); sleep 10; B=$(cpusecs)
  say "idle CPU over 10 s: $(echo "$A $B" | awk '{printf "%.1f%%", ($2-$1)*10}')"
else
  rm -rf "$OUT/$LABEL.trace"
  xcrun xctrace record --template 'Animation Hitches' --attach "$PID" --time-limit 22s \
    --output "$OUT/$LABEL.trace" >/dev/null 2>&1 &
  X=$!
  sleep 3
  ok=0
  for r in $ROWS; do sel $r && ok=$((ok + 1)); sleep 1.0; done
  wait $X
  say "switches driven: $ok/12"
fi
quitapp
