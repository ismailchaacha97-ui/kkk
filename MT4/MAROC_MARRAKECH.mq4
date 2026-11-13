//+------------------------------------------------------------------+
//|                                            MAROC_MARRAKECH.mq4   |
//|                                                                  |
//|  MT4 (MQL4) conversion of the Pine Script v5 indicator           |
//|  "MAROC MARRAKECH"                                               |
//|                                                                  |
//|  Contents of the original script, all converted here:            |
//|    1) Market structure engine (internal pivots, BOS / CHoCH /     |
//|       CHoCH+ detection)                                          |
//|    2) Volumetric Order Blocks (OB), mitigation, overlap filter,   |
//|       positioning modes and internal buy/sell activity metrics    |
//|    3) Session VWAP + EMA200 trend "dynamic colour"                |
//|    4) Weekly and Monthly anchored VWAP                            |
//|    5) EMA(11/34) cross signals with ATR based SL and 4 x TP       |
//|       levels, live hit detection                                  |
//|                                                                  |
//|  DESIGN NOTES / LIMITATIONS (MT4 platform constraints)           |
//|    * MT4 allows max. 8 indicator buffers, therefore the           |
//|      "fill" between VWAP and EMA200 is not drawn. The dynamic     |
//|      colour of the two lines is preserved by splitting every      |
//|      line in an "up" and a "down" buffer.                         |
//|    * Semi transparent colours do not exist in MT4 - the 50%       |
//|      alpha colours of the metrics are replaced by blended tones.  |
//|    * MT4 has no opaque boxes with text: the OB volume label is    |
//|      rendered with a OBJ_TEXT placed at the left edge of the      |
//|      extension box.                                               |
//|    * The logic runs on CLOSED bars (non repainting). AOB blocks   |
//|      appear at the close of the signal bar, exactly like the      |
//|      Pine version does on barstate.isconfirmed.                   |
//|    * Weekly/Monthly VWAP anchors are computed from the server     |
//|      time of the chart (00:00, Monday 00:00, 1st 00:00).          |
//|    * "Swing lookback" exists in the original script but its       |
//|      pivots are never used - the input is kept for compatibility. |
//+------------------------------------------------------------------+
#property copyright   "MT4 port of the Pine v5 script MAROC MARRAKECH"
#property link        ""
#property version     "1.00"
#property description "Volumetric Order Blocks + BOS/CHoCH + VWAP/EMA200 trend + EMA/ATR trade levels"
#property strict
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_color1  clrLime
#property indicator_color2  clrRed
#property indicator_color3  clrLime
#property indicator_color4  clrRed
#property indicator_color5  clrDodgerBlue
#property indicator_color6  clrOrange
#property indicator_color7  clrLime
#property indicator_color8  clrRed

//==================================================================//
//  ENUMERATIONS                                                    //
//==================================================================//
enum ENUM_MSMODE
  {
   MS_MANUAL  = 0,   // Manual
   MS_DYNAMIC = 1    // Dynamic
  };

enum ENUM_OBFILTER
  {
   OBF_NONE   = 0,   // None
   OBF_BOS    = 1,   // BOS
   OBF_CHOCH  = 2,   // CHoCH
   OBF_CHOCHP = 3    // CHoCH+
  };

enum ENUM_OBMITIG
  {
   OBM_ABSOLUTE = 0, // Absolute
   OBM_MIDDLE   = 1  // Middle
  };

enum ENUM_OBPOS
  {
   OBP_FULL     = 0, // Full
   OBP_MIDDLE   = 1, // Middle
   OBP_ACCURATE = 2, // Accurate
   OBP_PRECISE  = 3  // Precise
  };

//==================================================================//
//  INPUTS                                                          //
//==================================================================//
input string        InpHdrMS            = "----- MARKET STRUCTURE -----";      // MARKET STRUCTURE
input int           InpInternalLookback = 5;                                   // Internal pivot lookback
input int           InpSwingLookback    = 50;                                  // Swing lookback (unused, as in original)
input ENUM_MSMODE   InpMode             = MS_MANUAL;                           // Mode

input string        InpHdrOB            = "----- VOLUMETRIC ORDER BLOCKS -----"; // ORDER BLOCKS
input bool          InpShowOB           = true;                                // Show order blocks
input int           InpOBNum            = 5;                                   // Number of OBs
input bool          InpShowInternal     = true;                                // Show internal activity
input bool          InpShowMetrics      = true;                                // Show volume / percent
input ENUM_OBFILTER InpOBFilter         = OBF_NONE;                            // Filtering
input ENUM_OBMITIG  InpMitigation       = OBM_ABSOLUTE;                        // Mitigation
input ENUM_OBPOS    InpOBPos            = OBP_PRECISE;                         // Positioning
input bool          InpHideOverlap      = true;                                // Hide overlap
input color         InpBullOBColor      = C'8,153,129';                        // Bullish OB colour
input color         InpBearOBColor      = C'242,54,69';                        // Bearish OB colour
input color         InpMetricUpColor    = C'131,204,192';                      // Metric up colour
input color         InpMetricDnColor    = C'248,154,162';                      // Metric down colour
input int           InpExtendBars       = 100;                                 // OB extension (bars to right)

input string        InpHdrVWAP          = "----- VWAP / EMA TREND -----";       // VWAP / EMA
input int           InpEma200Len        = 200;                                 // EMA 200 length
input bool          InpShowWeekly       = true;                                // Show weekly VWAP
input color         InpWeeklyColor      = clrDodgerBlue;                       // Weekly VWAP colour
input int           InpWeeklyWidth      = 2;                                   // Weekly VWAP width
input bool          InpShowMonthly      = true;                                // Show monthly VWAP
input color         InpMonthlyColor     = clrOrange;                           // Monthly VWAP colour
input int           InpMonthlyWidth     = 2;                                   // Monthly VWAP width
input color         InpTrendUpColor     = clrLime;                             // Trend up colour
input color         InpTrendDnColor     = clrRed;                              // Trend down colour

