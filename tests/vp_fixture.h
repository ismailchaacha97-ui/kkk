//+------------------------------------------------------------------+
//| vp_fixture.h - market data loader + synthetic bar factory.        |
//|                                                                  |
//|  Fixture files are plain text, one bar per line:                   |
//|      unix_seconds,open,high,low,close,tick_volume,real_volume      |
//|  which is exactly what tools/make_fixture.py writes and what        |
//|  tools/fetch_data.py downloads (real data) and what                |
//|  tools/mt4_export_to_fixture.py converts from an MT4 history        |
//|  export.  Nothing about the tests is tied to a particular market.   |
//+------------------------------------------------------------------+
#ifndef VP_FIXTURE_H
#define VP_FIXTURE_H

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

struct VpRec
{
   long long t;
   double o, h, l, c;
   double tv;   // tick volume
   double rv;   // real volume
};

// Very small, allocation-light CSV reader.  Returns the number of bars
// loaded (0 when the file is missing - callers decide whether that is
// fatal).
static int vp_load_csv(const char *path, std::vector<VpRec> &out, int maxRows)
{
   out.clear();
   FILE *f = std::fopen(path, "rb");
   if (!f) return 0;
   char line[512];
   int n = 0;
   while (std::fgets(line, sizeof(line), f))
   {
      if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') continue;
      // Skip an optional header row.
      if ((line[0] < '0' || line[0] > '9') && line[0] != '-') continue;
      VpRec r;
      double t = 0.0;
      int got = std::sscanf(line, "%lf,%lf,%lf,%lf,%lf,%lf,%lf",
                            &t, &r.o, &r.h, &r.l, &r.c, &r.tv, &r.rv);
      if (got < 6) continue;
      if (got < 7) r.rv = 0.0;
      r.t = (long long)t;
      out.push_back(r);
      n++;
      if (maxRows > 0 && n >= maxRows) break;
   }
   std::fclose(f);
   return n;
}

//+------------------------------------------------------------------+
//| A bar factory with a documented data generating process.          |
//|                                                                  |
//|  It is deliberately *not* a random walk with bells on: real FX M1   |
//|  bars have (a) an intraday volatility smile, (b) session gaps,      |
//|  (c) fat tailed innovations, (d) tick counts that are an integer,   |
//|  autocorrelated, volatile function of the bar - never a proxy for   |
//|  size, and (e) a hidden buy/sell pressure that drives the close      |
//|  inside the bar's range.  Tests that care about the tick-rule        |
//|  estimator need (e); tests that care about volume repair need (d).   |
//+------------------------------------------------------------------+
struct VpBarFactory
{
   double price;
   double sigma;         // per bar log return vol at "neutral" hour
   long long t0;
   int    step;          // seconds per bar
   VpRng  rng;
   double pressure;      // AR(1) hidden order flow in [-1,1]
   double tickAutocorr;

   void Init(double startPrice, double perBarSigma, long long startTime, int secondsPerBar, unsigned long long seed)
   {
      price = startPrice;
      sigma = perBarSigma;
      t0 = startTime;
      step = secondsPerBar;
      rng.Seed(seed);
      rng.InitGauss();
      pressure = 0.0;
      tickAutocorr = 0.0;
   }

   // Intraday volatility seasonality for a 24x5 FX week (UTC hours).
   double VolSeason(int hourUtc)
   {
      // Quiet Asia, ramping London, peak at the London/NY overlap, decay
      // into the NY afternoon.
      static const double s[24] = {
         0.62,0.58,0.55,0.55,0.58,0.65,0.78,0.95,1.18,1.32,1.38,1.36,
         1.30,1.42,1.55,1.60,1.50,1.30,1.05,0.92,0.88,0.80,0.74,0.68 };
      return s[((hourUtc % 24) + 24) % 24];
   }

   // Produce one bar.  Returns false when a weekend gap was hit (no bar
   // exists then), in which case the caller should call again.
   bool Next(VpRec &r, bool weekendsOff)
   {
      long long t = t0;
      t0 += step;
      int secOfDay = (int)((t % 86400 + 86400) % 86400);
      int hour = secOfDay / 3600;
      int wday = (int)(((t / 86400) + 4) % 7 + 7) % 7;   // 0 = Sunday
      if (weekendsOff && (wday == 6 || (wday == 0 && hour < 21))) return false;

      double vol = sigma * VolSeason(hour);
      // a few scheduled news minutes per day
      bool news = (hour == 12 && (secOfDay % 3600) / 60 < 4) ||
                  (hour == 14 && (secOfDay % 3600) / 60 < 4);
      if (news) vol *= 3.1;

      // Hidden order flow: persistent, mean reverting, occasionally excited.
      pressure = pressure * 0.86 + 0.14 * rng.Gaussian() * (news ? 2.2 : 1.0) * 0.55;
      if (pressure >  1.0) pressure =  1.0;
      if (pressure < -1.0) pressure = -1.0;

      double ret = vol * rng.FatTail(5.0) * 0.35 + pressure * vol * 0.55;
      double open = price;
      double close = open * std::exp(ret);
      if (close <= 0.0) close = open;

      double wick = vol * open * (0.6 + 1.4 * rng.Uniform()) * (news ? 2.4 : 1.0);
      // Buy pressure pushes the close towards the high of the bar.
      double fbuy = 0.5 + 0.45 * pressure;
      double range = std::fabs(close - open) + wick;
      double high = std::max(open, close) + range * (1.0 - fbuy) * rng.Uniform();
      double low  = std::min(open, close) - range * fbuy * rng.Uniform();
      if (high < open) high = open;
      if (high < close) high = close;
      if (low > open) low = open;
      if (low > close) low = close;

      price = close;

      // Tick counts: integer, autocorrelated, increasing with volatility
      // and with the session, and NOT a measure of traded size.
      double base = 260.0 * VolSeason(hour) * (1.0 + 2.4 * std::fabs(ret) / (vol + 1e-12));
      tickAutocorr = tickAutocorr * 0.72 + base * 0.28;
      double ticks = tickAutocorr * (0.45 + 1.15 * rng.Uniform());
      if (news) ticks *= 2.2;
      ticks = std::floor(ticks) + 1.0;
      if (ticks < 1.0) ticks = 1.0;
      if (ticks > 30000.0) ticks = 30000.0;

      r.t = t; r.o = open; r.h = high; r.l = low; r.c = close;
      r.tv = ticks; r.rv = 0.0;
      return true;
   }
};

#endif // VP_FIXTURE_H
