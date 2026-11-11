//+------------------------------------------------------------------+
//|                                        SupplyDemand_BOS_Retest.mq4|
//|          Supply & Demand zones born from a STRONG MOVE that broke |
//|          market structure + FRESH retest + LTF confirmation.      |
//|                                                                   |
//|  Trading logic implemented (the 6 rules):                         |
//|  1. Find a strong move (displacement) that broke market structure |
//|     -> BOS = a candle CLOSES beyond the last confirmed swing.     |
//|  2. Mark the last OPPOSITE candle before that strong move.        |
//|     That candle (extended to the origin wick) is the zone.        |
//|  3. Wait for price to come BACK to the zone (retest).             |
//|     The indicator NEVER signals on the first touch alone.         |
//|  4. Entry needs a confirmation on a LOWER timeframe               |
//|     (structure break / engulfing / pin bar).                      |
//|  5. Zones already tested or broken are discarded (freshness).     |
//|  6. Stop loss is placed OUTSIDE the zone, target is the next      |
//|     liquidity / structure level; minimum R:R is enforced.         |
//|                                                                   |
//|  Attach it to the timeframe you want the ZONES from (H1 / H4 / D1).|
//|  It confirms automatically on the timeframe below (input override).|
//+------------------------------------------------------------------+
#property copyright   "Arena.ai agent for ismailchaacha97-ui"
#property link        "https://github.com/ismailchaacha97-ui/kkk"
#property version     "1.10"
#property description "Supply/Demand + BOS + fresh retest + lower timeframe confirmation."
#property description "No entry on the first touch: the trade needs an LTF confirmation."
#property description "Tested or broken zones are never traded again."
#property strict
#property indicator_chart_window
#property indicator_buffers 2

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_ZONE_MODE
  {
   ZONE_FULL_CANDLE = 0,   // Full candle (+ origin wick)
   ZONE_BODY        = 1,   // Body only (open/close)
   ZONE_OPEN_WICK   = 2    // Open -> wick (proximal/distal)
  };

enum ENUM_CONFIRM_MODE
  {
   CONFIRM_STRUCTURE = 0,  // LTF structure break
   CONFIRM_PATTERN   = 1,  // LTF reversal candle
   CONFIRM_BOTH      = 2   // Both required
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string  InpS1              = "=== 1. Market structure / BOS ===";  // ---
input int     InpSwingDepth      = 3;        // Swing strength (bars each side)
input int     InpHistoryBars     = 3000;     // Bars of history to scan
input int     InpATRPeriod       = 14;       // ATR period (volatility unit)
input double  InpMinImpulseATR   = 1.60;     // Min strong-move size (x ATR)
input int     InpMaxImpulseBars  = 12;       // Max bars for the strong move
input double  InpBOSBufferATR    = 0.05;     // Min close beyond swing (x ATR)

input string  InpS2              = "=== 2. Zone definition ===";         // ---
input ENUM_ZONE_MODE InpZoneMode = ZONE_FULL_CANDLE; // Zone size
input int     InpBaseLookback    = 6;        // Bars back to find opposite candle
input double  InpMaxZoneATR      = 3.00;     // Max zone height (x ATR), 0=off
input bool    InpDedupe          = true;     // Skip zones overlapping live ones
input int     InpMinBarsBetween  = 5;        // Min bars between two zones
input int     InpMaxZones        = 30;       // Max zones kept on the chart

input string  InpS3              = "=== 3/5. Retest & freshness ===";    // ---
input double  InpPenetrationPct  = 10.0;     // % of zone price must enter to count
input bool    InpInvalidOnClose  = true;     // Invalidate zone on CANDLE CLOSE (else wick)
input int     InpBreakBufferPts  = 10;       // Extra points beyond far edge to break
input int     InpLeaveBufferPts  = 30;       // Points away from zone that ends a visit
input bool    InpShowTested      = true;     // Draw zones that were tested
input bool    InpShowBroken      = false;    // Draw zones that were broken

input string  InpS4              = "=== 4. Lower timeframe confirmation ==="; // ---
input ENUM_TIMEFRAMES InpLowerTF = PERIOD_CURRENT; // Confirm TF (0 = one step down)
input ENUM_CONFIRM_MODE InpConfirmMode = CONFIRM_STRUCTURE; // Confirmation type
input int     InpLTFSwing        = 5;        // LTF bars for the structure break
input bool    InpRequireCloseBack= true;     // LTF close must be back outside the zone
input int     InpConfirmWindow   = 2;        // Extra closed LTF bars allowed
input double  InpMaxEntryDistATR = 1.00;     // Max distance price may run away (x ATR)

input string  InpS6              = "=== 6. Stop loss / target ===";      // ---
input int     InpSLBufferPts     = 50;       // Points beyond the zone for the stop
input double  InpSLBufferATR     = 0.30;     // ... or ATR fraction (bigger one is used)
input int     InpLiquidityBars   = 80;       // Bars scanned for the structure target
input double  InpMinRR           = 1.50;     // Minimum reward/risk to accept a signal
input double  InpMaxRiskATR      = 4.00;     // Max stop distance (x ATR), 0=off
input double  InpRRFallback      = 2.00;     // R:R used when no structure target found
input bool    InpShowTP2         = true;     // Second target = next liquidity level

input string  InpS7              = "=== Visuals & alerts ===";           // ---
input color   InpDemandColor     = clrDodgerBlue;  // Demand zone colour
input color   InpSupplyColor     = clrTomato;      // Supply zone colour
input color   InpTestedColor     = clrGray;        // Tested zone colour
input color   InpBrokenColor     = clrDimGray;     // Broken zone colour
input color   InpBuyArrowColor   = clrLime;        // Buy arrow colour
input color   InpSellArrowColor  = clrRed;         // Sell arrow colour
input bool    InpShowLevels      = true;     // Draw entry / SL / TP lines
input int     InpExtendBars      = 20;       // Bars to project live zones to the right
input bool    InpShowPanel       = true;     // Show the checklist panel
input int     InpPanelX          = 10;       // Panel X distance
input int     InpPanelY          = 20;       // Panel Y distance
input int     InpPanelSignalBars = 40;       // Keep a signal in the panel for N bars
input int     InpFontSize        = 9;        // Panel font size
input bool    InpAlertPopup      = true;     // Popup alert
input bool    InpAlertSound      = true;     // Sound alert
input bool    InpAlertPush       = false;    // Push notification
input bool    InpAlertMail       = false;    // E-mail alert
input string  InpSoundFile       = "alert2.wav"; // Sound file
input string  InpPrefix          = "SDBOS_"; // Object prefix

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define ZONE_DEMAND   1
#define ZONE_SUPPLY  -1

#define ST_FRESH   0
#define ST_INPLAY  1
#define ST_TESTED  2
#define ST_BROKEN  3
#define ST_SIGNAL  4

//+------------------------------------------------------------------+
//| Zone structure                                                   |
//+------------------------------------------------------------------+
struct ZoneInfo
  {
   int      type;            // ZONE_DEMAND / ZONE_SUPPLY
   double   top;             // upper edge
   double   bottom;          // lower edge
   double   prox;            // edge price reaches first (entry side)
   double   distal;          // far edge (stop loss side)
   datetime baseTime;        // time of the opposite candle (zone origin)
   datetime bosTime;         // time of the BOS candle
   int      state;           // ST_*
   bool     touching;        // price currently inside the zone
   int      touches;         // number of visits
   datetime visitStart;      // start of the current / first visit
   datetime lastTouch;       // last bar that touched the zone
   datetime stateTime;       // time the state changed
   bool     signaled;        // a confirmed signal was printed
   datetime signalTime;      // time of the signal
   double   entry;
   double   sl;
   double   tp;
   double   tp2;            // second target (next liquidity)
   double   rr;
   datetime evalLtf;         // last lower-TF candle already evaluated (tick cache)
   double   atr;             // ATR at zone creation
   int      id;              // sequence id for object names
  };

ZoneInfo Zones[];
int      ZoneCount = 0;

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
double   BufBuy[];
double   BufSell[];

int      gDepth     = 3;
int      gMaxBars   = 3000;
int      gATRPeriod = 14;
int      gMaxZones  = 30;
int      gLtfSwing  = 5;
int      gConfWin   = 2;
int      gLtfTF     = PERIOD_CURRENT;
int      gSeq       = 0;

//--- sanitised copies of the inputs (never trust the user)
int      gImpulseBars  = 12;
int      gBaseLookback = 6;
double   gPenPct       = 10.0;
int      gLiqBars      = 80;
int      gExtendBars   = 20;
int      gFontSize     = 9;
double   gMinRR        = 1.50;
int      gPanelSigBars = 40;

datetime gLastBarTime = 0;
datetime gLastAlert   = 0;
datetime gLastPanel   = 0;
bool     gReady       = false;
int      gConfirmCode = 0;
double   gNearestDist = 0.0;

//+------------------------------------------------------------------+
//| Small helpers                                                    |
//+------------------------------------------------------------------+
string TFText(int tf)
  {
   if(tf == PERIOD_CURRENT) tf = Period();
   string s = EnumToString((ENUM_TIMEFRAMES)tf);
   int p = StringFind(s, "PERIOD_");
   if(p >= 0)
      s = StringSubstr(s, p + 7);
   return s;
  }

int StepDownTF(int tf)
  {
   if(tf == PERIOD_MN1) return PERIOD_W1;
   if(tf == PERIOD_W1)  return PERIOD_D1;
   if(tf == PERIOD_D1)  return PERIOD_H4;
   if(tf == PERIOD_H4)  return PERIOD_H1;
   if(tf == PERIOD_H1)  return PERIOD_M30;
   if(tf == PERIOD_M30) return PERIOD_M15;
   if(tf == PERIOD_M15) return PERIOD_M5;
   if(tf == PERIOD_M5)  return PERIOD_M1;
   return PERIOD_M1;
  }

int ChartLtfRatio()
  {
   int a = PeriodSeconds(PERIOD_CURRENT);
   int b = PeriodSeconds(gLtfTF);
   if(b <= 0) return 1;
   int r = a / b;
   if(r < 1) r = 1;
   return r;
  }

string Px(double p)
  {
   return DoubleToString(p, _Digits);
  }

string Pts(double p)
  {
   return DoubleToString(p / _Point, 0);
  }

string StateText(int st)
  {
   if(st == ST_FRESH)  return "FRESH";
   if(st == ST_INPLAY) return "IN PLAY";
   if(st == ST_TESTED) return "TESTED";
   if(st == ST_BROKEN) return "BROKEN";
   if(st == ST_SIGNAL) return "SIGNAL";
   return "?";
  }

bool IsAlive(int st)
  {
   return (st == ST_FRESH || st == ST_INPLAY);
  }

double ATRat(int shift)
  {
   double v = iATR(_Symbol, PERIOD_CURRENT, gATRPeriod, shift);
   if(v <= 0) v = iHigh(_Symbol, PERIOD_CURRENT, shift) - iLow(_Symbol, PERIOD_CURRENT, shift);
   if(v <= 0) v = 10 * _Point;
   return v;
  }

//+------------------------------------------------------------------+
//| Object helpers                                                   |
//+------------------------------------------------------------------+
void DelObjectsByPrefix(string prefix)
  {
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, prefix) == 0)
         ObjectDelete(0, nm);
     }
  }

