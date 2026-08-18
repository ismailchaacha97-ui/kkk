//+------------------------------------------------------------------+
//|                               PropFirm_Institutional_Edge_Pro.mq4|
//|                     Institutional Prop Firm & Hedge Fund Strategy |
//|                 Smart Money Concepts (SMC) + Drawdown Engine Pro |
//|                                   Copyright 2026, Institutional  |
//|                     100% Standalone - Ultra-Stable Non-Disappearing|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional Edge Systems"
#property link      "https://github.com/ismailchaacha97-ui/kkk"
#property version   "3.60"
#property strict
#property indicator_chart_window
#property indicator_buffers 6

#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLimeGreen
#property indicator_width1  2
#property indicator_label1  "Institutional Buy Signal"

#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrDeepPink
#property indicator_width2  2
#property indicator_label2  "Institutional Sell Signal"

#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCyan
#property indicator_width3  1
#property indicator_label3  "Bullish Liquidity Sweep (SSL)"

#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrMagenta
#property indicator_width4  1
#property indicator_label4  "Bearish Liquidity Sweep (BSL)"

#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrMediumSpringGreen
#property indicator_width5  1
#property indicator_label5  "Bullish Structure Shift (CHoCH)"

#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrTomato
#property indicator_width6  1
#property indicator_label6  "Bearish Structure Shift (CHoCH)"

//+------------------------------------------------------------------+
//| ENUMS & STRUCTURE DEFINITIONS                                    |
//+------------------------------------------------------------------+
enum ENUM_PROPFIRM_PROFILE
{
   PROPFIRM_FTMO,          // FTMO (5% Daily DD, 10% Max DD, 10% Target)
   PROPFIRM_FUNDEDNEXT,    // FundedNext (5% Daily DD, 10% Max DD, 8% Target)
   PROPFIRM_THE5ERS,       // The 5%ers (4% Daily DD, 8% Max DD, 8% Target)
   PROPFIRM_TOPSTEP,       // Topstep (Daily Loss Limit, Max Loss Limit)
   PROPFIRM_ALPHA_CAPITAL, // Alpha Capital (5% Daily DD, 10% Max DD)
   PROPFIRM_CUSTOM         // Custom User Defined Rules
};

enum ENUM_HUD_THEME
{
   THEME_DARK_INSTITUTIONAL, // Sleek Obsidian & Cyan/Emerald
   THEME_BLOOMBERG_TERMINAL, // Amber & Slate Dark
   THEME_CYBER_MATRIX,       // Neon Cyan & Hot Magenta
   THEME_CLEAN_LIGHT         // Crisp Light Grey & Royal Blue
};

enum ENUM_OB_DISPLAY
{
   OB_DISPLAY_ALL,         // Show All (Unmitigated Bright, Mitigated Faded)
   OB_DISPLAY_UNMITIGATED  // Show Only Active Unmitigated Zones
};

struct SwingPoint
{
   datetime time;
   double   price;
   int      barIndex;
   int      type;            // +1 = Swing High, -1 = Swing Low
   bool     isBroken;
   bool     isSwept;
   string   label;
};

struct OrderBlock
{
   datetime time;
   double   high;
   double   low;
   double   open;
   double   close;
   int      direction;       // +1 = Bullish OB (Demand), -1 = Bearish OB (Supply)
   bool     isMitigated;
   datetime mitigationTime;
   double   volume;
   double   strength;
   string   objName;
};

struct FairValueGap
{
   datetime time;
   double   top;
   double   bottom;
   double   consequentEncroachment; // 50% CE level
   int      direction;              // +1 = Bullish FVG, -1 = Bearish FVG
   bool     isMitigated;
   datetime mitigationTime;
   string   objName;
};

struct PropFirmRiskState
{
   double initialBalance;
   double dayStartEquity;
   double currentBalance;
   double currentEquity;
   double floatingPnL;
   double todayClosedPnL;
   double todayTotalPnL;
   double todayDrawdownPct;
   double maxDailyDrawdownPct;
   double remainingDailyLossPct;
   double remainingDailyLossCash;
   double peakEquity;
   double overallDrawdownPct;
   double maxOverallDrawdownPct;
   double remainingOverallLossPct;
   double remainingOverallLossCash;
   double profitTargetPct;
   double profitTargetCash;
   double currentProfitPct;
   bool   isDailyDDBreached;
   bool   isOverallDDBreached;
   bool   isDailyDDWarning;
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//--- 1. INSTITUTIONAL MARKET STRUCTURE (SMC)
input string               InpHeaderSMC             = "=== INSTITUTIONAL MARKET STRUCTURE ===";
input int                  InpSwingLookback         = 5;             // Swing Fractal Lookback (Bars)
input int                  InpMaxHistoryBars        = 800;           // Historical Bars to Calculate
input bool                 InpShowStructure         = true;          // Show BOS & CHoCH Structure Lines
input bool                 InpShowBOS               = true;          // Break of Structure (BOS)
input bool                 InpShowCHoCH             = true;          // Change of Character (MSS/CHoCH)
input color                InpColorBullStructure    = clrLimeGreen;  // Bullish Structure Color
input color                InpColorBearStructure    = clrDeepPink;   // Bearish Structure Color

//--- 2. INSTITUTIONAL ORDER BLOCKS (OB)
input string               InpHeaderOB              = "=== INSTITUTIONAL ORDER BLOCKS (OB) ===";
input bool                 InpShowOrderBlocks       = true;          // Show Institutional Order Blocks
input ENUM_OB_DISPLAY      InpOBDisplayMode         = OB_DISPLAY_ALL;// Order Block Display Mode
input int                  InpMaxOrderBlocks        = 8;             // Max Active Order Blocks on Chart
input color                InpColorBullishOB        = C'15,75,50';   // Bullish Demand OB
input color                InpColorBearishOB        = C'85,25,35';   // Bearish Supply OB
input color                InpColorMitigatedOB      = C'40,45,55';   // Faded Mitigated OB Color

//--- 3. FAIR VALUE GAPS (FVG / IMBALANCE)
input string               InpHeaderFVG             = "=== FAIR VALUE GAPS (IMBALANCE) ===";
input bool                 InpShowFVG               = true;          // Show Fair Value Gaps (FVG)
input double               InpMinFVGPips            = 1.5;           // Minimum FVG Size (Pips)
input int                  InpMaxFVGToDraw          = 8;             // Max Active FVGs
input bool                 InpShowFVG_CE            = true;          // Show 50% Consequent Encroachment Line
input color                InpColorBullishFVG       = C'10,65,85';   // Bullish FVG Color
input color                InpColorBearishFVG       = C'85,45,20';   // Bearish FVG Color

//--- 4. LIQUIDITY POOLS & STOP HUNTS
input string               InpHeaderLiquidity       = "=== LIQUIDITY POOLS & STOP HUNTS ===";
input bool                 InpShowLiquiditySweeps   = true;          // Detect Turtle Soup / Liquidity Sweeps
input double               InpSweepWickPercent      = 35.0;          // Min Rejection Wick %
input bool                 InpShowEqualHighLow      = true;          // Detect Retail Equal Highs/Lows (EQH/EQL)
input double               InpEQHTolerancePips      = 2.0;           // EQH/EQL Tolerance (Pips)
input color                InpColorLiquidity        = clrGold;       // Liquidity Pools ($$$)

//--- 5. INSTITUTIONAL TIME & KILL ZONES
input string               InpHeaderKillzones       = "=== INSTITUTIONAL KILL ZONES ===";
input bool                 InpShowKillzones         = true;          // Highlight Institutional Kill Zones
input int                  InpBrokerGMTOffset       = 3;             // Broker Server GMT Offset (3 for GMT+3)
input string               InpAsianSession          = "00:00-07:00"; // Asian Range
input string               InpLondonKillzone        = "07:00-10:00"; // London Open KZ
input string               InpNYKillzone            = "12:00-15:00"; // New York Open KZ
input string               InpLondonCloseKZ         = "15:00-17:00"; // London Close
input bool                 InpFilterSignalsByKZ     = false;         // Only Signal Inside Kill Zones

//--- 6. PROP FIRM A+ CONFLUENCE SIGNALS
input string               InpHeaderSignals         = "=== PROP FIRM A+ CONFLUENCE SIGNALS ===";
input bool                 InpEnableSignals         = true;          // Enable High-Probability A+ Signals
input int                  InpMinConfluenceScore    = 75;            // Min Confluence Score (0-100)
input double               InpTargetRiskReward      = 3.0;           // Target R:R Ratio (1:3 RRR)
input double               InpSLBufferPips          = 2.0;           // SL Invalidation Buffer (Pips)
input double               InpRiskPerTradePct       = 0.5;           // Default Risk % Per Trade

//--- 7. PROP FIRM DRAWDOWN HUD & DASHBOARD
input string               InpHeaderHUD             = "=== PROP FIRM DRAWDOWN HUD & DASHBOARD ===";
input bool                 InpShowDashboard         = true;          // Show Prop Firm HUD on Chart
input ENUM_PROPFIRM_PROFILE InpPropFirmProfile     = PROPFIRM_FTMO; // Challenge Preset (FTMO/FundedNext)
input double               InpMaxDailyDrawdownPct   = 5.0;           // Max Daily Drawdown % (5%)
input double               InpMaxOverallDrawdownPct = 10.0;          // Max Overall Drawdown % (10%)
input double               InpProfitTargetPct       = 10.0;          // Target % (10%)
input ENUM_HUD_THEME       InpDashboardTheme        = THEME_DARK_INSTITUTIONAL;
input int                  InpDashboardX            = 20;
input int                  InpDashboardY            = 30;

//--- 8. ALERTS & NOTIFICATIONS
input string               InpHeaderAlerts          = "=== INSTITUTIONAL ALERTS ===";
input bool                 InpAlertPopup            = true;
input bool                 InpAlertSound            = true;
input bool                 InpAlertPush             = true;          // Push alerts to smartphone MT4 app
input bool                 InpAlertEmail            = false;
input bool                 InpAlertDailyLossWarning = true;          // Alert on 70% Daily Loss limit usage

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES & BUFFERS                                       |
//+------------------------------------------------------------------+
double BufferBuySignal[];
double BufferSellSignal[];
double BufferBullSweep[];
double BufferBearSweep[];
double BufferCHoCHBull[];
double BufferCHoCHBear[];

// Prefix for chart graphical objects
const string PREFIX = "PFE_";

// Dynamic storage arrays
SwingPoint    g_swings[];
OrderBlock    g_orderBlocks[];
FairValueGap  g_fvg[];
int           g_totalSwings = 0;
int           g_totalOBs = 0;
int           g_totalFVGs = 0;

// Tracking state for daily drawdown
datetime      g_currentDayStartTime = 0;
double        g_dayStartEquity = 0.0;
double        g_peakEquity = 0.0;
datetime      g_lastAlertTime = 0;
datetime      g_lastSignalBar = 0;
bool          g_dailyWarningSent = false;
bool          g_dashboardVisible = true;

// Pip multiplier
double        g_pipValue = 0.0001;
double        g_pointFactor = 1.0;

// Forward declarations
void ScanMarketStructure(const int rates_total, const int limit, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[]);
void ScanOrderBlocks(const int rates_total, const int limit, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[]);
void ScanFairValueGaps(const int rates_total, const int limit, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[]);
void ScanLiquiditySweeps(const int rates_total, const int limit, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[]);
void DrawKillzones();
void EvaluateInstitutionalSignals(const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[], const long &tick_volume[], int rates_total);
void RenderPropFirmHUD();
void InitializeDailyDrawdownState();
void UpdateDailyDrawdownAnchor();
double CalculateDayStartEquity();
void CleanAllIndicatorObjects();
void RegisterSwingPoint(datetime t, double price, int barIdx, int type);
void CheckStructureBreaks(int currentBar, const datetime &time[], const double &open[], const double &high[], const double &low[], const double &close[]);
bool IsBearishTrendPrior(int swingIdx);
bool IsBullishTrendPrior(int swingIdx);
void DrawStructureLine(datetime t1, double p1, datetime t2, double p2, string label, color clr, int style, int width);
void RegisterOrderBlock(datetime t, double h, double l, double o, double c, int dir, double vol);
void UpdateOrderBlocksMitigation(const datetime &time[], const double &high[], const double &low[], const double &close[]);
void DrawOBRectangle(int obIdx);
void RegisterFVG(datetime t, double top, double bot, int dir);
void UpdateFVGMitigation(const datetime &time[], const double &high[], const double &low[]);
void DrawFVGRectangle(int fvgIdx);
void DrawSweepMarker(datetime t, double price, string text, color clr, bool isTop);
void ScanEqualHighsAndLows(const datetime &time[]);
bool IsInInstitutionalKillzone();
double CalculatePropFirmLotSize(double stopLossPips, double riskPct);
void DrawTradeSignalVisuals(datetime t, double entry, double sl, double tp1, double tp2, int dir, double score);
void EmitSignalAlert(int dir, double score, double entry, double sl, double tp1, double tp2, double lots, string reasons);
void TriggerAlert(string text);
void CreateHUDLabel(string subName, int x, int y, string text, string font, int fontSize, color clr);
void CreateHUDPanel(string subName, int x, int y, int w, int h, color bgColor, color borderColor);
string PeriodToStr();

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Determine pip multiplier
   if(Digits == 3 || Digits == 5)
   {
      g_pipValue = Point * 10;
      g_pointFactor = 10;
   }
   else
   {
      g_pipValue = Point;
      g_pointFactor = 1;
   }

