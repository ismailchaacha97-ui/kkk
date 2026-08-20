//+------------------------------------------------------------------+
//| Dynamic Swing Anchored VWAP - MT4                                |
//| Based on the TradingView Dynamic Swing Anchored VWAP by Zeiierman |
//| Original work: CC BY-NC-SA 4.0                                   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1 clrLime
#property indicator_color2 clrRed
#property indicator_color3 clrDodgerBlue
#property indicator_color4 clrOrangeRed
#property indicator_width1 2
#property indicator_width2 2
#property indicator_width3 1
#property indicator_width4 1

//--- volume source
// Real volume is frequently unavailable in MT4 Forex feeds. When selected,
// the indicator falls back to tick volume if the broker returns zero.
enum ENUM_DSV_VOLUME_MODE
{
   DSV_TICK_VOLUME = 0,
   DSV_REAL_VOLUME = 1,
   DSV_PRICE_ONLY  = 2
};

extern int    SwingPeriod           = 50;
extern double AdaptivePriceTracking = 20.0;
extern bool   AdaptAPTByATR         = false;
extern double VolatilityBias        = 10.0;
extern int    ATRPeriod             = 50;
extern double MinimumSwingATR       = 0.0;       // 0 = disabled
extern double MinimumAPT             = 5.0;
extern double MaximumAPT             = 300.0;
extern bool   UseClosedBarsOnly     = true;
extern ENUM_DSV_VOLUME_MODE VolumeMode = DSV_TICK_VOLUME;
extern int    MaxCalculationBars    = 0;         // 0 = all available bars

extern color  SwingHighColor        = clrLime;
extern color  SwingLowColor         = clrRed;
extern color  VWAPUpColor            = clrLime;
extern color  VWAPDownColor          = clrRed;
extern int    VWAPLineWidth         = 2;

extern bool   EnableAlerts           = false;
extern bool   AlertOnTrendChange     = true;
extern bool   AlertOnVWAPCross       = false;
extern bool   AlertPushNotification  = false;
extern bool   AlertEmail             = false;

//--- Entry setup: higher-timeframe trend + pullback + continuation
extern bool   EnableEntryArrows      = true;
extern ENUM_TIMEFRAMES HigherTimeframe = PERIOD_H1;
extern int    HigherTimeframeEMAPeriod = 50;
extern int    PullbackLookback       = 3;
extern double PullbackMaxDistanceATR = 0.50;
extern double ArrowOffsetATR         = 0.25;

//--- indicator buffers
double VWAPUp[];
double VWAPDown[];
double BuyArrow[];
double SellArrow[];

string PREFIX = "DSAV_Lbl_";
static datetime g_lastBar = 0;
static datetime g_lastAlert = 0;

//+------------------------------------------------------------------+
double AlphaFromAPT(double apt)
{
   apt = MathMax(1.0, apt);
   return(1.0 - MathExp(-MathLog(2.0) / apt));
}

//+------------------------------------------------------------------+
double BarVolume(const int shift, const long &tick_volume[], const long &real_volume[])
{
   if(VolumeMode == DSV_PRICE_ONLY)
      return(1.0);

   if(VolumeMode == DSV_REAL_VOLUME && real_volume[shift] > 0)
      return((double)real_volume[shift]);

   return((double)tick_volume[shift]);
}

//+------------------------------------------------------------------+
void DeleteLabels()
{
   ObjectsDeleteAll(0, PREFIX);
}

//+------------------------------------------------------------------+
void MakeSwingLabel(const string text, const int shift, const double price,
                    const color clr, const double atr)
{
   if(shift < 0 || shift >= Bars || text == "") return;

   string name = PREFIX + IntegerToString((int)Time[shift]);
   if(ObjectFind(0, name) >= 0) return;

   double y = price;
   if(StringFind(text, "H") >= 0) y += atr * 0.25;
   else                           y -= atr * 0.25;

   if(ObjectCreate(0, name, OBJ_TEXT, 0, Time[shift], y))
   {
      ObjectSetText(name, text, 8, "Arial Bold", clr);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,
                      StringFind(text, "H") >= 0 ? ANCHOR_LOWER : ANCHOR_UPPER);
   }
}