void ObjRectangle(string name, datetime t1, double p1, datetime t2, double p2,
                  color clr, int width, bool onBack)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, onBack);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void ObjText(string name, datetime t, double p, string text, color clr, int size)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   else
      ObjectMove(0, name, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void ObjHLine(string name, datetime t1, double price, color clr, int style, int width)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t1 + PeriodSeconds(PERIOD_CURRENT) * 2, price);
   else
     {
      ObjectMove(0, name, 0, t1, price);
      ObjectMove(0, name, 1, t1 + PeriodSeconds(PERIOD_CURRENT) * 2, price);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void ObjLabel(string name, int x, int y, string text, color clr, int size)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Fractals / swings                                                |
//+------------------------------------------------------------------+
bool IsFractalHigh(int c)
  {
   int total = Bars(_Symbol, PERIOD_CURRENT);
   if(c - gDepth < 0 || c + gDepth >= total) return false;
   double v = iHigh(_Symbol, PERIOD_CURRENT, c);
   for(int k = 1; k <= gDepth; k++)
     {
      if(iHigh(_Symbol, PERIOD_CURRENT, c - k) >= v) return false;
      if(iHigh(_Symbol, PERIOD_CURRENT, c + k) >  v) return false;
     }
   return true;
  }

bool IsFractalLow(int c)
  {
   int total = Bars(_Symbol, PERIOD_CURRENT);
   if(c - gDepth < 0 || c + gDepth >= total) return false;
   double v = iLow(_Symbol, PERIOD_CURRENT, c);
   for(int k = 1; k <= gDepth; k++)
     {
      if(iLow(_Symbol, PERIOD_CURRENT, c - k) <= v) return false;
      if(iLow(_Symbol, PERIOD_CURRENT, c + k) <  v) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Zone list helpers                                                |
//+------------------------------------------------------------------+
color ZoneColor(int i)
  {
   if(Zones[i].state == ST_BROKEN) return InpBrokenColor;
   if(Zones[i].state == ST_TESTED) return InpTestedColor;
   if(Zones[i].type == ZONE_DEMAND) return InpDemandColor;
   return InpSupplyColor;
  }

string ZoneTypeText(int type)
  {
   if(type == ZONE_DEMAND) return "DEMAND";
   return "SUPPLY";
  }

bool OverlapsLiveZone(int type, double top, double bottom)
  {
   for(int i = 0; i < ZoneCount; i++)
     {
      if(Zones[i].type != type) continue;
      if(!IsAlive(Zones[i].state)) continue;
      if(bottom < Zones[i].top && top > Zones[i].bottom) return true;
     }
   return false;
  }

void RemoveOldestZone()
  {
   if(ZoneCount <= 0) return;
   for(int k = 0; k < ZoneCount - 1; k++)
      Zones[k] = Zones[k + 1];
   ZoneCount--;
  }

void AddZone(int type, double top, double bottom, int baseShift, int bosShift, double atr)
  {
   if(ZoneCount >= gMaxZones) RemoveOldestZone();
   if(ZoneCount >= gMaxZones) return;

   ArrayResize(Zones, ZoneCount + 1);
   int i = ZoneCount;
   gSeq++;

   Zones[i].type        = type;
   Zones[i].top         = top;
   Zones[i].bottom      = bottom;
   Zones[i].prox        = (type == ZONE_DEMAND) ? top : bottom;
   Zones[i].distal      = (type == ZONE_DEMAND) ? bottom : top;
   Zones[i].baseTime    = iTime(_Symbol, PERIOD_CURRENT, baseShift);
   Zones[i].bosTime     = iTime(_Symbol, PERIOD_CURRENT, bosShift);
   Zones[i].state       = ST_FRESH;
   Zones[i].touching    = false;
   Zones[i].touches     = 0;
   Zones[i].visitStart  = 0;
   Zones[i].lastTouch   = 0;
   Zones[i].stateTime   = 0;
   Zones[i].signaled    = false;
   Zones[i].signalTime  = 0;
   Zones[i].entry       = 0.0;
   Zones[i].sl          = 0.0;
   Zones[i].tp          = 0.0;
   Zones[i].tp2         = 0.0;
   Zones[i].rr          = 0.0;
   Zones[i].evalLtf     = 0;
   Zones[i].atr         = atr;
   Zones[i].id          = gSeq;

   ZoneCount++;
  }

//+------------------------------------------------------------------+
//| Find the last opposite candle before the strong move             |
//| (demand -> last bearish candle, supply -> last bullish candle)   |
//+------------------------------------------------------------------+
int FindBaseShift(int originShift, int type)
  {
   int total = Bars(_Symbol, PERIOD_CURRENT);
   for(int k = 1; k <= gBaseLookback; k++)
     {
      int sh = originShift + k;
      if(sh >= total) return -1;
      double o = iOpen(_Symbol, PERIOD_CURRENT, sh);
      double c = iClose(_Symbol, PERIOD_CURRENT, sh);
      if(type == ZONE_DEMAND)
        {
         if(c < o) return sh;
        }
      else
        {
         if(c > o) return sh;
        }
     }
   return -1;
  }

//+------------------------------------------------------------------+
//| Build a zone from a confirmed BOS                                |
//+------------------------------------------------------------------+
bool TryCreateZone(int type, int bosShift, double atr, double brokenSwing)
  {
   int total = Bars(_Symbol, PERIOD_CURRENT);
   if(bosShift + gImpulseBars > total - 1) return false;

   //--- origin of the impulse (lowest low / highest high of the leg)
   int originShift;
   if(type == ZONE_DEMAND)
      originShift = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, gImpulseBars + 1, bosShift);
   else
      originShift = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, gImpulseBars + 1, bosShift);
   if(originShift < bosShift) originShift = bosShift;

   //--- rule 1: the move must be STRONG (displacement)
   double impulse;
   if(type == ZONE_DEMAND)
      impulse = iClose(_Symbol, PERIOD_CURRENT, bosShift) - iLow(_Symbol, PERIOD_CURRENT, originShift);
   else
      impulse = iHigh(_Symbol, PERIOD_CURRENT, originShift) - iClose(_Symbol, PERIOD_CURRENT, bosShift);
   if(impulse <= 0) return false;
   if(impulse < InpMinImpulseATR * atr) return false;

   //--- rule 2: last opposite candle before the move
   int baseShift = FindBaseShift(originShift, type);
   if(baseShift < 0) return false;

   double bo = iOpen(_Symbol, PERIOD_CURRENT, baseShift);
   double bc = iClose(_Symbol, PERIOD_CURRENT, baseShift);
   double bh = iHigh(_Symbol, PERIOD_CURRENT, baseShift);
   double bl = iLow(_Symbol, PERIOD_CURRENT, baseShift);
   double originExt = (type == ZONE_DEMAND) ? iLow(_Symbol, PERIOD_CURRENT, originShift)
                                            : iHigh(_Symbol, PERIOD_CURRENT, originShift);

   double top, bottom;
   if(InpZoneMode == ZONE_BODY)
     {
      top    = MathMax(bo, bc);
      bottom = MathMin(bo, bc);
     }
   else if(InpZoneMode == ZONE_OPEN_WICK)
     {
      if(type == ZONE_DEMAND)
        {
         top    = bo;
         bottom = MathMin(bl, originExt);
        }
      else
        {
         bottom = bo;
         top    = MathMax(bh, originExt);
        }
     }
   else // ZONE_FULL_CANDLE
     {
      if(type == ZONE_DEMAND)
        {
         top    = bh;
         bottom = MathMin(bl, originExt);
        }
      else
        {
         bottom = bl;
         top    = MathMax(bh, originExt);
        }
     }

   if(top <= bottom) return false;

   //--- zone must sit behind the broken structure
   if(type == ZONE_DEMAND && top >= brokenSwing) return false;
   if(type == ZONE_SUPPLY && bottom <= brokenSwing) return false;

   //--- sanity: not an absurd news candle
   if(InpMaxZoneATR > 0 && (top - bottom) > InpMaxZoneATR * atr) return false;

   //--- rule 5: do not duplicate a live zone
   if(InpDedupe && OverlapsLiveZone(type, top, bottom)) return false;
   if(InpMinBarsBetween > 0 && ZoneCount > 0)
     {
      datetime lastZone = Zones[ZoneCount - 1].bosTime;
      int bars = iBarShift(_Symbol, PERIOD_CURRENT, lastZone);
      if(bars >= 0 && bars < InpMinBarsBetween) return false;
     }

   AddZone(type, top, bottom, baseShift, bosShift, atr);
   return true;
  }

//+------------------------------------------------------------------+
//| Lower timeframe helpers                                          |
//+------------------------------------------------------------------+
int LtfBaseShift(int chartShift)
  {
   int sh;
   if(chartShift <= 0)
      sh = iBarShift(_Symbol, gLtfTF, iTime(_Symbol, PERIOD_CURRENT, 0));
   else
      sh = iBarShift(_Symbol, gLtfTF, iTime(_Symbol, PERIOD_CURRENT, chartShift));
   if(sh < 0) sh = 0;
   return sh;
  }

int LtfLastClosedShift(int chartShift)
  {
   if(chartShift <= 0)
     {
      int cur = iBarShift(_Symbol, gLtfTF, TimeCurrent());
      if(cur < 0) cur = 0;
      return cur + 1;
     }
   return LtfBaseShift(chartShift) + ChartLtfRatio() - 1;
  }

bool IsBullEngulf(int ls)
  {
   int total = Bars(_Symbol, gLtfTF);
   if(ls + 1 >= total) return false;
   double o  = iOpen(_Symbol, gLtfTF, ls);
   double c  = iClose(_Symbol, gLtfTF, ls);
   double po = iOpen(_Symbol, gLtfTF, ls + 1);
   double pc = iClose(_Symbol, gLtfTF, ls + 1);
   if(!(c > o && pc < po)) return false;
   return (c >= po && o <= pc);
  }

bool IsBearEngulf(int ls)
  {
   int total = Bars(_Symbol, gLtfTF);
   if(ls + 1 >= total) return false;
   double o  = iOpen(_Symbol, gLtfTF, ls);
   double c  = iClose(_Symbol, gLtfTF, ls);
   double po = iOpen(_Symbol, gLtfTF, ls + 1);
   double pc = iClose(_Symbol, gLtfTF, ls + 1);
   if(!(c < o && pc > po)) return false;
   return (o >= pc && c <= po);
  }

bool IsBullPin(int ls)
  {
   double o = iOpen(_Symbol, gLtfTF, ls);
   double c = iClose(_Symbol, gLtfTF, ls);
   double h = iHigh(_Symbol, gLtfTF, ls);
   double l = iLow(_Symbol, gLtfTF, ls);
   double range = h - l;
   if(range <= 0) return false;
   double body = MathAbs(c - o);
   double lowerWick = MathMin(o, c) - l;
   double upperWick = h - MathMax(o, c);
   if(lowerWick < MathMax(2.0 * body, range * 0.50)) return false;
   if(upperWick > range * 0.25) return false;
   if(c < l + range * 0.65) return false;
   return true;
  }

bool IsBearPin(int ls)
  {
   double o = iOpen(_Symbol, gLtfTF, ls);
   double c = iClose(_Symbol, gLtfTF, ls);
   double h = iHigh(_Symbol, gLtfTF, ls);
   double l = iLow(_Symbol, gLtfTF, ls);
   double range = h - l;
   if(range <= 0) return false;
   double body = MathAbs(c - o);
   double lowerWick = MathMin(o, c) - l;
   double upperWick = h - MathMax(o, c);
   if(upperWick < MathMax(2.0 * body, range * 0.50)) return false;
   if(lowerWick > range * 0.25) return false;
   if(c > l + range * 0.35) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Rule 4: is this LTF candle a valid confirmation?                 |
//| returns 0 = no, 1 = structure break, 2 = reversal candle         |
//+------------------------------------------------------------------+
int LtfConfirmCode(int zi, int ls)
  {
   int total = Bars(_Symbol, gLtfTF);
   if(ls < 0 || ls + gLtfSwing + 2 >= total) return 0;

   double c = iClose(_Symbol, gLtfTF, ls);
   if(c <= 0) return 0;

   int hiIdx = iHighest(_Symbol, gLtfTF, MODE_HIGH, gLtfSwing, ls + 1);
   int loIdx = iLowest(_Symbol, gLtfTF, MODE_LOW, gLtfSwing, ls + 1);
   if(hiIdx < 0 || loIdx < 0) return 0;
   double swingHi = iHigh(_Symbol, gLtfTF, hiIdx);
   double swingLo = iLow(_Symbol, gLtfTF, loIdx);

   bool structOk  = false;
   bool patternOk = false;

   if(Zones[zi].type == ZONE_DEMAND)
     {
      structOk  = (c > swingHi);
      patternOk = (IsBullEngulf(ls) || IsBullPin(ls));
      if(InpRequireCloseBack && c <= Zones[zi].prox) return 0;
     }
   else
     {
      structOk  = (c < swingLo);
      patternOk = (IsBearEngulf(ls) || IsBearPin(ls));
      if(InpRequireCloseBack && c >= Zones[zi].prox) return 0;
     }

   if(InpConfirmMode == CONFIRM_PATTERN) return (patternOk ? 2 : 0);
   if(InpConfirmMode == CONFIRM_BOTH)    return ((structOk && patternOk) ? 1 : 0);
   return (structOk ? 1 : 0);
  }

string LtfConfirmText(int code, int type)
  {
   if(code <= 0) return "";
   if(type == ZONE_DEMAND)
      return (code == 1) ? "LTF bullish structure break" : "LTF bullish reversal candle";
   return (code == 1) ? "LTF bearish structure break" : "LTF bearish reversal candle";
  }

//+------------------------------------------------------------------+
//| Search a confirmation for zone zi at chart bar "s"               |
//| returns the confirming LTF shift, or -1                          |
//+------------------------------------------------------------------+
int FindConfirmation(int zi, int s)
  {
   gConfirmCode = 0;
   int total = Bars(_Symbol, gLtfTF);
   if(total < gLtfSwing + 10) return -1;

   int oldest = LtfLastClosedShift(s) + gConfWin;
   int newest = LtfBaseShift(s);
   if(oldest > total - 1) oldest = total - 1;
   if(newest < 1) newest = 1;   // never use the still-forming LTF candle

   double atr  = ATRat(s);
   double maxd = InpMaxEntryDistATR * atr;

   for(int ls = oldest; ls >= newest; ls--)
     {
      if(ls < 0) break;
      //--- the confirmation candle must come AFTER the zone and AFTER the retest
      if(iTime(_Symbol, gLtfTF, ls) < Zones[zi].bosTime) continue;
      if(Zones[zi].visitStart > 0 && iTime(_Symbol, gLtfTF, ls) < Zones[zi].visitStart) continue;

      int code = LtfConfirmCode(zi, ls);
      if(code <= 0) continue;

      //--- price must not have run away from the zone
      //    (measured on the confirmation candle = deterministic, no repaint)
      double px = iClose(_Symbol, gLtfTF, ls);
      if(maxd > 0)
        {
         if(Zones[zi].type == ZONE_DEMAND && px > Zones[zi].prox + maxd) continue;
         if(Zones[zi].type == ZONE_SUPPLY && px < Zones[zi].prox - maxd) continue;
        }
      gConfirmCode = code;
      return ls;
     }
   return -1;
  }

//+------------------------------------------------------------------+
//| Rule 6 (bonus): next liquidity level beyond a reference price    |
//| used for the optional second target (TP2)                        |
//+------------------------------------------------------------------+
double FindNextLiquidity(int zi, int s, double refPrice)
  {
   int total = Bars(_Symbol, PERIOD_CURRENT);
   int maxSh = s + gLiqBars;
   if(maxSh > total - gDepth - 2) maxSh = total - gDepth - 2;
   double best = 0.0;

   if(Zones[zi].type == ZONE_DEMAND)
     {
      for(int sh = s + 1; sh <= maxSh; sh++)
        {
         if(!IsFractalHigh(sh)) continue;
         double h = iHigh(_Symbol, PERIOD_CURRENT, sh);
         if(h < refPrice) continue;
         if(best == 0.0 || h < best) best = h;
        }
     }
   else
     {
      for(int sh2 = s + 1; sh2 <= maxSh; sh2++)
        {
         if(!IsFractalLow(sh2)) continue;
         double l = iLow(_Symbol, PERIOD_CURRENT, sh2);
         if(l > refPrice) continue;
         if(best == 0.0 || l > best) best = l;
        }
     }
   return best;
  }

//+------------------------------------------------------------------+
//| Rule 6: target from liquidity / market structure                 |
//+------------------------------------------------------------------+
double FindTarget(int zi, int s, double entry, double risk)
  {
   int total = Bars(_Symbol, PERIOD_CURRENT);
   int look  = gLiqBars;
   if(look < 10) look = 10;
   int maxSh = s + look;
   if(maxSh > total - gDepth - 2) maxSh = total - gDepth - 2;
   double minDist = gMinRR * risk;

   if(Zones[zi].type == ZONE_DEMAND)
     {
      double minTarget = entry + minDist;
      double best = 0.0;
      for(int sh = s + 1; sh <= maxSh; sh++)
        {
         if(!IsFractalHigh(sh)) continue;
         double h = iHigh(_Symbol, PERIOD_CURRENT, sh);
         if(h < minTarget) continue;
         if(best == 0.0 || h < best) best = h;
        }
      if(best == 0.0)
        {
         int cnt = look;
         if(s + 1 + cnt > total - 1) cnt = total - 1 - (s + 1);
         int hiIdx = -1;
         if(cnt > 1) hiIdx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, cnt, s + 1);
         if(hiIdx > 0)
           {
            double mx = iHigh(_Symbol, PERIOD_CURRENT, hiIdx);
            if(mx >= minTarget) best = mx;
           }
        }
      if(best == 0.0)
        {
         double rr = MathMax(InpRRFallback, gMinRR);
         best = entry + rr * risk;
        }
      return best;
     }

   //--- supply
   double maxTarget = entry - minDist;
   double bestS = 0.0;
   for(int sh2 = s + 1; sh2 <= maxSh; sh2++)
     {
      if(!IsFractalLow(sh2)) continue;
      double l = iLow(_Symbol, PERIOD_CURRENT, sh2);
      if(l > maxTarget) continue;
      if(bestS == 0.0 || l > bestS) bestS = l;
     }
   if(bestS == 0.0)
     {
      int cntL = look;
      if(s + 1 + cntL > total - 1) cntL = total - 1 - (s + 1);
      int loIdx = -1;
      if(cntL > 1) loIdx = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, cntL, s + 1);
      if(loIdx > 0)
        {
         double mn = iLow(_Symbol, PERIOD_CURRENT, loIdx);
         if(mn <= maxTarget) bestS = mn;
        }
     }
   if(bestS == 0.0)
     {
      double rr2 = MathMax(InpRRFallback, gMinRR);
      bestS = entry - rr2 * risk;
     }
   return bestS;
  }

