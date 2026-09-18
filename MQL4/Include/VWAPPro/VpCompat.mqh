//+------------------------------------------------------------------+
//|                                                     VpCompat.mqh |
//|                              VWAP Pro - portability layer         |
//|                                                                  |
//|  The whole VWAP Pro library is written in the intersection of      |
//|  MQL4 and C++ so that the *exact same source* that runs inside      |
//|  MetaTrader 4 can be compiled and unit-tested on a PC.             |
//|                                                                  |
//|  Everything platform specific that the core needs is funnelled      |
//|  through the macros below.  Defining VWAPPRO_CPP_TEST switches the  |
//|  macros (and nothing else) to standard C++.                         |
//|                                                                  |
//|  Rules the core headers obey, so that both compilers accept them:   |
//|    * no const member functions, no default arguments               |
//|    * no templates, no operator overloading, no exceptions           |
//|    * no pointers, no strings, no colour, no file or network I/O     |
//|    * dynamic arrays are declared with VP_DYN(type, name),           |
//|      resized with VP_RESIZE(name, count) and passed to functions    |
//|      with VP_ARR(type, name)                                        |
//+------------------------------------------------------------------+
#ifndef VWAPPRO_COMPAT_MQH
#define VWAPPRO_COMPAT_MQH

//+------------------------------------------------------------------+
//| Marker value for "no value".  Identical to MQL4's EMPTY_VALUE.    |
//+------------------------------------------------------------------+
#define VP_EMPTY 2147483647.0

#ifdef VWAPPRO_CPP_TEST
//+------------------------------------------------------------------+
//|                        C++ (unit test) target                    |
//+------------------------------------------------------------------+
#include <cmath>
#include <cstdio>
#include <vector>
#include <algorithm>

#define vp_int64 long long

inline double vp_abs(double x)      { return std::fabs(x); }
inline double vp_sqrt(double x)     { return (x <= 0.0) ? 0.0 : std::sqrt(x); }
inline double vp_floor(double x)    { return std::floor(x); }
inline double vp_ceil(double x)     { return std::ceil(x); }
inline double vp_round(double x)    { return std::floor(x + 0.5); }
inline double vp_pow(double a, double b) { return std::pow(a, b); }
inline double vp_log(double x)      { return (x > 0.0) ? std::log(x) : 0.0; }
inline double vp_exp(double x)      { return std::exp(x); }
inline double vp_max(double a, double b) { return a > b ? a : b; }
inline double vp_min(double a, double b) { return a < b ? a : b; }
inline int    vp_imax(int a, int b) { return a > b ? a : b; }
inline int    vp_imin(int a, int b) { return a < b ? a : b; }
inline bool   vp_isnan(double x)    { return x != x; }
inline bool   vp_isfinite(double x) { return std::isfinite(x); }
inline void   vp_log_msg(const char *s) { std::printf("%s\n", s); }

// Resize mirrors MQL4's ArrayResize: new elements are zeroed and the
// resulting element count is returned.  (A template is fine *here*
// because this macro body only ever reaches the C++ compiler.)
template <class T> inline int vp_cpp_resize(std::vector<T> &a, int n)
{
   if (n < 0) n = 0;
   a.assign((size_t)n, T());
   return (int)a.size();
}

#define VP_DYN(name, type)  std::vector<type> name
#define VP_RESIZE(a, n)     vp_cpp_resize(a, (n))
#define VP_SIZE(a)          ((int)(a).size())
#define VP_ZERO(a)          ((a).clear(), 0)
#define VP_ARR(type, name)  std::vector<type> &name

#else
//+------------------------------------------------------------------+
//|                          MQL4 target                             |
//+------------------------------------------------------------------+
#define vp_int64 long

#define vp_abs(x)        MathAbs(x)
#define vp_sqrt(x)       MathSqrt(x)
#define vp_floor(x)      MathFloor(x)
#define vp_ceil(x)       MathCeil(x)
#define vp_round(x)      MathRound(x)
#define vp_pow(a, b)     MathPow(a, b)
#define vp_log(x)        MathLog(x)
#define vp_exp(x)        MathExp(x)
#define vp_max(a, b)     MathMax(a, b)
#define vp_min(a, b)     MathMin(a, b)
#define vp_imax(a, b)    ((a) > (b) ? (a) : (b))
#define vp_imin(a, b)    ((a) < (b) ? (a) : (b))
#define vp_isnan(x)      ((x) != (x))
#define vp_isfinite(x)   (MathIsValidNumber(x))
#define vp_log_msg(s)    Print(s)

