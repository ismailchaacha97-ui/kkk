//+------------------------------------------------------------------+
//|                                             FTMO_QuantEdge.mq4   |
//|                     Adaptive Statistical EA for FTMO-style funds |
//|                                                                  |
//|  DESIGN                                                          |
//|  ------                                                          |
//|  Every decision is a closed-form mathematical function of price   |
//|  history. No discretionary rules, no martingale, no grid, no      |
//|  averaging down, no random numbers. The EA is fully deterministic |
//|  and therefore reproducible in the Strategy Tester.               |
//|                                                                  |
//|  1. Robust z-score      z = (C - median_n) / (1.4826 * MAD_n)     |
//|     Median/MAD instead of mean/stdev gives a breakdown point of   |
//|     ~50% instead of ~0%, so a single news spike cannot fake an    |
//|     "oversold" reading.                                           |
//|                                                                  |
//|  2. Normalised momentum m = (C1 - C1+k) / (ATR * sqrt(k))         |
//|     Dividing by sqrt(k) normalises the random-walk scale, so m is |
//|     comparable across lookbacks and instruments.                  |
//|                                                                  |
//|  3. Variance ratio      VR(q) = Var(r_q) / (q * Var(r_1))         |
//|     Lo-MacKinlay statistic. VR < 1 => mean reverting, VR > 1 =>   |
//|     trending. This is what switches the EA between regimes.       |
//|                                                                  |
//|  4. OU half-life        dp_t = a + b * p_{t-1}                    |
//|     Half-life = ln(2) / -ln(1+b), with the Kendall finite-sample  |
//|     bias correction b* = b + (1+3b)/n. The slope must also pass   |
//|     a Dickey-Fuller test (t <= -2.86, the 5% critical value with  |
//|     a constant). Without that test a random walk produces a       |
//|     plausible looking half-life 30-50% of the time, which is the  |
//|     single easiest way to build a mean-reversion EA that trades   |
//|     pure noise.                                                   |
//|                                                                  |
//|  5. Fibonacci confluence: distance of price to the 0.382 / 0.500  |
//|     / 0.618 retracement of the last swing, measured in ATR units. |
//|                                                                  |
//|  The five components are standardised to [-1,+1] and linearly     |
//|  combined into a single score s in [-1,+1]. A trade is opened     |
//|  only when |s| >= threshold and every hard filter agrees.         |
//|                                                                  |
//|  COMPLIANCE / SAFETY                                              |
//|  ---------------------                                             |
//|  * Equity-anchored daily-loss governor (FTMO 5% rule, default     |
//|    halt at 3.5% used so a gap cannot push the account over).      |
//|  * Static total-loss governor against the phase starting balance  |
//|    (FTMO 10% rule, default halt at 8.0%).                         |
//|  * Risk-based position sizing (default 0.5% of equity) with hard  |
//|    caps on per-trade risk, aggregate open risk and lot size.      |
//|  * Execution-efficiency guards that keep the trade profile away   |
//|    from the prohibited HFT / tick-scalping / latency-arbitrage    |
//|    patterns: minimum time between entries, minimum trade         |
//|    duration, per-day trade cap, no trading on the open gap, no    |
//|    trading in the rollover spread spike.                          |
//|  * Optional weekend flattening, session window, spread cap and    |
//|    CSV-driven high-impact news blackout.                          |
//|                                                                  |
//|  This program is provided for research/education. It is not       |
//|  financial advice. Past performance does not imply future         |
//|  results. Test on demo before any live use.                       |
//+------------------------------------------------------------------+
#property copyright   "QuantEdge Trading Systems"
#property link        "https://github.com/ismailchaacha97-ui/kkk"
#property version     "1.00"
#property description "Adaptive statistical EA: robust z-score, normalised momentum, variance-ratio regime, OU half-life, Fibonacci confluence."
#property description "FTMO governance: equity-anchored 5% daily and 10% total loss governors, risk-based sizing, execution-efficiency guards."
#property strict

//==================================================================
//  1. ENUMERATIONS
//==================================================================
enum ENUM_QE_STRATEGY
  {
   QE_ADAPTIVE = 0,   // Adaptive: variance-ratio regime switch
   QE_MEANREV  = 1,   // Mean reversion only  (z-score)
   QE_MOMENTUM = 2,   // Momentum continuation only
   QE_FIBONLY  = 3    // Fibonacci confluence only
  };

enum ENUM_QE_EXITMODE
  {
   QE_EXIT_RMULT   = 0,   // Fixed R multiple
   QE_EXIT_MEANREV = 1    // Statistical mean (rolling SMA) target
  };

enum ENUM_QE_ANCHOR
  {
   QE_ANCHOR_BALANCE = 0,   // Balance at 00:00 server (FTMO baseline)
   QE_ANCHOR_EQUITY  = 1,   // Equity at 00:00 server
   QE_ANCHOR_MAX     = 2    // max(balance, equity) - most conservative
  };

enum ENUM_QE_NEUTRAL
  {
   QE_NEUTRAL_NONE = 0,     // No trade when the variance ratio is inconclusive
   QE_NEUTRAL_MR   = 1,     // Mean reversion (the default thesis)
   QE_NEUTRAL_MO   = 2      // Momentum
  };

//==================================================================
//  2. INPUTS
//     (grouped by purpose; every parameter is documented in
//      docs/FTMO_QuantEdge_Manual.md)
//==================================================================

//--- 2.1 Identity -------------------------------------------------
input int             InpMagicBase        = 771100;      // Magic base (0 = auto from symbol+TF+instance)
input int             InpInstanceId       = 1;           // Instance id (use 1,2,3.. per chart)
input string          InpTradeComment     = "QEdge";     // Order comment

//--- 2.2 Strategy ------------------------------------------------
input ENUM_QE_STRATEGY InpStrategy        = QE_ADAPTIVE;  // Strategy mode
input double          InpEntryThreshold   = 0.55;        // |score| to open a trade (0.10..0.95)
input double          InpWeightZ          = 1.00;        // Weight: z-score factor
input double          InpWeightMom        = 0.60;        // Weight: momentum factor
input double          InpWeightFib        = 0.40;        // Weight: Fibonacci factor
input double          InpMinAbsZ          = 1.00;        // Hard gate: minimum |z| (0 = off)

//--- 2.3 Statistical windows -------------------------------------
input int             InpZPeriod          = 20;          // z-score window (bars)
input bool            InpRobustZ          = true;        // Use median/MAD z-score (else mean/stdev)
input double          InpZCap             = 3.00;        // z is clipped to +/- this before scoring
input int             InpMomLookback      = 8;           // Momentum lookback (bars)
input double          InpMomCap           = 2.00;        // Momentum is clipped to +/- this
input int             InpATRPeriod        = 14;          // ATR period
input int             InpVRWindow         = 240;         // Variance-ratio window (bars)
input int             InpVRHorizon        = 4;           // Variance-ratio horizon q
input double          InpVRThreshold      = 0.08;        // |VR-1| needed to declare a regime
input ENUM_QE_NEUTRAL InpNeutralRegime    = QE_NEUTRAL_MR; // Mode used when VR is inconclusive
input int             InpHalfLifeWindow   = 240;         // AR(1)/DF regression window (bars)
input double          InpMaxHalfLifeBars  = 80.0;        // Reject MR trades slower than this half-life
input double          InpHLTStatMin       = 2.86;        // Dickey-Fuller |t| the slope must beat (0 = off)
input bool            InpRequireHalfLifeGate = true;     // Mean reversion requires a proven half-life
input int             InpATRPercentileWindow = 200;      // Volatility percentile window
input double          InpMinATRPercentile = 0.10;        // Skip dead markets (ATR percentile below)
input double          InpMaxATRPercentile = 0.95;        // Skip extreme volatility (ATR percentile above)
input int             InpTrendMAPeriod    = 200;         // Trend filter MA period
input int             InpTrendSlopeBars   = 20;          // Bars over which the MA slope is measured
input bool            InpUseTrendFilter   = true;        // Momentum mode: require MA slope agreement

//--- 2.4 Fibonacci confluence ------------------------------------
input int             InpFibLookback      = 120;         // Swing lookback for Fib levels (bars)
input double          InpFibLevel1        = 0.382;       // Fib level 1 (0 = disable)
input double          InpFibLevel2        = 0.500;       // Fib level 2 (0 = disable)
input double          InpFibLevel3        = 0.618;       // Fib level 3 (0 = disable)
input double          InpFibTolATR        = 0.35;        // Tolerance around a level, in ATR units

//--- 2.5 Exits ----------------------------------------------------
input ENUM_QE_EXITMODE InpExitMode        = QE_EXIT_MEANREV; // Take-profit mode
input double          InpSL_ATR_Mult      = 2.00;        // Stop-loss distance in ATR
input double          InpRR               = 1.50;        // R multiple used by QE_EXIT_RMULT
input double          InpMinTP_R          = 0.80;        // Fallback R multiple if mean is too close
input bool            InpExitOnZNeutral   = true;        // Close when the z-score has normalised
input double          InpZExitLevel       = 0.25;        // |z| considered "normalised"
input int             InpMaxBarsInTrade   = 48;          // Hard time stop (bars)
input bool            InpUseHalfLifeStop  = true;        // Cap the time stop at k * half-life
input double          InpHalfLifeStopMult = 3.00;        // k for the half-life time stop
input bool            InpUseBreakEven     = true;        // Move SL to break-even
input double          InpBreakEvenR       = 1.00;        // ... once profit reaches this many R
input int             InpBreakEvenLockPts = 10;          // Points locked in beyond entry
input bool            InpUseTrailingStop  = false;       // ATR trailing stop
input double          InpTrailATRMult     = 1.20;        // Trailing distance in ATR

//--- 2.6 Risk management -----------------------------------------
input double          InpRiskPercent      = 0.50;        // Risk per trade (% of equity)
input double          InpMaxRiskPercent   = 1.00;        // Hard cap on risk per trade (%)
input double          InpMaxOpenRiskPct   = 1.50;        // Cap on aggregate open risk (%)
input int             InpMaxOpenPositions = 2;           // Maximum simultaneous positions
input bool            InpAllowHedge       = false;       // Allow opposite positions at once
input double          InpMaxLots          = 10.00;       // Absolute lot cap
input double          InpMinStopDistancePts = 0.0;       // Min SL distance in points (0 = broker only)

//--- 2.7 FTMO governors ------------------------------------------
input double          InpProfitTargetPct  = 10.0;        // Phase profit target (%)
input bool            InpLockAtProfitTarget = true;      // Stop trading at target (challenge phases)
input double          InpMaxDailyLossPct  = 5.0;         // FTMO daily loss limit (%) - hard rule
input double          InpDailyRiskBudgetPct = 3.5;       // EA halt threshold for the day (%)
input double          InpMaxTotalLossPct  = 10.0;        // FTMO max loss (%) - hard rule
input double          InpTotalRiskBudgetPct = 8.0;       // EA halt threshold for the phase (%)
input double          InpInitialBalance   = 0.0;         // Phase start balance (0 = auto-detect + persist)
input ENUM_QE_ANCHOR  InpDailyAnchorMode  = QE_ANCHOR_MAX; // Daily anchor: balance / equity / max
input int             InpDayRollHour      = 0;           // Server hour of the FTMO day rollover (EET servers: 23)
input int             InpDayRollMinute    = 0;           // Server minute of the day rollover
input bool            InpResetStoredAnchors = false;     // Clear the stored phase balance on init
input bool            InpCloseAllOnBreach = true;        // Flatten when a governor trips
input bool            InpFlattenOnProfitLock = false;    // Also close open trades at target

