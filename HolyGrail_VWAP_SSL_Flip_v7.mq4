//+------------------------------------------------------------------+
//|                HolyGrail_VWAP_SSL_Flip_v7.mq4                    |
//|  Anchored High/Low VWAP SSL flip - BIG MOVE EDITION              |
//|  v7 - Optimized for Weekly/Monthly VWAP on small TF to catch     |
//|       big moves 1:3, 1:5, 1:10+                                  |
//|                                                                  |
//|  Core:                                                           |
//|  - Anchored VWAPs (High, Low, Typical + 1SD/2SD/3SD)             |
//|  - Hysteretic SSL: bearish->bullish only above High VWAP         |
//|  - Entry Quality Engine 0-100 with Big Move Mode                 |
//|  - Big Move scoring: anchor progress, distance to bands, RR      |
//|  - Multi-TP risk planner: 1.5R, 3R, 5R+                           |
//|  - HUD shows anchor progress, RR potential, ENTER/SKIP           |
//+------------------------------------------------------------------+
#property copyright   "Holy Grail VWAP SSL Flip v7 - Big Move Edition"
#property description "Weekly/Monthly VWAP on small TF for 1:3 1:5+ moves with scored ENTER/SKIP"
#property version     "7.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 12
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
#property indicator_color11 clrGold       // BandUp3
#property indicator_color12 clrGold       // BandDown3

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
enum ENUM_SL_MODE
{
   SL_ATR = 0,
   SL_OPPOSITE_VWAP,
   SL_BAND1,
   SL_STRUCTURE
};

//--- Anchor
input string            InpHeaderAnchor = "==== ANCHOR (use Weekly/Monthly on M15/H1 for big moves) ====";
input ENUM_VWAP_ANCHOR  AnchorPeriod = ANCHOR_WEEKLY;
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

//--- SSL
input string            InpHeaderSSL = "==== SSL STATE ====";
input bool              CarryTrendAcrossAnchors = true;
input ENUM_INITIAL_TREND InitialTrend = INITIAL_AUTO;

//--- Visuals
input string            InpHeaderVisual = "==== VISUALS ====";
input color             UpTrendColor = clrLimeGreen;
input color             DownTrendColor = clrTomato;
input int               SSLLineWidth = 2;
input bool              ShowBands = true;
input color             Band1Color = clrDodgerBlue;
input color             Band2Color = clrSilver;
input color             Band3Color = clrGold;
input double            Band1Deviation = 1.0;
input double            Band2Deviation = 2.0;
input double            Band3Deviation = 3.0;
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

//--- Entry Quality Engine
input string            InpHeaderEntry = "==== ENTRY QUALITY ENGINE ====";
input bool              UseEntryFilter = true;
input bool              AlertOnlyHighQuality = true;
input int               MinScoreToEnter = 68;
input int               MinScoreToCaution = 50;
input double            MinBreakoutATR = 0.10;
input double            MinVolumeFactor = 1.10;
input int               VolumeMAPeriod = 20;
input bool              UseADXFilter = true;
input int               ADXPeriod = 14;
input double            MinADX = 16.0;
input bool              UseEMAFilter = true;
input int               EMAFast = 50;
input int               EMASlow = 200;
input bool              RequireEMABias = false;
input int               MinBarsBetweenFlips = 5;
input bool              AvoidChopZone = true;
input double            ChopThresholdATR = 0.40;
input double            MaxSpreadATR = 0.35;
input bool              UseBandPositionBonus = true;

//--- BIG MOVE MODE - for Weekly/Monthly on small TF catching 1:3 1:5+
input string            InpHeaderBigMove = "==== BIG MOVE MODE (Weekly/Monthly on M15/H1) ====";
input bool              UseBigMoveMode = true; // Enable big move scoring for 1:3 1:5+
input double            BigMoveMinRR = 3.0; // Minimum RR to be considered big move
input bool              AvoidLateAnchor = true; // Avoid entering late in anchor period
input double            MaxAnchorProgress = 0.80; // Don't enter after 80% through week/month
input bool              PreferEarlyAnchor = true; // Bonus for entering early in week/month
input double            EarlyAnchorBonusThreshold = 0.35; // Bonus if progress <35%
input bool              CheckBandExhaustion = true; // Avoid if price already beyond 2.5SD
input double            ExhaustionSD = 2.5; // Beyond this SD = exhausted
input bool              UseBigMoveRRFilter = true; // Require potential RR >= BigMoveMinRR to ENTER
input double            MinDistanceToBandATR = 2.0; // Need at least 2 ATR to opposite band for big move
input bool              ShowBigMoveLines = true; // Draw TP lines for 1.5R 3R 5R

//--- Risk planner - multi TP for big moves
input string            InpHeaderRisk = "==== RISK PLANNER (Multi-TP for big moves) ====";
input bool              ShowRiskPlanner = true;
input ENUM_SL_MODE      SLMode = SL_ATR; // SL calculation mode
input bool              UseEquityForRisk = true;
input double            ManualRiskCapital = 0.0;
input double            RiskPercent = 0.50;
input double            StopLossATR = 1.50;
input double            RewardRiskRatio = 3.00; // Main RR, use 3.0 for big moves
input double            TP1_RR = 1.5;
input double            TP2_RR = 3.0;
input double            TP3_RR = 5.0;
input double            TP4_RR = 8.0;

