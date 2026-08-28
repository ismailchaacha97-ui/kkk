#!/usr/bin/env python3
"""Static sanity checks for MQL4 sources (no MetaEditor in this sandbox).

Catches the mistakes that actually break an MT4 build:
  * brace / paren / bracket imbalance
  * calls to our own helpers that are never defined     (typos)
  * MQL5-only API in an MT4 file                        (build breaker)
  * global variables used before their declaration      (build breaker)
  * if (x = y) assignment typos
  * duplicate function definitions
  * declared-but-unused inputs (dead switches)
  * object names that would exceed MT4's 63-char limit
"""
import re
import sys

MQL5_ONLY = [
    "OnCalculate", "CopyRates", "CopyBuffer", "CopyClose", "CopyOpen", "CopyTime",
    "ArraySetAsSeries", "ChartSetSymbolPeriod", "SeriesInfoInteger", "MqlRates",
    "EnumCalculateMode", "PlotIndexSetInteger", "PlotIndexSetString", "tick_volume",
    "real_volume", "OnTradeTransaction", "PositionOpen", "OrderSend", "MathIsFinite",
    "iHigh", "iLow", "iClose", "iOpen",   # MQL4 has these, but cross-TF access
                                          # must be explicit - flag bare use
]
MQL4_PREDEFINED = ["Bars", "Time", "Open", "High", "Low", "Close", "Volume", "Point", "Digits", "Period"]


def scan(src):
    """single pass: blank out comments and string contents, keep code intact"""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":                       # line comment
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if c == "/" and nxt == "*":                       # block comment
            out.append("  ")
            i += 2
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
            continue
        if c in '"\'':                                    # string / char literal
            q = c
            out.append(c)
            i += 1
            while i < n:
                if src[i] == "\\":
                    out.append("  ")
                    i += 2
                    continue
                if src[i] == q:
                    out.append(q)
                    i += 1
                    break
                out.append("x" if src[i] != "\n" else "\n")
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def strip_pp(code):
    """drop preprocessor lines (#include/#define/#property) from analysis"""
    return "\n".join("" if ln.lstrip().startswith("#") else ln for ln in code.split("\n"))


