//+------------------------------------------------------------------+
//| LiquidityEMA9SMA20.mq4                                           |
//| EMA 9 / SMA 20 liquidity-sweep method from the supplied video.   |
//|                                                                  |
//| This is an analysis indicator. It draws signals, zones, trade    |
//| levels and exits; it does not place orders. Use the companion EA  |
//| if automated execution is required.                              |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "EMA 9 / SMA 20 liquidity-sweep indicator with MTF, zones, Fibonacci and exits."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_color1 clrBlack
#property indicator_color2 clrBlue
#property indicator_color3 clrLime
#property indicator_color4 clrRed
#property indicator_color5 clrOrange
#property indicator_color6 clrOrange
#property indicator_width1 1
#property indicator_width2 1
#property indicator_width3 1
#property indicator_width4 1
#property indicator_width5 2
#property indicator_width6 2

//--- Core method
input int FastEMAPeriod       = 9;
input int SlowSMAPeriod       = 20;
input int SweepLookback       = 1;
input int ATRPeriod           = 14;
input double ArrowOffsetATR   = 0.20;

//--- Range/trend filters
input bool UseRangeFilter     = true;
input double MinMASpreadATR   = 0.10;
input bool UseADXFilter       = false;
input int ADXPeriod           = 14;
input double MinADX           = 20.0;

//--- True multi-timeframe workflow
// On an M5/M15 chart, a closed HTF liquidity candle is required before
// a local entry signal can be accepted. On a chart equal to or higher
// than the selected HTF, the local signal is used directly.
input bool UseMultiTimeframeSetup = true;
input int HigherTimeframe         = PERIOD_H4;
input int MaxHTFSetupAgeBars      = 3;
input bool RequireEntryInHTFZone  = false;

//--- Supply, demand, order-block and fair-value-gap approximation
input bool UseZoneFilter          = true;
input int ZoneLookback            = 200;
input double MaxOpposingZoneATR   = 1.00;
input double DisplacementATR      = 1.00;
input bool DrawZones              = true;
input int MaxZonesToDraw          = 30;
input int ZoneProjectionBars      = 80;

//--- Stop, target and Fibonacci settings
// TargetMode: 0 = Fibonacci extension, 1 = fixed pips, 2 = risk/reward.
input int TargetMode              = 0;
input double FibExtension         = 1.25;
input double FixedTargetPips      = 40.0;
input double RiskRewardTarget     = 1.50;
input double StopBufferATR        = 0.10;
input bool DrawTradeLevels        = true;
input bool DrawFibonacci          = true;
input int MaxTradeDrawings        = 40;
input int TradeProjectionBars     = 60;

//--- Exit/virtual-trade analysis
input bool DrawExitSignals        = true;
input bool ExitOnInsideBar        = true;
input bool ExitOnAccumulation     = true;
input int AccumulationBars        = 2;
input double AccumulationBodyATR  = 0.40;
input bool ExitOnOppositeLiquidity = true;
input bool ExitOnMAFlip           = true;
input bool AllowPyramiding        = true;
input int MaxPyramids             = 3;

//--- Risk estimate (display only in this indicator)
input bool ShowRiskEstimate       = true;
input double RiskPercent           = 1.00;
input bool UseAccountBalance      = true;
input double ManualAccountSize    = 10000.0;

//--- Notifications and performance
input bool EnableAlerts           = true;
input bool EnableSound            = true;
input string SoundFile            = "alert.wav";
input bool EnablePush             = false;
input int MaxBarsToProcess        = 3000;

//--- Plotted buffers
double FastMABuffer[];
double SlowMABuffer[];
double BuyArrowBuffer[];
double SellArrowBuffer[];
double LongExitBuffer[];
double ShortExitBuffer[];

//--- Indicator state
datetime g_lastChartBar = 0;
datetime g_lastAlertedBar = 0;
bool g_alertStateReady = false;

//--- A virtual trade is used only to draw exits and levels. It does not
//--- represent a broker position and cannot place or modify an order.
struct VirtualTrade
{
   bool active;
   int direction;
   int entries;
   datetime entryTime;
   double entry;
   double stop;
   double target;
};

//+------------------------------------------------------------------+
//| Basic helpers                                                     |
//+------------------------------------------------------------------+
int SafePeriod(const int value)
{
   if(value < 1)
      return(1);
   return(value);
}

int ChartSeconds()
{
   int seconds = PeriodSeconds(Period());
   if(seconds < 1)
      seconds = 60;
   return(seconds);
}

double PipSize()
{
   if(Digits == 3 || Digits == 5)
      return(10.0 * Point);
   return(Point);
}

double PipsToPrice(const double pips)
{
   return(pips * PipSize());
}

string TFName(const int timeframe)
{
   switch(timeframe)
   {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
   }
   return(IntegerToString(timeframe));
}

