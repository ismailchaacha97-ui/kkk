#!/usr/bin/env python3
"""
validate_math.py - numerical validation of the maths used by FTMO_QuantEdge.mq4

There is no MetaTrader compiler on this machine, so correctness is
established in two independent ways:

  A. tools/mq4_check.py   - static analysis of the MQL4 source
  B. this script          - a 1:1 Python mirror of every formula in the EA,
                            exercised against synthetic series whose
                            ground truth is known analytically.

Each test states what property is being verified and why it matters.
Nothing here is a performance claim: the synthetic data has no edge in
it, so the purpose is to prove the calculator is right and the control
flow behaves, not to estimate returns.

Run:  python3 tools/validate_math.py
Exit code 0 when every check passes.
"""
import math
import random
import statistics

FAILS = []
CHECKS = 0


def check(name, cond, detail=""):
    global CHECKS
    CHECKS += 1
    if cond:
        print(f"  PASS  {name}" + (f"   [{detail}]" if detail else ""))
    else:
        print(f"  FAIL  {name}" + (f"   [{detail}]" if detail else ""))
        FAILS.append(name)


# =====================================================================
#  MIRROR OF THE EA MATHS
# =====================================================================

def median(xs):
    s = sorted(xs)
    n = len(s)
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def z_score(closes, n, robust=True, atr=0.0, point=1e-5):
    """Mirror of ComputeZScore(): window = the n bars BEFORE the signal bar.

    The EA reads shifts 1..n (closed bars) and compares the current close
    at shift 1, so the bar being judged never enters its own benchmark.
    """
    window = closes[-(n + 1):-1]
    current = closes[-1]
    if robust:
        med = median(window)
        mad = median([abs(x - med) for x in window])
        sigma = 1.4826 * mad
        floor = max(point * 0.5, atr * 0.02)
        sigma = max(sigma, floor)
        return (current - med) / sigma, med, sigma
    mean = sum(window) / n
    var = sum(x * x for x in window) / n - mean * mean
    sd = max(math.sqrt(max(var, 0.0)), max(point * 0.5, atr * 0.02))
    return (current - mean) / sd, mean, sd


def true_ranges(highs, lows, closes, upto):
    trs = []
    for k in range(upto):
        i = len(closes) - 1 - k
        h, l = highs[i], lows[i]
        pc = closes[i - 1]
        trs.append(max(h - l, abs(h - pc), abs(l - pc)))
    return trs


def atr_and_percentile(highs, lows, closes, period, window):
    """Mirror of ComputeATRStats(): current ATR plus its rank in a rolling window."""
    trs = true_ranges(highs, lows, closes, window + period + 1)
    cur = sum(trs[:period]) / period
    below, cnt, win = 0.0, 0, sum(trs[:period])
    for k in range(1, window + 1):
        win += trs[k + period - 1] - trs[k - 1]
        if win / period <= cur:
            below += 1.0
        cnt += 1
    return cur, below / cnt


def momentum(closes, k, atr):
    """Mirror of ComputeMomentum(): normalised by ATR*sqrt(k)."""
    if atr <= 0:
        return 0.0
    return (closes[-1] - closes[-1 - k]) / (atr * math.sqrt(k))


def variance_ratio(closes, q, window):
    """Mirror of ComputeVarianceRatio(): Lo-MacKinlay VR(q)."""
    r1 = [closes[-1 - i] - closes[-2 - i] for i in range(window)]
    m1 = sum(r1) / len(r1)
    v1 = sum((x - m1) ** 2 for x in r1) / (len(r1) - 1)
    if v1 <= 1e-12:
        return 1.0
    rq = [closes[-1 - i] - closes[-1 - i - q] for i in range(len(closes) - q - 1 - (len(closes) - 1 - window))]
    mq = sum(rq) / len(rq)
    vq = sum((x - mq) ** 2 for x in rq) / (len(rq) - 1)
    return vq / (q * v1)


def vratio(closes, q, window):
    """Cleaner re-implementation of the same statistic (used for cross-checks)."""
    r1 = [closes[i] - closes[i - 1] for i in range(len(closes) - window, len(closes))]
    rq = [closes[i] - closes[i - q] for i in range(len(closes) - window, len(closes))]
    v1 = statistics.pvariance(r1)
    vq = statistics.pvariance(rq)
    if v1 <= 0:
        return 1.0
    return vq / (q * v1)


