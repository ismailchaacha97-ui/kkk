//+------------------------------------------------------------------+
//| dump_bars.cpp - run the engine over a fixture and dump every bar  |
//|                                                                  |
//|  Used by tools/crosscheck.py and tools/benchmark.py so that the     |
//|  numbers they analyse come from the *actual* C++ engine (the same   |
//|  headers MT4 compiles) and not from a reimplementation.             |
//|                                                                  |
//|  usage: dump_bars <fixture.csv> [anchorMode] [volumeMode] [sigmaMode]|
//|                    [zWindow] [adaptSigma] [zeroVolume] [quiet]      |
//|                                                                  |
//|  quiet = run the engine but only print the final bar.  Used by      |
//|  tools/benchmark.py to time the *engine* rather than the printf.    |
//|  output: csv on stdout                                             |
//|      time,open,high,low,close,tick_volume,                                   |
//|      vwap,sigma,sigma_obs,sigma_prior,z,slope_pct,t_stat,r2,               |
//|      delta_tilt,skew,kurt,signal,up1,dn1,up2,dn2,up3,dn3,ready             |
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

#include <cstdio>
#include <cstdlib>
#include <cstring>

int main(int argc, char **argv)
{
   if (argc < 2)
   {
      std::fprintf(stderr, "usage: %s <fixture.csv> [anchor] [vol] [sigma] [zwin] [adapt] [zerovol]\n", argv[0]);
      return 2;
   }
   std::vector<VpRec> bars;
   int n = vp_load_csv(argv[1], bars, 0);
   if (n <= 0) { std::fprintf(stderr, "no bars in %s\n", argv[1]); return 2; }

   VpEngineConfig cfg;
   cfg.Init();
   if (argc > 2) cfg.anchorMode = std::atoi(argv[2]);
   if (argc > 3) cfg.volumeMode = std::atoi(argv[3]);
   if (argc > 4) cfg.sigmaMode  = std::atoi(argv[4]);
   if (argc > 5) cfg.zWindow    = std::atoi(argv[5]);
   if (argc > 6) cfg.adaptSigma = (std::atoi(argv[6]) != 0);
   bool zeroVol = (argc > 7) && (std::atoi(argv[7]) != 0);
   bool quiet   = (argc > 8) && (std::atoi(argv[8]) != 0);

   VpEngine e; e.Init(cfg);

   std::printf("time,open,high,low,close,tick_volume,vwap,sigma,sigma_obs,sigma_prior,z,"
               "slope_pct,t_stat,r2,delta_tilt,skew,kurt,signal,up1,dn1,up2,dn2,up3,dn3,ready\n");

   for (int i = 0; i < n; i++)
   {
      VpBar b;
      b.time = (vp_int64)bars[i].t;
      b.open = bars[i].o; b.high = bars[i].h; b.low = bars[i].l; b.close = bars[i].c;
      b.tickVol = zeroVol ? 0.0 : bars[i].tv;
      b.realVol = zeroVol ? 0.0 : bars[i].rv;

      vp_engine_push(e, cfg, vp_anchor_key(cfg, b.time), b.time, b);
      vp_engine_evaluate(e, cfg);

      // 17 significant digits: this dump is used for bit level
      // comparison against an independent implementation, so it must not
      // be the thing that limits the agreement.
      if (quiet && i != n - 1) continue;
      std::printf("%lld,%.17g,%.17g,%.17g,%.17g,%.0f,%.17g,%.17g,%.17g,%.17g,%.17g,"
                  "%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%d\n",
                  (long long)b.time, b.open, b.high, b.low, b.close, b.tickVol,
                  e.vwap, e.sigma, e.sigmaObs, e.sigmaPrior, e.z,
                  e.slopePct, e.tStat, e.r2, e.deltaTilt, e.skew, e.kurt, e.signal,
                  e.up1, e.dn1, e.up2, e.dn2, e.up3, e.dn3, e.ready ? 1 : 0);
   }
   return 0;
}
