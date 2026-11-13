//+------------------------------------------------------------------+
//|                                              M3K_HL_Sweep.mq4    |
//|                                                                  |
//|  MT4 (MQL4) conversion of the Pine Script v5 indicator           |
//|  "M3K HL Sweep"  (c) MM33KK                                      |
//|                                                                  |
//|  Everything of the original script is converted here:            |
//|    1) Theme inputs (bull / bear / neutral / gold + label size)    |
//|    2) Structure sweep (liquidity sweep of a pivot high / low)     |
//|       3 lines + H / L / SWP labels, only the last sweep is kept   |
//|    3) Supply & Demand zones from W / D / 4H / 1H / 15M through    |
//|       a "lookback" high & low of each timeframe                   |
//|    4) 1 minute RSI divergence (bull / bear)                       |
//|    5) Confluence signal : 2 or more levels touched in one bar     |
//|    6) Alerts                                                      |
//|                                                                  |
//|  MT4 notes                                                        |
//|    * MT4 has no real transparency, so every "color.new(col, x)"    |
//|      is replaced by a colour blended towards the chart background  |
//|      (that is exactly what an x% transparency looks like).         |
//|    * An MT4 rectangle has only one colour (no separate border),    |
//|      therefore every zone is drawn as a slightly bigger "border"   |
//|      rectangle + an inner "fill" rectangle.                        |
//|    * request.security() is replaced by iHighest()/iLowest() on     |
//|      the requested timeframe, and the 1 minute divergence uses     |
//|      iRSI()/iHigh()/iLow() on PERIOD_M1.                           |
//|    * Everything runs on CLOSED bars (non repainting), exactly      |
//|      like the original does with barstate.isconfirmed.             |
//|    * The BUY / SELL arrows are plotted for every past signal so    |
//|      that the chart stays readable; the big "SELL / BUY" label     |
//|      and the "D" label behave like the original (last one only).   |
//+------------------------------------------------------------------+
#property copyright   "MT4 port of the Pine v5 script M3K HL Sweep (c) MM33KK"
#property link        ""
#property version     "1.00"
#property description "Structure sweep + multi timeframe supply/demand zones + 1M divergence confluence"
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1  clrLime
#property indicator_color2  clrRed

//==================================================================//
//  ENUMERATIONS                                                    //
//==================================================================//
enum ENUM_LBLSIZE
  {
   LBL_TINY   = 0,   // Tiny
   LBL_SMALL  = 1,   // Small
   LBL_NORMAL = 2,   // Normal
   LBL_LARGE  = 3    // Large
  };

//==================================================================//
//  INPUTS                                                          //
//==================================================================//
input string       InpHdrTheme   = "----- THEME -----";        // THEME
input color        InpBullColor  = C'8,153,129';               // Bull / demand colour
input color        InpBearColor  = C'242,54,69';               // Bear / supply colour
input color        InpNeutral    = C'178,181,190';             // Neutral colour
input color        InpGoldColor  = C'255,215,0';               // Highlight colour (sweep)
input ENUM_LBLSIZE InpLabelSize  = LBL_TINY;                   // Label size

input string       InpHdrSweep   = "----- STRUCTURE SWEEP -----"; // SWEEP
input int          InpStrength   = 35;                          // Pivot strength
input bool         InpShowSweep  = true;                        // Show sweep
input bool         InpSweepHistory = false;                     // Keep every sweep (off = last only)

input string       InpHdrZones   = "----- SUPPLY / DEMAND ZONES -----"; // ZONES
input int          InpSRLookback = 100;                         // Lookback (bars of each TF)
input double       InpThickness  = 0.15;                        // Zone thickness (%)
input int          InpBoxBars    = 200;                         // Box extension (bars)
input bool         InpShowW      = true;                        // Show weekly (W)
input bool         InpShowD      = true;                        // Show daily (D)
input bool         InpShow4H     = true;                        // Show 4 hours (4H)
input bool         InpShow1H     = true;                        // Show 1 hour (1H)
input bool         InpShowM15    = true;                        // Show 15 minutes (15M)

input string       InpHdrSignal  = "----- SIGNALS -----";       // SIGNALS
input int          InpMinHits    = 2;                           // Minimum levels touched
input bool         InpRequireSweep = false;                     // Signal ONLY with a same direction sweep
input int          InpSweepWindow  = 3;                         // ... sweep must be within N bars
input bool         InpDivergence = true;                        // Show "D" (1M divergence)
input int          InpBackfill   = 300;                         // Backfill signals (bars, 0 = off)

