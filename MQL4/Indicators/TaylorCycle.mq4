//+------------------------------------------------------------------+
//| TaylorCycle.mq4  —  Taylor 3-Day Overnight/Daytrade Cycle        |
//| Version 2.02  (MQL4, MT4 build 600+)                              |
//|                                                                    |
//| Pre-open day labels (BUY / SHORT / SELL), prev-day High/Low,       |
//| Turn-of-Month + pre-macro flags, DT1/DT2/DT3 setup arrows with     |
//| entry/stop/target lines, 52-week + seasonal leadership score,      |
//| live session dashboard, alerts/push/mail.                          |
//|                                                                    |
//| Recommended: M30 chart, SP500/NAS100/US30 CFD (works on FX too).   |
//| See MT4_GUIDE.md for install + input help.                         |
//| Educational research — NOT financial advice.                       |
//+------------------------------------------------------------------+
#property copyright "TaylorCycle v2.0 — educational"
#property version   "2.02"
#property description "Taylor 3-day cycle: day labels, prev H/L, ToM/macro, DT1-DT3 arrows, dashboard"
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "DT1 Dip Long"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2
#property indicator_label2  "DT2 Fade Short"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_width2  2
#property indicator_label3  "DT3 Gap Long"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrAqua
#property indicator_width3  1
#property indicator_label4  "DT3 Gap Short"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrMagenta
#property indicator_width4  1

//--- inputs: cycle
input int    InpAtrPeriod    = 14;     // ATR period (daily)
input int    InpSwingN       = 5;      // Swing lookback (daily highs)
input double InpMinClosePos  = 0.60;   // Min close position to hold/confirm
input double InpViolationPen = 0.25;   // Violation: break prev low (ATR)
input double InpViolationCP  = 0.35;   // Violation: weak close below
//--- inputs: setups
input double InpStopAtr      = 0.5;    // Stop distance (ATR)
input double InpReclaimAtr   = 0.10;   // Reclaim/reject buffer (ATR)
input double InpGapFadeAtr   = 0.5;    // DT3 gap threshold (ATR)
input bool   InpUseGapFade   = true;   // Show DT3 gap-fade arrows
//--- inputs: leadership
input bool   InpUse52W       = true;   // Use 52-week leadership
input int    InpWeeks52      = 52;     // Weeks for 52W window (~x5 daily bars)
input double InpMinH52       = 0.90;   // Min Close/52W-high ratio
input double InpMinRec       = 0.75;   // Min 52W recency (1-N/365)
input bool   InpUseSeasonal  = true;   // Use same-month seasonality
input int    InpSeasonYears  = 5;      // Seasonal lookback (years)
//--- inputs: calendar/time
input string InpMacroDates   = "2026.10.02,2026.10.14,2026.10.28,2026.11.06,2026.11.10,2026.12.04,2026.12.09,2026.12.10";
input double InpETOffset     = -4.0;   // ET offset from GMT (-4 EDT Mar-Nov, -5 EST)
input int    InpHistoryDays  = 30;     // History days to draw/scan
//--- inputs: display
input bool   InpShowDashboard = true;  // Show dashboard
input bool   InpShowDayBoxes  = true;  // Show day-type boxes
input bool   InpShowPrevHL    = true;  // Show prev-day High/Low lines
input bool   InpShow52WLine   = false; // Show 52W-high line
input int    InpFontSize      = 8;      // Dashboard font size
input int    InpCorner        = 0;      // Corner: 0=LU 1=RU 2=LL 3=RU
input color  InpBuyColor      = C'20,80,20';    // BUY-day box tint
input color  InpShortColor    = C'120,25,25';   // SHORT-day box tint
input color  InpSellColor     = C'70,70,70';    // SELL-day box tint
input color  InpTomColor      = clrGold;        // ToM marker color
//--- inputs: alerts
input bool   InpAlerts = true;   // Popup alerts on trigger
input bool   InpPush   = false;  // Push notifications (configure MetaQuotes ID)
input bool   InpMail   = false;  // Email alerts (configure SMTP)
input bool   InpDebug  = true;   // Debug: Experts-log trail + DBG dashboard row

//--- buffers
double g_dt1[], g_dt2[], g_dt3l[], g_dt3s[];
//--- macro calendar (ET day-keys)
int    g_macroKeys[];
//--- alert memory
int    g_lastAlertKey = -1;
string g_lastAlertTag = "";
int    g_boxCount = 0;
int    g_lastErr = 0;

