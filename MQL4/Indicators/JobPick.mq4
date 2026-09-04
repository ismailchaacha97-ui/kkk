//+------------------------------------------------------------------+
//|                                                      JobPick.mq4 |
//|  v1.10                                                            |
//|                                                                  |
//|  VOTES (directional evidence, 3):                                 |
//|    Bias .......... VWAP (intraday) or 200 EMA (swing)             |
//|    Trend ......... 20 / 50 EMA                                    |
//|    Momentum ...... RSI(14) or MACD histogram, fresh turn only     |
//|                                                                  |
//|  GATES (pass/fail filters, 7):                                    |
//|    Regime ........ ADX >= min (+/-DI agreement)                   |
//|    Participation . RVOL >= threshold                              |
//|    Extension ..... price not stretched from fair value            |
//|    Spread ........ spread <= max pips                             |
//|    Session ....... broker-hour window                             |
//|    HTF ........... higher timeframe alignment                     |
//|    ATR floor ..... market not dead                                |
//|    Cooldown ...... min bars between signals                       |
//|                                                                  |
//|  RISK: ATR stop/target, ratcheting chandelier trail, breakeven    |
//+------------------------------------------------------------------+
#property copyright "JobPick"
#property version   "1.10"
#property strict
#property description "Votes (bias/trend/momentum) + Gates (regime/volume/cost/HTF) + ATR risk"
#property indicator_chart_window

#property indicator_buffers 8
#property indicator_color1  Orange          // VWAP
#property indicator_color2  DeepSkyBlue     // bias EMA (200)
#property indicator_color3  Lime            // fast EMA (20)
#property indicator_color4  Gold            // slow EMA (50)
#property indicator_color5  MediumSeaGreen  // ATR chandelier trail (longs)
#property indicator_color6  OrangeRed       // ATR chandelier trail (shorts)
#property indicator_color7  Lime            // buy arrow
#property indicator_color8  Red             // sell arrow

#define PREFIX     "JobPick_"
#define ARROW_UP   233
#define ARROW_DOWN 234

//+------------------------------------------------------------------+
//| Enums                                                             |
//+------------------------------------------------------------------+
enum ENUM_BIAS_MODE
  {
   BIAS_VWAP = 0,   // VWAP (intraday fair value)
   BIAS_EMA  = 1,   // 200 EMA (swing fair value)
   BIAS_BOTH = 2    // Both must agree
  };

enum ENUM_MOM_MODE
  {
   MOM_RSI  = 0,    // RSI(14) + slope
   MOM_MACD = 1     // MACD histogram + zero-line cross
  };

enum ENUM_VWAP_ANCHOR
  {
   VWAP_DAY   = 0,  // Reset at broker midnight
   VWAP_WEEK  = 1,  // Reset at start of week (Monday)
   VWAP_HOURS = 2   // Reset at custom broker hour
  };

enum ENUM_VOL_SOURCE
  {
   VOL_TICK = 0,    // Tick volume (every MT4 broker)
   VOL_REAL = 1     // Real volume (exchange instruments)
  };

enum ENUM_HTF
  {
   HTF_OFF = 0,
   HTF_M15 = 15,
   HTF_M30 = 30,
   HTF_H1  = 16385,
   HTF_H4  = 16388,
   HTF_D1  = 16408
  };

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
//--- 1. Bias / fair value (VOTE)
input ENUM_BIAS_MODE   InpBiasMode         = BIAS_VWAP;  // Bias source
input bool             InpShowVWAP         = true;       // Draw VWAP
input ENUM_VWAP_ANCHOR InpVWAPAnchor       = VWAP_DAY;   // VWAP anchor
input int              InpSessionStartHour = 0;          // Start hour (VWAP_HOURS only)
input bool             InpShowEMABias      = true;       // Draw 200 EMA
input int              InpEMABiasPeriod    = 200;        // Bias EMA period

//--- 2. Trend structure (VOTE)
input bool             InpShowTrendEMAs    = true;       // Draw 20/50 EMA
input int              InpEMAFast          = 20;         // Fast EMA
input int              InpEMASlow          = 50;         // Slow EMA

//--- 3. Momentum (VOTE)
input ENUM_MOM_MODE    InpMomentumMode     = MOM_RSI;    // Momentum engine
input int              InpRSIPeriod        = 14;         // RSI period
input int              InpRSIMid           = 50;         // RSI bull/bear line
input int              InpRSIOversold      = 35;         // RSI oversold (bounce trigger)
input int              InpRSIOverbought    = 65;         // RSI overbought (fade trigger)
input int              InpMACDFast         = 12;         // MACD fast
input int              InpMACDSlow         = 26;         // MACD slow
input int              InpMACDSignal       = 9;          // MACD signal
input bool             InpMomReset         = false;      // Require a fresh momentum turn
input int              InpMomResetBars     = 12;         // ... within this many bars
input double           InpMomResetBuffer   = 10.0;       // ... pullback depth (RSI pts)

//--- 3b. MEAN REVERSION (only where the trend leg is blocked: ADX < threshold)
input bool             InpUseMR            = true;       // Fade extremes when ADX is low
input double           InpMRADXMax         = 25.0;       // MR only fires when ADX below this
input double           InpMRExtATR         = 1.50;       // Min stretch from the mean (ATR)
input double           InpMRStopATR        = 1.00;       // MR stop distance (ATR)
input int              InpMRRsiOS          = 35;         // RSI oversold -> fade long
input int              InpMRRsiOB          = 65;         // RSI overbought -> fade short
input double           InpMRMinRR          = 1.00;       // Min reward:risk to the mean
input ENUM_MR_BASE     InpMRBase           = MR_FASTEMA; // Mean to revert to

