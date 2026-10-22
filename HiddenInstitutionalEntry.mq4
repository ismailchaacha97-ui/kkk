//+------------------------------------------------------------------+
//|                                 HiddenInstitutionalEntry.mq4     |
//|              Hidden Institutional Entry — Pure Price Action      |
//|                                                                  |
//|  Professional Trader & MQL4 Developer : Institutional Price      |
//|  Action Framework — Lag-Free, No-Repaint, Pure Price Structure   |
//|                                                                  |
//|  Concept:                                                        |
//|  Large participants do not chase price. They create liquidity    |
//|  events (sweep), engineer displacement (BOS/CHoCH + impulse),    |
//|  then re-enter on the discounted Order Block / Fair Value Gap    |
//|  with minimal footprint. This indicator reconstructs that        |
//|  footprint using ONLY price structure, candlestick behavior      |
//|  and optional tick-volume confirmation — no lagging oscillators. |
//|                                                                  |
//|  Core Pillars (all confirmed on CLOSED bar only):                |
//|  1) Market Structure: Swing HH/HL/LH/LL, BOS, CHoCH              |
//|  2) Liquidity Engineering: Swing sweep + aggressive rejection    |
//|  3) Displacement: Institutional impulse candle (range & body     |
//|     expansion vs ATR) that breaks structure                      |
//|  4) Institutional Zone: Last opposite Order Block + FVG          |
//|  5) Entry Trigger: Mitigation retest + engulfing/pinbar/inside  |
//|     break confirmation + optional volume spike                   |
//|                                                                  |
//|  Signals are NEVER generated on the forming bar (index 0).      |
//|  Only closed bar (index 1) is evaluated → no repaint / no lag.  |
//|  Optimized: O(limit) per tick, early exit, no heavy loops.     |
//|                                                                  |
//|  Version: 2.10  |  MT4 Build 1380+  |  Strict mode               |
//|  FIX v2.1: Default filters loosened so chart is never empty.     |
//|          Sweep & Volume OFF by default, impulse 1.20 ATR,        |
//|          brighter zones, visible on any pair/TF.                 |
//+------------------------------------------------------------------+
#property copyright "Institutional Price Action Lab — Professional Edition"
#property link      "https://github.com/ismailchaacha97-ui/kkk"
#property version   "2.10"
#property description "Hidden Institutional Entry — pure price action. Detects liquidity sweep + displacement + OB/FVG mitigation with candlestick confirmation. No lagging indicators."
#property strict

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1 clrLime       // Buy Signal
#property indicator_color2 clrRed        // Sell Signal
#property indicator_color3 clrNONE
#property indicator_color4 clrNONE
#property indicator_width1 2
#property indicator_width2 2

//--- Buffers
double BuySignalBuffer[];
double SellSignalBuffer[];
double BuyZoneBuffer[];
double SellZoneBuffer[];

//--- Inputs — Structure
input string Inp_Set_Structure = "===== MARKET STRUCTURE ====="; // === Market Structure ===
input int    InpSwingPeriod     = 5;          // Fractal Swing Period (2-10, 5 = classic 5-bar fractal)
input int    InpLookbackSwings  = 50;         // How many swings to track for structure
input int    InpBOSConfirmBars  = 10;         // Bars to confirm BOS/CHoCH after sweep
input bool   InpUseCHoCH        = true;       // Detect Change of Character (trend reversal)

//--- Inputs — Institutional Impulse
input string Inp_Set_Impulse   = "===== INSTITUTIONAL IMPULSE ====="; // === Institutional Impulse ===
input double InpImpulseATRFact  = 1.20;       // Impulse min range vs ATR(14) (1.0-2.5) LOWER = more zones
input double InpImpulseBodyFact = 0.50;       // Min body/range ratio for impulse (0.4-0.8)
input int    InpATRPeriod       = 14;        // ATR period for impulse measurement
input bool   InpRequireBOSImpulse = false;   // Impulse must break swing high/low (OFF = more zones)

//--- Inputs — Order Block & FVG
input string Inp_Set_Zones     = "===== INSTITUTIONAL ZONES (OB / FVG) ====="; // === Zones ===
input bool   InpUseOrderBlock  = true;       // Enable Order Block detection
input bool   InpUseFVG         = true;       // Enable Fair Value Gap / Imbalance
input double InpMinFVGPoints   = 2.0;        // Min FVG size in points (LOWER = more FVGs)
input int    InpMaxZones       = 15;         // Max active zones to keep (performance)
input int    InpZoneExpiryBars = 200;        // Expire zone after N bars if not mitigated
input bool   InpShowZones      = true;       // Draw OB/FVG rectangles
input color  InpBullOBColor    = C'0,150,0';     // Bullish OB - bright green, visible on black
input color  InpBearOBColor    = C'220,30,30';   // Bearish OB - bright red
input color  InpBullFVGColor   = C'0,120,180';   // Bullish FVG - blue
input color  InpBearFVGColor   = C'220,120,0';   // Bearish FVG - orange
input int    InpZoneBorderWidth= 1;          // Zone border width

//--- Inputs — Liquidity Sweep
input string Inp_Set_Sweep     = "===== LIQUIDITY SWEEP (Strict Filter) ====="; // === Liquidity ===
input bool   InpUseSweep       = false;      // Enable liquidity sweep filter (OFF = chart never empty)
input double InpSweepTolerancePts = 6;       // Sweep beyond swing by N points (wick tolerance)
input double InpRejectionFactor   = 0.35;    // Min wick/range ratio for rejection (0.30-0.65)
input int    InpSweepLookback    = 15;       // Bars to look for sweep before BOS

