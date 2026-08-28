//+------------------------------------------------------------------+
//|                                               BuyLowSellHigh.mq4 |
//|         Mean-reversion "Buy Low / Sell High" signal indicator    |
//|                                                                  |
//|  Plots a BUY arrow when price becomes extremely oversold and a   |
//|  SELL arrow when price becomes extremely overbought, using one   |
//|  of three selectable engines:                                    |
//|                                                                  |
//|    SIG_RSI_BB : RSI oversold/overbought + Bollinger Band pierce  |
//|    SIG_STOCH  : Stochastic %K/%D cross out of an extreme zone    |
//|    SIG_ZSCORE : statistical Z-Score of price vs its rolling mean |
//|                                                                  |
//|  An optional long-SMA trend filter only allows dips to be bought |
//|  in uptrends and rallies to be sold in downtrends ("buy low /    |
//|  sell high" in the direction of the bigger picture).             |
//|                                                                  |
//|  Signals are evaluated on CLOSED bars by default -> no repaint.  |
//|                                                                  |
//|  Buffers (readable via iCustom, e.g. by BuyLowSellHigh_EA):      |
//|    buffer 0 : buy arrow price  (EMPTY_VALUE when no signal)      |
//|    buffer 1 : sell arrow price (EMPTY_VALUE when no signal)      |
//+------------------------------------------------------------------+
#property copyright   "BuyLowSellHigh - educational example"
#property link        ""
#property version     "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1  clrLime
#property indicator_color2  clrOrangeRed
#property indicator_width1  2
#property indicator_width2  2

//--- signal engines
enum EnumSignalMode
  {
   SIG_RSI_BB = 0,   // RSI + Bollinger Bands
   SIG_STOCH  = 1,   // Stochastic cross from extreme
   SIG_ZSCORE = 2    // Z-Score of price
  };

//--- inputs: SIGNAL ENGINE -----------------------------------------
//  NOTE: the EA passes this input block (in this exact order) to
//  iCustom(). Do not reorder without updating the EA as well.
input EnumSignalMode InpMode            = SIG_RSI_BB;  // Signal mode
input int            InpRsiPeriod       = 14;          // RSI: period
input double         InpRsiBuyLevel     = 30.0;        // RSI: oversold level (buy zone)
input double         InpRsiSellLevel    = 70.0;        // RSI: overbought level (sell zone)
input int            InpBBPeriod        = 20;          // Bollinger: period
input double         InpBBDeviation     = 2.0;         // Bollinger: standard deviations
input int            InpStochK          = 14;          // Stochastic: %K period
input int            InpStochD          = 3;           // Stochastic: %D period
input int            InpStochSlowing    = 3;           // Stochastic: slowing
input double         InpStochBuyLevel   = 20.0;        // Stochastic: oversold level
input double         InpStochSellLevel  = 80.0;        // Stochastic: overbought level
input int            InpZWindow         = 100;         // Z-Score: rolling window (bars)
input double         InpZLevel          = 2.0;         // Z-Score: entry level (e.g. 2.0)
input bool           InpUseTrendFilter  = true;        // Trend filter on/off
input int            InpTrendPeriod     = 200;         // Trend filter: SMA period
input bool           InpSignalOnClose   = true;        // Signal on closed bar only (no repaint)
input int            InpMaxBars         = 2000;        // Max bars to scan (0 = all history)

//--- inputs: VISUALS & ALERTS --------------------------------------
input double         InpArrowGapATR     = 0.35;        // Arrow gap from bar (x ATR14)
input int            InpArrowWidth      = 2;           // Arrow width
input bool           InpAlertPopup      = true;        // Popup alert
input bool           InpAlertSound      = false;       // Sound alert
input string         InpSoundFile       = "alert.wav"; // Sound file (in Sounds folder)
input bool           InpAlertPush       = false;       // Push notification
input bool           InpAlertEmail      = false;       // E-mail alert
input bool           InpShowInfo        = true;        // Show info line on chart

//--- indicator buffers
double BuyBuf[];
double SellBuf[];

