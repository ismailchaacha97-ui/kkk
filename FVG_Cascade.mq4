//+------------------------------------------------------------------+
//|                                                  FVG_Cascade.mq4 |
//|        ICT-style FVG cascade indicator for MT4                  |
//|                                                                  |
//|  Strategy implemented (multi-timeframe cascade):                 |
//|                                                                  |
//|  STEP 1 - H1  : BIAS. Orderflow decides the bias:                |
//|                 - bearish FVGs being invalidated (price closes   |
//|                   above them)  -> bullish orderflow -> BULL bias |
//|                 - bullish FVGs being invalidated (price closes   |
//|                   below them)  -> bearish orderflow -> BEAR bias |
//|  STEP 2 - M30 : PD ARRAY. Find the inversion FVG (IFVG) that     |
//|                 matches the bias (a bearish FVG inverted upward  |
//|                 = bullish IFVG support, and vice versa) and wait |
//|                 for price to trade back into the zone.           |
//|  STEP 3 - M5  : SWING. After the tap, wait for price to print    |
//|                 a low (for buys) / high (for sells), confirmed   |
//|                 as an M5 fractal pivot.                          |
//|  STEP 4 - M1  : TRIGGER + EXECUTION. Wait for the opposite-side  |
//|                 M1 FVG to be invalidated by a closing candle     |
//|                 (buy : bearish M1 FVG closed above,              |
//|                  sell: bullish M1 FVG closed below) -> SIGNAL    |
//|                 with entry / SL / TP and alerts.                 |
//|                                                                  |
//|  Attach to the pair you trade (EURUSD) on the M1 chart.          |
//|  All logic runs on CLOSED candles only -> no repainting.         |
//+------------------------------------------------------------------+
#property copyright   "FVG Cascade"
#property link        ""
#property version     "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_color1  clrLime
#property indicator_color2  clrOrangeRed
#property indicator_width1  2
#property indicator_width2  2

//--- stop loss placement
enum ENUM_SL_MODE
  {
   SL_SWING = 0,   // Swing extreme since tap (M5 low / high)
   SL_ZONE  = 1,   // Far side of the M30 IFVG zone
   SL_FVG   = 2    // Far side of the M1 trigger FVG
  };
//--- take profit mode
enum ENUM_TP_MODE
  {
   TP_RR    = 0,   // Risk : Reward multiple
   TP_FIXED = 1    // Fixed points
  };

//=================== INPUTS: the cascade ==========================
input ENUM_TIMEFRAMES InpBiasTF  = PERIOD_H1;   // Step 1: bias timeframe
input ENUM_TIMEFRAMES InpZoneTF  = PERIOD_M30;  // Step 2: inversion FVG timeframe
input ENUM_TIMEFRAMES InpSwingTF = PERIOD_M5;   // Step 3: swing timeframe
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M1;   // Step 4: entry timeframe

//=================== INPUTS: bias (step 1) ========================
input int InpH1Lookback     = 200;  // Bias TF: bars scanned for FVGs
input int InpBiasWindowBars = 24;   // Bias: event counting window (bars of bias TF)
input int InpBiasMaxAgeBars = 36;   // Bias: latest invalidation newer than this (bars)
input int InpBiasMinEvents  = 1;    // Bias: min invalidation events supporting it

//=================== INPUTS: zone (step 2) ========================
input int    InpM30Lookback    = 150;  // Zone TF: bars scanned for FVGs
input int    InpZoneMaxAgeBars = 96;   // IFVG valid this many zone-TF bars after inversion
input double InpMinZonePoints  = 0;    // Min IFVG height in points (0 = off)
input double InpMaxZonePoints  = 0;    // Max IFVG height in points (0 = off)

//=================== INPUTS: swing + trigger ======================
input int InpSwingStrength    = 2;    // Swing TF: fractal strength (bars each side)
input int InpM5Lookback       = 600;  // Swing TF: bars scanned for pivots (auto-extended if needed)
input int InpSetupTimeoutMin  = 240;  // Setup expires this many minutes after the tap
input int InpM1ScanMinutes    = 720;  // Entry TF: minutes of history scanned for triggers
input int InpMaxTradesPerZone = 1;    // Max signals per IFVG zone
input int InpSignalCooldownMin = 10;  // Min minutes between two signals (anti-duplicate)

//=================== INPUTS: risk =================================
input ENUM_SL_MODE InpSLMode         = SL_SWING;  // Stop loss placement
input double       InpSLBufferPoints = 10;        // SL buffer (points)
input ENUM_TP_MODE InpTPMode         = TP_RR;     // Take profit mode
input double       InpRiskReward     = 2.0;       // TP = RR x risk
input double       InpTPPoints       = 200;       // TP fixed points (fixed mode)

//=================== INPUTS: alerts ===============================
input bool   InpAlertPopup  = true;         // Popup alert
input bool   InpAlertPush   = false;        // Push notification
input bool   InpAlertEmail  = false;        // Email
input bool   InpAlertSound  = true;         // Sound
input string InpSoundFile   = "alert.wav";  // Sound file
input bool   InpStageAlerts = true;         // Also alert bias / zone / tap / swing stages

//=================== INPUTS: visuals ==============================
input bool  InpDrawH1             = true;          // Draw bias-TF FVG boxes
input int   InpH1FVGsToDraw      = 5;             // How many bias-TF FVGs to draw
input bool  InpDrawZones         = true;          // Draw M30 IFVG zones
input bool  InpShowPanel         = true;          // Show dashboard panel
input int   InpPanelX            = 12;            // Panel X offset
input int   InpPanelY            = 22;            // Panel Y offset
input color InpBullColor         = clrDodgerBlue; // Bullish color
input color InpBearColor         = clrOrangeRed;  // Bearish color
input int   InpArrowOffsetPoints = 15;            // Arrow offset (points)
input bool  InpHistorySignals    = true;          // Draw historical signals on load
input int   InpHistoryBars       = 300;           // Entry-TF bars back for history signals

//=================== STRUCTS ======================================
// FVG: dir +1 = bullish gap, -1 = bearish gap (3-candle imbalance)
struct SFVG
  {
   datetime created;      // time of 3rd candle (FVG confirmed at its close)
   int      dir;          // +1 bullish / -1 bearish
   double   top;          // upper bound of the gap
   double   bottom;       // lower bound of the gap
   datetime t_mit;        // first touch of the zone (0 = none)
   datetime t_inv;        // first CLOSE beyond the far side = invalidation (0 = none)
   datetime t_retest;     // after inversion: first return into the zone
   datetime t_break;      // after inversion: first close beyond protective side
  };
// swing pivot on the swing TF
struct SPivot
  {
   datetime time;         // time of the pivot bar
   double   price;        // pivot price
   datetime confirmed;    // time the pivot got confirmed (strength bars later)
  };
