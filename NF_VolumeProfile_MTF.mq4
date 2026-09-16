//+------------------------------------------------------------------+
//|                                         NF_VolumeProfile_MTF.mq4 |
//|                                NF Trades Strategy Implementation |
//|                 Institutional Auction Market Theory Trading Suite|
//|               Session | Daily | Weekly | Monthly | Naked POCs    |
//|               + Dynamic SL/TP Trade Plans + Confluence Star Matrix|
//|               + LVN/HVN Detection + Session Kill Zone Filter      |
//+------------------------------------------------------------------+
#property copyright   "NF Trades Strategy - MTF Volume Profile"
#property link        "https://www.youtube.com/@NFTradesreal"
#property version     "2.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 18
#property indicator_plots   18

//--- Buffer Plot Definitions for EA Integration & Chart Visualization
#property indicator_label1  "Daily POC"
#property indicator_type1   DRAW_NONE
#property indicator_color1  clrDarkOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Daily VAH"
#property indicator_type2   DRAW_NONE
#property indicator_color2  clrCoral
#property indicator_style2  STYLE_DASH
#property indicator_width2  1

#property indicator_label3  "Daily VAL"
#property indicator_type3   DRAW_NONE
#property indicator_color3  clrCoral
#property indicator_style3  STYLE_DASH
#property indicator_width3  1

#property indicator_label4  "Weekly POC"
#property indicator_type4   DRAW_NONE
#property indicator_color4  clrDodgerBlue
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

#property indicator_label5  "Weekly VAH"
#property indicator_type5   DRAW_NONE
#property indicator_color5  clrDeepSkyBlue
#property indicator_style5  STYLE_DASH
#property indicator_width5  1

#property indicator_label6  "Weekly VAL"
#property indicator_type6   DRAW_NONE
#property indicator_color6  clrDeepSkyBlue
#property indicator_style6  STYLE_DASH
#property indicator_width6  1

#property indicator_label7  "Monthly POC"
#property indicator_type7   DRAW_NONE
#property indicator_color7  clrMagenta
#property indicator_style7  STYLE_SOLID
#property indicator_width7  2

#property indicator_label8  "Monthly VAH"
#property indicator_type8   DRAW_NONE
#property indicator_color8  clrViolet
#property indicator_style8  STYLE_DASH
#property indicator_width8  1

#property indicator_label9  "Monthly VAL"
#property indicator_type9   DRAW_NONE
#property indicator_color9  clrViolet
#property indicator_style9  STYLE_DASH
#property indicator_width9  1

#property indicator_label10 "Session POC"
#property indicator_type10  DRAW_NONE
#property indicator_color10 clrGold
#property indicator_style10 STYLE_SOLID
#property indicator_width10 2

#property indicator_label11 "Session VAH"
#property indicator_type11  DRAW_NONE
#property indicator_color11 clrYellow
#property indicator_style11 STYLE_DASH
#property indicator_width11 1

#property indicator_label12 "Session VAL"
#property indicator_type12  DRAW_NONE
#property indicator_color12 clrYellow
#property indicator_style12 STYLE_DASH
#property indicator_width12 1

#property indicator_label13 "AMT Buy Signal"
#property indicator_type13  DRAW_ARROW
#property indicator_color13 clrLime
#property indicator_width13 2

#property indicator_label14 "AMT Sell Signal"
#property indicator_type14  DRAW_ARROW
#property indicator_color14 clrRed
#property indicator_width14 2

#property indicator_label15 "Trade Plan SL"
#property indicator_type15  DRAW_NONE
#property indicator_color15 clrRed
#property indicator_style15 STYLE_DOT
#property indicator_width15 1

#property indicator_label16 "Trade Plan TP1"
#property indicator_type16  DRAW_NONE
#property indicator_color16 clrGold
#property indicator_style16 STYLE_DOT
#property indicator_width16 1

#property indicator_label17 "Trade Plan TP2"
#property indicator_type17  DRAW_NONE
#property indicator_color17 clrLime
#property indicator_style17 STYLE_DOT
#property indicator_width17 1

#property indicator_label18 "Active Naked POC"
#property indicator_type18  DRAW_NONE
#property indicator_color18 clrDarkOrange
#property indicator_style18 STYLE_DOT
#property indicator_width18 1

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_STEP_MODE
{
   STEP_DYNAMIC_ROWS, // Dynamic Rows (e.g. 200 Rows as in Video)
   STEP_FIXED_POINTS  // Fixed Step in Points
};

enum ENUM_SESSION_MODE
{
   SESSION_AUTO_BROKER,   // Auto / Broker Daily (Standard 5 PM NY Close)
   SESSION_NY_GLOBEX_1800 // Exact 18:00 NY CME Globex Open
};

