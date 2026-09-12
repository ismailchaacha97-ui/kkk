//+------------------------------------------------------------------+
//|                                                PremiumDiscount.mq5 |
//|         ICT-style Premium / Discount dealing-range indicator      |
//|                                                                   |
//|  Shows where price is EXPENSIVE (premium = sell high) and CHEAP   |
//|  (discount = buy low) relative to the daily / Asia dealing range. |
//|                                                                   |
//|  Levels (fractions of the dealing range, from range low):         |
//|    +50%  target extension      (high + 0.5 range)                 |
//|    100%  range high  -> PREMIUM (sell area)                       |
//|    70.5% deep premium   (optimal sell entry, ICT OTE)             |
//|    75%   half premium                                             |
//|    50%   EQUILIBRIUM (EQ)                                         |
//|    25%   half discount                                            |
//|    29.5% deep discount   (optimal buy entry, ICT OTE)             |
//|    0%    range low   -> DISCOUNT (buy area)                       |
//|    -50%  target extension      (low - 0.5 range)                  |
//|                                                                   |
//|  Anchor modes: PREV DAY (previous daily candle, stable),          |
//|                CUR DAY  (today's developing daily candle),        |
//|                ASIA     (most recent completed Asia session).     |
//|                                                                   |
//|  Alerts fire on CLOSED bars only (never repaint) and can be       |
//|  restricted to the London / New York kill zones.                  |
//|                                                                   |
//|  Draws only with chart objects - no indicator buffers.            |
//+------------------------------------------------------------------+
#property copyright "Arena"
#property link      ""
#property version   "1.00"
#property description "Premium/Discount dealing-range indicator (ICT style)"
#property description " "
#property description "BUY in DISCOUNT (below EQ = cheap), SELL in PREMIUM (above EQ = expensive)."
#property description "Deep levels 70.5%/29.5% of the range are the optimal entry areas."
#property indicator_chart_window

