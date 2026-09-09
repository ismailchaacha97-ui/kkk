//+------------------------------------------------------------------+
//|                                             EMAStudy_AutoTrade.mq4|
//   Companion to EMAStudy_Signals.mq4: the same rule as a tradeable  |
//   Expert Advisor, so it can be run through the MT4 Strategy Tester  |
//   on your own broker's data - which is exactly what this study says |
//   you should do before believing any backtest, including mine.     |
//                                                                    |
//   Fills at the OPEN of the bar after the signal bar closes, which  |
//   is the backtester's convention. Use the tester's "Open prices     |
//   only" model: it reproduces this EA's fills and is much faster.    |
//   Nothing here is investment advice.                                |
//+------------------------------------------------------------------+
#property copyright   "EMA pair study"
#property link        "https://github.com/ismailchaacha97-ui/kkk"
#property version     "1.00"
#property strict

enum ENUM_EA_MODE
  {
   EA_LONG_FLAT  = 0,
   EA_LONG_SHORT = 1
  };

input ENUM_EA_MODE      TradingMode     = EA_LONG_FLAT;     // position style
input int               FastPeriod      = 60;                // fast EMA, bars of SignalTimeframe
input int               SlowPeriod      = 132;               // slow EMA, bars of SignalTimeframe
input ENUM_TIMEFRAMES   SignalTimeframe = PERIOD_CURRENT;    // study used D1
input ENUM_MA_METHOD    MAMethod        = MODE_EMA;          // MODE_SMA = the study's control
input double            FixedLots       = 0.10;              // lot size when AutoLot = false
input bool              AutoLot         = false;             // size off equity risk instead
input double            RiskPercent     = 0.5;               // ... % of equity lost on a StopAtrMult*ATR move
input int               StopAtrMult     = 0;                 // 0 = no protective stop (as studied)
input int               AtrPeriod       = 14;                //
input int               MagicNumber     = 20260909;          //
input int               SlippagePoints  = 30;                //
input int               MaxSpreadPoints = 0;                 // 0 = no filter
input bool              CloseOnNewSignal= true;              // flatten before reversing
input string            TradeComment    = "EMAStudy";        //

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int Tf()
  {
   return((SignalTimeframe == PERIOD_CURRENT) ? Period() : SignalTimeframe);
  }

//+------------------------------------------------------------------+
//| +1 long / 0 flat / -1 short, from the last CLOSED signal bar      |
//+------------------------------------------------------------------+
int DesiredState()
  {
   int tf = Tf();
   double f = iMA(Symbol(), tf, FastPeriod, 0, MAMethod, PRICE_CLOSE, 1);
   double s = iMA(Symbol(), tf, SlowPeriod, 0, MAMethod, PRICE_CLOSE, 1);
   if(!MathIsValidNumber(f) || !MathIsValidNumber(s))
      return(0);
   if(f > s)
      return(1);
   return((TradingMode == EA_LONG_SHORT) ? -1 : 0);
  }

//+------------------------------------------------------------------+
int MyPosition()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      if(OrderType() == OP_BUY)
         return(1);
      if(OrderType() == OP_SELL)
         return(-1);
     }
   return(0);
  }

//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minl = MarketInfo(Symbol(), MODE_MINLOT);
   double maxl = MarketInfo(Symbol(), MODE_MAXLOT);
   if(step > 0.0)
      lots = MathFloor(lots / step + 0.5) * step;
   if(lots < minl)
      lots = minl;
   if(lots > maxl)
      lots = maxl;
   return(lots);
  }

//+------------------------------------------------------------------+
double LotSize()
  {
   if(!AutoLot || StopAtrMult <= 0)
      return(NormalizeLots(FixedLots));
   double atr  = iATR(Symbol(), 0, AtrPeriod, 1);
   double dist = StopAtrMult * atr;
   if(dist <= 0.0 || atr <= 0.0)
      return(NormalizeLots(FixedLots));
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0.0 || tickSize <= 0.0)
      return(NormalizeLots(FixedLots));
   double lossPerLot = dist / tickSize * tickVal;
   double lots       = AccountEquity() * RiskPercent / 100.0 / lossPerLot;
   return(NormalizeLots(lots));
  }