input string       InpHdrMisc    = "----- MISC -----";          // MISC
input int          InpMaxReplay  = 3000;                        // History bars replayed on start
input bool         InpAlerts     = true;                        // Popup alert on signal
input bool         InpAlertSound = true;                        // Sound on signal

//==================================================================//
//  DATA                                                            //
//==================================================================//
struct ZoneState
  {
   double            level;      // last level used to build the box
   datetime          left;       // fixed left edge of the box
   int               side;       // 1 = supply (close below), 0 = demand (close above)
   bool              valid;      // a box already exists
  };

//--- buffers (BUY / SELL arrows)
double BufBuy[];
double BufSell[];

//--- supply / demand zones : 0..9  (pairs : high, low)
ZoneState gZone[10];

//--- sweep state
double    gOriginHigh  = 0.0;
datetime  gOriginHighT = 0;
double    gLowAfterH   = 0.0;
datetime  gLowAfterHT  = 0;
double    gOriginLow   = 0.0;
datetime  gOriginLowT  = 0;
double    gHighAfterL  = 0.0;
datetime  gHighAfterLT = 0;

//--- last sweep drawings
int       gSweepId  = 0;
bool      gSwpValid = false;
bool      gSwpHigh  = true;
datetime  gSwpX1 = 0, gSwpX2 = 0, gSwpX3 = 0;
double    gSwpY1 = 0.0, gSwpY2 = 0.0, gSwpY3 = 0.0;

//--- last sweep (for the "sweep + signal" filter)
datetime  gLastSweepT    = 0;
bool      gLastSweepHigh = true;    // true = a high was swept => bearish

//--- last signal
datetime  gLastSigTime = 0;
int       gLastSigDir  = 0;     // +1 buy, -1 sell
bool      gLastSigDiv  = false;

//--- runtime
bool      gReady       = false;
datetime  gLastBarTime = 0;
int       gLastTotal   = 0;
color     gChartBg     = clrBlack;
double    gThick       = 0.0015;

//==================================================================//
//  SMALL HELPERS                                                   //
//==================================================================//
int LblSize()
  {
   switch(InpLabelSize)
     {
      case LBL_TINY:   return(7);
      case LBL_SMALL:  return(8);
      case LBL_NORMAL: return(10);
      case LBL_LARGE:  return(12);
     }
   return(8);
  }

//--- "colour.new(col, x)" emulation : blend the colour with the background
color Blend(const color a, const color b, const double weightA)
  {
   int ca = (int)a;
   int cb = (int)b;
   double w  = weightA;
   double wb = 1.0 - weightA;
   int r = (int)((ca & 0xFF) * w + (cb & 0xFF) * wb);
   int g = (int)(((ca >> 8) & 0xFF) * w + ((cb >> 8) & 0xFF) * wb);
   int c = (int)(((ca >> 16) & 0xFF) * w + ((cb >> 16) & 0xFF) * wb);
   if(r < 0) r = 0;
   if(r > 255) r = 255;
   if(g < 0) g = 0;
   if(g > 255) g = 255;
   if(c < 0) c = 0;
   if(c > 255) c = 255;
   return((color)(r | (g << 8) | (c << 16)));
  }

//--- length of one chart bar in seconds (MQL4 has no PeriodSeconds())
int TFSeconds()
  {
   int p = Period();
   if(p == PERIOD_M1)  return(60);
   if(p == PERIOD_M5)  return(300);
   if(p == PERIOD_M15) return(900);
   if(p == PERIOD_M30) return(1800);
   if(p == PERIOD_H1)  return(3600);
   if(p == PERIOD_H4)  return(14400);
   if(p == PERIOD_D1)  return(86400);
   if(p == PERIOD_W1)  return(604800);
   if(p == PERIOD_MN1) return(2592000);
   return(p * 60);
  }

//--- little marker shown after the timeframe name
string Glyph(const bool down)
  {
   return(down ? "v" : "^");     // supply / demand
  }

//--- zone meta
int ZoneTF(const int zi)
  {
   switch(zi / 2)
     {
      case 0: return(PERIOD_W1);
      case 1: return(PERIOD_D1);
      case 2: return(PERIOD_H4);
      case 3: return(PERIOD_H1);
      case 4: return(PERIOD_M15);
     }
   return(PERIOD_D1);
  }

