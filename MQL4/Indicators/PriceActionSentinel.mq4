//+------------------------------------------------------------------+
//|                                         PriceActionSentinel.mq4  |
//|                  Full-chart price action analyzer for MetaTrader 4|
//|  Swing structure * S/R floors/ceilings * Auto trendlines & breaks|
//|  Candlestick patterns * Confluence entries * Bias & risk map     |
//+------------------------------------------------------------------+
#property copyright "Price Action Sentinel"
#property link      "https://github.com/ismailchaacha97-ui/kkk"
#property version   "1.10"
#property strict
#property description "Whole-chart price action: S/R, structure (HH/HL/LH/LL),"
#property description "auto trendlines + breaks, candlesticks, EMA 50 / 13-21 confluence."
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_color1  clrLime
#property indicator_color2  clrTomato
#property indicator_width1  2
#property indicator_width2  2

//--- visible signal arrows + EMA plots (EA-readable via iCustom)
#property indicator_label1  "LongSetup"
#property indicator_label2  "ShortSetup"
#property indicator_label3  "NearestSupport"
#property indicator_label4  "NearestResistance"
#property indicator_label5  "TrendBias"
#property indicator_label6  "PatternCode"
#property indicator_label7  "EMA50"
#property indicator_label8  "EMA13"
#property indicator_label9  "EMA21"

#define PAS_PREFIX     "PAS_"
#define PAS_MAX_SWING  256
#define PAS_MAX_SR     48
#define PAS_MAX_TL     8
#define PAS_MAX_PAT    96
#define PAS_MAX_SETUP  32

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_TREND_BIAS
  {
   BIAS_RANGE = 0,
   BIAS_BULL  = 1,
   BIAS_BEAR  =-1
  };

enum ENUM_SWING_KIND
  {
   SWING_NONE = 0,
   SWING_HH   = 1,
   SWING_HL   = 2,
   SWING_LH   = 3,
   SWING_LL   = 4,
   SWING_EH   = 5,
   SWING_EL   = 6
  };

enum ENUM_DASH_CORNER
  {
   DASH_LEFT_TOP    = 0,
   DASH_RIGHT_TOP   = 1,
   DASH_LEFT_BOTTOM = 2,
   DASH_RIGHT_BOTTOM= 3
  };

//+------------------------------------------------------------------+
//| Inputs - Swing / structure                                        |
//+------------------------------------------------------------------+
input string              InpSecStructure   = "======== STRUCTURE ========"; // .
input int                 InpLookback       = 800;     // Bars to scan (whole-chart depth)
input int                 InpSwingStrength  = 5;       // Swing pivot strength (bars each side)
input bool                InpShowSwings     = true;    // Mark swing highs / lows
input bool                InpShowStructure  = true;    // Label HH / HL / LH / LL / EQ
input bool                InpShowBosChoch   = true;    // Mark BOS and CHoCH
input int                 InpEqualPips      = 3;       // Equal H/L tolerance (pips)

//+------------------------------------------------------------------+
//| Inputs - Support & resistance                                     |
//+------------------------------------------------------------------+
input string              InpSecSR          = "======== SUPPORT / RESISTANCE ========"; // .
input bool                InpShowSR         = true;    // Draw S/R floors & ceilings
input int                 InpMaxSR          = 10;      // Max S/R zones to draw
input double              InpSRClusterATR   = 0.35;    // Cluster width (x ATR)
input int                 InpMinTouches     = 2;       // Minimum historical touches
input bool                InpShowPDH        = true;    // Previous day / week / month H-L
input bool                InpShowRound      = true;    // Psychological round numbers
input bool                InpShowZones      = true;    // Draw zones (off = thin lines)

//+------------------------------------------------------------------+
//| Inputs - Trendlines                                               |
//+------------------------------------------------------------------+
input string              InpSecTL          = "======== TRENDLINES ========"; // .
input bool                InpShowTL         = true;    // Auto trendlines
input int                 InpTLTouches      = 2;       // Minimum touches to keep a line
input double              InpTLTouchATR     = 0.28;    // Touch / break buffer (x ATR)
input bool                InpShowTLBreaks   = true;    // Mark trendline breaks
input bool                InpShowRetest     = true;    // Mark break retests
input bool                InpRayRight       = true;    // Extend rays to the right

//+------------------------------------------------------------------+
//| Inputs - Candles & setups                                         |
//+------------------------------------------------------------------+
input string              InpSecCandle      = "======== CANDLES / SETUPS ========"; // .
input bool                InpShowPatterns   = true;    // Label candlestick patterns
input int                 InpPatternBars    = 60;      // How many recent bars to label
input bool                InpShowSetups     = true;    // Confluence long / short setups
input int                 InpMinSetupScore  = 5;       // Minimum confluence score (3-12)
input bool                InpShowRR         = true;    // Project SL / TP box on last setup
input double              InpRR             = 2.0;     // Reward : risk for TP box

//+------------------------------------------------------------------+
//| Inputs - Dashboard / alerts                                       |
//+------------------------------------------------------------------+
input string              InpSecUI          = "======== DISPLAY / ALERTS ========"; // .
input bool                InpShowDash       = true;    // Analysis dashboard
input ENUM_DASH_CORNER    InpDashCorner     = DASH_LEFT_TOP; // Dashboard corner
input bool                InpAlertBreaks    = true;    // Alert on TL / structure breaks
input bool                InpAlertSetups    = true;    // Alert on confluence setups
input bool                InpAlertPopup     = true;    // Popup alert
input bool                InpAlertSound     = true;    // Sound alert
input bool                InpAlertPush      = false;   // Push notification
input string              InpSoundFile      = "alert.wav"; // Sound file

//+------------------------------------------------------------------+
//| Inputs - Colors                                                   |
//+------------------------------------------------------------------+
input string              InpSecColor       = "======== COLORS ========"; // .
input color               InpColSupport     = C'38,166,154';   // Support
input color               InpColResist      = C'239,83,80';    // Resistance
input color               InpColBull        = C'0,200,118';    // Bullish structure
input color               InpColBear        = C'255,82,82';    // Bearish structure
input color               InpColEqual       = C'255,202,40';   // Equal H/L (liquidity)
input color               InpColTL          = C'66,165,245';   // Active trendline
input color               InpColTLBroken    = C'120,130,145';  // Broken trendline
input color               InpColBreak       = C'255,213,79';   // Break marker
input color               InpColText        = C'226,232,240';  // Dashboard text
input color               InpColMuted       = C'148,163,184';  // Dashboard muted
input color               InpColDash        = C'15,23,42';     // Dashboard background
input color               InpColBorder      = C'51,65,85';     // Dashboard border
input color               InpColEMA50       = C'255,193,7';    // 50 EMA
input color               InpColEMA13       = C'0,229,255';    // 13 EMA
input color               InpColEMA21       = C'186,104,200';  // 21 EMA

//+------------------------------------------------------------------+
//| Types                                                             |
//+------------------------------------------------------------------+
struct SwingPoint
  {
   int      bar;
   datetime time;
   double   price;
   bool     isHigh;
   int      kind;       // ENUM_SWING_KIND
  };

struct SRLevel
  {
   double   price;
   double   top;
   double   bot;
   int      touches;
   int      score;
   datetime lastTouch;
   bool     broken;
  };

struct AutoTL
  {
   datetime t1;
   datetime t2;
   double   p1;
   double   p2;
   int      bar1;
   int      bar2;
   bool     isSupport;
   int      touches;
   bool     broken;
   datetime breakTime;
   double   breakPrice;
   int      breakBar;
   bool     retested;
   datetime retestTime;
   double   retestPrice;
   bool     valid;
  };

struct CandlePat
  {
   int      bar;
   datetime time;
   int      dir;        // +1 bull, -1 bear, 0 indecision
   int      quality;    // 1-5
   int      code;
   string   name;
   bool     valid;
  };

struct Setup
  {
   int      bar;
   datetime time;
   int      dir;        // +1 long, -1 short
   int      score;
   double   entry;
   double   sl;
   double   tp;
   string   reason;
   bool     valid;
  };

//+------------------------------------------------------------------+
//| Buffers & state                                                   |
//+------------------------------------------------------------------+
double BufLong[];
double BufShort[];
double BufSup[];
double BufRes[];
double BufTrend[];
double BufPat[];
double BufEMA50[];
double BufEMA13[];
double BufEMA21[];

SwingPoint g_swings[];
int        g_swingCount = 0;

SRLevel    g_sr[];
int        g_srCount = 0;

AutoTL     g_tl[];
int        g_tlCount = 0;

CandlePat  g_pats[];
int        g_patCount = 0;

Setup      g_setups[];
int        g_setupCount = 0;

ENUM_TREND_BIAS g_bias      = BIAS_RANGE;
string          g_biasName  = "RANGE";
string          g_structTxt = "-";
string          g_regime    = "CONSOLIDATION";
double          g_atr       = 0.0;
double          g_nearSup   = 0.0;
double          g_nearRes   = 0.0;
string          g_lastPat   = "None";
string          g_lastSetup = "Waiting";
int             g_lastBosDir= 0;
string          g_lastBos   = "None";
string          g_emaTxt    = "off";
int             g_emaBias   = 0;      // +1 bull stack, -1 bear stack, 0 mixed

datetime g_lastAlertBar   = 0;
datetime g_lastBarTime    = 0;
bool     g_ready          = false;

