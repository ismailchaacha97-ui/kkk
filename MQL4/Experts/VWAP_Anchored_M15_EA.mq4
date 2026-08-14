//+------------------------------------------------------------------+
//|                                       VWAP_Anchored_M15_EA.mq4   |
//|  Trades the anchored-VWAP pullback setup described in            |
//|  MQL4/Indicators/VWAP_Anchored_M15_Setup.mq4                     |
//|                                                                  |
//|  Attach to the M5 chart. VWAP + trend filters are computed on    |
//|  M15 data; the pullback trigger candle is read on the chart TF.  |
//|  Orders are sent at the OPEN of the bar following the trigger.   |
//+------------------------------------------------------------------+
#property copyright "Arena.ai"
#property version   "1.00"
#property strict

input string  __anchor__            = "----- VWAP anchor (market open) -----";
input int     AnchorHour            = 9;      // Market open hour (server time)
input int     AnchorMinute          = 30;     // Market open minute (server time)
input ENUM_APPLIED_PRICE VwapPrice  = PRICE_TYPICAL;

input string  __calc__              = "----- Calculation -----";
input ENUM_TIMEFRAMES CalcTimeframe = PERIOD_M15; // VWAP / filters timeframe
input int     VwapSlopeBars         = 1;      // VWAP slope lookback (1 x M15 = 15 min)
input int     MomentumBars          = 4;      // Momentum lookback (4 x M15 = 1 hour)
input double  MomentumPercent       = 0.10;   // Required % move over that period
input bool    RequireCloserToVwap   = true;   // Trigger candle must pull back toward VWAP
input int     NoTradeMinutes        = 60;     // No trading in the first N minutes of the session
input int     SessionMinutes        = 0;      // Tradable session length in minutes (0 = no limit)

input string  __risk__              = "----- Orders / risk -----";
input double  Lots                  = 0.10;
input bool    UseRiskPercent        = false;  // Size from % of equity instead of fixed lots
input double  RiskPercent           = 0.50;
input int     StopLossPoints        = 0;      // 0 = use trigger candle extreme
input int     TakeProfitPoints      = 0;      // 0 = no TP
input double  RiskRewardTP          = 2.0;    // TP = R multiple when TakeProfitPoints = 0 (0 = off)
input int     SlBufferPoints        = 20;     // Extra buffer beyond the trigger candle extreme
input int     Slippage              = 30;
input int     MagicNumber           = 20260814;
input int     MaxTradesPerDay       = 3;
input bool    OneTradeAtATime       = true;
input string  TradeComment          = "VWAP-M15";

datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES CalcTf()
  {
   return(CalcTimeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : CalcTimeframe);
  }

datetime SessionStart(datetime t)
  {
   long anchorSec = (long)AnchorHour * 3600 + (long)AnchorMinute * 60;
   long day = (long)((t - anchorSec) / 86400);
   return((datetime)(day * 86400 + anchorSec));
  }

long SessionId(datetime t) { return((long)SessionStart(t) / 86400); }

int MinutesIntoSession(datetime t) { return((int)((t - SessionStart(t)) / 60)); }

double AppliedPriceOf(ENUM_TIMEFRAMES tf, int shift)
  {
   double o = iOpen(NULL, tf, shift), h = iHigh(NULL, tf, shift);
   double l = iLow(NULL, tf, shift),  c = iClose(NULL, tf, shift);
   switch(VwapPrice)
     {
      case PRICE_CLOSE:    return(c);
      case PRICE_OPEN:     return(o);
      case PRICE_HIGH:     return(h);
      case PRICE_LOW:      return(l);
      case PRICE_MEDIAN:   return((h + l) / 2.0);
      case PRICE_WEIGHTED: return((h + l + 2 * c) / 4.0);
     }
   return((h + l + c) / 3.0);
  }

//--- anchored VWAP value at calc-timeframe shift
double VwapAtShift(int shift)
  {
   ENUM_TIMEFRAMES tf = CalcTf();
   datetime start = SessionStart(iTime(NULL, tf, shift));
   double pv = 0.0, vv = 0.0;
   int first = iBarShift(NULL, tf, start, false);   // shift of the session's first bar
   if(first < shift)
      first = shift;
   for(int s = first; s >= shift; s--)
     {
      datetime bt = iTime(NULL, tf, s);
      if(bt < start)
         continue;
      double vol = (double)iVolume(NULL, tf, s);
      if(vol <= 0.0) vol = 1.0;
      pv += AppliedPriceOf(tf, s) * vol;
      vv += vol;
     }
   return(vv > 0.0 ? pv / vv : 0.0);
  }

//+------------------------------------------------------------------+
bool ContextOk(int dir, double &vwapOut)
  {
   ENUM_TIMEFRAMES tf = CalcTf();
   int s = 1;   // last closed M15 bar
   if(iBars(NULL, tf) < s + MomentumBars + VwapSlopeBars + 2)
      return(false);

   double vwap     = VwapAtShift(s);
   double vwapPrev = VwapAtShift(s + VwapSlopeBars);
   if(vwap <= 0.0 || vwapPrev <= 0.0)
      return(false);
   if(SessionId(iTime(NULL, tf, s)) != SessionId(iTime(NULL, tf, s + VwapSlopeBars)))
      return(false);
   vwapOut = vwap;

   double cNow  = iClose(NULL, tf, s);
   double cPast = iClose(NULL, tf, s + MomentumBars);
   if(cPast <= 0.0)
      return(false);
   double chg = (cNow - cPast) / cPast * 100.0;

   if(dir > 0)
      return(vwap > vwapPrev && chg >= MomentumPercent);
   return(vwap < vwapPrev && chg <= -MomentumPercent);
  }

