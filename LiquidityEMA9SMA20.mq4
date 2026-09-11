//+------------------------------------------------------------------+
//|                                             LiquidityEMA9SMA20.mq4 |
//|  Trend + liquidity-sweep indicator inspired by the supplied video |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "EMA 9 / SMA 20 trend filter with a candle liquidity sweep trigger."
#property description "Signals are generated on closed candles only."
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1 clrBlack
#property indicator_color2 clrBlue
#property indicator_color3 clrLime
#property indicator_color4 clrRed
#property indicator_width1 1
#property indicator_width2 1
#property indicator_width3 1
#property indicator_width4 1

//--- Moving-average settings
input int FastEMAPeriod       = 9;
input int SlowSMAPeriod       = 20;

//--- Liquidity candle settings
// A buy candle must sweep the lowest low of the preceding N candles and
// close back above that level. A sell candle is the exact inverse.
input int SweepLookback       = 1;
input int ATRPeriod           = 14;
input double ArrowOffsetATR   = 0.20;

//--- Optional filters
// The video says to avoid consolidation, but does not define it precisely.
// This ATR-normalized MA-separation filter is an objective approximation.
input bool UseRangeFilter     = true;
input double MinMASpreadATR   = 0.10;

// Optional ADX filter; disabled by default because the video uses only two MAs.
input bool UseADXFilter       = false;
input int ADXPeriod           = 14;
input double MinADX           = 20.0;

// Optional higher-timeframe trend confirmation. The closed HTF candle is used
// to avoid looking ahead into an unfinished higher-timeframe candle.
input bool UseHigherTF        = false;
input int HigherTimeframe     = PERIOD_H4;

//--- Alerts
input bool EnableAlerts       = true;
input bool EnableSound        = true;
input string SoundFile        = "alert.wav";
input bool EnablePush         = false;

//--- Indicator buffers
double FastMABuffer[];
double SlowMABuffer[];
double BuyArrowBuffer[];
double SellArrowBuffer[];

//--- State used to prevent repeated alerts on every tick
datetime g_lastAlertedBar = 0;
bool g_alertStateReady = false;

//+------------------------------------------------------------------+
//| Utility: lowest low in candles older than the signal candle       |
//+------------------------------------------------------------------+
double LowestPreviousLow(const int signalShift)
{
   double lowest = iLow(NULL, 0, signalShift + 1);

   for(int offset = 2; offset <= SweepLookback; offset++)
   {
      double value = iLow(NULL, 0, signalShift + offset);
      if(value < lowest)
         lowest = value;
   }

   return(lowest);
}

//+------------------------------------------------------------------+
//| Utility: highest high in candles older than the signal candle     |
//+------------------------------------------------------------------+
double HighestPreviousHigh(const int signalShift)
{
   double highest = iHigh(NULL, 0, signalShift + 1);

   for(int offset = 2; offset <= SweepLookback; offset++)
   {
      double value = iHigh(NULL, 0, signalShift + offset);
      if(value > highest)
         highest = value;
   }

   return(highest);
}

//+------------------------------------------------------------------+
//| Optional filter shared by both directions                         |
//+------------------------------------------------------------------+
bool PassesCommonFilters(const int signalShift,
                         const double fastMA,
                         const double slowMA)
{
   double atr = iATR(NULL, 0, ATRPeriod, signalShift);

   if(UseRangeFilter)
   {
      // If ATR is unavailable, do not manufacture a signal.
      if(atr <= 0.0)
         return(false);

      if(MathAbs(fastMA - slowMA) < (MinMASpreadATR * atr))
         return(false);
   }

   if(UseADXFilter)
   {
      double adx = iADX(NULL, 0, ADXPeriod, PRICE_CLOSE,
                        MODE_MAIN, signalShift);
      if(adx < MinADX)
         return(false);
   }

   return(true);
}

//+------------------------------------------------------------------+
//| Return the last fully closed higher-timeframe candle              |
//+------------------------------------------------------------------+
int ClosedHigherTFShift(const datetime signalBarTime)
{
   int shift = iBarShift(NULL, HigherTimeframe, signalBarTime, false);
   if(shift < 0)
      return(-1);

   // The candle containing signalBarTime may still be forming. Use the
   // preceding candle so the optional HTF filter does not repaint.
   return(shift + 1);
}