//+------------------------------------------------------------------+
//| Lifecycle                                                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufLong);
   SetIndexBuffer(1, BufShort);
   SetIndexBuffer(2, BufSup);
   SetIndexBuffer(3, BufRes);
   SetIndexBuffer(4, BufTrend);
   SetIndexBuffer(5, BufPat);
   SetIndexBuffer(6, BufEMA50);
   SetIndexBuffer(7, BufEMA13);
   SetIndexBuffer(8, BufEMA21);

   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 2, InpColBull);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 2, InpColBear);
   SetIndexStyle(2, DRAW_NONE);
   SetIndexStyle(3, DRAW_NONE);
   SetIndexStyle(4, DRAW_NONE);
   SetIndexStyle(5, DRAW_NONE);
   SetIndexStyle(6, (InpShowEMA50 ? DRAW_LINE : DRAW_NONE), STYLE_SOLID, 2, InpColEMA50);
   SetIndexStyle(7, (InpShowEMA1321 ? DRAW_LINE : DRAW_NONE), STYLE_SOLID, 1, InpColEMA13);
   SetIndexStyle(8, (InpShowEMA1321 ? DRAW_LINE : DRAW_NONE), STYLE_DASH, 1, InpColEMA21);

   SetIndexArrow(0, 233);
   SetIndexArrow(1, 234);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(2, EMPTY_VALUE);
   SetIndexEmptyValue(3, EMPTY_VALUE);
   SetIndexEmptyValue(4, EMPTY_VALUE);
   SetIndexEmptyValue(5, EMPTY_VALUE);
   SetIndexEmptyValue(6, EMPTY_VALUE);
   SetIndexEmptyValue(7, EMPTY_VALUE);
   SetIndexEmptyValue(8, EMPTY_VALUE);

   SetIndexLabel(0, "LongSetup");
   SetIndexLabel(1, "ShortSetup");
   SetIndexLabel(2, "NearestSupport");
   SetIndexLabel(3, "NearestResistance");
   SetIndexLabel(4, "TrendBias");
   SetIndexLabel(5, "PatternCode");
   SetIndexLabel(6, "EMA" + IntegerToString(EmaPeriod50()));
   SetIndexLabel(7, "EMA" + IntegerToString(EmaPeriodFast()));
   SetIndexLabel(8, "EMA" + IntegerToString(EmaPeriodSlow()));

   IndicatorShortName("Price Action Sentinel");
   IndicatorDigits(Digits);

   ArrayResize(g_swings, PAS_MAX_SWING);
   ArrayResize(g_sr,     PAS_MAX_SR);
   ArrayResize(g_tl,     PAS_MAX_TL);
   ArrayResize(g_pats,   PAS_MAX_PAT);
   ArrayResize(g_setups, PAS_MAX_SETUP);

   WipeObjects();
   g_ready = true;
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   WipeObjects();
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
   if(!g_ready || rates_total < InpSwingStrength * 4 + 20)
      return(0);

   ArraySetAsSeries(BufLong,  true);
   ArraySetAsSeries(BufShort, true);
   ArraySetAsSeries(BufSup,   true);
   ArraySetAsSeries(BufRes,   true);
   ArraySetAsSeries(BufTrend, true);
   ArraySetAsSeries(BufPat,   true);

   bool newBar = (Time[0] != g_lastBarTime);
   if(prev_calculated == 0)
      newBar = true;

   if(newBar)
     {
      g_lastBarTime = Time[0];
      FullScan(rates_total);
      WipeObjects();
      DrawAll();
     }
   else
     {
      UpdateLiveBar();
      if(InpShowDash)
         DrawDashboard();
     }

   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Full chart scan                                                   |
//+------------------------------------------------------------------+
void FullScan(const int rates_total)
  {
   int lookback = InpLookback;
   if(lookback < 100)
      lookback = 100;
   if(lookback > rates_total - 2)
      lookback = rates_total - 2;

   g_atr = iATR(NULL, 0, 14, 1);
   if(g_atr <= 0.0)
      g_atr = (High[1] - Low[1]);
   if(g_atr <= 0.0)
      g_atr = Point * 10;

   CollectSwings(lookback);
   ClassifyStructure();
   DetectBosChoch();
   BuildSR(lookback);
   BuildTrendlines(lookback);
   DetectPatterns(lookback);
   RefreshEmaState(1);
   ScoreSetups();
   FillBuffers(lookback);
  }

//+------------------------------------------------------------------+
//| Swing collection                                                  |
//+------------------------------------------------------------------+
void CollectSwings(const int lookback)
  {
   g_swingCount = 0;
   int strength = InpSwingStrength;
   if(strength < 2)
      strength = 2;

   // Confirmed pivots only: need `strength` bars to the right (newer).
   for(int i = lookback; i >= strength; i--)
     {
      bool sh = IsSwingHigh(i, strength);
      bool sl = IsSwingLow(i, strength);
      if(sh)
         PushSwing(i, Time[i], High[i], true);
      if(sl)
         PushSwing(i, Time[i], Low[i], false);
     }
  }

bool IsSwingHigh(const int i, const int strength)
  {
   double h = High[i];
   for(int k = 1; k <= strength; k++)
     {
      if(High[i + k] >= h)
         return(false);
      if(i - k >= 0 && High[i - k] > h)
         return(false);
     }
   return(true);
  }

bool IsSwingLow(const int i, const int strength)
  {
   double l = Low[i];
   for(int k = 1; k <= strength; k++)
     {
      if(Low[i + k] <= l)
         return(false);
      if(i - k >= 0 && Low[i - k] < l)
         return(false);
     }
   return(true);
  }

void PushSwing(const int bar, const datetime t, const double price, const bool isHigh)
  {
   if(g_swingCount >= PAS_MAX_SWING)
      return;
   g_swings[g_swingCount].bar    = bar;
   g_swings[g_swingCount].time   = t;
   g_swings[g_swingCount].price  = price;
   g_swings[g_swingCount].isHigh = isHigh;
   g_swings[g_swingCount].kind   = SWING_NONE;
   g_swingCount++;
  }

//+------------------------------------------------------------------+
//| Market structure: HH / HL / LH / LL / equal highs-lows            |
//+------------------------------------------------------------------+
void ClassifyStructure()
  {
   g_bias      = BIAS_RANGE;
   g_biasName  = "RANGE";
   g_structTxt = "No clear structure";
   g_regime    = "CONSOLIDATION";

   double lastHigh = 0.0;
   double lastLow  = 0.0;
   bool   haveH    = false;
   bool   haveL    = false;
   double eqTol    = PipSize() * InpEqualPips;

   for(int i = 0; i < g_swingCount; i++)
     {
      if(g_swings[i].isHigh)
        {
         if(haveH)
           {
            if(g_swings[i].price > lastHigh + eqTol)
               g_swings[i].kind = SWING_HH;
            else if(g_swings[i].price < lastHigh - eqTol)
               g_swings[i].kind = SWING_LH;
            else
               g_swings[i].kind = SWING_EH;
           }
         lastHigh = g_swings[i].price;
         haveH = true;
        }
      else
        {
         if(haveL)
           {
            if(g_swings[i].price > lastLow + eqTol)
               g_swings[i].kind = SWING_HL;
            else if(g_swings[i].price < lastLow - eqTol)
               g_swings[i].kind = SWING_LL;
            else
               g_swings[i].kind = SWING_EL;
           }
         lastLow = g_swings[i].price;
         haveL = true;
        }
     }

   // Bias from the most recent two classified highs and two lows.
   int lastH1 = -1, lastH2 = -1, lastL1 = -1, lastL2 = -1;
   for(int j = g_swingCount - 1; j >= 0; j--)
     {
      if(g_swings[j].isHigh)
        {
         if(lastH1 < 0) lastH1 = j;
         else if(lastH2 < 0) lastH2 = j;
        }
      else
        {
         if(lastL1 < 0) lastL1 = j;
         else if(lastL2 < 0) lastL2 = j;
        }
      if(lastH1 >= 0 && lastH2 >= 0 && lastL1 >= 0 && lastL2 >= 0)
         break;
     }

   bool risingH  = (lastH1 >= 0 && lastH2 >= 0 && g_swings[lastH1].price > g_swings[lastH2].price + eqTol);
   bool fallingH = (lastH1 >= 0 && lastH2 >= 0 && g_swings[lastH1].price < g_swings[lastH2].price - eqTol);
   bool risingL  = (lastL1 >= 0 && lastL2 >= 0 && g_swings[lastL1].price > g_swings[lastL2].price + eqTol);
   bool fallingL = (lastL1 >= 0 && lastL2 >= 0 && g_swings[lastL1].price < g_swings[lastL2].price - eqTol);

   if(risingH && risingL)
     {
      g_bias     = BIAS_BULL;
      g_biasName = "BULLISH";
      g_regime   = "UPTREND";
      g_structTxt= "HH + HL  (buyers in control)";
     }
   else if(fallingH && fallingL)
     {
      g_bias     = BIAS_BEAR;
      g_biasName = "BEARISH";
      g_regime   = "DOWNTREND";
      g_structTxt= "LH + LL  (sellers in control)";
     }
   else if(risingL && !fallingH)
     {
      g_bias     = BIAS_BULL;
      g_biasName = "BULLISH";
      g_regime   = "UPTREND (soft)";
      g_structTxt= "Higher lows, mixed highs";
     }
   else if(fallingH && !risingL)
     {
      g_bias     = BIAS_BEAR;
      g_biasName = "BEARISH";
      g_regime   = "DOWNTREND (soft)";
      g_structTxt= "Lower highs, mixed lows";
     }
   else
     {
      g_bias     = BIAS_RANGE;
      g_biasName = "RANGE";
      g_regime   = "CONSOLIDATION";
      g_structTxt= "Sideways - wait for breakout";
     }
  }

//+------------------------------------------------------------------+
//| Break of Structure / Change of Character                          |
//+------------------------------------------------------------------+
void DetectBosChoch()
  {
   g_lastBosDir = 0;
   g_lastBos    = "None";
   if(g_swingCount < 4)
      return;

   int sh = LastSwingIndex(true, 0);
   int sl = LastSwingIndex(false, 0);
   if(sh < 0 || sl < 0)
      return;

   double lastHigh = g_swings[sh].price;
   double lastLow  = g_swings[sl].price;
   int    startBar = MathMin(g_swings[sh].bar, g_swings[sl].bar);
   if(startBar < 2)
      return;

   // Newest closed bar first so the dashboard shows the latest event.
   for(int i = 1; i < startBar; i++)
     {
      if(g_bias == BIAS_BULL && Close[i] < lastLow)
        {
         g_lastBosDir = -1;
         g_lastBos    = "CHoCH v bearish";
         return;
        }
      if(g_bias == BIAS_BULL && Close[i] > lastHigh)
        {
         g_lastBosDir = 1;
         g_lastBos    = "BOS ^ bullish";
         return;
        }
      if(g_bias == BIAS_BEAR && Close[i] > lastHigh)
        {
         g_lastBosDir = 1;
         g_lastBos    = "CHoCH ^ bullish";
         return;
        }
      if(g_bias == BIAS_BEAR && Close[i] < lastLow)
        {
         g_lastBosDir = -1;
         g_lastBos    = "BOS v bearish";
         return;
        }
      if(g_bias == BIAS_RANGE && Close[i] > lastHigh)
        {
         g_lastBosDir = 1;
         g_lastBos    = "BOS ^ bullish";
         return;
        }
      if(g_bias == BIAS_RANGE && Close[i] < lastLow)
        {
         g_lastBosDir = -1;
         g_lastBos    = "BOS v bearish";
         return;
        }
     }
  }