//+------------------------------------------------------------------+
int OpenPositions()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            n++;
   return(n);
  }

int TradesToday()
  {
   int n = 0;
   datetime start = SessionStart(TimeCurrent());
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderOpenTime() >= start)
            n++;
   for(int j = OrdersTotal() - 1; j >= 0; j--)
      if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber && OrderOpenTime() >= start)
            n++;
   return(n);
  }

double NormalizeLots(double lots)
  {
   double mn = MarketInfo(Symbol(), MODE_MINLOT);
   double mx = MarketInfo(Symbol(), MODE_MAXLOT);
   double st = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(st <= 0.0) st = 0.01;
   lots = MathFloor(lots / st + 0.5) * st;
   lots = MathMax(mn, MathMin(mx, lots));
   return(NormalizeDouble(lots, 2));
  }

double LotSize(double slDistance)
  {
   if(!UseRiskPercent || slDistance <= 0.0)
      return(NormalizeLots(Lots));
   double tickVal = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSz  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0.0 || tickSz <= 0.0)
      return(NormalizeLots(Lots));
   double riskMoney = AccountEquity() * RiskPercent / 100.0;
   double lossPerLot = slDistance / tickSz * tickVal;
   if(lossPerLot <= 0.0)
      return(NormalizeLots(Lots));
   return(NormalizeLots(riskMoney / lossPerLot));
  }

//+------------------------------------------------------------------+
void SendTrade(int dir, double triggerExtreme)
  {
   RefreshRates();
   double price = (dir > 0 ? Ask : Bid);
   double pt    = Point;
   double buf   = SlBufferPoints * pt;

   double sl;
   if(StopLossPoints > 0)
      sl = (dir > 0 ? price - StopLossPoints * pt : price + StopLossPoints * pt);
   else
      sl = (dir > 0 ? triggerExtreme - buf : triggerExtreme + buf);

   double slDist = MathAbs(price - sl);
   double tp = 0.0;
   if(TakeProfitPoints > 0)
      tp = (dir > 0 ? price + TakeProfitPoints * pt : price - TakeProfitPoints * pt);
   else if(RiskRewardTP > 0.0 && slDist > 0.0)
      tp = (dir > 0 ? price + slDist * RiskRewardTP : price - slDist * RiskRewardTP);

   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * pt;
   if(slDist < stopLevel)
      sl = (dir > 0 ? price - stopLevel - pt : price + stopLevel + pt);

   sl = NormalizeDouble(sl, digits);
   tp = (tp > 0.0 ? NormalizeDouble(tp, digits) : 0.0);

   double lots = LotSize(MathAbs(price - sl));
   int ticket = OrderSend(Symbol(), (dir > 0 ? OP_BUY : OP_SELL), lots,
                          NormalizeDouble(price, digits), Slippage, sl, tp,
                          TradeComment, MagicNumber, 0,
                          (dir > 0 ? clrLime : clrRed));
   if(ticket < 0)
      Print("OrderSend failed: ", GetLastError());
   else
      Print("Opened ", (dir > 0 ? "LONG" : "SHORT"), " #", ticket, " lots=", lots, " sl=", sl, " tp=", tp);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- act only once, at the open of a new chart bar
   datetime bt = Time[0];
   if(bt == g_lastBarTime)
      return;
   g_lastBarTime = bt;

   int mins = MinutesIntoSession(bt);
   if(mins < NoTradeMinutes)
      return;                                   // first hour: let VWAP establish
   if(SessionMinutes > 0 && mins > SessionMinutes)
      return;
   if(OneTradeAtATime && OpenPositions() > 0)
      return;
   if(MaxTradesPerDay > 0 && TradesToday() >= MaxTradesPerDay)
      return;

   //--- trigger candle = last closed chart bar (shift 1); entry = open of bar 0
   double o = Open[1], c = Close[1], h = High[1], l = Low[1];
   double oP = Open[2], cP = Close[2];
   bool isRed     = (c < o),  isGreen   = (c > o);
   bool prevRed   = (cP < oP), prevGreen = (cP > oP);

   double vwap = 0.0;

   //--- LONG: price above rising VWAP, +0.1% over the hour, first red pullback candle
   if(isRed && !prevRed && ContextOk(+1, vwap))
     {
      bool closer = (!RequireCloserToVwap) || ((c - vwap) < (cP - vwap));
      if(c > vwap && closer && Open[0] > vwap)
        {
         SendTrade(+1, l);
         return;
        }
     }

   //--- SHORT: price below falling VWAP, -0.1% over the hour, first green pullback candle
   if(isGreen && !prevGreen && ContextOk(-1, vwap))
     {
      bool closer = (!RequireCloserToVwap) || ((vwap - c) < (vwap - cP));
      if(c < vwap && closer && Open[0] < vwap)
        {
         SendTrade(-1, h);
         return;
        }
     }
  }
//+------------------------------------------------------------------+
