//+------------------------------------------------------------------+
//|                                               SessionsOnly.mq4   |
//|                        Trading Sessions Indicator for MetaTrader 4 |
//|                                                                  |
//|  Draws the Sydney / Tokyo / London / New York trading sessions    |
//|  as range boxes on the chart. Nothing else - sessions only.       |
//|                                                                  |
//|  Features                                                         |
//|    - 4 fully configurable sessions (times, colours, on/off)       |
//|    - Session times can be entered in GMT or in broker/server time |
//|    - Automatic broker GMT offset detection + DST rules            |
//|      (EU / US / AU) so GMT based times stay correct all year      |
//|    - High/Low range box per session, per day                      |
//|    - Session name + range size (pips) labels                      |
//|    - Optional open/close vertical lines                           |
//|    - Optional live info panel with countdown to open/close        |
//|    - Optional alerts on session open and close                    |
//+------------------------------------------------------------------+
#property copyright "Sessions Only"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_TIME_BASE
  {
   TIMEBASE_GMT      = 0,  // Session times are GMT / UTC
   TIMEBASE_SERVER   = 1   // Session times are broker (server) time
  };

enum ENUM_OFFSET_MODE
  {
   OFFSET_AUTO       = 0,  // Auto detect broker GMT offset
   OFFSET_MANUAL     = 1   // Use the manual offset below
  };

enum ENUM_DST_RULE
  {
   DST_NONE          = 0,  // No DST (times fixed all year)
   DST_EU            = 1,  // Europe (last Sun Mar -> last Sun Oct)
   DST_US            = 2,  // United States (2nd Sun Mar -> 1st Sun Nov)
   DST_AU            = 3   // Australia (1st Sun Oct -> 1st Sun Apr)
  };

enum ENUM_LABEL_POS
  {
   LABELPOS_TOP      = 0,  // Above the box
   LABELPOS_INSIDE   = 1,  // Inside the box (top left)
   LABELPOS_BOTTOM   = 2   // Below the box
  };