int LastSwingIndex(const bool isHigh, const int skip)
  {
   int seen = 0;
   for(int i = g_swingCount - 1; i >= 0; i--)
     {
      if(g_swings[i].isHigh == isHigh)
        {
         if(seen == skip)
            return(i);
         seen++;
        }
     }
   return(-1);
  }

//+------------------------------------------------------------------+
//| Support & resistance - floors and ceilings                        |
//+------------------------------------------------------------------+
void BuildSR(const int lookback)
  {
   g_srCount = 0;
   g_nearSup = 0.0;
   g_nearRes = 0.0;

   double cluster = g_atr * InpSRClusterATR;
   if(cluster <= 0.0)
      cluster = PipSize() * 5.0;

   // Seed clusters from swing prices.
   for(int i = 0; i < g_swingCount; i++)
     {
      int idx = FindCluster(g_swings[i].price, cluster);
      if(idx < 0)
        {
         if(g_srCount >= PAS_MAX_SR)
            continue;
         idx = g_srCount;
         g_sr[idx].price     = g_swings[i].price;
         g_sr[idx].top       = g_swings[i].price;
         g_sr[idx].bot       = g_swings[i].price;
         g_sr[idx].touches   = 0;
         g_sr[idx].score     = 0;
         g_sr[idx].lastTouch = g_swings[i].time;
         g_sr[idx].broken    = false;
         g_srCount++;
        }
      else
        {
         // Running average keeps the zone centered on traffic.
         g_sr[idx].price = (g_sr[idx].price * g_sr[idx].touches + g_swings[i].price) /
                           (g_sr[idx].touches + 1.0);
         if(g_swings[i].price > g_sr[idx].top) g_sr[idx].top = g_swings[i].price;
         if(g_swings[i].price < g_sr[idx].bot) g_sr[idx].bot = g_swings[i].price;
         if(g_swings[i].time > g_sr[idx].lastTouch)
            g_sr[idx].lastTouch = g_swings[i].time;
        }
      g_sr[idx].touches++;
     }

   // Count extra wick touches that were not swing pivots.
   for(int s = 0; s < g_srCount; s++)
     {
      double mid = g_sr[s].price;
      int extra = 0;
      datetime last = g_sr[s].lastTouch;
      for(int i = 1; i <= lookback; i += 2)
        {
         if(High[i] >= mid - cluster && Low[i] <= mid + cluster)
           {
            extra++;
            if(Time[i] > last)
               last = Time[i];
           }
        }
      g_sr[s].touches  += extra / 3;          // de-noise
      g_sr[s].lastTouch = last;

      // Widen a touch into a tradable zone.
      double half = MathMax(cluster * 0.6, (g_sr[s].top - g_sr[s].bot) * 0.5);
      g_sr[s].top = mid + half;
      g_sr[s].bot = mid - half;

      // Score: touches + recency + proximity to price.
      int recency = 0;
      int ageBars = iBarShift(NULL, 0, g_sr[s].lastTouch);
      if(ageBars < 50)       recency = 4;
      else if(ageBars < 150) recency = 3;
      else if(ageBars < 400) recency = 2;
      else                   recency = 1;

      double dist = MathAbs(Close[0] - mid) / g_atr;
      int prox = (dist < 1.5 ? 3 : (dist < 4.0 ? 2 : 1));

      g_sr[s].score = g_sr[s].touches * 2 + recency + prox;

      // A close through the zone marks it broken (still drawn, lower weight).
      if((Close[1] > g_sr[s].top && Open[1] < g_sr[s].bot) ||
         (Close[1] < g_sr[s].bot && Open[1] > g_sr[s].top))
         g_sr[s].broken = true;
     }

   // Inject previous period H/L - classic institutional SNR.
   if(InpShowPDH)
     {
      AddFixedSR(iHigh(NULL, PERIOD_D1, 1),  iLow(NULL, PERIOD_D1, 1),  6);
      AddFixedSR(iHigh(NULL, PERIOD_W1, 1),  iLow(NULL, PERIOD_W1, 1),  7);
      AddFixedSR(iHigh(NULL, PERIOD_MN1, 1), iLow(NULL, PERIOD_MN1, 1), 8);
     }

   if(InpShowRound)
      AddRoundLevels();

   SortSRByScore();

   // Nearest living floor / ceiling relative to last close.
   double px = Close[0];
   double bestSupDist = 1.0e10;
   double bestResDist = 1.0e10;
   for(int k = 0; k < g_srCount; k++)
     {
      if(g_sr[k].price < px)
        {
         double d = px - g_sr[k].price;
         if(d < bestSupDist)
           { bestSupDist = d; g_nearSup = g_sr[k].price; }
        }
      else if(g_sr[k].price > px)
        {
         double d = g_sr[k].price - px;
         if(d < bestResDist)
           { bestResDist = d; g_nearRes = g_sr[k].price; }
        }
     }
  }

int FindCluster(const double price, const double width)
  {
   int best = -1;
   double bestDist = width;
   for(int i = 0; i < g_srCount; i++)
     {
      double d = MathAbs(g_sr[i].price - price);
      if(d <= bestDist)
        {
         bestDist = d;
         best = i;
        }
     }
   return(best);
  }

void AddFixedSR(const double hi, const double lo, const int baseScore)
  {
   if(hi > 0.0)
      PushRawSR(hi, baseScore);
   if(lo > 0.0 && MathAbs(hi - lo) > g_atr * 0.15)
      PushRawSR(lo, baseScore);
  }

void PushRawSR(const double price, const int score)
  {
   if(price <= 0.0)
      return;
   int idx = FindCluster(price, g_atr * InpSRClusterATR);
   if(idx >= 0)
     {
      g_sr[idx].score += score;
      g_sr[idx].touches++;
      return;
     }
   if(g_srCount >= PAS_MAX_SR)
      return;
   double half = g_atr * InpSRClusterATR * 0.5;
   g_sr[g_srCount].price     = price;
   g_sr[g_srCount].top       = price + half;
   g_sr[g_srCount].bot       = price - half;
   g_sr[g_srCount].touches   = 2;
   g_sr[g_srCount].score     = score + 2;
   g_sr[g_srCount].lastTouch = Time[1];
   g_sr[g_srCount].broken    = false;
   g_srCount++;
  }

void AddRoundLevels()
  {
   double step = RoundStep();
   if(step <= 0.0)
      return;
   double px = Close[0];
   double base = MathFloor(px / step) * step;
   for(int k = -3; k <= 4; k++)
      PushRawSR(base + k * step, 4);
  }

double RoundStep()
  {
   int d = Digits;
   if(d == 5 || d == 3)
      return(1000 * Point);          // 100 pips on 5/3-digit FX
   if(d == 4 || d == 2)
     {
      if(Bid > 20.0)
         return(10.0);               // gold / indices
      return(100 * Point);           // 100 pips on 4-digit FX / JPY
     }
   if(Bid > 100.0)
      return(50.0);
   return(100 * Point);
  }

void SortSRByScore()
  {
   for(int i = 0; i < g_srCount; i++)
     {
      int best = i;
      for(int j = i + 1; j < g_srCount; j++)
         if(g_sr[j].score > g_sr[best].score)
            best = j;
      if(best != i)
        {
         SRLevel tmp = g_sr[i];
         g_sr[i] = g_sr[best];
         g_sr[best] = tmp;
        }
     }
  }

//+------------------------------------------------------------------+
//| Automatic trendlines from swing pairs                             |
//+------------------------------------------------------------------+
void BuildTrendlines(const int lookback)
  {
   g_tlCount = 0;
   if(!InpShowTL)
      return;

   FindBestTL(true,  lookback);   // rising / falling support (swing lows)
   FindBestTL(false, lookback);   // falling / rising resistance (swing highs)

   // Secondary structure line: last two swings of each type.
   AddStructureLine(true);
   AddStructureLine(false);

   for(int i = 0; i < g_tlCount; i++)
      EvaluateBreaks(g_tl[i]);
  }

void FindBestTL(const bool useLows, const int lookback)
  {
   int idx[];
   int n = 0;
   ArrayResize(idx, g_swingCount);
   for(int i = 0; i < g_swingCount; i++)
     {
      if(g_swings[i].isHigh == !useLows)
        {
         idx[n] = i;
         n++;
        }
     }
   if(n < 2)
      return;

   int    bestA = -1, bestB = -1, bestScore = -9999;
   int    minTouches = InpTLTouches;
   double buf = g_atr * InpTLTouchATR;

   // Recent pairs first - search a bounded window so we stay real-time.
   int start = MathMax(0, n - 14);
   for(int a = start; a < n - 1; a++)
     {
      for(int b = a + 1; b < n; b++)
        {
         int ia = idx[a];
         int ib = idx[b];
         if(g_swings[ia].bar <= g_swings[ib].bar)
            continue; // ia must be older (higher index)

         int score = ScoreCandidate(g_swings[ia], g_swings[ib], useLows, buf, lookback);
         if(score > bestScore)
           {
            bestScore = score;
            bestA = ia;
            bestB = ib;
           }
        }
     }

   if(bestA < 0 || bestScore < minTouches * 8)
      return;

   AutoTL tl;
   ZeroTL(tl);
   tl.t1        = g_swings[bestA].time;
   tl.t2        = g_swings[bestB].time;
   tl.p1        = g_swings[bestA].price;
   tl.p2        = g_swings[bestB].price;
   tl.bar1      = g_swings[bestA].bar;
   tl.bar2      = g_swings[bestB].bar;
   tl.isSupport = useLows;
   tl.touches   = bestScore / 10;
   if(tl.touches < 2)
      tl.touches = 2;
   tl.valid     = true;
   PushTL(tl);
  }

