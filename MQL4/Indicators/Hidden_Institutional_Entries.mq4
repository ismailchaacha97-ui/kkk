//+------------------------------------------------------------------+
//|                          Hidden_Institutional_Entries.mq4        |
//|              H.I.E.P. - Hidden Institutional Entry Protocol      |
//|                                                                  |
//|  A pure price-action engine. No moving averages, no oscillators, |
//|  no repainting. Every decision is derived from raw OHLC + tick   |
//|  volume and is finalised on the CLOSE of a bar.                  |
//|                                                                  |
//|  Concepts implemented (institutional / smart-money model):       |
//|   1. Market structure  ......... HH/HL/LH/LL, BOS, CHoCH         |
//|   2. Liquidity pools   ......... unswept swing highs/lows        |
//|   3. Liquidity sweeps  ......... stop-hunt + reclaim (turtle soup)|
//|   4. Order blocks      ......... last opposing candle before an   |
//|                                  impulsive displacement leg      |
//|   5. Imbalance / FVG   ......... 3-candle fair value gaps         |
//|   6. Premium/Discount  ......... dealing-range equilibrium filter |
//|   7. HTF context       ......... higher-timeframe bias (no look-  |
//|                                  ahead: only closed HTF bars)    |
//|   8. Volume expansion  ......... tick-volume vs. its own average  |
//|                                                                  |
//|  Two signals are produced, both on CLOSED bars only:             |
//|   (A) SWEEP + RECLAIM - a liquidity grab that closes back inside  |
//|       the range, inside a live institutional zone, with structure |
//|       agreement and a confluence score above the user threshold.  |
//|   (B) CHoCH + RETEST - after a change of character, the first     |
//|       return into the order block / FVG that produced the         |
//|       displacement, confirmed by a rejection candle.              |
//|                                                                  |
//|  HONEST DISCLOSURE - READ THIS:                                  |
//|  This is a decision-support tool, not a profit guarantee. No      |
//|  indicator can be "error free and always profitable"; markets are |
//|  probabilistic. What this code DOES guarantee technically:       |
//|   - historical signals never move, vanish or repaint (all exits   |
//|     are evaluated on closed bars only),                          |
//|   - zero look-ahead in the higher-timeframe filter,               |
//|   - deterministic recalculation (same history -> same output),    |
//|   - no lagging averages (no smoothing of any kind).               |
//|  Validate on demo for 2-4 weeks and in the Strategy Tester before |
//|  risking capital. Past performance is not indicative.            |
//+------------------------------------------------------------------+
#property copyright "H.I.E.P. - Hidden Institutional Entry Protocol"
#property link      ""
#property version   "1.10"
#property description "Pure price-action institutional entries: liquidity sweeps + order blocks + FVG + market structure. Non-repainting."
#property strict

#property indicator_chart_window
#property indicator_buffers 2

#property indicator_color1 clrLime
#property indicator_color2 clrRed
#property indicator_width1 2
#property indicator_width2 2

#define PREFIX    "HIEP_"
#define DIR_BULL   1
#define DIR_BEAR  -1

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input string   __sep1            = "=========="; // === 1. ENGINE ===
input int      InpHistoryBars    = 1500;   // Bars analysed by the engine
input int      InpSwingStrength  = 4;      // Swing/fractal strength (bars each side)
input int      InpATRPeriod      = 14;     // ATR period (true range, pure PA)
input int      InpMaxZones       = 80;     // Max live institutional zones

input string   __sep2            = "=========="; // === 2. LIQUIDITY SWEEPS ===
input bool     InpUseSweeps      = true;   // Require a liquidity sweep (stop hunt)
input double   InpSweepPenATR    = 0.05;   // Min penetration beyond the level (x ATR)
input double   InpSweepClosePos  = 0.55;   // Reclaim close position in bar range (0..1)
input int      InpMinLevelAge    = 5;      // Level must be older than N bars
input int      InpSweepRecency   = 3;      // Signal must follow the sweep within N bars

input string   __sep3            = "=========="; // === 3. ORDER BLOCKS ===
input bool     InpUseOB          = true;   // Track order blocks
input bool     InpRefinedOB      = true;   // Refine OB zone to the candle body
input double   InpDisplacement   = 0.80;   // Min impulse leg (x ATR) to validate an OB
input int      InpOBLookback     = 12;     // Bars to search for the origin candle

input string   __sep4            = "=========="; // === 4. IMBALANCE / FVG ===
input bool     InpUseFVG         = true;   // Track fair value gaps
input double   InpMinFVGATR      = 0.12;   // Min gap size (x ATR)

input string   __sep5            = "=========="; // === 5. STRUCTURE & FILTERS ===
input bool     InpRequireStruct  = true;   // Require structure agreement for a signal
input int      InpStructRecency  = 12;     // CHoCH counts as valid for N bars
input bool     InpUseSession     = true;   // Killzone session filter
input int      InpLondonStart    = 8;      // London killzone start (server hour)
input int      InpLondonEnd      = 12;     // London killzone end   (server hour)
input int      InpNewYorkStart   = 13;     // New York killzone start (server hour)
input int      InpNewYorkEnd     = 17;     // New York killzone end   (server hour)
input string   InpBlackoutHours  = "";     // Extra blackout hours, e.g. "10,14,15,20"
input bool     InpUseSpread      = true;   // Suppress live alerts on wide spread
input int      InpMaxSpread      = 35;     // Max spread in points
input bool     InpUseHTF         = true;   // Higher timeframe bias filter
input ENUM_TIMEFRAMES InpHTF     = PERIOD_H4;  // Higher timeframe
input int      InpHTFRange       = 30;     // HTF bars used for the bias
input bool     InpUseVolume      = true;   // Volume expansion scoring
input double   InpVolMult        = 1.20;   // Volume must exceed N x average
input int      InpVolPeriod      = 20;     // Volume average period
input bool     InpUseDiscPrem    = true;   // Premium/discount (dealing range) filter
input int      InpRangeLookback  = 60;     // Dealing-range lookback
input double   InpDiscTolerance  = 0.10;   // Tolerance around equilibrium (0..0.5)

input bool     InpUseRetest      = true;   // CHoCH + zone retest entries
input int      InpRetestWindow   = 40;     // Bars a CHoCH stays actionable
input int      InpMaxZoneTouches = 2;      // Zone is dead after N retests
input double   InpRejectClose    = 0.60;   // Rejection close position (0..1)

input string   __sep6            = "=========="; // === 6. SIGNALS ===
input int      InpMinScore       = 68;     // Minimum confluence score (0..100)
input int      InpMinBarsBetween = 5;      // Cooldown between signals (bars)
input int      InpMaxPerDay      = 4;      // Max signals per day (prop guard)
input bool     InpAlertPopup     = true;   // Popup alert
input bool     InpAlertPush      = false;  // Push notification to mobile
input bool     InpAlertSound     = true;   // Sound alert
input string   InpSoundFile      = "alert2.wav"; // Sound file
input bool     InpAlertMail      = false;  // E-mail alert

input string   __sep7            = "=========="; // === 7. RISK & TARGETS ===
input double   InpRiskPercent    = 1.0;    // Risk per trade (% of balance)
input double   InpRewardRisk     = 2.0;    // Target in R multiples
input double   InpMinRR          = 1.5;    // Min RR accepted on a liquidity target
input double   InpMaxRR          = 4.0;    // Max RR accepted on a liquidity target
input bool     InpUseLiquidityTP = true;   // Prefer the next opposing liquidity as TP
input double   InpSLBufferATR    = 0.25;   // Stop-loss buffer (x ATR)
input double   InpSLBufferPts    = 20;     // Stop-loss buffer floor (points)
input double   InpMaxSLATR       = 3.0;    // Max stop distance (x ATR) - prop guard

input string   __sep8            = "=========="; // === 8. VISUALS ===
input bool     InpShowOB         = true;   // Draw order-block zones
input bool     InpShowFVG        = true;   // Draw fair value gaps
input bool     InpShowLiquidity  = true;   // Draw unswept liquidity levels
input int      InpMaxLiqLines    = 8;      // Max liquidity lines on chart
input bool     InpShowStructure  = true;   // Draw BOS / CHoCH labels
input bool     InpShowSwings     = false;  // Draw HH/HL/LH/LL labels
input bool     InpShowTradeLines = true;   // Draw entry/SL/TP lines
input bool     InpShowPanel      = true;   // Draw the dashboard
input int      InpPanelX         = 12;     // Panel X offset (px)
input int      InpPanelY         = 22;     // Panel Y offset (px)
input int      InpPanelFont      = 9;      // Panel font size
input int      InpDrawLastBars   = 500;    // Only draw objects from the last N bars
input int      InpZoneProject    = 120;    // Project zones N bars to the right
input color    InpBullOBColor    = C'16,52,30';   // Bullish order block fill
input color    InpBearOBColor    = C'58,18,18';   // Bearish order block fill
input color    InpBullFVGColor   = C'12,38,58';   // Bullish FVG fill
input color    InpBearFVGColor   = C'45,30,60';   // Bearish FVG fill
input color    InpBuyArrowColor  = clrLime;       // Buy arrow colour
input color    InpSellArrowColor = clrRed;        // Sell arrow colour
input int      InpArrowUp        = 233;           // Buy arrow wingdings code
input int      InpArrowDown      = 234;           // Sell arrow wingdings code
input int      InpArrowGapPts    = 40;            // Arrow distance from the bar (points)
input bool     InpVerbose        = false;         // Print engine diagnostics to the log

