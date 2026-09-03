//+------------------------------------------------------------------+
//|                                                      JobPick.mq4 |
//|   One indicator, five jobs:                                       |
//|     Bias / fair value ..... VWAP (intraday) or 200 EMA (swing)    |
//|     Trend structure ....... 20 / 50 EMA                           |
//|     Momentum / trigger .... RSI(14) or MACD histogram             |
//|     Participation ......... Volume / RVOL                         |
//|     Risk .................. ATR (stop, target, trailing stop)     |
//|                                                                  |
//|   Main-chart overlay + on-chart dashboard.                        |
//|   NOTE: MQL4 can only draw in ONE window per indicator, so the    |
//|   oscillator is reported numerically in the dashboard instead of  |
//|   a sub-window. (Ask for JobPick_Osc.mq4 if you want it plotted.) |
//+------------------------------------------------------------------+
#property copyright "JobPick"
#property version   "1.00"
#property strict
#property description "Bias + Trend + Momentum + Participation + Risk in one overlay"
#property indicator_chart_window

#property indicator_buffers 8
#property indicator_color1  Orange          // VWAP
#property indicator_color2  DeepSkyBlue     // bias EMA (200)
#property indicator_color3  Lime            // fast EMA (20)
#property indicator_color4  Gold            // slow EMA (50)
#property indicator_color5  MediumSeaGreen  // ATR trailing stop (longs)
#property indicator_color6  OrangeRed       // ATR trailing stop (shorts)
#property indicator_color7  Lime            // buy arrow
#property indicator_color8  Red             // sell arrow

#define PREFIX     "JobPick_"
#define ARROW_UP   233
#define ARROW_DOWN 234

//+------------------------------------------------------------------+
//| Enums                                                             |
//+------------------------------------------------------------------+
enum ENUM_BIAS_MODE
  {
   BIAS_VWAP = 0,   // VWAP (intraday fair value)
   BIAS_EMA  = 1,   // 200 EMA (swing fair value)
   BIAS_BOTH = 2    // Both must agree
  };

enum ENUM_MOM_MODE
  {
   MOM_RSI  = 0,    // RSI(14) + slope
   MOM_MACD = 1     // MACD histogram + zero-line cross
  };

enum ENUM_VWAP_ANCHOR
  {
   VWAP_DAY   = 0,  // Reset at broker midnight
   VWAP_WEEK  = 1,  // Reset at start of week (Monday)
   VWAP_HOURS = 2   // Reset at custom broker hour
  };

enum ENUM_VOL_SOURCE
  {
   VOL_TICK = 0,    // Tick volume (every MT4 broker)
   VOL_REAL = 1     // Real volume (exchange instruments)
  };

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
//--- 1. Bias / fair value
input ENUM_BIAS_MODE   InpBiasMode         = BIAS_VWAP;  // Bias source
input bool             InpShowVWAP         = true;       // Draw VWAP
input ENUM_VWAP_ANCHOR InpVWAPAnchor       = VWAP_DAY;   // VWAP anchor
input int              InpSessionStartHour = 0;          // Start hour (VWAP_HOURS only)
input bool             InpShowEMABias      = true;       // Draw 200 EMA
input int              InpEMABiasPeriod    = 200;        // Bias EMA period

//--- 2. Trend structure
input bool             InpShowTrendEMAs    = true;       // Draw 20/50 EMA
input int              InpEMAFast          = 20;         // Fast EMA
input int              InpEMASlow          = 50;         // Slow EMA

//--- 3. Momentum / trigger
input ENUM_MOM_MODE    InpMomentumMode     = MOM_RSI;    // Momentum engine
input int              InpRSIPeriod        = 14;         // RSI period
input int              InpRSIMid           = 50;         // RSI bull/bear line
input int              InpRSIOversold      = 35;         // RSI oversold (bounce trigger)
input int              InpRSIOverbought    = 65;         // RSI overbought (fade trigger)
input int              InpMACDFast         = 12;         // MACD fast
input int              InpMACDSlow         = 26;         // MACD slow
input int              InpMACDSignal       = 9;          // MACD signal