//--- anchor mode
enum ENUM_PD_ANCHOR
  {
   PD_ANCHOR_PREV_DAY = 0,   // Previous daily candle
   PD_ANCHOR_CUR_DAY  = 1,   // Current daily candle (developing)
   PD_ANCHOR_ASIA     = 2    // Asia session (completed)
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== 1. Anchor / dealing range ==="
input ENUM_PD_ANCHOR InpAnchorMode       = PD_ANCHOR_PREV_DAY; // Anchor mode
input bool          InpUseOpenAsEQ       = false;              // EQ = session open (else 50% of range)
input int           InpAsiaStartHour     = 0;                  // Asia start hour (server time)
input int           InpAsiaStartMinute   = 0;                  // Asia start minute
input int           InpAsiaEndHour       = 6;                  // Asia end hour
input int           InpAsiaEndMinute     = 0;                  // Asia end minute
input int           InpMaxBarsLookback   = 5000;               // Max bars scanned back for the range
input double        InpMinRangePoints    = 0.0;                // Min range in points (0 = auto ~10 pips)

input group "=== 2. Display ==="
input bool          InpShowZoneFill      = true;               // Show premium/discount zone fill
input int           InpFillAlpha         = 45;                 // Fill opacity 0-255 (MT5 only)
input bool          InpShowDeepFill      = true;               // Highlight deep 70.5%/29.5% sub-zones
input bool          InpShowLevels        = true;               // Draw price levels
input bool          InpShowDeepLevels    = true;               // Show deep premium/discount levels
input bool          InpShowExtensions    = true;               // Show +50%/-50% target extensions
input bool          InpShowHalfLevels    = false;              // Show 75%/25% half levels
input bool          InpShowLabels        = true;               // Show level labels
input int           InpLabelBarsRight    = 10;                 // Label offset (bars to the right)
input bool          InpShowPriceLine     = true;               // Show current-price dotted line
input bool          InpShowPanel         = true;               // Show info panel
input int           InpPanelCorner       = 0;                  // Panel corner: 0 TL, 1 TR, 2 BL, 3 BR
input int           InpEdgeWidth         = 2;                  // Range edge line width
input int           InpEQWidth           = 2;                  // EQ line width
input int           InpLevelWidth        = 1;                  // Inner level line width
input color         InpColorTop          = C'255,82,82';       // Range high (premium) color
input color         InpColorBottom       = C'76,175,80';       // Range low (discount) color
input color         InpColorEQ           = C'255,193,7';       // Equilibrium color
input color         InpColorDeep         = C'255,140,0';       // Deep 70.5/29.5 color
input color         InpColorExt          = C'150,150,160';     // Extension color
input color         InpColorHalf         = C'120,120,130';     // Half-level color
input color         InpColorPrice        = C'200,200,210';     // Current price line color
input color         InpColorFillPremium  = C'255,90,90';       // Premium zone fill
input color         InpColorFillDiscount = C'80,190,90';       // Discount zone fill
input color         InpColorFillDeep     = C'255,150,40';      // Deep sub-zone fill
input color         InpColorPanelBG      = C'22,26,33';        // Panel background
input color         InpColorPanelBorder  = C'70,76,86';        // Panel border
input color         InpColorPanelText    = C'225,228,233';     // Panel text

input group "=== 3. Alerts (bar close only - never repaints) ==="
input bool          InpAlertsEnabled     = true;               // Enable alerts
input bool          InpAlertOnlyKillZones= true;               // Alert only inside kill zones
input bool          InpAlertPopup        = true;               // Popup alert
input bool          InpAlertSound        = true;               // Sound alert
input bool          InpAlertPush         = false;              // Push notification (mobile)
input bool          InpAlertEmail        = false;              // Email alert
input string        InpAlertSoundFile    = "alert2.wav";       // Sound file
input bool          InpAlertEQTouch      = true;               // Alert: price enters premium/discount
input bool          InpAlertDeepLevels   = true;               // Alert: deep 70.5%/29.5% reached
input bool          InpAlertEQRetest     = true;               // Alert: EQ retested after deep move
input bool          InpAlertOpenDeep     = true;               // Alert: session opens deep in a zone

input group "=== 4. Kill zones (server time) ==="
input bool          InpUseKZ1            = true;               // Use kill zone 1
input string        InpKZ1Name           = "London KZ";        // Kill zone 1 name
input int           InpKZ1FromHour       = 7;                  // KZ1 from hour
input int           InpKZ1FromMinute     = 0;                  // KZ1 from minute
input int           InpKZ1ToHour         = 10;                 // KZ1 to hour
input int           InpKZ1ToMinute       = 0;                  // KZ1 to minute
input bool          InpUseKZ2            = true;               // Use kill zone 2
input string        InpKZ2Name           = "New York KZ";      // Kill zone 2 name
input int           InpKZ2FromHour       = 13;                 // KZ2 from hour
input int           InpKZ2FromMinute     = 0;                  // KZ2 from minute
input int           InpKZ2ToHour         = 16;                 // KZ2 to hour
input int           InpKZ2ToMinute       = 0;                  // KZ2 to minute

//+------------------------------------------------------------------+
//| Structures & state                                               |
//+------------------------------------------------------------------+
struct SessionRange
  {
   datetime          start;
   datetime          end;
   double            high;
   double            low;
   double            open;
   double            eq;
   bool              valid;
   string            tag;
  };

struct Levels
  {
   double            eq;
   double            top;
   double            bot;
   double            deepPrem;
   double            deepDisc;
   double            halfPrem;
   double            halfDisc;
   double            extPrem;
   double            extDisc;
  };

SessionRange g_sess;
datetime     g_lastBarTime = 0;
string       g_prefix = "";

//--- alert state (reset whenever the anchor session changes)
bool g_firedEQTouchDown = false;
bool g_firedEQTouchUp   = false;
bool g_firedDeepDisc    = false;
bool g_firedDeepPrem    = false;
bool g_firedRetestPrem  = false;
bool g_firedRetestDisc  = false;
bool g_firedOpenDeepDisc= false;
bool g_firedOpenDeepPrem= false;
bool g_visitedDeepPrem  = false;
bool g_visitedDeepDisc  = false;
int  g_processedBars    = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string DS(double v) { return DoubleToString(v, _Digits); }

string TFName()
  {
   switch(_Period)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
     }
   return "TF" + IntegerToString(_Period);
  }

double MinRangePrice()
  {
   if(InpMinRangePoints > 0.0)
      return InpMinRangePoints * _Point;
   return 100.0 * _Point;    // auto: ~10 pips on FX, ~$1 on gold
  }