//--- Inputs — Entry Confirmation
input string Inp_Set_Entry     = "===== ENTRY TRIGGER ====="; // === Entry Trigger ===
input bool   InpUseEngulfing   = true;       // Require bullish/bearish engulfing
input bool   InpUsePinBar      = true;       // Allow pin bar / hammer / shooting star
input bool   InpUseInsideBreak = true;       // Allow inside-bar break (more signals)
input double InpPinBarWickFact = 0.55;        // Pin bar wick/range ratio (0.50-0.70)
input double InpEngulfBodyFact = 1.0;        // Engulfing: current body > prev body * factor
input bool   InpVolumeConfirm  = false;      // Confirm with tick volume spike (OFF for Forex)
input int    InpVolMAPeriod    = 20;         // Tick volume MA period

//--- Inputs — Risk / Display
input string Inp_Set_Display   = "===== DISPLAY & ALERTS ====="; // === Display ===
input int    InpArrowOffsetATR = 30;         // Arrow offset (ATR * % /100)
input bool   InpAlerts         = true;       // Enable alerts (popup + push + email if configured)
input bool   InpShowDashboard  = true;       // Show info panel
input bool   InpShowDebug      = true;       // Show debug: impulses found / why no signal
input int    InpMaxBarsCalc    = 600;        // Max bars to calculate (performance cap)

//--- Globals
#define MAX_ZONES 64
struct Zone
{
   datetime time;
   double   high;
   double   low;
   double   mid;
   int      type;        // +1 bullish, -1 bearish
   int      kind;        // 1 = OrderBlock, 2 = FVG
   int      barIndex;
   bool     mitigated;
   bool     active;
   string   objName;
};

Zone OB_Zones[MAX_ZONES];
Zone FVG_Zones[MAX_ZONES];
int  OB_Count = 0;
int  FVG_Count = 0;

// Swing storage
double swingHighVal[];
double swingLowVal[];
int    swingHighBar[];
int    swingLowBar[];
int    swingHighCount=0;
int    swingLowCount=0;

datetime lastAlertBuy = 0;
datetime lastAlertSell = 0;
datetime lastBarTime = 0;
int debugImpulseCount=0;
int debugSweepCount=0;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorBuffers(4);
   SetIndexBuffer(0, BuySignalBuffer);
   SetIndexBuffer(1, SellSignalBuffer);
   SetIndexBuffer(2, BuyZoneBuffer);
   SetIndexBuffer(3, SellZoneBuffer);

   SetIndexStyle(0, DRAW_ARROW, EMPTY, 2, clrLime);
   SetIndexArrow(0, 233); // up arrow
   SetIndexStyle(1, DRAW_ARROW, EMPTY, 2, clrRed);
   SetIndexArrow(1, 234); // down arrow
   SetIndexStyle(2, DRAW_NONE);
   SetIndexStyle(3, DRAW_NONE);

   SetIndexLabel(0, "Hidden Institutional BUY");
   SetIndexLabel(1, "Hidden Institutional SELL");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);
   SetIndexEmptyValue(3, EMPTY_VALUE);

   IndicatorDigits(Digits);
   IndicatorShortName("Hidden Institutional Entry v2.1");

   ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
   ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);
   ArrayInitialize(BuyZoneBuffer, EMPTY_VALUE);
   ArrayInitialize(SellZoneBuffer, EMPTY_VALUE);

   // Init zone arrays
   for(int i=0;i<MAX_ZONES;i++)
   {
      OB_Zones[i].active=false; OB_Zones[i].mitigated=false; OB_Zones[i].objName="";
      FVG_Zones[i].active=false; FVG_Zones[i].mitigated=false; FVG_Zones[i].objName="";
   }

   // Allocate swing arrays
   ArrayResize(swingHighVal, InpLookbackSwings);
   ArrayResize(swingLowVal, InpLookbackSwings);
   ArrayResize(swingHighBar, InpLookbackSwings);
   ArrayResize(swingLowBar, InpLookbackSwings);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean objects
   for(int i=ObjectsTotal()-1;i>=0;i--)
   {
      string n=ObjectName(i);
      if(StringFind(n,"HIE_OB_")==0 || StringFind(n,"HIE_FVG_")==0 || StringFind(n,"HIE_DASH")==0 || StringFind(n,"HIE_ZONE")==0 || StringFind(n,"HIE_DBG")==0)
         ObjectDelete(n);
   }
   Comment("");
}

//+------------------------------------------------------------------+
//| Helpers — Price access (safe)                                    |
//+------------------------------------------------------------------+
double barOpen(int idx)  { return iOpen(Symbol(), PERIOD_CURRENT, idx); }
double barHigh(int idx)  { return iHigh(Symbol(), PERIOD_CURRENT, idx); }
double barLow(int idx)   { return iLow(Symbol(), PERIOD_CURRENT, idx); }
double barClose(int idx) { return iClose(Symbol(), PERIOD_CURRENT, idx); }
double barVolume(int idx){ return (double)iVolume(Symbol(), PERIOD_CURRENT, idx); }

