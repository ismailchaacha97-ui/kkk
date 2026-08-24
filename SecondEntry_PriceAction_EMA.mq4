//+------------------------------------------------------------------+
//|                                  SecondEntry_PriceAction_EMA.mq4 |
//|                                  Copyright 2026, Arena AI Trader |
//|                                      https://arena.ai/trading    |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Arena AI Trader"
#property link        "https://arena.ai/trading"
#property version     "2.10"
#property description "Institutional Price Action Trading (PATs) Indicator"
#property description "Detects Second Entry Long (2EL) & Second Entry Short (2ES) with 21 EMA Dynamic S/R and Naked S/R levels."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

// Plot 1: Buy Arrow (2EL)
#property indicator_label1  "2EL Buy Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 2: Sell Arrow (2ES)
#property indicator_label2  "2ES Sell Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 3: EMA Main Line
#property indicator_label3  "Dynamic EMA Base"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

// Plot 4: Bullish EMA Slope
#property indicator_label4  "EMA Bullish Trend"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrLimeGreen
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

// Plot 5: Bearish EMA Slope
#property indicator_label5  "EMA Bearish Trend"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrCrimson
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

// Plot 6: 1st Entry Marker (Educational/Optional)
#property indicator_label6  "1st Entry Marker"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrDarkGray
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

// --- 1. Dynamic EMA Settings ---
input string               Section_EMA             = "=== 1. EMA (DYNAMIC S/R) SETTINGS ==="; // --- EMA Settings ---
input int                  InpEMAPeriod            = 21;              // EMA Period (Default: 21)
input ENUM_MA_METHOD       InpEMAMethod            = MODE_EMA;        // Moving Average Method
input ENUM_APPLIED_PRICE   InpEMAAppliedPrice      = PRICE_CLOSE;     // Applied Price
input bool                 InpEnableEMATrendColor  = true;            // Color EMA by Trend Direction
input double               InpEMASlopeThresholdPts = 1.5;             // Slope Threshold (Points/Pips)
input int                  InpEMALineWidth         = 2;               // EMA Line Width

// --- 2. Naked Support & Resistance Settings ---
input string               Section_SR              = "=== 2. HORIZONTAL S/R SETTINGS ==="; // --- S/R Settings ---
input bool                 InpEnableSR             = true;            // Enable Naked S/R Detection
input int                  InpSRBarsBack           = 300;             // Historical Bars to Scan
input int                  InpSRSwingStrength      = 5;               // Swing Fractal Strength (Left/Right bars)
input int                  InpSRMinTouches         = 2;               // Min Touches to confirm Key Level
input double               InpSRZoneTolerancePips  = 6.0;             // S/R Level Zone Tolerance (Pips)
input int                  InpSRMaxLines           = 6;               // Max S/R Lines to display
input color                InpColorSupport         = clrDeepSkyBlue;  // Support Line Color
input color                InpColorResistance      = clrOrangeRed;    // Resistance Line Color
input ENUM_LINE_STYLE      InpSRLineStyle          = STYLE_DASH;      // S/R Line Style

// --- 3. Second Entry (2EL / 2ES) Core Rules ---
input string               Section_Strategy        = "=== 3. SECOND ENTRY STRATEGY RULES ==="; // --- Strategy Rules ---
input bool                 InpEnable2EL            = true;            // Enable Second Entry Long (2EL)
input bool                 InpEnable2ES            = true;            // Enable Second Entry Short (2ES)
input int                  InpMaxPullbackBars      = 25;              // Max Pullback Duration (Bars)
input int                  InpMinPullbackBars      = 2;               // Min Pullback Duration (Bars)
input bool                 InpStrictTrendFilter    = true;            // Strict Trend Filter (Price on correct side of EMA)
input bool                 InpAllowSRBounces       = true;            // Allow Bounces off Key S/R if near EMA
input double               InpMaxLevelDistPips     = 10.0;            // Max Distance from EMA/SR Level (Pips)

// --- 4. Candle Confirmation & Rejection Filters ---
input string               Section_Candle          = "=== 4. CANDLE REJECTION FILTERS ==="; // --- Candle Confirmation ---
input bool                 InpRequireRejection     = true;            // Require Sharp Rejection / Pinbar
input double               InpMinWickPercent       = 35.0;            // Min Rejection Wick % of Total Candle (e.g. 35%)
input double               InpMaxOppositeWickPct   = 35.0;            // Max Opposing Wick %
input bool                 InpRequireCloseInTrend  = true;            // Require Bullish Close for 2EL / Bearish for 2ES
input bool                 InpMustTouchLevel       = true;            // Candle Wick MUST Touch EMA or S/R

