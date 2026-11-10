//+------------------------------------------------------------------+
//|                             MarketStructureSyncScanner.mq4       |
//|                                                                  |
//|  Scans every symbol you have and reports which ones have market  |
//|  structure IN SYNC across WEEKLY, DAILY and H4:                  |
//|                                                                  |
//|     all three HH + HL  ->  SYNC BULLISH                          |
//|     all three LH + LL  ->  SYNC BEARISH                          |
//|                                                                  |
//|  Structure per timeframe is read from confirmed swing points     |
//|  (fractal pivots): the last swing high is compared with the      |
//|  previous swing high (HH / LH), and the last swing low with the  |
//|  previous swing low (HL / LL).                                   |
//+------------------------------------------------------------------+
#property copyright   "Market Structure Sync Scanner"
#property link        "https://arena.ai"
#property version     "1.00"
#property description "Weekly / Daily / H4 market-structure confluence scanner."
#property description "Shows every symbol where all three timeframes agree:"
#property description "green = HH+HL everywhere, red = LH+LL everywhere."
#property strict
#property indicator_chart_window

//=== CORE-BEGIN =====================================================
// Pure, dependency-free structure logic.
//
// This block is extracted VERBATIM by tools/test_core.py and compiled
// with gcc, so it must stay plain-C compatible: only int / double /
// long and plain arrays. No MQL4 API calls, no strings, no structs,
// no reference parameters. Everything the scanner decides about
// market structure lives here.
//--------------------------------------------------------------------

// structure states
#define ST_NONE    1   // mixed / no clean sequence
#define ST_BULL    2   // higher highs AND higher lows
#define ST_BEAR    3   // lower highs  AND lower lows
#define ST_WIDE    4   // higher highs AND lower lows  (expanding range)
#define ST_INSIDE  5   // lower highs  AND higher lows (contracting range)

// non-state return codes
#define RES_INSUFFICIENT -1   // history exists but not enough confirmed pivots
#define RES_NODATA       -2   // history not loaded / series too short

// sync codes
#define SYNC_NONE  0
#define SYNC_BULL  1
#define SYNC_BEAR  2

#define MAX_PIVOTS 8   // hard cap on pivots per side

//+------------------------------------------------------------------+
//| True when bar i is a confirmed swing high.                       |
//| Plateau rule: the NEWEST bar of a flat top is the pivot, so the  |
//| pivot must be > every newer bar and >= every older bar.          |
//+------------------------------------------------------------------+
int IsPivotHigh(double &high[], int total, int i, int leftBars, int rightBars)
  {
   if(i - leftBars < 0)          return(0);
   if(i + rightBars >= total)    return(0);

   for(int k = 1; k <= leftBars; k++)
      if(high[i] <= high[i - k]) return(0);   // a newer bar is as high or higher -> not the pivot

   for(int k = 1; k <= rightBars; k++)
      if(high[i] < high[i + k])  return(0);   // an older bar is higher -> not a pivot

   return(1);
  }

//+------------------------------------------------------------------+
//| True when bar i is a confirmed swing low (mirror of the above).  |
//| The newest bar of a flat bottom is the pivot.                    |
//+------------------------------------------------------------------+
int IsPivotLow(double &low[], int total, int i, int leftBars, int rightBars)
  {
   if(i - leftBars < 0)         return(0);
   if(i + rightBars >= total)   return(0);

   for(int k = 1; k <= leftBars; k++)
      if(low[i] >= low[i - k])  return(0);    // a newer bar is as low or lower -> not the pivot

   for(int k = 1; k <= rightBars; k++)
      if(low[i] > low[i + k])   return(0);    // an older bar is lower -> not a pivot

   return(1);
  }

//+------------------------------------------------------------------+
//| Walk the series newest -> oldest and collect the last `need`     |
//| confirmed swing highs and swing lows.                            |
//| Index 0 of every output array is the MOST RECENT pivot.          |
//| Returns the number of pivots collected per side, or -1.          |
//+------------------------------------------------------------------+
int CollectPivots(double &high[], double &low[], long &tArr[], int total,
                  int leftBars, int rightBars, int need, int maxLookback,
                  double &hiP[], long &hiT[], int &hiS[],
                  double &loP[], long &loT[], int &loS[])
  {
   int start = leftBars;
   int stop  = total - rightBars - 1;
   if(stop > maxLookback - 1) stop = maxLookback - 1;
   if(stop < start) return(-1);

   int hc = 0, lc = 0;

   for(int i = start; i <= stop; i++)
     {
      if(hc < need && IsPivotHigh(high, total, i, leftBars, rightBars))
        {
         hiP[hc] = high[i];
         hiT[hc] = tArr[i];
         hiS[hc] = i;
         hc++;
        }
      if(lc < need && IsPivotLow(low, total, i, leftBars, rightBars))
        {
         loP[lc] = low[i];
         loT[lc] = tArr[i];
         loS[lc] = i;
         lc++;
        }
      if(hc >= need && lc >= need) break;
     }

   if(hc < need || lc < need) return(-1);
   return(need);
  }

//+------------------------------------------------------------------+
//| Classify the structure from the collected pivots.                |
//| comps = number of consecutive comparisons (pivots per side - 1). |
//| hiP[0] / loP[0] are the newest pivots.                           |
//+------------------------------------------------------------------+
int ClassifyStructure(double &hiP[], double &loP[], int comps)
  {
   if(comps < 1) return(ST_NONE);

   int risingH = 1, fallingH = 1, risingL = 1, fallingL = 1;

   for(int i = 0; i < comps; i++)
     {
      if(!(hiP[i] > hiP[i + 1])) risingH  = 0;
      if(!(hiP[i] < hiP[i + 1])) fallingH = 0;
      if(!(loP[i] > loP[i + 1])) risingL  = 0;
      if(!(loP[i] < loP[i + 1])) fallingL = 0;
     }

   if(risingH  == 1 && risingL  == 1) return(ST_BULL);
   if(fallingH == 1 && fallingL == 1) return(ST_BEAR);
   if(risingH  == 1 && fallingL == 1) return(ST_WIDE);
   if(fallingH == 1 && risingL  == 1) return(ST_INSIDE);
   return(ST_NONE);
  }

//+------------------------------------------------------------------+
//| Are the three timeframes in sync?                                |
//| Returns SYNC_BULL / SYNC_BEAR / SYNC_NONE.                       |
//+------------------------------------------------------------------+
int SyncOf(int a, int b, int c)
  {
   if(a == ST_BULL && b == ST_BULL && c == ST_BULL) return(SYNC_BULL);
   if(a == ST_BEAR && b == ST_BEAR && c == ST_BEAR) return(SYNC_BEAR);
   return(SYNC_NONE);
  }

//+------------------------------------------------------------------+
//| Smallest series length that can hold `need` pivots per side.     |
//+------------------------------------------------------------------+
int MinBarsNeeded(int leftBars, int rightBars, int need)
  {
   return(leftBars + rightBars + need * 4 + 10);
  }

//+------------------------------------------------------------------+
//| Full per-timeframe analysis of one price series.                 |
//|   high/low/tArr : index 0 = most recent bar                      |
//|   total         : number of valid bars in those arrays           |
//|   out[0] = ST_* state or RES_* code                              |
//|   out[1] = bars since the newest confirmed pivot (structure age) |
//|   out[2] = 1 when that age exceeds maxAge (stale structure)      |
//|   outP[0] = newest swing high price, outP[1] = newest swing low  |
//+------------------------------------------------------------------+
int AnalyzeSeries(double &high[], double &low[], long &tArr[], int total,
                  int leftBars, int rightBars, int need, int maxLookback, int maxAge,
                  int &out[], double &outP[])
  {
   out[0]  = RES_NODATA;
   out[1]  = 0;
   out[2]  = 0;
   outP[0] = 0.0;
   outP[1] = 0.0;

   if(need < 2)          need = 2;
   if(need > MAX_PIVOTS) return(RES_NODATA);
   if(leftBars < 1 || rightBars < 1) return(RES_NODATA);
   if(total < MinBarsNeeded(leftBars, rightBars, need)) return(RES_NODATA);

   int lookback = total;
   if(maxLookback > 0 && maxLookback < lookback) lookback = maxLookback;

   double hiP[MAX_PIVOTS], loP[MAX_PIVOTS];
   long   hiT[MAX_PIVOTS], loT[MAX_PIVOTS];
   int    hiS[MAX_PIVOTS], loS[MAX_PIVOTS];

   int got = CollectPivots(high, low, tArr, lookback,
                           leftBars, rightBars, need, lookback,
                           hiP, hiT, hiS, loP, loT, loS);
   if(got < need) return(RES_INSUFFICIENT);

   int age = hiS[0];
   if(loS[0] < age) age = loS[0];

   out[0]  = ClassifyStructure(hiP, loP, need - 1);
   out[1]  = age;
   out[2]  = (maxAge > 0 && age > maxAge) ? 1 : 0;
   outP[0] = hiP[0];
   outP[1] = loP[0];

   return(out[0]);
  }

// ---- Area Of Interest ---------------------------------------------
// An AOI is the candle range of the swing point that matters for the
// current structure: the last swing low when structure is bullish (a
// demand zone you want price to come back down into) and the last swing
// high when it is bearish (a supply zone you want price to come back up
// into). The zone is then classified by what price has done to it since.

