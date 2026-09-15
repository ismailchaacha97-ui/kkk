#!/usr/bin/env python3
"""Generate annotated CHOCH + Gann-box schematic (SVG) and full HTML report.
All prices/times are readings taken from the user's EURUSD,M5 screenshot
(broker server time, 15 Sep 2026)."""

PLO, PHI = 1.15190, 1.15545          # price window of schematic
SPAN = PHI - PLO

BG="#131722"; PANEL="#0d0f14"; GRID="#232733"; TXT="#d1d4dc"; MUT="#8b909f"
BULL="#f2994a"; BEAR="#7b8494"; CYAN="#26c6da"; PURPLE="#b39ddb"
RED="#ef5350"; GREEN="#22c55e"; GOLD="#ffd54f"

# ---------------------------------------------------------------- zoom candles
# (time, open, high, low, close)  07:30 -> 11:10, illustrative reconstruction
Z = [
 ("07:30",1.15285,1.15300,1.15278,1.15295),
 ("07:35",1.15295,1.15315,1.15290,1.15310),
 ("07:40",1.15310,1.15325,1.15302,1.15318),
 ("07:45",1.15318,1.15335,1.15312,1.15330),
 ("07:50",1.15330,1.15345,1.15325,1.15340),   # LH pivot  (break level)
 ("07:55",1.15340,1.15342,1.15322,1.15328),
 ("08:00",1.15328,1.15335,1.15315,1.15320),
 ("08:05",1.15320,1.15328,1.15305,1.15310),
 ("08:10",1.15310,1.15320,1.15298,1.15305),
 ("08:15",1.15305,1.15315,1.15292,1.15298),
 ("08:20",1.15298,1.15308,1.15285,1.15292),
 ("08:25",1.15292,1.15302,1.15280,1.15286),
 ("08:30",1.15286,1.15295,1.15272,1.15278),
 ("08:35",1.15278,1.15285,1.15258,1.15262),
 ("08:40",1.15262,1.15268,1.15245,1.15250),
 ("08:45",1.15250,1.15255,1.15230,1.15235),
 ("08:50",1.15235,1.15242,1.15215,1.15220),
 ("08:55",1.15220,1.15228,1.15205,1.15212),   # SWING LOW (box anchor 2)
 ("09:00",1.15212,1.15245,1.15208,1.15240),
 ("09:05",1.15240,1.15268,1.15235,1.15262),
 ("09:10",1.15262,1.15288,1.15258,1.15284),
 ("09:15",1.15284,1.15310,1.15280,1.15306),
 ("09:20",1.15306,1.15328,1.15300,1.15324),
 ("09:25",1.15324,1.15338,1.15318,1.15334),
 ("09:30",1.15334,1.15344,1.15326,1.15338),   # last retest of LH, holds below
 ("09:35",1.15338,1.15375,1.15332,1.15370),   # CHOCH candle (close > 1.15345)
 ("09:40",1.15370,1.15395,1.15362,1.15390),   # confirmation
 ("09:45",1.15390,1.15400,1.15380,1.15395),   # post-CHOCH swing high ~ 0.382/37.5%
 ("09:50",1.15395,1.15400,1.15385,1.15388),
 ("09:55",1.15388,1.15390,1.15372,1.15375),   # pullback begins (stays above 0.5)
 ("10:00",1.15375,1.15378,1.15355,1.15360),   # FIRST TOUCH of 0.5 -> BUY signal
 ("10:05",1.15360,1.15365,1.15348,1.15352),
 ("10:10",1.15352,1.15358,1.15335,1.15340),
 ("10:15",1.15340,1.15345,1.15322,1.15328),
 ("10:20",1.15328,1.15332,1.15308,1.15312),
 ("10:25",1.15312,1.15318,1.15295,1.15300),
 ("10:30",1.15300,1.15308,1.15290,1.15294),   # HL at 75% line
 ("10:35",1.15294,1.15312,1.15290,1.15308),
 ("10:40",1.15308,1.15328,1.15304,1.15324),
 ("10:45",1.15324,1.15345,1.15320,1.15340),
 ("10:50",1.15340,1.15360,1.15336,1.15356),
 ("10:55",1.15356,1.15375,1.15352,1.15372),
 ("11:00",1.15372,1.15392,1.15368,1.15388),
 ("11:05",1.15388,1.15398,1.15380,1.15394),
 ("11:10",1.15394,1.15400,1.15384,1.15396),
]