//--- 4. GATES
input bool             InpUseADXGate       = true;       // Use ADX regime gate
input int              InpADXPeriod        = 14;         // ADX period
input double           InpADXMin           = 25.0;       // Min ADX (below = chop, no trade)
input bool             InpUseDIAgree       = true;       // Require +DI/-DI agreement
input bool             InpUseVolGate       = true;       // Use RVOL participation gate
input ENUM_VOL_SOURCE  InpVolumeSource     = VOL_TICK;   // Volume source
input int              InpRVOLPeriod       = 20;         // RVOL average period
input double           InpRVOLThreshold    = 1.20;       // Min RVOL
input bool             InpUseExtGate       = true;       // Use anti-chase gate
input bool             InpExtAdaptive      = true;       // Adaptive extension baseline
input double           InpMaxExtATR        = 2.00;       // Max dist from fair value (ATR)
input double           InpMaxExtEMATrend   = 2.50;       // Max dist from fast EMA (ATR)
input bool             InpUseSpreadGate    = true;       // Use spread gate
input double           InpMaxSpreadPips    = 2.0;        // Max spread (pips)
input bool             InpUseSessionGate   = false;      // Use session window gate
input int              InpSessionFrom      = 8;          // Session start hour (broker)
input int              InpSessionTo        = 18;         // Session end hour (broker)
input bool             InpUseHTFGate       = false;      // Use higher-timeframe gate
input ENUM_HTF         InpHTF              = HTF_H1;     // Higher timeframe
input int              InpHTFPeriod        = 50;         // HTF EMA period
input bool             InpHTFUseClosed     = true;       // Use last closed HTF bar
input bool             InpUseATRFloor      = false;      // Use minimum-volatility gate
input double           InpMinATRPips       = 5.0;        // Min ATR (pips)
input int              InpCooldownBars     = 5;          // Min bars between signals

//--- 5. Risk (ATR)
input int              InpATRPeriod        = 14;         // ATR period
input double           InpATRStopMult      = 1.50;       // Stop = ATR x this
input double           InpRiskReward       = 2.00;       // Target = stop x this
input bool             InpShowATRTrail     = true;       // Draw ATR chandelier trail
input int              InpTrailLookback    = 10;         // Chandelier lookback bars
input bool             InpUseBreakeven     = true;       // Move stop to entry at 1R
input bool             InpShowLevels       = true;       // Draw last SL / TP lines

//--- 6. Signals & alerts
input int              InpMinVotes         = 3;          // Min directional votes (1-3)
input bool             InpShowArrows       = true;       // Draw signal arrows
input bool             InpAlertOnSignal    = true;       // Pop-up alert
input bool             InpPushOnSignal     = false;      // Push notification

//--- 7. Dashboard
input bool             InpShowDashboard    = true;       // Show dashboard
input int              InpPanelCorner      = 0;          // Corner 0=TL 1=TR 2=BL 3=BR
input int              InpFontSize         = 9;          // Font size

//--- 8. Performance
input int              InpMaxBars          = 2000;       // Max bars calculated

//+------------------------------------------------------------------+
//| Buffers                                                           |
//+------------------------------------------------------------------+
double VWAPBuf[];
double EMABiasBuf[];
double EMAFastBuf[];
double EMASlowBuf[];
double TrailUpBuf[];
double TrailDnBuf[];
double BuyArrowBuf[];
double SellArrowBuf[];

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
int      g_ratesTotal    = 0;
int      g_sigDir        = 0;     // last bar's final direction (-1/0/1)
int      g_trailDir      = 0;     // chandelier direction
double   g_trailVal      = 0.0;   // chandelier level
bool     g_beDone        = false; // breakeven already triggered
int      g_lastSigIdx    = 0;     // bar index of last signal (cooldown)
datetime g_lastAlertTime = 0;

int      g_sigType       = 0;     // last signal: +1 buy / -1 sell
double   g_sigPrice      = 0.0;
double   g_sigStop       = 0.0;
double   g_sigTarget     = 0.0;
datetime g_sigTime       = 0;
bool     g_sigMR         = false; // last signal was a mean-reversion fade
bool     g_isMR          = false; // current bar is a fade (not a trend entry)
double   g_mrStretch     = 0.0;   // stretch from the mean, in ATR
double   g_mrRR          = 0.0;   // reward:risk to the mean