#define VP_DYN(name, type)  type name[]
#define VP_RESIZE(a, n)     (ArrayResize(a, n))
#define VP_SIZE(a)          (ArraySize(a))
#define VP_ZERO(a)          (ArrayResize(a, 0))
#define VP_ARR(type, name)  type &name[]

#endif

//+------------------------------------------------------------------+
//| Shared helper prototypes (MQL4 wants them visible up front when   |
//| a definition appears further down the include chain).             |
//+------------------------------------------------------------------+
double vp_div_safe(double num, double den, double fallback);
int    vp_sign(double x);
double vp_clamp(double x, double lo, double hi);
int    vp_isqrt(int n);
double vp_tanh(double x);
vp_int64 vp_floor_div(vp_int64 a, vp_int64 b);
vp_int64 vp_floor_mod(vp_int64 a, vp_int64 b);

//+------------------------------------------------------------------+
//| Safe division: returns "fallback" instead of inf/NaN when the     |
//| denominator is zero or degenerate.  Guarding here is what keeps    |
//| the indicator from ever painting a NaN on the chart.               |
//+------------------------------------------------------------------+
double vp_div_safe(double num, double den, double fallback)
{
   if (den == 0.0) return fallback;
   if (vp_isnan(den) || vp_isnan(num)) return fallback;
   double r = num / den;
   if (!vp_isfinite(r)) return fallback;
   return r;
}

//| Sign of a value: -1, 0 or +1 (never NaN).
int vp_sign(double x)
{
   if (vp_isnan(x)) return 0;
   if (x > 0.0) return 1;
   if (x < 0.0) return -1;
   return 0;
}

//| Clamp a value into [lo, hi].
double vp_clamp(double x, double lo, double hi)
{
   if (vp_isnan(x)) return lo;
   if (x < lo) return lo;
   if (x > hi) return hi;
   return x;
}

//| Integer square root.
int vp_isqrt(int n)
{
   if (n <= 0) return 0;
   int r = (int)vp_sqrt((double)n);
   while (r > 0 && r * r > n) r--;
   while ((r + 1) * (r + 1) <= n) r++;
   return r;
}

//+------------------------------------------------------------------+
//| tanh.                                                            |
//|                                                                  |
//|  Needed because MQL4 has no hyperbolic functions, and because the  |
//|  composite signal sums several heterogeneous quantities (a z-score, |
//|  a regression confidence, an order-flow tilt) whose scales differ   |
//|  by orders of magnitude.  tanh bounds each one into (-1, 1) so no   |
//|  single component can dominate, and is smooth, so the score does    |
//|  not jump when a value crosses a threshold.                          |
//|                                                                  |
//|  Implemented with the numerically safe formulation for large |x|.   |
//+------------------------------------------------------------------+
double vp_tanh(double x)
{
   if (vp_isnan(x)) return 0.0;
   if (x > 20.0) return 1.0;
   if (x < -20.0) return -1.0;
   double e2 = vp_exp(2.0 * x);
   if (!vp_isfinite(e2)) return (x > 0.0) ? 1.0 : -1.0;
   double t = (e2 - 1.0) / (e2 + 1.0);
   if (!vp_isfinite(t)) return (x > 0.0) ? 1.0 : -1.0;
   return t;
}

//+------------------------------------------------------------------+
//| Floor division / modulo for signed integers.                     |
//| C style "/" truncates towards zero, which is wrong for negative    |
//| timestamps (pre-1970 fixture data), so we normalise here.          |
//+------------------------------------------------------------------+
vp_int64 vp_floor_div(vp_int64 a, vp_int64 b)
{
   vp_int64 q = a / b;
   if ((a % b != 0) && ((a < 0) != (b < 0))) q--;
   return q;
}

vp_int64 vp_floor_mod(vp_int64 a, vp_int64 b)
{
   vp_int64 r = a % b;
   if (r != 0 && ((a < 0) != (b < 0))) r += b;
   return r;
}

#endif // VWAPPRO_COMPAT_MQH
//+------------------------------------------------------------------+
