//+------------------------------------------------------------------+
//| Adaptive SMC Dashboard for MetaTrader 4                          |
//| Smart-money structure signals, MTF filtering and local testing  |
//|                                                                  |
//| This indicator is deterministic. "Optimize" performs a bounded  |
//| historical parameter search; it does not call an AI service.     |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4
#property version           "1.00"
#property description       "Non-repainting SMC BOS/CHoCH signals with MTF scanner"
#property description       "Entry/SL/TP levels, dashboard, historical stats and optimizer"

//--- Public enums
enum ENUM_SMC_STOP_MODE
  {
   STOP_LAST_OPPOSITE_SWING = 0,
   STOP_BEHIND_ORDER_BLOCK  = 1,
   STOP_RECENT_HIGH_LOW     = 2,
   STOP_FIXED_POINTS        = 3,
   STOP_ATR_DISTANCE        = 4
  };

enum ENUM_SMC_TP_MODE
  {
   TAKE_PROFIT_RISK_REWARD = 0,
   TAKE_PROFIT_ATR         = 1
  };

enum ENUM_SMC_RECOVERY_MODE
  {
   RECOVERY_OFF       = 0,
   RECOVERY_MULTIPLY  = 1,
   RECOVERY_FIXED_ADD = 2
  };

enum ENUM_SMC_SEARCH_DEPTH
  {
   SEARCH_FAST   = 0,
   SEARCH_NORMAL = 1,
   SEARCH_FULL   = 2
  };

enum ENUM_SMC_OPTIMIZE_FOR
  {
   OPTIMIZE_NET_PROFIT    = 0,
   OPTIMIZE_PROFIT_FACTOR = 1,
   OPTIMIZE_WIN_RATE      = 2,
   OPTIMIZE_PROFIT_TRADE  = 3
  };

//--- Core structure settings
input string InpCoreHeader                 = "===== SMC STRUCTURE =====";
input int    SwingStrength                 = 3;       // Bars on each side of a swing
input int    MaxBarsToAnalyze              = 5000;    // Closed chart bars to process
input int    OrderBlockLookback            = 20;      // Search depth for last opposite candle
input bool   SignalOnCHoCHOnly              = false;   // Ignore continuation BOS signals
input bool   ReverseSignals                 = false;   // Reverse final buy/sell direction
input int    MaxSignalsOnChart              = 12;      // Accepted setups drawn on chart

//--- Stop and target settings
input string InpRiskHeader                 = "===== STOP / TARGET =====";
input ENUM_SMC_STOP_MODE StopLossMode       = STOP_LAST_OPPOSITE_SWING;
input ENUM_SMC_TP_MODE   TakeProfitMode     = TAKE_PROFIT_ATR;
input int    StopLookbackBars               = 8;
input double StopBufferPoints               = 50.0;
input double FixedStopPoints                = 3200.0;
input double MaxRiskPoints                  = 0.0;     // 0 disables the cap
input double RiskRewardTP1                  = 1.50;
input double RiskRewardTP2                  = 2.00;
input double RiskRewardTP3                  = 3.00;
input int    ATRPeriod                      = 8;
input double ATRStopMultiplier              = 1.50;
input double ATRTarget1Multiplier           = 2.50;
input double ATRTarget2Multiplier           = 3.50;
input double ATRTarget3Multiplier           = 4.50;

//--- Multi-timeframe scanner and filter
input string InpMTFHeader                   = "===== MULTI-TIMEFRAME FILTER =====";
input bool   EnableMTFScanner               = true;
input bool   UseMTFFilter                   = false;
input int    ScannerBars                    = 300;
input double MinimumMTFAgreement            = 60.0;
input bool   RejectWhenMTFHistoryMissing    = true;
input bool   DrawRejectedSignals            = true;
input bool   DrawRejectedTradeLevels        = false;
input bool   ScanM5                         = false;
input double WeightM5                       = 0.50;
input bool   ScanM15                        = true;
input double WeightM15                      = 1.00;
input bool   ScanM30                        = true;
input double WeightM30                      = 1.00;
input bool   ScanH1                         = true;
input double WeightH1                       = 1.50;
input bool   ScanH4                         = true;
input double WeightH4                       = 2.00;
input bool   ScanD1                         = false;
input double WeightD1                       = 2.50;

//--- Session and weekday filtering (broker/server time)
input string InpSessionHeader               = "===== SESSION FILTER =====";
input bool   UseSessionFilter               = false;
input int    SessionStartHour               = 0;
input int    SessionEndHour                 = 24;
input bool   TradeSunday                    = true;
input bool   TradeMonday                    = true;
input bool   TradeTuesday                   = true;
input bool   TradeWednesday                 = true;
input bool   TradeThursday                  = true;
input bool   TradeFriday                    = true;
input bool   TradeSaturday                  = true;

//--- On-chart optimizer
input string InpOptimizerHeader             = "===== ADAPTIVE OPTIMIZER =====";
input bool   EnableOptimizerButton          = true;
input ENUM_SMC_SEARCH_DEPTH OptimizerDepth  = SEARCH_NORMAL;
input ENUM_SMC_OPTIMIZE_FOR OptimizeFor     = OPTIMIZE_NET_PROFIT;
input int    OptimizationBars               = 1500;
input int    MinimumOptimizationTrades      = 8;
input bool   ReloadSavedSettingsAtStart     = true;

//--- Test assumptions and recovery model
input string InpTestHeader                  = "===== HISTORICAL TEST MODEL =====";
input double TestStartingBalance            = 2000.0;
input double TestLotSize                    = 0.10;
input double OverrideSpreadPoints           = 0.0;     // 0 = current broker spread
input double ExtraSpreadPoints              = 0.0;
input double CommissionPerLotRoundTurn      = 0.0;
input int    MaximumTradeBars               = 0;       // 0 = wait until SL/TP/current bar
input ENUM_SMC_RECOVERY_MODE RecoveryMode   = RECOVERY_FIXED_ADD;
input double RecoveryFactor                 = 2.0;
input double RecoveryLotStep                = 0.10;
input int    MaximumRecoverySteps           = 5;

//--- Display and alerts
input string InpDisplayHeader               = "===== DISPLAY / ALERTS =====";
input bool   ShowDashboard                  = true;
input ENUM_BASE_CORNER DashboardCorner      = CORNER_LEFT_UPPER;
input int    DashboardX                     = 8;
input int    DashboardY                     = 20;
input int    DashboardWidth                 = 340;
input int    DashboardFontSize              = 9;
input bool   DrawOrderBlocks                = true;
input bool   DrawEntryStopTargetLines       = true;
input int    TradeLineLengthBars            = 18;
input color  BuyColor                       = clrLimeGreen;
input color  SellColor                      = clrTomato;
input color  RejectedColor                  = clrDarkGray;
input color  EntryColor                     = clrDeepSkyBlue;
input color  StopColor                      = clrTomato;
input color  TargetColor                    = clrLimeGreen;
input bool   EnablePopupAlerts              = true;
input bool   EnablePushNotifications        = false;

//--- Indicator buffers (available to EAs through iCustom)
double BuySignalBuffer[];
double SellSignalBuffer[];
double RejectedBuyBuffer[];
double RejectedSellBuffer[];

//--- Internal data structures
struct SignalInfo
  {
   int      shift;
   int      direction;
   int      event_type;            // 1=BOS, 2=CHoCH
   datetime time;
   double   entry;
   double   stop;
   double   target1;
   double   target2;
   double   target3;
   double   order_low;
   double   order_high;
   int      order_shift;
   double   mtf_buy;
   double   mtf_sell;
   bool     accepted;
   bool     closed;
   bool     won;
   int      exit_shift;
   double   pnl;
  };

