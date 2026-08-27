//+------------------------------------------------------------------+
//|                                        VeteranTrader_Pro_V1.mq4  |
//|                       Veteran 30-Year Wall Street Trading Engine |
//|                             Classical Multi-Confluence System    |
//|                      (No Social-Media SMC/ICT Hype - Pure Math)  |
//+------------------------------------------------------------------+
#property copyright "Veteran Trader Institutional System"
#property link      "https://arena.ai"
#property version   "1.20"
#property strict
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_color1  clrLimeGreen      // Buy Signal Arrow
#property indicator_color2  clrCrimson        // Sell Signal Arrow
#property indicator_color3  clrDodgerBlue     // Fast EMA (20)
#property indicator_color4  clrDarkOrange     // Medium EMA (50)
#property indicator_color5  clrGold           // Slow EMA (200 - Baseline)
#property indicator_width1  3
#property indicator_width2  3
#property indicator_width3  1
#property indicator_width4  1
#property indicator_width5  2

//--- Indicator Buffers
double BuySignalBuffer[];
double SellSignalBuffer[];
double FastEMABuffer[];
double MedEMABuffer[];
double SlowEMABuffer[];

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//--- Trend Settings (Classical Dow Theory & Stage Analysis)
input string   Group_Trend          = "=== TREND & REGIME SETTINGS ===";
input int      InpEMAFast           = 20;          // Fast EMA (Tactical Momentum)
input int      InpEMAMedium         = 50;          // Medium EMA (Institutional Pullback)
input int      InpEMASlow           = 200;         // Slow EMA (Wall Street Baseline)
input bool     InpShowEMAs          = true;        // Show EMA Lines on Chart

//--- Anti-Chop & Range Suppression Filter
input string   Group_Chop           = "=== ANTI-CHOP & RANGE FILTER ===";
input bool     InpFilterChop        = true;        // Enable Anti-Chop Filter (Mute Range Signals)
input int      InpADXPeriod         = 14;          // ADX Trend Strength Period
input double   InpMinADX            = 22.0;        // Min ADX for Trending Market (>22 = Trend)
input bool     InpFilterHTF         = true;        // Require Higher Timeframe Confirmation (Elder Triple Screen)

//--- Clean Chart Signal Control (No Arrow Clutter)
input string   Group_SignalControl  = "=== CLEAN CHART SIGNAL CONTROL ===";
input bool     InpOneSignalPerTrend = true;        // Strict 1 Arrow per Trend Phase (No spam)
input int      InpSignalCooldown    = 15;          // Minimum Bars Between Arrows
input int      InpMaxHistoricalBars = 300;         // Max Historical Bars to Process

//--- Classical Floor Trader Pivots Settings
input string   Group_Pivots         = "=== FLOOR TRADER PIVOTS (D1) ===";
input bool     InpShowPivots        = true;        // Show Daily Floor Trader Pivots
input color    InpColorPivot        = clrSilver;   // Pivot Point (PP) Color
input color    InpColorR1           = clrOrangeRed;// Resistance 1 Color
input color    InpColorR2           = clrRed;      // Resistance 2 Color
input color    InpColorS1           = clrDeepSkyBlue; // Support 1 Color
input color    InpColorS2           = clrDodgerBlue;  // Support 2 Color

//--- Confluence & Momentum (Wilder & Larry Williams)
input string   Group_Momentum       = "=== MOMENTUM CONFLUENCE ===";
input int      InpRSIPeriod         = 14;          // RSI Period
input int      InpWilliamsPeriod    = 14;          // Larry Williams %R Period
input int      InpATRPeriod         = 14;          // ATR Period (Volatility)

//--- Risk Management (ATR Multiplier & Target Ratios)
input string   Group_Risk           = "=== RISK & TARGET MANAGEMENT ===";
input double   InpRiskPercent       = 1.0;         // Account Risk % for Lot Size Calc
input double   InpATRMorphSL        = 1.5;         // Stop Loss ATR Multiplier
input double   InpTP1_RR            = 1.5;         // Take Profit 1 Risk:Reward
input double   InpTP2_RR            = 2.5;         // Take Profit 2 Risk:Reward
input bool     InpShowTradeLines    = true;        // Show Visual Entry/SL/TP Lines

//--- Dashboard HUD Settings
input string   Group_Dashboard      = "=== INSTITUTIONAL DASHBOARD HUD ===";
input bool     InpShowDashboard     = true;        // Enable On-Chart Dashboard
input int      InpDashX             = 25;          // Dashboard X Position (Pixels)
input int      InpDashY             = 35;          // Dashboard Y Position (Pixels)
input int      InpFontSize          = 9;           // Base Font Size
input string   InpFontName          = "Segoe UI";  // Dashboard Font

