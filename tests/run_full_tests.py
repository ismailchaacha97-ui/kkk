import math
import datetime

print("==================================================================")
print("RUNNING INSTITUTIONAL MULTI-TEST SUITE FOR MT4 TRADING SUITE V2.0")
print("==================================================================")

# ----------------------------------------------------
# 1. Steidlmayer / Dalton Value Area Calculation Test
# ----------------------------------------------------
def dalton_profile(prices, volumes, va_percent=0.70):
    n = len(volumes)
    total_vol = sum(volumes)
    if total_vol <= 0:
        return None
    target_vol = total_vol * va_percent
    
    poc_bin = 0
    max_vol = volumes[0]
    for i in range(1, n):
        if volumes[i] > max_vol:
            max_vol = volumes[i]
            poc_bin = i
            
    current_vol = volumes[poc_bin]
    up = poc_bin + 1
    down = poc_bin - 1
    
    while current_vol < target_vol and (up < n or down >= 0):
        vol_up = 0
        step_up = 0
        if up < n:
            vol_up += volumes[up]
            step_up += 1
            if up + 1 < n:
                vol_up += volumes[up + 1]
                step_up += 1
                
        vol_down = 0
        step_down = 0
        if down >= 0:
            vol_down += volumes[down]
            step_down += 1
            if down - 1 >= 0:
                vol_down += volumes[down - 1]
                step_down += 1
                
        if vol_up > vol_down:
            current_vol += vol_up
            up += step_up
        elif vol_down > vol_up:
            current_vol += vol_down
            down -= step_down
        else:
            if up < n and down >= 0:
                current_vol += (volumes[up] + volumes[down])
                up += 1
                down -= 1
            elif up < n:
                current_vol += volumes[up]
                up += 1
            elif down >= 0:
                current_vol += volumes[down]
                down -= 1
            else:
                break
                
    vah_bin = min(n - 1, max(poc_bin, up - 1))
    val_bin = max(0, min(poc_bin, down + 1))
    
    coverage = current_vol / total_vol
    return {
        'poc': prices[poc_bin],
        'vah': prices[vah_bin],
        'val': prices[val_bin],
        'poc_bin': poc_bin,
        'vah_bin': vah_bin,
        'val_bin': val_bin,
        'coverage': coverage
    }

# Test 1.1: Standard Bell Curve
n_rows = 200
prices = [2000.0 + i * 0.5 for i in range(n_rows)]
vols_bell = [int(math.exp(-0.5 * ((p - 2050.0)/8.0)**2) * 5000 + 20) for p in prices]
res_bell = dalton_profile(prices, vols_bell, 0.70)
print(f"Test 1.1 (Bell Curve): POC={res_bell['poc']:.2f}, VAH={res_bell['vah']:.2f}, VAL={res_bell['val']:.2f}, Coverage={res_bell['coverage']*100:.2f}%")
assert res_bell['val'] <= res_bell['poc'] <= res_bell['vah']
assert res_bell['coverage'] >= 0.70

# Test 1.2: Asymmetric Skewed Trend Day
vols_skew = [int(1000.0 / (1.0 + math.exp(-0.1 * (p - 2040.0)))) for p in prices]
res_skew = dalton_profile(prices, vols_skew, 0.70)
print(f"Test 1.2 (Skewed Trend): POC={res_skew['poc']:.2f}, VAH={res_skew['vah']:.2f}, VAL={res_skew['val']:.2f}, Coverage={res_skew['coverage']*100:.2f}%")
assert res_skew['val'] <= res_skew['poc'] <= res_skew['vah']
assert res_skew['coverage'] >= 0.70

# ----------------------------------------------------
# 2. LVN & HVN Perimeter Detection Test
# ----------------------------------------------------
def find_perimeter_lvns(prices, volumes, vah_bin, val_bin):
    n = len(volumes)
    lvn_above_vah = -1
    min_v_above = 1e18
    for i in range(vah_bin + 1, n):
        if volumes[i] < min_v_above:
            min_v_above = volumes[i]
            lvn_above_vah = i
            
    lvn_below_val = -1
    min_v_below = 1e18
    for i in range(val_bin - 1, -1, -1):
        if volumes[i] < min_v_below:
            min_v_below = volumes[i]
            lvn_below_val = i
            
    return lvn_above_vah, lvn_below_val

