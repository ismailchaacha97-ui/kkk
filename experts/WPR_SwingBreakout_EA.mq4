//+------------------------------------------------------------------+
//|                                        WPR_SwingBreakout_EA.mq4  |
//|  Execution / measurement EA for the WPR_SwingBreakout indicator.  |
//|                                                                   |
//|  Signals come from the indicator via iCustom (single source of    |
//|  truth).  This EA adds exits, risk sizing and - most importantly  |
//|  - an honest report including a RANDOM ENTRY CONTROL GROUP, so    |
//|  you can see whether the signal actually beats chance with the    |
//|  same exits.                                                      |
//+------------------------------------------------------------------+
#property copyright "Measurement EA for WPR_SwingBreakout"
#property version   "1.00"
#property strict
#property description "Trades WPR_SwingBreakout signals and reports win rate, R multiples and a random baseline"

enum ENUM_BREAKOUT_MODE
  {
   BRK_WICK  = 0, // Wick
   BRK_CLOSE = 1  // Close
  };

enum ENUM_TRADE_MODE
  {
   TRADE_BOTH       = 0, // Long and short
   TRADE_LONG_ONLY  = 1, // Long only
   TRADE_SHORT_ONLY = 2  // Short only
  };

//+------------------------------------------------------------------+
//| SIGNAL INPUTS - must mirror the indicator, in the same order      |
//+------------------------------------------------------------------+
input string InpIndicatorName          = "WPR_SwingBreakout"; // Indicator file name
input ENUM_BREAKOUT_MODE InpMode       = BRK_CLOSE; // Breakout confirmation
input int    InpWPRPeriod              = 14;        // Williams %R period
input double InpLevelUp                = -20.0;     // Upper band
input double InpLevelDn                = -80.0;     // Lower band
input int    InpLookback               = 1000;      // Bars recalculated
input bool   InpClosedBarOnly          = true;      // Closed bar signals

input bool   InpUseHTFFilter           = true;      // HTF trend filter
input ENUM_TIMEFRAMES InpHTFTimeframe  = PERIOD_H1; // Higher timeframe
input int    InpHTFPeriod              = 50;        // HTF MA period
input ENUM_MA_METHOD InpHTFMethod      = MODE_EMA;  // HTF MA method
input bool   InpUseADXFilter           = true;      // ADX regime filter
input int    InpADXPeriod              = 14;        // ADX period
input double InpADXMin                 = 20.0;      // Minimum ADX
input bool   InpUseVolFilter           = true;      // Volatility regime
input int    InpVolPeriod              = 50;        // Bars for the average ATR
input double InpVolMinRatio            = 0.70;      // ATR / average ATR, min
input double InpVolMaxRatio            = 2.50;      // ATR / average ATR, max
input bool   InpUseSpreadFilter        = true;      // Spread filter
input double InpMaxSpreadPips          = 2.0;       // Maximum spread (pips)
input bool   InpUseSessionFilter       = false;     // Session filter
input int    InpSessionStart           = 8;         // From hour
input int    InpSessionEnd             = 18;        // To hour
input bool   InpUseImpulseFilter       = true;      // Strong signal candle
input double InpImpulseMinBody         = 0.35;      // Body / range, minimum
input bool   InpUseNoChase             = true;      // No chasing
input double InpMaxChaseATR            = 1.00;      // Max distance from level
input int    InpMinBarsBetween         = 3;         // Cooldown (bars)
input int    InpATRPeriod              = 14;        // ATR period
input int    InpMinScore               = 0;         // 0 = all enabled filters must pass

//+------------------------------------------------------------------+
//| EXITS                                                             |
//+------------------------------------------------------------------+
input double InpStopLossATR            = 1.5;       // Stop loss (ATR)
input double InpTakeProfitATR          = 3.0;       // Take profit (ATR)
input bool   InpUseBreakeven           = true;      // Move to break-even
input double InpBEStartATR             = 1.0;       // Break-even trigger (ATR)
input double InpBELockPips             = 1.0;       // Break-even lock (pips)
input bool   InpUseTrailing            = true;      // Trailing stop
input double InpTrailStartATR          = 1.5;       // Trailing trigger (ATR)
input double InpTrailATR               = 1.5;       // Trailing distance (ATR)
input int    InpMaxBarsInTrade         = 0;         // Time exit (bars, 0 = off)
input bool   InpReverseOnSignal        = true;      // Reverse on opposite signal

