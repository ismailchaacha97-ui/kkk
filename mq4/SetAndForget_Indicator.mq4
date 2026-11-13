//+------------------------------------------------------------------+
//|                                    SetAndForget_Indicator.mq4    |
//|      Holy Grail "Set and Forget" Strategy Analyzer  (INDICATOR)  |
//|                                                                  |
//|  This is the INDICATOR build of SetAndForget_EA.mq4. Indicators  |
//|  cannot place orders, so this file contains no trade code at all: |
//|  it only reads the market, draws the 4 Fundamentals on the chart |
//|  and can alert you. YOU enter the trade manually.                |
//|                                                                  |
//|  Why an indicator instead of an EA:                              |
//|    * no AutoTrading / "Allow live trading" dependency            |
//|    * OnCalculate() runs on every price change, and OnInit()      |
//|      redraws immediately when you switch symbol or timeframe      |
//|    * OnTimer() covers the no-tick case (weekend, dead symbol)     |
//|                                                                  |
//|  The 4 Fundamentals:                                             |
//|    1. TREND     - W1 + D1 must agree (EMAs).                     |
//|    2. AOI       - HTF + LTF areas of interest (swing clusters).  |
//|    3. STRUCTURE - Head & Shoulders or Break & Retest on LTF.     |
//|    4. ENTRY     - Engulfing candle on H1/H4 + LTF trend sync.    |
//|                                                                  |
//|  v3.00  indicator conversion of EA v2.11                         |
//|    * OnCalculate() replaces OnTick(); the first calculation      |
//|      forces a scan so the panel appears instantly                |
//|    * throttling uses GetTickCount() - server time can be frozen  |
//|      over the weekend and used to block every rescan              |
//|    * objects are drawn from the indicator, so nothing is lost    |
//|      when you change timeframe (OnInit redraws)                   |
//|    * SendNotification / SendMail keep the terminal quota in mind  |
//|      (max 10 per minute) - the cooldown protects you              |
//+------------------------------------------------------------------+
#property copyright "DeepSeek Harness"
#property link      ""
#property version   "3.20"
#property strict
#property indicator_chart_window
#define SF_VERSION "3.20"   // engine build shown in panel + journal

#property description "Set & Forget (Holy Grail) analyst: trend, AOI, structure, entry. Draws on the chart and alerts only - it cannot trade."

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//| NOTE: MQL4 has no "input group" keyword -> plain string headers. |
//| Same inputs as the EA build, so your presets carry over.         |
//+------------------------------------------------------------------+
input string InpSep1 = "=== 1. TREND (HTF: W1 + D1 in sync) ==="; // ---
input ENUM_TIMEFRAMES InpHTF1 = PERIOD_W1;        // Higher Time Frame 1
input ENUM_TIMEFRAMES InpHTF2 = PERIOD_D1;        // Higher Time Frame 2
input int             InpHTFEMAFast = 20;         // Trend EMA fast
input int             InpHTFEMASlow = 50;         // Trend EMA slow
input int             InpHTFEMATrend = 200;       // Trend EMA filter (0 = off)

input string InpSep2 = "=== 2. AOI (AREAS OF INTEREST) ==="; // ---
input int             InpAOILookback = 500;       // Bars to scan for swings
input int             InpAOISwingLookback = 5;    // Swing pivot strength (bars each side)
input int             InpAOIMinTouches = 2;       // Min touches for a strong AOI
input double          InpAOITolPoints = 0;        // Zone clustering tolerance (0 = auto ATR)
input ENUM_TIMEFRAMES InpLTF1 = PERIOD_H4;        // Lower Time Frame 1
input ENUM_TIMEFRAMES InpLTF2 = PERIOD_H1;        // Lower Time Frame 2
input ENUM_TIMEFRAMES InpLTF3 = PERIOD_M30;       // Lower Time Frame 3

input string InpSep3 = "=== 3. STRUCTURE (H&S / Break & Retest) ==="; // ---
input int             InpStructWindow = 120;      // Bars to scan for structures
input int             InpStructSwingLookback = 4; // Swing lookback for structure
input bool            InpDetectHnS = true;        // Detect Head & Shoulders
input bool            InpDetectBnR = true;        // Detect Break & Retest
input double          InpStructTolPoints = 0;     // Structure tolerance (0 = auto ATR)

input string InpSep4 = "=== 4. ENTRY SIGNAL (Engulfing candle) ==="; // ---
input ENUM_TIMEFRAMES InpEntryTF1 = PERIOD_H1;    // Entry Time Frame 1
input ENUM_TIMEFRAMES InpEntryTF2 = PERIOD_H4;    // Entry Time Frame 2
input bool            InpRequireEngulfing = true; // Require engulfing candle
input int             InpEngulfLookback = 3;      // Closed bars back to check

input string InpSepTrade = "=== 5. STOP LOSS / TAKE PROFIT ==="; // ---
input double          InpRiskReward = 2.0;        // Take profit = RR x stop distance
input double          InpSLBufferATR = 0.5;       // Extra stop buffer (x ATR H1)
input double          InpMaxSLATR = 2.5;          // Max stop distance (x ATR H1, 0 = off)
input double          InpMinRR = 0.0;             // Min reward:risk to show levels (0 = off)
input bool            InpTPAtNextZone = false;    // Cap TP at next opposing HTF zone
input bool            InpDrawTradeLevels = true;  // Draw entry / SL / TP lines

input string InpSepSig = "=== 6. SIGNALS (NO REPAINT) ==="; // ---
input bool            InpBarCloseSignals = true;  // One signal per closed bar only
input bool            InpKeepSignals = true;      // Keep arrows on reload / TF change
input int             InpMaxSignalArrows = 200;   // Max signals kept (arrow + SL/TP)

input string InpSep5 = "=== ALERTS ==="; // ---
input bool            InpAlertPopup = true;       // Show popup alert
input bool            InpAlertSound = true;       // Play sound
input string          InpSoundFile = "alert.wav"; // Alert sound file
input bool            InpAlertPush = false;       // Send push notification
input bool            InpAlertEmail = false;      // Send email
input int             InpAlertCooldownMin = 30;   // Min minutes between same-direction alerts

input string InpSep6 = "=== SCAN ==="; // ---
input int             InpScanEverySeconds = 60;   // Re-scan interval (seconds)
input bool            InpScanAllSymbols = false;  // Scan Market Watch (alerts only, slower)
input bool            InpUseTimer = true;         // Timer refresh (works with zero ticks)

input string InpSep7 = "=== DRAWING / DIAGNOSTICS ==="; // ---
input bool            InpDrawOnChart = true;      // Draw zones / structure on chart
input bool            InpShowPanel = true;        // Show status panel (top-left)
input bool            InpCommentFallback = true;  // Also print status via Comment()
input bool            InpDrawHTFZones = true;     // Draw HTF (W1/D1) levels as dashed lines
input double          InpHTFZoneMult = 4.0;       // HTF zone clustering width (x tolerance)
input color           InpSupplyClr = clrTomato;   // Supply / resistance colour
input color           InpDemandClr = clrDodgerBlue; // Demand / support colour
input color           InpStructClr = clrGold;     // Structure (B&R, H&S) colour
input bool            InpDebugLog = false;        // Verbose journal logging

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
datetime   gLastScanTime   = 0;
uint       gNextScanMs     = 0;   // GetTickCount() based next-scan time (wrap-safe)
datetime   gLastAlertTime  = 0;
int        gLastAlertDir   = 0;   // 1 = buy, -1 = sell, 0 = none
string     gLastSuggestedSymbol = "";
string     gLastSignal     = "";
string     gLastNodata     = "";   // last reported no-data detail

#define SF_MAXSYM 64
string     gSigSym[SF_MAXSYM];     // per-symbol: bar already signalled
datetime   gSigBar[SF_MAXSYM];
int        gSigCount       = 0;

#define SF_MAXSIG 512
datetime   gSigTime[SF_MAXSIG];    // signal bar times, oldest first
int        gSigTimeCount   = 0;
double     gLastSuggestedPrice  = 0;
int        gPanelLines     = 0;


//+------------------------------------------------------------------+
string TFName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H2:  return("H2");
      case PERIOD_H3:  return("H3");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
   }
   return("TF" + IntegerToString((int)tf));
}

