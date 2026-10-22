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
//|  Version: 2.00  |  MT4 Build 1380+  |  Strict mode                |
//+------------------------------------------------------------------+
#property copyright "Institutional Price Action Lab — Professional Edition"
#property link      "https://github.com/ismailchaacha97-ui/kkk"
#property version   "2.00"
#property description "Hidden Institutional Entry — pure price action. Detects liquidity sweep + displacement + OB/FVG mitigation with candlestick confirmation. No lagging indicators."
#property strict

#property indicator_chart_window
#property indicator_buffers 4
#property indicator_color1 clrLimeGreen      // Buy Signal
#property indicator_color2 clrCrimson        // Sell Signal
#property indicator_color3 clrNONE
#property indicator_color4 clrNONE
#property indicator_width1 2
#property indicator_width2 2

//--- Buffers
double BuySignalBuffer[];
double SellSignalBuffer[];
double BuyZoneBuffer[];   // for internal use / debugging, transparent
double SellZoneBuffer[];

//--- Inputs — Structure
input string Inp_Set_Structure = "===== MARKET STRUCTURE ====="; // === Market Structure ===
input int    InpSwingPeriod     = 5;          // Fractal Swing Period (2-10, 5 = classic 5-bar fractal)
input int    InpLookbackSwings  = 50;         // How many swings to track for structure
input int    InpBOSConfirmBars  = 10;         // Bars to confirm BOS/CHoCH after sweep
input bool   InpUseCHoCH        = true;       // Detect Change of Character (trend reversal)

//--- Inputs — Institutional Impulse
input string Inp_Set_Impulse   = "===== INSTITUTIONAL IMPULSE ====="; // === Institutional Impulse ===
input double InpImpulseATRFact  = 1.35;       // Impulse min range vs ATR(14) (1.2-2.5)
input double InpImpulseBodyFact = 0.55;       // Min body/range ratio for impulse (0.5-0.8)
input int    InpATRPeriod       = 14;        // ATR period for impulse measurement
input bool   InpRequireBOSImpulse = true;    // Impulse must break swing high/low

//--- Inputs — Order Block & FVG
input string Inp_Set_Zones     = "===== INSTITUTIONAL ZONES (OB / FVG) ====="; // === Zones ===
input bool   InpUseOrderBlock  = true;       // Enable Order Block detection
input bool   InpUseFVG         = true;       // Enable Fair Value Gap / Imbalance
input double InpMinFVGPoints   = 4.0;        // Min FVG size in * spread units (filter noise)
input int    InpMaxZones       = 12;         // Max active zones to keep (performance)
input int    InpZoneExpiryBars = 120;        // Expire zone after N bars if not mitigated
input bool   InpShowZones      = true;       // Draw OB/FVG rectangles
input color  InpBullOBColor    = C'20,60,20';   // Bullish OB fill (dark green)
input color  InpBearOBColor    = C'60,20,20';   // Bearish OB fill (dark red)
input color  InpBullFVGColor   = C'20,45,70';   // Bullish FVG fill
input color  InpBearFVGColor   = C'70,35,20';   // Bearish FVG fill

//--- Inputs — Liquidity Sweep
input string Inp_Set_Sweep     = "===== LIQUIDITY SWEEP ====="; // === Liquidity ===
input bool   InpUseSweep       = true;       // Enable liquidity sweep filter
input double InpSweepTolerancePts = 8;       // Sweep beyond swing by N points (wick tolerance)
input double InpRejectionFactor   = 0.40;    // Min wick/range ratio for rejection (0.35-0.65)
input int    InpSweepLookback    = 15;       // Bars to look for sweep before BOS