//+------------------------------------------------------------------+
//| DATA TYPES                                                       |
//+------------------------------------------------------------------+
struct SwingLevel
{
   datetime time;      // bar that printed the swing
   double   price;     // swing price
   int      dir;       // +1 = swing high, -1 = swing low
   bool     swept;     // liquidity taken (wick through + reclaim)
   bool     broken;    // structure broken (close through)
};

struct InstitutionalZone
{
   datetime created;   // bar on which the zone was registered
   datetime startTime; // left edge of the zone
   double   top;       // upper boundary
   double   bottom;    // lower boundary
   int      dir;       // +1 demand / -1 supply
   int      kind;      // 0 = order block, 1 = fair value gap
   int      touches;   // number of times price returned
   bool     active;    // still tradable
   int      quality;   // 0..100 at creation
};

struct SignalInfo
{
   datetime time;      // bar of the signal
   int      dir;       // +1 buy, -1 sell
   double   entry;     // reference entry (close of the signal bar)
   double   sl;        // stop loss
   double   tp;        // take profit
   int      score;     // confluence score
   double   lot;       // suggested lot for InpRiskPercent
   double   atr;       // ATR at signal time (for diagnostics)
};

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                     |
//+------------------------------------------------------------------+
double   gBuyBuf[];
double   gSellBuf[];

SwingLevel        gLevels[];
InstitutionalZone gZones[];
SignalInfo        gSignals[];

int      gSwingN        = 4;
int      gTrend         = 0;          // +1 bullish, -1 bearish, 0 undecided
int      gLastCHOCHDir  = 0;          // direction of the last CHoCH
datetime gLastCHOCHTime = 0;

int      gLastSweepDir     = 0;
datetime gLastSweepTime    = 0;
double   gLastSweepLevel   = 0.0;
double   gLastSweepExtreme = 0.0;

datetime gLastProcessedTime = 0;
int      gProcessedBars     = 0;
bool     gRebuilding        = false;
bool     gDirty             = false;

bool     gBlackout[24];
datetime gLastPanelTime = 0;
int      gObjCount      = 0;          // guard against runaway object creation

string   gObjNames[];                 // own object registry (for pruning)
datetime gObjTimes[];

//+------------------------------------------------------------------+
//| SMALL UTILITIES                                                  |
//+------------------------------------------------------------------+
int IMax(const int a, const int b) { return (a > b) ? a : b; }
int IMin(const int a, const int b) { return (a < b) ? a : b; }

// Number of bars between two times (approximate across weekends, which is
// acceptable for age / cooldown / recency windows).
int BarsAgo(const datetime older, const datetime newer)
{
   if(older <= 0 || newer <= older) return 0;
   int ps = PeriodSeconds();
   if(ps <= 0) return 0;
   return (int)((newer - older) / ps);
}

bool SameDay(const datetime a, const datetime b)
{
   return (TimeYear(a) == TimeYear(b) &&
           TimeMonth(a) == TimeMonth(b) &&
           TimeDay(a) == TimeDay(b));
}

string TFName(const int tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
   }
   return "TF";
}

//+------------------------------------------------------------------+
//| PRICE ACTION PRIMITIVES                                          |
//+------------------------------------------------------------------+
double TrueRange(const int shift)
{
   int bars = iBars(_Symbol, _Period);
   if(shift < 0 || shift >= bars) return 0.0;
   double h  = iHigh(_Symbol, _Period, shift);
   double l  = iLow(_Symbol, _Period, shift);
   double pc = (shift + 1 < bars) ? iClose(_Symbol, _Period, shift + 1)
                                  : iOpen(_Symbol, _Period, shift);
   double tr = h - l;
   double a  = MathAbs(h - pc);
   double b  = MathAbs(l - pc);
   if(a > tr) tr = a;
   if(b > tr) tr = b;
   return tr;
}

// ATR built from raw true ranges (no smoothing beyond the average itself,
// no dependency on any built-in indicator).
//
// NOTE: do NOT cache this by bar shift. Shift 1 refers to a different bar
// every time a new bar opens, so a shift-keyed cache silently freezes the
// ATR on a live chart. Recomputing is O(period) and happens once per bar.
double ATRv(const int shift, const int period)
{
   int p = IMax(1, period);
   int bars = iBars(_Symbol, _Period);
   double sum = 0.0;
   int n = 0;
   for(int k = 0; k < p; k++)
   {
      int s = shift + k;
      if(s >= bars) break;
      sum += TrueRange(s);
      n++;
   }
   return (n > 0) ? (sum / (double)n) : 0.0;
}

double AvgVolume(const int shift, const int period)
{
   int p = IMax(1, period);
   int bars = iBars(_Symbol, _Period);
   double sum = 0.0;
   int n = 0;
   for(int k = 1; k <= p; k++)
   {
      int s = shift + k;
      if(s >= bars) break;
      sum += (double)iVolume(_Symbol, _Period, s);
      n++;
   }
   return (n > 0) ? (sum / (double)n) : 0.0;
}

double RangeHigh(const int shift, const int lookback)
{
   int bars = iBars(_Symbol, _Period);
   int count = lookback;
   if(shift + count > bars) count = bars - shift;
   if(count <= 0) return 0.0;
   int idx = iHighest(_Symbol, _Period, MODE_HIGH, count, shift);
   if(idx < 0) return 0.0;
   return iHigh(_Symbol, _Period, idx);
}

double RangeLow(const int shift, const int lookback)
{
   int bars = iBars(_Symbol, _Period);
   int count = lookback;
   if(shift + count > bars) count = bars - shift;
   if(count <= 0) return 0.0;
   int idx = iLowest(_Symbol, _Period, MODE_LOW, count, shift);
   if(idx < 0) return 0.0;
   return iLow(_Symbol, _Period, idx);
}

// forward declarations (MQL4 needs them before use)
int  CountLiquidityLines();
void DeleteAllObjects();
void PruneObjects();
void CreatePanelBase();
void UpdatePanel();
void DrawZone(const int idx);
void DrawTrend(const string name, const datetime t1, const double p1,
               const datetime t2, const double p2, const color clr,
               const int style, const int width, const bool back);

//+------------------------------------------------------------------+
//| SWING DETECTION                                                  |
//+------------------------------------------------------------------+
bool IsSwingHigh(const int p, const int n)
{
   int bars = iBars(_Symbol, _Period);
   if(p - n < 0 || p + n >= bars) return false;
   double v = iHigh(_Symbol, _Period, p);
   for(int k = 1; k <= n; k++)
   {
      if(iHigh(_Symbol, _Period, p - k) >= v) return false;
      if(iHigh(_Symbol, _Period, p + k) >= v) return false;
   }
   return true;
}

bool IsSwingLow(const int p, const int n)
{
   int bars = iBars(_Symbol, _Period);
   if(p - n < 0 || p + n >= bars) return false;
   double v = iLow(_Symbol, _Period, p);
   for(int k = 1; k <= n; k++)
   {
      if(iLow(_Symbol, _Period, p - k) <= v) return false;
      if(iLow(_Symbol, _Period, p + k) <= v) return false;
   }
   return true;
}

// most recent unbroken swing in a direction (a swept pool is still valid
// structure: price closing through it IS a break of structure)
int LastStructureLevel(const int dir, const datetime before)
{
   for(int i = ArraySize(gLevels) - 1; i >= 0; i--)
   {
      if(gLevels[i].dir != dir)   continue;
      if(gLevels[i].broken)       continue;
      if(gLevels[i].time >= before) continue;
      return i;
   }
   return -1;
}

int LastLevelIndex(const int dir, const datetime before)
{
   for(int i = ArraySize(gLevels) - 1; i >= 0; i--)
   {
      if(gLevels[i].dir != dir)   continue;
      if(gLevels[i].broken)       continue;
      if(gLevels[i].time >= before) continue;
      return i;
   }
   return -1;
}

void TrimLevels()
{
   int n = ArraySize(gLevels);
   if(n <= 300) return;
   int remove = n - 300;
   for(int i = 0; i < n - remove; i++) gLevels[i] = gLevels[i + remove];
   ArrayResize(gLevels, n - remove);
}

//+------------------------------------------------------------------+
//| OBJECT REGISTRY + DRAW PRIMITIVES                                |
//+------------------------------------------------------------------+
string LiqName(const int dir, const datetime t)
{
   return PREFIX + "LIQ_" + ((dir > 0) ? "H_" : "L_") + IntegerToString((int)t);
}

string ZoneName(const int kind, const int dir, const datetime t)
{
   return PREFIX + "Z" + IntegerToString(kind) + ((dir > 0) ? "B_" : "S_") + IntegerToString((int)t);
}

string SigName(const int dir, const datetime t)
{
   return PREFIX + "SIG_" + ((dir > 0) ? "B_" : "S_") + IntegerToString((int)t);
}

void RegisterObject(const string name, const datetime t)
{
   int n = ArraySize(gObjNames);
   ArrayResize(gObjNames, n + 1);
   ArrayResize(gObjTimes, n + 1);
   gObjNames[n] = name;
   gObjTimes[n] = t;
   gObjCount++;
}

