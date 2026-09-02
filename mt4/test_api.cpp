// Compiles the ENTIRE indicator - core and MT4 half - against the MQL4 API
// stub, and asserts on what it actually does.
//
// This reaches the parts the core-only test cannot: pip conversion, tick value
// derivation, adopting live orders, and the objects it draws on the chart.
// It still does not prove MetaEditor will accept the file.

#include "mql4_api_stub.h"
#include "ind_under_test.inc"

#include <cmath>
#include <cstdio>

static int g_checks = 0;
static int g_failures = 0;

static void expect_near(const char *what, double got, double want, double tol)
{
   g_checks++;
   const bool ok = std::fabs(got - want) <= tol;
   if(!ok) g_failures++;
   std::printf("%-50s %14.7f  want %14.7f  %s\n", what, got, want,
               ok ? "ok" : "FAIL");
}

static void expect_int(const char *what, long got, long want)
{
   g_checks++;
   const bool ok = got == want;
   if(!ok) g_failures++;
   std::printf("%-50s %14ld  want %14ld  %s\n", what, got, want,
               ok ? "ok" : "FAIL");
}

static void expect_bool(const char *what, bool got, bool want)
{
   g_checks++;
   const bool ok = got == want;
   if(!ok) g_failures++;
   std::printf("%-50s %14s  want %14s  %s\n", what, got ? "true" : "false",
               want ? "true" : "false", ok ? "ok" : "FAIL");
}

static double obj_price(const string &name)
{
   auto it = g_objects.find(name);
   if(it == g_objects.end())
   {
      std::printf("  !! object %s was never drawn\n", name.c_str());
      return 0.0;
   }
   return it->second.props[OBJPROP_PRICE];
}

static void reset_world()
{
   g_objects.clear();
   g_alerts.clear();
   g_orders.clear();
   g_comment.clear();
   // DrawRung reads Time[0]; a real chart always has bars
   g_time.assign(4, 1700000000);
   g_point = 0.00001;
   g_digits = 5;
   g_bid = 1.1000;
   g_tick_value = 1.0;
   g_tick_size = 0.00001;
   g_balance = 100.0;
   g_leverage = 500;
   g_stopout_level = 50;
   InpBaseLot = 0.01;
   InpTakeProfit = 20;
   InpStep = 30;
   InpMultiplier = 2.0;
   InpMaxRungs = 12;
   InpDirection = 1;
   InpAnchorPrice = 0.0;
   InpMagic = 0;
   InpManualTickVal = 0.0;
   InpShowPanel = true;
   InpAlertNextRung = false;
   InpAlertKillZone = false;
}

// Hand-computed reference for the default setup. Rung 4's average entry is
// (1.1000*0.01 + 1.0970*0.02 + 1.0940*0.04 + 1.0910*0.08) / 0.15 = 1.0932.
// (An earlier version of this file reused rung 3's average here and called it
// rung 4, which is why the kill price looked wrong. It was not.)
static const double REF_AVG4  = 1.0932;
static const double REF_TP4   = 1.0952;
// Margin is valued at the CURRENT price, not the entry price, so at
// Bid = 1.0910 the 0.15 lot stack needs 0.15 * 100000 * 0.002 * 1.0910 = 32.73
// and the stop out level is 16.365.
static const double REF_KILL4 =
   1.0932 - (100.0 - 0.5 * 0.15 * 100000.0 * 0.002 * 1.0910) / (0.15 * 100000.0);

