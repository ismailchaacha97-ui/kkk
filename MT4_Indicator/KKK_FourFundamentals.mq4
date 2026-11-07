//+------------------------------------------------------------------+
//|                                      KKK_FourFundamentals.mq4    |
//|              4 Fundamental Strategy — Trend / AOI / Structure /  |
//|                     Entry (Engulfing) — MT4 Indicator            |
//|                                                                  |
//|  Strategy Owner: KKK — “Make No Mistake”                         |
//|  Implements exactly:                                             |
//|  1) Trend: HTF (W1 + D1) must be in sync                         |
//|  2) AOI: HTF AOI + LTF AOI (4H/2H/1H) — Break & Retest            |
//|  3) Structure: Head & Shoulder  OR  Break & Retest  + HL/LH      |
//|  4) Entry: ONLY Engulfing on H4/H2/H1 + 2 LTF trends in sync    |
//|                                                                  |
//|  Features:                                                       |
//|  - Multi-TF trend (EMA 50/200 + price structure HH/HL)           |
//|  - Fractal AOI clustering with touch-count strength              |
//|  - Synthetic H2 timeframe (MT4 has no native H2)                 |
//|  - HS / IHS detection + Break-Retest engine                      |
//|  - HL / LH swing entry filter                                    |
//|  - Engulfing detector (body/full + size filter)                  |
//|  - Dashboard + HTF/LTF zone drawing + alerts                     |
//|                                                                  |
//|  Installation: MQL4/Indicators/KKK_FourFundamentals.mq4 ->       |
//|  Compile in MetaEditor (F7) -> Attach to chart -> Allow DLL     |
//|  imports OFF (not needed). Works on any symbol / TF.             |
//+------------------------------------------------------------------+
#property copyright "KKK 4 Fundamentals — Make No Mistake"
#property link      "https://github.com/ismailchaacha97-ui/kkk"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1 Lime
#property indicator_color2 Red
#property indicator_width1 2
#property indicator_width2 2

//--- buffers
double BuySignalBuffer[];
double SellSignalBuffer[];

//--- enums
enum ENUM_TREND_METHOD { TREND_EMA_ONLY=0, TREND_STRUCTURE_ONLY=1, TREND_EMA_AND_STRUCTURE=2 };
enum ENUM_ENGULF_MODE  { ENGULF_BODY_ONLY=0, ENGULF_FULL_CANDLE=1 };

//+------------------------------------------------------------------+
//| Inputs — Fundamental 1 : TREND                                   |
//+------------------------------------------------------------------+
input string            InpHeader_Trend        = "===== 1. FUNDAMENTAL: TREND (HTF W1/D1) ====="; // --- Trend ---
input ENUM_TREND_METHOD InpTrendMethod         = TREND_EMA_AND_STRUCTURE; // Trend detection method
input int               InpEMA_Fast            = 50;   // EMA Fast
input int               InpEMA_Slow            = 200;  // EMA Slow
input int               InpHTF1                = 10080;// HTF 1 (W1=10080)
input int               InpHTF2                = 1440; // HTF 2 (D1=1440)
input bool              InpRequireHTFSync      = true; // Require W1 & D1 in sync?
input int               InpHTF_StructureLookback = 50; // HTF structure lookback (swings)

//+------------------------------------------------------------------+
//| Inputs — Fundamental 2 : AOI                                      |
//+------------------------------------------------------------------+
input string InpHeader_AOI          = "===== 2. FUNDAMENTAL: AOI ====="; // --- AOI ---
input int    InpHTF_AOI_TF          = 1440; // HTF AOI TF (D1=1440 / W1=10080)
input int    InpHTF_AOI_Lookback    = 250;  // HTF AOI lookback bars
input int    InpLTF_AOI_TF1         = 240;  // LTF AOI TF 1 (H4=240)
input int    InpLTF_AOI_TF2         = 60;   // LTF AOI TF 2 (H1=60)
input int    InpLTF_AOI_Lookback    = 150;  // LTF AOI lookback bars
input double InpZoneTolerancePips  = 12;   // Zone cluster tolerance (pips)
input double InpZoneATROn         = 1.0;   // ATR multiplier for tolerance (0=off)
input int    InpMinTouchesHTF     = 2;    // Min touches for HTF AOI (strength)
input int    InpMinTouchesLTF     = 2;    // Min touches for LTF AOI
input int    InpFractalBars       = 2;    // Fractal size (1=3bars, 2=5bars)
input int    InpMaxZonesHTF       = 6;    // Max HTF zones to draw
input int    InpMaxZonesLTF       = 6;    // Max LTF zones to draw
input color  InpColorHTF_Sup      = C'0,80,0';     // HTF Support
input color  InpColorHTF_Res      = C'120,0,0';    // HTF Resistance
input color  InpColorLTF_Sup      = C'0,180,80';   // LTF Support
input color  InpColorLTF_Res      = C'255,60,60';  // LTF Resistance

//+------------------------------------------------------------------+
//| Inputs — Fundamental 3 : STRUCTURE                               |
//+------------------------------------------------------------------+
input string InpHeader_Struct       = "===== 3. FUNDAMENTAL: STRUCTURE ====="; // --- Structure ---
input bool   InpDetectHS            = true;  // Detect Head & Shoulders
input bool   InpDetectBnR            = true;  // Detect Break & Retest
input int    InpHS_Lookback         = 80;    // HS lookback bars
input double InpHS_ShoulderTolerancePct = 15; // Shoulder height tolerance % of head
input double InpHS_NeckTolerancePct     = 12; // Neckline tolerance %
input int    InpBnR_MaxBarsAfterBreak = 25;  // Max bars to retest after break
input double InpBnR_BreakPadPips   = 3;     // Break padding (pips beyond zone)
input int    InpSwingLookbackHL    = 30;    // HL/LH detection lookback
input bool   InpRequireHL_LH       = true;  // Require next HL (buy) / LH (sell)
input bool   InpStrictStructure    = false; // If true: require HS or BnR (ideal); if false: HL/LH alone OK

//+------------------------------------------------------------------+
//| Inputs — Fundamental 4 : ENTRY                                   |
//+------------------------------------------------------------------+
input string InpHeader_Entry        = "===== 4. FUNDAMENTAL: ENTRY ====="; // --- Entry ---
input bool   InpUseEntryTF_H4      = true;  // Entry TF H4
input bool   InpUseEntryTF_H2      = true;  // Entry TF H2 (synthetic)
input bool   InpUseEntryTF_H1      = true;  // Entry TF H1
input bool   InpUseEntryTF_M30     = false; // Also scan M30 for trend sync (not entry)
input ENUM_ENGULF_MODE InpEngulfMode = ENGULF_BODY_ONLY; // Engulfing mode
input double InpEngulfMinBodyRatio = 1.0;  // Current body >= prior* ratio
input double InpEngulfMinBodyATR   = 0.0;  // Min body as ATR* (0=off)
input bool   InpEngulfWickFilter  = false; // Require body > wick
input bool   InpRequireTwoLTFTrendSync = true; // Require 2 LTF trends in sync
input int    InpLTF_Trend_TF1      = 30;   // LTF Trend TF1 (M30)
input int    InpLTF_Trend_TF2      = 60;   // LTF Trend TF2 (H1)
input int    InpLTF_Trend_TF3      = 120;  // LTF Trend TF3 (H2)
input int    InpLTF_Trend_TF4      = 240;  // LTF Trend TF4 (H4)
input bool   InpDoNotEnterAboveAOI = true; // Enforce: do not enter above LTF AOI
input double InpMaxDistanceAbovePips = 20; // Max distance above LTF AOI allowed
input bool   InpEntryOnClosedBar  = true;  // Signal only on bar close (shift 1)
input bool   InpEntryOnCurrentBar = false; // Also alert on forming bar 0

//+------------------------------------------------------------------+
//| Inputs — Display & Alerts                                        |
//+------------------------------------------------------------------+
input string InpHeader_Display      = "===== DISPLAY & ALERTS ====="; // --- Display ---
input bool   InpShowDashboard     = true; // Show dashboard
input bool   InpShowHTFZones      = true; // Draw HTF AOI zones
input bool   InpShowLTFZones      = true; // Draw LTF AOI zones
input bool   InpShowStructureMarkers = true; // Mark HS / BnR
input bool   InpShowArrows        = true; // Show Buy/Sell arrows
input int    InpArrowOffsetATR    = 1;    // Arrow offset (ATR * 0.5)
input bool   InpAlertPopup        = true; // Popup alert
input bool   InpAlertPush         = false;// Push notification
input bool   InpAlertEmail        = false;// Email
input bool   InpAlertSound        = false;// Play sound
input string InpSoundFile         = "alert.wav";
input bool   InpDebugLog          = false;// Verbose logs

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
#define OBJ_PREFIX "KKK4F_"
#define SYNTH_H2 120

// synthetic H2 storage: index 0 = newest (like MT4)
datetime H2Time[];
double   H2Open[];
double   H2High[];
double   H2Low[];
double   H2Close[];
int      H2BarsCount = 0;
datetime LastH1BarTime = 0;
datetime LastCalcTime = 0;

// AOI zone struct
struct AOIZone
{
   double   high;
   double   low;
   double   center;
   double   top; //alias high
   double   bottom; //low
   int      touches;
   int      type; // +1 resistance (supply), -1 support (demand)
   datetime firstTime;
   datetime lastTime;
   int      strength; // touches
   int      tf;
   bool     isHTF;
};

// swing point
struct SwingPoint
{
   double   price;
   datetime time;
   int      shift;
   int      type; // +1 high, -1 low
   int      tf;
};

