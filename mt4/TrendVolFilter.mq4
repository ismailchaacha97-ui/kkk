//+------------------------------------------------------------------+
//|                                            TrendVolFilter.mq4     |
//|   Rank #1 of 9,600 backtested strategies                          |
//|   trend_vol_filter(ma=200, volw=120, volmax=0.12, long-only,      |
//|                    sizing = 10% annualised vol target)            |
//|                                                                   |
//|   RULE                                                            |
//|     Be long only when BOTH are true at the close of the bar:      |
//|       1. Close > SMA(200)                     ... trend filter    |
//|       2. AnnVol(120) < 12%                    ... calm filter     |
//|     Position size = 10% / AnnVol(120), capped at 3.0x.            |
//|     The signal is acted on at the NEXT bar's open (1-bar lag),    |
//|     exactly as in the Python backtest -- no repainting.           |
//|                                                                   |
//|   Backtest (40 US ETFs/mega-caps, 2007-2017, net of 5bp):         |
//|     out-of-sample Sharpe 1.12 | full-period Sharpe 0.86           |
//|     CAGR 3.8% | vol 4.5% | max drawdown -8.8%                     |
//|     (SPY buy & hold over the same window: Sharpe 0.44, DD -56.5%) |
//+------------------------------------------------------------------+
#property copyright "Generated from the 9,600-strategy search"
#property link      "https://github.com/ismailchaacha97-ui/kkk"
#property version   "1.00"
#property strict

#property indicator_chart_window
#property indicator_buffers 4

//--- plots
#property indicator_color1 clrDodgerBlue      // SMA(200)
#property indicator_width1 2
#property indicator_color2 clrLimeGreen       // SMA painted while position is ON
#property indicator_width2 3
#property indicator_color3 clrLimeGreen       // entry arrow
#property indicator_width3 2
#property indicator_color4 clrOrangeRed       // exit arrow
#property indicator_width4 2

//--- inputs -------------------------------------------------------
input int    MA_Period        = 200;    // trend MA period (strategy: 200)
input int    Vol_Window       = 120;    // vol lookback for the FILTER (strategy: 120)
input int    Size_Vol_Window   = 60;     // vol lookback for SIZING  (strategy: 60)
input double Vol_Max          = 0.12;   // max annualised vol to allow a position
input double Vol_Target       = 0.10;   // annualised vol target for sizing
input double Leverage_Cap     = 3.0;    // max position scale
input int    Periods_Per_Year = 0;      // 0 = auto from chart timeframe
input double Account_Risk_Pct = 100.0;  // % of equity the 1.0x notional represents
input bool   Show_Panel       = true;   // draw the status panel
input bool   Show_Arrows      = true;   // draw entry/exit arrows
input bool   Alert_On_Signal  = true;   // popup alert on a new signal
input bool   Push_On_Signal   = false;  // push notification on a new signal

//--- buffers ------------------------------------------------------
double BufMA[];
double BufMAOn[];
double BufEntry[];
double BufExit[];
double BufState[];   // 1 = in position, 0 = flat (internal)
double BufScale[];   // position scale (internal)

//--- globals
double   g_annFactor;
datetime g_lastAlertBar = 0;
string   g_prefix = "TVF_";

//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorBuffers(6);          // 4 plotted + 2 internal (state, scale)

   SetIndexBuffer(0, BufMA);
   SetIndexStyle(0, DRAW_LINE, STYLE_DOT);
   SetIndexLabel(0, "SMA(" + IntegerToString(MA_Period) + ")");

   SetIndexBuffer(1, BufMAOn);
   SetIndexStyle(1, DRAW_LINE, STYLE_SOLID);
   SetIndexLabel(1, "In position");

   SetIndexBuffer(2, BufEntry);
   SetIndexStyle(2, DRAW_ARROW);
   SetIndexArrow(2, 233);                 // up arrow
   SetIndexLabel(2, "Entry");

   SetIndexBuffer(3, BufExit);
   SetIndexStyle(3, DRAW_ARROW);
   SetIndexArrow(3, 234);                 // down arrow
   SetIndexLabel(3, "Exit");

   SetIndexBuffer(4, BufState);
   SetIndexBuffer(5, BufScale);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);
   SetIndexEmptyValue(3, EMPTY_VALUE);

   IndicatorShortName("TrendVolFilter #1  MA" + IntegerToString(MA_Period) +
                      " Vol" + IntegerToString(Vol_Window) +
                      " max" + DoubleToString(Vol_Max * 100, 0) + "%");
   IndicatorDigits(Digits);

   g_annFactor = AnnualisationFactor();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_prefix);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Bars per year for the current timeframe, used to annualise vol.  |