//--- Alerts & Notifications
input string   Group_Alerts         = "=== ALERTS & NOTIFICATIONS ===";
input bool     InpPopupAlert        = true;        // Popup Alert on Chart
input bool     InpSoundAlert        = true;        // Sound Alert
input string   InpSoundFile         = "alert.wav"; // Alert Sound File
input bool     InpPushAlert         = true;        // Push Notification to MT4 Mobile
input bool     InpEmailAlert        = false;       // Send Email Alert

//+------------------------------------------------------------------+
//| GLOBAL CONSTANTS & VARIABLES                                     |
//+------------------------------------------------------------------+
#define PREFIX_DASH  "VTP_Dash_"
#define PREFIX_PIVOT "VTP_Piv_"
#define PREFIX_TRADE "VTP_Trd_"

datetime lastAlertTime = 0;
double   PipMultiplier = 0.0001;
int      PipDigits     = 4;

// Global trade structure for latest setup
struct TradeSetup
{
   int      signalType;       // 1 = BUY, -1 = SELL, 0 = NONE
   double   entryPrice;
   double   stopLoss;
   double   takeProfit1;
   double   takeProfit2;
   double   riskPips;
   double   recLotSize;
   double   confluence;
   datetime setupTime;
   string   marketRegime;
   bool     isChoppy;
   double   currentADX;
};

TradeSetup currentSetup;

// Forward Declarations
void CalculateAndDrawPivots();
void DrawTradeSetupLines();
void RenderDashboard();
void HandleAlerts(datetime currentBarTime);
string GetTimeframeString(int tf);
int  GetHigherTimeframe(int currentTf);
int  GetTimeframeTrend(int timeframe);
bool IsMarketChoppy(int shift, double &adxOut);
double CalculateLotSize(double slPips);
void CreateRectLabel(string name, int x, int y, int w, int h, color bgClr, color borderClr, int borderWidth);
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool isBold);
void CreateLine(string name, int x, int y, int w, color clr);
void DrawPivotLine(string objName, string desc, double price, color clr, int style, datetime tStart, datetime tEnd);
void DrawPriceLine(string name, string text, double price, color clr, int style, int width, datetime t1, datetime t2);

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Determine Pip Size based on Digits
   if(Digits == 3 || Digits == 5)
   {
      PipMultiplier = 10.0 * Point;
      PipDigits = (Digits == 5) ? 4 : 2;
   }
   else
   {
      PipMultiplier = Point;
      PipDigits = Digits;
   }

   // Set Buffers
   SetIndexBuffer(0, BuySignalBuffer);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 3, indicator_color1);
   SetIndexArrow(0, 233); // Bold Up Arrow (Wingdings 233)
   SetIndexLabel(0, "Veteran Prime Buy");

   SetIndexBuffer(1, SellSignalBuffer);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 3, indicator_color2);
   SetIndexArrow(1, 234); // Bold Down Arrow (Wingdings 234)
   SetIndexLabel(1, "Veteran Prime Sell");

   SetIndexBuffer(2, FastEMABuffer);
   SetIndexStyle(2, InpShowEMAs ? DRAW_LINE : DRAW_NONE, STYLE_SOLID, 1, indicator_color3);
   SetIndexLabel(2, "Fast EMA (" + IntegerToString(InpEMAFast) + ")");

   SetIndexBuffer(3, MedEMABuffer);
   SetIndexStyle(3, InpShowEMAs ? DRAW_LINE : DRAW_NONE, STYLE_SOLID, 1, indicator_color4);
   SetIndexLabel(3, "Medium EMA (" + IntegerToString(InpEMAMedium) + ")");

   SetIndexBuffer(4, SlowEMABuffer);
   SetIndexStyle(4, InpShowEMAs ? DRAW_LINE : DRAW_NONE, STYLE_SOLID, 2, indicator_color5);
   SetIndexLabel(4, "Slow EMA (" + IntegerToString(InpEMASlow) + ")");

   // Initialize current setup
   currentSetup.signalType = 0;
   currentSetup.entryPrice = 0;
   currentSetup.stopLoss = 0;
   currentSetup.takeProfit1 = 0;
   currentSetup.takeProfit2 = 0;
   currentSetup.riskPips = 0;
   currentSetup.recLotSize = 0.01;
   currentSetup.confluence = 0;
   currentSetup.setupTime = 0;
   currentSetup.marketRegime = "INITIALIZING...";
   currentSetup.isChoppy = false;
   currentSetup.currentADX = 0;

   // Indicator Short Name
   IndicatorShortName("Veteran Trader Pro [Clean Institutional System]");

   // Set top-left chart status
   Comment("★ Veteran Trader Pro Active | Clean Filter Mode ON | Symbol: ", Symbol(), " ★");

   // Render Dashboard and Pivots immediately on Init
   if(InpShowDashboard)
   {
      RenderDashboard();
   }
   CalculateAndDrawPivots();
   ChartRedraw(0);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIX_DASH);
   ObjectsDeleteAll(0, PREFIX_PIVOT);
   ObjectsDeleteAll(0, PREFIX_TRADE);
   Comment("");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Get Higher Timeframe for Triple Screen Confirmation              |