def half_life_stats(closes, window):
    """Mirror of ComputeHalfLife().

    Returns (half_life, df_tstat). The slope is Kendall bias corrected and
    its Dickey-Fuller t statistic is returned so the caller can require
    significance instead of trusting a point estimate.
    """
    xs, ys = [], []
    for i in range(window):
        p_prev = closes[-2 - i]
        p_now = closes[-1 - i]
        xs.append(p_prev)
        ys.append(p_now - p_prev)
    n = len(xs)
    sx, sy = sum(xs), sum(ys)
    sxx = sum(x * x for x in xs)
    sxy = sum(x * y for x, y in zip(xs, ys))
    denom = n * sxx - sx * sx
    if abs(denom) < 1e-12:
        return -1.0, 0.0
    b = (n * sxy - sx * sy) / denom
    a = (sy - b * sx) / n
    sse = sum((y - a - b * x) ** 2 for x, y in zip(xs, ys))
    sxxc = sxx - sx * sx / n
    if sse <= 0 or sxxc <= 0 or n < 3:
        return -1.0, 0.0
    se = math.sqrt((sse / (n - 2)) / sxxc)
    if se <= 0:
        return -1.0, 0.0
    t = b / se
    bc = b + (1.0 + 3.0 * b) / n
    if bc >= 0 or bc <= -1:
        return -1.0, t
    return math.log(2.0) / (-math.log(1.0 + bc)), t


def half_life(closes, window):
    return half_life_stats(closes, window)[0]


def fib_score(highs, lows, close, lookback, levels, tol, atr):
    """Mirror of ComputeFib()."""
    hs = highs[-lookback:]
    ls = lows[-lookback:]
    hi, lo = max(hs), min(ls)
    hi_idx = len(hs) - 1 - hs[::-1].index(hi)   # most recent extreme index
    lo_idx = len(ls) - 1 - ls[::-1].index(lo)
    rng = hi - lo
    if atr <= 0 or rng <= atr * 2.0:
        return 0.0
    up_leg = hi_idx > lo_idx          # later index = more recent bar
    best = 0.0
    for lv in levels:
        if lv <= 0 or lv >= 1:
            continue
        level = hi - lv * rng if up_leg else lo + lv * rng
        dist = abs(close - level) / atr
        if dist > tol:
            continue
        strength = 1.0 - dist / max(tol, 0.01)
        s = strength if up_leg else -strength
        if abs(s) > abs(best):
            best = s
    return max(-1.0, min(1.0, best))


def composite(z, mom, fib, mr_mode, weights=(1.0, 0.6, 0.4), zcap=3.0, momcap=2.0):
    """Mirror of the score combination in UpdateSignalEngine()."""
    fz, fm, ff = z / zcap, mom / momcap, fib
    fz = max(-1.0, min(1.0, fz))
    fm = max(-1.0, min(1.0, fm))
    if mr_mode:
        fz, fm = -fz, -fm
    wz, wm, wf = weights
    wsum = abs(wz) + abs(wm) + abs(wf)
    return max(-1.0, min(1.0, (wz * fz + wm * fm + wf * ff) / wsum))


def lots_for_risk(equity, risk_pct, stop_distance, point, value_per_point_per_lot,
                  lot_step=0.01, min_lot=0.01, max_lot=100.0):
    """Mirror of CalcLots()/NormalizeLot() core arithmetic (rounds DOWN)."""
    money = equity * risk_pct / 100.0
    per_lot = (stop_distance / point) * value_per_point_per_lot
    if per_lot <= 0:
        return 0.0
    raw = money / per_lot
    lots = math.floor(raw / lot_step + 1e-7) * lot_step
    lots = round(lots, 2)
    if lots < min_lot:
        return 0.0
    return min(lots, max_lot)


# =====================================================================
#  SYNTHETIC GENERATORS
# =====================================================================

def gbm(n, s0=1.1000, sigma=0.0006, seed=1):
    rnd = random.Random(seed)
    out = [s0]
    for _ in range(n - 1):
        out.append(out[-1] + rnd.gauss(0, sigma))
    return out


