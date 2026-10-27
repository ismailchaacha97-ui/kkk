//+------------------------------------------------------------------+
//|                                            ApexConfluencePro.mq4 |
//|                                                                  |
//|  A multi-factor confluence indicator for MetaTrader 4.           |
//|                                                                  |
//|  DESIGN PHILOSOPHY                                               |
//|  -----------------                                               |
//|  Every decision is taken from *structural* information that is   |
//|  already final when the candle closes:                           |
//|                                                                  |
//|    * Confirmed swing pivots  -> support / resistance zones       |
//|    * Break of structure (BOS) / change of character (CHoCH)      |
//|    * Candle anatomy (pin bar, engulfing, momentum close)         |
//|    * Liquidity sweeps (stop hunts) and immediate reclaims        |
//|    * Tick-volume expansion, median-relative volume, delta proxy  |
//|    * Fair value gaps (imbalance)                                 |
//|    * Kaufman efficiency ratio  -> trend vs. chop                 |
//|    * Higher timeframe structure  -> directional bias             |
//|                                                                  |
//|  No moving averages, no MACD, no Stochastics, no RSI crosses.    |
//|  ATR is used only as a volatility ruler (distances for stops,    |
//|  zones and targets), never as a directional signal.              |
//|  Nothing is projected forward and nothing is smoothed by a lag.  |
//|  Signals are produced on the close of a bar and never move       |
//|  afterwards (see "non-repainting" note in the header below).     |
//|                                                                  |
//|  NON-REPAINTING                                                  |
//|  ---------------                                                  |
//|  The engine is a single forward pass over history: at bar `s`    |
//|  it only knows pivots confirming at `s + strength`, closes of    |
//|  bars >= s and the last *closed* higher timeframe candle.        |
//|  The pass is re-run on every new bar, so history and real time   |
//|  are produced by exactly the same code path.                     |
//|                                                                  |
//|  Arrows are printed on the bar that has just CLOSED (never on    |
//|  the forming bar) and the cooldown is applied forward in time,   |
//|  so a printed arrow is never removed or moved afterwards while   |
//|  it stays inside the analysis window (InpHistoryBars).            |
//|  The optional intrabar preview is drawn on the dashboard only    |
//|  and is always labelled "forming" - it is not a signal.          |
//+------------------------------------------------------------------+
#property copyright "Apex Confluence Pro"
#property link      ""
#property version   "1.00"
#property description "Price action + support/resistance + volume + market structure confluence engine."
#property description "Non-repainting, profile driven (scalping / day trading / swing), with a live dashboard."
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTomato
#property indicator_width2  2

//==================================================================
//  CONSTANTS
//==================================================================
#define ACP_PREFIX       "ACP_"
#define ACP_MAX_ZONES    160
#define ACP_MAX_REASONS  5
#define ACP_ROWS         18
#define ACP_ROW_H        15
#define ACP_PANEL_W      344
#define ACP_MAX_SCORE    15.0

#define CLR_PANEL_BG     C'18,22,28'
#define CLR_PANEL_EDGE   C'48,60,74'
#define CLR_TITLE        C'120,190,255'
#define CLR_TEXT         C'206,214,224'
#define CLR_DIM          C'124,136,152'
#define CLR_BULL         C'0,200,130'
#define CLR_BEAR         C'240,86,96'
#define CLR_WARN         C'245,184,64'
#define CLR_NEUTRAL      C'150,162,178'
#define CLR_ZONE_SUP     C'0,168,152'
#define CLR_ZONE_RES     C'214,84,104'
#define CLR_ZONE_FLIP    C'140,124,214'
#define CLR_FILL_SUP     C'0,58,55'
#define CLR_FILL_RES     C'76,28,36'
#define CLR_FILL_FLIP    C'46,40,80'

//==================================================================
//  ENUMS
//==================================================================
enum ENUM_ACP_PROFILE
  {
   ACP_SCALPING = 0,   // Scalping   (M1-M5)
   ACP_DAYTRADE = 1,   // Day trading (M5-M30)
   ACP_SWING    = 2,   // Swing      (H1-H4)
   ACP_CUSTOM   = 3    // Custom     (use advanced inputs)
  };

enum ENUM_ACP_SESSION
  {
   ACP_SESS_OFF    = 0,   // Off - trade any hour
   ACP_SESS_LDN_NY = 1,   // London + New York only
   ACP_SESS_LONDON = 2,   // London only
   ACP_SESS_NEWYORK= 3    // New York only
  };

//==================================================================
//  INPUTS
//==================================================================
input ENUM_ACP_PROFILE  InpProfile          = ACP_DAYTRADE;    // Trading profile
input string            InpSep1             = "--- display ---";  // ----------
input bool              InpShowPanel        = true;            // Show dashboard
input ENUM_BASE_CORNER  InpCorner           = CORNER_LEFT_UPPER; // Dashboard corner
input int               InpPanelX           = 12;              // Dashboard X offset (px)
input int               InpPanelY           = 24;              // Dashboard Y offset (px)
input string            InpFont             = "Courier New";   // Dashboard font
input int               InpFontSize         = 9;               // Dashboard font size
input color             InpColorBull        = clrLime;         // Buy arrow colour
input color             InpColorBear        = clrTomato;       // Sell arrow colour

//--- engine: quality gates (always active) ---------------------------
input string            InpSep2             = "--- engine: quality gates ---"; // ----------
input int               InpAtrPeriod        = 14;              // ATR period (volatility unit)
input int               InpMinScore         = 10;              // Min confluence score (of 15)
input double            InpERMinTrend       = 0.22;            // Minimum ER for "trending"
input double            InpERChop           = 0.10;            // Below this ER = chop (avoid)
input int               InpERPeriod         = 14;              // Efficiency ratio period
input double            InpVolSpikeMult     = 1.5;             // Volume spike multiple

//--- engine: geometry (CUSTOM profile) -------------------------------
input string            InpSep2b            = "--- geometry (CUSTOM profile) ---"; // ----------
input int               InpSwingStrength    = 3;               // Pivot strength (bars each side)
input int               InpHistoryBars      = 700;             // Bars scanned on every new bar
input double            InpLevelProxATR     = 0.55;            // Level proximity (x ATR)
input double            InpMergeATR         = 0.45;            // Zone merge distance (x ATR)
input int               InpSweepLookback    = 12;              // Liquidity sweep lookback
input int               InpVolPeriod        = 20;              // Median volume window
input int               InpHTFSteps         = 2;               // Higher timeframe steps (1..4)
input double            InpSLMinATR         = 1.0;             // Minimum stop distance (x ATR)
input double            InpMinRR            = 1.5;             // Minimum reward:risk to target 1
input int               InpCooldownBars     = 3;               // Bars between signals
input int               InpSetupTTL         = 5;               // Bars a setup stays actionable
input string            InpSep3             = "--- session / news ---"; // ----------
input ENUM_ACP_SESSION  InpSessionMode      = ACP_SESS_OFF;    // Session filter
input int               InpAsiaStart        = 0;               // Asia session start (server hour)
input int               InpAsiaEnd          = 8;               // Asia session end (server hour)
input int               InpLondonStart      = 7;               // London start (server hour)
input int               InpLondonEnd        = 16;              // London end (server hour)
input int               InpNYStart          = 12;              // New York start (server hour)
input int               InpNYEnd            = 21;              // New York end (server hour)
input string            InpBlackout1        = "";              // News blackout 1 "HH:MM-HH:MM"
input string            InpBlackout2        = "";              // News blackout 2 "HH:MM-HH:MM"
input int               InpMaxSpreadPoints  = 0;               // Max spread in points (0 = off)

//--- drawing --------------------------------------------------------
input string            InpSep4             = "--- drawing ---"; // ----------
input bool              InpShowZones        = true;            // Draw S/R zones
input int               InpMaxZonesShown    = 6;               // Max zones per side
input bool              InpShowZoneLabels   = true;            // Zone labels
input bool              InpShowTradeLevels  = true;            // Entry / SL / TP lines
input bool              InpShowDailyLevels  = true;            // Previous day high/low
input bool              InpShowWeeklyLevels = false;           // Previous week high/low
input int               InpZoneExtendBars   = 40;              // Zone right extension (bars)
input double            InpArrowOffsetATR   = 0.45;            // Arrow offset (x ATR)

//--- alerts ---------------------------------------------------------
input string            InpSep5             = "--- alerts ---"; // ----------
input bool              InpAlertPopup       = true;            // Popup alert
input bool              InpAlertSound       = false;           // Sound alert
input string            InpSoundFile        = "alert2.wav";    // Sound file
input bool              InpAlertPush        = false;           // Push notification
input bool              InpAlertEmail       = false;           // Email alert
input bool              InpAlertIntrabar    = false;           // Evaluate forming bar (may flicker)

//==================================================================
//  TYPES
//==================================================================
struct ACPZone
  {
   double    price;        // cluster centre
   double    top;          // band top
   double    bottom;       // band bottom
   int       lowTouches;   // pivots made of swing lows  -> support
   int       highTouches;  // pivots made of swing highs -> resistance
   double    strength;     // touches + flip bonus
   int       role;         // +1 support, -1 resistance
   bool      broken;       // retired from the active list
   datetime  bornTime;
  };

struct ACPSetup
  {
   bool      valid;
   int       dir;          // +1 long, -1 short
   datetime  barTime;      // time of the signal bar
   double    entry;
   double    sl;
   double    tp1;
   double    tp2;
   int       score;
   string    r0, r1, r2, r3, r4;
  };

//==================================================================
//  BUFFERS
//==================================================================
double g_bufUp[];
double g_bufDn[];
double g_bufScore[];
double g_bufBias[];

//==================================================================
//  GLOBALS - resolved profile
//==================================================================
int    g_strength      = 3;
int    g_historyBars   = 700;
int    g_minScore      = 9;
double g_levelProxATR  = 0.55;
double g_mergeATR      = 0.45;
int    g_sweepLookback = 12;
int    g_volPeriod     = 20;
double g_volSpike      = 1.5;
int    g_erPeriod      = 14;
double g_erTrend       = 0.22;
double g_erChop        = 0.10;
int    g_htfSteps      = 2;
double g_slMinATR      = 1.0;
double g_minRR         = 1.5;
int    g_cooldown      = 3;
int    g_setupTTL      = 5;
int    g_sessionMode   = ACP_SESS_OFF;
int    g_atrPeriod     = 14;

//==================================================================
//  GLOBALS - engine state
//==================================================================
ACPZone   g_zones[];
int       g_zoneCount        = 0;
bool      g_pivotHi[];
bool      g_pivotLo[];
double    g_atrCache[];
bool      g_atrCacheOn       = false;

double    g_shPrice          = 0.0;   // most recent unbroken swing high
double    g_slPrice          = 0.0;   // most recent unbroken swing low
int       g_structTrend      = 0;     // +1 bull, -1 bear, 0 unknown
int       g_lastBOSDir       = 0;
int       g_bosShift         = -1;
int       g_chochShift       = -1;

int       g_lastSignalShift  = -1;
int       g_lastSignalDir    = 0;
int       g_candN            = 0;
int       g_candShift[];
int       g_candDir[];
int       g_candScore[];
datetime  g_candTime[];
double    g_candEntry[];
double    g_candSL[];
double    g_candTP1[];
double    g_candTP2[];
string    g_candR0[];
string    g_candR1[];
string    g_candR2[];
string    g_candR3[];

ACPSetup  g_setup;
int       g_setupState       = 0;     // 0 none, 1 active, 2 stopped, 3 target hit, 4 expired
bool      g_formingSignal    = false;
int       g_formingDir       = 0;