struct TestStats
  {
   int    total;
   int    wins;
   int    losses;
   int    open_trades;
   double gross_profit;
   double gross_loss;
   double net_profit;
   double profit_factor;
   double win_rate;
   double growth;
   double max_lot;
   int    max_step;
  };

//--- Runtime state
string   g_prefix="";
string   g_draw_prefix="";
string   g_panel_prefix="";
bool     g_force_rebuild=true;
bool     g_panel_collapsed=false;
bool     g_optimizing=false;
datetime g_last_chart_bar=0;
datetime g_last_alerted_signal=0;

int                    g_active_swing=3;
ENUM_SMC_STOP_MODE     g_active_stop_mode=STOP_LAST_OPPOSITE_SWING;
double                 g_active_sl_atr=1.5;
double                 g_active_tp1_atr=2.5;
bool                   g_active_choch_only=false;
double                 g_active_mtf_threshold=60.0;
bool                   g_using_optimized=false;

int      g_structure_bias=0;
int      g_bias_m5=0;
int      g_bias_m15=0;
int      g_bias_m30=0;
int      g_bias_h1=0;
int      g_bias_h4=0;
int      g_bias_d1=0;
double   g_current_buy_strength=0.0;
double   g_current_sell_strength=0.0;
TestStats g_stats;
TestStats g_signal_to_signal_stats;
TestStats g_recovery_stats;
SignalInfo g_latest_signal;
bool       g_has_latest_signal=false;

//+------------------------------------------------------------------+
//| Utility functions                                                |
//+------------------------------------------------------------------+
int ClampInt(const int value,const int minimum,const int maximum)
  {
   return(MathMax(minimum,MathMin(maximum,value)));
  }

double ClampDouble(const double value,const double minimum,const double maximum)
  {
   return(MathMax(minimum,MathMin(maximum,value)));
  }

string DirectionText(const int direction)
  {
   if(direction>0) return("BUY");
   if(direction<0) return("SELL");
   return("NEUTRAL");
  }

color DirectionColor(const int direction)
  {
   if(direction>0) return(BuyColor);
   if(direction<0) return(SellColor);
   return(clrSilver);
  }

string StopModeText(const ENUM_SMC_STOP_MODE mode)
  {
   if(mode==STOP_LAST_OPPOSITE_SWING) return("Opposite swing");
   if(mode==STOP_BEHIND_ORDER_BLOCK)  return("Order block");
   if(mode==STOP_RECENT_HIGH_LOW)     return("Recent high/low");
   if(mode==STOP_FIXED_POINTS)        return("Fixed points");
   return("ATR");
  }

string RecoveryModeText(const ENUM_SMC_RECOVERY_MODE mode)
  {
   if(mode==RECOVERY_MULTIPLY)  return("MULTIPLY");
   if(mode==RECOVERY_FIXED_ADD) return("FIXED ADD");
   return("OFF");
  }

string TimeframeText(const int timeframe)
  {
   if(timeframe==PERIOD_M1)  return("M1");
   if(timeframe==PERIOD_M5)  return("M5");
   if(timeframe==PERIOD_M15) return("M15");
   if(timeframe==PERIOD_M30) return("M30");
   if(timeframe==PERIOD_H1)  return("H1");
   if(timeframe==PERIOD_H4)  return("H4");
   if(timeframe==PERIOD_D1)  return("D1");
   if(timeframe==PERIOD_W1)  return("W1");
   return(IntegerToString(timeframe));
  }

int SafePeriodSeconds(const int timeframe)
  {
   int seconds=PeriodSeconds((ENUM_TIMEFRAMES)timeframe);
   if(seconds<=0) seconds=timeframe*60;
   return(MathMax(60,seconds));
  }

void ResetStats(TestStats &stats)
  {
   stats.total=0;
   stats.wins=0;
   stats.losses=0;
   stats.open_trades=0;
   stats.gross_profit=0.0;
   stats.gross_loss=0.0;
   stats.net_profit=0.0;
   stats.profit_factor=0.0;
   stats.win_rate=0.0;
   stats.growth=0.0;
   stats.max_lot=TestLotSize;
   stats.max_step=0;
  }

void DeleteObjectsWithPrefix(const string prefix)
  {
   for(int i=ObjectsTotal()-1;i>=0;i--)
     {
      string name=ObjectName(i);
      if(StringFind(name,prefix,0)==0)
         ObjectDelete(0,name);
     }
  }

string SavedKey(const string suffix)
  {
   string symbol=Symbol();
   if(StringLen(symbol)>16) symbol=StringSubstr(symbol,0,16);
   return("ASMC."+symbol+"."+IntegerToString(Period())+"."+suffix);
  }

void SaveActiveSettings()
  {
   GlobalVariableSet(SavedKey("swing"),g_active_swing);
   GlobalVariableSet(SavedKey("stop"),(int)g_active_stop_mode);
   GlobalVariableSet(SavedKey("slatr"),g_active_sl_atr);
   GlobalVariableSet(SavedKey("tpatr"),g_active_tp1_atr);
   GlobalVariableSet(SavedKey("choch"),g_active_choch_only ? 1.0 : 0.0);
   GlobalVariableSet(SavedKey("mtf"),g_active_mtf_threshold);
  }

bool LoadActiveSettings()
  {
   if(!GlobalVariableCheck(SavedKey("swing"))) return(false);
   g_active_swing=ClampInt((int)GlobalVariableGet(SavedKey("swing")),1,10);
   g_active_stop_mode=(ENUM_SMC_STOP_MODE)ClampInt((int)GlobalVariableGet(SavedKey("stop")),0,4);
   g_active_sl_atr=ClampDouble(GlobalVariableGet(SavedKey("slatr")),0.25,10.0);
   g_active_tp1_atr=ClampDouble(GlobalVariableGet(SavedKey("tpatr")),0.25,20.0);
   g_active_choch_only=(GlobalVariableGet(SavedKey("choch"))>0.5);
   g_active_mtf_threshold=ClampDouble(GlobalVariableGet(SavedKey("mtf")),0.0,100.0);
   g_using_optimized=true;
   return(true);
  }

void ResetActiveSettings(const bool erase_saved)
  {
   g_active_swing=ClampInt(SwingStrength,1,10);
   g_active_stop_mode=StopLossMode;
   g_active_sl_atr=MathMax(0.1,ATRStopMultiplier);
   g_active_tp1_atr=MathMax(0.1,ATRTarget1Multiplier);
   g_active_choch_only=SignalOnCHoCHOnly;
   g_active_mtf_threshold=ClampDouble(MinimumMTFAgreement,0.0,100.0);
   g_using_optimized=false;
   if(erase_saved)
     {
      GlobalVariableDel(SavedKey("swing"));
      GlobalVariableDel(SavedKey("stop"));
      GlobalVariableDel(SavedKey("slatr"));
      GlobalVariableDel(SavedKey("tpatr"));
      GlobalVariableDel(SavedKey("choch"));
      GlobalVariableDel(SavedKey("mtf"));
     }
  }

//+------------------------------------------------------------------+
//| Swing and structure helpers                                      |
//+------------------------------------------------------------------+
bool IsSwingHighTF(const int timeframe,const int shift,const int strength)
  {
   int bars=iBars(NULL,timeframe);
   if(shift-strength<0 || shift+strength>=bars) return(false);
   double value=iHigh(NULL,timeframe,shift);
   for(int k=1;k<=strength;k++)
     {
      if(value<=iHigh(NULL,timeframe,shift-k)) return(false);
      if(value<iHigh(NULL,timeframe,shift+k))  return(false);
     }
   return(true);
  }

bool IsSwingLowTF(const int timeframe,const int shift,const int strength)
  {
   int bars=iBars(NULL,timeframe);
   if(shift-strength<0 || shift+strength>=bars) return(false);
   double value=iLow(NULL,timeframe,shift);
   for(int k=1;k<=strength;k++)
     {
      if(value>=iLow(NULL,timeframe,shift-k)) return(false);
      if(value>iLow(NULL,timeframe,shift+k))  return(false);
     }
   return(true);
  }

