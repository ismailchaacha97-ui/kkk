#!/usr/bin/env python3
"""
MQL4 Validation & Trading Simulation Engine for Second Entry Strategy
"""
import re
import math
import random
import json

def validate_mql4_syntax(filepath):
    print(f"Validating MQL4 file: {filepath}")
    with open(filepath, 'r', encoding='utf-8') as f:
        raw = f.read()

    # Strip strings & comments
    code_no_str = re.sub(r'\"(\\.|[^\"])*\"', '\"\"', raw)
    code_no_comments = re.sub(r'//.*', '', code_no_str)
    code_clean = re.sub(r'/\*.*?\*/', '', code_no_comments, flags=re.DOTALL)

    open_braces = code_clean.count('{')
    close_braces = code_clean.count('}')
    assert open_braces == close_braces, f"Brace mismatch! {{ {open_braces} != }} {close_braces}"

    open_parens = code_clean.count('(')
    close_parens = code_clean.count(')')
    assert open_parens == close_parens, f"Parentheses mismatch! ( {open_parens} != ) {close_parens}"

    open_brackets = code_clean.count('[')
    close_brackets = code_clean.count(']')
    assert open_brackets == close_brackets, f"Bracket mismatch! [ {open_brackets} != ] {close_brackets}"

    assert 'OnInit()' in raw, "Missing OnInit()"
    assert 'OnDeinit(' in raw, "Missing OnDeinit()"
    assert 'OnCalculate(' in raw, "Missing OnCalculate()"

    print(f"✓ All {open_braces} code blocks, {open_parens} calls, and {open_brackets} array indices match perfectly!")
    return True

# Simulation of Second Entry Price Action strategy on realistic candle data
def simulate_price_action_strategy():
    print("\n--- Running Price Action Second Entry Simulation ---")
    random.seed(42)
    bars = 300
    price = 1.0850
    candles = []
    
    # Generate realistic trending and pulling back price series
    trend = 0.0001
    for i in range(bars):
        if i % 60 == 0:
            trend = -trend
        
        noise = random.gauss(0, 0.0004)
        o = price
        c = price + trend + noise
        h = max(o, c) + abs(random.gauss(0, 0.0003))
        l = min(o, c) - abs(random.gauss(0, 0.0003))
        price = c
        candles.append({'open': o, 'high': h, 'low': l, 'close': c, 'time': i})

    # Compute 21 EMA
    ema_period = 21
    k = 2.0 / (ema_period + 1.0)
    ema_values = []
    current_ema = candles[0]['close']
    for c in candles:
        current_ema = (c['close'] * k) + (current_ema * (1.0 - k))
        ema_values.append(current_ema)

    # Detect 2EL and 2ES
    signals = []
    for i in range(25, len(candles) - 1):
        c = candles[i]
        prev_c = candles[i-1]
        ema = ema_values[i]
        prev_ema = ema_values[i-1]
        slope = ema - prev_ema

        # 2EL (Second Entry Long) check:
        if slope > 0 and c['close'] > ema:
            # Check for lower wick rejection
            total_range = c['high'] - c['low']
            if total_range > 0:
                lower_wick = min(c['open'], c['close']) - c['low']
                if (lower_wick / total_range) >= 0.30 and c['low'] <= ema + 0.0005:
                    signals.append({'bar': i, 'type': '2EL', 'price': c['close'], 'sl': c['low'] - 0.0003, 'tp': c['close'] + 2*(c['close'] - (c['low'] - 0.0003))})

        # 2ES (Second Entry Short) check:
        elif slope < 0 and c['close'] < ema:
            total_range = c['high'] - c['low']
            if total_range > 0:
                upper_wick = c['high'] - max(c['open'], c['close'])
                if (upper_wick / total_range) >= 0.30 and c['high'] >= ema - 0.0005:
                    signals.append({'bar': i, 'type': '2ES', 'price': c['close'], 'sl': c['high'] + 0.0003, 'tp': c['close'] - 2*((c['high'] + 0.0003) - c['close'])})

    print(f"Generated {len(candles)} candles.")
    print(f"Identified {len(signals)} Second Entry signals (2EL / 2ES).")
    for s in signals[:5]:
        print(f"  Signal on Bar {s['bar']}: {s['type']} @ {s['price']:.5f} | SL: {s['sl']:.5f} | TP: {s['tp']:.5f}")
    
    return True

if __name__ == '__main__':
    validate_mql4_syntax('/home/user/kkk/SecondEntry_PriceAction_EMA.mq4')
    simulate_price_action_strategy()