// dashboard state
int      HTF_Trend_W1 = 0;
int      HTF_Trend_D1 = 0;
int      LTF_Trends[4];
string   LastSignal = "NONE";
datetime LastSignalTime = 0;

// zones cache
AOIZone HTF_Zones[];
AOIZone LTF_Zones[];

//+------------------------------------------------------------------+
//| Helpers: pip & point                                             |
//+------------------------------------------------------------------+
double GetPipValue()
{
   double pt = MarketInfo(Symbol(), MODE_POINT);
   int dg = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(dg==3 || dg==5) return(pt*10);
   return(pt);
}
double PipsToPrice(double pips) { return(pips * GetPipValue()); }
double PriceToPips(double priceDiff) { double pip=GetPipValue(); if(pip==0) return(0); return(priceDiff/pip); }

//+------------------------------------------------------------------+
//| Synthetic H2 builder                                             |
//+------------------------------------------------------------------+
void BuildSyntheticH2()
{
   int h1Total = iBars(Symbol(), PERIOD_H1);
   if(h1Total < 10) { H2BarsCount=0; return; }

   // allocate worst case
   ArrayResize(H2Time,  h1Total);
   ArrayResize(H2Open,  h1Total);
   ArrayResize(H2High,  h1Total);
   ArrayResize(H2Low,   h1Total);
   ArrayResize(H2Close, h1Total);
   ArrayInitialize(H2Time, 0);
   ArrayInitialize(H2Open, 0);
   ArrayInitialize(H2High, 0);
   ArrayInitialize(H2Low,  0);
   ArrayInitialize(H2Close,0);

   // We will group H1 bars into 2-hour blocks aligned to even hours (00,02,04...)
   // Iterate from oldest to newest, aggregating blocks.
   int h2Idx = 0;
   datetime curBlock = 0;
   double curO=0, curH=0, curL=0, curC=0;
   bool hasBlock=false;

   for(int i = h1Total-1; i>=0; i--) // oldest -> newest
   {
      datetime t = iTime(Symbol(), PERIOD_H1, i);
      if(t==0) continue;
      int hr = TimeHour(t);
      int mn = TimeMinute(t);
      int sc = TimeSeconds(t);
      // floor to even hour
      datetime blockTime = t - (hr%2)*3600 - mn*60 - sc;
      double o = iOpen(Symbol(), PERIOD_H1, i);
      double h = iHigh(Symbol(), PERIOD_H1, i);
      double l = iLow(Symbol(), PERIOD_H1, i);
      double c = iClose(Symbol(), PERIOD_H1, i);

      if(!hasBlock || blockTime != curBlock)
      {
         if(hasBlock)
         {
            H2Time[h2Idx]  = curBlock;
            H2Open[h2Idx]  = curO;
            H2High[h2Idx]  = curH;
            H2Low[h2Idx]   = curL;
            H2Close[h2Idx] = curC;
            h2Idx++;
         }
         curBlock = blockTime;
         curO = o; curH = h; curL = l; curC = c;
         hasBlock = true;
      }
      else
      {
         // same 2H block — merge
         // open stays first, high/low expand, close becomes newest
         curH = MathMax(curH, h);
         curL = MathMin(curL, l);
         curC = c;
      }
   }
   if(hasBlock)
   {
      H2Time[h2Idx]  = curBlock;
      H2Open[h2Idx]  = curO;
      H2High[h2Idx]  = curH;
      H2Low[h2Idx]   = curL;
      H2Close[h2Idx] = curC;
      h2Idx++;
   }

   // Now arrays are oldest->newest (0 oldest). Reverse to MT4 style 0=newest
   H2BarsCount = h2Idx;
   // temporary reverse
   for(int i=0; i<H2BarsCount/2; i++)
   {
      int j = H2BarsCount-1 - i;
      datetime tmpT = H2Time[i]; H2Time[i]=H2Time[j]; H2Time[j]=tmpT;
      double tmpO = H2Open[i]; H2Open[i]=H2Open[j]; H2Open[j]=tmpO;
      double tmpH = H2High[i]; H2High[i]=H2High[j]; H2High[j]=tmpH;
      double tmpL = H2Low[i];  H2Low[i]=H2Low[j];   H2Low[j]=tmpL;
      double tmpC = H2Close[i]; H2Close[i]=H2Close[j]; H2Close[j]=tmpC;
   }
   ArrayResize(H2Time,  H2BarsCount);
   ArrayResize(H2Open,  H2BarsCount);
   ArrayResize(H2High,  H2BarsCount);
   ArrayResize(H2Low,   H2BarsCount);
   ArrayResize(H2Close, H2BarsCount);
}

// wrappers for synthetic-aware market data
int iBarsEx(string sym, int tf)
{
   if(tf==SYNTH_H2) return(H2BarsCount);
   return(iBars(sym, tf));
}
datetime iTimeEx(string sym, int tf, int shift)
{
   if(tf==SYNTH_H2)
   {
      if(shift<0 || shift>=H2BarsCount) return(0);
      return(H2Time[shift]);
   }
   return(iTime(sym, tf, shift));
}
double iOpenEx(string sym, int tf, int shift)
{
   if(tf==SYNTH_H2)
   {
      if(shift<0 || shift>=H2BarsCount) return(0);
      return(H2Open[shift]);
   }
   return(iOpen(sym, tf, shift));
}
double iHighEx(string sym, int tf, int shift)
{
   if(tf==SYNTH_H2)
   {
      if(shift<0 || shift>=H2BarsCount) return(0);
      return(H2High[shift]);
   }
   return(iHigh(sym, tf, shift));
}
double iLowEx(string sym, int tf, int shift)
{
   if(tf==SYNTH_H2)
   {
      if(shift<0 || shift>=H2BarsCount) return(0);
      return(H2Low[shift]);
   }
   return(iLow(sym, tf, shift));
}
double iCloseEx(string sym, int tf, int shift)
{
   if(tf==SYNTH_H2)
   {
      if(shift<0 || shift>=H2BarsCount) return(0);
      return(H2Close[shift]);
   }
   return(iClose(sym, tf, shift));
}
double iATRex(string sym, int tf, int period, int shift)
{
   if(tf==SYNTH_H2)
   {
      // compute ATR manually over synthetic
      if(H2BarsCount < period+5) return(0);
      double sum=0;
      for(int i=shift; i<shift+period && i+1<H2BarsCount; i++)
      {
         double tr = MathMax(H2High[i]-H2Low[i], MathMax(MathAbs(H2High[i]-H2Close[i+1]), MathAbs(H2Low[i]-H2Close[i+1])));
         sum+=tr;
      }
      return(sum/period);
   }
   return(iATR(sym, tf, period, shift));
}

// EMA for synthetic
double GetEMAEx(string sym, int tf, int period, int shift)
{
   if(tf!=SYNTH_H2)
   {
      return(iMA(sym, tf, period, 0, MODE_EMA, PRICE_CLOSE, shift));
   }
   // synthetic EMA
   if(H2BarsCount < period+10) return(0);
   // build closes newest->oldest; we have H2Close[0]=newest
   // Need EMA array newest->oldest but calc from oldest forward
   // Create temp array oldest->newest
   int total = H2BarsCount;
   // we compute EMA up to required shift
   // Use iterative from oldest
   double k = 2.0/(period+1.0);
   // SMA of oldest period bars as seed
   int oldestIdx = total-1;
   // compute seed: average of oldest 'period' closes
   double sma=0;
   for(int i=0; i<period; i++)
   {
      int idx = oldestIdx - i;
      if(idx<0 || idx>=total) break;
      sma += H2Close[idx];
   }
   sma/=period;
   // build EMA array oldest->newest
   double ema = sma;
   // map: we have index mapping: position in oldest->newest order = total-1 - shiftMT4
   // Instead compute EMA sequentially from oldest period to newest
   // We'll iterate from oldest+period to newest (index decreasing in MT4 terms)
   // Let's create array emaByMT4Shift size total
   double emaByShift[];
   ArrayResize(emaByShift, total);
   ArrayInitialize(emaByShift, 0);
   // start from oldest
   for(int mtfShift = total-1; mtfShift>=0; mtfShift--)
   {
      // mtfShift is MT4 shift (0 newest)
      int seq = total-1 - mtfShift; // 0 oldest sequential
      double close = H2Close[mtfShift];
      if(seq < period-1)
      {
         // before seed complete, just use SMA seed later
         if(seq==period-1) ema = sma;
         else ema = close; // placeholder
      }
      else if(seq==period-1)
      {
         ema = sma;
      }
      else
      {
         ema = close*k + ema*(1-k);
      }
      emaByShift[mtfShift]=ema;
   }
   if(shift<0 || shift>=total) return(0);
   return(emaByShift[shift]);
}

// Generic OHLC arrays for a TF
void GetOHLCArrays(int tf, int need, double &opens[], double &highs[], double &lows[], double &closes[], datetime &times[])
{
   int bars = iBarsEx(Symbol(), tf);
   int n = MathMin(need, bars);
   ArrayResize(opens, n); ArrayResize(highs,n); ArrayResize(lows,n); ArrayResize(closes,n); ArrayResize(times,n);
   for(int i=0; i<n; i++)
   {
      opens[i]  = iOpenEx(Symbol(), tf, i);
      highs[i]  = iHighEx(Symbol(), tf, i);
      lows[i]   = iLowEx(Symbol(), tf, i);
      closes[i] = iCloseEx(Symbol(), tf, i);
      times[i]  = iTimeEx(Symbol(), tf, i);
   }
}