int StructureBiasFromShift(const int timeframe,const int newest_shift,const int strength,
                           const int lookback,bool &available)
  {
   available=false;
   int total=iBars(NULL,timeframe);
   if(total<=newest_shift+strength*2+10) return(0);

   int oldest=MathMin(total-strength-1,newest_shift+MathMax(50,lookback)+strength*2);
   if(oldest<=newest_shift+strength) return(0);

   double swing_high=0.0,swing_low=0.0;
   bool high_broken=true,low_broken=true;
   int trend=0;
   int processed=0;

   for(int i=oldest;i>=newest_shift;i--)
     {
      int pivot=i+strength;
      if(pivot+strength<total)
        {
         if(IsSwingHighTF(timeframe,pivot,strength))
           {
            swing_high=iHigh(NULL,timeframe,pivot);
            high_broken=false;
           }
         if(IsSwingLowTF(timeframe,pivot,strength))
           {
            swing_low=iLow(NULL,timeframe,pivot);
            low_broken=false;
           }
        }

      double close_now=iClose(NULL,timeframe,i);
      double close_old=iClose(NULL,timeframe,i+1);
      if(swing_high>0.0 && !high_broken && close_now>swing_high && close_old<=swing_high)
        {
         trend=1;
         high_broken=true;
        }
      else if(swing_low>0.0 && !low_broken && close_now<swing_low && close_old>=swing_low)
        {
         trend=-1;
         low_broken=true;
        }
      processed++;
     }

   available=(processed>=MathMin(30,MathMax(10,lookback/3)));
   return(trend);
  }

int BiasAtDecisionTime(const int timeframe,const datetime signal_open_time,bool &available)
  {
   datetime decision_time=signal_open_time+SafePeriodSeconds(Period());
   int shift=iBarShift(NULL,timeframe,decision_time-1,false);
   if(shift<0)
     {
      available=false;
      return(0);
     }

   datetime bar_open=iTime(NULL,timeframe,shift);
   if(bar_open<=0)
     {
      available=false;
      return(0);
     }

   // If the containing higher-timeframe candle had not closed when the
   // chart signal became known, use the preceding completed candle.
   if(bar_open+SafePeriodSeconds(timeframe)>decision_time)
      shift++;

   return(StructureBiasFromShift(timeframe,shift,g_active_swing,ScannerBars,available));
  }

int CurrentClosedBias(const int timeframe)
  {
   bool available=false;
   int direction=StructureBiasFromShift(timeframe,1,g_active_swing,ScannerBars,available);
   if(!available) return(0);
   return(direction);
  }

void AddWeightedBias(const bool enabled,const int direction,const double weight,
                     double &buy_weight,double &sell_weight,double &total_weight,
                     bool &missing)
  {
   if(!enabled) return;
   double safe_weight=MathMax(0.0,weight);
   if(direction==0)
     {
      missing=true;
      return;
     }
   total_weight+=safe_weight;
   if(direction>0) buy_weight+=safe_weight;
   else            sell_weight+=safe_weight;
  }

void CalculateCurrentScanner()
  {
   if(!EnableMTFScanner)
     {
      g_bias_m5=0; g_bias_m15=0; g_bias_m30=0;
      g_bias_h1=0; g_bias_h4=0; g_bias_d1=0;
      g_current_buy_strength=0.0;
      g_current_sell_strength=0.0;
      return;
     }

   g_bias_m5 =ScanM5  ? CurrentClosedBias(PERIOD_M5)  : 0;
   g_bias_m15=ScanM15 ? CurrentClosedBias(PERIOD_M15) : 0;
   g_bias_m30=ScanM30 ? CurrentClosedBias(PERIOD_M30) : 0;
   g_bias_h1 =ScanH1  ? CurrentClosedBias(PERIOD_H1)  : 0;
   g_bias_h4 =ScanH4  ? CurrentClosedBias(PERIOD_H4)  : 0;
   g_bias_d1 =ScanD1  ? CurrentClosedBias(PERIOD_D1)  : 0;

   double buy_weight=0.0,sell_weight=0.0,total_weight=0.0;
   bool missing=false;
   AddWeightedBias(ScanM5,g_bias_m5,WeightM5,buy_weight,sell_weight,total_weight,missing);
   AddWeightedBias(ScanM15,g_bias_m15,WeightM15,buy_weight,sell_weight,total_weight,missing);
   AddWeightedBias(ScanM30,g_bias_m30,WeightM30,buy_weight,sell_weight,total_weight,missing);
   AddWeightedBias(ScanH1,g_bias_h1,WeightH1,buy_weight,sell_weight,total_weight,missing);
   AddWeightedBias(ScanH4,g_bias_h4,WeightH4,buy_weight,sell_weight,total_weight,missing);
   AddWeightedBias(ScanD1,g_bias_d1,WeightD1,buy_weight,sell_weight,total_weight,missing);

   if(total_weight>0.0)
     {
      g_current_buy_strength=100.0*buy_weight/total_weight;
      g_current_sell_strength=100.0*sell_weight/total_weight;
     }
   else
     {
      g_current_buy_strength=0.0;
      g_current_sell_strength=0.0;
     }
  }

void HistoricalMTFStrength(const datetime signal_time,double &buy_strength,
                           double &sell_strength,bool &history_missing)
  {
   buy_strength=0.0;
   sell_strength=0.0;
   history_missing=false;

   // Filtering can remain active even when the live scanner rows are hidden.
   double buy_weight=0.0,sell_weight=0.0,total_weight=0.0;
   bool available=false;
   int direction=0;

   if(ScanM5)
     {
      direction=BiasAtDecisionTime(PERIOD_M5,signal_time,available);
      if(!available) history_missing=true;
      else AddWeightedBias(true,direction,WeightM5,buy_weight,sell_weight,total_weight,history_missing);
     }
   if(ScanM15)
     {
      direction=BiasAtDecisionTime(PERIOD_M15,signal_time,available);
      if(!available) history_missing=true;
      else AddWeightedBias(true,direction,WeightM15,buy_weight,sell_weight,total_weight,history_missing);
     }
   if(ScanM30)
     {
      direction=BiasAtDecisionTime(PERIOD_M30,signal_time,available);
      if(!available) history_missing=true;
      else AddWeightedBias(true,direction,WeightM30,buy_weight,sell_weight,total_weight,history_missing);
     }
   if(ScanH1)
     {
      direction=BiasAtDecisionTime(PERIOD_H1,signal_time,available);
      if(!available) history_missing=true;
      else AddWeightedBias(true,direction,WeightH1,buy_weight,sell_weight,total_weight,history_missing);
     }
   if(ScanH4)
     {
      direction=BiasAtDecisionTime(PERIOD_H4,signal_time,available);
      if(!available) history_missing=true;
      else AddWeightedBias(true,direction,WeightH4,buy_weight,sell_weight,total_weight,history_missing);
     }
   if(ScanD1)
     {
      direction=BiasAtDecisionTime(PERIOD_D1,signal_time,available);
      if(!available) history_missing=true;
      else AddWeightedBias(true,direction,WeightD1,buy_weight,sell_weight,total_weight,history_missing);
     }

   if(total_weight>0.0)
     {
      buy_strength=100.0*buy_weight/total_weight;
      sell_strength=100.0*sell_weight/total_weight;
     }
  }