//+------------------------------------------------------------------+
//| Pip size (3- and 5-digit quotes are priced in points)            |
//+------------------------------------------------------------------+
double PipSize()
{
   if(Digits == 3 || Digits == 5) return(Point * 10.0);
   return(Point);
}

//+------------------------------------------------------------------+
//| ATR in price units (0 = not enough history)                      |
//+------------------------------------------------------------------+
double GetATR(string symbol, ENUM_TIMEFRAMES tf, int period)
{
   if(period < 2) period = 14;
   double o[], h[], l[], c[];
   int n = Hist(symbol, tf, period + 3, o, h, l, c);
   if(n < period + 2) return(0);

   double sum = 0;
   for(int i = 0; i < period; i++)
   {
      double hl = h[i] - l[i];
      double hc = MathAbs(h[i] - c[i + 1]);
      double lc = MathAbs(l[i] - c[i + 1]);
      sum += MathMax(MathMax(hl, hc), lc);
   }
   return(sum / period);
}

//+------------------------------------------------------------------+
//| Copy OHLC history and return the REAL usable bar count.          |
//| Every loop in this EA is bounded by this value -> no more        |
//| "array out of range" crashes on short history.                   |
//+------------------------------------------------------------------+
int Hist(string symbol, ENUM_TIMEFRAMES tf, int want,
         double &o[], double &h[], double &l[], double &c[])
{
   if(want < 2) want = 2;
   ArraySetAsSeries(o, true);
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(c, true);

   int no = CopyOpen (symbol, tf, 0, want, o);
   int nh = CopyHigh (symbol, tf, 0, want, h);
   int nl = CopyLow  (symbol, tf, 0, want, l);
   int nc = CopyClose(symbol, tf, 0, want, c);

   if(no <= 0 || nh <= 0 || nl <= 0 || nc <= 0) return(0);

   int n = (int)MathMin(MathMin(no, nh), MathMin(nl, nc));
   n = (int)MathMin(n, ArraySize(o));
   n = (int)MathMin(n, ArraySize(h));
   n = (int)MathMin(n, ArraySize(l));
   n = (int)MathMin(n, ArraySize(c));
   if(n < 2) return(0);

   ArrayResize(o, n);
   ArrayResize(h, n);
   ArrayResize(l, n);
   ArrayResize(c, n);
   return(n);
}

//+------------------------------------------------------------------+
//| Manual EMA on a timeframe/symbol (0 = not enough history)        |
//+------------------------------------------------------------------+
double GetEMA(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   if(period <= 0 || shift < 0) return(0);
   int need = period + shift + 2;

   double buf[];
   ArraySetAsSeries(buf, true);
   int copied = CopyClose(symbol, tf, 0, need, buf);

   if(copied < shift + period)
   {
      // While the terminal builds/downloads the series of another timeframe,
      // CopyClose() returns -1 (or fewer bars than exist). Reading the closes
      // straight from the timeseries gets us the data that is already there,
      // instead of leaving the panel on NODATA for minutes.
      ArrayResize(buf, need);
      int last = -1;
      for(int j = 0; j < need; j++)
      {
         buf[j] = iClose(symbol, tf, j);
         if(buf[j] > 0) last = j;
      }
      if(last + 1 < shift + period) return(0);
      copied = last + 1;
   }

   int n = (int)MathMin(copied, ArraySize(buf));
   if(n < shift + period) return(0);           // genuinely not enough bars

   double k   = 2.0 / (period + 1.0);
   int    old = shift + period - 1;            // oldest bar used
   double ema = buf[old];
   for(int i = old - 1; i >= shift; i--)
      ema = buf[i] * k + ema * (1.0 - k);
   return(ema);
}

//+------------------------------------------------------------------+
//| Trend label: "UP" / "DOWN" / "RANGE" / "NODATA"                  |
//+------------------------------------------------------------------+
string TrendLabelEx(string symbol, ENUM_TIMEFRAMES tf, string &why)
{
   why = "";
   if(InpHTFEMAFast <= 0 || InpHTFEMASlow <= 0)
   {
      why = "EMA period is 0 - set Trend EMA fast/slow (e.g. 20 / 50)";
      return("NODATA");
   }

   double price = iClose(symbol, tf, 0);
   if(price <= 0)
   {
      why = StringFormat("%s: no price yet (%d bars)", TFName(tf), iBars(symbol, tf));
      return("NODATA");
   }

   double eFast = GetEMA(symbol, tf, InpHTFEMAFast, 0);
   if(eFast == 0)
   {
      why = StringFormat("%s: EMA%d needs %d bars, have %d",
                         TFName(tf), InpHTFEMAFast, InpHTFEMAFast, iBars(symbol, tf));
      return("NODATA");
   }

   double eSlow = GetEMA(symbol, tf, InpHTFEMASlow, 0);
   if(eSlow == 0)
   {
      why = StringFormat("%s: EMA%d needs %d bars, have %d",
                         TFName(tf), InpHTFEMASlow, InpHTFEMASlow, iBars(symbol, tf));
      return("NODATA");
   }

   int score = 0;
   if(price > eFast) score++; else score--;
   if(eFast > eSlow) score++; else score--;
   if(InpHTFEMATrend > 0)
   {
      double eTrend = GetEMA(symbol, tf, InpHTFEMATrend, 0);
      if(eTrend > 0)
      {
         if(eSlow > eTrend) score++; else score--;
      }
   }
   if(score >= 2)  return("UP");
   if(score <= -2) return("DOWN");
   return("RANGE");
}

string TrendLabel(string symbol, ENUM_TIMEFRAMES tf)
{
   string why = "";
   return(TrendLabelEx(symbol, tf, why));
}

//+------------------------------------------------------------------+
//| Auto tolerance from ATR(14) H1 (fallback = 100 points)           |
//+------------------------------------------------------------------+
double GetTolerance(string symbol, double basePoints)
{
   if(basePoints > 0) return(basePoints * Point);

   double o[], h[], l[], c[];
   int n = Hist(symbol, PERIOD_H1, 20, o, h, l, c);
   if(n < 16) return(100 * Point);

   double trSum = 0;
   int cnt = 0;
   for(int i = 0; i < 14; i++)
   {
      double hl = h[i] - l[i];
      double hc = MathAbs(h[i] - c[i + 1]);
      double lc = MathAbs(l[i] - c[i + 1]);
      trSum += MathMax(MathMax(hl, hc), lc);
      cnt++;
   }
   if(cnt <= 0) return(100 * Point);
   double atr = trSum / (double)cnt;
   if(atr > 0) return(atr * 0.5);
   return(100 * Point);
}

//+------------------------------------------------------------------+
//| Collect swing highs/lows (appends). Returns number added.        |
//+------------------------------------------------------------------+
int CollectSwings(string symbol, ENUM_TIMEFRAMES tf, int lookback, int swingLb,
                  double &highs[], double &lows[])
{
   double o[], h[], l[], c[];
   int n = Hist(symbol, tf, lookback, o, h, l, c);
   if(n < swingLb * 2 + 3) return(0);

   int added = 0;
   for(int i = swingLb; i <= n - swingLb - 1; i++)
   {
      bool isHi = true;
      for(int k = -swingLb; k <= swingLb; k++)
         if(h[i] < h[i + k]) { isHi = false; break; }
      if(isHi && (h[i] > h[i - 1] || h[i] > h[i + 1]))
      {
         int m = ArraySize(highs);
         ArrayResize(highs, m + 1);
         highs[m] = h[i];
         added++;
      }

      bool isLo = true;
      for(int k2 = -swingLb; k2 <= swingLb; k2++)
         if(l[i] > l[i + k2]) { isLo = false; break; }
      if(isLo && (l[i] < l[i - 1] || l[i] < l[i + 1]))
      {
         int m2 = ArraySize(lows);
         ArrayResize(lows, m2 + 1);
         lows[m2] = l[i];
         added++;
      }
   }
   return(added);
}