//+------------------------------------------------------------------+
//| RISK                                                              |
//+------------------------------------------------------------------+
input double InpLots                   = 0.10;      // Fixed lot size
input bool   InpUseRiskPercent         = false;     // Size by risk %
input double InpRiskPercent            = 1.0;       // Risk per trade (%)
input int    InpSlippagePips           = 1;         // Max slippage (pips)
input double InpMaxEntrySpreadPips     = 3.0;       // Skip entry if spread above
input ENUM_TRADE_MODE InpTradeMode     = TRADE_BOTH;// Direction filter
input int    InpMagic                  = 20260828;  // Magic number

//+------------------------------------------------------------------+
//| CONTROL GROUP                                                     |
//+------------------------------------------------------------------+
input bool   InpRandomBaseline         = false;     // Random entries, same exits
input int    InpRandSeed               = 42;        // Random seed
input int    InpRandEveryNBars         = 20;        // 1 entry attempt per N bars

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
datetime g_lastBar      = 0;
int      g_digits       = 5;
double   g_point        = 0.0;
double   g_pip          = 0.0;
double   g_tickValue    = 0.0;
double   g_tickSize     = 0.0;
double   g_minLot       = 0.01;
double   g_maxLot       = 100.0;
double   g_lotStep      = 0.01;
int      g_stopLevel    = 0;

//--- current position
int      g_ticket       = 0;
int      g_type         = -1;
double   g_entryPrice   = 0.0;
double   g_initialSL    = 0.0;
int      g_barsInTrade  = 0;

//--- statistics
int      g_trades       = 0;
int      g_wins         = 0;
int      g_losses       = 0;
double   g_grossProfit  = 0.0;
double   g_grossLoss    = 0.0;
double   g_netProfit    = 0.0;
double   g_sumR         = 0.0;
double   g_peakEquity   = 0.0;
double   g_maxDD        = 0.0;
double   g_maxDDpct     = 0.0;

//+------------------------------------------------------------------+
//| Read a signal buffer from the indicator                           |
//+------------------------------------------------------------------+
double GetSignal(const int buffer, const int shift)
  {
   return(iCustom(_Symbol, _Period, InpIndicatorName,
                  InpMode, InpWPRPeriod, InpLevelUp, InpLevelDn, InpLookback, InpClosedBarOnly,
                  InpUseHTFFilter, InpHTFTimeframe, InpHTFPeriod, InpHTFMethod,
                  InpUseADXFilter, InpADXPeriod, InpADXMin,
                  InpUseVolFilter, InpVolPeriod, InpVolMinRatio, InpVolMaxRatio,
                  InpUseSpreadFilter, InpMaxSpreadPips,
                  InpUseSessionFilter, InpSessionStart, InpSessionEnd,
                  InpUseImpulseFilter, InpImpulseMinBody,
                  InpUseNoChase, InpMaxChaseATR,
                  InpMinBarsBetween, InpATRPeriod, InpMinScore,
                  buffer, shift));
  }

//+------------------------------------------------------------------+
//| Slippage in points                                                |
//+------------------------------------------------------------------+
int SlippagePoints()
  {
   int sl = (int)MathRound(InpSlippagePips * g_pip / g_point);
   return(sl > 0 ? sl : 1);
  }

//+------------------------------------------------------------------+
//| Position sizing                                                   |
//+------------------------------------------------------------------+
double CalcLots(const double slDistance)
  {
   double lots = InpLots;

   if(InpUseRiskPercent && slDistance > 0.0 && g_tickSize > 0.0 && g_tickValue > 0.0)
     {
      double riskMoney   = AccountBalance() * InpRiskPercent / 100.0;
      double oneLotLoss  = slDistance / g_tickSize * g_tickValue;
      if(oneLotLoss > 0.0)
         lots = riskMoney / oneLotLoss;
     }

   lots = MathMax(g_minLot, MathMin(g_maxLot, lots));
   if(g_lotStep > 0.0)
      lots = MathFloor(lots / g_lotStep + 0.0000001) * g_lotStep;
   lots = MathMax(g_minLot, MathMin(g_maxLot, lots));
   return(NormalizeDouble(lots, 2));
  }

//+------------------------------------------------------------------+
//| Is the ticket still open?                                         |
//+------------------------------------------------------------------+
bool IsOpen(const int ticket)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderTicket() == ticket && OrderCloseTime() == 0)
            return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Record a closed trade into the statistics                         |