//--- 2.8 Session / market structure ------------------------------
input bool            InpUseSession       = true;        // Restrict trading to a time window
input int             InpSessionStartHour = 8;           // Session start hour (server time)
input int             InpSessionStartMin  = 0;           // Session start minute
input int             InpSessionEndHour   = 20;          // Session end hour (server time)
input int             InpSessionEndMin    = 0;           // Session end minute
input int             InpSkipRolloverMin  = 15;          // Skip N minutes around 00:00 server
input int             InpReopenBlackoutMin = 10;         // Skip N minutes after the weekly open
input bool            InpCloseBeforeWeekend = true;      // Flatten before the weekend (Normal accounts)
input int             InpFridayCloseHour  = 20;          // Friday flatten hour (server time)
input bool            InpNoNewTradesFriday = true;       // No new entries late on Friday
input int             InpFridayNoTradeHour = 17;         // ... from this hour
input double          InpMaxSpreadPoints  = 0.0;         // Max spread in points (0 = auto)
input double          InpAutoSpreadMult   = 3.0;         // Auto cap = this * median spread

//--- 2.9 Execution -----------------------------------------------
input int             InpSlippagePoints   = 10;          // Max deviation (points)
input int             InpMaxRetries       = 3;           // Order retries per signal
input int             InpRetryDelayMs     = 250;         // Delay between retries (ms)
input int             InpMinSecBetweenTrades = 30;       // Minimum seconds between entries
input int             InpMinTradeDurationSec = 120;      // Minimum position lifetime (anti tick-scalping)
input int             InpMaxTradesPerDay  = 6;           // Daily entry cap
input bool            InpOneTradePerBar   = true;        // At most one entry per bar

//--- 2.10 News blackout ------------------------------------------
input bool            InpNewsFilter       = false;       // Enable CSV news blackout
input string          InpNewsFileName     = "QuantEdge_news.csv"; // File in MQL4/Files
input int             InpNewsBeforeMin    = 2;           // Blackout minutes before event
input int             InpNewsAfterMin     = 2;           // Blackout minutes after event
input bool            InpNewsHighOnly     = true;        // Only "High" impact rows

//--- 2.11 Diagnostics --------------------------------------------
input bool            InpVerbose          = false;       // Detailed journal output
input bool            InpCsvLog           = false;       // Append decisions to a CSV file
input string          InpCsvFileName      = "QuantEdge_log.csv"; // CSV file in MQL4/Files
input bool            InpShowDashboard    = true;        // On-chart status panel
input ENUM_BASE_CORNER InpDashCorner      = CORNER_LEFT_UPPER; // Panel corner
input int             InpDashX            = 12;          // Panel X offset
input int             InpDashY            = 18;          // Panel Y offset
input int             InpDashFontSize     = 9;           // Panel font size
input color           InpDashColor        = clrDodgerBlue; // Panel colour
input int             InpDashRefreshSec   = 1;           // Panel refresh (seconds)
input bool            InpSelfTest         = true;        // Validate and clamp inputs on init

//==================================================================
//  3. CONSTANTS AND GLOBAL STATE
//==================================================================
#define QE_MAX_WINDOW   480     // Maximum supported window (validated on init)
#define QE_MAX_NEWS     600     // Maximum news rows held in memory
#define QE_EPS          1.0e-12

string   g_symbol        = "";
int      g_period        = 0;
int      g_digits        = 5;
double   g_point         = 0.00001;
double   g_tickSize      = 0.00001;
double   g_minLot        = 0.01;
double   g_maxLot        = 100.0;
double   g_lotStep       = 0.01;
double   g_contractSize  = 100000.0;
int      g_stopLevel     = 0;
int      g_freezeLevel   = 0;
int      g_magic         = 771100;
int      g_neededBars    = 250;
bool     g_ready         = false;

//--- signal state (valid for the current bar)
bool     g_mathReady     = false;
double   g_atr           = 0.0;
double   g_atrPct        = 0.5;
double   g_z             = 0.0;
double   g_zMean         = 0.0;
double   g_zStd          = 0.0;
double   g_momRaw        = 0.0;
double   g_vr            = 1.0;
double   g_halfLife      = -1.0;
double   g_hlTStat       = 0.0;
double   g_fibScore      = 0.0;
double   g_fibHigh       = 0.0;
double   g_fibLow        = 0.0;
double   g_trendMA       = 0.0;
double   g_trendSlope    = 0.0;
int      g_trendBias     = 0;
int      g_regime        = 0;
double   g_score         = 0.0;
int      g_dir           = 0;
bool     g_useMR         = false;   // mean-reversion logic active this bar
bool     g_useMO         = false;   // momentum logic active this bar
bool     g_useFB         = false;   // fibonacci logic active this bar
bool     g_volOk         = false;
bool     g_mrHorizonOk   = false;
bool     g_trendOk       = false;
string   g_blockReason   = "";

//--- workspaces (fixed size: no allocation, no fragmentation)
double   g_work[QE_MAX_WINDOW];
double   g_tr[QE_MAX_WINDOW + 16];

//--- account and compliance state
double   g_initialBalance = 0.0;
double   g_dayAnchor      = 0.0;
datetime g_dayStamp       = 0;
bool     g_anchorLive     = false;
bool     g_dailyHalted    = false;
bool     g_totalHalted    = false;
bool     g_targetLocked   = false;
bool     g_weekendHalted  = false;
double   g_openRiskPct    = 0.0;

//--- execution state
datetime g_lastBarTime    = 0;
datetime g_lastEntryTime  = 0;
datetime g_lastEntryBar   = 0;
datetime g_tradeDay       = 0;
int      g_tradesToday    = 0;
int      g_spreadMedian   = 0;
datetime g_spreadCalcTime = 0;
datetime g_lastDashTime   = 0;
datetime g_lastNewsLoad   = 0;

//--- news cache
datetime g_newsTime[QE_MAX_NEWS];
string   g_newsCcy[QE_MAX_NEWS];
bool     g_newsHigh[QE_MAX_NEWS];
int      g_newsCount      = 0;

//==================================================================
//  4. SMALL UTILITIES
//==================================================================
double ClampD(double v, double lo, double hi)
  {
   if(v < lo) return(lo);
   if(v > hi) return(hi);
   return(v);
  }

int SignD(double v)
  {
   if(v > 0.0) return(1);
   if(v < 0.0) return(-1);
   return(0);
  }

datetime DayStartOf(datetime t)
  {
   return((datetime)(((long)t / 86400) * 86400));
  }

double BidPrice()
  {
   return(MarketInfo(g_symbol, MODE_BID));
  }

double AskPrice()
  {
   return(MarketInfo(g_symbol, MODE_ASK));
  }

int SpreadPoints()
  {
   if(g_point <= 0.0) return(0);
   return((int)MathRound((AskPrice() - BidPrice()) / g_point));
  }

//--- monetary value of one point for one lot (handles tickSize != point)
double ValuePerPointPerLot()
  {
   double tv = MarketInfo(g_symbol, MODE_TICKVALUE);
   double ts = MarketInfo(g_symbol, MODE_TICKSIZE);
   if(ts <= 0.0 || tv <= 0.0) return(0.0);
   return(tv * (g_point / ts));
  }

bool IsNewBar()
  {
   datetime t = iTime(g_symbol, g_period, 0);
   if(t == g_lastBarTime) return(false);
   g_lastBarTime = t;
   return(true);
  }

//--- stable string hash, used to derive a unique magic number per chart
int HashString(string s)
  {
   int h = 5381;
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
      h = ((h * 33) + (int)StringGetCharacter(s, i)) % 2147483;
   return(h);
  }

//--- insertion sort of g_work[0..n-1], n is small (<= 64)
void SortWorkAsc(int n)
  {
   for(int i = 1; i < n; i++)
     {
      double key = g_work[i];
      int j = i - 1;
      while(j >= 0 && g_work[j] > key)
        {
         g_work[j + 1] = g_work[j];
         j--;
        }
      g_work[j + 1] = key;
     }
  }

//==================================================================
//  5. MARKET / ACCOUNT INITIALISATION
//==================================================================
bool InitMarket()
  {
   g_symbol       = _Symbol;
   g_period       = _Period;
   g_point        = MarketInfo(g_symbol, MODE_POINT);
   g_digits       = (int)MarketInfo(g_symbol, MODE_DIGITS);
   g_tickSize     = MarketInfo(g_symbol, MODE_TICKSIZE);
   g_minLot       = MarketInfo(g_symbol, MODE_MINLOT);
   g_maxLot       = MarketInfo(g_symbol, MODE_MAXLOT);
   g_lotStep      = MarketInfo(g_symbol, MODE_LOTSTEP);
   g_contractSize = MarketInfo(g_symbol, MODE_LOTSIZE);
   g_stopLevel    = (int)MarketInfo(g_symbol, MODE_STOPLEVEL);
   g_freezeLevel  = (int)MarketInfo(g_symbol, MODE_FREEZELEVEL);

   if(g_point <= 0.0 || g_tickSize <= 0.0 || g_digits < 0)
     {
      Print("QE: invalid symbol specification, cannot start");
      return(false);
     }
   if(g_lotStep <= 0.0) g_lotStep = 0.01;
   if(g_minLot  <= 0.0) g_minLot  = g_lotStep;
   if(g_maxLot  <= 0.0) g_maxLot  = 100.0;
   if(g_digits  <= 0)   g_digits  = 2;

   //--- magic number: explicit, or derived so that several instances on
   //--- different charts never interfere with each other
   if(InpMagicBase > 0)
      g_magic = InpMagicBase + MathMax(0, InpInstanceId - 1);
   else
      g_magic = 100000 + HashString(g_symbol + IntegerToString(g_period) + IntegerToString(InpInstanceId));

   if(InpVerbose)
      PrintFormat("QE: symbol=%s point=%.8f digits=%d tickSize=%.8f minLot=%.2f maxLot=%.2f step=%.2f stopLevel=%d magic=%d",
                  g_symbol, g_point, g_digits, g_tickSize, g_minLot, g_maxLot, g_lotStep, g_stopLevel, g_magic);
   return(true);
  }