//+------------------------------------------------------------------+
void SendSignal(const string message)
{
   if(!EnableAlerts) return;
   Alert(message);
   if(AlertPushNotification) SendNotification(message);
   if(AlertEmail) SendMail("Dynamic Swing Anchored VWAP", message);
}

//+------------------------------------------------------------------+
// Returns the higher-timeframe direction using a closed HTF candle,
// its EMA, and EMA slope. This prevents the still-forming HTF candle
// from changing the entry filter intrabar.
int HigherTimeframeTrend(const datetime barTime)
{
   int tf = HigherTimeframe == PERIOD_CURRENT ? Period() : (int)HigherTimeframe;
   int hs = iBarShift(NULL, tf, barTime, false) + 1;
   if(hs < 1) return(0);

   double emaNow  = iMA(NULL, tf, HigherTimeframeEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, hs);
   double emaPrev = iMA(NULL, tf, HigherTimeframeEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, hs + 1);
   double htfClose = iClose(NULL, tf, hs);
   if(emaNow <= 0.0 || emaPrev <= 0.0 || htfClose <= 0.0) return(0);

   if(htfClose > emaNow && emaNow > emaPrev) return(1);
   if(htfClose < emaNow && emaNow < emaPrev) return(-1);
   return(0);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(SwingPeriod < 2) SwingPeriod = 2;
   if(ATRPeriod < 2) ATRPeriod = 2;
   if(HigherTimeframeEMAPeriod < 2) HigherTimeframeEMAPeriod = 2;
   if(PullbackLookback < 1) PullbackLookback = 1;
   if(PullbackMaxDistanceATR < 0.0) PullbackMaxDistanceATR = 0.0;
   if(ArrowOffsetATR < 0.0) ArrowOffsetATR = 0.0;
   if(MinimumAPT < 1.0) MinimumAPT = 1.0;
   if(MaximumAPT < MinimumAPT) MaximumAPT = MinimumAPT;

   IndicatorBuffers(2);
   SetIndexBuffer(0, VWAPUp);
   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, VWAPLineWidth, VWAPUpColor);
   SetIndexLabel(0, "VWAP (Up)");
   SetIndexEmptyValue(0, EMPTY_VALUE);

   SetIndexBuffer(1, VWAPDown);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, VWAPLineWidth, VWAPDownColor);
   SetIndexLabel(1, "VWAP (Down)");
   SetIndexEmptyValue(1, EMPTY_VALUE);

   SetIndexBuffer(2, BuyArrow);
   SetIndexStyle(2, DRAW_ARROW, STYLE_SOLID, 1, clrDodgerBlue);
   SetIndexArrow(2, 233);
   SetIndexLabel(2, "Buy entry");
   SetIndexEmptyValue(2, EMPTY_VALUE);

   SetIndexBuffer(3, SellArrow);
   SetIndexStyle(3, DRAW_ARROW, STYLE_SOLID, 1, clrOrangeRed);
   SetIndexArrow(3, 234);
   SetIndexLabel(3, "Sell entry");
   SetIndexEmptyValue(3, EMPTY_VALUE);

   ArraySetAsSeries(VWAPUp, true);
   ArraySetAsSeries(VWAPDown, true);
   ArraySetAsSeries(BuyArrow, true);
   ArraySetAsSeries(SellArrow, true);
   IndicatorShortName("Dynamic Swing Anchored VWAP");
   IndicatorDigits(Digits);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteLabels();
}

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
   if(rates_total < SwingPeriod + ATRPeriod + 10)
      return(0);

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);
   ArraySetAsSeries(volume, true);

   // With closed-bar mode, nothing can change between ticks. Avoid rebuilding
   // the full state machine until a new candle arrives.
   bool newBar = (time[0] != g_lastBar);
   if(prev_calculated > 0 && UseClosedBarsOnly && !newBar)
      return(rates_total);
   g_lastBar = time[0];

   int first = UseClosedBarsOnly ? 1 : 0;
   int oldest = rates_total - 1;
   if(MaxCalculationBars > 0)
      oldest = MathMin(oldest, MaxCalculationBars - 1);

   double atr[], atrRma[], apt[], alpha[], price[], vol[];
   ArrayResize(atr, oldest + 1);
   ArrayResize(atrRma, oldest + 1);
   ArrayResize(apt, oldest + 1);
   ArrayResize(alpha, oldest + 1);
   ArrayResize(price, oldest + 1);
   ArrayResize(vol, oldest + 1);

   ArrayInitialize(VWAPUp, EMPTY_VALUE);
   ArrayInitialize(VWAPDown, EMPTY_VALUE);
   ArrayInitialize(BuyArrow, EMPTY_VALUE);
   ArrayInitialize(SellArrow, EMPTY_VALUE);

   // Build ATR and source arrays from old to new. The RMA is seeded with an
   // SMA of ATR values, rather than with an arbitrary first value.
   for(int s = oldest; s >= 0; s--)
   {
      price[s] = (high[s] + low[s] + close[s]) / 3.0;
      vol[s] = BarVolume(s, tick_volume, volume);
      if(vol[s] <= 0.0) vol[s] = 1.0;
      atr[s] = iATR(NULL, 0, ATRPeriod, s);
   }

   double seed = 0.0;
   int seedCount = 0;
   for(int k = oldest; k >= 0 && k > oldest - ATRPeriod; k--)
   {
      seed += atr[k];
      seedCount++;
   }
   atrRma[oldest] = seedCount > 0 ? seed / seedCount : atr[oldest];

   for(int s = oldest - 1; s >= 0; s--)
   {
      atrRma[s] = (atrRma[s + 1] * (ATRPeriod - 1.0) + atr[s]) / ATRPeriod;
      double ratio = atrRma[s] > 0.0 ? atr[s] / atrRma[s] : 1.0;
      ratio = MathMax(0.25, MathMin(4.0, ratio));
      double rawAPT = AdaptAPTByATR
                    ? AdaptivePriceTracking / MathPow(ratio, VolatilityBias)
                    : AdaptivePriceTracking;
      apt[s] = MathMax(MinimumAPT, MathMin(MaximumAPT, rawAPT));
      alpha[s] = AlphaFromAPT(apt[s]);
   }
   apt[oldest] = MathMax(MinimumAPT, MathMin(MaximumAPT, AdaptivePriceTracking));
   alpha[oldest] = AlphaFromAPT(apt[oldest]);

   if(newBar || prev_calculated == 0)
      DeleteLabels();

   double ph = 0.0, pl = 0.0, prevPivot = 0.0;
   int phG = -1, plG = -1;
   int direction = 0, previousDirection = 0;
   double pState = 0.0, volState = 0.0;
   bool initialized = false, haveFirstFlip = false;
   string latestSignal = "";

   for(int s = oldest; s >= first; s--)
   {
      int g = (rates_total - 1) - s;
      double previousSwingHigh = ph;
      double previousSwingLow  = pl;
      bool newHigh = true, newLow = true;
      int look = MathMin(SwingPeriod, rates_total - s);

      for(int k = 1; k < look; k++)
      {
         if(high[s + k] > high[s]) newHigh = false;
         if(low[s + k] < low[s])   newLow = false;
      }

      double swingATR = atr[s] * MinimumSwingATR;
      if(MinimumSwingATR > 0.0)
      {
         if(plG >= 0 && MathAbs(high[s] - pl) < swingATR) newHigh = false;
         if(phG >= 0 && MathAbs(low[s] - ph) < swingATR)  newLow = false;
      }

      if(newHigh) { ph = high[s]; phG = g; }
      if(newLow)  { pl = low[s];  plG = g; }
      if(phG < 0 && plG < 0) continue;

      direction = (phG > plG) ? 1 : -1;
      if(!initialized)
      {
         // Seed the state once. Do not process this same bar a second time.
         pState = price[s] * vol[s];
         volState = vol[s];
         initialized = true;
         previousDirection = direction;
         double initialValue = pState / volState;
         if(direction > 0) VWAPUp[s] = initialValue;
         else              VWAPDown[s] = initialValue;
         continue;
      }

      if(direction != previousDirection)
      {
         int anchorG = direction > 0 ? plG : phG;
         int anchorShift = (rates_total - 1) - anchorG;
         int barsBack = g - anchorG;
         double anchorPrice = direction > 0 ? pl : ph;
         double p = anchorPrice * vol[anchorShift];
         double v = vol[anchorShift];

         // Start after the anchor, so it is not counted twice.
         for(int i = barsBack - 1; i >= 0; i--)
         {
            int q = s + i;
            p = (1.0 - alpha[q]) * p + alpha[q] * price[q] * vol[q];
            v = (1.0 - alpha[q]) * v + alpha[q] * vol[q];
            double value = v > 0.0 ? p / v : EMPTY_VALUE;
            if(direction > 0) VWAPUp[q] = value;
            else              VWAPDown[q] = value;
         }

         pState = p;
         volState = v;
         string label = "";
         if(haveFirstFlip)
         {
            if(direction > 0) label = pl < prevPivot ? "LL" : "HL";
            else              label = ph < prevPivot ? "LH" : "HH";
         }
         if(label != "")
         {
            int pivotShift = direction > 0 ? (rates_total - 1 - plG)
                                           : (rates_total - 1 - phG);
            MakeSwingLabel(label, pivotShift,
                           direction > 0 ? pl : ph, 
                           direction > 0 ? SwingLowColor : SwingHighColor,
                           atr[pivotShift]);
            latestSignal = label;
         }
         prevPivot = direction > 0 ? ph : pl;
         haveFirstFlip = true;
      }
      else
      {
         pState = (1.0 - alpha[s]) * pState + alpha[s] * price[s] * vol[s];
         volState = (1.0 - alpha[s]) * volState + alpha[s] * vol[s];
         double value = volState > 0.0 ? pState / volState : EMPTY_VALUE;
         if(direction > 0) VWAPUp[s] = value;
         else              VWAPDown[s] = value;
      }

      // Entry arrow logic:
      // 1) closed candle is in the local VWAP trend;
      // 2) one of the preceding candles pulled back to the VWAP;
      // 3) the current candle confirms continuation through the prior bar;
      // 4) the higher timeframe agrees with the direction.
      if(EnableEntryArrows && s >= 1 && s + 1 < rates_total)
      {
         double currentVWAP = direction > 0 ? VWAPUp[s] : VWAPDown[s];
         bool pulledBack = false;
         int pbLook = MathMax(1, PullbackLookback);
         double maxDistance = atr[s] * MathMax(0.0, PullbackMaxDistanceATR);

         for(int k = 1; k <= pbLook && s + k < rates_total; k++)
         {
            double priorVWAP = direction > 0 ? VWAPUp[s + k] : VWAPDown[s + k];
            if(priorVWAP == EMPTY_VALUE) continue;

            bool nearVWAP = low[s + k] <= priorVWAP + maxDistance &&
                            high[s + k] >= priorVWAP - maxDistance;
            if(nearVWAP)
               pulledBack = true;
         }

         int htfDirection = HigherTimeframeTrend(time[s]);
         bool htfAgrees = (htfDirection == direction);
         bool bullishContinuation = close[s] > open[s] &&
                                    close[s] > high[s + 1] &&
                                    previousSwingHigh > 0.0 &&
                                    close[s] > previousSwingHigh;
         bool bearishContinuation = close[s] < open[s] &&
                                    close[s] < low[s + 1] &&
                                    previousSwingLow > 0.0 &&
                                    close[s] < previousSwingLow;

         if(currentVWAP != EMPTY_VALUE && pulledBack && htfAgrees)
         {
            if(direction > 0 && bullishContinuation)
               BuyArrow[s] = low[s] - atr[s] * ArrowOffsetATR;
            if(direction < 0 && bearishContinuation)
               SellArrow[s] = high[s] + atr[s] * ArrowOffsetATR;
         }
      }
      previousDirection = direction;
   }

   if(newBar && UseClosedBarsOnly && rates_total > 3)
   {
      bool upNow = VWAPUp[1] != EMPTY_VALUE;
      bool upPrev = VWAPUp[2] != EMPTY_VALUE;
      bool trendChanged = upNow != upPrev;
      bool crossed = false;
      double v1 = upNow ? VWAPUp[1] : VWAPDown[1];
      double v2 = upNow ? VWAPUp[2] : VWAPDown[2];
      if(close[1] > v1 && close[2] <= v2) crossed = true;
      if(close[1] < v1 && close[2] >= v2) crossed = true;

      string msg = Symbol() + " " + IntegerToString(Period()) + "M: ";
      if(AlertOnTrendChange && trendChanged)
         SendSignal(msg + (upNow ? "VWAP trend turned UP" : "VWAP trend turned DOWN"));
      else if(AlertOnVWAPCross && crossed)
         SendSignal(msg + "price crossed the adaptive anchored VWAP");
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
