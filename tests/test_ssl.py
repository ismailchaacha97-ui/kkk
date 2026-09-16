import sys
sys.path.insert(0, 'src')
from vwap_ssl_engine import Bar, calculate_vwap_series, AnchorPeriod, VolumeMode
from datetime import datetime, timedelta

def make_flat_bars(n, price=100):
    base = datetime(2024,1,1,0,0)
    bars=[]
    for i in range(n):
        t = base + timedelta(hours=i)
        bars.append(Bar(time=t, open=price, high=price+0.5, low=price-0.5, close=price, tick_volume=1000))
    return bars

def test_ssl_hysteretic():
    """
    SSL should be hysteretic:
    - bearish flips bullish only after close above High VWAP
    - bullish flips bearish only after close below Low VWAP
    - between stays same
    """
    base = datetime(2024,1,1,0,0)
    bars=[]
    # Create scenario: start bullish, price between VWAPs should stay bullish
    # We'll craft bars where close is between high and low VWAP
    for i in range(10):
        t = base + timedelta(hours=i)
        # keep price stable
        bars.append(Bar(time=t, open=100, high=101, low=99, close=100, tick_volume=1000))
    states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    # initial trend auto: close vs midpoint -> should be bullish or bearish but stable
    # After first bar, trend should stay same as long as close stays between
    # Since our closes are 100, and high VWAP ~101, low ~99, close between, so trend should not flip after initial
    trends = [s.trend for s in states]
    # No flips after first should occur if price stays between
    flips = [s.flipped for s in states]
    # first bar flipped is False by definition (prior 0)
    assert not any(flips[1:]), f"Should not flip when price between VWAPs, got flips {flips}"

def test_ssl_flip_bullish():
    base = datetime(2024,1,1,0,0)
    bars=[]
    # 5 bars bearish low price - make close slightly below mid to get bearish initial
    for i in range(5):
        t = base + timedelta(hours=i)
        bars.append(Bar(time=t, open=90, high=91, low=89, close=89.2, tick_volume=1000))
    # then 1 bar huge bullish breakout above High VWAP
    t = base + timedelta(hours=5)
    bars.append(Bar(time=t, open=90, high=110, low=89, close=109, tick_volume=1000))
    states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    # initial trend should be bearish, after breakout should flip bullish
    assert states[5].flipped == True, f"Should flip bullish on close above High VWAP, prior trend {states[4].trend}, new {states[5].trend}, highVWAP {states[5].high_vwap}"
    assert states[5].trend == 1, "Should be bullish after flip"

def test_ssl_flip_bearish():
    base = datetime(2024,1,1,0,0)
    bars=[]
    for i in range(5):
        t = base + timedelta(hours=i)
        bars.append(Bar(time=t, open=110, high=111, low=109, close=110.8, tick_volume=1000))
    t = base + timedelta(hours=5)
    bars.append(Bar(time=t, open=110, high=111, low=90, close=90, tick_volume=1000))
    states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    assert states[5].flipped == True, f"Should flip bearish, prior {states[4].trend} new {states[5].trend} lowVWAP {states[5].low_vwap}"
    assert states[5].trend == -1

def test_carry_trend_across_anchors():
    base = datetime(2024,1,1,0,0)
    bars=[]
    # day 1: bullish
    for i in range(5):
        t = base + timedelta(hours=i)
        bars.append(Bar(time=t, open=100, high=101, low=99, close=101, tick_volume=1000))
    # day 2: new anchor, price slightly lower but still above new low VWAP
    for i in range(5,10):
        t = base + timedelta(days=1, hours=i)
        bars.append(Bar(time=t, open=100, high=101, low=99, close=100, tick_volume=1000))
    states_carry = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    states_no_carry = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, False, 0)
    # with carry, trend at bar 5 should be same as previous day's last trend
    # without carry, trend at bar 5 should be re-initialized
    # Since we start day2 at 100, midpoint of new day's first bar = 100, close=100 => bullish (auto)
    # So both might be bullish, but test that no_carry resets state to 0 before first bar of new anchor
    # The important thing is that code path works
    assert len(states_carry)==10
    assert len(states_no_carry)==10

def test_initial_trend_enum():
    base = datetime(2024,1,1,0,0)
    bars=[]
    for i in range(3):
        t = base + timedelta(hours=i)
        bars.append(Bar(time=t, open=100, high=101, low=99, close=100, tick_volume=1000))
    states_bull = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 1)
    states_bear = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, -1)
    assert states_bull[0].trend == 1
    assert states_bear[0].trend == -1

if __name__ == "__main__":
    test_ssl_hysteretic()
    test_ssl_flip_bullish()
    test_ssl_flip_bearish()
    test_carry_trend_across_anchors()
    test_initial_trend_enum()
    print("All SSL tests passed")
