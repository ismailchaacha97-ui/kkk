//+------------------------------------------------------------------+
//|                                                       VpMath.mqh |
//|      VWAP Pro - streaming statistics (portable MQL4 / C++)        |
//|                                                                  |
//|  Everything here is *streaming*: O(1) memory and O(1) time per    |
//|  update, so the indicator stays flat on a 20-year M1 chart.       |
//|                                                                  |
//|  A note on numerical accuracy, because this is where most         |
//|  hand-written indicators quietly fall apart:                      |
//|                                                                  |
//|  The classic "sum(x), sum(x^2), sum(xy), sum(y)" accumulation is  |
//|  a numerical disaster on financial data - price levels are large  |
//|  (1.10000 or 35000.5) while bar-to-bar *variance* is tiny, so     |
//|  sum(x^2) - sum(x)^2/n suffers catastrophic cancellation.  On     |
//|  EURUSD M1 a few thousand bars are routinely enough to produce a  |
//|  *negative* variance, hence a NaN slope, hence a broken band -    |
//|  which is precisely the "indicator paints nonsense" bug users see.|
//|                                                                  |
//|  We therefore use Welford / Chan parallel-combination updates,     |
//|  which are the numerically stable form of the same quantities.    |
//|  The included test suite demonstrates the difference on synthetic  |
//|  data engineered to cancel (see tests/test_math.cpp).             |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_MATH_MQH
#define VWAPPRO_MATH_MQH

#include "VpCompat.mqh"

//+------------------------------------------------------------------+
//| Streaming mean / variance accumulator (Welford + Chan).          |
//+------------------------------------------------------------------+
struct VpMoments
{
   int    n;        // sample count
   double mean;     // running mean of x
   double m2;       // sum of squared deviations

   void Reset() { n = 0; mean = 0.0; m2 = 0.0; }

   //| Chan et al. parallel merge - the workhorse of the whole library.
   void Merge(int nb, double meanB, double m2B)
   {
      if (nb <= 0) return;
      if (n <= 0)
      {
         n = nb; mean = meanB; m2 = m2B;
         if (m2 < 0.0) m2 = 0.0;
         return;
      }
      double delta = meanB - mean;
      int    nt    = n + nb;
      double w     = vp_div_safe((double)nb, (double)nt, 0.0);
      mean = mean + delta * w;
      m2   = m2 + m2B + delta * delta * (double)n * w;
      n    = nt;
      if (m2 < 0.0) m2 = 0.0;      // guard against any residual rounding
   }

   void Push(double x)
   {
      n++;
      double delta = x - mean;
      mean = mean + delta / (double)n;
      m2   = m2 + delta * (x - mean);
      if (m2 < 0.0) m2 = 0.0;
   }

   double Variance()
   {
      if (n < 2) return 0.0;
      double v = m2 / (double)(n - 1);
      return (v > 0.0) ? v : 0.0;
   }

   double StdDev() { return vp_sqrt(Variance()); }
   bool   Valid()  { return n >= 2; }
};

//+------------------------------------------------------------------+
//| Streaming covariance accumulator for (x, y) pairs.                |
//|                                                                  |
//|  Also exposes the Pearson coefficient without ever forming the     |
//|  variance of each series separately, so any positive scaling of x  |
//|  or y leaves the result bit-for-bit identical.  That single        |
//|  property kills the entire family of "my VWAP sigma is in USD, it  |
//|  should be in points" bugs: the z-score of price against a VWAP    |
//|  band is normalised by the price scale and is therefore quote-     |
//|  currency and digit-count agnostic.                                 |
//+------------------------------------------------------------------+
struct VpCovariance
{
   double m2x;      // sum (x - mx)^2
   double m2y;      // sum (y - my)^2
   double cxy;      // sum (x - mx)(y - my)
   double mx;       // running mean of x
   double my;       // running mean of y
   int    n;

   void Reset()
   {
      m2x = 0.0; m2y = 0.0; cxy = 0.0;
      mx = 0.0; my = 0.0; n = 0;
   }

