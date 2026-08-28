//+------------------------------------------------------------------+
//|                                            WPR_SwingBreakout.mq4 |
//|  Williams %R swing-breakout arrows (stop & reverse).              |
//|                                                                   |
//|  Clean rewrite of the decompiled "%R / Terminal Signal / GGT"     |
//|  arrow indicator.  Same trading idea, none of the original bugs.  |
//|  See indicators/README.md for the full list of fixes.             |
//+------------------------------------------------------------------+
#property copyright "Rewrite of a decompiled %R swing indicator"
#property version   "2.00"
#property strict
#property description "Williams %R swing breakout arrows - non-repainting, closed-bar signals"

#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "Buy"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  Lime
#property indicator_width1  3

#property indicator_label2  "Sell"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  Red
#property indicator_width2  3

//+------------------------------------------------------------------+
//| How the breakout is confirmed                                     |
//+------------------------------------------------------------------+
enum ENUM_BREAKOUT_MODE
  {
   BRK_WICK  = 0, // Wick - fires as soon as the swing level is pierced
   BRK_CLOSE = 1  // Close - stricter, ignores wick spikes (recommended)
  };

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input ENUM_BREAKOUT_MODE InpMode        = BRK_CLOSE; // Breakout confirmation
input int    InpWPRPeriod               = 14;        // Williams %R period
input double InpLevelUp                 = -20.0;     // Upper band (e.g. -20)
input double InpLevelDn                 = -80.0;     // Lower band (e.g. -80)
input int    InpLookback                = 1000;      // Bars recalculated (0 = all)

input bool   InpClosedBarOnly           = true;      // Signals on closed bars only
input bool   InpUseTrendFilter          = false;     // Filter by moving average
input int    InpTrendPeriod             = 200;       // Trend MA period
input ENUM_MA_METHOD InpTrendMethod     = MODE_EMA;  // Trend MA method

input bool   InpATROffset               = true;      // ATR based arrow offset
input double InpATRMultiplier           = 0.5;       // ATR multiplier
input int    InpATRPeriod               = 14;        // ATR period
input double InpOffsetPips              = 5.0;       // Fixed offset (pips) if ATR off

input bool   InpAlerts                  = true;      // Pop-up alert
input bool   InpComment                 = true;      // Chart comment
input bool   InpPush                    = false;     // Push notification
input bool   InpSound                   = true;      // Sound
input string InpSoundFile               = "news.wav";// Sound file

//+------------------------------------------------------------------+
//| Buffers and globals                                               |
//+------------------------------------------------------------------+
double   BufUp[];   // buy arrows
double   BufDn[];   // sell arrows

datetime g_lastBar   = 0;   // time of the last processed bar
datetime g_alertBuy  = 0;   // bar time of the last BUY notification
datetime g_alertSell = 0;   // bar time of the last SELL notification
int      g_digits    = 5;
double   g_point     = 0.0;
double   g_pip       = 0.0;
string   g_shortName = "";

//+------------------------------------------------------------------+
//| Vertical offset used to keep the arrow clear of the candle        |
//+------------------------------------------------------------------+
double ArrowOffset(const int shift)
  {
   if(InpATROffset)
     {
      double atr = iATR(NULL, 0, InpATRPeriod, shift);
      if(atr > 0.0)
         return(atr * InpATRMultiplier);
     }
   return(InpOffsetPips * g_pip);
  }

//+------------------------------------------------------------------+
//| Readable timeframe name                                           |
//+------------------------------------------------------------------+
string TFToStr(const int period)
  {
   switch(period)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M2:  return("M2");
      case PERIOD_M3:  return("M3");
      case PERIOD_M4:  return("M4");
      case PERIOD_M5:  return("M5");
      case PERIOD_M6:  return("M6");
      case PERIOD_M10: return("M10");
      case PERIOD_M12: return("M12");
      case PERIOD_M15: return("M15");
      case PERIOD_M20: return("M20");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H2:  return("H2");
      case PERIOD_H3:  return("H3");
      case PERIOD_H4:  return("H4");
      case PERIOD_H6:  return("H6");
      case PERIOD_H8:  return("H8");
      case PERIOD_H12: return("H12");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
     }
   return("TF" + IntegerToString(period));
  }

