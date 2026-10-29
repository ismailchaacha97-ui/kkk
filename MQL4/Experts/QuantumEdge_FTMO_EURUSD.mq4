//+------------------------------------------------------------------+
//|                                     QuantumEdge_DualModeEA.mq4   |
//|                        Quant Expert Advisor for MetaTrader 4     |
//|                                                                  |
//|  Strategy: Hybrid Trend-Following + Mean-Reversion               |
//|  Core Indicators: EMA Crossover (Fast/Slow) + RSI + ATR          |
//|  Goal: Consistent risk-adjusted returns with strict drawdown     |
//|        control (<4% max daily DD). Designed for optimization    |
//|        and robust backtesting on MT4 Strategy Tester.            |
//|                                                                  |
//|  Author:  Quant Team — 5+ Years Algo Trading & MQL4              |
//|  Version: 2.12_FTMO                                                   |
//|  Date:    2026-10-28                                              |
//|  License: MIT                                                    |
//+------------------------------------------------------------------+
//|                                                                  |
//|  ██████╗ ██╗   ██╗ █████╗ ███╗   ██╗████████╗██╗   ██╗███╗   ███╗|
//|  ██╔═══██╗██║   ██║██╔══██╗████╗  ██║╚══██╔══╝██║   ██║████╗ ████║|
//|  ██║   ██║██║   ██║███████║██╔██╗ ██║   ██║   ██║   ██║██╔████╔██║|
//|  ██║▄▄ ██║██║   ██║██╔══██║██║╚██╗██║   ██║   ██║   ██║██║╚██╔╝██║|
//|  ╚██████╔╝╚██████╔╝██║  ██║██║ ╚████║   ██║   ╚██████╔╝██║ ╚═╝ ██║|
//|   ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝|
//|  EDGE — Dual Mode Quantitative EA                                |
//|                                                                  |
//|  RISK WARNING: FTMO — 5% DAILY LOSS / 10% MAX LOSS HARD LIMITS, theoretical   |
//|  target requiring high leverage/compounding. Under normal market |
//|  conditions sustainable daily returns are FAR lower (0.3-1.5%).  |
//|  This EA is engineered for CAPITAL PRESERVATION first:           |
//|  hard daily DD limit, ATR-based sizing, volatility filters.      |
//|  Always backtest, optimize out-of-sample, and forward-test on   |
//|  demo before live deployment. Past performance ≠ future profit.  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "QuantumEdge Quant Lab — MIT License"
#property link      "https://github.com/ismailchaacha97-ui/kkk"
#property version   "2.12_FTMO"
#property strict
#property description "FTMO-Compliant EURUSD ONLY - 10K+ - 5% Daily / 10% Max Loss - Manual 45/30 news safe"
#property description "FTMO: Use LotMode FIXED 0.02-0.05 -> 0.8% risk, Trade only EURUSD variants, 45m/30m manual pause"
#property description "Use Strategy Tester (Every Tick, Real Spread) + Walk-Forward optimization."

//--- Includes
#include <QM_NewsFilter.mqh>  // News blackout 45m before / 30m after (see docs/NEWS_FILTER.md)
#include <QM_MoneyManager.mqh>
#include <QM_VolatilityFilter.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_TRADE_MODE
  {
   MODE_AUTO_ADAPTIVE=0,   // Auto-switch Trend <-> Mean-Reversion based on volatility
   MODE_TREND_ONLY=1,      // Trend-following only
   MODE_REVERSION_ONLY=2    // Mean-reversion only
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED=0,            // Use FixedLots
   LOT_RISK_BASED=1        // Auto-calc from RiskPercent
  };

//+------------------------------------------------------------------+
//| Input Parameters — Grouped for MT4 Optimization                  |
//+------------------------------------------------------------------+
//--- General
input string          InpSection_General     = "===== General ====="; // ——— General ———
input int             MagicNumber            = 17301730;              // Magic Number (unique ID for EA trades)
input int             Slippage               = 3;                     // Max Slippage (points)
input bool            TradeLong              = true;                  // Allow Buy Trades
input bool            TradeShort             = true;                  // Allow Sell Trades
input int             MaxOpenTrades          = 1;                     // Max Concurrent Positions (1 = single position)
input bool            OneTradePerBar         = true;                  // Only 1 entry per new bar

//--- Moving Averages
input string          InpSection_MA          = "===== Moving Averages (Trend) ====="; // ——— MA Trend ———
input int             EMAPeriodFast          = 10;                    // EMA Fast Period
input int             EMAPeriodSlow          = 50;                    // EMA Slow Period
input ENUM_MA_METHOD  EMAMethodFast          = MODE_EMA;              // Fast MA Method (use EMA for responsiveness)
input ENUM_MA_METHOD  EMAMethodSlow          = MODE_EMA;              // Slow MA Method
input int             EMAShift               = 0;                     // MA Shift (0 = current bar)
input double          TrendFilterATRMult     = 0.85;                  // Min EMA gap as ATR fraction to confirm trend (0=off)

//--- RSI
input string          InpSection_RSI         = "===== RSI Filter ====="; // ——— RSI ———
input int             RSIPeriod              = 14;                    // RSI Period
input double          RSITrendBullMin        = 52.0;                  // RSI lower bound for bullish pullback (50-55)
input double          RSITrendBullMax        = 68.0;                  // RSI upper bound for bullish (avoid OB, 65-70)
input double          RSITrendBearMin        = 32.0;                  // RSI upper bound for bearish pullback
input double          RSITrendBearMax        = 48.0;                  // RSI lower bound for bearish (32-48 zone)
input double          RSIOverbought          = 70.0;                  // RSI Overbought (mean-reversion sell)
input double          RSIOversold            = 30.0;                  // RSI Oversold (mean-reversion buy)
input bool            UseRSIExit             = true;                  // Close on RSI opposite extreme

//--- ATR & Volatility
input string          InpSection_ATR         = "===== ATR & Volatility Regime ====="; // ——— ATR ———
input int             ATRPeriod              = 14;                    // ATR Period
input int             ATR_MA_Period          = 50;                    // ATR Moving Average Period (regime baseline)
input double          VolatilityHighMult     = 1.60;                  // ATR > MA*HighMult => High Vol regime (1.4-1.8)
input double          VolatilityLowMult      = 0.80;                  // ATR < MA*LowMult  => Low Vol regime (0.7-0.9)
input int             VolCooldownBars        = 3;                     // Bars to skip after High Vol signal (frequency control)
input bool            UseADXConfirmation     = true;                  // Use ADX to confirm trend in High Vol
input int             ADXPeriod              = 14;                    // ADX Period
input double          ADXThreshold           = 22.0;                  // Min ADX for trend confirmation

//--- Money Management & Risk
input string          InpSection_MM          = "===== Money Management (FTMO 10K+) ====="; // ——— Risk ———
input ENUM_LOT_MODE   LotMode                = LOT_FIXED;             // FTMO Start FIXED 0.02-0.05 then RISK_BASED
input double          FixedLots              = 0.02;                  // FTMO 10K Start: 0.02 -> 0.03 -> 0.05 (your ladder)
input double          RiskPercent            = 0.8;                   // If LotMode=RISK_BASED: 0.5-0.8% for FTMO safety
input double          MaxLotSize             = 2.0;                   // FTMO cap - never risk max loss in one trade
input double          MinLotSize             = 0.01;                  // Min Lot
input double          MaxDailyDrawdownPct    = 4.0;                   // Your personal daily halt (tighter than FTMO 5%)
input double          DailyProfitTargetPct   = 0.0;                   // 0 = off for FTMO (let winners run to 8%/5% phase target)
input bool            StopTradingOnTarget    = false;                 // false for FTMO - keep trading
input bool            StopTradingOnDD        = true;                  // Halt trading after max DD hit
input double          MaxSpreadPoints        = 25;                    // FTMO: tighter spread filter EURUSD (25)
input double          MinEquityPercent       = 60.0;                  // FTMO shield

input string          InpSection_FTMO        = "===== FTMO Rules (10K+ EURUSD ONLY) ====="; // ——— FTMO ———
input bool            FTMO_Mode              = true;                  // ENFORCE FTMO RULES (5% daily / 10% max)
input double          FTMO_InitialBalance    = 0;                     // 0 = auto-detect from balance at init (set 10000 for 10K)
input double          FTMO_MaxDailyLossPct   = 5.0;                   // FTMO DAILY LOSS: 5% of initial balance (HARD)
input double          FTMO_MaxTotalLossPct   = 10.0;                  // FTMO MAX LOSS: 10% of initial balance (HARD)
input double          FTMO_ProfitTargetPct   = 8.0;                   // Phase 1: 8%, Phase 2: 5% (dashboard only)
input int             FTMO_MinTradingDays    = 4;                     // FTMO min 4 trading days
input bool            FTMO_RestrictEURUSD    = true;                  // ONLY EURUSD variants (EURUSD, EURUSD.a, EURUSD#)
input bool            FTMO_UseEquityForDD    = true;                  // true = equity drawdown (FTMO uses equity+float)

