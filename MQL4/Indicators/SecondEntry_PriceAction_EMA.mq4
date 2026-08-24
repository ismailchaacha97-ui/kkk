//+------------------------------------------------------------------+
//|                                  SecondEntry_PriceAction_EMA.mq4 |
//|                                  Copyright 2026, Arena AI Trader |
//|                                      https://arena.ai/trading    |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Arena AI Trader"
#property link        "https://arena.ai/trading"
#property version     "3.00"
#property description "Institutional Price Action Strategy: 2L & 2S Failure Patterns"
#property description "Combines Static S/R Mapping, Candle Rejection/Absorption, Market Structure (HH/HL/LH/LL), and 13/50 EMA Dynamic Confluence."
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   7

// Plot 1: Buy Arrow (2L Signal)
#property indicator_label1  "2L Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 2: Sell Arrow (2S Signal)
#property indicator_label2  "2S Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 3: Fast EMA Line (13 EMA)
#property indicator_label3  "Fast EMA (13)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

// Plot 4: Slow EMA Line (50 EMA)
#property indicator_label4  "Slow EMA (50)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrange
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

// Plot 5: Bullish EMA Accent
#property indicator_label5  "Bullish EMA Accent"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrLimeGreen
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

// Plot 6: Bearish EMA Accent
#property indicator_label6  "Bearish EMA Accent"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrCrimson
#property indicator_style6  STYLE_SOLID
#property indicator_width6  2

// Plot 7: 1st Entry Failed Marker
#property indicator_label7  "1st Entry Failed Marker"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrSlateGray
#property indicator_style7  STYLE_DOT
#property indicator_width7  1

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

// --- 1. Dynamic EMA Confluence Settings (13 / 50 EMA) ---
input string               Section_EMA             = "=== 1. DUAL EMA DYNAMIC CONFLUENCE ==="; // --- EMA Settings ---
input int                  InpFastEMAPeriod        = 13;              // Fast EMA Period (Dynamic Trigger, default: 13)
input int                  InpSlowEMAPeriod        = 50;              // Slow EMA Period (Macro Trend / Baseline, default: 50)
input ENUM_MA_METHOD       InpEMAMethod            = MODE_EMA;        // MA Method
input ENUM_APPLIED_PRICE   InpEMAAppliedPrice      = PRICE_CLOSE;     // Applied Price
input bool                 InpRequireEMATouch      = true;            // Trade ONLY if Price Touches/Tests 13 or 50 EMA
input double               InpEMATouchBufferPips   = 4.0;             // Max Distance from EMA to Count as Touch (Pips)
input bool                 InpEnableEMATrendColor  = true;            // Color Fast EMA by Alignment

// --- 2. Static Support & Resistance Mapping ---
input string               Section_SR              = "=== 2. STATIC S/R MAPPING ==="; // --- S/R Mapping ---
input bool                 InpEnableStaticSR       = true;            // Enable Static Horizontal S/R Detection
input int                  InpSRBarsBack           = 350;             // Historical Bars to Scan for Reversals
input int                  InpSRSwingStrength      = 5;               // Swing Fractal Strength (Left/Right bars)
input int                  InpSRMinTouches         = 2;               // Min Reversal Touches to Confirm Level
input double               InpSRZoneTolerancePips  = 6.0;             // S/R Zone Width Tolerance (Pips)
input int                  InpSRMaxLines           = 6;               // Max S/R Lines on Chart
input color                InpColorSupport         = clrDeepSkyBlue;  // Support Line Color
input color                InpColorResistance      = clrOrangeRed;    // Resistance Line Color
input ENUM_LINE_STYLE      InpSRLineStyle          = STYLE_DASH;      // S/R Line Style

// --- 3. Market Structure Alignment (HH/HL vs LH/LL) ---
input string               Section_Structure       = "=== 3. MARKET STRUCTURE ALIGNMENT ==="; // --- Market Structure ---
input bool                 InpRequireStructure     = true;            // Filter by Structure (HH/HL for Long, LH/LL for Short)
input int                  InpStructureLookback    = 30;              // Structure Lookback Bars
input bool                 InpFilterRangeChop      = true;            // Suppress Signals in Flat / Choppy Consolidation
input double               InpMinEMASeparationPips = 1.0;             // Min Separation Between 13 & 50 EMA (Pips)

// --- 4. Second Entry Failure Rules (2L & 2S) ---
input string               Section_Strategy        = "=== 4. SECOND ENTRY PATTERN (2L / 2S) ==="; // --- 2L / 2S Rules ---
input bool                 InpEnable2L             = true;            // Enable Second Entry Long (2L)
input bool                 InpEnable2S             = true;            // Enable Second Entry Short (2S)
input int                  InpMaxPullbackBars      = 25;              // Max Pullback Duration (Bars)
input int                  InpMinPullbackBars      = 2;               // Min Pullback Duration (Bars)
input bool                 InpRequireSRConfluence  = false;           // Require Setup to Touch BOTH S/R Zone & EMA (False = EMA OR S/R)

