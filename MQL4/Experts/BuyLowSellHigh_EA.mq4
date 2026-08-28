//+------------------------------------------------------------------+
//|                                          BuyLowSellHigh_EA.mq4  |
//|        Auto-trading companion for the BuyLowSellHigh indicator  |
//|                                                                  |
//|  Reads the arrow signals of BuyLowSellHigh.ex4 via iCustom and   |
//|  trades them: a BUY signal closes shorts and opens a long, a     |
//|  SELL signal closes longs and opens a short.                     |
//|                                                                  |
//|  Features:                                                       |
//|   - fixed-lot or risk-percent position sizing                    |
//|   - fixed-points or ATR-based stop loss / take profit            |
//|   - optional trailing stop, spread filter, one position per side |
//|   - evaluates signals once per bar on the last CLOSED bar        |
//|                                                                  |
//|  IMPORTANT: the "Signal indicator" input block below must match  |
//|  the indicator's settings, because the values are forwarded to   |
//|  iCustom() positionally. Keep the indicator's InpSignalOnClose   |
//|  = true (default) when trading with this EA.                     |
//+------------------------------------------------------------------+
#property copyright "BuyLowSellHigh EA - educational example"
#property link      ""
#property version   "1.00"
#property strict

//--- must mirror the indicator's enum values
enum EnumSignalMode
  {
   SIG_RSI_BB = 0,   // RSI + Bollinger Bands
   SIG_STOCH  = 1,   // Stochastic cross from extreme
   SIG_ZSCORE = 2    // Z-Score of price
  };

enum EnumLotMode
  {
   LOT_FIXED = 0,    // Fixed lot size
   LOT_RISK  = 1     // Risk % of balance (needs a stop loss)
  };

enum EnumSLMode
  {
   SL_FIXED = 0,     // Fixed distance in points
   SL_ATR   = 1      // ATR-based
  };

//--- inputs: SIGNAL INDICATOR (forwarded to iCustom, keep in sync!)
input string         ___Signal1         = "--- Signal indicator settings ---";
input EnumSignalMode InpMode            = SIG_RSI_BB;  // Signal mode
input int            InpRsiPeriod       = 14;          // RSI: period
input double         InpRsiBuyLevel     = 30.0;        // RSI: oversold level
input double         InpRsiSellLevel    = 70.0;        // RSI: overbought level
input int            InpBBPeriod        = 20;          // Bollinger: period
input double         InpBBDeviation     = 2.0;         // Bollinger: deviations
input int            InpStochK          = 14;          // Stochastic: %K
input int            InpStochD          = 3;           // Stochastic: %D
input int            InpStochSlowing    = 3;           // Stochastic: slowing
input double         InpStochBuyLevel   = 20.0;        // Stochastic: oversold level
input double         InpStochSellLevel  = 80.0;        // Stochastic: overbought level
input int            InpZWindow         = 100;         // Z-Score: window (bars)
input double         InpZLevel          = 2.0;         // Z-Score: entry level
input bool           InpUseTrendFilter  = true;        // Trend filter on/off
input int            InpTrendPeriod     = 200;         // Trend filter: SMA period
input bool           InpSignalOnClose   = true;        // Signal on closed bar (keep true)
input int            InpMaxBars         = 2000;        // Indicator max bars scan
input string         InpIndicatorName   = "BuyLowSellHigh"; // Indicator file name (ex4)

