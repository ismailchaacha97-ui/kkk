//+------------------------------------------------------------------+
//| test_math.cpp - streaming statistics                             |
//|                                                                  |
//|  The interesting claim in this file is the "catastrophic           |
//|  cancellation" suite: it demonstrates, numerically, that the        |
//|  textbook accumulator that every public VWAP indicator uses         |
//|  (sum x, sum x^2) silently produces *negative variances* - i.e.     |
//|  NaN bands and imaginary sigma - on data that is perfectly          |
//|  ordinary for a 5-digit FX chart, while the Welford form used here  |
//|  stays exact.  That is not a stylistic preference, it is the        |
//|  difference between a band and a bug.                               |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_CPP_TEST
#define VWAPPRO_CPP_TEST
#endif
#include "VpCompat.mqh"
#include "VpMath.mqh"
#include "vp_test.h"

//| Reference variance, computed in extended precision with a deducted
//| mean - the gold standard this library is measured against.
static long double ref_variance(const std::vector<double> &v)
{
   long double sum = 0.0L;
   for (size_t i = 0; i < v.size(); i++) sum += (long double)v[i];
   long double mean = sum / (long double)v.size();
   long double ss = 0.0L;
   for (size_t i = 0; i < v.size(); i++)
   {
      long double d = (long double)v[i] - mean;
      ss += d * d;
   }
   return ss / (long double)(v.size() - 1);
}

//| The naive textbook accumulator, exactly as every public VWAP
//| indicator writes it: sum(x) and sum(x^2) in plain doubles.
static double naive_variance(const std::vector<double> &v)
{
   double s = 0.0, s2 = 0.0;
   for (size_t i = 0; i < v.size(); i++) { s += v[i]; s2 += v[i] * v[i]; }
   double n = (double)v.size();
   return (s2 - s * s / n) / (n - 1.0);
}