//+------------------------------------------------------------------+
//| Date math (Howard Hinnant civil algorithms, ET-day keys)          |
//+------------------------------------------------------------------+
int DateToKey(int y, int m, int d)
{
   y -= (m <= 2 ? 1 : 0);
   int era = (y >= 0 ? y : y - 399) / 400;
   int yoe = y - era * 400;
   int mp  = m + (m > 2 ? -3 : 9);
   int doy = (153 * mp + 2) / 5 + d - 1;
   int doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
   return era * 146097 + doe - 719468;
}
void KeyToDate(int z, int &y, int &m, int &d)
{
   z += 719468;
   int era = (z >= 0 ? z : z - 146096) / 146097;
   int doe = z - era * 146097;
   int yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
   y = yoe + era * 400;
   int doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
   int mp  = (5 * doy + 2) / 153;
   d = doy - (153 * mp + 2) / 5 + 1;
   m = mp + (mp < 10 ? 3 : -9);
   y += (m <= 2 ? 1 : 0);
}
int KeyWeekday(int key) { int w = (key + 4) % 7; if(w < 0) w += 7; return w; } // 0=Sun
bool IsLastTradingDayKey(int key)
{
   int n = key + 1, guard = 0;
   while((KeyWeekday(n) == 0 || KeyWeekday(n) == 6) && guard < 10) { n++; guard++; }
   int y1, m1, d1, y2, m2, d2;
   KeyToDate(key, y1, m1, d1); KeyToDate(n, y2, m2, d2);
   return (m2 != m1);
}
bool IsToMKey(int key)
{
   int y, m, d; KeyToDate(key, y, m, d);
   if(d <= 3) return true;
   return IsLastTradingDayKey(key);
}
int ETShiftSeconds()
{
   long serverGmt = (long)TimeCurrent() - (long)TimeGMT();
   int sh = (int)(InpETOffset * 3600.0 - (double)serverGmt);
   return (sh / 60) * 60; // minute-rounded: kills tick-to-tick wobble
}
int BarETKey(datetime t, int sh) { return (int)(((long)t + sh + 12 * 3600) / 86400); }
int ETMinutes(datetime t, int sh) // minutes since ET midnight
{
   long e = (long)t + sh;
   long d = (e >= 0 ? e : e - 86399) / 86400;
   return (int)((e - d * 86400) / 60);
}

