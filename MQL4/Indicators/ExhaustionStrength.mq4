//+------------------------------------------------------------------+
//|                                            ExhaustionStrength.mq4 |
//|         Clean rewrite of the decompiled "Modified LexLampard"     |
//|         MQL4 indicator (record-extreme exhaustion ratio).         |
//+------------------------------------------------------------------+
#property copyright   "Rewrite - original concept credited to LexLampard (2016)"
#property version     "2.01"
#property description "Counter-trend exhaustion indicator."
#property description "Scans backwards over Len bars accumulating closes at"
#property description "record highs / record lows. A one-sided ratio means the"
#property description "preceding move is stretched: BUY after a fall, SELL after a rise."
#property strict

#property indicator_chart_window
#property indicator_buffers 4

//--- Plot 0: Buy arrow
#property indicator_color1  clrDodgerBlue
#property indicator_width1  3
//--- Plot 1: Sell arrow
#property indicator_color2  clrCrimson
#property indicator_width2  3
//--- Plots 2/3 are DRAW_NONE (data only, readable via iCustom)
//--- NOTE: no indicator_level properties - the originals were dead
//--- leftovers from a separate-window version and did nothing here.

//+------------------------------------------------------------------+
//| Inputs (old name -> new name mapping is in README.md)             |
//+------------------------------------------------------------------+
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_CURRENT; // Signal timeframe (>= chart timeframe)
input int             InpLength          = 15;             // Lookback in signal bars (old: Len)
input double          InpSignalLevel     = 3.0;            // Ratio threshold (old: UrovenSignal=6, see README)
input int             InpHistoryBars     = 500;            // Signal bars to evaluate (0 = all; old: HistoryBars)
input bool            InpUseHighLow      = true;           // true: High/Low, false: body extremes (old: ModeHL)
input bool            InpAlternating     = true;           // Alternate BUY/SELL signals (old: sUp/sDn behaviour)
input bool            InpClosedBarOnly   = true;           // Signals only on closed signal bars (no repaint)
input int             InpATRPeriod       = 14;             // ATR period for arrow offset
input double          InpArrowOffsetATR  = 0.15;           // Arrow offset = ATR * this (replaces Move_Arrow*Point)
input int             InpArrowBuyCode    = 233;            // Buy arrow Wingdings code (old: ArrowBuyCode)
input int             InpArrowSellCode   = 234;            // Sell arrow Wingdings code (old: ArrowSellCode)
input int             InpArrowBuyWidth   = 3;              // Buy arrow width
input int             InpArrowSellWidth  = 3;              // Sell arrow width
input color           InpArrowBuyColor   = clrDodgerBlue;  // Buy arrow color
input color           InpArrowSellColor  = clrCrimson;     // Sell arrow color
input bool            InpAlertPopup      = false;          // Popup alert on new signal (old: alert)
input bool            InpAlertSound      = false;          // Sound alert (old: sound)
input string          InpSoundFile       = "alert.wav";    // Sound file
input bool            InpAlertEmail      = false;          // Email alert (old: email)
input bool            InpAlertPush       = false;          // Push notification
input bool            InpShowDiagnostics = true;           // Show on-chart diagnostics (turn off once working)

//+------------------------------------------------------------------+
//| Buffers                                                           |
//|  0: Buy arrow      1: Sell arrow                                  |
//|  2: FallStrength   (old UP: sum@record-highs / sum@record-lows,   |
//|                     scanned newest->oldest, i.e. strength of the  |
//|                     preceding FALL)                               |
//|  3: RiseStrength   (old DN: exact reciprocal of buffer 2)         |
//+------------------------------------------------------------------+
double g_buyBuffer[];
double g_sellBuffer[];
double g_fallBuffer[];
double g_riseBuffer[];

int      g_signalTF      = 0;     // Resolved signal timeframe (minutes-style int)
datetime g_lastAlertBar  = 0;     // Open time of last alerted signal bar
bool     g_alertPrimed   = false; // Suppress alert for pre-existing signal on attach