int ScoreCandidate(const SwingPoint &a, const SwingPoint &b,
                   const bool isSupport, const double buf, const int lookback)
  {
   if(a.bar == b.bar)
      return(-9999);

   int touches = 2;
   int viol    = 0;
   int from    = a.bar;
   int to      = 1;
   if(from > lookback)
      from = lookback;

   for(int i = from - 1; i >= to; i--)
     {
      if(i == a.bar || i == b.bar)
         continue;
      double lp = LinePriceAtBar(a.bar, a.price, b.bar, b.price, i);
      if(lp <= 0.0)
         continue;

      if(isSupport)
        {
         if(MathAbs(Low[i] - lp) <= buf)
            touches++;
         if(Close[i] < lp - buf)
            viol++;
        }
      else
        {
         if(MathAbs(High[i] - lp) <= buf)
            touches++;
         if(Close[i] > lp + buf)
            viol++;
        }
     }

   // Recency bonus - we care about the working edge of the chart.
   int recency = 40 - b.bar;
   if(recency < 0)
      recency = 0;

   // Prefer lines that are not flat noise and not absurdly steep.
   double slope = MathAbs(b.price - a.price) / MathMax(1, a.bar - b.bar);
   int slopePts = 0;
   if(slope > g_atr * 0.02 && slope < g_atr * 0.80)
      slopePts = 8;

   return(touches * 10 - viol * 18 + recency + slopePts);
  }

void AddStructureLine(const bool useLows)
  {
   int a = LastSwingIndex(useLows ? false : true, 1);
   int b = LastSwingIndex(useLows ? false : true, 0);
   if(a < 0 || b < 0)
      return;

   // Skip if it duplicates an existing auto line.
   for(int i = 0; i < g_tlCount; i++)
     {
      if(g_tl[i].bar1 == g_swings[a].bar && g_tl[i].bar2 == g_swings[b].bar)
         return;
     }

   AutoTL tl;
   ZeroTL(tl);
   tl.t1        = g_swings[a].time;
   tl.t2        = g_swings[b].time;
   tl.p1        = g_swings[a].price;
   tl.p2        = g_swings[b].price;
   tl.bar1      = g_swings[a].bar;
   tl.bar2      = g_swings[b].bar;
   tl.isSupport = useLows;
   tl.touches   = 2;
   tl.valid     = true;
   PushTL(tl);
  }

void EvaluateBreaks(AutoTL &tl)
  {
   double buf = g_atr * InpTLTouchATR;
   for(int i = tl.bar2 - 1; i >= 1; i--)
     {
      double lp = LinePriceAtBar(tl.bar1, tl.p1, tl.bar2, tl.p2, i);
      if(lp <= 0.0)
         continue;

      bool brk = false;
      if(tl.isSupport && Close[i] < lp - buf)
         brk = true;
      if(!tl.isSupport && Close[i] > lp + buf)
         brk = true;

      if(brk)
        {
         tl.broken     = true;
         tl.breakBar   = i;
         tl.breakTime  = Time[i];
         tl.breakPrice = lp;
         // Hunt a retest after the break.
         if(InpShowRetest)
           {
            int horizon = i - 25;
            if(horizon < 1) horizon = 1;
            for(int r = i - 1; r >= horizon; r--)
              {
               double lp2 = LinePriceAtBar(tl.bar1, tl.p1, tl.bar2, tl.p2, r);
               if(MathAbs(Close[r] - lp2) <= buf * 1.4)
                 {
                  // Rejection in the break direction.
                  if(tl.isSupport && Close[r] < Open[r]) // was support, now resist
                    {
                     tl.retested    = true;
                     tl.retestTime  = Time[r];
                     tl.retestPrice = lp2;
                     break;
                    }
                  if(!tl.isSupport && Close[r] > Open[r])
                    {
                     tl.retested    = true;
                     tl.retestTime  = Time[r];
                     tl.retestPrice = lp2;
                     break;
                    }
                 }
              }
           }
         return;
        }
     }
  }

void ZeroTL(AutoTL &tl)
  {
   tl.t1 = 0; tl.t2 = 0;
   tl.p1 = 0; tl.p2 = 0;
   tl.bar1 = 0; tl.bar2 = 0;
   tl.isSupport = false;
   tl.touches = 0;
   tl.broken = false;
   tl.breakTime = 0;
   tl.breakPrice = 0;
   tl.breakBar = 0;
   tl.retested = false;
   tl.retestTime = 0;
   tl.retestPrice = 0;
   tl.valid = false;
  }

void PushTL(const AutoTL &tl)
  {
   if(g_tlCount >= PAS_MAX_TL)
      return;
   g_tl[g_tlCount] = tl;
   g_tlCount++;
  }

double LinePriceAtBar(const int b1, const double p1, const int b2, const double p2, const int bar)
  {
   double den = (double)(b2 - b1);
   if(MathAbs(den) < 0.5)
      return(p1);
   // Series indexes: larger bar = older. Extrapolate linearly in bar space.
   return(p1 + (p2 - p1) * ((double)(bar - b1) / den));
  }

//+------------------------------------------------------------------+
//| Candlestick pattern recognition                                   |
//+------------------------------------------------------------------+
void DetectPatterns(const int lookback)
  {
   g_patCount = 0;
   g_lastPat  = "None";
   if(!InpShowPatterns && !InpShowSetups)
      return;

   int depth = InpPatternBars;
   if(depth < 10) depth = 10;
   if(depth > lookback - 5) depth = lookback - 5;

   for(int i = depth; i >= 1; i--)
     {
      CandlePat p;
      p.valid = false;
      p.bar = i;
      p.time = Time[i];
      p.dir = 0;
      p.quality = 0;
      p.code = 0;
      p.name = "";

      if(PatFakey(i, p))            {}
      else if(PatMorningEvening(i, p)) {}
      else if(PatEngulf(i, p))      {}
      else if(PatHarami(i, p))      {}
      else if(PatPiercingDark(i, p)){}
      else if(PatPin(i, p))         {}
      else if(PatInside(i, p))      {}
      else if(PatOutside(i, p))     {}
      else if(PatSoldiersCrows(i, p)){}
      else if(PatTweezers(i, p))    {}
      else if(PatMarubozu(i, p))    {}
      else if(PatDoji(i, p))        {}

      if(p.valid)
         PushPat(p);
     }

   if(g_patCount > 0)
      g_lastPat = g_pats[g_patCount - 1].name;
  }

bool Body(const int i, double &body, double &range, double &upper, double &lower, bool &bull)
  {
   range = High[i] - Low[i];
   if(range <= Point)
      return(false);
   body  = MathAbs(Close[i] - Open[i]);
   bull  = (Close[i] >= Open[i]);
   double topBody = MathMax(Open[i], Close[i]);
   double botBody = MathMin(Open[i], Close[i]);
   upper = High[i] - topBody;
   lower = botBody - Low[i];
   return(true);
  }

bool PatDoji(const int i, CandlePat &p)
  {
   double body, range, up, lo;
   bool bull;
   if(!Body(i, body, range, up, lo, bull))
      return(false);
   if(body / range > 0.12)
      return(false);
   p.valid = true;
   p.dir = 0;
   p.quality = 2;
   p.code = 1;
   p.name = "Doji";
   if(up > range * 0.55 && lo < range * 0.18)
     { p.name = "Gravestone Doji"; p.dir = -1; p.quality = 3; }
   else if(lo > range * 0.55 && up < range * 0.18)
     { p.name = "Dragonfly Doji"; p.dir = 1; p.quality = 3; }
   return(true);
  }

bool PatPin(const int i, CandlePat &p)
  {
   double body, range, up, lo;
   bool bull;
   if(!Body(i, body, range, up, lo, bull))
      return(false);
   if(range < g_atr * 0.45)
      return(false);

   // Classic pin bar: wick >= 2/3 of the candle, tiny opposite wick.
   if(lo >= range * 0.62 && up <= range * 0.18 && body / range <= 0.35)
     {
      p.valid = true;
      p.dir = 1;
      p.quality = (lo >= range * 0.72 ? 5 : 4);
      p.code = 10;
      p.name = "Bull Pin / Hammer";
      return(true);
     }
   if(up >= range * 0.62 && lo <= range * 0.18 && body / range <= 0.35)
     {
      p.valid = true;
      p.dir = -1;
      p.quality = (up >= range * 0.72 ? 5 : 4);
      p.code = 11;
      p.name = "Bear Pin / Star";
      return(true);
     }
   return(false);
  }

bool PatEngulf(const int i, CandlePat &p)
  {
   double b1, r1, u1, l1, b0, r0, u0, l0;
   bool bull1, bull0;
   if(!Body(i, b0, r0, u0, l0, bull0))
      return(false);
   if(!Body(i + 1, b1, r1, u1, l1, bull1))
      return(false);
   if(b0 < g_atr * 0.25)
      return(false);

   double max0 = MathMax(Open[i], Close[i]);
   double min0 = MathMin(Open[i], Close[i]);
   double max1 = MathMax(Open[i+1], Close[i+1]);
   double min1 = MathMin(Open[i+1], Close[i+1]);

   if(bull0 && !bull1 && min0 <= min1 && max0 >= max1 && b0 > b1)
     {
      p.valid = true;
      p.dir = 1;
      p.quality = 4;
      p.code = 20;
      p.name = "Bull Engulfing";
      return(true);
     }
   if(!bull0 && bull1 && min0 <= min1 && max0 >= max1 && b0 > b1)
     {
      p.valid = true;
      p.dir = -1;
      p.quality = 4;
      p.code = 21;
      p.name = "Bear Engulfing";
      return(true);
     }
   return(false);
  }

bool PatHarami(const int i, CandlePat &p)
  {
   double max0 = MathMax(Open[i], Close[i]);
   double min0 = MathMin(Open[i], Close[i]);
   double max1 = MathMax(Open[i+1], Close[i+1]);
   double min1 = MathMin(Open[i+1], Close[i+1]);
   double b1 = MathAbs(Close[i+1] - Open[i+1]);
   double b0 = MathAbs(Close[i] - Open[i]);
   if(b1 < g_atr * 0.35 || b0 < Point)
      return(false);
   if(!(min0 > min1 && max0 < max1))
      return(false);
   bool motherBull = Close[i+1] >= Open[i+1];
   bool childBull  = Close[i]   >= Open[i];
   if(motherBull && !childBull)
     {
      p.valid = true; p.dir = -1; p.quality = 3; p.code = 22; p.name = "Bear Harami";
      return(true);
     }
   if(!motherBull && childBull)
     {
      p.valid = true; p.dir = 1; p.quality = 3; p.code = 23; p.name = "Bull Harami";
      return(true);
     }
   return(false);
  }

bool PatInside(const int i, CandlePat &p)
  {
   if(High[i] < High[i+1] && Low[i] > Low[i+1])
     {
      p.valid = true;
      p.dir = 0;
      p.quality = 3;
      p.code = 30;
      p.name = "Inside Bar";
      return(true);
     }
   return(false);
  }