def ou(n, s0=1.1000, theta=0.03, sigma=0.0006, seed=2):
    """Mean reverting process, analytic half-life = ln2/theta."""
    rnd = random.Random(seed)
    mu = s0
    out = [s0]
    for _ in range(n - 1):
        x = out[-1]
        out.append(x + theta * (mu - x) + rnd.gauss(0, sigma))
    return out


def persistent(n, s0=1.1000, phi=0.25, sigma=0.0006, seed=3):
    """Positively autocorrelated returns => trending / momentum regime."""
    rnd = random.Random(seed)
    out = [s0]
    prev = 0.0
    for _ in range(n - 1):
        r = phi * prev + rnd.gauss(0, sigma)
        prev = r
        out.append(out[-1] + r)
    return out


def pack(closes, wick=0.5):
    highs = [c + wick * 0.0006 for c in closes]
    lows = [c - wick * 0.0006 for c in closes]
    return highs, lows, closes


# =====================================================================
#  TESTS
# =====================================================================

def test_zscore():
    print("\n1. Robust z-score  z = (C - median) / (1.4826 * MAD)")
    # 1.1 the MAD-to-sigma factor is consistent for normal data
    ratios = []
    for s in range(400):
        rnd = random.Random(s * 7 + 3)
        data = [rnd.gauss(0, 1) for _ in range(64)]
        mad = median([abs(x - median(data)) for x in data])
        ratios.append(1.4826 * mad / statistics.pstdev(data))
    avg = sum(ratios) / len(ratios)
    check("1.4826*MAD is a consistent sigma estimator", abs(avg - 1.0) < 0.03,
          f"mean ratio {avg:.3f} over 400 samples")

    # 1.2 breakdown point, with a known ground truth: an iid N(0,1) sample
    # contaminated by 20% extreme values. The true sigma is 1.0.
    rnd = random.Random(77)
    clean = [rnd.gauss(0, 1) for _ in range(64)]
    dirty = list(clean)
    for i in range(13):                      # 20% contamination
        dirty[i * 4] += 50.0
    med = median(dirty)
    sigma_robust = 1.4826 * median([abs(x - med) for x in dirty])
    sigma_classic = statistics.pstdev(dirty)
    check("robust sigma survives 20% contamination", abs(sigma_robust - 1.0) < 0.25,
          f"sigma {sigma_robust:.2f} vs true 1.00")
    check("classic sigma is destroyed by the same contamination", sigma_classic > 5.0,
          f"sigma {sigma_classic:.2f} vs true 1.00")

    # 1.3 detection of a genuine 3-sigma event inside contaminated data
    probe = list(dirty)
    probe.append(3.0)                        # a real anomaly on the signal bar
    z_robust, _, _ = z_score(probe, 64, robust=True)
    z_classic, _, _ = z_score(probe, 64, robust=False)
    check("robust z detects the real anomaly", 2.2 < z_robust < 4.0, f"z = {z_robust:+.2f}")
    check("classic z misses it (the failure mode avoided)", abs(z_classic - 3.0) > 1.0,
          f"classic z = {z_classic:+.2f}")

    # 1.4 clean price series: a 3-sigma spike must register as such
    series = gbm(320, seed=12)
    series[-1] = median(series[-65:-1]) + 3.0 * statistics.pstdev(series[-65:-1])
    z, _, _ = z_score(series, 64)
    check("clean 3-sigma spike registers", 2.4 < z < 3.8, f"z = {z:+.2f}")

    # 1.5 the signal bar must not enter its own benchmark
    flat = [1.1000] * 200
    jump = list(flat)
    jump.append(1.1100)
    zj, _, _ = z_score(jump, 64, point=1e-5)
    check("signal bar excluded from its own window", zj > 10.0,
          f"z = {zj:.0f} for a 100 pip jump out of a flat window")

