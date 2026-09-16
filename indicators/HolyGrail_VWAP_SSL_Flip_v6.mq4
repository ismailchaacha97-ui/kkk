//+------------------------------------------------------------------+
//|                HolyGrail_VWAP_SSL_Flip_v6.mq4                    |
//|  Anchored High/Low VWAP SSL flip with Entry Quality Engine       |
//|  v6 - tells you EXACTLY if you should ENTER or SKIP a flip       |
//|                                                                  |
//|  Core logic:                                                     |
//|  - Anchored VWAPs (High, Low, Typical + 1SD/2SD bands)           |
//|  - Hysteretic SSL state: bearish->bullish only above High VWAP,  |
//|    bullish->bearish only below Low VWAP                          |
//|  - Entry Quality Engine scores each flip 0-100:                  |
//|    Breakout distance / ATR, Volume confirmation, ADX trend,      |
//|    EMA bias, Chop filter, Bars since last flip, Band position    |
//|  - Decision: ENTER (>=70), CAUTION (50-69), SKIP (<50)            |
//|  - Only high-quality flips get big arrows + alerts (configurable)|
//|  - HUD shows decision, score, checklist, risk plan               |
//|  - Risk planner: sizing only, never auto-trading                 |
//+------------------------------------------------------------------+
#property copyright   "Holy Grail VWAP SSL Flip v6 - Entry Quality Engine"
#property description "Confirmed anchored High/Low VWAP SSL flip with scored ENTER/SKIP decision"
#property version     "6.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 10
#property indicator_color1 clrLimeGreen   // UpLine Bullish Low VWAP
#property indicator_color2 clrTomato      // DownLine Bearish High VWAP
#property indicator_color3 clrLimeGreen   // BuyArrow all flips
#property indicator_color4 clrTomato      // SellArrow all flips
#property indicator_color5 clrDodgerBlue  // BandUp1
#property indicator_color6 clrDodgerBlue  // BandDown1
#property indicator_color7 clrSilver      // BandUp2
#property indicator_color8 clrSilver      // BandDown2
#property indicator_color9 clrLime        // BuyEnter high quality
#property indicator_color10 clrRed        // SellEnter high quality

//--- enums
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
enum ENUM_ENTRY_DECISION
{
   DECISION_NONE = 0,
   DECISION_SKIP = 1,
   DECISION_CAUTION = 2,
   DECISION_ENTER = 3
};

//--- Anchor settings
input string            InpHeaderAnchor = "==== ANCHOR SETTINGS ===="; // Anchor
input ENUM_VWAP_ANCHOR  AnchorPeriod = ANCHOR_DAILY;
input int               LondonStartHour = 8;
input int               LondonStartMinute = 0;
input int               NewYorkStartHour = 13;
input int               NewYorkStartMinute = 30;
input int               AsiaStartHour = 0;
input int               AsiaStartMinute = 0;
input int               CustomSessionHour = 0;
input int               CustomSessionMinute = 0;
input datetime          CustomAnchorTime = D'2024.01.01 00:00';
input ENUM_VWAP_VOLUME  VWAPVolume = VOLUME_TICK;

//--- SSL state
input string            InpHeaderSSL = "==== SSL STATE ===="; // SSL
input bool              CarryTrendAcrossAnchors = true;
input ENUM_INITIAL_TREND InitialTrend = INITIAL_AUTO;

//--- Visuals
input string            InpHeaderVisual = "==== VISUALS ===="; // Visuals
input color             UpTrendColor = clrLimeGreen;
input color             DownTrendColor = clrTomato;
input int               SSLLineWidth = 2;
input bool              ShowBands = true;
input color             Band1Color = clrDodgerBlue;
input color             Band2Color = clrSilver;
input double            Band1Deviation = 1.0;
input double            Band2Deviation = 2.0;
input bool              ShowArrows = true;
input int               ArrowSize = 3;
input int               BuyArrowCode = 233;
input int               SellArrowCode = 234;
input double            ArrowOffsetATR = 0.20;
input int               ArrowATRPeriod = 14;
input bool              SignalsOnClosedBarsOnly = true;
input bool              ShowQualityArrows = true;
input int               QualityArrowSize = 4;
input int               BuyEnterArrowCode = 233;
input int               SellEnterArrowCode = 234;

//--- Entry Quality Engine - THIS IS THE CORE THAT TELLS YOU ENTER OR SKIP
input string            InpHeaderEntry = "==== ENTRY QUALITY ENGINE (ENTER vs SKIP) ===="; // Entry Filter
input bool              UseEntryFilter = true; // Enable ENTER/SKIP decision engine
input bool              AlertOnlyHighQuality = true; // Alert only ENTER-grade flips
input int               MinScoreToEnter = 70; // Score >= this = ENTER (0-100)
input int               MinScoreToCaution = 50; // Score >= this = CAUTION, else SKIP
input double            MinBreakoutATR = 0.12; // Min breakout distance in ATR units (e.g. 0.12 = 12% ATR beyond VWAP)
input double            MinVolumeFactor = 1.15; // Flip bar volume / VolMA must be >= this
input int               VolumeMAPeriod = 20; // Volume MA period
input bool              UseADXFilter = true;
input int               ADXPeriod = 14;
input double            MinADX = 18.0; // Minimum ADX to consider trending
input bool              UseEMAFilter = true;
input int               EMAFast = 50;
input int               EMASlow = 200;
input bool              RequireEMABias = false; // If true, misaligned EMA = forced SKIP
input int               MinBarsBetweenFlips = 5; // Avoid flip-flop: require N bars between flips
input bool              AvoidChopZone = true;
input double            ChopThresholdATR = 0.45; // If HighVWAP-LowVWAP < X*ATR => chop, low score
input double            MaxSpreadATR = 0.35; // If spread > X*ATR => penalize
input bool              UseBandPositionBonus = true; // Bonus if price was beyond 1SD before flip

//--- Risk planner (display only)
input string            InpHeaderRisk = "==== RISK PLANNER (display only) ===="; // Risk
input bool              ShowRiskPlanner = true;
input bool              UseEquityForRisk = true;
input double            ManualRiskCapital = 0.0;
input double            RiskPercent = 0.50;
input double            StopLossATR = 1.50;
input double            RewardRiskRatio = 2.00;

//--- Alerts
input string            InpHeaderAlert = "==== ALERTS ===="; // Alerts
input bool              EnableAlerts = true;
input bool              PopupAlert = false;
input bool              SoundAlert = false;
input string            AlertSoundFile = "alert.wav";
input bool              EmailAlert = false;
input bool              PushAlert = false;
input bool              AlertOncePerFlipBar = true;
input bool              AlertOnAttach = false;

//--- HUD
input string            InpHeaderHUD = "==== HUD ===="; // HUD
input bool              ShowHUD = true;
input int               HUDCorner = 0; // 0 TL, 1 TR, 2 BL, 3 BR
input int               HUDX = 18;
input int               HUDY = 24;
input int               HUDWidth = 320;
input int               HUDHeight = 360;
input string            HUDInstanceTag = "main";
input string            HUDFont = "Consolas";
input color             HUDBackgroundColor = C'30,30,30';
input color             HUDBorderColor = C'70,70,70';
input color             HUDTitleColor = clrWhite;
input color             HUDTextColor = clrSilver;
input color             HUDMutedColor = clrGray;
input color             HUDBullColor = clrLimeGreen;
input color             HUDBearColor = clrTomato;
input color             HUDEnterColor = clrLime;
input color             HUDSkipColor = clrTomato;
input color             HUDCautionColor = clrOrange;

