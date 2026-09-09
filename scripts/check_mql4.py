#!/usr/bin/env python3
"""Structural checks for the MQL4 sources in mt4/ - see check_mql4 docstring for why.

There is no MetaEditor in this sandbox, so nothing here can claim "it compiles". What CAN be verified
locally is the class of mistake that breaks compiles in practice and is easy to make when a file is
written blind: unbalanced delimiters, a statement with a missing semicolon, a call to a function that
is neither a documented MQL4 builtin nor defined in the file, an `indicator_buffers` count that
disagrees with the SetIndexBuffer/plot properties, non-ASCII bytes in the source, and - the one that
actually bit me while writing these files - a name used before it is declared.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MT4 = HERE.parent / "mt4"

# Every MQL4 identifier these files call, minus the ones defined in the file. A call outside this list
# is reported so a human can look it up in the reference; it is not automatically an error.
BUILTIN = set("""
AccountEquity AccountFreeMarginCheck Alert ArrayResize ArraySetAsSeries Ask Bars Bid ChartGetDouble iMA iATR iClose iOpen
ChartGetInteger ChartRedraw Close Comment Digits iBarShift iBars iTime DoubleToStr DoubleToString GetLastError High
IndicatorCounted IndicatorDigits IndicatorShortName IntegerToString IsTesting Low MarketInfo MathAbs
MathFloor MathIsValidNumber MathMax MathMin MathNormalize MathPow MathSqrt NormalizeDouble
ObjectCreate ObjectDelete ObjectsDeleteAll ObjectSetInteger OrderClose OrderLots OrderMagicNumber
OrderSelect OrderSend OrderSymbol OrderTicket OrderType OrdersTotal Period PlaySound Print RefreshRates ResetLastError
SendNotification SetIndexArrow SetIndexBuffer SetIndexEmptyValue SetIndexLabel SetIndexStyle StringFormat
StringSplit StringToInteger Symbol Time WindowClose
""".split())

# constants/enums relied on; MQL4 spells most of these in UPPER or clr* form
CONST_RE = re.compile(r"^(EMPTY_VALUE|MODE_[A-Z_]+|PRICE_[A-Z]+|OP_[A-Z]+|PERIOD_[A-Z0-9]+|INIT_[A-Z_]+|"
                      r"OBJ_[A-Z]+|OBJPROP_[A-Z]+|DRAW_[A-Z]+|STYLE_[A-Z]+|CHART_[A-Z_]+|clr[A-Za-z0-9]+|"
                      r"[A-Z][A-Z0-9_]{2,})$")

KEYWORDS = set("""
if for while switch else do return break continue case default enum struct class void int double bool
string datetime long short uint uchar color input sinput static const true false new delete this
""".split())

CTRL_RE = re.compile(r"^(if|for|while|switch|else|do|case|default)\b")


def strip_line(line: str) -> tuple[str, bool]:
    """Drop // comments and string bodies. Returns (code, ends_inside_string)."""
    out, i, n, in_str = [], 0, len(line), False
    while i < n:
        c = line[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append('""')
            i += 1
            continue
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            break
        out.append(c)
        i += 1
    return "".join(out), in_str


def check(path: Path) -> tuple[list[str], dict]:
    raw = path.read_bytes()
    problems: list[str] = []
    stats = {"statements": 0, "funcs": 0, "loops": 0}

    if b"\t" in raw:
        problems.append("hard tabs present (MetaEditor will reformat them; harmless)")
    text = raw.decode("utf-8", errors="replace")
    code_text = "\n".join(strip_line(l)[0] for l in text.split("\n"))
    bad = sorted({c for c in text if ord(c) > 127})
    if bad:
        problems.append("non-ASCII bytes in source: " + " ".join(f"U+{ord(c):04X}" for c in bad[:8]) +
                        " - keep MT4 sources ASCII or MetaEditor may show mojibake")

    lines = text.split("\n")
    bal = {"{": 0, "(": 0, "[": 0}
    close = {"}": "{", ")": "(", "]": "["}
    in_block = in_enum = False
    min_depth_seen = 0
    for ln, line in enumerate(lines, 1):
        code, cont = strip_line(line)
        if "/*" in code:
            if "*/" not in code:
                in_block = True
                continue
        if in_block:
            if "*/" in code:
                in_block = False
            continue
        stripped = code.strip()
        before = dict(bal)                      # state entering this line
        for ch in code:
            if ch in bal:
                bal[ch] += 1
                min_depth_seen = min(min_depth_seen, min(bal.values()))
            elif ch in close:
                bal[close[ch]] -= 1
                if bal[close[ch]] < 0:
                    problems.append(f"line {ln}: '{ch}' closes nothing")
        if not stripped or stripped.startswith(("#", "//")):
            continue

        # enum bodies are comma separated, not semicolon terminated
        if re.match(r"^enum\b", stripped):
            in_enum = True
        if in_enum:
            if stripped.startswith("}"):
                in_enum = False
            continue
        if CTRL_RE.match(stripped):
            continue
        # unfinished constructs: inside an argument list, or a line that only closes one
        if before["("] > 0 or before["["] > 0:
            continue
        if code.count("(") + code.count("[") > code.count(")") + code.count("]"):
            continue
        is_header = bool(re.match(r"^[A-Za-z_][\w\s\*&<>,:\[\]]*\b[A-Za-z_]\w*\s*\([^;]*\)$", stripped))
        if is_header or cont:
            continue
        if stripped.endswith((";", "{", "}", ",", ":", "&&", "||", "+", "-", "*", "/")):
            continue
        if re.search(r"[=+\-*/<>(,]\s*$", stripped):
            continue
        problems.append(f"line {ln}: statement with no terminator: {stripped[:76]}")
        stats["statements"] += 1

    for k, v in bal.items():
        if v != 0:
            problems.append(f"unbalanced '{k}' at end of file (depth {v})")
    if min_depth_seen < 0:
        problems.append("a brace closed before it opened somewhere")

    # definitions, then every call site
    defined = set(re.findall(r"^\s*(?:[A-Za-z_]\w*\**\s+)+([A-Za-z_]\w*)\s*\([^;]*\)\s*$", code_text, re.M))
    stats["funcs"] = len(defined)
    calls = set(re.findall(r"(?<![.\w])([A-Za-z_]\w*)\s*\(", code_text))
    unknown = sorted(c for c in calls
                     if c not in BUILTIN and c not in defined and c not in KEYWORDS
                     and not CONST_RE.match(c) and not c.isupper())
    if unknown:
        problems.append("calls not on the vetted builtin list - confirm in the MQL4 reference: " + ", ".join(unknown))

    # declarations must be consistent: buffers vs SetIndexBuffer vs plot property groups vs array decls
    nb = None
    m = re.search(r"indicator_buffers\s+(\d+)", text)
    if m:
        nb = int(m.group(1))
        bufs = sorted(int(x) for x in re.findall(r"SetIndexBuffer\((\d+),", text))
        if set(bufs) != set(range(nb)):
            problems.append(f"indicator_buffers={nb} but SetIndexBuffer indices are {bufs}")
        arrays = re.findall(r"^double\s+(\w+)\[\];", text, re.M)
        if len(arrays) < nb:
            problems.append(f"{nb} buffers declared but only {len(arrays)} buffer arrays exist: {arrays}")
        labels = sorted({int(x) for x in re.findall(r"indicator_label(\d+)", text)})
        types = sorted({int(x) for x in re.findall(r"indicator_type(\d+)", text)})
        if labels and (max(labels) > nb or len(labels) != nb):
            problems.append(f"indicator_buffers={nb} but plot labels declared for {labels}")
        if types and len(types) != nb:
            problems.append(f"indicator_buffers={nb} but DRAW types declared for {types}")
        if "indicator_chart_window" in text and "indicator_separate_window" in text:
            problems.append("both chart_window and separate_window declared")

    return problems, stats


def main() -> int:
    files = sorted(MT4.glob("*.mq4"))
    if not files:
        print("no .mq4 files found in", MT4)
        return 1
    rc = 0
    for f in files:
        probs, st = check(f)
        head = (f"{f.name}: {st['funcs']} functions, {f.read_text().count(chr(10)) + 1} lines -> "
                + ("clean" if not probs else f"{len(probs)} issue(s)"))
        print(head)
        for p in probs:
            rc = 1
            print("   -", p)
    print("\nThis is a structure check, not a compiler: open each file in MetaEditor and press F7.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
