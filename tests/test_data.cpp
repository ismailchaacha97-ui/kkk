//+------------------------------------------------------------------+
//| test_data.cpp - the battery that runs on *market data*           |
//|                                                                  |
//|  Everything here reads tests/fixtures/*.csv (the deterministic      |
//|  synthetic M1 stream that ships with the repository, plus anything   |
//|  the user drops in - a fetch_data.py download or an MT4 export).    |
//|                                                                  |
//|  It answers the three questions that decide whether the indicator   |
//|  is usable rather than merely correct:                              |
//|                                                                  |
//|   1. structural: no NaN, no inverted band, no state leak, bit-exact  |
//|      reproducibility, and the anchor is the true textbook VWAP;      |
//|   2. statistical: are the bands calibrated?  (A band that claims to  |
//|      be a 1 sigma band but is exceeded 20% of the time is worse than |
//|      no band, because it is a lie a trader will size positions on.)  |
//|   3. degraded-feed: what happens when the volume column is missing   |
//|      or useless, which is the normal case on retail MT4 feeds.       |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_CPP_TEST
#define VWAPPRO_CPP_TEST
#endif
#include "VpCompat.mqh"
#include "VpMath.mqh"
#include "VpEngine.mqh"
#include "VpAnchor.mqh"
#include "vp_test.h"
#include "vp_fixture.h"

#include <dirent.h>
#include <string>
#include <vector>

struct Fixture
{
   std::string name;
   std::vector<VpRec> bars;
};

static void list_fixtures(std::vector<Fixture> &out)
{
   out.clear();
   DIR *d = opendir("tests/fixtures");
   if (!d) d = opendir("../tests/fixtures");
   if (!d) return;
   struct dirent *e;
   while ((e = readdir(d)) != NULL)
   {
      std::string nm = e->d_name;
      if (nm.size() < 4) continue;
      if (nm.substr(nm.size() - 4) != ".csv") continue;
      Fixture f;
      f.name = nm;
      std::string path = "tests/fixtures/" + nm;
      if (vp_load_csv(path.c_str(), f.bars, 0) <= 0)
         vp_load_csv(("../tests/fixtures/" + nm).c_str(), f.bars, 0);
      if (!f.bars.empty()) out.push_back(f);
   }
   closedir(d);
}

//| Run the engine across a whole fixture with daily anchors.
struct RunStats
{
   int    bars;
   int    nonFinite;
   int    inverted;
   int    rejected;
   double vwapMaxRelErr;
   // calibration
   double fracZ1, fracZ2, fracZ3;
   double meanAbsZ;
};

static void run_fixture(const std::vector<VpRec> &bars, VpEngineConfig &cfg,
                        bool zeroVolume, RunStats &st)
{
   st.bars = 0; st.nonFinite = 0; st.inverted = 0; st.rejected = 0;
   st.vwapMaxRelErr = 0.0;
   st.fracZ1 = st.fracZ2 = st.fracZ3 = 0.0; st.meanAbsZ = 0.0;

   VpEngine e; e.Init(cfg);
   int n1 = 0, n2 = 0, n3 = 0, nz = 0;
   double sumAbsZ = 0.0;

   for (size_t i = 0; i < bars.size(); i++)
   {
      VpBar b;
      b.time = (vp_int64)bars[i].t;
      b.open = bars[i].o; b.high = bars[i].h; b.low = bars[i].l; b.close = bars[i].c;
      b.tickVol = zeroVolume ? 0.0 : bars[i].tv;
      b.realVol = zeroVolume ? 0.0 : bars[i].rv;

      VpDateTime dt; vp_break_time(b.time, dt);
      vp_int64 anchor = vp_anchor_key(cfg, b.time);
      vp_engine_push(e, cfg, anchor, b.time, b);
      vp_engine_evaluate(e, cfg);
      st.bars++;

      if (!std::isfinite(e.vwap) || !std::isfinite(e.sigma) || !std::isfinite(e.z) ||
          !std::isfinite(e.up1) || !std::isfinite(e.dn1) ||
          !std::isfinite(e.up2) || !std::isfinite(e.dn2) ||
          !std::isfinite(e.up3) || !std::isfinite(e.dn3) ||
          !std::isfinite(e.signal) || !std::isfinite(e.tStat))
         st.nonFinite++;
      if (!(e.dn3 <= e.dn2 && e.dn2 <= e.dn1 && e.dn1 <= e.vwap &&
            e.vwap <= e.up1 && e.up1 <= e.up2 && e.up2 <= e.up3))
         st.inverted++;
      if (e.barsInAnchor >= cfg.minBars && e.sigma > 0.0)
      {
         double az = std::fabs(e.z);
         sumAbsZ += az;
         nz++;
         if (az > 1.0) n1++;
         if (az > 2.0) n2++;
         if (az > 3.0) n3++;
      }
   }
   st.rejected = e.feedWarnings;
   if (nz > 0)
   {
      st.fracZ1 = (double)n1 / nz;
      st.fracZ2 = (double)n2 / nz;
      st.fracZ3 = (double)n3 / nz;
      st.meanAbsZ = sumAbsZ / nz;
   }
}

