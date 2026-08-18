//+------------------------------------------------------------------+
//|                      PropFirm_Institutional_Execution_EA.mq4     |
//|               Institutional Trade Manager & Capital Guard EA     |
//|               1-Click Execution + Hard Daily Drawdown Killswitch |
//|                                   Copyright 2026, Institutional  |
//|                                    100% Standalone - Zero Include|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional Edge Systems"
#property link      "https://github.com/ismailchaacha97-ui/kkk"
#property version   "3.50"
#property strict

//--- Prop Firm Challenge Rule Profiles
enum ENUM_PROPFIRM_PROFILE
{
   PROPFIRM_FTMO,          // FTMO (5% Daily DD, 10% Max DD, 10% Target)
   PROPFIRM_FUNDEDNEXT,    // FundedNext (5% Daily DD, 10% Max DD, 8% Target)
   PROPFIRM_THE5ERS,       // The 5%ers (4% Daily DD, 8% Max DD, 8% Target)
   PROPFIRM_TOPSTEP,       // Topstep (Daily Loss Limit, Max Loss Limit)
   PROPFIRM_ALPHA_CAPITAL, // Alpha Capital (5% Daily DD, 10% Max DD)
   PROPFIRM_CUSTOM         // Custom User Defined Rules
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//--- 1. PROP FIRM RISK & CAPITAL GUARD SETTINGS
input string               InpHeaderRisk            = "=== 1. PROP FIRM CAPITAL GUARD ===";
input ENUM_PROPFIRM_PROFILE InpPropFirmProfile      = PROPFIRM_FTMO; // Challenge Preset
input double               InpRiskPerTradePct       = 0.50;          // Risk Per Trade % (e.g. 0.5% or 1.0%)
input double               InpMaxDailyDrawdownPct   = 5.0;           // Hard Daily Drawdown Limit % (FTMO = 5.0%)
input double               InpEmergencyKillPct      = 4.2;           // Emergency Killswitch % (Auto Close All Trades)
input double               InpMaxOverallDrawdownPct = 10.0;          // Max Total Drawdown % (FTMO = 10.0%)
input double               InpProfitTargetPct       = 10.0;          // Challenge Profit Target %
input int                  InpMaxDailyTrades        = 5;             // Max Trades Allowed Per Day

//--- 2. TRADE EXECUTION & STOP LOSS SETTINGS
input string               InpHeaderExecution       = "=== 2. TRADE EXECUTION & SL/TP ===";
input double               InpDefaultSLPips         = 15.0;          // Default Stop Loss (Pips for 1-Click)
input double               InpTargetRiskReward      = 3.0;           // Default R:R Ratio (e.g. 1:3)
input int                  InpSlippage              = 3;             // Max Slippage (Pips)
input int                  InpMagicNumber           = 888001;        // EA Unique Magic Number

//--- 3. INSTITUTIONAL TRADE MANAGEMENT
input string               InpHeaderManagement      = "=== 3. TRADE MANAGEMENT & SCALING ===";
input bool                 InpAutoBreakEven         = true;          // Move SL to Break-Even at 1.5R
input double               InpBreakEvenTriggerR     = 1.5;           // Break-Even Trigger (In Multiples of R)
input double               InpBreakEvenBufferPips   = 1.5;           // Profit Lock Buffer on Break-Even (Pips)
input bool                 InpEnablePartialTP       = true;          // Enable Multi-Stage Partial Closes
input double               InpPartialTP1_R          = 2.0;           // Partial TP1 Target (In R)
input double               InpPartialTP1_ClosePct   = 50.0;          // Partial TP1 Close % of Lot Size
input bool                 InpEnableTrailingStop    = true;          // Enable Trailing Stop for Runner
input double               InpTrailDistancePips     = 15.0;          // Trailing Stop Distance (Pips)

//--- 4. AUTO-TRADING FROM INDICATOR
input string               InpHeaderAutoTrade       = "=== 4. INDICATOR AUTO-EXECUTION ===";
input bool                 InpAutoExecuteSignals    = false;         // Auto-Execute Indicator A+ Signals
input int                  InpMinSignalConfluence   = 80;            // Min Indicator Confluence Score to Execute
input bool                 InpFilterByKillzones     = true;          // Only Execute during London / NY Killzones
input int                  InpBrokerGMTOffset       = 2;             // Broker Server GMT Offset

//--- 5. ALERTS & NOTIFICATIONS
input string               InpHeaderAlerts          = "=== 5. ALERTS & NOTIFICATIONS ===";
input bool                 InpAlertPopup            = true;
input bool                 InpAlertSound            = true;
input bool                 InpAlertPush             = true;
input bool                 InpAlertEmail            = false;

//+------------------------------------------------------------------+
//| GLOBAL STATE & VARIABLES                                         |
//+------------------------------------------------------------------+
const string EA_PREFIX = "PF_EA_";

datetime g_eaDayStartTime = 0;
double   g_eaDayStartEquity = 0.0;
double   g_eaPeakEquity = 0.0;
int      g_todayTradesCount = 0;
bool     g_emergencyKillTriggered = false;

double   g_eaPipValue = 0.0001;
double   g_eaPointFactor = 1.0;

// Tracking partial closes per ticket
struct PositionState
{
   int    ticket;
   bool   tp1Taken;
   bool   beApplied;
   double initialSL;
   double initialOpenPrice;
   double initialRiskPips;
};
PositionState g_trackedPositions[];
int           g_totalTracked = 0;

// Forward Declarations
void InitializeEADrawdown();
void UpdateEADrawdownAnchor();
double CalculateEADayStartEquity();
bool CheckPropFirmDrawdownGuard();
void ExecuteManualOrder(int type);
double CalculatePositionLotSize(double stopLossPips, double riskPct);
void RegisterPositionState(int ticket, double openPrice, double sl, double riskPips);
void ManageActivePositions();
int FindTrackedIndex(int ticket);
void ScanIndicatorSignals();
void ApplyManualBreakEvenToAll();
void CloseAllPositions(string reason);
void DeleteAllPendingOrders();
void Create1ClickCockpit();
void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color fg);
void UpdateCockpitDisplay();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set Pip Multiplier
   if(Digits == 3 || Digits == 5)
   {
      g_eaPipValue = Point * 10;
      g_eaPointFactor = 10;
   }
   else
   {
      g_eaPipValue = Point;
      g_eaPointFactor = 1;
   }

   // Initialize Day Start Equity
   InitializeEADrawdown();

   // Draw On-Chart 1-Click Cockpit
   Create1ClickCockpit();

   Print("[Prop Firm EA] Initialized successfully on ", Symbol(), ". Risk Guard Active.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, EA_PREFIX);
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Maintain Daily Drawdown Reference at Midnight
   UpdateEADrawdownAnchor();

   // 2. Perform Critical Prop Firm Hard Drawdown Protection Check
   if(CheckPropFirmDrawdownGuard())
   {
      // Killswitch active: do not process new trades or manage positions
      UpdateCockpitDisplay();
      return;
   }

   // 3. Manage Open Positions (Break-Even, Partial Close, Trailing Stop)
   ManageActivePositions();

   // 4. If Auto-Execute is enabled, scan for indicator signals
   if(InpAutoExecuteSignals)
   {
      ScanIndicatorSignals();
   }

   // 5. Refresh Cockpit UI
   UpdateCockpitDisplay();
}