LEVELS = [ (0,"1.15530"), (12.5,"1.15489"), (25,"1.15449"), (37.5,"1.15408"),
           (50,"1.15368"), (62.5,"1.15327"), (75,"1.15286"),
           (87.5,"1.15246"), (100,"1.15205") ]

# session overview waypoints: (minutes since 23:15, price)
WP = [(0,1.15455),(15,1.15385),(45,1.15435),(70,1.15495),(85,1.15440),
 (105,1.15480),(155,1.15530),(185,1.15495),(215,1.15460),(245,1.15400),
 (270,1.15390),(335,1.15385),(375,1.15315),(420,1.15375),(455,1.15295),
 (480,1.15270),(520,1.15340),(550,1.15290),(580,1.15205),(610,1.15325),
 (630,1.15390),(645,1.15368),(670,1.15290),(715,1.15395),(750,1.15325),
 (770,1.15390),(810,1.15330),(850,1.15335),(920,1.15440),(950,1.15425),
 (980,1.15475),(1020,1.15410),(1025,1.15430),(1065,1.15530),(1100,1.15413)]

W, ML, PW = 1070, 70, 880
OV_Y0, OV_H = 30, 130
ZM_Y0, ZM_H = 235, 470

def yov(p): return OV_Y0 + (PHI - p) / SPAN * OV_H
def xov(m): return ML + m / 1105.0 * PW
def yz(p):  return ZM_Y0 + (PHI - p) / SPAN * ZM_H

step = PW / len(Z)
def xz(i):  return ML + (i + 0.5) * step

def esc(s): return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

def label(x, y, text, fill=TXT, anchor="start", size=11, weight="normal", bg=None):
    t = f'<text x="{x:.1f}" y="{y:.1f}" fill="{fill}" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}" font-family="Segoe UI,Roboto,sans-serif">{esc(text)}</text>'
    if bg:
        pad = 4
        wt = 6.1*len(text)
        bx = x - pad if anchor=="start" else x - wt/2 - pad if anchor=="middle" else x - wt - pad
        t = f'<rect x="{bx:.1f}" y="{y - size + 1:.1f}" width="{wt + 2*pad:.0f}" height="{size + 6}" rx="3" fill="{bg}" opacity="0.92"/>' + t
    return t

svg = []
svg.append(f'<svg viewBox="0 0 {W} 810" xmlns="http://www.w3.org/2000/svg" style="width:100%;height:auto;background:{BG};border-radius:10px">')
svg.append(f'<rect x="0" y="0" width="{W}" height="810" fill="{BG}"/>')
svg.append(label(ML, 18, "SESSION OVERVIEW  ·  EURUSD M5 · 14 Sep 23:15 → 15 Sep 17:30 (server time) · schematic reconstruction", MUT, size=12, weight="bold"))

# ---- overview panel
svg.append(f'<rect x="{ML}" y="{OV_Y0}" width="{PW}" height="{OV_H}" fill="{PANEL}" rx="6"/>')
# gann box rect on overview
bx1, bx2 = xov(155), xov(580)
by1, by2 = yov(1.15530), yov(1.15205)
svg.append(f'<rect x="{bx1:.1f}" y="{by1:.1f}" width="{bx2-bx1:.1f}" height="{by2-by1:.1f}" fill="{PURPLE}" opacity="0.08"/>')
svg.append(f'<rect x="{bx1:.1f}" y="{by1:.1f}" width="{bx2-bx1:.1f}" height="{by2-by1:.1f}" fill="none" stroke="{PURPLE}" stroke-width="1.2" stroke-dasharray="5 4"/>')
# 0.5 line across overview
svg.append(f'<line x1="{ML}" y1="{yov(1.15368):.1f}" x2="{ML+PW}" y2="{yov(1.15368):.1f}" stroke="{CYAN}" stroke-width="1" stroke-dasharray="4 4" opacity="0.55"/>')
# day separator
svg.append(f'<line x1="{xov(45):.1f}" y1="{OV_Y0}" x2="{xov(45):.1f}" y2="{OV_Y0+OV_H}" stroke="{GRID}" stroke-width="1"/>')
svg.append(label(xov(45)+4, OV_Y0+10, "15 Sep", MUT, size=9))
# path
pts = " ".join(f"{xov(m):.1f},{yov(p):.1f}" for m,p in WP)
svg.append(f'<polyline points="{pts}" fill="none" stroke="{TXT}" stroke-width="1.4" opacity="0.9"/>')
# hour labels
for m,lab in [(45,"00:00"),(225,"03:00"),(405,"06:00"),(585,"09:00"),(765,"12:00"),(945,"15:00"),(1095,"17:30")]:
    svg.append(f'<line x1="{xov(m):.1f}" y1="{OV_Y0+OV_H}" x2="{xov(m):.1f}" y2="{OV_Y0+OV_H+4}" stroke="{MUT}"/>')
    svg.append(label(xov(m), OV_Y0+OV_H+15, lab, MUT, anchor="middle", size=9.5))