#define AOI_NONE    0
#define AOI_DEMAND  1   // built from a swing low  -> zone below price
#define AOI_SUPPLY  2   // built from a swing high -> zone above price
#define AOI_ANY     3   // caller has no view: take the most recent pivot

#define AOI_FRESH   0   // price has not come back to the zone yet
#define AOI_TESTED  1   // price returned into the zone and held
#define AOI_INSIDE  2   // price is inside the zone right now
#define AOI_SPENT   3   // price closed through the zone -> invalidated

//+------------------------------------------------------------------+
//| Locate the Area Of Interest zone of one series.                  |
//|   wantDir : AOI_DEMAND, AOI_SUPPLY or AOI_ANY                    |
//|   zone[0] = zone top,  zone[1] = zone bottom                     |
//|   tOut[0] = time of the pivot bar the zone is built from         |
//|   info[0] = AOI_DEMAND / AOI_SUPPLY actually used                |
//|   info[1] = bar shift of that pivot                              |
//|   info[2] = AOI_FRESH / AOI_TESTED / AOI_INSIDE / AOI_SPENT      |
//| Returns the zone type used, or AOI_NONE.                         |
//+------------------------------------------------------------------+
int FindAOI(double &high[], double &low[], double &close[], long &tArr[], int total,
            int leftBars, int rightBars, int wantDir, int maxLookback,
            double &zone[], long &tOut[], int &info[])
  {
   zone[0] = 0.0;
   zone[1] = 0.0;
   tOut[0] = 0;
   info[0] = AOI_NONE;
   info[1] = -1;
   info[2] = AOI_FRESH;

   if(wantDir != AOI_DEMAND && wantDir != AOI_SUPPLY && wantDir != AOI_ANY)
      return(AOI_NONE);
   if(leftBars < 1 || rightBars < 1)       return(AOI_NONE);
   if(total < leftBars + rightBars + 3)    return(AOI_NONE);

   int start = leftBars;
   int stop  = total - rightBars - 1;
   if(stop > maxLookback - 1) stop = maxLookback - 1;
   if(stop < start) return(AOI_NONE);

   // most recent confirmed swing high and swing low
   int pH = -1, pL = -1;
   for(int i = start; i <= stop; i++)
     {
      if(pH < 0 && IsPivotHigh(high, total, i, leftBars, rightBars)) pH = i;
      if(pL < 0 && IsPivotLow (low,  total, i, leftBars, rightBars)) pL = i;
      if(wantDir == AOI_DEMAND && pL >= 0) break;
      if(wantDir == AOI_SUPPLY && pH >= 0) break;
      if(pH >= 0 && pL >= 0) break;
     }

   int p = -1, dir = AOI_NONE;
   if(wantDir == AOI_DEMAND)      { p = pL; dir = AOI_DEMAND; }
   else if(wantDir == AOI_SUPPLY) { p = pH; dir = AOI_SUPPLY; }
   else
     {
      // smaller shift = more recent
      if(pL >= 0 && (pH < 0 || pL < pH)) { p = pL; dir = AOI_DEMAND; }
      else if(pH >= 0)                   { p = pH; dir = AOI_SUPPLY; }
     }
   if(p < 0) return(AOI_NONE);

   double zTop = high[p];
   double zBot = low[p];

   // Walk forward in time from the pivot. Price must first LEAVE the zone
   // before a later dip back into it counts as a test, otherwise the bar
   // immediately after the pivot would always look like a touch.
   int left = 0, touched = 0, broken = 0;
   for(int i = p - 1; i >= 0; i--)
     {
      if(dir == AOI_DEMAND)
        {
         if(close[i] < zBot)                  broken  = 1;
         else if(left == 1 && low[i] <= zTop) touched = 1;
         else if(low[i] > zTop)               left    = 1;
        }
      else
        {
         if(close[i] > zTop)                    broken  = 1;
         else if(left == 1 && high[i] >= zBot) touched = 1;
         else if(high[i] < zBot)                left    = 1;
        }
     }

   int state;
   if(broken == 1)                                state = AOI_SPENT;
   else if(close[0] >= zBot && close[0] <= zTop)  state = AOI_INSIDE;
   else if(touched == 1)                          state = AOI_TESTED;
   else                                           state = AOI_FRESH;

   zone[0] = zTop;
   zone[1] = zBot;
   tOut[0] = tArr[p];
   info[0] = dir;
   info[1] = p;
   info[2] = state;
   return(dir);
  }

// ---- Entries -----------------------------------------------------
// The higher timeframes say WHERE to look; the entry timeframes say
// WHEN.  An entry is a lower-timeframe structure turning in the same
// direction as the zone price is standing in.
#define ENTRY_NONE  0
#define ENTRY_LONG  1
#define ENTRY_SHORT 2

#define MAX_ENTRY 3

//+------------------------------------------------------------------+
//| Combine a higher-timeframe zone direction with the structure of   |
//| the entry timeframes.                                             |
//|   aoiDir     : AOI_DEMAND (want longs) or AOI_SUPPLY (want shorts)|
//|   st1..st3   : ST_* of the three entry timeframes                 |
//|   minConfirm : how many of the three must agree (clamped 1..3)    |
//|   out[0]     : ENTRY_NONE / ENTRY_LONG / ENTRY_SHORT              |
//|   out[1]     : how many entry timeframes actually confirmed       |
//| Returns out[0].                                                   |
//+------------------------------------------------------------------+
int EntrySignal(int aoiDir, int st1, int st2, int st3, int minConfirm, int &out[])
  {
   out[0] = ENTRY_NONE;
   out[1] = 0;

   // a zone with no direction gives nothing to align against
   if(aoiDir != AOI_DEMAND && aoiDir != AOI_SUPPLY) return(ENTRY_NONE);

   int need = minConfirm;
   if(need < 1) need = 1;
   if(need > MAX_ENTRY) need = MAX_ENTRY;

   // a demand zone is bought, so it wants bullish structure underneath it;
   // a supply zone is sold, so it wants bearish structure
   int want = (aoiDir == AOI_DEMAND) ? ST_BULL : ST_BEAR;

   int n = 0;
   if(st1 == want) n++;
   if(st2 == want) n++;
   if(st3 == want) n++;
   out[1] = n;

   if(n < need) return(ENTRY_NONE);

   out[0] = (aoiDir == AOI_DEMAND) ? ENTRY_LONG : ENTRY_SHORT;
   return(out[0]);
  }

//=== CORE-END =======================================================


//============================== INPUTS ==============================
input string Sep0             = "=====  SCAN SCOPE  ======================";
input int    ScanScope        = 0;                    // 0=Market Watch, 1=All terminal symbols, 2=Custom list
input string CustomSymbols    = "EURUSD,GBPUSD,USDJPY,XAUUSD"; // used when ScanScope=2
input string IncludeFilter    = "";                   // comma list: symbol must contain one of these ("" = all)
input string ExcludeFilter    = "";                   // comma list: skip symbols containing any of these
input bool   AddToMarketWatch = true;                 // auto-add scanned symbols to Market Watch

input string Sep1             = "=====  STRUCTURE ENGINE  =================";
input int    PivotLeft        = 2;                    // bars on the newer side of a pivot
input int    PivotRight       = 2;                    // bars on the older side of a pivot (confirmation)
input int    PivotsPerSide    = 2;                    // pivots per side: 2 = HH/HL, 3 = HH+HH/HL+HL (stricter)
input int    MaxLookbackBars  = 250;                  // max bars searched per timeframe
input int    MaxSwingAgeBars  = 0;                    // 0=off; else a structure older than this is stale

input string Sep2             = "=====  TIMEFRAMES  =====================";
input ENUM_TIMEFRAMES TF_High = PERIOD_W1;            // highest timeframe
input ENUM_TIMEFRAMES TF_Mid  = PERIOD_D1;            // middle timeframe
input ENUM_TIMEFRAMES TF_Fast = PERIOD_H4;            // fastest timeframe

input string Sep3             = "=====  PANEL  ===========================";
input int    PanelCorner      = 0;                    // 0=left-top 1=right-top 2=left-bottom 3=right-bottom
input int    PanelX           = 12;                   // X offset (px)
input int    PanelY           = 22;                   // Y offset (px)
input int    PanelMaxRows     = 40;                   // max symbol rows shown
input bool   ShowOnlySynced   = false;                // show only synced symbols
input bool   ShowUnavailable  = true;                 // show symbols whose history is not loaded yet
input bool   ShowBackground   = true;                 // draw the panel background box
input string PanelFont        = "Consolas";           // keep a monospace font for column alignment
input int    PanelFontSize    = 9;
input double PanelCharFactor  = 0.55;                 // char width = fontsize * factor (0.55 Consolas, 0.60 Courier)
input color  ColorBull        = C'40,205,130';
input color  ColorBear        = C'255,85,95';
input color  ColorNeutral     = C'150,155,170';
input color  ColorHeader      = C'225,228,240';
input color  ColorTitle       = C'255,215,90';
input color  ColorBackground  = C'16,18,24';
input color  ColorBorder      = C'60,66,84';

input string Sep4             = "=====  SCAN + ALERTS  ===================";
input int    RescanSeconds    = 30;                   // seconds between scan passes
input int    SymbolsPerPass   = 8;                    // symbols analysed per pass (keeps the chart responsive)
input bool   AlertOnStartup   = false;                // fire alerts for syncs already present on the first scan
input bool   AlertPopup       = true;
input bool   AlertPush        = false;                // push notification (needs terminal setup)
input bool   AlertEmail       = false;                // email (needs terminal setup)
input bool   AlertSound       = true;
input string AlertSoundFile   = "alert.wav";
input int    AlertCooldownMin = 120;                  // minutes before re-alerting the same symbol + direction
input bool   PrintResults     = true;                 // log the synced list to the Experts tab
input bool   PrintFullTable   = false;                // log the whole table to the Experts tab

