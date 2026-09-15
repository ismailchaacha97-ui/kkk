//+------------------------------------------------------------------+
//|                                            SDZ_ThreeEntries.mq4  |
//|  v1.1 - Supply & Demand zones + three entry styles:              |
//|    [1] PENDING LIMIT   - limit tagged at zone proximal line      |
//|    [2] CONFIRMATION    - engulfing candle inside the zone        |
//|    [3] PULLBACK STRUCT - tap -> swing -> counter-swing -> break  |
//|                                                                  |
//|  v1.1 additions (trade what I would trade):                      |
//|    * HTF trend filter (EMA fast/slow bias) - signals only with   |
//|      the higher-timeframe trend                                  |
//|    * zone quality score Q0..Q4 (impulse strength, BOS, liquidity |
//|      sweep, tight base) - signals only at/above minimum score    |
//|    * optional session filter (two windows, server time)          |
//|    * RR trade planner: draws Entry / SL / TP at InpRR (1.50)     |
//|    * room check: skips plans whose TP lands inside the next      |
//|      opposite zone (tagged NR)                                   |
//|    * alerts carry exact entry/SL/TP prices                       |
//|                                                                  |
//|  Zone model: impulse candle (body >= mult*ATR, optional BOS)     |
//|  defines a zone from its base. States: fresh -> tapped ->        |
//|  broken (close beyond far edge).                                 |
//|                                                                  |
//|  All detection runs on CLOSED candles only -> no repainting.     |
//+------------------------------------------------------------------+
#property copyright "Arena.ai"
#property version   "1.10"
#property strict
#property indicator_chart_window

#define PREFIX "SDZ_"

//--- zone detection --------------------------------------------------
input int    InpATRPeriod      = 14;          // ATR period (impulse measure)
input double InpImpulseMult    = 1.0;         // impulse body >= x * ATR
input bool   InpRequireBOS     = true;        // impulse must break prior structure
input int    InpBOSLookback    = 10;          // structure lookback (bars)
input int    InpMaxBaseCandles = 3;           // max candles searched for zone base
input bool   InpSkipOverlap    = true;        // ignore zones overlapping active ones
input int    InpHistoryBars    = 1500;        // bars scanned
input int    InpMaxZones       = 30;          // max zones kept in memory

//--- quality / context filters ---------------------------------------
input int    InpMinScore       = 2;           // min zone quality Q0..Q4 for signals
input bool   InpUseHTF         = true;        // HTF trend filter
input ENUM_TIMEFRAMES InpHTF   = PERIOD_H1;   // higher timeframe
input int    InpHTFFast        = 50;          // HTF fast EMA
input int    InpHTFSlow        = 200;         // HTF slow EMA
input bool   InpUseSessions    = false;       // trade only inside session windows
input int    InpS1Start        = 7;           // window 1 start hour (server time)
input int    InpS1End          = 10;          // window 1 end hour
input int    InpS2Start        = 12;          // window 2 start hour (server time)
input int    InpS2End          = 15;          // window 2 end hour

//--- entry styles ----------------------------------------------------
input bool   InpEntryLimit     = true;        // entry 1: pending limit marks
input bool   InpEntryConfirm   = true;        // entry 2: engulfing confirmation
input bool   InpEntryStruct    = true;        // entry 3: pullback structure
input int    InpFractalN       = 2;           // fractal side bars (structure entry)

//--- trade planner ---------------------------------------------------
input bool   InpDrawPlan       = true;        // draw Entry/SL/TP lines on signals
input double InpRR             = 1.50;        // reward : risk
input double InpSLBufferPips   = 3;           // stop buffer beyond zone (pips)
input bool   InpRoomCheck      = true;        // skip plans with no room to TP
input int    InpPlanBars       = 40;          // plan line length (bars)