//--- 4. Participation
input ENUM_VOL_SOURCE  InpVolumeSource     = VOL_TICK;   // Volume source
input int              InpRVOLPeriod       = 20;         // RVOL average period
input double           InpRVOLThreshold    = 1.20;       // RVOL "strong" threshold

//--- 5. Risk (ATR)
input int              InpATRPeriod        = 14;         // ATR period
input double           InpATRStopMult      = 1.50;       // Stop = ATR x this
input double           InpRiskReward       = 2.00;       // Target = stop x this
input bool             InpShowATRTrail     = true;       // Draw ATR trailing stop
input bool             InpShowLevels       = true;       // Draw last SL / TP lines

//--- 6. Signals & alerts
input int              InpMinScore         = 4;          // Min confluence (1-4) to fire
input bool             InpShowArrows       = true;       // Draw signal arrows
input bool             InpAlertOnSignal    = true;       // Pop-up alert
input bool             InpPushOnSignal     = false;      // Push notification

//--- 7. Dashboard
input bool             InpShowDashboard    = true;       // Show dashboard
input int              InpPanelCorner      = 0;          // Corner 0=TL 1=TR 2=BL 3=BR
input int              InpFontSize         = 9;          // Font size

//--- 8. Performance
input int              InpMaxBars          = 2000;       // Max bars calculated

//+------------------------------------------------------------------+
//| Buffers                                                           |
//+------------------------------------------------------------------+
double VWAPBuf[];
double EMABiasBuf[];
double EMAFastBuf[];
double EMASlowBuf[];
double TrailUpBuf[];
double TrailDnBuf[];
double BuyArrowBuf[];
double SellArrowBuf[];

//+------------------------------------------------------------------+
//| Globals (state carried between calls)                             |
//+------------------------------------------------------------------+
int      g_sigDir        = 0;     // last bar's alignment direction (-1/0/1)
int      g_trailDir      = 0;     // trailing-stop direction
double   g_trailVal      = 0.0;   // trailing-stop level
datetime g_lastAlertTime = 0;

int      g_sigType       = 0;     // last signal: +1 buy / -1 sell
double   g_sigPrice      = 0.0;
double   g_sigStop       = 0.0;
double   g_sigTarget     = 0.0;
datetime g_sigTime       = 0;

//--- bar-0 snapshot for the dashboard
double   g_dFair=0.0, g_dATR=0.0, g_dRSI=0.0, g_dHist=0.0, g_dRVOL=0.0;
int      g_bullScore=0, g_bearScore=0, g_dirNow=0;
bool     g_bBiasBull=false, g_bTrendBull=false, g_bMomBull=false, g_bVolOK=false;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- buffers
   SetIndexBuffer(0,VWAPBuf);      SetIndexLabel(0,"VWAP");
   SetIndexBuffer(1,EMABiasBuf);   SetIndexLabel(1,"EMA Bias");
   SetIndexBuffer(2,EMAFastBuf);   SetIndexLabel(2,"EMA Fast");
   SetIndexBuffer(3,EMASlowBuf);   SetIndexLabel(3,"EMA Slow");
   SetIndexBuffer(4,TrailUpBuf);   SetIndexLabel(4,"ATR Trail Long");
   SetIndexBuffer(5,TrailDnBuf);   SetIndexLabel(5,"ATR Trail Short");
   SetIndexBuffer(6,BuyArrowBuf);  SetIndexLabel(6,"Buy");
   SetIndexBuffer(7,SellArrowBuf); SetIndexLabel(7,"Sell");

//--- styles
   SetIndexStyle(0,DRAW_LINE,STYLE_SOLID,2);
   SetIndexStyle(1,DRAW_LINE,STYLE_SOLID,2);
   SetIndexStyle(2,DRAW_LINE,STYLE_SOLID,1);
   SetIndexStyle(3,DRAW_LINE,STYLE_SOLID,1);
   SetIndexStyle(4,DRAW_LINE,STYLE_DASHDOT,1);
   SetIndexStyle(5,DRAW_LINE,STYLE_DASHDOT,1);
   SetIndexStyle(6,DRAW_ARROW,STYLE_SOLID,2);
   SetIndexStyle(7,DRAW_ARROW,STYLE_SOLID,2);
   SetIndexArrow(6,ARROW_UP);
   SetIndexArrow(7,ARROW_DOWN);