//| The naive reference implementation: textbook VWAP with a *running*
//| unshrunk session sigma accumulated the textbook way.  This is what
//| almost every published VWAP band does.
static void run_naive(const std::vector<VpRec> &bars, RunStats &st)
{
   st.bars = 0; st.nonFinite = 0; st.inverted = 0; st.rejected = 0;
   st.fracZ1 = st.fracZ2 = st.fracZ3 = 0.0; st.meanAbsZ = 0.0;

   double sumW = 0, sumWP = 0, sumWP2 = 0;
   long long anchorDay = -1;
   int n1 = 0, n2 = 0, n3 = 0, nz = 0;
   double sumAbsZ = 0.0;
   for (size_t i = 0; i < bars.size(); i++)
   {
      VpBar b;
      b.time = (vp_int64)bars[i].t;
      b.open = bars[i].o; b.high = bars[i].h; b.low = bars[i].l; b.close = bars[i].c;
      b.tickVol = bars[i].tv; b.realVol = bars[i].rv;

      VpDateTime dt; vp_break_time(b.time, dt);
      if (dt.dayIndex != anchorDay)
      {
         anchorDay = dt.dayIndex;
         sumW = 0; sumWP = 0; sumWP2 = 0;
      }
      double w = b.tickVol > 0 ? b.tickVol : 1.0;
      double p = (b.high + b.low + b.close) / 3.0;
      sumW += w; sumWP += w * p; sumWP2 += w * p * p;
      st.bars++;

      double vwap = sumWP / sumW;
      double var = sumWP2 / sumW - vwap * vwap;
      if (var < 0.0) var = 0.0;
      double sd = std::sqrt(var);
      double z = (sd > 0.0) ? (b.close - vwap) / sd : 0.0;
      if (!std::isfinite(z)) { st.nonFinite++; z = 0.0; }
      if (std::fabs(z) > 1e12) z = 0.0;         // the naive form really does this

      double az = std::fabs(z);
      sumAbsZ += az; nz++;
      if (az > 1.0) n1++;
      if (az > 2.0) n2++;
      if (az > 3.0) n3++;
   }
   if (nz > 0)
   {
      st.fracZ1 = (double)n1 / nz;
      st.fracZ2 = (double)n2 / nz;
      st.fracZ3 = (double)n3 / nz;
      st.meanAbsZ = sumAbsZ / nz;
   }
}