//--- inputs: TRADING ----------------------------------------------
input string         ___Trading         = "--- Trading ---";
input bool           InpAllowBuy        = true;        // Open longs on BUY signals
input bool           InpAllowSell       = true;        // Open shorts on SELL signals
input bool           InpCloseOnOpposite = true;        // Close position on opposite signal
input EnumLotMode    InpLotMode         = LOT_FIXED;   // Position sizing mode
input double         InpFixedLot        = 0.10;        // Fixed lot size
input double         InpRiskPercent     = 1.0;         // Risk % of balance per trade
input EnumSLMode     InpSLMode          = SL_ATR;      // Stop loss mode
input int            InpSLPoints        = 300;         // Fixed SL distance (points)
input int            InpTPPoints        = 400;         // Fixed TP distance (points)
input int            InpATRPeriod       = 14;          // ATR period (ATR SL/TP mode)
input double         InpATRMultSL       = 2.0;         // SL = ATR x this
input double         InpATRMultTP       = 3.0;         // TP = ATR x this
input bool           InpUseTrailing     = false;       // Trailing stop on/off
input int            InpTrailPoints     = 250;         // Trailing distance (points)
input double         InpMaxSpreadPoints = 40;          // Max spread in points (0 = off)
input int            InpMagic           = 20260828;    // Magic number
input int            InpSlippagePoints  = 30;          // Max slippage (points)
input string         InpOrderComment    = "BuyLowSellHigh"; // Order comment

//--- constants
#define RETRY_COUNT   3
#define RETRY_SLEEP   500

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("BuyLowSellHigh EA started on ", Symbol(), " ",
         DoubleToString(Ask, Digits), "/", DoubleToString(Bid, Digits));
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }
//+------------------------------------------------------------------+
//| Tick handler                                                     |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(Bars < InpTrendPeriod + 10)
      return;

   //--- manage trailing on every tick
   if(InpUseTrailing)
      ManageTrailing();

   //--- act once per bar, on the first tick of a new bar
   if(!IsNewBar())
      return;

   if(!IsTradeAllowed())
     {
      Print("Trading not allowed (AutoTrading disabled or trade context busy).");
      return;
     }

   //--- read the signals of the last CLOSED bar
   bool buySig  = ReadSignal(0);   // buffer 0 = buy arrows
   bool sellSig = ReadSignal(1);   // buffer 1 = sell arrows

   if(!buySig && !sellSig)
      return;

   ExecuteSignals(buySig, sellSig);
  }
