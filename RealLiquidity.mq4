//+------------------------------------------------------------------+
//|                                               RealLiquidity.mq4  |
//|                REAL LIQUIDITY - institutional liquidity mapper    |
//|                                                                  |
//|  Maps the places where resting orders (liquidity) most likely    |
//|  sit, using only chart data that MetaTrader 4 can provide:       |
//|                                                                  |
//|   * Buy-side liquidity  (BSL): stops above swing highs / equal   |
//|     highs.                                                       |
//|   * Sell-side liquidity (SSL): stops below swing lows / equal    |
//|     lows.                                                        |
//|   * Liquidity pools: clusters of 2+ equal highs/lows (a strong   |
//|     magnet, because everybody's stop is in the same place).      |
//|   * Volume-spike areas: bars where volume expanded far above the |
//|     average and the range was meaningful -> institutional        |
//|     participation.                                               |
//|   * Liquidity voids / imbalances: 3-bar gaps left behind by an   |
//|     aggressive move (price often returns to rebalance them).     |
//|   * Liquidity sweeps: a wick through a level followed by a close |
//|     back inside -> stop-run / liquidity grab.                    |
//|                                                                  |
//|  The indicator is object based (no indicator buffers) and never  |
//|  repaints confirmed structure: pivots are only used after their  |
//|  right-hand confirmation bars have closed.                       |
//|                                                                  |
//|  Free to use, modify and redistribute. No warranty.              |
//+------------------------------------------------------------------+
#property copyright   "Arena.ai agent"
#property version     "1.10"
#property description "Maps real liquidity: buy-side / sell-side pools, equal highs and"
#property description "lows, volume-spike institutional areas, liquidity voids and sweeps."
#property description "Entry signals with entry/SL/TP. Object based, non-repainting."
#property strict
#property indicator_chart_window

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_RLQ_VOLSRC
{
   RLQ_VOL_TICK = 0,   // Tick volume (default for FX)
   RLQ_VOL_REAL = 1    // Real / exchange volume (falls back to tick)
};

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string  InpG1              = "=== Detection ===";         // Detection
input int     InpSensitivity     = 5;                            // Sensitivity (1 = strict, 10 = aggressive)
input int     InpLookbackBars    = 600;                          // Lookback bars to scan
input int     InpPivotLeft       = 0;                            // Pivot strength left (0 = auto)
input int     InpPivotRight      = 0;                            // Pivot strength right (0 = auto)
input double  InpEqualTolPips    = 2.0;                          // Equal high/low tolerance (pips)
input double  InpMaxPoolWidthPips= 5.0;                          // Max pool width (pips, 0 = no limit)
input int     InpMinTouches      = 2;                            // Min touches to call it a "pool"
input int     InpMaxPools        = 6;                            // Max liquidity pools drawn
input int     InpMaxSingleLevels = 0;                            // Max single swing levels (0 = off)
input int     InpZonePadBars     = 8;                            // Bars a zone extends past its last touch
input int     InpZoneMaxBars     = 40;                           // Longer zones become lines (bars, 0 = always box)
input int     InpExtendBars      = 24;                           // Projection length for nearest levels (bars)
input bool    InpProjectNearest  = true;                         // Project only the nearest BSL/SSL level
input bool    InpOnlyActivePools = false;                        // Hide already swept pools
input bool    InpShowSweeps      = true;                         // Show sweep arrows
input bool    InpSweepCloseBack  = true;                         // Sweep = wick through + close back

input string  InpG2              = "=== Volume / order flow ==="; // Volume / order flow
input ENUM_RLQ_VOLSRC InpVolumeSource = RLQ_VOL_TICK;            // Volume source
input int     InpVolAvgPeriod    = 20;                           // Volume average period
input double  InpVolSpikeMult    = 1.80;                         // Volume spike multiplier
input int     InpVolMinTicks     = 20;                           // Ignore bars below this volume
input double  InpVolZoneATRMult  = 0.60;                         // Min bar range (x ATR) for a zone
input bool    InpVolZoneUseBody  = false;                        // Use body instead of full bar
input int     InpMaxVolZones     = 4;                            // Max volume zones drawn
input int     InpVolZoneExtend   = 10;                           // Volume zone extension (bars)
input int     InpFlowBars        = 50;                           // Bars used for flow-bias estimate

input string  InpG3              = "=== Liquidity voids ===";    // Liquidity voids
input bool    InpShowVoids       = true;                         // Show voids / imbalances
input double  InpVoidMinATR      = 0.35;                         // Min gap size (x ATR)
input int     InpMaxVoids        = 3;                            // Max voids drawn
input bool    InpHideFilledVoids = true;                         // Hide voids that price already filled
input int     InpVoidExtendBars  = 20;                           // Void box length (bars)

input string  InpG3B             = "=== Entry signals ===";        // Entry signals
input bool    InpShowEntries     = true;                         // Show entry signals
input bool    InpEntrySweep      = true;                         // Sweep-reversal entries
input bool    InpEntryBreakout   = true;                         // Pool-acceptance entries
input int     InpEntryConfirmBars= 1;                            // Bars after sweep to confirm
input double  InpEntrySLBufferATR= 0.25;                         // Stop buffer beyond wick (x ATR)
input double  InpEntryMaxRiskATR = 6.0;                          // Max stop distance (x ATR, 0 = off)
input int     InpEntryTPMode     = 2;                            // Target: 0=pool only 1=fixed RR 2=pool or RR
input double  InpEntryRR         = 2.0;                          // Fixed risk:reward target
input double  InpEntryMinRR      = 1.0;                          // Min RR to accept a pool target
input int     InpEntryMaxSignals = 6;                            // Max entry signals kept
input int     InpEntryLookback   = 300;                          // Only signals within N bars
input int     InpEntryProjectBars= 18;                           // Project entry/SL/TP lines (bars)
input bool    InpEntryShowLevels = true;                         // Draw entry / SL / TP lines
input bool    InpEntryShowZones  = false;                        // Shade risk / reward areas
input bool    InpEntryVolFilter  = false;                        // Require volume expansion
input double  InpEntryVolMult    = 1.20;                         // Volume multiple for entry filter
input color   InpColorBuy        = clrAqua;                      // Buy entry
input color   InpColorSell       = clrMagenta;                   // Sell entry
input color   InpColorSL         = clrRed;                       // Stop-loss line
input color   InpColorTP         = clrMediumSeaGreen;            // Take-profit line

input string  InpG4              = "=== Visuals ===";            // Visuals
input bool    InpShowPanel       = true;                         // Show information panel
input bool    InpShowLegend      = false;                        // Show legend
input bool    InpShowNearest     = false;                        // Highlight nearest liquidity
input int     InpFontSize        = 8;                            // Font size
input bool    InpZoneFill        = false;                        // Shade zones (off = outline only)
input int     InpZoneLabels      = 1;                            // Zone tags: 0=off 1=compact 2=full
input bool    InpSweepLabels     = false;                        // Show "sweep" text (arrow only if off)
input int     InpEntryLevelLines = 2;                            // Recent signals with E/SL/TP lines
input int     InpLabelDensity    = 1;                            // Tag spacing: 1=tight 2=normal 3=airy
input color   InpColorBSL        = clrOrangeRed;                  // Buy-side liquidity
input color   InpColorSSL        = clrDodgerBlue;                 // Sell-side liquidity
input color   InpColorBull       = clrLimeGreen;                  // Bullish volume spike
input color   InpColorBear       = clrRed;                        // Bearish volume spike
input color   InpColorVoid       = clrGold;                       // Liquidity void / imbalance
input color   InpColorSwept      = clrSlateGray;                  // Swept liquidity
input color   InpColorText       = clrSilver;                     // Chart labels
input color   InpColorPanelBg    = clrBlack;                      // Panel background
input color   InpColorPanelBorder= clrDimGray;                    // Panel border
input color   InpColorPanelTx    = clrWhite;                      // Panel text

input string  InpG5              = "=== Alerts ===";             // Alerts
input bool    InpAlertSweep      = true;                          // Alert on liquidity sweep
input bool    InpAlertEntry      = true;                          // Alert on new entry signal
input bool    InpAlertApproach   = false;                         // Alert when price nears liquidity
input double  InpAlertDistPips   = 5.0;                           // Approach distance (pips)
input bool    InpAlertPush       = false;                         // Send push notification
input bool    InpAlertSound      = false;                         // Play sound

//+------------------------------------------------------------------+
//| Constants, structures and globals                                |
//+------------------------------------------------------------------+
#define PFX_OBJ     "RLQO_"      // prefix for chart geometry
#define PFX_PNL     "RLQP_"      // prefix for panel objects
#define PANEL_ROWS  13
#define PANEL_W     292

#define RLQ_BSL     0            // buy-side liquidity (highs)
#define RLQ_SSL     1            // sell-side liquidity (lows)

struct PivotInfo
{
   datetime tm;
   double   price;
   int      kind;                 // RLQ_BSL / RLQ_SSL
   int      bar;                  // series index
};

struct LiqPool
{
   datetime tFirst;               // oldest pivot in the cluster
   datetime tLast;                // newest pivot in the cluster
   datetime tSwept;               // time of the sweep (0 = never)
   double   top;                  // highest pivot of the cluster
   double   bottom;               // lowest pivot of the cluster
   double   level;                // actionable level (top for BSL, bottom for SSL)
   double   sweepPrice;           // extreme of the sweeping bar
   int      sweepBar;             // series index of the sweeping bar (-1 = none)
   int      kind;                 // RLQ_BSL / RLQ_SSL
   int      touches;              // number of pivots in the cluster
   int      lastBar;              // series index of the newest pivot
   bool     swept;
};