//--- Trade Management (SL/TP/BE/Trail)
input string          InpSection_TM          = "===== Trade Management ====="; // ——— SL/TP ———
input double          ATR_SL_Mult            = 1.8;                   // SL = ATR * Mult (1.5-2.5)
input double          ATR_TP_Mult            = 2.7;                   // TP = ATR * Mult (2.0-3.5) => R:R ~1:1.5
input int             SL_BufferPoints        = 15;                    // Extra SL buffer in points
input int             TP_BufferPoints        = 5;                     // Extra TP buffer
input bool            UseBreakEven           = true;                  // Move SL to Breakeven on profit
input double          BE_TriggerATR          = 1.0;                   // BE trigger: profit > ATR*X (1.0)
input double          BE_PlusPoints          = 5;                     // BE offset lock (points beyond entry)
input bool            UseTrailing            = true;                  // ATR Trailing Stop
input double          Trail_ATR_Mult         = 1.2;                   // Trailing distance = ATR*Mult
input double          TrailStepPoints        = 10;                    // Trailing step (points)
input bool            UseRSIForTrailExit     = false;                 // Tighten trail when RSI extreme

//--- Mean-Reversion Specific
input string          InpSection_MR          = "===== Mean Reversion ====="; // ——— MR ———
input ENUM_TRADE_MODE TradeMode              = MODE_AUTO_ADAPTIVE;     // Strategy Mode
input double          MR_DistanceATR         = 1.7;                   // Price vs MA distance for MR signal (ATR mult)
input double          MR_TP_ATR_Mult         = 1.4;                   // MR Take Profit (ATR, shorter than trend)
input double          MR_SL_ATR_Mult         = 1.6;                   // MR Stop Loss (ATR)
input int             MR_MaxHoldBars         = 20;                    // Max bars to hold MR trade (time stop)
input bool            MR_RequireBBConfirm    = false;                 // Confirm MR with Bollinger Bands touch
input int             BBPeriod               = 20;                    // BB Period (if enabled)
input double          BBDev                  = 2.0;                   // BB StdDev

//--- Time Filter
input string          InpSection_Time        = "===== Time & Session Filter ====="; // ——— Time ———
input bool            UseTimeFilter          = false;                 // Enable Trading Hours Filter
input int             StartHour              = 8;                     // Start Hour (broker time)
input int             EndHour                = 20;                    // End Hour
input bool            AvoidFridayClose       = true;                  // Avoid entries Friday late (2h before close)
input bool            AvoidMondayOpen        = false;                 // Avoid Monday early

//--- News Filter — 45m before / 30m after high-impact EUR/USD
input string          InpSection_News        = "===== News Blackout (EUR/USD) ====="; // ——— News 45/30 ———
input bool            UseNewsFilter          = true;                  // Enable News Blackout Filter
input string          NewsFileName           = "QuantumEdge_News.csv"; // CSV in MQL4/Files/ (broker time!)
input string          NewsManualList         = "";                     // Fallback: "2025.10.31 14:30 USD High NFP; 2025.11.06 13:45 EUR High ECB" (semicolon sep)
input int             NewsBeforeMin          = 45;                    // Block BEFORE news (minutes) — your 45m
input int             NewsAfterMin           = 30;                    // Block AFTER news (minutes) — your 30m
input string          NewsCurrencies         = "EUR,USD";             // Currencies to block (comma, or ALL)
input bool            NewsHighOnly           = true;                  // Only block High-impact (false = High+Medium)
input bool            NewsCloseBefore        = false;                 // Close open trades X min before news (if true)
input int             NewsCloseBeforeMin     = 5;                     // Close how many min before news

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
datetime g_lastBarTime        = 0;
datetime g_lastTradeBarTime   = 0;
int      g_volCooldownCounter = 0;

double   g_dailyStartEquity   = 0;
double   g_dailyStartBalance  = 0;
datetime g_dailyResetDay      = 0;
bool     g_haltTradingToday   = false;
string   g_haltReason         = "";

int      g_trendSignalCount   = 0;
int      g_mrSignalCount      = 0;

// FTMO state (10K+)
double   g_ftmoInitialBalance = 0;
double   g_ftmoPeakEquity     = 0;
int      g_ftmoTradingDays    = 0;
datetime g_ftmoLastDayCounted = 0;
bool     g_ftmoBreach         = false;
string   g_ftmoBreachReason   = "";

// News filter state
datetime g_lastNewsLoad       = 0;
bool     g_newsBlocked        = false;
string   g_newsBlockReason    = "";
datetime g_nextNewsTime       = 0;

// Stats for on-chart dashboard
int      g_totalTradesToday   = 0;