//+------------------------------------------------------------------+
//| Alert helper                                                     |
//+------------------------------------------------------------------+
void SendSignalAlert(int zi, string how)
  {
   if(Zones[zi].signalTime <= gLastAlert) return;
   gLastAlert = Zones[zi].signalTime;

   string dir = (Zones[zi].type == ZONE_DEMAND) ? "BUY" : "SELL";
   string msg = _Symbol + " " + TFText(PERIOD_CURRENT) + " " + dir + " setup: " +
                ZoneTypeText(Zones[zi].type) + " zone " +
                Px(Zones[zi].bottom) + "-" + Px(Zones[zi].top) +
                " | " + how +
                " | entry " + Px(Zones[zi].entry) +
                " SL " + Px(Zones[zi].sl) +
                " TP " + Px(Zones[zi].tp) +
                " R:R " + DoubleToString(Zones[zi].rr, 2);

   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound(InpSoundFile);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertMail)  SendMail("S/D signal " + _Symbol, msg);
  }

//+------------------------------------------------------------------+
//| Try to validate a signal on zone zi at chart bar s               |
//+------------------------------------------------------------------+
void TrySignal(int zi, int s)
  {
   if(Zones[zi].signaled) return;

   //--- performance: on the live bar evaluate a zone at most once per closed
   //    lower timeframe candle (the answer cannot change before it closes)
   if(s == 0)
     {
      int cacheShift = LtfLastClosedShift(0);
      if(cacheShift < 1) return;
      datetime stamp = iTime(_Symbol, gLtfTF, cacheShift);
      if(stamp <= 0) return;
      if(Zones[zi].evalLtf == stamp) return;
      Zones[zi].evalLtf = stamp;
     }

   int confirmShift = FindConfirmation(zi, s);
   if(confirmShift < 0) return;
   string how = LtfConfirmText(gConfirmCode, Zones[zi].type);

   double atr = ATRat(s);
   double buf = MathMax(InpSLBufferPts * _Point, InpSLBufferATR * atr);
   //--- entry = close of the confirming candle (stable, never repainted)
   double entry = iClose(_Symbol, gLtfTF, confirmShift);
   if(entry <= 0) entry = iClose(_Symbol, PERIOD_CURRENT, s);
   double sl, risk;

   if(Zones[zi].type == ZONE_DEMAND)
     {
      sl   = Zones[zi].distal - buf;
      risk = entry - sl;
     }
   else
     {
      sl   = Zones[zi].distal + buf;
      risk = sl - entry;
     }
   if(risk <= 0) return;
   if(InpMaxRiskATR > 0 && risk > InpMaxRiskATR * atr) return;   // zone too wide to trade

   double tp = FindTarget(zi, s, entry, risk);
   if(tp <= 0) return;

   double rr;
   if(Zones[zi].type == ZONE_DEMAND)
     {
      if(tp <= entry) return;
      rr = (tp - entry) / risk;
     }
   else
     {
      if(tp >= entry) return;
      rr = (entry - tp) / risk;
     }
   if(rr < gMinRR) return;

   //--- optional second target: next liquidity level beyond TP1
   Zones[zi].tp2 = 0.0;
   if(InpShowTP2)
     {
      double ref = (Zones[zi].type == ZONE_DEMAND) ? tp + 0.5 * risk : tp - 0.5 * risk;
      Zones[zi].tp2 = FindNextLiquidity(zi, s, ref);
     }

   Zones[zi].signaled   = true;
   Zones[zi].state      = ST_SIGNAL;
   Zones[zi].touching   = false;
   Zones[zi].signalTime = iTime(_Symbol, PERIOD_CURRENT, s);
   Zones[zi].stateTime  = Zones[zi].signalTime;
   Zones[zi].entry      = entry;
   Zones[zi].sl         = sl;
   Zones[zi].tp         = tp;
   Zones[zi].rr         = rr;

   double off = MathMax(0.20 * atr, 30 * _Point);
   if(Zones[zi].type == ZONE_DEMAND)
      BufBuy[s]  = iLow(_Symbol, PERIOD_CURRENT, s) - off;
   else
      BufSell[s] = iHigh(_Symbol, PERIOD_CURRENT, s) + off;

   if(s <= 1) SendSignalAlert(zi, how);
  }