//--- validate inputs. Any violation aborts initialisation with an exact
//--- message: silent clamping produces backtests that do not match the
//--- settings the user believes they are running.
bool ValidateInputs()
  {
   bool ok = true;

   if(!(InpZPeriod >= 5 && InpZPeriod <= 64))
     {
      Print("QE INPUT ERROR: InpZPeriod must be in [5,64]");
      ok = false;
     }
   if(!(InpATRPeriod >= 2 && InpATRPeriod <= 100))
     {
      Print("QE INPUT ERROR: InpATRPeriod must be in [2,100]");
      ok = false;
     }
   if(!(InpMomLookback >= 1 && InpMomLookback <= 100))
     {
      Print("QE INPUT ERROR: InpMomLookback must be in [1,100]");
      ok = false;
     }
   if(!(InpEntryThreshold >= 0.10 && InpEntryThreshold <= 0.95))
     {
      Print("QE INPUT ERROR: InpEntryThreshold must be in [0.10,0.95]");
      ok = false;
     }
   if(!(InpZCap >= 0.5 && InpZCap <= 10.0))
     {
      Print("QE INPUT ERROR: InpZCap must be in [0.5,10]");
      ok = false;
     }
   if(!(InpMomCap >= 0.1 && InpMomCap <= 20.0))
     {
      Print("QE INPUT ERROR: InpMomCap must be in [0.1,20]");
      ok = false;
     }
   if(!(InpVRHorizon >= 2 && InpVRHorizon <= 60))
     {
      Print("QE INPUT ERROR: InpVRHorizon must be in [2,60]");
      ok = false;
     }
   if(!(InpVRWindow >= InpVRHorizon + 10 && InpVRWindow <= QE_MAX_WINDOW - 8))
     {
      Print("QE INPUT ERROR: InpVRWindow must be >= InpVRHorizon+10 and <= 472");
      ok = false;
     }
   if(!(InpVRThreshold >= 0.0 && InpVRThreshold <= 0.9))
     {
      Print("QE INPUT ERROR: InpVRThreshold must be in [0,0.9]");
      ok = false;
     }
   if(!(InpHalfLifeWindow >= 20 && InpHalfLifeWindow <= QE_MAX_WINDOW - 8))
     {
      Print("QE INPUT ERROR: InpHalfLifeWindow must be in [20,472]");
      ok = false;
     }
   if(!(InpMaxHalfLifeBars >= 5.0 && InpMaxHalfLifeBars <= 1000.0))
     {
      Print("QE INPUT ERROR: InpMaxHalfLifeBars must be in [5,1000]");
      ok = false;
     }
   if(!(InpHLTStatMin >= 0.0 && InpHLTStatMin <= 6.0))
     {
      Print("QE INPUT ERROR: InpHLTStatMin must be in [0,6] (2.86 = Dickey-Fuller 5% critical value)");
      ok = false;
     }
   if(!(InpATRPercentileWindow >= 50 && InpATRPercentileWindow <= QE_MAX_WINDOW - InpATRPeriod - 8))
     {
      Print("QE INPUT ERROR: InpATRPercentileWindow must be >= 50 and small enough to fit the buffer");
      ok = false;
     }
   if(!(InpMinATRPercentile >= 0.0 && InpMinATRPercentile < InpMaxATRPercentile && InpMaxATRPercentile <= 1.0))
     {
      Print("QE INPUT ERROR: ATR percentile bounds must satisfy 0 <= min < max <= 1");
      ok = false;
     }
   if(!(InpTrendMAPeriod >= 20 && InpTrendMAPeriod <= QE_MAX_WINDOW - InpTrendSlopeBars - 8))
     {
      Print("QE INPUT ERROR: InpTrendMAPeriod must be in [20, 472-InpTrendSlopeBars]");
      ok = false;
     }
   if(!(InpTrendSlopeBars >= 1 && InpTrendSlopeBars <= 100))
     {
      Print("QE INPUT ERROR: InpTrendSlopeBars must be in [1,100]");
      ok = false;
     }
   if(!(InpFibLookback >= 20 && InpFibLookback <= QE_MAX_WINDOW - 8))
     {
      Print("QE INPUT ERROR: InpFibLookback must be in [20,472]");
      ok = false;
     }
   if(!(InpFibTolATR > 0.0 && InpFibTolATR <= 2.0))
     {
      Print("QE INPUT ERROR: InpFibTolATR must be in (0,2]");
      ok = false;
     }
   if(!(InpSL_ATR_Mult >= 0.3 && InpSL_ATR_Mult <= 20.0))
     {
      Print("QE INPUT ERROR: InpSL_ATR_Mult must be in [0.3,20]");
      ok = false;
     }
   if(!(InpRR > 0.0 && InpRR <= 20.0)) { Print("QE INPUT ERROR: InpRR must be in (0,20]"); ok = false; }
   if(!(InpMinTP_R >= 0.1 && InpMinTP_R <= InpRR + 5.0))
     {
      Print("QE INPUT ERROR: InpMinTP_R must be in [0.1, InpRR+5]");
      ok = false;
     }
   if(!(InpRiskPercent > 0.0 && InpRiskPercent <= InpMaxRiskPercent))
     {
      Print("QE INPUT ERROR: InpRiskPercent must be > 0 and <= InpMaxRiskPercent");
      ok = false;
     }
   if(!(InpMaxRiskPercent <= 2.0))
     {
      Print("QE INPUT ERROR: InpMaxRiskPercent must be <= 2.0 percent for FTMO use");
      ok = false;
     }
   if(!(InpMaxOpenRiskPct > 0.0 && InpMaxOpenRiskPct < InpDailyRiskBudgetPct))
     {
      Print("QE INPUT ERROR: InpMaxOpenRiskPct must be inside (0, InpDailyRiskBudgetPct)");
      ok = false;
     }
   if(!(InpMaxOpenPositions >= 1 && InpMaxOpenPositions <= 20))
     {
      Print("QE INPUT ERROR: InpMaxOpenPositions must be in [1,20]");
      ok = false;
     }
   if(!(InpMaxLots > 0.0)) { Print("QE INPUT ERROR: InpMaxLots must be > 0"); ok = false; }
   if(!(InpProfitTargetPct > 0.0 && InpProfitTargetPct <= 50.0))
     {
      Print("QE INPUT ERROR: InpProfitTargetPct must be in (0,50]");
      ok = false;
     }
   if(!(InpMaxDailyLossPct > 0.0 && InpMaxDailyLossPct <= 10.0))
     {
      Print("QE INPUT ERROR: InpMaxDailyLossPct must be in (0,10]");
      ok = false;
     }
   if(!(InpDailyRiskBudgetPct > 0.0 && InpDailyRiskBudgetPct < InpMaxDailyLossPct))
     {
      Print("QE INPUT ERROR: InpDailyRiskBudgetPct must be inside (0, InpMaxDailyLossPct)");
      ok = false;
     }
   if(!(InpMaxTotalLossPct > 0.0 && InpMaxTotalLossPct <= 20.0))
     {
      Print("QE INPUT ERROR: InpMaxTotalLossPct must be in (0,20]");
      ok = false;
     }
   if(!(InpTotalRiskBudgetPct > 0.0 && InpTotalRiskBudgetPct < InpMaxTotalLossPct))
     {
      Print("QE INPUT ERROR: InpTotalRiskBudgetPct must be inside (0, InpMaxTotalLossPct)");
      ok = false;
     }
   if(!(InpDayRollHour >= 0 && InpDayRollHour <= 23))
     {
      Print("QE INPUT ERROR: InpDayRollHour must be in [0,23]");
      ok = false;
     }
   if(!(InpDayRollMinute >= 0 && InpDayRollMinute <= 59))
     {
      Print("QE INPUT ERROR: InpDayRollMinute must be in [0,59]");
      ok = false;
     }
   if(!(InpInitialBalance >= 0.0)) { Print("QE INPUT ERROR: InpInitialBalance must be >= 0"); ok = false; }
   if(!(InpSessionStartHour >= 0 && InpSessionStartHour <= 23))
     {
      Print("QE INPUT ERROR: InpSessionStartHour must be in [0,23]");
      ok = false;
     }
   if(!(InpSessionEndHour >= 0 && InpSessionEndHour <= 24))
     {
      Print("QE INPUT ERROR: InpSessionEndHour must be in [0,24]");
      ok = false;
     }
   if(!(InpFridayCloseHour >= 0 && InpFridayCloseHour <= 24))
     {
      Print("QE INPUT ERROR: InpFridayCloseHour must be in [0,24]");
      ok = false;
     }
   if(!(InpFridayNoTradeHour >= 0 && InpFridayNoTradeHour <= 24))
     {
      Print("QE INPUT ERROR: InpFridayNoTradeHour must be in [0,24]");
      ok = false;
     }
   if(!(InpSkipRolloverMin >= 0 && InpSkipRolloverMin <= 120))
     {
      Print("QE INPUT ERROR: InpSkipRolloverMin must be in [0,120]");
      ok = false;
     }
   if(!(InpReopenBlackoutMin >= 0 && InpReopenBlackoutMin <= 240))
     {
      Print("QE INPUT ERROR: InpReopenBlackoutMin must be in [0,240]");
      ok = false;
     }
   if(!(InpMaxSpreadPoints >= 0.0)) { Print("QE INPUT ERROR: InpMaxSpreadPoints must be >= 0"); ok = false; }
   if(!(InpAutoSpreadMult >= 1.0)) { Print("QE INPUT ERROR: InpAutoSpreadMult must be >= 1"); ok = false; }
   if(!(InpSlippagePoints >= 0 && InpSlippagePoints <= 200))
     {
      Print("QE INPUT ERROR: InpSlippagePoints must be in [0,200]");
      ok = false;
     }
   if(!(InpMaxRetries >= 1 && InpMaxRetries <= 10))
     {
      Print("QE INPUT ERROR: InpMaxRetries must be in [1,10]");
      ok = false;
     }
   if(!(InpMaxTradesPerDay >= 0 && InpMaxTradesPerDay <= 100))
     {
      Print("QE INPUT ERROR: InpMaxTradesPerDay must be in [0,100]");
      ok = false;
     }
   if(!(InpMinTradeDurationSec >= 30 && InpMinTradeDurationSec <= 3600))
     {
      Print("QE INPUT ERROR: InpMinTradeDurationSec must be in [30,3600] (anti tick-scalping guard)");
      ok = false;
     }
   if(!(InpMaxBarsInTrade >= 1 && InpMaxBarsInTrade <= 5000))
     {
      Print("QE INPUT ERROR: InpMaxBarsInTrade must be in [1,5000]");
      ok = false;
     }
   if(!(InpHalfLifeStopMult >= 0.5 && InpHalfLifeStopMult <= 20.0))
     {
      Print("QE INPUT ERROR: InpHalfLifeStopMult must be in [0.5,20]");
      ok = false;
     }
   if(!(InpBreakEvenR > 0.0 && InpBreakEvenR <= 10.0))
     {
      Print("QE INPUT ERROR: InpBreakEvenR must be in (0,10]");
      ok = false;
     }
   if(!(InpTrailATRMult >= 0.2 && InpTrailATRMult <= 10.0))
     {
      Print("QE INPUT ERROR: InpTrailATRMult must be in [0.2,10]");
      ok = false;
     }
   if(!(InpNewsBeforeMin >= 0 && InpNewsAfterMin >= 0))
     {
      Print("QE INPUT ERROR: News blackout minutes must be >= 0");
      ok = false;
     }
   if(!(InpNewsBeforeMin <= 240 && InpNewsAfterMin <= 240))
     {
      Print("QE INPUT ERROR: News blackout minutes must be <= 240");
      ok = false;
     }
   if(!(InpDashFontSize >= 6 && InpDashFontSize <= 24))
     {
      Print("QE INPUT ERROR: InpDashFontSize must be in [6,24]");
      ok = false;
     }
   if(!(InpDashRefreshSec >= 1)) { Print("QE INPUT ERROR: InpDashRefreshSec must be >= 1"); ok = false; }

   if(InpUseSession &&
      InpSessionEndHour * 60 + InpSessionEndMin <= InpSessionStartHour * 60 + InpSessionStartMin)
     {
      Print("QE INPUT ERROR: session end must be after session start (or disable InpUseSession)");
      ok = false;
     }

   if(InpWeightZ + InpWeightMom + InpWeightFib <= 0.0)
     {
      Print("QE INPUT ERROR: at least one score weight must be > 0");
      ok = false;
     }

   return(ok);
  }

//--- minimum number of bars needed before the engine can produce a signal
int ComputeNeededBars()
  {
   int need = InpTrendMAPeriod + InpTrendSlopeBars + 5;
   need = (int)MathMax(need, InpATRPercentileWindow + InpATRPeriod + 5);
   need = (int)MathMax(need, InpVRWindow + InpVRHorizon + 5);
   need = (int)MathMax(need, InpHalfLifeWindow + 5);
   need = (int)MathMax(need, InpFibLookback + 5);
   need = (int)MathMax(need, InpZPeriod + 5);
   need = (int)MathMax(need, InpMomLookback + 5);
   need = (int)MathMax(need, 60);
   return(need);
  }

//==================================================================
//  6. MATHEMATICAL ENGINE
//     All routines read closed bars (shift >= 1) and run once per
//     bar, so their cost is irrelevant to tick latency.
//==================================================================

