//+------------------------------------------------------------------+
//| LiquidityEMA9SMA20_EA.mq4                                        |
//| Optional execution companion for LiquidityEMA9SMA20.mq4.         |
//|                                                                  |
//| Trading is disabled by default. EnableTrading must be set true   |
//| after testing on a demo account.                                 |
//+------------------------------------------------------------------+
#property strict
#property version "2.00"
#property description "EMA9/SMA20 liquidity-sweep EA with MTF confirmation, zones, risk and exits."

//--- Strategy
input int FastEMAPeriod        = 9;
input int SlowSMAPeriod        = 20;
input int SweepLookback        = 1;
input int ATRPeriod            = 14;
input bool UseRangeFilter      = true;
input double MinMASpreadATR    = 0.10;
input bool UseADXFilter        = false;
input int ADXPeriod            = 14;
input double MinADX            = 20.0;

//--- Multi-timeframe confirmation
input bool UseMultiTimeframeSetup = true;
input int HigherTimeframe         = PERIOD_H4;
input int MaxHTFSetupAgeBars      = 3;
input bool RequireEntryInHTFZone  = false;

//--- Zones
input bool UseZoneFilter          = true;
input int ZoneLookback            = 200;
input double MaxOpposingZoneATR   = 1.00;
input double DisplacementATR      = 1.00;

//--- Stop/target
// TargetMode: 0 = Fibonacci extension, 1 = fixed pips, 2 = risk/reward.
input int TargetMode              = 0;
input double FibExtension         = 1.25;
input double FixedTargetPips      = 40.0;
input double RiskRewardTarget     = 1.50;
input double StopBufferATR        = 0.10;

//--- Execution and risk
input bool EnableTrading          = false;
input bool TradeLong              = true;
input bool TradeShort             = true;
input bool UseRiskBasedLots       = true;
input double RiskPercent          = 1.00;
input double FixedLots            = 0.10;
input int MaxPyramids             = 3;
input int MagicNumber             = 90200920;
input int SlippagePoints          = 30;
input double MaxSpreadPips        = 3.0;
input string TradeComment         = "L9S20 liquidity";

//--- Exit management
input bool ExitOnInsideBar        = true;
input bool ExitOnAccumulation     = true;
input int AccumulationBars        = 2;
input double AccumulationBodyATR  = 0.40;
input bool ExitOnOppositeLiquidity = true;
input bool ExitOnMAFlip           = true;
input bool AllowPyramiding        = true;

//--- State
datetime g_lastBar = 0;

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
double PipSize()
{
   if(Digits == 3 || Digits == 5)
      return(10.0 * Point);
   return(Point);
}

double PipsToPrice(const double pips)
{
   return(pips * PipSize());
}

int LotDigits()
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step >= 1.0) return(0);
   if(step >= 0.1) return(1);
   return(2);
}

double NormalizeLotsDown(double lots)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(step <= 0.0)
      step = 0.01;

   if(lots > maxLot)
      lots = maxLot;
   lots = MathFloor(lots / step) * step;
   lots = NormalizeDouble(lots, LotDigits());
   if(lots < minLot)
      return(0.0);
   return(lots);
}

bool IsManagedOrder()
{
   return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber &&
          (OrderType() == OP_BUY || OrderType() == OP_SELL));
}

int CountDirection(const int direction)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(!IsManagedOrder())
         continue;
      if((direction > 0 && OrderType() == OP_BUY) ||
         (direction < 0 && OrderType() == OP_SELL))
         count++;
   }
   return(count);
}

int CountAllManaged()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && IsManagedOrder())
         count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Signal logic                                                      |
//+------------------------------------------------------------------+
double LowestPreviousLow(const int timeframe, const int shift)
{
   double value = iLow(NULL, timeframe, shift + 1);
   for(int n = 2; n <= SweepLookback; n++)
      value = MathMin(value, iLow(NULL, timeframe, shift + n));
   return(value);
}

double HighestPreviousHigh(const int timeframe, const int shift)
{
   double value = iHigh(NULL, timeframe, shift + 1);
   for(int n = 2; n <= SweepLookback; n++)
      value = MathMax(value, iHigh(NULL, timeframe, shift + n));
   return(value);
}

bool PassesFilters(const int timeframe, const int shift,
                   const double fast, const double slow)
{
   double atr = iATR(NULL, timeframe, ATRPeriod, shift);
   if(UseRangeFilter)
   {
      if(atr <= 0.0 || MathAbs(fast - slow) < MinMASpreadATR * atr)
         return(false);
   }
   if(UseADXFilter)
   {
      if(iADX(NULL, timeframe, ADXPeriod, PRICE_CLOSE,
              MODE_MAIN, shift) < MinADX)
         return(false);
   }
   return(true);
}

