//+------------------------------------------------------------------+
//|                                            RuleOP_Ladder.mq4     |
//|  Visualises a "Rule OP / No Loss" grid + martingale ladder.      |
//|                                                                  |
//|  What it draws, for the stack you are actually in (or the one    |
//|  you are about to open):                                         |
//|    - every rung of the ladder, with its lot size                 |
//|    - the basket take profit, which moves as rungs are added      |
//|    - the KILL PRICE: where the broker stops the account out      |
//|    - the deepest rung this balance can survive                   |
//|                                                                  |
//|  It shows you the trap; it does not trade.                       |
//+------------------------------------------------------------------+
#property copyright "kkk"
#property version   "1.00"
#property strict
#property indicator_chart_window

//--- inputs --------------------------------------------------------
input double InpBaseLot      = 0.01;   // First lot size
input int    InpTakeProfit   = 20;     // Basket take profit (pips)
input int    InpStep         = 30;     // Pips adverse before next rung
input double InpMultiplier   = 2.0;    // Martingale multiplier
input int    InpMaxRungs     = 12;     // Rungs to draw
input int    InpDirection    = 1;      // +1 = buy ladder, -1 = sell ladder
input double InpAnchorPrice  = 0.0;    // First entry price (0 = current Bid)
input int    InpMagic        = 0;      // Magic number of your EA (0 = preview mode)
input bool   InpAlertNextRung = true;  // Alert when price reaches next rung
input bool   InpAlertKillZone = true;  // Alert inside 20% of the kill zone
input bool   InpShowPanel     = true;  // Show the account panel
input double InpManualTickVal = 0.0;   // Override tick value per lot (0 = auto)

//--- CORE BEGIN ----------------------------------------------------
// Everything between the CORE markers is plain arithmetic: no MT4 API,
// no strings, no drawing. The Makefile extracts it verbatim and compiles
// it as C++17 so the exact same code can be unit tested off-platform.
// Keep this section valid in both MQL4 and C++.

#ifndef NOLOSS_NO_CORE

#define NOLOSS_MAX_RUNGS 64

struct LadderSpec
{
   double first_entry;   // price of rung 1
   double step;          // adverse price distance between rungs
   double take_profit;   // basket take profit, in price units
   double base_lot;      // lot of rung 1
   double multiplier;    // lot multiplier per rung
   int    dir;           // +1 buy ladder (price falling), -1 sell ladder
};

struct AccountSpec
{
   double balance;
   double contract_size; // units per 1.00 lot, normally 100000
   double margin_rate;   // 1/leverage, e.g. 0.002 for 1:500
   double stopout_pct;   // stop out level, 0.5 = 50% of used margin
   double price;         // current price used for margin valuation
};

//--- entry price of rung n (1-based) -------------------------------
double LadderEntry(LadderSpec s, const int rung)
{
   return s.first_entry - s.dir * (rung - 1) * s.step;
}

//--- lot of rung n (1-based) ---------------------------------------
double LadderLot(LadderSpec s, const int rung)
{
   double lot = s.base_lot;
   for(int i = 1; i < rung; i++)
      lot *= s.multiplier;
   return lot;
}

//--- total lot held after opening rungs 1..rung --------------------
double LadderCumLot(LadderSpec s, const int rung)
{
   double total = 0.0;
   for(int i = 1; i <= rung; i++)
      total += LadderLot(s, i);
   return total;
}

//--- volume weighted average entry of rungs 1..rung ----------------
double LadderAvgEntry(LadderSpec s, const int rung)
{
   double total = LadderCumLot(s, rung);
   if(total <= 0.0)
      return s.first_entry;
   double weighted = 0.0;
   for(int i = 1; i <= rung; i++)
      weighted += LadderEntry(s, i) * LadderLot(s, i);
   return weighted / total;
}

//--- basket take profit price once `rung` rungs are open -----------
// The whole stack closes here. This is the level that drifts towards
// the market every time a rung is added, which is why the system feels
// like it always recovers.
//
// Sign check, because it is easy to get backwards: for a BUY ladder the
// adverse direction is DOWN, so the rungs step down and the average entry
// drifts down; the basket TP sits ABOVE it and price rallies into it.
// For a SELL ladder the adverse direction is UP, the rungs step up, the
// average entry drifts up, and the basket TP sits above it again - price
// still has to fall back through it. So in both cases it is plus dir.
double LadderBasketTP(LadderSpec s, const int rung)
{
   return LadderAvgEntry(s, rung) + s.dir * s.take_profit;
}

