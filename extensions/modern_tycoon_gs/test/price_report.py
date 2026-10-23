#!/usr/bin/env python3
"""Summarise MT-PRICE lines from a Modern Tycoon game log and check the pricing contract.

Usage: price_report.py <log> [--skip-months N]
Exit code 0 when every check passes, 1 otherwise.

SPDX-License-Identifier: GPL-2.0-only
"""
import re
import statistics
import sys

LINE = re.compile(r"MT-PRICE (\d+) (\S+) price=(-?\d+) fair=(-?\d+) fundamental=(-?\d+) sentiment=(-?\d+)")
OPEN = re.compile(r" open=([01])")
# A company that opened for trading may not rise more than this in one month or in its first year.
MAX_OPEN_MONTHLY_RISE = 1.0
MAX_FIRST_YEAR_RETURN = 3.0


def main():
    path = sys.argv[1]
    skip = 6
    if "--skip-months" in sys.argv:
        skip = int(sys.argv[sys.argv.index("--skip-months") + 1])

    series = {}
    opened = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = LINE.search(line)
            if not match:
                continue
            month, sec, price, fair, fundamental, sentiment = match.groups()
            series.setdefault(sec, []).append((int(month), int(price), int(fair), int(fundamental), int(sentiment)))
            flag = OPEN.search(line)
            if flag and flag.group(1) == "1" and sec not in opened:
                opened[sec] = int(month)

    if not series:
        print("FAIL: no MT-PRICE lines")
        return 1

    first_month = min(points[0][0] for points in series.values())
    ratios, ups, downs, flats, moves = [], 0, 0, 0, []
    quarter_returns, year_returns = [], []
    company_quarters, company_years = [], []
    for sec, points in series.items():
        points.sort()
        for month, price, fair, fundamental, sentiment in points:
            if month - first_month >= skip and fundamental > 0:
                ratios.append(price / fundamental)
        for (m0, p0, *_), (m1, p1, *_) in zip(points, points[1:]):
            if m1 != m0 + 1 or p0 <= 0:
                continue
            change = (p1 - p0) / p0
            moves.append(change)
            if p1 > p0:
                ups += 1
            elif p1 < p0:
                downs += 1
            else:
                flats += 1
        by_month = {m: p for m, p, *_ in points}
        for month, price in by_month.items():
            if month - first_month < skip or price <= 0:
                continue
            if month + 3 in by_month:
                quarter_returns.append((by_month[month + 3] - price) / price)
                if sec.startswith("C:"):
                    company_quarters.append((by_month[month + 3] - price) / price)
            if month + 12 in by_month:
                year_returns.append((by_month[month + 12] - price) / price)
                if sec.startswith("C:"):
                    company_years.append((by_month[month + 12] - price) / price)

    ratios.sort()
    median_ratio = statistics.median(ratios)
    p10 = ratios[len(ratios) // 10]
    p90 = ratios[(len(ratios) * 9) // 10]
    lost_quarters = sum(1 for r in quarter_returns if r < 0)
    lost_years = sum(1 for r in year_returns if r < 0)
    worst_quarter = min(quarter_returns) if quarter_returns else 0
    worst_year = min(year_returns) if year_returns else 0
    biggest_rise = max(moves) if moves else 0
    biggest_fall = min(moves) if moves else 0

    print(f"securities={len(series)} quotes={sum(len(p) for p in series.values())}")
    print(f"price/fundamental: median={median_ratio:.3f} p10={p10:.3f} p90={p90:.3f} min={ratios[0]:.3f} max={ratios[-1]:.3f}")
    print(f"monthly moves: up={ups} down={downs} flat={flats} biggest rise={biggest_rise:+.1%} biggest fall={biggest_fall:+.1%}")
    print(f"buy-and-hold: lost money in {lost_quarters}/{len(quarter_returns)} quarter holds "
          f"({lost_quarters / max(1, len(quarter_returns)):.0%}, worst {worst_quarter:+.1%}) and "
          f"{lost_years}/{len(year_returns)} one-year holds ({lost_years / max(1, len(year_returns)):.0%}, worst {worst_year:+.1%})")

    lost_cq = sum(1 for r in company_quarters if r < 0)
    lost_cy = sum(1 for r in company_years if r < 0)
    print(f"  company shares only: lost in {lost_cq}/{len(company_quarters)} quarter holds and "
          f"{lost_cy}/{len(company_years)} one-year holds (worst {min(company_years, default=0):+.1%})")

    for sec in sorted(series):
        points = series[sec]
        if sec.startswith("C:"):
            first, last = points[0], points[-1]
            print(f"  {sec}: {first[1]} -> {last[1]} (fundamental {first[3]} -> {last[3]}), mood now {last[4] / 100:+.1f}%")

    # What a buyer could earn once a company opened for trading (logs without the open flag count every month as open).
    open_rises, first_years = [], []
    for sec, points in series.items():
        if not sec.startswith("C:"):
            continue
        start = opened.get(sec, points[0][0] if not opened else None)
        if start is None:
            continue
        by_month = {m: p for m, p, *_ in points}
        for month in sorted(by_month):
            if month > start and month - 1 in by_month and by_month[month - 1] > 0:
                open_rises.append((by_month[month] - by_month[month - 1]) / by_month[month - 1])
        if start + 12 in by_month and by_month[start] > 0:
            first_years.append((sec, (by_month[start + 12] - by_month[start]) / by_month[start]))
    if opened:
        print(f"listing periods: " + " ".join(f"{sec} opened after {month - series[sec][0][0] + 1} months" for sec, month in sorted(opened.items()) if sec.startswith("C:")))
    print(f"after opening: biggest monthly rise={max(open_rises, default=0):+.1%}; first-year returns: " +
          (" ".join(f"{sec} {ret:+.0%}" for sec, ret in first_years) or "none"))

    failures = []
    if open_rises and max(open_rises) > MAX_OPEN_MONTHLY_RISE:
        failures.append(f"an open company rose {max(open_rises):+.0%} in one month (limit {MAX_OPEN_MONTHLY_RISE:+.0%})")
    for sec, ret in first_years:
        if ret > MAX_FIRST_YEAR_RETURN:
            failures.append(f"{sec} returned {ret:+.0%} in its first year of trading (limit {MAX_FIRST_YEAR_RETURN:+.0%})")
    if not 0.8 <= median_ratio <= 1.25:
        failures.append(f"median price/fundamental {median_ratio:.3f} is not within 0.80..1.25")
    if ratios[0] < 0.2 or ratios[-1] > 5.0:
        failures.append(f"price/fundamental range {ratios[0]:.3f}..{ratios[-1]:.3f} breaks the 0.2..5 sanity bound")
    if downs < max(1, (ups + downs) // 6):
        failures.append(f"prices hardly fall: {downs} falls against {ups} rises")
    if lost_quarters == 0:
        failures.append("buy-and-hold never lost money over a quarter")
    if company_quarters and lost_cq == 0:
        failures.append("company shares never lost money over a quarter")
    for failure in failures:
        print("FAIL: " + failure)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
