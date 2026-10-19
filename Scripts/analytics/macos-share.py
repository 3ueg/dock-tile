#!/usr/bin/env python3
"""Dock Tile active users by macOS major version, per calendar month. Read-only.

Feeds the macOS floor review (docs/macos-27-compatibility-2026-09.md, "Floor review").

    python3 Scripts/analytics/macos-share.py [START_DATE]    # default 2026-06-01

Auth: the `ga4-fetch` service account must be active in gcloud (`gcloud auth list`). Never pass
or open its key file here. Property 542196919 holds only the app stream; Firebase reports a Mac
app as platform "iOS", so this query does not filter on operating system.

Caveats: users are counted once per (month, exact version), so summing by major slightly
over-counts people who upgraded mid-month. The current month is partial. Intel Macs never appear:
the app is arm64-only, so they can't launch it to report.
"""
import json
import subprocess
import sys
import urllib.request
from collections import defaultdict

PROPERTY = "542196919"
SERVICE_ACCOUNT = "ga4-fetch@dock-tile.iam.gserviceaccount.com"
SCOPE = "https://www.googleapis.com/auth/analytics.readonly"
MAJORS = ("15", "26", "27", "28")


def access_token() -> str:
    return subprocess.run(
        ["gcloud", "auth", "print-access-token", f"--account={SERVICE_ACCOUNT}", f"--scopes={SCOPE}"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def fetch_rows(start: str) -> list:
    body = {
        "dateRanges": [{"startDate": start, "endDate": "today"}],
        "dimensions": [{"name": "yearMonth"}, {"name": "operatingSystemVersion"}],
        "metrics": [{"name": "activeUsers"}],
        "limit": 1000,
    }
    request = urllib.request.Request(
        f"https://analyticsdata.googleapis.com/v1beta/properties/{PROPERTY}:runReport",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {access_token()}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response).get("rows", [])


def users_by_month_and_major(rows: list) -> dict:
    table = defaultdict(lambda: defaultdict(int))
    for row in rows:
        month, version = (v["value"] for v in row["dimensionValues"])
        table[month][version.split(".")[0]] += int(row["metricValues"][0]["value"])
    return table


def main() -> None:
    start = sys.argv[1] if len(sys.argv) > 1 else "2026-06-01"
    table = users_by_month_and_major(fetch_rows(start))
    print(f"{'month':<8} {'users':>5}  " + "  ".join(f"{'macOS ' + m:>13}" for m in MAJORS))
    for month in sorted(table):
        counts = table[month]
        total = sum(counts.values())
        cells = (f"{counts.get(m, 0):>4} ({100 * counts.get(m, 0) / total:4.1f}%)" for m in MAJORS)
        print(f"{month:<8} {total:>5}  " + "  ".join(f"{c:>13}" for c in cells))


if __name__ == "__main__":
    main()
