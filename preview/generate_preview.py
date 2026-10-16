#!/usr/bin/env python3
"""
Independent re-implementation of the Pine v6 indicator logic (fib_hh_ll_signals.pine)
on synthetic candles.  It is used to check that the 0.755/0.766/0.788 → TP 0.33 / SL 0.98
plan arms, fills and exits where the levels say it should, and to render a preview
of what the indicator looks like on a chart (see fib_preview.html).

Pure standard library, no dependencies:  python3 preview/generate_preview.py
"""
import html
import random

# ── inputs (mirror of the Pine defaults) ────────────────────────────────────────
PIV_L, PIV_R = 5, 5
E1, E2, E3 = 0.755, 0.766, 0.788
TP, SL = 0.33, 0.98
NEED_STRUCT = True
MAX_LEG, MAX_WAIT, LADDER = 150, 120, 10
FLIP = False

C_E1, C_E2, C_E3 = "#00BCD4", "#26C6DA", "#4DD0E1"
C_TP, C_SL = "#2962FF", "#F23645"
UP, DOWN = "#26A69A", "#EF5350"


def fib_px(r, hi, lo, up):
    """Same formula as fibPx() in the Pine script."""
    span = hi - lo
    if FLIP:
        return lo + r * span if up else hi - r * span
    return hi - r * span if up else lo + r * span


# ── synthetic market: impulse legs, retracement into the zone, expansion ────────
def make_candles(seed=7):
    random.seed(seed)
    # (target price at bar, number of bars) — hand-shaped so the plan is exercised
    path = [
        (100.0, 10), (98.0, 5), (101.5, 8), (104.0, 4), (101.0, 6),
        (100.5, 4), (105.0, 8), (110.0, 8), (107.5, 6), (102.0, 9),
        (103.5, 4), (106.9, 8), (108.5, 6),
    ]
    closes, i = [], 0
    for target, n in path:
        start = closes[-1] if closes else target
        for k in range(1, n + 1):
            closes.append(start + (target - start) * (k / n) + random.gauss(0, 0.22))
    out = []
    prev = 100.0
    for c in closes:
        o = prev + random.gauss(0, 0.12)
        wick_up, wick_dn = abs(random.gauss(0, 0.28)), abs(random.gauss(0, 0.28))
        h = max(o, c) + wick_up
        l = min(o, c) - wick_dn
        out.append({"o": o, "h": h, "l": l, "c": c})
        prev = c
    return out


def pivots(cdl, kind):
    """ta.pivothigh / ta.pivotlow equivalent: value + confirmation bar."""
    key = "h" if kind == "high" else "l"
    res = {}
    for i in range(len(cdl)):
        p = i - PIV_R
        if p - PIV_L < 0:
            continue
        v = cdl[p][key]
        left = [cdl[j][key] for j in range(p - PIV_L, p)]
        right = [cdl[j][key] for j in range(p + 1, p + 1 + PIV_R)]
        if kind == "high":
            ok = all(v > x for x in left) and all(v > x for x in right)
        else:
            ok = all(v < x for x in left) and all(v < x for x in right)
        if ok:
            res[i] = (p, v)
    return res