// --- 5. Candlestick Rejection & Absorption Filter ---
input string               Section_Candle          = "=== 5. CANDLE REJECTION & ABSORPTION ==="; // --- Candle Confirmation ---
input bool                 InpRequireAbsorption    = true;            // Require Clear Rejection Wick & Strong Close
input double               InpMinWickPercent       = 35.0;            // Min Rejection Wick % of Total Candle (e.g. 35%)
input double               InpMaxOppositeWickPct   = 35.0;            // Max Opposing Wick %
input bool                 InpRequireStrongClose   = true;            // 2L: Close in upper 50% | 2S: Close in lower 50%

// --- 6. Risk Management & Targets (SL / TP) ---
input string               Section_Risk            = "=== 6. RISK MANAGEMENT & TARGETS ==="; // --- SL / TP ---
input bool                 InpShowSLTP             = true;            // Draw SL & TP Target Lines on Chart
input double               InpRiskRewardRatio      = 2.0;             // Take Profit Risk:Reward Ratio (e.g. 1:2.0)
input double               InpSLBufferPips         = 2.0;             // Stop Loss Buffer beyond Signal Wick (Pips)

// --- 7. Visuals & On-Chart Dashboard ---
input string               Section_Visuals         = "=== 7. VISUALS & HUD DASHBOARD ==="; // --- Visuals ---
input int                  InpBuyArrowCode         = 233;             // Buy Arrow Wingdings Code (233=Arrow Up)
input int                  InpSellArrowCode        = 234;             // Sell Arrow Wingdings Code (234=Arrow Down)
input int                  InpArrowSize            = 2;               // Signal Arrow Size
input bool                 InpShowPatternLabels    = true;            // Show "2L" / "2S" Text Labels
input bool                 InpShow1stEntryMarkers  = false;           // Show "1L" / "1S" educational markers
input bool                 InpShowDashboard        = true;            // Show On-Chart HUD Dashboard
input ENUM_BASE_CORNER     InpDashboardCorner      = CORNER_RIGHT_UPPER; // Dashboard Corner
input color                InpDashboardBgColor     = C'16,20,30';     // Dashboard Background Color
input color                InpDashboardTextColor   = clrWhite;        // Dashboard Text Color

// --- 8. Multi-Alert Engine ---
input string               Section_Alerts          = "=== 8. ALERTS & NOTIFICATIONS ==="; // --- Alerts ---
input bool                 InpAlertOnBarClose      = true;            // Alert Only on Bar Close (Confirmed Candle)
input bool                 InpPopupAlert           = true;            // Enable MT4 Pop-up Alert Window
input bool                 InpSoundAlert           = true;            // Enable Sound Alert
input string               InpSoundFile            = "alert.wav";     // Sound File Name
input bool                 InpPushNotification    = false;           // Enable Mobile Push Notification
input bool                 InpEmailAlert           = false;           // Enable Email Notification

//+------------------------------------------------------------------+
//| INDICATOR BUFFERS & GLOBALS                                      |
//+------------------------------------------------------------------+
double BufferBuyArrow[];
double BufferSellArrow[];
double BufferFastEMA[];
double BufferSlowEMA[];
double BufferEMABull[];
double BufferEMABear[];
double BufferFirstEntry[];

string   Prefix = "2E_PRO_";
double   PipMultiplier = 0.0001;
int      PipDigits = 4;
datetime LastAlertTime = 0;
int      TotalBuySignals = 0;
int      TotalSellSignals = 0;

// Structure to store horizontal S/R levels
struct SRLevel
{
   double   price;
   int      touches;
   bool     isSupport;
   datetime lastTime;
};
SRLevel SR_Levels[];
int     SR_Count = 0;