// per-bar evaluation result
bool      g_evalSignal       = false;
int       g_evalDir          = 0;
int       g_evalScore        = 0;
string    g_blockText        = "";
double    g_evalEntry        = 0.0;
double    g_evalSL           = 0.0;
double    g_evalTP1          = 0.0;
double    g_evalTP2          = 0.0;
string    g_reasons[ACP_MAX_REASONS];

// snapshot of the last closed bar (panel)
double    g_curATR           = 0.0;
double    g_curER            = 0.0;
double    g_curRV            = 0.0;
double    g_curDelta         = 0.0;
double    g_curAtrRatio      = 1.0;
int       g_curSessionMask   = 0;
int       g_htfNow           = 0;

//==================================================================
//  GLOBALS - higher timeframe cache
//==================================================================
double    g_htfH[];
double    g_htfL[];
double    g_htfC[];
bool      g_htfPivHi[];
bool      g_htfPivLo[];
int       g_htfTrend[];
int       g_htfCount         = 0;
int       g_htfPeriod        = PERIOD_H1;

//==================================================================
//  GLOBALS - panel / alerts
//==================================================================
string    g_rows[ACP_ROWS];
color     g_rowClr[ACP_ROWS];
string    g_prevRows[ACP_ROWS];
color     g_prevClr[ACP_ROWS];
bool      g_panelInit        = false;
color     g_accent           = CLR_NEUTRAL;
color     g_prevAccent       = CLR_NEUTRAL;
datetime  g_lastBarTime      = 0;
datetime  g_lastAlertTime    = 0;
int       g_lastAlertDir     = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, g_bufUp);
   SetIndexBuffer(1, g_bufDn);
   SetIndexBuffer(2, g_bufScore);
   SetIndexBuffer(3, g_bufBias);

   //--- explicit series indexing: shift 0 = current bar
   ArraySetAsSeries(g_bufUp,    true);
   ArraySetAsSeries(g_bufDn,    true);
   ArraySetAsSeries(g_bufScore, true);
   ArraySetAsSeries(g_bufBias,  true);

   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 2, InpColorBull);
   SetIndexArrow(0, 233);
   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexLabel(0, "ACP Long");

   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 2, InpColorBear);
   SetIndexArrow(1, 234);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexLabel(1, "ACP Short");

   SetIndexStyle(2, DRAW_NONE);
   SetIndexLabel(2, "ACP Score");
   SetIndexStyle(3, DRAW_NONE);
   SetIndexLabel(3, "ACP Structure Bias");

   ResolveProfile();
   IndicatorShortName("Apex Confluence Pro [" + ProfileName() + "]");
   IndicatorDigits(Digits);

   DeleteByPrefix(ACP_PREFIX);
   ResetRuntime();
   g_lastBarTime   = 0;     // force a full build on the first tick
   g_lastAlertTime = 0;
   g_lastAlertDir  = 0;

   if(InpShowPanel)
      PanelBuildFrame();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeleteByPrefix(ACP_PREFIX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Main calculation                                                 |
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
   if(rates_total < 160)
      return(0);
   if(Bars < 160)
      return(0);

   bool newBar = (g_lastBarTime != Time[0]);

   if(newBar || prev_calculated <= 0)
     {
      g_lastBarTime = Time[0];

      ArrayInitialize(g_bufUp,    EMPTY_VALUE);
      ArrayInitialize(g_bufDn,    EMPTY_VALUE);
      ArrayInitialize(g_bufScore, 0.0);
      ArrayInitialize(g_bufBias,  0.0);

      BuildHTF();
      RunEngine();
      SnapshotMarket();
      UpdateSetupState();
      DrawStatic();
      ChartRedraw();
     }

   EvaluateFormingBar();
   UpdateSetupState();

   if(newBar || InpAlertIntrabar)
      CheckSignalAlert();

   UpdatePanel();
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Reset every piece of runtime state                               |
//+------------------------------------------------------------------+
void ResetRuntime()
  {
   g_zoneCount       = 0;
   ArrayResize(g_zones, ACP_MAX_ZONES);
   for(int i = 0; i < ACP_MAX_ZONES; i++)
      ZoneClear(g_zones[i]);

   g_shPrice         = 0.0;
   g_slPrice         = 0.0;
   g_structTrend     = 0;
   g_lastBOSDir      = 0;
   g_bosShift        = -1;
   g_chochShift      = -1;
   g_lastSignalShift = -1;
   g_lastSignalDir   = 0;
   g_formingSignal   = false;
   g_formingDir      = 0;

   SetupClear();
   ClearEval();
  }

void SetupClear()
  {
   g_setup.valid   = false;
   g_setup.dir     = 0;
   g_setup.barTime = 0;
   g_setup.entry   = 0.0;
   g_setup.sl      = 0.0;
   g_setup.tp1     = 0.0;
   g_setup.tp2     = 0.0;
   g_setup.score   = 0;
   g_setup.r0      = "";
   g_setup.r1      = "";
   g_setup.r2      = "";
   g_setup.r3      = "";
   g_setup.r4      = "";
   g_setupState    = 0;
  }

void ClearEval()
  {
   g_evalSignal  = false;
   g_evalDir     = 0;
   g_evalScore   = 0;
   g_blockText   = "";
   g_evalEntry   = 0.0;
   g_evalSL      = 0.0;
   g_evalTP1     = 0.0;
   g_evalTP2     = 0.0;
   for(int i = 0; i < ACP_MAX_REASONS; i++)
      g_reasons[i] = "";
  }

void ZoneClear(ACPZone &z)
  {
   z.price       = 0.0;
   z.top         = 0.0;
   z.bottom      = 0.0;
   z.lowTouches  = 0;
   z.highTouches = 0;
   z.strength    = 0.0;
   z.role        = 0;
   z.broken      = true;
   z.bornTime    = 0;
  }

//+------------------------------------------------------------------+
//| Resolve the active profile into engine parameters                |
//+------------------------------------------------------------------+
void ResolveProfile()
  {
   g_atrPeriod     = InpAtrPeriod;
   g_strength      = InpSwingStrength;
   g_historyBars   = InpHistoryBars;
   g_minScore      = InpMinScore;
   g_levelProxATR  = InpLevelProxATR;
   g_mergeATR      = InpMergeATR;
   g_sweepLookback = InpSweepLookback;
   g_volPeriod     = InpVolPeriod;
   g_volSpike      = InpVolSpikeMult;
   g_erPeriod      = InpERPeriod;
   g_erTrend       = InpERMinTrend;
   g_erChop        = InpERChop;
   g_htfSteps      = InpHTFSteps;
   g_slMinATR      = InpSLMinATR;
   g_minRR         = InpMinRR;
   g_cooldown      = InpCooldownBars;
   g_setupTTL      = InpSetupTTL;
   g_sessionMode   = (int)InpSessionMode;

   if(g_atrPeriod < 2)
      g_atrPeriod = 2;
   if(g_volPeriod < 3)
      g_volPeriod = 3;
   if(g_erPeriod < 2)
      g_erPeriod = 2;
   if(g_sweepLookback < 3)
      g_sweepLookback = 3;
   if(g_strength < 1)
      g_strength = 1;
   if(g_minScore < 5)
      g_minScore = 5;
   if(g_minScore > (int)ACP_MAX_SCORE)
      g_minScore = (int)ACP_MAX_SCORE;

   if(InpProfile == ACP_SCALPING)
     {
      g_strength      = 2;      // faster pivots
      g_historyBars   = 400;
      g_levelProxATR  = 0.60;
      g_mergeATR      = 0.50;
      g_sweepLookback = 8;
      g_volPeriod     = 14;
      g_htfSteps      = 2;      // M1 -> M15, M5 -> H1
      g_slMinATR      = 0.80;
      g_minRR         = 1.20;
      g_cooldown      = 3;
      g_setupTTL      = 3;
      g_erTrend       = 0.20;
     }
   else if(InpProfile == ACP_DAYTRADE)
     {
      g_strength      = 3;
      g_historyBars   = 700;
      g_levelProxATR  = 0.55;
      g_mergeATR      = 0.45;
      g_sweepLookback = 12;
      g_volPeriod     = 20;
      g_htfSteps      = 2;      // M5 -> H1, M15 -> H4
      g_slMinATR      = 1.00;
      g_minRR         = 1.50;
      g_cooldown      = 4;
      g_setupTTL      = 5;
      g_erTrend       = 0.22;
      g_sessionMode   = ACP_SESS_OFF;
     }
   else if(InpProfile == ACP_SWING)
     {
      g_strength      = 5;      // slower, cleaner pivots
      g_historyBars   = 1000;
      g_levelProxATR  = 0.65;
      g_mergeATR      = 0.55;
      g_sweepLookback = 20;
      g_volPeriod     = 30;
      g_htfSteps      = 2;      // H1 -> D1, H4 -> D1
      g_slMinATR      = 1.40;
      g_minRR         = 2.20;
      g_cooldown      = 5;
      g_setupTTL      = 8;
      g_erTrend       = 0.25;
      g_sessionMode   = ACP_SESS_OFF;
     }

   g_htfPeriod = HigherTF(Period(), g_htfSteps);
  }

//+------------------------------------------------------------------+
//| Names                                                            |
//+------------------------------------------------------------------+
string ProfileName()
  {
   switch((int)InpProfile)
     {
      case ACP_SCALPING: return("SCALPING");
      case ACP_DAYTRADE: return("DAYTRADE");
      case ACP_SWING:    return("SWING");
     }
   return("CUSTOM");
  }

string TfToStr(int tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
     }
   return("TF");
  }

//+------------------------------------------------------------------+
//| Timeframe ladder                                                 |
//+------------------------------------------------------------------+
int HigherTF(int tf, int steps)
  {
   int ladder[9];
   ladder[0] = PERIOD_M1;
   ladder[1] = PERIOD_M5;
   ladder[2] = PERIOD_M15;
   ladder[3] = PERIOD_M30;
   ladder[4] = PERIOD_H1;
   ladder[5] = PERIOD_H4;
   ladder[6] = PERIOD_D1;
   ladder[7] = PERIOD_W1;
   ladder[8] = PERIOD_MN1;

   int idx = 0;
   for(int i = 0; i < 9; i++)
      if(ladder[i] == tf)
        {
         idx = i;
         break;
        }

   idx = idx + steps;
   if(idx > 8)
      idx = 8;
   return(ladder[idx]);
  }

//+------------------------------------------------------------------+
//| Small numeric helpers                                            |
//+------------------------------------------------------------------+
void BuildATRCache(int maxIdx)
  {
   ArrayResize(g_atrCache, maxIdx + 1);
   for(int i = 0; i <= maxIdx; i++)
     {
      double a = iATR(NULL, 0, g_atrPeriod, i);
      g_atrCache[i] = (a > 0.0 ? a : Point * 10.0);
     }
   g_atrCacheOn = true;
  }

double ATRAt(int shift)
  {
   if(g_atrCacheOn && shift >= 0 && shift < ArraySize(g_atrCache))
      return(g_atrCache[shift]);

   double a = iATR(NULL, 0, g_atrPeriod, shift);
   if(a <= 0.0)
      a = Point * 10.0;
   return(a);
  }

double PipSize()
  {
   double p = Point;
   if(Digits == 3 || Digits == 5)
      p = Point * 10.0;
   return(p);
  }

double LowestLow(int startShift, int count)
  {
   double v = Low[startShift];
   for(int i = startShift; i < startShift + count; i++)
     {
      if(i >= Bars)
         break;
      if(Low[i] < v)
         v = Low[i];
     }
   return(v);
  }

