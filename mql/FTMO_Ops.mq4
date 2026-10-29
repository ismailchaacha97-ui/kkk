//+------------------------------------------------------------------+
//|                                                   FTMO_Ops.mq4   |
//|  Trading executor for the FTMO operating system (FTMO_SYSTEM.md) |
//|                                                                  |
//|  PLACES REAL TRADES. Implements, mechanically:                   |
//|    S3.1  universe, sessions, news filter, weekend-flat           |
//|    S3.2  H1 bias + H1 zone + M15 trigger entry model             |
//|    S3.3  anti-martingale rules (no adds, no stop-widening, caps) |
//|    S4.1  fixed-fractional sizing off a FIXED reference balance   |
//|    S4.2  daily budget, trade-level breaker, weekly halt          |
//|    S4.3  all eight halt conditions                                |
//|    S4.4  correlated net-USD exposure cap                          |
//|    S6.x  after 8% in an evaluation: drop to lock risk            |
//|                                                                  |
//|  USAGE                                                            |
//|    * One chart per symbol you want to trade (EURUSD, GBPUSD,     |
//|      USDJPY). Same InpMagic on every chart: the per-day caps and |
//|      breakers are counted from account history, so one EA        |
//|      cannot cheat another.                                       |
//|    * When the account changes, delete the EA's GlobalVariables   |
//|      (named FTMOOPS_*) from Tools > Global Variables so the      |
//|      reference balance resets.                                   |
//|                                                                  |
//|  STATUS - READ THIS FIRST                                        |
//|    * Logic is a port of the unit-tested Python engine            |
//|      (ftmo_engine/risk.py, mc.py). THIS MQL4 FILE HAS NOT BEEN   |
//|      COMPILED OR RUN anywhere yet.                               |
//|    * Step 1: compile in MetaEditor, fix any warnings.            |
//|    * Step 2: Strategy Tester, "Every tick based on real ticks",  |
//|      6+ months, visual ON. Verify: no trade after a halt day,   |
//|      no position over a weekend, every order has SL+TP, lots    |
//|      match the risk table, no entry inside a news window.        |
//|    * Step 3: live demo account, 2-4 weeks.                        |
//|    * Only then: a real evaluation account.                       |
//+------------------------------------------------------------------+
#property copyright "FTMO operating system"
#property version   "1.00"
#property strict

//--- universe / account --------------------------------------------------
input string InpAllowedSymbols   = "EURUSD,GBPUSD,USDJPY"; // Exact broker symbol names, comma list
input int    InpMagic            = 20261029;    // Magic number (same on all charts)
input int    InpMaxOpenPositions = 2;           // Max simultaneous positions (per account)
input int    InpMaxTradesPerDay  = 2;           // Max entries per day (hard cap)
input int    InpMaxTradesPerWeekPerSymbol = 3;  // Max entries per week per symbol

//--- account phase / risk (S4.1) ----------------------------------------
input int    InpMode             = 0;           // 0=Challenge, 1=Verification, 2=Funded
input double InpRiskPercent      = 0.50;        // Risk per trade, evaluation (%)
input double InpFundedRiskPercent= 0.40;        // Risk per trade, funded (%)
input double InpLockProfitPct    = 8.0;         // Eval: profit above which risk locks down (%)
input double InpLockRiskPct      = 0.10;        // Locked risk (%)
input double InpRefBalanceOverride = 0.0;       // >0: fixed reference balance (else balance at attach)

//--- firm limits (S4.2) ---------------------------------------------------
input double InpFirmDailyLossPct = 5.0;         // Firm daily limit (%)
input double InpFirmTotalLossPct = 10.0;        // Firm static total floor (%)
input double InpSelfDailyStopPct = 2.0;         // Self-imposed daily stop (%)
input double InpSelfTotalStopPct = 7.0;         // Self-imposed total stop (%)
input int    InpTotalStopHaltDays= 7;           // Days stopped after self total stop
input double InpWeeklyLossBudgetMult = 2.0;     // Weekly halt at N x daily budget lost (%)
input bool   InpFlatOnFirmDaily  = true;        // Close all if firm daily limit hit
input bool   InpFlatOnFirmTotal  = true;        // Close all if firm floor hit
input bool   InpFlatOnNews       = true;        // Close all at high-impact news (playbook: flat)

//--- trade-level breaker (S4.3) ------------------------------------------
input int    InpMaxConsecLosses  = 2;           // Consecutive losing trades -> daily halt
input double InpMaxFloatingLossR = 1.5;         // Halt when floating basket loss >= N R