// --- 5. Risk Management & Targets (SL / TP Projections) ---
input string               Section_Risk            = "=== 5. RISK MANAGEMENT & TARGETS ==="; // --- SL / TP ---
input bool                 InpShowSLTP             = true;            // Draw SL & TP Target Lines on Chart
input double               InpRiskRewardRatio      = 2.0;             // Take Profit Risk:Reward Ratio (e.g. 2.0)
input double               InpSLBufferPips         = 2.0;             // Stop Loss Buffer below/above Signal (Pips)
input int                  InpATRPeriod            = 14;              // ATR Period for Dynamic Volatility Buffer

// --- 6. Visual Display & On-Chart Dashboard ---
input string               Section_Visuals         = "=== 6. VISUALS & HUD DASHBOARD ==="; // --- Visuals ---
input int                  InpBuyArrowCode         = 233;             // Buy Arrow Wingdings Code (233=Arrow Up)
input int                  InpSellArrowCode        = 234;             // Sell Arrow Wingdings Code (234=Arrow Down)
input int                  InpArrowSize            = 2;               // Signal Arrow Size
input bool                 InpShowPatternLabels    = true;            // Show "2EL" / "2ES" Text Labels
input bool                 InpShow1stEntryMarkers  = false;           // Show "1EL" / "1ES" educational dots
input bool                 InpShowDashboard        = true;            // Show On-Chart HUD Dashboard
input ENUM_BASE_CORNER     InpDashboardCorner      = CORNER_RIGHT_UPPER; // Dashboard Screen Corner
input color                InpDashboardBgColor     = C'20,24,35';     // Dashboard Background Color
input color                InpDashboardTextColor   = clrWhite;        // Dashboard Text Color

// --- 7. Multi-Alert Engine ---
input string               Section_Alerts          = "=== 7. ALERTS & NOTIFICATIONS ==="; // --- Alerts ---
input bool                 InpAlertOnBarClose      = true;            // Alert Only on Bar Close (No Repaint)
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
double BufferEMAMain[];
double BufferEMABull[];
double BufferEMABear[];
double BufferFirstEntry[];