bool IsLiquiditySignalTF(const int timeframe, const int shift,
                         const int direction)
{
   if(shift < 1)
      return(false);

   double fast = iMA(NULL, timeframe, FastEMAPeriod, 0,
                     MODE_EMA, PRICE_CLOSE, shift);
   double slow = iMA(NULL, timeframe, SlowSMAPeriod, 0,
                     MODE_SMA, PRICE_CLOSE, shift);
   if(direction > 0 && fast <= slow)
      return(false);
   if(direction < 0 && fast >= slow)
      return(false);
   if(!PassesFilters(timeframe, shift, fast, slow))
      return(false);

   double o = iOpen(NULL, timeframe, shift);
   double c = iClose(NULL, timeframe, shift);
   double h = iHigh(NULL, timeframe, shift);
   double l = iLow(NULL, timeframe, shift);
   if(h < fast || l > fast)
      return(false);

   if(direction > 0)
   {
      double oldLow = LowestPreviousLow(timeframe, shift);
      return(c > o && l < oldLow && c > oldLow);
   }

   double oldHigh = HighestPreviousHigh(timeframe, shift);
   return(c < o && h > oldHigh && c < oldHigh);
}

bool FindHTFSetup(const datetime entryTime, const int direction)
{
   if(!UseMultiTimeframeSetup || HigherTimeframe <= Period())
      return(true);

   int current = iBarShift(NULL, HigherTimeframe, entryTime, false);
   if(current < 0)
      return(false);

   int first = MathMax(1, current + 1);
   int last = first + MathMax(1, MaxHTFSetupAgeBars) - 1;
   for(int h = first; h <= last; h++)
   {
      if(!IsLiquiditySignalTF(HigherTimeframe, h, direction))
         continue;

      datetime setupClose = iTime(NULL, HigherTimeframe, h - 1);
      if(setupClose <= 0 || entryTime < setupClose)
         continue;

      if(RequireEntryInHTFZone)
      {
         int lowerShift = iBarShift(NULL, 0, entryTime, false);
         if(lowerShift < 0)
            continue;
         double zoneHigh = iHigh(NULL, HigherTimeframe, h);
         double zoneLow = iLow(NULL, HigherTimeframe, h);
         if(iHigh(NULL, 0, lowerShift) < zoneLow ||
            iLow(NULL, 0, lowerShift) > zoneHigh)
            continue;
      }
      return(true);
   }
   return(false);
}

bool GetDemandZone(const int shift, double &low, double &high)
{
   if(shift < 2)
      return(false);
   double o = iOpen(NULL, 0, shift);
   double c = iClose(NULL, 0, shift);
   double h = iHigh(NULL, 0, shift);
   double atr = iATR(NULL, 0, ATRPeriod, shift - 1);
   if(c >= o || iClose(NULL, 0, shift - 1) <= h || atr <= 0.0)
      return(false);
   if(MathAbs(iClose(NULL, 0, shift - 1) -
              iOpen(NULL, 0, shift - 1)) < DisplacementATR * atr)
      return(false);
   low = iLow(NULL, 0, shift);
   high = MathMax(o, c);
   return(high > low);
}

bool GetSupplyZone(const int shift, double &low, double &high)
{
   if(shift < 2)
      return(false);
   double o = iOpen(NULL, 0, shift);
   double c = iClose(NULL, 0, shift);
   double l = iLow(NULL, 0, shift);
   double atr = iATR(NULL, 0, ATRPeriod, shift - 1);
   if(c <= o || iClose(NULL, 0, shift - 1) >= l || atr <= 0.0)
      return(false);
   if(MathAbs(iClose(NULL, 0, shift - 1) -
              iOpen(NULL, 0, shift - 1)) < DisplacementATR * atr)
      return(false);
   low = MathMin(o, c);
   high = iHigh(NULL, 0, shift);
   return(high > low);
}

bool GetBullishFVG(const int newest, double &low, double &high)
{
   if(newest < 1)
      return(false);
   low = iHigh(NULL, 0, newest + 2);
   high = iLow(NULL, 0, newest);
   return(low < high);
}

bool GetBearishFVG(const int newest, double &low, double &high)
{
   if(newest < 1)
      return(false);
   low = iHigh(NULL, 0, newest);
   high = iLow(NULL, 0, newest + 2);
   return(low < high);
}

