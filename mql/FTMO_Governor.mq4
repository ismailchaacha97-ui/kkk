//+------------------------------------------------------------------+
//|                                            FTMO_Governor.mq4     |
//|  Daily-budget supervisor for an FTMO-style account.               |
//|                                                                   |
//|  WHAT IT DOES                                                     |
//|    * derives the day-start balance and the day's realized P&L     |
//|    * draws the four lines that matter (firm daily, self daily,    |
//|      firm total, self total) so you can see the distance to ruin  |
//|    * trips a HALT when any condition in FTMO_SYSTEM.md sec 4.3 is |
//|      true, and shows exactly which one                          |
//|    * optional: flattens everything on a daily breach              |
//|                                                                   |
//|  WHAT IT DOES NOT DO                                              |
//|    MT4 gives an EA no way to veto a *manual* order. This is a     |
//|    supervisor, not a lock. It cannot stop you clicking buy, and  |
//|    it will not place trades for you. It makes the rule visible    |
//|    and loud at the exact moment you are least likely to count.    |
//|                                                                   |
//|  STATUS                                                           |
//|    The logic here is a port of ftmo_engine/risk.py, which is      |
//|    unit-tested. THIS FILE HAS NOT BEEN COMPILED OR RUN in the     |
//|    environment where it was written -- compile it, run it on      |
//|    demo for a week, and check the numbers against your broker's   |
//|    statement before trusting it with a funded account.            |
//+------------------------------------------------------------------+
#property copyright "FTMO operating system"
#property version   "1.00"
#property strict

input double InpRiskPercent        = 0.50;  // Risk per trade (%)
input double InpSelfDailyStopPct   = 2.00;  // Self-imposed daily stop (%)
input double InpFirmDailyLossPct   = 5.00;  // Firm daily limit (%)
input double InpFirmTotalLossPct   = 10.00; // Firm max total loss (%)
input double InpSelfTotalStopPct   = 7.00;  // Self-imposed total stop (%)
input int    InpMaxTradesPerDay    = 2;     // Max entries per day
input int    InpMaxConsecLosses    = 2;     // Consecutive losses -> halt
input int    InpServerToCETOffset  = 1;     // Server time -> CET offset (hours)
input bool   InpCountAllSymbols    = true;  // Count P&L across the account
input bool   InpFlatOnDailyBreach  = false; // Close all if firm daily limit hit
input bool   InpAlerts             = true;  // Alerts on halt
input color  InpLineColorSelf      = clrOrange;
input color  InpLineColorFirm      = clrRed;

//--- state
double   g_initialBalance   = 0.0;   // set once, on attach (static floor reference)
double   g_dayStartBalance  = 0.0;
datetime g_dayStartTime     = 0;
bool     g_halted           = false;
string   g_haltReason       = "";
int      g_tradesToday      = 0;
int      g_consecLosses     = 0;
double   g_realizedToday    = 0.0;
double   g_realizedTotal    = 0.0;

#define PREFIX "FGV_"

//+------------------------------------------------------------------+
int OnInit()
{
   if(!InpCountAllSymbols && Symbol() == "")
      return(INIT_FAILED);

   g_initialBalance = AccountBalance();
   ResetDay();

   if(!ObjectFind(PREFIX "firm_daily"))
   {
      MakeLine(PREFIX "firm_daily", 0, InpLineColorFirm,      STYLE_DOT,   "Firm daily limit");
      MakeLine(PREFIX "self_daily", 0, InpLineColorSelf,      STYLE_SOLID, "Self daily stop");
      MakeLine(PREFIX "firm_total", 0, InpLineColorFirm,      STYLE_DASHDOT, "Firm total floor");
      MakeLine(PREFIX "self_total", 0, InpLineColorSelf,      STYLE_DOT,   "Self total stop");
   }
   UpdatePanel();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   // only our own objects, never the user's drawings
   ObjectsDeleteAll(0, PREFIX);
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   // new trading day (midnight CET, approximated from server time)
   datetime nowCET = TimeCurrent() - InpServerToCETOffset * 3600;
   datetime midnight = StrToTime(TimeToString(nowCET, TIME_DATE)) + InpServerToCETOffset * 3600;
   if(midnight != g_dayStartTime)
      ResetDay();

   Recompute();
   CheckHalts();
   UpdatePanel();
}