//--- buffers
double UpLine[];
double DownLine[];
double BuyArrow[];
double SellArrow[];
double BandUp1[];
double BandDown1[];
double BandUp2[];
double BandDown2[];
double BuyEnterArrow[];
double SellEnterArrow[];

//--- internal series
double gHighVWAP[];
double gLowVWAP[];
double gTypicalVWAP[];
double gStdDev[];
double gATR[];
double gVolumeMA[];
double gADX[];
double gEMAFast[];
double gEMASlow[];
double gEntryScore[];
int    gTrend[];          // 1 bullish, -1 bearish, 0 NA
int    gDecision[];       // ENUM_ENTRY_DECISION
string gReason[];         // why score is what it is (only for last 100 bars to save mem)
int    gBarsSinceFlip[];

const long INVALID_ANCHOR = -1;
datetime gLastAlertTime = 0;
int gLastAlertTrend = 0;
bool gAlertsPrimed = false;
string gHUDPrefix = "";
int gLastFlipIndex = -1; // absolute index (rates_total based) of last flip
datetime gLastFlipTime = 0;

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorBuffers(10);
   SetIndexBuffer(0, UpLine);
   SetIndexBuffer(1, DownLine);
   SetIndexBuffer(2, BuyArrow);
   SetIndexBuffer(3, SellArrow);
   SetIndexBuffer(4, BandUp1);
   SetIndexBuffer(5, BandDown1);
   SetIndexBuffer(6, BandUp2);
   SetIndexBuffer(7, BandDown2);
   SetIndexBuffer(8, BuyEnterArrow);
   SetIndexBuffer(9, SellEnterArrow);

   ArraySetAsSeries(UpLine, true);
   ArraySetAsSeries(DownLine, true);
   ArraySetAsSeries(BuyArrow, true);
   ArraySetAsSeries(SellArrow, true);
   ArraySetAsSeries(BandUp1, true);
   ArraySetAsSeries(BandDown1, true);
   ArraySetAsSeries(BandUp2, true);
   ArraySetAsSeries(BandDown2, true);
   ArraySetAsSeries(BuyEnterArrow, true);
   ArraySetAsSeries(SellEnterArrow, true);

   if(ArrowATRPeriod < 1 || ArrowOffsetATR < 0.0 || Band1Deviation < 0.0 || Band2Deviation < 0.0 ||
      ManualRiskCapital < 0.0 || RiskPercent < 0.0 || RiskPercent > 100.0 || StopLossATR <= 0.0 ||
      RewardRiskRatio <= 0.0 || VolumeMAPeriod < 2 || MinScoreToEnter < 0 || MinScoreToEnter > 100 ||
      MinScoreToCaution < 0 || MinScoreToCaution > 100 || ADXPeriod < 2 || EMAFast < 2 || EMASlow < 2 ||
      MinBarsBetweenFlips < 0 || MinBreakoutATR < 0.0 || MinVolumeFactor < 0.0 || ChopThresholdATR < 0.0)
   {
      Print("HolyGrail v6: invalid numeric input");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(MinScoreToCaution > MinScoreToEnter)
   {
      Print("HolyGrail v6: MinScoreToCaution should be <= MinScoreToEnter");
      return(INIT_PARAMETERS_INCORRECT);
   }

   int lineWidth = ClampInt(SSLLineWidth,1,5);
   int arrowWidth = ClampInt(ArrowSize,1,5);
   int qArrowWidth = ClampInt(QualityArrowSize,1,5);

   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, lineWidth, UpTrendColor);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID, lineWidth, DownTrendColor);
   SetIndexStyle(2, ShowArrows ? DRAW_ARROW : DRAW_NONE, STYLE_SOLID, arrowWidth, UpTrendColor);
   SetIndexStyle(3, ShowArrows ? DRAW_ARROW : DRAW_NONE, STYLE_SOLID, arrowWidth, DownTrendColor);
   SetIndexArrow(2, BuyArrowCode);
   SetIndexArrow(3, SellArrowCode);
   SetIndexStyle(4, ShowBands ? DRAW_LINE : DRAW_NONE, STYLE_DOT, 1, Band1Color);
   SetIndexStyle(5, ShowBands ? DRAW_LINE : DRAW_NONE, STYLE_DOT, 1, Band1Color);
   SetIndexStyle(6, ShowBands ? DRAW_LINE : DRAW_NONE, STYLE_DOT, 1, Band2Color);
   SetIndexStyle(7, ShowBands ? DRAW_LINE : DRAW_NONE, STYLE_DOT, 1, Band2Color);
   SetIndexStyle(8, ShowQualityArrows ? DRAW_ARROW : DRAW_NONE, STYLE_SOLID, qArrowWidth, HUDEnterColor);
   SetIndexStyle(9, ShowQualityArrows ? DRAW_ARROW : DRAW_NONE, STYLE_SOLID, qArrowWidth, HUDSkipColor);
   SetIndexArrow(8, BuyEnterArrowCode);
   SetIndexArrow(9, SellEnterArrowCode);

   SetIndexLabel(0, "Bullish Low VWAP");
   SetIndexLabel(1, "Bearish High VWAP");
   SetIndexLabel(2, "Flip Buy (all)");
   SetIndexLabel(3, "Flip Sell (all)");
   SetIndexLabel(4, "Typical +1SD");
   SetIndexLabel(5, "Typical -1SD");
   SetIndexLabel(6, "Typical +2SD");
   SetIndexLabel(7, "Typical -2SD");
   SetIndexLabel(8, "ENTER Buy (quality)");
   SetIndexLabel(9, "ENTER Sell (quality)");

   for(int i=0;i<10;i++) SetIndexEmptyValue(i, EMPTY_VALUE);

   IndicatorDigits(Digits);
   IndicatorShortName("Holy Grail VWAP SSL v6 ENTER/SKIP ("+AnchorLabel()+")");

   gLastAlertTime = 0;
   gLastAlertTrend = 0;
   gAlertsPrimed = false;
   gLastFlipIndex = -1;
   gHUDPrefix = "HGSSL6_HUD_" + IntegerToString((int)ChartID()) + "_" + HUDInstanceTag + "_";
   DeleteHUDObjects();
   if(ShowHUD) EnsureHUDObjects();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
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
   int minBars = MathMax(3, MathMax(ArrowATRPeriod, MathMax(VolumeMAPeriod, MathMax(ADXPeriod, EMASlow))) + 2);
   if(rates_total < minBars)
   {
      for(int i=0;i<rates_total;i++) ClearDrawBuffers(i);
      if(ShowHUD) UpdateHUDWaiting("Waiting for more bars...");
      return(0);
   }

   ResizeWorkArrays(rates_total);
   CalculateATR(rates_total, high, low, close);
   CalculateVolumeMA(rates_total, tick_volume, volume);
   CalculateADXandEMA(rates_total);

   double sumVolume=0.0;
   double highVWAP=0.0;
   double lowVWAP=0.0;
   double typicalVWAP=0.0;
   double typicalM2=0.0;
   long activeAnchor = INVALID_ANCHOR;
   int state=0;
   gLastFlipIndex = -1; // will recompute each full recalc for correctness on history
   int lastFlipAbsolute = -1; // in terms of i (0 newest, large oldest)

   // walk chronologically: oldest to newest = rates_total-1 down to 0
   for(int i=rates_total-1; i>=0; i--)
   {
      ClearDrawBuffers(i);
      gEntryScore[i] = 0;
      gDecision[i] = DECISION_NONE;
      gBarsSinceFlip[i] = 9999;

      long anchor = AnchorKey(time[i]);
      if(anchor==INVALID_ANCHOR)
      {
         gHighVWAP[i]=EMPTY_VALUE;
         gLowVWAP[i]=EMPTY_VALUE;
         gTypicalVWAP[i]=EMPTY_VALUE;
         gStdDev[i]=EMPTY_VALUE;
         gTrend[i]=0;
         activeAnchor=INVALID_ANCHOR;
         state=0;
         sumVolume=0; highVWAP=0; lowVWAP=0; typicalVWAP=0; typicalM2=0;
         continue;
      }
      if(anchor!=activeAnchor)
      {
         sumVolume=0; highVWAP=0; lowVWAP=0; typicalVWAP=0; typicalM2=0;
         activeAnchor=anchor;
         if(!CarryTrendAcrossAnchors) state=0;
      }

      double weight = BarVolume(i, tick_volume, volume);
      double typical = (high[i]+low[i]+close[i])/3.0;
      double newSumVolume = sumVolume + weight;
      double alpha = weight / newSumVolume;

      highVWAP += alpha * (high[i] - highVWAP);
      lowVWAP  += alpha * (low[i] - lowVWAP);
      double delta = typical - typicalVWAP;
      typicalVWAP += alpha * delta;
      typicalM2 += weight * delta * (typical - typicalVWAP);
      sumVolume = newSumVolume;

      gHighVWAP[i]=highVWAP;
      gLowVWAP[i]=lowVWAP;
      gTypicalVWAP[i]=typicalVWAP;
      gStdDev[i]=MathSqrt(MathMax(0.0, typicalM2/sumVolume));

      int priorState = state;
      if(priorState==0)
         state = InitialTrendState(close[i], highVWAP, lowVWAP);
      else if(priorState<0 && close[i] > highVWAP)
         state = 1;
      else if(priorState>0 && close[i] < lowVWAP)
         state = -1;

      gTrend[i]=state;
      bool flipped = (priorState!=0 && state!=priorState);

      if(flipped)
      {
         if(lastFlipAbsolute==-1)
            gBarsSinceFlip[i]=9999;
         else
            gBarsSinceFlip[i]= lastFlipAbsolute - i; // since i decreasing forward in time, lastFlip older => larger index
      }
      else
      {
         if(lastFlipAbsolute==-1) gBarsSinceFlip[i]=9999;
         else gBarsSinceFlip[i]= lastFlipAbsolute - i;
      }

      // SSL lines
      if(state>0)
      {
         UpLine[i]=gLowVWAP[i];
         if(flipped) DownLine[i]=gHighVWAP[i];
      }
      else if(state<0)
      {
         DownLine[i]=gHighVWAP[i];
         if(flipped) UpLine[i]=gLowVWAP[i];
      }

      // bands
      if(ShowBands)
      {
         BandUp1[i]=gTypicalVWAP[i]+Band1Deviation*gStdDev[i];
         BandDown1[i]=gTypicalVWAP[i]-Band1Deviation*gStdDev[i];
         BandUp2[i]=gTypicalVWAP[i]+Band2Deviation*gStdDev[i];
         BandDown2[i]=gTypicalVWAP[i]-Band2Deviation*gStdDev[i];
      }

      bool canSignal = (!SignalsOnClosedBarsOnly || i>0);
      if(flipped && canSignal)
      {
         double offset = MathMax(5.0*Point, gATR[i]*ArrowOffsetATR);
         if(state>0)
         {
            if(ShowArrows) BuyArrow[i]=low[i]-offset;
         }
         else
         {
            if(ShowArrows) SellArrow[i]=high[i]+offset;
         }

         //--- compute entry quality
         int decision = DECISION_SKIP;
         double score = 0;
         string reason = "";
         ComputeEntryQuality(i, state, priorState, close, high, low, time, tick_volume, volume, score, decision, reason);

         gEntryScore[i]=score;
         gDecision[i]=decision;
         gReason[i]=reason;

         if(decision==DECISION_ENTER)
         {
            double qOffset = MathMax(8.0*Point, gATR[i]*ArrowOffsetATR*1.8);
            if(state>0)
            {
               if(ShowQualityArrows) BuyEnterArrow[i]=low[i]-qOffset;
            }
            else
            {
               if(ShowQualityArrows) SellEnterArrow[i]=high[i]+qOffset;
            }
         }

         lastFlipAbsolute = i;
         gLastFlipIndex = i;
         gLastFlipTime = time[i];
      }
      else
      {
         // not flipped, carry last flip
         if(lastFlipAbsolute!=-1 && lastFlipAbsolute!=i)
         {
            // gBarsSinceFlip already set above
         }
      }
   }

   ProcessAlert(time, close, rates_total);
   UpdateHUD(close[0], rates_total, time);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Work arrays resize                                               |