string FormatHMS(int secs)
  {
   int h = secs / 3600;
   int m = (secs % 3600) / 60;
   int s = secs % 60;
   return StringFormat("%02d:%02d:%02d", h, m, s);
  }

//--- cross-midnight safe time window check
bool TimeInWindow(datetime t, int fh, int fm, int th, int tm)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = fh; dt.min = fm; dt.sec = 0;
   datetime wStart = StructToTime(dt);
   int dur = (th * 3600 + tm * 60) - (fh * 3600 + fm * 60);
   if(dur <= 0) dur += 86400;
   if(t >= wStart && t < wStart + dur) return true;
   if(t >= wStart - 86400 && t < wStart - 86400 + dur) return true;
   return false;
  }

int SecondsToWindowOpen(datetime t, int fh, int fm)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = fh; dt.min = fm; dt.sec = 0;
   datetime wStart = StructToTime(dt);
   int secs = (int)(wStart - t);
   while(secs <= 0) secs += 86400;
   return secs;
  }

//--- most recent COMPLETED Asia session window [start, end)
void AsiaWindow(datetime now, datetime &start, datetime &end)
  {
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = InpAsiaStartHour; dt.min = InpAsiaStartMinute; dt.sec = 0;
   start = StructToTime(dt);
   int dur = (InpAsiaEndHour * 3600 + InpAsiaEndMinute * 60)
           - (InpAsiaStartHour * 3600 + InpAsiaStartMinute * 60);
   if(dur <= 0) dur += 86400;
   end = start + dur;
   if(end > now) { start -= 86400; end -= 86400; }
  }

void ResetSessionState()
  {
   g_firedEQTouchDown = false;
   g_firedEQTouchUp   = false;
   g_firedDeepDisc    = false;
   g_firedDeepPrem    = false;
   g_firedRetestPrem  = false;
   g_firedRetestDisc  = false;
   g_firedOpenDeepDisc= false;
   g_firedOpenDeepPrem= false;
   g_visitedDeepPrem  = false;
   g_visitedDeepDisc  = false;
   g_processedBars    = 0;
  }

//+------------------------------------------------------------------+
//| Session / range detection                                        |
//+------------------------------------------------------------------+
bool CollectRange(datetime from, datetime to, double minRange, SessionRange &s)
  {
   double hi = -DBL_MAX;
   double lo = DBL_MAX;
   double firstOpen = 0.0;
   int count = 0;
   for(int shift = 0; shift < InpMaxBarsLookback; shift++)
     {
      datetime t = iTime(_Symbol, _Period, shift);
      if(t == 0 || t < from - 86400)   // time-bounded scan (weekend / history safe)
         break;
      if(to > 0 && t >= to)            // bars belonging to a newer day -> skip
         continue;
      double h = iHigh(_Symbol, _Period, shift);
      double l = iLow(_Symbol, _Period, shift);
      if(h > hi) hi = h;
      if(l < lo) lo = l;
      firstOpen = iOpen(_Symbol, _Period, shift);
      count++;
     }
   if(count < 1 || hi <= lo)
      return false;
   if(hi - lo < minRange)
      return false;
   s.start = from;
   s.end = (to == 0) ? from + 86400 : to;
   s.high = hi;
   s.low = lo;
   s.open = firstOpen;
   s.valid = true;
   return true;
  }

//--- find the active dealing range; returns true if it changed
bool UpdateSession()
  {
   SessionRange s;
   s.valid = false;
   s.start = 0; s.end = 0; s.high = 0; s.low = 0; s.open = 0; s.eq = 0; s.tag = "";
   double minRange = MinRangePrice();

   if(InpAnchorMode == PD_ANCHOR_ASIA)
     {
      datetime now = TimeCurrent();
      for(int tries = 0; tries < 7 && !s.valid; tries++)
        {
         datetime wStart, wEnd;
         AsiaWindow(now - tries * 86400, wStart, wEnd);
         if(CollectRange(wStart, wEnd, minRange, s))
            s.tag = "ASIA";
        }
     }

   if(!s.valid)
     {
      int k0 = (InpAnchorMode == PD_ANCHOR_CUR_DAY) ? 0 : 1;
      for(int k = k0; k <= 3 && !s.valid; k++)
        {
         datetime d1 = iTime(_Symbol, PERIOD_D1, k);          // window start
         datetime d1n = (k == 0) ? 0 : iTime(_Symbol, PERIOD_D1, k - 1); // window end
         if(d1 == 0) continue;
         if(k > 0 && d1n == 0) continue;
         if(CollectRange(d1, d1n, minRange, s))
           {
            s.tag = (k == 0) ? "CUR DAY" : "PREV DAY";
            s.open = iOpen(_Symbol, PERIOD_D1, k);             // exact daily open
           }
        }
     }

   if(s.valid)
      s.eq = InpUseOpenAsEQ ? s.open : (s.high + s.low) / 2.0;

   bool changed = (s.valid != g_sess.valid || s.start != g_sess.start || s.end != g_sess.end);
   g_sess = s;
   if(changed)
      ResetSessionState();
   return changed;
  }