//+------------------------------------------------------------------+
void ResetDay()
{
   g_dayStartBalance = AccountBalance();
   datetime nowCET   = TimeCurrent() - InpServerToCETOffset * 3600;
   g_dayStartTime    = StrToTime(TimeToString(nowCET, TIME_DATE)) + InpServerToCETOffset * 3600;
   g_halted          = false;
   g_haltReason      = "";
   g_tradesToday     = 0;
   g_consecLosses    = 0;
   g_realizedToday   = 0.0;
   Recompute();
}

bool IsMine()
{
   if(InpCountAllSymbols) return(true);
   return(OrderSymbol() == Symbol());
}

void Recompute()
{
   g_realizedToday = 0.0;
   g_realizedTotal = 0.0;
   g_tradesToday   = 0;
   g_consecLosses  = 0;

   int total = OrdersHistoryTotal();
   // walk closed orders newest-first so consecutive losses can be counted
   int lastClose = -1;
   for(int i = total - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsMine()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderOpenTime() == lastClose) continue;

      double net = OrderProfit() + OrderSwap() + OrderCommission();
      g_realizedTotal += net;
      if(OrderCloseTime() >= g_dayStartTime)
      {
         g_realizedToday += net;
         g_tradesToday++;
      }
   }

   // consecutive losses from the most recent closed trades
   int scanned = 0;
   for(int j = total - 1; j >= 0 && scanned < InpMaxConsecLosses + 1; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsMine()) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      if(net < 0) g_consecLosses++;
      else        break;
      scanned++;
   }
   lastClose = 0;
}

//+------------------------------------------------------------------+
void CheckHalts()
{
   if(g_halted) return;

   double firmDailyFloor  = g_dayStartBalance * (1.0 - InpFirmDailyLossPct  / 100.0);
   double selfDailyFloor  = g_dayStartBalance * (1.0 - InpSelfDailyStopPct  / 100.0);
   double firmTotalFloor  = g_initialBalance  * (1.0 - InpFirmTotalLossPct  / 100.0);
   double selfTotalFloor  = g_initialBalance  * (1.0 - InpSelfTotalStopPct  / 100.0);
   double equity          = AccountEquity();

   string why = "";
   if(equity <= firmDailyFloor)      why = "FIRM DAILY LIMIT BREACHED";
   else if(equity <= selfDailyFloor) why = "self daily stop reached";
   else if(equity <= firmTotalFloor) why = "FIRM TOTAL FLOOR BREACHED";
   else if(equity <= selfTotalFloor) why = "self total stop reached - stop for the week";
   else if(g_consecLosses >= InpMaxConsecLosses) why = "max consecutive losses today";
   else if(g_tradesToday >= InpMaxTradesPerDay)  why = "max trades today";

   if(why == "") return;

   g_halted     = true;
   g_haltReason = why;

   if(InpAlerts)
      Alert("FTMO Governor HALT: ", why);

   if(InpFlatOnDailyBreach && (equity <= firmDailyFloor || equity <= selfDailyFloor))
      FlatAll();
}

//+------------------------------------------------------------------+
void FlatAll()
{
   for(int attempt = 0; attempt < 3; attempt++)
   {
      bool anyLeft = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(!IsMine()) continue;
         if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

         RefreshRates();
         double price = (OrderType() == OP_BUY) ? Bid : Ask;
         if(!OrderClose(OrderTicket(), OrderLots(), price, 30, clrWhite))
         {
            Print("FTMO Governor: close failed on #", OrderTicket(),
                  " err=", GetLastError());
            anyLeft = true;
         }
      }
      if(!anyLeft) return;
      Sleep(500);          // never spin: bounded attempts, then give up loudly
   }
}