enum ENUM_HIST_ALIGN
{
   HIST_ALIGN_SESSION_START, // Left Side of Session
   HIST_ALIGN_CHART_RIGHT    // Right Side of Current Chart
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
//--- 1. PROFILE CALCULATION SETTINGS
input string               InpSection1             = "=== PROFILE SETTINGS ==="; // ---
input ENUM_STEP_MODE       InpStepMode             = STEP_DYNAMIC_ROWS;          // Step Calculation Mode
input int                  InpNumberOfRows         = 200;                        // Number of Rows (TradingView Default: 200)
input int                  InpFixedPoints          = 20;                         // Fixed Step in Points (if Fixed Points selected)
input double               InpValueAreaPercent     = 70.0;                       // Value Area Percentage (Dalton AMT: 70%)

//--- 2. SESSION & TIMEZONE ALIGNMENT
input string               InpSection2             = "=== TIMEZONE & SESSION ==="; // ---
input ENUM_SESSION_MODE    InpSessionMode          = SESSION_AUTO_BROKER;        // Session Rollover Mode
input int                  InpBrokerGMTOffset      = 2;                          // Broker Winter GMT Offset (e.g. +2 for EET)
input bool                 InpAutoNY_DST           = true;                       // Auto-Detect US/NY Daylight Saving Time
input int                  InpNYGMTOffset          = -5;                         // Manual NY GMT Offset (if Auto-DST disabled)
input int                  InpNYSessionStartHour   = 18;                         // CME Globex Day Start Hour (18:00 NY)

//--- 3. MULTI-TIMEFRAME LEVEL VISIBILITY
input string               InpSection3             = "=== TIMEFRAME LEVELS ==="; // ---
input bool                 InpShowSession          = true;                       // Show Current Session Levels (S-POC, S-VAH, S-VAL)
input bool                 InpShowDaily            = true;                       // Show Previous Day Levels (D-POC, D-VAH, D-VAL)
input bool                 InpShowWeekly           = true;                       // Show Previous Week Levels (W-POC, W-VAH, W-VAL)
input bool                 InpShowMonthly          = true;                       // Show Previous Month Levels (M-POC, M-VAH, M-VAL)
input bool                 InpExtendRay            = false;                      // Extend Lines as Infinite Ray to Right
input int                  InpExtendBars           = 80;                         // Extension Length in Bars (if Ray is False)

//--- 4. NAKED / VIRGIN POC (vPOC) TRACKING
input string               InpSection4             = "=== VIRGIN / NAKED POCS ==="; // ---
input bool                 InpShowVPOC             = true;                       // Track Untested Virgin POCs (vPOC / nPOC)
input int                  InpNumVPOCDays          = 5;                          // Track Last N Daily Naked POCs
input int                  InpNumVPOCWeeks         = 3;                          // Track Last N Weekly Naked POCs
input color                InpColorVPOCDaily       = clrDarkOrange;              // Naked Daily POC Color
input color                InpColorVPOCWeekly      = clrDodgerBlue;              // Naked Weekly POC Color

//--- 5. COLORS & STYLES
input string               InpSection5             = "=== COLORS & STYLES ==="; // ---
input color                InpColorSessionPOC      = clrGold;                    // Session POC Color
input color                InpColorSessionVA       = clrYellow;                  // Session VAH / VAL Color
input color                InpColorDailyPOC        = clrDarkOrange;              // Previous Day POC Color
input color                InpColorDailyVA         = clrCoral;                   // Previous Day VAH / VAL Color
input color                InpColorWeeklyPOC       = clrDodgerBlue;              // Previous Week POC Color
input color                InpColorWeeklyVA        = clrDeepSkyBlue;             // Previous Week VAH / VAL Color
input color                InpColorMonthlyPOC      = clrMagenta;                 // Previous Month POC Color
input color                InpColorMonthlyVA       = clrViolet;                  // Previous Month VAH / VAL Color
input int                  InpLineWidthPOC         = 2;                          // POC Line Thickness
input int                  InpLineWidthVA          = 1;                          // VAH / VAL Line Thickness
input ENUM_LINE_STYLE      InpLineStyleVA          = STYLE_DASH;                 // VAH / VAL Line Style

//--- 6. VISUAL SESSION HISTOGRAM
input string               InpSection6             = "=== VISUAL HISTOGRAM ==="; // ---
input bool                 InpDrawHistogram        = true;                       // Draw Session Volume Profile Histogram
input ENUM_HIST_ALIGN      InpHistAlignment        = HIST_ALIGN_SESSION_START;   // Histogram Alignment
input int                  InpMaxHistWidthBars     = 40;                         // Max Histogram Width in Bars
input color                InpHistColorPOC         = clrGold;                    // Histogram POC Bar Color
input color                InpHistColorVA          = C'40,90,160';               // Histogram Inside Value Area Color
input color                InpHistColorOutside     = C'60,70,85';                // Histogram Outside Value Area Color

//--- 7. CONFLUENCE ENGINE & STAR RATINGS
input string               InpSection7             = "=== CONFLUENCE & RATINGS ==="; // ---
input bool                 InpEnableConfluence     = true;                       // Enable MTF Confluence Detection
input double               InpConfluenceThreshold  = 5.0;                        // Max Confluence Distance (in Pips / Ticks)
input color                InpConfluenceColor      = clrLimeGreen;               // Confluent Level Highlight Color
input bool                 InpEnableAlerts         = true;                       // Enable Alert on Confluence Test
input bool                 InpAlertPopup           = true;                       // Confluence Screen Pop-up Alert
input bool                 InpAlertSound           = true;                       // Confluence Sound Alert

//--- 8. INSTITUTIONAL KILL ZONE FILTER
input string               InpSection8             = "=== TIME & KILL ZONES ==="; // ---
input bool                 InpUseKillZones         = false;                      // Filter Entry Signs by Institutional Kill Zones
input bool                 InpTradeLondonOpen      = true;                       // London Open (03:00 - 06:00 NY)
input bool                 InpTradeNYOpen          = true;                       // NY Cash Open (09:30 - 11:30 NY)
input bool                 InpTradeNYAfternoon     = true;                       // NY Afternoon Rotation (13:30 - 15:30 NY)

//--- 9. ENTRY SIGNALS & ARROWS
input string               InpSection9             = "=== ENTRY SIGNALS (SIGNS) ==="; // ---
input bool                 InpShowEntrySignals     = true;                       // Enable Buy/Sell Entry Signs (Arrows)
input bool                 InpSignalValVahRotate   = true;                       // Setup 1: Value Area Extreme Rotation
input bool                 InpSignalImbalanceRetest= true;                       // Setup 2: Imbalance Retest (Breakout Flip)
input bool                 InpSignalConfluence     = true;                       // Setup 3: MTF Confluence Bounce
input double               InpSignalTolerancePips  = 3.0;                        // Price Proximity Tolerance (Pips/Ticks)
input int                  InpSignalScanBars       = 300;                        // Historical Bars to Scan on Startup
input color                InpColorBuySignal       = clrLime;                    // Buy Arrow Color
input color                InpColorSellSignal      = clrRed;                     // Sell Arrow Color
input int                  InpArrowCodeBuy         = 233;                        // Wingdings Arrow Code (233 = Up Arrow)
input int                  InpArrowCodeSell        = 234;                        // Wingdings Arrow Code (234 = Down Arrow)
input int                  InpArrowSize            = 2;                          // Arrow Size
input double               InpArrowOffsetPips      = 5.0;                        // Distance from Candle Wick (Pips)
input bool                 InpSignalAlert          = true;                       // Sound & Pop-up Alert on Entry Sign
input bool                 InpSignalPushNotify     = false;                      // Send Mobile Push Notification
input string               InpSoundFile            = "alert.wav";                // Alert Sound File

//--- 10. DYNAMIC SL / TP & RISK-REWARD TRADE PLAN
input string               InpSection10            = "=== DYNAMIC SL / TP PLAN ==="; // ---
input bool                 InpShowTradePlan        = true;                       // Project Dynamic Entry, SL, TP1, TP2 & R:R Box
input double               InpSLBufferPips         = 2.0;                        // Extra Buffer beyond Rejection Wick/LVN (Pips)
input int                  InpTradePlanBars        = 50;                         // Trade Plan Projection Length (Bars)
input color                InpColorPlanEntry       = clrCyan;                    // Trade Plan Entry Line Color
input color                InpColorPlanSL          = clrRed;                     // Trade Plan Stop Loss Line Color
input color                InpColorPlanTP1         = clrGold;                    // Trade Plan TP1 (50% Scale-Out) Color
input color                InpColorPlanTP2         = clrLime;                    // Trade Plan TP2 (Final Runner) Color

//--- 11. AMT ON-SCREEN DASHBOARD
input string               InpSection11            = "=== AMT DASHBOARD ===";    // ---
input bool                 InpShowDashboard        = true;                       // Display AMT Heads-Up Display (HUD)
input ENUM_BASE_CORNER     InpDashCorner           = CORNER_RIGHT_UPPER;         // Dashboard Corner
input int                  InpDashX                = 20;                         // Dashboard X Position (Pixels)
input int                  InpDashY                = 30;                         // Dashboard Y Position (Pixels)

//+------------------------------------------------------------------+
//| Global Constants & Variables                                     |
//+------------------------------------------------------------------+
#define PREFIX "VP_NF_"
#define MAX_BINS 1000

//--- Indicator Buffers (Accessible by EAs via iCustom)
double buf_DailyPOC[];
double buf_DailyVAH[];
double buf_DailyVAL[];
double buf_WeeklyPOC[];
double buf_WeeklyVAH[];
double buf_WeeklyVAL[];
double buf_MonthlyPOC[];
double buf_MonthlyVAH[];
double buf_MonthlyVAL[];
double buf_SessionPOC[];
double buf_SessionVAH[];
double buf_SessionVAL[];
double buf_SignalBuy[];
double buf_SignalSell[];
double buf_TradePlanSL[];
double buf_TradePlanTP1[];
double buf_TradePlanTP2[];
double buf_ActiveVPOC[];

//--- Profile Result Structure
struct SProfileResult
{
   double   poc;
   double   vah;
   double   val;
   double   high;
   double   low;
   double   lvnUpper;
   double   lvnLower;
   long     totalVol;
   int      pocBin;
   int      vahBin;
   int      valBin;
   int      numBins;
   double   step;
   datetime startTime;
   datetime endTime;
   bool     isValid;
};

//--- Confluence Pair Structure
struct SConfluence
{
   string   name1;
   string   name2;
   double   price1;
   double   price2;
   double   midPrice;
   double   diffPips;
   int      stars;
   string   ratingStr;
};

//--- Virgin / Naked POC Structure
struct SVPOC
{
   double   price;
   datetime startTime;
   datetime endTime;
   datetime mitigationTime;
   bool     isMitigated;
   bool     isWeekly;
   int      dayIndex;
};

//--- Trade Plan Structure
struct STradePlan
{
   string   direction;
   double   entryPrice;
   double   slPrice;
   double   tp1Price;
   double   tp2Price;
   double   riskPips;
   double   reward1Pips;
   double   reward2Pips;
   double   rr1;
   double   rr2;
   datetime signalTime;
   string   setupName;
   bool     isActive;
};

//--- Cached Profile Data
SProfileResult g_profSession;
SProfileResult g_profDaily;
SProfileResult g_profWeekly;
SProfileResult g_profMonthly;

//--- Confluence List
SConfluence    g_confluences[];

//--- Virgin POC List
SVPOC          g_vpocs[];

//--- Latest Active Trade Plan
STradePlan     g_activePlan;

//--- State tracking
datetime g_lastBarTime         = 0;
datetime g_lastDayTime         = 0;
datetime g_lastWeekTime        = 0;
datetime g_lastMonthTime       = 0;
datetime g_lastAlertTime       = 0;
datetime g_lastSignalAlertTime = 0;
int      g_lastHistBarCount    = 0;
string   g_lastSignalType      = "NONE";
double   g_lastSignalPrice     = 0.0;
string   g_lastSignalDesc      = "Waiting for Setup...";

//+------------------------------------------------------------------+
//| Helper: Get Standard Pip Size                                    |
//+------------------------------------------------------------------+
double GetPipSize()
{
   if(Digits == 3 || Digits == 5) return(Point * 10.0);
   return(Point);
}

//+------------------------------------------------------------------+
//| Helper: Get Bar Volume across timeframes in MT4                  |
//+------------------------------------------------------------------+
long GetBarVolume(string sym, ENUM_TIMEFRAMES tf, int shift)
{
   long bVol = iVolume(sym, tf, shift);
   if(bVol <= 0) bVol = 1;
   return(bVol);
}

//+------------------------------------------------------------------+
//| Custom Indicator Initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Bind Buffers
   SetIndexBuffer(0,  buf_DailyPOC);
   SetIndexBuffer(1,  buf_DailyVAH);
   SetIndexBuffer(2,  buf_DailyVAL);
   SetIndexBuffer(3,  buf_WeeklyPOC);
   SetIndexBuffer(4,  buf_WeeklyVAH);
   SetIndexBuffer(5,  buf_WeeklyVAL);
   SetIndexBuffer(6,  buf_MonthlyPOC);
   SetIndexBuffer(7,  buf_MonthlyVAH);
   SetIndexBuffer(8,  buf_MonthlyVAL);
   SetIndexBuffer(9,  buf_SessionPOC);
   SetIndexBuffer(10, buf_SessionVAH);
   SetIndexBuffer(11, buf_SessionVAL);
   SetIndexBuffer(12, buf_SignalBuy);
   SetIndexBuffer(13, buf_SignalSell);
   SetIndexBuffer(14, buf_TradePlanSL);
   SetIndexBuffer(15, buf_TradePlanTP1);
   SetIndexBuffer(16, buf_TradePlanTP2);
   SetIndexBuffer(17, buf_ActiveVPOC);

   //--- Configure Profile Level Buffers
   for(int i = 0; i < 12; i++)
   {
      SetIndexStyle(i, DRAW_NONE);
      SetIndexEmptyValue(i, 0.0);
   }

   //--- Configure Entry Sign Buffers (Visible Arrows on Chart)
   SetIndexStyle(12, DRAW_ARROW, EMPTY, InpArrowSize, InpColorBuySignal);
   SetIndexArrow(12, InpArrowCodeBuy);
   SetIndexEmptyValue(12, 0.0);
   SetIndexLabel(12, "AMT Buy Signal");

   SetIndexStyle(13, DRAW_ARROW, EMPTY, InpArrowSize, InpColorSellSignal);
   SetIndexArrow(13, InpArrowCodeSell);
   SetIndexEmptyValue(13, 0.0);
   SetIndexLabel(13, "AMT Sell Signal");

   //--- Configure EA Trade Plan & VPOC Buffers
   for(int i = 14; i < 18; i++)
   {
      SetIndexStyle(i, DRAW_NONE);
      SetIndexEmptyValue(i, 0.0);
   }
   SetIndexLabel(14, "Trade Plan SL");
   SetIndexLabel(15, "Trade Plan TP1");
   SetIndexLabel(16, "Trade Plan TP2");
   SetIndexLabel(17, "Active Naked POC");

   //--- Set Indicator Short Name
   string shortName = "NF_VolumeProfile_MTF (" + Symbol() + ")";
   IndicatorShortName(shortName);

   //--- Clean any old artifacts
   CleanupObjects();

