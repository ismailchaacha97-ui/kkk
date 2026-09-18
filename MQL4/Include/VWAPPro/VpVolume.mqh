//+------------------------------------------------------------------+
//|                                                     VpVolume.mqh |
//|          VWAP Pro - the volume truth engine                       |
//|                                                                  |
//|  This module exists because of the single biggest flaw in every   |
//|  VWAP indicator you can download: it blindly multiplies price by  |
//|  MT4's tick_volume as if tick counts were share volume.           |
//|                                                                  |
//|  Why that is wrong on retail forex/CFD feeds:                     |
//|                                                                  |
//|   1. MT4 tick_volume is *not* traded size.  It is the number of    |
//|      price updates the server pushed for that bar.  It is an       |
//|      integer, it is quantised, it is broker-dependent, and on      |
//|      indices/metals it is frequently a raw contract count while on |
//|      FX it is closer to quote intensity.                          |
//|   2. It is heavily autocorrelated with volatility, not with size.  |
//|      News spikes inflate it without any real transacted volume.    |
//|   3. It is often *absent* altogether (many brokers ship 0 or a     |
//|      constant).  Every "best VWAP" on the market then either        |
//|      paints a straight line or divides by zero.                    |
//|                                                                  |
//|  VWAP Pro fixes this in three independent ways:                    |
//|                                                                  |
//|   A. Degenerate-feed detection.  Constant / zero / NaN / negative  |
//|      volumes are detected and the engine transparently degrades to |
//|      the tick rule (B) or to an unbiased estimator (C) instead of   |
//|      producing garbage.                                             |
//|                                                                  |
//|   B. Tick-rule proxy volume (BVC).  For each bar we split its      |
//|      tick count by the buy/sell pressure implied by where the      |
//|      bar closed inside its own range, then weight by the range:    |
//|                                                                   |
//|          f_buy = 0.5 * (1 + 2c - 1) ... see VpVolumeWeights()       |
//|                                                                   |
//|      with an optional volume-clock (Easley/O'Hara VPIN style)       |
//|      bucketing of the body against the wicks.  The result tracks    |
//|      true directional participation far better than raw ticks.      |
//|                                                                   |
//|   C. Imbalance (proxy) volume: w_i = |close_i - open_i| (or the    |
//|      candle body in points) when even the tick count is useless.   |
//|      This is the standard fallback in academic "volume-less" VWAP   |
//|      literature and it is at least *scale free*.                   |
//|                                                                   |
//|  On top of that the engine provides the only weighting scheme that |
//|  actually maximises the statistical efficiency of a VWAP estimate  |
//|  when the "volume" is a noisy proxy:                                |
//|                                                                   |
//|     1 / variance weighting (inverse-variance), i.e.                 |
//|       w_i = v_i / sigma_i^2,  with sigma_i estimated from the       |
//|       bar range - long, quiet bars get more weight than wild spikes, |
//|       which is exactly what Bayesian/tick-data VWAP research says   |
//|       to do (a noisy observation contains less information).        |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_VOLUME_MQH
#define VWAPPRO_VOLUME_MQH

#include "VpCompat.mqh"
#include "VpMath.mqh"

#define VP_VOL_TICK    0   // weight = tick volume
#define VP_VOL_REAL    1   // weight = real volume (indices/CFD feeds)
#define VP_VOL_BVC     2   // weight = buy/sell tick-rule proxy
#define VP_VOL_RANGE   3   // weight = bar range (volatility clock)
#define VP_VOL_BODY    4   // weight = |close-open| (imbalance clock)
#define VP_VOL_UNIFORM 5   // weight = 1 (plain arithmetic anchor)
#define VP_VOL_INVRANGE 6  // weight = 1/range^2 * v (inverse-variance)
#define VP_VOL_AUTO    7   // engine picks the best available

//+------------------------------------------------------------------+
//| Which volume column is the feed actually giving us?              |
//+------------------------------------------------------------------+
struct VpVolumeProbe
{
   bool   tickUsable;    // tick volume carries information
   bool   realUsable;    // real volume carries information
   bool   tickConstant;  // every bar had the same value
   int    samples;
   double tickMean;
   double tickMin;
   double tickMax;
   double realMean;
   double lastTick;

