//+------------------------------------------------------------------+
//|                                            SDZ_ThreeEntries.mq4  |
//|  Supply & Demand zones with the three entry styles:              |
//|    [1] PENDING LIMIT   - limit order tagged at the zone's        |
//|                          proximal line when the zone forms       |
//|    [2] CONFIRMATION    - engulfing candle printed inside the     |
//|                          zone after a tap                        |
//|    [3] PULLBACK STRUCT - zone tap -> swing -> counter-swing ->   |
//|                          structure break entry                   |
//|                                                                  |
//|  Zone model:                                                     |
//|    * an impulse candle (body >= mult*ATR, optionally breaking    |
//|      prior structure) defines a zone from its base (the last     |
//|      opposite-colour candle before the impulse, including the    |
//|      candles between base and impulse).                          |
//|    * zone states: fresh -> tapped (mitigated) -> broken (close   |
//|      beyond the far edge).                                       |
//|                                                                  |
//|  All detection runs on CLOSED candles only -> no repainting.     |
//|  Uses the predefined series arrays (Time/Open/High/Low/Close).   |
//+------------------------------------------------------------------+
#property copyright "Arena.ai"
#property version   "1.00"
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

//--- entry styles ----------------------------------------------------
input bool   InpEntryLimit     = true;        // entry 1: pending limit marks
input bool   InpEntryConfirm   = true;        // entry 2: engulfing confirmation
input bool   InpEntryStruct    = true;        // entry 3: pullback structure
input int    InpFractalN       = 2;           // fractal side bars (structure entry)

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
  };

struct SigRec
  {
   datetime          t;
   double            price;      // anchor price (arrow offset applied at draw)
   int               dir;        // +1 buy, -1 sell
   int               kind;       // 1 limit, 2 confirm, 3 structure
  };

ZoneRec  g_zones[];
SigRec   g_sigs[];
string   g_zoneNames[];
datetime g_lastBar    = 0;
string   g_alertedKey = "";

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
      //--- forming bar: just keep zone rectangles glued to the right edge
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

   int start = total - 3 - InpBOSLookback;
   if(start > InpHistoryBars)
      start = InpHistoryBars;
   if(start < 1)
      start = 1;

   for(int i = start; i >= 1; i--)
     {
      //--- first let existing zones react to this closed bar
      int zn = ArraySize(g_zones);
      for(int z = 0; z < zn; z++)
         UpdateZone(z, i, total);
      //--- then check whether this bar births a new zone
      TryFormZone(i, total);
     }
  }
//+------------------------------------------------------------------+
//| Zone birth: impulse candle + base                                 |
//+------------------------------------------------------------------+
void TryFormZone(int i, int total)
  {
   if(i < 2)
      return;                              // never use the forming bar as base
   double atr = iATR(NULL, 0, InpATRPeriod, i);
   if(atr <= 0.0)
      return;
   double body = MathAbs(Close[i] - Open[i]);
   if(body < InpImpulseMult * atr)
      return;                              // not an impulse
   int dir = (Close[i] > Open[i]) ? 1 : -1;

   //--- optional structure break: close beyond prior swing
   if(InpRequireBOS)
     {
      double hh = -DBL_MAX, ll = DBL_MAX;
      for(int k = 1; k <= InpBOSLookback; k++)
        {
         if(i + k >= total)
            break;
         hh = MathMax(hh, High[i + k]);
         ll = MathMin(ll, Low[i + k]);
        }
      if(dir ==  1 && !(Close[i] > hh))
         return;
      if(dir == -1 && !(Close[i] < ll))
         return;
     }

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

   //--- entry style 1: pending limit sits at the proximal line
   if(InpEntryLimit)
      AddSig(Time[i], dir, 1, (dir == 1) ? zt : zb);
  }
