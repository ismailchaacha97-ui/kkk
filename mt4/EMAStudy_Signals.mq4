//+------------------------------------------------------------------+
//|                                            EMAStudy_Signals.mq4 |
//|          EMA(60)/EMA(132) regime overlay, as measured by the    |
//|      multi-market study (82 markets, 1970-2026, 9,761,738      |
//|      backtests). It draws the pair, marks the flips you can     |
//|      actually trade, and replays the study's accounting on THIS |
//|      symbol/timeframe so you can check whether the edge is      |
//|      present in your own broker's data instead of trusting mine.|
//|                                                                  |
//|      No repaint: the state for a bar is decided by the EMA of   |
//|      the last CLOSED bar of SignalTimeframe - the same one-bar  |
//|      lag the backtester used (Bessembinder & Chan, 1995).       |
//|      Target: MT4 build 600+ (any current build).               |
//+------------------------------------------------------------------+
#property copyright   "EMA pair study"
#property link        "https://github.com/ismailchaacha97-ui/kkk"
#property version     "1.00"
#property description "Fast/slow EMA regime overlay + on-chart replication of the study."
#property description "Studied config: daily bars, EMA 60/132, long/flat, 6 bps per position change."
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "Fast EMA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_label2  "Slow EMA"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2
#property indicator_label3  "Go long"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_width3  2
#property indicator_label4  "Exit / go short"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrTomato
#property indicator_width4  2

enum ENUM_EMA_MODE
  {
   EMA_LONG_FLAT  = 0,   // long when fast>slow, else flat
   EMA_LONG_SHORT = 1    // long when fast>slow, short when fast<slow
  };

input ENUM_EMA_MODE       TradingMode      = EMA_LONG_FLAT;      // position style
input int                 FastPeriod       = 60;                 // fast EMA, bars of SignalTimeframe
input int                 SlowPeriod       = 132;                // slow EMA, bars of SignalTimeframe
input ENUM_TIMEFRAMES     SignalTimeframe  = PERIOD_CURRENT;     // timeframe the signal is read on (study = D1)
input ENUM_MA_METHOD      MAMethod         = MODE_EMA;           // MA type (MODE_SMA = the study's control)
input ENUM_APPLIED_PRICE  AppliedPrice     = PRICE_CLOSE;        // applied price
input double              CostBps          = 6.0;                // cost per position change, bps of notional
input int                 StatsYears       = 0;                  // replay window: 0 = all history, else N years
input bool                ShadeFlatSpells  = true;               // wash over the bars it sits in cash
input int                 MaxShadeRegions  = 250;                // ... at most this many rectangles
input bool                AlertOnFlip      = true;               // alert once, on the bar of the flip
input bool                UseSound         = true;               //
input string              SoundFile        = "alert.wav";        //
input bool                PushNotify       = false;              // mobile push as well

#define  MAX_CACHE  20000

double FastE[];
double SlowE[];
double ArrowUp[];
double ArrowDn[];

//--- EMA series on the signal timeframe, indexed by signal-TF shift (0 = current bar)
double   gF[];
double   gS[];
int      gN      = 0;
datetime gAnchor = 0;

//+------------------------------------------------------------------+
int Tf()
  {
   return((SignalTimeframe == PERIOD_CURRENT) ? Period() : SignalTimeframe);
  }

//+------------------------------------------------------------------+
string TfLabel(int tf)
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
   return("TF" + IntegerToString(tf));
  }

//+------------------------------------------------------------------+
//| (Re)build the signal-TF EMA cache. Rebuilt at most once per new |
//| signal bar, and never for more than MAX_CACHE bars, so a tick   |
//| chart cannot spend every minute recomputing hundreds of         |
//| thousands of averages.                                          |
//+------------------------------------------------------------------+
int EnsureCache()
  {
   int tf   = Tf();
   int need = iBars(NULL, tf);
   if(need < SlowPeriod + 3)
      return(0);
   if(need > MAX_CACHE)
      need = MAX_CACHE;

   datetime anchor = iTime(NULL, tf, 0);
   if(gN == need && gAnchor == anchor)
      return(gN);

   ArrayResize(gF, need);
   ArrayResize(gS, need);
   ArraySetAsSeries(gF, true);
   ArraySetAsSeries(gS, true);
   for(int s = 0; s < need; s++)
     {
      gF[s] = iMA(NULL, tf, FastPeriod, 0, MAMethod, AppliedPrice, s);
      gS[s] = iMA(NULL, tf, SlowPeriod, 0, MAMethod, AppliedPrice, s);
     }
   gN      = need;
   gAnchor = anchor;
   return(gN);
  }