void ForgetObject(const string name)
{
   int n = ArraySize(gObjNames);
   for(int i = 0; i < n; i++)
   {
      if(gObjNames[i] == name)
      {
         ObjectDelete(0, name);
         gObjNames[i] = gObjNames[n - 1];
         gObjTimes[i] = gObjTimes[n - 1];
         ArrayResize(gObjNames, n - 1);
         ArrayResize(gObjTimes, n - 1);
         gObjCount--;
         return;
      }
   }
   ObjectDelete(0, name);
}

void DeleteAllObjects()
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i);
      if(StringFind(nm, PREFIX) == 0) ObjectDelete(0, nm);
   }
   ArrayResize(gObjNames, 0);
   ArrayResize(gObjTimes, 0);
   gObjCount = 0;
}

// Remove drawings whose anchor bar fell out of the visual window.
void PruneObjects()
{
   datetime cutoff = iTime(_Symbol, _Period, IMin(InpDrawLastBars, iBars(_Symbol, _Period) - 1));
   if(cutoff <= 0) return;
   for(int i = ArraySize(gObjNames) - 1; i >= 0; i--)
   {
      if(StringFind(gObjNames[i], PREFIX + "PNL_") == 0) continue;
      if(gObjTimes[i] > 0 && gObjTimes[i] < cutoff)
      {
         string nm = gObjNames[i];
         ForgetObject(nm);
      }
   }
}

bool ObjectAllowed()
{
   if(gObjCount > 900) return false;
   return true;
}

void DrawRectangle(const string name, const datetime t1, const double p1,
                   const datetime t2, const double p2, const color clr,
                   const int style, const int width)
{
   if(ObjectFind(0, name) >= 0) return;
   if(!ObjectAllowed()) return;
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   RegisterObject(name, t1);
}

void DrawTrend(const string name, const datetime t1, const double p1,
               const datetime t2, const double p2, const color clr,
               const int style, const int width, const bool back)
{
   if(ObjectFind(0, name) >= 0) return;
   if(!ObjectAllowed()) return;
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, back);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   RegisterObject(name, t1);
}

void DrawText(const string name, const datetime t, const double p,
              const string text, const color clr, const int size, const int anchor)
{
   if(ObjectFind(0, name) >= 0) return;
   if(!ObjectAllowed()) return;
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, p)) return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   RegisterObject(name, t);
}

// Left edge of the analysis window *as seen from bar s*. Anchoring the
// horizon to the bar being processed (not to "now") is what makes a fresh
// chart attach and a chart that has been running for weeks converge on the
// same decisions: the engine never depends on more than InpHistoryBars.
datetime StateHorizon(const int s)
{
   int bars  = iBars(_Symbol, _Period);
   int depth = IMax(InpHistoryBars, 200);
   int idx   = s + depth;
   if(idx >= bars) idx = bars - 1;
   if(idx < s)     idx = s;
   return iTime(_Symbol, _Period, idx);
}

//+------------------------------------------------------------------+
//| ZONE MANAGEMENT                                                  |
//+------------------------------------------------------------------+
void RemoveZone(const int idx)
{
   int n = ArraySize(gZones);
   if(idx < 0 || idx >= n) return;
   for(int i = idx; i < n - 1; i++) gZones[i] = gZones[i + 1];
   ArrayResize(gZones, n - 1);
}

bool ZoneOverlapsExisting(const double top, const double bottom, const int dir, const int kind)
{
   double h = top - bottom;
   if(h <= 0) return true;
   for(int i = 0; i < ArraySize(gZones); i++)
   {
      if(!gZones[i].active) continue;
      if(gZones[i].dir != dir) continue;
      if(gZones[i].kind != kind) continue;
      double oh = gZones[i].top - gZones[i].bottom;
      double lo = MathMax(gZones[i].bottom, bottom);
      double hi = MathMin(gZones[i].top, top);
      if(hi <= lo) continue;
      double overlap = (hi - lo) / MathMin(h, oh);
      if(overlap > 0.60) return true;
   }
   return false;
}

int AddZone(const int kind, const int dir, const double bottom, const double top,
            const datetime startTime, const datetime created, const int quality)
{
   if(top <= bottom) return -1;
   if(ZoneOverlapsExisting(top, bottom, dir, kind)) return -1;

   if(ArraySize(gZones) >= IMax(10, InpMaxZones))
   {
      int victim = -1;
      for(int i = 0; i < ArraySize(gZones); i++)
      {
         if(!gZones[i].active) { victim = i; break; }
      }
      if(victim < 0) victim = 0;
      ForgetObject(ZoneName(gZones[victim].kind, gZones[victim].dir, gZones[victim].startTime));
      RemoveZone(victim);
   }

   int n = ArraySize(gZones);
   ArrayResize(gZones, n + 1);
   gZones[n].created    = created;
   gZones[n].startTime  = startTime;
   gZones[n].top        = top;
   gZones[n].bottom     = bottom;
   gZones[n].dir        = dir;
   gZones[n].kind       = kind;
   gZones[n].touches    = 0;
   gZones[n].active     = true;
   gZones[n].quality    = quality;
   return n;
}

void DrawZone(const int idx)
{
   if(idx < 0 || idx >= ArraySize(gZones)) return;
   if(!gZones[idx].active) return;

   bool isOB = (gZones[idx].kind == 0);
   if(isOB && !InpShowOB)  return;
   if(!isOB && !InpShowFVG) return;

   datetime t = gZones[idx].startTime;
   if(BarsAgo(t, TimeCurrent()) > InpDrawLastBars) return;

   datetime t2 = TimeCurrent() + InpZoneProject * PeriodSeconds();
   color clr;
   int style = isOB ? STYLE_SOLID : STYLE_DOT;

   if(gZones[idx].dir > 0)
      clr = isOB ? InpBullOBColor : InpBullFVGColor;
   else
      clr = isOB ? InpBearOBColor : InpBearFVGColor;

   string nm = ZoneName(gZones[idx].kind, gZones[idx].dir, t);
   DrawRectangle(nm, t, gZones[idx].top, t2, gZones[idx].bottom, clr, style, 1);

   // balance line of the zone (institutional "mean threshold")
   string ml = nm + "_MID";
   double mid = (gZones[idx].top + gZones[idx].bottom) / 2.0;
   DrawTrend(ml, t, mid, t2, mid,
             (gZones[idx].dir > 0) ? clrLime : clrTomato, STYLE_DOT, 1, true);
}

int FindZoneAt(const double price, const int dir, const double tol)
{
   int best = -1;
   double bestDist = 1e15;
   for(int i = 0; i < ArraySize(gZones); i++)
   {
      if(!gZones[i].active) continue;
      if(gZones[i].dir != dir) continue;
      if(price < gZones[i].bottom - tol || price > gZones[i].top + tol) continue;
      double mid = (gZones[i].top + gZones[i].bottom) / 2.0;
      double d = MathAbs(price - mid);
      if(d < bestDist) { bestDist = d; best = i; }
   }
   return best;
}

// the best active zone of a direction that this bar has traded into
int ZoneTouched(const int s, const int dir)
{
   datetime barTime = iTime(_Symbol, _Period, s);
   double h = iHigh(_Symbol, _Period, s);
   double l = iLow(_Symbol, _Period, s);
   double c = iClose(_Symbol, _Period, s);
   int    best = -1;

   for(int i = 0; i < ArraySize(gZones); i++)
   {
      if(!gZones[i].active)             continue;
      if(gZones[i].dir != dir)          continue;
      if(gZones[i].created >= barTime)  continue;   // never use a zone on its own bar
      if(gZones[i].touches > InpMaxZoneTouches) continue;

      bool inside = false;
      if(dir > 0) inside = (l <= gZones[i].top && c >= gZones[i].bottom);
      else        inside = (h >= gZones[i].bottom && c <= gZones[i].top);
      if(!inside) continue;

      if(best < 0) { best = i; continue; }
      // prefer an order block over a gap, then the freshest zone
      int  kNew  = gZones[i].kind, kOld = gZones[best].kind;
      if(kNew < kOld) { best = i; continue; }
      if(kNew == kOld && gZones[i].startTime > gZones[best].startTime) best = i;
   }
   return best;
}

// true when an order block and an FVG of the same direction are stacked
bool ZoneStacked(const int idx)
{
   if(idx < 0) return false;
   int other = (gZones[idx].kind == 0) ? 1 : 0;
   for(int i = 0; i < ArraySize(gZones); i++)
   {
      if(!gZones[i].active) continue;
      if(gZones[i].dir != gZones[idx].dir) continue;
      if(gZones[i].kind != other) continue;
      double lo = MathMax(gZones[i].bottom, gZones[idx].bottom);
      double hi = MathMin(gZones[i].top, gZones[idx].top);
      if(hi > lo) return true;
   }
   return false;
}