input string Sep5             = "=====  CHART PIVOTS  ====================";
input bool   ShowPivotsOnChart= true;                 // draw swing points on this chart's symbol/period
input int    ChartPivotCount  = 14;                   // swings per side to draw
input color  ColorSwingHigh   = C'255,120,130';
input color  ColorSwingLow    = C'80,190,255';

input string Sep6             = "=====  AOI (AREA OF INTEREST)  ===========";
input bool   ScanAOI          = true;                 // scan Weekly + Daily areas of interest
input bool   DrawAOIOnChart   = true;                 // draw the W1/D1 AOI zones on this chart
input bool   AOIShowSpent     = false;                // also draw zones price has already closed through
input int    AOIExtendBars    = 40;                   // how many bars forward to extend each zone
input bool   AOIAlertOnTouch  = true;                 // alert when price enters a fresh/tested W1 or D1 zone
input color  ColorDemand      = C'35,150,110';        // bullish AOI (from a swing low)
input color  ColorSupply      = C'190,70,85';         // bearish AOI (from a swing high)
input color  ColorAOISpent    = C'95,100,115';

input string Sep7               = "=====  ENTRIES (M15 / M30 / H1)  =====";
input bool   ScanEntries        = true;               // grade entries while price sits in a live W1/D1 AOI
input ENUM_TIMEFRAMES TF_Entry1 = PERIOD_M15;         // entry timeframe 1
input ENUM_TIMEFRAMES TF_Entry2 = PERIOD_M30;         // entry timeframe 2
input ENUM_TIMEFRAMES TF_Entry3 = PERIOD_H1;          // entry timeframe 3
input int    EntryMinConfirm    = 1;                  // how many entry timeframes must agree (1-3)
input bool   EntryAllowTested   = false;              // also signal on zones price has touched and left
input bool   EntryAlert         = true;               // alert when a new entry signal appears
input color  ColorEntryLong     = C'60,190,140';      // long entry
input color  ColorEntryShort    = C'230,110,120';     // short entry


//============================= GLOBALS ==============================
#define PREFIX "MSS_"

#define DATA_UNKNOWN 0
#define DATA_LOADING 1
#define DATA_READY   2
#define DATA_MISSING 3

#define MAX_TF 3

// display-only extra state, never produced by the core logic
#define ST_FEW 6

struct SymRec
  {
   string   symbol;
   int      st[MAX_TF];      // ST_* per timeframe
   int      data[MAX_TF];    // DATA_* per timeframe
   int      age[MAX_TF];     // bars since the newest confirmed pivot
   double   hiPrice[MAX_TF]; // newest swing high price
   double   loPrice[MAX_TF]; // newest swing low price
   bool     stale[MAX_TF];
   int      sync;            // SYNC_*
   int      loadAttempts;
   // area of interest, tracked for the two higher timeframes (W1, D1)
   int      aoiType[MAX_TF];  // AOI_* zone direction
   int      aoiState[MAX_TF]; // AOI_FRESH / TESTED / INSIDE / SPENT
   double   aoiTop[MAX_TF];
   double   aoiBot[MAX_TF];
   datetime aoiTime[MAX_TF];
   // entry timeframes, only graded while price is inside a live AOI
   int      eSt[MAX_ENTRY];      // ST_* per entry timeframe
   int      eData[MAX_ENTRY];    // DATA_* per entry timeframe
   int      entrySig;            // ENTRY_NONE / ENTRY_LONG / ENTRY_SHORT
   int      entryConfirm;        // how many entry timeframes agreed
   int      entryTF;             // index of the AOI that triggered it (0=W1, 1=D1)
  };

SymRec   g_syms[];
int      g_symCount    = 0;
int      g_cursor      = 0;
int      g_generation  = 0;
int      g_lastTotal   = -1;
bool     g_listDirty   = true;

int      g_prevSync[];     // sync state at the end of the previous pass
datetime g_alertTime[];    // last alert time per symbol
int      g_alertDir[];     // last alerted direction per symbol
int      g_prevEntry[];    // entry signal at the end of the previous pass
datetime g_entryTime[];    // last entry alert time per symbol
int      g_order[];        // render order (indices into g_syms)

// runtime copies of the inputs (input variables are read-only)
int      g_pivotLeft, g_pivotRight, g_pivotsPerSide, g_lookback, g_maxAge;
int      g_scanSeconds, g_perPass, g_cooldownSec, g_maxRows, g_chartPivots, g_scope;
bool     g_scanAOI;
int      g_aoiExtend;
int      g_aoiAlerted = 0;   // bitmask of the W1/D1 zones we already alerted on

bool     g_scanEntries;
int      g_entryMinConfirm;
bool     g_entryAllowTested;

ENUM_TIMEFRAMES g_tfs[MAX_TF];
ENUM_TIMEFRAMES g_efs[MAX_ENTRY];   // entry timeframes

// panel metrics
int      g_charW        = 6;
int      g_lineH        = 15;
int      g_anchor       = ANCHOR_LEFT_UPPER;
bool     g_rightAligned = false;
bool     g_lowerCorner  = false;

// panel layout, measured in characters
#define COL_SYM_OFF   0
#define COL_SYM_W    11
#define COL_T1_OFF   12
#define COL_T1_W      6
#define COL_T2_OFF   19
#define COL_T2_W      6
#define COL_T3_OFF   26
#define COL_T3_W      6
#define COL_SYNC_OFF 33
#define COL_SYNC_W    6
#define COL_AGE_OFF  40
#define COL_AGE_W     9
#define COL_AOI1_OFF 50
#define COL_AOI1_W   10
#define COL_AOI2_OFF 61
#define COL_AOI2_W   10
// entry timeframes: StateText() is 5 chars wide, so 5 is enough per cell
#define COL_E1_OFF   72
#define COL_E1_W      5
#define COL_E2_OFF   78
#define COL_E2_W      5
#define COL_E3_OFF   84
#define COL_E3_W      5
#define COL_ENTRY_OFF 90
#define COL_ENTRY_W   9        // "SHORT 3/3" is the widest value
#define TOTAL_CHARS  99
#define HEADER_ROWS  11


//=========================== HELPERS ================================
string PadRight(string s, int width)
  {
   string r = s;
   while(StringLen(r) < width) r = r + " ";
   if(StringLen(r) > width) r = StringSubstr(r, 0, width);
   return(r);
  }

string PadLeft(string s, int width)
  {
   string r = s;
   while(StringLen(r) < width) r = " " + r;
   if(StringLen(r) > width) r = StringSubstr(r, StringLen(r) - width, width);
   return(r);
  }

string Repeat(string ch, int n)
  {
   string r = "";
   for(int i = 0; i < n; i++) r = r + ch;
   return(r);
  }