bool SessionAllows(const datetime bar_time)
  {
   int weekday=TimeDayOfWeek(bar_time);
   if(weekday==0 && !TradeSunday)   return(false);
   if(weekday==1 && !TradeMonday)   return(false);
   if(weekday==2 && !TradeTuesday)  return(false);
   if(weekday==3 && !TradeWednesday)return(false);
   if(weekday==4 && !TradeThursday) return(false);
   if(weekday==5 && !TradeFriday)   return(false);
   if(weekday==6 && !TradeSaturday) return(false);

   if(!UseSessionFilter) return(true);
   int hour=TimeHour(bar_time);
   int start=ClampInt(SessionStartHour,0,23);
   int finish=ClampInt(SessionEndHour,0,24);
   if(start==finish || (start==0 && finish==24)) return(true);
   if(start<finish) return(hour>=start && hour<finish);
   return(hour>=start || hour<finish); // overnight window
  }

//+------------------------------------------------------------------+
//| Signal construction                                               |
//+------------------------------------------------------------------+
bool FindOrderBlock(const int direction,const int signal_shift,
                    double &zone_low,double &zone_high,int &order_shift)
  {
   zone_low=0.0;
   zone_high=0.0;
   order_shift=-1;
   int total=iBars(NULL,0);
   int limit=MathMin(total-1,signal_shift+MathMax(1,OrderBlockLookback));
   for(int i=signal_shift+1;i<=limit;i++)
     {
      double open=iOpen(NULL,0,i);
      double close=iClose(NULL,0,i);
      bool opposite=(direction>0 ? close<open : close>open);
      if(opposite)
        {
         zone_low=iLow(NULL,0,i);
         zone_high=iHigh(NULL,0,i);
         order_shift=i;
         return(true);
        }
     }
   return(false);
  }

double RecentExtreme(const int direction,const int signal_shift)
  {
   int count=MathMax(1,StopLookbackBars);
   int total=iBars(NULL,0);
   count=MathMin(count,total-signal_shift);
   if(count<=0) return(iClose(NULL,0,signal_shift));
   if(direction>0)
     {
      int low_shift=iLowest(NULL,0,MODE_LOW,count,signal_shift);
      return(iLow(NULL,0,low_shift));
     }
   int high_shift=iHighest(NULL,0,MODE_HIGH,count,signal_shift);
   return(iHigh(NULL,0,high_shift));
  }

void CalculateTradeLevels(SignalInfo &signal,const double last_swing_high,
                          const double last_swing_low)
  {
   double point=Point;
   double atr=iATR(NULL,0,MathMax(1,ATRPeriod),signal.shift);
   if(atr<=0.0) atr=MathMax(point*100.0,iHigh(NULL,0,signal.shift)-iLow(NULL,0,signal.shift));
   double buffer=MathMax(0.0,StopBufferPoints)*point;
   double stop=0.0;

   if(g_active_stop_mode==STOP_LAST_OPPOSITE_SWING)
      stop=(signal.direction>0 ? last_swing_low-buffer : last_swing_high+buffer);
   else if(g_active_stop_mode==STOP_BEHIND_ORDER_BLOCK && signal.order_shift>=0)
      stop=(signal.direction>0 ? signal.order_low-buffer : signal.order_high+buffer);
   else if(g_active_stop_mode==STOP_RECENT_HIGH_LOW)
      stop=(signal.direction>0 ? RecentExtreme(1,signal.shift)-buffer : RecentExtreme(-1,signal.shift)+buffer);
   else if(g_active_stop_mode==STOP_FIXED_POINTS)
      stop=signal.entry-signal.direction*MathMax(1.0,FixedStopPoints)*point;
   else
      stop=signal.entry-signal.direction*MathMax(0.1,g_active_sl_atr)*atr;

   // Invalid structural stops fall back to an ATR distance.
   if(stop<=0.0 || (signal.direction>0 && stop>=signal.entry) ||
      (signal.direction<0 && stop<=signal.entry))
      stop=signal.entry-signal.direction*MathMax(0.1,g_active_sl_atr)*atr;

   double risk=MathAbs(signal.entry-stop);
   if(MaxRiskPoints>0.0 && risk>MaxRiskPoints*point)
     {
      risk=MaxRiskPoints*point;
      stop=signal.entry-signal.direction*risk;
     }
   risk=MathMax(point,risk);
   signal.stop=NormalizeDouble(stop,Digits);

   if(TakeProfitMode==TAKE_PROFIT_RISK_REWARD)
     {
      signal.target1=signal.entry+signal.direction*risk*MathMax(0.1,RiskRewardTP1);
      signal.target2=signal.entry+signal.direction*risk*MathMax(RiskRewardTP1,RiskRewardTP2);
      signal.target3=signal.entry+signal.direction*risk*MathMax(RiskRewardTP2,RiskRewardTP3);
     }
   else
     {
      signal.target1=signal.entry+signal.direction*atr*MathMax(0.1,g_active_tp1_atr);
      signal.target2=signal.entry+signal.direction*atr*MathMax(g_active_tp1_atr,ATRTarget2Multiplier);
      signal.target3=signal.entry+signal.direction*atr*MathMax(ATRTarget2Multiplier,ATRTarget3Multiplier);
     }
   signal.target1=NormalizeDouble(signal.target1,Digits);
   signal.target2=NormalizeDouble(signal.target2,Digits);
   signal.target3=NormalizeDouble(signal.target3,Digits);
  }

void AppendSignal(SignalInfo &signals[],int &count,const int shift,const int raw_direction,
                  const int event_type,const double last_swing_high,const double last_swing_low)
  {
   int direction=(ReverseSignals ? -raw_direction : raw_direction);
   ArrayResize(signals,count+1);

   signals[count].shift=shift;
   signals[count].direction=direction;
   signals[count].event_type=event_type;
   signals[count].time=iTime(NULL,0,shift);
   signals[count].entry=NormalizeDouble(iClose(NULL,0,shift),Digits);
   signals[count].stop=0.0;
   signals[count].target1=0.0;
   signals[count].target2=0.0;
   signals[count].target3=0.0;
   signals[count].order_low=0.0;
   signals[count].order_high=0.0;
   signals[count].order_shift=-1;
   signals[count].mtf_buy=0.0;
   signals[count].mtf_sell=0.0;
   signals[count].accepted=true;
   signals[count].closed=false;
   signals[count].won=false;
   signals[count].exit_shift=-1;
   signals[count].pnl=0.0;

   FindOrderBlock(direction,shift,signals[count].order_low,
                  signals[count].order_high,signals[count].order_shift);
   CalculateTradeLevels(signals[count],last_swing_high,last_swing_low);

   if(!SessionAllows(signals[count].time))
      signals[count].accepted=false;

   if(UseMTFFilter)
     {
      bool missing=false;
      HistoricalMTFStrength(signals[count].time,signals[count].mtf_buy,
                            signals[count].mtf_sell,missing);
      double directional_strength=(direction>0 ? signals[count].mtf_buy : signals[count].mtf_sell);
      if(directional_strength+0.0001<g_active_mtf_threshold)
         signals[count].accepted=false;
      if(missing && RejectWhenMTFHistoryMissing)
         signals[count].accepted=false;
     }
   count++;
  }