//--- entry model (S3.1 / S3.2) -------------------------------------------
input int    InpSessionStartCET  = 7;           // Session start, CET
input int    InpSessionEndCET    = 16;          // Session end, CET
input int    InpCloseFridayCET   = 21;          // Flat by this hour Friday, CET
input int    InpServerToCETOffset= 1;           // Hours server time is ahead of CET (winter: 1)
input int    InpSwingK           = 3;           // Fractal strength
input int    InpLookbackH1       = 200;         // H1 bars to search for the swing
input int    InpZoneBars         = 3;           // Bars of the up/down leg defining the zone
input int    InpZoneMaxAge       = 48;          // Max H1 bars since breakout
input double InpZoneWidthAtx     = 0.35;        // Zone width in ATR(H1,14) units
input int    InpMaxH1Touches     = 1;           // Max H1 touches since breakout (M15 tap = 2nd)
input int    InpZoneTolerancePips= 3;           // Tap tolerance, pips
input double InpAtrBiasMult      = 1.2;         // M15 ATR must be <= this x 20-bar mean
input double InpStopAtrX         = 0.3;         // Stop beyond zone edge, ATR(M15) units
input int    InpMinStopPips      = 8;           // Minimum stop distance, pips
input int    InpMaxStopPips      = 40;          // Skip trade if stop wider than this
input int    InpMaxSpreadPips    = 20;          // Skip if spread wider than this
input double InpFirstTargetR     = 2.0;         // Initial target, R
input double InpBreakevenR       = 1.0;         // Move SL to breakeven at +N R
input double InpSplitFraction    = 0.6;         // Fraction of lots closed at first target
input double InpRunnerTargetR    = 3.5;         // Target for the remainder, R
input int    InpTimeStopBars     = 8;           // M15 bars until +0.5R else close
input double InpTimeStopProfitR  = 0.5;

//--- news filter (S3.1) ---------------------------------------------------
input int    InpNewsWindowMin    = 30;          // No-trade window around news, minutes
input bool   InpAutoNFP          = true;        // Auto first-Friday NFP
input int    InpNfpHourServer    = 12;          // NFP hour, SERVER time (set for your broker)
input int    InpNfpMinuteServer  = 30;          // NFP minute, SERVER time
input string InpNewsTimesServer  = "";          // Extra news "yyyy.mm.dd hh:mm, ..." SERVER time

//--- misc -----------------------------------------------------------------
input bool   InpDryRun           = false;       // Log signals, place no orders
input bool   InpCountAllSymbols  = true;        // Count P&L/trades across the account (magic)
input bool   InpAlerts           = true;        // Alert on halts and entries

//--- state ------------------------------------------------------------------
double   g_initial   = 0.0;
double   g_dayStart  = 0.0;
datetime g_dayMark   = 0;
bool     g_haltDay   = false;
bool     g_haltWeek  = false;
string   g_haltWhy   = "";
int      g_openCount = 0;
int      g_todayEntries = 0;
int      g_consecLosses = 0;
datetime g_totalStopUntil = 0;
bool     g_newsFlatDone = false;
datetime g_lastM15Bar = 0;
string   g_lastSignal = "none";
double   g_newsTimes[];

#define GV_PREFIX "FTMOOPS_"

//+------------------------------------------------------------------+
int OnInit()
{
   // reference balance: fixed for the life of the account (S4.1)
   if(GlobalVariableCheck(GV_PREFIX "init"))
      g_initial = GlobalVariableGet(GV_PREFIX "init");
   else
   {
      g_initial = (InpRefBalanceOverride > 0) ? InpRefBalanceOverride : AccountBalance();
      GlobalVariableSet(GV_PREFIX "init", g_initial);   // no expiry in MQL4: lives until deleted
      Print("FTMO_Ops: reference balance fixed at ", DoubleToString(g_initial, 2),
            ". Delete ", GV_PREFIX, "* globals when the account changes.");
   }
   g_dayMark = 0;
   g_totalStopUntil = (datetime)GetGV("totalstop", 0);
   LoadNewsList();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManageDay();
   CheckHalts();
   ManagePositions();
   HandleWeekendFlat();
   HandleNewsFlattening();

   // trade the close of the last completed M15 bar, exactly once per bar
   datetime barTime = iTime(Symbol(), PERIOD_M15, 0);
   if(barTime != g_lastM15Bar)
   {
      g_lastM15Bar = barTime;
      if(!IsTradeContextBusy())
         EvaluateSignal();
   }
   UpdatePanel();
}

//+------------------------------------------------------------------+
//  TIME AND STATE
//+------------------------------------------------------------------+
double PipSize()
{
   return((Digits == 3 || Digits == 5) ? Point * 10.0 : Point);
}

double PipValuePerLot()
{
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickSize <= 0.0) return(10.0);
   return(tickValue * (PipSize() / tickSize));
}

datetime NowCET() { return(TimeCurrent() - InpServerToCETOffset * 3600); }

void SetGV(string name, double value)
{
   GlobalVariableSet(GV_PREFIX + name, value);   // no expiry in MQL4: it lives until deleted
}