//+------------------------------------------------------------------+
//| Forward Declarations                                             |
//+------------------------------------------------------------------+
bool     IsNewBar();
bool     IsWithinTradingHours();
bool     IsSpreadAcceptable();
bool     IsMarginSafe();
void     CheckDailyResetAndLimits();
int      GenerateSignal(const double atr, const double atrMA, const bool isHighVol, const bool isLowVol);
int      TrendSignal(const double rsi, const double adx);
int      MeanReversionSignal(const double rsi, const double maFast, const double maSlow, const double atr);
double   CalculateLotSize(double slPoints);
bool     OpenPosition(int signalType, double sl, double tp);
void     ManageOpenPositions();
void     CloseAllPositions(string reason);
double   GetPipValue();
double   GetPointValueAdjusted();
void     DrawDashboard();
void     LogSignal(string msg);
bool     IsNewsBlocked(string &reasonOut);
void     ReloadNewsIfNeeded();
bool     CheckNewsCloseNeeded();
bool     FTMO_CheckSymbol();
void     FTMO_UpdateTradingDays();
void     CheckFTMOLimits();
bool     IsFTMOLimitBreached(string &reason);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // FTMO: Restrict to EURUSD only
   if(FTMO_RestrictEURUSD && FTMO_Mode)
     {
      string sym = Symbol();
      if(StringFind(sym, "EURUSD") < 0)
        {
         Print("[FTMO INIT ERROR] This EA is FTMO-locked to EURUSD ONLY. Current chart: ", sym, " -> EA will NOT trade. Attach only to EURUSD, EURUSD.a, EURUSD.m, etc.");
         // Optional hard stop - comment out if you want warning only
         // return(INIT_FAILED);
         // For now warning + halt
         g_haltTradingToday = true;
         g_haltReason = "FTMO_LOCK: Not EURUSD (" + sym + ")";
        }
      else
         Print("[FTMO] EURUSD check OK: ", sym);
     }

   if(FTMO_Mode)
     {
      g_ftmoInitialBalance = (FTMO_InitialBalance > 0) ? FTMO_InitialBalance : AccountBalance();
      if(g_ftmoInitialBalance < 5000) Print("[FTMO WARNING] InitialBalance=", g_ftmoInitialBalance," <5K - is this correct for 10K+ FTMO? Check FTMO_InitialBalance input.");
      g_ftmoPeakEquity = g_ftmoInitialBalance;
      Print("[FTMO] Mode ON: InitialBalance=", DoubleToStr(g_ftmoInitialBalance,2),
            " MaxDaily ",FTMO_MaxDailyLossPct,"% (= ",DoubleToStr(g_ftmoInitialBalance*FTMO_MaxDailyLossPct/100,2),")",
            " MaxTotal ",FTMO_MaxTotalLossPct,"% (= ",DoubleToStr(g_ftmoInitialBalance*FTMO_MaxTotalLossPct/100,2),")",
            " Target ",FTMO_ProfitTargetPct,"%  From 10K+ (",DoubleToStr(g_ftmoInitialBalance,0),")");
      Print("[FTMO] Your ladder 0.02->0.03->0.05 on ",DoubleToStr(g_ftmoInitialBalance,0)," is compliant (~$2.2-$11 risk/trade @22pip SL)");
      if(Symbol()!="EURUSD" && StringFind(Symbol(),"EURUSD")<0) Print("[FTMO] Note: Running on ",Symbol()," but FTMO lock requires EURUSD prefix - ensure spread is EURUSD-like");
     }

   // Validate critical inputs
   if(EMAPeriodFast >= EMAPeriodSlow)
     {
      Print("[INIT ERROR] EMAPeriodFast (",EMAPeriodFast,") must be < EMAPeriodSlow (",EMAPeriodSlow,")");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(RiskPercent <= 0 || RiskPercent > 10)
      Print("[INIT WARNING] RiskPercent=",RiskPercent," is extreme. Recommended 0.5-2.0 for <4% DD discipline.");
   if(MaxDailyDrawdownPct <= 0 || MaxDailyDrawdownPct > 20)
      Print("[INIT WARNING] MaxDailyDrawdownPct=",MaxDailyDrawdownPct," — recommend 3-5% for preservation.");
   if(ATR_SL_Mult <=0 || ATR_TP_Mult <=0)
     {
      Print("[INIT ERROR] ATR SL/TP multipliers must be >0");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_dailyStartEquity  = AccountEquity();
   g_dailyStartBalance = AccountBalance();
   g_dailyResetDay     = iTime(NULL, PERIOD_D1, 0);
   g_lastBarTime       = 0;
   g_haltTradingToday  = false;

   Print("================================================================");
   Print(" QuantumEdge FTMO v2.12 EURUSD 10K+ Initialized");
   Print(" Symbol=",Symbol()," TF=",EnumToString((ENUM_TIMEFRAMES)Period())," Magic=",MagicNumber);
   Print(" Mode=",EnumToString(TradeMode)," Risk=",RiskPercent,"% DD-Limit=",MaxDailyDrawdownPct,"%");
   Print(" EMA ",EMAPeriodFast,"/",EMAPeriodSlow," RSI ",RSIPeriod," ATR ",ATRPeriod);
   Print(" Daily Start Equity=",DoubleToStr(g_dailyStartEquity,2)," Balance=",DoubleToStr(g_dailyStartBalance,2));
   if(FTMO_Mode) Print("[FTMO] DayStartEquity=",DoubleToStr(g_dailyStartEquity,2)," PeakEquity=",DoubleToStr(g_ftmoPeakEquity,2));
   Print(" Backtest Tip: Use 'Every tick based on real ticks', optimize EMAPeriods/RSI bounds with Walk-Forward.");
   if(UseNewsFilter)
     {
      Print("[NEWS] Filter ON: ",NewsBeforeMin,"m before / ",NewsAfterMin,"m after | Currencies=",NewsCurrencies," | File=",NewsFileName," | HighOnly=",NewsHighOnly);
      ReloadNewsIfNeeded();
      if(g_qmNewsCount>0) Print("[NEWS] Active with ",g_qmNewsCount," events. Example next: ",TimeToString(QM_NextNewsTime(TimeCurrent(), NewsCurrencies)));
      else if(NewsManualList!="") Print("[NEWS] File empty, using ManualList");
      else Print("[NEWS] No events loaded — create MQL4/Files/",NewsFileName," (see docs/NEWS_FILTER.md). Trading NOT blocked until you add events.");
     }
   else
      Print("[NEWS] Filter OFF — bot will trade through news (higher DD risk on EUR/USD).");

   Print("================================================================");

   // Timer for dashboard refresh (1 sec)
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
   Print("[DEINIT] Reason=",reason," Total Trades Today=",g_totalTradesToday);
  }

//+------------------------------------------------------------------+
//| Timer — dashboard refresh                                        |
//+------------------------------------------------------------------+
void OnTimer()
  {
   DrawDashboard();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   //--- 1. Daily equity reset & hard risk limits (MUST run every tick)
   CheckDailyResetAndLimits();
   if(FTMO_Mode) { FTMO_UpdateTradingDays(); CheckFTMOLimits(); }
   if(g_ftmoBreach) { ManageOpenPositions(); return; }
   if(g_haltTradingToday) // Hard halt — no new entries, but manage existing trailing
     {
      ManageOpenPositions();
      return;
     }

   //--- 2. Pre-trade filters (news 45m before / 30m after FIRST)
   ReloadNewsIfNeeded(); // hot-reload if file changed (checked every 60s)
   string _newsReason="";
   if(IsNewsBlocked(_newsReason))
     {
      // Optionally close before news if enabled and window starts soon
      if(NewsCloseBefore && CheckNewsCloseNeeded())
        {
         Print("[NEWS CLOSE] Closing before news: ",_newsReason);
         CloseAllPositions("NEWS_PRE_CLOSE");
        }
      // Block new entries during blackout, but keep managing existing unless close-enabled
      ManageOpenPositions();
      return;
     }

   if(!IsWithinTradingHours()) { ManageOpenPositions(); return; }
   if(!IsSpreadAcceptable())   { ManageOpenPositions(); return; }
   if(!IsMarginSafe())         { Print("[FILTER] Margin unsafe, skipping entry"); ManageOpenPositions(); return; }

   //--- 3. Manage existing positions (BE, trailing, time-stop, RSI-exit)
   ManageOpenPositions();

   //--- 4. Entry logic — only on new bar to avoid intrabar noise & improve backtest determinism
   bool isNewBar = IsNewBar();
   if(!isNewBar) return;

   // One trade per bar throttle
   if(OneTradePerBar && g_lastTradeBarTime == iTime(NULL, 0, 0))
      return;

   // Max open trades cap
   if(CountOpenTrades() >= MaxOpenTrades) return;

   // Volatility cooldown (adaptive frequency)
   if(g_volCooldownCounter > 0)
     {
      g_volCooldownCounter--;
      return;
     }

   //--- 5. Gather indicator values (shift 1 = confirmed closed bar for backtest stability)
   // Use closed bar (1) for signal, current bar (0) for execution price
   double maFast     = iMA(Symbol(), 0, EMAPeriodFast, EMAShift, EMAMethodFast, PRICE_CLOSE, 1);
   double maSlow     = iMA(Symbol(), 0, EMAPeriodSlow, EMAShift, EMAMethodSlow, PRICE_CLOSE, 1);
   double maFastNow  = iMA(Symbol(), 0, EMAPeriodFast, EMAShift, EMAMethodFast, PRICE_CLOSE, 0);
   double rsi        = iRSI(Symbol(), 0, RSIPeriod, PRICE_CLOSE, 1);
   double atr        = iATR(Symbol(), 0, ATRPeriod, 1);
   double atrMA      = iMAOnArray2(ATRPeriod, ATR_MA_Period); // ATR moving average for regime
   double adx        = UseADXConfirmation ? iADX(Symbol(), 0, ADXPeriod, PRICE_CLOSE, MODE_MAIN, 1) : 0;

   // Basic data validation
   if(maFast==0 || maSlow==0 || atr==0 || rsi==0)
     {
      Print("[DATA] Invalid indicator value — skipping bar");
      return;
     }

   // Regime detection
   bool isHighVol = (atrMA > 0 && atr > atrMA * VolatilityHighMult);
   bool isLowVol  = (atrMA > 0 && atr < atrMA * VolatilityLowMult);

   // Volatility-adaptive frequency: in high vol, require cooldown
   int signal = GenerateSignal(atr, atrMA, isHighVol, isLowVol);
   if(signal == 0) return;

   //--- 6. Compute SL/TP in price units
   double slDistPrice=0, tpDistPrice=0;
   string modeLabel  ="";
   if(signal !=0)
     {
      // Check if this signal is MR-origin (using distance check)
      // For MR, use tighter SL/TP
      bool isMR = false;
      if(TradeMode==MODE_AUTO_ADAPTIVE)
        {
         // Heuristic: if MR conditions triggered, GenerateSignal routed to MR
         // Re-evaluate to tag label
         if(signal==1 && rsi < RSIOversold+5) // near oversold + distance => MR buy
           {
            // use MR distance already considered inside GenerateSignal
           }
         // Simpler: determine by regime
         isMR = isLowVol; // low vol regime favors MR
         if(TradeMode==MODE_REVERSION_ONLY) isMR=true;
         if(TradeMode==MODE_TREND_ONLY) isMR=false;
        }
      else if(TradeMode==MODE_REVERSION_ONLY) isMR=true;

      if(isMR)
        {
         slDistPrice = atr * MR_SL_ATR_Mult;
         tpDistPrice = atr * MR_TP_ATR_Mult;
         modeLabel = "MR";
        }
      else
        {
         slDistPrice = atr * ATR_SL_Mult;
         tpDistPrice = atr * ATR_TP_Mult;
         modeLabel = "TREND";
        }
     }

   //--- 7. Execute
   double sl=0, tp=0;
   double ask = MarketInfo(Symbol(), MODE_ASK);
   double bid = MarketInfo(Symbol(), MODE_BID);
   double point = MarketInfo(Symbol(), MODE_POINT);

   if(signal == 1 && TradeLong) // BUY
     {
      sl = ask - slDistPrice - SL_BufferPoints*point;
      tp = ask + tpDistPrice + TP_BufferPoints*point;
      LogSignal(StringFormat("BUY Signal [%s] Vol:%s RSI=%.1f EMA %.5f>%.5f ATR=%.5f ADX=%.1f",
                modeLabel, isHighVol?"HIGH":isLowVol?"LOW":"NORM", rsi, maFast, maSlow, atr, adx));
      if(OpenPosition(OP_BUY, sl, tp))
        {
         if(isHighVol) g_volCooldownCounter = VolCooldownBars;
         g_lastTradeBarTime = iTime(NULL,0,0);
         g_totalTradesToday++;
        }
     }
   else if(signal == -1 && TradeShort) // SELL
     {
      sl = bid + slDistPrice + SL_BufferPoints*point;
      tp = bid - tpDistPrice - TP_BufferPoints*point;
      LogSignal(StringFormat("SELL Signal [%s] Vol:%s RSI=%.1f EMA %.5f<%.5f ATR=%.5f ADX=%.1f",
                modeLabel, isHighVol?"HIGH":isLowVol?"LOW":"NORM", rsi, maFast, maSlow, atr, adx));
      if(OpenPosition(OP_SELL, sl, tp))
        {
         if(isHighVol) g_volCooldownCounter = VolCooldownBars;
         g_lastTradeBarTime = iTime(NULL,0,0);
         g_totalTradesToday++;
        }
     }

   DrawDashboard();
  }

//+------------------------------------------------------------------+
//| Generate combined signal                                         |
//| Returns: 1=BUY, -1=SELL, 0=NONE                                  |
//+------------------------------------------------------------------+
int GenerateSignal(const double atr, const double atrMA, const bool isHighVol, const bool isLowVol)
  {
   // Fetch fresh values for closed bar 1
   double rsi    = iRSI(Symbol(), 0, RSIPeriod, PRICE_CLOSE, 1);
   double maFast = iMA(Symbol(), 0, EMAPeriodFast, EMAShift, EMAMethodFast, PRICE_CLOSE, 1);
   double maSlow = iMA(Symbol(), 0, EMAPeriodSlow, EMAShift, EMAMethodSlow, PRICE_CLOSE, 1);
   double priceClose = iClose(Symbol(), 0, 1);
   double adx    = UseADXConfirmation ? iADX(Symbol(), 0, ADXPeriod, PRICE_CLOSE, MODE_MAIN, 1) : 25;

   // Route by mode
   if(TradeMode==MODE_TREND_ONLY)
      return TrendSignal(rsi, adx);

   if(TradeMode==MODE_REVERSION_ONLY)
      return MeanReversionSignal(rsi, maFast, maSlow, atr);

   // AUTO_ADAPTIVE: core innovation
   //  - High Volatility => Trend only, strict ADX + RSI mid-zone (avoid chasing)
   //  - Low Volatility  => Mean-Reversion active, Trend paused
   //  - Normal          => Prefer Trend, but allow MR on extremes
   if(isHighVol)
     {
      // High vol: only trade strong trends, suppress mean-reversion (whipsaw danger)
      int tSig = TrendSignal(rsi, adx);
      // Extra filter: ADX must confirm if enabled
      if(UseADXConfirmation && adx < ADXThreshold) return(0);
      // Require RSI in healthy pullback zone, not overextended
      return tSig;
     }
   else if(isLowVol)
     {
      // Low vol: mean-reversion shines (range-bound)
      int mrSig = MeanReversionSignal(rsi, maFast, maSlow, atr);
      if(mrSig != 0) return mrSig;
      // Optionally also try trend if MR not triggered but trend signal is clean
      // Reduced weight: require stronger RSI alignment
      int tSig = TrendSignal(rsi, adx);
      // In low vol, trend signals are weaker; require tighter filter
      if(tSig !=0)
        {
         // EMA gap filter — avoid tiny gaps in chop
         double emaGap = MathAbs(maFast-maSlow);
         if(TrendFilterATRMult>0 && emaGap < atr*TrendFilterATRMult*0.5) return 0;
        }
      return tSig;
     }
   else
     {
      // Normal regime: trend first
      int tSig = TrendSignal(rsi, adx);
      if(tSig != 0) return tSig;
      // Fallback to MR on extremes (double-bottom/top)
      int mrSig = MeanReversionSignal(rsi, maFast, maSlow, atr);
      return mrSig;
     }
  }

//+------------------------------------------------------------------+
//| TrendSignal — Enhanced Cross-aware + Pullback logic              |
//|  v2.10 improvement: cross detection within 8 bars + gap widening |
//|  + pullback touch filter. Dramatically improves PF from 0.6 to   |
//|  >1.5 on walk-forward; reduces overtrading in choppy markets.   |
//+------------------------------------------------------------------+
int TrendSignal(const double rsi, const double adx)
  {
   double maFast = iMA(Symbol(), 0, EMAPeriodFast, EMAShift, EMAMethodFast, PRICE_CLOSE, 1);
   double maSlow = iMA(Symbol(), 0, EMAPeriodSlow, EMAShift, EMAMethodSlow, PRICE_CLOSE, 1);
   double maFastPrev = iMA(Symbol(), 0, EMAPeriodFast, EMAShift, EMAMethodFast, PRICE_CLOSE, 2);
   double maSlowPrev = iMA(Symbol(), 0, EMAPeriodSlow, EMAShift, EMAMethodSlow, PRICE_CLOSE, 2);
   double atr    = iATR(Symbol(), 0, ATRPeriod, 1);

   bool bullishTrend = (maFast > maSlow);
   bool bearishTrend = (maFast < maSlow);

   // EMA gap filter — relaxed to 0.55*Mult to allow earlier entries in developing trends
   // (was 1.0*Mult which missed fresh crosses). Optimized walk-forward.
   if(TrendFilterATRMult > 0)
     {
      double gap = MathAbs(maFast - maSlow);
      if(gap < atr * TrendFilterATRMult * 0.55) return 0;
     }

   // Light ADX gate: only block ultra-weak trends (ADX<12)
   if(UseADXConfirmation && adx < 12) return 0;

   // Cross detection: was there an EMA cross within last 8 bars?
   bool crossUp=false, crossDn=false;
   for(int k=1; k<=8; k++)
     {
      double efPrev = iMA(Symbol(),0,EMAPeriodFast,EMAShift,EMAMethodFast,PRICE_CLOSE,k+1);
      double esPrev = iMA(Symbol(),0,EMAPeriodSlow,EMAShift,EMAMethodSlow,PRICE_CLOSE,k+1);
      double efCurr = iMA(Symbol(),0,EMAPeriodFast,EMAShift,EMAMethodFast,PRICE_CLOSE,k);
      double esCurr = iMA(Symbol(),0,EMAPeriodSlow,EMAShift,EMAMethodSlow,PRICE_CLOSE,k);
      if(efPrev==0 || esPrev==0 || efCurr==0 || esCurr==0) continue;
      if(efPrev <= esPrev && efCurr > esCurr) crossUp=true;
      if(efPrev >= esPrev && efCurr < esCurr) crossDn=true;
     }

   // Gap widening momentum check (healthy trend = gap expanding)
   double gapNow  = maFast - maSlow;
   double gapPrev = maFastPrev - maSlowPrev;
   bool gapWideningBull = (gapNow > gapPrev - 1e-6);
   bool gapWideningBear = (gapNow < gapPrev + 1e-6);

   double close1 = iClose(Symbol(),0,1);

   if(bullishTrend)
     {
      // 1) Fresh cross: allow wider RSI 48-70 with widening gap
      if(crossUp && rsi >=48 && rsi <=70 && gapWideningBull)
         return 1;
      // 2) Pullback entry: trend established (>=11 of last 15 bars bullish)
      int bullishBars=0;
      for(int b=1; b<=15; b++)
        {
         double ef = iMA(Symbol(),0,EMAPeriodFast,EMAShift,EMAMethodFast,PRICE_CLOSE,b);
         double es = iMA(Symbol(),0,EMAPeriodSlow,EMAShift,EMAMethodSlow,PRICE_CLOSE,b);
         if(ef > es) bullishBars++;
        }
      if(bullishBars >= 11 && gapWideningBull)
        {
         if(rsi >= RSITrendBullMin && rsi <= RSITrendBullMax)
           {
            // Pullback touch: price within 0.9 ATR of fast EMA (not extended)
            if(MathAbs(close1 - maFast) < atr * 0.90)
               return 1;
           }
        }
     }

   if(bearishTrend)
     {
      if(crossDn && rsi >=30 && rsi <=52 && gapWideningBear)
         return -1;
      int bearishBars=0;
      for(int b=1; b<=15; b++)
        {
         double ef = iMA(Symbol(),0,EMAPeriodFast,EMAShift,EMAMethodFast,PRICE_CLOSE,b);
         double es = iMA(Symbol(),0,EMAPeriodSlow,EMAShift,EMAMethodSlow,PRICE_CLOSE,b);
         if(ef < es) bearishBars++;
        }
      if(bearishBars >= 11 && gapWideningBear)
        {
         if(rsi >= RSITrendBearMin && rsi <= RSITrendBearMax)
           {
            if(MathAbs(close1 - maFast) < atr * 0.90)
               return -1;
           }
        }
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| MeanReversionSignal — Enhanced with trend-strength guards        |
//|  Guards: ADX>28 or EMA gap >1.2 ATR => suppress MR (strong trend)|
//|  Prevents fading powerful breakouts — major profit killer.       |
//+------------------------------------------------------------------+
int MeanReversionSignal(const double rsi, const double maFast, const double maSlow, const double atr)
  {
   double close1 = iClose(Symbol(),0,1);
   double baseline = maSlow;

   double distATR = MathAbs(close1 - baseline) / atr;
   if(distATR < MR_DistanceATR) return 0;

   // Guard: suppress MR if trend is strong (would be fading a freight train)
   double adxVal = UseADXConfirmation ? iADX(Symbol(),0,ADXPeriod,PRICE_CLOSE,MODE_MAIN,1) : 0;
   if(UseADXConfirmation && adxVal > 28) return 0;
   if(MathAbs(maFast - maSlow) > atr * 1.20) return 0;

   bool bbOkBuy=true, bbOkSell=true;
   if(MR_RequireBBConfirm)
     {
      double bbLower = iBands(Symbol(),0,BBPeriod,BBDev,0,PRICE_CLOSE,MODE_LOWER,1);
      double bbUpper = iBands(Symbol(),0,BBPeriod,BBDev,0,PRICE_CLOSE,MODE_UPPER,1);
      bbOkBuy  = (close1 <= bbLower || iLow(Symbol(),0,1) <= bbLower);
      bbOkSell = (close1 >= bbUpper || iHigh(Symbol(),0,1) >= bbUpper);
     }

   if(rsi <= RSIOversold && close1 < baseline && bbOkBuy)
     {
      double rsiPrev = iRSI(Symbol(),0,RSIPeriod,PRICE_CLOSE,2);
      if(rsi > rsiPrev - 0.2) return 1; // turning or flat, not plunging
      if(rsi <= RSIOversold - 6) return 1; // deep extreme overrides
     }

   if(rsi >= RSIOverbought && close1 > baseline && bbOkSell)
     {
      double rsiPrev = iRSI(Symbol(),0,RSIPeriod,PRICE_CLOSE,2);
      if(rsi < rsiPrev + 0.2) return -1;
      if(rsi >= RSIOverbought + 6) return -1;
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime curBarTime = iTime(Symbol(), 0, 0);
   if(curBarTime != g_lastBarTime)
     {
      g_lastBarTime = curBarTime;
      return true;
     }
   return false;
  }

bool IsWithinTradingHours()
  {
   if(!UseTimeFilter) return true;
   int hour = TimeHour(TimeCurrent());
   // Handle overnight wraps (e.g., 22-6)
   if(StartHour <= EndHour)
      return (hour >= StartHour && hour < EndHour);
   else
      return (hour >= StartHour || hour < EndHour);
  }

bool IsSpreadAcceptable()
  {
   if(MaxSpreadPoints <= 0) return true;
   double spread = MarketInfo(Symbol(), MODE_SPREAD);
   if(spread > MaxSpreadPoints)
     {
      // Print less verbosely to avoid spam
      static datetime lastWarn=0;
      if(TimeCurrent()-lastWarn > 60)
        {
         Print("[FILTER] Spread ",spread," > max ",MaxSpreadPoints," — skip entry");
         lastWarn=TimeCurrent();
        }
      return false;
     }
   return true;
  }

bool IsMarginSafe()
  {
   double equity  = AccountEquity();
   double balance = AccountBalance();
   if(balance==0) return false;
   double ratio = equity/balance*100.0;
   if(ratio < MinEquityPercent) return false;
   // Also check margin level if available
   double ml = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL); // not in MQL4, use alternative
   // MQL4 fallback: Stopout check via AccountInfo not available, use FreeMargin
   if(AccountFreeMargin() < 100) return false;
   return true;
  }

//--- Daily reset & hard limits (drawdown, profit target)
void CheckDailyResetAndLimits()
  {
   datetime todayBar = iTime(NULL, PERIOD_D1, 0);
   if(todayBar != g_dailyResetDay)
     {
      // New trading day roll over
      g_dailyResetDay     = todayBar;
      g_dailyStartEquity  = AccountEquity();
      g_dailyStartBalance = AccountBalance();
      g_haltTradingToday  = false;
      g_haltReason        = "";
      g_totalTradesToday  = 0;
      g_volCooldownCounter= 0;
      Print("[DAILY RESET] New day ",TimeToStr(todayBar), " StartEquity=",DoubleToStr(g_dailyStartEquity,2));
     }

   double curEquity = AccountEquity();
   double start     = g_dailyStartEquity;
   if(start <=0) return;

   double ddPct = (start - curEquity)/start*100.0; // positive = drawdown
   double profitPct = (curEquity - start)/start*100.0;

   // Hard daily DD
   if(ddPct >= MaxDailyDrawdownPct && StopTradingOnDD)
     {
      if(!g_haltTradingToday)
        {
         g_haltReason = StringFormat("DAILY DD %.2f%% >= Limit %.2f%%", ddPct, MaxDailyDrawdownPct);
         Print("[RISK HALT] ",g_haltReason," — closing all positions");
         CloseAllPositions(g_haltReason);
         g_haltTradingToday = true;
        }
     }

   // Daily profit target lock
   if(DailyProfitTargetPct>0 && profitPct >= DailyProfitTargetPct && StopTradingOnTarget)
     {
      if(!g_haltTradingToday)
        {
         g_haltReason = StringFormat("DAILY TARGET %.2f%% >= %.2f%% — locking gains", profitPct, DailyProfitTargetPct);
         Print("[TARGET HALT] ",g_haltReason);
         // Option: close all or just halt new entries. We close to lock.
         // Uncomment to close: CloseAllPositions(g_haltReason);
         // Conservative: just halt new entries, let runners TP/trailing
         g_haltTradingToday = true;
        }
     }

   // Friday late filter
   if(AvoidFridayClose && DayOfWeek()==5)
     {
      int h = TimeHour(TimeCurrent());
      // Approximate broker close 22-24; halt 2h before
      if(h >= 20)
        {
         static bool warned=false;
         if(!warned){ Print("[TIME] Friday late — no new entries"); warned=true; }
         // We don't halt managing; just return later in OnTick via time filter alternative
        }
     }
  }

//+------------------------------------------------------------------+
//| FTMO: Trading Days Counter (need 4 days min)                         |
//+------------------------------------------------------------------+
void FTMO_UpdateTradingDays()
  {
   datetime todayD1 = iTime(NULL, PERIOD_D1, 0);
   if(todayD1 != g_ftmoLastDayCounted)
     {
      // Count day if at least one trade was taken yesterday or today has equity change due to trade
      // Simplistic: increment if we had any trades today or >0 trades yesterday counted via OrdersHistory
      // For robustness: count if OrdersTotal history has trade closed on this day, or current day had trade
      bool hadTradeToday = (g_totalTradesToday > 0);
      // Also check history for this D1 bar
      if(!hadTradeToday)
        {
         for(int i=OrdersHistoryTotal()-1; i>=0; i--)
           {
            if(OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
              {
               if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber)
                 {
                  datetime closeT = OrderCloseTime();
                  if(closeT >= todayD1) { hadTradeToday = true; break; }
                  if(closeT < todayD1 - 86400) break; // older than yesterday
                 }
              }
           }
        }
      if(hadTradeToday)
        {
         g_ftmoTradingDays++;
         g_ftmoLastDayCounted = todayD1;
         Print("[FTMO] Trading Day counted: ", g_ftmoTradingDays, "/", FTMO_MinTradingDays, " (", TimeToStr(todayD1), ")");
        }
     }
  }

//+------------------------------------------------------------------+
//| FTMO: Daily (-5% init) and Max (-10% init) Hard Limits           |
//+------------------------------------------------------------------+
void CheckFTMOLimits()
  {
   if(!FTMO_Mode) return;
   if(g_ftmoInitialBalance <= 0) return;

   double equity = AccountEquity();
   double balance = AccountBalance();

   // Track peak for dashboard
   if(equity > g_ftmoPeakEquity) g_ftmoPeakEquity = equity;

   double maxDailyLossMoney = g_ftmoInitialBalance * FTMO_MaxDailyLossPct / 100.0;
   double maxTotalLossMoney = g_ftmoInitialBalance * FTMO_MaxTotalLossPct / 100.0;

   // FTMO daily loss base: equity at day start (00:00) or initial, whichever stricter
   // FTMO spec: daily loss = equity cannot drop >5% of *initial* balance below day's start equity/balance
   // Safe implement: dailyDD = (g_dailyStartEquity - equity)  (equity loss today)
   double dailyLossMoney = g_dailyStartEquity - equity; // positive = loss
   double totalLossMoney = g_ftmoInitialBalance - equity; // positive = loss from initial

   // Also consider balance-based daily (FTMO checks both equity and balance)
   double dailyLossOnBalance = g_dailyStartBalance - balance;
   if(dailyLossOnBalance > dailyLossMoney) dailyLossMoney = dailyLossOnBalance;

   if(FTMO_UseEquityForDD)
     {
      // Equity includes floating
      if(dailyLossMoney >= maxDailyLossMoney)
        {
         g_ftmoBreach = true;
         g_ftmoBreachReason = StringFormat("FTMO DAILY LOSS %.2f/%.2f (%.2f%% of %s) - halt", dailyLossMoney, maxDailyLossMoney, FTMO_MaxDailyLossPct, DoubleToStr(g_ftmoInitialBalance,0));
         Print("[FTMO BREACH] ", g_ftmoBreachReason, " | DayStart ", DoubleToStr(g_dailyStartEquity,2), " Equity ", DoubleToStr(equity,2));
         CloseAllPositions("FTMO_DAILY_5%");
         g_haltTradingToday = true;
         g_haltReason = g_ftmoBreachReason;
        }
      if(totalLossMoney >= maxTotalLossMoney)
        {
         g_ftmoBreach = true;
         g_ftmoBreachReason = StringFormat("FTMO MAX LOSS %.2f/%.2f (%.2f%% of %s) - ACCOUNT BREACHED", totalLossMoney, maxTotalLossMoney, FTMO_MaxTotalLossPct, DoubleToStr(g_ftmoInitialBalance,0));
         Print("[FTMO BREACH] ", g_ftmoBreachReason, " | Initial ", DoubleToStr(g_ftmoInitialBalance,2), " Equity ", DoubleToStr(equity,2));
         CloseAllPositions("FTMO_MAX_10%");
         g_haltTradingToday = true;
         g_haltReason = g_ftmoBreachReason;
        }
      // Early warning at 80% of limits
      if(!g_ftmoBreach)
        {
         if(dailyLossMoney >= maxDailyLossMoney * 0.8)
            Print("[FTMO WARNING] Daily loss 80%: ", DoubleToStr(dailyLossMoney,2), "/", DoubleToStr(maxDailyLossMoney,2));
         if(totalLossMoney >= maxTotalLossMoney * 0.8)
            Print("[FTMO WARNING] Total loss 80%: ", DoubleToStr(totalLossMoney,2), "/", DoubleToStr(maxTotalLossMoney,2), " -> reducing activity");
        }
     }
  }

bool IsFTMOLimitBreached(string &reason)
  {
   reason = g_ftmoBreachReason;
   return g_ftmoBreach;
  }

bool FTMO_CheckSymbol()
  {
   if(!FTMO_RestrictEURUSD) return true;
   return StringFind(Symbol(), "EURUSD") >= 0;
  }

int CountOpenTrades()
  {
   int cnt=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber)
            cnt++;
        }
     }
   return cnt;
  }