def run(cdl):
    """Mirror of sections ⑤ ⑥ ⑦ of the Pine script."""
    ph, pl = pivots(cdl, "high"), pivots(cdl, "low")
    st = {k: 0 for k in ("dir", "stat", "hiB", "loB", "armB", "tapB", "fills")}
    st.update(hi=0.0, lo=0.0, ext=0.0, avg=0.0, rr=0.0)
    hist = []
    ph1 = ph2 = pl1 = pl2 = 0.0
    nPH = nPL = 0
    events, fib = [], None

    for i, b in enumerate(cdl):
        bar = {"i": i, **b}
        # swings
        if i in ph:
            p, v = ph[i]
            ph2, ph1, ph1B_prev = ph1, v, st["hiB"]
            st["hiB"] = p
            nPH += 1
        if i in pl:
            p, v = pl[i]
            pl2, pl1 = pl1, v
            st["loB"] = p
            nPL += 1
        bull = nPH > 1 and nPL > 1 and ph1 > ph2 and pl1 > pl2
        bear = nPH > 1 and nPL > 1 and ph1 < ph2 and pl1 < pl2
        armL = (i in ph) and ph1 > pl1 and st["hiB"] > st["loB"] and (i - min(st["hiB"], st["loB"])) <= MAX_LEG and (bull or not NEED_STRUCT)
        armS = (i in pl) and ph1 > pl1 and st["loB"] > st["hiB"] and (i - min(st["hiB"], st["loB"])) <= MAX_LEG and (bear or not NEED_STRUCT)
        same = (armL and st["dir"] == 1 and st["hi"] == ph1 and st["lo"] == pl1) or (armS and st["dir"] == -1 and st["hi"] == ph1 and st["lo"] == pl1)
        if (armL or armS) and not same:
            st.update(dir=1 if armL else -1, hi=ph1, lo=pl1, stat=1, tapB=0, fills=0, avg=0.0, rr=0.0)
            st["ext"] = st["hi"] if armL else st["lo"]
            fib = {"xL": min(st["loB"], st["hiB"]), "hi": ph1, "lo": pl1, "dir": st["dir"], "arm": i}
            events.append((i, "armed", "LONG" if armL else "SHORT"))
        up = st["dir"] == 1
        e1 = fib_px(E1, st["hi"], st["lo"], up)
        e2 = fib_px(E2, st["hi"], st["lo"], up)
        e3 = fib_px(E3, st["hi"], st["lo"], up)
        sl_px = fib_px(SL, st["hi"], st["lo"], up)
        tp_px = fib_px(TP, st["hi"], st["lo"], up)
        ztop, zbot = max(e1, e2, e3), min(e1, e2, e3)
        # 1 · touch
        tapL = st["stat"] == 1 and up and b["l"] <= ztop
        tapS = st["stat"] == 1 and not up and b["h"] >= zbot
        if tapL or tapS:
            st.update(stat=2, tapB=i, ext=b["l"] if tapL else b["h"])
            events.append((i, "entry", "LONG" if tapL else "SHORT"))
            bar["entry_price"] = ztop if tapL else zbot
        # 2 · ladder
        if st["stat"] == 2 and (i - st["tapB"]) <= LADDER:
            st["ext"] = min(st["ext"], b["l"]) if up else max(st["ext"], b["h"])
        # 3 · fills
        fs = []
        for px in (e1, e2, e3):
            fs.append(px >= st["ext"] if up else px <= st["ext"])
        if st["stat"] == 2:
            st["fills"] = sum(fs)
            s = sum(px for px, f in zip((e1, e2, e3), fs) if f)
            st["avg"] = s / st["fills"] if st["fills"] else (ztop if up else zbot)
            risk = abs(st["avg"] - sl_px)
            rew = abs(tp_px - st["avg"])
            st["rr"] = rew / risk if risk > 0 else st["rr"]
        # 4 · exits (stop wins inside one candle)
        hit_tp = st["stat"] == 2 and (b["h"] >= tp_px if up else b["l"] <= tp_px)
        hit_sl = st["stat"] == 2 and (b["l"] <= sl_px if up else b["h"] >= sl_px)
        if st["stat"] == 2:
            if hit_sl:
                st["stat"], ev = 4, "SL"
            elif hit_tp:
                st["stat"], ev = 3, "TP"
            else:
                ev = None
            if ev:
                events.append((i, ev, str(st["fills"]) + "/3"))
        # 5 · expiry
        if st["stat"] == 1 and ((i - st["armB_eff"] if False else (i - fib["arm"])) > MAX_WAIT or (b["l"] <= sl_px if up else b["h"] >= sl_px)):
            st["stat"] = 5
            events.append((i, "cancelled", ""))
        hist.append({"st": dict(st), "e1": e1, "e2": e2, "e3": e3, "sl": sl_px, "tp": tp_px, "fib": dict(fib) if fib else None})
    return hist, events


# ── rendering ──────────────────────────────────────────────────────────────────
W, H, PAD_L, PAD_R, PAD_T, PAD_B = 1280, 660, 24, 190, 26, 46


