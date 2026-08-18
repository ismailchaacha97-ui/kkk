//+------------------------------------------------------------------+
//|                                           PropFirm_Constants.mqh |
//|                     Institutional Prop Firm & Hedge Fund Engine  |
//|                                   Copyright 2026, Institutional  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional Edge Systems"
#property link      "https://github.com/ismailchaacha97-ui/kkk"
#property strict

//--- Prop Firm Challenge Rule Profiles
enum ENUM_PROPFIRM_PROFILE
{
   PROPFIRM_FTMO,          // FTMO (5% Daily DD, 10% Max DD, 10% Target)
   PROPFIRM_FUNDEDNEXT,    // FundedNext (5% Daily DD, 10% Max DD, 8% Target)
   PROPFIRM_THE5ERS,       // The 5%ers (4% Daily DD, 8% Max DD, 8% Target)
   PROPFIRM_TOPSTEP,       // Topstep (Daily Loss Limit, Max Loss Limit)
   PROPFIRM_ALPHA_CAPITAL, // Alpha Capital (5% Daily DD, 10% Max DD)
   PROPFIRM_CUSTOM         // Custom User Defined Rules
};

//--- Market Structure Types
enum ENUM_STRUCTURE_TYPE
{
   STRUCT_NONE,
   STRUCT_BOS_BULL,        // Bullish Break of Structure (Continuation)
   STRUCT_BOS_BEAR,        // Bearish Break of Structure (Continuation)
   STRUCT_CHOCH_BULL,      // Bullish Change of Character / MSS (Reversal)
   STRUCT_CHOCH_BEAR       // Bearish Change of Character / MSS (Reversal)
};

//--- Liquidity Pool Types
enum ENUM_LIQUIDITY_TYPE
{
   LIQ_NONE,
   LIQ_BSL_SWEEP,          // Buy-Side Liquidity Sweep (Turtle Soup Bearish Reversal)
   LIQ_SSL_SWEEP,          // Sell-Side Liquidity Sweep (Turtle Soup Bullish Reversal)
   LIQ_EQH,                // Equal Highs (Untapped Buy-Side Pool)
   LIQ_EQL,                // Equal Lows (Untapped Sell-Side Pool)
   LIQ_SESSION_HIGH_SWEEP, // Asian/London High Sweep
   LIQ_SESSION_LOW_SWEEP   // Asian/London Low Sweep
};

//--- Signal Quality Rating
enum ENUM_SIGNAL_GRADE
{
   GRADE_NONE,
   GRADE_C,                // < 65% Confluence (Filtered Retail Noise)
   GRADE_B,                // 65% - 79% Confluence (Standard Setup)
   GRADE_A_PLUS            // 80% - 100% Confluence (Institutional A+ High Prob)
};

//--- Dashboard UI Themes
enum ENUM_HUD_THEME
{
   THEME_DARK_INSTITUTIONAL, // Sleek Obsidian & Cyan/Emerald
   THEME_BLOOMBERG_TERMINAL, // Amber & Slate Dark
   THEME_CYBER_MATRIX,       // Neon Cyan & Hot Magenta
   THEME_CLEAN_LIGHT         // Crisp Light Grey & Royal Blue
};

//--- Structure point record
struct SwingPoint
{
   datetime time;
   double   price;
   int      barIndex;
   int      type;            // +1 = Swing High, -1 = Swing Low
   bool     isBroken;        // Has price broken past this swing?
   bool     isSwept;         // Was this swing swept by wick only?
   string   label;
};

//--- Institutional Order Block Record
struct OrderBlock
{
   datetime time;
   double   high;
   double   low;
   double   open;
   double   close;
   int      direction;       // +1 = Bullish OB (Demand), -1 = Bearish OB (Supply)
   bool     isMitigated;     // Has price retested and filled this OB?
   datetime mitigationTime;
   double   volume;
   double   strength;        // 0-100 score based on displacement & FVG creation
   string   objName;
};

//--- Fair Value Gap (Imbalance) Record
struct FairValueGap
{
   datetime time;
   double   top;
   double   bottom;
   double   consequentEncroachment; // Midpoint (50% level)
   int      direction;       // +1 = Bullish FVG, -1 = Bearish FVG
   bool     isMitigated;
   datetime mitigationTime;
   string   objName;
};

//--- Trade Signal Record
struct InstitutionalSignal
{
   datetime time;
   int      barIndex;
   int      type;            // +1 = BUY, -1 = SELL
   double   entryPrice;
   double   stopLoss;
   double   takeProfit1;     // 1:2 RRR
   double   takeProfit2;     // 1:3.5 RRR
   double   takeProfit3;     // 1:5+ RRR / Liquidity Target
   double   riskReward;
   double   confluenceScore; // 0 - 100%
   ENUM_SIGNAL_GRADE grade;
   string   setupReason;
   double   recommendedLots;
};

//--- Prop Firm Risk State
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
   bool   isDailyDDWarning;  // Triggered at 70% of max daily DD
};
