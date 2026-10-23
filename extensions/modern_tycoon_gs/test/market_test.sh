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
#   migrate  Saves from the schema 2 lab (pinned commit) and the schema 3 Ledger
#            (pinned commit) load into the current script.
#   pricing  Ten years with Nordlys Air and Fjellbanen Gods: quotes track
#            fundamentals, rise and fall, stay bounded, and buy-and-hold can lose.
#   replay   The same game run twice gives identical quotes (determinism).
#   soak     The original 150,000-tick soak with the built-in buy/distribution/sell self-test.
#   all      Everything above.
#
# Usage: extensions/modern_tycoon_gs/test/market_test.sh [scenario]
# Env:   OPENTTD_BIN  openttd binary (default: build/openttd of this checkout)
#        PRICING_SEED map seed for the pricing scenario (default 20261023)
#        KEEP_WORK=1  keep the temporary profiles
#
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GS_DIR="$ROOT/extensions/modern_tycoon_gs"
TEST_AI_DIR="$ROOT/extensions/modern_tycoon_test_ai"
NORDLYS_DIR="$ROOT/extensions/nordlys_air"
FJELLBANEN_DIR="$ROOT/extensions/fjellbanen_gods"
SCHEMA2_REF=926376b84  # Last commit with the schema 2 market lab (before The Transport Ledger).
SCHEMA3_REF=7cf977433  # Schema 3: The Transport Ledger, before deterministic pricing.
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
	ln -s "$NORDLYS_DIR" "$base/profile/ai/nordlys_air"
	# A route-building rival gives Rival Watch something to report.
	local ai_lines="\"Nordlys Air\" =
\"Modern Tycoon Test Company\" ="
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

# migrate <git ref> <script version> <schema>: a save made by an older script loads into this one.
migrate() {
	local ref="$1" version="$2" schema="$3"
	local base; base="$(new_profile "migrate$schema")"
	mkdir -p "$base/old_gs"
	git -C "$ROOT" archive "$ref" extensions/modern_tycoon_gs | tar -x -C "$base/old_gs"
	grep -q "GetVersion()     { return $version; }" "$base/old_gs/extensions/modern_tycoon_gs/info.nut" \
		|| { echo "FAIL: $ref is not script version $version" >&2; exit 1; }
	ln -s "$base/old_gs/extensions/modern_tycoon_gs" "$base/profile/game/modern_tycoon_gs"
	ln -s "$TEST_AI_DIR" "$base/profile/ai/modern_tycoon_test_ai"
	local ais="\"Modern Tycoon Test Company\" =
\"Modern Tycoon Test Company\" ="
	write_cfg "$base" 1995 "$ais" "$GS_DEFAULTS,news_frequency=2,developer_self_test=0"

	echo "== migrate: one year with the schema $schema script from $ref"
	run_game "$base" "$base/run1.log" $((TICKS_PER_MONTH * 12)) -g
	check_clean "$base/run1.log"

	echo "== migrate: load that save with the current script"
	rm "$base/profile/game/modern_tycoon_gs"
	ln -s "$GS_DIR" "$base/profile/game/modern_tycoon_gs"
	run_game "$base" "$base/run2.log" $((TICKS_PER_MONTH * 3)) -g "$base/profile/save/mt_test.sav"
	check_clean "$base/run2.log"
	grep -h "Loading Modern Tycoon save data from script version $version" "$base/run2.log" >/dev/null \
		|| { echo "FAIL: save was not loaded as version $version" >&2; exit 1; }
	local loaded; loaded=$(grep -h "saved instruments (schema $schema)" "$base/run2.log" | sed -E 's/.*loaded ([0-9]+) saved.*/\1/')
	[[ -n "$loaded" && "$loaded" -gt 0 ]] || { echo "FAIL: no instruments loaded from the schema $schema save" >&2; exit 1; }
	grep -E "MT-PRICING state restored for 0 securities, started from fair value for $loaded" "$base/run2.log" >/dev/null \
		|| { echo "FAIL: pricing state was not initialised for all $loaded securities" >&2; grep "MT-PRICING" "$base/run2.log" >&2; exit 1; }
	# Loaded games keep the script settings stored in the save, so the price log stays off; the exchange close shows quotes moved.
	grep -q "Exchange close:" "$base/run2.log" || { echo "FAIL: no exchange close after migration" >&2; exit 1; }
	grep -q "MT-LEDGER EDITION" "$base/run2.log" || { echo "FAIL: no edition after migration" >&2; exit 1; }
	if [[ "$schema" == 2 ]]; then
		local before; before=$(grep -h "MT-LEDGER MIGRATED" "$base/run2.log" | sed -E 's/.* ([0-9]+) securities listed.*/\1/')
		[[ "$before" == "$loaded" ]] || { echo "FAIL: schema 2 save listed '$before' securities, loaded '$loaded'" >&2; exit 1; }
		grep -E "MT-LEDGER STATS start .*archived=1 " "$base/run2.log" >/dev/null || { echo "FAIL: old headlines were not archived" >&2; exit 1; }
	else
		# A year of monthly editions was saved; a fresh Ledger would start with one.
		local kept; kept=$(grep -h "MT-LEDGER STATS start" "$base/run2.log" | sed -E 's/.*editions=([0-9]+).*/\1/')
		[[ -n "$kept" && "$kept" -ge 6 ]] || { echo "FAIL: Ledger editions not kept (start editions='$kept')" >&2; grep "MT-LEDGER STATS" "$base/run2.log" >&2; exit 1; }
	fi
	echo "PASS: migrate: schema $schema save from $ref with $loaded instruments loaded; quotes start from fair value; Ledger continues"
}