   //--- Reset tracking variables
   g_lastBarTime         = 0;
   g_lastDayTime         = 0;
   g_lastWeekTime        = 0;
   g_lastMonthTime       = 0;
   g_lastAlertTime       = 0;
   g_lastSignalAlertTime = 0;
   g_lastHistBarCount    = 0;
   g_lastSignalType      = "NONE";
   g_lastSignalPrice     = 0.0;
   g_lastSignalDesc      = "Waiting for Setup...";
   g_activePlan.isActive = false;

   //--- Force initial calculation
   CalculateAllProfiles(true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom Indicator Deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupObjects();
   Comment("");
}

//+------------------------------------------------------------------+
//| Cleanup Chart Objects                                            |
//+------------------------------------------------------------------+
void CleanupObjects()
{
   ObjectsDeleteAll(0, PREFIX);
}

//+------------------------------------------------------------------+
//| Forward Declarations                                             |
//+------------------------------------------------------------------+
void CalculateMonthlyProfile();
void CalculateWeeklyProfile();
void CalculateDailyProfile();
void CalculateSessionProfile();
void CalculateAllProfiles(bool force);
void CalculateNakedPOCs();
void DetectConfluences();
void DrawAllLevels();
void DrawSessionHistogram();
void DrawVPOCLines();
void DrawTradePlan();
void PopulateBuffers(int rates_total);
void EvaluateEntrySignals(int rates_total, int prev_calculated);
void UpdateDashboard();
void CheckConfluenceAlerts();
bool IsInKillZone(datetime time);

//+------------------------------------------------------------------+
//| Custom Indicator Iteration                                       |
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
   if(rates_total < 10) return(0);

   datetime currentBarTime   = Time[0];
   datetime currentDayTime   = iTime(Symbol(), PERIOD_D1, 0);
   datetime currentWeekTime  = iTime(Symbol(), PERIOD_W1, 0);
   datetime currentMonthTime = iTime(Symbol(), PERIOD_MN1, 0);

   bool needFullRecalc = (prev_calculated == 0);

   //--- Check for Monthly Rollover
   if(currentMonthTime != g_lastMonthTime || needFullRecalc)
   {
      CalculateMonthlyProfile();
      g_lastMonthTime = currentMonthTime;
   }

   //--- Check for Weekly Rollover
   if(currentWeekTime != g_lastWeekTime || needFullRecalc)
   {
      CalculateWeeklyProfile();
      g_lastWeekTime = currentWeekTime;
   }

   //--- Check for Daily Rollover
   if(currentDayTime != g_lastDayTime || needFullRecalc)
   {
      CalculateDailyProfile();
      if(InpShowVPOC) CalculateNakedPOCs();
      g_lastDayTime = currentDayTime;
   }

   //--- Recalculate Current Session on new bar (or init)
   if(currentBarTime != g_lastBarTime || needFullRecalc)
   {
      CalculateSessionProfile();
      DetectConfluences();
      DrawAllLevels();
      if(InpShowVPOC) DrawVPOCLines();
      if(InpDrawHistogram) DrawSessionHistogram();
      g_lastBarTime = currentBarTime;
   }

   //--- Update Buffer Values for EA access
   PopulateBuffers(rates_total);

   //--- Evaluate Entry Signs (Rejections, Retests, Confluences)
   if(InpShowEntrySignals)
   {
      EvaluateEntrySignals(rates_total, prev_calculated);
   }

   //--- Update Dynamic Trade Plan Lines
   if(InpShowTradePlan && g_activePlan.isActive)
   {
      DrawTradePlan();
   }

   //--- Update Real-time AMT Dashboard
   if(InpShowDashboard)
   {
      UpdateDashboard();
   }