# markers
MK = [(155,1.15530,"① 01:50 — structure START (high 1.15530)",TXT,"start",-8,GOLD),
      (580,1.15205,"② 08:55 — structure END (low 1.15205)",TXT,"start",-16,GOLD),
      (620,1.15370,"③ 09:35 — CHOCH: close > LH 1.15345",GREEN,"start",-6,GREEN),
      (645,1.15368,"④ 10:00 — touch 0.5 → BUY",CYAN,"end",-22,CYAN),
      (1065,1.15530,"⑤ ~17:00 — box top retested 1.15530",MUT,"end",-8,MUT)]
for m,p,txt,_,anchor,dy,c in MK:
    x,y = xov(m), yov(p)
    svg.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="3.6" fill="{c}" stroke="{BG}" stroke-width="1"/>')
    ax = x + (6 if anchor=="start" else -6)
    svg.append(label(ax, y+dy+ (10 if dy>0 else 0), txt, c, anchor=anchor, size=10.5, weight="bold", bg="#131722"))

# ---- zoom panel title
svg.append(label(ML, ZM_Y0-16, "ZOOM 07:30 → 11:10  ·  structure ②, CHOCH ③ and 0.5 trigger ④  (levels = Gann-box eighths)", MUT, size=12, weight="bold"))
svg.append(f'<rect x="{ML}" y="{ZM_Y0}" width="{PW}" height="{ZM_H}" fill="{PANEL}" rx="6"/>')

# hour gridlines + bottom time labels
for i,lab in [(0,"07:30"),(6,"08:00"),(12,"08:30"),(18,"09:00"),(24,"09:30"),(30,"10:00"),(36,"10:30"),(42,"11:00")]:
    svg.append(f'<line x1="{xz(i):.1f}" y1="{ZM_Y0}" x2="{xz(i):.1f}" y2="{ZM_Y0+ZM_H}" stroke="{GRID}" stroke-width="1"/>')
    svg.append(label(xz(i), ZM_Y0+ZM_H+16, lab, MUT, anchor="middle", size=9.5))

# box eighth levels
for frac, ps in LEVELS:
    col = CYAN if frac == 50 else "#3a3f4d"
    wd  = 1.6 if frac == 50 else 1
    dash = "" if frac == 50 else ' stroke-dasharray="2 4"'
    svg.append(f'<line x1="{ML}" y1="{yz(float(ps)):.1f}" x2="{ML+PW}" y2="{yz(float(ps)):.1f}" stroke="{col}" stroke-width="{wd}"{dash}/>')
    colt = CYAN if frac == 50 else MUT
    wbold = "bold" if frac in (50,) else "normal"
    svg.append(label(ML+PW+8, yz(float(ps))+4, f"{ps}  ·  {frac:g}%", colt, size=10.5, weight=wbold))

# LH line
svg.append(f'<line x1="{xz(3):.1f}" y1="{yz(1.15345):.1f}" x2="{xz(26):.1f}" y2="{yz(1.15345):.1f}" stroke="{RED}" stroke-width="1.3" stroke-dasharray="6 4"/>')
svg.append(label(xz(8), yz(1.15345)-6, "last LOWER HIGH 1.15340–45 — broken = CHOCH", RED, size=10.5, weight="bold", bg="#131722"))