//+------------------------------------------------------------------+
//| Macro calendar parse                                             |
//+------------------------------------------------------------------+
void ParseMacroDates()
{
   ArrayResize(g_macroKeys, 0);
   string s = InpMacroDates;
   StringReplace(s, ";", ",");
   string items[];
   int n = StringSplit(s, ',', items);
   for(int i = 0; i < n; i++)
   {
      string it = items[i];
      StringTrimLeft(it); StringTrimRight(it);
      StringReplace(it, "-", "."); StringReplace(it, "/", ".");
      string p[];
      if(StringSplit(it, '.', p) != 3) continue;
      int y = (int)StringToInteger(p[0]);
      int m = (int)StringToInteger(p[1]);
      int d = (int)StringToInteger(p[2]);
      if(y < 2000 || m < 1 || m > 12 || d < 1 || d > 31) continue;
      int sz = ArraySize(g_macroKeys);
      ArrayResize(g_macroKeys, sz + 1);
      g_macroKeys[sz] = DateToKey(y, m, d);
   }
}
bool IsMacroKey(int key)
{
   for(int i = 0; i < ArraySize(g_macroKeys); i++)
      if(g_macroKeys[i] == key) return true;
   return false;
}
bool IsPreMacroKey(int key)
{
   for(int i = 0; i < ArraySize(g_macroKeys); i++)
      if(g_macroKeys[i] == key + 1) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Daily helpers (broker D1; approximation documented in guide)      |
//+------------------------------------------------------------------+
int DnStreak(int fromSh) // consecutive down closes ending at fromSh (D1)
{
   int c = 0;
   for(int s = fromSh; s < fromSh + 10; s++)
   {
      if(s + 1 >= Bars(_Symbol, PERIOD_D1)) break;
      if(iClose(_Symbol, PERIOD_D1, s) < iClose(_Symbol, PERIOD_D1, s + 1)) c++;
      else break;
   }
   return c;
}
int UpStreak(int fromSh)
{
   int c = 0;
   for(int s = fromSh; s < fromSh + 10; s++)
   {
      if(s + 1 >= Bars(_Symbol, PERIOD_D1)) break;
      if(iClose(_Symbol, PERIOD_D1, s) > iClose(_Symbol, PERIOD_D1, s + 1)) c++;
      else break;
   }
   return c;
}
double DayClosePos(int sh)
{
   double h = iHigh(_Symbol, PERIOD_D1, sh), l = iLow(_Symbol, PERIOD_D1, sh);
   double c = iClose(_Symbol, PERIOD_D1, sh);
   if(h <= l) return 0.5;
   return (c - l) / (h - l);
}
// pre-open label for the day AFTER daily bar 'refSh' (refSh=1 -> today)
void DayLabel(int refSh, bool &isBuy, bool &isShort, bool &isSell, bool &isSuper)
{
   isBuy = false; isShort = false; isSell = false; isSuper = false;
   if(refSh + 8 >= Bars(_Symbol, PERIOD_D1)) return;
   int dn = DnStreak(refSh), up = UpStreak(refSh);
   if(dn >= 6 || up >= 6) { isSuper = true; return; }
   // swing-high shift relative to refSh
   int best = refSh; double mx = -1.0;
   for(int s = refSh; s <= refSh + InpSwingN; s++)
   {
      double h = iHigh(_Symbol, PERIOD_D1, s);
      if(h > mx) { mx = h; best = s; }
   }
   int sinceSwing = best - refSh; // 0=yesterday was swing high
   if(dn >= 2 || (dn >= 1 && (sinceSwing == 1 || sinceSwing == 2))) { isBuy = true; return; }
   if(up >= 2) { isShort = true; return; }
   // SELL: yesterday was a Buy-day ramp (dn2 through refSh+1, strong close at refSh)
   int dnY = DnStreak(refSh + 1);
   if(dnY >= 2 && DayClosePos(refSh) >= InpMinClosePos) { isSell = true; return; }
}

//+------------------------------------------------------------------+
//| Leadership: 52W ratio/recency + seasonal z                       |
//+------------------------------------------------------------------+
bool H52Stats(double &ratio, double &rec, double &hiPrice)
{
   ratio = 0; rec = 0; hiPrice = 0;
   if(!InpUse52W) return false;
   int need = InpWeeks52 * 5;
   int nb = Bars(_Symbol, PERIOD_D1);
   if(nb < need + 2) return false;
   double mx = -1.0; datetime mt = 0;
   for(int s = 1; s <= need; s++)
   {
      double h = iHigh(_Symbol, PERIOD_D1, s);
      if(h > mx) { mx = h; mt = iTime(_Symbol, PERIOD_D1, s); }
   }
   double c = iClose(_Symbol, PERIOD_D1, 1);
   if(mx <= 0 || c <= 0) return false;
   hiPrice = mx; ratio = c / mx;
   int days = (int)((TimeCurrent() - mt) / 86400);
   rec = 1.0 - (double)days / 365.0;
   return true;
}
bool SeasonalStats(double &sret, double &sz)
{
   sret = 0; sz = 0;
   if(!InpUseSeasonal) return false;
   int nb = Bars(_Symbol, PERIOD_MN1);
   if(nb < 14) return false;
   int cm = TimeMonth(TimeCurrent());
   double sum = 0, sum2 = 0; int k = 0;
   int cy = TimeYear(TimeCurrent());
   for(int s = 1; s < nb - 1 && k < InpSeasonYears + 1; s++)
   {
      datetime t = iTime(_Symbol, PERIOD_MN1, s);
      if(TimeMonth(t) != cm) continue;
      if(TimeYear(t) >= cy) continue;
      double c0 = iClose(_Symbol, PERIOD_MN1, s), c1 = iClose(_Symbol, PERIOD_MN1, s + 1);
      if(c1 <= 0) continue;
      double r = c0 / c1 - 1.0;
      sum += r; sum2 += r * r; k++;
      if(k >= InpSeasonYears) break;
   }
   if(k < 2) return false;
   sret = sum / k;
   double var = (sum2 - sum * sum / k) / (k - 1);
   double sd = MathSqrt(MathMax(var, 1e-12));
   sz = sret / sd;
   return true;
}

//+------------------------------------------------------------------+
//| Object helpers                                                   |
//+------------------------------------------------------------------+
string PREF = "TC_";
void MkLabel(string name, int y, string text, color clr)
{
   string n = PREF + name;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, InpCorner);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
}
void UpsertHLine(string name, double price, color clr, int style, int width, string text)
{
   string n = PREF + name;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, n, OBJPROP_PRICE, price);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_STYLE, style);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
}
void DeleteIfExists(string name)
{
   string n = PREF + name;
   if(ObjectFind(0, n) >= 0) ObjectDelete(0, n);
}
void DrawNote(string text)
{
   string n = PREF + "NOTE";
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 200);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, 200);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 12);
   ObjectSetString(0, n, OBJPROP_FONT, "Arial");
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
}
void DeleteNote() { DeleteIfExists("NOTE"); }
void UpsertDayBox(int key, datetime t1, datetime t2, double p1, double p2, color clr, bool tom)
{
   string n = StringFormat("%sBOX_%d", PREF, key);
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else { ObjectMove(0, n, 0, t1, p1); ObjectMove(0, n, 1, t2, p2); }
   ObjectSetInteger(0, n, OBJPROP_COLOR, tom ? InpTomColor : clr);
   ObjectSetInteger(0, n, OBJPROP_FILL, true);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, tom ? 2 : 1);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   g_boxCount++;
}
void PruneDayObjects(int minKey)
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string n = ObjectName(0, i);
      if(StringFind(n, PREF + "BOX_") != 0 && StringFind(n, PREF + "TAG_") != 0) continue;
      string tail = StringSubstr(n, StringLen(PREF) + 4);
      int k = (int)StringToInteger(tail);
      if(k < minKey) ObjectDelete(0, n);
   }
}
void UpsertDayTag(int key, datetime t, double p, string text, color clr)
{
   string n = StringFormat("%sTAG_%d", PREF, key);
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
   else ObjectMove(0, n, 0, t, p);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 7);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
}
void FireAlert(string tag, string msg, int key)
{
   if(key == g_lastAlertKey && tag == g_lastAlertTag) return;
   g_lastAlertKey = key; g_lastAlertTag = tag;
   if(InpAlerts) Alert(msg);
   if(InpPush) SendNotification(msg);
   if(InpMail) SendMail("TaylorCycle " + tag, msg);
}

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void ProcessDay(int dFirst, int dLast, int key, int nowKey,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], int etSh,
                double atrD, int b0key, int b0mm, int scoreNow);