//+------------------------------------------------------------------+
//| ATR                                                              |
//+------------------------------------------------------------------+
double GetATR(int idx, int period)
{
   double atr = iATR(Symbol(), PERIOD_CURRENT, period, idx);
   if(atr==0 || atr==EMPTY_VALUE) return (High[0]-Low[0] + 10*Point); // fallback to avoid div/0
   return atr;
}

//+------------------------------------------------------------------+
//| Candlestick Patterns — Pure Price Action                         |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(int idx)
{
   if(idx < 1) return false;
   double o1 = barOpen(idx+1), c1 = barClose(idx+1);
   double o2 = barOpen(idx),   c2 = barClose(idx);
   if(c1 >= o1) return false; // prev must be bearish
   if(c2 <= o2) return false; // curr bullish
   double prevBody = MathAbs(o1 - c1);
   double currBody = MathAbs(o2 - c2);
   if(prevBody < Point) return false;
   bool bodyEngulfs = (currBody > prevBody * InpEngulfBodyFact) && (o2 <= c1 + Point) && (c2 >= o1 - Point);
   return bodyEngulfs;
}

bool IsBearishEngulfing(int idx)
{
   if(idx < 1) return false;
   double o1 = barOpen(idx+1), c1 = barClose(idx+1);
   double o2 = barOpen(idx),   c2 = barClose(idx);
   if(c1 <= o1) return false;
   if(c2 >= o2) return false;
   double prevBody = MathAbs(o1 - c1);
   double currBody = MathAbs(o2 - c2);
   if(prevBody < Point) return false;
   bool bodyEngulfs = (currBody > prevBody * InpEngulfBodyFact) && (o2 >= c1 - Point) && (c2 <= o1 + Point);
   return bodyEngulfs;
}

bool IsBullishPinBar(int idx)
{
   double o = barOpen(idx), h = barHigh(idx), l = barLow(idx), c = barClose(idx);
   double range = h - l;
   if(range <= 5*Point) return false;
   double body = MathAbs(o - c);
   if(body < Point) body = Point;
   double lowerWick = MathMin(o,c) - l;
   double upperWick = h - MathMax(o,c);
   bool wickOK = (lowerWick / range >= InpPinBarWickFact);
   bool bodySmall = (body / range <= 0.40);
   bool closeHigh = (c > o) && (upperWick / range <= 0.30);
   bool hammerShape = (lowerWick > 1.8 * body);
   return (wickOK && bodySmall) || (closeHigh && hammerShape) || hammerShape;
}

bool IsBearishPinBar(int idx)
{
   double o = barOpen(idx), h = barHigh(idx), l = barLow(idx), c = barClose(idx);
   double range = h - l;
   if(range <= 5*Point) return false;
   double body = MathAbs(o - c);
   if(body < Point) body = Point;
   double upperWick = h - MathMax(o,c);
   double lowerWick = MathMin(o,c) - l;
   bool wickOK = (upperWick / range >= InpPinBarWickFact);
   bool bodySmall = (body / range <= 0.40);
   bool closeLow = (c < o) && (lowerWick / range <= 0.30);
   bool shootingShape = (upperWick > 1.8 * body);
   return (wickOK && bodySmall) || (closeLow && shootingShape) || shootingShape;
}

bool IsInsideBar(int idx)
{
   if(idx < 1) return false;
   return (barHigh(idx) < barHigh(idx+1) && barLow(idx) > barLow(idx+1));
}

bool IsInsideBreakBullish(int idx)
{
   if(idx < 1) return false;
   if(!IsInsideBar(idx+1)) return false;
   return (barClose(idx) > barHigh(idx+1));
}
bool IsInsideBreakBearish(int idx)
{
   if(idx < 1) return false;
   if(!IsInsideBar(idx+1)) return false;
   return (barClose(idx) < barLow(idx+1));
}

// Volume spike confirmation — tick volume
bool HasVolumeSpike(int idx)
{
   if(!InpVolumeConfirm) return true;
   if(idx < InpVolMAPeriod) return true; // not enough history = pass
   double sum=0;
   for(int i=1;i<=InpVolMAPeriod;i++) sum += barVolume(idx+i);
   double ma = sum / InpVolMAPeriod;
   if(ma < 1) return true;
   return (barVolume(idx) > ma * 1.20);
}

//+------------------------------------------------------------------+
//| Fractal Swing Detection                                          |
//+------------------------------------------------------------------+
bool IsSwingHigh(int idx)
{
   int half = InpSwingPeriod/2;
   if(idx-half < 0 || idx+half >= Bars) return false;
   double h0 = barHigh(idx);
   for(int k=1;k<=half;k++)
   {
      if(barHigh(idx+k) >= h0) return false;
      if(barHigh(idx-k) > h0) return false;
   }
   return true;
}
bool IsSwingLow(int idx)
{
   int half = InpSwingPeriod/2;
   if(idx-half < 0 || idx+half >= Bars) return false;
   double l0 = barLow(idx);
   for(int k=1;k<=half;k++)
   {
      if(barLow(idx+k) <= l0) return false;
      if(barLow(idx-k) < l0) return false;
   }
   return true;
}