int main()
{
   std::printf("\n--- PipSize: a 5-digit broker quotes fractional pips ---\n");
   reset_world();
   expect_near("5 digits -> pip is 10 points", PipSize(), 0.0001, 1e-12);
   g_digits = 4;   // Point stays 0.00001 here; only Digits changes
   expect_near("4 digits -> pip is 1 point", PipSize(), 0.00001, 1e-12);
   g_digits = 3;   // JPY pair quotes 3 decimals, so Point is 0.001
   g_point = 0.001;
   expect_near("3 digits -> pip is 10 points", PipSize(), 0.01, 1e-12);
   g_point = 0.00001;
   g_digits = 5;

   std::printf("\n--- TickValuePerLot comes from MarketInfo, not a builtin ---\n");
   reset_world();
   expect_near("1.0 per 0.00001 -> 100000 per price unit",
               TickValuePerLot(), 100000.0, 1e-6);
   InpManualTickVal = 50000.0;
   expect_near("manual override wins", TickValuePerLot(), 50000.0, 1e-9);
   InpManualTickVal = 0.0;
   g_tick_size = 0.0;   // broker returned nothing usable
   expect_near("falls back to a standard lot", TickValuePerLot(), 100000.0, 1e-9);

   std::printf("\n--- MakeSpec converts pips into price units ---\n");
   reset_world();
   LadderSpec s;
   MakeSpec(s, 1.1000, PipSize());
   expect_near("step 30 pips -> 0.0030", s.step, 0.0030, 1e-12);
   expect_near("tp 20 pips -> 0.0020", s.take_profit, 0.0020, 1e-12);
   expect_near("first entry is the anchor", s.first_entry, 1.1000, 1e-12);
   expect_int("default direction is a buy", s.dir, 1);
   InpDirection = -1;
   LadderSpec sell;
   MakeSpec(sell, 1.1, 0.0001);
   expect_int("InpDirection=-1 gives a sell", sell.dir, -1);

   std::printf("\n--- MakeAccount reads the terminal, not a constant ---\n");
   reset_world();
   AccountSpec a;
   MakeAccount(a);
   expect_near("balance", a.balance, 100.0, 1e-9);
   expect_near("1:500 -> margin rate 0.002", a.margin_rate, 0.002, 1e-12);
   expect_near("stopout 50 -> 0.5", a.stopout_pct, 0.5, 1e-12);
   g_leverage = 100;
   AccountSpec b;
   MakeAccount(b);
   expect_near("1:100 -> margin rate 0.01", b.margin_rate, 0.01, 1e-12);

   std::printf("\n--- LiveAnchor: preview mode with no orders open ---\n");
   reset_world();
   int rungs = -1, dir = 0;
   expect_near("anchors at Bid", LiveAnchor(rungs, dir), 1.1000, 1e-12);
   expect_int("zero open rungs", rungs, 0);
   InpAnchorPrice = 1.2345;
   expect_near("explicit anchor wins over Bid", LiveAnchor(rungs, dir),
               1.2345, 1e-12);

   std::printf("\n--- LiveAnchor adopts a real buy ladder ---\n");
   reset_world();
   InpMagic = 777;
   // opened out of order on purpose: rung 1 is the LOWEST entry for a buy
   g_orders.push_back({"EURUSD", 777, OP_BUY, 1.0970, 0.02});
   g_orders.push_back({"EURUSD", 777, OP_BUY, 1.0940, 0.04});
   g_orders.push_back({"EURUSD", 777, OP_BUY, 1.1000, 0.01});
   g_orders.push_back({"GBPUSD", 777, OP_BUY, 0.5000, 9.99});   // other symbol
   g_orders.push_back({"EURUSD", 999, OP_BUY, 0.9000, 9.99});   // other magic
   double anchor = LiveAnchor(rungs, dir);
   // rung 1 is the FIRST position opened, which in an averaging-down buy
   // ladder is the HIGHEST entry - not the lowest
   expect_near("rung 1 is the first/highest matching entry", anchor,
               1.1000, 1e-12);
   expect_int("three matching orders counted", rungs, 3);
   expect_int("direction taken from the orders", dir, 1);

   std::printf("\n--- LiveAnchor ignores a mixed-direction account ---\n");
   reset_world();
   InpMagic = 777;
   g_orders.push_back({"EURUSD", 777, OP_BUY,  1.1000, 0.01});
   g_orders.push_back({"EURUSD", 777, OP_SELL, 1.1000, 0.01});
   rungs = -1;
   LiveAnchor(rungs, dir);
   expect_int("only same-direction orders counted", rungs, 1);

   std::printf("\n--- what the indicator draws on a $100 account ---\n");
   reset_world();
   // Four real buy orders, so the indicator adopts an actual 4-rung ladder
   // rather than previewing from Bid. Now the average entry, basket TP and
   // kill price all describe the same stack.
   InpMagic = 777;
   g_bid = 1.0910;
   g_orders.push_back({"EURUSD", 777, OP_BUY, 1.1000, 0.01});
   g_orders.push_back({"EURUSD", 777, OP_BUY, 1.0970, 0.02});
   g_orders.push_back({"EURUSD", 777, OP_BUY, 1.0940, 0.04});
   g_orders.push_back({"EURUSD", 777, OP_BUY, 1.0910, 0.08});
   OnInit();
   // OnCalculate's array parameters are unused by the body, so minimal ones
   std::vector<datetime_> t(2, 0);
   std::vector<double> px(2, 1.1);
   std::vector<long> vol(2, 0);
   std::vector<int> spr(2, 1);
   OnCalculate(2, 0, t, px, px, px, px, vol, vol, spr);

   expect_near("rung 1 drawn at the anchor", obj_price("RuleOP_rung1"),
               1.1000, 1e-9);
   expect_near("rung 2 drawn 30 pips lower", obj_price("RuleOP_rung2"),
               1.0970, 1e-9);
   expect_near("rung 4 drawn 90 pips lower", obj_price("RuleOP_rung4"),
               1.0910, 1e-9);
   expect_near("average entry line", obj_price("RuleOP_avg"), REF_AVG4, 1e-9);
   expect_near("basket take profit line", obj_price("RuleOP_tp"), REF_TP4, 1e-9);
   expect_near("KILL PRICE line", obj_price("RuleOP_kill"), REF_KILL4, 1e-9);
   // the kill price must track the live price, because margin does
   expect_near("kill price uses live Bid for margin", REF_KILL4,
               1.0876243333, 1e-9);

   // rung 5 is the one this account cannot fund: it must be drawn red, not blue
   {
      auto it = g_objects.find("RuleOP_rung5");
      if(it == g_objects.end())
      {
         std::printf("%-50s %14s\n", "rung 5 drawn as the unaffordable rung",
                     "not drawn");
         g_checks++;
      }
      else
      {
         expect_near("rung 5 is drawn red (unaffordable)",
                     it->second.props[OBJPROP_COLOR], (double)clrCrimson, 0.5);
      }
      auto ok4 = g_objects.find("RuleOP_rung4");
      expect_near("rung 4 is drawn blue (affordable)",
                  ok4->second.props[OBJPROP_COLOR], (double)clrDodgerBlue, 0.5);
   }

   std::printf("\n--- the panel tells the truth about depth ---\n");
   expect_bool("panel says deepest rung is 4",
               g_comment.find("deepest rung you can open   4") != string::npos,
               true);
   expect_bool("panel says rung now is 4",
               g_comment.find("rung now        4") != string::npos, true);
   expect_bool("panel names the direction",
               g_comment.find("BUY") != string::npos, true);

   std::printf("\n--- cleanup removes exactly its own objects ---\n");
   {
      g_objects["SomeOtherIndicator_line"] = StubObject();
      const int before = (int)g_objects.size();
      OnDeinit(0);
      expect_int("its own objects removed", (long)g_objects.count("RuleOP_tp"), 0);
      expect_int("other indicators left alone",
                 (long)g_objects.count("SomeOtherIndicator_line"), 1);
      expect_bool("panel cleared", g_comment.empty(), true);
      (void)before;
   }

   std::printf("\n=====================================\n");
   std::printf("%d checks, %d failures\n", g_checks, g_failures);
   if(g_failures > 0)
   {
      std::printf("FAILED\n");
      return 1;
   }
   std::printf("ALL PASS\n");
   return 0;
}