void DropStaleState(const datetime horizon)
{
   // levels are appended chronologically: drop from the front
   int drop = 0;
   while(drop < ArraySize(gLevels) && gLevels[drop].time < horizon) drop++;
   if(drop > 0)
   {
      int n = ArraySize(gLevels);
      for(int i = 0; i < n - drop; i++) gLevels[i] = gLevels[i + drop];
      ArrayResize(gLevels, n - drop);
   }
   for(int i = ArraySize(gZones) - 1; i >= 0; i--)
   {
      if(!gZones[i].active || gZones[i].created >= horizon) continue;
      gZones[i].active = false;
      ForgetObject(ZoneName(gZones[i].kind, gZones[i].dir, gZones[i].startTime));
      ForgetObject(ZoneName(gZones[i].kind, gZones[i].dir, gZones[i].startTime) + "_MID");
   }
}

void MaintainZones(const int s, const double atr)
{
   datetime barTime = iTime(_Symbol, _Period, s);
   double c = iClose(_Symbol, _Period, s);
   double h = iHigh(_Symbol, _Period, s);
   double l = iLow(_Symbol, _Period, s);
   double inval = 0.10 * atr;

   for(int i = ArraySize(gZones) - 1; i >= 0; i--)
   {
      if(!gZones[i].active) continue;
      if(gZones[i].created == barTime) continue;   // do not age a zone on its own bar

      if(gZones[i].dir > 0)
      {
         if(c < gZones[i].bottom - inval)
         {
            gZones[i].active = false;
            ForgetObject(ZoneName(gZones[i].kind, gZones[i].dir, gZones[i].startTime));
            ForgetObject(ZoneName(gZones[i].kind, gZones[i].dir, gZones[i].startTime) + "_MID");
            continue;
         }
         if(l <= gZones[i].top) gZones[i].touches++;
      }
      else
      {
         if(c > gZones[i].top + inval)
         {
            gZones[i].active = false;
            ForgetObject(ZoneName(gZones[i].kind, gZones[i].dir, gZones[i].startTime));
            ForgetObject(ZoneName(gZones[i].kind, gZones[i].dir, gZones[i].startTime) + "_MID");
            continue;
         }
         if(h >= gZones[i].bottom) gZones[i].touches++;
      }
   }
}

