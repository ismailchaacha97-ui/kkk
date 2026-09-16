"""
Demo backtest using the VWAP SSL Flip v6 engine
Shows how the indicator tells you ENTER vs SKIP
"""
import sys
sys.path.insert(0, 'src')
from vwap_ssl_engine import Bar, run_full_engine, AnchorPeriod, VolumeMode, Decision
from datetime import datetime, timedelta
import random

def load_sample_data():
    # Generate synthetic trending + choppy market
    base = datetime(2024,1,1,8,0)
    bars=[]
    price=1.1000
    random.seed(123)
    for i in range(500):
        t = base + timedelta(minutes=15*i)
        # create regimes
        if 100 < i < 200:  # strong up trend
            price += random.uniform(0.0002, 0.0008)
            vol = random.randint(1500, 3000)
        elif 200 < i < 300:  # chop
            price += random.uniform(-0.0003, 0.0003)
            vol = random.randint(400, 900)
        elif 300 < i < 400:  # strong down trend
            price -= random.uniform(0.0002, 0.0008)
            vol = random.randint(1500, 3000)
        else:
            price += random.uniform(-0.0005, 0.0005)
            vol = random.randint(800, 1500)

        high = price + random.uniform(0.0001, 0.0006)
        low = price - random.uniform(0.0001, 0.0006)
        close = random.uniform(low, high)
        bars.append(Bar(time=t, open=price, high=high, low=low, close=close, tick_volume=vol, spread=0.0001))
        price = close
    return bars

def main():
    bars = load_sample_data()
    params = {
        'AnchorPeriod': AnchorPeriod.DAILY,
        'VolumeMode': VolumeMode.TICK,
        'ArrowATRPeriod': 14,
        'VolumeMAPeriod': 20,
        'ADXPeriod': 14,
        'EMAFast': 50,
        'EMASlow': 200,
        'MinBreakoutATR': 0.12,
        'MinVolumeFactor': 1.15,
        'MinADX': 18.0,
        'ChopThresholdATR': 0.45,
        'MaxSpreadATR': 0.35,
        'MinBarsBetweenFlips': 5,
        'UseADXFilter': True,
        'UseEMAFilter': True,
        'RequireEMABias': False,
        'UseBandPositionBonus': True,
        'AvoidChopZone': True,
        'Band1Deviation': 1.0,
        'MinScoreToEnter': 70,
        'MinScoreToCaution': 50,
        'CarryTrendAcrossAnchors': True,
        'InitialTrend': 0
    }

    results = run_full_engine(bars, params)
    flips = [r for r in results if r['vwap'].flipped]

    print(f"Total bars: {len(bars)}")
    print(f"Total flips: {len(flips)}")
    print(f"{'Time':<20} {'Side':<6} {'Decision':<10} {'Score':<6} {'Reason'}")
    print("-"*120)
    for r in flips:
        b = r['bar']
        e = r['entry']
        side = "BUY" if r['vwap'].trend>0 else "SELL"
        print(f"{b.time.strftime('%Y-%m-%d %H:%M'):<20} {side:<6} {Decision.to_str(e.decision):<10} {e.score:<6.0f} {e.reason}")

    enters = [r for r in flips if r['entry'].decision==Decision.ENTER]
    cautions = [r for r in flips if r['entry'].decision==Decision.CAUTION]
    skips = [r for r in flips if r['entry'].decision==Decision.SKIP]

    print("\n--- SUMMARY ---")
    print(f"ENTER  : {len(enters)} ({len(enters)/max(1,len(flips))*100:.1f}%) - these are high quality, trade them")
    print(f"CAUTION: {len(cautions)} ({len(cautions)/max(1,len(flips))*100:.1f}%) - marginal, consider waiting or smaller size")
    print(f"SKIP   : {len(skips)} ({len(skips)/max(1,len(flips))*100:.1f}%) - low quality, avoid")

    # Show improvement vs trading all flips
    print("\n--- WHY FILTER MATTERS ---")
    print("Without filter: you would trade every flip (including choppy false breaks)")
    print(f"With filter (ENTER only): you trade {len(enters)} out of {len(flips)} flips")
    print(f"Filtering out {len(skips)+len(cautions)} low quality flips saves you from whipsaw")

if __name__ == "__main__":
    main()
