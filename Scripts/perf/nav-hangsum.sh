#!/bin/zsh
# Summarise a nav-bench.sh trace: nav-hangsum.sh <label>
# Prints "[label] hangs: N totalling X ms, worst Y ms". Exits 2 (and prints nothing else) when the
# run did not drive all 12 switches or has no trace — an invalid run must never read as "no hangs".
LABEL=$1
OUT=${NAV_BENCH_OUT:-${TMPDIR:-/tmp}/nav-bench}
LOG="$OUT/$LABEL.log"; T="$OUT/$LABEL.trace"
if ! grep -q "switches driven: 12/12" "$LOG" 2>/dev/null || [[ ! -d "$T" ]]; then
  echo "[$LABEL] INVALID — $(grep -h 'switches driven\|invalid' "$LOG" 2>/dev/null | tail -1)"
  exit 2
fi
X="$OUT/$LABEL-hangs.xml"
xcrun xctrace export --input "$T" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="potential-hangs"]' > "$X" 2>/dev/null
python3 -I - "$X" "$LABEL" <<'PY'
import sys
import xml.etree.ElementTree as ET
path, label = sys.argv[1], sys.argv[2]
root = ET.parse(path).getroot()
by_id = {el.attrib['id']: el for el in root.iter() if 'id' in el.attrib}
ms = []
for row in root.iter('row'):
    for el in row:
        if el.tag == 'duration':
            src = by_id.get(el.attrib.get('ref'), el)
            ms.append(int(src.text) / 1e6)
            break
if ms:
    print(f"[{label}] hangs: {len(ms)} totalling {sum(ms):.0f} ms, worst {max(ms):.0f} ms")
else:
    print(f"[{label}] hangs: 0 totalling 0 ms, worst 0 ms")
PY