// Structure for market structure swings
struct SwingPoint
{
   double   price;
   int      bar;
   bool     isHigh;
};

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   if(Digits == 3 || Digits == 5)
   {
      PipMultiplier = Point * 10.0;
      PipDigits = Digits - 1;
   }
   else
   {
      PipMultiplier = Point;
      PipDigits = Digits;
   }

   IndicatorBuffers(7);

   // Buffer 0: Buy Signal (2L)
   SetIndexBuffer(0, BufferBuyArrow);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, InpArrowSize, clrLime);
   SetIndexArrow(0, InpBuyArrowCode);
   SetIndexEmptyValue(0, 0.0);
   ArraySetAsSeries(BufferBuyArrow, true);

   // Buffer 1: Sell Signal (2S)
   SetIndexBuffer(1, BufferSellArrow);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, InpArrowSize, clrRed);
   SetIndexArrow(1, InpSellArrowCode);
   SetIndexEmptyValue(1, 0.0);
   ArraySetAsSeries(BufferSellArrow, true);

   // Buffer 2: Fast EMA (13)
   SetIndexBuffer(2, BufferFastEMA);
   SetIndexStyle(2, DRAW_LINE, STYLE_SOLID, 2, clrDodgerBlue);
   SetIndexEmptyValue(2, 0.0);
   ArraySetAsSeries(BufferFastEMA, true);

   // Buffer 3: Slow EMA (50)
   SetIndexBuffer(3, BufferSlowEMA);
   SetIndexStyle(3, DRAW_LINE, STYLE_SOLID, 2, clrOrange);
   SetIndexEmptyValue(3, 0.0);
   ArraySetAsSeries(BufferSlowEMA, true);

   // Buffer 4: EMA Bullish Accent
   SetIndexBuffer(4, BufferEMABull);
   SetIndexStyle(4, DRAW_LINE, STYLE_SOLID, 2, clrLimeGreen);
   SetIndexEmptyValue(4, 0.0);
   ArraySetAsSeries(BufferEMABull, true);

   // Buffer 5: EMA Bearish Accent
   SetIndexBuffer(5, BufferEMABear);
   SetIndexStyle(5, DRAW_LINE, STYLE_SOLID, 2, clrCrimson);
   SetIndexEmptyValue(5, 0.0);
   ArraySetAsSeries(BufferEMABear, true);

   // Buffer 6: 1st Entry Marker
   SetIndexBuffer(6, BufferFirstEntry);
   SetIndexStyle(6, DRAW_ARROW, STYLE_DOT, 1, clrSlateGray);
   SetIndexArrow(6, 159);
   SetIndexEmptyValue(6, 0.0);
   ArraySetAsSeries(BufferFirstEntry, true);

   ObjectsDeleteAll(0, Prefix);

   IndicatorShortName(StringFormat("2L/2S Price Action Pro (%d/%d EMA + Static S/R)", InpFastEMAPeriod, InpSlowEMAPeriod));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, Prefix);
   Comment("");
}

//+------------------------------------------------------------------+
//| Static Support and Resistance Mapping Function                   |
//+------------------------------------------------------------------+
void UpdateStaticSR(int rates_total, const double &high[], const double &low[], const datetime &time[])
{
   if(!InpEnableStaticSR) return;

   ArrayResize(SR_Levels, 0);
   SR_Count = 0;

   int scanLimit = MathMin(InpSRBarsBack, rates_total - InpSRSwingStrength - 2);
   if(scanLimit < InpSRSwingStrength * 2) return;

   double swingHighs[];
   datetime swingHighTimes[];
   double swingLows[];
   datetime swingLowTimes[];
   int countHighs = 0;
   int countLows = 0;

   ArrayResize(swingHighs, scanLimit);
   ArrayResize(swingHighTimes, scanLimit);
   ArrayResize(swingLows, scanLimit);
   ArrayResize(swingLowTimes, scanLimit);

   int i_idx, k_idx, h1, h2, l1, l2;
   bool isHigh, isLow;

   for(i_idx = InpSRSwingStrength + 1; i_idx < scanLimit; i_idx++)
   {
      isHigh = true;
      isLow = true;

      for(k_idx = 1; k_idx <= InpSRSwingStrength; k_idx++)
      {
         if(high[i_idx] <= high[i_idx - k_idx] || high[i_idx] < high[i_idx + k_idx])
            isHigh = false;
         if(low[i_idx] >= low[i_idx - k_idx] || low[i_idx] > low[i_idx + k_idx])
            isLow = false;
      }

      if(isHigh)
      {
         swingHighs[countHighs] = high[i_idx];
         swingHighTimes[countHighs] = time[i_idx];
         countHighs++;
      }
      if(isLow)
      {
         swingLows[countLows] = low[i_idx];
         swingLowTimes[countLows] = time[i_idx];
         countLows++;
      }
   }

   double zonePips = InpSRZoneTolerancePips * PipMultiplier;
   bool usedHigh[];
   ArrayResize(usedHigh, countHighs);
   ArrayInitialize(usedHigh, false);

   double sumPrice;
   int touches;
   datetime lastT;

   for(h1 = 0; h1 < countHighs; h1++)
   {
      if(usedHigh[h1]) continue;

      sumPrice = swingHighs[h1];
      touches = 1;
      lastT = swingHighTimes[h1];

      for(h2 = h1 + 1; h2 < countHighs; h2++)
      {
         if(!usedHigh[h2] && MathAbs(swingHighs[h1] - swingHighs[h2]) <= zonePips)
         {
            sumPrice += swingHighs[h2];
            touches++;
            usedHigh[h2] = true;
            if(swingHighTimes[h2] > lastT) lastT = swingHighTimes[h2];
         }
      }

      if(touches >= InpSRMinTouches && SR_Count < InpSRMaxLines * 2)
      {
         ArrayResize(SR_Levels, SR_Count + 1);
         SR_Levels[SR_Count].price = sumPrice / (double)touches;
         SR_Levels[SR_Count].touches = touches;
         SR_Levels[SR_Count].isSupport = false;
         SR_Levels[SR_Count].lastTime = lastT;
         SR_Count++;
      }
   }

   bool usedLow[];
   ArrayResize(usedLow, countLows);
   ArrayInitialize(usedLow, false);

   for(l1 = 0; l1 < countLows; l1++)
   {
      if(usedLow[l1]) continue;

      sumPrice = swingLows[l1];
      touches = 1;
      lastT = swingLowTimes[l1];

      for(l2 = l1 + 1; l2 < countLows; l2++)
      {
         if(!usedLow[l2] && MathAbs(swingLows[l1] - swingLows[l2]) <= zonePips)
         {
            sumPrice += swingLows[l2];
            touches++;
            usedLow[l2] = true;
            if(swingLowTimes[l2] > lastT) lastT = swingLowTimes[l2];
         }
      }

      if(touches >= InpSRMinTouches && SR_Count < InpSRMaxLines * 4)
      {
         ArrayResize(SR_Levels, SR_Count + 1);
         SR_Levels[SR_Count].price = sumPrice / (double)touches;
         SR_Levels[SR_Count].touches = touches;
         SR_Levels[SR_Count].isSupport = true;
         SR_Levels[SR_Count].lastTime = lastT;
         SR_Count++;
      }
   }

   DrawStaticSRLevels();
}