//+------------------------------------------------------------------+
//| Cluster price levels into zones (sorts vals ascending).          |
//+------------------------------------------------------------------+
int ClusterZones(double &vals[], double tol, double &zl[], int &zc[])
{
   int n = ArraySize(vals);
   ArrayResize(zl, 0);
   ArrayResize(zc, 0);
   if(n == 0) return(0);
   if(tol <= 0) tol = Point;
   ArraySort(vals);

   int gn = 1;
   ArrayResize(zl, 1);
   ArrayResize(zc, 1);
   zl[0] = vals[0];
   zc[0] = 1;
   for(int i = 1; i < n; i++)
   {
      if(vals[i] - zl[gn - 1] <= tol)
      {
         zl[gn - 1] = (zl[gn - 1] * zc[gn - 1] + vals[i]) / (zc[gn - 1] + 1);
         zc[gn - 1]++;
      }
      else
      {
         gn++;
         ArrayResize(zl, gn);
         ArrayResize(zc, gn);
         zl[gn - 1] = vals[i];
         zc[gn - 1] = 1;
      }
   }
   return(gn);
}

//+------------------------------------------------------------------+
//| Nearest zone to price with >= minTouches (0 if none).            |
//+------------------------------------------------------------------+
double NearestZone(double &zl[], int &zc[], double price, double tol,
                   int minTouches, bool supply, int &touches)
{
   double best = 0, bestDist = DBL_MAX;
   touches = 0;
   for(int i = 0; i < ArraySize(zl); i++)
   {
      if(zc[i] < minTouches) continue;
      if(supply  && zl[i] < price - 2.0 * tol) continue;
      if(!supply && zl[i] > price + 2.0 * tol) continue;
      double d = MathAbs(zl[i] - price);
      if(d < bestDist) { bestDist = d; best = zl[i]; touches = zc[i]; }
   }
   return(best);
}

//+------------------------------------------------------------------+
//| Break & Retest. Returns 1 / -1 / 0.                              |
//+------------------------------------------------------------------+
int DetectBreakRetest(string symbol, ENUM_TIMEFRAMES tf, int window, int swingLb, double tol,
                      double &levelPrice, int &levelBar, int &breakBar)
{
   double o[], h[], l[], c[];
   int n = Hist(symbol, tf, window, o, h, l, c);
   if(n < swingLb * 2 + 8) return(0);

   double lastClose = c[0];
   int    look      = swingLb;
   if(look < 1) look = 1;

   int    bestDir = 0;
   int    bestJb  = 2000000000;
   int    bestBar = -1;
   double bestLvl = 0;

   for(int i = look; i <= n - look - 1; i++)
   {
      // ---- swing high -> bullish break & retest ----
      bool isHi = true;
      for(int k = -look; k <= look; k++)
         if(h[i] < h[i + k]) { isHi = false; break; }

      if(isHi)
      {
         double lvl = h[i];
         int jb = -1;
         for(int j = i - 1; j >= 0; j--)          // bars AFTER the swing
            if(c[j] > lvl) { jb = j; break; }

         if(jb >= 1)
         {
            bool retest = false, held = true;
            for(int j = jb - 1; j >= 0; j--)
            {
               if(c[j] < lvl - tol) { held = false; break; }
               if(l[j] <= lvl + tol) retest = true;
            }
            if(held && retest && lastClose > lvl && jb < bestJb)
            { bestJb = jb; bestLvl = lvl; bestDir = 1; bestBar = i; }
         }
      }

      // ---- swing low -> bearish break & retest ----
      bool isLo = true;
      for(int k2 = -look; k2 <= look; k2++)
         if(l[i] > l[i + k2]) { isLo = false; break; }

      if(isLo)
      {
         double lvl2 = l[i];
         int jb2 = -1;
         for(int j2 = i - 1; j2 >= 0; j2--)
            if(c[j2] < lvl2) { jb2 = j2; break; }

         if(jb2 >= 1)
         {
            bool retest2 = false, held2 = true;
            for(int j3 = jb2 - 1; j3 >= 0; j3--)
            {
               if(c[j3] > lvl2 + tol) { held2 = false; break; }
               if(h[j3] >= lvl2 - tol) retest2 = true;
            }
            if(held2 && retest2 && lastClose < lvl2 && jb2 < bestJb)
            { bestJb = jb2; bestLvl = lvl2; bestDir = -1; bestBar = i; }
         }
      }
   }

   if(bestDir != 0)
   {
      levelPrice = bestLvl;
      levelBar   = bestBar;
      breakBar   = bestJb;
      return(bestDir);
   }
   return(0);
}

//+------------------------------------------------------------------+
//| Head & Shoulders / Inverse H&S. 1 = bullish inv H&S, -1 = H&S.   |
//+------------------------------------------------------------------+
int DetectHeadShoulders(string symbol, ENUM_TIMEFRAMES tf, int window, int swingLb, double tol,
                        double &headPrice, double &neckPrice,
                        int &barNew, int &barHead, int &barOld)
{
   double o[], h[], l[], c[];
   int n = Hist(symbol, tf, window, o, h, l, c);
   if(n < swingLb * 2 + 10) return(0);

   double swH[];   int swHB[];
   double swL[];   int swLB[];
   int    swHCnt = 0, swLCnt = 0;
   int    look   = swingLb;
   if(look < 1) look = 1;

   for(int i = look; i <= n - look - 1; i++)
   {
      bool isHi = true;
      for(int k = -look; k <= look; k++)
         if(h[i] < h[i + k]) { isHi = false; break; }
      if(isHi && (h[i] > h[i - 1] || h[i] > h[i + 1]))
      {
         ArrayResize(swH,  swHCnt + 1);
         ArrayResize(swHB, swHCnt + 1);
         swH[swHCnt]  = h[i];
         swHB[swHCnt] = i;
         swHCnt++;
      }

      bool isLo = true;
      for(int k2 = -look; k2 <= look; k2++)
         if(l[i] > l[i + k2]) { isLo = false; break; }
      if(isLo && (l[i] < l[i - 1] || l[i] < l[i + 1]))
      {
         ArrayResize(swL,  swLCnt + 1);
         ArrayResize(swLB, swLCnt + 1);
         swL[swLCnt]  = l[i];
         swLB[swLCnt] = i;
         swLCnt++;
      }
   }

   // swings are ordered newest -> oldest
   // bearish H&S: 3 highs, middle highest, shoulders ~equal
   for(int j = 0; j <= swHCnt - 3; j++)
   {
      double s1 = swH[j], head = swH[j + 1], s2 = swH[j + 2];
      if(head > s1 && head > s2 && MathAbs(s1 - s2) <= tol)
      {
         double neck = l[swHB[j]];
         for(int t = swHB[j]; t <= swHB[j + 2]; t++)
            if(l[t] < neck) neck = l[t];
         headPrice = head;
         neckPrice = neck;
         barNew  = swHB[j];
         barHead = swHB[j + 1];
         barOld  = swHB[j + 2];
         return(-1);
      }
   }

   // bullish inverse H&S: 3 lows, middle lowest, shoulders ~equal
   for(int j2 = 0; j2 <= swLCnt - 3; j2++)
   {
      double s3 = swL[j2], head2 = swL[j2 + 1], s4 = swL[j2 + 2];
      if(head2 < s3 && head2 < s4 && MathAbs(s3 - s4) <= tol)
      {
         double neck2 = h[swLB[j2]];
         for(int t2 = swLB[j2]; t2 <= swLB[j2 + 2]; t2++)
            if(h[t2] > neck2) neck2 = h[t2];
         headPrice = head2;
         neckPrice = neck2;
         barNew  = swLB[j2];
         barHead = swLB[j2 + 1];
         barOld  = swLB[j2 + 2];
         return(1);
      }
   }
   return(0);
}

//+------------------------------------------------------------------+
//| Engulfing on CLOSED bars. 1 = bullish, -1 = bearish, 0 = none.   |
//| (v2.00 indexed one bar past the end of the copied array here,    |
//|  which raised "array out of range" and stopped the EA.)          |
//+------------------------------------------------------------------+
int DetectEngulfing(string symbol, ENUM_TIMEFRAMES tf, int look)
{
   if(look < 1) look = 1;
   double o[], h[], l[], c[];
   int n = Hist(symbol, tf, look + 2, o, h, l, c);
   if(n < 3) return(0);

   int maxK = (int)MathMin(look, n - 2);
   for(int k = 1; k <= maxK; k++)   // k = 0 is the still-forming bar -> skipped
   {
      int cur = k;      // candidate (closed) candle
      int prv = k + 1;  // prior (closed) candle
      bool bull = (c[cur] > o[cur]) && (c[prv] < o[prv]) &&
                  (o[cur] <= c[prv]) && (c[cur] >= o[prv]);
      bool bear = (c[cur] < o[cur]) && (c[prv] > o[prv]) &&
                  (o[cur] >= c[prv]) && (c[cur] <= o[prv]);
      if(bull) return(1);
      if(bear) return(-1);
   }
   return(0);
}

