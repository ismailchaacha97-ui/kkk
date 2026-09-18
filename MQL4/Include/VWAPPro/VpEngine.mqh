//+------------------------------------------------------------------+
//|                                                     VpEngine.mqh |
//|          VWAP Pro - anchored VWAP engine + signal statistics      |
//|                                                                  |
//|  Design goals, in priority order:                                 |
//|                                                                  |
//|   1. *Be a correct VWAP first.*  A VWAP that is not the true       |
//|      volume weighted average price is not a VWAP.  This engine     |
//|      reproduces the textbook estimator exactly when fed clean       |
//|      volume, and degrades deliberately - never silently - when the  |
//|      feed cannot support it.                                        |
//|                                                                  |
//|   2. *Statistically honest bands.*  Dispersion is the volume        |
//|      weighted standard deviation of price about the anchor,         |
//|      accumulated with an origin-shifted, Kahan-compensated scheme   |
//|      so it keeps ~1e-13 relative accuracy even on 5-digit FX where  |
//|      naive accumulation destroys every significant digit.  It is    |
//|      scale invariant: quote in USD or in points, the bands land in  |
//|      the same place (there is a test for that).                     |
//|                                                                  |
//|   3. *Usable from the first bar.*  Early in a session the observed  |
//|      dispersion is meaningless, so the engine shrinks it towards a  |
//|      Brownian-bridge prior built from ATR.  For a driftless path    |
//|      the typical deviation of price from its own time-average is    |
//|      sigma_bar * sqrt(T/3); using that as a shrinkage prior is what |
//|      kills the classic "1 sigma is 40 points wide at 00:05 and 4    |
//|      points wide at 00:06" pathology of every public VWAP band.     |
//|                                                                  |
//|   4. *Signals that know their own significance.*  Every number the  |
//|      indicator emits (z, slope, flow tilt, confidence) is in units  |
//|      that do not depend on symbol, timeframe or quote currency, so  |
//|      the composite score means the same thing on EURUSD M1 and on   |
//|      NAS100 H4.                                                     |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_ENGINE_MQH
#define VWAPPRO_ENGINE_MQH

#include "VpCompat.mqh"
#include "VpMath.mqh"
#include "VpTime.mqh"
#include "VpVolume.mqh"

//--- anchoring -----------------------------------------------------
#define VP_ANCHOR_SESSION   0   // whatever the chart timeframe rolls into
#define VP_ANCHOR_SERVERDAY 1   // broker midnight
#define VP_ANCHOR_UTCDAY    2   // UTC midnight (DST proof)
#define VP_ANCHOR_FIXED     3   // a fixed server-time hour:minute
#define VP_ANCHOR_WEEK      4   // start of week

//--- sigma modes ---------------------------------------------------
#define VP_SIGMA_SESSION 0      // volume weighted sd since the anchor
#define VP_SIGMA_WINDOW  1      // rolling volume weighted sd (zWindow bars)
#define VP_SIGMA_BLEND   2      // blend of session and window sd

//--- band modes ----------------------------------------------------
#define VP_BANDS_SD         0   // classic k * sigma
#define VP_BANDS_CONFIDENCE 1   // Cornish-Fisher adjusted probability bands

// The rolling window is a refinement; 4096 bars is far more than any
// sane z-score window and keeps the per-bar cost bounded on M1.
#define VP_MAX_RING 4096

//+------------------------------------------------------------------+
//| Kahan / Neumaier compensated accumulator.                        |
//|                                                                  |
//|  Without it, sum(w*P^2) on EURUSD loses ~10 significant digits:    |
//|  P^2 ~ 1.2 while the running total reaches 1e9, so the interesting  |
//|  part of the sum ends up below the rounding error of the           |
//|  accumulator.  Compensated summation keeps full precision and is    |
//|  O(1) per update.                                                   |
//+------------------------------------------------------------------+
struct VpKSum
{
   double sum;
   double comp;

   void Reset() { sum = 0.0; comp = 0.0; }

   void Add(double x)
   {
      double t = sum + x;
      if (vp_abs(sum) >= vp_abs(x))
         comp = comp + (sum - t) + x;
      else
         comp = comp + (x - t) + sum;
      sum = t;
   }

   void Sub(double x) { Add(-x); }

   double Val() { return sum + comp; }
};

//+------------------------------------------------------------------+
//| One bar handed to the engine.                                    |
//+------------------------------------------------------------------+
struct VpBar
{
   vp_int64 time;
   double   open;
   double   high;
   double   low;
   double   close;
   double   tickVol;
   double   realVol;
};

//+------------------------------------------------------------------+
//| Engine configuration.  Mirrors the user inputs 1:1.              |
//+------------------------------------------------------------------+
struct VpEngineConfig
{
   int    anchorMode;
   int    anchorHour;
   int    anchorMinute;
   int    anchorShiftSec;
   int    weekStartDay;

   int    volumeMode;
   double bvcK;

   int    sigmaMode;
   int    zWindow;
   bool   adaptSigma;
   int    adaptPriorBars;

   int    atrPeriod;
   int    adxPeriod;

   int    bandMode;
   double mult1;
   double mult2;
   double mult3;

   bool   adaptiveSignal;
   int    minBars;