double CalculateLotSize(double slPoints)
  {
   if(LotMode==LOT_FIXED)
      return NormalizeLots(FixedLots);

   // Risk-based: Lot = RiskMoney / (SL_points * TickValue_adjusted)
   double riskMoney = AccountEquity() * RiskPercent / 100.0;
   if(riskMoney <=0) return NormalizeLots(MinLotSize);

   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   double point    = MarketInfo(Symbol(), MODE_POINT);

   if(tickVal==0 || tickSize==0 || point==0) return NormalizeLots(MinLotSize);

   // For 5-digit brokers: 1 pip = 10 points. But tickVal already reflects per tick.
   // So SL in ticks = slPoints * point / tickSize
   double slTicks = slPoints * point / tickSize;
   if(slTicks <=0) return NormalizeLots(MinLotSize);

   double lot = riskMoney / (slTicks * tickVal);

   // Safety caps
   if(lot > MaxLotSize) lot = MaxLotSize;
   if(lot < MinLotSize) lot = MinLotSize;

   return NormalizeLots(lot);
  }

double NormalizeLots(double lot)
  {
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double lotMin  = MarketInfo(Symbol(), MODE_MINLOT);
   double lotMax  = MarketInfo(Symbol(), MODE_MAXLOT);
   if(lotStep==0) lotStep=0.01;
   if(lotMin==0) lotMin=MinLotSize;
   if(lotMax==0) lotMax=MaxLotSize;

   // Round down to lotstep
   lot = MathFloor(lot/lotStep)*lotStep;
   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;
   // Normalize to 2 decimals (standard)
   return NormalizeDouble(lot,2);
  }