# rivals_profile <name>: a profile with Nordlys Air, Fjellbanen Gods and one idle test company.
rivals_profile() {
	local base; base="$(new_profile "$1")"
	ln -s "$GS_DIR" "$base/profile/game/modern_tycoon_gs"
	ln -s "$TEST_AI_DIR" "$base/profile/ai/modern_tycoon_test_ai"
	ln -s "$NORDLYS_DIR" "$base/profile/ai/nordlys_air"
	ln -s "$FJELLBANEN_DIR" "$base/profile/ai/fjellbanen_gods"
	write_cfg "$base" 1995 "\"Nordlys Air\" =
\"Fjellbanen Gods\" =
\"Modern Tycoon Test Company\" =" "$GS_DEFAULTS,news_frequency=1,developer_fixture=0,developer_self_test=0,developer_price_log=1"
	echo "$base"
}

pricing() {
	local base; base="$(rivals_profile pricing)"
	local seed="${PRICING_SEED:-20261023}"
	echo "== pricing: ten years with Nordlys Air, Fjellbanen Gods and an idle company (map seed $seed)"
	run_game "$base" "$base/run1.log" $((TICKS_PER_MONTH * 12 * 10)) -g -G "$seed"
	check_clean "$base/run1.log"
	python3 -I "$GS_DIR/test/price_report.py" "$base/run1.log" > "$base/report.txt" || { cat "$base/report.txt"; exit 1; }
	cat "$base/report.txt"
	echo "-- market reports in the Ledger:"
	grep -E "Quarter in review|beats expectations|misses expectations|quarterly loss|warns it will close|output (jumps|drops)" "$base/run1.log" \
		| strip_log | sed -E 's/^MT-LEDGER +//' | sort | uniq -c | sort -rn | head -12
	grep -q "Quarter in review" "$base/run1.log" || { echo "FAIL: the Ledger never reviewed a quarter" >&2; exit 1; }

	echo "== pricing: reload and play three more months"
	run_game "$base" "$base/run2.log" $((TICKS_PER_MONTH * 3)) -g "$base/profile/save/mt_test.sav"
	check_clean "$base/run2.log"
	grep -E "MT-PRICING state restored for [1-9][0-9]* securities, started from fair value for 0" "$base/run2.log" >/dev/null \
		|| { echo "FAIL: pricing state not restored from the save" >&2; grep "MT-PRICING" "$base/run2.log" >&2; exit 1; }
	echo "PASS: pricing: quotes track fundamentals, rise and fall, stay bounded; state survived reload"
}

replay() {
	local a b; a="$(rivals_profile replay_a)"; b="$(rivals_profile replay_b)"
	echo "== replay: the same two-year game twice"
	run_game "$a" "$a/run1.log" $((TICKS_PER_MONTH * 24)) -g -G 20261023
	run_game "$b" "$b/run1.log" $((TICKS_PER_MONTH * 24)) -g -G 20261023
	check_clean "$a/run1.log"; check_clean "$b/run1.log"
	grep -o "MT-PRICE .*" "$a/run1.log" > "$a/quotes.txt"
	grep -o "MT-PRICE .*" "$b/run1.log" > "$b/quotes.txt"
	local count; count=$(wc -l < "$a/quotes.txt" | tr -d ' ')
	[[ "$count" -gt 100 ]] || { echo "FAIL: only $count quotes" >&2; exit 1; }
	diff -q "$a/quotes.txt" "$b/quotes.txt" >/dev/null || { echo "FAIL: quotes differ between identical games" >&2; diff "$a/quotes.txt" "$b/quotes.txt" | head >&2; exit 1; }
	echo "PASS: replay: $count quotes identical across two runs of the same game"
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
	migrate) migrate "$SCHEMA2_REF" 2 2; migrate "$SCHEMA3_REF" 3 3 ;;
	pricing) pricing ;;
	replay) replay ;;
	soak) soak ;;
	all) fixture merger; fixture delist; news; migrate "$SCHEMA2_REF" 2 2; migrate "$SCHEMA3_REF" 3 3; pricing; replay; soak ;;
	*) echo "unknown scenario: $SCENARIO" >&2; exit 2 ;;
esac
