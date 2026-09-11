//+------------------------------------------------------------------+
//|                                           BPT_GEX_OrderFlow.mq4 |
//|       BPT 8-FIGURE APEX QUANTITATIVE TERMINAL (v8.0 OMNI FINAL) |
//|         (GEX + Tape Imbalances + MSS Engine + 8-Figure Matrix)  |
//|                                    https://www.youtube.com/@bptnq|
//+------------------------------------------------------------------+
#property copyright "BPT 8-Figure Quantitative Terminal - Omni v8.0 FINAL"
#property link      "https://www.youtube.com/@bptnq"
#property version   "8.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   7

// --- Plot 1: Tier-1 Diamond Buy Setup ---
#property indicator_label1  "Tier-1 Diamond Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

// --- Plot 2: Tier-1 Diamond Sell Setup ---
#property indicator_label2  "Tier-1 Diamond Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  3

// --- Plot 3: Institutional Call Wall (Ceiling) ---
#property indicator_label3  "Institutional Call Wall"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrCrimson
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

// --- Plot 4: Zero Gamma Flip / Regime Boundary ---
#property indicator_label4  "Zero Gamma Flip"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGold
#property indicator_style4  STYLE_DOT
#property indicator_width4  1

// --- Plot 5: Institutional Put Wall (Floor) ---
#property indicator_label5  "Institutional Put Wall"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrDodgerBlue
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

// --- Plot 6: Institutional Liquidity Sweep Marker ---
#property indicator_label6  "Institutional Liquidity Sweep"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrAqua
#property indicator_style6  STYLE_SOLID
#property indicator_width6  1

// --- Plot 7: Order Flow Tape Absorption Marker ---
#property indicator_label7  "Order Flow Tape Absorption"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrMagenta
#property indicator_style7  STYLE_SOLID
#property indicator_width7  1

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_GEX_MODE
{
   GEX_MODE_AUTO = 0,    // Auto-Calculated Institutional Volatility & GEX Model
   GEX_MODE_MANUAL = 1   // Manual Strike Inputs (from Deepcharts / CBOE)
};

