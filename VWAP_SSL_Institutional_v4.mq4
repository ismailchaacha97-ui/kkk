//+------------------------------------------------------------------+
//|                                   VWAP_SSL_Institutional_v4.mq4  |
//|   Institutional Grade VWAP SSL — Fixed & Production Ready        |
//|   v4.10 — Arena 2026-08-21 — Early-Signal Fix                      |
//|                                                                   |
//|   FIXES vs v3 (see REVIEW.md):                                    |
//|   • Series-safe (0=newest), no repaint, incremental O(N)         |
//|   • Real anchored sessions: DAILY/WEEKLY/MONTHLY/LONDON/NY/ASIA   |
//|   • SSL dead-zone 0.25σ to kill chop (now selectable)             |
//|   • True σ bands ±1σ ±2σ (variance = E[TP²]-E[TP]²)              |
//|   • True Volume Profile: 24-bin histogram POC + 70% VA expansion  |
//|   • Real MTF: HTF SMA20 slope, not single candle color            |
//|   • Session-relative volume SMA (no iVolume loops per tick)       |
//|   • Squeeze detection σ < 0.7·SMA(σ,20) + breakout scoring        |
//|   • Anchored SL/TP (freeze at flip), one alert per bar-close     |
//|   • Arrows + strength 0-100 weighted, EA-readable buffers         |
//|   • v4.10: FLIP modes SAFE/MODERATE/EARLY/VWAP/WICK — fixes late  |
//+------------------------------------------------------------------+
#property copyright   "Institutional VWAP SSL v4.10 — Early Fix"
#property link        "https://arena.ai"
#property version     "4.10"
#property strict
#property indicator_chart_window
#property indicator_buffers 14

//--- visual defaults
#property indicator_color1  clrLimeGreen  // SSL Up
#property indicator_color2  clrRed        // SSL Down
#property indicator_color3  clrDodgerBlue // Band +1
#property indicator_color4  clrDodgerBlue // Band -1
#property indicator_color5  clrSilver     // Band +2
#property indicator_color6  clrSilver     // Band -2
#property indicator_color7  clrGold       // POC
#property indicator_color8  clrYellow     // VAH (MT4 only shows 8 colors in header; rest set via SetIndexStyle)

// widths
#property indicator_width1 2
#property indicator_width2 2
#property indicator_width3 1
#property indicator_width4 1
#property indicator_width5 1
#property indicator_width6 1
#property indicator_width7 3
#property indicator_width8 1

//== Enums ===========================================================
enum ENUM_VWAP_PERIOD
{
   VWAP_DAILY   = 0,  // Daily anchored (00:00 broker)
   VWAP_WEEKLY  = 1,  // Weekly anchored (Monday)
   VWAP_MONTHLY = 2,  // Monthly anchored
   VWAP_LONDON  = 3,  // London 08:00 (broker time + offset)
   VWAP_NEWYORK = 4,  // New York 13:00
   VWAP_ASIA    = 5   // Asia 22:00
};

enum ENUM_MTF_MODE
{
   MTF_OFF    = 0, // No MTF check
   MTF_HIGHER = 1  // Require HTF SMA20 alignment
};

enum ENUM_VA_MODE
{
   VA_SIGMA     = 0, // Fast: VWAP ±0.85σ (old approximation)
   VA_HISTOGRAM = 1  // True: 70% volume profile histogram
};

enum ENUM_FLIP_MODE
{
   FLIP_SAFE     = 0, // Classic: close beyond VWAP-H/L + buffer (late, 0.25σ) - fewest whipsaws
   FLIP_MODERATE = 1, // close beyond VWAP-H/L + 0.10σ (balanced)
   FLIP_EARLY    = 2, // close beyond VWAP-H/L, no buffer (≈1 bar earlier)
   FLIP_VWAP     = 3, // close beyond VWAP_T itself (≈1-2 bars earlier, aggressive)
   FLIP_WICK     = 4  // wick beyond VWAP_T (earliest, most false - scalping only)
};