struct VolArea
{
   datetime tStart;
   double   top;
   double   bottom;
   double   ratio;                // volume / average
   double   delta;                // signed flow proxy
   int      kind;                 // 0 = bullish, 1 = bearish
   int      bar;
};

struct VoidArea
{
   datetime tStart;
   double   top;
   double   bottom;
   int      kind;                 // 0 = bullish void, 1 = bearish void
   bool     filled;
};

struct EntrySignal
{
   datetime tm;                   // confirmation bar time
   double   entry;                // entry price (close of the signal bar)
   double   sl;                   // stop-loss
   double   tp;                   // take-profit
   double   rr;                   // planned risk:reward
   double   barHigh;              // signal bar range, for arrow placement
   double   barLow;
   int      dir;                  // +1 buy, -1 sell
   int      reason;               // 0 = sweep reversal, 1 = pool acceptance
   int      touches;              // strength of the pool behind the signal
   int      bar;                  // series index of the signal bar
};

PivotInfo g_pivots[];
int       g_pivCount      = 0;
LiqPool   g_pools[];
int       g_poolCount     = 0;
VolArea   g_volAreas[];
int       g_volCount      = 0;
VoidArea  g_voids[];
int       g_voidCount     = 0;
EntrySignal g_entries[];
int       g_entryCount    = 0;

double    g_vol[];                // volume per bar (series aligned)
double    g_volSma[];             // average of the N bars BEFORE the bar
double    g_delta[];              // close-location-value * volume (flow proxy)
double    g_tr[];                 // true range
double    g_atr[];                // ATR per bar
double    g_atrNow        = 0.0;

double    g_pointsPerPip  = 0.0001;
int       g_pivotL        = 2;
int       g_pivotR        = 2;
double    g_tol           = 0.0;  // equal-level tolerance in price
double    g_maxPoolWidth  = 0.0;  // max height of one pool in price
datetime  g_tRight        = 0;    // right edge of drawn zones
datetime  g_tLeft         = 0;

int       g_swingHighs    = 0;
int       g_swingLows     = 0;
int       g_activePools   = 0;
int       g_sweptPools    = 0;

bool      g_hasBSL        = false;
bool      g_hasSSL        = false;
double    g_nearBSL       = 0.0;
double    g_nearSSL       = 0.0;

double    g_biasPct       = 0.0;
double    g_volRatioNow   = 0.0;
string    g_structBias    = "n/a";
string    g_lastEvent     = "none";
string    g_panelRows[PANEL_ROWS];
color     g_panelColors[PANEL_ROWS];
int       g_panelRowCount = 0;
bool      g_ready         = false;

double    g_lblPrices[64];        // prices already carrying a chart tag
int       g_lblCount      = 0;
double    g_lblGap        = 0.0;  // min vertical separation between tags

