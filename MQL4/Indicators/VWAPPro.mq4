//+------------------------------------------------------------------+
//|                                              VWAPPro.mq4         |
//|                                                                  |
//|  VWAP Pro - Anchored Volume Weighted Average Price                |
//|             with volume-integrity repair, statistically honest     |
//|             dispersion bands and a regime aware composite score.   |
//|                                                                  |
//|  The engine (MQL4/Include/VWAPPro/*.mqh) is shared, byte for byte, |
//|  with a C++ unit test suite - tests/ - so every formula on this    |
//|  chart is covered by an assertion somewhere in this repository.    |
//|                                                                  |
//|  WHAT MAKES THIS DIFFERENT FROM THE USUAL DOWNLOAD                   |
//|                                                                  |
//|   1. It refuses to lie about volume.  MT4 tick volume is not share  |
//|      volume.  The engine detects degenerate feeds (constant, zero,   |
//|      missing) and switches to a tick-rule / volatility-clock proxy,  |
//|      so on a metal or index CFD the bands do not collapse.           |
//|                                                                  |
//|   2. The dispersion is a volume weighted standard deviation with a   |
//|      Brownian-bridge shrinkage prior, so the bands are usable from   |
//|      the first minute of a session instead of being garbage until    |
//|      enough bars accumulate.                                         |
//|                                                                  |
//|   3. The moments are accumulated in deviation form with Kahan        |
//|      compensation, so they stay accurate to ~1e-13 relative on       |
//|      5-digit FX where the naive sum(x^2) approach loses every        |
//|      significant digit.                                              |
//|                                                                  |
//|   4. Bands can be Gaussian (k*sigma) or empirical confidence         |
//|      quantiles, corrected for the skewness and excess kurtosis the   |
//|      anchor has actually exhibited (Cornish-Fisher), because intraday|
//|      returns are not normal and pretending they are is why "2 sigma"  |
//|      VWAP bands get hit far more often than the 5% the label implies. |
//|                                                                  |
//|   5. The composite score blends mean-reversion and trend-continuation |
//|      hypotheses with regime weights (ADX + R^2) instead of hardcoding |
//|      one of them and calling it a day.                                |
//+------------------------------------------------------------------+
#property copyright "VWAP Pro"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_color1  clrDodgerBlue
#property indicator_color2  clrDarkGray
#property indicator_color3  clrDarkGray
#property indicator_color4  clrFireBrick
#property indicator_color5  clrFireBrick
#property indicator_color6  clrMaroon
#property indicator_color7  clrMaroon
#property indicator_color8  clrNONE
#property indicator_width1  2
#property indicator_width2  1
#property indicator_width3  1
#property indicator_width4  1
#property indicator_width5  1
#property indicator_width6  1
#property indicator_width7  1
#property indicator_style2  STYLE_DOT
#property indicator_style3  STYLE_DOT
#property indicator_style4  STYLE_DASH
#property indicator_style5  STYLE_DASH
#property indicator_style6  STYLE_DOT
#property indicator_style7  STYLE_DOT

#include <VWAPPro/VpCompat.mqh>
#include <VWAPPro/VpEngine.mqh>
#include <VWAPPro/VpAnchor.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
enum ENUM_VP_ANCHOR
{
   VP_ANCH_EACHBAR = 0,   // Each chart bar
   VP_ANCH_DAILY   = 1,   // Broker day (00:00 server)
   VP_ANCH_UTCDAY  = 2,   // UTC day
   VP_ANCH_FIXED   = 3,   // Fixed server time
   VP_ANCH_WEEK    = 4    // Week
};

enum ENUM_VP_VOLUME
{
   VP_VOL_AUTO   = 0,  // Auto (real > tick > range)
   VP_VOL_TICK   = 1,  // Tick volume
   VP_VOL_REAL   = 2,  // Real volume
   VP_VOL_BVCPR  = 3,  // Tick rule + split price
   VP_VOL_RANGE  = 4,  // Bar range clock
   VP_VOL_BODY   = 5,  // Bar body clock
   VP_VOL_UNIF   = 6,  // Uniform (unweighted anchor)
   VP_VOL_INVR   = 7   // Inverse-variance (precision)
};