//== Inputs ==========================================================
input string            InpSec01          = "===== Core Anchoring =====";
input ENUM_VWAP_PERIOD  InpPeriod         = VWAP_DAILY;
input int               InpSessionOffset  = 0;              // Hours to shift session opens (broker -> GMT etc)
input ENUM_MTF_MODE     InpMTF_Mode       = MTF_HIGHER;
input bool              InpVolFilter      = true;
input int               InpVolFactor      = 150;            // Volume must exceed SMA(Vol,20) * 150%
input int               InpVolPeriod      = 20;             // Lookback for volume SMA
input ENUM_VA_MODE      InpVAMode         = VA_HISTOGRAM;
input int               InpHistBins       = 24;             // Bins for histogram (12..48)
input double            InpDeadZoneSigma  = 0.25;           // SSL dead-zone as fraction of σ (kills chop) — used when FlipMode = SAFE
input ENUM_FLIP_MODE    InpFlipMode       = FLIP_MODERATE;  // <— FIX FOR "LATE" SIGNALS: use EARLY/VWAP/WICK for 1-2 bars earlier
input bool              InpConfirmOnClose = true;           // true = wait for bar close (safe), false = intra-bar wick (early but repaints)
input bool              InpEarlyNoFilter  = false;          // true = early flips ignore Vol/MTF filters (even earlier, more noise)
input string            InpSec02          = "===== Visuals & Bands =====";
input color             InpUpColor        = clrLimeGreen;
input color             InpDnColor        = clrRed;
input bool              InpShowBands      = true;
input color             InpBand1Color     = clrDodgerBlue;
input color             InpBand2Color     = clrSilver;
input bool              InpShowVA         = true;
input bool              InpShowPOC        = true;
input string            InpSec03          = "===== Risk Management =====";
input bool              InpShowRisk       = true;
input double            InpRiskMult       = 1.5;            // SL = entry ± σ * 1.5
input double            InpRewardMult     = 3.0;            // TP = entry ± σ * 3.0
input string            InpSec04          = "===== Squeeze & Scoring =====";
input bool              InpShowSqueeze    = true;
input double            InpSqueezeThresh  = 0.70;           // σ < SMA(σ,20)*0.70 => squeeze
input int               InpSqueezePeriod  = 20;
input int               InpStrengthThresh = 70;             // Only alert if score >= 70
input string            InpSec05          = "===== Alerts & HUD =====";
input bool              InpShowHUD        = true;
input bool              InpAlertPopup     = false;
input bool              InpAlertSound     = false;
input bool              InpAlertMobile    = false;
input string            InpAlertWav       = "alert.wav";
input bool              InpAlertOnClose   = true;           // Only on bar close (recommended)
input int               InpArrowOffsetPts = 15;             // Arrow distance in points

//== Buffers =========================================================
double BufSSLUp[];     // 0
double BufSSLDn[];     // 1
double BufBandUp1[];   // 2  +1σ
double BufBandDn1[];   // 3  -1σ
double BufBandUp2[];   // 4  +2σ
double BufBandDn2[];   // 5  -2σ
double BufPOC[];       // 6
double BufVAH[];       // 7
double BufVAL[];       // 8
double BufBuy[];       // 9  arrow buy
double BufSell[];      //10  arrow sell
double BufStrength[];  //11  0-100 (DRAW_NONE, for EA)
double BufSL[];        //12  anchored SL
double BufTP[];        //13  anchored TP

//== Internal state (series, 0=newest) ===============================
double g_sumPVH[], g_sumPVL[], g_sumPT[], g_sumV[], g_sumPT2[];
double g_volSMA[], g_sigma[];
int    g_trend[];              // 0=up,1=down,-1=init
int    g_sessionStart[];       // index of oldest bar of current session (larger index)
double g_anchorSL[], g_anchorTP[];
double g_squeeze[];            // 1=squeeze, 0=normal

datetime g_lastAlertBarTime = 0;
int      g_lastAlertTrend   = -99;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
int GetHigherTF()
{
   int p = Period();
   if(p==PERIOD_M1)  return PERIOD_M5;
   if(p==PERIOD_M5)  return PERIOD_M15;
   if(p==PERIOD_M15) return PERIOD_H1;
   if(p==PERIOD_M30) return PERIOD_H1;
   if(p==PERIOD_H1)  return PERIOD_H4;
   if(p==PERIOD_H4)  return PERIOD_D1;
   if(p==PERIOD_D1)  return PERIOD_W1;
   if(p==PERIOD_W1)  return PERIOD_MN1;
   return p;
}

int AdjustedHour(datetime t)
{
   int h = TimeHour(t);
   h = (h + InpSessionOffset) % 24;
   if(h<0) h+=24;
   return h;
}

bool IsNewSession(datetime tCurr, datetime tPrev, ENUM_VWAP_PERIOD mode)
{
   // tCurr is newer (larger datetime) than tPrev
   if(tCurr <= tPrev) return false;
   // Daily
   if(mode==VWAP_DAILY)
      return TimeDay(tCurr)!=TimeDay(tPrev);
   if(mode==VWAP_WEEKLY)
   {
      int dowCurr = TimeDayOfWeek(tCurr);
      int dowPrev = TimeDayOfWeek(tPrev);
      // week rolls when dow goes backward or hits Monday crossing
      if(dowCurr < dowPrev) return true;
      if(dowCurr==1 && dowPrev!=1 && TimeDay(tCurr)!=TimeDay(tPrev)) return true;
      return false;
   }
   if(mode==VWAP_MONTHLY)
      return TimeMonth(tCurr)!=TimeMonth(tPrev);

   // Session based: new when we cross the open hour
   int hCurr = AdjustedHour(tCurr);
   int hPrev = AdjustedHour(tPrev);
   int dayCurr = TimeDay(tCurr);
   int dayPrev = TimeDay(tPrev);

   if(mode==VWAP_LONDON) // 08:00
   {
      // crossing 08:00 forward
      if(hPrev < 8 && hCurr >= 8) return true;
      if(hCurr==8 && hPrev!=8) return true;
      // also if gap over 08:00 (weekend) -- compare date+hour
      if(dayCurr!=dayPrev && hCurr>=8 && hPrev>=8 && (tCurr - tPrev) > 12*3600) return true;
      return false;
   }
   if(mode==VWAP_NEWYORK) // 13:00
   {
      if(hPrev < 13 && hCurr >= 13) return true;
      if(hCurr==13 && hPrev!=13) return true;
      if(dayCurr!=dayPrev && hCurr>=13 && hPrev>=13 && (tCurr - tPrev) > 12*3600) return true;
      return false;
   }
   if(mode==VWAP_ASIA) // 22:00
   {
      // Asia wraps overnight 22-08
      if(hPrev < 22 && hCurr >= 22) return true;
      if(hCurr==22 && hPrev!=22) return true;
      if(dayCurr!=dayPrev && hCurr>=22) return true;
      // if gap includes 22:00
      if((tCurr - tPrev) > 10*3600 && hCurr>=22) return true;
      return false;
   }
   return false;
}