int SplitCSV(string src, string &out[])
  {
   ArrayResize(out, 0);
   if(StringLen(src) == 0) return(0);

   string parts[];
   ushort sep = StringGetCharacter(",", 0);
   int n = StringSplit(src, sep, parts);

   for(int i = 0; i < n; i++)
     {
      string t = parts[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      if(StringLen(t) > 0)
        {
         int c = ArraySize(out);
         ArrayResize(out, c + 1);
         out[c] = t;
        }
     }
   return(ArraySize(out));
  }

bool ContainsAny(string sym, string &tokens[])
  {
   string up = sym;
   StringToUpper(up);
   for(int i = 0; i < ArraySize(tokens); i++)
     {
      string t = tokens[i];
      StringToUpper(t);
      if(StringFind(up, t) >= 0) return(true);
     }
   return(false);
  }

string TFLabel(ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return(s);
  }

int FindIdx(string sym)
  {
   for(int i = 0; i < ArraySize(g_syms); i++)
      if(g_syms[i].symbol == sym) return(i);
   return(-1);
  }


//=========================== STATE TEXT =============================
string StateText(int st)
  {
   if(st == ST_BULL)   return("HH HL");
   if(st == ST_BEAR)   return("LH LL");
   if(st == ST_WIDE)   return("HH LL");
   if(st == ST_INSIDE) return("LH HL");
   if(st == ST_FEW)    return("~few");
   if(st == ST_NONE)   return("mixed");
   return("-");
  }

color StateColor(int st)
  {
   if(st == ST_BULL) return(ColorBull);
   if(st == ST_BEAR) return(ColorBear);
   if(st == ST_WIDE || st == ST_INSIDE) return(C'230,175,60');
   return(ColorNeutral);
  }

string SyncText(int s)
  {
   if(s == SYNC_BULL) return("BULL");
   if(s == SYNC_BEAR) return("BEAR");
   return("-");
  }

color SyncColor(int s)
  {
   if(s == SYNC_BULL) return(ColorBull);
   if(s == SYNC_BEAR) return(ColorBear);
   return(ColorNeutral);
  }


//======================== STRUCTURE ENGINE ==========================
//+------------------------------------------------------------------+
//| Pull the series for one symbol/timeframe and analyse it.         |
//| Returns an ST_* state, or RES_INSUFFICIENT / RES_NODATA.         |
//+------------------------------------------------------------------+
int AnalyzeTF(string sym, ENUM_TIMEFRAMES tf, bool withAOI,
              int &ageOut, double &hiOut, double &loOut, bool &staleOut,
              int &aoiTypeOut, int &aoiStateOut,
              double &aoiTopOut, double &aoiBotOut, datetime &aoiTimeOut)
  {
   ageOut      = 0;
   hiOut       = 0.0;
   loOut       = 0.0;
   staleOut    = false;
   aoiTypeOut  = AOI_NONE;
   aoiStateOut = AOI_FRESH;
   aoiTopOut   = 0.0;
   aoiBotOut   = 0.0;
   aoiTimeOut  = 0;

   int need = g_pivotsPerSide;
   if(need < 2) need = 2;

   int total = iBars(sym, tf);
   if(total < MinBarsNeeded(g_pivotLeft, g_pivotRight, need)) return(RES_NODATA);

   int want = MathMin(g_lookback, total);

   double hi[], lo[], cl[];
   long   tm[];
   if(ArrayResize(hi, want) != want) return(RES_NODATA);
   ArrayResize(lo, want);
   ArrayResize(cl, want);
   ArrayResize(tm, want);

   int valid = want;
   for(int i = 0; i < want; i++)
     {
      double   h = iHigh(sym, tf, i);
      double   l = iLow(sym, tf, i);
      double   c = iClose(sym, tf, i);
      datetime t = iTime(sym, tf, i);
      if(h <= 0.0 || l <= 0.0 || c <= 0.0 || t <= 0)
        {
         valid = i;                 // broker history ends here
         break;
        }
      hi[i] = h;
      lo[i] = l;
      cl[i] = c;
      tm[i] = (long)t;
     }

   int    out[3];
   double outP[2];
   int r = AnalyzeSeries(hi, lo, tm, valid,
                         g_pivotLeft, g_pivotRight, need, g_lookback, g_maxAge,
                         out, outP);

   ageOut   = out[1];
   hiOut    = outP[0];
   loOut    = outP[1];
   staleOut = (out[2] == 1);

   // The zone follows the structure: bullish structure -> buy the dip into
   // the last higher low; bearish -> sell the rally into the last lower high.
   // With no clean structure we fall back to whichever pivot is most recent.
   if(withAOI && r >= 0)
     {
      int wantDir = AOI_ANY;
      if(r == ST_BULL)      wantDir = AOI_DEMAND;
      else if(r == ST_BEAR) wantDir = AOI_SUPPLY;

      double zone[2];
      long   zt[1];
      int    info[3];
      if(FindAOI(hi, lo, cl, tm, valid,
                 g_pivotLeft, g_pivotRight, wantDir, g_lookback,
                 zone, zt, info) != AOI_NONE)
        {
         aoiTypeOut  = info[0];
         aoiStateOut = info[2];
         aoiTopOut   = zone[0];
         aoiBotOut   = zone[1];
         aoiTimeOut  = (datetime)zt[0];
        }
     }

   return(r);
  }

//+------------------------------------------------------------------+
//| Analyse one symbol across all three timeframes.                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Index of the higher-timeframe zone price is trading in right now. |
//| INSIDE always wins over TESTED, and Weekly wins over Daily.       |
//| Returns 0 (W1), 1 (D1) or -1 when price is in neither.            |
//+------------------------------------------------------------------+
int ZoneAtPrice(int idx)
  {
   for(int t = 0; t < 2; t++)
     {
      if(g_syms[idx].data[t] == DATA_READY &&
         g_syms[idx].aoiType[t] != AOI_NONE &&
         g_syms[idx].aoiState[t] == AOI_INSIDE) return(t);
     }

   if(!g_entryAllowTested) return(-1);

   for(int t = 0; t < 2; t++)
     {
      if(g_syms[idx].data[t] == DATA_READY &&
         g_syms[idx].aoiType[t] != AOI_NONE &&
         g_syms[idx].aoiState[t] == AOI_TESTED) return(t);
     }
   return(-1);
  }

//+------------------------------------------------------------------+
//| Grade the entry timeframes, but only while price is standing in   |
//| one of the higher-timeframe zones - an M15 signal with no zone    |
//| behind it is noise, and scanning it for every symbol is waste.    |
//+------------------------------------------------------------------+
void ScanEntries(int idx)
  {
   g_syms[idx].entrySig     = ENTRY_NONE;
   g_syms[idx].entryConfirm = 0;
   g_syms[idx].entryTF      = -1;

   int est[MAX_ENTRY];
   for(int e = 0; e < MAX_ENTRY; e++)
     {
      est[e]                 = ST_NONE;
      g_syms[idx].eSt[e]     = ST_NONE;
      g_syms[idx].eData[e]   = DATA_UNKNOWN;
     }

   if(!g_scanEntries || !g_scanAOI) return;

   int zone = ZoneAtPrice(idx);
   if(zone < 0) return;

   for(int e = 0; e < MAX_ENTRY; e++)
     {
      int      age = 0;
      double   hp = 0.0, lp = 0.0;
      bool     stale = false;
      int      aType = AOI_NONE, aState = AOI_FRESH;
      double   aTop = 0.0, aBot = 0.0;
      datetime aTime = 0;

      // entries never carry their own AOI - the zone is the higher timeframe's
      int r = AnalyzeTF(g_syms[idx].symbol, g_efs[e], false,
                        age, hp, lp, stale, aType, aState, aTop, aBot, aTime);

      if(r == RES_NODATA)
        {
         g_syms[idx].loadAttempts++;
         g_syms[idx].eData[e] = (g_syms[idx].loadAttempts > 10) ? DATA_MISSING : DATA_LOADING;
        }
      else if(r == RES_INSUFFICIENT)
        {
         g_syms[idx].eData[e] = DATA_READY;   // history exists, not enough swings yet
         est[e]               = ST_FEW;
        }
      else
        {
         g_syms[idx].eData[e] = DATA_READY;
         est[e]               = r;
        }
     }

   for(int e = 0; e < MAX_ENTRY; e++) g_syms[idx].eSt[e] = est[e];

   int eo[2];
   EntrySignal(g_syms[idx].aoiType[zone], est[0], est[1], est[2],
               g_entryMinConfirm, eo);

   g_syms[idx].entrySig     = eo[0];
   g_syms[idx].entryConfirm = eo[1];
   g_syms[idx].entryTF      = zone;
  }

void ScanSymbol(int idx)
  {
   if(idx < 0 || idx >= g_symCount) return;

   int stLocal[MAX_TF] = {ST_NONE, ST_NONE, ST_NONE};
   int readyCount = 0;

   for(int t = 0; t < MAX_TF; t++)
     {
      int      age = 0;
      double   hp  = 0.0, lp = 0.0;
      bool     stale = false;
      int      aType = AOI_NONE, aState = AOI_FRESH;
      double   aTop = 0.0, aBot = 0.0;
      datetime aTime = 0;

      // AOI is only tracked on the two higher timeframes (Weekly, Daily)
      bool withAOI = (g_scanAOI && t < 2);
      int  r = AnalyzeTF(g_syms[idx].symbol, g_tfs[t], withAOI,
                         age, hp, lp, stale, aType, aState, aTop, aBot, aTime);

      stLocal[t]              = ST_NONE;
      g_syms[idx].age[t]      = age;
      g_syms[idx].hiPrice[t]  = hp;
      g_syms[idx].loPrice[t]  = lp;
      g_syms[idx].stale[t]    = false;
      g_syms[idx].aoiType[t]  = aType;
      g_syms[idx].aoiState[t] = aState;
      g_syms[idx].aoiTop[t]   = aTop;
      g_syms[idx].aoiBot[t]   = aBot;
      g_syms[idx].aoiTime[t]  = aTime;

      if(r == RES_NODATA)
        {
         g_syms[idx].loadAttempts++;
         g_syms[idx].data[t] = (g_syms[idx].loadAttempts > 10) ? DATA_MISSING : DATA_LOADING;
        }
      else if(r == RES_INSUFFICIENT)
        {
         g_syms[idx].data[t] = DATA_READY;   // history exists, just not enough swings yet
         stLocal[t]          = ST_FEW;
         readyCount++;
        }
      else
        {
         g_syms[idx].data[t] = DATA_READY;
         stLocal[t]          = r;
         g_syms[idx].stale[t] = stale;
         readyCount++;
        }
     }

   for(int t = 0; t < MAX_TF; t++) g_syms[idx].st[t] = stLocal[t];

   int sync = SYNC_NONE;
   if(readyCount == MAX_TF)
     {
      bool anyStale = false;
      for(int t = 0; t < MAX_TF; t++)
         if(g_syms[idx].stale[t]) anyStale = true;
      if(!anyStale)
         sync = SyncOf(g_syms[idx].st[0], g_syms[idx].st[1], g_syms[idx].st[2]);
     }
   g_syms[idx].sync = sync;

   ScanEntries(idx);
  }


//========================== SYMBOL LIST =============================
bool MatchesFilters(string sym)
  {
   string inc[], exc[];
   int ni = SplitCSV(IncludeFilter, inc);
   int ne = SplitCSV(ExcludeFilter, exc);

   if(ni > 0 && !ContainsAny(sym, inc)) return(false);
   if(ne > 0 &&  ContainsAny(sym, exc)) return(false);
   return(true);
  }

void AddSymbolToList(string sym)
  {
   if(StringLen(sym) == 0) return;
   if(FindIdx(sym) >= 0)   return;

   int n = ArraySize(g_syms);
   ArrayResize(g_syms, n + 1);

   g_syms[n].symbol       = sym;
   g_syms[n].sync         = SYNC_NONE;
   g_syms[n].loadAttempts = 0;
   for(int t = 0; t < MAX_TF; t++)
     {
      g_syms[n].st[t]      = ST_NONE;
      g_syms[n].data[t]    = DATA_UNKNOWN;
      g_syms[n].age[t]     = 0;
      g_syms[n].hiPrice[t] = 0.0;
      g_syms[n].loPrice[t] = 0.0;
      g_syms[n].stale[t]   = false;
     }

   if(AddToMarketWatch && SymbolInfoInteger(sym, SYMBOL_SELECT) == 0)
      SymbolSelect(sym, true);
  }

//+------------------------------------------------------------------+
//| (Re)build the scan list, preserving per-symbol alert state.      |
//+------------------------------------------------------------------+
void BuildSymbolList()
  {
   int oldN = ArraySize(g_syms);
   string   oldSym[];
   datetime oldAt[];
   int      oldDir[];
   datetime oldEntAt[];
   ArrayResize(oldSym,   oldN);
   ArrayResize(oldAt,    oldN);
   ArrayResize(oldDir,   oldN);
   ArrayResize(oldEntAt, oldN);
   for(int i = 0; i < oldN; i++)
     {
      oldSym[i]   = g_syms[i].symbol;
      oldAt[i]    = (i < ArraySize(g_alertTime)) ? g_alertTime[i] : 0;
      oldDir[i]   = (i < ArraySize(g_alertDir))  ? g_alertDir[i]  : SYNC_NONE;
      oldEntAt[i] = (i < ArraySize(g_entryTime)) ? g_entryTime[i] : 0;
     }

   ArrayResize(g_syms, 0);

   if(g_scope == 2)
     {
      string list[];
      int n = SplitCSV(CustomSymbols, list);
      for(int i = 0; i < n; i++) AddSymbolToList(list[i]);
     }
   else
     {
      bool selected = (g_scope == 0);
      int  total    = SymbolsTotal(selected);
      for(int i = 0; i < total; i++)
        {
         string s = SymbolName(i, selected);
         if(StringLen(s) == 0)  continue;
         if(!MatchesFilters(s)) continue;
         AddSymbolToList(s);
        }
      g_lastTotal = total;
     }

   g_symCount = ArraySize(g_syms);

   ArrayResize(g_prevSync,  g_symCount);
   ArrayResize(g_alertTime, g_symCount);
   ArrayResize(g_alertDir,  g_symCount);
   ArrayResize(g_prevEntry, g_symCount);
   ArrayResize(g_entryTime, g_symCount);

   for(int i = 0; i < g_symCount; i++)
     {
      g_prevSync[i]  = SYNC_NONE;
      g_alertTime[i] = 0;
      g_alertDir[i]  = SYNC_NONE;
      g_prevEntry[i] = ENTRY_NONE;
      g_entryTime[i] = 0;
      for(int j = 0; j < oldN; j++)
        {
         if(oldSym[j] == g_syms[i].symbol)
           {
            g_alertTime[i] = oldAt[j];
            g_alertDir[i]  = oldDir[j];
            g_entryTime[i] = oldEntAt[j];
            break;
           }
        }
     }

   g_cursor = 0;
  }


//============================ SCANNER ===============================
void OnPassComplete()
  {
   CheckAlerts();
   CheckAOIAlert();
   CheckEntryAlert();
   if(ShowPivotsOnChart) DrawChartPivots();
   DrawAOIZones();

   if(PrintResults)
     {
      int nb = 0, nr = 0;
      string bull = "", bear = "";
      for(int i = 0; i < g_symCount; i++)
        {
         if(g_syms[i].sync == SYNC_BULL) { nb++; bull = bull + (nb > 1 ? ", " : "") + g_syms[i].symbol; }
         if(g_syms[i].sync == SYNC_BEAR) { nr++; bear = bear + (nr > 1 ? ", " : "") + g_syms[i].symbol; }
        }
      Print("MSS pass ", g_generation, " | symbols ", g_symCount,
            " | SYNC BULL ", nb, " [", bull, "]",
            " | SYNC BEAR ", nr, " [", bear, "]");

      if(PrintFullTable)
        {
         string tbl = "MSS full table:";
         for(int i = 0; i < g_symCount; i++) tbl = tbl + "\n  " + RowLog(i);
         Print(tbl);
        }
     }
  }

void RunPass()
  {
   if(g_listDirty)
     {
      BuildSymbolList();
      g_listDirty = false;
     }

   if(g_symCount == 0)
     {
      RenderPanel();
      ChartRedraw();
      return;
     }

   int processed = 0;
   while(processed < g_perPass && g_cursor < g_symCount)
     {
      ScanSymbol(g_cursor);
      g_cursor++;
      processed++;
     }

   if(g_cursor >= g_symCount)
     {
      g_cursor = 0;
      g_generation++;
      OnPassComplete();
     }

   RenderPanel();
   ChartRedraw();
  }


//============================ ALERTS ================================
string DescribeSymbol(int idx)
  {
   string s = g_syms[idx].symbol + " | ";
   for(int t = 0; t < MAX_TF; t++)
     {
      s = s + TFLabel(g_tfs[t]) + ":" + StateText(g_syms[idx].st[t]);
      if(t < MAX_TF - 1) s = s + " | ";
     }
   return(s);
  }

void CheckAlerts()
  {
   // the first completed pass only records the baseline unless asked otherwise
   if(g_generation <= 1 && !AlertOnStartup)
     {
      for(int i = 0; i < g_symCount; i++) g_prevSync[i] = g_syms[i].sync;
      return;
     }

   for(int i = 0; i < g_symCount; i++)
     {
      int now  = g_syms[i].sync;
      int prev = g_prevSync[i];
      if(now == SYNC_NONE || now == prev) continue;

      if(g_alertDir[i] == now && g_alertTime[i] > 0 &&
         TimeCurrent() - g_alertTime[i] < g_cooldownSec) continue;

      string dir = (now == SYNC_BULL) ? "BULLISH  (HH+HL on all 3)" : "BEARISH  (LH+LL on all 3)";
      string msg = "STRUCTURE SYNC " + dir + " | " + DescribeSymbol(i);

      if(AlertPopup) Alert(msg);
      if(AlertPush)  SendNotification(msg);
      if(AlertEmail) SendMail("Market Structure Sync - " + g_syms[i].symbol, msg);
      if(AlertSound) PlaySound(AlertSoundFile);

      g_alertTime[i] = TimeCurrent();
      g_alertDir[i]  = now;
      g_prevSync[i]  = now;
     }
  }

//+------------------------------------------------------------------+
//| Entry alerts.  Fires when a symbol ACQUIRES an entry signal, and  |
//| re-arms when the signal goes away, so a signal that holds across   |
//| passes shouts once rather than every 30 seconds.                  |
//+------------------------------------------------------------------+
void CheckEntryAlert()
  {
   if(!g_scanEntries || !EntryAlert) return;

   // same baseline rule as the sync alerts: do not shout about entries
   // that were already there when the indicator was attached
   if(g_generation <= 1 && !AlertOnStartup)
     {
      for(int i = 0; i < g_symCount; i++) g_prevEntry[i] = g_syms[i].entrySig;
      return;
     }

   for(int i = 0; i < g_symCount; i++)
     {
      int now  = g_syms[i].entrySig;
      int prev = g_prevEntry[i];
      if(now == ENTRY_NONE || now == prev) { g_prevEntry[i] = now; continue; }

      if(g_entryTime[i] > 0 && TimeCurrent() - g_entryTime[i] < g_cooldownSec) continue;

      int    zone = g_syms[i].entryTF;
      string side = (now == ENTRY_LONG) ? "LONG" : "SHORT";
      string msg  = "ENTRY " + side + " | " + g_syms[i].symbol +
                    " | in " + TFLabel(g_tfs[zone]) +
                    ((g_syms[i].aoiType[zone] == AOI_DEMAND) ? " DEMAND" : " SUPPLY") + " zone " +
                    IntegerToString(g_syms[i].entryConfirm) + "/" + IntegerToString(MAX_ENTRY) +
                    " entry TFs agree | " + DescribeSymbol(i);

      if(AlertPopup) Alert(msg);
      if(AlertPush)  SendNotification(msg);
      if(AlertEmail) SendMail("Entry signal - " + g_syms[i].symbol, msg);
      if(AlertSound) PlaySound(AlertSoundFile);

      g_entryTime[i] = TimeCurrent();
      g_prevEntry[i] = now;
     }
  }


//============================= PANEL ================================
//+------------------------------------------------------------------+
//| The background must be created BEFORE the text labels, otherwise |
//| it is painted over them (MT4 z-order follows creation order).    |
//+------------------------------------------------------------------+
void EnsureBackground()
  {
   string name = PREFIX + "BG";
   if(!ShowBackground)
     {
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
      return;
     }
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, name, OBJPROP_CORNER,      PanelCorner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,      g_anchor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,    false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
      ObjectSetInteger(0, name, OBJPROP_BACK,        false);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   PanelX - 7);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   PanelY - 5);
      ObjectSetInteger(0, name, OBJPROP_XSIZE,       10);
      ObjectSetInteger(0, name, OBJPROP_YSIZE,       10);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     ColorBackground);
      ObjectSetInteger(0, name, OBJPROP_COLOR,       ColorBorder);
     }
  }

