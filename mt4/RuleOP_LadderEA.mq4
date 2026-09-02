//+------------------------------------------------------------------+
//|                                              RuleOP_LadderEA.mq4 |
//|                                                                  |
//|  Executes the Rule OP ladder WITH HARD CIRCUIT BREAKERS.         |
//|                                                                  |
//|  Read this before you run it anywhere.                           |
//|                                                                  |
//|  The ladder this trades is a negative-expectation system. Over    |
//|  600 simulated $100 accounts it returned -9.7% of capital, and    |
//|  80% of those accounts never completed the run. Nothing in this   |
//|  file changes that. It exists so that if you trade it anyway,     |
//|  you trade it with a stop that actually fires.                    |
//|                                                                  |
//|  The single useful control here is InpMaxDrawdownPct. It closes   |
//|  the whole stack and stops trading for the day. Without it, the   |
//|  system's designed behaviour is to hold a losing ladder until     |
//|  the broker liquidates you. With it, you decide the number        |
//|  instead of the broker deciding for you.                         |
//+------------------------------------------------------------------+
#property copyright "kkk"
#property version   "1.00"
#property strict

//--- ladder --------------------------------------------------------
input double InpBaseLot        = 0.01;  // First lot size
input int    InpTakeProfit     = 20;    // Basket take profit (pips)
input int    InpStep           = 30;    // Pips adverse before next rung
input double InpMultiplier     = 2.0;   // Martingale multiplier
input int    InpMaxRungs       = 4;     // Hard cap on ladder depth
input int    InpDirection      = 1;     // +1 buy ladder, -1 sell ladder

//--- risk. Leave all of these on. ----------------------------------
input bool   InpUseRisk        = true;  // Enable the circuit breakers
input double InpMaxDrawdownPct = 15.0;  // Close all + stop, % off the start
input double InpMaxDailyLossPct= 10.0;  // Close all + stop for the day, %
input double InpRiskCapital    = 100.0; // Capital you are willing to lose, USD
input int    InpMaxSpreadPts   = 30;    // Do not open into a wider spread

//--- plumbing ------------------------------------------------------
input int    InpMagic          = 20240917;
input bool   InpOneCycleOnly   = false; // Close the stack and stop for good
input bool   InpVerbose        = true;  // Log every decision

//--- EA CORE BEGIN -------------------------------------------------
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

//--- EA CORE END ---------------------------------------------------

#ifndef NOLOSS_CORE_ONLY
//--- MT4 side ------------------------------------------------------

double g_first_entry;
int    g_rungs;
double g_peak_equity;
double g_day_start_equity;
double g_session_start_equity;
datetime g_day;
bool   g_halted_today;
bool   g_finished;

double PipSize()
{
   double p = Point;
   if(Digits == 3 || Digits == 5)
      p *= 10.0;
   return p;
}

double TickValuePerLot()
{
   double tick_value = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tick_size  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tick_value <= 0.0 || tick_size <= 0.0)
      return 100000.0;
   return tick_value / tick_size;
}

void Log(const string msg)
{
   if(InpVerbose)
      Print("RuleOP_EA: ", msg);
}

//--- count our own open positions and find the deepest entry -------
void ScanStack()
{
   int count = 0;
   double deepest = 0.0;
   int dir = (InpDirection < 0 ? -1 : 1);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      int d = (OrderType() == OP_BUY ? 1 : -1);
      if(count == 0)
      {
         dir = d;
         deepest = OrderOpenPrice();
      }
      else if(d != dir)
         continue;
      // the deepest entry is the most recent rung: lowest for a buy ladder
      if((d > 0 && OrderOpenPrice() < deepest) ||
         (d < 0 && OrderOpenPrice() > deepest))
         deepest = OrderOpenPrice();
      count++;
   }
   g_rungs = count;
   if(count > 0)
      g_first_entry = deepest;
}

bool CloseEverything(const string why)
{
   bool all_closed = true;
   for(int pass = 0; pass < 3; pass++)
   {
      bool any_left = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            continue;
         if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic)
            continue;
         if(OrderType() != OP_BUY && OrderType() != OP_SELL)
            continue;
         any_left = true;
         double px = (OrderType() == OP_BUY ? Bid : Ask);
         if(!OrderClose(OrderTicket(), OrderLots(), px, 30, clrYellow))
            all_closed = false;
      }
      if(!any_left)
         break;
   }
   Log("closed the whole stack: " + why);
   return all_closed;
}