enum ENUM_EXECUTION_MODE
{
   EXEC_APEX_MSS        = 0, // 8-Figure Mode: 2-Bar Market Structure Shift (MSS) Reclaim
   EXEC_DIRECT_SWEEP    = 1  // Direct Mode: Immediate Liquidity Sweep Absorption
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
// --- 1. 8-Figure Institutional Compounding & Position Sizing ---
input string             Section_Compounding     = "=== 1. 8-FIGURE COMPOUNDING ENGINE ===";
input double             InpRiskPercent          = 1.0;             // Risk Per Trade (% of Account Balance)
input double             InpCustomBalance        = 0.0;             // Custom Account Balance (0 = Use Live Balance)
input double             InpStopBufferATR        = 0.35;            // Anti-Slippage Invalidation Cushion (x ATR)

// --- 2. Institutional GEX & Volatility Model ---
input string             Section_GEX             = "=== 2. GAMMA EXPOSURE (GEX) ===";
input ENUM_GEX_MODE      InpGexMode              = GEX_MODE_AUTO;   // GEX Calculation Mode
input double             InpManualCallWall       = 0.0;             // Manual Call Wall Strike (0 = Auto)
input double             InpManualPutWall        = 0.0;             // Manual Put Wall Strike (0 = Auto)
input double             InpManualZeroGamma      = 0.0;             // Manual Zero Gamma Strike (0 = Auto)
input int                InpAutoPeriod           = 30;              // Volatility Lookback Period
input double             InpGexDevMultiplier     = 2.2;             // GEX Wall Multiplier (2.0 - 2.5)

// --- 3. Order Flow Microstructure & Confluence Scoring ---
input string             Section_OrderFlow       = "=== 3. 8-FIGURE CONFLUENCE FILTERS ===";
input ENUM_EXECUTION_MODE InpExecutionMode       = EXEC_APEX_MSS;   // Institutional Execution Mechanism
input int                InpMinConfluenceScore   = 75;              // Minimum Confluence Score (75% = Tier-1 Diamond)
input bool               InpRequireDeltaFlip     = true;            // Require Real Aggressive Delta Direction
input bool               InpRequireLiquiditySweep= true;            // Require Liquidity Sweep of Prior Extreme
input bool               InpUseTrendFilter       = true;            // Filter by Macro Trend Baseline (200 EMA)
input int                InpTrendEmaPeriod       = 200;             // Macro Trend Baseline EMA Period
input bool               InpUseSessionFilter     = false;           // Filter by High-Liquidity Hours (NY / London)
input int                InpSessionStartHour     = 8;               // Trading Start Hour (Broker Time)
input int                InpSessionEndHour       = 17;              // Trading End Hour (Broker Time)
input bool               InpRequireGexConfluence = true;            // Strict Mode: ONLY Trigger at GEX Walls
input double             InpGexToleranceATR      = 0.85;            // Max Distance to GEX Wall (x ATR)
input int                InpVolAvgPeriod         = 20;              // Volume Moving Average Period
input double             InpVolSpikeFactor       = 1.6;             // Minimum Institutional Volume Spike (1.6x SMA)
input double             InpWickAbsorptionRatio  = 0.40;            // Minimum Absorption Wick Ratio (40%)
input int                InpSignalCooldownBars   = 6;               // Min Bars Between Consecutive Signals

// --- 4. 4-Stage 8-Figure Compounding Targets (The BPT Mega-Pyramid) ---
input string             Section_Targets         = "=== 4. 8-FIGURE ASYMMETRIC TARGETS ===";
input double             InpBreakevenTrigger_R   = 0.8;             // Trigger to Move SL to Breakeven (+0.8R)
input double             InpTarget1_R            = 3.0;             // TP1: Bank 40% Position (+3R Locked)
input double             InpTarget2_R            = 7.0;             // TP2: Bank 30% Position (+7R Expansion)
input double             InpTarget3_R            = 12.0;            // TP3: Bank 20% Position (+12R Structural)
input double             InpTarget4_R            = 20.0;            // TP4: Mega-Runner 10% Position (+20R Macro)
input bool               InpShowPersistentPlan   = true;            // Keep Trade Plan Anchored on Chart

// --- 5. Visuals & Deluxe Bloomberg-Style HUD Terminal ---
input string             Section_Visuals         = "=== 5. DELUXE TERMINAL HUD ===";
input bool               InpShowDashboard        = true;            // Show On-Chart HUD Terminal
input int                InpDashboardX           = 20;              // Terminal X Position
input int                InpDashboardY           = 30;              // Terminal Y Position

// --- 6. Notifications ---
input string             Section_Alerts          = "=== 6. NOTIFICATIONS ===";
input bool               InpAlertPopup           = true;            // Pop-up Alert
input bool            InpAlertSound           = true;            // Sound Alert
input bool               InpAlertPush            = false;           // Mobile Push Notification
input string             InpSoundFile            = "alert.wav";     // Alert Sound File

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS & STRUCTURES                                   |
//+------------------------------------------------------------------+
double BufferBuySignal[];
double BufferSellSignal[];
double BufferCallWall[];
double BufferZeroGamma[];
double BufferPutWall[];
double BufferBullAbsorption[];
double BufferBearAbsorption[];

// Internal Data Buffers
double BufferEstimatedDelta[];
double BufferCVD[];

struct TradeSetup
{
   bool     valid;
   bool     isLong;
   datetime time;
   double   entry;
   double   sl;
   double   be;
   double   tp1;
   double   tp2;
   double   tp3;
   double   tp4;
   double   riskPts;
   double   lotSize;
   double   riskDollars;
   int      confluenceScore;
};

TradeSetup g_LastSetup;
string g_RegimeText   = "Positive Gamma (Long GEX)";
color  g_RegimeColor  = clrLimeGreen;
datetime g_LastAlertTime = 0;
const string PREFIX   = "BPT_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferBuySignal);
   SetIndexBuffer(1, BufferSellSignal);
   SetIndexBuffer(2, BufferCallWall);
   SetIndexBuffer(3, BufferZeroGamma);
   SetIndexBuffer(4, BufferPutWall);
   SetIndexBuffer(5, BufferBullAbsorption);
   SetIndexBuffer(6, BufferBearAbsorption);

   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 3, clrLime);
   SetIndexArrow(0, 233);
   SetIndexEmptyValue(0, 0.0);

   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 3, clrRed);
   SetIndexArrow(1, 234);
   SetIndexEmptyValue(1, 0.0);

   SetIndexStyle(2, DRAW_LINE, STYLE_SOLID, 2, clrCrimson);
   SetIndexEmptyValue(2, 0.0);

   SetIndexStyle(3, DRAW_LINE, STYLE_DOT, 1, clrGold);
   SetIndexEmptyValue(3, 0.0);

   SetIndexStyle(4, DRAW_LINE, STYLE_SOLID, 2, clrDodgerBlue);
   SetIndexEmptyValue(4, 0.0);

   SetIndexStyle(5, DRAW_ARROW, STYLE_SOLID, 1, clrAqua);
   SetIndexArrow(5, 159);
   SetIndexEmptyValue(5, 0.0);

   SetIndexStyle(6, DRAW_ARROW, STYLE_SOLID, 1, clrMagenta);
   SetIndexArrow(6, 159);
   SetIndexEmptyValue(6, 0.0);

   ArraySetAsSeries(BufferBuySignal, true);
   ArraySetAsSeries(BufferSellSignal, true);
   ArraySetAsSeries(BufferCallWall, true);
   ArraySetAsSeries(BufferZeroGamma, true);
   ArraySetAsSeries(BufferPutWall, true);
   ArraySetAsSeries(BufferBullAbsorption, true);
   ArraySetAsSeries(BufferBearAbsorption, true);

   g_LastSetup.valid = false;
   ObjectsDeleteAll(0, PREFIX);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX);
   Comment("");
}