// Build swing arrays (most recent first)
void UpdateSwings(int limit)
{
   swingHighCount=0;
   swingLowCount=0;
   int half = InpSwingPeriod/2;
   for(int i=1+half; i < limit-half && (swingHighCount < InpLookbackSwings || swingLowCount < InpLookbackSwings); i++)
   {
      if(swingHighCount < InpLookbackSwings && IsSwingHigh(i))
      {
         swingHighVal[swingHighCount]=barHigh(i);
         swingHighBar[swingHighCount]=i;
         swingHighCount++;
      }
      if(swingLowCount < InpLookbackSwings && IsSwingLow(i))
      {
         swingLowVal[swingLowCount]=barLow(i);
         swingLowBar[swingLowCount]=i;
         swingLowCount++;
      }
   }
}

// BOS / CHoCH detection
bool IsBOSBullish(int idx)
{
   if(swingHighCount==0) return false;
   double lastHigh = EMPTY_VALUE;
   int lastBar=-1;
   for(int i=0;i<swingHighCount;i++)
   {
      if(swingHighBar[i] > idx)
      {
         lastHigh = swingHighVal[i];
         lastBar  = swingHighBar[i];
         break;
      }
   }
   if(lastHigh==EMPTY_VALUE) return false;
   if(barClose(idx) <= lastHigh) return false;
   if(lastBar - idx > 60) return false;
   return true;
}
bool IsBOSBearish(int idx)
{
   if(swingLowCount==0) return false;
   double lastLow = EMPTY_VALUE;
   int lastBar=-1;
   for(int i=0;i<swingLowCount;i++)
   {
      if(swingLowBar[i] > idx)
      {
         lastLow = swingLowVal[i];
         lastBar = swingLowBar[i];
         break;
      }
   }
   if(lastLow==EMPTY_VALUE) return false;
   if(barClose(idx) >= lastLow) return false;
   if(lastBar - idx > 60) return false;
   return true;
}