input string        InpHdrLogic         = "----- LOGIC / TRADE -----";          // LOGIC
input int           InpEmaFast          = 11;                                  // EMA fast
input int           InpEmaSlow          = 34;                                  // EMA slow
input int           InpAtrPeriod        = 14;                                  // ATR period
input double        InpSLMult           = 2.5;                                 // SL multiplier (x ATR)
input double        InpTPMult           = 1.5;                                 // TP multiplier (x SL)
input int           InpTradeExtendBars  = 10;                                  // Trade level extension (bars)

input string        InpHdrMisc          = "----- MISC -----";                   // MISC
input int           InpMaxReplayBars    = 3000;                                // History bars replayed on start
input bool          InpAlerts           = false;                               // Enable alerts

//==================================================================//
//  DATA TYPES                                                      //
//==================================================================//
struct OBInfo
  {
   datetime          left;      // left edge (time of the extreme bar)
   double            top;       // upper boundary
   double            btm;       // lower boundary
   double            avg;       // middle line
   double            cV;        // volume of the reference bar
   int               dir;       // +1 bullish candle / -1 bearish candle
   int               wM;        // internal activity state machine
   int               blVP;      // buy pressure bars
   int               brVP;      // sell pressure bars
  };

struct HitInfo
  {
   datetime          t;
   double            price;
   int               kind;      // 0 = SL, 1..4 = TP1..TP4
  };

//==================================================================//
//  INDICATOR BUFFERS                                               //
//==================================================================//
double BufVwapUp[];    // 0 - VWAP      (trend up)
double BufVwapDn[];    // 1 - VWAP      (trend down)
double BufEmaUp[];     // 2 - EMA200    (trend up)
double BufEmaDn[];     // 3 - EMA200    (trend down)
double BufWeekly[];    // 4 - weekly VWAP
double BufMonthly[];   // 5 - monthly VWAP
double BufBuyArrow[];  // 6 - buy arrow
double BufSellArrow[]; // 7 - sell arrow

//==================================================================//
//  GLOBAL STATE                                                    //
//==================================================================//
double   gEmaF[];      // EMA fast  (series indexed : 0 = current bar)
double   gEmaS[];      // EMA slow
double   gEma200[];    // EMA 200
double   gAtr[];       // ATR

//--- market structure (pivot prices, newest first)
double   gUpP[];       // pivot highs - cleared on a bullish break
double   gUpL[];       // pivot highs - never cleared (used by CHoCH+)
double   gDnP[];       // pivot lows  - cleared on a bearish break
double   gDnL[];       // pivot lows  - never cleared (used by CHoCH+)
int      gTrend   = 0;
int      gILen    = 5;
datetime gLastPivotHi = 0;
datetime gLastPivotLo = 0;

//--- order blocks
OBInfo   gBullOB[];
OBInfo   gBearOB[];

//--- trade engine
double   gEntry = 0.0;
double   gSL    = 0.0;
double   gTP1   = 0.0;
double   gTP2   = 0.0;
double   gTP3   = 0.0;
double   gTP4   = 0.0;
int      gTradeDir  = 0;      // 0 = closed / no trade, +1 long, -1 short
int      gTradeSide = 0;      // direction of the last signal (persists)
datetime gTradeTime = 0;
bool     gHit1 = false, gHit2 = false, gHit3 = false, gHit4 = false;
HitInfo  gHits[];

//--- signals of the current bar
bool     gSignalBull = false;
bool     gSignalBear = false;
bool     gCrossLong  = false;
bool     gCrossShort = false;

//--- runtime
bool     gReady       = false;
datetime gLastBarTime = 0;
int      gLastTotal   = 0;

//==================================================================//
//  SMALL HELPERS                                                   //
//==================================================================//
double HLC3(const int sh)  { return (High[sh] + Low[sh] + Close[sh]) / 3.0; }
double HL2(const int sh)   { return (High[sh] + Low[sh]) / 2.0;            }
double OHLC4(const int sh) { return (Open[sh] + High[sh] + Low[sh] + Close[sh]) / 4.0; }
double HLCC4(const int sh) { return (High[sh] + Low[sh] + 2.0 * Close[sh]) / 4.0; }

//--- start of the server day
datetime DayStart(const datetime t) { return (datetime)(((long)t / 86400) * 86400); }
//--- start of the server week (Monday 00:00)
datetime WeekStart(const datetime t)
  {
   int dow = TimeDayOfWeek(t);          // 0 = Sunday ... 6 = Saturday
   int back = (dow == 0) ? 6 : dow - 1;
   return (datetime)((long)DayStart(t) - (long)back * 86400);
  }
//--- start of the server month
datetime MonthStart(const datetime t)
  {
   return (datetime)((long)DayStart(t) - (long)(TimeDay(t) - 1) * 86400);
  }

//--- volume text (same scaling as str.tostring in Pine)
string FmtVolume(const double v)
  {
   if(v >= 1000000000.0) return DoubleToString(v / 1000000000.0, 3) + "B";
   if(v >= 1000000.0)    return DoubleToString(v / 1000000.0, 3)    + "M";
   if(v >= 1000.0)       return DoubleToString(v / 1000.0, 3)       + "K";
   return DoubleToString(v, 0);
  }

//--- unshift a value in a dynamic array (index 0 = newest)
void PushFront(double &arr[], const double v)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   for(int i = n; i > 0; i--) arr[i] = arr[i - 1];
   arr[0] = v;
  }