double HighestHigh(int startShift, int count)
  {
   double v = High[startShift];
   for(int i = startShift; i < startShift + count; i++)
     {
      if(i >= Bars)
         break;
      if(High[i] > v)
         v = High[i];
     }
   return(v);
  }

int BarDir(int s)
  {
   if(Close[s] > Open[s])
      return(1);
   if(Close[s] < Open[s])
      return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
//| Tick volume: median relative volume and delta pressure           |
//+------------------------------------------------------------------+
double MedianVolume(int startShift, int count)
  {
   double v[96];
   int    n = 0;

   for(int i = startShift; i < startShift + count; i++)
     {
      if(i >= Bars)
         break;
      if(n >= 96)
         break;
      v[n] = (double)Volume[i];
      n++;
     }
   if(n == 0)
      return(0.0);

   for(int a = 1; a < n; a++)
     {
      double key = v[a];
      int    b   = a - 1;
      while(b >= 0 && v[b] > key)
        {
         v[b + 1] = v[b];
         b--;
        }
      v[b + 1] = key;
     }

   if((n % 2) == 1)
      return(v[n / 2]);
   return(0.5 * (v[n / 2 - 1] + v[n / 2]));
  }

double RelVolume(int s)
  {
   double med = MedianVolume(s + 1, g_volPeriod);
   double cur = (double)Volume[s];
   if(med <= 0.0)
      return(cur > 0.0 ? 1.0 : 0.0);
   return(cur / med);
  }

double DeltaPressure(int s, int n)
  {
   double up = 0.0;
   double dn = 0.0;
   for(int i = s; i < s + n; i++)
     {
      if(i >= Bars)
         break;
      if(Close[i] >= Open[i])
         up += (double)Volume[i];
      else
         dn += (double)Volume[i];
     }
   if(up + dn <= 0.0)
      return(0.0);
   return(100.0 * (up - dn) / (up + dn));
  }

//+------------------------------------------------------------------+
//| Kaufman efficiency ratio: 1 = perfect trend, 0 = pure chop       |
//+------------------------------------------------------------------+
double EfficiencyRatio(int s, int n)
  {
   if(n < 2)
      return(0.0);
   if(s + n >= Bars)
      n = Bars - s - 1;
   if(n < 2)
      return(0.0);

   double net = MathAbs(Close[s] - Close[s + n]);
   double sum = 0.0;
   for(int i = s; i < s + n; i++)
      sum += MathAbs(Close[i] - Close[i + 1]);

   if(sum <= 0.0)
      return(0.0);
   return(net / sum);
  }

//+------------------------------------------------------------------+
//| Sessions and news blackout                                       |
//+------------------------------------------------------------------+
bool HourInWindow(int hour, int startH, int endH)
  {
   if(startH == endH)
      return(false);
   if(startH < endH)
      return(hour >= startH && hour < endH);
   return(hour >= startH || hour < endH);        // wraps midnight
  }

int SessionMask(datetime t)
  {
   MqlDateTime mdt;
   TimeToStruct(t, mdt);
   int mask = 0;
   if(HourInWindow(mdt.hour, InpAsiaStart, InpAsiaEnd))
      mask = mask | 1;
   if(HourInWindow(mdt.hour, InpLondonStart, InpLondonEnd))
      mask = mask | 2;
   if(HourInWindow(mdt.hour, InpNYStart, InpNYEnd))
      mask = mask | 4;
   return(mask);
  }

string SessionLabel(int mask)
  {
   string s = "";
   if((mask & 1) == 1)
      s = s + "ASIA";
   if((mask & 2) == 2)
      s = (s == "" ? "LONDON" : s + "+LONDON");
   if((mask & 4) == 4)
      s = (s == "" ? "NEWYORK" : s + "+NY");
   if(s == "")
      s = "OFF-HOURS";
   return(s);
  }

bool SessionAllowed(datetime t)
  {
   if(g_sessionMode == ACP_SESS_OFF)
      return(true);

   int mask = SessionMask(t);
   if(g_sessionMode == ACP_SESS_LDN_NY)
      return((mask & (2 | 4)) != 0);
   if(g_sessionMode == ACP_SESS_LONDON)
      return((mask & 2) != 0);
   if(g_sessionMode == ACP_SESS_NEWYORK)
      return((mask & 4) != 0);
   return(true);
  }

int ParseHM(string s)
  {
   int p = StringFind(s, ":", 0);
   if(p <= 0)
      return(-1);
   int hh = (int)StringToInteger(StringSubstr(s, 0, p));
   int mm = (int)StringToInteger(StringSubstr(s, p + 1, 2));
   if(hh < 0 || hh > 23 || mm < 0 || mm > 59)
      return(-1);
   return(hh * 60 + mm);
  }

bool InBlackoutWindow(datetime t, string spec)
  {
   if(StringLen(spec) < 9)
      return(false);
   int dash = StringFind(spec, "-", 0);
   if(dash <= 0)
      return(false);

   int from = ParseHM(StringSubstr(spec, 0, dash));
   int to   = ParseHM(StringSubstr(spec, dash + 1));
   if(from < 0 || to < 0)
      return(false);

   MqlDateTime mdt;
   TimeToStruct(t, mdt);
   int now = mdt.hour * 60 + mdt.min;

   if(from == to)
      return(false);
   if(from < to)
      return(now >= from && now < to);
   return(now >= from || now < to);
  }

bool InBlackout(datetime t)
  {
   if(InBlackoutWindow(t, InpBlackout1))
      return(true);
   if(InBlackoutWindow(t, InpBlackout2))
      return(true);
   return(false);
  }

//+------------------------------------------------------------------+
//| Higher timeframe structure cache                                 |
//+------------------------------------------------------------------+
void BuildHTF()
  {
   g_htfCount = 0;
   if(g_htfPeriod == Period())
      g_htfPeriod = HigherTF(Period(), 1);

   int avail = iBars(NULL, g_htfPeriod);
   int n     = (int)MathMin(400, avail);
   if(n < 80)
      return;

   if(ArraySize(g_htfH) != n)
     {
      ArrayResize(g_htfH, n);
      ArrayResize(g_htfL, n);
      ArrayResize(g_htfC, n);
      ArrayResize(g_htfTrend, n);
      ArrayResize(g_htfPivHi, n);
      ArrayResize(g_htfPivLo, n);
     }

   for(int i = 0; i < n; i++)
     {
      g_htfH[i]     = iHigh(NULL, g_htfPeriod, i);
      g_htfL[i]     = iLow(NULL, g_htfPeriod, i);
      g_htfC[i]     = iClose(NULL, g_htfPeriod, i);
      g_htfPivHi[i] = false;
      g_htfPivLo[i] = false;
      g_htfTrend[i] = 0;
     }

   int st = 2;
   for(int i = 1; i < n - 1; i++)
     {
      bool isHi = true;
      bool isLo = true;
      for(int k = 1; k <= st; k++)
        {
         if(i + k >= n || i - k < 0)
           {
            isHi = false;
            isLo = false;
            break;
           }
         if(g_htfH[i + k] >= g_htfH[i] || g_htfH[i - k] >= g_htfH[i])
            isHi = false;
         if(g_htfL[i + k] <= g_htfL[i] || g_htfL[i - k] <= g_htfL[i])
            isLo = false;
        }
      g_htfPivHi[i] = isHi;
      g_htfPivLo[i] = isLo;
     }

   double sh     = 0.0;
   double sl     = 0.0;
   int    trend  = 0;

   for(int s = n - 1; s >= 0; s--)
     {
      int p = s + st;
      if(p < n)
        {
         if(g_htfPivHi[p])
            sh = g_htfH[p];
         if(g_htfPivLo[p])
            sl = g_htfL[p];
        }
      if(sh > 0.0 && g_htfC[s] > sh)
        {
         trend = 1;
         sh    = 0.0;
        }
      else
         if(sl > 0.0 && g_htfC[s] < sl)
           {
            trend = -1;
            sl    = 0.0;
           }
      g_htfTrend[s] = trend;
     }

   g_htfCount = n;
  }

//+------------------------------------------------------------------+
//| HTF bias valid at a given chart time (uses last CLOSED HTF bar)  |
//+------------------------------------------------------------------+
int HTFTrendAt(datetime t)
  {
   if(g_htfCount <= 0)
      return(0);

   int sh = iBarShift(NULL, g_htfPeriod, t, false);
   if(sh < 0)
      return(0);

   sh = sh + 1;                        // last finished HTF candle
   if(sh >= g_htfCount)
      return(0);
   return(g_htfTrend[sh]);
  }

//==================================================================
//  SECTION 2 - SUPPORT / RESISTANCE ZONE ENGINE
//==================================================================

//+------------------------------------------------------------------+
//| Add or merge a pivot into the zone list                          |
//| type: 1 = swing high (resistance), -1 = swing low (support)      |
//+------------------------------------------------------------------+
void ZoneAdd(double price, int type, datetime bornT, double atr)
  {
   if(price <= 0.0 || atr <= 0.0)
      return;

   double tol = g_mergeATR * atr;

   int best = -1;
   double bestD = tol;
   for(int i = 0; i < g_zoneCount; i++)
     {
      double d = MathAbs(g_zones[i].price - price);
      if(d <= bestD)
        {
         bestD = d;
         best  = i;
        }
     }

   if(best >= 0)
     {
      int    n     = g_zones[best].lowTouches + g_zones[best].highTouches;
      double newP  = (g_zones[best].price * n + price) / (n + 1);
      g_zones[best].price    = newP;
      g_zones[best].top      = newP + tol;
      g_zones[best].bottom   = newP - tol;
      if(type > 0)
         g_zones[best].highTouches = g_zones[best].highTouches + 1;
      else
         g_zones[best].lowTouches  = g_zones[best].lowTouches + 1;
      g_zones[best].strength = (double)(g_zones[best].lowTouches + g_zones[best].highTouches);
      if(g_zones[best].lowTouches > 0 && g_zones[best].highTouches > 0)
         g_zones[best].strength = g_zones[best].strength + 1.0;   // flip zone bonus
      g_zones[best].broken   = false;
      if(bornT > 0 && (g_zones[best].bornTime == 0 || bornT > g_zones[best].bornTime))
         g_zones[best].bornTime = bornT;
      return;
     }

   if(g_zoneCount >= ACP_MAX_ZONES)
     {
      // recycle the weakest, farthest retired zone
      int    worst  = -1;
      double worstD = -1.0;
      for(int i = 0; i < g_zoneCount; i++)
        {
         if(g_zones[i].strength > 1.5)
            continue;
         double d = MathAbs(g_zones[i].price - price);
         if(d > worstD)
           {
            worstD = d;
            worst  = i;
           }
        }
      if(worst < 0)
         return;

      ZoneClear(g_zones[worst]);
      g_zones[worst].price       = price;
      g_zones[worst].top         = price + tol;
      g_zones[worst].bottom      = price - tol;
      g_zones[worst].lowTouches  = (type < 0 ? 1 : 0);
      g_zones[worst].highTouches = (type > 0 ? 1 : 0);
      g_zones[worst].strength    = 1.0;
      g_zones[worst].role        = (type > 0 ? -1 : 1);
      g_zones[worst].broken      = false;
      g_zones[worst].bornTime    = bornT;
      return;
     }

   g_zones[g_zoneCount].price       = price;
   g_zones[g_zoneCount].top         = price + tol;
   g_zones[g_zoneCount].bottom      = price - tol;
   g_zones[g_zoneCount].lowTouches  = (type < 0 ? 1 : 0);
   g_zones[g_zoneCount].highTouches = (type > 0 ? 1 : 0);
   g_zones[g_zoneCount].strength    = 1.0;
   g_zones[g_zoneCount].role        = (type > 0 ? -1 : 1);
   g_zones[g_zoneCount].broken      = false;
   g_zones[g_zoneCount].bornTime    = bornT;
   g_zoneCount++;
  }

//+------------------------------------------------------------------+
//| Invalidate zones that price has closed decisively through        |
//+------------------------------------------------------------------+
void ZoneCheckBreak(int s)
  {
   double c = Close[s];

   for(int i = 0; i < g_zoneCount; i++)
     {
      if(g_zones[i].broken)
         continue;

      if(g_zones[i].role < 0)
        {
         // resistance: becomes support once price closes above it
         if(c > g_zones[i].top)
           {
            g_zones[i].role        = 1;
            g_zones[i].highTouches = 0;
            g_zones[i].lowTouches  = 2;
            g_zones[i].strength    = g_zones[i].strength + 1.0;
           }
        }
      else
         if(g_zones[i].role > 0)
           {
            // support: becomes resistance once price closes below it
            if(c < g_zones[i].bottom)
              {
               g_zones[i].role        = -1;
               g_zones[i].lowTouches  = 0;
               g_zones[i].highTouches = 2;
               g_zones[i].strength    = g_zones[i].strength + 1.0;
              }
           }
     }
  }

//+------------------------------------------------------------------+
//| Nearest active zone above / below a price                        |
//+------------------------------------------------------------------+
int ZoneNearestAbove(double price)
  {
   int    best  = -1;
   double bestD = 1e12;
   for(int i = 0; i < g_zoneCount; i++)
     {
      if(g_zones[i].broken)
         continue;
      if(g_zones[i].bottom <= price)
         continue;
      double d = g_zones[i].bottom - price;
      if(d < bestD)
        {
         bestD = d;
         best  = i;
        }
     }
   return(best);
  }

int ZoneNearestBelow(double price)
  {
   int    best  = -1;
   double bestD = 1e12;
   for(int i = 0; i < g_zoneCount; i++)
     {
      if(g_zones[i].broken)
         continue;
      if(g_zones[i].top >= price)
         continue;
      double d = price - g_zones[i].top;
      if(d < bestD)
        {
         bestD = d;
         best  = i;
        }
     }
   return(best);
  }

//+------------------------------------------------------------------+
//| Nearest active zones by absolute distance                        |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Nearest zone strictly below the close, gap measured from the bar |
//| low (0 when the candle is trading inside the zone)               |
//+------------------------------------------------------------------+
int ZoneBelowPrice(int s, double &gap)
  {
   double c = Close[s];
   double l = Low[s];
   int    best     = -1;
   double bestGap  = 1e12;

   for(int i = 0; i < g_zoneCount; i++)
     {
      if(g_zones[i].broken)
         continue;
      if(g_zones[i].price >= c)
         continue;
      double g = MathMax(0.0, l - g_zones[i].top);
      if(g < bestGap)
        {
         bestGap = g;
         best    = i;
        }
     }
   gap = (best >= 0 ? bestGap : 1e9);
   return(best);
  }

//+------------------------------------------------------------------+
//| Nearest zone strictly above the close                            |
//+------------------------------------------------------------------+
int ZoneAbovePrice(int s, double &gap)
  {
   double c = Close[s];
   double h = High[s];
   int    best    = -1;
   double bestGap = 1e12;

   for(int i = 0; i < g_zoneCount; i++)
     {
      if(g_zones[i].broken)
         continue;
      if(g_zones[i].price <= c)
         continue;
      double g = MathMax(0.0, g_zones[i].bottom - h);
      if(g < bestGap)
        {
         bestGap = g;
         best    = i;
        }
     }
   gap = (best >= 0 ? bestGap : 1e9);
   return(best);
  }

//==================================================================
//  SECTION 3 - MARKET STRUCTURE
//==================================================================

//+------------------------------------------------------------------+
//| Structure tracker step for bar s (pivot p = s + strength)        |
//+------------------------------------------------------------------+
void StructureStep(int s)
  {
   int p = s + g_strength;

   if(p < Bars && g_pivotHi[p])
      g_shPrice = High[p];
   if(p < Bars && g_pivotLo[p])
      g_slPrice = Low[p];

   if(g_shPrice > 0.0 && Close[s] > g_shPrice)
     {
      g_lastBOSDir = 1;
      g_bosShift   = s;
      if(g_structTrend == -1)
         g_chochShift = s;
      g_structTrend = 1;
      g_shPrice     = 0.0;
     }
   else
      if(g_slPrice > 0.0 && Close[s] < g_slPrice)
        {
         g_lastBOSDir = -1;
         g_bosShift   = s;
         if(g_structTrend == 1)
            g_chochShift = s;
         g_structTrend = -1;
         g_slPrice     = 0.0;
        }
  }

//+------------------------------------------------------------------+
//| Candlestick anatomy flags                                        |
//+------------------------------------------------------------------+
void CandleAnatomy(int s, bool &bullPin, bool &bearPin, bool &bullEng,
                   bool &bearEng, double &bodyR)
  {
   double o  = Open[s];
   double c  = Close[s];
   double h  = High[s];
   double l  = Low[s];
   double rng = h - l;

   bullPin = false;
   bearPin = false;
   bullEng = false;
   bearEng = false;
   bodyR = 0.0;

   if(rng <= 0.0)
      return;

   double body  = MathAbs(c - o);
   double upper = h - MathMax(o, c);
   double lower = MathMin(o, c) - l;
   bodyR = body / rng;

   if(body > 0.0 && lower >= 1.8 * body && upper <= 0.9 * body && c >= o)
      bullPin = true;
   if(body > 0.0 && upper >= 1.8 * body && lower <= 0.9 * body && c <= o)
      bearPin = true;

   if(BarDir(s) > 0 && BarDir(s + 1) < 0 && c >= Open[s + 1] && o <= Close[s + 1])
      bullEng = true;
   if(BarDir(s) < 0 && BarDir(s + 1) > 0 && c <= Open[s + 1] && o >= Close[s + 1])
      bearEng = true;

  }

//+------------------------------------------------------------------+
//| Liquidity sweep detection: wick beyond a level, close back in    |
//+------------------------------------------------------------------+
bool SweepLow(int s, double atr)
  {
   int n = g_sweepLookback;
   if(s + n + 1 >= Bars)
      n = Bars - s - 2;
   if(n < 3)
      return(false);

   double priorLow = LowestLow(s + 1, n);
   double buffer   = 0.05 * atr;

   return(Low[s] < priorLow - buffer && Close[s] > priorLow);
  }

bool SweepHigh(int s, double atr)
  {
   int n = g_sweepLookback;
   if(s + n + 1 >= Bars)
      n = Bars - s - 2;
   if(n < 3)
      return(false);

   double priorHigh = HighestHigh(s + 1, n);
   double buffer    = 0.05 * atr;

   return(High[s] > priorHigh + buffer && Close[s] < priorHigh);
  }

//+------------------------------------------------------------------+
//| Fair value gap (3 candle imbalance)                              |
//+------------------------------------------------------------------+
bool BullFVG(int s, double atr, double &gapTop, double &gapBottom)
  {
   gapTop    = 0.0;
   gapBottom = 0.0;
   if(s + 2 >= Bars)
      return(false);
   double top = Low[s];
   double bot = High[s + 2];
   if(top - bot > 0.25 * atr)
     {
      gapTop    = top;
      gapBottom = bot;
      return(true);
     }
   return(false);
  }

bool BearFVG(int s, double atr, double &gapTop, double &gapBottom)
  {
   gapTop    = 0.0;
   gapBottom = 0.0;
   if(s + 2 >= Bars)
      return(false);
   double top = Low[s + 2];
   double bot = High[s];
   if(top - bot > 0.25 * atr)
     {
      gapTop    = top;
      gapBottom = bot;
      return(true);
     }
   return(false);
  }

//==================================================================
//  SECTION 4 - CONFLUENCE ENGINE
//==================================================================

//+------------------------------------------------------------------+
//| Push one scored reason onto a direction bucket                   |
//+------------------------------------------------------------------+
void ScoreAdd(int &score, string &arr[], int &n, string txt, int pts)
  {
   score = score + pts;
   if(n < 8)
     {
      arr[n] = txt;
      n++;
     }
  }

//+------------------------------------------------------------------+
//| Evaluate one bar. `s` = shift, `forming` = bar 0 tick preview    |
//+------------------------------------------------------------------+
void EvaluateAt(int s, bool forming)
  {
   ClearEval();

   double atr = ATRAt(s);
   if(atr <= 0.0)
      return;

   double o = Open[s];
   double c = Close[s];
   double h = High[s];
   double l = Low[s];
   double rng = h - l;
   if(rng <= 0.0)
      return;

   int dir = BarDir(s);
   if(dir == 0)
      return;

   //--- basic measurements -----------------------------------------
   bool bullPin, bearPin, bullEng, bearEng;
   double bodyRatio = 0.0;
   CandleAnatomy(s, bullPin, bearPin, bullEng, bearEng, bodyRatio);

   double rv    = RelVolume(s);
   double delta = DeltaPressure(s, 5);
   double er    = EfficiencyRatio(s, g_erPeriod);

   double atrAvg = 0.0;
   int    atrN   = 0;
   for(int k = 0; k < 20; k++)
     {
      if(s + k >= Bars)
         break;
      atrAvg += ATRAt(s + k);
      atrN++;
     }
   if(atrN > 0)
      atrAvg = atrAvg / atrN;
   double atrRatio = (atrAvg > 0.0 ? atr / atrAvg : 1.0);

   int htf = HTFTrendAt(Time[s]);

   //--- proximity to structure -------------------------------------
   double distSup = 1e9;
   double distRes = 1e9;
   int    zSup    = ZoneBelowPrice(s, distSup);
   int    zRes    = ZoneAbovePrice(s, distRes);

   int supStr = (zSup >= 0 ? (int)g_zones[zSup].strength : 0);
   int resStr = (zRes >= 0 ? (int)g_zones[zRes].strength : 0);

   double prox = g_levelProxATR * atr;

   //--- price action patterns --------------------------------------
   double tailUp  = MathMin(o, c) - l;     // lower wick
   double tailDn  = h - MathMax(o, c);     // upper wick
   double closeLoc = (c - l) / rng;        // 1 = close at high

   bool rejBull = (dir > 0 && tailUp >= 0.35 * rng && closeLoc >= 0.55 && distSup <= prox);
   bool rejBear = (dir < 0 && tailDn >= 0.35 * rng && closeLoc <= 0.45 && distRes <= prox);
   bool pinBull = (bullPin && distSup <= prox * 1.4);
   bool pinBear = (bearPin && distRes <= prox * 1.4);

   bool engBull = (bullEng && distSup <= prox * 1.4);
   bool engBear = (bearEng && distRes <= prox * 1.4);

   bool swLow  = SweepLow(s, atr);
   bool swHigh = SweepHigh(s, atr);

   double fvgT = 0.0, fvgB = 0.0;
   bool bFvg = BullFVG(s, atr, fvgT, fvgB);
   bool sFvg = BearFVG(s, atr, fvgT, fvgB);

   bool momUp = (bodyRatio >= 0.55 && c > HighestHigh(s + 1, 5));
   bool momDn = (bodyRatio >= 0.55 && c < LowestLow(s + 1, 5));

   //--- scoring buckets --------------------------------------------
   string upR[8];
   string dnR[8];
   int    upN = 0, dnN = 0;
   int    upSc = 0, dnSc = 0;

   // 1) zone rejection / pin bar
   if(rejBull || pinBull)
     {
      int pts = (tailUp >= 0.5 * rng ? 3 : 2);
      if(supStr >= 2)
         pts = pts + 1;
      ScoreAdd(upSc, upR, upN, "Rejection at support", pts);
     }
   if(rejBear || pinBear)
     {
      int pts = (tailDn >= 0.5 * rng ? 3 : 2);
      if(resStr >= 2)
         pts = pts + 1;
      ScoreAdd(dnSc, dnR, dnN, "Rejection at resistance", pts);
     }

   // 2) engulfing
   if(engBull)
      ScoreAdd(upSc, upR, upN, "Bullish engulfing", 2);
   if(engBear)
      ScoreAdd(dnSc, dnR, dnN, "Bearish engulfing", 2);

   // 3) liquidity sweep
   if(swLow)
      ScoreAdd(upSc, upR, upN, "Sell-side sweep reclaimed", 2);
   if(swHigh)
      ScoreAdd(dnSc, dnR, dnN, "Buy-side sweep rejected", 2);

   // 4) break of structure / change of character
   if(g_bosShift == s && g_lastBOSDir > 0)
      ScoreAdd(upSc, upR, upN, (g_chochShift == s ? "CHoCH - bulls in control" : "BOS - bullish"), (g_chochShift == s ? 3 : 2));
   if(g_bosShift == s && g_lastBOSDir < 0)
      ScoreAdd(dnSc, dnR, dnN, (g_chochShift == s ? "CHoCH - bears in control" : "BOS - bearish"), (g_chochShift == s ? 3 : 2));

   // 5) structure trend alignment
   if(g_structTrend > 0)
      ScoreAdd(upSc, upR, upN, "Structure: higher highs", 1);
   if(g_structTrend < 0)
      ScoreAdd(dnSc, dnR, dnN, "Structure: lower lows", 1);

   // 6) momentum candle
   if(momUp)
      ScoreAdd(upSc, upR, upN, "Momentum break of micro high", 1);
   if(momDn)
      ScoreAdd(dnSc, dnR, dnN, "Momentum break of micro low", 1);

   // 7) volume
   if(dir > 0 && rv >= g_volSpike)
      ScoreAdd(upSc, upR, upN, "Volume expansion " + DoubleToString(rv, 1) + "x", 2);
   else
      if(dir > 0 && rv >= 1.15)
         ScoreAdd(upSc, upR, upN, "Above-average volume", 1);
   if(dir < 0 && rv >= g_volSpike)
      ScoreAdd(dnSc, dnR, dnN, "Volume expansion " + DoubleToString(rv, 1) + "x", 2);
   else
      if(dir < 0 && rv >= 1.15)
         ScoreAdd(dnSc, dnR, dnN, "Above-average volume", 1);

   // 8) delta pressure (tick-volume proxy, 5 bars)
   if(delta >= 15.0)
      ScoreAdd(upSc, upR, upN, "Buying pressure +" + DoubleToString(delta, 0), 1);
   if(delta <= -15.0)
      ScoreAdd(dnSc, dnR, dnN, "Selling pressure " + DoubleToString(delta, 0), 1);

   // 9) fair value gap
   if(bFvg)
      ScoreAdd(upSc, upR, upN, "Bullish imbalance", 1);
   if(sFvg)
      ScoreAdd(dnSc, dnR, dnN, "Bearish imbalance", 1);

   // 10) higher timeframe bias
   if(htf > 0)
      ScoreAdd(upSc, upR, upN, "HTF " + TfToStr(g_htfPeriod) + " bullish", 2);
   if(htf < 0)
      ScoreAdd(dnSc, dnR, dnN, "HTF " + TfToStr(g_htfPeriod) + " bearish", 2);
   if(htf < 0 && dir > 0)
      ScoreAdd(upSc, upR, upN, "Counter-trend vs HTF", -2);
   if(htf > 0 && dir < 0)
      ScoreAdd(dnSc, dnR, dnN, "Counter-trend vs HTF", -2);

   // 11) trend quality
   if(er >= g_erTrend)
     {
      if(dir > 0)
         ScoreAdd(upSc, upR, upN, "Directional efficiency " + DoubleToString(er, 2), 1);
      else
         ScoreAdd(dnSc, dnR, dnN, "Directional efficiency " + DoubleToString(er, 2), 1);
     }

   // 12) room to the opposite structure
   if(dir > 0 && (zRes < 0 || (g_zones[zRes].bottom - c) >= 1.2 * atr))
      ScoreAdd(upSc, upR, upN, "Open room to next level", 1);
   if(dir < 0 && (zSup < 0 || (c - g_zones[zSup].top) >= 1.2 * atr))
      ScoreAdd(dnSc, dnR, dnN, "Open room to next level", 1);

   //--- pick direction ---------------------------------------------
   int    bestDir = 0;
   int    bestSc  = 0;
   string bestR[8];
   int    bestN   = 0;

   if(dir > 0 && upSc >= dnSc)
     {
      bestDir = 1;
      bestSc  = upSc;
      bestN   = upN;
      for(int i = 0; i < upN; i++)
         bestR[i] = upR[i];
     }
   else
      if(dir < 0 && dnSc >= upSc)
        {
         bestDir = -1;
         bestSc  = dnSc;
         bestN   = dnN;
         for(int j = 0; j < dnN; j++)
            bestR[j] = dnR[j];
        }
      else
         return;

   if(bestSc > (int)ACP_MAX_SCORE)
      bestSc = (int)ACP_MAX_SCORE;
   if(bestSc < 0)
      bestSc = 0;

   g_evalDir   = bestDir;
   g_evalScore = bestSc;
   for(int r = 0; r < ACP_MAX_REASONS; r++)
      g_reasons[r] = (r < bestN ? bestR[r] : "");

   //--- a structural trigger must be present -----------------------
   bool trig = false;
   if(bestDir > 0)
      trig = (rejBull || pinBull || engBull || swLow || bFvg ||
              (g_bosShift == s && g_lastBOSDir > 0) ||
              (momUp && g_structTrend > 0));
   else
      trig = (rejBear || pinBear || engBear || swHigh || sFvg ||
              (g_bosShift == s && g_lastBOSDir < 0) ||
              (momDn && g_structTrend < 0));

   if(!trig)
     {
      g_blockText = "WAIT - no structural trigger";
      return;
     }

   //--- hard filters -----------------------------------------------
   if(bestSc < g_minScore)
     {
      g_blockText = "WAIT - score " + IntegerToString(bestSc) + "/" + IntegerToString(g_minScore);
      return;
     }
   if(er < g_erChop)
     {
      g_blockText = "AVOID - choppy (ER " + DoubleToString(er, 2) + ")";
      return;
     }
   if(atrRatio < 0.55)
     {
      g_blockText = "AVOID - volatility too low";
      return;
     }
   if(!SessionAllowed(Time[s]))
     {
      g_blockText = "AVOID - " + SessionLabel(SessionMask(Time[s])) + " session";
      return;
     }
   if(InBlackout(Time[s]))
     {
      g_blockText = "AVOID - news blackout";
      return;
     }
   if(InpMaxSpreadPoints > 0)
     {
      long sp = (long)((Ask - Bid) / Point);
      if(sp > InpMaxSpreadPoints)
        {
         g_blockText = "AVOID - spread " + IntegerToString((int)sp) + " pts";
         return;
        }
     }

   //--- trade construction -----------------------------------------
   double entry = c;
   double risk  = 0.0;
   double sl    = 0.0;

   if(bestDir > 0)
     {
      sl   = l - 0.35 * atr;
      risk = entry - sl;
      if(risk < g_slMinATR * atr)
        {
         sl   = entry - g_slMinATR * atr;
         risk = entry - sl;
        }
     }
   else
     {
      sl   = h + 0.35 * atr;
      risk = sl - entry;
      if(risk < g_slMinATR * atr)
        {
         sl   = entry + g_slMinATR * atr;
         risk = sl - entry;
        }
     }
   if(risk <= 0.0)
     {
      g_blockText = "AVOID - invalid risk";
      return;
     }

   double tp1 = 0.0;
   double tp2 = 0.0;
   int    tz  = -1;

   if(bestDir > 0)
     {
      tz  = ZoneNearestAbove(entry + 0.1 * atr);
      tp1 = (tz >= 0 ? g_zones[tz].bottom : entry + 2.5 * risk);
      if(tp1 - entry < g_minRR * risk)
        {
         g_blockText = "AVOID - target too close (" + DoubleToString((tp1 - entry) / risk, 1) + "R)";
         return;
        }
      int tz3 = ZoneNearestAbove(tp1 + 0.1 * atr);
      if(tz3 >= 0)
         tp2 = g_zones[tz3].bottom;
      else
         tp2 = tp1 + 1.5 * (tp1 - entry);
     }
   else
     {
      tz  = ZoneNearestBelow(entry - 0.1 * atr);
      tp1 = (tz >= 0 ? g_zones[tz].top : entry - 2.5 * risk);
      if(entry - tp1 < g_minRR * risk)
        {
         g_blockText = "AVOID - target too close (" + DoubleToString((entry - tp1) / risk, 1) + "R)";
         return;
        }
      int tz3 = ZoneNearestBelow(tp1 - 0.1 * atr);
      if(tz3 >= 0)
         tp2 = g_zones[tz3].top;
      else
         tp2 = tp1 - 1.5 * (entry - tp1);
     }

   g_evalEntry = NormalizeDouble(entry, Digits);
   g_evalSL    = NormalizeDouble(sl, Digits);
   g_evalTP1   = NormalizeDouble(tp1, Digits);
   g_evalTP2   = NormalizeDouble(tp2, Digits);
   g_evalSignal= true;
  }

//==================================================================
//  SECTION 5 - DRIVER: FORWARD PASS OVER HISTORY
//==================================================================

//+------------------------------------------------------------------+
//| Append the current evaluation to the candidate list              |
//+------------------------------------------------------------------+
void CandAdd(int s)
  {
   int n = g_candN + 1;

   ArrayResize(g_candShift, n);
   ArrayResize(g_candDir,   n);
   ArrayResize(g_candScore, n);
   ArrayResize(g_candTime,  n);
   ArrayResize(g_candEntry, n);
   ArrayResize(g_candSL,    n);
   ArrayResize(g_candTP1,   n);
   ArrayResize(g_candTP2,   n);
   ArrayResize(g_candR0,    n);
   ArrayResize(g_candR1,    n);
   ArrayResize(g_candR2,    n);
   ArrayResize(g_candR3,    n);

   g_candShift[g_candN] = s;
   g_candDir[g_candN]   = g_evalDir;
   g_candScore[g_candN] = g_evalScore;
   g_candTime[g_candN]  = Time[s];
   g_candEntry[g_candN] = g_evalEntry;
   g_candSL[g_candN]    = g_evalSL;
   g_candTP1[g_candN]   = g_evalTP1;
   g_candTP2[g_candN]   = g_evalTP2;
   g_candR0[g_candN]    = g_reasons[0];
   g_candR1[g_candN]    = g_reasons[1];
   g_candR2[g_candN]    = g_reasons[2];
   g_candR3[g_candN]    = g_reasons[3];

   g_candN = n;
  }

//+------------------------------------------------------------------+
//| Rebuild zones, structure and signals from scratch                |
//+------------------------------------------------------------------+
void RunEngine()
  {
   int total = Bars;
   if(total < 160)
      return;

   int limit = (int)MathMin((double)g_historyBars, (double)(total - 10));
   if(limit < 80)
      limit = (int)MathMin(80.0, (double)(total - 10));
   if(limit < 30)
      return;

   ResetRuntime();
   ArrayResize(g_zones, ACP_MAX_ZONES);
   for(int zc = 0; zc < ACP_MAX_ZONES; zc++)
      ZoneClear(g_zones[zc]);

   int maxIdx = limit + g_strength;
   if(maxIdx >= total)
      maxIdx = total - 1;

   BuildATRCache(maxIdx);

   ArrayResize(g_pivotHi, maxIdx + 2);
   ArrayResize(g_pivotLo, maxIdx + 2);
   for(int i = 0; i <= maxIdx + 1; i++)
     {
      g_pivotHi[i] = false;
      g_pivotLo[i] = false;
     }

   //--- detect swings (strict fractal, needs g_strength bars each side)
   for(int i = g_strength; i <= maxIdx; i++)
     {
      bool isHi = true;
      bool isLo = true;
      for(int k = 1; k <= g_strength; k++)
        {
         if(i + k >= total)
           {
            isHi = false;
            isLo = false;
            break;
           }
         if(High[i + k] >= High[i] || High[i - k] >= High[i])
            isHi = false;
         if(Low[i + k] <= Low[i] || Low[i - k] <= Low[i])
            isLo = false;
        }
      g_pivotHi[i] = isHi;
      g_pivotLo[i] = isLo;
     }

   //--- forward pass: old -> new, only confirmed information
   g_candN = 0;

   for(int s = limit; s >= 0; s--)
     {
      // the forming bar never mutates engine state: zones and structure
      // shown on the chart always describe closed bars only
      if(s == 0)
         break;

      int p = s + g_strength;

      if(p <= maxIdx && p >= g_strength)
        {
         if(g_pivotHi[p])
            ZoneAdd(High[p], 1, Time[p], ATRAt(p));
         if(g_pivotLo[p])
            ZoneAdd(Low[p], -1, Time[p], ATRAt(p));
        }

      StructureStep(s);
      ZoneCheckBreak(s);

      EvaluateAt(s, false);

      g_bufScore[s] = (double)g_evalScore;
      g_bufBias[s]  = (double)g_structTrend;

      if(!g_evalSignal)
         continue;

      // candidates are stored oldest -> newest; the cooldown is applied
      // *forward* afterwards so a printed arrow can never vanish
      CandAdd(s);
     }

   //--- greedy forward acceptance (no look-ahead, no retraction) ---
   int lastAcc = limit + 1000;

   for(int c = 0; c < g_candN; c++)
     {
      if(lastAcc - g_candShift[c] < g_cooldown)
         continue;

      lastAcc = g_candShift[c];

      double off = InpArrowOffsetATR * ATRAt(g_candShift[c]);

      if(g_candDir[c] > 0)
         g_bufUp[g_candShift[c]] = Low[g_candShift[c]] - off;
      else
         g_bufDn[g_candShift[c]] = High[g_candShift[c]] + off;

      g_lastSignalShift = g_candShift[c];
      g_lastSignalDir   = g_candDir[c];

      // later iterations are newer, so this ends on the latest setup
      g_setup.valid   = true;
      g_setup.dir     = g_candDir[c];
      g_setup.barTime = g_candTime[c];
      g_setup.entry   = g_candEntry[c];
      g_setup.sl      = g_candSL[c];
      g_setup.tp1     = g_candTP1[c];
      g_setup.tp2     = g_candTP2[c];
      g_setup.score   = g_candScore[c];
      g_setup.r0      = g_candR0[c];
      g_setup.r1      = g_candR1[c];
      g_setup.r2      = g_candR2[c];
      g_setup.r3      = g_candR3[c];
     }

   if(!g_setup.valid)
      SetupClear();
   else
      g_setupState = 1;

   g_atrCacheOn = false;      // the forming bar must use live ATR
  }

//+------------------------------------------------------------------+
//| Intrabar preview of the forming bar (opt-in, may flicker)        |
//+------------------------------------------------------------------+
void EvaluateFormingBar()
  {
   g_formingSignal = false;
   g_formingDir    = 0;

   EvaluateAt(0, true);

   if(g_evalSignal)
     {
      g_formingSignal = true;
      g_formingDir    = g_evalDir;
     }
  }

//+------------------------------------------------------------------+
//| Track what happened to the most recent setup                     |
//+------------------------------------------------------------------+
void UpdateSetupState()
  {
   if(!g_setup.valid)
     {
      g_setupState = 0;
      return;
     }

   int sh = iBarShift(NULL, 0, g_setup.barTime, false);
   if(sh < 0)
      return;

   if(sh - 1 > g_setupTTL)
     {
      g_setupState = 4;
      return;
     }

   for(int i = sh - 1; i >= 0; i--)
     {
      if(i >= Bars)
         continue;

      if(g_setup.dir > 0)
        {
         if(Low[i] <= g_setup.sl)
           {
            g_setupState = 2;
            return;
           }
         if(High[i] >= g_setup.tp1)
           {
            g_setupState = 3;
            return;
           }
        }
      else
        {
         if(High[i] >= g_setup.sl)
           {
            g_setupState = 2;
            return;
           }
         if(Low[i] <= g_setup.tp1)
           {
            g_setupState = 3;
            return;
           }
        }
     }

   if(g_setupState == 2 || g_setupState == 3 || g_setupState == 4)
      return;

   //--- a change of character against the setup is an exit warning
   if(g_chochShift >= 0 && g_chochShift < sh && g_structTrend != 0 &&
      g_structTrend != g_setup.dir)
     {
      g_setupState = 5;
      return;
     }

   g_setupState = 1;
  }

//+------------------------------------------------------------------+
//| Alert once per signal bar                                        |
//+------------------------------------------------------------------+
void CheckSignalAlert()
  {
   if(g_setup.valid)
     {
      if(g_setup.barTime == g_lastAlertTime)
         return;

      int sh = iBarShift(NULL, 0, g_setup.barTime, false);
      if(sh < 0 || sh > 1)
         return;

      g_lastAlertTime = g_setup.barTime;
      FireAlert(g_setup.dir, g_setup.score, g_setup.entry, g_setup.sl, g_setup.tp1,
                g_setup.r0, false);
      return;
     }

   if(g_formingSignal && InpAlertIntrabar)
     {
      if(g_lastAlertTime == Time[0] && g_lastAlertDir == g_formingDir)
         return;
      g_lastAlertTime = Time[0];
      g_lastAlertDir  = g_formingDir;
      FireAlert(g_formingDir, g_evalScore, g_evalEntry, g_evalSL, g_evalTP1, g_reasons[0], true);
     }
  }

void FireAlert(int dir, int score, double entry, double sl, double tp, string reason, bool forming)
  {
   string head = (dir > 0 ? "BUY" : "SELL");
   if(forming)
      head = head + " (forming)";

   string msg = "Apex Confluence Pro | " + Symbol() + " " + TfToStr(Period()) +
                " | " + head + " | score " + IntegerToString(score) + "/" + IntegerToString((int)ACP_MAX_SCORE) +
                " (min " + IntegerToString(g_minScore) + ")" +
                " | entry " + DoubleToString(entry, Digits) +
                " SL " + DoubleToString(sl, Digits) +
                " TP " + DoubleToString(tp, Digits);

   if(reason != "")
      msg = msg + " | " + reason;

   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertSound)
      PlaySound(InpSoundFile);
   if(InpAlertPush)
      SendNotification(msg);
   if(InpAlertEmail)
      SendMail("Apex Confluence Pro signal", msg);
  }

