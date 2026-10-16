#!/usr/bin/env python3
"""
Renders preview/fib_preview.png — a faithful picture of what fib_hh_ll_signals.pine
draws (levels, entry zone, ladder tap, TP/SL markers, plan dashboard).

Pure standard library: a 5x7 bitmap font + a small rasteriser + a PNG writer.
Candle data and signal logic come from generate_preview.py (the same maths the
Pine script uses).  Run:  python3 preview/render_png.py
"""
import zlib, struct
from generate_preview import make_candles, run, C_E1, C_E2, C_E3, C_TP, C_SL

W, H = 1600, 880
PAD_L, PAD_R, PAD_T, PAD_B = 26, 300, 66, 40
BG, UP, DN = (19, 23, 34), (38, 166, 154), (239, 83, 80)
GRID, GRAY = (30, 34, 45), (120, 123, 134)
PANEL, BORDER, TXT = (16, 20, 29), (54, 58, 69), (178, 181, 190)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ── 5x7 font ────────────────────────────────────────────────────────────────────
F = {
 '0': (".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."),
 '1': ("..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."),
 '2': (".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"),
 '3': ("#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."),
 '4': ("...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."),
 '5': ("#####", "#....", "####.", "....#", "....#", "#...#", ".###."),
 '6': ("..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."),
 '7': ("#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."),
 '8': (".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."),
 '9': (".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."),
 'A': ("..#..", ".#.#.", "#...#", "#...#", "#####", "#...#", "#...#"),
 'B': ("####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."),
 'C': (".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."),
 'D': ("###..", "#..#.", "#...#", "#...#", "#...#", "#..#.", "###.."),
 'E': ("#####", "#....", "#....", "####.", "#....", "#....", "#####"),
 'F': ("#####", "#....", "#....", "####.", "#....", "#....", "#...."),
 'G': (".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."),
 'H': ("#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
 'I': (".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."),
 'J': ("..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."),
 'K': ("#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"),
 'L': ("#....", "#....", "#....", "#....", "#....", "#....", "#####"),
 'M': ("#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"),
 'N': ("#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"),
 'O': (".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
 'P': ("####.", "#...#", "#...#", "####.", "#....", "#....", "#...."),
 'Q': (".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"),
 'R': ("####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"),
 'S': (".####", "#....", "#....", ".###.", "....#", "....#", "####."),
 'T': ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."),
 'U': ("#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
 'V': ("#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."),
 'W': ("#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"),
 'X': ("#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"),
 'Y': ("#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."),
 'Z': ("#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"),
 '.': (".....", ".....", ".....", ".....", ".....", ".##..", ".##.."),
 ',': (".....", ".....", ".....", ".....", ".##..", ".##..", ".#..."),
 ':': (".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."),
 '-': (".....", ".....", ".....", "#####", ".....", ".....", "....."),
 '+': (".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."),
 '/': ("....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."),
 '|': ("..#..", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."),
 '%': ("##..#", "##.#.", "..#..", ".#...", "#..##", "#..##", "....."),
 '(': ("..##.", ".#...", "#....", "#....", "#....", ".#...", "..##."),
 ')': (".##..", "...#.", "....#", "....#", "....#", "...#.", ".##.."),
 '>': ("#....", ".#...", "..#..", "...#.", "..#..", ".#...", "#...."),
 ' ': (".....", ".....", ".....", ".....", ".....", ".....", "....."),
}

buf = bytearray(bytes(BG) * W * H)


def px(x, y, c):
    x, y = int(x), int(y)
    if 0 <= x < W and 0 <= y < H:
        o = (y * W + x) * 3
        buf[o:o + 3] = bytes(c)


def rect(x0, y0, x1, y1, c, mix=1.0):
    for y in range(max(0, int(y0)), min(H, int(y1) + 1)):
        for x in range(max(0, int(x0)), min(W, int(x1) + 1)):
            o = (y * W + x) * 3
            if mix >= 1.0:
                px(x, y, c)
            else:
                px(x, y, tuple(int(buf[o + k] * (1 - mix) + c[k] * mix) for k in range(3)))


def line(x0, y0, x1, y1, c, w=1):
    n = max(1, int(max(abs(x1 - x0), abs(y1 - y0))))
    for k in range(n + 1):
        for d in range(w):
            px(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n + d, c)


def text(x, y, s, c, sc=2, sp=1):
    cx = x
    for ch in s.upper():
        g = F.get(ch, F['?'] if '?' in F else F[' '])
        for r, row in enumerate(g):
            for k, b in enumerate(row):
                if b == '#':
                    rect(cx + k * sc, y + r * sc, cx + k * sc + sc - 1, y + r * sc + sc - 1, c)
        cx += (5 + sp) * sc
    return cx


def tw(s, sc=2, sp=1):
    return len(s) * (5 + sp) * sc - sp * sc


def main():
    cdl = make_candles()
    hist, events = run(cdl)
    L = hist[-1]
    fib = L['fib']
    st = L['st']
    levels = [(L['e1'], "0.755", "E1", hexc(C_E1)), (L['e2'], "0.766", "E2", hexc(C_E2)),
              (L['e3'], "0.788", "E3", hexc(C_E3)), (L['tp'], "0.33", "TP", hexc(C_TP)),
              (L['sl'], "0.98", "SL", hexc(C_SL)), (fib['hi'], "0", "LEG HIGH", GRAY),
              (fib['lo'], "1", "LEG LOW", GRAY)]
    lo = min(b['l'] for b in cdl) - 0.35
    hi = max(b['h'] for b in cdl) + 0.35
    n = len(cdl)
    cw = (W - PAD_L - PAD_R) / (n + 6)
    X = lambda i: PAD_L + (i + 3) * cw
    Y = lambda p: PAD_T + (hi - p) / (hi - lo) * (H - PAD_T - PAD_B)

    # grid + axis
    g = 1.0
    p = (int(lo / g)) * g
    while p < hi:
        y = Y(p)
        line(PAD_L, y, W - PAD_R, y, GRID)
        text(PAD_L + 4, y - 9, f"{p:.0f}", (66, 70, 82), 2)
        p += g

    # fib span box + entry zone
    xL, xR = X(fib['xL']), X(n - 1)
    rect(xL, Y(fib['hi']), xR, Y(fib['lo']), GRAY, 0.05)
    rect(xL, Y(max(L['e1'], L['e2'], L['e3'])), xR, Y(min(L['e1'], L['e2'], L['e3'])), hexc(C_E1), 0.16)

    # candles
    for i, b in enumerate(cdl):
        x = X(i)
        c = UP if b['c'] >= b['o'] else DN
        line(x, Y(b['h']), x, Y(b['l']), c)
        rect(x - cw * 0.32, Y(max(b['o'], b['c'])), x + cw * 0.32, Y(min(b['o'], b['c'])) + 1, c)

    # levels, then right-hand price tags fanned out so they never collide
    ys = sorted(range(len(levels)), key=lambda k: Y(levels[k][0]))
    GAP = 23
    pos = {}
    prev = None
    for k in ys:
        y = Y(levels[k][0])
        y2 = y if prev is None else max(y, prev + GAP)
        pos[k] = y2
        prev = y2
    shift = (H - PAD_B + 4) - (pos[ys[-1]] + 11) if pos[ys[-1]] + 11 > H - PAD_B else 0
    for k in ys:
        pos[k] += shift
    for k, (pxv, nm, tag, col) in enumerate(levels):
        y, y2 = Y(pxv), pos[k]
        line(xL, y, xR, y, col, 2)
        txt = f"{nm}  {tag}" if tag else nm
        if abs(y2 - y) > 2:
            line(xR + 1, y, xR + 4, y2, col)
        rect(xR + 3, y2 - 10, xR + 5, y2 + 10, col)
        rect(xR + 5, y2 - 10, xR + 14 + tw(f"{txt}  {pxv:.3f}", 2), y2 + 10, PANEL)
        text(xR + 11, y2 - 7, f"{txt}  {pxv:.3f}", col, 2)

    # event markers
    for i, kind, tag in events:
        x = X(i)
        if kind == 'entry':
            y = Y(cdl[i]['l'])
            for d in range(9):
                line(x - d, y + 16 + d, x + d, y + 16 + d, hexc(C_E1))
            text(x - tw(tag + ' ENTRY', 2) / 2, y + 30, tag + " ENTRY", hexc(C_E1), 2)
        elif kind in ('TP', 'SL'):
            col = hexc(C_TP) if kind == 'TP' else hexc(C_SL)
            y = Y(cdl[i]['h']) - 18 if kind == 'TP' else Y(cdl[i]['l']) + 18
            line(x - 7, y - 7, x + 7, y + 7, col, 2)
            line(x - 7, y + 7, x + 7, y - 7, col, 2)
            text(x + 12, y - 7, kind + " " + tag, col, 2)

    # title + legend
    text(PAD_L, 16, "FIB HH/LL  ·  0.755 / 0.766 / 0.788 ENTRIES  ·  TP 0.33  ·  SL 0.98", (209, 212, 220), 2)
    x = PAD_L
    for nm, col in (("ENTRIES 0.755-0.788", E1 if False else hexc(C_E1)), ("TP 0.33", hexc(C_TP)), ("SL 0.98", hexc(C_SL)), ("ANCHORS 0/1", GRAY)):
        rect(x, 40, x + 12, 52, col)
        x = text(x + 20, 40, nm, TXT, 2) + 26
        text(x - 20, 40, "   ", TXT, 2)

    # dashboard panel
    status = {0: "NO SETUP", 1: "WAITING FOR ENTRY", 2: "IN TRADE", 3: "TP HIT", 4: "SL HIT", 5: "SETUP CANCELLED"}[st['stat']]
    dup, ddir = st['dir'] == 1, "LONG" if st['dir'] == 1 else "SHORT"
    rows = [
        ("LEG", f"{fib['lo']:.3f}  >  {fib['hi']:.3f}", TXT),
        ("ENTRIES", f"{L['e1']:.3f}  {L['e2']:.3f}  {L['e3']:.3f}", TXT),
        ("STOP / TARGET", f"{L['sl']:.3f} (0.98)   |   {L['tp']:.3f} (0.33)", TXT),
        ("FILLED", f"{st['fills']} / 3    AVG {st['avg']:.3f}", TXT),
        ("REWARD : RISK", f"{st['rr']:.2f} R", TXT),
        ("STATUS", status, hexc(C_TP) if st['stat'] == 3 else hexc(C_SL) if st['stat'] == 4 else hexc(C_E1)),
    ]
    pw = max(tw(k, 2) + tw(v, 2) + 70 for k, v, _ in rows)
    pw = max(pw, tw("FIB PLAN   " + ddir, 2) + 40)
    ph = 22 * len(rows) + 52
    px0, py0 = PAD_L + 10, PAD_T + 12
    rect(px0, py0, px0 + pw, py0 + ph, PANEL)
    rect(px0, py0, px0 + pw, py0 + 30, (24, 29, 41))
    rect(px0, py0, px0 + pw, py0 + 1, BORDER)
    rect(px0, py0 + ph, px0 + pw, py0 + ph, BORDER)
    rect(px0, py0, px0 + 1, py0 + ph, BORDER)
    rect(px0 + pw, py0, px0 + pw, py0 + ph, BORDER)
    rect(px0, py0 + 30, px0 + pw, py0 + 31, BORDER)
    text(px0 + 12, py0 + 8, "FIB PLAN   " + ddir, hexc(C_E1) if dup else hexc(C_SL), 2)
    for r, (k, v, col) in enumerate(rows):
        yy = py0 + 44 + r * 22
        text(px0 + 12, yy, k, (255, 255, 255), 2)
        text(px0 + pw - 12 - tw(v, 2), yy, v, col, 2)

    raw = b''.join(b'\x00' + bytes(buf[y * W * 3:(y + 1) * W * 3]) for y in range(H))
    def ch(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + ch(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
           + ch(b'IDAT', zlib.compress(raw, 6)) + ch(b'IEND', b''))
    open('preview/fib_preview.png', 'wb').write(png)
    print("wrote preview/fib_preview.png", len(png) // 1024, "KB")


if __name__ == "__main__":
    main()