int main()
{
   std::printf("VWAP Pro - market data battery\n");

   std::vector<Fixture> fixtures;
   list_fixtures(fixtures);
   if (fixtures.empty())
   {
      std::printf("\n  No fixtures found in tests/fixtures/*.csv\n");
      std::printf("  Generate one:  python3 tools/make_fixture.py --out tests/fixtures/synth_m1_eurusd.csv\n");
      return 1;
   }

   VpEngineConfig cfg;
   cfg.Init();
   cfg.anchorMode = VP_ANCHOR_SERVERDAY;
   cfg.volumeMode = VP_VOL_AUTO;
   cfg.sigmaMode  = VP_SIGMA_SESSION;
   cfg.adaptSigma = true;

   for (size_t f = 0; f < fixtures.size(); f++)
   {
      char label[256];
      std::snprintf(label, sizeof(label), "%s (%d bars)", fixtures[f].name.c_str(),
                    (int)fixtures[f].bars.size());
      vp_suite(label);
      const std::vector<VpRec> &bars = fixtures[f].bars;

      //--------------------------------------------------------------
      RunStats st;
      run_fixture(bars, cfg, false, st);
      std::printf("    bars %d  rejected-as-unusable %d\n", st.bars, st.rejected);
      std::printf("    z distribution: mean|z| %.3f  P(|z|>1) %.3f  P(|z|>2) %.3f  P(|z|>3) %.4f\n",
                  st.meanAbsZ, st.fracZ1, st.fracZ2, st.fracZ3);
      CHECK_MSG(st.nonFinite == 0, "no non-finite value ever reached a buffer");
      CHECK_MSG(st.inverted == 0, "bands never crossed");
      CHECK(st.bars == (int)bars.size());
      CHECK_MSG(st.rejected == 0, "the fixture contains no unusable bar");

      //--------------------------------------------------------------
      // Calibration.  For a scale free z score the Gaussian reference is
      // P(|z|>1)=31.7%, P(|z|>2)=4.55%, P(|z|>3)=0.27%.  Market data is
      // not Gaussian, so the absolute numbers will not match exactly -
      // but a *correctly estimated* dispersion must be in the right
      // neighbourhood, while an unshrunk running sigma produces garbage
      // in the first bars of every session (sigma ~ 0 -> |z| huge).
      RunStats naive;
      run_naive(bars, naive);
      std::printf("    naive VWAP  : mean|z| %.3f  P(|z|>1) %.3f  P(|z|>2) %.3f  P(|z|>3) %.4f  nan %d\n",
                  naive.meanAbsZ, naive.fracZ1, naive.fracZ2, naive.fracZ3, naive.nonFinite);

      double errPro   = std::fabs(st.fracZ3 - 0.0027) + std::fabs(st.fracZ2 - 0.0455);
      double errNaive = std::fabs(naive.fracZ3 - 0.0027) + std::fabs(naive.fracZ2 - 0.0455);
      std::printf("    calibration error (|P - Gaussian|, 2+3 sigma): pro %.4f vs naive %.4f\n",
                  errPro, errNaive);
      CHECK_MSG(st.fracZ2 < 0.35, "2 sigma is not being hit like a 1 sigma band");
      CHECK_MSG(st.fracZ3 < 0.20, "3 sigma is not being hit like a 2 sigma band");
      CHECK_MSG(st.meanAbsZ < 1.6, "z stays in a plausible range");
      CHECK_MSG(errPro <= errNaive + 1e-9, "shrinkage beats the unshrunk running sigma");
      CHECK_MSG(naive.fracZ3 > st.fracZ3, "the naive estimator is measurably worse at 3 sigma");

      //--------------------------------------------------------------
      // Reproducibility: the same bars must give bit-identical output.
      RunStats again;
      run_fixture(bars, cfg, false, again);
      CHECK_MSG(again.fracZ3 == st.fracZ3 && again.meanAbsZ == st.meanAbsZ,
                "deterministic across runs");

      //--------------------------------------------------------------
      // The anchor must be the textbook VWAP when the weighting mode is
      // the textbook one.
      {
         VpEngineConfig c2 = cfg;
         c2.volumeMode = VP_VOL_TICK;
         c2.adaptSigma = false;
         VpEngine e; e.Init(c2);
         double worst = 0.0;
         double sumW = 0, sumWP = 0;
         long long anchorDay = -1;
         for (size_t i = 0; i < bars.size(); i++)
         {
            VpBar b;
            b.time = (vp_int64)bars[i].t;
            b.open = bars[i].o; b.high = bars[i].h; b.low = bars[i].l; b.close = bars[i].c;
            b.tickVol = bars[i].tv; b.realVol = bars[i].rv;
            VpDateTime dt; vp_break_time(b.time, dt);
            if (dt.dayIndex != anchorDay)
            {
               anchorDay = dt.dayIndex;
               sumW = 0; sumWP = 0;
            }
            vp_engine_push(e, c2, vp_anchor_key(c2, b.time), b.time, b);
            vp_engine_evaluate(e, c2);
            double p = (b.high + b.low + b.close) / 3.0;
            sumW += b.tickVol; sumWP += b.tickVol * p;
            double ref = sumWP / sumW;
            double rel = std::fabs(e.vwap - ref) / ref;
            if (rel > worst) worst = rel;
         }
         std::printf("    textbook reproduction: worst relative error %.3g over %d bars\n",
                     worst, (int)bars.size());
         CHECK_MSG(worst < 1e-12, "the anchor is the real VWAP on real bars");
      }

      //--------------------------------------------------------------
      // Degraded feed: strip the volume column entirely.  The anchor
      // must degrade to the volatility clock (documented behaviour) and
      // stay finite and close to the priced anchor - never collapse.
      {
         RunStats noVol;
         run_fixture(bars, cfg, true, noVol);
         std::printf("    volume stripped: non-finite %d, P(|z|>2) %.3f, mean|z| %.3f\n",
                     noVol.nonFinite, noVol.fracZ2, noVol.meanAbsZ);
         CHECK_EQ_I(noVol.nonFinite, 0);
         CHECK_EQ_I(noVol.inverted, 0);
         CHECK_MSG(noVol.fracZ2 < 0.5, "survives a feed with no volume at all");

         // The two anchors must still agree closely: volume weighting
         // refines a VWAP, it does not redefine it.
         VpEngineConfig c3 = cfg; c3.volumeMode = VP_VOL_RANGE;
         VpEngine a, b2;
         a.Init(cfg); b2.Init(c3);
         double maxDiff = 0.0, scale = 0.0;
         for (size_t i = 0; i < bars.size(); i += 7)
         {
            VpBar b;
            b.time = (vp_int64)bars[i].t;
            b.open = bars[i].o; b.high = bars[i].h; b.low = bars[i].l; b.close = bars[i].c;
            b.tickVol = bars[i].tv; b.realVol = bars[i].rv;
            vp_engine_push(a, cfg, vp_anchor_key(cfg, b.time), b.time, b);
            vp_engine_evaluate(a, cfg);
            vp_engine_push(b2, c3, vp_anchor_key(c3, b.time), b.time, b);
            vp_engine_evaluate(b2, c3);
            double diff = std::fabs(a.vwap - b2.vwap);
            if (diff > maxDiff) maxDiff = diff;
            scale = std::max(scale, a.vwap);
         }
         std::printf("    tick-volume anchor vs range-clock anchor: max gap %.6g (%.3f%% of price)\n",
                     maxDiff, 100.0 * maxDiff / scale);
         CHECK_MSG(maxDiff / scale < 0.002, "the two weighting families agree closely");
      }
   }

   std::printf("\n(Every number above comes from the same headers MT4 compiles.)\n");
   return vp_report("test_data");
}