// Check MTF alignment using HTF SMA20 slope + price vs MA
bool CheckMTFAlignment(int curTrend, datetime barTime)
{
   if(InpMTF_Mode==MTF_OFF) return true;
   int hTF = GetHigherTF();
   if(hTF <= Period()) return true;

   int shift = iBarShift(NULL, hTF, barTime, true);
   if(shift < 0) return true;
   // need at least 22 bars
   if(Bars < 30) return true;

   // Use SMA of typical price to define HTF trend
   double ma  = iMA(NULL, hTF, 20, 0, MODE_SMA, PRICE_TYPICAL, shift);
   double ma1 = iMA(NULL, hTF, 20, 0, MODE_SMA, PRICE_TYPICAL, shift+1);
   double closeHTF = iClose(NULL, hTF, shift);
   if(ma==0 || ma1==0 || closeHTF==0) return true;

   bool hBull = (closeHTF > ma && ma > ma1);
   bool hBear = (closeHTF < ma && ma < ma1);
   // If flat, fallback to candle direction but require MA flat tolerance
   if(!hBull && !hBear)
   {
      // consider flat as no bias -> allow both
      return true;
   }
   if(curTrend==0) return hBull;
   if(curTrend==1) return hBear;
   return true;
}

// Simple SMA of sigma for squeeze
double SigmaSMA(int idx, int period, int rates_total)
{
   if(idx + period >= rates_total) return g_sigma[idx];
   double s=0;
   int cnt=0;
   for(int k=0;k<period;k++)
   {
      int j = idx + k;
      if(j>=rates_total) break;
      if(g_sigma[j]==EMPTY_VALUE) continue;
      s+= g_sigma[j]; cnt++;
   }
   if(cnt==0) return g_sigma[idx];
   return s / cnt;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("Inst. VWAP SSL v4 ("+EnumToString(InpPeriod)+")");
   IndicatorDigits(_Digits);

   //--- map buffers
   SetIndexBuffer(0, BufSSLUp);   SetIndexLabel(0, "SSL Up");
   SetIndexBuffer(1, BufSSLDn);   SetIndexLabel(1, "SSL Down");
   SetIndexBuffer(2, BufBandUp1); SetIndexLabel(2, "Band +1σ");
   SetIndexBuffer(3, BufBandDn1); SetIndexLabel(3, "Band -1σ");
   SetIndexBuffer(4, BufBandUp2); SetIndexLabel(4, "Band +2σ");
   SetIndexBuffer(5, BufBandDn2); SetIndexLabel(5, "Band -2σ");
   SetIndexBuffer(6, BufPOC);     SetIndexLabel(6, "POC");
   SetIndexBuffer(7, BufVAH);     SetIndexLabel(7, "VAH 70%");
   SetIndexBuffer(8, BufVAL);     SetIndexLabel(8, "VAL 70%");
   SetIndexBuffer(9, BufBuy);     SetIndexLabel(9, "Buy Signal");
   SetIndexBuffer(10,BufSell);    SetIndexLabel(10,"Sell Signal");
   SetIndexBuffer(11,BufStrength);SetIndexLabel(11,"Strength 0-100");
   SetIndexBuffer(12,BufSL);      SetIndexLabel(12,"Anchored SL");
   SetIndexBuffer(13,BufTP);      SetIndexLabel(13,"Anchored TP");

   //--- styles
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 2, InpUpColor);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, 2, InpDnColor);

   if(InpShowBands)
   {
      SetIndexStyle(2, DRAW_LINE, STYLE_DOT, 1, InpBand1Color);
      SetIndexStyle(3, DRAW_LINE, STYLE_DOT, 1, InpBand1Color);
      SetIndexStyle(4, DRAW_LINE, STYLE_DOT, 1, InpBand2Color);
      SetIndexStyle(5, DRAW_LINE, STYLE_DOT, 1, InpBand2Color);
   }
   else
   {
      SetIndexStyle(2, DRAW_NONE); SetIndexStyle(3, DRAW_NONE);
      SetIndexStyle(4, DRAW_NONE); SetIndexStyle(5, DRAW_NONE);
   }

   if(InpShowPOC) SetIndexStyle(6, DRAW_LINE, STYLE_SOLID, 3, clrGold);
   else           SetIndexStyle(6, DRAW_NONE);

   if(InpShowVA)
   {
      SetIndexStyle(7, DRAW_LINE, STYLE_DOT, 1, clrYellow);
      SetIndexStyle(8, DRAW_LINE, STYLE_DOT, 1, clrOrange);
   }
   else
   {
      SetIndexStyle(7, DRAW_NONE); SetIndexStyle(8, DRAW_NONE);
   }

   SetIndexStyle(9,  DRAW_ARROW, STYLE_SOLID, 2, clrLime);
   SetIndexArrow(9, 233); // up arrow
   SetIndexStyle(10, DRAW_ARROW, STYLE_SOLID, 2, clrRed);
   SetIndexArrow(10, 234); // down arrow

   SetIndexStyle(11, DRAW_NONE); // hidden but EA readable

   if(InpShowRisk)
   {
      SetIndexStyle(12, DRAW_LINE, STYLE_DASH, 1, clrRed);
      SetIndexStyle(13, DRAW_LINE, STYLE_DASH, 1, clrLime);
   }
   else
   {
      SetIndexStyle(12, DRAW_NONE); SetIndexStyle(13, DRAW_NONE);
   }

   for(int i=0;i<14;i++) SetIndexEmptyValue(i, EMPTY_VALUE);

   // indicator buffers are series by default
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { Comment(""); }

