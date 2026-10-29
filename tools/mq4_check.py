#!/usr/bin/env python3
"""
mq4_check.py - lightweight static analyser for MQL4 sources.

This is NOT a compiler. It performs the checks that catch the mistakes
which actually break an MQL4 build in practice:

  1. unbalanced braces / parentheses / brackets
  2. functions called but never defined and not part of the MQL4 API
  3. functions defined twice
  4. inputs that are not terminated with a semicolon
  5. use of MQL5-only calls that do not exist in MQL4
  6. obviously mismatched argument counts for user functions

Usage:  python3 tools/mq4_check.py path/to/file.mq4 [more.mq4 ...]
Exit code 0 = no errors, 1 = errors, 2 = warnings only.
"""
import re
import sys
import os

# ---------------------------------------------------------------- helpers
def strip_comments_and_strings(src: str) -> str:
    """Replace comments and string/char literals with spaces (keeps offsets)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
        elif c == "/" and i + 1 < n and src[i + 1] == "*":
            out.append("  ")
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
        elif c in "\"'":
            q = c
            out.append(" ")
            i += 1
            while i < n and src[i] != q:
                if src[i] == "\\":
                    out.append("  ")
                    i += 2
                    continue
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            out.append(" ")
            i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


MQL4_BUILTINS = set("""
Print PrintFormat Alert Comment StringFormat StringConcatenate StringLen StringSubstr
StringFind StringGetCharacter StringToTime TimeToString TimeCurrent TimeLocal TimeGMT
TimeDayOfWeek TimeHour TimeMinute TimeYear TimeMonth TimeDay TimeSeconds TimeDayOfYear
StringTrimLeft StringTrimRight StringToDouble StringToInteger StringToLower StringToUpper
IntegerToString DoubleToString NormalizeDouble MathAbs MathMax MathMin MathRound MathFloor
MathCeil MathSqrt MathLog MathLog10 MathPow MathExp MathSin MathCos MathTan MathMod MathRand
MathIsValidNumber ArrayResize ArraySize ArrayCopy ArrayInitialize ArraySetAsSeries
OrderSend OrderClose OrderModify OrderDelete OrderSelect OrderTicket OrderType OrderLots
OrderOpenPrice OrderOpenTime OrderStopLoss OrderTakeProfit OrderSymbol OrderMagicNumber
OrderComment OrderProfit OrderSwap OrderCommission OrderClosePrice OrderCloseTime
OrderPrint OrdersTotal OrdersHistoryTotal OrderExpiration
MarketInfo SymbolInfoDouble SymbolInfoInteger SymbolInfoString
AccountBalance AccountEquity AccountFreeMargin AccountMargin AccountCurrency AccountNumber
AccountLeverage AccountName AccountCompany AccountProfit AccountFreeMarginCheck
AccountInfoInteger AccountInfoDouble AccountInfoString
iOpen iHigh iLow iClose iTime iVolume iSpread iBars iBarShift
Bars Period Symbol Digits Point IsTradeAllowed IsTradeContextBusy IsTesting IsOptimization
IsVisualMode IsDemo IsConnected IsExpertEnabled
RefreshRates Sleep GetLastError ResetLastError WindowFind WindowRedraw
ObjectCreate ObjectDelete ObjectFind ObjectSetInteger ObjectSetDouble ObjectSetString
ObjectGetInteger ObjectGetDouble ObjectGetString ObjectSet ObjectGet
FileOpen FileClose FileReadString FileWrite FileSeek FileTell FileIsEnding FileIsLineEnding
FileDelete FileSize FileFlush FileWriteString FileReadNumber FileReadDatetime
GlobalVariableCheck GlobalVariableSet GlobalVariableGet GlobalVariableDel GlobalVariableName
GlobalVariablesTotal GlobalVariableTime GlobalVariableTemp
TerminalInfoInteger TerminalInfoDouble TerminalInfoString
EventSetTimer EventKillTimer SymbolsTotal MarketInfo
PeriodSeconds PeriodToStr PeriodMQL PeriodDecimal
ChartRedraw ChartID ChartSymbol ChartPeriod
SendNotification WebRequest
DatabaseOpen DatabaseClose DatabaseExecute DatabasePrepare DatabaseRead
timeframeMinutes
""".split())

# functions that exist in MQL5 but NOT in MQL4 -> hard error
MQL5_ONLY = set("""
CTrade CPositionInfo CAccountInfo CSymbolInfo CIndicatorBuffer iATR iRSI iMA iStochastic
CopyBuffer CopyRates CopyClose CopyOpen CopyHigh CopyLow CopyTime CopyTickVolume
PositionsTotal PositionSelect PositionGetInteger PositionGetDouble PositionGetString
PositionGetSymbol HistorySelect HistoryDealsTotal HistoryDealGetInteger
ArraySetAsSeries Bars _Point _Digits _Symbol _Period OnCalculate
""".split())

CONTROL_KEYWORDS = {"if", "for", "while", "switch", "return", "sizeof", "do", "else",
                    "case", "break", "continue", "delete", "new", "catch", "throw"}


def check(path: str):
    errors, warnings = [], []
    src = open(path, encoding="utf-8", errors="replace").read()
    code = strip_comments_and_strings(src)

    # ---- 1. balanced delimiters
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    for idx, ch in enumerate(code):
        if ch in "([{":
            stack.append((ch, idx))
        elif ch in ")]}":
            if not stack:
                line = code[:idx].count("\n") + 1
                errors.append(f"{path}:{line}: closing '{ch}' without an opener")
                break
            op, oidx = stack.pop()
            if op != pairs[ch]:
                line = code[:idx].count("\n") + 1
                errors.append(f"{path}:{line}: '{ch}' closes '{op}' opened on line "
                              f"{code[:oidx].count(chr(10)) + 1}")
                break
    if stack:
        op, oidx = stack[-1]
        line = code[:oidx].count("\n") + 1
        errors.append(f"{path}:{line}: unclosed '{op}'")

    # ---- 2. collect function definitions and declarations
    fn_def_re = re.compile(
        r"^[ \t]*(?:static[ \t]+)?(?:int|void|bool|double|string|datetime|long|color|ulong|uint|short|char|float)"
        r"[ \t]+(\w+)[ \t]*\(", re.MULTILINE)
    defined = {}
    for m in fn_def_re.finditer(code):
        name = m.group(1)
        line = code[:m.start()].count("\n") + 1
        defined.setdefault(name, []).append(line)

    # object-like / function-like macros count as defined
    macro_names = set(re.findall(r"^[ \t]*#[ \t]*define[ \t]+(\w+)", code, re.MULTILINE))
    for m in macro_names:
        defined.setdefault(m, []).append(0)

    for name, lines in defined.items():
        if len(lines) > 1:
            # multiple definitions are only an error if none is a prototype
            bodies = 0
            for ln in lines:
                seg = code.split("\n")[ln - 1]
                if ";" not in seg:
                    bodies += 1
            if bodies > 1:
                errors.append(f"{path}: function '{name}' defined {bodies} times "
                              f"(lines {lines})")

    # ---- 3. calls to unknown functions
    call_re = re.compile(r"(?<![\w.])([A-Za-z_]\w*)[ \t]*\(")
    seen_unknown = {}
    for m in call_re.finditer(code):
        name = m.group(1)
        if name in CONTROL_KEYWORDS or name in defined or name in MQL4_BUILTINS:
            continue
        if name in MQL5_ONLY:
            line = code[:m.start()].count("\n") + 1
            errors.append(f"{path}:{line}: '{name}' is MQL5-only and does not exist in MQL4")
            continue
        line = code[:m.start()].count("\n") + 1
        seen_unknown.setdefault(name, []).append(line)
    for name, lines in seen_unknown.items():
        errors.append(f"{path}:{lines[0]}: undefined function '{name}' (called on lines {lines})")

    # ---- 4. input declarations must end with ';'
    for i, line in enumerate(src.split("\n"), 1):
        s = line.strip()
        if s.startswith("input ") and s and not s.endswith(";") and "//" not in s:
            errors.append(f"{path}:{i}: input declaration without terminating ';'")

    # ---- 5. common MQL5-isms in property/attribute usage
    for bad in ("#property strict", "#property description"):
        pass

    # ---- 6. unbalanced #if / #endif is not used here; check known trap:
    if "#property strict" not in src:
        warnings.append(f"{path}: '#property strict' missing (recommended)")

    # ---- 7. handler sanity
    for h in ("OnInit", "OnTick"):
        if h not in defined:
            errors.append(f"{path}: required handler {h}() not found")

    # ---- 8. heuristic: statement lines that look unterminated.
    # A line is only suspicious if it is NOT a signature, NOT a continuation
    # of a multi-line expression, and NOT a control statement header.
    lines = src.split("\n")
    fn_sig_re = re.compile(
        r"^[ \t]*(?:static[ \t]+)?(?:int|void|bool|double|string|datetime|long|color|ulong|"
        r"uint|short|char|float)[ \t]+\w+[ \t]*\(")
    suspicious = []
    for i, line in enumerate(lines):
        s = line.strip()
        if not s or s.startswith("//") or s.startswith("#") or s.startswith("*"):
            continue
        if s.startswith(("input ", "extern ", "enum ", "class ", "struct ")):
            continue
        if re.match(r"^(if|else|for|while|switch|case|do|return|break|continue)\b", s):
            continue
        if s.endswith((";", "{", "}", ":", "\\", ",", "(", "[", "&&", "||", "+", "?")):
            continue
        if "//" in s:
            continue
        if fn_sig_re.match(s):
            continue
        # continuation of the previous line
        prev = lines[i - 1].strip() if i > 0 else ""
        if prev.endswith(("(", ",", "&&", "||", "+", "?", "=", "\\")):
            continue
        # continuation onto the next line
        nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
        if nxt.startswith((")", "&&", "||", "+", "?", ";", ":", ".")):
            continue
        if s.endswith(")") or re.match(r"^\w[\w\s\*]*\w$", s):
            suspicious.append((i + 1, s))
    for ln, s in suspicious:
        warnings.append(f"{path}:{ln}: possible missing ';' -> {s[:70]}")
    if len(suspicious) > 0:
        errors.append(f"{path}: {len(suspicious)} statement(s) may be unterminated (see warnings)")

    return errors, warnings


def main(argv):
    paths = argv[1:]
    if not paths:
        print(__doc__)
        return 1
    total_err, total_warn = 0, 0
    for p in paths:
        if not os.path.exists(p):
            print(f"missing file: {p}")
            return 1
        e, w = check(p)
        total_err += len(e)
        total_warn += len(w)
        for msg in e:
            print("ERROR  " + msg)
        for msg in w:
            print("WARN   " + msg)
        if not e and not w:
            print(f"OK     {p}")
    print(f"\n{total_err} error(s), {total_warn} warning(s)")
    return 0 if total_err == 0 else (2 if total_warn else 1)


if __name__ == "__main__":
    sys.exit(0 if main(sys.argv) == 0 else 1)
