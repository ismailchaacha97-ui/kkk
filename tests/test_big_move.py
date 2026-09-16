import sys
sys.path.insert(0, 'src')
from vwap_ssl_engine_v7 import Bar, calculate_vwap_series, calculate_anchor_progress, anchor_start_time, AnchorPeriod, VolumeMode, Decision, run_full_engine_v7
from datetime import datetime, timedelta
import math

def make_bars(n, start_price=100, anchor=AnchorPeriod.WEEKLY):
    bars=[]
    base = datetime(2024,1,1,0,0)  # Monday
    price=start_price
    for i in range(n):
        t = base + timedelta(hours=i)
        price += 0.05
        high = price + 0.5
        low = price - 0.5
        close = price
        bars.append(Bar(time=t, open=price, high=high, low=low, close=close, tick_volume=1000))
    return bars

def test_anchor_progress():
    base = datetime(2024,1,1,0,0)  # Monday
    # weekly anchor: Monday 00:00 start, duration 5 days
    anchor_start = anchor_start_time(base, AnchorPeriod.WEEKLY)
    assert anchor_start == datetime(2024,1,1,0,0)
    # Tuesday = 1 day elapsed = 20% progress
    tuesday = datetime(2024,1,2,0,0)
    prog = calculate_anchor_progress(tuesday, anchor_start, AnchorPeriod.WEEKLY)
    assert abs(prog - 0.2) < 0.01, f"Expected 20% got {prog}"

    # Friday 00:00 = 4 days = 80%
    friday = datetime(2024,1,5,0,0)
    prog_fri = calculate_anchor_progress(friday, anchor_start, AnchorPeriod.WEEKLY)
    assert abs(prog_fri - 0.8) < 0.01

    # Monthly
    jan15 = datetime(2024,1,15,0,0)
    jan_start = anchor_start_time(jan15, AnchorPeriod.MONTHLY)
    assert jan_start == datetime(2024,1,1,0,0)
    prog_jan = calculate_anchor_progress(jan15, jan_start, AnchorPeriod.MONTHLY)
    # 14 days / 31 ~45%
    assert 0.4 < prog_jan < 0.5

def test_big_move_rr():
    # Create scenario where price near typical VWAP has high RR to 2SD band
    base = datetime(2024,1,1,0,0)
    bars=[]
    for i in range(20):
        t = base + timedelta(hours=i)
        # stable price 100
        bars.append(Bar(time=t, open=100, high=100.5, low=99.5, close=100, tick_volume=1000))
    # flip bar far? Actually need VWAP with stddev
    params={
        'AnchorPeriod': AnchorPeriod.WEEKLY,
        'VolumeMode': VolumeMode.TICK,
        'ArrowATRPeriod': 14,
        'VolumeMAPeriod': 20,
        'ADXPeriod': 14,
        'EMAFast': 10,
        'EMASlow': 20,
        'MinBreakoutATR': 0.10,
        'MinVolumeFactor': 1.10,
        'MinADX': 16.0,
        'ChopThresholdATR': 0.40,
        'MaxSpreadATR': 0.35,
        'MinBarsBetweenFlips': 5,
        'UseADXFilter': True,
        'UseEMAFilter': False,
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
        'MinDistanceToBandATR': 1.0,
        'SLMode': 0,
        'StopLossATR': 1.5
    }
    results = run_full_engine_v7(bars, params)
    # Should not crash, check anchor progress exists
    for r in results:
        assert hasattr(r['vwap'], 'anchor_progress')
        assert 0 <= r['vwap'].anchor_progress <= 1