//+------------------------------------------------------------------+
int GetHigherTimeframe(int currentTf)
{
   switch(currentTf)
   {
      case PERIOD_M1:  return PERIOD_M15;
      case PERIOD_M5:  return PERIOD_H1;
      case PERIOD_M15: return PERIOD_H1;
      case PERIOD_M30: return PERIOD_H4;
      case PERIOD_H1:  return PERIOD_H4;
      case PERIOD_H4:  return PERIOD_D1;
      case PERIOD_D1:  return PERIOD_W1;
      default:         return PERIOD_D1;
   }
}

//+------------------------------------------------------------------+
//| Helper to calculate MTF EMA Trend                               |
//+------------------------------------------------------------------+
int GetTimeframeTrend(int timeframe)
{
   double ema20  = iMA(NULL, timeframe, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema50  = iMA(NULL, timeframe, InpEMAMedium, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema200 = iMA(NULL, timeframe, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE, 1);
   double close1 = iClose(NULL, timeframe, 1);

   if(ema20 <= 0 || ema50 <= 0 || ema200 <= 0 || close1 <= 0)
      return 0;

   // Bullish: Price > 200 EMA and 20 EMA > 50 EMA
   if(close1 > ema200 && ema20 > ema50 && close1 > ema50)
      return 1;
   // Bearish: Price < 200 EMA and 20 EMA < 50 EMA
   if(close1 < ema200 && ema20 < ema50 && close1 < ema50)
      return -1;

   return 0; // Range / Neutral
}

//+------------------------------------------------------------------+
//| Institutional Anti-Chop & Range Detector                         |
//+------------------------------------------------------------------+
bool IsMarketChoppy(int shift, double &adxOut)
{
   adxOut = iADX(NULL, 0, InpADXPeriod, PRICE_CLOSE, MODE_MAIN, shift);
   if(adxOut <= 0) adxOut = 25.0; // fallback

   if(!InpFilterChop) return false;

   // 1. ADX Threshold: If ADX is below threshold, market is strictly ranging/choppy
   if(adxOut < InpMinADX)
      return true;

   // 2. EMA Compression / Entanglement Check:
   double fastEMA = iMA(NULL, 0, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE, shift);
   double medEMA  = iMA(NULL, 0, InpEMAMedium, 0, MODE_EMA, PRICE_CLOSE, shift);
   double slowEMA = iMA(NULL, 0, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE, shift);

   double atr = iATR(NULL, 0, InpATRPeriod, shift);
   if(atr <= 0) atr = 10 * PipMultiplier;

   // If 20 EMA and 50 EMA are squeezed within 0.5x ATR, price is dead/chopping
   if(MathAbs(fastEMA - medEMA) < (atr * 0.4))
      return true;

   // If price is oscillating right through 200 EMA back and forth
   if(MathAbs(Close[shift] - slowEMA) < (atr * 0.3) && MathAbs(fastEMA - slowEMA) < (atr * 0.6))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Account Balance and SL Risk          |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   if(slPips <= 0) return 0.01;

   double balance = AccountBalance();
   if(balance <= 0) balance = 10000.0;

   double riskMoney = balance * (InpRiskPercent / 100.0);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);

   if(tickSize <= 0 || tickValue <= 0)
   {
      return NormalizeDouble((riskMoney / (slPips * 10.0)), 2);
   }

   double pipValuePerStandardLot = (tickValue / tickSize) * PipMultiplier;
   if(pipValuePerStandardLot <= 0) pipValuePerStandardLot = 10.0;

   double lots = riskMoney / (slPips * pipValuePerStandardLot);

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(minLot <= 0)  minLot = 0.01;
   if(maxLot <= 0)  maxLot = 100.0;
   if(lotStep <= 0) lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Calculate Floor Trader Pivots (Daily)                            |
//+------------------------------------------------------------------+
void CalculateAndDrawPivots()
{
   if(!InpShowPivots)
   {
      ObjectsDeleteAll(0, PREFIX_PIVOT);
      return;
   }

   double dHigh  = iHigh(NULL, PERIOD_D1, 1);
   double dLow   = iLow(NULL, PERIOD_D1, 1);
   double dClose = iClose(NULL, PERIOD_D1, 1);

   if(dHigh <= 0 || dLow <= 0 || dClose <= 0)
   {
      dHigh  = High[iHighest(NULL, 0, MODE_HIGH, MathMin(Bars - 1, 24), 1)];
      dLow   = Low[iLowest(NULL, 0, MODE_LOW, MathMin(Bars - 1, 24), 1)];
      dClose = Close[1];
   }

   if(dHigh <= 0 || dLow <= 0 || dClose <= 0) return;

   double pp = (dHigh + dLow + dClose) / 3.0;
   double r1 = (2.0 * pp) - dLow;
   double s1 = (2.0 * pp) - dHigh;
   double r2 = pp + (dHigh - dLow);
   double s2 = pp - (dHigh - dLow);

   datetime todayStart = Time[MathMin(Bars - 1, 50)];
   datetime todayEnd   = Time[0] + (Period() * 60 * 30);

   DrawPivotLine(PREFIX_PIVOT + "PP",  "Daily Pivot (PP)", pp, InpColorPivot, STYLE_SOLID, todayStart, todayEnd);
   DrawPivotLine(PREFIX_PIVOT + "R1",  "Resistance 1 (R1)", r1, InpColorR1, STYLE_DASH, todayStart, todayEnd);
   DrawPivotLine(PREFIX_PIVOT + "R2",  "Resistance 2 (R2)", r2, InpColorR2, STYLE_DASH, todayStart, todayEnd);
   DrawPivotLine(PREFIX_PIVOT + "S1",  "Support 1 (S1)", s1, InpColorS1, STYLE_DASH, todayStart, todayEnd);
   DrawPivotLine(PREFIX_PIVOT + "S2",  "Support 2 (S2)", s2, InpColorS2, STYLE_DASH, todayStart, todayEnd);
}

//+------------------------------------------------------------------+
//| Draw a single Pivot Line with label                              |
//+------------------------------------------------------------------+
void DrawPivotLine(string objName, string desc, double price, color clr, int style, datetime tStart, datetime tEnd)
{
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_TREND, 0, tStart, price, tEnd, price);
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, objName, OBJPROP_STYLE, style);
      ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, objName, OBJPROP_TEXT, desc + ": " + DoubleToString(price, Digits));
   }
   else
   {
      ObjectSetDouble(0, objName, OBJPROP_PRICE1, price);
      ObjectSetDouble(0, objName, OBJPROP_PRICE2, price);
      ObjectSetInteger(0, objName, OBJPROP_TIME1, tStart);
      ObjectSetInteger(0, objName, OBJPROP_TIME2, tEnd);
      ObjectSetString(0, objName, OBJPROP_TEXT, desc + ": " + DoubleToString(price, Digits));
   }
}