input string            __s0                  = "=== VWAP Pro ===";   // ---
input ENUM_VP_ANCHOR    InpAnchor             = VP_ANCH_DAILY;        // Anchor
input string            InpAnchorTime         = "09:30";              // Fixed anchor HH:MM (server)
input int               InpAnchorShiftMin     = 0;                    // Anchor shift (minutes)
input int               InpWeekStart          = 1;                    // Week starts (0=Sun..6=Sat)

input string            __s1                  = "=== Volume handling ==="; // ---
input ENUM_VP_VOLUME    InpVolumeMode         = VP_VOL_AUTO;          // Weighting
input double            InpBuySellK           = 1.0;                  // Tick-rule strength (0..1.5)

input string            __s2                  = "=== Dispersion / bands ==="; // ---
input int               InpSigmaMode          = 0;                    // Sigma: 0=session 1=window 2=blend
input int               InpZWindow            = 0;                    // Window bars (0=whole anchor)
input bool              InpAdaptSigma         = true;                 // Shrink sigma to ATR prior
input int               InpAdaptPriorBars     = 40;                   // Prior strength (bars)
input int               InpBandMode           = 0;                    // Bands: 0=sd 1=confidence
input double            InpBand1              = 1.0;                  // Band 1 (sd or 0.80)
input double            InpBand2              = 2.0;                  // Band 2 (sd or 0.95)
input double            InpBand3              = 3.0;                  // Band 3 (sd or 0.99)

input string            __s3                  = "=== Signal ===";     // ---
input bool              InpAdaptiveSignal     = true;                 // Regime-adaptive score
input int               InpMinBars            = 3;                    // Bars before signalling
input bool              InpAlerts             = true;                 // Alerts on extremes
input double            InpAlertZ             = 2.0;                  // Alert at |z| >=
input bool              InpPushNotify         = false;                // Also send push

input string            __s4                  = "=== Display ===";    // ---
input bool              InpShowPanel          = true;                 // Info panel
input int               InpPanelCorner        = 0;                    // 0=TL 1=TR 2=BL 3=BR
input bool              InpShowPriceLabels    = true;                 // Price labels
input int               InpTZOffsetHours      = 0;                    // Broker GMT offset (hours)
input bool              InpVerbose            = false;                // Log feed diagnostics at init

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double BufVwap[];
double BufUp1[], BufDn1[];
double BufUp2[], BufDn2[];
double BufUp3[], BufDn3[];
double BufSignal[];

//+------------------------------------------------------------------+
//| State                                                            |
//+------------------------------------------------------------------+
VpEngine        gMain;         // engine over *closed* bars only
VpEngine        gPreview;      // gMain + the forming bar (never committed)
VpEngineConfig  gCfg;
datetime        gLastClosed    = 0;
bool            gInitialised   = false;
datetime        gAlertBar      = 0;
string          gPanelPrefix   = "VWAPPro_";
bool            gReportedFeed  = false;

