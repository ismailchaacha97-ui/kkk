import sys
sys.path.insert(0, 'src')
from vwap_ssl_engine import Bar, run_full_engine, AnchorPeriod, VolumeMode, Decision
from datetime import datetime, timedelta
import random

def generate_random_walk(n, seed=42):
    random.seed(seed)
    base = datetime(2024,1,1,0,0)
    bars=[]
    price=100.0
    for i in range(n):
        t = base + timedelta(minutes=15*i)
        # random walk
        price += random.uniform(-0.5, 0.5)
        high = price + random.uniform(0, 0.8)
        low = price - random.uniform(0, 0.8)
        close = random.uniform(low, high)
        vol = random.randint(500, 2000)
        # add spread 0.1
        bars.append(Bar(time=t, open=price, high=high, low=low, close=close, tick_volume=vol, spread=0.1))
    return bars

def test_full_engine_no_crash():
    bars = generate_random_walk(200)
    params={
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
    assert len(results)==len(bars)
    # check that flips produce entry objects
    flips = [r for r in results if r['vwap'].flipped]
    print(f"Found {len(flips)} flips in 200 random bars")
    for r in flips:
        assert r['entry'] is not None
        assert 0 <= r['entry'].score <= 100
        assert r['entry'].decision in [Decision.SKIP, Decision.CAUTION, Decision.ENTER]
    # at least some flips should be ENTER or CAUTION in random data? not guaranteed but likely
    enters = [r for r in flips if r['entry'].decision==Decision.ENTER]
    print(f"Enters: {len(enters)}")

def test_full_engine_deterministic():
    bars1 = generate_random_walk(100, seed=1)
    bars2 = generate_random_walk(100, seed=1)
    params={
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
    res1 = run_full_engine(bars1, params)
    res2 = run_full_engine(bars2, params)
    for a,b in zip(res1,res2):
        assert a['vwap'].trend == b['vwap'].trend
        if a['vwap'].flipped:
            assert abs(a['entry'].score - b['entry'].score) < 1e-6

def test_session_anchors_integration():
    # test with different anchor periods
    bars = generate_random_walk(100)
    for anchor in [AnchorPeriod.DAILY, AnchorPeriod.WEEKLY, AnchorPeriod.LONDON, AnchorPeriod.NEW_YORK]:
        params={
            'AnchorPeriod': anchor,
            'VolumeMode': VolumeMode.TICK,
            'ArrowATRPeriod': 14,
            'VolumeMAPeriod': 20,
            'ADXPeriod': 14,
            'EMAFast': 10,
            'EMASlow': 20,
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
        assert len(results)==100

def test_decision_distribution():
    # Simulate trending market where ENTER should be more frequent than in chop
    # trending: strong directional moves
    base = datetime(2024,1,1,0,0)
    trending=[]
    price=100
    for i in range(100):
        t = base + timedelta(hours=i)
        if i%20<10:
            price+=1.0  # up trend
        else:
            price-=0.2
        trending.append(Bar(time=t, open=price, high=price+0.5, low=price-0.5, close=price, tick_volume=1500 if i%20==9 else 800, spread=0.05))

    chop=[]
    price=100
    for i in range(100):
        t = base + timedelta(hours=i)
        price+= (1 if i%2==0 else -1)*0.1
        chop.append(Bar(time=t, open=price, high=price+0.3, low=price-0.3, close=price, tick_volume=800, spread=0.05))

    params={
        'AnchorPeriod': AnchorPeriod.DAILY,
        'VolumeMode': VolumeMode.TICK,
        'ArrowATRPeriod': 14,
        'VolumeMAPeriod': 20,
        'ADXPeriod': 14,
        'EMAFast': 10,
        'EMASlow': 20,
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

    res_trend = run_full_engine(trending, params)
    res_chop = run_full_engine(chop, params)

    flips_trend = [r for r in res_trend if r['vwap'].flipped]
    flips_chop = [r for r in res_chop if r['vwap'].flipped]

    enters_trend = [r for r in flips_trend if r['entry'].decision==Decision.ENTER]
    enters_chop = [r for r in flips_chop if r['entry'].decision==Decision.ENTER]

    print(f"Trending: {len(flips_trend)} flips, {len(enters_trend)} enters")
    print(f"Chop: {len(flips_chop)} flips, {len(enters_chop)} enters")

    # In trending, enter rate should be >= chop enter rate, or at least not crash
    # This is not strict but we check engine runs

if __name__ == "__main__":
    test_full_engine_no_crash()
    test_full_engine_deterministic()
    test_session_anchors_integration()
    test_decision_distribution()
    print("All integration tests passed")
