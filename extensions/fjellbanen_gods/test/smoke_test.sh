#!/usr/bin/env bash
# Smoke test for the Fjellbanen Gods rail AI.
#
# Runs headless games in a throw-away profile (never the player's own profile):
#   1. A new game where Fjellbanen Gods must build double-track lines whose
#      trains earn money, with no lost or stuck trains. Saved every month.
#   2. The last save is loaded again, and the AI must pick its lines back up.
#
# Usage: extensions/fjellbanen_gods/test/smoke_test.sh [start_year] [years] [seed]
# Env:   OPENTTD_BIN    path to the openttd binary (default: build/openttd)
#        KEEP_WORK=1    keep the temporary profile for inspection
#        PERSONALITY    0 cautious, 1 balanced, 2 aggressive, 3 random (default 3)
#        START_TRAINS   trains on each new line (default 2; use 4-6 to stress signals)
#        MAP_BITS       map side as a power of two (default 8 = 256x256, 9 = 512x512)
#        TERRAIN        0 very flat .. 4 alpinist (default 1, hilly)
#        RIVALS=1       also run Nordlys Air in the same game and check both
#        REQUIRE_JUMP=1 fail unless at least one bridge or tunnel was built
#        AI_DIR         AI to run (default: this checkout's fjellbanen_gods)
#        V1_SAVE=path   skip run 1 and load this save (made by version 1) instead
#        SAVE_OUT=path  copy the last save of run 1 here
#
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
AI_DIR="${AI_DIR:-$ROOT/extensions/fjellbanen_gods}"
NORDLYS_DIR="$ROOT/extensions/nordlys_air"
BIN="${OPENTTD_BIN:-$ROOT/build/openttd}"
START_YEAR="${1:-1995}"
YEARS="${2:-6}"
SEED="${3:-20261023}"
MAP_BITS="${MAP_BITS:-8}"
TICKS_PER_YEAR=27010

# Every Modern Tycoon AI must carry the same personality rules.
if ! cmp -s "$ROOT/extensions/fjellbanen_gods/personality.nut" "$NORDLYS_DIR/personality.nut"; then
	echo "FAIL: personality.nut differs between fjellbanen_gods and nordlys_air" >&2
	exit 1
fi

if [[ ! -x "$BIN" ]]; then
	echo "FAIL: no openttd binary at $BIN (build first, or set OPENTTD_BIN)" >&2
	exit 1
fi
if ! ls "$(dirname "$BIN")"/baseset/OpenGFX*.tar >/dev/null 2>&1; then
	echo "FAIL: OpenGFX not found in $(dirname "$BIN")/baseset" >&2
	exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fjellbanen.XXXXXX")"