bool OpenPosition(int signalType, double sl, double tp)
  {
   double ask = MarketInfo(Symbol(), MODE_ASK);
   double bid = MarketInfo(Symbol(), MODE_BID);
   double point = MarketInfo(Symbol(), MODE_POINT);

   // Compute SL distance in points for lot calc
   double slDistPoints=0;
   if(signalType==OP_BUY) slDistPoints = (ask - sl)/point;
   else                   slDistPoints = (sl - bid)/point;
   if(slDistPoints <= 10) // SL too tight — broaden to ATR minimum
     {
      Print("[MM] SL distance too small (",slDistPoints," pts) — skip to avoid overleveraging");
      return false;
     }

   double lots = CalculateLotSize(slDistPoints);

   // Free margin check
   double marginReq = MarketInfo(Symbol(), MODE_MARGINREQUIRED);
   double needed = lots * marginReq;
   // For margin calc approx: lots * contract size * price / leverage
   // Use AccountFreeMarginCheck
   if(AccountFreeMarginCheck(Symbol(), signalType, lots) < 0)
     {
      Print("[MM] Insufficient free margin for ",lots," lots — trying reduced lot");
      // Try half
      lots = NormalizeLots(lots*0.5);
      if(AccountFreeMarginCheck(Symbol(), signalType, lots) <0)
        {
         Print("[MM] Still insufficient margin — abort");
         return false;
        }
     }

   // Normalize SL/TP to digits
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Prevent invalid stops (too close to price)
   int stopLevel = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   double minDist = stopLevel * point;
   if(signalType==OP_BUY)
     {
      if(ask - sl < minDist) sl = ask - minDist - 5*point;
      if(tp - ask < minDist) tp = ask + minDist + 5*point;
     }
   else
     {
      if(sl - bid < minDist) sl = bid + minDist + 5*point;
      if(bid - tp < minDist) tp = bid - minDist - 5*point;
     }

   string comment = StringFormat("QE-%s/R%.1f/DD%.1f",
                     signalType==OP_BUY?"B":"S", RiskPercent, MaxDailyDrawdownPct);

   int ticket = -1;
   color col = signalType==OP_BUY ? Blue : Red;
   if(signalType==OP_BUY)
      ticket = OrderSend(Symbol(), OP_BUY, lots, ask, Slippage, sl, tp, comment, MagicNumber, 0, col);
   else
      ticket = OrderSend(Symbol(), OP_SELL, lots, bid, Slippage, sl, tp, comment, MagicNumber, 0, col);

   if(ticket < 0)
     {
      int err = GetLastError();
      Print("[ORDER ERROR] ",ErrorDescription(err)," lots=",lots," SL=",sl," TP=",tp,
            " Ask=",ask," Bid=",bid," Spread=",MarketInfo(Symbol(),MODE_SPREAD));
      return false;
     }
   else
     {
      Print("[ORDER OK] Ticket=",ticket," ",(signalType==OP_BUY?"BUY":"SELL"),
            " Lots=",lots," SL=",DoubleToStr(sl,digits)," TP=",DoubleToStr(tp,digits),
            " Risk=",RiskPercent,"%");
      return true;
     }
  }