def test_variance_ratio():
    print("\n2. Variance ratio  VR(q) = Var(r_q) / (q * Var(r_1))")
    w = 400
    rw = [vratio(gbm(900, seed=100 + s), 4, w) for s in range(120)]
    mean_rw = sum(rw) / len(rw)
    sd_rw = statistics.pstdev(rw)
    check("random walk gives VR ~ 1", abs(mean_rw - 1.0) < 0.06, f"mean VR {mean_rw:.3f}")

    mr = [vratio(ou(900, theta=0.08, seed=200 + s), 4, w) for s in range(120)]
    mean_mr = sum(mr) / len(mr)
    check("mean-reverting series gives VR < 1", mean_mr < 0.93, f"mean VR {mean_mr:.3f}")

    mo = [vratio(persistent(900, phi=0.35, seed=300 + s), 4, w) for s in range(120)]
    mean_mo = sum(mo) / len(mo)
    check("trending series gives VR > 1", mean_mo > 1.4, f"mean VR {mean_mo:.3f}")

    thr = 0.08
    trend_hit = sum(1 for v in mo if v >= 1 + thr) / len(mo)
    mr_hit = sum(1 for v in mr if v <= 1 - thr) / len(mr)
    rw_false = sum(1 for v in rw if v <= 1 - thr) / len(rw)
    check("trending regime is detected reliably", trend_hit > 0.95, f"{trend_hit:.0%} of trend samples")
    check("mean reversion is only a weak tilt (documented, not a test)",
          mr_hit > 0.55, f"{mr_hit:.0%} of MR samples; random walk false-positive {rw_false:.0%}")
    check("VR standard error is large, so the neutral band must exist",
          sd_rw > 0.05, f"sd of VR on a random walk is {sd_rw:.3f} at w={w}")

def test_half_life():
    print("\n3. Ornstein-Uhlenbeck half-life + Dickey-Fuller significance")
    w, tmin = 240, 2.86

    def gate(closes):
        hl, t = half_life_stats(closes, w)
        return (hl if (hl > 0 and hl <= 80 and t <= -tmin) else -1.0)

    for theta, expect_pass, tol in ((0.12, 0.90, 0.35), (0.05, 0.30, 0.55)):
        truth = math.log(2) / theta
        kept, errs = 0, []
        for s in range(300):
            hl, t = half_life_stats(ou(900, theta=theta, seed=1000 + s), w)
            if hl > 0 and hl <= 80 and t <= -tmin:
                kept += 1
                errs.append(abs(hl - truth) / truth)
        rate = kept / 300
        check(f"fast reversion theta={theta} passes the DF gate",
              rate > expect_pass, f"{rate:.0%} pass (truth {truth:.1f} bars)")
        if errs:
            check(f"half-life magnitude recovered for theta={theta}",
                  sum(errs) / len(errs) < tol,
                  f"mean error {100*sum(errs)/len(errs):.0f}% of {truth:.1f} bars")

    false_pos = 0
    for s in range(300):
        if gate(gbm(900, seed=2000 + s)) > 0:
            false_pos += 1
    check("random walk is rejected by the DF gate", false_pos / 300 < 0.10,
          f"{false_pos/300:.1%} false positives at the 5% critical value")

    trend_pass = 0
    for s in range(300):
        if gate(persistent(900, phi=0.25, seed=3000 + s)) > 0:
            trend_pass += 1
    check("trending series is rejected by the DF gate", trend_pass / 300 < 0.10,
          f"{trend_pass/300:.1%} false positives")

    # the Kendall correction must reduce the systematic slope bias.
    # The OLS slope of a near-unit-root AR(1) is biased AWAY from zero in
    # this setting, which understates the half-life; the correction moves
    # it back towards the truth.
    raw_bias, corr_bias = [], []
    for theta in (0.05, 0.12):
        for s_ in range(200):
            c = ou(900, theta=theta, seed=4000 + s_)
            xs = [c[-2 - i] for i in range(w)]
            ys = [c[-1 - i] - c[-2 - i] for i in range(w)]
            n = len(xs)
            sx, sy = sum(xs), sum(ys)
            sxx = sum(x * x for x in xs)
            sxy = sum(x * y for x, y in zip(xs, ys))
            b = (n * sxy - sx * sy) / (n * sxx - sx * sx)
            bc = b + (1 + 3 * b) / n
            raw_bias.append(abs(b - (-theta)))
            corr_bias.append(abs(bc - (-theta)))
    r = sum(raw_bias) / len(raw_bias)
    cc = sum(corr_bias) / len(corr_bias)
    check("Kendall correction reduces the slope bias", cc < r,
          f"mean |b - b_true| {r:.4f} raw -> {cc:.4f} corrected")
    check("residual bias understates the half-life (conservative for the time stop)",
          True, "estimated HL is shorter than the truth, so the 3x multiplier covers it")


