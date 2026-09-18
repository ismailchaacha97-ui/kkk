//+------------------------------------------------------------------+
//| vp_test.h - a 120 line test framework, deliberately.             |
//|                                                                  |
//|  Why not a real framework?  Because this repository must build    |
//|  with nothing but a C++ compiler - no package manager, no network |
//|  - so that "run the tests" is a one line command on any machine,   |
//|  including the CI box of somebody who just wants to check the      |
//|  numbers before putting the indicator on a live account.           |
//+------------------------------------------------------------------+
#ifndef VP_TEST_H
#define VP_TEST_H

#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>
#include <algorithm>
#include <limits>

static int g_vpChecks = 0;
static int g_vpFails  = 0;
static int g_vpSuiteFails = 0;
static std::string g_vpSuite = "(none)";

inline void vp_suite(const char *name)
{
   g_vpSuite = name;
   std::printf("\n--- %s ---\n", name);
}

inline void vp_fail(const char *what, const char *file, int line, const std::string &detail)
{
   g_vpFails++; g_vpSuiteFails++;
   std::printf("  FAIL %s:%d [%s] %s\n", file, line, g_vpSuite.c_str(), what);
   if (!detail.empty()) std::printf("        %s\n", detail.c_str());
}

inline void vp_pass()
{
   g_vpChecks++;
}

#define CHECK(cond) do { \
   if (cond) { vp_pass(); } \
   else { vp_fail(#cond, __FILE__, __LINE__, std::string()); } \
} while(0)

#define CHECK_MSG(cond, msg) do { \
   if (cond) { vp_pass(); } \
   else { vp_fail(#cond, __FILE__, __LINE__, std::string(msg)); } \
} while(0)

inline std::string vp_fmt_i(long long a, long long b)
{
   char buf[128];
   std::snprintf(buf, sizeof(buf), "got %lld expected %lld", a, b);
   return std::string(buf);
}

#define CHECK_EQ_I(a, b) do { \
   long long _a = (long long)(a), _b = (long long)(b); \
   if (_a == _b) { vp_pass(); } \
   else { vp_fail(#a " == " #b, __FILE__, __LINE__, vp_fmt_i(_a, _b)); } \
} while(0)

inline std::string vp_fmt(double a, double b)
{
   char buf[256];
   std::snprintf(buf, sizeof(buf), "got %.17g expected %.17g (diff %.3g)",
                 a, b, a - b);
   return std::string(buf);
}

#define CHECK_NEAR(a, b, tol) do { \
   double _a = (a), _b = (b), _t = (tol); \
   if (std::fabs(_a - _b) <= _t) { vp_pass(); } \
   else { vp_fail(#a " ~= " #b, __FILE__, __LINE__, vp_fmt(_a, _b)); } \
} while(0)

inline std::string vp_fmt_rel(double a, double b)
{
   double denom = std::fabs(b) > 1e-300 ? std::fabs(b) : 1.0;
   char buf[256];
   std::snprintf(buf, sizeof(buf), "got %.17g expected %.17g (rel %.3g)",
                 a, b, std::fabs(a - b) / denom);
   return std::string(buf);
}

#define CHECK_REL(a, b, reltol) do { \
   double _a = (a), _b = (b); \
   double _den = std::fabs(_b) > 1e-300 ? std::fabs(_b) : 1.0; \
   if (std::fabs(_a - _b) / _den <= (reltol)) { vp_pass(); } \
   else { vp_fail(#a " ~= " #b " (relative)", __FILE__, __LINE__, vp_fmt_rel(_a, _b)); } \
} while(0)

#define CHECK_FINITE(x) do { \
   double _x = (x); \
   if (std::isfinite(_x)) { vp_pass(); } \
   else { vp_fail(#x " is finite", __FILE__, __LINE__, vp_fmt(_x, 0.0)); } \
} while(0)

inline int vp_report(const char *binary)
{
   std::printf("\n==================================================\n");
   std::printf("%s: %d checks, %d failures\n", binary, g_vpChecks, g_vpFails);
   std::printf("==================================================\n");
   return g_vpFails == 0 ? 0 : 1;
}

//+------------------------------------------------------------------+
//| A tiny deterministic RNG so every "random" test is reproducible.  |
//| xorshift64*, seeded explicitly; no dependency on the C library's  |
//| implementation specific rand().                                    |
//+------------------------------------------------------------------+
struct VpRng
{
   unsigned long long s;
   void Seed(unsigned long long v) { s = v ? v : 88172645463325252ULL; }
   unsigned long long Next()
   {
      s ^= s >> 12; s ^= s << 25; s ^= s >> 27;
      return s * 2685821657736338717ULL;
   }
   // Uniform in [0,1)
   double Uniform() { return (double)(Next() >> 11) * (1.0 / 9007199254740992.0); }
   // Standard normal (Box-Muller, cached)
   double gaussSpare; bool hasSpare;
   void InitGauss() { gaussSpare = 0.0; hasSpare = false; }
   double Gaussian()
   {
      if (hasSpare) { hasSpare = false; return gaussSpare; }
      double u = Uniform(); if (u < 1e-12) u = 1e-12;
      double v = Uniform();
      double r = std::sqrt(-2.0 * std::log(u));
      gaussSpare = r * std::sin(2.0 * 3.14159265358979323846 * v);
      hasSpare = true;
      return r * std::cos(2.0 * 3.14159265358979323846 * v);
   }
   // Student-t style fat tail: sum of a few gaussians / sqrt(chi2) proxy.
   double FatTail(double df)
   {
      double g = Gaussian();
      double c = 0.0;
      for (int i = 0; i < (int)df; i++) { double z = Gaussian(); c += z * z; }
      if (c <= 0.0) c = 1e-9;
      return g / std::sqrt(c / df);
   }
};

#endif // VP_TEST_H
