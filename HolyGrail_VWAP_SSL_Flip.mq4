//+------------------------------------------------------------------+
//|                HolyGrail_VWAP_SSL_Flip.mq4                      |
//| Anchored High/Low VWAP SSL flip with bands, arrows, alerts, HUD |
//| FINAL RELEASE • clean dashboard • closed-bar confirmation default |
//| Optional risk planner • sizing only, never automatic execution    |
//+------------------------------------------------------------------+
#property copyright   "Holy Grail VWAP SSL Flip"
#property description "Confirmed anchored High/Low VWAP SSL flip with sessions, bands, alerts and risk planner"
#property version     "5.10"
#property strict
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_color1 clrLimeGreen
#property indicator_color2 clrTomato
#property indicator_color3 clrLimeGreen
#property indicator_color4 clrTomato
#property indicator_color5 clrDodgerBlue
#property indicator_color6 clrDodgerBlue
#property indicator_color7 clrSilver
#property indicator_color8 clrSilver

// The SSL state is deliberately hysteretic:
//   - a bearish state flips bullish only after a close above High VWAP;
//   - a bullish state flips bearish only after a close below Low VWAP;
//   - price between the two VWAPs leaves the existing state unchanged.
//
// All anchor/session times use the broker/server time shown by MT4. The
// indicator never uses future bars. With SignalsOnClosedBarsOnly=true, arrows
// and alerts are produced only from fully closed candles.

enum ENUM_VWAP_ANCHOR
{
   ANCHOR_DAILY = 0,
   ANCHOR_WEEKLY,
   ANCHOR_MONTHLY,
   ANCHOR_QUARTERLY,
   ANCHOR_YEARLY,
   ANCHOR_LONDON,
   ANCHOR_NEW_YORK,
   ANCHOR_ASIA,
   ANCHOR_CUSTOM_SESSION,
   ANCHOR_CUSTOM_TIME
};

enum ENUM_VWAP_VOLUME
{
   VOLUME_TICK = 0,
   VOLUME_REAL_WITH_TICK_FALLBACK
};

enum ENUM_INITIAL_TREND
{
   INITIAL_AUTO = 0,
   INITIAL_BULLISH,
   INITIAL_BEARISH
};

// Anchor settings. Session clocks refer to the time shown by MT4.
input ENUM_VWAP_ANCHOR AnchorPeriod = ANCHOR_DAILY;
input int LondonStartHour = 8;
input int LondonStartMinute = 0;
input int NewYorkStartHour = 13;
input int NewYorkStartMinute = 30;
input int AsiaStartHour = 0;
input int AsiaStartMinute = 0;
input int CustomSessionHour = 0;
input int CustomSessionMinute = 0;
input datetime CustomAnchorTime = D'2024.01.01 00:00';
input ENUM_VWAP_VOLUME VWAPVolume = VOLUME_TICK;

// SSL state settings.
// Keeping this true preserves the sticky SSL state over a new VWAP anchor.
// Set it false when each day/session should start with a fresh state.
input bool CarryTrendAcrossAnchors = true;
input ENUM_INITIAL_TREND InitialTrend = INITIAL_AUTO;

// Visual settings.
input color UpTrendColor = clrLimeGreen;
input color DownTrendColor = clrTomato;
input int SSLLineWidth = 2;
input bool ShowBands = true;
input color Band1Color = clrDodgerBlue;
input color Band2Color = clrSilver;
input double Band1Deviation = 1.0;
input double Band2Deviation = 2.0;
input bool ShowArrows = true;
input int ArrowSize = 3;
input int BuyArrowCode = 233;
input int SellArrowCode = 234;
input double ArrowOffsetATR = 0.20;
input int ArrowATRPeriod = 14;
input bool SignalsOnClosedBarsOnly = true;

// Optional risk planner. It only displays a stop, target and conservative
// lot-size estimate; it never opens, modifies or closes an MT4 order.
input bool ShowRiskPlanner = true;
input bool UseEquityForRisk = true;
input double ManualRiskCapital = 0.0;
input double RiskPercent = 0.50;
input double StopLossATR = 1.50;
input double RewardRiskRatio = 2.00;

// Alert settings.
input bool EnableAlerts = true;
input bool PopupAlert = false;
input bool SoundAlert = false;
input string AlertSoundFile = "alert.wav";
input bool EmailAlert = false;
input bool PushAlert = false;
input bool AlertOncePerFlipBar = true;
input bool AlertOnAttach = false;