// MQL4 globals never expire, so prune yesterday's day keys on each new day
void CleanOldDayKeys()
{
   datetime todayDt = (datetime)StrToTime(TimeToString(NowCET(), TIME_DATE));
   // "FTMOOPS_daystart_" and "FTMOOPS_daymark_" are both 17 chars; the date follows
   int prefixLen = StringLen(GV_PREFIX "daystart_");
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariablesName(i);
      if(StringFind(name, GV_PREFIX "daystart_") != 0 && StringFind(name, GV_PREFIX "daymark_") != 0)
         continue;
      if(StringLen(name) <= prefixLen) continue;
      datetime d = StrToTime(StringSubstr(name, prefixLen));
      if(d < todayDt)
         GlobalVariableDel(name);
   }
}

double GetGV(string name, double fallback)
{
   string full = GV_PREFIX + name;
   return(GlobalVariableCheck(full) ? GlobalVariableGet(full) : fallback);
}

void ManageDay()
{
   string dayKey = TimeToString(NowCET(), TIME_DATE);
   double savedDayStart = GetGV("daystart_" + dayKey, 0.0);
   datetime savedMark    = (datetime)GetGV("daymark_" + dayKey, 0);

   if(savedMark != 0 && savedDayStart > 0)
   {
      g_dayStart = savedDayStart;               // restart same day: state restored
      g_dayMark  = savedMark;
      return;
   }

   // new day (or first run): fix the day-start balance
   g_dayStart = AccountBalance();
   g_dayMark  = (datetime)StrToTime(dayKey);
   g_haltDay  = false;
   g_haltWhy  = "";
   g_newsFlatDone = false;
   CleanOldDayKeys();
   SetGV("daystart_" + dayKey, g_dayStart);
   SetGV("daymark_" + dayKey, (double)g_dayMark);
   if(InpAlerts)
      Print("FTMO_Ops: new day. day-start balance ", DoubleToString(g_dayStart, 2));
}

//+------------------------------------------------------------------+
//  HISTORY-BASED COUNTERS (survive restarts, attribute by magic)
//+------------------------------------------------------------------+
bool Mine(string sym)
{
   if(InpCountAllSymbols) return(true);
   return(sym == Symbol());
}

bool IsEntryOrder(int type) { return(type == OP_BUY || type == OP_SELL); }

int CountEntriesSince(datetime from)
{
   int n = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(!IsEntryOrder(OrderType())) continue;
      if(!Mine(OrderSymbol())) continue;
      if(OrderOpenTime() >= from) n++;
   }
   return(n);
}

// NOTE: in MQL4 the account history (MODE_HISTORY) already includes open orders,
// so counting from it alone is correct and complete.

int CountEntriesWeekForSymbol(string sym)
{
   datetime weekStart = NowCET() - 7 * 86400;
   int n = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(!IsEntryOrder(OrderType())) continue;
      if(OrderSymbol() != sym) continue;
      if(OrderOpenTime() >= weekStart) n++;
   }
   return(n);
}

double RealizedPnLSince(datetime from)
{
   double s = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(!IsEntryOrder(OrderType())) continue;
      if(OrderCloseTime() == 0) continue;          // closed orders only
      if(OrderCloseTime() < from) continue;
      s += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return(s);
}

int CountConsecLosses()
{
   int n = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0 && n < InpMaxConsecLosses + 1; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(!IsEntryOrder(OrderType())) continue;
      if(!Mine(OrderSymbol())) continue;
      if(OrderCloseTime() == 0) continue;          // settled losses only
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      if(net < 0) n++;
      else        break;
   }
   return(n);
}

//+------------------------------------------------------------------+
//  HALTS (S4.2 / S4.3)
//+------------------------------------------------------------------+
void Halt(string why)
{
   if(why != g_haltWhy && why != "" && InpAlerts)
      Alert("FTMO_Ops HALT: ", why);
   g_haltWhy = why;
   g_haltDay  = true;
}

void ClearHalt()
{
   g_haltDay  = false;
   g_haltWeek = false;
   g_haltWhy  = "";
}

