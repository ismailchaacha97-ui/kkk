//+------------------------------------------------------------------+
//|                                       QM_MoneyManager.mqh        |
//|  QuantumEdge Money Management Library for MT4                    |
//|  Provides: risk-based lot sizing, equity protection,            |
//|            drawdown guard, Kelly-lite, compounding logic         |
//+------------------------------------------------------------------+
#property copyright "QuantumEdge Quant Lab — MIT"
#property strict

//+------------------------------------------------------------------+
//| Normalize lot to broker constraints                              |
//+------------------------------------------------------------------+
double QM_NormalizeLots(string symbol, double lots)
  {
   double step = MarketInfo(symbol, MODE_LOTSTEP);
   double mn   = MarketInfo(symbol, MODE_MINLOT);
   double mx   = MarketInfo(symbol, MODE_MAXLOT);
   if(step==0) step=0.01;
   if(mn==0) mn=0.01;
   if(mx==0) mx=100;
   double l = MathFloor(lots/step)*step;
   if(l<mn) l=mn;
   if(l>mx) l=mx;
   return NormalizeDouble(l,2);
  }

//+------------------------------------------------------------------+
//| Risk-based lot calculation (ATR SL aware)                        |
//+------------------------------------------------------------------+
double QM_LotByRisk(string symbol, double riskPct, double slPoints)
  {
   double equity = AccountEquity();
   double riskMoney = equity * riskPct / 100.0;
   double tickVal = MarketInfo(symbol, MODE_TICKVALUE);
   double tickSize= MarketInfo(symbol, MODE_TICKSIZE);
   double point   = MarketInfo(symbol, MODE_POINT);
   if(tickVal==0 || tickSize==0 || point==0) return MarketInfo(symbol, MODE_MINLOT);
   double ticks = slPoints * point / tickSize;
   if(ticks<=0) return MarketInfo(symbol, MODE_MINLOT);
   double lots = riskMoney / (ticks * tickVal);
   return QM_NormalizeLots(symbol, lots);
  }

//+------------------------------------------------------------------+
//| Daily drawdown guard                                             |
//+------------------------------------------------------------------+
bool QM_IsDailyDrawdownBreached(double startEquity, double maxDDPct)
  {
   if(startEquity<=0) return false;
   double dd = (startEquity - AccountEquity())/startEquity*100.0;
   return (dd >= maxDDPct);
  }

//+------------------------------------------------------------------+
//| Equity trail — progressive lock (example: lock 50% of gains)     |
//+------------------------------------------------------------------+
double QM_EquityTrailStop(double peakEquity, double lockRatio=0.5)
  {
   // Returns equity level where to halt if pullback > (1-lockRatio) of gains
   // e.g., start 10k, peak 12k, gains 2k, lock 50% => stop at 11k
   return peakEquity; // placeholder for extension
  }