string ZoneTFName(const int zi)
  {
   switch(zi / 2)
     {
      case 0: return("W");
      case 1: return("D");
      case 2: return("4H");
      case 3: return("1H");
      case 4: return("15M");
     }
   return("");
  }

bool ZoneIsHigh(const int zi) { return((zi % 2) == 0); }

bool ZoneShown(const int zi)
  {
   switch(zi / 2)
     {
      case 0: return(InpShowW);
      case 1: return(InpShowD);
      case 2: return(InpShow4H);
      case 3: return(InpShow1H);
      case 4: return(InpShowM15);
     }
   return(false);
  }

int ZoneAlign(const int zi)
  {
   switch(zi / 2)
     {
      case 0: return(ANCHOR_RIGHT);    // W  - text.align_right
      case 1: return(ANCHOR_LEFT);     // D  - text.align_left
      case 2: return(ANCHOR_CENTER);   // 4H - text.align_center
      case 3: return(ANCHOR_RIGHT);    // 1H - text.align_right
      case 4: return(ANCHOR_LEFT);     // 15M- text.align_left
     }
   return(ANCHOR_CENTER);
  }

//==================================================================//
//  PIVOTS  (ta.pivothigh(high, strength, strength))                //
//==================================================================//
bool PivotHigh(const int sh, const int len, double &price)
  {
   if(len < 1) return(false);
   int p = sh + len;
   if(p + len >= Bars) return(false);
   double mid = High[p];
   for(int i = p - len; i < p; i++)
     {
      if(i < 0) return(false);
      if(High[i] >= mid) return(false);
     }
   for(int j = p + 1; j <= p + len; j++)
     {
      if(High[j] > mid) return(false);      // right side allows equality
     }
   price = mid;
   return(true);
  }

bool PivotLow(const int sh, const int len, double &price)
  {
   if(len < 1) return(false);
   int p = sh + len;
   if(p + len >= Bars) return(false);
   double mid = Low[p];
   for(int i = p - len; i < p; i++)
     {
      if(i < 0) return(false);
      if(Low[i] <= mid) return(false);
     }
   for(int j = p + 1; j <= p + len; j++)
     {
      if(Low[j] < mid) return(false);       // right side allows equality
     }
   price = mid;
   return(true);
  }