// Chart display.
input bool ShowHUD = true;
// Top-left is the safest default across MT4 themes and chart layouts.
input int HUDCorner = CORNER_LEFT_UPPER;
input int HUDX = 18;
input int HUDY = 24;
input int HUDWidth = 250;
input int HUDHeight = 250;
input string HUDInstanceTag = "main";
input string HUDFont = "Arial";
input color HUDBackgroundColor = clrDarkSlateGray;
input color HUDBorderColor = clrGray;
input color HUDTitleColor = clrWhite;
input color HUDTextColor = clrSilver;
input color HUDMutedColor = clrGray;
input color HUDBullColor = clrLimeGreen;
input color HUDBearColor = clrTomato;

// Drawn buffers. Eight buffers keeps the indicator compatible with broad MT4
// builds while allowing each active line and band to be styled independently.
double UpLine[];
double DownLine[];
double BuyArrow[];
double SellArrow[];
double BandUp1[];
double BandDown1[];
double BandUp2[];
double BandDown2[];

// Internal, non-drawn series.
double gHighVWAP[];
double gLowVWAP[];
double gTypicalVWAP[];
double gStdDev[];
double gATR[];
int gTrend[]; // 1 = bullish, -1 = bearish, 0 = not available

const long INVALID_ANCHOR = -1;
datetime gLastAlertTime = 0;
int gLastAlertTrend = 0;
bool gAlertsPrimed = false;
string gHUDPrefix = "";