//+------------------------------------------------------------------+
//| LIQUIDITY SWEEP (stop hunt + reclaim)                            |
//+------------------------------------------------------------------+
int DetectSweep(const int s, const double atr)
{
   datetime barTime = iTime(_Symbol, _Period, s);
   double h = iHigh(_Symbol, _Period, s);
   double l = iLow(_Symbol, _Period, s);
   double c = iClose(_Symbol, _Period, s);
   double rng = h - l;
   if(rng <= 0.0 || atr <= 0.0) return 0;

   double closePos = (c - l) / rng;          // 0 = at low, 1 = at high
   double penATR   = InpSweepPenATR * atr;

   double bestLowLevel  = -1.0;
   double bestHighLevel = -1.0;
   double lowExtreme    = l;
   double highExtreme   = h;

   for(int i = ArraySize(gLevels) - 1; i >= 0; i--)
   {
      if(gLevels[i].swept || gLevels[i].broken) continue;
      if(gLevels[i].time >= barTime) continue;

      int age = BarsAgo(gLevels[i].time, barTime);
      if(age < InpMinLevelAge) continue;

      // ---- sweep of a low: wick below the pool, close back above ----
      if(gLevels[i].dir < 0 && c > gLevels[i].price && l < gLevels[i].price)
      {
         double pen = gLevels[i].price - l;
         if(pen >= penATR && closePos >= InpSweepClosePos)
         {
            gLevels[i].swept = true;
            if(gLevels[i].price > bestLowLevel) bestLowLevel = gLevels[i].price;
            if(l < lowExtreme) lowExtreme = l;
            ForgetObject(LiqName(-1, gLevels[i].time));
         }
      }
      // ---- sweep of a high: wick above the pool, close back below ----
      if(gLevels[i].dir > 0 && c < gLevels[i].price && h > gLevels[i].price)
      {
         double pen = h - gLevels[i].price;
         if(pen >= penATR && closePos <= (1.0 - InpSweepClosePos))
         {
            gLevels[i].swept = true;
            if(bestHighLevel < 0.0 || gLevels[i].price < bestHighLevel) bestHighLevel = gLevels[i].price;
            if(h > highExtreme) highExtreme = h;
            ForgetObject(LiqName(1, gLevels[i].time));
         }
      }
   }

   bool bullSweep = (bestLowLevel >= 0.0);
   bool bearSweep = (bestHighLevel >= 0.0);

   if(bullSweep && bearSweep)
   {
      // outside bar that took both sides: follow the close
      if(closePos >= 0.5) bearSweep = false; else bullSweep = false;
   }

   if(bullSweep)
   {
      gLastSweepDir     = DIR_BULL;
      gLastSweepTime    = barTime;
      gLastSweepLevel   = bestLowLevel;
      gLastSweepExtreme = lowExtreme;
      if(InpVerbose)
         PrintFormat("HIEP sweep LOW @ %s  level=%s", TimeToString(barTime, TIME_DATE|TIME_MINUTES), DoubleToString(bestLowLevel, _Digits));
      return DIR_BULL;
   }
   if(bearSweep)
   {
      gLastSweepDir     = DIR_BEAR;
      gLastSweepTime    = barTime;
      gLastSweepLevel   = bestHighLevel;
      gLastSweepExtreme = highExtreme;
      if(InpVerbose)
         PrintFormat("HIEP sweep HIGH @ %s  level=%s", TimeToString(barTime, TIME_DATE|TIME_MINUTES), DoubleToString(bestHighLevel, _Digits));
      return DIR_BEAR;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| STRUCTURE: BOS / CHoCH + ORDER BLOCK CREATION                    |
//+------------------------------------------------------------------+
void CreateOrderBlock(const int s, const int dir, const double atr)
{
   int bars = iBars(_Symbol, _Period);
   int ob = -1;

   int stop = IMin(s + InpOBLookback, bars - 2);
   for(int k = s + 1; k <= stop; k++)
   {
      double o = iOpen(_Symbol, _Period, k);
      double c = iClose(_Symbol, _Period, k);
      if(dir > 0 && c < o) { ob = k; break; }   // last down candle before the up impulse
      if(dir < 0 && c > o) { ob = k; break; }   // last up candle before the down impulse
   }
   if(ob < 0) return;

   double obLow  = iLow(_Symbol, _Period, ob);
   double obHigh = iHigh(_Symbol, _Period, ob);
   double legExt = (dir > 0) ? iHigh(_Symbol, _Period, s) : iLow(_Symbol, _Period, s);
   double disp   = (dir > 0) ? (legExt - obLow) : (obHigh - legExt);

   if(disp < InpDisplacement * atr) return;

   double top, bottom;
   if(dir > 0)
   {
      bottom = obLow;
      top    = InpRefinedOB ? MathMax(iOpen(_Symbol, _Period, ob), iClose(_Symbol, _Period, ob)) : obHigh;
   }
   else
   {
      top    = obHigh;
      bottom = InpRefinedOB ? MathMin(iOpen(_Symbol, _Period, ob), iClose(_Symbol, _Period, ob)) : obLow;
   }
   if(top <= bottom) top = bottom + 10 * Point;

   int quality = (int)MathMin(100.0, 55.0 + (disp / atr) * 15.0);
   int idx = AddZone(0, dir, bottom, top, iTime(_Symbol, _Period, ob), iTime(_Symbol, _Period, s), quality);
   if(idx >= 0)
   {
      DrawZone(idx);
      if(InpVerbose)
         PrintFormat("HIEP OB %s created @ %s  [%s - %s]",
                     (dir > 0 ? "DEMAND" : "SUPPLY"),
                     TimeToString(iTime(_Symbol, _Period, s), TIME_DATE|TIME_MINUTES),
                     DoubleToString(bottom, _Digits), DoubleToString(top, _Digits));
   }
}

void DetectStructure(const int s, const double atr)
{
   datetime barTime = iTime(_Symbol, _Period, s);
   double c = iClose(_Symbol, _Period, s);

   int hiIdx = LastStructureLevel(DIR_BULL, barTime);
   int loIdx = LastStructureLevel(DIR_BEAR, barTime);

   int brokenDir = 0;

   if(hiIdx >= 0 && c > gLevels[hiIdx].price)
   {
      gLevels[hiIdx].broken = true;
      ForgetObject(LiqName(1, gLevels[hiIdx].time));
      bool choch = (gTrend <= 0);
      gTrend = DIR_BULL;
      if(choch) { gLastCHOCHDir = DIR_BULL; gLastCHOCHTime = barTime; }
      brokenDir = DIR_BULL;
      if(InpShowStructure)
         DrawText(PREFIX + "STR_" + IntegerToString((int)barTime),
                  barTime, iHigh(_Symbol, _Period, s) + atr * 0.9,
                  choch ? "CHoCH" : "BOS", clrDeepSkyBlue, 9, ANCHOR_LOWER);
      if(InpUseOB) CreateOrderBlock(s, DIR_BULL, atr);
   }
   else if(loIdx >= 0 && c < gLevels[loIdx].price)
   {
      gLevels[loIdx].broken = true;
      ForgetObject(LiqName(-1, gLevels[loIdx].time));
      bool choch = (gTrend >= 0);
      gTrend = DIR_BEAR;
      if(choch) { gLastCHOCHDir = DIR_BEAR; gLastCHOCHTime = barTime; }
      brokenDir = DIR_BEAR;
      if(InpShowStructure)
         DrawText(PREFIX + "STR_" + IntegerToString((int)barTime),
                  barTime, iLow(_Symbol, _Period, s) - atr * 0.9,
                  choch ? "CHoCH" : "BOS", clrOrangeRed, 9, ANCHOR_UPPER);
      if(InpUseOB) CreateOrderBlock(s, DIR_BEAR, atr);
   }

   if(brokenDir != 0 && InpVerbose)
      PrintFormat("HIEP structure %s @ %s",
                  (brokenDir > 0 ? "BULLISH BREAK" : "BEARISH BREAK"),
                  TimeToString(barTime, TIME_DATE|TIME_MINUTES));
}

//+------------------------------------------------------------------+
//| FAIR VALUE GAP (imbalance)                                       |
//+------------------------------------------------------------------+
void DetectFVG(const int s, const double atr)
{
   int bars = iBars(_Symbol, _Period);
   if(s + 2 >= bars) return;
   if(atr <= 0.0) return;

   double c1 = iClose(_Symbol, _Period, s);
   double o1 = iOpen(_Symbol, _Period, s);
   double h1 = iHigh(_Symbol, _Period, s);
   double l1 = iLow(_Symbol, _Period, s);
   double h3 = iHigh(_Symbol, _Period, s + 2);
   double l3 = iLow(_Symbol, _Period, s + 2);
   double minGap = InpMinFVGATR * atr;

   // bullish imbalance: gap between the high of candle A and the low of candle C
   if(c1 > o1 && (l1 - h3) >= minGap)
   {
      int idx = AddZone(1, DIR_BULL, h3, l1, iTime(_Symbol, _Period, s + 2),
                        iTime(_Symbol, _Period, s), (int)MathMin(100.0, 50.0 + ((l1 - h3) / atr) * 25.0));
      if(idx >= 0)
      {
         DrawZone(idx);
         if(InpVerbose)
            PrintFormat("HIEP bullish FVG @ %s [%s - %s]", TimeToString(iTime(_Symbol, _Period, s), TIME_DATE|TIME_MINUTES),
                        DoubleToString(h3, _Digits), DoubleToString(l1, _Digits));
      }
   }
   // bearish imbalance
   if(c1 < o1 && (l3 - h1) >= minGap)
   {
      int idx = AddZone(1, DIR_BEAR, h1, l3, iTime(_Symbol, _Period, s + 2),
                        iTime(_Symbol, _Period, s), (int)MathMin(100.0, 50.0 + ((l3 - h1) / atr) * 25.0));
      if(idx >= 0)
      {
         DrawZone(idx);
         if(InpVerbose)
            PrintFormat("HIEP bearish FVG @ %s [%s - %s]", TimeToString(iTime(_Symbol, _Period, s), TIME_DATE|TIME_MINUTES),
                        DoubleToString(h1, _Digits), DoubleToString(l3, _Digits));
      }
   }
}

//+------------------------------------------------------------------+
//| HIGHER TIMEFRAME BIAS (no look-ahead)                            |
//+------------------------------------------------------------------+
int HTFBiasAt(const datetime barTime)
{
   if(!InpUseHTF) return 0;
   if(InpHTF == PERIOD_CURRENT) return 0;
   if((int)InpHTF < Period()) return 0;      // never use a lower timeframe as context

   int htf = (int)InpHTF;
   int htfBars = iBars(_Symbol, htf);
   if(htfBars < 10) return 0;

   int sh = iBarShift(_Symbol, htf, barTime, false);
   if(sh < 0) return 0;

   int start = sh + 1;                 // last HTF bar CLOSED before barTime
   if(start >= htfBars) return 0;

   int count = InpHTFRange;
   if(start + count > htfBars) count = htfBars - start;
   if(count < 3) return 0;

   int hi = iHighest(_Symbol, htf, MODE_HIGH, count, start);
   int lo = iLowest(_Symbol, htf, MODE_LOW, count, start);
   if(hi < 0 || lo < 0) return 0;

   double hh = iHigh(_Symbol, htf, hi);
   double ll = iLow(_Symbol, htf, lo);
   double cc = iClose(_Symbol, htf, start);
   if(hh <= ll) return 0;

   double mid = (hh + ll) / 2.0;
   if(cc > mid) return DIR_BULL;
   if(cc < mid) return DIR_BEAR;
   return 0;
}

//+------------------------------------------------------------------+
//| SESSION / SPREAD / RISK HELPERS                                  |
//+------------------------------------------------------------------+
bool InHourRange(const int h, const int a, const int b)
{
   if(a == b) return false;                 // empty window
   if(a < 0 || b < 0) return true;          // disabled
   if(a < b) return (h >= a && h < b);
   return (h >= a || h < b);                // window wraps midnight
}

bool IsSessionActive(const datetime t)
{
   if(!InpUseSession) return true;
   int h = TimeHour(t);
   if(h < 0 || h > 23) return true;
   if(gBlackout[h]) return false;
   if(InHourRange(h, InpLondonStart, InpLondonEnd))  return true;
   if(InHourRange(h, InpNewYorkStart, InpNewYorkEnd)) return true;
   return false;
}

string SessionName(const datetime t)
{
   int h = TimeHour(t);
   if(gBlackout[h]) return "BLACKOUT";
   if(InHourRange(h, InpLondonStart, InpLondonEnd))   return "LONDON";
   if(InHourRange(h, InpNewYorkStart, InpNewYorkEnd)) return "NEW YORK";
   return "OFF-SESSION";
}

bool SpreadOK()
{
   if(!InpUseSpread) return true;
   double sp = MarketInfo(_Symbol, MODE_SPREAD);
   if(sp <= 0) return true;
   return (sp <= InpMaxSpread);
}

double SuggestLot(const double entry, const double sl)
{
   double dist = MathAbs(entry - sl);
   if(dist <= 0) return 0.0;

   double tickSize = MarketInfo(_Symbol, MODE_TICKSIZE);
   double tickVal  = MarketInfo(_Symbol, MODE_TICKVALUE);
   double step     = MarketInfo(_Symbol, MODE_LOTSTEP);
   double minLot   = MarketInfo(_Symbol, MODE_MINLOT);
   double maxLot   = MarketInfo(_Symbol, MODE_MAXLOT);
   if(tickSize <= 0 || tickVal <= 0) return 0.0;
   if(step <= 0) step = 0.01;

   double riskMoney = AccountBalance() * InpRiskPercent / 100.0;
   double pointVal  = tickVal * (Point / tickSize);     // account value of 1 point per 1 lot
   double points    = dist / Point;
   if(pointVal <= 0 || points <= 0) return 0.0;

   double lot = riskMoney / (points * pointVal);
   lot = MathFloor(lot / step) * step;
   if(lot < minLot) return 0.0;
   if(maxLot > 0 && lot > maxLot) lot = maxLot;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| SIGNAL EVALUATION                                                |
//+------------------------------------------------------------------+
int SignalsOnDay(const datetime day)
{
   int n = 0;
   for(int i = 0; i < ArraySize(gSignals); i++)
      if(SameDay(gSignals[i].time, day)) n++;
   return n;
}

int LastSignalBarsAgo(const datetime barTime)
{
   int n = ArraySize(gSignals);
   if(n == 0) return 9999;
   return BarsAgo(gSignals[n - 1].time, barTime);
}

void StoreSignal(SignalInfo &sig)
{
   int n = ArraySize(gSignals);
   ArrayResize(gSignals, n + 1);
   gSignals[n] = sig;
   if(ArraySize(gSignals) > 200)
   {
      for(int i = 0; i < ArraySize(gSignals) - 1; i++) gSignals[i] = gSignals[i + 1];
      ArrayResize(gSignals, ArraySize(gSignals) - 1);
   }
}

void FireAlert(SignalInfo &sig)
{
   if(gRebuilding) return;                     // never alert historical replay

   if(!SpreadOK())
   {
      if(InpVerbose)
         PrintFormat("HIEP signal suppressed: spread %d > %d",
                     (int)MarketInfo(_Symbol, MODE_SPREAD), InpMaxSpread);
      return;
   }

   string tf = TFName(Period());
   string msg = StringFormat("HIEP %s %s %s | entry %s  SL %s  TP %s | score %d | lot %.2f | %s",
                             (sig.dir > 0) ? "BUY" : "SELL", _Symbol, tf,
                             DoubleToString(sig.entry, _Digits),
                             DoubleToString(sig.sl, _Digits),
                             DoubleToString(sig.tp, _Digits),
                             sig.score, sig.lot, SessionName(sig.time));

   if(InpAlertPopup) Alert(msg);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertMail)  SendMail("HIEP signal", msg);
   if(InpAlertSound) PlaySound(InpSoundFile);
   Print(msg);
}

void DrawSignal(SignalInfo &sig, const int s)
{
   int dir = sig.dir;
   double atr = sig.atr;

   // marker
   string nm = SigName(dir, sig.time) + "_M";
   double gap = MathMax(InpArrowGapPts * Point, atr * 0.35);
   double y   = (dir > 0) ? iLow(_Symbol, _Period, s) - gap
                          : iHigh(_Symbol, _Period, s) + gap;
   DrawText(nm, sig.time, y, StringFormat("%s %d", (dir > 0 ? "BUY" : "SELL"), sig.score),
            (dir > 0) ? InpBuyArrowColor : InpSellArrowColor, 8,
            (dir > 0) ? ANCHOR_UPPER : ANCHOR_LOWER);

   if(!InpShowTradeLines) return;

   datetime t1 = sig.time;
   datetime t2 = sig.time + 30 * PeriodSeconds();

   DrawTrend(SigName(dir, sig.time) + "_E", t1, sig.entry, t2, sig.entry,
             clrSilver, STYLE_DOT, 1, false);
   DrawTrend(SigName(dir, sig.time) + "_SL", t1, sig.sl, t2, sig.sl,
             clrRed, STYLE_SOLID, 1, false);
   DrawTrend(SigName(dir, sig.time) + "_TP", t1, sig.tp, t2, sig.tp,
             clrLime, STYLE_SOLID, 1, false);
   DrawText(SigName(dir, sig.time) + "_SLT", t2, sig.sl,
            "SL " + DoubleToString(sig.sl, _Digits), clrRed, 8, ANCHOR_RIGHT);
   DrawText(SigName(dir, sig.time) + "_TPT", t2, sig.tp,
            "TP " + DoubleToString(sig.tp, _Digits), clrLime, 8, ANCHOR_RIGHT);
}

void EmitSignal(const int s, const int dir, const int score,
                const double zoneTop, const double zoneBottom)
{
   double atr   = ATRv(s, InpATRPeriod);
   double entry = iClose(_Symbol, _Period, s);
   double h     = iHigh(_Symbol, _Period, s);
   double l     = iLow(_Symbol, _Period, s);

   double buf = MathMax(atr * InpSLBufferATR, InpSLBufferPts * Point);
   double sp  = MarketInfo(_Symbol, MODE_SPREAD) * Point;
   if(sp > buf) buf = sp * 1.5;

   double sl, tp;
   if(dir > 0)
   {
      sl = MathMin(l, zoneBottom) - buf;
      if(entry - sl > InpMaxSLATR * atr) sl = l - buf;      // zone too far: structure stop
      if(entry - sl > InpMaxSLATR * atr) sl = entry - InpMaxSLATR * atr;
      double risk = entry - sl;
      if(risk <= 0) return;
      tp = entry + risk * InpRewardRisk;
      if(InpUseLiquidityTP)
      {
         // next unswept liquidity pool, but only inside the RR window
         int idx = LastLevelIndex(DIR_BULL, iTime(_Symbol, _Period, s));
         if(idx >= 0)
         {
            double lvl = gLevels[idx].price;
            if(lvl >= entry + risk * InpMinRR && lvl <= entry + risk * InpMaxRR)
               tp = lvl;
         }
      }
   }
   else
   {
      sl = MathMax(h, zoneTop) + buf;
      if(sl - entry > InpMaxSLATR * atr) sl = h + buf;      // zone too far: structure stop
      if(sl - entry > InpMaxSLATR * atr) sl = entry + InpMaxSLATR * atr;
      double risk = sl - entry;
      if(risk <= 0) return;
      tp = entry - risk * InpRewardRisk;
      if(InpUseLiquidityTP)
      {
         int idx = LastLevelIndex(DIR_BEAR, iTime(_Symbol, _Period, s));
         if(idx >= 0)
         {
            double lvl = gLevels[idx].price;
            if(lvl <= entry - risk * InpMinRR && lvl >= entry - risk * InpMaxRR)
               tp = lvl;
         }
      }
   }

   if(dir > 0 && tp <= entry) return;
   if(dir < 0 && tp >= entry) return;

   // markers are written only once the setup is fully validated, so an arrow
   // can never appear without a corresponding entry / SL / TP
   if(dir > 0) gBuyBuf[s]  = l - MathMax(InpArrowGapPts * Point, atr * 0.35);
   else        gSellBuf[s] = h + MathMax(InpArrowGapPts * Point, atr * 0.35);

   SignalInfo sig;
   sig.time  = iTime(_Symbol, _Period, s);
   sig.dir   = dir;
   sig.entry = entry;
   sig.sl    = NormalizeDouble(sl, _Digits);
   sig.tp    = NormalizeDouble(tp, _Digits);
   sig.score = score;
   sig.atr   = atr;
   sig.lot   = SuggestLot(entry, sl);

   StoreSignal(sig);
   if(!gRebuilding || BarsAgo(sig.time, TimeCurrent()) <= 30) DrawSignal(sig, s);
   FireAlert(sig);

   gDirty = true;
   if(InpVerbose)
      PrintFormat("HIEP SIGNAL %s score=%d entry=%s sl=%s tp=%s",
                  (dir > 0 ? "BUY" : "SELL"), score,
                  DoubleToString(entry, _Digits), DoubleToString(sig.sl, _Digits),
                  DoubleToString(sig.tp, _Digits));
}

void EvaluateSignal(const int s, const int dir, const double atr)
{
   datetime barTime = iTime(_Symbol, _Period, s);

   // ---- hard filters -------------------------------------------------
   if(!IsSessionActive(barTime)) return;

   if(BarsAgo(gLastSweepTime, barTime) > InpSweepRecency) return;

   if(LastSignalBarsAgo(barTime) < InpMinBarsBetween) return;
   if(SignalsOnDay(barTime) >= InpMaxPerDay) return;

   double o = iOpen(_Symbol, _Period, s);
   double c = iClose(_Symbol, _Period, s);
   double h = iHigh(_Symbol, _Period, s);
   double l = iLow(_Symbol, _Period, s);
   if(h - l <= 0) return;

   // confirmation candle must close in the signal direction
   if(dir > 0 && c <= o) return;
   if(dir < 0 && c >= o) return;

   // ---- zone confluence ---------------------------------------------
   double tol = 0.35 * atr;
   int zi = FindZoneAt(gLastSweepExtreme, dir, tol);
   if(zi < 0) zi = FindZoneAt(c, dir, tol * 0.5);
   if(zi < 0) return;                       // no institutional zone = no trade

   int score = 35;                          // base: sweep + reclaim

   if(gZones[zi].kind == 0) score += 15;    // order block
   else                     score += 10;    // fair value gap

   if(ZoneStacked(zi))           score += 8;
   if(gZones[zi].touches <= 1)   score += 5;

   // confirmation candle quality
   if(dir > 0 && c > iHigh(_Symbol, _Period, s + 1)) score += 12;
   if(dir < 0 && c < iLow(_Symbol, _Period, s + 1))  score += 12;

   // ---- structure ----------------------------------------------------
   // A sweep that is reclaimed with displacement is itself a structural
   // event, so an aligned trend / fresh CHoCH is preferred but a strong
   // displacement close is accepted as confirmation.
   bool displacement = false;
   if(dir > 0) displacement = (c > iHigh(_Symbol, _Period, s + 1) && (c - o) >= 0.5 * (h - l));
   if(dir < 0) displacement = (c < iLow(_Symbol, _Period, s + 1)  && (o - c) >= 0.5 * (h - l));

   bool structOk = !InpRequireStruct;
   if(gTrend == dir) structOk = true;
   if(!structOk && gLastCHOCHDir == dir &&
      BarsAgo(gLastCHOCHTime, barTime) <= InpStructRecency)
      structOk = true;
   if(!structOk && displacement) structOk = true;
   if(!structOk) return;
   if(gTrend == dir) score += 10;
   if(BarsAgo(gLastCHOCHTime, barTime) <= InpStructRecency) score += 5;

   // ---- higher timeframe --------------------------------------------
   int htf = HTFBiasAt(barTime);
   if(htf == dir)                score += 10;
   else if(htf != 0 && htf == -dir) score -= 10;

   // ---- volume -------------------------------------------------------
   if(InpUseVolume)
   {
      double av = AvgVolume(s, InpVolPeriod);
      double v  = (double)iVolume(_Symbol, _Period, s);
      if(av > 0 && v >= av * InpVolMult) score += 8;
      else                               score -= 4;
   }

   // ---- premium / discount ------------------------------------------
   if(InpUseDiscPrem)
   {
      double rh = RangeHigh(s, InpRangeLookback);
      double rl = RangeLow(s, InpRangeLookback);
      double rng = rh - rl;
      if(rng > 0)
      {
         double eq = (rh + rl) / 2.0;
         if(dir > 0)
         {
            if(c > eq + InpDiscTolerance * rng) return;   // buying at a premium
            score += 8;
         }
         else
         {
            if(c < eq - InpDiscTolerance * rng) return;   // selling at a discount
            score += 8;
         }
      }
   }

   if(score < InpMinScore) return;
   if(score > 100) score = 100;

   EmitSignal(s, dir, score, gZones[zi].top, gZones[zi].bottom);
}

//+------------------------------------------------------------------+
//| FAMILY B: CHoCH + RETEST OF AN INSTITUTIONAL ZONE                |
//| After structure flips, the "hidden" entry is the first return    |
//| into the zone that produced the displacement, with a rejection    |
//| candle. This is where institutions re-load without chasing.       |
//+------------------------------------------------------------------+
void EvaluateRetest(const int s)
{
   if(!InpUseRetest) return;
   if(gLastCHOCHTime == 0 || gLastCHOCHDir == 0) return;

   datetime barTime = iTime(_Symbol, _Period, s);
   int dir = gLastCHOCHDir;

   if(BarsAgo(gLastCHOCHTime, barTime) > InpRetestWindow) return;
   if(!IsSessionActive(barTime)) return;
   if(LastSignalBarsAgo(barTime) < InpMinBarsBetween) return;
   if(SignalsOnDay(barTime) >= InpMaxPerDay) return;

   double o = iOpen(_Symbol, _Period, s);
   double c = iClose(_Symbol, _Period, s);
   double h = iHigh(_Symbol, _Period, s);
   double l = iLow(_Symbol, _Period, s);
   if(h - l <= 0) return;

   // rejection candle in the direction of the structure shift
   double closePos = (c - l) / (h - l);
   if(dir > 0 && !(c > o && closePos >= InpRejectClose))       return;
   if(dir < 0 && !(c < o && (1.0 - closePos) >= InpRejectClose)) return;

   int zi = ZoneTouched(s, dir);
   if(zi < 0) return;

   int score = 35;                              // base: CHoCH + zone retest
   if(gZones[zi].kind == 0) score += 15;        // order block
   else                     score += 10;        // fair value gap
   if(ZoneStacked(zi))              score += 8;
   if(gZones[zi].touches <= 1)      score += 5;
   if(dir > 0 && closePos >= 0.75) score += 12;   // strong demand rejection
   if(dir < 0 && closePos <= 0.25) score += 12;   // strong supply rejection
   if(gTrend == dir)                score += 10;
   if(BarsAgo(gLastCHOCHTime, barTime) <= 10) score += 8;

   int htf = HTFBiasAt(barTime);
   if(htf == dir)                     score += 10;
   else if(htf != 0 && htf == -dir)   score -= 10;

   if(InpUseVolume)
   {
      double av = AvgVolume(s, InpVolPeriod);
      double v  = (double)iVolume(_Symbol, _Period, s);
      if(av > 0 && v >= av * InpVolMult) score += 8;
      else                               score -= 4;
   }

   if(InpUseDiscPrem)
   {
      double rh = RangeHigh(s, InpRangeLookback);
      double rl = RangeLow(s, InpRangeLookback);
      double rng = rh - rl;
      if(rng > 0)
      {
         double eq = (rh + rl) / 2.0;
         if(dir > 0)
         {
            if(c > eq + InpDiscTolerance * rng) return;
            score += 8;
         }
         else
         {
            if(c < eq - InpDiscTolerance * rng) return;
            score += 8;
         }
      }
   }

   if(score < InpMinScore) return;
   if(score > 100) score = 100;

   EmitSignal(s, dir, score, gZones[zi].top, gZones[zi].bottom);
}

//+------------------------------------------------------------------+
//| PER-BAR PIPELINE                                                 |
//+------------------------------------------------------------------+
void AddSwingPoint(const int p, const int dir)
{
   datetime t = iTime(_Symbol, _Period, p);
   double price = (dir > 0) ? iHigh(_Symbol, _Period, p) : iLow(_Symbol, _Period, p);
   if(price <= 0) return;

   int n = ArraySize(gLevels);
   if(n > 0 && gLevels[n - 1].time == t && gLevels[n - 1].dir == dir) return;

   ArrayResize(gLevels, n + 1);
   gLevels[n].time   = t;
   gLevels[n].price  = price;
   gLevels[n].dir    = dir;
   gLevels[n].swept  = false;
   gLevels[n].broken = false;
   TrimLevels();

   int total = ArraySize(gLevels);
   bool ext = false;
   if(total >= 2)
   {
      for(int k = total - 2; k >= 0; k--)
      {
         if(gLevels[k].dir == dir && gLevels[k].time < t)
         {
            ext = (dir > 0) ? (price > gLevels[k].price) : (price < gLevels[k].price);
            break;
         }
      }
   }

   if(InpShowSwings)
   {
      string lbl = (dir > 0) ? (ext ? "HH" : "LH") : (ext ? "HL" : "LL");
      double off = 0.35 * ATRv(p, InpATRPeriod);
      DrawText(PREFIX + "SW_" + IntegerToString((int)t) + ((dir > 0) ? "H" : "L"),
               t, (dir > 0) ? price + off : price - off, lbl,
               (dir > 0) ? clrSilver : clrGray, 7,
               (dir > 0) ? ANCHOR_LOWER : ANCHOR_UPPER);
   }

   // draw the liquidity pool while it is still intact
   if(InpShowLiquidity && CountLiquidityLines() < InpMaxLiqLines)
   {
      datetime t2 = TimeCurrent() + InpZoneProject * PeriodSeconds();
      DrawTrend(LiqName(dir, t), t, price, t2, price,
                (dir > 0) ? clrOrange : clrDeepSkyBlue, STYLE_DASH, 1, true);
   }
}

int CountLiquidityLines()
{
   int n = 0;
   for(int i = 0; i < ArraySize(gObjNames); i++)
      if(StringFind(gObjNames[i], PREFIX + "LIQ_") == 0) n++;
   return n;
}

void ProcessClosedBar(const int s)
{
   int bars = iBars(_Symbol, _Period);
   if(s < 1 || s >= bars) return;

   // 1) confirm the fractal that becomes final on this bar
   int p = s + gSwingN;
   if(p < bars - 1)
   {
      if(IsSwingHigh(p, gSwingN)) AddSwingPoint(p, DIR_BULL);
      if(IsSwingLow(p, gSwingN))  AddSwingPoint(p, DIR_BEAR);
   }

   double atr = ATRv(s, InpATRPeriod);
   if(atr <= 0.0) atr = iHigh(_Symbol, _Period, s) - iLow(_Symbol, _Period, s);
   if(atr <= 0.0) return;

   // 2) stop hunt / liquidity grab
   int sweepDir = 0;
   if(InpUseSweeps) sweepDir = DetectSweep(s, atr);

   // 3) structure + order blocks
   DetectStructure(s, atr);

   // 4) imbalance
   if(InpUseFVG) DetectFVG(s, atr);

   // 5) zone life-cycle
   MaintainZones(s, atr);

   DropStaleState(StateHorizon(s));

   // 6) signals: (A) sweep + reclaim, (B) CHoCH + zone retest
   if(sweepDir != 0 && InpUseSweeps) EvaluateSignal(s, sweepDir, atr);
   EvaluateRetest(s);
}

//+------------------------------------------------------------------+
//| ENGINE DRIVER                                                    |
//+------------------------------------------------------------------+
void ResetState()
{
   ArrayResize(gLevels, 0);
   ArrayResize(gZones, 0);
   ArrayResize(gSignals, 0);
   gTrend           = 0;
   gLastCHOCHDir    = 0;
   gLastCHOCHTime   = 0;
   gLastSweepDir    = 0;
   gLastSweepTime   = 0;
   gLastSweepLevel  = 0.0;
   gLastSweepExtreme= 0.0;
}

void ClearBuffers()
{
   int n = IMin(ArraySize(gBuyBuf), ArraySize(gSellBuf));
   if(n <= 0) n = iBars(_Symbol, _Period);
   for(int i = 0; i < n; i++)
   {
      gBuyBuf[i]  = EMPTY_VALUE;
      gSellBuf[i] = EMPTY_VALUE;
   }
}

void Rebuild()
{
   gRebuilding = true;
   DeleteAllObjects();
   ResetState();
   ClearBuffers();

   int bars = iBars(_Symbol, _Period);
   int first = IMin(bars - 2, InpHistoryBars + gSwingN + 60);
   if(first > bars - InpATRPeriod - 3) first = bars - InpATRPeriod - 3;
   if(first < 2) first = 2;

   for(int s = first; s >= 1; s--) ProcessClosedBar(s);

   gLastProcessedTime = iTime(_Symbol, _Period, 1);
   gProcessedBars     = bars;
   gRebuilding        = false;

   PruneObjects();
   if(InpShowPanel) CreatePanelBase();
   if(InpVerbose)
      PrintFormat("HIEP rebuilt: %d bars, %d levels, %d zones, %d signals",
                  first, ArraySize(gLevels), ArraySize(gZones), ArraySize(gSignals));
}

void Advance()
{
   int lastShift = iBarShift(_Symbol, _Period, gLastProcessedTime, false);
   if(lastShift < 0)
   {
      Rebuild();
      return;
   }
   bool newBar = (lastShift > 1);
   for(int s = lastShift - 1; s >= 1; s--) ProcessClosedBar(s);

   gLastProcessedTime = iTime(_Symbol, _Period, 1);
   gProcessedBars     = iBars(_Symbol, _Period);

   if(newBar) PruneObjects();
   if(InpShowPanel) CreatePanelBase();
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+
void EnsureLabel(const string name, const int x, const int y, const int size)
{
   if(ObjectFind(0, name) >= 0) return;
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return;
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void CreatePanelBase()
{
   if(!InpShowPanel) return;
   string bg = PREFIX + "PNL_BG";
   if(ObjectFind(0, bg) >= 0) return;
   if(!ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, InpPanelX - 8);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, InpPanelY - 8);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, 300);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, 210);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'12,16,22');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'45,55,70');
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);
}