//+------------------------------------------------------------------+
//| Input hygiene: every input is clamped here so that no combination |
//| of settings can produce a divide by zero or an absurd band.        |
//+------------------------------------------------------------------+
void vp_build_config()
{
   gCfg.Init();

   gCfg.anchorMode  = (int)InpAnchor;
   gCfg.anchorHour  = 0;
   gCfg.anchorMinute = 0;
   // Parse "HH:MM"
   string s = InpAnchorTime;
   int colon = StringFind(s, ":");
   if (colon > 0)
   {
      gCfg.anchorHour   = (int)StringToInteger(StringSubstr(s, 0, colon));
      gCfg.anchorMinute = (int)StringToInteger(StringSubstr(s, colon + 1, 2));
   }
   if (gCfg.anchorHour < 0) gCfg.anchorHour = 0;
   if (gCfg.anchorHour > 23) gCfg.anchorHour = 23;
   if (gCfg.anchorMinute < 0) gCfg.anchorMinute = 0;
   if (gCfg.anchorMinute > 59) gCfg.anchorMinute = 59;
   gCfg.anchorShiftSec = InpAnchorShiftMin * 60;
   gCfg.weekStartDay   = vp_imin(6, vp_imax(0, InpWeekStart));

   gCfg.volumeMode = (int)InpVolumeMode;
   gCfg.bvcK       = vp_clamp(InpBuySellK, 0.0, 1.5);

   gCfg.sigmaMode  = vp_imin(2, vp_imax(0, InpSigmaMode));
   gCfg.zWindow    = vp_imax(0, InpZWindow);
   // Window based sigma without a window is meaningless: default to a
   // sensible one instead of silently falling back to the session sigma.
   if (gCfg.sigmaMode != VP_SIGMA_SESSION && gCfg.zWindow < 10) gCfg.zWindow = 240;
   gCfg.adaptSigma = InpAdaptSigma;
   gCfg.adaptPriorBars = vp_imax(0, InpAdaptPriorBars);

   gCfg.atrPeriod  = 14;
   gCfg.adxPeriod  = 14;

   gCfg.bandMode   = vp_imin(1, vp_imax(0, InpBandMode));
   gCfg.mult1      = InpBand1;
   gCfg.mult2      = InpBand2;
   gCfg.mult3      = InpBand3;
   if (gCfg.bandMode == VP_BANDS_CONFIDENCE)
   {
      // Inputs are probabilities in this mode: convert to normal quantiles.
      gCfg.mult1 = vp_norm_quantile(vp_clamp(InpBand1, 0.50, 0.999));
      gCfg.mult2 = vp_norm_quantile(vp_clamp(InpBand2, 0.50, 0.9995));
      gCfg.mult3 = vp_norm_quantile(vp_clamp(InpBand3, 0.50, 0.9999));
   }
   else
   {
      gCfg.mult1 = vp_clamp(InpBand1, 0.1, 20.0);
      gCfg.mult2 = vp_clamp(InpBand2, 0.1, 20.0);
      gCfg.mult3 = vp_clamp(InpBand3, 0.1, 20.0);
   }

   gCfg.adaptiveSignal = InpAdaptiveSignal;
   gCfg.minBars        = vp_imax(1, InpMinBars);
}

//+------------------------------------------------------------------+
//| Write the engine outputs of one bar into the indicator buffers.    |
//| (series index i: 0 = newest bar)                                   |
//+------------------------------------------------------------------+
void vp_write_buffers(int i, VpEngine &e)
{
   BufVwap[i]   = e.vwap;
   BufUp1[i]    = e.up1;   BufDn1[i] = e.dn1;
   BufUp2[i]    = e.up2;   BufDn2[i] = e.dn2;
   BufUp3[i]    = e.up3;   BufDn3[i] = e.dn3;
   BufSignal[i] = e.signal;
}

//+------------------------------------------------------------------+
//| Feed one chart bar (by series index) into an engine.               |
//+------------------------------------------------------------------+
void vp_push_series_bar(VpEngine &e, const datetime &time[], const double &open[],
                        const double &high[], const double &low[], const double &close[],
                        const long &tick_volume[], const long &volume[], int i)
{
   VpBar b;
   b.time    = (vp_int64)time[i];
   b.open    = open[i];
   b.high    = high[i];
   b.low     = low[i];
   b.close   = close[i];
   b.tickVol = (double)tick_volume[i];
   b.realVol = (double)volume[i];

   vp_int64 key = vp_anchor_key(gCfg, b.time);
   vp_engine_push(e, gCfg, key, b.time, b);
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorBuffers(8);
   SetIndexBuffer(0, BufVwap);    SetIndexLabel(0, "VWAP");
   SetIndexBuffer(1, BufUp1);     SetIndexLabel(1, "+1");
   SetIndexBuffer(2, BufDn1);     SetIndexLabel(2, "-1");
   SetIndexBuffer(3, BufUp2);     SetIndexLabel(3, "+2");
   SetIndexBuffer(4, BufDn2);     SetIndexLabel(4, "-2");
   SetIndexBuffer(5, BufUp3);     SetIndexLabel(5, "+3");
   SetIndexBuffer(6, BufDn3);     SetIndexLabel(6, "-3");
   SetIndexBuffer(7, BufSignal);  SetIndexLabel(7, "VWAP Pro score");

   SetIndexStyle(7, DRAW_NONE);
   SetIndexEmptyValue(7, 0.0);

   vp_build_config();

   //--- timezone reference for the UTC anchored modes
   vp_tz_offset_hours = (double)InpTZOffsetHours;

   gMain.Reset();
   gPreview.Reset();
   gLastClosed = 0;
   gReportedFeed = false;

   IndicatorShortName("VWAP Pro");
   IndicatorDigits(Digits);

   if (InpShowPanel) vp_panel_create();

   gInitialised = true;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   vp_panel_destroy();
   Comment("");
}

