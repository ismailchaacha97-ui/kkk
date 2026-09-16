import sys
sys.path.insert(0, 'src')
from vwap_ssl_engine import Bar, calculate_vwap_series, AnchorPeriod, VolumeMode
from datetime import datetime, timedelta
import math

def make_bars(n, start_price=100.0, anchor=AnchorPeriod.DAILY):
    bars=[]
    base = datetime(2024,1,1,0,0)
    price=start_price
    for i in range(n):
        t = base + timedelta(hours=i)
        # simple up trend with noise
        price += 0.1
        high = price + 0.5
        low = price - 0.5
        close = price + (0.1 if i%2==0 else -0.1)
        bars.append(Bar(time=t, open=price, high=high, low=low, close=close, tick_volume=1000+ i*10))
    return bars

def test_vwap_basic():
    bars = make_bars(50)
    states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    assert len(states)==len(bars)
    # VWAP should be between low and high roughly
    for s, b in zip(states, bars):
        if s.anchor_key != -1:
            assert s.high_vwap >= b.low - 2.0
            assert s.low_vwap <= b.high + 2.0
            # typical VWAP between high and low VWAP?
            # high VWAP uses high prices, low VWAP uses low, so high_vwap should generally be >= low_vwap
            assert s.high_vwap >= s.low_vwap - 1e-6

def test_vwap_anchor_reset():
    # daily anchor, 48 hours = 2 days, should reset
    bars = make_bars(48)
    states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    # find where anchor changes
    anchors = [s.anchor_key for s in states]
    # should have at least 2 unique anchors
    uniq = set(anchors)
    assert len(uniq)>=2, f"Expected at least 2 anchors, got {uniq}"
    # after reset, stddev should be small then grow? check first bar after reset has stddev ~ small
    # find index where anchor changes
    change_idx=None
    for i in range(1,len(anchors)):
        if anchors[i]!=anchors[i-1]:
            change_idx=i
            break
    assert change_idx is not None
    # stddev at reset should be relatively small compared to later
    assert states[change_idx].stddev < states[change_idx+5].stddev + 1.0

def test_vwap_weighted():
    # test that higher volume bars have more weight
    base = datetime(2024,1,1,0,0)
    bars=[]
    # 3 bars, middle has huge volume at high price
    bars.append(Bar(time=base, open=100, high=100, low=100, close=100, tick_volume=100))
    bars.append(Bar(time=base+timedelta(hours=1), open=200, high=200, low=200, close=200, tick_volume=10000))
    bars.append(Bar(time=base+timedelta(hours=2), open=100, high=100, low=100, close=100, tick_volume=100))
    states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    # typical VWAP should be closer to 200 than 100 due to volume
    # weighted average: (100*100 + 200*10000 + 100*100)/(100+10000+100) ~ 198
    assert states[2].typical_vwap > 150, f"VWAP should be weighted, got {states[2].typical_vwap}"

def test_vwap_no_future_leak():
    # Ensure VWAP at bar i does not use future bars
    bars = make_bars(20)
    states_full = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    # compute with only first 10 bars
    states_partial = calculate_vwap_series(bars[:10], AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    # first 10 should be identical
    for i in range(10):
        assert math.isclose(states_full[i].typical_vwap, states_partial[i].typical_vwap, rel_tol=1e-9), f"Future leak at {i}"

if __name__ == "__main__":
    test_vwap_basic()
    test_vwap_anchor_reset()
    test_vwap_weighted()
    test_vwap_no_future_leak()
    print("All VWAP tests passed")
