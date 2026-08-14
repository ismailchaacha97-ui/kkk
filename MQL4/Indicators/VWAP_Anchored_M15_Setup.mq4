//+------------------------------------------------------------------+
//|                                    VWAP_Anchored_M15_Setup.mq4   |
//|  Session-anchored VWAP computed on M15 data, drawn on any chart  |
//|  (designed for a 5-minute chart) + Long / Short pullback setups. |
//|                                                                  |
//|  LONG SETUP                                                      |
//|    1. Price is above VWAP                                        |
//|    2. VWAP is rising over the last 15 minutes (1 M15 bar)        |
//|    3. Price is up >= +0.1% over the last hour (4 x M15 bars)     |
//|    4. TRIGGER: first RED candle pulling back toward VWAP ->      |
//|       buy at the OPEN of the next bar                            |
//|                                                                  |
//|  SHORT SETUP  (mirror image, first GREEN pullback candle)        |
//|                                                                  |
//|  No signals during the first hour after the anchor (market open) |
//|  so that the VWAP has time to establish itself.                  |
//+------------------------------------------------------------------+
#property copyright "Arena.ai"
#property link      ""
#property version   "1.00"
#property strict

#property indicator_chart_window
#property indicator_buffers 3
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2
#property indicator_color2  clrLime
#property indicator_width2  2
#property indicator_color3  clrRed
#property indicator_width3  2

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string  __anchor__            = "----- VWAP anchor (market open) -----";
input int     AnchorHour            = 9;      // Market open hour (broker/server time)
input int     AnchorMinute          = 30;     // Market open minute (server time)
input bool    AnchorEveryDay        = true;   // Re-anchor VWAP at every session open
input ENUM_APPLIED_PRICE VwapPrice  = PRICE_TYPICAL; // Price used for VWAP ((H+L+C)/3 = typical)

input string  __calc__              = "----- Calculation -----";
input ENUM_TIMEFRAMES CalcTimeframe = PERIOD_M15; // Timeframe VWAP + conditions are computed on
input ENUM_TIMEFRAMES TriggerTF     = PERIOD_CURRENT; // Timeframe of the trigger candle (chart TF = M5)
input int     MaxBarsBack           = 3000;   // Max chart bars to process

input string  __filters__           = "----- Setup filters -----";
input int     VwapSlopeBars         = 1;      // VWAP slope lookback in CalcTimeframe bars (1 = 15 min)
input int     MomentumBars          = 4;      // Momentum lookback in CalcTimeframe bars (4 = 1 hour)
input double  MomentumPercent       = 0.10;   // Required move over that period, in % (0.10 = 0.1%)
input bool    RequireCloserToVwap   = true;   // Trigger candle must move back toward VWAP
input double  MaxDistanceVwapPct    = 0.0;    // Max distance price-VWAP in % (0 = off)
input int     NoTradeMinutes        = 60;     // No signals in the first N minutes after the anchor
input int     SessionMinutes        = 0;      // Length of the tradable session in minutes (0 = no limit)

input string  __alerts__            = "----- Alerts -----";
input bool    ShowArrows            = true;
input bool    ShowVwapLabel         = true;
input bool    AlertPopup            = false;
input bool    AlertPush             = false;
input string  ArrowPrefix           = "VWAPSig_";

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double VwapBuf[];
double LongBuf[];
double ShortBuf[];

//--- CalcTimeframe VWAP cache
double   CalcVwap[];      // index = shift on CalcTimeframe
datetime CalcTime[];
int      CalcCount = 0;

datetime g_lastAlertBar = 0;
string   g_labelName;

//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorBuffers(3);

   SetIndexBuffer(0, VwapBuf);
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 2, clrDodgerBlue);
   SetIndexLabel(0, "VWAP (" + TfToStr(CalcTf()) + " anchored)");

   SetIndexBuffer(1, LongBuf);
   SetIndexStyle(1, DRAW_ARROW, EMPTY, 2, clrLime);
   SetIndexArrow(1, 233);   // up arrow
   SetIndexLabel(1, "Long entry");

   SetIndexBuffer(2, ShortBuf);
   SetIndexStyle(2, DRAW_ARROW, EMPTY, 2, clrRed);
   SetIndexArrow(2, 234);   // down arrow
   SetIndexLabel(2, "Short entry");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);

   IndicatorShortName("VWAP anchored " + TfToStr(CalcTf()) +
                      " @ " + StringFormat("%02d:%02d", AnchorHour, AnchorMinute));

   g_labelName = ArrowPrefix + "label";
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string nm = ObjectName(i);
      if(StringFind(nm, ArrowPrefix) == 0)
         ObjectDelete(nm);
     }
   Comment("");
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES CalcTf()
  {
   return(CalcTimeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : CalcTimeframe);
  }