# candles
for i,(t,o,h,l,c) in enumerate(Z):
    x = xz(i); col = BULL if c >= o else BEAR
    svg.append(f'<line x1="{x:.1f}" y1="{yz(h):.1f}" x2="{x:.1f}" y2="{yz(l):.1f}" stroke="{col}" stroke-width="1.2"/>')
    yo_, yc = yz(max(o,c)), yz(min(o,c))
    if yo_ - yc < 1: yc = yo_ + 1
    fill = col if c < o else col
    svg.append(f'<rect x="{x-5.5:.1f}" y="{yo_:.1f}" width="11" height="{max(yc-yo_,1.5):.1f}" fill="{col}" rx="0.5"/>')

# key candle annotations
x = xz(17)
svg.append(f'<circle cx="{x:.1f}" cy="{yz(1.15205)+6:.1f}" r="7" fill="none" stroke="{GOLD}" stroke-width="1.4"/>')
svg.append(label(x+12, yz(1.15205)-12, "② swing LOW 1.15205 (08:55) — box anchor", GOLD, size=10.5, weight="bold", bg="#131722"))

x = xz(25)
svg.append(f'<rect x="{x-8:.1f}" y="{yz(1.15375)-6:.1f}" width="16" height="{yz(1.15332)-yz(1.15375)+12:.1f}" fill="none" stroke="{GREEN}" stroke-width="1.6" rx="2"/>')
svg.append(label(x-12, 437, "③ CHOCH candle 09:35 — closes 1.15370 > 1.15345", GREEN, size=10.5, weight="bold", anchor="end", bg="#131722"))

x = xz(30)
svg.append(f'<circle cx="{x:.1f}" cy="{yz(1.15355):.1f}" r="8" fill="none" stroke="{CYAN}" stroke-width="1.8"/>')
svg.append(label(x-12, 455, "④ 10:00 candle — FIRST TOUCH of 0.5 (1.15368) → BUY", CYAN, size=11, weight="bold", anchor="end", bg="#131722"))

x = xz(36)
svg.append(label(x, yz(1.15290)+22, "HL holds 75% (1.15290)", MUT, anchor="middle", size=10, bg="#131722"))

svg.append(label(ML+8, yz(1.15408)-40, "post-CHOCH high ≈1.15400 = 37.5% line / fib 0.618", MUT, size=10, bg="#131722"))
svg.append(f'<path d="M {ML+PW-160} {ZM_Y0+10} h 150" stroke="none"/>')
svg.append(label(ML+6, ZM_Y0+16, "Gann box ①→② : 01:50 @ 1.15530 → 08:55 @ 1.15205 · 85 × M5 candles · 32.5 pips", PURPLE, size=10.5, weight="bold", bg="#131722"))

svg.append("</svg>")
SVG = "\n".join(svg)

CSS = """
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:#0b0d12;color:#d1d4dc;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;line-height:1.55}
.wrap{max-width:1120px;margin:0 auto;padding:28px 22px 60px}
h1{font-size:26px;margin:6px 0 2px}
h2{font-size:19px;margin:34px 0 10px;color:#f2994a;border-bottom:1px solid #232733;padding-bottom:6px}
h3{font-size:15px;margin:20px 0 6px;color:#b39ddb}
.sub{color:#8b909f;font-size:13px;margin-bottom:18px}
.card{background:#131722;border:1px solid #232733;border-radius:10px;padding:16px 18px;margin:14px 0}
table{border-collapse:collapse;width:100%;font-size:13px;margin:10px 0}
th,td{border:1px solid #232733;padding:6px 9px;text-align:left}
th{background:#1a1e29;color:#f2994a;font-weight:600}
td.num{font-family:Consolas,Menlo,monospace}
.hl{background:#0e2a2e}
.buy{color:#22c55e;font-weight:700}
.cyn{color:#26c6da;font-weight:700}
.gld{color:#ffd54f;font-weight:700}
.red{color:#ef5350;font-weight:700}
.pur{color:#b39ddb;font-weight:700}
.mut{color:#8b909f}
code,.mono{font-family:Consolas,Menlo,monospace;background:#1a1e29;padding:1px 5px;border-radius:4px;font-size:12.5px}
ul{margin:6px 0 6px 22px;padding:0}
li{margin:4px 0}
.warn{border-left:3px solid #ffd54f;background:#1a1608;padding:10px 14px;border-radius:6px;font-size:13px;margin:14px 0}
.trade{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:12px;margin:12px 0}
.tcell{background:#131722;border:1px solid #232733;border-radius:10px;padding:12px 14px}
.tcell .k{color:#8b909f;font-size:11.5px;text-transform:uppercase;letter-spacing:.4px}
.tcell .v{font-size:16px;font-weight:700;margin-top:3px;font-family:Consolas,Menlo,monospace}
"""