//+------------------------------------------------------------------+
//| Draw visual Entry / Stop Loss / Take Profit Lines                |
//+------------------------------------------------------------------+
void DrawTradeSetupLines()
{
   if(!InpShowTradeLines || currentSetup.signalType == 0)
   {
      ObjectsDeleteAll(0, PREFIX_TRADE);
      return;
   }

   datetime tStart = currentSetup.setupTime > 0 ? currentSetup.setupTime : Time[0];
   datetime tEnd   = Time[0] + (Period() * 60 * 30);

   color entryClr = (currentSetup.signalType == 1) ? clrLimeGreen : clrCrimson;
   string dirText = (currentSetup.signalType == 1) ? "BUY" : "SELL";

   // Entry Line
   DrawPriceLine(PREFIX_TRADE + "Entry", "ENTRY [" + dirText + "]: " + DoubleToString(currentSetup.entryPrice, Digits),
                 currentSetup.entryPrice, entryClr, STYLE_SOLID, 2, tStart, tEnd);

   // Stop Loss Line
   DrawPriceLine(PREFIX_TRADE + "SL", "STOP LOSS: " + DoubleToString(currentSetup.stopLoss, Digits) + " (" + DoubleToString(currentSetup.riskPips, 1) + " pips)",
                 currentSetup.stopLoss, clrRed, STYLE_DASH, 1, tStart, tEnd);

   // TP1 Line
   double tp1Pips = MathAbs(currentSetup.takeProfit1 - currentSetup.entryPrice) / PipMultiplier;
   DrawPriceLine(PREFIX_TRADE + "TP1", "TARGET 1 (1:1.5): " + DoubleToString(currentSetup.takeProfit1, Digits) + " (+" + DoubleToString(tp1Pips, 1) + " pips)",
                 currentSetup.takeProfit1, clrMediumSeaGreen, STYLE_DASHDOT, 1, tStart, tEnd);

   // TP2 Line
   double tp2Pips = MathAbs(currentSetup.takeProfit2 - currentSetup.entryPrice) / PipMultiplier;
   DrawPriceLine(PREFIX_TRADE + "TP2", "TARGET 2 (1:2.5): " + DoubleToString(currentSetup.takeProfit2, Digits) + " (+" + DoubleToString(tp2Pips, 1) + " pips)",
                 currentSetup.takeProfit2, clrDeepSkyBlue, STYLE_SOLID, 1, tStart, tEnd);
}

