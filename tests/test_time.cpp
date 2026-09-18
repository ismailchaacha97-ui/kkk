//+------------------------------------------------------------------+
//| test_time.cpp - calendar arithmetic                              |
//|                                                                  |
//|  Anchoring is a *calendar* problem: get the day boundary wrong by  |
//|  one bar and every VWAP after a weekend is measured from the wrong |
//|  open.  These tests pin the conversions against values that can be  |
//|  verified by hand, and prove the round trip over two centuries of   |
//|  dates including every leap year rule.                              |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_CPP_TEST
#define VWAPPRO_CPP_TEST
#endif
#include "VpCompat.mqh"
#include "VpTime.mqh"
#include "vp_test.h"

int main()
{
   std::printf("VWAP Pro - calendar tests\n");

   vp_suite("days_from_civil: epoch and known dates");
   CHECK_EQ_I(vp_days_from_civil(1970, 1, 1), 0);
   CHECK_EQ_I(vp_days_from_civil(1970, 1, 2), 1);
   CHECK_EQ_I(vp_days_from_civil(1969, 12, 31), -1);
   CHECK_EQ_I(vp_days_from_civil(2000, 1, 1), 10957);
   CHECK_EQ_I(vp_days_from_civil(2000, 2, 29), 11016);   // leap day
   CHECK_EQ_I(vp_days_from_civil(2024, 2, 29), 19782);
   CHECK_EQ_I(vp_days_from_civil(1900, 3, 1), -25508);   // 1900 NOT a leap year
   CHECK_EQ_I(vp_days_from_civil(2100, 3, 1), 47541);    // 2100 NOT a leap year
   CHECK_EQ_I(vp_days_from_civil(1600, 3, 1), -135080);  // 1600 IS a leap year

   vp_suite("civil_from_days rounds trip for 200 years");
   int bad = 0;
   for (vp_int64 d = -25567; d < 47482; d++)      // 1900-01-01 .. 2099-12-31
   {
      int y, m, dd;
      vp_civil_from_days(d, y, m, dd);
      vp_int64 back = vp_days_from_civil(y, m, dd);
      if (back != d) { bad++; if (bad < 4) std::printf("    mismatch at %lld -> %d-%d-%d -> %lld\n", (long long)d, y, m, dd, (long long)back); }
      // sanity of the produced calendar date
      if (m < 1 || m > 12 || dd < 1 || dd > 31) bad++;
   }
   CHECK_MSG(bad == 0, "all 73k dates round trip");

   vp_suite("weekday");
   // 2026-09-18 is a Friday (wday = 5 when Sunday = 0).
   {
      int y, m, d;
      vp_civil_from_days(vp_days_from_civil(2026, 9, 18), y, m, d);
      CHECK_EQ_I(y, 2026); CHECK_EQ_I(m, 9); CHECK_EQ_I(d, 18);
      CHECK_EQ_I(vp_wday_of_day(vp_days_from_civil(2026, 9, 18)), 5);
      CHECK_EQ_I(vp_wday_of_day(vp_days_from_civil(2026, 9, 21)), 1);  // Monday
      CHECK_EQ_I(vp_wday_of_day(vp_days_from_civil(1970, 1, 1)), 4);   // Thursday
      CHECK_EQ_I(vp_wday_of_day(vp_days_from_civil(2000, 1, 1)), 6);   // Saturday
   }

   vp_suite("break_time");
   {
      // 2026-09-18 13:45:59 UTC == 1787233559
      vp_int64 secs = vp_days_from_civil(2026, 9, 18) * 86400LL + 13 * 3600 + 45 * 60 + 59;
      VpDateTime dt;
      vp_break_time(secs, dt);
      CHECK_EQ_I(dt.year, 2026);
      CHECK_EQ_I(dt.month, 9);
      CHECK_EQ_I(dt.day, 18);
      CHECK_EQ_I(dt.hour, 13);
      CHECK_EQ_I(dt.minute, 45);
      CHECK_EQ_I(dt.second, 59);
      CHECK_EQ_I(dt.wday, 5);
      CHECK_EQ_I(dt.yday, 260);       // Sep 18 of a non leap year
      CHECK_EQ_I(dt.secondOfDay, 13 * 3600 + 45 * 60 + 59);

      // Negative epoch (pre 1970) must stay well formed - brokers with
      // bad history generate these and naive /86400 truncation breaks.
      VpDateTime dtn;
      vp_break_time(-1, dtn);
      CHECK_EQ_I(dtn.year, 1969);
      CHECK_EQ_I(dtn.month, 12);
      CHECK_EQ_I(dtn.day, 31);
      CHECK_EQ_I(dtn.hour, 23);
      CHECK_EQ_I(dtn.minute, 59);
      CHECK_EQ_I(dtn.second, 59);
   }

   vp_suite("floor div / mod");
   CHECK_EQ_I((long long)vp_floor_div(7, 3), 2);
   CHECK_EQ_I((long long)vp_floor_div(-7, 3), -3);
   CHECK_EQ_I((long long)vp_floor_div(-1, 86400), -1);
   CHECK_EQ_I((long long)vp_floor_mod(-1, 86400), 86399);
   CHECK_EQ_I((long long)vp_floor_mod(86400 * 3 + 5, 86400), 5);
   CHECK_EQ_I((long long)vp_floor_mod(-7, 3), 2);

   vp_suite("week start");
   {
      vp_int64 fri = vp_days_from_civil(2026, 9, 18);
      CHECK_EQ_I((long long)vp_week_start_day(fri, 1), (long long)vp_days_from_civil(2026, 9, 14)); // Monday
      CHECK_EQ_I((long long)vp_week_start_day(fri, 0), (long long)vp_days_from_civil(2026, 9, 13)); // Sunday
      // Monday itself is stable
      CHECK_EQ_I((long long)vp_week_start_day(vp_days_from_civil(2026, 9, 14), 1),
                 (long long)vp_days_from_civil(2026, 9, 14));
      // And the key never steps backwards for a monotone time series.
      vp_int64 prev = -1; int errors = 0;
      for (vp_int64 d = 18000; d < 20000; d++)
      {
         vp_int64 k = vp_week_start_day(d, 1);
         if (k > d) errors++;
         if (k < prev - 7) errors++;
         prev = k;
      }
      CHECK_MSG(errors == 0, "week keys are monotone and never in the future");
   }

   vp_suite("make_time");
   {
      vp_int64 d = vp_days_from_civil(2026, 9, 18);
      vp_int64 t = vp_make_time(d, 9, 30);
      VpDateTime dt; vp_break_time(t, dt);
      CHECK_EQ_I(dt.hour, 9); CHECK_EQ_I(dt.minute, 30); CHECK_EQ_I(dt.day, 18);
      CHECK_EQ_I(dt.second, 0);
   }

   return vp_report("test_time");
}