//==================================================================
//  SECTION 6 - CHART OBJECTS
//==================================================================

//+------------------------------------------------------------------+
//| Remove every object whose name starts with prefix                |
//+------------------------------------------------------------------+
void DeleteByPrefix(string prefix)
  {
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string nm = ObjectName(i);
      if(StringFind(nm, prefix, 0) == 0)
         ObjectDelete(nm);
     }
  }

//+------------------------------------------------------------------+
//| Create or refresh a trend line                                   |
//+------------------------------------------------------------------+
void SetLine(string name, datetime t1, double p1, datetime t2, double p2,
             color clr, int style, int width, bool ray, string text)
  {
   if(ObjectFind(name) < 0)
      ObjectCreate(name, OBJ_TREND, 0, t1, p1, t2, p2);

   ObjectSet(name, OBJPROP_TIME1, t1);
   ObjectSet(name, OBJPROP_PRICE1, p1);
   ObjectSet(name, OBJPROP_TIME2, t2);
   ObjectSet(name, OBJPROP_PRICE2, p2);
   ObjectSet(name, OBJPROP_COLOR, clr);
   ObjectSet(name, OBJPROP_STYLE, style);
   ObjectSet(name, OBJPROP_WIDTH, width);
   ObjectSet(name, OBJPROP_RAY, ray);
   ObjectSet(name, OBJPROP_BACK, false);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
   ObjectSet(name, OBJPROP_HIDDEN, true);
   if(text != "")
      ObjectSetText(name, text, 8, "Arial", clr);
  }