   void Init()
   {
      // Daily (broker midnight) is the anchor a discretionary trader
      // means by "the VWAP" nine times out of ten.
      anchorMode = VP_ANCHOR_SERVERDAY;
      anchorHour = 0; anchorMinute = 0; anchorShiftSec = 0;
      weekStartDay = 1;                       // Monday

      volumeMode = VP_VOL_AUTO;
      bvcK = 1.0;

      sigmaMode = VP_SIGMA_SESSION;
      zWindow = 0;
      adaptSigma = true;
      adaptPriorBars = 40;

      atrPeriod = 14;
      adxPeriod = 14;

      bandMode = VP_BANDS_SD;
      mult1 = 1.0; mult2 = 2.0; mult3 = 3.0;

      adaptiveSignal = true;
      minBars = 3;
   }
};

//+------------------------------------------------------------------+
//| The engine state.                                                |
//+------------------------------------------------------------------+
struct VpEngine
{
   VpEngineConfig cfg;

   //--- volume feed diagnostics
   VpVolumeProbe vol;

   //--- anchoring
   bool      started;
   vp_int64  anchorKey;        // identifies the current anchor period
   vp_int64  anchorTime;       // time of the first bar of that period
   int       barIndex;         // 0-based index of the bar inside the period
   int       barsInAnchor;     // bars actually accumulated

   //--- weighted price moments, written as deviations from "origin"
   double    origin;
   VpKSum    sw;               // sum w
   VpKSum    swd;              // sum w * (p - origin)
   VpKSum    swd2;             // sum w * (p - origin)^2
   VpKSum    swd3;             // sum w * (p - origin)^3   (skewness)
   VpKSum    swd4;             // sum w * (p - origin)^4   (kurtosis)
   VpKSum    swBuy;            // sum w * buyFraction
   VpKSum    swSell;           // sum w * (1 - buyFraction)

   //--- OLS of price on bar index (the anchor's own slope)
   VpKSum    sx, sy, sxx, sxy;
   //--- unweighted price sums about the same origin (for R^2)
   VpKSum    su1, su2;

   //--- volatility context
   VpATR     atr;
   VpADX     adx;
   VpMoments retMom;           // per-bar log return moments
   double    prevClose;
   bool      havePrevClose;
   double    rangeEwma;        // scale reference for inverse-variance weights

   //--- last bar's raw material
   double    lastOpen, lastHigh, lastLow, lastClose;
   double    lastTickVol, lastRealVol;
   double    lastWeight;
   double    lastBuyFrac;
   double    lastEffPrice;

   //--- rolling window ring buffer (only used when cfg.zWindow > 0)
   VP_DYN(ringPrice, double);
   VP_DYN(ringWeight, double);
   int       ringCap;
   int       ringCount;
   int       ringHead;

   //--- last completed bar's outputs
   double    vwap;
   double    sigma;
   double    sigmaObs;
   double    sigmaPrior;
   double    z;
   double    slopePct;         // regression slope, % of price per bar
   double    slopeSigma;       // regression slope, sigmas per bar
   double    deltaTilt;        // (buy - sell) / (buy + sell), [-1, 1]
   double    r2;               // regression confidence
   double    skew, kurt;
   double    signal;           // composite score, [-1, 1]
   double    up1, dn1, up2, dn2, up3, dn3;
   double    sigmaRatio;       // sigma / prior
   double    tStat;            // t statistic of the anchor's own slope
   bool      ready;

   //--- diagnostics
   int       feedWarnings;

   //------------------------------------------------------------------
   //| Initialise the engine with a configuration and clear the state.
   //| Always prefer this over Reset() - an engine whose cfg was never
   //| assigned would otherwise size its ring buffer from garbage.
   void Init(VpEngineConfig &c)
   {
      cfg = c;
      Reset();
   }

   //| Clear the state.  Every config read below is range checked, so a
   //| Reset() on a default constructed engine is still safe in both
   //| languages (C++ leaves the members uninitialised, MQL4 zeroes them).
   void Reset()
   {
      int ap = (cfg.atrPeriod >= 1 && cfg.atrPeriod <= 1000) ? cfg.atrPeriod : 14;
      int xp = (cfg.adxPeriod >= 2 && cfg.adxPeriod <= 1000) ? cfg.adxPeriod : 14;
      int zw = (cfg.zWindow >= 0 && cfg.zWindow <= VP_MAX_RING) ? cfg.zWindow : 0;
      vol.Reset();
      started = false;
      anchorKey = 0; anchorTime = 0;
      barIndex = -1; barsInAnchor = 0;
      origin = 0.0;
      sw.Reset(); swd.Reset(); swd2.Reset(); swd3.Reset(); swd4.Reset();
      swBuy.Reset(); swSell.Reset();
      sx.Reset(); sy.Reset(); sxx.Reset(); sxy.Reset();
      su1.Reset(); su2.Reset();
      atr.Reset(ap);
      adx.Reset(xp);
      retMom.Reset();
      prevClose = 0.0; havePrevClose = false;
      rangeEwma = 0.0;
      lastOpen = 0.0; lastHigh = 0.0; lastLow = 0.0; lastClose = 0.0;
      lastTickVol = 0.0; lastRealVol = 0.0;
      lastWeight = 0.0; lastBuyFrac = 0.5; lastEffPrice = 0.0;
      ringCap = zw;
      ringCount = 0; ringHead = 0;
      if (ringCap > 0)
      {
         VP_RESIZE(ringPrice, ringCap);
         VP_RESIZE(ringWeight, ringCap);
      }
      vwap = 0.0; sigma = 0.0; sigmaObs = 0.0; sigmaPrior = 0.0;
      z = 0.0; slopePct = 0.0; slopeSigma = 0.0;
      deltaTilt = 0.0; r2 = 0.0; signal = 0.0; skew = 0.0; kurt = 0.0;
      up1 = 0.0; dn1 = 0.0; up2 = 0.0; dn2 = 0.0; up3 = 0.0; dn3 = 0.0;
      sigmaRatio = 1.0;
      tStat = 0.0;
      ready = false;
   }
};