#define RLQ_MAX_BANDS 32
double    g_bTop[RLQ_MAX_BANDS];  // price bands already covered by a zone
double    g_bBot[RLQ_MAX_BANDS];
datetime  g_bT1[RLQ_MAX_BANDS];
datetime  g_bT2[RLQ_MAX_BANDS];
int       g_bCount        = 0;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_pointsPerPip = PipSize();
   if(g_pointsPerPip <= 0.0) g_pointsPerPip = Point;

   g_pivotL = (InpPivotLeft  > 0) ? InpPivotLeft  : EffPivotStrength();
   g_pivotR = (InpPivotRight > 0) ? InpPivotRight : EffPivotStrength();
   if(g_pivotL < 1) g_pivotL = 1;
   if(g_pivotR < 1) g_pivotR = 1;

   g_tol          = EffTolPips() * g_pointsPerPip;
   g_maxPoolWidth = InpMaxPoolWidthPips * g_pointsPerPip;
   if(g_maxPoolWidth < 0.0) g_maxPoolWidth = 0.0;
   g_ready        = false;

   DeleteAllObjects();
   if(InpShowPanel)  CreatePanelObjects();
   if(InpShowLegend) CreateLegendObjects();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeleteAllObjects();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Main calculation entry point                                     |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &t[],
                const double &o[],
                const double &h[],
                const double &l[],
                const double &c[],
                const long &tv[],
                const long &rv[],
                const int &sp[])
{
   if(rates_total < 100 || ArraySize(c) < 100) return(0);

   static datetime lastBarTime = 0;
   static int      lastRates   = 0;

   bool newBar  = (t[0] != lastBarTime);
   bool rebuild = (prev_calculated == 0 || !g_ready || lastRates != rates_total || newBar);

   if(rebuild)
   {
      Analyze(t, o, h, l, c, tv, rv, rates_total);

      DeleteDrawObjects();
      RenderAll();
      UpdatePanel();
      ChartRedraw();

      CheckAlerts(t);

      lastBarTime = t[0];
      lastRates   = rates_total;
      g_ready     = true;
   }
   else
   {
      UpdatePanel();
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| PIP / parameter helpers                                          |
//+------------------------------------------------------------------+
double PipSize()
{
   int d = (int)Digits;
   if(d == 3 || d == 5) return(Point * 10.0);
   if(d == 2 || d == 1) return(Point * 10.0);
   return(Point);
}

int EffPivotStrength()
{
   int sens = (int)MathMax(1, MathMin(10, InpSensitivity));
   return((int)MathMax(1, MathRound(2.0 + (10 - sens) / 3.0)));
}

double EffTolPips()
{
   double sens = (double)InpSensitivity;
   double f    = 1.0 + (sens - 5.0) * 0.06;
   if(f < 0.3) f = 0.3;
   return(MathMax(0.1, InpEqualTolPips * f));
}

double EffVolumeMult()
{
   double sens = (double)InpSensitivity;
   double f    = 1.0 - (sens - 5.0) * 0.04;
   if(f < 0.6) f = 0.6;
   return(MathMax(1.05, InpVolSpikeMult * f));
}

//+------------------------------------------------------------------+
//| ANALYSIS: volumes                                                |
//+------------------------------------------------------------------+
void BuildVolume(const double &h[], const double &l[], const double &c[],
                 const long &tv[], const long &rv[], int bars)
{
   ArrayResize(g_vol,    bars);
   ArrayResize(g_volSma, bars);
   ArrayResize(g_delta,  bars);

   bool useReal = (InpVolumeSource == RLQ_VOL_REAL);
   if(useReal)
   {
      int got = 0;
      int chk = (int)MathMin(bars, 200);
      for(int k = 0; k < chk; k++) if(rv[k] > 0) got++;
      if(got < 10) useReal = false;   // no real volume on this symbol
   }

   for(int i = 0; i < bars; i++)
   {
      g_vol[i] = (double)(useReal ? rv[i] : tv[i]);

      double rng = h[i] - l[i];
      double clv = (rng > 0.0) ? (c[i] - l[i]) / rng : 0.5;
      if(clv < 0.0) clv = 0.0;
      if(clv > 1.0) clv = 1.0;
      g_delta[i] = (2.0 * clv - 1.0) * g_vol[i];
   }

   // average of the N bars BEFORE bar i (excludes the bar itself)
   double cum[];
   ArrayResize(cum, bars + 1);
   cum[bars] = 0.0;
   for(int i = bars - 1; i >= 0; i--) cum[i] = cum[i + 1] + g_vol[i];

   int per = (int)MathMax(2, InpVolAvgPeriod);
   for(int i = 0; i < bars; i++)
   {
      int a = i + 1;
      int b = i + per;
      if(b > bars - 1) b = bars - 1;
      if(a <= b) g_volSma[i] = (cum[a] - cum[b + 1]) / (double)(b - a + 1);
      else       g_volSma[i] = g_vol[i];
   }
}

//+------------------------------------------------------------------+
//| ANALYSIS: ATR                                                    |
//+------------------------------------------------------------------+
void BuildATR(const double &h[], const double &l[], const double &c[], int bars, int period)
{
   ArrayResize(g_tr,  bars);
   ArrayResize(g_atr, bars);

   for(int i = 0; i < bars; i++)
   {
      double pc  = (i + 1 < bars) ? c[i + 1] : c[i];
      double rng = h[i] - l[i];
      double up  = MathAbs(h[i] - pc);
      double dn  = MathAbs(l[i] - pc);
      g_tr[i] = MathMax(rng, MathMax(up, dn));
   }

   double run = 0.0;
   int    per = (int)MathMax(2, period);
   for(int i = bars - 1; i >= 0; i--)
   {
      run += g_tr[i];
      int out = i + per;
      if(out <= bars - 1) run -= g_tr[out];
      int n = (int)MathMin(per, bars - i);
      g_atr[i] = (n > 0) ? run / (double)n : 0.0;
   }
}

//+------------------------------------------------------------------+
//| ANALYSIS: swing pivots                                           |
//+------------------------------------------------------------------+
void AddPivot(datetime tm, double price, int kind, int bar)
{
   if(g_pivCount >= ArraySize(g_pivots)) return;
   g_pivots[g_pivCount].tm    = tm;
   g_pivots[g_pivCount].price = price;
   g_pivots[g_pivCount].kind  = kind;
   g_pivots[g_pivCount].bar   = bar;
   g_pivCount++;
}

void FindPivots(const datetime &t[], const double &h[], const double &l[], int bars, int scan)
{
   g_pivCount   = 0;
   g_swingHighs = 0;
   g_swingLows  = 0;

   ArrayResize(g_pivots, bars + 8);

   int from = g_pivotR + 1;
   int to   = (int)MathMin(bars - 1 - g_pivotL, scan);
   if(to < from) return;

   int k;
   for(int i = to; i >= from; i--)          // oldest -> newest
   {
      bool isHigh = true;
      bool isLow  = true;

      for(k = 1; k <= g_pivotL; k++)        // older side
      {
         if(h[i] < h[i + k]) isHigh = false;
         if(l[i] > l[i + k]) isLow  = false;
      }
      for(k = 1; k <= g_pivotR; k++)        // newer side
      {
         if(h[i] <= h[i - k]) isHigh = false;
         if(l[i] >= l[i - k]) isLow  = false;
      }

      if(isHigh)
      {
         AddPivot(t[i], h[i], RLQ_BSL, i);
         g_swingHighs++;
      }
      if(isLow)
      {
         AddPivot(t[i], l[i], RLQ_SSL, i);
         g_swingLows++;
      }
   }
}

//+------------------------------------------------------------------+
//| ANALYSIS: cluster pivots into liquidity pools                    |
//+------------------------------------------------------------------+
void BuildPools()
{
   g_poolCount = 0;
   ArrayResize(g_pools, g_pivCount + 8);

   double tol = g_tol;
   if(tol <= 0.0) tol = Point * 2.0;

   for(int i = 0; i < g_pivCount; i++)
   {
      int    kind  = g_pivots[i].kind;
      double price = g_pivots[i].price;

      int    found = -1;
      double best  = tol + 1.0;

      for(int j = 0; j < g_poolCount; j++)
      {
         if(g_pools[j].kind != kind) continue;

         double d = MathAbs(g_pools[j].level - price);
         if(d > tol || d >= best) continue;

         // tolerance chaining guard: never let a cluster drift into a
         // wide band, otherwise unrelated swings become one "pool"
         if(g_maxPoolWidth > 0.0)
         {
            double newTop    = MathMax(g_pools[j].top, price);
            double newBottom = MathMin(g_pools[j].bottom, price);
            if(newTop - newBottom > g_maxPoolWidth) continue;
         }

         best  = d;
         found = j;
      }

      if(found < 0)
      {
         int idx = g_poolCount;
         g_poolCount++;

         g_pools[idx].tFirst     = g_pivots[i].tm;
         g_pools[idx].tLast      = g_pivots[i].tm;
         g_pools[idx].tSwept     = 0;
         g_pools[idx].top        = price;
         g_pools[idx].bottom     = price;
         g_pools[idx].level      = price;
         g_pools[idx].sweepPrice = 0.0;
         g_pools[idx].sweepBar   = -1;
         g_pools[idx].kind       = kind;
         g_pools[idx].touches    = 1;
         g_pools[idx].lastBar    = g_pivots[i].bar;
         g_pools[idx].swept      = false;
      }
      else
      {
         g_pools[found].touches++;

         if(g_pivots[i].tm < g_pools[found].tFirst) g_pools[found].tFirst = g_pivots[i].tm;
         if(g_pivots[i].tm > g_pools[found].tLast)  g_pools[found].tLast  = g_pivots[i].tm;

         if(kind == RLQ_BSL)
         {
            if(price > g_pools[found].level) g_pools[found].level = price;
         }
         else
         {
            if(price < g_pools[found].level) g_pools[found].level = price;
         }

         if(price > g_pools[found].top)    g_pools[found].top    = price;
         if(price < g_pools[found].bottom) g_pools[found].bottom = price;

         if(g_pivots[i].bar < g_pools[found].lastBar)
            g_pools[found].lastBar = g_pivots[i].bar;
      }
   }
}

//+------------------------------------------------------------------+
//| ANALYSIS: rank pools (strongest first, then freshest)            |
//| Rendering is capped, so the most meaningful zones must come first|
//+------------------------------------------------------------------+
void SortPools()
{
   for(int i = 1; i < g_poolCount; i++)
   {
      LiqPool key = g_pools[i];
      int j = i - 1;

      while(j >= 0 && PoolRank(g_pools[j]) < PoolRank(key))
      {
         g_pools[j + 1] = g_pools[j];
         j--;
      }
      g_pools[j + 1] = key;
   }
}

//+------------------------------------------------------------------+
//| Pool importance score                                            |
//+------------------------------------------------------------------+
double PoolRank(LiqPool &p)
{
   double score = (double)p.touches * 100.0;

   if(!p.swept) score += 50.0;                 // active zones matter more
   if(p.lastBar < 200) score += (200 - p.lastBar) * 0.1;  // freshness

   return(score);
}

//+------------------------------------------------------------------+
//| ANALYSIS: detect liquidity sweeps (stop runs)                    |
//+------------------------------------------------------------------+
void DetectSweeps(const datetime &t[], const double &h[], const double &l[], const double &c[])
{
   double eps = Point * 0.5;

   for(int i = 0; i < g_poolCount; i++)
   {
      g_pools[i].swept      = false;
      g_pools[i].tSwept     = 0;
      g_pools[i].sweepPrice = 0.0;
      g_pools[i].sweepBar   = -1;

      int start = g_pools[i].lastBar - g_pivotR;
      if(start < 0) continue;

      double lvl = g_pools[i].level;

      for(int j = start; j >= 0; j--)          // oldest -> newest, first hit wins
      {
         bool hit = false;

         if(g_pools[i].kind == RLQ_BSL)
            hit = (h[j] > lvl + eps) && (!InpSweepCloseBack || c[j] < lvl);
         else
            hit = (l[j] < lvl - eps) && (!InpSweepCloseBack || c[j] > lvl);

         if(hit)
         {
            g_pools[i].swept      = true;
            g_pools[i].tSwept     = t[j];
            g_pools[i].sweepBar   = j;
            g_pools[i].sweepPrice = (g_pools[i].kind == RLQ_BSL) ? h[j] : l[j];
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ANALYSIS: pool statistics                                        |
//+------------------------------------------------------------------+
void CountPools()
{
   g_activePools = 0;
   g_sweptPools  = 0;

   for(int i = 0; i < g_poolCount; i++)
   {
      if(g_pools[i].touches < InpMinTouches) continue;
      if(g_pools[i].swept) g_sweptPools++;
      else                 g_activePools++;
   }
}

//+------------------------------------------------------------------+
//| ANALYSIS: volume-spike (institutional) areas                     |
//+------------------------------------------------------------------+
void FindVolumeAreas(const datetime &t[], const double &o[], const double &h[],
                     const double &l[], const double &c[], int bars, int scan)
{
   int cap = (int)MathMax(2, InpMaxVolZones) + 2;
   ArrayResize(g_volAreas, cap);

   double mult = EffVolumeMult();

   for(int i = 1; i <= scan && g_volCount < cap - 1; i++)
   {
      if(g_vol[i] < (double)InpVolMinTicks) continue;

      double avg = g_volSma[i];
      if(avg <= 0.0) continue;

      double ratio = g_vol[i] / avg;
      if(ratio < mult) continue;

      double rng = h[i] - l[i];
      if(g_atr[i] > 0.0 && rng < g_atr[i] * InpVolZoneATRMult) continue;

      double top    = h[i];
      double bottom = l[i];
      if(InpVolZoneUseBody)
      {
         top    = MathMax(o[i], c[i]);
         bottom = MathMin(o[i], c[i]);
      }
      if(top - bottom < Point * 2.0)
      {
         double mid = (top + bottom) * 0.5;
         top    = mid + Point;
         bottom = mid - Point;
      }

      double clv   = (rng > 0.0) ? (c[i] - l[i]) / rng : 0.5;
      double delta = (2.0 * clv - 1.0) * g_vol[i];

      int k = g_volCount;
      g_volCount++;

      g_volAreas[k].tStart = t[i];
      g_volAreas[k].top    = top;
      g_volAreas[k].bottom = bottom;
      g_volAreas[k].ratio  = ratio;
      g_volAreas[k].delta  = delta;
      g_volAreas[k].kind   = (delta >= 0.0) ? 0 : 1;
      g_volAreas[k].bar    = i;
   }
}

//+------------------------------------------------------------------+
//| ANALYSIS: liquidity voids / 3-bar imbalances                     |
//+------------------------------------------------------------------+
void FindVoids(const datetime &t[], const double &h[], const double &l[],
               const double &c[], int bars, int scan)
{
   int cap = (int)MathMax(2, InpMaxVoids) + 2;
   ArrayResize(g_voids, cap);

   for(int i = 1; i <= scan - 2 && g_voidCount < cap - 1; i++)
   {
      int    older = i + 2;
      double atr   = g_atr[i];
      if(atr <= 0.0) continue;

      // bullish void: gap between the older bar high and the newer bar low
      if(l[i] > h[older])
      {
         double gap = l[i] - h[older];
         if(gap < atr * InpVoidMinATR) continue;

         bool filled = false;
         for(int j = i - 1; j >= 0; j--)
         {
            if(l[j] <= h[older]) { filled = true; break; }
         }

         int k = g_voidCount;
         g_voidCount++;

         g_voids[k].tStart = t[older];
         g_voids[k].top    = l[i];
         g_voids[k].bottom = h[older];
         g_voids[k].kind   = 0;
         g_voids[k].filled = filled;
      }
      // bearish void: gap between the newer bar high and the older bar low
      else if(h[i] < l[older])
      {
         double gap = l[older] - h[i];
         if(gap < atr * InpVoidMinATR) continue;

         bool filled = false;
         for(int j = i - 1; j >= 0; j--)
         {
            if(h[j] >= l[older]) { filled = true; break; }
         }

         int k = g_voidCount;
         g_voidCount++;

         g_voids[k].tStart = t[older];
         g_voids[k].top    = l[older];
         g_voids[k].bottom = h[i];
         g_voids[k].kind   = 1;
         g_voids[k].filled = filled;
      }
   }
}

//+------------------------------------------------------------------+
//| ANALYSIS: flow proxy, market structure                           |
//+------------------------------------------------------------------+
void ComputeStats(int bars)
{
   // --- estimated order-flow bias (delta proxy) ---------------------
   int n = (int)MathMin(InpFlowBars, bars - 2);
   if(n < 1) n = 1;

   double sumDelta = 0.0;
   double sumVol   = 0.0;
   for(int i = 1; i <= n; i++)
   {
      sumDelta += g_delta[i];
      sumVol   += g_vol[i];
   }
   g_biasPct = (sumVol > 0.0) ? (sumDelta / sumVol) * 100.0 : 0.0;
   if(g_biasPct >  100.0) g_biasPct =  100.0;
   if(g_biasPct < -100.0) g_biasPct = -100.0;

   // --- current volume expansion ------------------------------------
   g_volRatioNow = 0.0;
   if(ArraySize(g_volSma) > 2 && g_volSma[1] > 0.0)
      g_volRatioNow = g_vol[1] / g_volSma[1];

   // --- market structure from the last two pivots of each kind ------
   double hi1 = 0.0, hi2 = 0.0, lo1 = 0.0, lo2 = 0.0;
   int    hc = 0, lc = 0;

   for(int i = g_pivCount - 1; i >= 0; i--)
   {
      if(g_pivots[i].kind == RLQ_BSL && hc < 2)
      {
         if(hc == 0) hi1 = g_pivots[i].price;
         else        hi2 = g_pivots[i].price;
         hc++;
      }
      if(g_pivots[i].kind == RLQ_SSL && lc < 2)
      {
         if(lc == 0) lo1 = g_pivots[i].price;
         else        lo2 = g_pivots[i].price;
         lc++;
      }
      if(hc >= 2 && lc >= 2) break;
   }

   if(hc >= 2 && lc >= 2)
   {
      bool hh = (hi1 > hi2);
      bool hl = (lo1 > lo2);

      if(hh && hl)        g_structBias = "HH / HL (up)";
      else if(!hh && !hl) g_structBias = "LH / LL (down)";
      else if(hh && !hl)  g_structBias = "HH / LL (expansion)";
      else                g_structBias = "LH / HL (contraction)";
   }
   else g_structBias = "n/a";
}

//+------------------------------------------------------------------+
//| ANALYSIS: nearest resting liquidity                              |
//+------------------------------------------------------------------+
void FindNearest(double price)
{
   g_hasBSL  = false;
   g_hasSSL  = false;
   g_nearBSL = 0.0;
   g_nearSSL = 0.0;

   double up = 0.0;
   double dn = 0.0;

   for(int i = 0; i < g_poolCount; i++)
   {
      if(g_pools[i].swept) continue;

      double lvl = g_pools[i].level;

      if(lvl > price + Point * 0.5)
      {
         if(up == 0.0 || lvl < up) up = lvl;
      }
      else if(lvl < price - Point * 0.5)
      {
         if(dn == 0.0 || lvl > dn) dn = lvl;
      }
   }

   if(up > 0.0) { g_hasBSL = true; g_nearBSL = up; }
   if(dn > 0.0) { g_hasSSL = true; g_nearSSL = dn; }
}

//+------------------------------------------------------------------+
//| ANALYSIS: latest structural event                                |
//+------------------------------------------------------------------+
void SetLastEvent()
{
   datetime newest = 0;
   int      idx    = -1;

   for(int i = 0; i < g_poolCount; i++)
   {
      if(!g_pools[i].swept) continue;
      if(g_pools[i].touches < InpMinTouches) continue;
      if(g_pools[i].tSwept > newest)
      {
         newest = g_pools[i].tSwept;
         idx    = i;
      }
   }

   if(idx >= 0)
   {
      string side = (g_pools[idx].kind == RLQ_BSL) ? "BSL" : "SSL";
      g_lastEvent = "Swept " + side + " @ " + DoubleToString(g_pools[idx].sweepPrice, (int)Digits);
   }
   else if(g_volCount > 0)
   {
      g_lastEvent = "Vol spike " + DoubleToString(g_volAreas[0].ratio, 1) + "x";
   }
   else g_lastEvent = "none";
}

//+------------------------------------------------------------------+
//| ENTRY SIGNALS                                                    |
//|                                                                  |
//|  Two entry models, both confirmed on closed bars only:            |
//|                                                                  |
//|   A) Sweep reversal - a pool is swept (wick through, close back) |
//|      and the next bar closes beyond the sweeping bar's opposite   |
//|      extreme. Stops go beyond the wick that created the sweep.    |
//|                                                                  |
//|   B) Pool acceptance - price closes beyond a pool level for two   |
//|      consecutive bars (no close back inside). Stops go beyond the  |
//|      opposite edge of the pool.                                    |
//|                                                                  |
//|  Take profit is either the next liquidity pool in the direction   |
//|  of the trade, a fixed risk:reward, or whichever is valid first.  |
//+------------------------------------------------------------------+
double VolRatioAt(int bar)
{
   if(bar < 1 || bar >= ArraySize(g_volSma)) return(0.0);
   if(g_volSma[bar] <= 0.0) return(0.0);
   return(g_vol[bar] / g_volSma[bar]);
}

//+------------------------------------------------------------------+
//| Nearest active pool of a given kind beyond a reference price     |
//+------------------------------------------------------------------+
double TargetLevel(int kind, double price)
{
   double best = 0.0;

   for(int i = 0; i < g_poolCount; i++)
   {
      if(g_pools[i].kind != kind) continue;
      if(g_pools[i].swept) continue;
      if(g_pools[i].touches < InpMinTouches) continue;

      double lvl = g_pools[i].level;

      if(kind == RLQ_BSL)
      {
         if(lvl > price + Point * 0.5)
            if(best == 0.0 || lvl < best) best = lvl;
      }
      else
      {
         if(lvl < price - Point * 0.5)
            if(best == 0.0 || lvl > best) best = lvl;
      }
   }

   return(best);
}

//+------------------------------------------------------------------+
//| Take profit: pool target, fixed RR, or pool-if-RR-ok             |
//+------------------------------------------------------------------+
double ResolveTP(int dir, double entry, double risk)
{
   if(risk <= 0.0) return(0.0);

   double rr   = MathMax(0.5, InpEntryRR);
   double rrTp = entry + dir * risk * rr;

   if(InpEntryTPMode == 1) return(rrTp);

   double poolTp = TargetLevel((dir > 0) ? RLQ_BSL : RLQ_SSL, entry);

   if(poolTp > 0.0)
   {
      double poolRR = MathAbs(poolTp - entry) / risk;
      if(poolRR >= InpEntryMinRR) return(poolTp);
      if(InpEntryTPMode == 2)     return(rrTp);
      return(0.0);                       // mode 0: pool must be valid
   }

   if(InpEntryTPMode == 0) return(0.0);
   return(rrTp);
}

//+------------------------------------------------------------------+
//| Store a validated entry signal                                   |
//+------------------------------------------------------------------+
void AddEntry(datetime tm, int bar, double entry, double sl, double tp,
              int dir, int reason, int touches, double barHigh, double barLow)
{
   if(g_entryCount >= ArraySize(g_entries)) return;

   // geometry must make sense for the direction
   if(dir > 0 && !(sl < entry && entry < tp)) return;
   if(dir < 0 && !(tp < entry && entry < sl)) return;

   double risk   = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   if(risk <= 0.0 || reward <= 0.0) return;

   // a stop wider than InpEntryMaxRiskATR is not a tradeable setup: it means
   // the swept wick was an outlier. Skipping these keeps both quality and the
   // chart readable (otherwise SL/TP lines span half the screen).
   if(InpEntryMaxRiskATR > 0.0 && g_atrNow > 0.0)
      if(risk > g_atrNow * InpEntryMaxRiskATR) return;

   int k = g_entryCount;
   g_entryCount++;

   g_entries[k].tm       = tm;
   g_entries[k].entry    = entry;
   g_entries[k].sl       = sl;
   g_entries[k].tp       = tp;
   g_entries[k].rr       = reward / risk;
   g_entries[k].barHigh  = barHigh;
   g_entries[k].barLow   = barLow;
   g_entries[k].dir      = dir;
   g_entries[k].reason   = reason;
   g_entries[k].touches  = touches;
   g_entries[k].bar      = bar;
}

//+------------------------------------------------------------------+
//| Keep the strongest signal per bar, newest first, capped           |
//+------------------------------------------------------------------+
double EntryScore(EntrySignal &e)
{
   double score = (double)e.touches * 10.0 + MathMin(e.rr, 5.0);
   if(e.reason == 0) score += 5.0;       // sweep reversals are the primary model
   return(score);
}

void FilterAndSortEntries()
{
   // insertion sort: newest first, stronger signal wins a tie
   for(int i = 1; i < g_entryCount; i++)
   {
      EntrySignal key = g_entries[i];
      int j = i - 1;

      while(j >= 0)
      {
         bool swap = false;

         if(g_entries[j].tm < key.tm)                 swap = true;
         else if(g_entries[j].tm == key.tm &&
                 EntryScore(g_entries[j]) < EntryScore(key)) swap = true;

         if(!swap) break;

         g_entries[j + 1] = g_entries[j];
         j--;
      }
      g_entries[j + 1] = key;
   }

   // keep one signal per bar, drop stale ones, respect the cap
   EntrySignal kept[];
   ArrayResize(kept, g_entryCount + 2);
   int n = 0;

   for(int i = 0; i < g_entryCount; i++)
   {
      if(g_entries[i].bar > InpEntryLookback) continue;
      if(n > 0 && kept[n - 1].tm == g_entries[i].tm) continue;

      if(n >= (int)MathMax(1, InpEntryMaxSignals)) break;

      kept[n] = g_entries[i];
      n++;
   }

   for(int i = 0; i < n; i++) g_entries[i] = kept[i];
   g_entryCount = n;
}

//+------------------------------------------------------------------+
//| Detect entry signals                                             |
//+------------------------------------------------------------------+
bool EntryFilterPass(int bar)
{
   if(!InpEntryVolFilter) return(true);
   return(VolRatioAt(bar) >= InpEntryVolMult);
}

void DetectEntries(const datetime &t[], const double &o[], const double &h[],
                   const double &l[], const double &c[])
{
   g_entryCount = 0;
   if(!InpShowEntries || g_poolCount <= 0) return;

   ArrayResize(g_entries, g_poolCount * 2 + 4);

   double buf = MathMax(InpEntrySLBufferATR * g_atrNow, Point * 20.0);

   for(int i = 0; i < g_poolCount; i++)
   {
      if(g_pools[i].touches < InpMinTouches) continue;

      // ---------------- A) sweep reversal ----------------
      if(InpEntrySweep && g_pools[i].swept && g_pools[i].sweepBar >= 2)
      {
         int j = g_pools[i].sweepBar;
         int k = j - (int)MathMax(1, InpEntryConfirmBars);
         if(k < 1) continue;

         int dir = 0;

         // swept highs -> short, swept lows -> long
         if(g_pools[i].kind == RLQ_BSL && c[k] < l[j]) dir = -1;
         if(g_pools[i].kind == RLQ_SSL && c[k] > h[j]) dir = +1;

         if(dir != 0 && EntryFilterPass(j) && EntryFilterPass(k))
         {
            double entry = c[k];
            double sl    = (dir < 0) ? (h[j] + buf) : (l[j] - buf);
            double tp    = ResolveTP(dir, entry, MathAbs(entry - sl));

            AddEntry(t[k], k, entry, sl, tp, dir, 0, g_pools[i].touches, h[k], l[k]);
         }
      }

      // ---------------- B) pool acceptance ----------------
      if(InpEntryBreakout && !g_pools[i].swept)
      {
         int start = g_pools[i].lastBar - g_pivotR;
         if(start < 3) continue;

         int brk = -1;
         for(int j = start; j >= 1; j--)
         {
            if(g_pools[i].kind == RLQ_BSL)
            {
               if(c[j] > g_pools[i].level) { brk = j; break; }
            }
            else
            {
               if(c[j] < g_pools[i].level) { brk = j; break; }
            }
         }

         if(brk < 2) continue;

         // acceptance needs the newest bar of the run to close beyond too
         bool accepted = false;
         if(g_pools[i].kind == RLQ_BSL) accepted = (c[brk - 1] > g_pools[i].level);
         else                          accepted = (c[brk - 1] < g_pools[i].level);
         if(!accepted) continue;

         int kb = brk - 1;
         if(!EntryFilterPass(kb)) continue;

         int    dir   = (g_pools[i].kind == RLQ_BSL) ? +1 : -1;
         double entry = c[kb];
         double sl    = (dir > 0) ? (g_pools[i].bottom - buf)
                                  : (g_pools[i].top + buf);
         double tp    = ResolveTP(dir, entry, MathAbs(entry - sl));

         AddEntry(t[kb], kb, entry, sl, tp, dir, 1, g_pools[i].touches, h[kb], l[kb]);
      }
   }

   FilterAndSortEntries();
}

//+------------------------------------------------------------------+
//| ANALYSIS: master routine                                         |
//+------------------------------------------------------------------+
void Analyze(const datetime &t[], const double &o[], const double &h[], const double &l[],
             const double &c[], const long &tv[], const long &rv[], int bars)
{
   g_ready = false;

   g_pivCount   = 0;
   g_poolCount  = 0;
   g_volCount   = 0;
   g_voidCount  = 0;
   g_entryCount = 0;

   int scan = (int)MathMin(bars - g_pivotL - 2, InpLookbackBars);
   if(scan < 30) scan = (int)MathMin(bars - 2, 30);
   if(scan < 10) return;

   g_tol = EffTolPips() * g_pointsPerPip;
   if(g_tol <= 0.0) g_tol = Point * 2.0;

   g_maxPoolWidth = InpMaxPoolWidthPips * g_pointsPerPip;
   if(g_maxPoolWidth < 0.0) g_maxPoolWidth = 0.0;

   g_tRight = t[0] + (datetime)(PeriodSeconds() * (int)MathMax(2, InpExtendBars));
   g_tLeft  = t[(int)MathMin(scan, bars - 1)];

   BuildVolume(h, l, c, tv, rv, bars);
   BuildATR(h, l, c, bars, 14);

   g_atrNow = g_atr[0];
   if(g_atrNow <= 0.0) g_atrNow = h[0] - l[0];

   FindPivots(t, h, l, bars, scan);
   BuildPools();
   DetectSweeps(t, h, l, c);
   SortPools();
   CountPools();
   FindVolumeAreas(t, o, h, l, c, bars, scan);
   FindVoids(t, h, l, c, bars, scan);
   ComputeStats(bars);
   FindNearest(c[0]);
   SetLastEvent();
   DetectEntries(t, o, h, l, c);
}

//+------------------------------------------------------------------+
//| DRAWING: low level object helpers                                |
//+------------------------------------------------------------------+
void DrawRect(string nm, datetime t1, double p1, datetime t2, double p2,
              color clr, bool filled, int style, int width, bool back)
{
   if(t1 > t2) { datetime tt = t1; t1 = t2; t2 = tt; }
   if(p1 > p2) { double pp = p1; p1 = p2; p2 = pp; }

   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2)) return;
   }
   else
   {
      ObjectMove(0, nm, 0, t1, p1);
      ObjectMove(0, nm, 1, t2, p2);
   }

   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, nm, OBJPROP_FILL,       filled);
   ObjectSetInteger(0, nm, OBJPROP_BACK,       back);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
}

void DrawLine(string nm, datetime t1, double p1, datetime t2, double p2,
              color clr, int style, int width, bool ray)
{
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_TREND, 0, t1, p1, t2, p2)) return;
   }
   else
   {
      ObjectMove(0, nm, 0, t1, p1);
      ObjectMove(0, nm, 1, t2, p2);
   }

   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,      width);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT,  ray);
   ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
}