//+------------------------------------------------------------------+
//| Rules 3 & 5: retest / freshness state machine                    |
//+------------------------------------------------------------------+
void ProcessZonesOnBar(int s, bool liveBar)
  {
   double hi = iHigh(_Symbol, PERIOD_CURRENT, s);
   double lo = iLow(_Symbol, PERIOD_CURRENT, s);
   double cl = iClose(_Symbol, PERIOD_CURRENT, s);
   datetime bt = iTime(_Symbol, PERIOD_CURRENT, s);

   double brkBuf   = InpBreakBufferPts * _Point;
   double leaveBuf = InpLeaveBufferPts * _Point;

   for(int i = ZoneCount - 1; i >= 0; i--)
     {
      if(!IsAlive(Zones[i].state)) continue;
      double h = Zones[i].top - Zones[i].bottom;
      if(h <= 0) continue;
      double pen = h * gPenPct / 100.0;

      bool entered = false;
      bool broken  = false;
      bool left    = false;

      if(Zones[i].type == ZONE_DEMAND)
        {
         entered = (lo <= Zones[i].prox - pen);
         broken  = InpInvalidOnClose ? (cl < Zones[i].distal - brkBuf)
                                     : (lo < Zones[i].distal - brkBuf);
         left    = (cl > Zones[i].prox + leaveBuf);
        }
      else
        {
         entered = (hi >= Zones[i].prox + pen);
         broken  = InpInvalidOnClose ? (cl > Zones[i].distal + brkBuf)
                                     : (hi > Zones[i].distal + brkBuf);
         left    = (cl < Zones[i].prox - leaveBuf);
        }

      if(broken)
        {
         Zones[i].state     = ST_BROKEN;
         Zones[i].stateTime = bt;
         Zones[i].touching  = false;
         continue;
        }

      if(entered)
        {
         if(!Zones[i].touching)
           {
            Zones[i].touching   = true;
            Zones[i].visitStart = bt;
            Zones[i].evalLtf    = 0;
            //--- one test per bar, even with many ticks inside the same bar
            if(Zones[i].lastTouch != bt) Zones[i].touches = Zones[i].touches + 1;
           }
         Zones[i].lastTouch = bt;
         if(Zones[i].state == ST_FRESH) Zones[i].state = ST_INPLAY;

         TrySignal(i, s);
         if(Zones[i].state == ST_SIGNAL) continue;
        }
      else if(Zones[i].touching && left)
        {
         Zones[i].touching = false;
         if(!Zones[i].signaled && !liveBar)
           {
            // rule 5: the zone was tested without confirmation -> dead
            Zones[i].state     = ST_TESTED;
            Zones[i].stateTime = bt;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Full history rebuild                                             |
//+------------------------------------------------------------------+
void Rebuild()
  {
   DelObjectsByPrefix(InpPrefix);
   ArrayInitialize(BufBuy, EMPTY_VALUE);
   ArrayInitialize(BufSell, EMPTY_VALUE);

   ZoneCount = 0;
   ArrayResize(Zones, 0, gMaxZones + 4);
   gSeq = 0;

   int total = Bars(_Symbol, PERIOD_CURRENT);
   int maxShift = (int)MathMin((double)gMaxBars, (double)(total - 2 * gDepth - 3));
   if(maxShift < 50)
     {
      DrawPanel();
      return;
     }

   double lastHigh = 0.0, lastLow = 0.0;
   bool   haveHigh = false, haveLow = false;
   bool   highBroken = false, lowBroken = false;

   //--- walk history from the oldest bar to the newest CLOSED bar
   for(int s = maxShift; s >= 1; s--)
     {
      int cand = s + gDepth;
      if(cand + gDepth <= total - 1)
        {
         if(IsFractalHigh(cand))
           {
            lastHigh   = iHigh(_Symbol, PERIOD_CURRENT, cand);
            haveHigh   = true;
            highBroken = false;
           }
         if(IsFractalLow(cand))
           {
            lastLow   = iLow(_Symbol, PERIOD_CURRENT, cand);
            haveLow   = true;
            lowBroken = false;
           }
        }

      double atr = ATRat(s);
      double cl  = iClose(_Symbol, PERIOD_CURRENT, s);
      double bosBuf = InpBOSBufferATR * atr;

      //--- rule 1: BOS = close beyond the last confirmed swing
      if(haveHigh && !highBroken && cl > lastHigh + bosBuf)
        {
         highBroken = true;
         TryCreateZone(ZONE_DEMAND, s, atr, lastHigh);
        }
      if(haveLow && !lowBroken && cl < lastLow - bosBuf)
        {
         lowBroken = true;
         TryCreateZone(ZONE_SUPPLY, s, atr, lastLow);
        }

      ProcessZonesOnBar(s, false);
     }

   DrawZones();
   DrawPanel();
  }

//+------------------------------------------------------------------+
//| Live update (the forming bar)                                    |
//+------------------------------------------------------------------+
void LiveUpdate()
  {
   if(ZoneCount > 0)
      ProcessZonesOnBar(0, true);
  }

//+------------------------------------------------------------------+
//| Drawing: zones and trade levels                                  |
//+------------------------------------------------------------------+
void DrawTradeLevels(int i, datetime t2)
  {
   if(!InpShowLevels) return;
   string base = InpPrefix + "L" + IntegerToString(Zones[i].id);
   datetime t1 = Zones[i].signalTime;
   if(t1 <= 0) return;

   ObjHLine(base + "_E", t1, Zones[i].entry, clrGold, STYLE_DOT, 1);
   ObjHLine(base + "_S", t1, Zones[i].sl, clrRed, STYLE_DASH, 1);
   ObjHLine(base + "_T", t1, Zones[i].tp, clrLime, STYLE_DASH, 1);

   ObjText(base + "_Et", t2, Zones[i].entry, "entry " + Px(Zones[i].entry), clrGold, 8);
   ObjText(base + "_St", t2, Zones[i].sl, "SL " + Px(Zones[i].sl), clrRed, 8);
   ObjText(base + "_Tt", t2, Zones[i].tp, "TP " + Px(Zones[i].tp) +
           "  (R:R " + DoubleToString(Zones[i].rr, 2) + ")", clrLime, 8);

   if(InpShowTP2 && Zones[i].tp2 > 0.0)
     {
      double risk = MathAbs(Zones[i].entry - Zones[i].sl);
      double rr2  = (risk > 0) ? MathAbs(Zones[i].tp2 - Zones[i].entry) / risk : 0.0;
      ObjHLine(base + "_T2", t1, Zones[i].tp2, clrMediumSeaGreen, STYLE_DOT, 1);
      ObjText(base + "_T2t", t2, Zones[i].tp2, "TP2 " + Px(Zones[i].tp2) +
              "  (R:R " + DoubleToString(rr2, 2) + ")", clrMediumSeaGreen, 8);
     }
  }

void DrawZones()
  {
   int ps = PeriodSeconds(PERIOD_CURRENT);
   datetime right = iTime(_Symbol, PERIOD_CURRENT, 0) + gExtendBars * ps;

   for(int i = 0; i < ZoneCount; i++)
     {
      if(Zones[i].state == ST_TESTED && !InpShowTested) continue;
      if(Zones[i].state == ST_BROKEN && !InpShowBroken) continue;

      bool alive = IsAlive(Zones[i].state);
      bool extend = (alive || Zones[i].state == ST_SIGNAL);
      datetime t1 = Zones[i].baseTime;
      datetime t2;
      if(extend)
         t2 = right;
      else
        {
         t2 = (Zones[i].stateTime > t1) ? Zones[i].stateTime : right;
         if(t2 < t1) t2 = t1 + ps;
        }

      string base = InpPrefix + "Z" + IntegerToString(Zones[i].id);
      color c = ZoneColor(i);
      ObjRectangle(base, t1, Zones[i].top, t2, Zones[i].bottom, c, 1, true);

      string lbl = ZoneTypeText(Zones[i].type);
      lbl = lbl + "  " + StateText(Zones[i].state);
      if(Zones[i].touches > 0) lbl = lbl + "  (" + IntegerToString(Zones[i].touches) + " test)";
      if(alive && Zones[i].touching) lbl = lbl + "  - wait " + TFText(gLtfTF) + " confirm";
      //--- keep the label inside the zone so it stays on screen
      datetime lt = t1 + (t2 - t1) / 3;
      ObjText(base + "_t", lt, Zones[i].top, lbl, c, 8);

      if(Zones[i].signaled)
         DrawTradeLevels(i, right - 8 * ps);
     }
  }

//+------------------------------------------------------------------+
//| Panel: the 6 rules check list                                    |
//+------------------------------------------------------------------+
int NearestZone()
  {
   int best = -1;
   double bd = 0.0;
   gNearestDist = 0.0;
   double px = iClose(_Symbol, PERIOD_CURRENT, 0);
   for(int i = 0; i < ZoneCount; i++)
     {
      bool usable = IsAlive(Zones[i].state);
      if(!usable && Zones[i].state == ST_SIGNAL)
        {
         //--- keep the fresh signal (and its trade plan) in the panel for a while
         int age = iBarShift(_Symbol, PERIOD_CURRENT, Zones[i].signalTime);
         if(age >= 0 && age <= gPanelSigBars) usable = true;
        }
      if(!usable) continue;
      double d = 0.0;
      if(px > Zones[i].top)      d = px - Zones[i].top;
      else if(px < Zones[i].bottom) d = Zones[i].bottom - px;
      if(best < 0 || d < bd)
        {
         best = i;
         bd = d;
        }
     }
   gNearestDist = bd;
   return best;
  }

//+------------------------------------------------------------------+
//| Same confirmation rules as the signal engine, for the panel      |
//+------------------------------------------------------------------+
int PanelConfirmCode(int zi)
  {
   int ls = LtfLastClosedShift(0);
   if(ls < 1) return 0;
   datetime t = iTime(_Symbol, gLtfTF, ls);
   if(t <= 0) return 0;
   if(t < Zones[zi].bosTime) return 0;
   if(Zones[zi].visitStart > 0 && t < Zones[zi].visitStart) return 0;
   if(iClose(_Symbol, gLtfTF, ls) <= 0) return 0;
   return LtfConfirmCode(zi, ls);
  }

void PanelLine(int idx, string text, color clr)
  {
   ObjLabel(InpPrefix + "P" + IntegerToString(idx), InpPanelX, InpPanelY + idx * (gFontSize + 6),
            text, clr, gFontSize);
  }

void DrawPanel()
  {
   if(!InpShowPanel) return;

   color okC   = clrLime;
   color waitC = clrOrange;
   color badC  = clrRed;
   color dimC  = clrSilver;

   PanelLine(0, "SUPPLY / DEMAND  -  BOS + FRESH RETEST", clrWhite);
   PanelLine(1, "chart " + TFText(PERIOD_CURRENT) + "   confirm " + TFText(gLtfTF) +
             "   bars " + IntegerToString(Bars(_Symbol, PERIOD_CURRENT)), dimC);
   PanelLine(2, "------------------------------------------------", dimC);

   int zi = NearestZone();

   if(zi < 0)
     {
      PanelLine(3, "No active zone on this chart.", waitC);
      PanelLine(4, "Waiting for a strong move that breaks structure.", dimC);
      for(int k = 5; k < 12; k++) PanelLine(k, " ", dimC);
      PanelLine(12, "1 strong move + BOS      -> search", dimC);
      PanelLine(13, "2 last opposite candle   -> zone", dimC);
      PanelLine(14, "3 retest of the zone     -> wait", dimC);
      PanelLine(15, "4 LTF confirmation       -> entry", dimC);
      PanelLine(16, "5 fresh zone only        -> filter", dimC);
      PanelLine(17, "6 SL outside / TP by structure", dimC);
      for(int k2 = 18; k2 < 22; k2++) PanelLine(k2, " ", dimC);
      return;
     }

   bool liveConfirm = false;
   string confText = "-";
   int liveCode = PanelConfirmCode(zi);
   if(liveCode > 0 && Zones[zi].touching)
     {
      liveConfirm = true;
      confText = LtfConfirmText(liveCode, Zones[zi].type);
     }

   PanelLine(3, "Zone    " + ZoneTypeText(Zones[zi].type) + "   (" +
             ((Zones[zi].type == ZONE_DEMAND) ? "BOS up)" : "BOS down)"), ZoneColor(zi));
   PanelLine(4, "Edges   " + Px(Zones[zi].bottom) + " - " + Px(Zones[zi].top) +
             "   (" + Pts(Zones[zi].top - Zones[zi].bottom) + " pts)", dimC);
   PanelLine(5, "State   " + StateText(Zones[zi].state) + "   tests " +
             IntegerToString(Zones[zi].touches), dimC);
   PanelLine(6, "Dist    " + Pts(gNearestDist) + " pts   ATR " + Pts(Zones[zi].atr) + " pts", dimC);
   PanelLine(7, "Created " + TimeToString(Zones[zi].baseTime, TIME_DATE | TIME_MINUTES) +
             "   " + IntegerToString(iBarShift(_Symbol, PERIOD_CURRENT, Zones[zi].baseTime)) +
             " bars ago", dimC);
   PanelLine(8, "------------ RULE CHECK LIST -------------------", dimC);

   PanelLine(9, "1 strong move + BOS    [OK]", okC);
   PanelLine(10, "2 last opposite candle [OK]", okC);

   string retest = "[WAIT] price above zone";
   color  retestC = waitC;
   if(Zones[zi].state == ST_SIGNAL)
     {
      retest = "[OK] retested + confirmed";
      retestC = okC;
     }
   else if(Zones[zi].touching)
     {
      retest = "[..] inside the zone now";
      retestC = waitC;
     }
   else if(Zones[zi].touches > 0)
     {
      retest = "[!] already tested";
      retestC = badC;
     }
   else if(Zones[zi].type == ZONE_SUPPLY)
      retest = "[WAIT] price below zone";
   PanelLine(11, "3 retest of the zone   " + retest, retestC);

   string confLine = "[WAIT] needs the retest first";
   color  confC = waitC;
   if(Zones[zi].state == ST_SIGNAL)
     {
      confLine = "[OK] confirmed on " + TFText(gLtfTF);
      confC = okC;
     }
   else if(Zones[zi].touching && liveConfirm)
     {
      confLine = "[OK] " + confText;
      confC = okC;
     }
   else if(Zones[zi].touching)
     {
      confLine = "[WAIT] " + TFText(gLtfTF) + " not confirmed yet";
     }
   PanelLine(12, "4 confirm " + TFText(gLtfTF) + "  " + confLine, confC);

   string fresh = "[OK] untouched zone";
   color  freshC = okC;
   if(Zones[zi].state == ST_SIGNAL)
     {
      fresh = "[OK] was untouched, first test only";
      freshC = okC;
     }
   else if(Zones[zi].touches > 1)
     {
      fresh = "[NO] over-tested (" + IntegerToString(Zones[zi].touches) + ")";
      freshC = badC;
     }
   else if(Zones[zi].touches == 1)
     {
      fresh = "[!] first test in progress";
      freshC = waitC;
     }
   PanelLine(13, "5 fresh zone only      " + fresh, freshC);

   if(Zones[zi].state == ST_SIGNAL)
     {
      PanelLine(14, "6 SL " + Px(Zones[zi].sl) + "  TP " + Px(Zones[zi].tp) +
                "  R:R " + DoubleToString(Zones[zi].rr, 2), okC);
     }
   else
      PanelLine(14, "6 SL " + Pts(MathMax(InpSLBufferPts * _Point, InpSLBufferATR * Zones[zi].atr)) +
                " pts beyond zone, TP on structure", dimC);

   PanelLine(15, "------------ TRADE PLAN ------------------------", dimC);
   if(Zones[zi].state == ST_SIGNAL)
     {
      PanelLine(16, "SIGNAL " + ((Zones[zi].type == ZONE_DEMAND) ? "BUY" : "SELL") +
                " @ " + Px(Zones[zi].entry), okC);
      PanelLine(17, "SL " + Px(Zones[zi].sl) + "   TP " + Px(Zones[zi].tp) +
                "   R:R " + DoubleToString(Zones[zi].rr, 2), okC);
      if(InpShowTP2 && Zones[zi].tp2 > 0.0)
         PanelLine(18, "TP2 " + Px(Zones[zi].tp2) + "  (next liquidity)", dimC);
      else
         PanelLine(18, "Signal time " + TimeToString(Zones[zi].signalTime, TIME_DATE | TIME_MINUTES), dimC);
     }
   else
     {
      PanelLine(16, "NO TRADE YET.", waitC);
      PanelLine(17, "Do not enter on arrival at the zone.", dimC);
      PanelLine(18, "Wait for the " + TFText(gLtfTF) + " confirmation.", dimC);
     }
   PanelLine(19, " ", dimC);
   PanelLine(20, "Zone " + IntegerToString(zi + 1) + "/" + IntegerToString(ZoneCount), dimC);
   PanelLine(21, " ", dimC);
  }

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- clamp inputs into globals
   gDepth = InpSwingDepth;
   if(gDepth < 1) gDepth = 1;
   if(gDepth > 10) gDepth = 10;

   gMaxBars = InpHistoryBars;
   if(gMaxBars < 200) gMaxBars = 200;
   if(gMaxBars > 20000) gMaxBars = 20000;

   gATRPeriod = InpATRPeriod;
   if(gATRPeriod < 2) gATRPeriod = 2;

   gMaxZones = InpMaxZones;
   if(gMaxZones < 4) gMaxZones = 4;
   if(gMaxZones > 200) gMaxZones = 200;

   gLtfSwing = InpLTFSwing;
   if(gLtfSwing < 2) gLtfSwing = 2;
   if(gLtfSwing > 50) gLtfSwing = 50;

   gConfWin = InpConfirmWindow;
   if(gConfWin < 0) gConfWin = 0;
   if(gConfWin > 20) gConfWin = 20;

   gImpulseBars = InpMaxImpulseBars;
   if(gImpulseBars < 2) gImpulseBars = 2;
   if(gImpulseBars > 100) gImpulseBars = 100;

   gBaseLookback = InpBaseLookback;
   if(gBaseLookback < 1) gBaseLookback = 1;
   if(gBaseLookback > 50) gBaseLookback = 50;

   gPenPct = InpPenetrationPct;
   if(gPenPct < 0.0) gPenPct = 0.0;
   if(gPenPct > 90.0) gPenPct = 90.0;

   gLiqBars = InpLiquidityBars;
   if(gLiqBars < 10) gLiqBars = 10;
   if(gLiqBars > 1000) gLiqBars = 1000;

   gMinRR = InpMinRR;
   if(gMinRR < 0.2) gMinRR = 0.2;
   if(gMinRR > 20.0) gMinRR = 20.0;

   gExtendBars = InpExtendBars;
   if(gExtendBars < 1) gExtendBars = 1;
   if(gExtendBars > 500) gExtendBars = 500;

   gFontSize = InpFontSize;
   if(gFontSize < 6) gFontSize = 6;
   if(gFontSize > 14) gFontSize = 14;

   gPanelSigBars = InpPanelSignalBars;
   if(gPanelSigBars < 0) gPanelSigBars = 0;
   if(gPanelSigBars > 5000) gPanelSigBars = 5000;

   gLtfTF = (InpLowerTF == PERIOD_CURRENT) ? StepDownTF(Period()) : InpLowerTF;
   if(PeriodSeconds(gLtfTF) > PeriodSeconds(PERIOD_CURRENT))
     {
      Print("SupplyDemand: lower TF must not be higher than the chart TF. Using the chart TF.");
      gLtfTF = PERIOD_CURRENT;
     }

   SetIndexBuffer(0, BufBuy);
   SetIndexStyle(0, DRAW_ARROW, STYLE_SOLID, 2, InpBuyArrowColor);
   SetIndexArrow(0, 233);
   SetIndexLabel(0, "Buy signal");
   SetIndexEmptyValue(0, EMPTY_VALUE);

   SetIndexBuffer(1, BufSell);
   SetIndexStyle(1, DRAW_ARROW, STYLE_SOLID, 2, InpSellArrowColor);
   SetIndexArrow(1, 234);
   SetIndexLabel(1, "Sell signal");
   SetIndexEmptyValue(1, EMPTY_VALUE);

   IndicatorShortName("SupplyDemand BOS Retest (" + TFText(PERIOD_CURRENT) +
                      " / " + TFText(gLtfTF) + ")");

   gReady = true;
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DelObjectsByPrefix(InpPrefix);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Main                                                             |
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
   if(!gReady) return 0;
   if(rates_total < 100) return 0;

   bool newBar = (gLastBarTime != iTime(_Symbol, PERIOD_CURRENT, 0));
   if(newBar)
     {
      gLastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      Rebuild();
     }
   else
      LiveUpdate();

   if(TimeCurrent() != gLastPanel)
     {
      gLastPanel = TimeCurrent();
      DrawPanel();
      ChartRedraw();
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