def render(cdl, hist, events):
    lo = min(b["l"] for b in cdl) - 0.6
    hi = max(b["h"] for b in cdl) + 0.6
    n = len(cdl)
    cw = (W - PAD_L - PAD_R) / (n + 6)

    def X(i):
        return PAD_L + (i + 3) * cw

    def Y(p):
        return PAD_T + (hi - p) / (hi - lo) * (H - PAD_T - PAD_B)

    last = hist[-1]
    fib = last["fib"]
    s = [f'<svg viewBox="0 0 {W} {H}" width="100%" preserveAspectRatio="xMidYMid meet" style="font-family:\'Trebuchet MS\',system-ui,sans-serif">']
    s.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#131722"/>')
    # grid
    import math
    step = math.pow(10, math.floor(math.log10((hi - lo) / 6)))
    g = round((hi - lo) / 6 / step) * step
    p = math.ceil(lo / g) * g
    while p < hi:
        y = Y(p)
        s.append(f'<line x1="{PAD_L}" y1="{y:.1f}" x2="{W-PAD_R}" y2="{y:.1f}" stroke="#1e222d" stroke-width="1"/>')
        s.append(f'<text x="{W-PAD_R+8}" y="{y+4:.1f}" fill="#787B86" font-size="11">{p:,.3f}</text>')
        p += g
    # fib span + entry zone
    if fib:
        xL, xR = X(fib["xL"]), X(n - 1)
        if last["e1"] is not None:
            s.append(f'<rect x="{xL:.1f}" y="{Y(max(last["e1"],last["e2"],last["e3"])):.1f}" width="{xR-xL:.1f}" height="{abs(Y(min(last["e1"],last["e2"],last["e3"]))-Y(max(last["e1"],last["e2"],last["e3"]))):.1f}" fill="#00BCD4" opacity="0.12"/>')
            s.append(f'<rect x="{xL:.1f}" y="{Y(fib["hi"]):.1f}" width="{xR-xL:.1f}" height="{abs(Y(fib["lo"])-Y(fib["hi"])):.1f}" fill="none" stroke="#2a2e39" stroke-width="1"/>')
    # candles
    for i, b in enumerate(cdl):
        x = X(i)
        col = UP if b["c"] >= b["o"] else DOWN
        s.append(f'<line x1="{x:.1f}" y1="{Y(b["h"]):.1f}" x2="{x:.1f}" y2="{Y(b["l"]):.1f}" stroke="{col}" stroke-width="1.1"/>')
        y1, y2 = Y(max(b["o"], b["c"])), Y(min(b["o"], b["c"]))
        s.append(f'<rect x="{x-cw*0.32:.1f}" y="{y1:.1f}" width="{cw*0.64:.1f}" height="{max(y2-y1,1):.1f}" fill="{col}"/>')
    # fib lines + labels
    if fib:
        levels = [(last["e1"], "0.755", "E1", C_E1), (last["e2"], "0.766", "E2", C_E2), (last["e3"], "0.788", "E3", C_E3),
                  (last["sl"], "0.98", "SL", C_SL), (last["tp"], "0.33", "TP", C_TP),
                  (fib["hi"], "0", "", "#787B86"), (fib["lo"], "1", "", "#787B86")]
        for px, nm, tg, col in levels:
            y = Y(px)
            s.append(f'<line x1="{xL:.1f}" y1="{y:.1f}" x2="{xR:.1f}" y2="{y:.1f}" stroke="{col}" stroke-width="{1.9 if tg else 1}" opacity="{0.95 if tg else 0.5}"/>')
            txt = f'{nm}' + (f'   {tg}' if tg else '')
            s.append(f'<rect x="{xR+3:.1f}" y="{y-9:.1f}" width="126" height="18" rx="3" fill="#131722" stroke="{col}" stroke-width="1"/>')
            s.append(f'<text x="{xR+7:.1f}" y="{y+4:.1f}" fill="{col}" font-size="11">{txt}</text>')
    # event markers
    for i, kind, tag in events:
        x = X(i)
        if kind in ("entry",):
            y = Y(cdl[i]["l"]) + 16
            s.append(f'<path d="M{x:.1f},{y-11:.1f} l6,9 l-12,0 z" fill="{C_E1}"/>')
            s.append(f'<text x="{x:.1f}" y="{y+22:.1f}" fill="{C_E1}" font-size="11" text-anchor="middle">{tag} entry</text>')
        elif kind in ("TP", "SL"):
            col = C_TP if kind == "TP" else C_SL
            y = Y(cdl[i]["h"]) - 20 if kind == "TP" else Y(cdl[i]["l"]) + 20
            s.append(f'<text x="{x:.1f}" y="{y:.1f}" fill="{col}" font-size="12" font-weight="bold" text-anchor="middle">{kind}</text>')
        elif kind == "cancelled":
            s.append(f'<text x="{x:.1f}" y="{Y(cdl[i]["h"])-8:.1f}" fill="#787B86" font-size="10" text-anchor="middle">cancelled</text>')
    # title
    s.append(f'<text x="{PAD_L}" y="18" fill="#D1D4DC" font-size="13" font-weight="bold">Fib HH/LL preview — synthetic data, same logic as the Pine script</text>')
    s.append("</svg>")
    return "\n".join(s), last