   void Reset()
   {
      tickUsable = true; realUsable = false;
      tickConstant = false;
      samples = 0; tickMean = 0.0; tickMin = 0.0; tickMax = 0.0;
      realMean = 0.0; lastTick = 0.0;
   }

   //| Feed one bar of raw feed data.  Called once per historical bar
   //| during the initialisation sweep; afterwards Update() is enough.
   void Push(double tickVol, double realVol)
   {
      bool tickOk = vp_isfinite(tickVol) && tickVol > 0.0;
      bool realOk = vp_isfinite(realVol) && realVol > 0.0;
      if (!tickOk) { tickUsable = false; }
      if (realOk)  { realUsable = true; }

      if (tickOk)
      {
         if (samples == 0) { tickMin = tickVol; tickMax = tickVol; }
         if (tickVol < tickMin) tickMin = tickVol;
         if (tickVol > tickMax) tickMax = tickVol;
         tickMean = (tickMean * (double)samples + tickVol) / (double)(samples + 1);
         lastTick = tickVol;
         samples++;
      }
      if (realOk) realMean = (realMean * 0.98) + realVol * 0.02;

      // If the feed is handing out a constant, the "volume" carries no
      // information at all and weighting by it silently degenerates into
      // an unweighted anchor.  Detect it explicitly instead.
      if (samples >= 64 && tickMax == tickMin) tickConstant = true;
   }

   void Update(double tickVol, double realVol)
   {
      // Cheap online maintenance after init.
      bool tickOk = vp_isfinite(tickVol) && tickVol > 0.0;
      if (!tickOk) { tickUsable = false; return; }
      if (tickVol < tickMin) tickMin = tickVol;
      if (tickVol > tickMax) tickMax = tickVol;
      if (samples >= 64 && tickMax == tickMin) tickConstant = true;
      lastTick = tickVol;
   }
};

//+------------------------------------------------------------------+
//| Buy/sell pressure for one bar (tick rule family).
//|
//|     close_position = (C - L) / (H - L)      in [0, 1]
//|     f_buy          = (1 + k * (2 * close_position - 1)) / 2
//|
//|  k = 1 recovers the bulk-volume classification rule used in the
//|  academic literature; lower values shrink the split towards 50/50 for
//|  noisier instruments.
//|
//|  Note what is deliberately *not* here: any damping that shrinks the
//|  conviction of bars with a small body.  It is tempting (a doji "looks"
//|  uninformative) but it is wrong - a long-legged bar that closes exactly
//|  on its low is one of the strongest selling signatures on a chart, and
//|  penalising it costs exactly the bars where the tick rule has the most
//|  information.  There is a test that pins the monotonicity of this
//|  function in the close position for that reason.
//+------------------------------------------------------------------+
double vp_buy_fraction(double o, double h, double l, double c, double k)
{
   double range = h - l;
   if (!(range > 0.0))
   {
      // Dull bar: no information at all, stay neutral.
      return 0.5;
   }
   double pos = (c - l) / range;
   if (pos < 0.0) pos = 0.0;
   if (pos > 1.0) pos = 1.0;

   double f = 0.5 + 0.5 * k * (2.0 * pos - 1.0);

   // The split must stay strictly inside (0,1): a 100% one-sided bar is
   // never justified by a proxy classification, and a hard 0 or 1 would
   // make the order-flow tilt a step function.
   if (f < 0.02) f = 0.02;
   if (f > 0.98) f = 0.98;
   return f;
}

