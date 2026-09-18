//+------------------------------------------------------------------+
//| test_engine.cpp - the anchored VWAP engine                       |
//|                                                                  |
//|  This is the file that decides whether the indicator is allowed    |
//|  near a trading account.  It checks:                                |
//|                                                                  |
//|   * the anchor really is the textbook volume weighted average       |
//|     price (compared against a long-double brute force reference);    |
//|   * the dispersion is accurate at any price scale, and invariant    |
//|     under a change of quote units;                                   |
//|   * the bands are ordered, symmetric where they should be and       |
//|     asymmetric where the data says they should be;                   |
//|   * no input - including hostile input - can produce NaN, an        |
//|     inverted band or a leaked state;                                 |
//|   * the incremental (live) path and the batch (history) path give    |
//|     bit-identical results, which is the "no repaint" guarantee.      |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_CPP_TEST
#define VWAPPRO_CPP_TEST
#endif
#include "VpCompat.mqh"
#include "VpMath.mqh"
#include "VpEngine.mqh"
#include "vp_test.h"

//+------------------------------------------------------------------+
//| Long double references                                           |
//+------------------------------------------------------------------+
struct RefVwap
{
   std::vector<long double> wv, wp, wp2;
   long double W, P, P2;
   void Init() { wv.clear(); wp.clear(); wp2.clear(); W = 0; P = 0; P2 = 0; }
   void Push(long double w, long double p)
   {
      W += w; P += w * p; P2 += w * p * p;
   }
   double Vwap()   { return (double)(P / W); }
   double Var()    { long double m = P / W; long double v = P2 / W - m * m; return v > 0 ? (double)v : 0.0; }
};

static void push_bar(VpEngine &e, VpEngineConfig &cfg, vp_int64 anchor, vp_int64 t,
                     double o, double h, double l, double c, double tv, double rv)
{
   VpBar b;
   b.time = t; b.open = o; b.high = h; b.low = l; b.close = c;
   b.tickVol = tv; b.realVol = rv;
   vp_engine_push(e, cfg, anchor, t, b);
}

//| A reproducible synthetic bar stream (positive prices, valid OHLC).
struct BarStream
{
   VpRng rng;
   double price;
   int    n;
   long long t0;
   int    stepSec;

   void Init(double start, unsigned long long seed, long long startTime, int step)
   {
      rng.Seed(seed); rng.InitGauss();
      price = start; n = 0; t0 = startTime; stepSec = step;
   }

   void Next(double vol, double &o, double &h, double &l, double &c, double &tv, double &rv)
   {
      double r = vol * rng.Gaussian();
      o = price;
      c = o * std::exp(r);
      if (c <= 0.0) c = o * 0.999;
      double range = std::fabs(c - o) + std::fabs(rng.Gaussian()) * vol * o;
      h = std::max(o, c) + range * rng.Uniform();
      l = std::min(o, c) - range * rng.Uniform();
      if (h < std::max(o, c)) h = std::max(o, c);
      if (l > std::min(o, c)) l = std::min(o, c);
      price = c;
      tv = std::floor(50.0 + std::fabs(rng.Gaussian()) * 300.0) + 1.0;
      rv = 0.0;
      t0 += stepSec;
      n++;
   }
};

