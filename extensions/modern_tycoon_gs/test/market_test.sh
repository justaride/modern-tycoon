#!/usr/bin/env bash
# Headless tests for the Modern Tycoon market lab and The Transport Ledger.
#
# Every scenario runs in a throw-away profile (never the player's profile),
# with null video/sound/music drivers.
#
#   merger   Gate 1: a bankrupt company is bought; portfolio transfer, self-share
#            settlement, delisting payouts, pending settlement, funds rules.
#   delist   Gate 1: a bankrupt company closes; delisting payouts and released lots.
#   news     A ten-year game with a route-building AI; checks the newspaper is
#            useful and not spammy, then reloads the save.
#   migrate  A schema 2 save from the last schema 2 commit (SCHEMA2_COMMIT) loads into the current script.
#   soak     The original 150,000-tick soak with the built-in buy/distribution/sell self-test.
#   all      Everything above.
#
# Usage: extensions/modern_tycoon_gs/test/market_test.sh [scenario]
# Env:   OPENTTD_BIN  openttd binary (default: build/openttd of this checkout)
#        KEEP_WORK=1  keep the temporary profiles
#
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GS_DIR="$ROOT/extensions/modern_tycoon_gs"
TEST_AI_DIR="$ROOT/extensions/modern_tycoon_test_ai"
BIN="${OPENTTD_BIN:-$ROOT/build/openttd}"
TICKS_PER_MONTH=2250
SCENARIO="${1:-all}"

if [[ ! -x "$BIN" ]]; then echo "FAIL: no openttd binary at $BIN (set OPENTTD_BIN)" >&2; exit 1; fi
if ! ls "$(dirname "$BIN")"/baseset/OpenGFX*.tar >/dev/null 2>&1; then
	echo "FAIL: OpenGFX not found in $(dirname "$BIN")/baseset" >&2; exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mt-market.XXXXXX")"
cleanup() { [[ "${KEEP_WORK:-0}" == 1 ]] && echo "Kept work dir: $WORK" || rm -rf "$WORK"; }
trap cleanup EXIT

# new_profile <name>: an empty profile at the personal path the game uses on this OS.
new_profile() {
	local base="$WORK/$1"
	mkdir -p "$base/profile/ai" "$base/profile/game" "$base/profile/scripts" "$base/profile/save" "$base/home/Documents" "$base/xdg" "$base/run"
	if [[ "$(uname)" == Darwin ]]; then ln -s "$base/profile" "$base/home/Documents/OpenTTD"; else ln -s "$base/profile" "$base/xdg/openttd"; fi
	printf 'schedule on-next-calendar-month monthly.scr\n' > "$base/profile/scripts/game_start.scr"
	printf 'save mt_test\nschedule on-next-calendar-month monthly.scr\n' > "$base/profile/monthly.scr"
	echo "$base"
}

# write_cfg <base> <start_year> <ai lines> <gs settings>; one competitor per AI line.
write_cfg() {
	cat > "$1/profile/test.cfg" <<CFG
[misc]
language = english.lng

[gui]
autosave = off
ai_developer_tools = true

[game_creation]
map_x = 8
map_y = 8
starting_year = $2
generation_seed = 20261023
town_name = english

[difficulty]
max_no_competitors = $(printf '%s\n' "$3" | grep -c .)
competitors_interval = 0

[ai_players]
$3

[game_scripts]
"Modern Tycoon Markets and News" = $4
CFG
}

# run_game <base> <log> <ticks> [extra openttd args]
run_game() {
	local base="$1" log="$2" ticks="$3"; shift 3
	(cd "$base/run" && HOME="$base/home" XDG_DATA_HOME="$base/xdg" XDG_CONFIG_HOME="$base/xdg" \
		"$BIN" -x -c "$base/profile/test.cfg" -v null:ticks="$ticks" -s null -m null -d script=4 "$@") > "$log" 2>&1 \
		|| { echo "FAIL: openttd exited with an error ($log)" >&2; tail -30 "$log" >&2; exit 1; }
}

check_clean() {
	if grep -E "\[S\]|\[E\]|script died|Your script made an error|Error compiling|No data saved" "$1" >/dev/null; then
		echo "FAIL: script error in $1:" >&2
		grep -E -B3 -A10 "\[S\]|\[E\]|script died|Your script made an error|Error compiling|No data saved" "$1" | head -60 >&2
		exit 1
	fi
}

strip_log() { sed -E 's/^.*\[script:[0-9]+\] *(\[[0-9]+\] \[.\] )?//'; }

GS_DEFAULTS="company_dividend_percent=25,company_market=1,industry_market=1,industry_yield_per_unit=10,max_industries=12,transaction_fee_bp=100"