   // Initialize Indicator Buffers
   SetIndexBuffer(0, BufferBuySignal);
   SetIndexBuffer(1, BufferSellSignal);
   SetIndexBuffer(2, BufferBullSweep);
   SetIndexBuffer(3, BufferBearSweep);
   SetIndexBuffer(4, BufferCHoCHBull);
   SetIndexBuffer(5, BufferCHoCHBear);

   // CRITICAL: Set all buffers as series to match MT4 Timeseries indexing (0 = latest candle)
   ArraySetAsSeries(BufferBuySignal, true);
   ArraySetAsSeries(BufferSellSignal, true);
   ArraySetAsSeries(BufferBullSweep, true);
   ArraySetAsSeries(BufferBearSweep, true);
   ArraySetAsSeries(BufferCHoCHBull, true);
   ArraySetAsSeries(BufferCHoCHBear, true);

   // Set Empty Values
   SetIndexEmptyValue(0, 0.0);
   SetIndexEmptyValue(1, 0.0);
   SetIndexEmptyValue(2, 0.0);
   SetIndexEmptyValue(3, 0.0);
   SetIndexEmptyValue(4, 0.0);
   SetIndexEmptyValue(5, 0.0);

   // Styling
   SetIndexStyle(0, DRAW_ARROW, EMPTY, 2, clrLimeGreen);
   SetIndexArrow(0, 233); // Up Arrow
   SetIndexStyle(1, DRAW_ARROW, EMPTY, 2, clrDeepPink);
   SetIndexArrow(1, 234); // Down Arrow

   SetIndexStyle(2, DRAW_ARROW, EMPTY, 1, clrCyan);
   SetIndexArrow(2, 217); // Bullish Sweep Diamond
   SetIndexStyle(3, DRAW_ARROW, EMPTY, 1, clrMagenta);
   SetIndexArrow(3, 218); // Bearish Sweep Diamond

   SetIndexStyle(4, DRAW_ARROW, EMPTY, 1, clrMediumSpringGreen);
   SetIndexArrow(4, 159); // Bullish CHoCH Dot
   SetIndexStyle(5, DRAW_ARROW, EMPTY, 1, clrTomato);
   SetIndexArrow(5, 159); // Bearish CHoCH Dot

   IndicatorDigits(Digits);
   IndicatorShortName("PropFirm Institutional Edge Pro");

   g_dashboardVisible = InpShowDashboard;

   // Initialize Day Start Equity
   InitializeDailyDrawdownState();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up all graphical objects created by this indicator
   ObjectsDeleteAll(0, PREFIX);
   Comment("");
}

//+------------------------------------------------------------------+
//| Chart Event Handler (Hotkeys)                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      // Press 'D' to toggle Dashboard HUD
      if(lparam == 'D' || lparam == 'd')
      {
         g_dashboardVisible = !g_dashboardVisible;
         if(!g_dashboardVisible)
         {
            ObjectsDeleteAll(0, PREFIX + "HUD_");
         }
         else
         {
            RenderPropFirmHUD();
         }
         ChartRedraw();
      }
   }
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   if(rates_total < InpSwingLookback * 3 + 10) return(0);

   // Update daily drawdown anchor at start of day
   UpdateDailyDrawdownAnchor();

   // Determine calculation range
   int limit;
   if(prev_calculated == 0)
   {
      // Full recalculation on load/timeframe change
      CleanAllIndicatorObjects();
      limit = MathMin(rates_total - InpSwingLookback * 2 - 2, InpMaxHistoryBars);
   }
   else
   {
      // Incremental calculation on live ticks
      limit = rates_total - prev_calculated + 5;
      if(limit > InpMaxHistoryBars) limit = InpMaxHistoryBars;
   }

   // 1. Process Institutional SMC Engine
   ScanMarketStructure(rates_total, limit, time, open, high, low, close, tick_volume);

   // 2. Scan Order Blocks & Fair Value Gaps
   if(InpShowOrderBlocks) ScanOrderBlocks(rates_total, limit, time, open, high, low, close, tick_volume);
   if(InpShowFVG) ScanFairValueGaps(rates_total, limit, time, open, high, low, close);

   // 3. Scan Institutional Liquidity Sweeps
   if(InpShowLiquiditySweeps) ScanLiquiditySweeps(rates_total, limit, time, open, high, low, close);

   // 4. Scan Session Killzones
   if(InpShowKillzones) DrawKillzones();

   // 5. Evaluate A+ Confluence Signals on Completed Bar
   if(InpEnableSignals)
   {
      EvaluateInstitutionalSignals(time, open, high, low, close, tick_volume, rates_total);
   }

   // 6. Render Prop Firm Dashboard HUD
   if(g_dashboardVisible)
   {
      RenderPropFirmHUD();
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Initialize / Anchor Daily Equity for Prop Firm Drawdown Tracker  |
//+------------------------------------------------------------------+
void InitializeDailyDrawdownState()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   g_currentDayStartTime = StructToTime(dt);

   g_dayStartEquity = CalculateDayStartEquity();
   if(g_dayStartEquity <= 0) g_dayStartEquity = AccountBalance();

   g_peakEquity = AccountBalance();
   if(AccountEquity() > g_peakEquity) g_peakEquity = AccountEquity();
}