int BuildSignals(SignalInfo &signals[],const int requested_bars,const bool update_bias)
  {
   ArrayResize(signals,0);
   int total=iBars(NULL,0);
   int strength=ClampInt(g_active_swing,1,10);
   int bars=MathMin(MathMax(100,requested_bars),total-strength*2-2);
   if(bars<=strength*2+10) return(0);

   // Warm-up extends beyond the requested test region so the first tested
   // bars already have valid market-structure state.
   int oldest=MathMin(total-strength-2,bars+MathMax(100,ScannerBars/2)+strength*2);
   double swing_high=0.0,swing_low=0.0;
   bool high_broken=true,low_broken=true;
   int trend=0;
   int count=0;

   for(int i=oldest;i>=1;i--)
     {
      int pivot=i+strength;
      if(pivot+strength<total)
        {
         if(IsSwingHighTF(0,pivot,strength))
           {
            swing_high=iHigh(NULL,0,pivot);
            high_broken=false;
           }
         if(IsSwingLowTF(0,pivot,strength))
           {
            swing_low=iLow(NULL,0,pivot);
            low_broken=false;
           }
        }

      double close_now=iClose(NULL,0,i);
      double close_old=iClose(NULL,0,i+1);
      if(swing_high>0.0 && !high_broken && close_now>swing_high && close_old<=swing_high)
        {
         int event_type=(trend<0 ? 2 : 1);
         trend=1;
         high_broken=true;
         if(i<=bars && (!g_active_choch_only || event_type==2))
            AppendSignal(signals,count,i,1,event_type,swing_high,swing_low);
        }
      else if(swing_low>0.0 && !low_broken && close_now<swing_low && close_old>=swing_low)
        {
         int event_type=(trend>0 ? 2 : 1);
         trend=-1;
         low_broken=true;
         if(i<=bars && (!g_active_choch_only || event_type==2))
            AppendSignal(signals,count,i,-1,event_type,swing_high,swing_low);
        }
     }

   if(update_bias) g_structure_bias=trend;
   return(count);
  }

//+------------------------------------------------------------------+
//| Historical test model                                            |
//+------------------------------------------------------------------+
double EffectiveSpreadPoints()
  {
   double spread=(OverrideSpreadPoints>0.0 ? OverrideSpreadPoints : MarketInfo(Symbol(),MODE_SPREAD));
   return(MathMax(0.0,spread+ExtraSpreadPoints));
  }

double PriceMoveToMoney(const double signed_price_move,const double lot)
  {
   double tick_size=MarketInfo(Symbol(),MODE_TICKSIZE);
   double tick_value=MarketInfo(Symbol(),MODE_TICKVALUE);
   if(tick_size<=0.0) tick_size=Point;
   if(tick_value<=0.0) tick_value=1.0;
   double gross=signed_price_move/tick_size*tick_value*lot;
   double spread_cost=EffectiveSpreadPoints()*Point/tick_size*tick_value*lot;
   double commission=MathMax(0.0,CommissionPerLotRoundTurn)*lot;
   return(gross-spread_cost-commission);
  }

void AddClosedTrade(TestStats &stats,const double pnl)
  {
   stats.total++;
   if(pnl>=0.0)
     {
      stats.wins++;
      stats.gross_profit+=pnl;
     }
   else
     {
      stats.losses++;
      stats.gross_loss+=-pnl;
     }
   stats.net_profit+=pnl;
  }

void FinalizeStats(TestStats &stats)
  {
   int closed=stats.wins+stats.losses;
   stats.win_rate=(closed>0 ? 100.0*stats.wins/closed : 0.0);
   stats.profit_factor=(stats.gross_loss>0.0 ? stats.gross_profit/stats.gross_loss :
                        (stats.gross_profit>0.0 ? 999.0 : 0.0));
   stats.growth=(TestStartingBalance!=0.0 ? 100.0*stats.net_profit/TestStartingBalance : 0.0);
  }

void EvaluateSignals(SignalInfo &signals[],const int count,TestStats &stats,const double lot)
  {
   ResetStats(stats);
   for(int n=0;n<count;n++)
     {
      if(!signals[n].accepted) continue;
      bool finished=false;
      int held=0;
      for(int j=signals[n].shift-1;j>=0;j--)
        {
         held++;
         bool stop_hit=(signals[n].direction>0 ? iLow(NULL,0,j)<=signals[n].stop :
                                                iHigh(NULL,0,j)>=signals[n].stop);
         bool target_hit=(signals[n].direction>0 ? iHigh(NULL,0,j)>=signals[n].target1 :
                                                  iLow(NULL,0,j)<=signals[n].target1);

         // Conservative handling when both prices occur in one candle.
         if(stop_hit)
           {
            double move=signals[n].direction*(signals[n].stop-signals[n].entry);
            signals[n].pnl=PriceMoveToMoney(move,lot);
            signals[n].closed=true;
            signals[n].won=false;
            signals[n].exit_shift=j;
            AddClosedTrade(stats,signals[n].pnl);
            finished=true;
            break;
           }
         if(target_hit)
           {
            double move=signals[n].direction*(signals[n].target1-signals[n].entry);
            signals[n].pnl=PriceMoveToMoney(move,lot);
            signals[n].closed=true;
            signals[n].won=true;
            signals[n].exit_shift=j;
            AddClosedTrade(stats,signals[n].pnl);
            finished=true;
            break;
           }
         if(MaximumTradeBars>0 && held>=MaximumTradeBars)
           {
            double move=signals[n].direction*(iClose(NULL,0,j)-signals[n].entry);
            signals[n].pnl=PriceMoveToMoney(move,lot);
            signals[n].closed=true;
            signals[n].won=(signals[n].pnl>=0.0);
            signals[n].exit_shift=j;
            AddClosedTrade(stats,signals[n].pnl);
            finished=true;
            break;
           }
        }
      if(!finished)
        {
         signals[n].closed=false;
         signals[n].exit_shift=-1;
         stats.total++;
         stats.open_trades++;
        }
     }
   FinalizeStats(stats);
  }

void EvaluateSignalToSignal(SignalInfo &signals[],const int count,TestStats &stats)
  {
   ResetStats(stats);
   int previous=-1;
   for(int n=0;n<count;n++)
     {
      if(!signals[n].accepted) continue;
      if(previous<0)
        {
         previous=n;
         continue;
        }
      if(signals[n].direction==signals[previous].direction)
         continue;

      double move=signals[previous].direction*(signals[n].entry-signals[previous].entry);
      double pnl=PriceMoveToMoney(move,TestLotSize);
      AddClosedTrade(stats,pnl);
      previous=n;
     }
   if(previous>=0)
     {
      stats.total++;
      stats.open_trades++;
     }
   FinalizeStats(stats);
  }

void EvaluateRecovery(SignalInfo &signals[],const int count,TestStats &stats)
  {
   ResetStats(stats);
   int loss_step=0;
   for(int n=0;n<count;n++)
     {
      if(!signals[n].accepted || !signals[n].closed) continue;
      int applied_step=MathMin(loss_step,MathMax(0,MaximumRecoverySteps));
      double lot=TestLotSize;
      if(RecoveryMode==RECOVERY_MULTIPLY)
         lot=TestLotSize*MathPow(MathMax(1.0,RecoveryFactor),applied_step);
      else if(RecoveryMode==RECOVERY_FIXED_ADD)
         lot=TestLotSize+MathMax(0.0,RecoveryLotStep)*applied_step;
      lot=MathMax(0.01,NormalizeDouble(lot,2));
      stats.max_lot=MathMax(stats.max_lot,lot);
      stats.max_step=MathMax(stats.max_step,applied_step);

      double exit_price=(signals[n].won ? signals[n].target1 : signals[n].stop);
      double move=signals[n].direction*(exit_price-signals[n].entry);
      double pnl=PriceMoveToMoney(move,lot);
      AddClosedTrade(stats,pnl);

      if(pnl>=0.0)
         loss_step=0;
      else
        {
         loss_step++;
         if(loss_step>MathMax(0,MaximumRecoverySteps))
            loss_step=0;
        }
     }
   FinalizeStats(stats);
  }