ENUM_TIMEFRAMES TrigTf()
  {
   return(TriggerTF == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : TriggerTF);
  }

string TfToStr(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
     }
   return("TF" + IntegerToString((int)tf));
  }

//--- Session id: bars belonging to the same "market day" share the same id
long SessionId(datetime t)
  {
   if(!AnchorEveryDay)
      return(0);
   long anchorSec = (long)AnchorHour * 3600 + (long)AnchorMinute * 60;
   return((long)((t - anchorSec) / 86400));
  }

datetime SessionStart(datetime t)
  {
   long anchorSec = (long)AnchorHour * 3600 + (long)AnchorMinute * 60;
   long day = (long)((t - anchorSec) / 86400);
   return((datetime)(day * 86400 + anchorSec));
  }

int MinutesIntoSession(datetime t)
  {
   return((int)((t - SessionStart(t)) / 60));
  }

double AppliedPriceOf(ENUM_TIMEFRAMES tf, int shift)
  {
   double o = iOpen(NULL, tf, shift);
   double h = iHigh(NULL, tf, shift);
   double l = iLow(NULL, tf, shift);
   double c = iClose(NULL, tf, shift);
   switch(VwapPrice)
     {
      case PRICE_CLOSE:    return(c);
      case PRICE_OPEN:     return(o);
      case PRICE_HIGH:     return(h);
      case PRICE_LOW:      return(l);
      case PRICE_MEDIAN:   return((h + l) / 2.0);
      case PRICE_TYPICAL:  return((h + l + c) / 3.0);
      case PRICE_WEIGHTED: return((h + l + 2 * c) / 4.0);
     }
   return((h + l + c) / 3.0);
  }

//+------------------------------------------------------------------+
//| Build the anchored VWAP on the calculation timeframe             |
//+------------------------------------------------------------------+
bool BuildCalcVwap(int neededBars)
  {
   ENUM_TIMEFRAMES tf = CalcTf();
   int total = iBars(NULL, tf);
   if(total < 5)
      return(false);

   int n = MathMin(total, neededBars + MomentumBars + VwapSlopeBars + 10);
   if(ArraySize(CalcVwap) != n)
     {
      ArrayResize(CalcVwap, n);
      ArrayResize(CalcTime, n);
     }
   CalcCount = n;

   double cumPV = 0.0, cumV = 0.0;
   long   curSession = -9223372036854775807;

   //--- walk from the oldest bar forward so cumulative sums are correct
   for(int s = n - 1; s >= 0; s--)
     {
      datetime bt = iTime(NULL, tf, s);
      long sid = SessionId(bt);
      if(sid != curSession)
        {
         curSession = sid;
         cumPV = 0.0;
         cumV  = 0.0;
        }
      double vol = (double)iVolume(NULL, tf, s);
      if(vol <= 0.0)
         vol = 1.0;
      cumPV += AppliedPriceOf(tf, s) * vol;
      cumV  += vol;

      CalcVwap[s] = (cumV > 0.0 ? cumPV / cumV : EMPTY_VALUE);
      CalcTime[s] = bt;
     }
   return(true);
  }

//--- VWAP value at the calc-timeframe bar that contains time t
double VwapAt(datetime t)
  {
   int s = iBarShift(NULL, CalcTf(), t, false);
   if(s < 0 || s >= CalcCount)
      return(EMPTY_VALUE);
   return(CalcVwap[s]);
  }

