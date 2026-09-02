// Decision logic only: scalars in, scalars out, no orders, no MT4 API, no
// strings. The Makefile extracts this section and compiles it as C++17 so the
// rules that decide whether to trade are unit tested off-platform.
//
// Same discipline as the indicator: no structs across a function boundary, no
// function-like macros, no inheritance. MQL4 rejects all three.

//--- the price at which the basket take profit sits ----------------
// Average entry of rungs 1..rungs, pushed one TP distance onto the profit
// side. Identical arithmetic to the indicator's LadderBasketTP.
double EABasketTP(double first, double step, double tp, double base,
                  double mult, int dir, int rungs)
{
   double total = 0.0;
   double weighted = 0.0;
   for(int i = 1; i <= rungs; i++)
   {
      double lot = base;
      for(int k = 1; k < i; k++)
         lot *= mult;
      total += lot;
      weighted += (first - dir * (i - 1) * step) * lot;
   }
   if(total <= 0.0)
      return first + dir * tp;
   return weighted / total + dir * tp;
}

//--- should the whole stack close now? -----------------------------
bool BasketShouldClose(double first, double step, double tp, double base,
                       double mult, int dir, int rungs, double bid)
{
   if(rungs <= 0)
      return false;
   double level = EABasketTP(first, step, tp, base, mult, dir, rungs);
   // A weighted average is a division, so `level` carries floating point
   // residue. An exact comparison lets the stack sit on its own take profit
   // and refuse to close, which is the one bug you cannot afford here.
   double tol = tp * 1e-6;
   if(tol <= 0.0)
      tol = 1e-9;
   if(dir > 0)
      return bid >= level - tol;
   return bid <= level + tol;
}

//--- should the next rung be added? --------------------------------
// True only when price is a full step beyond the deepest entry AND the rung
// cap has not been reached. The cap is the hard one; the broker's margin
// check will refuse you sooner on a small account anyway.
bool NextRungDue(double first, double step, int dir, int rungs, int max_rungs,
                 double bid)
{
   if(rungs < 1 || rungs >= max_rungs)
      return false;
   double deepest = first - dir * (rungs - 1) * step;
   double adverse = dir * (deepest - bid);
   return adverse >= step;
}

//--- circuit breaker: peak-to-equity drawdown ----------------------
// Returns true when equity has fallen this far below the reference. This is
// the control that stops the account being liquidated by the broker instead.
bool MaxDrawdownBreached(double equity, double reference, double limit_pct)
{
   if(limit_pct <= 0.0 || reference <= 0.0)
      return false;
   return equity <= reference * (1.0 - limit_pct / 100.0);
}

//--- circuit breaker: loss since the start of the day --------------
bool DailyLossBreached(double equity, double day_start, double limit_pct)
{
   if(limit_pct <= 0.0 || day_start <= 0.0)
      return false;
   return equity <= day_start * (1.0 - limit_pct / 100.0);
}

//--- circuit breaker: absolute capital at risk ---------------------
bool RiskCapitalExhausted(double equity, double start_capital,
                          double risk_capital)
{
   if(risk_capital <= 0.0)
      return false;
   return start_capital - equity >= risk_capital;
}

//--- the lot the next rung needs ---------------------------------
double RungLot(double base, double mult, int rung)
{
   double lot = base;
   for(int i = 1; i < rung; i++)
      lot *= mult;
   return lot;
}

//--- normalise a lot to what a broker will actually accept ---------
// Rounds to the lot step and clamps to min/max. Brokers reject orders that
// skip this, and a rejected rung silently turns a ladder into a naked loss.
double NormaliseLot(double lot, double min_lot, double max_lot,
                    double lot_step)
{
   if(lot_step <= 0.0)
      lot_step = 0.01;
   double steps = lot / lot_step;
   long whole = (long)steps;               // truncate toward zero
   double normalised = (double)whole * lot_step;
   if(normalised < min_lot)
      normalised = min_lot;
   if(normalised > max_lot)
      normalised = max_lot;
   return normalised;
}

//--- is the spread tight enough to open into? ----------------------
bool SpreadAcceptable(int spread_points, int max_points)
{
   if(max_points <= 0)
      return true;
   return spread_points <= max_points;
}