bool PatOutside(const int i, CandlePat &p)
  {
   if(High[i] > High[i+1] && Low[i] < Low[i+1] && MathAbs(Close[i]-Open[i]) > g_atr * 0.3)
     {
      p.valid = true;
      p.dir = (Close[i] >= Open[i] ? 1 : -1);
      p.quality = 3;
      p.code = 31;
      p.name = (p.dir > 0 ? "Bull Outside Bar" : "Bear Outside Bar");
      return(true);
     }
   return(false);
  }

bool PatPiercingDark(const int i, CandlePat &p)
  {
   double mid1 = (Open[i+1] + Close[i+1]) * 0.5;
   // Piercing line
   if(Close[i+1] < Open[i+1] && Close[i] > Open[i] &&
      Open[i] < Low[i+1] && Close[i] > mid1 && Close[i] < Open[i+1])
     {
      p.valid = true; p.dir = 1; p.quality = 4; p.code = 24; p.name = "Piercing Line";
      return(true);
     }
   // Dark cloud cover
   if(Close[i+1] > Open[i+1] && Close[i] < Open[i] &&
      Open[i] > High[i+1] && Close[i] < mid1 && Close[i] > Open[i+1])
     {
      p.valid = true; p.dir = -1; p.quality = 4; p.code = 25; p.name = "Dark Cloud";
      return(true);
     }
   return(false);
  }

bool PatMorningEvening(const int i, CandlePat &p)
  {
   double b2 = MathAbs(Close[i+2] - Open[i+2]);
   double b1 = MathAbs(Close[i+1] - Open[i+1]);
   double b0 = MathAbs(Close[i]   - Open[i]);
   double mid2 = (Open[i+2] + Close[i+2]) * 0.5;

   // Morning star: long bear, small indecision, long bull closing into first body.
   if(Close[i+2] < Open[i+2] && b2 > g_atr * 0.4 &&
      b1 < b2 * 0.45 &&
      Close[i] > Open[i] && b0 > g_atr * 0.35 && Close[i] > mid2)
     {
      p.valid = true; p.dir = 1; p.quality = 5; p.code = 40; p.name = "Morning Star";
      return(true);
     }
   if(Close[i+2] > Open[i+2] && b2 > g_atr * 0.4 &&
      b1 < b2 * 0.45 &&
      Close[i] < Open[i] && b0 > g_atr * 0.35 && Close[i] < mid2)
     {
      p.valid = true; p.dir = -1; p.quality = 5; p.code = 41; p.name = "Evening Star";
      return(true);
     }
   return(false);
  }

bool PatSoldiersCrows(const int i, CandlePat &p)
  {
   bool s1 = Close[i]   > Open[i]   && Close[i]   > Close[i+1];
   bool s2 = Close[i+1] > Open[i+1] && Close[i+1] > Close[i+2];
   bool s3 = Close[i+2] > Open[i+2];
   if(s1 && s2 && s3 &&
      MathAbs(Close[i]-Open[i]) > g_atr * 0.25 &&
      MathAbs(Close[i+1]-Open[i+1]) > g_atr * 0.25)
     {
      p.valid = true; p.dir = 1; p.quality = 4; p.code = 42; p.name = "3 White Soldiers";
      return(true);
     }
   bool c1 = Close[i]   < Open[i]   && Close[i]   < Close[i+1];
   bool c2 = Close[i+1] < Open[i+1] && Close[i+1] < Close[i+2];
   bool c3 = Close[i+2] < Open[i+2];
   if(c1 && c2 && c3 &&
      MathAbs(Close[i]-Open[i]) > g_atr * 0.25 &&
      MathAbs(Close[i+1]-Open[i+1]) > g_atr * 0.25)
     {
      p.valid = true; p.dir = -1; p.quality = 4; p.code = 43; p.name = "3 Black Crows";
      return(true);
     }
   return(false);
  }

bool PatTweezers(const int i, CandlePat &p)
  {
   double tol = g_atr * 0.12;
   if(MathAbs(High[i] - High[i+1]) <= tol &&
      Close[i] < Open[i] && Close[i+1] > Open[i+1] &&
      High[i] - MathMax(Open[i], Close[i]) > g_atr * 0.15)
     {
      p.valid = true; p.dir = -1; p.quality = 3; p.code = 50; p.name = "Tweezer Top";
      return(true);
     }
   if(MathAbs(Low[i] - Low[i+1]) <= tol &&
      Close[i] > Open[i] && Close[i+1] < Open[i+1] &&
      MathMin(Open[i], Close[i]) - Low[i] > g_atr * 0.15)
     {
      p.valid = true; p.dir = 1; p.quality = 3; p.code = 51; p.name = "Tweezer Bottom";
      return(true);
     }
   return(false);
  }

bool PatMarubozu(const int i, CandlePat &p)
  {
   double body, range, up, lo;
   bool bull;
   if(!Body(i, body, range, up, lo, bull))
      return(false);
   if(range < g_atr * 0.6)
      return(false);
   if(body / range < 0.88)
      return(false);
   p.valid = true;
   p.dir = (bull ? 1 : -1);
   p.quality = 3;
   p.code = (bull ? 60 : 61);
   p.name = (bull ? "Bull Marubozu" : "Bear Marubozu");
   return(true);
  }

bool PatFakey(const int i, CandlePat &p)
  {
   // Williams / Price Action: inside bar false breakout that closes back inside.
   if(!(High[i+1] < High[i+2] && Low[i+1] > Low[i+2]))
      return(false);
   bool brokeHigh = High[i] > High[i+1];
   bool brokeLow  = Low[i]  < Low[i+1];
   if(brokeHigh && !brokeLow && Close[i] < High[i+1] && Close[i] < Open[i])
     {
      p.valid = true; p.dir = -1; p.quality = 5; p.code = 70; p.name = "Fakey Short";
      return(true);
     }
   if(brokeLow && !brokeHigh && Close[i] > Low[i+1] && Close[i] > Open[i])
     {
      p.valid = true; p.dir = 1; p.quality = 5; p.code = 71; p.name = "Fakey Long";
      return(true);
     }
   return(false);
  }

void PushPat(const CandlePat &p)
  {
   if(g_patCount >= PAS_MAX_PAT)
     {
      // Drop the oldest to keep the newest.
      for(int i = 1; i < PAS_MAX_PAT; i++)
         g_pats[i-1] = g_pats[i];
      g_patCount = PAS_MAX_PAT - 1;
     }
   g_pats[g_patCount] = p;
   g_patCount++;
  }

//+------------------------------------------------------------------+
//| EMA helpers - 50 trend filter + 13/21 ribbon                      |
//+------------------------------------------------------------------+
int EmaPeriod50()
  {
   return(InpEMA50Period < 2 ? 50 : InpEMA50Period);
  }

int EmaPeriodFast()
  {
   return(InpEMAFast < 2 ? 13 : InpEMAFast);
  }

int EmaPeriodSlow()
  {
   int slow = (InpEMASlow < 2 ? 21 : InpEMASlow);
   if(slow <= EmaPeriodFast())
      slow = EmaPeriodFast() + 8;
   return(slow);
  }

double EmaAt(const int period, const int bar)
  {
   return(iMA(NULL, 0, period, 0, MODE_EMA, PRICE_CLOSE, bar));
  }

bool EmaEnabled()
  {
   return(InpUseEMA50 || InpUseEMA1321);
  }

void RefreshEmaState(const int bar)
  {
   g_emaTxt  = "off";
   g_emaBias = 0;
   if(!EmaEnabled())
      return;

   double e50 = EmaAt(EmaPeriod50(), bar);
   double e13 = EmaAt(EmaPeriodFast(), bar);
   double e21 = EmaAt(EmaPeriodSlow(), bar);
   double px  = Close[bar];

   int stack = 0;
   string txt = "";

   if(InpUseEMA1321 && InpUseEMA50)
     {
      if(e13 > e21 && e21 > e50 && px > e50)
        { stack = 1; txt = IntegerToString(EmaPeriodFast()) + ">" +
                           IntegerToString(EmaPeriodSlow()) + ">" +
                           IntegerToString(EmaPeriod50()) + "  BULL"; }
      else if(e13 < e21 && e21 < e50 && px < e50)
        { stack = -1; txt = IntegerToString(EmaPeriodFast()) + "<" +
                            IntegerToString(EmaPeriodSlow()) + "<" +
                            IntegerToString(EmaPeriod50()) + "  BEAR"; }
      else
         txt = "mixed stack";
     }
   else if(InpUseEMA1321)
     {
      if(e13 > e21)
        { stack = 1; txt = IntegerToString(EmaPeriodFast()) + ">" +
                           IntegerToString(EmaPeriodSlow()) + "  BULL"; }
      else if(e13 < e21)
        { stack = -1; txt = IntegerToString(EmaPeriodFast()) + "<" +
                            IntegerToString(EmaPeriodSlow()) + "  BEAR"; }
      else
         txt = "13/21 flat";
     }
   else if(InpUseEMA50)
     {
      if(px > e50)
        { stack = 1; txt = "above EMA" + IntegerToString(EmaPeriod50()); }
      else if(px < e50)
        { stack = -1; txt = "below EMA" + IntegerToString(EmaPeriod50()); }
      else
         txt = "on EMA" + IntegerToString(EmaPeriod50());
     }

   g_emaBias = stack;
   g_emaTxt  = txt;
  }

bool TouchedEma(const int bar, const double ema)
  {
   double buf = g_atr * InpEMATouchATR;
   if(buf <= 0.0)
      buf = g_atr * 0.35;
   return(Low[bar] <= ema + buf && High[bar] >= ema - buf);
  }

bool InRibbon(const int bar, const double fast, const double slow)
  {
   double lo = MathMin(fast, slow);
   double hi = MathMax(fast, slow);
   double pad = g_atr * InpEMATouchATR;
   return(Low[bar] <= hi + pad && High[bar] >= lo - pad);
  }

