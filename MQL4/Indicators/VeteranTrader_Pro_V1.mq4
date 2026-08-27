//+------------------------------------------------------------------+
//|                                        VeteranTrader_Pro_V1.mq4  |
//|                       Veteran 30-Year Wall Street Trading Engine |
//|                             Classical Multi-Confluence System    |
//|                      (No Social-Media SMC/ICT Hype - Pure Math)  |
//+------------------------------------------------------------------+
#property copyright "Veteran Trader Institutional System"
#property link      "https://arena.ai"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_color1  clrLimeGreen      // Buy Signal Arrow
#property indicator_color2  clrCrimson        // Sell Signal Arrow
#property indicator_color3  clrDodgerBlue     // Fast EMA (20)
#property indicator_color4  clrDarkOrange     // Medium EMA (50)
#property indicator_color5  clrGold           // Slow EMA (200 - Baseline)

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
input string   Group_Trend        = "=== TREND & REGIME SETTINGS ===";
input int      InpEMAFast         = 20;          // Fast EMA (Tactical Momentum)
input int      InpEMAMedium       = 50;          // Medium EMA (Institutional Pullback)
input int      InpEMASlow         = 200;         // Slow EMA (Wall Street Baseline)
input bool     InpShowEMAs        = true;        // Show EMA Lines on Chart

//--- Classical Floor Trader Pivots Settings
input string   Group_Pivots       = "=== FLOOR TRADER PIVOTS (D1) ===";
input bool     InpShowPivots      = true;        // Show Daily Floor Trader Pivots
input color    InpColorPivot      = clrSilver;   // Pivot Point (PP) Color
input color    InpColorR1         = clrOrangeRed;// Resistance 1 Color
input color    InpColorR2         = clrRed;      // Resistance 2 Color
input color    InpColorS1         = clrDeepSkyBlue; // Support 1 Color
input color    InpColorS2         = clrDodgerBlue;  // Support 2 Color

//--- Confluence & Momentum (Wilder & Larry Williams)
input string   Group_Momentum     = "=== MOMENTUM CONFLUENCE ===";
input int      InpRSIPeriod       = 14;          // RSI Period
input int      InpWilliamsPeriod  = 14;          // Larry Williams %R Period
input int      InpATRPeriod       = 14;          // ATR Period (Volatility)

//--- Risk Management (ATR Multiplier & Target Ratios)
input string   Group_Risk         = "=== RISK & TARGET MANAGEMENT ===";
input double   InpRiskPercent     = 1.0;         // Account Risk % for Lot Size Calc
input double   InpATRMorphSL      = 1.5;         // Stop Loss ATR Multiplier
input double   InpTP1_RR          = 1.5;         // Take Profit 1 Risk:Reward
input double   InpTP2_RR          = 2.5;         // Take Profit 2 Risk:Reward
input bool     InpShowTradeLines  = true;        // Show Visual Entry/SL/TP Lines

//--- Dashboard HUD Settings
input string   Group_Dashboard    = "=== INSTITUTIONAL DASHBOARD HUD ===";
input bool     InpShowDashboard   = true;        // Enable On-Chart Dashboard
input int      InpDashX           = 20;          // Dashboard X Position (Pixels)
input int      InpDashY           = 30;          // Dashboard Y Position (Pixels)
input int      InpFontSize        = 9;           // Base Font Size
input string   InpFontName        = "Segoe UI";  // Dashboard Font

//--- Alerts & Notifications
input string   Group_Alerts       = "=== ALERTS & NOTIFICATIONS ===";
input bool     InpPopupAlert      = true;        // Popup Alert on Chart
input bool     InpSoundAlert      = true;        // Sound Alert
input string   InpSoundFile       = "alert.wav"; // Alert Sound File
input bool     InpPushAlert       = true;        // Push Notification to MT4 Mobile
input bool     InpEmailAlert      = false;       // Send Email Alert

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
};