//--- state
datetime g_lastAlertTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorShortName("BuyLowSellHigh(" + ModeName(InpMode) + ")");
   IndicatorDigits(Digits);

   SetIndexBuffer(0, BuyBuf);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, InpArrowWidth, clrLime);
   SetIndexArrow(0, 233);                      // up arrow
   SetIndexLabel(0, "Buy low signal");
   SetIndexEmptyValue(0, EMPTY_VALUE);

   SetIndexBuffer(1, SellBuf);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, InpArrowWidth, clrOrangeRed);
   SetIndexArrow(1, 234);                      // down arrow
   SetIndexLabel(1, "Sell high signal");
   SetIndexEmptyValue(1, EMPTY_VALUE);

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }
//+------------------------------------------------------------------+
//| Main calculation                                                 |
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
   int warm = WarmupBars();
   if(rates_total <= warm + 2)
      return(0);

   int limit;
   if(prev_calculated <= 0)
     {
      //--- first run: fill the whole (limited) history
      limit = rates_total - warm - 1;
      if(InpMaxBars > 0 && limit > InpMaxBars)
         limit = InpMaxBars;
      ArrayInitialize(BuyBuf, EMPTY_VALUE);
      ArrayInitialize(SellBuf, EMPTY_VALUE);
     }
   else
     {
      //--- 0 on the same bar, >=1 right after a new bar opens
      limit = rates_total - prev_calculated;
      if(limit > rates_total - warm - 1)
         limit = rates_total - warm - 1;
     }

   for(int i = limit; i >= 0; i--)
     {
      BuyBuf[i]  = EMPTY_VALUE;
      SellBuf[i] = EMPTY_VALUE;

      //--- closed-bar mode: never draw on the still-forming bar (no repaint)
      if(InpSignalOnClose && i == 0)
         continue;

      bool buyEdge  = false;
      bool sellEdge = false;

      switch(InpMode)
        {
         case SIG_RSI_BB:   // RSI extreme + Bollinger pierce, arrow on zone entry
          {
           double rsi0  = iRSI(NULL, 0, InpRsiPeriod, PRICE_CLOSE, i);
           double rsi1  = iRSI(NULL, 0, InpRsiPeriod, PRICE_CLOSE, i + 1);
           double bbLo0 = iBands(NULL, 0, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_LOWER, i);
           double bbUp0 = iBands(NULL, 0, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_UPPER, i);
           double bbLo1 = iBands(NULL, 0, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_LOWER, i + 1);
           double bbUp1 = iBands(NULL, 0, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_UPPER, i + 1);

           bool buyZone   = (rsi0 < InpRsiBuyLevel  && close[i] < bbLo0);
           bool sellZone  = (rsi0 > InpRsiSellLevel && close[i] > bbUp0);
           bool buyZoneP  = (rsi1 < InpRsiBuyLevel  && close[i + 1] < bbLo1);
           bool sellZoneP = (rsi1 > InpRsiSellLevel && close[i + 1] > bbUp1);

           buyEdge  = buyZone  && !buyZoneP;
           sellEdge = sellZone && !sellZoneP;
           break;
          }

         case SIG_STOCH:   // %K crosses %D while leaving an extreme zone
          {
           double k0 = iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, PRICE_CLOSE, MODE_MAIN,   i);
           double d0 = iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, PRICE_CLOSE, MODE_SIGNAL, i);
           double k1 = iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, PRICE_CLOSE, MODE_MAIN,   i + 1);
           double d1 = iStochastic(NULL, 0, InpStochK, InpStochD, InpStochSlowing, MODE_SMA, PRICE_CLOSE, MODE_SIGNAL, i + 1);

           bool crossUp   = (k0 > d0 && k1 <= d1);
           bool crossDown = (k0 < d0 && k1 >= d1);

           buyEdge  = crossUp   && (k1 < InpStochBuyLevel);
           sellEdge = crossDown && (k1 > InpStochSellLevel);
           break;
          }

         case SIG_ZSCORE:  // price stretched statistically far from its mean
          {
           double z0 = ZScore(i, close, rates_total);
           double z1 = ZScore(i + 1, close, rates_total);

           buyEdge  = (z0 < -InpZLevel && z1 >= -InpZLevel);
           sellEdge = (z0 >  InpZLevel && z1 <=  InpZLevel);
           break;
          }
        }

      if(buyEdge || sellEdge)
        {
         bool allowBuy  = true;
         bool allowSell = true;
         if(InpUseTrendFilter)
           {
            double ma = iMA(NULL, 0, InpTrendPeriod, 0, MODE_SMA, PRICE_CLOSE, i);
            allowBuy  = (close[i] > ma);   // buy dips only above the long SMA
            allowSell = (close[i] < ma);   // sell rallies only below the long SMA
           }
         if(buyEdge && allowBuy)
            BuyBuf[i] = low[i] - ArrowGap(i);
         if(sellEdge && allowSell)
            SellBuf[i] = high[i] + ArrowGap(i);
        }
     }

   //--- alerts (real time only, once per bar)
   int s = InpSignalOnClose ? 1 : 0;
   if(prev_calculated <= 0)
     {
      // avoid an alert storm right after attaching
      if(s < rates_total)
         g_lastAlertTime = time[s];
     }
   else
     {
      if(s < rates_total)
        {
         if(BuyBuf[s] != EMPTY_VALUE && time[s] != g_lastAlertTime)
           {
            DoAlert("BUY", close[s], time[s]);
            g_lastAlertTime = time[s];
           }
         else if(SellBuf[s] != EMPTY_VALUE && time[s] != g_lastAlertTime)
           {
            DoAlert("SELL", close[s], time[s]);
            g_lastAlertTime = time[s];
           }
        }
     }

   //--- optional one-line info
   if(InpShowInfo)
     {
      string txt = StringFormat("BuyLowSellHigh | mode=%s | trend filter=%s(%d) | last BUY: %s | last SELL: %s",
                                ModeName(InpMode),
                                (InpUseTrendFilter ? "ON" : "OFF"),
                                InpTrendPeriod,
                                LastSignalText(BuyBuf, time, close, rates_total),
                                LastSignalText(SellBuf, time, close, rates_total));
      Comment(txt);
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Number of bars the engines need before signals are valid         |
//+------------------------------------------------------------------+
int WarmupBars()
  {
   int w = InpRsiPeriod + InpBBPeriod + 2;
   if(InpStochK + InpStochD + InpStochSlowing + 2 > w)
      w = InpStochK + InpStochD + InpStochSlowing + 2;
   if(InpZWindow + 2 > w)
      w = InpZWindow + 2;
   if(InpUseTrendFilter && InpTrendPeriod + 2 > w)
      w = InpTrendPeriod + 2;
   return(w);
  }
//+------------------------------------------------------------------+
//| Rolling Z-Score of close[shift] vs the InpZWindow bars before it |
//+------------------------------------------------------------------+
double ZScore(const int shift, const double &close[], const int total)
  {
   int w = InpZWindow;
   if(shift + w > total)
      w = total - shift;
   if(w < 2)
      return(0.0);

   double sum = 0.0;
   for(int j = 0; j < w; j++)
      sum += close[shift + j];
   double mean = sum / w;

   double varSum = 0.0;
   for(int k = 0; k < w; k++)
     {
      double d = close[shift + k] - mean;
      varSum += d * d;
     }
   double sd = MathSqrt(varSum / w);
   if(sd <= 0.0)
      return(0.0);

   return((close[shift] - mean) / sd);
  }
//+------------------------------------------------------------------+
//| Vertical gap used to place arrows away from the candle           |
//+------------------------------------------------------------------+
double ArrowGap(const int shift)
  {
   double atr = iATR(NULL, 0, 14, shift);
   double gap = atr * InpArrowGapATR;
   if(gap < Point)
      gap = Point;
   return(gap);
  }
//+------------------------------------------------------------------+
//| Mode name for the chart label                                    |
//+------------------------------------------------------------------+
string ModeName(const EnumSignalMode mode)
  {
   switch(mode)
     {
      case SIG_STOCH:  return("Stoch");
      case SIG_ZSCORE: return("Z-Score");
      default:         return("RSI+BB");
     }
  }
//+------------------------------------------------------------------+
//| Text of the most recent arrow of a buffer (search back 500 bars) |
//+------------------------------------------------------------------+
string LastSignalText(const double &buf[], const datetime &time[], const double &close[], const int total)
  {
   int maxScan = 500;
   if(maxScan > total)
      maxScan = total;
   for(int i = 0; i < maxScan; i++)
     {
      if(buf[i] != EMPTY_VALUE)
         return(StringFormat("%s @ %s", TimeToString(time[i], TIME_DATE | TIME_MINUTES), DoubleToString(close[i], Digits)));
     }
   return("-");
  }
//+------------------------------------------------------------------+
//| Fire the enabled alert channels                                  |
//+------------------------------------------------------------------+
void DoAlert(const string direction, const double price, const datetime barTime)
  {
   string msg = StringFormat("BuyLowSellHigh %s %s: %s signal @ %s (%s)",
                             Symbol(), TimeFrameName(Period()), direction,
                             DoubleToString(price, Digits),
                             TimeToString(barTime, TIME_DATE | TIME_MINUTES));

   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertSound)
      PlaySound(InpSoundFile);
   if(InpAlertPush)
      SendNotification(msg);
   if(InpAlertEmail)
      SendMail("BuyLowSellHigh signal", msg);
  }
//+------------------------------------------------------------------+
//| Timeframe to text                                                |
//+------------------------------------------------------------------+
string TimeFrameName(const int tf)
  {
   switch(tf)
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
   return("M" + IntegerToString(tf));
  }
//+------------------------------------------------------------------+