//+------------------------------------------------------------------+
void ResizeWorkArrays(const int size)
{
   ArrayResize(gHighVWAP,size); ArraySetAsSeries(gHighVWAP,true);
   ArrayResize(gLowVWAP,size); ArraySetAsSeries(gLowVWAP,true);
   ArrayResize(gTypicalVWAP,size); ArraySetAsSeries(gTypicalVWAP,true);
   ArrayResize(gStdDev,size); ArraySetAsSeries(gStdDev,true);
   ArrayResize(gATR,size); ArraySetAsSeries(gATR,true);
   ArrayResize(gTrend,size); ArraySetAsSeries(gTrend,true);
   ArrayResize(gVolumeMA,size); ArraySetAsSeries(gVolumeMA,true);
   ArrayResize(gADX,size); ArraySetAsSeries(gADX,true);
   ArrayResize(gEMAFast,size); ArraySetAsSeries(gEMAFast,true);
   ArrayResize(gEMASlow,size); ArraySetAsSeries(gEMASlow,true);
   ArrayResize(gEntryScore,size); ArraySetAsSeries(gEntryScore,true);
   ArrayResize(gDecision,size); ArraySetAsSeries(gDecision,true);
   ArrayResize(gBarsSinceFlip,size); ArraySetAsSeries(gBarsSinceFlip,true);
   ArrayResize(gReason,size); ArraySetAsSeries(gReason,true);
}