string PriceText(const double price)
{
   return(DoubleToString(price, Digits));
}

string ObjectId(const string prefix, const datetime t, const int suffix)
{
   return(prefix + IntegerToString((int)t) + "_" + IntegerToString(suffix));
}

//+------------------------------------------------------------------+
//| Moving-average and candle signal logic                            |
//+------------------------------------------------------------------+
double LowestPreviousLow(const int timeframe, const int signalShift)
{
   double lowest = iLow(NULL, timeframe, signalShift + 1);
   for(int offset = 2; offset <= SweepLookback; offset++)
   {
      double value = iLow(NULL, timeframe, signalShift + offset);
      if(value < lowest)
         lowest = value;
   }
   return(lowest);
}

double HighestPreviousHigh(const int timeframe, const int signalShift)
{
   double highest = iHigh(NULL, timeframe, signalShift + 1);
   for(int offset = 2; offset <= SweepLookback; offset++)
   {
      double value = iHigh(NULL, timeframe, signalShift + offset);
      if(value > highest)
         highest = value;
   }
   return(highest);
}

bool PassesTFFilters(const int timeframe, const int shift,
                     const double fastMA, const double slowMA)
{
   double atr = iATR(NULL, timeframe, ATRPeriod, shift);

   if(UseRangeFilter)
   {
      if(atr <= 0.0)
         return(false);
      if(MathAbs(fastMA - slowMA) < MinMASpreadATR * atr)
         return(false);
   }

   if(UseADXFilter)
   {
      double adx = iADX(NULL, timeframe, ADXPeriod, PRICE_CLOSE,
                        MODE_MAIN, shift);
      if(adx < MinADX)
         return(false);
   }

   return(true);
}

// A liquidity candle is interpreted as a same-colour candle that sweeps
// a preceding high/low and closes back through that level.
bool IsLiquiditySignalTF(const int timeframe, const int shift,
                         const int direction)
{
   if(shift < 1)
      return(false);

   double fastMA = iMA(NULL, timeframe, FastEMAPeriod, 0,
                       MODE_EMA, PRICE_CLOSE, shift);
   double slowMA = iMA(NULL, timeframe, SlowSMAPeriod, 0,
                       MODE_SMA, PRICE_CLOSE, shift);

   if(direction > 0 && fastMA <= slowMA)
      return(false);
   if(direction < 0 && fastMA >= slowMA)
      return(false);
   if(!PassesTFFilters(timeframe, shift, fastMA, slowMA))
      return(false);

   double o = iOpen(NULL, timeframe, shift);
   double c = iClose(NULL, timeframe, shift);
   double h = iHigh(NULL, timeframe, shift);
   double l = iLow(NULL, timeframe, shift);

   // The candle must touch/intersect EMA 9.
   if(h < fastMA || l > fastMA)
      return(false);

   if(direction > 0)
   {
      if(c <= o)
         return(false);
      double previousLow = LowestPreviousLow(timeframe, shift);
      if(l >= previousLow || c <= previousLow)
         return(false);
   }
   else
   {
      if(c >= o)
         return(false);
      double previousHigh = HighestPreviousHigh(timeframe, shift);
      if(h <= previousHigh || c >= previousHigh)
         return(false);
   }

   return(true);
}

bool IsLongSignal(const int shift)
{
   return(IsLiquiditySignalTF(0, shift, 1));
}

bool IsShortSignal(const int shift)
{
   return(IsLiquiditySignalTF(0, shift, -1));
}

//+------------------------------------------------------------------+
//| Multi-timeframe setup detection                                   |
//+------------------------------------------------------------------+
int ClosedHTFShiftForTime(const datetime barTime)
{
   int shift = iBarShift(NULL, HigherTimeframe, barTime, false);
   if(shift < 0)
      return(-1);
   return(shift);
}