void CheckHalts()
{
   g_openCount = 0;
   double maxFloatingLossR = 0.0;
   double riskCash = RiskCash();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(!IsEntryOrder(OrderType())) continue;
      g_openCount++;
      if(OrderProfit() < 0 && riskCash > 0)
         maxFloatingLossR = MathMax(maxFloatingLossR, -OrderProfit() / riskCash);
   }

   // midnight CET expressed in server time = midnight-of-CET-date + offset
   datetime midnightCET = (datetime)StrToTime(TimeToString(NowCET(), TIME_DATE)) + InpServerToCETOffset * 3600;
   g_todayEntries = CountEntriesSince(midnightCET);
   g_consecLosses = CountConsecLosses();

   double equity         = AccountEquity();
   double firmDailyFloor = g_dayStart * (1.0 - InpFirmDailyLossPct / 100.0);
   double selfDailyFloor = g_dayStart * (1.0 - InpSelfDailyStopPct / 100.0);
   double firmTotalFloor = g_initial  * (1.0 - InpFirmTotalLossPct / 100.0);
   double selfTotalFloor = g_initial  * (1.0 - InpSelfTotalStopPct / 100.0);

   // --- hard total stops ---
   if(equity <= firmTotalFloor)
   {
      g_haltWeek = true;
      Halt("FIRM TOTAL FLOOR BREACHED");
      if(InpFlatOnFirmTotal) FlatAll("firm total floor");
      return;
   }
   if(equity <= selfTotalFloor)
   {
      g_totalStopUntil = TimeCurrent() + (datetime)InpTotalStopHaltDays * 86400;
      SetGV("totalstop", (double)g_totalStopUntil);
      g_haltWeek = true;
      Halt("self total stop - stopped for " + IntegerToString(InpTotalStopHaltDays) + " days");
      return;
   }
   if(g_totalStopUntil > TimeCurrent())
   {
      g_haltWeek = true;
      Halt("inside self-total-stop window");
      return;
   }

   // --- firm daily ---
   if(equity <= firmDailyFloor)
   {
      Halt("FIRM DAILY LIMIT BREACHED");
      if(InpFlatOnFirmDaily) FlatAll("firm daily limit");
      return;
   }
   // --- self daily ---
   if(equity <= selfDailyFloor)
   {
      Halt("self daily stop reached");
      return;
   }
   // --- weekly halt: realized week loss >= N x daily budget ---
   double weekLoss    = -RealizedPnLSince(NowCET() - 7 * 86400);
   double dailyBudget = g_dayStart * InpSelfDailyStopPct / 100.0;
   if(weekLoss >= InpWeeklyLossBudgetMult * dailyBudget)
   {
      Halt("weekly loss budget exhausted");
      return;
   }
   // --- trade-level breakers ---
   if(g_consecLosses >= InpMaxConsecLosses)
   {
      Halt("max consecutive losses today");
      return;
   }
   if(g_todayEntries >= InpMaxTradesPerDay)
   {
      Halt("max trades today");
      return;
   }
   if(maxFloatingLossR >= InpMaxFloatingLossR)
   {
      Halt("floating basket loss >= " + DoubleToString(InpMaxFloatingLossR, 1) + "R");
      return;
   }

   ClearHalt();
}

//+------------------------------------------------------------------+
void HandleNewsFlattening()
{
   if(!InNewsWindow())
   {
      g_newsFlatDone = false;
      return;
   }
   if(InpFlatOnNews && g_openCount > 0 && !g_newsFlatDone)
   {
      g_newsFlatDone = true;
      FlatAll("news window");
   }
}

// playbook S3.1: all flat by InpCloseFridayCET Friday - no weekend holds
void HandleWeekendFlat()
{
   MqlDateTime dt;
   TimeToStruct(NowCET(), dt);
   if(dt.day_of_week == 5 && dt.hour >= InpCloseFridayCET && g_openCount > 0)
      FlatAll("weekend flat");
}

//+------------------------------------------------------------------+
//  SIZING (S4.1) - fixed fraction of the FIXED reference balance
//+------------------------------------------------------------------+
double RiskPct()
{
   if(InpMode == 2) return(InpFundedRiskPercent);
   double profitPct = (AccountBalance() - g_initial) / g_initial * 100.0;
   if(profitPct >= InpLockProfitPct) return(InpLockRiskPct);   // S6.x: 8% reached
   return(InpRiskPercent);
}

double RiskCash()
{
   return(g_initial * RiskPct() / 100.0);
}

double NormalizeLots(double lots)
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minL = MarketInfo(Symbol(), MODE_MINLOT);
   double maxL = MarketInfo(Symbol(), MODE_MAXLOT);
   if(step <= 0.0) step = 0.01;
   lots = MathFloor(lots / step) * step;        // floor, never round up
   if(lots < minL) return(0.0);
   if(lots > maxL) return(maxL);
   return(NormalizeDouble(lots, 8));
}

double PositionRiskUSD(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return(0.0);
   if(OrderStopLoss() <= 0) return(0.0);
   double pips = MathAbs(OrderOpenPrice() - OrderStopLoss()) / PipSize();
   return(pips * OrderLots() * PipValuePerLot());
}

//+------------------------------------------------------------------+
//  NEWS FILTER (S3.1)
//+------------------------------------------------------------------+
void LoadNewsList()
{
   int n = 0;
   string s = InpNewsTimesServer;
   while(StringLen(s) > 0)
   {
      int cpos = StringFind(s, ",");
      string item = (cpos >= 0) ? StringSubstr(s, 0, cpos) : s;
      if(cpos >= 0) s = StringSubstr(s, cpos + 1);
      else s = "";
      StringTrimLeft(item);
      StringTrimRight(item);
      if(StringLen(item) < 16) continue;
      datetime t = StringToTime(item);   // "yyyy.mm.dd hh:mm" (server time)
      if(t == 0) continue;
      ArrayResize(g_newsTimes, n + 1);
      g_newsTimes[n++] = (double)t;
   }
   ArrayResize(g_newsTimes, n);
}