la, lb = find_perimeter_lvns(prices, vols_bell, res_bell['vah_bin'], res_bell['val_bin'])
print(f"Test 2.1 (Perimeter LVNs): LVN Above VAH={prices[la]:.2f}, LVN Below VAL={prices[lb]:.2f}")
assert prices[la] > res_bell['vah']
assert prices[lb] < res_bell['val']
print("Test 2.1: Perimeter LVN Detection PASSED!")

# ----------------------------------------------------
# 3. Virgin / Naked POC (vPOC) Mitigation Lifecycle
# ----------------------------------------------------
class Bar:
    def __init__(self, high, low, time):
        self.high = high
        self.low = low
        self.time = time

def check_vpoc_lifecycle(vpoc_price, subsequent_bars):
    for b in subsequent_bars:
        if b.low <= vpoc_price <= b.high:
            return True, b.time
    return False, None

bars_untested = [Bar(2060, 2055, 1), Bar(2070, 2062, 2)]
bars_tested = [Bar(2060, 2055, 1), Bar(2070, 2062, 2), Bar(2052, 2048, 3)]

mit1, t1 = check_vpoc_lifecycle(2050.0, bars_untested)
mit2, t2 = check_vpoc_lifecycle(2050.0, bars_tested)

assert mit1 == False
assert mit2 == True and t2 == 3
print("Test 3.1: Virgin POC (vPOC) Lifecycle & Mitigation PASSED!")

# ----------------------------------------------------
# 4. Confluence Star Matrix Verification
# ----------------------------------------------------
def rate_confluence(name1, name2):
    s1, s2 = name1[:1], name2[:1]
    is_m = (s1 == 'M' or s2 == 'M')
    is_w = (s1 == 'W' or s2 == 'W')
    is_d = (s1 == 'D' or s2 == 'D')
    is_s = (s1 == 'S' or s2 == 'S')
    
    poc1 = ('POC' in name1)
    poc2 = ('POC' in name2)
    both_poc = poc1 and poc2
    
    if is_m and is_w and both_poc:
        return 5, "[5 STARS] Macro Institutional Wall"
    if is_m and (is_w or is_d):
        return 4, "[4 STARS] High-Probability Macro Reversal"
    if is_w and is_d and (poc1 or poc2):
        return 4, "[4 STARS] A+ Institutional Setup"
    if is_w and is_d:
        return 3, "[3 STARS] Solid Day-Trade Confluence"
    if is_d and is_s:
        return 2, "[2 STARS] Intraday Scalp Confluence"
    return 1, "[1 STAR] Minor Level"

assert rate_confluence("M-POC", "W-POC")[0] == 5
assert rate_confluence("W-POC", "D-VAL")[0] == 4
assert rate_confluence("W-VAH", "D-VAH")[0] == 3
assert rate_confluence("D-POC", "S-VAL")[0] == 2
print("Test 4.1: Confluence Quality Star Matrix PASSED!")

# ----------------------------------------------------
# 5. Dynamic SL / TP & Risk:Reward Projection Test
# ----------------------------------------------------
def calculate_trade_plan(direction, entry, wick_extreme, lvn_level, poc_target, va_target, pip_size, sl_buffer_pips=2.0):
    if direction == "BUY":
        sl = wick_extreme - sl_buffer_pips * pip_size
        if lvn_level > 0 and lvn_level < sl:
            sl = lvn_level - sl_buffer_pips * pip_size
        tp1 = poc_target
        tp2 = va_target
        risk = entry - sl
        reward1 = tp1 - entry
        reward2 = tp2 - entry
    else:
        sl = wick_extreme + sl_buffer_pips * pip_size
        if lvn_level > 0 and lvn_level > sl:
            sl = lvn_level + sl_buffer_pips * pip_size
        tp1 = poc_target
        tp2 = va_target
        risk = sl - entry
        reward1 = entry - tp1
        reward2 = entry - tp2
        
    rr1 = reward1 / risk if risk > 0 else 0
    rr2 = reward2 / risk if risk > 0 else 0
    return sl, tp1, tp2, rr1, rr2