//+------------------------------------------------------------------+
//| Level & zone math                                                |
//+------------------------------------------------------------------+
void CalcLevels(const SessionRange &s, Levels &lv)
  {
   double r = s.high - s.low;
   lv.top = s.high;
   lv.bot = s.low;
   lv.eq = s.eq;
   lv.deepPrem = s.low + 0.705 * r;
   lv.deepDisc = s.low + 0.295 * r;
   lv.halfPrem = s.low + 0.75 * r;
   lv.halfDisc = s.low + 0.25 * r;
   lv.extPrem = s.low + 1.5 * r;
   lv.extDisc = s.low - 0.5 * r;
  }

void DescribeZone(double price, const Levels &lv, string &text, color &clr)
  {
   if(price > lv.top)          { text = "EXTREME PREMIUM - SELL AREA";  clr = InpColorTop; }
   else if(price > lv.deepPrem){ text = "DEEP PREMIUM - SELL AREA";     clr = InpColorDeep; }
   else if(price > lv.eq)      { text = "PREMIUM - SELL AREA";          clr = InpColorTop; }
   else if(price < lv.bot)     { text = "EXTREME DISCOUNT - BUY AREA";  clr = InpColorBottom; }
   else if(price < lv.deepDisc){ text = "DEEP DISCOUNT - BUY AREA";     clr = InpColorDeep; }
   else if(price < lv.eq)      { text = "DISCOUNT - BUY AREA";          clr = InpColorBottom; }
   else                        { text = "AT EQUILIBRIUM - NEUTRAL";     clr = InpColorPanelText; }
  }

string ZonePct(double price, const Levels &lv)
  {
   double r = lv.top - lv.bot;
   if(price > lv.eq)
     {
      double den = lv.top - lv.eq;
      double pct = (den > 0.001 * r) ? (price - lv.eq) / den * 100.0 : 100.0;
      return StringFormat("PREMIUM %.1f%%", pct);
     }
   if(price < lv.eq)
     {
      double den = lv.eq - lv.bot;
      double pct = (den > 0.001 * r) ? (lv.eq - price) / den * 100.0 : 100.0;
      return StringFormat("DISCOUNT %.1f%%", pct);
     }
   return "AT EQ 0%";
  }

//+------------------------------------------------------------------+
//| Chart objects                                                    |
//+------------------------------------------------------------------+
string O(string id) { return g_prefix + id; }

void ShowObj(string id, bool visible)
  {
   string name = O(id);
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
  }

bool EnsureObj(string id, ENUM_OBJECT type)
  {
   string name = O(id);
   if(ObjectFind(0, name) < 0)
      return ObjectCreate(0, name, type, 0, 0, 0);
   return true;
  }

void SetRect(string id, datetime t0, double p0, datetime t1, double p1,
             color clr, int alpha, bool visible)
  {
   EnsureObj(id, OBJ_RECTANGLE);
   string name = O(id);
   ObjectSetInteger(0, name, OBJPROP_TIME1, (long)t0);
   ObjectSetDouble(0, name, OBJPROP_PRICE1, p0);
   ObjectSetInteger(0, name, OBJPROP_TIME2, (long)t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE2, p1);
   ObjectSetInteger(0, name, OBJPROP_COLOR, ColorToARGB((uchar)alpha, clr));
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);      // behind candles
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
  }