//--- bar-0 snapshot for the dashboard
double   g_dFair=0.0, g_dATR=0.0, g_dRSI=0.0, g_dHist=0.0, g_dRVOL=0.0, g_dADX=0.0;
int      g_bullVotes=0, g_bearVotes=0, g_dirNow=0;
bool     g_bBiasBull=false, g_bTrendBull=false, g_bMomBull=false;
bool     g_gADX=true, g_gVol=true, g_gExt=true, g_gSpr=true, g_gSes=true, g_gHTF=true, g_gATR=true;
bool     g_gCool=true;
string   g_blockers="";

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0,VWAPBuf);      SetIndexLabel(0,"VWAP");
   SetIndexBuffer(1,EMABiasBuf);   SetIndexLabel(1,"EMA Bias");
   SetIndexBuffer(2,EMAFastBuf);   SetIndexLabel(2,"EMA Fast");
   SetIndexBuffer(3,EMASlowBuf);   SetIndexLabel(3,"EMA Slow");
   SetIndexBuffer(4,TrailUpBuf);   SetIndexLabel(4,"ATR Trail Long");
   SetIndexBuffer(5,TrailDnBuf);   SetIndexLabel(5,"ATR Trail Short");
   SetIndexBuffer(6,BuyArrowBuf);  SetIndexLabel(6,"Buy");
   SetIndexBuffer(7,SellArrowBuf); SetIndexLabel(7,"Sell");

   SetIndexStyle(0,DRAW_LINE,STYLE_SOLID,2);
   SetIndexStyle(1,DRAW_LINE,STYLE_SOLID,2);
   SetIndexStyle(2,DRAW_LINE,STYLE_SOLID,1);
   SetIndexStyle(3,DRAW_LINE,STYLE_SOLID,1);
   SetIndexStyle(4,DRAW_LINE,STYLE_DASHDOT,1);
   SetIndexStyle(5,DRAW_LINE,STYLE_DASHDOT,1);
   SetIndexStyle(6,DRAW_ARROW,STYLE_SOLID,2);
   SetIndexStyle(7,DRAW_ARROW,STYLE_SOLID,2);
   SetIndexArrow(6,ARROW_UP);
   SetIndexArrow(7,ARROW_DOWN);

   for(int b=0; b<6; b++)
      SetIndexEmptyValue(b,0.0);
   SetIndexEmptyValue(6,EMPTY_VALUE);
   SetIndexEmptyValue(7,EMPTY_VALUE);

   SetIndexDrawBegin(1,InpEMABiasPeriod);
   SetIndexDrawBegin(2,InpEMAFast);
   SetIndexDrawBegin(3,InpEMASlow);

   ArrayInitialize(BuyArrowBuf,EMPTY_VALUE);
   ArrayInitialize(SellArrowBuf,EMPTY_VALUE);

   ArraySetAsSeries(VWAPBuf,true);
   ArraySetAsSeries(EMABiasBuf,true);
   ArraySetAsSeries(EMAFastBuf,true);
   ArraySetAsSeries(EMASlowBuf,true);
   ArraySetAsSeries(TrailUpBuf,true);
   ArraySetAsSeries(TrailDnBuf,true);
   ArraySetAsSeries(BuyArrowBuf,true);
   ArraySetAsSeries(SellArrowBuf,true);

   IndicatorShortName("JobPick("+(InpBiasMode==BIAS_EMA ? "EMA"+IntegerToString(InpEMABiasPeriod) : "VWAP")
                      +" | "+IntegerToString(InpEMAFast)+"/"+IntegerToString(InpEMASlow)
                      +" | "+(InpMomentumMode==MOM_RSI ? "RSI"+IntegerToString(InpRSIPeriod) : "MACD")
                      +" | ATR"+IntegerToString(InpATRPeriod)+")");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,PREFIX,0,-1);
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
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
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);
   ArraySetAsSeries(tick_volume,true);
   ArraySetAsSeries(volume,true);

   g_ratesTotal = rates_total;

   int minBars = (int)MathMax(InpEMASlow,InpEMABiasPeriod) + InpRVOLPeriod + InpTrailLookback + 20;
   if(rates_total < minBars)
      return(0);

//--- how far back to (re)calculate
   int limit;
   if(prev_calculated <= 0)
     {
      limit = (int)MathMin(rates_total-1,InpMaxBars);
      g_sigDir=0; g_trailDir=0; g_trailVal=0.0; g_beDone=false;
      g_lastAlertTime=0; g_lastSigIdx=1000000;
      g_sigType=0; g_sigPrice=0.0; g_sigStop=0.0; g_sigTarget=0.0; g_sigTime=0;
      ArrayInitialize(BuyArrowBuf,EMPTY_VALUE);
      ArrayInitialize(SellArrowBuf,EMPTY_VALUE);
     }
   else
     {
      limit = rates_total - prev_calculated;
      if(limit < 1)
         limit = 1;
      g_lastSigIdx += (rates_total - prev_calculated);   // indices shift by new bars
     }
   if(limit > rates_total-1)
      limit = rates_total-1;

//--- VWAP is path dependent: start from the first bar of the session holding 'limit'
   int    start   = SessionStartIndex(limit,time,rates_total);
   double cumPV   = 0.0;
   double cumVol  = 0.0;
   bool   needEMA = (InpBiasMode != BIAS_VWAP) || InpShowEMABias;
   int    minVotes= (int)MathMax(1,MathMin(3,InpMinVotes));
   double pipFac  = (_Digits==3 || _Digits==5) ? 10.0 : 1.0;
   double spreadPts = MarketInfo(Symbol(),MODE_SPREAD);