TradeSetup currentSetup;

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
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 2, indicator_color1);
   SetIndexArrow(0, 233); // Up arrow (Wingdings 233)
   SetIndexLabel(0, "Veteran Buy Signal");

   SetIndexBuffer(1, SellSignalBuffer);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 2, indicator_color2);
   SetIndexArrow(1, 234); // Down arrow (Wingdings 234)
   SetIndexLabel(1, "Veteran Sell Signal");

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

   // Indicator Short Name
   IndicatorShortName("Veteran Trader Pro [30-Yr Institutional System]");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up all chart objects created by this indicator
   ObjectsDeleteAll(0, PREFIX_DASH);
   ObjectsDeleteAll(0, PREFIX_PIVOT);
   ObjectsDeleteAll(0, PREFIX_TRADE);
   ChartRedraw(0);
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

   // Strong Bullish: Price > 200 EMA and 20 EMA > 50 EMA and Close > 50 EMA
   if(close1 > ema200 && ema20 > ema50 && close1 > ema50)
      return 1;
   // Strong Bearish: Price < 200 EMA and 20 EMA < 50 EMA and Close < 50 EMA
   if(close1 < ema200 && ema20 < ema50 && close1 < ema50)
      return -1;

   return 0; // Neutral / Transition / Range
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Account Balance and SL Risk          |
//+------------------------------------------------------------------+
double CalculateLotSize(double slPips)
{
   if(slPips <= 0) return 0.01;

   double balance = AccountBalance();
   if(balance <= 0) balance = 10000.0; // fallback preview

   double riskMoney = balance * (InpRiskPercent / 100.0);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double pointVal  = Point;

   if(tickSize <= 0 || tickValue <= 0) return 0.01;

   double pipValuePerStandardLot = (tickValue / tickSize) * PipMultiplier;
   if(pipValuePerStandardLot <= 0) pipValuePerStandardLot = 10.0; // default for 1 standard lot on USD

   double lots = riskMoney / (slPips * pipValuePerStandardLot);

   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(minLot <= 0)  minLot = 0.01;
   if(maxLot <= 0)  maxLot = 100.0;
   if(lotStep <= 0) lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   return lots;
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

   // Get previous day's High, Low, Close
   double dHigh  = iHigh(NULL, PERIOD_D1, 1);
   double dLow   = iLow(NULL, PERIOD_D1, 1);
   double dClose = iClose(NULL, PERIOD_D1, 1);

   if(dHigh <= 0 || dLow <= 0 || dClose <= 0) return;

   // Classical Floor Trader Pivot Formula
   double pp = (dHigh + dLow + dClose) / 3.0;
   double r1 = (2.0 * pp) - dLow;
   double s1 = (2.0 * pp) - dHigh;
   double r2 = pp + (dHigh - dLow);
   double s2 = pp - (dHigh - dLow);

   // Draw or Update Pivot Lines for today
   datetime todayStart = iTime(NULL, PERIOD_D1, 0);
   datetime todayEnd   = todayStart + 86400; // 24 hours

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
      ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
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

   datetime tStart = currentSetup.setupTime;
   datetime tEnd   = TimeCurrent() + (Period() * 60 * 30); // 30 candles into future

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
   if(rates_total < InpEMASlow + 50)
      return(0);

   int limit = rates_total - prev_calculated;
   if(prev_calculated > 0)
      limit++;

   // Calculate EMAs and Signal Buffers
   for(int i = limit; i >= 0; i--)
   {
      FastEMABuffer[i] = iMA(NULL, 0, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE, i);
      MedEMABuffer[i]  = iMA(NULL, 0, InpEMAMedium, 0, MODE_EMA, PRICE_CLOSE, i);
      SlowEMABuffer[i] = iMA(NULL, 0, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE, i);
      BuySignalBuffer[i] = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
   }

   // Signal Detection Loop (Historical and Live on completed bars)
   for(int i = limit; i >= 1; i--)
   {
      double fastEMA   = FastEMABuffer[i];
      double medEMA    = MedEMABuffer[i];
      double slowEMA   = SlowEMABuffer[i];

      double prevFast  = FastEMABuffer[i + 1];
      double prevMed   = MedEMABuffer[i + 1];

      double rsi       = iRSI(NULL, 0, InpRSIPeriod, PRICE_CLOSE, i);
      double prevRSI   = iRSI(NULL, 0, InpRSIPeriod, PRICE_CLOSE, i + 1);

      double wpr       = iWPR(NULL, 0, InpWilliamsPeriod, i);
      double prevWPR   = iWPR(NULL, 0, InpWilliamsPeriod, i + 1);

      double atr       = iATR(NULL, 0, InpATRPeriod, i);

      // Classical Stage Analysis / Dow Trend Condition:
      bool isBullishRegime = (close[i] > slowEMA && fastEMA > medEMA);
      bool isBearishRegime = (close[i] < slowEMA && fastEMA < medEMA);

      // Classical High-Probability Pullback & Momentum Trigger:
      // Bullish:
      // 1. Regime is Bullish (Price above 200 EMA, Fast > Medium)
      // 2. Bar touched or pulled back near 20/50 EMA (Low[i] <= fastEMA * 1.0015 or Low[i+1] <= medEMA)
      // 3. Momentum confirmation: Close[i] > Open[i] (bullish candle) and RSI crosses above 50 or recovers from oversold
      // 4. Williams %R recovers from oversold (< -50 crossing up)
      bool buyCondition = isBullishRegime &&
                          (low[i] <= fastEMA || low[i+1] <= fastEMA || low[i] <= medEMA) &&
                          (close[i] > open[i]) &&
                          (close[i] > high[i+1] || (rsi > 50 && prevRSI <= 50) || (wpr > -50 && prevWPR <= -50));

      // Bearish:
      // 1. Regime is Bearish (Price below 200 EMA, Fast < Medium)
      // 2. Bar touched or pulled back near 20/50 EMA (High[i] >= fastEMA * 0.9985 or High[i+1] >= medEMA)
      // 3. Momentum confirmation: Close[i] < Open[i] (bearish candle) and RSI crosses below 50
      // 4. Williams %R falls from overbought (> -50 crossing down)
      bool sellCondition = isBearishRegime &&
                           (high[i] >= fastEMA || high[i+1] >= fastEMA || high[i] >= medEMA) &&
                           (close[i] < open[i]) &&
                           (close[i] < low[i+1] || (rsi < 50 && prevRSI >= 50) || (wpr < -50 && prevWPR >= -50));

      if(buyCondition && !sellCondition)
      {
         BuySignalBuffer[i] = low[i] - (atr * 0.5);
         // If this is the most recent closed bar (i == 1)
         if(i == 1)
         {
            currentSetup.signalType = 1;
            currentSetup.entryPrice = close[1];
            // Stop loss placed below signal candle low - ATR buffer
            double slDistance = MathMax((close[1] - low[1]) + (atr * InpATRMorphSL), atr * 1.2);
            currentSetup.stopLoss = close[1] - slDistance;
            currentSetup.riskPips = slDistance / PipMultiplier;
            currentSetup.recLotSize = CalculateLotSize(currentSetup.riskPips);
            currentSetup.takeProfit1 = close[1] + (slDistance * InpTP1_RR);
            currentSetup.takeProfit2 = close[1] + (slDistance * InpTP2_RR);
            currentSetup.setupTime = time[1];
            currentSetup.marketRegime = "STAGE 2: INSTITUTIONAL BULLISH EXPANSION";
         }
      }
      else if(sellCondition && !buyCondition)
      {
         SellSignalBuffer[i] = high[i] + (atr * 0.5);
         // If this is the most recent closed bar (i == 1)
         if(i == 1)
         {
            currentSetup.signalType = -1;
            currentSetup.entryPrice = close[1];
            // Stop loss placed above signal candle high + ATR buffer
            double slDistance = MathMax((high[1] - close[1]) + (atr * InpATRMorphSL), atr * 1.2);
            currentSetup.stopLoss = close[1] + slDistance;
            currentSetup.riskPips = slDistance / PipMultiplier;
            currentSetup.recLotSize = CalculateLotSize(currentSetup.riskPips);
            currentSetup.takeProfit1 = close[1] - (slDistance * InpTP1_RR);
            currentSetup.takeProfit2 = close[1] - (slDistance * InpTP2_RR);
            currentSetup.setupTime = time[1];
            currentSetup.marketRegime = "STAGE 4: INSTITUTIONAL BEARISH DISTRIBUTION";
         }
      }
   }

   // Floor Trader Pivots calculation & display
   CalculateAndDrawPivots();

   // Draw visual Entry/SL/TP target lines
   DrawTradeSetupLines();

   // Handle Alerts on Bar 1 Confirmation
   HandleAlerts(time[0]);

   // Render Executive Institutional Dashboard
   if(InpShowDashboard)
   {
      RenderDashboard();
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Trigger Audio, Pop-up, Mobile & Email Alerts                     |
//+------------------------------------------------------------------+
void HandleAlerts(datetime currentBarTime)
{
   if(currentBarTime == lastAlertTime) return; // Only one alert per bar

   if(BuySignalBuffer[1] != EMPTY_VALUE && BuySignalBuffer[1] > 0)
   {
      lastAlertTime = currentBarTime;
      string msg = StringFormat("[VETERAN TRADER PRO] 🟢 STRONG BUY SIGNAL\nSymbol: %s | Timeframe: %s\nEntry: %s | SL: %s (%0.1f pips)\nTP1: %s | TP2: %s\nRec Lot: %0.2f (at %0.1f%% risk)\nRule: Check High-Impact News Before Entry!",
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
      string msg = StringFormat("[VETERAN TRADER PRO] 🔴 STRONG SELL SIGNAL\nSymbol: %s | Timeframe: %s\nEntry: %s | SL: %s (%0.1f pips)\nTP1: %s | TP2: %s\nRec Lot: %0.2f (at %0.1f%% risk)\nRule: Check High-Impact News Before Entry!",
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
   int width = 320;
   int rowH = 18;
   int totalRows = 18;
   int height = (totalRows * rowH) + 25;

   color bgClr     = C'18,22,28';
   color borderClr = C'45,62,80';
   color headerClr = C'240,185,11'; // Gold
   color textClr   = C'220,225,230';
   color subClr    = C'130,145,160';
   color greenClr  = C'0,230,118';
   color redClr    = C'255,82,82';

   // Main Panel Background
   CreateRectLabel(PREFIX_DASH + "BG", x, y, width, height, bgClr, borderClr, 2);

   // Header
   CreateLabel(PREFIX_DASH + "H1", x + 12, y + 8, "★ VETERAN TRADER PRO (30-YR WALL ST)", headerClr, InpFontSize + 1, true);
   CreateLabel(PREFIX_DASH + "H2", x + 12, y + 26, "Classical Dow & Confluence Engine (No SMC/ICT)", subClr, InpFontSize - 2, false);

   // Divider 1
   CreateLine(PREFIX_DASH + "Div1", x + 10, y + 42, width - 20, borderClr);

   // Asset Info
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

   color mtfClr = (score >= 50) ? greenClr : (score <= -50) ? redClr : clrOrange;

   CreateLabel(PREFIX_DASH + "MTF_Label", x + 12, y + 68, "MTF Flow:", subClr, InpFontSize - 1, false);
   CreateLabel(PREFIX_DASH + "MTF_Icons", x + 85, y + 68, StringFormat("%s  %s  %s  %s", iconM15, iconH1, iconH4, iconD1), mtfClr, InpFontSize - 1, true);

   // Confluence Score
   string scoreText = (score > 0) ? StringFormat("+%d%% (BULLISH CONFLUENCE)", score) : (score < 0) ? StringFormat("%d%% (BEARISH CONFLUENCE)", score) : "0% (RANGE / CHOPPY)";
   CreateLabel(PREFIX_DASH + "Conf_Label", x + 12, y + 88, "Score:", subClr, InpFontSize - 1, false);
   CreateLabel(PREFIX_DASH + "Conf_Val",   x + 85, y + 88, scoreText, mtfClr, InpFontSize - 1, true);

   // Regime Analysis
   double ema200Now = iMA(NULL, 0, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE, 0);
   double closeNow  = Close[0];
   string regimeStr = (closeNow > ema200Now) ? "Bullish (Stage 2 Markup)" : "Bearish (Stage 4 Markdown)";
   color regimeClr  = (closeNow > ema200Now) ? greenClr : redClr;

   CreateLabel(PREFIX_DASH + "Reg_Label", x + 12, y + 108, "200 EMA:", subClr, InpFontSize - 1, false);
   CreateLabel(PREFIX_DASH + "Reg_Val",   x + 85, y + 108, regimeStr, regimeClr, InpFontSize - 1, true);

   // Divider 2
   CreateLine(PREFIX_DASH + "Div2", x + 10, y + 128, width - 20, borderClr);

   // Tactical Trade Action Box
   string actionText = "WAIT / LOOKING FOR SETUP";
   color actionClr   = clrDarkGray;

   if(currentSetup.signalType == 1)
   {
      actionText = "★ ACTIVE BUY SETUP ★";
      actionClr  = greenClr;
   }
   else if(currentSetup.signalType == -1)
   {
      actionText = "★ ACTIVE SELL SETUP ★";
      actionClr  = redClr;
   }

   CreateLabel(PREFIX_DASH + "Act_Title", x + 12, y + 135, "INSTITUTIONAL ACTION:", headerClr, InpFontSize - 1, true);
   CreateLabel(PREFIX_DASH + "Act_Val",   x + 12, y + 153, actionText, actionClr, InpFontSize + 1, true);

   // Trade Parameters (Entry, SL, TP1, TP2, Lot Size)
   if(currentSetup.signalType != 0)
   {
      CreateLabel(PREFIX_DASH + "Trd_Entry", x + 12, y + 175, StringFormat("Entry: %s", DoubleToString(currentSetup.entryPrice, Digits)), textClr, InpFontSize - 1, true);
      CreateLabel(PREFIX_DASH + "Trd_SL",    x + 12, y + 193, StringFormat("Stop Loss: %s  (%0.1f pips)", DoubleToString(currentSetup.stopLoss, Digits), currentSetup.riskPips), redClr, InpFontSize - 1, true);
      CreateLabel(PREFIX_DASH + "Trd_TP1",   x + 12, y + 211, StringFormat("Target TP1 (1:1.5): %s", DoubleToString(currentSetup.takeProfit1, Digits)), greenClr, InpFontSize - 1, true);
      CreateLabel(PREFIX_DASH + "Trd_TP2",   x + 12, y + 229, StringFormat("Target TP2 (1:2.5): %s", DoubleToString(currentSetup.takeProfit2, Digits)), greenClr, InpFontSize - 1, true);
      CreateLabel(PREFIX_DASH + "Trd_Lot",   x + 12, y + 247, StringFormat("Calculated Lot (%0.1f%% Risk): %0.2f Lots", InpRiskPercent, currentSetup.recLotSize), headerClr, InpFontSize - 1, true);
   }
   else
   {
      CreateLabel(PREFIX_DASH + "Trd_Entry", x + 12, y + 175, "Entry: Waiting for 20/50 EMA Pullback...", subClr, InpFontSize - 1, false);
      CreateLabel(PREFIX_DASH + "Trd_SL",    x + 12, y + 193, "Stop Loss: Dynamic ATR Floor", subClr, InpFontSize - 1, false);
      CreateLabel(PREFIX_DASH + "Trd_TP1",   x + 12, y + 211, "Target TP1: Minimum 1:1.5 RR", subClr, InpFontSize - 1, false);
      CreateLabel(PREFIX_DASH + "Trd_TP2",   x + 12, y + 229, "Target TP2: Expansion 1:2.5 RR", subClr, InpFontSize - 1, false);
      CreateLabel(PREFIX_DASH + "Trd_Lot",   x + 12, y + 247, StringFormat("Lot Size: Auto-calculated at %0.1f%% risk", InpRiskPercent), subClr, InpFontSize - 1, false);
   }

   // Divider 3
   CreateLine(PREFIX_DASH + "Div3", x + 10, y + 268, width - 20, borderClr);

   // Institutional Rules (News & Risk Management)
   CreateLabel(PREFIX_DASH + "Rule1", x + 12, y + 274, "⚠️ 1. CHECK HIGH-IMPACT NEWS BEFORE ENTRY!", clrOrange, InpFontSize - 2, true);
   CreateLabel(PREFIX_DASH + "Rule2", x + 12, y + 290, "🛡️ 2. Max Risk: 1% to 2% Account Balance", subClr, InpFontSize - 2, false);
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
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
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
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   }
}
//+------------------------------------------------------------------+