bool PassesZoneFilter(const int shift, const int direction,
                      const double entry)
{
   if(!UseZoneFilter)
      return(true);
   double atr = iATR(NULL, 0, ATRPeriod, shift);
   if(atr <= 0.0)
      return(false);
   double maxDistance = MaxOpposingZoneATR * atr;
   int last = shift + MathMax(10, ZoneLookback);

   for(int base = shift + 2; base <= last; base++)
   {
      double zl = 0.0;
      double zh = 0.0;
      if(direction > 0)
      {
         if(GetSupplyZone(base, zl, zh) &&
            ((entry >= zl && entry <= zh) || (zl >= entry && zl - entry <= maxDistance)))
            return(false);
         if(GetBearishFVG(base - 1, zl, zh) &&
            ((entry >= zl && entry <= zh) || (zl >= entry && zl - entry <= maxDistance)))
            return(false);
      }
      else
      {
         if(GetDemandZone(base, zl, zh) &&
            ((entry >= zl && entry <= zh) || (zh <= entry && entry - zh <= maxDistance)))
            return(false);
         if(GetBullishFVG(base - 1, zl, zh) &&
            ((entry >= zl && entry <= zh) || (zh <= entry && entry - zh <= maxDistance)))
            return(false);
      }
   }
   return(true);
}

bool GetSignal(const int shift, const int direction)
{
   if(!IsLiquiditySignalTF(0, shift, direction))
      return(false);
   if(!FindHTFSetup(iTime(NULL, 0, shift), direction))
      return(false);
   return(PassesZoneFilter(shift, direction, iClose(NULL, 0, shift)));
}

//+------------------------------------------------------------------+
//| Levels and risk                                                  |
//+------------------------------------------------------------------+
void GetLevels(const int shift, const int direction,
               double &entry, double &stop, double &target)
{
   entry = direction > 0 ? Ask : Bid;
   double atr = iATR(NULL, 0, ATRPeriod, shift);
   if(atr <= 0.0)
      atr = 10.0 * Point;

   if(direction > 0)
      stop = iLow(NULL, 0, shift) - StopBufferATR * atr;
   else
      stop = iHigh(NULL, 0, shift) + StopBufferATR * atr;

   double risk = MathAbs(entry - stop);
   double distance = risk * FibExtension;
   if(TargetMode == 1)
      distance = PipsToPrice(FixedTargetPips);
   else if(TargetMode == 2)
      distance = risk * RiskRewardTarget;
   target = entry + direction * distance;

   double minimum = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(minimum > 0.0)
   {
      if(direction > 0)
      {
         if(entry - stop < minimum) stop = entry - minimum;
         if(target - entry < minimum) target = entry + minimum;
      }
      else
      {
         if(stop - entry < minimum) stop = entry + minimum;
         if(entry - target < minimum) target = entry - minimum;
      }
   }
   entry = NormalizeDouble(entry, Digits);
   stop = NormalizeDouble(stop, Digits);
   target = NormalizeDouble(target, Digits);
}

double LotsForRisk(const double entry, const double stop)
{
   if(!UseRiskBasedLots)
      return(NormalizeLotsDown(FixedLots));

   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double riskMoney = AccountBalance() * RiskPercent / 100.0;
   double distance = MathAbs(entry - stop);
   if(tickSize <= 0.0 || tickValue <= 0.0 || distance <= 0.0)
      return(0.0);

   double lossPerLot = distance / tickSize * tickValue;
   if(lossPerLot <= 0.0)
      return(0.0);
   return(NormalizeLotsDown(riskMoney / lossPerLot));
}

//+------------------------------------------------------------------+
//| Exit conditions                                                   |
//+------------------------------------------------------------------+
bool IsInsideBar(const int shift)
{
   return(iHigh(NULL, 0, shift) <= iHigh(NULL, 0, shift + 1) &&
          iLow(NULL, 0, shift) >= iLow(NULL, 0, shift + 1));
}

bool IsAccumulationBar(const int shift)
{
   double atr = iATR(NULL, 0, ATRPeriod, shift);
   if(atr <= 0.0)
      return(false);
   return(MathAbs(iClose(NULL, 0, shift) - iOpen(NULL, 0, shift)) <=
          AccumulationBodyATR * atr);
}

bool ShouldExit(const int direction, const int shift)
{
   double fast = iMA(NULL, 0, FastEMAPeriod, 0,
                     MODE_EMA, PRICE_CLOSE, shift);
   double slow = iMA(NULL, 0, SlowSMAPeriod, 0,
                     MODE_SMA, PRICE_CLOSE, shift);
   if(ExitOnMAFlip && ((direction > 0 && fast <= slow) ||
                       (direction < 0 && fast >= slow)))
      return(true);

   if(ExitOnInsideBar && IsInsideBar(shift))
      return(true);

   if(ExitOnAccumulation)
   {
      bool accumulation = true;
      for(int n = 0; n < MathMax(1, AccumulationBars); n++)
      {
         if(!IsAccumulationBar(shift + n))
         {
            accumulation = false;
            break;
         }
      }
      if(accumulation)
         return(true);
   }

   if(ExitOnOppositeLiquidity &&
      ((direction > 0 && GetSignal(shift, -1)) ||
       (direction < 0 && GetSignal(shift, 1))))
      return(true);

   return(false);
}