//--- oldest -> newest
   for(int i=start; i>=0; i--)
     {
      //---------------- VWAP (session anchored) ---------------------
      if(i < rates_total-1 && SessionId(time[i]) != SessionId(time[i+1]))
        {
         cumPV  = 0.0;
         cumVol = 0.0;
        }
      double typ = (high[i] + low[i] + close[i]) / 3.0;
      double vol = VolAt(i,tick_volume,volume);
      cumPV  += typ * vol;
      cumVol += vol;
      double vwap = (cumVol > 0.0) ? cumPV / cumVol : typ;

      if(i > limit)
         continue;

      //---------------- Moving averages / ATR -----------------------
      double emaBias = 0.0;
      if(needEMA)
         emaBias = iMA(NULL,0,InpEMABiasPeriod,0,MODE_EMA,PRICE_CLOSE,i);
      double emaFast = iMA(NULL,0,InpEMAFast,0,MODE_EMA,PRICE_CLOSE,i);
      double emaSlow = iMA(NULL,0,InpEMASlow,0,MODE_EMA,PRICE_CLOSE,i);
      if(emaFast == 0.0 || emaSlow == 0.0)
         continue;

      double atr = iATR(NULL,0,InpATRPeriod,i);
      if(atr <= 0.0)
         atr = high[i] - low[i];

      //---------------- Momentum ------------------------------------
      double rsi=0.0, rsiPrev=0.0, hist=0.0, histPrev=0.0;
      if(InpMomentumMode == MOM_RSI || InpUseMR)   // MR needs RSI even in MACD mode
        {
         rsi     = iRSI(NULL,0,InpRSIPeriod,PRICE_CLOSE,i);
         rsiPrev = iRSI(NULL,0,InpRSIPeriod,PRICE_CLOSE,i+1);
        }
      if(InpMomentumMode == MOM_MACD)
        {
         hist     = MacdHist(i);
         histPrev = MacdHist(i+1);
        }

      //---------------- RVOL ----------------------------------------
      double rvol  = 0.0;
      bool   volOK = true;
      if(i + InpRVOLPeriod + 1 < rates_total)
        {
         double av = 0.0;
         for(int k=1; k<=InpRVOLPeriod; k++)
            av += VolAt(i+k,tick_volume,volume);
         av /= (double)InpRVOLPeriod;
         if(av > 0.0)
           {
            rvol  = vol / av;
            volOK = (rvol >= InpRVOLThreshold);
           }
        }

      //=========== VOTE 1: bias / fair value ========================
      bool biasBull=false, biasBear=false;
      if(InpBiasMode == BIAS_VWAP)
        {
         biasBull = (close[i] > vwap);
         biasBear = (close[i] < vwap);
        }
      else if(InpBiasMode == BIAS_EMA)
        {
         if(emaBias > 0.0)
           {
            biasBull = (close[i] > emaBias);
            biasBear = (close[i] < emaBias);
           }
        }
      else if(emaBias > 0.0)
        {
         biasBull = (close[i] > vwap && close[i] > emaBias);
         biasBear = (close[i] < vwap && close[i] < emaBias);
        }

      //=========== VOTE 2: trend structure ==========================
      bool trendBull = (emaFast > emaSlow);
      bool trendBear = (emaFast < emaSlow);

      //=========== VOTE 3: momentum =================================
      bool momBull=false, momBear=false;
      if(InpMomentumMode == MOM_RSI)
        {
         momBull = ((rsi > InpRSIMid && rsi > rsiPrev) ||
                    (rsiPrev <= InpRSIOversold && rsi > rsiPrev));
         momBear = ((rsi < InpRSIMid && rsi < rsiPrev) ||
                    (rsiPrev >= InpRSIOverbought && rsi < rsiPrev));
         if(InpMomReset)
           {
            // require a real pullback first, not a trending continuation
            momBull = momBull && (MinRSI(i,InpMomResetBars) <= InpRSIMid + InpMomResetBuffer);
            momBear = momBear && (MaxRSI(i,InpMomResetBars) >= InpRSIMid - InpMomResetBuffer);
           }
        }
      else
        {
         momBull = ((hist > 0.0 && hist > histPrev) || (histPrev <= 0.0 && hist > 0.0));
         momBear = ((hist < 0.0 && hist < histPrev) || (histPrev >= 0.0 && hist < 0.0));
         if(InpMomReset)
           {
            momBull = momBull && (MinHist(i,InpMomResetBars) <= 0.0);
            momBear = momBear && (MaxHist(i,InpMomResetBars) >= 0.0);
           }
        }

      int bullVotes = (biasBull ?1:0) + (trendBull ?1:0) + (momBull ?1:0);
      int bearVotes = (biasBear ?1:0) + (trendBear ?1:0) + (momBear ?1:0);

      int dirNow = 0;
      int votes  = 0;
      if(bullVotes >= minVotes && bullVotes > bearVotes)
        { dirNow = 1;  votes = bullVotes; }
      else
      if(bearVotes >= minVotes && bearVotes > bullVotes)
        { dirNow = -1; votes = bearVotes; }

      //=========== GATES ============================================
      double fairVal = (InpBiasMode == BIAS_EMA) ? emaBias : vwap;
      if(fairVal <= 0.0)
         fairVal = vwap;

      double adx = iADX(NULL,0,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,i);

      //=========== MEAN REVERSION (only when the trend leg is off) ==
      //  Fade a stretch away from the mean, targeting the mean itself.
      //  Only ever reached when the trend votes failed, so it cannot
      //  cannibalise a trend entry.
      bool   isMR     = false;
      double mrStop   = 0.0;
      double mrTarget = 0.0;
      double mrMean   = fairVal;
      g_mrStretch = 0.0;
      g_mrRR      = 0.0;
      if(InpUseMR && dirNow == 0 && adx > 0.0 && adx < InpMRADXMax && atr > 0.0)
        {
         mrMean = (InpMRBase == MR_FASTEMA) ? emaFast : fairVal;
         double stretch = (close[i] - mrMean) / atr;
         if(stretch <= -InpMRExtATR && rsi <= InpMRRsiOS && close[i] > close[i+1])
           { dirNow = 1;  isMR = true; }
         else
         if(stretch >= InpMRExtATR && rsi >= InpMRRsiOB && close[i] < close[i+1])
           { dirNow = -1; isMR = true; }

         if(isMR)
           {
            mrStop   = atr * InpMRStopATR;
            mrTarget = mrMean;
            double reward = MathAbs(mrTarget - close[i]);
            if(mrStop <= 0.0 || reward / mrStop < InpMRMinRR)
              { dirNow = 0; isMR = false; }      // not enough room to the mean
            else
              { g_mrStretch = MathAbs(stretch); g_mrRR = reward / mrStop; }
           }
        }
      g_isMR = isMR;

      bool gADX=true, gVol=true, gExt=true, gSpr=true, gSes=true, gHTF=true, gATR=true, gCool=true;

      //--- regime: ADX (+ optional DI agreement). Skipped for fades, which
      //    are defined by low ADX in the first place.
      if(!isMR && InpUseADXGate)
        {
         if(adx < InpADXMin)
            gADX = false;
         if(InpUseDIAgree)
           {
            double pdi = iADX(NULL,0,InpADXPeriod,PRICE_CLOSE,MODE_PLUSDI,i);
            double mdi = iADX(NULL,0,InpADXPeriod,PRICE_CLOSE,MODE_MINUSDI,i);
            if(dirNow == 1  && !(pdi > mdi)) gADX = false;
            if(dirNow == -1 && !(mdi > pdi)) gADX = false;
           }
        }

      //--- participation (not required for fades: a volume spike in a range
      //    usually means breakout, so requiring it would fight the fade)
      if(!isMR && InpUseVolGate && !volOK)
         gVol = false;

      //--- anti-chase: distance from the regime-appropriate baseline.
      //    In a range, "extended" means far from fair value (fade risk).
      //    In a trend, it means far from the fast EMA (chase risk) - using
      //    VWAP here kills trends, because VWAP resets every session.
      if(!isMR && InpUseExtGate && atr > 0.0)
        {
         double base = fairVal;
         double thr  = InpMaxExtATR;
         if(InpExtAdaptive && adx >= InpADXMin)
           {
            base = emaFast;
            thr  = InpMaxExtEMATrend;
           }
         double ext = MathAbs(close[i] - base) / atr;
         if(ext > thr)
            gExt = false;
        }

      //--- cost: spread
      if(InpUseSpreadGate && spreadPts > InpMaxSpreadPips * pipFac)
         gSpr = false;

      //--- session window (broker time)
      if(InpUseSessionGate)
        {
         int hr = TimeHour(time[i]);
         if(InpSessionFrom <= InpSessionTo)
           { if(hr < InpSessionFrom || hr > InpSessionTo) gSes = false; }
         else
           { if(hr < InpSessionFrom && hr > InpSessionTo) gSes = false; }
        }

      //--- higher timeframe alignment
      if(!isMR && InpUseHTFGate && (int)InpHTF > 0 && (int)InpHTF != Period())
        {
         int hb = iBarShift(NULL,(int)InpHTF,time[i],false);
         if(InpHTFUseClosed)
            hb = hb + 1;
         if(hb >= 0)
           {
            double htfMA    = iMA(NULL,(int)InpHTF,InpHTFPeriod,0,MODE_EMA,PRICE_CLOSE,hb);
            double htfClose = iClose(NULL,(int)InpHTF,hb);
            if(htfMA > 0.0 && htfClose > 0.0)
              {
               if(dirNow == 1  && !(htfClose > htfMA)) gHTF = false;
               if(dirNow == -1 && !(htfClose < htfMA)) gHTF = false;
              }
           }
        }

      //--- volatility floor
      if(InpUseATRFloor && (atr/_Point) < InpMinATRPips * pipFac)
         gATR = false;

      //--- cooldown since last signal
      if(g_lastSigIdx - i < InpCooldownBars)
         gCool = false;

      bool allGates = (gADX && gVol && gExt && gSpr && gSes && gHTF && gATR && gCool);

      int dirFinal = (allGates ? dirNow : 0);

      //---------------- Plot buffers --------------------------------
      VWAPBuf[i]    = (InpShowVWAP ? vwap : 0.0);
      EMABiasBuf[i] = (InpShowEMABias && emaBias > 0.0) ? emaBias : 0.0;
      EMAFastBuf[i] = (InpShowTrendEMAs ? emaFast : 0.0);
      EMASlowBuf[i] = (InpShowTrendEMAs ? emaSlow : 0.0);

      //---------------- RISK: chandelier trail + breakeven ----------
      double stopDist = isMR ? mrStop : atr * InpATRStopMult;
      if(!isMR && dirFinal == 1)
        {
         double hh = HighestHigh(i,InpTrailLookback);
         double s  = hh - stopDist;
         if(g_trailDir != 1)
           { g_trailVal = close[i] - stopDist; g_beDone = false; }
         if(InpUseBreakeven && !g_beDone && high[i] >= g_sigPrice + stopDist && g_sigPrice > 0.0)
            g_beDone = true;
         if(g_beDone)
            s = MathMax(s,g_sigPrice);
         g_trailVal = MathMax(g_trailVal,s);
         g_trailDir = 1;
        }
      else
      if(dirFinal == -1)
        {
         double ll = LowestLow(i,InpTrailLookback);
         double s  = ll + stopDist;
         if(g_trailDir != -1)
           { g_trailVal = close[i] + stopDist; g_beDone = false; }
         if(InpUseBreakeven && !g_beDone && low[i] <= g_sigPrice - stopDist && g_sigPrice > 0.0)
            g_beDone = true;
         if(g_beDone)
            s = MathMin(s,g_sigPrice);
         g_trailVal = MathMin(g_trailVal,s);
         g_trailDir = -1;
        }

      if(InpShowATRTrail && !isMR && g_trailDir == 1)
        { TrailUpBuf[i] = g_trailVal; TrailDnBuf[i] = 0.0; }
      else
      if(InpShowATRTrail && !isMR && g_trailDir == -1)
        { TrailDnBuf[i] = g_trailVal; TrailUpBuf[i] = 0.0; }
      else
        { TrailUpBuf[i] = 0.0; TrailDnBuf[i] = 0.0; }

      //---------------- Signals (closed bars only) -------------------
      if(InpShowArrows && i >= 1 && dirFinal != 0 && dirFinal != g_sigDir)
        {
         if(dirFinal == 1)
            BuyArrowBuf[i]  = low[i] - atr * 0.35;
         else
            SellArrowBuf[i] = high[i] + atr * 0.35;

         g_sigType   = dirFinal;
         g_sigPrice  = close[i];
         g_sigStop   = (dirFinal == 1) ? close[i] - stopDist : close[i] + stopDist;
         g_sigTarget = isMR ? mrTarget
                            : ((dirFinal == 1) ? close[i] + stopDist * InpRiskReward
                                               : close[i] - stopDist * InpRiskReward);
         g_sigMR     = isMR;
         g_sigTime   = time[i];
         g_lastSigIdx= i;
         g_beDone    = false;

         if(i == 1 && prev_calculated > 0 && time[i] != g_lastAlertTime)
           {
            g_lastAlertTime = time[i];
            string msg = "JobPick "+Symbol()+" "+TFToString()+" : "
                         +((dirFinal==1) ? "BUY" : "SELL")
                         +((isMR) ? " (FADE)" : "")
                         +" @ "+DoubleToString(close[i],_Digits)
                         +" | SL "+DoubleToString(g_sigStop,_Digits)
                         +" | TP "+DoubleToString(g_sigTarget,_Digits)
                         +" | ATR "+DoubleToString(atr/_Point,1)+"pt"
                         +" | ADX "+DoubleToString(adx,1)
                         +" | RVOL "+DoubleToString(rvol,2)
                         +" | votes "+IntegerToString(votes)+"/3";
            if(InpAlertOnSignal)
               Alert(msg);
            if(InpPushOnSignal)
               SendNotification(msg);
           }
        }
      g_sigDir = dirFinal;

      //---------------- Dashboard snapshot (bar 0) -------------------
      if(i == 0)
        {
         g_dFair     = fairVal;
         g_dATR      = atr;
         g_dRSI      = rsi;
         g_dHist     = hist;
         g_dRVOL     = rvol;
         g_dADX      = adx;
         g_bullVotes = bullVotes;
         g_bearVotes = bearVotes;
         g_dirNow    = dirNow;
         g_bBiasBull = biasBull;
         g_bTrendBull= trendBull;
         g_bMomBull  = momBull;
         g_gADX=gADX; g_gVol=gVol; g_gExt=gExt; g_gSpr=gSpr;
         g_gSes=gSes; g_gHTF=gHTF; g_gATR=gATR; g_gCool=gCool;

         g_blockers = "";
         if(!gADX) g_blockers += "ADX ";
         if(!gVol) g_blockers += "VOL ";
         if(!gExt) g_blockers += "EXT ";
         if(!gSpr) g_blockers += "SPR ";
         if(!gSes) g_blockers += "SES ";
         if(!gHTF) g_blockers += "HTF ";
         if(!gATR) g_blockers += "ATR ";
         if(!gCool) g_blockers += "COOL ";
        }
     }

   if(InpShowLevels)
      DrawLevels();
   else
      DeleteLevels();

   if(InpShowDashboard)
      DrawPanel();
   else
      DeletePanel();

   ChartRedraw();
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Volume at bar i                                                   |
//+------------------------------------------------------------------+
double VolAt(int i,const long &tick_volume[],const long &volume[])
  {
   double v = (InpVolumeSource == VOL_REAL) ? (double)volume[i] : (double)tick_volume[i];
   if(v <= 0.0)
      v = (double)tick_volume[i];
   if(v <= 0.0)
      v = 1.0;
   return(v);
  }