//+------------------------------------------------------------------+
//| Fire every configured notification channel once per signal bar    |
//+------------------------------------------------------------------+
void Notify(const string side, const datetime barTime, const double price)
  {
   string head = g_shortName + " - " + side;
   string msg  = head + "\n"
               + "Symbol: " + _Symbol + "    Period: " + TFToStr(Period()) + "\n"
               + "Bar: "    + TimeToString(barTime, TIME_DATE | TIME_MINUTES) + "\n"
               + "Close: "  + DoubleToString(price, g_digits) + "\n"
               + "Bid: "    + DoubleToString(Bid, g_digits)
               + "    Ask: " + DoubleToString(Ask, g_digits);

   if(InpComment) Comment(msg);
   if(InpAlerts)  Alert(head + " - " + _Symbol + " " + TFToStr(Period())
                        + " @ " + DoubleToString(price, g_digits));
   if(InpPush)    SendNotification(msg);
   if(InpSound && InpSoundFile != "") PlaySound(InpSoundFile);
  }

//+------------------------------------------------------------------+
//| Custom indicator initialization                                   |
//+------------------------------------------------------------------+
int OnInit(void)
  {
//--- validate inputs
   if(InpWPRPeriod < 2)
     {
      Print("WPR period must be >= 2");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpLevelUp <= InpLevelDn)
     {
      Print("Upper level must be greater than the lower level (e.g. -20 and -80)");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpLookback < 0)
     {
      Print("Lookback cannot be negative");
      return(INIT_PARAMETERS_INCORRECT);
     }

//--- buffers
   SetIndexBuffer(0, BufUp);
   SetIndexBuffer(1, BufDn);
   ArrayInitialize(BufUp, EMPTY_VALUE);
   ArrayInitialize(BufDn, EMPTY_VALUE);
   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexArrow(0, 233);
   SetIndexArrow(1, 234);
   SetIndexLabel(0, "Buy");
   SetIndexLabel(1, "Sell");
   SetIndexDrawBegin(0, InpWPRPeriod + 1);
   SetIndexDrawBegin(1, InpWPRPeriod + 1);

//--- symbol properties
   g_digits = (int)MarketInfo(_Symbol, MODE_DIGITS);
   g_point  = MarketInfo(_Symbol, MODE_POINT);
   if(g_digits <= 0) g_digits = Digits;
   if(g_point  <= 0.0) g_point = Point;
   //--- a "pip" is 10 points on 3/5 digit brokers
   g_pip = (g_digits == 3 || g_digits == 5) ? g_point * 10.0 : g_point;

   g_shortName = "WPR Swing Breakout (" + IntegerToString(InpWPRPeriod) + ","
                 + DoubleToString(InpLevelUp, 0) + "," + DoubleToString(InpLevelDn, 0) + ")";
   IndicatorSetString(INDICATOR_SHORTNAME, g_shortName);
   IndicatorDigits(g_digits);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
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
//--- enough history for a single %R value plus one swing?
   if(rates_total <= InpWPRPeriod + 2)
      return(0);

//--- recalculate once per bar (and once after every load / history refresh)
   bool newBar = (prev_calculated == 0) || (time[0] != g_lastBar);
   if(newBar)
      g_lastBar = time[0];

//--- closed-bar mode: nothing can change between two ticks of the same bar
   if(!newBar && InpClosedBarOnly)
      return(rates_total);

//--- calculation window
   int available = rates_total - InpWPRPeriod;                        // bars with a full %R lookback
   int bars      = (InpLookback > 0) ? (int)MathMin(InpLookback, available) : available;
   int start     = bars - 1;                                          // oldest bar of the window
   int stop      = InpClosedBarOnly ? 1 : 0;                          // newest bar to evaluate
   if(start < stop)
      return(rates_total);

//--- wipe the buffers, then rebuild them deterministically (oldest -> newest).
//    This is what makes it non-repainting: the value of a closed bar is
//    recomputed from scratch every time and can never drift.
   ArrayInitialize(BufUp, EMPTY_VALUE);
   ArrayInitialize(BufDn, EMPTY_VALUE);

//--- state machine, reset on every recalculation
   int    leg         = 0;      // +1: %R last reached the upper band, -1: lower band, 0: unknown
   double curHigh     = 0.0;    // extreme of the current up leg
   double curLow      = 0.0;    // extreme of the current down leg
   double prevHigh    = 0.0;    // extreme of the last completed up leg
   double prevLow     = 0.0;    // extreme of the last completed down leg
   bool   hasPrevHigh = false;
   bool   hasPrevLow  = false;
   int    trend       = 0;      // +1 long / -1 short (stop & reverse latch)

   for(int i = start; i >= stop; i--)
     {
      //--- Williams %R, computed inline: (HH - Close) / (HH - LL) * -100
      double hh = high[i];
      double ll = low[i];
      for(int k = 1; k < InpWPRPeriod; k++)
        {
         if(high[i + k] > hh) hh = high[i + k];
         if(low[i + k]  < ll) ll = low[i + k];
        }
      double den = hh - ll;
      double wpr = (den > 0.0) ? -100.0 * (hh - close[i]) / den : -50.0;

      //--- leg transitions: a leg ends when %R reaches the opposite band
      if(wpr >= InpLevelUp && leg != 1)
        {
         if(leg == -1) { prevLow = curLow; hasPrevLow = true; }   // down leg finished
         leg     = 1;
         curHigh = high[i];
        }
      else
         if(wpr <= InpLevelDn && leg != -1)
           {
            if(leg == 1) { prevHigh = curHigh; hasPrevHigh = true; } // up leg finished
            leg    = -1;
            curLow = low[i];
           }

      //--- running extremes of the current leg
      if(leg == 1)  { if(high[i] > curHigh) curHigh = high[i]; }
      if(leg == -1) { if(low[i]  < curLow)  curLow  = low[i];  }

      //--- optional trend filter
      bool bullOk = true;
      bool bearOk = true;
      if(InpUseTrendFilter && InpTrendPeriod > 1)
        {
         double ma = iMA(NULL, 0, InpTrendPeriod, 0, InpTrendMethod, PRICE_CLOSE, i);
         if(ma > 0.0)
           {
            bullOk = (close[i] > ma);
            bearOk = (close[i] < ma);
           }
        }

      //--- stop & reverse: first break of the previous swing extreme after a reversal
      if(leg == 1 && trend != 1 && hasPrevHigh && bullOk)
        {
         double lvl = (InpMode == BRK_CLOSE) ? close[i] : high[i];
         if(lvl > prevHigh)
           {
            BufUp[i] = low[i] - ArrowOffset(i);
            trend    = 1;
           }
        }

      if(leg == -1 && trend != -1 && hasPrevLow && bearOk)
        {
         double lvl = (InpMode == BRK_CLOSE) ? close[i] : low[i];
         if(lvl < prevLow)
           {
            BufDn[i] = high[i] + ArrowOffset(i);
            trend    = -1;
           }
        }
     }

//--- notifications: deduplicated by bar time, not by price
   if(InpAlerts || InpComment || InpPush || InpSound)
     {
      int      sigBar   = InpClosedBarOnly ? 1 : 0;
      datetime barTime  = time[sigBar];

      if(BufUp[sigBar] != EMPTY_VALUE && g_alertBuy != barTime)
        {
         g_alertBuy = barTime;
         Notify("BUY", barTime, close[sigBar]);
        }
      if(BufDn[sigBar] != EMPTY_VALUE && g_alertSell != barTime)
        {
         g_alertSell = barTime;
         Notify("SELL", barTime, close[sigBar]);
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