string   Prefix = "2E_PA_";
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

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set Pip Multiplier based on digits (handles 3 & 5 digit brokers)
   if(Digits == 3 || Digits == 5)
   {
      PipMultiplier = Point * 10;
      PipDigits = Digits - 1;
   }
   else
   {
      PipMultiplier = Point;
      PipDigits = Digits;
   }

   // Indicator Buffers Mapping
   IndicatorBuffers(6);

   // Buffer 0: Buy Signal (2EL)
   SetIndexBuffer(0, BufferBuyArrow);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, InpArrowSize, clrLime);
   SetIndexArrow(0, InpBuyArrowCode);
   SetIndexEmptyValue(0, 0.0);
   ArraySetAsSeries(BufferBuyArrow, true);

   // Buffer 1: Sell Signal (2ES)
   SetIndexBuffer(1, BufferSellArrow);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, InpArrowSize, clrRed);
   SetIndexArrow(1, InpSellArrowCode);
   SetIndexEmptyValue(1, 0.0);
   ArraySetAsSeries(BufferSellArrow, true);

   // Buffer 2: EMA Base Line
   SetIndexBuffer(2, BufferEMAMain);
   SetIndexStyle(2, DRAW_LINE, STYLE_SOLID, InpEMALineWidth, clrDodgerBlue);
   SetIndexEmptyValue(2, 0.0);
   ArraySetAsSeries(BufferEMAMain, true);

   // Buffer 3: EMA Bullish Slope
   SetIndexBuffer(3, BufferEMABull);
   SetIndexStyle(3, DRAW_LINE, STYLE_SOLID, InpEMALineWidth, clrLimeGreen);
   SetIndexEmptyValue(3, 0.0);
   ArraySetAsSeries(BufferEMABull, true);

   // Buffer 4: EMA Bearish Slope
   SetIndexBuffer(4, BufferEMABear);
   SetIndexStyle(4, DRAW_LINE, STYLE_SOLID, InpEMALineWidth, clrCrimson);
   SetIndexEmptyValue(4, 0.0);
   ArraySetAsSeries(BufferEMABear, true);

   // Buffer 5: 1st Entry Marker
   SetIndexBuffer(5, BufferFirstEntry);
   SetIndexStyle(5, DRAW_ARROW, STYLE_DOT, 1, clrDarkGray);
   SetIndexArrow(5, 159);
   SetIndexEmptyValue(5, 0.0);
   ArraySetAsSeries(BufferFirstEntry, true);

   // Clear any existing chart objects with our prefix
   ObjectsDeleteAll(0, Prefix);

   IndicatorShortName("Second Entry PA Pro (21 EMA + S/R)");

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
//| Horizontal Support and Resistance Calculation                    |
//+------------------------------------------------------------------+
void UpdateSRLevels(int rates_total, const double &high[], const double &low[], const datetime &time[])
{
   if(!InpEnableSR) return;

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

   // Detect Fractal Swings
   for(int i = InpSRSwingStrength + 1; i < scanLimit; i++)
   {
      bool isHigh = true;
      bool isLow = true;

      for(int k = 1; k <= InpSRSwingStrength; k++)
      {
         if(high[i] <= high[i - k] || high[i] < high[i + k])
            isHigh = false;
         if(low[i] >= low[i - k] || low[i] > low[i + k])
            isLow = false;
      }

      if(isHigh)
      {
         swingHighs[countHighs] = high[i];
         swingHighTimes[countHighs] = time[i];
         countHighs++;
      }
      if(isLow)
      {
         swingLows[countLows] = low[i];
         swingLowTimes[countLows] = time[i];
         countLows++;
      }
   }

   // Group Resistance Levels
   double zonePips = InpSRZoneTolerancePips * PipMultiplier;
   bool usedHigh[];
   ArrayResize(usedHigh, countHighs);
   ArrayInitialize(usedHigh, false);

   for(int h1 = 0; h1 < countHighs; h1++)
   {
      if(usedHigh[h1]) continue;

      double sumPrice = swingHighs[h1];
      int touches = 1;
      datetime lastT = swingHighTimes[h1];

      for(int h2 = h1 + 1; h2 < countHighs; h2++)
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

   // Group Support Levels
   bool usedLow[];
   ArrayResize(usedLow, countLows);
   ArrayInitialize(usedLow, false);

   for(int l1 = 0; l1 < countLows; l1++)
   {
      if(usedLow[l1]) continue;

      double sumPrice = swingLows[l1];
      int touches = 1;
      datetime lastT = swingLowTimes[l1];

      for(int l2 = l1 + 1; l2 < countLows; l2++)
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

   // Render S/R Lines on Chart
   DrawSRLevels();
}

//+------------------------------------------------------------------+
//| Draw Support & Resistance Lines on Chart                         |
//+------------------------------------------------------------------+
void DrawSRLevels()
{
   for(int i = ObjectsTotal(0, 0, OBJ_HLINE) - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i, 0, OBJ_HLINE);
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
      
      string text = (SR_Levels[s].isSupport ? "Key Support (" : "Key Resistance (") + 
                    IntegerToString(SR_Levels[s].touches) + " tests) " + DoubleToString(SR_Levels[s].price, Digits);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, text);
      drawnCount++;
   }
}