//--- 6.1 ATR and its percentile rank ------------------------------
void ComputeATRStats()
  {
   int p = InpATRPeriod;
   int w = InpATRPercentileWindow;
   int need = w + p + 2;

   //--- true range for shifts 1..need
   for(int k = 0; k < need; k++)
     {
      double h  = iHigh(g_symbol, g_period, k + 1);
      double l  = iLow(g_symbol, g_period, k + 1);
      double pc = iClose(g_symbol, g_period, k + 2);
      double r1 = h - l;
      double r2 = MathAbs(h - pc);
      double r3 = MathAbs(l - pc);
      g_tr[k] = MathMax(r1, MathMax(r2, r3));
     }

   //--- current ATR = mean of the newest p true ranges
   double winSum = 0.0;
   for(int k = 0; k < p; k++)
      winSum += g_tr[k];
   g_atr = winSum / p;

   //--- rolling ATRs for the percentile rank (O(w))
   double below = 0.0;
   int    cnt   = 0;
   for(int k = 1; k <= w; k++)
     {
      winSum += g_tr[k + p - 1] - g_tr[k - 1];
      double a = winSum / p;
      if(a <= g_atr) below += 1.0;
      cnt++;
     }
   g_atrPct = (cnt > 0) ? (below / cnt) : 0.5;
  }

//--- 6.2 Robust z-score -------------------------------------------
//     standard : z = (C - mean) / stdev
//     robust   : z = (C - median) / (1.4826 * MAD)
//     The 1.4826 factor makes MAD a consistent estimator of sigma
//     for normally distributed data.
void ComputeZScore()
  {
   int n = InpZPeriod;
   double c1 = iClose(g_symbol, g_period, 1);

   if(InpRobustZ)
     {
      for(int i = 0; i < n; i++)
         g_work[i] = iClose(g_symbol, g_period, i + 1);
      SortWorkAsc(n);

      double med = (n % 2 == 1) ? g_work[n / 2] : 0.5 * (g_work[n / 2 - 1] + g_work[n / 2]);

      for(int i = 0; i < n; i++)
         g_work[i] = MathAbs(iClose(g_symbol, g_period, i + 1) - med);
      SortWorkAsc(n);

      double mad = (n % 2 == 1) ? g_work[n / 2] : 0.5 * (g_work[n / 2 - 1] + g_work[n / 2]);
      double sigma = 1.4826 * mad;
      double floorSd = MathMax(g_point * 0.5, g_atr * 0.02);
      if(sigma < floorSd) sigma = floorSd;

      g_zMean = med;
      g_zStd  = sigma;
     }
   else
     {
      double sum = 0.0;
      double sum2 = 0.0;
      for(int i = 1; i <= n; i++)
        {
         double c = iClose(g_symbol, g_period, i);
         sum  += c;
         sum2 += c * c;
        }
      double mean = sum / n;
      double var  = (sum2 / n) - (mean * mean);
      if(var < 0.0) var = 0.0;
      double sd = MathSqrt(var);
      double floorSd = MathMax(g_point * 0.5, g_atr * 0.02);
      if(sd < floorSd) sd = floorSd;

      g_zMean = mean;
      g_zStd  = sd;
     }

   g_z = ClampD((c1 - g_zMean) / g_zStd, -50.0, 50.0);
  }

//--- 6.3 Normalised momentum --------------------------------------
void ComputeMomentum()
  {
   int k = InpMomLookback;
   if(g_atr <= 0.0)
     {
      g_momRaw = 0.0;
      return;
     }
   double c1 = iClose(g_symbol, g_period, 1);
   double ck = iClose(g_symbol, g_period, 1 + k);
   g_momRaw = (c1 - ck) / (g_atr * MathSqrt((double)k));
  }

//--- 6.4 Trend filter ---------------------------------------------
void ComputeTrend()
  {
   int p = InpTrendMAPeriod;
   int s = MathMax(1, InpTrendSlopeBars);

   double sum = 0.0;
   for(int i = 1; i <= p; i++)
      sum += iClose(g_symbol, g_period, i);
   g_trendMA = sum / p;

   double sumPrev = 0.0;
   for(int i = 1 + s; i <= p + s; i++)
      sumPrev += iClose(g_symbol, g_period, i);
   double maPrev = sumPrev / p;

   g_trendSlope = (g_trendMA - maPrev);
   double c1 = iClose(g_symbol, g_period, 1);

   if(g_trendSlope > 0.0 && c1 > g_trendMA)      g_trendBias = 1;
   else if(g_trendSlope < 0.0 && c1 < g_trendMA) g_trendBias = -1;
   else                                          g_trendBias = 0;
  }

//--- 6.5 Lo-MacKinlay variance ratio ------------------------------
//     VR(q) = Var(q-period return) / (q * Var(1-period return))
//     VR = 1 -> random walk, VR < 1 -> mean reverting,
//     VR > 1 -> trending / momentum.
void ComputeVarianceRatio()
  {
   int q = InpVRHorizon;
   int w = InpVRWindow;
   if(w <= q + 4)
     {
      g_vr = 1.0;
      return;
     }

   int n1 = w;
   double s1 = 0.0;
   for(int i = 0; i < n1; i++)
     {
      double r = iClose(g_symbol, g_period, i + 1) - iClose(g_symbol, g_period, i + 2);
      g_work[i] = r;
      s1 += r;
     }
   double m1 = s1 / n1;
   double v1 = 0.0;
   for(int i = 0; i < n1; i++)
     {
      double d = g_work[i] - m1;
      v1 += d * d;
     }
   v1 /= (n1 - 1);
   if(v1 <= QE_EPS)
     {
      g_vr = 1.0;
      return;
     }

   int nq = w - q;
   double sq = 0.0;
   for(int i = 0; i < nq; i++)
     {
      double r = iClose(g_symbol, g_period, i + 1) - iClose(g_symbol, g_period, i + 1 + q);
      g_work[i] = r;
      sq += r;
     }
   double mq = sq / nq;
   double vq = 0.0;
   for(int i = 0; i < nq; i++)
     {
      double d = g_work[i] - mq;
      vq += d * d;
     }
   vq /= (nq - 1);

   g_vr = vq / (q * v1);
  }

//--- 6.6 Ornstein-Uhlenbeck half-life -----------------------------
//     OLS of dp_t on p_{t-1}:  dp = a + b*p,  theta = -b
//     HL = ln(2) / theta ,  only defined for -1 < b < 0.
//
//     Two corrections matter in practice and both are applied here:
//
//     1. Kendall bias correction  b* = b + (1 + 3b)/n
//        The OLS slope of an AR(1) is biased towards zero in finite
//        samples (Hurwicz). Left uncorrected the EA reads reversion
//        as faster than it is, which is the unsafe direction.
//
//     2. Dickey-Fuller significance.  For a pure random walk the
//        statistic t = b/se(b) is *not* standard normal; its 5%
//        critical value with a constant is about -2.86. Requiring
//        t <= -2.86 rejects a random walk ~95% of the time. Without
//        this test, ~30-50% of random walks produce a plausible
//        looking "half-life" and the mean-reversion branch trades noise.
void ComputeHalfLife()
  {
   int w = InpHalfLifeWindow;
   g_halfLife = -1.0;
   g_hlTStat  = 0.0;
   if(w < 20 || w >= QE_MAX_WINDOW)
      return;

   double sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
   for(int i = 0; i < w; i++)
     {
      double pPrev = iClose(g_symbol, g_period, i + 2);
      double pNow  = iClose(g_symbol, g_period, i + 1);
      double dp    = pNow - pPrev;
      g_work[i] = pPrev;     // regressor
      g_tr[i]   = dp;        // regressand
      sx  += pPrev;
      sy  += dp;
      sxx += pPrev * pPrev;
      sxy += pPrev * dp;
     }

   double n = (double)w;
   double denom = n * sxx - sx * sx;
   if(MathAbs(denom) < QE_EPS)
      return;

   double b = (n * sxy - sx * sy) / denom;
   double a = (sy - b * sx) / n;

   //--- residual variance and the standard error of the slope
   double sse = 0.0;
   for(int i = 0; i < w; i++)
     {
      double e = g_tr[i] - a - b * g_work[i];
      sse += e * e;
     }
   double sxxc = sxx - (sx * sx) / n;
   if(sse <= 0.0 || sxxc <= 0.0 || w < 3)
      return;
   double se = MathSqrt((sse / (n - 2.0)) / sxxc);
   if(se <= 0.0)
      return;
   g_hlTStat = b / se;

   //--- Kendall bias correction, then the half-life itself
   double bc = b + (1.0 + 3.0 * b) / n;
   if(bc >= 0.0 || bc <= -1.0)
      return;                       // no exploitable reversion
   g_halfLife = MathLog(2.0) / (-MathLog(1.0 + bc));
  }

//--- 6.7 Fibonacci confluence -------------------------------------
//     Locate the dominant swing of the lookback window, then measure
//     how close price is to the configured retracement levels, in
//     ATR units. Output is in [-1,+1] and signed with the swing.
void ComputeFib()
  {
   int L = InpFibLookback;
   g_fibScore = 0.0;
   if(L < 20 || g_atr <= 0.0) return;

   int    hiIdx = 1, loIdx = 1;
   double hi = -1.0e18, lo = 1.0e18;
   for(int i = 1; i <= L; i++)
     {
      double h = iHigh(g_symbol, g_period, i);
      double l = iLow(g_symbol, g_period, i);
      if(h > hi) { hi = h; hiIdx = i; }
      if(l < lo) { lo = l; loIdx = i; }
     }
   g_fibHigh = hi;
   g_fibLow  = lo;

   double range = hi - lo;
   if(range <= g_atr * 2.0) return;          // swing too small to be meaningful

   bool   upLeg = (hiIdx < loIdx);           // the high is the more recent extreme
   double c     = iClose(g_symbol, g_period, 1);
   double best  = 0.0;
   double lv[3];
   lv[0] = InpFibLevel1;
   lv[1] = InpFibLevel2;
   lv[2] = InpFibLevel3;

   for(int k = 0; k < 3; k++)
     {
      if(lv[k] <= 0.0 || lv[k] >= 1.0) continue;
      double level = upLeg ? (hi - lv[k] * range) : (lo + lv[k] * range);
      double distATR = MathAbs(c - level) / g_atr;
      if(distATR > InpFibTolATR) continue;
      double strength = 1.0 - (distATR / MathMax(InpFibTolATR, 0.01));
      double s = upLeg ? strength : -strength;
      if(MathAbs(s) > MathAbs(best)) best = s;
     }
   g_fibScore = ClampD(best, -1.0, 1.0);
  }