//+------------------------------------------------------------------+
//| Calculate Optimal Lot Size Based on Account Balance & Stop Loss  |
//+------------------------------------------------------------------+
double CalculateOptimalLotSize(double slPoints)
{
   if(slPoints <= 0.0) return 0.1;

   double balance = (InpCustomBalance > 0.0) ? InpCustomBalance : AccountBalance();
   if(balance <= 0.0) balance = 10000.0;

   double riskMoney = balance * (InpRiskPercent / 100.0);
   double tickSize  = MarketInfo(_Symbol, MODE_TICKSIZE);
   double tickValue = MarketInfo(_Symbol, MODE_TICKVALUE);
   double pointVal  = MarketInfo(_Symbol, MODE_POINT);

   if(tickSize <= 0.0 || pointVal <= 0.0) return 0.1;

   double pointValueInAccountCurrency = tickValue * (pointVal / tickSize);
   if(pointValueInAccountCurrency <= 0.0) pointValueInAccountCurrency = 1.0;

   double lotSize = riskMoney / (slPoints * pointValueInAccountCurrency);

   double minLot  = MarketInfo(_Symbol, MODE_MINLOT);
   double maxLot  = MarketInfo(_Symbol, MODE_MAXLOT);
   double lotStep = MarketInfo(_Symbol, MODE_LOTSTEP);

   if(lotStep > 0.0)
      lotSize = MathFloor(lotSize / lotStep) * lotStep;

   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;

   return lotSize;
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   int minBarsNeeded = MathMax(InpAutoPeriod, InpTrendEmaPeriod) + InpVolAvgPeriod + 10;
   if(rates_total < minBarsNeeded)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);

   if(ArraySize(BufferEstimatedDelta) < rates_total)
   {
      ArrayResize(BufferEstimatedDelta, rates_total);
      ArrayResize(BufferCVD, rates_total);
      ArraySetAsSeries(BufferEstimatedDelta, true);
      ArraySetAsSeries(BufferCVD, true);
   }

   int limit = rates_total - prev_calculated;
   if(limit > rates_total - InpAutoPeriod - 5)
      limit = rates_total - InpAutoPeriod - 5;

   // 1. ESTIMATED DELTA & CVD TAPE ENGINE
   for(int i = limit; i >= 0; i--)
   {
      double range = high[i] - low[i];
      double vol = (double)tick_volume[i];
      if(vol <= 0.0) vol = 1.0;

      if(range > 0.0)
      {
         double buyerPressure  = close[i] - low[i];
         double sellerPressure = high[i] - close[i];
         BufferEstimatedDelta[i] = vol * ((buyerPressure - sellerPressure) / range);
      }
      else
      {
         BufferEstimatedDelta[i] = 0.0;
      }

      if(i == rates_total - 1)
         BufferCVD[i] = BufferEstimatedDelta[i];
      else
         BufferCVD[i] = BufferCVD[i + 1] + BufferEstimatedDelta[i];
   }

   // 2. MAIN CALCULATION & CONFLUENCE GRADING LOOP
   int lastBuyBar  = -999;
   int lastSellBar = -999;

   for(int i = limit; i >= 0; i--)
   {
      BufferBuySignal[i]        = 0.0;
      BufferSellSignal[i]       = 0.0;
      BufferBullAbsorption[i]   = 0.0;
      BufferBearAbsorption[i]   = 0.0;

      double atr = iATR(NULL, 0, 14, i);
      if(atr <= 0.0) atr = (high[i] - low[i]);
      if(atr <= 0.0) atr = 10.0 * Point;

      // Calculate GEX Levels
      double callWall = 0.0;
      double putWall = 0.0;
      double zeroGamma = 0.0;

      if(InpGexMode == GEX_MODE_MANUAL && InpManualCallWall > 0.0 && InpManualPutWall > 0.0)
      {
         callWall  = InpManualCallWall;
         putWall   = InpManualPutWall;
         zeroGamma = (InpManualZeroGamma > 0.0) ? InpManualZeroGamma : (callWall + putWall) / 2.0;
      }
      else
      {
         double sumPrice = 0.0;
         double sumVol   = 0.0;
         for(int k = 0; k < InpAutoPeriod; k++)
         {
            double v = (double)tick_volume[i + k];
            if(v <= 0) v = 1.0;
            sumPrice += close[i + k] * v;
            sumVol   += v;
         }
         double mean = (sumVol > 0) ? (sumPrice / sumVol) : close[i];

         double sumSq = 0.0;
         for(int k = 0; k < InpAutoPeriod; k++)
         {
            sumSq += MathPow(close[i + k] - mean, 2);
         }
         double stdDev = MathSqrt(sumSq / InpAutoPeriod);

         zeroGamma = mean;
         callWall  = mean + (stdDev * InpGexDevMultiplier);
         putWall   = mean - (stdDev * InpGexDevMultiplier);
      }

      BufferCallWall[i]  = callWall;
      BufferZeroGamma[i] = zeroGamma;
      BufferPutWall[i]   = putWall;

      // Trend EMA Filter
      double trendEma = iMA(NULL, 0, InpTrendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE, i);
      bool isBullTrend = (!InpUseTrendFilter || close[i] >= trendEma);
      bool isBearTrend = (!InpUseTrendFilter || close[i] <= trendEma);

      // Session Timing Filter
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      bool inSession = (!InpUseSessionFilter || (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour));

      // Volume SMA
      double volSum = 0.0;
      for(int v = 1; v <= InpVolAvgPeriod; v++)
      {
         volSum += (double)tick_volume[i + v];
      }
      double avgVol = volSum / InpVolAvgPeriod;

      double candleRange = high[i] - low[i];
      double lowerWick   = MathMin(open[i], close[i]) - low[i];
      double upperWick   = high[i] - MathMax(open[i], close[i]);
      double curVol      = (double)tick_volume[i];

      bool isHighVol = (curVol >= avgVol * InpVolSpikeFactor);

      // Sweep & Absorption Detection
      bool isBullSweep = false;
      bool isBearSweep = false;

      if(candleRange > 0.0 && isHighVol)
      {
         bool sweptLow = (!InpRequireLiquiditySweep || (i + 1 < rates_total && low[i] <= low[i + 1]));
         if(sweptLow && (lowerWick / candleRange) >= InpWickAbsorptionRatio)
         {
            isBullSweep = true;
            BufferBullAbsorption[i] = low[i] - (atr * 0.2);
         }

         bool sweptHigh = (!InpRequireLiquiditySweep || (i + 1 < rates_total && high[i] >= high[i + 1]));
         if(sweptHigh && (upperWick / candleRange) >= InpWickAbsorptionRatio)
         {
            isBearSweep = true;
            BufferBearAbsorption[i] = high[i] + (atr * 0.2);
         }
      }

      // GEX Proximity
      double gexTol = atr * InpGexToleranceATR;
      bool nearPutWall  = (!InpRequireGexConfluence || (low[i] <= putWall + gexTol && low[i] >= putWall - (gexTol * 1.5)));
      bool nearCallWall = (!InpRequireGexConfluence || (high[i] >= callWall - gexTol && high[i] <= callWall + (gexTol * 1.5)));

      // Delta Momentum Flip
      bool deltaBullish = (!InpRequireDeltaFlip || BufferEstimatedDelta[i] > 0);
      bool deltaBearish = (!InpRequireDeltaFlip || BufferEstimatedDelta[i] < 0);

      // --- 8-FIGURE CONFLUENCE SCORING ENGINE (0 TO 100%) ---
      int buyScore = 0;
      if(nearPutWall)            buyScore += 25;
      if(isBullSweep)            buyScore += 25;
      if(deltaBullish)           buyScore += 20;
      if(isBullTrend)            buyScore += 15;
      if(inSession)              buyScore += 15;

      int sellScore = 0;
      if(nearCallWall)           sellScore += 25;
      if(isBearSweep)            sellScore += 25;
      if(deltaBearish)           sellScore += 20;
      if(isBearTrend)            sellScore += 15;
      if(inSession)              sellScore += 15;

      // --- APEX TIER-1 DIAMOND BUY TRIGGER ---
      bool buyCondition = false;
      double buySweepLow = low[i];

      if(InpExecutionMode == EXEC_APEX_MSS)
      {
         if(i + 1 < rates_total)
         {
            bool prevWasSweep = (BufferBullAbsorption[i + 1] > 0.0 || (MathMin(open[i + 1], close[i + 1]) - low[i + 1]) / (high[i + 1] - low[i + 1]) >= 0.35);
            bool mssReclaim   = (close[i] > high[i + 1] && close[i] > open[i]);
            if(prevWasSweep && mssReclaim && nearPutWall && deltaBullish && buyScore >= InpMinConfluenceScore)
            {
               buyCondition = true;
               buySweepLow  = MathMin(low[i], low[i + 1]);
            }
         }
      }
      else
      {
         if(nearPutWall && isBullSweep && close[i] > open[i] && deltaBullish && buyScore >= InpMinConfluenceScore)
         {
            buyCondition = true;
            buySweepLow  = low[i];
         }
      }

      if(inSession && isBullTrend && buyCondition)
      {
         bool cooldownOk = (lastBuyBar - i >= InpSignalCooldownBars || lastBuyBar == -999);
         if(cooldownOk)
         {
            BufferBuySignal[i] = low[i] - (atr * 0.6);
            lastBuyBar = i;

            if(i == 0 || !g_LastSetup.valid || time[i] >= g_LastSetup.time)
            {
               g_LastSetup.valid           = true;
               g_LastSetup.isLong          = true;
               g_LastSetup.time            = time[i];
               g_LastSetup.entry           = close[i];
               g_LastSetup.sl              = buySweepLow - (atr * InpStopBufferATR);
               g_LastSetup.riskPts         = MathAbs(g_LastSetup.entry - g_LastSetup.sl);
               g_LastSetup.be              = g_LastSetup.entry + (g_LastSetup.riskPts * InpBreakevenTrigger_R);
               g_LastSetup.tp1             = g_LastSetup.entry + (g_LastSetup.riskPts * InpTarget1_R);
               g_LastSetup.tp2             = g_LastSetup.entry + (g_LastSetup.riskPts * InpTarget2_R);
               g_LastSetup.tp3             = g_LastSetup.entry + (g_LastSetup.riskPts * InpTarget3_R);
               g_LastSetup.tp4             = g_LastSetup.entry + (g_LastSetup.riskPts * InpTarget4_R);
               g_LastSetup.confluenceScore = buyScore;

               double pts = g_LastSetup.riskPts / Point;
               g_LastSetup.lotSize         = CalculateOptimalLotSize(pts);
               double bal = (InpCustomBalance > 0.0) ? InpCustomBalance : AccountBalance();
               g_LastSetup.riskDollars     = bal * (InpRiskPercent / 100.0);
            }

            if(i == 0 && time[0] != g_LastAlertTime)
            {
               Trigger8FigureAlert(true, close[0], g_LastSetup.sl, g_LastSetup.tp1, g_LastSetup.tp2, g_LastSetup.tp3, g_LastSetup.tp4, g_LastSetup.lotSize, buyScore);
               g_LastAlertTime = time[0];
            }
         }
      }

      // --- APEX TIER-1 DIAMOND SELL TRIGGER ---
      bool sellCondition = false;
      double sellSweepHigh = high[i];

      if(InpExecutionMode == EXEC_APEX_MSS)
      {
         if(i + 1 < rates_total)
         {
            bool prevWasSweep = (BufferBearAbsorption[i + 1] > 0.0 || (high[i + 1] - MathMax(open[i + 1], close[i + 1])) / (high[i + 1] - low[i + 1]) >= 0.35);
            bool mssRejection = (close[i] < low[i + 1] && close[i] < open[i]);
            if(prevWasSweep && mssRejection && nearCallWall && deltaBearish && sellScore >= InpMinConfluenceScore)
            {
               sellCondition = true;
               sellSweepHigh = MathMax(high[i], high[i + 1]);
            }
         }
      }
      else
      {
         if(nearCallWall && isBearSweep && close[i] < open[i] && deltaBearish && sellScore >= InpMinConfluenceScore)
         {
            sellCondition = true;
            sellSweepHigh = high[i];
         }
      }

      if(inSession && isBearTrend && sellCondition)
      {
         bool cooldownOk = (lastSellBar - i >= InpSignalCooldownBars || lastSellBar == -999);
         if(cooldownOk)
         {
            BufferSellSignal[i] = high[i] + (atr * 0.6);
            lastSellBar = i;

            if(i == 0 || !g_LastSetup.valid || time[i] >= g_LastSetup.time)
            {
               g_LastSetup.valid           = true;
               g_LastSetup.isLong          = false;
               g_LastSetup.time            = time[i];
               g_LastSetup.entry           = close[i];
               g_LastSetup.sl              = sellSweepHigh + (atr * InpStopBufferATR);
               g_LastSetup.riskPts         = MathAbs(g_LastSetup.entry - g_LastSetup.sl);
               g_LastSetup.be              = g_LastSetup.entry - (g_LastSetup.riskPts * InpBreakevenTrigger_R);
               g_LastSetup.tp1             = g_LastSetup.entry - (g_LastSetup.riskPts * InpTarget1_R);
               g_LastSetup.tp2             = g_LastSetup.entry - (g_LastSetup.riskPts * InpTarget2_R);
               g_LastSetup.tp3             = g_LastSetup.entry - (g_LastSetup.riskPts * InpTarget3_R);
               g_LastSetup.tp4             = g_LastSetup.entry - (g_LastSetup.riskPts * InpTarget4_R);
               g_LastSetup.confluenceScore = sellScore;

               double pts = g_LastSetup.riskPts / Point;
               g_LastSetup.lotSize         = CalculateOptimalLotSize(pts);
               double bal = (InpCustomBalance > 0.0) ? InpCustomBalance : AccountBalance();
               g_LastSetup.riskDollars     = bal * (InpRiskPercent / 100.0);
            }

            if(i == 0 && time[0] != g_LastAlertTime)
            {
               Trigger8FigureAlert(false, close[0], g_LastSetup.sl, g_LastSetup.tp1, g_LastSetup.tp2, g_LastSetup.tp3, g_LastSetup.tp4, g_LastSetup.lotSize, sellScore);
               g_LastAlertTime = time[0];
            }
         }
      }
   }

   // 3. PERSISTENT 4-STAGE TARGET PLAN
   if(InpShowPersistentPlan && g_LastSetup.valid)
   {
      Draw8FigureTradePlan(g_LastSetup);
   }

   // 4. MARKET REGIME & HUD UPDATE
   if(close[0] >= BufferZeroGamma[0])
   {
      g_RegimeText  = "+ LONG GAMMA (Mean-Reverting / Fade Extremes)";
      g_RegimeColor = clrLimeGreen;
   }
   else
   {
      g_RegimeText  = "- SHORT GAMMA (Expansion / Squeeze Risk)";
      g_RegimeColor = clrOrangeRed;
   }

   if(InpShowDashboard)
      RenderDashboard(close[0]);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Draw 8-Figure Master Trade Plan (Entry, SL, BE, TP1, TP2, TP3, 4)|
