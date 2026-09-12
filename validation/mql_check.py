"""Lightweight sanity checks for the MQL sources.

MetaEditor cannot run in this sandbox, so this performs the most valuable
static checks:
  * balanced (), {}, [] and properly closed string literals
  * version-appropriate API usage (MQL4-only vs MQL5-only tokens)
  * all called helper functions are defined
  * StringFormat placeholder vs argument count (rough)
  * input identifier duplication
"""

import re
import sys
from collections import Counter

ROOT = "/home/user/kkk"

MQL5_ONLY = ["input group", "ColorToARGB", "OBJPROP_RAY_RIGHT", "OBJPROP_ANCHOR",
             "OBJPROP_BGCOLOR", "OBJPROP_BORDER_TYPE", "BORDER_FLAT",
             "ObjectsDeleteAll(0,"]
MQL4_ONLY = ["#property strict", "OBJPROP_RAY)", "ObjectSetInteger(name,",
             "ChartRedraw();", "ObjectDelete(name)"]


def load(path):
    with open(path) as f:
        return f.read()


def strip_comments_and_strings(src):
    """Return src with comments removed and string literals blanked."""
    out = []
    i = 0
    in_str = False
    in_line = False
    in_block = False
    while i < len(src):
        ch = src[i]
        nxt = src[i + 1] if i + 1 < len(src) else ""
        if in_line:
            if ch == "\n":
                in_line = False
                out.append("\n")
        elif in_block:
            if ch == "*" and nxt == "/":
                in_block = False
                i += 1
                out.append("  ")
            elif ch == "\n":
                out.append("\n")
            else:
                out.append(" ")
        elif in_str:
            if ch == "\\":
                i += 1
                out.append("  ")
            elif ch == '"':
                in_str = False
                out.append('"')
            else:
                out.append(" ")
        else:
            if ch == "/" and nxt == "/":
                in_line = True
                i += 1
                out.append("  ")
            elif ch == "/" and nxt == "*":
                in_block = True
                i += 1
                out.append("  ")
            elif ch == '"':
                in_str = True
                out.append('"')
            else:
                out.append(ch)
        i += 1
    return "".join(out)


def check_balance(src, path):
    errs = []
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    line = 1
    in_str = False
    in_line_comment = False
    in_block_comment = False
    i = 0
    while i < len(src):
        ch = src[i]
        nxt = src[i + 1] if i + 1 < len(src) else ""
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                line += 1
        elif in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 1
            elif ch == "\n":
                line += 1
        elif in_str:
            if ch == "\\":
                i += 1
            elif ch == '"':
                in_str = False
            elif ch == "\n":
                errs.append(f"{path}:{line}: unclosed string")
                in_str = False
                line += 1
        else:
            if ch == "/" and nxt == "/":
                in_line_comment = True
                i += 1
            elif ch == "/" and nxt == "*":
                in_block_comment = True
                i += 1
            elif ch == '"':
                in_str = True
            elif ch in "([{":
                stack.append((ch, line))
            elif ch in ")]}":
                if not stack or stack[-1][0] != pairs[ch]:
                    errs.append(f"{path}:{line}: unbalanced '{ch}'")
                else:
                    stack.pop()
            elif ch == "\n":
                line += 1
        i += 1
    for ch, ln in stack:
        errs.append(f"{path}:{ln}: unclosed '{ch}'")
    if in_str or in_block_comment:
        errs.append(f"{path}: unterminated string/comment at EOF")
    return errs


def check_tokens(src, path, banned, label):
    errs = []
    code = strip_comments_and_strings(src)
    for tok in banned:
        if tok in code:
            errs.append(f"{path}: {label} token found: {tok!r}")
    return errs