//--- visuals & alerts ------------------------------------------------
input int    InpFutureBars     = 20;          // zone extension right (bars)
input bool   InpShowBroken     = false;       // keep broken zones on chart (grey)
input double InpArrowPips      = 3;           // arrow offset (pips)
input color  InpDemandFill     = C'224,242,224';
input color  InpDemandEdge     = clrSeaGreen;
input color  InpSupplyFill     = C'247,226,226';
input color  InpSupplyEdge     = clrFireBrick;
input bool   InpAlertPopup     = true;        // popup alert on new signal
input bool   InpAlertPush      = false;       // push notification on new signal

//--- data ------------------------------------------------------------
struct ZoneRec
  {
   int               dir;        // +1 demand, -1 supply
   datetime          t0;         // formation time
   double            top;
   double            bot;
   int               state;      // 0 fresh, 1 tapped, 2 broken
   int               phase;      // structure-entry state machine (0..4, 9 dead)
   datetime          tapT;
   datetime          sw1T;
   double            sw1;
   double            sw2;
   bool              confDone;
   bool              strDone;
   int               score;      // quality Q0..Q4
  };

struct SigRec
  {
   datetime          t;
   int               dir;        // +1 buy, -1 sell
   int               kind;       // 1 limit, 2 confirm, 3 structure
   double            entry;
   double            sl;
   double            tp;
   bool              room;       // passed the room check
  };

ZoneRec  g_zones[];
SigRec   g_sigs[];
string   g_zoneNames[];
datetime g_lastBar    = 0;
string   g_alertedKey = "";
int      g_bias       = 0;       // +1 bull, -1 bear (HTF)