//+------------------------------------------------------------------+
//| Update Daily Drawdown Anchor at midnight 00:00 server time       |
//+------------------------------------------------------------------+
void UpdateDailyDrawdownAnchor()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime todayStart = StructToTime(dt);

   if(todayStart > g_currentDayStartTime)
   {
      g_currentDayStartTime = todayStart;
      g_dayStartEquity = AccountEquity();
      g_dailyWarningSent = false;
   }

   if(AccountEquity() > g_peakEquity)
   {
      g_peakEquity = AccountEquity();
   }
}

//+------------------------------------------------------------------+
//| Calculate Day Start Equity accurately from Account Balance/Trades|
//+------------------------------------------------------------------+
double CalculateDayStartEquity()
{
   double balance = AccountBalance();
   double todayClosedProfit = 0.0;

   int totalHistory = OrdersHistoryTotal();
   for(int i = 0; i < totalHistory; i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
      {
         if(OrderCloseTime() >= g_currentDayStartTime)
         {
            todayClosedProfit += OrderProfit() + OrderSwap() + OrderCommission();
         }
      }
   }

   double startDayBalance = balance - todayClosedProfit;
   return(startDayBalance);
}

//+------------------------------------------------------------------+
//| Clean indicator-specific objects                                 |
//+------------------------------------------------------------------+
void CleanAllIndicatorObjects()
{
   ObjectsDeleteAll(0, PREFIX);
   ArrayResize(g_swings, 0);
   ArrayResize(g_orderBlocks, 0);
   ArrayResize(g_fvg, 0);
   g_totalSwings = 0;
   g_totalOBs = 0;
   g_totalFVGs = 0;
}

//+------------------------------------------------------------------+
//| 1. SCAN MARKET STRUCTURE (Fractal Swings, BOS, CHoCH)             |
//+------------------------------------------------------------------+
void ScanMarketStructure(const int rates_total, const int limit,
                         const datetime &time[], const double &open[],
                         const double &high[], const double &low[],
                         const double &close[], const long &tick_volume[])
{
   int lookback = InpSwingLookback;
   int startBar = MathMin(limit + lookback + 5, rates_total - lookback - 2);

   for(int i = startBar; i >= 1; i--)
   {
      // Check Swing High
      bool isSwingHigh = true;
      for(int k = 1; k <= lookback; k++)
      {
         if(high[i] <= high[i - k] || high[i] <= high[i + k])
         {
            isSwingHigh = false;
            break;
         }
      }

      // Check Swing Low
      bool isSwingLow = true;
      for(int k = 1; k <= lookback; k++)
      {
         if(low[i] >= low[i - k] || low[i] >= low[i + k])
         {
            isSwingLow = false;
            break;
         }
      }

      if(isSwingHigh)
      {
         RegisterSwingPoint(time[i], high[i], i, 1);
      }
      if(isSwingLow)
      {
         RegisterSwingPoint(time[i], low[i], i, -1);
      }

      // Structure Break Analysis (BOS / CHoCH)
      CheckStructureBreaks(i, time, open, high, low, close);
   }
}

//+------------------------------------------------------------------+
//| Register a confirmed Swing Point in dynamic array                |
//+------------------------------------------------------------------+
void RegisterSwingPoint(datetime t, double price, int barIdx, int type)
{
   for(int j = g_totalSwings - 1; j >= MathMax(0, g_totalSwings - 10); j--)
   {
      if(g_swings[j].time == t && g_swings[j].type == type) return;
   }

   ArrayResize(g_swings, g_totalSwings + 1);
   g_swings[g_totalSwings].time = t;
   g_swings[g_totalSwings].price = price;
   g_swings[g_totalSwings].barIndex = barIdx;
   g_swings[g_totalSwings].type = type;
   g_swings[g_totalSwings].isBroken = false;
   g_swings[g_totalSwings].isSwept = false;
   g_swings[g_totalSwings].label = (type == 1) ? "SH" : "SL";
   g_totalSwings++;

   // Draw swing marker
   if(InpShowStructure)
   {
      string name = PREFIX + "SWING_" + TimeToString(t) + "_" + IntegerToString(type);
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
         ObjectSetString(0, name, OBJPROP_TEXT, (type == 1) ? "● SH" : "● SL");
         ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 7);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clrDimGray);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, (type == 1) ? ANCHOR_LOWER : ANCHOR_UPPER);
      }
   }
}