//+------------------------------------------------------------------+
//| Weighted mean / variance accessors on the shifted accumulators.   |
//+------------------------------------------------------------------+
double vp_engine_vwap(VpEngine &e)
{
   double W = e.sw.Val();
   if (!(W > 0.0)) return 0.0;
   return e.origin + e.swd.Val() / W;
}

double vp_engine_variance(VpEngine &e)
{
   double W = e.sw.Val();
   if (!(W > 0.0) || e.barsInAnchor < 2) return 0.0;
   double mean = e.swd.Val() / W;
   double v = e.swd2.Val() / W - mean * mean;
   // A negative value here would mean the accumulator itself is broken.
   // Because we accumulate deviations from a nearby origin with Kahan
   // compensation it can only ever be a floating point epsilon, never a
   // genuine large negative (see the cancellation test).
   if (v < 0.0) v = 0.0;
   return v;
}

//| Unweighted price variance about the same origin (for R^2).
double vp_engine_var_unweighted(VpEngine &e)
{
   if (e.barsInAnchor < 2) return 0.0;
   double n  = (double)e.barsInAnchor;
   double U1 = e.su1.Val();
   double v  = e.su2.Val() - U1 * U1 / n;
   if (v < 0.0) v = 0.0;
   return v / n;
}

//| Third and fourth standardised moments (skew, excess kurtosis).
void vp_engine_shape(VpEngine &e, double &skewOut, double &kurtOut)
{
   skewOut = 0.0; kurtOut = 0.0;
   double W = e.sw.Val();
   if (!(W > 0.0) || e.barsInAnchor < 6) return;
   double S1 = e.swd.Val() / W;
   double S2 = e.swd2.Val() / W;
   double S3 = e.swd3.Val() / W;
   double S4 = e.swd4.Val() / W;
   double m2 = S2 - S1 * S1;
   if (!(m2 > 0.0)) return;
   double m3 = S3 - 3.0 * S1 * S2 + 2.0 * S1 * S1 * S1;
   double m4 = S4 - 4.0 * S1 * S3 + 6.0 * S1 * S1 * S2 - 3.0 * S1 * S1 * S1 * S1;
   double s = vp_sqrt(m2);
   skewOut = vp_div_safe(m3, s * s * s, 0.0);
   kurtOut = vp_div_safe(m4, m2 * m2, 0.0) - 3.0;
   if (!vp_isfinite(skewOut)) skewOut = 0.0;
   if (!vp_isfinite(kurtOut)) kurtOut = 0.0;
}

//+------------------------------------------------------------------+
//| Re-centre the shifted accumulators.                              |
//|                                                                  |
//|  Keeping the origin next to the running VWAP is what turns a sum  |
//|  of huge numbers into a sum of small ones.  The transformation     |
//|  below is algebraically exact, so re-centring changes nothing      |
//|  except the conditioning (the "translation invariance" test in     |
//|  tests/test_engine.cpp pins this down).                            |
//+------------------------------------------------------------------+
void vp_engine_reorigin(VpEngine &e, double newOrigin)
{
   double dl = newOrigin - e.origin;
   if (dl == 0.0) return;

   double W  = e.sw.Val();
   double S1 = e.swd.Val();
   double S2 = e.swd2.Val();
   double S3 = e.swd3.Val();
   double S4 = e.swd4.Val();

   double nS1 = S1 - dl * W;
   double nS2 = S2 - 2.0 * dl * S1 + dl * dl * W;
   double nS3 = S3 - 3.0 * dl * S2 + 3.0 * dl * dl * S1 - dl * dl * dl * W;
   double nS4 = S4 - 4.0 * dl * S3 + 6.0 * dl * dl * S2 - 4.0 * dl * dl * dl * S1
                + dl * dl * dl * dl * W;

   e.swd.Reset();  e.swd.Add(nS1);
   e.swd2.Reset(); e.swd2.Add(nS2);
   e.swd3.Reset(); e.swd3.Add(nS3);
   e.swd4.Reset(); e.swd4.Add(nS4);

   double U1 = e.su1.Val();
   double U2 = e.su2.Val();
   double n  = (double)e.barsInAnchor;
   e.su1.Reset(); e.su1.Add(U1 - dl * n);
   e.su2.Reset(); e.su2.Add(U2 - 2.0 * dl * U1 + dl * dl * n);

   e.origin = newOrigin;
}