void DrawText(string nm, datetime tm, double price, string txt, color clr,
              int fontsize, int anchor)
{
   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, OBJ_TEXT, 0, tm, price)) return;
   }
   else ObjectMove(0, nm, 0, tm, price);

   ObjectSetString(0, nm, OBJPROP_TEXT,     txt);
   ObjectSetString(0, nm, OBJPROP_FONT,     "Arial");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, fontsize);
   ObjectSetInteger(0, nm, OBJPROP_COLOR,    clr);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR,   anchor);
   ObjectSetInteger(0, nm, OBJPROP_BACK,     false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
}

void DrawArrow(string nm, datetime tm, double price, bool up, color clr)
{
   ENUM_OBJECT type = up ? OBJ_ARROW_UP : OBJ_ARROW_DOWN;

   if(ObjectFind(0, nm) < 0)
   {
      if(!ObjectCreate(0, nm, type, 0, tm, price)) return;
   }
   else if((int)ObjectGetInteger(0, nm, OBJPROP_TYPE) != type)
   {
      ObjectDelete(0, nm);
      if(!ObjectCreate(0, nm, type, 0, tm, price)) return;
   }
   else ObjectMove(0, nm, 0, tm, price);

   ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, nm, OBJPROP_BACK,       false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTED,   false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| LABEL PLACEMENT                                                  |
//|                                                                  |
//|  Tags are the main source of visual clutter, so every tag has to  |
//|  pass a vertical-spacing test first. Without this, six pools in    |
//|  the same price area print six overlapping strings.               |
//+------------------------------------------------------------------+
void ResetLabelSlots()
{
   g_lblCount = 0;

   double base = MathMax(g_atrNow, Point * 10);
   int    dens = (int)MathMax(1, MathMin(3, InpLabelDensity));

   if(dens == 1)      g_lblGap = base * 1.1;
   else if(dens == 2) g_lblGap = base * 1.8;
   else               g_lblGap = base * 2.8;

   if(g_lblGap < Point * 12) g_lblGap = Point * 12;
}

bool LabelFits(double price, double extra)
{
   for(int i = 0; i < g_lblCount; i++)
      if(MathAbs(g_lblPrices[i] - price) < g_lblGap + extra) return(false);
   return(true);
}

void RegisterLabel(double price)
{
   if(g_lblCount >= 64) return;
   g_lblPrices[g_lblCount] = price;
   g_lblCount++;
}

//+------------------------------------------------------------------+
//| Local right edge of a zone: a few bars past the last touch, so    |
//| zones stay next to the structure that created them instead of     |
//| stretching across the whole chart.                                |
//+------------------------------------------------------------------+
datetime ZoneEnd(datetime tLast, int padBars)
{
   int pad = (int)MathMax(1, padBars);
   return(tLast + (datetime)(PeriodSeconds() * pad));
}

//+------------------------------------------------------------------+
//| ZONE OVERLAP GUARD                                               |
//|                                                                  |
//|  Price often leaves several voids and volume zones in the same    |
//|  area. Drawing all of them produces a stack of rectangles that    |
//|  hides the candles, so every zone must claim empty space first.   |
//+------------------------------------------------------------------+
void ResetBands()
{
   g_bCount = 0;
}

bool BandFree(double top, double bottom, datetime t1, datetime t2)
{
   double h = top - bottom;
   if(h <= 0.0) return(false);

   // a margin keeps neighbouring zones from stacking into a ladder of boxes
   double margin = MathMax(g_atrNow * 0.45, Point * 15);
   top    += margin;
   bottom -= margin;

   for(int i = 0; i < g_bCount; i++)
   {
      if(t2 < g_bT1[i] || t1 > g_bT2[i]) continue;       // different time

      double bh = g_bTop[i] - g_bBot[i];
      double ov = MathMin(top, g_bTop[i]) - MathMax(bottom, g_bBot[i]);
      if(ov <= 0.0) continue;

      double denom = MathMin(h, bh);
      if(denom > 0.0 && ov / denom > 0.55) return(false);  // too much shared area
   }

   return(true);
}

void RegisterBand(double top, double bottom, datetime t1, datetime t2)
{
   if(g_bCount >= RLQ_MAX_BANDS) return;
   g_bTop[g_bCount] = top;
   g_bBot[g_bCount] = bottom;
   g_bT1[g_bCount]  = t1;
   g_bT2[g_bCount]  = t2;
   g_bCount++;
}

//+------------------------------------------------------------------+
//| Compact tag text                                                 |
//+------------------------------------------------------------------+
string PoolTag(int kind, int touches, bool swept)
{
   string side = (kind == RLQ_BSL) ? "BSL" : "SSL";

   if(touches >= 2) side = side + IntegerToString(touches);
   if(swept)        side = side + "-";

   if(InpZoneLabels == 2)
   {
      side = (kind == RLQ_BSL) ? "Buy-side" : "Sell-side";
      side = side + " x" + IntegerToString(touches);
      if(swept) side = side + " (swept)";
   }

   return(side);
}

//+------------------------------------------------------------------+
//| DRAWING: liquidity pools and sweeps                              |
//+------------------------------------------------------------------+
void RenderLiquidity()
{
   double tol      = g_tol;
   int    poolsOut = 0;
   int    singles  = 0;

   for(int i = 0; i < g_poolCount; i++)
   {
      bool isPool = (g_pools[i].touches >= InpMinTouches);
      bool swept  = g_pools[i].swept;

      if(InpOnlyActivePools && swept) continue;

      if(isPool)
      {
         if(poolsOut >= InpMaxPools) continue;
      }
      else
      {
         if(singles >= InpMaxSingleLevels) continue;
      }

      color col = (g_pools[i].kind == RLQ_BSL) ? InpColorBSL : InpColorSSL;
      if(swept) col = InpColorSwept;

      double top    = g_pools[i].top + tol * 0.25;
      double bottom = g_pools[i].bottom - tol * 0.25;

      if(top - bottom < Point * 4.0)
      {
         double mid = (top + bottom) * 0.5;
         top    = mid + Point * 2.0;
         bottom = mid - Point * 2.0;
      }

      // the zone stays local to the structure that formed it
      datetime t1 = g_pools[i].tFirst;
      datetime t2 = ZoneEnd(g_pools[i].tLast, InpZonePadBars);
      if(t2 <= t1) t2 = t1 + (datetime)(PeriodSeconds() * 2);

      // only the nearest level is projected to the live edge
      bool isNear = false;
      if(InpProjectNearest && !swept && isPool)
      {
         if(g_pools[i].kind == RLQ_BSL && g_hasBSL && MathAbs(g_pools[i].level - g_nearBSL) < Point * 0.5)
            isNear = true;
         if(g_pools[i].kind == RLQ_SSL && g_hasSSL && MathAbs(g_pools[i].level - g_nearSSL) < Point * 0.5)
            isNear = true;
      }

      int style = swept ? STYLE_DOT : STYLE_SOLID;

      // ---- zone: outline by default, shading only when asked for ----
      // swept zones are history: the arrow marks them, a box would just add
      // another rectangle to an already busy chart. Wide pools become plain
      // level lines so one old cluster cannot span the whole screen.
      int spanBars = (int)((t2 - t1) / (datetime)PeriodSeconds());
      bool boxed   = (InpZoneMaxBars <= 0) || (spanBars <= InpZoneMaxBars);

      if(isPool && !swept && boxed)
      {
         string boxName = PFX_OBJ + "POOL_" + IntegerToString(i);
         DrawRect(boxName, t1, top, t2, bottom, col, InpZoneFill, style, 1, true);
      }

      // ---- level line --------------------------------------------
      string lineName = PFX_OBJ + "LVL_" + IntegerToString(i);
      int      width  = isPool ? (swept ? 1 : 2) : 1;
      datetime lineT1 = boxed ? t1 : g_pools[i].tLast;
      DrawLine(lineName, lineT1, g_pools[i].level, t2, g_pools[i].level,
               col, isPool ? style : STYLE_DOT, width, false);

      if(isNear && g_tRight > t2)
      {
         string projName = PFX_OBJ + "PRJ_" + IntegerToString(i);
         DrawLine(projName, t2, g_pools[i].level, g_tRight, g_pools[i].level,
                  col, STYLE_DOT, 1, false);
      }

      // ---- tag, at the start of the zone, if there is room --------
      if(InpZoneLabels > 0 && isPool && !swept && LabelFits(top, 0.0))
      {
         string labelName = PFX_OBJ + "PLBL_" + IntegerToString(i);
         DrawText(labelName, t1, top,
                  PoolTag(g_pools[i].kind, g_pools[i].touches, swept),
                  col, (int)MathMax(6, InpFontSize - 1), ANCHOR_LEFT_LOWER);
         RegisterLabel(top);
      }

      // ---- sweep marker ------------------------------------------
      if(swept && InpShowSweeps && g_pools[i].tSwept > 0)
      {
         bool   up  = (g_pools[i].kind == RLQ_SSL);       // SSL sweep -> up arrow
         double off = MathMax(g_atrNow * 0.35, Point * 8.0);
         double py  = up ? (g_pools[i].sweepPrice - off) : (g_pools[i].sweepPrice + off);

         string arrowName = PFX_OBJ + "SWA_" + IntegerToString(i);
         DrawArrow(arrowName, g_pools[i].tSwept, py, up, col);

         if(InpSweepLabels)
         {
            string sweepLabel = PFX_OBJ + "SWL_" + IntegerToString(i);
            DrawText(sweepLabel, g_pools[i].tSwept, py, "sweep", col,
                     (int)MathMax(6, InpFontSize - 1),
                     up ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
         }
      }

      if(isPool) poolsOut++;
      else       singles++;
   }
}

//+------------------------------------------------------------------+
//| DRAWING: volume spike areas                                      |
//+------------------------------------------------------------------+
void RenderVolumeAreas()
{
   // newest first: fresh institutional areas matter more than historical ones
   for(int i = g_volCount - 1; i >= 0; i--)
   {
      color col = (g_volAreas[i].kind == 0) ? InpColorBull : InpColorBear;

      datetime t1 = g_volAreas[i].tStart;
      datetime t2 = t1 + (datetime)(PeriodSeconds() * (int)MathMax(2, InpVolZoneExtend));

      if(!BandFree(g_volAreas[i].top, g_volAreas[i].bottom, t1, t2)) continue;
      RegisterBand(g_volAreas[i].top, g_volAreas[i].bottom, t1, t2);

      string boxName = PFX_OBJ + "VOL_" + IntegerToString(i);
      DrawRect(boxName, t1, g_volAreas[i].top, t2, g_volAreas[i].bottom,
               col, InpZoneFill, STYLE_DOT, 1, true);

      if(InpZoneLabels > 0 && LabelFits(g_volAreas[i].top, 0.0))
      {
         string labelName = PFX_OBJ + "VOLT_" + IntegerToString(i);
         string txt = DoubleToString(g_volAreas[i].ratio, 1) + "x";

         if(InpZoneLabels == 2)
            txt = txt + " volume";
         else
            txt = txt + "v";

         DrawText(labelName, t1, g_volAreas[i].top, txt, col,
                  (int)MathMax(6, InpFontSize - 1), ANCHOR_LEFT_LOWER);
         RegisterLabel(g_volAreas[i].top);
      }
   }
}

//+------------------------------------------------------------------+
//| DRAWING: liquidity voids                                         |
//+------------------------------------------------------------------+
void RenderVoids()
{
   if(!InpShowVoids) return;

   // newest first, so the freshest imbalance wins the space
   for(int i = g_voidCount - 1; i >= 0; i--)
   {
      if(InpHideFilledVoids && g_voids[i].filled) continue;

      datetime t1 = g_voids[i].tStart;
      datetime t2 = ZoneEnd(g_voids[i].tStart, InpVoidExtendBars);

      if(!BandFree(g_voids[i].top, g_voids[i].bottom, t1, t2)) continue;
      RegisterBand(g_voids[i].top, g_voids[i].bottom, t1, t2);

      string boxName = PFX_OBJ + "VOID_" + IntegerToString(i);
      DrawRect(boxName, t1, g_voids[i].top, t2, g_voids[i].bottom,
               InpColorVoid, InpZoneFill, STYLE_DASHDOT, 1, true);

      if(InpZoneLabels == 2 && LabelFits(g_voids[i].top, 0.0))
      {
         string labelName = PFX_OBJ + "VOIDT_" + IntegerToString(i);
         string txt = (g_voids[i].kind == 0) ? "void up" : "void dn";
         DrawText(labelName, t1, g_voids[i].top, txt, InpColorVoid,
                  (int)MathMax(6, InpFontSize - 1), ANCHOR_LEFT_LOWER);
         RegisterLabel(g_voids[i].top);
      }
   }
}

//+------------------------------------------------------------------+
//| DRAWING: nearest liquidity markers                               |
//+------------------------------------------------------------------+
void RenderNearest()
{
   if(!InpShowNearest) return;

   double price = c0_safe();

   if(g_hasBSL)
   {
      string nm = PFX_OBJ + "NEAR_BSL";
      if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_HLINE, 0, 0, g_nearBSL);
      ObjectMove(0, nm, 0, 0, g_nearBSL);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      InpColorBSL);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);

      string lb = PFX_OBJ + "NEAR_BSLT";
      string txt = "BSL " + DoubleToString(g_nearBSL, (int)Digits) + "  (+" +
                   DoubleToString((g_nearBSL - price) / g_pointsPerPip, 1) + "p)";
      DrawText(lb, Time[0], g_nearBSL, txt, InpColorBSL, InpFontSize, ANCHOR_LEFT_LOWER);
   }

   if(g_hasSSL)
   {
      string nm = PFX_OBJ + "NEAR_SSL";
      if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_HLINE, 0, 0, g_nearSSL);
      ObjectMove(0, nm, 0, 0, g_nearSSL);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      InpColorSSL);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_DOT);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);

      string lb = PFX_OBJ + "NEAR_SSLT";
      string txt = "SSL " + DoubleToString(g_nearSSL, (int)Digits) + "  (" +
                   DoubleToString((g_nearSSL - price) / g_pointsPerPip, 1) + "p)";
      DrawText(lb, Time[0], g_nearSSL, txt, InpColorSSL, InpFontSize, ANCHOR_LEFT_UPPER);
   }
}