//+------------------------------------------------------------------+
//| Indicator initialization                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, UpLine);
   SetIndexBuffer(1, DownLine);
   SetIndexBuffer(2, BuyArrow);
   SetIndexBuffer(3, SellArrow);
   SetIndexBuffer(4, BandUp1);
   SetIndexBuffer(5, BandDown1);
   SetIndexBuffer(6, BandUp2);
   SetIndexBuffer(7, BandDown2);

   ArraySetAsSeries(UpLine, true);
   ArraySetAsSeries(DownLine, true);
   ArraySetAsSeries(BuyArrow, true);
   ArraySetAsSeries(SellArrow, true);
   ArraySetAsSeries(BandUp1, true);
   ArraySetAsSeries(BandDown1, true);
   ArraySetAsSeries(BandUp2, true);
   ArraySetAsSeries(BandDown2, true);

   if(ArrowATRPeriod < 1 ||
      ArrowOffsetATR < 0.0 ||
      Band1Deviation < 0.0 ||
      Band2Deviation < 0.0 ||
      ManualRiskCapital < 0.0 ||
      RiskPercent < 0.0 ||
      RiskPercent > 100.0 ||
      StopLossATR <= 0.0 ||
      RewardRiskRatio <= 0.0)
   {
      Print("HolyGrail_VWAP_SSL_Flip: invalid numeric input.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   int lineWidth = ClampInt(SSLLineWidth, 1, 5);
   int arrowWidth = ClampInt(ArrowSize, 1, 5);

   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, lineWidth, UpTrendColor);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, lineWidth, DownTrendColor);
   SetIndexStyle(2, ShowArrows ? DRAW_ARROW : DRAW_NONE,
                 STYLE_SOLID, arrowWidth, UpTrendColor);
   SetIndexStyle(3, ShowArrows ? DRAW_ARROW : DRAW_NONE,
                 STYLE_SOLID, arrowWidth, DownTrendColor);
   SetIndexArrow(2, BuyArrowCode);
   SetIndexArrow(3, SellArrowCode);
   SetIndexStyle(4, ShowBands ? DRAW_LINE : DRAW_NONE,
                 STYLE_DOT, 1, Band1Color);
   SetIndexStyle(5, ShowBands ? DRAW_LINE : DRAW_NONE,
                 STYLE_DOT, 1, Band1Color);
   SetIndexStyle(6, ShowBands ? DRAW_LINE : DRAW_NONE,
                 STYLE_DOT, 1, Band2Color);
   SetIndexStyle(7, ShowBands ? DRAW_LINE : DRAW_NONE,
                 STYLE_DOT, 1, Band2Color);

   SetIndexLabel(0, "Bullish Low VWAP");
   SetIndexLabel(1, "Bearish High VWAP");
   SetIndexLabel(2, "Buy Flip");
   SetIndexLabel(3, "Sell Flip");
   SetIndexLabel(4, "Typical VWAP + Band 1");
   SetIndexLabel(5, "Typical VWAP - Band 1");
   SetIndexLabel(6, "Typical VWAP + Band 2");
   SetIndexLabel(7, "Typical VWAP - Band 2");

   for(int i = 0; i < 8; i++)
      SetIndexEmptyValue(i, EMPTY_VALUE);

   IndicatorDigits(Digits);
   IndicatorShortName("Holy Grail VWAP SSL (" + AnchorLabel() + ")");
   gLastAlertTime = 0;
   gLastAlertTrend = 0;
   gAlertsPrimed = false;
   // IntegerToString is used instead of LongToString for older MT4 builds.
   // The chart id is only a namespace suffix, so a 32-bit cast is sufficient.
   gHUDPrefix = "HGSSL_HUD_" + IntegerToString((int)ChartID()) + "_" +
                HUDInstanceTag + "_";
   // Remove stale objects left by an older copy before rebuilding the layout.
   DeleteHUDObjects();
   if(ShowHUD)
      EnsureHUDObjects();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Indicator deinitialization                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteHUDObjects();
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
   int minimumBars = MathMax(3, ArrowATRPeriod + 2);
   if(rates_total < minimumBars)
   {
      for(int i = 0; i < rates_total; i++)
         ClearDrawBuffers(i);
      if(ShowHUD)
         UpdateHUDWaiting("Waiting for more bars...");
      return(0);
   }

   ResizeWorkArrays(rates_total);
   CalculateATR(rates_total, high, low, close);

   double sumVolume = 0.0;
   double highVWAP = 0.0;
   double lowVWAP = 0.0;
   double typicalVWAP = 0.0;
   double typicalM2 = 0.0; // weighted second central moment
   long activeAnchor = INVALID_ANCHOR;
   int state = 0;

   // MT4 series arrays are newest-to-oldest. Walking backwards processes
   // candles chronologically, which makes each VWAP pass O(rates_total) and
   // prevents a future candle from influencing an earlier candle.
   for(int i = rates_total - 1; i >= 0; i--)
   {
      ClearDrawBuffers(i);

      long anchor = AnchorKey(time[i]);
      if(anchor == INVALID_ANCHOR)
      {
         gHighVWAP[i] = EMPTY_VALUE;
         gLowVWAP[i] = EMPTY_VALUE;
         gTypicalVWAP[i] = EMPTY_VALUE;
         gStdDev[i] = EMPTY_VALUE;
         gTrend[i] = 0;

         // This is used by one-time custom anchors. It also makes a later
         // valid segment start cleanly if the available history is unusual.
         activeAnchor = INVALID_ANCHOR;
         state = 0;
         continue;
      }

      if(anchor != activeAnchor)
      {
         sumVolume = 0.0;
         highVWAP = 0.0;
         lowVWAP = 0.0;
         typicalVWAP = 0.0;
         typicalM2 = 0.0;
         activeAnchor = anchor;

         if(!CarryTrendAcrossAnchors)
            state = 0;
      }

      double weight = BarVolume(i, tick_volume, volume);
      double typical = (high[i] + low[i] + close[i]) / 3.0;
      double newSumVolume = sumVolume + weight;
      double alpha = weight / newSumVolume;

      // Weighted online means avoid large-price cancellation and keep the
      // values stable on long monthly/yearly anchors.
      highVWAP += alpha * (high[i] - highVWAP);
      lowVWAP += alpha * (low[i] - lowVWAP);

      double delta = typical - typicalVWAP;
      typicalVWAP += alpha * delta;
      typicalM2 += weight * delta * (typical - typicalVWAP);
      sumVolume = newSumVolume;

      gHighVWAP[i] = highVWAP;
      gLowVWAP[i] = lowVWAP;
      gTypicalVWAP[i] = typicalVWAP;
      gStdDev[i] = MathSqrt(MathMax(0.0, typicalM2 / sumVolume));

      int priorState = state;
      if(priorState == 0)
      {
         state = InitialTrendState(close[i], highVWAP, lowVWAP);
      }
      else if(priorState < 0 && close[i] > highVWAP)
      {
         state = 1;
      }
      else if(priorState > 0 && close[i] < lowVWAP)
      {
         state = -1;
      }
      gTrend[i] = state;

      bool flipped = (priorState != 0 && state != priorState);

      // Put the old line on the flip candle as a bridge. This prevents an
      // apparent gap while still leaving only the active SSL line afterward.
      if(state > 0)
      {
         UpLine[i] = gLowVWAP[i];
         if(flipped)
            DownLine[i] = gHighVWAP[i];
      }
      else
      {
         DownLine[i] = gHighVWAP[i];
         if(flipped)
            UpLine[i] = gLowVWAP[i];
      }

      bool canSignal = (!SignalsOnClosedBarsOnly || i > 0);
      if(flipped && canSignal && ShowArrows)
      {
         double offset = MathMax(5.0 * Point, gATR[i] * ArrowOffsetATR);
         if(state > 0)
            BuyArrow[i] = low[i] - offset;
         else
            SellArrow[i] = high[i] + offset;
      }

      if(ShowBands)
      {
         BandUp1[i] = gTypicalVWAP[i] + Band1Deviation * gStdDev[i];
         BandDown1[i] = gTypicalVWAP[i] - Band1Deviation * gStdDev[i];
         BandUp2[i] = gTypicalVWAP[i] + Band2Deviation * gStdDev[i];
         BandDown2[i] = gTypicalVWAP[i] - Band2Deviation * gStdDev[i];
      }
   }

   ProcessAlert(time, close, rates_total);
   UpdateHUD(close[0], rates_total);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Work-array allocation                                            |