//+------------------------------------------------------------------+
//| Clear buffers for one bar                                        |
//+------------------------------------------------------------------+
void ClearDrawBuffers(const int i)
{
   UpLine[i]=EMPTY_VALUE;
   DownLine[i]=EMPTY_VALUE;
   BuyArrow[i]=EMPTY_VALUE;
   SellArrow[i]=EMPTY_VALUE;
   BandUp1[i]=EMPTY_VALUE;
   BandDown1[i]=EMPTY_VALUE;
   BandUp2[i]=EMPTY_VALUE;
   BandDown2[i]=EMPTY_VALUE;
   BuyEnterArrow[i]=EMPTY_VALUE;
   SellEnterArrow[i]=EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| Bar volume with fallback                                         |
//+------------------------------------------------------------------+
double BarVolume(const int i, const long &tick_volume[], const long &volume[])
{
   double w = (double)tick_volume[i];
   if(VWAPVolume==VOLUME_REAL_WITH_TICK_FALLBACK && volume[i]>0) w=(double)volume[i];
   if(w<=0.0) w=1.0;
   return(w);
}

//+------------------------------------------------------------------+
//| ATR Wilder                                                       |
//+------------------------------------------------------------------+
void CalculateATR(const int rates_total, const double &high[], const double &low[], const double &close[])
{
   int period = MathMax(1, ArrowATRPeriod);
   double trSum=0.0; double atr=0.0; int count=0;
   for(int i=rates_total-1; i>=0; i--)
   {
      double tr;
      if(i==rates_total-1) tr=high[i]-low[i];
      else
      {
         double pc=close[i+1];
         tr=MathMax(high[i], pc) - MathMin(low[i], pc);
      }
      tr=MathMax(0.0,tr);
      count++;
      if(count<period){ trSum+=tr; atr=trSum/count; }
      else if(count==period){ trSum+=tr; atr=trSum/period; }
      else atr=((atr*(period-1))+tr)/period;
      gATR[i]=atr;
   }
}

//+------------------------------------------------------------------+
//| Volume MA                                                        |
//+------------------------------------------------------------------+
void CalculateVolumeMA(const int rates_total, const long &tick_volume[], const long &volume[])
{
   int period = MathMax(2, VolumeMAPeriod);
   double sum=0.0;
   for(int i=rates_total-1; i>=0; i--)
   {
      double v = BarVolume(i, tick_volume, volume);
      sum+=v;
      if(i+period < rates_total)
      {
         double oldV = BarVolume(i+period, tick_volume, volume);
         sum-=oldV;
         gVolumeMA[i]=sum/period;
      }
      else
      {
         int cnt = rates_total - i;
         if(cnt>0) gVolumeMA[i]=sum/cnt;
         else gVolumeMA[i]=v;
      }
   }
}

//+------------------------------------------------------------------+
//| ADX and EMA via built-in calls                                   |
//+------------------------------------------------------------------+
void CalculateADXandEMA(const int rates_total)
{
   for(int i=0;i<rates_total;i++)
   {
      // note: i is series index (0 newest). iADX etc expect shift = i
      double adx = 0;
      if(UseADXFilter)
      {
         adx = iADX(NULL,0,ADXPeriod,PRICE_CLOSE,MODE_MAIN,i);
         if(adx==EMPTY_VALUE) adx=0;
      }
      gADX[i]=adx;
      double emaF=0, emaS=0;
      if(UseEMAFilter)
      {
         emaF = iMA(NULL,0,EMAFast,0,MODE_EMA,PRICE_CLOSE,i);
         emaS = iMA(NULL,0,EMASlow,0,MODE_EMA,PRICE_CLOSE,i);
      }
      gEMAFast[i]=emaF;
      gEMASlow[i]=emaS;
   }
}

//+------------------------------------------------------------------+
//| ENTRY QUALITY ENGINE - core decision logic                       |
//+------------------------------------------------------------------+
void ComputeEntryQuality(const int idx,
                         const int newTrend,
                         const int oldTrend,
                         const double &close[],
                         const double &high[],
                         const double &low[],
                         const datetime &time[],
                         const long &tick_volume[],
                         const long &volume[],
                         double &outScore,
                         int &outDecision,
                         string &outReason)
{
   outScore=0;
   outDecision=DECISION_SKIP;
   outReason="";

   if(!UseEntryFilter)
   {
      outScore=100;
      outDecision=DECISION_ENTER;
      outReason="Filter disabled => ENTER";
      return;
   }

   double atr = gATR[idx];
   if(atr<=0 || atr==EMPTY_VALUE) atr = (high[idx]-low[idx]);
   if(atr<=0) atr = 10*Point;

   double highVWAP = gHighVWAP[idx];
   double lowVWAP = gLowVWAP[idx];
   double typicalVWAP = gTypicalVWAP[idx];
   double stddev = gStdDev[idx];
   double vol = BarVolume(idx, tick_volume, volume);
   double volMA = gVolumeMA[idx];
   if(volMA<=0) volMA=vol;
   double volRatio = vol / volMA;

   double breakoutDist = 0;
   if(newTrend>0) breakoutDist = close[idx] - highVWAP; // bullish: how far above high VWAP
   else breakoutDist = lowVWAP - close[idx]; // bearish: how far below low VWAP

   double breakoutATR = breakoutDist / atr;
   double channelWidth = highVWAP - lowVWAP;
   double channelATR = (atr>0) ? channelWidth/atr : 0;

   //--- Scoring breakdown 0-100
   double scoreBreakout=0, scoreVolume=0, scoreADX=0, scoreEMA=0, scoreChop=0, scoreFlipGap=0, scoreBand=0, scoreSpread=0;
   string r="";

   // 1. Breakout distance (0-25 pts) - MOST IMPORTANT
   // require close beyond VWAP by MinBreakoutATR
   if(breakoutATR >= MinBreakoutATR*2.0) scoreBreakout=25;
   else if(breakoutATR >= MinBreakoutATR) scoreBreakout= 15 + 10*(breakoutATR - MinBreakoutATR)/MinBreakoutATR;
   else if(breakoutATR >= 0) scoreBreakout= 15 * breakoutATR / MathMax(0.0001, MinBreakoutATR);
   else scoreBreakout=0; // negative means didn't actually close beyond? shouldn't happen on flip
   if(breakoutATR<0) scoreBreakout=0;

   // 2. Volume confirmation (0-20 pts)
   if(volRatio >= MinVolumeFactor*1.3) scoreVolume=20;
   else if(volRatio >= MinVolumeFactor) scoreVolume=12 + 8*(volRatio - MinVolumeFactor)/(MinVolumeFactor*0.3);
   else if(volRatio >= 1.0) scoreVolume= 8 + 4*(volRatio-1.0)/(MinVolumeFactor-1.0);
   else if(volRatio >= 0.7) scoreVolume= 4 * (volRatio-0.7)/0.3;
   else scoreVolume=0;

   // 3. ADX trend strength (0-15 pts)
   if(!UseADXFilter) scoreADX=15;
   else
   {
      double adx = gADX[idx];
      if(adx >= MinADX*1.5) scoreADX=15;
      else if(adx >= MinADX) scoreADX=8 + 7*(adx - MinADX)/(MinADX*0.5);
      else if(adx >= MinADX*0.7) scoreADX= 4 + 4*(adx - MinADX*0.7)/(MinADX*0.3);
      else scoreADX= 2 * adx / MathMax(0.1, MinADX*0.7);
   }

   // 4. EMA bias (0-15 pts)
   if(!UseEMAFilter) scoreEMA=15;
   else
   {
      double emaF = gEMAFast[idx];
      double emaS = gEMASlow[idx];
      double c = close[idx];
      bool emaBullAligned = (c > emaF && emaF > emaS);
      bool emaBearAligned = (c < emaF && emaF < emaS);
      bool aligned = (newTrend>0 && emaBullAligned) || (newTrend<0 && emaBearAligned);
      bool neutral = (newTrend>0 && c>emaF) || (newTrend<0 && c<emaF);
      bool opposite = !aligned && !neutral;

      if(aligned) scoreEMA=15;
      else if(neutral) scoreEMA=7;
      else scoreEMA=0;

      if(RequireEMABias && opposite)
      {
         // force skip regardless of other scores
         outScore=0;
         outDecision=DECISION_SKIP;
         outReason=StringFormat("SKIP: EMA misaligned vs flip | Score 0 | Vol %.2f Break %.2fATR ADX %.1f",
                                volRatio, breakoutATR, gADX[idx]);
         return;
      }
   }

   // 5. Chop filter - channel width (0-10 pts)
   if(!AvoidChopZone) scoreChop=10;
   else
   {
      if(channelATR >= ChopThresholdATR*1.8) scoreChop=10;
      else if(channelATR >= ChopThresholdATR) scoreChop=5 + 5*(channelATR - ChopThresholdATR)/(ChopThresholdATR*0.8);
      else scoreChop= 5 * channelATR / MathMax(0.0001, ChopThresholdATR);
   }

   // 6. Bars since last flip (0-10 pts) - avoid whipsaw
   int barsSince = gBarsSinceFlip[idx];
   if(barsSince>=MinBarsBetweenFlips*3) scoreFlipGap=10;
   else if(barsSince>=MinBarsBetweenFlips) scoreFlipGap=4 + 6*(barsSince - MinBarsBetweenFlips)/(MinBarsBetweenFlips*2.0);
   else if(barsSince>=0) scoreFlipGap= 4 * barsSince / MathMax(1, MinBarsBetweenFlips);
   else scoreFlipGap=10; // first flip

   // 7. Band position bonus (0-5 pts)
   if(!UseBandPositionBonus) scoreBand=5;
   else
   {
      // check if previous bar was beyond 1SD opposite side (mean reversion + breakout)
      double prevTypical = (idx+1 < ArraySize(gTypicalVWAP)) ? gTypicalVWAP[idx+1] : typicalVWAP;
      double prevStd = (idx+1 < ArraySize(gStdDev)) ? gStdDev[idx+1] : stddev;
      double prevClose = (idx+1 < ArraySize(close)) ? close[idx+1] : close[idx];
      bool wasBeyondBand = false;
      if(newTrend>0) // bullish flip, was price below -1SD before?
         wasBeyondBand = (prevClose < prevTypical - Band1Deviation*prevStd);
      else
         wasBeyondBand = (prevClose > prevTypical + Band1Deviation*prevStd);
      scoreBand = wasBeyondBand ? 5 : 2;
   }

   // 8. Spread penalty (subtract up to -5? we do 0-5 pts where low spread = high score)
   double spreadPoints = MarketInfo(Symbol(), MODE_SPREAD);
   double spreadPrice = spreadPoints * Point;
   double spreadATR = (atr>0) ? spreadPrice/atr : 0;
   if(spreadATR <= MaxSpreadATR*0.5) scoreSpread=5;
   else if(spreadATR <= MaxSpreadATR) scoreSpread= 2 + 3*(MaxSpreadATR - spreadATR)/(MaxSpreadATR*0.5);
   else scoreSpread=0;

   outScore = scoreBreakout + scoreVolume + scoreADX + scoreEMA + scoreChop + scoreFlipGap + scoreBand + scoreSpread;
   outScore = MathMin(100, MathMax(0, outScore));

   if(outScore >= MinScoreToEnter) outDecision=DECISION_ENTER;
   else if(outScore >= MinScoreToCaution) outDecision=DECISION_CAUTION;
   else outDecision=DECISION_SKIP;

   // build reason string for HUD / logs
   string decisionStr = (outDecision==DECISION_ENTER?"ENTER":(outDecision==DECISION_CAUTION?"CAUTION":"SKIP"));
   r = StringFormat("%s (%.0f) | B:%.0f V:%.0f ADX:%.0f EMA:%.0f CH:%.0f GAP:%.0f BD:%.0f SP:%.0f | Volx%.2f Brk%.2fATR ADX%.1f Ch%.2fATR %dbars",
                    decisionStr, outScore,
                    scoreBreakout, scoreVolume, scoreADX, scoreEMA, scoreChop, scoreFlipGap, scoreBand, scoreSpread,
                    volRatio, breakoutATR, gADX[idx], channelATR, barsSince);
   outReason = r;
}

//+------------------------------------------------------------------+
//| Risk plan (display only)                                         |
//+------------------------------------------------------------------+
bool CalculateRiskPlan(const double entryPrice, const int trend, double &stopPrice, double &targetPrice, double &riskMoney, double &lots)
{
   stopPrice=0; targetPrice=0; riskMoney=0; lots=-1;
   if(!ShowRiskPlanner || RiskPercent<=0.0 || trend==0) return(false);
   if(ArraySize(gATR)<1 || gATR[0]<=0.0 || gATR[0]==EMPTY_VALUE) return(false);
   double capital = ManualRiskCapital;
   if(capital<=0.0) capital = UseEquityForRisk ? AccountEquity() : AccountBalance();
   if(capital<=0.0) return(false);
   double stopDist = gATR[0]*StopLossATR;
   if(stopDist<=0.0) return(false);
   riskMoney = capital*RiskPercent/100.0;
   stopPrice = NormalizeDouble(trend>0 ? entryPrice - stopDist : entryPrice + stopDist, Digits);
   targetPrice = NormalizeDouble(trend>0 ? entryPrice + stopDist*RewardRiskRatio : entryPrice - stopDist*RewardRiskRatio, Digits);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(tickValue<=0.0 || tickSize<=0.0 || minLot<=0.0 || maxLot<=0.0) return(true);
   if(lotStep<=0.0) lotStep=minLot;
   double moneyPerLot = stopDist / tickSize * tickValue;
   if(moneyPerLot<=0.0) return(true);
   double rawLots = riskMoney / moneyPerLot;
   if(rawLots>=minLot)
   {
      lots = MathFloor(rawLots/lotStep+0.000000001)*lotStep;
      lots = MathMin(lots, maxLot);
      lots = NormalizeDouble(lots, LotDigits(lotStep));
      if(lots<minLot) lots=0.0;
   }
   else lots=0.0;
   return(true);
}
int LotDigits(const double lotStep)
{
   int digits=0; double scaled=lotStep;
   while(digits<8 && MathAbs(scaled-MathRound(scaled))>0.000000001){ scaled*=10.0; digits++; }
   return(digits);
}
string RiskLotsLabel(const double lots)
{
   if(lots<0.0) return("n/a");
   if(lots==0.0) return("below min");
   double step=MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step<=0.0) step=0.01;
   return(DoubleToString(lots, LotDigits(step)));
}

