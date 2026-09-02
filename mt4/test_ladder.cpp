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

static void expect_near(const char *what, const double got, const double want,
                        const double tol)
{
   g_checks++;
   const bool ok = std::fabs(got - want) <= tol;
   if(!ok) g_failures++;
   std::printf("%-52s %12.6f  want %12.6f  %s\n", what, got, want,
               ok ? "ok" : "FAIL");
}

static void expect_int(const char *what, const int got, const int want)
{
   g_checks++;
   const bool ok = (got == want);
   if(!ok) g_failures++;
   std::printf("%-52s %12d  want %12d  %s\n", what, got, want, ok ? "ok" : "FAIL");
}

static void expect_bool(const char *what, const bool got, const bool want)
{
   g_checks++;
   const bool ok = (got == want);
   if(!ok) g_failures++;
   std::printf("%-52s %12s  want %12s  %s\n", what, got ? "true" : "false",
               want ? "true" : "false", ok ? "ok" : "FAIL");
}

// The reference ladder, matching the report.md parameters:
//   $100 account, 0.01 first lot, 30 pip step, 2.0x multiplier,
//   20 pip basket take profit, 1:500 leverage, 50% stop out.
// 1 pip = 0.0001 price units, so 30 pips = 0.0030 and 20 pips = 0.0020.
// tick_value is the account currency value of ONE FULL PRICE UNIT on 1.00 lot:
// 100000 units * $1 = $100000, i.e. $10 per pip per lot.
static const double FIRST = 1.1000;
static const double STEP  = 0.0030;
static const double TP    = 0.0020;
static const double BASE  = 0.01;
static const double MULT  = 2.0;
static const double TV    = 100000.0;

// the reference account
static const double BAL    = 100.0;
static const double CSIZE  = 100000.0;
static const double MRATE  = 0.002;    // 1:500
static const double PRICE  = 1.1000;
static const double STOP   = 0.5;