//+------------------------------------------------------------------+
//| DRAWING: entry signals with entry / SL / TP                      |
//+------------------------------------------------------------------+
void RenderEntries()
{
   if(!InpShowEntries || g_entryCount <= 0) return;

   double off      = MathMax(g_atrNow * 0.7, Point * 40.0);
   int    withLvl  = (int)MathMax(0, InpEntryLevelLines);

   for(int i = 0; i < g_entryCount; i++)
   {
      int    dir  = g_entries[i].dir;
      bool   buy  = (dir > 0);
      color  col  = buy ? InpColorBuy : InpColorSell;
      double py   = buy ? (g_entries[i].barLow  - off)
                        : (g_entries[i].barHigh + off);

      // ---- arrow ------------------------------------------------
      string arrowName = PFX_OBJ + "ENTA_" + IntegerToString(i);
      DrawArrow(arrowName, g_entries[i].tm, py, buy, col);

      // ---- compact signal tag ------------------------------------
      string why = "a";
      if(g_entries[i].reason == 0) why = "s";

      string txt = "SELL-" + why + " " + DoubleToString(g_entries[i].rr, 1) + "R";
      if(buy) txt = "BUY-" + why + " " + DoubleToString(g_entries[i].rr, 1) + "R";

      if(LabelFits(py, 0.0))
      {
         string labelName = PFX_OBJ + "ENTT_" + IntegerToString(i);
         DrawText(labelName, g_entries[i].tm, py, txt, col,
                  (int)MathMax(6, InpFontSize - 1),
                  buy ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
         RegisterLabel(py);
      }

      // ---- entry / stop / target, only for the newest signals -----
      if(!InpEntryShowLevels || i >= withLvl) continue;

      datetime t2 = g_entries[i].tm +
                    (datetime)(PeriodSeconds() * (int)MathMax(2, InpEntryProjectBars));

      string eName = PFX_OBJ + "ENTL_" + IntegerToString(i);
      DrawLine(eName, g_entries[i].tm, g_entries[i].entry, t2, g_entries[i].entry,
               col, STYLE_SOLID, 1, false);

      // a level line is only drawn together with its tag: an unlabelled
      // fragment looks like a stray mark on the chart
      bool slFits = LabelFits(g_entries[i].sl, 0.0);
      if(slFits)
      {
         string sName = PFX_OBJ + "ENTSL_" + IntegerToString(i);
         DrawLine(sName, g_entries[i].tm, g_entries[i].sl, t2, g_entries[i].sl,
                  InpColorSL, STYLE_DOT, 1, false);

         string sTxt = PFX_OBJ + "ENTSLT_" + IntegerToString(i);
         DrawText(sTxt, t2, g_entries[i].sl, "SL", InpColorSL,
                  (int)MathMax(6, InpFontSize - 2), ANCHOR_LEFT_UPPER);
         RegisterLabel(g_entries[i].sl);
      }

      bool tpFits = LabelFits(g_entries[i].tp, 0.0);
      if(tpFits)
      {
         string pName = PFX_OBJ + "ENTTP_" + IntegerToString(i);
         DrawLine(pName, g_entries[i].tm, g_entries[i].tp, t2, g_entries[i].tp,
                  InpColorTP, STYLE_DOT, 1, false);

         string pTxt = PFX_OBJ + "ENTTPT_" + IntegerToString(i);
         DrawText(pTxt, t2, g_entries[i].tp, "TP", InpColorTP,
                  (int)MathMax(6, InpFontSize - 2), ANCHOR_LEFT_LOWER);
         RegisterLabel(g_entries[i].tp);
      }

      // ---- risk / reward shading ---------------------------------
      if(InpEntryShowZones)
      {
         string rName = PFX_OBJ + "ENTRZ_" + IntegerToString(i);
         DrawRect(rName, g_entries[i].tm, g_entries[i].entry, t2, g_entries[i].sl,
                  InpColorSL, false, STYLE_DOT, 1, true);

         string wName = PFX_OBJ + "ENTWZ_" + IntegerToString(i);
         DrawRect(wName, g_entries[i].tm, g_entries[i].entry, t2, g_entries[i].tp,
                  InpColorTP, false, STYLE_DOT, 1, true);
      }
   }
}

//+------------------------------------------------------------------+
//| DRAWING: entry point                                             |
//+------------------------------------------------------------------+
void RenderAll()
{
   ResetLabelSlots();
   ResetBands();

   // entries are the most important information, so they claim label space
   // first; zones then fill whatever is left without overlapping
   RenderEntries();
   RenderLiquidity();
   RenderVolumeAreas();
   RenderVoids();
   RenderNearest();
}

//+------------------------------------------------------------------+
//| PANEL / LEGEND                                                   |
//+------------------------------------------------------------------+
string PadRight(string s, int len)
{
   while(StringLen(s) < len) s = s + " ";
   return(s);
}

void AddPanelRow(string txt, color clr)
{
   if(g_panelRowCount >= PANEL_ROWS) return;
   g_panelRows[g_panelRowCount]   = txt;
   g_panelColors[g_panelRowCount] = clr;
   g_panelRowCount++;
}

void BuildPanelRows()
{
   g_panelRowCount = 0;

   AddPanelRow(PadRight("Swings", 13) + ": BSL " + IntegerToString(g_swingHighs) +
               "   SSL " + IntegerToString(g_swingLows), InpColorPanelTx);

   AddPanelRow(PadRight("Pools", 13) + ": " + IntegerToString(g_activePools) +
               " active / " + IntegerToString(g_sweptPools) + " swept", InpColorPanelTx);

   AddPanelRow(PadRight("Vol zones", 13) + ": " + IntegerToString(g_volCount) +
               "  (>=" + DoubleToString(EffVolumeMult(), 2) + "x)", InpColorPanelTx);

   AddPanelRow(PadRight("Voids", 13) + ": " + IntegerToString(g_voidCount) +
               "  (" + (InpShowVoids ? "on" : "off") + ")", InpColorPanelTx);

   string biasTxt = "flat";
   if(g_biasPct >  8.0) biasTxt = "buyers";
   if(g_biasPct < -8.0) biasTxt = "sellers";
   AddPanelRow(PadRight("Flow bias", 13) + ": " +
               (g_biasPct >= 0.0 ? "+" : "") + DoubleToString(g_biasPct, 0) + "%  " + biasTxt,
               (g_biasPct >= 0.0) ? InpColorBull : InpColorBear);

   AddPanelRow(PadRight("Structure", 13) + ": " + g_structBias, InpColorPanelTx);

   AddPanelRow(PadRight("Vol now", 13) + ": " +
               DoubleToString(g_volRatioNow, 2) + "x  (avg " +
               IntegerToString(InpVolAvgPeriod) + ")", InpColorPanelTx);

   string bslTxt = "---";
   if(g_hasBSL)
      bslTxt = DoubleToString(g_nearBSL, (int)Digits) + "  (+" +
               DoubleToString((g_nearBSL - c0_safe()) / g_pointsPerPip, 1) + "p)";
   AddPanelRow(PadRight("Nearest BSL", 13) + ": " + bslTxt,
               g_hasBSL ? InpColorBSL : InpColorPanelTx);

   string sslTxt = "---";
   if(g_hasSSL)
      sslTxt = DoubleToString(g_nearSSL, (int)Digits) + "  (" +
               DoubleToString((g_nearSSL - c0_safe()) / g_pointsPerPip, 1) + "p)";
   AddPanelRow(PadRight("Nearest SSL", 13) + ": " + sslTxt,
               g_hasSSL ? InpColorSSL : InpColorPanelTx);

   AddPanelRow(PadRight("Last event", 13) + ": " + g_lastEvent, InpColorText);

   string sigTxt = "none";
   color  sigClr = InpColorPanelTx;
   if(g_entryCount > 0)
   {
      int    dir   = g_entries[0].dir;
      string sideS = "SELL ";
      if(dir > 0) sideS = "BUY ";

      string whyS = "accept ";
      if(g_entries[0].reason == 0) whyS = "sweep ";

      sigTxt = sideS + whyS + DoubleToString(g_entries[0].rr, 1) + "R @ " +
               DoubleToString(g_entries[0].entry, (int)Digits);
      sigClr = (dir > 0) ? InpColorBuy : InpColorSell;
   }
   AddPanelRow(PadRight("Last signal", 13) + ": " + sigTxt, sigClr);

   string modeS = "off";
   if(InpEntrySweep && InpEntryBreakout) modeS = "sweep+accept";
   else if(InpEntrySweep)                modeS = "sweep";
   else if(InpEntryBreakout)             modeS = "accept";
   AddPanelRow(PadRight("Signals", 13) + ": " + IntegerToString(g_entryCount) +
               "  (" + modeS + ")", InpColorPanelTx);

   AddPanelRow(PadRight("Scan", 13) + ": " + IntegerToString(InpLookbackBars) +
               " bars | ATR " + DoubleToString(g_atrNow / g_pointsPerPip, 1) + "p", InpColorPanelTx);
}

void CreatePanelObjects()
{
   int x0 = 10;
   int y0 = 18;

   string bg = PFX_PNL + "BG";
   if(ObjectFind(0, bg) < 0) ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   x0);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   y0);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,       PANEL_W);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,       46 + PANEL_ROWS * 13);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     InpColorPanelBg);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR,       InpColorPanelBorder);
   ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN,      true);

   string title = PFX_PNL + "TITLE";
   if(ObjectFind(0, title) < 0) ObjectCreate(0, title, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, title, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, title, OBJPROP_XDISTANCE,  x0 + 10);
   ObjectSetInteger(0, title, OBJPROP_YDISTANCE,  y0 + 10);
   ObjectSetString(0, title,  OBJPROP_TEXT,       "REAL LIQUIDITY");
   ObjectSetString(0, title,  OBJPROP_FONT,       "Arial");
   ObjectSetInteger(0, title, OBJPROP_FONTSIZE,   InpFontSize + 1);
   ObjectSetInteger(0, title, OBJPROP_COLOR,      InpColorBSL);
   ObjectSetInteger(0, title, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, title, OBJPROP_HIDDEN,     true);

   for(int r = 0; r < PANEL_ROWS; r++)
   {
      string nm = PFX_PNL + "ROW_" + IntegerToString(r);
      if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, nm, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE,  x0 + 10);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE,  y0 + 36 + r * 13);
      ObjectSetString(0, nm,  OBJPROP_FONT,       "Courier New");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   InpFontSize);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      InpColorPanelTx);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
   }
}