//--- 6.8 Composite score ------------------------------------------
//     Every factor is clipped to [-1,+1] and combined linearly, then
//     divided by the sum of absolute weights: the result is bounded
//     by construction, which is what makes the threshold portable
//     across instruments and timeframes.
void UpdateSignalEngine()
  {
   g_mathReady = false;
   g_blockReason = "";

   if(Bars < g_neededBars)
     {
      g_blockReason = "warming up";
      return;
     }

   ComputeATRStats();
   if(g_atr <= 0.0)
     {
      g_blockReason = "no ATR";
      return;
     }
   ComputeZScore();
   ComputeMomentum();
   ComputeTrend();
   ComputeVarianceRatio();
   ComputeHalfLife();
   ComputeFib();

   //--- regime from the variance ratio
   if(g_vr <= 1.0 - InpVRThreshold)      g_regime = -1;   // mean reverting
   else if(g_vr >= 1.0 + InpVRThreshold) g_regime = 1;    // trending
   else                                  g_regime = 0;    // inconclusive

   //--- mode selection
   bool mrMode = false;
   bool moMode = false;
   bool fibMode = false;
   if(InpStrategy == QE_MEANREV)       mrMode = true;
   else if(InpStrategy == QE_MOMENTUM) moMode = true;
   else if(InpStrategy == QE_FIBONLY)  fibMode = true;
   else
     {
      if(g_regime == -1)      mrMode = true;
      else if(g_regime == 1)  moMode = true;
      else
        {
         //--- the variance ratio is a weak tilt, not a test: when it is
         //--- inconclusive fall back to the configured base thesis
         if(InpNeutralRegime == QE_NEUTRAL_MR)      mrMode = true;
         else if(InpNeutralRegime == QE_NEUTRAL_MO) moMode = true;
        }
     }
   g_useMR = mrMode;
   g_useMO = moMode;
   g_useFB = fibMode;

   //--- normalised factors
   double cap = MathMax(InpZCap, 0.5);
   double fz = ClampD(g_z / cap, -1.0, 1.0);
   double fm = ClampD(g_momRaw / MathMax(InpMomCap, 0.1), -1.0, 1.0);
   double ff = g_fibScore;

   if(mrMode)
     {
      fz = -fz;          // fade the deviation
      fm = -fm;          // fade the move
     }

   double wz = InpWeightZ;
   double wm = InpWeightMom;
   double wf = InpWeightFib;
   if(fibMode)
     {
      wz = 0.0;
      wm = 0.0;
     }
   if(!mrMode && !moMode && !fibMode)
     {
      wz = 0.0; wm = 0.0; wf = 0.0;   // inconclusive regime in ADAPTIVE mode
     }

   double wsum = MathAbs(wz) + MathAbs(wm) + MathAbs(wf);
   g_score = (wsum > QE_EPS) ? ((wz * fz + wm * fm + wf * ff) / wsum) : 0.0;
   g_score = ClampD(g_score, -1.0, 1.0);

   //--- hard gates
   bool tSignificant = (InpHLTStatMin <= 0.0) ? true : (g_hlTStat <= -InpHLTStatMin);
   g_volOk        = (g_atrPct >= InpMinATRPercentile && g_atrPct <= InpMaxATRPercentile);
   g_mrHorizonOk  = (g_halfLife > 0.0 && g_halfLife <= InpMaxHalfLifeBars &&
                     (!InpRequireHalfLifeGate || tSignificant));
   g_trendOk      = (!InpUseTrendFilter) || (moMode ? (g_trendBias != 0) : true);

   //--- direction
   g_dir = 0;
   if(g_score >= InpEntryThreshold)       g_dir = 1;
   else if(g_score <= -InpEntryThreshold) g_dir = -1;

   if(MathAbs(g_score) < InpEntryThreshold) g_blockReason = "score below threshold";
   g_mathReady = true;
  }

//==================================================================
//  7. ACCOUNT ANCHORS AND FTMO GOVERNORS
//     FTMO measures the daily loss from the equity/balance at the
//     start of the trading day and the total loss from the phase
//     starting balance (static). Both are enforced here with a
//     safety buffer, and the hard FTMO thresholds act as a last
//     resort circuit breaker.
//==================================================================
#define QE_MAX_TRACK 64
int      g_tkTicket[QE_MAX_TRACK];
double   g_tkSL[QE_MAX_TRACK];
double   g_tkEntry[QE_MAX_TRACK];
int      g_tkMode[QE_MAX_TRACK];       // -1 mean reversion, +1 momentum, 0 fibonacci
int      g_tkCount = 0;

double   g_lastTickTime = 0;
datetime g_sessionOpenTime = 0;
datetime g_weekendLatch = 0;
int      g_hardBreachCount = 0;

//--- forward declarations (helpers used before their definition)
bool     InNewsWindow();
string   PeriodToStr();
void     CloseAll(string why);
void     CsvLog(string evt, int dir, double lots, double price, double sl, double tp, string note);

void TrackClear()
  {
   g_tkCount = 0;
   for(int i = 0; i < QE_MAX_TRACK; i++)
     {
      g_tkTicket[i] = 0;
      g_tkSL[i] = 0.0;
      g_tkEntry[i] = 0.0;
      g_tkMode[i] = 0;
     }
  }

void TrackAdd(int ticket, double sl, double entry, int mode)
  {
   for(int i = 0; i < g_tkCount; i++)
      if(g_tkTicket[i] == ticket)
        {
         g_tkSL[i] = sl;
         g_tkEntry[i] = entry;
         g_tkMode[i] = mode;
         return;
        }
   if(g_tkCount >= QE_MAX_TRACK) return;
   g_tkTicket[g_tkCount] = ticket;
   g_tkSL[g_tkCount] = sl;
   g_tkEntry[g_tkCount] = entry;
   g_tkMode[g_tkCount] = mode;
   g_tkCount++;
  }

bool TrackGet(int ticket, double &sl, double &entry)
  {
   for(int i = 0; i < g_tkCount; i++)
      if(g_tkTicket[i] == ticket)
        {
         sl = g_tkSL[i];
         entry = g_tkEntry[i];
         return(true);
        }
   return(false);
  }

int TrackMode(int ticket)
  {
   for(int i = 0; i < g_tkCount; i++)
      if(g_tkTicket[i] == ticket)
         return(g_tkMode[i]);
   return(0);
  }

//--- drop tracked tickets that no longer exist in the terminal
void TrackPrune()
  {
   int keep = 0;
   for(int i = 0; i < g_tkCount; i++)
     {
      bool alive = false;
      if(OrderSelect(g_tkTicket[i], SELECT_BY_TICKET, MODE_TRADES))
         if(OrderSymbol() == g_symbol && OrderMagicNumber() == g_magic)
            alive = true;
      if(alive)
        {
         g_tkTicket[keep] = g_tkTicket[i];
         g_tkSL[keep] = g_tkSL[i];
         g_tkEntry[keep] = g_tkEntry[i];
         g_tkMode[keep] = g_tkMode[i];
         keep++;
        }
     }
   g_tkCount = keep;
  }

//--- the trading day, shifted by the configured rollover time
datetime TradingDayStart(datetime t)
  {
   datetime d = DayStartOf(t);
   int roll = InpDayRollHour * 3600 + InpDayRollMinute * 60;
   if((int)(t - d) < roll)
      d -= 86400;
   return(d + roll);
  }

void EnsureInitialBalance()
  {
   if(InpInitialBalance > 0.0)
     {
      g_initialBalance = InpInitialBalance;
      return;
     }

   if(IsTesting() || IsOptimization())
     {
      g_initialBalance = AccountBalance();
      return;
     }

   string key = "QE_IB_" + IntegerToString(AccountNumber()) + "_" + IntegerToString(g_magic);
   if(InpResetStoredAnchors)
     {
      GlobalVariableDel(key);
      Print("QE: stored phase balance cleared for ", key);
     }
   if(GlobalVariableCheck(key))
      g_initialBalance = GlobalVariableGet(key);
   else
     {
      g_initialBalance = AccountBalance();
      GlobalVariableSet(key, g_initialBalance);
      PrintFormat("QE: phase starting balance stored = %.2f %s", g_initialBalance, AccountCurrency());
     }
   if(g_initialBalance <= 0.0) g_initialBalance = AccountBalance();
  }

//--- (re)capture the daily anchor at each rollover
void RefreshDayAnchor()
  {
   datetime tds = TradingDayStart(TimeCurrent());
   if(tds == g_dayStamp && g_anchorLive) return;

   g_dayStamp  = tds;
   double b = AccountBalance();
   double e = AccountEquity();
   if(InpDailyAnchorMode == QE_ANCHOR_BALANCE)      g_dayAnchor = b;
   else if(InpDailyAnchorMode == QE_ANCHOR_EQUITY)  g_dayAnchor = e;
   else                                             g_dayAnchor = MathMax(b, e);
   if(g_dayAnchor <= 0.0) g_dayAnchor = b;
   g_anchorLive = true;

   g_dailyHalted = false;
   g_tradesToday = 0;
   g_tradeDay    = tds;
  }

double DailyLossPct()
  {
   if(!g_anchorLive || g_dayAnchor <= 0.0) return(0.0);
   double dd = g_dayAnchor - AccountEquity();
   if(dd <= 0.0) return(0.0);
   return(100.0 * dd / g_dayAnchor);
  }

double TotalLossPct()
  {
   if(g_initialBalance <= 0.0) return(0.0);
   double dd = g_initialBalance - AccountEquity();
   if(dd <= 0.0) return(0.0);
   return(100.0 * dd / g_initialBalance);
  }

double ProfitPct()
  {
   if(g_initialBalance <= 0.0) return(0.0);
   return(100.0 * (AccountEquity() - g_initialBalance) / g_initialBalance);
  }

//--- distance from the nearest governor in percent terms
double RemainingDailyBudgetPct()
  {
   double used = DailyLossPct();
   return(MathMax(0.0, InpDailyRiskBudgetPct - used));
  }

//--- total equity at risk in the currently open EA positions (%)
double OpenRiskPct()
  {
   if(AccountEquity() <= 0.0) return(0.0);
   double total = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != g_symbol || OrderMagicNumber() != g_magic) continue;
      if(OrderType() > OP_SELL) continue;

      double sl = OrderStopLoss();
      double entry = OrderOpenPrice();
      double initSL = 0.0, initEntry = 0.0;
      if(TrackGet(OrderTicket(), initSL, initEntry))
        {
         if(initSL > 0.0) sl = initSL;
         if(initEntry > 0.0) entry = initEntry;
        }
      double dist = MathAbs(entry - sl);
      if(dist <= 0.0) dist = InpSL_ATR_Mult * g_atr;
      double vpp = ValuePerPointPerLot();
      if(vpp <= 0.0 || g_point <= 0.0) continue;
      total += (dist / g_point) * vpp * OrderLots();
     }
   return(100.0 * total / AccountEquity());
  }

int CountEAPositions(int dir)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != g_symbol || OrderMagicNumber() != g_magic) continue;
      if(OrderType() > OP_SELL) continue;
      if(dir > 0 && OrderType() == OP_BUY)  n++;
      if(dir < 0 && OrderType() == OP_SELL) n++;
     }
   return(n);
  }

void CsvLog(string evt, int dir, double lots, double price, double sl, double tp, string note);

void UpdateGovernors()
  {
   RefreshDayAnchor();
   if(g_initialBalance <= 0.0) EnsureInitialBalance();

   //--- hard FTMO thresholds: always flatten, these end the account
   if(DailyLossPct() >= InpMaxDailyLossPct)
     {
      if(g_hardBreachCount == 0 || g_hardBreachCount % 50 == 0)
         PrintFormat("QE: !!! FTMO DAILY LOSS LIMIT REACHED (%.2f%% >= %.2f%%) - EMERGENCY FLATTEN !!!",
                     DailyLossPct(), InpMaxDailyLossPct);
      g_hardBreachCount++;
      g_dailyHalted = true;
      CloseAll("FTMO daily limit");
      return;
     }
   if(TotalLossPct() >= InpMaxTotalLossPct)
     {
      PrintFormat("QE: !!! FTMO MAXIMUM LOSS REACHED (%.2f%% >= %.2f%%) - EMERGENCY FLATTEN !!!",
                  TotalLossPct(), InpMaxTotalLossPct);
      g_totalHalted = true;
      CloseAll("FTMO maximum loss");
      return;
     }

   //--- soft (EA) buffers: stop trading early, well before the rules bite
   if(!g_dailyHalted && DailyLossPct() >= InpDailyRiskBudgetPct)
     {
      g_dailyHalted = true;
      PrintFormat("QE: daily risk budget used (%.2f%% of %.2f%%) - no new entries until %s",
                  DailyLossPct(), InpDailyRiskBudgetPct, TimeToString(g_dayStamp + 86400, TIME_DATE|TIME_MINUTES));
      CsvLog("DAILY_HALT", 0, 0, 0, 0, 0, DoubleToString(DailyLossPct(), 2));
      if(InpCloseAllOnBreach) CloseAll("daily risk budget");
     }

   if(!g_totalHalted && TotalLossPct() >= InpTotalRiskBudgetPct)
     {
      g_totalHalted = true;
      PrintFormat("QE: total risk budget used (%.2f%% of %.2f%%) - trading suspended",
                  TotalLossPct(), InpTotalRiskBudgetPct);
      CsvLog("TOTAL_HALT", 0, 0, 0, 0, 0, DoubleToString(TotalLossPct(), 2));
      if(InpCloseAllOnBreach) CloseAll("total risk budget");
     }

   if(InpLockAtProfitTarget && !g_targetLocked && ProfitPct() >= InpProfitTargetPct)
     {
      g_targetLocked = true;
      PrintFormat("QE: profit target reached (%.2f%% >= %.2f%%) - entries locked",
                  ProfitPct(), InpProfitTargetPct);
      CsvLog("TARGET_LOCK", 0, 0, 0, 0, 0, DoubleToString(ProfitPct(), 2));
      if(InpFlattenOnProfitLock) CloseAll("profit target lock");
     }

   //--- weekend handling (FTMO Normal accounts must be flat over the weekend)
   int dow = TimeDayOfWeek(TimeCurrent());
   int hh  = TimeHour(TimeCurrent());
   int mm  = TimeMinute(TimeCurrent());
   if(InpCloseBeforeWeekend && dow == 5 && hh >= InpFridayCloseHour)
     {
      datetime wk = TradingDayStart(TimeCurrent());
      if(g_weekendLatch != wk)
        {
         g_weekendLatch = wk;
         g_weekendHalted = true;
         Print("QE: weekend flatten (Friday ", InpFridayCloseHour, ":00 server)");
         CsvLog("WEEKEND_FLAT", 0, 0, 0, 0, 0, "");
         CloseAll("weekend flatten");
        }
     }
   if(dow == 1 || dow == 2)   // new week: release the weekend latch
      g_weekendHalted = false;
  }