//+------------------------------------------------------------------+
//| Start a new anchor period.                                       |
//+------------------------------------------------------------------+
void vp_engine_begin_anchor(VpEngine &e, vp_int64 key, vp_int64 time, double openPrice)
{
   e.anchorKey  = key;
   e.anchorTime = time;
   e.barIndex   = -1;
   e.barsInAnchor = 0;
   e.origin     = openPrice;      // origin next to price => best conditioning
   e.sw.Reset(); e.swd.Reset(); e.swd2.Reset(); e.swd3.Reset(); e.swd4.Reset();
   e.swBuy.Reset(); e.swSell.Reset();
   e.sx.Reset(); e.sy.Reset(); e.sxx.Reset(); e.sxy.Reset();
   e.su1.Reset(); e.su2.Reset();
   e.ringCount = 0; e.ringHead = 0;
   e.started = true;
   e.ready = false;
   e.vwap = openPrice; e.sigma = 0.0; e.z = 0.0;
   e.slopePct = 0.0; e.slopeSigma = 0.0; e.deltaTilt = 0.0; e.r2 = 0.0;
   e.skew = 0.0; e.kurt = 0.0; e.signal = 0.0;
   e.up1 = openPrice; e.dn1 = openPrice;
   e.up2 = openPrice; e.dn2 = openPrice;
   e.up3 = openPrice; e.dn3 = openPrice;
}

//+------------------------------------------------------------------+
//| Ring buffer (rolling window variance support).                   |
//+------------------------------------------------------------------+
void vp_ring_push(VpEngine &e, double price, double weight)
{
   if (e.ringCap <= 0) return;
   if (e.ringCount < e.ringCap)
   {
      e.ringPrice[e.ringCount]  = price;
      e.ringWeight[e.ringCount] = weight;
      e.ringCount++;
   }
   else
   {
      e.ringPrice[e.ringHead]  = price;
      e.ringWeight[e.ringHead] = weight;
      e.ringHead = (e.ringHead + 1) % e.ringCap;
   }
}

//| Volume weighted variance of the rolling window.  Two passes with a
//| deducted mean: still O(window) but numerically clean.
void vp_ring_variance(VpEngine &e, double &varOut, double &meanOut, int &nOut)
{
   varOut = 0.0; meanOut = 0.0; nOut = 0;
   if (e.ringCount < 2) return;
   double W = 0.0, S = 0.0;
   for (int i = 0; i < e.ringCount; i++)
   {
      W += e.ringWeight[i];
      S += e.ringWeight[i] * e.ringPrice[i];
   }
   if (!(W > 0.0)) return;
   double mean = S / W;
   double V = 0.0;
   for (int i = 0; i < e.ringCount; i++)
   {
      double d = e.ringPrice[i] - mean;
      V += e.ringWeight[i] * d * d;
   }
   varOut  = vp_div_safe(V, W, 0.0);
   meanOut = mean;
   nOut    = e.ringCount;
}

//+------------------------------------------------------------------+
//| Cornish-Fisher expansion: map a normal quantile to the quantile    |
//| of a distribution with the observed skewness and excess kurtosis.  |
//|                                                                  |
//|  x_q ~ z + (z^2-1)*g1/6 + (z^3-3z)*g2/24 - (2z^3-5z)*g1^2/36      |
//|                                                                  |
//|  This is what makes VWAP Pro's confidence bands *empirical* rather |
//|  than assuming a Gaussian that intraday returns are known not to    |
//|  be.  The correction is clamped so a fat-tail reading can never     |
//|  collapse or explode a band.                                        |
//+------------------------------------------------------------------+
double vp_cornish_fisher(double zNorm, double skew, double exKurt)
{
   double z  = zNorm;
   double z2 = z * z;
   double z3 = z2 * z;
   double g1 = vp_clamp(skew, -3.0, 3.0);
   double g2 = vp_clamp(exKurt, -2.0, 25.0);
   double x = z
            + (z2 - 1.0) * g1 / 6.0
            + (z3 - 3.0 * z) * g2 / 24.0
            - (2.0 * z3 - 5.0 * z) * g1 * g1 / 36.0;
   // Keep the corrected quantile within half to twice the Gaussian one:
   // the expansion is only valid near the centre and a fat-tail reading
   // must never be allowed to collapse a band.
   double a = z * 0.5, b = z * 2.0;
   double lo = vp_min(a, b);
   double hi = vp_max(a, b);
   if (x < lo) x = lo;
   if (x > hi) x = hi;
   return x;
}