html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>EURUSD M5 — CHOCH + Gann Box 0.5 Analysis</title>
<style>{CSS}</style></head><body><div class="wrap">

<h1>EURUSD M5 — CHOCH Detection &amp; Gann-Box 0.5 Entry Study</h1>
<div class="sub">Instrument EURUSD · Timeframe M5 · Session 14 Sep 2026 23:15 → 15 Sep 2026 17:30 (broker server time, as printed on the chart) · Source: user screenshot <span class="mono">EURUSDM5.png</span> · Prepared 15 Sep 2026</div>

<div class="warn"><b>Precision notice.</b> This analysis is read from a static screenshot. Axis grid resolution ≈ 1.5 pips, so every price quoted is accurate to roughly <b>±0.5–1 pip</b> and every timestamp to roughly <b>±1 M5 candle (±5–10 min)</b>. Snap the anchors on your live chart to confirm exact prints before trading.</div>

{SVG}

<h2>Step 0 — Definitions used</h2>
<div class="card">
<h3>“Start of HIGH or LOW”</h3>
<p>The origin pivot of the impulse leg that defines the current structure — the absolute swing extreme where the move that will be broken <i>begins</i>. For a bearish structure the start is a <span class="gld">swing HIGH</span>; for a bullish structure the start is a swing LOW. On this chart the active structure is bearish, so its start is the high at <b>15 Sep 01:50 ≈ 1.15530</b>.</p>
<h3>CHOCH (Change of Character)</h3>
<p>The <i>first counter-trend break</i> of the most recent opposing pivot:</p>
<ul>
<li><b>Bullish CHOCH</b> — price is printing lower lows / lower highs; the first candle <b>close above the last lower high (LH)</b> flips the character to bullish.</li>
<li><b>Bearish CHOCH</b> — mirror image: first close below the last higher low in an uptrend.</li>
<li>It differs from <b>BOS</b> (Break of Structure), which is a break <i>in the direction of the trend</i> (continuation), not against it.</li>
</ul>
<h3>Gann box as applied here</h3>
<p>A rectangle anchored at the structure start ① and at the terminal point of the broken structure ② — the exact pivot from which the breaking impulse launches. Its horizontal grid divides the structure range into eighths; the <span class="cyn">0.5 (50%) line</span> is the bisector of the full ①→② range and is the entry trigger of this strategy.</p>
</div>

<h2>Step 1 — Locating the CHOCH</h2>
<div class="card">
<p>From the 01:50 high the market printed a textbook bearish structure for ~7 hours — every rally failed at a lower high and every decline broke the prior low:</p>
<table>
<tr><th>Swing (server time)</th><th>Type</th><th>Price (approx)</th><th>Role</th></tr>
<tr><td>01:50</td><td>H</td><td class="num">1.15530</td><td>Major high — structure start ①</td></tr>
<tr><td>03:20 – 05:00</td><td>L / H</td><td class="num">1.15385 – 1.15390</td><td>LL then LH</td></tr>
<tr><td>05:30</td><td>L</td><td class="num">1.15315</td><td>LL</td></tr>
<tr><td>06:10 – 06:20</td><td>H</td><td class="num">1.15375 – 1.15380</td><td>LH</td></tr>
<tr><td>06:50 – 07:20</td><td>L</td><td class="num">1.15265 – 1.15295</td><td>LL</td></tr>
<tr class="hl"><td>07:45 – 07:55</td><td>H</td><td class="num">1.15340 – 1.15345</td><td><b>Last lower high — the CHOCH break level</b></td></tr>
<tr class="hl"><td>08:55</td><td>L</td><td class="num">1.15205</td><td><b>Terminal low — structure end ②</b></td></tr>
</table>
<p><b>The CHOCH candle:</b> at <b>09:35</b> (±1 candle) a strong bull candle opens ≈1.15338 and <b>closes ≈1.15370, above the last lower high 1.15345</b> — the first close against the downtrend's swing sequence → <span class="buy">bullish CHOCH confirmed</span>. The next candle (09:40) extends to ≈1.15390 and is the confirmation candle; the post-CHOCH impulse stalls at ≈1.15400.</p>
<p class="mut">Before the break, the 09:30 candle retests the LH zone and holds below it — the failure of that retest is what precedes the expansion candle.</p>
</div>