//+------------------------------------------------------------------+
//| Chart drawing                                                     |
//+------------------------------------------------------------------+
void SetTrendSegment(const string name,const datetime time1,const datetime time2,
                     const double price,const color line_color,const int style)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TREND,0,time1,price,time2,price);
   else
     {
      ObjectMove(0,name,0,time1,price);
      ObjectMove(0,name,1,time2,price);
     }
   ObjectSetInteger(0,name,OBJPROP_COLOR,line_color);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void SetPriceText(const string name,const datetime when,const double price,
                  const string text,const color text_color)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_TEXT,0,when,price);
   else
      ObjectMove(0,name,0,when,price);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void DrawOneSignal(const SignalInfo &signal,const int sequence)
  {
   string id=g_draw_prefix+IntegerToString((int)signal.time)+"_"+IntegerToString(sequence);
   datetime end_time=signal.time+SafePeriodSeconds(Period())*MathMax(2,TradeLineLengthBars);
   color direction_color=DirectionColor(signal.direction);
   string event_text=(signal.event_type==2 ? "CHoCH" : "BOS");

   if(DrawEntryStopTargetLines || (!signal.accepted && DrawRejectedTradeLevels))
     {
      color entry_color=(signal.accepted ? EntryColor : RejectedColor);
      color stop_color=(signal.accepted ? StopColor : RejectedColor);
      color target_color=(signal.accepted ? TargetColor : RejectedColor);
      SetTrendSegment(id+"_ENTRY",signal.time,end_time,signal.entry,entry_color,STYLE_DOT);
      SetTrendSegment(id+"_SL",signal.time,end_time,signal.stop,stop_color,STYLE_DASH);
      SetTrendSegment(id+"_TP1",signal.time,end_time,signal.target1,target_color,STYLE_SOLID);
      SetTrendSegment(id+"_TP2",signal.time,end_time,signal.target2,target_color,STYLE_DOT);
      SetTrendSegment(id+"_TP3",signal.time,end_time,signal.target3,target_color,STYLE_DOT);
      SetPriceText(id+"_ENTRY_TXT",end_time,signal.entry,"Entry "+DoubleToString(signal.entry,Digits),entry_color);
      SetPriceText(id+"_SL_TXT",end_time,signal.stop,"SL "+DoubleToString(signal.stop,Digits),stop_color);
      SetPriceText(id+"_TP_TXT",end_time,signal.target1,"TP1 "+DoubleToString(signal.target1,Digits),target_color);
     }

   double atr=iATR(NULL,0,MathMax(1,ATRPeriod),signal.shift);
   double label_price=(signal.direction>0 ? iLow(NULL,0,signal.shift)-atr*0.30 :
                                             iHigh(NULL,0,signal.shift)+atr*0.30);
   SetPriceText(id+"_EVENT",signal.time,label_price,
                (signal.accepted ? event_text+" "+DirectionText(signal.direction) : "REJECTED "+event_text),
                (signal.accepted ? direction_color : RejectedColor));

   if(DrawOrderBlocks && signal.order_shift>=0 && signal.order_low>0.0)
     {
      string ob_name=id+"_OB";
      datetime ob_time=iTime(NULL,0,signal.order_shift);
      if(ObjectFind(0,ob_name)<0)
         ObjectCreate(0,ob_name,OBJ_RECTANGLE,0,ob_time,signal.order_low,end_time,signal.order_high);
      ObjectSetInteger(0,ob_name,OBJPROP_COLOR,(signal.accepted ? direction_color : RejectedColor));
      ObjectSetInteger(0,ob_name,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,ob_name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,ob_name,OBJPROP_BACK,true);
      ObjectSetInteger(0,ob_name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,ob_name,OBJPROP_HIDDEN,true);
     }
  }

void RenderSignals(SignalInfo &signals[],const int count,const int rates_total)
  {
   ArrayInitialize(BuySignalBuffer,EMPTY_VALUE);
   ArrayInitialize(SellSignalBuffer,EMPTY_VALUE);
   ArrayInitialize(RejectedBuyBuffer,EMPTY_VALUE);
   ArrayInitialize(RejectedSellBuffer,EMPTY_VALUE);
   DeleteObjectsWithPrefix(g_draw_prefix);

   int accepted_drawn=0;
   int rejected_drawn=0;
   for(int n=count-1;n>=0;n--)
     {
      int shift=signals[n].shift;
      if(shift<0 || shift>=rates_total) continue;
      double atr=iATR(NULL,0,MathMax(1,ATRPeriod),shift);
      if(atr<=0.0) atr=100.0*Point;

      if(signals[n].accepted && accepted_drawn<MathMax(1,MaxSignalsOnChart))
        {
         if(signals[n].direction>0)
            BuySignalBuffer[shift]=iLow(NULL,0,shift)-atr*0.12;
         else
            SellSignalBuffer[shift]=iHigh(NULL,0,shift)+atr*0.12;
         DrawOneSignal(signals[n],accepted_drawn);
         accepted_drawn++;
        }
      else if(!signals[n].accepted && DrawRejectedSignals &&
              rejected_drawn<MathMax(1,MaxSignalsOnChart))
        {
         if(signals[n].direction>0)
            RejectedBuyBuffer[shift]=iLow(NULL,0,shift)-atr*0.08;
         else
            RejectedSellBuffer[shift]=iHigh(NULL,0,shift)+atr*0.08;
         DrawOneSignal(signals[n],1000+rejected_drawn);
         rejected_drawn++;
        }
      if(accepted_drawn>=MathMax(1,MaxSignalsOnChart) &&
         (!DrawRejectedSignals || rejected_drawn>=MathMax(1,MaxSignalsOnChart)))
         break;
     }
  }

//+------------------------------------------------------------------+
//| Dashboard                                                         |
//+------------------------------------------------------------------+
void CreateRectangleLabel(const string name,const int x,const int y,const int width,
                          const int height,const color background,const color border)
  {
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,DashboardCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void SetPanelLine(const int row,const string text,const color text_color,const bool bold=false)
  {
   string name=g_panel_prefix+"L"+IntegerToString(row);
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,DashboardCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,DashboardX+10);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,DashboardY+10+row*16);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,(DashboardCorner==CORNER_RIGHT_UPPER || DashboardCorner==CORNER_RIGHT_LOWER) ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,(bold ? "Arial Bold" : "Consolas"));
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,DashboardFontSize);
   ObjectSetInteger(0,name,OBJPROP_COLOR,text_color);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void CreateButton(const string suffix,const string text,const int x,const int y,
                  const int width,const color background)
  {
   string name=g_panel_prefix+suffix;
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,DashboardCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,20);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,background);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrDimGray);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

string BiasListText(const string tf,const int bias)
  {
   return(tf+": "+DirectionText(bias));
  }