void SizeBackground(int rows)
  {
   if(!ShowBackground) return;
   string name = PREFIX + "BG";
   if(ObjectFind(0, name) < 0) return;

   ObjectSetInteger(0, name, OBJPROP_XSIZE, TOTAL_CHARS * g_charW + 14);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, rows * g_lineH + 10);
  }

//+------------------------------------------------------------------+
//| One text cell of the panel.                                      |
//+------------------------------------------------------------------+
void Place(int id, int charOff, int width, int rowIdx, string text, color clr, bool isTitle)
  {
   string name = PREFIX + "L" + IntegerToString(id);

   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return;
      ObjectSetInteger(0, name, OBJPROP_CORNER,     PanelCorner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     g_anchor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetString (0, name, OBJPROP_FONT,       PanelFont);
     }

   int xp = PanelX + charOff * g_charW;
   if(g_rightAligned) xp = PanelX + (TOTAL_CHARS - (charOff + width)) * g_charW;

   int yp = PanelY + rowIdx * g_lineH;
   if(g_lowerCorner) yp = PanelY + (HEADER_ROWS + g_maxRows + 1 - rowIdx) * g_lineH;

   string body = g_rightAligned ? PadLeft(text, width) : PadRight(text, width);

   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xp);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yp);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  isTitle ? PanelFontSize + 2 : PanelFontSize);
   ObjectSetString (0, name, OBJPROP_TEXT,      body);
  }