//+------------------------------------------------------------------+
void ResizeWorkArrays(const int size)
{
   ArrayResize(gHighVWAP, size);
   ArrayResize(gLowVWAP, size);
   ArrayResize(gTypicalVWAP, size);
   ArrayResize(gStdDev, size);
   ArrayResize(gATR, size);
   ArrayResize(gTrend, size);

   ArraySetAsSeries(gHighVWAP, true);
   ArraySetAsSeries(gLowVWAP, true);
   ArraySetAsSeries(gTypicalVWAP, true);
   ArraySetAsSeries(gStdDev, true);
   ArraySetAsSeries(gATR, true);
   ArraySetAsSeries(gTrend, true);
}

//+------------------------------------------------------------------+
//| Clear all visible values on one bar                              |
//+------------------------------------------------------------------+
void ClearDrawBuffers(const int i)
{
   UpLine[i] = EMPTY_VALUE;
   DownLine[i] = EMPTY_VALUE;
   BuyArrow[i] = EMPTY_VALUE;
   SellArrow[i] = EMPTY_VALUE;
   BandUp1[i] = EMPTY_VALUE;
   BandDown1[i] = EMPTY_VALUE;
   BandUp2[i] = EMPTY_VALUE;
   BandDown2[i] = EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| Select real volume, falling back safely to tick volume            |
//+------------------------------------------------------------------+
double BarVolume(const int i, const long &tick_volume[], const long &volume[])
{
   double weight = (double)tick_volume[i];
   if(VWAPVolume == VOLUME_REAL_WITH_TICK_FALLBACK && volume[i] > 0)
      weight = (double)volume[i];
   if(weight <= 0.0)
      weight = 1.0;
   return(weight);
}

//+------------------------------------------------------------------+
//| Calculate a stable Wilder ATR series for arrow placement         |
//+------------------------------------------------------------------+
void CalculateATR(const int rates_total,
                 const double &high[],
                 const double &low[],
                 const double &close[])
{
   int period = MathMax(1, ArrowATRPeriod);
   double trSum = 0.0;
   double atr = 0.0;
   int count = 0;

   for(int i = rates_total - 1; i >= 0; i--)
   {
      double trueRange;
      if(i == rates_total - 1)
      {
         trueRange = high[i] - low[i];
      }
      else
      {
         double previousClose = close[i + 1];
         trueRange = MathMax(high[i], previousClose) -
                     MathMin(low[i], previousClose);
      }
      trueRange = MathMax(0.0, trueRange);

      count++;
      if(count < period)
      {
         trSum += trueRange;
         atr = trSum / count;
      }
      else if(count == period)
      {
         trSum += trueRange;
         atr = trSum / period;
      }
      else
      {
         atr = ((atr * (period - 1)) + trueRange) / period;
      }
      gATR[i] = atr;
   }
}

//+------------------------------------------------------------------+
//| Build a display-only risk plan from the current signal            |
//+------------------------------------------------------------------+
//| The plan uses a logical ATR stop and converts the chosen account   |
//| risk into an approximate lot size. It never sends an order.        |
//+------------------------------------------------------------------+
bool CalculateRiskPlan(const double entryPrice,
                       const int trend,
                       double &stopPrice,
                       double &targetPrice,
                       double &riskMoney,
                       double &lots)
{
   stopPrice = 0.0;
   targetPrice = 0.0;
   riskMoney = 0.0;
   lots = -1.0; // -1 means broker tick-value data is unavailable.

   if(!ShowRiskPlanner || RiskPercent <= 0.0 || trend == 0)
      return(false);
   if(ArraySize(gATR) < 1 || gATR[0] <= 0.0 || gATR[0] == EMPTY_VALUE)
      return(false);

   double capital = ManualRiskCapital;
   if(capital <= 0.0)
      capital = UseEquityForRisk ? AccountEquity() : AccountBalance();
   if(capital <= 0.0)
      return(false);

   double stopDistance = gATR[0] * StopLossATR;
   if(stopDistance <= 0.0)
      return(false);

   riskMoney = capital * RiskPercent / 100.0;
   stopPrice = NormalizeDouble(trend > 0 ? entryPrice - stopDistance :
                                            entryPrice + stopDistance, Digits);
   targetPrice = NormalizeDouble(trend > 0 ? entryPrice +
                                             stopDistance * RewardRiskRatio :
                                             entryPrice -
                                             stopDistance * RewardRiskRatio, Digits);

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(tickValue <= 0.0 || tickSize <= 0.0 ||
      minLot <= 0.0 || maxLot <= 0.0)
   {
      return(true);
   }

   if(lotStep <= 0.0)
      lotStep = minLot;
   double moneyPerLot = stopDistance / tickSize * tickValue;
   if(moneyPerLot <= 0.0)
      return(true);

   double rawLots = riskMoney / moneyPerLot;
   if(rawLots >= minLot)
   {
      lots = MathFloor(rawLots / lotStep + 0.000000001) * lotStep;
      lots = MathMin(lots, maxLot);
      lots = NormalizeDouble(lots, LotDigits(lotStep));
      if(lots < minLot)
         lots = 0.0;
   }
   else
   {
      lots = 0.0; // the requested risk is below the broker's minimum lot.
   }
   return(true);
}

int LotDigits(const double lotStep)
{
   int digits = 0;
   double scaled = lotStep;
   while(digits < 8 && MathAbs(scaled - MathRound(scaled)) > 0.000000001)
   {
      scaled *= 10.0;
      digits++;
   }
   return(digits);
}

string RiskLotsLabel(const double lots)
{
   if(lots < 0.0)
      return("n/a");
   if(lots == 0.0)
      return("below min");
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0)
      step = 0.01;
   return(DoubleToString(lots, LotDigits(step)));
}