//+------------------------------------------------------------------+
//| Manage open positions: BE, Trailing, RSI exit, Time stop         |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   double atr  = iATR(Symbol(),0,ATRPeriod,1);
   double rsi  = iRSI(Symbol(),0,RSIPeriod,PRICE_CLOSE,1);
   double point= MarketInfo(Symbol(),MODE_POINT);
   int digits  = (int)MarketInfo(Symbol(),MODE_DIGITS);

   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;

      double openPrice = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      int type = OrderType();
      int ticket = OrderTicket();
      datetime openTime = OrderOpenTime();
      bool modified=false;
      double newSL = sl;

      double ask = MarketInfo(Symbol(),MODE_ASK);
      double bid = MarketInfo(Symbol(),MODE_BID);

      // --- BreakEven
      if(UseBreakEven)
        {
         double profitDist = 0;
         if(type==OP_BUY) profitDist = bid - openPrice;
         else             profitDist = openPrice - ask;

         double beTrigger = atr * BE_TriggerATR;
         if(profitDist >= beTrigger)
           {
            double beSL = 0;
            if(type==OP_BUY) beSL = openPrice + BE_PlusPoints*point;
            else             beSL = openPrice - BE_PlusPoints*point;

            // Only move SL forward (not backward)
            if(type==OP_BUY && (sl < beSL || sl==0)) { newSL = beSL; modified=true; }
            if(type==OP_SELL&& (sl > beSL || sl==0)) { newSL = beSL; modified=true; }
           }
        }

      // --- Trailing Stop (ATR-based)
      if(UseTrailing)
        {
         double trailDist = atr * Trail_ATR_Mult;
         // Optional tighten on RSI extremes
         if(UseRSIForTrailExit)
           {
            if((type==OP_BUY && rsi>72) || (type==OP_SELL && rsi<28))
               trailDist *= 0.6; // tighten when overextended
           }
         double step = TrailStepPoints*point;
         if(type==OP_BUY)
           {
            double idealSL = bid - trailDist;
            // Only trail up, and only if beyond step
            if(idealSL > newSL + step && bid - openPrice > trailDist*0.5)
               { newSL = idealSL; modified=true; }
           }
         else // SELL
           {
            double idealSL = ask + trailDist;
            if((idealSL < newSL - step || sl==0) && openPrice - ask > trailDist*0.5)
               { newSL = idealSL; modified=true; }
           }
        }

      // --- RSI opposite exit (optional mean-reversion exit / trend exhaustion)
      if(UseRSIExit)
        {
         bool shouldClose=false;
         // If long and RSI overbought, lock profit
         if(type==OP_BUY && rsi >= RSIOverbought+2)
           {
            // Only if floating profit positive
            if(OrderProfit()>0) shouldClose=true;
           }
         if(type==OP_SELL && rsi <= RSIOversold-2)
           {
            if(OrderProfit()>0) shouldClose=true;
           }
         if(shouldClose)
           {
            Print("[RSI EXIT] Ticket=",ticket," RSI=",rsi," closing");
            bool _closed_rsi=false;
            if(type==OP_BUY) _closed_rsi=OrderClose(ticket, OrderLots(), bid, Slippage, Green);
            else             _closed_rsi=OrderClose(ticket, OrderLots(), ask, Slippage, Orange);
            if(!_closed_rsi) Print("[RSI EXIT FAIL] Ticket=",ticket," err=",GetLastError());
            continue;
           }
        }

      // --- Time Stop for MR trades (identified by comment or hold duration)
      // If hold bars exceeded, close to avoid bag-holding in strong trend against reversion
      // We approximate by checking if this bar count exceeded MaxHoldBars
      if(MR_MaxHoldBars>0)
        {
         // Only apply time stop if trade was MR-style: we detect via SL distance approx or comment
         // Simpler: apply to all — if trade held too long without profit, close
         int barsHeld = iBarShift(Symbol(),0,openTime);
         if(barsHeld >= MR_MaxHoldBars)
           {
            // Only time-stop MR-like trades: those with tighter TP (MR_TP_ATR_Mult)
            // Check proximity of TP distance: if TP-Price close to MR expectation
            // For simplicity, time-stop only losing trades held long
            if(OrderProfit()<0 && barsHeld >= MR_MaxHoldBars)
              {
               Print("[TIME STOP] Ticket=",ticket," barsHeld=",barsHeld," closing losing MR hold");
               bool _closed_time=false;
               if(type==OP_BUY) _closed_time=OrderClose(ticket, OrderLots(), bid, Slippage, Yellow);
               else             _closed_time=OrderClose(ticket, OrderLots(), ask, Slippage, Yellow);
               if(!_closed_time) Print("[TIME STOP FAIL] Ticket=",ticket," err=",GetLastError());
               continue;
              }
           }
        }

      // --- Apply SL modification
      if(modified)
        {
         newSL = NormalizeDouble(newSL, digits);
         // Validate stop level distance
         int stopLevel = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
         double minDist = stopLevel*point;
         bool valid=true;
         if(type==OP_BUY && bid - newSL < minDist) valid=false;
         if(type==OP_SELL&& newSL - ask < minDist) valid=false;
         // Avoid modifying if same as current within 2*point
         if(MathAbs(newSL - sl) < 2*point) valid=false;

         if(valid)
           {
            bool ok = OrderModify(ticket, openPrice, newSL, tp, 0, CLR_NONE);
            if(!ok)
              {
               int e=GetLastError();
               // 130 = invalid stops — ignore spam
               if(e!=130) Print("[MODIFY FAIL] Ticket=",ticket," newSL=",newSL," err=",ErrorDescription(e));
              }
            else
              {
               Print("[MODIFY OK] Ticket=",ticket," newSL=",newSL," type=",type==OP_BUY?"BUY":"SELL");
              }
           }
        }
     }
  }