//--- empty values: 0 for lines, EMPTY_VALUE for arrows
   for(int b=0; b<6; b++)
      SetIndexEmptyValue(b,0.0);
   SetIndexEmptyValue(6,EMPTY_VALUE);
   SetIndexEmptyValue(7,EMPTY_VALUE);

   SetIndexDrawBegin(1,InpEMABiasPeriod);
   SetIndexDrawBegin(2,InpEMAFast);
   SetIndexDrawBegin(3,InpEMASlow);

   ArrayInitialize(BuyArrowBuf,EMPTY_VALUE);
   ArrayInitialize(SellArrowBuf,EMPTY_VALUE);

   ArraySetAsSeries(VWAPBuf,true);
   ArraySetAsSeries(EMABiasBuf,true);
   ArraySetAsSeries(EMAFastBuf,true);
   ArraySetAsSeries(EMASlowBuf,true);
   ArraySetAsSeries(TrailUpBuf,true);
   ArraySetAsSeries(TrailDnBuf,true);
   ArraySetAsSeries(BuyArrowBuf,true);
   ArraySetAsSeries(SellArrowBuf,true);

   IndicatorShortName("JobPick("+(InpBiasMode==BIAS_EMA ? "EMA"+IntegerToString(InpEMABiasPeriod) : "VWAP")
                      +" | "+IntegerToString(InpEMAFast)+"/"+IntegerToString(InpEMASlow)
                      +" | "+(InpMomentumMode==MOM_RSI ? "RSI"+IntegerToString(InpRSIPeriod) : "MACD")
                      +" | ATR"+IntegerToString(InpATRPeriod)+")");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0,PREFIX,0,-1);
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
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
//--- indexing: newest bar = 0
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);
   ArraySetAsSeries(tick_volume,true);
   ArraySetAsSeries(volume,true);

   int minBars = (int)MathMax(InpEMASlow,InpEMABiasPeriod) + InpRVOLPeriod + 10;
   if(rates_total < minBars)
      return(0);

//--- how far back to (re)calculate
   int limit;
   if(prev_calculated <= 0)
     {
      limit = (int)MathMin(rates_total-1,InpMaxBars);
      g_sigDir=0; g_trailDir=0; g_trailVal=0.0; g_lastAlertTime=0;
      g_sigType=0; g_sigPrice=0.0; g_sigStop=0.0; g_sigTarget=0.0; g_sigTime=0;
      ArrayInitialize(BuyArrowBuf,EMPTY_VALUE);
      ArrayInitialize(SellArrowBuf,EMPTY_VALUE);
     }
   else
     {
      limit = rates_total - prev_calculated;
      if(limit < 1)
         limit = 1;
     }
   if(limit > rates_total-1)
      limit = rates_total-1;

//--- VWAP is path dependent: start from the first bar of the session holding 'limit'
   int    start   = SessionStartIndex(limit,time,rates_total);
   double cumPV   = 0.0;
   double cumVol  = 0.0;
   bool   needEMA = (InpBiasMode != BIAS_VWAP) || InpShowEMABias;
   int    minScore= (int)MathMax(1,MathMin(4,InpMinScore));