datetime NextNfp()
{
   if(!InpAutoNFP) return(0);
   for(int m = 0; m < 2; m++)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.day = 1;
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      if(m == 1)
      {
         dt.mon = (dt.mon % 12) + 1;
         if(dt.mon == 1) dt.year = dt.year + 1;
      }
      datetime first = StructToTime(dt);
      while(TimeDayOfWeek(first) != 5) first += 86400;
      datetime nfp = first + InpNfpHourServer * 3600 + InpNfpMinuteServer * 60;
      if(nfp >= TimeCurrent() - InpNewsWindowMin * 60) return(nfp);
   }
   return(0);
}

bool InNewsWindow()
{
   datetime now = TimeCurrent();
   datetime nfp = NextNfp();
   if(nfp > 0 && MathAbs((int)(now - nfp)) <= InpNewsWindowMin * 60) return(true);
   for(int i = 0; i < ArraySize(g_newsTimes); i++)
   {
      datetime t = (datetime)g_newsTimes[i];
      if(t > now + 7 * 86400) continue;
      if(MathAbs((int)(now - t)) <= InpNewsWindowMin * 60) return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//  ZONE DETECTION (S3.2)
//+------------------------------------------------------------------+
bool FractalHigh(int s, int k)
{
   double h = iHigh(Symbol(), PERIOD_H1, s);
   for(int j = 1; j <= k; j++)
   {
      if(h < iHigh(Symbol(), PERIOD_H1, s - j) || h < iHigh(Symbol(), PERIOD_H1, s + j))
         return(false);
   }
   return(true);
}

bool FractalLow(int s, int k)
{
   double l = iLow(Symbol(), PERIOD_H1, s);
   for(int j = 1; j <= k; j++)
   {
      if(l > iLow(Symbol(), PERIOD_H1, s - j) || l > iLow(Symbol(), PERIOD_H1, s + j))
         return(false);
   }
   return(true);
}

// long zone: lowest low of the up-leg that broke the last swing high
bool FindLongZone(double &zl, double &zh, int &touches)
{
   int swingBar = -1;
   for(int s = InpSwingK + 1; s <= InpLookbackH1; s++)
      if(FractalHigh(s, InpSwingK)) { swingBar = s; break; }
   if(swingBar < 0) return(false);

   int breakoutBar = -1;
   double swingH = iHigh(Symbol(), PERIOD_H1, swingBar);
   for(int b = 1; b < swingBar; b++)
   {
      if(iClose(Symbol(), PERIOD_H1, b) > swingH) { breakoutBar = b; break; }
   }
   if(breakoutBar < 0) return(false);
   if(breakoutBar > InpZoneMaxAge) return(false);

   double base = DBL_MAX;
   int used = 0;
   for(int c = 1; c <= InpZoneBars; c++)
   {
      int idx = breakoutBar - c;
      if(idx < 1) continue;
      base = MathMin(base, iLow(Symbol(), PERIOD_H1, idx));
      used++;
   }
   if(used < 2 || base == DBL_MAX) return(false);

   double atrH1 = iATR(Symbol(), PERIOD_H1, 14, 1);
   zl = base;
   zh = base + InpZoneWidthAtx * atrH1;

   double tol = InpZoneTolerancePips * PipSize();
   int t = 0;
   for(int c = 1; c < breakoutBar; c++)
   {
      if(iLow(Symbol(), PERIOD_H1, c) <= zh && iLow(Symbol(), PERIOD_H1, c) >= zl - tol)
         t++;
   }
   if(t > InpMaxH1Touches) return(false);
   touches = t;
   return(true);
}

// short zone: mirror image
bool FindShortZone(double &zl, double &zh, int &touches)
{
   int swingBar = -1;
   for(int s = InpSwingK + 1; s <= InpLookbackH1; s++)
      if(FractalLow(s, InpSwingK)) { swingBar = s; break; }
   if(swingBar < 0) return(false);

   int breakoutBar = -1;
   double swingL = iLow(Symbol(), PERIOD_H1, swingBar);
   for(int b = 1; b < swingBar; b++)
   {
      if(iClose(Symbol(), PERIOD_H1, b) < swingL) { breakoutBar = b; break; }
   }
   if(breakoutBar < 0) return(false);
   if(breakoutBar > InpZoneMaxAge) return(false);

   double base = -DBL_MAX;
   int used = 0;
   for(int c = 1; c <= InpZoneBars; c++)
   {
      int idx = breakoutBar - c;
      if(idx < 1) continue;
      base = MathMax(base, iHigh(Symbol(), PERIOD_H1, idx));
      used++;
   }
   if(used < 2 || base == -DBL_MAX) return(false);

   double atrH1 = iATR(Symbol(), PERIOD_H1, 14, 1);
   zh = base;
   zl = base - InpZoneWidthAtx * atrH1;

   double tol = InpZoneTolerancePips * PipSize();
   int t = 0;
   for(int c = 1; c < breakoutBar; c++)
   {
      if(iHigh(Symbol(), PERIOD_H1, c) >= zl && iHigh(Symbol(), PERIOD_H1, c) <= zh + tol)
         t++;
   }
   if(t > InpMaxH1Touches) return(false);
   touches = t;
   return(true);
}

//+------------------------------------------------------------------+
//  SIGNAL (S3.2)
//+------------------------------------------------------------------+
int Bias()
{
   double e50  = iMA(Symbol(), PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE, 1);
   double e200 = iMA(Symbol(), PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE, 1);
   double c1   = iClose(Symbol(), PERIOD_H1, 1);
   if(e50 > e200 && c1 > e200) return(1);
   if(e50 < e200 && c1 < e200) return(-1);
   return(0);
}

bool AtrCalm()
{
   double cur = iATR(Symbol(), PERIOD_M15, 14, 1);
   double sum = 0.0;
   for(int i = 1; i <= 20; i++) sum += iATR(Symbol(), PERIOD_M15, 14, i);
   double avg = sum / 20.0;
   return(avg > 0 && cur <= InpAtrBiasMult * avg);
}

bool AllowedSymbol()
{
   return(StringFind("," + InpAllowedSymbols + ",", "," + Symbol() + ",") >= 0);
}

int UsdSign(string sym, int type)
{
   // S4.4: exposure in "risk to a long-USD bet" units, per position symbol
   if(sym == "EURUSD" || sym == "GBPUSD") return(type == OP_BUY ? 1 : -1);
   if(sym == "USDJPY")                     return(type == OP_BUY ? -1 : 1);
   return(0);
}

double NetUsdExposureUSD()
{
   double net = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(!IsEntryOrder(OrderType())) continue;
      net += UsdSign(OrderSymbol(), OrderType()) * PositionRiskUSD(OrderTicket());
   }
   return(net);
}

bool InSession()
{
   MqlDateTime dt;
   TimeToStruct(NowCET(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return(false);
   if(dt.day_of_week == 5 && dt.hour >= InpCloseFridayCET) return(false); // flat Friday
   if(dt.hour < InpSessionStartCET || dt.hour >= InpSessionEndCET) return(false);
   return(true);
}

void EvaluateSignal()
{
   g_lastSignal = "none";
   if(!AllowedSymbol()) return;
   if(!InSession())    { g_lastSignal = "outside session"; return; }
   if(InNewsWindow())  { g_lastSignal = "news window";     return; }
   if(g_haltDay || g_haltWeek) { g_lastSignal = "halted: " + g_haltWhy; return; }
   if(g_openCount >= InpMaxOpenPositions) { g_lastSignal = "max positions"; return; }
   if(CountEntriesWeekForSymbol(Symbol()) >= InpMaxTradesPerWeekPerSymbol)
   { g_lastSignal = "weekly per-symbol cap"; return; }

   int bias = Bias();
   if(bias == 0) { g_lastSignal = "no H1 bias"; return; }

   double zl, zh;
   int touches = 0;
   if(bias == 1)
   {
      if(!FindLongZone(zl, zh, touches)) { g_lastSignal = "no demand zone"; return; }
   }
   else
   {
      if(!FindShortZone(zl, zh, touches)) { g_lastSignal = "no supply zone"; return; }
   }

   // trigger on the just-closed M15 bar
   double o1 = iOpen(Symbol(), PERIOD_M15, 1), c1 = iClose(Symbol(), PERIOD_M15, 1);
   double l1 = iLow(Symbol(), PERIOD_M15, 1),  h1 = iHigh(Symbol(), PERIOD_M15, 1);
   double o2 = iOpen(Symbol(), PERIOD_M15, 2), c2 = iClose(Symbol(), PERIOD_M15, 2);
   double pip = PipSize();
   double tol = InpZoneTolerancePips * pip;

   bool trigger = false;
   if(bias == 1)
   {
      bool tap = (l1 >= zl - tol) && (l1 <= zh + tol) && (c1 >= zl - tol) && (c1 <= zh + tol);
      bool engulf = (o1 < c2) && (c1 > o2) && (c1 > o1);
      double body = MathAbs(c1 - o1);
      bool pin = (c1 > o1) && (MathMin(o1, c1) - l1 >= 2.0 * MathMax(body, pip))
                 && (c1 >= l1 + 0.6 * (h1 - l1));
      trigger = tap && (engulf || pin);
   }
   else
   {
      bool tap = (h1 <= zh + tol) && (h1 >= zl - tol) && (c1 <= zh + tol) && (c1 >= zl - tol);
      bool engulf = (o1 > c2) && (c1 < o2) && (c1 < o1);
      double body = MathAbs(c1 - o1);
      bool pin = (c1 < o1) && (h1 - MathMax(o1, c1) >= 2.0 * MathMax(body, pip))
                 && (c1 <= h1 - 0.6 * (h1 - l1));
      trigger = tap && (engulf || pin);
   }
   if(!trigger) { g_lastSignal = "zone ok, no trigger"; return; }
   if(!AtrCalm()) { g_lastSignal = "ATR too high"; return; }

   // spread gate
   if((int)MarketInfo(Symbol(), MODE_SPREAD) > InpMaxSpreadPips * (int)(pip / Point))
   { g_lastSignal = "spread too wide"; return; }

   // --- entry / stop / target ---
   double entry, sl, tp;
   int type;
   if(bias == 1)
   {
      type = OP_BUY;
      entry = Ask;
      sl = zl - InpStopAtrX * iATR(Symbol(), PERIOD_M15, 14, 1);
      if((entry - sl) / pip < InpMinStopPips) sl = entry - InpMinStopPips * pip;
      if((entry - sl) / pip > InpMaxStopPips) { g_lastSignal = "stop too wide"; return; }
      tp = entry + InpFirstTargetR * (entry - sl);
   }
   else
   {
      type = OP_SELL;
      entry = Bid;
      sl = zh + InpStopAtrX * iATR(Symbol(), PERIOD_M15, 14, 1);
      if((sl - entry) / pip < InpMinStopPips) sl = entry + InpMinStopPips * pip;
      if((sl - entry) / pip > InpMaxStopPips) { g_lastSignal = "stop too wide"; return; }
      tp = entry - InpFirstTargetR * (sl - entry);
   }

   double riskCash = RiskCash();

   // single-loss floor check (S4.3 #5)
   double firmFloor = g_initial * (1.0 - InpFirmTotalLossPct / 100.0);
   if(AccountEquity() - riskCash < firmFloor) { g_lastSignal = "floor check: skip"; return; }

   // correlation cap (S4.4)
   double projected = NetUsdExposureUSD() + UsdSign(Symbol(), type) * riskCash;
   if(MathAbs(projected) > 1.5 * riskCash) { g_lastSignal = "correlation cap"; return; }

   // sizing (S4.1)
   double stopPips = MathAbs(entry - sl) / pip;
   double lots = NormalizeLots(riskCash / (stopPips * PipValuePerLot()));
   if(lots < 0.0) { g_lastSignal = "size below min lot"; return; }

   string cmt = "FTMO_OPS|mode" + IntegerToString(InpMode) + "|r" + DoubleToString(stopPips, 1);
   if(InpDryRun)
   {
      g_lastSignal = "DRY RUN " + (type == OP_BUY ? "BUY" : "SELL") + " " + DoubleToString(lots, 2)
                     + " @ " + DoubleToString(entry, 5) + " SL " + DoubleToString(sl, 5)
                     + " TP " + DoubleToString(tp, 5);
      Print(g_lastSignal);
      return;
   }

   int ticket = OrderSend(Symbol(), type, lots, entry, 30, sl, tp, cmt, InpMagic, 0,
                          type == OP_BUY ? clrBlue : clrRed);
   if(ticket < 0)
   {
      if(InpAlerts) Alert("FTMO_Ops: OrderSend failed, err=", GetLastError());
      return;
   }
   g_lastSignal = "TRADED " + (type == OP_BUY ? "BUY" : "SELL") + " " + DoubleToString(lots, 2)
                 + " risk $" + DoubleToString(riskCash, 2);
   if(InpAlerts)
      Alert("FTMO_Ops: ", g_lastSignal, " ticket ", ticket);
}

//+------------------------------------------------------------------+
//  POSITION MANAGEMENT (S3.2 exit ladder, S3.3)
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(!IsEntryOrder(OrderType())) continue;

      int type   = OrderType();
      double open = OrderOpenPrice();
      double sl   = OrderStopLoss();
      double tp   = OrderTakeProfit();
      double lots = OrderLots();
      double pip  = PipSize();
      bool isBuy  = (type == OP_BUY);

      // original stop distance (R), preserved in the comment ("|r12.3")
      double origR = 0.0;
      int rpos = StringFind(OrderComment(), "|r");
      if(rpos >= 0)
         origR = StringToDouble(StringSubstr(OrderComment(), rpos + 2));
      if(origR <= 0)
         origR = (sl > 0) ? MathAbs(open - sl) / pip : 0.0;
      if(origR <= 0) continue;

      double profit     = isBuy ? (Bid - open) : (open - Ask);
      double profitPips = profit / pip;
      bool beDone    = isBuy ? (sl >= open) : (sl <= open);
      bool splitDone = isBuy ? (tp >= open + 3.4 * origR * pip)
                             : (tp <= open - 3.4 * origR * pip);

      // 1) breakeven at +1R
      if(!beDone && profitPips >= InpBreakevenR * origR)
      {
         double nsl = isBuy ? open + 2 * pip : open - 2 * pip;
         if(!OrderModify(OrderTicket(), open, nsl, tp, 0, clrYellow))
            Print("FTMO_Ops: BE modify failed err=", GetLastError());
      }
      // 2) split at +2R: close InpSplitFraction, send the rest to 3.5R
      if(beDone && !splitDone && profitPips >= InpFirstTargetR * origR)
      {
         double step = MarketInfo(Symbol(), MODE_LOTSTEP);
         double minL = MarketInfo(Symbol(), MODE_MINLOT);
         double keep = NormalizeDouble(MathFloor(lots * (1.0 - InpSplitFraction) / step) * step, 8);
         if(keep >= minL)
         {
            double closePrice = isBuy ? Bid : Ask;
            if(OrderClose(OrderTicket(), lots - keep, closePrice, 30, clrWhite))
            {
               double ntp = isBuy ? open + InpRunnerTargetR * origR * pip
                                  : open - InpRunnerTargetR * origR * pip;
               if(OrderSelect(OrderTicket(), SELECT_BY_TICKET))
               {
                  double curSl = OrderStopLoss();
                  if(!OrderModify(OrderTicket(), open, curSl, ntp, 0, clrWhite))
                     Print("FTMO_Ops: runner TP modify failed err=", GetLastError());
               }
            }
            else
               Print("FTMO_Ops: partial close failed err=", GetLastError());
         }
      }
      // 3) time stop: not +0.5R within N M15 bars
      int bars = iBarShift(Symbol(), PERIOD_M15, OrderOpenTime(), false);
      if(bars >= InpTimeStopBars && profitPips < InpTimeStopProfitR * origR)
      {
         double closePrice = isBuy ? Bid : Ask;
         if(OrderClose(OrderTicket(), lots, closePrice, 30, clrGray))
            Print("FTMO_Ops: time stop on #", OrderTicket());
         else
            Print("FTMO_Ops: time-stop close failed err=", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
void FlatAll(string why)
{
   for(int attempt = 0; attempt < 3; attempt++)
   {
      bool anyLeft = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderMagicNumber() != InpMagic) continue;
         if(!IsEntryOrder(OrderType())) continue;
         RefreshRates();
         double price = (OrderType() == OP_BUY) ? Bid : Ask;
         if(!OrderClose(OrderTicket(), OrderLots(), price, 30, clrWhite))
         {
            anyLeft = true;
            Print("FTMO_Ops: flat failed on #", OrderTicket(), " err=", GetLastError());
         }
      }
      if(!anyLeft) break;
      Sleep(500);
   }
   Print("FTMO_Ops: FLAT ALL (", why, ")");
}

//+------------------------------------------------------------------+
//  PANEL
//+------------------------------------------------------------------+
void UpdatePanel()
{
   string s = "";
   s += "FTMO OPS  " + (InpDryRun ? "[DRY RUN] " : "") +
        (g_haltDay || g_haltWeek ? "*** HALT: " + g_haltWhy + " ***" : "clear to trade") + "\n";
   s += "mode           : " + (InpMode == 0 ? "challenge" : (InpMode == 1 ? "verification" : "funded")) +
        "   risk " + DoubleToString(RiskPct(), 2) + "% = $" + DoubleToString(RiskCash(), 2) + "\n";
   s += "reference      : $" + DoubleToString(g_initial, 2) +
        "   balance $" + DoubleToString(AccountBalance(), 2) +
        "   equity $" + DoubleToString(AccountEquity(), 2) + "\n";
   s += "day start      : $" + DoubleToString(g_dayStart, 2) + "\n";
   s += "self daily stop: $" + DoubleToString(g_dayStart * (1 - InpSelfDailyStopPct / 100), 2) + "\n";
   s += "firm daily stop: $" + DoubleToString(g_dayStart * (1 - InpFirmDailyLossPct / 100), 2) + "\n";
   s += "self total stop: $" + DoubleToString(g_initial * (1 - InpSelfTotalStopPct / 100), 2) + "\n";
   s += "firm floor     : $" + DoubleToString(g_initial * (1 - InpFirmTotalLossPct / 100), 2) + "\n";
   s += "entries today  : " + IntegerToString(g_todayEntries) + "/" + IntegerToString(InpMaxTradesPerDay) +
        "   open " + IntegerToString(g_openCount) + "/" + IntegerToString(InpMaxOpenPositions) +
        "   consec losses " + IntegerToString(g_consecLosses) + "\n";
   s += "net USD expo   : $" + DoubleToString(NetUsdExposureUSD(), 2) +
        " (cap $" + DoubleToString(1.5 * RiskCash(), 2) + ")\n";
   s += "news window    : " + (InNewsWindow() ? "ACTIVE" : "clear") + "\n";
   s += "last signal    : " + g_lastSignal;
   Comment(s);
}
//+------------------------------------------------------------------+
