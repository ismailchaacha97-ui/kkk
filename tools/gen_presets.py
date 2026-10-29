#!/usr/bin/env python3
"""
gen_presets.py - build MetaTrader 4 .set files from the EA's own inputs.

Reading the defaults straight out of the .mq4 removes the usual failure mode
where a preset silently stops matching the EA after a rename: every key in a
preset is validated against the declared inputs and the script fails loudly
if one no longer exists.

The .set format is the plain "Name=Value" form MT4 writes with the Save
button; enum inputs are written as their integer value.

Usage: python3 tools/gen_presets.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EA = os.path.join(ROOT, "mt4", "Experts", "QuantEdge", "FTMO_QuantEdge.mq4")
OUT = os.path.join(ROOT, "mt4", "Presets")

# MT4 stores colours as BGR integers in .set files
COLOR_MAP = {
    "Black": 0, "White": 16777215, "Red": 255, "Lime": 65280, "Blue": 16711680,
    "Yellow": 65535, "Aqua": 16776960, "Magenta": 16711935, "Gold": 55295,
    "Orange": 42495, "OrangeRed": 17919, "DodgerBlue": 16748574,
    "DeepSkyBlue": 16760576, "Silver": 12632256, "Gray": 8421504,
}

INPUT_RE = re.compile(
    r"^input\s+(\w+)\s+(\w+)\s*=\s*([^;]+);", re.MULTILINE)
ENUM_RE = re.compile(r"enum\s+(\w+)\s*\{(.*?)\}", re.DOTALL)


def parse_inputs(src):
    enums = {}
    for m in ENUM_RE.finditer(src):
        values = {}
        for line in m.group(2).split("\n"):
            mm = re.match(r"\s*(\w+)\s*=\s*(\d+)", line)
            if mm:
                values[mm.group(1)] = mm.group(2)
        enums[m.group(1)] = values

    inputs = []
    for m in INPUT_RE.finditer(src):
        typ, name, default = m.group(1), m.group(2), m.group(3).strip()
        if typ in enums and default in enums[typ]:
            default = enums[typ][default]
        elif typ == "bool":
            default = "true" if default.lower() == "true" else "false"
        elif typ == "color":
            cname = default.replace("clr", "").strip()
            if cname not in COLOR_MAP:
                raise SystemExit(f"colour {cname} missing from COLOR_MAP")
            default = str(COLOR_MAP[cname])
        elif typ == "string":
            default = default.strip().strip('"')
        inputs.append((name, default))
    return inputs


PRESETS = {
    "FTMO_Challenge_Balanced": {
        # the shipped defaults: everything defined, nothing overridden
    },
    "FTMO_Challenge_Conservative": {
        "InpRiskPercent": "0.25",
        "InpMaxRiskPercent": "0.50",
        "InpMaxOpenPositions": "1",
        "InpMaxOpenRiskPct": "0.75",
        "InpMaxTradesPerDay": "3",
        "InpDailyRiskBudgetPct": "2.00",
        "InpTotalRiskBudgetPct": "6.00",
        "InpEntryThreshold": "0.65",
        "InpMinAbsZ": "1.25",
        "InpMaxSpreadPoints": "20",
        "InpUseSession": "true",
        "InpSessionStartHour": "9",
        "InpSessionEndHour": "17",
        "InpUseTrailingStop": "true",
        "InpTrailATRMult": "1.50",
        "InpMaxBarsInTrade": "36",
        "InpCloseBeforeWeekend": "true",
        "InpCsvLog": "true",
    },
    "FTMO_Challenge_Active": {
        "InpRiskPercent": "0.75",
        "InpMaxRiskPercent": "1.00",
        "InpMaxOpenPositions": "2",
        "InpMaxOpenRiskPct": "1.50",
        "InpMaxTradesPerDay": "8",
        "InpDailyRiskBudgetPct": "4.00",
        "InpTotalRiskBudgetPct": "8.00",
        "InpEntryThreshold": "0.50",
        "InpMinAbsZ": "0.85",
        "InpMaxSpreadPoints": "25",
    },
    "Mean_Reversion_Pure": {
        "InpStrategy": "1",
        "InpWeightZ": "1.20",
        "InpWeightMom": "0.40",
        "InpWeightFib": "0.20",
        "InpExitMode": "1",
        "InpExitOnZNeutral": "true",
        "InpMaxHalfLifeBars": "60.0",
        "InpHLTStatMin": "2.86",
        "InpRequireHalfLifeGate": "true",
    },
    "Momentum_Pure": {
        "InpStrategy": "2",
        "InpWeightZ": "0.40",
        "InpWeightMom": "1.20",
        "InpWeightFib": "0.30",
        "InpUseTrendFilter": "true",
        "InpTrendMAPeriod": "200",
        "InpTrendSlopeBars": "20",
        "InpExitMode": "0",
        "InpRR": "2.00",
        "InpExitOnZNeutral": "false",
        "InpMaxBarsInTrade": "96",
        "InpUseTrailingStop": "true",
        "InpTrailATRMult": "1.50",
        "InpRequireHalfLifeGate": "false",
    },
    "Backtest_M15_Diagnostics": {
        "InpVerbose": "true",
        "InpCsvLog": "true",
        "InpCsvFileName": "QuantEdge_log.csv",
        "InpSelfTest": "true",
        "InpShowDashboard": "true",
        "InpMaxTradesPerDay": "6",
    },
}


def main():
    if not os.path.exists(EA):
        print(f"EA not found: {EA}")
        return 1
    src = open(EA, encoding="utf-8").read()
    inputs = parse_inputs(src)
    known = dict(inputs)
    if len(inputs) < 50:
        print(f"only {len(inputs)} inputs parsed - the regex has drifted from the source")
        return 1

    os.makedirs(OUT, exist_ok=True)
    written = 0
    for name, overrides in PRESETS.items():
        unknown = [k for k in overrides if k not in known]
        if unknown:
            print(f"{name}: unknown input(s) {unknown}")
            return 1
        lines = [f"; QuantEdge preset: {name}",
                 f"; generated by tools/gen_presets.py from FTMO_QuantEdge.mq4",
                 "; load with: EA properties -> Inputs -> Load"]
        for key, default in inputs:
            lines.append(f"{key}={overrides.get(key, default)}")
        path = os.path.join(OUT, name + ".set")
        with open(path, "w", encoding="utf-8", newline="\r\n") as fh:
            fh.write("\n".join(lines) + "\n")
        overridden = len(overrides)
        print(f"wrote {os.path.relpath(path, ROOT)}  ({len(inputs)} inputs, {overridden} overridden)")
        written += 1

    print(f"\n{written} presets, {len(inputs)} declared inputs each")
    return 0


if __name__ == "__main__":
    sys.exit(main())
