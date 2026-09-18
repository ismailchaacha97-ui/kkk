//+------------------------------------------------------------------+
//|                                                     VpAnchor.mqh |
//|          VWAP Pro - anchor calendar                               |
//|                                                                  |
//|  Deciding *what* to anchor to is where most VWAP indicators are    |
//|  quietly wrong:                                                     |
//|                                                                  |
//|   * "daily" resets at the terminal's midnight, which on a broker    |
//|     with a GMT+3 server means the anchor rolls at 21:00 UTC -       |
//|     nowhere near any institutional reference point;                  |
//|   * "session" is meaningless on M1 where every bar is its own        |
//|     session;                                                          |
//|   * none of them survive the DST switch, so a "09:30 New York"       |
//|     VWAP silently becomes 08:30 for half the year.                    |
//|                                                                  |
//|  The calendar below is explicit about the reference frame:           |
//|  every mode is defined in *server time* (what the chart shows) or    |
//|  in *UTC* (converted through the live GMT offset), and the offset     |
//|  can be pinned by the user so a VWAP anchored to the London open      |
//|  keeps anchoring to the London open across the DST boundary.          |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_ANCHOR_MQH
#define VWAPPRO_ANCHOR_MQH

#include "VpCompat.mqh"
#include "VpTime.mqh"
#include "VpEngine.mqh"

//+------------------------------------------------------------------+
//| Compute the anchor key for one bar time.                         |
//|                                                                  |
//|  The key changes exactly when a new anchor period begins, so the   |
//|  engine can use a plain inequality test.                           |
//+------------------------------------------------------------------+
vp_int64 vp_anchor_key(VpEngineConfig &cfg, vp_int64 serverTime)
{
   vp_int64 t = serverTime + (vp_int64)cfg.anchorShiftSec;

   switch (cfg.anchorMode)
   {
      case VP_ANCHOR_SESSION:
      {
         // One anchor per bar: the pure "session VWAP".  The engine then
         // reproduces the textbook estimator bar by bar.
         return t;
      }
      case VP_ANCHOR_SERVERDAY:
      {
         return vp_floor_div(t, VP_SECS_PER_DAY);
      }
      case VP_ANCHOR_UTCDAY:
      {
         vp_int64 utc = t - (vp_int64)vp_round(vp_tz_offset_hours * 3600.0);
         return vp_floor_div(utc, VP_SECS_PER_DAY);
      }
      case VP_ANCHOR_WEEK:
      {
         vp_int64 dayIdx = vp_floor_div(t, VP_SECS_PER_DAY);
         vp_int64 wkStart = vp_week_start_day(dayIdx, cfg.weekStartDay);
         return wkStart;
      }
      case VP_ANCHOR_FIXED:
      default:
      {
         vp_int64 dayIdx = vp_floor_div(t, VP_SECS_PER_DAY);
         int secOfDay = (int)vp_floor_mod(t, VP_SECS_PER_DAY);
         int anchorSec = cfg.anchorHour * VP_SECS_PER_HOUR + cfg.anchorMinute * VP_SECS_PER_MIN;
         if (secOfDay >= anchorSec) return dayIdx * VP_SECS_PER_DAY + anchorSec;
         return (dayIdx - 1) * VP_SECS_PER_DAY + anchorSec;
      }
   }
}

#endif // VWAPPRO_ANCHOR_MQH
//+------------------------------------------------------------------+