   //--- Check Confluence Alerts
   if(InpEnableAlerts && InpEnableConfluence)
   {
      CheckConfluenceAlerts();
   }

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Compute Daylight Saving Offset for New York                      |
//+------------------------------------------------------------------+
int GetNYGMTOffset(datetime time)
{
   if(!InpAutoNY_DST) return(InpNYGMTOffset);

   MqlDateTime dt;
   TimeToStruct(time, dt);

   if(dt.mon < 3 || dt.mon > 11) return(-5); // Winter: EST
   if(dt.mon > 3 && dt.mon < 11) return(-4); // Summer: EDT

   if(dt.mon == 3)
   {
      MqlDateTime m1;
      ZeroMemory(m1);
      m1.year = dt.year; m1.mon = 3; m1.day = 1; m1.hour = 0; m1.min = 0; m1.sec = 0;
      datetime tm1 = StructToTime(m1);
      TimeToStruct(tm1, m1);
      int firstSunOffset = (7 - m1.day_of_week) % 7;
      int secondSunDay = 1 + firstSunOffset + 7;
      if(dt.day > secondSunDay || (dt.day == secondSunDay && dt.hour >= 2)) return(-4);
      return(-5);
   }

   if(dt.mon == 11)
   {
      MqlDateTime n1;
      ZeroMemory(n1);
      n1.year = dt.year; n1.mon = 11; n1.day = 1; n1.hour = 0; n1.min = 0; n1.sec = 0;
      datetime tn1 = StructToTime(n1);
      TimeToStruct(tn1, n1);
      int firstSunOffset = (7 - n1.day_of_week) % 7;
      int firstSunDay = 1 + firstSunOffset;
      if(dt.day < firstSunDay || (dt.day == firstSunDay && dt.hour < 2)) return(-4);
      return(-5);
   }

   return(-5);
}

//+------------------------------------------------------------------+
//| Convert NY Time to Broker Server Time                            |
//+------------------------------------------------------------------+
datetime NYTimeToBrokerTime(datetime nyTime)
{
   int nyOffset = GetNYGMTOffset(nyTime);
   int shiftHours = InpBrokerGMTOffset - nyOffset;
   return(nyTime + shiftHours * 3600);
}

//+------------------------------------------------------------------+
//| Convert Broker Server Time to NY Time                            |
//+------------------------------------------------------------------+
datetime BrokerTimeToNYTime(datetime brokerTime)
{
   int nyOffset = GetNYGMTOffset(brokerTime);
   int shiftHours = InpBrokerGMTOffset - nyOffset;
   return(brokerTime - shiftHours * 3600);
}

//+------------------------------------------------------------------+
//| Institutional Kill Zone Time Filter                              |
//+------------------------------------------------------------------+
bool IsInKillZone(datetime time)
{
   if(!InpUseKillZones) return(true);

   datetime nyTime = BrokerTimeToNYTime(time);
   MqlDateTime dt;
   TimeToStruct(nyTime, dt);

   int minuteOfDay = dt.hour * 60 + dt.min;

   if(InpTradeLondonOpen && minuteOfDay >= 180 && minuteOfDay <= 360) return(true);
   if(InpTradeNYOpen && minuteOfDay >= 570 && minuteOfDay <= 690) return(true);
   if(InpTradeNYAfternoon && minuteOfDay >= 810 && minuteOfDay <= 930) return(true);

   return(false);
}

//+------------------------------------------------------------------+
//| Calculate Range Boundaries for Current Session                   |
//+------------------------------------------------------------------+
void GetSessionTimeRange(datetime currentTime, datetime &sStart, datetime &sEnd)
{
   if(InpSessionMode == SESSION_AUTO_BROKER)
   {
      sStart = iTime(Symbol(), PERIOD_D1, 0);
      sEnd   = currentTime;
   }
   else
   {
      datetime nyNow = BrokerTimeToNYTime(currentTime);
      MqlDateTime dt;
      TimeToStruct(nyNow, dt);

      dt.hour = InpNYSessionStartHour;
      dt.min  = 0;
      dt.sec  = 0;
      datetime nySessionStart = StructToTime(dt);

      if(nyNow < nySessionStart)
      {
         nySessionStart -= 86400;
      }

      TimeToStruct(nySessionStart, dt);
      if(dt.day_of_week == 6)
      {
         nySessionStart -= 86400;
      }

      sStart = NYTimeToBrokerTime(nySessionStart);
      sEnd   = currentTime;
   }
}

//+------------------------------------------------------------------+
//| Calculate Range Boundaries for Previous Day                      |
//+------------------------------------------------------------------+
void GetDailyTimeRange(datetime currentTime, datetime &dStart, datetime &dEnd)
{
   if(InpSessionMode == SESSION_AUTO_BROKER)
   {
      dStart = iTime(Symbol(), PERIOD_D1, 1);
      dEnd   = iTime(Symbol(), PERIOD_D1, 0) - 1;
   }
   else
   {
      datetime sStart, sEnd;
      GetSessionTimeRange(currentTime, sStart, sEnd);

      dEnd = sStart - 1;
      datetime nyEnd = BrokerTimeToNYTime(dEnd);
      datetime nyStart = nyEnd - 86400 + 1;

      MqlDateTime dt;
      TimeToStruct(nyStart, dt);
      if(dt.day_of_week == 0)
      {
         nyStart -= 2 * 86400;
         nyEnd   -= 2 * 86400;
      }
      else if(dt.day_of_week == 6)
      {
         nyStart -= 86400;
         nyEnd   -= 86400;
      }

      dStart = NYTimeToBrokerTime(nyStart);
      dEnd   = NYTimeToBrokerTime(nyEnd);
   }
}

//+------------------------------------------------------------------+
//| Calculate Range Boundaries for Previous Week                     |
//+------------------------------------------------------------------+
void GetWeeklyTimeRange(datetime &wStart, datetime &wEnd)
{
   wStart = iTime(Symbol(), PERIOD_W1, 1);
   wEnd   = iTime(Symbol(), PERIOD_W1, 0) - 1;
}

//+------------------------------------------------------------------+
//| Calculate Range Boundaries for Previous Month                    |
//+------------------------------------------------------------------+
void GetMonthlyTimeRange(datetime &mStart, datetime &mEnd)
{
   mStart = iTime(Symbol(), PERIOD_MN1, 1);
   mEnd   = iTime(Symbol(), PERIOD_MN1, 0) - 1;
}

//+------------------------------------------------------------------+
//| Pick optimal calculation timeframe to balance precision & speed  |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetOptimalTimeframe(datetime startTime, datetime endTime, int targetProfileType)
{
   int chartTF = Period();

   if(targetProfileType == 0 || targetProfileType == 1)
   {
      if(iBars(Symbol(), PERIOD_M1) > 1000) return(PERIOD_M1);
      if(iBars(Symbol(), PERIOD_M5) > 500)  return(PERIOD_M5);
      return((ENUM_TIMEFRAMES)MathMax(chartTF, PERIOD_M1));
   }
   else if(targetProfileType == 2)
   {
      if(iBars(Symbol(), PERIOD_M5) > 2000) return(PERIOD_M5);
      if(iBars(Symbol(), PERIOD_M15) > 1000) return(PERIOD_M15);
      return((ENUM_TIMEFRAMES)MathMax(chartTF, PERIOD_M15));
   }
   else
   {
      if(iBars(Symbol(), PERIOD_M15) > 3000) return(PERIOD_M15);
      if(iBars(Symbol(), PERIOD_H1) > 1000)  return(PERIOD_H1);
      return((ENUM_TIMEFRAMES)MathMax(chartTF, PERIOD_H1));
   }
}

//+------------------------------------------------------------------+
//| Core Volume Profile Engine (Dalton 70% Value Area + LVN/HVN)     |
//+------------------------------------------------------------------+
bool CalculateProfile(datetime startTime, datetime endTime, int profileType, SProfileResult &result)
{
   result.isValid = false;
   if(startTime >= endTime) return(false);

   ENUM_TIMEFRAMES calcTF = GetOptimalTimeframe(startTime, endTime, profileType);

   int startBar = iBarShift(Symbol(), calcTF, startTime, false);
   int endBar   = iBarShift(Symbol(), calcTF, endTime, false);

   if(startBar < 0 || endBar < 0 || startBar <= endBar) return(false);

   double highestPrice = -1.0;
   double lowestPrice  = 1e12;

   for(int i = startBar; i >= endBar; i--)
   {
      double h = iHigh(Symbol(), calcTF, i);
      double l = iLow(Symbol(), calcTF, i);
      if(h > highestPrice) highestPrice = h;
      if(l < lowestPrice)  lowestPrice  = l;
   }

   if(highestPrice <= lowestPrice || lowestPrice <= 0) return(false);

   double step = 0.0;
   int numBins = 0;

   if(InpStepMode == STEP_DYNAMIC_ROWS)
   {
      numBins = MathMax(20, MathMin(MAX_BINS, InpNumberOfRows));
      step    = (highestPrice - lowestPrice) / (double)numBins;
   }
   else
   {
      step = InpFixedPoints * Point;
      if(step <= 0) step = Point * 10;
      numBins = (int)MathCeil((highestPrice - lowestPrice) / step) + 1;
      if(numBins > MAX_BINS)
      {
         numBins = MAX_BINS;
         step    = (highestPrice - lowestPrice) / (double)numBins;
      }
   }

   if(step <= 0 || numBins <= 1) return(false);

   long binsVolume[];
   ArrayResize(binsVolume, numBins);
   ArrayInitialize(binsVolume, 0);

   long totalVolume = 0;

   for(int i = startBar; i >= endBar; i--)
   {
      double bHigh = iHigh(Symbol(), calcTF, i);
      double bLow  = iLow(Symbol(), calcTF, i);
      long   bVol  = GetBarVolume(Symbol(), calcTF, i);

      int binLow  = (int)MathFloor((bLow - lowestPrice) / step);
      int binHigh = (int)MathFloor((bHigh - lowestPrice) / step);

      if(binLow < 0) binLow = 0;
      if(binHigh >= numBins) binHigh = numBins - 1;

      int span = binHigh - binLow + 1;
      if(span <= 1)
      {
         binsVolume[binLow] += bVol;
      }
      else
      {
         long volPerBin = bVol / span;
         long remainder = bVol % span;
         for(int b = binLow; b <= binHigh; b++)
         {
            binsVolume[b] += volPerBin + (b == binLow ? remainder : 0);
         }
      }
      totalVolume += bVol;
   }

   if(totalVolume <= 0) return(false);

   int  pocBin    = 0;
   long maxVolBin = binsVolume[0];

   for(int b = 1; b < numBins; b++)
   {
      if(binsVolume[b] > maxVolBin)
      {
         maxVolBin = binsVolume[b];
         pocBin    = b;
      }
   }

   double targetVol  = totalVolume * (InpValueAreaPercent / 100.0);
   long   currentVol = binsVolume[pocBin];

   int up   = pocBin + 1;
   int down = pocBin - 1;

   while(currentVol < targetVol && (up < numBins || down >= 0))
   {
      long volUp = 0;
      int  stepUp = 0;
      if(up < numBins)
      {
         volUp += binsVolume[up];
         stepUp++;
         if(up + 1 < numBins)
         {
            volUp += binsVolume[up + 1];
            stepUp++;
         }
      }

      long volDown = 0;
      int  stepDown = 0;
      if(down >= 0)
      {
         volDown += binsVolume[down];
         stepDown++;
         if(down - 1 >= 0)
         {
            volDown += binsVolume[down - 1];
            stepDown++;
         }
      }

      if(volUp > volDown)
      {
         currentVol += volUp;
         up += stepUp;
      }
      else if(volDown > volUp)
      {
         currentVol += volDown;
         down -= stepDown;
      }
      else
      {
         if(up < numBins && down >= 0)
         {
            currentVol += (binsVolume[up] + binsVolume[down]);
            up++;
            down--;
         }
         else if(up < numBins)
         {
            currentVol += binsVolume[up];
            up++;
         }
         else if(down >= 0)
         {
            currentVol += binsVolume[down];
            down--;
         }
         else
         {
            break;
         }
      }
   }

   int vahBin = MathMin(numBins - 1, MathMax(pocBin, up - 1));
   int valBin = MathMax(0, MathMin(pocBin, down + 1));

   int lvnAboveBin = -1;
   long minVAbove = 0x7FFFFFFFFFFFFFFF;
   for(int b = vahBin + 1; b < numBins; b++)
   {
      if(binsVolume[b] < minVAbove)
      {
         minVAbove = binsVolume[b];
         lvnAboveBin = b;
      }
   }

   int lvnBelowBin = -1;
   long minVBelow = 0x7FFFFFFFFFFFFFFF;
   for(int b = valBin - 1; b >= 0; b--)
   {
      if(binsVolume[b] < minVBelow)
      {
         minVBelow = binsVolume[b];
         lvnBelowBin = b;
      }
   }

   result.poc         = NormalizeDouble(lowestPrice + (pocBin + 0.5) * step, Digits);
   result.vah         = NormalizeDouble(lowestPrice + (vahBin + 1.0) * step, Digits);
   result.val         = NormalizeDouble(lowestPrice + (valBin * step), Digits);
   result.lvnUpper    = (lvnAboveBin >= 0) ? NormalizeDouble(lowestPrice + (lvnAboveBin + 0.5) * step, Digits) : result.vah;
   result.lvnLower    = (lvnBelowBin >= 0) ? NormalizeDouble(lowestPrice + (lvnBelowBin + 0.5) * step, Digits) : result.val;
   result.high        = NormalizeDouble(highestPrice, Digits);
   result.low         = NormalizeDouble(lowestPrice, Digits);
   result.totalVol    = totalVolume;
   result.pocBin      = pocBin;
   result.vahBin      = vahBin;
   result.valBin      = valBin;
   result.numBins     = numBins;
   result.step        = step;
   result.startTime   = startTime;
   result.endTime     = endTime;
   result.isValid     = true;

   return(true);
}

//+------------------------------------------------------------------+
//| Calculate Profiles across all timeframes                         |
//+------------------------------------------------------------------+
void CalculateSessionProfile()
{
   if(!InpShowSession && !InpDrawHistogram) return;
   datetime sStart, sEnd;
   GetSessionTimeRange(TimeCurrent(), sStart, sEnd);
   CalculateProfile(sStart, sEnd, 0, g_profSession);
}

void CalculateDailyProfile()
{
   if(!InpShowDaily) return;
   datetime dStart, dEnd;
   GetDailyTimeRange(TimeCurrent(), dStart, dEnd);
   CalculateProfile(dStart, dEnd, 1, g_profDaily);
}

void CalculateWeeklyProfile()
{
   if(!InpShowWeekly) return;
   datetime wStart, wEnd;
   GetWeeklyTimeRange(wStart, wEnd);
   CalculateProfile(wStart, wEnd, 2, g_profWeekly);
}

void CalculateMonthlyProfile()
{
   if(!InpShowMonthly) return;
   datetime mStart, mEnd;
   GetMonthlyTimeRange(mStart, mEnd);
   CalculateProfile(mStart, mEnd, 3, g_profMonthly);
}

//+------------------------------------------------------------------+
//| Virgin / Naked POC (vPOC) Engine                                 |
//+------------------------------------------------------------------+
void CalculateNakedPOCs()
{
   ArrayResize(g_vpocs, 0);
   if(!InpShowVPOC) return;

   for(int d = 1; d <= InpNumVPOCDays; d++)
   {
      datetime dStart = iTime(Symbol(), PERIOD_D1, d);
      datetime dEnd   = iTime(Symbol(), PERIOD_D1, d - 1) - 1;
      if(dStart <= 0 || dEnd <= 0) continue;

      SProfileResult pRes;
      if(!CalculateProfile(dStart, dEnd, 1, pRes)) continue;

      double pocPrice = pRes.poc;
      bool isMitigated = false;
      datetime mitTime = 0;

      int startShift = iBarShift(Symbol(), PERIOD_M15, dEnd, false);
      for(int b = startShift; b >= 0; b--)
      {
         double bh = iHigh(Symbol(), PERIOD_M15, b);
         double bl = iLow(Symbol(), PERIOD_M15, b);
         if(bl <= pocPrice && bh >= pocPrice)
         {
            isMitigated = true;
            mitTime = iTime(Symbol(), PERIOD_M15, b);
            break;
         }
      }

      int sz = ArraySize(g_vpocs);
      ArrayResize(g_vpocs, sz + 1);
      g_vpocs[sz].price          = pocPrice;
      g_vpocs[sz].startTime      = dStart;
      g_vpocs[sz].endTime        = dEnd;
      g_vpocs[sz].mitigationTime = mitTime;
      g_vpocs[sz].isMitigated    = isMitigated;
      g_vpocs[sz].isWeekly       = false;
      g_vpocs[sz].dayIndex       = d;
   }

   for(int w = 1; w <= InpNumVPOCWeeks; w++)
   {
      datetime wStart = iTime(Symbol(), PERIOD_W1, w);
      datetime wEnd   = iTime(Symbol(), PERIOD_W1, w - 1) - 1;
      if(wStart <= 0 || wEnd <= 0) continue;

      SProfileResult pRes;
      if(!CalculateProfile(wStart, wEnd, 2, pRes)) continue;

      double pocPrice = pRes.poc;
      bool isMitigated = false;
      datetime mitTime = 0;

      int startShift = iBarShift(Symbol(), PERIOD_H1, wEnd, false);
      for(int b = startShift; b >= 0; b--)
      {
         double bh = iHigh(Symbol(), PERIOD_H1, b);
         double bl = iLow(Symbol(), PERIOD_H1, b);
         if(bl <= pocPrice && bh >= pocPrice)
         {
            isMitigated = true;
            mitTime = iTime(Symbol(), PERIOD_H1, b);
            break;
         }
      }

      int sz = ArraySize(g_vpocs);
      ArrayResize(g_vpocs, sz + 1);
      g_vpocs[sz].price          = pocPrice;
      g_vpocs[sz].startTime      = wStart;
      g_vpocs[sz].endTime        = wEnd;
      g_vpocs[sz].mitigationTime = mitTime;
      g_vpocs[sz].isMitigated    = isMitigated;
      g_vpocs[sz].isWeekly       = true;
      g_vpocs[sz].dayIndex       = w;
   }
}

//+------------------------------------------------------------------+
//| Calculate All Profiles                                           |
//+------------------------------------------------------------------+
void CalculateAllProfiles(bool force)
{
   CalculateMonthlyProfile();
   CalculateWeeklyProfile();
   CalculateDailyProfile();
   CalculateSessionProfile();
   if(InpShowVPOC) CalculateNakedPOCs();
   DetectConfluences();
   DrawAllLevels();
   if(InpShowVPOC) DrawVPOCLines();
   if(InpDrawHistogram) DrawSessionHistogram();
}

//+------------------------------------------------------------------+
//| Confluence Star Rating Matrix                                    |
//+------------------------------------------------------------------+
int RateConfluence(string name1, string name2, string &ratingDesc)
{
   string p1 = StringSubstr(name1, 0, 1);
   string p2 = StringSubstr(name2, 0, 1);
   bool isM = (p1 == "M" || p2 == "M");
   bool isW = (p1 == "W" || p2 == "W");
   bool isD = (p1 == "D" || p2 == "D");
   bool isS = (p1 == "S" || p2 == "S");

   bool poc1 = (StringFind(name1, "POC") >= 0);
   bool poc2 = (StringFind(name2, "POC") >= 0);
   bool bothPOC = (poc1 && poc2);

   if(isM && isW && bothPOC)
   {
      ratingDesc = "[5 STARS] Macro Institutional Wall";
      return(5);
   }
   if(isM && (isW || isD))
   {
      ratingDesc = "[4 STARS] High-Probability Macro Reversal";
      return(4);
   }
   if(isW && isD && (poc1 || poc2))
   {
      ratingDesc = "[4 STARS] A+ Institutional Setup";
      return(4);
   }
   if(isW && isD)
   {
      ratingDesc = "[3 STARS] Solid Day-Trade Confluence";
      return(3);
   }
   if(isD && isS)
   {
      ratingDesc = "[2 STARS] Intraday Scalp Confluence";
      return(2);
   }

   ratingDesc = "[1 STAR] Minor Level";
   return(1);
}

//+------------------------------------------------------------------+
//| Detect Multi-Timeframe Level Confluences                         |
//+------------------------------------------------------------------+
void DetectConfluences()
{
   ArrayResize(g_confluences, 0);
   if(!InpEnableConfluence) return;

   string names[12]  = {"","","","","","","","","","","",""};
   double prices[12] = {0,0,0,0,0,0,0,0,0,0,0,0};
   int count = 0;

   if(g_profMonthly.isValid && InpShowMonthly)
   {
      names[count] = "M-POC"; prices[count++] = g_profMonthly.poc;
      names[count] = "M-VAH"; prices[count++] = g_profMonthly.vah;
      names[count] = "M-VAL"; prices[count++] = g_profMonthly.val;
   }
   if(g_profWeekly.isValid && InpShowWeekly)
   {
      names[count] = "W-POC"; prices[count++] = g_profWeekly.poc;
      names[count] = "W-VAH"; prices[count++] = g_profWeekly.vah;
      names[count] = "W-VAL"; prices[count++] = g_profWeekly.val;
   }
   if(g_profDaily.isValid && InpShowDaily)
   {
      names[count] = "D-POC"; prices[count++] = g_profDaily.poc;
      names[count] = "D-VAH"; prices[count++] = g_profDaily.vah;
      names[count] = "D-VAL"; prices[count++] = g_profDaily.val;
   }
   if(g_profSession.isValid && InpShowSession)
   {
      names[count] = "S-POC"; prices[count++] = g_profSession.poc;
      names[count] = "S-VAH"; prices[count++] = g_profSession.vah;
      names[count] = "S-VAL"; prices[count++] = g_profSession.val;
   }

   double pipSize = GetPipSize();
   double threshold = InpConfluenceThreshold * pipSize;

   for(int i = 0; i < count; i++)
   {
      for(int j = i + 1; j < count; j++)
      {
         if(StringSubstr(names[i], 0, 1) == StringSubstr(names[j], 0, 1)) continue;

         double diff = MathAbs(prices[i] - prices[j]);
         if(diff <= threshold)
         {
            int cSize = ArraySize(g_confluences);
            ArrayResize(g_confluences, cSize + 1);
            g_confluences[cSize].name1    = names[i];
            g_confluences[cSize].name2    = names[j];
            g_confluences[cSize].price1   = prices[i];
            g_confluences[cSize].price2   = prices[j];
            g_confluences[cSize].midPrice = NormalizeDouble((prices[i] + prices[j]) / 2.0, Digits);
            g_confluences[cSize].diffPips = NormalizeDouble(diff / pipSize, 1);

            string rDesc = "";
            g_confluences[cSize].stars     = RateConfluence(names[i], names[j], rDesc);
            g_confluences[cSize].ratingStr = rDesc;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if a level is part of an active confluence                 |
//+------------------------------------------------------------------+
bool IsLevelConfluent(string levelName, string &confluentWith, double &partnerPrice, int &stars)
{
   for(int i = 0; i < ArraySize(g_confluences); i++)
   {
      if(g_confluences[i].name1 == levelName)
      {
         confluentWith = g_confluences[i].name2;
         partnerPrice  = g_confluences[i].price2;
         stars         = g_confluences[i].stars;
         return(true);
      }
      if(g_confluences[i].name2 == levelName)
      {
         confluentWith = g_confluences[i].name1;
         partnerPrice  = g_confluences[i].price1;
         stars         = g_confluences[i].stars;
         return(true);
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Object Pool: Draw or Update a Trend Line                         |
//+------------------------------------------------------------------+
void DrawOrUpdateTrendLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, int width, ENUM_LINE_STYLE style, bool ray)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE1, p1);
      ObjectSetDouble(0, name, OBJPROP_PRICE2, p2);
      ObjectSetInteger(0, name, OBJPROP_TIME1, t1);
      ObjectSetInteger(0, name, OBJPROP_TIME2, t2);
   }
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, ray);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
}

//+------------------------------------------------------------------+
//| Object Pool: Draw or Update a Text Label                         |
//+------------------------------------------------------------------+
void DrawOrUpdateTextLabel(string name, datetime t, double p, string text, color clr, int fontSize, ENUM_ANCHOR_POINT anchor)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE1, p);
      ObjectSetInteger(0, name, OBJPROP_TIME1, t);
   }
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Draw a Profile Level Line with Label                             |
//+------------------------------------------------------------------+
void DrawLevelLine(string id, string labelText, double price, datetime startTime, color baseColor, int baseWidth, ENUM_LINE_STYLE baseStyle)
{
   if(price <= 0) return;

   string lineName  = PREFIX + "Line_"  + id;
   string labelName = PREFIX + "Label_" + id;

   int secPerBar = PeriodSeconds();
   datetime endTime = TimeCurrent() + InpExtendBars * secPerBar;

   string partner = "";
   double partnerPrice = 0;
   int stars = 0;
   bool isConf = IsLevelConfluent(id, partner, partnerPrice, stars);

   color drawColor = (isConf && InpEnableConfluence) ? InpConfluenceColor : baseColor;
   int   drawWidth = (isConf && InpEnableConfluence) ? (baseWidth + 2) : baseWidth;

   DrawOrUpdateTrendLine(lineName, startTime, price, endTime, price, drawColor, drawWidth, baseStyle, InpExtendRay);

   datetime labelTime = InpExtendRay ? (TimeCurrent() + 20 * secPerBar) : endTime;
   string textStr = StringFormat("[%s] %s", labelText, DoubleToString(price, Digits));
   if(isConf && InpEnableConfluence)
   {
      textStr += StringFormat(" [★%d CONF w/ %s]", stars, partner);
   }

   DrawOrUpdateTextLabel(labelName, labelTime, price, textStr, drawColor, 8, ANCHOR_LEFT);
}

//+------------------------------------------------------------------+
//| Draw All Profile Levels on Chart                                 |
//+------------------------------------------------------------------+
void DrawAllLevels()
{
   if(InpShowSession && g_profSession.isValid)
   {
      DrawLevelLine("S-POC", "S-POC", g_profSession.poc, g_profSession.startTime, InpColorSessionPOC, InpLineWidthPOC, STYLE_SOLID);
      DrawLevelLine("S-VAH", "S-VAH", g_profSession.vah, g_profSession.startTime, InpColorSessionVA,  InpLineWidthVA,  InpLineStyleVA);
      DrawLevelLine("S-VAL", "S-VAL", g_profSession.val, g_profSession.startTime, InpColorSessionVA,  InpLineWidthVA,  InpLineStyleVA);
   }
   if(InpShowDaily && g_profDaily.isValid)
   {
      DrawLevelLine("D-POC", "D-POC", g_profDaily.poc, g_profDaily.startTime, InpColorDailyPOC, InpLineWidthPOC, STYLE_SOLID);
      DrawLevelLine("D-VAH", "D-VAH", g_profDaily.vah, g_profDaily.startTime, InpColorDailyVA,  InpLineWidthVA,  InpLineStyleVA);
      DrawLevelLine("D-VAL", "D-VAL", g_profDaily.val, g_profDaily.startTime, InpColorDailyVA,  InpLineWidthVA,  InpLineStyleVA);
   }
   if(InpShowWeekly && g_profWeekly.isValid)
   {
      DrawLevelLine("W-POC", "W-POC", g_profWeekly.poc, g_profWeekly.startTime, InpColorWeeklyPOC, InpLineWidthPOC, STYLE_SOLID);
      DrawLevelLine("W-VAH", "W-VAH", g_profWeekly.vah, g_profWeekly.startTime, InpColorWeeklyVA,  InpLineWidthVA,  InpLineStyleVA);
      DrawLevelLine("W-VAL", "W-VAL", g_profWeekly.val, g_profWeekly.startTime, InpColorWeeklyVA,  InpLineWidthVA,  InpLineStyleVA);
   }
   if(InpShowMonthly && g_profMonthly.isValid)
   {
      DrawLevelLine("M-POC", "M-POC", g_profMonthly.poc, g_profMonthly.startTime, InpColorMonthlyPOC, InpLineWidthPOC, STYLE_SOLID);
      DrawLevelLine("M-VAH", "M-VAH", g_profMonthly.vah, g_profMonthly.startTime, InpColorMonthlyVA,  InpLineWidthVA,  InpLineStyleVA);
      DrawLevelLine("M-VAL", "M-VAL", g_profMonthly.val, g_profMonthly.startTime, InpColorMonthlyVA,  InpLineWidthVA,  InpLineStyleVA);
   }
}

//+------------------------------------------------------------------+
//| Draw Virgin / Naked POC Lines                                    |
//+------------------------------------------------------------------+
void DrawVPOCLines()
{
   if(!InpShowVPOC) return;

   int count = ArraySize(g_vpocs);
   for(int i = 0; i < count; i++)
   {
      string id = (g_vpocs[i].isWeekly ? "W_" : "D_") + IntegerToString(g_vpocs[i].dayIndex);
      string lineName  = PREFIX + "vPOC_Line_"  + id;
      string labelName = PREFIX + "vPOC_Label_" + id;

      if(g_vpocs[i].isMitigated)
      {
         ObjectDelete(0, lineName);
         ObjectDelete(0, labelName);
         continue;
      }

      datetime tEnd = TimeCurrent() + 60 * PeriodSeconds();
      color vpocColor = g_vpocs[i].isWeekly ? InpColorVPOCWeekly : InpColorVPOCDaily;

      DrawOrUpdateTrendLine(lineName, g_vpocs[i].endTime, g_vpocs[i].price, tEnd, g_vpocs[i].price, vpocColor, 1, STYLE_DOT, InpExtendRay);

      string lbl = StringFormat("[vPOC %s] %s", (g_vpocs[i].isWeekly ? "Wk" : "Day") + IntegerToString(g_vpocs[i].dayIndex), DoubleToString(g_vpocs[i].price, Digits));
      DrawOrUpdateTextLabel(labelName, tEnd, g_vpocs[i].price, lbl, vpocColor, 8, ANCHOR_LEFT);
   }
}

//+------------------------------------------------------------------+
//| Draw Session Volume Profile Histogram                            |
//+------------------------------------------------------------------+
void DrawSessionHistogram()
{
   if(!g_profSession.isValid || g_profSession.numBins <= 0) return;

   ENUM_TIMEFRAMES calcTF = GetOptimalTimeframe(g_profSession.startTime, g_profSession.endTime, 0);
   int startBar = iBarShift(Symbol(), calcTF, g_profSession.startTime, false);
   int endBar   = iBarShift(Symbol(), calcTF, g_profSession.endTime, false);
   if(startBar <= endBar) return;

   int numBins = g_profSession.numBins;
   double step = g_profSession.step;
   double lowestPrice = g_profSession.low;

   long bins[];
   ArrayResize(bins, numBins);
   ArrayInitialize(bins, 0);
   long maxV = 0;

   for(int i = startBar; i >= endBar; i--)
   {
      double bHigh = iHigh(Symbol(), calcTF, i);
      double bLow  = iLow(Symbol(), calcTF, i);
      long   bVol  = GetBarVolume(Symbol(), calcTF, i);

      int binLow  = (int)MathFloor((bLow - lowestPrice) / step);
      int binHigh = (int)MathFloor((bHigh - lowestPrice) / step);
      if(binLow < 0) binLow = 0;
      if(binHigh >= numBins) binHigh = numBins - 1;

      int span = binHigh - binLow + 1;
      long vPer = bVol / span;
      for(int b = binLow; b <= binHigh; b++)
      {
         bins[b] += vPer;
         if(bins[b] > maxV) maxV = bins[b];
      }
   }

   if(maxV <= 0) return;

   datetime anchorTime = (InpHistAlignment == HIST_ALIGN_SESSION_START) ? g_profSession.startTime : Time[0];
   int secPerBar = PeriodSeconds();

   if(g_lastHistBarCount > numBins)
   {
      for(int b = numBins; b < g_lastHistBarCount; b++)
      {
         ObjectDelete(0, PREFIX + "Hist_" + IntegerToString(b));
      }
   }
   g_lastHistBarCount = numBins;

   for(int b = 0; b < numBins; b++)
   {
      string barName = PREFIX + "Hist_" + IntegerToString(b);
      double p1 = lowestPrice + b * step;
      double p2 = lowestPrice + (b + 1) * step;

      int barWidth = (int)MathRound(((double)bins[b] / (double)maxV) * InpMaxHistWidthBars);
      if(barWidth < 1) barWidth = 1;

      datetime t1 = anchorTime;
      datetime t2 = anchorTime + barWidth * secPerBar;

      color barColor = InpHistColorOutside;
      if(b == g_profSession.pocBin)
         barColor = InpHistColorPOC;
      else if(b >= g_profSession.valBin && b <= g_profSession.vahBin)
         barColor = InpHistColorVA;

      if(ObjectFind(0, barName) < 0)
      {
         ObjectCreate(0, barName, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
         ObjectSetInteger(0, barName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, barName, OBJPROP_BACK, true);
      }
      else
      {
         ObjectSetDouble(0, barName, OBJPROP_PRICE1, p1);
         ObjectSetDouble(0, barName, OBJPROP_PRICE2, p2);
         ObjectSetInteger(0, barName, OBJPROP_TIME1, t1);
         ObjectSetInteger(0, barName, OBJPROP_TIME2, t2);
      }
      ObjectSetInteger(0, barName, OBJPROP_COLOR, barColor);
   }
}

//+------------------------------------------------------------------+
//| Populate Buffers for EA (iCustom)                                |
//+------------------------------------------------------------------+
void PopulateBuffers(int rates_total)
{
   int limit = MathMin(rates_total, 500);

   double nearestVPOC = 0.0;
   for(int v = 0; v < ArraySize(g_vpocs); v++)
   {
      if(!g_vpocs[v].isMitigated)
      {
         nearestVPOC = g_vpocs[v].price;
         break;
      }
   }

   for(int i = 0; i < limit; i++)
   {
      buf_DailyPOC[i]   = g_profDaily.isValid   ? g_profDaily.poc   : 0.0;
      buf_DailyVAH[i]   = g_profDaily.isValid   ? g_profDaily.vah   : 0.0;
      buf_DailyVAL[i]   = g_profDaily.isValid   ? g_profDaily.val   : 0.0;

      buf_WeeklyPOC[i]  = g_profWeekly.isValid  ? g_profWeekly.poc  : 0.0;
      buf_WeeklyVAH[i]  = g_profWeekly.isValid  ? g_profWeekly.vah  : 0.0;
      buf_WeeklyVAL[i]  = g_profWeekly.isValid  ? g_profWeekly.val  : 0.0;

      buf_MonthlyPOC[i] = g_profMonthly.isValid ? g_profMonthly.poc : 0.0;
      buf_MonthlyVAH[i] = g_profMonthly.isValid ? g_profMonthly.vah : 0.0;
      buf_MonthlyVAL[i] = g_profMonthly.isValid ? g_profMonthly.val : 0.0;

      buf_SessionPOC[i] = g_profSession.isValid ? g_profSession.poc : 0.0;
      buf_SessionVAH[i] = g_profSession.isValid ? g_profSession.vah : 0.0;
      buf_SessionVAL[i] = g_profSession.isValid ? g_profSession.val : 0.0;

      buf_TradePlanSL[i]  = g_activePlan.isActive ? g_activePlan.slPrice  : 0.0;
      buf_TradePlanTP1[i] = g_activePlan.isActive ? g_activePlan.tp1Price : 0.0;
      buf_TradePlanTP2[i] = g_activePlan.isActive ? g_activePlan.tp2Price : 0.0;
      buf_ActiveVPOC[i]   = nearestVPOC;
   }
}

//+------------------------------------------------------------------+
//| Evaluate High-Probability AMT Entry Signals (Signs)              |
//+------------------------------------------------------------------+
void EvaluateEntrySignals(int rates_total, int prev_calculated)
{
   if(!InpShowEntrySignals) return;

   double pipSize   = GetPipSize();
   double tolerance = InpSignalTolerancePips * pipSize;
   double offset    = InpArrowOffsetPips * pipSize;

   int limit = rates_total - prev_calculated - 1;
   if(prev_calculated == 0)
   {
      limit = MathMin(rates_total - 2, InpSignalScanBars);
      ArrayInitialize(buf_SignalBuy, 0.0);
      ArrayInitialize(buf_SignalSell, 0.0);
   }

   buf_SignalBuy[0]  = 0.0;
   buf_SignalSell[0] = 0.0;

   for(int i = limit; i >= 1; i--)
   {
      buf_SignalBuy[i]  = 0.0;
      buf_SignalSell[i] = 0.0;

      if(InpUseKillZones && !IsInKillZone(Time[i])) continue;

      double o = Open[i];
      double h = High[i];
      double l = Low[i];
      double c = Close[i];
      double totalRange = h - l;
      if(totalRange <= 0) continue;

      bool   isBullishCandle = (c > o);
      bool   isBearishCandle = (c < o);
      double lowerWick       = MathMin(o, c) - l;
      double upperWick       = h - MathMax(o, c);

      string signalDesc = "";
      string setupType  = "";
      bool   buyFound   = false;
      bool   sellFound  = false;

      // ------------------------------------------------------------------
      // SETUP 3: Multi-Timeframe Confluence Bounce (Highest Probability)
      // ------------------------------------------------------------------
      if(InpSignalConfluence && ArraySize(g_confluences) > 0)
      {
         for(int k = 0; k < ArraySize(g_confluences); k++)
         {
            double confPrice = g_confluences[k].midPrice;

            if(l <= confPrice + tolerance && h >= confPrice - tolerance && isBullishCandle && c >= confPrice)
            {
               if(lowerWick >= 0.20 * totalRange || c > confPrice)
               {
                  buyFound  = true;
                  setupType = "Confluence Bounce";
                  signalDesc = StringFormat("BUY: Confluence Bounce [%s + %s] @ %s (★%d)",
                                            g_confluences[k].name1,
                                            g_confluences[k].name2,
                                            DoubleToString(confPrice, Digits),
                                            g_confluences[k].stars);
                  break;
               }
            }

            if(h >= confPrice - tolerance && l <= confPrice + tolerance && isBearishCandle && c <= confPrice)
            {
               if(upperWick >= 0.20 * totalRange || c < confPrice)
               {
                  sellFound = true;
                  setupType = "Confluence Rejection";
                  signalDesc = StringFormat("SELL: Confluence Rejection [%s + %s] @ %s (★%d)",
                                            g_confluences[k].name1,
                                            g_confluences[k].name2,
                                            DoubleToString(confPrice, Digits),
                                            g_confluences[k].stars);
                  break;
               }
            }
         }
      }

      // ------------------------------------------------------------------
      // SETUP 1: Value Area Extreme Rotation (Mean Reversion)
      // ------------------------------------------------------------------
      if(!buyFound && !sellFound && InpSignalValVahRotate && g_profDaily.isValid)
      {
         double dVal = g_profDaily.val;
         double dVah = g_profDaily.vah;

         if(l <= dVal + tolerance && h >= dVal - tolerance && isBullishCandle && c >= dVal)
         {
            if(lowerWick >= 0.20 * totalRange || c > dVal)
            {
               buyFound  = true;
               setupType = "VAL Rejection";
               signalDesc = StringFormat("BUY: D-VAL Rejection @ %s (Target D-POC %s)",
                                         DoubleToString(dVal, Digits),
                                         DoubleToString(g_profDaily.poc, Digits));
            }
         }

         if(h >= dVah - tolerance && l <= dVah + tolerance && isBearishCandle && c <= dVah)
         {
            if(upperWick >= 0.20 * totalRange || c < dVah)
            {
               sellFound = true;
               setupType = "VAH Rejection";
               signalDesc = StringFormat("SELL: D-VAH Rejection @ %s (Target D-POC %s)",
                                         DoubleToString(dVah, Digits),
                                         DoubleToString(g_profDaily.poc, Digits));
            }
         }
      }

      // ------------------------------------------------------------------
      // SETUP 2: Imbalance Retest (Breakout & Flip)
      // ------------------------------------------------------------------
      if(!buyFound && !sellFound && InpSignalImbalanceRetest && g_profDaily.isValid)
      {
         double dVal = g_profDaily.val;
         double dVah = g_profDaily.vah;

         if(i + 1 < rates_total && Open[i + 1] >= dVah - tolerance)
         {
            if(l <= dVah + tolerance && l >= dVah - 2 * tolerance && isBullishCandle && c > dVah)
            {
               buyFound  = true;
               setupType = "VAH Retest";
               signalDesc = StringFormat("BUY: Imbalance Retest [D-VAH Support] @ %s", DoubleToString(dVah, Digits));
            }
         }

         if(i + 1 < rates_total && Open[i + 1] <= dVal + tolerance)
         {
            if(h >= dVal - tolerance && h <= dVal + 2 * tolerance && isBearishCandle && c < dVal)
            {
               sellFound = true;
               setupType = "VAL Retest";
               signalDesc = StringFormat("SELL: Imbalance Retest [D-VAL Resistance] @ %s", DoubleToString(dVal, Digits));
            }
         }
      }

      // ------------------------------------------------------------------
      // Record Arrows, Build Dynamic Trade Plan & Trigger Alerts
      // ------------------------------------------------------------------
      if(buyFound)
      {
         buf_SignalBuy[i] = l - offset;

         if(i == 1)
         {
            g_lastSignalType  = "BUY";
            g_lastSignalPrice = c;
            g_lastSignalDesc  = signalDesc;

            g_activePlan.direction   = "BUY";
            g_activePlan.entryPrice  = c;
            double baseSL = l - InpSLBufferPips * pipSize;
            if(g_profDaily.isValid && g_profDaily.lvnLower < baseSL && g_profDaily.lvnLower > 0)
               baseSL = g_profDaily.lvnLower - InpSLBufferPips * pipSize;
            g_activePlan.slPrice     = NormalizeDouble(baseSL, Digits);

            double tp1 = g_profDaily.isValid ? g_profDaily.poc : (c + 20 * pipSize);
            double tp2 = g_profDaily.isValid ? g_profDaily.vah : (c + 40 * pipSize);
            if(tp1 <= c) tp1 = c + (c - g_activePlan.slPrice) * 1.5;
            if(tp2 <= tp1) tp2 = tp1 + (tp1 - c);

            g_activePlan.tp1Price    = NormalizeDouble(tp1, Digits);
            g_activePlan.tp2Price    = NormalizeDouble(tp2, Digits);
            g_activePlan.riskPips    = NormalizeDouble((g_activePlan.entryPrice - g_activePlan.slPrice) / pipSize, 1);
            g_activePlan.reward1Pips = NormalizeDouble((g_activePlan.tp1Price - g_activePlan.entryPrice) / pipSize, 1);
            g_activePlan.reward2Pips = NormalizeDouble((g_activePlan.tp2Price - g_activePlan.entryPrice) / pipSize, 1);
            g_activePlan.rr1         = (g_activePlan.riskPips > 0) ? NormalizeDouble(g_activePlan.reward1Pips / g_activePlan.riskPips, 2) : 0.0;
            g_activePlan.rr2         = (g_activePlan.riskPips > 0) ? NormalizeDouble(g_activePlan.reward2Pips / g_activePlan.riskPips, 2) : 0.0;
            g_activePlan.signalTime  = Time[1];
            g_activePlan.setupName   = setupType;
            g_activePlan.isActive    = true;

            if(InpSignalAlert && Time[1] != g_lastSignalAlertTime)
            {
               string alertMsg = StringFormat("[NF Trades MTF VP] %s: %s | SL: %s | TP1: %s (R:R 1:%.1f)",
                                              Symbol(),
                                              signalDesc,
                                              DoubleToString(g_activePlan.slPrice, Digits),
                                              DoubleToString(g_activePlan.tp1Price, Digits),
                                              g_activePlan.rr1);
               Alert(alertMsg);
               PlaySound(InpSoundFile);
               if(InpSignalPushNotify) SendNotification(alertMsg);
               g_lastSignalAlertTime = Time[1];
            }
         }
      }
      else if(sellFound)
      {
         buf_SignalSell[i] = h + offset;

         if(i == 1)
         {
            g_lastSignalType  = "SELL";
            g_lastSignalPrice = c;
            g_lastSignalDesc  = signalDesc;

            g_activePlan.direction   = "SELL";
            g_activePlan.entryPrice  = c;
            double baseSL = h + InpSLBufferPips * pipSize;
            if(g_profDaily.isValid && g_profDaily.lvnUpper > baseSL)
               baseSL = g_profDaily.lvnUpper + InpSLBufferPips * pipSize;
            g_activePlan.slPrice     = NormalizeDouble(baseSL, Digits);

            double tp1 = g_profDaily.isValid ? g_profDaily.poc : (c - 20 * pipSize);
            double tp2 = g_profDaily.isValid ? g_profDaily.val : (c - 40 * pipSize);
            if(tp1 >= c) tp1 = c - (g_activePlan.slPrice - c) * 1.5;
            if(tp2 >= tp1) tp2 = tp1 - (c - tp1);

            g_activePlan.tp1Price    = NormalizeDouble(tp1, Digits);
            g_activePlan.tp2Price    = NormalizeDouble(tp2, Digits);
            g_activePlan.riskPips    = NormalizeDouble((g_activePlan.slPrice - g_activePlan.entryPrice) / pipSize, 1);
            g_activePlan.reward1Pips = NormalizeDouble((g_activePlan.entryPrice - g_activePlan.tp1Price) / pipSize, 1);
            g_activePlan.reward2Pips = NormalizeDouble((g_activePlan.entryPrice - g_activePlan.tp2Price) / pipSize, 1);
            g_activePlan.rr1         = (g_activePlan.riskPips > 0) ? NormalizeDouble(g_activePlan.reward1Pips / g_activePlan.riskPips, 2) : 0.0;
            g_activePlan.rr2         = (g_activePlan.riskPips > 0) ? NormalizeDouble(g_activePlan.reward2Pips / g_activePlan.riskPips, 2) : 0.0;
            g_activePlan.signalTime  = Time[1];
            g_activePlan.setupName   = setupType;
            g_activePlan.isActive    = true;

            if(InpSignalAlert && Time[1] != g_lastSignalAlertTime)
            {
               string alertMsg = StringFormat("[NF Trades MTF VP] %s: %s | SL: %s | TP1: %s (R:R 1:%.1f)",
                                              Symbol(),
                                              signalDesc,
                                              DoubleToString(g_activePlan.slPrice, Digits),
                                              DoubleToString(g_activePlan.tp1Price, Digits),
                                              g_activePlan.rr1);
               Alert(alertMsg);
               PlaySound(InpSoundFile);
               if(InpSignalPushNotify) SendNotification(alertMsg);
               g_lastSignalAlertTime = Time[1];
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Draw Dynamic Trade Plan (Entry, SL, TP1, TP2, R:R Box)           |
//+------------------------------------------------------------------+
void DrawTradePlan()
{
   if(!InpShowTradePlan || !g_activePlan.isActive) return;

   datetime t1 = g_activePlan.signalTime;
   datetime t2 = t1 + InpTradePlanBars * PeriodSeconds();

   // 1. Entry Line
   DrawOrUpdateTrendLine(PREFIX + "Plan_Entry", t1, g_activePlan.entryPrice, t2, g_activePlan.entryPrice, InpColorPlanEntry, 1, STYLE_SOLID, false);
   string eLbl = StringFormat("[ENTRY %s] %s", g_activePlan.direction, DoubleToString(g_activePlan.entryPrice, Digits));
   DrawOrUpdateTextLabel(PREFIX + "Plan_EntryLbl", t2, g_activePlan.entryPrice, eLbl, InpColorPlanEntry, 8, ANCHOR_LEFT);

   // 2. Stop Loss Line
   DrawOrUpdateTrendLine(PREFIX + "Plan_SL", t1, g_activePlan.slPrice, t2, g_activePlan.slPrice, InpColorPlanSL, 2, STYLE_DASH, false);
   string slLbl = StringFormat("[SL] %s (-%.1f pips)", DoubleToString(g_activePlan.slPrice, Digits), g_activePlan.riskPips);
   DrawOrUpdateTextLabel(PREFIX + "Plan_SLLbl", t2, g_activePlan.slPrice, slLbl, InpColorPlanSL, 8, ANCHOR_LEFT);

   // 3. Take Profit 1 Line (50% scale-out)
   DrawOrUpdateTrendLine(PREFIX + "Plan_TP1", t1, g_activePlan.tp1Price, t2, g_activePlan.tp1Price, InpColorPlanTP1, 1, STYLE_SOLID, false);
   string tp1Lbl = StringFormat("[TP1 - 50%%] %s (+%.1f pips | 1:%.1f R:R)", DoubleToString(g_activePlan.tp1Price, Digits), g_activePlan.reward1Pips, g_activePlan.rr1);
   DrawOrUpdateTextLabel(PREFIX + "Plan_TP1Lbl", t2, g_activePlan.tp1Price, tp1Lbl, InpColorPlanTP1, 8, ANCHOR_LEFT);

   // 4. Take Profit 2 Line (Runner)
   DrawOrUpdateTrendLine(PREFIX + "Plan_TP2", t1, g_activePlan.tp2Price, t2, g_activePlan.tp2Price, InpColorPlanTP2, 1, STYLE_SOLID, false);
   string tp2Lbl = StringFormat("[TP2 - Runner] %s (+%.1f pips | 1:%.1f R:R)", DoubleToString(g_activePlan.tp2Price, Digits), g_activePlan.reward2Pips, g_activePlan.rr2);
   DrawOrUpdateTextLabel(PREFIX + "Plan_TP2Lbl", t2, g_activePlan.tp2Price, tp2Lbl, InpColorPlanTP2, 8, ANCHOR_LEFT);
}

//+------------------------------------------------------------------+
//| Create or Update Chart Label (HUD)                               |
//+------------------------------------------------------------------+
void UpdateDashLabel(string id, string text, int x, int y, color clr, int fontSize = 8, bool bold = false)
{
   string name = PREFIX + "HUD_" + id;
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, InpDashCorner);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Segoe UI Bold" : "Segoe UI");
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Render Auction Market Theory Heads-Up Display (HUD)              |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int x = InpDashX;
   int y = InpDashY;
   int rowHeight = 16;
   double pipSize = GetPipSize();

   //--- 0. Dashboard Background Card
   string bgName = PREFIX + "HUD_BG";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, InpDashCorner);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
      ObjectSetInteger(0, bgName, OBJPROP_COLOR, C'45,55,75');
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'16,22,32');
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_WIDTH, 1);
   }
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x - 8);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y - 6);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 290);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 205);

   // 1. Header
   UpdateDashLabel("Title", "=== NF TRADES | AMT PROFILE ===", x, y, clrGold, 9, true);
   y += rowHeight + 2;

   // 2. Symbol & Bid
   string symStr = StringFormat("%s  TF: %d  |  Bid: %s", Symbol(), Period(), DoubleToString(Bid, Digits));
   UpdateDashLabel("Sym", symStr, x, y, clrWhite, 8, false);
   y += rowHeight;

   // 3. Market Balance State
   string stateStr = "STATE: UNKNOWN";
   color  stateClr = clrWhite;

   if(g_profSession.isValid)
   {
      if(Bid > g_profSession.vah)
      {
         stateStr = "STATE: BULLISH IMBALANCE (> VAH)";
         stateClr = clrLimeGreen;
      }
      else if(Bid < g_profSession.val)
      {
         stateStr = "STATE: BEARISH IMBALANCE (< VAL)";
         stateClr = clrRed;
      }
      else
      {
         stateStr = "STATE: BALANCED / ROTATING (Inside VA)";
         stateClr = clrYellow;
      }
   }
   UpdateDashLabel("State", stateStr, x, y, stateClr, 8, true);
   y += rowHeight;

   // 4. Daily POC Proximity
   if(g_profDaily.isValid)
   {
      double distPips = (Bid - g_profDaily.poc) / pipSize;
      string dStr = StringFormat("D-POC: %s  (Dist: %+.1f pips)", DoubleToString(g_profDaily.poc, Digits), distPips);
      UpdateDashLabel("DPOC", dStr, x, y, InpColorDailyPOC, 8, false);
      y += rowHeight;
   }

   // 5. Weekly POC Proximity
   if(g_profWeekly.isValid)
   {
      double distPips = (Bid - g_profWeekly.poc) / pipSize;
      string wStr = StringFormat("W-POC: %s  (Dist: %+.1f pips)", DoubleToString(g_profWeekly.poc, Digits), distPips);
      UpdateDashLabel("WPOC", wStr, x, y, InpColorWeeklyPOC, 8, false);
      y += rowHeight;
   }

   // 6. Monthly POC Proximity
   if(g_profMonthly.isValid)
   {
      double distPips = (Bid - g_profMonthly.poc) / pipSize;
      string mStr = StringFormat("M-POC: %s  (Dist: %+.1f pips)", DoubleToString(g_profMonthly.poc, Digits), distPips);
      UpdateDashLabel("MPOC", mStr, x, y, InpColorMonthlyPOC, 8, false);
      y += rowHeight;
   }

   // 7. Active Confluences with Star Ratings
   int confCount = ArraySize(g_confluences);
   if(InpEnableConfluence && confCount > 0)
   {
      string confHeader = StringFormat("--- CONFLUENCES DETECTED: %d ---", confCount);
      UpdateDashLabel("ConfHeader", confHeader, x, y, clrLimeGreen, 8, true);
      y += rowHeight;

      for(int i = 0; i < MathMin(confCount, 2); i++)
      {
         string cDesc = StringFormat("* %s & %s @ %s [★%d]",
                                     g_confluences[i].name1,
                                     g_confluences[i].name2,
                                     DoubleToString(g_confluences[i].midPrice, Digits),
                                     g_confluences[i].stars);
         UpdateDashLabel("Conf_" + IntegerToString(i), cDesc, x, y, InpConfluenceColor, 8, false);
         y += rowHeight;
      }
   }
   else
   {
      UpdateDashLabel("ConfHeader", "Confluences: None within threshold", x, y, clrGray, 8, false);
      for(int i = 0; i < 2; i++)
      {
         ObjectDelete(0, PREFIX + "HUD_Conf_" + IntegerToString(i));
      }
      y += rowHeight;
   }

   // 8. Latest Entry Sign Status & R:R Summary
   string sigStr = "ENTRY SIGN: WAITING...";
   color  sigClr = clrDarkGray;
   if(g_activePlan.isActive)
   {
      sigStr = StringFormat("PLAN: %s | R:R 1:%.1f | TP1: %s",
                            g_activePlan.direction,
                            g_activePlan.rr1,
                            DoubleToString(g_activePlan.tp1Price, Digits));
      sigClr = (g_activePlan.direction == "BUY") ? clrLime : clrRed;
   }
   else if(g_lastSignalType != "NONE")
   {
      sigStr = StringFormat("ENTRY SIGN: %s @ %s", g_lastSignalType, DoubleToString(g_lastSignalPrice, Digits));
      sigClr = (g_lastSignalType == "BUY") ? clrLime : clrRed;
   }
   UpdateDashLabel("EntrySign", sigStr, x, y, sigClr, 8, true);
}

//+------------------------------------------------------------------+
//| Check and Trigger Confluence Entry Alerts                        |
//+------------------------------------------------------------------+
void CheckConfluenceAlerts()
{
   if(ArraySize(g_confluences) == 0) return;

   if(Time[0] == g_lastAlertTime) return;

   double pipSize = GetPipSize();
   double threshold = InpConfluenceThreshold * pipSize;

   for(int i = 0; i < ArraySize(g_confluences); i++)
   {
      double dist = MathAbs(Bid - g_confluences[i].midPrice);
      if(dist <= threshold)
      {
         string msg = StringFormat("[NF Trades MTF VP] %s TEST on %s: %s + %s at %s!",
                                   g_confluences[i].ratingStr,
                                   Symbol(),
                                   g_confluences[i].name1,
                                   g_confluences[i].name2,
                                   DoubleToString(g_confluences[i].midPrice, Digits));

         if(InpAlertPopup) Alert(msg);
         if(InpAlertSound) PlaySound(InpSoundFile);

         g_lastAlertTime = Time[0];
         break;
      }
   }
}
//+------------------------------------------------------------------+