//+------------------------------------------------------------------+
//| New bar detection                                                |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime lastBar = 0;
   if(Time[0] != lastBar)
     {
      lastBar = Time[0];
      return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
//| Read one signal buffer of the indicator at shift 1 (closed bar)  |
//+------------------------------------------------------------------+
bool ReadSignal(const int bufferIndex)
  {
   double v = iCustom(Symbol(), 0, InpIndicatorName,
                      InpMode,
                      InpRsiPeriod, InpRsiBuyLevel, InpRsiSellLevel,
                      InpBBPeriod, InpBBDeviation,
                      InpStochK, InpStochD, InpStochSlowing,
                      InpStochBuyLevel, InpStochSellLevel,
                      InpZWindow, InpZLevel,
                      InpUseTrendFilter, InpTrendPeriod,
                      InpSignalOnClose, InpMaxBars,
                      bufferIndex, 1);

   int err = GetLastError();
   if(err != 0 && err != 4051) // 4051 sometimes shows up harmlessly on first calls
      Print("iCustom error ", err, " reading ", InpIndicatorName, " buffer ", bufferIndex);

   return(v != EMPTY_VALUE && v != 0.0);
  }
//+------------------------------------------------------------------+
//| Turn signals into orders                                         |
//+------------------------------------------------------------------+
void ExecuteSignals(const bool buySig, const bool sellSig)
  {
   int buys = 0, sells = 0;
   CountPositions(buys, sells);

   if(buySig)
     {
      if(InpCloseOnOpposite && sells > 0)
         CloseAllPositions(OP_SELL);
      if(InpAllowBuy && !HasPosition(OP_BUY) && SpreadOK())
         OpenPosition(OP_BUY);
     }

   if(sellSig)
     {
      if(InpCloseOnOpposite && buys > 0)
         CloseAllPositions(OP_BUY);
      if(InpAllowSell && !HasPosition(OP_SELL) && SpreadOK())
         OpenPosition(OP_SELL);
     }
  }
//+------------------------------------------------------------------+
//| Open a market order with SL/TP, with retries                     |
//+------------------------------------------------------------------+
void OpenPosition(const int type)
  {
   double slDist = StopDistance(true);
   double tpDist = StopDistance(false);

   double lots = CalcLots(slDist);
   if(lots <= 0.0)
     {
      Print("Lot calculation failed, order skipped.");
      return;
     }

   for(int attempt = 1; attempt <= RETRY_COUNT; attempt++)
     {
      RefreshRates();
      double price  = (type == OP_BUY) ? Ask : Bid;
      double sl     = (type == OP_BUY) ? price - slDist : price + slDist;
      double tp     = (type == OP_BUY) ? price + tpDist : price - tpDist;
      color  clr    = (type == OP_BUY) ? clrDodgerBlue : clrTomato;

      int ticket = OrderSend(Symbol(), type, lots,
                             NormalizeDouble(price, Digits),
                             InpSlippagePoints,
                             NormalizeDouble(sl, Digits),
                             NormalizeDouble(tp, Digits),
                             InpOrderComment, InpMagic, 0, clr);
      if(ticket >= 0)
        {
         Print((type == OP_BUY ? "BUY" : "SELL"), " opened #", ticket,
               " lots=", DoubleToString(lots, 2),
               " sl=", DoubleToString(sl, Digits),
               " tp=", DoubleToString(tp, Digits));
         return;
        }

      int err = GetLastError();
      Print("OrderSend failed (attempt ", attempt, "/", RETRY_COUNT, "): error ", err);
      // retry only on recoverable errors
      if(err == 129 || err == 135 || err == 136 || err == 137 || err == 146 || err == 128)
         Sleep(RETRY_SLEEP);
      else
         break;
     }
  }
//+------------------------------------------------------------------+
//| Stop loss / take profit distance in price units                  |
//+------------------------------------------------------------------+
double StopDistance(const bool isStopLoss)
  {
   double dist;
   if(InpSLMode == SL_FIXED)
     {
      dist = (isStopLoss ? InpSLPoints : InpTPPoints) * Point;
     }
   else
     {
      double atr = iATR(NULL, 0, InpATRPeriod, 1);
      if(atr <= 0.0)
         atr = (isStopLoss ? InpSLPoints : InpTPPoints) * Point;
      dist = atr * (isStopLoss ? InpATRMultSL : InpATRMultTP);
     }

   //--- respect the broker minimum stop level
   double minDist = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(dist < minDist)
      dist = minDist;
   if(dist <= 0.0)
      dist = 10 * Point;
   return(dist);
  }
//+------------------------------------------------------------------+
//| Lot size: fixed or risk-percent of balance vs SL distance        |
//+------------------------------------------------------------------+
double CalcLots(const double slDist)
  {
   double lots = InpFixedLot;

   if(InpLotMode == LOT_RISK)
     {
      double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
      double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
      if(tickValue > 0.0 && tickSize > 0.0 && slDist > 0.0)
        {
         double valuePerPointPerLot = tickValue * (Point / tickSize);
         double lossPerLot          = (slDist / Point) * valuePerPointPerLot;
         double riskMoney           = AccountBalance() * InpRiskPercent / 100.0;
         if(lossPerLot > 0.0)
            lots = riskMoney / lossPerLot;
        }
     }

   //--- normalize to broker limits
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(lotStep > 0.0)
      lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot)
      lots = minLot;
   if(lots > maxLot)
      lots = maxLot;
   //--- round to the number of decimals implied by the lot step
   int lotDigits = 2;
   if(lotStep > 0.0)
      lotDigits = (int)MathRound(-MathLog10(lotStep));
   if(lotDigits < 0)
      lotDigits = 0;
   return(NormalizeDouble(lots, lotDigits));
  }