void HideFrom(int firstId, int lastId)
  {
   for(int id = firstId; id <= lastId; id++)
     {
      string name = PREFIX + "L" + IntegerToString(id);
      if(ObjectFind(0, name) >= 0) ObjectSetString(0, name, OBJPROP_TEXT, "");
     }
  }

//+------------------------------------------------------------------+
//| Render order: synced first, then partial, then no data.          |
//| Ties are broken alphabetically.                                  |
//+------------------------------------------------------------------+
bool ComesFirst(int a, int b)
  {
   int ra = RankOf(a), rb = RankOf(b);
   if(ra != rb) return(ra > rb);
   return(g_syms[a].symbol < g_syms[b].symbol);
  }

void SortOrder()
  {
   ArrayResize(g_order, g_symCount);
   for(int i = 0; i < g_symCount; i++) g_order[i] = i;

   for(int i = 1; i < g_symCount; i++)
     {
      int key = g_order[i];
      int j   = i - 1;
      while(j >= 0 && ComesFirst(key, g_order[j]))
        {
         g_order[j + 1] = g_order[j];
         j--;
        }
      g_order[j + 1] = key;
     }
  }

int RankOf(int idx)
  {
   // A confirmed entry outranks everything: price is in a higher-timeframe
   // zone AND the entry timeframes have turned the same way. Below that,
   // sitting in a live zone, then a plain three-timeframe sync.
   if(g_syms[idx].entrySig != ENTRY_NONE) return(500);

   int at = -1;
   if(AtLiveAOI(idx, at)) return(400);

   if(g_syms[idx].sync == SYNC_BULL) return(300);
   if(g_syms[idx].sync == SYNC_BEAR) return(290);

   int ready = 0;
   for(int t = 0; t < MAX_TF; t++) if(g_syms[idx].data[t] == DATA_READY) ready++;
   if(ready == MAX_TF) return(200);
   if(ready > 0)       return(100 + ready);
   return(10);
  }

string CellText(int idx, int t)
  {
   if(g_syms[idx].data[t] == DATA_LOADING) return("~load");
   if(g_syms[idx].data[t] == DATA_MISSING) return("nodat");
   if(g_syms[idx].data[t] != DATA_READY)   return("....");
   return(StateText(g_syms[idx].st[t]));
  }

color CellColor(int idx, int t)
  {
   if(g_syms[idx].data[t] != DATA_READY) return(C'95,100,115');
   return(StateColor(g_syms[idx].st[t]));
  }

string AgeText(int idx)
  {
   string s = "";
   for(int t = 0; t < MAX_TF; t++)
     {
      if(g_syms[idx].data[t] == DATA_READY) s = s + IntegerToString(g_syms[idx].age[t]);
      else                                  s = s + "-";
      if(t < MAX_TF - 1) s = s + "/";
     }
   return(s);
  }

//+------------------------------------------------------------------+
//| AOI cell, e.g. "D 1.08432" / "S 1.09110".                        |
//| Suffix marks the state: nothing = fresh, t = tested,              |
//| > = price is inside it now, x = closed through (dead).            |
//+------------------------------------------------------------------+
string AOIText(int idx, int t)
  {
   if(g_syms[idx].data[t] != DATA_READY)   return("-");
   if(g_syms[idx].aoiType[t] == AOI_NONE)  return("-");

   string s = (g_syms[idx].aoiType[t] == AOI_DEMAND) ? "D " : "S ";
   // SymbolInfoInteger returns long; DoubleToString wants int
   s = s + DoubleToString(g_syms[idx].aoiTop[t],
                          (int)SymbolInfoInteger(g_syms[idx].symbol, SYMBOL_DIGITS));

   int st = g_syms[idx].aoiState[t];
   if(st == AOI_TESTED)      s = s + "t";
   else if(st == AOI_INSIDE) s = s + ">";
   else if(st == AOI_SPENT)  s = s + "x";
   return(s);
  }

color AOIColor(int idx, int t)
  {
   if(g_syms[idx].data[t] != DATA_READY || g_syms[idx].aoiType[t] == AOI_NONE)
      return(C'95,100,115');
   if(g_syms[idx].aoiState[t] == AOI_SPENT) return(ColorAOISpent);
   return(g_syms[idx].aoiType[t] == AOI_DEMAND ? ColorDemand : ColorSupply);
  }

