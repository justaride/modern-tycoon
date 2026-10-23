#!/usr/bin/env bash
# Smoke test for the Nordlys Air AI.
#
# Runs headless games in a throw-away profile (never the player's own profile):
#   1. A new game where Nordlys Air must build routes and survive several years.
#      The game is saved every month.
#   2. The last save is loaded again, and the AI must pick its routes back up.
#
# Usage: extensions/nordlys_air/test/smoke_test.sh [start_year] [years]
# Env:   OPENTTD_BIN  path to the openttd binary (default: build/openttd)
#        KEEP_WORK=1  keep the temporary profile for inspection
#        PERSONALITY  0 cautious, 1 balanced, 2 aggressive, 3 random (default 3)
#        RUN1_AI_DIR  play run 1 with another copy of the AI (e.g. an older version),
#                     then load that save with this version in run 2 (upgrade test)
#
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
AI_DIR="$ROOT/extensions/nordlys_air"
BIN="${OPENTTD_BIN:-$ROOT/build/openttd}"
START_YEAR="${1:-1995}"
YEARS="${2:-6}"
TICKS_PER_YEAR=27010

if [[ ! -x "$BIN" ]]; then
	echo "FAIL: no openttd binary at $BIN (build first, or set OPENTTD_BIN)" >&2
	exit 1
fi
if ! ls "$(dirname "$BIN")"/baseset/OpenGFX*.tar >/dev/null 2>&1; then
	echo "FAIL: OpenGFX not found in $(dirname "$BIN")/baseset" >&2
	echo "      Copy OpenGFX-*.tar there (it is free, from the in-game content download)." >&2
	exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/nordlys-air.XXXXXX")"
cleanup() { [[ "${KEEP_WORK:-0}" == 1 ]] && echo "Kept work dir: $WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

# One profile directory, at the personal path the game uses on this OS.
PROFILE="$WORK/profile"
mkdir -p "$PROFILE/ai" "$PROFILE/scripts" "$PROFILE/save" "$WORK/home/Documents" "$WORK/xdg"
if [[ "$(uname)" == Darwin ]]; then
	ln -s "$PROFILE" "$WORK/home/Documents/OpenTTD"
else
	ln -s "$PROFILE" "$WORK/xdg/openttd"
fi
ln -s "${RUN1_AI_DIR:-$AI_DIR}" "$PROFILE/ai/nordlys_air"

cat > "$PROFILE/test.cfg" <<EOF
[misc]
language = english.lng

[gui]
autosave = off

[game_creation]
map_x = 8
map_y = 8
starting_year = $START_YEAR
generation_seed = 20261023
town_name = english

[difficulty]
max_no_competitors = 1
competitors_interval = 0

[ai_players]
"Nordlys Air" = personality=${PERSONALITY:-3}
EOF

# Save every month, so the last save is at most one month old when the run ends.
printf 'schedule on-next-calendar-month monthly.scr\n' > "$PROFILE/scripts/game_start.scr"
printf 'save nordlys_smoke\nschedule on-next-calendar-month monthly.scr\n' > "$PROFILE/monthly.scr"

run_game() {
	local log="$1"; shift
	(cd "$WORK" && HOME="$WORK/home" XDG_DATA_HOME="$WORK/xdg" XDG_CONFIG_HOME="$WORK/xdg" \
		"$BIN" -x -c "$PROFILE/test.cfg" -v null:ticks="$TICKS" -s null -m null -d script=4 "$@") > "$log" 2>&1
}

check_clean() {
	local log="$1"
	if grep -E "\[S\]|script died|Your script made an error|Error compiling" "$log" >/dev/null; then
		echo "FAIL: script error in $log:" >&2
		grep -E -B2 -A8 "\[S\]|script died|Your script made an error|Error compiling" "$log" | head -40 >&2
		exit 1
	fi
}

echo "== Run 1: new game, start $START_YEAR, $YEARS years"
TICKS=$((TICKS_PER_YEAR * YEARS))
run_game "$WORK/run1.log" -g || { echo "FAIL: game exited with an error" >&2; tail -30 "$WORK/run1.log" >&2; exit 1; }
check_clean "$WORK/run1.log"
grep -q "Nordlys Air er klar for avgang" "$WORK/run1.log" || { echo "FAIL: AI never started" >&2; tail -30 "$WORK/run1.log" >&2; exit 1; }
ROUTES=$(grep -c "Ny rute:" "$WORK/run1.log" || true)
[[ "$ROUTES" -ge 1 ]] || { echo "FAIL: no routes built" >&2; grep "\[script\]" "$WORK/run1.log" | tail -30 >&2; exit 1; }
SAVE="$PROFILE/save/nordlys_smoke.sav"
[[ -f "$SAVE" ]] || { echo "FAIL: no save game written" >&2; exit 1; }

echo "== Run 2: load the save and play one more year"
ln -sfn "$AI_DIR" "$PROFILE/ai/nordlys_air"
TICKS=$TICKS_PER_YEAR
run_game "$WORK/run2.log" -g "$SAVE" || { echo "FAIL: loaded game exited with an error" >&2; tail -30 "$WORK/run2.log" >&2; exit 1; }
check_clean "$WORK/run2.log"
grep -E "Ruter i drift: [1-9]" "$WORK/run2.log" >/dev/null || { echo "FAIL: routes were lost after load" >&2; grep "\[script\]" "$WORK/run2.log" | tail -20 >&2; exit 1; }

echo "== Nordlys Air log (both runs)"
grep -h -E "Ny rute|Årsrapport|pensjoneres|styrtet|gjeldfri|Ruter i drift|sliter|byttes ut|større flyplasser|Postfly|Personlighet| fly, overskudd" "$WORK/run1.log" "$WORK/run2.log" \
	| sed -E 's/^.*\[script\] *//' | head -80
echo "PASS: $ROUTES routes built, state survived save and load"