int main()
{
   std::printf("VWAP Pro - engine tests\n");
   VpEngineConfig cfg;
   cfg.Init();

   //==================================================================
   vp_suite("textbook VWAP reproduction (typical price, tick volume)");
   {
      cfg.volumeMode = VP_VOL_TICK;
      cfg.adaptSigma = false;
      VpEngine e; e.Init(cfg);
      RefVwap ref; ref.Init();

      BarStream bs; bs.Init(1.10000, 12345ULL, 1750000000LL, 60);
      double worst = 0.0;
      for (int i = 0; i < 3000; i++)
      {
         double o, h, l, c, tv, rv;
         bs.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(e, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
         vp_engine_evaluate(e, cfg);
         double tp = (h + l + c) / 3.0;
         ref.Push((long double)tv, (long double)tp);
         double rel = std::fabs(e.vwap - ref.Vwap()) / ref.Vwap();
         if (rel > worst) worst = rel;
      }
      std::printf("    worst relative deviation from brute force: %.3g\n", worst);
      CHECK_MSG(worst < 1e-12, "engine == textbook VWAP at every bar");
      CHECK_REL(e.vwap, ref.Vwap(), 1e-14);
      CHECK_EQ_I(e.barsInAnchor, 3000);

      // The dispersion must match the volume weighted definition too.
      double refSd = std::sqrt(ref.Var());
      std::printf("    sigma engine %.17g vs reference %.17g\n", e.sigmaObs, refSd);
      CHECK_REL(e.sigmaObs, refSd, 1e-12);
   }

   //==================================================================
   vp_suite("dispersion accuracy at any price scale (origin shift)");
   {
      double levels[3] = { 1.10000, 150.250, 1.0e9 };
      for (int k = 0; k < 3; k++)
      {
         double lvl = levels[k];
         double sig = lvl * 7e-5;
         cfg.volumeMode = VP_VOL_TICK;
         cfg.adaptSigma = false;
         VpEngine e; e.Init(cfg);
         RefVwap ref; ref.Init();
         BarStream bs; bs.Init(lvl, 777ULL + (unsigned long long)k, 1750000000LL, 60);
         for (int i = 0; i < 5000; i++)
         {
            double o, h, l, c, tv, rv;
            bs.Next(sig / lvl, o, h, l, c, tv, rv);
            push_bar(e, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
            ref.Push((long double)tv, (long double)((h + l + c) / 3.0));
         }
         vp_engine_evaluate(e, cfg);
         double refSd = std::sqrt(ref.Var());
         double relErr = std::fabs(e.sigmaObs - refSd) / refSd;
         std::printf("    level %.8g : sd %.10g  rel err %.3g\n", lvl, e.sigmaObs, relErr);
         CHECK_MSG(relErr < 1e-11, "long-double grade accuracy at this scale");
         CHECK_REL(e.vwap, ref.Vwap(), 1e-13);
      }
   }

   //==================================================================
   vp_suite("unit invariance: x1000 does not change z, +1e6 does not change shape");
   {
      cfg.volumeMode = VP_VOL_TICK;
      cfg.adaptSigma = false;
      VpEngine a, b, c;
      a.Init(cfg); b.Init(cfg); c.Init(cfg);
      BarStream bs; bs.Init(1.10000, 4242ULL, 1750000000LL, 60);
      for (int i = 0; i < 2000; i++)
      {
         double o, h, l, cl, tv, rv;
         bs.Next(0.00007, o, h, l, cl, tv, rv);
         vp_int64 t = 1000000LL + i;
         push_bar(a, cfg, 0, t, o, h, l, cl, tv, rv);
         push_bar(b, cfg, 0, t, o * 1000.0, h * 1000.0, l * 1000.0, cl * 1000.0, tv, rv);
         push_bar(c, cfg, 0, t, o + 1.0e6, h + 1.0e6, l + 1.0e6, cl + 1.0e6, tv, rv);
      }
      vp_engine_evaluate(a, cfg);
      vp_engine_evaluate(b, cfg);
      vp_engine_evaluate(c, cfg);

      CHECK_REL(b.vwap, a.vwap * 1000.0, 1e-13);
      CHECK_REL(b.sigma, a.sigma * 1000.0, 1e-11);
      CHECK_REL(b.z, a.z, 1e-12);
      CHECK_REL(b.deltaTilt, a.deltaTilt, 1e-9);
      CHECK_REL(b.slopeSigma, a.slopeSigma, 1e-11);
      CHECK_REL(b.r2, a.r2, 1e-10);
      CHECK_REL(b.signal, a.signal, 1e-10);

      // Translation: a *modest* absolute shift changes nothing but the
      // level (this is the exact algebraic property).
      VpEngine t1, t2;
      t1.Init(cfg); t2.Init(cfg);
      BarStream ts; ts.Init(1.10000, 9090ULL, 1750000000LL, 60);
      for (int i = 0; i < 1500; i++)
      {
         double o, h, l, cl, tv, rv;
         ts.Next(0.00007, o, h, l, cl, tv, rv);
         push_bar(t1, cfg, 0, 1000000LL + i, o, h, l, cl, tv, rv);
         push_bar(t2, cfg, 0, 1000000LL + i, o + 1000.0, h + 1000.0, l + 1000.0, cl + 1000.0, tv, rv);
      }
      vp_engine_evaluate(t1, cfg);
      vp_engine_evaluate(t2, cfg);
      CHECK_NEAR(t2.vwap - t1.vwap, 1000.0, 1e-9);
      CHECK_REL(t2.sigma, t1.sigma, 1e-11);
      CHECK_REL(t2.z, t1.z, 1e-10);
      CHECK_REL(t2.signal, t1.signal, 1e-8);
      CHECK_REL(t2.skew, t1.skew, 1e-8);

      // At +1e6 the test data itself stops being representable at the
      // scale of the price pattern (double has ~16 digits, the pattern
      // lives in the 4th), so we only require that nothing degrades
      // *catastrophically* - a 1e6 offset still gives 5 correct digits.
      std::printf("    +1e6 offset residual: sigma %.3g, z %.3g, signal %.3g\n",
                  std::fabs(c.sigma / a.sigma - 1.0), std::fabs(c.z / a.z - 1.0),
                  std::fabs(c.signal / a.signal - 1.0));
      CHECK_REL(c.sigma, a.sigma, 1e-7);
      CHECK(std::fabs(c.z - a.z) < 1e-5);
      CHECK(std::fabs(c.signal - a.signal) < 1e-4);
   }

   //==================================================================
   vp_suite("band construction");
   {
      cfg.volumeMode = VP_VOL_TICK;
      cfg.bandMode = VP_BANDS_SD;
      cfg.mult1 = 1.0; cfg.mult2 = 2.0; cfg.mult3 = 3.0;
      cfg.sigmaMode = VP_SIGMA_SESSION;
      VpEngine e; e.Init(cfg);
      BarStream bs; bs.Init(1.10000, 99ULL, 1750000000LL, 60);
      for (int i = 0; i < 800; i++)
      {
         double o, h, l, c, tv, rv;
         bs.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(e, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
      }
      vp_engine_evaluate(e, cfg);

      CHECK(e.sigma > 0.0);
      CHECK(e.dn3 < e.dn2 && e.dn2 < e.dn1 && e.dn1 < e.vwap);
      CHECK(e.vwap < e.up1 && e.up1 < e.up2 && e.up2 < e.up3);
      CHECK_NEAR(e.up1 - e.vwap, e.vwap - e.dn1, 1e-15);
      CHECK_NEAR(e.up2 - e.vwap, 2.0 * (e.up1 - e.vwap), 1e-15);
      CHECK_NEAR(e.up3 - e.vwap, 3.0 * (e.up1 - e.vwap), 1e-15);
      CHECK(e.ready);

      // A price shock must not be able to invert the bands.
      push_bar(e, cfg, 0, 2000000LL, 1.1, 1.6, 0.6, 1.5, 10, 0);
      vp_engine_evaluate(e, cfg);
      CHECK(e.dn3 < e.dn2 && e.dn2 < e.dn1 && e.dn1 <= e.vwap);
      CHECK(e.vwap <= e.up1 && e.up1 < e.up2 && e.up2 < e.up3);
   }

   //==================================================================
   vp_suite("confidence bands react to the distribution's shape");
   {
      cfg.bandMode = VP_BANDS_CONFIDENCE;
      cfg.mult1 = 1.2815515655446004;    // 80%
      cfg.mult2 = 1.9599639845400545;    // 95%
      cfg.mult3 = 2.5758293035489004;    // 99%
      VpEngine e; e.Init(cfg);
      BarStream bs; bs.Init(1.10000, 31337ULL, 1750000000LL, 60);
      for (int i = 0; i < 600; i++)
      {
         double o, h, l, c, tv, rv;
         bs.Next(0.00007, o, h, l, c, tv, rv);
         // inject a positive skew: occasional large upper excursions
         if (i % 97 == 0) { h += 0.0040; c = h - 0.0002; }
         push_bar(e, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
      }
      vp_engine_evaluate(e, cfg);
      std::printf("    skew %.4f kurt %.4f  up1-vwap %.6g  vwap-dn1 %.6g\n",
                  e.skew, e.kurt, e.up1 - e.vwap, e.vwap - e.dn1);
      CHECK(e.skew > 0.0);
      // Right skew widens the upper band and narrows the lower one.
      CHECK(e.up1 - e.vwap > e.vwap - e.dn1);
      CHECK_FINITE(e.up3); CHECK_FINITE(e.dn3);
      CHECK(e.dn3 < e.dn2 && e.dn2 < e.dn1);
      CHECK(e.up1 < e.up2 && e.up2 < e.up3);

      // Gaussian-ish data must not be distorted much by the correction.
      VpEngine g; g.Init(cfg);
      BarStream bs2; bs2.Init(1.10000, 31337ULL, 1750000000LL, 60);
      for (int i = 0; i < 4000; i++)
      {
         double o, h, l, c, tv, rv;
         bs2.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(g, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
      }
      vp_engine_evaluate(g, cfg);
      double asym = std::fabs((g.up1 - g.vwap) - (g.vwap - g.dn1)) / (g.up1 - g.vwap);
      std::printf("    symmetric data: band asymmetry %.4g (skew %.4f)\n", asym, g.skew);
      CHECK_MSG(asym < 0.25, "correction stays small for near-normal data");
   }

   //==================================================================
   vp_suite("shrinkage prior: usable from the first bars");
   {
      cfg.bandMode = VP_BANDS_SD;
      cfg.mult1 = 1.0; cfg.mult2 = 2.0; cfg.mult3 = 3.0;
      cfg.sigmaMode = VP_SIGMA_SESSION;
      cfg.adaptSigma = true;
      cfg.adaptPriorBars = 40;
      VpEngine e; e.Init(cfg);
      BarStream bs; bs.Init(1.10000, 8ULL, 1750000000LL, 60);

      // Warm the ATR estimator with one complete "day" first.
      for (int i = 0; i < 200; i++)
      {
         double o, h, l, c, tv, rv;
         bs.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(e, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
      }
      vp_engine_evaluate(e, cfg);
      double priorRef = e.sigmaPrior;
      CHECK(priorRef > 0.0);

      // Now start a fresh anchor and look at the first few bars: the
      // observed dispersion is meaningless there, the prior must carry it.
      e.Init(cfg);
      BarStream bs2; bs2.Init(1.10000, 8ULL, 1750000000LL, 60);
      for (int i = 0; i < 200; i++)   // rebuild ATR context
      {
         double o, h, l, c, tv, rv;
         bs2.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(e, cfg, 10, 1000000LL + i, o, h, l, c, tv, rv);
      }
      // Bar one of a new anchor period.
      double o, h, l, c, tv, rv;
      bs2.Next(0.00007, o, h, l, c, tv, rv);
      push_bar(e, cfg, 11, 2000000LL, o, h, l, c, tv, rv);
      vp_engine_evaluate(e, cfg);
      std::printf("    bar 1 of anchor: sigma %.6g (prior %.6g, observed %.6g)\n",
                  e.sigma, e.sigmaPrior, e.sigmaObs);
      CHECK(e.sigma > 0.0);
      CHECK_FINITE(e.z);
      CHECK(std::fabs(e.z) < 10.0);          // bounded, not divide-by-tiny garbage
      CHECK(e.sigma >= e.sigmaObs * 0.999);  // prior can only add information

      // With the prior switched off, the first bar has no dispersion at
      // all - which is exactly the pathology the prior fixes.
      cfg.adaptSigma = false;
      VpEngine e2; e2.Init(cfg);
      BarStream bs3; bs3.Init(1.10000, 8ULL, 1750000000LL, 60);
      for (int i = 0; i < 200; i++)
      {
         double oo, hh, ll2, cc, tt, rr;
         bs3.Next(0.00007, oo, hh, ll2, cc, tt, rr);
         push_bar(e2, cfg, 10, 1000000LL + i, oo, hh, ll2, cc, tt, rr);
      }
      bs3.Next(0.00007, o, h, l, c, tv, rv);
      push_bar(e2, cfg, 11, 2000000LL, o, h, l, c, tv, rv);
      vp_engine_evaluate(e2, cfg);
      std::printf("    prior off      : sigma %.6g\n", e2.sigma);
      CHECK_NEAR(e2.sigma, 0.0, 1e-15);
      cfg.adaptSigma = true;
   }

   //==================================================================
   vp_suite("rolling window sigma matches brute force");
   {
      cfg.sigmaMode = VP_SIGMA_WINDOW;
      cfg.zWindow = 50;
      cfg.adaptSigma = false;
      cfg.volumeMode = VP_VOL_TICK;
      VpEngine e; e.Init(cfg);        // Init() picks the new window up
      BarStream bs; bs.Init(1.10000, 555ULL, 1750000000LL, 60);
      std::vector<double> win;
      for (int i = 0; i < 500; i++)
      {
         double o, h, l, c, tv, rv;
         bs.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(e, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
         vp_engine_evaluate(e, cfg);
         win.push_back((h + l + c) / 3.0);
         if ((int)win.size() > 50) win.erase(win.begin());
      }
      // brute force volume weighted sd over the window needs the weights,
      // so recompute them the same way the engine would have.
      VpEngine w2; w2.Init(cfg);
      BarStream bs2; bs2.Init(1.10000, 555ULL, 1750000000LL, 60);
      std::vector<double> px, wts;
      for (int i = 0; i < 500; i++)
      {
         double o, h, l, c, tv, rv;
         bs2.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(w2, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
         px.push_back((h + l + c) / 3.0);
         wts.push_back(tv);
         if ((int)px.size() > 50) { px.erase(px.begin()); wts.erase(wts.begin()); }
      }
      RefVwap ref; ref.Init();
      for (size_t i = 0; i < px.size(); i++) ref.Push((long double)wts[i], (long double)px[i]);
      double refSd = std::sqrt(ref.Var());
      std::printf("    window sigma engine %.10g vs brute force %.10g\n", e.sigma, refSd);
      CHECK_REL(e.sigma, refSd, 1e-9);

      cfg.sigmaMode = VP_SIGMA_SESSION;
      cfg.zWindow = 0;
      cfg.adaptSigma = true;
   }

   //==================================================================
   vp_suite("anchor rollover");
   {
      cfg.sigmaMode = VP_SIGMA_SESSION;
      cfg.volumeMode = VP_VOL_TICK;
      VpEngine e; e.Init(cfg);
      BarStream bs; bs.Init(1.10000, 2024ULL, 1750000000LL, 60);
      RefVwap day2; day2.Init();
      double lastDay1Vwap = 0.0;
      for (int i = 0; i < 1000; i++)
      {
         double o, h, l, c, tv, rv;
         bs.Next(0.00007, o, h, l, c, tv, rv);
         vp_int64 anchor = (i < 500) ? 1 : 2;
         push_bar(e, cfg, anchor, 1000000LL + i, o, h, l, c, tv, rv);
         vp_engine_evaluate(e, cfg);
         if (i == 499) lastDay1Vwap = e.vwap;
         if (i >= 500) day2.Push((long double)tv, (long double)((h + l + c) / 3.0));
      }
      CHECK_EQ_I(e.barsInAnchor, 500);
      CHECK_REL(e.vwap, day2.Vwap(), 1e-13);
      CHECK(std::fabs(e.vwap - lastDay1Vwap) > 0.0);   // state did reset

      // barsInAnchor is the anchor's bar count, not the stream length
      CHECK_EQ_I(e.barIndex, 499);
   }

   //==================================================================
   vp_suite("hostile input fuzzing: nothing can produce NaN or a broken band");
   {
      cfg.volumeMode = VP_VOL_AUTO;
      cfg.adaptSigma = true;
      VpEngine e; e.Init(cfg);
      VpRng rng; rng.Seed(24680ULL); rng.InitGauss();
      int bad = 0, inverted = 0, nonFiniteZ = 0;
      for (int i = 0; i < 60000; i++)
      {
         double o = 1.1 + rng.Gaussian() * 0.001;
         double h = o, l = o, c = o, tv = 0.0, rv = 0.0;
         int kind = i % 12;
         switch (kind)
         {
            case 0: break;                                        // flat bar, no volume
            case 1: h = o; l = o; c = o; tv = 1; break;            // flat bar, volume
            case 2: h = o + 1e-9; l = o; tv = 5; break;            // microscopic range
            case 3: h = 0; l = 0; c = 0; tv = 0; break;            // zero prices
            case 4: h = -1; l = -2; c = -1.5; tv = 10; break;      // negative prices
            case 5: h = 1e12; l = 1e-9; c = 1e6; tv = 1e9; break;  // insane range
            case 6: h = o * 1.0001; l = o; c = h; tv = 0.0/0.0; break; // NaN volume
            case 7: h = o; l = o * 1.001; c = o; tv = 3; break;    // inverted range
            case 8: h = 1e300; l = 1e299; c = 1e299; tv = 1; break;// astronomic
            case 9: h = o; l = o; c = o; tv = -5; break;           // negative volume
            case 10: h = 1e-300; l = 1e-301; c = 1e-300; tv = 1; break;
            default: h = o + 0.001; l = o - 0.001; c = o; tv = 100; break;
         }
         vp_int64 anchor = i / 100;         // roll the anchor every 100 bars
         push_bar(e, cfg, anchor, 1000000LL + i, o, h, l, c, tv, rv);
         vp_engine_evaluate(e, cfg);

         if (!std::isfinite(e.vwap) || !std::isfinite(e.sigma) ||
             !std::isfinite(e.up1) || !std::isfinite(e.dn1) ||
             !std::isfinite(e.up2) || !std::isfinite(e.dn2) ||
             !std::isfinite(e.up3) || !std::isfinite(e.dn3) ||
             !std::isfinite(e.z) || !std::isfinite(e.signal) ||
             !std::isfinite(e.skew) || !std::isfinite(e.kurt) ||
             !std::isfinite(e.deltaTilt) || !std::isfinite(e.r2) ||
             !std::isfinite(e.slopeSigma))
            bad++;
         if (!(e.dn3 <= e.dn2 && e.dn2 <= e.dn1 && e.dn1 <= e.vwap &&
               e.vwap <= e.up1 && e.up1 <= e.up2 && e.up2 <= e.up3))
            inverted++;
         if (std::fabs(e.z) > 99.0000001) nonFiniteZ++;
         if (e.signal < -1.0 || e.signal > 1.0) bad++;
      }
      std::printf("    checked 60000 hostile bars: %d non-finite, %d inverted, %d z out of bounds\n",
                  bad, inverted, nonFiniteZ);
      CHECK_EQ_I(bad, 0);
      CHECK_EQ_I(inverted, 0);
      CHECK_EQ_I(nonFiniteZ, 0);
   }

   //==================================================================
   vp_suite("determinism");
   {
      VpEngine a, b; a.Init(cfg); b.Init(cfg);
      BarStream s1, s2;
      s1.Init(1.1, 5150ULL, 1750000000LL, 60);
      s2.Init(1.1, 5150ULL, 1750000000LL, 60);
      int diff = 0;
      for (int i = 0; i < 2000; i++)
      {
         double o, h, l, c, tv, rv;
         s1.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(a, cfg, i / 500, 1000000LL + i, o, h, l, c, tv, rv);
         vp_engine_evaluate(a, cfg);
         s2.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(b, cfg, i / 500, 1000000LL + i, o, h, l, c, tv, rv);
         vp_engine_evaluate(b, cfg);
         if (a.vwap != b.vwap || a.sigma != b.sigma || a.signal != b.signal) diff++;
      }
      CHECK_EQ_I(diff, 0);
   }

   //==================================================================
   vp_suite("live/committed separation (the no-repaint guarantee)");
   {
      // The indicator evaluates the forming bar on a clone of the engine
      // that holds closed bars.  Reproduce that here and prove the clone
      // is indistinguishable from a from-scratch run - i.e. the live
      // evaluation can never contaminate the committed state.
      VpEngine committed, preview;
      committed.Init(cfg);
      BarStream bs; bs.Init(1.2, 606ULL, 1750000000LL, 60);

      std::vector<double> hist;
      for (int i = 0; i < 500; i++)
      {
         double o, h, l, c, tv, rv;
         bs.Next(0.00007, o, h, l, c, tv, rv);
         // 100 extra "ticks" of the forming bar, evaluating each time
         for (int tick = 0; tick < 3; tick++)
         {
            double hh = h + 0.0001 * tick, cc = c + 0.00005 * tick;
            vp_engine_clone(committed, preview);
            push_bar(preview, cfg, 0, 1000000LL + i, o, hh, l, cc, tv, rv);
            vp_engine_evaluate(preview, cfg);
            CHECK_FINITE(preview.vwap);
         }
         // commit the closed bar
         push_bar(committed, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
         vp_engine_evaluate(committed, cfg);
         hist.push_back(committed.vwap);
      }

      // A fresh engine fed only the committed bars must agree exactly.
      VpEngine ref; ref.Init(cfg);
      BarStream bs2; bs2.Init(1.2, 606ULL, 1750000000LL, 60);
      int mismatch = 0;
      for (int i = 0; i < 500; i++)
      {
         double o, h, l, c, tv, rv;
         bs2.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(ref, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
         vp_engine_evaluate(ref, cfg);
         if (ref.vwap != hist[i]) mismatch++;
      }
      CHECK_EQ_I(mismatch, 0);
      CHECK(committed.vwap == ref.vwap);

      // And the ring buffer must survive the clone when it is in use.
      cfg.zWindow = 64; cfg.sigmaMode = VP_SIGMA_WINDOW;
      VpEngine ringA; ringA.Init(cfg);
      BarStream bs3; bs3.Init(1.2, 606ULL, 1750000000LL, 60);
      for (int i = 0; i < 200; i++)
      {
         double o, h, l, c, tv, rv;
         bs3.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(ringA, cfg, 0, 1000000LL + i, o, h, l, c, tv, rv);
         vp_engine_evaluate(ringA, cfg);
      }
      VpEngine ringB; ringB.Init(cfg);
      vp_engine_clone(ringA, ringB);
      CHECK_EQ_I(ringB.ringCount, ringA.ringCount);
      CHECK_EQ_I(ringB.ringHead, ringA.ringHead);
      int ringDiff = 0;
      for (int i = 0; i < ringA.ringCount; i++)
         if (ringA.ringPrice[i] != ringB.ringPrice[i] || ringA.ringWeight[i] != ringB.ringWeight[i]) ringDiff++;
      CHECK_EQ_I(ringDiff, 0);
      CHECK_REL(ringB.sigma, ringA.sigma, 1e-15);
      vp_engine_evaluate(ringB, cfg);
      CHECK_REL(ringB.sigma, ringA.sigma, 1e-15);
      cfg.zWindow = 0; cfg.sigmaMode = VP_SIGMA_SESSION;
   }

   //==================================================================
   vp_suite("convergence");
   {
      VpEngine e; e.Init(cfg);
      for (int i = 0; i < 500; i++)
         push_bar(e, cfg, 0, 1000000LL + i, 1.23456, 1.23456, 1.23456, 1.23456, 10, 0);
      vp_engine_evaluate(e, cfg);
      CHECK_REL(e.vwap, 1.23456, 1e-15);
      CHECK_NEAR(e.sigmaObs, 0.0, 1e-15);
      CHECK_NEAR(e.sigma, 0.0, 1e-15);      // ATR is 0 too, so no phantom band
      CHECK_NEAR(e.z, 0.0, 1e-15);
      CHECK_NEAR(e.signal, 0.0, 1e-15);

      // Feeding more bars at a new level moves the anchor smoothly.
      double prev = e.vwap;
      int monotone = 0;
      for (int i = 0; i < 50; i++)
      {
         push_bar(e, cfg, 0, 2000000LL + i, 1.30, 1.30, 1.30, 1.30, 10, 0);
         vp_engine_evaluate(e, cfg);
         if (e.vwap >= prev) monotone++;
         prev = e.vwap;
      }
      CHECK_EQ_I(monotone, 50);
      CHECK(e.vwap > 1.23456 && e.vwap < 1.30);
   }

   //==================================================================
   vp_suite("composite score behaviour");
   {
      // (a) A strong, persistent, low-noise uptrend with a directional
      //     volume tilt: the trend hypothesis should win and the score
      //     should be positive.
      cfg.volumeMode = VP_VOL_BVC;
      cfg.adaptiveSignal = true;
      cfg.minBars = 5;
      VpEngine up; up.Init(cfg);
      double p = 1.10000;
      double scorePos = 0.0; int nPos = 0;
      for (int i = 0; i < 400; i++)
      {
         double o = p, c = p + 0.00006;
         double h = c + 0.000005, l = o - 0.000005;
         push_bar(up, cfg, 0, 1000000LL + i, o, h, l, c, 50 + i, 0);
         vp_engine_evaluate(up, cfg);
         if (i > 100) { scorePos += up.signal; nPos++; }
         p = c;
      }
      double avgUp = scorePos / (double)nPos;
      std::printf("    trending: avg score %+.3f (adx %.1f, r2 %.3f, slopeSigma %.3f)\n",
                  avgUp, up.adx.Value(), up.r2, up.slopeSigma);
      CHECK(up.adx.Value() > 40.0);
      CHECK_MSG(avgUp > 0.3, "trend regime -> positive score");

      // (b) Pure rotation around a flat anchor with the price stretched
      //     above it: the reversion hypothesis should win -> negative.
      VpEngine chop; chop.Init(cfg);
      p = 1.10000;
      double scoreNeg = 0.0; int nNeg = 0;
      for (int i = 0; i < 400; i++)
      {
         double c = (i % 40 < 20) ? 1.10040 : 1.09960;   // flat anchor, oscillation
         double o = p;
         double h = std::max(o, c) + 0.00002, l = std::min(o, c) - 0.00002;
         push_bar(chop, cfg, 0, 1000000LL + i, o, h, l, c, 100, 0);
         vp_engine_evaluate(chop, cfg);
         if (i > 200) { scoreNeg += chop.signal; nNeg++; }
         p = c;
      }
      double avgChop = scoreNeg / (double)nNeg;
      std::printf("    rotation: avg score %+.3f (adx %.1f, r2 %.3f)\n",
                  avgChop, chop.adx.Value(), chop.r2);
      CHECK_MSG(avgChop < 0.0, "rotation regime -> fade the extension");

      // Bounds hold in every regime.
      CHECK(up.signal >= -1.0 && up.signal <= 1.0);
      CHECK(chop.signal >= -1.0 && chop.signal <= 1.0);

      // And a score of exactly 0 before the minimum bar count.
      VpEngine early; early.Init(cfg);
      push_bar(early, cfg, 0, 1000000LL, 1.1, 1.2, 1.0, 1.15, 100, 0);
      vp_engine_evaluate(early, cfg);
      CHECK_NEAR(early.signal, 0.0, 0.0);
      CHECK(!early.ready);

      cfg.adaptiveSignal = true;
      cfg.volumeMode = VP_VOL_AUTO;
      cfg.minBars = 3;
   }

   //==================================================================
   vp_suite("degraded feed: VWAP must degrade, not lie");
   {
      // No volume anywhere: the anchor must still be a sensible average
      // and the flags must report what happened.
      cfg.volumeMode = VP_VOL_AUTO;
      VpEngine e; e.Init(cfg);
      BarStream bs; bs.Init(1.1, 1ULL, 1750000000LL, 60);
      RefVwap ref; ref.Init();
      for (int i = 0; i < 2000; i++)
      {
         double o, h, l, c, tv, rv;
         bs.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(e, cfg, 0, 1000000LL + i, o, h, l, c, 0.0, 0.0);
         vp_engine_evaluate(e, cfg);
         ref.Push((long double)std::fabs(h - l), (long double)((h + l + c) / 3.0));
      }
      std::printf("    tickUsable %d constant %d realUsable %d\n",
                  (int)e.vol.tickUsable, (int)e.vol.tickConstant, (int)e.vol.realUsable);
      CHECK(!e.vol.tickUsable);
      CHECK_FINITE(e.vwap);
      CHECK(e.sigma > 0.0);
      // Falls back to the volatility clock: weights proportional to range.
      CHECK_REL(e.vwap, ref.Vwap(), 1e-12);

      // Constant tick volume feed: the flag fires and AUTO stops trusting it.
      VpEngine k; k.Init(cfg);
      BarStream bs2; bs2.Init(1.1, 1ULL, 1750000000LL, 60);
      for (int i = 0; i < 500; i++)
      {
         double o, h, l, c, tv, rv;
         bs2.Next(0.00007, o, h, l, c, tv, rv);
         push_bar(k, cfg, 0, 1000000LL + i, o, h, l, c, 250.0, 0.0);
         vp_engine_evaluate(k, cfg);
      }
      CHECK(k.vol.tickConstant);
      CHECK_FINITE(k.vwap);
      CHECK(k.sigma > 0.0);

      // Real volume feed: AUTO must switch to it unconditionally.
      VpEngine r; r.Init(cfg);
      BarStream bs3; bs3.Init(1.1, 1ULL, 1750000000LL, 60);
      RefVwap ref3; ref3.Init();
      for (int i = 0; i < 1000; i++)
      {
         double o, h, l, c, tv, rv;
         bs3.Next(0.00007, o, h, l, c, tv, rv);
         rv = 1000.0 + std::fabs(o - c) * 1e8;
         push_bar(r, cfg, 0, 1000000LL + i, o, h, l, c, 0.0, rv);
         vp_engine_evaluate(r, cfg);
         ref3.Push((long double)rv, (long double)((h + l + c) / 3.0));
      }
      CHECK(r.vol.realUsable);
      CHECK_REL(r.vwap, ref3.Vwap(), 1e-13);
   }

   //==================================================================
   vp_suite("BVC weighting uses the tick-rule price");
   {
      // With the tick rule enabled the anchor must sit above the typical
      // price anchor when the tape is persistently bought, and below it
      // when persistently sold - that is the whole point of the mode.
      cfg.volumeMode = VP_VOL_TICK;
      VpEngine typical; typical.Init(cfg);
      cfg.volumeMode = VP_VOL_BVC;
      VpEngine bvcBuy; bvcBuy.Init(cfg);
      VpEngine bvcSell; bvcSell.Init(cfg);
      cfg.volumeMode = VP_VOL_TICK;

      double p = 1.10000;
      for (int i = 0; i < 500; i++)
      {
         // bars that close on their high => buying pressure
         double o = p, c = p + 0.00010;
         double h = c, l = o;
         push_bar(typical, cfg, 0, 1000000LL + i, o, h, l, c, 100, 0);
         cfg.volumeMode = VP_VOL_BVC;
         push_bar(bvcBuy, cfg, 0, 1000000LL + i, o, h, l, c, 100, 0);
         // bars that close on their low => selling pressure
         double o2 = p, c2 = p + 0.00010;
         push_bar(bvcSell, cfg, 0, 1000000LL + i, o2, c2, o2, o2, 100, 0);
         cfg.volumeMode = VP_VOL_TICK;
         p = c;
      }
      vp_engine_evaluate(typical, cfg);
      cfg.volumeMode = VP_VOL_BVC;
      vp_engine_evaluate(bvcBuy, cfg);
      vp_engine_evaluate(bvcSell, cfg);
      std::printf("    typical %.6f | bvc(buy) %.6f | bvc(sell) %.6f\n",
                  typical.vwap, bvcBuy.vwap, bvcSell.vwap);
      CHECK(bvcBuy.vwap > typical.vwap);
      CHECK(bvcSell.vwap < typical.vwap);
      CHECK(bvcBuy.deltaTilt > 0.5);
      CHECK(bvcSell.deltaTilt < -0.5);
      cfg.volumeMode = VP_VOL_AUTO;
   }

   return vp_report("test_engine");
}