//+------------------------------------------------------------------+
//| Clone an engine.                                                 |
//|                                                                  |
//|  MQL4 cannot copy a struct that owns a dynamic array, so the ring  |
//|  buffer is copied element by element.  The indicator evaluates the  |
//|  forming bar on a clone of the committed engine, which is what      |
//|  guarantees that an unfinished bar can never leak into the state    |
//|  that closed bars were computed from ("no repaint").  It is unit    |
//|  tested against a from-scratch run on the same data.                |
//+------------------------------------------------------------------+
void vp_engine_clone(VpEngine &src, VpEngine &dst)
{
   dst.cfg = src.cfg;
   dst.vol = src.vol;

   dst.started = src.started;
   dst.anchorKey = src.anchorKey;
   dst.anchorTime = src.anchorTime;
   dst.barIndex = src.barIndex;
   dst.barsInAnchor = src.barsInAnchor;

   dst.origin = src.origin;
   dst.sw = src.sw; dst.swd = src.swd; dst.swd2 = src.swd2;
   dst.swd3 = src.swd3; dst.swd4 = src.swd4;
   dst.swBuy = src.swBuy; dst.swSell = src.swSell;
   dst.sx = src.sx; dst.sy = src.sy; dst.sxx = src.sxx; dst.sxy = src.sxy;
   dst.su1 = src.su1; dst.su2 = src.su2;

   dst.atr = src.atr;
   dst.adx = src.adx;
   dst.retMom = src.retMom;
   dst.prevClose = src.prevClose;
   dst.havePrevClose = src.havePrevClose;
   dst.rangeEwma = src.rangeEwma;

   dst.lastOpen = src.lastOpen; dst.lastHigh = src.lastHigh;
   dst.lastLow = src.lastLow;   dst.lastClose = src.lastClose;
   dst.lastTickVol = src.lastTickVol; dst.lastRealVol = src.lastRealVol;
   dst.lastWeight = src.lastWeight;   dst.lastBuyFrac = src.lastBuyFrac;
   dst.lastEffPrice = src.lastEffPrice;

   dst.feedWarnings = src.feedWarnings;
   dst.ringCap = src.ringCap;
   dst.ringCount = src.ringCount;
   dst.ringHead = src.ringHead;
   VP_RESIZE(dst.ringPrice, src.ringCap);
   VP_RESIZE(dst.ringWeight, src.ringCap);
   for (int i = 0; i < src.ringCount; i++)
   {
      dst.ringPrice[i]  = src.ringPrice[i];
      dst.ringWeight[i] = src.ringWeight[i];
   }

   dst.vwap = src.vwap; dst.sigma = src.sigma;
   dst.sigmaObs = src.sigmaObs; dst.sigmaPrior = src.sigmaPrior;
   dst.z = src.z; dst.slopePct = src.slopePct; dst.slopeSigma = src.slopeSigma;
   dst.deltaTilt = src.deltaTilt; dst.r2 = src.r2;
   dst.skew = src.skew; dst.kurt = src.kurt;
   dst.signal = src.signal;
   dst.up1 = src.up1; dst.dn1 = src.dn1;
   dst.up2 = src.up2; dst.dn2 = src.dn2;
   dst.up3 = src.up3; dst.dn3 = src.dn3;
   dst.sigmaRatio = src.sigmaRatio;
   dst.tStat = src.tStat;
   dst.ready = src.ready;
}