bool OpenRung(const int rung)
{
   double lot = NormaliseLot(RungLot(InpBaseLot, InpMultiplier, rung),
                             MarketInfo(Symbol(), MODE_MINLOT),
                             MarketInfo(Symbol(), MODE_MAXLOT),
                             MarketInfo(Symbol(), MODE_LOTSTEP));
   if(!SpreadAcceptable((int)MarketInfo(Symbol(), MODE_SPREAD),
                        InpMaxSpreadPts))
   {
      Log("spread too wide to open rung " + IntegerToString(rung));
      return false;
   }
   bool is_buy = (InpDirection > 0);
   double px = (is_buy ? Ask : Bid);
   int type = (is_buy ? OP_BUY : OP_SELL);
   int ticket = OrderSend(Symbol(), type, lot, px, 30, 0, 0,
                          "RuleOP rung " + IntegerToString(rung),
                          InpMagic, 0, clrAqua);
   if(ticket < 0)
   {
      Log("OrderSend failed for rung " + IntegerToString(rung) +
          ", error " + IntegerToString(GetLastError()));
      return false;
   }
   g_first_entry = px;
   Log("opened rung " + IntegerToString(rung) + " at " +
       DoubleToString(px, Digits) + " lot " + DoubleToString(lot, 2));
   return true;
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_peak_equity          = AccountEquity();
   g_day_start_equity     = AccountEquity();
   g_session_start_equity = AccountEquity();
   g_day                  = 0;
   g_halted_today         = false;
   g_finished             = false;
   g_rungs                = 0;
   g_first_entry          = 0.0;

   if(InpRiskCapital >= AccountBalance())
   {
      Alert("RuleOP_EA: InpRiskCapital (", DoubleToString(InpRiskCapital, 2),
            ") is greater than or equal to your balance (",
            DoubleToString(AccountBalance(), 2),
            "). That is not a risk limit, that is the whole account. Refusing "
            "to start.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   Log("started. peak equity " + DoubleToString(g_peak_equity, 2));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- reset the daily reference at midnight ----------------------
   datetime today = iTime(Symbol(), PERIOD_D1, 0);
   if(today != g_day)
   {
      g_day = today;
      g_day_start_equity = AccountEquity();
      g_halted_today = false;
   }

   const double equity = AccountEquity();
   if(equity > g_peak_equity)
      g_peak_equity = equity;

   //--- circuit breakers, checked before anything else -------------
   if(InpUseRisk)
   {
      if(MaxDrawdownBreached(equity, g_peak_equity, InpMaxDrawdownPct))
      {
         CloseEverything("max drawdown " +
                         DoubleToString(InpMaxDrawdownPct, 1) + "% hit");
         g_finished = true;
         Alert("RuleOP_EA stopped: drawdown limit reached. Fix the settings "
               "before restarting.");
         return;
      }
      if(DailyLossBreached(equity, g_day_start_equity, InpMaxDailyLossPct))
      {
         CloseEverything("daily loss " +
                         DoubleToString(InpMaxDailyLossPct, 1) + "% hit");
         g_halted_today = true;
         Alert("RuleOP_EA halted for today: daily loss limit reached.");
         return;
      }
      if(RiskCapitalExhausted(equity, g_session_start_equity,
                              InpRiskCapital))
      {
         CloseEverything("risk capital of " +
                         DoubleToString(InpRiskCapital, 2) + " exhausted");
         g_finished = true;
         Alert("RuleOP_EA stopped: you have lost the capital you said you "
               "were willing to lose.");
         return;
      }
   }

   if(g_finished || g_halted_today)
      return;

   //--- ladder management -----------------------------------------
   ScanStack();
   const double pip = PipSize();
   const double step = InpStep * pip;
   const double tp = InpTakeProfit * pip;
   const double tv = TickValuePerLot();

   if(g_rungs == 0)
   {
      OpenRung(1);
      ScanStack();
   }

   if(g_rungs > 0)
   {
      if(BasketShouldClose(g_first_entry, step, tp, InpBaseLot,
                           InpMultiplier, InpDirection, g_rungs, Bid))
      {
         CloseEverything("basket take profit");
         g_rungs = 0;
         if(InpOneCycleOnly)
         {
            g_finished = true;
            Log("one cycle only - finished");
         }
      }
      else if(NextRungDue(g_first_entry, step, InpDirection, g_rungs,
                          InpMaxRungs, Bid))
      {
         OpenRung(g_rungs + 1);
         ScanStack();
      }
   }

   //--- panel -----------------------------------------------------
   string txt = "";
   txt += "RULE OP EA\n";
   txt += "rungs open      " + IntegerToString(g_rungs) + "\n";
   if(g_rungs > 0)
   {
      txt += "basket TP       " +
             DoubleToString(EABasketTP(g_first_entry, step, tp, InpBaseLot,
                                       InpMultiplier, InpDirection, g_rungs),
                            Digits) + "\n";
   }
   txt += "equity          " + DoubleToString(equity, 2) + "\n";
   txt += "peak            " + DoubleToString(g_peak_equity, 2) + "\n";
   txt += "stop at equity  " +
          DoubleToString(g_peak_equity * (1.0 - InpMaxDrawdownPct / 100.0), 2) +
          "\n";
   txt += (g_halted_today ? "HALTED FOR TODAY\n" : "");
   txt += (g_finished ? "STOPPED\n" : "");
   Comment(txt);
}
#endif // NOLOSS_CORE_ONLY
//+------------------------------------------------------------------+