cleanup() { [[ "${KEEP_WORK:-0}" == 1 ]] && echo "Kept work dir: $WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

PROFILE="$WORK/profile"
mkdir -p "$PROFILE/ai" "$PROFILE/scripts" "$PROFILE/save" "$WORK/home/Documents" "$WORK/xdg"
if [[ "$(uname)" == Darwin ]]; then
	ln -s "$PROFILE" "$WORK/home/Documents/OpenTTD"
else
	ln -s "$PROFILE" "$WORK/xdg/openttd"
fi
ln -s "$AI_DIR" "$PROFILE/ai/fjellbanen_gods"
COMPETITORS=1
AI_LINES="\"Fjellbanen Gods\" = personality=${PERSONALITY:-3},start_trains=${START_TRAINS:-2}"
if [[ "${RIVALS:-0}" == 1 ]]; then
	ln -s "$NORDLYS_DIR" "$PROFILE/ai/nordlys_air"
	COMPETITORS=2
	AI_LINES="$AI_LINES
\"Nordlys Air\" = personality=${PERSONALITY:-3}"
fi

cat > "$PROFILE/test.cfg" <<EOF
[misc]
language = english.lng

[gui]
autosave = off

[game_creation]
map_x = $MAP_BITS
map_y = $MAP_BITS
starting_year = $START_YEAR
town_name = english

[difficulty]
terrain_type = ${TERRAIN:-1}
max_no_competitors = $COMPETITORS
competitors_interval = 0

[ai_players]
$AI_LINES
EOF

printf 'schedule on-next-calendar-month monthly.scr\n' > "$PROFILE/scripts/game_start.scr"
printf 'save fjellbanen_smoke\nschedule on-next-calendar-month monthly.scr\n' > "$PROFILE/monthly.scr"

run_game() {
	local log="$1"; shift
	(cd "$WORK" && HOME="$WORK/home" XDG_DATA_HOME="$WORK/xdg" XDG_CONFIG_HOME="$WORK/xdg" \
		"$BIN" -x -c "$PROFILE/test.cfg" -v null:ticks="$TICKS" -s null -m null -d script=4 "$@") > "$log" 2>&1
}

check_clean() {
	local log="$1"
	if grep -E "\[S\]|script died|Your script made an error|Error compiling" "$log" >/dev/null; then
		echo "FAIL: script error in $log:" >&2
		grep -E -B2 -A12 "\[S\]|script died|Your script made an error|Error compiling" "$log" | head -60 >&2
		exit 1
	fi
	if grep -q "finner ikke frem" "$log"; then fail "a train got lost" "$log"; fi
	if grep -q "står fast" "$log"; then fail "a train stood still outside stations for a year (stuck)" "$log"; fi
	if grep -q "Sporfeil" "$log"; then fail "built track does not connect" "$log"; fi
}

fail() { echo "FAIL: $1" >&2; grep "\[script" "${2:-$WORK/run1.log}" | grep -v "same name\|taking precedence\|  [12]: " | tail -40 >&2; exit 1; }

SAVE="$PROFILE/save/fjellbanen_smoke.sav"
LINES=0
if [[ -n "${V1_SAVE:-}" ]]; then
	cp "$V1_SAVE" "$SAVE"
	echo "== Using version 1 save $V1_SAVE"
else
	echo "== Run 1: new game, start $START_YEAR, $YEARS years, seed $SEED, map 2^$MAP_BITS, start trains ${START_TRAINS:-2}"
	TICKS=$((TICKS_PER_YEAR * YEARS))
	run_game "$WORK/run1.log" -G "$SEED" -g || fail "game exited with an error"
	check_clean "$WORK/run1.log"
	grep -q "Fjellbanen Gods er klar" "$WORK/run1.log" || fail "AI never started"
	LINES=$(grep -c "Ny jernbane:" "$WORK/run1.log" || true)
	[[ "$LINES" -ge 1 ]] || fail "no rail line built"
	grep -E "togoverskudd [1-9]" "$WORK/run1.log" >/dev/null || fail "no train earned money"
	if grep -q "dobbeltspor" "$WORK/run1.log"; then
		grep -E "^.*\[I\]   .*: [A-Z]+, [2-9] tog, overskudd [1-9]" "$WORK/run1.log" >/dev/null || fail "no line runs two or more trains at a profit"
	fi
	if [[ "${REQUIRE_JUMP:-0}" == 1 ]]; then
		grep -E "Ny jernbane:.*([1-9][0-9]* bruer|[1-9][0-9]* tunneler)" "$WORK/run1.log" >/dev/null || fail "no bridge or tunnel was built"
	fi
	if [[ "${RIVALS:-0}" == 1 ]]; then
		grep -q "Ny rute:" "$WORK/run1.log" || fail "Nordlys Air built no route in the shared game"
	fi
	[[ -f "$SAVE" ]] || fail "no save game written"
	if [[ -n "${SAVE_OUT:-}" ]]; then cp "$SAVE" "$SAVE_OUT"; fi
fi

echo "== Run 2: load the save and play two more years"
TICKS=$((TICKS_PER_YEAR * 2))
run_game "$WORK/run2.log" -g "$SAVE" || fail "loaded game exited with an error" "$WORK/run2.log"
check_clean "$WORK/run2.log"
grep -E "Jernbaner i drift: [1-9]" "$WORK/run2.log" >/dev/null || fail "rail lines were lost after load" "$WORK/run2.log"
grep -E "togoverskudd [1-9]" "$WORK/run2.log" >/dev/null || fail "trains earned nothing after load" "$WORK/run2.log"

echo "== Log (both runs)"
LOGS=("$WORK/run2.log")
[[ -f "$WORK/run1.log" ]] && LOGS=("$WORK/run1.log" "$WORK/run2.log")
if [[ "${LOG_LINES:-80}" != 0 ]]; then
	grep -h -E "Ny jernbane|Ny rute|Årsrapport|  .*overskudd|legges ned|forulykket|finner ikke frem|står fast|gjeldfri|i drift|Personlighet|Tog nummer|Sporfeil" \
		"${LOGS[@]}" | sed -E 's/^.*\[script:[0-9]\] //' | head -"${LOG_LINES:-80}" || true
fi
count_sum() { { cat "${LOGS[@]}" | grep -oE "[0-9]+ $1" || true; } | awk '{s+=$1} END {print s+0}'; }
BRIDGES=$(count_sum bruer)
TUNNELS=$(count_sum tunneler)
MAXTRAINS=$({ cat "${LOGS[@]}" | grep -oE ": [A-Z]+, [0-9]+ tog" || true; } | grep -oE "[0-9]+ tog" | awk '{if ($1>m) m=$1} END {print m+0}' || true)
LASTPROFIT=$({ grep -h "Årsrapport.*jernbaner" "${LOGS[@]}" || true; } | tail -1 | sed -E 's/.*togoverskudd (-?[0-9]+).*/\1/')
echo "SUMMARY lines=$LINES bridges=$BRIDGES tunnels=$TUNNELS max_trains_per_line=$MAXTRAINS last_year_profit=$LASTPROFIT"
echo "PASS: rail lines run without lost or stuck trains, and state survived save and load"