void CreateOrUpdateDashboard()
  {
   if(!ShowDashboard)
     {
      DeleteObjectsWithPrefix(g_panel_prefix);
      return;
     }

   int height=(g_panel_collapsed ? 44 : 590);
   CreateRectangleLabel(g_panel_prefix+"BG",DashboardX,DashboardY,DashboardWidth,height,
                        C'18,22,28',C'70,80,92');

   if(g_panel_collapsed)
     {
      SetPanelLine(0,"ADAPTIVE SMC DASHBOARD",clrWhite,true);
      CreateButton("TOGGLE","+",DashboardX+DashboardWidth-28,DashboardY+7,20,C'50,80,110');
      return;
     }

   string active=(g_using_optimized ? "OPTIMIZED" : "MANUAL");
   SetPanelLine(0,"ADAPTIVE SMC DASHBOARD  ["+active+"]",clrWhite,true);
   SetPanelLine(1,Symbol()+"  "+TimeframeText(Period())+"  | Structure: "+DirectionText(g_structure_bias),DirectionColor(g_structure_bias));
   SetPanelLine(2,"Swing "+IntegerToString(g_active_swing)+" | "+StopModeText(g_active_stop_mode)+
                  " | TP ATR "+DoubleToString(g_active_tp1_atr,1),clrSilver);

   SetPanelLine(4,"MULTI-TIMEFRAME SCANNER",C'90,190,255',true);
   SetPanelLine(5,BiasListText("M5 ",g_bias_m5)+"   "+BiasListText("M15",g_bias_m15),clrGainsboro);
   SetPanelLine(6,BiasListText("M30",g_bias_m30)+"   "+BiasListText("H1 ",g_bias_h1),clrGainsboro);
   SetPanelLine(7,BiasListText("H4 ",g_bias_h4)+"   "+BiasListText("D1 ",g_bias_d1),clrGainsboro);
   SetPanelLine(8,"BUY "+DoubleToString(g_current_buy_strength,1)+"%   SELL "+
                  DoubleToString(g_current_sell_strength,1)+"%",
                  (g_current_buy_strength>=g_current_sell_strength ? BuyColor : SellColor),true);
   int agreement_direction=0;
   if(g_current_buy_strength>g_current_sell_strength+0.0001) agreement_direction=1;
   if(g_current_sell_strength>g_current_buy_strength+0.0001) agreement_direction=-1;
   string agreement=DirectionText(agreement_direction);
   SetPanelLine(9,"Agreement: "+agreement+" | filter "+(UseMTFFilter ? "ON" : "OFF")+
                  " >= "+DoubleToString(g_active_mtf_threshold,0)+"%",clrSilver);

   SetPanelLine(11,"HISTORICAL TP1 TEST",C'90,190,255',true);
   SetPanelLine(12,"Signals "+IntegerToString(g_stats.total)+" | W "+IntegerToString(g_stats.wins)+
                   " | L "+IntegerToString(g_stats.losses)+" | Open "+IntegerToString(g_stats.open_trades),clrGainsboro);
   SetPanelLine(13,"Win "+DoubleToString(g_stats.win_rate,1)+"% | PF "+
                   DoubleToString(g_stats.profit_factor,2),clrGainsboro);

   if(g_has_latest_signal)
     {
      SetPanelLine(14,"Last: "+DirectionText(g_latest_signal.direction)+" "+
                      (g_latest_signal.event_type==2 ? "CHoCH" : "BOS")+
                      " | MTF "+DoubleToString((g_latest_signal.direction>0 ? g_latest_signal.mtf_buy : g_latest_signal.mtf_sell),0)+"%",
                      DirectionColor(g_latest_signal.direction),true);
      SetPanelLine(15,"Entry "+DoubleToString(g_latest_signal.entry,Digits)+" | SL "+
                      DoubleToString(g_latest_signal.stop,Digits),clrGainsboro);
      SetPanelLine(16,"TP1 "+DoubleToString(g_latest_signal.target1,Digits)+" | TP2 "+
                      DoubleToString(g_latest_signal.target2,Digits),clrGainsboro);
     }
   else
     {
      SetPanelLine(14,"Last: no accepted setup in test window",clrSilver);
      SetPanelLine(15,"Entry -- | SL --",clrSilver);
      SetPanelLine(16,"TP1 -- | TP2 --",clrSilver);
     }

   SetPanelLine(18,"MONEY MODEL",C'90,190,255',true);
   SetPanelLine(19,"Start "+DoubleToString(TestStartingBalance,2)+" | Lot "+DoubleToString(TestLotSize,2)+
                   " | Spread "+DoubleToString(EffectiveSpreadPoints(),0),clrGainsboro);
   SetPanelLine(20,"Gross +"+DoubleToString(g_stats.gross_profit,2)+"  -"+
                   DoubleToString(g_stats.gross_loss,2),clrGainsboro);
   SetPanelLine(21,"Net "+DoubleToString(g_stats.net_profit,2)+" | Growth "+
                   DoubleToString(g_stats.growth,1)+"%",(g_stats.net_profit>=0.0 ? BuyColor : SellColor),true);

   SetPanelLine(23,"SIGNAL-TO-SIGNAL",C'90,190,255',true);
   SetPanelLine(24,"Trades "+IntegerToString(g_signal_to_signal_stats.total)+" | W "+
                   IntegerToString(g_signal_to_signal_stats.wins)+" | L "+
                   IntegerToString(g_signal_to_signal_stats.losses),clrGainsboro);
   SetPanelLine(25,"Net "+DoubleToString(g_signal_to_signal_stats.net_profit,2)+" | Growth "+
                   DoubleToString(g_signal_to_signal_stats.growth,1)+"%",
                   (g_signal_to_signal_stats.net_profit>=0.0 ? BuyColor : SellColor));

   SetPanelLine(27,"RECOVERY SIMULATION",C'90,190,255',true);
   SetPanelLine(28,RecoveryModeText(RecoveryMode)+" | Max lot "+DoubleToString(g_recovery_stats.max_lot,2)+
                   " | Step "+IntegerToString(g_recovery_stats.max_step),clrGainsboro);
   SetPanelLine(29,"Net "+DoubleToString(g_recovery_stats.net_profit,2)+" | Growth "+
                   DoubleToString(g_recovery_stats.growth,1)+"%",
                   (g_recovery_stats.net_profit>=0.0 ? BuyColor : SellColor));

   SetPanelLine(31,(g_optimizing ? "Optimizer is running..." :
                   "Closed candles only | intrabar ties -> SL"),
                   (g_optimizing ? clrGold : clrDarkGray));

   int button_y=DashboardY+540;
   if(EnableOptimizerButton)
      CreateButton("OPTIMIZE","OPTIMIZE",DashboardX+10,button_y,92,C'25,105,80');
   CreateButton("RESET","RESET",DashboardX+108,button_y,72,C'110,65,35');
   CreateButton("TOGGLE","-",DashboardX+DashboardWidth-28,DashboardY+7,20,C'50,80,110');
  }

//+------------------------------------------------------------------+
//| Optimizer                                                         |
//+------------------------------------------------------------------+
double OptimizationScore(const TestStats &stats)
  {
   int closed=stats.wins+stats.losses;
   if(closed<MathMax(1,MinimumOptimizationTrades)) return(-1.0e100);
   if(OptimizeFor==OPTIMIZE_PROFIT_FACTOR)
      return(stats.profit_factor*1000.0+stats.net_profit*0.001);
   if(OptimizeFor==OPTIMIZE_WIN_RATE)
      return(stats.win_rate*1000.0+stats.net_profit*0.001);
   if(OptimizeFor==OPTIMIZE_PROFIT_TRADE)
      return(stats.net_profit/closed);
   return(stats.net_profit);
  }