string LiveWatchText()
{
   int bars = iBars(_Symbol, _Period);
   if(bars < 5) return "waiting for data";
   double h = iHigh(_Symbol, _Period, 0);
   double l = iLow(_Symbol, _Period, 0);
   double c = iClose(_Symbol, _Period, 0);
   datetime now = iTime(_Symbol, _Period, 0);

   for(int i = ArraySize(gLevels) - 1; i >= 0; i--)
   {
      if(gLevels[i].swept || gLevels[i].broken) continue;
      if(gLevels[i].time >= now) continue;
      if(gLevels[i].dir < 0 && l < gLevels[i].price && c > gLevels[i].price)
         return "LIQUIDITY TAKEN BELOW - WATCH RECLAIM";
      if(gLevels[i].dir > 0 && h > gLevels[i].price && c < gLevels[i].price)
         return "LIQUIDITY TAKEN ABOVE - WATCH REJECTION";
   }
   return "no live sweep";
}

void UpdatePanel()
{
   if(!InpShowPanel) return;
   if(TimeCurrent() == gLastPanelTime) return;
   gLastPanelTime = TimeCurrent();

   string lines[32];
   color  cols[32];
   int n = 0;
   for(int z = 0; z < 32; z++) { lines[z] = ""; cols[z] = clrSilver; }

   string bias = "RANGE / UNDECIDED";
   color  biasC = clrSilver;
   if(gTrend > 0) { bias = "BULLISH (HH/HL)"; biasC = clrLime; }
   if(gTrend < 0) { bias = "BEARISH (LH/LL)"; biasC = clrTomato; }

   int htf = 0;
   string htfTxt = "OFF";
   if(InpUseHTF) { htf = HTFBiasAt(TimeCurrent()); }
   if(htf > 0) htfTxt = TFName((int)InpHTF) + " BULL";
   if(htf < 0) htfTxt = TFName((int)InpHTF) + " BEAR";

   double sp = MarketInfo(_Symbol, MODE_SPREAD);
   double atr = ATRv(0, InpATRPeriod);
   double av  = AvgVolume(0, InpVolPeriod);
   double v0  = (double)iVolume(_Symbol, _Period, 0);
   double vr  = (av > 0) ? v0 / av : 0.0;

   int today = SignalsOnDay(TimeCurrent());
   int lossesToCap = (InpRiskPercent > 0) ? (int)MathFloor(5.0 / InpRiskPercent) : 0;

   bool sessionOn = IsSessionActive(TimeCurrent());
   bool spreadOn  = SpreadOK();

   string guard = "GREEN";
   color  guardC = clrLime;
   if(!sessionOn || !spreadOn) { guard = "AMBER - FILTERED"; guardC = clrGold; }
   if(today >= InpMaxPerDay)   { guard = "LOCKED - DAILY CAP"; guardC = clrOrange; }

   lines[n] = "H.I.E.P.  v1.10   " + _Symbol + " " + TFName(Period()); cols[n] = clrAqua; n++;
   lines[n] = "------------------------------"; cols[n] = C'70,80,95'; n++;
   lines[n] = StringFormat("STRUCTURE   %s", bias); cols[n] = biasC; n++;
   lines[n] = StringFormat("HTF BIAS    %s", htfTxt);
   cols[n] = (htf > 0 ? clrLime : (htf < 0 ? clrTomato : clrSilver)); n++;
   lines[n] = StringFormat("SESSION     %s  %s", SessionName(TimeCurrent()), sessionOn ? "OPEN" : "CLOSED");
   cols[n] = sessionOn ? clrLime : clrGold; n++;
   lines[n] = StringFormat("SPREAD      %.0f pts  %s", sp, spreadOn ? "OK" : "WIDE");
   cols[n] = spreadOn ? clrLime : clrTomato; n++;
   lines[n] = StringFormat("ATR(%d)     %s", InpATRPeriod, DoubleToString(atr, _Digits));
   cols[n] = clrSilver; n++;
   lines[n] = StringFormat("VOLUME      %.2fx avg", vr);
   cols[n] = (vr >= InpVolMult ? clrLime : clrSilver); n++;
   lines[n] = "------------------------------"; cols[n] = C'70,80,95'; n++;
   lines[n] = StringFormat("SIGNALS     %d / %d today", today, InpMaxPerDay);
   cols[n] = (today >= InpMaxPerDay ? clrOrange : clrSilver); n++;
   lines[n] = StringFormat("RISK/TRADE  %.1f%%  (%d losses = 5%%)", InpRiskPercent, lossesToCap);
   cols[n] = clrSilver; n++;

   if(ArraySize(gSignals) > 0)
   {
      SignalInfo sg = gSignals[ArraySize(gSignals) - 1];
      lines[n] = "------------------------------"; cols[n] = C'70,80,95'; n++;
      lines[n] = StringFormat("LAST %s  %s  %.0f", (sg.dir > 0 ? "BUY " : "SELL"),
                              TimeToString(sg.time, TIME_MINUTES), sg.score);
      cols[n] = (sg.dir > 0 ? clrLime : clrTomato); n++;
      lines[n] = StringFormat(" E %s  SL %s", DoubleToString(sg.entry, _Digits),
                              DoubleToString(sg.sl, _Digits));
      cols[n] = clrSilver; n++;
      lines[n] = StringFormat(" TP %s", DoubleToString(sg.tp, _Digits));
      cols[n] = clrSilver; n++;
      lines[n] = StringFormat(" LOT %.2f  (risk %.1f%%)", sg.lot, InpRiskPercent);
      cols[n] = clrSilver; n++;
   }
   else
   {
      lines[n] = "------------------------------"; cols[n] = C'70,80,95'; n++;
      lines[n] = "NO VALID SETUP YET"; cols[n] = clrSilver; n++;
   }

   lines[n] = "------------------------------"; cols[n] = C'70,80,95'; n++;
   lines[n] = StringFormat("PROP GUARD  %s", guard); cols[n] = guardC; n++;
   if(gLastSweepTime > 0)
   {
      lines[n] = StringFormat("LAST SWEEP  %s %s (%d bars ago)",
                              (gLastSweepDir > 0 ? "LOW " : "HIGH"),
                              DoubleToString(gLastSweepLevel, _Digits),
                              BarsAgo(gLastSweepTime, TimeCurrent()));
      cols[n] = (gLastSweepDir > 0 ? clrLime : clrTomato); n++;
   }
   lines[n] = StringFormat("WATCH  %s", LiveWatchText()); cols[n] = clrKhaki; n++;

   int lineH = InpPanelFont + 7;
   for(int i = 0; i < 32; i++)          // clear leftovers from a longer panel
   {
      string nm = PREFIX + "PNL_" + IntegerToString(i);
      EnsureLabel(nm, InpPanelX, InpPanelY + i * lineH, InpPanelFont);
      ObjectSetString(0, nm, OBJPROP_TEXT, (i < n) ? lines[i] : "");
      if(i < n) ObjectSetInteger(0, nm, OBJPROP_COLOR, cols[i]);
   }

   string bg = PREFIX + "PNL_BG";
   if(ObjectFind(0, bg) >= 0)
   {
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, 330);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, n * lineH + 14);
   }
   gDirty = true;
}