//+------------------------------------------------------------------+
//| Broker operations                                                 |
//+------------------------------------------------------------------+
bool SpreadAllowed()
{
   if(MaxSpreadPips <= 0.0)
      return(true);
   RefreshRates();
   double spreadPips = (Ask - Bid) / PipSize();
   return(spreadPips <= MaxSpreadPips);
}

bool CloseDirection(const int direction)
{
   bool result = true;
   RefreshRates();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(!IsManagedOrder())
         continue;
      if(direction != 0 && ((direction > 0 && OrderType() != OP_BUY) ||
                            (direction < 0 && OrderType() != OP_SELL)))
         continue;

      double price = OrderType() == OP_BUY ? Bid : Ask;
      if(!OrderClose(OrderTicket(), OrderLots(), price, SlippagePoints, clrOrange))
      {
         Print("L9S20 close failed #", OrderTicket(), " error ", GetLastError());
         result = false;
      }
   }
   return(result);
}

bool OpenDirection(const int direction, const int signalShift)
{
   if(!EnableTrading || !IsTradeAllowed() || !SpreadAllowed())
      return(false);
   if(direction > 0 && !TradeLong)
      return(false);
   if(direction < 0 && !TradeShort)
      return(false);

   RefreshRates();
   double entry = 0.0;
   double stop = 0.0;
   double target = 0.0;
   GetLevels(signalShift, direction, entry, stop, target);
   double lots = LotsForRisk(entry, stop);
   if(lots <= 0.0)
   {
      Print("L9S20: calculated lot size is below broker minimum or invalid");
      return(false);
   }

   int type = direction > 0 ? OP_BUY : OP_SELL;
   string comment = TradeComment + (direction > 0 ? " BUY" : " SELL");
   int ticket = OrderSend(Symbol(), type, lots, entry, SlippagePoints,
                          stop, target, comment, MagicNumber, 0,
                          direction > 0 ? clrLime : clrRed);
   if(ticket < 0)
   {
      Print("L9S20 order failed error ", GetLastError());
      return(false);
   }

   Print("L9S20 opened ", direction > 0 ? "BUY" : "SELL",
         " #", ticket, " lots ", DoubleToString(lots, LotDigits()),
         " SL ", DoubleToString(stop, Digits),
         " TP ", DoubleToString(target, Digits));
   return(true);
}

//+------------------------------------------------------------------+
//| New-bar controller                                                |
//+------------------------------------------------------------------+
void ProcessNewBar()
{
   int shift = 1;
   bool buySignal = GetSignal(shift, 1);
   bool sellSignal = GetSignal(shift, -1);

   int buys = CountDirection(1);
   int sells = CountDirection(-1);

   // Exit on the method's discretionary-style conditions. Broker SL/TP
   // remain active independently and will handle hard levels.
   if(buys > 0 && ShouldExit(1, shift))
      CloseDirection(1);
   if(sells > 0 && ShouldExit(-1, shift))
      CloseDirection(-1);

   buys = CountDirection(1);
   sells = CountDirection(-1);

   // A reverse signal closes the opposite side first.
   if(buySignal && sells > 0)
   {
      CloseDirection(-1);
      sells = 0;
   }
   if(sellSignal && buys > 0)
   {
      CloseDirection(1);
      buys = 0;
   }

   if(buySignal && buys == 0)
      OpenDirection(1, shift);
   else if(buySignal && AllowPyramiding && buys < MaxPyramids)
      OpenDirection(1, shift);

   if(sellSignal && sells == 0)
      OpenDirection(-1, shift);
   else if(sellSignal && AllowPyramiding && sells < MaxPyramids)
      OpenDirection(-1, shift);
}

//+------------------------------------------------------------------+
//| Expert lifecycle                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   if(FastEMAPeriod < 1 || SlowSMAPeriod < 1 || SweepLookback < 1 ||
      ATRPeriod < 1 || ADXPeriod < 1 || MaxPyramids < 1 ||
      RiskPercent <= 0.0 || FixedLots <= 0.0 || FibExtension <= 0.0 ||
      FixedTargetPips <= 0.0 || RiskRewardTarget <= 0.0)
      return(INIT_PARAMETERS_INCORRECT);

   g_lastBar = iTime(NULL, 0, 0);
   Print("L9S20 EA loaded. EnableTrading = ", EnableTrading ? "true" : "false");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(iBars(NULL, 0) < 100)
      return;

   datetime currentBar = iTime(NULL, 0, 0);
   if(currentBar <= 0 || currentBar == g_lastBar)
      return;

   g_lastBar = currentBar;
   ProcessNewBar();
}
//+------------------------------------------------------------------+
