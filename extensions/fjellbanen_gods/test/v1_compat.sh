#!/usr/bin/env bash
# Save compatibility: a game saved with Fjellbanen Gods version 1 must load
# and keep running with the current version.
#
# 1. Exports version 1 of the AI from git (commit V1_COMMIT) into a temp dir.
# 2. Plays a new game with it and keeps the last monthly save.
# 3. Loads that save with the current AI and checks the old lines keep earning.
#
# Usage: extensions/fjellbanen_gods/test/v1_compat.sh [start_year] [years] [seed]
# Env:   OPENTTD_BIN, V1_COMMIT (default 9e6157bff, the version 1 commit)
#
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TEST="$ROOT/extensions/fjellbanen_gods/test/smoke_test.sh"
V1_COMMIT="${V1_COMMIT:-9e6157bff}"
START_YEAR="${1:-1995}"
YEARS="${2:-5}"
SEED="${3:-20261023}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fjellbanen-v1.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/fjellbanen_gods"
for f in info.nut main.nut pathfinder.nut personality.nut license.txt; do
	git -C "$ROOT" show "$V1_COMMIT:extensions/fjellbanen_gods/$f" > "$TMP/fjellbanen_gods/$f"
done
grep -q "GetVersion()     { return 1; }" "$TMP/fjellbanen_gods/info.nut" || { echo "FAIL: $V1_COMMIT is not version 1" >&2; exit 1; }

echo "== Making a save with version 1 ($V1_COMMIT)"
AI_DIR="$TMP/fjellbanen_gods" SAVE_OUT="$TMP/v1.sav" LOG_LINES=0 "$TEST" "$START_YEAR" "$YEARS" "$SEED" | grep -E "PASS|FAIL|SUMMARY"

echo "== Loading it with the current version"
V1_SAVE="$TMP/v1.sav" LOG_LINES=40 "$TEST" "$START_YEAR" "$YEARS" "$SEED" | grep -E "i drift|Årsrapport|enkeltspor|PASS|FAIL"
echo "PASS: version 1 save loads and keeps running with the current version"
