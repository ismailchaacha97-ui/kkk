import math
import datetime

print("==================================================")
print("RUNNING INSTITUTIONAL TEST SUITE FOR MT4 INDICATOR")
print("==================================================")

# ----------------------------------------------------
# 1. Steidlmayer / Dalton Value Area Calculation Test
# ----------------------------------------------------
def dalton_profile(prices, volumes, va_percent=0.70):
    n = len(volumes)
    total_vol = sum(volumes)
    if total_vol <= 0:
        return None
    target_vol = total_vol * va_percent
    
    # POC
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

# Test 1.1: Standard Bell Curve (Nasdaq / Gold balanced day)
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

# Test 1.3: Bimodal (Double Distribution Trend Day)
vols_bimodal = [int(math.exp(-0.5 * ((p - 2025.0)/4.0)**2) * 3000 + math.exp(-0.5 * ((p - 2075.0)/4.0)**2) * 4000 + 10) for p in prices]
res_bimodal = dalton_profile(prices, vols_bimodal, 0.70)
print(f"Test 1.3 (Bimodal Day): POC={res_bimodal['poc']:.2f}, VAH={res_bimodal['vah']:.2f}, VAL={res_bimodal['val']:.2f}, Coverage={res_bimodal['coverage']*100:.2f}%")
assert res_bimodal['val'] <= res_bimodal['poc'] <= res_bimodal['vah']
assert res_bimodal['coverage'] >= 0.70

# ----------------------------------------------------
# 2. Timezone & New York DST Transition Test
# ----------------------------------------------------
def get_ny_dst_offset(dt):
    if dt.month < 3 or dt.month > 11:
        return -5 # EST
    if dt.month > 3 and dt.month < 11:
        return -4 # EDT
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
assert get_ny_dst_offset(datetime.datetime(2026, 3, 1, 12, 0)) == -5
assert get_ny_dst_offset(datetime.datetime(2026, 3, 15, 12, 0)) == -4
assert get_ny_dst_offset(datetime.datetime(2026, 7, 4, 12, 0)) == -4
assert get_ny_dst_offset(datetime.datetime(2026, 11, 10, 12, 0)) == -5
print("Test 2.1 (US/NY Daylight Saving Rules): PASSED across all seasons!")

# ----------------------------------------------------
# 3. Confluence Detection Engine Test
# ----------------------------------------------------
def test_confluence(levels, threshold_pips, pip_size=0.1):
    threshold = threshold_pips * pip_size
    confluences = []
    items = list(levels.items())
    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            k1, v1 = items[i]
            k2, v2 = items[j]
            if k1[0] == k2[0]: # Same timeframe
                continue
            diff = abs(v1 - v2)
            if diff <= threshold:
                confluences.append((k1, k2, (v1 + v2)/2.0, diff / pip_size))
    return confluences

levels_test = {
    'S-POC': 19520.0,
    'S-VAH': 19580.0,
    'S-VAL': 19480.0,
    'D-POC': 19500.0,
    'D-VAH': 19560.0,
    'D-VAL': 19450.0,
    'W-POC': 19500.5, # Confluent with D-POC (diff 0.5 = 5 pips)
    'W-VAH': 19650.0,
    'W-VAL': 19400.0,
    'M-POC': 19560.8  # Confluent with D-VAH (diff 0.8 = 8 pips)
}

confs = test_confluence(levels_test, threshold_pips=10.0, pip_size=0.1)
print(f"Test 3.1 (Confluence Count): {len(confs)} detected.")
for c in confs:
    print(f"  * {c[0]} & {c[1]} @ {c[2]:.2f} (Spread: {c[3]:.1f} pips)")

assert len(confs) == 2
assert ('D-POC', 'W-POC') in [(c[0], c[1]) for c in confs]
assert ('D-VAH', 'M-POC') in [(c[0], c[1]) for c in confs]
print("Test 3.2 (Confluence Pairs Validation): PASSED!")

print("\n==================================================")
print("ALL MATHEMATICAL AND LOGICAL UNIT TESTS PASSED 100%!")
print("==================================================")