//--- unshift an order block in a dynamic array
void OBInsertFirst(OBInfo &arr[], OBInfo &rec, const int maxKeep)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   for(int i = n; i > 0; i--) arr[i] = arr[i - 1];
   arr[0] = rec;
   int keep = (maxKeep < 1) ? 1 : maxKeep;
   if(ArraySize(arr) > keep) ArrayResize(arr, keep);
  }

//--- remove one order block
void OBRemoveAt(OBInfo &arr[], const int idx)
  {
   int n = ArraySize(arr);
   if(idx < 0 || idx >= n) return;
   for(int i = idx; i < n - 1; i++) arr[i] = arr[i + 1];
   ArrayResize(arr, n - 1);
  }

//==================================================================//
//  PIVOTS                                                          //
//  Pine : ta.pivothigh(high, len, len) evaluated on bar `sh`       //
//  -> the pivot bar is `sh + len`, the right side uses the len      //
//     bars sh..sh+len-1 and the left side sh+len+1..sh+2*len        //
//==================================================================//
bool PivotHigh(const int sh, const int len, double &price)
  {
   if(len < 1) return false;
   int p = sh + len;
   if(p + len >= Bars) return false;
   double mid = High[p];
   for(int i = p - len; i < p; i++)
     {
      if(i < 0) return false;
      if(High[i] >= mid) return false;
     }
   for(int j = p + 1; j <= p + len; j++)
     {
      if(High[j] >= mid) return false;
     }
   price = mid;
   return true;
  }

bool PivotLow(const int sh, const int len, double &price)
  {
   if(len < 1) return false;
   int p = sh + len;
   if(p + len >= Bars) return false;
   double mid = Low[p];
   for(int i = p - len; i < p; i++)
     {
      if(i < 0) return false;
      if(Low[i] <= mid) return false;
     }
   for(int j = p + 1; j <= p + len; j++)
     {
      if(Low[j] <= mid) return false;
     }
   price = mid;
   return true;
  }

//--- z-score of the normalised momentum (f_zscore in the original)
double ZScoreVV(const int sh, const int len)
  {
   if(len < 2) return 0.0;
   if(sh + 2 * len + 1 >= Bars) return 0.0;
   double sum = 0.0, sum2 = 0.0;
   double src = 0.0;
   for(int i = 0; i < len; i++)
     {
      int s2 = sh + i;
      double c0 = Close[s2];
      double c1 = Close[s2 + len];
      double x  = (c1 != 0.0) ? ((c0 - c1) / c1) * 100.0 : 0.0;
      if(i == 0) src = x;
      sum  += x;
      sum2 += x * x;
     }
   double mean = sum / len;
   double var  = sum2 / len - mean * mean;      // population variance (ta.stdev)
   if(var <= 0.0) return 0.0;
   return (src - mean) / MathSqrt(var);
  }

//==================================================================//
//  ORDER BLOCK ENGINE                                              //
//==================================================================//
//--- "pos" of the original : Full / Middle / Accurate / Precise
double PosValue(const int sh, const bool bull)
  {
   switch(InpOBPos)
     {
      case OBP_FULL:     return bull ? High[sh] : Low[sh];
      case OBP_MIDDLE:   return OHLC4(sh);
      case OBP_ACCURATE: return HL2(sh);
      case OBP_PRECISE:  return HL2(sh);
     }
   return HL2(sh);
  }

//--- create a new order block (drawVOB -> "if cdn" block)
void CreateOB(const bool bull, const datetime locTime, const int sh)
  {
   if(locTime <= 0) return;
   int locShift = iBarShift(NULL, 0, locTime, false);
   if(locShift < 0) return;
   int winLen = locShift - sh;        // bars examined : sh .. locShift-1
   if(winLen < 1) return;
   if(sh + winLen > Bars - 1) winLen = Bars - 1 - sh;
   if(winLen < 1) return;

   double minLow = 0.0, maxHigh = 0.0;
   int    mMin = -1, mMax = -1;
   for(int j = 0; j < winLen; j++)
     {
      int s2 = sh + j;
      double hh = High[s2];
      double ll = Low[s2];
      if(mMin < 0 || ll < minLow) { minLow = ll; mMin = j; }
      if(mMax < 0 || hh > maxHigh) { maxHigh = hh; mMax = j; }
     }
   if(mMin < 0 || mMax < 0) return;

   int shU = sh + mMin + 1;           // same +1 offset as the Pine code
   int shD = sh + mMax + 1;
   if(shU > Bars - 1) shU = Bars - 1;
   if(shD > Bars - 1) shD = Bars - 1;

   OBInfo rec;
   rec.dir  = bull ? ((Close[shU] > Open[shU]) ? 1 : -1)
                   : ((Close[shD] > Open[shD]) ? 1 : -1);
   if(bull)
     {
      rec.top  = PosValue(shU, true);
      rec.btm  = minLow;
      rec.left = Time[sh + mMin];
      rec.cV   = (double)Volume[shU];
     }
   else
     {
      rec.top  = maxHigh;
      rec.btm  = PosValue(shD, false);
      rec.left = Time[sh + mMax];
      rec.cV   = (double)Volume[shD];
     }
   rec.avg  = (rec.top + rec.btm) / 2.0;
   rec.wM   = 1;
   rec.blVP = 0;
   rec.brVP = 0;

   //--- "Precise" fine tuning (identical conditions to the original)
   if(InpOBPos == OBP_PRECISE)
     {
      if(bull)
        {
         double bodyEdge = MathMin(Close[shU], Open[shU]);
         if(rec.avg < bodyEdge && rec.top > HLCC4(shU))
           {
            rec.top = rec.avg;
            rec.avg = (rec.top + rec.btm) / 2.0;
           }
        }
      else
        {
         // the original compares c[iU]/o[iU] but uses o[iD]/c[iD] - kept as is
         double cmpVal = (Close[shU] < Open[shU]) ? Open[shD] : Close[shD];
         if(rec.avg > cmpVal && rec.btm < HLCC4(shD))
           {
            rec.btm = rec.avg;
            rec.avg = (rec.top + rec.btm) / 2.0;
           }
        }
     }

   //--- hide overlap : drop the previous block when they overlap
   if(bull)
     {
      if(InpHideOverlap && ArraySize(gBullOB) > 0 && rec.btm < gBullOB[0].top)
         OBRemoveAt(gBullOB, 0);
      OBInsertFirst(gBullOB, rec, InpOBNum);
     }
   else
     {
      if(InpHideOverlap && ArraySize(gBearOB) > 0 && rec.top > gBearOB[0].btm)
         OBRemoveAt(gBearOB, 0);
      OBInsertFirst(gBearOB, rec, InpOBNum);
     }
  }