//+------------------------------------------------------------------+
//| Draw Static S/R Levels on Chart                                  |
//+------------------------------------------------------------------+
void DrawStaticSRLevels()
{
   int objIdx;
   for(objIdx = ObjectsTotal(0, 0, OBJ_HLINE) - 1; objIdx >= 0; objIdx--)
   {
      string objName = ObjectName(0, objIdx, 0, OBJ_HLINE);
      if(StringFind(objName, Prefix + "SR_") == 0)
         ObjectDelete(0, objName);
   }

   int drawnCount = 0;
   for(int s = 0; s < SR_Count && drawnCount < InpSRMaxLines; s++)
   {
      string name = Prefix + "SR_" + IntegerToString(s) + "_" + (SR_Levels[s].isSupport ? "Sup" : "Res");
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, SR_Levels[s].price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, SR_Levels[s].isSupport ? InpColorSupport : InpColorResistance);
      ObjectSetInteger(0, name, OBJPROP_STYLE, InpSRLineStyle);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      
      string text = (SR_Levels[s].isSupport ? "Static Support (" : "Static Resistance (") + 
                    IntegerToString(SR_Levels[s].touches) + " tests) " + DoubleToString(SR_Levels[s].price, Digits);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, text);
      drawnCount++;
   }
}

//+------------------------------------------------------------------+
//| Check if price touches or is near a static S/R level             |
//+------------------------------------------------------------------+
bool IsNearStaticSR(double price, bool checkSupport, double &nearestLevel)
{
   if(!InpEnableStaticSR || SR_Count == 0) return false;

   double maxDist = InpSRZoneTolerancePips * PipMultiplier;
   for(int idx = 0; idx < SR_Count; idx++)
   {
      if(SR_Levels[idx].isSupport == checkSupport)
      {
         if(MathAbs(price - SR_Levels[idx].price) <= maxDist)
         {
            nearestLevel = SR_Levels[idx].price;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Candlestick Rejection & Absorption Analysis                      |
//+------------------------------------------------------------------+
bool IsBullishAbsorption(double openVal, double highVal, double lowVal, double closeVal)
{
   double range = highVal - lowVal;
   if(range <= 0.0) return false;

   double lowerWick = MathMin(openVal, closeVal) - lowVal;
   double upperWick = highVal - MathMax(openVal, closeVal);

   double lowerWickPct = (lowerWick / range) * 100.0;
   double upperWickPct = (upperWick / range) * 100.0;

   if(lowerWickPct < InpMinWickPercent) return false;
   if(upperWickPct > InpMaxOppositeWickPct) return false;

   if(InpRequireStrongClose)
   {
      if(closeVal < (lowVal + range * 0.45))
         return false;
   }

   return true;
}

bool IsBearishAbsorption(double openVal, double highVal, double lowVal, double closeVal)
{
   double range = highVal - lowVal;
   if(range <= 0.0) return false;

   double upperWick = highVal - MathMax(openVal, closeVal);
   double lowerWick = MathMin(openVal, closeVal) - lowVal;

   double upperWickPct = (upperWick / range) * 100.0;
   double lowerWickPct = (lowerWick / range) * 100.0;

   if(upperWickPct < InpMinWickPercent) return false;
   if(lowerWickPct > InpMaxOppositeWickPct) return false;

   if(InpRequireStrongClose)
   {
      if(closeVal > (highVal - range * 0.45))
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Market Structure Alignment Check (HH/HL for Bull, LH/LL for Bear)|
//+------------------------------------------------------------------+
int CheckMarketStructure(int barIdx, const double &high[], const double &low[], int rates_total)
{
   int lookback = MathMin(InpStructureLookback, rates_total - barIdx - 10);
   if(lookback < 15) return 0;

   double recentHigh1 = -1.0, recentHigh2 = -1.0;
   double recentLow1 = 999999.0, recentLow2 = 999999.0;
   int countH = 0, countL = 0;

   for(int b = barIdx + 2; b <= barIdx + lookback; b++)
   {
      if(high[b] > high[b - 1] && high[b] > high[b + 1])
      {
         if(countH == 0) { recentHigh1 = high[b]; countH++; }
         else if(countH == 1 && MathAbs(high[b] - recentHigh1) > (3.0 * PipMultiplier)) { recentHigh2 = high[b]; countH++; }
      }

      if(low[b] < low[b - 1] && low[b] < low[b + 1])
      {
         if(countL == 0) { recentLow1 = low[b]; countL++; }
         else if(countL == 1 && MathAbs(low[b] - recentLow1) > (3.0 * PipMultiplier)) { recentLow2 = low[b]; countL++; }
      }

      if(countH >= 2 && countL >= 2) break;
   }

   if(countH >= 2 && countL >= 2)
   {
      if(recentHigh1 >= recentHigh2 && recentLow1 >= recentLow2)
         return 1;
      if(recentHigh1 <= recentHigh2 && recentLow1 <= recentLow2)
         return -1;
   }

   return 0;
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
   if(rates_total < InpSlowEMAPeriod + 30) return(0);

   int limit = rates_total - prev_calculated;
   if(prev_calculated == 0)
   {
      limit = rates_total - InpSlowEMAPeriod - 2;
      ArrayInitialize(BufferBuyArrow, 0.0);
      ArrayInitialize(BufferSellArrow, 0.0);
      ArrayInitialize(BufferFastEMA, 0.0);
      ArrayInitialize(BufferSlowEMA, 0.0);
      ArrayInitialize(BufferEMABull, 0.0);
      ArrayInitialize(BufferEMABear, 0.0);
      ArrayInitialize(BufferFirstEntry, 0.0);
      TotalBuySignals = 0;
      TotalSellSignals = 0;
   }
   if(limit < 1) limit = 1;

   int i, k, bar;
   double fastEmaVal, slowEmaVal, prevFastEma, fastSlope;
   double curFastEMA, prevFastEMA, curSlowEMA;
   double emaTouchBuffer = InpEMATouchBufferPips * PipMultiplier;
   
   int swingHighBar, swingLowBar;
   int firstEntryLongBar, firstEntryShortBar;
   double maxHigh, minLow;
   int structureState;
   bool isBullishTrend, isBearishTrend;
   bool leg2Occurred, triggerSignal;
   bool touchedFastEMA, touchedSlowEMA, touchedEMA, nearSR, levelConfluence, candleAbsorption;
   double srLevel, slPrice, risk, tpPrice;

   // 1. Calculate Dual EMAs (13 Fast & 50 Slow)
   for(i = limit; i >= 0; i--)
   {
      fastEmaVal = iMA(NULL, 0, InpFastEMAPeriod, 0, InpEMAMethod, InpEMAAppliedPrice, i);
      slowEmaVal = iMA(NULL, 0, InpSlowEMAPeriod, 0, InpEMAMethod, InpEMAAppliedPrice, i);

      BufferFastEMA[i] = fastEmaVal;
      BufferSlowEMA[i] = slowEmaVal;

      if(InpEnableEMATrendColor && i < rates_total - 2)
      {
         prevFastEma = iMA(NULL, 0, InpFastEMAPeriod, 0, InpEMAMethod, InpEMAAppliedPrice, i + 1);
         fastSlope = (fastEmaVal - prevFastEma) / PipMultiplier;

         if(fastEmaVal > slowEmaVal && fastSlope > 0.2)
         {
            BufferEMABull[i] = fastEmaVal;
            BufferEMABear[i] = EMPTY_VALUE;
         }
         else if(fastEmaVal < slowEmaVal && fastSlope < -0.2)
         {
            BufferEMABear[i] = fastEmaVal;
            BufferEMABull[i] = EMPTY_VALUE;
         }
         else
         {
            BufferEMABull[i] = EMPTY_VALUE;
            BufferEMABear[i] = EMPTY_VALUE;
         }
      }
      else
      {
         BufferEMABull[i] = EMPTY_VALUE;
         BufferEMABear[i] = EMPTY_VALUE;
      }
   }

   // 2. Update Static Support & Resistance Mapping
   UpdateStaticSR(rates_total, high, low, time);

   // 3. Scan for Second Entry Failure Patterns (2L & 2S)
   for(i = limit; i >= 1; i--)
   {
      BufferBuyArrow[i] = 0.0;
      BufferSellArrow[i] = 0.0;
      BufferFirstEntry[i] = 0.0;

      curFastEMA = BufferFastEMA[i];
      prevFastEMA = BufferFastEMA[i + 1];
      curSlowEMA = BufferSlowEMA[i];
      fastSlope = (curFastEMA - prevFastEMA) / PipMultiplier;

      if(InpFilterRangeChop)
      {
         if(MathAbs(curFastEMA - curSlowEMA) < (InpMinEMASeparationPips * PipMultiplier))
            continue;
      }

      structureState = 0;
      if(InpRequireStructure)
      {
         structureState = CheckMarketStructure(i, high, low, rates_total);
      }

      // ===================================================================
      // BULLISH SETUP: Second Entry Long (2L)
      // ===================================================================
      if(InpEnable2L)
      {
         isBullishTrend = (curFastEMA >= curSlowEMA && fastSlope >= -0.1 && close[i] >= curSlowEMA - (2.0 * PipMultiplier));
         if(InpRequireStructure && structureState == -1)
         {
            isBullishTrend = false;
         }

         if(isBullishTrend)
         {
            swingHighBar = -1;
            maxHigh = -1.0;

            for(k = i + 1; k <= i + InpMaxPullbackBars && k < rates_total - 2; k++)
            {
               if(high[k] > curFastEMA && high[k] > maxHigh)
               {
                  maxHigh = high[k];
                  swingHighBar = k;
               }
            }

            if(swingHighBar > i + InpMinPullbackBars)
            {
               firstEntryLongBar = -1;

               for(bar = swingHighBar - 1; bar > i; bar--)
               {
                  if(high[bar] > high[bar + 1])
                  {
                     firstEntryLongBar = bar;
                     break;
                  }
               }

               if(firstEntryLongBar > i)
               {
                  if(InpShow1stEntryMarkers)
                  {
                     BufferFirstEntry[firstEntryLongBar] = low[firstEntryLongBar] - (3.0 * PipMultiplier);
                  }

                  leg2Occurred = false;
                  for(bar = firstEntryLongBar - 1; bar >= i; bar--)
                  {
                     if(low[bar] < low[bar + 1])
                     {
                        leg2Occurred = true;
                        break;
                     }
                  }

                  if(leg2Occurred)
                  {
                     triggerSignal = (high[i] > high[i + 1] || close[i] > open[i]);

                     if(triggerSignal)
                     {
                        touchedFastEMA = (low[i] <= curFastEMA + emaTouchBuffer && high[i] >= curFastEMA - emaTouchBuffer);
                        touchedSlowEMA = (low[i] <= curSlowEMA + emaTouchBuffer && high[i] >= curSlowEMA - emaTouchBuffer);
                        touchedEMA = (touchedFastEMA || touchedSlowEMA);

                        srLevel = 0.0;
                        nearSR = IsNearStaticSR(low[i], true, srLevel);

                        if(InpRequireSRConfluence)
                           levelConfluence = (touchedEMA && nearSR);
                        else if(InpRequireEMATouch)
                           levelConfluence = (touchedEMA || nearSR);
                        else
                           levelConfluence = true;

                        candleAbsorption = true;
                        if(InpRequireAbsorption)
                        {
                           candleAbsorption = IsBullishAbsorption(open[i], high[i], low[i], close[i]);
                        }

                        if(levelConfluence && candleAbsorption)
                        {
                           BufferBuyArrow[i] = low[i] - (5.0 * PipMultiplier);
                           TotalBuySignals++;

                           if(InpShowPatternLabels)
                           {
                              CreateSignalLabel(time[i], BufferBuyArrow[i] - (3.0 * PipMultiplier), "2L", clrLime, true);
                           }

                           if(InpShowSLTP)
                           {
                              slPrice = low[i] - (InpSLBufferPips * PipMultiplier);
                              risk = (close[i] - slPrice);
                              tpPrice = close[i] + (risk * InpRiskRewardRatio);
                              DrawSLTP(time[i], close[i], slPrice, tpPrice, true);
                           }

                           if(i == 1 && time[1] != LastAlertTime)
                           {
                              TriggerAlert("2L (Second Entry Long) Setup", close[1], time[1]);
                              LastAlertTime = time[1];
                           }
                        }
                     }
                  }
               }
            }
         }
      }

      // ===================================================================
      // BEARISH SETUP: Second Entry Short (2S)
      // ===================================================================
      if(InpEnable2S)
      {
         isBearishTrend = (curFastEMA <= curSlowEMA && fastSlope <= 0.1 && close[i] <= curSlowEMA + (2.0 * PipMultiplier));
         if(InpRequireStructure && structureState == 1)
         {
            isBearishTrend = false;
         }

         if(isBearishTrend)
         {
            swingLowBar = -1;
            minLow = 999999.0;

            for(k = i + 1; k <= i + InpMaxPullbackBars && k < rates_total - 2; k++)
            {
               if(low[k] < curFastEMA && low[k] < minLow)
               {
                  minLow = low[k];
                  swingLowBar = k;
               }
            }

            if(swingLowBar > i + InpMinPullbackBars)
            {
               firstEntryShortBar = -1;

               for(bar = swingLowBar - 1; bar > i; bar--)
               {
                  if(low[bar] < low[bar + 1])
                  {
                     firstEntryShortBar = bar;
                     break;
                  }
               }

               if(firstEntryShortBar > i)
               {
                  if(InpShow1stEntryMarkers)
                  {
                     BufferFirstEntry[firstEntryShortBar] = high[firstEntryShortBar] + (3.0 * PipMultiplier);
                  }

                  leg2Occurred = false;
                  for(bar = firstEntryShortBar - 1; bar >= i; bar--)
                  {
                     if(high[bar] > high[bar + 1])
                     {
                        leg2Occurred = true;
                        break;
                     }
                  }

                  if(leg2Occurred)
                  {
                     triggerSignal = (low[i] < low[i + 1] || close[i] < open[i]);

                     if(triggerSignal)
                     {
                        touchedFastEMA = (high[i] >= curFastEMA - emaTouchBuffer && low[i] <= curFastEMA + emaTouchBuffer);
                        touchedSlowEMA = (high[i] >= curSlowEMA - emaTouchBuffer && low[i] <= curSlowEMA + emaTouchBuffer);
                        touchedEMA = (touchedFastEMA || touchedSlowEMA);

                        srLevel = 0.0;
                        nearSR = IsNearStaticSR(high[i], false, srLevel);

                        if(InpRequireSRConfluence)
                           levelConfluence = (touchedEMA && nearSR);
                        else if(InpRequireEMATouch)
                           levelConfluence = (touchedEMA || nearSR);
                        else
                           levelConfluence = true;

                        candleAbsorption = true;
                        if(InpRequireAbsorption)
                        {
                           candleAbsorption = IsBearishAbsorption(open[i], high[i], low[i], close[i]);
                        }

                        if(levelConfluence && candleAbsorption)
                        {
                           BufferSellArrow[i] = high[i] + (5.0 * PipMultiplier);
                           TotalSellSignals++;

                           if(InpShowPatternLabels)
                           {
                              CreateSignalLabel(time[i], BufferSellArrow[i] + (3.0 * PipMultiplier), "2S", clrRed, false);
                           }

                           if(InpShowSLTP)
                           {
                              slPrice = high[i] + (InpSLBufferPips * PipMultiplier);
                              risk = (slPrice - close[i]);
                              tpPrice = close[i] - (risk * InpRiskRewardRatio);
                              DrawSLTP(time[i], close[i], slPrice, tpPrice, false);
                           }

                           if(i == 1 && time[1] != LastAlertTime)
                           {
                              TriggerAlert("2S (Second Entry Short) Setup", close[1], time[1]);
                              LastAlertTime = time[1];
                           }
                        }
                     }
                  }
               }
            }
         }
      }
   }

   // 4. Update HUD Dashboard
   if(InpShowDashboard)
   {
      UpdateDashboard(close[0], BufferFastEMA[0], BufferSlowEMA[0], (BufferFastEMA[0] - BufferFastEMA[1]) / PipMultiplier);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Create Text Label on Chart for 2L / 2S                           |
//+------------------------------------------------------------------+
void CreateSignalLabel(datetime t, double price, string text, color clr, bool isLong)
{
   string name = Prefix + "LBL_" + TimeToString(t, TIME_DATE|TIME_MINUTES);
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isLong ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw SL and TP Targets on Chart                                  |
//+------------------------------------------------------------------+
void DrawSLTP(datetime t, double entry, double sl, double tp, bool isLong)
{
   string nameSL = Prefix + "SL_" + TimeToString(t, TIME_DATE|TIME_MINUTES);
   string nameTP = Prefix + "TP_" + TimeToString(t, TIME_DATE|TIME_MINUTES);

   datetime tEnd = t + (datetime)(PeriodSeconds() * 10);

   // SL Line
   ObjectCreate(0, nameSL, OBJ_TREND, 0, t, sl, tEnd, sl);
   ObjectSetInteger(0, nameSL, OBJPROP_COLOR, clrCrimson);
   ObjectSetInteger(0, nameSL, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nameSL, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nameSL, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, nameSL, OBJPROP_TOOLTIP, "Stop Loss: " + DoubleToString(sl, Digits));

   // TP Line
   ObjectCreate(0, nameTP, OBJ_TREND, 0, t, tp, tEnd, tp);
   ObjectSetInteger(0, nameTP, OBJPROP_COLOR, clrLimeGreen);
   ObjectSetInteger(0, nameTP, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nameTP, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nameTP, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, nameTP, OBJPROP_TOOLTIP, "Take Profit (1:" + DoubleToString(InpRiskRewardRatio, 1) + "): " + DoubleToString(tp, Digits));
}

//+------------------------------------------------------------------+
//| Multi-Alert Engine Execution                                     |
//+------------------------------------------------------------------+
void TriggerAlert(string patternName, double price, datetime t)
{
   string msg = StringFormat("[%s] %s | Pair: %s | Timeframe: %s | Price: %s",
                             "2nd Entry PA",
                             patternName,
                             Symbol(),
                             EnumToString((ENUM_TIMEFRAMES)Period()),
                             DoubleToString(price, Digits));

   if(InpPopupAlert)
   {
      Alert(msg);
   }

   if(InpSoundAlert)
   {
      PlaySound(InpSoundFile);
   }

   if(InpPushNotification)
   {
      SendNotification(msg);
   }

   if(InpEmailAlert)
   {
      SendMail("MT4 Strategy Alert: " + patternName, msg);
   }
}

//+------------------------------------------------------------------+
//| Draw On-Chart HUD Information Dashboard                          |
//+------------------------------------------------------------------+
void UpdateDashboard(double curPrice, double fastEMA, double slowEMA, double fastSlope)
{
   string bgName = Prefix + "Dash_BG";
   string titleName = Prefix + "Dash_Title";
   string row1Name = Prefix + "Dash_R1";
   string row2Name = Prefix + "Dash_R2";
   string row3Name = Prefix + "Dash_R3";
   string row4Name = Prefix + "Dash_R4";

   int xOffset = 20;
   int yOffset = 30;

   // 1. Background Box
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, InpDashboardCorner);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, xOffset);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, yOffset);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 255);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 135);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, InpDashboardBgColor);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, bgName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
   }

   // Trend & Structure Evaluation
   string trendStr = "CHOP / CONSOLIDATION";
   color trendClr = clrGold;
   if(fastEMA > slowEMA && fastSlope > 0.2 && curPrice >= fastEMA - (2.0 * PipMultiplier))
   {
      trendStr = "BULLISH (13>50 EMA + HH/HL)";
      trendClr = clrLimeGreen;
   }
   else if(fastEMA < slowEMA && fastSlope < -0.2 && curPrice <= fastEMA + (2.0 * PipMultiplier))
   {
      trendStr = "BEARISH (13<50 EMA + LH/LL)";
      trendClr = clrCrimson;
   }

   // Title Label
   CreateOrUpdateLabel(titleName, "  2L/2S PRICE ACTION PRO", xOffset + 12, yOffset + 10, clrDodgerBlue, 10, true);
   
   // Row 1: Trend & Structure
   CreateOrUpdateLabel(row1Name, "Trend: " + trendStr, xOffset + 12, yOffset + 35, trendClr, 8, false);

   // Row 2: Dual EMA Confluence
   string emaText = StringFormat("13/50 EMA: %s / %s", DoubleToString(fastEMA, Digits), DoubleToString(slowEMA, Digits));
   CreateOrUpdateLabel(row2Name, emaText, xOffset + 12, yOffset + 55, clrLightSteelBlue, 8, false);

   // Row 3: Static S/R Levels
   string srText = StringFormat("Static S/R: %d Active Zones Mapped", SR_Count);
   CreateOrUpdateLabel(row3Name, srText, xOffset + 12, yOffset + 75, clrWhite, 8, false);

   // Row 4: Live Setup Status
   string ruleText = "Waiting for 2-Leg Pullback...";
   if(trendClr == clrLimeGreen) ruleText = "Scanning 2L Pullback to 13/50 EMA & Support";
   else if(trendClr == clrCrimson) ruleText = "Scanning 2S Pullback to 13/50 EMA & Resistance";
   CreateOrUpdateLabel(row4Name, ruleText, xOffset + 12, yOffset + 98, clrAquamarine, 8, false);
}

//+------------------------------------------------------------------+
//| Helper to create/update Label Object                             |
//+------------------------------------------------------------------+
void CreateOrUpdateLabel(string name, string text, int x, int y, color clr, int fontSize, bool isBold)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpDashboardCorner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, isBold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}
//+------------------------------------------------------------------+