//+------------------------------------------------------------------+
//| Is this symbol sitting in (or right at) a live Weekly/Daily AOI?  |
//+------------------------------------------------------------------+
bool AtLiveAOI(int idx, int &whichTF)
  {
   whichTF = -1;
   for(int t = 0; t < 2; t++)
     {
      if(g_syms[idx].data[t] != DATA_READY)      continue;
      if(g_syms[idx].aoiType[t] == AOI_NONE)     continue;
      if(g_syms[idx].aoiState[t] == AOI_SPENT)   continue;
      if(g_syms[idx].aoiState[t] == AOI_INSIDE)  { whichTF = t; return(true); }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Entry column rendering.  When price is in no zone the entry        |
//| timeframes are not scanned at all, so they read "-" rather than    |
//| pretending to a verdict nobody asked for.                          |
//+------------------------------------------------------------------+
string EntryCellText(int idx, int e)
  {
   if(g_syms[idx].entryTF < 0)              return("-");
   if(g_syms[idx].eData[e] == DATA_LOADING) return("~load");
   if(g_syms[idx].eData[e] == DATA_MISSING) return("nodat");
   if(g_syms[idx].eData[e] != DATA_READY)   return("-");
   return(StateText(g_syms[idx].eSt[e]));
  }

color EntryCellColor(int idx, int e)
  {
   if(g_syms[idx].entryTF < 0 || g_syms[idx].eData[e] != DATA_READY)
      return(C'95,100,115');
   if(g_syms[idx].eSt[e] == ST_BULL) return(ColorBull);
   if(g_syms[idx].eSt[e] == ST_BEAR) return(ColorBear);
   return(ColorNeutral);
  }

string EntryText(int idx)
  {
   string tally = IntegerToString(g_syms[idx].entryConfirm) + "/" + IntegerToString(MAX_ENTRY);
   if(g_syms[idx].entrySig == ENTRY_LONG)  return("LONG "  + tally);
   if(g_syms[idx].entrySig == ENTRY_SHORT) return("SHORT " + tally);
   if(g_syms[idx].entryTF >= 0)            return("wait "  + tally);
   return("-");
  }

color EntryColor(int idx)
  {
   if(g_syms[idx].entrySig == ENTRY_LONG)  return(ColorEntryLong);
   if(g_syms[idx].entrySig == ENTRY_SHORT) return(ColorEntryShort);
   if(g_syms[idx].entryTF >= 0)            return(ColorNeutral);
   return(C'95,100,115');
  }

string RowLog(int idx)
  {
   string s = PadRight(g_syms[idx].symbol, COL_SYM_W) + " ";
   for(int t = 0; t < MAX_TF; t++) s = s + PadRight(CellText(idx, t), COL_T1_W) + " ";
   s = s + PadRight(SyncText(g_syms[idx].sync), COL_SYNC_W) + " ";
   s = s + PadRight(AgeText(idx), COL_AGE_W);
   if(g_scanAOI)
      s = s + " " + PadRight(AOIText(idx, 0), COL_AOI1_W) + " " + AOIText(idx, 1);
   if(g_scanEntries)
     {
      for(int e = 0; e < MAX_ENTRY; e++)
         s = s + " " + PadRight(EntryCellText(idx, e), COL_E1_W);
      s = s + " " + EntryText(idx);
     }
   return(s);
  }

bool RowVisible(int idx)
  {
   if(g_syms[idx].sync != SYNC_NONE) return(true);
   if(ShowOnlySynced) return(false);
   bool anyReady = false;
   for(int t = 0; t < MAX_TF; t++) if(g_syms[idx].data[t] == DATA_READY) anyReady = true;
   if(!anyReady && !ShowUnavailable) return(false);
   return(true);
  }

void RenderPanel()
  {
   g_charW = (int)MathRound((double)PanelFontSize * PanelCharFactor);
   if(g_charW < 3) g_charW = 3;
   g_lineH = PanelFontSize + 6;

   g_anchor       = ANCHOR_LEFT_UPPER;
   g_rightAligned = false;
   g_lowerCorner  = false;
   if(PanelCorner == 1) { g_anchor = ANCHOR_RIGHT_UPPER; g_rightAligned = true; }
   if(PanelCorner == 2) { g_anchor = ANCHOR_LEFT_LOWER;  g_lowerCorner  = true; }
   if(PanelCorner == 3) { g_anchor = ANCHOR_RIGHT_LOWER; g_rightAligned = true; g_lowerCorner = true; }

   EnsureBackground();

   int id = 0;

   // ---- stats --------------------------------------------------
   int nBull = 0, nBear = 0, nReady = 0, nPending = 0, nAtAOI = 0;
   int nEntryLong = 0, nEntryShort = 0;
   SortOrder();

   string bullList = "", bearList = "", aoiList = "";
   string entryLongList = "", entryShortList = "";
   for(int i = 0; i < g_symCount; i++)
     {
      int idx = g_order[i];
      if(g_syms[idx].sync == SYNC_BULL) { nBull++; bullList = bullList + (nBull > 1 ? "  " : "") + g_syms[idx].symbol; }
      if(g_syms[idx].sync == SYNC_BEAR) { nBear++; bearList = bearList + (nBear > 1 ? "  " : "") + g_syms[idx].symbol; }

      int at = -1;
      if(AtLiveAOI(idx, at))
        {
         nAtAOI++;
         aoiList = aoiList + (nAtAOI > 1 ? "  " : "") +
                   g_syms[idx].symbol + "(" + TFLabel(g_tfs[at]) + ")";
        }

      if(g_syms[idx].entrySig == ENTRY_LONG)
        {
         nEntryLong++;
         entryLongList = entryLongList + (nEntryLong > 1 ? "  " : "") +
                         g_syms[idx].symbol + "(" + TFLabel(g_tfs[g_syms[idx].entryTF]) + ")";
        }
      if(g_syms[idx].entrySig == ENTRY_SHORT)
        {
         nEntryShort++;
         entryShortList = entryShortList + (nEntryShort > 1 ? "  " : "") +
                          g_syms[idx].symbol + "(" + TFLabel(g_tfs[g_syms[idx].entryTF]) + ")";
        }

      int ready = 0;
      for(int t = 0; t < MAX_TF; t++) if(g_syms[idx].data[t] == DATA_READY) ready++;
      if(ready == MAX_TF) nReady++;
      else                nPending++;
     }

   // ---- header -------------------------------------------------
   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 0, "MARKET STRUCTURE SYNC SCANNER", ColorTitle, true);
   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 1,
         TFLabel(g_tfs[0]) + " + " + TFLabel(g_tfs[1]) + " + " + TFLabel(g_tfs[2]) +
         "    pivots:" + IntegerToString(g_pivotsPerSide) +
         "    fractal:" + IntegerToString(g_pivotLeft) + "/" + IntegerToString(g_pivotRight),
         ColorHeader, false);
   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 2,
         "symbols " + IntegerToString(g_symCount) +
         "    ready " + IntegerToString(nReady) +
         "    pending " + IntegerToString(nPending) +
         "    pass " + IntegerToString(g_generation) +
         "    " + TimeToString(TimeCurrent(), TIME_MINUTES | TIME_SECONDS),
         ColorNeutral, false);
   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 3, Repeat("-", TOTAL_CHARS), ColorBorder, false);

   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 4,
         "SYNC BULLISH (" + IntegerToString(nBull) + "): " + (nBull > 0 ? bullList : "none"),
         nBull > 0 ? ColorBull : ColorNeutral, false);
   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 5,
         "SYNC BEARISH (" + IntegerToString(nBear) + "): " + (nBear > 0 ? bearList : "none"),
         nBear > 0 ? ColorBear : ColorNeutral, false);

   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 6,
         "AT " + TFLabel(g_tfs[0]) + "/" + TFLabel(g_tfs[1]) + " AOI (" +
         IntegerToString(nAtAOI) + "): " + (nAtAOI > 0 ? aoiList : "none"),
         nAtAOI > 0 ? ColorTitle : ColorNeutral, false);

   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 7,
         "ENTRY LONG (" + IntegerToString(nEntryLong) + "): " +
         (g_scanEntries ? (nEntryLong > 0 ? entryLongList : "none") : "scanning off"),
         nEntryLong > 0 ? ColorEntryLong : ColorNeutral, false);
   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 8,
         "ENTRY SHORT (" + IntegerToString(nEntryShort) + "): " +
         (g_scanEntries ? (nEntryShort > 0 ? entryShortList : "none") : "scanning off"),
         nEntryShort > 0 ? ColorEntryShort : ColorNeutral, false);

   Place(id++, COL_SYM_OFF, TOTAL_CHARS, 9, Repeat("-", TOTAL_CHARS), ColorBorder, false);

   Place(id++, COL_SYM_OFF,  COL_SYM_W,  10, "SYMBOL", ColorHeader, false);
   Place(id++, COL_T1_OFF,   COL_T1_W,   10, TFLabel(g_tfs[0]), ColorHeader, false);
   Place(id++, COL_T2_OFF,   COL_T2_W,   10, TFLabel(g_tfs[1]), ColorHeader, false);
   Place(id++, COL_T3_OFF,   COL_T3_W,   10, TFLabel(g_tfs[2]), ColorHeader, false);
   Place(id++, COL_SYNC_OFF, COL_SYNC_W, 10, "SYNC",   ColorHeader, false);
   Place(id++, COL_AGE_OFF,  COL_AGE_W,  10, "AGE",    ColorHeader, false);
   if(g_scanAOI)
     {
      Place(id++, COL_AOI1_OFF, COL_AOI1_W, 10, TFLabel(g_tfs[0]) + " AOI", ColorHeader, false);
      Place(id++, COL_AOI2_OFF, COL_AOI2_W, 10, TFLabel(g_tfs[1]) + " AOI", ColorHeader, false);
     }
   if(g_scanEntries)
     {
      Place(id++, COL_E1_OFF,    COL_E1_W,    10, TFLabel(g_efs[0]), ColorHeader, false);
      Place(id++, COL_E2_OFF,    COL_E2_W,    10, TFLabel(g_efs[1]), ColorHeader, false);
      Place(id++, COL_E3_OFF,    COL_E3_W,    10, TFLabel(g_efs[2]), ColorHeader, false);
      Place(id++, COL_ENTRY_OFF, COL_ENTRY_W, 10, "ENTRY",           ColorHeader, false);
     }

   // ---- rows ---------------------------------------------------
   int row   = HEADER_ROWS;
   int shown = 0;
   for(int i = 0; i < g_symCount && shown < g_maxRows; i++)
     {
      int idx = g_order[i];
      if(!RowVisible(idx)) continue;

      Place(id++, COL_SYM_OFF, COL_SYM_W, row, g_syms[idx].symbol,
            g_syms[idx].sync != SYNC_NONE ? SyncColor(g_syms[idx].sync) : ColorHeader, false);

      for(int t = 0; t < MAX_TF; t++)
        {
         int off = (t == 0 ? COL_T1_OFF : (t == 1 ? COL_T2_OFF : COL_T3_OFF));
         Place(id++, off, COL_T1_W, row, CellText(idx, t), CellColor(idx, t), false);
        }

      Place(id++, COL_SYNC_OFF, COL_SYNC_W, row, SyncText(g_syms[idx].sync), SyncColor(g_syms[idx].sync), false);
      Place(id++, COL_AGE_OFF,  COL_AGE_W,  row, AgeText(idx), ColorNeutral, false);

      if(g_scanAOI)
        {
         Place(id++, COL_AOI1_OFF, COL_AOI1_W, row, AOIText(idx, 0), AOIColor(idx, 0), false);
         Place(id++, COL_AOI2_OFF, COL_AOI2_W, row, AOIText(idx, 1), AOIColor(idx, 1), false);
        }

      if(g_scanEntries)
        {
         for(int e = 0; e < MAX_ENTRY; e++)
           {
            int eoff = (e == 0 ? COL_E1_OFF : (e == 1 ? COL_E2_OFF : COL_E3_OFF));
            Place(id++, eoff, COL_E1_W, row,
                  EntryCellText(idx, e), EntryCellColor(idx, e), false);
           }
         Place(id++, COL_ENTRY_OFF, COL_ENTRY_W, row, EntryText(idx), EntryColor(idx), false);
        }

      row++;
      shown++;
     }

   if(shown == 0)
     {
      Place(id++, COL_SYM_OFF, TOTAL_CHARS, row,
            g_symCount == 0 ? "no symbol matches the current filter" : "no synced symbol yet",
            ColorNeutral, false);
      row++;
     }
   else if(shown < g_symCount)
     {
      Place(id++, COL_SYM_OFF, TOTAL_CHARS, row,
            "... " + IntegerToString(g_symCount - shown) + " more (raise PanelMaxRows)",
            C'95,100,115', false);
      row++;
     }

   // Upper bound on the label ids this pass can use, so HideFrom() covers every
   // label a previous pass may have written.  Header: at most 22 cells (10 text
   // rows + 6 always-on column labels + 2 AOI + 4 entry labels).  Body: at most
   // 12 cells per row (symbol + 3 timeframes + sync + age + 2 AOI + 3 entry
   // timeframes + entry verdict).  Plus 1 trailing message row.
   int pool = 22 + g_maxRows * 12 + 2;
   HideFrom(id, pool);
   SizeBackground(row + 1);
  }