//+------------------------------------------------------------------+
//| Helper: Draw Price Line                                          |
//+------------------------------------------------------------------+
void DrawPriceLine(string name, string text, double price, color clr, int style, int width, datetime t1, datetime t2)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE1, price);
      ObjectSetDouble(0, name, OBJPROP_PRICE2, price);
      ObjectSetInteger(0, name, OBJPROP_TIME1, t1);
      ObjectSetInteger(0, name, OBJPROP_TIME2, t2);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
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
   int counted_bars = prev_calculated;
   if(rates_total < 30) return(0);

   int limit = rates_total - counted_bars;
   if(counted_bars > 0) limit++;
   if(limit > rates_total - 1) limit = rates_total - 1;

   // 1. Calculate EMAs and Clear Buffer points
   for(int i = limit; i >= 0; i--)
   {
      FastEMABuffer[i] = iMA(NULL, 0, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE, i);
      MedEMABuffer[i]  = iMA(NULL, 0, InpEMAMedium, 0, MODE_EMA, PRICE_CLOSE, i);
      SlowEMABuffer[i] = iMA(NULL, 0, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE, i);
      BuySignalBuffer[i] = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
   }

   // Higher Timeframe check
   int htf = GetHigherTimeframe(Period());
   int htfTrend = InpFilterHTF ? GetTimeframeTrend(htf) : 0;

   // Scan for Clean, Non-Repainting Signals
   int scanLimit = MathMin(rates_total - 1, InpMaxHistoricalBars);
   
   int lastSignalBar = 9999;
   int lastSignalDir = 0; // 1 = BUY, -1 = SELL

   // Scan chronologically backwards (from oldest bar to newest bar 1) to apply signal cooldown
   for(int i = scanLimit; i >= 1; i--)
   {
      double fastEMA = FastEMABuffer[i];
      double medEMA  = MedEMABuffer[i];
      double slowEMA = SlowEMABuffer[i];

      double rsi     = iRSI(NULL, 0, InpRSIPeriod, PRICE_CLOSE, i);
      double prevRSI = iRSI(NULL, 0, InpRSIPeriod, PRICE_CLOSE, i + 1);

      double wpr     = iWPR(NULL, 0, InpWilliamsPeriod, i);
      double prevWPR = iWPR(NULL, 0, InpWilliamsPeriod, i + 1);

      double atr     = iATR(NULL, 0, InpATRPeriod, i);
      if(atr <= 0) atr = 10 * PipMultiplier;

      double cVal = Close[i];
      double oVal = Open[i];
      double hVal = High[i];
      double lVal = Low[i];
      double prevH = High[i+1];
      double prevL = Low[i+1];

      // Chop & Consolidation Check
      double adxVal = 0;
      bool isChop = IsMarketChoppy(i, adxVal);

      // Record live status for Bar 1
      if(i == 1)
      {
         currentSetup.isChoppy = isChop;
         currentSetup.currentADX = adxVal;
      }

      // If Market is in Chop/Range, SUPPRESS ALL SIGNALS!
      if(isChop && InpFilterChop)
         continue;

      // Classical Stage Analysis Trend
      bool isBullishRegime = (cVal > slowEMA && fastEMA > medEMA && cVal > medEMA);
      bool isBearishRegime = (cVal < slowEMA && fastEMA < medEMA && cVal < medEMA);

      // Apply HTF filter if enabled
      if(InpFilterHTF && htfTrend != 0)
      {
         if(htfTrend == -1) isBullishRegime = false; // HTF is bearish, no Buy
         if(htfTrend == 1)  isBearishRegime = false; // HTF is bullish, no Sell
      }

      // High-Precision Pullback Trigger (Value Zone Rejection)
      bool buyRaw = isBullishRegime &&
                    (lVal <= fastEMA || prevL <= fastEMA || lVal <= medEMA) &&
                    (cVal > oVal) &&
                    (cVal > prevH || (rsi > 50 && prevRSI <= 50) || (wpr > -50 && prevWPR <= -50));

      bool sellRaw = isBearishRegime &&
                     (hVal >= fastEMA || prevH >= fastEMA || hVal >= medEMA) &&
                     (cVal < oVal) &&
                     (cVal < prevL || (rsi < 50 && prevRSI >= 50) || (wpr < -50 && prevWPR >= -50));

      // Cooldown and Anti-Spam (Only 1 clean arrow per move)
      int barsSinceLastSignal = MathAbs(lastSignalBar - i);

      bool allowBuy = buyRaw && (!InpOneSignalPerTrend || lastSignalDir != 1 || barsSinceLastSignal >= InpSignalCooldown);
      bool allowSell = sellRaw && (!InpOneSignalPerTrend || lastSignalDir != -1 || barsSinceLastSignal >= InpSignalCooldown);

      if(allowBuy && !sellRaw)
      {
         BuySignalBuffer[i] = lVal - (atr * 0.4);
         lastSignalBar = i;
         lastSignalDir = 1;

         if(i == 1)
         {
            currentSetup.signalType = 1;
            currentSetup.entryPrice = Close[1];
            double slDistance = MathMax((Close[1] - Low[1]) + (atr * InpATRMorphSL), atr * 1.2);
            currentSetup.stopLoss = Close[1] - slDistance;
            currentSetup.riskPips = slDistance / PipMultiplier;
            currentSetup.recLotSize = CalculateLotSize(currentSetup.riskPips);
            currentSetup.takeProfit1 = Close[1] + (slDistance * InpTP1_RR);
            currentSetup.takeProfit2 = Close[1] + (slDistance * InpTP2_RR);
            currentSetup.setupTime = Time[1];
            currentSetup.marketRegime = "STAGE 2: BULLISH EXPANSION";
         }
      }
      else if(allowSell && !buyRaw)
      {
         SellSignalBuffer[i] = hVal + (atr * 0.4);
         lastSignalBar = i;
         lastSignalDir = -1;

         if(i == 1)
         {
            currentSetup.signalType = -1;
            currentSetup.entryPrice = Close[1];
            double slDistance = MathMax((High[1] - Close[1]) + (atr * InpATRMorphSL), atr * 1.2);
            currentSetup.stopLoss = Close[1] + slDistance;
            currentSetup.riskPips = slDistance / PipMultiplier;
            currentSetup.recLotSize = CalculateLotSize(currentSetup.riskPips);
            currentSetup.takeProfit1 = Close[1] - (slDistance * InpTP1_RR);
            currentSetup.takeProfit2 = Close[1] - (slDistance * InpTP2_RR);
            currentSetup.setupTime = Time[1];
            currentSetup.marketRegime = "STAGE 4: BEARISH DISTRIBUTION";
         }
      }
   }

   // Update Regime Status if Choppy
   if(currentSetup.isChoppy)
   {
      currentSetup.marketRegime = "CONSOLIDATION / RANGE (CHOP)";
   }

   // 3. Render Visual Components
   CalculateAndDrawPivots();
   DrawTradeSetupLines();

   // 4. Alerts Trigger
   HandleAlerts(Time[0]);

   // 5. Render Executive Dashboard
   if(InpShowDashboard)
   {
      RenderDashboard();
   }

   ChartRedraw(0);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Trigger Audio, Pop-up, Mobile & Email Alerts                     |
