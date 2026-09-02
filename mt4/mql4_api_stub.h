// Minimal MQL4 API surface, so the MT4 half of RuleOP_Ladder.mq4 can be
// compiled and exercised off-platform.
//
// This exists because MetaEditor is not available in the sandbox. It does not
// prove the indicator compiles under MetaEditor - only the real compiler can do
// that - but it does prove the MT4 half is syntactically valid C++ and that its
// logic does the right thing, which is more than "eyeballed it".
//
// Every object the indicator draws is recorded in g_objects so tests can assert
// on the prices it chose.

#pragma once

// MQL4-only keywords and directives, neutralised for C++
#define input

#include <cmath>
#include <cstdio>
#include <map>
#include <string>
#include <vector>

typedef std::string string;
typedef int color;
typedef long long datetime_;
#define datetime datetime_

// MQL4's OnCalculate takes `const datetime &time[]` and friends - arrays of
// references, which C++ forbids. The Makefile rewrites every such parameter in
// the generated ind_under_test.inc to one of these aliases. RuleOP_Ladder.mq4
// itself is never modified.
typedef const std::vector<datetime_> &datetime_vec;
typedef const std::vector<double>    &double_vec;
typedef const std::vector<long>      &long_vec;
typedef const std::vector<int>       &int_vec;

//--- constants -----------------------------------------------------
#define MODE_TICKVALUE 28
#define MODE_TICKSIZE  27
#define MODE_TRADES    0
#define SELECT_BY_POS  0
#define OP_BUY         0
#define OP_SELL        1
#define OBJ_HLINE          1
#define OBJ_ARROW_RIGHT_PRICE 2
#define OBJPROP_PRICE  0
#define OBJPROP_COLOR  1
#define OBJPROP_WIDTH  2
#define OBJPROP_STYLE  3
#define OBJPROP_BACK   4
#define OBJPROP_TEXT   5
#define STYLE_SOLID    0
#define INIT_SUCCEEDED 0

const color clrDodgerBlue = 16748574;
const color clrCrimson    = 3937500;
const color clrGray       = 8421504;
const color clrLime       = 65280;
const color clrRed        = 255;

//--- instrument / account state the tests drive --------------------
extern double  g_point;
extern int     g_digits;
extern double  g_bid;
extern double  g_tick_value;
extern double  g_tick_size;
extern double  g_balance;
extern int     g_leverage;
extern int     g_stopout_level;
extern std::vector<datetime_> g_time;

struct StubOrder
{
   string sym;
   int    magic;
   int    type;
   double open_price;
   double lots;
   datetime_ open_time = 0;
};
extern std::vector<StubOrder> g_orders;
extern int g_selected;

#define Point      g_point
#define Digits     g_digits
#define Bid        g_bid
#define Ask        g_bid
#define Time       g_time
#define TickValue  g_tick_value
#define TickSize   g_tick_size

//--- recorded objects ---------------------------------------------
struct StubObject
{
   std::map<int, double> props;
   std::map<int, string> text;
   int type = 0;
};
extern std::map<string, StubObject> g_objects;
extern std::vector<string> g_alerts;
extern string g_comment;

//--- API -----------------------------------------------------------
inline string Symbol() { return "EURUSD"; }
inline datetime_ TimeCurrent() { return 1700000000; }

inline double MarketInfo(string /*sym*/, int mode)
{
   if(mode == MODE_TICKVALUE) return g_tick_value;
   if(mode == MODE_TICKSIZE)  return g_tick_size;
   return 0.0;
}

inline double AccountBalance()      { return g_balance; }
inline int    AccountLeverage()     { return g_leverage; }
inline int    AccountStopoutLevel() { return g_stopout_level; }

inline int OrdersTotal() { return (int)g_orders.size(); }

inline bool OrderSelect(int i, int /*sel*/, int /*mode*/)
{
   if(i < 0 || i >= (int)g_orders.size()) return false;
   g_selected = i;
   return true;
}
inline string OrderSymbol()        { return g_orders[g_selected].sym; }
inline int    OrderMagicNumber()   { return g_orders[g_selected].magic; }
inline int    OrderType()          { return g_orders[g_selected].type; }
inline double OrderOpenPrice()     { return g_orders[g_selected].open_price; }
inline datetime_ OrderOpenTime() { return g_orders[g_selected].open_time; }
inline double OrderLots()          { return g_orders[g_selected].lots; }

inline int ObjectFind(long /*chart*/, string name)
{
   return g_objects.count(name) ? 0 : -1;
}
inline bool ObjectCreate(long /*chart*/, string name, int type,
                         int /*window*/, datetime_ /*t*/, double price)
{
   StubObject o;
   o.type = type;
   o.props[OBJPROP_PRICE] = price;
   g_objects[name] = o;
   return true;
}
inline bool ObjectDelete(long /*chart*/, string name)
{
   return g_objects.erase(name) > 0;
}
inline bool ObjectSetDouble(long /*c*/, string n, int p, double v)
{
   g_objects[n].props[p] = v;
   return true;
}
inline bool ObjectSetInteger(long /*c*/, string n, int p, long v)
{
   g_objects[n].props[p] = (double)v;
   return true;
}
inline bool ObjectSetString(long /*c*/, string n, int p, string v)
{
   g_objects[n].text[p] = v;
   return true;
}
inline int ObjectsDeleteAll(long /*c*/, string prefix)
{
   int removed = 0;
   for(auto it = g_objects.begin(); it != g_objects.end();)
   {
      if(it->first.rfind(prefix, 0) == 0) { it = g_objects.erase(it); removed++; }
      else ++it;
   }
   return removed;
}

inline double MathAbs(double v) { return std::fabs(v); }
inline double MathMax(double a, double b) { return a > b ? a : b; }

//--- string helpers ------------------------------------------------
// MQL4 concatenates numbers onto strings with +. std::string will not, so
// provide the free functions the indicator uses and rely on those.
inline string DoubleToString(double v, int digits)
{
   char buf[64];
   std::snprintf(buf, sizeof(buf), "%.*f", digits, v);
   return string(buf);
}
inline string IntegerToString(long v)
{
   char buf[32];
   std::snprintf(buf, sizeof(buf), "%ld", v);
   return string(buf);
}

inline void Comment(string s) { g_comment = s; }
void Alert(const string &a, const string &b = string(),
           const string &c = string(), const string &d = string(),
           const string &e = string());
inline bool IndicatorShortName(string /*s*/) { return true; }