int ApplyEmaScore(const int bar, const int dir, string &why)
  {
   if(!EmaEnabled() || dir == 0)
      return(0);

   int add = 0;
   double e50 = EmaAt(EmaPeriod50(), bar);
   double e13 = EmaAt(EmaPeriodFast(), bar);
   double e21 = EmaAt(EmaPeriodSlow(), bar);

   if(InpUseEMA50)
     {
      bool above = (Close[bar] > e50);
      if((dir > 0 && above) || (dir < 0 && !above))
        { add += 2; why += "EMA50 "; }
      else
        { add -= 1; why += "against-EMA50 "; }

      if(TouchedEma(bar, e50))
        {
         if(dir > 0 && Close[bar] > e50 && Low[bar] <= e50 + g_atr * InpEMATouchATR)
           { add += 2; why += "EMA50-bounce "; }
         if(dir < 0 && Close[bar] < e50 && High[bar] >= e50 - g_atr * InpEMATouchATR)
           { add += 2; why += "EMA50-reject "; }
        }
     }

   if(InpUseEMA1321)
     {
      bool bullRibbon = (e13 > e21);
      if((dir > 0 && bullRibbon) || (dir < 0 && !bullRibbon))
        { add += 2; why += "13/21 "; }
      else
        { add -= 1; why += "against-13/21 "; }

      if(InRibbon(bar, e13, e21))
        {
         if(dir > 0 && Close[bar] >= MathMin(e13, e21))
           { add += 2; why += "ribbon-hold "; }
         if(dir < 0 && Close[bar] <= MathMax(e13, e21))
           { add += 2; why += "ribbon-reject "; }
        }

      // Fresh cross on this bar in the trade direction.
      double p13 = EmaAt(EmaPeriodFast(), bar + 1);
      double p21 = EmaAt(EmaPeriodSlow(), bar + 1);
      if(dir > 0 && e13 > e21 && p13 <= p21)
        { add += 1; why += "13/21-cross "; }
      if(dir < 0 && e13 < e21 && p13 >= p21)
        { add += 1; why += "13/21-cross "; }
     }

   if(InpUseEMA50 && InpUseEMA1321)
     {
      if(dir > 0 && e13 > e21 && e21 > e50 && Close[bar] > e50)
        { add += 1; why += "stack "; }
      if(dir < 0 && e13 < e21 && e21 < e50 && Close[bar] < e50)
        { add += 1; why += "stack "; }
     }

   return(add);
  }

//+------------------------------------------------------------------+
//| Confluence setups - how a discretionary PA trader times entries   |
//+------------------------------------------------------------------+
void ScoreSetups()
  {
   g_setupCount = 0;
   g_lastSetup  = "Waiting for confluence";
   if(!InpShowSetups)
      return;

   int depth = MathMin(InpPatternBars, 40);
   for(int i = depth; i >= 1; i--)
     {
      Setup s;
      s.valid = false;
      s.bar = i;
      s.time = Time[i];
      s.dir = 0;
      s.score = 0;
      s.entry = Close[i];
      s.sl = 0;
      s.tp = 0;
      s.reason = "";

      CandlePat pat;
      pat.valid = false;
      pat.dir = 0;
      pat.quality = 0;
      pat.name = "";
      for(int p = 0; p < g_patCount; p++)
         if(g_pats[p].bar == i)
           { pat = g_pats[p]; break; }

      bool atSup = false, atRes = false, atTLSup = false, atTLRes = false;
      NearLocation(i, atSup, atRes, atTLSup, atTLRes);

      bool ema50BounceUp = false, ema50BounceDn = false;
      bool ribbonHoldUp  = false, ribbonHoldDn  = false;
      if(InpUseEMA50)
        {
         double e50 = EmaAt(EmaPeriod50(), i);
         if(TouchedEma(i, e50) && Close[i] > Open[i] && Close[i] > e50)
            ema50BounceUp = true;
         if(TouchedEma(i, e50) && Close[i] < Open[i] && Close[i] < e50)
            ema50BounceDn = true;
        }
      if(InpUseEMA1321)
        {
         double e13 = EmaAt(EmaPeriodFast(), i);
         double e21 = EmaAt(EmaPeriodSlow(), i);
         if(InRibbon(i, e13, e21) && Close[i] > Open[i] && e13 >= e21)
            ribbonHoldUp = true;
         if(InRibbon(i, e13, e21) && Close[i] < Open[i] && e13 <= e21)
            ribbonHoldDn = true;
        }

      int dir = 0;
      if(pat.valid && pat.dir != 0)
         dir = pat.dir;
      else if(atSup && Close[i] > Open[i])
         dir = 1;
      else if(atRes && Close[i] < Open[i])
         dir = -1;
      else if(ema50BounceUp || ribbonHoldUp)
         dir = 1;
      else if(ema50BounceDn || ribbonHoldDn)
         dir = -1;

      if(dir == 0)
         continue;

      int score = 0;
      string why = "";

      // 1. Trade with the structure, not against it.
      if((dir > 0 && g_bias == BIAS_BULL) || (dir < 0 && g_bias == BIAS_BEAR))
        { score += 2; why += "with-trend "; }
      else if(g_bias == BIAS_RANGE)
        { score += 0; why += "range "; }
      else
        { score -= 1; why += "counter "; }

      // 2. Floor / ceiling reaction.
      if(dir > 0 && atSup)
        { score += 3; why += "support-bounce "; }
      if(dir < 0 && atRes)
        { score += 3; why += "resist-reject "; }

      // 3. Trendline bounce or retest after a break.
      if(dir > 0 && atTLSup)
        { score += 2; why += "TL-hold "; }
      if(dir < 0 && atTLRes)
        { score += 2; why += "TL-reject "; }

      bool retestLong = false, retestShort = false;
      for(int t = 0; t < g_tlCount; t++)
        {
         if(g_tl[t].retested && g_tl[t].retestTime == Time[i])
           {
            if(g_tl[t].isSupport) retestShort = true;  // broken support -> resist
            else                  retestLong  = true;  // broken resist  -> support
           }
        }
      if(dir > 0 && retestLong)
        { score += 3; why += "TL-retest "; }
      if(dir < 0 && retestShort)
        { score += 3; why += "TL-retest "; }

      // 4. Candlestick trigger.
      if(pat.valid)
        {
         score += MathMax(1, pat.quality / 2 + 1);
         why += pat.name + " ";
        }

      // 5. Structure event nearby.
      if((dir > 0 && g_lastBosDir > 0) || (dir < 0 && g_lastBosDir < 0))
        { score += 1; why += g_lastBos + " "; }

      // 6. EMA 50 filter / bounce and optional 13/21 ribbon.
      score += ApplyEmaScore(i, dir, why);

      if(score < InpMinSetupScore)
         continue;

      s.valid  = true;
      s.dir    = dir;
      s.score  = score;
      s.reason = why;
      s.entry  = Close[i];

      // Risk: stop beyond the signal candle (classic PA) with a small ATR pad.
      double pad = g_atr * 0.15;
      if(dir > 0)
        {
         s.sl = Low[i] - pad;
         if(atSup && g_nearSup > 0.0 && g_nearSup < s.entry)
            s.sl = MathMin(s.sl, g_nearSup - pad);
         s.tp = s.entry + (s.entry - s.sl) * InpRR;
         if(g_nearRes > s.entry)
            s.tp = MathMin(s.tp, g_nearRes - pad);
        }
      else
        {
         s.sl = High[i] + pad;
         if(atRes && g_nearRes > 0.0 && g_nearRes > s.entry)
            s.sl = MathMax(s.sl, g_nearRes + pad);
         s.tp = s.entry - (s.sl - s.entry) * InpRR;
         if(g_nearSup > 0.0 && g_nearSup < s.entry)
            s.tp = MathMax(s.tp, g_nearSup + pad);
        }

      PushSetup(s);
     }

   if(g_setupCount > 0)
     {
      Setup last = g_setups[g_setupCount - 1];
      g_lastSetup = (last.dir > 0 ? "LONG  " : "SHORT ") +
                    IntegerToString(last.score) + "pts  " + last.reason;
      MaybeAlert(last);
     }
  }

void NearLocation(const int bar, bool &atSup, bool &atRes, bool &atTLSup, bool &atTLRes)
  {
   atSup = false; atRes = false; atTLSup = false; atTLRes = false;
   double buf = g_atr * 0.45;

   for(int s = 0; s < g_srCount && s < InpMaxSR + 6; s++)
     {
      if(Low[bar]  <= g_sr[s].top && Low[bar]  >= g_sr[s].bot - buf)
         atSup = true;
      if(High[bar] >= g_sr[s].bot && High[bar] <= g_sr[s].top + buf)
         atRes = true;
      // Also treat mid-touch.
      if(MathAbs(Low[bar]  - g_sr[s].price) <= buf) atSup = true;
      if(MathAbs(High[bar] - g_sr[s].price) <= buf) atRes = true;
     }

   for(int t = 0; t < g_tlCount; t++)
     {
      if(!g_tl[t].valid)
         continue;
      double lp = LinePriceAtBar(g_tl[t].bar1, g_tl[t].p1, g_tl[t].bar2, g_tl[t].p2, bar);
      if(g_tl[t].isSupport && !g_tl[t].broken && MathAbs(Low[bar] - lp) <= buf)
         atTLSup = true;
      if(!g_tl[t].isSupport && !g_tl[t].broken && MathAbs(High[bar] - lp) <= buf)
         atTLRes = true;
      if(g_tl[t].broken && MathAbs(((Low[bar]+High[bar])*0.5) - lp) <= buf)
        {
         if(g_tl[t].isSupport) atTLRes = true;
         else                  atTLSup = true;
        }
     }
  }

void PushSetup(const Setup &s)
  {
   if(g_setupCount >= PAS_MAX_SETUP)
     {
      for(int i = 1; i < PAS_MAX_SETUP; i++)
         g_setups[i-1] = g_setups[i];
      g_setupCount = PAS_MAX_SETUP - 1;
     }
   g_setups[g_setupCount] = s;
   g_setupCount++;
  }

//+------------------------------------------------------------------+
//| Buffers for iCustom / data window                                 |
//+------------------------------------------------------------------+
void FillBuffers(const int lookback)
  {
   int bars = Bars;
   int n = MathMin(lookback + 2, bars);
   int p50 = EmaPeriod50();
   int p13 = EmaPeriodFast();
   int p21 = EmaPeriodSlow();
   bool draw50 = InpShowEMA50;
   bool drawRb = InpShowEMA1321;
   int emaBars = bars;
   if(emaBars > 5000)
      emaBars = 5000;
   if(emaBars < n)
      emaBars = n;

   for(int i = 0; i < emaBars; i++)
     {
      if(i < n)
        {
         BufLong[i]  = EMPTY_VALUE;
         BufShort[i] = EMPTY_VALUE;
         BufSup[i]   = (g_nearSup > 0.0 ? g_nearSup : EMPTY_VALUE);
         BufRes[i]   = (g_nearRes > 0.0 ? g_nearRes : EMPTY_VALUE);
         BufTrend[i] = (double)g_bias;
         BufPat[i]   = 0;
        }
      BufEMA50[i] = (draw50 ? EmaAt(p50, i) : EMPTY_VALUE);
      BufEMA13[i] = (drawRb ? EmaAt(p13, i) : EMPTY_VALUE);
      BufEMA21[i] = (drawRb ? EmaAt(p21, i) : EMPTY_VALUE);
     }

   for(int p = 0; p < g_patCount; p++)
     {
      int b = g_pats[p].bar;
      if(b >= 0 && b < n)
         BufPat[b] = (double)g_pats[p].code * (g_pats[p].dir == 0 ? 1 : g_pats[p].dir);
     }

   for(int s = 0; s < g_setupCount; s++)
     {
      int b = g_setups[s].bar;
      if(b < 0 || b >= n)
         continue;
      if(g_setups[s].dir > 0)
         BufLong[b] = Low[b] - g_atr * 0.25;
      else
         BufShort[b] = High[b] + g_atr * 0.25;
     }
  }