//+------------------------------------------------------------------+
//| MACD histogram (MQL4 iMACD has MODE_MAIN / MODE_SIGNAL only)      |
//+------------------------------------------------------------------+
double MacdHist(int shift)
  {
   double main   = iMACD(NULL,0,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE,MODE_MAIN,shift);
   double signal = iMACD(NULL,0,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE,MODE_SIGNAL,shift);
   return(main - signal);
  }

//+------------------------------------------------------------------+
//| Momentum lookback helpers (bounds-safe)                           |
//+------------------------------------------------------------------+
double MinRSI(int i,int n)
  {
   double m = 1000.0;
   for(int k=0; k<n; k++)
      if(i+k < g_ratesTotal)
         m = MathMin(m,iRSI(NULL,0,InpRSIPeriod,PRICE_CLOSE,i+k));
   return(m);
  }

double MaxRSI(int i,int n)
  {
   double m = -1000.0;
   for(int k=0; k<n; k++)
      if(i+k < g_ratesTotal)
         m = MathMax(m,iRSI(NULL,0,InpRSIPeriod,PRICE_CLOSE,i+k));
   return(m);
  }

double MinHist(int i,int n)
  {
   double m = 1e10;
   for(int k=0; k<n; k++)
      if(i+k < g_ratesTotal)
         m = MathMin(m,MacdHist(i+k));
   return(m);
  }