bool FindActiveHTFSetup(const datetime entryTime, const int direction,
                        int &setupShift, double &zoneLow, double &zoneHigh,
                        datetime &zoneStart, datetime &setupClose)
{
   setupShift = -1;
   zoneLow = 0.0;
   zoneHigh = 0.0;
   zoneStart = 0;
   setupClose = 0;

   if(!UseMultiTimeframeSetup)
      return(true);

   // If the chart is equal to or above the requested HTF, use the local
   // signal. There is no lower timeframe on which to perform confirmation.
   if(HigherTimeframe <= Period())
      return(true);

   int currentHTFShift = ClosedHTFShiftForTime(entryTime);
   if(currentHTFShift < 0)
      return(false);

   int first = currentHTFShift + 1;
   if(first < 1)
      first = 1;
   int last = first + MathMax(1, MaxHTFSetupAgeBars) - 1;

   for(int hShift = first; hShift <= last; hShift++)
   {
      if(iTime(NULL, HigherTimeframe, hShift) <= 0)
         continue;
      if(!IsLiquiditySignalTF(HigherTimeframe, hShift, direction))
         continue;

      // The setup candle must be closed before the lower-timeframe entry.
      datetime closeTime = iTime(NULL, HigherTimeframe, hShift - 1);
      if(closeTime <= 0 || entryTime < closeTime)
         continue;

      double h = iHigh(NULL, HigherTimeframe, hShift);
      double l = iLow(NULL, HigherTimeframe, hShift);

      if(RequireEntryInHTFZone)
      {
         int lowerShift = iBarShift(NULL, 0, entryTime, false);
         if(lowerShift < 0)
            continue;
         double entryHigh = iHigh(NULL, 0, lowerShift);
         double entryLow = iLow(NULL, 0, lowerShift);
         if(entryHigh < l || entryLow > h)
            continue;
      }

      setupShift = hShift;
      zoneLow = l;
      zoneHigh = h;
      zoneStart = iTime(NULL, HigherTimeframe, hShift);
      setupClose = closeTime;
      return(true);
   }

   return(false);
}

bool PassesMultiTimeframeSetup(const int shift, const int direction,
                               int &setupShift, double &zoneLow,
                               double &zoneHigh, datetime &zoneStart,
                               datetime &setupClose)
{
   datetime t = iTime(NULL, 0, shift);
   return(FindActiveHTFSetup(t, direction, setupShift, zoneLow,
                             zoneHigh, zoneStart, setupClose));
}

//+------------------------------------------------------------------+
//| Zone detection                                                    |
//+------------------------------------------------------------------+
// These are deliberately objective approximations of the video's
// discretionary supply/demand, order-block and FVG references.
bool GetDemandZone(const int shift, double &zoneLow, double &zoneHigh)
{
   if(shift < 2)
      return(false);

   double o = iOpen(NULL, 0, shift);
   double c = iClose(NULL, 0, shift);
   double h = iHigh(NULL, 0, shift);
   double l = iLow(NULL, 0, shift);
   double nextC = iClose(NULL, 0, shift - 1);
   double atr = iATR(NULL, 0, ATRPeriod, shift - 1);

   // Bearish base candle followed by bullish displacement.
   if(c >= o || nextC <= h || atr <= 0.0)
      return(false);
   if(MathAbs(iClose(NULL, 0, shift - 1) -
              iOpen(NULL, 0, shift - 1)) < DisplacementATR * atr)
      return(false);

   zoneLow = l;
   zoneHigh = MathMax(o, c);
   return(zoneHigh > zoneLow);
}

bool GetSupplyZone(const int shift, double &zoneLow, double &zoneHigh)
{
   if(shift < 2)
      return(false);

   double o = iOpen(NULL, 0, shift);
   double c = iClose(NULL, 0, shift);
   double h = iHigh(NULL, 0, shift);
   double l = iLow(NULL, 0, shift);
   double nextC = iClose(NULL, 0, shift - 1);
   double atr = iATR(NULL, 0, ATRPeriod, shift - 1);

   // Bullish base candle followed by bearish displacement.
   if(c <= o || nextC >= l || atr <= 0.0)
      return(false);
   if(MathAbs(iClose(NULL, 0, shift - 1) -
              iOpen(NULL, 0, shift - 1)) < DisplacementATR * atr)
      return(false);

   zoneLow = MathMin(o, c);
   zoneHigh = h;
   return(zoneHigh > zoneLow);
}

bool GetBullishFVG(const int newestShift, double &zoneLow, double &zoneHigh)
{
   if(newestShift < 1)
      return(false);

   // Old candle is newestShift+2; new candle is newestShift.
   double oldHigh = iHigh(NULL, 0, newestShift + 2);
   double newLow = iLow(NULL, 0, newestShift);
   if(oldHigh >= newLow)
      return(false);

   zoneLow = oldHigh;
   zoneHigh = newLow;
   return(true);
}

bool GetBearishFVG(const int newestShift, double &zoneLow, double &zoneHigh)
{
   if(newestShift < 1)
      return(false);

   double oldLow = iLow(NULL, 0, newestShift + 2);
   double newHigh = iHigh(NULL, 0, newestShift);
   if(oldLow <= newHigh)
      return(false);

   zoneLow = newHigh;
   zoneHigh = oldLow;
   return(true);
}