//+------------------------------------------------------------------+
//| Initial trend                                                    |
//+------------------------------------------------------------------+
int InitialTrendState(const double closePrice, const double highVWAP, const double lowVWAP)
{
   if(InitialTrend==INITIAL_BULLISH) return(1);
   if(InitialTrend==INITIAL_BEARISH) return(-1);
   double mid = (highVWAP+lowVWAP)/2.0;
   return(closePrice>=mid ? 1 : -1);
}

//+------------------------------------------------------------------+
//| Anchor key                                                       |
//+------------------------------------------------------------------+
long AnchorKey(const datetime barTime)
{
   if(AnchorPeriod==ANCHOR_CUSTOM_TIME)
      return(barTime>=CustomAnchorTime ? (long)CustomAnchorTime : INVALID_ANCHOR);
   if(AnchorPeriod==ANCHOR_DAILY) return((long)StartOfDay(barTime));
   if(AnchorPeriod==ANCHOR_WEEKLY)
   {
      datetime day=StartOfDay(barTime);
      int dow = TimeDayOfWeek(barTime);
      int daysSinceMonday = (dow+6)%7;
      return((long)(day - daysSinceMonday*86400));
   }
   int year=TimeYear(barTime);
   int month=TimeMonth(barTime);
   if(AnchorPeriod==ANCHOR_MONTHLY) return((long)(year*12+month));
   if(AnchorPeriod==ANCHOR_QUARTERLY) return((long)(year*4+(month-1)/3));
   if(AnchorPeriod==ANCHOR_YEARLY) return((long)year);
   int hour=CustomSessionHour;
   int minute=CustomSessionMinute;
   if(AnchorPeriod==ANCHOR_LONDON){ hour=LondonStartHour; minute=LondonStartMinute; }
   else if(AnchorPeriod==ANCHOR_NEW_YORK){ hour=NewYorkStartHour; minute=NewYorkStartMinute; }
   else if(AnchorPeriod==ANCHOR_ASIA){ hour=AsiaStartHour; minute=AsiaStartMinute; }
   hour=ClampInt(hour,0,23); minute=ClampInt(minute,0,59);
   int sessSec=hour*3600+minute*60;
   datetime day=StartOfDay(barTime);
   int secIntoDay=(int)(barTime-day);
   if(secIntoDay<sessSec) day-=86400;
   return((long)(day+sessSec));
}
datetime StartOfDay(const datetime value)
{
   return(value - TimeHour(value)*3600 - TimeMinute(value)*60 - TimeSeconds(value));
}
int ClampInt(const int value, const int minimum, const int maximum)
{
   if(value<minimum) return(minimum);
   if(value>maximum) return(maximum);
   return(value);
}