double MaxHist(int i,int n)
  {
   double m = -1e10;
   for(int k=0; k<n; k++)
      if(i+k < g_ratesTotal)
         m = MathMax(m,MacdHist(i+k));
   return(m);
  }

double HighestHigh(int i,int n)
  {
   double hh = -1e10;
   for(int k=0; k<n; k++)
      if(i+k < g_ratesTotal)
         hh = MathMax(hh,iHigh(NULL,0,i+k));
   return(hh);
  }

double LowestLow(int i,int n)
  {
   double ll = 1e10;
   for(int k=0; k<n; k++)
      if(i+k < g_ratesTotal)
         ll = MathMin(ll,iLow(NULL,0,i+k));
   return(ll);
  }

//+------------------------------------------------------------------+
//| Session id (unique per VWAP anchor period)                        |
//+------------------------------------------------------------------+
int SessionId(datetime t)
  {
   MqlDateTime st;
   if(!TimeToStruct(t,st))
      return(0);

   if(InpVWAPAnchor == VWAP_WEEK)
     {
      int back = (st.day_of_week + 6) % 7;
      return(st.year*1000 + (st.day_of_year - back));
     }

   if(InpVWAPAnchor == VWAP_HOURS)
     {
      MqlDateTime sd;
      if(!TimeToStruct(t - InpSessionStartHour*3600,sd))
         return(0);
      return(sd.year*1000 + sd.day_of_year);
     }

   return(st.year*1000 + st.day_of_year);
  }