//+------------------------------------------------------------------+
int OnInit()
  {
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PREFIX);
  }
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
   if(rates_total < 100)
      return(0);

   if(prev_calculated == 0 || Time[0] != g_lastBar)
     {
      //--- a new closed bar (or reload): full re-scan, no repainting
      ObjectsDeleteAll(0, PREFIX);
      ArrayResize(g_zoneNames, 0);
      ScanHistory(rates_total);
      DrawAll();
      CheckAlerts();
      g_lastBar = Time[0];
     }
   else
     {
      StretchZones();
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
//| Full historical scan, old -> new                                  |
//+------------------------------------------------------------------+
void ScanHistory(int total)
  {
   ArrayResize(g_zones, 0);
   ArrayResize(g_sigs, 0);

   g_bias = 0;
   if(InpUseHTF)
     {
      double f = iMA(NULL, InpHTF, InpHTFFast, 0, MODE_EMA, PRICE_CLOSE, 0);
      double s = iMA(NULL, InpHTF, InpHTFSlow, 0, MODE_EMA, PRICE_CLOSE, 0);
      g_bias = (f > s) ? 1 : -1;
     }

   int start = total - 3 - InpBOSLookback;
   if(start > InpHistoryBars)
      start = InpHistoryBars;
   if(start < 1)
      start = 1;

   for(int i = start; i >= 1; i--)
     {
      int zn = ArraySize(g_zones);
      for(int z = 0; z < zn; z++)
         UpdateZone(z, i, total);
      TryFormZone(i, total);
     }
  }
//+------------------------------------------------------------------+
//| Context gates for any signal                                      |
//+------------------------------------------------------------------+
bool SignalAllowed(int dir, datetime t, int score)
  {
   if(score < InpMinScore)
      return(false);
   if(InpUseHTF && g_bias != 0 && dir != g_bias)
      return(false);
   if(InpUseSessions && !InSession(t))
      return(false);
   return(true);
  }
//+------------------------------------------------------------------+
bool InSession(datetime t)
  {
   int h = TimeHour(t);
   if(h >= InpS1Start && h < InpS1End)
      return(true);
   if(h >= InpS2Start && h < InpS2End)
      return(true);
   return(false);
  }
//+------------------------------------------------------------------+
//| Liquidity sweep just before the impulse                           |
//+------------------------------------------------------------------+
bool SweptLiquidity(int i, int dir, int total)
  {
   for(int j = i - 1; j >= i - 5 && j >= 1; j--)
     {
      if(j + 10 >= total)
         continue;
      if(dir == 1)
        {
         double prior = DBL_MAX;
         for(int k = j + 1; k <= j + 10; k++)
            prior = MathMin(prior, Low[k]);
         if(Low[j] < prior && Close[j] > prior)
            return(true);             // wick took the lows, close reclaimed
        }
      else
        {
         double prior = -DBL_MAX;
         for(int k = j + 1; k <= j + 10; k++)
            prior = MathMax(prior, High[k]);
         if(High[j] > prior && Close[j] < prior)
            return(true);             // wick took the highs, close rejected
        }
     }
   return(false);
  }
//+------------------------------------------------------------------+
//| Zone birth: impulse candle + base + quality score                 |
//+------------------------------------------------------------------+
void TryFormZone(int i, int total)
  {
   if(i < 2)
      return;                          // never use the forming bar as base
   double atr = iATR(NULL, 0, InpATRPeriod, i);
   if(atr <= 0.0)
      return;
   double body = MathAbs(Close[i] - Open[i]);
   if(body < InpImpulseMult * atr)
      return;                          // not an impulse
   int dir = (Close[i] > Open[i]) ? 1 : -1;

   //--- structure break (scored always, gating optional)
   bool bos = false;
     {
      double hh = -DBL_MAX, ll = DBL_MAX;
      for(int k = 1; k <= InpBOSLookback; k++)
        {
         if(i + k >= total)
            break;
         hh = MathMax(hh, High[i + k]);
         ll = MathMin(ll, Low[i + k]);
        }
      bos = (dir == 1) ? (Close[i] > hh) : (Close[i] < ll);
     }
   if(InpRequireBOS && !bos)
      return;

   //--- base: last opposite-colour candle within the lookback
   int base = -1;
   for(int k = 1; k <= InpMaxBaseCandles; k++)
     {
      int j = i - k;
      if(j < 1)
         break;
      if(dir ==  1 && Close[j] < Open[j]) { base = j; break; }
      if(dir == -1 && Close[j] > Open[j]) { base = j; break; }
     }
   if(base < 0)
      base = i - 1;

   double zt = -DBL_MAX, zb = DBL_MAX;
   for(int j = base; j <= i - 1; j++)
     {
      zt = MathMax(zt, High[j]);
      zb = MathMin(zb, Low[j]);
     }

   //--- skip if stacked on an active zone of the same side
   if(InpSkipOverlap)
      for(int z = 0; z < ArraySize(g_zones); z++)
         if(g_zones[z].dir == dir && g_zones[z].state < 2 &&
            zt >= g_zones[z].bot && zb <= g_zones[z].top)
            return;

   //--- quality score Q0..Q4
   int score = 0;
   if(body >= 1.5 * atr)
      score++;
   if(bos)
      score++;
   if(SweptLiquidity(i, dir, total))
      score++;
   if(MathAbs(Close[base] - Open[base]) <= 0.5 * atr)
      score++;

   if(ArraySize(g_zones) >= InpMaxZones)
      RemoveOldestZone();

   int n = ArraySize(g_zones);
   ArrayResize(g_zones, n + 1);
   g_zones[n].dir      = dir;
   g_zones[n].t0       = Time[i];
   g_zones[n].top      = zt;
   g_zones[n].bot      = zb;
   g_zones[n].state    = 0;
   g_zones[n].phase    = 0;
   g_zones[n].tapT     = 0;
   g_zones[n].sw1T     = 0;
   g_zones[n].sw1      = 0.0;
   g_zones[n].sw2      = 0.0;
   g_zones[n].confDone = false;
   g_zones[n].strDone  = false;
   g_zones[n].score    = score;

   //--- entry style 1: pending limit sits at the proximal line
   if(InpEntryLimit && SignalAllowed(dir, Time[i], score))
      MakeSig(i, dir, 1, (dir == 1) ? zt : zb, zt, zb);
  }
//+------------------------------------------------------------------+
//| Let one zone react to one closed bar                              |
//+------------------------------------------------------------------+
void UpdateZone(int zi, int i, int total)
  {
   ZoneRec z = g_zones[zi];
   if(z.state == 2)
      return;                          // broken zones are frozen

   //--- tap / invalidation
   if(z.dir == 1)
     {
      if(Close[i] < z.bot)
        {
         z.state = 2;
         z.phase = 9;
         g_zones[zi] = z;
         return;
        }
      if(Low[i] <= z.top)
        {
         if(z.state == 0)
            z.state = 1;
         if(z.phase == 0)
           {
            z.phase = 1;
            z.tapT  = Time[i];
           }
        }
     }
   else
     {
      if(Close[i] > z.top)
        {
         z.state = 2;
         z.phase = 9;
         g_zones[zi] = z;
         return;
        }
      if(High[i] >= z.bot)
        {
         if(z.state == 0)
            z.state = 1;
         if(z.phase == 0)
           {
            z.phase = 1;
            z.tapT  = Time[i];
           }
        }
     }

   //--- entry style 2: engulfing confirmation inside the zone
   if(InpEntryConfirm && !z.confDone && i + 1 < total)
     {
      bool touch = (z.dir == 1) ? (Low[i] <= z.top) : (High[i] >= z.bot);
      if(touch)
        {
         bool bull  = Close[i] > Open[i];
         bool bear  = Close[i] < Open[i];
         bool bullP = Close[i+1] > Open[i+1];
         bool bearP = Close[i+1] < Open[i+1];
         if(z.dir ==  1 && bull && bearP && Open[i] <= Close[i+1] && Close[i] >= Open[i+1])
           {
            z.confDone = true;
            if(SignalAllowed(1, Time[i], z.score))
               MakeSig(i, 1, 2, Close[i], z.top, z.bot);
           }
         if(z.dir == -1 && bear && bullP && Open[i] >= Close[i+1] && Close[i] <= Open[i+1])
           {
            z.confDone = true;
            if(SignalAllowed(-1, Time[i], z.score))
               MakeSig(i, -1, 2, Close[i], z.top, z.bot);
           }
        }
     }

   //--- entry style 3: tap -> swing -> counter-swing -> break
   if(InpEntryStruct && !z.strDone && z.phase >= 1 && z.phase <= 3)
     {
      int j = i - InpFractalN;         // fractal at j is confirmed by bar i
      if(j >= InpFractalN && j + InpFractalN < total)
        {
         if(z.phase == 1 && Time[j] >= z.tapT)
           {
            if(z.dir ==  1 && IsFractalLow(j, InpFractalN))
              {
               z.sw1 = Low[j]; z.sw1T = Time[j]; z.phase = 2;
              }
            if(z.dir == -1 && IsFractalHigh(j, InpFractalN))
              {
               z.sw1 = High[j]; z.sw1T = Time[j]; z.phase = 2;
              }
           }
         else if(z.phase == 2 && Time[j] > z.sw1T)
           {
            if(z.dir ==  1 && IsFractalHigh(j, InpFractalN))
              {
               z.sw2 = High[j]; z.phase = 3;
              }
            if(z.dir == -1 && IsFractalLow(j, InpFractalN))
              {
               z.sw2 = Low[j]; z.phase = 3;
              }
           }
        }
      if(z.phase == 3)
        {
         if(z.dir ==  1 && Close[i] > z.sw2)
           {
            z.strDone = true; z.phase = 4;
            if(SignalAllowed(1, Time[i], z.score))
               MakeSig(i, 1, 3, Close[i], z.top, z.bot);
           }
         if(z.dir == -1 && Close[i] < z.sw2)
           {
            z.strDone = true; z.phase = 4;
            if(SignalAllowed(-1, Time[i], z.score))
               MakeSig(i, -1, 3, Close[i], z.top, z.bot);
           }
        }
     }

   g_zones[zi] = z;
  }
//+------------------------------------------------------------------+
//| Build a signal + its 1.50-style plan (entry/SL/TP, room check)    |
//+------------------------------------------------------------------+
void MakeSig(int i, int dir, int kind, double entry, double ztop, double zbot)
  {
   double buffer = InpSLBufferPips * 10 * _Point;
   double sl = (dir == 1) ? zbot - buffer : ztop + buffer;
   double R  = MathAbs(entry - sl);
   if(R <= 0.0)
      return;
   double tp = (dir == 1) ? entry + R * InpRR : entry - R * InpRR;

   bool room = true;
   if(InpRoomCheck)
     {
      double need = R * InpRR;
      double best = DBL_MAX;
      for(int z = 0; z < ArraySize(g_zones); z++)
        {
         if(g_zones[z].state == 2)
            continue;
         if(dir == 1 && g_zones[z].dir == -1 && g_zones[z].bot > entry)
            best = MathMin(best, g_zones[z].bot - entry);   // supply proximal above
         if(dir == -1 && g_zones[z].dir == 1 && g_zones[z].top < entry)
            best = MathMin(best, entry - g_zones[z].top);   // demand proximal below
        }
      if(best < need)
         room = false;
     }

   int n = ArraySize(g_sigs);
   ArrayResize(g_sigs, n + 1);
   g_sigs[n].t     = Time[i];
   g_sigs[n].dir   = dir;
   g_sigs[n].kind  = kind;
   g_sigs[n].entry = entry;
   g_sigs[n].sl    = sl;
   g_sigs[n].tp    = tp;
   g_sigs[n].room  = room;
  }
//+------------------------------------------------------------------+
bool IsFractalLow(int j, int n)
  {
   for(int k = 1; k <= n; k++)
      if(Low[j] >= Low[j - k] || Low[j] >= Low[j + k])
         return(false);
   return(true);
  }
//+------------------------------------------------------------------+
bool IsFractalHigh(int j, int n)
  {
   for(int k = 1; k <= n; k++)
      if(High[j] <= High[j - k] || High[j] <= High[j + k])
         return(false);
   return(true);
  }
//+------------------------------------------------------------------+
void RemoveOldestZone()
  {
   int n = ArraySize(g_zones);
   for(int k = 0; k < n - 1; k++)
      g_zones[k] = g_zones[k + 1];
   ArrayResize(g_zones, n - 1);
  }
//+------------------------------------------------------------------+
//| Drawing                                                           |
//+------------------------------------------------------------------+
void DrawAll()
  {
   datetime t2  = Time[0] + PeriodSeconds() * InpFutureBars;
   double   off = InpArrowPips * 10 * _Point;

   //--- zones
   for(int z = 0; z < ArraySize(g_zones); z++)
     {
      ZoneRec zn = g_zones[z];
      if(zn.state == 2 && !InpShowBroken)
         continue;
      string nm = PREFIX + "z" + IntegerToString(z) + "_" + IntegerToString((int)zn.t0);
      color  base = (zn.dir == 1) ? InpDemandFill : InpSupplyFill;
      color  edge = (zn.dir == 1) ? InpDemandEdge : InpSupplyEdge;
      if(zn.state == 2)
        {
         base = clrGray;
         edge = clrGray;
        }
      ENUM_LINE_STYLE sty = (zn.state == 2) ? STYLE_DASH :
                            ((zn.state == 1) ? STYLE_DOT : STYLE_SOLID);
      //--- light body of the zone
      if(ObjectCreate(0, nm, OBJ_RECTANGLE, 0, zn.t0, zn.top, t2, zn.bot))
        {
         ObjectSetInteger(0, nm, OBJPROP_BACK,  true);
         ObjectSetInteger(0, nm, OBJPROP_FILL,  (zn.state == 2) ? false : true);
         ObjectSetInteger(0, nm, OBJPROP_COLOR, base);
         ObjectSetInteger(0, nm, OBJPROP_STYLE, sty);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
         RememberName(nm);
        }
      //--- dark proximal (entry) line
      double prox = (zn.dir == 1) ? zn.top : zn.bot;
      string pn = nm + "p";
      if(ObjectCreate(0, pn, OBJ_TREND, 0, zn.t0, prox, t2, prox))
        {
         ObjectSetInteger(0, pn, OBJPROP_COLOR, edge);
         ObjectSetInteger(0, pn, OBJPROP_STYLE, sty);
         ObjectSetInteger(0, pn, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, pn, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, pn, OBJPROP_BACK, false);
         ObjectSetInteger(0, pn, OBJPROP_SELECTABLE, false);
         RememberName(pn);
        }
      //--- quality tag Q0..Q4
      string qn = nm + "q";
      if(ObjectCreate(0, qn, OBJ_TEXT, 0, zn.t0, prox, 0, 0))
        {
         ObjectSetString (0, qn, OBJPROP_TEXT, "Q" + IntegerToString(zn.score));
         ObjectSetString (0, qn, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, qn, OBJPROP_FONTSIZE, 7);
         ObjectSetInteger(0, qn, OBJPROP_COLOR, edge);
         ObjectSetInteger(0, qn, OBJPROP_ANCHOR,
                          (zn.dir == 1) ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
         ObjectSetInteger(0, qn, OBJPROP_SELECTABLE, false);
        }
     }

   //--- entry signals + plans
   for(int s = 0; s < ArraySize(g_sigs); s++)
     {
      SigRec sg   = g_sigs[s];
      string nm   = PREFIX + "s" + IntegerToString(s) + "_" + IntegerToString((int)sg.t);
      double ap   = sg.entry + ((sg.dir == 1) ? -off : off);

      if(ObjectCreate(0, nm, OBJ_ARROW, 0, sg.t, ap, 0, 0))
        {
         ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, (sg.dir == 1) ? 233 : 234);
         ObjectSetInteger(0, nm, OBJPROP_COLOR,     (sg.dir == 1) ? clrGreen : clrRed);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH,     2);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
        }
      string ln  = nm + "t";
      string txt = (sg.kind == 1) ? "LMT" : ((sg.kind == 2) ? "CNF" : "STR");
      if(!sg.room)
         txt = txt + " NR";
      double lp  = ap + ((sg.dir == 1) ? -off : off);
      if(ObjectCreate(0, ln, OBJ_TEXT, 0, sg.t, lp, 0, 0))
        {
         ObjectSetString (0, ln, OBJPROP_TEXT, txt);
         ObjectSetString (0, ln, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, ln, OBJPROP_FONTSIZE, 7);
         ObjectSetInteger(0, ln, OBJPROP_COLOR, sg.room ? ((sg.dir == 1) ? clrGreen : clrRed) : clrGray);
         ObjectSetInteger(0, ln, OBJPROP_ANCHOR,
                          (sg.dir == 1) ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
        }

      //--- trade plan lines
      if(InpDrawPlan && sg.room)
        {
         datetime t3 = sg.t + PeriodSeconds() * InpPlanBars;
         DrawPlanLine(nm + "e",  sg.t, t3, sg.entry, clrDodgerBlue, STYLE_SOLID, "E");
         DrawPlanLine(nm + "sl", sg.t, t3, sg.sl,    clrRed,        STYLE_DASH,  "SL");
         DrawPlanLine(nm + "tp", sg.t, t3, sg.tp,    clrGreen,      STYLE_DASH,  "TP");
        }
     }

   //--- info label
   int d = 0, sp = 0;
   for(int z = 0; z < ArraySize(g_zones); z++)
     {
      if(g_zones[z].state == 2)
         continue;
      if(g_zones[z].dir == 1)
         d++;
      else
         sp++;
     }
   string biasTxt = !InpUseHTF ? "HTF off" :
                    ((g_bias == 1) ? "HTF bull" : "HTF bear");
   string inf = PREFIX + "info";
   if(ObjectCreate(0, inf, OBJ_LABEL, 0, 0, 0, 0, 0))
     {
      ObjectSetInteger(0, inf, OBJPROP_CORNER,    1);
      ObjectSetInteger(0, inf, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, inf, OBJPROP_YDISTANCE, 15);
      ObjectSetString (0, inf, OBJPROP_FONT,      "Arial");
      ObjectSetInteger(0, inf, OBJPROP_FONTSIZE,  8);
      ObjectSetInteger(0, inf, OBJPROP_COLOR,     clrDimGray);
      ObjectSetString (0, inf, OBJPROP_TEXT,
                       StringFormat("SDZ | %s | demand %d / supply %d | signals %d | RR %.2f",
                                    biasTxt, d, sp, ArraySize(g_sigs), InpRR));
     }
  }
//+------------------------------------------------------------------+
void DrawPlanLine(string nm, datetime t1, datetime t2, double price,
                  color col, ENUM_LINE_STYLE sty, string tag)
  {
   if(ObjectCreate(0, nm, OBJ_TREND, 0, t1, price, t2, price))
     {
      ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
      ObjectSetInteger(0, nm, OBJPROP_STYLE, sty);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
     }
   string tn = nm + "t";
   if(ObjectCreate(0, tn, OBJ_TEXT, 0, t2, price, 0, 0))
     {
      ObjectSetString (0, tn, OBJPROP_TEXT, tag);
      ObjectSetString (0, tn, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, tn, OBJPROP_COLOR, col);
      ObjectSetInteger(0, tn, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
     }
  }
//+------------------------------------------------------------------+
void RememberName(string nm)
  {
   int cnt = ArraySize(g_zoneNames);
   ArrayResize(g_zoneNames, cnt + 1);
   g_zoneNames[cnt] = nm;
  }
//+------------------------------------------------------------------+
void StretchZones()
  {
   datetime t2 = Time[0] + PeriodSeconds() * InpFutureBars;
   for(int k = 0; k < ArraySize(g_zoneNames); k++)
      ObjectSetInteger(0, g_zoneNames[k], OBJPROP_TIME2, t2);
  }
//+------------------------------------------------------------------+
void CheckAlerts()
  {
   if(!InpAlertPopup && !InpAlertPush)
      return;
   for(int s = 0; s < ArraySize(g_sigs); s++)
     {
      if(g_sigs[s].t != Time[1])
         continue;                       // only brand-new (just closed) signals
      if(!g_sigs[s].room)
         continue;                       // no-room signals are not trade alerts
      string key = IntegerToString(g_sigs[s].kind) + "_" +
                   IntegerToString(g_sigs[s].dir) + "_" +
                   IntegerToString((int)g_sigs[s].t);
      if(key == g_alertedKey)
         continue;
      g_alertedKey = key;

      string side = (g_sigs[s].dir == 1) ? "BUY" : "SELL";
      string what = (g_sigs[s].kind == 1) ? "LMT" :
                    ((g_sigs[s].kind == 2) ? "CNF" : "STR");
      string msg = "SDZ " + Symbol() + " " + IntegerToString((int)Period()) + "m " +
                   side + " " + what +
                   " @ " + DoubleToString(g_sigs[s].entry, Digits) +
                   " SL " + DoubleToString(g_sigs[s].sl, Digits) +
                   " TP " + DoubleToString(g_sigs[s].tp, Digits) +
                   " (RR " + DoubleToString(InpRR, 2) + ")";
      if(InpAlertPopup)
         Alert(msg);
      if(InpAlertPush)
         SendNotification(msg);
     }
  }
//+------------------------------------------------------------------+