//+------------------------------------------------------------------+
//| Set the first state in a valid segment                           |
//+------------------------------------------------------------------+
int InitialTrendState(const double closePrice,
                      const double highVWAP,
                      const double lowVWAP)
{
   if(InitialTrend == INITIAL_BULLISH)
      return(1);
   if(InitialTrend == INITIAL_BEARISH)
      return(-1);

   // On the first candle high/low VWAPs usually bracket the close, so using
   // the VWAP midpoint gives a deterministic and useful neutral-zone seed.
   double midpoint = (highVWAP + lowVWAP) / 2.0;
   return(closePrice >= midpoint ? 1 : -1);
}

//+------------------------------------------------------------------+
//| Return the anchor/session key for a bar                          |
//+------------------------------------------------------------------+
long AnchorKey(const datetime barTime)
{
   if(AnchorPeriod == ANCHOR_CUSTOM_TIME)
      return(barTime >= CustomAnchorTime ? (long)CustomAnchorTime : INVALID_ANCHOR);

   if(AnchorPeriod == ANCHOR_DAILY)
      return((long)StartOfDay(barTime));

   if(AnchorPeriod == ANCHOR_WEEKLY)
   {
      datetime day = StartOfDay(barTime);
      int daysSinceMonday = (TimeDayOfWeek(barTime) + 6) % 7;
      return((long)(day - daysSinceMonday * 86400));
   }

   int year = TimeYear(barTime);
   int month = TimeMonth(barTime);
   if(AnchorPeriod == ANCHOR_MONTHLY)
      return((long)(year * 12 + month));
   if(AnchorPeriod == ANCHOR_QUARTERLY)
      return((long)(year * 4 + (month - 1) / 3));
   if(AnchorPeriod == ANCHOR_YEARLY)
      return((long)year);

   int hour = CustomSessionHour;
   int minute = CustomSessionMinute;
   if(AnchorPeriod == ANCHOR_LONDON)
   {
      hour = LondonStartHour;
      minute = LondonStartMinute;
   }
   else if(AnchorPeriod == ANCHOR_NEW_YORK)
   {
      hour = NewYorkStartHour;
      minute = NewYorkStartMinute;
   }
   else if(AnchorPeriod == ANCHOR_ASIA)
   {
      hour = AsiaStartHour;
      minute = AsiaStartMinute;
   }

   hour = ClampInt(hour, 0, 23);
   minute = ClampInt(minute, 0, 59);
   int sessionSeconds = hour * 3600 + minute * 60;
   datetime day = StartOfDay(barTime);
   int secondsIntoDay = (int)(barTime - day);
   if(secondsIntoDay < sessionSeconds)
      day -= 86400;
   return((long)(day + sessionSeconds));
}

//+------------------------------------------------------------------+
//| Midnight in broker/server time                                  |
//+------------------------------------------------------------------+
datetime StartOfDay(const datetime value)
{
   return(value - TimeHour(value) * 3600 -
          TimeMinute(value) * 60 - TimeSeconds(value));
}

//+------------------------------------------------------------------+
//| Clamp a user input without changing the stored input             |
//+------------------------------------------------------------------+
int ClampInt(const int value, const int minimum, const int maximum)
{
   if(value < minimum)
      return(minimum);
   if(value > maximum)
      return(maximum);
   return(value);
}