void DrawDashboard(int nowKey, int nowMin,
                   bool isBuy, bool isShort, bool isSell, bool isSuper,
                   bool tom, bool preM, bool macT,
                   double prevH, double prevL, double prevC, double atrD,
                   double h52r, double h52rec, bool has52,
                   double sret, double sz, bool hasSe, int score,
                   const datetime &time[], const double &open[], const double &high[],
                   const double &low[], const double &close[], int etSh);
void UpdateLiveRows(int nowKey, int nowMin, const datetime &time[], int etSh);
color sLeadColor(bool has52, bool hasSe, double h52r, double h52rec, double sz);
string TFName();

//+------------------------------------------------------------------+
//| Init / Deinit                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, g_dt1, INDICATOR_DATA);
   SetIndexBuffer(1, g_dt2, INDICATOR_DATA);
   SetIndexBuffer(2, g_dt3l, INDICATOR_DATA);
   SetIndexBuffer(3, g_dt3s, INDICATOR_DATA);
   ArraySetAsSeries(g_dt1, true); ArraySetAsSeries(g_dt2, true);
   ArraySetAsSeries(g_dt3l, true); ArraySetAsSeries(g_dt3s, true);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(2, PLOT_ARROW, 241);
   PlotIndexSetInteger(3, PLOT_ARROW, 242);
   for(int i = 0; i < 4; i++) PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, 0.0);
   ParseMacroDates();
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREF);
   Comment("");
}

//+------------------------------------------------------------------+
//| Main                                                             |
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
   int d1bars = Bars(_Symbol, PERIOD_D1);
   if(rates_total < 100 || d1bars < 30)
   {
      DrawNote(StringFormat("TaylorCycle: loading history...  bars=%d  D1=%d (need 100 / 30)",
                            rates_total, d1bars));
      return 0;
   }
   DeleteNote();
   ArraySetAsSeries(time, true); ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int etSh = ETShiftSeconds();
   int nowKey = (int)(((long)TimeGMT() + (long)(InpETOffset * 3600.0) + 12 * 3600) / 86400);
   int nowMin = ETMinutes(TimeCurrent(), etSh);
   static datetime lastFullBar = 0;
   if(prev_calculated > 0 && time[0] == lastFullBar)
   {
      UpdateLiveRows(nowKey, nowMin, time, etSh); // clock + setup rows only
      return rates_total;
   }
   lastFullBar = time[0];
   ArrayInitialize(g_dt1, 0.0); ArrayInitialize(g_dt2, 0.0);
   ArrayInitialize(g_dt3l, 0.0); ArrayInitialize(g_dt3s, 0.0);
   ResetLastError();
   g_boxCount = 0;

   double atrD = iATR(_Symbol, PERIOD_D1, InpAtrPeriod, 1);
   if(atrD <= 0)
   {
      DrawNote("TaylorCycle: waiting for daily ATR data (no tick yet?)...");
      return 0;
   }
   double prevH = iHigh(_Symbol, PERIOD_D1, 1);
   double prevL = iLow(_Symbol, PERIOD_D1, 1);
   double prevC = iClose(_Symbol, PERIOD_D1, 1);

   //--- today's pre-open label + score
   bool isBuy, isShort, isSell, isSuper;
   DayLabel(1, isBuy, isShort, isSell, isSuper);
   bool tom = IsToMKey(nowKey);
   bool preM = IsPreMacroKey(nowKey);
   bool macT = IsMacroKey(nowKey);
   double h52r, h52rec, h52px, sret, sz;
   bool has52 = H52Stats(h52r, h52rec, h52px);
   bool hasSe = SeasonalStats(sret, sz);
   int sLead = (has52 && hasSe && h52r >= InpMinH52 && h52rec >= InpMinRec && sz > 0) ? 1 : 0;
   int score = (tom ? 1 : 0) + (preM ? 1 : 0) + sLead;

   //--- scan last N ET-days for history arrows + boxes (skip forming bar 0)
   int minKey = nowKey - InpHistoryDays - 2;
   // series arrays: index rates_total-1 = oldest. find oldest bar in range:
   int j = rates_total - 1;
   while(j >= 1 && BarETKey(time[j], etSh) < minKey) j--;
   int rangeOldest = j;
   if(rangeOldest < 1)
      DrawNote("TaylorCycle: chart data stale/offline (no bars in scan range) - check connection");
   int b0key = BarETKey(time[0], etSh);
   int b0mm = ETMinutes(time[0], etSh);
   int dk = -1, dFirst = -1, dLast = -1;
   for(int b = rangeOldest; b >= 1; b--)
   {
      int key = BarETKey(time[b], etSh);
      if(key != dk)
      {
         if(dk != -1) ProcessDay(dFirst, dLast, dk, nowKey, time, open, high, low, close, etSh,
                                 atrD, b0key, b0mm, score);
         dk = key; dFirst = b; dLast = b;
      }
      else dLast = b;
      if(b == 1) // finalize newest day
         ProcessDay(dFirst, dLast, dk, nowKey, time, open, high, low, close, etSh,
                    atrD, b0key, b0mm, score);
   }
   if(InpShowDayBoxes) PruneDayObjects(minKey);

   //--- prev H/L lines
   if(InpShowPrevHL)
   {
      UpsertHLine("PH", prevH, clrSteelBlue, STYLE_DASH, 1, "Prev H " + DoubleToString(prevH, _Digits));
      UpsertHLine("PL", prevL, clrSteelBlue, STYLE_DASH, 1, "Prev L " + DoubleToString(prevL, _Digits));
   }
   else { DeleteIfExists("PH"); DeleteIfExists("PL"); }
   if(InpShow52WLine && has52)
      UpsertHLine("H52", h52px, clrDarkOrange, STYLE_DOT, 1, "52W " + DoubleToString(h52px, _Digits));
   else DeleteIfExists("H52");

   g_lastErr = GetLastError();
   DrawDashboard(nowKey, nowMin, isBuy, isShort, isSell, isSuper, tom, preM, macT,
                 prevH, prevL, prevC, atrD, h52r, h52rec, has52, sret, sz, hasSe,
                 score, time, open, high, low, close, etSh);
   static int dbgDay = -99;
   if(InpDebug && nowKey != dbgDay)
   {
      dbgDay = nowKey;
      Print(StringFormat("TaylorCycle: bars=%d D1=%d atrD=%s etSh=%dh label=%s score=%d boxes=%d err=%d",
         rates_total, Bars(_Symbol, PERIOD_D1), DoubleToString(atrD, _Digits), etSh / 3600,
         (isSuper ? "SUPER" : (isBuy ? "BUY" : (isShort ? "SHORT" : (isSell ? "SELL" : "NONE")))),
         score, g_boxCount, g_lastErr));
   }
   return rates_total;
}

