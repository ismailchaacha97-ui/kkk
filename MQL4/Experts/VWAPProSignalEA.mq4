//+------------------------------------------------------------------+
//|                                            VWAPProSignalEA.mq4   |
//|                                                                  |
//|  A deliberately small reference EA that shows how to consume VWAP  |
//|  Pro from another program.  It is *not* a strategy to run live on   |
//|  its own - it exists to demonstrate three things:                   |
//|                                                                  |
//|   1. how to read the eight buffers with iCustom (including the       |
//|      composite score, which is what an EA should trade off);         |
//|   2. how to wait for a *closed* bar, so the signal can never change  |
//|      under you (VWAP Pro computes closed bars only; the live bar is  |
//|      an estimate and is deliberately marked as such);                 |
//|   3. how to keep position sizing tied to the same dispersion the      |
//|      chart is showing (ATR-free, VWAP-native sizing).                 |
//|                                                                  |
//|  Rules used:                                                         |
//|    enter long  when the score crosses up  through +Threshold          |
//|    enter short when the score crosses down through -Threshold         |
//|    exit when the score crosses back through zero, or on a stop that   |
//|    is placed at the far band (a VWAP-native stop).                    |
//+------------------------------------------------------------------+
#property copyright "VWAP Pro"
#property version   "1.00"
#property strict

//--- must match the indicator's own inputs, in order ------------------
extern int    InpAnchor            = 1;
extern string InpAnchorTime        = "09:30";
extern int    InpAnchorShiftMin    = 0;
extern int    InpWeekStart         = 1;
extern int    InpVolumeMode        = 0;
extern double InpBuySellK          = 1.0;
extern int    InpSigmaMode         = 0;
extern int    InpZWindow           = 0;
extern bool   InpAdaptSigma        = true;
extern int    InpAdaptPriorBars    = 40;
extern int    InpBandMode          = 0;
extern double InpBand1             = 1.0;
extern double InpBand2             = 2.0;
extern double InpBand3             = 3.0;
extern bool   InpAdaptiveSignal    = true;
extern int    InpMinBars           = 3;
extern bool   InpAlerts            = false;
extern double InpAlertZ            = 2.0;
extern bool   InpPushNotify        = false;
extern bool   InpShowPanel         = false;
extern int    InpPanelCorner       = 0;
extern bool   InpShowPriceLabels   = false;
extern int    InpTZOffsetHours     = 0;
extern bool   InpVerbose           = false;

//--- EA inputs --------------------------------------------------------
extern double InpThreshold         = 0.55;   // |score| needed to act
extern double InpRiskPercent        = 0.5;    // % of equity per trade
extern double InpStopBandMultiple   = 2.0;    // stop at this band
extern int    InpMagic              = 20260918;
extern int    InpMaxSpreadPoints    = 30;

//--- buffers ----------------------------------------------------------
double BufVwap, BufUp1, BufDn1, BufUp2, BufDn2, BufUp3, BufDn3, BufScore;

//+------------------------------------------------------------------+
int OnInit()
{
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//| Read one buffer value of the last *closed* bar (shift 1).
double VpRead(int buffer, int shift)
{
   return iCustom(Symbol(), Period(), "VWAPPro",
                  InpAnchor, InpAnchorTime, InpAnchorShiftMin, InpWeekStart,
                  InpVolumeMode, InpBuySellK,
                  InpSigmaMode, InpZWindow, InpAdaptSigma, InpAdaptPriorBars,
                  InpBandMode, InpBand1, InpBand2, InpBand3,
                  InpAdaptiveSignal, InpMinBars,
                  InpAlerts, InpAlertZ, InpPushNotify,
                  InpShowPanel, InpPanelCorner, InpShowPriceLabels,
                  InpTZOffsetHours, InpVerbose,
                  buffer, shift);
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- one decision per closed bar ---------------------------------
   static datetime lastBar = 0;
   if (Time[0] == lastBar) return;
   lastBar = Time[0];

   double vwap = VpRead(0, 1);
   double up2  = VpRead(3, 1);
   double dn2  = VpRead(4, 1);
   double score = VpRead(7, 1);
   double scorePrev = VpRead(7, 2);

   if (vwap <= 0.0) return;                     // indicator not ready
   if ((Ask - Bid) / Point > InpMaxSpreadPoints) return;
   if ((int)(Time[0] - Time[1]) > 2 * PeriodSeconds()) return;          // weekend/holiday gap

   int    openLots = CountOrders(OP_BUY) + CountOrders(OP_SELL);
   double lots = LotsForRisk(vwap, up2, dn2);

   //--- exits -------------------------------------------------------
   if (openLots > 0)
   {
      if (CountOrders(OP_BUY) > 0 && score < 0.0) CloseAll(OP_BUY);
      if (CountOrders(OP_SELL) > 0 && score > 0.0) CloseAll(OP_SELL);
   }

   //--- entries: the score crossing the threshold, on a closed bar ---
   if (scorePrev < InpThreshold && score >= InpThreshold)
   {
      CloseAll(OP_SELL);
      if (CountOrders(OP_BUY) == 0 && lots > 0.0)
         OrderSend(Symbol(), OP_BUY, lots, Ask, 3, dn2, 0, "VWAP Pro", InpMagic, 0, clrLime);
   }
   if (scorePrev > -InpThreshold && score <= -InpThreshold)
   {
      CloseAll(OP_BUY);
      if (CountOrders(OP_SELL) == 0 && lots > 0.0)
         OrderSend(Symbol(), OP_SELL, lots, Bid, 3, up2, 0, "VWAP Pro", InpMagic, 0, clrTomato);
   }
}

//+------------------------------------------------------------------+
//| Position sizing from the *VWAP's own* dispersion: the distance from  |
//| the anchor to the stop band, scaled so that the trade risks a fixed  |
//| fraction of equity.  No ATR, no fixed lots - if the anchor is quiet    |
//| the size goes up, if the session is wild it goes down.                 |
//+------------------------------------------------------------------+
double LotsForRisk(double vwap, double up2, double dn2)
{
   double stopDistance = MathMax(MathAbs(vwap - up2), MathAbs(vwap - dn2)) * InpStopBandMultiple;
   if (stopDistance <= 0.0) return 0.0;
   double riskMoney = AccountEquity() * InpRiskPercent / 100.0;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if (tickValue <= 0.0 || tickSize <= 0.0) return 0.0;
   double lossPerLot = stopDistance / tickSize * tickValue;
   if (lossPerLot <= 0.0) return 0.0;
   double lots = riskMoney / lossPerLot;
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);
   if (step <= 0.0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   if (lots < minLot) lots = 0.0;               // never round *up* into a risk breach
   if (maxLot > 0.0 && lots > maxLot) lots = maxLot;
   return lots;
}

int CountOrders(int type)
{
   int n = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderMagicNumber() != InpMagic) continue;
      if (OrderSymbol() != Symbol()) continue;
      if (OrderType() == type) n++;
   }
   return n;
}

void CloseAll(int type)
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderMagicNumber() != InpMagic) continue;
      if (OrderSymbol() != Symbol()) continue;
      if (OrderType() != type) continue;
      if (type == OP_BUY)  OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrWhite);
      else                 OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrWhite);
   }
}

//+------------------------------------------------------------------+