//--- profit booked when the basket take profit is hit --------------
// Always exactly cumLot * tp * tick_value, at every rung depth. This
// is the arithmetic behind the "no loss" claim: the basket TP sits at
// the average entry, so reaching it puts the whole stack in profit.
double LadderBasketTPProfit(LadderSpec s, const int rung,
                            const double tick_value)
{
   return LadderCumLot(s, rung) * s.take_profit * tick_value;
}

//--- open P&L of rungs 1..rung at price p, in currency -------------
double LadderFloating(LadderSpec s, const int rung, const double p,
                      const double tick_value)
{
   double pnl = 0.0;
   for(int i = 1; i <= rung; i++)
      pnl += (p - LadderEntry(s, i)) * s.dir * LadderLot(s, i) * tick_value;
   return pnl;
}

//--- margin locked up by rungs 1..rung -----------------------------
double LadderMargin(LadderSpec s, AccountSpec a, const int rung)
{
   return LadderCumLot(s, rung) * a.contract_size * a.margin_rate * a.price;
}

//--- rung number at price p (1-based), clamped ---------------------
int RungAtPrice(LadderSpec s, const double p)
{
   if(s.step <= 0.0)
      return 1;
   double adverse = s.dir * (s.first_entry - p);
   if(adverse < 0.0)
      return 1;
   // integer division, no library call: keeps this core compilable
   // as plain C++ as well as MQL4
   int full_steps = (int)(adverse / s.step);
   return full_steps + 1;
}

//--- can this balance still open rung n? ---------------------------
// True when the equity after the rung is opened stays above the
// broker's stop out level.
bool RungIsSurvivable(LadderSpec s, AccountSpec a, const int rung,
                      const double tick_value)
{
   double entry = LadderEntry(s, rung);
   double floating = LadderFloating(s, rung, entry, tick_value);
   double equity = a.balance + floating;
   double margin = LadderMargin(s, a, rung);
   if(margin <= 0.0)
      return equity > 0.0;
   return equity > a.stopout_pct * margin;
}

//--- deepest rung this account can open ----------------------------
// Beyond this the next rung stops the account out.
int MaxAffordableRung(LadderSpec s, AccountSpec a,
                      const double tick_value, const int max_rungs)
{
   int cap = max_rungs;
   if(cap > NOLOSS_MAX_RUNGS)
      cap = NOLOSS_MAX_RUNGS;
   int best = 0;
   for(int n = 1; n <= cap; n++)
   {
      if(!RungIsSurvivable(s, a, n, tick_value))
         return best;
      best = n;
   }
   return best;
}

//--- the kill price ------------------------------------------------
// The price at which equity falls to the stop out level, holding the
// whole ladder 1..rung open. Returns 0 when there is no such price
// (the account cannot be stopped out at this depth).
double KillPrice(LadderSpec s, AccountSpec a, const int rung,
                 const double tick_value)
{
   double total = LadderCumLot(s, rung);
   if(total <= 0.0)
      return 0.0;
   double margin = LadderMargin(s, a, rung);
   double stop_equity = a.stopout_pct * margin;
   // equity = balance + dir*(p - avg)*total*tick_value = stop_equity
   double drift = a.balance - stop_equity;
   if(s.dir > 0)
   {
      if(drift <= 0.0)
         return LadderEntry(s, rung);   // already dead at the last rung
      return LadderAvgEntry(s, rung) - drift / (total * tick_value);
   }
   if(drift <= 0.0)
      return LadderEntry(s, rung);
   return LadderAvgEntry(s, rung) + drift / (total * tick_value);
}

#endif // NOLOSS_NO_CORE

//--- CORE END ------------------------------------------------------

#ifndef NOLOSS_CORE_ONLY
//--- MT4 side: conversion helpers, live orders, drawing -------------

string ObjPrefix;
datetime LastRungAlert;
datetime LastKillAlert;

double PipSize()
{
   double p = Point;
   if(Digits == 3 || Digits == 5)
      p *= 10.0;
   return p;
}

//--- account currency value of ONE FULL PRICE UNIT on 1.00 lot -----
// For a standard EURUSD lot this is 100000. Tick value is quoted per tick
// size, so the ratio converts it to a per-price-unit figure.
//
// MQL4 has no predefined TickValue/TickSize variables - they have to come
// from MarketInfo(). This was a compile error before.
double TickValuePerLot()
{
   if(InpManualTickVal > 0.0)
      return InpManualTickVal;
   double tick_value = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tick_size  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tick_value <= 0.0 || tick_size <= 0.0)
      return 100000.0;
   return tick_value / tick_size;
}