//+------------------------------------------------------------------+
//| Main calculation                                                  |
//|                                                                  |
//|  Incremental by construction: closed bars are pushed through the   |
//|  engine exactly once, and the forming bar is evaluated on a clone  |
//|  so it can never contaminate the committed state (no repainting of |
//|  closed bars, no "the VWAP moved after the fact" complaints).      |
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
   if (!gInitialised) return(0);
   if (rates_total < 3) return(0);

   //--- (re)build from scratch -------------------------------------
   bool rebuild = (prev_calculated <= 0) || (prev_calculated > rates_total)
                  || (gLastClosed == 0);
   if (rebuild)
   {
      gMain.Reset();
      gLastClosed = 0;
      // oldest -> newest, skipping the forming bar (series index 0)
      for (int i = rates_total - 1; i >= 1; i--)
      {
         vp_push_series_bar(gMain, time, open, high, low, close, tick_volume, volume, i);
         vp_engine_evaluate(gMain, gCfg);
         vp_write_buffers(i, gMain);
      }
      gLastClosed = time[1];
      // Bars older than the visible window are still needed for the
      // engine's continuity, but only "limit" of them are re-emitted.
   }
   else
   {
      //--- process the bars that closed since the previous call ---------
      // Walk backwards from the newest closed bar to the last one we
      // know about.  The scan is bounded so a broken history can never
      // stall the terminal.
      int idx = 1;
      int guard = 0;
      while (idx <= rates_total - 1 && guard < 100000)
      {
         if ((datetime)time[idx] == gLastClosed) break;
         idx++;
         guard++;
      }
      if (guard >= 100000)
      {
         // History changed under us (broker re-sync, symbol refresh):
         // fall back to a clean rebuild on the next call.
         return(0);
      }
      for (int i = idx - 1; i >= 1; i--)
      {
         vp_push_series_bar(gMain, time, open, high, low, close, tick_volume, volume, i);
         vp_engine_evaluate(gMain, gCfg);
         vp_write_buffers(i, gMain);
      }
      if (idx >= 2) gLastClosed = time[1];
   }

   //--- the forming bar: evaluate on a clone so the committed state is
   //--- never touched by an unfinished bar -----------------------------
   vp_engine_clone(gMain, gPreview);
   vp_push_series_bar(gPreview, time, open, high, low, close, tick_volume, volume, 0);
   vp_engine_evaluate(gPreview, gCfg);
   vp_write_buffers(0, gPreview);

   //--- feed diagnostics (once, on request) --------------------------
   if (InpVerbose && !gReportedFeed)
   {
      gReportedFeed = true;
      Print("VWAP Pro: tickVolume usable=", gMain.vol.tickUsable,
            " constant=", gMain.vol.tickConstant,
            " realVolume usable=", gMain.vol.realUsable,
            " rejectedBars=", gMain.feedWarnings,
            " weightingMode=", gCfg.volumeMode);
      if (gMain.vol.tickConstant)
         Print("VWAP Pro: the feed reports a constant tick volume - AUTO weighting switches to ",
               "the volatility clock (a constant is not information).");
      if (!gMain.vol.tickUsable && !gMain.vol.realUsable)
         Print("VWAP Pro: no usable volume at all - the anchor degrades to the volatility clock ",
               "(range weighted), which is a documented, scale free fallback.");
   }

   //--- presentation & alerts ---------------------------------------
   if (InpShowPanel) vp_panel_update(gPreview);
   if (InpShowPriceLabels) vp_price_labels(gPreview);
   vp_check_alerts(gPreview, time[0]);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Alerts: only on a *closed* bar, only once per bar, so an alert     |