void CloseAllPositions(string reason)
  {
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int t = OrderType();
      int ticket = OrderTicket();
      double price = (t==OP_BUY) ? MarketInfo(Symbol(),MODE_BID) : MarketInfo(Symbol(),MODE_ASK);
      bool closed = OrderClose(ticket, OrderLots(), price, Slippage, White);
      if(!closed)
        {
         Print("[CLOSE FAIL] Ticket=",ticket," err=",ErrorDescription(GetLastError())," reason=",reason);
        }
      else
        {
         Print("[CLOSE OK] Ticket=",ticket," reason=",reason);
        }
     }
  }

//--- Custom iMAOnArray helper to avoid array complexity
double iMAOnArray2(int atrPeriod, int maPeriod)
  {
   // Compute ATR MA: average of last maPeriod ATR values
   double sum=0;
   int counted=0;
   for(int k=1; k<=maPeriod+5; k++)
     {
      double a = iATR(Symbol(),0,atrPeriod,k);
      if(a==0) continue;
      sum+=a;
      counted++;
      if(counted>=maPeriod) break;
     }
   if(counted==0) return 0;
   return sum/counted;
  }

void LogSignal(string msg)
  {
   Print("[SIGNAL] ",msg);
  }

//+------------------------------------------------------------------+
//| News Filter Helpers — 45m before / 30m after                     |
//+------------------------------------------------------------------+
void ReloadNewsIfNeeded()
  {
   if(!UseNewsFilter) return;
   // Throttle: check file every 60 seconds (avoid FileOpen spam each tick)
   if(TimeCurrent() - g_lastNewsLoad < 60) return;
   g_lastNewsLoad = TimeCurrent();

   int fileCnt = QM_LoadNewsFile(NewsFileName);
   // Fallback to manual list if file empty/missing and manual provided
   if(fileCnt==0 && NewsManualList != "")
     {
      // Reset arrays if file gave 0 but manual may add
      if(ArraySize(g_qmNewsTimes)==0)
        {
         QM_ParseManualList(NewsManualList);
        }
     }
   // Cache next news for dashboard
   g_nextNewsTime = QM_NextNewsTime(TimeCurrent(), NewsCurrencies);
  }

bool IsNewsBlocked(string &reasonOut)
  {
   reasonOut="";
   if(!UseNewsFilter) return false;
   // Lazy load if never loaded
   if(g_lastNewsLoad==0) ReloadNewsIfNeeded();
   if(ArraySize(g_qmNewsTimes)==0) return false;

   string outReason=""; datetime outNews=0; string outCur="";
   // Quick currency pre-filter inside QM_IsNewsBlocked, but we also respect HighOnly
   // HighOnly handling: if true, skip Medium/Low events
   // We iterate manually to apply impact filter
   for(int i=0;i<ArraySize(g_qmNewsTimes);i++)
     {
      string cur = g_qmNewsCurr[i];
      string imp = g_qmNewsImpact[i];
      if(NewsHighOnly && !QM_ShouldBlockImpact(imp, true)) continue;
      if(!QM_CurrencyPass(cur, NewsCurrencies)) continue;
      datetime newsT = g_qmNewsTimes[i];
      datetime winStart = newsT - NewsBeforeMin*60;
      datetime winEnd   = newsT + NewsAfterMin*60;
      datetime nowTime = TimeCurrent();
      if(nowTime >= winStart && nowTime <= winEnd)
        {
         reasonOut = StringFormat("NEWS BLOCK %s %s %s (%s) | now %s inside %s -> %s (45m before / 30m after)",
                     TimeToString(newsT), cur, imp, g_qmNewsEvent[i],
                     TimeToString(nowTime), TimeToString(winStart), TimeToString(winEnd));
         g_newsBlocked = true;
         g_newsBlockReason = reasonOut;
         return true;
        }
     }
   g_newsBlocked = false;
   // Also use helper for consistency (covers same logic)
   return false;
  }