//+------------------------------------------------------------------+
//| Alerts                                                           |
//+------------------------------------------------------------------+
void ProcessAlert(const datetime &time[], const double &close[], const int rates_total)
{
   if(!EnableAlerts || rates_total<2) return;
   int bar = SignalsOnClosedBarsOnly ? 1 : 0;
   if(bar+1>=rates_total) return;
   if(gTrend[bar]==0 || gTrend[bar+1]==0) return;
   if(!gAlertsPrimed)
   {
      gAlertsPrimed=true;
      if(!AlertOnAttach){ gLastAlertTime=time[bar]; gLastAlertTrend=gTrend[bar]; return; }
   }
   bool buy = (gTrend[bar]>0 && gTrend[bar+1]<0);
   bool sell = (gTrend[bar]<0 && gTrend[bar+1]>0);
   if(!buy && !sell) return;

   // filter by quality if requested
   if(AlertOnlyHighQuality && UseEntryFilter)
   {
      if(gDecision[bar]!=DECISION_ENTER) return;
   }

   int trend = buy ? 1 : -1;
   if(AlertOncePerFlipBar && time[bar]==gLastAlertTime && trend==gLastAlertTrend) return;

   string side = buy ? "BUY" : "SELL";
   string decisionStr = "UNKNOWN";
   if(ArraySize(gDecision)>bar)
   {
      if(gDecision[bar]==DECISION_ENTER) decisionStr="ENTER";
      else if(gDecision[bar]==DECISION_CAUTION) decisionStr="CAUTION";
      else if(gDecision[bar]==DECISION_SKIP) decisionStr="SKIP";
   }
   string scoreStr = "";
   if(ArraySize(gEntryScore)>bar) scoreStr = StringFormat(" Score %.0f", gEntryScore[bar]);

   string reason = "";
   if(ArraySize(gReason)>bar) reason = gReason[bar];

   string message = StringFormat("HolyGrail v6 %s %s | %s %s | %s%s | %s | Bar %s | Price %s | %s",
                                 side, decisionStr,
                                 Symbol(), TimeframeLabel(Period()),
                                 AnchorLabel(),
                                 scoreStr,
                                 VolumeLabel(),
                                 TimeToString(time[bar], TIME_DATE|TIME_MINUTES),
                                 DoubleToString(close[bar], Digits),
                                 reason);

   if(PopupAlert) Alert(message);
   if(SoundAlert) PlaySound(AlertSoundFile);
   if(EmailAlert) SendMail("Holy Grail v6 signal", message);
   if(PushAlert) SendNotification(message);
   gLastAlertTime=time[bar];
   gLastAlertTrend=trend;
}