bool IsNearOpposingZone(const int signalShift, const int direction,
                        const double entryPrice)
{
   if(!UseZoneFilter)
      return(true);

   double atr = iATR(NULL, 0, ATRPeriod, signalShift);
   if(atr <= 0.0)
      return(false);
   double maxDistance = MaxOpposingZoneATR * atr;
   int last = signalShift + MathMax(10, ZoneLookback);

   for(int base = signalShift + 2; base <= last; base++)
   {
      double zl = 0.0;
      double zh = 0.0;

      if(direction > 0)
      {
         // Supply above a long entry is opposing.
         if(GetSupplyZone(base, zl, zh))
         {
            if(entryPrice >= zl && entryPrice <= zh)
               return(false);
            if(zl >= entryPrice && zl - entryPrice <= maxDistance)
               return(false);
         }
         if(GetBearishFVG(base - 1, zl, zh))
         {
            if(entryPrice >= zl && entryPrice <= zh)
               return(false);
            if(zl >= entryPrice && zl - entryPrice <= maxDistance)
               return(false);
         }
      }
      else
      {
         // Demand below a short entry is opposing.
         if(GetDemandZone(base, zl, zh))
         {
            if(entryPrice >= zl && entryPrice <= zh)
               return(false);
            if(zh <= entryPrice && entryPrice - zh <= maxDistance)
               return(false);
         }
         if(GetBullishFVG(base - 1, zl, zh))
         {
            if(entryPrice >= zl && entryPrice <= zh)
               return(false);
            if(zh <= entryPrice && entryPrice - zh <= maxDistance)
               return(false);
         }
      }
   }

   return(true);
}

//+------------------------------------------------------------------+
//| Stops, targets, risk estimate                                     |
//+------------------------------------------------------------------+
void GetTradeLevels(const int shift, const int direction,
                    double &entry, double &stop, double &target)
{
   entry = iClose(NULL, 0, shift);
   double atr = iATR(NULL, 0, ATRPeriod, shift);
   if(atr <= 0.0)
      atr = 10.0 * Point;

   if(direction > 0)
      stop = iLow(NULL, 0, shift) - StopBufferATR * atr;
   else
      stop = iHigh(NULL, 0, shift) + StopBufferATR * atr;

   double risk = MathAbs(entry - stop);
   double distance;

   if(TargetMode == 1)
      distance = PipsToPrice(FixedTargetPips);
   else if(TargetMode == 2)
      distance = risk * RiskRewardTarget;
   else
      distance = risk * FibExtension;

   target = entry + direction * distance;
}

double EstimatedLots(const double entry, const double stop)
{
   if(!ShowRiskEstimate || RiskPercent <= 0.0)
      return(0.0);

   double accountSize = ManualAccountSize;
   if(UseAccountBalance)
      accountSize = AccountBalance();
   if(accountSize <= 0.0)
      return(0.0);

   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double riskDistance = MathAbs(entry - stop);
   if(tickSize <= 0.0 || tickValue <= 0.0 || riskDistance <= 0.0)
      return(0.0);

   double riskMoney = accountSize * RiskPercent / 100.0;
   double lossPerLot = riskDistance / tickSize * tickValue;
   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0)
      step = 0.01;
   lots = MathFloor(lots / step) * step;
   return(NormalizeDouble(lots, 2));
}

//+------------------------------------------------------------------+
//| Exit conditions                                                   |
//+------------------------------------------------------------------+
bool IsInsideBar(const int shift)
{
   if(shift + 1 >= iBars(NULL, 0))
      return(false);
   return(iHigh(NULL, 0, shift) <= iHigh(NULL, 0, shift + 1) &&
          iLow(NULL, 0, shift) >= iLow(NULL, 0, shift + 1));
}

bool IsAccumulationBar(const int shift)
{
   double atr = iATR(NULL, 0, ATRPeriod, shift);
   if(atr <= 0.0)
      return(false);
   double body = MathAbs(iClose(NULL, 0, shift) - iOpen(NULL, 0, shift));
   return(body <= AccumulationBodyATR * atr);
}

bool IsAccumulation(const int shift)
{
   if(ExitOnInsideBar && IsInsideBar(shift))
      return(true);
   if(!ExitOnAccumulation)
      return(false);

   int bars = MathMax(1, AccumulationBars);
   for(int n = 0; n < bars; n++)
   {
      if(!IsAccumulationBar(shift + n))
         return(false);
   }
   return(true);
}

int ExitReason(const VirtualTrade &trade, const int shift)
{
   if(!trade.active)
      return(0);

   double h = iHigh(NULL, 0, shift);
   double l = iLow(NULL, 0, shift);

   // Conservative ordering: if both are hit in one candle, assume stop first.
   if(trade.direction > 0)
   {
      if(l <= trade.stop)
         return(1); // stop
      if(h >= trade.target)
         return(2); // target
   }
   else
   {
      if(h >= trade.stop)
         return(1);
      if(l <= trade.target)
         return(2);
   }

   double fast = iMA(NULL, 0, FastEMAPeriod, 0,
                     MODE_EMA, PRICE_CLOSE, shift);
   double slow = iMA(NULL, 0, SlowSMAPeriod, 0,
                     MODE_SMA, PRICE_CLOSE, shift);

   if(ExitOnMAFlip && ((trade.direction > 0 && fast <= slow) ||
                       (trade.direction < 0 && fast >= slow)))
      return(3); // MA flip

   if(ExitOnInsideBar || ExitOnAccumulation)
   {
      if(IsAccumulation(shift))
         return(4); // accumulation/inside bar
   }

   if(ExitOnOppositeLiquidity)
   {
      if((trade.direction > 0 && IsShortSignal(shift)) ||
         (trade.direction < 0 && IsLongSignal(shift)))
         return(5); // opposite liquidity
   }

   return(0);
}