//+------------------------------------------------------------------+
//| Can this bar be believed?                                        |
//|                                                                  |
//|  Real MT4 feeds push bars with a zero or negative price after a    |
//|  reconnection, bars whose high is below their low after a bad tick, |
//|  and - on some CFD feeds - bars with a 10x range around a contract  |
//|  switch.  Accumulating those is how an indicator ends up drawing a  |
//|  band through the axis.  A bar that fails these checks is skipped    |
//|  entirely: it moves neither the anchor nor the volatility context.   |
//+------------------------------------------------------------------+
bool vp_bar_usable(double o, double h, double l, double c)
{
   if (!vp_isfinite(o) || !vp_isfinite(h) || !vp_isfinite(l) || !vp_isfinite(c)) return false;
   if (!(o > 0.0) || !(c > 0.0)) return false;
   if (!(h >= l)) return false;
   if (!(h > 0.0)) return false;
   double range = h - l;
   // A single bar cannot travel more than the whole price - anything
   // wider is a data error (contract roll, zero tick, bad history).
   if (range > c) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Push one closed bar.                                             |
//|                                                                  |
//|  "anchor" is the anchor-period key computed by the caller (it      |
//|  owns the calendar logic); the engine only reacts to the change.    |
//+------------------------------------------------------------------+
void vp_engine_push(VpEngine &e, VpEngineConfig &cfg,
                    vp_int64 anchor, vp_int64 barTime, VpBar &b)
{
   //--- reject bars that cannot be believed --------------------------
   // A rejected bar moves *nothing*: not the anchor, not the ATR, not the
   // regression.  It is counted for diagnostics and otherwise ignored.
   if (!vp_bar_usable(b.open, b.high, b.low, b.close))
   {
      e.feedWarnings++;
      return;
   }

   //--- anchor roll -------------------------------------------------
   if (!e.started || anchor != e.anchorKey)
      vp_engine_begin_anchor(e, anchor, barTime, b.open);

   e.barIndex++;
   e.lastOpen = b.open; e.lastHigh = b.high; e.lastLow = b.low; e.lastClose = b.close;
   e.lastTickVol = b.tickVol; e.lastRealVol = b.realVol;

   //--- feed diagnostics --------------------------------------------
   e.vol.Push(b.tickVol, b.realVol);

   //--- weighting ----------------------------------------------------
   // The price observation for the bar.  For weightings that carry a
   // directional proxy we use the tick-rule adjusted price; for plain
   // volume modes we use the standard typical price, so the anchor stays
   // directly comparable with the textbook VWAP.
   double buyFrac = vp_buy_fraction(b.open, b.high, b.low, b.close, cfg.bvcK);
   double w = vp_bar_weight(cfg.volumeMode, b.open, b.high, b.low, b.close,
                            b.tickVol, b.realVol, e.rangeEwma,
                            e.vol.tickUsable, e.vol.tickConstant, e.vol.realUsable);

   double p;
   if (cfg.volumeMode == VP_VOL_BVC || cfg.volumeMode == VP_VOL_INVRANGE)
      p = vp_effective_price(b.open, b.high, b.low, b.close, buyFrac);
   else
      p = (b.high + b.low + b.close) / 3.0;
   if (!vp_isfinite(p) || p <= 0.0) p = b.close;
   if (!vp_isfinite(p) || p <= 0.0)
   {
      e.feedWarnings++;
      return;
   }

   //--- guard the accumulators against overflow ----------------------
   // Guards against overflow of the higher moments (d^2, d^4) on
   // pathological scales.  A bar this far from its own anchor is not
   // information about the anchor, it is an outlier to be skipped.
   double d = p - e.origin;
   if (!vp_isfinite(d) || vp_abs(d) > 1e150)
   {
      e.feedWarnings++;
      return;
   }

   //--- volatility context (anchor independent) ----------------------
   // Updated only for accepted bars, so a garbage tick cannot inflate
   // the ATR prior that the dispersion bands are shrunk towards.
   double tr1 = b.high - b.low;
   double tr2 = e.havePrevClose ? vp_abs(b.high - e.prevClose) : tr1;
   double tr3 = e.havePrevClose ? vp_abs(b.low  - e.prevClose) : tr1;
   double tr  = vp_max(tr1, vp_max(tr2, tr3));
   e.atr.Push(tr);
   e.adx.Push(b.high, b.low, b.close);
   if (e.havePrevClose && e.prevClose > 0.0 && b.close > 0.0)
   {
      double r = vp_log(b.close / e.prevClose);
      if (vp_isfinite(r)) e.retMom.Push(r);
   }
   e.prevClose = b.close;
   e.havePrevClose = true;

   double range = vp_abs(b.high - b.low);
   e.rangeEwma = (e.rangeEwma <= 0.0) ? range : (e.rangeEwma * 0.98 + range * 0.02);

   e.lastWeight = w;
   e.lastBuyFrac = buyFrac;
   e.lastEffPrice = p;

   //--- accumulate weighted moments about the current origin ---------
   double d2 = d * d;
   e.sw.Add(w);
   e.swd.Add(w * d);
   e.swd2.Add(w * d2);
   e.swd3.Add(w * d2 * d);
   e.swd4.Add(w * d2 * d2);
   e.swBuy.Add(w * buyFrac);
   e.swSell.Add(w * (1.0 - buyFrac));

   //--- OLS of price on bar index -------------------------------------
   double x = (double)e.barIndex;
   e.sx.Add(x); e.sy.Add(p); e.sxx.Add(x * x); e.sxy.Add(x * p);

   //--- unweighted price sums about the same origin -------------------
   e.su1.Add(d);
   e.su2.Add(d2);

   e.barsInAnchor++;

   //--- rolling window -------------------------------------------------
   vp_ring_push(e, p, w);

   //--- re-centre periodically to keep the conditioning ideal ----------
   if (e.barsInAnchor > 0 && (e.barsInAnchor % 128) == 0)
      vp_engine_reorigin(e, vp_engine_vwap(e));
}

//+------------------------------------------------------------------+
//| The composite score.                                             |
//|                                                                  |
//|  Two competing hypotheses about a VWAP deviation:                 |
//|                                                                  |
//|   * mean reversion* - price stretched N sigmas from the fair value |
//|     tends to snap back (the reversion edge institutions trade);     |
//|   * trend continuation* - when the anchor is sloping and the        |
//|     regression is tight, the deviation is *information*, not        |
//|     noise, and fading it is how retail accounts die.                |
//|                                                                  |
//|  Both are true; which dominates is regime dependent.  ADX and R^2   |
//|  decide the blend, and the output is bounded to [-1, 1] so it can   |
//|  be used directly as a position weight.                              |
//+------------------------------------------------------------------+
double vp_composite_signal(VpEngine &e, VpEngineConfig &cfg)
{
   if (e.barsInAnchor < vp_imax(1, cfg.minBars)) return 0.0;

   double trendness = 0.0;
   if (cfg.adaptiveSignal)
   {
      double adxN = vp_clamp((e.adx.Value() - 15.0) / 25.0, 0.0, 1.0);
      double conf = vp_clamp(e.r2 * 3.0, 0.0, 1.0);
      trendness = vp_clamp(0.6 * adxN + 0.4 * conf, 0.0, 1.0);
   }

   // How stretched price is, in sigmas: the reversion hypothesis.
   double fade  = -vp_tanh(e.z / 1.6);
   // How significant the anchor's own drift is (t statistic of the slope,
   // ~6 sigma of significance saturates): the continuation hypothesis.
   double trend =  vp_tanh(e.tStat / 6.0);
   // Where the aggressive side of the tape has been sitting.
   double flow  =  vp_tanh(e.deltaTilt * 2.5);

   double sig = 0.0;
   if (cfg.adaptiveSignal)
   {
      sig = (1.0 - trendness) * fade + trendness * trend;
      sig = 0.85 * sig + 0.15 * flow;
   }
   else
   {
      sig = 0.60 * fade + 0.25 * trend + 0.15 * flow;
   }
   return vp_clamp(sig, -1.0, 1.0);
}

//+------------------------------------------------------------------+
//| Turn the accumulators into the numbers the chart displays.        |
//+------------------------------------------------------------------+
void vp_engine_evaluate(VpEngine &e, VpEngineConfig &cfg)
{
   e.ready = false;

   double W = e.sw.Val();
   if (!(W > 0.0) || e.barsInAnchor < 1)
   {
      e.vwap = e.lastClose;
      e.sigma = 0.0; e.sigmaObs = 0.0; e.sigmaPrior = 0.0;
      e.z = 0.0; e.slopePct = 0.0; e.slopeSigma = 0.0;
      e.deltaTilt = 0.0; e.r2 = 0.0; e.signal = 0.0; e.skew = 0.0; e.kurt = 0.0;
      e.up1 = e.lastClose; e.dn1 = e.lastClose;
      e.up2 = e.lastClose; e.dn2 = e.lastClose;
      e.up3 = e.lastClose; e.dn3 = e.lastClose;
      return;
   }

   //--- anchor -------------------------------------------------------
   e.vwap = vp_engine_vwap(e);

   //--- observed dispersion ------------------------------------------
   double varObs = vp_engine_variance(e);
   e.sigmaObs = vp_sqrt(varObs);

   //--- Brownian-bridge prior ----------------------------------------
   //  For a driftless path with per-bar sigma s observed over T bars the
   //  typical deviation of price from its own time average is
   //  s*sqrt(T/3).  ATR is a robust range based proxy for s (~2 sigma_bar
   //  for a Gaussian bar), so s ~ ATR/2.  Shrinking towards this prior
   //  is what makes the very first bars of a session usable.
   double T = (double)vp_imax(1, e.barsInAnchor);
   double sBar = 0.0;
   if (e.atr.Ready()) sBar = e.atr.Value() * 0.5;
   else if (e.retMom.n >= 2) sBar = e.retMom.StdDev() * e.vwap;
   double sigmaPrior = sBar * vp_sqrt(T / 3.0);
   if (!vp_isfinite(sigmaPrior) || sigmaPrior < 0.0) sigmaPrior = 0.0;
   e.sigmaPrior = sigmaPrior;

   //--- window modes ---------------------------------------------------
   e.sigma = e.sigmaObs;
   double vWin = 0.0, mWin = 0.0; int nWin = 0;
   // The rolling window pass is O(window); skip it entirely when the
   // user did not ask for it (this is what keeps a full 20 year M1
   // history load linear instead of quadratic).
   if (cfg.sigmaMode != VP_SIGMA_SESSION)
   {
      vp_ring_variance(e, vWin, mWin, nWin);
   }
   if (cfg.sigmaMode == VP_SIGMA_WINDOW)
   {
      if (nWin >= 2) e.sigma = vp_sqrt(vWin);
   }
   else if (cfg.sigmaMode == VP_SIGMA_BLEND)
   {
      if (nWin >= 2)
      {
         double wWin = 0.5;
         e.sigma = vp_sqrt(vWin * wWin + varObs * (1.0 - wWin));
      }
   }

   //--- shrinkage towards the prior -------------------------------------
   if (cfg.adaptSigma && sigmaPrior > 0.0)
   {
      int    nPrior = vp_imax(0, cfg.adaptPriorBars);
      double nObs   = (double)vp_imax(1, e.barsInAnchor);
      double wPrior = (double)nPrior / (nObs + (double)nPrior);
      double sigmaShrunk = vp_sqrt(varObs * (1.0 - wPrior) + sigmaPrior * sigmaPrior * wPrior);
      if (cfg.sigmaMode == VP_SIGMA_SESSION) e.sigma = sigmaShrunk;
      else if (nWin < 5) e.sigma = sigmaShrunk;
   }
   e.sigmaRatio = vp_div_safe(e.sigma, e.sigmaPrior, 1.0);

   //--- z-score ---------------------------------------------------------
   double dx = e.lastClose - e.vwap;
   e.z = vp_div_safe(dx, e.sigma, 0.0);
   if (!vp_isfinite(e.z)) e.z = 0.0;
   if (e.z >  99.0) e.z =  99.0;
   if (e.z < -99.0) e.z = -99.0;

   //--- anchor slope -----------------------------------------------------
   VpOLS ols;
   ols.Reset();
   double dn = (double)e.barsInAnchor;
   if (ols.Solve(e.barsInAnchor, e.sx.Val(), e.sy.Val(), e.sxx.Val(), e.sxy.Val()))
   {
      e.slopePct   = vp_div_safe(ols.slope * 100.0, e.vwap, 0.0);
      e.slopeSigma = vp_div_safe(ols.slope, e.sigma, 0.0);
   }
   else { e.slopePct = 0.0; e.slopeSigma = 0.0; }

   //--- regression confidence (R^2 of price on index) ----------------------
   double Sxx = e.sxx.Val() - e.sx.Val() * e.sx.Val() / dn;
   double Sxy = e.sxy.Val() - e.sx.Val() * e.sy.Val() / dn;
   double Syy = vp_engine_var_unweighted(e) * dn;
   e.tStat = 0.0;
   if (Sxx > 0.0 && Syy > 0.0)
   {
      double rr = Sxy * Sxy / (Sxx * Syy);
      if (rr > 1.0) rr = 1.0;
      if (rr < 0.0) rr = 0.0;
      e.r2 = rr;

      // Trend significance: the t statistic of the slope.  This matters
      // because the *size* of a slope in sigma units is not the same as
      // "is this trend distinguishable from noise" - on a quiet anchor a
      // tiny drift can be highly significant, and on a wild one a big
      // drift can still be indistinguishable from a random walk.
      double sse = Syy - (Sxx > 0.0 ? Sxy * Sxy / Sxx : 0.0);
      if (sse < 0.0) sse = 0.0;
      double dof = (dn > 2.0) ? (dn - 2.0) : 1.0;
      double mse = sse / dof;
      double slope = vp_div_safe(Sxy, Sxx, 0.0);
      if (mse > 0.0)
      {
         double se = vp_sqrt(mse / Sxx);
         e.tStat = vp_div_safe(slope, se, 0.0);
      }
      else
      {
         // A perfect fit: either a genuine monotone run (huge t) or a
         // flat anchor (zero slope).
         e.tStat = (slope > 0.0) ? 1.0e6 : ((slope < 0.0) ? -1.0e6 : 0.0);
      }
      if (!vp_isfinite(e.tStat)) e.tStat = 0.0;
   }
   else e.r2 = 0.0;

   //--- order flow tilt -----------------------------------------------------
   double buy  = e.swBuy.Val();
   double sell = e.swSell.Val();
   e.deltaTilt = vp_div_safe(buy - sell, buy + sell, 0.0);
   if (!vp_isfinite(e.deltaTilt)) e.deltaTilt = 0.0;

   //--- distribution shape ---------------------------------------------------
   vp_engine_shape(e, e.skew, e.kurt);

   //--- bands ------------------------------------------------------------------
   double m1u = cfg.mult1, m2u = cfg.mult2, m3u = cfg.mult3;
   double m1d = cfg.mult1, m2d = cfg.mult2, m3d = cfg.mult3;
   if (cfg.bandMode == VP_BANDS_CONFIDENCE)
   {
      // Each tail is corrected separately: for a right-skewed anchor the
      // upper band has to sit further away than the lower one, and only
      // evaluating the expansion at the *negative* quantile captures that.
      m1u =  vp_cornish_fisher(cfg.mult1, e.skew, e.kurt);
      m1d = -vp_cornish_fisher(-cfg.mult1, e.skew, e.kurt);
      m2u =  vp_cornish_fisher(cfg.mult2, e.skew, e.kurt);
      m2d = -vp_cornish_fisher(-cfg.mult2, e.skew, e.kurt);
      m3u =  vp_cornish_fisher(cfg.mult3, e.skew, e.kurt);
      m3d = -vp_cornish_fisher(-cfg.mult3, e.skew, e.kurt);
   }
   double sd = e.sigma;
   e.up1 = e.vwap + m1u * sd; e.dn1 = e.vwap - m1d * sd;
   e.up2 = e.vwap + m2u * sd; e.dn2 = e.vwap - m2d * sd;
   e.up3 = e.vwap + m3u * sd; e.dn3 = e.vwap - m3d * sd;

   e.ready = (e.barsInAnchor >= vp_imax(1, cfg.minBars));

   //--- composite score -----------------------------------------------------------
   e.signal = vp_composite_signal(e, cfg);

   //--- last line of defence ---------------------------------------------------
   // Nothing that reaches a chart may be NaN, infinite or absurd.  These
   // branches are unreachable with sane input (the fuzz suite checks that
   // they are never taken on 60k hostile bars) but a trading indicator is
   // not allowed to have an "unreachable in theory" hole in it.
   double cap = (e.vwap > 0.0) ? e.vwap : 0.0;
   if (!vp_isfinite(e.vwap) || e.vwap <= 0.0) e.vwap = e.lastClose;
   if (!vp_isfinite(e.sigma) || e.sigma < 0.0) e.sigma = 0.0;
   if (cap > 0.0 && e.sigma > cap) e.sigma = cap;
   if (!vp_isfinite(e.z)) e.z = 0.0;
   if (!vp_isfinite(e.signal)) e.signal = 0.0;
   if (!vp_isfinite(e.deltaTilt)) e.deltaTilt = 0.0;
   if (!vp_isfinite(e.r2)) e.r2 = 0.0;
   if (!vp_isfinite(e.skew)) e.skew = 0.0;
   if (!vp_isfinite(e.kurt)) e.kurt = 0.0;
   if (!vp_isfinite(e.tStat)) e.tStat = 0.0;
   if (!vp_isfinite(e.up1)) e.up1 = e.vwap;
   if (!vp_isfinite(e.dn1)) e.dn1 = e.vwap;
   if (!vp_isfinite(e.up2)) e.up2 = e.vwap;
   if (!vp_isfinite(e.dn2)) e.dn2 = e.vwap;
   if (!vp_isfinite(e.up3)) e.up3 = e.vwap;
   if (!vp_isfinite(e.dn3)) e.dn3 = e.vwap;
   // Bands are ordered by construction; enforce it anyway so that a
   // corrupted accumulator can never draw a crossed band.
   if (e.dn1 > e.vwap) e.dn1 = e.vwap;
   if (e.up1 < e.vwap) e.up1 = e.vwap;
   if (e.dn2 > e.dn1) e.dn2 = e.dn1;
   if (e.up2 < e.up1) e.up2 = e.up1;
   if (e.dn3 > e.dn2) e.dn3 = e.dn2;
   if (e.up3 < e.up2) e.up3 = e.up2;
}

#endif // VWAPPRO_ENGINE_MQH
//+------------------------------------------------------------------+