//+------------------------------------------------------------------+
//| HUD                                                              |
//+------------------------------------------------------------------+
void UpdateHUD(const double currentClose, const int rates_total, const datetime &time[])
{
   if(!ShowHUD){ DeleteHUDObjects(); return; }
   if(!EnsureHUDObjects()) return;
   if(rates_total<1 || gTypicalVWAP[0]==EMPTY_VALUE)
   {
      UpdateHUDWaiting("Waiting for custom anchor...");
      return;
   }

   double mid = (gHighVWAP[0]+gLowVWAP[0])/2.0;
   double devPct = (mid!=0.0) ? (currentClose-mid)/mid*100.0 : 0.0;
   bool bullish = (gTrend[0]>0);
   string trendStr = bullish ? "BULLISH" : "BEARISH";
   color trendColor = bullish ? HUDBullColor : HUDBearColor;

   string signalMode = SignalsOnClosedBarsOnly ? "closed candles" : "live candle";

   // find last flip bar
   int lastFlip = -1;
   for(int i=0;i<rates_total && i<500;i++)
   {
      if(gDecision[i]!=DECISION_NONE) { lastFlip=i; break; }
   }

   string decisionText = "NO FLIP YET";
   color decisionColor = HUDMutedColor;
   double lastScore = 0;
   string lastReason = "";
   string lastFlipTimeStr = "-";

   if(lastFlip>=0)
   {
      lastScore = gEntryScore[lastFlip];
      lastReason = gReason[lastFlip];
      lastFlipTimeStr = TimeToString(time[lastFlip], TIME_DATE|TIME_MINUTES);
      if(gDecision[lastFlip]==DECISION_ENTER){ decisionText=StringFormat("ENTER %s (%.0f)", gTrend[lastFlip]>0?"BUY":"SELL", lastScore); decisionColor=HUDEnterColor; }
      else if(gDecision[lastFlip]==DECISION_CAUTION){ decisionText=StringFormat("CAUTION %s (%.0f)", gTrend[lastFlip]>0?"BUY":"SELL", lastScore); decisionColor=HUDCautionColor; }
      else { decisionText=StringFormat("SKIP %s (%.0f)", gTrend[lastFlip]>0?"BUY":"SELL", lastScore); decisionColor=HUDSkipColor; }
   }

   SetHUDLabel("SUBTITLE", "Anchor: "+AnchorLabel()+" | "+VolumeLabel()+" | "+signalMode, HUDMutedColor);
   SetHUDPanelColor("STATUS_BG", trendColor);
   SetHUDLabel("STATUS", trendStr, clrWhite);

   SetHUDLabel("ROW_HIGH", "High VWAP   "+DoubleToString(gHighVWAP[0], Digits), HUDTextColor);
   SetHUDLabel("ROW_LOW", "Low VWAP    "+DoubleToString(gLowVWAP[0], Digits), HUDTextColor);
   SetHUDLabel("ROW_TYPICAL", "Typical VWAP "+DoubleToString(gTypicalVWAP[0], Digits), HUDTextColor);
   SetHUDLabel("ROW_STD", "Std Dev      "+DoubleToString(gStdDev[0], Digits), HUDTextColor);
   SetHUDLabel("ROW_MID", StringFormat("Price vs mid %+.2f%%", devPct), HUDTextColor);
   SetHUDLabel("ROW_BAND1", StringFormat("Band 1 SD   %s / %s", DoubleToString(gTypicalVWAP[0]+Band1Deviation*gStdDev[0], Digits), DoubleToString(gTypicalVWAP[0]-Band1Deviation*gStdDev[0], Digits)), HUDTextColor);
   SetHUDLabel("ROW_BAND2", StringFormat("Band 2 SD   %s / %s", DoubleToString(gTypicalVWAP[0]+Band2Deviation*gStdDev[0], Digits), DoubleToString(gTypicalVWAP[0]-Band2Deviation*gStdDev[0], Digits)), HUDTextColor);

   // decision panel
   SetHUDPanelColor("DECISION_BG", decisionColor);
   SetHUDLabel("DECISION", decisionText, clrWhite);

   if(lastFlip>=0)
   {
      SetHUDLabel("DECISION_TIME", "Last flip: "+lastFlipTimeStr+" ("+IntegerToString(gBarsSinceFlip[0])+" bars ago)", HUDTextColor);
      SetHUDLabel("DECISION_SCORE", StringFormat("Score: %.0f/100 (Enter>=%d Caution>=%d)", lastScore, MinScoreToEnter, MinScoreToCaution), HUDTextColor);
      // truncate reason for HUD
      string shortReason = lastReason;
      if(StringLen(shortReason)>65) shortReason = StringSubstr(shortReason,0,65)+"...";
      SetHUDLabel("DECISION_REASON", shortReason, HUDMutedColor);
   }
   else
   {
      SetHUDLabel("DECISION_TIME", "No flip yet in this anchor", HUDMutedColor);
      SetHUDLabel("DECISION_SCORE", "", HUDMutedColor);
      SetHUDLabel("DECISION_REASON", "", HUDMutedColor);
   }

   // checklist
   string checklist = BuildChecklistString(0);
   SetHUDLabel("CHECKLIST", checklist, HUDTextColor);

   double stopPrice=0, targetPrice=0, riskMoney=0, lots=-1;
   bool hasRisk = CalculateRiskPlan(currentClose, gTrend[0], stopPrice, targetPrice, riskMoney, lots);
   if(!ShowRiskPlanner) SetHUDLabel("RISK", "Risk planner: disabled", HUDMutedColor);
   else if(hasRisk) SetHUDLabel("RISK", StringFormat("Risk %.2f%%  %s %.2f  Lots %s", RiskPercent, AccountCurrency(), riskMoney, RiskLotsLabel(lots)), HUDTextColor);
   else SetHUDLabel("RISK", "Risk plan: unavailable", HUDMutedColor);

   if(hasRisk) SetHUDLabel("FOOTER", StringFormat("SL %s | TP %s | %s", DoubleToString(stopPrice, Digits), DoubleToString(targetPrice, Digits), signalMode), HUDMutedColor);
   else SetHUDLabel("FOOTER", "Signals: "+signalMode+" | Quality arrows: "+(ShowQualityArrows?"ON":"OFF"), HUDMutedColor);

   ChartRedraw();
}

string BuildChecklistString(int idx)
{
   if(!UseEntryFilter) return("Filter OFF => all flips are ENTER");
   double atr = gATR[idx];
   if(atr<=0 || atr==EMPTY_VALUE) atr=1;
   double highVWAP = gHighVWAP[idx];
   double lowVWAP = gLowVWAP[idx];
   double curClose = iClose(NULL,0,idx);
   double breakout = 0;
   if(gTrend[idx]>0) breakout = (curClose - highVWAP)/atr;
   else if(gTrend[idx]<0) breakout = (lowVWAP - curClose)/atr;
   double volRatio = 0;
   double volMA = gVolumeMA[idx];
   if(volMA>0) volRatio = (double)iVolume(NULL,0,idx) / volMA;
   string chk = "";
   chk += StringFormat("Brk %.2fATR>%0.2f? %s | ", breakout, MinBreakoutATR, breakout>=MinBreakoutATR?"YES":"NO");
   chk += StringFormat("Vol x%.2f>=%.2f? %s | ", volRatio, MinVolumeFactor, volRatio>=MinVolumeFactor?"YES":"NO");
   if(UseADXFilter) chk+= StringFormat("ADX %.0f>=%.0f? %s | ", gADX[idx], MinADX, gADX[idx]>=MinADX?"YES":"NO");
   if(AvoidChopZone)
   {
      double ch = (highVWAP-lowVWAP)/atr;
      chk+= StringFormat("Ch %.2fATR>=%.2f? %s", ch, ChopThresholdATR, ch>=ChopThresholdATR?"YES":"NO");
   }
   return(chk);
}