//+------------------------------------------------------------------+
//| Signal-TF shift whose CLOSE decides the position for chart bar  |
//| `shift`. On the signal's own timeframe that is simply shift+1, |
//| i.e. "signal at the close of t-1, position over t" - the exact |
//| convention of the backtester. Returns -1 when no closed bar is  |
//| available (start of history).                                   |
//+------------------------------------------------------------------+
int DecideShift(int shift)
  {
   if(shift < 0)
      shift = 0;
   if(Tf() == Period())
      return(shift + 1);
   int k = iBarShift(NULL, Tf(), Time[shift], false);
   if(k < 0)
      return(-1);
   return(k + 1);
  }

//+------------------------------------------------------------------+
//| +1 long, 0 flat, -1 short (short only in EMA_LONG_SHORT).       |
//| Unknown range (older than the cache) also reads as 0, but        |
//| `Decidable()` is used anywhere that must not treat that as data. |
//+------------------------------------------------------------------+
bool Decidable(int shift)
  {
   int s = DecideShift(shift);
   return(s >= 1 && s < gN);
  }

int StateAt(int shift)
  {
   int s = DecideShift(shift);
   if(s < 1 || s >= gN)
      return(0);
   if(!MathIsValidNumber(gF[s]) || !MathIsValidNumber(gS[s]))
      return(0);
   if(gF[s] > gS[s])
      return(1);
   return((TradingMode == EMA_LONG_SHORT) ? -1 : 0);
  }

//+------------------------------------------------------------------+
//| Average seconds per bar of the signal timeframe, measured from  |
//| the data over several bars. One bar pair is not enough: a       |
//| Friday->Monday gap on D1 is 3 days, which would make a 132-bar  |
//| slow EMA look like 1.3 months instead of 6.3, and would size a   |
//| "last N years" window wrong by the same factor.                 |
//+------------------------------------------------------------------+
int TfSeconds()
  {
   int tf = Tf();
   int k  = 20;
   int a  = iTime(NULL, tf, 0);
   int b  = iTime(NULL, tf, k);
   if(a > b && k > 0)
      return((a - b) / k);
   return(86400);
  }

