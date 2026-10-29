//+------------------------------------------------------------------+
//|                                    QM_VolatilityFilter.mqh       |
//|  Adaptive volatility regime detection & frequency throttle        |
//+------------------------------------------------------------------+
#property copyright "QuantumEdge Quant Lab — MIT"
#property strict

enum ENUM_VOL_REGIME { VOL_LOW=0, VOL_NORMAL=1, VOL_HIGH=2 };

ENUM_VOL_REGIME QM_GetRegime(string sym, int atrPeriod, int atrMAPeriod, double hiMult, double loMult)
  {
   double atr = iATR(sym, 0, atrPeriod, 1);
   double sum=0; int n=0;
   for(int k=1;k<=atrMAPeriod+5;k++){ double a=iATR(sym,0,atrPeriod,k); if(a>0){sum+=a; n++; if(n>=atrMAPeriod) break; } }
   if(n==0 || atr==0) return VOL_NORMAL;
   double ma = sum/n;
   if(atr > ma*hiMult) return VOL_HIGH;
   if(atr < ma*loMult) return VOL_LOW;
   return VOL_NORMAL;
  }

bool QM_ShouldThrottle(ENUM_VOL_REGIME regime, int cooldownBars, int &counter)
  {
   if(regime==VOL_HIGH && counter>0){ counter--; return true; }
   if(regime==VOL_HIGH) counter=cooldownBars;
   return false;
  }