//+------------------------------------------------------------------+
//| Spread filter                                                    |
//+------------------------------------------------------------------+
bool SpreadOK()
  {
   if(InpMaxSpreadPoints <= 0.0)
      return(true);
   RefreshRates();
   double spreadPoints = (Ask - Bid) / Point;
   if(spreadPoints > InpMaxSpreadPoints)
     {
      Print("Spread too high (", DoubleToString(spreadPoints, 1),
            " pts), trade skipped.");
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
//| Count open positions of this EA                                  |
//+------------------------------------------------------------------+
void CountPositions(int &buys, int &sells)
  {
   buys  = 0;
   sells = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic)
         continue;
      if(OrderType() == OP_BUY)
         buys++;
      if(OrderType() == OP_SELL)
         sells++;
     }
  }
//+------------------------------------------------------------------+
//| Is there an open position of the given type?                     |
//+------------------------------------------------------------------+
bool HasPosition(const int type)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic)
         continue;
      if(OrderType() == type)
         return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+
//| Close all positions of the given type, with retries              |
//+------------------------------------------------------------------+
void CloseAllPositions(const int type)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic)
         continue;
      if(OrderType() != type)
         continue;

      for(int attempt = 1; attempt <= RETRY_COUNT; attempt++)
        {
         RefreshRates();
         double closePrice = (type == OP_BUY) ? Bid : Ask;
         bool ok = OrderClose(OrderTicket(), OrderLots(),
                              NormalizeDouble(closePrice, Digits),
                              InpSlippagePoints, clrYellow);
         if(ok)
           {
            Print("Closed #", OrderTicket());
            break;
           }
         int err = GetLastError();
         Print("OrderClose failed (attempt ", attempt, "/", RETRY_COUNT,
               "): error ", err);
         if(err == 129 || err == 135 || err == 136 || err == 137 || err == 146 || err == 138)
            Sleep(RETRY_SLEEP);
         else
            break;
        }
     }
  }
//+------------------------------------------------------------------+
//| Trailing stop                                                    |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   double trailDist = InpTrailPoints * Point;
   if(trailDist <= 0.0)
      return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic)
         continue;

      RefreshRates();
      if(OrderType() == OP_BUY)
        {
         double newSL = NormalizeDouble(Bid - trailDist, Digits);
         if(Bid - OrderOpenPrice() > trailDist &&
            (OrderStopLoss() == 0.0 || newSL > OrderStopLoss() + Point / 2.0))
            ModifySLTP(OrderTicket(), newSL, OrderTakeProfit());
        }
      else if(OrderType() == OP_SELL)
        {
         double newSL = NormalizeDouble(Ask + trailDist, Digits);
         if(OrderOpenPrice() - Ask > trailDist &&
            (OrderStopLoss() == 0.0 || newSL < OrderStopLoss() - Point / 2.0))
            ModifySLTP(OrderTicket(), newSL, OrderTakeProfit());
        }
     }
  }
//+------------------------------------------------------------------+
//| Modify SL/TP with retries                                        |
//+------------------------------------------------------------------+
void ModifySLTP(const int ticket, const double sl, const double tp)
  {
   for(int attempt = 1; attempt <= RETRY_COUNT; attempt++)
     {
      if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES))
        {
         bool ok = OrderModify(ticket, OrderOpenPrice(),
                               NormalizeDouble(sl, Digits),
                               NormalizeDouble(tp, Digits), 0, clrGray);
         if(ok)
            return;
        }
      int err = GetLastError();
      if(err == 1) // ERR_NO_RESULT: SL already at that level
         return;
      Print("OrderModify failed (attempt ", attempt, "/", RETRY_COUNT, "): error ", err);
      if(err == 130 || err == 135 || err == 138 || err == 146)
         Sleep(RETRY_SLEEP);
      else
         break;
     }
  }
//+------------------------------------------------------------------+