//--- Alerts
input string            InpHeaderAlert = "==== ALERTS ====";
input bool              EnableAlerts = true;
input bool              PopupAlert = false;
input bool              SoundAlert = false;
input string            AlertSoundFile = "alert.wav";
input bool              EmailAlert = false;
input bool              PushAlert = false;
input bool              AlertOncePerFlipBar = true;
input bool              AlertOnAttach = false;

//--- HUD
input string            InpHeaderHUD = "==== HUD ====";
input bool              ShowHUD = true;
input int               HUDCorner = 0;
input int               HUDX = 18;
input int               HUDY = 24;
input int               HUDWidth = 340;
input int               HUDHeight = 420;
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
double BandUp3[];
double BandDown3[];

//--- internal
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
double gAnchorProgress[];
double gBigMoveRR[];
int    gTrend[];
int    gDecision[];
string gReason[];
int    gBarsSinceFlip[];

const long INVALID_ANCHOR = -1;
datetime gLastAlertTime = 0;
int gLastAlertTrend = 0;
bool gAlertsPrimed = false;
string gHUDPrefix = "";
int gLastFlipIndex = -1;
datetime gLastFlipTime = 0;
datetime gAnchorStartTime = 0;

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorBuffers(12);
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
   SetIndexBuffer(10, BandUp3);
   SetIndexBuffer(11, BandDown3);

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
   ArraySetAsSeries(BandUp3, true);
   ArraySetAsSeries(BandDown3, true);

   if(ArrowATRPeriod < 1 || ArrowOffsetATR < 0.0 || Band1Deviation < 0.0 || Band2Deviation < 0.0 ||
      ManualRiskCapital < 0.0 || RiskPercent < 0.0 || RiskPercent > 100.0 || StopLossATR <= 0.0 ||
      RewardRiskRatio <= 0.0 || VolumeMAPeriod < 2 || MinScoreToEnter < 0 || MinScoreToEnter > 100 ||
      MinScoreToCaution < 0 || MinScoreToCaution > 100 || ADXPeriod < 2 || EMAFast < 2 || EMASlow < 2 ||
      MinBarsBetweenFlips < 0 || MinBreakoutATR < 0.0 || MinVolumeFactor < 0.0 || ChopThresholdATR < 0.0 ||
      BigMoveMinRR < 0 || MaxAnchorProgress < 0 || MaxAnchorProgress > 1.0 || EarlyAnchorBonusThreshold < 0 || EarlyAnchorBonusThreshold > 1.0)
   {
      Print("HolyGrail v7: invalid numeric input");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(MinScoreToCaution > MinScoreToEnter)
   {
      Print("HolyGrail v7: MinScoreToCaution should be <= MinScoreToEnter");
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
   SetIndexStyle(10, ShowBands ? DRAW_LINE : DRAW_NONE, STYLE_DOT, 1, Band3Color);
   SetIndexStyle(11, ShowBands ? DRAW_LINE : DRAW_NONE, STYLE_DOT, 1, Band3Color);

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
   SetIndexLabel(10, "Typical +3SD");
   SetIndexLabel(11, "Typical -3SD");

   for(int i=0;i<12;i++) SetIndexEmptyValue(i, EMPTY_VALUE);

   IndicatorDigits(Digits);
   IndicatorShortName("Holy Grail VWAP SSL v7 BIG MOVE ("+AnchorLabel()+")");

   gLastAlertTime = 0;
   gLastAlertTrend = 0;
   gAlertsPrimed = false;
   gLastFlipIndex = -1;
   gHUDPrefix = "HGSSL7_HUD_" + IntegerToString((int)ChartID()) + "_" + HUDInstanceTag + "_";
   DeleteHUDObjects();
   DeleteBigMoveLines();
   if(ShowHUD) EnsureHUDObjects();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteHUDObjects();
   DeleteBigMoveLines();
}

//+------------------------------------------------------------------+
//| Main calc                                                        |
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
   gLastFlipIndex = -1;
   int lastFlipAbsolute = -1;
   datetime anchorStart = 0;

   for(int i=rates_total-1; i>=0; i--)
   {
      ClearDrawBuffers(i);
      gEntryScore[i] = 0;
      gDecision[i] = DECISION_NONE;
      gBarsSinceFlip[i] = 9999;
      gAnchorProgress[i] = 0;
      gBigMoveRR[i] = 0;

      long anchor = AnchorKey(time[i]);
      datetime thisAnchorStart = AnchorStartTime(time[i]);
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
         anchorStart=0;
         continue;
      }
      if(anchor!=activeAnchor)
      {
         sumVolume=0; highVWAP=0; lowVWAP=0; typicalVWAP=0; typicalM2=0;
         activeAnchor=anchor;
         anchorStart = thisAnchorStart;
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

      // anchor progress
      double progress = CalculateAnchorProgress(time[i], anchorStart);
      gAnchorProgress[i]=progress;
      if(i==0) gAnchorStartTime = anchorStart;

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
         if(lastFlipAbsolute==-1) gBarsSinceFlip[i]=9999;
         else gBarsSinceFlip[i]= lastFlipAbsolute - i;
      }
      else
      {
         if(lastFlipAbsolute==-1) gBarsSinceFlip[i]=9999;
         else gBarsSinceFlip[i]= lastFlipAbsolute - i;
      }

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

      if(ShowBands)
      {
         BandUp1[i]=gTypicalVWAP[i]+Band1Deviation*gStdDev[i];
         BandDown1[i]=gTypicalVWAP[i]-Band1Deviation*gStdDev[i];
         BandUp2[i]=gTypicalVWAP[i]+Band2Deviation*gStdDev[i];
         BandDown2[i]=gTypicalVWAP[i]-Band2Deviation*gStdDev[i];
         BandUp3[i]=gTypicalVWAP[i]+Band3Deviation*gStdDev[i];
         BandDown3[i]=gTypicalVWAP[i]-Band3Deviation*gStdDev[i];
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

         int decision = DECISION_SKIP;
         double score = 0;
         string reason = "";
         double bigMoveRR = 0;
         ComputeEntryQuality(i, state, priorState, close, high, low, time, tick_volume, volume, score, decision, reason, bigMoveRR);

         gEntryScore[i]=score;
         gDecision[i]=decision;
         gReason[i]=reason;
         gBigMoveRR[i]=bigMoveRR;

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
   }

   ProcessAlert(time, close, rates_total);
   UpdateHUD(close[0], rates_total, time);
   if(ShowBigMoveLines) DrawBigMoveLines(close[0], rates_total);
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Resize                                                           |
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
   ArrayResize(gAnchorProgress,size); ArraySetAsSeries(gAnchorProgress,true);
   ArrayResize(gBigMoveRR,size); ArraySetAsSeries(gBigMoveRR,true);
}
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
   BandUp3[i]=EMPTY_VALUE;
   BandDown3[i]=EMPTY_VALUE;
}
double BarVolume(const int i, const long &tick_volume[], const long &volume[])
{
   double w = (double)tick_volume[i];
   if(VWAPVolume==VOLUME_REAL_WITH_TICK_FALLBACK && volume[i]>0) w=(double)volume[i];
   if(w<=0.0) w=1.0;
   return(w);
}
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
void CalculateADXandEMA(const int rates_total)
{
   for(int i=0;i<rates_total;i++)
   {
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
//| ENTRY QUALITY + BIG MOVE                                         |
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
                         string &outReason,
                         double &outBigMoveRR)
{
   outScore=0;
   outDecision=DECISION_SKIP;
   outReason="";
   outBigMoveRR=0;

   if(!UseEntryFilter)
   {
      outScore=100;
      outDecision=DECISION_ENTER;
      outReason="Filter disabled => ENTER";
      outBigMoveRR=RewardRiskRatio;
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
   if(newTrend>0) breakoutDist = close[idx] - highVWAP;
   else breakoutDist = lowVWAP - close[idx];

   double breakoutATR = breakoutDist / atr;
   double channelWidth = highVWAP - lowVWAP;
   double channelATR = (atr>0) ? channelWidth/atr : 0;
   double progress = gAnchorProgress[idx];

   // big move RR calculation: distance to opposite 2SD band / SL
   double slDist = 0;
   if(SLMode==SL_ATR) slDist = atr*StopLossATR;
   else if(SLMode==SL_OPPOSITE_VWAP) slDist = MathAbs(close[idx] - (newTrend>0? lowVWAP : highVWAP));
   else if(SLMode==SL_BAND1) slDist = MathAbs(close[idx] - (newTrend>0? typicalVWAP - Band1Deviation*stddev : typicalVWAP + Band1Deviation*stddev));
   else slDist = atr*StopLossATR;
   if(slDist<=0) slDist = atr*StopLossATR;

   double target2SD = (newTrend>0) ? typicalVWAP + Band2Deviation*stddev : typicalVWAP - Band2Deviation*stddev;
   double distTo2SD = MathAbs(target2SD - close[idx]);
   double rrTo2SD = (slDist>0) ? distTo2SD/slDist : 0;
   outBigMoveRR = rrTo2SD;

   // distance to 3SD for ultra big move
   double target3SD = (newTrend>0) ? typicalVWAP + Band3Deviation*stddev : typicalVWAP - Band3Deviation*stddev;
   double distTo3SD = MathAbs(target3SD - close[idx]);
   double rrTo3SD = (slDist>0) ? distTo3SD/slDist : 0;

   double scoreBreakout=0, scoreVolume=0, scoreADX=0, scoreEMA=0, scoreChop=0, scoreFlipGap=0, scoreBand=0, scoreSpread=0;
   double scoreBigMove=0, scoreAnchor=0;

   // 1. Breakout 0-20 (reduced to make room for big move)
   if(breakoutATR >= MinBreakoutATR*2.0) scoreBreakout=20;
   else if(breakoutATR >= MinBreakoutATR) scoreBreakout= 12 + 8*(breakoutATR - MinBreakoutATR)/MinBreakoutATR;
   else if(breakoutATR >= 0) scoreBreakout= 12 * breakoutATR / MathMax(0.0001, MinBreakoutATR);
   else scoreBreakout=0;
   if(breakoutATR<0) scoreBreakout=0;

   // 2. Volume 0-15
   if(volRatio >= MinVolumeFactor*1.3) scoreVolume=15;
   else if(volRatio >= MinVolumeFactor) scoreVolume=9 + 6*(volRatio - MinVolumeFactor)/(MinVolumeFactor*0.3);
   else if(volRatio >= 1.0) scoreVolume= 6 + 3*(volRatio-1.0)/(MinVolumeFactor-1.0);
   else if(volRatio >= 0.7) scoreVolume= 3 * (volRatio-0.7)/0.3;
   else scoreVolume=0;

   // 3. ADX 0-10
   if(!UseADXFilter) scoreADX=10;
   else
   {
      double adx = gADX[idx];
      if(adx >= MinADX*1.5) scoreADX=10;
      else if(adx >= MinADX) scoreADX=6 + 4*(adx - MinADX)/(MinADX*0.5);
      else if(adx >= MinADX*0.7) scoreADX= 3 + 3*(adx - MinADX*0.7)/(MinADX*0.3);
      else scoreADX= 2 * adx / MathMax(0.1, MinADX*0.7);
   }

   // 4. EMA 0-10
   if(!UseEMAFilter) scoreEMA=10;
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
      if(aligned) scoreEMA=10;
      else if(neutral) scoreEMA=5;
      else scoreEMA=0;
      if(RequireEMABias && opposite)
      {
         outScore=0;
         outDecision=DECISION_SKIP;
         outReason=StringFormat("SKIP: EMA misaligned | Vol %.2f Brk %.2fATR ADX %.1f", volRatio, breakoutATR, gADX[idx]);
         return;
      }
   }

   // 5. Chop 0-8
   if(!AvoidChopZone) scoreChop=8;
   else
   {
      if(channelATR >= ChopThresholdATR*1.8) scoreChop=8;
      else if(channelATR >= ChopThresholdATR) scoreChop=4 + 4*(channelATR - ChopThresholdATR)/(ChopThresholdATR*0.8);
      else scoreChop= 4 * channelATR / MathMax(0.0001, ChopThresholdATR);
   }

   // 6. Gap 0-7
   int barsSince = gBarsSinceFlip[idx];
   if(barsSince>=MinBarsBetweenFlips*3) scoreFlipGap=7;
   else if(barsSince>=MinBarsBetweenFlips) scoreFlipGap=3 + 4*(barsSince - MinBarsBetweenFlips)/(MinBarsBetweenFlips*2.0);
   else if(barsSince>=0) scoreFlipGap= 3 * barsSince / MathMax(1, MinBarsBetweenFlips);
   else scoreFlipGap=7;

   // 7. Band bonus 0-5
   if(!UseBandPositionBonus) scoreBand=5;
   else
   {
      double prevTypical = (idx+1 < ArraySize(gTypicalVWAP)) ? gTypicalVWAP[idx+1] : typicalVWAP;
      double prevStd = (idx+1 < ArraySize(gStdDev)) ? gStdDev[idx+1] : stddev;
      double prevClose = (idx+1 < ArraySize(close)) ? close[idx+1] : close[idx];
      bool wasBeyondBand = false;
      if(newTrend>0) wasBeyondBand = (prevClose < prevTypical - Band1Deviation*prevStd);
      else wasBeyondBand = (prevClose > prevTypical + Band1Deviation*prevStd);
      scoreBand = wasBeyondBand ? 5 : 2;
   }

   // 8. Spread 0-5
   double spreadPoints = MarketInfo(Symbol(), MODE_SPREAD);
   double spreadPrice = spreadPoints * Point;
   double spreadATR = (atr>0) ? spreadPrice/atr : 0;
   if(spreadATR <= MaxSpreadATR*0.5) scoreSpread=5;
   else if(spreadATR <= MaxSpreadATR) scoreSpread= 2 + 3*(MaxSpreadATR - spreadATR)/(MaxSpreadATR*0.5);
   else scoreSpread=0;

   // 9. Big Move RR potential 0-15 (NEW for weekly/monthly big moves)
   if(!UseBigMoveMode) scoreBigMove=15;
   else
   {
      // Need at least MinDistanceToBandATR to opposite band and RR >= BigMoveMinRR
      double minDistOK = (distTo2SD >= atr*MinDistanceToBandATR) ? 1 : 0;
      if(rrTo2SD >= BigMoveMinRR*1.5) scoreBigMove=15;
      else if(rrTo2SD >= BigMoveMinRR) scoreBigMove=10 + 5*(rrTo2SD - BigMoveMinRR)/(BigMoveMinRR*0.5);
      else if(rrTo2SD >= BigMoveMinRR*0.6) scoreBigMove= 5 + 5*(rrTo2SD - BigMoveMinRR*0.6)/(BigMoveMinRR*0.4);
      else scoreBigMove= 3 * rrTo2SD / MathMax(0.1, BigMoveMinRR*0.6);

      if(minDistOK==0) scoreBigMove *= 0.5; // penalize if too close to band

      // Exhaustion check: if price already beyond 2.5SD, penalize heavily
      if(CheckBandExhaustion)
      {
         double distFromTypical = MathAbs(close[idx] - typicalVWAP);
         double sdMultiple = (stddev>0) ? distFromTypical/stddev : 0;
         if(sdMultiple >= ExhaustionSD)
         {
            scoreBigMove *= 0.2; // 80% penalty if exhausted
         }
      }

      // Require RR filter: if UseBigMoveRRFilter and RR < BigMoveMinRR*0.7, force low score
      if(UseBigMoveRRFilter && rrTo2SD < BigMoveMinRR*0.5)
      {
         scoreBigMove = MathMin(scoreBigMove, 2);
      }
   }

   // 10. Anchor progress 0-5 (NEW)
   if(!UseBigMoveMode || !AvoidLateAnchor) scoreAnchor=5;
   else
   {
      if(progress <= EarlyAnchorBonusThreshold && PreferEarlyAnchor) scoreAnchor=5;
      else if(progress <= MaxAnchorProgress*0.7) scoreAnchor=4;
      else if(progress <= MaxAnchorProgress) scoreAnchor=2 + 2*(MaxAnchorProgress - progress)/(MaxAnchorProgress*0.3);
      else scoreAnchor=0; // late anchor

      if(progress > MaxAnchorProgress)
      {
         // late anchor = forced caution/skip for big moves
         // don't force skip completely, but heavily penalize
         scoreAnchor=0;
      }
   }

   outScore = scoreBreakout + scoreVolume + scoreADX + scoreEMA + scoreChop + scoreFlipGap + scoreBand + scoreSpread + scoreBigMove + scoreAnchor;
   outScore = MathMin(100, MathMax(0, outScore));

   if(outScore >= MinScoreToEnter) outDecision=DECISION_ENTER;
   else if(outScore >= MinScoreToCaution) outDecision=DECISION_CAUTION;
   else outDecision=DECISION_SKIP;

   // extra: if big move mode and late anchor and RR filter, force SKIP if progress > max and RR low
   if(UseBigMoveMode && AvoidLateAnchor && progress > MaxAnchorProgress && UseBigMoveRRFilter && rrTo2SD < BigMoveMinRR)
   {
      outDecision=DECISION_SKIP;
   }

   string decisionStr = (outDecision==DECISION_ENTER?"ENTER":(outDecision==DECISION_CAUTION?"CAUTION":"SKIP"));
   outReason = StringFormat("%s (%.0f) RR%.1f->2SD %.1f->3SD | B:%.0f V:%.0f ADX:%.0f EMA:%.0f BM:%.0f AP:%.0f | Volx%.2f Brk%.2fATR ADX%.0f Prog%.0f%% %dbars",
                    decisionStr, outScore, rrTo2SD, rrTo3SD,
                    scoreBreakout, scoreVolume, scoreADX, scoreEMA, scoreBigMove, scoreAnchor,
                    volRatio, breakoutATR, gADX[idx], progress*100, barsSince);
}

//+------------------------------------------------------------------+
//| Risk plan multi TP                                               |
//+------------------------------------------------------------------+
bool CalculateRiskPlan(const double entryPrice, const int trend, double &stopPrice, double &targetPrice, double &riskMoney, double &lots, double &tp1, double &tp2, double &tp3, double &tp4)
{
   stopPrice=0; targetPrice=0; riskMoney=0; lots=-1; tp1=0; tp2=0; tp3=0; tp4=0;
   if(!ShowRiskPlanner || RiskPercent<=0.0 || trend==0) return(false);
   if(ArraySize(gATR)<1 || gATR[0]<=0.0 || gATR[0]==EMPTY_VALUE) return(false);
   double capital = ManualRiskCapital;
   if(capital<=0.0) capital = UseEquityForRisk ? AccountEquity() : AccountBalance();
   if(capital<=0.0) return(false);
   double atr = gATR[0];
   double slDist = 0;
   if(SLMode==SL_ATR) slDist = atr*StopLossATR;
   else if(SLMode==SL_OPPOSITE_VWAP) slDist = MathAbs(entryPrice - (trend>0? gLowVWAP[0] : gHighVWAP[0]));
   else if(SLMode==SL_BAND1)
   {
      double band = (trend>0) ? gTypicalVWAP[0] - Band1Deviation*gStdDev[0] : gTypicalVWAP[0] + Band1Deviation*gStdDev[0];
      slDist = MathAbs(entryPrice - band);
   }
   else slDist = atr*StopLossATR;
   if(slDist<=0) slDist = atr*StopLossATR;
   if(slDist<=0) return(false);
   riskMoney = capital*RiskPercent/100.0;
   stopPrice = NormalizeDouble(trend>0 ? entryPrice - slDist : entryPrice + slDist, Digits);
   targetPrice = NormalizeDouble(trend>0 ? entryPrice + slDist*RewardRiskRatio : entryPrice - slDist*RewardRiskRatio, Digits);
   tp1 = NormalizeDouble(trend>0 ? entryPrice + slDist*TP1_RR : entryPrice - slDist*TP1_RR, Digits);
   tp2 = NormalizeDouble(trend>0 ? entryPrice + slDist*TP2_RR : entryPrice - slDist*TP2_RR, Digits);
   tp3 = NormalizeDouble(trend>0 ? entryPrice + slDist*TP3_RR : entryPrice - slDist*TP3_RR, Digits);
   tp4 = NormalizeDouble(trend>0 ? entryPrice + slDist*TP4_RR : entryPrice - slDist*TP4_RR, Digits);

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(tickValue<=0.0 || tickSize<=0.0 || minLot<=0.0 || maxLot<=0.0) return(true);
   if(lotStep<=0.0) lotStep=minLot;
   double moneyPerLot = slDist / tickSize * tickValue;
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
int InitialTrendState(const double closePrice, const double highVWAP, const double lowVWAP)
{
   if(InitialTrend==INITIAL_BULLISH) return(1);
   if(InitialTrend==INITIAL_BEARISH) return(-1);
   double mid = (highVWAP+lowVWAP)/2.0;
   return(closePrice>=mid ? 1 : -1);
}
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
datetime AnchorStartTime(const datetime barTime)
{
   if(AnchorPeriod==ANCHOR_CUSTOM_TIME) return(CustomAnchorTime);
   if(AnchorPeriod==ANCHOR_DAILY) return(StartOfDay(barTime));
   if(AnchorPeriod==ANCHOR_WEEKLY)
   {
      datetime day=StartOfDay(barTime);
      int dow = TimeDayOfWeek(barTime);
      int daysSinceMonday = (dow+6)%7;
      return(day - daysSinceMonday*86400);
   }
   if(AnchorPeriod==ANCHOR_MONTHLY)
   {
      return(StrToTime(StringFormat("%04d.%02d.01 00:00", TimeYear(barTime), TimeMonth(barTime))));
   }
   if(AnchorPeriod==ANCHOR_QUARTERLY)
   {
      int q = (TimeMonth(barTime)-1)/3;
      int m = q*3+1;
      return(StrToTime(StringFormat("%04d.%02d.01 00:00", TimeYear(barTime), m)));
   }
   if(AnchorPeriod==ANCHOR_YEARLY)
   {
      return(StrToTime(StringFormat("%04d.01.01 00:00", TimeYear(barTime))));
   }
   // sessions: daily anchor at session time
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
   return(day+sessSec);
}
double CalculateAnchorProgress(const datetime barTime, const datetime anchorStart)
{
   if(anchorStart==0) return(0);
   double elapsed = (double)(barTime - anchorStart);
   double duration = 0;
   if(AnchorPeriod==ANCHOR_DAILY) duration = 86400;
   else if(AnchorPeriod==ANCHOR_WEEKLY) duration = 5*86400; // 5 trading days
   else if(AnchorPeriod==ANCHOR_MONTHLY)
   {
      // approximate days in month
      int y = TimeYear(barTime);
      int m = TimeMonth(barTime);
      int days = 31;
      if(m==2) days = ( (y%4==0 && (y%100!=0 || y%400==0)) ? 29 : 28 );
      else if(m==4 || m==6 || m==9 || m==11) days=30;
      duration = days*86400;
   }
   else if(AnchorPeriod==ANCHOR_QUARTERLY) duration = 90*86400;
   else if(AnchorPeriod==ANCHOR_YEARLY) duration = 365*86400;
   else duration = 86400; // sessions daily

   if(duration<=0) return(0);
   double prog = elapsed/duration;
   if(prog<0) prog=0;
   if(prog>1) prog=1;
   return(prog);
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
   double rr = 0;
   if(ArraySize(gBigMoveRR)>bar) rr = gBigMoveRR[bar];

   string message = StringFormat("HolyGrail v7 %s %s RR%.1f | %s %s | %s%s | %s | Bar %s | Price %s | %s",
                                 side, decisionStr, rr,
                                 Symbol(), TimeframeLabel(Period()),
                                 AnchorLabel(),
                                 scoreStr,
                                 VolumeLabel(),
                                 TimeToString(time[bar], TIME_DATE|TIME_MINUTES),
                                 DoubleToString(close[bar], Digits),
                                 reason);

   if(PopupAlert) Alert(message);
   if(SoundAlert) PlaySound(AlertSoundFile);
   if(EmailAlert) SendMail("Holy Grail v7 signal", message);
   if(PushAlert) SendNotification(message);
   gLastAlertTime=time[bar];
   gLastAlertTrend=trend;
}

//+------------------------------------------------------------------+
//| Big Move Lines                                                   |
//+------------------------------------------------------------------+
void DrawBigMoveLines(const double currentClose, const int rates_total)
{
   if(!ShowBigMoveLines || !ShowRiskPlanner || rates_total<1) return;
   if(gTrend[0]==0) return;
   double stopPrice=0, targetPrice=0, riskMoney=0, lots=-1, tp1=0, tp2=0, tp3=0, tp4=0;
   if(!CalculateRiskPlan(currentClose, gTrend[0], stopPrice, targetPrice, riskMoney, lots, tp1, tp2, tp3, tp4)) return;

   string prefix = gHUDPrefix + "BM_";
   CreateHLine(prefix+"SL", stopPrice, clrRed, STYLE_DASH, 1, "SL");
   CreateHLine(prefix+"TP1", tp1, clrOrange, STYLE_DOT, 1, StringFormat("TP1 %.1fR", TP1_RR));
   CreateHLine(prefix+"TP2", tp2, clrGold, STYLE_DOT, 1, StringFormat("TP2 %.1fR", TP2_RR));
   CreateHLine(prefix+"TP3", tp3, clrLime, STYLE_DOT, 1, StringFormat("TP3 %.1fR", TP3_RR));
   CreateHLine(prefix+"TP4", tp4, clrDodgerBlue, STYLE_DOT, 1, StringFormat("TP4 %.1fR", TP4_RR));
}
void CreateHLine(const string name, const double price, const color col, const int style, const int width, const string label)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetString(0, name, OBJPROP_TEXT, label);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}
void DeleteBigMoveLines()
{
   if(gHUDPrefix=="") return;
   string prefix = gHUDPrefix + "BM_";
   ObjectDelete(0, prefix+"SL");
   ObjectDelete(0, prefix+"TP1");
   ObjectDelete(0, prefix+"TP2");
   ObjectDelete(0, prefix+"TP3");
   ObjectDelete(0, prefix+"TP4");
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
   double lastRR = 0;
   double lastProgress = gAnchorProgress[0];

   if(lastFlip>=0)
   {
      lastScore = gEntryScore[lastFlip];
      lastReason = gReason[lastFlip];
      lastRR = gBigMoveRR[lastFlip];
      lastFlipTimeStr = TimeToString(time[lastFlip], TIME_DATE|TIME_MINUTES);
      if(gDecision[lastFlip]==DECISION_ENTER){ decisionText=StringFormat("ENTER %s (%.0f) RR%.1f", gTrend[lastFlip]>0?"BUY":"SELL", lastScore, lastRR); decisionColor=HUDEnterColor; }
      else if(gDecision[lastFlip]==DECISION_CAUTION){ decisionText=StringFormat("CAUTION %s (%.0f) RR%.1f", gTrend[lastFlip]>0?"BUY":"SELL", lastScore, lastRR); decisionColor=HUDCautionColor; }
      else { decisionText=StringFormat("SKIP %s (%.0f) RR%.1f", gTrend[lastFlip]>0?"BUY":"SELL", lastScore, lastRR); decisionColor=HUDSkipColor; }
   }

   SetHUDLabel("SUBTITLE", "Anchor: "+AnchorLabel()+" | "+VolumeLabel()+" | "+signalMode, HUDMutedColor);
   SetHUDPanelColor("STATUS_BG", trendColor);
   SetHUDLabel("STATUS", trendStr+" | Prog "+DoubleToString(lastProgress*100,0)+"%", clrWhite);

   SetHUDLabel("ROW_HIGH", "High VWAP   "+DoubleToString(gHighVWAP[0], Digits), HUDTextColor);
   SetHUDLabel("ROW_LOW", "Low VWAP    "+DoubleToString(gLowVWAP[0], Digits), HUDTextColor);
   SetHUDLabel("ROW_TYPICAL", "Typical VWAP "+DoubleToString(gTypicalVWAP[0], Digits), HUDTextColor);
   SetHUDLabel("ROW_STD", "Std Dev      "+DoubleToString(gStdDev[0], Digits), HUDTextColor);
   SetHUDLabel("ROW_MID", StringFormat("Price vs mid %+.2f%% | 2SD RR %.1fR", devPct, lastRR), HUDTextColor);
   SetHUDLabel("ROW_BAND1", StringFormat("Band 1 SD   %s / %s", DoubleToString(gTypicalVWAP[0]+Band1Deviation*gStdDev[0], Digits), DoubleToString(gTypicalVWAP[0]-Band1Deviation*gStdDev[0], Digits)), HUDTextColor);
   SetHUDLabel("ROW_BAND2", StringFormat("Band 2 SD   %s / %s", DoubleToString(gTypicalVWAP[0]+Band2Deviation*gStdDev[0], Digits), DoubleToString(gTypicalVWAP[0]-Band2Deviation*gStdDev[0], Digits)), HUDTextColor);
   SetHUDLabel("ROW_BAND3", StringFormat("Band 3 SD   %s / %s", DoubleToString(gTypicalVWAP[0]+Band3Deviation*gStdDev[0], Digits), DoubleToString(gTypicalVWAP[0]-Band3Deviation*gStdDev[0], Digits)), HUDTextColor);

   SetHUDPanelColor("DECISION_BG", decisionColor);
   SetHUDLabel("DECISION", decisionText, clrWhite);

   if(lastFlip>=0)
   {
      SetHUDLabel("DECISION_TIME", "Last flip: "+lastFlipTimeStr+" ("+IntegerToString(gBarsSinceFlip[0])+" bars ago) | Anchor "+DoubleToString(gAnchorProgress[lastFlip]*100,0)+"%", HUDTextColor);
      SetHUDLabel("DECISION_SCORE", StringFormat("Score: %.0f/100 (Enter>=%d) | BigMove RR %.1f (need %.1f)", lastScore, MinScoreToEnter, lastRR, BigMoveMinRR), HUDTextColor);
      string shortReason = lastReason;
      if(StringLen(shortReason)>75) shortReason = StringSubstr(shortReason,0,75)+"...";
      SetHUDLabel("DECISION_REASON", shortReason, HUDMutedColor);
   }
   else
   {
      SetHUDLabel("DECISION_TIME", "No flip yet | Anchor progress "+DoubleToString(lastProgress*100,0)+"%", HUDMutedColor);
      SetHUDLabel("DECISION_SCORE", "", HUDMutedColor);
      SetHUDLabel("DECISION_REASON", "", HUDMutedColor);
   }

   string checklist = BuildChecklistString(0);
   SetHUDLabel("CHECKLIST", checklist, HUDTextColor);

   double stopPrice=0, targetPrice=0, riskMoney=0, lots=-1, tp1=0, tp2=0, tp3=0, tp4=0;
   bool hasRisk = CalculateRiskPlan(currentClose, gTrend[0], stopPrice, targetPrice, riskMoney, lots, tp1, tp2, tp3, tp4);
   if(!ShowRiskPlanner) SetHUDLabel("RISK", "Risk planner: disabled", HUDMutedColor);
   else if(hasRisk)
   {
      SetHUDLabel("RISK", StringFormat("Risk %.2f%%  %s %.2f  Lots %s | SL %s", RiskPercent, AccountCurrency(), riskMoney, RiskLotsLabel(lots), DoubleToString(stopPrice, Digits)), HUDTextColor);
      SetHUDLabel("RISK_TP", StringFormat("TP1 %.1fR %s | TP2 %.1fR %s | TP3 %.1fR %s | TP4 %.1fR %s", TP1_RR, DoubleToString(tp1, Digits), TP2_RR, DoubleToString(tp2, Digits), TP3_RR, DoubleToString(tp3, Digits), TP4_RR, DoubleToString(tp4, Digits)), HUDTextColor);
   }
   else SetHUDLabel("RISK", "Risk plan: unavailable", HUDMutedColor);

   SetHUDLabel("FOOTER", "BigMove "+(UseBigMoveMode?"ON":"OFF")+" | SL:"+EnumToString(SLMode)+" | "+signalMode+" | QArrows:"+(ShowQualityArrows?"ON":"OFF"), HUDMutedColor);

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
   double prog = gAnchorProgress[idx];
   double rr = gBigMoveRR[idx];
   string chk = "";
   chk += StringFormat("Brk %.2fATR>%0.2f? %s | ", breakout, MinBreakoutATR, breakout>=MinBreakoutATR?"YES":"NO");
   chk += StringFormat("Vol x%.2f>=%.2f? %s | ", volRatio, MinVolumeFactor, volRatio>=MinVolumeFactor?"YES":"NO");
   if(UseBigMoveMode) chk+= StringFormat("RR %.1f>=%.1f? %s | Prog %.0f%%<%.0f%%? %s | ", rr, BigMoveMinRR, rr>=BigMoveMinRR?"YES":"NO", prog*100, MaxAnchorProgress*100, prog<=MaxAnchorProgress?"YES":"NO");
   if(UseADXFilter) chk+= StringFormat("ADX %.0f>=%.0f? %s", gADX[idx], MinADX, gADX[idx]>=MinADX?"YES":"NO");
   return(chk);
}
bool EnsureHUDObjects()
{
   if(!ShowHUD || gHUDPrefix=="") return(false);
   if(ObjectFind(0, HUDName("PANEL"))>=0 && ObjectFind(0, HUDName("RISK"))>=0 && ObjectFind(0, HUDName("FOOTER"))>=0) return(true);
   int corner=ClampInt(HUDCorner,0,3);
   int width=ClampInt(HUDWidth,300,600);
   int height=ClampInt(HUDHeight,380,700);
   int chartWidth=(int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartHeight=(int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int maxX=2000, maxY=2000;
   if(chartWidth>0) maxX=MathMax(0, chartWidth-width-6);
   if(chartHeight>0) maxY=MathMax(0, chartHeight-height-6);
   int x=ClampInt(HUDX,0,maxX);
   int y=ClampInt(HUDY,0,maxY);
   string font=HUDFont; if(font=="") font="Consolas";

   if(!CreateHUDPanel(HUDName("PANEL"), corner, x, y, width, height, HUDBackgroundColor, HUDBorderColor)) return(false);
   CreateHUDLabel(HUDName("TITLE"), corner, x+12, y+9, "HOLY GRAIL v7 BIG MOVE / VWAP SSL", HUDTitleColor, 10, font);
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
   CreateHUDLabel(HUDName("ROW_BAND3"), corner, x+14, y+250, "Band 3 SD   -- / --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("CHECKLIST"), corner, x+14, y+268, "", HUDTextColor, 7, font);
   CreateHUDLabel(HUDName("RISK"), corner, x+14, y+294, "Risk plan   --", HUDTextColor, 8, font);
   CreateHUDLabel(HUDName("RISK_TP"), corner, x+14, y+308, "", HUDTextColor, 7, font);
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
   SetHUDLabel("ROW_BAND3", "", HUDTextColor);
   SetHUDLabel("CHECKLIST", "", HUDMutedColor);
   SetHUDLabel("RISK", ShowRiskPlanner?"Risk plan: waiting":"Risk planner: disabled", HUDMutedColor);
   SetHUDLabel("RISK_TP", "", HUDMutedColor);
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
   DeleteHUDObject("ROW_STD"); DeleteHUDObject("ROW_MID"); DeleteHUDObject("ROW_BAND1"); DeleteHUDObject("ROW_BAND2"); DeleteHUDObject("ROW_BAND3");
   DeleteHUDObject("CHECKLIST"); DeleteHUDObject("RISK"); DeleteHUDObject("RISK_TP"); DeleteHUDObject("FOOTER");
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