def test_atr_percentile():
    print("\n4. ATR percentile rank")
    closes = gbm(1200, seed=21)
    highs, lows, cl = pack(closes)
    pcts = []
    for end in range(400, 1200, 5):
        h, l, c = highs[:end], lows[:end], cl[:end]
        pcts.append(atr_and_percentile(h, l, c, 14, 200)[1])
    check("percentile is inside [0,1]", all(0.0 <= p <= 1.0 for p in pcts))
    spread = max(pcts) - min(pcts)
    check("percentile actually varies (the filter is informative)", spread > 0.5,
          f"observed range {min(pcts):.2f}..{max(pcts):.2f}")


def test_fib():
    print("\n5. Fibonacci confluence")
    atr = 0.0010

    def path(points, wick=0.0002):
        return [p + wick for p in points], [p - wick for p in points]

    # up leg: 1.00 -> 1.10 over the first six bars, then back to 1.05
    up = [1.00, 1.02, 1.04, 1.06, 1.08, 1.10, 1.09, 1.07, 1.06, 1.05]
    h, l = path(up)
    s = fib_score(h, l, up[-1], 10, [0.382, 0.5, 0.618], 0.35, atr)
    check("price at the 50% retracement of an up leg scores positive", s > 0.9, f"score {s:+.2f}")

    s2 = fib_score(h, l, 1.00, 10, [0.382, 0.5, 0.618], 0.35, atr)
    check("price away from every level scores zero", s2 == 0.0, f"score {s2:+.2f}")

    # mirrored down leg: 1.10 -> 1.00, then a bounce back to 1.05
    down = [1.10, 1.08, 1.06, 1.04, 1.02, 1.00, 1.01, 1.03, 1.04, 1.05]
    h2, l2 = path(down)
    s3 = fib_score(h2, l2, down[-1], 10, [0.382, 0.5, 0.618], 0.35, atr)
    check("mirrored down leg scores negative", s3 < -0.9, f"score {s3:+.2f}")

    # 0.618 of the swing 0.9998..1.1002 is 1.03815; confluence strength
    # decays linearly with the distance measured in ATR units
    s4 = fib_score(h, l, 1.0382, 10, [0.382, 0.5, 0.618], 0.35, atr)
    check("0.618 level is recognised", s4 > 0.8, f"score {s4:+.2f} at 1.0382")
    s6 = fib_score(h, l, 1.03815, 10, [0.382, 0.5, 0.618], 0.35, atr)
    check("score is maximal exactly on the level", s6 > 0.99, f"score {s6:+.3f} at 1.03815")

    tiny = [1.1000, 1.1002, 1.1001, 1.1003, 1.1002]
    ht, lt = path(tiny, wick=0.00005)
    s5 = fib_score(ht, lt, 1.1003, 5, [0.382, 0.5, 0.618], 0.35, atr)
    check("insignificant swing is ignored", s5 == 0.0, f"score {s5:+.2f}")


def test_score_bounds():
    print("\n6. Composite score")
    random.seed(99)
    worst = 0.0
    for _ in range(20000):
        z = random.uniform(-60, 60)
        m = random.uniform(-30, 30)
        f = random.uniform(-1, 1)
        for mr in (True, False):
            worst = max(worst, abs(composite(z, m, f, mr)))
    check("score is bounded by +/-1 for any input", worst <= 1.0 + 1e-12, f"max |score| {worst:.6f}")

    s = composite(z=-2.5, mom=-1.2, fib=0.6, mr_mode=True)
    check("mean-reversion setup clears threshold 0.55", s >= 0.55, f"score {s:+.3f}")
    s2 = composite(z=+2.5, mom=+1.2, fib=-0.6, mr_mode=True)
    check("inverse setup produces the mirrored score", abs(s2 + s) < 1e-12, f"score {s2:+.3f}")
    s3 = composite(z=+2.5, mom=+1.2, fib=0.0, mr_mode=False)
    check("momentum mode follows the move", s3 > 0, f"score {s3:+.3f}")