void CreateLegendObjects()
{
   string txt[5];
   color  clr[5];

   txt[0] = "Buy-side liquidity (stops above highs)";
   clr[0] = InpColorBSL;
   txt[1] = "Sell-side liquidity (stops below lows)";
   clr[1] = InpColorSSL;
   txt[2] = "Volume spike zone (institutional)";
   clr[2] = InpColorBull;
   txt[3] = "Liquidity void / imbalance";
   clr[3] = InpColorVoid;
   txt[4] = "Swept liquidity (already taken)";
   clr[4] = InpColorSwept;

   for(int i = 0; i < 5; i++)
   {
      string nm = PFX_PNL + "LEG_" + IntegerToString(i);
      if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, nm, OBJPROP_CORNER,     CORNER_LEFT_LOWER);
      ObjectSetInteger(0, nm, OBJPROP_XDISTANCE,  12);
      ObjectSetInteger(0, nm, OBJPROP_YDISTANCE,  18 + (4 - i) * 14);
      ObjectSetString(0, nm,  OBJPROP_TEXT,       txt[i]);
      ObjectSetString(0, nm,  OBJPROP_FONT,       "Arial");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE,   (int)MathMax(6, InpFontSize - 1));
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      clr[i]);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
   }
}

void UpdatePanel()
{
   if(!InpShowPanel) return;
   if(ArraySize(g_vol) < 3) return;

   BuildPanelRows();

   for(int r = 0; r < PANEL_ROWS; r++)
   {
      string nm  = PFX_PNL + "ROW_" + IntegerToString(r);
      string txt = (r < g_panelRowCount) ? g_panelRows[r] : "";
      color  clr = (r < g_panelRowCount) ? g_panelColors[r] : InpColorPanelTx;

      ObjectSetString(0, nm, OBJPROP_TEXT, txt);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, clr);
   }
}

