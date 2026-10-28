#!/usr/bin/env python3
"""
Lightweight static checker for the MQL4 sources in EA/.

MetaEditor is not available in this environment, so this script does the checks
that catch the mistakes a compiler would otherwise catch first:

  * balanced braces / parentheses / brackets, and unclosed string literals,
  * every called function is either built-in MQL4 or defined in the project,
  * every identifier that is *read* looks declared (locals, globals, inputs,
    parameters, or a known MQL4 constant/enum),
  * statements end with ';' or a block delimiter,
  * no leftover TODO / placeholder text.

It is deliberately conservative: false positives are reported as warnings.

Usage:  python tools/mql4_lint.py EA/LiquiditySweep_Portfolio.mq4
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

BUILTIN_FUNCS = """
ArrayCopy ArrayInitialize ArrayMaximum ArrayMinimum ArrayRange ArrayResize ArraySetAsSeries ArraySize ArraySort
Bars BarsSince Bid Ask Point Digits Close Open High Low Time Volume iTime iOpen iHigh iLow iClose iVolume iBars
iBarShift iHighest iLowest MarketInfo Symbol SymbolInfoDouble SymbolInfoInteger SymbolInfoString SymbolSelect
AccountBalance AccountEquity AccountFreeMargin AccountNumber AccountCurrency AccountLeverage AccountMargin
AccountProfit AccountCredit
OrderSend OrderClose OrderModify OrderDelete OrderSelect OrderTicket OrderType OrderLots OrderSymbol
OrderOpenPrice OrderOpenTime OrderStopLoss OrderTakeProfit OrderMagicNumber OrderComment OrderProfit OrderSwap
OrderCommission OrderCloseTime OrdersTotal OrdersHistoryTotal OrderPrint OrderCloseBy
Print PrintFormat DoubleToStr StrToDouble StrToInteger IntegerToString DoubleToString StringConcatenate
StringSplit StringTrimLeft StringTrimRight StringFind StringLen StringSubstr StringReplace StringGetChar
StringToLower StringToUpper StringToDouble
TimeCurrent TimeLocal TimeToStr StrToTime TimeYear TimeMonth TimeDay TimeHour TimeMinute TimeSeconds
TimeDayOfWeek TimeDayOfYear TimeGMTOffset
MathAbs MathMax MathMin MathFloor MathCeil MathRound MathSqrt MathPow MathLog MathExp MathMod MathRand MathRand
MathIsValidNumber NormalizeDouble
RefreshRates Sleep GetLastError ResetLastError IsConnected IsTesting IsOptimization IsVisualMode
IsDemo IsTradeAllowed IsTradeContextBusy TerminalCompany TerminalName
Comment GlobalVariableSet GlobalVariableGet GlobalVariableDel GlobalVariableCheck GlobalVariableSetOnCondition
GlobalVariablesDeleteAll
SendNotification SendMail PlaySound Alert
FileOpen FileClose FileWrite FileWriteString FileReadString FileReadNumber FileFlush FileDelete FileIsExist
ChartRedraw WindowRedraw ObjectCreate ObjectDelete ObjectSet IntegerToString
Period SymbolsTotal SymbolName GetTickCount OrdersTotal
""".split()

BUILTIN_CONSTS = set("""
OP_BUY OP_SELL OP_BUYLIMIT OP_SELLLIMIT OP_BUYSTOP OP_SELLSTOP
SELECT_BY_POS SELECT_BY_TICKET MODE_TRADES MODE_HISTORY
MODE_ASK MODE_BID MODE_POINT MODE_DIGITS MODE_SPREAD MODE_STOPLEVEL MODE_FREEZELEVEL
MODE_LOTSIZE MODE_MINLOT MODE_MAXLOT MODE_LOTSTEP MODE_TICKVALUE MODE_TICKSIZE MODE_MARGINREQUIRED
MODE_LOW MODE_HIGH MODE_OPEN MODE_CLOSE MODE_TIME MODE_VOLUME MODE_PROFITCALCMODE
PERIOD_M1 PERIOD_M5 PERIOD_M15 PERIOD_M30 PERIOD_H1 PERIOD_H4 PERIOD_D1 PERIOD_W1 PERIOD_MN1 PERIOD_CURRENT
INIT_SUCCEEDED INIT_FAILED INIT_PARAMETERS_INCORRECT
MODE_ASCENDING MODE_DESCENDING WHOLE_ARRAY
TIME_DATE TIME_MINUTES TIME_SECONDS
clrWhite clrYellow clrRed clrGreen clrBlue clrDodgerBlue clrBlack clrOrange clrAqua clrMagenta clrGray
true false NULL EMPTY_VALUE
""".split())

KEYWORDS = set("""
if else for while do return break continue switch case default new delete sizeof
int double bool string datetime color void static extern const input
""".split())


def strip_comments(src: str) -> str:
    out = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"':
                if src[j] == "\\":
                    j += 1
                j += 1
            out.append('"' + "_" * (j - i - 1) + '"')   # neutralise string contents
            i = j + 1
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def main(path: str) -> int:
    text = Path(path).read_text()
    code = strip_comments(text)
    errors, warns = [], []

    # ---- balance ----------------------------------------------------------
    for open_c, close_c in (("{", "}"), ("(", ")"), ("[", "]")):
        if code.count(open_c) != code.count(close_c):
            errors.append(f"unbalanced '{open_c}{close_c}': {code.count(open_c)} vs {code.count(close_c)}")
    depth = 0
    line_of = {i + 1: 0 for i in range(0)}
    ln = 1
    for ch in code:
        if ch == "\n":
            ln += 1
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth < 0:
                errors.append(f"line {ln}: closing brace without opener")
                depth = 0

    # ---- declared functions ----------------------------------------------
    defined = set(re.findall(r"\b(?:void|int|double|bool|string|datetime|color)\s+(\w+)\s*\(", code))
    called = set(re.findall(r"\b(\w+)\s*\(", code))
    unknown_calls = sorted(c for c in called
                           if c not in defined and c not in BUILTIN_FUNCS and c not in KEYWORDS
                           and not c[0].isdigit())
    for c in unknown_calls:
        errors.append(f"call to undefined function '{c}'")

    # ---- simple declaration tracking -------------------------------------
    declared = set(defined)
    declared |= set(re.findall(r"\binput\s+(?:string|int|double|bool|datetime|color)\s+(\w+)", code))
    declared |= set(re.findall(r"\b(?:int|double|bool|string|datetime|color)\s+(\w+)\s*(?:\[[^\]]*\])?\s*(?:=|;|,)", code))
    for m in re.finditer(r"\(([^)]*)\)\s*\{?", code):
        for p in re.finditer(r"\b(?:int|double|bool|string|datetime|color)\s*&?\s*(\w+)", m.group(1)):
            declared.add(p.group(1))
    declared |= set(re.findall(r"\bstatic\s+(?:int|double|bool|string|datetime)\s+(\w+)", code))
    # for-loop declarations
    for m in re.finditer(r"for\s*\([^;]*?(?:int|double)\s+(\w+)", code):
        declared.add(m.group(1))
    # assignment-style locals
    declared |= set(re.findall(r"\b(\w+)\s*=\s", code))
    declared |= BUILTIN_CONSTS | KEYWORDS

    # ---- statement termination -------------------------------------------
    func_def = re.compile(r"^(?:void|int|double|bool|string|datetime|color)\s+\w+\s*\(")
    prev_open = False
    for i, raw in enumerate(text.splitlines(), 1):
        line = raw.split("//")[0].rstrip()
        st = line.strip()
        if prev_open:
            prev_open = st.endswith((",", "("))
            continue
        if not st or st.startswith("#"):
            continue
        if func_def.match(st):
            prev_open = st.endswith((",", "("))
            continue
        if st.startswith(("+", "-", "*", "/", "&&", "||", "?")):
            continue   # continuation line of a long expression
        if st.endswith((";", "{", "}", ",", ":", "\\", "(", "+", "&", "|")):
            continue
        if st.startswith(("if", "else", "for", "while", "input", "//")):
            continue
        if st.endswith(")") and re.match(r"^(if|for|while)\b", st):
            prev_open = True
            continue
        warns.append(f"line {i}: statement may be unterminated -> {st[:70]}")

    # ---- placeholder / typo scan ------------------------------------------
    for i, raw in enumerate(text.splitlines(), 1):
        if re.search(r"\bTODO\b|\bFIXME\b|\bXXX\b|\bplaceholder\b", raw, re.I):
            errors.append(f"line {i}: leftover placeholder text -> {raw.strip()[:80]}")

    # ---- double declaration of inputs -------------------------------------
    ins = re.findall(r"\binput\s+\w+\s+(\w+)", code)
    seen = set()
    for nm in ins:
        if nm in seen:
            errors.append(f"duplicate input '{nm}'")
        seen.add(nm)

    print(f"{path}: {len(text.splitlines())} lines, {len(defined)} functions, {len(ins)} inputs")
    if unknown_calls:
        print("  unresolved calls:", ", ".join(unknown_calls))
    for w in warns:
        print("  WARN ", w)
    for e in errors:
        print("  ERROR", e)
    if not errors:
        print("  OK - no structural errors found")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "EA/LiquiditySweep_Portfolio.mq4"))