//+------------------------------------------------------------------+
//| Drawing helpers (all objects are prefixed SF_)                   |
//+------------------------------------------------------------------+
datetime ChartRightTime()
{
   datetime t0 = iTime(Symbol(), 0, 0);
   if(t0 <= 0) t0 = TimeCurrent();
   return(t0 + (datetime)(PeriodSeconds() * 25));
}

datetime ChartLeftTime()
{
   int total = iBars(Symbol(), 0);
   int n = 300;
   if(total > 0) n = (int)MathMin(total - 1, 300);
   if(n < 0) n = 0;
   datetime t = iTime(Symbol(), 0, n);
   if(t <= 0) t = ChartRightTime() - (datetime)(PeriodSeconds() * 300);
   return(t);
}

void DrawLine(string name, datetime t1, double p1, datetime t2, double p2,
              color clr, int style, int width)
{
   if(t1 <= 0 || t2 <= 0 || p1 <= 0 || p2 <= 0) return;
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void DrawText(string name, datetime t, double p, string txt, color clr, int size = 8)
{
   if(t <= 0 || p <= 0 || txt == "") return;
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, p)) return;
   ObjectSetString (0, name, OBJPROP_TEXT, txt);
   ObjectSetString (0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawZone(string name, datetime t1, datetime t2, double pTop, double pBot, color clr, string txt)
{
   if(t1 <= 0 || t2 <= 0 || pTop <= 0 || pBot <= 0) return;
   if(pTop < pBot) { double tmp = pTop; pTop = pBot; pBot = tmp; }
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, pTop, t2, pBot))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);   // shaded, candles stay visible
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   // solid borders so the zone is visible even with filled candles
   DrawLine(name + "_B1", t1, pTop, t2, pTop, clr, STYLE_DOT, 1);
   DrawLine(name + "_B2", t1, pBot, t2, pBot, clr, STYLE_DOT, 1);
   DrawText(name + "_T", iTime(Symbol(), 0, 0), pTop, txt, clr, 8);
}

//+------------------------------------------------------------------+
//| Status panel (OBJ_RECTANGLE_LABEL + OBJ_LABEL lines)             |
//+------------------------------------------------------------------+
void PanelLine(int idx, string txt, color clr)
{
   string nm = "SF_PNL_" + IntegerToString(idx);
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetString (0, nm, OBJPROP_FONT, "Consolas");
   }
   ObjectSetString (0, nm, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 16);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 14 + idx * 16);
}

void DrawPanelBackground(int lines, int maxChars)
{
   int w = 24 + maxChars * 7;
   if(w < 220) w = 220;
   if(w > 700) w = 700;
   int h = 16 + lines * 16;

   string nm = "SF_PNL_BG";
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, 8);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, C'22,22,22');
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

//+------------------------------------------------------------------+
//| Signal arrows are pruned so they cannot pile up forever          |
//+------------------------------------------------------------------+
void DeleteSignalObjects(datetime t)
{
   string key = "SF_SIG_" + IntegerToString((int)t) + "_";
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, key) == 0) ObjectDelete(0, nm);
   }
}

//+------------------------------------------------------------------+
//| Keep at most InpMaxSignalArrows signals. Only the oldest record   |
//| is ever removed - never a newer one, so nothing "repaints".       |
//+------------------------------------------------------------------+
void RegisterSignal(datetime t)
{
   int maxKeep = (InpMaxSignalArrows < 1 ? 1 : InpMaxSignalArrows);

   if(gSigTimeCount < SF_MAXSIG)
   {
      gSigTime[gSigTimeCount] = t;
      gSigTimeCount++;
   }
   else
   {
      for(int s = 1; s < SF_MAXSIG; s++) gSigTime[s - 1] = gSigTime[s];
      gSigTime[SF_MAXSIG - 1] = t;
   }

   while(gSigTimeCount > maxKeep)
   {
      datetime oldest = gSigTime[0];
      for(int k = 1; k < gSigTimeCount; k++) gSigTime[k - 1] = gSigTime[k];
      gSigTimeCount--;
      DeleteSignalObjects(oldest);
   }
}

//+------------------------------------------------------------------+
//| Send an alert (indicator: cannot trade, manual entry only)       |
//+------------------------------------------------------------------+
void SendSuggestion(int dir, string symbol, double entry,
                    string reason, string structure, string aoiInfo,
                    double sl, double tp, datetime stampTime)
{
   if(dir == 0) return;
   datetime now = TimeCurrent();
   if(now <= 0) now = TimeLocal();

   // cooldown: don't repeat the same alert (symbol + direction) too often
   if(gLastAlertTime != 0 && now - gLastAlertTime < InpAlertCooldownMin * 60 &&
      gLastAlertDir == dir && gLastSuggestedSymbol == symbol) return;

   string dirStr = (dir == 1 ? "BUY" : "SELL");
   double rr = 0;
   if(sl > 0 && tp > 0 && MathAbs(entry - sl) > 0)
      rr = MathAbs(tp - entry) / MathAbs(entry - sl);

   string msg = StringFormat("SET & FORGET %s SIGNAL | %s | Entry=%.5f", dirStr, symbol, entry);
   if(sl > 0 && tp > 0)
      msg += StringFormat("\nSL=%.5f   TP=%.5f   (RR 1:%.1f, %d/%d pips)",
                          sl, tp, rr,
                          (int)MathRound(MathAbs(entry - sl) / PipSize()),
                          (int)MathRound(MathAbs(tp - entry) / PipSize()));
   msg += "\n" + reason;
   if(structure != "") msg += "\nStructure: " + structure;
   if(aoiInfo != "")   msg += "\nAOI: " + aoiInfo;
   msg += "\nSUGGESTION ONLY - you enter manually. No auto-trading.";

   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound(InpSoundFile);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("Set & Forget " + dirStr + " " + symbol, msg);

   gLastAlertTime       = now;
   gLastAlertDir        = dir;
   gLastSuggestedSymbol = symbol;
   gLastSuggestedPrice  = entry;
   gLastSignal = StringFormat("%s %s @ %.5f", dirStr, symbol, entry);
   if(sl > 0 && tp > 0)
      gLastSignal += StringFormat("  SL %.5f  TP %.5f", sl, tp);
   gLastSignal += "  (" + TimeToString(now, TIME_DATE | TIME_MINUTES) + ")";

   // ---- NON-REPAINTING arrow --------------------------------------
   // Stamped on the last CLOSED bar, with a name derived from that bar time,
   // and only created once. It is never moved and never deleted afterwards,
   // so it cannot repaint.
   if(InpDrawOnChart && symbol == Symbol())
   {
      if(stampTime <= 0) stampTime = iTime(symbol, 0, 0);
      if(stampTime > 0)
      {
         string an = StringFormat("SF_SIG_%d_%s", (int)stampTime, dir == 1 ? "B" : "S");
         color clr = (dir == 1 ? InpDemandClr : InpSupplyClr);
         if(ObjectFind(0, an) < 0)
         {
            if(ObjectCreate(0, an, OBJ_ARROW, 0, stampTime, entry))
            {
               ObjectSetInteger(0, an, OBJPROP_ARROWCODE, dir == 1 ? 233 : 234);
               ObjectSetInteger(0, an, OBJPROP_COLOR, clr);
               ObjectSetInteger(0, an, OBJPROP_WIDTH, 3);
               ObjectSetInteger(0, an, OBJPROP_ANCHOR, dir == 1 ? ANCHOR_TOP : ANCHOR_BOTTOM);
               ObjectSetInteger(0, an, OBJPROP_SELECTABLE, false);
            }
            string txt = dirStr + " " + DoubleToString(entry, Digits);
            if(sl > 0 && tp > 0)
               txt += StringFormat("  SL %s  TP %s",
                                   DoubleToString(sl, Digits), DoubleToString(tp, Digits));
            DrawText(an + "_T", stampTime, entry, txt, clr, 8);

            // SL/TP of THIS signal, anchored to the signal bar: they belong to
            // the record and are never redrawn while later bars form.
            if(sl > 0 && tp > 0)
            {
               datetime tEnd = stampTime + (datetime)(PeriodSeconds(InpEntryTF1) * 120);
               DrawLine(an + "_SL", stampTime, sl, tEnd, sl, clrTomato, STYLE_SOLID, 1);
               DrawLine(an + "_TP", stampTime, tp, tEnd, tp, clrLime, STYLE_SOLID, 1);
            }
            RegisterSignal(stampTime);
         }
      }
   }
   Print(msg);
}