enum ENUM_PANEL_CORNER
  {
   PANEL_TOP_LEFT     = 0, // Top left
   PANEL_TOP_RIGHT    = 1, // Top right
   PANEL_BOTTOM_LEFT  = 2, // Bottom left
   PANEL_BOTTOM_RIGHT = 3  // Bottom right
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string           __gen__            = "======= General =======";      // ---
input int              InpDaysToShow      = 10;                             // Days of history to draw
input ENUM_TIME_BASE   InpTimeBase        = TIMEBASE_GMT;                    // Session times are given in
input ENUM_OFFSET_MODE InpOffsetMode      = OFFSET_AUTO;                     // Broker GMT offset mode
input double           InpManualOffset    = 3.0;                             // Manual broker GMT offset (hours)
input bool             InpSkipSaturday    = true;                            // Skip Saturday sessions
input bool             InpSkipSunday      = false;                           // Skip Sunday sessions
input ENUM_TIMEFRAMES  InpMaxTimeframe    = PERIOD_H4;                       // Draw only on TF <= this

input string           __box__            = "======= Boxes =======";        // ---
input bool             InpShowBoxes       = true;                            // Show session range boxes
input bool             InpFillBoxes       = true;                            // Fill boxes with colour
input bool             InpShowBorder      = true;                            // Draw box border
input ENUM_LINE_STYLE  InpBorderStyle     = STYLE_SOLID;                     // Border style
input int              InpBorderWidth     = 1;                               // Border width
input bool             InpBoxInBackground = true;                            // Boxes behind price

input string           __lbl__            = "======= Labels =======";       // ---
input bool             InpShowLabels      = true;                            // Show session name labels
input ENUM_LABEL_POS   InpLabelPos        = LABELPOS_TOP;                    // Label position
input bool             InpShowRangePips   = true;                            // Add range size (pips) to label
input string           InpLabelFont       = "Arial";                         // Label font
input int              InpLabelSize       = 8;                               // Label font size

input string           __lin__            = "======= Open / Close lines ======="; // ---
input bool             InpShowOpenLine    = false;                           // Vertical line at session open
input bool             InpShowCloseLine   = false;                           // Vertical line at session close
input ENUM_LINE_STYLE  InpVLineStyle      = STYLE_DOT;                       // Vertical line style
input int              InpVLineWidth      = 1;                               // Vertical line width

input string           __pnl__            = "======= Info panel =======";   // ---
input bool             InpShowPanel       = true;                            // Show info panel
input ENUM_PANEL_CORNER InpPanelCorner    = PANEL_TOP_RIGHT;                 // Panel corner
input int              InpPanelX          = 12;                              // Panel X distance
input int              InpPanelY          = 18;                              // Panel Y distance
input color            InpPanelTextColor  = clrSilver;                       // Panel text colour
input int              InpPanelFontSize   = 8;                               // Panel font size

input string           __alr__            = "======= Alerts =======";       // ---
input bool             InpAlertOnOpen     = false;                           // Alert on session open
input bool             InpAlertOnClose    = false;                           // Alert on session close
input bool             InpAlertPopup      = true;                            // Alert: popup
input bool             InpAlertPush       = false;                           // Alert: push notification

input string           __s1__             = "======= Session 1 =======";    // ---
input bool             InpS1Enabled       = true;                            // Sydney: enabled
input string           InpS1Name          = "Sydney";                        // Sydney: name
input string           InpS1Start         = "21:00";                         // Sydney: start (HH:MM)
input string           InpS1End           = "06:00";                         // Sydney: end (HH:MM)
input color            InpS1Color         = C'32,48,64';                     // Sydney: colour
input ENUM_DST_RULE    InpS1Dst           = DST_AU;                          // Sydney: DST rule

input string           __s2__             = "======= Session 2 =======";    // ---
input bool             InpS2Enabled       = true;                            // Tokyo: enabled
input string           InpS2Name          = "Tokyo";                         // Tokyo: name
input string           InpS2Start         = "00:00";                         // Tokyo: start (HH:MM)
input string           InpS2End           = "09:00";                         // Tokyo: end (HH:MM)
input color            InpS2Color         = C'64,32,64';                     // Tokyo: colour
input ENUM_DST_RULE    InpS2Dst           = DST_NONE;                        // Tokyo: DST rule

input string           __s3__             = "======= Session 3 =======";    // ---
input bool             InpS3Enabled       = true;                            // London: enabled
input string           InpS3Name          = "London";                        // London: name
input string           InpS3Start         = "08:00";                         // London: start (HH:MM)
input string           InpS3End           = "17:00";                         // London: end (HH:MM)
input color            InpS3Color         = C'26,64,48';                     // London: colour
input ENUM_DST_RULE    InpS3Dst           = DST_EU;                          // London: DST rule

input string           __s4__             = "======= Session 4 =======";    // ---
input bool             InpS4Enabled       = true;                            // New York: enabled
input string           InpS4Name          = "New York";                      // New York: name
input string           InpS4Start         = "13:00";                         // New York: start (HH:MM)
input string           InpS4End           = "22:00";                         // New York: end (HH:MM)
input color            InpS4Color         = C'72,40,32';                     // New York: colour
input ENUM_DST_RULE    InpS4Dst           = DST_US;                          // New York: DST rule

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
#define SESSION_COUNT 4
#define PREFIX        "SessOnly_"

struct SessionDef
  {
   bool          enabled;
   string        name;
   int           startMin;      // minutes from midnight
   int           endMin;        // minutes from midnight
   color         clr;
   ENUM_DST_RULE dst;
  };

SessionDef  g_sess[SESSION_COUNT];
double      g_pip           = 0.0;
int         g_pipDigits     = 1;
double      g_brokerOffset  = 0.0;   // hours, broker time = GMT + offset
datetime    g_lastBar       = 0;
bool        g_active        = false; // false -> unsupported timeframe
datetime    g_alertOpen[SESSION_COUNT];
datetime    g_alertClose[SESSION_COUNT];

//+------------------------------------------------------------------+
//| Helpers: time parsing                                            |
//+------------------------------------------------------------------+
int ParseHHMM(const string txt, const int fallback)
  {
   string s = txt;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) == 0)
      return(fallback);

   int sep = StringFind(s, ":");
   int hh, mm;
   if(sep < 0)
     {
      hh = (int)StringToInteger(s);
      mm = 0;
     }
   else
     {
      hh = (int)StringToInteger(StringSubstr(s, 0, sep));
      mm = (int)StringToInteger(StringSubstr(s, sep + 1));
     }

   if(hh < 0 || hh > 24 || mm < 0 || mm > 59)
     {
      Print("SessionsOnly: bad time string '", txt, "', using default.");
      return(fallback);
     }
   return(hh * 60 + mm);
  }