def dashboard(last):
    st = last["st"]
    status = {0: "NO SETUP", 1: "WAITING FOR ENTRY", 2: "IN TRADE", 3: "TP HIT", 4: "SL HIT", 5: "SETUP CANCELLED"}[st["stat"]]
    col = {3: C_TP, 4: C_SL, 2: C_E1}.get(st["stat"], "#B2B5BE")
    rows = [
        ("Leg", f'{last["fib"]["lo"]:.3f}  →  {last["fib"]["hi"]:.3f}'),
        ("Entries", f'{last["e1"]:.3f} · {last["e2"]:.3f} · {last["e3"]:.3f}'),
        ("Stop / Target", f'{last["sl"]:.3f}  (0.98)   |   {last["tp"]:.3f}  (0.33)'),
        ("Filled", f'{st["fills"]} / 3   ·   avg {st["avg"]:.3f}'),
        ("Reward : Risk", f'{st["rr"]:.2f} R'),
        ("Status", status),
    ]
    head = "FIB PLAN   " + ("LONG" if st["dir"] == 1 else "SHORT")
    body = "".join(
        f'<div class="row"><span>{k}</span><span style="color:{col if k=="Status" else "#B2B5BE"}">{html.escape(v)}</span></div>'
        for k, v in rows)
    return f'<div class="dash"><div class="dashhead" style="color:{C_E1 if st["dir"]==1 else C_SL}">{head}</div>{body}</div>'


def main():
    cdl = make_candles()
    hist, events = run(cdl)
    svg, last = render(cdl, hist, events)
    st = last["st"]
    print("events:", events)
    print(f"status={st['stat']} dir={st['dir']} fills={st['fills']} avg={st['avg']:.3f} rr={st['rr']:.2f}")
    print(f"levels: e1={last['e1']:.3f} e2={last['e2']:.3f} e3={last['e3']:.3f} sl={last['sl']:.3f} tp={last['tp']:.3f}")
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Fib HH/LL — indicator preview</title>
<style>
  body{{margin:0;background:#0b0e14;color:#D1D4DC;font-family:'Trebuchet MS',system-ui,sans-serif}}
  .wrap{{max-width:1340px;margin:0 auto;padding:14px}}
  h1{{font-size:17px;margin:6px 0 2px}} p.sub{{margin:0 0 12px;color:#787B86;font-size:13px}}
  .chart{{position:relative;border:1px solid #2a2e39;border-radius:8px;overflow:hidden;background:#131722}}
  .dash{{position:absolute;top:12px;left:12px;background:rgba(19,23,34,.94);border:1px solid #363a45;border-radius:6px;
        font-size:11.5px;min-width:296px;box-shadow:0 2px 10px #0008}}
  .dashhead{{padding:5px 9px;font-weight:bold;border-bottom:1px solid #363a45;letter-spacing:.4px}}
  .row{{display:flex;justify-content:space-between;gap:14px;padding:3px 9px}}
  .row span:first-child{{color:#fff}}
  .legend{{display:flex;flex-wrap:wrap;gap:12px;margin:10px 2px;font-size:12px;color:#B2B5BE}}
  .dot{{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:5px;vertical-align:-1px}}
</style></head><body><div class="wrap">
<h1>Fib HH/LL · 0.755 / 0.766 / 0.788 entries — TP 0.33 — SL 0.98</h1>
<p class="sub">Rendered from the same level maths the Pine script uses (synthetic candles). Structure: HH + HL → long, LL + LH → short.</p>
<div class="chart">{svg}{dashboard(last)}</div>
<div class="legend">
  <span><i class="dot" style="background:{C_E1}"></i>0.755 / 0.766 / 0.788 — entries</span>
  <span><i class="dot" style="background:{C_TP}"></i>0.33 — take profit</span>
  <span><i class="dot" style="background:{C_SL}"></i>0.98 — stop loss</span>
  <span><i class="dot" style="background:#787B86"></i>0 / 1 — leg anchors (off by default)</span>
</div></div></body></html>
"""
    with open("preview/fib_preview.html", "w") as f:
        f.write(page)
    with open("preview/fib_preview.svg", "w") as f:
        f.write(svg.replace('<svg viewBox', '<svg xmlns="http://www.w3.org/2000/svg" viewBox', 1))
    print("wrote preview/fib_preview.html and preview/fib_preview.svg")


if __name__ == "__main__":
    main()