bool EnsureHUDObjects()
{
   if(!ShowHUD || gHUDPrefix=="") return(false);
   if(ObjectFind(0, HUDName("PANEL"))>=0 && ObjectFind(0, HUDName("RISK"))>=0 && ObjectFind(0, HUDName("FOOTER"))>=0) return(true);
   int corner=ClampInt(HUDCorner,0,3);
   int width=ClampInt(HUDWidth,280,600);
   int height=ClampInt(HUDHeight,320,600);
   int chartWidth=(int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartHeight=(int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int maxX=2000, maxY=2000;
   if(chartWidth>0) maxX=MathMax(0, chartWidth-width-6);
   if(chartHeight>0) maxY=MathMax(0, chartHeight-height-6);
   int x=ClampInt(HUDX,0,maxX);
   int y=ClampInt(HUDY,0,maxY);
   string font=HUDFont; if(font=="") font="Consolas";

   if(!CreateHUDPanel(HUDName("PANEL"), corner, x, y, width, height, HUDBackgroundColor, HUDBorderColor)) return(false);
   CreateHUDLabel(HUDName("TITLE"), corner, x+12, y+9, "HOLY GRAIL v6 / VWAP SSL ENTER?", HUDTitleColor, 10, font);
   CreateHUDLabel(HUDName("SUBTITLE"), corner, x+12, y+27, "Anchor: "+AnchorLabel(), HUDMutedColor, 8, font);
   CreateHUDPanel(HUDName("STATUS_BG"), corner, x+12, y+45, width-24, 20, HUDMutedColor, HUDMutedColor);
   CreateHUDLabel(HUDName("STATUS"), corner, x+22, y+47, "WAITING", clrWhite, 9, font);

   CreateHUDPanel(HUDName("DECISION_BG"), corner, x+12, y+72, width-24, 24, HUDMutedColor, HUDMutedColor);
   CreateHUDLabel(HUDName("DECISION"), corner, x+22, y+76, "NO FLIP YET", clrWhite, 10, font);

   CreateHUDLabel(HUDName("DECISION_TIME"), corner, x+14, y+104, "", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("DECISION_SCORE"), corner, x+14, y+118, "", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("DECISION_REASON"), corner, x+14, y+132, "", HUDMutedColor, 7, font);

   CreateHUDLabel(HUDName("ROW_HIGH"), corner, x+14, y+152, "High VWAP   --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("ROW_LOW"), corner, x+14, y+166, "Low VWAP    --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("ROW_TYPICAL"), corner, x+14, y+180, "Typical VWAP --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("ROW_STD"), corner, x+14, y+194, "Std Dev      --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("ROW_MID"), corner, x+14, y+208, "Price vs mid --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("ROW_BAND1"), corner, x+14, y+222, "Band 1 SD   -- / --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("ROW_BAND2"), corner, x+14, y+236, "Band 2 SD   -- / --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("CHECKLIST"), corner, x+14, y+254, "", HUDTextColor, 7, font);
   CreateHUDLabel(HUDName("RISK"), corner, x+14, y+280, "Risk plan   --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("FOOTER"), corner, x+14, y+height-20, "Signals: closed candles", HUDMutedColor, 8, font);
   return(true);
}
void UpdateHUDWaiting(const string message)
{
   if(!ShowHUD){ DeleteHUDObjects(); return; }
   if(!EnsureHUDObjects()) return;
   SetHUDLabel("SUBTITLE", AnchorLabel(), HUDMutedColor);
   SetHUDPanelColor("STATUS_BG", HUDMutedColor);
   SetHUDLabel("STATUS", "WAITING", clrWhite);
   SetHUDPanelColor("DECISION_BG", HUDMutedColor);
   SetHUDLabel("DECISION", "WAITING", clrWhite);
   SetHUDLabel("DECISION_TIME", "", HUDMutedColor);
   SetHUDLabel("DECISION_SCORE", "", HUDMutedColor);
   SetHUDLabel("DECISION_REASON", message, HUDTextColor);
   SetHUDLabel("ROW_HIGH", message, HUDTextColor);
   SetHUDLabel("ROW_LOW", "", HUDTextColor);
   SetHUDLabel("ROW_TYPICAL", "", HUDTextColor);
   SetHUDLabel("ROW_STD", "", HUDTextColor);
   SetHUDLabel("ROW_MID", "", HUDTextColor);
   SetHUDLabel("ROW_BAND1", "", HUDTextColor);
   SetHUDLabel("ROW_BAND2", "", HUDTextColor);
   SetHUDLabel("CHECKLIST", "", HUDMutedColor);
   SetHUDLabel("RISK", ShowRiskPlanner?"Risk plan: waiting":"Risk planner: disabled", HUDMutedColor);
   SetHUDLabel("FOOTER", "Signals: closed candles", HUDMutedColor);
   ChartRedraw();
}
string HUDName(const string suffix){ return(gHUDPrefix+suffix); }
bool CreateHUDPanel(const string name, const int corner, const int x, const int y, const int width, const int height, const color background, const color border)
{
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0)) return(false);
   ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   return(true);
}
bool CreateHUDLabel(const string name, const int corner, const int x, const int y, const string text, const color textColor, const int fontSize, const string font)
{
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_LABEL,0,0,0)) return(false);
   ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,textColor);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_FONT,font);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   return(true);
}
void SetHUDLabel(const string suffix, const string text, const color textColor)
{
   string name=HUDName(suffix);
   if(ObjectFind(0,name)<0) return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,textColor);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}
void SetHUDPanelColor(const string suffix, const color background)
{
   string name=HUDName(suffix);
   if(ObjectFind(0,name)>=0) ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
}
void DeleteHUDObject(const string suffix){ if(gHUDPrefix!="") ObjectDelete(0, HUDName(suffix)); }
void DeleteHUDObjects()
{
   DeleteHUDObject("PANEL"); DeleteHUDObject("TITLE"); DeleteHUDObject("SUBTITLE");
   DeleteHUDObject("STATUS_BG"); DeleteHUDObject("STATUS");
   DeleteHUDObject("DECISION_BG"); DeleteHUDObject("DECISION");
   DeleteHUDObject("DECISION_TIME"); DeleteHUDObject("DECISION_SCORE"); DeleteHUDObject("DECISION_REASON");
   DeleteHUDObject("ROW_HIGH"); DeleteHUDObject("ROW_LOW"); DeleteHUDObject("ROW_TYPICAL");
   DeleteHUDObject("ROW_STD"); DeleteHUDObject("ROW_MID"); DeleteHUDObject("ROW_BAND1"); DeleteHUDObject("ROW_BAND2");
   DeleteHUDObject("CHECKLIST"); DeleteHUDObject("RISK"); DeleteHUDObject("FOOTER");
}
string VolumeLabel(){ if(VWAPVolume==VOLUME_REAL_WITH_TICK_FALLBACK) return("Real volume"); return("Tick volume"); }
string AnchorLabel()
{
   if(AnchorPeriod==ANCHOR_WEEKLY) return("Weekly");
   if(AnchorPeriod==ANCHOR_MONTHLY) return("Monthly");
   if(AnchorPeriod==ANCHOR_QUARTERLY) return("Quarterly");
   if(AnchorPeriod==ANCHOR_YEARLY) return("Yearly");
   if(AnchorPeriod==ANCHOR_LONDON) return("London Session");
   if(AnchorPeriod==ANCHOR_NEW_YORK) return("New York Session");
   if(AnchorPeriod==ANCHOR_ASIA) return("Asia Session");
   if(AnchorPeriod==ANCHOR_CUSTOM_SESSION) return("Custom Session");
   if(AnchorPeriod==ANCHOR_CUSTOM_TIME) return("Custom Time");
   return("Daily");
}
string TimeframeLabel(const int timeframe)
{
   if(timeframe==PERIOD_M1) return("M1");
   if(timeframe==PERIOD_M5) return("M5");
   if(timeframe==PERIOD_M15) return("M15");
   if(timeframe==PERIOD_M30) return("M30");
   if(timeframe==PERIOD_H1) return("H1");
   if(timeframe==PERIOD_H4) return("H4");
   if(timeframe==PERIOD_D1) return("D1");
   if(timeframe==PERIOD_W1) return("W1");
   if(timeframe==PERIOD_MN1) return("MN1");
   return(IntegerToString(timeframe));
}
//+------------------------------------------------------------------+