//--- is a new entry in direction 'dir' allowed right now?
//--- writes a human readable reason when it is not
bool TradingAllowed(int dir, string &reason)
  {
   reason = "";
   if(!IsTradeAllowed())
     { reason = "auto trading disabled"; return(false); }
   if(InpDailyRiskBudgetPct > 0 && g_dailyHalted)
     { reason = "daily governor halted"; return(false); }
   if(g_totalHalted)
     { reason = "total-loss governor halted"; return(false); }
   if(g_targetLocked)
     { reason = "profit target locked"; return(false); }
   if(InpCloseBeforeWeekend && g_weekendHalted)
     { reason = "weekend flat"; return(false); }
   if(!IsTesting() && !IsOptimization())
     {
      if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
        { reason = "terminal trading disabled"; return(false); }
      if(AccountInfoInteger(ACCOUNT_TRADE_EXPERT) == 0)
        { reason = "expert trading disabled on account"; return(false); }
     }

   //--- trade frequency and execution profile
   datetime now = TimeCurrent();
   if(g_lastEntryTime > 0 && (now - g_lastEntryTime) < InpMinSecBetweenTrades)
     { reason = "minimum time between entries"; return(false); }
   if(InpOneTradePerBar && g_lastEntryBar == iTime(g_symbol, g_period, 0))
     { reason = "already traded this bar"; return(false); }
   int todayCount = g_tradesToday;
   if(InpMaxTradesPerDay > 0 && todayCount >= InpMaxTradesPerDay)
     { reason = "daily trade cap reached"; return(false); }

   //--- position limits
   if(CountEAPositions(0) >= InpMaxOpenPositions)
     { reason = "maximum open positions"; return(false); }
   if(!InpAllowHedge && dir != 0 && CountEAPositions(-dir) > 0)
     { reason = "opposite position open (hedging disabled)"; return(false); }
   if(OpenRiskPct() >= InpMaxOpenRiskPct)
     { reason = "aggregate open risk cap"; return(false); }

   //--- remaining daily budget must still cover one standard trade
   if(RemainingDailyBudgetPct() < InpRiskPercent * 0.99)
     { reason = "insufficient remaining daily budget"; return(false); }

   //--- session window
   int hh = TimeHour(TimeCurrent());
   int mm = TimeMinute(TimeCurrent());
   int mins = hh * 60 + mm;
   int s1 = InpSessionStartHour * 60 + InpSessionStartMin;
   int s2 = InpSessionEndHour * 60 + InpSessionEndMin;
   if(InpUseSession && s2 > s1 && (mins < s1 || mins >= s2))
     { reason = "outside session window"; return(false); }

   //--- rollover spread spike
   if(InpSkipRolloverMin > 0)
     {
      if(hh == 23 && mm >= (60 - InpSkipRolloverMin)) { reason = "pre-rollover window"; return(false); }
      if(hh == 0  && mm <  InpSkipRolloverMin)        { reason = "post-rollover window"; return(false); }
     }

   //--- weekly / holiday open: no gap trading
   if(g_sessionOpenTime > 0 && (now - g_sessionOpenTime) < InpReopenBlackoutMin * 60)
     { reason = "market open blackout"; return(false); }

   //--- Friday cut-off
   if(InpCloseBeforeWeekend && InpNoNewTradesFriday && dow == 5 && hh >= InpFridayNoTradeHour)
     { reason = "no new trades late Friday"; return(false); }

   //--- spread
   double maxSpread = InpMaxSpreadPoints;
   if(maxSpread <= 0.0 && g_spreadMedian > 0)
      maxSpread = InpAutoSpreadMult * (double)g_spreadMedian;
   if(maxSpread > 0.0 && SpreadPoints() > (int)maxSpread)
     { reason = "spread above cap"; return(false); }
   if(g_freezeLevel > 0 && SpreadPoints() > g_freezeLevel)
     { reason = "spread inside freeze level"; return(false); }

   //--- news blackout
   if(InpNewsFilter && InNewsWindow())
     { reason = "news blackout"; return(false); }

   return(true);
  }

//==================================================================
//  8. NEWS BLACKOUT
//     CSV rows:  YYYY.MM.DD;HH:MM;CCY;Impact;Title
//     Times must be in server time, matching TimeCurrent().
//==================================================================
bool LoadNews()
  {
   g_newsCount = 0;
   ResetLastError();
   int h = FileOpen(InpNewsFileName, FILE_READ|FILE_CSV|FILE_ANSI, ';');
   if(h == INVALID_HANDLE)
     {
      if(InpVerbose)
         PrintFormat("QE: news file '%s' not found (error %d) - news filter inert",
                     InpNewsFileName, GetLastError());
      return(false);
     }

   int guard = 0;
   while(!FileIsEnding(h) && g_newsCount < QE_MAX_NEWS && guard < QE_MAX_NEWS * 2)
     {
      guard++;
      string d = FileReadString(h);
      string t = FileReadString(h);
      string c = FileReadString(h);
      string imp = FileReadString(h);
      string title = FileReadString(h);
      if(StringLen(d) < 8 || StringFind(d, "YYYY") >= 0) continue;
      datetime when = StringToTime(d + " " + t);
      if(when <= 0) continue;
      g_newsTime[g_newsCount] = when;
      g_newsCcy[g_newsCount]  = c;
      g_newsHigh[g_newsCount] = (StringFind(imp, "igh") >= 0);
      g_newsCount++;
     }
   FileClose(h);
   g_lastNewsLoad = TimeCurrent();
   if(InpVerbose) PrintFormat("QE: %d news rows loaded from %s", g_newsCount, InpNewsFileName);
   return(g_newsCount > 0);
  }

//--- symbol currency exposure: "EURUSD" -> EUR and USD
bool CurrencyMatches(string rowCcy)
  {
   if(StringLen(rowCcy) < 3) return(false);
   string base = StringSubstr(g_symbol, 0, 3);
   string quote = StringSubstr(g_symbol, 3, 3);
   if(rowCcy == base || rowCcy == quote) return(true);
   if(rowCcy == "ALL" || rowCcy == "GLOBAL") return(true);
   return(false);
  }

bool InNewsWindow()
  {
   if(g_newsCount <= 0) return(false);
   datetime now = TimeCurrent();
   for(int i = 0; i < g_newsCount; i++)
     {
      if(InpNewsHighOnly && !g_newsHigh[i]) continue;
      if(!CurrencyMatches(g_newsCcy[i])) continue;
      if(now >= g_newsTime[i] - InpNewsBeforeMin * 60 &&
         now <= g_newsTime[i] + InpNewsAfterMin * 60)
         return(true);
     }
   return(false);
  }

//==================================================================
//  9. POSITION SIZING
//     lots = (equity * risk%) / (stopDistance * valuePerPoint)
//     then clamped by the aggregate risk cap, the remaining daily
//     budget and the broker lot constraints.
//==================================================================
double NormalizeLot(double lots)
  {
   if(g_lotStep <= 0.0) return(lots);
   lots = MathFloor(lots / g_lotStep + 0.0000001) * g_lotStep;
   if(lots < g_minLot) return(0.0);
   //--- the caps are applied on the same grid, so a clamp can never produce
   //--- a volume the broker would reject
   if(lots > g_maxLot)
      lots = MathFloor(g_maxLot / g_lotStep) * g_lotStep;
   if(lots > InpMaxLots)
      lots = MathFloor(InpMaxLots / g_lotStep) * g_lotStep;
   if(lots < g_minLot) return(0.0);
   int dec = 2;
   if(g_lotStep >= 1.0)      dec = 0;
   else if(g_lotStep >= 0.1) dec = 1;
   else if(g_lotStep >= 0.01) dec = 2;
   else dec = 3;
   return(NormalizeDouble(lots, dec));
  }

double RiskPercentToLots(double riskPct, double stopDistance)
  {
   double vpp = ValuePerPointPerLot();
   if(vpp <= 0.0 || g_point <= 0.0 || stopDistance <= 0.0) return(0.0);
   double money = AccountEquity() * riskPct / 100.0;
   double moneyPerLot = (stopDistance / g_point) * vpp;
   if(moneyPerLot <= 0.0) return(0.0);
   return(money / moneyPerLot);
  }

double CalcLots(double stopDistance)
  {
   if(stopDistance <= 0.0) return(0.0);
   double riskPct = MathMin(InpRiskPercent, InpMaxRiskPercent);

   //--- aggregate cap: never let open risk exceed the configured ceiling
   double already = OpenRiskPct();
   double roomAgg  = InpMaxOpenRiskPct - already;
   if(roomAgg <= 0.0) return(0.0);
   riskPct = MathMin(riskPct, roomAgg);

   //--- daily cap: the trade in full loss must not trip the governor
   double roomDay = RemainingDailyBudgetPct();
   if(roomDay <= 0.0) return(0.0);
   riskPct = MathMin(riskPct, roomDay);

   //--- total cap
   double roomTot = InpTotalRiskBudgetPct - TotalLossPct();
   if(roomTot <= 0.0) return(0.0);
   riskPct = MathMin(riskPct, roomTot);

   double lots = RiskPercentToLots(riskPct, stopDistance);
   lots = NormalizeLot(lots);
   return(lots);
  }

//==================================================================
//  10. ORDER EXECUTION
//==================================================================
double MinStopDistancePrice()
  {
   double d = g_stopLevel * g_point;
   d = MathMax(d, InpMinStopDistancePts * g_point);
   d = MathMax(d, SpreadPoints() * g_point * 1.5);
   d = MathMax(d, 2.0 * g_point);
   return(d);
  }

bool IsRetryableError(int err)
  {
   if(err == 128 || err == 135 || err == 136 || err == 137 || err == 138 ||
      err == 145 || err == 146 || err == 147 || err == 148 || err == 149)
      return(true);
   return(false);
  }

string ErrorText(int err)
  {
   switch(err)
     {
      case 128: return "trade timeout";
      case 129: return "invalid price";
      case 130: return "invalid stops";
      case 131: return "invalid volume";
      case 132: return "market closed";
      case 133: return "trading disabled";
      case 134: return "not enough money";
      case 135: return "price changed";
      case 136: return "off quotes";
      case 137: return "broker busy";
      case 138: return "requote";
      case 145: return "modification denied (order too close)";
      case 146: return "trade context busy";
      case 147: return "expiration denied";
      case 148: return "too many orders";
      case 149: return "hedging prohibited";
      case 4109: return "trading not allowed";
      case 4110: return "longs not allowed";
      case 4111: return "shorts not allowed";
     }
   return("error " + IntegerToString(err));
  }