void SetLine(string id, datetime t0, datetime t1, double p, int style, int width,
             color clr, string label, bool showLabel)
  {
   EnsureObj(id, OBJ_TREND);
   string name = O(id);
   ObjectSetInteger(0, name, OBJPROP_TIME1, (long)t0);
   ObjectSetDouble(0, name, OBJPROP_PRICE1, p);
   ObjectSetInteger(0, name, OBJPROP_TIME2, (long)t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE2, p);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   if(showLabel && label != "")
     {
      EnsureObj("T_" + id, OBJ_TEXT);
      string lname = O("T_" + id);
      ObjectSetInteger(0, lname, OBJPROP_TIME1, (long)t1);
      ObjectSetDouble(0, lname, OBJPROP_PRICE1, p);
      ObjectSetInteger(0, lname, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, lname, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lname, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, lname, OBJPROP_FONT, "Arial");
      ObjectSetString(0, lname, OBJPROP_TEXT, " " + label);
      ObjectSetInteger(0, lname, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lname, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, lname, OBJPROP_BACK, false);
      ObjectSetInteger(0, lname, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
     }
   else
      ShowObj("T_" + id, false);
  }

void SetPanelLabel(string id, int corner, int x, int y, string text, color clr, int size)
  {
   EnsureObj(id, OBJ_LABEL);
   string name = O(id);
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
  }

void SetPanelBG(string id, int corner, int x, int y, int xsize, int ysize, color bg, color border)
  {
   EnsureObj(id, OBJ_RECTANGLE_LABEL);
   string name = O(id);
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, xsize);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, ysize);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
  }

void HideLevelObjects()
  {
   ShowObj("L_TOP", false);    ShowObj("T_TOP", false);
   ShowObj("L_BOTTOM", false); ShowObj("T_BOTTOM", false);
   ShowObj("L_EQ", false);     ShowObj("T_EQ", false);
   ShowObj("L_DEEPP", false);  ShowObj("T_DEEPP", false);
   ShowObj("L_DEEPD", false);  ShowObj("T_DEEPD", false);
   ShowObj("L_HALFP", false);  ShowObj("T_HALFP", false);
   ShowObj("L_HALFD", false);  ShowObj("T_HALFD", false);
   ShowObj("L_EXTP", false);   ShowObj("T_EXTP", false);
   ShowObj("L_EXTD", false);   ShowObj("T_EXTD", false);
   ShowObj("PRICE", false);
  }

void HideZoneObjects()
  {
   ShowObj("BAND_PREM", false);
   ShowObj("BAND_DISC", false);
   ShowObj("DEEP_PREM", false);
   ShowObj("DEEP_DISC", false);
  }