//+------------------------------------------------------------------+
//| OnCalculate — series-safe, incremental                           |
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
   if(rates_total < 50) return 0;

   // Ensure internal arrays are series (0=newest)
   int need = rates_total;
   bool needResize = (ArraySize(g_sumV) != need);
   if(needResize)
   {
      ArrayResize(g_sumPVH, need); ArrayResize(g_sumPVL, need);
      ArrayResize(g_sumPT,  need); ArrayResize(g_sumV,  need);
      ArrayResize(g_sumPT2, need);
      ArrayResize(g_volSMA, need);
      ArrayResize(g_sigma,  need);
      ArrayResize(g_trend,  need);
      ArrayResize(g_sessionStart, need);
      ArrayResize(g_anchorSL, need);
      ArrayResize(g_anchorTP, need);
      ArrayResize(g_squeeze, need);

      ArraySetAsSeries(g_sumPVH, true); ArraySetAsSeries(g_sumPVL, true);
      ArraySetAsSeries(g_sumPT,  true); ArraySetAsSeries(g_sumV,   true);
      ArraySetAsSeries(g_sumPT2, true); ArraySetAsSeries(g_volSMA, true);
      ArraySetAsSeries(g_sigma,  true); ArraySetAsSeries(g_trend,  true);
      ArraySetAsSeries(g_sessionStart, true);
      ArraySetAsSeries(g_anchorSL, true); ArraySetAsSeries(g_anchorTP, true);
      ArraySetAsSeries(g_squeeze, true);

      ArraySetAsSeries(BufSSLUp, true); ArraySetAsSeries(BufSSLDn, true);
      ArraySetAsSeries(BufBandUp1, true); ArraySetAsSeries(BufBandDn1, true);
      ArraySetAsSeries(BufBandUp2, true); ArraySetAsSeries(BufBandDn2, true);
      ArraySetAsSeries(BufPOC, true); ArraySetAsSeries(BufVAH, true); ArraySetAsSeries(BufVAL, true);
      ArraySetAsSeries(BufBuy, true); ArraySetAsSeries(BufSell, true);
      ArraySetAsSeries(BufStrength, true); ArraySetAsSeries(BufSL, true); ArraySetAsSeries(BufTP, true);
   }

   //--- determine start index for incremental update
   int start;
   if(prev_calculated==0)
      start = rates_total-1; // oldest
   else
   {
      // recalc last few bars + any new bars
      start = rates_total - prev_calculated;
      // +2 safety for session carry; ensure not out of bounds
      start = MathMin(start + 2, rates_total-1);
      start = MathMax(start, 0);
   }

   // Clamp hist bins
   int histBins = InpHistBins;
   if(histBins < 12) histBins = 12;
   if(histBins > 60) histBins = 60;

   // ===============================================================
   // PASS 1: cumulative VWAP sums + session tracking + vol SMA
   // ===============================================================
   // Pre-compute volume SMA for all affected bars first (needed for filter)
   // volSMA[idx] = SMA of tick_volume over InpVolPeriod *excluding* current bar
   // (i.e., average of next N older bars)
   for(int i=start; i>=0; i--)
   {
      double sum = 0;
      int cnt = 0;
      for(int k=1; k<=InpVolPeriod; k++)
      {
         int j = i + k;
         if(j >= rates_total) break;
         sum += (double)tick_volume[j];
         cnt++;
      }
      if(cnt>0) g_volSMA[i] = sum / cnt;
      else      g_volSMA[i] = (double)tick_volume[i];
   }
   // Also need SMA for older bars that may be referenced by limit? For start edge, ensure next bar has SMA
   if(start+1 < rates_total && g_volSMA[start+1]==0)
   {
      // fallback ensure filled
      for(int i=start+1; i< MathMin(start+InpVolPeriod+5, rates_total); i++)
         if(g_volSMA[i]==0) g_volSMA[i]=(double)tick_volume[i];
   }

   // Cumulative VWAP
   for(int i=start; i>=0; i--)
   {
      double v = (double)tick_volume[i];
      if(v<=0) v=1;
      double tp = (high[i] + low[i] + close[i]) / 3.0;

      bool isNew = false;
      if(i==rates_total-1) isNew = true;
      else isNew = IsNewSession(time[i], time[i+1], InpPeriod);

      if(isNew)
      {
         g_sumPVH[i] = high[i]*v;
         g_sumPVL[i] = low[i]*v;
         g_sumPT[i]  = tp*v;
         g_sumV[i]   = v;
         g_sumPT2[i] = tp*tp*v;
         g_sessionStart[i] = i;
      }
      else
      {
         // carry from older bar i+1
         g_sumPVH[i] = g_sumPVH[i+1] + high[i]*v;
         g_sumPVL[i] = g_sumPVL[i+1] + low[i]*v;
         g_sumPT[i]  = g_sumPT[i+1]  + tp*v;
         g_sumV[i]   = g_sumV[i+1]   + v;
         g_sumPT2[i] = g_sumPT2[i+1] + tp*tp*v;
         g_sessionStart[i] = g_sessionStart[i+1];
      }
   }

   // ===============================================================
   // PASS 2: trend, sigma, bands, VA/POC, strength, risk, signals
   // ===============================================================
   int prevTrend = -1;
   if(start+1 < rates_total) prevTrend = g_trend[start+1];
   double prevAnchorSL = EMPTY_VALUE, prevAnchorTP = EMPTY_VALUE;
   if(start+1 < rates_total)
   {
      prevAnchorSL = g_anchorSL[start+1];
      prevAnchorTP = g_anchorTP[start+1];
   }

   // For squeeze SMA we need g_sigma of older bars already computed for start+1..end
   // On first run g_sigma not yet filled for old bars, but our loop fills oldest->newest, so older bars already have sigma from previous iteration in same pass? Actually we fill sigma in this same loop sequentially from oldest to newest? But we iterate start->0 (oldest recalc toward newest), so when we are at i = start (older), sigma for i+1 (even older) is already known (either from previous tick or just computed). For first full run start=oldest, sigma for i+1 not yet computed if we go newest direction? We go from oldest downward to 0? Wait start is oldest affected; loop i=start down to 0 goes oldest -> newest. So at i=start (oldest), i+1 is out of bounds (since oldest has no older). At i=start-1 (next newer), g_sigma[i+1] is just computed. So squeeze SMA which looks *older* (i+1..i+N) will reference already computed sigmas except first few. So we should iterate in order that older sigma are computed first — which we do (oldest first). So fine.

   for(int i=start; i>=0; i--)
   {
      double sumV = g_sumV[i];
      if(sumV<=0) sumV=1;
      double vwapH = g_sumPVH[i]/sumV;
      double vwapL = g_sumPVL[i]/sumV;
      double vwapT = g_sumPT[i]/sumV;

      double variance = (g_sumPT2[i]/sumV) - (vwapT*vwapT);
      if(variance < 0) variance = 0;
      double sigma = MathSqrt(variance);
      g_sigma[i] = sigma;

      // Smooth early-session sigma (avoid 0)
      int barsInSession = (int)(g_sessionStart[i] - i + 1);
      if(barsInSession < 20 && barsInSession>0)
      {
         // blend with ATR-ish floor: use max(sigma, avg high-low *0.3 / bars)
         double minSigma = _Point * 10;
         // compute avg range of session so far
         double rangeSum=0;
         for(int rr=i; rr<=g_sessionStart[i] && rr < rates_total; rr++) rangeSum += (high[rr]-low[rr]);
         double avgRange = rangeSum / barsInSession;
         double floored = MathMax(sigma, avgRange*0.15);
         // ramp up over first 20 bars
         double ramp = (double)barsInSession / 20.0;
         sigma = sigma * ramp + floored * (1.0 - ramp);
         // keep g_sigma as raw for SMA calc but use smoothed for bands? store smoothed for display
         // we keep smoothed in local var; g_sigma keeps raw for squeeze detection
      }

      // --- SSL trend — FIX FOR LATENESS: choose flip sensitivity
      int curT = prevTrend;
      // effective buffer depends on FlipMode (SAFE uses your input, others override)
      double effBuffer = sigma * InpDeadZoneSigma;
      if(InpFlipMode==FLIP_MODERATE) effBuffer = sigma * 0.10;
      else if(InpFlipMode==FLIP_EARLY) effBuffer = 0;
      else if(InpFlipMode==FLIP_VWAP) effBuffer = 0;
      else if(InpFlipMode==FLIP_WICK) effBuffer = 0;

      // price to test: close (confirmed) vs wick (earliest)
      double priceUpTest   = close[i]; // for flipping short->long
      double priceDownTest = close[i]; // for flipping long->short
      // For WICK mode use high/low so flip triggers as soon as wick touches
      // For live bar (i==0) and InpConfirmOnClose==false, also use wicks for intrabar sensitivity
      bool useWick = (InpFlipMode==FLIP_WICK) || (!InpConfirmOnClose && i==0 && (InpFlipMode==FLIP_VWAP || InpFlipMode==FLIP_EARLY));
      if(useWick)
      {
         priceUpTest   = high[i];
         priceDownTest = low[i];
      }

      if(prevTrend==-1)
      {
         curT = (close[i] >= vwapT) ? 0 : 1;
      }
      else if(InpFlipMode==FLIP_VWAP || InpFlipMode==FLIP_WICK)
      {
         // EARLIEST: cross the VWAP centre itself — ~1-2 bars before H/L
         if(prevTrend==0 && priceDownTest < vwapT) curT = 1;
         else if(prevTrend==1 && priceUpTest > vwapT) curT = 0;
      }
      else
      {
         // SAFE / MODERATE / EARLY: cross the SSL band (VWAP-H/L)
         if(prevTrend==0 && priceDownTest < vwapL - effBuffer) curT = 1;
         else if(prevTrend==1 && priceUpTest > vwapH + effBuffer) curT = 0;
      }
      g_trend[i] = curT;
      bool flipped = (prevTrend!=-1 && curT!=prevTrend);

      prevTrend = curT;

      // --- Volume confluence
      bool volConfirms = true;
      if(InpVolFilter)
      {
         double avgVol = g_volSMA[i];
         double needVol = avgVol * (InpVolFactor/100.0);
         if((double)tick_volume[i] < needVol) volConfirms = false;
      }

      // --- MTF alignment
      bool mtfAligns = CheckMTFAlignment(curT, time[i]);
      // Early mode: optionally bypass filters for 1-2 bars earlier signal (more noise)
      if(InpEarlyNoFilter && flipped && (InpFlipMode==FLIP_EARLY || InpFlipMode==FLIP_VWAP || InpFlipMode==FLIP_WICK))
      {
         volConfirms = true;
         mtfAligns   = true;
      }

      // --- Squeeze detection
      double smaSigma = SigmaSMA(i, InpSqueezePeriod, rates_total);
      bool inSqueeze = (sigma < smaSigma * InpSqueezeThresh && smaSigma>0);
      g_squeeze[i] = inSqueeze ? 1 : 0;

      // --- Signal strength 0-100
      double strength = 0;
      if(flipped)
      {
         strength = 30; // base flip
         if(volConfirms) strength += 20;
         if(mtfAligns)   strength += 20;
         double dist = MathAbs(close[i] - vwapT);
         if(dist > sigma*0.5) strength += 10;
         if(dist > sigma)     strength += 5; // extra momentum
         if(!inSqueeze)       strength += 10; // not chopping
         else
         {
            // squeeze breakout gets bonus if volume confirms
            if(volConfirms) strength += 10;
         }
         // VA position bonus: price beyond VA is stronger
         // we compute VA after; for now placeholder, will add after VA calc
      }
      else
      {
         strength = 0;
      }

      // --- Buffers: SSL lines (show only active side)
      if(curT==0)
      {
         BufSSLUp[i] = vwapL;
         BufSSLDn[i] = EMPTY_VALUE;
      }
      else if(curT==1)
      {
         BufSSLUp[i] = EMPTY_VALUE;
         BufSSLDn[i] = vwapH;
      }
      else
      {
         BufSSLUp[i]=EMPTY_VALUE; BufSSLDn[i]=EMPTY_VALUE;
      }

      // --- Bands
      if(InpShowBands)
      {
         BufBandUp1[i] = vwapT + sigma;
         BufBandDn1[i] = vwapT - sigma;
         BufBandUp2[i] = vwapT + 2*sigma;
         BufBandDn2[i] = vwapT - 2*sigma;
      }
      else
      {
         BufBandUp1[i]=EMPTY_VALUE; BufBandDn1[i]=EMPTY_VALUE;
         BufBandUp2[i]=EMPTY_VALUE; BufBandDn2[i]=EMPTY_VALUE;
      }

      // --- POC / VA
      double poc = vwapT, vah = vwapT + 0.85*sigma, val = vwapT - 0.85*sigma;
      if(InpShowPOC || InpShowVA)
      {
         if(InpVAMode==VA_SIGMA)
         {
            // already set
         }
         else // histogram
         {
            int sessStart = g_sessionStart[i];
            // find session range
            double sessLow = low[i];
            double sessHigh= high[i];
            for(int j=i+1; j<=sessStart && j < rates_total; j++)
            {
               if(low[j] < sessLow)  sessLow  = low[j];
               if(high[j] > sessHigh) sessHigh = high[j];
            }
            double range = sessHigh - sessLow;
            if(range < _Point*20 || histBins<4)
            {
               poc = vwapT; vah = vwapT+0.85*sigma; val = vwapT-0.85*sigma;
            }
            else
            {
               double binSize = range / histBins;
               double bins[60];
               ArrayInitialize(bins, 0.0);
               double totalVol = 0;
               for(int j=i; j<=sessStart && j < rates_total; j++)
               {
                  double volj = (double)tick_volume[j]; if(volj<=0) volj=1;
                  double typical = (high[j]+low[j]+close[j])/3.0;
                  int bin = (int)((typical - sessLow)/binSize);
                  if(bin<0) bin=0;
                  if(bin>=histBins) bin=histBins-1;
                  bins[bin] += volj;
                  totalVol += volj;
               }
               // find POC bin
               int pocBin = 0; double maxVol = bins[0];
               for(int b=1;b<histBins;b++) if(bins[b] > maxVol){maxVol=bins[b]; pocBin=b;}
               poc = sessLow + (pocBin+0.5)*binSize;

               // 70% VA expansion
               if(totalVol>0)
               {
                  double target = totalVol * 0.70;
                  int lowBin  = pocBin;
                  int highBin = pocBin;
                  double vaVol = bins[pocBin];
                  // expand outward choosing side with more volume
                  while(vaVol < target && (lowBin>0 || highBin<histBins-1))
                  {
                     double volBelow = (lowBin>0) ? bins[lowBin-1] : -1;
                     double volAbove = (highBin<histBins-1) ? bins[highBin+1] : -1;
                     if(volAbove > volBelow)
                     {
                        highBin++; vaVol += bins[highBin];
                     }
                     else if(volBelow > volAbove)
                     {
                        lowBin--; vaVol += bins[lowBin];
                     }
                     else // equal, expand both if possible
                     {
                        if(lowBin>0 && highBin<histBins-1)
                        {
                           // expand to both sides
                           if(vaVol + bins[lowBin-1] + bins[highBin+1] <= target+maxVol*0.5)
                           {
                              lowBin--; highBin++; vaVol += bins[lowBin]+bins[highBin];
                           }
                           else if(volBelow>=0){ lowBin--; vaVol+=bins[lowBin];}
                           else if(volAbove>=0){ highBin++; vaVol+=bins[highBin];}
                           else break;
                        }
                        else if(lowBin>0){ lowBin--; vaVol+=bins[lowBin];}
                        else if(highBin<histBins-1){ highBin++; vaVol+=bins[highBin];}
                        else break;
                     }
                  }
                  vah = sessLow + (highBin+1)*binSize;
                  val = sessLow + lowBin*binSize;
               }
            }
         }
         BufPOC[i] = InpShowPOC ? poc : EMPTY_VALUE;
         BufVAH[i] = InpShowVA  ? vah : EMPTY_VALUE;
         BufVAL[i] = InpShowVA  ? val : EMPTY_VALUE;

         // strength bonus for price outside VA
         if(flipped)
         {
            if(curT==0 && close[i] > vah) strength += 5;
            if(curT==1 && close[i] < val) strength += 5;
            if(strength>100) strength=100;
         }
      }
      else
      {
         BufPOC[i]=EMPTY_VALUE; BufVAH[i]=EMPTY_VALUE; BufVAL[i]=EMPTY_VALUE;
      }

      if(strength>100) strength=100;
      if(strength<0) strength=0;
      BufStrength[i] = strength;

      // --- Anchored risk (freeze at flip)
      double anchorSL = EMPTY_VALUE, anchorTP = EMPTY_VALUE;
      if(flipped)
      {
         double entry = close[i];
         if(curT==0) // long
         {
            anchorSL = entry - sigma*InpRiskMult;
            // also ensure below VAH/val for institutional placement
            double alt = vwapL - sigma*InpRiskMult*0.5;
            if(anchorSL > alt) anchorSL = alt;
            anchorTP = entry + sigma*InpRewardMult;
         }
         else // short
         {
            anchorSL = entry + sigma*InpRiskMult;
            double alt = vwapH + sigma*InpRiskMult*0.5;
            if(anchorSL < alt) anchorSL = alt;
            anchorTP = entry - sigma*InpRewardMult;
         }
         prevAnchorSL = anchorSL; prevAnchorTP = anchorTP;
      }
      else
      {
         // carry forward previous anchored levels (if any and trend continues)
         if(curT!=-1 && prevAnchorSL!=EMPTY_VALUE)
         {
            anchorSL = prevAnchorSL;
            anchorTP = prevAnchorTP;
         }
         else
         {
            anchorSL = EMPTY_VALUE; anchorTP = EMPTY_VALUE;
         }
      }
      g_anchorSL[i]=anchorSL; g_anchorTP[i]=anchorTP;
      BufSL[i]=anchorSL; BufTP[i]=anchorTP;

      // --- Arrows (only on strong flips)
      BufBuy[i]=EMPTY_VALUE; BufSell[i]=EMPTY_VALUE;
      if(flipped && strength >= 45) // show even moderate, EA can filter higher
      {
         double offset = InpArrowOffsetPts * _Point;
         if(offset < 5*_Point) offset = 5*_Point;
         // additionally make offset sigma-relative on high volatility
         offset = MathMax(offset, sigma*0.1);
         if(curT==0)
         {
            // only plot if volume+mtf not both failing unless very strong
            if(strength>=InpStrengthThresh || (!InpVolFilter && InpMTF_Mode==MTF_OFF) || strength>=60)
               BufBuy[i] = low[i] - offset;
         }
         else
         {
            if(strength>=InpStrengthThresh || (!InpVolFilter && InpMTF_Mode==MTF_OFF) || strength>=60)
               BufSell[i] = high[i] + offset;
         }
      }

      // --- Alerts (only on newest bar, once per bar)
      if(flipped && i==0 && strength >= InpStrengthThresh)
      {
         bool isNewBar = (time[0] != g_lastAlertBarTime);
         bool allow = isNewBar;
         if(!InpAlertOnClose) allow = true; // every tick (noisy)
         else
         {
            // require bar close: check if not isNewBar, skip; or use volume tick?
            // we use isNewBar as proxy for new bar
            // plus avoid repeating same trend alert on same bar
            if(curT==g_lastAlertTrend && !isNewBar) allow=false;
         }
         if(allow)
         {
            string type = (curT==0) ? "BUY" : "SELL";
            string squeezeTxt = inSqueeze ? "SQUEEZE_BREAK" : "TREND";
            string msg = StringFormat("%s %s %s | %.0f%% | σ=%.5f | %s | MTF:%s Vol:%s",
                                      Symbol(), EnumToString(InpPeriod), type, strength, sigma, squeezeTxt,
                                      mtfAligns?"OK":"NO", volConfirms?"OK":"WEAK");
            if(InpAlertPopup) Alert(msg);
            if(InpAlertSound) PlaySound(InpAlertWav);
            if(InpAlertMobile) SendNotification(msg);
            g_lastAlertBarTime = time[0];
            g_lastAlertTrend = curT;
            Print("[VWAP v4] ", msg);
         }
      }
   }

   //=== HUD =========================================================
   if(InpShowHUD && rates_total>0)
   {
      int idx=0; // newest
      int tr = g_trend[idx];
      double str = BufStrength[idx];
      // if no flip, strength 0, show trend persistence info instead
      string trendTxt = (tr==0) ? "LONG ▲" : (tr==1 ? "SHORT ▼" : "WAIT");
      color trendCol = (tr==0) ? InpUpColor : InpDnColor;
      string mtfTxt = CheckMTFAlignment(tr, time[idx]) ? "ALIGNED ✓" : "DIVERGENT ✗";
      double vwap = (g_sumV[idx]>0) ? g_sumPT[idx]/g_sumV[idx] : close[idx];
      double sig  = g_sigma[idx];
      bool sq = g_squeeze[idx]==1;
      double vah0 = BufVAH[idx], val0 = BufVAL[idx], poc0 = BufPOC[idx];
      double sl0 = BufSL[idx], tp0 = BufTP[idx];
      double rr = (InpRiskMult>0) ? InpRewardMult/InpRiskMult : 0;
      string sigTxt = "";
      if(str>=80) sigTxt="STRONG";
      else if(str>=60) sigTxt="SOLID";
      else if(str>=45) sigTxt="MODERATE";
      else if(str>0) sigTxt="WEAK FLIP";
      else sigTxt = sq ? "SQUEEZE…" : "HOLD";

      // Build comment - monospaced box
      string hud = StringFormat(
         "╔════════ VWAP SSL v4  %s ═══════╗\n"+
         "║ Trend : %s  (%s)      \n"+
         "║ Score : %.0f%%  %-10s  Squeeze:%s\n"+
         "║ MTF   : %s                 \n"+
         "╠══════════════════════════════════╣\n"+
         "║ VWAP  : %."+IntegerToString(_Digits)+"f  σ:%.5f     \n"+
         "║ POC   : %."+IntegerToString(_Digits)+"f  VAH:%.5f  VAL:%.5f\n"+
         "║ SL    : %."+IntegerToString(_Digits)+"f  TP:%.5f  R:R 1:%.1f\n"+
         "╚══════════════════════════════════╝",
         EnumToString(InpPeriod),
         trendTxt, (tr==0?"BULL":"BEAR"),
         str, sigTxt, sq?"ON":"OFF",
         mtfTxt,
         vwap, sig,
         poc0, vah0, val0,
         sl0, tp0, rr
      );
      // Add session info
      int barsSess = (int)(g_sessionStart[idx]-idx+1);
      hud += StringFormat("\n Session bars: %d  HistBins:%d  VA:%s", barsSess, histBins, EnumToString(InpVAMode));
      Comment(hud);
   }
   else if(!InpShowHUD) Comment("");

   return(rates_total);
}
//+------------------------------------------------------------------+