string MinutesToText(const int minutes)
  {
   int m = ((minutes % 1440) + 1440) % 1440;
   return(StringFormat("%02d:%02d", m / 60, m % 60));
  }

string DurationToText(const int seconds)
  {
   int s = seconds;
   if(s < 0)
      s = 0;
   int h = s / 3600;
   int m = (s % 3600) / 60;
   int ss = s % 60;
   if(h > 0)
      return(StringFormat("%02d:%02d:%02d", h, m, ss));
   return(StringFormat("%02d:%02d", m, ss));
  }

//+------------------------------------------------------------------+
//| Helpers: DST                                                     |
//+------------------------------------------------------------------+
datetime MakeDate(const int year, const int month, const int day, const int hour)
  {
   return(StringToTime(StringFormat("%04d.%02d.%02d %02d:00", year, month, day, hour)));
  }

int DaysInMonth(const int year, const int month)
  {
   int d[] = {31,28,31,30,31,30,31,31,30,31,30,31};
   int n = d[month - 1];
   if(month == 2)
     {
      bool leap = ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0));
      if(leap)
         n = 29;
     }
   return(n);
  }

int DowOf(const datetime t)
  {
   MqlDateTime st;
   TimeToStruct(t, st);
   return(st.day_of_week);
  }

//--- nth (1-based) Sunday of a month, at the given hour
datetime NthSunday(const int year, const int month, const int nth, const int hour)
  {
   datetime first = MakeDate(year, month, 1, 0);
   int dow  = DowOf(first);              // 0 = Sunday
   int day  = 1 + ((7 - dow) % 7) + (nth - 1) * 7;
   int last = DaysInMonth(year, month);
   if(day > last)
      day -= 7;
   return(MakeDate(year, month, day, hour));
  }

//--- last Sunday of a month, at the given hour
datetime LastSunday(const int year, const int month, const int hour)
  {
   int day = DaysInMonth(year, month);
   datetime t = MakeDate(year, month, day, hour);
   while(DowOf(t) != 0)
     {
      day--;
      t = MakeDate(year, month, day, hour);
     }
   return(t);
  }

//--- returns extra hours (0 or 1) that apply to a GMT timestamp
int DstShiftHours(const datetime gmtTime, const ENUM_DST_RULE rule)
  {
   if(rule == DST_NONE)
      return(0);

   MqlDateTime st;
   TimeToStruct(gmtTime, st);
   int y = st.year;

   if(rule == DST_EU)
     {
      datetime on  = LastSunday(y, 3, 1);    // 01:00 UTC
      datetime off = LastSunday(y, 10, 1);   // 01:00 UTC
      return((gmtTime >= on && gmtTime < off) ? 1 : 0);
     }

   if(rule == DST_US)
     {
      datetime on  = NthSunday(y, 3, 2, 7);  // 02:00 local = 07:00 UTC
      datetime off = NthSunday(y, 11, 1, 6); // 02:00 local = 06:00 UTC
      return((gmtTime >= on && gmtTime < off) ? 1 : 0);
     }

   if(rule == DST_AU)                                     // southern hemisphere
     {
      //--- 1st Sun Oct 02:00 AEST  = 16:00 UTC on the Saturday before
      //--- 1st Sun Apr 03:00 AEDT  = 16:00 UTC on the Saturday before
      datetime on  = (datetime)(NthSunday(y, 10, 1, 16) - 86400);
      datetime off = (datetime)(NthSunday(y,  4, 1, 16) - 86400);
      return((gmtTime >= on || gmtTime < off) ? 1 : 0);
     }

   return(0);
  }

//+------------------------------------------------------------------+
//| Broker GMT offset                                                |
//+------------------------------------------------------------------+
double DetectBrokerOffset()
  {
   if(InpOffsetMode == OFFSET_MANUAL)
      return(InpManualOffset);

   datetime srv = TimeCurrent();
   datetime gmt = TimeGMT();
   if(srv <= 0 || gmt <= 0)
      return(InpManualOffset);

   double diff = (double)(srv - gmt) / 3600.0;
   double off  = MathRound(diff * 2.0) / 2.0;   // snap to half hours
   if(off < -13.0 || off > 14.0)
     {
      Print("SessionsOnly: implausible auto GMT offset (", DoubleToString(off, 1),
            "), falling back to manual value.");
      return(InpManualOffset);
     }
   return(off);
  }