void RunOptimizer()
  {
   if(!EnableOptimizerButton || g_optimizing) return;
   g_optimizing=true;
   CreateOrUpdateDashboard();
   ChartRedraw();

   int old_swing=g_active_swing;
   ENUM_SMC_STOP_MODE old_stop=g_active_stop_mode;
   double old_sl=g_active_sl_atr;
   double old_tp=g_active_tp1_atr;
   bool old_choch=g_active_choch_only;
   double old_mtf=g_active_mtf_threshold;

   int tests=24;
   if(OptimizerDepth==SEARCH_NORMAL) tests=72;
   if(OptimizerDepth==SEARCH_FULL)   tests=180;

   double best_score=-1.0e100;
   int best_swing=old_swing;
   ENUM_SMC_STOP_MODE best_stop=old_stop;
   double best_sl=old_sl;
   double best_tp=old_tp;
   bool best_choch=old_choch;
   double best_mtf=old_mtf;

   for(int test=0;test<tests && !IsStopped();test++)
     {
      if(test==0)
        {
         g_active_swing=old_swing;
         g_active_stop_mode=old_stop;
         g_active_sl_atr=old_sl;
         g_active_tp1_atr=old_tp;
         g_active_choch_only=old_choch;
         g_active_mtf_threshold=old_mtf;
        }
      else
        {
         g_active_swing=2+((test*3+test/7)%5); // 2..6
         int stop_pick=(test*5+test/3)%4;
         if(stop_pick==0) g_active_stop_mode=STOP_LAST_OPPOSITE_SWING;
         if(stop_pick==1) g_active_stop_mode=STOP_BEHIND_ORDER_BLOCK;
         if(stop_pick==2) g_active_stop_mode=STOP_RECENT_HIGH_LOW;
         if(stop_pick==3) g_active_stop_mode=STOP_ATR_DISTANCE;
         g_active_sl_atr=1.0+0.5*((test*7+test/5)%4);
         g_active_tp1_atr=1.5+0.5*((test*11+test/2)%6);
         g_active_choch_only=(((test*13+test/4)%4)==0);
         int threshold_pick=(test*17+test/6)%4;
         if(threshold_pick==0) g_active_mtf_threshold=50.0;
         if(threshold_pick==1) g_active_mtf_threshold=60.0;
         if(threshold_pick==2) g_active_mtf_threshold=75.0;
         if(threshold_pick==3) g_active_mtf_threshold=80.0;
        }

      SignalInfo trial_signals[];
      int trial_count=BuildSignals(trial_signals,MathMax(200,OptimizationBars),false);
      TestStats trial_stats;
      EvaluateSignals(trial_signals,trial_count,trial_stats,TestLotSize);
      double score=OptimizationScore(trial_stats);
      if(score>best_score)
        {
         best_score=score;
         best_swing=g_active_swing;
         best_stop=g_active_stop_mode;
         best_sl=g_active_sl_atr;
         best_tp=g_active_tp1_atr;
         best_choch=g_active_choch_only;
         best_mtf=g_active_mtf_threshold;
        }
     }

   if(best_score<=-1.0e99)
     {
      g_active_swing=old_swing;
      g_active_stop_mode=old_stop;
      g_active_sl_atr=old_sl;
      g_active_tp1_atr=old_tp;
      g_active_choch_only=old_choch;
      g_active_mtf_threshold=old_mtf;
      Print("Adaptive SMC: optimizer found no configuration with enough closed trades.");
     }
   else
     {
      g_active_swing=best_swing;
      g_active_stop_mode=best_stop;
      g_active_sl_atr=best_sl;
      g_active_tp1_atr=best_tp;
      g_active_choch_only=best_choch;
      g_active_mtf_threshold=best_mtf;
      g_using_optimized=true;
      SaveActiveSettings();
      Print("Adaptive SMC: optimized settings selected. Swing=",best_swing,
            ", stop=",StopModeText(best_stop),", SL ATR=",DoubleToString(best_sl,1),
            ", TP ATR=",DoubleToString(best_tp,1),", score=",DoubleToString(best_score,2));
     }

   g_optimizing=false;
   g_force_rebuild=true;
  }

//+------------------------------------------------------------------+
//| Alerts and full recalculation                                     |
//+------------------------------------------------------------------+
void FindLatestAccepted(SignalInfo &signals[],const int count)
  {
   g_has_latest_signal=false;
   for(int n=count-1;n>=0;n--)
     {
      if(signals[n].accepted)
        {
         g_latest_signal=signals[n];
         g_has_latest_signal=true;
         return;
        }
     }
  }

void CheckSignalAlert()
  {
   if(!g_has_latest_signal) return;
   if(g_latest_signal.time<=g_last_alerted_signal) return;
   if(g_latest_signal.shift!=1)
     {
      g_last_alerted_signal=g_latest_signal.time;
      return;
     }

   string message="Adaptive SMC "+Symbol()+" "+TimeframeText(Period())+" "+
                  DirectionText(g_latest_signal.direction)+" "+
                  (g_latest_signal.event_type==2 ? "CHoCH" : "BOS")+
                  " | Entry "+DoubleToString(g_latest_signal.entry,Digits)+
                  " SL "+DoubleToString(g_latest_signal.stop,Digits)+
                  " TP1 "+DoubleToString(g_latest_signal.target1,Digits);
   if(EnablePopupAlerts) Alert(message);
   if(EnablePushNotifications) SendNotification(message);
   g_last_alerted_signal=g_latest_signal.time;
  }

void RebuildIndicator(const int rates_total)
  {
   SignalInfo signals[];
   int count=BuildSignals(signals,MathMax(100,MaxBarsToAnalyze),true);
   EvaluateSignals(signals,count,g_stats,TestLotSize);
   EvaluateSignalToSignal(signals,count,g_signal_to_signal_stats);
   EvaluateRecovery(signals,count,g_recovery_stats);
   FindLatestAccepted(signals,count);
   CalculateCurrentScanner();
   RenderSignals(signals,count,rates_total);
   CreateOrUpdateDashboard();
   CheckSignalAlert();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Standard MT4 event handlers                                       |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_prefix="ASMC_"+IntegerToString((int)ChartID())+"_";
   g_draw_prefix=g_prefix+"DRAW_";
   g_panel_prefix=g_prefix+"PANEL_";

   SetIndexBuffer(0,BuySignalBuffer);
   SetIndexStyle(0,DRAW_ARROW,STYLE_SOLID,1,BuyColor);
   SetIndexArrow(0,233);
   SetIndexLabel(0,"SMC Buy");
   SetIndexEmptyValue(0,EMPTY_VALUE);

   SetIndexBuffer(1,SellSignalBuffer);
   SetIndexStyle(1,DRAW_ARROW,STYLE_SOLID,1,SellColor);
   SetIndexArrow(1,234);
   SetIndexLabel(1,"SMC Sell");
   SetIndexEmptyValue(1,EMPTY_VALUE);

   SetIndexBuffer(2,RejectedBuyBuffer);
   SetIndexStyle(2,DRAW_ARROW,STYLE_SOLID,1,RejectedColor);
   SetIndexArrow(2,233);
   SetIndexLabel(2,"Rejected Buy");
   SetIndexEmptyValue(2,EMPTY_VALUE);

   SetIndexBuffer(3,RejectedSellBuffer);
   SetIndexStyle(3,DRAW_ARROW,STYLE_SOLID,1,RejectedColor);
   SetIndexArrow(3,234);
   SetIndexLabel(3,"Rejected Sell");
   SetIndexEmptyValue(3,EMPTY_VALUE);

   ArraySetAsSeries(BuySignalBuffer,true);
   ArraySetAsSeries(SellSignalBuffer,true);
   ArraySetAsSeries(RejectedBuyBuffer,true);
   ArraySetAsSeries(RejectedSellBuffer,true);

   IndicatorShortName("Adaptive SMC Dashboard");
   ResetActiveSettings(false);
   if(ReloadSavedSettingsAtStart) LoadActiveSettings();

   ResetStats(g_stats);
   ResetStats(g_signal_to_signal_stats);
   ResetStats(g_recovery_stats);
   g_last_alerted_signal=iTime(NULL,0,1);
   g_last_chart_bar=0;
   g_force_rebuild=true;
   EventSetTimer(2);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteObjectsWithPrefix(g_prefix);
  }

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   if(rates_total<100) return(0);
   datetime current_bar=iTime(NULL,0,0);
   if(g_force_rebuild || current_bar!=g_last_chart_bar || prev_calculated==0)
     {
      g_force_rebuild=false;
      g_last_chart_bar=current_bar;
      RebuildIndicator(rates_total);
     }
   return(rates_total);
  }

void OnTimer()
  {
   if(g_optimizing) return;
   datetime current_bar=iTime(NULL,0,0);
   if(current_bar!=g_last_chart_bar)
     {
      g_force_rebuild=true;
      ChartRedraw();
     }
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK) return;

   if(sparam==g_panel_prefix+"OPTIMIZE")
     {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      RunOptimizer();
      if(g_force_rebuild)
        {
         g_force_rebuild=false;
         RebuildIndicator(Bars);
        }
     }
   else if(sparam==g_panel_prefix+"RESET")
     {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      ResetActiveSettings(true);
      g_force_rebuild=false;
      RebuildIndicator(Bars);
     }
   else if(sparam==g_panel_prefix+"TOGGLE")
     {
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      g_panel_collapsed=!g_panel_collapsed;
      DeleteObjectsWithPrefix(g_panel_prefix);
      CreateOrUpdateDashboard();
      ChartRedraw();
     }
  }
//+------------------------------------------------------------------+