//+------------------------------------------------------------------+
//| Fractal swing detection                                          |
//+------------------------------------------------------------------+
bool IsSwingHighTF(int tf, int shift)
{
   int fb = InpFractalBars;
   double h0 = iHighEx(Symbol(), tf, shift);
   if(h0==0) return(false);
   for(int i=1; i<=fb; i++)
   {
      double hl = iHighEx(Symbol(), tf, shift+i);
      double hr = iHighEx(Symbol(), tf, shift-i);
      if(hl==0 || hr==0) return(false);
      if(h0 <= hl || h0 <= hr) return(false);
      // strict > to avoid plateaus; allow equal? we require >
   }
   return(true);
}
bool IsSwingLowTF(int tf, int shift)
{
   int fb = InpFractalBars;
   double l0 = iLowEx(Symbol(), tf, shift);
   if(l0==0) return(false);
   for(int i=1; i<=fb; i++)
   {
      double ll = iLowEx(Symbol(), tf, shift+i);
      double lr = iLowEx(Symbol(), tf, shift-i);
      if(ll==0 || lr==0) return(false);
      if(l0 >= ll || l0 >= lr) return(false);
   }
   return(true);
}

// collect swing points for a TF
int CollectSwings(int tf, int lookback, SwingPoint &swings[])
{
   ArrayResize(swings,0);
   int bars = iBarsEx(Symbol(), tf);
   int n = MathMin(lookback, bars-5);
   if(n<10) return(0);
   // iterate shift from n down to fb to get chronological but we will sort later
   for(int s=2; s<n-2; s++)
   {
      if(IsSwingHighTF(tf,s))
      {
         int sz=ArraySize(swings);
         ArrayResize(swings, sz+1);
         swings[sz].price = iHighEx(Symbol(), tf, s);
         swings[sz].time  = iTimeEx(Symbol(), tf, s);
         swings[sz].shift = s;
         swings[sz].type  = 1;
         swings[sz].tf    = tf;
      }
      else if(IsSwingLowTF(tf,s))
      {
         int sz=ArraySize(swings);
         ArrayResize(swings, sz+1);
         swings[sz].price = iLowEx(Symbol(), tf, s);
         swings[sz].time  = iTimeEx(Symbol(), tf, s);
         swings[sz].shift = s;
         swings[sz].type  = -1;
         swings[sz].tf    = tf;
      }
   }
   // sort by time ascending (oldest first) — swings currently newest? Actually s increasing is older? In MT4 shift 0 newest, so larger shift older.
   // Our loop s=2..n-2 where n is older, so we inserted from newer to older — not sorted.
   // Sort by time ascending
   for(int i=0; i<ArraySize(swings); i++)
      for(int j=i+1; j<ArraySize(swings); j++)
         if(swings[i].time > swings[j].time)
         {
            SwingPoint tmp=swings[i]; swings[i]=swings[j]; swings[j]=tmp;
         }
   return(ArraySize(swings));
}

//+------------------------------------------------------------------+
//| Trend detection                                                  |
//+------------------------------------------------------------------+
int GetTrendEMA(int tf)
{
   double emaFast0, emaSlow0, emaFast1, emaSlow1;
   if(tf==SYNTH_H2)
   {
      emaFast0 = GetEMAEx(Symbol(), tf, InpEMA_Fast, 0);
      emaSlow0 = GetEMAEx(Symbol(), tf, InpEMA_Slow, 0);
      emaFast1 = GetEMAEx(Symbol(), tf, InpEMA_Fast, 5);
      emaSlow1 = GetEMAEx(Symbol(), tf, InpEMA_Slow, 5);
   }
   else
   {
      emaFast0 = iMA(Symbol(), tf, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 0);
      emaSlow0 = iMA(Symbol(), tf, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 0);
      emaFast1 = iMA(Symbol(), tf, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE, 5);
      emaSlow1 = iMA(Symbol(), tf, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE, 5);
   }
   if(emaFast0==0 || emaSlow0==0) return(0);
   double diff0 = emaFast0-emaSlow0;
   double diff1 = emaFast1-emaSlow1;
   double pip = GetPipValue();
   double threshold = PipsToPrice(5); // 5 pips dead zone
   // bullish if fast above slow and expanding or stable
   if(diff0 > threshold) return(1);
   if(diff0 < -threshold) return(-1);
   return(0);
}
int GetTrendStructure(int tf, int lookback)
{
   SwingPoint swings[];
   int cnt = CollectSwings(tf, lookback, swings);
   if(cnt < 4) return(0);
   // extract last 2 highs and 2 lows in chronological order
   double lastHigh=0, prevHigh=0, lastLow=0, prevLow=0;
   int highCount=0, lowCount=0;
   // iterate from newest backwards (end of array is newest)
   for(int i=ArraySize(swings)-1; i>=0; i--)
   {
      if(swings[i].type==1 && highCount<2)
      {
         if(highCount==0) lastHigh=swings[i].price;
         else prevHigh=swings[i].price;
         highCount++;
      }
      if(swings[i].type==-1 && lowCount<2)
      {
         if(lowCount==0) lastLow=swings[i].price;
         else prevLow=swings[i].price;
         lowCount++;
      }
      if(highCount==2 && lowCount==2) break;
   }
   if(highCount<2 || lowCount<2) return(0);
   bool hh = (lastHigh > prevHigh);
   bool hl = (lastLow  > prevLow);
   bool ll = (lastLow  < prevLow);
   bool lh = (lastHigh < prevHigh);
   if(hh && hl) return(1);
   if(ll && lh) return(-1);
   // if structure bullish bias but not both, check close vs swings
   double close = iCloseEx(Symbol(), tf, 0);
   if(close > lastHigh && hl) return(1);
   if(close < lastLow  && lh) return(-1);
   return(0);
}
int GetTrend(int tf)
{
   int emaTrend = GetTrendEMA(tf);
   int structTrend = GetTrendStructure(tf, InpHTF_StructureLookback);
   if(InpTrendMethod==TREND_EMA_ONLY) return(emaTrend);
   if(InpTrendMethod==TREND_STRUCTURE_ONLY) return(structTrend);
   // combined: both must agree for strong, else take EMA if structure neutral, else structure if EMA neutral
   if(emaTrend!=0 && structTrend!=0)
   {
      if(emaTrend==structTrend) return(emaTrend);
      else return(0); // conflict = neutral
   }
   if(emaTrend!=0) return(emaTrend);
   return(structTrend);
}

//+------------------------------------------------------------------+
//| AOI detection — clustering                                       |
//+------------------------------------------------------------------+
void ClusterLevels(double &levels[], double tolerance, double &centers[], int &counts[], double &zoneHighs[], double &zoneLows[])
{
   int n = ArraySize(levels);
   if(n==0) return;
   // sort ascending
   for(int i=0; i<n; i++)
      for(int j=i+1; j<n; j++)
         if(levels[i] > levels[j])
         {
            double tmp=levels[i]; levels[i]=levels[j]; levels[j]=tmp;
         }
   // group
   ArrayResize(centers,0); ArrayResize(counts,0); ArrayResize(zoneHighs,0); ArrayResize(zoneLows,0);
   int idx=0;
   while(idx<n)
   {
      double groupMin = levels[idx];
      double groupMax = levels[idx];
      double sum = levels[idx];
      int cnt=1;
      int j=idx+1;
      while(j<n && (levels[j] - groupMax) <= tolerance)
      {
         groupMax = levels[j];
         sum += levels[j];
         cnt++;
         j++;
      }
      double center = sum/cnt;
      double pad = tolerance*0.4;
      double zh = groupMax + pad;
      double zl = groupMin - pad;
      int sz=ArraySize(centers);
      ArrayResize(centers, sz+1); ArrayResize(counts, sz+1); ArrayResize(zoneHighs, sz+1); ArrayResize(zoneLows, sz+1);
      centers[sz]=center; counts[sz]=cnt; zoneHighs[sz]=zh; zoneLows[sz]=zl;
      idx=j;
   }
}