string ExitReasonText(const int reason)
{
   if(reason == 1) return("SL");
   if(reason == 2) return("TP");
   if(reason == 3) return("MA flip");
   if(reason == 4) return("inside/accumulation");
   if(reason == 5) return("opposite liquidity");
   if(reason == 6) return("reverse signal");
   return("exit");
}

//+------------------------------------------------------------------+
//| Chart objects                                                     |
//+------------------------------------------------------------------+
void DeleteOurObjects()
{
   for(int index = ObjectsTotal(0, -1, -1) - 1; index >= 0; index--)
   {
      string name = ObjectName(0, index);
      if(StringFind(name, "L9S20_") == 0)
         ObjectDelete(0, name);
   }
}

void SetObjectStyle(const string name, const color lineColor,
                    const int width, const bool filled)
{
   ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   if(filled)
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
}

void DrawRectangleZone(const string name, const datetime start,
                       const datetime finish, const double zoneLow,
                       const double zoneHigh, const color zoneColor)
{
   if(zoneHigh <= zoneLow || start <= 0 || finish <= start)
      return;
   if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, start, zoneHigh,
                   finish, zoneLow))
      SetObjectStyle(name, zoneColor, 1, true);
}

void DrawPriceLine(const string name, const datetime start,
                   const datetime finish, const double price,
                   const color lineColor, const ENUM_LINE_STYLE style,
                   const string label)
{
   if(!ObjectCreate(0, name, OBJ_TREND, 0, start, price,
                    finish, price))
      return;
   SetObjectStyle(name, lineColor, 1, false);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetString(0, name, OBJPROP_TEXT, label);
}

void DrawTextLabel(const string name, const datetime when,
                   const double price, const string text,
                   const color textColor)
{
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, when, price))
      return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawFibObject(const string name, const datetime start,
                   const datetime finish, const int direction,
                   const double stop, const double entry)
{
   if(!DrawFibonacci)
      return;
   if(!ObjectCreate(0, name, OBJ_FIBO, 0, start, stop, finish, entry))
      return;

   SetObjectStyle(name, clrSilver, 1, false);
   ObjectSetInteger(0, name, OBJPROP_LEVELS, 3);
   ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 0, 0.0);
   ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 1, 1.0);
   ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 2, FibExtension);
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, 0, "SL");
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, 1, "Entry");
   ObjectSetString(0, name, OBJPROP_LEVELTEXT, 2,
                   DoubleToString(FibExtension, 2) + "R");
}

void DrawTrade(const VirtualTrade &trade, const int sequence)
{
   if(!DrawTradeLevels)
      return;

   datetime finish = trade.entryTime +
                     (datetime)(ChartSeconds() * MathMax(1, TradeProjectionBars));
   string id = ObjectId("L9S20_TRADE_", trade.entryTime, sequence);

   DrawPriceLine(id + "_ENTRY", trade.entryTime, finish, trade.entry,
                 clrDodgerBlue, STYLE_DOT, "Entry");
   DrawPriceLine(id + "_SL", trade.entryTime, finish, trade.stop,
                 clrRed, STYLE_DASH, "SL");
   DrawPriceLine(id + "_TP", trade.entryTime, finish, trade.target,
                 clrLimeGreen, STYLE_DASH, "TP");
   DrawFibObject(id + "_FIB", trade.entryTime, finish, trade.direction,
                 trade.stop, trade.entry);

   if(ShowRiskEstimate)
   {
      double lots = EstimatedLots(trade.entry, trade.stop);
      string label = "risk " + DoubleToString(RiskPercent, 2) +
                     "%  lots~" + DoubleToString(lots, 2);
      DrawTextLabel(id + "_TEXT", finish, trade.target, label, clrWhite);
   }
}

void DrawExit(const int shift, const int direction, const int reason)
{
   if(!DrawExitSignals)
      return;
   datetime t = iTime(NULL, 0, shift);
   double atr = iATR(NULL, 0, ATRPeriod, shift);
   if(atr <= 0.0)
      atr = 10.0 * Point;
   double price = direction > 0 ? iHigh(NULL, 0, shift) + 0.2 * atr
                                : iLow(NULL, 0, shift) - 0.2 * atr;
   string name = ObjectId("L9S20_EXIT_", t, reason + direction);
   DrawTextLabel(name, t, price,
                 direction > 0 ? "EXIT LONG " + ExitReasonText(reason)
                                : "EXIT SHORT " + ExitReasonText(reason),
                 clrOrange);
}