# fixture <merger|delist>
fixture() {
	local name="$1" code accept
	if [[ "$name" == merger ]]; then code=1; accept=1; else code=2; accept=0; fi
	local base; base="$(new_profile "$name")"
	ln -s "$GS_DIR" "$base/profile/game/modern_tycoon_gs"
	ln -s "$TEST_AI_DIR" "$base/profile/ai/modern_tycoon_test_ai"
	local ai="\"Modern Tycoon Test Company\" = accept_merger=$accept"
	write_cfg "$base" 1990 "$ai
$ai
$ai" "$GS_DEFAULTS,news_frequency=1,developer_fixture=$code,developer_self_test=0"

	echo "== $name fixture: run 1 (setup, pending settlement, drain), 5 months"
	run_game "$base" "$base/run1.log" $((TICKS_PER_MONTH * 5)) -g
	check_clean "$base/run1.log"
	grep -q "MT-FIXTURE DRAINED" "$base/run1.log" || { echo "FAIL: fixture never drained the target" >&2; grep "MT-" "$base/run1.log" | strip_log >&2; exit 1; }
	if grep -q "MT-FIXTURE COMPLETE" "$base/run1.log"; then echo "FAIL: fixture finished before the reload" >&2; exit 1; fi

	echo "== $name fixture: run 2 (reload mid-bankruptcy, wait for the outcome), 13 months"
	run_game "$base" "$base/run2.log" $((TICKS_PER_MONTH * 13)) -g "$base/profile/save/mt_test.sav"
	check_clean "$base/run2.log"
	grep -q "MT-FIXTURE RESUME" "$base/run2.log" || { echo "FAIL: fixture did not resume from the save" >&2; exit 1; }
	cat "$base/run1.log" "$base/run2.log" | grep -E "MT-FIXTURE|Takeover offer" | strip_log
	local summary; summary="$(grep -h "MT-FIXTURE COMPLETE" "$base/run2.log" || true)"
	[[ -n "$summary" ]] || { echo "FAIL: fixture did not complete" >&2; exit 1; }
	[[ "$summary" == *"failed=0"* ]] || { echo "FAIL: $summary" >&2; exit 1; }
	echo "PASS: $name fixture: $(echo "$summary" | strip_log)"
}

news() {
	local base; base="$(new_profile news)"
	ln -s "$GS_DIR" "$base/profile/game/modern_tycoon_gs"
	ln -s "$TEST_AI_DIR" "$base/profile/ai/modern_tycoon_test_ai"
	local ai_lines="\"Modern Tycoon Test Company\" ="
	# A route-building rival gives Rival Watch something to report. Nordlys Air lives on another branch.
	if git -C "$ROOT" cat-file -e origin/claude/first-ai-player:extensions/nordlys_air/main.nut 2>/dev/null; then
		mkdir -p "$base/profile/ai/nordlys_air"
		for f in info.nut main.nut; do git -C "$ROOT" show "origin/claude/first-ai-player:extensions/nordlys_air/$f" > "$base/profile/ai/nordlys_air/$f"; done
		ai_lines="\"Nordlys Air\" =
$ai_lines"
	else
		echo "note: Nordlys Air not available; Rival Watch will only see idle companies"
	fi
	write_cfg "$base" 1995 "$ai_lines" "$GS_DEFAULTS,news_frequency=1,developer_fixture=0,developer_self_test=0"

	echo "== news: ten years"
	run_game "$base" "$base/run1.log" $((TICKS_PER_MONTH * 12 * 10)) -g
	check_clean "$base/run1.log"
	local editions popups
	editions=$(grep -c "MT-LEDGER EDITION" "$base/run1.log" || true)
	popups=$(grep "MT-LEDGER STATS" "$base/run1.log" | tail -1 | sed -E 's/.*popups=([0-9]+).*/\1/')
	echo "-- first edition and the last two editions:"
	grep -E "MT-LEDGER (EDITION|  )" "$base/run1.log" | strip_log | awk '/MT-LEDGER EDITION/{n++} n==1' | head -20
	echo "..."
	grep -E "MT-LEDGER (EDITION|  )" "$base/run1.log" | strip_log | awk -v total="$editions" '/MT-LEDGER EDITION/{n++} n>=total-1'
	grep "MT-LEDGER STATS" "$base/run1.log" | strip_log
	[[ "$editions" -ge 30 ]] || { echo "FAIL: only $editions editions in ten years" >&2; exit 1; }
	[[ "$popups" -le 60 ]] || { echo "FAIL: $popups news pop-ups in ten years is spammy" >&2; exit 1; }
	if grep -q "Nordlys Air" "$base/profile/test.cfg"; then
		grep -q "RIVAL WATCH" "$base/run1.log" || { echo "FAIL: no Rival Watch reports with a route-building AI" >&2; exit 1; }
	fi

	echo "== news: reload the ten-year save and play two more months"
	local archived; archived=$(grep "MT-LEDGER STATS" "$base/run1.log" | tail -1 | sed -E 's/.*archived=([0-9]+).*/\1/')
	run_game "$base" "$base/run2.log" $((TICKS_PER_MONTH * 2)) -g "$base/profile/save/mt_test.sav"
	check_clean "$base/run2.log"
	grep -E "MT-LEDGER STATS start .*archived=$archived" "$base/run2.log" >/dev/null \
		|| { echo "FAIL: archive not restored (expected archived=$archived)" >&2; grep "MT-LEDGER STATS" "$base/run2.log" >&2; exit 1; }
	echo "PASS: news: $editions editions, $popups pop-ups in ten years; archive of $archived editions survived reload"
}

