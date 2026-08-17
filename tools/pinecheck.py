#!/usr/bin/env python3
"""Structural linter for Pine Script sources.

Checks the mechanical rules that the TradingView editor only reports at
compile time:
  * wrapped/continuation lines must NOT be indented by a multiple of 4
    (Pine uses 4-space boundaries to open local blocks, so a wrapped line
    at a multiple of 4 is silently reparsed as a new statement/block)
  * balanced brackets
  * no tab characters (mixing tabs and spaces breaks block detection)
"""
import sys

CONT_END = ("+", "-", "*", "/", "?", ",", "%")
CONT_WORD = ("and", "or", "not")


def strip_code(s):
    """Blank out string literals and drop // comments."""
    out, in_str, i = [], None, 0
    while i < len(s):
        c = s[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == in_str:
                in_str = None
                out.append("S")
            i += 1
            continue
        if c in "\"'":
            in_str = c
            i += 1
            continue
        if c == "/" and i + 1 < len(s) and s[i + 1] == "/":
            break
        out.append(c)
        i += 1
    return "".join(out)


def check(path):
    errors = []
    depth = 0
    prev_continues = False
    starter_indent = 0

    for n, raw in enumerate(open(path).read().split("\n"), 1):
        if "\t" in raw:
            errors.append(f"{n}: TAB character present")
        if raw.strip() == "":
            continue
        code = strip_code(raw)
        if code.strip() == "":
            continue
        indent = len(raw) - len(raw.lstrip(" "))

        if prev_continues:
            if indent % 4 == 0:
                errors.append(
                    f"{n}: continuation indented {indent} (multiple of 4): {raw.strip()[:60]}")
            elif indent <= starter_indent:
                errors.append(
                    f"{n}: continuation indent {indent} <= starter {starter_indent}")
        else:
            starter_indent = indent

        depth += (code.count("(") - code.count(")")
                  + code.count("[") - code.count("]"))
        if depth < 0:
            errors.append(f"{n}: unbalanced closing bracket")
            depth = 0

        st = code.rstrip()
        ends_op = st.endswith(CONT_END) or any(st.endswith(" " + w) for w in CONT_WORD)
        if st.endswith(":"):
            ends_op = True
        if st.endswith("=>"):
            ends_op = False
        prev_continues = depth > 0 or ends_op

    if depth != 0:
        errors.append(f"EOF: bracket depth {depth} != 0")
    return errors


if __name__ == "__main__":
    paths = sys.argv[1:] or ["AutoTrendLines.pine"]
    bad = False
    for p in paths:
        errs = check(p)
        print(f"{p}: {'OK - no structural problems found.' if not errs else 'ERRORS:'}")
        for e in errs:
            print("   ", e)
        bad = bad or bool(errs)
    sys.exit(1 if bad else 0)