//+------------------------------------------------------------------+
void RecordTrade(const int ticket)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_HISTORY))
     {
      Print("RecordTrade: cannot select #", ticket, " in history, error ", GetLastError());
      return;
     }

   double profit = OrderProfit() + OrderSwap() + OrderCommission();
   double lots   = OrderLots();

   double riskMoney = 0.0;
   if(g_initialSL > 0.0 && g_tickSize > 0.0 && g_tickValue > 0.0)
      riskMoney = MathAbs(g_entryPrice - g_initialSL) / g_tickSize * g_tickValue * lots;

   g_trades++;
   g_netProfit += profit;
   if(profit >= 0.0) { g_wins++;        g_grossProfit += profit; }
   else              { g_losses++;      g_grossLoss   += -profit; }
   if(riskMoney > 0.0)
      g_sumR += profit / riskMoney;
  }

//+------------------------------------------------------------------+
//| Close a position and record it                                    |
//+------------------------------------------------------------------+
bool ClosePosition(const int ticket)
  {
   for(int attempt = 0; attempt < 3; attempt++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
         return(false);

      double price = (OrderType() == OP_BUY) ? Bid : Ask;
      price = NormalizeDouble(price, g_digits);
      RefreshRates();

      if(OrderClose(ticket, OrderLots(), price, SlippagePoints(), clrNONE))
        {
         RecordTrade(ticket);
         if(g_ticket == ticket)
            g_ticket = 0;
         return(true);
        }

      int err = GetLastError();
      Print("OrderClose #", ticket, " failed, error ", err);
      RefreshRates();
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Open a position                                                   |
//+------------------------------------------------------------------+
bool OpenPosition(const int cmd)
  {
   double atr = iATR(_Symbol, _Period, InpATRPeriod, 0);
   if(atr <= 0.0)
      return(false);

   double price  = (cmd == OP_BUY) ? Ask : Bid;
   double slDist = InpStopLossATR   * atr;
   double tpDist = InpTakeProfitATR * atr;

//--- respect the broker's minimum stop distance
   double minDist = (g_stopLevel + 2) * g_point;
   if(slDist < minDist) slDist = minDist;
   if(tpDist < minDist) tpDist = minDist;

   double sl = (cmd == OP_BUY) ? price - slDist : price + slDist;
   double tp = (cmd == OP_BUY) ? price + tpDist : price - tpDist;
   sl = NormalizeDouble(sl, g_digits);
   tp = NormalizeDouble(tp, g_digits);

   double lots = CalcLots(slDist);
   int ticket  = OrderSend(_Symbol, cmd, lots, NormalizeDouble(price, g_digits),
                           SlippagePoints(), sl, tp, "WPR SB", InpMagic, 0, clrNONE);
   if(ticket < 0)
     {
      Print("OrderSend failed, error ", GetLastError());
      return(false);
     }

   g_ticket      = ticket;
   g_type        = cmd;
   g_entryPrice  = price;
   g_initialSL   = sl;
   g_barsInTrade = 0;
   Print("Opened #", ticket, (cmd == OP_BUY ? " BUY " : " SELL "), DoubleToString(lots, 2),
         " @ ", DoubleToString(price, g_digits),
         " SL ", DoubleToString(sl, g_digits), " TP ", DoubleToString(tp, g_digits));
   return(true);
  }

//+------------------------------------------------------------------+
//| Trailing, break-even and time exit                                |
//+------------------------------------------------------------------+
void ManagePosition()
  {
   if(g_ticket == 0)
      return;
   if(!OrderSelect(g_ticket, SELECT_BY_TICKET, MODE_TRADES))
      return;

   int    type  = OrderType();
   double curSL = OrderStopLoss();
   double curTP = OrderTakeProfit();

//--- time exit
   if(InpMaxBarsInTrade > 0 && g_barsInTrade >= InpMaxBarsInTrade)
     {
      Print("Time exit after ", g_barsInTrade, " bars");
      ClosePosition(g_ticket);
      return;
     }

   double atr = iATR(_Symbol, _Period, InpATRPeriod, 0);
   if(atr <= 0.0)
      return;

   double minDist = (g_stopLevel + 2) * g_point;
   bool   have    = false;    // do we have a candidate stop?
   double cand    = 0.0;      // candidate stop price

   if(type == OP_BUY)
     {
      double profitDist = Bid - g_entryPrice;
      if(InpUseBreakeven && profitDist >= InpBEStartATR * atr)
        { cand = g_entryPrice + InpBELockPips * g_pip; have = true; }
      if(InpUseTrailing && profitDist >= InpTrailStartATR * atr)
        {
         double t = Bid - InpTrailATR * atr;
         if(!have || t > cand) { cand = t; have = true; }
        }
      if(!have)
         return;
      double target = (curSL > 0.0) ? MathMax(curSL, cand) : cand;
      if((curSL <= 0.0 || target > curSL + g_point * 0.5) && (Bid - target) >= minDist)
         if(!OrderModify(g_ticket, OrderOpenPrice(), NormalizeDouble(target, g_digits),
                         curTP, 0, clrNONE))
            Print("OrderModify failed, error ", GetLastError());
     }
   else
      if(type == OP_SELL)
        {
         double profitDist = g_entryPrice - Ask;
         if(InpUseBreakeven && profitDist >= InpBEStartATR * atr)
           { cand = g_entryPrice - InpBELockPips * g_pip; have = true; }
         if(InpUseTrailing && profitDist >= InpTrailStartATR * atr)
           {
            double t = Ask + InpTrailATR * atr;
            if(!have || t < cand) { cand = t; have = true; }
           }
         if(!have)
            return;
         double target = (curSL > 0.0) ? MathMin(curSL, cand) : cand;
         if((curSL <= 0.0 || target < curSL - g_point * 0.5) && (target - Ask) >= minDist)
            if(!OrderModify(g_ticket, OrderOpenPrice(), NormalizeDouble(target, g_digits),
                            curTP, 0, clrNONE))
               Print("OrderModify failed, error ", GetLastError());
        }
  }

//+------------------------------------------------------------------+
//| Drawdown tracking                                                 |
//+------------------------------------------------------------------+
void TrackEquity()
  {
   double eq = AccountEquity();
   if(eq > g_peakEquity) g_peakEquity = eq;
   double dd = g_peakEquity - eq;
   if(dd > g_maxDD) g_maxDD = dd;
   double pct = (g_peakEquity > 0.0) ? 100.0 * dd / g_peakEquity : 0.0;
   if(pct > g_maxDDpct) g_maxDDpct = pct;
  }

//+------------------------------------------------------------------+
//| Signal check (one evaluation per new bar)                         |
//+------------------------------------------------------------------+
void CheckForSignal()
  {
   double buy  = GetSignal(0, 1);   // buffer 0, last closed bar
   double sell = GetSignal(1, 1);   // buffer 1, last closed bar

   bool sigBuy  = (buy  != EMPTY_VALUE);
   bool sigSell = (sell != EMPTY_VALUE);
   if(!sigBuy && !sigSell)
      return;
   if(sigBuy  && InpTradeMode == TRADE_SHORT_ONLY) return;
   if(sigSell && InpTradeMode == TRADE_LONG_ONLY)  return;

   int wanted = sigBuy ? OP_BUY : OP_SELL;

//--- already in that direction?
   if(g_ticket != 0)
     {
      if(!OrderSelect(g_ticket, SELECT_BY_TICKET, MODE_TRADES)) return;
      if(OrderType() == wanted)      return;              // nothing to do
      if(!InpReverseOnSignal)        return;              // hold, let SL/TP decide
      ClosePosition(g_ticket);                            // reverse
     }

//--- live spread guard
   double spreadPips = (Ask - Bid) / ((g_pip > 0.0) ? g_pip : g_point);
   if(spreadPips > InpMaxEntrySpreadPips)
     {
      Print("Entry skipped, spread ", DoubleToString(spreadPips, 1), " pips");
      return;
     }

   OpenPosition(wanted);
  }

//+------------------------------------------------------------------+
//| Random control group: same exits, random entries                  |
//+------------------------------------------------------------------+
void MaybeRandomEntry()
  {
   if(g_ticket != 0)
      return;
   if(InpRandEveryNBars <= 1 || (MathRand() % InpRandEveryNBars) != 0)
      return;

   int cmd = (MathRand() % 2 == 0) ? OP_BUY : OP_SELL;
   if(InpTradeMode == TRADE_LONG_ONLY)  cmd = OP_BUY;
   if(InpTradeMode == TRADE_SHORT_ONLY) cmd = OP_SELL;

   double spreadPips = (Ask - Bid) / ((g_pip > 0.0) ? g_pip : g_point);
   if(spreadPips > InpMaxEntrySpreadPips)
      return;

   OpenPosition(cmd);
  }

//+------------------------------------------------------------------+
//| Final report                                                      |
//+------------------------------------------------------------------+
void PrintReport()
  {
   double winRate = (g_trades > 0) ? 100.0 * g_wins / g_trades : 0.0;
   double pf      = (g_grossLoss > 0.0) ? g_grossProfit / g_grossLoss
                                        : ((g_grossProfit > 0.0) ? 999.99 : 0.0);
   double avgR    = (g_trades > 0) ? g_sumR / g_trades : 0.0;
   double rr      = (InpStopLossATR > 0.0) ? InpTakeProfitATR / InpStopLossATR : 0.0;
   double beWR    = (rr > 0.0) ? 100.0 / (1.0 + rr) : 0.0;
   double avgWin  = (g_wins   > 0) ? g_grossProfit / g_wins   : 0.0;
   double avgLoss = (g_losses > 0) ? g_grossLoss   / g_losses : 0.0;

   Print("===================================================================");
   Print(" WPR Swing Breakout - report");
   Print(" Mode                 : ", (InpRandomBaseline ? "*** RANDOM BASELINE (control group) ***" : "signal driven"));
   Print(" Symbol / period      : ", _Symbol, " / ", Period());
   Print("-------------------------------------------------------------------");
   PrintFormat(" Trades              : %d  (wins %d / losses %d)", g_trades, g_wins, g_losses);
   PrintFormat(" Win rate            : %.2f %%", winRate);
   PrintFormat(" TP:SL               : %.2f : 1  ->  break-even win rate %.1f %% (before costs)", rr, beWR);
   PrintFormat(" Net profit          : %.2f %s", g_netProfit, AccountCurrency());
   PrintFormat(" Profit factor       : %.2f", pf);
   PrintFormat(" Average win / loss  : %.2f / %.2f", avgWin, avgLoss);
   PrintFormat(" Average R multiple  : %.3f R per trade", avgR);
   PrintFormat(" Max drawdown        : %.2f %s (%.2f %%)", g_maxDD, AccountCurrency(), g_maxDDpct);
   Print("-------------------------------------------------------------------");
   Print(" Read this before chasing a win rate number:");
   Print("  * win rate is a property of the EXIT, not of the entry.");
   Print("  * at TP:SL = 1:1 you break even at ~50 %, at 2:1 at ~33 %, at 3:1 at ~25 %.");
   Print("  * a high win rate with small targets is usually negative expectancy");
   Print("    once spread, commission and the occasional large loss are counted.");
   Print("  * what matters is: profit factor > 1, average R > 0, and stability");
   Print("    out of sample. Compare this run against the random baseline run");
   Print("    (InpRandomBaseline = true, same dates, same exits).");
   Print("===================================================================");
  }

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   g_digits    = (int)MarketInfo(_Symbol, MODE_DIGITS);
   g_point     = MarketInfo(_Symbol, MODE_POINT);
   if(g_digits <= 0) g_digits = Digits;
   if(g_point  <= 0.0) g_point = Point;
   g_pip       = (g_digits == 3 || g_digits == 5) ? g_point * 10.0 : g_point;
   g_tickValue = MarketInfo(_Symbol, MODE_TICKVALUE);
   g_tickSize  = MarketInfo(_Symbol, MODE_TICKSIZE);
   g_minLot    = MarketInfo(_Symbol, MODE_MINLOT);
   g_maxLot    = MarketInfo(_Symbol, MODE_MAXLOT);
   g_lotStep   = MarketInfo(_Symbol, MODE_LOTSTEP);
   g_stopLevel = (int)MarketInfo(_Symbol, MODE_STOPLEVEL);
   if(g_tickSize  <= 0.0) g_tickSize  = g_point;
   if(g_lotStep   <= 0.0) g_lotStep   = 0.01;
   if(g_minLot    <= 0.0) g_minLot    = 0.01;

   g_peakEquity = AccountEquity();

   if(InpRandomBaseline)
      MathSrand(InpRandSeed);

   Print("WPR_SwingBreakout_EA started. Indicator: ", InpIndicatorName,
         " | TP:SL = ", DoubleToString(InpTakeProfitATR, 2), ":", DoubleToString(InpStopLossATR, 2),
         " | random baseline: ", (InpRandomBaseline ? "ON (control group)" : "off"));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   PrintReport();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   TrackEquity();

   if(Bars < InpWPRPeriod + 50)
      return;

   datetime barTime = iTime(_Symbol, _Period, 0);
   bool     newBar  = (barTime != g_lastBar);
   if(newBar)
      g_lastBar = barTime;

//--- did the position we track get closed (SL / TP / margin)?
   if(g_ticket != 0)
     {
      if(!IsOpen(g_ticket))
        {
         RecordTrade(g_ticket);
         g_ticket = 0;
        }
      else
        {
         if(newBar)
            g_barsInTrade++;
         ManagePosition();
        }
     }

   if(!newBar)
      return;
   if(!IsTradeAllowed())
      return;

   if(InpRandomBaseline)
      MaybeRandomEntry();
   else
      CheckForSignal();
  }
//+------------------------------------------------------------------+