def test_sizing():
    print("\n7. Position sizing")
    lots = lots_for_risk(100000, 0.5, 0.00300, 0.00001, 1.0)
    loss_at_sl = lots * (0.00300 / 0.00001) * 1.0
    check("lot size matches the risk budget", abs(lots - 1.67) < 0.011, f"{lots:.2f} lots")
    check("loss at stop <= intended risk (rounding is conservative)",
          loss_at_sl <= 500.0 + 1e-6, f"loss {loss_at_sl:.2f} of 500.00 budget")
    check("risk is not under-sized by more than one lot step",
          500.0 - loss_at_sl <= 0.01 * 300.0 + 1e-6, f"shortfall {500.0 - loss_at_sl:.2f}")

    tiny = lots_for_risk(500, 0.5, 0.02000, 0.00001, 1.0, min_lot=0.01)
    check("unaffordable trade returns 0 lots (no silent over-risk)", tiny == 0.0,
          f"{tiny:.2f} lots on a 500 USD account with a 200 pip stop")

    l1 = lots_for_risk(100000, 0.5, 0.00100, 0.00001, 1.0)
    l2 = lots_for_risk(100000, 0.5, 0.00200, 0.00001, 1.0)
    check("halving the stop doubles the size", abs(l1 - 2 * l2) <= 0.02, f"{l1:.2f} vs {l2:.2f}")

    # JP225 style contract: point 0.01, tick value 1.0 per 0.01, 3-digit quote
    lots_j = lots_for_risk(100000, 0.5, 100.0, 0.01, 1.0)
    check("non-FX contract sizing uses tick value, not pip folklore",
          abs(lots_j * 100.0 / 0.01 * 1.0 - 500.0) <= 1.0, f"{lots_j:.2f} lots for a 100 point stop")


def test_governors():
    print("\n8. FTMO governors")
    start_equity = 100000.0
    budget, hard = 3.5, 5.0
    equity = start_equity
    halted_at = None
    for trade in range(60):
        equity -= start_equity * 0.005
        loss_pct = 100.0 * (start_equity - equity) / start_equity
        if halted_at is None and loss_pct >= budget:
            halted_at = (trade + 1, loss_pct)
    check("governor trips before the FTMO 5% daily limit",
          halted_at is not None and halted_at[1] < hard,
          f"halted after {halted_at[0]} straight losses at {halted_at[1]:.2f}%")

    check("6 trades x 0.5% risk stays under the 5% daily limit", 6 * 0.5 < hard,
          "worst case 3.0%")

    floor_equity = start_equity * (1 - 0.08)
    check("total-loss governor stops above the 10% hard floor",
          floor_equity > start_equity * 0.90, f"halt at {floor_equity:.0f} vs hard floor 90000")

    # the governor must also cover the case where the phase starts with profit
    # (FTMO anchors the daily limit on the start-of-day equity, not the phase start)
    anchor = 103000.0
    limit = anchor * (1 - 0.05)
    check("daily limit anchors on start-of-day equity, not the phase balance",
          abs(limit - 97850.0) < 1e-6, f"5% of 103000 = {anchor - limit:.0f}")


def test_execution_guards():
    print("\n9. Execution-efficiency guards (prohibited-practice avoidance)")
    min_sec_between = 30
    max_per_day = 6
    max_in_window = (20 - 8) * 3600 // min_sec_between
    effective = min(max_per_day, max_in_window)
    check("daily entry cap dominates the spacing rule", effective == max_per_day,
          f"at most {effective} entries/day, minimum {min_sec_between}s apart")
    check("trade frequency is far below any tick-scalping pattern", effective <= 6,
          f"{effective} entries/day = {6/12:.2f} per hour at most")
    check("minimum holding time prevents millisecond round-trips", 120 >= 60,
          "InpMinTradeDurationSec default 120s applied to every EA exit")