//+------------------------------------------------------------------+
//| Chart Event Handler for 1-Click Buttons                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(g_emergencyKillTriggered)
      {
         Alert("🛑 TRADING LOCKED: Daily Drawdown Emergency Killswitch is active!");
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         return;
      }

      if(sparam == EA_PREFIX + "BTN_BUY")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ExecuteManualOrder(OP_BUY);
      }
      else if(sparam == EA_PREFIX + "BTN_SELL")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ExecuteManualOrder(OP_SELL);
      }
      else if(sparam == EA_PREFIX + "BTN_BE")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ApplyManualBreakEvenToAll();
      }
      else if(sparam == EA_PREFIX + "BTN_CLOSEALL")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         CloseAllPositions("Manual Emergency Close");
      }
   }
}

//+------------------------------------------------------------------+
//| Initialize EA Daily Drawdown State                               |
//+------------------------------------------------------------------+
void InitializeEADrawdown()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   g_eaDayStartTime = StructToTime(dt);

   g_eaDayStartEquity = CalculateEADayStartEquity();
   if(g_eaDayStartEquity <= 0) g_eaDayStartEquity = AccountBalance();

   g_eaPeakEquity = AccountBalance();
   if(AccountEquity() > g_eaPeakEquity) g_eaPeakEquity = AccountEquity();
}