//+------------------------------------------------------------------+
//| Rendering                                                        |
//+------------------------------------------------------------------+
void DrawSession()
  {
   if(!g_sess.valid)
     {
      HideZoneObjects();
      HideLevelObjects();
      return;
     }
   Levels lv;
   CalcLevels(g_sess, lv);
   datetime t0 = g_sess.start;
   datetime t1 = iTime(_Symbol, _Period, 0) + (InpLabelBarsRight + 1) * PeriodSeconds();

   //--- zone fills (drawn behind the candles)
   if(InpShowZoneFill)
     {
      SetRect("BAND_PREM", t0, lv.eq, t1, lv.top, InpColorFillPremium, InpFillAlpha, true);
      SetRect("BAND_DISC", t0, lv.bot, t1, lv.eq, InpColorFillDiscount, InpFillAlpha, true);
      if(InpShowDeepFill)
        {
         int a2 = InpFillAlpha + 55;
         if(a2 > 255) a2 = 255;
         SetRect("DEEP_PREM", t0, lv.deepPrem, t1, lv.top, InpColorFillDeep, a2, true);
         SetRect("DEEP_DISC", t0, lv.bot, t1, lv.deepDisc, InpColorFillDeep, a2, true);
        }
      else
        {
         ShowObj("DEEP_PREM", false);
         ShowObj("DEEP_DISC", false);
        }
     }
   else
      HideZoneObjects();

   //--- levels
   if(InpShowLevels)
     {
      SetLine("L_TOP",    t0, t1, lv.top,       STYLE_SOLID, InpEdgeWidth,  InpColorTop,
              "RANGE HIGH 100%  " + DS(lv.top), InpShowLabels);
      SetLine("L_BOTTOM", t0, t1, lv.bot,       STYLE_SOLID, InpEdgeWidth,  InpColorBottom,
              "RANGE LOW 0%  " + DS(lv.bot), InpShowLabels);
      SetLine("L_EQ",     t0, t1, lv.eq,        STYLE_SOLID, InpEQWidth,    InpColorEQ,
              InpUseOpenAsEQ ? "EQ (OPEN)  " + DS(lv.eq) : "EQ 50%  " + DS(lv.eq), InpShowLabels);
      if(InpShowDeepLevels)
        {
         SetLine("L_DEEPP", t0, t1, lv.deepPrem, STYLE_DASH, InpLevelWidth, InpColorDeep,
                 "DEEP PREMIUM 70.5%  " + DS(lv.deepPrem), InpShowLabels);
         SetLine("L_DEEPD", t0, t1, lv.deepDisc, STYLE_DASH, InpLevelWidth, InpColorDeep,
                 "DEEP DISCOUNT 29.5%  " + DS(lv.deepDisc), InpShowLabels);
        }
      else
        {
         ShowObj("L_DEEPP", false); ShowObj("T_DEEPP", false);
         ShowObj("L_DEEPD", false); ShowObj("T_DEEPD", false);
        }
      if(InpShowHalfLevels)
        {
         SetLine("L_HALFP", t0, t1, lv.halfPrem, STYLE_DOT, InpLevelWidth, InpColorHalf,
                 "HALF PREMIUM 75%  " + DS(lv.halfPrem), InpShowLabels);
         SetLine("L_HALFD", t0, t1, lv.halfDisc, STYLE_DOT, InpLevelWidth, InpColorHalf,
                 "HALF DISCOUNT 25%  " + DS(lv.halfDisc), InpShowLabels);
        }
      else
        {
         ShowObj("L_HALFP", false); ShowObj("T_HALFP", false);
         ShowObj("L_HALFD", false); ShowObj("T_HALFD", false);
        }
      if(InpShowExtensions)
        {
         SetLine("L_EXTP", t0, t1, lv.extPrem, STYLE_DOT, InpLevelWidth, InpColorExt,
                 "TARGET +50%  " + DS(lv.extPrem), InpShowLabels);
         SetLine("L_EXTD", t0, t1, lv.extDisc, STYLE_DOT, InpLevelWidth, InpColorExt,
                 "TARGET -50%  " + DS(lv.extDisc), InpShowLabels);
        }
      else
        {
         ShowObj("L_EXTP", false); ShowObj("T_EXTP", false);
         ShowObj("L_EXTD", false); ShowObj("T_EXTD", false);
        }
     }
   else
      HideLevelObjects();

   //--- current price dotted line
   if(InpShowPriceLine)
      SetLine("PRICE", t0, t1, iClose(_Symbol, _Period, 0), STYLE_DOT, 1, InpColorPrice, "", false);
   else
      ShowObj("PRICE", false);
  }

//+------------------------------------------------------------------+
//| Info panel                                                       |
//+------------------------------------------------------------------+
string KZLine(datetime now, bool enabled, string name, int fh, int fm, int th, int tm)
  {
   if(!enabled)
      return name + ": disabled";
   if(TimeInWindow(now, fh, fm, th, tm))
      return name + ": OPEN NOW";
   return name + ": in " + FormatHMS(SecondsToWindowOpen(now, fh, fm));
  }

int CornerFromInput()
  {
   switch(InpPanelCorner)
     {
      case 1: return CORNER_RIGHT_UPPER;
      case 2: return CORNER_LEFT_LOWER;
      case 3: return CORNER_RIGHT_LOWER;
     }
   return CORNER_LEFT_UPPER;
  }

int LongestLine(const string &txt)
  {
   int longest = 0, cur = 0;
   int len = StringLen(txt);
   for(int i = 0; i < len; i++)
     {
      string ch = StringSubstr(txt, i, 1);
      if(ch == "\n") { if(cur > longest) longest = cur; cur = 0; }
      else cur++;
     }
   if(cur > longest) longest = cur;
   return longest;
  }