//+------------------------------------------------------------------+
//| Let one zone react to one closed bar                              |
//+------------------------------------------------------------------+
void UpdateZone(int zi, int i, int total)
  {
   ZoneRec z = g_zones[zi];
   if(z.state == 2)
      return;                              // broken zones are frozen

   //--- tap / invalidation
   if(z.dir == 1)
     {
      if(Close[i] < z.bot)                 // closed through the far edge
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
            AddSig(Time[i], 1, 2, Low[i]);
           }
         if(z.dir == -1 && bear && bullP && Open[i] >= Close[i+1] && Close[i] <= Open[i+1])
           {
            z.confDone = true;
            AddSig(Time[i], -1, 2, High[i]);
           }
        }
     }

   //--- entry style 3: tap -> swing -> counter-swing -> break
   if(InpEntryStruct && !z.strDone && z.phase >= 1 && z.phase <= 3)
     {
      int j = i - InpFractalN;             // fractal at j is confirmed by bar i
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
            AddSig(Time[i], 1, 3, Low[i]);
           }
         if(z.dir == -1 && Close[i] < z.sw2)
           {
            z.strDone = true; z.phase = 4;
            AddSig(Time[i], -1, 3, High[i]);
           }
        }
     }

   g_zones[zi] = z;
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
void AddSig(datetime t, int dir, int kind, double anchor)
  {
   int n = ArraySize(g_sigs);
   ArrayResize(g_sigs, n + 1);
   g_sigs[n].t     = t;
   g_sigs[n].dir   = dir;
   g_sigs[n].kind  = kind;
   g_sigs[n].price = anchor;
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
         int cnt = ArraySize(g_zoneNames);
         ArrayResize(g_zoneNames, cnt + 1);
         g_zoneNames[cnt] = nm;
        }
      //--- dark proximal (entry) line, like the reference chart
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
         int cnt = ArraySize(g_zoneNames);
         ArrayResize(g_zoneNames, cnt + 1);
         g_zoneNames[cnt] = pn;
        }
     }

   //--- entry signals
   for(int s = 0; s < ArraySize(g_sigs); s++)
     {
      SigRec sg   = g_sigs[s];
      string nm   = PREFIX + "s" + IntegerToString(s) + "_" + IntegerToString((int)sg.t);
      double price = sg.price + ((sg.dir == 1) ? -off : off);

      if(ObjectCreate(0, nm, OBJ_ARROW, 0, sg.t, price, 0, 0))
        {
         ObjectSetInteger(0, nm, OBJPROP_ARROWCODE, (sg.dir == 1) ? 233 : 234);
         ObjectSetInteger(0, nm, OBJPROP_COLOR,     (sg.dir == 1) ? clrGreen : clrRed);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH,     2);
         ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
        }
      string ln  = nm + "t";
      string txt = (sg.kind == 1) ? "LMT" : ((sg.kind == 2) ? "CNF" : "STR");
      double lp  = price + ((sg.dir == 1) ? -off : off);
      if(ObjectCreate(0, ln, OBJ_TEXT, 0, sg.t, lp, 0, 0))
        {
         ObjectSetString (0, ln, OBJPROP_TEXT, txt);
         ObjectSetString (0, ln, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, ln, OBJPROP_FONTSIZE, 7);
         ObjectSetInteger(0, ln, OBJPROP_COLOR, (sg.dir == 1) ? clrGreen : clrRed);
         ObjectSetInteger(0, ln, OBJPROP_ANCHOR,
                          (sg.dir == 1) ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
         ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
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
                       StringFormat("SDZ | demand %d / supply %d | signals %d",
                                    d, sp, ArraySize(g_sigs)));
     }
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
         continue;                         // only brand-new (just closed) signals
      string key = IntegerToString(g_sigs[s].kind) + "_" +
                   IntegerToString(g_sigs[s].dir) + "_" +
                   IntegerToString((int)g_sigs[s].t);
      if(key == g_alertedKey)
         continue;
      g_alertedKey = key;

      string side = (g_sigs[s].dir == 1) ? "BUY" : "SELL";
      string what = (g_sigs[s].kind == 1) ? "pending limit at zone" :
                    ((g_sigs[s].kind == 2) ? "engulfing confirmation" :
                                             "pullback structure break");
      string msg = "SDZ " + Symbol() + " " + IntegerToString((int)Period()) + "m " +
                   side + " - " + what;
      if(InpAlertPopup)
         Alert(msg);
      if(InpAlertPush)
         SendNotification(msg);
     }
  }
//+------------------------------------------------------------------+