// Trend determination via structure
int CurrentStructureBias()
{
   if(swingHighCount < 2 || swingLowCount < 2) return 0;
   bool isHH = swingHighVal[0] > swingHighVal[1];
   bool isHL = swingLowVal[0] > swingLowVal[1];
   bool isLH = swingHighVal[0] < swingHighVal[1];
   bool isLL = swingLowVal[0] < swingLowVal[1];
   if(isHH && isHL) return 1;
   if(isLH && isLL) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Institutional Impulse                                            |
//+------------------------------------------------------------------+
bool IsInstitutionalImpulse(int idx, int direction)
{
   double range = barHigh(idx) - barLow(idx);
   if(range <= 5*Point) return false;
   double body = MathAbs(barOpen(idx) - barClose(idx));
   double atr = GetATR(idx+1, InpATRPeriod);
   if(atr < Point) return false;
   bool rangeExpansion = (range >= atr * InpImpulseATRFact);
   bool bodyStrong     = (body / range >= InpImpulseBodyFact);
   if(!rangeExpansion || !bodyStrong) return false;

   if(direction > 0)
   {
      if(barClose(idx) <= barOpen(idx)) return false;
      if(InpRequireBOSImpulse && !IsBOSBullish(idx)) return false;
      return true;
   }
   else
   {
      if(barClose(idx) >= barOpen(idx)) return false;
      if(InpRequireBOSImpulse && !IsBOSBearish(idx)) return false;
      return true;
   }
}

//+------------------------------------------------------------------+
//| Order Block Detection                                            |
//+------------------------------------------------------------------+
bool FindBullishOrderBlockForImpulse(int impulseIdx, double &obHigh, double &obLow, int &obIdx)
{
   for(int k=1;k<=6;k++)
   {
      int idx = impulseIdx + k;
      if(idx >= Bars-2) break;
      double o = barOpen(idx), c = barClose(idx);
      if(c < o)
      {
         obHigh = barHigh(idx);
         obLow  = barLow(idx);
         obIdx = idx;
         return true;
      }
   }
   return false;
}
bool FindBearishOrderBlockForImpulse(int impulseIdx, double &obHigh, double &obLow, int &obIdx)
{
   for(int k=1;k<=6;k++)
   {
      int idx = impulseIdx + k;
      if(idx >= Bars-2) break;
      double o = barOpen(idx), c = barClose(idx);
      if(c > o)
      {
         obHigh = barHigh(idx);
         obLow  = barLow(idx);
         obIdx = idx;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Fair Value Gap (Imbalance) — 3-bar pattern                       |
//+------------------------------------------------------------------+
bool IsBullishFVG(int idx, double &fvgHigh, double &fvgLow)
{
   if(idx < 1 || idx+2 >= Bars) return false;
   double h0 = barHigh(idx+2);
   double l2 = barLow(idx);
   if(l2 <= h0) return false;
   double gap = l2 - h0;
   double minSize = InpMinFVGPoints * Point;
   double atr = GetATR(idx+1, 14);
   // show FVG if gap > minSize OR > 5% ATR - much looser
   if(gap < minSize && gap < atr * 0.05) return false;
   fvgHigh = l2;
   fvgLow  = h0;
   return true;
}
bool IsBearishFVG(int idx, double &fvgHigh, double &fvgLow)
{
   if(idx < 1 || idx+2 >= Bars) return false;
   double l0 = barLow(idx+2);
   double h2 = barHigh(idx);
   if(h2 >= l0) return false;
   double gap = l0 - h2;
   double minSize = InpMinFVGPoints * Point;
   double atr = GetATR(idx+1, 14);
   if(gap < minSize && gap < atr * 0.05) return false;
   fvgHigh = l0;
   fvgLow  = h2;
   return true;
}

//+------------------------------------------------------------------+
//| Liquidity Sweep (Stop Hunt)                                      |
//+------------------------------------------------------------------+
bool IsLiquiditySweepLow(int idx)
{
   double swingLow = EMPTY_VALUE;
   for(int s=0;s<swingLowCount;s++)
   {
      if(swingLowBar[s] > idx && swingLowBar[s] - idx <= InpSweepLookback)
      {
         swingLow = swingLowVal[s];
         break;
      }
   }
   if(swingLow==EMPTY_VALUE) return false;
   double l = barLow(idx);
   double c = barClose(idx);
   double o = barOpen(idx);
   double h = barHigh(idx);
   double tolerance = InpSweepTolerancePts * Point;
   bool swept = (l < swingLow - tolerance*0.5) || (l < swingLow && c > swingLow);
   if(!swept) return false;
   double range = h - l;
   if(range <= 5*Point) return false;
   double lowerWick = MathMin(o,c) - l;
   bool rejection = (lowerWick / range >= InpRejectionFactor);
   bool closeInside = (c > swingLow);
   return rejection && closeInside;
}

bool IsLiquiditySweepHigh(int idx)
{
   double swingHigh = EMPTY_VALUE;
   for(int s=0;s<swingHighCount;s++)
   {
      if(swingHighBar[s] > idx && swingHighBar[s] - idx <= InpSweepLookback)
      {
         swingHigh = swingHighVal[s];
         break;
      }
   }
   if(swingHigh==EMPTY_VALUE) return false;
   double h = barHigh(idx);
   double c = barClose(idx);
   double o = barOpen(idx);
   double l = barLow(idx);
   double tolerance = InpSweepTolerancePts * Point;
   bool swept = (h > swingHigh + tolerance*0.5) || (h > swingHigh && c < swingHigh);
   if(!swept) return false;
   double range = h - l;
   if(range <= 5*Point) return false;
   double upperWick = h - MathMax(o,c);
   bool rejection = (upperWick / range >= InpRejectionFactor);
   bool closeInside = (c < swingHigh);
   return rejection && closeInside;
}

bool HasRecentSweepLow(int idx, int lookback)
{
   for(int i=idx+1; i<= idx+lookback && i < Bars-1; i++)
      if(IsLiquiditySweepLow(i)) return true;
   return false;
}
bool HasRecentSweepHigh(int idx, int lookback)
{
   for(int i=idx+1; i<= idx+lookback && i < Bars-1; i++)
      if(IsLiquiditySweepHigh(i)) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Zone Management                                                  |
//+------------------------------------------------------------------+
void AddOBZone(int type, double hi, double lo, int barIdx, datetime t)
{
   double atr = GetATR(barIdx+1, 14);
   double tol = MathMax(Point*5, atr*0.1);
   for(int i=0;i<OB_Count;i++)
      if(OB_Zones[i].active && MathAbs(OB_Zones[i].high - hi) < tol && MathAbs(OB_Zones[i].low - lo) < tol)
         return;
   if(OB_Count >= MAX_ZONES)
   {
      if(OB_Zones[MAX_ZONES-1].objName != "")
      {
         ObjectDelete(OB_Zones[MAX_ZONES-1].objName);
         ObjectDelete(OB_Zones[MAX_ZONES-1].objName+"_L");
      }
      OB_Count = MAX_ZONES-1;
   }
   for(int i=OB_Count;i>0;i--) OB_Zones[i]=OB_Zones[i-1];
   OB_Zones[0].high = hi;
   OB_Zones[0].low  = lo;
   OB_Zones[0].mid  = (hi+lo)/2.0;
   OB_Zones[0].type = type;
   OB_Zones[0].kind = 1;
   OB_Zones[0].barIndex = barIdx;
   OB_Zones[0].time = t;
   OB_Zones[0].active = true;
   OB_Zones[0].mitigated = false;
   OB_Zones[0].objName = "HIE_OB_"+IntegerToString(type>0?1:2)+"_"+IntegerToString(barIdx)+"_"+IntegerToString(MathRand());
   OB_Count++;
}

void AddFVGZone(int type, double hi, double lo, int barIdx, datetime t)
{
   double atr = GetATR(barIdx+1, 14);
   double tol = MathMax(Point*3, atr*0.08);
   for(int i=0;i<FVG_Count;i++)
      if(FVG_Zones[i].active && MathAbs(FVG_Zones[i].high - hi) < tol && MathAbs(FVG_Zones[i].low - lo) < tol)
         return;
   if(FVG_Count >= MAX_ZONES)
   {
      if(FVG_Zones[MAX_ZONES-1].objName != "")
      {
         ObjectDelete(FVG_Zones[MAX_ZONES-1].objName);
         ObjectDelete(FVG_Zones[MAX_ZONES-1].objName+"_L");
      }
      FVG_Count = MAX_ZONES-1;
   }
   for(int i=FVG_Count;i>0;i--) FVG_Zones[i]=FVG_Zones[i-1];
   FVG_Zones[0].high = hi;
   FVG_Zones[0].low  = lo;
   FVG_Zones[0].mid  = (hi+lo)/2.0;
   FVG_Zones[0].type = type;
   FVG_Zones[0].kind = 2;
   FVG_Zones[0].barIndex = barIdx;
   FVG_Zones[0].time = t;
   FVG_Zones[0].active = true;
   FVG_Zones[0].mitigated = false;
   FVG_Zones[0].objName = "HIE_FVG_"+IntegerToString(type>0?1:2)+"_"+IntegerToString(barIdx)+"_"+IntegerToString(MathRand());
   FVG_Count++;
}

void CheckMitigationAndExpiry(int currentBar)
{
   for(int i=0;i<OB_Count;i++)
   {
      if(!OB_Zones[i].active || OB_Zones[i].mitigated) continue;
      if(currentBar - OB_Zones[i].barIndex > InpZoneExpiryBars)
      {
         OB_Zones[i].active=false;
         ObjectDelete(OB_Zones[i].objName);
         ObjectDelete(OB_Zones[i].objName+"_L");
         continue;
      }
   }
   for(int i=0;i<FVG_Count;i++)
   {
      if(!FVG_Zones[i].active || FVG_Zones[i].mitigated) continue;
      if(currentBar - FVG_Zones[i].barIndex > InpZoneExpiryBars)
      {
         FVG_Zones[i].active=false;
         ObjectDelete(FVG_Zones[i].objName);
         ObjectDelete(FVG_Zones[i].objName+"_L");
         continue;
      }
   }
}

bool IsPriceInBullishZone(int idx, Zone &z)
{
   double l = barLow(idx);
   double c = barClose(idx);
   double h = barHigh(idx);
   // any interaction: wick pierces zone or body closes inside
   bool wickIn = (l <= z.high && l >= z.low) || (h >= z.low && h <= z.high);
   bool closeIn = (c <= z.high && c >= z.low);
   bool engulfsZone = (l < z.low && c > z.low);
   return (wickIn || closeIn || engulfsZone);
}
bool IsPriceInBearishZone(int idx, Zone &z)
{
   double h = barHigh(idx);
   double c = barClose(idx);
   double l = barLow(idx);
   bool wickIn = (h >= z.low && h <= z.high) || (l >= z.low && l <= z.high);
   bool closeIn = (c >= z.low && c <= z.high);
   bool engulfsZone = (h > z.high && c < z.high);
   return (wickIn || closeIn || engulfsZone);
}

//+------------------------------------------------------------------+
//| Entry Trigger — Confluence                                        |
//+------------------------------------------------------------------+
bool IsBullishEntryTrigger(int idx)
{
   bool engulf = InpUseEngulfing && IsBullishEngulfing(idx);
   bool pin    = InpUsePinBar && IsBullishPinBar(idx);
   bool inside = InpUseInsideBreak && IsInsideBreakBullish(idx);
   bool pattern = (engulf || pin || inside);
   if(!pattern) return false;
   if(!HasVolumeSpike(idx)) return false;
   return true;
}
bool IsBearishEntryTrigger(int idx)
{
   bool engulf = InpUseEngulfing && IsBearishEngulfing(idx);
   bool pin    = InpUsePinBar && IsBearishPinBar(idx);
   bool inside = InpUseInsideBreak && IsInsideBreakBearish(idx);
   bool pattern = (engulf || pin || inside);
   if(!pattern) return false;
   if(!HasVolumeSpike(idx)) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Drawing — FIXED TO BE VISIBLE                                    |
//+------------------------------------------------------------------+
void DrawZone(Zone &z)
{
   if(!InpShowZones) return;
   if(z.objName=="") return;
   datetime end = Time[0] + Period()*60*10; // extend 10 bars forward so always visible
   if(ObjectFind(0, z.objName) >= 0)
   {
      ObjectSetInteger(0, z.objName, OBJPROP_TIME2, end);
      ObjectSetInteger(0, z.objName+"_L", OBJPROP_TIME2, end);
      return;
   }
   datetime start = z.time;
   double hi = z.high;
   double lo = z.low;
   // safety: ensure hi>lo
   if(hi <= lo) return;
   color col = clrNONE;
   string label="";
   if(z.kind==1)
   {
      col = (z.type>0 ? InpBullOBColor : InpBearOBColor);
      label = (z.type>0 ? "BULL OB" : "BEAR OB");
   }
   else
   {
      col = (z.type>0 ? InpBullFVGColor : InpBearFVGColor);
      label = (z.type>0 ? "BULL FVG" : "BEAR FVG");
   }

   // Main rectangle - NOT back, so it's visible over candles
   if(!ObjectCreate(0, z.objName, OBJ_RECTANGLE, 0, start, hi, end, lo))
      return;
   ObjectSetInteger(0, z.objName, OBJPROP_COLOR, col);
   ObjectSetInteger(0, z.objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, z.objName, OBJPROP_WIDTH, InpZoneBorderWidth);
   ObjectSetInteger(0, z.objName, OBJPROP_BACK, false); // false = draw on top, visible!
   ObjectSetInteger(0, z.objName, OBJPROP_FILL, true);
   ObjectSetInteger(0, z.objName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, z.objName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, z.objName, OBJPROP_ZORDER, 0);

   // Mid line
   string lineName = z.objName+"_L";
   ObjectCreate(0, lineName, OBJ_TREND, 0, start, z.mid, end, z.mid);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, col);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lineName, OBJPROP_RAY, false);
   ObjectSetInteger(0, lineName, OBJPROP_BACK, false);
   ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);

   // Label at top of zone
   string txtName = z.objName+"_TXT";
   ObjectCreate(0, txtName, OBJ_TEXT, 0, start, hi);
   ObjectSetText(txtName, label, 7, "Arial Bold", col);
   ObjectSetInteger(0, txtName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
}

void DrawZones()
{
   for(int i=0;i<OB_Count;i++) if(OB_Zones[i].active && !OB_Zones[i].mitigated) DrawZone(OB_Zones[i]);
   for(int i=0;i<FVG_Count;i++) if(FVG_Zones[i].active && !FVG_Zones[i].mitigated) DrawZone(FVG_Zones[i]);
}

void UpdateDashboard(int bias, int obCount, int fvgCount)
{
   if(!InpShowDashboard) return;
   string biasStr = (bias>0 ? "BULLISH" : bias<0 ? "BEARISH" : "NEUTRAL");
   string tf = TFToString(Period());
   string txt = StringFormat("HIE v2.1 | %s %s | Bias:%s | OB:%d FVG:%d | Impulses:%d Sweeps:%d",
                             Symbol(), tf, biasStr, obCount, fvgCount, debugImpulseCount, debugSweepCount);
   Comment(txt);
   if(InpShowDebug && obCount==0 && fvgCount==0)
   {
      string hint = "\nNo zones yet? Try: Lower InpImpulseATRFact to 1.0 or set InpRequireBOSImpulse=false (now default). Chart: "+tf+" needs 600 bars history.";
      Comment(txt+hint);
   }
   string bName="HIE_DASH_BIAS";
   if(ObjectFind(0,bName)<0)
   {
      ObjectCreate(0,bName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0,bName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0,bName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0,bName, OBJPROP_YDISTANCE, 38);
   }
   color biasCol = (bias>0 ? clrLime : bias<0 ? clrRed : clrGold);
   ObjectSetText(bName, "Structure: "+biasStr+"  |  OB:"+IntegerToString(obCount)+" FVG:"+IntegerToString(fvgCount), 8, "Arial Bold", biasCol);
}

//+------------------------------------------------------------------+
string TFToString(int tf)
{
   switch(tf)
   {
      case PERIOD_M1: return "M1";
      case PERIOD_M5: return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1: return "H1";
      case PERIOD_H4: return "H4";
      case PERIOD_D1: return "D1";
      case PERIOD_W1: return "W1";
      case PERIOD_MN1: return "MN1";
      default: return IntegerToString(tf);
   }
}

//+------------------------------------------------------------------+
//| Main Calculation — OnCalculate                                    |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(Bars < 80) return(0);
   if(rates_total < 50) return(0);

   int limit = MathMin(Bars - 10, InpMaxBarsCalc);
   int start = 1;
   bool isNewBar = (Time[0] != lastBarTime);
   if(prev_calculated == 0)
   {
      ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
      ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);
      ArrayInitialize(BuyZoneBuffer, EMPTY_VALUE);
      ArrayInitialize(SellZoneBuffer, EMPTY_VALUE);
      OB_Count=0; FVG_Count=0;
      for(int i=ObjectsTotal()-1;i>=0;i--)
      {
         string n=ObjectName(i);
         if(StringFind(n,"HIE_OB_")==0 || StringFind(n,"HIE_FVG_")==0 || StringFind(n,"HIE_DBG")==0)
         {
            ObjectDelete(n);
            ObjectDelete(n+"_L");
            ObjectDelete(n+"_TXT");
         }
      }
      start = limit;
   }
   else
   {
      int barsChanged = rates_total - prev_calculated;
      if(barsChanged <= 1 && !isNewBar) return(rates_total);
      start = MathMin(limit, MathMax(1, barsChanged + 5));
   }

   UpdateSwings(limit);

   debugImpulseCount=0;
   debugSweepCount=0;
   // Count sweeps for dashboard
   for(int s=1; s< MathMin(30, limit); s++)
   {
      if(IsLiquiditySweepLow(s) || IsLiquiditySweepHigh(s)) debugSweepCount++;
   }

   // Scan for new zones
   for(int i=start; i>=1; i--)
   {
      bool bullImpulse = IsInstitutionalImpulse(i, 1);
      bool bearImpulse = IsInstitutionalImpulse(i, -1);
      if(bullImpulse || bearImpulse) debugImpulseCount++;

      if(bullImpulse && InpUseOrderBlock)
      {
         double obH, obL; int obIdx;
         if(FindBullishOrderBlockForImpulse(i, obH, obL, obIdx))
         {
            datetime t = Time[obIdx];
            bool sweepOK = !InpUseSweep || HasRecentSweepLow(i, InpSweepLookback);
            if(sweepOK) AddOBZone(1, obH, obL, obIdx, t);
         }
      }
      if(bearImpulse && InpUseOrderBlock)
      {
         double obH, obL; int obIdx;
         if(FindBearishOrderBlockForImpulse(i, obH, obL, obIdx))
         {
            datetime t = Time[obIdx];
            bool sweepOK = !InpUseSweep || HasRecentSweepHigh(i, InpSweepLookback);
            if(sweepOK) AddOBZone(-1, obH, obL, obIdx, t);
         }
      }

      if(InpUseFVG)
      {
         double fvgH, fvgL;
         if(IsBullishFVG(i, fvgH, fvgL))
         {
            bool hasImpulseNearby = false;
            for(int k=0;k<6;k++) if(IsInstitutionalImpulse(i+k,1)) { hasImpulseNearby=true; break; }
            if(hasImpulseNearby || (fvgH - fvgL) > GetATR(i,14)*0.10)
               AddFVGZone(1, fvgH, fvgL, i, Time[i+1]);
            else if(!InpRequireBOSImpulse) // loose mode: show all FVGs
               AddFVGZone(1, fvgH, fvgL, i, Time[i+1]);
         }
         if(IsBearishFVG(i, fvgH, fvgL))
         {
            bool hasImpulseNearby=false;
            for(int k=0;k<6;k++) if(IsInstitutionalImpulse(i+k,-1)) { hasImpulseNearby=true; break; }
            if(hasImpulseNearby || (fvgH - fvgL) > GetATR(i,14)*0.10)
               AddFVGZone(-1, fvgH, fvgL, i, Time[i+1]);
            else if(!InpRequireBOSImpulse)
               AddFVGZone(-1, fvgH, fvgL, i, Time[i+1]);
         }
      }
   }

   CheckMitigationAndExpiry(limit);

   // Entry signal evaluation
   for(int idx = MathMin(start, 10); idx>=1; idx--)
   {
      bool buySignal = false;
      bool sellSignal = false;

      for(int z=0; z<OB_Count && !buySignal; z++)
      {
         if(!OB_Zones[z].active || OB_Zones[z].mitigated) continue;
         if(OB_Zones[z].type != 1) continue;
         if(!IsPriceInBullishZone(idx, OB_Zones[z])) continue;
         if(IsBullishEntryTrigger(idx))
         {
            double c = barClose(idx);
            if(c < OB_Zones[z].low - 10*Point) continue;
            buySignal = true;
         }
      }
      if(!buySignal)
      {
         for(int z=0; z<FVG_Count && !buySignal; z++)
         {
            if(!FVG_Zones[z].active || FVG_Zones[z].mitigated) continue;
            if(FVG_Zones[z].type != 1) continue;
            if(!IsPriceInBullishZone(idx, FVG_Zones[z])) continue;
            if(IsBullishEntryTrigger(idx))
            {
               buySignal = true;
            }
         }
      }

      for(int z=0; z<OB_Count && !sellSignal; z++)
      {
         if(!OB_Zones[z].active || OB_Zones[z].mitigated) continue;
         if(OB_Zones[z].type != -1) continue;
         if(!IsPriceInBearishZone(idx, OB_Zones[z])) continue;
         if(IsBearishEntryTrigger(idx))
         {
            double c = barClose(idx);
            if(c > OB_Zones[z].high + 10*Point) continue;
            sellSignal = true;
         }
      }
      if(!sellSignal)
      {
         for(int z=0; z<FVG_Count && !sellSignal; z++)
         {
            if(!FVG_Zones[z].active || FVG_Zones[z].mitigated) continue;
            if(FVG_Zones[z].type != -1) continue;
            if(!IsPriceInBearishZone(idx, FVG_Zones[z])) continue;
            if(IsBearishEntryTrigger(idx))
            {
               sellSignal = true;
            }
         }
      }

      if(buySignal)
      {
         double atr = GetATR(idx, InpATRPeriod);
         double offset = atr * InpArrowOffsetATR / 100.0;
         if(offset < 10*Point) offset = 10*Point;
         BuySignalBuffer[idx] = barLow(idx) - offset;
         BuyZoneBuffer[idx] = barLow(idx);
         if(idx==1 && InpAlerts && Time[1] != lastAlertBuy)
         {
            string msg = StringFormat("HIE BUY  %s %s @ %s  | %s",
                                      Symbol(), TFToString(Period()), DoubleToString(barClose(idx), Digits),
                                      (IsBullishEngulfing(idx)?"Engulfing": IsBullishPinBar(idx)?"PinBar":"InsideBreak"));
            Alert(msg);
            if(!IsTesting())
            {
               SendNotification(msg);
            }
            lastAlertBuy = Time[1];
         }
      }
      else
      {
         if(prev_calculated==0) BuySignalBuffer[idx]=EMPTY_VALUE;
         else if(idx==1) BuySignalBuffer[idx]=EMPTY_VALUE;
      }

      if(sellSignal)
      {
         double atr = GetATR(idx, InpATRPeriod);
         double offset = atr * InpArrowOffsetATR / 100.0;
         if(offset < 10*Point) offset = 10*Point;
         SellSignalBuffer[idx] = barHigh(idx) + offset;
         SellZoneBuffer[idx] = barHigh(idx);
         if(idx==1 && InpAlerts && Time[1] != lastAlertSell)
         {
            string msg = StringFormat("HIE SELL %s %s @ %s | %s",
                                      Symbol(), TFToString(Period()), DoubleToString(barClose(idx), Digits),
                                      (IsBearishEngulfing(idx)?"Engulfing": IsBearishPinBar(idx)?"PinBar":"InsideBreak"));
            Alert(msg);
            if(!IsTesting()) SendNotification(msg);
            lastAlertSell = Time[1];
         }
      }
      else
      {
         if(prev_calculated==0) SellSignalBuffer[idx]=EMPTY_VALUE;
         else if(idx==1) SellSignalBuffer[idx]=EMPTY_VALUE;
      }
   }

   DrawZones();
   UpdateDashboard(CurrentStructureBias(), OB_Count, FVG_Count);

   lastBarTime = Time[0];
   return(rates_total);
}
//+------------------------------------------------------------------+