void UpdatePanel()
  {
   int corner = CornerFromInput();
   if(!InpShowPanel)
     {
      ShowObj("PNL_BG", false);
      ShowObj("PNL_MAIN", false);
      ShowObj("PNL_ZONE", false);
      ShowObj("PNL_REST", false);
      return;
     }

   double px = iClose(_Symbol, _Period, 0);
   datetime now = TimeCurrent();
   string mainTxt, zoneTxt, restTxt, zoneDesc;
   color zoneClr = InpColorPanelText;

   if(g_sess.valid)
     {
      Levels lv;
      CalcLevels(g_sess, lv);
      mainTxt = "PREMIUM / DISCOUNT   " + _Symbol + " " + TFName() + "\n"
              + "Anchor: " + g_sess.tag + "   (" + TimeToString(g_sess.start, TIME_DATE) + ")\n"
              + "Range:  " + DS(lv.bot) + " - " + DS(lv.top)
              + "   (" + DS(lv.top - lv.bot) + ")\n"
              + "EQ:     " + DS(lv.eq)
              + (InpUseOpenAsEQ ? " (session open)" : " (50%)") + "\n"
              + "Price:  " + DS(px);
      zoneTxt = "Position: " + ZonePct(px, lv) + "   >>   ";
      DescribeZone(px, lv, zoneDesc, zoneClr);
      restTxt = "Deep prem: " + DS(lv.deepPrem) + "   Deep disc: " + DS(lv.deepDisc) + "\n"
              + KZLine(now, InpUseKZ1, InpKZ1Name, InpKZ1FromHour, InpKZ1FromMinute, InpKZ1ToHour, InpKZ1ToMinute) + "\n"
              + KZLine(now, InpUseKZ2, InpKZ2Name, InpKZ2FromHour, InpKZ2FromMinute, InpKZ2ToHour, InpKZ2ToMinute) + "\n"
              + "Server: " + TimeToString(now, TIME_DATE) + " " + TimeToString(now, TIME_MINUTES);
     }
   else
     {
      mainTxt = "PREMIUM / DISCOUNT   " + _Symbol + " " + TFName() + "\n"
              + "Anchor: collecting data...\n"
              + "Range:  n/a\n"
              + "EQ:     n/a\n"
              + "Price:  " + DS(px);
      zoneTxt = "Position: n/a";
      zoneDesc = "";
     }

   SetPanelLabel("PNL_MAIN", corner, 10, 24, mainTxt, InpColorPanelText, 9);
   SetPanelLabel("PNL_ZONE", corner, 10, 24 + 5 * 15 + 6, zoneTxt + zoneDesc, zoneClr, 9);
   SetPanelLabel("PNL_REST", corner, 10, 24 + 5 * 15 + 6 + 16, restTxt, InpColorPanelText, 9);

   //--- background box sized to the longest line
   int longest = LongestLine(mainTxt);
   int l2 = LongestLine(zoneTxt + zoneDesc);
   int l3 = LongestLine(restTxt);
   if(l2 > longest) longest = l2;
   if(l3 > longest) longest = l3;
   if(longest < 20) longest = 20;
   int lines = 5 + 1 + 4;
   SetPanelBG("PNL_BG", corner, 4, 16, longest * 7 + 16, lines * 15 + 26,
              InpColorPanelBG, InpColorPanelBorder);
  }

//+------------------------------------------------------------------+
//| Alerts (evaluated on closed bars only -> never repaint)          |
//+------------------------------------------------------------------+
void Notify(string msg)
  {
   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound(InpAlertSoundFile);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("Premium/Discount alert", msg);
  }

bool InKillZoneNow(datetime now)
  {
   if(InpUseKZ1 && TimeInWindow(now, InpKZ1FromHour, InpKZ1FromMinute, InpKZ1ToHour, InpKZ1ToMinute)) return true;
   if(InpUseKZ2 && TimeInWindow(now, InpKZ2FromHour, InpKZ2FromMinute, InpKZ2ToHour, InpKZ2ToMinute)) return true;
   return false;
  }