//+------------------------------------------------------------------+
//| Index of the oldest bar in the session containing bar i           |
//+------------------------------------------------------------------+
int SessionStartIndex(int i,const datetime &time[],int rates_total)
  {
   int id    = SessionId(time[i]);
   int k     = i;
   int max   = rates_total - 1;
   int guard = 0;
   while(k < max && guard < 50000)
     {
      if(SessionId(time[k+1]) != id)
         break;
      k++;
      guard++;
     }
   return(k);
  }

//+------------------------------------------------------------------+
//| Timeframe name                                                    |
//+------------------------------------------------------------------+
string TFToString()
  {
   switch(Period())
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN");
     }
   return("M"+IntegerToString(Period()/60));
  }

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void DrawPanel()
  {
   int corner = (int)MathMax(0,MathMin(3,InpPanelCorner));
   int fs     = (int)MathMax(7,MathMin(14,InpFontSize));
   int lh     = fs + 4;
   int x      = 14;
   int y      = 22;
   int w      = fs * 30;
   int h      = 12 * lh + 10;

   string bg = PREFIX+"BG";
   if(ObjectFind(0,bg) < 0)
     {
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_CORNER,corner);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,x-6);
      ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,y-6);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,w+12);
      ObjectSetInteger(0,bg,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'18,18,22');
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bg,OBJPROP_COLOR,C'60,60,70');
      ObjectSetInteger(0,bg,OBJPROP_BACK,true);
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,bg,OBJPROP_SELECTED,false);
     }

   double pip     = (_Digits==3 || _Digits==5) ? _Point*10.0 : _Point;
   double atrPip  = g_dATR / pip;
   double stopPip = atrPip * InpATRStopMult;
   double targPip = stopPip * InpRiskReward;

   SetRow(PREFIX+"r0",0," JobPick v1.10  "+Symbol()+"  "+TFToString(),
          C'235,235,245',corner,x,y,fs,lh);
   SetRow(PREFIX+"r1",1," "+RepStr("-",29),C'70,70,85',corner,x,y,fs,lh);

   string biasSrc = (InpBiasMode==BIAS_VWAP) ? "VWAP"
                  : ((InpBiasMode==BIAS_EMA) ? ("EMA"+IntegerToString(InpEMABiasPeriod)) : "VWAP+EMA");
   SetRow(PREFIX+"r2",2," BIAS      "+Pad((g_bBiasBull ? "BULL" : "BEAR"),5)
          +"  "+DoubleToString(g_dFair,_Digits)+"  "+biasSrc,
          g_bBiasBull ? C'0,230,120' : C'255,90,90',corner,x,y,fs,lh);

   SetRow(PREFIX+"r3",3," TREND     "+Pad((g_bTrendBull ? "UP" : "DOWN"),5)
          +"  "+IntegerToString(InpEMAFast)+"/"+IntegerToString(InpEMASlow)+" EMA",
          g_bTrendBull ? C'0,230,120' : C'255,90,90',corner,x,y,fs,lh);

   string momTxt;
   if(InpMomentumMode == MOM_RSI)
      momTxt = " MOMENTUM  RSI "+Pad(DoubleToString(g_dRSI,1),5)
               +"  "+((g_bMomBull) ? "^ rising" : "v falling");
   else
      momTxt = " MOMENTUM  MACD hist "+((g_dHist>=0.0) ? "+" : "")+DoubleToString(g_dHist,_Digits+1)
               +"  "+((g_bMomBull) ? "^ rising" : "v falling");
   SetRow(PREFIX+"r4",4,momTxt,g_bMomBull ? C'0,230,120' : C'255,90,90',corner,x,y,fs,lh);

   SetRow(PREFIX+"r5",5," RISK      ATR "+Pad(DoubleToString(atrPip,1)+"pip",9)
          +"  SL "+DoubleToString(stopPip,1)+"  TP "+DoubleToString(targPip,1),
          C'120,190,255',corner,x,y,fs,lh);

   SetRow(PREFIX+"r6",6," "+RepStr("-",29),C'70,70,85',corner,x,y,fs,lh);

   int votes = (g_dirNow==1) ? g_bullVotes : ((g_dirNow==-1) ? g_bearVotes : (int)MathMax(g_bullVotes,g_bearVotes));
   string vdots = "";
   for(int k=0; k<3; k++)
      vdots += (k < votes) ? "*" : ".";
   string vState = (g_dirNow==1) ? "BUY " : ((g_dirNow==-1) ? "SELL" : "WAIT");
   SetRow(PREFIX+"r7",7," VOTES     "+vState+"  "+vdots+"  "+IntegerToString(votes)+"/3",
          (g_dirNow==1) ? C'0,230,120' : ((g_dirNow==-1) ? C'255,90,90' : C'160,160,175'),
          corner,x,y,fs,lh);

   string g1 = " GATES     ADX "+Pad(DoubleToString(g_dADX,1),5)+" "+Flag(g_gADX);
   SetRow(PREFIX+"r8",8,g1,g_gADX ? C'0,230,120' : C'255,90,90',corner,x,y,fs,lh);

   string g2 = "           VOL "+Pad(DoubleToString(g_dRVOL,2),5)+" "+Flag(g_gVol)
               +"  EXT "+Flag(g_gExt);
   SetRow(PREFIX+"r9",9,g2,(g_gVol && g_gExt) ? C'0,230,120' : C'255,90,90',corner,x,y,fs,lh);

   string g3 = "           SPR "+Flag(g_gSpr)+"  SES "+Flag(g_gSes)
               +"  HTF "+Flag(g_gHTF);
   SetRow(PREFIX+"r10",10,g3,(g_gSpr && g_gSes && g_gHTF) ? C'0,230,120' : C'255,90,90',
          corner,x,y,fs,lh);

