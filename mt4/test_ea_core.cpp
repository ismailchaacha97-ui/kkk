// Test harness for the EA CORE section of RuleOP_LadderEA.mq4.
//
// Same idea as the indicator: the Makefile extracts the bytes between
// "EA CORE BEGIN" and "EA CORE END" and compiles them as C++17, so these tests
// run the exact code MetaEditor will compile.
//
// The circuit breakers are the reason this file exists. They are the only part
// of a Rule OP system that protects the account, and they are trivially easy
// to get backwards - a `>=` where a `<=` belongs means the stop never fires.

#include "ea_core_under_test.inc"
#include <cmath>
#include <cstdio>

static int g_checks = 0;
static int g_failures = 0;

static void expect_near(const char *what, double got, double want, double tol)
{
   g_checks++;
   const bool ok = std::fabs(got - want) <= tol;
   if(!ok) g_failures++;
   std::printf("%-54s %12.6f  want %12.6f  %s\n", what, got, want,
               ok ? "ok" : "FAIL");
}

static void expect_bool(const char *what, bool got, bool want)
{
   g_checks++;
   const bool ok = got == want;
   if(!ok) g_failures++;
   std::printf("%-54s %12s  want %12s  %s\n", what, got ? "true" : "false",
               want ? "true" : "false", ok ? "ok" : "FAIL");
}

// reference ladder: $100, 0.01 first lot, 30 pip step, 2x, 20 pip TP
static const double FIRST = 1.1000;
static const double STEP  = 0.0030;
static const double TP    = 0.0020;
static const double BASE  = 0.01;
static const double MULT  = 2.0;

// Independent reference P&L, written out longhand. Nothing here calls the
// core, so comparing the core against it is a real check and not the core
// grading itself.
static double ref_stack_pnl(int dir, int rungs, double price)
{
   static const double lots[8] = {0.01, 0.02, 0.04, 0.08,
                                  0.16, 0.32, 0.64, 1.28};
   double pnl = 0.0;
   for(int i = 0; i < rungs; i++)
   {
      const double entry = FIRST - dir * i * STEP;
      pnl += (price - entry) * dir * lots[i] * 100000.0;
   }
   return pnl;
}