int OpenTrade(int dir, double lots, double sl, double tp, string tag, int mode)
  {
   if(lots <= 0.0) return(0);
   int cmd = (dir > 0) ? OP_BUY : OP_SELL;
   string comment = InpTradeComment + ((tag == "") ? "" : "-" + tag);

   for(int attempt = 0; attempt < MathMax(1, InpMaxRetries); attempt++)
     {
      if(!IsTradeAllowed())
        {
         Print("QE: trading not allowed at order time");
         return(0);
        }
      RefreshRates();

      double price = (dir > 0) ? AskPrice() : BidPrice();
      if(price <= 0.0) return(0);

      //--- recompute distances against live prices on every attempt
      double minDist = MinStopDistancePrice();
      double slAdj = sl;
      double tpAdj = tp;
      if(dir > 0)
        {
         if(slAdj > 0.0 && price - slAdj < minDist) slAdj = price - minDist;
         if(tpAdj > 0.0 && tpAdj - price < minDist) tpAdj = price + minDist;
        }
      else
        {
         if(slAdj > 0.0 && slAdj - price < minDist) slAdj = price + minDist;
         if(tpAdj > 0.0 && price - tpAdj < minDist) tpAdj = price - minDist;
        }
      slAdj = NormalizeDouble(slAdj, g_digits);
      tpAdj = NormalizeDouble(tpAdj, g_digits);

      int ticket = OrderSend(g_symbol, cmd, lots, NormalizeDouble(price, g_digits),
                             InpSlippagePoints, slAdj, tpAdj, comment, g_magic, 0,
                             (dir > 0) ? clrDodgerBlue : clrOrangeRed);
      if(ticket > 0)
        {
         TrackAdd(ticket, slAdj, price, mode);
         if(OrderSelect(ticket, SELECT_BY_TICKET))
            PrintFormat("QE: %s %.2f %s @%s sl=%s tp=%s ticket=%d",
                        (dir > 0 ? "BUY" : "SELL"), lots, g_symbol,
                        DoubleToString(OrderOpenPrice(), g_digits),
                        DoubleToString(slAdj, g_digits),
                        DoubleToString(tpAdj, g_digits), ticket);
         CsvLog("OPEN", dir, lots, price, slAdj, tpAdj, tag);
         return(ticket);
        }

      int err = GetLastError();
      PrintFormat("QE: OrderSend failed (%s) attempt %d/%d", ErrorText(err), attempt + 1, InpMaxRetries);
      if(err == 134 || err == 131)
         return(0);                          // money / volume problems: retrying is pointless
      if(!IsRetryableError(err) && err != 130)
         return(0);
      if(!IsTesting()) Sleep(InpRetryDelayMs);
     }
   return(0);
  }

bool ClosePosition(int ticket, double lots, string why)
  {
   for(int attempt = 0; attempt < MathMax(1, InpMaxRetries); attempt++)
     {
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return(true); // already gone
      if(!IsTradeAllowed()) return(false);
      RefreshRates();

      int    type = OrderType();
      double vol  = MathMin(lots, OrderLots());
      double px   = (type == OP_BUY) ? BidPrice() : AskPrice();
      if(px <= 0.0) return(false);

      if(OrderClose(ticket, vol, NormalizeDouble(px, g_digits), InpSlippagePoints, clrGold))
        {
         PrintFormat("QE: closed #%d (%.2f lots) - %s", ticket, vol, why);
         CsvLog("CLOSE", (type == OP_BUY ? 1 : -1), vol, px, 0, 0, why);
         return(true);
        }

      int err = GetLastError();
      PrintFormat("QE: OrderClose #%d failed (%s) attempt %d", ticket, ErrorText(err), attempt + 1);
      if(err == 4108 || err == 4109 || err == 4051) return(false);
      if(!IsRetryableError(err)) return(false);
      if(!IsTesting()) Sleep(InpRetryDelayMs);
     }
   return(false);
  }

bool ModifyPosition(int ticket, double newSL, double newTP, string why)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return(false);
   double curSL = OrderStopLoss();
   double curTP = OrderTakeProfit();
   if(MathAbs(curSL - newSL) < g_point * 0.5 && MathAbs(curTP - newTP) < g_point * 0.5)
      return(true);

   for(int attempt = 0; attempt < 2; attempt++)
     {
      RefreshRates();
      if(OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(newSL, g_digits),
                     NormalizeDouble(newTP, g_digits), 0, clrYellow))
        {
         if(InpVerbose) PrintFormat("QE: modified #%d - %s", ticket, why);
         return(true);
        }
      int err = GetLastError();
      if(err == 1) return(true);              // no changes
      if(!IsRetryableError(err) && err != 1)
        {
         if(InpVerbose) PrintFormat("QE: modify #%d failed (%s)", ticket, ErrorText(err));
         return(false);
        }
      if(!IsTesting()) Sleep(150);
     }
   return(false);
  }

void CloseAll(string why)
  {
   int attempts = 0;
   while(attempts < 3)
     {
      attempts++;
      bool anyLeft = false;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
         if(OrderSymbol() != g_symbol || OrderMagicNumber() != g_magic) continue;
         if(OrderType() > OP_SELL) continue;
         anyLeft = true;
         ClosePosition(OrderTicket(), OrderLots(), why);
        }
      if(!anyLeft) break;
     }
   //--- keep tracking anything that refused to close, so its original stop
   //--- is not lost and the R arithmetic stays correct
   TrackPrune();
  }

//==================================================================
//  11. POSITION MANAGEMENT
//==================================================================
void ManageOnePosition()
  {
   int    ticket = OrderTicket();
   int    type   = OrderType();
   double entry  = OrderOpenPrice();
   double sl     = OrderStopLoss();
   double tp     = OrderTakeProfit();
   double lots   = OrderLots();
   datetime opened = OrderOpenTime();

   double initSL = sl, initEntry = entry;
   TrackGet(ticket, initSL, initEntry);
   if(initEntry > 0.0) entry = initEntry;
   if(initSL <= 0.0) initSL = sl;

   int    dir = (type == OP_BUY) ? 1 : -1;

   //--- safety net: a position with no protective stop is an unbounded risk
   //--- on a prop account, whatever created it. Re-arm it from ATR.
   if(sl <= 0.0 && g_atr > 0.0)
     {
      double d = MathMax(InpSL_ATR_Mult * g_atr, MinStopDistancePrice());
      double restore = NormalizeDouble(entry - dir * d, g_digits);
      if(ModifyPosition(ticket, restore, tp, "restore missing stop"))
        {
         sl = restore;
         initSL = restore;
         TrackAdd(ticket, restore, entry, TrackMode(ticket));
        }
     }

   double risk = MathAbs(entry - initSL);
   if(risk <= 0.0) risk = InpSL_ATR_Mult * g_atr;
   if(risk <= 0.0) return;
   double px  = (dir > 0) ? BidPrice() : AskPrice();
   double profitPrice = (px - entry) * dir;      // in price units
   double rMultiple   = profitPrice / risk;
   int    secsOpen    = (int)(TimeCurrent() - opened);              // explicit int maths
   int    barSeconds  = MathMax(1, PeriodSeconds(g_period));
   int    barsOpen    = (barSeconds > 0) ? (secsOpen / barSeconds) : 0;
   bool   minDurationOk = (secsOpen >= InpMinTradeDurationSec);

   //--- 11.1 break-even lock
   if(InpUseBreakEven && rMultiple >= InpBreakEvenR && minDurationOk)
     {
      double lock = InpBreakEvenLockPts * g_point;
      double be   = NormalizeDouble(entry + dir * lock, g_digits);
      bool better = (dir > 0) ? (be > sl + g_point * 0.5) : (be < sl - g_point * 0.5 || sl == 0.0);
      if(better)
        {
         double minDist = MinStopDistancePrice();
         bool valid = (dir > 0) ? (px - be >= minDist) : (be - px >= minDist);
         if(valid) ModifyPosition(ticket, be, tp, "break-even");
        }
     }

   //--- 11.2 ATR trailing stop (only ever tightens)
   if(InpUseTrailingStop && minDurationOk)
     {
      double dist = MathMax(InpTrailATRMult * g_atr, MinStopDistancePrice());
      double cand = (dir > 0) ? (px - dist) : (px + dist);
      bool better = (dir > 0) ? (cand > sl + g_point * 0.5)
                              : (sl == 0.0 || cand < sl - g_point * 0.5);
      if(better) ModifyPosition(ticket, cand, tp, "trailing stop");
     }

   //--- 11.3 statistical exit: deviation has normalised.
   //--- Only applied to trades opened by the mean-reversion branch, where
   //--- "z back to the mean" is the thesis. A momentum or Fibonacci trade
   //--- has no such thesis and is left to its own stop, target and clock.
   if(InpExitOnZNeutral && g_mathReady && minDurationOk && TrackMode(ticket) == -1)
     {
      bool normalised = false;
      if(dir > 0 && g_z >= -InpZExitLevel) normalised = true;
      if(dir < 0 && g_z <=  InpZExitLevel) normalised = true;
      // only meaningful once the trade is at least flat
      if(normalised && rMultiple > -0.25)
        {
         if(ClosePosition(ticket, lots, "z normalised"))
           { TrackPrune(); return; }
        }
     }

   //--- 11.4 time stops
   bool timeStop = false;
   string why = "";
   if(InpMaxBarsInTrade > 0 && barsOpen >= InpMaxBarsInTrade)
     {
      timeStop = true;
      why = "max bars in trade";
     }
   if(InpUseHalfLifeStop && g_halfLife > 0.0 && (double)barsOpen >= InpHalfLifeStopMult * g_halfLife)
     {
      timeStop = true;
      why = "half-life time stop";
     }
   if(timeStop && minDurationOk)
     {
      if(ClosePosition(ticket, lots, why))
        { TrackPrune(); return; }
     }
  }

void ManagePositions()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != g_symbol || OrderMagicNumber() != g_magic) continue;
      if(OrderType() > OP_SELL) continue;
      ManageOnePosition();
     }
  }