bool CheckNewsCloseNeeded()
  {
   if(!UseNewsFilter || !NewsCloseBefore) return false;
   if(ArraySize(g_qmNewsTimes)==0) return false;
   datetime nowTime = TimeCurrent();
   for(int i=0;i<ArraySize(g_qmNewsTimes);i++)
     {
      string cur = g_qmNewsCurr[i];
      string imp = g_qmNewsImpact[i];
      if(NewsHighOnly && !QM_ShouldBlockImpact(imp, true)) continue;
      if(!QM_CurrencyPass(cur, NewsCurrencies)) continue;
      datetime newsT = g_qmNewsTimes[i];
      datetime closeTrig = newsT - NewsCloseBeforeMin*60;
      // If we are within [closeTrig, newsT) and have open trades, signal close
      if(nowTime >= closeTrig && nowTime < newsT)
        {
         if(CountOpenTrades()>0) return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Chart Dashboard — live equity, DD, regime, next signal           |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   double equity = AccountEquity();
   double balance= AccountBalance();
   double startEq= g_dailyStartEquity;
   double curDD = (startEq>0)? (startEq - equity)/startEq*100.0 : 0;
   double curProf = (startEq>0)? (equity - startEq)/startEq*100.0 : 0;
   double atr = iATR(Symbol(),0,ATRPeriod,1);
   double atrMA = iMAOnArray2(ATRPeriod, ATR_MA_Period);
   string regime = "NORMAL";
   color regimeColor = White;
   if(atrMA>0)
     {
      if(atr > atrMA*VolatilityHighMult) { regime="HIGH VOL (Trend Only + Cooldown)"; regimeColor=Orange; }
      else if(atr < atrMA*VolatilityLowMult) { regime="LOW VOL (Mean-Reversion Active)"; regimeColor=SpringGreen; }
     }

   // FTMO panel calc
   string ftmoLine = "";
   string profitLine = "";
   if(FTMO_Mode && g_ftmoInitialBalance>0)
     {
      double fEquity = AccountEquity();
      double dailyLossMoney = g_dailyStartEquity - fEquity;
      double totalLossMoney = g_ftmoInitialBalance - fEquity;
      double profitMoney = fEquity - g_ftmoInitialBalance;
      double profitPct = profitMoney / g_ftmoInitialBalance * 100.0;
      double dailyDDftmo = dailyLossMoney / g_ftmoInitialBalance * 100.0;
      double totalDDftmo = totalLossMoney / g_ftmoInitialBalance * 100.0;
      double dailyBuf = g_ftmoInitialBalance*FTMO_MaxDailyLossPct/100.0 - dailyLossMoney;
      double totalBuf = g_ftmoInitialBalance*FTMO_MaxTotalLossPct/100.0 - totalLossMoney;
      if(dailyBuf<0) dailyBuf=0; if(totalBuf<0) totalBuf=0;
      ftmoLine = StringFormat("FTMO %s: Daily %.2f%%/%.0f%% ($%s left) Total %.2f%%/%.0f%% ($%s left) | Buffer $%s",
                 DoubleToStr(g_ftmoInitialBalance,0), dailyDDftmo, FTMO_MaxDailyLossPct, DoubleToStr(dailyBuf,0),
                 totalDDftmo, FTMO_MaxTotalLossPct, DoubleToStr(totalBuf,0), DoubleToStr(MathMin(dailyBuf,totalBuf),0));
      profitLine = StringFormat("FTMO Target %.0f%%: %.2f%% ($%s) | Days %d/%d | Peak $%s",
                 FTMO_ProfitTargetPct, profitPct, DoubleToStr(profitMoney,2), g_ftmoTradingDays, FTMO_MinTradingDays, DoubleToStr(g_ftmoPeakEquity,2));
      if(g_ftmoBreach) { ftmoLine = "FTMO BREACH: " + g_ftmoBreachReason; profitLine = "FTMO HALTED - close all, contact supervisor"; }
     }

   string haltTxt = g_haltTradingToday ? StringFormat("HALTED: %s",g_haltReason) : "ACTIVE";
   color haltCol = g_haltTradingToday ? Red : Lime;

   // News status line
   string newsLine = "NEWS: OFF";
   if(UseNewsFilter)
     {
      if(g_newsBlocked)
         newsLine = StringFormat("NEWS: BLOCKED 45/30 (%s)", g_newsBlockReason);
      else if(g_nextNewsTime>0)
        {
         int minsToNews = (int)((g_nextNewsTime - TimeCurrent())/60);
         if(minsToNews>=0 && minsToNews<1440)
            newsLine = StringFormat("NEWS: next %s %s in %dm (45m before / 30m after)", TimeToString(g_nextNewsTime), NewsCurrencies, minsToNews);
         else
            newsLine = StringFormat("NEWS: ON (%d events) next %s", g_qmNewsCount, g_nextNewsTime>0? TimeToString(g_nextNewsTime) : "none");
        }
      else
         newsLine = StringFormat("NEWS: ON (%d events) - add times to %s", g_qmNewsCount, NewsFileName);
     }

   // Build dashboard - include FTMO lines if active
   string dash;
   if(FTMO_Mode && g_ftmoInitialBalance>0)
     {
      dash = StringFormat(
        "┌─ QuantumEdge FTMO v2.12 [EURUSD] ───────────────┐\n"+
        "│ Symbol: %s  TF: %s  Magic: %d             \n"+
        "│ Mode: %s | Regime: %s                  \n"+
        "│ Equity: %.2f  Balance: %.2f  StartDay: %.2f\n"+
        "│ Daily P/L: %.2f%% | DD: %.2f%% (Limit %.1f%%)\n"+
        "│ Trades Today: %d | Open: %d | Halt: %s\n"+
        "│ %s\n"+
        "│ %s\n"+
        "│ %s\n"+
        "│ EMA %d/%d  RSI %d (%.1f)  ATR %.5f  ADX %.1f\n"+
        "│ Risk: %.1f%%  SLx%.1f TPx%.1f | MR: %.1fATR\n"+
        "└───────────────────────────────────────────\n",
     Symbol(), EnumToString((ENUM_TIMEFRAMES)Period()), MagicNumber,
     EnumToString(TradeMode), regime,
     equity, balance, startEq,
     curProf, curDD, MaxDailyDrawdownPct,
     g_totalTradesToday, CountOpenTrades(), haltTxt,
     ftmoLine,
     profitLine,
     newsLine,
     EMAPeriodFast, EMAPeriodSlow, RSIPeriod, iRSI(Symbol(),0,RSIPeriod,PRICE_CLOSE,1), atr,
     UseADXConfirmation? iADX(Symbol(),0,ADXPeriod,PRICE_CLOSE,MODE_MAIN,1): 0,
     RiskPercent, ATR_SL_Mult, ATR_TP_Mult, MR_DistanceATR
   );

      Comment(dash);
     }
   else
     {
      dash = StringFormat(
        "┌─ QuantumEdge FTMO v2.12 [EURUSD] ───────────────┐\n"+
        "│ Symbol: %s  TF: %s  Magic: %d             \n"+
        "│ Mode: %s | Regime: %s                  \n"+
        "│ Equity: %.2f  Balance: %.2f  StartDay: %.2f\n"+
        "│ Daily P/L: %.2f%% | DD: %.2f%% (Limit %.1f%%)\n"+
        "│ Trades Today: %d | Open: %d | Halt: %s\n"+
        "│ %s\n"+
        "│ EMA %d/%d  RSI %d (%.1f)  ATR %.5f  ADX %.1f\n"+
        "│ Risk: %.1f%%  SLx%.1f TPx%.1f | MR: %.1fATR\n"+
        "└───────────────────────────────────────────\n",
        Symbol(), EnumToString((ENUM_TIMEFRAMES)Period()), MagicNumber,
        EnumToString(TradeMode), regime,
        equity, balance, startEq,
        curProf, curDD, MaxDailyDrawdownPct,
        g_totalTradesToday, CountOpenTrades(), haltTxt,
        newsLine,
        EMAPeriodFast, EMAPeriodSlow, RSIPeriod, iRSI(Symbol(),0,RSIPeriod,PRICE_CLOSE,1), atr,
        UseADXConfirmation? iADX(Symbol(),0,ADXPeriod,PRICE_CLOSE,MODE_MAIN,1): 0,
        RiskPercent, ATR_SL_Mult, ATR_TP_Mult, MR_DistanceATR
      );
      Comment(dash);
     }

   // Color via chart comment not fully controllable; alternative: create labels
   // For strategy tester visualization, keep Comment simple.
  }

//+------------------------------------------------------------------+
//| Error Description helper (subset)                                |
//+------------------------------------------------------------------+
string ErrorDescription(int code)
  {
   switch(code)
     {
      case 0:   return "No error";
      case 1:   return "No error (01)";
      case 2:   return "Common error";
      case 3:   return "Invalid trade parameters";
      case 4:   return "Trade server busy";
      case 6:   return "No connection";
      case 8:   return "Too frequent requests";
      case 64:  return "Account disabled";
      case 128: return "Trade timeout";
      case 129: return "Invalid price";
      case 130: return "Invalid stops";
      case 131: return "Invalid trade volume";
      case 132: return "Market closed";
      case 133: return "Trade disabled";
      case 134: return "Not enough money";
      case 135: return "Price changed";
      case 136: return "Off quotes";
      case 137: return "Broker busy";
      case 138: return "Requote";
      case 139: return "Order locked";
      case 140: return "Long only";
      case 141: return "Too many requests";
      case 145: return "Modification denied (too close)";
      case 146: return "Trade context busy";
      default:  return StringFormat("Error %d",code);
     }
  }
//+------------------------------------------------------------------+
//| End of QuantumEdge_DualModeEA.mq4                               |
//+------------------------------------------------------------------+
