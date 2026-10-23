#!/usr/bin/env bash
# Smoke test for the Allvei Konsern AI.
#
# Runs headless games in a throw-away profile (never the player's own profile):
#   1. A new game where Allvei Konsern must build at least three routes and
#      its vehicles must earn money. The game is saved every month.
#   2. The last save is loaded again, and the AI must pick its routes back up.
#
# Usage: extensions/allvei_konsern/test/smoke_test.sh [start_year] [years] [seed]
# Env:   OPENTTD_BIN  path to the openttd binary (default: build/openttd)
#        KEEP_WORK=1  keep the temporary profile for inspection
#        PERSONALITY  0 cautious, 1 balanced, 2 aggressive, 3 random (default 3)
#        RIVALS=1     also run Nordlys Air in the same game and check both
#        SEA=1        a map with much sea, so ship routes get built and checked
#        SHIPS_ONLY=1 with SEA=1: switch off road, rail and air to test ships alone
#
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
AI_DIR="$ROOT/extensions/allvei_konsern"
NORDLYS_DIR="$ROOT/extensions/nordlys_air"
BIN="${OPENTTD_BIN:-$ROOT/build/openttd}"
START_YEAR="${1:-1995}"
YEARS="${2:-6}"
SEED="${3:-20261023}"
TICKS_PER_YEAR=27010

# Every Modern Tycoon AI must carry the same personality rules and rail pathfinder.
if ! cmp -s "$AI_DIR/personality.nut" "$NORDLYS_DIR/personality.nut"; then
	echo "FAIL: personality.nut differs between allvei_konsern and nordlys_air" >&2
	exit 1
fi
if ! cmp -s "$AI_DIR/pathfinder.nut" "$ROOT/extensions/fjellbanen_gods/pathfinder.nut"; then
	echo "FAIL: pathfinder.nut differs between allvei_konsern and fjellbanen_gods" >&2
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/allvei.XXXXXX")"
cleanup() { [[ "${KEEP_WORK:-0}" == 1 ]] && echo "Kept work dir: $WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

PROFILE="$WORK/profile"
mkdir -p "$PROFILE/ai" "$PROFILE/scripts" "$PROFILE/save" "$WORK/home/Documents" "$WORK/xdg"
if [[ "$(uname)" == Darwin ]]; then
	ln -s "$PROFILE" "$WORK/home/Documents/OpenTTD"
else
	ln -s "$PROFILE" "$WORK/xdg/openttd"
fi
ln -s "$AI_DIR" "$PROFILE/ai/allvei_konsern"
COMPETITORS=1
AI_LINES="\"Allvei Konsern\" = personality=${PERSONALITY:-3}"
if [[ "${SHIPS_ONLY:-0}" == 1 ]]; then
	AI_LINES="$AI_LINES,use_road=0,use_rail=0,use_air=0"
fi
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
map_x = 8
map_y = 8
starting_year = $START_YEAR
generation_seed = $SEED
town_name = english

[difficulty]
max_no_competitors = $COMPETITORS
competitors_interval = 0
$( [[ "${SEA:-0}" == 1 ]] && echo "quantity_sea_lakes = 4" )

[ai_players]
$AI_LINES
EOF

printf 'schedule on-next-calendar-month monthly.scr\n' > "$PROFILE/scripts/game_start.scr"
printf 'save allvei_smoke\nschedule on-next-calendar-month monthly.scr\n' > "$PROFILE/monthly.scr"

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
}

fail() { echo "FAIL: $1" >&2; grep "\[script" "$WORK/run1.log" | tail -60 >&2; exit 1; }

echo "== Run 1: new game, start $START_YEAR, $YEARS years, seed $SEED"
TICKS=$((TICKS_PER_YEAR * YEARS))
run_game "$WORK/run1.log" -g -G "$SEED" || fail "game exited with an error"
check_clean "$WORK/run1.log"
grep -q "Allvei Konsern er klar" "$WORK/run1.log" || fail "AI never started"
ROUTES=$(grep -c "Ny rute (" "$WORK/run1.log" || true)
[[ "$ROUTES" -ge 3 ]] || fail "fewer than 3 routes built ($ROUTES)"
MODES=$(grep -o "Ny rute ([a-z]*)" "$WORK/run1.log" | sort -u | wc -l | tr -d ' ')
grep -E "kjøretøyoverskudd [1-9]" "$WORK/run1.log" >/dev/null || fail "the vehicles did not earn money in any year"
if [[ "${RIVALS:-0}" == 1 ]]; then
	grep -q "Ny rute:" "$WORK/run1.log" || fail "Nordlys Air built no route in the shared game"
fi
if [[ "${SEA:-0}" == 1 ]]; then
	grep -q "Ny rute (skip)" "$WORK/run1.log" || fail "no ship route on a sea map"
fi
SAVE="$PROFILE/save/allvei_smoke.sav"
[[ -f "$SAVE" ]] || fail "no save game written"

echo "== Run 2: load the save and play one more year"
TICKS=$TICKS_PER_YEAR
run_game "$WORK/run2.log" -g "$SAVE" || fail "loaded game exited with an error"
check_clean "$WORK/run2.log"
grep -E "Ruter i drift: [1-9]" "$WORK/run2.log" >/dev/null || fail "routes were lost after load"

echo "== Log (both runs)"
grep -h -E "Ny rute|Årsrapport|legges ned|forulykket|finner ikke frem|gjeldfri|i drift|finansierer|leter etter|byttes til" \
	"$WORK/run1.log" "$WORK/run2.log" | sed -E 's/^.*\[script:[0-9]\] //' | head -150
echo "PASS: $ROUTES routes in $MODES transport modes, vehicles earn money, state survived save and load"