//+------------------------------------------------------------------+
//| Per-day processing: label, triggers, arrows, boxes, lines        |
//+------------------------------------------------------------------+
void ProcessDay(int dFirst, int dLast, int key, int nowKey,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], int etSh,
                double atrD, int b0key, int b0mm, int scoreNow)
{
   // dFirst = oldest bar index of day (highest index), dLast = newest (lowest)
   // collect session bars ET 9:30..16:00
   int f0 = -1, f1 = -1; // first-90m range (oldest..newest indices)
   int maxMM = -1;
   double fLow = 0, fHigh = 0, sessOpen = 0;
   bool haveF = false;
   double dHigh = -1.0, dLow = 1e12;
   datetime tFirst = 0, tLast = 0;
   for(int b = dFirst; b >= dLast; b--)
   {
      int mm = ETMinutes(time[b], etSh);
      if(mm < 570 || mm > 960) continue; // 9:30..16:00 ET
      if(mm > maxMM) maxMM = mm;
      if(tFirst == 0) tFirst = time[b];
      tLast = time[b];
      if(sessOpen == 0) sessOpen = open[b];
      if(high[b] > dHigh) dHigh = high[b];
      if(low[b] < dLow) dLow = low[b];
      if(mm < 660) // 9:30..11:00
      {
         if(!haveF) { fLow = low[b]; fHigh = high[b]; haveF = true; f0 = b; }
         else { if(low[b] < fLow) fLow = low[b]; if(high[b] > fHigh) fHigh = high[b]; }
         f1 = b;
      }
   }
   if(!haveF || tFirst == 0) return;
   double entryPx = close[f1]; // close of last first-90m bar (tradable)

   //--- historical label for this day via D1 shift
   int dsh = iBarShift(_Symbol, PERIOD_D1, tFirst, false);
   bool isBuy = false, isShort = false, isSell = false, isSuper = false;
   double atrRef = atrD;
   bool isToday = (key == nowKey);
   if(isToday)
      DayLabel(1, isBuy, isShort, isSell, isSuper); // live day: pre-open label
   else if(dsh >= 1 && dsh + 8 < Bars(_Symbol, PERIOD_D1))
   {
      DayLabel(dsh + 1, isBuy, isShort, isSell, isSuper);
      double a = iATR(_Symbol, PERIOD_D1, InpAtrPeriod, dsh + 1);
      if(a > 0) atrRef = a;
   }
   bool dayTom = IsToMKey(key);
   bool dayPreM = IsPreMacroKey(key);
   bool dayMac = IsMacroKey(key);

   //--- triggers (tradable at f1 close)
   double off = iATR(_Symbol, 0, 14, f1);
   if(off <= 0) off = (dHigh - dLow) * 0.15;
   off *= 0.4;
   bool dipped = (fLow < sessOpen);
   bool rallied = (fHigh > sessOpen);
   bool reclaim = (entryPx > fLow + InpReclaimAtr * atrRef);
   bool reject = (entryPx < fHigh - InpReclaimAtr * atrRef);
   bool windowDone = (maxMM >= 660) || (key == b0key && b0mm >= 660);
   bool trigL = (windowDone && isBuy && dipped && reclaim && !isSuper);
   bool trigS = (windowDone && isShort && rallied && reject && !isSuper);
   if(trigL) g_dt1[f1] = low[f1] - off;
   if(trigS) g_dt2[f1] = high[f1] + off;
   //--- DT3 gap fade
   if(InpUseGapFade && (isToday || dsh >= 1))
   {
      double pc = isToday ? iClose(_Symbol, PERIOD_D1, 1) : iClose(_Symbol, PERIOD_D1, dsh + 1);
      if(pc > 0)
      {
         double gap = (sessOpen / pc - 1.0) / (atrRef / pc);
         int b930 = -1;
         for(int b = dFirst; b >= dLast; b--)
         {
            int mm = ETMinutes(time[b], etSh);
            if(mm >= 570 && mm < 570 + Period()) { b930 = b; break; }
         }
         if(b930 > 0)
         {
            if(gap > InpGapFadeAtr) g_dt3s[b930] = high[b930] + off;
            else if(gap < -InpGapFadeAtr) g_dt3l[b930] = low[b930] - off;
         }
      }
   }

   //--- day box + tag
   if(InpShowDayBoxes)
   {
      color bc = isSuper ? C'40,40,40' : (isBuy ? InpBuyColor : (isShort ? InpShortColor : (isSell ? InpSellColor : C'35,35,35')));
      UpsertDayBox(key, tFirst, tLast, dHigh, dLow, bc, dayTom);
      string tag = "";
      if(dayTom) tag += "ToM ";
      if(dayMac) tag += "MACRO ";
      else if(dayPreM) tag += "PRE ";
      if(isBuy) tag += "BUY";
      else if(isShort) tag += "SHORT";
      else if(isSell) tag += "SELL";
      else if(isSuper) tag += "SUPER";
      if(tag != "") UpsertDayTag(key, tFirst, dHigh, tag, dayTom ? InpTomColor : clrSilver);
   }

   //--- today: entry/stop/tp lines + alerts
   if(isToday)
   {
      int mmNow = ETMinutes(TimeCurrent(), etSh);
      bool live = (mmNow >= 570 && mmNow < 960);
      // state needs trigger bar closed: current forming bar must be newer than f1
      bool f1Closed = (f1 > 0);
      if((trigL || trigS) && f1Closed && live)
      {
         double stop = trigL ? entryPx - InpStopAtr * atrRef : entryPx + InpStopAtr * atrRef;
         double tp1 = trigL ? entryPx + InpStopAtr * atrRef : entryPx - InpStopAtr * atrRef;
         UpsertHLine("ENTRY", entryPx, trigL ? clrDodgerBlue : clrOrange, STYLE_SOLID, 2,
                     (trigL ? "DT1 LONG " : "DT2 SHORT ") + DoubleToString(entryPx, _Digits));
         UpsertHLine("STOP", stop, clrRed, STYLE_DASHDOT, 1, "STOP " + DoubleToString(stop, _Digits));
         UpsertHLine("TP1", tp1, clrLimeGreen, STYLE_DASHDOT, 1, "TP +0.5ATR " + DoubleToString(tp1, _Digits));
         string tag = trigL ? "DT1" : "DT2";
         FireAlert(tag, StringFormat("%s %s %s @ %s (stop %s, score %d)",
                     _Symbol, TFName(), tag,
                     DoubleToString(entryPx, _Digits), DoubleToString(stop, _Digits), scoreNow), key);
      }
      else { DeleteIfExists("ENTRY"); DeleteIfExists("STOP"); DeleteIfExists("TP1"); }
   }
}

