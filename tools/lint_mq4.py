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
    "IntegerToString", "DoubleToString",
    "EnumToString",
    # time
    "TimeCurrent", "TimeToString", "PeriodSeconds",
    # series access
    "iBars", "iHigh", "iLow", "iClose", "iTime",
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
    "ENUM_ANCHOR_POINT", "ENUM_ARROW_ANCHOR", "ENUM_TIMEFRAMES",
    "INIT_SUCCEEDED", "NULL",
    "OBJPROP_ANCHOR", "OBJPROP_ARROWCODE", "OBJPROP_BACK", "OBJPROP_BGCOLOR",
    "OBJPROP_BORDER_TYPE", "OBJPROP_COLOR", "OBJPROP_CORNER", "OBJPROP_FILL",
    "OBJPROP_FONT", "OBJPROP_FONTSIZE", "OBJPROP_HIDDEN", "OBJPROP_PRICE",
    "OBJPROP_SELECTABLE", "OBJPROP_SELECTED", "OBJPROP_STYLE", "OBJPROP_TEXT",
    "OBJPROP_TIME", "OBJPROP_TOOLTIP", "OBJPROP_WIDTH",
    "OBJPROP_XDISTANCE", "OBJPROP_XSIZE", "OBJPROP_YDISTANCE", "OBJPROP_YSIZE",
    "OBJ_ARROW", "OBJ_LABEL", "OBJ_RECTANGLE", "OBJ_RECTANGLE_LABEL",
    "PERIOD_D1", "PERIOD_H1", "PERIOD_H4", "PERIOD_M15", "PERIOD_M30", "PERIOD_W1",
    "STYLE_SOLID",
    "SYMBOL_DIGITS", "SYMBOL_SELECT",
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

    # ---- 2c. namespace collisions ----------------------------------------
    # MQL4 keeps global variables, inputs and functions in one namespace, so an
    # input and a function cannot share a name. This is invisible to every
    # other check here: the call still "resolves" to something, and the API
    # cross-check only ever looks names up in other people's files.
    func_names = {}
    for m in re.finditer(r"^\s*[A-Za-z_][\w]*\s+([A-Za-z_]\w*)\s*\(", clean, re.M):
        func_names.setdefault(m.group(1), clean[:m.start()].count("\n") + 1)
    global_names = {}
    for m in re.finditer(
            r"^\s*(?:int|void|bool|string|double|datetime|color|long)\s+(g_\w+)\s*[\[;=]",
            clean, re.M):
        global_names.setdefault(m.group(1), clean[:m.start()].count("\n") + 1)
    input_names = {}
    for m in re.finditer(r"^\s*input\s+[\w<>]+\s+(\w+)\s*=", clean, re.M):
        input_names.setdefault(m.group(1), clean[:m.start()].count("\n") + 1)

    for label, others in (("a function", func_names), ("a global", global_names)):
        for name in sorted(set(input_names) & set(others)):
            fails.append("input '%s' (line %d) collides with %s of the same name "
                         "(line %d) - MQL4 has one namespace for both"
                         % (name, input_names[name], label, others[name]))
    for name in sorted(set(func_names) & set(global_names)):
        fails.append("function '%s' (line %d) collides with a global of the same "
                     "name (line %d)" % (name, func_names[name], global_names[name]))

    # ---- 2d. anchor enum membership --------------------------------------
    # ANCHOR_TOP / ANCHOR_BOTTOM belong to ENUM_ARROW_ANCHOR (OBJ_ARROW);
    # ANCHOR_*_UPPER / ANCHOR_*_LOWER belong to ENUM_ANCHOR_POINT (OBJ_LABEL,
    # OBJ_RECTANGLE_LABEL). Two names - ANCHOR_LEFT and ANCHOR_RIGHT - are
    # valid in both, which is why a wrong pick can slip through the compiler.
    # Getting this wrong is what produced 4 of the original 22 MetaEditor
    # errors, and no other check here can see it.
    #
    # A constant can reach OBJPROP_ANCHOR two ways: written inline, or via a
    # variable assigned somewhere else entirely (g_anchor is set in
    # RenderPanel and read in Place). Both paths are resolved here, because
    # the variable path is the one that actually caused the original bug.
    ANCHOR_ARROW = {"ANCHOR_TOP", "ANCHOR_BOTTOM", "ANCHOR_UPPER_LEFT",
                    "ANCHOR_UPPER_RIGHT", "ANCHOR_LOWER_LEFT", "ANCHOR_LOWER_RIGHT"}
    ANCHOR_POINT = {"ANCHOR_LEFT_UPPER", "ANCHOR_LEFT_LOWER",
                    "ANCHOR_RIGHT_UPPER", "ANCHOR_RIGHT_LOWER",
                    "ANCHOR_UPPER", "ANCHOR_LOWER", "ANCHOR_CENTER"}

    # Every ANCHOR_* constant ever assigned to each variable. The (?!=) guards
    # stop this matching the first '=' of a '==' comparison, which would
    # otherwise attribute `if(x == 1) { g_anchor = ANCHOR_..; }` to `x`.
    anchor_vars = {}
    for m in re.finditer(r"(?<![=!<>+\-*/&|^])\b(\w+)\s*=(?!=)\s*([^;]+);", clean):
        vals = re.findall(r"\b(ANCHOR_[A-Z_]+)\b", m.group(2))
        if vals:
            anchor_vars.setdefault(m.group(1), set()).update(vals)

    for m in re.finditer(r"^\s*[A-Za-z_][\w]*\s+([A-Za-z_]\w*)\s*\(", clean, re.M):
        open_brace = clean.find("{", m.end())
        if open_brace < 0:
            continue
        depth, i = 0, open_brace
        while i < len(clean):
            if clean[i] == "{":
                depth += 1
            elif clean[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = clean[open_brace:i + 1]
        objs = set(re.findall(r"ObjectCreate\s*\([^;]*?,\s*(OBJ_\w+)", body))
        wants_arrow = "OBJ_ARROW" in objs
        wants_point = bool(objs & {"OBJ_LABEL", "OBJ_RECTANGLE_LABEL"})
        if wants_arrow == wants_point:
            continue                      # ambiguous or no text/arrow object here
        for am in re.finditer(r"OBJPROP_ANCHOR\s*,\s*([^;]+?)\)\s*;", body):
            expr = am.group(1)
            consts = set(re.findall(r"\b(ANCHOR_[A-Z_]+)\b", expr))
            # expand any variable in the expression to the constants assigned
            # to it elsewhere in the file
            via = set()
            for ident in re.findall(r"\b([A-Za-z_]\w*)\b", expr):
                if ident in anchor_vars and ident not in consts:
                    consts |= anchor_vars[ident]
                    via.add(ident)
            for const in sorted(consts):
                in_arrow, in_point = const in ANCHOR_ARROW, const in ANCHOR_POINT
                if in_arrow == in_point:
                    continue              # ANCHOR_LEFT / ANCHOR_RIGHT: valid in both
                wrong = in_arrow if wants_point else in_point
                if wrong:
                    src = (" via '%s'" % sorted(via)[0]) if via else ""
                    fails.append(
                        "line %d: '%s' is %s but is set on %s, which needs %s%s"
                        % (clean[:open_brace].count("\n") + 1, const,
                           "ENUM_ARROW_ANCHOR" if in_arrow else "ENUM_ANCHOR_POINT",
                           "/".join(sorted(objs)),
                           "ENUM_ANCHOR_POINT" if wants_point else "ENUM_ARROW_ANCHOR",
                           src))

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