//+------------------------------------------------------------------+
void ClosePosition()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber)
         continue;
      double px = (OrderType() == OP_BUY) ? Bid : Ask;
      if(!OrderClose(OrderTicket(), OrderLots(), px, SlippagePoints, clrSilver))
         Print("EMAStudy: close failed, error ", GetLastError(), " (order ", OrderTicket(), ")");
      else
         Print("EMAStudy: closed ", (OrderType() == OP_BUY ? "long" : "short"), " at ", DoubleToStr(px, Digits));
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(FastPeriod < 1 || SlowPeriod <= FastPeriod)
     {
      Alert("EMAStudy_AutoTrade: need 0 < FastPeriod < SlowPeriod");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(StopAtrMult > 0)
      Print("EMAStudy_AutoTrade: a protective stop is NOT part of the studied strategy - ",
            "adding one changes what is being measured.");
   return(0);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- one decision per bar, taken at that bar's open: no intrabar flip-flopping
   if(Time[0] == lastBarTime)
      return;
   lastBarTime = Time[0];

   if(Bars < SlowPeriod + 5)
     {
      Comment("EMAStudy_AutoTrade: warming up (", Bars, "/", SlowPeriod + 5, " bars)");
      return;
     }

   int want = DesiredState();
   int have = MyPosition();

   if(MaxSpreadPoints > 0 && (int)((Ask - Bid) / Point) > MaxSpreadPoints)
     {
      Comment("EMAStudy_AutoTrade: spread too wide, skipping the bar");
      return;
     }

   if(want == have)
     {
      Comment("EMAStudy_AutoTrade  ", FastPeriod, "/", SlowPeriod, "  holding ", (have == 0 ? "flat" : (have > 0 ? "LONG" : "SHORT")));
      return;
     }

   if(have != 0 && want == 0 && CloseOnNewSignal)
      ClosePosition();
   if(have != 0 && want != 0 && want != have)
     {
      if(!CloseOnNewSignal)
         return;                                    // leave it alone rather than reverse
      ClosePosition();
      RefreshRates();                               // Bid/Ask moved while the close was processing
      have = 0;
     }

   if(want == 0)
     {
      Comment("EMAStudy_AutoTrade  ", FastPeriod, "/", SlowPeriod, "  flat");
      return;
     }

   double lots = LotSize();
   if(lots <= 0.0)
      return;
   double atr = (StopAtrMult > 0) ? StopAtrMult * iATR(Symbol(), 0, AtrPeriod, 1) : 0.0;
   double price, sl = 0.0;
   int    type = (want > 0) ? OP_BUY : OP_SELL;
   price = (want > 0) ? Ask : Bid;
   if(atr > 0.0)
      sl = (want > 0) ? NormalizeDouble(price - atr, Digits) : NormalizeDouble(price + atr, Digits);

   ResetLastError();
   if(AccountFreeMarginCheck(Symbol(), type, lots) <= 0.0 || GetLastError() == 134)
     {
      Print("EMAStudy_AutoTrade: not enough free margin for ", lots, " lots");
      return;
     }

   int ticket = OrderSend(Symbol(), type, lots, price, SlippagePoints, sl, 0.0,
                          TradeComment, MagicNumber, 0, (want > 0) ? clrDodgerBlue : clrTomato);
   if(ticket < 0)
      Print("EMAStudy_AutoTrade: OrderSend failed, error ", GetLastError());
   else
      Print("EMAStudy_AutoTrade: ", (want > 0 ? "BUY " : "SELL "), lots, " lots at ", DoubleToStr(price, Digits),
            (sl > 0.0 ? " sl " + DoubleToStr(sl, Digits) : ""));
  }
//+------------------------------------------------------------------+