int main()
{
   std::printf("\n--- rung entries: 1.1000 less 30 pips per rung ---\n");
   expect_near("LadderEntry(1)", LadderEntry(FIRST, STEP, 1, 1), 1.1000, 1e-9);
   expect_near("LadderEntry(2)", LadderEntry(FIRST, STEP, 1, 2), 1.0970, 1e-9);
   expect_near("LadderEntry(3)", LadderEntry(FIRST, STEP, 1, 3), 1.0940, 1e-9);
   expect_near("LadderEntry(6)", LadderEntry(FIRST, STEP, 1, 6), 1.0850, 1e-9);

   std::printf("\n--- lot per rung doubles ---\n");
   expect_near("LadderLot(1)", LadderLot(BASE, MULT, 1), 0.01, 1e-12);
   expect_near("LadderLot(4)", LadderLot(BASE, MULT, 4), 0.08, 1e-12);
   expect_near("LadderLot(10)", LadderLot(BASE, MULT, 10), 5.12, 1e-9);

   std::printf("\n--- cumulative lot: base * (2^n - 1) ---\n");
   expect_near("LadderCumLot(1)", LadderCumLot(BASE, MULT, 1), 0.01, 1e-12);
   expect_near("LadderCumLot(3)", LadderCumLot(BASE, MULT, 3), 0.07, 1e-12);
   expect_near("LadderCumLot(5)", LadderCumLot(BASE, MULT, 5), 0.31, 1e-12);
   expect_near("LadderCumLot(6)", LadderCumLot(BASE, MULT, 6), 0.63, 1e-9);
   expect_near("LadderCumLot(10)", LadderCumLot(BASE, MULT, 10), 10.23, 1e-9);

   std::printf("\n--- average entry, hand computed for rung 3 ---\n");
   // (1.1000*0.01 + 1.0970*0.02 + 1.0940*0.04) / 0.07
   expect_near("LadderAvgEntry(3)",
               LadderAvgEntry(FIRST, STEP, BASE, MULT, 1, 3),
               (1.1000 * 0.01 + 1.0970 * 0.02 + 1.0940 * 0.04) / 0.07, 1e-9);
   expect_near("LadderAvgEntry(1) == first entry",
               LadderAvgEntry(FIRST, STEP, BASE, MULT, 1, 1), 1.1000, 1e-12);

   std::printf("\n--- THE 'NO LOSS' IDENTITY: basket TP profit ---\n");
   // At the basket TP the stack is always worth cumLot * tp * tick_value, at
   // every depth. Hand values: 0.01*0.002*100000 = $2.00 and so on.
   expect_near("basket TP profit, rung 1",
               LadderBasketTPProfit(TP, BASE, MULT, 1, TV), 2.0, 1e-9);
   expect_near("basket TP profit, rung 2",
               LadderBasketTPProfit(TP, BASE, MULT, 2, TV), 6.0, 1e-9);
   expect_near("basket TP profit, rung 3",
               LadderBasketTPProfit(TP, BASE, MULT, 3, TV), 14.0, 1e-9);
   expect_near("basket TP profit, rung 5",
               LadderBasketTPProfit(TP, BASE, MULT, 5, TV), 62.0, 1e-9);
   expect_near("basket TP profit, rung 6",
               LadderBasketTPProfit(TP, BASE, MULT, 6, TV), 126.0, 1e-9);

   // and the floating P&L evaluated AT the basket TP must equal it exactly
   std::printf("\n--- floating P&L evaluated at the basket TP matches ---\n");
   for(int n = 1; n <= 6; n++)
   {
      const double tp_price =
         LadderBasketTP(FIRST, STEP, TP, BASE, MULT, 1, n);
      char label[64];
      std::snprintf(label, sizeof(label), "floating at basket TP, rung %d", n);
      expect_near(label,
                  LadderFloating(FIRST, STEP, BASE, MULT, 1, n, tp_price, TV),
                  LadderBasketTPProfit(TP, BASE, MULT, n, TV), 1e-6);
   }

   std::printf("\n--- floating loss of the WHOLE stack grows geometrically ---\n");
   // Hand summed at each rung's own entry price, e.g. rung 5:
   //   0.01*0.012 + 0.02*0.009 + 0.04*0.006 + 0.08*0.003 + 0.16*0 = 0.00078
   //   * 100000 = -$78.00
   // NOTE: this is NOT (adverse move * newest lot), which is what report.md's
   // "loss on newest rung" column shows. The stack is worth less than it looks.
   expect_near("stack floating at rung 3 entry",
               LadderFloating(FIRST, STEP, BASE, MULT, 1, 3, 1.0940, TV),
               -12.0, 1e-6);
   expect_near("stack floating at rung 5 entry",
               LadderFloating(FIRST, STEP, BASE, MULT, 1, 5, 1.0880, TV),
               -78.0, 1e-6);
   expect_near("stack floating at rung 6 entry",
               LadderFloating(FIRST, STEP, BASE, MULT, 1, 6, 1.0850, TV),
               -171.0, 1e-6);

   std::printf("\n--- margin: cumLot * 100000 * 0.002 * 1.10 = $220 per lot ---\n");
   expect_near("margin rung 1",
               LadderMargin(BASE, MULT, 1, CSIZE, MRATE, PRICE), 2.20, 1e-9);
   expect_near("margin rung 3",
               LadderMargin(BASE, MULT, 3, CSIZE, MRATE, PRICE), 15.40, 1e-9);
   expect_near("margin rung 6",
               LadderMargin(BASE, MULT, 6, CSIZE, MRATE, PRICE), 138.60, 1e-9);

   std::printf("\n--- RungAtPrice ---\n");
   expect_int("rung at entry", RungAtPrice(FIRST, STEP, 1, 1.1000), 1);
   expect_int("rung 10 pips down (still rung 1)",
              RungAtPrice(FIRST, STEP, 1, 1.0990), 1);
   expect_int("rung exactly at rung 2", RungAtPrice(FIRST, STEP, 1, 1.0970), 2);
   expect_int("rung 65 pips down", RungAtPrice(FIRST, STEP, 1, 1.0935), 3);
   expect_int("rung above entry (in profit)",
              RungAtPrice(FIRST, STEP, 1, 1.1050), 1);

   std::printf("\n--- survivability, hand computed ---\n");
   // rung 4: stack floating -33, equity 67, margin 33.00, stopout 16.50 -> alive
   expect_bool("rung 4 survivable",
               RungIsSurvivable(FIRST, STEP, BASE, MULT, 1, 4, BAL, CSIZE,
                                MRATE, PRICE, STOP, TV), true);
   // rung 5: stack floating -78, equity 22, margin 68.20 -> no free margin
   expect_bool("rung 5 survivable",
               RungIsSurvivable(FIRST, STEP, BASE, MULT, 1, 5, BAL, CSIZE,
                                MRATE, PRICE, STOP, TV), false);
   expect_int("MaxAffordableRung on $100",
              MaxAffordableRung(FIRST, STEP, BASE, MULT, 1, BAL, CSIZE, MRATE,
                                PRICE, STOP, TV, 12), 4);

   std::printf("\n--- kill price for rung 3, hand computed ---\n");
   // avg(3) - (balance - 0.5*margin) / (cumLot * tick_value)
   const double avg3 = (1.1000 * 0.01 + 1.0970 * 0.02 + 1.0940 * 0.04) / 0.07;
   const double want_kill = avg3 - (100.0 - 0.5 * 15.40) / (0.07 * TV);
   expect_near("KillPrice(rung 3)",
               KillPrice(FIRST, STEP, BASE, MULT, 1, 3, BAL, CSIZE, MRATE,
                         PRICE, STOP, TV), want_kill, 1e-9);

   // independent check: equity AT the kill price must equal the stopout level
   {
      const double k = KillPrice(FIRST, STEP, BASE, MULT, 1, 3, BAL, CSIZE,
                                 MRATE, PRICE, STOP, TV);
      const double equity =
         BAL + LadderFloating(FIRST, STEP, BASE, MULT, 1, 3, k, TV);
      expect_near("equity at kill price == stopout level",
                  equity, STOP * LadderMargin(BASE, MULT, 3, CSIZE, MRATE,
                                              PRICE), 1e-6);
   }

   std::printf("\n--- sell ladder mirrors the buy ladder ---\n");
   expect_near("sell LadderEntry(3)", LadderEntry(FIRST, STEP, -1, 3),
               1.1060, 1e-9);
   expect_near("sell basket TP profit rung 3",
               LadderBasketTPProfit(TP, BASE, MULT, 3, TV), 14.0, 1e-9);
   expect_int("sell rung 65 pips up", RungAtPrice(FIRST, STEP, -1, 1.1065), 3);
   expect_int("sell MaxAffordableRung",
              MaxAffordableRung(FIRST, STEP, BASE, MULT, -1, BAL, CSIZE, MRATE,
                                PRICE, STOP, TV, 12), 4);
   // Absolute assertions, not self-comparisons. The offset direction flips
   // with the ladder, and it is the one place this is easy to get backwards:
   //   buy ladder  - rungs step DOWN, avg entry drifts down, TP above it
   //   sell ladder - rungs step UP,   avg entry drifts up,   TP below it
   expect_near("buy basket TP is 20 pips above avg entry",
               LadderBasketTP(FIRST, STEP, TP, BASE, MULT, 1, 3)
               - LadderAvgEntry(FIRST, STEP, BASE, MULT, 1, 3), 0.0020, 1e-12);
   expect_near("sell basket TP is 20 pips below avg entry",
               LadderAvgEntry(FIRST, STEP, BASE, MULT, -1, 3)
               - LadderBasketTP(FIRST, STEP, TP, BASE, MULT, -1, 3),
               0.0020, 1e-12);
   // the real proof either way: the stack is IN PROFIT at its basket TP
   expect_near("buy stack floating at its basket TP",
               LadderFloating(FIRST, STEP, BASE, MULT, 1, 3,
                              LadderBasketTP(FIRST, STEP, TP, BASE, MULT, 1, 3),
                              TV), 14.0, 1e-6);
   expect_near("sell stack floating at its basket TP",
               LadderFloating(FIRST, STEP, BASE, MULT, -1, 3,
                              LadderBasketTP(FIRST, STEP, TP, BASE, MULT, -1, 3),
                              TV), 14.0, 1e-6);

   std::printf("\n--- a bigger account survives deeper ---\n");
   // rung 11 on $10000: floating -6108, equity 3892, margin 4503.40, so free
   // margin is -611.40 and the broker refuses it. Max affordable is 10.
   expect_int("MaxAffordableRung on $10000",
              MaxAffordableRung(FIRST, STEP, BASE, MULT, 1, 10000.0, CSIZE,
                                MRATE, PRICE, STOP, TV, 12), 10);

   std::printf("\n--- degenerate inputs must not divide by zero ---\n");
   expect_int("zero step clamps to rung 1", RungAtPrice(FIRST, 0.0, 1, 0.5), 1);
   expect_near("zero lot gives no margin",
               LadderMargin(0.0, MULT, 3, CSIZE, MRATE, PRICE), 0.0, 1e-12);
   expect_near("kill price of an empty stack",
               KillPrice(FIRST, STEP, BASE, MULT, 1, 0, BAL, CSIZE, MRATE,
                         PRICE, STOP, TV), 0.0, 1e-12);

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