def check_functions(src, path):
    errs = []
    code = strip_comments_and_strings(src)
    defined = set(re.findall(r"\b(?:void|bool|int|double|string|datetime|color)\s+([A-Za-z_]\w*)\s*\(", code))
    called = set(re.findall(r"\b([A-Za-z_]\w*)\s*\(", code))
    mql_builtins = {"ObjectCreate", "ObjectFind", "ObjectSetInteger", "ObjectSetDouble",
                    "ObjectSetString", "ObjectDelete", "ObjectsDeleteAll", "ObjectName",
                    "ObjectGetInteger", "ObjectGetDouble", "ObjectGetString", "Alert",
                    "PlaySound", "SendNotification", "SendMail", "ChartRedraw",
                    "IndicatorSetString", "IndicatorShortName", "TimeToStruct",
                    "StructToTime", "TimeToString", "TimeCurrent", "StringFormat",
                    "StringLen", "StringSubstr", "DoubleToString", "IntegerToString",
                    "MathAbs", "MathRand", "MathMax", "MathMin", "PeriodSeconds",
                    "ArraySize", "ArrayResize", "ArrayInitialize", "iTime", "iHigh",
                    "iLow", "iOpen", "iClose", "SymbolInfoDouble", "Print", "PrintFormat",
                    "Comment", "GetTickCount", "ChartID", "Bars", "NormalizeDouble",
                    "StringConcatenate", "StringFind", "SymbolInfoInteger",
                    "TimeDayOfWeek", "MathFloor", "MathCeil", "MathSqrt", "MathPow",
                    "CopyTime", "CopyHigh", "CopyLow", "CopyClose", "ArraySetAsSeries",
                    "MathIsValidNumber", "CharToString", "StringToInteger",
                    "StringToDouble", "ObjectMove", "ObjectSetText", "WindowFirstVisibleBar",
                    "ColorToARGB", "ColorToString", "StringToColor",
                    "ArrayCopy", "EventSetTimer", "Sleep", "FileWrite", "FileOpen",
                    "FileClose", "GlobalVariableSet", "GlobalVariableGet"}
    for fn in sorted(called):
        if fn in defined or fn in mql_builtins:
            continue
        if re.search(r"\b(if|for|while|switch|return|sizeof|string|enum)\b", fn):
            continue
        errs.append(f"{path}: call to undefined function '{fn}()'")
    return errs


def split_args(s, i):
    """Split argument text starting at index i, respecting nested parens/strings."""
    args = []
    depth = 0
    cur = []
    in_str = False
    while i < len(s):
        ch = s[i]
        if in_str:
            if ch == "\\":
                cur.append(ch); i += 1
                if i < len(s): cur.append(s[i])
            elif ch == '"':
                in_str = False; cur.append(ch)
            else:
                cur.append(ch)
        else:
            if ch == '"':
                in_str = True; cur.append(ch)
            elif ch == "(":
                depth += 1; cur.append(ch)
            elif ch == ")":
                if depth == 0:
                    break
                depth -= 1; cur.append(ch)
            elif ch == "," and depth == 0:
                args.append("".join(cur).strip()); cur = []
            else:
                cur.append(ch)
        i += 1
    if "".join(cur).strip():
        args.append("".join(cur).strip())
    return args


def check_stringformats(src, path):
    errs = []
    for m in re.finditer(r'StringFormat\(\s*"((?:[^"\\]|\\.)*)"\s*(,|\))', src):
        fmt = m.group(1)
        specs = re.findall(r"%(?:[-+0 #]*\d*(?:\.\d+)?)?[diufFeEgGxXosc]", fmt)
        if m.group(2) == ")":
            nargs = 0
        else:
            args = split_args(src, m.end())
            nargs = len(args)
        if len(specs) != nargs:
            errs.append(f"{path}: StringFormat mismatch: {len(specs)} specs vs {nargs} args "
                        f"in {fmt[:50]!r}")
    return errs


def check_duplicate_inputs(src, path):
    errs = []
    code = strip_comments_and_strings(src)
    names = re.findall(r"\binput\s+[A-Za-z_][\w]*\s+(\w+)\s*=", code)
    for n, c in Counter(names).items():
        if c > 1:
            errs.append(f"{path}: duplicate input '{n}'")
    return errs


def check_objset_form(src, path):
    """ObjectSetInteger/Double/String must use the chart-id-first form
    (0, name, prop, value) - the only form accepted by the unified
    MetaEditor's MQL compiler (see compile errors reported by the user)."""
    errs = []
    for m in re.finditer(r"\bObjectSet(?:Integer|Double|String)\s*\(", src):
        rest = src[m.end():]
        if not re.match(r"\s*0\s*,", rest):
            line = src[:m.start()].count("\n") + 1
            errs.append(f"{path}:{line}: ObjectSet* call must use the chart-id form 'ObjectSetXxx(0, name, ...)'")
    return errs


def main():
    all_errs = []
    for fname, banned_mt5, banned_mt4 in (
            ("PremiumDiscount.mq5", MQL4_ONLY, []),
            ("PremiumDiscount.mq4", MQL5_ONLY, [])):
        path = f"{ROOT}/{fname}"
        src = load(path)
        all_errs += check_balance(src, path)
        all_errs += check_tokens(src, path, banned_mt5, "MQL4-only")
        all_errs += check_tokens(src, path, banned_mt4, "MQL5-only")
        all_errs += check_functions(src, path)
        all_errs += check_stringformats(src, path)
        all_errs += check_duplicate_inputs(src, path)
        all_errs += check_objset_form(src, path)
        print(f"{fname}: {len(src)} chars, {src.count(chr(10))} lines")

    if all_errs:
        print(f"\n{len(all_errs)} issue(s):")
        for e in all_errs:
            print("  ", e)
        sys.exit(1)
    print("\nAll MQL sanity checks passed.")


if __name__ == "__main__":
    main()