void ProcessBarClose()
  {
   if(!g_sess.valid || !InpAlertsEnabled)
      return;

   datetime closedT = iTime(_Symbol, _Period, 1);
   datetime prevT   = iTime(_Symbol, _Period, 2);
   if(closedT < g_sess.start)
      return;                       // closed bar belongs to an older session
   bool prevInSession = (prevT >= g_sess.start);

   double c  = iClose(_Symbol, _Period, 1);
   double pc = iClose(_Symbol, _Period, 2);
   Levels lv;
   CalcLevels(g_sess, lv);
   double r = g_sess.high - g_sess.low;

   //--- visited-deep state is updated from the closed bar (always)
   if(c >= lv.deepPrem) g_visitedDeepPrem = true;
   if(c <= lv.deepDisc) g_visitedDeepDisc = true;
   g_processedBars++;

   datetime now = TimeCurrent();
   if(InpAlertOnlyKillZones && !InKillZoneNow(now))
      return;                       // outside kill zones -> suppressed

   string sym = _Symbol + " " + TFName();

   //--- entered discount / premium (crossed EQ)
   if(InpAlertEQTouch)
     {
      if(!g_firedEQTouchDown && prevInSession && c < lv.eq && pc >= lv.eq)
        {
         g_firedEQTouchDown = true;
         Notify(StringFormat("PD %s: price entered DISCOUNT - BUY AREA (%s below EQ %s, target EQ)",
                             sym, DS(c), DS(lv.eq)));
        }
      if(!g_firedEQTouchUp && prevInSession && c > lv.eq && pc <= lv.eq)
        {
         g_firedEQTouchUp = true;
         Notify(StringFormat("PD %s: price entered PREMIUM - SELL AREA (%s above EQ %s, target EQ)",
                             sym, DS(c), DS(lv.eq)));
        }
     }

   //--- deep levels crossed
   if(InpAlertDeepLevels)
     {
      if(!g_firedDeepDisc && prevInSession && c <= lv.deepDisc && pc > lv.deepDisc)
        {
         g_firedDeepDisc = true;
         Notify(StringFormat("PD %s: DEEP DISCOUNT - price %s at/below 29.5%% level %s - bargain buy zone",
                             sym, DS(c), DS(lv.deepDisc)));
        }
      if(!g_firedDeepPrem && prevInSession && c >= lv.deepPrem && pc < lv.deepPrem)
        {
         g_firedDeepPrem = true;
         Notify(StringFormat("PD %s: DEEP PREMIUM - price %s at/above 70.5%% level %s - sell zone",
                             sym, DS(c), DS(lv.deepPrem)));
        }
     }

   //--- EQ retested after a deep excursion (profit target / reversal area)
   if(InpAlertEQRetest && MathAbs(c - lv.eq) <= 0.05 * r)
     {
      if(!g_firedRetestPrem && g_visitedDeepPrem)
        {
         g_firedRetestPrem = true;
         Notify(StringFormat("PD %s: returned to EQ %s from deep premium - take-profit / reversal area",
                             sym, DS(lv.eq)));
        }
      if(!g_firedRetestDisc && g_visitedDeepDisc)
        {
         g_firedRetestDisc = true;
         Notify(StringFormat("PD %s: returned to EQ %s from deep discount - take-profit / reversal area",
                             sym, DS(lv.eq)));
        }
     }

   //--- session opened deep in a zone
   if(InpAlertOpenDeep && g_processedBars == 1)
     {
      if(!g_firedOpenDeepDisc && c <= lv.deepDisc)
        {
         g_firedOpenDeepDisc = true;
         Notify(StringFormat("PD %s: session opened in DEEP DISCOUNT (%s)", sym, DS(c)));
        }
      if(!g_firedOpenDeepPrem && c >= lv.deepPrem)
        {
         g_firedOpenDeepPrem = true;
         Notify(StringFormat("PD %s: session opened in DEEP PREMIUM (%s)", sym, DS(c)));
        }
     }
  }

//+------------------------------------------------------------------+
//| Indicator events                                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME, "Premium/Discount PD");
   g_prefix = StringFormat("PD_%d_", (int)ChartID());
   ObjectsDeleteAll(0, g_prefix);      // clean leftovers of this chart instance
   g_lastBarTime = 0;
   g_sess.valid = false;
   ResetSessionState();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw(0);
  }

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
   if(rates_total < 3)
      return 0;

   datetime barTime = time[rates_total - 1];
   bool newBar = (barTime != g_lastBarTime);

   //--- evaluate the bar that just closed (shift 1) once, at bar open
   if(newBar && g_lastBarTime != 0)
      ProcessBarClose();
   g_lastBarTime = barTime;

   //--- refresh anchor range; redraw static objects when it changes
   bool changed = UpdateSession();
   if(newBar || changed)
      DrawSession();

   UpdatePanel();
   ChartRedraw(0);
   return rates_total;
  }
//+------------------------------------------------------------------+