//--- oldest -> newest
   for(int i=start; i>=0; i--)
     {
      //---------------- JOB 1a: VWAP (session anchored) --------------
      if(i < rates_total-1 && SessionId(time[i]) != SessionId(time[i+1]))
        {
         cumPV  = 0.0;
         cumVol = 0.0;
        }
      double typ = (high[i] + low[i] + close[i]) / 3.0;
      double vol = VolAt(i,tick_volume,volume);
      cumPV  += typ * vol;
      cumVol += vol;
      double vwap = (cumVol > 0.0) ? cumPV / cumVol : typ;

      if(i > limit)
         continue;                        // still accumulating, nothing to plot

      //---------------- Moving averages ------------------------------
      double emaBias = 0.0;
      if(needEMA)
         emaBias = iMA(NULL,0,InpEMABiasPeriod,0,MODE_EMA,PRICE_CLOSE,i);
      double emaFast = iMA(NULL,0,InpEMAFast,0,MODE_EMA,PRICE_CLOSE,i);
      double emaSlow = iMA(NULL,0,InpEMASlow,0,MODE_EMA,PRICE_CLOSE,i);
      if(emaFast == 0.0 || emaSlow == 0.0)
         continue;

      double atr = iATR(NULL,0,InpATRPeriod,i);
      if(atr <= 0.0)
         atr = high[i] - low[i];

      //---------------- JOB 3: momentum ------------------------------
      double rsi=0.0, rsiPrev=0.0, hist=0.0, histPrev=0.0;
      if(InpMomentumMode == MOM_RSI)
        {
         rsi     = iRSI(NULL,0,InpRSIPeriod,PRICE_CLOSE,i);
         rsiPrev = iRSI(NULL,0,InpRSIPeriod,PRICE_CLOSE,i+1);
        }
      else
        {
         hist     = iMACD(NULL,0,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE,MODE_HISTOGRAM,i);
         histPrev = iMACD(NULL,0,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE,MODE_HISTOGRAM,i+1);
        }

      //---------------- JOB 4: participation (RVOL) ------------------
      double rvol  = 0.0;
      bool   volOK = true;
      if(i + InpRVOLPeriod + 1 < rates_total)
        {
         double av = 0.0;
         for(int k=1; k<=InpRVOLPeriod; k++)
            av += VolAt(i+k,tick_volume,volume);
         av /= (double)InpRVOLPeriod;
         if(av > 0.0)
           {
            rvol  = vol / av;
            volOK = (rvol >= InpRVOLThreshold);
           }
        }

      //---------------- JOB 1b: bias / fair value --------------------
      bool biasBull=false, biasBear=false;
      if(InpBiasMode == BIAS_VWAP)
        {
         biasBull = (close[i] > vwap);
         biasBear = (close[i] < vwap);
        }
      else if(InpBiasMode == BIAS_EMA)
        {
         if(emaBias > 0.0)
           {
            biasBull = (close[i] > emaBias);
            biasBear = (close[i] < emaBias);
           }
        }
      else if(emaBias > 0.0)
        {
         biasBull = (close[i] > vwap && close[i] > emaBias);
         biasBear = (close[i] < vwap && close[i] < emaBias);
        }

      //---------------- JOB 2: trend structure -----------------------
      bool trendBull = (emaFast > emaSlow);
      bool trendBear = (emaFast < emaSlow);

      //---------------- JOB 3b: momentum trigger ---------------------
      bool momBull=false, momBear=false;
      if(InpMomentumMode == MOM_RSI)
        {
         momBull = ((rsi > InpRSIMid && rsi > rsiPrev) ||
                    (rsiPrev <= InpRSIOversold && rsi > rsiPrev));
         momBear = ((rsi < InpRSIMid && rsi < rsiPrev) ||
                    (rsiPrev >= InpRSIOverbought && rsi < rsiPrev));
        }
      else
        {
         momBull = ((hist > 0.0 && hist > histPrev) || (histPrev <= 0.0 && hist > 0.0));
         momBear = ((hist < 0.0 && hist < histPrev) || (histPrev >= 0.0 && hist < 0.0));
        }

      //---------------- Confluence score (out of 4) ------------------
      int bullScore = (biasBull ?1:0) + (trendBull ?1:0) + (momBull ?1:0) + (volOK ?1:0);
      int bearScore = (biasBear ?1:0) + (trendBear ?1:0) + (momBear ?1:0) + (volOK ?1:0);

      int dirNow = 0;
      int score  = 0;
      if(bullScore >= minScore && bullScore > bearScore)
        { dirNow = 1;  score = bullScore; }
      else
      if(bearScore >= minScore && bearScore > bullScore)
        { dirNow = -1; score = bearScore; }

      //---------------- Plot buffers ---------------------------------
      VWAPBuf[i]    = (InpShowVWAP ? vwap : 0.0);
      EMABiasBuf[i] = (InpShowEMABias && emaBias > 0.0) ? emaBias : 0.0;
      EMAFastBuf[i] = (InpShowTrendEMAs ? emaFast : 0.0);
      EMASlowBuf[i] = (InpShowTrendEMAs ? emaSlow : 0.0);

      //---------------- JOB 5: ATR trailing stop ---------------------
      double stopDist = atr * InpATRStopMult;
      if(dirNow == 1)
        {
         double s = close[i] - stopDist;
         g_trailVal = (g_trailDir != 1) ? s : MathMax(g_trailVal,s);
         g_trailDir = 1;
        }
      else
      if(dirNow == -1)
        {
         double s = close[i] + stopDist;
         g_trailVal = (g_trailDir != -1) ? s : MathMin(g_trailVal,s);
         g_trailDir = -1;
        }

      if(InpShowATRTrail && g_trailDir == 1)
        { TrailUpBuf[i] = g_trailVal; TrailDnBuf[i] = 0.0; }
      else
      if(InpShowATRTrail && g_trailDir == -1)
        { TrailDnBuf[i] = g_trailVal; TrailUpBuf[i] = 0.0; }
      else
        { TrailUpBuf[i] = 0.0; TrailDnBuf[i] = 0.0; }

      //---------------- Signals (closed bars only, no repaint) -------
      if(InpShowArrows && i >= 1 && dirNow != 0 && dirNow != g_sigDir)
        {
         if(dirNow == 1)
            BuyArrowBuf[i]  = low[i] - atr * 0.35;
         else
            SellArrowBuf[i] = high[i] + atr * 0.35;

         g_sigType   = dirNow;
         g_sigPrice  = close[i];
         g_sigStop   = (dirNow == 1) ? close[i] - stopDist : close[i] + stopDist;
         g_sigTarget = (dirNow == 1) ? close[i] + stopDist * InpRiskReward
                                     : close[i] - stopDist * InpRiskReward;
         g_sigTime   = time[i];

         //--- alert only on the bar that just closed
         if(i == 1 && prev_calculated > 0 && time[i] != g_lastAlertTime)
           {
            g_lastAlertTime = time[i];
            string msg = "JobPick "+Symbol()+" "+TFToString()+" : "
                         +((dirNow==1) ? "BUY" : "SELL")
                         +" @ "+DoubleToString(close[i],_Digits)
                         +" | SL "+DoubleToString(g_sigStop,_Digits)
                         +" | TP "+DoubleToString(g_sigTarget,_Digits)
                         +" | ATR "+DoubleToString(atr/_Point,1)+"pt"
                         +" | RVOL "+DoubleToString(rvol,2)
                         +" | score "+IntegerToString(score)+"/4";
            if(InpAlertOnSignal)
               Alert(msg);
            if(InpPushOnSignal)
               SendNotification(msg);
           }
        }
      g_sigDir = dirNow;

      //---------------- Dashboard snapshot (bar 0) -------------------
      if(i == 0)
        {
         g_dFair      = (InpBiasMode == BIAS_EMA) ? emaBias : vwap;
         g_dATR       = atr;
         g_dRSI       = rsi;
         g_dHist      = hist;
         g_dRVOL      = rvol;
         g_bullScore  = bullScore;
         g_bearScore  = bearScore;
         g_dirNow     = dirNow;
         g_bBiasBull  = biasBull;
         g_bTrendBull = trendBull;
         g_bMomBull   = momBull;
         g_bVolOK     = volOK;
        }
     }