datetime ServerToGmt(const datetime srv)
  {
   return((datetime)(srv - (int)MathRound(g_brokerOffset * 3600.0)));
  }

//+------------------------------------------------------------------+
//| Colour helpers                                                   |
//+------------------------------------------------------------------+
//--- box colours are deliberately dark so price stays readable; text
//--- drawn in that same colour would be invisible, so brighten it.
color Brighten(const color clr, const double factor)
  {
   int r = (int)(clr & 0xFF);
   int g = (int)((clr >> 8) & 0xFF);
   int b = (int)((clr >> 16) & 0xFF);

   r = (int)MathRound(r * factor);
   g = (int)MathRound(g * factor);
   b = (int)MathRound(b * factor);

   //--- keep some minimum luminance so very dark inputs stay visible
   if(r < 90 && g < 90 && b < 90)
     {
      r += 90;
      g += 90;
      b += 90;
     }

   if(r > 255) r = 255;
   if(g > 255) g = 255;
   if(b > 255) b = 255;

   return((color)(r | (g << 8) | (b << 16)));
  }

//+------------------------------------------------------------------+
//| Object helpers                                                   |
//+------------------------------------------------------------------+
void DeleteOwnObjects()
  {
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, PREFIX) == 0)
         ObjectDelete(0, nm);
     }
  }

void DrawBox(const string name, const datetime t1, const double p1,
             const datetime t2, const double p2, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
         return;
     }
   ObjectSetInteger(0, name, OBJPROP_TIME1,  t1);
   ObjectSetDouble (0, name, OBJPROP_PRICE1, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME2,  t2);
   ObjectSetDouble (0, name, OBJPROP_PRICE2, p2);
   ObjectSetInteger(0, name, OBJPROP_COLOR,  clr);
   ObjectSetInteger(0, name, OBJPROP_FILL,   InpFillBoxes);
   ObjectSetInteger(0, name, OBJPROP_BACK,   InpBoxInBackground);
   ObjectSetInteger(0, name, OBJPROP_STYLE,  InpShowBorder ? InpBorderStyle : STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,  InpShowBorder ? InpBorderWidth : 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     0);
  }

void DrawText(const string name, const datetime t, const double price,
              const string text, const color clr, const int anchor)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
         return;
     }
   ObjectSetInteger(0, name, OBJPROP_TIME1,  t);
   ObjectSetDouble (0, name, OBJPROP_PRICE1, price);
   ObjectSetString (0, name, OBJPROP_TEXT,   text);
   ObjectSetString (0, name, OBJPROP_FONT,   InpLabelFont);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpLabelSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,  clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_BACK,   false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
  }

void DrawVLine(const string name, const datetime t, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_VLINE, 0, t, 0))
         return;
     }
   ObjectSetInteger(0, name, OBJPROP_TIME1, t);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, InpVLineStyle);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpVLineWidth);
   ObjectSetInteger(0, name, OBJPROP_BACK,  true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
  }

void DrawPanelLine(const string name, const int row, const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return;
     }
   int corner = CORNER_RIGHT_UPPER;
   switch(InpPanelCorner)
     {
      case PANEL_TOP_LEFT:     corner = CORNER_LEFT_UPPER;  break;
      case PANEL_TOP_RIGHT:    corner = CORNER_RIGHT_UPPER; break;
      case PANEL_BOTTOM_LEFT:  corner = CORNER_LEFT_LOWER;  break;
      case PANEL_BOTTOM_RIGHT: corner = CORNER_RIGHT_LOWER; break;
     }
   bool bottom = (InpPanelCorner == PANEL_BOTTOM_LEFT || InpPanelCorner == PANEL_BOTTOM_RIGHT);
   bool right  = (InpPanelCorner == PANEL_TOP_RIGHT   || InpPanelCorner == PANEL_BOTTOM_RIGHT);
   int  step   = InpPanelFontSize + 6;
   int  rowIdx = bottom ? (SESSION_COUNT + 1 - row) : row;

   ObjectSetInteger(0, name, OBJPROP_CORNER,    corner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + rowIdx * step);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  InpPanelFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
  }