//+------------------------------------------------------------------+
//| Optional higher-timeframe trend filter                            |
//+------------------------------------------------------------------+
bool PassesHigherTFLong(const datetime signalBarTime)
{
   if(!UseHigherTF)
      return(true);

   int htfShift = ClosedHigherTFShift(signalBarTime);
   if(htfShift < 0)
      return(false);

   double fast = iMA(NULL, HigherTimeframe, FastEMAPeriod, 0,
                     MODE_EMA, PRICE_CLOSE, htfShift);
   double slow = iMA(NULL, HigherTimeframe, SlowSMAPeriod, 0,
                     MODE_SMA, PRICE_CLOSE, htfShift);

   return(fast > slow);
}

//+------------------------------------------------------------------+
//| Optional higher-timeframe trend filter                            |
//+------------------------------------------------------------------+
bool PassesHigherTFShort(const datetime signalBarTime)
{
   if(!UseHigherTF)
      return(true);

   int htfShift = ClosedHigherTFShift(signalBarTime);
   if(htfShift < 0)
      return(false);

   double fast = iMA(NULL, HigherTimeframe, FastEMAPeriod, 0,
                     MODE_EMA, PRICE_CLOSE, htfShift);
   double slow = iMA(NULL, HigherTimeframe, SlowSMAPeriod, 0,
                     MODE_SMA, PRICE_CLOSE, htfShift);

   return(fast < slow);
}

//+------------------------------------------------------------------+
//| Detect a long setup                                                |
//+------------------------------------------------------------------+
bool IsLongSignal(const int signalShift, const datetime signalBarTime)
{
   double fastMA = iMA(NULL, 0, FastEMAPeriod, 0,
                       MODE_EMA, PRICE_CLOSE, signalShift);
   double slowMA = iMA(NULL, 0, SlowSMAPeriod, 0,
                       MODE_SMA, PRICE_CLOSE, signalShift);

   // Trend condition from the video: EMA 9 above SMA 20.
   if(fastMA <= slowMA)
      return(false);

   if(!PassesCommonFilters(signalShift, fastMA, slowMA))
      return(false);

   if(!PassesHigherTFLong(signalBarTime))
      return(false);

   double openPrice  = iOpen(NULL, 0, signalShift);
   double closePrice = iClose(NULL, 0, signalShift);
   double highPrice  = iHigh(NULL, 0, signalShift);
   double lowPrice   = iLow(NULL, 0, signalShift);

   // Green/bullish liquidity candle touching the fast EMA.
   if(closePrice <= openPrice)
      return(false);
   if(highPrice < fastMA || lowPrice > fastMA)
      return(false);

   // Sweep the previous low(s), then reclaim the swept level.
   double previousLow = LowestPreviousLow(signalShift);
   if(lowPrice >= previousLow)
      return(false);
   if(closePrice <= previousLow)
      return(false);

   return(true);
}

//+------------------------------------------------------------------+
//| Detect a short setup                                               |
//+------------------------------------------------------------------+
bool IsShortSignal(const int signalShift, const datetime signalBarTime)
{
   double fastMA = iMA(NULL, 0, FastEMAPeriod, 0,
                       MODE_EMA, PRICE_CLOSE, signalShift);
   double slowMA = iMA(NULL, 0, SlowSMAPeriod, 0,
                       MODE_SMA, PRICE_CLOSE, signalShift);

   // Trend condition from the video: EMA 9 below SMA 20.
   if(fastMA >= slowMA)
      return(false);

   if(!PassesCommonFilters(signalShift, fastMA, slowMA))
      return(false);

   if(!PassesHigherTFShort(signalBarTime))
      return(false);

   double openPrice  = iOpen(NULL, 0, signalShift);
   double closePrice = iClose(NULL, 0, signalShift);
   double highPrice  = iHigh(NULL, 0, signalShift);
   double lowPrice   = iLow(NULL, 0, signalShift);

   // Red/bearish liquidity candle touching the fast EMA.
   if(closePrice >= openPrice)
      return(false);
   if(highPrice < fastMA || lowPrice > fastMA)
      return(false);

   // Sweep the previous high(s), then reject back below the swept level.
   double previousHigh = HighestPreviousHigh(signalShift);
   if(highPrice <= previousHigh)
      return(false);
   if(closePrice >= previousHigh)
      return(false);

   return(true);
}

//+------------------------------------------------------------------+
//| Build an alert message                                             |
//+------------------------------------------------------------------+
void NotifySignal(const bool isLong, const datetime signalBarTime)
{
   string direction = isLong ? "BUY" : "SELL";
   string message = StringFormat("%s %s %s: EMA%d/SMA%d liquidity signal at %s",
                                 Symbol(), PeriodDescription(Period()),
                                 direction, FastEMAPeriod, SlowSMAPeriod,
                                 TimeToString(signalBarTime, TIME_DATE | TIME_MINUTES));

   Alert(message);

   if(EnableSound && StringLen(SoundFile) > 0)
      PlaySound(SoundFile);

   if(EnablePush)
      SendNotification(message);
}