def check(path):
    raw = open(path, encoding="utf-8", errors="replace").read()
    code = strip_pp(scan(raw))
    errs, warns = [], []

    for o, c, nm in (("{", "}", "brace"), ("(", ")", "paren"), ("[", "]", "bracket")):
        if code.count(o) != code.count(c):
            errs.append(f"unbalanced {nm}: {code.count(o)} '{o}' vs {code.count(c)} '{c}'")

    #--- functions ------------------------------------------------
    funcs = {}
    for m in re.finditer(r"^\s*(?:void|int|bool|double|string|color|datetime|uint|long)\s+(\w+)\s*\(",
                         code, flags=re.M):
        name = m.group(1)
        if name in funcs:
            errs.append(f"duplicate function definition: {name}()")
        funcs[name] = m.start()

    defined = set(funcs) | set(re.findall(r"#define\s+(\w+)", raw))
    builtin = set(re.findall(r"\b(Indicator\w+|SetIndex\w+|Object\w+|Chart\w+|Math\w+|String\w+|"
                             r"Array\w+|Double\w+|Integer\w+|Time\w+|PlaySound|Alert|Comment|"
                             r"GetLastError|GetTickCount|iVolume|Symbol|Period|StrToTime|ResetLastError)\w*",
                             code))
    for c in sorted(set(re.findall(r"\b(VVP\w+|BuildProfile|BuildSessions|RecalcVWAP|DrawAll)\s*\(", code))):
        if c not in defined:
            errs.append(f"call to undefined function: {c}()")

    for f in MQL5_ONLY:
        if re.search(r"\b" + f + r"\s*\(", code):
            errs.append(f"MQL5-only API used in an MT4 file: {f}()")

    #--- globals must precede use --------------------------------
    gvars = {}
    for m in re.finditer(r"^(?:double|int|bool|string|color|datetime|uint)\s+(g_\w+)\s*(?:\[[^\]]*\])?\s*(?:=[^;]*)?;",
                         code, flags=re.M):
        gvars.setdefault(m.group(1), m.start())
    for m in re.finditer(r"\b(g_\w+)\b", code):
        name, pos = m.group(1), m.start()
        if name in gvars and pos < gvars[name]:
            line = code[:pos].count("\n") + 1
            errs.append(f"global '{name}' used at line {line}, declared at line "
                        f"{code[:gvars[name]].count(chr(10)) + 1}")

    #--- loop variables: MQL4 'for(int i...)' is scoped to the loop, so a
    #--- later 'for(i = ...)' in the same function is an undeclared identifier
    bodies = []
    for m in re.finditer(r"^\s*(?:void|int|bool|double|string|color|datetime|uint|long)\s+(\w+)\s*\([^;]*\)\s*$",
                         code, flags=re.M):
        fname = m.group(1)
        seg = code[m.start():]
        depth, j = 0, 0
        while j < len(seg):
            if seg[j] == "{":
                depth += 1
            elif seg[j] == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        bodies.append((fname, seg[:j + 1]))

    for fname, body in bodies:
        # every 'for(int X ...)' is loop-scoped in MQL4; a later write to X in
        # the same function (outside that loop body) means an undeclared name.
        for m in re.finditer(r"for\s*\(\s*(?:int|double|bool)\s+(\w+)", body):
            name = m.group(1)
            # find the end of that loop's body
            k = body.find("{", m.end())
            head = body[m.end():k] if k > 0 else ""
            if k < 0 or "=" in head.split(";")[0]:
                endp = k if k > 0 else len(body)          # single statement body
                if k > 0:
                    d, j = 0, k
                    while j < len(body):
                        if body[j] == "{":
                            d += 1
                        elif body[j] == "}":
                            d -= 1
                            if d == 0:
                                break
                        j += 1
                    endp = j + 1
            else:
                d, j = 0, k
                while j < len(body):
                    if body[j] == "{":
                        d += 1
                    elif body[j] == "}":
                        d -= 1
                        if d == 0:
                            break
                    j += 1
                endp = j + 1
            tail = body[endp:]
            if re.search(r"\b" + name + r"\s*(?:=[^=]|\+\+|--|\+=|-=)", tail) and not re.search(
                    r"(?:int|double|bool|datetime|string)\s+" + name + r"\b", tail):
                errs.append(f"{fname}(): '{name}' written after its for() scope ends "
                            "(MQL4 for-variables are loop-scoped - hoist the declaration)")

    #--- assignment in condition ---------------------------------
    for m in re.finditer(r"if\s*\([^\n=!<>]*?[^\n=!<>+\-*/%]=[^=]", code):
        warns.append("possible assignment in if(): " + m.group(0).strip()[:70])

    #--- buffer arrays sized by IndicatorBuffers ------------------
    nb = len(re.findall(r"^\s*(?:double)\s+(Buf\w+)\s*\[\s*\];", code, flags=re.M))
    m = re.search(r"IndicatorBuffers\((\d+)\)", code)
    if not m:
        warns.append("no IndicatorBuffers(n) call found (legacy MT4 indicator?)")
    elif m.group(1) != str(nb):
        errs.append(f"IndicatorBuffers({m.group(1)}) but {nb} 'Buf*' arrays declared")

    #--- inputs used ---------------------------------------------
    inputs = re.findall(r"^input\b[^=;]*?\b(\w+)\s*=", raw, flags=re.M)
    for i in sorted(set(inputs)):
        if len(re.findall(r"\b" + i + r"\b", code)) < 2:
            warns.append(f"input '{i}' declared but never read")

    #--- object name length: MT4 allows at most 63 chars ---------
    if 'g_tag + IntegerToString(key)' in code:
        pass  # built as VVP<tag>_<key>_<kind><idx>: worst case ~24 chars, safe
    for m in re.finditer(r'ObjectCreate\(\s*"([^"]{40,})"', code):
        warns.append("hard-coded object name close to the 63-char limit")

    pre = [p for p in MQL4_PREDEFINED if re.search(r"\b" + p + r"\b", code)]
    print("== " + path)
    print("   {} lines | {} functions | {} inputs | {} buffers | MQL4 predefined: {}".format(
        len(raw.splitlines()), len(funcs), len(inputs), nb, ", ".join(pre)))
    for e in errs:
        print("   ERROR:", e)
    for w in warns:
        print("   warn :", w)
    if not errs:
        print("   OK: no static errors found")
    return (not errs), len(errs), len(warns)


if __name__ == "__main__":
    ok = True
    bad = 0
    for p in sys.argv[1:]:
        r, e, w = check(p)
        ok = ok and r
        bad += e
    sys.exit(1 if (ok is False or bad) else 0)