//+------------------------------------------------------------------+
void MakeLine(string name, double price, color c, int style, string text)
{
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void MoveLine(string name, double price)
{
   if(ObjectFind(0, name) >= 0)
      ObjectMove(0, name, 0, 0, price);
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   double firmDailyFloor  = g_dayStartBalance * (1.0 - InpFirmDailyLossPct / 100.0);
   double selfDailyFloor  = g_dayStartBalance * (1.0 - InpSelfDailyStopPct / 100.0);
   double firmTotalFloor  = g_initialBalance  * (1.0 - InpFirmTotalLossPct / 100.0);
   double selfTotalFloor  = g_initialBalance  * (1.0 - InpSelfTotalStopPct / 100.0);

   MoveLine(PREFIX "firm_daily", firmDailyFloor);
   MoveLine(PREFIX "self_daily", selfDailyFloor);
   MoveLine(PREFIX "firm_total", firmTotalFloor);
   MoveLine(PREFIX "self_total", selfTotalFloor);

   double equity   = AccountEquity();
   double riskCash = g_initialBalance * InpRiskPercent / 100.0;
   double remaining = MathMax(0.0, equity - selfDailyFloor);

   string s = "";
   s += "FTMO GOVERNOR  " + (g_halted ? "*** HALTED: " + g_haltReason + " ***" : "clear to trade") + "\n";
   s += "day start      : " + DoubleToString(g_dayStartBalance, 2) + "\n";
   s += "equity         : " + DoubleToString(equity, 2) + "\n";
   s += "realized today : " + DoubleToString(g_realizedToday, 2) + "\n";
   s += "self daily stop: " + DoubleToString(selfDailyFloor, 2)
        + "  (room " + DoubleToString(remaining, 2) + ")\n";
   s += "firm daily stop: " + DoubleToString(firmDailyFloor, 2) + "\n";
   s += "self total stop: " + DoubleToString(selfTotalFloor, 2) + "\n";
   s += "firm floor     : " + DoubleToString(firmTotalFloor, 2) + "\n";
   s += "trades today   : " + IntegerToString(g_tradesToday) + " / " + IntegerToString(InpMaxTradesPerDay) + "\n";
   s += "consec losses  : " + IntegerToString(g_consecLosses) + " / " + IntegerToString(InpMaxConsecLosses) + "\n";
   s += "risk this trade: " + DoubleToString(riskCash, 2)
        + "  (" + DoubleToString(InpRiskPercent, 2) + "%)   lots @20p = "
        + DoubleToString(NormalizeLots(riskCash / (20.0 * PipValuePerLot())), 2) + "\n";
   s += "trades left    : " + IntegerToString(MathMax(0, InpMaxTradesPerDay - g_tradesToday))
        + "   losses before halt: " + IntegerToString(MathMax(0, InpMaxConsecLosses - g_consecLosses));
   Comment(s);
}

//+------------------------------------------------------------------+
double PipValuePerLot()
{
   // account-currency value of one pip on one lot, for the chart symbol
   double pip = (Digits == 3 || Digits == 5) ? Point * 10.0 : Point;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickSize <= 0.0) return(10.0);
   return(tickValue * (pip / tickSize));
}

double NormalizeLots(double lots)
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minL = MarketInfo(Symbol(), MODE_MINLOT);
   double maxL = MarketInfo(Symbol(), MODE_MAXLOT);
   if(step <= 0.0) step = 0.01;
   lots = MathFloor(lots / step) * step;   // floor, never round up
   if(lots < minL) return(0.0);            // below minimum: skip the trade
   if(lots > maxL) lots = maxL;
   return(NormalizeDouble(lots, 8));
}
//+------------------------------------------------------------------+