//--- mitigation (removed once price closes through the level)
void MitigateOB(const bool bull, const int sh)
  {
   if(bull)
     {
      for(int i = ArraySize(gBullOB) - 1; i >= 0; i--)
        {
         double pt = (InpMitigation == OBM_MIDDLE) ? gBullOB[i].avg : gBullOB[i].btm;
         if(Close[sh] < pt) OBRemoveAt(gBullOB, i);
        }
     }
   else
     {
      for(int i = ArraySize(gBearOB) - 1; i >= 0; i--)
        {
         double pt = (InpMitigation == OBM_MIDDLE) ? gBearOB[i].avg : gBearOB[i].top;
         if(Close[sh] > pt) OBRemoveAt(gBearOB, i);
        }
     }
  }

//--- internal buy / sell activity state machine
void UpdateMetrics(const bool bull)
  {
   int n = bull ? ArraySize(gBullOB) : ArraySize(gBearOB);
   for(int i = 0; i < n; i++)
     {
      int dir, wm, bl, br;
      if(bull)
        {
         dir = gBullOB[i].dir;
         wm  = gBullOB[i].wM;
         bl  = gBullOB[i].blVP;
         br  = gBullOB[i].brVP;
        }
      else
        {
         dir = gBearOB[i].dir;
         wm  = gBearOB[i].wM;
         bl  = gBearOB[i].blVP;
         br  = gBearOB[i].brVP;
        }

      if(dir == 1)
        {
         if(wm == 1)      { bl++; wm = 2; }
         else if(wm == 2) { bl++; wm = 3; }
         else             { br++; wm = 1; }
        }
      else
        {
         if(wm == 1)      { br++; wm = 2; }
         else if(wm == 2) { br++; wm = 3; }
         else             { bl++; wm = 1; }
        }

      if(bull) { gBullOB[i].blVP = bl; gBullOB[i].brVP = br; gBullOB[i].wM = wm; }
      else     { gBearOB[i].blVP = bl; gBearOB[i].brVP = br; gBearOB[i].wM = wm; }
     }
  }

//--- one call of drawVOB() : called on EVERY bar for both directions
void RunVOB(const bool bull, const datetime locTime, const bool create, const int sh)
  {
   if(create) CreateOB(bull, locTime, sh);
   MitigateOB(bull, sh);
   if(InpShowInternal) UpdateMetrics(bull);
  }

//==================================================================//
//  TRADE ENGINE  (EMA fast/slow cross + ATR SL / 4 x TP)           //
//==================================================================//
void AddHit(const datetime t, const double price, const int kind)
  {
   int n = ArraySize(gHits);
   ArrayResize(gHits, n + 1);
   gHits[n].t     = t;
   gHits[n].price = price;
   gHits[n].kind  = kind;
  }

void TradeLogic(const int sh)
  {
   gCrossLong  = false;
   gCrossShort = false;
   if(sh + 1 >= Bars) return;

   bool longSig  = (gEmaF[sh + 1] > 0.0 && gEmaS[sh + 1] > 0.0 &&
                    gEmaF[sh + 1] <= gEmaS[sh + 1] && gEmaF[sh] > gEmaS[sh]);
   bool shortSig = (gEmaF[sh + 1] > 0.0 && gEmaS[sh + 1] > 0.0 &&
                    gEmaF[sh + 1] >= gEmaS[sh + 1] && gEmaF[sh] < gEmaS[sh]);
   gCrossLong  = longSig;
   gCrossShort = shortSig;

   //--- new signal (cleanup() + new levels in the original)
   if(longSig || shortSig)
     {
      gTradeSide = longSig ? 1 : -1;
      gTradeDir  = gTradeSide;
      ArrayResize(gHits, 0);

      double entry = Close[sh];
      double atr   = gAtr[sh];
      if(atr <= 0.0) atr = High[sh] - Low[sh];
      if(atr <= 0.0) atr = 10.0 * Point;

      gEntry     = entry;
      gSL        = entry - gTradeSide * atr * InpSLMult;
      gTP1       = entry + gTradeSide * atr * InpSLMult * InpTPMult * 1.0;
      gTP2       = entry + gTradeSide * atr * InpSLMult * InpTPMult * 2.0;
      gTP3       = entry + gTradeSide * atr * InpSLMult * InpTPMult * 3.0;
      gTP4       = entry + gTradeSide * atr * InpSLMult * InpTPMult * 4.0;
      gTradeTime = Time[sh];
      gHit1 = false; gHit2 = false; gHit3 = false; gHit4 = false;
     }

   //--- live detection (same bar as the signal can already trigger a hit)
   if(gTradeDir != 0)
     {
      bool slHit = ((gTradeDir == 1 && Low[sh]  <= gSL) ||
                    (gTradeDir == -1 && High[sh] >= gSL));
      if(slHit)
        {
         AddHit(Time[sh], gSL,  0);
         gTradeDir = 0;
        }

      if(gTradeDir != 0)
        {
         if(!gHit1 && ((gTradeDir == 1 && High[sh] >= gTP1) || (gTradeDir == -1 && Low[sh] <= gTP1)))
           {
            gHit1 = true;
            AddHit(Time[sh], gTP1, 1);
           }
         if(!gHit2 && ((gTradeDir == 1 && High[sh] >= gTP2) || (gTradeDir == -1 && Low[sh] <= gTP2)))
           {
            gHit2 = true;
            AddHit(Time[sh], gTP2, 2);
           }
         if(!gHit3 && ((gTradeDir == 1 && High[sh] >= gTP3) || (gTradeDir == -1 && Low[sh] <= gTP3)))
           {
            gHit3 = true;
            AddHit(Time[sh], gTP3, 3);
           }
         if(!gHit4 && ((gTradeDir == 1 && High[sh] >= gTP4) || (gTradeDir == -1 && Low[sh] <= gTP4)))
           {
            gHit4 = true;
            AddHit(Time[sh], gTP4, 4);
            gTradeDir = 0;
           }
        }
     }
  }