//| The strategy was fitted on daily bars (252/yr).                  |
//+------------------------------------------------------------------+
double AnnualisationFactor()
  {
   if(Periods_Per_Year > 0)
      return((double)Periods_Per_Year);

   switch(Period())
     {
      case PERIOD_M1:  return(252.0 * 1440.0);
      case PERIOD_M5:  return(252.0 * 288.0);
      case PERIOD_M15: return(252.0 * 96.0);
      case PERIOD_M30: return(252.0 * 48.0);
      case PERIOD_H1:  return(252.0 * 24.0);
      case PERIOD_H4:  return(252.0 * 6.0);
      case PERIOD_D1:  return(252.0);
      case PERIOD_W1:  return(52.0);
      case PERIOD_MN1: return(12.0);
     }
   return(252.0);
  }

//+------------------------------------------------------------------+
//| Annualised realised volatility of simple returns over the last   |
//| Vol_Window bars ending at bar `shift` (sample stdev, ddof = 1).  |
//+------------------------------------------------------------------+
double AnnualisedVol(const int shift, const int window)
  {
   if(window < 2 || shift + window + 1 >= Bars)
      return(-1.0);

   double sum = 0.0, sumsq = 0.0;
   int    n   = 0;

   for(int i = shift; i < shift + window; i++)
     {
      double prev = Close[i + 1];
      if(prev <= 0.0)
         continue;
      double r = Close[i] / prev - 1.0;
      sum   += r;
      sumsq += r * r;
      n++;
     }

   if(n < 2)
      return(-1.0);

   double mean = sum / n;
   double var  = (sumsq - n * mean * mean) / (n - 1);
   if(var <= 0.0)
      return(0.0);

   return(MathSqrt(var) * MathSqrt(g_annFactor));
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
   int minBars = MathMax(MA_Period, MathMax(Vol_Window, Size_Vol_Window)) + 3;
   if(rates_total < minBars)
      return(0);

   // recompute the tail; +2 so the state chain stays correct
   int limit = rates_total - prev_calculated + 2;
   if(prev_calculated == 0)
      limit = rates_total - minBars;
   if(limit > rates_total - minBars)
      limit = rates_total - minBars;

   for(int i = limit; i >= 0; i--)
     {
      BufMA[i]    = EMPTY_VALUE;
      BufMAOn[i]  = EMPTY_VALUE;
      BufEntry[i] = EMPTY_VALUE;
      BufExit[i]  = EMPTY_VALUE;
      BufState[i] = 0.0;
      BufScale[i] = 0.0;

      double ma = iMA(NULL, 0, MA_Period, 0, MODE_SMA, PRICE_CLOSE, i);
      if(ma <= 0.0)
         continue;
      BufMA[i] = ma;

      // ---- signal is formed on the PREVIOUS closed bar (1-bar lag) ----
      int s = i + 1;

      double ma_s = iMA(NULL, 0, MA_Period, 0, MODE_SMA, PRICE_CLOSE, s);
      double vol_s = AnnualisedVol(s, Vol_Window);
      if(ma_s <= 0.0 || vol_s < 0.0)
         continue;

      bool trendOK = (Close[s] > ma_s);          // rule 1: above the 200 SMA
      bool calmOK  = (vol_s < Vol_Max);          // rule 2: vol below the ceiling
      bool inPos   = (trendOK && calmOK);

      // Sizing uses a SEPARATE 60-bar vol window, measured on the bar before
      // the signal bar -- exactly what the Python overlay does
      // (cache.vol(60).shift(1)). The 120-bar window is the filter only.
      double vol_z = AnnualisedVol(s + 1, Size_Vol_Window);
      double scale = 0.0;
      if(inPos && vol_z > 0.0)
        {
         scale = Vol_Target / vol_z;             // 10% vol target
         if(scale > Leverage_Cap)
            scale = Leverage_Cap;                // cap at 3.0x
        }

      BufState[i] = inPos ? 1.0 : 0.0;
      BufScale[i] = scale;

      if(inPos)
         BufMAOn[i] = ma;

      // ---- transition arrows ----
      double prevState = (i + 1 <= rates_total - 1) ? BufState[i + 1] : 0.0;
      if(Show_Arrows)
        {
         if(inPos && prevState == 0.0)
            BufEntry[i] = Low[i] - 1.2 * iATR(NULL, 0, 14, i);
         if(!inPos && prevState == 1.0)
            BufExit[i] = High[i] + 1.2 * iATR(NULL, 0, 14, i);
        }
     }

   UpdatePanel();
   CheckAlert();
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Status panel                                                     |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!Show_Panel)
      return;

   int s = 1;                                   // last closed bar
   double ma  = iMA(NULL, 0, MA_Period, 0, MODE_SMA, PRICE_CLOSE, s);
   double vol = AnnualisedVol(s, Vol_Window);
   if(ma <= 0.0 || vol < 0.0)
      return;

   bool trendOK = (Close[s] > ma);
   bool calmOK  = (vol < Vol_Max);
   bool inPos   = (trendOK && calmOK);
   double volz  = AnnualisedVol(s + 1, Size_Vol_Window);
   double scale = 0.0;
   if(inPos && volz > 0.0)
      scale = MathMin(Vol_Target / volz, Leverage_Cap);

   double distPct = (Close[s] / ma - 1.0) * 100.0;

   string txt = "";
   txt += "TREND-VOL FILTER  (rank #1 / 9,600)\n";
   txt += "-------------------------------------------\n";
   txt += StringFormat("Trend   Close vs SMA%d : %s  (%+.2f%%)\n",
                       MA_Period, (trendOK ? "ABOVE  OK" : "BELOW  no"), distPct);
   txt += StringFormat("Vol     Ann%d          : %.2f%%  (max %.2f%%)  %s\n",
                       Vol_Window, vol * 100.0, Vol_Max * 100.0,
                       (calmOK ? "OK" : "no"));
   txt += "-------------------------------------------\n";
   txt += StringFormat("SIGNAL                 : %s\n", (inPos ? "LONG" : "FLAT"));
   txt += StringFormat("Sizing vol Ann%d       : %.2f%%\n",
                       Size_Vol_Window, (volz > 0 ? volz * 100.0 : 0.0));
   txt += StringFormat("Position scale         : %.2fx  (target %.0f%% vol)\n",
                       scale, Vol_Target * 100.0);

   if(inPos)
     {
      double risk = AccountEquity() * (Account_Risk_Pct / 100.0) * scale;
      txt += StringFormat("Notional @ %.0f%% equity  : %.2f %s\n",
                          Account_Risk_Pct, risk, AccountCurrency());
     }

   txt += "-------------------------------------------\n";
   txt += "Signal from the last CLOSED bar (1-bar lag).";

   Comment(txt);

   // coloured state box
   string obj = g_prefix + "state";
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, 12);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, 18);
      ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
     }
   ObjectSetString(0, obj, OBJPROP_TEXT,
                   inPos ? StringFormat("LONG  %.2fx", scale) : "FLAT");
   ObjectSetInteger(0, obj, OBJPROP_COLOR, inPos ? clrLimeGreen : clrGray);
   ObjectSetString(0, obj, OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 14);
  }

//+------------------------------------------------------------------+
//| Alert once per bar on a state change                             |
//+------------------------------------------------------------------+
void CheckAlert()
  {
   if(!Alert_On_Signal && !Push_On_Signal)
      return;
   if(Bars < 3)
      return;
   if(g_lastAlertBar == Time[0])
      return;

   bool entry = (BufEntry[1] != EMPTY_VALUE && BufEntry[1] != 0.0);
   bool exitS = (BufExit[1]  != EMPTY_VALUE && BufExit[1]  != 0.0);
   if(!entry && !exitS)
      return;

   string msg = StringFormat("%s %s  TrendVolFilter: %s  (scale %.2fx)",
                             Symbol(), PeriodToStr(Period()),
                             (entry ? "GO LONG" : "GO FLAT"),
                             BufScale[1]);

   if(Alert_On_Signal)
      Alert(msg);
   if(Push_On_Signal)
      SendNotification(msg);

   g_lastAlertBar = Time[0];
  }

//+------------------------------------------------------------------+
string PeriodToStr(const int p)
  {
   switch(p)
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
   return("TF" + IntegerToString(p));
  }
//+------------------------------------------------------------------+
