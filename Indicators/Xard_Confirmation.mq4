//+------------------------------------------------------------------+
//|                                           Xard_Confirmation.mq4 |
//| A non-repainting, XARD-style confirmation indicator for MT4.    |
//|                                                                  |
//| Method (conservative):                                           |
//|  1) EMA trend alignment (13/55 by default)                       |
//|  2) Optional Daily Open and higher-timeframe alignment           |
//|  3) A confirmed higher low (buy) or lower high (sell)            |
//|  4) A closed, directional confirmation candle                    |
//|                                                                  |
//| This is an independent confirmation tool. It does NOT reproduce  |
//| XARD's proprietary templates or claim that any signal will win.  |
//| Pivots are confirmed only after PivotStrength closed bars, so    |
//| signals arrive later than an unconfirmed ZigZag/Semafor dot.     |
//+------------------------------------------------------------------+
#property strict
#property copyright "Open educational implementation"
#property link      "https://forex-station.com/xard-simple-trend-following-trading-system-t8416709.html"
#property version   "1.00"
#property description "Conservative XARD-style confirmation: EMA trend + Daily Open + confirmed higher low/lower high."
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_color1  clrLimeGreen
#property indicator_color2  clrTomato
#property indicator_color3  clrNONE
#property indicator_color4  clrNONE
#property indicator_color5  clrNONE
#property indicator_color6  clrGold

//---- Trend and location filters
input int                FastEMAPeriod             = 13;
input int                SlowEMAPeriod             = 55;
input ENUM_APPLIED_PRICE EMAPrice                   = PRICE_CLOSE;
input bool               UseDailyOpenFilter        = true;
input bool               ShowDailyOpen             = true;
input bool               UseHigherTimeframeFilter  = true;
input ENUM_TIMEFRAMES    BiasTimeframe             = PERIOD_H1;

//---- Confirmed-structure / "2nd Dot" approximation
input int                PivotStrength             = 2;
input int                PriorPivotSearchBars      = 80;
input int                ATRPeriod                 = 14;
input double             MinimumStructureGapATR    = 0.10;
input double             MaximumEntryDistanceATR   = 1.00;

//---- Display and alerts
input int                MaximumBarsToProcess      = 1500;
input double             ArrowOffsetATR            = 0.25;
input bool               EnablePopupAlerts         = true;
input bool               EnablePushAlerts          = false;
input bool               EnableEmailAlerts         = false;

//---- Buffers. Stop-guide and trend buffers are intentionally hidden,
//---- but can be read by an EA or displayed in MT4's Data Window.
double BuyConfirmation[];
double SellConfirmation[];
double LongStopGuide[];
double ShortStopGuide[];
double TrendState[];
double DailyOpenLine[];

//---- Alert de-duplication for the last closed bar.
datetime LastBuyAlertTime  = 0;
datetime LastSellAlertTime = 0;

//+------------------------------------------------------------------+
//| Convert a timeframe to a compact readable label.                |
//+------------------------------------------------------------------+
string TimeframeLabel(const int timeframe)
{
   if(timeframe == PERIOD_M1)  return "M1";
   if(timeframe == PERIOD_M5)  return "M5";
   if(timeframe == PERIOD_M15) return "M15";
   if(timeframe == PERIOD_M30) return "M30";
   if(timeframe == PERIOD_H1)  return "H1";
   if(timeframe == PERIOD_H4)  return "H4";
   if(timeframe == PERIOD_D1)  return "D1";
   if(timeframe == PERIOD_W1)  return "W1";
   if(timeframe == PERIOD_MN1) return "MN1";
   return IntegerToString(timeframe);
}