int DetectAOIZones(int tf, int lookback, int minTouches, bool isHTF, AOIZone &zones[])
{
   ArrayResize(zones,0);
   int bars = iBarsEx(Symbol(), tf);
   if(bars < lookback+10) lookback = bars-10;
   if(lookback<30) return(0);

   double pip = GetPipValue();
   double atrTolerance = 0;
   if(InpZoneATROn>0)
   {
      double atr = iATRex(Symbol(), tf, 14, 1);
      atrTolerance = atr * InpZoneATROn * 0.3;
   }
   double pipTolerance = InpZoneTolerancePips * pip;
   double tolerance = MathMax(pipTolerance, atrTolerance);
   if(tolerance==0) tolerance = pipTolerance;

   // collect fractal levels
   double highLevels[]; ArrayResize(highLevels,0);
   double lowLevels[];  ArrayResize(lowLevels,0);
   // also collect times for matching later? For AOI firstTime we will find earliest fractal in cluster.
   // Collect swings with time
   SwingPoint swings[];
   CollectSwings(tf, lookback, swings);
   for(int i=0; i<ArraySize(swings); i++)
   {
      if(swings[i].type==1) { int sz=ArraySize(highLevels); ArrayResize(highLevels, sz+1); highLevels[sz]=swings[i].price; }
      else { int sz=ArraySize(lowLevels); ArrayResize(lowLevels, sz+1); lowLevels[sz]=swings[i].price; }
   }
   // cluster highs (resistance)
   double rCenters[], rHighs[], rLows[]; int rCounts[];
   ClusterLevels(highLevels, tolerance, rCenters, rCounts, rHighs, rLows);
   for(int i=0; i<ArraySize(rCenters); i++)
   {
      if(rCounts[i] < minTouches) continue;
      int sz=ArraySize(zones);
      ArrayResize(zones, sz+1);
      zones[sz].high = rHighs[i];
      zones[sz].low  = rLows[i];
      zones[sz].center = rCenters[i];
      zones[sz].top = rHighs[i];
      zones[sz].bottom = rLows[i];
      zones[sz].touches = rCounts[i];
      zones[sz].type = 1; // resistance
      zones[sz].strength = rCounts[i];
      zones[sz].tf = tf;
      zones[sz].isHTF = isHTF;
      // find first/last time of levels in this cluster (approx)
      zones[sz].firstTime = iTimeEx(Symbol(), tf, lookback);
      zones[sz].lastTime  = iTimeEx(Symbol(), tf, 1);
      // try to locate precise first touch
      for(int s=0; s<ArraySize(swings); s++) if(swings[s].type==1 && swings[s].price>=rLows[i] && swings[s].price<=rHighs[i]) { zones[sz].firstTime=swings[s].time; break; }
      for(int s=ArraySize(swings)-1; s>=0; s--) if(swings[s].type==1 && swings[s].price>=rLows[i] && swings[s].price<=rHighs[i]) { zones[sz].lastTime=swings[s].time; break; }
   }
   // cluster lows (support)
   double sCenters[], sHighs[], sLows[]; int sCounts[];
   ClusterLevels(lowLevels, tolerance, sCenters, sCounts, sHighs, sLows);
   for(int i=0; i<ArraySize(sCenters); i++)
   {
      if(sCounts[i] < minTouches) continue;
      int sz=ArraySize(zones);
      ArrayResize(zones, sz+1);
      zones[sz].high = sHighs[i];
      zones[sz].low  = sLows[i];
      zones[sz].center = sCenters[i];
      zones[sz].top = sHighs[i];
      zones[sz].bottom = sLows[i];
      zones[sz].touches = sCounts[i];
      zones[sz].type = -1;
      zones[sz].strength = sCounts[i];
      zones[sz].tf = tf;
      zones[sz].isHTF = isHTF;
      zones[sz].firstTime = iTimeEx(Symbol(), tf, lookback);
      zones[sz].lastTime  = iTimeEx(Symbol(), tf, 1);
      for(int s=0; s<ArraySize(swings); s++) if(swings[s].type==-1 && swings[s].price>=sLows[i] && swings[s].price<=sHighs[i]) { zones[sz].firstTime=swings[s].time; break; }
      for(int s=ArraySize(swings)-1; s>=0; s--) if(swings[s].type==-1 && swings[s].price>=sLows[i] && swings[s].price<=sHighs[i]) { zones[sz].lastTime=swings[s].time; break; }
   }

   // secondary wick touch counting: iterate all bars, count additional touches where high/low entered zone
   for(int z=0; z<ArraySize(zones); z++)
   {
      int extra=0;
      for(int b=1; b<lookback; b++)
      {
         double h = iHighEx(Symbol(), tf, b);
         double l = iLowEx(Symbol(), tf, b);
         bool inside = (h>=zones[z].low && h<=zones[z].high) || (l>=zones[z].low && l<=zones[z].high) || (l<=zones[z].low && h>=zones[z].high);
         if(inside)
         {
            // avoid double counting fractals already counted; we approximate by checking if bar is not already a swing we counted?
            // just count wick rejections: close on opposite side
            double o=iOpenEx(Symbol(), tf,b), c=iCloseEx(Symbol(), tf,b);
            if(zones[z].type==1) { if(c < zones[z].low) extra++; } // rejection from resistance
            else { if(c > zones[z].high) extra++; }
         }
      }
      zones[z].touches += (int)(extra*0.5); // weighted
      zones[z].strength = zones[z].touches;
   }

   // filter max zones: keep strongest / closest to price
   // sort by touches descending, then distance ascending
   double price = iCloseEx(Symbol(), tf, 0);
   for(int i=0; i<ArraySize(zones); i++)
      for(int j=i+1; j<ArraySize(zones); j++)
      {
         bool swap=false;
         if(zones[j].touches > zones[i].touches) swap=true;
         else if(zones[j].touches==zones[i].touches)
         {
            double distI = MathAbs(price - zones[i].center);
            double distJ = MathAbs(price - zones[j].center);
            if(distJ < distI) swap=true;
         }
         if(swap) { AOIZone tmp=zones[i]; zones[i]=zones[j]; zones[j]=tmp; }
      }

   int maxKeep = isHTF ? InpMaxZonesHTF : InpMaxZonesLTF;
   if(ArraySize(zones) > maxKeep) ArrayResize(zones, maxKeep);

   // also sort by price descending for display? Keep as is
   return(ArraySize(zones));
}

// check if price is inside zone (with padding)
bool PriceInZone(double price, double high, double low, double pad)
{
   return(price >= low - pad && price <= high + pad);
}
bool BarTouchesZone(int tf, int shift, AOIZone &z, double pad)
{
   double h=iHighEx(Symbol(), tf, shift);
   double l=iLowEx(Symbol(), tf, shift);
   if(h==0||l==0) return(false);
   // overlap
   return( (h>=z.low-pad && h<=z.high+pad) || (l>=z.low-pad && l<=z.high+pad) || (l<=z.low && h>=z.high) );
}
int FindTouchingZone(double price, AOIZone &zones[], int typeFilter) // typeFilter 0=any, 1=res, -1=sup
{
   double pad = PipsToPrice(3);
   for(int i=0; i<ArraySize(zones); i++)
   {
      if(typeFilter!=0 && zones[i].type != typeFilter) continue;
      if(price >= zones[i].low - pad && price <= zones[i].high + pad) return(i);
      // also check close proximity (within 1 ATR)
      double atr = iATRex(Symbol(), zones[i].tf, 14, 0);
      double prox = MathMax(atr*0.2, PipsToPrice(8));
      if(MathAbs(price - zones[i].center) <= prox) return(i);
   }
   return(-1);
}

//+------------------------------------------------------------------+
//| HL / LH detection                                                |
//+------------------------------------------------------------------+
bool IsNextHL(int tf)
{
   SwingPoint swings[];
   CollectSwings(tf, InpSwingLookbackHL+20, swings);
   double lastLow=0, prevLow=0;
   int found=0;
   for(int i=ArraySize(swings)-1; i>=0; i--)
   {
      if(swings[i].type==-1)
      {
         if(found==0) lastLow=swings[i].price;
         else if(found==1) { prevLow=swings[i].price; break; }
         found++;
      }
   }
   if(found<2) return(false);
   return(lastLow > prevLow);
}
bool IsNextLH(int tf)
{
   SwingPoint swings[];
   CollectSwings(tf, InpSwingLookbackHL+20, swings);
   double lastHigh=0, prevHigh=0;
   int found=0;
   for(int i=ArraySize(swings)-1; i>=0; i--)
   {
      if(swings[i].type==1)
      {
         if(found==0) lastHigh=swings[i].price;
         else if(found==1) { prevHigh=swings[i].price; break; }
         found++;
      }
   }
   if(found<2) return(false);
   return(lastHigh < prevHigh);
}

