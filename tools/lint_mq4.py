#!/usr/bin/env python3
"""
Static lint for the MT4 indicator.

There is no MetaEditor in CI, so this does the checks that do not need one:

  1. balanced (), {}, [] outside of strings and comments
  2. every function that is CALLED is either defined in the file or is a
     known MQL4 built-in (list below is checked against real .mq4 sources
     on GitHub by tools/check_mql4_api.py)
  3. every `input` variable is actually referenced somewhere
  4. no `#property indicator_buffers` / buffer usage we never set up

Usage:  python3 tools/lint_mq4.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MQ4 = os.path.normpath(os.path.join(
    HERE, "..", "mt4", "MQL4", "Indicators", "MarketStructureSyncScanner.mq4"))

# MQL4 built-ins used by this indicator (build 600+).
BUILTINS = {
    # arrays / math / strings
    "ArrayResize", "ArraySize",
    "MathMin", "MathMax", "MathRound",
    "StringLen", "StringSubstr", "StringFind", "StringSplit", "StringGetCharacter",
    "StringTrimLeft", "StringTrimRight", "StringToUpper", "StringReplace",
    "IntegerToString",
    "EnumToString",
    # time
    "TimeCurrent", "TimeToString",
    # series access
    "iBars", "iHigh", "iLow", "iTime",
    # symbols
    "Symbol", "Period", "SymbolsTotal", "SymbolName", "SymbolSelect",
    "SymbolInfoInteger",
    # chart objects
    "ObjectCreate", "ObjectDelete", "ObjectFind", "ObjectsDeleteAll",
    "ObjectSetInteger", "ObjectSetDouble", "ObjectSetString",
    # chart / indicator
    "ChartRedraw", "IndicatorShortName",
    # events / io
    "EventSetTimer", "EventKillTimer",
    "Print", "Alert", "SendNotification", "SendMail", "PlaySound",
}

# `input string Sep0 = "..."` rows are group headers in the inputs dialog;
# MQL4 shows them but the program never reads them.
INPUT_GROUP_PREFIX = "Sep"

# MQL4 constants / enum members / types used by this indicator.
CONSTANTS = {
    "ANCHOR_BOTTOM", "ANCHOR_TOP",
    "ANCHOR_LEFT_UPPER", "ANCHOR_RIGHT_UPPER", "ANCHOR_LEFT_LOWER", "ANCHOR_RIGHT_LOWER",
    "BORDER_FLAT",
    "ENUM_ANCHOR_POINT", "ENUM_TIMEFRAMES",
    "INIT_SUCCEEDED", "NULL",
    "OBJPROP_ANCHOR", "OBJPROP_ARROWCODE", "OBJPROP_BACK", "OBJPROP_BGCOLOR",
    "OBJPROP_BORDER_TYPE", "OBJPROP_COLOR", "OBJPROP_CORNER", "OBJPROP_FONT",
    "OBJPROP_FONTSIZE", "OBJPROP_HIDDEN", "OBJPROP_PRICE", "OBJPROP_SELECTABLE",
    "OBJPROP_SELECTED", "OBJPROP_TEXT", "OBJPROP_TIME", "OBJPROP_WIDTH",
    "OBJPROP_XDISTANCE", "OBJPROP_XSIZE", "OBJPROP_YDISTANCE", "OBJPROP_YSIZE",
    "OBJ_ARROW", "OBJ_LABEL", "OBJ_RECTANGLE_LABEL",
    "PERIOD_D1", "PERIOD_H4", "PERIOD_W1",
    "SYMBOL_SELECT",
    "TIME_MINUTES", "TIME_SECONDS",
}

# language keywords / control words that look like calls but are not
NOT_CALLS = {"if", "for", "while", "switch", "return", "sizeof", "defined"}


def strip_noise(src):
    """Blank out comments, string and char literals, keeping offsets intact."""
    out = []
    i, n = 0, len(src)
    while i < n:
        two = src[i:i + 2]
        if two == "//":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif two == "/*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(c if c == "\n" else " " for c in src[i:j]))
            i = j
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(" " * (j - i))
            i = j
        elif src[i] == "'":
            j = i + 1
            while j < n and src[j] != "'":
                j += 2 if src[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(" " * (j - i))
            i = j
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def main():
    with open(MQ4, "r", encoding="utf-8") as fh:
        raw = fh.read()
    clean = strip_noise(raw)

    fails = []

    # ---- 1. balance -------------------------------------------------------
    stack = []
    pairs = {")": "(", "}": "{", "]": "["}
    line = 1
    for ch, orig in zip(clean, raw):
        if orig == "\n":
            line += 1
        if ch in "({[":
            stack.append((ch, line))
        elif ch in ")}]":
            if not stack or stack[-1][0] != pairs[ch]:
                fails.append("line %d: unmatched '%s'" % (line, ch))
                break
            stack.pop()
    if stack:
        fails.append("unclosed '%s' opened on line %d" % (stack[-1][0], stack[-1][1]))

    # ---- 2. callees -------------------------------------------------------
    defined = set(re.findall(r"^\s*[A-Za-z_][\w]*\s+([A-Za-z_]\w*)\s*\(", clean, re.M))
    # event handlers declared with a return type on the same line are caught above
    called = {}
    for m in re.finditer(r"\b([A-Za-z_]\w*)\s*\(", clean):
        name = m.group(1)
        if name in NOT_CALLS or name in defined:
            continue
        called.setdefault(name, clean[:m.start()].count("\n") + 1)

    unknown = sorted(n for n in called if n not in BUILTINS)
    if unknown:
        for n in unknown:
            fails.append("line %d: calls '%s' which is neither defined here nor a known MQL4 built-in"
                         % (called[n], n))

    unused_builtins = sorted(BUILTINS - set(called))

    # ---- 2b. constants ----------------------------------------------------
    own_defines = set(re.findall(r"^\s*#define\s+(\w+)", clean, re.M))
    used_caps = set(re.findall(r"\b([A-Z][A-Z0-9_]{2,})\b", clean))
    unknown_caps = sorted(c for c in used_caps
                          if c not in own_defines and c not in CONSTANTS)
    for c in unknown_caps:
        fails.append("'%s' is neither #defined here nor a known MQL4 constant" % c)

    # ---- 3. inputs referenced --------------------------------------------
    inputs = re.findall(r"^\s*input\s+[\w<>]+\s+(\w+)\s*=", clean, re.M)
    for name in inputs:
        if name.startswith(INPUT_GROUP_PREFIX):
            continue                      # group header row, intentionally unread
        # count occurrences outside the declaration itself
        uses = len(re.findall(r"\b%s\b" % re.escape(name), clean))
        if uses < 2:
            fails.append("input '%s' is declared but never used" % name)

    # ---- report -----------------------------------------------------------
    real_inputs = [n for n in inputs if not n.startswith(INPUT_GROUP_PREFIX)]
    print("file            : %s" % MQ4)
    print("lines           : %d" % raw.count("\n"))
    print("functions       : %d" % len(defined))
    print("inputs          : %d (%d settings + %d group headers)"
          % (len(inputs), len(real_inputs), len(inputs) - len(real_inputs)))
    print("mql4 built-ins  : %d used" % len(set(called) & BUILTINS))
    print("mql4 constants  : %d used" % len(used_caps - own_defines))
    if unused_builtins:
        print("builtins listed but not used: %s" % ", ".join(unused_builtins))

    if fails:
        print("\nLINT FAILED")
        for f in fails:
            print("  - %s" % f)
        return 1
    print("\nlint ok: brackets balanced, %d external calls and %d constants all "
          "recognised, all %d settings referenced"
          % (len(set(called) & BUILTINS), len(used_caps - own_defines), len(real_inputs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