// full cascade state at a given moment
struct SState
  {
   int      bias;         // +1 bull / -1 bear / 0 undefined
   int      bullInv;      // count: bullish FVGs invalidated in window (bearish events)
   int      bearInv;      // count: bearish FVGs invalidated in window (bullish events)
   datetime biasEvTime;   // time of the latest invalidation event
   int      biasEvDir;    // direction of the FVG of that latest event
   int      zi;           // index in gM30 of the ACTIVE (tapped) zone, -1 = none
   int      zw;           // index in gM30 of the WAITING (untapped) zone, -1 = none
   datetime tapTime;      // time price first tapped the active zone (entry TF)
   int      pi;           // index in gPivLo/gPivHi of the swing pivot, -1 = none
   double   swingExt;     // lowest low / highest high since the tap (entry TF)
   int      ti;           // index in gM1 of the candidate trigger FVG, -1 = none
   int      sigDir;       // signal at this bar: +1 buy / -1 sell / 0 none
   int      sigTrig;      // index in gM1 of the trigger FVG that fired
   datetime sigT;         // bar time of the fired trigger (entry bar)
   double   entry;
   double   sl;
   double   tp;
   string   status;       // human readable state
  };
// last signal tracker
struct SSignal
  {
   bool     valid;
   int      dir;
   datetime t;
   double   entry;
   double   sl;
   double   tp;
   int      result;       // 0 open / +1 TP hit / -1 SL hit
   datetime closeT;
  };

//=================== GLOBALS ======================================
SFVG    gH1[];              // bias TF FVGs
SFVG    gM30[];             // zone TF FVGs
SFVG    gM1[];              // entry TF FVGs
SPivot  gPivLo[];           // swing TF low pivots
SPivot  gPivHi[];           // swing TF high pivots
double  BufBuy[];
double  BufSell[];
datetime gLastClosed  = 0;  // last processed closed entry-TF bar time
int     gPrevBias     = 0;  // last bias direction alerted (live only)
bool    gNeedRebuild  = false;
datetime gLastSigTrigT = 0; // trigger time of the last fired signal (cooldown)
string  gFired[];           // dedup keys for alerts / signals
SSignal gSig;               // last signal

//=================== SMALL HELPERS ================================
int IMin(int a, int b) { return (a < b ? a : b); }
int IMax(int a, int b) { return (a > b ? a : b); }
int TFSec(int tf)      { return (tf * 60); }

string TFName(int tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return ("M1");
      case PERIOD_M5:  return ("M5");
      case PERIOD_M15: return ("M15");
      case PERIOD_M30: return ("M30");
      case PERIOD_H1:  return ("H1");
      case PERIOD_H4:  return ("H4");
      case PERIOD_D1:  return ("D1");
     }
   return ("TF" + IntegerToString(tf));
  }

string P2S(double p) { return (DoubleToString(p, Digits)); }
double PipPts()      { return ((Digits == 3 || Digits == 5) ? 10.0 : 1.0); }
string PipsStr(double priceDiff)
  {
   return (DoubleToString(priceDiff / Point / PipPts(), 1) + " pips");
  }
string ShortTime(datetime t)
  {
   if(t <= 0) return ("--");
   return (StringSubstr(TimeToString(t, TIME_DATE | TIME_MINUTES), 5));
  }

//=================== EVENT KEY STORE ==============================
bool KeyFired(string key)
  {
   for(int i = 0; i < ArraySize(gFired); i++)
      if(gFired[i] == key) return (true);
   return (false);
  }
void FireKey(string key)
  {
   if(KeyFired(key)) return;
   int n = ArraySize(gFired);
   ArrayResize(gFired, n + 1);
   gFired[n] = key;
  }
int CountKeyPrefix(string pfx)
  {
   int c = 0;
   for(int i = 0; i < ArraySize(gFired); i++)
      if(StringFind(gFired[i], pfx) == 0) c++;
   return (c);
  }

//=================== NOTIFY =======================================
void Notify(string msg)
  {
   msg = "FVG-Cascade [" + Symbol() + "] " + msg;
   if(InpAlertPopup) Alert(msg);
   if(InpAlertPush)  SendNotification(msg);
   if(InpAlertEmail) SendMail("FVG Cascade " + Symbol(), msg);
   if(InpAlertSound) PlaySound(InpSoundFile);
  }
// stage events (bias / zone / tap / swing): alert only when live,
// but always mark the key so a restart does not re-alert old stages.
void StageEvent(string key, string msg, bool live)
  {
   if(KeyFired(key)) return;
   FireKey(key);
   if(live && InpStageAlerts) Notify(msg);
  }

//=================== OBJECT HELPERS ===============================
void DelObj(string name)
  {
   if(ObjectFind(name) >= 0) ObjectDelete(name);
  }