//+------------------------------------------------------------------+
//| Session time computation                                         |
//+------------------------------------------------------------------+
//--- start of the server-time day, "shift" days back from the last bar
datetime DayStart(const int shift)
  {
   datetime ref = TimeCurrent();
   if(Bars > 0 && Time[0] > ref)
      ref = Time[0];
   datetime midnight = (datetime)(ref - (ref % 86400));
   return((datetime)(midnight - (datetime)shift * 86400));
  }

//--- server-time window of session s for the day starting at dayStart
void SessionWindow(const int s, const datetime dayStart, datetime &from, datetime &to)
  {
   int shiftSec = 0;
   if(InpTimeBase == TIMEBASE_GMT)
     {
      //--- Times are entered as the winter (standard time) GMT values.
      //--- While the market observes DST its local session happens one hour
      //--- EARLIER in GMT (London 08:00 BST = 07:00 GMT), hence the minus.
      datetime gmtRef = ServerToGmt((datetime)(dayStart + g_sess[s].startMin * 60));
      int dstHours    = DstShiftHours(gmtRef, g_sess[s].dst);
      shiftSec        = (int)MathRound(g_brokerOffset * 3600.0) - dstHours * 3600;
     }

   from = (datetime)(dayStart + g_sess[s].startMin * 60 + shiftSec);
   int span = g_sess[s].endMin - g_sess[s].startMin;
   if(span <= 0)
      span += 1440;                                   // session crosses midnight
   to = (datetime)(from + span * 60);
  }

//--- high / low of the bars inside [from, to)
bool SessionRange(const datetime from, const datetime to, double &hi, double &lo,
                  datetime &firstBar, datetime &lastBar)
  {
   hi = -DBL_MAX;
   lo =  DBL_MAX;
   firstBar = 0;
   lastBar  = 0;

   if(Bars <= 0)
      return(false);
   if(Time[Bars - 1] >= to)
      return(false);

   int startIdx = iBarShift(NULL, 0, (datetime)(to - 1), false);
   if(startIdx < 0)
      startIdx = 0;

   bool found = false;
   for(int b = startIdx; b < Bars; b++)
     {
      datetime bt = Time[b];
      if(bt >= to)
         continue;
      if(bt < from)
         break;
      if(High[b] > hi)
         hi = High[b];
      if(Low[b] < lo)
         lo = Low[b];
      if(!found)
         lastBar = bt;
      firstBar = bt;
      found = true;
     }
   return(found);
  }

//+------------------------------------------------------------------+
//| Drawing one session of one day                                   |
//+------------------------------------------------------------------+
void DrawSessionDay(const int s, const int dayShift)
  {
   datetime dayStart = DayStart(dayShift);
   datetime from, to;
   SessionWindow(s, dayStart, from, to);

   MqlDateTime st;
   TimeToStruct(from, st);
   if(InpSkipSaturday && st.day_of_week == 6)
      return;
   if(InpSkipSunday && st.day_of_week == 0)
      return;

   double hi, lo;
   datetime fb, lb;
   if(!SessionRange(from, to, hi, lo, fb, lb))
      return;

   string tag  = StringFormat("%s%d_%s", PREFIX, s, TimeToString(from, TIME_DATE | TIME_MINUTES));
   datetime t2 = to;
   datetime now = TimeCurrent();
   if(t2 > now && lb > 0)                 // session still running -> stop at last bar
      t2 = (datetime)MathMax((double)lb, (double)(fb + 1));

   if(InpShowBoxes)
      DrawBox(tag + "_box", from, hi, t2, lo, g_sess[s].clr);

   if(InpShowLabels)
     {
      string txt = g_sess[s].name;
      if(InpShowRangePips)
        {
         double pips = (hi - lo) / g_pip;
         txt = StringFormat("%s  %s", txt, DoubleToString(pips, g_pipDigits));
        }
      double price  = hi;
      int    anchor = ANCHOR_LEFT_LOWER;
      if(InpLabelPos == LABELPOS_INSIDE)
        {
         price  = hi;
         anchor = ANCHOR_LEFT_UPPER;
        }
      else
         if(InpLabelPos == LABELPOS_BOTTOM)
           {
            price  = lo;
            anchor = ANCHOR_LEFT_UPPER;
           }
      DrawText(tag + "_lbl", from, price, txt, Brighten(g_sess[s].clr, 2.6), anchor);
     }

   if(InpShowOpenLine)
      DrawVLine(tag + "_vo", from, g_sess[s].clr);
   if(InpShowCloseLine)
      DrawVLine(tag + "_vc", to, g_sess[s].clr);
  }