//+------------------------------------------------------------------+
//| Check Break of Structure (BOS) and Market Structure Shift (CHoCH)|
//+------------------------------------------------------------------+
void CheckStructureBreaks(int currentBar, const datetime &time[], const double &open[],
                          const double &high[], const double &low[], const double &close[])
{
   if(g_totalSwings < 4) return;

   for(int s = g_totalSwings - 1; s >= MathMax(0, g_totalSwings - 6); s--)
   {
      if(g_swings[s].isBroken) continue;
      if(time[currentBar] <= g_swings[s].time) continue;

      // Bullish Break above Swing High
      if(g_swings[s].type == 1 && close[currentBar] > g_swings[s].price && close[currentBar + 1] <= g_swings[s].price)
      {
         g_swings[s].isBroken = true;

         bool isCHoCH = IsBearishTrendPrior(s);
         string tag = isCHoCH ? "CHoCH" : "BOS";

         if(isCHoCH && InpShowCHoCH)
         {
            BufferCHoCHBull[currentBar] = low[currentBar] - (10 * Point);
            DrawStructureLine(g_swings[s].time, g_swings[s].price, time[currentBar], g_swings[s].price,
                              tag + " (Bullish MSS)", InpColorBullStructure, STYLE_SOLID, 2);
            TriggerAlert("Bullish " + tag + " (Market Structure Shift) confirmed on " + Symbol() + " [" + PeriodToStr() + "]");
         }
         else if(!isCHoCH && InpShowBOS)
         {
            DrawStructureLine(g_swings[s].time, g_swings[s].price, time[currentBar], g_swings[s].price,
                              "BOS +", InpColorBullStructure, STYLE_DOT, 1);
         }
      }

      // Bearish Break below Swing Low
      if(g_swings[s].type == -1 && close[currentBar] < g_swings[s].price && close[currentBar + 1] >= g_swings[s].price)
      {
         g_swings[s].isBroken = true;

         bool isCHoCH = IsBullishTrendPrior(s);
         string tag = isCHoCH ? "CHoCH" : "BOS";

         if(isCHoCH && InpShowCHoCH)
         {
            BufferCHoCHBear[currentBar] = high[currentBar] + (10 * Point);
            DrawStructureLine(g_swings[s].time, g_swings[s].price, time[currentBar], g_swings[s].price,
                              tag + " (Bearish MSS)", InpColorBearStructure, STYLE_SOLID, 2);
            TriggerAlert("Bearish " + tag + " (Market Structure Shift) confirmed on " + Symbol() + " [" + PeriodToStr() + "]");
         }
         else if(!isCHoCH && InpShowBOS)
         {
            DrawStructureLine(g_swings[s].time, g_swings[s].price, time[currentBar], g_swings[s].price,
                              "BOS -", InpColorBearStructure, STYLE_DOT, 1);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if trend prior to swing was Bearish (for CHoCH determination)
//+------------------------------------------------------------------+
bool IsBearishTrendPrior(int swingIdx)
{
   if(swingIdx < 3) return(false);
   int highCount = 0, lowCount = 0;
   double prevHigh = 999999, prevLow = 999999;

   for(int i = swingIdx; i >= MathMax(0, swingIdx - 4); i--)
   {
      if(g_swings[i].type == 1)
      {
         if(g_swings[i].price < prevHigh) highCount++;
         prevHigh = g_swings[i].price;
      }
      else if(g_swings[i].type == -1)
      {
         if(g_swings[i].price < prevLow) lowCount++;
         prevLow = g_swings[i].price;
      }
   }
   return(highCount >= 1 && lowCount >= 1);
}

//+------------------------------------------------------------------+
//| Check if trend prior to swing was Bullish (for CHoCH determination)
//+------------------------------------------------------------------+
bool IsBullishTrendPrior(int swingIdx)
{
   if(swingIdx < 3) return(false);
   int highCount = 0, lowCount = 0;
   double prevHigh = -1, prevLow = -1;

   for(int i = swingIdx; i >= MathMax(0, swingIdx - 4); i--)
   {
      if(g_swings[i].type == 1)
      {
         if(g_swings[i].price > prevHigh && prevHigh > 0) highCount++;
         prevHigh = g_swings[i].price;
      }
      else if(g_swings[i].type == -1)
      {
         if(g_swings[i].price > prevLow && prevLow > 0) lowCount++;
         prevLow = g_swings[i].price;
      }
   }
   return(highCount >= 1 && lowCount >= 1);
}

//+------------------------------------------------------------------+
//| Draw graphical structure lines with institutional styling        |
//+------------------------------------------------------------------+
void DrawStructureLine(datetime t1, double p1, datetime t2, double p2, string label, color clr, int style, int width)
{
   string lineName = PREFIX + "STRUCT_LINE_" + TimeToString(t1) + "_" + DoubleToString(p1, Digits);
   string textName = PREFIX + "STRUCT_TXT_" + TimeToString(t1) + "_" + DoubleToString(p1, Digits);

   if(ObjectFind(0, lineName) < 0)
   {
      ObjectCreate(0, lineName, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, style);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, lineName, OBJPROP_RAY, false);
      ObjectSetInteger(0, lineName, OBJPROP_BACK, true);

      datetime midTime = t1 + (t2 - t1) / 2;
      ObjectCreate(0, textName, OBJ_TEXT, 0, midTime, p1);
      ObjectSetString(0, textName, OBJPROP_TEXT, "  " + label);
      ObjectSetString(0, textName, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, textName, OBJPROP_COLOR, clr);
   }
   else
   {
      ObjectSetDouble(0, lineName, OBJPROP_PRICE2, p2);
      ObjectSetInteger(0, lineName, OBJPROP_TIME2, t2);
   }
}

//+------------------------------------------------------------------+
//| 2. SCAN INSTITUTIONAL ORDER BLOCKS (OB)                          |
//+------------------------------------------------------------------+
void ScanOrderBlocks(const int rates_total, const int limit,
                     const datetime &time[], const double &open[],
                     const double &high[], const double &low[],
                     const double &close[], const long &tick_volume[])
{
   int start = MathMin(limit + 5, rates_total - 10);

   for(int i = start; i >= 2; i--)
   {
      double atr = (High[iLowest(NULL, 0, MODE_LOW, 14, i)] - Low[iLowest(NULL, 0, MODE_LOW, 14, i)]) / 14.0;
      if(atr <= 0) atr = 10 * Point;

      bool isBullishDisplacement = (close[i] > open[i]) &&
                                   ((close[i] - open[i]) > 1.3 * (high[i] - low[i]) * 0.6) &&
                                   ((high[i] - low[i]) > 1.1 * atr);

      bool isBearishDisplacement = (close[i] < open[i]) &&
                                   ((open[i] - close[i]) > 1.3 * (high[i] - low[i]) * 0.6) &&
                                   ((high[i] - low[i]) > 1.1 * atr);

      if(isBullishDisplacement && (close[i + 1] < open[i + 1] || close[i + 2] < open[i + 2]))
      {
         int obIdx = (close[i + 1] < open[i + 1]) ? (i + 1) : (i + 2);
         RegisterOrderBlock(time[obIdx], high[obIdx], low[obIdx], open[obIdx], close[obIdx], 1, (double)tick_volume[obIdx]);
      }

      if(isBearishDisplacement && (close[i + 1] > open[i + 1] || close[i + 2] > open[i + 2]))
      {
         int obIdx = (close[i + 1] > open[i + 1]) ? (i + 1) : (i + 2);
         RegisterOrderBlock(time[obIdx], high[obIdx], low[obIdx], open[obIdx], close[obIdx], -1, (double)tick_volume[obIdx]);
      }
   }

   UpdateOrderBlocksMitigation(time, high, low, close);
}

//+------------------------------------------------------------------+
//| Register an Order Block into memory & draw rectangular zone      |
//+------------------------------------------------------------------+
void RegisterOrderBlock(datetime t, double h, double l, double o, double c, int dir, double vol)
{
   for(int k = 0; k < g_totalOBs; k++)
   {
      if(g_orderBlocks[k].time == t && g_orderBlocks[k].direction == dir) return;
   }

   if(g_totalOBs >= InpMaxOrderBlocks * 4) return;

   ArrayResize(g_orderBlocks, g_totalOBs + 1);
   g_orderBlocks[g_totalOBs].time = t;
   g_orderBlocks[g_totalOBs].high = h;
   g_orderBlocks[g_totalOBs].low = l;
   g_orderBlocks[g_totalOBs].open = o;
   g_orderBlocks[g_totalOBs].close = c;
   g_orderBlocks[g_totalOBs].direction = dir;
   g_orderBlocks[g_totalOBs].isMitigated = false;
   g_orderBlocks[g_totalOBs].volume = vol;
   g_orderBlocks[g_totalOBs].strength = 85.0;
   g_orderBlocks[g_totalOBs].objName = PREFIX + "OB_" + TimeToString(t) + "_" + IntegerToString(dir);
   g_totalOBs++;

   DrawOBRectangle(g_totalOBs - 1);
}

//+------------------------------------------------------------------+
//| Update mitigation & continuously extend active Order Blocks      |
//+------------------------------------------------------------------+
void UpdateOrderBlocksMitigation(const datetime &time[], const double &high[], const double &low[], const double &close[])
{
   datetime extendTime = TimeCurrent() + (PeriodSeconds() * 30);

   for(int i = g_totalOBs - 1; i >= 0; i--)
   {
      int bar = iBarShift(NULL, 0, g_orderBlocks[i].time);
      
      // Check mitigation if not already mitigated
      if(!g_orderBlocks[i].isMitigated)
      {
         for(int b = bar - 1; b >= 0; b--)
         {
            if(g_orderBlocks[i].direction == 1 && low[b] <= g_orderBlocks[i].high)
            {
               g_orderBlocks[i].isMitigated = true;
               g_orderBlocks[i].mitigationTime = time[b];
               break;
            }
            else if(g_orderBlocks[i].direction == -1 && high[b] >= g_orderBlocks[i].low)
            {
               g_orderBlocks[i].isMitigated = true;
               g_orderBlocks[i].mitigationTime = time[b];
               break;
            }
         }
      }

      string name = g_orderBlocks[i].objName;
      string lblName = name + "_LBL";

      if(g_orderBlocks[i].isMitigated)
      {
         if(InpOBDisplayMode == OB_DISPLAY_UNMITIGATED)
         {
            ObjectDelete(0, name);
            ObjectDelete(0, lblName);
         }
         else
         {
            // Keep mitigated OB faded so trader sees past institutional reaction
            ObjectSetInteger(0, name, OBJPROP_COLOR, InpColorMitigatedOB);
            ObjectSetInteger(0, name, OBJPROP_TIME2, (g_orderBlocks[i].mitigationTime > 0) ? g_orderBlocks[i].mitigationTime : extendTime);
         }
      }
      else
      {
         // Active unmitigated OB: CONTINUOUSLY EXTEND FORWARD SO IT NEVER DISAPPEARS!
         if(ObjectFind(0, name) >= 0)
         {
            ObjectSetInteger(0, name, OBJPROP_TIME2, extendTime);
         }
         else
         {
            DrawOBRectangle(i);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw Order Block zone rectangle                                  |
//+------------------------------------------------------------------+
void DrawOBRectangle(int obIdx)
{
   OrderBlock ob = g_orderBlocks[obIdx];
   string name = ob.objName;
   string lblName = name + "_LBL";
   datetime extendTime = TimeCurrent() + (PeriodSeconds() * 30);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, ob.time, ob.high, extendTime, ob.low);
      color obColor = (ob.direction == 1) ? InpColorBullishOB : InpColorBearishOB;
      ObjectSetInteger(0, name, OBJPROP_COLOR, obColor);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

      ObjectCreate(0, lblName, OBJ_TEXT, 0, ob.time, (ob.direction == 1) ? ob.low : ob.high);
      ObjectSetString(0, lblName, OBJPROP_TEXT, (ob.direction == 1) ? "+OB (Demand)" : "-OB (Supply)");
      ObjectSetString(0, lblName, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, (ob.direction == 1) ? clrLightSeaGreen : clrSalmon);
      ObjectSetInteger(0, lblName, OBJPROP_SELECTABLE, false);
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME2, extendTime);
   }
}

//+------------------------------------------------------------------+
//| 3. SCAN FAIR VALUE GAPS (FVG / IMBALANCES)                       |
//+------------------------------------------------------------------+
void ScanFairValueGaps(const int rates_total, const int limit,
                       const datetime &time[], const double &open[],
                       const double &high[], const double &low[],
                       const double &close[])
{
   int start = MathMin(limit + 5, rates_total - 6);
   double minGap = InpMinFVGPips * g_pipValue;

   for(int i = start; i >= 2; i--)
   {
      // Bullish FVG: Low of candle [i] > High of candle [i+2]
      if(low[i] > high[i + 2] + minGap)
      {
         double top = low[i];
         double bot = high[i + 2];
         RegisterFVG(time[i + 1], top, bot, 1);
      }

      // Bearish FVG: High of candle [i] < Low of candle [i+2]
      if(high[i] < low[i + 2] - minGap)
      {
         double top = low[i + 2];
         double bot = high[i];
         RegisterFVG(time[i + 1], top, bot, -1);
      }
   }

   UpdateFVGMitigation(time, high, low);
}

//+------------------------------------------------------------------+
//| Register Fair Value Gap into memory & draw zone                  |
//+------------------------------------------------------------------+
void RegisterFVG(datetime t, double top, double bot, int dir)
{
   for(int k = 0; k < g_totalFVGs; k++)
   {
      if(g_fvg[k].time == t && g_fvg[k].direction == dir) return;
   }

   if(g_totalFVGs >= InpMaxFVGToDraw * 4) return;

   ArrayResize(g_fvg, g_totalFVGs + 1);
   g_fvg[g_totalFVGs].time = t;
   g_fvg[g_totalFVGs].top = top;
   g_fvg[g_totalFVGs].bottom = bot;
   g_fvg[g_totalFVGs].consequentEncroachment = (top + bot) / 2.0;
   g_fvg[g_totalFVGs].direction = dir;
   g_fvg[g_totalFVGs].isMitigated = false;
   g_fvg[g_totalFVGs].objName = PREFIX + "FVG_" + TimeToString(t) + "_" + IntegerToString(dir);
   g_totalFVGs++;

   DrawFVGRectangle(g_totalFVGs - 1);
}

//+------------------------------------------------------------------+
//| Update mitigation & continuously extend active FVGs              |
//+------------------------------------------------------------------+
void UpdateFVGMitigation(const datetime &time[], const double &high[], const double &low[])
{
   datetime extendTime = TimeCurrent() + (PeriodSeconds() * 30);

   for(int i = g_totalFVGs - 1; i >= 0; i--)
   {
      int bar = iBarShift(NULL, 0, g_fvg[i].time);

      if(!g_fvg[i].isMitigated)
      {
         for(int b = bar - 1; b >= 0; b--)
         {
            if(g_fvg[i].direction == 1 && low[b] <= g_fvg[i].bottom)
            {
               g_fvg[i].isMitigated = true;
               g_fvg[i].mitigationTime = time[b];
               break;
            }
            else if(g_fvg[i].direction == -1 && high[b] >= g_fvg[i].top)
            {
               g_fvg[i].isMitigated = true;
               g_fvg[i].mitigationTime = time[b];
               break;
            }
         }
      }

      string name = g_fvg[i].objName;
      string ceName = name + "_CE";

      if(g_fvg[i].isMitigated)
      {
         ObjectDelete(0, name);
         ObjectDelete(0, ceName);
      }
      else
      {
         // Active FVG: Extend forward
         if(ObjectFind(0, name) >= 0)
         {
            ObjectSetInteger(0, name, OBJPROP_TIME2, extendTime);
            if(InpShowFVG_CE) ObjectSetInteger(0, ceName, OBJPROP_TIME2, extendTime);
         }
         else
         {
            DrawFVGRectangle(i);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw FVG zone rectangle and Consequent Encroachment (50% line)   |
//+------------------------------------------------------------------+
void DrawFVGRectangle(int fvgIdx)
{
   FairValueGap gap = g_fvg[fvgIdx];
   string name = gap.objName;
   datetime extendTime = TimeCurrent() + (PeriodSeconds() * 30);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, gap.time, gap.top, extendTime, gap.bottom);
      color fvgColor = (gap.direction == 1) ? InpColorBullishFVG : InpColorBearishFVG;
      ObjectSetInteger(0, name, OBJPROP_COLOR, fvgColor);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

      if(InpShowFVG_CE)
      {
         string ceName = name + "_CE";
         ObjectCreate(0, ceName, OBJ_TREND, 0, gap.time, gap.consequentEncroachment, extendTime, gap.consequentEncroachment);
         ObjectSetInteger(0, ceName, OBJPROP_COLOR, clrSilver);
         ObjectSetInteger(0, ceName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, ceName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, ceName, OBJPROP_RAY, false);
         ObjectSetInteger(0, ceName, OBJPROP_BACK, true);
         ObjectSetInteger(0, ceName, OBJPROP_SELECTABLE, false);
      }
   }
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME2, extendTime);
      if(InpShowFVG_CE) ObjectSetInteger(0, name + "_CE", OBJPROP_TIME2, extendTime);
   }
}

//+------------------------------------------------------------------+
//| 4. SCAN LIQUIDITY SWEEPS & EQUAL HIGHS/LOWS                      |
//+------------------------------------------------------------------+
void ScanLiquiditySweeps(const int rates_total, const int limit,
                         const datetime &time[], const double &open[],
                         const double &high[], const double &low[],
                         const double &close[])
{
   int start = MathMin(limit + 5, rates_total - 10);

   for(int i = start; i >= 1; i--)
   {
      double candleRange = high[i] - low[i];
      if(candleRange <= 0) continue;

      double upperWick = high[i] - MathMax(open[i], close[i]);
      double lowerWick = MathMin(open[i], close[i]) - low[i];

      // Buy-Side Liquidity (BSL) Sweep
      if((upperWick / candleRange) >= (InpSweepWickPercent / 100.0))
      {
         for(int s = g_totalSwings - 1; s >= MathMax(0, g_totalSwings - 8); s--)
         {
            if(g_swings[s].type == 1 && !g_swings[s].isSwept && time[i] > g_swings[s].time)
            {
               if(high[i] > g_swings[s].price && close[i] < g_swings[s].price)
               {
                  g_swings[s].isSwept = true;
                  BufferBearSweep[i] = high[i] + (8 * Point);
                  DrawSweepMarker(time[i], high[i], "BSL SWEEP $$$", clrMagenta, true);
                  TriggerAlert("Buy-Side Liquidity (BSL) Swept on " + Symbol() + " [" + PeriodToStr() + "] - Institutional Sell Setup Brewing!");
                  break;
               }
            }
         }
      }

      // Sell-Side Liquidity (SSL) Sweep
      if((lowerWick / candleRange) >= (InpSweepWickPercent / 100.0))
      {
         for(int s = g_totalSwings - 1; s >= MathMax(0, g_totalSwings - 8); s--)
         {
            if(g_swings[s].type == -1 && !g_swings[s].isSwept && time[i] > g_swings[s].time)
            {
               if(low[i] < g_swings[s].price && close[i] > g_swings[s].price)
               {
                  g_swings[s].isSwept = true;
                  BufferBullSweep[i] = low[i] - (8 * Point);
                  DrawSweepMarker(time[i], low[i], "SSL SWEEP $$$", clrCyan, false);
                  TriggerAlert("Sell-Side Liquidity (SSL) Swept on " + Symbol() + " [" + PeriodToStr() + "] - Institutional Buy Setup Brewing!");
                  break;
               }
            }
         }
      }
   }

   if(InpShowEqualHighLow) ScanEqualHighsAndLows(time);
}

//+------------------------------------------------------------------+
//| Draw Liquidity Sweep Visual Marker                               |
//+------------------------------------------------------------------+
void DrawSweepMarker(datetime t, double price, string text, color clr, bool isTop)
{
   string name = PREFIX + "SWEEP_" + TimeToString(t);
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, price);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, isTop ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

//+------------------------------------------------------------------+
//| Scan for Equal Highs (EQH) and Equal Lows (EQL)                  |
//+------------------------------------------------------------------+
void ScanEqualHighsAndLows(const datetime &time[])
{
   double tol = InpEQHTolerancePips * g_pipValue;
   if(g_totalSwings < 4) return;

   for(int i = g_totalSwings - 1; i >= MathMax(0, g_totalSwings - 6); i--)
   {
      for(int j = i - 1; j >= MathMax(0, g_totalSwings - 8); j--)
      {
         if(g_swings[i].type == 1 && g_swings[j].type == 1)
         {
            if(MathAbs(g_swings[i].price - g_swings[j].price) <= tol)
            {
               string name = PREFIX + "EQH_" + TimeToString(g_swings[j].time);
               if(ObjectFind(0, name) < 0)
               {
                  ObjectCreate(0, name, OBJ_TREND, 0, g_swings[j].time, g_swings[j].price, g_swings[i].time + (PeriodSeconds() * 15), g_swings[i].price);
                  ObjectSetInteger(0, name, OBJPROP_COLOR, InpColorLiquidity);
                  ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
                  ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
                  ObjectSetInteger(0, name, OBJPROP_RAY, false);
                  ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

                  string txtName = name + "_TXT";
                  ObjectCreate(0, txtName, OBJ_TEXT, 0, g_swings[i].time, g_swings[i].price);
                  ObjectSetString(0, txtName, OBJPROP_TEXT, "  EQH (Buy Stops $$$)");
                  ObjectSetString(0, txtName, OBJPROP_FONT, "Segoe UI Bold");
                  ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 8);
                  ObjectSetInteger(0, txtName, OBJPROP_COLOR, InpColorLiquidity);
                  ObjectSetInteger(0, txtName, OBJPROP_SELECTABLE, false);
               }
            }
         }
         else if(g_swings[i].type == -1 && g_swings[j].type == -1)
         {
            if(MathAbs(g_swings[i].price - g_swings[j].price) <= tol)
            {
               string name = PREFIX + "EQL_" + TimeToString(g_swings[j].time);
               if(ObjectFind(0, name) < 0)
               {
                  ObjectCreate(0, name, OBJ_TREND, 0, g_swings[j].time, g_swings[j].price, g_swings[i].time + (PeriodSeconds() * 15), g_swings[i].price);
                  ObjectSetInteger(0, name, OBJPROP_COLOR, InpColorLiquidity);
                  ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
                  ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
                  ObjectSetInteger(0, name, OBJPROP_RAY, false);
                  ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

                  string txtName = name + "_TXT";
                  ObjectCreate(0, txtName, OBJ_TEXT, 0, g_swings[i].time, g_swings[i].price);
                  ObjectSetString(0, txtName, OBJPROP_TEXT, "  EQL (Sell Stops $$$)");
                  ObjectSetString(0, txtName, OBJPROP_FONT, "Segoe UI Bold");
                  ObjectSetInteger(0, txtName, OBJPROP_FONTSIZE, 8);
                  ObjectSetInteger(0, txtName, OBJPROP_COLOR, InpColorLiquidity);
                  ObjectSetInteger(0, txtName, OBJPROP_SELECTABLE, false);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| 5. DRAW INSTITUTIONAL KILL ZONES (Asian, London, NY)             |
//+------------------------------------------------------------------+
void DrawKillzones()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   int gmtHour = (dt.hour - InpBrokerGMTOffset + 24) % 24;

   string activeSession = "OFF-HOURS";
   color sessColor = clrDimGray;

   if(gmtHour >= 0 && gmtHour < 7)
   {
      activeSession = "ASIAN ACCUMULATION";
      sessColor = clrTeal;
   }
   else if(gmtHour >= 7 && gmtHour < 10)
   {
      activeSession = "LONDON OPEN KILLZONE 🔥";
      sessColor = clrOrangeRed;
   }
   else if(gmtHour >= 12 && gmtHour < 15)
   {
      activeSession = "NEW YORK OPEN KILLZONE 🔥";
      sessColor = clrDodgerBlue;
   }
   else if(gmtHour >= 15 && gmtHour < 17)
   {
      activeSession = "LONDON CLOSE KILLZONE";
      sessColor = clrMediumPurple;
   }

   string labelName = PREFIX + "ACTIVE_KZ_STATUS";
   if(ObjectFind(0, labelName) < 0)
   {
      ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 30);
      ObjectSetString(0, labelName, OBJPROP_FONT, "Segoe UI Bold");
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, labelName, OBJPROP_SELECTABLE, false);
   }
   ObjectSetString(0, labelName, OBJPROP_TEXT, "SESSION: " + activeSession + " (GMT " + StringFormat("%02d:%02d", gmtHour, dt.min) + ")");
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, sessColor);
}

//+------------------------------------------------------------------+
//| Check if current time is inside Institutional Killzone           |
//+------------------------------------------------------------------+
bool IsInInstitutionalKillzone()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int gmtHour = (dt.hour - InpBrokerGMTOffset + 24) % 24;

   if((gmtHour >= 7 && gmtHour < 10) || (gmtHour >= 12 && gmtHour < 15))
   {
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| 6. EVALUATE HIGH-PROBABILITY INSTITUTIONAL A+ SIGNALS            |
//+------------------------------------------------------------------+
void EvaluateInstitutionalSignals(const datetime &time[], const double &open[],
                                  const double &high[], const double &low[],
                                  const double &close[], const long &tick_volume[],
                                  int rates_total)
{
   int bar = 1;
   if(time[bar] == g_lastSignalBar) return;

   if(InpFilterSignalsByKZ && !IsInInstitutionalKillzone()) return;

   double bullScore = 0.0;
   double bearScore = 0.0;
   string bullReasons = "";
   string bearReasons = "";

   // Factor 1: Liquidity Sweep (+25 pts)
   bool recentSSL = false;
   bool recentBSL = false;
   for(int k = 1; k <= 5; k++)
   {
      if(BufferBullSweep[k] != 0.0 && BufferBullSweep[k] != EMPTY_VALUE) recentSSL = true;
      if(BufferBearSweep[k] != 0.0 && BufferBearSweep[k] != EMPTY_VALUE) recentBSL = true;
   }
   if(recentSSL) { bullScore += 25; bullReasons += "[SSL Swept +25] "; }
   if(recentBSL) { bearScore += 25; bearReasons += "[BSL Swept +25] "; }

   // Factor 2: CHoCH (+25 pts)
   bool recentBullCHoCH = false;
   bool recentBearCHoCH = false;
   for(int k = 1; k <= 8; k++)
   {
      if(BufferCHoCHBull[k] != 0.0 && BufferCHoCHBull[k] != EMPTY_VALUE) recentBullCHoCH = true;
      if(BufferCHoCHBear[k] != 0.0 && BufferCHoCHBear[k] != EMPTY_VALUE) recentBearCHoCH = true;
   }
   if(recentBullCHoCH) { bullScore += 25; bullReasons += "[Bull CHoCH +25] "; }
   if(recentBearCHoCH) { bearScore += 25; bearReasons += "[Bear CHoCH +25] "; }

   // Factor 3: OB Retest (+20 pts)
   bool atBullishOB = false;
   bool atBearishOB = false;
   for(int ob = 0; ob < g_totalOBs; ob++)
   {
      if(!g_orderBlocks[ob].isMitigated)
      {
         if(g_orderBlocks[ob].direction == 1 && low[bar] <= g_orderBlocks[ob].high && close[bar] >= g_orderBlocks[ob].low)
         {
            atBullishOB = true;
            break;
         }
         else if(g_orderBlocks[ob].direction == -1 && high[bar] >= g_orderBlocks[ob].low && close[bar] <= g_orderBlocks[ob].high)
         {
            atBearishOB = true;
            break;
         }
      }
   }
   if(atBullishOB) { bullScore += 20; bullReasons += "[Demand OB Tap +20] "; }
   if(atBearishOB) { bearScore += 20; bearReasons += "[Supply OB Tap +20] "; }

   // Factor 4: Kill Zone (+15 pts)
   if(IsInInstitutionalKillzone())
   {
      bullScore += 15; bullReasons += "[KZ Active +15] ";
      bearScore += 15; bearReasons += "[KZ Active +15] ";
   }

   // Factor 5: EMA Alignment (+15 pts)
   double fastEMA = iMA(NULL, 0, 20, 0, MODE_EMA, PRICE_CLOSE, bar);
   double slowEMA = iMA(NULL, 0, 50, 0, MODE_EMA, PRICE_CLOSE, bar);
   if(close[bar] > fastEMA && fastEMA > slowEMA)
   {
      bullScore += 15; bullReasons += "[EMA Alignment +15] ";
   }
   if(close[bar] < fastEMA && fastEMA < slowEMA)
   {
      bearScore += 15; bearReasons += "[EMA Alignment +15] ";
   }

   double entryPrice = close[bar];

   // BULLISH SIGNAL
   if(bullScore >= InpMinConfluenceScore && bullScore > bearScore)
   {
      g_lastSignalBar = time[bar];
      BufferBuySignal[bar] = low[bar] - (15 * Point);

      double lowestLow = low[bar];
      for(int w = bar; w <= bar + 6; w++)
      {
         if(low[w] < lowestLow) lowestLow = low[w];
      }
      double slPrice = lowestLow - (InpSLBufferPips * g_pipValue);
      double slPips = MathAbs(entryPrice - slPrice) / g_pipValue;
      if(slPips < 5.0) slPips = 5.0;
      slPrice = entryPrice - (slPips * g_pipValue);

      double tp1Price = entryPrice + (slPips * 2.0 * g_pipValue);
      double tp2Price = entryPrice + (slPips * InpTargetRiskReward * g_pipValue);

      double recommendedLots = CalculatePropFirmLotSize(slPips, InpRiskPerTradePct);

      DrawTradeSignalVisuals(time[bar], entryPrice, slPrice, tp1Price, tp2Price, 1, bullScore);
      EmitSignalAlert(1, bullScore, entryPrice, slPrice, tp1Price, tp2Price, recommendedLots, bullReasons);
   }

   // BEARISH SIGNAL
   if(bearScore >= InpMinConfluenceScore && bearScore > bullScore)
   {
      g_lastSignalBar = time[bar];
      BufferSellSignal[bar] = high[bar] + (15 * Point);

      double highestHigh = high[bar];
      for(int w = bar; w <= bar + 6; w++)
      {
         if(high[w] > highestHigh) highestHigh = high[w];
      }
      double slPrice = highestHigh + (InpSLBufferPips * g_pipValue);
      double slPips = MathAbs(slPrice - entryPrice) / g_pipValue;
      if(slPips < 5.0) slPips = 5.0;
      slPrice = entryPrice + (slPips * g_pipValue);

      double tp1Price = entryPrice - (slPips * 2.0 * g_pipValue);
      double tp2Price = entryPrice - (slPips * InpTargetRiskReward * g_pipValue);

      double recommendedLots = CalculatePropFirmLotSize(slPips, InpRiskPerTradePct);

      DrawTradeSignalVisuals(time[bar], entryPrice, slPrice, tp1Price, tp2Price, -1, bearScore);
      EmitSignalAlert(-1, bearScore, entryPrice, slPrice, tp1Price, tp2Price, recommendedLots, bearReasons);
   }
}

//+------------------------------------------------------------------+
//| Calculate precise Lot Size for Prop Firm risk management         |
//+------------------------------------------------------------------+
double CalculatePropFirmLotSize(double stopLossPips, double riskPct)
{
   double accountEquity = AccountEquity();
   double riskAmount = accountEquity * (riskPct / 100.0);
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(tickValue <= 0 || stopLossPips <= 0) return(minLot);

   double pipsToTicks = g_pipValue / tickSize;
   double lossPerLot = stopLossPips * pipsToTicks * tickValue;

   if(lossPerLot <= 0) return(minLot);

   double rawLots = riskAmount / lossPerLot;
   double steppedLots = MathFloor(rawLots / lotStep) * lotStep;

   if(steppedLots < minLot) steppedLots = minLot;
   if(steppedLots > maxLot) steppedLots = maxLot;

   return(NormalizeDouble(steppedLots, 2));
}

//+------------------------------------------------------------------+
//| Draw visual entry, SL, TP target lines on chart                  |
//+------------------------------------------------------------------+
void DrawTradeSignalVisuals(datetime t, double entry, double sl, double tp1, double tp2, int dir, double score)
{
   string prefix = PREFIX + "SIG_" + TimeToString(t) + "_";
   datetime expTime = t + (PeriodSeconds() * 30);

   // Entry line
   ObjectDelete(0, prefix + "ENTRY");
   ObjectCreate(0, prefix + "ENTRY", OBJ_TREND, 0, t, entry, expTime, entry);
   ObjectSetInteger(0, prefix + "ENTRY", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix + "ENTRY", OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, prefix + "ENTRY", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, prefix + "ENTRY", OBJPROP_RAY, false);
   ObjectSetInteger(0, prefix + "ENTRY", OBJPROP_SELECTABLE, false);

   // SL line
   ObjectDelete(0, prefix + "SL");
   ObjectCreate(0, prefix + "SL", OBJ_TREND, 0, t, sl, expTime, sl);
   ObjectSetInteger(0, prefix + "SL", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, prefix + "SL", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, prefix + "SL", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, prefix + "SL", OBJPROP_RAY, false);
   ObjectSetInteger(0, prefix + "SL", OBJPROP_SELECTABLE, false);

   // TP2 line
   ObjectDelete(0, prefix + "TP");
   ObjectCreate(0, prefix + "TP", OBJ_TREND, 0, t, tp2, expTime, tp2);
   ObjectSetInteger(0, prefix + "TP", OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, prefix + "TP", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, prefix + "TP", OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, prefix + "TP", OBJPROP_RAY, false);
   ObjectSetInteger(0, prefix + "TP", OBJPROP_SELECTABLE, false);

   // Text Tag
   string txt = (dir == 1) ? "🚀 BUY (A+ " : "🔻 SELL (A+ ";
   txt += DoubleToString(score, 0) + "%) | SL: " + DoubleToString(sl, Digits) + " | TP: " + DoubleToString(tp2, Digits);
   ObjectDelete(0, prefix + "TAG");
   ObjectCreate(0, prefix + "TAG", OBJ_TEXT, 0, t, (dir == 1) ? (entry + (10 * Point)) : (entry - (10 * Point)));
   ObjectSetString(0, prefix + "TAG", OBJPROP_TEXT, txt);
   ObjectSetString(0, prefix + "TAG", OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, prefix + "TAG", OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, prefix + "TAG", OBJPROP_COLOR, (dir == 1) ? clrLime : clrDeepPink);
   ObjectSetInteger(0, prefix + "TAG", OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Emit Push, Popup, Sound & Email Signal Alerts                    |
//+------------------------------------------------------------------+
void EmitSignalAlert(int dir, double score, double entry, double sl, double tp1, double tp2, double lots, string reasons)
{
   string signalType = (dir == 1) ? "BUY (LONG)" : "SELL (SHORT)";
   string gradeStr = (score >= 80) ? "INSTITUTIONAL A+ GRADE 🔥" : "GRADE B SETUP";

   string msg = StringFormat("[PROP FIRM EDGE] %s %s\nPair: %s [%s]\nConfluence: %.0f%%\nEntry: %s\nStopLoss: %s\nTP1: %s\nTP2: %s\nSizing (0.5%% Risk): %s Lots\nRules: %s",
                             gradeStr, signalType, Symbol(), PeriodToStr(), score,
                             DoubleToString(entry, Digits), DoubleToString(sl, Digits),
                             DoubleToString(tp1, Digits), DoubleToString(tp2, Digits),
                             DoubleToString(lots, 2), reasons);

   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound("alert.wav");
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("Prop Firm Institutional Signal: " + Symbol(), msg);
}

//+------------------------------------------------------------------+
//| General trigger alert for key SMC events                         |
//+------------------------------------------------------------------+
void TriggerAlert(string text)
{
   if(TimeCurrent() - g_lastAlertTime < 60) return;
   g_lastAlertTime = TimeCurrent();

   if(InpAlertSound) PlaySound("tick.wav");
}

//+------------------------------------------------------------------+
//| 7. RENDER PROP FIRM DRAWDOWN & CAPITAL PROTECTION HUD            |
//+------------------------------------------------------------------+
void RenderPropFirmHUD()
{
   PropFirmRiskState rs;
   rs.initialBalance = AccountBalance();
   rs.dayStartEquity = g_dayStartEquity;
   rs.currentBalance = AccountBalance();
   rs.currentEquity = AccountEquity();
   rs.floatingPnL = rs.currentEquity - rs.currentBalance;
   rs.peakEquity = g_peakEquity;

   double dailyLossCash = rs.dayStartEquity - rs.currentEquity;
   if(dailyLossCash < 0) dailyLossCash = 0;
   rs.todayDrawdownPct = (rs.dayStartEquity > 0) ? (dailyLossCash / rs.dayStartEquity * 100.0) : 0.0;
   rs.maxDailyDrawdownPct = InpMaxDailyDrawdownPct;
   rs.remainingDailyLossPct = rs.maxDailyDrawdownPct - rs.todayDrawdownPct;
   if(rs.remainingDailyLossPct < 0) rs.remainingDailyLossPct = 0;
   rs.remainingDailyLossCash = (rs.remainingDailyLossPct / 100.0) * rs.dayStartEquity;

   double overallLossCash = rs.peakEquity - rs.currentEquity;
   if(overallLossCash < 0) overallLossCash = 0;
   rs.overallDrawdownPct = (rs.peakEquity > 0) ? (overallLossCash / rs.peakEquity * 100.0) : 0.0;
   rs.maxOverallDrawdownPct = InpMaxOverallDrawdownPct;
   rs.remainingOverallLossPct = rs.maxOverallDrawdownPct - rs.overallDrawdownPct;
   if(rs.remainingOverallLossPct < 0) rs.remainingOverallLossPct = 0;
   rs.remainingOverallLossCash = (rs.remainingOverallLossPct / 100.0) * rs.peakEquity;

   rs.profitTargetPct = InpProfitTargetPct;
   double currentGainCash = rs.currentEquity - rs.dayStartEquity;
   rs.currentProfitPct = (rs.dayStartEquity > 0) ? (currentGainCash / rs.dayStartEquity * 100.0) : 0.0;

   if(rs.todayDrawdownPct >= (InpMaxDailyDrawdownPct * 0.70) && !g_dailyWarningSent && InpAlertDailyLossWarning)
   {
      g_dailyWarningSent = true;
      string warn = StringFormat("⚠️ PROP FIRM DRAWDOWN WARNING! Daily Loss is at %.2f%% (Limit: %.2f%%). Remaining Buffer: $%.2f. STOP TRADING TO PROTECT ACCOUNT!",
                                 rs.todayDrawdownPct, InpMaxDailyDrawdownPct, rs.remainingDailyLossCash);
      Alert(warn);
      SendNotification(warn);
   }

   color bgBox = C'15,20,28';
   color borderBox = C'40,55,75';
   color textPrimary = clrWhite;
   color textSecondary = clrLightSteelBlue;
   color colGreen = C'0,230,120';
   color colRed = C'255,75,90';
   color colOrange = C'255,170,0';
   color colCyan = C'0,220,255';

   if(InpDashboardTheme == THEME_BLOOMBERG_TERMINAL)
   {
      bgBox = C'18,18,18';
      borderBox = C'200,130,0';
      textPrimary = clrGold;
      textSecondary = clrOrange;
      colCyan = clrYellow;
   }
   else if(InpDashboardTheme == THEME_CYBER_MATRIX)
   {
      bgBox = C'10,12,20';
      borderBox = clrDarkViolet;
      textPrimary = clrAqua;
      textSecondary = clrMagenta;
      colCyan = clrMagenta;
   }

   int x = InpDashboardX;
   int y = InpDashboardY;
   int width = 310;
   int height = 295;

   CreateHUDPanel("BG", x, y, width, height, bgBox, borderBox);

   string propFirmName = "FTMO";
   if(InpPropFirmProfile == PROPFIRM_FUNDEDNEXT) propFirmName = "FUNDEDNEXT";
   else if(InpPropFirmProfile == PROPFIRM_THE5ERS) propFirmName = "THE 5%ERS";
   else if(InpPropFirmProfile == PROPFIRM_TOPSTEP) propFirmName = "TOPSTEP";
   else if(InpPropFirmProfile == PROPFIRM_ALPHA_CAPITAL) propFirmName = "ALPHA CAPITAL";
   else if(InpPropFirmProfile == PROPFIRM_CUSTOM) propFirmName = "PROP FIRM PRO";

   CreateHUDLabel("TITLE", x + 12, y + 10, "⚡ " + propFirmName + " RISK & EDGE DASHBOARD", "Segoe UI Bold", 9, colCyan);

   CreateHUDLabel("L_BAL", x + 12, y + 34, "Account Balance:", "Segoe UI", 8, textSecondary);
   CreateHUDLabel("V_BAL", x + 120, y + 34, "$" + DoubleToString(rs.currentBalance, 2), "Segoe UI Bold", 8, textPrimary);

   CreateHUDLabel("L_EQUITY", x + 12, y + 50, "Floating Equity:", "Segoe UI", 8, textSecondary);
   color eqColor = (rs.floatingPnL >= 0) ? colGreen : colRed;
   string pnlSign = (rs.floatingPnL >= 0) ? "+$" : "-$";
   CreateHUDLabel("V_EQUITY", x + 120, y + 50, "$" + DoubleToString(rs.currentEquity, 2) + " (" + pnlSign + DoubleToString(MathAbs(rs.floatingPnL), 2) + ")", "Segoe UI Bold", 8, eqColor);

   CreateHUDLabel("L_DDD", x + 12, y + 74, "Daily DD Limit (" + DoubleToString(InpMaxDailyDrawdownPct, 1) + "%):", "Segoe UI", 8, textSecondary);
   color ddColor = (rs.todayDrawdownPct < InpMaxDailyDrawdownPct * 0.5) ? colGreen : ((rs.todayDrawdownPct < InpMaxDailyDrawdownPct * 0.75) ? colOrange : colRed);
   CreateHUDLabel("V_DDD", x + 160, y + 74, DoubleToString(rs.todayDrawdownPct, 2) + "% / " + DoubleToString(InpMaxDailyDrawdownPct, 1) + "%", "Segoe UI Bold", 8, ddColor);

   CreateHUDLabel("L_DBUF", x + 12, y + 90, "Daily Loss Buffer Left:", "Segoe UI", 8, textSecondary);
   CreateHUDLabel("V_DBUF", x + 160, y + 90, "$" + DoubleToString(rs.remainingDailyLossCash, 2) + " (" + DoubleToString(rs.remainingDailyLossPct, 2) + "%)", "Segoe UI Bold", 8, ddColor);

   CreateHUDLabel("L_MDD", x + 12, y + 114, "Max DD Limit (" + DoubleToString(InpMaxOverallDrawdownPct, 1) + "%):", "Segoe UI", 8, textSecondary);
   color mddColor = (rs.overallDrawdownPct < InpMaxOverallDrawdownPct * 0.5) ? colGreen : ((rs.overallDrawdownPct < InpMaxOverallDrawdownPct * 0.75) ? colOrange : colRed);
   CreateHUDLabel("V_MDD", x + 160, y + 114, DoubleToString(rs.overallDrawdownPct, 2) + "% / " + DoubleToString(InpMaxOverallDrawdownPct, 1) + "%", "Segoe UI Bold", 8, mddColor);

   CreateHUDLabel("L_MBUF", x + 12, y + 130, "Max Loss Buffer Left:", "Segoe UI", 8, textSecondary);
   CreateHUDLabel("V_MBUF", x + 160, y + 130, "$" + DoubleToString(rs.remainingOverallLossCash, 2) + " (" + DoubleToString(rs.remainingOverallLossPct, 2) + "%)", "Segoe UI Bold", 8, mddColor);

   CreateHUDLabel("L_TGT", x + 12, y + 154, "Target Progress (" + DoubleToString(InpProfitTargetPct, 1) + "%):", "Segoe UI", 8, textSecondary);
   color tgtColor = (rs.currentProfitPct >= 0) ? colGreen : colOrange;
   CreateHUDLabel("V_TGT", x + 160, y + 154, DoubleToString(rs.currentProfitPct, 2) + "% (" + DoubleToString(MathMin(100.0, (rs.currentProfitPct / InpProfitTargetPct) * 100.0), 1) + "% Done)", "Segoe UI Bold", 8, tgtColor);

   double sampleSLPips = 15.0;
   double calcLots05 = CalculatePropFirmLotSize(sampleSLPips, InpRiskPerTradePct);
   CreateHUDLabel("L_RISK", x + 12, y + 180, "Institutional Risk Sizing:", "Segoe UI Bold", 8, colCyan);
   CreateHUDLabel("V_RISK", x + 12, y + 196, "Risk: " + DoubleToString(InpRiskPerTradePct, 1) + "% ($" + DoubleToString(rs.currentEquity * (InpRiskPerTradePct / 100.0), 2) + ") | 15p SL = " + DoubleToString(calcLots05, 2) + " Lots", "Segoe UI", 8, textPrimary);

   string smcStatus = "WAITING FOR A+ CONFLUENCE";
   color smcCol = clrLightSteelBlue;
   if(g_lastSignalBar > 0 && (TimeCurrent() - g_lastSignalBar < PeriodSeconds() * 5))
   {
      smcStatus = "🔥 ACTIVE INSTITUTIONAL SETUP";
      smcCol = colGreen;
   }
   CreateHUDLabel("L_SMC", x + 12, y + 224, "SMC Engine: " + smcStatus, "Segoe UI Bold", 8, smcCol);

   string statusText = "● ACCOUNT SAFE - TRADING PERMITTED";
   color statusColor = colGreen;
   if(rs.todayDrawdownPct >= InpMaxDailyDrawdownPct * 0.70)
   {
      statusText = "⚠️ DAILY LOSS WARNING (REDUCE RISK)";
      statusColor = colOrange;
   }
   if(rs.todayDrawdownPct >= InpMaxDailyDrawdownPct * 0.95 || rs.overallDrawdownPct >= InpMaxOverallDrawdownPct * 0.95)
   {
      statusText = "🛑 HARD STOP: DRAWDOWN LIMIT REACHED";
      statusColor = colRed;
   }

   CreateHUDPanel("STATUS_BG", x + 10, y + 250, width - 20, 30, C'25,32,45', borderBox);
   CreateHUDLabel("STATUS_TXT", x + 18, y + 258, statusText, "Segoe UI Bold", 8, statusColor);
}

//+------------------------------------------------------------------+
//| HUD Helper: Create or Update GUI Label                           |
//+------------------------------------------------------------------+
void CreateHUDLabel(string subName, int x, int y, string text, string font, int fontSize, color clr)
{
   string name = PREFIX + "HUD_" + subName;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| HUD Helper: Create or Update GUI Background Panel Rectangle      |
//+------------------------------------------------------------------+
void CreateHUDPanel(string subName, int x, int y, int w, int h, color bgColor, color borderColor)
{
   string name = PREFIX + "HUD_PNL_" + subName;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

//+------------------------------------------------------------------+
//| Helper: Period to String representation                          |
//+------------------------------------------------------------------+
string PeriodToStr()
{
   switch(Period())
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
      default:         return(IntegerToString(Period()));
   }
}