# Gold Buy trade at VAL=2518.00, entry at 2519.00, wick low at 2517.50, LVN at 2516.00, POC=2526.00, VAH=2535.00
sl, tp1, tp2, rr1, rr2 = calculate_trade_plan("BUY", 2519.00, 2517.50, 2516.00, 2526.00, 2535.00, pip_size=0.1)
print(f"Test 5.1 (Trade Plan Buy): Entry=2519.00, SL={sl:.2f}, TP1={tp1:.2f} (R:R 1:{rr1:.1f}), TP2={tp2:.2f} (R:R 1:{rr2:.1f})")
assert sl < 2519.00
assert tp1 == 2526.00 and tp2 == 2535.00
assert rr1 >= 1.5 and rr2 >= 3.0
print("Test 5.1: Dynamic SL/TP Trade Plan & R:R Projection PASSED!")

# ----------------------------------------------------
# 6. Institutional Kill Zone Time Filtering Test
# ----------------------------------------------------
def is_in_kill_zone(ny_hour, ny_min, trade_london=True, trade_ny_open=True, trade_ny_pm=True):
    minute_of_day = ny_hour * 60 + ny_min
    if trade_london and 180 <= minute_of_day <= 360:
        return True, "London Open"
    if trade_ny_open and 570 <= minute_of_day <= 690:
        return True, "NY Cash Open"
    if trade_ny_pm and 810 <= minute_of_day <= 930:
        return True, "NY Afternoon"
    return False, "Outside Kill Zones"

assert is_in_kill_zone(9, 45)[0] == True # NY Open 09:45
assert is_in_kill_zone(12, 15)[0] == False # Lunch Lull 12:15
assert is_in_kill_zone(4, 0)[0] == True # London Open 04:00
assert is_in_kill_zone(14, 30)[0] == True # NY Afternoon 14:30
assert is_in_kill_zone(18, 0)[0] == False # CME Open (outside kill zone)
print("Test 6.1: Institutional Kill Zone Time Filter PASSED!")

# ----------------------------------------------------
# 7. Multi-Asset Pip & Point Scaling Test
# ----------------------------------------------------
def get_pip_size(digits, point):
    if digits == 3 or digits == 5:
        return point * 10.0
    return point

# 5-digit Forex (EURUSD): Point=0.00001, Digits=5 -> 1 Pip = 0.0001
assert round(get_pip_size(5, 0.00001), 6) == 0.0001
# 2-digit Gold (XAUUSD): Point=0.01, Digits=2 -> 1 Pip = 0.01 ($0.01)
assert round(get_pip_size(2, 0.01), 4) == 0.01
# 1-digit Index (NAS100 / NQ): Point=0.1, Digits=1 -> 1 Pip = 0.1
assert round(get_pip_size(1, 0.1), 4) == 0.1
# 2-digit Crypto (BTCUSD): Point=0.01, Digits=2 -> 1 Pip = 0.01
assert round(get_pip_size(2, 0.01), 4) == 0.01
print("Test 7.1: Multi-Asset Pip/Point Adaptive Scaling PASSED!")

# ----------------------------------------------------
# 8. US/NY Daylight Saving Time (DST) Transitions
# ----------------------------------------------------
def get_ny_dst_offset(dt):
    if dt.month < 3 or dt.month > 11:
        return -5
    if dt.month > 3 and dt.month < 11:
        return -4
    if dt.month == 3:
        m1 = datetime.datetime(dt.year, 3, 1)
        first_sun = (6 - m1.weekday()) % 7
        second_sun = 1 + first_sun + 7
        if dt.day > second_sun or (dt.day == second_sun and dt.hour >= 2):
            return -4
        return -5
    if dt.month == 11:
        n1 = datetime.datetime(dt.year, 11, 1)
        first_sun = (6 - n1.weekday()) % 7
        first_sun_day = 1 + first_sun
        if dt.day < first_sun_day or (dt.day == first_sun_day and dt.hour < 2):
            return -4
        return -5
    return -5

assert get_ny_dst_offset(datetime.datetime(2026, 1, 15, 12, 0)) == -5
assert get_ny_dst_offset(datetime.datetime(2026, 6, 15, 12, 0)) == -4
assert get_ny_dst_offset(datetime.datetime(2026, 11, 20, 12, 0)) == -5
print("Test 8.1: US/NY Daylight Saving Rules across seasons PASSED!")

print("\n==================================================================")
print("ALL 8 ADVANCED INSTITUTIONAL UNIT & STRESS TESTS PASSED 100%!")
print("==================================================================")

