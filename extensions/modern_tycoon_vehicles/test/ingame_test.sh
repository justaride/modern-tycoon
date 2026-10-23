#!/usr/bin/env bash
# Headless in-game test for Modern Tycoon Trains.
#
# Builds the NewGRF, then in a throw-away profile (never the player profile):
#   1. starts a 2020 game with the GRF and the test AI (test/ai), which must
#      find both vehicles, build them, refit the wagons and run the train;
#   2. reloads the saved game and checks the train survived;
#   3. runs Fjellbanen Gods with the GRF for two years and reports which
#      locomotive it chose (informational: it may prefer another engine).
#
# Env: OPENTTD_BIN (default ../../build/openttd), KEEP_WORK=1 to keep the profile.
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

PACK="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$PACK/../.." && pwd)"
BIN="${OPENTTD_BIN:-$ROOT/build/openttd}"
[[ -x "$BIN" ]] || { echo "FAIL: no openttd binary at $BIN (set OPENTTD_BIN)" >&2; exit 1; }

"$PACK/build.sh" >/dev/null

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mt-trains.XXXXXX")"
cleanup() { [[ "${KEEP_WORK:-0}" == 1 ]] && echo "Kept work dir: $WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

PROFILE="$WORK/profile"
# With -c, the config file's directory becomes the personal directory, so the
# config lives in the profile and HOME/XDG point at empty directories.
mkdir -p "$PROFILE/ai" "$PROFILE/game" "$PROFILE/newgrf" "$PROFILE/scripts" "$PROFILE/save" "$WORK/home" "$WORK/xdg"
cp "$PACK/generated/modern_tycoon_trains.grf" "$PROFILE/newgrf/"
ln -s "$PACK/test/ai" "$PROFILE/ai/mt_vehicle_test"
ln -s "$PACK/test/gs" "$PROFILE/game/mt_fleet_census"
[[ -d "$ROOT/extensions/fjellbanen_gods" ]] && ln -s "$ROOT/extensions/fjellbanen_gods" "$PROFILE/ai/fjellbanen_gods"

write_cfg() {
	cat > "$PROFILE/$1.cfg" <<EOF
[misc]
language = english.lng

[gui]
autosave = off

[game_creation]
map_x = 8
map_y = 8
starting_year = 2020
generation_seed = 20261023
town_name = english

[difficulty]
max_no_competitors = 1
competitors_interval = 0
competitor_speed = 4

[ai_players]
"$2" =

[newgrf]
modern_tycoon_trains.grf =
EOF
	if [[ -n "${3:-}" ]]; then printf '\n[game_scripts]\n"%s" =\n' "$3" >> "$PROFILE/$1.cfg"; fi
}

run_game() {
	local cfg="$1" log="$2" ticks="$3"; shift 3
	(cd "$PROFILE" && HOME="$WORK/home" XDG_DATA_HOME="$WORK/xdg" XDG_CONFIG_HOME="$WORK/xdg" \
		"$BIN" -x -c "$PROFILE/$cfg.cfg" -v null:ticks="$ticks" -s null -m null -d script=4,grf=1 "$@") > "$log" 2>&1
}

check_clean() {
	if grep -E "\[S\]|script died|Your script made an error|MTV-TEST FAIL|NewGRF.*(not found|disabled)|\[grf:[01]\].*(rror|nvalid)" "$1" >/dev/null; then
		echo "FAIL: errors in $1:" >&2
		grep -E -A6 "\[S\]|script died|Your script made an error|MTV-TEST FAIL|NewGRF.*(not found|disabled)|\[grf:[01]\].*(rror|nvalid)" "$1" | head -30 >&2
		exit 1
	fi
}

printf 'schedule on-next-calendar-month monthly.scr\n' > "$PROFILE/scripts/game_start.scr"
printf 'save mt_trains\nschedule on-next-calendar-month monthly.scr\n' > "$PROFILE/monthly.scr"

echo "== Run 1: 2020 game with the GRF and the vehicle test AI"
write_cfg vehicles "MT Vehicle Test"
run_game vehicles "$WORK/run1.log" 9000 -g || { echo "FAIL: game exited with an error" >&2; tail -20 "$WORK/run1.log" >&2; exit 1; }
check_clean "$WORK/run1.log"
grep -q "MTV-TEST RUN PASS" "$WORK/run1.log" || { echo "FAIL: train did not run" >&2; grep -E "MTV-TEST|grf" "$WORK/run1.log" | tail -20 >&2; exit 1; }
[[ -f "$PROFILE/save/mt_trains.sav" ]] || { echo "FAIL: no save written" >&2; exit 1; }

echo "== Run 2: reload the save"
run_game vehicles "$WORK/run2.log" 3000 -g "$PROFILE/save/mt_trains.sav" || { echo "FAIL: reload exited with an error" >&2; tail -20 "$WORK/run2.log" >&2; exit 1; }
check_clean "$WORK/run2.log"
grep -q "MTV-TEST RELOAD ok" "$WORK/run2.log" || { echo "FAIL: train lost after reload" >&2; grep "MTV-TEST" "$WORK/run2.log" >&2; exit 1; }

grep -h "MTV-TEST" "$WORK/run1.log" "$WORK/run2.log" | sed -E 's/^.*\] MTV-TEST/MTV-TEST/'

if [[ -L "$PROFILE/ai/fjellbanen_gods" ]]; then
	echo "== Run 3 (informational): Fjellbanen Gods with the GRF, two years from 2020"
	write_cfg rival "Fjellbanen Gods" "MT Fleet Census"
	run_game rival "$WORK/run3.log" 54020 -g || { echo "FAIL: rival game exited with an error" >&2; tail -20 "$WORK/run3.log" >&2; exit 1; }
	check_clean "$WORK/run3.log"
	grep -h -E "Ny jernbane|Årsrapport|MTV-CENSUS" "$WORK/run3.log" | sed -E 's/^.*\[I\] *//' | tail -8 || true
	census="$(grep "MTV-CENSUS" "$WORK/run3.log" | tail -1 || true)"
	if [[ "$census" == *"Tinde DM6"* ]]; then echo "Fjellbanen Gods runs the Tinde DM6"; else echo "Fjellbanen Gods does not run the Tinde DM6 (it picks locomotives by speed x power)"; fi
	if [[ "$census" == *"Tinde Bulk Hopper"* ]]; then echo "Fjellbanen Gods runs Tinde Bulk Hoppers"; else echo "Fjellbanen Gods does not run Tinde Bulk Hoppers"; fi
fi

echo "PASS: Modern Tycoon Trains loads, builds, refits, runs and survives save/reload"