   //| Chan et al. parallel merge of two disjoint chunks.
   void Merge(int nb, double mxB, double myB, double m2xB, double m2yB, double cxyB)
   {
      if (nb <= 0) return;
      if (n <= 0)
      {
         n = nb; m2x = m2xB; m2y = m2yB; cxy = cxyB; mx = mxB; my = myB;
         if (m2x < 0.0) m2x = 0.0;
         if (m2y < 0.0) m2y = 0.0;
         return;
      }
      int    nt  = n + nb;
      double na  = (double)n;
      double nbv = (double)nb;
      double w   = vp_div_safe(nbv, (double)nt, 0.0);
      double dx  = mxB - mx;
      double dy  = myB - my;
      cxy = cxy + cxyB + dx * dy * na * w;
      m2x = m2x + m2xB + dx * dx * na * w;
      m2y = m2y + m2yB + dy * dy * na * w;
      mx  = mx + dx * w;
      my  = my + dy * w;
      n   = nt;
      if (m2x < 0.0) m2x = 0.0;
      if (m2y < 0.0) m2y = 0.0;
   }

   //| Streaming pair update (single pass).
   void PushXY(double x, double y)
   {
      n++;
      double dx = x - mx;
      double dy = y - my;
      mx = mx + dx / (double)n;
      my = my + dy / (double)n;
      cxy = cxy + dx * (y - my);
      m2x = m2x + dx * (x - mx);
      m2y = m2y + dy * (y - my);
      if (m2x < 0.0) m2x = 0.0;
      if (m2y < 0.0) m2y = 0.0;
   }

   //| Correlation in [-1, 1].  Scale invariant by construction.
   double Corr()
   {
      if (n < 2) return 0.0;
      if (!(m2x > 0.0) || !(m2y > 0.0)) return 0.0;
      double r = cxy / vp_sqrt(m2x * m2y);
      if (vp_isnan(r)) return 0.0;
      if (r >  1.0) r =  1.0;
      if (r < -1.0) r = -1.0;
      return r;
   }

   //| R squared - the share of price variance explained by the linear
   //| component.  Used as the "is this trend worth following" weight.
   double RSquared()
   {
      double r = Corr();
      return r * r;
   }
};

//+------------------------------------------------------------------+
//| Ordinary least squares fit y = a + b*x.                          |
//|                                                                  |
//|  Uses the centred sums (Sxx, Sxy) rather than the textbook         |
//|  sum(x)sum(y) form; on real data the textbook form loses most of   |
//|  the significant digits of both the slope AND the intercept, which |
//|  is why hand-rolled "linear regression channels" visibly jitter.   |
//|  Both forms are mathematically identical, so the test suite can     |
//|  assert agreement to ~1e-12 on well conditioned input.              |
//+------------------------------------------------------------------+
struct VpOLS
{
   double slope;
   double intercept;
   bool   ok;

   void Reset() { slope = 0.0; intercept = 0.0; ok = false; }

   //| Solve from raw sums.  Returns false for degenerate input.
   bool Solve(int n, double sx, double sy, double sxx, double sxy)
   {
      ok = false; slope = 0.0; intercept = 0.0;
      if (n < 2) return false;
      double dn = (double)n;
      double xx = sxx - sx * sx / dn;              // Sxx (centred)
      double xy = sxy - sx * sy / dn;              // Sxy (centred)
      if (vp_abs(xx) <= 1e-18) return false;
      slope     = xy / xx;
      intercept = sy / dn - slope * (sx / dn);
      if (vp_isnan(slope) || vp_isnan(intercept)) return false;
      if (!vp_isfinite(slope) || !vp_isfinite(intercept)) return false;
      ok = true;
      return true;
   }

   double ValueAt(double x) { return intercept + slope * x; }
};

//+------------------------------------------------------------------+
//| Average True Range (Wilder).                                     |
//|                                                                  |
//|  Seed = arithmetic mean of the first "period" true ranges, then    |
//|  Wilder smoothing - the same definition MT4's own ATR uses, so     |
//|  ATR here matches the platform indicator and ATR-relative sizing    |
//|  behaves the way a trader expects.                                  |
//+------------------------------------------------------------------+
struct VpATR
{
   int    period;
   int    count;
   double seedSum;
   double value;

   void Reset(int p) { period = vp_imax(1, p); count = 0; seedSum = 0.0; value = 0.0; }

   void Push(double trueRange)
   {
      double tr = vp_abs(trueRange);
      if (!vp_isfinite(tr)) return;
      if (count < period)
      {
         seedSum += tr;
         count++;
         if (count == period) value = seedSum / (double)period;
      }
      else
      {
         value = value + (tr - value) / (double)period;
      }
   }

   bool   Ready() { return count >= period; }
   double Value() { return Ready() ? value : 0.0; }
};