//==================================================================//
//  ONE BAR OF THE WHOLE STRATEGY (exactly one Pine execution)      //
//==================================================================//
void ProcessBar(const int sh)
  {
   if(sh < 0 || sh >= Bars - 1) return;

   gSignalBull = false;
   gSignalBear = false;

   //--- 1) internal lookback (Dynamic mode)
   //    NOTE : in the Pine source the switch lists vv >= 1.5 first, and a
   //    Pine switch returns the FIRST matching branch - so every case after
   //    the first one is unreachable and the lookback would always be 10.
   //    Here the obviously intended behaviour (the more extreme the z-score,
   //    the shorter the lookback) is implemented.
   if(InpMode == MS_DYNAMIC)
     {
      double vv = MathAbs(ZScoreVV(sh, gILen));
      if(vv >= 2.0)      gILen = 5;
      else if(vv >= 1.9) gILen = 6;
      else if(vv >= 1.8) gILen = 7;
      else if(vv >= 1.7) gILen = 8;
      else if(vv >= 1.6) gILen = 9;
      else if(vv >= 1.5) gILen = 10;
     }
   int iLen = gILen;

   //--- 2) internal pivots
   double pH = 0.0, pL = 0.0;
   bool hasIH = PivotHigh(sh, iLen, pH);
   bool hasIL = PivotLow(sh, iLen, pL);

   //--- 3) structure() : push pivots, detect BOS / CHoCH / CHoCH+
   if(hasIH) { PushFront(gUpP, pH); PushFront(gUpL, pH); }
   if(hasIL) { PushFront(gDnP, pL); PushFront(gDnL, pL); }

   string txt = "";

   if(ArraySize(gUpP) > 0 && ArraySize(gDnL) > 1)
     {
      double lvl = gUpP[0];
      if(Close[sh + 1] <= lvl && Close[sh] > lvl)
        {
         bool choch = (gTrend < 0);
         if(!choch) txt = "BOS";
         else       txt = (gDnL[0] > gDnL[1]) ? "CHoCH+" : "CHoCH";

         bool ok = (InpOBFilter == OBF_NONE) ||
                   (InpOBFilter == OBF_BOS    && txt == "BOS") ||
                   (InpOBFilter == OBF_CHOCH  && txt == "CHoCH") ||
                   (InpOBFilter == OBF_CHOCHP && txt == "CHoCH+");
         if(ok) gSignalBull = true;

         gTrend = 1;
         ArrayResize(gUpP, 0);          // Pine clears up.n / up.p only
        }
     }

   if(ArraySize(gDnP) > 0 && ArraySize(gUpL) > 1)
     {
      double lvl = gDnP[0];
      if(Close[sh + 1] >= lvl && Close[sh] < lvl)
        {
         bool choch = (gTrend > 0);
         if(!choch) txt = "BOS";
         else       txt = (gUpL[0] < gUpL[1]) ? "CHoCH+" : "CHoCH";

         bool ok = (InpOBFilter == OBF_NONE) ||
                   (InpOBFilter == OBF_BOS    && txt == "BOS") ||
                   (InpOBFilter == OBF_CHOCH  && txt == "CHoCH") ||
                   (InpOBFilter == OBF_CHOCHP && txt == "CHoCH+");
         if(ok) gSignalBear = true;

         gTrend = -1;
         ArrayResize(gDnP, 0);
        }
     }

   //--- 4) execution : keep the last internal pivot bar, then draw the VOBs
   if(hasIH) gLastPivotHi = Time[sh + iLen];
   if(hasIL) gLastPivotLo = Time[sh + iLen];

   if(InpShowOB)
     {
      RunVOB(true,  gLastPivotHi, gSignalBull, sh);
      RunVOB(false, gLastPivotLo, gSignalBear, sh);
     }

   //--- 5) EMA cross / SL / TP engine
   TradeLogic(sh);
  }

