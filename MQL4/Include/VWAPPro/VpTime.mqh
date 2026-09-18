//+------------------------------------------------------------------+
//|                                                       VpTime.mqh |
//|          VWAP Pro - calendar arithmetic (portable MQL4 / C++)    |
//|                                                                  |
//|  MetaTrader hands us server time as a 64-bit count of seconds    |
//|  since 1970-01-01 (already shifted by the broker's GMT offset).  |
//|  To anchor VWAP we need exact civil dates back out of it.        |
//|                                                                  |
//|  The algorithms below are the well known "days from civil"       |
//|  proleptic Gregorian conversions (Howard Hinnant, public          |
//|  domain).  They are exact for every date we will ever see, are    |
//|  free of library dependencies, and - unlike MQL4's TimeToStruct() |
//|  - they are pure integer maths, which makes them unit-testable    |
//|  against an independent reference implementation.                 |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_TIME_MQH
#define VWAPPRO_TIME_MQH

#include "VpCompat.mqh"

#define VP_SECS_PER_DAY  86400
#define VP_SECS_PER_HOUR 3600
#define VP_SECS_PER_MIN  60

//+------------------------------------------------------------------+
//| Days since 1970-01-01 for a proleptic Gregorian date.            |
//+------------------------------------------------------------------+
vp_int64 vp_days_from_civil(int y, int m, int d)
{
   int yy = y - (m <= 2 ? 1 : 0);
   vp_int64 era = vp_floor_div((vp_int64)yy, 400);
   int yoe = (int)((vp_int64)yy - era * 400);                      // [0,399]
   int mp  = (m > 2) ? (m - 3) : (m + 9);                          // [0,11]
   int doy = (153 * mp + 2) / 5 + d - 1;                           // [0,365]
   int doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;                // [0,146096]
   return era * 146097 + (vp_int64)doe - 719468;
}

//+------------------------------------------------------------------+
//| Inverse of the above.                                            |
//+------------------------------------------------------------------+
void vp_civil_from_days(vp_int64 z, int &y, int &m, int &d)
{
   z += 719468;
   vp_int64 era = vp_floor_div(z, 146097);
   int doe = (int)(z - era * 146097);                              // [0,146096]
   int yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;// [0,399]
   int yy  = yoe + (int)(era * 400);
   int doy = doe - (365 * yoe + yoe / 4 - yoe / 100);              // [0,365]
   int mp  = (5 * doy + 2) / 153;                                  // [0,11]
   int dd  = doy - (153 * mp + 2) / 5 + 1;                         // [1,31]
   int mm  = mp + (mp < 10 ? 3 : -9);                              // [1,12]
   yy += (mm <= 2) ? 1 : 0;
   y = yy; m = mm; d = dd;
}

//+------------------------------------------------------------------+
//| Broken down calendar time for one instant.                       |
//|                                                                  |
//|  dayIndex    days since 1970-01-01 (the date only)               |
//|  secondOfDay seconds elapsed since local midnight                |
//|  wday        0 = Sunday ... 6 = Saturday                         |
//|  yday        0 = January 1st                                     |
//+------------------------------------------------------------------+
struct VpDateTime
{
   int       year;
   int       month;
   int       day;
   int       hour;
   int       minute;
   int       second;
   int       wday;
   int       yday;
   vp_int64  dayIndex;
   int       secondOfDay;
};

void vp_break_time(vp_int64 t, VpDateTime &dt)
{
   dt.dayIndex    = vp_floor_div(t, VP_SECS_PER_DAY);
   dt.secondOfDay = (int)vp_floor_mod(t, VP_SECS_PER_DAY);
   dt.hour        = dt.secondOfDay / VP_SECS_PER_HOUR;
   dt.minute      = (dt.secondOfDay % VP_SECS_PER_HOUR) / VP_SECS_PER_MIN;
   dt.second      = dt.secondOfDay % VP_SECS_PER_MIN;
   vp_civil_from_days(dt.dayIndex, dt.year, dt.month, dt.day);
   dt.yday = (int)(dt.dayIndex - vp_days_from_civil(dt.year, 1, 1));
   // 1970-01-01 was a Thursday -> Sunday = 0.
   dt.wday = (int)vp_floor_mod(dt.dayIndex + 4, 7);
}

//+------------------------------------------------------------------+
//| Weekday of a day index (0 = Sunday).                             |
//+------------------------------------------------------------------+
int vp_wday_of_day(vp_int64 dayIndex)
{
   return (int)vp_floor_mod(dayIndex + 4, 7);
}

//+------------------------------------------------------------------+
//| Compose an instant from a day index, hour and minute.            |
//+------------------------------------------------------------------+
vp_int64 vp_make_time(vp_int64 dayIndex, int hour, int minute)
{
   return dayIndex * VP_SECS_PER_DAY + (vp_int64)hour * VP_SECS_PER_HOUR
          + (vp_int64)minute * VP_SECS_PER_MIN;
}

//+------------------------------------------------------------------+
//| Start of the ISO-ish week (weekStartDay: 0=Sun .. 6=Sat).        |
//+------------------------------------------------------------------+
vp_int64 vp_week_start_day(vp_int64 dayIndex, int weekStartDay)
{
   // weekStartDay uses the same convention as VpDateTime::wday (0 = Sunday),
   // and wday = (dayIndex + 4) % 7 because 1970-01-01 was a Thursday.
   // (The +4 is the single most commonly forgotten term in hand written
   //  "start of week" code - see the week-key tests.)
   int delta = (int)vp_floor_mod(dayIndex + 4 - (vp_int64)weekStartDay, 7);
   return dayIndex - (vp_int64)delta;
}

//+------------------------------------------------------------------+
//| Timezone reference.                                              |
//|                                                                  |
//|  MT4 gives us *server* time - a UTC instant already shifted by the |
//|  broker's offset.  MQL4 exposes no reliable way to read that        |
//|  offset (TimeGMTOffset() is an MQL5 API), so it is an explicit      |
//|  parameter instead of a guess.  This is deliberate: a wrong silent  |
//|  guess is exactly how "10:30 New York" anchors end up an hour away  |
//|  from the open half the year.                                       |
//|                                                                  |
//|  serverLondonOffset = the broker's GMT offset (+2 for GMT+2 ...).   |
//|  UTC-anchored modes use it to place bars on the true UTC calendar.  |
//+------------------------------------------------------------------+
double vp_tz_offset_hours = 0.0;      // server time - UTC, in hours

//+------------------------------------------------------------------+
//| Convert a UTC instant to server time using the configured offset. |
//| Used by the "UTC anchor" mode.                                    |
//+------------------------------------------------------------------+
vp_int64 vp_utc_to_server(vp_int64 utcSeconds)
{
   return utcSeconds + (vp_int64)vp_round(vp_tz_offset_hours * 3600.0);
}

#endif // VWAPPRO_TIME_MQH
//+------------------------------------------------------------------+