//+------------------------------------------------------------------+
//| Analysis result container                                        |
//+------------------------------------------------------------------+
struct SFResult
{
   bool   ok;                 // history available for the main TFs
   string sym;
   double price;
   string t1, t2;
   bool   htfSync;
   string htfDir;
   int    tradeDir;
   int    ltfSync;
   string l1, l2, l3;
   bool   atAoi;
   string aoiInfo;
   double htfRes, htfSup, ltfRes, ltfSup;
   int    htfResT, htfSupT, ltfResT, ltfSupT;
   double tol;
   double entry, sl, tp, rr;  // trade plan (rr in R multiples)
   int    brDir;
   double brLevel;
   int    brBar;
   int    hsDir;
   double hsHead, hsNeck;
   int    hsNew, hsHeadBar, hsOld;
   int    engDir;
   string engTF;
   bool   ready;
   string reason;
   string structure;
   int    structDir;
   int    barsHTF1, barsHTF2, barsLTF;
   string dataDiag;           // per-TF bar counts, always shown
   string histNote;           // why a timeframe has no data (NODATA)
};

//+------------------------------------------------------------------+
//| Draw zones / structure for one analysis                          |
//+------------------------------------------------------------------+
void DrawAnalysis(SFResult &r)
{
   ObjectsDeleteAll(0, "SF_Z_");
   ObjectsDeleteAll(0, "SF_S_");
   ObjectsDeleteAll(0, "SF_T_");
   if(!InpDrawOnChart || r.sym != Symbol() || r.price <= 0) return;

   datetime tL = ChartLeftTime();
   datetime tR = ChartRightTime();
   double   tol = r.tol;
   if(tol <= 0) tol = Point;

   if(InpDrawHTFZones)
   {
      if(r.htfRes > 0)
      {
         DrawLine("SF_Z_HTFRES", tL, r.htfRes, tR, r.htfRes, InpSupplyClr, STYLE_DASH, 2);
         DrawText("SF_Z_HTFRES_T", iTime(r.sym, 0, 0), r.htfRes,
                  StringFormat("HTF supply %d", r.htfResT), InpSupplyClr);
      }
      if(r.htfSup > 0)
      {
         DrawLine("SF_Z_HTFSUP", tL, r.htfSup, tR, r.htfSup, InpDemandClr, STYLE_DASH, 2);
         DrawText("SF_Z_HTFSUP_T", iTime(r.sym, 0, 0), r.htfSup,
                  StringFormat("HTF demand %d", r.htfSupT), InpDemandClr);
      }
   }

   if(r.ltfRes > 0)
      DrawZone("SF_Z_LTFRES", tL, tR, r.ltfRes + tol * 0.5, r.ltfRes - tol * 0.5,
               InpSupplyClr, StringFormat("LTF supply %d", r.ltfResT));
   if(r.ltfSup > 0)
      DrawZone("SF_Z_LTFSUP", tL, tR, r.ltfSup + tol * 0.5, r.ltfSup - tol * 0.5,
               InpDemandClr, StringFormat("LTF demand %d", r.ltfSupT));

   ENUM_TIMEFRAMES structTF = InpLTF2;

   if(r.brDir != 0 && r.brLevel > 0)
   {
      datetime tb = iTime(r.sym, structTF, r.brBar);
      if(tb <= 0) tb = tL;
      DrawLine("SF_S_BR", tb, r.brLevel, tR, r.brLevel, InpStructClr, STYLE_SOLID, 2);
      DrawText("SF_S_BR_T", iTime(r.sym, 0, 0), r.brLevel,
               r.brDir == 1 ? "B&R bullish" : "B&R bearish", InpStructClr, 9);
   }

   if(r.hsDir != 0 && r.hsHead > 0)
   {
      datetime tOld = iTime(r.sym, structTF, r.hsOld);
      datetime tHd  = iTime(r.sym, structTF, r.hsHeadBar);
      datetime tNw  = iTime(r.sym, structTF, r.hsNew);
      double   pOld = (r.hsDir == -1) ? iHigh(r.sym, structTF, r.hsOld) : iLow(r.sym, structTF, r.hsOld);
      double   pNw  = (r.hsDir == -1) ? iHigh(r.sym, structTF, r.hsNew) : iLow(r.sym, structTF, r.hsNew);
      if(tOld > 0 && tHd > 0 && tNw > 0)
      {
         DrawLine("SF_S_HS1", tOld, pOld, tHd, r.hsHead, InpStructClr, STYLE_SOLID, 2);
         DrawLine("SF_S_HS2", tHd, r.hsHead, tNw, pNw, InpStructClr, STYLE_SOLID, 2);
         DrawLine("SF_S_NECK", tOld, r.hsNeck, tR, r.hsNeck, InpStructClr, STYLE_DASH, 1);
         DrawText("SF_S_HS_T", tHd, r.hsHead, r.hsDir == -1 ? "H&S" : "Inv H&S", InpStructClr, 9);
      }
   }
   if(InpDrawTradeLevels && r.sl > 0 && r.tp > 0)
   {
      datetime tNow = iTime(r.sym, 0, 0);
      DrawLine("SF_T_ENTRY", tL, r.entry, tR, r.entry, clrSilver, STYLE_DOT, 1);
      DrawText("SF_T_ENTRY_T", tNow, r.entry, StringFormat("entry %.5f", r.entry), clrSilver, 8);
      DrawLine("SF_T_SL", tL, r.sl, tR, r.sl, clrTomato, STYLE_SOLID, 2);
      DrawText("SF_T_SL_T", tNow, r.sl, StringFormat("SL %.5f", r.sl), clrTomato, 9);
      DrawLine("SF_T_TP", tL, r.tp, tR, r.tp, clrLime, STYLE_SOLID, 2);
      DrawText("SF_T_TP_T", tNow, r.tp, StringFormat("TP %.5f", r.tp), clrLime, 9);
   }

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw the status panel + optional Comment() text                  |
//+------------------------------------------------------------------+
void DrawStatus(SFResult &r)
{
   string lines[16];
   color  clrs[16];
   int    cnt = 0;

   lines[cnt] = StringFormat("SET & FORGET v%s   %s  %s   %s", SF_VERSION, r.sym,
                             TFName((ENUM_TIMEFRAMES)Period()),
                             TimeToString(TimeCurrent(), TIME_MINUTES));
   clrs[cnt]  = clrWhite; cnt++;

   if(!r.ok)
   {
      lines[cnt] = "History not ready - waiting for bars / download"; clrs[cnt] = clrOrange; cnt++;
      if(r.dataDiag != "")
      {
         lines[cnt] = "Bars       " + r.dataDiag; clrs[cnt] = clrGray; cnt++;
      }
      if(r.histNote != "")
      {
         lines[cnt] = "History    " + r.histNote; clrs[cnt] = clrOrange; cnt++;
      }
      lines[cnt] = "Check: open the W1 + D1 charts once, then re-attach"; clrs[cnt] = clrSilver; cnt++;
   }
   else
   {
      lines[cnt] = StringFormat("Price      %.5f", r.price); clrs[cnt] = clrWhite; cnt++;

      lines[cnt] = StringFormat("Trend      %s:%s  %s:%s  ->  HTF %s",
                                TFName(InpHTF1), r.t1, TFName(InpHTF2), r.t2, r.htfDir);
      if(!r.htfSync)      clrs[cnt] = clrOrange;
      else if(r.htfDir == "UP")   clrs[cnt] = clrLime;
      else if(r.htfDir == "DOWN") clrs[cnt] = clrTomato;
      else                clrs[cnt] = clrSilver;
      cnt++;

      lines[cnt] = StringFormat("LTF        %s:%s  %s:%s  %s:%s  ->  sync %d/3",
                                TFName(InpLTF1), r.l1, TFName(InpLTF2), r.l2,
                                TFName(InpLTF3), r.l3, r.ltfSync);
      clrs[cnt] = (r.ltfSync >= 2 ? clrLime : clrSilver); cnt++;

      lines[cnt] = "AOI        " + (r.atAoi ? r.aoiInfo : "price not at an LTF zone");
      clrs[cnt] = (r.atAoi ? clrAqua : clrSilver); cnt++;

      lines[cnt] = "Structure  " + (r.structure != "" ? r.structure : "none");
      clrs[cnt] = (r.structDir != 0 && r.structDir == r.tradeDir ? clrGold : clrSilver); cnt++;

      lines[cnt] = "Entry      " + (r.engDir == 0
                     ? StringFormat("no engulfing on %s/%s", TFName(InpEntryTF1), TFName(InpEntryTF2))
                     : StringFormat("%s engulfing on %s", r.engDir == 1 ? "bullish" : "bearish", r.engTF));
      clrs[cnt] = (r.engDir != 0 && r.engDir == r.tradeDir ? clrLime : clrSilver); cnt++;

      if(r.sl > 0 && r.tp > 0)
      {
         lines[cnt] = StringFormat("Trade      %s @ %.5f   SL %.5f   TP %.5f   RR 1:%.1f",
                                   r.tradeDir == 1 ? "BUY" : "SELL", r.entry, r.sl, r.tp, r.rr);
         clrs[cnt] = (r.tradeDir == 1 ? clrLime : clrTomato); cnt++;

         lines[cnt] = StringFormat("           %d pips risk  /  %d pips target",
                                   (int)MathRound(MathAbs(r.entry - r.sl) / PipSize()),
                                   (int)MathRound(MathAbs(r.tp - r.entry) / PipSize()));
         clrs[cnt] = clrSilver; cnt++;
      }

      lines[cnt] = r.reason;
      if(r.ready)                                     clrs[cnt] = clrLime;
      else if(StringFind(r.reason, "NO TRADE") == 0)   clrs[cnt] = clrTomato;
      else if(StringFind(r.reason, "WATCH") == 0)      clrs[cnt] = clrGold;
      else                                             clrs[cnt] = clrOrange;
      cnt++;

      if(gLastSignal != "")
      {
         lines[cnt] = "Last       " + gLastSignal; clrs[cnt] = clrSilver; cnt++;
      }

      lines[cnt] = "Bars       " + r.dataDiag;
      clrs[cnt] = clrGray; cnt++;

      if(r.histNote != "")
      {
         lines[cnt] = "History    " + r.histNote;
         clrs[cnt] = clrOrange; cnt++;
      }
   }

   // --- Comment() fallback: always visible, even if objects fail ----
   if(InpCommentFallback && r.sym == Symbol())
   {
      string cm = "";
      for(int i1 = 0; i1 < cnt; i1++)
      {
         cm += lines[i1];
         if(i1 < cnt - 1) cm += "\n";
      }
      if(cm == "") cm = "Set & Forget: starting...";
      Comment(cm);
   }

   // --- graphical panel ---------------------------------------------
   if(!InpShowPanel || r.sym != Symbol()) return;

   ObjectsDeleteAll(0, "SF_PNL_");
   gPanelLines = cnt;

   int maxChars = 0;
   for(int i2 = 0; i2 < cnt; i2++)
      maxChars = (int)MathMax(maxChars, StringLen(lines[i2]));

   DrawPanelBackground(cnt, maxChars);
   for(int i3 = 0; i3 < cnt; i3++)
      PanelLine(i3, lines[i3], clrs[i3]);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| True if this symbol already handled this (forming) bar.          |
//| One signal per bar -> an arrow can never be created twice or move |
//+------------------------------------------------------------------+
bool BarAlreadyHandled(string symbol, datetime barTime)
{
   for(int i = 0; i < gSigCount; i++)
   {
      if(gSigSym[i] != symbol) continue;
      if(gSigBar[i] == barTime) return(true);
      gSigBar[i] = barTime;
      return(false);
   }
   if(gSigCount < SF_MAXSYM)
   {
      gSigSym[gSigCount] = symbol;
      gSigBar[gSigCount] = barTime;
      gSigCount++;
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Stop loss / take profit for the current setup.                   |
//|                                                                  |
//| SL  : beyond the level that invalidates the idea - the AOI zone,  |
//|       the broken level (B&R) and the H&S head - plus an ATR       |
//|       buffer. The widest of those levels is used (most           |
//|       conservative), so a wick into the zone does not stop us.    |
//| TP  : InpRiskReward x risk, optionally capped at the next        |
//|       opposing HTF zone.                                          |
//| Both are derived from r.entry, which is the close of the last     |
//| CLOSED entry-TF bar, so they do not drift while the bar forms.    |
//+------------------------------------------------------------------+
void ComputeTradeLevels(string symbol, SFResult &r, double sto, double tol)
{
   r.sl = 0; r.tp = 0; r.rr = 0;
   if(r.entry <= 0 || r.tradeDir == 0) return;

   double atr = GetATR(symbol, PERIOD_H1, 14);
   if(atr <= 0) atr = 10 * Point;

   double buf = InpSLBufferATR * atr;          // extra room beyond the level
   if(buf < 2 * Point) buf = 2 * Point;

   bool   buy   = (r.tradeDir == 1);
   double slAoi = 0;                            // invalidation given by the AOI
   double slStr = 0;                            // invalidation given by structure

   if(buy)
   {
      if(r.ltfSup > 0)                  slAoi = r.ltfSup - tol * 0.5;
      if(r.brDir == 1 && r.brLevel > 0) slStr = r.brLevel - sto * 0.25;
      if(r.hsDir == 1 && r.hsHead > 0)
         slStr = (slStr > 0 ? MathMin(slStr, r.hsHead) : r.hsHead);
   }
   else
   {
      if(r.ltfRes > 0)                    slAoi = r.ltfRes + tol * 0.5;
      if(r.brDir == -1 && r.brLevel > 0)  slStr = r.brLevel + sto * 0.25;
      if(r.hsDir == -1 && r.hsHead > 0)
         slStr = (slStr > 0 ? MathMax(slStr, r.hsHead) : r.hsHead);
   }

   // Use the wider of the AOI / structure invalidation, otherwise the one that
   // exists, otherwise an ATR-based stop.
   double sl = 0;
   if(slAoi > 0 && slStr > 0)  sl = (buy ? MathMin(slAoi, slStr) : MathMax(slAoi, slStr));
   else if(slAoi > 0)          sl = slAoi;
   else if(slStr > 0)          sl = slStr;
   else                        sl = (buy ? r.entry - 1.5 * atr : r.entry + 1.5 * atr);

   // Sanity cap: never accept a stop further than InpMaxSLATR * ATR.
   if(InpMaxSLATR > 0 && MathAbs(r.entry - sl) > InpMaxSLATR * atr)
   {
      if(slAoi > 0 && MathAbs(r.entry - slAoi) <= InpMaxSLATR * atr)
         sl = slAoi;
      else
         sl = (buy ? r.entry - InpMaxSLATR * atr : r.entry + InpMaxSLATR * atr);
   }

   sl = (buy ? sl - buf : sl + buf);
   if(buy  && sl >= r.entry - 2 * Point) return;
   if(!buy && sl <= r.entry + 2 * Point) return;

   double risk = MathAbs(r.entry - sl);
   if(risk <= 0) return;

   double tp = (buy ? r.entry + InpRiskReward * risk
                    : r.entry - InpRiskReward * risk);

   if(InpTPAtNextZone)
   {
      if(buy  && r.htfRes > r.entry && r.htfRes < tp) tp = r.htfRes;
      if(!buy && r.htfSup > 0 && r.htfSup < r.entry && r.htfSup > tp) tp = r.htfSup;
   }

   double reward = MathAbs(tp - r.entry);
   if(reward <= 0) return;

   double rr = reward / risk;
   if(InpMinRR > 0 && rr < InpMinRR) return;      // target too close: no plan

   r.sl = NormalizeDouble(sl, Digits);
   r.tp = NormalizeDouble(tp, Digits);
   r.rr = rr;
}

//+------------------------------------------------------------------+
//| Main analysis per symbol                                         |
//+------------------------------------------------------------------+
void AnalyzeSymbol(string symbol, SFResult &r)
{
   r.ok = false;
   r.sym = symbol;
   r.price = 0;
   r.t1 = "NODATA"; r.t2 = "NODATA";
   r.htfSync = false; r.htfDir = "MIXED"; r.tradeDir = 0;
   r.ltfSync = 0; r.l1 = "NODATA"; r.l2 = "NODATA"; r.l3 = "NODATA";
   r.atAoi = false; r.aoiInfo = "";
   r.htfRes = 0; r.htfSup = 0; r.ltfRes = 0; r.ltfSup = 0;
   r.htfResT = 0; r.htfSupT = 0; r.ltfResT = 0; r.ltfSupT = 0;
   r.brDir = 0; r.brLevel = 0; r.brBar = 0;
   r.hsDir = 0; r.hsHead = 0; r.hsNeck = 0; r.hsNew = 0; r.hsHeadBar = 0; r.hsOld = 0;
   r.engDir = 0; r.engTF = "";
   r.ready = false; r.reason = "WAIT - no data"; r.structure = ""; r.structDir = 0;
   r.dataDiag = ""; r.histNote = "";
   r.entry = 0; r.sl = 0; r.tp = 0; r.rr = 0;
   r.barsHTF1 = 0; r.barsHTF2 = 0; r.barsLTF = 0;
   r.tol = GetTolerance(symbol, InpAOITolPoints);

   //=== 1) HTF Trend: W1 + D1 must be in sync =======================
   string whyHTF1 = "", whyHTF2 = "", whyL1 = "", whyL2 = "", whyL3 = "";
   r.t1 = TrendLabelEx(symbol, InpHTF1, whyHTF1);
   r.t2 = TrendLabelEx(symbol, InpHTF2, whyHTF2);
   r.htfSync = (r.t1 == r.t2 && (r.t1 == "UP" || r.t1 == "DOWN"));
   r.htfDir  = r.htfSync ? r.t1 : "MIXED";
   if(r.htfDir == "UP")   r.tradeDir = 1;
   if(r.htfDir == "DOWN") r.tradeDir = -1;

   //=== 2) LTF trend sync: min 2 of H4/H1/M30 in sync with HTF ======
   r.l1 = TrendLabelEx(symbol, InpLTF1, whyL1);
   r.l2 = TrendLabelEx(symbol, InpLTF2, whyL2);
   r.l3 = TrendLabelEx(symbol, InpLTF3, whyL3);
   if(r.htfSync)
   {
      if(r.l1 == r.htfDir) r.ltfSync++;
      if(r.l2 == r.htfDir) r.ltfSync++;
      if(r.l3 == r.htfDir) r.ltfSync++;
   }

   //=== price / diagnostics =========================================
   r.barsHTF1 = iBars(symbol, InpHTF1);
   r.barsHTF2 = iBars(symbol, InpHTF2);
   r.barsLTF  = iBars(symbol, InpLTF2);
   r.dataDiag = StringFormat("%s %d  %s %d  %s %d  %s %d  %s %d",
                             TFName(InpHTF1), iBars(symbol, InpHTF1),
                             TFName(InpHTF2), iBars(symbol, InpHTF2),
                             TFName(InpLTF1), iBars(symbol, InpLTF1),
                             TFName(InpLTF2), iBars(symbol, InpLTF2),
                             TFName(InpLTF3), iBars(symbol, InpLTF3));
   string whys[5];
   whys[0] = whyHTF1; whys[1] = whyHTF2;
   whys[2] = whyL1;   whys[3] = whyL2;   whys[4] = whyL3;
   for(int wi = 0; wi < 5; wi++)
   {
      if(whys[wi] == "") continue;
      if(StringFind(r.histNote, whys[wi]) >= 0) continue;   // no duplicates
      if(r.histNote != "") r.histNote += "  |  ";
      r.histNote += whys[wi];
   }

   // explain it once in the journal too (the panel can be off-screen)
   if(r.histNote != "" && r.histNote != gLastNodata)
   {
      Print("[Set&Forget] ", symbol, " no-data detail: ", r.histNote,
            "   |   bars: ", r.dataDiag);
      gLastNodata = r.histNote;
   }
   if(r.histNote == "") gLastNodata = "";
   r.price    = iClose(symbol, PERIOD_H1, 0);
   if(r.price <= 0) r.price = iClose(symbol, (ENUM_TIMEFRAMES)Period(), 0);

   bool htfData = (r.t1 != "NODATA" && r.t2 != "NODATA");
   r.ok = (r.price > 0);

   if(!r.ok)
   {
      r.reason = "WAIT - no price data yet (history still downloading)";
      return;
   }

   double tol    = r.tol;
   double sto    = GetTolerance(symbol, InpStructTolPoints);
   double htfTol = tol * InpHTFZoneMult;
   if(htfTol <= 0) htfTol = tol;

   //=== 3) AOI zones ================================================
   double htfH[], htfL[], ltfH[], ltfL[];
   CollectSwings(symbol, InpHTF1, InpAOILookback, InpAOISwingLookback, htfH, htfL);
   CollectSwings(symbol, InpHTF2, InpAOILookback, InpAOISwingLookback, htfH, htfL);
   CollectSwings(symbol, InpLTF1, InpAOILookback, InpAOISwingLookback, ltfH, ltfL);
   CollectSwings(symbol, InpLTF2, InpAOILookback, InpAOISwingLookback, ltfH, ltfL);
   CollectSwings(symbol, InpLTF3, InpAOILookback, InpAOISwingLookback, ltfH, ltfL);

   double zl[];        // zone price   (ClusterZones/NearestZone expect double[])
   int    zc[];        // touch counts (ClusterZones/NearestZone expect int[])

   if(ClusterZones(htfH, htfTol, zl, zc) > 0)
      r.htfRes = NearestZone(zl, zc, r.price, htfTol, InpAOIMinTouches, true,  r.htfResT);
   if(ClusterZones(htfL, htfTol, zl, zc) > 0)
      r.htfSup = NearestZone(zl, zc, r.price, htfTol, InpAOIMinTouches, false, r.htfSupT);
   if(ClusterZones(ltfH, tol, zl, zc) > 0)
      r.ltfRes = NearestZone(zl, zc, r.price, tol, InpAOIMinTouches, true,  r.ltfResT);
   if(ClusterZones(ltfL, tol, zl, zc) > 0)
      r.ltfSup = NearestZone(zl, zc, r.price, tol, InpAOIMinTouches, false, r.ltfSupT);

   if(r.htfSync)
   {
      if(r.htfDir == "DOWN" && r.ltfRes > 0 && MathAbs(r.price - r.ltfRes) <= tol * 2.0)
      {
         r.atAoi  = true;
         r.aoiInfo = StringFormat("supply %.5f (%d touches)", r.ltfRes, r.ltfResT);
      }
      else if(r.htfDir == "UP" && r.ltfSup > 0 && MathAbs(r.price - r.ltfSup) <= tol * 2.0)
      {
         r.atAoi  = true;
         r.aoiInfo = StringFormat("demand %.5f (%d touches)", r.ltfSup, r.ltfSupT);
      }
   }

   //=== 4) Structure on primary LTF =================================
   ENUM_TIMEFRAMES structTF = InpLTF2;
   int brBreak = 0;
   if(InpDetectBnR)
      r.brDir = DetectBreakRetest(symbol, structTF, InpStructWindow, InpStructSwingLookback,
                                  sto, r.brLevel, r.brBar, brBreak);
   if(InpDetectHnS)
      r.hsDir = DetectHeadShoulders(symbol, structTF, InpStructWindow, InpStructSwingLookback, sto,
                                    r.hsHead, r.hsNeck, r.hsNew, r.hsHeadBar, r.hsOld);

   string brTxt = (r.brDir != 0)
                ? StringFormat("%s B&R @ %.5f", r.brDir == 1 ? "bullish" : "bearish", r.brLevel) : "";
   string hsTxt = (r.hsDir != 0)
                ? StringFormat("%s H&S @ %.5f (neck %.5f)",
                               r.hsDir == 1 ? "bullish inverse" : "bearish", r.hsHead, r.hsNeck) : "";

   // prefer structures that match the trend direction
   if(r.brDir != 0 && (r.tradeDir == 0 || r.brDir == r.tradeDir))
   { r.structDir = r.brDir; r.structure = brTxt; }
   if(r.hsDir != 0 && (r.tradeDir == 0 || r.hsDir == r.tradeDir))
   {
      if(r.structure != "") r.structure += " + ";
      r.structure += hsTxt;
      r.structDir = r.hsDir;
   }
   if(r.structDir == 0)   // nothing matches: still report what exists
   {
      if(r.brDir != 0)      { r.structDir = r.brDir; r.structure = brTxt; }
      else if(r.hsDir != 0) { r.structDir = r.hsDir; r.structure = hsTxt; }
   }

   //=== 5) Entry: engulfing candle on H1/H4 =========================
   if(InpRequireEngulfing)
   {
      int e1 = DetectEngulfing(symbol, InpEntryTF1, InpEngulfLookback);
      int e2 = DetectEngulfing(symbol, InpEntryTF2, InpEngulfLookback);
      if(e1 != 0)      { r.engDir = e1; r.engTF = TFName(InpEntryTF1); }
      else if(e2 != 0) { r.engDir = e2; r.engTF = TFName(InpEntryTF2); }
   }

   //=== Verdict =====================================================
   if(!htfData)
      r.reason = "WAIT - HTF trend unavailable: " + r.histNote;
   else if(!r.htfSync)
      r.reason = StringFormat("WAIT - HTF not in sync (%s=%s, %s=%s)",
                              TFName(InpHTF1), r.t1, TFName(InpHTF2), r.t2);
   else if(r.ltfSync < 2)
      r.reason = StringFormat("WAIT - LTF trend not in sync (%d/3)", r.ltfSync);
   else if(!r.atAoi)
      r.reason = StringFormat("WAIT - price not at an LTF AOI (%s trend)", r.htfDir);
   else if(r.structDir == 0 || r.structDir != r.tradeDir)
      r.reason = StringFormat("WAIT - no matching structure (%s)",
                              r.structure != "" ? r.structure : "none");
   else if(InpRequireEngulfing && r.engDir == 0)
      r.reason = StringFormat("WATCH - AOI + structure ready, awaiting engulfing on %s/%s",
                              TFName(InpEntryTF1), TFName(InpEntryTF2));
   else if(InpRequireEngulfing && r.engDir != r.tradeDir)
      r.reason = StringFormat("NO TRADE - engulfing (%s) opposes HTF trend (%s)",
                              r.engDir == 1 ? "BUY" : "SELL", r.htfDir);
   else
   {
      r.ready  = true;
      r.reason = StringFormat("VALID %s SETUP - HTF %s | LTF %d/3 | at AOI | %s | engulfing %s",
                              r.tradeDir == 1 ? "BUY" : "SELL", r.htfDir, r.ltfSync,
                              r.structure != "" ? r.structure : "structure",
                              r.engTF != "" ? r.engTF : "n/a");
   }

   if(InpDebugLog)
      Print(StringFormat("[Set&Forget] %s | HTF %s (%s/%s) | LTF sync %d/3 | AOI %s | Struct %s | Engulf %s | %s",
                         symbol, r.htfDir, r.t1, r.t2, r.ltfSync, r.atAoi ? "YES" : "no",
                         r.structure != "" ? r.structure : "none",
                         r.engDir == 0 ? "none" : (r.engDir == 1 ? "bullish" : "bearish"),
                         r.reason));

   //=== 6) Trade plan: entry / SL / TP ==============================
   // Entry is the close of the last CLOSED entry-TF bar (not the live tick),
   // so the plan - and the arrow that records it - never drift mid-bar.
   r.entry = r.price;
   if(InpBarCloseSignals)
   {
      double c1 = iClose(symbol, InpEntryTF1, 1);
      if(c1 > 0) r.entry = c1;
   }
   if(r.tradeDir != 0)
      ComputeTradeLevels(symbol, r, sto, tol);

   //=== 7) Signal: max one per bar, arrow is final ==================
   if(r.ready && r.tradeDir != 0)
   {
      datetime barTime = iTime(symbol, InpEntryTF1, 0);       // forming bar
      if(barTime <= 0) barTime = iTime(symbol, 0, 0);

      if(!InpBarCloseSignals || !BarAlreadyHandled(symbol, barTime))
      {
         datetime stamp = (InpBarCloseSignals ? iTime(symbol, InpEntryTF1, 1)
                                              : iTime(symbol, 0, 0));
         SendSuggestion(r.tradeDir, symbol, r.entry, r.reason, r.structure, r.aoiInfo,
                        r.sl, r.tp, stamp);
      }
   }
}

//+------------------------------------------------------------------+
//| Scan symbols                                                     |
//+------------------------------------------------------------------+
void ScanSymbols(bool force)
{
   // Throttle on the terminal's millisecond clock. TimeCurrent() is the last
   // quote time and can stand still over a weekend, which used to block rescans.
   uint nowMs = (uint)GetTickCount();
   if(!force && gNextScanMs != 0 && nowMs < gNextScanMs) return;
   gNextScanMs = nowMs + (uint)(InpScanEverySeconds * 1000);

   datetime now = TimeCurrent();
   if(now <= 0) now = TimeLocal();
   gLastScanTime = now;

   if(InpScanAllSymbols)
   {
      int total = SymbolsTotal(false);
      for(int i = 0; i < total; i++)
      {
         string sym = SymbolName(i, false);
         if(sym == "") continue;
         if(!SymbolSelect(sym, true)) continue;
         SFResult rs;
         AnalyzeSymbol(sym, rs);              // non-chart symbols: no drawing inside
      }
      SymbolSelect(Symbol(), true);
   }

   SFResult r;
   AnalyzeSymbol(Symbol(), r);
   DrawAnalysis(r);
   DrawStatus(r);

   // Higher timeframes may still be downloading (CopyClose returns -1 until the
   // series is built). Do not sit on a NODATA panel for a whole scan interval.
   if(!r.ok || r.t1 == "NODATA" || r.t2 == "NODATA" ||
      r.l1 == "NODATA" || r.l2 == "NODATA" || r.l3 == "NODATA")
      gNextScanMs = nowMs + 3000;
}

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName(StringFormat("Set & Forget v%s", SF_VERSION));
   IndicatorDigits(Digits);
   Print(StringFormat("=== Set and Forget INDICATOR v%s (analysis only, cannot trade) ===", SF_VERSION));
   Print(StringFormat("HTF: %s + %s | LTF: %s/%s/%s | Entry: %s/%s | draw=%s panel=%s",
                      TFName(InpHTF1), TFName(InpHTF2),
                      TFName(InpLTF1), TFName(InpLTF2), TFName(InpLTF3),
                      TFName(InpEntryTF1), TFName(InpEntryTF2),
                      InpDrawOnChart ? "yes" : "no", InpShowPanel ? "yes" : "no"));

   // Clear analysis leftovers, but NOT the signal arrows: they are the trade
   // record and must never be repainted or removed by a reload.
   ObjectsDeleteAll(0, "SF_Z_");
   ObjectsDeleteAll(0, "SF_S_");
   ObjectsDeleteAll(0, "SF_T_");
   ObjectsDeleteAll(0, "SF_PNL_");
   ObjectsDeleteAll(0, "SF_CMT_");
   if(!InpKeepSignals) ObjectsDeleteAll(0, "SF_SIG_");
   Comment("");

   gLastScanTime = 0;
   gNextScanMs   = 0;
   gSigCount     = 0;
   if(InpUseTimer)
   {
      int secs = (int)MathMax(5, InpScanEverySeconds);
      if(!EventSetTimer(secs))
         Print("EventSetTimer failed, error ", GetLastError());
   }

   // draw immediately - no tick required
   ScanSymbols(true);
   ChartRedraw(0);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, "SF_Z_");
   ObjectsDeleteAll(0, "SF_S_");
   ObjectsDeleteAll(0, "SF_T_");
   ObjectsDeleteAll(0, "SF_PNL_");
   ObjectsDeleteAll(0, "SF_CMT_");
   if(!InpKeepSignals) ObjectsDeleteAll(0, "SF_SIG_");
   Comment("");
   ChartRedraw(0);
}

void OnTimer()
{
   ScanSymbols(true);
}

//+------------------------------------------------------------------+
//| Indicator calculation: called on every price change               |
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
   if(rates_total < 2) return(0);

   // prev_calculated == 0 -> first run, history refresh or template reload
   ScanSymbols(prev_calculated == 0);

   return(rates_total);
}
//+------------------------------------------------------------------+