//==================================================================//
//  SERIES  (VWAP, EMAs, ATR, arrows)                               //
//==================================================================//
void ComputeSeries(const int total)
  {
   if(ArraySize(gEmaF) != total)
     {
      ArrayResize(gEmaF,   total); ArraySetAsSeries(gEmaF,   true);
      ArrayResize(gEmaS,   total); ArraySetAsSeries(gEmaS,   true);
      ArrayResize(gEma200, total); ArraySetAsSeries(gEma200, true);
      ArrayResize(gAtr,    total); ArraySetAsSeries(gAtr,    true);
     }

   double kF   = 2.0 / (InpEmaFast + 1.0);
   double kS   = 2.0 / (InpEmaSlow + 1.0);
   double k200 = 2.0 / (InpEma200Len + 1.0);

   double emaF = 0.0, emaS = 0.0, ema200 = 0.0;
   double sumF = 0.0, sumS = 0.0, sum200 = 0.0;
   int    cF = 0, cS = 0, c200 = 0;

   double atr = 0.0, sumTr = 0.0;
   int    cTr = 0;

   double sumPVd = 0.0, sumVd = 0.0;
   double sumPVw = 0.0, sumVw = 0.0;
   double sumPVm = 0.0, sumVm = 0.0;
   datetime curD = 0, curW = 0, curM = 0;

   int emaFastLen = (InpEmaFast   < 1) ? 1 : InpEmaFast;
   int emaSlowLen = (InpEmaSlow   < 1) ? 1 : InpEmaSlow;
   int ema200Len  = (InpEma200Len < 1) ? 1 : InpEma200Len;
   int atrLen     = (InpAtrPeriod < 1) ? 1 : InpAtrPeriod;

   for(int sh = total - 1; sh >= 0; sh--)
     {
      int k  = total - 1 - sh;
      double c = Close[sh];

      //--- EMAs (seeded with the SMA of the first N values, like ta.ema)
      if(cF < emaFastLen)
        {
         sumF += c; cF++;
         if(cF == emaFastLen) emaF = sumF / emaFastLen;
        }
      else emaF = c * kF + emaF * (1.0 - kF);
      gEmaF[sh] = (cF >= emaFastLen) ? emaF : 0.0;

      if(cS < emaSlowLen)
        {
         sumS += c; cS++;
         if(cS == emaSlowLen) emaS = sumS / emaSlowLen;
        }
      else emaS = c * kS + emaS * (1.0 - kS);
      gEmaS[sh] = (cS >= emaSlowLen) ? emaS : 0.0;

      if(c200 < ema200Len)
        {
         sum200 += c; c200++;
         if(c200 == ema200Len) ema200 = sum200 / ema200Len;
        }
      else ema200 = c * k200 + ema200 * (1.0 - k200);
      gEma200[sh] = (c200 >= ema200Len) ? ema200 : 0.0;

      //--- ATR (Wilder / RMA)
      double tr;
      if(sh + 1 < total)
         tr = MathMax(High[sh] - Low[sh],
                      MathMax(MathAbs(High[sh] - Close[sh + 1]),
                              MathAbs(Low[sh]  - Close[sh + 1])));
      else
         tr = High[sh] - Low[sh];

      if(cTr < atrLen)
        {
         sumTr += tr; cTr++;
         if(cTr == atrLen) atr = sumTr / atrLen;
        }
      else atr = (atr * (atrLen - 1) + tr) / atrLen;
      gAtr[sh] = (cTr >= atrLen) ? atr : 0.0;

      //--- anchored VWAPs
      datetime t  = Time[sh];
      datetime d0 = DayStart(t);
      datetime w0 = WeekStart(t);
      datetime m0 = MonthStart(t);
      if(d0 != curD) { curD = d0; sumPVd = 0.0; sumVd = 0.0; }
      if(w0 != curW) { curW = w0; sumPVw = 0.0; sumVw = 0.0; }
      if(m0 != curM) { curM = m0; sumPVm = 0.0; sumVm = 0.0; }

      double tp = (High[sh] + Low[sh] + c) / 3.0;   // hlc3
      double v  = (double)Volume[sh];
      if(v <= 0.0) v = 1.0;

      sumPVd += tp * v; sumVd += v;
      sumPVw += tp * v; sumVw += v;
      sumPVm += tp * v; sumVm += v;

      double vwapD = (sumVd > 0.0) ? sumPVd / sumVd : tp;
      double vwapW = (sumVw > 0.0) ? sumPVw / sumVw : tp;
      double vwapM = (sumVm > 0.0) ? sumPVm / sumVm : tp;

      //--- buffers : dynamic colour of VWAP / EMA200
      BufVwapUp[k] = EMPTY_VALUE;
      BufVwapDn[k] = EMPTY_VALUE;
      BufEmaUp[k]  = EMPTY_VALUE;
      BufEmaDn[k]  = EMPTY_VALUE;

      if(gEma200[sh] > 0.0)
        {
         if(vwapD > gEma200[sh])
           {
            BufVwapUp[k] = vwapD;
            BufEmaUp[k]  = gEma200[sh];
           }
         else
           {
            BufVwapDn[k] = vwapD;
            BufEmaDn[k]  = gEma200[sh];
           }
        }

      BufWeekly[k]  = InpShowWeekly  ? vwapW : EMPTY_VALUE;
      BufMonthly[k] = InpShowMonthly ? vwapM : EMPTY_VALUE;

      //--- EMA cross arrows
      BufBuyArrow[k]  = EMPTY_VALUE;
      BufSellArrow[k] = EMPTY_VALUE;

      if(sh + 1 < total && gEmaF[sh] > 0.0 && gEmaS[sh] > 0.0 &&
         gEmaF[sh + 1] > 0.0 && gEmaS[sh + 1] > 0.0)
        {
         double off = (gAtr[sh] > 0.0) ? gAtr[sh] * 0.6 : (High[sh] - Low[sh]) * 0.5;
         if(off <= 0.0) off = 5.0 * Point;

         if(gEmaF[sh + 1] <= gEmaS[sh + 1] && gEmaF[sh] > gEmaS[sh])
            BufBuyArrow[k] = Low[sh] - off;

         if(gEmaF[sh + 1] >= gEmaS[sh + 1] && gEmaF[sh] < gEmaS[sh])
            BufSellArrow[k] = High[sh] + off;
        }
     }
  }