//+------------------------------------------------------------------+
void HandleAlerts(datetime currentBarTime)
{
   if(currentBarTime == lastAlertTime) return;

   if(BuySignalBuffer[1] != EMPTY_VALUE && BuySignalBuffer[1] > 0)
   {
      lastAlertTime = currentBarTime;
      string msg = StringFormat("[VETERAN TRADER PRO] 🟢 PRIME BUY SIGNAL\nSymbol: %s | Timeframe: %s\nEntry: %s | SL: %s (%0.1f pips)\nTP1: %s | TP2: %s\nRec Lot: %0.2f (at %0.1f%% risk)\nRule: Check High-Impact News Before Entry!",
                                Symbol(), GetTimeframeString(Period()),
                                DoubleToString(currentSetup.entryPrice, Digits),
                                DoubleToString(currentSetup.stopLoss, Digits), currentSetup.riskPips,
                                DoubleToString(currentSetup.takeProfit1, Digits),
                                DoubleToString(currentSetup.takeProfit2, Digits),
                                currentSetup.recLotSize, InpRiskPercent);

      if(InpPopupAlert) Alert(msg);
      if(InpSoundAlert) PlaySound(InpSoundFile);
      if(InpPushAlert)  SendNotification(msg);
      if(InpEmailAlert) SendMail("Veteran Trader Alert - BUY " + Symbol(), msg);
   }
   else if(SellSignalBuffer[1] != EMPTY_VALUE && SellSignalBuffer[1] > 0)
   {
      lastAlertTime = currentBarTime;
      string msg = StringFormat("[VETERAN TRADER PRO] 🔴 PRIME SELL SIGNAL\nSymbol: %s | Timeframe: %s\nEntry: %s | SL: %s (%0.1f pips)\nTP1: %s | TP2: %s\nRec Lot: %0.2f (at %0.1f%% risk)\nRule: Check High-Impact News Before Entry!",
                                Symbol(), GetTimeframeString(Period()),
                                DoubleToString(currentSetup.entryPrice, Digits),
                                DoubleToString(currentSetup.stopLoss, Digits), currentSetup.riskPips,
                                DoubleToString(currentSetup.takeProfit1, Digits),
                                DoubleToString(currentSetup.takeProfit2, Digits),
                                currentSetup.recLotSize, InpRiskPercent);

      if(InpPopupAlert) Alert(msg);
      if(InpSoundAlert) PlaySound(InpSoundFile);
      if(InpPushAlert)  SendNotification(msg);
      if(InpEmailAlert) SendMail("Veteran Trader Alert - SELL " + Symbol(), msg);
   }
}

//+------------------------------------------------------------------+
//| Timeframe String Helper                                          |
//+------------------------------------------------------------------+
string GetTimeframeString(int tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return IntegerToString(tf);
   }
}