//+------------------------------------------------------------------+
//| The study's accounting, on this chart:                          |
//|   weight from the previous close, return close-to-close,        |
//|   CostBps per unit of position change, first `slow` bars dropped|
//|   annualisation measured from the data (bars per calendar year),|
//|   and buy & hold on the identical window.                        |
//+------------------------------------------------------------------+
void Replay(string &out)
  {
   int warm = SlowPeriod + 2;
   int i0   = Bars - 1 - warm;                       // oldest scorable chart bar
   if(StatsYears > 0)
     {
      datetime cut = (datetime)(Time[0] - (long)(StatsYears * 365.25 * 86400.0));
      while(i0 > 3 && Time[i0] < cut)
         i0--;                                        // walk to the oldest bar inside the window
     }
   if(i0 < 3)
     {
      out = "not enough history for a fair replay (need more than " + IntegerToString(warm + 3) + " bars)";
      return;
     }
   //--- DecideShift grows with shift, so walk forward until the cache covers us
   int guard = 0;
   while(i0 > 3 && !Decidable(i0) && guard++ < Bars)
      i0--;
   if(!Decidable(i0))
     {
      out = "no closed signal bar inside the cached range - reload more history";
      return;
     }

   double eq = 1.0, bh = 1.0, peak = 1.0, maxdd = 0.0, bpeak = 1.0, bmaxdd = 0.0;
   double entryEq = 1.0, bestT = 0.0, worstT = 0.0, sumT = 0.0;
   bool   haveT = false;                              // else "best" reads +0.0% on an all-losing run
   double s1 = 0.0, s2 = 0.0, b1 = 0.0, b2 = 0.0;
   int    w = 0, wPrev = 0, trades = 0, wins = 0, flips = 0, inPos = 0, bars = 0, costHits = 0;

   for(int i = i0; i >= 0; i--)
     {
      w = StateAt(i);
      bars++;
      if(w != 0)
         inPos++;
      if(w != wPrev)
        {
         flips++;
         if(wPrev != 0)
           {
            double t = eq / entryEq - 1.0;
            trades++;
            sumT += t;
            if(t > 0.0)
               wins++;
            if(!haveT)
              {
               bestT = t;
               worstT = t;
               haveT = true;
              }
            else
              {
               if(t > bestT)
                  bestT = t;
               if(t < worstT)
                  worstT = t;
              }
           }
         entryEq = eq;
        }

      double c1 = Close[i + 1];
      double r  = (c1 > 0.0) ? (Close[i] / c1 - 1.0) : 0.0;
      double k  = MathAbs(w - wPrev) * CostBps / 10000.0;
      if(k > 0.0)
         costHits++;
      double net = w * r - k;
      eq *= (1.0 + net);
      bh *= (1.0 + r);
      s1 += net;
      s2 += net * net;
      b1 += r;
      b2 += r * r;
      if(eq > peak)
         peak = eq;
      if(peak > 0.0 && eq / peak - 1.0 < maxdd)
         maxdd = eq / peak - 1.0;
      if(bh > bpeak)
         bpeak = bh;
      if(bpeak > 0.0 && bh / bpeak - 1.0 < bmaxdd)
         bmaxdd = bh / bpeak - 1.0;
      wPrev = w;
     }

   double secs  = MathMax(1.0, (double)(Time[0] - Time[i0]));
   double years = secs / (365.25 * 86400.0);
   if(years < 0.25 || bars < 30)
     {
      out = "only " + DoubleToString(years, 2) + " years / " + IntegerToString(bars) +
            " bars of usable history - too short to judge anything";
      return;
     }

   double bpsYr  = bars / years;
   double cagr   = (eq > 0.0) ? (MathPow(eq, 1.0 / years) - 1.0) : -1.0;
   double cagrBh = (bh > 0.0) ? (MathPow(bh, 1.0 / years) - 1.0) : -1.0;
   double shr    = AnnSharpe(s1, s2, bars, bpsYr);
   double shrBh  = AnnSharpe(b1, b2, bars, bpsYr);

   out = StringFormat(
      "REPLAY  %s %d/%d  %s %s  |  %.1f yr, %d bars, %.0f bars/yr\n"
      "changes %.2f/yr   round trips %.2f/yr   in-position %.0f%%   trades %d   win %.0f%%   avg %+.2f%%   best %+.1f%%   worst %+.1f%%\n"
      "strategy   CAGR %+.2f%%   Sharpe %.2f   maxDD %.1f%%\n"
      "buy & hold CAGR %+.2f%%   Sharpe %.2f   maxDD %.1f%%   (costs %.1f bps on %d changes)\n%s",
      (MAMethod == MODE_EMA) ? "EMA" : "SMA", FastPeriod, SlowPeriod, Symbol(), TfLabel(Tf()),
      years, bars, bpsYr,
      flips / years, trades / years, 100.0 * inPos / MathMax(1.0, (double)bars), trades,
      (trades > 0) ? 100.0 * wins / trades : 0.0,
      (trades > 0) ? 100.0 * sumT / trades : 0.0, 100.0 * bestT, 100.0 * worstT,
      100.0 * cagr, shr, 100.0 * maxdd,
      100.0 * cagrBh, shrBh, 100.0 * bmaxdd, CostBps, costHits,
      (Bars - 1 - warm > i0) ? "note: replay starts at the oldest bar the cache covers" : "");
  }

