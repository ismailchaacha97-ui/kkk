// Test harness for the CORE section of RuleOP_Ladder.mq4.
//
// The Makefile extracts the bytes between "CORE BEGIN" and "CORE END" out of
// the .mq4 file and compiles them here as C++17. That means these tests run
// the SAME source that MetaEditor will compile - not a copy of it. If the
// ladder arithmetic changes in the indicator, these tests exercise the change.
//
// Every expected value below was derived by hand from first principles, not
// by asking the code what it produces.

#include "core_under_test.inc"
#include <cmath>
#include <cstdio>
#include <cstdlib>

static int g_checks = 0;
static int g_failures = 0;

static bool near_eq(const double a, const double b, const double tol)
{
   return std::fabs(a - b) <= tol;
}

static void expect_near(const char *what, const double got, const double want,
                        const double tol)
{
   g_checks++;
   const bool ok = near_eq(got, want, tol);
   if(!ok)
      g_failures++;
   std::printf("%-52s %12.6f  want %12.6f  %s\n", what, got, want,
               ok ? "ok" : "FAIL");
}

static void expect_int(const char *what, const int got, const int want)
{
   g_checks++;
   const bool ok = (got == want);
   if(!ok)
      g_failures++;
   std::printf("%-52s %12d  want %12d  %s\n", what, got, want, ok ? "ok" : "FAIL");
}

static void expect_bool(const char *what, const bool got, const bool want)
{
   g_checks++;
   const bool ok = (got == want);
   if(!ok)
      g_failures++;
   std::printf("%-52s %12s  want %12s  %s\n", what, got ? "true" : "false",
               want ? "true" : "false", ok ? "ok" : "FAIL");
}

// The reference setup, matching the report.md parameters:
//   $100 account, 0.01 first lot, 30 pip step, 2.0x multiplier,
//   20 pip basket take profit, 1:500 leverage, 50% stop out.
// 1 pip = 0.0001 price units, so 30 pips = 0.0030 and 20 pips = 0.0020.
// tick_value is the account currency value of ONE FULL PRICE UNIT on 1.00
// lot: 100000 units * $1 = $100000, i.e. $10 per pip per lot.
static LadderSpec ref_ladder()
{
   LadderSpec s;
   s.first_entry = 1.1000;
   s.step        = 0.0030;
   s.take_profit = 0.0020;
   s.base_lot    = 0.01;
   s.multiplier  = 2.0;
   s.dir         = 1;
   return s;
}

static AccountSpec ref_account()
{
   AccountSpec a;
   a.balance      = 100.0;
   a.contract_size = 100000.0;
   a.margin_rate  = 0.002;   // 1:500
   a.stopout_pct  = 0.5;
   a.price        = 1.1000;
   return a;
}

static const double TV = 100000.0;