def test_big_move_early_vs_late():
    # Early anchor should score higher than late anchor for same setup
    base = datetime(2024,1,1,0,0)
    bars_early=[]
    for i in range(5):
        t = base + timedelta(hours=i)  # early in week
        bars_early.append(Bar(time=t, open=90, high=91, low=89, close=89.2, tick_volume=1000))
    t = base + timedelta(hours=5)
    bars_early.append(Bar(time=t, open=90, high=110, low=89, close=109, tick_volume=3000))

    # late in week: Friday
    base_late = datetime(2024,1,5,10,0)  # Friday
    bars_late=[]
    for i in range(5):
        t = base_late - timedelta(hours=5-i)
        bars_late.append(Bar(time=t, open=90, high=91, low=89, close=89.2, tick_volume=1000))
    t = base_late
    bars_late.append(Bar(time=t, open=90, high=110, low=89, close=109, tick_volume=3000))

    params={
        'AnchorPeriod': AnchorPeriod.WEEKLY,
        'VolumeMode': VolumeMode.TICK,
        'ArrowATRPeriod': 14,
        'VolumeMAPeriod': 20,
        'ADXPeriod': 14,
        'EMAFast': 10,
        'EMASlow': 20,
        'MinBreakoutATR': 0.10,
        'MinVolumeFactor': 1.10,
        'MinADX': 16.0,
        'ChopThresholdATR': 0.40,
        'MaxSpreadATR': 0.35,
        'MinBarsBetweenFlips': 5,
        'UseADXFilter': False,
        'UseEMAFilter': False,
        'RequireEMABias': False,
        'UseBandPositionBonus': True,
        'AvoidChopZone': False,
        'Band1Deviation': 1.0,
        'Band2Deviation': 2.0,
        'Band3Deviation': 3.0,
        'MinScoreToEnter': 68,
        'MinScoreToCaution': 50,
        'CarryTrendAcrossAnchors': True,
        'InitialTrend': 0,
        'UseBigMoveMode': True,
        'BigMoveMinRR': 2.0,
        'AvoidLateAnchor': True,
        'MaxAnchorProgress': 0.80,
        'PreferEarlyAnchor': True,
        'EarlyAnchorBonusThreshold': 0.35,
        'CheckBandExhaustion': False,
        'ExhaustionSD': 2.5,
        'UseBigMoveRRFilter': False,
        'MinDistanceToBandATR': 0.5,
        'SLMode': 0,
        'StopLossATR': 1.5
    }

    from vwap_ssl_engine_v7 import calculate_atr, calculate_volume_ma, calculate_adx, calculate_ema, compute_entry_quality_v7, calculate_vwap_series
    vwap_early = calculate_vwap_series(bars_early, AnchorPeriod.WEEKLY, VolumeMode.TICK, True, 0)
    atr_early = calculate_atr(bars_early, 14)
    vol_ma_early = calculate_volume_ma(bars_early, 20, VolumeMode.TICK)
    adx_early = calculate_adx(bars_early, 14)
    closes_early=[b.close for b in bars_early]
    ema_f_early=calculate_ema(closes_early, 10)
    ema_s_early=calculate_ema(closes_early, 20)

    vwap_late = calculate_vwap_series(bars_late, AnchorPeriod.WEEKLY, VolumeMode.TICK, True, 0)
    atr_late = calculate_atr(bars_late, 14)
    vol_ma_late = calculate_volume_ma(bars_late, 20, VolumeMode.TICK)
    adx_late = calculate_adx(bars_late, 14)
    closes_late=[b.close for b in bars_late]
    ema_f_late=calculate_ema(closes_late, 10)
    ema_s_late=calculate_ema(closes_late, 20)

    eq_early = compute_entry_quality_v7(5, bars_early, vwap_early, atr_early, vol_ma_early, adx_early, ema_f_early, ema_s_early, params, -1)
    eq_late = compute_entry_quality_v7(5, bars_late, vwap_late, atr_late, vol_ma_late, adx_late, ema_f_late, ema_s_late, params, -1)

    print(f"Early: prog {eq_early.anchor_progress:.2f} score {eq_early.score:.0f} RR {eq_early.big_move_rr_2sd:.1f}")
    print(f"Late: prog {eq_late.anchor_progress:.2f} score {eq_late.score:.0f} RR {eq_late.big_move_rr_2sd:.1f}")

    # Early should have higher anchor score
    assert eq_early.breakdown['anchor'] >= eq_late.breakdown['anchor'], "Early anchor should score >= late"

def test_monthly_on_small_tf():
    # Simulate M15 bars over 2 weeks with monthly anchor
    base = datetime(2024,1,2,0,0)
    bars=[]
    price=100
    for i in range(500):  # 500 * 15min = ~5 days
        t = base + timedelta(minutes=15*i)
        price += 0.01
        bars.append(Bar(time=t, open=price, high=price+0.2, low=price-0.2, close=price, tick_volume=1000))

    params={
        'AnchorPeriod': AnchorPeriod.MONTHLY,
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
        'MinBarsBetweenFlips': 10,
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
    results = run_full_engine_v7(bars, params)
    assert len(results)==500
    # Should have some flips? In trending data, maybe few
    flips = [r for r in results if r['vwap'].flipped]
    print(f"Monthly on M15: {len(flips)} flips in 500 bars")
    # Check all have progress
    for r in flips:
        assert 0 <= r['vwap'].anchor_progress <= 1

if __name__ == "__main__":
    test_anchor_progress()
    test_big_move_rr()
    test_big_move_early_vs_late()
    test_monthly_on_small_tf()
    print("All big move tests passed")