void UpdateLiveBar()
  {
   BufSup[0]   = (g_nearSup > 0.0 ? g_nearSup : EMPTY_VALUE);
   BufRes[0]   = (g_nearRes > 0.0 ? g_nearRes : EMPTY_VALUE);
   BufTrend[0] = (double)g_bias;
  }

//+------------------------------------------------------------------+
//| Drawing                                                           |
//+------------------------------------------------------------------+
void DrawAll()
  {
   if(InpShowSR)
      DrawSR();
   if(InpShowSwings || InpShowStructure)
      DrawSwings();
   if(InpShowTL)
      DrawTrendlines();
   if(InpShowPatterns)
      DrawPatterns();
   if(InpShowSetups)
      DrawSetups();
   if(InpShowBosChoch)
      DrawBosTag();
   if(InpShowDash)
      DrawDashboard();
   ChartRedraw(0);
  }

void DrawSR()
  {
   int drawn = 0;
   int cap = InpMaxSR;
   if(cap < 2) cap = 2;
   if(cap > 16) cap = 16;

   datetime tLeft  = Time[MathMin(Bars - 1, InpLookback)];
   datetime tRight = Time[0] + PasBarSeconds() * 12;

   for(int i = 0; i < g_srCount && drawn < cap; i++)
     {
      if(g_sr[i].touches < InpMinTouches && g_sr[i].score < 8)
         continue;

      bool isRes = (g_sr[i].price >= Close[0]);
      color col  = (isRes ? InpColResist : InpColSupport);
      int   alphaStyle = (g_sr[i].broken ? STYLE_DOT : STYLE_SOLID);
      string tag = PAS_PREFIX + "SR" + IntegerToString(i);
      string lab = (isRes ? "R " : "S ") +
                   DoubleToString(g_sr[i].price, Digits) +
                   "  x" + IntegerToString(g_sr[i].touches);

      if(InpShowZones)
        {
         ObjectCreate(0, tag, OBJ_RECTANGLE, 0, tLeft, g_sr[i].top, tRight, g_sr[i].bot);
         ObjectSetInteger(0, tag, OBJPROP_COLOR, col);
         ObjectSetInteger(0, tag, OBJPROP_STYLE, alphaStyle);
         ObjectSetInteger(0, tag, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, tag, OBJPROP_BACK, true);
         ObjectSetInteger(0, tag, OBJPROP_FILL, true);
         ObjectSetInteger(0, tag, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, tag, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, tag, OBJPROP_RAY_RIGHT, false);
        }
      else
        {
         ObjectCreate(0, tag, OBJ_HLINE, 0, 0, g_sr[i].price);
         ObjectSetInteger(0, tag, OBJPROP_COLOR, col);
         ObjectSetInteger(0, tag, OBJPROP_STYLE, alphaStyle);
         ObjectSetInteger(0, tag, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, tag, OBJPROP_BACK, true);
         ObjectSetInteger(0, tag, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, tag, OBJPROP_HIDDEN, true);
        }

      string tn = tag + "T";
      ObjectCreate(0, tn, OBJ_TEXT, 0, tRight, isRes ? g_sr[i].top : g_sr[i].bot);
      ObjectSetString(0, tn, OBJPROP_TEXT, lab);
      ObjectSetString(0, tn, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tn, OBJPROP_COLOR, col);
      ObjectSetInteger(0, tn, OBJPROP_ANCHOR, isRes ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
      drawn++;
     }
  }

void DrawSwings()
  {
   int start = MathMax(0, g_swingCount - 48);
   for(int i = start; i < g_swingCount; i++)
     {
      string nm = PAS_PREFIX + "SW" + IntegerToString(i);
      color  col = InpColMuted;
      int    arr = (g_swings[i].isHigh ? 242 : 241);
      switch(g_swings[i].kind)
        {
         case SWING_HH:
         case SWING_HL: col = InpColBull; break;
         case SWING_LH:
         case SWING_LL: col = InpColBear; break;
         case SWING_EH:
         case SWING_EL: col = InpColEqual; break;
        }

      if(InpShowSwings)
        {
         ObjectCreate(0, nm, OBJ_ARROW, 0, g_swings[i].time, g_swings[i].price);
         ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, arr);
         ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, nm, OBJPROP_ANCHOR,
                          g_swings[i].isHigh ? ANCHOR_BOTTOM : ANCHOR_TOP);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
        }

      if(InpShowStructure && g_swings[i].kind != SWING_NONE)
        {
         string lb = KindName(g_swings[i].kind);
         string tn = nm + "L";
         double off = g_atr * (g_swings[i].isHigh ? 0.25 : -0.25);
         ObjectCreate(0, tn, OBJ_TEXT, 0, g_swings[i].time, g_swings[i].price + off);
         ObjectSetString(0, tn, OBJPROP_TEXT, lb);
         ObjectSetString(0, tn, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, tn, OBJPROP_COLOR, col);
         ObjectSetInteger(0, tn, OBJPROP_ANCHOR,
                          g_swings[i].isHigh ? ANCHOR_LOWER : ANCHOR_UPPER);
         ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
        }
     }
  }

string KindName(const int kind)
  {
   switch(kind)
     {
      case SWING_HH: return("HH");
      case SWING_HL: return("HL");
      case SWING_LH: return("LH");
      case SWING_LL: return("LL");
      case SWING_EH: return("EQH");
      case SWING_EL: return("EQL");
     }
   return("");
  }

void DrawTrendlines()
  {
   for(int i = 0; i < g_tlCount; i++)
     {
      if(!g_tl[i].valid)
         continue;
      string nm = PAS_PREFIX + "TL" + IntegerToString(i);
      color  col = (g_tl[i].broken ? InpColTLBroken : InpColTL);
      int    st  = (g_tl[i].broken ? STYLE_DOT : STYLE_SOLID);

      ObjectCreate(0, nm, OBJ_TREND, 0, g_tl[i].t1, g_tl[i].p1, g_tl[i].t2, g_tl[i].p2);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, st);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, g_tl[i].broken ? 1 : 2);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, InpRayRight);
      ObjectSetInteger(0, nm, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);

      string side = (g_tl[i].isSupport ? "TL support" : "TL resist");
      if(g_tl[i].broken)
         side += "  BROKEN";
      string tn = nm + "L";
      ObjectCreate(0, tn, OBJ_TEXT, 0, g_tl[i].t2, g_tl[i].p2);
      ObjectSetString(0, tn, OBJPROP_TEXT, "  " + side + " x" + IntegerToString(g_tl[i].touches));
      ObjectSetString(0, tn, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, tn, OBJPROP_COLOR, col);
      ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);

      if(InpShowTLBreaks && g_tl[i].broken && g_tl[i].breakTime > 0)
        {
         string bn = nm + "B";
         ObjectCreate(0, bn, OBJ_ARROW, 0, g_tl[i].breakTime, g_tl[i].breakPrice);
         ObjectSetInteger(0, bn, OBJPROP_ARROWCODE, 181);
         ObjectSetInteger(0, bn, OBJPROP_COLOR, InpColBreak);
         ObjectSetInteger(0, bn, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, bn, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, bn, OBJPROP_HIDDEN, true);

         string bt = bn + "T";
         ObjectCreate(0, bt, OBJ_TEXT, 0, g_tl[i].breakTime, g_tl[i].breakPrice);
         ObjectSetString(0, bt, OBJPROP_TEXT, "  BREAK");
         ObjectSetString(0, bt, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, bt, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, bt, OBJPROP_COLOR, InpColBreak);
         ObjectSetInteger(0, bt, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, bt, OBJPROP_HIDDEN, true);

         if(InpAlertBreaks && g_tl[i].breakBar == 1)
            FireAlert("Trendline BREAK " + side + " @ " + DoubleToString(g_tl[i].breakPrice, Digits));
        }

      if(InpShowRetest && g_tl[i].retested && g_tl[i].retestTime > 0)
        {
         string rn = nm + "R";
         ObjectCreate(0, rn, OBJ_ARROW, 0, g_tl[i].retestTime, g_tl[i].retestPrice);
         ObjectSetInteger(0, rn, OBJPROP_ARROWCODE, 159);
         ObjectSetInteger(0, rn, OBJPROP_COLOR, InpColEqual);
         ObjectSetInteger(0, rn, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, rn, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, rn, OBJPROP_HIDDEN, true);

         string rt = rn + "T";
         ObjectCreate(0, rt, OBJ_TEXT, 0, g_tl[i].retestTime, g_tl[i].retestPrice);
         ObjectSetString(0, rt, OBJPROP_TEXT, "  RETEST");
         ObjectSetString(0, rt, OBJPROP_FONT, "Arial Bold");
         ObjectSetInteger(0, rt, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, rt, OBJPROP_COLOR, InpColEqual);
         ObjectSetInteger(0, rt, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, rt, OBJPROP_HIDDEN, true);
        }
     }
  }

void DrawPatterns()
  {
   int start = MathMax(0, g_patCount - InpPatternBars);
   for(int i = start; i < g_patCount; i++)
     {
      if(!g_pats[i].valid)
         continue;
      color col = InpColMuted;
      if(g_pats[i].dir > 0) col = InpColBull;
      if(g_pats[i].dir < 0) col = InpColBear;

      double y = (g_pats[i].dir >= 0 ? Low[g_pats[i].bar] - g_atr * 0.55
                                     : High[g_pats[i].bar] + g_atr * 0.55);
      string nm = PAS_PREFIX + "PAT" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_TEXT, 0, g_pats[i].time, y);
      ObjectSetString(0, nm, OBJPROP_TEXT, g_pats[i].name);
      ObjectSetString(0, nm, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
      ObjectSetInteger(0, nm, OBJPROP_ANCHOR,
                       g_pats[i].dir >= 0 ? ANCHOR_UPPER : ANCHOR_LOWER);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
     }
  }