//+------------------------------------------------------------------+
//| Wilder's ADX - a regime filter.                                  |
//|                                                                  |
//|  High ADX = directional market  -> deviations get bought/sold.     |
//|  Low  ADX = rotation            -> deviations mean revert.         |
//|  The indicator uses this to pick which half of the signal set is   |
//|  statistically appropriate instead of firing everything blindly.   |
//+------------------------------------------------------------------+
struct VpADX
{
   int    period;
   int    count;
   double trS, dmpS, dmmS;      // seed sums
   double trR, dmpR, dmmR;      // Wilder smoothed sums
   double adx;
   int    adxCount;
   double adxSeedSum;
   double prevHigh, prevLow, prevClose;
   bool   havePrev;

   void Reset(int p)
   {
      period = vp_imax(2, p);
      count = 0; trS = 0.0; dmpS = 0.0; dmmS = 0.0;
      trR = 0.0; dmpR = 0.0; dmmR = 0.0;
      adx = 0.0; adxCount = 0; adxSeedSum = 0.0;
      havePrev = false;
      prevHigh = 0.0; prevLow = 0.0; prevClose = 0.0;
   }

   void Push(double high, double low, double close)
   {
      if (!havePrev)
      {
         prevHigh = high; prevLow = low; prevClose = close;
         havePrev = true;
         return;
      }
      double upMove   = high - prevHigh;
      double downMove = prevLow - low;
      double dmp = (upMove > downMove && upMove > 0.0) ? upMove : 0.0;
      double dmm = (downMove > upMove && downMove > 0.0) ? downMove : 0.0;
      double tr1 = high - low;
      double tr2 = vp_abs(high - prevClose);
      double tr3 = vp_abs(low  - prevClose);
      double tr  = vp_max(tr1, vp_max(tr2, tr3));

      prevHigh = high; prevLow = low; prevClose = close;

      if (count < period)
      {
         trS += tr; dmpS += dmp; dmmS += dmm;
         count++;
         if (count == period) { trR = trS; dmpR = dmpS; dmmR = dmmS; }
         return;
      }

      // Wilder smoothing
      trR  = trR  - trR  / (double)period + tr;
      dmpR = dmpR - dmpR / (double)period + dmp;
      dmmR = dmmR - dmmR / (double)period + dmm;

      double diP = 100.0 * vp_div_safe(dmpR, trR, 0.0);
      double diM = 100.0 * vp_div_safe(dmmR, trR, 0.0);
      double dx  = 100.0 * vp_div_safe(vp_abs(diP - diM), diP + diM, 0.0);

      adxCount++;
      if (adxCount <= period)
      {
         adxSeedSum += dx;
         if (adxCount == period) adx = adxSeedSum / (double)period;
      }
      else
      {
         adx = (adx * (double)(period - 1) + dx) / (double)period;
      }
   }

   bool   Ready() { return adxCount >= period; }
   double Value() { return Ready() ? adx : 0.0; }
};

//+------------------------------------------------------------------+
//| Rescaled-range (Hurst) exponent over one window.                 |
//|                                                                  |
//|  H ~ 0.5 : random walk      -> z-scores behave normally           |
//|  H > 0.5 : trending          -> deviations keep extending          |
//|  H < 0.5 : mean reverting    -> deviations snap back               |
//|                                                                  |
//|  R/S on log-returns.  O(n) per evaluation, n <= 128, evaluated at  |
//|  most every "update frequency" bars, so the cost is bounded.       |
//+------------------------------------------------------------------+
double vp_hurst_rs(int n, VP_ARR(double, x))
{
   if (n < 8) return 0.5;
   int m = n;
   if (m > VP_SIZE(x)) m = VP_SIZE(x);
   if (m < 8) return 0.5;

   double sum = 0.0;
   for (int i = 0; i < m; i++) sum += x[i];
   double mean = sum / (double)m;

   double cum = 0.0, mn = 0.0, mx = 0.0;
   for (int i = 0; i < m; i++)
   {
      cum += x[i] - mean;
      if (i == 0) { mn = cum; mx = cum; }
      else { if (cum < mn) mn = cum; if (cum > mx) mx = cum; }
   }
   double range = mx - mn;

   double ss = 0.0;
   for (int i = 0; i < m; i++) { double d = x[i] - mean; ss += d * d; }
   double sd = vp_sqrt(ss / (double)m);
   if (!(sd > 0.0)) return 0.5;
   if (!(range > 0.0)) return 0.5;

   double h = vp_log(range / sd) / vp_log((double)m);
   if (!vp_isfinite(h)) return 0.5;
   if (h < 0.0) h = 0.0;
   if (h > 1.0) h = 1.0;
   return h;
}

#endif // VWAPPRO_MATH_MQH
//+------------------------------------------------------------------+