//+------------------------------------------------------------------+
void Draw8FigureTradePlan(const TradeSetup &setup)
{
   if(!setup.valid || setup.riskPts <= 0.0) return;

   datetime startTime = setup.time;
   datetime endTime   = TimeCurrent() + PeriodSeconds() * 50;

   // 1. Entry Line (Gold)
   DrawRayLine(PREFIX + "Plan_Entry", startTime, setup.entry, endTime, setup.entry, clrGold, STYLE_DOT, 1, "💎 Tier-1 Entry");

   // 2. Stop Loss Line (Red)
   DrawRayLine(PREFIX + "Plan_SL", startTime, setup.sl, endTime, setup.sl, clrCrimson, STYLE_SOLID, 2, "1R Invalidation SL");

   // 3. Breakeven Trigger (White Dash - Zero-Risk Point)
   DrawRayLine(PREFIX + "Plan_BE", startTime, setup.be, endTime, setup.be, clrWhite, STYLE_DOT, 1, StringFormat("Risk-Free BE (+%.1fR -> Lock SL to Entry)", InpBreakevenTrigger_R));

   // 4. TP1 (+3R Target - 40% Banked)
   DrawRayLine(PREFIX + "Plan_TP1", startTime, setup.tp1, endTime, setup.tp1, clrMediumSeaGreen, STYLE_DASH, 2, StringFormat("TP1 (+%.0fR - Bank 40%%)", InpTarget1_R));

   // 5. TP2 (+7R Target - 30% Expansion)
   DrawRayLine(PREFIX + "Plan_TP2", startTime, setup.tp2, endTime, setup.tp2, clrDeepSkyBlue, STYLE_SOLID, 2, StringFormat("TP2 (+%.0fR - Bank 30%%)", InpTarget2_R));

   // 6. TP3 (+12R Target - 20% Structural)
   DrawRayLine(PREFIX + "Plan_TP3", startTime, setup.tp3, endTime, setup.tp3, clrMagenta, STYLE_SOLID, 2, StringFormat("TP3 (+%.0fR - Bank 20%%)", InpTarget3_R));

   // 7. TP4 (+20R Target - 10% Macro Mega-Runner)
   DrawRayLine(PREFIX + "Plan_TP4", startTime, setup.tp4, endTime, setup.tp4, clrAqua, STYLE_SOLID, 2, StringFormat("TP4 (+%.0fR - 8-Figure Runner 10%%)", InpTarget4_R));
}