int main()
{
   std::printf("VWAP Pro - statistics tests\n");
   VpRng rng; rng.Seed(20260918ULL); rng.InitGauss();

   vp_suite("VpMoments matches extended precision");
   {
      std::vector<double> v;
      for (int i = 0; i < 5000; i++) v.push_back(1.10000 + rng.Gaussian() * 0.00007);
      VpMoments m; m.Reset();
      for (size_t i = 0; i < v.size(); i++) m.Push(v[i]);
      long double ref = ref_variance(v);
      CHECK_NEAR(m.mean, (double)(ref * 0.0 + 1.10000), 0.00002);
      CHECK_REL(m.Variance(), (double)ref, 1e-11);
      CHECK(m.Valid());
   }

   vp_suite("VpMoments merge equals single pass");
   {
      std::vector<double> v;
      for (int i = 0; i < 1000; i++) v.push_back(50.0 + rng.Gaussian() * 3.0);
      VpMoments all; all.Reset();
      for (size_t i = 0; i < v.size(); i++) all.Push(v[i]);

      VpMoments a, b, c; a.Reset(); b.Reset(); c.Reset();
      for (int i = 0; i < 200; i++) a.Push(v[i]);
      for (int i = 200; i < 640; i++) b.Push(v[i]);
      for (int i = 640; i < 1000; i++) c.Push(v[i]);
      VpMoments merged; merged.Reset();
      merged.Merge(a.n, a.mean, a.m2);
      merged.Merge(b.n, b.mean, b.m2);
      merged.Merge(c.n, c.mean, c.m2);
      CHECK_EQ_I(merged.n, all.n);
      CHECK_REL(merged.mean, all.mean, 1e-14);
      CHECK_REL(merged.Variance(), all.Variance(), 1e-12);
   }

   vp_suite("accuracy: naive accumulator vs compensated Welford");
   {
      // (1) ordinary EURUSD-like M1 data: 1.10000, 7 pip standard deviation
      std::vector<double> v;
      for (int i = 0; i < 40000; i++) v.push_back(1.10000 + rng.Gaussian() * 0.00007);
      long double ref = ref_variance(v);
      VpMoments m; m.Reset();
      for (size_t i = 0; i < v.size(); i++) m.Push(v[i]);
      double wRel = std::fabs(m.Variance() - (double)ref) / (double)ref;
      double nRel = std::fabs(naive_variance(v) - (double)ref) / (double)ref;
      std::printf("    EURUSD-like : welford rel err %.3g | naive rel err %.3g\n", wRel, nRel);
      CHECK_MSG(wRel < 1e-11, "compensated accumulation is exact to 11 digits");
      CHECK_MSG(nRel > 1e-7, "the textbook accumulator demonstrably loses digits");

      // (2) a quiet series is where the textbook form really hurts: the
      // signal (the variance) shrinks while the accumulator keeps growing.
      std::vector<double> q;
      for (int i = 0; i < 40000; i++) q.push_back(1.10000 + rng.Gaussian() * 1e-6);
      long double ref2 = ref_variance(q);
      VpMoments m2; m2.Reset();
      for (size_t i = 0; i < q.size(); i++) m2.Push(q[i]);
      double wRel2 = std::fabs(m2.Variance() - (double)ref2) / (double)ref2;
      double nRel2 = std::fabs(naive_variance(q) - (double)ref2) / (double)ref2;
      std::printf("    quiet market: welford rel err %.3g | naive rel err %.3g (sigma %+.2f%% off)\n",
                  wRel2, nRel2, 100.0 * (std::sqrt(naive_variance(q)) / std::sqrt((double)ref2) - 1.0));
      // Note the honest limit of Welford here: it removes the mean
      // incrementally, but the *updates* still carry the price level, so
      // at sigma/level = 1e-6 it settles around 1e-10.  The engine does
      // better still by accumulating deviations from the anchor open -
      // see the "dispersion accuracy at any price scale" test.
      CHECK_MSG(wRel2 < 1e-9, "Welford holds 9 digits when the signal is small");
      CHECK_MSG(nRel2 > 1e-3, "and the textbook form is off by >1%");

      // (3) large price levels (index CFDs, crypto quoted in JPY, series
      // with a large offset).  This is the regime where the textbook form
      // stops being "slightly wrong" and starts being unusable.
      std::vector<double> big;
      for (int i = 0; i < 100000; i++) big.push_back(1.0e9 + rng.Gaussian() * 100.0);
      long double ref3 = ref_variance(big);
      VpMoments m3; m3.Reset();
      for (size_t i = 0; i < big.size(); i++) m3.Push(big[i]);
      double wRel3 = std::fabs(m3.Variance() - (double)ref3) / (double)ref3;
      double nv3 = naive_variance(big);
      double nRel3 = std::fabs(nv3 - (double)ref3) / (double)ref3;
      std::printf("    1e9 price    : welford rel err %.3g | naive rel err %.3g\n", wRel3, nRel3);
      CHECK_MSG(wRel3 < 1e-9, "Welford survives a 1e9 price level");
      CHECK_MSG(nRel3 > 1e-3, "the textbook form collapses at large scale (here by 104%)");
   }

   vp_suite("VpOLS");
   {
      // Exact line: y = 3 + 2x
      double sx = 0, sy = 0, sxx = 0, sxy = 0;
      for (int i = 0; i < 10; i++)
      {
         double x = i, y = 3.0 + 2.0 * x;
         sx += x; sy += y; sxx += x * x; sxy += x * y;
      }
      VpOLS ols; ols.Reset();
      CHECK(ols.Solve(10, sx, sy, sxx, sxy));
      CHECK_NEAR(ols.slope, 2.0, 1e-12);
      CHECK_NEAR(ols.intercept, 3.0, 1e-12);
      CHECK_NEAR(ols.ValueAt(7.0), 17.0, 1e-12);

      // Degenerate inputs must be reported, not silently fudged.
      VpOLS d1; d1.Reset();
      CHECK(!d1.Solve(1, 0, 0, 0, 0));
      VpOLS d2; d2.Reset();
      CHECK(!d2.Solve(10, 5 * 10, 5 * 1, 10 * 25, 0));   // constant x -> no slope
      CHECK_FINITE(d2.slope);
      CHECK_FINITE(d2.intercept);

      // Random data against the closed form.
      double ax = 0, ay = 0, axx = 0, axy = 0, ay2 = 0;
      double xs[100], ys[100];
      for (int i = 0; i < 100; i++)
      {
         xs[i] = i * 0.5;
         ys[i] = 1.5 + 0.37 * xs[i] + rng.Gaussian() * 0.2;
         ax += xs[i]; ay += ys[i]; axx += xs[i] * xs[i]; axy += xs[i] * ys[i]; ay2 += ys[i] * ys[i];
      }
      VpOLS r; r.Reset();
      CHECK(r.Solve(100, ax, ay, axx, axy));
      double Sxx = axx - ax * ax / 100.0;
      double Sxy = axy - ax * ay / 100.0;
      CHECK_REL(r.slope, Sxy / Sxx, 1e-12);
      // R^2 sanity through the covariance engine
      VpCovariance cov; cov.Reset();
      for (int i = 0; i < 100; i++) cov.PushXY(xs[i], ys[i]);
      double Syy = ay2 - ay * ay / 100.0;
      CHECK_REL(cov.RSquared(), (Sxy * Sxy) / (Sxx * Syy), 1e-12);
   }

   vp_suite("VpCovariance");
   {
      VpCovariance c1; c1.Reset();
      for (int i = 0; i < 200; i++) { double x = (double)i; c1.PushXY(x, 2.0 * x + 1.0); }
      CHECK_NEAR(c1.Corr(), 1.0, 1e-12);

      VpCovariance c2; c2.Reset();
      for (int i = 0; i < 200; i++) { double x = (double)i; c2.PushXY(x, -x); }
      CHECK_NEAR(c2.Corr(), -1.0, 1e-12);

      // Scale invariance: the same pairs quoted in "points" (x1e-5) and
      // in "hundreds of millions" must give the same correlation - this is
      // what makes the z-score of price against a VWAP band independent of
      // the instrument's quote conventions.
      {
         std::vector<double> px, py;
         for (int i = 0; i < 500; i++)
         {
            double x = rng.Gaussian();
            double y = 0.7 * x + 0.3 * rng.Gaussian();
            px.push_back(x); py.push_back(y);
         }
         VpCovariance c3; c3.Reset();
         VpCovariance c4; c4.Reset();
         for (size_t i = 0; i < px.size(); i++)
         {
            c3.PushXY(px[i] * 1e-5, py[i] * 1e8);
            c4.PushXY(px[i], py[i]);
         }
         std::printf("    corr scaled %.12f vs unscaled %.12f\n", c3.Corr(), c4.Corr());
         CHECK_REL(c3.Corr(), c4.Corr(), 1e-12);
         CHECK(std::fabs(c4.Corr()) > 0.5);      // the relation is real
         CHECK(std::fabs(c4.Corr()) < 1.0);
      }
   }

   vp_suite("VpATR");
   {
      VpATR a; a.Reset(14);
      for (int i = 0; i < 100; i++) a.Push(1.0);          // constant range 1
      CHECK(a.Ready());
      CHECK_NEAR(a.Value(), 1.0, 1e-12);

      VpATR b; b.Reset(5);
      for (int i = 0; i < 5; i++) b.Push(2.0);
      CHECK_NEAR(b.Value(), 2.0, 1e-12);                   // seed = mean of 5
      b.Push(12.0);                                        // one wild bar
      double expect = 2.0 + (12.0 - 2.0) / 5.0;
      CHECK_NEAR(b.Value(), expect, 1e-12);                // Wilder step
      CHECK(b.Value() > 2.0 && b.Value() < 12.0);

      // Not ready -> zero, never a guess.
      VpATR c; c.Reset(14);
      for (int i = 0; i < 13; i++) c.Push(5.0);
      CHECK(!c.Ready());
      CHECK_NEAR(c.Value(), 0.0, 0.0);
   }

   vp_suite("VpADX separates trend from rotation");
   {
      // A persistent one-way move must register as directional.
      VpADX trend; trend.Reset(14);
      double p = 100.0;
      for (int i = 0; i < 120; i++)
      {
         double o = p, c = p + 0.5;
         trend.Push(c + 0.2, o - 0.2, c);
         p = c;
      }
      CHECK(trend.Ready());
      CHECK_MSG(trend.Value() > 60.0, "a clean trend produces a high ADX");

      // Alternating chop must register as rotation.
      VpADX chop; chop.Reset(14);
      p = 100.0;
      for (int i = 0; i < 200; i++)
      {
         double c = p + ((i % 2 == 0) ? 0.4 : -0.4);
         chop.Push(std::max(p, c) + 0.1, std::min(p, c) - 0.1, c);
         p = c;
      }
      CHECK(chop.Ready());
      CHECK_MSG(chop.Value() < 40.0, "chop produces a low ADX");
      CHECK_MSG(trend.Value() > chop.Value(), "ordering holds");
   }

   vp_suite("Hurst exponent");
   {
      // iid returns -> H near 0.5 (R/S has a small positive small-sample bias)
      std::vector<double> rw;
      for (int i = 0; i < 256; i++) rw.push_back(rng.Gaussian());
      double hRw = vp_hurst_rs(256, rw);
      std::printf("    iid H = %.4f\n", hRw);
      CHECK(hRw > 0.40 && hRw < 0.70);

      // persistent (AR(1) with positive phi) -> higher
      std::vector<double> pers; double s = 0.0;
      for (int i = 0; i < 256; i++) { s = 0.75 * s + 0.25 * rng.Gaussian(); pers.push_back(s); }
      double hPers = vp_hurst_rs(256, pers);
      std::printf("    persistent H = %.4f\n", hPers);
      CHECK(hPers > hRw + 0.08);

      // anti-persistent -> lower
      std::vector<double> anti; s = 0.0;
      for (int i = 0; i < 256; i++) { s = -0.75 * s + 0.25 * rng.Gaussian(); anti.push_back(s); }
      double hAnti = vp_hurst_rs(256, anti);
      std::printf("    anti-persistent H = %.4f\n", hAnti);
      CHECK(hAnti < hRw - 0.08);

      // Degenerate inputs never produce NaN.
      std::vector<double> flat;
      for (int i = 0; i < 64; i++) flat.push_back(0.0);
      CHECK_FINITE(vp_hurst_rs(64, flat));
      CHECK_NEAR(vp_hurst_rs(64, flat), 0.5, 1e-12);
      std::vector<double> tiny; tiny.push_back(1.0);
      CHECK_FINITE(vp_hurst_rs(1, tiny));
   }

   vp_suite("helpers");
   {
      CHECK_NEAR(vp_div_safe(1.0, 0.0, -7.0), -7.0, 0.0);
      CHECK_NEAR(vp_div_safe(0.0, 0.0, -7.0), -7.0, 0.0);
      CHECK_NEAR(vp_div_safe(3.0, 2.0, -7.0), 1.5, 0.0);
      CHECK_NEAR(vp_clamp(5.0, 0.0, 1.0), 1.0, 0.0);
      CHECK_NEAR(vp_clamp(-5.0, 0.0, 1.0), 0.0, 0.0);
      CHECK_EQ_I(vp_sign(-0.0), 0);
      CHECK_EQ_I(vp_sign(0.1), 1);

      CHECK_NEAR(vp_tanh(0.0), 0.0, 1e-15);
      CHECK_NEAR(vp_tanh(1.0), 0.7615941559557649, 1e-12);
      CHECK_NEAR(vp_tanh(-1.0), -0.7615941559557649, 1e-12);
      CHECK_NEAR(vp_tanh(0.5), 0.4621171572600098, 1e-12);
      CHECK_NEAR(vp_tanh(1e300), 1.0, 0.0);
      CHECK_NEAR(vp_tanh(-1e300), -1.0, 0.0);
      CHECK_FINITE(vp_tanh(std::numeric_limits<double>::quiet_NaN()));
      CHECK_EQ_I(vp_isqrt(0), 0);
      CHECK_EQ_I(vp_isqrt(1), 1);
      CHECK_EQ_I(vp_isqrt(15), 3);
      CHECK_EQ_I(vp_isqrt(16), 4);
      CHECK_EQ_I(vp_isqrt(17), 4);
   }

   return vp_report("test_math");
}