//+------------------------------------------------------------------+
//| mean/std of per-bar returns, annualised by measured bars/year   |
//+------------------------------------------------------------------+
double AnnSharpe(double sum, double sumsq, int n, double barsPerYear)
  {
   if(n < 2 || barsPerYear <= 0.0)
      return(0.0);
   double mean = sum / n;
   double var  = sumsq / n - mean * mean;
   if(var <= 1e-18)
      return(0.0);
   return(mean / MathSqrt(var) * MathSqrt(barsPerYear));
  }

//+------------------------------------------------------------------+
//| Shade the flat spells in the visible range: the visible price of |
//| the strategy - the part of the market it declines to hold.      |
//+------------------------------------------------------------------+
void PaintSpells()
  {
   ObjectsDeleteAll(0, "EMAS_F");
   if(!ShadeFlatSpells)
      return;
   double pmin = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   double pmax = ChartGetDouble(0, CHART_PRICE_MAX, 0);
   if(!(pmax > pmin))
      return;

   int from = (int)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR, 0);   // shift of the LEFT-most bar
   if(from > Bars - 3)
      from = Bars - 3;
   if(from < 1)
      return;
   int tfSec = TfSeconds();

   int made     = 0;
   int run      = StateAt(from);
   int startRun = from;
   for(int i = from - 1; i >= 0 && made < MaxShadeRegions; i--)
     {
      int w = StateAt(i);
      if(w != run)
        {
         if(run == 0 && startRun > i + 1 && Decidable(startRun))
           {
            string nm = "EMAS_F" + IntegerToString(made);
            int    a  = MathMin(startRun, Bars - 1);      // open of the oldest flat bar
            int    b  = MathMin(i + 1, Bars - 1);         // newest flat bar (run spans i+1..startRun)
            ObjectCreate(0, nm, OBJ_RECTANGLE, 0, Time[a], pmin, Time[b] + tfSec, pmax);
            ObjectSetInteger(0, nm, OBJPROP_COLOR,      clrGainsboro);
            ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_SOLID);
            ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
            ObjectSetInteger(0, nm, OBJPROP_FILL,       true);
            ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
            made++;
           }
         run      = w;
         startRun = i;
        }
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   if(FastPeriod < 1 || SlowPeriod < 2 || SlowPeriod <= FastPeriod)
     {
      Alert("EMAStudy_Signals: need 0 < FastPeriod < SlowPeriod (got ", FastPeriod, "/", SlowPeriod, ")");
      return(INIT_PARAMETERS_INCORRECT);
     }
   IndicatorDigits(Digits + 1);
   SetIndexBuffer(0, FastE);
   SetIndexBuffer(1, SlowE);
   SetIndexBuffer(2, ArrowUp);
   SetIndexBuffer(3, ArrowDn);
   SetIndexLabel(0, (MAMethod == MODE_EMA ? "EMA " : "SMA ") + IntegerToString(FastPeriod));
   SetIndexLabel(1, (MAMethod == MODE_EMA ? "EMA " : "SMA ") + IntegerToString(SlowPeriod));
   SetIndexLabel(2, "go long");
   SetIndexLabel(3, TradingMode == EMA_LONG_SHORT ? "go short" : "go flat");
   SetIndexEmptyValue(2, EMPTY_VALUE);
   SetIndexEmptyValue(3, EMPTY_VALUE);
   SetIndexArrow(2, 233);
   SetIndexArrow(3, 234);
   IndicatorShortName("EMAStudy " + IntegerToString(FastPeriod) + "/" + IntegerToString(SlowPeriod) +
                      " " + ((TradingMode == EMA_LONG_SHORT) ? "[L/S]" : "[L/flat]") +
                      " " + TfLabel(Tf()));
   gN      = 0;
   gAnchor = 0;
   return(0);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "EMAS_F");
   Comment("");
  }