void DrawSetups()
  {
   // Highlight the most recent setup with a risk box; arrows come from buffers.
   if(g_setupCount <= 0)
      return;
   Setup s = g_setups[g_setupCount - 1];
   if(!s.valid || s.bar > 30)
      return;

   if(InpShowRR && s.sl > 0.0 && s.tp > 0.0)
     {
      datetime t1 = s.time;
      datetime t2 = Time[0] + PasBarSeconds() * 6;
      color riskCol = C'239,83,80';
      color rewCol  = C'38,166,154';

      string r1 = PAS_PREFIX + "RR_RISK";
      ObjectCreate(0, r1, OBJ_RECTANGLE, 0, t1, s.entry, t2, s.sl);
      ObjectSetInteger(0, r1, OBJPROP_COLOR, riskCol);
      ObjectSetInteger(0, r1, OBJPROP_FILL, true);
      ObjectSetInteger(0, r1, OBJPROP_BACK, true);
      ObjectSetInteger(0, r1, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, r1, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, r1, OBJPROP_HIDDEN, true);

      string r2 = PAS_PREFIX + "RR_REW";
      ObjectCreate(0, r2, OBJ_RECTANGLE, 0, t1, s.entry, t2, s.tp);
      ObjectSetInteger(0, r2, OBJPROP_COLOR, rewCol);
      ObjectSetInteger(0, r2, OBJPROP_FILL, true);
      ObjectSetInteger(0, r2, OBJPROP_BACK, true);
      ObjectSetInteger(0, r2, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, r2, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, r2, OBJPROP_HIDDEN, true);

      string r3 = PAS_PREFIX + "RR_TXT";
      ObjectCreate(0, r3, OBJ_TEXT, 0, t2, s.tp);
      ObjectSetString(0, r3, OBJPROP_TEXT,
                      (s.dir > 0 ? "  LONG " : "  SHORT ") +
                      DoubleToString(InpRR, 1) + "R");
      ObjectSetString(0, r3, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, r3, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, r3, OBJPROP_COLOR, InpColText);
      ObjectSetInteger(0, r3, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, r3, OBJPROP_HIDDEN, true);
     }
  }

void DrawBosTag()
  {
   if(g_lastBosDir == 0)
      return;
   int sh = LastSwingIndex(true, 0);
   int sl = LastSwingIndex(false, 0);
   if(sh < 0 || sl < 0)
      return;
   int bar = MathMin(g_swings[sh].bar, g_swings[sl].bar);
   if(bar < 1)
      bar = 1;
   double px = (g_lastBosDir > 0 ? g_swings[sh].price : g_swings[sl].price);
   datetime t = Time[MathMax(1, bar - 1)];
   color col = (g_lastBosDir > 0 ? InpColBull : InpColBear);

   string nm = PAS_PREFIX + "BOS";
   ObjectCreate(0, nm, OBJ_TEXT, 0, t, px);
   ObjectSetString(0, nm, OBJPROP_TEXT, "  " + g_lastBos);
   ObjectSetString(0, nm, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| On-chart analysis dashboard                                       |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   int corner = CORNER_LEFT_UPPER;
   int x = 14;
   int y = 22;
   if(InpDashCorner == DASH_RIGHT_TOP)
     { corner = CORNER_RIGHT_UPPER; }
   else if(InpDashCorner == DASH_LEFT_BOTTOM)
     { corner = CORNER_LEFT_LOWER; }
   else if(InpDashCorner == DASH_RIGHT_BOTTOM)
     { corner = CORNER_RIGHT_LOWER; }

   int w = 268;
   int h = (EmaEnabled() ? 328 : 292);

   CreateRect("DASH_BG", x, y, w, h, corner, InpColDash, InpColBorder);
   CreateRect("DASH_HD", x, y, w, 28, corner, C'30,41,59', InpColBorder);

   color biasCol = InpColMuted;
   if(g_bias == BIAS_BULL) biasCol = InpColBull;
   if(g_bias == BIAS_BEAR) biasCol = InpColBear;

   int ly = y + 6;
   DashLabel("H1", "PRICE ACTION SENTINEL", x + 10, ly, corner, InpColText, 9, true);
   ly = y + 38;
   DashLabel("L1", "BIAS",     x + 10, ly, corner, InpColMuted, 8, false);
   DashLabel("V1", g_biasName, x + 88, ly, corner, biasCol, 10, true);
   ly += 18;
   DashLabel("L2", "REGIME",   x + 10, ly, corner, InpColMuted, 8, false);
   DashLabel("V2", g_regime,   x + 88, ly, corner, InpColText, 9, true);
   ly += 18;
   DashLabel("L3", "STRUCT",   x + 10, ly, corner, InpColMuted, 8, false);
   DashLabel("V3", g_structTxt,x + 88, ly, corner, InpColText, 8, false);
   ly += 20;
   DashLabel("L4", "EVENT",    x + 10, ly, corner, InpColMuted, 8, false);
   DashLabel("V4", g_lastBos,  x + 88, ly, corner, InpColEqual, 8, false);

   if(EmaEnabled())
     {
      color emaCol = InpColMuted;
      if(g_emaBias > 0) emaCol = InpColBull;
      if(g_emaBias < 0) emaCol = InpColBear;
      ly += 18;
      DashLabel("L4B", "EMA",   x + 10, ly, corner, InpColMuted, 8, false);
      DashLabel("V4B", g_emaTxt, x + 88, ly, corner, emaCol, 8, true);
     }

   ly += 22;
   CreateRect("DASH_DIV1", x + 10, ly, w - 20, 1, corner, InpColBorder, InpColBorder);
   ly += 10;

   DashLabel("L5", "CEILING",  x + 10, ly, corner, InpColResist, 8, false);
   DashLabel("V5", g_nearRes > 0.0 ? DoubleToString(g_nearRes, Digits) : "-",
             x + 88, ly, corner, InpColResist, 9, true);
   ly += 18;
   DashLabel("L6", "PRICE",    x + 10, ly, corner, InpColMuted, 8, false);
   DashLabel("V6", DoubleToString(Close[0], Digits), x + 88, ly, corner, InpColText, 9, true);
   ly += 18;
   DashLabel("L7", "FLOOR",    x + 10, ly, corner, InpColSupport, 8, false);
   DashLabel("V7", g_nearSup > 0.0 ? DoubleToString(g_nearSup, Digits) : "-",
             x + 88, ly, corner, InpColSupport, 9, true);

   ly += 22;
   CreateRect("DASH_DIV2", x + 10, ly, w - 20, 1, corner, InpColBorder, InpColBorder);
   ly += 10;

   DashLabel("L8", "CANDLE",   x + 10, ly, corner, InpColMuted, 8, false);
   DashLabel("V8", g_lastPat,  x + 88, ly, corner, InpColText, 8, false);
   ly += 18;
   DashLabel("L9", "SETUP",    x + 10, ly, corner, InpColMuted, 8, false);
   DashLabel("V9", StringSubstr(g_lastSetup, 0, 28), x + 88, ly, corner, InpColEqual, 8, false);

   ly += 22;
   string plan = "Wait - no edge";
   color  planCol = InpColMuted;
   if(g_bias == BIAS_BULL)
     {
      plan = "LONG: buy dips into the floor";
      planCol = InpColBull;
     }
   else if(g_bias == BIAS_BEAR)
     {
      plan = "SHORT: sell rallies into ceiling";
      planCol = InpColBear;
     }
   DashLabel("L10", "PLAN",    x + 10, ly, corner, InpColMuted, 8, false);
   DashLabel("V10", plan,      x + 88, ly, corner, planCol, 8, true);

   ly += 20;
   DashLabel("L11", Symbol() + "  " + TFName(Period()) + "  ATR " + DoubleToString(g_atr, Digits),
             x + 10, ly, corner, InpColMuted, 7, false);
  }

void CreateRect(const string id, const int x, const int y, const int w, const int h,
                const int corner, const color bg, const color bd)
  {
   string nm = PAS_PREFIX + id;
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, bd);
   ObjectSetInteger(0, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nm, OBJPROP_BACK, false);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 100);
  }

void DashLabel(const string id, const string text, const int x, const int y,
               const int corner, const color col, const int size, const bool bold)
  {
   string nm = PAS_PREFIX + "DL_" + id;
   if(ObjectFind(0, nm) < 0)
      ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  nm, OBJPROP_TEXT, text);
   ObjectSetString(0,  nm, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, nm, OBJPROP_ZORDER, 110);
  }

string TFName(const int tf)
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
      case PERIOD_MN1: return("MN");
     }
   return("TF" + IntegerToString(tf));
  }

//+------------------------------------------------------------------+
//| Alerts                                                            |
//+------------------------------------------------------------------+
void MaybeAlert(const Setup &s)
  {
   if(!InpAlertSetups)
      return;
   if(s.bar != 1)
      return;                 // only the bar that just closed
   if(g_lastAlertBar == s.time)
      return;
   g_lastAlertBar = s.time;
   string msg = (s.dir > 0 ? "LONG setup " : "SHORT setup ") +
                IntegerToString(s.score) + "pts  " + s.reason +
                "  " + Symbol() + " " + TFName(Period());
   FireAlert(msg);
  }

void FireAlert(const string msg)
  {
   string full = "PAS  " + Symbol() + " " + TFName(Period()) + "  " + msg;
   if(InpAlertPopup)
      Alert(full);
   else
      Print(full);
   if(InpAlertSound)
      PlaySound(InpSoundFile);
   if(InpAlertPush)
      SendNotification(full);
  }

//+------------------------------------------------------------------+
//| Housekeeping                                                      |
//+------------------------------------------------------------------+
void WipeObjects()
  {
   int total = ObjectsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, PAS_PREFIX) == 0)
         ObjectDelete(name);
     }
  }

double PipSize()
  {
   if(Digits == 3 || Digits == 5)
      return(Point * 10.0);
   return(Point);
  }

int PasBarSeconds()
  {
   int p = Period();
   if(p == PERIOD_MN1)
      return(30 * 86400);
   if(p == PERIOD_W1)
      return(7 * 86400);
   return(p * 60);
  }
//+------------------------------------------------------------------+