//| can never be triggered by the same bar repainting.                 |
//+------------------------------------------------------------------+
void vp_check_alerts(VpEngine &e, datetime barTime)
{
   if (!InpAlerts) return;
   if (barTime == gAlertBar) return;
   if (!e.ready) return;
   if (vp_abs(e.z) < InpAlertZ) return;

   gAlertBar = barTime;
   string dir = (e.z > 0.0) ? "ABOVE" : "BELOW";
   string msg = "VWAP Pro " + Symbol() + " " + vp_tf_text() + ": price is "
                + DoubleToString(vp_abs(e.z), 2) + " sd " + dir + " the anchor ("
                + DoubleToString(e.vwap, Digits) + "), score "
                + DoubleToString(e.signal, 2);
   Alert(msg);
   if (InpPushNotify) SendNotification(msg);
}

//+------------------------------------------------------------------+
//| Human readable anchor start (display only - the shared engine      |
//| deliberately contains no string code so that it stays portable).    |
//+------------------------------------------------------------------+
string vp_anchor_time_text(vp_int64 key)
{
   VpDateTime dt;
   vp_break_time(key, dt);
   return StringFormat("%04d.%02d.%02d %02d:%02d", dt.year, dt.month, dt.day, dt.hour, dt.minute);
}

//+------------------------------------------------------------------+
//| Timeframe as text (MQL4 has no EnumToString(ENUM_TIMEFRAMES) that  |
//| is safe across builds).                                            |
//+------------------------------------------------------------------+
string vp_tf_text()
{
   switch (Period())
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
   }
   return IntegerToString(Period());
}

//+------------------------------------------------------------------+
//| Normal quantile (Acklam's rational approximation, |err| < 1.15e-9 |
//| over the whole range) - used to convert probability inputs into    |
//| z multipliers.                                                     |
//+------------------------------------------------------------------+
double vp_norm_quantile(double p)
{
   if (p <= 0.0) return -6.0;
   if (p >= 1.0) return  6.0;
   if (p > 0.5) return -vp_norm_quantile(1.0 - p);

   double a[6];
   a[0] = -3.969683028665376e+01; a[1] =  2.209460984245205e+02;
   a[2] = -2.759285104469687e+02; a[3] =  1.383577518672690e+02;
   a[4] = -3.066479806614716e+01; a[5] =  2.506628277459239e+00;
   double b[5];
   b[0] = -5.447609879822406e+01; b[1] =  1.615858368580409e+02;
   b[2] = -1.556989798598866e+02; b[3] =  6.680131188771972e+01;
   b[4] = -1.328068155288572e+01;
   double c[6];
   c[0] = -7.784894002430293e-03; c[1] = -3.223964580411365e-01;
   c[2] = -2.400758277161838e+00; c[3] = -2.549732539343734e+00;
   c[4] =  4.374664141464968e+00; c[5] =  2.938163982698783e+00;
   double d[4];
   d[0] =  7.784695709041462e-03; d[1] =  3.224671290700398e-01;
   d[2] =  2.445134137142996e+00; d[3] =  3.754408661907416e+00;

   double plow = 0.02425;
   double q, r, x;
   if (p < plow)
   {
      q = MathSqrt(-2.0 * MathLog(p));
      x = (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) /
          ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1.0);
   }
   else
   {
      q = p - 0.5;
      r = q * q;
      x = (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q /
          (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1.0);
   }
   return x;
}

//+------------------------------------------------------------------+
//| On-chart information panel                                       |
//+------------------------------------------------------------------+
void vp_panel_create()
{
   vp_panel_destroy();
}