//+------------------------------------------------------------------+
//| Alert on the first eligible transition only                      |
//+------------------------------------------------------------------+
void ProcessAlert(const datetime &time[],
                  const double &close[],
                  const int rates_total)
{
   if(!EnableAlerts || rates_total < 2)
      return;

   int bar = SignalsOnClosedBarsOnly ? 1 : 0;
   if(bar + 1 >= rates_total)
      return;
   if(gTrend[bar] == 0 || gTrend[bar + 1] == 0)
      return;

   // Do not fire a stale historical signal merely because the indicator was
   // attached or reloaded. Set AlertOnAttach=true when that behavior is
   // explicitly wanted.
   if(!gAlertsPrimed)
   {
      gAlertsPrimed = true;
      if(!AlertOnAttach)
      {
         gLastAlertTime = time[bar];
         gLastAlertTrend = gTrend[bar];
         return;
      }
   }

   bool buy = (gTrend[bar] > 0 && gTrend[bar + 1] < 0);
   bool sell = (gTrend[bar] < 0 && gTrend[bar + 1] > 0);
   if(!buy && !sell)
      return;

   int trend = buy ? 1 : -1;
   if(AlertOncePerFlipBar &&
      time[bar] == gLastAlertTime &&
      trend == gLastAlertTrend)
   {
      return;
   }

   string side = buy ? "BUY" : "SELL";
   string message = StringFormat(
      "Holy Grail VWAP SSL %s | %s %s | %s | Bar %s | Price %s",
      side,
      Symbol(),
      TimeframeLabel(Period()),
      AnchorLabel(),
      TimeToString(time[bar], TIME_DATE | TIME_MINUTES),
      DoubleToString(close[bar], Digits));

   if(PopupAlert)
      Alert(message);
   if(SoundAlert)
      PlaySound(AlertSoundFile);
   if(EmailAlert)
      SendMail("Holy Grail VWAP SSL signal", message);
   if(PushAlert)
      SendNotification(message);

   gLastAlertTime = time[bar];
   gLastAlertTrend = trend;
}