//+------------------------------------------------------------------+
//| Setup conditions evaluated on the calc timeframe                 |
//| dir: +1 long context, -1 short context                           |
//+------------------------------------------------------------------+
bool ContextOk(datetime t, int dir, double &vwapOut)
  {
   ENUM_TIMEFRAMES tf = CalcTf();
   int s = iBarShift(NULL, tf, t, false);
   if(s < 0 || s + MomentumBars + VwapSlopeBars >= CalcCount)
      return(false);

   double vwap = CalcVwap[s];
   double vwapPrev = CalcVwap[s + VwapSlopeBars];
   if(vwap == EMPTY_VALUE || vwapPrev == EMPTY_VALUE)
      return(false);
   vwapOut = vwap;

   //--- same session for the slope / momentum lookback (no cross-session compare)
   if(SessionId(CalcTime[s]) != SessionId(CalcTime[s + VwapSlopeBars]))
      return(false);

   double cNow  = iClose(NULL, tf, s);
   double cPast = iClose(NULL, tf, s + MomentumBars);
   if(cPast <= 0.0)
      return(false);
   double chgPct = (cNow - cPast) / cPast * 100.0;

   if(dir > 0)
     {
      if(!(vwap > vwapPrev))            return(false);   // VWAP rising
      if(!(chgPct >= MomentumPercent))  return(false);   // +0.1% over the hour
     }
   else
     {
      if(!(vwap < vwapPrev))            return(false);   // VWAP falling
      if(!(chgPct <= -MomentumPercent)) return(false);   // -0.1% over the hour
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Main calculation                                                 |
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
   int limit = MathMin(rates_total - 1, MaxBarsBack);
   if(limit < 10)
      return(0);

   if(!BuildCalcVwap(limit * (PeriodSeconds((ENUM_TIMEFRAMES)Period()) / MathMax(1, PeriodSeconds(CalcTf()))) + 100))
      return(0);

   ArrayInitialize(LongBuf, EMPTY_VALUE);
   ArrayInitialize(ShortBuf, EMPTY_VALUE);

   //--- 1) VWAP line on the chart timeframe
   for(int i = limit; i >= 0; i--)
     {
      double v = VwapAt(time[i]);
      VwapBuf[i] = (v == EMPTY_VALUE ? EMPTY_VALUE : v);
     }
   for(int i = rates_total - 1; i > limit; i--)
      VwapBuf[i] = EMPTY_VALUE;

   //--- 2) signals on the trigger timeframe, drawn on the chart
   ENUM_TIMEFRAMES ttf = TrigTf();
   int tTotal = iBars(NULL, ttf);
   int tScan  = MathMin(tTotal - MomentumBars - 3,
                        (int)(limit * (double)PeriodSeconds((ENUM_TIMEFRAMES)Period()) / PeriodSeconds(ttf)) + 2);
   if(tScan < 5)
      return(rates_total);

   datetime lastSignalTime = 0;
   int lastSignalDir = 0;

   for(int s = tScan; s >= 1; s--)   // s = trigger candle (closed), entry on bar s-1
     {
      datetime tTrig  = iTime(NULL, ttf, s);
      datetime tEntry = iTime(NULL, ttf, s - 1);
      if(tTrig == 0 || tEntry == 0)
         continue;

      //--- no trading in the first N minutes after the market open
      int mins = MinutesIntoSession(tEntry);
      if(mins < NoTradeMinutes)
         continue;
      if(SessionMinutes > 0 && mins > SessionMinutes)
         continue;
      if(SessionId(tTrig) != SessionId(tEntry))
         continue;

      double o  = iOpen(NULL, ttf, s);
      double c  = iClose(NULL, ttf, s);
      double h  = iHigh(NULL, ttf, s);
      double l  = iLow(NULL, ttf, s);
      double cP = iClose(NULL, ttf, s + 1);
      double oP = iOpen(NULL, ttf, s + 1);
      double entryPrice = iOpen(NULL, ttf, s - 1);

      double vwap = 0.0;
      bool   isRed   = (c < o);
      bool   isGreen = (c > o);
      bool   prevRed   = (cP < oP);
      bool   prevGreen = (cP > oP);

      //================= LONG =================
      if(isRed && !prevRed && ContextOk(tTrig, +1, vwap))
        {
         bool priceAbove = (c > vwap);
         bool closer = (!RequireCloserToVwap) || ((c - vwap) < (cP - vwap));
         bool distOk = (MaxDistanceVwapPct <= 0.0) ||
                       ((l - vwap) / vwap * 100.0 <= MaxDistanceVwapPct);
         if(priceAbove && closer && distOk && entryPrice > vwap)
           {
            PlaceSignal(tEntry, +1, entryPrice, l, lastSignalTime, lastSignalDir);
           }
        }

      //================= SHORT =================
      if(isGreen && !prevGreen && ContextOk(tTrig, -1, vwap))
        {
         bool priceBelow = (c < vwap);
         bool closer = (!RequireCloserToVwap) || ((vwap - c) < (vwap - cP));
         bool distOk = (MaxDistanceVwapPct <= 0.0) ||
                       ((vwap - h) / vwap * 100.0 <= MaxDistanceVwapPct);
         if(priceBelow && closer && distOk && entryPrice < vwap)
           {
            PlaceSignal(tEntry, -1, entryPrice, h, lastSignalTime, lastSignalDir);
           }
        }
     }

   //--- alert on the most recent signal of the freshly closed trigger bar
   if(lastSignalTime > 0 && lastSignalTime != g_lastAlertBar)
     {
      datetime curTrigBar = iTime(NULL, ttf, 0);
      if(lastSignalTime == curTrigBar)
        {
         g_lastAlertBar = lastSignalTime;
         string msg = StringFormat("%s %s: %s VWAP pullback entry @ %s",
                                   Symbol(), TfToStr(ttf),
                                   (lastSignalDir > 0 ? "LONG" : "SHORT"),
                                   DoubleToString(iOpen(NULL, ttf, 0), (int)MarketInfo(Symbol(), MODE_DIGITS)));
         if(AlertPopup) Alert(msg);
         if(AlertPush)  SendNotification(msg);
        }
     }

   if(ShowVwapLabel)
      DrawVwapLabel();

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Store a signal into the chart buffers / objects                  |
//+------------------------------------------------------------------+
void PlaceSignal(datetime entryTime, int dir, double entryPrice, double extreme,
                 datetime &lastSignalTime, int &lastSignalDir)
  {
   int ci = iBarShift(NULL, PERIOD_CURRENT, entryTime, false);
   if(ci < 0)
      return;

   double offset = 6 * Point * MathPow(10, (MarketInfo(Symbol(), MODE_DIGITS) % 2));
   if(dir > 0)
      LongBuf[ci] = iLow(NULL, PERIOD_CURRENT, ci) - offset;
   else
      ShortBuf[ci] = iHigh(NULL, PERIOD_CURRENT, ci) + offset;

   if(ShowArrows)
     {
      string nm = ArrowPrefix + (dir > 0 ? "L_" : "S_") + IntegerToString((int)entryTime);
      if(ObjectFind(nm) < 0)
        {
         ObjectCreate(nm, OBJ_ARROW, 0, entryTime, entryPrice);
         ObjectSet(nm, OBJPROP_ARROWCODE, dir > 0 ? 233 : 234);
         ObjectSet(nm, OBJPROP_COLOR, dir > 0 ? clrLime : clrRed);
         ObjectSet(nm, OBJPROP_WIDTH, 2);
         ObjectSetString(0, nm, OBJPROP_TEXT,
                         (dir > 0 ? "LONG @ " : "SHORT @ ") + DoubleToString(entryPrice, Digits));
        }
     }

   if(entryTime > lastSignalTime)
     {
      lastSignalTime = entryTime;
      lastSignalDir  = dir;
     }
  }

//+------------------------------------------------------------------+
void DrawVwapLabel()
  {
   double v = VwapAt(iTime(NULL, PERIOD_CURRENT, 0));
   if(v == EMPTY_VALUE)
      return;
   string nm = ArrowPrefix + "vwaptxt";
   datetime t = iTime(NULL, PERIOD_CURRENT, 0);
   if(ObjectFind(nm) < 0)
      ObjectCreate(nm, OBJ_TEXT, 0, t, v);
   ObjectMove(nm, 0, t, v);
   ObjectSetString(0, nm, OBJPROP_TEXT, " VWAP " + DoubleToString(v, Digits));
   ObjectSet(nm, OBJPROP_COLOR, clrDodgerBlue);
  }
//+------------------------------------------------------------------+