//+------------------------------------------------------------------+
//| Render Institutional Bloomberg-Style Dashboard                   |
//+------------------------------------------------------------------+
void RenderDashboard()
{
   int x = InpDashX;
   int y = InpDashY;
   int width = 325;
   int rowH = 18;
   int totalRows = 19;
   int height = (totalRows * rowH) + 25;

   color bgClr     = C'18,22,28';
   color borderClr = C'45,62,80';
   color headerClr = C'240,185,11'; // Gold
   color textClr   = C'220,225,230';
   color subClr    = C'130,145,160';
   color greenClr  = C'0,230,118';
   color redClr    = C'255,82,82';
   color yellowClr = C'255,193,7';  // Orange-Yellow

   // Main Panel Background
   CreateRectLabel(PREFIX_DASH + "BG", x, y, width, height, bgClr, borderClr, 2);

   // Header
   CreateLabel(PREFIX_DASH + "H1", x + 12, y + 8, "★ VETERAN TRADER PRO (CLEAN ENGINE)", headerClr, InpFontSize + 1, true);
   CreateLabel(PREFIX_DASH + "H2", x + 12, y + 26, "Wall Street Anti-Chop Confluence (No SMC/ICT)", subClr, InpFontSize - 2, false);

   // Divider 1
   CreateLine(PREFIX_DASH + "Div1", x + 10, y + 42, width - 20, borderClr);

   // Asset & Volatility Info
   double currentSpread = (double)MarketInfo(Symbol(), MODE_SPREAD);
   if(Digits == 3 || Digits == 5) currentSpread = currentSpread / 10.0;
   string assetInfo = StringFormat("Asset: %s (%s)  |  Spread: %0.1f pips", Symbol(), GetTimeframeString(Period()), currentSpread);
   CreateLabel(PREFIX_DASH + "Asset", x + 12, y + 48, assetInfo, textClr, InpFontSize - 1, false);

   // Multi-Timeframe Alignment
   int trendM15 = GetTimeframeTrend(PERIOD_M15);
   int trendH1  = GetTimeframeTrend(PERIOD_H1);
   int trendH4  = GetTimeframeTrend(PERIOD_H4);
   int trendD1  = GetTimeframeTrend(PERIOD_D1);

   string iconM15 = (trendM15 == 1) ? "[▲ M15]" : (trendM15 == -1) ? "[▼ M15]" : "[— M15]";
   string iconH1  = (trendH1 == 1)  ? "[▲ H1]"  : (trendH1 == -1)  ? "[▼ H1]"  : "[— H1]";
   string iconH4  = (trendH4 == 1)  ? "[▲ H4]"  : (trendH4 == -1)  ? "[▼ H4]"  : "[— H4]";
   string iconD1  = (trendD1 == 1)  ? "[▲ D1]"  : (trendD1 == -1)  ? "[▼ D1]"  : "[— D1]";

   int score = 0;
   if(trendM15 == 1) score += 25; else if(trendM15 == -1) score -= 25;
   if(trendH1 == 1)  score += 25; else if(trendH1 == -1) score -= 25;
   if(trendH4 == 1)  score += 25; else if(trendH4 == -1) score -= 25;
   if(trendD1 == 1)  score += 25; else if(trendD1 == -1) score -= 25;

   color mtfClr = (score >= 50) ? greenClr : (score <= -50) ? redClr : yellowClr;

   CreateLabel(PREFIX_DASH + "MTF_Label", x + 12, y + 68, "MTF Flow:", subClr, InpFontSize - 1, false);
   CreateLabel(PREFIX_DASH + "MTF_Icons", x + 85, y + 68, StringFormat("%s  %s  %s  %s", iconM15, iconH1, iconH4, iconD1), mtfClr, InpFontSize - 1, true);

   // Market Regime & ADX Chop Status
   string chopStatusStr = currentSetup.isChoppy ? "🚫 CHOP / RANGE (MUTED)" : "✅ ACTIVE TRENDING";
   color chopStatusClr  = currentSetup.isChoppy ? yellowClr : greenClr;
   string adxText = StringFormat("ADX: %0.1f  |  Regime: %s", currentSetup.currentADX, chopStatusStr);
   CreateLabel(PREFIX_DASH + "ADX_Label", x + 12, y + 88, "Market State:", subClr, InpFontSize - 1, false);
   CreateLabel(PREFIX_DASH + "ADX_Val",   x + 92, y + 88, adxText, chopStatusClr, InpFontSize - 1, true);

   // Confluence Score
   string scoreText = (score > 0) ? StringFormat("+%d%% (BULLISH CONFLUENCE)", score) : (score < 0) ? StringFormat("%d%% (BEARISH CONFLUENCE)", score) : "0% (CHOP / NEUTRAL)";
   CreateLabel(PREFIX_DASH + "Conf_Label", x + 12, y + 108, "Score:", subClr, InpFontSize - 1, false);
   CreateLabel(PREFIX_DASH + "Conf_Val",   x + 85, y + 108, scoreText, mtfClr, InpFontSize - 1, true);

   // Divider 2
   CreateLine(PREFIX_DASH + "Div2", x + 10, y + 128, width - 20, borderClr);

   // Tactical Trade Action Box
   string actionText = "WAIT / LOOKING FOR SETUP";
   color actionClr   = clrDarkGray;

   if(currentSetup.isChoppy)
   {
      actionText = "⚠️ MARKET IN RANGE — DO NOT TRADE";
      actionClr  = yellowClr;
   }
   else if(currentSetup.signalType == 1)
   {
      actionText = "★ PRIME BUY ENTRY ACTIVE ★";
      actionClr  = greenClr;
   }
   else if(currentSetup.signalType == -1)
   {
      actionText = "★ PRIME SELL ENTRY ACTIVE ★";
      actionClr  = redClr;
   }

   CreateLabel(PREFIX_DASH + "Act_Title", x + 12, y + 135, "INSTITUTIONAL ACTION:", headerClr, InpFontSize - 1, true);
   CreateLabel(PREFIX_DASH + "Act_Val",   x + 12, y + 153, actionText, actionClr, InpFontSize + 1, true);

   // Trade Parameters (Entry, SL, TP1, TP2, Lot Size)
   if(currentSetup.signalType != 0 && !currentSetup.isChoppy)
   {
      CreateLabel(PREFIX_DASH + "Trd_Entry", x + 12, y + 175, StringFormat("Entry: %s", DoubleToString(currentSetup.entryPrice, Digits)), textClr, InpFontSize - 1, true);
      CreateLabel(PREFIX_DASH + "Trd_SL",    x + 12, y + 193, StringFormat("Stop Loss: %s  (%0.1f pips)", DoubleToString(currentSetup.stopLoss, Digits), currentSetup.riskPips), redClr, InpFontSize - 1, true);
      CreateLabel(PREFIX_DASH + "Trd_TP1",   x + 12, y + 211, StringFormat("Target TP1 (1:1.5): %s", DoubleToString(currentSetup.takeProfit1, Digits)), greenClr, InpFontSize - 1, true);
      CreateLabel(PREFIX_DASH + "Trd_TP2",   x + 12, y + 229, StringFormat("Target TP2 (1:2.5): %s", DoubleToString(currentSetup.takeProfit2, Digits)), greenClr, InpFontSize - 1, true);
      CreateLabel(PREFIX_DASH + "Trd_Lot",   x + 12, y + 247, StringFormat("Calculated Lot (%0.1f%% Risk): %0.2f Lots", InpRiskPercent, currentSetup.recLotSize), headerClr, InpFontSize - 1, true);
   }
   else
   {
      string rangeSub = currentSetup.isChoppy ? "Suppressed: Waiting for Range Breakout..." : "Waiting for 20/50 EMA Pullback...";
      CreateLabel(PREFIX_DASH + "Trd_Entry", x + 12, y + 175, "Entry: " + rangeSub, subClr, InpFontSize - 1, false);
      CreateLabel(PREFIX_DASH + "Trd_SL",    x + 12, y + 193, "Stop Loss: Dynamic ATR Floor", subClr, InpFontSize - 1, false);
      CreateLabel(PREFIX_DASH + "Trd_TP1",   x + 12, y + 211, "Target TP1: Minimum 1:1.5 RR", subClr, InpFontSize - 1, false);
      CreateLabel(PREFIX_DASH + "Trd_TP2",   x + 12, y + 229, "Target TP2: Expansion 1:2.5 RR", subClr, InpFontSize - 1, false);
      CreateLabel(PREFIX_DASH + "Trd_Lot",   x + 12, y + 247, StringFormat("Lot Size: Auto-calculated at %0.1f%% risk", InpRiskPercent), subClr, InpFontSize - 1, false);
   }

   // Divider 3
   CreateLine(PREFIX_DASH + "Div3", x + 10, y + 268, width - 20, borderClr);

   // Institutional Rules
   CreateLabel(PREFIX_DASH + "Rule1", x + 12, y + 274, "⚠️ 1. NEVER TRADE 15 MIN AROUND HIGH-IMPACT NEWS", clrOrange, InpFontSize - 2, true);
   CreateLabel(PREFIX_DASH + "Rule2", x + 12, y + 290, "🛡️ 2. Max 1% Risk per Trade | 1 Arrow per Trend Leg", subClr, InpFontSize - 2, false);
   CreateLabel(PREFIX_DASH + "Rule3", x + 12, y + 306, "🎯 3. Lock 50% Profit at TP1 & Move SL to Breakeven", subClr, InpFontSize - 2, false);
}

//+------------------------------------------------------------------+
//| UI Helper: Create Rectangle Label                                |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int w, int h, color bgClr, color borderClr, int borderWidth)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderClr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, borderWidth);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   }
}

//+------------------------------------------------------------------+
//| UI Helper: Create Text Label                                     |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize, bool isBold)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, InpFontName);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   else
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   }
}

//+------------------------------------------------------------------+
//| UI Helper: Create Horizontal Line inside HUD                     |
//+------------------------------------------------------------------+
void CreateLine(string name, int x, int y, int w, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 1);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   }
}
//+------------------------------------------------------------------+