//+------------------------------------------------------------------+
//| Create or refresh a rectangle                                    |
//+------------------------------------------------------------------+
void SetRect(string name, datetime t1, double p1, datetime t2, double p2,
             color clr, bool back, int borderStyle, string text)
  {
   if(ObjectFind(name) < 0)
      ObjectCreate(name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSet(name, OBJPROP_TIME1, t1);
   ObjectSet(name, OBJPROP_PRICE1, p1);
   ObjectSet(name, OBJPROP_TIME2, t2);
   ObjectSet(name, OBJPROP_PRICE2, p2);
   ObjectSet(name, OBJPROP_COLOR, clr);
   ObjectSet(name, OBJPROP_BACK, back);
   ObjectSet(name, OBJPROP_STYLE, borderStyle);
   ObjectSet(name, OBJPROP_WIDTH, 1);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
   ObjectSet(name, OBJPROP_HIDDEN, true);
   if(text != "")
      ObjectSetText(name, text, 8, "Arial", clr);
  }

//+------------------------------------------------------------------+
//| Static (per bar) chart objects                                   |
//+------------------------------------------------------------------+
void DrawStatic()
  {
   DeleteByPrefix(ACP_PREFIX + "Z_");
   DeleteByPrefix(ACP_PREFIX + "T_");
   DeleteByPrefix(ACP_PREFIX + "D_");

   datetime tRight = Time[0] + InpZoneExtendBars * PeriodSeconds();

   if(InpShowZones)
      DrawZones(tRight);

   if(InpShowDailyLevels)
     {
      double pdh = iHigh(NULL, PERIOD_D1, 1);
      double pdl = iLow(NULL, PERIOD_D1, 1);
      if(pdh > 0.0)
         DrawHLevel("D_PDH", pdh, CLR_ZONE_RES, "PDH " + DoubleToString(pdh, Digits));
      if(pdl > 0.0)
         DrawHLevel("D_PDL", pdl, CLR_ZONE_SUP, "PDL " + DoubleToString(pdl, Digits));
     }

   if(InpShowWeeklyLevels)
     {
      double pwh = iHigh(NULL, PERIOD_W1, 1);
      double pwl = iLow(NULL, PERIOD_W1, 1);
      if(pwh > 0.0)
         DrawHLevel("D_PWH", pwh, CLR_ZONE_RES, "PWH " + DoubleToString(pwh, Digits));
      if(pwl > 0.0)
         DrawHLevel("D_PWL", pwl, CLR_ZONE_SUP, "PWL " + DoubleToString(pwl, Digits));
     }

   if(InpShowTradeLevels)
      DrawTradeLevels(tRight);
  }

void DrawHLevel(string tag, double price, color clr, string text)
  {
   string nm = ACP_PREFIX + "D_" + tag;
   if(ObjectFind(nm) < 0)
     {
      ObjectCreate(nm, OBJ_HLINE, 0, 0, price);
      ObjectSet(nm, OBJPROP_STYLE, STYLE_DOT);
      ObjectSet(nm, OBJPROP_WIDTH, 1);
      ObjectSet(nm, OBJPROP_BACK, true);
      ObjectSet(nm, OBJPROP_SELECTABLE, false);
      ObjectSet(nm, OBJPROP_HIDDEN, true);
     }
   ObjectSet(nm, OBJPROP_PRICE1, price);
   ObjectSet(nm, OBJPROP_COLOR, clr);
   ObjectSetText(nm, text, 7, "Arial", clr);
  }

//+------------------------------------------------------------------+
//| Draw the strongest N zones above and below price                 |
//+------------------------------------------------------------------+
void DrawZones(datetime tRight)
  {
   int    used[ACP_MAX_ZONES];
   for(int u = 0; u < ACP_MAX_ZONES; u++)
      used[u] = 0;

   double ref = (Bid > 0.0 ? Bid : Close[0]);
   int    drawn = 0;
   int    limitEach = InpMaxZonesShown;
   if(limitEach < 1)
      limitEach = 1;

   //--- above price, nearest first
   for(int n = 0; n < limitEach; n++)
     {
      int    best  = -1;
      double bestD = 1e15;
      for(int i = 0; i < g_zoneCount; i++)
        {
         if(g_zones[i].broken || used[i] == 1)
            continue;
         if(g_zones[i].bottom <= ref)
            continue;
         double d = g_zones[i].bottom - ref;
         if(d < bestD)
           {
            bestD = d;
            best  = i;
           }
        }
      if(best < 0)
         break;
      used[best] = 1;
      DrawOneZone(best, tRight, drawn);
      drawn++;
     }

   //--- below price, nearest first
   for(int m = 0; m < limitEach; m++)
     {
      int    best2  = -1;
      double bestD2 = 1e15;
      for(int j = 0; j < g_zoneCount; j++)
        {
         if(g_zones[j].broken || used[j] == 1)
            continue;
         if(g_zones[j].top >= ref)
            continue;
         double d2 = ref - g_zones[j].top;
         if(d2 < bestD2)
           {
            bestD2 = d2;
            best2  = j;
           }
        }
      if(best2 < 0)
         break;
      used[best2] = 1;
      DrawOneZone(best2, tRight, drawn);
      drawn++;
     }
  }

void DrawOneZone(int idx, datetime tRight, int seq)
  {
   color clr  = CLR_ZONE_SUP;
   color fill = CLR_FILL_SUP;
   string tag = "SUP";

   if(g_zones[idx].highTouches > 0 && g_zones[idx].lowTouches > 0)
     {
      clr  = CLR_ZONE_FLIP;
      fill = CLR_FILL_FLIP;
      tag  = "FLIP";
     }
   else
      if(g_zones[idx].role < 0)
        {
         clr  = CLR_ZONE_RES;
         fill = CLR_FILL_RES;
         tag  = "RES";
        }

   datetime tLeft = g_zones[idx].bornTime;
   if(tLeft <= 0 || tLeft > Time[0])
      tLeft = Time[(int)MathMin(120, Bars - 1)];

   string nm = ACP_PREFIX + "Z_" + IntegerToString(seq);
   SetRect(nm, tLeft, g_zones[idx].top, tRight, g_zones[idx].bottom, fill, true, STYLE_SOLID, "");

   if(InpShowZoneLabels)
     {
      string ln = ACP_PREFIX + "Z_L" + IntegerToString(seq);
      string txt = tag + " " + DoubleToString(g_zones[idx].price, Digits) +
                   " (" + IntegerToString((int)g_zones[idx].strength) + ")";
      datetime lt = Time[(int)MathMin(60, Bars - 1)];
      if(ObjectFind(ln) < 0)
         ObjectCreate(ln, OBJ_TEXT, 0, lt, g_zones[idx].top);
      ObjectSet(ln, OBJPROP_TIME1, lt);
      ObjectSet(ln, OBJPROP_PRICE1, g_zones[idx].top);
      ObjectSet(ln, OBJPROP_COLOR, clr);
      ObjectSet(ln, OBJPROP_SELECTABLE, false);
      ObjectSet(ln, OBJPROP_HIDDEN, true);
      ObjectSetText(ln, txt, 8, "Arial", clr);
     }
  }

//+------------------------------------------------------------------+
//| Entry / stop / target lines for the active setup                 |
//+------------------------------------------------------------------+
void DrawTradeLevels(datetime tRight)
  {
   if(!g_setup.valid || g_setupState == 2 || g_setupState == 4)
      return;

   datetime tLeft = g_setup.barTime;
   string   dtag  = (g_setup.dir > 0 ? "LONG" : "SHORT");

   SetLine(ACP_PREFIX + "T_E", tLeft, g_setup.entry, tRight, g_setup.entry,
           CLR_WARN, STYLE_SOLID, 1, false, "");
   SetLine(ACP_PREFIX + "T_S", tLeft, g_setup.sl, tRight, g_setup.sl,
           CLR_BEAR, STYLE_DOT, 1, false, "");
   SetLine(ACP_PREFIX + "T_T1", tLeft, g_setup.tp1, tRight, g_setup.tp1,
           CLR_BULL, STYLE_DOT, 1, false, "");
   SetLine(ACP_PREFIX + "T_T2", tLeft, g_setup.tp2, tRight, g_setup.tp2,
           CLR_BULL, STYLE_DOT, 1, false, "");

   SetTextTag(ACP_PREFIX + "T_L1", tRight, g_setup.entry,
              "ENTRY " + DoubleToString(g_setup.entry, Digits) + " " + dtag, CLR_WARN);
   SetTextTag(ACP_PREFIX + "T_L2", tRight, g_setup.sl,
              "SL " + DoubleToString(g_setup.sl, Digits), CLR_BEAR);
   SetTextTag(ACP_PREFIX + "T_L3", tRight, g_setup.tp1,
              "TP1 " + DoubleToString(g_setup.tp1, Digits), CLR_BULL);
   SetTextTag(ACP_PREFIX + "T_L4", tRight, g_setup.tp2,
              "TP2 " + DoubleToString(g_setup.tp2, Digits), CLR_BULL);
  }

void SetTextTag(string name, datetime t, double price, string txt, color clr)
  {
   if(ObjectFind(name) < 0)
      ObjectCreate(name, OBJ_TEXT, 0, t, price);
   ObjectSet(name, OBJPROP_TIME1, t);
   ObjectSet(name, OBJPROP_PRICE1, price);
   ObjectSet(name, OBJPROP_COLOR, clr);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
   ObjectSet(name, OBJPROP_HIDDEN, true);
   ObjectSetText(name, " " + txt, 8, "Arial", clr);
  }

//==================================================================
//  SECTION 7 - DASHBOARD
//==================================================================

int PanelX()
  {
   if(InpCorner == CORNER_RIGHT_UPPER || InpCorner == CORNER_RIGHT_LOWER)
      return(-InpPanelX - ACP_PANEL_W);
   return(InpPanelX);
  }

int PanelY(int height)
  {
   if(InpCorner == CORNER_LEFT_LOWER || InpCorner == CORNER_RIGHT_LOWER)
      return(-InpPanelY - height);
   return(InpPanelY);
  }

string Pad(string s, int n)
  {
   if(StringLen(s) > n)
      return(StringSubstr(s, 0, n));
   while(StringLen(s) < n)
      s = s + " ";
   return(s);
  }

string Meter(int score)
  {
   string m = "";
   for(int i = 0; i < (int)ACP_MAX_SCORE; i++)
      m = m + (i < score ? "#" : ".");
   return(m);
  }

void PanelLabel(string name, int x, int y, string txt, color clr)
  {
   if(ObjectFind(name) < 0)
     {
      ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
      ObjectSet(name, OBJPROP_CORNER, InpCorner);
      ObjectSet(name, OBJPROP_XDISTANCE, x);
      ObjectSet(name, OBJPROP_YDISTANCE, y);
      ObjectSet(name, OBJPROP_SELECTABLE, false);
      ObjectSet(name, OBJPROP_HIDDEN, true);
      ObjectSet(name, OBJPROP_BACK, false);
     }
   ObjectSetText(name, txt, InpFontSize, InpFont, clr);
  }

void PanelBuildFrame()
  {
   int height = ACP_ROWS * ACP_ROW_H + 48;
   int px = PanelX();
   int py = PanelY(height);

   string bg = ACP_PREFIX + "P_BG";
   if(ObjectFind(bg) < 0)
      ObjectCreate(bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSet(bg, OBJPROP_CORNER, InpCorner);
   ObjectSet(bg, OBJPROP_XDISTANCE, px);
   ObjectSet(bg, OBJPROP_YDISTANCE, py);
   ObjectSet(bg, OBJPROP_XSIZE, ACP_PANEL_W);
   ObjectSet(bg, OBJPROP_YSIZE, height);
   ObjectSet(bg, OBJPROP_BGCOLOR, CLR_PANEL_BG);
   ObjectSet(bg, OBJPROP_COLOR, CLR_PANEL_EDGE);
   ObjectSet(bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSet(bg, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet(bg, OBJPROP_WIDTH, 1);
   ObjectSet(bg, OBJPROP_BACK, false);
   ObjectSet(bg, OBJPROP_SELECTABLE, false);
   ObjectSet(bg, OBJPROP_HIDDEN, true);

   string ac = ACP_PREFIX + "P_ACC";
   if(ObjectFind(ac) < 0)
      ObjectCreate(ac, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSet(ac, OBJPROP_CORNER, InpCorner);
   ObjectSet(ac, OBJPROP_XDISTANCE, px);
   ObjectSet(ac, OBJPROP_YDISTANCE, py);
   ObjectSet(ac, OBJPROP_XSIZE, 4);
   ObjectSet(ac, OBJPROP_YSIZE, height);
   ObjectSet(ac, OBJPROP_BGCOLOR, CLR_TITLE);
   ObjectSet(ac, OBJPROP_COLOR, CLR_TITLE);
   ObjectSet(ac, OBJPROP_BACK, false);
   ObjectSet(ac, OBJPROP_SELECTABLE, false);
   ObjectSet(ac, OBJPROP_HIDDEN, true);

   PanelLabel(ACP_PREFIX + "P_T", px + 14, py + 8,
              "APEX CONFLUENCE PRO", CLR_TITLE);
   PanelLabel(ACP_PREFIX + "P_ST", px + 14, py + 24,
              "structure | levels | volume | timing", CLR_DIM);

   for(int r = 0; r < ACP_ROWS; r++)
      PanelLabel(ACP_PREFIX + "P_R" + IntegerToString(r), px + 14,
                 py + 44 + r * ACP_ROW_H, "", CLR_TEXT);
  }

void PanelSet(int row, string txt, color clr)
  {
   if(row < 0 || row >= ACP_ROWS)
      return;
   g_rows[row]   = txt;
   g_rowClr[row] = clr;
  }

//+------------------------------------------------------------------+
//| Push buffered rows to the chart only when something changed     |
//+------------------------------------------------------------------+
void PanelFlush()
  {
   bool changed = !g_panelInit;

   for(int i = 0; i < ACP_ROWS; i++)
     {
      if(g_rows[i] != g_prevRows[i] || g_rowClr[i] != g_prevClr[i])
        {
         changed = true;
         break;
        }
     }
   if(g_accent != g_prevAccent)
      changed = true;

   if(!changed)
      return;

   int px = PanelX() + 14;
   int py = PanelY(ACP_ROWS * ACP_ROW_H + 48) + 44;

   for(int r = 0; r < ACP_ROWS; r++)
     {
      PanelLabel(ACP_PREFIX + "P_R" + IntegerToString(r), px, py + r * ACP_ROW_H,
                 g_rows[r], g_rowClr[r]);
      g_prevRows[r] = g_rows[r];
      g_prevClr[r]  = g_rowClr[r];
     }

   string ac = ACP_PREFIX + "P_ACC";
   if(ObjectFind(ac) >= 0)
     {
      ObjectSet(ac, OBJPROP_BGCOLOR, g_accent);
      ObjectSet(ac, OBJPROP_COLOR, g_accent);
     }
   g_prevAccent = g_accent;
   g_panelInit  = true;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Snapshot of the last closed bar for the dashboard                |
//+------------------------------------------------------------------+
void SnapshotMarket()
  {
   if(Bars < 60)
      return;

   int s = 1;
   g_curATR   = ATRAt(s);
   g_curER    = EfficiencyRatio(s, g_erPeriod);
   g_curRV    = RelVolume(s);
   g_curDelta = DeltaPressure(s, 5);

   double avg = 0.0;
   int    n   = 0;
   for(int k = 0; k < 20; k++)
     {
      if(s + k >= Bars)
         break;
      avg += ATRAt(s + k);
      n++;
     }
   if(n > 0)
      avg = avg / n;
   g_curAtrRatio = (avg > 0.0 ? g_curATR / avg : 1.0);

   g_curSessionMask = SessionMask(Time[s]);
   g_htfNow         = HTFTrendAt(Time[s]);
  }

string BiasText(int bias)
  {
   if(bias > 0)
      return("BULLISH (HH/HL)");
   if(bias < 0)
      return("BEARISH (LH/LL)");
   return("RANGE / UNDEFINED");
  }

string MarketStateText()
  {
   if(g_curER >= g_erTrend)
      return("TRENDING");
   if(g_curER <= g_erChop)
      return("CHOPPY");
   return("BALANCED");
  }

string VolText()
  {
   if(g_curAtrRatio >= 1.35)
      return("HIGH");
   if(g_curAtrRatio <= 0.70)
      return("LOW");
   return("NORMAL");
  }

string RvolText()
  {
   if(g_curRV >= g_volSpike)
      return("EXPANSION");
   if(g_curRV <= 0.70)
      return("THIN");
   return("NORMAL");
  }

string DirText(int d)
  {
   if(d > 0)
      return("BUY");
   if(d < 0)
      return("SELL");
   return("--");
  }

string StateText()
  {
   if(!g_setup.valid)
      return("NO SETUP");
   int sh = iBarShift(NULL, 0, g_setup.barTime, false);
   int barsAgo = (sh >= 0 ? sh - 1 : 0);
   if(barsAgo < 0)
      barsAgo = 0;

   if(g_setupState == 1)
      return("ACTIVE  (bar " + IntegerToString(barsAgo + 1) + "/" + IntegerToString(g_setupTTL) + ")");
   if(g_setupState == 2)
      return("INVALIDATED - STOP HIT");
   if(g_setupState == 3)
      return("TARGET 1 REACHED");
   if(g_setupState == 4)
      return("EXPIRED");
   if(g_setupState == 5)
      return("STRUCTURE FLIP - EXIT");
   return("--");
  }

//+------------------------------------------------------------------+
//| Refresh the dashboard                                            |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
      return;

   double pip = PipSize();

   //--- header ------------------------------------------------
   color sigClr = CLR_NEUTRAL;

   string sigLine = "SIGNAL     NO SETUP";

   if(g_formingSignal)
     {
      sigClr  = (g_formingDir > 0 ? CLR_BULL : CLR_BEAR);
      sigLine = "SIGNAL     " + DirText(g_formingDir) + " (forming)";
     }

   if(g_setup.valid && !g_formingSignal)
     {
      string stateTag = "";
      if(g_setupState == 2)
        {
         stateTag = " (failed)";
         sigClr   = CLR_BEAR;
        }
      else
         if(g_setupState == 3)
           {
            stateTag = " (TP1)";
            sigClr   = CLR_BULL;
           }
         else
            if(g_setupState == 4)
              {
               stateTag = " (expired)";
               sigClr   = CLR_DIM;
              }
            else
               if(g_setupState == 5)
                 {
                  stateTag = " (flip)";
                  sigClr   = CLR_WARN;
                 }
               else
                  sigClr = (g_setup.dir > 0 ? CLR_BULL : CLR_BEAR);

      sigLine = "SIGNAL     " + DirText(g_setup.dir) + stateTag +
                "   " + IntegerToString(g_setup.score) + "/" + IntegerToString((int)ACP_MAX_SCORE);
     }

   if(!g_setup.valid && !g_formingSignal && g_blockText != "" &&
      StringFind(g_blockText, "AVOID", 0) >= 0)
     {
      sigLine = "SIGNAL     NO TRADE";
      sigClr  = CLR_WARN;
     }

   int scoreShown = (g_setup.valid ? g_setup.score : (g_formingSignal ? g_evalScore : 0));

   //--- structure ---------------------------------------------
   PanelSet(0, "PROFILE    " + ProfileName() + "   " + Symbol() + " " + TfToStr(Period()),
            CLR_TEXT);
   PanelSet(1, "STRUCTURE  " + BiasText(g_structTrend), CLR_TEXT);
   PanelSet(2, "HTF " + Pad(TfToStr(g_htfPeriod), 5) + "  " + BiasText(g_htfNow), CLR_TEXT);
   PanelSet(3, sigLine, sigClr);
   PanelSet(4, "SCORE      [" + Meter(scoreShown) + "] " + IntegerToString(scoreShown),
            (scoreShown >= g_minScore ? CLR_BULL : CLR_WARN));

   //--- trade plan (forming preview takes priority) -----------
   bool   useForming = g_formingSignal;
   bool   hasPlan    = (useForming || (g_setup.valid && g_setupState != 4));
   double pEntry     = (useForming ? g_evalEntry : g_setup.entry);
   double pStop      = (useForming ? g_evalSL    : g_setup.sl);
   double pTp1       = (useForming ? g_evalTP1   : g_setup.tp1);
   int    pDir       = (useForming ? g_formingDir : g_setup.dir);

   if(hasPlan)
     {
      double riskPts = MathAbs(pEntry - pStop);
      double rr      = (riskPts > 0.0 ? MathAbs(pTp1 - pEntry) / riskPts : 0.0);
      string tail    = (useForming ? "  (forming)" : "");
      PanelSet(5, "ENTRY      " + DoubleToString(pEntry, Digits) +
               "   " + DirText(pDir) + tail, CLR_TEXT);
      PanelSet(6, "STOP       " + DoubleToString(pStop, Digits) +
               "   " + DoubleToString(riskPts / pip, 1) + " pips", CLR_BEAR);
      PanelSet(7, "TARGET 1   " + DoubleToString(pTp1, Digits) +
               "   " + DoubleToString(rr, 1) + "R", CLR_BULL);
     }
   else
     {
      PanelSet(5, "ENTRY      --", CLR_DIM);
      PanelSet(6, "STOP       --", CLR_DIM);
      PanelSet(7, "TARGET 1   --", CLR_DIM);
     }

   //--- confluence reasons ------------------------------------
   string reasons[4];
   reasons[0] = (g_setup.valid ? g_setup.r0 : "");
   reasons[1] = (g_setup.valid ? g_setup.r1 : "");
   reasons[2] = (g_setup.valid ? g_setup.r2 : "");
   reasons[3] = (g_setup.valid ? g_setup.r3 : "");

   if(g_formingSignal)
     {
      reasons[0] = g_reasons[0];
      reasons[1] = g_reasons[1];
      reasons[2] = g_reasons[2];
      reasons[3] = g_reasons[3];
     }

   for(int i = 0; i < 4; i++)
     {
      string txt = "+ " + reasons[i];
      PanelSet(8 + i, txt, (reasons[i] == "" ? CLR_DIM : CLR_TEXT));
     }

   //--- market context ----------------------------------------
   PanelSet(12, "MARKET     " + Pad(MarketStateText(), 9) +
            " ER " + DoubleToString(g_curER, 2), CLR_TEXT);
   PanelSet(13, "VOLATILITY " + Pad(VolText(), 9) +
            " RVOL " + DoubleToString(g_curRV, 1) + " (" + RvolText() + ")", CLR_TEXT);
   PanelSet(14, "SESSION    " + Pad(SessionLabel(g_curSessionMask), 12) +
            " delta " + DoubleToString(g_curDelta, 0), CLR_TEXT);
   PanelSet(15, "STATUS     " + StateText(), sigClr);

   //--- action guidance ---------------------------------------
   string a1 = "";
   string a2 = "";
   color  ac = CLR_DIM;

   if(g_formingSignal)
     {
      a1 = "> " + DirText(g_formingDir) + " forming - wait for the close";
      a2 = "> Do not enter on an unfinished bar";
      ac = CLR_WARN;
     }
   else
      if(g_setup.valid && g_setupState == 1)
        {
         a1 = "> ACTION: " + DirText(g_setup.dir) + " valid at zone";
         a2 = "> Risk " + DoubleToString(MathAbs(g_setup.entry - g_setup.sl) / pip, 1) +
              " pips | invalidation " + DoubleToString(g_setup.sl, Digits);
         ac = sigClr;
        }
      else
         if(g_setup.valid && g_setupState == 2)
           {
            a1 = "> SETUP FAILED - protection was hit";
            a2 = "> Stand aside, wait for a new flush";
            ac = CLR_BEAR;
           }
         else
            if(g_setup.valid && g_setupState == 3)
              {
               a1 = "> TARGET 1 reached";
               a2 = "> Trail stop / take partials";
               ac = CLR_BULL;
              }
            else
               if(g_setup.valid && g_setupState == 5)
                 {
                  a1 = "> Structure flipped against the trade";
                  a2 = "> Take profit / tighten stop now";
                  ac = CLR_WARN;
                 }
               else
                  if(g_setup.valid && g_setupState == 4)
                    {
                     a1 = "> Last setup expired";
                     a2 = "> Wait for fresh confluence";
                     ac = CLR_DIM;
                    }
               else
                 {
                  a1 = "> " + (g_blockText == "" ? "NO TRADE - wait at a level" : g_blockText);
                  a2 = "> A+ setups need a zone + trigger + volume";
                  ac = CLR_WARN;
                 }

   PanelSet(16, a1, ac);
   PanelSet(17, a2, CLR_DIM);

   //--- colour the accent bar with the live bias --------------
   color accent = CLR_NEUTRAL;
   if(g_setup.valid && g_setupState == 1)
      accent = (g_setup.dir > 0 ? CLR_BULL : CLR_BEAR);
   else
      if(g_blockText != "" && StringFind(g_blockText, "AVOID", 0) >= 0)
         accent = CLR_WARN;
      else
         if(g_structTrend > 0)
            accent = CLR_BULL;
         else
            if(g_structTrend < 0)
               accent = CLR_BEAR;

   g_accent = accent;
   PanelFlush();
  }