int main()
{
   LadderSpec s = ref_ladder();
   AccountSpec a = ref_account();

   std::printf("\n--- rung entries: 1.1000 less 30 pips per rung ---\n");
   expect_near("LadderEntry(1)", LadderEntry(s, 1), 1.1000, 1e-9);
   expect_near("LadderEntry(2)", LadderEntry(s, 2), 1.0970, 1e-9);
   expect_near("LadderEntry(3)", LadderEntry(s, 3), 1.0940, 1e-9);
   expect_near("LadderEntry(6)", LadderEntry(s, 6), 1.0850, 1e-9);

   std::printf("\n--- lot per rung doubles ---\n");
   expect_near("LadderLot(1)", LadderLot(s, 1), 0.01, 1e-12);
   expect_near("LadderLot(4)", LadderLot(s, 4), 0.08, 1e-12);
   expect_near("LadderLot(10)", LadderLot(s, 10), 5.12, 1e-9);

   std::printf("\n--- cumulative lot: base * (2^n - 1) ---\n");
   expect_near("LadderCumLot(1)", LadderCumLot(s, 1), 0.01, 1e-12);
   expect_near("LadderCumLot(3)", LadderCumLot(s, 3), 0.07, 1e-12);
   expect_near("LadderCumLot(5)", LadderCumLot(s, 5), 0.31, 1e-12);
   expect_near("LadderCumLot(6)", LadderCumLot(s, 6), 0.63, 1e-9);
   expect_near("LadderCumLot(10)", LadderCumLot(s, 10), 10.23, 1e-9);

   std::printf("\n--- average entry, hand computed for rung 3 ---\n");
   // (1.1000*0.01 + 1.0970*0.02 + 1.0940*0.04) / 0.07
   expect_near("LadderAvgEntry(3)", LadderAvgEntry(s, 3),
               (1.1000 * 0.01 + 1.0970 * 0.02 + 1.0940 * 0.04) / 0.07, 1e-9);
   expect_near("LadderAvgEntry(1) == first entry", LadderAvgEntry(s, 1),
               1.1000, 1e-12);

   std::printf("\n--- THE 'NO LOSS' IDENTITY: basket TP profit ---\n");
   // At the basket TP the stack is always worth cumLot * tp * tick_value,
   // at every depth. Hand values: 0.01*0.002*100000 = $2.00 and so on.
   expect_near("basket TP profit, rung 1", LadderBasketTPProfit(s, 1, TV), 2.0, 1e-9);
   expect_near("basket TP profit, rung 2", LadderBasketTPProfit(s, 2, TV), 6.0, 1e-9);
   expect_near("basket TP profit, rung 3", LadderBasketTPProfit(s, 3, TV), 14.0, 1e-9);
   expect_near("basket TP profit, rung 5", LadderBasketTPProfit(s, 5, TV), 62.0, 1e-9);
   expect_near("basket TP profit, rung 6", LadderBasketTPProfit(s, 6, TV), 126.0, 1e-9);

   // and the floating P&L evaluated AT the basket TP must equal it exactly
   std::printf("\n--- floating P&L evaluated at the basket TP matches ---\n");
   for(int n = 1; n <= 6; n++)
   {
      const double tp_price = LadderBasketTP(s, n);
      char label[64];
      std::snprintf(label, sizeof(label), "floating at basket TP, rung %d", n);
      expect_near(label, LadderFloating(s, n, tp_price, TV),
                  LadderBasketTPProfit(s, n, TV), 1e-6);
   }

   std::printf("\n--- floating loss of the WHOLE stack grows geometrically ---\n");
   // Hand summed at each rung's own entry price, e.g. rung 5:
   //   0.01*0.012 + 0.02*0.009 + 0.04*0.006 + 0.08*0.003 + 0.16*0 = 0.00078
   //   * 100000 = -$78.00
   // NOTE: this is NOT the same as (adverse move * newest lot), which is what
   // report.md's "floating loss" column shows. That column is the loss on the
   // newest rung alone. The stack is worth far less than it looks.
   expect_near("stack floating at rung 3 entry", LadderFloating(s, 3, 1.0940, TV),
               -12.0, 1e-6);
   expect_near("stack floating at rung 5 entry", LadderFloating(s, 5, 1.0880, TV),
               -78.0, 1e-6);
   expect_near("stack floating at rung 6 entry", LadderFloating(s, 6, 1.0850, TV),
               -171.0, 1e-6);

   std::printf("\n--- margin: cumLot * 100000 * 0.002 * 1.10 = $220 per lot ---\n");
   expect_near("margin rung 1", LadderMargin(s, a, 1), 2.20, 1e-9);
   expect_near("margin rung 3", LadderMargin(s, a, 3), 15.40, 1e-9);
   expect_near("margin rung 6", LadderMargin(s, a, 6), 138.60, 1e-9);

   std::printf("\n--- RungAtPrice ---\n");
   expect_int("rung at entry", RungAtPrice(s, 1.1000), 1);
   expect_int("rung 10 pips down (still rung 1)", RungAtPrice(s, 1.0990), 1);
   expect_int("rung exactly at rung 2", RungAtPrice(s, 1.0970), 2);
   expect_int("rung 65 pips down", RungAtPrice(s, 1.0935), 3);
   expect_int("rung above entry (in profit)", RungAtPrice(s, 1.1050), 1);

   std::printf("\n--- survivability, hand computed ---\n");
   // rung 4: stack floating -33, equity 67, margin 33.00, stopout 16.50 -> alive
   expect_bool("rung 4 survivable", RungIsSurvivable(s, a, 4, TV), true);
   // rung 5: stack floating -78, equity 22, margin 68.20, stopout 34.10 -> dead
   expect_bool("rung 5 survivable", RungIsSurvivable(s, a, 5, TV), false);
   expect_int("MaxAffordableRung on $100", MaxAffordableRung(s, a, TV, 12), 4);

   std::printf("\n--- kill price for rung 3, hand computed ---\n");
   // avg(3) - (balance - 0.5*margin) / (cumLot * tick_value)
   //        = 1.0952857 - (100 - 7.70) / 7000 = 1.0821286
   const double want_kill =
      ((1.1000 * 0.01 + 1.0970 * 0.02 + 1.0940 * 0.04) / 0.07)
      - (100.0 - 0.5 * 15.40) / (0.07 * TV);
   expect_near("KillPrice(rung 3)", KillPrice(s, a, 3, TV), want_kill, 1e-9);

   // independent check: equity AT the kill price must equal the stopout level
   {
      const double k = KillPrice(s, a, 3, TV);
      const double equity = a.balance + LadderFloating(s, 3, k, TV);
      expect_near("equity at kill price == stopout level",
                  equity, a.stopout_pct * LadderMargin(s, a, 3), 1e-6);
   }

   std::printf("\n--- sell ladder mirrors the buy ladder ---\n");
   {
      LadderSpec q = ref_ladder();
      q.dir = -1;
      expect_near("sell LadderEntry(3)", LadderEntry(q, 3), 1.1060, 1e-9);
      expect_near("sell basket TP profit rung 3", LadderBasketTPProfit(q, 3, TV),
                  14.0, 1e-9);
      expect_int("sell rung 65 pips up", RungAtPrice(q, 1.1065), 3);
      expect_int("sell MaxAffordableRung", MaxAffordableRung(q, a, TV, 12), 4);
      // Absolute assertions, not self-comparisons. The offset direction flips
      // with the ladder, and it is worth being explicit because it is the one
      // place this code is easy to get backwards:
      //   buy ladder  - rungs step DOWN, avg entry drifts down, TP above it
      //   sell ladder - rungs step UP,   avg entry drifts up,   TP below it
      expect_near("buy basket TP is 20 pips above avg entry",
                  LadderBasketTP(s, 3) - LadderAvgEntry(s, 3), 0.0020, 1e-12);
      expect_near("sell basket TP is 20 pips below avg entry",
                  LadderAvgEntry(q, 3) - LadderBasketTP(q, 3), 0.0020, 1e-12);
      // the real proof either way: the stack is IN PROFIT at its basket TP
      expect_near("buy stack floating at its basket TP",
                  LadderFloating(s, 3, LadderBasketTP(s, 3), TV), 14.0, 1e-6);
      expect_near("sell stack floating at its basket TP",
                  LadderFloating(q, 3, LadderBasketTP(q, 3), TV), 14.0, 1e-6);
   }

   std::printf("\n--- a bigger account survives deeper, as the report shows ---\n");
   {
      AccountSpec big = ref_account();
      big.balance = 10000.0;
      expect_int("MaxAffordableRung on $10000", MaxAffordableRung(s, big, TV, 12), 11);
   }

   std::printf("\n--- degenerate inputs must not divide by zero ---\n");
   {
      LadderSpec z = ref_ladder();
      z.step = 0.0;
      expect_int("zero step clamps to rung 1", RungAtPrice(z, 0.5), 1);
      expect_near("zero lot gives no margin",
                  LadderMargin(ref_ladder(), ref_account(), 0), 0.0, 1e-12);
      expect_near("kill price of an empty stack",
                  KillPrice(ref_ladder(), ref_account(), 0, TV), 0.0, 1e-12);
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