LadderSpec MakeSpec(const double anchor, const double pip)
{
   LadderSpec s;
   s.first_entry = anchor;
   s.step        = InpStep * pip;
   s.take_profit = InpTakeProfit * pip;
   s.base_lot    = InpBaseLot;
   s.multiplier  = InpMultiplier;
   s.dir         = (InpDirection < 0 ? -1 : 1);
   return s;
}

AccountSpec MakeAccount()
{
   AccountSpec a;
   a.balance      = AccountBalance();
   a.contract_size = 100000.0;   // units per 1.00 lot
   a.margin_rate  = (AccountLeverage() > 0 ? 1.0 / (double)AccountLeverage() : 0.002);
   a.stopout_pct  = AccountStopoutLevel() / 100.0;
   if(a.stopout_pct <= 0.0)
      a.stopout_pct = 0.5;
   a.price        = Bid;
   return a;
}

//--- adopt the real ladder if the EA has orders open ---------------
// Returns the entry price of rung 1, and sets `rungs` to how many
// positions are actually open. In preview mode (magic 0 or no orders)
// it anchors at the current price with one rung.
double LiveAnchor(int &rungs, int &dir)
{
   rungs = 0;
   dir = (InpDirection < 0 ? -1 : 1);
   double best = 0.0;
   datetime best_time = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      if(InpMagic != 0 && OrderMagicNumber() != InpMagic)
         continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;
      int d = (OrderType() == OP_BUY ? 1 : -1);
      if(rungs == 0)
      {
         dir = d;
         best = OrderOpenPrice();
         best_time = OrderOpenTime();
      }
      else if(d != dir)
         continue;
      // Rung 1 is the FIRST position opened. In an averaging-down ladder the
      // first buy is at the HIGHEST price and each later rung is lower, so
      // for a buy ladder rung 1 is the highest entry and for a sell ladder
      // the lowest. Getting this backwards draws the whole ladder from the
      // wrong end, which is what this did before.
      // Where two orders share a price, the older one is rung 1.
      const bool better_price =
         (d > 0 ? OrderOpenPrice() > best : OrderOpenPrice() < best);
      const bool older_at_same_price =
         OrderOpenPrice() == best && OrderOpenTime() < best_time;
      if(better_price || older_at_same_price)
      {
         best = OrderOpenPrice();
         best_time = OrderOpenTime();
      }
      rungs++;
   }
   if(rungs == 0)
   {
      if(InpAnchorPrice > 0.0)
         return InpAnchorPrice;
      return Bid;
   }
   return best;
}

void DrawHLine(const string name, const double price, const color col,
               const int width, const string label)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetString(0, name, OBJPROP_TEXT, label);
}

void DrawRung(const int i, const double price, const double lot,
              const bool survivable)
{
   string n = ObjPrefix + "rung" + IntegerToString(i);
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_ARROW_RIGHT_PRICE, 0, Time[0], price);
   ObjectSetDouble(0, n, OBJPROP_PRICE, price);
   ObjectSetInteger(0, n, OBJPROP_COLOR, survivable ? clrDodgerBlue : clrCrimson);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
   ObjectSetString(0, n, OBJPROP_TEXT,
                   "rung " + IntegerToString(i) + "  lot " +
                   DoubleToString(lot, 2));
}

void HideFrom(const int from)
{
   for(int i = from; i <= NOLOSS_MAX_RUNGS; i++)
   {
      string n = ObjPrefix + "rung" + IntegerToString(i);
      if(ObjectFind(0, n) >= 0)
         ObjectDelete(0, n);
   }
}

void AlertOnce(datetime &last, const string msg)
{
   if(TimeCurrent() - last < 300)
      return;
   last = TimeCurrent();
   Alert(Symbol(), " ", msg);
}