//+------------------------------------------------------------------+
//| STANDARD EVENT HANDLERS                                          |
//+------------------------------------------------------------------+
int OnInit()
{
   gSwingN = IMax(2, InpSwingStrength);

   SetIndexBuffer(0, gBuyBuf);
   SetIndexBuffer(1, gSellBuf);

   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 1, InpBuyArrowColor);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 1, InpSellArrowColor);

   SetIndexArrow(0, InpArrowUp);
   SetIndexArrow(1, InpArrowDown);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);

   SetIndexLabel(0, "HIEP Buy");
   SetIndexLabel(1, "HIEP Sell");

   SetIndexDrawBegin(0, 0);
   SetIndexDrawBegin(1, 0);

   IndicatorShortName("H.I.E.P.  Hidden Institutional Entries");

   // parse blackout hours once
   for(int i = 0; i < 24; i++) gBlackout[i] = false;
   if(StringLen(InpBlackoutHours) > 0)
   {
      string parts[];
      int cnt = StringSplit(InpBlackoutHours, ',', parts);
      for(int k = 0; k < cnt; k++)
      {
         int hh = (int)StringToInteger(parts[k]);
         if(hh >= 0 && hh <= 23) gBlackout[hh] = true;
      }
   }

   ArrayResize(gObjNames, 0);
   ArrayResize(gObjTimes, 0);
   gObjCount = 0;

   if(InpHistoryBars < 200)
      Print("HIEP warning: InpHistoryBars is very small, structure quality may suffer.");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   DeleteAllObjects();
   Comment("");
}

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
   if(rates_total < 60) return(0);

   int bars = iBars(_Symbol, _Period);
   bool needRebuild = (prev_calculated == 0 || gLastProcessedTime == 0);

   if(!needRebuild)
   {
      if(bars < gProcessedBars)                       needRebuild = true;
      else if(bars - gProcessedBars > 20)             needRebuild = true;
      else if(iBarShift(_Symbol, _Period, gLastProcessedTime, false) < 0) needRebuild = true;
   }

   if(needRebuild) Rebuild();
   else            Advance();

   UpdatePanel();

   if(gDirty)
   {
      ChartRedraw();
      gDirty = false;
   }
   return(rates_total);
}
//+------------------------------------------------------------------+
