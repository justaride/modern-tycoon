#!/usr/bin/env bash
# Runs the Fjellbanen Gods smoke test over several seeds, start years and map
# sizes in parallel, and prints one summary line per game.
# Every game plays YEARS (default 10) years, saves, reloads and plays two more.
#
# Usage: extensions/fjellbanen_gods/test/matrix.sh
# Env:   OPENTTD_BIN, YEARS, JOBS (parallel games, default 6)
#
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
YEARS="${YEARS:-10}"
JOBS="${JOBS:-6}"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/fjellbanen-matrix.XXXXXX")"

# name | env | start year | seed
CASES=(
	"256-1950-a|PERSONALITY=1|1950|11"
	"256-1950-b|PERSONALITY=2|1950|22"
	"256-1950-c|PERSONALITY=0|1950|33"
	"256-1995-a|PERSONALITY=1|1995|11"
	"256-1995-b|PERSONALITY=2|1995|22"
	"256-1995-c|PERSONALITY=0|1995|33"
	"256-1995-stress|PERSONALITY=1 START_TRAINS=5|1995|44"
	"512-1995|PERSONALITY=1 MAP_BITS=9|1995|55"
	"256-1995-rivals|PERSONALITY=1 RIVALS=1|1995|66"
	"256-1995-mountain|PERSONALITY=1 TERRAIN=3|1995|77"
	"256-1995-alpine|PERSONALITY=2 TERRAIN=4|1995|78"
)

run_case() {
	local spec="$1" name env year seed
	IFS='|' read -r name env year seed <<<"$spec"
	env $env LOG_LINES=0 "$DIR/smoke_test.sh" "$year" "$YEARS" "$seed" > "$OUT/$name.log" 2>&1
	echo $? > "$OUT/$name.rc"
}

running=0
for spec in "${CASES[@]}"; do
	run_case "$spec" &
	running=$((running + 1))
	if [[ "$running" -ge "$JOBS" ]]; then wait; running=0; fi   # Batches: works with bash 3.2 too.
done
wait

failed=0
printf '%-18s %-6s %s\n' "game" "result" "summary"
for spec in "${CASES[@]}"; do
	name="${spec%%|*}"
	rc="$(cat "$OUT/$name.rc")"
	summary="$(grep SUMMARY "$OUT/$name.log" | sed 's/SUMMARY //')"
	if [[ "$rc" == 0 ]]; then
		printf '%-18s %-6s %s\n' "$name" "PASS" "$summary"
	else
		failed=1
		printf '%-18s %-6s %s\n' "$name" "FAIL" "$(grep FAIL "$OUT/$name.log" | head -1)"
	fi
done
echo "Logs: $OUT"
exit "$failed"