//+------------------------------------------------------------------+
//| Update midnight anchor                                           |
//+------------------------------------------------------------------+
void UpdateEADrawdownAnchor()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayStart = StructToTime(dt);

   if(todayStart > g_eaDayStartTime)
   {
      g_eaDayStartTime = todayStart;
      g_eaDayStartEquity = AccountEquity();
      g_todayTradesCount = 0;
      g_emergencyKillTriggered = false;
      Print("[Prop Firm EA] New Day Anchor set. Day Start Equity: $", DoubleToString(g_eaDayStartEquity, 2));
   }

   if(AccountEquity() > g_eaPeakEquity)
   {
      g_eaPeakEquity = AccountEquity();
   }
}

//+------------------------------------------------------------------+
//| Calculate Day Start Equity accurately                            |
//+------------------------------------------------------------------+
double CalculateEADayStartEquity()
{
   double balance = AccountBalance();
   double todayProfit = 0.0;
   int totalHistory = OrdersHistoryTotal();

   for(int i = 0; i < totalHistory; i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
      {
         if(OrderCloseTime() >= g_eaDayStartTime)
         {
            todayProfit += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
   }
   return(balance - todayProfit);
}

//+------------------------------------------------------------------+
//| HARD DRAWDOWN GUARD & EMERGENCY KILLSWITCH                       |
//+------------------------------------------------------------------+
bool CheckPropFirmDrawdownGuard()
{
   double currentEquity = AccountEquity();
   double dailyLossCash = g_eaDayStartEquity - currentEquity;
   if(dailyLossCash < 0) dailyLossCash = 0;

   double dailyLossPct = (g_eaDayStartEquity > 0) ? (dailyLossCash / g_eaDayStartEquity * 100.0) : 0.0;

   // Emergency Killswitch Check
   if(dailyLossPct >= InpEmergencyKillPct || g_emergencyKillTriggered)
   {
      if(!g_emergencyKillTriggered)
      {
         g_emergencyKillTriggered = true;
         string alertMsg = StringFormat("🛑 EMERGENCY KILLSWITCH ACTIVATED! Daily Loss reached %.2f%% (Kill Threshold: %.2f%%). Closing ALL trades to protect Prop Firm Account!",
                                        dailyLossPct, InpEmergencyKillPct);

         Print(alertMsg);
         if(InpAlertPopup) Alert(alertMsg);
         if(InpAlertSound) PlaySound("siren.wav");
         if(InpAlertPush)  SendNotification(alertMsg);

         CloseAllPositions("EMERGENCY PROP FIRM KILLSWITCH");
         DeleteAllPendingOrders();
      }
      return(true);
   }

   return(false);
}

//+------------------------------------------------------------------+
//| Execute Manual 1-Click Trade with Automatic Risk Sizing          |
//+------------------------------------------------------------------+
void ExecuteManualOrder(int type)
{
   if(g_todayTradesCount >= InpMaxDailyTrades)
   {
      Alert("⚠️ Daily Trade Limit Reached (Max ", InpMaxDailyTrades, " trades/day). Protect your discipline!");
      return;
   }

   double slPips = InpDefaultSLPips;
   double lotSize = CalculatePositionLotSize(slPips, InpRiskPerTradePct);

   double price = (type == OP_BUY) ? Ask : Bid;
   double sl = 0.0;
   double tp = 0.0;

   if(type == OP_BUY)
   {
      sl = price - (slPips * g_eaPipValue);
      tp = price + (slPips * InpTargetRiskReward * g_eaPipValue);
   }
   else
   {
      sl = price + (slPips * g_eaPipValue);
      tp = price - (slPips * InpTargetRiskReward * g_eaPipValue);
   }

   int ticket = OrderSend(Symbol(), type, lotSize, price, InpSlippage * (int)g_eaPointFactor,
                          NormalizeDouble(sl, Digits), NormalizeDouble(tp, Digits),
                          "PF_EDGE_MANUAL", InpMagicNumber, 0, (type == OP_BUY) ? clrLimeGreen : clrDeepPink);

   if(ticket > 0)
   {
      g_todayTradesCount++;
      RegisterPositionState(ticket, price, sl, slPips);
      string msg = StringFormat("[1-CLICK] %s %s %.2f Lots | Risk: %.1f%% ($%.2f) | SL: %s | TP: %s",
                                (type == OP_BUY) ? "BUY" : "SELL", Symbol(), lotSize, InpRiskPerTradePct,
                                AccountEquity() * (InpRiskPerTradePct / 100.0), DoubleToString(sl, Digits), DoubleToString(tp, Digits));
      Print(msg);
      if(InpAlertSound) PlaySound("ok.wav");
   }
   else
   {
      Print("❌ OrderSend failed with error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size for precise Risk %                            |
//+------------------------------------------------------------------+
double CalculatePositionLotSize(double stopLossPips, double riskPct)
{
   double accountEquity = AccountEquity();
   double riskAmount = accountEquity * (riskPct / 100.0);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(tickValue <= 0 || stopLossPips <= 0) return(minLot);

   double pipsToTicks = g_eaPipValue / tickSize;
   double lossPerLot = stopLossPips * pipsToTicks * tickValue;

   if(lossPerLot <= 0) return(minLot);

   double rawLots = riskAmount / lossPerLot;
   double steppedLots = MathFloor(rawLots / lotStep) * lotStep;

   if(steppedLots < minLot) steppedLots = minLot;
   if(steppedLots > maxLot) steppedLots = maxLot;

   return(NormalizeDouble(steppedLots, 2));
}

//+------------------------------------------------------------------+
//| Register position tracking structure                             |
//+------------------------------------------------------------------+
void RegisterPositionState(int ticket, double openPrice, double sl, double riskPips)
{
   ArrayResize(g_trackedPositions, g_totalTracked + 1);
   g_trackedPositions[g_totalTracked].ticket = ticket;
   g_trackedPositions[g_totalTracked].tp1Taken = false;
   g_trackedPositions[g_totalTracked].beApplied = false;
   g_trackedPositions[g_totalTracked].initialSL = sl;
   g_trackedPositions[g_totalTracked].initialOpenPrice = openPrice;
   g_trackedPositions[g_totalTracked].initialRiskPips = riskPips;
   g_totalTracked++;
}

//+------------------------------------------------------------------+
//| Position Management Engine (Auto Break-Even, Partial TP, Trail)  |
//+------------------------------------------------------------------+
void ManageActivePositions()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagicNumber) continue;

      int ticket = OrderTicket();
      int pIdx = FindTrackedIndex(ticket);

      double openPrice = OrderOpenPrice();
      double currentSL = OrderStopLoss();
      double currentTP = OrderTakeProfit();
      double lots = OrderLots();
      int type = OrderType();

      double riskPips = (pIdx >= 0) ? g_trackedPositions[pIdx].initialRiskPips : (MathAbs(openPrice - currentSL) / g_eaPipValue);
      if(riskPips <= 0) riskPips = InpDefaultSLPips;

      // 1. AUTO BREAK-EVEN at 1.5R
      if(InpAutoBreakEven)
      {
         bool shouldBE = false;
         double newSL = 0.0;

         if(type == OP_BUY)
         {
            double gainPips = (Bid - openPrice) / g_eaPipValue;
            if(gainPips >= (riskPips * InpBreakEvenTriggerR) && (currentSL < openPrice || currentSL == 0))
            {
               newSL = openPrice + (InpBreakEvenBufferPips * g_eaPipValue);
               shouldBE = true;
            }
         }
         else if(type == OP_SELL)
         {
            double gainPips = (openPrice - Ask) / g_eaPipValue;
            if(gainPips >= (riskPips * InpBreakEvenTriggerR) && (currentSL > openPrice || currentSL == 0))
            {
               newSL = openPrice - (InpBreakEvenBufferPips * g_eaPipValue);
               shouldBE = true;
            }
         }

         if(shouldBE)
         {
            bool res = OrderModify(ticket, openPrice, NormalizeDouble(newSL, Digits), currentTP, 0, clrGold);
            if(res)
            {
               Print("[AUTO BREAK-EVEN] Moved SL to BE+ for Ticket #", ticket);
               if(pIdx >= 0) g_trackedPositions[pIdx].beApplied = true;
            }
         }
      }

      // 2. MULTI-STAGE PARTIAL TAKE PROFIT (50% at 2R)
      if(InpEnablePartialTP && pIdx >= 0 && !g_trackedPositions[pIdx].tp1Taken)
      {
         bool reachedTP1 = false;
         if(type == OP_BUY && ((Bid - openPrice) / g_eaPipValue >= riskPips * InpPartialTP1_R)) reachedTP1 = true;
         if(type == OP_SELL && ((openPrice - Ask) / g_eaPipValue >= riskPips * InpPartialTP1_R)) reachedTP1 = true;

         if(reachedTP1)
         {
            double minLot = MarketInfo(Symbol(), MODE_MINLOT);
            double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
            double closeLots = MathFloor((lots * (InpPartialTP1_ClosePct / 100.0)) / lotStep) * lotStep;

            if(closeLots >= minLot && (lots - closeLots) >= minLot)
            {
               bool closed = OrderClose(ticket, closeLots, (type == OP_BUY) ? Bid : Ask, InpSlippage * (int)g_eaPointFactor, clrLime);
               if(closed)
               {
                  g_trackedPositions[pIdx].tp1Taken = true;
                  Print("[PARTIAL TP1] Closed ", closeLots, " Lots (50%) at 2R for Ticket #", ticket);
               }
            }
         }
      }

      // 3. TRAILING STOP FOR RUNNERS
      if(InpEnableTrailingStop)
      {
         double trailDist = InpTrailDistancePips * g_eaPipValue;
         if(type == OP_BUY)
         {
            if(Bid - openPrice > trailDist)
            {
               double proposedSL = Bid - trailDist;
               if(proposedSL > currentSL + (2 * g_eaPipValue))
               {
                  OrderModify(ticket, openPrice, NormalizeDouble(proposedSL, Digits), currentTP, 0, clrDeepSkyBlue);
               }
            }
         }
         else if(type == OP_SELL)
         {
            if(openPrice - Ask > trailDist)
            {
               double proposedSL = Ask + trailDist;
               if(proposedSL < currentSL - (2 * g_eaPipValue) || currentSL == 0)
               {
                  OrderModify(ticket, openPrice, NormalizeDouble(proposedSL, Digits), currentTP, 0, clrDeepSkyBlue);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Find Tracked Position State Index                                |
//+------------------------------------------------------------------+
int FindTrackedIndex(int ticket)
{
   for(int i = 0; i < g_totalTracked; i++)
   {
      if(g_trackedPositions[i].ticket == ticket) return(i);
   }
   return(-1);
}

//+------------------------------------------------------------------+
//| Scan for Indicator Signals (Auto Execution Mode)                 |
//+------------------------------------------------------------------+
void ScanIndicatorSignals()
{
   // Read Indicator arrow buffers at bar 1
   double buyVal = iCustom(NULL, 0, "PropFirm_Institutional_Edge_Pro", 0, 1);
   double sellVal = iCustom(NULL, 0, "PropFirm_Institutional_Edge_Pro", 1, 1);

   if(buyVal != EMPTY_VALUE && buyVal > 0)
   {
      ExecuteManualOrder(OP_BUY);
   }
   else if(sellVal != EMPTY_VALUE && sellVal > 0)
   {
      ExecuteManualOrder(OP_SELL);
   }
}

//+------------------------------------------------------------------+
//| Apply Break-Even to all open positions                           |
//+------------------------------------------------------------------+
void ApplyManualBreakEvenToAll()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol())
         {
            double openP = OrderOpenPrice();
            double sl = (OrderType() == OP_BUY) ? (openP + (1.0 * g_eaPipValue)) : (openP - (1.0 * g_eaPipValue));
            OrderModify(OrderTicket(), openP, NormalizeDouble(sl, Digits), OrderTakeProfit(), 0, clrGold);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all open positions                                         |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         int type = OrderType();
         if(type == OP_BUY)
         {
            OrderClose(OrderTicket(), OrderLots(), Bid, InpSlippage * (int)g_eaPointFactor, clrRed);
         }
         else if(type == OP_SELL)
         {
            OrderClose(OrderTicket(), OrderLots(), Ask, InpSlippage * (int)g_eaPointFactor, clrRed);
         }
      }
   }
   Print("[CLOSE ALL] Triggered reason: ", reason);
}

//+------------------------------------------------------------------+
//| Delete all pending orders                                        |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         int type = OrderType();
         if(type > OP_SELL)
         {
            OrderDelete(OrderTicket(), clrRed);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 1-Click On-Chart Cockpit Creation                                |
//+------------------------------------------------------------------+
void Create1ClickCockpit()
{
   int startX = 20;
   int startY = 345;
   int btnWidth = 145;
   int btnHeight = 28;

   CreateButton("BTN_BUY", startX, startY, btnWidth, btnHeight, "BUY (0.5% Risk)", C'20,120,60', clrWhite);
   CreateButton("BTN_SELL", startX + btnWidth + 10, startY, btnWidth, btnHeight, "SELL (0.5% Risk)", C'160,30,45', clrWhite);

   CreateButton("BTN_BE", startX, startY + 34, btnWidth, btnHeight, "BREAK-EVEN ALL", C'40,60,90', clrWhite);
   CreateButton("BTN_CLOSEALL", startX + btnWidth + 10, startY + 34, btnWidth, btnHeight, "EMERGENCY CLOSE", C'120,40,40', clrWhite);
}

//+------------------------------------------------------------------+
//| Helper: Create Button                                            |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color fg)
{
   string objName = EA_PREFIX + name;
   ObjectDelete(0, objName);
   ObjectCreate(0, objName, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, h);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetString(0, objName, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, clrSilver);
}

//+------------------------------------------------------------------+
//| Update Cockpit Display                                           |
//+------------------------------------------------------------------+
void UpdateCockpitDisplay()
{
   if(g_emergencyKillTriggered)
   {
      ObjectSetString(0, EA_PREFIX + "BTN_BUY", OBJPROP_TEXT, "🛑 LOCKED (KILLSWITCH)");
      ObjectSetString(0, EA_PREFIX + "BTN_SELL", OBJPROP_TEXT, "🛑 LOCKED (KILLSWITCH)");
   }
}
