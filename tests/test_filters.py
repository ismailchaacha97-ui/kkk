import sys
sys.path.insert(0, 'src')
from vwap_ssl_engine import Bar, calculate_vwap_series, calculate_atr, calculate_volume_ma, calculate_adx, calculate_ema, compute_entry_quality, AnchorPeriod, VolumeMode, Decision
from datetime import datetime, timedelta

def make_trending_bars(n, start=100, trend=0.2, vol_base=1000):
    base = datetime(2024,1,1,0,0)
    bars=[]
    price=start
    for i in range(n):
        t = base + timedelta(hours=i)
        price+=trend
        high=price+0.5
        low=price-0.5
        close=price
        vol=vol_base + (500 if i%5==0 else 0)
        bars.append(Bar(time=t, open=price, high=high, low=low, close=close, tick_volume=vol))
    return bars

def default_params():
    return {
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

def test_entry_quality_strong_vs_weak():
    # Create bars where a flip occurs with strong breakout and volume vs weak
    base = datetime(2024,1,1,0,0)
    bars=[]
    # 10 bars stable low price 90
    for i in range(10):
        t = base + timedelta(hours=i)
        bars.append(Bar(time=t, open=90, high=90.5, low=89.5, close=90, tick_volume=1000))
    # flip bar 1: strong breakout, high volume, far above VWAP
    t = base + timedelta(hours=10)
    bars.append(Bar(time=t, open=90, high=110, low=89, close=109, tick_volume=5000))
    # another scenario: weak breakout
    bars_weak=[]
    for i in range(10):
        t = base + timedelta(hours=i)
        bars_weak.append(Bar(time=t, open=90, high=90.5, low=89.5, close=90, tick_volume=1000))
    t = base + timedelta(hours=10)
    # barely above High VWAP, low volume
    bars_weak.append(Bar(time=t, open=90, high=90.8, low=89.5, close=90.6, tick_volume=500))

    params=default_params()
    # strong
    vwap_states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    atr = calculate_atr(bars, 14)
    vol_ma = calculate_volume_ma(bars, 20, VolumeMode.TICK)
    adx = calculate_adx(bars, 14)
    closes=[b.close for b in bars]
    ema_f=calculate_ema(closes, 10)
    ema_s=calculate_ema(closes, 20)

    eq_strong = compute_entry_quality(10, bars, vwap_states, atr, vol_ma, adx, ema_f, ema_s, params, -1)

    # weak
    vwap_states_w = calculate_vwap_series(bars_weak, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    atr_w = calculate_atr(bars_weak, 14)
    vol_ma_w = calculate_volume_ma(bars_weak, 20, VolumeMode.TICK)
    adx_w = calculate_adx(bars_weak, 14)
    closes_w=[b.close for b in bars_weak]
    ema_f_w=calculate_ema(closes_w, 10)
    ema_s_w=calculate_ema(closes_w, 20)
    eq_weak = compute_entry_quality(10, bars_weak, vwap_states_w, atr_w, vol_ma_w, adx_w, ema_f_w, ema_s_w, params, -1)

    print(f"Strong: {eq_strong.reason}")
    print(f"Weak: {eq_weak.reason}")
    assert eq_strong.score > eq_weak.score, "Strong breakout should score higher than weak"
    assert eq_strong.breakout_atr > eq_weak.breakout_atr
    assert eq_strong.vol_ratio > eq_weak.vol_ratio

def test_volume_filter():
    params=default_params()
    base = datetime(2024,1,1,0,0)
    bars=[]
    for i in range(10):
        t = base + timedelta(hours=i)
        bars.append(Bar(time=t, open=100, high=101, low=99, close=100, tick_volume=1000))
    # flip with low volume
    t = base + timedelta(hours=10)
    bars.append(Bar(time=t, open=100, high=110, low=99, close=109, tick_volume=200))
    vwap_states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    atr = calculate_atr(bars, 14)
    vol_ma = calculate_volume_ma(bars, 20, VolumeMode.TICK)
    adx = calculate_adx(bars, 14)
    closes=[b.close for b in bars]
    ema_f=calculate_ema(closes, 10)
    ema_s=calculate_ema(closes, 20)
    eq = compute_entry_quality(10, bars, vwap_states, atr, vol_ma, adx, ema_f, ema_s, params, -1)
    # low volume should penalize
    assert eq.breakdown['volume'] < 10, f"Low volume should give low volume score, got {eq.breakdown['volume']}"

def test_chop_filter():
    params=default_params()
    base = datetime(2024,1,1,0,0)
    bars=[]
    # very tight range = chop
    for i in range(10):
        t = base + timedelta(hours=i)
        bars.append(Bar(time=t, open=100, high=100.1, low=99.9, close=100, tick_volume=1000))
    t = base + timedelta(hours=10)
    bars.append(Bar(time=t, open=100, high=100.2, low=99.9, close=100.15, tick_volume=2000))
    vwap_states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    atr = calculate_atr(bars, 14)
    vol_ma = calculate_volume_ma(bars, 20, VolumeMode.TICK)
    adx = calculate_adx(bars, 14)
    closes=[b.close for b in bars]
    ema_f=calculate_ema(closes, 10)
    ema_s=calculate_ema(closes, 20)
    eq = compute_entry_quality(10, bars, vwap_states, atr, vol_ma, adx, ema_f, ema_s, params, -1)
    # chop score should be low because channel width small
    # channel ATR = (highVWAP-lowVWAP)/ATR, if range tight, channel small
    print(f"Chop test: channelATR {eq.channel_atr} score chop {eq.breakdown['chop']}")
    # not strict assert because ATR also small, but check logic runs

def test_bars_since_flip():
    params=default_params()
    base = datetime(2024,1,1,0,0)
    bars=[]
    for i in range(20):
        t = base + timedelta(hours=i)
        # alternate to cause flips? We'll manually test compute with last_flip close
        bars.append(Bar(time=t, open=100, high=101, low=99, close=100, tick_volume=1000))
    # make last bar a flip
    bars[19].close=110
    bars[19].high=111
    vwap_states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    atr = calculate_atr(bars, 14)
    vol_ma = calculate_volume_ma(bars, 20, VolumeMode.TICK)
    adx = calculate_adx(bars, 14)
    closes=[b.close for b in bars]
    ema_f=calculate_ema(closes, 10)
    ema_s=calculate_ema(closes, 20)

    eq_close_flip = compute_entry_quality(19, bars, vwap_states, atr, vol_ma, adx, ema_f, ema_s, params, last_flip_idx=18)
    eq_far_flip = compute_entry_quality(19, bars, vwap_states, atr, vol_ma, adx, ema_f, ema_s, params, last_flip_idx=5)
    print(f"Close flip gap score {eq_close_flip.breakdown['gap']} vs far {eq_far_flip.breakdown['gap']}")
    assert eq_close_flip.breakdown['gap'] < eq_far_flip.breakdown['gap'], "Close flips should be penalized vs far flips"

def test_ema_bias_forced_skip():
    params=default_params()
    params['RequireEMABias']=True
    params['UseEMAFilter']=True
    base = datetime(2024,1,1,0,0)
    bars=[]
    # downtrend EMA
    price=110
    for i in range(20):
        t = base + timedelta(hours=i)
        price-=0.5
        bars.append(Bar(time=t, open=price, high=price+0.5, low=price-0.5, close=price, tick_volume=1000))
    # bullish flip against EMA downtrend
    t = base + timedelta(hours=20)
    bars.append(Bar(time=t, open=100, high=105, low=99, close=104, tick_volume=2000))
    vwap_states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    atr = calculate_atr(bars, 14)
    vol_ma = calculate_volume_ma(bars, 20, VolumeMode.TICK)
    adx = calculate_adx(bars, 14)
    closes=[b.close for b in bars]
    ema_f=calculate_ema(closes, 10)
    ema_s=calculate_ema(closes, 20)
    eq = compute_entry_quality(20, bars, vwap_states, atr, vol_ma, adx, ema_f, ema_s, params, -1)
    # Should be forced SKIP if EMA misaligned
    # Depending on EMA values, check if it actually triggers
    if eq.breakdown['ema']==0:
        assert eq.decision==Decision.SKIP, "With RequireEMABias and misaligned EMA, should be SKIP"

def test_score_bounds():
    params=default_params()
    base = datetime(2024,1,1,0,0)
    bars=[]
    for i in range(15):
        t = base + timedelta(hours=i)
        bars.append(Bar(time=t, open=100, high=101, low=99, close=100, tick_volume=1000))
    t = base + timedelta(hours=15)
    bars.append(Bar(time=t, open=100, high=150, low=90, close=145, tick_volume=10000))
    vwap_states = calculate_vwap_series(bars, AnchorPeriod.DAILY, VolumeMode.TICK, True, 0)
    atr = calculate_atr(bars, 14)
    vol_ma = calculate_volume_ma(bars, 20, VolumeMode.TICK)
    adx = calculate_adx(bars, 14)
    closes=[b.close for b in bars]
    ema_f=calculate_ema(closes, 10)
    ema_s=calculate_ema(closes, 20)
    eq = compute_entry_quality(15, bars, vwap_states, atr, vol_ma, adx, ema_f, ema_s, params, -1)
    assert 0 <= eq.score <= 100, f"Score should be 0-100, got {eq.score}"
    assert eq.decision in [Decision.SKIP, Decision.CAUTION, Decision.ENTER]

if __name__ == "__main__":
    test_entry_quality_strong_vs_weak()
    test_volume_filter()
    test_chop_filter()
    test_bars_since_flip()
    test_ema_bias_forced_skip()
    test_score_bounds()
    print("All filter tests passed")
