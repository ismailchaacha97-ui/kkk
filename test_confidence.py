def calculate_confidence(htf_trend, d1_trend, ema_aligned, adx_val, rsi_val, near_pivot, candle_size_ratio):
    score = 40  # base starting score for a valid triggered setup
    
    # HTF Alignment (up to +25%)
    if htf_trend == 1:
        score += 15
    if d1_trend == 1:
        score += 10
        
    # EMA Ribbon Alignment (20 > 50 > 200) (+10%)
    if ema_aligned:
        score += 10
        
    # ADX Trend Strength (+15%)
    if adx_val >= 35:
        score += 15
    elif adx_val >= 25:
        score += 10
    elif adx_val >= 22:
        score += 5
        
    # RSI Momentum (+10%)
    if (rsi_val >= 52 and rsi_val <= 68):
        score += 10
        
    # Floor Pivot bounce (+10%)
    if near_pivot:
        score += 10
        
    return min(98, score)

print("Test sample high confidence:", calculate_confidence(1, 1, True, 36.5, 58.0, True, 1.5))
print("Test sample medium confidence:", calculate_confidence(1, 0, True, 24.0, 51.0, False, 1.0))