//==================================================================
//  12. ENTRY LOGIC
//==================================================================
void TryEntry()
  {
   if(!g_mathReady) return;
   if(g_dir == 0) return;

   string block = "";
   if(!TradingAllowed(g_dir, block))
     {
      if(InpVerbose) Print("QE: entry blocked - ", block);
      return;
     }

   //--- hard statistical gates
   if(!g_volOk)
     {
      if(InpVerbose) PrintFormat("QE: blocked - volatility percentile %.2f outside [%.2f,%.2f]",
                                 g_atrPct, InpMinATRPercentile, InpMaxATRPercentile);
      return;
     }
   if(MathAbs(g_z) < InpMinAbsZ)
     {
      if(InpVerbose) PrintFormat("QE: blocked - |z| %.2f < %.2f", MathAbs(g_z), InpMinAbsZ);
      return;
     }
   if(g_useMR && InpRequireHalfLifeGate && !g_mrHorizonOk)
     {
      if(InpVerbose)
         PrintFormat("QE: blocked - reversion not proven (half-life %.1f bars, DF t %.2f, limit %.1f bars / -%.2f)",
                     g_halfLife, g_hlTStat, InpMaxHalfLifeBars, InpHLTStatMin);
      return;
     }
   if(g_useMO && InpUseTrendFilter && g_trendBias != g_dir)
     {
      if(InpVerbose) Print("QE: blocked - trend filter disagrees with momentum signal");
      return;
     }

   //--- price geometry from ATR
   double slDist = InpSL_ATR_Mult * g_atr;
   double minDist = MinStopDistancePrice();
   if(slDist < minDist) slDist = minDist;
   if(slDist <= 0.0) return;

   RefreshRates();
   double entry = (g_dir > 0) ? AskPrice() : BidPrice();
   if(entry <= 0.0) return;

   double sl = (g_dir > 0) ? entry - slDist : entry + slDist;

   double tp = 0.0;
   if(InpExitMode == QE_EXIT_RMULT)
      tp = entry + g_dir * slDist * InpRR;
   else
     {
      double minTP = InpMinTP_R * slDist;
      if(g_dir > 0)
         tp = MathMax(g_zMean, entry + MathMax(minTP, minDist));
      else
         tp = MathMin(g_zMean, entry - MathMax(minTP, minDist));
     }
   //--- never leave a target inside the broker's stop distance
   if(tp > 0.0 && MathAbs(tp - entry) < minDist)
      tp = entry + g_dir * minDist;
   tp = NormalizeDouble(tp, g_digits);

   double lots = CalcLots(slDist);
   if(lots <= 0.0)
     {
      if(InpVerbose) Print("QE: blocked - calculated lot size is below the broker minimum");
      return;
     }

   string tag = (g_useMR ? "MR" : (g_useMO ? "MO" : "FB"));
   int    mode = (g_useMR ? -1 : (g_useMO ? 1 : 0));
   if(InpVerbose)
      PrintFormat("QE: signal %s s=%.3f z=%.2f vr=%.3f hl=%.1f atrPct=%.2f lots=%.2f",
                  tag, g_score, g_z, g_vr, g_halfLife, g_atrPct, lots);

   int ticket = OpenTrade(g_dir, lots, sl, tp, tag, mode);
   if(ticket > 0)
     {
      g_lastEntryTime = TimeCurrent();
      g_lastEntryBar  = iTime(g_symbol, g_period, 0);
      g_tradesToday++;
     }
  }

//==================================================================
//  13. CSV DECISION LOG
//==================================================================
void CsvLog(string evt, int dir, double lots, double price, double sl, double tp, string note)
  {
   if(!InpCsvLog) return;

   int h = FileOpen(InpCsvFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   if(FileTell(h) == 0)
      FileWrite(h, "time", "event", "symbol", "dir", "lots", "price", "sl", "tp",
                "score", "z", "vr", "halflife", "atrpct", "equity", "daily_pct", "note");
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), evt, g_symbol,
             IntegerToString(dir), DoubleToString(lots, 2), DoubleToString(price, g_digits),
             DoubleToString(sl, g_digits), DoubleToString(tp, g_digits),
             DoubleToString(g_score, 3), DoubleToString(g_z, 2), DoubleToString(g_vr, 3),
             DoubleToString(g_halfLife, 1), DoubleToString(g_atrPct, 2),
             DoubleToString(AccountEquity(), 2), DoubleToString(DailyLossPct(), 2), note);
   FileClose(h);
  }

//==================================================================
//  14. DASHBOARD
//==================================================================
string RegimeText()
  {
   if(g_regime < 0) return("mean-revert");
   if(g_regime > 0) return("trending");
   return("neutral");
  }

void UpdateDashboard()
  {
   if(!InpShowDashboard) return;
   if(TimeCurrent() == g_lastDashTime) return;
   if(TimeCurrent() - g_lastDashTime < InpDashRefreshSec && g_lastDashTime != 0) return;
   g_lastDashTime = TimeCurrent();

   string status = "OK";
   if(g_dailyHalted)        status = "HALTED: daily governor";
   if(g_totalHalted)        status = "HALTED: total-loss governor";
   if(g_targetLocked)       status = "LOCKED: profit target";
   if(g_weekendHalted)      status = "FLAT: weekend";
   if(!g_ready)             status = "WARMING UP";
   else if(!g_mathReady)    status = "NO DATA: " + g_blockReason;

   string mode = "neutral";
   if(g_useMR) mode = "mean-reversion";
   else if(g_useMO) mode = "momentum";
   else if(g_useFB) mode = "fibonacci";

   string dirTxt = (g_dir > 0 ? "LONG" : (g_dir < 0 ? "SHORT" : "flat"));

   string txt = "";
   StringConcatenate(txt, "QuantEdge  ", g_symbol, "  ", PeriodToStr(), "\n");
   StringConcatenate(txt, "magic ", g_magic, "   spread ", SpreadPoints(), " pts   bars ", Bars, "\n");
   StringConcatenate(txt, "score ", DoubleToString(g_score, 3), " (thr ", DoubleToString(InpEntryThreshold, 2),
                     ")  z ", DoubleToString(g_z, 2), "  mom ", DoubleToString(g_momRaw, 2), "\n");
   StringConcatenate(txt, "VR ", DoubleToString(g_vr, 3), " ", RegimeText(),
                     "   half-life ", (g_halfLife > 0 ? DoubleToString(g_halfLife, 1) + " bars" : "n/a"),
                     " (DF t ", DoubleToString(g_hlTStat, 2), ")\n");
   StringConcatenate(txt, "ATR ", DoubleToString(g_atr, g_digits), " (pct ",
                     DoubleToString(g_atrPct * 100.0, 0), "%)  fib ", DoubleToString(g_fibScore, 2), "\n");
   StringConcatenate(txt, "mode ", mode, "   signal ", dirTxt, "\n");
   StringConcatenate(txt, "equity ", DoubleToString(AccountEquity(), 2), "   risk/trade ",
                     DoubleToString(InpRiskPercent, 2), "%\n");
   StringConcatenate(txt, "day loss ", DoubleToString(DailyLossPct(), 2), "% / ",
                     DoubleToString(InpDailyRiskBudgetPct, 2), "%  (hard ",
                     DoubleToString(InpMaxDailyLossPct, 1), "%)\n");
   StringConcatenate(txt, "total DD ", DoubleToString(TotalLossPct(), 2), "% / ",
                     DoubleToString(InpTotalRiskBudgetPct, 2), "%  (hard ",
                     DoubleToString(InpMaxTotalLossPct, 1), "%)\n");
   StringConcatenate(txt, "profit ", DoubleToString(ProfitPct(), 2), "% / target ",
                     DoubleToString(InpProfitTargetPct, 1), "%\n");
   StringConcatenate(txt, "open ", CountEAPositions(0), "/", InpMaxOpenPositions,
                     "   open risk ", DoubleToString(OpenRiskPct(), 2), "%   trades today ",
                     g_tradesToday, "/", InpMaxTradesPerDay, "\n");
   StringConcatenate(txt, "status: ", status);

   string name = "QE_DASH_" + IntegerToString(g_magic);
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpDashCorner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpDashX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpDashY);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpDashFontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, InpDashColor);
   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
  }

string PeriodToStr()
  {
   string s = "";
   switch(g_period)
     {
      case PERIOD_M1:  s = "M1"; break;
      case PERIOD_M5:  s = "M5"; break;
      case PERIOD_M15: s = "M15"; break;
      case PERIOD_M30: s = "M30"; break;
      case PERIOD_H1:  s = "H1"; break;
      case PERIOD_H4:  s = "H4"; break;
      case PERIOD_D1:  s = "D1"; break;
      case PERIOD_W1:  s = "W1"; break;
      default:         s = IntegerToString(g_period); break;
     }
   return(s);
  }

//==================================================================
//  15. INPUT SELF-TEST (runtime invariants)
//==================================================================
bool SelfTest()
  {
   bool ok = true;

   if(SpreadPoints() < 0)
     { Print("QE SELFTEST FAIL: negative spread"); ok = false; }
   if(g_atr < 0.0)
     { Print("QE SELFTEST FAIL: negative ATR"); ok = false; }
   if(g_atrPct < 0.0 || g_atrPct > 1.0)
     { Print("QE SELFTEST FAIL: ATR percentile outside [0,1]"); ok = false; }
   if(g_score < -1.0 || g_score > 1.0)
     { Print("QE SELFTEST FAIL: score outside [-1,1]"); ok = false; }
   if(g_vr < 0.0)
     { Print("QE SELFTEST FAIL: negative variance ratio"); ok = false; }
   if(g_halfLife > 0.0 && g_halfLife > 100000.0)
     { Print("QE SELFTEST FAIL: implausible half-life"); ok = false; }

   //--- lot normalisation must respect the broker step
   double probe = NormalizeLot(g_minLot + g_lotStep * 3.7);
   double steps = probe / g_lotStep;
   if(MathAbs(steps - MathRound(steps)) > 0.001 && probe > 0.0)
     { Print("QE SELFTEST FAIL: lot normalisation not on the broker step"); ok = false; }

   //--- price normalisation
   double p = NormalizeDouble(1.23456789, g_digits);
   if(g_digits >= 0 && MathAbs(p - 1.23456789) > MathPow(10.0, -g_digits) * 1.0001)
     { Print("QE SELFTEST FAIL: price normalisation"); ok = false; }

   if(ok && InpVerbose) Print("QE SELFTEST: all invariants hold");
   return(ok);
  }

//==================================================================
//  16. EVENT HANDLERS
//==================================================================
int OnInit()
  {
   if(!InitMarket()) return(INIT_PARAMETERS_INCORRECT);
   if(!ValidateInputs()) return(INIT_PARAMETERS_INCORRECT);

   g_neededBars = ComputeNeededBars();
   if(Bars < g_neededBars)
      PrintFormat("QE: %d bars available, %d needed - the engine will warm up on its own",
                  Bars, g_neededBars);

   EnsureInitialBalance();
   RefreshDayAnchor();
   TrackClear();
   g_ready = true;

   //--- spread baseline from recent bars: used by the automatic spread cap
   int    samples = 0;
   double sum = 0.0;
   for(int i = 1; i <= 200; i++)
     {
      double s = (double)iSpread(g_symbol, g_period, i);
      if(s > 0) { sum += s; samples++; }
     }
   if(samples > 0) g_spreadMedian = (int)MathRound(sum / samples);
   if(g_spreadMedian <= 0) g_spreadMedian = (int)MathMax(1, MarketInfo(g_symbol, MODE_SPREAD));
   if(g_spreadMedian <= 0) g_spreadMedian = 20;

   if(InpNewsFilter) LoadNews();

   PrintFormat("QE: initialised on %s %s | magic %d | strategy %d | risk %.2f%% | daily halt %.2f%% | total halt %.2f%% | phase balance %.2f",
               g_symbol, PeriodToStr(), g_magic, (int)InpStrategy, InpRiskPercent,
               InpDailyRiskBudgetPct, InpTotalRiskBudgetPct, g_initialBalance);

   if(InpSelfTest)
     {
      UpdateSignalEngine();
      if(!SelfTest())
         Print("QE: self-test warnings above - review the configuration before going live");
     }

   UpdateDashboard();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(InpShowDashboard)
      ObjectDelete(0, "QE_DASH_" + IntegerToString(g_magic));
   PrintFormat("QE: stopped (reason %d) | equity %.2f | daily %.2f%% | total DD %.2f%%",
               reason, AccountEquity(), DailyLossPct(), TotalLossPct());
  }

void OnTick()
  {
   if(!g_ready) return;

   datetime now = TimeCurrent();

   //--- detect a session re-open (weekend / holiday gap) without trading it
   if(g_lastTickTime > 0 && (now - g_lastTickTime) > 3600)
     {
      g_sessionOpenTime = now;
      if(InpVerbose) Print("QE: market re-opened after a gap - blackout ",
                           InpReopenBlackoutMin, " minutes");
     }
   g_lastTickTime = now;

   //--- 1. compliance first: nothing below may run if a limit is hit
   UpdateGovernors();

   //--- 2. manage what is already open
   ManagePositions();

   //--- 3. decision engine once per closed bar
   if(IsNewBar())
     {
      UpdateSignalEngine();
      TryEntry();
     }

   //--- 4. housekeeping
   if(now - g_lastNewsLoad > 3600 && InpNewsFilter)
      LoadNews();

   UpdateDashboard();
  }