//--- on-chart output
   if(InpShowLevels)
      DrawLevels();
   else
      DeleteLevels();

   if(InpShowDashboard)
      DrawPanel();
   else
      DeletePanel();

   ChartRedraw();
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Volume at bar i                                                   |
//+------------------------------------------------------------------+
double VolAt(int i,const long &tick_volume[],const long &volume[])
  {
   double v = (InpVolumeSource == VOL_REAL) ? (double)volume[i] : (double)tick_volume[i];
   if(v <= 0.0)
      v = (double)tick_volume[i];      // fallback
   if(v <= 0.0)
      v = 1.0;                          // broker reports no volume -> neutral weight
   return(v);
  }

//+------------------------------------------------------------------+
//| Session id (unique per VWAP anchor period)                        |
//+------------------------------------------------------------------+
int SessionId(datetime t)
  {
   MqlDateTime st;
   if(!TimeToStruct(t,st))
      return(0);

   if(InpVWAPAnchor == VWAP_WEEK)       // bucket on the week's Monday
     {
      int back = (st.day_of_week + 6) % 7;
      return(st.year*1000 + (st.day_of_year - back));
     }

   if(InpVWAPAnchor == VWAP_HOURS)      // custom session start (broker time)
     {
      MqlDateTime sd;
      if(!TimeToStruct(t - InpSessionStartHour*3600,sd))
         return(0);
      return(sd.year*1000 + sd.day_of_year);
     }

   return(st.year*1000 + st.day_of_year);   // broker day
  }

