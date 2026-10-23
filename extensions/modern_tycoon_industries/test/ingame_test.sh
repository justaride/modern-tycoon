#!/usr/bin/env bash
# Headless in-game test for Modern Tycoon Space Industry.
#
# Builds the NewGRF, then in a throw-away profile (never the player profile):
#   1. starts a 1990 temperate game with the GRF and the test GameScript
#      (test/gs), which checks the new cargos, builds all three industries,
#      checks their acceptance, finds vehicles that refit to the new cargos and
#      waits for the spaceport to produce asteroid ore;
#   2. reloads the saved game and checks the industries survived.
#
# Env: OPENTTD_BIN (default ../../build/openttd), KEEP_WORK=1 to keep the profile,
#      SKIP_BUILD=1 to test the already built .grf.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$PACK/../.." && pwd)"
BIN="${OPENTTD_BIN:-$ROOT/build/openttd}"
[[ -x "$BIN" ]] || { echo "FAIL: no openttd binary at $BIN (set OPENTTD_BIN)" >&2; exit 1; }

[[ "${SKIP_BUILD:-0}" == 1 ]] || "$PACK/build.sh" >/dev/null

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mt-space.XXXXXX")"
cleanup() { [[ "${KEEP_WORK:-0}" == 1 ]] && echo "Kept work dir: $WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

PROFILE="$WORK/profile"
mkdir -p "$PROFILE/game" "$PROFILE/newgrf" "$PROFILE/scripts" "$PROFILE/save" "$WORK/home" "$WORK/xdg"
cp "$PACK/generated/modern_tycoon_space.grf" "$PROFILE/newgrf/"
ln -s "$PACK/test/gs" "$PROFILE/game/mt_space_test"

cat > "$PROFILE/space.cfg" <<CFG
[misc]
language = english.lng

[gui]
autosave = off

[game_creation]
map_x = 7
map_y = 7
starting_year = 1990
generation_seed = 20261023
landscape = temperate
terrain_type = 0
town_name = english

[difficulty]
max_no_competitors = 0
terrain_type = 0

[newgrf]
modern_tycoon_space.grf =

[game_scripts]
"MT Space Test" =
CFG

run_game() {
	local log="$1" ticks="$2"; shift 2
	(cd "$PROFILE" && HOME="$WORK/home" XDG_DATA_HOME="$WORK/xdg" XDG_CONFIG_HOME="$WORK/xdg" \
		"$BIN" -x -c "$PROFILE/space.cfg" -v null:ticks="$ticks" -s null -m null -d script=4,grf=1 "$@") > "$log" 2>&1
}

check_clean() {
	local pat='\[S\]|script died|Your script made an error|MTS-TEST FAIL|NewGRF.*(not found|disabled)|\[grf:[01]\].*(rror|nvalid)'
	if grep -E "$pat" "$1" >/dev/null; then
		echo "FAIL: errors in $1:" >&2
		grep -E -A6 "$pat" "$1" | head -30 >&2
		exit 1
	fi
}

printf 'schedule on-next-calendar-month monthly.scr\n' > "$PROFILE/scripts/game_start.scr"
printf 'save mt_space\nschedule on-next-calendar-month monthly.scr\n' > "$PROFILE/monthly.scr"

echo "== Run 1: 1990 game with the GRF and the test GameScript"
run_game "$WORK/run1.log" 9000 -g || { echo "FAIL: game exited with an error" >&2; tail -20 "$WORK/run1.log" >&2; exit 1; }
check_clean "$WORK/run1.log"
grep -q "MTS-TEST RUN PASS" "$WORK/run1.log" || { echo "FAIL: test did not pass" >&2; grep -E "MTS-TEST|grf|script" "$WORK/run1.log" | tail -20 >&2; exit 1; }
[[ -f "$PROFILE/save/mt_space.sav" ]] || { echo "FAIL: no save written" >&2; exit 1; }

echo "== Run 2: reload the save"
run_game "$WORK/run2.log" 3000 -g "$PROFILE/save/mt_space.sav" || { echo "FAIL: reload exited with an error" >&2; tail -20 "$WORK/run2.log" >&2; exit 1; }
check_clean "$WORK/run2.log"
grep -q "MTS-TEST RELOAD ok" "$WORK/run2.log" || { echo "FAIL: industries lost after reload" >&2; grep "MTS-TEST" "$WORK/run2.log" >&2; exit 1; }

grep -h "MTS-TEST" "$WORK/run1.log" "$WORK/run2.log" | sed -E 's/^.*\] MTS-TEST/MTS-TEST/'
echo "PASS: Modern Tycoon Space Industry loads, builds, produces and survives save/reload"