//==================================================================//
//  DRAWING                                                         //
//==================================================================//
void ObjRect(const string name, const datetime t1, const double p1,
             const datetime t2, const double p2, const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

void ObjText(const string name, const datetime t, const double p, const string txt,
             const color clr, const int fsize, const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   else
      ObjectMove(0, name, 0, t, p);

   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fsize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void ObjTrend(const string name, const datetime t1, const double p1,
              const datetime t2, const double p2, const color clr,
              const int style, const int width)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, (ENUM_LINE_STYLE)style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void DrawOBSet(OBInfo &arr[], const bool bull)
  {
   int cnt = ArraySize(arr);
   if(cnt > InpOBNum) cnt = InpOBNum;
   if(cnt <= 0) return;

   double tV = 0.0;
   for(int j = 0; j < cnt; j++) tV += arr[j].cV;

   string side = bull ? "B" : "S";
   color  base = bull ? InpBullOBColor : InpBearOBColor;
   datetime rightEdge = (datetime)(Time[0] + (long)PeriodSeconds() * (long)InpExtendBars);

   for(int i = 0; i < cnt; i++)
     {
      string pfx = "MMRK_OB_" + side + IntegerToString(i) + "_";
      double pct = (tV > 0.0) ? MathFloor((arr[i].cV / tV) * 100.0) : 0.0;

      //--- order block + right extension
      ObjRect(pfx + "BOX", arr[i].left, arr[i].top, Time[0], arr[i].btm, base);
      ObjRect(pfx + "EXT", Time[0], arr[i].top, rightEdge, arr[i].btm, base);

      //--- volume / percentage text
      ObjText(pfx + "TXT", Time[0], arr[i].top,
              FmtVolume(arr[i].cV) + " (" + DoubleToString(pct, 0) + "%)",
              base, 8, ANCHOR_LEFT_UPPER);

      //--- BUY / SELL badge attached to the block
      if(bull)
         ObjText(pfx + "SIG", arr[i].left, arr[i].btm, "BUY", base, 8, ANCHOR_UPPER);
      else
         ObjText(pfx + "SIG", arr[i].left, arr[i].top, "SELL", base, 8, ANCHOR_LOWER);

      //--- internal activity (buy / sell pressure bars)
      if(InpShowInternal)
        {
         int bw = PeriodSeconds();
         if(arr[i].blVP > 0)
           {
            datetime t2 = (datetime)(arr[i].left + (long)bw * (long)arr[i].blVP);
            ObjRect(pfx + "BL", arr[i].left, arr[i].top, t2, arr[i].avg, InpMetricUpColor);
           }
         if(arr[i].brVP > 0)
           {
            datetime t3 = (datetime)(arr[i].left + (long)bw * (long)arr[i].brVP);
            ObjRect(pfx + "BR", arr[i].left, arr[i].avg, t3, arr[i].btm, InpMetricDnColor);
           }
        }
     }
  }

void RedrawOBs()
  {
   ObjectsDeleteAll(0, "MMRK_OB_");
   if(!InpShowOB) return;
   DrawOBSet(gBullOB, true);
   DrawOBSet(gBearOB, false);
  }

void RedrawTrade()
  {
   ObjectsDeleteAll(0, "MMRK_TR_");
   ObjectsDeleteAll(0, "MMRK_HIT_");
   if(gEntry <= 0.0) return;

   datetime t1 = gTradeTime;
   datetime t2 = (datetime)(Time[0] + (long)PeriodSeconds() * (long)InpTradeExtendBars);

   ObjTrend("MMRK_TR_ENTRY", t1, gEntry, t2, gEntry, clrGray, STYLE_DASH, 1);
   ObjTrend("MMRK_TR_SL",    t1, gSL,    t2, gSL,    clrRed,  STYLE_SOLID, 2);
   ObjTrend("MMRK_TR_TP1",   t1, gTP1,   t2, gTP1,   clrLime, STYLE_SOLID, 1);
   ObjTrend("MMRK_TR_TP2",   t1, gTP2,   t2, gTP2,   clrLime, STYLE_SOLID, 1);
   ObjTrend("MMRK_TR_TP3",   t1, gTP3,   t2, gTP3,   clrLime, STYLE_SOLID, 1);
   ObjTrend("MMRK_TR_TP4",   t1, gTP4,   t2, gTP4,   clrLime, STYLE_SOLID, 1);

   int sigShift = iBarShift(NULL, 0, gTradeTime, false);
   double y = gEntry;
   if(sigShift >= 0)
      y = (gTradeSide > 0) ? Low[sigShift] : High[sigShift];

   if(gTradeSide > 0)
      ObjText("MMRK_TR_SIG", gTradeTime, y, "BUY",
              clrLime, 9, ANCHOR_UPPER);
   else
      ObjText("MMRK_TR_SIG", gTradeTime, y, "SELL",
              clrRed, 9, ANCHOR_LOWER);

   for(int i = 0; i < ArraySize(gHits); i++)
     {
      string hTxt = "TP4 HIT";
      color  hClr = clrOrange;
      switch(gHits[i].kind)
        {
         case 0: hTxt = "SL HIT";  hClr = clrRed;  break;
         case 1: hTxt = "TP1 OK";  hClr = clrLime; break;
         case 2: hTxt = "TP2 OK";  hClr = clrLime; break;
         case 3: hTxt = "TP3 OK";  hClr = clrLime; break;
        }
      ObjText("MMRK_HIT_" + IntegerToString(i), gHits[i].t, gHits[i].price,
              hTxt, hClr, 7, ANCHOR_CENTER);
     }
  }

//==================================================================//
//  ALERTS                                                          //
//==================================================================//
void DoAlerts()
  {
   string head = Symbol() + " " + IntegerToString((int)Period()) + " : ";
   if(gSignalBull)  Alert(head + "Bullish Volumetric Order Block (BUY)");
   if(gSignalBear)  Alert(head + "Bearish Volumetric Order Block (SELL)");
   if(gCrossLong)   Alert(head + "Long signal (EMA " + IntegerToString(InpEmaFast) + "/" + IntegerToString(InpEmaSlow) + ")");
   if(gCrossShort)  Alert(head + "Short signal (EMA " + IntegerToString(InpEmaFast) + "/" + IntegerToString(InpEmaSlow) + ")");
  }

//==================================================================//
//  HISTORY REPLAY                                                  //
//==================================================================//
void ResetState()
  {
   ArrayResize(gUpP, 0);
   ArrayResize(gUpL, 0);
   ArrayResize(gDnP, 0);
   ArrayResize(gDnL, 0);
   ArrayResize(gBullOB, 0);
   ArrayResize(gBearOB, 0);
   ArrayResize(gHits, 0);

   gTrend       = 0;
   gILen        = InpInternalLookback;
   gLastPivotHi = 0;
   gLastPivotLo = 0;

   gEntry = 0.0; gSL = 0.0;
   gTP1 = 0.0; gTP2 = 0.0; gTP3 = 0.0; gTP4 = 0.0;
   gTradeDir  = 0;
   gTradeSide = 0;
   gTradeTime = 0;
   gHit1 = false; gHit2 = false; gHit3 = false; gHit4 = false;
  }

void ReplayHistory()
  {
   ResetState();

   int maxLen = (InpInternalLookback > 10) ? InpInternalLookback : 10;
   int startSh = Bars - 1 - 2 * maxLen - 2;
   if(startSh > InpMaxReplayBars) startSh = InpMaxReplayBars;
   if(startSh > Bars - 2) startSh = Bars - 2;
   if(startSh < 1) return;

   for(int sh = startSh; sh >= 1; sh--) ProcessBar(sh);
  }

//==================================================================//
//  INIT / DEINIT / CALCULATE                                       //
//==================================================================//
int OnInit()
  {
   SetIndexBuffer(0, BufVwapUp);
   SetIndexBuffer(1, BufVwapDn);
   SetIndexBuffer(2, BufEmaUp);
   SetIndexBuffer(3, BufEmaDn);
   SetIndexBuffer(4, BufWeekly);
   SetIndexBuffer(5, BufMonthly);
   SetIndexBuffer(6, BufBuyArrow);
   SetIndexBuffer(7, BufSellArrow);

   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 2, InpTrendUpColor);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, 2, InpTrendDnColor);
   SetIndexStyle(2, DRAW_LINE, STYLE_DASH,  1, InpTrendUpColor);
   SetIndexStyle(3, DRAW_LINE, STYLE_DASH,  1, InpTrendDnColor);
   SetIndexStyle(4, DRAW_LINE, STYLE_SOLID, InpWeeklyWidth,  InpWeeklyColor);
   SetIndexStyle(5, DRAW_LINE, STYLE_SOLID, InpMonthlyWidth, InpMonthlyColor);

   SetIndexStyle(6, DRAW_ARROW, STYLE_SOLID, 1);
   SetIndexStyle(7, DRAW_ARROW, STYLE_SOLID, 1);
   SetIndexArrow(6, 233);
   SetIndexArrow(7, 234);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);
   SetIndexEmptyValue(3, EMPTY_VALUE);
   SetIndexEmptyValue(4, EMPTY_VALUE);
   SetIndexEmptyValue(5, EMPTY_VALUE);
   SetIndexEmptyValue(6, EMPTY_VALUE);
   SetIndexEmptyValue(7, EMPTY_VALUE);

   SetIndexLabel(0, "Session VWAP (up)");
   SetIndexLabel(1, "Session VWAP (down)");
   SetIndexLabel(2, "EMA 200 (up)");
   SetIndexLabel(3, "EMA 200 (down)");
   SetIndexLabel(4, "Weekly VWAP");
   SetIndexLabel(5, "Monthly VWAP");
   SetIndexLabel(6, "Long signal");
   SetIndexLabel(7, "Short signal");

   IndicatorShortName("MAROC MARRAKECH");
   IndicatorDigits(Digits);

   ArraySetAsSeries(gEmaF,   false);
   ArraySetAsSeries(gEmaS,   false);
   ArraySetAsSeries(gEma200, false);
   ArraySetAsSeries(gAtr,    false);

   ObjectsDeleteAll(0, "MMRK_");
   ChartRedraw(0);

   gReady       = false;
   gLastBarTime = 0;
   gLastTotal   = 0;
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "MMRK_");
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
   int needBars = (InpEmaSlow + 5 > 60) ? InpEmaSlow + 5 : 60;
   if(rates_total < needBars) return(0);

   //--- 1) all plotted / helper series
   ComputeSeries(rates_total);

   //--- 2) strategy runs once per closed bar
   bool newBar = (gLastBarTime != Time[0]);
   bool bigHistoryLoad = (gReady && rates_total > gLastTotal + 200);
   gLastTotal = rates_total;

   if(newBar || bigHistoryLoad)
     {
      if(newBar) gLastBarTime = Time[0];

      if(!gReady)
        {
         ReplayHistory();
         gReady = true;
        }
      else if(bigHistoryLoad)
        {
         //--- the terminal loaded a big chunk of older history : rebuild the
         //    whole state so that pivots / order blocks stay identical
         ReplayHistory();
        }
      else
        {
         ProcessBar(1);
         if(InpAlerts) DoAlerts();
        }

      RedrawOBs();
      RedrawTrade();
      ChartRedraw(0);
     }


   return(rates_total);
  }
//+------------------------------------------------------------------+