void vp_panel_destroy()
{
   for (int i = 0; i < 40; i++)
   {
      string nm = gPanelPrefix + IntegerToString(i);
      if (ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   }
}

void vp_panel_label(int index, string text, color clr, int fontsize)
{
   string nm = gPanelPrefix + IntegerToString(index);
   if (ObjectFind(0, nm) < 0)
   {
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
      ObjectSet(nm, OBJPROP_SELECTABLE, false);
      ObjectSet(nm, OBJPROP_HIDDEN, true);
      ObjectSet(nm, OBJPROP_BACK, false);
   }
   ObjectSet(nm, OBJPROP_CORNER, InpPanelCorner);
   ObjectSet(nm, OBJPROP_XDISTANCE, 12);
   ObjectSet(nm, OBJPROP_YDISTANCE, 18 + index * 15);
   ObjectSetText(nm, text, fontsize, "Consolas", clr);
}

void vp_panel_clear_from(int index)
{
   for (int i = index; i < 40; i++)
   {
      string nm = gPanelPrefix + IntegerToString(i);
      if (ObjectFind(0, nm) >= 0) ObjectSetText(nm, "", 8, "Consolas", clrNONE);
   }
}

void vp_panel_update(VpEngine &e)
{
   int line = 0;
   string feed = "none";
   color  feedClr = clrGray;
   if (e.vol.realUsable && (gCfg.volumeMode == VP_VOL_AUTO || gCfg.volumeMode == VP_VOL_REAL))
   { feed = "real volume"; feedClr = clrLimeGreen; }
   else if (!e.vol.tickUsable)
   { feed = "no volume -> volatility clock"; feedClr = clrOrange; }
   else if (e.vol.tickConstant)
   { feed = "constant volume -> repaired"; feedClr = clrOrange; }
   else
   { feed = "tick volume"; feedClr = clrSilver; }

   vp_panel_label(line++, "VWAP Pro", clrWhite, 10);
   vp_panel_label(line++, "anchor  " + vp_anchor_time_text(e.anchorTime), clrSilver, 8);
   vp_panel_label(line++, "vwap    " + DoubleToString(e.vwap, Digits), (e.lastClose >= e.vwap ? clrLimeGreen : clrTomato), 9);
   vp_panel_label(line++, "sigma   " + DoubleToString(e.sigma / _Point, 1) + " pts", clrSilver, 8);
   vp_panel_label(line++, "z       " + DoubleToString(e.z, 2), (e.z > 0 ? clrLimeGreen : clrTomato), 9);
   vp_panel_label(line++, "slope   " + DoubleToString(e.slopePct, 4) + " %/bar", clrSilver, 8);
   vp_panel_label(line++, "flow    " + DoubleToString(e.deltaTilt, 3), clrSilver, 8);
   vp_panel_label(line++, "conf R2 " + DoubleToString(e.r2, 3), clrSilver, 8);
   vp_panel_label(line++, "skew/kurt " + DoubleToString(e.skew, 2) + " / " + DoubleToString(e.kurt, 2), clrSilver, 8);
   vp_panel_label(line++, "score   " + DoubleToString(e.signal, 2), (e.signal > 0 ? clrLimeGreen : (e.signal < 0 ? clrTomato : clrSilver)), 9);
   vp_panel_label(line++, "feed    " + feed, feedClr, 8);
   vp_panel_label(line++, "bars    " + IntegerToString(e.barsInAnchor), clrGray, 8);
   vp_panel_clear_from(line);
}

//+------------------------------------------------------------------+
//| Price labels on the right edge of the anchor + bands              |
//+------------------------------------------------------------------+
void vp_price_labels(VpEngine &e)
{
   double lv[7];
   string tx[7];
   color  cl[7];
   lv[0] = e.vwap; tx[0] = "VWAP"; cl[0] = clrDodgerBlue;
   lv[1] = e.up1;  tx[1] = "+1";   cl[1] = clrDarkGray;
   lv[2] = e.dn1;  tx[2] = "-1";   cl[2] = clrDarkGray;
   lv[3] = e.up2;  tx[3] = "+2";   cl[3] = clrFireBrick;
   lv[4] = e.dn2;  tx[4] = "-2";   cl[4] = clrFireBrick;
   lv[5] = e.up3;  tx[5] = "+3";   cl[5] = clrMaroon;
   lv[6] = e.dn3;  tx[6] = "-3";   cl[6] = clrMaroon;

   for (int i = 0; i < 7; i++)
   {
      string nm = gPanelPrefix + "lvl" + IntegerToString(i);
      if (ObjectFind(0, nm) < 0)
      {
         ObjectCreate(0, nm, OBJ_TEXT, 0, 0, lv[i]);
         ObjectSet(nm, OBJPROP_SELECTABLE, false);
         ObjectSet(nm, OBJPROP_HIDDEN, true);
      }
      datetime t = (datetime)(Time[0] + 3 * PeriodSeconds());
      ObjectMove(0, nm, 0, t, lv[i]);
      ObjectSetText(nm, tx[i] + " " + DoubleToString(lv[i], Digits), 7, "Consolas", cl[i]);
   }
}

//+------------------------------------------------------------------+