//+------------------------------------------------------------------+
//| main                                                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[], const int &spread[])
  {
   if(EnsureCache() < SlowPeriod + 3)
     {
      Comment("EMAStudy_Signals: needs more than " + IntegerToString(SlowPeriod + 3) + " bars on " +
              TfLabel(Tf()) + " - load more history, or shrink the periods");
      return(0);
     }

   //--- history can be extending under us (broker downloading, or a bar just opened): in that case
   //--- rates_total and the Bars/Time[]/Close[] series disagree by one, so skip this tick rather
   //--- than write a buffer value onto the wrong bar.
   if(rates_total < 3 || Bars != rates_total)
      return(0);

   int total   = Bars;
   int counted = prev_calculated;
   if(counted < 0)
      return(-1);
   int limit = total - 1;
   if(counted > 0)
      limit = total - counted;
   if(limit > total - 1)
      limit = total - 1;
   if(limit < 0)
      limit = 0;

   bool sameTf  = (Tf() == Period());
   int  warmLim = SlowPeriod + 2;

   for(int i = limit; i >= 0; i--)
     {
      int idx = total - 1 - i;
      int k   = sameTf ? i : MathMax(0, iBarShift(NULL, Tf(), Time[i], false));
      if(k >= gN)
        {
         FastE[idx]   = EMPTY_VALUE;
         SlowE[idx]   = EMPTY_VALUE;
         ArrowUp[idx] = EMPTY_VALUE;
         ArrowDn[idx] = EMPTY_VALUE;
         continue;
        }
      //--- the lines: on the signal's own timeframe they track the forming bar (live),
      //--- which is what people expect to see; the SIGNAL only ever uses closed bars.
      FastE[idx] = sameTf ? iMA(NULL, 0, FastPeriod, 0, MAMethod, AppliedPrice, i) : gF[k];
      SlowE[idx] = sameTf ? iMA(NULL, 0, SlowPeriod, 0, MAMethod, AppliedPrice, i) : gS[k];

      ArrowUp[idx] = EMPTY_VALUE;
      ArrowDn[idx] = EMPTY_VALUE;
      if(DecideShift(i) < warmLim || !Decidable(i) || !Decidable(i + 1))
         continue;

      int w  = StateAt(i);
      int wp = StateAt(i + 1);
      if(w != wp)
        {
         if(w > 0)
            ArrowUp[idx] = Low[i] - 5 * Point;
         else
            ArrowDn[idx] = High[i] + 5 * Point;
        }
     }

   //--- panel, shading and alerts once per new bar, so intrabar the chart stays quiet
   static datetime lastPanel = 0;
   if(Time[0] != lastPanel || counted == 0)
     {
      lastPanel = Time[0];
      if(!IsTesting())
         PaintSpells();

      string replay = "";
      Replay(replay);

      int    w   = StateAt(0);
      string st  = (w > 0) ? "LONG" : ((w < 0) ? "SHORT" : "FLAT");
      int    age = 0;
      while(age < Bars - 2 && StateAt(age) == w)
         age++;
      double months = SlowPeriod * TfSeconds() / 2629800.0;

      string warn = "";
      if(!sameTf)
         warn = "signal read on " + TfLabel(Tf()) + ", drawn on this " + TfLabel(Period()) + " chart\n";
      if(Tf() != PERIOD_D1)
         warn += "!! the study measured 60/132 on DAILY bars. Here the slow EMA spans " +
                 DoubleToString(months, 1) + " months, so its numbers do NOT transfer.\n";

      Comment("EMAStudy_Signals  " + IntegerToString(FastPeriod) + "/" + IntegerToString(SlowPeriod) + "  " +
              ((MAMethod == MODE_EMA) ? "EMA" : "SMA") + "  " + TfLabel(Tf()) + "  ->  " + st +
              "  (this state: " + IntegerToString(age) + " bars)\n" +
              "studied on 82 markets, D1: median Sharpe 0.43, positive in 94% of markets, ~1.5 flips/yr,\n" +
              "diversified book at 10% vol: maxDD -21% vs -63% for buy & hold at matched risk\n" +
              warn + replay);
      ChartRedraw(0);

      if(AlertOnFlip && DecideShift(0) >= warmLim && Decidable(0) && Decidable(1) && w != StateAt(1))
        {
         string msg = Symbol() + " " + TfLabel(Tf()) + " EMAStudy " + IntegerToString(FastPeriod) + "/" +
                      IntegerToString(SlowPeriod) + ": -> " + st;
         if(UseSound)
            PlaySound(SoundFile);
         Alert(msg);
         if(PushNotify)
            SendNotification(msg);
        }
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