int main()
{
   std::printf("\n--- basket take profit matches the indicator ---\n");
   // rung 4 average entry is 1.0932, so the buy basket TP is 1.0952
   expect_near("buy basket TP, 4 rungs",
               EABasketTP(FIRST, STEP, TP, BASE, MULT, 1, 4), 1.0952, 1e-9);
   expect_near("buy basket TP, 1 rung",
               EABasketTP(FIRST, STEP, TP, BASE, MULT, 1, 1), 1.1020, 1e-9);
   // Sell ladder: rungs step UP, so the average entry is 1.1068, and the
   // basket TP is one TP distance on the profit side, i.e. BELOW it at
   // 1.1048. That is still 48 pips above the first entry - the stack is
   // long since out of the red, it just has not got all the way back.
   expect_near("sell basket TP, 4 rungs",
               EABasketTP(FIRST, STEP, TP, BASE, MULT, -1, 4), 1.1048, 1e-9);

   // The check that actually settles the sign, for both directions: at its own
   // basket TP the stack must be IN PROFIT, by exactly cumLot * tp * pip value.
   expect_near("buy stack in profit at its basket TP",
               ref_stack_pnl(1, 4,
                             EABasketTP(FIRST, STEP, TP, BASE, MULT, 1, 4)),
               30.0, 1e-6);
   expect_near("sell stack in profit at its basket TP",
               ref_stack_pnl(-1, 4,
                             EABasketTP(FIRST, STEP, TP, BASE, MULT, -1, 4)),
               30.0, 1e-6);
   // and one TP the wrong way is a loss of the same size
   expect_near("buy stack loses 30 one TP the other side",
               ref_stack_pnl(1, 4,
                             EABasketTP(FIRST, STEP, TP, BASE, MULT, 1, 4)
                             - 2 * TP),
               -30.0, 1e-6);
   expect_near("empty stack returns first + dir*tp",
               EABasketTP(FIRST, STEP, TP, BASE, MULT, 1, 0), 1.1020, 1e-9);

   std::printf("\n--- the basket close fires on the right side only ---\n");
   expect_bool("buy: closes at the TP",
               BasketShouldClose(FIRST, STEP, TP, BASE, MULT, 1, 4, 1.0952),
               true);
   expect_bool("buy: does not close below the TP",
               BasketShouldClose(FIRST, STEP, TP, BASE, MULT, 1, 4, 1.0951),
               false);
   expect_bool("sell: closes at the TP",
               BasketShouldClose(FIRST, STEP, TP, BASE, MULT, -1, 4, 1.1048),
               true);
   expect_bool("sell: does not close above the TP",
               BasketShouldClose(FIRST, STEP, TP, BASE, MULT, -1, 4, 1.1049),
               false);
   expect_bool("no positions, nothing to close",
               BasketShouldClose(FIRST, STEP, TP, BASE, MULT, 1, 0, 1.5),
               false);

   std::printf("\n--- the next rung waits a full step, and respects the cap ---\n");
   // with 1 rung open at 1.1000, rung 2 is due at 1.0970
   expect_bool("buy: not due 29 pips down",
               NextRungDue(FIRST, STEP, 1, 1, 4, 1.0971), false);
   expect_bool("buy: due at exactly 30 pips down",
               NextRungDue(FIRST, STEP, 1, 1, 4, 1.0970), true);
   expect_bool("buy: not due when in profit",
               NextRungDue(FIRST, STEP, 1, 1, 4, 1.1050), false);
   expect_bool("buy: cap of 4 stops the 5th rung",
               NextRungDue(FIRST, STEP, 1, 4, 4, 1.0800), false);
   expect_bool("buy: 3rd rung still allowed under a cap of 4",
               NextRungDue(FIRST, STEP, 1, 3, 4, 1.0900), true);
   // sell ladder rungs step up, so the next rung is due 30 pips ABOVE the
   // deepest entry. 1.1030 is only 30 pips above the FIRST entry, which is
   // where the ladder is currently in profit, not in trouble.
   expect_bool("sell: not due 30 pips up from the first entry",
               NextRungDue(FIRST, STEP, -1, 1, 4, 1.1030), false);
   expect_bool("sell: due 30 pips beyond the deepest entry",
               NextRungDue(FIRST, STEP, -1, 1, 4, 1.1060), true);
   expect_bool("nothing open, nothing due",
               NextRungDue(FIRST, STEP, 1, 0, 4, 1.0000), false);

   std::printf("\n--- CIRCUIT BREAKER: max drawdown ---\n");
   // $100 peak, 15% limit -> stop at $85
   expect_bool("breached at 84.99 on a 100 peak",
               MaxDrawdownBreached(84.99, 100.0, 15.0), true);
   expect_bool("breached at exactly 85.00",
               MaxDrawdownBreached(85.00, 100.0, 15.0), true);
   expect_bool("not breached at 85.01",
               MaxDrawdownBreached(85.01, 100.0, 15.0), false);
   expect_bool("not breached while in profit",
               MaxDrawdownBreached(150.0, 100.0, 15.0), false);
   expect_bool("limit of 0 disables the breaker",
               MaxDrawdownBreached(1.0, 100.0, 0.0), false);
   expect_bool("reference of 0 disables the breaker",
               MaxDrawdownBreached(1.0, 0.0, 15.0), false);
   // the reference must be the PEAK, not the starting balance, or a winning
   // account can lose everything it made before the stop ever fires
   expect_bool("measured from a grown peak, not the deposit",
               MaxDrawdownBreached(170.0, 200.0, 15.0), true);

   std::printf("\n--- CIRCUIT BREAKER: daily loss ---\n");
   expect_bool("breached after a 10% fall from the day's start",
               DailyLossBreached(89.9, 100.0, 10.0), true);
   expect_bool("not breached before it",
               DailyLossBreached(90.1, 100.0, 10.0), false);
   expect_bool("not breached when the day is up",
               DailyLossBreached(120.0, 100.0, 10.0), false);
   expect_bool("limit of 0 disables it",
               DailyLossBreached(1.0, 100.0, 0.0), false);

   std::printf("\n--- CIRCUIT BREAKER: risk capital ---\n");
   expect_bool("breached once the stated risk is gone",
               RiskCapitalExhausted(50.0, 100.0, 50.0), true);
   expect_bool("not breached while some remains",
               RiskCapitalExhausted(60.0, 100.0, 50.0), false);
   expect_bool("not breached while in profit",
               RiskCapitalExhausted(150.0, 100.0, 50.0), false);
   expect_bool("risk of 0 disables it",
               RiskCapitalExhausted(0.0, 100.0, 0.0), false);

   std::printf("\n--- rung lot and broker lot normalisation ---\n");
   expect_near("rung 1", RungLot(BASE, MULT, 1), 0.01, 1e-12);
   expect_near("rung 5", RungLot(BASE, MULT, 5), 0.16, 1e-12);
   expect_near("truncates down to the lot step",
               NormaliseLot(0.015, 0.01, 100.0, 0.01), 0.01, 1e-12);
   expect_near("0.024 -> 0.02",
               NormaliseLot(0.024, 0.01, 100.0, 0.01), 0.02, 1e-12);
   expect_near("clamps up to the broker minimum",
               NormaliseLot(0.004, 0.01, 100.0, 0.01), 0.01, 1e-12);
   expect_near("clamps down to the broker maximum",
               NormaliseLot(500.0, 0.01, 50.0, 0.01), 50.0, 1e-12);
   expect_near("a zero lot step falls back to 0.01",
               NormaliseLot(0.027, 0.01, 100.0, 0.0), 0.02, 1e-12);

   std::printf("\n--- spread filter ---\n");
   expect_bool("20 points passes a 30 point limit",
               SpreadAcceptable(20, 30), true);
   expect_bool("31 points fails a 30 point limit",
               SpreadAcceptable(31, 30), false);
   expect_bool("limit of 0 means do not filter",
               SpreadAcceptable(999, 0), true);

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