//+------------------------------------------------------------------+
//| Index of the oldest bar in the session containing bar i           |
//+------------------------------------------------------------------+
int SessionStartIndex(int i,const datetime &time[],int rates_total)
  {
   int id    = SessionId(time[i]);
   int k     = i;
   int max   = rates_total - 1;
   int guard = 0;
   while(k < max && guard < 50000)
     {
      if(SessionId(time[k+1]) != id)
         break;
      k++;
      guard++;
     }
   return(k);
  }

//+------------------------------------------------------------------+
//| Timeframe name                                                    |
//+------------------------------------------------------------------+
string TFToString()
  {
   switch(Period())
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN");
     }
   return("M"+IntegerToString(Period()/60));
  }

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void DrawPanel()
  {
   int corner = (int)MathMax(0,MathMin(3,InpPanelCorner));
   int fs     = (int)MathMax(7,MathMin(14,InpFontSize));
   int lh     = fs + 4;
   int x      = 14;
   int y      = 22;
   int w      = fs * 27;
   int h      = 8 * lh + 10;

//--- background
   string bg = PREFIX+"BG";
   if(ObjectFind(0,bg) < 0)
     {
      ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,bg,OBJPROP_CORNER,corner);
      ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,x-6);
      ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,y-6);
      ObjectSetInteger(0,bg,OBJPROP_XSIZE,w+12);
      ObjectSetInteger(0,bg,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'18,18,22');
      ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,bg,OBJPROP_COLOR,C'60,60,70');
      ObjectSetInteger(0,bg,OBJPROP_BACK,true);
      ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,bg,OBJPROP_SELECTED,false);
     }

   double pip     = (_Digits==3 || _Digits==5) ? _Point*10.0 : _Point;
   double atrPip  = g_dATR / pip;
   double stopPip = atrPip * InpATRStopMult;
   double targPip = stopPip * InpRiskReward;

