"""
Big Move Demo - Weekly/Monthly VWAP on small TF for 1:3, 1:5, 1:8+ moves
Shows how v7 filters for big RR
"""
import sys
sys.path.insert(0, 'src')
from vwap_ssl_engine_v7 import Bar, run_full_engine_v7, AnchorPeriod, VolumeMode, Decision
from datetime import datetime, timedelta
import random

def load_big_move_data():
    # Simulate 2 weeks of M15 data with weekly anchor
    base = datetime(2024,1,1,0,0)  # Monday
    bars=[]
    price=1.1000
    random.seed(456)
    # Week 1: Monday-Tuesday chop, Wednesday breakout, Thursday-Friday trend
    for i in range(500):  # ~5 days M15 = 480 bars
        t = base + timedelta(minutes=15*i)
        day = i // 96  # 96 M15 per day
        hour_in_day = (i % 96) * 15 / 60

        if day == 0:  # Monday chop
            price += random.uniform(-0.0002, 0.0002)
            vol = random.randint(600, 1000)
        elif day == 1:  # Tuesday accumulation, volume rising
            price += random.uniform(-0.0001, 0.0003)
            vol = random.randint(800, 1300)
        elif day == 2:  # Wednesday breakout - big move start
            if hour_in_day < 8:
                price += random.uniform(-0.0001, 0.0002)
                vol = random.randint(800, 1200)
            else:
                price += random.uniform(0.0003, 0.0009)  # strong up
                vol = random.randint(1800, 3500)
        elif day in [3,4]:  # Thursday Friday trend continuation
            price += random.uniform(0.0001, 0.0005)
            vol = random.randint(1200, 2000)
        else:
            price += random.uniform(-0.0002, 0.0002)
            vol = random.randint(600, 1000)

        high = price + random.uniform(0.0001, 0.0004)
        low = price - random.uniform(0.0001, 0.0004)
        close = random.uniform(low, high)
        bars.append(Bar(time=t, open=price, high=high, low=low, close=close, tick_volume=vol, spread=0.00005))
        price = close
    return bars

def main():
    bars = load_big_move_data()
    params_weekly = {
        'AnchorPeriod': AnchorPeriod.WEEKLY,
        'VolumeMode': VolumeMode.TICK,
        'ArrowATRPeriod': 14,
        'VolumeMAPeriod': 20,
        'ADXPeriod': 14,
        'EMAFast': 50,
        'EMASlow': 200,
        'MinBreakoutATR': 0.10,
        'MinVolumeFactor': 1.10,
        'MinADX': 16.0,
        'ChopThresholdATR': 0.40,
        'MaxSpreadATR': 0.35,
        'MinBarsBetweenFlips': 5,
        'UseADXFilter': True,
        'UseEMAFilter': True,
        'RequireEMABias': False,
        'UseBandPositionBonus': True,
        'AvoidChopZone': True,
        'Band1Deviation': 1.0,
        'Band2Deviation': 2.0,
        'Band3Deviation': 3.0,
        'MinScoreToEnter': 68,
        'MinScoreToCaution': 50,
        'CarryTrendAcrossAnchors': True,
        'InitialTrend': 0,
        'UseBigMoveMode': True,
        'BigMoveMinRR': 3.0,
        'AvoidLateAnchor': True,
        'MaxAnchorProgress': 0.80,
        'PreferEarlyAnchor': True,
        'EarlyAnchorBonusThreshold': 0.35,
        'CheckBandExhaustion': True,
        'ExhaustionSD': 2.5,
        'UseBigMoveRRFilter': True,
        'MinDistanceToBandATR': 2.0,
        'SLMode': 0,
        'StopLossATR': 1.5
    }

    params_monthly = dict(params_weekly)
    params_monthly['AnchorPeriod'] = AnchorPeriod.MONTHLY
    params_monthly['MinBarsBetweenFlips'] = 15

    print("=== WEEKLY VWAP on M15 (catching big moves inside week) ===")
    results_w = run_full_engine_v7(bars, params_weekly)
    flips_w = [r for r in results_w if r['vwap'].flipped]
    print(f"Total bars: {len(bars)} (M15, ~1 week)")
    print(f"Flips: {len(flips_w)}")
    print(f"{'Time':<20} {'Side':<6} {'Decision':<10} {'Score':<5} {'RR2SD':<6} {'Prog':<6} {'Reason'}")
    print("-"*140)
    for r in flips_w:
        b = r['bar']
        e = r['entry']
        side = "BUY" if r['vwap'].trend>0 else "SELL"
        print(f"{b.time.strftime('%m-%d %H:%M'):<20} {side:<6} {Decision.to_str(e.decision):<10} {e.score:<5.0f} {e.big_move_rr_2sd:<6.1f} {e.anchor_progress*100:<5.0f}% {e.reason[:70]}")

    enters_w = [r for r in flips_w if r['entry'].decision==Decision.ENTER]
    print(f"\nENTER: {len(enters_w)}/{len(flips_w)} - these have >=3R potential to 2SD band, early in week, not exhausted")

    print("\n\n=== MONTHLY VWAP on M15 (catching big moves inside month) ===")
    results_m = run_full_engine_v7(bars, params_monthly)
    flips_m = [r for r in results_m if r['vwap'].flipped]
    print(f"Flips: {len(flips_m)}")
    for r in flips_m:
        b = r['bar']
        e = r['entry']
        side = "BUY" if r['vwap'].trend>0 else "SELL"
        print(f"{b.time.strftime('%m-%d %H:%M'):<20} {side:<6} {Decision.to_str(e.decision):<10} {e.score:<5.0f} RR{e.big_move_rr_2sd:.1f} Prog{e.anchor_progress*100:.0f}%")

    print("\n--- BIG MOVE MODE EXPLAINED ---")
    print("When you use Weekly VWAP on M15/H1 to catch 1:3, 1:5+ moves:")
    print("- Early week (Mon-Tue) bonus: more time for move to develop")
    print("- Late week (Fri 80%+) penalized: avoid entering when week almost over")
    print("- RR filter: needs at least 3R to 2SD band (distance to band / SL)")
    print("- Exhaustion: if price already beyond 2.5SD, skip (move already done)")
    print("- Min distance: need 2 ATR to band, else no room for big move")
    print("- Multi-TP: HUD shows TP1 1.5R, TP2 3R, TP3 5R, TP4 8R for scaling out")
    print("\nFor monthly on small TF:")
    print("- Same logic but duration = days in month")
    print("- Early month = best for big moves, late month = avoid")
    print("- Use SLMode=OPPOSITE_VWAP or BAND1 for wider SL that gives more room for 1:5+")

if __name__ == "__main__":
    main()