//+------------------------------------------------------------------+
//| Check if price is near any active S/R level                      |
//+------------------------------------------------------------------+
bool IsNearSR(double price, bool checkSupport, double &nearestLevel)
{
   if(!InpEnableSR || SR_Count == 0) return false;

   double maxDist = InpMaxLevelDistPips * PipMultiplier;
   for(int i = 0; i < SR_Count; i++)
   {
      if(SR_Levels[i].isSupport == checkSupport)
      {
         if(MathAbs(price - SR_Levels[i].price) <= maxDist)
         {
            nearestLevel = SR_Levels[i].price;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Rejection Candle Analysis                                        |
//+------------------------------------------------------------------+
bool IsBullishRejection(double open, double high, double low, double close)
{
   double range = high - low;
   if(range <= 0.0) return false;

   double lowerWick = MathMin(open, close) - low;
   double upperWick = high - MathMax(open, close);

   double lowerWickPct = (lowerWick / range) * 100.0;
   double upperWickPct = (upperWick / range) * 100.0;

   // Lower wick must meet minimum percentage
   if(lowerWickPct < InpMinWickPercent) return false;

   // Upper wick should not be excessive
   if(upperWickPct > InpMaxOppositeWickPct) return false;

   // Directional close check
   if(InpRequireCloseInTrend)
   {
      if(close < open && close < (low + range * 0.45))
         return false;
   }

   return true;
}

bool IsBearishRejection(double open, double high, double low, double close)
{
   double range = high - low;
   if(range <= 0.0) return false;

   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;

   double upperWickPct = (upperWick / range) * 100.0;
   double lowerWickPct = (lowerWick / range) * 100.0;

   // Upper wick must meet minimum percentage
   if(upperWickPct < InpMinWickPercent) return false;

   // Lower wick should not be excessive
   if(lowerWickPct > InpMaxOppositeWickPct) return false;

   // Directional close check
   if(InpRequireCloseInTrend)
   {
      if(close > open && close > (high - range * 0.45))
         return false;
   }

   return true;
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
   if(rates_total < InpEMAPeriod + 30) return(0);

   int limit = rates_total - prev_calculated;
   if(prev_calculated == 0)
   {
      limit = rates_total - InpEMAPeriod - 2;
      ArrayInitialize(BufferBuyArrow, 0.0);
      ArrayInitialize(BufferSellArrow, 0.0);
      ArrayInitialize(BufferEMAMain, 0.0);
      ArrayInitialize(BufferEMABull, 0.0);
      ArrayInitialize(BufferEMABear, 0.0);
      ArrayInitialize(BufferFirstEntry, 0.0);
      TotalBuySignals = 0;
      TotalSellSignals = 0;
   }
   if(limit < 1) limit = 1;

   // 1. Calculate Base EMA & Slope Buffers
   for(int i = limit; i >= 0; i--)
   {
      double emaVal = iMA(NULL, 0, InpEMAPeriod, 0, InpEMAMethod, InpEMAAppliedPrice, i);
      BufferEMAMain[i] = emaVal;

      if(InpEnableEMATrendColor && i < rates_total - 2)
      {
         double prevEma = iMA(NULL, 0, InpEMAPeriod, 0, InpEMAMethod, InpEMAAppliedPrice, i + 1);
         double slope = (emaVal - prevEma) / PipMultiplier;

         if(slope > InpEMASlopeThresholdPts)
         {
            BufferEMABull[i] = emaVal;
            BufferEMABear[i] = EMPTY_VALUE;
         }
         else if(slope < -InpEMASlopeThresholdPts)
         {
            BufferEMABear[i] = emaVal;
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

   // 2. Update Horizontal Support & Resistance Levels
   UpdateSRLevels(rates_total, high, low, time);

   // 3. Scan for Second Entry Long (2EL) and Second Entry Short (2ES)
   double maxDist = InpMaxLevelDistPips * PipMultiplier;
   
   for(int i = limit; i >= 1; i--)
   {
      BufferBuyArrow[i] = 0.0;
      BufferSellArrow[i] = 0.0;
      BufferFirstEntry[i] = 0.0;

      double curEMA = BufferEMAMain[i];
      double prevEMA = BufferEMAMain[i + 1];
      double emaSlope = (curEMA - prevEMA) / PipMultiplier;

      // ===================================================================
      // BULLISH SETUP: Second Entry Long (2EL)
      // ===================================================================
      if(InpEnable2EL)
      {
         // Trend condition: EMA sloping up or price comfortably above EMA
         bool isUptrend = (emaSlope >= -0.2 && close[i] >= curEMA - (2 * PipMultiplier));
         if(InpStrictTrendFilter)
         {
            isUptrend = (emaSlope > 0.0 && close[i] > curEMA);
         }

         if(isUptrend)
         {
            // Find swing high that started the pullback
            int swingHighBar = -1;
            double maxHigh = -1.0;

            for(int k = i + 1; k <= i + InpMaxPullbackBars && k < rates_total - 2; k++)
            {
               if(high[k] > curEMA && high[k] > maxHigh)
               {
                  maxHigh = high[k];
                  swingHighBar = k;
               }
            }

            if(swingHighBar > i + InpMinPullbackBars)
            {
               int firstEntryLongBar = -1;

               // Scan for First Entry Long (1EL)
               for(int bar = swingHighBar - 1; bar > i; bar--)
               {
                  if(high[bar] > high[bar + 1])
                  {
                     firstEntryLongBar = bar;
                     break;
                  }
               }

               // If 1EL occurred, scan for 2nd push down and 2EL trigger
               if(firstEntryLongBar > i)
               {
                  if(InpShow1stEntryMarkers)
                  {
                     BufferFirstEntry[firstEntryLongBar] = low[firstEntryLongBar] - (3 * PipMultiplier);
                  }

                  // Check if price pushed down again after 1EL (Leg 2 Down)
                  bool leg2Occurred = false;
                  for(int bar = firstEntryLongBar - 1; bar >= i; bar--)
                  {
                     if(low[bar] < low[bar + 1])
                     {
                        leg2Occurred = true;
                        break;
                     }
                  }

                  if(leg2Occurred)
                  {
                     // Check if bar 'i' triggered 2EL
                     bool trigger2EL = (high[i] > high[i + 1] || close[i] > open[i]);

                     if(trigger2EL)
                     {
                        double srLevel = 0.0;
                        bool nearEMA = (MathAbs(low[i] - curEMA) <= maxDist || (low[i] <= curEMA && close[i] >= curEMA));
                        bool nearSR = IsNearSR(low[i], true, srLevel);

                        bool levelValid = nearEMA || (InpAllowSRBounces && nearSR);

                        bool candleValid = true;
                        if(InpRequireRejection)
                        {
                           candleValid = IsBullishRejection(open[i], high[i], low[i], close[i]);
                        }

                        if(InpMustTouchLevel)
                        {
                           bool touched = (low[i] <= curEMA + (2 * PipMultiplier)) || (nearSR && low[i] <= srLevel + (2 * PipMultiplier));
                           if(!touched) candleValid = false;
                        }

                        if(levelValid && candleValid)
                        {
                           BufferBuyArrow[i] = low[i] - (5 * PipMultiplier);
                           TotalBuySignals++;

                           if(InpShowPatternLabels)
                           {
                              CreateSignalLabel(time[i], BufferBuyArrow[i] - (3 * PipMultiplier), "2EL", clrLime, true);
                           }

                           if(InpShowSLTP)
                           {
                              double slPrice = low[i] - (InpSLBufferPips * PipMultiplier);
                              double risk = (close[i] - slPrice);
                              double tpPrice = close[i] + (risk * InpRiskRewardRatio);
                              DrawSLTP(time[i], close[i], slPrice, tpPrice, true);
                           }

                           if(i == 1 && time[1] != LastAlertTime)
                           {
                              TriggerAlert("2EL (Second Entry Long) Bullish Setup", close[1], time[1]);
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
      // BEARISH SETUP: Second Entry Short (2ES)
      // ===================================================================
      if(InpEnable2ES)
      {
         // Trend condition: EMA sloping down or price comfortably below EMA
         bool isDowntrend = (emaSlope <= 0.2 && close[i] <= curEMA + (2 * PipMultiplier));
         if(InpStrictTrendFilter)
         {
            isDowntrend = (emaSlope < 0.0 && close[i] < curEMA);
         }

         if(isDowntrend)
         {
            // Find swing low that started the pullback
            int swingLowBar = -1;
            double minLow = 999999.0;

            for(int k = i + 1; k <= i + InpMaxPullbackBars && k < rates_total - 2; k++)
            {
               if(low[k] < curEMA && low[k] < minLow)
               {
                  minLow = low[k];
                  swingLowBar = k;
               }
            }

            if(swingLowBar > i + InpMinPullbackBars)
            {
               int firstEntryShortBar = -1;

               // Scan for First Entry Short (1ES)
               for(int bar = swingLowBar - 1; bar > i; bar--)
               {
                  if(low[bar] < low[bar + 1])
                  {
                     firstEntryShortBar = bar;
                     break;
                  }
               }

               // If 1ES occurred, scan for 2nd push up and 2ES trigger
               if(firstEntryShortBar > i)
               {
                  if(InpShow1stEntryMarkers)
                  {
                     BufferFirstEntry[firstEntryShortBar] = high[firstEntryShortBar] + (3 * PipMultiplier);
                  }

                  // Check if price pushed up again after 1ES (Leg 2 Up)
                  bool leg2Occurred = false;
                  for(int bar = firstEntryShortBar - 1; bar >= i; bar--)
                  {
                     if(high[bar] > high[bar + 1])
                     {
                        leg2Occurred = true;
                        break;
                     }
                  }

                  if(leg2Occurred)
                  {
                     // Check if bar 'i' triggered 2ES
                     bool trigger2ES = (low[i] < low[i + 1] || close[i] < open[i]);

                     if(trigger2ES)
                     {
                        double srLevel = 0.0;
                        bool nearEMA = (MathAbs(high[i] - curEMA) <= maxDist || (high[i] >= curEMA && close[i] <= curEMA));
                        bool nearSR = IsNearSR(high[i], false, srLevel);

                        bool levelValid = nearEMA || (InpAllowSRBounces && nearSR);

                        bool candleValid = true;
                        if(InpRequireRejection)
                        {
                           candleValid = IsBearishRejection(open[i], high[i], low[i], close[i]);
                        }

                        if(InpMustTouchLevel)
                        {
                           bool touched = (high[i] >= curEMA - (2 * PipMultiplier)) || (nearSR && high[i] >= srLevel - (2 * PipMultiplier));
                           if(!touched) candleValid = false;
                        }

                        if(levelValid && candleValid)
                        {
                           BufferSellArrow[i] = high[i] + (5 * PipMultiplier);
                           TotalSellSignals++;

                           if(InpShowPatternLabels)
                           {
                              CreateSignalLabel(time[i], BufferSellArrow[i] + (3 * PipMultiplier), "2ES", clrRed, false);
                           }

                           if(InpShowSLTP)
                           {
                              double slPrice = high[i] + (InpSLBufferPips * PipMultiplier);
                              double risk = (slPrice - close[i]);
                              double tpPrice = close[i] - (risk * InpRiskRewardRatio);
                              DrawSLTP(time[i], close[i], slPrice, tpPrice, false);
                           }

                           if(i == 1 && time[1] != LastAlertTime)
                           {
                              TriggerAlert("2ES (Second Entry Short) Bearish Setup", close[1], time[1]);
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
      UpdateDashboard(close[0], BufferEMAMain[0], (BufferEMAMain[0] - BufferEMAMain[1]) / PipMultiplier);
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Create Text Label on Chart for 2EL / 2ES                         |
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

   datetime tEnd = t + PeriodSeconds() * 10;

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
void UpdateDashboard(double curPrice, double emaVal, double emaSlope)
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
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 240);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 130);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, InpDashboardBgColor);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, bgName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
   }

   // Trend Evaluation
   string trendStr = "NEUTRAL / FLAT";
   color trendClr = clrGold;
   if(emaSlope > InpEMASlopeThresholdPts && curPrice >= emaVal)
   {
      trendStr = "BULLISH (UPTREND)";
      trendClr = clrLimeGreen;
   }
   else if(emaSlope < -InpEMASlopeThresholdPts && curPrice <= emaVal)
   {
      trendStr = "BEARISH (DOWNTREND)";
      trendClr = clrCrimson;
   }

   // Title Label
   CreateOrUpdateLabel(titleName, "  PATs SECOND ENTRY PRO", xOffset + 12, yOffset + 10, clrDodgerBlue, 10, true);
   
   // Row 1: Trend
   CreateOrUpdateLabel(row1Name, "Trend: " + trendStr, xOffset + 12, yOffset + 35, trendClr, 8, false);

   // Row 2: EMA Status
   string emaText = StringFormat("EMA(%d): %s (Slope: %+.1f pips)", InpEMAPeriod, DoubleToString(emaVal, Digits), emaSlope);
   CreateOrUpdateLabel(row2Name, emaText, xOffset + 12, yOffset + 55, clrLightSteelBlue, 8, false);

   // Row 3: Active S/R Levels
   string srText = StringFormat("Naked S/R: %d Active Levels", SR_Count);
   CreateOrUpdateLabel(row3Name, srText, xOffset + 12, yOffset + 75, clrWhite, 8, false);

   // Row 4: Rule Status
   string ruleText = "Waiting for 2-Legged Pullback...";
   if(trendClr == clrLimeGreen) ruleText = "Bullish Filter: Watch for 2EL at EMA";
   else if(trendClr == clrCrimson) ruleText = "Bearish Filter: Watch for 2ES at EMA";
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