//+------------------------------------------------------------------+
//| Full redraw                                                      |
//+------------------------------------------------------------------+
void RedrawAll()
  {
   for(int s = 0; s < SESSION_COUNT; s++)
     {
      if(!g_sess[s].enabled)
         continue;
      //--- d = -1 covers a session pushed into "tomorrow" by the broker offset
      int days = (InpDaysToShow < 1) ? 1 : InpDaysToShow;
      for(int d = -1; d < days; d++)
         DrawSessionDay(s, d);
     }
  }

//--- only the sessions that can still be running (cheap per-tick update)
void UpdateLiveSessions()
  {
   datetime now = TimeCurrent();
   for(int s = 0; s < SESSION_COUNT; s++)
     {
      if(!g_sess[s].enabled)
         continue;
      for(int d = -1; d <= 2; d++)
        {
         datetime from, to;
         SessionWindow(s, DayStart(d), from, to);
         if(now >= from && now <= to)
            DrawSessionDay(s, d);
        }
     }
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   datetime now = TimeCurrent();
   datetime gmt = ServerToGmt(now);

   string head = StringFormat("SESSIONS   srv %s  gmt %s  (GMT%+.1f)",
                              TimeToString(now, TIME_MINUTES),
                              TimeToString(gmt, TIME_MINUTES),
                              g_brokerOffset);
   DrawPanelLine(PREFIX + "pnl_0", 0, head, InpPanelTextColor);

   for(int s = 0; s < SESSION_COUNT; s++)
     {
      string nm = PREFIX + "pnl_" + IntegerToString(s + 1);
      if(!g_sess[s].enabled)
        {
         ObjectDelete(0, nm);
         continue;
        }

      bool open = false;
      int  secs = 0;

      //--- look at yesterday / today / tomorrow to find the state
      for(int d = 2; d >= -1; d--)
        {
         datetime f, t;
         SessionWindow(s, DayStart(d), f, t);
         if(now >= f && now < t)
           {
            open = true;
            secs = (int)(t - now);
            break;
           }
        }

      if(!open)
        {
         datetime next = 0;
         for(int d = 2; d >= -2; d--)
           {
            datetime f, t;
            SessionWindow(s, DayStart(d), f, t);
            if(f > now && (next == 0 || f < next))
               next = f;
           }
         secs = (next > 0) ? (int)(next - now) : 0;
        }

      string line = StringFormat("%-9s %-6s %s  %s-%s",
                                 g_sess[s].name,
                                 open ? "OPEN" : "closed",
                                 DurationToText(secs),
                                 MinutesToText(g_sess[s].startMin),
                                 MinutesToText(g_sess[s].endMin));
      DrawPanelLine(nm, s + 1, line,
                    open ? Brighten(g_sess[s].clr, 2.9) : InpPanelTextColor);
     }
  }

//+------------------------------------------------------------------+
//| Alerts                                                           |
//+------------------------------------------------------------------+
void SendAlert(const string text)
  {
   if(InpAlertPopup)
      Alert(text);
   else
      Print(text);
   if(InpAlertPush)
      SendNotification(text);
  }