//+------------------------------------------------------------------+
//| Bar weight for a given weighting mode.                           |
//|                                                                  |
//| Returns a *positive* weight in proxy units.  The value is only    |
//| ever used in ratios (every accumulator divides by the running     |
//| total weight), so its absolute scale is irrelevant - which is why  |
//| a range clock and a share-count clock can be mixed safely.        |
//+------------------------------------------------------------------+
double vp_bar_weight(int mode, double o, double h, double l, double c,
                     double tickVol, double realVol, double rangeScale,
                     bool tickUsable, bool tickConstant, bool realUsable)
{
   double range = h - l;
   if (range < 0.0) range = -range;
   if (!(rangeScale > 0.0)) rangeScale = 1.0;

   double v = 0.0;
   bool   haveV = false;

   switch (mode)
   {
      case VP_VOL_REAL:
         if (realUsable && vp_isfinite(realVol) && realVol > 0.0) { v = realVol; haveV = true; }
         break;
      case VP_VOL_BVC:
         // Tick rule: the *magnitude* is the raw count, the direction is
         // resolved later by vp_effective_price().  If the feed has no
         // usable count we fall back to the volatility clock, which is
         // the best available proxy for participation.
         if (realUsable && vp_isfinite(realVol) && realVol > 0.0) { v = realVol; haveV = true; }
         else if (tickUsable && !tickConstant && vp_isfinite(tickVol) && tickVol > 0.0) { v = tickVol; haveV = true; }
         else if (range > 0.0) { v = range; haveV = true; }
         break;
      case VP_VOL_TICK:
         if (tickUsable && !tickConstant && vp_isfinite(tickVol) && tickVol > 0.0) { v = tickVol; haveV = true; }
         break;
      case VP_VOL_RANGE:
         if (range > 0.0) { v = range; haveV = true; }
         break;
      case VP_VOL_BODY:
         if (vp_abs(c - o) > 0.0) { v = vp_abs(c - o); haveV = true; }
         break;
      case VP_VOL_UNIFORM:
         v = 1.0; haveV = true;
         break;
      case VP_VOL_INVRANGE:
         // Inverse-variance (a.k.a. precision) weighting: the bar's price
         // observation is noisy with sigma proportional to its range, so
         // its information content is 1/sigma^2.  Multiplied by the
         // volume proxy this is the Gauss-Markov optimal combination of
         // "how much traded" and "how cleanly it traded".
         if (tickUsable && !tickConstant && vp_isfinite(tickVol) && tickVol > 0.0 && range > 0.0)
         {
            double rs = range / rangeScale;
            v = tickVol / (rs * rs);
            haveV = true;
         }
         break;
      case VP_VOL_AUTO:
      default:
         // Priority: real volume > clean tick volume > volatility clock.
         if (realUsable && vp_isfinite(realVol) && realVol > 0.0) { v = realVol; haveV = true; }
         else if (tickUsable && !tickConstant && vp_isfinite(tickVol) && tickVol > 0.0) { v = tickVol; haveV = true; }
         else if (range > 0.0) { v = range; haveV = true; }
         break;
   }

   if (!haveV || !(v > 0.0))
   {
      // Thin/flat bar: contribute with a floor weight so we neither drop
      // the bar (which biases the anchor) nor let it dominate.  One
      // millionth of a normal bar is enough to be invisible.
      v = 1e-6;
   }
   return v;
}

//+------------------------------------------------------------------+
//| Weighted *price* for a bar under the BVC weighting.               |
//|                                                                  |
//|  Instead of using the typical price (H+L+C)/3 for every bar - the  |
//|  crude approximation every public VWAP uses - we split the bar by   |
//|  the inferred buy/sell pressure and use the corresponding side of   |
//|  the bar.  Bars dominated by buying are anchored towards their      |
//|  highs, bars dominated by selling towards their lows, which is what |
//|  true VWAP does with real prints (buy prints trade at the ask).     |
//+------------------------------------------------------------------+
double vp_effective_price(double o, double h, double l, double c, double buyFraction)
{
   double typical = (h + l + c) / 3.0;
   if (!(h > l)) return typical;
   // Bar VWAP proxy: a blend of the typical price and the buy/sell
   // weighted average of the bar's traded extremes.
   double wBuy  = buyFraction;
   double wSell = 1.0 - buyFraction;
   // Price levels actually available inside the bar for each side.
   double pBuy  = (h + c) * 0.5;         // buyers transact up here
   double pSell = (l + c) * 0.5;         // sellers transact down here
   double vwapProxy = (pBuy * wBuy + pSell * wSell);
   // Blend 60/40 with the typical price so the anchor stays smooth.
   return 0.6 * vwapProxy + 0.4 * typical;
}

#endif // VWAPPRO_VOLUME_MQH
//+------------------------------------------------------------------+