//+------------------------------------------------------------------+
//| Per-tick refresh: clock/session + setup rows only (no redraw)    |
//+------------------------------------------------------------------+
void UpdateLiveRows(int nowKey, int nowMin, const datetime &time[], int etSh)
{
   if(!InpShowDashboard) return;
   int y, m, d; KeyToDate(nowKey, y, m, d);
   int hh = nowMin / 60, mm = nowMin % 60;
   bool macT = IsMacroKey(nowKey);
   string sess = "WAIT"; color sessC = clrGray;
   if(macT) { sess = "MACRO DAY-BLACKOUT"; sessC = clrRed; }
   else if(nowMin >= 570 && nowMin < 600) { sess = "OPEN DRIVE"; sessC = clrYellow; }
   else if(nowMin >= 600 && nowMin < 690) { sess = "AM CONFIRM"; sessC = clrAqua; }
   else if(nowMin >= 690 && nowMin < 840) { sess = "DEAD ZONE-NO ENTRY"; sessC = clrGray; }
   else if(nowMin >= 840 && nowMin < 930) { sess = "TAYLOR MOVE"; sessC = clrLime; }
   else if(nowMin >= 930 && nowMin < 958) { sess = "CLOSE ONLY-FLAT 15:58"; sessC = clrOrange; }
   string st = "WAITING 9:30 ET", tag = "";
   for(int b = 1; b < MathMin(300, Bars(_Symbol, _Period)); b++)
   {
      if(BarETKey(time[b], etSh) != nowKey) { if(BarETKey(time[b], etSh) < nowKey) break; else continue; }
      if(g_dt1[b] > 0) { tag = "DT1"; break; }
      if(g_dt2[b] > 0) { tag = "DT2"; break; }
   }
   if(tag == "DT1") st = "TRIGGERED LONG (see ENTRY line)";
   else if(tag == "DT2") st = "TRIGGERED SHORT (see ENTRY line)";
   else if(nowMin >= 690) st = "NO TRIGGER - window passed";
   else if(nowMin >= 570) st = "ARMED - trigger @11:00 ET bar";
   int lh = InpFontSize + 8, x0 = 8;
   MkLabel("D1", x0 + 1 * lh, StringFormat("ET %04d.%02d.%02d %02d:%02d  |  %s", y, m, d, hh, mm, sess), sessC);
   MkLabel("D8", x0 + 8 * lh, "SETUP: " + st, (tag != "" ? clrYellow : clrSilver));
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void DrawDashboard(int nowKey, int nowMin,
                   bool isBuy, bool isShort, bool isSell, bool isSuper,
                   bool tom, bool preM, bool macT,
                   double prevH, double prevL, double prevC, double atrD,
                   double h52r, double h52rec, bool has52,
                   double sret, double sz, bool hasSe, int score,
                   const datetime &time[], const double &open[], const double &high[],
                   const double &low[], const double &close[], int etSh)
{
   if(!InpShowDashboard)
   {
      for(int r = 0; r < 14; r++) DeleteIfExists("D" + IntegerToString(r));
      DeleteIfExists("DBG");
      return;
   }
   int y, m, d; KeyToDate(nowKey, y, m, d);
   int hh = nowMin / 60, mm = nowMin % 60;
   string sess = "WAIT";
   color sessC = clrGray;
   if(macT) { sess = "MACRO DAY-BLACKOUT"; sessC = clrRed; }
   else if(nowMin >= 570 && nowMin < 600) { sess = "OPEN DRIVE"; sessC = clrYellow; }
   else if(nowMin >= 600 && nowMin < 690) { sess = "AM CONFIRM"; sessC = clrAqua; }
   else if(nowMin >= 690 && nowMin < 840) { sess = "DEAD ZONE-NO ENTRY"; sessC = clrGray; }
   else if(nowMin >= 840 && nowMin < 930) { sess = "TAYLOR MOVE"; sessC = clrLime; }
   else if(nowMin >= 930 && nowMin < 958) { sess = "CLOSE ONLY-FLAT 15:58"; sessC = clrOrange; }

   string dayS = "NO EDGE"; color dayC = clrSilver;
   if(isSuper) { dayS = "SUPER-TREND: NO FADES"; dayC = clrRed; }
   else if(isBuy) { dayS = "BUY DAY: dip-buy bias"; dayC = clrLimeGreen; }
   else if(isShort) { dayS = "SHORT DAY: fade bias"; dayC = clrOrangeRed; }
   else if(isSell) { dayS = "SELL DAY: range-fade"; dayC = clrSilver; }

   double liveO = iOpen(_Symbol, PERIOD_D1, 0);
   double gapA = (prevC > 0 && atrD > 0) ? (liveO / prevC - 1.0) / (atrD / prevC) : 0;
   double cp = DayClosePos(1);
   double penL = (atrD > 0) ? (iLow(_Symbol, PERIOD_D1, 2) - iLow(_Symbol, PERIOD_D1, 1)) / atrD : 0;
   bool viol = (penL > InpViolationPen && cp < InpViolationCP);
   double q = 55.0 * cp + (!viol ? 20.0 : 0.0) + ((penL > 0 && cp >= 0.5) ? 10.0 : 0.0) + 5.0;

   string cal = "";
   if(tom) cal += "ToM ";
   if(macT) cal += "MACRO-TODAY ";
   else if(preM) cal += "PRE-MACRO ";
   if(cal == "") cal = "-";

   // setup state today
   string st = "WAITING 9:30 ET", tag = "";
   // find today's trigger state from buffers (last 200 bars)
   for(int b = 1; b < MathMin(300, Bars(_Symbol, _Period)); b++)
   {
      if(BarETKey(time[b], etSh) != nowKey) { if(BarETKey(time[b], etSh) < nowKey) break; else continue; }
      if(g_dt1[b] > 0) { tag = "DT1"; break; }
      if(g_dt2[b] > 0) { tag = "DT2"; break; }
   }
   if(tag == "DT1") st = "TRIGGERED LONG (see ENTRY line)";
   else if(tag == "DT2") st = "TRIGGERED SHORT (see ENTRY line)";
   else if(nowMin >= 690) st = "NO TRIGGER - window passed";
   else if(nowMin >= 570) st = "ARMED - trigger @11:00 ET bar";

   int lh = InpFontSize + 8, x0 = 8;
   if(ObjectFind(0, PREF + "DBG") < 0)
      ObjectCreate(0, PREF + "DBG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_CORNER, InpCorner);
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_XDISTANCE, 4);
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_YDISTANCE, 4);
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_XSIZE, 340);
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_YSIZE, lh * 14 + 12);
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_BGCOLOR, C'16,16,16');
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_BACK, false);
   ObjectSetInteger(0, PREF + "DBG", OBJPROP_SELECTABLE, false);

   int r = 0;
   MkLabel("D" + IntegerToString(r++), x0 + 0 * lh, "TAYLOR CYCLE v2.02 " + _Symbol + "  " + TFName(), clrGold);
   MkLabel("D" + IntegerToString(r++), x0 + 1 * lh, StringFormat("ET %04d.%02d.%02d %02d:%02d  |  %s", y, m, d, hh, mm, sess), sessC);
   MkLabel("D" + IntegerToString(r++), x0 + 2 * lh, "DAY: " + dayS, dayC);
   MkLabel("D" + IntegerToString(r++), x0 + 3 * lh, "CAL: " + cal + "   SCORE: " + IntegerToString(score) + "/3", tom || preM ? clrGold : clrSilver);
   MkLabel("D" + IntegerToString(r++), x0 + 4 * lh, StringFormat("Prev H/L: %s / %s  Gap: %+.2f ATR",
            DoubleToString(prevH, _Digits), DoubleToString(prevL, _Digits), gapA), MathAbs(gapA) > InpGapFadeAtr ? clrYellow : clrSilver);
   MkLabel("D" + IntegerToString(r++), x0 + 5 * lh, StringFormat("ATR14: %s  Stop0.5: %d pts  Yday CP: %.2f%s",
            DoubleToString(atrD, _Digits), (int)(InpStopAtr * atrD / _Point), cp, viol ? " VIOLATION" : ""), viol ? clrRed : clrSilver);
   string lead = (!has52 && !hasSe) ? "leadership: n/a (need history)" :
      StringFormat("52W: %s rec %s  seas z: %s",
         has52 ? DoubleToString(h52r, 3) : "n/a", has52 ? DoubleToString(h52rec, 2) : "n/a",
         hasSe ? DoubleToString(sz, 2) : "n/a");
   MkLabel("D" + IntegerToString(r++), x0 + 6 * lh, lead, sLeadColor(has52, hasSe, h52r, h52rec, sz));
   MkLabel("D" + IntegerToString(r++), x0 + 7 * lh, StringFormat("Quality(yday base): %.0f/100  (close_pos x55 + no-viol x20 + fail x10)",
            MathMin(q, 100.0)), clrSilver);
   MkLabel("D" + IntegerToString(r++), x0 + 8 * lh, "SETUP: " + st, (tag != "" ? clrYellow : clrSilver));
   MkLabel("D" + IntegerToString(r++), x0 + 9 * lh, "ENTRY/STOP/TP lines plot on trigger (EOD exit, flat 15:58)", clrGray);
   MkLabel("D" + IntegerToString(r++), x0 + 10 * lh, "Risk: 0.25-0.5%/trade  Daily stop 1-1.5%  Max 3/day", clrGray);
   MkLabel("D" + IntegerToString(r++), x0 + 11 * lh, "Edu research - not financial advice. See MT4_GUIDE.md", clrDimGray);
   MkLabel("D" + IntegerToString(r++), x0 + 12 * lh, StringFormat("DBG bars=%d D1=%d etSh=%dh boxes=%d err=%d",
            Bars(_Symbol, _Period), Bars(_Symbol, PERIOD_D1), ETShiftSeconds() / 3600,
            g_boxCount, g_lastErr), clrDimGray);
}
color sLeadColor(bool has52, bool hasSe, double h52r, double h52rec, double sz)
{
   if(has52 && hasSe && h52r >= InpMinH52 && h52rec >= InpMinRec && sz > 0) return clrLimeGreen;
   return clrSilver;
}
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
   return "T" + IntegerToString(_Period);
}
//+------------------------------------------------------------------+