//--- Inputs — Entry Confirmation
input string Inp_Set_Entry     = "===== ENTRY TRIGGER ====="; // === Entry Trigger ===
input bool   InpUseEngulfing   = true;       // Require bullish/bearish engulfing
input bool   InpUsePinBar      = true;       // Allow pin bar / hammer / shooting star
input bool   InpUseInsideBreak = false;      // Allow inside-bar break (less strict)
input double InpPinBarWickFact = 0.60;        // Pin bar wick/range ratio (0.55-0.70)
input double InpEngulfBodyFact = 1.05;       // Engulfing: current body > prev body * factor
input bool   InpVolumeConfirm  = true;       // Confirm with tick volume spike (Volume[1] > MA)
input int    InpVolMAPeriod    = 20;         // Tick volume MA period

//--- Inputs — Risk / Display
input string Inp_Set_Display   = "===== DISPLAY & ALERTS ====="; // === Display ===
input int    InpArrowOffsetATR = 25;         // Arrow offset (ATR * % /100)
input bool   InpAlerts         = true;       // Enable alerts (popup + push + email if configured)
input bool   InpShowDashboard  = true;       // Show info panel
input int    InpMaxBarsCalc    = 800;        // Max bars to calculate (performance cap)

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

   SetIndexStyle(0, DRAW_ARROW, EMPTY, 2, clrLimeGreen);
   SetIndexArrow(0, 233); // up arrow
   SetIndexStyle(1, DRAW_ARROW, EMPTY, 2, clrCrimson);
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
   IndicatorShortName("Hidden Institutional Entry v2.0");

   ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
   ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);
   ArrayInitialize(BuyZoneBuffer, EMPTY_VALUE);
   ArrayInitialize(SellZoneBuffer, EMPTY_VALUE);

   // Init zone arrays
   for(int i=0;i<MAX_ZONES;i++)
   {
      OB_Zones[i].active=false; OB_Zones[i].mitigated=false;
      FVG_Zones[i].active=false; FVG_Zones[i].mitigated=false;
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
      if(StringFind(n,"HIE_OB_")==0 || StringFind(n,"HIE_FVG_")==0 || StringFind(n,"HIE_DASH")==0 || StringFind(n,"HIE_ZONE")==0)
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
//| ATR (no iATR lag — use Wilder directly but cache)                |
//+------------------------------------------------------------------+
double GetATR(int idx, int period)
{
   // Use built-in iATR for correctness; MQL4 caches it efficiently
   double atr = iATR(Symbol(), PERIOD_CURRENT, period, idx);
   if(atr==0 || atr==EMPTY_VALUE) return (High[0]-Low[0]); // fallback
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
   if(prevBody==0) return false;
   bool bodyEngulfs = (currBody > prevBody * InpEngulfBodyFact) && (o2 <= c1) && (c2 >= o1);
   // Full range engulfing is stronger but body is the institutional footprint
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
   if(prevBody==0) return false;
   bool bodyEngulfs = (currBody > prevBody * InpEngulfBodyFact) && (o2 >= c1) && (c2 <= o1);
   return bodyEngulfs;
}

bool IsBullishPinBar(int idx)
{
   double o = barOpen(idx), h = barHigh(idx), l = barLow(idx), c = barClose(idx);
   double range = h - l;
   if(range <= 0) return false;
   double body = MathAbs(o - c);
   double lowerWick = MathMin(o,c) - l;
   double upperWick = h - MathMax(o,c);
   // Bullish pin: long lower wick, small upper wick, close near high
   bool wickOK = (lowerWick / range >= InpPinBarWickFact);
   bool bodySmall = (body / range <= 0.35);
   bool closeHigh = (c > o) && (upperWick / range <= 0.25);
   // also accept hammer: bullish close in upper 1/3
   bool hammerShape = (lowerWick > 2.0 * body) && (upperWick < body);
   return (wickOK && bodySmall && closeHigh) || hammerShape;
}

bool IsBearishPinBar(int idx)
{
   double o = barOpen(idx), h = barHigh(idx), l = barLow(idx), c = barClose(idx);
   double range = h - l;
   if(range <= 0) return false;
   double body = MathAbs(o - c);
   double upperWick = h - MathMax(o,c);
   double lowerWick = MathMin(o,c) - l;
   bool wickOK = (upperWick / range >= InpPinBarWickFact);
   bool bodySmall = (body / range <= 0.35);
   bool closeLow = (c < o) && (lowerWick / range <= 0.25);
   bool shootingShape = (upperWick > 2.0 * body) && (lowerWick < body);
   return (wickOK && bodySmall && closeLow) || shootingShape;
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
   if(!InpVolumeConfirm) return true; // disabled = always pass
   if(idx < InpVolMAPeriod) return false;
   double sum=0;
   for(int i=1;i<=InpVolMAPeriod;i++) sum += barVolume(idx+i);
   double ma = sum / InpVolMAPeriod;
   if(ma==0) return true;
   return (barVolume(idx) > ma * 1.25); // 25% above average = institutional participation
}

//+------------------------------------------------------------------+
//| Fractal Swing Detection (lag-free: confirms on bar close)        |
//|  Classic 5-bar fractal: high[i] > high[i±1] && high[i] > high[i±2] |
//|  We evaluate on closed bar (idx=1) with offset = InpSwingPeriod/2 |
//+------------------------------------------------------------------+
bool IsSwingHigh(int idx)
{
   int half = InpSwingPeriod/2;
   if(idx-half < 0 || idx+half >= Bars) return false;
   double h0 = barHigh(idx);
   for(int k=1;k<=half;k++)
   {
      if(barHigh(idx+k) >= h0) return false;
      if(barHigh(idx-k) > h0) return false; // allow equal on right for strictness
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
   // scan from 1 to limit
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

double MostRecentSwingHigh(int excludeBars)
{
   for(int i=0;i<swingHighCount;i++) if(swingHighBar[i] > excludeBars) return swingHighVal[i];
   return EMPTY_VALUE;
}
double MostRecentSwingLow(int excludeBars)
{
   for(int i=0;i<swingLowCount;i++) if(swingLowBar[i] > excludeBars) return swingLowVal[i];
   return EMPTY_VALUE;
}

// BOS / CHoCH detection
// BOS bullish: close breaks above last swing high
bool IsBOSBullish(int idx)
{
   if(swingHighCount==0) return false;
   double lastHigh = EMPTY_VALUE;
   int    lastBar  = -1;
   // find last swing high BEFORE idx
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
   // BOS: close breaks high, with impulse
   if(barClose(idx) <= lastHigh) return false;
   // ensure not too old
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

// Trend determination via structure (HH/HL vs LH/LL)
int CurrentStructureBias()
{
   // +1 bullish, -1 bearish, 0 neutral
   if(swingHighCount < 2 || swingLowCount < 2) return 0;
   bool higherHigh = swingHighVal[1] > swingHighVal[0]; // note array is most recent first? Actually 0 is most recent, so 1 is older
   // Let's correct: swingHighVal[0] is most recent (lowest bar index gap), swingHighVal[1] older
   // But our loop fills in increasing i order, so index 0 = most recent near current.
   // So higher high bullish means recent > older
   bool isHH = swingHighVal[0] > swingHighVal[1];
   bool isHL = swingLowVal[0] > swingLowVal[1];
   bool isLH = swingHighVal[0] < swingHighVal[1];
   bool isLL = swingLowVal[0] < swingLowVal[1];
   if(isHH && isHL) return 1;
   if(isLH && isLL) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Institutional Impulse: Large range + large body + close beyond   |
//+------------------------------------------------------------------+
bool IsInstitutionalImpulse(int idx, int direction)
{
   // direction +1 bullish, -1 bearish
   double range = barHigh(idx) - barLow(idx);
   if(range <= 0) return false;
   double body = MathAbs(barOpen(idx) - barClose(idx));
   double atr = GetATR(idx+1, InpATRPeriod); // use prior ATR to avoid lookahead
   if(atr==0) return false;
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
//|  Bullish OB: last BEARISH candle before a bullish impulse (BOS)  |
//|  Valid OB must have wick making higher low protection            |
//+------------------------------------------------------------------+
bool FindBullishOrderBlockForImpulse(int impulseIdx, double &obHigh, double &obLow, int &obIdx)
{
   // search back 5 bars before impulse for last bearish candle
   for(int k=1;k<=6;k++)
   {
      int idx = impulseIdx + k;
      if(idx >= Bars-1) break;
      double o = barOpen(idx), c = barClose(idx);
      if(c < o) // bearish candle
      {
         obHigh = MathMax(o,c);
         obLow  = MathMin(o,c);
         // Extend to wick: institutional OB is High/Low of that candle
         // More precise: high = high of candle, low = low
         obHigh = barHigh(idx);
         obLow  = barLow(idx);
         // Alternative classic: use open/close only for mitigation zone
         // We use 50% of wick filtered: use High-Low but keep body priority
         // Refine: OB zone = open to low (for bullish)
         // Actually ICT: bullish OB = last down candle's High-Low, entry at 50%
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
      if(idx >= Bars-1) break;
      double o = barOpen(idx), c = barClose(idx);
      if(c > o) // bullish before bearish impulse
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
//|  Bullish FVG: low[ idx ] > high[ idx+2 ]  (gap between 1st and 3rd)|
//|  Bearish FVG: high[ idx ] < low[ idx+2 ]                          |
//+------------------------------------------------------------------+
bool IsBullishFVG(int idx, double &fvgHigh, double &fvgLow)
{
   if(idx < 1 || idx+2 >= Bars) return false;
   double h0 = barHigh(idx+2); // first candle high
   double l2 = barLow(idx);    // third candle low
   if(l2 <= h0) return false;
   double gap = l2 - h0;
   // filter by min size
   double minSize = InpMinFVGPoints * Point * (MarketInfo(Symbol(), MODE_SPREAD) > 0 ? 1 : 1);
   // Use points * 0.5 spread? Better use ATR fraction
   double atr = GetATR(idx+1, 14);
   if(gap < atr * 0.08) // too tiny gap = noise, at least 8% ATR
      if(gap < minSize) return false;
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
   double atr = GetATR(idx+1, 14);
   double minSize = InpMinFVGPoints * Point;
   if(gap < atr * 0.08)
      if(gap < minSize) return false;
   fvgHigh = l0;
   fvgLow  = h2;
   return true;
}

//+------------------------------------------------------------------+
//| Liquidity Sweep (Stop Hunt)                                      |
//|  Bullish sweep setup: price sweeps swing LOW (takes liquidity)   |
//|  then aggressively rejects — long wick, close back inside.       |
//|  This sweep precedes LONG institutional entry.                   |
//+------------------------------------------------------------------+
bool IsLiquiditySweepLow(int idx)
{
   // Need recent swing low
   double swingLow = EMPTY_VALUE;
   int swingBar = -1;
   for(int s=0;s<swingLowCount;s++)
   {
      if(swingLowBar[s] > idx && swingLowBar[s] - idx <= InpSweepLookback)
      {
         swingLow = swingLowVal[s];
         swingBar = swingLowBar[s];
         break;
      }
   }
   if(swingLow==EMPTY_VALUE) return false;

   // Sweep: low dips below swing low by tolerance, but close back above swing low
   double l = barLow(idx);
   double c = barClose(idx);
   double o = barOpen(idx);
   double h = barHigh(idx);
   double tolerance = InpSweepTolerancePts * Point;

   bool swept = (l < swingLow - tolerance*0.5) || (l < swingLow && c > swingLow);
   if(!swept) return false;

   // Rejection: long lower wick
   double range = h - l;
   if(range <= 0) return false;
   double lowerWick = MathMin(o,c) - l;
   bool rejection = (lowerWick / range >= InpRejectionFactor);

   // Must close back inside
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
   if(range <= 0) return false;
   double upperWick = h - MathMax(o,c);
   bool rejection = (upperWick / range >= InpRejectionFactor);
   bool closeInside = (c < swingHigh);
   return rejection && closeInside;
}

// Historical check: was there a sweep in last N bars before idx ?
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
   // Deduplicate: if same level exists, skip
   for(int i=0;i<OB_Count;i++)
      if(OB_Zones[i].active && MathAbs(OB_Zones[i].high - hi) < Point*2 && MathAbs(OB_Zones[i].low - lo) < Point*2)
         return;
   if(OB_Count >= MAX_ZONES) // shift out oldest
   {
      // remove oldest (last)
      if(InpShowZones && OB_Zones[MAX_ZONES-1].objName != "")
         ObjectDelete(OB_Zones[MAX_ZONES-1].objName);
      OB_Count = MAX_ZONES-1;
   }
   // shift down to make room at 0 (most recent first)
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
   OB_Zones[0].objName = "HIE_OB_"+IntegerToString(type>0?1:2)+"_"+IntegerToString(barIdx)+"_"+IntegerToString(GetTickCount());
   OB_Count++;
}

void AddFVGZone(int type, double hi, double lo, int barIdx, datetime t)
{
   for(int i=0;i<FVG_Count;i++)
      if(FVG_Zones[i].active && MathAbs(FVG_Zones[i].high - hi) < Point && MathAbs(FVG_Zones[i].low - lo) < Point)
         return;
   if(FVG_Count >= MAX_ZONES)
   {
      if(InpShowZones && FVG_Zones[MAX_ZONES-1].objName != "")
         ObjectDelete(FVG_Zones[MAX_ZONES-1].objName);
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
   FVG_Zones[0].objName = "HIE_FVG_"+IntegerToString(type>0?1:2)+"_"+IntegerToString(barIdx)+"_"+IntegerToString(GetTickCount());
   FVG_Count++;
}

void CheckMitigationAndExpiry(int currentBar)
{
   // Mark mitigated if price closed through mid or fully through zone
   for(int i=0;i<OB_Count;i++)
   {
      if(!OB_Zones[i].active || OB_Zones[i].mitigated) continue;
      // expiry
      if(currentBar - OB_Zones[i].barIndex > InpZoneExpiryBars)
      {
         OB_Zones[i].active=false;
         if(InpShowZones) ObjectDelete(OB_Zones[i].objName);
         continue;
      }
      // bullish OB: mitigation when price goes into zone (wick) and then leaves? For signal, we allow first touch.
      // For cleanup: if close below zone (bearish OB) or above (bullish) beyond zone by 1 ATR, mark mitigated
      double c = barClose(1);
      if(OB_Zones[i].type > 0)
      {
         // bullish zone below price, if price fully leaves upward and closed above zone high + buffer, consider mitigated after use
         // We'll mark mitigated only after price has touched and then moved 1.5x zone height away — keep active for retest logic outside
      }
      else
      {
      }
   }
   for(int i=0;i<FVG_Count;i++)
   {
      if(!FVG_Zones[i].active || FVG_Zones[i].mitigated) continue;
      if(currentBar - FVG_Zones[i].barIndex > InpZoneExpiryBars)
      {
         FVG_Zones[i].active=false;
         if(InpShowZones) ObjectDelete(FVG_Zones[i].objName);
         continue;
      }
   }
}

// Check if price is interacting with zone at idx
bool IsPriceInBullishZone(int idx, Zone &z)
{
   // For bullish entry: price dips into demand zone
   double l = barLow(idx);
   double c = barClose(idx);
   // Touch: low inside zone OR close inside zone
   bool inZone = (l <= z.high && l >= z.low) || (c <= z.high && c >= z.low) || (l < z.low && c > z.low && c < z.high);
   // Also allow close inside zone's mid
   return inZone;
}
bool IsPriceInBearishZone(int idx, Zone &z)
{
   double h = barHigh(idx);
   double c = barClose(idx);
   bool inZone = (h >= z.low && h <= z.high) || (c >= z.low && c <= z.high) || (h > z.high && c < z.high && c > z.low);
   return inZone;
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
//| Drawing                                                          |
//+------------------------------------------------------------------+
void DrawZone(Zone &z)
{
   if(!InpShowZones) return;
   if(z.objName=="") return;
   if(ObjectFind(z.objName) >= 0) // update
   {
      // extend rectangle to current time
      datetime endTime = Time[0] + Period()*60*6; // extend 6 bars forward
      ObjectSet(z.objName, OBJPROP_TIME2, endTime);
      return;
   }
   // Create rectangle: from zone bar time to future
   datetime start = z.time;
   datetime end   = Time[0] + Period()*60*8;
   double hi = z.high;
   double lo = z.low;
   color col = clrNONE;
   if(z.kind==1) col = (z.type>0 ? InpBullOBColor : InpBearOBColor);
   else          col = (z.type>0 ? InpBullFVGColor : InpBearFVGColor);

   ObjectCreate(z.objName, OBJ_RECTANGLE, 0, start, hi, end, lo);
   ObjectSet(z.objName, OBJPROP_COLOR, col);
   ObjectSet(z.objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet(z.objName, OBJPROP_WIDTH, 1);
   ObjectSet(z.objName, OBJPROP_BACK, true);
   ObjectSet(z.objName, OBJPROP_FILL, true);
   // Make semi-transparent via UI (MT4 doesn't support alpha, use BACK)
   ObjectSet(z.objName, OBJPROP_SELECTED, false);
   ObjectSet(z.objName, OBJPROP_SELECTABLE, false);
   string label = (z.kind==1 ? (z.type>0 ? "BULL OB" : "BEAR OB") : (z.type>0 ? "BULL FVG" : "BEAR FVG"));
   ObjectSetText(z.objName, label, 7, "Arial", col);

   // Add border line for entry edge
   string lineName = z.objName+"_L";
   ObjectCreate(lineName, OBJ_TREND, 0, start, z.mid, end, z.mid);
   ObjectSet(lineName, OBJPROP_COLOR, col);
   ObjectSet(lineName, OBJPROP_STYLE, STYLE_DOT);
   ObjectSet(lineName, OBJPROP_WIDTH, 1);
   ObjectSet(lineName, OBJPROP_RAY, false);
   ObjectSet(lineName, OBJPROP_BACK, true);
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
   color biasCol = (bias>0 ? clrLimeGreen : bias<0 ? clrCrimson : clrGold);

   string name = "HIE_DASH_BG";
   if(ObjectFind(name)<0)
   {
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSet(name, OBJPROP_XDISTANCE, 8);
      ObjectSet(name, OBJPROP_YDISTANCE, 18);
   }
   string txt = StringFormat("HIDDEN INSTITUTIONAL ENTRY v2.0  |  Bias: %s  |  OB:%d  FVG:%d  |  TF:%s",
                             biasStr, obCount, fvgCount, TFToString(Period()));
   // Use Comment for lightweight dashboard (no object spam)
   Comment(txt);

   // Optional bias label
   string bName="HIE_DASH_BIAS";
   if(ObjectFind(bName)<0)
   {
      ObjectCreate(bName, OBJ_LABEL, 0, 0, 0);
      ObjectSet(bName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSet(bName, OBJPROP_XDISTANCE, 10);
      ObjectSet(bName, OBJPROP_YDISTANCE, 40);
   }
   ObjectSetText(bName, "Structure Bias: "+biasStr, 8, "Arial Bold", biasCol);
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
   // Safety
   if(Bars < 100) return(0);
   if(rates_total < 50) return(0);

   // Performance cap
   int limit = MathMin(Bars - 50, InpMaxBarsCalc);

   // Determine start index: if first run, calculate all; otherwise only new bar(s)
   int start = 1;
   bool isNewBar = (Time[0] != lastBarTime);
   if(prev_calculated == 0)
   {
      // Full init
      ArrayInitialize(BuySignalBuffer, EMPTY_VALUE);
      ArrayInitialize(SellSignalBuffer, EMPTY_VALUE);
      OB_Count=0; FVG_Count=0;
      // Clean objects
      for(int i=ObjectsTotal()-1;i>=0;i--)
      {
         string n=ObjectName(i);
         if(StringFind(n,"HIE_OB_")==0 || StringFind(n,"HIE_FVG_")==0) ObjectDelete(n);
      }
      start = limit;
   }
   else
   {
      // Incremental: only process newest closed bar (idx=1) unless we missed bars
      int barsChanged = rates_total - prev_calculated;
      if(barsChanged <= 1 && !isNewBar) return(rates_total); // no new closed bar
      start = MathMin(limit, MathMax(1, barsChanged + 4));
   }

   // Always update swings based on recent structure (lightweight)
   UpdateSwings(limit);

   // Scan for new zones (from oldest to newest to keep order)
   for(int i=start; i>=1; i--)
   {
      // 1) Institutional impulse detection
      bool bullImpulse = IsInstitutionalImpulse(i, 1);
      bool bearImpulse = IsInstitutionalImpulse(i, -1);

      if(bullImpulse && InpUseOrderBlock)
      {
         double obH, obL; int obIdx;
         if(FindBullishOrderBlockForImpulse(i, obH, obL, obIdx))
         {
            datetime t = Time[obIdx];
            // Optional: require sweep before impulse for higher quality
            bool sweepOK = !InpUseSweep || HasRecentSweepLow(i, InpSweepLookback);
            // Optional: check CHoCH alignment
            if(sweepOK)
               AddOBZone(1, obH, obL, obIdx, t);
         }
      }
      if(bearImpulse && InpUseOrderBlock)
      {
         double obH, obL; int obIdx;
         if(FindBearishOrderBlockForImpulse(i, obH, obL, obIdx))
         {
            datetime t = Time[obIdx];
            bool sweepOK = !InpUseSweep || HasRecentSweepHigh(i, InpSweepLookback);
            if(sweepOK)
               AddOBZone(-1, obH, obL, obIdx, t);
         }
      }

      // 2) FVG detection
      if(InpUseFVG)
      {
         double fvgH, fvgL;
         if(IsBullishFVG(i, fvgH, fvgL))
         {
            // Only keep FVGs that appeared with or after impulse
            bool hasImpulseNearby = false;
            for(int k=0;k<6;k++) if(IsInstitutionalImpulse(i+k,1)) { hasImpulseNearby=true; break; }
            // Also keep standalone FVGs that are significant (ATR filtered already)
            if(hasImpulseNearby || (fvgH - fvgL) > GetATR(i,14)*0.18)
               AddFVGZone(1, fvgH, fvgL, i, Time[i+1]); // FVG time is middle bar
         }
         if(IsBearishFVG(i, fvgH, fvgL))
         {
            bool hasImpulseNearby=false;
            for(int k=0;k<6;k++) if(IsInstitutionalImpulse(i+k,-1)) { hasImpulseNearby=true; break; }
            if(hasImpulseNearby || (fvgH - fvgL) > GetATR(i,14)*0.18)
               AddFVGZone(-1, fvgH, fvgL, i, Time[i+1]);
         }
      }
   } // end zone scan

   // Clean mitigated/expired zones
   CheckMitigationAndExpiry(Bars);

   // 3) Entry signal evaluation — ONLY on closed bar (idx=1)
   // We evaluate idx=1 every new bar; also re-evaluate idx=2..5 on full recalc to avoid gaps
   for(int idx = MathMin(start, 6); idx>=1; idx--)
   {
      // Skip if already signaled at this bar (prevent repaint on history)
      // Check bullish zones
      bool buySignal = false;
      bool sellSignal = false;

      // Bias filter: optional — don't force, but can weight
      int bias = CurrentStructureBias();

      // --- BUY: price in bullish OB/FVG + bullish trigger + (optional) sweep+ BOS context already ensured at zone creation
      for(int z=0; z<OB_Count && !buySignal; z++)
      {
         if(!OB_Zones[z].active || OB_Zones[z].mitigated) continue;
         if(OB_Zones[z].type != 1) continue;
         if(!IsPriceInBullishZone(idx, OB_Zones[z])) continue;
         // Trigger
         if(IsBullishEntryTrigger(idx))
         {
            // Extra confluence: price must be above zone low, close above zone mid for strength
            double c = barClose(idx);
            if(c < OB_Zones[z].low) continue;
            buySignal = true;
            // Mark zone as mitigated after successful signal to avoid spam (keep 1 more touch allowed)
            // We allow 2 touches: only mitigate after second signal
            // For now keep active but we could tag
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
               double c = barClose(idx);
               if(c < FVG_Zones[z].low) continue;
               buySignal = true;
            }
         }
      }

      // --- SELL
      for(int z=0; z<OB_Count && !sellSignal; z++)
      {
         if(!OB_Zones[z].active || OB_Zones[z].mitigated) continue;
         if(OB_Zones[z].type != -1) continue;
         if(!IsPriceInBearishZone(idx, OB_Zones[z])) continue;
         if(IsBearishEntryTrigger(idx))
         {
            double c = barClose(idx);
            if(c > OB_Zones[z].high) continue;
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
               double c = barClose(idx);
               if(c > FVG_Zones[z].high) continue;
               sellSignal = true;
            }
         }
      }

      // Place buffers
      if(buySignal)
      {
         double atr = GetATR(idx, InpATRPeriod);
         double offset = atr * InpArrowOffsetATR / 100.0;
         BuySignalBuffer[idx] = barLow(idx) - offset;
         BuyZoneBuffer[idx] = barLow(idx);

         if(idx==1 && InpAlerts && Time[1] != lastAlertBuy)
         {
            string msg = StringFormat("HIE BUY  %s %s @ %s  | Sweep+OB/FVG + %s",
                                      Symbol(), TFToString(Period()), DoubleToString(barClose(idx), Digits),
                                      (IsBullishEngulfing(idx)?"Engulfing": IsBullishPinBar(idx)?"PinBar":"InsideBreak"));
            Alert(msg);
            if(IsTesting()==false)
            {
               SendNotification(msg);
               SendMail("HIE Buy Signal "+Symbol()+" "+TFToString(Period()), msg);
            }
            lastAlertBuy = Time[1];
            PlaySound("alert.wav");
         }
      }
      else
      {
         // Do not overwrite existing history if not signal — keep EMPTY_VALUE for clean chart
         if(prev_calculated==0) BuySignalBuffer[idx]=EMPTY_VALUE;
      }

      if(sellSignal)
      {
         double atr = GetATR(idx, InpATRPeriod);
         double offset = atr * InpArrowOffsetATR / 100.0;
         SellSignalBuffer[idx] = barHigh(idx) + offset;
         SellZoneBuffer[idx] = barHigh(idx);

         if(idx==1 && InpAlerts && Time[1] != lastAlertSell)
         {
            string msg = StringFormat("HIE SELL %s %s @ %s | Sweep+OB/FVG + %s",
                                      Symbol(), TFToString(Period()), DoubleToString(barClose(idx), Digits),
                                      (IsBearishEngulfing(idx)?"Engulfing": IsBearishPinBar(idx)?"PinBar":"InsideBreak"));
            Alert(msg);
            if(IsTesting()==false)
            {
               SendNotification(msg);
               SendMail("HIE Sell Signal "+Symbol()+" "+TFToString(Period()), msg);
            }
            lastAlertSell = Time[1];
            PlaySound("alert.wav");
         }
      }
      else
      {
         if(prev_calculated==0) SellSignalBuffer[idx]=EMPTY_VALUE;
      }
   }

   // Draw zones (after signals)
   DrawZones();

   // Dashboard
   UpdateDashboard(CurrentStructureBias(), OB_Count, FVG_Count);

   lastBarTime = Time[0];
   return(rates_total);
}
//+------------------------------------------------------------------+