<h2>Step 2 — Start point of the structure</h2>
<div class="card">
<p>The structure whose break creates the CHOCH is the bearish leg <b>01:50 → 08:55</b>. Its start point (the “start of HIGH”) is:</p>
<p style="font-size:16px">① <span class="gld">Start anchor: 15 Sep 2026, 01:50 · <b>1.15530</b></span> (major session high)</p>
<p>Its terminal point — the low that ends the structure and from which the CHOCH-breaking impulse is launched:</p>
<p style="font-size:16px">② <span class="gld">End anchor: 15 Sep 2026, 08:55 · <b>1.15205</b></span> (session low)</p>
</div>

<h2>Step 3 — Gann box measurement ① → ②</h2>
<div class="card">
<table>
<tr><th>Box parameter</th><th>Value</th></tr>
<tr><td>Anchor 1 (start high)</td><td class="num">2026-09-15 01:50 · 1.15530</td></tr>
<tr><td>Anchor 2 (break-origin low)</td><td class="num">2026-09-15 08:55 · 1.15205</td></tr>
<tr><td>Box height (price range)</td><td class="num">0.00325 = 32.5 pips</td></tr>
<tr><td>Box width (time)</td><td class="num">7 h 05 min = 425 min = 85 × M5 candles</td></tr>
<tr class="hl"><td><b>0.5 level (trigger)</b></td><td class="num"><b>1.15530 − 0.001625 = 1.153675 ≈ 1.15368</b></td></tr>
</table>
<h3>Full level grid (box eighths) with Fibonacci cross-check</h3>
<table>
<tr><th>Box fraction (from top)</th><th>Price</th><th>Fib retracement of ②→① up-move</th><th>What happened there</th></tr>
<tr><td>0%</td><td class="num">1.15530</td><td class="num">100%</td><td>Structure start ① / final target</td></tr>
<tr><td>12.5%</td><td class="num">1.15489</td><td class="num">≈78.6% (1.15460)</td><td>—</td></tr>
<tr><td>25%</td><td class="num">1.15449</td><td class="num">—</td><td>Secondary target zone</td></tr>
<tr><td>37.5%</td><td class="num">1.15408</td><td class="num">61.8% (1.15406)</td><td>Post-CHOCH swing high ≈1.15400 launched the pullback</td></tr>
<tr class="hl"><td><b>50%</b></td><td class="num"><b>1.15368</b></td><td class="num">50% (1.15368)</td><td><b>ENTRY TRIGGER — first touch 10:00 candle</b></td></tr>
<tr><td>62.5%</td><td class="num">1.15327</td><td class="num">38.2% (1.15329)</td><td>Confluence with the LH 1.15340–45 → the CHOCH broke right through this zone</td></tr>
<tr><td>75%</td><td class="num">1.15286</td><td class="num">23.6% (1.15282)</td><td>Pullback low 1.15290 held here → higher low</td></tr>
<tr><td>87.5%</td><td class="num">1.15246</td><td class="num">—</td><td>—</td></tr>
<tr><td>100%</td><td class="num">1.15205</td><td class="num">0%</td><td>Structure end ② / stop-loss anchor</td></tr>
</table>
<p><b>Why these anchors and not the break candle itself:</b> measuring ① → the 09:35 break candle (≈1.15370) would collapse the box to ~16 pips, put its 0.5 at ≈1.15450, and the “retracement touch” would not occur until ~14:35 — a degenerate reading. The strategy's convention is that the box bisects the <i>whole broken structure</i>, so the second anchor is the structure extreme ② (the pivot from which the break emanates). The 0.5 line then marks the true equilibrium of the ①→② leg.</p>
</div>