//+------------------------------------------------------------------+
//| Helper to Draw/Update Trend Line Ray                             |
//+------------------------------------------------------------------+
void DrawRayLine(string name, datetime t1, double p1, datetime t2, double p2, color col, int style, int width, string text)
{
   if(p1 <= 0.0) return;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME1, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE1, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME2, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE2, p2);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
}

//+------------------------------------------------------------------+
//| Deluxe Bloomberg-Style HUD Terminal Rendering                    |
//+------------------------------------------------------------------+
void RenderDashboard(double currentPrice)
{
   int x = InpDashboardX;
   int y = InpDashboardY;
   int width = 350;
   int height = 285;

   // Background Box
   string bgName = PREFIX + "HUD_BG";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'6,10,16');
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'24,38,56');
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
   }

   // Header
   CreateLabel(PREFIX + "HUD_Title", "BPT 8-FIGURE QUANTITATIVE TERMINAL", x + 15, y + 10, clrGold, 10, true);
   CreateLabel(PREFIX + "HUD_Sep1", "---------------------------------------------------------------", x + 15, y + 25, clrDimGray, 7, false);

   // GEX Levels
   CreateLabel(PREFIX + "HUD_Call", StringFormat("Call Wall (Ceiling): %.2f", BufferCallWall[0]), x + 15, y + 38, clrCrimson, 8, true);
   CreateLabel(PREFIX + "HUD_Zero", StringFormat("Zero Gamma Flip:   %.2f", BufferZeroGamma[0]), x + 15, y + 54, clrGold, 8, true);
   CreateLabel(PREFIX + "HUD_Put",  StringFormat("Put Wall (Floor):   %.2f", BufferPutWall[0]), x + 15, y + 70, clrDodgerBlue, 8, true);

   // Market Regime
   CreateLabel(PREFIX + "HUD_RegimeVal", g_RegimeText, x + 15, y + 90, g_RegimeColor, 8, true);

   // Order Flow Status
   double curDelta = BufferEstimatedDelta[0];
   string deltaStr = StringFormat("Tape Delta: %+.0f | CVD: %+.0f", curDelta, BufferCVD[0]);
   color deltaCol = (curDelta >= 0) ? clrLime : clrRed;
   CreateLabel(PREFIX + "HUD_Delta", deltaStr, x + 15, y + 110, deltaCol, 8, true);

   CreateLabel(PREFIX + "HUD_Sep2", "---------------------------------------------------------------", x + 15, y + 126, clrDimGray, 7, false);

   // Active Setup & Compounding Engine
   if(g_LastSetup.valid)
   {
      double curR = 0.0;
      if(g_LastSetup.riskPts > 0)
      {
         curR = g_LastSetup.isLong ? (currentPrice - g_LastSetup.entry) / g_LastSetup.riskPts
                                   : (g_LastSetup.entry - currentPrice) / g_LastSetup.riskPts;
      }

      double estProfitDollars = curR * g_LastSetup.riskDollars;

      string setupStr = StringFormat("Setup: %s @ %.2f | Size: %.2f Lots [%d%% DIAMOND]",
                                     g_LastSetup.isLong ? "OMNI BUY" : "OMNI SELL", g_LastSetup.entry, g_LastSetup.lotSize, g_LastSetup.confluenceScore);
      color setupCol = g_LastSetup.isLong ? clrLime : clrRed;
      CreateLabel(PREFIX + "HUD_Setup", setupStr, x + 15, y + 138, setupCol, 8, true);

      string beStatus = (curR >= InpBreakevenTrigger_R) ? "[PROTECTED: ZERO-RISK] SL at Breakeven"
                                                        : StringFormat("Move to BE at +%.1fR (+%.2f)", InpBreakevenTrigger_R, g_LastSetup.be);
      color beCol = (curR >= InpBreakevenTrigger_R) ? clrLime : clrWhite;
      CreateLabel(PREFIX + "HUD_BeStatus", beStatus, x + 15, y + 156, beCol, 8, true);

      string rStr = StringFormat("P&L: %+.2f R ($%+.2f) | Risk: $%.2f (%.1f pts)",
                                 curR, estProfitDollars, g_LastSetup.riskDollars, g_LastSetup.riskPts);
      color rCol = (curR >= 0) ? clrLimeGreen : clrOrangeRed;
      CreateLabel(PREFIX + "HUD_Pnl", rStr, x + 15, y + 174, rCol, 8, true);

      string tp1Str = StringFormat("TP1 (+%.0fR - 40%%): %.2f (+$%.0f)", InpTarget1_R, g_LastSetup.tp1, g_LastSetup.riskDollars * InpTarget1_R);
      CreateLabel(PREFIX + "HUD_TP1", tp1Str, x + 15, y + 194, clrMediumSeaGreen, 7, true);

      string tp2Str = StringFormat("TP2 (+%.0fR - 30%%): %.2f (+$%.0f)", InpTarget2_R, g_LastSetup.tp2, g_LastSetup.riskDollars * InpTarget2_R);
      CreateLabel(PREFIX + "HUD_TP2", tp2Str, x + 15, y + 210, clrDeepSkyBlue, 7, true);

      string tp3Str = StringFormat("TP3 (+%.0fR - 20%%): %.2f (+$%.0f)", InpTarget3_R, g_LastSetup.tp3, g_LastSetup.riskDollars * InpTarget3_R);
      CreateLabel(PREFIX + "HUD_TP3", tp3Str, x + 15, y + 226, clrMagenta, 7, true);

      string tp4Str = StringFormat("TP4 (+%.0fR - 10%% Mega-Runner): %.2f (+$%.0f)", InpTarget4_R, g_LastSetup.tp4, g_LastSetup.riskDollars * InpTarget4_R);
      CreateLabel(PREFIX + "HUD_TP4", tp4Str, x + 15, y + 242, clrAqua, 7, true);

      CreateLabel(PREFIX + "HUD_Rule", "8-Figure Play: Bank TP1/TP2 -> Let TP4 Runner Ride!", x + 15, y + 262, clrSilver, 7, false);
   }
   else
   {
      double bal = (InpCustomBalance > 0.0) ? InpCustomBalance : AccountBalance();
      double riskMoney = bal * (InpRiskPercent / 100.0);
      string idleStr = StringFormat("Account: $%.0f | Risk Per Trade: $%.0f (%.1f%%)", bal, riskMoney, InpRiskPercent);
      CreateLabel(PREFIX + "HUD_Setup", idleStr, x + 15, y + 138, clrGold, 8, true);
      CreateLabel(PREFIX + "HUD_BeStatus", "Status: Scanning for Tier-1 Institutional Confluence...", x + 15, y + 158, clrSilver, 8, false);
      CreateLabel(PREFIX + "HUD_Pnl", "8-Figure Asymmetric Target Projections:", x + 15, y + 178, clrWhite, 7, false);
      CreateLabel(PREFIX + "HUD_TP1", StringFormat("TP 1 (+%.0fR - 40%% Banked):     +$%.0f", InpTarget1_R, riskMoney * InpTarget1_R), x + 15, y + 196, clrMediumSeaGreen, 7, false);
      CreateLabel(PREFIX + "HUD_TP2", StringFormat("TP 2 (+%.0fR - 30%% Expansion):  +$%.0f", InpTarget2_R, riskMoney * InpTarget2_R), x + 15, y + 212, clrDeepSkyBlue, 7, false);
      CreateLabel(PREFIX + "HUD_TP3", StringFormat("TP 3 (+%.0fR - 20%% Structural): +$%.0f", InpTarget3_R, riskMoney * InpTarget3_R), x + 15, y + 228, clrMagenta, 7, false);
      CreateLabel(PREFIX + "HUD_TP4", StringFormat("TP 4 (+%.0fR - 10%% Mega-Runner): +$%.0f", InpTarget4_R, riskMoney * InpTarget4_R), x + 15, y + 244, clrAqua, 7, false);
      CreateLabel(PREFIX + "HUD_Rule", "Rule: Zero-Risk Protection Triggered at +0.8R", x + 15, y + 264, clrAqua, 7, false);
   }
}

//+------------------------------------------------------------------+
//| Helper to Create or Update a Dashboard Label                     |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color col, int fontSize, bool bold)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   else
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   }
}

//+------------------------------------------------------------------+
//| Trigger 8-Figure Master Alert with Complete Trade Ticket Details |
//+------------------------------------------------------------------+
void Trigger8FigureAlert(bool isLong, double entry, double sl, double tp1, double tp2, double tp3, double tp4, double lotSize, int score)
{
   string fullMsg = StringFormat("[BPT 8-FIGURE %s (%d%% DIAMOND)] %s | Lot: %.2f | Entry: %.2f | SL: %.2f | TP1 (+3R): %.2f | TP2 (+7R): %.2f | TP3 (+12R): %.2f | TP4 (+20R): %.2f",
                                 isLong ? "BUY" : "SELL", score, _Symbol, lotSize, entry, sl, tp1, tp2, tp3, tp4);

   if(InpAlertPopup)
      Alert(fullMsg);

   if(InpAlertSound)
      PlaySound(InpSoundFile);

   if(InpAlertPush)
      SendNotification(fullMsg);
}
//+------------------------------------------------------------------+