void CheckAlerts()
  {
   if(!InpAlertOnOpen && !InpAlertOnClose)
      return;
   if(IsTesting() || IsOptimization())
      return;

   datetime now = TimeCurrent();
   for(int s = 0; s < SESSION_COUNT; s++)
     {
      if(!g_sess[s].enabled)
         continue;
      for(int d = 2; d >= 0; d--)
        {
         datetime f, t;
         SessionWindow(s, DayStart(d), f, t);

         if(InpAlertOnOpen && g_alertOpen[s] != f && now >= f && now < f + 300)
           {
            g_alertOpen[s] = f;
            SendAlert(StringFormat("%s %s session OPEN (%s)", _Symbol, g_sess[s].name,
                                   TimeToString(f, TIME_MINUTES)));
           }
         if(InpAlertOnClose && g_alertClose[s] != t && now >= t && now < t + 300)
           {
            g_alertClose[s] = t;
            SendAlert(StringFormat("%s %s session CLOSED (%s)", _Symbol, g_sess[s].name,
                                   TimeToString(t, TIME_MINUTES)));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorShortName("SessionsOnly");

   g_sess[0].enabled = InpS1Enabled; g_sess[0].name = InpS1Name;
   g_sess[0].startMin = ParseHHMM(InpS1Start, 21 * 60);
   g_sess[0].endMin   = ParseHHMM(InpS1End,    6 * 60);
   g_sess[0].clr = InpS1Color; g_sess[0].dst = InpS1Dst;

   g_sess[1].enabled = InpS2Enabled; g_sess[1].name = InpS2Name;
   g_sess[1].startMin = ParseHHMM(InpS2Start, 0);
   g_sess[1].endMin   = ParseHHMM(InpS2End,   9 * 60);
   g_sess[1].clr = InpS2Color; g_sess[1].dst = InpS2Dst;

   g_sess[2].enabled = InpS3Enabled; g_sess[2].name = InpS3Name;
   g_sess[2].startMin = ParseHHMM(InpS3Start,  8 * 60);
   g_sess[2].endMin   = ParseHHMM(InpS3End,   17 * 60);
   g_sess[2].clr = InpS3Color; g_sess[2].dst = InpS3Dst;

   g_sess[3].enabled = InpS4Enabled; g_sess[3].name = InpS4Name;
   g_sess[3].startMin = ParseHHMM(InpS4Start, 13 * 60);
   g_sess[3].endMin   = ParseHHMM(InpS4End,   22 * 60);
   g_sess[3].clr = InpS4Color; g_sess[3].dst = InpS4Dst;

   g_pip = (Digits == 3 || Digits == 5) ? Point * 10.0 : Point;
   if(g_pip <= 0.0)
      g_pip = (Point > 0.0) ? Point : 1.0;
   g_pipDigits = (Digits == 3 || Digits == 5) ? 1 : 0;

   g_brokerOffset = DetectBrokerOffset();
   g_lastBar      = 0;

   //--- Seed the alert stamps with any session boundary that has already
   //--- passed, so attaching the indicator never fires a stale alert.
   datetime nowInit = TimeCurrent();
   for(int s = 0; s < SESSION_COUNT; s++)
     {
      g_alertOpen[s]  = 0;
      g_alertClose[s] = 0;
      for(int d = 2; d >= 0; d--)
        {
         datetime f, t;
         SessionWindow(s, DayStart(d), f, t);
         if(nowInit >= f && nowInit < f + 300)
            g_alertOpen[s] = f;
         if(nowInit >= t && nowInit < t + 300)
            g_alertClose[s] = t;
        }
     }

   DeleteOwnObjects();

   //--- PERIOD_CURRENT (0) would otherwise disable everything
   int maxTf = (InpMaxTimeframe == PERIOD_CURRENT) ? Period() : (int)InpMaxTimeframe;
   g_active  = (Period() <= maxTf);
   if(!g_active)
     {
      DrawPanelLine(PREFIX + "pnl_0", 0,
                    "SessionsOnly: timeframe too high - switch to M1..H4", clrTomato);
      ChartRedraw();
      return(INIT_SUCCEEDED);
     }

   RedrawAll();
   UpdatePanel();
   ChartRedraw();

   if(InpShowPanel)
      EventSetTimer(1);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteOwnObjects();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Timer (panel countdown)                                          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_active)
      return;
   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Calculation                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(!g_active)
      return(rates_total);
   if(rates_total < 2)
      return(rates_total);

   bool newBar = (g_lastBar != Time[0]);
   if(newBar)
     {
      g_lastBar = Time[0];
      if(InpOffsetMode == OFFSET_AUTO)
         g_brokerOffset = DetectBrokerOffset();
      DeleteOwnObjects();
      RedrawAll();
     }
   else
      UpdateLiveSessions();

   UpdatePanel();
   CheckAlerts();
   ChartRedraw();

   return(rates_total);
  }
//+------------------------------------------------------------------+