migrate() {
	local base; base="$(new_profile migrate)"
	mkdir -p "$base/old_gs"
	# Pinned: main moved to schema 3 when the Ledger merged, so origin/main no longer has the old script.
	local old="${SCHEMA2_COMMIT:-72e60f2ef}"
	git -C "$ROOT" archive "$old" extensions/modern_tycoon_gs | tar -x -C "$base/old_gs"
	grep -q 'GetVersion()     { return 2; }' "$base/old_gs/extensions/modern_tycoon_gs/info.nut" || { echo "FAIL: $old is not schema 2" >&2; exit 1; }
	ln -s "$base/old_gs/extensions/modern_tycoon_gs" "$base/profile/game/modern_tycoon_gs"
	ln -s "$TEST_AI_DIR" "$base/profile/ai/modern_tycoon_test_ai"
	write_cfg "$base" 1995 "\"Modern Tycoon Test Company\" =
\"Modern Tycoon Test Company\" =" "$GS_DEFAULTS,news_frequency=2,developer_self_test=0"

	echo "== migrate: one year with the schema 2 script from ${SCHEMA2_COMMIT:-72e60f2ef}"
	run_game "$base" "$base/run1.log" $((TICKS_PER_MONTH * 12)) -g
	check_clean "$base/run1.log"
	echo "== migrate: load that save with the current script"
	rm "$base/profile/game/modern_tycoon_gs"
	ln -s "$GS_DIR" "$base/profile/game/modern_tycoon_gs"
	run_game "$base" "$base/run2.log" $((TICKS_PER_MONTH * 3)) -g "$base/profile/save/mt_test.sav"
	check_clean "$base/run2.log"
	grep -h "Loading Modern Tycoon save data from script version 2" "$base/run2.log" >/dev/null || { echo "FAIL: save was not loaded as version 2" >&2; exit 1; }
	# The last old exchange close says how many securities the schema 2 save holds.
	local before after
	before=$(grep -h "MT-LEDGER MIGRATED" "$base/run2.log" | sed -E 's/.* ([0-9]+) securities listed.*/\1/')
	after=$(grep -h "saved instruments (schema 2)" "$base/run2.log" | sed -E 's/.*loaded ([0-9]+) saved.*/\1/')
	[[ -n "$before" && "$before" == "$after" ]] || { echo "FAIL: schema 2 save listed '$before' securities, loaded '$after'" >&2; exit 1; }
	grep -E "MT-LEDGER STATS start .*archived=1 " "$base/run2.log" >/dev/null || { echo "FAIL: old headlines were not archived" >&2; grep "MT-LEDGER" "$base/run2.log" >&2; exit 1; }
	grep -q "MT-LEDGER EDITION" "$base/run2.log" || { echo "FAIL: no edition after migration" >&2; exit 1; }
	echo "PASS: migrate: schema 2 save with $before instruments loaded; old headlines archived; new editions published"
}

soak() {
	local base; base="$(new_profile soak)"
	ln -s "$GS_DIR" "$base/profile/game/modern_tycoon_gs"
	ln -s "$TEST_AI_DIR" "$base/profile/ai/modern_tycoon_test_ai"
	write_cfg "$base" 1950 "\"Modern Tycoon Test Company\" =
\"Modern Tycoon Test Company\" =" "$GS_DEFAULTS,news_frequency=2,developer_self_test=1,developer_fixture=0"
	echo "== soak: 150,000 ticks with the built-in self-test"
	run_game "$base" "$base/run1.log" 150000 -g
	check_clean "$base/run1.log"
	grep -q "self-test passed" "$base/run1.log" || { echo "FAIL: self-test did not pass" >&2; grep "self-test" "$base/run1.log" >&2; exit 1; }
	echo "PASS: soak: $(grep -h "self-test passed" "$base/run1.log" | strip_log)"
}

case "$SCENARIO" in
	merger|delist) fixture "$SCENARIO" ;;
	news) news ;;
	migrate) migrate ;;
	soak) soak ;;
	all) fixture merger; fixture delist; news; migrate; soak ;;
	*) echo "unknown scenario: $SCENARIO" >&2; exit 2 ;;
esac