//--- row 11: which engine is armed right now
   string modeTxt;
   color  modeClr;
   if(g_dADX >= InpADXMin)
     {
      modeTxt = " MODE      TREND   ADX "+DoubleToString(g_dADX,1);
      modeClr = C'120,190,255';
     }
   else
     {
      modeTxt = " MODE      FADE    str "+DoubleToString(g_mrStretch,2)
                +"  R:R "+DoubleToString(g_mrRR,2);
      modeClr = C'230,180,60';
     }
   SetRow(PREFIX+"r11",11,modeTxt,modeClr,corner,x,y,fs,lh);
  }

string Flag(bool ok)
  {
   return(ok ? "ok" : "NO");
  }

void SetRow(string name,int row,string text,color clr,int corner,int x,int y,int fs,int lh)
  {
   if(ObjectFind(0,name) < 0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y + row*lh);
      ObjectSetString(0,name,OBJPROP_FONT,"Courier New");
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
      ObjectSetString(0,name,OBJPROP_TEXT,text);
     }
   if(ObjectGetString(0,name,OBJPROP_TEXT) != text)
      ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
  }

void DeletePanel()
  {
   ObjectsDeleteAll(0,PREFIX,0,OBJ_LABEL);
   ObjectsDeleteAll(0,PREFIX,0,OBJ_RECTANGLE_LABEL);
  }

//+------------------------------------------------------------------+
//| Last signal stop / target lines                                   |
//+------------------------------------------------------------------+
void DrawLevels()
  {
   if(g_sigType == 0 || g_sigTime == 0)
      return;
   DrawHLine(PREFIX+"SL",g_sigStop,  C'255,90,90',  STYLE_DASHDOT,1);
   DrawHLine(PREFIX+"TP",g_sigTarget,C'0,230,120',  STYLE_DASHDOT,1);
   DrawHLine(PREFIX+"EN",g_sigPrice, C'150,150,170',STYLE_DOT,    1);
  }

void DrawHLine(string name,double price,color clr,int style,int width)
  {
   if(ObjectFind(0,name) < 0)
     {
      ObjectCreate(0,name,OBJ_HLINE,0,0,price);
      ObjectSetInteger(0,name,OBJPROP_STYLE,style);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
     }
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
  }

void DeleteLevels()
  {
   ObjectsDeleteAll(0,PREFIX,0,OBJ_HLINE);
  }

//+------------------------------------------------------------------+
//| String helpers                                                    |
//+------------------------------------------------------------------+
string Pad(string s,int width)
  {
   for(int i=StringLen(s); i<width; i++)
      s += " ";
   return(s);
  }

string RepStr(string ch,int count)
  {
   string s = "";
   for(int i=0; i<count; i++)
      s += ch;
   return(s);
  }
//+------------------------------------------------------------------+