void SetRect(string name, datetime t1, double p1, datetime t2, double p2,
             color c, bool back, string txt)
  {
   DelObj(name);
   ObjectCreate(name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSet(name, OBJPROP_COLOR, c);
   ObjectSet(name, OBJPROP_BACK, back);
   ObjectSet(name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetText(name, txt, 8, "Arial", c);
  }
void SetArrowObj(string name, datetime t, double p, int code, color c)
  {
   DelObj(name);
   ObjectCreate(name, OBJ_ARROW, 0, t, p);
   ObjectSet(name, OBJPROP_ARROWCODE, code);
   ObjectSet(name, OBJPROP_COLOR, c);
   ObjectSet(name, OBJPROP_WIDTH, 2);
   ObjectSetText(name, "FVG Cascade", 8, "Arial", c);
  }
void SetTrendLine(string name, datetime t1, double p1, datetime t2, double p2,
                  color c, int style, bool ray)
  {
   DelObj(name);
   ObjectCreate(name, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSet(name, OBJPROP_COLOR, c);
   ObjectSet(name, OBJPROP_STYLE, style);
   ObjectSet(name, OBJPROP_RAY, ray);
   ObjectSet(name, OBJPROP_WIDTH, 1);
   ObjectSet(name, OBJPROP_BACK, true);
  }
void PlaceText(string name, datetime t, double p, string txt, color c)
  {
   DelObj(name);
   ObjectCreate(name, OBJ_TEXT, 0, t, p);
   ObjectSetText(name, txt, 8, "Arial", c);
  }
void SetLabel(string name, int x, int y, string txt, color c, int size)
  {
   DelObj(name);
   ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
   ObjectSet(name, OBJPROP_CORNER, 0);
   ObjectSet(name, OBJPROP_XDISTANCE, x);
   ObjectSet(name, OBJPROP_YDISTANCE, y);
   ObjectSetText(name, txt, size, "Consolas", c);
  }
void CleanupObjects()
  {
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string nm = ObjectName(i);
      if(StringFind(nm, "FVGC_") == 0) ObjectDelete(nm);
     }
  }

//=================== DATA BUILDERS ================================
// Scan a timeframe for 3-candle FVGs and their events.
// Events are computed on CLOSED bars only (shift >= 1) -> deterministic,
// no repaint. Arrays come back ordered oldest -> newest.
void BuildFVGs(int tf, int lookback, datetime minCreated, SFVG &out[])
  {
   ArrayResize(out, 0);
   int bars = iBars(Symbol(), tf);
   if(bars < 10) return;

   int n = lookback;
   if(n > bars - 3) n = bars - 3;

   for(int s = n; s >= 1; s--)
     {
      double hiNew = iHigh(Symbol(), tf, s);
      double loNew = iLow(Symbol(), tf, s);
      double hiOld = iHigh(Symbol(), tf, s + 2);
      double loOld = iLow(Symbol(), tf, s + 2);
      datetime tc  = iTime(Symbol(), tf, s);
      if(tc <= 0) continue;
      if(tc < minCreated) continue;

      int dir = 0;
      double top = 0.0, bot = 0.0;
      if(loNew > hiOld)      { dir =  1; bot = hiOld; top = loNew; }  // bullish FVG
      else if(hiNew < loOld) { dir = -1; bot = hiNew; top = loOld; }  // bearish FVG
      if(dir == 0) continue;

      SFVG f;
      f.created = tc; f.dir = dir; f.top = top; f.bottom = bot;
      f.t_mit = 0; f.t_inv = 0; f.t_retest = 0; f.t_break = 0;

      //--- raw events: first mitigation (touch) and first invalidation (close beyond)
      bool mit = false, inv = false;
      for(int k = s - 1; k >= 1; k--)
        {
         double kh = iHigh(Symbol(), tf, k);
         double kl = iLow(Symbol(), tf, k);
         double kc = iClose(Symbol(), tf, k);
         datetime kt = iTime(Symbol(), tf, k);
         if(!mit)
           {
            if(dir > 0 && kl <= top) { f.t_mit = kt; mit = true; }
            if(dir < 0 && kh >= bot) { f.t_mit = kt; mit = true; }
           }
         if(!inv)
           {
            if(dir > 0 && kc < bot) { f.t_inv = kt; inv = true; }
            if(dir < 0 && kc > top) { f.t_inv = kt; inv = true; }
           }
         if(mit && inv) break;
        }

      //--- post-inversion behaviour (this FVG has become an inversion FVG)
      //    dir +1 inverted -> bearish IFVG resistance : retest = high>=bottom, break = close>top
      //    dir -1 inverted -> bullish IFVG support    : retest = low<=top,   break = close<bottom
      if(inv)
        {
         bool rt = false, br = false;
         for(int k2 = s - 1; k2 >= 1; k2--)
           {
            datetime kt = iTime(Symbol(), tf, k2);
            if(kt <= f.t_inv) continue;
            double kh = iHigh(Symbol(), tf, k2);
            double kl = iLow(Symbol(), tf, k2);
            double kc = iClose(Symbol(), tf, k2);
            if(!rt)
              {
               if(dir > 0 && kh >= bot) { f.t_retest = kt; rt = true; }
               if(dir < 0 && kl <= top) { f.t_retest = kt; rt = true; }
              }
            if(!br)
              {
               if(dir > 0 && kc > top) { f.t_break = kt; br = true; }
               if(dir < 0 && kc < bot) { f.t_break = kt; br = true; }
              }
            if(rt && br) break;
           }
        }

      int sz = ArraySize(out);
      ArrayResize(out, sz + 1);
      out[sz] = f;
     }
  }

// Scan the swing TF for confirmed fractal pivots (oldest -> newest).
void BuildPivots(int tf, int lookback, int strength, SPivot &lo[], SPivot &hi[])
  {
   ArrayResize(lo, 0);
   ArrayResize(hi, 0);
   int bars = iBars(Symbol(), tf);
   if(bars < strength * 2 + 5) return;

   int n = lookback;
   if(n > bars - strength - 1) n = bars - strength - 1;

   for(int s = n; s >= strength + 1; s--)
     {
      double l = iLow(Symbol(), tf, s);
      double h = iHigh(Symbol(), tf, s);
      bool isLo = true, isHi = true;
      for(int j = 1; j <= strength; j++)
        {
         if(l > iLow(Symbol(), tf, s - j) || l >= iLow(Symbol(), tf, s + j))  isLo = false;
         if(h < iHigh(Symbol(), tf, s - j) || h <= iHigh(Symbol(), tf, s + j)) isHi = false;
         if(!isLo && !isHi) break;
        }
      if(isLo)
        {
         int k = ArraySize(lo);
         ArrayResize(lo, k + 1);
         lo[k].time = iTime(Symbol(), tf, s);
         lo[k].price = l;
         lo[k].confirmed = iTime(Symbol(), tf, s - strength) + TFSec(tf);
        }
      if(isHi)
        {
         int k2 = ArraySize(hi);
         ArrayResize(hi, k2 + 1);
         hi[k2].time = iTime(Symbol(), tf, s);
         hi[k2].price = h;
         hi[k2].confirmed = iTime(Symbol(), tf, s - strength) + TFSec(tf);
        }
     }
  }

// Build everything once per closed entry-TF bar.
void BuildAll()
  {
   datetime nowT = TimeCurrent();

   // auto-keep scan windows consistent with history settings
   int scanMin    = IMax(InpM1ScanMinutes, InpHistoryBars + InpSetupTimeoutMin + 60);
   int zoneAgeMin = InpZoneMaxAgeBars * TFSec(InpZoneTF) / 60;
   int effH1  = IMax(InpH1Lookback, InpBiasWindowBars + InpBiasMaxAgeBars + 30);
   int effM30 = IMax(InpM30Lookback, InpZoneMaxAgeBars + 30);
   int effM5  = IMax(InpM5Lookback, (scanMin + zoneAgeMin + 120) * 60 / TFSec(InpSwingTF));

   BuildFVGs(InpBiasTF, effH1, 0, gH1);
   BuildFVGs(InpZoneTF, effM30, 0, gM30);

   int m1lb = scanMin + 60;
   int m1bars = iBars(Symbol(), InpEntryTF);
   if(m1lb > m1bars - 3) m1lb = m1bars - 3;
   if(m1lb < 10) m1lb = 10;
   BuildFVGs(InpEntryTF, m1lb, nowT - scanMin * 60, gM1);

   int m5bars = iBars(Symbol(), InpSwingTF);
   int m5lb = effM5;
   if(m5lb > m5bars - InpSwingStrength - 1) m5lb = m5bars - InpSwingStrength - 1;
   if(m5lb < 10) m5lb = 10;
   BuildPivots(InpSwingTF, m5lb, InpSwingStrength, gPivLo, gPivHi);
  }

//=================== STEP 1: BIAS =================================
// Bias = direction of the LATEST FVG invalidation event on the bias TF.
//   bearish FVG invalidated (closed above)  -> bullish bias (+1)
//   bullish FVG invalidated (closed below)  -> bearish bias (-1)
int BiasAt(datetime t, SState &st)
  {
   st.bullInv = 0; st.bearInv = 0; st.biasEvTime = 0; st.biasEvDir = 0;

   datetime winStart = t - InpBiasWindowBars * TFSec(InpBiasTF);
   datetime best = 0;
   int bestDir = 0;

   for(int i = 0; i < ArraySize(gH1); i++)
     {
      datetime ti = gH1[i].t_inv;
      if(ti <= 0 || ti > t) continue;
      if(ti >= winStart)
        {
         if(gH1[i].dir > 0) st.bullInv++;
         else               st.bearInv++;
        }
      if(ti > best) { best = ti; bestDir = gH1[i].dir; }
     }

   if(best == 0) return (0);
   if((int)(t - best) > InpBiasMaxAgeBars * TFSec(InpBiasTF)) return (0);

   int bias = (bestDir > 0 ? -1 : 1);

   // optional confirmation: enough events of the implying type inside the window
   int implying = (bias > 0 ? st.bearInv : st.bullInv);
   if(implying < InpBiasMinEvents) return (0);

   st.biasEvTime = best;
   st.biasEvDir = bestDir;
   return (bias);
  }

//=================== STEP 2: ZONES ================================
// First time price trades back into the inverted zone (entry-TF granularity),
// strictly AFTER the invalidating zone-TF bar has closed.
datetime TapTime(datetime tInv, double zTop, double zBottom, int bias, datetime t)
  {
   datetime from = tInv + TFSec(InpZoneTF);
   if(from >= t) return (0);
   int sFrom = iBarShift(Symbol(), InpEntryTF, from, false);
   int sTo   = iBarShift(Symbol(), InpEntryTF, t, false);
   if(sFrom < 0 || sTo < 0) return (0);
   for(int s = sFrom; s >= sTo; s--)
     {
      if(bias > 0) { if(iLow(Symbol(), InpEntryTF, s) <= zTop)    return (iTime(Symbol(), InpEntryTF, s)); }
      else         { if(iHigh(Symbol(), InpEntryTF, s) >= zBottom) return (iTime(Symbol(), InpEntryTF, s)); }
     }
   return (0);
  }

// Setup death: a swing-TF candle CLOSES beyond the protective side of the
// zone after the tap (only closed swing-TF bars count, the forming one is skipped).
bool ZoneBrokenSwing(int bias, datetime tap, datetime t, double zTop, double zBottom)
  {
   int sFrom = iBarShift(Symbol(), InpSwingTF, tap, false);
   int sTo   = iBarShift(Symbol(), InpSwingTF, t, false) + 1; // exclude bar still forming at t
   if(sFrom < 0 || sTo < 0) return (false);
   for(int s = sFrom; s >= sTo; s--)
     {
      double c = iClose(Symbol(), InpSwingTF, s);
      if(bias > 0 && c < zBottom) return (true);
      if(bias < 0 && c > zTop)    return (true);
     }
   return (false);
  }

// Pick the active (tapped, alive, not consumed) IFVG and the next waiting one.
//   bullish bias -> zones come from bearish FVGs inverted upward   (support)
//   bearish bias -> zones come from bullish FVGs inverted downward (resistance)
void PickZones(int bias, datetime t, double px, int &zi, int &zw, datetime &ziTap)
  {
   zi = -1; zw = -1; ziTap = 0;
   datetime bestTap = 0;
   double bestDist = 1.0e100;
   int n = ArraySize(gM30);

   for(int i = n - 1; i >= 0; i--)
     {
      if(gM30[i].dir != -bias) continue;                       // direction must match the bias
      if(gM30[i].t_inv <= 0 || gM30[i].t_inv > t) continue;    // must be inverted by t
      if(gM30[i].t_break > 0 && gM30[i].t_break <= t) continue;// zone structurally broken
      if((int)(t - gM30[i].t_inv) > InpZoneMaxAgeBars * TFSec(InpZoneTF)) continue; // too old
      double h = gM30[i].top - gM30[i].bottom;
      if(InpMinZonePoints > 0 && h < InpMinZonePoints * Point) continue;
      if(InpMaxZonePoints > 0 && h > InpMaxZonePoints * Point) continue;
      // fully traded on this zone already?
      if(CountKeyPrefix("SIG|" + IntegerToString((int)gM30[i].created) + "|") >= InpMaxTradesPerZone)
         continue;

      datetime tap = TapTime(gM30[i].t_inv, gM30[i].top, gM30[i].bottom, bias, t);
      if(tap > 0)
        {
         if((int)(t - tap) <= InpSetupTimeoutMin * 60)          // setup still fresh
           {
            if(tap > bestTap) { bestTap = tap; zi = i; ziTap = tap; }
           }
        }
      else // not tapped yet -> candidate waiting zone on the correct side of price
        {
         if(bias > 0 && gM30[i].top < px)
           {
            double d = px - gM30[i].top;
            if(d < bestDist) { bestDist = d; zw = i; }
           }
         else if(bias < 0 && gM30[i].bottom > px)
           {
            double d = gM30[i].bottom - px;
            if(d < bestDist) { bestDist = d; zw = i; }
           }
        }
     }
  }

//=================== STEP 3: SWING ================================
// lowest low / highest high since the tap, entry-TF granularity (closed bars)
double ExtremumSince(int tf, datetime from, datetime to, bool lowSide)
  {
   int a = iBarShift(Symbol(), tf, from, false);
   int b = iBarShift(Symbol(), tf, to, false);
   if(a < 0 || b < 0) return (0);
   if(a < b) { int tmp = a; a = b; b = tmp; }
   double best;
   if(lowSide)
     {
      best = iLow(Symbol(), tf, a);
      for(int s = a - 1; s >= b; s--)
        {
         double v = iLow(Symbol(), tf, s);
         if(v < best) best = v;
        }
     }
   else
     {
      best = iHigh(Symbol(), tf, a);
      for(int s = a - 1; s >= b; s--)
        {
         double v = iHigh(Symbol(), tf, s);
         if(v > best) best = v;
        }
     }
   return (best);
  }

// latest CONFIRMED swing-TF pivot after the tap (buy -> low pivot, sell -> high pivot)
int LastPivotIdx(int bias, datetime tap, datetime t)
  {
   if(bias > 0)
     {
      for(int i = ArraySize(gPivLo) - 1; i >= 0; i--)
         if(gPivLo[i].time > tap && gPivLo[i].confirmed <= t) return (i);
     }
   else
     {
      for(int j = ArraySize(gPivHi) - 1; j >= 0; j--)
         if(gPivHi[j].time > tap && gPivHi[j].confirmed <= t) return (j);
     }
   return (-1);
  }

//=================== STEP 4: TRIGGER ==============================
// candidate trigger FVG for display: latest opposite-side entry-TF FVG
// created after the tap and still alive
int CandTriggerIdx(int bias, datetime tap, datetime t)
  {
   for(int i = ArraySize(gM1) - 1; i >= 0; i--)
     {
      if(gM1[i].created <= tap || gM1[i].created > t) continue;
      if(bias > 0 && gM1[i].dir >= 0) continue;   // buy needs a bearish FVG
      if(bias < 0 && gM1[i].dir <= 0) continue;   // sell needs a bullish FVG
      if(gM1[i].t_inv > 0 && gM1[i].t_inv <= t) continue;
      return (i);
     }
   return (-1);
  }

// The trigger that fires the setup: an opposite-side entry-TF FVG created
// after the tap, invalidated by a closing candle that happens AFTER the swing
// pivot bar has closed and no later than the evaluated bar t. Because the
// pivot only becomes visible "strength" bars later, the trigger may be
// detected a few bars after it actually fired - the entry is then reported
// on the trigger's own bar.
int FindFiredTrigger(int bias, datetime tap, datetime pivotT, datetime t)
  {
   datetime pivotBarClose = pivotT + TFSec(InpSwingTF);
   for(int i = ArraySize(gM1) - 1; i >= 0; i--)
     {
      if(gM1[i].created <= tap || gM1[i].created > t) continue;
      if(bias > 0 && gM1[i].dir >= 0) continue;
      if(bias < 0 && gM1[i].dir <= 0) continue;
      if(gM1[i].t_inv <= 0) continue;              // not invalidated (yet)
      if(gM1[i].t_inv < pivotBarClose) continue;   // must fire after the pivot bar closed
      if(gM1[i].t_inv > t) continue;               // not yet at evaluation time
      return (i);
     }
   return (-1);
  }

//=================== FULL CASCADE EVALUATION ======================
// Pure function of time t (a closed entry-TF bar): rebuilds the whole
// cascade state as it was at t. live=true only controls alerts.
void EvalState(datetime t, bool live, SState &st)
  {
   st.bias = 0; st.bullInv = 0; st.bearInv = 0; st.biasEvTime = 0; st.biasEvDir = 0;
   st.zi = -1; st.zw = -1; st.tapTime = 0; st.pi = -1; st.swingExt = 0;
   st.ti = -1; st.sigDir = 0; st.sigTrig = -1; st.sigT = 0; st.entry = 0; st.sl = 0; st.tp = 0;
   st.status = "WAIT: " + TFName(InpBiasTF) + " bias undefined (no fresh FVG invalidation)";

   //--- STEP 1: bias
   int b = BiasAt(t, st);
   if(b == 0) return;
   st.bias = b;

   if(live && b != gPrevBias)
     {
      gPrevBias = b;
      if(InpStageAlerts)
         Notify(TFName(InpBiasTF) + " bias: " + (b > 0 ? "BULLISH" : "BEARISH") +
                " (last invalidated: " + (st.biasEvDir > 0 ? "bullish" : "bearish") + " FVG @ " + ShortTime(st.biasEvTime) +
                " | " + IntegerToString(InpBiasWindowBars) + " bars: " +
                IntegerToString(st.bearInv) + " bear-inv / " + IntegerToString(st.bullInv) + " bull-inv)");
     }

   int shiftT = iBarShift(Symbol(), InpEntryTF, t, false);
   if(shiftT < 0) return;
   double px = iClose(Symbol(), InpEntryTF, shiftT);

   //--- STEP 2: zone
   int ziL = -1, zwL = -1;
   datetime tapL = 0;
   PickZones(b, t, px, ziL, zwL, tapL);
   st.zi = ziL;
   st.zw = zwL;

   if(st.zw >= 0)
      StageEvent("ZONE|" + IntegerToString((int)gM30[st.zw].created),
                 "New " + TFName(InpZoneTF) + " IFVG " + (b > 0 ? "bullish (support)" : "bearish (resistance)") +
                 " " + P2S(gM30[st.zw].bottom) + ".." + P2S(gM30[st.zw].top) + " - waiting price tap", live);

   if(st.zi < 0)
     {
      if(st.zw >= 0)
         st.status = "WAIT: price to tap the IFVG " + P2S(gM30[st.zw].bottom) + ".." + P2S(gM30[st.zw].top);
      else
         st.status = "WAIT: a fresh " + TFName(InpZoneTF) + " IFVG matching the bias";
      return;
     }

   double   zTop = gM30[st.zi].top;
   double   zBottom = gM30[st.zi].bottom;
   datetime zCreated = gM30[st.zi].created;
   st.tapTime = tapL;

   StageEvent("TAP|" + IntegerToString((int)zCreated),
              "Price tapped " + TFName(InpZoneTF) + " IFVG " + P2S(zBottom) + ".." + P2S(zTop) +
              " - waiting " + TFName(InpSwingTF) + " " + (b > 0 ? "LOW" : "HIGH"), live);

   // setup death check: swing-TF close beyond the protective side after the tap
   if(ZoneBrokenSwing(b, st.tapTime, t, zTop, zBottom))
     {
      st.status = "DEAD: zone broken after tap - waiting new setup";
      return;
     }

   //--- STEP 3: swing
   st.swingExt = ExtremumSince(InpEntryTF, st.tapTime, t, b > 0);
   st.pi = LastPivotIdx(b, st.tapTime, t);
   if(st.pi < 0)
     {
      st.status = "WAIT: " + TFName(InpSwingTF) + " " + (b > 0 ? "LOW" : "HIGH") + " after the tap";
      return;
     }

   datetime pt = (b > 0 ? gPivLo[st.pi].time : gPivHi[st.pi].time);
   double   pp = (b > 0 ? gPivLo[st.pi].price : gPivHi[st.pi].price);

   StageEvent("SWING|" + IntegerToString((int)pt),
              TFName(InpSwingTF) + " swing " + (b > 0 ? "LOW" : "HIGH") + " @ " + P2S(pp) +
              " - waiting " + TFName(InpEntryTF) + " " + (b > 0 ? "bearish" : "bullish") + " FVG invalidation", live);

   //--- STEP 4: trigger
   st.ti = CandTriggerIdx(b, st.tapTime, t);
   int ft = FindFiredTrigger(b, st.tapTime, pt, t);

   if(ft >= 0)
     {
      string sigKey = "SIG|" + IntegerToString((int)zCreated) + "|" + IntegerToString((int)gM1[ft].created);
      int eShift = iBarShift(Symbol(), InpEntryTF, gM1[ft].t_inv, false);
      if(eShift < 0) eShift = shiftT;
      double entry = iClose(Symbol(), InpEntryTF, eShift);
      double buf = InpSLBufferPoints * Point;
      double sl = 0;

      if(InpSLMode == SL_ZONE)     sl = (b > 0 ? zBottom - buf : zTop + buf);
      else if(InpSLMode == SL_FVG) sl = (b > 0 ? gM1[ft].bottom - buf : gM1[ft].top + buf);
      else                         sl = (b > 0 ? st.swingExt - buf : st.swingExt + buf);

      if(b > 0)
        {
         if(sl >= entry) sl = st.swingExt - buf;
         if(sl >= entry) sl = zBottom - buf;
         if(sl >= entry) sl = entry - 50 * Point;
        }
      else
        {
         if(sl <= entry) sl = st.swingExt + buf;
         if(sl <= entry) sl = zTop + buf;
         if(sl <= entry) sl = entry + 50 * Point;
        }

      double risk = MathAbs(entry - sl);
      if(risk >= Point)
        {
         double tp;
         if(InpTPMode == TP_FIXED) tp = (b > 0 ? entry + InpTPPoints * Point : entry - InpTPPoints * Point);
         else                      tp = (b > 0 ? entry + InpRiskReward * risk : entry - InpRiskReward * risk);

         bool alreadyFired = KeyFired(sigKey);
         bool inCooldown = (!alreadyFired && gLastSigTrigT > 0 &&
                            MathAbs((int)(gM1[ft].t_inv - gLastSigTrigT)) < InpSignalCooldownMin * 60);

         if(alreadyFired || !inCooldown)
           {
            st.sigDir = b;
            st.sigTrig = ft;
            st.sigT = gM1[ft].t_inv;
            st.entry = entry;
            st.sl = sl;
            st.tp = tp;
            st.status = (b > 0 ? "NEW SIGNAL: BUY" : "NEW SIGNAL: SELL") + " @ " + P2S(entry) +
                        " SL " + P2S(sl) + " TP " + P2S(tp);

            if(!alreadyFired)
              {
               FireKey(sigKey);
               gLastSigTrigT = gM1[ft].t_inv;
               gSig.valid = true; gSig.dir = b; gSig.t = st.sigT;
               gSig.entry = entry; gSig.sl = sl; gSig.tp = tp;
               gSig.result = 0; gSig.closeT = 0;
               if(live)
                  Notify((b > 0 ? "BUY" : "SELL") + " " + Symbol() + " @ " + P2S(entry) +
                         " | SL " + P2S(sl) + " | TP " + P2S(tp) +
                         " | risk " + PipsStr(risk) +
                         " | " + TFName(InpBiasTF) + " bias " + (b > 0 ? "BULL" : "BEAR") +
                         " | zone " + P2S(zBottom) + ".." + P2S(zTop) +
                         " | " + TFName(InpSwingTF) + " " + (b > 0 ? "low" : "high") + " " + P2S(st.swingExt) +
                         " | " + TFName(InpEntryTF) + " " + (b > 0 ? "bearish" : "bullish") + " FVG invalidated");
              }
            return;
           }

         st.status = "SKIP: duplicate trigger inside cooldown window";
         return;
        }
     }

   //--- still waiting for the M1 trigger
   if(st.ti >= 0)
     {
      if(b > 0) st.status = "WAIT: " + TFName(InpEntryTF) + " close > " + P2S(gM1[st.ti].top) + " (bearish FVG)";
      else      st.status = "WAIT: " + TFName(InpEntryTF) + " close < " + P2S(gM1[st.ti].bottom) + " (bullish FVG)";
     }
   else
      st.status = "WAIT: " + (b > 0 ? "bearish" : "bullish") + " " + TFName(InpEntryTF) + " FVG to form";
  }

//=================== SIGNAL TRACKING ==============================
void UpdateOutcome()
  {
   if(!gSig.valid || gSig.result != 0) return;
   int sSig = iBarShift(Symbol(), InpEntryTF, gSig.t, false);
   if(sSig < 0) return;
   for(int s = sSig - 1; s >= 1; s--)
     {
      double h = iHigh(Symbol(), InpEntryTF, s);
      double l = iLow(Symbol(), InpEntryTF, s);
      if(gSig.dir > 0)
        {
         if(l <= gSig.sl) { gSig.result = -1; gSig.closeT = iTime(Symbol(), InpEntryTF, s); return; }
         if(h >= gSig.tp) { gSig.result =  1; gSig.closeT = iTime(Symbol(), InpEntryTF, s); return; }
        }
      else
        {
         if(h >= gSig.sl) { gSig.result = -1; gSig.closeT = iTime(Symbol(), InpEntryTF, s); return; }
         if(l <= gSig.tp) { gSig.result =  1; gSig.closeT = iTime(Symbol(), InpEntryTF, s); return; }
        }
     }
  }

// signal arrows are drawn through the indicator buffers so they persist
void DrawSignalArrow(int dir, datetime t)
  {
   int cshift = iBarShift(Symbol(), 0, t, false);
   if(cshift < 0 || cshift >= ArraySize(BufBuy)) return;
   int eshift = iBarShift(Symbol(), InpEntryTF, t, false);
   if(eshift < 0) return;
   if(dir > 0) BufBuy[cshift]  = iLow(Symbol(), InpEntryTF, eshift)  - InpArrowOffsetPoints * Point;
   else        BufSell[cshift] = iHigh(Symbol(), InpEntryTF, eshift) + InpArrowOffsetPoints * Point;
  }

//=================== HISTORY PASS =================================
// Replays the cascade over recent closed entry-TF bars so past signals
// appear on the chart (no alerts) and alert keys get pre-marked.
void RunHistoryPass()
  {
   int bars = iBars(Symbol(), InpEntryTF);
   int hIdx = InpHistoryBars;
   if(hIdx > bars - 2) hIdx = bars - 2;
   for(int nb = hIdx; nb >= 2; nb--)
     {
      datetime t = iTime(Symbol(), InpEntryTF, nb);
      if(t <= 0) continue;
      SState st;
      EvalState(t, false, st);
      if(st.sigDir != 0) DrawSignalArrow(st.sigDir, (st.sigT > 0 ? st.sigT : t));
     }
  }

//=================== DRAWING ======================================
void DrawPanel(SState &st)
  {
   int x = InpPanelX;
   int y = InpPanelY;
   int dy = 15;
   int r = 0;

   string chain = TFName(InpBiasTF) + " > " + TFName(InpZoneTF) + " > " +
                  TFName(InpSwingTF) + " > " + TFName(InpEntryTF);
   SetLabel("FVGC_P0", x, y + dy * r, "FVG CASCADE  " + Symbol() + "  [" + chain + "]", clrWhite, 10);
   r++;

   //--- 1) bias
   string r1;
   color  c1 = clrSilver;
   if(st.bias == 0)
      r1 = "1) " + TFName(InpBiasTF) + " bias: UNDEFINED (no fresh FVG invalidation)";
   else
     {
      r1 = "1) " + TFName(InpBiasTF) + " bias: " + (st.bias > 0 ? "BULLISH" : "BEARISH") +
           "  (last: " + (st.biasEvDir > 0 ? "bull" : "bear") + " FVG invalidated " + ShortTime(st.biasEvTime) +
           " | " + IntegerToString(InpBiasWindowBars) + " bars: " +
           IntegerToString(st.bearInv) + " bear-inv / " + IntegerToString(st.bullInv) + " bull-inv)";
      c1 = (st.bias > 0 ? InpBullColor : InpBearColor);
     }
   SetLabel("FVGC_P1", x, y + dy * r, r1, c1, 9);
   r++;

   //--- 2) zone
   string r2;
   color  c2 = clrSilver;
   if(st.zi >= 0)
     {
      int taken = CountKeyPrefix("SIG|" + IntegerToString((int)gM30[st.zi].created) + "|");
      r2 = "2) IFVG (active): " + P2S(gM30[st.zi].bottom) + ".." + P2S(gM30[st.zi].top) +
           "  inv " + ShortTime(gM30[st.zi].t_inv) + "  tap " + ShortTime(st.tapTime) +
           "  trades " + IntegerToString(taken) + "/" + IntegerToString(InpMaxTradesPerZone);
      c2 = (st.bias > 0 ? InpBullColor : InpBearColor);
     }
   else if(st.zw >= 0)
     {
      r2 = "2) IFVG (waiting tap): " + P2S(gM30[st.zw].bottom) + ".." + P2S(gM30[st.zw].top) +
           "  inv " + ShortTime(gM30[st.zw].t_inv);
      c2 = clrDarkGray;
     }
   else
      r2 = "2) IFVG: none matching bias yet - waiting";
   SetLabel("FVGC_P2", x, y + dy * r, r2, c2, 9);
   r++;

   //--- 3) swing
   string r3;
   if(st.zi >= 0 && st.pi >= 0)
     {
      if(st.bias > 0)
         r3 = "3) " + TFName(InpSwingTF) + " swing LOW @ " + P2S(gPivLo[st.pi].price) +
              " (" + ShortTime(gPivLo[st.pi].time) + ")  extreme " + P2S(st.swingExt);
      else
         r3 = "3) " + TFName(InpSwingTF) + " swing HIGH @ " + P2S(gPivHi[st.pi].price) +
              " (" + ShortTime(gPivHi[st.pi].time) + ")  extreme " + P2S(st.swingExt);
     }
   else if(st.zi >= 0)
      r3 = "3) waiting " + TFName(InpSwingTF) + " " + (st.bias > 0 ? "LOW" : "HIGH") + " after tap";
   else
      r3 = "3) -";
   SetLabel("FVGC_P3", x, y + dy * r, r3, clrSilver, 9);
   r++;

   //--- 4) trigger
   string r4;
   if(st.zi >= 0 && st.pi >= 0)
     {
      if(st.ti >= 0)
        {
         if(st.bias > 0)
            r4 = "4) waiting " + TFName(InpEntryTF) + " close > " + P2S(gM1[st.ti].top) +
                 "  (bear FVG " + P2S(gM1[st.ti].bottom) + ".." + P2S(gM1[st.ti].top) + ")";
         else
            r4 = "4) waiting " + TFName(InpEntryTF) + " close < " + P2S(gM1[st.ti].bottom) +
                 "  (bull FVG " + P2S(gM1[st.ti].bottom) + ".." + P2S(gM1[st.ti].top) + ")";
        }
      else
         r4 = "4) waiting " + (st.bias > 0 ? "bearish" : "bullish") + " " + TFName(InpEntryTF) + " FVG to form";
     }
   else
      r4 = "4) -";
   SetLabel("FVGC_P4", x, y + dy * r, r4, clrSilver, 9);
   r++;

   //--- state
   color c5 = clrGold;
   if(StringFind(st.status, "DEAD") == 0) c5 = clrGray;
   else if(StringFind(st.status, "NEW SIGNAL") == 0) c5 = (st.bias > 0 ? InpBullColor : InpBearColor);
   SetLabel("FVGC_P5", x, y + dy * r, "STATE: " + st.status, c5, 9);
   r++;

   //--- last signal
   string r6;
   color  c6 = clrSilver;
   if(gSig.valid)
     {
      string res;
      if(gSig.result > 0)      res = "WIN  +" + PipsStr(MathAbs(gSig.tp - gSig.entry));
      else if(gSig.result < 0) res = "LOSS -" + PipsStr(MathAbs(gSig.entry - gSig.sl));
      else
        {
         double fl = (gSig.dir > 0 ? Bid - gSig.entry : gSig.entry - Bid);
         res = "open " + (fl >= 0 ? "+" : "") + PipsStr(fl);
        }
      r6 = "Last signal: " + (gSig.dir > 0 ? "BUY" : "SELL") + " " + P2S(gSig.entry) +
           " SL " + P2S(gSig.sl) + " TP " + P2S(gSig.tp) + "  (" + ShortTime(gSig.t) + ")  " + res;
      c6 = (gSig.dir > 0 ? InpBullColor : InpBearColor);
     }
   else
      r6 = "Last signal: none yet";
   SetLabel("FVGC_P6", x, y + dy * r, r6, c6, 9);
   r++;
  }

void DrawAll(SState &st, datetime tLive)
  {
   CleanupObjects();

   datetime ext = tLive + TFSec(InpEntryTF) * 30; // extend zones 30 entry bars right

   //--- bias TF FVG boxes
   if(InpDrawH1)
     {
      int n = ArraySize(gH1);
      int biasIdx = -1;
      for(int i = 0; i < n; i++)
         if(gH1[i].t_inv > 0 && gH1[i].t_inv == st.biasEvTime && gH1[i].dir == st.biasEvDir)
           { biasIdx = i; break; }
      for(int k = 0; k < IMin(InpH1FVGsToDraw, n); k++)
        {
         int idx = n - 1 - k;
         datetime t2 = (gH1[idx].t_inv > 0 ? gH1[idx].t_inv : tLive + TFSec(InpBiasTF));
         color c = (idx == biasIdx) ? clrYellow :
                   (gH1[idx].t_inv > 0 ? clrDimGray : (gH1[idx].dir > 0 ? InpBullColor : InpBearColor));
         string d = TFName(InpBiasTF) + " " + (gH1[idx].dir > 0 ? "bullish" : "bearish") + " FVG" +
                    (gH1[idx].t_inv > 0 ? " (invalidated)" : "") +
                    (idx == biasIdx ? " [BIAS SETTER]" : "");
         SetRect("FVGC_H1_" + IntegerToString(k), gH1[idx].created, gH1[idx].top,
                 t2, gH1[idx].bottom, c, true, d);
        }
     }

   //--- zones / swing / trigger
   if(InpDrawZones)
     {
      if(st.zi >= 0)
        {
         color c = (st.bias > 0 ? InpBullColor : InpBearColor);
         SetRect("FVGC_ZONE", gM30[st.zi].t_inv, gM30[st.zi].top, ext, gM30[st.zi].bottom, c, true,
                 TFName(InpZoneTF) + " " + (st.bias > 0 ? "bullish" : "bearish") + " IFVG " +
                 P2S(gM30[st.zi].bottom) + ".." + P2S(gM30[st.zi].top) + " (trade zone)");
        }
      if(st.zw >= 0)
        {
         SetRect("FVGC_ZONEW", gM30[st.zw].t_inv, gM30[st.zw].top, ext, gM30[st.zw].bottom,
                 clrGray, true,
                 TFName(InpZoneTF) + " IFVG " + P2S(gM30[st.zw].bottom) + ".." +
                 P2S(gM30[st.zw].top) + " (waiting tap)");
        }
      if(st.zi >= 0 && st.pi >= 0)
        {
         if(st.bias > 0)
            SetArrowObj("FVGC_SWING", gPivLo[st.pi].time,
                        gPivLo[st.pi].price - InpArrowOffsetPoints * Point, 233, InpBullColor);
         else
            SetArrowObj("FVGC_SWING", gPivHi[st.pi].time,
                        gPivHi[st.pi].price + InpArrowOffsetPoints * Point, 234, InpBearColor);
        }
      if(st.ti >= 0)
        {
         color c = (gM1[st.ti].dir > 0 ? InpBullColor : InpBearColor);
         SetRect("FVGC_TRIG", gM1[st.ti].created, gM1[st.ti].top, ext, gM1[st.ti].bottom, c, true,
                 TFName(InpEntryTF) + " " + (gM1[st.ti].dir > 0 ? "bullish" : "bearish") +
                 " FVG (trigger)");
        }
     }

   //--- last signal SL / TP lines
   if(gSig.valid)
     {
      SetTrendLine("FVGC_SL", gSig.t, gSig.sl, ext, gSig.sl, clrOrangeRed, STYLE_SOLID, false);
      SetTrendLine("FVGC_TP", gSig.t, gSig.tp, ext, gSig.tp, clrAqua, STYLE_SOLID, false);
      PlaceText("FVGC_SLTX", ext, gSig.sl, "SL " + P2S(gSig.sl), clrOrangeRed);
      PlaceText("FVGC_TPTX", ext, gSig.tp, "TP " + P2S(gSig.tp), clrAqua);
     }

   //--- panel
   if(InpShowPanel) DrawPanel(st);

   WindowRedraw();
  }

void DrawWaitLabel()
  {
   SetLabel("FVGC_WAIT", InpPanelX, InpPanelY,
            "FVG Cascade: loading multi-timeframe data (" + TFName(InpBiasTF) + "/" +
            TFName(InpZoneTF) + "/" + TFName(InpSwingTF) + "/" + TFName(InpEntryTF) + ")...",
            clrGold, 9);
  }

//=================== DATA READINESS ===============================
bool DataReady()
  {
   if(iBars(Symbol(), InpEntryTF) < 60) return (false);
   if(iBars(Symbol(), InpSwingTF) < 60) return (false);
   if(iBars(Symbol(), InpZoneTF)  < 60) return (false);
   if(iBars(Symbol(), InpBiasTF)  < 60) return (false);
   if(iTime(Symbol(), InpBiasTF, 1)  <= 0) return (false);
   if(iTime(Symbol(), InpZoneTF, 1)  <= 0) return (false);
   if(iTime(Symbol(), InpEntryTF, 1) <= 0) return (false);
   return (true);
  }

//=================== MT4 EVENTS ===================================
int OnInit()
  {
   IndicatorBuffers(2);
   SetIndexBuffer(0, BufBuy);
   SetIndexBuffer(1, BufSell);
   SetIndexStyle(0, DRAW_ARROW, EMPTY, 2, InpBullColor);
   SetIndexStyle(1, DRAW_ARROW, EMPTY, 2, InpBearColor);
   SetIndexArrow(0, 233);
   SetIndexArrow(1, 234);
   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexLabel(0, "FVG Cascade BUY");
   SetIndexLabel(1, "FVG Cascade SELL");
   IndicatorShortName("FVG Cascade (" + TFName(InpBiasTF) + "/" + TFName(InpZoneTF) +
                      "/" + TFName(InpSwingTF) + "/" + TFName(InpEntryTF) + ")");
   IndicatorDigits(Digits);

   gLastClosed = 0;
   gPrevBias = 0;
   gNeedRebuild = false;
   gLastSigTrigT = 0;
   ArrayResize(gFired, 0);
   gSig.valid = false;
   gSig.result = 0;

   return (INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   CleanupObjects();
   WindowRedraw();
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
   if(rates_total < 20) return (rates_total);

   bool full = (prev_calculated <= 0);
   if(full)
     {
      ArrayInitialize(BufBuy, EMPTY_VALUE);
      ArrayInitialize(BufSell, EMPTY_VALUE);
      ArrayResize(gFired, 0);
      gLastSigTrigT = 0;
      gSig.valid = false;
      gSig.result = 0;
      gNeedRebuild = true;
     }

   UpdateOutcome();

   if(!DataReady())
     {
      DrawWaitLabel();
      return (rates_total);
     }

   datetime closedT = iTime(Symbol(), InpEntryTF, 1);
   if(closedT <= 0) return (rates_total);

   bool newBar = (closedT != gLastClosed);
   if(!newBar && !gNeedRebuild) return (rates_total);

   bool first = (gLastClosed == 0);
   gLastClosed = closedT;
   gNeedRebuild = false;

   BuildAll();

   if(InpHistorySignals && (first || full))
     {
      RunHistoryPass();
      UpdateOutcome();
     }

   SState st;
   EvalState(closedT, true, st);
   if(st.sigDir != 0) DrawSignalArrow(st.sigDir, (st.sigT > 0 ? st.sigT : closedT));
   DrawAll(st, closedT);

   return (rates_total);
  }
//+------------------------------------------------------------------+