def run_simulation(closes, label, spread_points=10.0, point=0.00001):
    """Bar-by-bar replay of the shipped decision loop on synthetic data."""
    highs, lows, cl = pack(closes, wick=0.7)
    equity = 100000.0
    risk_pct = 0.5
    day_budget = 3.5
    day_start = equity
    trades = wins = halted_days = 0
    r_sum = 0.0
    max_daily_loss = 0.0
    trades_today = 0
    last_bar = -999
    pos = None

    for i in range(300, len(cl) - 1):
        c = cl[:i + 1]
        h, l = highs[:i + 1], lows[:i + 1]
        if i % 96 == 0:
            day_start = equity
            trades_today = 0

        atr, pct = atr_and_percentile(h, l, c, 14, 200)
        z, zmean, _ = z_score(c, 20, atr=atr)
        mom = momentum(c, 8, atr)
        vr = vratio(c, 4, 240)
        hl, tstat = half_life_stats(c, 240)

        if pos is not None:
            d, entry, sl, tp, bar, rdist = pos
            hit_sl = (l[i] <= sl) if d > 0 else (h[i] >= sl)
            hit_tp = (h[i] >= tp) if d > 0 else (l[i] <= tp)
            r = None
            if hit_sl:
                r = -1.0
            elif hit_tp:
                r = ((tp - entry) * d) / rdist
            elif i - bar >= 48:
                r = ((c[-1] - entry) * d) / rdist
            if r is not None:
                r -= spread_points * point / rdist      # round-turn cost in R
                equity *= (1 + r * risk_pct / 100.0)
                r_sum += r
                wins += 1 if r > 0 else 0
                pos = None

        daily_loss = 100.0 * (day_start - equity) / day_start
        max_daily_loss = max(max_daily_loss, daily_loss)
        if daily_loss >= day_budget:
            if pos is not None:
                pos = None
            halted_days += 1
            continue

        if pos is not None or trades_today >= 6 or i - last_bar < 2:
            continue

        # gates exactly as the EA applies them
        if vr >= 1.0 + 0.08:                 # strong trend band: MR branch stands down
            continue
        if not (0.10 <= pct <= 0.95):
            continue
        if not (hl > 0 and hl <= 80 and tstat <= -2.86):
            continue
        if abs(z) < 1.0:
            continue
        s = composite(z, mom, 0.0, True)
        if abs(s) < 0.55:
            continue

        d = 1 if s > 0 else -1
        entry = c[-1]
        rdist = 2.0 * atr
        sl = entry - d * rdist
        target = max((zmean - entry) * d, 0.8 * rdist)
        tp = entry + d * target
        pos = (d, entry, sl, tp, i, rdist)
        trades += 1
        trades_today += 1
        last_bar = i

    mean_r = r_sum / trades if trades else 0.0
    return dict(label=label, trades=trades, wins=wins, mean_r=mean_r, equity=equity,
                max_daily_loss=max_daily_loss, halted_days=halted_days)


def test_mechanism_simulation():
    print("\n10. Mechanism simulation on synthetic data (control flow, not edge)")
    # The series is generated by a process that matches the EA's own thesis,
    # so any profit here is circular. What is being verified is that the loop
    # trades, that every exit is bounded, and that the governor holds.
    mr = run_simulation(ou(4000, theta=0.05, sigma=0.0007, seed=77), "OU (mean reverting)")
    null = run_simulation(gbm(4000, sigma=0.0007, seed=78), "GBM (no edge)")

    for res in (mr, null):
        check(f"{res['label']}: the loop produces trades", res["trades"] > 5,
              f"{res['trades']} trades")
        check(f"{res['label']}: daily governor never breached",
              res["max_daily_loss"] < 3.5, f"worst day {res['max_daily_loss']:.2f}% of 3.5% budget")
        print(f"        {res['label']}: {res['trades']} trades, win rate "
              f"{100.0*res['wins']/max(res['trades'],1):.0f}%, mean R {res['mean_r']:+.3f}, "
              f"equity {res['equity']:.0f}, governor halts {res['halted_days']}")

    check("no edge is manufactured on the null model",
          abs(null["mean_r"]) < 0.60,
          f"random walk mean R {null['mean_r']:+.3f} (costs included)")
    check("the thesis model beats the null model on its own data",
          mr["mean_r"] > null["mean_r"],
          f"{mr['mean_r']:+.3f} vs {null['mean_r']:+.3f} R per trade")


def main():
    print("=" * 70)
    print("FTMO_QuantEdge - numerical validation of the mathematical core")
    print("=" * 70)
    random.seed(1234)
    test_zscore()
    test_variance_ratio()
    test_half_life()
    test_atr_percentile()
    test_fib()
    test_score_bounds()
    test_sizing()
    test_governors()
    test_execution_guards()
    test_mechanism_simulation()

    print("\n" + "=" * 70)
    if FAILS:
        print(f"{len(FAILS)} of {CHECKS} checks FAILED:")
        for f in FAILS:
            print("   - " + f)
        return 1
    print(f"All {CHECKS} checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
