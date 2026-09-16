"""
Holy Grail VWAP SSL Flip v7 - Big Move Edition
Python Engine - mirrors MQL4 v7 logic

Optimized for Weekly/Monthly VWAP on small TF (M15/H1) to catch 1:3, 1:5, 1:8+ moves

New in v7:
- Anchor progress tracking (how far through week/month)
- Big Move RR calculation: distance to 2SD/3SD bands vs SL
- Big Move scoring: RR potential, early anchor bonus, exhaustion check
- Multi-TP risk planner
- SL modes: ATR, opposite VWAP, band1
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import List, Optional, Dict
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

class SLMode:
    ATR = 0
    OPPOSITE_VWAP = 1
    BAND1 = 2
    STRUCTURE = 3

@dataclass
class Bar:
    time: datetime
    open: float
    high: float
    low: float
    close: float
    tick_volume: int
    volume: int = 0
    spread: float = 0.0

@dataclass
class VWAPState:
    high_vwap: float
    low_vwap: float
    typical_vwap: float
    stddev: float
    anchor_key: int
    anchor_start: datetime
    anchor_progress: float
    trend: int
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
    big_move_rr_2sd: float
    big_move_rr_3sd: float
    anchor_progress: float

def start_of_day(dt: datetime) -> datetime:
    return dt.replace(hour=0, minute=0, second=0, microsecond=0)

def anchor_start_time(bar_time: datetime, anchor_period: int,
                      london_h=8, london_m=0,
                      ny_h=13, ny_m=30,
                      asia_h=0, asia_m=0,
                      custom_h=0, custom_m=0,
                      custom_anchor_time: Optional[datetime]=None) -> datetime:
    if anchor_period == AnchorPeriod.CUSTOM_TIME:
        return custom_anchor_time if custom_anchor_time else bar_time
    if anchor_period == AnchorPeriod.DAILY:
        return start_of_day(bar_time)
    if anchor_period == AnchorPeriod.WEEKLY:
        sod = start_of_day(bar_time)
        dow = bar_time.weekday()
        return sod - timedelta(days=dow)
    if anchor_period == AnchorPeriod.MONTHLY:
        return bar_time.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    if anchor_period == AnchorPeriod.QUARTERLY:
        q = (bar_time.month-1)//3
        m = q*3+1
        return bar_time.replace(month=m, day=1, hour=0, minute=0, second=0, microsecond=0)
    if anchor_period == AnchorPeriod.YEARLY:
        return bar_time.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
    # sessions
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
    sess_sec = hour*3600 + minute*60
    day = start_of_day(bar_time)
    sec_into = int((bar_time - day).total_seconds())
    if sec_into < sess_sec:
        day = day - timedelta(days=1)
    return day + timedelta(seconds=sess_sec)

def anchor_key_for_bar(bar_time: datetime, anchor_period: int,
                       london_h=8, london_m=0,
                       ny_h=13, ny_m=30,
                       asia_h=0, asia_m=0,
                       custom_h=0, custom_m=0,
                       custom_anchor_time: Optional[datetime]=None) -> int:
    if anchor_period == AnchorPeriod.CUSTOM_TIME:
        if custom_anchor_time is None:
            return INVALID_ANCHOR
        if bar_time >= custom_anchor_time:
            return int(custom_anchor_time.timestamp())
        else:
            return INVALID_ANCHOR
    if anchor_period == AnchorPeriod.DAILY:
        sod = start_of_day(bar_time)
        return int(sod.timestamp())
    if anchor_period == AnchorPeriod.WEEKLY:
        sod = start_of_day(bar_time)
        dow = bar_time.weekday()
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

def calculate_anchor_progress(bar_time: datetime, anchor_start: datetime, anchor_period: int) -> float:
    if anchor_start is None:
        return 0.0
    elapsed = (bar_time - anchor_start).total_seconds()
    if anchor_period == AnchorPeriod.DAILY:
        duration = 86400
    elif anchor_period == AnchorPeriod.WEEKLY:
        duration = 5*86400
    elif anchor_period == AnchorPeriod.MONTHLY:
        # days in month
        y = bar_time.year
        m = bar_time.month
        if m == 12:
            next_month = datetime(y+1, 1, 1)
        else:
            next_month = datetime(y, m+1, 1)
        this_month = datetime(y, m, 1)
        duration = (next_month - this_month).total_seconds()
    elif anchor_period == AnchorPeriod.QUARTERLY:
        duration = 90*86400
    elif anchor_period == AnchorPeriod.YEARLY:
        duration = 365*86400
    else:
        duration = 86400
    if duration <= 0:
        return 0.0
    prog = elapsed / duration
    return max(0.0, min(1.0, prog))

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
    sma=0.0
    for i in range(n):
        if i<period:
            sma+=prices[i]
            ema[i]=sma/(i+1)
        else:
            if i==period:
                ema[i]=sma/period
            k=2.0/(period+1)
            ema[i]=prices[i]*k + ema[i-1]*(1-k)
    return ema

def calculate_adx(bars: List[Bar], period: int) -> List[float]:
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
        sum_di = plus_di[i]+minus_di[i]
        if sum_di!=0:
            dx[i]=100*abs(plus_di[i]-minus_di[i])/sum_di
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
    n=len(bars)
    states: List[VWAPState] = []
    sum_vol=0.0
    high_vwap=0.0
    low_vwap=0.0
    typical_vwap=0.0
    typical_m2=0.0
    active_anchor = INVALID_ANCHOR
    trend_state=0
    anchor_start = None

    for i in range(n):
        bar = bars[i]
        anchor = anchor_key_for_bar(bar.time, anchor_period,
                                    london_h,london_m,ny_h,ny_m,asia_h,asia_m,
                                    custom_h,custom_m,custom_anchor_time)
        this_anchor_start = anchor_start_time(bar.time, anchor_period,
                                              london_h,london_m,ny_h,ny_m,asia_h,asia_m,
                                              custom_h,custom_m,custom_anchor_time)
        if anchor == INVALID_ANCHOR:
            states.append(VWAPState(0,0,0,0,INVALID_ANCHOR, this_anchor_start, 0, 0, False))
            active_anchor=INVALID_ANCHOR
            trend_state=0
            sum_vol=0; high_vwap=0; low_vwap=0; typical_vwap=0; typical_m2=0
            anchor_start=None
            continue

        if anchor != active_anchor:
            sum_vol=0; high_vwap=0; low_vwap=0; typical_vwap=0; typical_m2=0
            active_anchor=anchor
            anchor_start = this_anchor_start
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
        progress = calculate_anchor_progress(bar.time, anchor_start, anchor_period) if anchor_start else 0.0

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

        flipped = (prior!=0 and trend_state!=prior)

        states.append(VWAPState(high_vwap, low_vwap, typical_vwap, stddev, anchor, anchor_start, progress, trend_state, flipped))

    return states

def compute_entry_quality_v7(idx: int,
                             bars: List[Bar],
                             vwap_states: List[VWAPState],
                             atr: List[float],
                             vol_ma: List[float],
                             adx: List[float],
                             ema_fast: List[float],
                             ema_slow: List[float],
                             params: dict,
                             last_flip_idx: int) -> EntryQuality:
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
    progress = state.anchor_progress

    breakout_dist = 0.0
    if state.trend>0:
        breakout_dist = bar.close - high_vwap
    else:
        breakout_dist = low_vwap - bar.close

    breakout_atr = breakout_dist / atr_val if atr_val!=0 else 0
    channel_width = high_vwap - low_vwap
    channel_atr = channel_width / atr_val if atr_val!=0 else 0

    if last_flip_idx==-1:
        bars_since = 9999
    else:
        bars_since = idx - last_flip_idx

    # SL distance for RR calc
    sl_mode = params.get('SLMode', SLMode.ATR)
    sl_atr_mult = params.get('StopLossATR', 1.5)
    band1_dev = params.get('Band1Deviation', 1.0)
    band2_dev = params.get('Band2Deviation', 2.0)
    band3_dev = params.get('Band3Deviation', 3.0)

    if sl_mode == SLMode.ATR:
        sl_dist = atr_val * sl_atr_mult
    elif sl_mode == SLMode.OPPOSITE_VWAP:
        sl_dist = abs(bar.close - (low_vwap if state.trend>0 else high_vwap))
    elif sl_mode == SLMode.BAND1:
        band = (typical_vwap - band1_dev*stddev) if state.trend>0 else (typical_vwap + band1_dev*stddev)
        sl_dist = abs(bar.close - band)
    else:
        sl_dist = atr_val * sl_atr_mult
    if sl_dist <=0:
        sl_dist = atr_val * sl_atr_mult

    # targets for big move
    target_2sd = (typical_vwap + band2_dev*stddev) if state.trend>0 else (typical_vwap - band2_dev*stddev)
    target_3sd = (typical_vwap + band3_dev*stddev) if state.trend>0 else (typical_vwap - band3_dev*stddev)
    dist_2sd = abs(target_2sd - bar.close)
    dist_3sd = abs(target_3sd - bar.close)
    rr_2sd = dist_2sd / sl_dist if sl_dist>0 else 0
    rr_3sd = dist_3sd / sl_dist if sl_dist>0 else 0

    # params
    min_breakout = params.get('MinBreakoutATR', 0.10)
    min_vol_factor = params.get('MinVolumeFactor', 1.10)
    min_adx = params.get('MinADX', 16.0)
    chop_thr = params.get('ChopThresholdATR', 0.40)
    max_spread_atr = params.get('MaxSpreadATR', 0.35)
    min_bars = params.get('MinBarsBetweenFlips', 5)
    use_adx = params.get('UseADXFilter', True)
    use_ema = params.get('UseEMAFilter', True)
    require_ema = params.get('RequireEMABias', False)
    use_band_bonus = params.get('UseBandPositionBonus', True)
    avoid_chop = params.get('AvoidChopZone', True)
    band_dev = params.get('Band1Deviation', 1.0)

    # big move params
    use_big_move = params.get('UseBigMoveMode', True)
    big_move_min_rr = params.get('BigMoveMinRR', 3.0)
    avoid_late = params.get('AvoidLateAnchor', True)
    max_progress = params.get('MaxAnchorProgress', 0.80)
    prefer_early = params.get('PreferEarlyAnchor', True)
    early_thr = params.get('EarlyAnchorBonusThreshold', 0.35)
    check_exhaustion = params.get('CheckBandExhaustion', True)
    exhaustion_sd = params.get('ExhaustionSD', 2.5)
    use_rr_filter = params.get('UseBigMoveRRFilter', True)
    min_dist_band_atr = params.get('MinDistanceToBandATR', 2.0)

    # scoring - v7: 10 components, 100 total
    # breakout 20, volume 15, adx 10, ema 10, chop 8, gap 7, band 5, spread 5, bigmove 15, anchor 5 = 100
    s_breakout=0; s_volume=0; s_adx=0; s_ema=0; s_chop=0; s_gap=0; s_band=0; s_spread=0; s_bigmove=0; s_anchor=0

    if breakout_atr >= min_breakout*2.0:
        s_breakout=20
    elif breakout_atr >= min_breakout:
        s_breakout=12 + 8*(breakout_atr - min_breakout)/max(0.0001,min_breakout)
    elif breakout_atr>=0:
        s_breakout=12*breakout_atr/max(0.0001,min_breakout)

    if vol_ratio >= min_vol_factor*1.3:
        s_volume=15
    elif vol_ratio >= min_vol_factor:
        s_volume=9 + 6*(vol_ratio - min_vol_factor)/(min_vol_factor*0.3)
    elif vol_ratio >=1.0:
        s_volume=6 + 3*(vol_ratio-1.0)/max(0.0001,(min_vol_factor-1.0))
    elif vol_ratio >=0.7:
        s_volume=3*(vol_ratio-0.7)/0.3

    if not use_adx:
        s_adx=10
    else:
        adx_val = adx[idx]
        if adx_val >= min_adx*1.5:
            s_adx=10
        elif adx_val >= min_adx:
            s_adx=6 + 4*(adx_val - min_adx)/(min_adx*0.5)
        elif adx_val >= min_adx*0.7:
            s_adx=3 + 3*(adx_val - min_adx*0.7)/(min_adx*0.3)
        else:
            s_adx=2*adx_val/max(0.1,min_adx*0.7)

    if not use_ema:
        s_ema=10
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
            s_ema=10
        elif neutral:
            s_ema=5
        else:
            s_ema=0
        if require_ema and opposite:
            reason = f"SKIP: EMA misaligned | Vol {vol_ratio:.2f} Brk {breakout_atr:.2f}ATR ADX {adx[idx]:.1f}"
            return EntryQuality(0, Decision.SKIP,
                                {"breakout":s_breakout,"volume":s_volume,"adx":s_adx,"ema":s_ema,"chop":0,"gap":0,"band":0,"spread":0,"bigmove":0,"anchor":0},
                                reason, vol_ratio, breakout_atr, adx[idx], channel_atr, bars_since, rr_2sd, rr_3sd, progress)

    if not avoid_chop:
        s_chop=8
    else:
        if channel_atr >= chop_thr*1.8:
            s_chop=8
        elif channel_atr >= chop_thr:
            s_chop=4 + 4*(channel_atr - chop_thr)/(chop_thr*0.8)
        else:
            s_chop=4*channel_atr/max(0.0001,chop_thr)

    if bars_since>=min_bars*3:
        s_gap=7
    elif bars_since>=min_bars:
        s_gap=3 + 4*(bars_since - min_bars)/(min_bars*2.0) if min_bars>0 else 7
    elif bars_since>=0:
        s_gap=3*bars_since/max(1,min_bars)
    else:
        s_gap=7

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

    spread_price = bar.spread
    spread_atr = spread_price/atr_val if atr_val>0 else 0
    if spread_atr <= max_spread_atr*0.5:
        s_spread=5
    elif spread_atr <= max_spread_atr:
        s_spread=2 + 3*(max_spread_atr - spread_atr)/(max_spread_atr*0.5)
    else:
        s_spread=0

    # big move scoring
    if not use_big_move:
        s_bigmove=15
    else:
        min_dist_ok = 1 if dist_2sd >= atr_val*min_dist_band_atr else 0
        if rr_2sd >= big_move_min_rr*1.5:
            s_bigmove=15
        elif rr_2sd >= big_move_min_rr:
            s_bigmove=10 + 5*(rr_2sd - big_move_min_rr)/(big_move_min_rr*0.5)
        elif rr_2sd >= big_move_min_rr*0.6:
            s_bigmove=5 + 5*(rr_2sd - big_move_min_rr*0.6)/(big_move_min_rr*0.4)
        else:
            s_bigmove=3*rr_2sd/max(0.1,big_move_min_rr*0.6)
        if min_dist_ok==0:
            s_bigmove*=0.5
        if check_exhaustion:
            dist_from_typical = abs(bar.close - typical_vwap)
            sd_mult = dist_from_typical/stddev if stddev>0 else 0
            if sd_mult >= exhaustion_sd:
                s_bigmove*=0.2
        if use_rr_filter and rr_2sd < big_move_min_rr*0.5:
            s_bigmove=min(s_bigmove,2)

    # anchor progress scoring
    if not use_big_move or not avoid_late:
        s_anchor=5
    else:
        if progress <= early_thr and prefer_early:
            s_anchor=5
        elif progress <= max_progress*0.7:
            s_anchor=4
        elif progress <= max_progress:
            s_anchor=2 + 2*(max_progress - progress)/(max_progress*0.3)
        else:
            s_anchor=0

    score = s_breakout + s_volume + s_adx + s_ema + s_chop + s_gap + s_band + s_spread + s_bigmove + s_anchor
    score = max(0, min(100, score))

    min_enter = params.get('MinScoreToEnter',68)
    min_caution = params.get('MinScoreToCaution',50)

    if score >= min_enter:
        decision = Decision.ENTER
    elif score >= min_caution:
        decision = Decision.CAUTION
    else:
        decision = Decision.SKIP

    if use_big_move and avoid_late and progress > max_progress and use_rr_filter and rr_2sd < big_move_min_rr:
        decision = Decision.SKIP

    breakdown = {
        "breakout": s_breakout,
        "volume": s_volume,
        "adx": s_adx,
        "ema": s_ema,
        "chop": s_chop,
        "gap": s_gap,
        "band": s_band,
        "spread": s_spread,
        "bigmove": s_bigmove,
        "anchor": s_anchor
    }

    reason = f"{Decision.to_str(decision)} ({score:.0f}) RR{rr_2sd:.1f}->2SD {rr_3sd:.1f}->3SD | B:{s_breakout:.0f} V:{s_volume:.0f} ADX:{s_adx:.0f} EMA:{s_ema:.0f} BM:{s_bigmove:.0f} AP:{s_anchor:.0f} | Volx{vol_ratio:.2f} Brk{breakout_atr:.2f}ATR ADX{adx[idx]:.0f} Prog{progress*100:.0f}% {bars_since}bars"

    return EntryQuality(score, decision, breakdown, reason, vol_ratio, breakout_atr, adx[idx], channel_atr, bars_since, rr_2sd, rr_3sd, progress)

def run_full_engine_v7(bars: List[Bar], params: dict):
    anchor_period = params.get('AnchorPeriod', AnchorPeriod.WEEKLY)
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
            entry = compute_entry_quality_v7(i, bars, vwap_states, atr, vol_ma, adx, ema_fast, ema_slow, params, last_flip_idx)
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