//========================= CHART PIVOTS =============================
void ClearChartPivots()
  {
   ObjectsDeleteAll(0, PREFIX + "PH");
   ObjectsDeleteAll(0, PREFIX + "PL");
  }

//+------------------------------------------------------------------+
//| Weekly / Daily areas of interest for the chart symbol, drawn as  |
//| filled rectangles from the pivot bar out to the right.           |
//+------------------------------------------------------------------+
void ClearAOIZones()
  {
   ObjectsDeleteAll(0, PREFIX + "AOI");
  }

void DrawZone(string name, datetime t1, double top, double bot, color clr)
  {
   // Period() returns int in MQL4, so the cast is required before it reaches
   // an ENUM_TIMEFRAMES parameter - same reason OnInit casts it.
   long   ext = (long)PeriodSeconds((ENUM_TIMEFRAMES)Period()) * (long)g_aoiExtend;
   datetime t2 = (datetime)((long)t1 + ext);

   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, top, t2, bot)) return;
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);   // sit behind the candles
      ObjectSetInteger(0, name, OBJPROP_FILL,       true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
     }
   ObjectSetInteger(0, name, OBJPROP_TIME,  0, (long)t1);
   ObjectSetInteger(0, name, OBJPROP_TIME,  1, (long)t2);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 0, top);
   ObjectSetDouble (0, name, OBJPROP_PRICE, 1, bot);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

void DrawAOIZones()
  {
   ClearAOIZones();
   if(!g_scanAOI || !DrawAOIOnChart) return;

   string sym = Symbol();
   int    ci  = FindIdx(sym);
   if(ci < 0) return;                       // chart symbol is not in the scan list

   for(int t = 0; t < 2; t++)
     {
      if(g_syms[ci].data[t] != DATA_READY)  continue;
      if(g_syms[ci].aoiType[t] == AOI_NONE) continue;
      if(g_syms[ci].aoiState[t] == AOI_SPENT && !AOIShowSpent) continue;

      color clr = (g_syms[ci].aoiState[t] == AOI_SPENT) ? ColorAOISpent
                : (g_syms[ci].aoiType[t] == AOI_DEMAND  ? ColorDemand : ColorSupply);

      DrawZone(PREFIX + "AOI" + IntegerToString(t),
               g_syms[ci].aoiTime[t], g_syms[ci].aoiTop[t], g_syms[ci].aoiBot[t], clr);
     }
  }

//+------------------------------------------------------------------+
//| One-shot alert when price on this chart enters a live W1/D1 AOI.  |
//+------------------------------------------------------------------+
void CheckAOIAlert()
  {
   if(!g_scanAOI || !AOIAlertOnTouch) return;

   string sym = Symbol();
   int    ci  = FindIdx(sym);
   if(ci < 0) return;

   for(int t = 0; t < 2; t++)
     {
      int bit = (t == 0) ? 1 : 2;
      bool inside = (g_syms[ci].data[t] == DATA_READY &&
                     g_syms[ci].aoiType[t] != AOI_NONE &&
                     g_syms[ci].aoiState[t] == AOI_INSIDE);

      if(inside && (g_aoiAlerted & bit) == 0)
        {
         string kind = (g_syms[ci].aoiType[t] == AOI_DEMAND) ? "DEMAND" : "SUPPLY";
         int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         string msg = "AOI TOUCH | " + sym + " | " + TFLabel(g_tfs[t]) + " " + kind + " zone " +
                      DoubleToString(g_syms[ci].aoiBot[t], dg) + " - " +
                      DoubleToString(g_syms[ci].aoiTop[t], dg);
         if(AlertPopup) Alert(msg);
         if(AlertPush)  SendNotification(msg);
         if(AlertSound) PlaySound(AlertSoundFile);
         g_aoiAlerted = g_aoiAlerted | bit;
        }
      else if(!inside)
        {
         g_aoiAlerted = g_aoiAlerted & ~bit;   // re-arm once price leaves the zone
        }
     }
  }

//+------------------------------------------------------------------+
//| OBJ_ARROW uses ENUM_ARROW_ANCHOR (ANCHOR_TOP / ANCHOR_BOTTOM),   |
//| which is a different enum from the ENUM_ANCHOR_POINT used by     |
//| OBJ_LABEL - do not mix them.                                     |
//+------------------------------------------------------------------+
void DrawDot(string name, datetime t, double price, color clr, ENUM_ARROW_ANCHOR anchor)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_ARROW, 0, t, price)) return;
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE,  159);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
     }
   ObjectSetInteger(0, name, OBJPROP_TIME,   (long)t);
   ObjectSetDouble (0, name, OBJPROP_PRICE,  price);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_COLOR,  clr);
  }

void DrawChartPivots()
  {
   string          sym = Symbol();
   ENUM_TIMEFRAMES tf  = (ENUM_TIMEFRAMES)Period();

   int need = g_chartPivots;
   if(need < 2) need = 2;

   int total = iBars(sym, tf);
   if(total < MinBarsNeeded(g_pivotLeft, g_pivotRight, need)) { ClearChartPivots(); return; }

   int lookback = MathMin(g_lookback, total);

   double hi[], lo[];
   long   tm[];
   ArrayResize(hi, lookback);
   ArrayResize(lo, lookback);
   ArrayResize(tm, lookback);

   int valid = lookback;
   for(int i = 0; i < lookback; i++)
     {
      hi[i] = iHigh(sym, tf, i);
      lo[i] = iLow(sym, tf, i);
      tm[i] = (long)iTime(sym, tf, i);
      if(hi[i] <= 0.0 || lo[i] <= 0.0 || tm[i] <= 0) { valid = i; break; }
     }

   ClearChartPivots();
   if(valid < MinBarsNeeded(g_pivotLeft, g_pivotRight, need)) return;

   double hiP[], loP[];
   long   hiT[], loT[];
   int    hiS[], loS[];
   ArrayResize(hiP, need);
   ArrayResize(hiT, need);
   ArrayResize(hiS, need);
   ArrayResize(loP, need);
   ArrayResize(loT, need);
   ArrayResize(loS, need);

   if(CollectPivots(hi, lo, tm, valid, g_pivotLeft, g_pivotRight, need, valid,
                    hiP, hiT, hiS, loP, loT, loS) < need) return;

   for(int i = 0; i < need; i++)
     {
      // ANCHOR_TOP pins the top of the icon to the price, so the dot hangs
      // BELOW a swing high; ANCHOR_BOTTOM makes it sit ABOVE a swing low.
      DrawDot(PREFIX + "PH" + IntegerToString(i), (datetime)hiT[i], hiP[i], ColorSwingHigh, ANCHOR_TOP);
      DrawDot(PREFIX + "PL" + IntegerToString(i), (datetime)loT[i], loP[i], ColorSwingLow,  ANCHOR_BOTTOM);
     }
  }


//============================= EVENTS ===============================
int OnInit()
  {
   g_pivotLeft     = MathMax(1, PivotLeft);
   g_pivotRight    = MathMax(1, PivotRight);
   g_pivotsPerSide = MathMax(2, MathMin(MAX_PIVOTS, PivotsPerSide));
   g_lookback      = MathMax(40, MaxLookbackBars);
   g_maxAge        = MathMax(0, MaxSwingAgeBars);
   g_scanSeconds   = MathMax(2, RescanSeconds);
   g_perPass       = MathMax(1, SymbolsPerPass);
   g_cooldownSec   = MathMax(0, AlertCooldownMin) * 60;
   g_maxRows       = MathMax(1, PanelMaxRows);
   g_chartPivots   = MathMax(2, MathMin(60, ChartPivotCount));
   g_scope         = MathMax(0, MathMin(2, ScanScope));
   g_scanAOI       = ScanAOI;
   g_aoiExtend     = MathMax(5, MathMin(500, AOIExtendBars));

   g_scanEntries     = ScanEntries;
   g_entryMinConfirm = MathMax(1, MathMin(MAX_ENTRY, EntryMinConfirm));
   g_entryAllowTested = EntryAllowTested;

   g_tfs[0] = TF_High;
   g_tfs[1] = TF_Mid;
   g_tfs[2] = TF_Fast;

   g_efs[0] = TF_Entry1;
   g_efs[1] = TF_Entry2;
   g_efs[2] = TF_Entry3;

   IndicatorShortName("MSS " + TFLabel(g_tfs[0]) + "/" + TFLabel(g_tfs[1]) + "/" + TFLabel(g_tfs[2]));

   g_listDirty  = true;
   g_generation = 0;
   g_cursor     = 0;
   g_lastTotal  = -1;

   EventSetTimer(g_scanSeconds);
   RunPass();

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, PREFIX);
   ChartRedraw();
  }

void OnTimer()
  {
   RunPass();
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
   static datetime lastBar = 0;

   datetime cur = iTime(NULL, 0, 0);
   if(cur != lastBar)
     {
      lastBar = cur;
      // pick up symbols added to / removed from Market Watch
      if(g_scope != 2 && SymbolsTotal(g_scope == 0) != g_lastTotal) g_listDirty = true;
      RunPass();
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