#define SIGNAL_BUY   1
#define SIGNAL_SELL -1

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate inputs (the original validated nothing)
   if(InpLength < 2)
   {
      Print(__FUNCTION__, ": InpLength must be >= 2");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpSignalLevel <= 1.0)
   {
      Print(__FUNCTION__, ": InpSignalLevel must be > 1.0 (it is a ratio)");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpATRPeriod < 1 || InpArrowOffsetATR < 0.0)
   {
      Print(__FUNCTION__, ": Invalid ATR settings");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Resolve signal timeframe
   g_signalTF = (InpSignalTimeframe == PERIOD_CURRENT) ? Period()
                                                       : (int)InpSignalTimeframe;

   //--- One arrow per chart bar must be unambiguous: signal TF may not
   //--- be lower than the chart TF (several signals would collide on
   //--- a single chart bar). Attach to a chart <= signal timeframe.
   if(PeriodSeconds((ENUM_TIMEFRAMES)g_signalTF) < PeriodSeconds((ENUM_TIMEFRAMES)Period()))
   {
      Print(__FUNCTION__, ": Signal timeframe must be >= chart timeframe. ",
            "Attach the indicator to a lower-or-equal timeframe chart.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   //--- Bind buffers
   SetIndexBuffer(0, g_buyBuffer);
   SetIndexBuffer(1, g_sellBuffer);
   SetIndexBuffer(2, g_fallBuffer);
   SetIndexBuffer(3, g_riseBuffer);

   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, InpArrowBuyWidth, InpArrowBuyColor);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, InpArrowSellWidth, InpArrowSellColor);
   SetIndexStyle(2, DRAW_NONE);
   SetIndexStyle(3, DRAW_NONE);

   SetIndexArrow(0, InpArrowBuyCode);
   SetIndexArrow(1, InpArrowSellCode);

   //--- Fixed: every buffer now gets a proper empty value and is
   //--- cleared each calculation (original never cleared anything,
   //--- so stale arrows survived recalculations).
   for(int b = 0; b < 4; b++)
      SetIndexEmptyValue(b, EMPTY_VALUE);

   SetIndexLabel(0, "Buy (exhaustion)");
   SetIndexLabel(1, "Sell (exhaustion)");
   SetIndexLabel(2, "FallStrength (old UP)");
   SetIndexLabel(3, "RiseStrength (old DN)");

   IndicatorShortName(StringFormat("ExhaustionStrength(%d,%.1f,%s)",
                                   InpLength, InpSignalLevel,
                                   EnumToString((ENUM_TIMEFRAMES)g_signalTF)));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//| Map a signal bar (series shift on the signal TF) to a chart-bar   |
//| index in OnCalculate's non-series arrays.                         |
//|                                                                   |
//| Same TF : identical shift.                                        |
//| HTF     : the arrow belongs where the signal became knowable -    |
//|           the first chart bar at/after the signal bar's close.    |
//| Returns -1 when there is no such chart bar yet.                   |
//+------------------------------------------------------------------+
int ChartIndexForSignal(const int signalShift, const datetime signalTime,
                        const int rates_total)
{
   int chartShift;
   if(g_signalTF == Period())
   {
      chartShift = signalShift;
   }
   else
   {
      datetime knowableAt = signalTime + PeriodSeconds((ENUM_TIMEFRAMES)g_signalTF);
      chartShift = iBarShift(_Symbol, Period(), knowableAt, false);
      if(chartShift < 0)
         return(-1);
   }
   if(chartShift >= rates_total)
      return(-1);
   return(rates_total - 1 - chartShift); // series shift -> non-series index
}

//+------------------------------------------------------------------+
//| Fire alerts exactly once per signal bar (the original checked     |
//| sUp/sDn AFTER toggling them, so its alerts could never fire).     |
//+------------------------------------------------------------------+
void FireAlert(const int direction, const datetime barTime,
               const double fallStrength, const double riseStrength)
{
   string text = StringFormat("%s %s: %s exhaustion signal at %s (FallStrength=%.2f, RiseStrength=%.2f)",
                              _Symbol,
                              EnumToString((ENUM_TIMEFRAMES)g_signalTF),
                              (direction == SIGNAL_BUY ? "BUY" : "SELL"),
                              TimeToString(barTime, TIME_DATE | TIME_MINUTES),
                              fallStrength, riseStrength);
   Print(text);
   if(IsTesting())
      return; // keep the tester log clean, as the original intended
   if(InpAlertPopup)
      Alert(text);
   if(InpAlertSound)
      PlaySound(InpSoundFile);
   if(InpAlertEmail && !SendMail("ExhaustionStrength " + _Symbol, text))
      Print(__FUNCTION__, ": SendMail failed, error ", GetLastError());
   if(InpAlertPush && !SendNotification(text))
      Print(__FUNCTION__, ": SendNotification failed, error ", GetLastError());
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
   if(rates_total < 2)
      return(0);

   //--- Load signal-timeframe bars directly (fixed: the original
   //--- manually resampled TF1 bars, treating the timeframe's minute
   //--- value as a bar count and overflowing a fixed [][240] array
   //--- for any TF above H4. CopyRates makes all of that unnecessary.)
   int available = iBars(_Symbol, g_signalTF);
   if(available < InpLength + 1)
      return(0); // not enough signal history yet; retry on next tick

   int wanted = (InpHistoryBars <= 0) ? available
                                      : MathMin(available, InpHistoryBars);
   //--- Need at least one fully evaluable bar
   if(wanted < InpLength + 1)
      wanted = MathMin(available, InpLength + 1);

   MqlRates sig[];
   ArraySetAsSeries(sig, true);
   int copied = CopyRates(_Symbol, g_signalTF, 0, wanted, sig);
   if(copied < InpLength + 1)
      return(0); // history not ready yet; retry on next tick

   //--- Per-signal-bar results (series indexed, like sig[])
   double sigFall[], sigRise[];
   int    sigSignal[];
   ArrayResize(sigFall, copied);
   ArrayResize(sigRise, copied);
   ArrayResize(sigSignal, copied);
   ArrayInitialize(sigFall, EMPTY_VALUE);
   ArrayInitialize(sigRise, EMPTY_VALUE);
   ArrayInitialize(sigSignal, 0);

   //--- Evaluate oldest -> newest so the alternating-signal state
   //--- machine is built chronologically (the original let its
   //--- sUp/sDn globals leak out of the history scan in scan order).
   int lastDirection  = 0;
   int newestShift    = InpClosedBarOnly ? 1 : 0;
   int oldestShift    = copied - InpLength;

   for(int shift = oldestShift; shift >= 0; shift--)
   {
      //--- Core algorithm, preserved but made explicit.
      //--- Scan newest -> oldest over the lookback window. Walking
      //--- backwards in time after a FALL, prices rise, so "record
      //--- highs" accumulate: sumHighRecords grows. After a RISE,
      //--- "record lows" accumulate instead. Hence:
      //---   FallStrength = sumHighRecords / sumLowRecords  (old UP)
      //---   RiseStrength = 1 / FallStrength                (old DN)
      //--- Fixed: running extremes start at -DBL_MAX / +DBL_MAX
      //--- (original used 0 / 1,000,000, broken for symbols priced
      //--- above 1e6), and no stale globals leak between bars.
      double runningHigh   = -DBL_MAX;
      double runningLow    = DBL_MAX;
      double sumHighRecords = 0.0;
      double sumLowRecords  = 0.0;

      for(int k = 0; k < InpLength; k++)
      {
         int idx = shift + k; // shift, shift+1, ... = newest -> oldest
         double barHigh = InpUseHighLow ? sig[idx].high
                                        : MathMax(sig[idx].open, sig[idx].close);
         double barLow  = InpUseHighLow ? sig[idx].low
                                        : MathMin(sig[idx].open, sig[idx].close);
         double barClose = sig[idx].close;
         if(barClose <= 0.0)
            continue; // missing/bad data - never reuse a stale close

         if(barHigh > runningHigh)
         {
            runningHigh    = barHigh;
            sumHighRecords += barClose;
         }
         if(barLow < runningLow)
         {
            runningLow    = barLow;
            sumLowRecords += barClose;
         }
      }

      if(sumLowRecords <= 0.0 || sumHighRecords <= 0.0)
         continue; // insufficient valid data for this bar

      double fallStrength = sumHighRecords / sumLowRecords;
      double riseStrength = sumLowRecords / sumHighRecords;
      sigFall[shift] = fallStrength;
      sigRise[shift] = riseStrength;

      //--- Signal decision (confirmed bars only, unless disabled)
      if(shift < newestShift)
         continue;

      int candidate = 0;
      if(fallStrength >= InpSignalLevel)
         candidate = SIGNAL_BUY;   // fall looks exhausted -> buy
      else if(riseStrength >= InpSignalLevel)
         candidate = SIGNAL_SELL;  // rise looks exhausted -> sell

      if(candidate == 0)
         continue;
      if(InpAlternating && candidate == lastDirection)
         continue; // suppress repeated same-direction arrows

      sigSignal[shift] = candidate;
      lastDirection    = candidate;
   }

   //--- Clear chart buffers every call (fixed: stale arrows can no
   //--- longer survive a recalculation that no longer qualifies).
   ArrayInitialize(g_buyBuffer, EMPTY_VALUE);
   ArrayInitialize(g_sellBuffer, EMPTY_VALUE);
   ArrayInitialize(g_fallBuffer, EMPTY_VALUE);
   ArrayInitialize(g_riseBuffer, EMPTY_VALUE);

   //--- Project signal bars onto chart bars (counting for diagnostics)
   int buyCount = 0, sellCount = 0;
   for(int shift = oldestShift; shift >= 0; shift--)
   {
      if(sigFall[shift] == EMPTY_VALUE)
         continue;

      int chartIndex = ChartIndexForSignal(shift, sig[shift].time, rates_total);
      if(chartIndex < 0)
         continue;

      g_fallBuffer[chartIndex] = sigFall[shift];
      g_riseBuffer[chartIndex] = sigRise[shift];

      if(sigSignal[shift] == 0)
         continue;

      //--- Fixed: arrow offset scales with volatility (ATR) instead
      //--- of Move_Arrow * Point, which is negligible on 5-digit
      //--- symbols and huge relative to quiet instruments.
      double atr    = iATR(_Symbol, g_signalTF, InpATRPeriod, shift);
      double offset = (atr > 0.0) ? atr * InpArrowOffsetATR : 10.0 * Point;

      if(sigSignal[shift] == SIGNAL_BUY)
      {
         g_buyBuffer[chartIndex]  = low[chartIndex] - offset;
         buyCount++;
      }
      else
      {
         g_sellBuffer[chartIndex] = high[chartIndex] + offset;
         sellCount++;
      }
   }

   //--- Alerts: once per signal bar, on the newest confirmed signal
   for(int shift = newestShift; shift < copied; shift++)
   {
      if(sigSignal[shift] == 0)
         continue;

      if(!g_alertPrimed)
      {
         // First calculation after attach: adopt the existing signal
         // silently instead of alerting for a historical bar.
         g_lastAlertBar = sig[shift].time;
         g_alertPrimed  = true;
      }
      else if(g_lastAlertBar != sig[shift].time)
      {
         g_lastAlertBar = sig[shift].time;
         FireAlert(sigSignal[shift], sig[shift].time,
                   sigFall[shift], sigRise[shift]);
      }
      break; // only the newest signal is alertable
   }

   //--- Diagnostics: the #1 support question is "no arrows", so make
   //--- the reason visible on the chart instead of silent.
   double maxFall = 0.0, maxRise = 0.0;
   for(int shift = oldestShift; shift >= 0; shift--)
   {
      if(sigFall[shift] == EMPTY_VALUE)
         continue;
      if(sigFall[shift] > maxFall) maxFall = sigFall[shift];
      if(sigRise[shift] > maxRise) maxRise = sigRise[shift];
   }
   if(prev_calculated == 0)
      Print(StringFormat("ExhaustionStrength: evaluated %d %s bars, drew %d BUY / %d SELL arrows (max Fall=%.2f, max Rise=%.2f, level=%.2f)",
                         copied, EnumToString((ENUM_TIMEFRAMES)g_signalTF),
                         buyCount, sellCount, maxFall, maxRise, InpSignalLevel));
   if(InpShowDiagnostics)
   {
      string hint = (buyCount + sellCount == 0)
                    ? StringFormat("\n>> No bar crossed the level. Strongest seen: Fall %.2f / Rise %.2f.\n>> Lower InpSignalLevel (try 2.5) or increase InpHistoryBars to see arrows.", maxFall, maxRise)
                    : "\n>> Arrows are below/above candles - scroll back if none are on screen.";
      Comment(StringFormat("ExhaustionStrength v2.01\nSignal TF: %s | Bars evaluated: %d\nLast closed: Fall=%.2f Rise=%.2f (level %.2f)\nArrows drawn: %d BUY / %d SELL%s",
                           EnumToString((ENUM_TIMEFRAMES)g_signalTF), copied,
                           (copied > 1 && sigFall[1] != EMPTY_VALUE) ? sigFall[1] : 0.0,
                           (copied > 1 && sigRise[1] != EMPTY_VALUE) ? sigRise[1] : 0.0,
                           InpSignalLevel, buyCount, sellCount, hint));
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
