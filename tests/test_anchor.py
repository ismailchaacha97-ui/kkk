import sys
sys.path.insert(0, 'src')
from vwap_ssl_engine import anchor_key_for_bar, AnchorPeriod, INVALID_ANCHOR
from datetime import datetime

def test_daily_anchor():
    dt = datetime(2024, 3, 15, 10, 30)
    key = anchor_key_for_bar(dt, AnchorPeriod.DAILY)
    # same day different times should give same key
    dt2 = datetime(2024, 3, 15, 22, 15)
    key2 = anchor_key_for_bar(dt2, AnchorPeriod.DAILY)
    assert key == key2, "Daily anchor should be same for same day"
    dt3 = datetime(2024, 3, 16, 1, 0)
    key3 = anchor_key_for_bar(dt3, AnchorPeriod.DAILY)
    assert key != key3, "Different days should have different daily keys"

def test_weekly_anchor():
    # Monday to Sunday same week
    mon = datetime(2024, 3, 11, 10, 0)  # Monday
    wed = datetime(2024, 3, 13, 15, 0)
    sun = datetime(2024, 3, 17, 23, 0)
    next_mon = datetime(2024, 3, 18, 1, 0)
    k_mon = anchor_key_for_bar(mon, AnchorPeriod.WEEKLY)
    k_wed = anchor_key_for_bar(wed, AnchorPeriod.WEEKLY)
    k_sun = anchor_key_for_bar(sun, AnchorPeriod.WEEKLY)
    k_next = anchor_key_for_bar(next_mon, AnchorPeriod.WEEKLY)
    assert k_mon == k_wed == k_sun, "Same week should have same weekly anchor"
    assert k_mon != k_next, "Next week should have different anchor"

def test_monthly_anchor():
    jan15 = datetime(2024, 1, 15)
    jan30 = datetime(2024, 1, 30)
    feb1 = datetime(2024, 2, 1)
    k1 = anchor_key_for_bar(jan15, AnchorPeriod.MONTHLY)
    k2 = anchor_key_for_bar(jan30, AnchorPeriod.MONTHLY)
    k3 = anchor_key_for_bar(feb1, AnchorPeriod.MONTHLY)
    assert k1 == k2
    assert k1 != k3

def test_session_anchor():
    # London 8:00
    # bar at 7:59 should belong to previous day's session
    # bar at 8:01 should belong to current day's session
    before = datetime(2024, 3, 15, 7, 59)
    after = datetime(2024, 3, 15, 8, 1)
    k_before = anchor_key_for_bar(before, AnchorPeriod.LONDON, london_h=8, london_m=0)
    k_after = anchor_key_for_bar(after, AnchorPeriod.LONDON, london_h=8, london_m=0)
    assert k_before != k_after, "Session anchor should roll at session start"

    # same session next day
    next_day = datetime(2024, 3, 16, 8, 1)
    k_next = anchor_key_for_bar(next_day, AnchorPeriod.LONDON, london_h=8, london_m=0)
    assert k_after != k_next

def test_custom_time_anchor():
    custom = datetime(2024, 1, 10, 0, 0)
    before = datetime(2024, 1, 9, 23, 59)
    after = datetime(2024, 1, 11, 0, 0)
    k_before = anchor_key_for_bar(before, AnchorPeriod.CUSTOM_TIME, custom_anchor_time=custom)
    k_after = anchor_key_for_bar(after, AnchorPeriod.CUSTOM_TIME, custom_anchor_time=custom)
    assert k_before == INVALID_ANCHOR
    assert k_after != INVALID_ANCHOR

def test_custom_session_roll():
    # custom 0:00
    dt1 = datetime(2024, 3, 15, 0, 1)
    dt2 = datetime(2024, 3, 15, 23, 59)
    k1 = anchor_key_for_bar(dt1, AnchorPeriod.CUSTOM_SESSION, custom_h=0, custom_m=0)
    k2 = anchor_key_for_bar(dt2, AnchorPeriod.CUSTOM_SESSION, custom_h=0, custom_m=0)
    assert k1 == k2, "Same custom session day should match"

if __name__ == "__main__":
    test_daily_anchor()
    test_weekly_anchor()
    test_monthly_anchor()
    test_session_anchor()
    test_custom_time_anchor()
    test_custom_session_roll()
    print("All anchor tests passed")