//+------------------------------------------------------------------+
//| ALERTS                                                           |
//+------------------------------------------------------------------+
void Notify(string msg)
{
   if(InpAlertSound) PlaySound("alert2.wav");
   Alert(msg);
   if(InpAlertPush) SendNotification(msg);
}

void CheckAlerts(const datetime &t[])
{
   static datetime lastChecked = 0;

   if(lastChecked == 0)
   {
      lastChecked = t[0];
      return;                       // never alert on the first calculation
   }
   if(t[0] == lastChecked) return;
   lastChecked = t[0];

   if(InpAlertSweep)
   {
      for(int i = 0; i < g_poolCount; i++)
      {
         if(!g_pools[i].swept) continue;
         if(g_pools[i].touches < InpMinTouches) continue;
         if(g_pools[i].tSwept != t[1]) continue;

         string side = (g_pools[i].kind == RLQ_BSL) ? "BUY-side (above highs)"
                                                   : "SELL-side (below lows)";
         string msg  = _Symbol + " " + IntegerToString(_Period) + "min: " + side + " liquidity swept at " +
                       DoubleToString(g_pools[i].sweepPrice, (int)Digits) +
                       " (" + IntegerToString(g_pools[i].touches) + " touches)";
         Notify(msg);
      }
   }

   if(InpAlertEntry)
   {
      for(int i = 0; i < g_entryCount; i++)
      {
         if(g_entries[i].tm != t[1]) continue;

         string side = "SELL";
         if(g_entries[i].dir > 0) side = "BUY";

         string why = "pool acceptance";
         if(g_entries[i].reason == 0) why = "liquidity sweep";
         Notify(_Symbol + " " + IntegerToString(_Period) + "min: " + side + " entry (" + why +
                ") E " + DoubleToString(g_entries[i].entry, (int)Digits) +
                " SL " + DoubleToString(g_entries[i].sl, (int)Digits) +
                " TP " + DoubleToString(g_entries[i].tp, (int)Digits) +
                "  " + DoubleToString(g_entries[i].rr, 1) + "R");
      }
   }

   if(InpAlertApproach)
   {
      if(g_hasBSL && (g_nearBSL - c0_safe()) / g_pointsPerPip <= InpAlertDistPips)
      {
         Notify(_Symbol + " " + IntegerToString(_Period) + "min: price approaching buy-side liquidity at " +
                DoubleToString(g_nearBSL, (int)Digits));
      }
      if(g_hasSSL && (c0_safe() - g_nearSSL) / g_pointsPerPip <= InpAlertDistPips)
      {
         Notify(_Symbol + " " + IntegerToString(_Period) + "min: price approaching sell-side liquidity at " +
                DoubleToString(g_nearSSL, (int)Digits));
      }
   }
}

//+------------------------------------------------------------------+
//| UTILITIES                                                        |
//+------------------------------------------------------------------+
double c0_safe()
{
   if(ArraySize(Close) > 0) return(Close[0]);
   return(0.0);
}

void DeleteObjectsByPrefix(string prefix)
{
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, prefix) == 0) ObjectDelete(0, nm);
   }
}

void DeleteDrawObjects()
{
   DeleteObjectsByPrefix(PFX_OBJ);
}

void DeleteAllObjects()
{
   DeleteObjectsByPrefix(PFX_OBJ);
   DeleteObjectsByPrefix(PFX_PNL);
}
//+------------------------------------------------------------------+