//+------------------------------------------------------------------+
//| Head & Shoulders detection                                       |
//+------------------------------------------------------------------+
bool DetectHeadAndShoulders(int tf, int lookback, bool bullishInverse, double &neckline, double &patternHigh, double &patternLow)
{
   SwingPoint swings[];
   CollectSwings(tf, lookback, swings);
   if(ArraySize(swings) < 5) return(false);
   // For bearish HS we need pattern of 5 alternating: High Low High Low High
   // For bullish IHS: Low High Low High Low
   for(int i=0; i<=ArraySize(swings)-5; i++)
   {
      // window of 5
      SwingPoint p0=swings[i], p1=swings[i+1], p2=swings[i+2], p3=swings[i+3], p4=swings[i+4];
      if(!bullishInverse)
      {
         // bearish: H L H L H
         if(p0.type!=1 || p1.type!=-1 || p2.type!=1 || p3.type!=-1 || p4.type!=1) continue;
         double LS=p0.price, LV1=p1.price, Head=p2.price, LV2=p3.price, RS=p4.price;
         if(Head <= LS || Head <= RS) continue;
         double headNeckDist = Head - MathMin(LV1,LV2);
         if(headNeckDist<=0) continue;
         double shoulderDiff = MathAbs(LS-RS);
         double neckDiff = MathAbs(LV1-LV2);
         double shoulderTol = headNeckDist * InpHS_ShoulderTolerancePct/100.0;
         double neckTol = headNeckDist * InpHS_NeckTolerancePct/100.0;
         if(shoulderDiff > shoulderTol) continue;
         if(neckDiff > neckTol) continue;
         // head must be significantly higher than shoulders
         if( (Head-LS) < headNeckDist*0.3 ) continue;
         if( (Head-RS) < headNeckDist*0.3 ) continue;
         neckline = (LV1+LV2)/2.0;
         patternHigh = Head;
         patternLow = neckline;
         // check that after RS, price has not gone far beyond? But we just detect pattern existence
         return(true);
      }
      else
      {
         // bullish inverse: L H L H L
         if(p0.type!=-1 || p1.type!=1 || p2.type!=-1 || p3.type!=1 || p4.type!=-1) continue;
         double LS=p0.price, PK1=p1.price, Head=p2.price, PK2=p3.price, RS=p4.price;
         if(Head >= LS || Head >= RS) continue;
         double headNeckDist = MathMax(PK1,PK2) - Head;
         if(headNeckDist<=0) continue;
         double shoulderDiff = MathAbs(LS-RS);
         double neckDiff = MathAbs(PK1-PK2);
         double shoulderTol = headNeckDist * InpHS_ShoulderTolerancePct/100.0;
         double neckTol = headNeckDist * InpHS_NeckTolerancePct/100.0;
         if(shoulderDiff > shoulderTol) continue;
         if(neckDiff > neckTol) continue;
         if( (LS-Head) < headNeckDist*0.3 ) continue;
         if( (RS-Head) < headNeckDist*0.3 ) continue;
         neckline = (PK1+PK2)/2.0;
         patternLow = Head;
         patternHigh = neckline;
         return(true);
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Break & Retest detection                                         |
//+------------------------------------------------------------------+
bool IsBreakAndRetest(int tf, AOIZone &z, bool bullish, int maxBars)
{
   // bullish: was resistance, broke above, then retested as support
   // bearish: was support, broke below, then retested as resistance
   double pad = PipsToPrice(InpBnR_BreakPadPips);
   int bars = iBarsEx(Symbol(), tf);
   int checkBars = MathMin(maxBars, bars-2);
   // step 1: find most recent break bar within checkBars
   int breakShift = -1;
   for(int s=1; s<checkBars; s++)
   {
      double close = iCloseEx(Symbol(), tf, s);
      double prevClose = iCloseEx(Symbol(), tf, s+1);
      if(bullish)
      {
         if(prevClose <= z.high && close > z.high + pad)
         {
            breakShift = s;
            break;
         }
      }
      else
      {
         if(prevClose >= z.low && close < z.low - pad)
         {
            breakShift = s;
            break;
         }
      }
   }
   if(breakShift==-1) return(false);
   // step 2: after break (more recent bars 1..breakShift-1), find retest bar where wick touches zone
   for(int s=1; s<breakShift; s++)
   {
      double h = iHighEx(Symbol(), tf, s);
      double l = iLowEx(Symbol(), tf, s);
      double c = iCloseEx(Symbol(), tf, s);
      double o = iOpenEx(Symbol(), tf, s);
      if(bullish)
      {
         // retest from above: low touches zone top area
         if(l <= z.high + pad && l >= z.low - pad*2)
         {
            // bullish reversal: close above open or above zone
            if(c > o && c > z.high - pad)
               return(true);
            // also allow hammer / close near high
            if(c > (h+l)/2) return(true);
         }
      }
      else
      {
         if(h >= z.low - pad && h <= z.high + pad*2)
         {
            if(c < o && c < z.low + pad)
               return(true);
            if(c < (h+l)/2) return(true);
         }
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Engulfing detection                                              |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(int tf, int shift)
{
   double o1 = iOpenEx(Symbol(), tf, shift+1);
   double c1 = iCloseEx(Symbol(), tf, shift+1);
   double o0 = iOpenEx(Symbol(), tf, shift);
   double c0 = iCloseEx(Symbol(), tf, shift);
   double h1 = iHighEx(Symbol(), tf, shift+1);
   double l1 = iLowEx(Symbol(), tf, shift+1);
   double h0 = iHighEx(Symbol(), tf, shift);
   double l0 = iLowEx(Symbol(), tf, shift);
   if(o1==0||c1==0||o0==0||c0==0) return(false);
   // prior bearish, current bullish
   if(!(c1 < o1 && c0 > o0)) return(false);
   // avoid doji prior: body must be meaningful
   double body1 = MathAbs(c1-o1);
   double body0 = MathAbs(c0-o0);
   double pip = GetPipValue();
   if(body1 < PipsToPrice(2)) return(false);
   if(InpEngulfMinBodyRatio>0 && body0 < body1 * InpEngulfMinBodyRatio) return(false);
   // ATR filter
   if(InpEngulfMinBodyATR>0)
   {
      double atr = iATRex(Symbol(), tf, 14, shift+1);
      if(body0 < atr * InpEngulfMinBodyATR) return(false);
   }
   if(InpEngulfWickFilter)
   {
      double upperWick0 = h0 - MathMax(o0,c0);
      double lowerWick0 = MathMin(o0,c0) - l0;
      if(body0 <= upperWick0 || body0 <= lowerWick0) return(false);
   }
   if(InpEngulfMode==ENGULF_BODY_ONLY)
   {
      if(o0 <= c1 && c0 >= o1) return(true); // allow equal with tolerance 1 pip
      if(o0 <= c1 + pip && c0 >= o1 - pip) return(true);
   }
   else
   {
      // full candle engulf
      if(h0 >= h1 && l0 <= l1 && o0 <= c1 && c0 >= o1) return(true);
      if(o0 <= c1 && c0 >= o1 && body0 > body1) return(true);
   }
   return(false);
}
bool IsBearishEngulfing(int tf, int shift)
{
   double o1 = iOpenEx(Symbol(), tf, shift+1);
   double c1 = iCloseEx(Symbol(), tf, shift+1);
   double o0 = iOpenEx(Symbol(), tf, shift);
   double c0 = iCloseEx(Symbol(), tf, shift);
   double h1 = iHighEx(Symbol(), tf, shift+1);
   double l1 = iLowEx(Symbol(), tf, shift+1);
   double h0 = iHighEx(Symbol(), tf, shift);
   double l0 = iLowEx(Symbol(), tf, shift);
   if(o1==0||c1==0||o0==0||c0==0) return(false);
   if(!(c1 > o1 && c0 < o0)) return(false);
   double body1 = MathAbs(c1-o1);
   double body0 = MathAbs(c0-o0);
   double pip = GetPipValue();
   if(body1 < PipsToPrice(2)) return(false);
   if(InpEngulfMinBodyRatio>0 && body0 < body1 * InpEngulfMinBodyRatio) return(false);
   if(InpEngulfMinBodyATR>0)
   {
      double atr = iATRex(Symbol(), tf, 14, shift+1);
      if(body0 < atr * InpEngulfMinBodyATR) return(false);
   }
   if(InpEngulfWickFilter)
   {
      double upperWick0 = h0 - MathMax(o0,c0);
      double lowerWick0 = MathMin(o0,c0) - l0;
      if(body0 <= upperWick0 || body0 <= lowerWick0) return(false);
   }
   if(InpEngulfMode==ENGULF_BODY_ONLY)
   {
      if(o0 >= c1 && c0 <= o1) return(true);
      if(o0 >= c1 - pip && c0 <= o1 + pip) return(true);
   }
   else
   {
      if(h0 >= h1 && l0 <= l1 && o0 >= c1 && c0 <= o1) return(true);
      if(o0 >= c1 && c0 <= o1 && body0 > body1) return(true);
   }
   return(false);
}

// check engulfing on multiple entry TFs
bool HasBullishEngulfingOnEntryTFs(int &foundTF)
{
   foundTF = 0;
   if(InpUseEntryTF_H4)
   {
      int tf=PERIOD_H4;
      if(InpEntryOnClosedBar && IsBullishEngulfing(tf,1)) { foundTF=tf; return(true); }
      if(InpEntryOnCurrentBar && IsBullishEngulfing(tf,0)) { foundTF=tf; return(true); }
   }
   if(InpUseEntryTF_H2)
   {
      int tf=SYNTH_H2;
      if(H2BarsCount>5)
      {
         if(InpEntryOnClosedBar && IsBullishEngulfing(tf,1)) { foundTF=tf; return(true); }
         if(InpEntryOnCurrentBar && IsBullishEngulfing(tf,0)) { foundTF=tf; return(true); }
      }
   }
   if(InpUseEntryTF_H1)
   {
      int tf=PERIOD_H1;
      if(InpEntryOnClosedBar && IsBullishEngulfing(tf,1)) { foundTF=tf; return(true); }
      if(InpEntryOnCurrentBar && IsBullishEngulfing(tf,0)) { foundTF=tf; return(true); }
   }
   return(false);
}
bool HasBearishEngulfingOnEntryTFs(int &foundTF)
{
   foundTF=0;
   if(InpUseEntryTF_H4)
   {
      int tf=PERIOD_H4;
      if(InpEntryOnClosedBar && IsBearishEngulfing(tf,1)) { foundTF=tf; return(true); }
      if(InpEntryOnCurrentBar && IsBearishEngulfing(tf,0)) { foundTF=tf; return(true); }
   }
   if(InpUseEntryTF_H2)
   {
      int tf=SYNTH_H2;
      if(H2BarsCount>5)
      {
         if(InpEntryOnClosedBar && IsBearishEngulfing(tf,1)) { foundTF=tf; return(true); }
         if(InpEntryOnCurrentBar && IsBearishEngulfing(tf,0)) { foundTF=tf; return(true); }
      }
   }
   if(InpUseEntryTF_H1)
   {
      int tf=PERIOD_H1;
      if(InpEntryOnClosedBar && IsBearishEngulfing(tf,1)) { foundTF=tf; return(true); }
      if(InpEntryOnCurrentBar && IsBearishEngulfing(tf,0)) { foundTF=tf; return(true); }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Object helpers                                                   |
//+------------------------------------------------------------------+
void DeleteObjectsByPrefix(string prefix)
{
   for(int i=ObjectsTotal()-1; i>=0; i--)
   {
      string name = ObjectName(i);
      if(StringFind(name, prefix)==0) ObjectDelete(name);
   }
}
void CreateRect(string name, datetime t1, double p1, datetime t2, double p2, color col, int style, int width, bool fill)
{
   if(ObjectFind(name)!=-1) ObjectDelete(name);
   ObjectCreate(name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSet(name, OBJPROP_COLOR, col);
   ObjectSet(name, OBJPROP_STYLE, style);
   ObjectSet(name, OBJPROP_WIDTH, width);
   ObjectSet(name, OBJPROP_BACK, fill);
   ObjectSet(name, OBJPROP_FILL, fill);
   // rectangle ray? extend to future: we set t2 as future
}
void CreateLabel(string name, int x, int y, string text, color col, int fontSize, string font, int corner, int anchor)
{
   if(ObjectFind(name)==-1) ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
   ObjectSetText(name, text, fontSize, font, col);
   ObjectSet(name, OBJPROP_CORNER, corner);
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSet(name, OBJPROP_XSIZE, 0);
   ObjectSet(name, OBJPROP_YSIZE, 0);
   // anchor via OBJPROP_ANCHOR not for label; use corner
}

//+------------------------------------------------------------------+
//| Drawing AOI zones                                                |
//+------------------------------------------------------------------+
void DrawAOIZones()
{
   DeleteObjectsByPrefix(OBJ_PREFIX+"HTF_");
   DeleteObjectsByPrefix(OBJ_PREFIX+"LTF_");
   datetime future = Time[0] + Period()*60*15;
   // HTF
   if(InpShowHTFZones)
   {
      for(int i=0; i<ArraySize(HTF_Zones); i++)
      {
         string n = OBJ_PREFIX+"HTF_"+IntegerToString(i)+"_"+(HTF_Zones[i].type==1?"R":"S");
         datetime t1 = HTF_Zones[i].firstTime;
         datetime t2 = future;
         color col = (HTF_Zones[i].type==1 ? InpColorHTF_Res : InpColorHTF_Sup);
         // strength determines width/style
         int width = (HTF_Zones[i].touches>=3 ? 2 : 1);
         CreateRect(n, t1, HTF_Zones[i].high, t2, HTF_Zones[i].low, col, STYLE_SOLID, width, true);
         // make translucent: set fill via back true, but MT4 fill opacity limited
         // label
         string ln = n+"_LBL";
         string txt = "HTF "+(HTF_Zones[i].type==1?"RES ":"SUP ")+IntegerToString(HTF_Zones[i].touches)+"x "+DoubleToStr(HTF_Zones[i].center, Digits);
         if(ObjectFind(ln)==-1) ObjectCreate(ln, OBJ_TEXT, 0, t1, HTF_Zones[i].center);
         else { ObjectSet(ln, OBJPROP_TIME1, t1); ObjectSet(ln, OBJPROP_PRICE1, HTF_Zones[i].center); }
         ObjectSetText(ln, txt, 7, "Arial", col);
      }
   }
   if(InpShowLTFZones)
   {
      for(int i=0; i<ArraySize(LTF_Zones); i++)
      {
         string n = OBJ_PREFIX+"LTF_"+IntegerToString(i)+"_"+(LTF_Zones[i].type==1?"R":"S");
         datetime t1 = LTF_Zones[i].firstTime;
         datetime t2 = future;
         color col = (LTF_Zones[i].type==1 ? InpColorLTF_Res : InpColorLTF_Sup);
         int width = (LTF_Zones[i].touches>=3 ? 2 : 1);
         CreateRect(n, t1, LTF_Zones[i].high, t2, LTF_Zones[i].low, col, STYLE_SOLID, width, true);
         string ln = n+"_LBL";
         string txt = "LTF "+(LTF_Zones[i].type==1?"RES ":"SUP ")+IntegerToString(LTF_Zones[i].touches)+"x "+DoubleToStr(LTF_Zones[i].center, Digits);
         if(ObjectFind(ln)==-1) ObjectCreate(ln, OBJ_TEXT, 0, t1, LTF_Zones[i].center);
         else { ObjectSet(ln, OBJPROP_TIME1, t1); ObjectSet(ln, OBJPROP_PRICE1, LTF_Zones[i].center); }
         ObjectSetText(ln, txt, 7, "Arial", col);
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void DrawDashboard(string htfBias, string ltfSyncStatus, string htfAOIStatus, string ltfAOIStatus, string structStatus, string entryStatus, string signal)
{
   if(!InpShowDashboard) return;
   int x0=10, y0=20, lineH=16, w=320;
   string bg = OBJ_PREFIX+"DASH_BG";
   if(ObjectFind(bg)==-1) ObjectCreate(bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSet(bg, OBJPROP_XDISTANCE, x0-5);
   ObjectSet(bg, OBJPROP_YDISTANCE, y0-5);
   ObjectSet(bg, OBJPROP_XSIZE, w);
   ObjectSet(bg, OBJPROP_YSIZE, 150);
   ObjectSet(bg, OBJPROP_BGCOLOR, C'20,20,20');
   ObjectSet(bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSet(bg, OBJPROP_CORNER, 0);
   ObjectSet(bg, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet(bg, OBJPROP_WIDTH, 1);
   ObjectSet(bg, OBJPROP_BACK, false);
   ObjectSet(bg, OBJPROP_COLOR, C'60,60,60');

   color colTitle = C'255,215,0';
   CreateLabel(OBJ_PREFIX+"DASH_T0", x0, y0, "KKK 4 FUNDAMENTALS — MAKE NO MISTAKE", colTitle, 8, "Arial Bold", 0, 0);
   // line 1: HTF Trend
   string txt1 = "1.TREND HTF: W1 "+(HTF_Trend_W1==1?"▲BULL":HTF_Trend_W1==-1?"▼BEAR":"—NEUT")+"  D1 "+(HTF_Trend_D1==1?"▲BULL":HTF_Trend_D1==-1?"▼BEAR":"—NEUT")+"  => "+htfBias;
   color c1 = (htfBias=="BULLISH SYNC" ? Lime : htfBias=="BEARISH SYNC" ? Red : Yellow);
   CreateLabel(OBJ_PREFIX+"DASH_L1", x0, y0+lineH, txt1, c1, 7, "Arial", 0,0);

   string txt2 = "LTF SYNC: M30 "+(LTF_Trends[0]==1?"▲":LTF_Trends[0]==-1?"▼":"—")+" H1 "+(LTF_Trends[1]==1?"▲":LTF_Trends[1]==-1?"▼":"—")+" H2 "+(LTF_Trends[2]==1?"▲":LTF_Trends[2]==-1?"▼":"—")+" H4 "+(LTF_Trends[3]==1?"▲":LTF_Trends[3]==-1?"▼":"—")+" => "+ltfSyncStatus;
   color c2 = (StringFind(ltfSyncStatus,"OK")>=0 ? Lime : StringFind(ltfSyncStatus,"WAIT")>=0 ? Yellow : Red);
   CreateLabel(OBJ_PREFIX+"DASH_L2", x0, y0+lineH*2, txt2, c2, 7, "Arial",0,0);

   CreateLabel(OBJ_PREFIX+"DASH_L3", x0, y0+lineH*3, "2.AOI  HTF: "+htfAOIStatus, (StringFind(htfAOIStatus,"INSIDE")>=0?Lime:Yellow), 7,"Arial",0,0);
   CreateLabel(OBJ_PREFIX+"DASH_L4", x0, y0+lineH*4, "     LTF: "+ltfAOIStatus, (StringFind(ltfAOIStatus,"TOUCH")>=0||StringFind(ltfAOIStatus,"INSIDE")>=0?Lime:Yellow), 7,"Arial",0,0);
   CreateLabel(OBJ_PREFIX+"DASH_L5", x0, y0+lineH*5, "3.STRUCT: "+structStatus, (StringFind(structStatus,"OK")>=0?Lime:Yellow), 7,"Arial",0,0);
   CreateLabel(OBJ_PREFIX+"DASH_L6", x0, y0+lineH*6, "4.ENTRY Engulf: "+entryStatus, (StringFind(entryStatus,"YES")>=0?Lime:Yellow), 7,"Arial",0,0);
   color cSig = (signal=="BUY" ? Lime : signal=="SELL" ? Red : White);
   CreateLabel(OBJ_PREFIX+"DASH_SIG", x0, y0+lineH*7+4, "SIGNAL: "+signal+"  |  Last: "+LastSignal+" "+TimeToStr(LastSignalTime, TIME_MINUTES), cSig, 8, "Arial Bold",0,0);
   string foot = "HTF "+IntegerToString(ArraySize(HTF_Zones))+" zones | LTF "+IntegerToString(ArraySize(LTF_Zones))+" zones | H2 "+IntegerToString(H2BarsCount)+" bars";
   CreateLabel(OBJ_PREFIX+"DASH_FOOT", x0, y0+lineH*8+6, foot, C'160,160,160', 6,"Arial",0,0);
}

//+------------------------------------------------------------------+
//| Core evaluation                                                  |
//+------------------------------------------------------------------+
bool EvaluateAll(bool &isBuy, bool &isSell, string &detailHTFBias, string &detailLTFSync, string &detailHTFAOI, string &detailLTFAOI, string &detailStruct, string &detailEntry)
{
   isBuy=false; isSell=false;
   double price = Close[0];

   // 1. HTF TREND
   HTF_Trend_W1 = GetTrend(InpHTF1);
   HTF_Trend_D1 = GetTrend(InpHTF2);
   int htfBias = 0;
   if(HTF_Trend_W1==1 && HTF_Trend_D1==1) htfBias=1;
   else if(HTF_Trend_W1==-1 && HTF_Trend_D1==-1) htfBias=-1;
   else if(!InpRequireHTFSync)
   {
      // take dominant or D1
      if(HTF_Trend_D1!=0) htfBias=HTF_Trend_D1;
      else if(HTF_Trend_W1!=0) htfBias=HTF_Trend_W1;
   }
   detailHTFBias = (htfBias==1?"BULLISH SYNC":htfBias==-1?"BEARISH SYNC":"NO SYNC");

   // LTF TRENDS
   int tfs[4];
   tfs[0]=InpLTF_Trend_TF1; tfs[1]=InpLTF_Trend_TF2; tfs[2]=InpLTF_Trend_TF3; tfs[3]=InpLTF_Trend_TF4;
   for(int i=0;i<4;i++)
   {
      int tf = tfs[i];
      if(tf==120 && H2BarsCount<10)
      {
         LTF_Trends[i]=0;
         continue;
      }
      LTF_Trends[i]=GetTrend(tf);
   }
   int bullCount=0, bearCount=0;
   for(int i=0;i<4;i++) { if(LTF_Trends[i]==1) bullCount++; if(LTF_Trends[i]==-1) bearCount++; }
   bool ltfBullSync = (bullCount>=2);
   bool ltfBearSync = (bearCount>=2);
   detailLTFSync = IntegerToString(bullCount)+"BULL/"+IntegerToString(bearCount)+"BEAR "+(ltfBullSync||ltfBearSync?"SYNC OK":"WAIT SYNC");

   // 2. AOI — already detected globally in OnCalculate; here evaluate proximity
   // HTF AOI: price inside or near?
   bool insideHTF = false;
   int nearestHTF = -1; double nearestHTFDist=999999;
   string nearestHTFInfo="NONE";
   for(int i=0;i<ArraySize(HTF_Zones);i++)
   {
      double dist = MathAbs(price - HTF_Zones[i].center);
      if(dist < nearestHTFDist) { nearestHTFDist=dist; nearestHTF=i; }
      if(PriceInZone(price, HTF_Zones[i].high, HTF_Zones[i].low, PipsToPrice(5))) { insideHTF=true; }
   }
   if(nearestHTF>=0) nearestHTFInfo = (HTF_Zones[nearestHTF].type==1?"RES ":"SUP ")+DoubleToStr(HTF_Zones[nearestHTF].center,Digits)+" "+IntegerToString(HTF_Zones[nearestHTF].touches)+"x "+DoubleToStr(PriceToPips(nearestHTFDist),1)+"p";
   else nearestHTFInfo="NO HTF ZONE";
   detailHTFAOI = (insideHTF?"INSIDE ":"NEAR ")+nearestHTFInfo;

   // LTF AOI
   bool insideLTF=false, touchingLTF=false;
   int nearestLTF=-1; double nearestLTFDist=999999;
   for(int i=0;i<ArraySize(LTF_Zones);i++)
   {
      double dist=MathAbs(price-LTF_Zones[i].center);
      if(dist<nearestLTFDist) { nearestLTFDist=dist; nearestLTF=i; }
      if(PriceInZone(price, LTF_Zones[i].high, LTF_Zones[i].low, PipsToPrice(2))) { insideLTF=true; touchingLTF=true; }
      else if(BarTouchesZone(PERIOD_CURRENT,0, LTF_Zones[i], PipsToPrice(5))) touchingLTF=true;
   }
   string ltfInfo="NONE";
   if(nearestLTF>=0) ltfInfo=(LTF_Zones[nearestLTF].type==1?"RES ":"SUP ")+DoubleToStr(LTF_Zones[nearestLTF].center,Digits)+" "+IntegerToString(LTF_Zones[nearestLTF].touches)+"x "+DoubleToStr(PriceToPips(nearestLTFDist),1)+"p";
   else ltfInfo="NO LTF ZONE";
   detailLTFAOI = (touchingLTF?"TOUCH ":"OUT ")+ltfInfo;
   if(insideLTF) detailLTFAOI = "INSIDE "+ltfInfo;

   // Above AOI check: "DO NOT WANT to Enter if we are above this LTF AOI"
   bool aboveAOI_BullBlock = false;
   bool aboveAOI_BearBlock = false;
   if(nearestLTF>=0 && InpDoNotEnterAboveAOI)
   {
      double maxAbove = PipsToPrice(InpMaxDistanceAbovePips);
      // if price is above LTF zone high + threshold, block bullish? Actually both directions shouldn't chase above
      // Interpretation: For BUY, if price is above support zone too far, it's extended - don't enter
      // For SELL, if price is above resistance zone, wait for retest inside
      if(LTF_Zones[nearestLTF].type==-1) // support zone (buy)
      {
         if(price > LTF_Zones[nearestLTF].high + maxAbove) aboveAOI_BullBlock=true;
      }
      else // resistance zone (sell)
      {
         if(price > LTF_Zones[nearestLTF].high + maxAbove) aboveAOI_BearBlock=true; // actually for sell, being above resistance could be breakout - need retest, so block if far above
         // Also for sell, if price is still above zone without retest, block? We'll be conservative: block sell if not touching
         if(!touchingLTF && price > LTF_Zones[nearestLTF].high) aboveAOI_BearBlock=true;
      }
   }

   // 3. STRUCTURE — HL/LH + BnR/HS
   bool hl = IsNextHL(InpLTF_AOI_TF2); // on LTF main (H1)
   bool lh = IsNextLH(InpLTF_AOI_TF2);
   // also check on H4
   bool hl_H4 = IsNextHL(PERIOD_H4);
   bool lh_H4 = IsNextLH(PERIOD_H4);
   bool hasHL = hl || hl_H4;
   bool hasLH = lh || lh_H4;

   bool hasBnR_Bull=false, hasBnR_Bear=false;
   bool hasHS_Bear=false, hasHS_Bull=false;
   double dummy1, dummy2, dummy3;
   // search BnR among LTF zones (for relevant direction)
   if(InpDetectBnR)
   {
      for(int i=0;i<ArraySize(LTF_Zones);i++)
      {
         if(LTF_Zones[i].type==1) // resistance -> bullish break
         {
            if(IsBreakAndRetest(LTF_Zones[i].tf, LTF_Zones[i], true, InpBnR_MaxBarsAfterBreak)) hasBnR_Bull=true;
         }
         if(LTF_Zones[i].type==-1) // support -> bearish break
         {
            if(IsBreakAndRetest(LTF_Zones[i].tf, LTF_Zones[i], false, InpBnR_MaxBarsAfterBreak)) hasBnR_Bear=true;
         }
      }
      // also check HTF zones for big picture BnR
      for(int i=0;i<ArraySize(HTF_Zones);i++)
      {
         if(HTF_Zones[i].type==1 && IsBreakAndRetest(HTF_Zones[i].tf, HTF_Zones[i], true, InpBnR_MaxBarsAfterBreak)) hasBnR_Bull=true;
         if(HTF_Zones[i].type==-1 && IsBreakAndRetest(HTF_Zones[i].tf, HTF_Zones[i], false, InpBnR_MaxBarsAfterBreak)) hasBnR_Bear=true;
      }
   }
   if(InpDetectHS)
   {
      hasHS_Bear = DetectHeadAndShoulders(PERIOD_H1, InpHS_Lookback, false, dummy1,dummy2,dummy3);
      if(!hasHS_Bear) hasHS_Bear = DetectHeadAndShoulders(PERIOD_H4, InpHS_Lookback, false, dummy1,dummy2,dummy3);
      if(!hasHS_Bear && H2BarsCount>20) hasHS_Bear = DetectHeadAndShoulders(SYNTH_H2, InpHS_Lookback, false, dummy1,dummy2,dummy3);
      hasHS_Bull = DetectHeadAndShoulders(PERIOD_H1, InpHS_Lookback, true, dummy1,dummy2,dummy3);
      if(!hasHS_Bull) hasHS_Bull = DetectHeadAndShoulders(PERIOD_H4, InpHS_Lookback, true, dummy1,dummy2,dummy3);
      if(!hasHS_Bull && H2BarsCount>20) hasHS_Bull = DetectHeadAndShoulders(SYNTH_H2, InpHS_Lookback, true, dummy1,dummy2,dummy3);
   }

   bool structBullIdeal = hasBnR_Bull || hasHS_Bull;
   bool structBearIdeal = hasBnR_Bear || hasHS_Bear;
   bool structBull = hasHL && (InpStrictStructure ? structBullIdeal : true);
   bool structBear = hasLH && (InpStrictStructure ? structBearIdeal : true);
   // allow ideal to compensate if HL/LH not perfect but BnR exists? But spec says always want HL/LH, so keep strict.

   detailStruct = "HL:"+(string)(hasHL?"YES":"NO")+" LH:"+(string)(hasLH?"YES":"NO")+" BnR B:"+(hasBnR_Bull?"Y":"N")+" S:"+(hasBnR_Bear?"Y":"N")+" HS B:"+(hasHS_Bull?"Y":"N")+" S:"+(hasHS_Bear?"Y":"N")+" => "+(structBull||structBear?"OK":"WAIT");

   // 4. ENTRY — Engulfing
   int engulfBullTF=0, engulfBearTF=0;
   bool engulfBull = HasBullishEngulfingOnEntryTFs(engulfBullTF);
   bool engulfBear = HasBearishEngulfingOnEntryTFs(engulfBearTF);
   string engBullTxt = engulfBull ? "YES "+(engulfBullTF==240?"H4":engulfBullTF==120?"H2":engulfBullTF==60?"H1":"M30") : "NO";
   string engBearTxt = engulfBear ? "YES "+(engulfBearTF==240?"H4":engulfBearTF==120?"H2":engulfBearTF==60?"H1":"M30") : "NO";
   detailEntry = "BULL "+engBullTxt+" | BEAR "+engBearTxt;

   // FINAL COMBINE — MAKE NO MISTAKE: all 4 must align
   // BULL: HTF bullish sync + at least 2 LTF bullish + inside HTF AOI + touching LTF support + structure bullish + engulfing bullish + not above AOI
   bool htfOK_Bull = (htfBias==1);
   bool htfOK_Bear = (htfBias==-1);
   bool ltfOK_Bull = ltfBullSync || !InpRequireTwoLTFTrendSync;
   bool ltfOK_Bear = ltfBearSync || !InpRequireTwoLTFTrendSync;
   bool aoiHTF_OK = insideHTF || nearestHTFDist < PipsToPrice(40); // allow near within 40 pips
   bool aoiLTF_OK_Bull = (touchingLTF || insideLTF) && !aboveAOI_BullBlock;
   bool aoiLTF_OK_Bear = (touchingLTF || insideLTF) && !aboveAOI_BearBlock;
   // For sell, ensure we are at resistance AOI type
   if(nearestLTF>=0)
   {
      if(htfOK_Bull && LTF_Zones[nearestLTF].type != -1) aoiLTF_OK_Bull = aoiLTF_OK_Bull && false; // need support for buy; but allow if no type strict? We'll enforce loose: if zone is resistance, still possible BnR bullish breakout => allow, so don't strict block
      // Actually for buy we want support, for sell resistance — but BnR bullish is resistance breakout, so after break it's support.
      // So we will not hard enforce type, just ensure proximity.
   }

   isBuy = htfOK_Bull && ltfOK_Bull && aoiHTF_OK && aoiLTF_OK_Bull && structBull && engulfBull;
   isSell = htfOK_Bear && ltfOK_Bear && aoiHTF_OK && aoiLTF_OK_Bear && structBear && engulfBear;

   if(InpDebugLog)
   {
      Print("EVAL BUY=",isBuy," SELL=",isSell," HTF=",detailHTFBias," LTF=",detailLTFSync," HTF_AOI=",detailHTFAOI," LTF_AOI=",detailLTFAOI," STRUCT=",detailStruct," ENTRY=",detailEntry);
   }
   return(isBuy || isSell);
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorBuffers(2);
   SetIndexBuffer(0, BuySignalBuffer);
   SetIndexBuffer(1, SellSignalBuffer);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 2, Lime);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 2, Red);
   SetIndexArrow(0, 233); // up arrow Wingdings
   SetIndexArrow(1, 234); // down arrow
   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexLabel(0, "KKK BUY");
   SetIndexLabel(1, "KKK SELL");

   ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
   ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);

   // Build synthetic H2 immediately
   BuildSyntheticH2();
   LastH1BarTime = iTime(Symbol(), PERIOD_H1, 0);

   Print("KKK Four Fundamentals v1.00 initialized on ",Symbol()," M",Period()," — HTF ",InpHTF1,"/",InpHTF2," LTF AOI ",InpLTF_AOI_TF1,"/",InpLTF_AOI_TF2);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteObjectsByPrefix(OBJ_PREFIX);
   // also clear buffers
   Comment("");
}

//+------------------------------------------------------------------+
//| New bar check                                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime cur = iTime(Symbol(), Period(), 0);
   if(cur != LastCalcTime)
   {
      LastCalcTime = cur;
      return(true);
   }
   return(false);
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
   // Always update synthetic H2 if H1 bar changed
   datetime curH1 = iTime(Symbol(), PERIOD_H1, 0);
   if(curH1 != LastH1BarTime)
   {
      BuildSyntheticH2();
      LastH1BarTime = curH1;
   }

   // Throttle heavy AOI recalc to new bar or first run
   bool needRecalc = false;
   if(prev_calculated==0) needRecalc=true;
   if(IsNewBar()) needRecalc=true;
   // also recalc every 5 sec on tick if no new bar but we want live dashboard? keep light
   static datetime lastHeavy=0;
   if(TimeCurrent() - lastHeavy > 5) needRecalc=true;

   if(needRecalc)
   {
      lastHeavy = TimeCurrent();
      // Detect AOI zones
      DetectAOIZones(InpHTF_AOI_TF, InpHTF_AOI_Lookback, InpMinTouchesHTF, true, HTF_Zones);
      // LTF AOI: we need to combine two TFs? Strategy says LTF AOI is 4hr/2hr/1hr — we will detect on both and merge
      AOIZone zonesA[], zonesB[];
      DetectAOIZones(InpLTF_AOI_TF1, InpLTF_AOI_Lookback, InpMinTouchesLTF, false, zonesA);
      DetectAOIZones(InpLTF_AOI_TF2, InpLTF_AOI_Lookback, InpMinTouchesLTF, false, zonesB);
      // merge
      ArrayResize(LTF_Zones, ArraySize(zonesA)+ArraySize(zonesB));
      for(int i=0;i<ArraySize(zonesA);i++) LTF_Zones[i]=zonesA[i];
      for(int i=0;i<ArraySize(zonesB);i++) LTF_Zones[ArraySize(zonesA)+i]=zonesB[i];
      // If H2 requested as LTF AOI, also detect there and merge (if distinct)
      if(InpLTF_AOI_TF1!=120 && InpLTF_AOI_TF2!=120 && H2BarsCount>50)
      {
         AOIZone zonesC[];
         DetectAOIZones(SYNTH_H2, InpLTF_AOI_Lookback, InpMinTouchesLTF, false, zonesC);
         int oldSz=ArraySize(LTF_Zones);
         ArrayResize(LTF_Zones, oldSz+ArraySize(zonesC));
         for(int i=0;i<ArraySize(zonesC);i++) LTF_Zones[oldSz+i]=zonesC[i];
      }
      // sort merged LTF by touches descending (already) and limit
      // limit to InpMaxZonesLTF*2 then trim
      if(ArraySize(LTF_Zones) > InpMaxZonesLTF*2)
         ArrayResize(LTF_Zones, InpMaxZonesLTF*2);

      DrawAOIZones();
   }

   // Evaluate signals
   bool isBuy, isSell;
   string dHTF, dLTF, dHTFAOI, dLTFAOI, dStruct, dEntry;
   bool hasSignal = EvaluateAll(isBuy, isSell, dHTF, dLTF, dHTFAOI, dLTFAOI, dStruct, dEntry);

   // Dashboard update every tick
   string sigTxt="NONE";
   if(isBuy) sigTxt="BUY";
   else if(isSell) sigTxt="SELL";
   DrawDashboard(dHTF, dLTF, dHTFAOI, dLTFAOI, dStruct, dEntry, sigTxt);

   // Manage buffers: set arrow on signal bar
   // We signal on closed bar 1 but draw arrow at bar 1 low/high; also for live bar 0 if enabled
   int sigShift = InpEntryOnClosedBar ? 1 : 0;
   double atr = iATR(Symbol(), Period(), 14, 1);
   if(atr==0) atr = PipsToPrice(15);
   double offset = atr * 0.6;

   // Clear previous tick's tentative? We keep history: only set at sigShift when condition holds, don't clear old signals
   // But to avoid repaint confusion, we will only set when new signal appears and keep
   if(hasSignal)
   {
      datetime sigTime = iTime(Symbol(), Period(), sigShift);
      bool isNewSignal = (sigTime != LastSignalTime);
      if(isBuy && isNewSignal)
      {
         BuySignalBuffer[sigShift] = Low[sigShift] - offset;
         if(InpShowArrows)
         {
            string oname = OBJ_PREFIX+"BUY_"+TimeToStr(sigTime);
            if(ObjectFind(oname)==-1)
            {
               ObjectCreate(oname, OBJ_ARROW, 0, sigTime, Low[sigShift]-offset);
               ObjectSet(oname, OBJPROP_ARROWCODE, 233);
               ObjectSet(oname, OBJPROP_COLOR, Lime);
               ObjectSet(oname, OBJPROP_WIDTH, 2);
            }
         }
         LastSignal="BUY"; LastSignalTime=sigTime;
         if(InpAlertPopup || InpAlertPush || InpAlertEmail || InpAlertSound)
         {
            string msg = StringConcatenate("KKK 4F BUY ",Symbol()," M",Period(),
                         " HTF:",dHTF," LTF:",dLTF," AOI:",dLTFAOI," STRUCT:",dStruct," ENTRY:",dEntry);
            if(InpAlertPopup) Alert(msg);
            if(InpAlertPush) SendNotification(msg);
            if(InpAlertEmail) SendMail("KKK 4F BUY "+Symbol(), msg);
            if(InpAlertSound) PlaySound(InpSoundFile);
         }
      }
      if(isSell && isNewSignal)
      {
         SellSignalBuffer[sigShift] = High[sigShift] + offset;
         if(InpShowArrows)
         {
            string oname = OBJ_PREFIX+"SELL_"+TimeToStr(sigTime);
            if(ObjectFind(oname)==-1)
            {
               ObjectCreate(oname, OBJ_ARROW, 0, sigTime, High[sigShift]+offset);
               ObjectSet(oname, OBJPROP_ARROWCODE, 234);
               ObjectSet(oname, OBJPROP_COLOR, Red);
               ObjectSet(oname, OBJPROP_WIDTH, 2);
            }
         }
         LastSignal="SELL"; LastSignalTime=sigTime;
         if(InpAlertPopup || InpAlertPush || InpAlertEmail || InpAlertSound)
         {
            string msg = StringConcatenate("KKK 4F SELL ",Symbol()," M",Period(),
                         " HTF:",dHTF," LTF:",dLTF," AOI:",dLTFAOI," STRUCT:",dStruct," ENTRY:",dEntry);
            if(InpAlertPopup) Alert(msg);
            if(InpAlertPush) SendNotification(msg);
            if(InpAlertEmail) SendMail("KKK 4F SELL "+Symbol(), msg);
            if(InpAlertSound) PlaySound(InpSoundFile);
         }
      }
   }

   // Comment fallback if dashboard disabled
   if(!InpShowDashboard)
      Comment("KKK 4F | HTF:",dHTF," | LTF:",dLTF," | HTF_AOI:",dHTFAOI," | LTF_AOI:",dLTFAOI," | STRUCT:",dStruct," | ENTRY:",dEntry," | SIG:",sigTxt);

   return(rates_total);
}
//+------------------------------------------------------------------+