//==================================================================//
//  OBJECT HELPERS                                                  //
//==================================================================//
void ObjRect(const string name, const datetime t1, const double p1,
             const datetime t2, const double p2, const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

void ObjText(const string name, const datetime t, const double p, const string txt,
             const color clr, const int fsize, const ENUM_ANCHOR_POINT anchor)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   else
      ObjectMove(0, name, 0, t, p);

   ObjectSetString(0, name, OBJPROP_TEXT, txt);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fsize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void ObjTrend(const string name, const datetime t1, const double p1,
              const datetime t2, const double p2, const color clr,
              const int style, const int width)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, (ENUM_LINE_STYLE)style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//==================================================================//
//  MULTI TIMEFRAME LEVELS                                          //
//  request.security(sym, tf, ta.highest(high, N)[1])               //
//==================================================================//
double ZoneLevelAt(const int zi, const datetime tClose)
  {
   int tf = ZoneTF(zi);
   int forming = iBarShift(NULL, tf, tClose, false);
   if(forming < 0) return(0.0);
   int start = forming + 1;                 // the "[1]" of the original
   int nb = iBars(NULL, tf);
   if(nb <= start) return(0.0);

   int cnt = InpSRLookback;
   if(start + cnt > nb) cnt = nb - start;   // not enough history yet
   if(cnt < 1) return(0.0);

   if(ZoneIsHigh(zi))
     {
      int sh = iHighest(NULL, tf, MODE_HIGH, cnt, start);
      if(sh < 0) return(0.0);
      return(iHigh(NULL, tf, sh));
     }

   int sl = iLowest(NULL, tf, MODE_LOW, cnt, start);
   if(sl < 0) return(0.0);
   return(iLow(NULL, tf, sl));
  }

//==================================================================//
//  1 MINUTE DIVERGENCE                                             //
//  r = ta.rsi(close,14)  +  [bear[1], bull[1]]                     //
//==================================================================//
void Divergence(const datetime tClose, bool &outBear, bool &outBull)
  {
   outBear = false;
   outBull = false;

   int totalM1 = iBars(NULL, PERIOD_M1);
   if(totalM1 < 60) return;

   int mLast = iBarShift(NULL, PERIOD_M1, tClose, false) + 1;   // last closed M1 bar
   int k     = mLast + 1;                                       // original "[1]"
   if(k < 0 || k + 11 >= totalM1) return;

   double hk  = iHigh(NULL, PERIOD_M1, k);
   double hk1 = iHigh(NULL, PERIOD_M1, k + 1);
   double lk  = iLow(NULL,  PERIOD_M1, k);
   double lk1 = iLow(NULL,  PERIOD_M1, k + 1);
   double rk  = iRSI(NULL,  PERIOD_M1, 14, PRICE_CLOSE, k);
   double rk1 = iRSI(NULL,  PERIOD_M1, 14, PRICE_CLOSE, k + 1);
   if(hk <= 0.0 || lk <= 0.0 || rk <= 0.0) return;

   double hMax = 0.0, rMax = 0.0, lMin = 0.0, rMin = 0.0;
   for(int j = 1; j <= 10; j++)
     {
      double hh = iHigh(NULL, PERIOD_M1, k + j);
      double ll = iLow(NULL,  PERIOD_M1, k + j);
      double rr = iRSI(NULL,  PERIOD_M1, 14, PRICE_CLOSE, k + j);
      if(rr <= 0.0) continue;
      if(j == 1 || hh > hMax) hMax = hh;
      if(j == 1 || rr > rMax) rMax = rr;
      if(j == 1 || ll < lMin) lMin = ll;
      if(j == 1 || rr < rMin) rMin = rr;
     }
   if(hMax <= 0.0 || lMin <= 0.0) return;

   outBear = ((hk > hk1 && rk < rk1) || (hk > hMax && rk < rMax));
   outBull = ((lk < lk1 && rk > rk1) || (lk < lMin && rk > rMin));
  }

//==================================================================//
//  STRUCTURE SWEEP                                                 //
//==================================================================//
void NewSweep(const bool high, const datetime tBar, const double hi, const double lo)
  {
   gSweepId++;
   gLastSweepT    = tBar;
   gLastSweepHigh = high;
   gSwpValid = true;
   gSwpHigh  = high;
   gSwpX3    = tBar;

   if(high)
     {
      gSwpX1 = gOriginHighT;
      gSwpY1 = gOriginHigh;
      gSwpX2 = gLowAfterHT;
      gSwpY2 = gLowAfterH;
      gSwpY3 = hi;
      gOriginHigh = 0.0;
     }
   else
     {
      gSwpX1 = gOriginLowT;
      gSwpY1 = gOriginLow;
      gSwpX2 = gHighAfterLT;
      gSwpY2 = gHighAfterL;
      gSwpY3 = lo;
      gOriginLow = 0.0;
     }

   //--- "clear_sweep_drawings()" : only the last sweep survives
   if(!InpSweepHistory)
      ObjectsDeleteAll(0, "M3K_SWP_LAST_");

   DrawSweep();
  }

void ProcessSweep(const int sh)
  {
   double ph = 0.0, pl = 0.0;
   bool hasPH = PivotHigh(sh, InpStrength, ph);
   bool hasPL = PivotLow(sh, InpStrength, pl);
   datetime pvT = 0;
   if(sh + InpStrength < Bars) pvT = Time[sh + InpStrength];

   //--- origin high
   if(hasPH)
     {
      gOriginHigh  = ph;
      gOriginHighT = pvT;
      gLowAfterH   = 0.0;
      gLowAfterHT  = 0;
     }
   if(hasPL && gOriginHigh > 0.0)
     {
      if(pl < gOriginHigh)
        {
         gLowAfterH  = pl;
         gLowAfterHT = pvT;
        }
     }
   if(gLowAfterH > 0.0 && gOriginHigh > 0.0 &&
      High[sh] > gOriginHigh && Close[sh] < gOriginHigh)
      NewSweep(true, Time[sh], High[sh], Low[sh]);

   //--- origin low
   if(hasPL)
     {
      gOriginLow  = pl;
      gOriginLowT = pvT;
      gHighAfterL = 0.0;
      gHighAfterLT = 0;
     }
   if(hasPH && gOriginLow > 0.0)
     {
      if(ph > gOriginLow)
        {
         gHighAfterL  = ph;
         gHighAfterLT = pvT;
        }
     }
   if(gHighAfterL > 0.0 && gOriginLow > 0.0 &&
      Low[sh] < gOriginLow && Close[sh] > gOriginLow)
      NewSweep(false, Time[sh], High[sh], Low[sh]);
  }

void DrawSweep()
  {
   if(!InpShowSweep) return;
   if(!gSwpValid) return;

   string pfx = "M3K_SWP_LAST_";
   if(InpSweepHistory)
      pfx = "M3K_SWP_" + IntegerToString(gSweepId) + "_";

   color lineCol = gSwpHigh ? Blend(InpNeutral, gChartBg, 0.80)
                            : Blend(InpGoldColor, gChartBg, 0.80);
   color dashCol = gSwpHigh ? Blend(InpBearColor, gChartBg, 0.60)
                            : Blend(InpBullColor, gChartBg, 0.60);
   color txtCol  = gSwpHigh ? InpBearColor : InpBullColor;

   ObjTrend(pfx + "L1", gSwpX1, gSwpY1, gSwpX2, gSwpY2, lineCol, STYLE_DOT, 2);
   ObjTrend(pfx + "L2", gSwpX2, gSwpY2, gSwpX3, gSwpY3, lineCol, STYLE_DOT, 2);
   ObjTrend(pfx + "LS", gSwpX1, gSwpY1, gSwpX3, gSwpY1, dashCol, STYLE_DASH, 1);

   int fs = LblSize();
   if(gSwpHigh)
     {
      ObjText(pfx + "T1", gSwpX1, gSwpY1, "H", InpNeutral, fs + 1, ANCHOR_LOWER);
      ObjText(pfx + "T2", gSwpX2, gSwpY2, "L", InpNeutral, fs + 1, ANCHOR_UPPER);
     }
   else
     {
      ObjText(pfx + "T1", gSwpX1, gSwpY1, "L", InpNeutral, fs + 1, ANCHOR_UPPER);
      ObjText(pfx + "T2", gSwpX2, gSwpY2, "H", InpNeutral, fs + 1, ANCHOR_LOWER);
     }

   datetime mid = (datetime)(gSwpX1 + (long)((gSwpX3 - gSwpX1) / 2));
   ObjText(pfx + "T3", mid, gSwpY1, "SWP", txtCol, fs,
           gSwpHigh ? ANCHOR_LOWER : ANCHOR_UPPER);
  }

//==================================================================//
//  SUPPLY / DEMAND ZONES                                           //
//==================================================================//
void ZoneObjects(const int zi)
  {
   string pfx = "M3K_ZN_" + IntegerToString(zi) + "_";

   if(!ZoneShown(zi) || !gZone[zi].valid)
     {
      ObjectsDeleteAll(0, pfx);
      return;
     }

   double lvl = gZone[zi].level;
   double th  = gThick;
   bool   sup = (gZone[zi].side == 1);

   double top = sup ? lvl : lvl * (1.0 + th);
   double btm = sup ? lvl * (1.0 - th) : lvl;

   color baseCol = sup ? InpBearColor : InpBullColor;
   color fillCol = Blend(baseCol, gChartBg, 0.12);   // color.new(col, 88)
   color brdCol  = Blend(baseCol, gChartBg, 0.55);   // color.new(col, 45)

   double pad = (top - btm) * 0.08;
   if(pad <= 0.0) pad = 5.0 * Point;

   datetime right = Time[0];
   datetime left  = gZone[zi].left;

   //--- MT4 has a single colour per rectangle : border rectangle + fill rectangle
   ObjRect(pfx + "BRD", left, top + pad, right, btm - pad, brdCol);
   ObjRect(pfx + "BOX", left, top, right, btm, fillCol);

   string txt = "  " + ZoneTFName(zi) + " " + Glyph(sup);
   ObjText(pfx + "TXT", left, (top + btm) / 2.0, txt, baseCol, LblSize(),
           (ENUM_ANCHOR_POINT)ZoneAlign(zi));
  }

void UpdateZones()
  {
   datetime tClose = Time[0];
   for(int zi = 0; zi < 10; zi++)
     {
      if(!ZoneShown(zi))
        {
         gZone[zi].valid = false;
         ZoneObjects(zi);
         continue;
        }

      double lvl = ZoneLevelAt(zi, tClose);
      if(lvl <= 0.0)
        {
         ZoneObjects(zi);
         continue;
        }

      if(!gZone[zi].valid || lvl != gZone[zi].level)
        {
         //--- manage_zone() : rebuild the box when the level changes
         gZone[zi].level = lvl;
         gZone[zi].side  = (Close[0] < lvl) ? 1 : 0;
         gZone[zi].left  = (datetime)(Time[0] - (long)TFSeconds() * (long)InpBoxBars);
         gZone[zi].valid = true;
        }
      ZoneObjects(zi);
     }
  }

//==================================================================//
//  CONFLUENCE SIGNAL                                               //
//==================================================================//
void CountHits(const datetime tClose, const double hi, const double lo,
               int &sHits, int &dHits)
  {
   sHits = 0;
   dHits = 0;

   for(int zi = 0; zi < 10; zi++)
     {
      if(!ZoneShown(zi)) continue;
      double lvl = ZoneLevelAt(zi, tClose);
      if(lvl <= 0.0) continue;

      if(ZoneIsHigh(zi))
        {
         //--- check_touch(val, true)
         double b = lvl * (1.0 - gThick);
         if(hi >= b && lo <= lvl) sHits++;
        }
      else
        {
         //--- check_touch(val, false)
         double t = lvl * (1.0 + gThick);
         if(hi >= lvl && lo <= t) dHits++;
        }
     }
  }

//--- returns +1 buy, -1 sell, 0 nothing
int EvaluateSignal(const int sh)
  {
   datetime tClose = (datetime)(Time[sh] + TFSeconds());
   int sHits = 0, dHits = 0;
   CountHits(tClose, High[sh], Low[sh], sHits, dHits);

   if(sHits < InpMinHits && dHits < InpMinHits) return(0);

   bool isSell = (sHits >= InpMinHits);

   //--- "signal + sweep in the same direction" filter
   if(InpRequireSweep)
     {
      if(gLastSweepT <= 0) return(0);
      int sw3 = iBarShift(NULL, 0, gLastSweepT, false);
      if(sw3 < 0) return(0);
      int dist = sw3 - sh;                    // bars since the sweep (0 = same bar)
      if(dist < 0 || dist > InpSweepWindow) return(0);
      if(isSell && !gLastSweepHigh) return(0);   // SELL needs a swept high
      if(!isSell && gLastSweepHigh) return(0);   // BUY  needs a swept low
     }

   bool divBear = false, divBull = false;
   if(InpDivergence) Divergence(tClose, divBear, divBull);

   bool divOk = (isSell && divBear) || (!isSell && divBull);
   int  dir   = isSell ? -1 : 1;
   int  k     = Bars - 1 - sh;

   //--- arrow
   double off = (High[sh] - Low[sh]) * 0.5;
   if(off <= 0.0) off = 10.0 * Point;
   if(k >= 0 && k < Bars)
     {
      if(isSell) BufSell[k] = High[sh] + off;
      else       BufBuy[k]  = Low[sh]  - off;
     }

   gLastSigTime = Time[sh];
   gLastSigDir  = dir;
   gLastSigDiv  = divOk;

   return(dir);
  }

//--- big SELL / BUY label + "D" of the last signal (the original deletes the old ones)
void DrawLastSignal()
  {
   ObjectsDeleteAll(0, "M3K_SIG");
   ObjectsDeleteAll(0, "M3K_DIV");
   if(gLastSigTime <= 0) return;

   int sh = iBarShift(NULL, 0, gLastSigTime, false);
   if(sh < 0 || sh >= Bars) return;

   bool sell = (gLastSigDir < 0);
   color col = sell ? InpBearColor : InpBullColor;
   double y  = sell ? High[sh] : Low[sh];

   ObjText("M3K_SIG", gLastSigTime, y, sell ? "SELL" : "BUY", col, LblSize() + 1,
           sell ? ANCHOR_LOWER : ANCHOR_UPPER);

   if(gLastSigDiv)
      ObjText("M3K_DIV", gLastSigTime, y, "D", col, LblSize() + 1,
              sell ? ANCHOR_LOWER : ANCHOR_UPPER);
  }

//==================================================================//
//  HISTORY REBUILD                                                 //
//==================================================================//
void ResetState()
  {
   gOriginHigh = 0.0;  gOriginHighT = 0;
   gLowAfterH  = 0.0;  gLowAfterHT  = 0;
   gOriginLow  = 0.0;  gOriginLowT  = 0;
   gHighAfterL = 0.0;  gHighAfterLT = 0;

   gSweepId = 0;
   gSwpValid = false;
   gSwpX1 = 0; gSwpX2 = 0; gSwpX3 = 0;
   gSwpY1 = 0.0; gSwpY2 = 0.0; gSwpY3 = 0.0;

   gLastSweepT    = 0;
   gLastSweepHigh = true;

   gLastSigTime = 0;
   gLastSigDir  = 0;
   gLastSigDiv  = false;

   for(int zi = 0; zi < 10; zi++)
     {
      gZone[zi].level = 0.0;
      gZone[zi].left  = 0;
      gZone[zi].side  = 0;
      gZone[zi].valid = false;
     }

   ObjectsDeleteAll(0, "M3K_SWP_");
   ObjectsDeleteAll(0, "M3K_SIG");
   ObjectsDeleteAll(0, "M3K_DIV");
   ObjectsDeleteAll(0, "M3K_ZN_");
  }

void Rebuild(const int rates_total)
  {
   ResetState();

   //--- 1) sweep engine over the history
   int need = 2 * InpStrength + 2;
   int startSh = Bars - 1 - need;
   if(startSh > InpMaxReplay) startSh = InpMaxReplay;
   if(startSh > Bars - 2) startSh = Bars - 2;
   if(startSh < 1) startSh = 1;
   for(int sh = startSh; sh >= 1; sh--) ProcessSweep(sh);

   //--- 2) signal backfill (arrows only)
   if(InpBackfill > 0)
     {
      int maxBars = InpBackfill;
      if(maxBars > Bars - 2) maxBars = Bars - 2;
      for(int s2 = maxBars; s2 >= 1; s2--) EvaluateSignal(s2);
     }
   DrawLastSignal();
  }

//==================================================================//
//  INIT / DEINIT / CALCULATE                                       //
//==================================================================//
int OnInit()
  {
   SetIndexBuffer(0, BufBuy);
   SetIndexBuffer(1, BufSell);

   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 2, InpBullColor);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 2, InpBearColor);
   SetIndexArrow(0, 233);
   SetIndexArrow(1, 234);

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexLabel(0, "BUY confluence");
   SetIndexLabel(1, "SELL confluence");

   IndicatorShortName("M3K HL Sweep");
   IndicatorDigits(Digits);

   gChartBg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   gThick   = InpThickness / 100.0;
   if(gThick <= 0.0) gThick = 0.0001;

   ObjectsDeleteAll(0, "M3K_");
   ChartRedraw(0);

   gReady       = false;
   gLastBarTime = 0;
   gLastTotal   = 0;
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "M3K_");
   ChartRedraw(0);
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
   if(rates_total < 120) return(0);

   //--- buffers must start empty, otherwise bar 0 draws an arrow at price 0
   if(prev_calculated == 0)
     {
      for(int k = 0; k < rates_total; k++)
        {
         BufBuy[k]  = EMPTY_VALUE;
         BufSell[k] = EMPTY_VALUE;
        }
      gReady = false;          // buffers were wiped : rebuild everything
     }
   BufBuy[rates_total - 1]  = EMPTY_VALUE;
   BufSell[rates_total - 1] = EMPTY_VALUE;

   bool newBar = (gLastBarTime != Time[0]);
   bool bigLoad = (gReady && rates_total > gLastTotal + 200);
   gLastTotal = rates_total;

   //--- first run or a big chunk of history was loaded
   if(!gReady || bigLoad)
     {
      Rebuild(rates_total);
      UpdateZones();
      gReady       = true;
      gLastBarTime = Time[0];
      ChartRedraw(0);
      return(rates_total);
     }

   //--- one closed bar
   if(newBar)
     {
      gLastBarTime = Time[0];

      ProcessSweep(1);
      UpdateZones();

      int dir = EvaluateSignal(1);
      if(dir != 0)
        {
         DrawLastSignal();
        }
      if(dir != 0 && InpAlerts)
        {
         string side = (dir > 0) ? "BUY" : "SELL";
         Alert(Symbol() + " " + IntegerToString((int)Period()) + " : " + side +
               " confluence - price " + DoubleToString(Close[1], Digits));
         if(InpAlertSound) PlaySound("alert.wav");
        }

      ChartRedraw(0);
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