void DrawAllZones()
{
   if(!DrawZones)
      return;

   int zoneCount = 0;
   int last = MathMin(iBars(NULL, 0) - 3, MathMax(10, ZoneLookback));
   datetime finish = iTime(NULL, 0, 0) +
                     (datetime)(ChartSeconds() * MathMax(1, ZoneProjectionBars));

   for(int base = 2; base <= last && zoneCount < MaxZonesToDraw; base++)
   {
      double zl = 0.0;
      double zh = 0.0;
      datetime start = iTime(NULL, 0, base);

      if(GetDemandZone(base, zl, zh))
      {
         DrawRectangleZone(ObjectId("L9S20_DEMAND_", start, 1), start,
                           finish, zl, zh, clrPaleGreen);
         zoneCount++;
      }
      if(zoneCount >= MaxZonesToDraw)
         break;
      if(GetSupplyZone(base, zl, zh))
      {
         DrawRectangleZone(ObjectId("L9S20_SUPPLY_", start, 1), start,
                           finish, zl, zh, clrMistyRose);
         zoneCount++;
      }
   }

   // Fair-value gaps are drawn separately so they remain distinguishable.
   int fvgCount = 0;
   for(int newest = 1; newest <= last - 2 && fvgCount < MaxZonesToDraw; newest++)
   {
      double zl = 0.0;
      double zh = 0.0;
      datetime start = iTime(NULL, 0, newest + 2);
      if(GetBullishFVG(newest, zl, zh))
      {
         DrawRectangleZone(ObjectId("L9S20_BFVG_", start, 1), start,
                           finish, zl, zh, clrLightSkyBlue);
         fvgCount++;
      }
      if(GetBearishFVG(newest, zl, zh))
      {
         DrawRectangleZone(ObjectId("L9S20_SFVG_", start, 1), start,
                           finish, zl, zh, clrPlum);
         fvgCount++;
      }
   }

   // Draw recent higher-timeframe liquidity zones.
   if(UseMultiTimeframeSetup && HigherTimeframe > Period())
   {
      int htfCount = 0;
      int htfLast = MathMin(iBars(NULL, HigherTimeframe) - 3,
                            MathMax(10, MaxHTFSetupAgeBars * 8));
      datetime htfFinish = iTime(NULL, 0, 0) +
                           (datetime)(ChartSeconds() * MathMax(1, ZoneProjectionBars));
      for(int h = 1; h <= htfLast && htfCount < MaxZonesToDraw; h++)
      {
         datetime start = iTime(NULL, HigherTimeframe, h);
         if(start <= 0)
            continue;
         double zl = iLow(NULL, HigherTimeframe, h);
         double zh = iHigh(NULL, HigherTimeframe, h);
         if(IsLiquiditySignalTF(HigherTimeframe, h, 1))
         {
            DrawRectangleZone(ObjectId("L9S20_HTFBUY_", start, h), start,
                              htfFinish, zl, zh, clrDarkSeaGreen);
            htfCount++;
         }
         if(htfCount >= MaxZonesToDraw)
            break;
         if(IsLiquiditySignalTF(HigherTimeframe, h, -1))
         {
            DrawRectangleZone(ObjectId("L9S20_HTFSELL_", start, h), start,
                              htfFinish, zl, zh, clrIndianRed);
            htfCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Alerts                                                            |
//+------------------------------------------------------------------+
void Notify(const string message)
{
   if(!EnableAlerts)
      return;
   Alert(message);
   if(EnableSound && StringLen(SoundFile) > 0)
      PlaySound(SoundFile);
   if(EnablePush)
      SendNotification(message);
}

void CheckEntryAlert(const datetime &time[], const int rates_total)
{
   if(!EnableAlerts || rates_total < 2)
      return;

   datetime closedTime = time[1];
   if(!g_alertStateReady)
   {
      g_lastAlertedBar = closedTime;
      g_alertStateReady = true;
      return;
   }
   if(closedTime == g_lastAlertedBar)
      return;

   g_lastAlertedBar = closedTime;
   if(BuyArrowBuffer[1] != EMPTY_VALUE)
      Notify(Symbol() + " " + TFName(Period()) + " BUY liquidity setup");
   else if(SellArrowBuffer[1] != EMPTY_VALUE)
      Notify(Symbol() + " " + TFName(Period()) + " SELL liquidity setup");
   else if(LongExitBuffer[1] != EMPTY_VALUE)
      Notify(Symbol() + " " + TFName(Period()) + " LONG exit");
   else if(ShortExitBuffer[1] != EMPTY_VALUE)
      Notify(Symbol() + " " + TFName(Period()) + " SHORT exit");
}

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(FastEMAPeriod < 1 || SlowSMAPeriod < 1 || SweepLookback < 1 ||
      ATRPeriod < 1 || ADXPeriod < 1 || MaxBarsToProcess < 100 ||
      ZoneLookback < 10 || MaxPyramids < 1 || AccumulationBars < 1 ||
      MaxZonesToDraw < 1 || MaxTradeDrawings < 1 ||
      MinMASpreadATR < 0.0 || StopBufferATR < 0.0 ||
      FibExtension <= 0.0 || FixedTargetPips <= 0.0 ||
      RiskRewardTarget <= 0.0)
      return(INIT_PARAMETERS_INCORRECT);

   SetIndexBuffer(0, FastMABuffer);
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 1, clrBlack);
   SetIndexLabel(0, "EMA " + IntegerToString(FastEMAPeriod));
   SetIndexEmptyValue(0, EMPTY_VALUE);

   SetIndexBuffer(1, SlowMABuffer);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, 1, clrBlue);
   SetIndexLabel(1, "SMA " + IntegerToString(SlowSMAPeriod));
   SetIndexEmptyValue(1, EMPTY_VALUE);

   SetIndexBuffer(2, BuyArrowBuffer);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 1, clrLime);
   SetIndexArrow(2, 233);
   SetIndexLabel(2, "Liquidity buy");
   SetIndexEmptyValue(2, EMPTY_VALUE);

   SetIndexBuffer(3, SellArrowBuffer);
   SetIndexStyle(3, DRAW_ARROW, STYLE_SOLID, 1, clrRed);
   SetIndexArrow(3, 234);
   SetIndexLabel(3, "Liquidity sell");
   SetIndexEmptyValue(3, EMPTY_VALUE);

   SetIndexBuffer(4, LongExitBuffer);
   SetIndexStyle(4, DRAW_ARROW, STYLE_SOLID, 2, clrOrange);
   SetIndexArrow(4, 251);
   SetIndexLabel(4, "Long exit");
   SetIndexEmptyValue(4, EMPTY_VALUE);

   SetIndexBuffer(5, ShortExitBuffer);
   SetIndexStyle(5, DRAW_ARROW, STYLE_SOLID, 2, clrOrange);
   SetIndexArrow(5, 251);
   SetIndexLabel(5, "Short exit");
   SetIndexEmptyValue(5, EMPTY_VALUE);

   ArraySetAsSeries(FastMABuffer, true);
   ArraySetAsSeries(SlowMABuffer, true);
   ArraySetAsSeries(BuyArrowBuffer, true);
   ArraySetAsSeries(SellArrowBuffer, true);
   ArraySetAsSeries(LongExitBuffer, true);
   ArraySetAsSeries(ShortExitBuffer, true);

   IndicatorShortName("Liquidity EMA9/SMA20 MTF");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main calculation                                                  |
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
   ArraySetAsSeries(time, true);

   int minimumBars = MathMax(SlowSMAPeriod, FastEMAPeriod);
   minimumBars = MathMax(minimumBars, SweepLookback + 2);
   minimumBars = MathMax(minimumBars, ATRPeriod + 2);
   minimumBars = MathMax(minimumBars, ADXPeriod + 2);
   if(rates_total <= minimumBars + 10)
      return(0);

   int oldest = rates_total - minimumBars - 1;
   if(oldest > MaxBarsToProcess)
      oldest = MaxBarsToProcess;
   if(oldest < 5)
      return(0);

   bool rebuildObjects = (prev_calculated == 0 || time[0] != g_lastChartBar);
   if(rebuildObjects)
   {
      g_lastChartBar = time[0];
      DeleteOurObjects();
      ArrayInitialize(FastMABuffer, EMPTY_VALUE);
      ArrayInitialize(SlowMABuffer, EMPTY_VALUE);
      ArrayInitialize(BuyArrowBuffer, EMPTY_VALUE);
      ArrayInitialize(SellArrowBuffer, EMPTY_VALUE);
      ArrayInitialize(LongExitBuffer, EMPTY_VALUE);
      ArrayInitialize(ShortExitBuffer, EMPTY_VALUE);
   }

   // Always refresh the visible calculation window. This makes the virtual
   // trade/exit sequence deterministic after a new candle appears.
   for(int clearShift = 1; clearShift <= oldest; clearShift++)
   {
      BuyArrowBuffer[clearShift] = EMPTY_VALUE;
      SellArrowBuffer[clearShift] = EMPTY_VALUE;
      LongExitBuffer[clearShift] = EMPTY_VALUE;
      ShortExitBuffer[clearShift] = EMPTY_VALUE;
   }

   FastMABuffer[0] = iMA(NULL, 0, FastEMAPeriod, 0,
                          MODE_EMA, PRICE_CLOSE, 0);
   SlowMABuffer[0] = iMA(NULL, 0, SlowSMAPeriod, 0,
                          MODE_SMA, PRICE_CLOSE, 0);
   BuyArrowBuffer[0] = EMPTY_VALUE;
   SellArrowBuffer[0] = EMPTY_VALUE;
   LongExitBuffer[0] = EMPTY_VALUE;
   ShortExitBuffer[0] = EMPTY_VALUE;

   VirtualTrade trade;
   trade.active = false;
   trade.direction = 0;
   trade.entries = 0;
   trade.entryTime = 0;
   trade.entry = 0.0;
   trade.stop = 0.0;
   trade.target = 0.0;

   int tradeDrawings = 0;
   int sequence = 0;

   // Iterate from old to new, because exits need a chronological state.
   for(int shift = oldest; shift >= 1; shift--)
   {
      FastMABuffer[shift] = iMA(NULL, 0, FastEMAPeriod, 0,
                                MODE_EMA, PRICE_CLOSE, shift);
      SlowMABuffer[shift] = iMA(NULL, 0, SlowSMAPeriod, 0,
                                MODE_SMA, PRICE_CLOSE, shift);

      int htfSetup = -1;
      double htfLow = 0.0;
      double htfHigh = 0.0;
      datetime htfStart = 0;
      datetime htfClose = 0;

      bool longSignal = IsLongSignal(shift) &&
                        PassesMultiTimeframeSetup(shift, 1, htfSetup,
                                                  htfLow, htfHigh,
                                                  htfStart, htfClose);
      bool shortSignal = IsShortSignal(shift) &&
                         PassesMultiTimeframeSetup(shift, -1, htfSetup,
                                                   htfLow, htfHigh,
                                                   htfStart, htfClose);

      double signalEntry = iClose(NULL, 0, shift);
      if(longSignal && !IsNearOpposingZone(shift, 1, signalEntry))
         longSignal = false;
      if(shortSignal && !IsNearOpposingZone(shift, -1, signalEntry))
         shortSignal = false;

      double atr = iATR(NULL, 0, ATRPeriod, shift);
      if(atr <= 0.0)
         atr = 10.0 * Point;

      if(longSignal)
         BuyArrowBuffer[shift] = iLow(NULL, 0, shift) - ArrowOffsetATR * atr;
      if(shortSignal)
         SellArrowBuffer[shift] = iHigh(NULL, 0, shift) + ArrowOffsetATR * atr;

      // First resolve any existing virtual position on this closed candle.
      if(trade.active)
      {
         int reason = ExitReason(trade, shift);
         if(reason > 0)
         {
            if(trade.direction > 0)
               LongExitBuffer[shift] = iHigh(NULL, 0, shift) + 0.25 * atr;
            else
               ShortExitBuffer[shift] = iLow(NULL, 0, shift) - 0.25 * atr;
            if(rebuildObjects)
               DrawExit(shift, trade.direction, reason);
            trade.active = false;
            trade.entries = 0;
         }
      }

      // A reverse signal closes the old virtual trade at the signal close.
      if(trade.active && ((trade.direction > 0 && shortSignal) ||
                          (trade.direction < 0 && longSignal)))
      {
         if(trade.direction > 0)
            LongExitBuffer[shift] = iHigh(NULL, 0, shift) + 0.25 * atr;
         else
            ShortExitBuffer[shift] = iLow(NULL, 0, shift) - 0.25 * atr;
         if(rebuildObjects)
            DrawExit(shift, trade.direction, 6);
         trade.active = false;
         trade.entries = 0;
      }

      if(!trade.active && (longSignal || shortSignal))
      {
         int direction = longSignal ? 1 : -1;
         GetTradeLevels(shift, direction, trade.entry, trade.stop,
                        trade.target);
         trade.active = true;
         trade.direction = direction;
         trade.entries = 1;
         trade.entryTime = iTime(NULL, 0, shift);
         sequence++;
         if(rebuildObjects && tradeDrawings < MaxTradeDrawings)
         {
            DrawTrade(trade, sequence);
            tradeDrawings++;
         }
      }
      else if(trade.active && AllowPyramiding &&
              trade.entries < MaxPyramids &&
              ((trade.direction > 0 && longSignal) ||
               (trade.direction < 0 && shortSignal)))
      {
         trade.entries++;
         if(rebuildObjects && tradeDrawings < MaxTradeDrawings)
         {
            VirtualTrade addOn = trade;
            addOn.entryTime = iTime(NULL, 0, shift);
            GetTradeLevels(shift, trade.direction, addOn.entry,
                           addOn.stop, addOn.target);
            sequence++;
            DrawTrade(addOn, sequence);
            tradeDrawings++;
         }
      }
   }

   if(rebuildObjects)
      DrawAllZones();

   CheckEntryAlert(time, rates_total);
   return(rates_total);
}
//+------------------------------------------------------------------+