//+------------------------------------------------------------------+
int OnInit()
{
   ObjPrefix = "RuleOP_";
   IndicatorShortName("RuleOP Ladder");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, ObjPrefix);
   Comment("");
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   double pip = PipSize();

   int live_rungs = 0, live_dir = 0;
   double anchor = LiveAnchor(live_rungs, live_dir);

   LadderSpec s = MakeSpec(anchor, pip);
   if(live_rungs > 0)
      s.dir = live_dir;
   AccountSpec a = MakeAccount();

   // value of one full price unit on 1.00 lot, in account currency
   double tv = TickValuePerLot();

   int rung_now = RungAtPrice(s, Bid);
   if(live_rungs > 0 && rung_now < live_rungs)
      rung_now = live_rungs;
   if(rung_now > InpMaxRungs)
      rung_now = InpMaxRungs;

   int max_ok = MaxAffordableRung(s, a, tv, InpMaxRungs);

   //--- draw the ladder --------------------------------------------
   for(int n = 1; n <= InpMaxRungs; n++)
   {
      if(n > max_ok + 1)
         break;
      DrawRung(n, LadderEntry(s, n), LadderLot(s, n), n <= max_ok);
   }
   int keep_until = max_ok + 1;
   if(keep_until > InpMaxRungs)
      keep_until = InpMaxRungs;
   HideFrom(keep_until + 1);

   //--- basket take profit and kill price ---------------------------
   DrawHLine(ObjPrefix + "avg", LadderAvgEntry(s, rung_now), clrGray, 1,
             "average entry " + DoubleToString(LadderAvgEntry(s, rung_now), Digits));
   DrawHLine(ObjPrefix + "tp", LadderBasketTP(s, rung_now), clrLime, 2,
             "basket TP  +$" +
             DoubleToString(LadderBasketTPProfit(s, rung_now, tv), 2));

   double kill = KillPrice(s, a, MathMax(max_ok, 1), tv);
   if(kill > 0.0)
      DrawHLine(ObjPrefix + "kill", kill, clrRed, 2,
                "KILL PRICE  " + DoubleToString(kill, Digits));

   //--- alerts ------------------------------------------------------
   if(InpAlertNextRung && rung_now < InpMaxRungs)
   {
      double next = LadderEntry(s, rung_now + 1);
      double dist = MathAbs(Bid - next);
      if(dist < 2.0 * pip)
         AlertOnce(LastRungAlert, "rung " + IntegerToString(rung_now + 1) +
                   " at " + DoubleToString(next, Digits) + "  lot " +
                   DoubleToString(LadderLot(s, rung_now + 1), 2));
   }
   if(InpAlertKillZone && kill > 0.0)
   {
      double span = MathAbs(kill - anchor);
      if(span > 0.0 && MathAbs(Bid - kill) < 0.2 * span)
         AlertOnce(LastKillAlert, "inside the kill zone, " +
                   DoubleToString(MathAbs(Bid - kill) / pip, 1) + " pips out");
   }

   //--- panel -------------------------------------------------------
   if(InpShowPanel)
   {
      string txt = "";
      txt += "RULE OP LADDER  ";
      txt += (s.dir > 0 ? "BUY" : "SELL");
      txt += "\n";
      txt += "rung now        " + IntegerToString(rung_now) + "\n";
      txt += "total lot       " + DoubleToString(LadderCumLot(s, rung_now), 2) + "\n";
      txt += "average entry   " + DoubleToString(LadderAvgEntry(s, rung_now), Digits) + "\n";
      txt += "basket TP       " +
             DoubleToString(LadderBasketTP(s, rung_now), Digits) + "   +$" +
             DoubleToString(LadderBasketTPProfit(s, rung_now, tv), 2) + "\n";
      txt += "open P&L        $" +
             DoubleToString(LadderFloating(s, rung_now, Bid, tv), 2) + "\n";
      txt += "margin used     $" + DoubleToString(LadderMargin(s, a, rung_now), 2) + "\n";
      txt += "-----------------------------\n";
      txt += "deepest rung you can open   " + IntegerToString(max_ok) + "\n";
      if(max_ok > 0)
         txt += "kill price                  " +
                DoubleToString(KillPrice(s, a, max_ok, tv), Digits) + "   (" +
                DoubleToString(MathAbs(Bid - KillPrice(s, a, max_ok, tv)) / pip, 0) +
                " pips away)\n";
      else
         txt += "kill price                  ALREADY PAST IT\n";
      txt += "adverse move to rung " + IntegerToString(max_ok) + "   " +
             DoubleToString((max_ok - 1) * InpStep, 0) + " pips\n";
      Comment(txt);
   }
   return(rates_total);
}
#endif // NOLOSS_CORE_ONLY
//+------------------------------------------------------------------+
