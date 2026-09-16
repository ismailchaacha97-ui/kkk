"""
Holy Grail VWAP SSL Flip v6 - Python Engine
Mirrors MQL4 logic for testing and validation.

This module implements the anchored VWAP SSL flip with Entry Quality Engine.
It tells you exactly if you should ENTER or SKIP a flip.

Core principles:
- Anchored VWAPs: High, Low, Typical with weighted stddev
- Hysteretic SSL: bearish flips bullish only above High VWAP, bullish flips bearish only below Low VWAP
- Entry Quality Score 0-100 based on:
  Breakout distance / ATR (25pts)
  Volume confirmation (20pts)
  ADX trend (15pts)
  EMA bias (15pts)
  Chop filter - channel width (10pts)
  Bars since last flip (10pts)
  Band position (5pts)
  Spread (5pts) - simulated as 0 in backtest unless provided
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import List, Tuple, Optional, Dict
import math

INVALID_ANCHOR = -1

class AnchorPeriod:
    DAILY = 0
    WEEKLY = 1
    MONTHLY = 2
    QUARTERLY = 3
    YEARLY = 4
    LONDON = 5
    NEW_YORK = 6
    ASIA = 7
    CUSTOM_SESSION = 8
    CUSTOM_TIME = 9

class VolumeMode:
    TICK = 0
    REAL_WITH_TICK_FALLBACK = 1

class Decision:
    NONE = 0
    SKIP = 1
    CAUTION = 2
    ENTER = 3

    @staticmethod
    def to_str(d):
        return {0:"NONE",1:"SKIP",2:"CAUTION",3:"ENTER"}.get(d,"UNKNOWN")

@dataclass
class Bar:
    time: datetime
    open: float
    high: float
    low: float
    close: float
    tick_volume: int
    volume: int = 0
    spread: float = 0.0  # in price units

@dataclass
class VWAPState:
    high_vwap: float
    low_vwap: float
    typical_vwap: float
    stddev: float
    anchor_key: int
    trend: int  # 1 bullish, -1 bearish, 0 NA
    flipped: bool

@dataclass
class EntryQuality:
    score: float
    decision: int
    breakdown: Dict[str, float]
    reason: str
    vol_ratio: float
    breakout_atr: float
    adx: float
    channel_atr: float
    bars_since: int

def start_of_day(dt: datetime) -> datetime:
    return dt.replace(hour=0, minute=0, second=0, microsecond=0)

def anchor_key_for_bar(bar_time: datetime, anchor_period: int,
                       london_h=8, london_m=0,
                       ny_h=13, ny_m=30,
                       asia_h=0, asia_m=0,
                       custom_h=0, custom_m=0,
                       custom_anchor_time: Optional[datetime]=None) -> int:
    """
    Returns anchor key or INVALID_ANCHOR
    Mirrors MQL4 AnchorKey logic
    """
    if anchor_period == AnchorPeriod.CUSTOM_TIME:
        if custom_anchor_time is None:
            return INVALID_ANCHOR
        if bar_time >= custom_anchor_time:
            # use timestamp as key (seconds since epoch)
            return int(custom_anchor_time.timestamp())
        else:
            return INVALID_ANCHOR

    if anchor_period == AnchorPeriod.DAILY:
        sod = start_of_day(bar_time)
        return int(sod.timestamp())

    if anchor_period == AnchorPeriod.WEEKLY:
        sod = start_of_day(bar_time)
        # Monday = 0
        dow = bar_time.weekday()  # Monday 0
        monday = sod - timedelta(days=dow)
        return int(monday.timestamp())

    year = bar_time.year
    month = bar_time.month

    if anchor_period == AnchorPeriod.MONTHLY:
        return year*12 + month

    if anchor_period == AnchorPeriod.QUARTERLY:
        return year*4 + (month-1)//3

    if anchor_period == AnchorPeriod.YEARLY:
        return year

    # session anchors
    hour = custom_h
    minute = custom_m
    if anchor_period == AnchorPeriod.LONDON:
        hour, minute = london_h, london_m
    elif anchor_period == AnchorPeriod.NEW_YORK:
        hour, minute = ny_h, ny_m
    elif anchor_period == AnchorPeriod.ASIA:
        hour, minute = asia_h, asia_m

    hour = max(0, min(23, hour))
    minute = max(0, min(59, minute))
    session_seconds = hour*3600 + minute*60
    day = start_of_day(bar_time)
    seconds_into_day = int((bar_time - day).total_seconds())
    if seconds_into_day < session_seconds:
        day = day - timedelta(days=1)
    session_start = day + timedelta(seconds=session_seconds)
    return int(session_start.timestamp())

def bar_volume(bar: Bar, volume_mode: int) -> float:
    w = float(bar.tick_volume)
    if volume_mode == VolumeMode.REAL_WITH_TICK_FALLBACK and bar.volume>0:
        w = float(bar.volume)
    if w<=0:
        w=1.0
    return w

def calculate_atr(bars: List[Bar], period: int) -> List[float]:
    n = len(bars)
    atr = [0.0]*n
    tr_sum=0.0
    atr_val=0.0
    count=0
    # oldest first? bars are chronological oldest->newest for our engine
    # But original MQL4 walks backwards, but ATR Wilder is same forward
    for i in range(n):
        if i==0:
            tr = bars[i].high - bars[i].low
        else:
            pc = bars[i-1].close
            tr = max(bars[i].high, pc) - min(bars[i].low, pc)
        tr = max(0.0, tr)
        count+=1
        if count < period:
            tr_sum+=tr
            atr_val = tr_sum / count if count>0 else tr
        elif count == period:
            tr_sum+=tr
            atr_val = tr_sum / period
        else:
            atr_val = ((atr_val*(period-1))+tr)/period
        atr[i]=atr_val
    return atr

def calculate_volume_ma(bars: List[Bar], period: int, volume_mode: int) -> List[float]:
    n=len(bars)
    vma=[0.0]*n
    sum_v=0.0
    for i in range(n):
        v = bar_volume(bars[i], volume_mode)
        sum_v+=v
        if i>=period:
            old_v = bar_volume(bars[i-period], volume_mode)
            sum_v-=old_v
            vma[i]=sum_v/period
        else:
            vma[i]=sum_v/(i+1)
    return vma

def calculate_ema(prices: List[float], period: int) -> List[float]:
    n=len(prices)
    ema=[0.0]*n
    if n==0:
        return ema
    # SMA for first period
    sma=0.0
    for i in range(n):
        if i<period:
            sma+=prices[i]
            ema[i]=sma/(i+1)
        else:
            # first EMA after SMA period uses SMA
            if i==period:
                ema[i]=sma/period
            # Wilder smoothing for EMA: EMA = (price * k) + (prevEMA * (1-k))
            k=2.0/(period+1)
            ema[i]=prices[i]*k + ema[i-1]*(1-k)
    return ema

def calculate_adx(bars: List[Bar], period: int) -> List[float]:
    """
    Simplified ADX Wilder
    """
    n=len(bars)
    if n<period*2:
        return [0.0]*n
    tr_list=[0.0]*n
    plus_dm=[0.0]*n
    minus_dm=[0.0]*n
    for i in range(1,n):
        high = bars[i].high
        low = bars[i].low
        prev_high = bars[i-1].high
        prev_low = bars[i-1].low
        prev_close = bars[i-1].close

        tr = max(high-low, abs(high-prev_close), abs(low-prev_close))
        tr_list[i]=tr

        up_move = high - prev_high
        down_move = prev_low - low

        if up_move>down_move and up_move>0:
            plus_dm[i]=up_move
        else:
            plus_dm[i]=0

        if down_move>up_move and down_move>0:
            minus_dm[i]=down_move
        else:
            minus_dm[i]=0

    # Wilder smoothing
    def wilder_smooth(arr, per):
        smoothed=[0.0]*n
        s=0.0
        for i in range(1,n):
            if i<per:
                s+=arr[i]
                smoothed[i]=s
            elif i==per:
                s+=arr[i]
                smoothed[i]=s
            else:
                smoothed[i]=smoothed[i-1] - smoothed[i-1]/per + arr[i]
        return smoothed

    tr_smooth = wilder_smooth(tr_list, period)
    plus_smooth = wilder_smooth(plus_dm, period)
    minus_smooth = wilder_smooth(minus_dm, period)

    plus_di=[0.0]*n
    minus_di=[0.0]*n
    dx=[0.0]*n
    adx=[0.0]*n

    for i in range(n):
        if tr_smooth[i]!=0:
            plus_di[i]=100*plus_smooth[i]/tr_smooth[i]
            minus_di[i]=100*minus_smooth[i]/tr_smooth[i]
        else:
            plus_di[i]=0
            minus_di[i]=0
        sum_di = plus_di[i]+minus_di[i]
        if sum_di!=0:
            dx[i]=100*abs(plus_di[i]-minus_di[i])/sum_di
        else:
            dx[i]=0

    # ADX is smoothed DX
    dx_sum=0.0
    for i in range(n):
        if i<period*2-1:
            dx_sum+=dx[i]
            if i==period*2-2:
                adx[i]=dx_sum/period
        else:
            adx[i]= (adx[i-1]*(period-1) + dx[i])/period

    return adx

def calculate_vwap_series(bars: List[Bar],
                          anchor_period: int = AnchorPeriod.DAILY,
                          volume_mode: int = VolumeMode.TICK,
                          carry_trend: bool = True,
                          initial_trend: int = 0,
                          london_h=8, london_m=0,
                          ny_h=13, ny_m=30,
                          asia_h=0, asia_m=0,
                          custom_h=0, custom_m=0,
                          custom_anchor_time: Optional[datetime]=None) -> List[VWAPState]:
    """
    Calculates anchored VWAP series and SSL state.
    bars: chronological oldest -> newest
    """
    n=len(bars)
    states: List[VWAPState] = []
    sum_vol=0.0
    high_vwap=0.0
    low_vwap=0.0
    typical_vwap=0.0
    typical_m2=0.0
    active_anchor = INVALID_ANCHOR
    trend_state=0

    for i in range(n):
        bar = bars[i]
        anchor = anchor_key_for_bar(bar.time, anchor_period,
                                    london_h,london_m,ny_h,ny_m,asia_h,asia_m,
                                    custom_h,custom_m,custom_anchor_time)
        if anchor == INVALID_ANCHOR:
            states.append(VWAPState(0,0,0,0,INVALID_ANCHOR,0,False))
            active_anchor=INVALID_ANCHOR
            trend_state=0
            sum_vol=0; high_vwap=0; low_vwap=0; typical_vwap=0; typical_m2=0
            continue

        if anchor != active_anchor:
            sum_vol=0; high_vwap=0; low_vwap=0; typical_vwap=0; typical_m2=0
            active_anchor=anchor
            if not carry_trend:
                trend_state=0

        weight = bar_volume(bar, volume_mode)
        typical = (bar.high + bar.low + bar.close)/3.0
        new_sum = sum_vol + weight
        alpha = weight / new_sum if new_sum!=0 else 0

        high_vwap += alpha * (bar.high - high_vwap)
        low_vwap += alpha * (bar.low - low_vwap)
        delta = typical - typical_vwap
        typical_vwap += alpha * delta
        typical_m2 += weight * delta * (typical - typical_vwap)
        sum_vol = new_sum

        stddev = math.sqrt(max(0.0, typical_m2/sum_vol)) if sum_vol>0 else 0.0

        prior = trend_state
        if prior==0:
            if initial_trend==1:
                trend_state=1
            elif initial_trend==-1:
                trend_state=-1
            else:
                mid = (high_vwap+low_vwap)/2.0
                trend_state = 1 if bar.close>=mid else -1
        else:
            if prior<0 and bar.close>high_vwap:
                trend_state=1
            elif prior>0 and bar.close<low_vwap:
                trend_state=-1
            # else stay

        flipped = (prior!=0 and trend_state!=prior)

        states.append(VWAPState(high_vwap, low_vwap, typical_vwap, stddev, anchor, trend_state, flipped))

    return states

def compute_entry_quality(idx: int,
                          bars: List[Bar],
                          vwap_states: List[VWAPState],
                          atr: List[float],
                          vol_ma: List[float],
                          adx: List[float],
                          ema_fast: List[float],
                          ema_slow: List[float],
                          params: dict,
                          last_flip_idx: int) -> EntryQuality:
    """
    Entry quality engine - mirrors MQL4 ComputeEntryQuality
    params dict contains:
      MinBreakoutATR, MinVolumeFactor, MinADX, ChopThresholdATR, MaxSpreadATR,
      MinBarsBetweenFlips, UseADXFilter, UseEMAFilter, RequireEMABias, UseBandPositionBonus,
      Band1Deviation, AvoidChopZone
    """
    bar = bars[idx]
    state = vwap_states[idx]
    atr_val = atr[idx] if atr[idx]>0 else (bar.high-bar.low if bar.high>bar.low else 1e-5)

    vol = bar_volume(bar, params.get('VolumeMode', VolumeMode.TICK))
    vma = vol_ma[idx] if vol_ma[idx]>0 else vol
    vol_ratio = vol / vma if vma>0 else 1.0

    high_vwap = state.high_vwap
    low_vwap = state.low_vwap
    typical_vwap = state.typical_vwap
    stddev = state.stddev

    breakout_dist = 0.0
    if state.trend>0:
        breakout_dist = bar.close - high_vwap
    else:
        breakout_dist = low_vwap - bar.close

    breakout_atr = breakout_dist / atr_val if atr_val!=0 else 0
    channel_width = high_vwap - low_vwap
    channel_atr = channel_width / atr_val if atr_val!=0 else 0

    # bars since last flip
    if last_flip_idx==-1:
        bars_since = 9999
    else:
        bars_since = idx - last_flip_idx

    # scoring
    min_breakout = params.get('MinBreakoutATR', 0.12)
    min_vol_factor = params.get('MinVolumeFactor', 1.15)
    min_adx = params.get('MinADX', 18.0)
    chop_thr = params.get('ChopThresholdATR', 0.45)
    max_spread_atr = params.get('MaxSpreadATR', 0.35)
    min_bars = params.get('MinBarsBetweenFlips', 5)
    use_adx = params.get('UseADXFilter', True)
    use_ema = params.get('UseEMAFilter', True)
    require_ema = params.get('RequireEMABias', False)
    use_band_bonus = params.get('UseBandPositionBonus', True)
    avoid_chop = params.get('AvoidChopZone', True)
    band_dev = params.get('Band1Deviation', 1.0)

    # 1 breakout 0-25
    if breakout_atr >= min_breakout*2.0:
        s_breakout=25
    elif breakout_atr >= min_breakout:
        s_breakout=15 + 10*(breakout_atr - min_breakout)/max(0.0001,min_breakout)
    elif breakout_atr>=0:
        s_breakout=15*breakout_atr/max(0.0001,min_breakout)
    else:
        s_breakout=0

    # 2 volume 0-20
    if vol_ratio >= min_vol_factor*1.3:
        s_volume=20
    elif vol_ratio >= min_vol_factor:
        s_volume=12 + 8*(vol_ratio - min_vol_factor)/(min_vol_factor*0.3)
    elif vol_ratio >=1.0:
        s_volume=8 + 4*(vol_ratio-1.0)/max(0.0001,(min_vol_factor-1.0))
    elif vol_ratio >=0.7:
        s_volume=4*(vol_ratio-0.7)/0.3
    else:
        s_volume=0

    # 3 ADX 0-15
    if not use_adx:
        s_adx=15
    else:
        adx_val = adx[idx]
        if adx_val >= min_adx*1.5:
            s_adx=15
        elif adx_val >= min_adx:
            s_adx=8 + 7*(adx_val - min_adx)/(min_adx*0.5)
        elif adx_val >= min_adx*0.7:
            s_adx=4 + 4*(adx_val - min_adx*0.7)/(min_adx*0.3)
        else:
            s_adx=2*adx_val/max(0.1,min_adx*0.7)

    # 4 EMA 0-15
    if not use_ema:
        s_ema=15
        aligned=True
        neutral=True
        opposite=False
    else:
        ema_f = ema_fast[idx]
        ema_s = ema_slow[idx]
        c = bar.close
        ema_bull = (c>ema_f and ema_f>ema_s)
        ema_bear = (c<ema_f and ema_f<ema_s)
        aligned = (state.trend>0 and ema_bull) or (state.trend<0 and ema_bear)
        neutral = (state.trend>0 and c>ema_f) or (state.trend<0 and c<ema_f)
        opposite = not aligned and not neutral
        if aligned:
            s_ema=15
        elif neutral:
            s_ema=7
        else:
            s_ema=0

        if require_ema and opposite:
            # forced skip
            reason = f"SKIP: EMA misaligned vs flip | Score 0 | Vol {vol_ratio:.2f} Brk {breakout_atr:.2f}ATR ADX {adx[idx]:.1f}"
            return EntryQuality(0, Decision.SKIP,
                                {"breakout":s_breakout,"volume":s_volume,"adx":s_adx,"ema":s_ema,"chop":0,"gap":0,"band":0,"spread":0},
                                reason, vol_ratio, breakout_atr, adx[idx], channel_atr, bars_since)

    # 5 chop 0-10
    if not avoid_chop:
        s_chop=10
    else:
        if channel_atr >= chop_thr*1.8:
            s_chop=10
        elif channel_atr >= chop_thr:
            s_chop=5 + 5*(channel_atr - chop_thr)/(chop_thr*0.8)
        else:
            s_chop=5*channel_atr/max(0.0001,chop_thr)

    # 6 bars since 0-10
    if bars_since>=min_bars*3:
        s_gap=10
    elif bars_since>=min_bars:
        s_gap=4 + 6*(bars_since - min_bars)/(min_bars*2.0) if min_bars>0 else 10
    elif bars_since>=0:
        s_gap=4*bars_since/max(1,min_bars)
    else:
        s_gap=10

    # 7 band bonus 0-5
    if not use_band_bonus:
        s_band=5
    else:
        was_beyond=False
        if idx>0:
            prev_typical = vwap_states[idx-1].typical_vwap
            prev_std = vwap_states[idx-1].stddev
            prev_close = bars[idx-1].close
            if state.trend>0:
                was_beyond = (prev_close < prev_typical - band_dev*prev_std)
            else:
                was_beyond = (prev_close > prev_typical + band_dev*prev_std)
        s_band = 5 if was_beyond else 2

    # 8 spread 0-5
    spread_price = bar.spread
    spread_atr = spread_price/atr_val if atr_val>0 else 0
    if spread_atr <= max_spread_atr*0.5:
        s_spread=5
    elif spread_atr <= max_spread_atr:
        s_spread=2 + 3*(max_spread_atr - spread_atr)/(max_spread_atr*0.5)
    else:
        s_spread=0

    score = s_breakout + s_volume + s_adx + s_ema + s_chop + s_gap + s_band + s_spread
    score = max(0, min(100, score))

    min_enter = params.get('MinScoreToEnter',70)
    min_caution = params.get('MinScoreToCaution',50)

    if score >= min_enter:
        decision = Decision.ENTER
    elif score >= min_caution:
        decision = Decision.CAUTION
    else:
        decision = Decision.SKIP

    breakdown = {
        "breakout": s_breakout,
        "volume": s_volume,
        "adx": s_adx,
        "ema": s_ema,
        "chop": s_chop,
        "gap": s_gap,
        "band": s_band,
        "spread": s_spread
    }

    reason = f"{Decision.to_str(decision)} ({score:.0f}) | B:{s_breakout:.0f} V:{s_volume:.0f} ADX:{s_adx:.0f} EMA:{s_ema:.0f} CH:{s_chop:.0f} GAP:{s_gap:.0f} BD:{s_band:.0f} SP:{s_spread:.0f} | Volx{vol_ratio:.2f} Brk{breakout_atr:.2f}ATR ADX{adx[idx]:.1f} Ch{channel_atr:.2f}ATR {bars_since}bars"

    return EntryQuality(score, decision, breakdown, reason, vol_ratio, breakout_atr, adx[idx], channel_atr, bars_since)

def run_full_engine(bars: List[Bar], params: dict):
    """
    Runs full engine and returns list of dicts for each bar with all computed values
    """
    anchor_period = params.get('AnchorPeriod', AnchorPeriod.DAILY)
    volume_mode = params.get('VolumeMode', VolumeMode.TICK)
    atr_period = params.get('ArrowATRPeriod', 14)
    vol_ma_period = params.get('VolumeMAPeriod', 20)
    adx_period = params.get('ADXPeriod', 14)
    ema_fast_period = params.get('EMAFast', 50)
    ema_slow_period = params.get('EMASlow', 200)

    vwap_states = calculate_vwap_series(bars, anchor_period, volume_mode,
                                        params.get('CarryTrendAcrossAnchors', True),
                                        params.get('InitialTrend', 0))

    atr = calculate_atr(bars, atr_period)
    vol_ma = calculate_volume_ma(bars, vol_ma_period, volume_mode)
    adx = calculate_adx(bars, adx_period)
    closes = [b.close for b in bars]
    ema_fast = calculate_ema(closes, ema_fast_period)
    ema_slow = calculate_ema(closes, ema_slow_period)

    results=[]
    last_flip_idx=-1
    for i in range(len(bars)):
        entry = None
        if vwap_states[i].flipped:
            entry = compute_entry_quality(i, bars, vwap_states, atr, vol_ma, adx, ema_fast, ema_slow, params, last_flip_idx)
            last_flip_idx=i
        results.append({
            "bar": bars[i],
            "vwap": vwap_states[i],
            "atr": atr[i],
            "vol_ma": vol_ma[i],
            "adx": adx[i],
            "ema_fast": ema_fast[i],
            "ema_slow": ema_slow[i],
            "entry": entry
        })
    return results