<h2>Step 4 — Retracement &amp; the candle that touches 0.5</h2>
<div class="card">
<ul>
<li>09:35–09:50 — impulse to ≈1.15400 (stalls at the 37.5% / fib-61.8% shelf).</li>
<li>09:55 — first pullback candle; low 1.15372 still above the 0.5 line.</li>
<li class="cyn"><b>10:00 candle — low ≈1.15355 &lt; 1.15368 → FIRST TOUCH of the 0.5 level. This is the signal candle (±1 candle: 10:00–10:10).</b></li>
<li>10:05–10:30 — price continues into the sweet zone, printing the retracement low ≈1.15290 exactly on the 75% line (1.15286) — a higher low vs ②, structure stays valid.</li>
<li>10:35 onward — reclaim of 0.618/0.5, then expansion: 11:10 ≈1.15400 → 14:35 ≈1.15440 → 15:35 ≈1.15475 → 17:00 spike 1.15530–1.15535 (box top retested = target zone hit).</li>
</ul>
</div>

<h2>Step 5 — Entry signal &amp; trade card</h2>
<div class="card">
<p>Touch of 0.5 after a confirmed bullish CHOCH = <span class="buy">BUY (long) signal on EURUSD M5 at ≈1.15368, candle of 10:00 server time</span>.</p>
<div class="trade">
<div class="tcell"><div class="k">Signal</div><div class="v buy">BUY @ 1.15368</div><div class="k">10:00 M5 candle (touch) / fill ≈10:05</div></div>
<div class="tcell"><div class="k">Stop loss (strategy)</div><div class="v">1.15195</div><div class="k">below structure low ② 1.15205 · risk 17.3 pips</div></div>
<div class="tcell"><div class="k">T1 / T2 / T3</div><div class="v">1.15406 / 1.15449 / 1.15530</div><div class="k">37.5% shelf · 25% · box top ①</div></div>
<div class="tcell"><div class="k">R:R to box top</div><div class="v">≈ 1 : 0.94</div><div class="k">tactical stop under 1.15285 → ≈ 1 : 1.95</div></div>
<div class="tcell"><div class="k">Outcome on this chart</div><div class="v buy">+16 pips (T3 hit ~17:00)</div><div class="k">MAE: −8 pips at 10:30 (75% held)</div></div>
<div class="tcell"><div class="k">Invalidation</div><div class="v red">M5 close &lt; 1.15205</div><div class="k">or close back below 62.5% (1.15327) after entry = stand aside</div></div>
</div>
</div>

<h2>Reproducing the measurement on your chart</h2>
<div class="card">
<ul>
<li>Select the <b>Gann Box</b> tool (TradingView) or Gann Square/Fan equivalent.</li>
<li>Drag corner 1 to <span class="mono">15 Sep 01:50 · 1.15530</span> (the session high candle), corner 2 to <span class="mono">15 Sep 08:55 · 1.15205</span> (the session-low candle).</li>
<li>Keep the default eighths (0, 1/8 … 4/8 … 1); the <span class="cyn">4/8 = 50% line should print at ≈1.15367–1.15368</span> — if it doesn't, your anchor snap is off.</li>
<li>Verify the CHOCH: the 09:35 candle body closes above the 07:45–07:55 lower-high wick zone (1.15340–45).</li>
</ul>
</div>

<h2>Assumptions &amp; caveats</h2>
<div class="card">
<ul>
<li>All values are derived visually from the supplied screenshot — not from OHLC data. Treat prices as ±0.5–1 pip and times as ±1 candle.</li>
<li>Broker server time is used throughout (as printed on the chart axis); convert to your local timezone as needed.</li>
<li>The session overview polyline and the zoom candles are a schematic reconstruction drawn from the screenshot's shape for illustration — they preserve the sequence and levels of the real swing points but are not a tick-accurate replay.</li>
<li>CHOCH retracement entries fail in strong news conditions; this was the pre-London/New-York overlap window — check the calendar before replaying live.</li>
</ul>
<p class="mut">Educational chart analysis, not financial advice.</p>
</div>

</div></body></html>
"""

out = "/home/user/kkk/EURUSD_M5_CHOCH_Gann_Box_Analysis.html"
with open(out, "w") as f:
    f.write(html)
print("written", out, len(html), "bytes")
