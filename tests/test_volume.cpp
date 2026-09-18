//+------------------------------------------------------------------+
//| test_volume.cpp - the volume integrity layer                     |
//|                                                                  |
//|  These tests exist because "volume" is the part of a VWAP that     |
//|  every public implementation gets wrong on real MT4 feeds, and      |
//|  because a wrong weight is invisible on the chart - it just moves   |
//|  the line quietly.  Each property below is a statement about what   |
//|  the repair layer must guarantee.                                   |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_CPP_TEST
#define VWAPPRO_CPP_TEST
#endif
#include "VpCompat.mqh"
#include "VpMath.mqh"
#include "VpVolume.mqh"
#include "vp_test.h"

int main()
{
   std::printf("VWAP Pro - volume tests\n");
   VpRng rng; rng.Seed(987654321ULL); rng.InitGauss();

   vp_suite("feed probe");
   {
      // A normal feed: variable tick volume.
      VpVolumeProbe p1; p1.Reset();
      for (int i = 0; i < 200; i++) p1.Push(100 + (i % 37), 0);
      CHECK(p1.tickUsable);
      CHECK(!p1.tickConstant);
      CHECK(!p1.realUsable);

      // A broker that ships a constant tick volume - very common on
      // some CFD feeds, and the reason "VWAP looks like a straight line".
      VpVolumeProbe p2; p2.Reset();
      for (int i = 0; i < 200; i++) p2.Push(17, 0);
      CHECK(p2.tickConstant);
      CHECK(p2.tickUsable);          // usable, but flagged as uninformative

      // A feed with zero volume entirely.
      VpVolumeProbe p3; p3.Reset();
      for (int i = 0; i < 200; i++) p3.Push(0, 0);
      CHECK(!p3.tickUsable);
      CHECK(!p3.realUsable);

      // A feed with real volume (indices, futures, some CFDs).
      VpVolumeProbe p4; p4.Reset();
      for (int i = 0; i < 200; i++) p4.Push(0, 5000 + i * 3);
      CHECK(!p4.tickUsable);
      CHECK(p4.realUsable);

      // Mixed: bad values must not poison the flags permanently.
      VpVolumeProbe p5; p5.Reset();
      for (int i = 0; i < 200; i++) p5.Push((i == 5) ? -1.0 : 42.0 + i, 0);
      CHECK(!p5.tickUsable);
   }

   vp_suite("tick-rule buy fraction");
   {
      // Closing on the high is buying, on the low is selling, flat is neutral.
      double fUp   = vp_buy_fraction(1.0, 1.0010, 0.9990, 0.0000 + 1.0010, 1.0);
      double fDn   = vp_buy_fraction(1.0, 1.0010, 0.9990, 0.9990, 1.0);
      double fFlat = vp_buy_fraction(1.0, 1.0000, 1.0000, 1.0000, 1.0);
      double fMid  = vp_buy_fraction(1.0, 1.0010, 0.9990, 1.0000, 1.0);
      CHECK(fUp > 0.5); CHECK(fDn < 0.5);
      CHECK_NEAR(fFlat, 0.5, 1e-12);
      CHECK(fMid >= 0.45 && fMid <= 0.55);
      CHECK(fUp <= 0.98 && fDn >= 0.02);          // never fully one-sided

      // Monotone in the close position, and always inside (0,1) - the
      // property that keeps the flow tilt bounded.
      double prev = -1.0; int violations = 0; int outOfRange = 0;
      for (int i = 0; i <= 100; i++)
      {
         double h = 1.0020, l = 0.9980;
         double c = l + (h - l) * (double)i / 100.0;
         double f = vp_buy_fraction(1.0000, h, l, c, 1.0);
         if (f < prev - 1e-12) violations++;
         prev = f;
         if (f <= 0.0 || f >= 1.0) outOfRange++;
      }
      CHECK_EQ_I(violations, 0);
      CHECK_EQ_I(outOfRange, 0);

      // k = 0 means "no opinion" -> exactly 50/50.
      CHECK_NEAR(vp_buy_fraction(1.0, 1.002, 0.998, 1.002, 0.0), 0.5, 1e-12);

      // Fuzz: never NaN, never outside [0,1].
      int bad = 0;
      for (int i = 0; i < 20000; i++)
      {
         double o = 1.0 + rng.Gaussian() * 0.01;
         double h = o + std::fabs(rng.Gaussian()) * 0.005;
         double l = o - std::fabs(rng.Gaussian()) * 0.005;
         double c = l + (h - l) * rng.Uniform();
         double f = vp_buy_fraction(o, h, l, c, 1.0);
         if (!std::isfinite(f) || f < 0.0 || f > 1.0) bad++;
      }
      CHECK_EQ_I(bad, 0);

      // Inverted / zero-range bars (garbage ticks, or a flat bar on a
      // low-liquidity symbol) must not produce NaN or an extreme split.
      CHECK_FINITE(vp_buy_fraction(1.0, 0.9, 1.1, 1.0, 1.0));
      CHECK_NEAR(vp_buy_fraction(1.0, 1.0, 1.0, 1.0, 1.0), 0.5, 1e-12);
   }

   vp_suite("weighting modes");
   {
      double o = 1.10000, h = 1.10050, l = 1.09950, c = 1.10020;
      double tv = 250, rv = 0;
      double rs = 1e-4;

      // Every mode must return a strictly positive, finite weight for a
      // normal bar...
      int bad = 0;
      for (int mode = 0; mode <= 7; mode++)
      {
         double w = vp_bar_weight(mode, o, h, l, c, tv, rv, rs, true, false, false);
         if (!(w > 0.0) || !std::isfinite(w)) { bad++; std::printf("    mode %d -> %.17g\n", mode, w); }
      }
      CHECK_EQ_I(bad, 0);

      // ...and for pathological bars too.
      bad = 0;
      for (int mode = 0; mode <= 7; mode++)
      {
         // zero range, zero volume, NaN volume, inverted range, huge price
         double ws[5];
         ws[0] = vp_bar_weight(mode, o, o, o, o, 0, 0, rs, false, false, false);
         ws[1] = vp_bar_weight(mode, o, h, l, c, 0, 0, rs, false, true, false);
         ws[2] = vp_bar_weight(mode, o, h, l, c, 0.0/0.0, 0, rs, true, false, false);
         ws[3] = vp_bar_weight(mode, o, l, h, c, tv, rv, rs, true, false, false);
         ws[4] = vp_bar_weight(mode, 1e9, 1e9 + 100, 1e9 - 100, 1e9, tv, rv, rs, true, false, false);
         for (int k = 0; k < 5; k++)
            if (!(ws[k] > 0.0) || !std::isfinite(ws[k])) { bad++; }
      }
      CHECK_EQ_I(bad, 0);

      // AUTO priority: real volume wins when present.
      double wAutoReal = vp_bar_weight(VP_VOL_AUTO, o, h, l, c, 250, 9000, rs, false, false, true);
      double wReal     = vp_bar_weight(VP_VOL_REAL, o, h, l, c, 250, 9000, rs, false, false, true);
      CHECK_NEAR(wAutoReal, wReal, 0.0);

      // ...then tick volume...
      double wAutoTick = vp_bar_weight(VP_VOL_AUTO, o, h, l, c, 250, 0, rs, true, false, false);
      double wTick     = vp_bar_weight(VP_VOL_TICK, o, h, l, c, 250, 0, rs, true, false, false);
      CHECK_NEAR(wAutoTick, wTick, 0.0);

      // ...then the volatility clock (never zero, never a divide by zero).
      double wFallback = vp_bar_weight(VP_VOL_AUTO, o, h, l, c, 0, 0, rs, false, false, false);
      CHECK(wFallback > 0.0);

      // A constant feed must not be trusted as volume.
      double wConst = vp_bar_weight(VP_VOL_AUTO, o, h, l, c, 17, 0, rs, true, true, false);
      double wPure  = vp_bar_weight(VP_VOL_TICK, o, h, l, c, 17, 0, rs, true, true, false);
      CHECK(wConst > 0.0);
      CHECK(wPure > 0.0);   // explicitly requested -> honoured, but flagged upstream
   }

   vp_suite("effective price");
   {
      int bad = 0;
      for (int i = 0; i < 20000; i++)
      {
         double o = 1.1 + rng.Gaussian() * 0.01;
         double h = o + std::fabs(rng.Gaussian()) * 0.004 + 1e-9;
         double l = o - std::fabs(rng.Gaussian()) * 0.004 - 1e-9;
         if (l > h) { double tmp = l; l = h; h = tmp; }
         double c = l + (h - l) * rng.Uniform();
         double f = vp_buy_fraction(o, h, l, c, 1.0);
         double p = vp_effective_price(o, h, l, c, f);
         if (!std::isfinite(p)) bad++;
         // The proxy price must stay inside the bar (with a small tolerance
         // for the typical price blend).
         if (p < l - 1e-12 || p > h + 1e-12) bad++;
      }
      CHECK_EQ_I(bad, 0);

      // Directional sanity: a bar dominated by buying prices higher than
      // one dominated by selling, all else equal.
      double pBuy  = vp_effective_price(1.0, 1.002, 0.998, 1.0018, 0.9);
      double pSell = vp_effective_price(1.0, 1.002, 0.998, 0.9982, 0.1);
      CHECK(pBuy > pSell);
   }

   return vp_report("test_volume");
}
