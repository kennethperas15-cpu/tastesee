"""Demand forecasting — pure Python, no numpy (PyScript-safe).
Algorithm (explainable, senior-level baseline):
  1. 7-day moving average = baseline
  2. Weekday seasonality factor = avg(that weekday) / overall avg
  3. Linear trend (least squares) over last 14 days
  4. forecast = (baseline + slope * days_ahead) * weekday_factor
  5. Safety stock x1.05, clamp >= 0. Confidence band +-15%.
"""
from __future__ import annotations
import math


def linear_slope(y: list[float]) -> tuple[float, float]:
    n = len(y)
    if n < 2:
        return 0.0, (y[0] if y else 0.0)
    x_mean = (n - 1) / 2
    y_mean = sum(y) / n
    num = sum((i - x_mean) * (v - y_mean) for i, v in enumerate(y))
    den = sum((i - x_mean) ** 2 for i in range(n)) or 1.0
    slope = num / den
    intercept = y_mean - slope * x_mean
    return slope, intercept


def weekday_factors(qtys: list[float], weekdays: list[int]) -> dict[int, float]:
    overall = sum(qtys) / len(qtys) if qtys else 1.0
    if overall == 0:
        return {d: 1.0 for d in range(7)}
    buckets: dict[int, list[float]] = {d: [] for d in range(7)}
    for q, w in zip(qtys, weekdays):
        buckets[w].append(q)
    return {d: ((sum(v) / len(v)) / overall if v else 1.0) for d, v in buckets.items()}


def forecast_next_7(daily_qty: list[float], weekdays: list[int], daily_rev: list[float] | None = None):
    """Returns list of dicts: {day_index, qty, low, high, bake_plan, revenue}."""
    if len(daily_qty) < 7:
        pad = [sum(daily_qty) / max(len(daily_qty), 1)] * (7 - len(daily_qty))
        daily_qty = pad + daily_qty
        weekdays = ([0, 1, 2, 3, 4, 5, 6] * 2)[: 7 - len(weekdays)] + weekdays if weekdays else list(range(7))
    recent = daily_qty[-14:] if len(daily_qty) >= 14 else daily_qty
    baseline = sum(daily_qty[-7:]) / 7
    slope, _ = linear_slope(recent)
    slope = max(min(slope, baseline * 0.15), -baseline * 0.15)  # dampen wild trends
    factors = weekday_factors(daily_qty, weekdays)
    last_wd = weekdays[-1] if weekdays else 0
    avg_price = (sum(daily_rev) / max(sum(daily_qty), 1)) if daily_rev else 5.20
    out = []
    for i in range(1, 8):
        wd = (last_wd + i) % 7
        raw = (baseline + slope * i) * factors.get(wd, 1.0)
        raw = max(raw, 0.0)
        bake = math.ceil(raw * 1.05)  # 5% safety = less waste than typical 20%
        out.append({
            "day_ahead": i, "weekday": wd,
            "qty": round(raw, 1),
            "low": round(raw * 0.85, 1), "high": round(raw * 1.15, 1),
            "bake_plan": bake,
            "revenue": round(raw * avg_price, 2),
        })
    return out


def peak_hours(order_hours: list[int]) -> dict:
    buckets = [0] * 24
    for h in order_hours:
        if 0 <= h < 24:
            buckets[h] += 1
    top = sorted(range(24), key=lambda h: buckets[h], reverse=True)[:3]
    return {"hourly": buckets, "top": top}


def demo_last_28_days(seed: int = 7) -> tuple[list[float], list[int], list[float]]:
    """Deterministic demo sales when Supabase has no history yet."""
    import random
    rng = random.Random(seed)
    qtys, revs, wds = [], [], []
    for i in range(28):
        wd = (2 + i) % 7  # start Wednesday
        weekend_boost = 1.45 if wd in (5, 6) else 1.0
        growth = 1 + i * 0.008
        base = 42 * weekend_boost * growth + rng.uniform(-6, 8)
        q = max(18.0, round(base, 1))
        qtys.append(q)
        revs.append(round(q * (5.2 + rng.uniform(-0.3, 0.5)), 2))
        wds.append(wd)
    return qtys, wds, revs