//--- rows
   SetRow(PREFIX+"r0",0," JobPick  "+Symbol()+"  "+TFToString(),
          C'235,235,245',corner,x,y,fs,lh);

   SetRow(PREFIX+"r1",1," "+RepStr("-",26),C'70,70,85',corner,x,y,fs,lh);

   string biasSrc = (InpBiasMode==BIAS_VWAP) ? "VWAP"
                  : ((InpBiasMode==BIAS_EMA) ? ("EMA"+IntegerToString(InpEMABiasPeriod)) : "VWAP+EMA");
   SetRow(PREFIX+"r2",2," BIAS      "+Pad((g_bBiasBull ? "BULL" : "BEAR"),5)
          +"  "+DoubleToString(g_dFair,_Digits)+"  "+biasSrc,
          g_bBiasBull ? C'0,230,120' : C'255,90,90',corner,x,y,fs,lh);

   SetRow(PREFIX+"r3",3," TREND     "+Pad((g_bTrendBull ? "UP" : "DOWN"),5)
          +"  "+IntegerToString(InpEMAFast)+"/"+IntegerToString(InpEMASlow)+" EMA",
          g_bTrendBull ? C'0,230,120' : C'255,90,90',corner,x,y,fs,lh);

   string momTxt;
   if(InpMomentumMode == MOM_RSI)
      momTxt = " MOMENTUM  RSI "+Pad(DoubleToString(g_dRSI,1),5)
               +"  "+((g_bMomBull) ? "^ rising" : "v falling");
   else
      momTxt = " MOMENTUM  MACD hist "+((g_dHist>=0.0) ? "+" : "")+DoubleToString(g_dHist,_Digits+1)
               +"  "+((g_bMomBull) ? "^ rising" : "v falling");
   SetRow(PREFIX+"r4",4,momTxt,g_bMomBull ? C'0,230,120' : C'255,90,90',corner,x,y,fs,lh);

   SetRow(PREFIX+"r5",5," VOLUME    RVOL "+Pad(DoubleToString(g_dRVOL,2),5)+"  "
          +((g_dRVOL<=0.0) ? "n/a" : (g_bVolOK ? "STRONG" : "weak")),
          (g_dRVOL<=0.0) ? C'150,150,160' : (g_bVolOK ? C'0,230,120' : C'230,180,60'),
          corner,x,y,fs,lh);

   SetRow(PREFIX+"r6",6," RISK      ATR "+Pad(DoubleToString(atrPip,1)+"pip",9)
          +"  SL "+DoubleToString(stopPip,1)+"  TP "+DoubleToString(targPip,1),
          C'120,190,255',corner,x,y,fs,lh);

   int score = (g_dirNow==1) ? g_bullScore : ((g_dirNow==-1) ? g_bearScore : (int)MathMax(g_bullScore,g_bearScore));
   string dots = "";
   for(int k=0; k<4; k++)
      dots += (k < score) ? "*" : ".";
   string sigState = (g_dirNow==1) ? "BUY " : ((g_dirNow==-1) ? "SELL" : "WAIT");
   SetRow(PREFIX+"r7",7," SIGNAL    "+sigState+"  "+dots+"  "+IntegerToString(score)+"/4",
          (g_dirNow==1) ? C'0,230,120' : ((g_dirNow==-1) ? C'255,90,90' : C'160,160,175'),
          corner,x,y,fs,lh);
  }

//+------------------------------------------------------------------+
//| Dashboard row helper                                              |
//+------------------------------------------------------------------+
void SetRow(string name,int row,string text,color clr,int corner,int x,int y,int fs,int lh)
  {
   if(ObjectFind(0,name) < 0)
     {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,corner);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y + row*lh);
      ObjectSetString(0,name,OBJPROP_FONT,"Courier New");
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
      ObjectSetString(0,name,OBJPROP_TEXT,text);
     }
   if(ObjectGetString(0,name,OBJPROP_TEXT) != text)
      ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
  }

void DeletePanel()
  {
   ObjectsDeleteAll(0,PREFIX,0,OBJ_LABEL);
   ObjectsDeleteAll(0,PREFIX,0,OBJ_RECTANGLE_LABEL);
  }

//+------------------------------------------------------------------+
//| Last signal stop / target lines                                   |
//+------------------------------------------------------------------+
void DrawLevels()
  {
   if(g_sigType == 0 || g_sigTime == 0)
      return;
   DrawHLine(PREFIX+"SL",g_sigStop,  C'255,90,90',  STYLE_DASHDOT,1);
   DrawHLine(PREFIX+"TP",g_sigTarget,C'0,230,120',  STYLE_DASHDOT,1);
   DrawHLine(PREFIX+"EN",g_sigPrice, C'150,150,170',STYLE_DOT,    1);
  }

void DrawHLine(string name,double price,color clr,int style,int width)
  {
   if(ObjectFind(0,name) < 0)
     {
      ObjectCreate(0,name,OBJ_HLINE,0,0,price);
      ObjectSetInteger(0,name,OBJPROP_STYLE,style);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
     }
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
  }

void DeleteLevels()
  {
   ObjectsDeleteAll(0,PREFIX,0,OBJ_HLINE);
  }

//+------------------------------------------------------------------+
//| String helpers                                                    |
//+------------------------------------------------------------------+
string Pad(string s,int width)
  {
   for(int i=StringLen(s); i<width; i++)
      s += " ";
   return(s);
  }

string RepStr(string ch,int count)
  {
   string s = "";
   for(int i=0; i<count; i++)
      s += ch;
   return(s);
  }
//+------------------------------------------------------------------+