//+------------------------------------------------------------------+
//| Reset a bar's output values.                                    |
//+------------------------------------------------------------------+
void ClearBar(const int bar)
{
   BuyConfirmation[bar]  = EMPTY_VALUE;
   SellConfirmation[bar] = EMPTY_VALUE;
   LongStopGuide[bar]    = EMPTY_VALUE;
   ShortStopGuide[bar]   = EMPTY_VALUE;
   TrendState[bar]       = 0.0;
   DailyOpenLine[bar]    = EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| A pivot is confirmed only after bars on BOTH sides are closed.   |
//| Arrays use MT4 time-series indexing: 0 is the current bar.      |
//+------------------------------------------------------------------+
bool IsConfirmedPivotLow(const double &low[], const int index, const int rates_total)
{
   if(index - PivotStrength < 1 || index + PivotStrength >= rates_total)
      return false;

   for(int offset = 1; offset <= PivotStrength; offset++)
   {
      // Strict on the newer side prevents duplicate equal-low pivots.
      if(low[index] >= low[index - offset])
         return false;
      if(low[index] > low[index + offset])
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Confirmed pivot high counterpart.                               |
//+------------------------------------------------------------------+
bool IsConfirmedPivotHigh(const double &high[], const int index, const int rates_total)
{
   if(index - PivotStrength < 1 || index + PivotStrength >= rates_total)
      return false;

   for(int offset = 1; offset <= PivotStrength; offset++)
   {
      // Strict on the newer side prevents duplicate equal-high pivots.
      if(high[index] <= high[index - offset])
         return false;
      if(high[index] < high[index + offset])
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Find the next older confirmed pivot of the requested direction. |
//+------------------------------------------------------------------+
int FindPreviousPivotLow(const double &low[], const int newestPivot, const int rates_total)
{
   int lastSearchBar = (int)MathMin(rates_total - PivotStrength - 1,
                                    newestPivot + PriorPivotSearchBars);
   for(int bar = newestPivot + 1; bar <= lastSearchBar; bar++)
   {
      if(IsConfirmedPivotLow(low, bar, rates_total))
         return bar;
   }
   return -1;
}

int FindPreviousPivotHigh(const double &high[], const int newestPivot, const int rates_total)
{
   int lastSearchBar = (int)MathMin(rates_total - PivotStrength - 1,
                                    newestPivot + PriorPivotSearchBars);
   for(int bar = newestPivot + 1; bar <= lastSearchBar; bar++)
   {
      if(IsConfirmedPivotHigh(high, bar, rates_total))
         return bar;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Retrieve the broker's Daily Open that was known at barTime.     |
//+------------------------------------------------------------------+
bool GetDailyOpenAtTime(const datetime barTime, double &dailyOpen)
{
   int dayShift = iBarShift(NULL, PERIOD_D1, barTime, false);
   if(dayShift < 0)
      return false;

   dailyOpen = iOpen(NULL, PERIOD_D1, dayShift);
   return (dailyOpen != 0.0);
}

//+------------------------------------------------------------------+
//| Use ONLY a completed candle from the higher timeframe.          |
//| This avoids using the still-forming H1/H4 candle as confirmation.|
//+------------------------------------------------------------------+
bool GetHigherTimeframeTrend(const datetime barTime, bool &isBullish, bool &isBearish)
{
   isBullish = false;
   isBearish = false;

   int containingBar = iBarShift(NULL, BiasTimeframe, barTime, false);
   if(containingBar < 0)
      return false;

   // +1 is the previously completed higher-timeframe bar.
   int closedBar = containingBar + 1;
   int requiredBars = SlowEMAPeriod + closedBar + 2;
   if(iBars(NULL, BiasTimeframe) < requiredBars)
      return false;

   double fast  = iMA(NULL, BiasTimeframe, FastEMAPeriod, 0, MODE_EMA, EMAPrice, closedBar);
   double slow  = iMA(NULL, BiasTimeframe, SlowEMAPeriod, 0, MODE_EMA, EMAPrice, closedBar);
   double close = iClose(NULL, BiasTimeframe, closedBar);

   if(fast == 0.0 || slow == 0.0 || close == 0.0)
      return false;

   isBullish = (fast > slow && close > slow);
   isBearish = (fast < slow && close < slow);
   return true;
}

//+------------------------------------------------------------------+
//| Send one alert per confirmed signal bar and direction.           |
//+------------------------------------------------------------------+
void Notify(const bool isBuy, const datetime signalTime, const double signalPrice)
{
   string direction = isBuy ? "BUY" : "SELL";
   string message = StringFormat("XARD-style %s confirmation | %s %s | closed bar %s | price %s",
                                 direction,
                                 Symbol(),
                                 TimeframeLabel(Period()),
                                 TimeToString(signalTime, TIME_DATE|TIME_MINUTES),
                                 DoubleToString(signalPrice, Digits));

   if(EnablePopupAlerts)
      Alert(message);
   if(EnablePushAlerts)
      SendNotification(message);
   if(EnableEmailAlerts)
      SendMail("XARD-style MT4 confirmation", message);
}

//+------------------------------------------------------------------+
//| Indicator initialisation.                                       |
//+------------------------------------------------------------------+
int OnInit()
{
   if(FastEMAPeriod < 2 || SlowEMAPeriod <= FastEMAPeriod ||
      PivotStrength < 1 || PriorPivotSearchBars < PivotStrength + 4 ||
      ATRPeriod < 2 || MaximumBarsToProcess < 100 ||
      MinimumStructureGapATR < 0.0 || MaximumEntryDistanceATR <= 0.0)
   {
      Print("Xard_Confirmation: invalid input. Use Slow EMA > Fast EMA, ",
            "PivotStrength >= 1, and a positive entry-distance limit.");
      return INIT_PARAMETERS_INCORRECT;
   }

   IndicatorDigits(Digits);
   IndicatorShortName(StringFormat("XARD-style Confirmation (%d/%d EMA, pivot %d)",
                                   FastEMAPeriod, SlowEMAPeriod, PivotStrength));

   SetIndexBuffer(0, BuyConfirmation);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 1, clrLimeGreen);
   SetIndexArrow(0, 233);
   SetIndexLabel(0, "Buy confirmation");
   SetIndexEmptyValue(0, EMPTY_VALUE);

   SetIndexBuffer(1, SellConfirmation);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 1, clrTomato);
   SetIndexArrow(1, 234);
   SetIndexLabel(1, "Sell confirmation");
   SetIndexEmptyValue(1, EMPTY_VALUE);

   SetIndexBuffer(2, LongStopGuide);
   SetIndexStyle(2, DRAW_NONE);
   SetIndexLabel(2, "Long structural stop guide");
   SetIndexEmptyValue(2, EMPTY_VALUE);

   SetIndexBuffer(3, ShortStopGuide);
   SetIndexStyle(3, DRAW_NONE);
   SetIndexLabel(3, "Short structural stop guide");
   SetIndexEmptyValue(3, EMPTY_VALUE);

   SetIndexBuffer(4, TrendState);
   SetIndexStyle(4, DRAW_NONE);
   SetIndexLabel(4, "Trend state (1 buy, -1 sell, 0 none)");

   SetIndexBuffer(5, DailyOpenLine);
   SetIndexStyle(5, ShowDailyOpen ? DRAW_LINE : DRAW_NONE, STYLE_DOT, 1, clrGold);
   SetIndexLabel(5, "Broker Daily Open");
   SetIndexEmptyValue(5, EMPTY_VALUE);

   ArraySetAsSeries(BuyConfirmation, true);
   ArraySetAsSeries(SellConfirmation, true);
   ArraySetAsSeries(LongStopGuide, true);
   ArraySetAsSeries(ShortStopGuide, true);
   ArraySetAsSeries(TrendState, true);
   ArraySetAsSeries(DailyOpenLine, true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Main calculation.                                                |
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
   int requiredHistory = SlowEMAPeriod + PriorPivotSearchBars + (PivotStrength * 2) + ATRPeriod + 10;
   if(rates_total < requiredHistory)
      return 0;

   // The oldest bar that can be safely evaluated while still allowing
   // an older pivot to be found within PriorPivotSearchBars.
   int maxSignalBar = (int)MathMin(MaximumBarsToProcess,
                                   rates_total - PriorPivotSearchBars - PivotStrength - 2);
   if(maxSignalBar < 1)
      return 0;

   if(prev_calculated == 0)
   {
      for(int clear = 0; clear < rates_total; clear++)
         ClearBar(clear);
   }
   else
   {
      // Clear all bars that may be recalculated or displayed by this run.
      int clearLimit = (int)MathMin(rates_total - 1,
                                    maxSignalBar + PriorPivotSearchBars + PivotStrength + 2);
      for(int clear = 0; clear <= clearLimit; clear++)
         ClearBar(clear);
   }

   // Work from old to new so historical arrows are deterministic.
   for(int bar = maxSignalBar; bar >= 1; bar--)
   {
      double dailyOpen = 0.0;
      bool hasDailyOpen = GetDailyOpenAtTime(time[bar], dailyOpen);
      if(ShowDailyOpen && hasDailyOpen)
         DailyOpenLine[bar] = dailyOpen;

      double atr = iATR(NULL, 0, ATRPeriod, bar);
      double fast = iMA(NULL, 0, FastEMAPeriod, 0, MODE_EMA, EMAPrice, bar);
      double slow = iMA(NULL, 0, SlowEMAPeriod, 0, MODE_EMA, EMAPrice, bar);
      if(atr <= 0.0 || fast == 0.0 || slow == 0.0)
         continue;

      bool htfBull = true;
      bool htfBear = true;
      if(UseHigherTimeframeFilter)
      {
         if(!GetHigherTimeframeTrend(time[bar], htfBull, htfBear))
            continue;
      }

      // A pivot at bar + PivotStrength becomes known only after the
      // currently evaluated bar has CLOSED. This deliberately avoids
      // a live, repainting pivot signal.
      int candidatePivot = bar + PivotStrength;
      bool isNewConfirmedLow  = IsConfirmedPivotLow(low, candidatePivot, rates_total);
      bool isNewConfirmedHigh = IsConfirmedPivotHigh(high, candidatePivot, rates_total);

      bool dailyBull = (!UseDailyOpenFilter || (hasDailyOpen && close[bar] > dailyOpen));
      bool dailyBear = (!UseDailyOpenFilter || (hasDailyOpen && close[bar] < dailyOpen));
      bool emaBull   = (fast > slow && close[bar] > fast);
      bool emaBear   = (fast < slow && close[bar] < fast);
      bool candleBull = (close[bar] > open[bar]);
      bool candleBear = (close[bar] < open[bar]);
      bool nearFastForBuy  = ((close[bar] - fast) <= MaximumEntryDistanceATR * atr);
      bool nearFastForSell = ((fast - close[bar]) <= MaximumEntryDistanceATR * atr);

      // Bullish structure: newest confirmed low is higher than the prior low.
      if(isNewConfirmedLow && dailyBull && emaBull && htfBull && candleBull && nearFastForBuy)
      {
         int priorLow = FindPreviousPivotLow(low, candidatePivot, rates_total);
         if(priorLow > 0)
         {
            double pivotATR = iATR(NULL, 0, ATRPeriod, candidatePivot);
            bool higherLow = (pivotATR > 0.0 &&
                              low[candidatePivot] > low[priorLow] + MinimumStructureGapATR * pivotATR);
            if(higherLow)
            {
               BuyConfirmation[bar] = low[bar] - ArrowOffsetATR * atr;
               LongStopGuide[bar] = low[candidatePivot];
               TrendState[bar] = 1.0;
            }
         }
      }

      // Bearish structure: newest confirmed high is lower than the prior high.
      if(isNewConfirmedHigh && dailyBear && emaBear && htfBear && candleBear && nearFastForSell)
      {
         int priorHigh = FindPreviousPivotHigh(high, candidatePivot, rates_total);
         if(priorHigh > 0)
         {
            double pivotATR = iATR(NULL, 0, ATRPeriod, candidatePivot);
            bool lowerHigh = (pivotATR > 0.0 &&
                              high[candidatePivot] < high[priorHigh] - MinimumStructureGapATR * pivotATR);
            if(lowerHigh)
            {
               SellConfirmation[bar] = high[bar] + ArrowOffsetATR * atr;
               ShortStopGuide[bar] = high[candidatePivot];
               TrendState[bar] = -1.0;
            }
         }
      }
   }

   // Keep the Daily Open visible through the currently forming bar too.
   if(ShowDailyOpen)
   {
      double currentDailyOpen = 0.0;
      if(GetDailyOpenAtTime(time[0], currentDailyOpen))
         DailyOpenLine[0] = currentDailyOpen;
   }

   // Alert only for the last completed chart candle; never alert from bar 0.
   if(BuyConfirmation[1] != EMPTY_VALUE && time[1] != LastBuyAlertTime)
   {
      Notify(true, time[1], close[1]);
      LastBuyAlertTime = time[1];
   }
   if(SellConfirmation[1] != EMPTY_VALUE && time[1] != LastSellAlertTime)
   {
      Notify(false, time[1], close[1]);
      LastSellAlertTime = time[1];
   }

   return rates_total;
}
//+------------------------------------------------------------------+