//+------------------------------------------------------------------+
//| Human-readable timeframe label                                     |
//+------------------------------------------------------------------+
string PeriodDescription(const int timeframe)
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

//+------------------------------------------------------------------+
//| Alert only when a new candle has closed                            |
//+------------------------------------------------------------------+
void CheckForNewClosedBarAlert(const datetime &time[],
                               const int rates_total)
{
   if(!EnableAlerts || rates_total < 2)
      return;

   datetime closedBarTime = time[1];

   // Do not alert for an old signal merely because the indicator was attached.
   if(!g_alertStateReady)
   {
      g_lastAlertedBar = closedBarTime;
      g_alertStateReady = true;
      return;
   }

   if(closedBarTime == g_lastAlertedBar)
      return;

   g_lastAlertedBar = closedBarTime;

   if(BuyArrowBuffer[1] != EMPTY_VALUE)
      NotifySignal(true, closedBarTime);
   else if(SellArrowBuffer[1] != EMPTY_VALUE)
      NotifySignal(false, closedBarTime);
}

//+------------------------------------------------------------------+
//| Initialization                                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   if(FastEMAPeriod < 1 || SlowSMAPeriod < 1 ||
      SweepLookback < 1 || ATRPeriod < 1 || ADXPeriod < 1 ||
      MinMASpreadATR < 0.0 || ArrowOffsetATR < 0.0)
   {
      return(INIT_PARAMETERS_INCORRECT);
   }

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

   ArraySetAsSeries(FastMABuffer, true);
   ArraySetAsSeries(SlowMABuffer, true);
   ArraySetAsSeries(BuyArrowBuffer, true);
   ArraySetAsSeries(SellArrowBuffer, true);

   IndicatorShortName("Liquidity EMA9/SMA20");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main calculation                                                   |
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

   if(rates_total <= minimumBars + 2)
      return(0);

   int oldestUsableShift = rates_total - minimumBars - 1;
   int start;

   if(prev_calculated == 0)
   {
      ArrayInitialize(FastMABuffer, EMPTY_VALUE);
      ArrayInitialize(SlowMABuffer, EMPTY_VALUE);
      ArrayInitialize(BuyArrowBuffer, EMPTY_VALUE);
      ArrayInitialize(SellArrowBuffer, EMPTY_VALUE);
      start = oldestUsableShift;
   }
   else
   {
      // Recalculate the newest closed bar and the currently forming bar.
      start = rates_total - prev_calculated + 1;
      if(start < 1)
         start = 1;
      if(start > oldestUsableShift)
         start = oldestUsableShift;
   }

   // Keep the current moving-average values live, but never signal on bar 0.
   FastMABuffer[0] = iMA(NULL, 0, FastEMAPeriod, 0,
                          MODE_EMA, PRICE_CLOSE, 0);
   SlowMABuffer[0] = iMA(NULL, 0, SlowSMAPeriod, 0,
                          MODE_SMA, PRICE_CLOSE, 0);
   BuyArrowBuffer[0] = EMPTY_VALUE;
   SellArrowBuffer[0] = EMPTY_VALUE;

   for(int shift = start; shift >= 1; shift--)
   {
      FastMABuffer[shift] = iMA(NULL, 0, FastEMAPeriod, 0,
                                MODE_EMA, PRICE_CLOSE, shift);
      SlowMABuffer[shift] = iMA(NULL, 0, SlowSMAPeriod, 0,
                                MODE_SMA, PRICE_CLOSE, shift);

      BuyArrowBuffer[shift] = EMPTY_VALUE;
      SellArrowBuffer[shift] = EMPTY_VALUE;

      if(IsLongSignal(shift, time[shift]))
      {
         double atr = iATR(NULL, 0, ATRPeriod, shift);
         if(atr <= 0.0)
            atr = 10.0 * Point;
         BuyArrowBuffer[shift] = iLow(NULL, 0, shift) -
                                 (ArrowOffsetATR * atr);
      }
      else if(IsShortSignal(shift, time[shift]))
      {
         double atr = iATR(NULL, 0, ATRPeriod, shift);
         if(atr <= 0.0)
            atr = 10.0 * Point;
         SellArrowBuffer[shift] = iHigh(NULL, 0, shift) +
                                  (ArrowOffsetATR * atr);
      }
   }

   CheckForNewClosedBarAlert(time, rates_total);
   return(rates_total);
}
//+------------------------------------------------------------------+