//+------------------------------------------------------------------+
//| Update the compact chart HUD                                    |
//+------------------------------------------------------------------+
void UpdateHUD(const double currentClose, const int rates_total)
{
   if(!ShowHUD)
   {
      DeleteHUDObjects();
      return;
   }

   if(!EnsureHUDObjects())
      return;

   if(rates_total < 1 || gTypicalVWAP[0] == EMPTY_VALUE)
   {
      UpdateHUDWaiting("Waiting for custom anchor...");
      return;
   }

   double midpoint = (gHighVWAP[0] + gLowVWAP[0]) / 2.0;
   double deviationPercent = 0.0;
   if(midpoint != 0.0)
      deviationPercent = (currentClose - midpoint) / midpoint * 100.0;

   bool bullish = (gTrend[0] > 0);
   string trend = bullish ? "BULLISH" : "BEARISH";
   color trendColor = bullish ? HUDBullColor : HUDBearColor;
   string signalMode = SignalsOnClosedBarsOnly ? "closed candles" : "live candle";

   SetHUDLabel("SUBTITLE",
               "Anchor: " + AnchorLabel() + "  |  " + VolumeLabel(),
               HUDMutedColor);
   SetHUDPanelColor("STATUS_BG", trendColor);
   SetHUDLabel("STATUS", trend, clrWhite);
   SetHUDLabel("ROW_HIGH",
               "High VWAP   " + DoubleToString(gHighVWAP[0], Digits),
               HUDTextColor);
   SetHUDLabel("ROW_LOW",
               "Low VWAP    " + DoubleToString(gLowVWAP[0], Digits),
               HUDTextColor);
   SetHUDLabel("ROW_TYPICAL",
               "Typical VWAP " + DoubleToString(gTypicalVWAP[0], Digits),
               HUDTextColor);
   SetHUDLabel("ROW_STD",
               "Std Dev      " + DoubleToString(gStdDev[0], Digits),
               HUDTextColor);
   SetHUDLabel("ROW_MID",
               StringFormat("Price vs mid %+.2f%%", deviationPercent),
               HUDTextColor);
   SetHUDLabel("ROW_BAND1",
               StringFormat("Band 1 SD   %s / %s",
                            DoubleToString(gTypicalVWAP[0] +
                                           Band1Deviation * gStdDev[0], Digits),
                            DoubleToString(gTypicalVWAP[0] -
                                           Band1Deviation * gStdDev[0], Digits)),
               HUDTextColor);
   SetHUDLabel("ROW_BAND2",
               StringFormat("Band 2 SD   %s / %s",
                            DoubleToString(gTypicalVWAP[0] +
                                           Band2Deviation * gStdDev[0], Digits),
                            DoubleToString(gTypicalVWAP[0] -
                                           Band2Deviation * gStdDev[0], Digits)),
               HUDTextColor);

   double stopPrice = 0.0;
   double targetPrice = 0.0;
   double riskMoney = 0.0;
   double lots = -1.0;
   bool hasRiskPlan = CalculateRiskPlan(currentClose, gTrend[0],
                                        stopPrice, targetPrice,
                                        riskMoney, lots);
   if(!ShowRiskPlanner)
   {
      SetHUDLabel("RISK", "Risk planner: disabled", HUDMutedColor);
   }
   else if(hasRiskPlan)
   {
      SetHUDLabel("RISK",
                  StringFormat("Risk %.2f%%  %s %.2f  Lots %s",
                               RiskPercent,
                               AccountCurrency(),
                               riskMoney,
                               RiskLotsLabel(lots)),
                  HUDTextColor);
   }
   else
   {
      SetHUDLabel("RISK", "Risk plan: unavailable", HUDMutedColor);
   }

   if(hasRiskPlan)
   {
      SetHUDLabel("FOOTER",
                  StringFormat("SL %s  |  TP %s  |  %s",
                               DoubleToString(stopPrice, Digits),
                               DoubleToString(targetPrice, Digits),
                               signalMode),
                  HUDMutedColor);
   }
   else
   {
      SetHUDLabel("FOOTER", "Signals: " + signalMode, HUDMutedColor);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Create the polished chart HUD                                   |
//+------------------------------------------------------------------+
bool EnsureHUDObjects()
{
   if(!ShowHUD || gHUDPrefix == "")
      return(false);

   // The layout is static; only text/colors are updated on each tick.
   if(ObjectFind(0, HUDName("PANEL")) >= 0 &&
      ObjectFind(0, HUDName("RISK")) >= 0 &&
      ObjectFind(0, HUDName("FOOTER")) >= 0)
   {
      return(true);
   }

   int corner = ClampInt(HUDCorner, 0, 3);
   int width = ClampInt(HUDWidth, 210, 600);
   int height = ClampInt(HUDHeight, 250, 500);

   // Keep the panel inside the currently visible chart even when an old
   // template contains an excessive X/Y offset.
   int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int maxX = 2000;
   int maxY = 2000;
   if(chartWidth > 0)
      maxX = MathMax(0, chartWidth - width - 6);
   if(chartHeight > 0)
      maxY = MathMax(0, chartHeight - height - 6);

   int x = ClampInt(HUDX, 0, maxX);
   int y = ClampInt(HUDY, 0, maxY);
   string font = HUDFont;
   if(font == "")
      font = "Arial";

   if(!CreateHUDPanel(HUDName("PANEL"), corner, x, y, width, height,
                      HUDBackgroundColor, HUDBorderColor))
   {
      return(false);
   }

   CreateHUDLabel(HUDName("TITLE"), corner, x + 12, y + 9,
                  "HOLY GRAIL  /  VWAP SSL", HUDTitleColor, 11, font);
   CreateHUDLabel(HUDName("SUBTITLE"), corner, x + 12, y + 31,
                  "Anchor: " + AnchorLabel(), HUDMutedColor, 8, font);
   CreateHUDPanel(HUDName("STATUS_BG"), corner, x + 12, y + 52,
                  width - 24, 22, HUDMutedColor, HUDMutedColor);
   CreateHUDLabel(HUDName("STATUS"), corner, x + 22, y + 55,
                  "WAITING", clrWhite, 9, font);

   CreateHUDLabel(HUDName("ROW_HIGH"), corner, x + 14, y + 86,
                  "High VWAP   --", HUDTextColor, 9, font);
   CreateHUDLabel(HUDName("ROW_LOW"), corner, x + 14, y + 102,
                  "Low VWAP    --", HUDTextColor, 9, font);
   CreateHUDLabel(HUDName("ROW_TYPICAL"), corner, x + 14, y + 118,
                  "Typical VWAP --", HUDTextColor, 9, font);
   CreateHUDLabel(HUDName("ROW_STD"), corner, x + 14, y + 134,
                  "Std Dev      --", HUDTextColor, 9, font);
   CreateHUDLabel(HUDName("ROW_MID"), corner, x + 14, y + 150,
                  "Price vs mid --", HUDTextColor, 9, font);
   CreateHUDLabel(HUDName("ROW_BAND1"), corner, x + 14, y + 168,
                  "Band 1 SD   -- / --", HUDTextColor, 9, font);
   CreateHUDLabel(HUDName("ROW_BAND2"), corner, x + 14, y + 184,
                  "Band 2 SD   -- / --", HUDTextColor, 9, font);
   CreateHUDLabel(HUDName("RISK"), corner, x + 14, y + 202,
                  "Risk plan   --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("FOOTER"), corner, x + 14, y + height - 22,
                  "Signals: closed candles", HUDMutedColor, 8, font);
   return(true);
}

void UpdateHUDWaiting(const string message)
{
   if(!ShowHUD)
   {
      DeleteHUDObjects();
      return;
   }
   if(!EnsureHUDObjects())
      return;

   SetHUDLabel("SUBTITLE", AnchorLabel(), HUDMutedColor);
   SetHUDPanelColor("STATUS_BG", HUDMutedColor);
   SetHUDLabel("STATUS", "WAITING", clrWhite);
   SetHUDLabel("ROW_HIGH", message, HUDTextColor);
   SetHUDLabel("ROW_LOW", "", HUDTextColor);
   SetHUDLabel("ROW_TYPICAL", "", HUDTextColor);
   SetHUDLabel("ROW_STD", "", HUDTextColor);
   SetHUDLabel("ROW_MID", "", HUDTextColor);
   SetHUDLabel("ROW_BAND1", "", HUDTextColor);
   SetHUDLabel("ROW_BAND2", "", HUDTextColor);
   SetHUDLabel("RISK", ShowRiskPlanner ? "Risk plan: waiting" :
                              "Risk planner: disabled", HUDMutedColor);
   SetHUDLabel("FOOTER", "Signals: closed candles", HUDMutedColor);
   ChartRedraw();
}

string HUDName(const string suffix)
{
   return(gHUDPrefix + suffix);
}

bool CreateHUDPanel(const string name,
                    const int corner,
                    const int x,
                    const int y,
                    const int width,
                    const int height,
                    const color background,
                    const color border)
{
   if(ObjectFind(0, name) < 0 &&
      !ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      return(false);
   }

   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return(true);
}

bool CreateHUDLabel(const string name,
                    const int corner,
                    const int x,
                    const int y,
                    const string text,
                    const color textColor,
                    const int fontSize,
                    const string font)
{
   if(ObjectFind(0, name) < 0 &&
      !ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
   {
      return(false);
   }

   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   return(true);
}

void SetHUDLabel(const string suffix, const string text, const color textColor)
{
   string name = HUDName(suffix);
   if(ObjectFind(0, name) < 0)
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void SetHUDPanelColor(const string suffix, const color background)
{
   string name = HUDName(suffix);
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, background);
}

void DeleteHUDObject(const string suffix)
{
   if(gHUDPrefix != "")
      ObjectDelete(0, HUDName(suffix));
}

void DeleteHUDObjects()
{
   DeleteHUDObject("PANEL");
   DeleteHUDObject("TITLE");
   DeleteHUDObject("SUBTITLE");
   DeleteHUDObject("STATUS_BG");
   DeleteHUDObject("STATUS");
   DeleteHUDObject("ROW_HIGH");
   DeleteHUDObject("ROW_LOW");
   DeleteHUDObject("ROW_TYPICAL");
   DeleteHUDObject("ROW_STD");
   DeleteHUDObject("ROW_MID");
   DeleteHUDObject("ROW_BAND1");
   DeleteHUDObject("ROW_BAND2");
   DeleteHUDObject("RISK");
   DeleteHUDObject("FOOTER");
}

//+------------------------------------------------------------------+
//| Human-readable labels                                           |
//+------------------------------------------------------------------+
string VolumeLabel()
{
   if(VWAPVolume == VOLUME_REAL_WITH_TICK_FALLBACK)
      return("Real volume");
   return("Tick volume");
}

string AnchorLabel()
{
   if(AnchorPeriod == ANCHOR_WEEKLY)
      return("Weekly");
   if(AnchorPeriod == ANCHOR_MONTHLY)
      return("Monthly");
   if(AnchorPeriod == ANCHOR_QUARTERLY)
      return("Quarterly");
   if(AnchorPeriod == ANCHOR_YEARLY)
      return("Yearly");
   if(AnchorPeriod == ANCHOR_LONDON)
      return("London Session");
   if(AnchorPeriod == ANCHOR_NEW_YORK)
      return("New York Session");
   if(AnchorPeriod == ANCHOR_ASIA)
      return("Asia Session");
   if(AnchorPeriod == ANCHOR_CUSTOM_SESSION)
      return("Custom Session");
   if(AnchorPeriod == ANCHOR_CUSTOM_TIME)
      return("Custom Time");
   return("Daily");
}

string TimeframeLabel(const int timeframe)
{
   if(timeframe == PERIOD_M1)
      return("M1");
   if(timeframe == PERIOD_M5)
      return("M5");
   if(timeframe == PERIOD_M15)
      return("M15");
   if(timeframe == PERIOD_M30)
      return("M30");
   if(timeframe == PERIOD_H1)
      return("H1");
   if(timeframe == PERIOD_H4)
      return("H4");
   if(timeframe == PERIOD_D1)
      return("D1");
   if(timeframe == PERIOD_W1)
      return("W1");
   if(timeframe == PERIOD_MN1)
      return("MN1");
   return(IntegerToString(timeframe));
}
//+------------------------------------------------------------------+
