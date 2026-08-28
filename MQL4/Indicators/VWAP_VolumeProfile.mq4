//+------------------------------------------------------------------+
//|                                            VWAP_VolumeProfile.mq4|
//|                                                                  |
//|  Session-anchored VWAP + volume-weighted standard-deviation      |
//|  bands, plus a per-session horizontal Volume Profile             |
//|  (POC / VAH / VAL) - all in one MetaTrader 4 chart-window file.  |
//|                                                                  |
//|  MATH                                                            |
//|   VWAP = SUM(v_i*p_i) / SUM(v_i), accumulated over the current    |
//|          anchor period and reset at every session boundary.       |
//|          p_i = (H+L+C)/3 by default, v_i = tick volume.          |
//|   SD   = sqrt( SUM(v*p*p)/SUM(v) - VWAP^2 )   (volume weighted)  |
//|   bands= VWAP +/- K*SD                                           |
//|   VP   : MT4 publishes no volume per price level, so each bar's  |
//|          volume is distributed over the price rows the bar       |
//|          traded in - uniformly by time/overlap, or biased toward  |
//|          the O/H/L/C marks. POC = heaviest row. Value Area = rows |
//|          grown out of the POC until >= InpValueAreaPct of volume. |
//|                                                                  |
//|  Objects are reused between redraws (no flicker) and every object |
//|  this indicator owns is tracked in its own list, so nothing on   |
//|  the chart is touched that the indicator did not create.         |
//|                                                                  |
//|  MetaTrader 4 / MQL4, build 600+. No DLLs, no external files.    |
//+------------------------------------------------------------------+
#property copyright   "Arena Agent"
#property link        "https://github.com/ismailchaacha97-ui/kkk"
#property version     "1.00"
#property strict
#property description "Anchored VWAP (daily / weekly / monthly / fixed date) with volume-"
#property description "weighted SD bands, plus a per-session Volume Profile with POC, VAH, VAL."

#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5
#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2
#property indicator_label2  "VWAP +SD1"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSilver
#property indicator_width2  1
#property indicator_label3  "VWAP -SD1"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrSilver
#property indicator_width3  1
#property indicator_label4  "VWAP +SD2"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGray
#property indicator_width4  1
#property indicator_label5  "VWAP -SD2"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrGray
#property indicator_width5  1

//--- limits -------------------------------------------------------
#define VVP_MAX_BINS    400
#define VVP_MAX_WIDTH   300
#define VVP_OBJ_BUDGET  2400
#define VVP_LOOK_KEY    (-1000000000)
#define VVP_FIXED_KEY   (1000000000)
#define VVP_EPS         1.0e-12
#define VVP_NOMAX       (2147483647)

//--- enumerations --------------------------------------------------
enum ENUM_VVP_ANCHOR
  {
   VVP_ANCHOR_DAILY   = 0,   // Daily session
   VVP_ANCHOR_WEEKLY  = 1,   // Weekly session
   VVP_ANCHOR_MONTHLY = 2,   // Monthly session
   VVP_ANCHOR_FIXED   = 3    // Fixed anchor date
  };

enum ENUM_VVP_PRICE
  {
   VVP_P_TYPICAL  = 0,       // (H+L+C)/3
   VVP_P_WEIGHTED = 1,       // (H+L+2C)/4
   VVP_P_MEDIAN   = 2,       // (H+L)/2
   VVP_P_CLOSE    = 3        // Close
  };

enum ENUM_VVP_VOL
  {
   VVP_V_TICK = 0,           // Tick volume - Volume[]
   VVP_V_REAL = 1,           // iVolume() - real lots where the feed has them
   VVP_V_TIME = 2            // Equal weight per bar (time-based)
  };

enum ENUM_VVP_MODEL
  {
   VVP_M_UNIFORM = 0,        // Uniform across the bar range
   VVP_M_OHLC    = 1         // Biased to Open / High / Low / Close
  };

enum ENUM_VVP_MODE
  {
   VVP_MODE_VOL  = 0,        // Volume profile
   VVP_MODE_TPO  = 1,        // TPO (time at price)
   VVP_MODE_BOTH = 2         // Volume + TPO blended
  };

//--- inputs: VWAP --------------------------------------------------
input ENUM_VVP_ANCHOR InpAnchor     = VVP_ANCHOR_DAILY;  // Anchor / reset
input int      InpOffsetHour    = 0;              // Session start hour (chart/server time)
input int      InpOffsetMin     = 0;              // Session start minute
input int      InpWeekdayStart  = 1;              // Weekly: week starts on (1=Mon .. 7=Sun)
input string   InpAnchorDate    = "";             // Fixed anchor date "YYYY.MM.DD HH:MM" ("" = first bar)
input ENUM_VVP_PRICE InpPriceType = VVP_P_TYPICAL;// VWAP price
input ENUM_VVP_VOL   InpVolSource = VVP_V_TICK;   // Volume source
input int      InpMaxBars       = 3000;           // Max bars to calculate (0 = all history)
input bool     InpDrawBands     = true;           // Draw SD bands
input double   InpSD1           = 1.0;            // Band 1 (x std-dev)
input double   InpSD2           = 2.0;            // Band 2 (x std-dev)

//--- inputs: volume profile ---------------------------------------
input bool     InpShowProfile   = true;           // Draw volume profile
input ENUM_VVP_MODE  InpProfMode = VVP_MODE_VOL;  // Profile metric
input ENUM_VVP_MODEL InpVolModel = VVP_M_UNIFORM; // Intra-bar distribution model
input int      InpBins          = 40;             // Price rows
input double   InpValueAreaPct  = 70.0;           // Value area volume (%)
input int      InpProfWidth     = 24;             // Max profile width (bars)
input int      InpProfSessions  = 2;              // Sessions to draw (0 = all in range)
input bool     InpClipSession   = false;          // Clip rows to the session width
input bool     InpHideCurrent   = false;          // Skip drawing the in-progress session
input bool     InpShowLookback  = false;          // Combined profile for the whole range
input double   InpRowHeightPct  = 80.0;           // Row height (% of bin)
input bool     InpSkipEmpty     = true;           // Skip empty rows
input bool     InpDrawVA        = true;           // Draw VAH/VAL + value-area box
input bool     InpDrawPOCLine   = true;           // Draw POC line
input bool     InpDrawLabels    = true;           // Draw POC/VAH/VAL labels

//--- inputs: look & feel ------------------------------------------
input color    InpColorVWAP    = clrDodgerBlue;   // VWAP color
input color    InpColorBand1   = clrSilver;       // Band 1 color
input color    InpColorBand2   = clrGray;         // Band 2 color
input color    InpColorVA      = clrTeal;         // Value-area rows
input color    InpColorOut     = clrDimGray;      // Out-of-value rows
input color    InpColorPOC     = clrRed;          // POC row / line
input color    InpColorVAHVAL  = clrOrange;       // VAH / VAL lines
input color    InpColorBox     = clrGold;         // Value-area box
input bool     InpLiveTick     = true;            // Update profile on ticks
input int      InpRedrawMs     = 500;             //   min ms between tick updates
input bool     InpShowStats    = true;            // Show stats panel (chart comment)
input int      InpFontSize     = 8;               // Label font size
input bool     InpAlertVWAP    = false;           // Alert on VWAP cross
input string   InpSound        = "alert.wav";     // Alert sound ("" = silent)
input string   InpTag          = "1";             // Instance tag (2 copies: "1","2")

//--- indicator buffers --------------------------------------------
double BufVWAP[];
double BufUp1[];
double BufDn1[];
double BufUp2[];
double BufDn2[];

//--- runtime state ------------------------------------------------
string   g_tag          = "VVP_";    // object-name prefix
int      g_depth        = 0;         // bars calculated
int      g_first        = 0;         // oldest bar used by the VWAP pass
int      g_prevFirst    = -1;
datetime g_prevTime0    = 0;
datetime g_lastAlertBar = 0;
uint     g_lastDrawMs   = 0;
bool     g_anchorDone   = false;
datetime g_anchorTime   = 0;
double   g_avgBarVol    = 1.0;       // mean bar volume, TPO scaling
string   g_note         = "";
int      g_objFail      = 0;

//--- session map (oldest session first, last entry = current)
int      g_sSid[];
int      g_sOld[];
int      g_sNew[];
datetime g_sT1[];
datetime g_sT2[];
double   g_sPOC[];

//--- current session summary (stats panel)
double   g_curPOC = 0.0, g_curVAH = 0.0, g_curVAL = 0.0;
double   g_curTot = 0.0, g_curVWAP = 0.0;
int      g_curBars = 0, g_curKey = 0;

//--- the profile just built (BuildProfile writes, VVPRender reads)
double   g_pBin[];
double   g_pLo = 0.0, g_pHi = 0.0, g_pBinPx = 0.0;
double   g_pPOC = 0.0, g_pVAH = 0.0, g_pVAL = 0.0;
double   g_pTot = 0.0, g_pMax = 0.0;
int      g_pPOCIdx = 0, g_pVALo = 0, g_pVAHi = 0;

//--- object bookkeeping: names we own, and the names drawn so far
string   g_owned[];
string   g_next[];
string   g_keySig   = "";
string   g_keySigNew = "";

//+==================================================================+
//| init / deinit                                                     |
//+==================================================================+
int init()
  {
   IndicatorBuffers(5);

   SetIndexBuffer(0, BufVWAP);
   SetIndexBuffer(1, BufUp1);
   SetIndexBuffer(2, BufDn1);
   SetIndexBuffer(3, BufUp2);
   SetIndexBuffer(4, BufDn2);

   SetIndexStyle(0, DRAW_LINE, STYLE_SOLID, 2, InpColorVWAP);
   SetIndexStyle(1, DRAW_LINE, STYLE_DOT,   1, InpColorBand1);
   SetIndexStyle(2, DRAW_LINE, STYLE_DOT,   1, InpColorBand1);
   SetIndexStyle(3, DRAW_LINE, STYLE_DOT,   1, InpColorBand2);
   SetIndexStyle(4, DRAW_LINE, STYLE_DOT,   1, InpColorBand2);

   SetIndexLabel(0, "VWAP");
   SetIndexLabel(1, "VWAP +" + DoubleToString(InpSD1, 1) + " SD");
   SetIndexLabel(2, "VWAP -" + DoubleToString(InpSD1, 1) + " SD");
   SetIndexLabel(3, "VWAP +" + DoubleToString(InpSD2, 1) + " SD");
   SetIndexLabel(4, "VWAP -" + DoubleToString(InpSD2, 1) + " SD");
   for(int i = 0; i <= 4; i++)
      SetIndexEmpty(i, EMPTY_VALUE);

   //--- object names: unique per instance, ASCII only, no '_' (they are parsed)
   string t = InpTag;
   StringReplace(t, " ", "");
   StringReplace(t, "_", "");
   if(StringLen(t) == 0)
      t = "1";
   g_tag = "VVP" + t + "_";

   IndicatorDigits(Digits);
   IndicatorShortName("VWAP+VP[" + VVPAnchorText() + "]");

   g_prevFirst  = -1;
   g_prevTime0  = 0;
   g_lastDrawMs = 0;
   g_anchorDone = false;
   g_objFail    = 0;
   g_note       = "";
   g_keySig     = "";
   g_keySigNew  = "";
   VVPWipe();
   VVPSweepOrphans();      // clean up anything a previous run left behind

   return(0);
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
int deinit()
  {
   VVPWipe();
   Comment("");
   return(0);
  }

//+==================================================================+
//| start - called on every tick                                      |
//+==================================================================+
int start()
  {
   if(Bars < 4)
      return(0);
   if(IndicatorCounted() < 0)
      return(-1);

   //--- a daily / weekly anchor needs several bars per session
   if(VVPPeriodSeconds() >= 86400 && InpAnchor != VVP_ANCHOR_MONTHLY && InpAnchor != VVP_ANCHOR_FIXED)
     {
      if(g_note != "timeframe")
        {
         g_note = "timeframe";
         Comment("VWAP+VP: on " + VVPTFName() + " charts use the Monthly or Fixed anchor.");
        }
      return(0);
     }

   RecalcVWAP();

   bool newBar  = (Time[0] != g_prevTime0);
   bool shifted = (g_first != g_prevFirst);
   uint now     = GetTickCount();

   bool doDraw = (g_lastDrawMs == 0) || newBar || shifted || (ArraySize(g_owned) == 0);
   if(!doDraw && InpLiveTick)
      doDraw = ((now - g_lastDrawMs) >= (uint)MathMax(50, InpRedrawMs));

   if(doDraw)
     {
      g_prevTime0  = Time[0];
      g_lastDrawMs = now;
      DrawAll();
     }

   VVPCheckAlert();
   return(0);
  }

//+==================================================================+
//|  VWAP                                                             |
//+==================================================================+

//--- seconds per chart period (own switch: no dependency on the
//--- newer PeriodSeconds() helper)
int VVPPeriodSeconds()
  {
   switch(Period)
     {
      case PERIOD_M1:  return(60);
      case PERIOD_M5:  return(300);
      case PERIOD_M15: return(900);
      case PERIOD_M30: return(1800);
      case PERIOD_H1:  return(3600);
      case PERIOD_H4:  return(14400);
      case PERIOD_D1:  return(86400);
      case PERIOD_W1:  return(604800);
      case PERIOD_MN1: return(2592000);
     }
   return(60 * Period);
  }

//--- how many bars we calculate over
int VVPMaxBars()
  {
   if(InpMaxBars <= 0)
      return(Bars - 1);
   return(VVPClamp(InpMaxBars, 20, Bars - 1));
  }

//--- the price that is volume-weighted
double VVPBarPrice(const int i)
  {
   switch(InpPriceType)
     {
      case VVP_P_TYPICAL:  return((High[i] + Low[i] + Close[i]) / 3.0);
      case VVP_P_WEIGHTED: return((High[i] + Low[i] + 2.0 * Close[i]) / 4.0);
      case VVP_P_MEDIAN:   return((High[i] + Low[i]) / 2.0);
      case VVP_P_CLOSE:    return(Close[i]);
     }
   return(Close[i]);
  }

//--- the weight of a bar
double VVPBarVolume(const int i)
  {
   double v = 0.0;
   if(InpVolSource == VVP_V_TICK)
      v = Volume[i];
   else if(InpVolSource == VVP_V_REAL)
     {
      v = iVolume(Symbol(), 0, i);
      if(v <= 0.0)
         v = Volume[i];
     }
   if(v <= 0.0)
      v = 1.0;                    // empty volume feed -> flat weighting
   return(v);
  }

//--- session key of bar i; equal keys mean equal session.
//--- Arithmetic on Time[] only, so the boundary is the same time the
//--- chart axis prints - independent of the terminal time zone.
int VVPSessionId(const int i)
  {
   int off = InpOffsetHour * 3600 + InpOffsetMin * 60;
   int d   = (int)MathFloor((double)(Time[i] - off) / 86400.0);

   switch(InpAnchor)
     {
      case VVP_ANCHOR_DAILY:
         return(d);

      case VVP_ANCHOR_WEEKLY:
        {
         int dow    = ((d + 4) % 7 + 7) % 7;          // 1970.01.01 = Thursday
         int target = InpWeekdayStart % 7;            // Mon(1) ... Sun(0)
         int since  = ((dow - target) % 7 + 7) % 7;
         return((int)MathFloor((double)(d - since) / 7.0));
        }

      case VVP_ANCHOR_MONTHLY:
         return((int)TimeYear(Time[i]) * 12 + (int)TimeMonth(Time[i]) - 1);

      case VVP_ANCHOR_FIXED:
         return((Time[i] >= VVPAnchorTime()) ? VVP_FIXED_KEY : -1);
     }
   return(d);
  }

//--- anchor datetime for VVP_ANCHOR_FIXED
datetime VVPAnchorTime()
  {
   if(g_anchorDone)
      return(g_anchorTime);
   g_anchorDone = true;

   string s = InpAnchorDate;
   StringTrimLeft(s);
   StringTrimRight(s);

   datetime t = 0;
   if(StringLen(s) > 0)
     {
      t = StrToTime(s);
      if(t <= 0)
         g_note = "unparsable anchor date '" + s + "'";
     }
   if(t <= 0)
     {
      //--- no/invalid date: use the session start of the oldest calculated bar
      int last = VVPClamp(VVPMaxBars(), 0, Bars - 1);
      int off  = InpOffsetHour * 3600 + InpOffsetMin * 60;
      int dn   = (int)MathFloor((double)(Time[last] - off) / 86400.0);
      t = (datetime)(dn * 86400 + off);
     }
   g_anchorTime = t;
   return(t);
  }

//+------------------------------------------------------------------+
//| VWAP + bands.                                                     |
//| One forward pass over the range; the accumulators reset whenever  |
//| the session key changes. The pass starts at the first bar of the  |
//| session that contains the oldest bar in range, so a half-seen     |
//| session never skews the average.                                  |
//+------------------------------------------------------------------+
void RecalcVWAP()
  {
   int depth = VVPMaxBars();
   int first = depth;

   if(InpAnchor == VVP_ANCHOR_FIXED)
     {
      //--- oldest bar at or after the anchor
      datetime a = VVPAnchorTime();
      while(first >= 0 && Time[first] < a)
         first--;
     }
   else
     {
      //--- walk back to the start of this session
      int guard = 0;
      while(first + 1 < Bars && VVPSessionId(first + 1) == VVPSessionId(first) && guard < Bars)
        {
         first++;
         guard++;
        }
     }

   //--- everything outside the window is empty
   for(int i = Bars - 1; i > first; i--)
     {
      BufVWAP[i] = EMPTY_VALUE;
      BufUp1[i]  = EMPTY_VALUE;
      BufDn1[i]  = EMPTY_VALUE;
      BufUp2[i]  = EMPTY_VALUE;
      BufDn2[i]  = EMPTY_VALUE;
     }

   if(first < 0)
     {
      g_prevFirst = g_first;
      g_first     = -1;
      g_depth     = depth;
      g_curVWAP   = EMPTY_VALUE;
      return;
     }

   double sumV = 0.0, sumVP = 0.0, sumVP2 = 0.0, vSum = 0.0;
   int    cur  = -VVP_NOMAX;

   for(int i = first; i >= 0; i--)
     {
      int s = VVPSessionId(i);
      if(s != cur)
        {
         cur    = s;
         sumV   = 0.0;
         sumVP  = 0.0;
         sumVP2 = 0.0;
        }

      double p = VVPBarPrice(i);
      double v = VVPBarVolume(i);

      sumV   += v;
      sumVP  += v * p;
      sumVP2 += v * p * p;
      if(i <= depth)
         vSum += v;

      double vw = (sumV > VVP_EPS) ? sumVP / sumV : p;
      double vr = (sumV > VVP_EPS) ? (sumVP2 / sumV - vw * vw) : 0.0;
      if(vr < 0.0)
         vr = 0.0;
      double sd = MathSqrt(vr);

      BufVWAP[i] = vw;
      if(InpDrawBands)
        {
         BufUp1[i] = vw + InpSD1 * sd;
         BufDn1[i] = vw - InpSD1 * sd;
         BufUp2[i] = vw + InpSD2 * sd;
         BufDn2[i] = vw - InpSD2 * sd;
        }
      else
        {
         BufUp1[i] = EMPTY_VALUE;
         BufDn1[i] = EMPTY_VALUE;
         BufUp2[i] = EMPTY_VALUE;
         BufDn2[i] = EMPTY_VALUE;
        }
     }

   g_avgBarVol = (depth > 0) ? vSum / (depth + 1.0) : 1.0;
   if(g_avgBarVol <= 0.0)
      g_avgBarVol = 1.0;

   g_curVWAP   = BufVWAP[0];
   g_prevFirst = g_first;
   g_first     = first;
   g_depth     = depth;
  }

//+==================================================================+
//|  SESSION MAP                                                      |
//|  Collected from bar 0 (newest) backwards, then reversed, so      |
//|  index 0 = oldest kept session and the last index = live one.    |
//+==================================================================+
int BuildSessions()
  {
   ArrayResize(g_sSid, 0);
   ArrayResize(g_sOld, 0);
   ArrayResize(g_sNew, 0);
   ArrayResize(g_sT1,  0);
   ArrayResize(g_sT2,  0);
   ArrayResize(g_sPOC, 0);
   if(!InpShowProfile || g_first < 0)
      return(0);

   int bins = VVPClamp(InpBins, 3, VVP_MAX_BINS);
   //--- objects per session = rows + POC/VAH/VAL lines + box + 4 labels
   int perSession = bins + 8;
   int nMax = VVPClamp(VVP_OBJ_BUDGET / perSession, 1, 512);
   int want = (InpProfSessions <= 0) ? nMax : VVPClamp(InpProfSessions, 1, nMax);

   int cur    = -VVP_NOMAX;
   int newest = 0;

   for(int i = 0; i <= g_depth; i++)
     {
      int s = VVPSessionId(i);
      if(s != cur)
        {
         if(cur != -VVP_NOMAX && ArraySize(g_sSid) < want)
            VVPPushSession(cur, i - 1, newest);
         cur    = s;
         newest = i;
        }
     }
   if(cur != -VVP_NOMAX && ArraySize(g_sSid) < want)
      VVPPushSession(cur, g_depth, newest);

   //--- reverse: oldest first
   int n = ArraySize(g_sSid);
   for(int a = 0; a < n / 2; a++)
     {
      int b = n - 1 - a;
      int  ti;
      ti = g_sSid[a]; g_sSid[a] = g_sSid[b]; g_sSid[b] = ti;
      ti = g_sOld[a]; g_sOld[a] = g_sOld[b]; g_sOld[b] = ti;
      ti = g_sNew[a]; g_sNew[a] = g_sNew[b]; g_sNew[b] = ti;
      datetime td = g_sT1[a]; g_sT1[a] = g_sT1[b]; g_sT1[b] = td;
      td = g_sT2[a]; g_sT2[a] = g_sT2[b]; g_sT2[b] = td;
      double dd = g_sPOC[a]; g_sPOC[a] = g_sPOC[b]; g_sPOC[b] = dd;
     }
   return(n);
  }

//+------------------------------------------------------------------+
//| session occupying bars newIdx..oldIdx (newIdx = newest bar)       |
//+------------------------------------------------------------------+
void VVPPushSession(const int sid, const int oldIdx, const int newIdx)
  {
   if(newIdx < 0)
      return;
   int k = ArraySize(g_sSid);
   ArrayResize(g_sSid, k + 1);
   ArrayResize(g_sOld, k + 1);
   ArrayResize(g_sNew, k + 1);
   ArrayResize(g_sT1,  k + 1);
   ArrayResize(g_sT2,  k + 1);
   ArrayResize(g_sPOC, k + 1);

   g_sSid[k] = sid;
   g_sOld[k] = VVPClamp(oldIdx, 0, Bars - 1);
   g_sNew[k] = VVPClamp(newIdx, 0, Bars - 1);
   g_sT1[k]  = Time[g_sOld[k]];
   g_sT2[k]  = Time[g_sNew[k]] + VVPPeriodSeconds();
   g_sPOC[k] = 0.0;
  }

//+==================================================================+
//|  PROFILE                                                          |
//+==================================================================+

//--- price -> row index (g_pBin must already be sized)
int VVPBinOf(const double p)
  {
   int n = ArraySize(g_pBin) - 1;
   if(n < 0)
      return(0);
   return(VVPClamp((int)MathFloor((p - g_pLo) / g_pBinPx), 0, n));
  }

//+------------------------------------------------------------------+
//| Build the histogram of bars newIdx..oldIdx into g_pBin[] and      |
//| derive POC / VAH / VAL.  Returns false when there is nothing to   |
//| draw.                                                            |
//+------------------------------------------------------------------+
bool BuildProfile(const int oldIdx, const int newIdx, const int bins)
  {
   //--- loop counters are declared up-front: MQL4 scopes 'for(int i...)' to
   //--- the loop itself, so a later 'for(i = ...)' would not see them
   int i, b, j, guard;

   int lo = VVPClamp(newIdx, 0, Bars - 1);
   int hi = VVPClamp(oldIdx, 0, Bars - 1);
   if(hi < lo || bins < 2)
      return(false);

   g_pLo    =  1.0e300;
   g_pHi    = -1.0e300;
   for(i = lo; i <= hi; i++)
     {
      if(Low[i]  < g_pLo) g_pLo = Low[i];
      if(High[i] > g_pHi) g_pHi = High[i];
     }
   if(!(g_pHi > g_pLo))
     {
      double pad = Point * bins * 0.5;
      g_pLo -= pad;
      g_pHi += pad;
     }
   g_pBinPx = (g_pHi - g_pLo) / bins;
   if(g_pBinPx <= VVP_EPS)
      return(false);

   ArrayResize(g_pBin, bins);
   for(b = 0; b < bins; b++)
      g_pBin[b] = 0.0;

   bool   useVol = (InpProfMode != VVP_MODE_TPO);
   bool   useTpo = (InpProfMode != VVP_MODE_VOL);
   double tpoW   = useTpo ? ((useVol) ? g_avgBarVol : 1.0) : 0.0;

   for(i = lo; i <= hi; i++)
     {
      double vol   = useVol ? VVPBarVolume(i) : 0.0;
      double range = High[i] - Low[i];
      int    b0    = VVPBinOf(Low[i]);
      int    b1    = VVPBinOf(High[i]);

      //--- TPO part: one count per row the bar traded in
      if(tpoW > 0.0)
         for(j = b0; j <= b1; j++)
            g_pBin[j] += tpoW;

      if(!useVol)
         continue;

      //--- degenerate bar (doji / single price) -> all weight to its row
      if(range <= VVP_EPS || b1 < b0)
        {
         g_pBin[VVPBinOf(Close[i])] += vol;
         continue;
        }

      if(InpVolModel == VVP_M_OHLC)
        {
         //--- 25% Close, 10% Open, 7.5% High, 7.5% Low, 50% uniform
         g_pBin[VVPBinOf(Close[i])] += vol * 0.25;
         g_pBin[VVPBinOf(Open[i])]   += vol * 0.10;
         g_pBin[VVPBinOf(High[i])]   += vol * 0.075;
         g_pBin[VVPBinOf(Low[i])]    += vol * 0.075;
         double rest = vol * 0.50;
         for(j = b0; j <= b1; j++)
           {
            double a  = MathMax(Low[i],  g_pLo + j * g_pBinPx);
            double bb = MathMin(High[i], g_pLo + (j + 1) * g_pBinPx);
            double ov = bb - a;
            if(ov > 0.0)
               g_pBin[j] += rest * ov / range;
           }
        }
      else
        {
         //--- uniform: every touched row gets its traded overlap share
         for(j = b0; j <= b1; j++)
           {
            double a  = MathMax(Low[i],  g_pLo + j * g_pBinPx);
            double bb = MathMin(High[i], g_pLo + (j + 1) * g_pBinPx);
            double ov = bb - a;
            if(ov > 0.0)
               g_pBin[j] += vol * ov / range;
           }
        }
     }

   //--- totals and POC row
   g_pTot    = 0.0;
   g_pMax    = 0.0;
   g_pPOCIdx = 0;
   for(b = 0; b < bins; b++)
     {
      if(g_pBin[b] < 0.0)
         g_pBin[b] = 0.0;
      g_pTot += g_pBin[b];
      if(g_pBin[b] > g_pMax)
        {
         g_pMax    = g_pBin[b];
         g_pPOCIdx = b;
        }
     }
   if(g_pTot <= VVP_EPS || g_pMax <= VVP_EPS)
      return(false);

   g_pPOC = g_pLo + (g_pPOCIdx + 0.5) * g_pBinPx;

   //--- value area: grow out of the POC, always taking the heavier neighbour
   double target = g_pTot * InpValueAreaPct / 100.0;
   if(target > g_pTot)
      target = g_pTot;
   int    up = g_pPOCIdx, dn = g_pPOCIdx;
   double acc = g_pBin[g_pPOCIdx];
   for(guard = 0; acc < target && guard <= bins + 1; guard++)
     {
      bool   canUp = (up < bins - 1);
      bool   canDn = (dn > 0);
      if(!canUp && !canDn)
         break;
      double vu = canUp ? g_pBin[up + 1] : -1.0;
      double vd = canDn ? g_pBin[dn - 1] : -1.0;
      if(vu >= vd)
        {
         up++;
         acc += g_pBin[up];
        }
      else
        {
         dn--;
         acc += g_pBin[dn];
        }
     }
   g_pVAHi = up;
   g_pVALo = dn;
   g_pVAH  = g_pLo + (up + 1) * g_pBinPx;
   g_pVAL  = g_pLo + dn * g_pBinPx;
   return(true);
  }

//+==================================================================+
//|  DRAW                                                             |
//+==================================================================+
void DrawAll()
  {
   int bins = VVPClamp(InpBins, 3, VVP_MAX_BINS);

   if(!InpShowProfile)
     {
      VVPBeginPass();
      g_keySigNew = "|";   // own nothing -> everything we had is stale
      VVPCommitPass();
      ArrayResize(g_sSid, 0);
      ArrayResize(g_sOld, 0);
      ArrayResize(g_sNew, 0);
      VVPStats();
      return;
     }

   int ns = BuildSessions();

   VVPBeginPass();
   g_keySigNew = "|";

   //--- combined profile of the whole calculated range
   if(InpShowLookback && g_depth >= 3)
     {
      if(BuildProfile(g_depth, 0, bins))
        {
         g_keySigNew = g_keySigNew + IntegerToString(VVP_LOOK_KEY) + "|";
         VVPRender(VVP_LOOK_KEY, Time[g_depth], Time[0] + VVPPeriodSeconds(), bins, true, false);
        }
     }

   //--- session profiles: oldest first so the live session ends up on top
   for(int s = 0; s < ns; s++)
     {
      g_sPOC[s] = 0.0;
      if(g_sOld[s] < g_sNew[s])
         continue;
      if(!BuildProfile(g_sOld[s], g_sNew[s], bins))
         continue;

      g_sPOC[s] = g_pPOC;
      bool live = (g_sNew[s] == 0);
      if(live)
        {
         g_curPOC  = g_pPOC;
         g_curVAH  = g_pVAH;
         g_curVAL  = g_pVAL;
         g_curTot  = g_pTot;
         g_curBars = g_sOld[s] - g_sNew[s] + 1;
         g_curKey  = g_sSid[s];
        }
      if(InpHideCurrent && live)
         continue;

      g_keySigNew = g_keySigNew + IntegerToString(g_sSid[s]) + "|";
      VVPRender(g_sSid[s], g_sT1[s], g_sT2[s], bins, false, live);
     }

   VVPCommitPass();
   ArrayResize(g_pBin, 0);
   VVPStats();
  }

//+------------------------------------------------------------------+
//| Render the profile currently held in g_p*  (rows, POC, VA, labels)|
//+------------------------------------------------------------------+
void VVPRender(const int key, const datetime t1in, const datetime t2in, const int bins,
              const bool isRange, const bool live)
  {
   datetime t1 = t1in;
   datetime t2 = t2in;
   if(t2 <= t1)
      t2 = t1 + VVPPeriodSeconds();

   //--- vertical gap: a row drawn at H% height leaves (100-H)/2 of a bin of
   //--- empty space above and below it, so neighbouring rows never overlap
   double pad   = g_pBinPx * (100.0 - VVPRowHeight()) / 100.0 * 0.5;
   int    width = VVPClamp(InpProfWidth, 1, VVP_MAX_WIDTH);

   for(int b = 0; b < bins; b++)
     {
      string nm = VVPName(key, "b", b);
      double v  = g_pBin[b];

      if(InpSkipEmpty && v <= 0.0)
        {
         VVPDrop(nm);
         continue;
        }

      double frac = (g_pMax > VVP_EPS) ? v / g_pMax : 0.0;
      if(frac > 1.0)
         frac = 1.0;

      int rows = (int)MathRound(frac * width);
      if(rows < 1)
         rows = 1;
      datetime te = t1 + (datetime)(rows * VVPPeriodSeconds());
      if(InpClipSession && te > t2)
         te = t2;
      if(te <= t1)
         te = t1 + VVPPeriodSeconds();

      color c;
      if(b == g_pPOCIdx)
         c = InpColorPOC;
      else if(b >= g_pVALo && b <= g_pVAHi)
         c = VVPMix(InpColorVA, frac);
      else
         c = VVPMix(InpColorOut, frac * 0.6);

      double p1 = g_pLo + b * g_pBinPx + pad;
      double p2 = g_pLo + (b + 1) * g_pBinPx - pad;
      if(p2 <= p1)
         p2 = p1 + g_pBinPx * 0.01;

      VVPRect(nm, t1, p1, te, p2, c, true);
     }

   //--- POC
   if(InpDrawPOCLine)
      VVPLine(VVPName(key, "l", 0), t1, g_pPOC, t2, g_pPOC, InpColorPOC, STYLE_DOT, 1);
   else
      VVPDrop(VVPName(key, "l", 0));

   //--- VAH / VAL / box
   if(InpDrawVA)
     {
      VVPLine(VVPName(key, "l", 1), t1, g_pVAH, t2, g_pVAH, InpColorVAHVAL, STYLE_DOT, 1);
      VVPLine(VVPName(key, "l", 2), t1, g_pVAL, t2, g_pVAL, InpColorVAHVAL, STYLE_DOT, 1);
      VVPRect(VVPName(key, "x", 0), t1, g_pVAL, t2, g_pVAH, InpColorBox, false);
     }
   else
     {
      VVPDrop(VVPName(key, "l", 1));
      VVPDrop(VVPName(key, "l", 2));
      VVPDrop(VVPName(key, "x", 0));
     }

   //--- labels, in a column right of the widest possible profile
   datetime tl = t1 + (datetime)((width + 1) * VVPPeriodSeconds());
   if(tl < t2)
      tl = t2;
   if(InpDrawLabels)
     {
      string head = "POC";
      if(isRange)
         head = "RANGE POC";
      else if(live)
         head = "LIVE POC";

      VVPLabel(VVPName(key, "t", 0), tl, g_pPOC, head + " " + VVPFmt(g_pPOC), InpColorPOC);
      if(InpDrawVA)
        {
         VVPLabel(VVPName(key, "t", 1), tl, g_pVAH, "VAH " + VVPFmt(g_pVAH), InpColorVAHVAL);
         VVPLabel(VVPName(key, "t", 2), tl, g_pVAL, "VAL " + VVPFmt(g_pVAL), InpColorVAHVAL);
        }
      else
        {
         VVPDrop(VVPName(key, "t", 1));
         VVPDrop(VVPName(key, "t", 2));
        }
      VVPLabel(VVPName(key, "t", 3), tl, g_pVAL - g_pBinPx,
               VVPVol(g_pTot) + " " + VVPVolUnit() + (live ? "  forming" : ""), InpColorVA);
     }
   else
      for(int k = 0; k <= 3; k++)
         VVPDrop(VVPName(key, "t", k));
  }

//--- row height percentage, clamped
double VVPRowHeight()
  {
   if(InpRowHeightPct < 20.0)
      return(20.0);
   if(InpRowHeightPct > 100.0)
      return(100.0);
   return(InpRowHeightPct);
  }

//+==================================================================+
//|  OBJECT LAYER                                                     |
//|  Only the legacy, unambiguous MQL4 object calls are used:         |
//|    ObjectCreate(name, type, sub_window, t1, p1, t2, p2)          |
//|    ObjectMove(name, point_index, time, price)                    |
//|    ObjectSet(name, OBJPROP_xxx, value)                           |
//|    ObjectSetText(name, text, size, font, color)                  |
//|  plus ObjectSetInteger(0, name, prop, value) for the properties   |
//|  that only exist in the newer property enumeration.              |
//+==================================================================+
string VVPName(const int key, const string kind, const int idx)
  {
   return(g_tag + IntegerToString(key) + "_" + kind + IntegerToString(idx));
  }

//--- pass bookkeeping ------------------------------------------------
void VVPBeginPass()
  {
   ArrayResize(g_next, 0);
  }

//--- delete objects that were not part of this pass, then adopt it.
//--- Only a change of the drawn session set can leave stale objects: every
//--- row / line / label of a drawn session is visited on every pass (empty
//--- rows are dropped explicitly), so no per-row diff is needed here.
void VVPCommitPass()
  {
   int nOwn  = ArraySize(g_owned);
   int nNext = ArraySize(g_next);

   if(g_keySig != g_keySigNew)
     {
      for(int i = nOwn - 1; i >= 0; i--)
        {
         string nm = g_owned[i];
         bool   found = false;
         for(int j = 0; j < nNext; j++)
           {
            if(g_next[j] == nm)
              {
               found = true;
               break;
              }
           }
         if(!found && ObjectFind(nm) >= 0)
            ObjectDelete(nm);
        }
      g_keySig = g_keySigNew;
     }

   ArrayResize(g_owned, nNext);
   for(int k = 0; k < nNext; k++)
      g_owned[k] = g_next[k];
   ArrayResize(g_next, 0);
  }

//--- delete VVP objects left behind by a previous (crashed) session
void VVPSweepOrphans()
  {
   int tlen = StringLen(g_tag);
   int nOwn = ArraySize(g_owned);

   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string nm = ObjectName(i);
      if(StringLen(nm) <= tlen || StringFind(nm, g_tag, 0) != 0)
         continue;
      bool own = false;
      for(int k = 0; k < nOwn; k++)
        {
         if(g_owned[k] == nm)
           {
            own = true;
            break;
           }
        }
      if(!own)
         ObjectDelete(nm);
     }
  }

//--- remember a name we have just drawn
void VVPTake(const string nm)
  {
   int k = ArraySize(g_next);
   ArrayResize(g_next, k + 1);
   g_next[k] = nm;
  }

//--- remove an object we no longer want
void VVPDrop(const string nm)
  {
   if(ObjectFind(nm) >= 0)
      ObjectDelete(nm);
  }

//--- true when creating a new object is not allowed (budget)
bool VVPBudget()
  {
   if(ArraySize(g_next) >= VVP_OBJ_BUDGET)
     {
      if(g_note != "objects")
         g_note = "objects";
      return(true);
     }
   return(false);
  }

//--- rectangle: filled background rows, or an outline for the VA box
bool VVPRect(const string nm, const datetime t1, const double p1, const datetime t2,
             const double p2, const color clr, const bool fill)
  {
   if(ObjectFind(nm) < 0)
     {
      if(VVPBudget())
         return(false);
      if(!ObjectCreate(nm, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
        {
         g_objFail++;
         return(false);
        }
      ObjectSet(nm, OBJPROP_COLOR, (int)clr);
      ObjectSet(nm, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSet(nm, OBJPROP_WIDTH, 1);
      ObjectSet(nm, OBJPROP_BACK,  (fill) ? 1 : 0);
      ObjectSetInteger(0, nm, OBJPROP_FILL,       fill);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
      VVPTake(nm);
      return(true);
     }

   ObjectMove(nm, 0, t1, p1);
   ObjectMove(nm, 1, t2, p2);
   ObjectSet(nm, OBJPROP_COLOR, (int)clr);
   VVPTake(nm);
   return(true);
  }

//--- trend line used as a horizontal segment
bool VVPLine(const string nm, const datetime t1, const double p1, const datetime t2,
             const double p2, const color clr, const int style, const int wide)
  {
   if(ObjectFind(nm) < 0)
     {
      if(VVPBudget())
         return(false);
      if(!ObjectCreate(nm, OBJ_TREND, 0, t1, p1, t2, p2))
        {
         g_objFail++;
         return(false);
        }
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
      ObjectSet(nm, OBJPROP_BACK, 0);
      VVPTake(nm);
     }
   else
      VVPTake(nm);

   ObjectMove(nm, 0, t1, p1);
   ObjectMove(nm, 1, t2, p2);
   ObjectSet(nm, OBJPROP_COLOR, (int)clr);
   ObjectSet(nm, OBJPROP_STYLE, style);
   ObjectSet(nm, OBJPROP_WIDTH, wide);
   ObjectSet(nm, OBJPROP_RAY,   0);
   return(true);
  }

//--- price-anchored text
bool VVPLabel(const string nm, const datetime t, const double p, const string txt, const color clr)
  {
   if(StringLen(txt) == 0)
     {
      VVPDrop(nm);
      return(false);
     }
   if(ObjectFind(nm) < 0)
     {
      if(VVPBudget())
         return(false);
      if(!ObjectCreate(nm, OBJ_TEXT, 0, t, p, t, p))
        {
         g_objFail++;
         return(false);
        }
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, nm, OBJPROP_HIDDEN,     true);
      ObjectSet(nm, OBJPROP_BACK, 0);
      VVPTake(nm);
     }
   else
      VVPTake(nm);

   ObjectMove(nm, 0, t, p);
   ObjectSetText(nm, txt, MathMax(6, InpFontSize), "Arial", clr);
   return(true);
  }

//--- delete every object this instance created
void VVPWipe()
  {
   int n = ArraySize(g_owned);
   for(int i = 0; i < n; i++)
      VVPDrop(g_owned[i]);
   ArrayResize(g_owned, 0);
   ArrayResize(g_next, 0);
   g_keySig = "";
  }

//+==================================================================+
//|  STATS / HELPERS                                                  |
//+==================================================================+
void VVPStats()
  {
   if(!InpShowStats)
     {
      Comment("");
      return;
     }

   string ln = "---------------------------------------------\n";
   string s  = ln;
   s = s + "  VWAP + VOLUME PROFILE   " + Symbol() + "  " + VVPTFName() + "  " + VVPAnchorText() + "\n";
   s = s + ln;
   s = s + "  VWAP      " + VVPAd(VVPFmt(BufVWAP[0]), 11) + VVPBias() + "\n";
   s = s + "  +1 / -1SD " + VVPAd(VVPFmt(BufUp1[0]), 11) + "  " + VVPFmt(BufDn1[0]) + "\n";
   s = s + "  +2 / -2SD " + VVPAd(VVPFmt(BufUp2[0]), 11) + "  " + VVPFmt(BufDn2[0]) + "\n";
   s = s + ln;
   if(InpShowProfile)
     {
      s = s + "  POC       " + VVPAd(VVPFmt(g_curPOC), 11) + VVPDist(g_curPOC) + "\n";
      s = s + "  VAH / VAL " + VVPAd(VVPFmt(g_curVAH), 11) + "  " + VVPFmt(g_curVAL) + "\n";
      s = s + "  rows      " + VVPAd(IntegerToString(VVPClamp(InpBins, 3, VVP_MAX_BINS)), 11) +
            "   value area " + DoubleToString(InpValueAreaPct, 0) + "% (" + VVPModeName() + ")\n";
      s = s + "  volume    " + VVPAd(VVPVol(g_curTot) + " " + VVPVolUnit(), 11) +
            "   session bars " + IntegerToString(g_curBars) + "\n";
      int pn = ArraySize(g_sPOC) - 1;
      if(pn > 0 && g_sPOC[pn - 1] > 0.0 && g_curPOC > 0.0)
         s = s + "  prev POC  " + VVPAd(VVPFmt(g_sPOC[pn - 1]), 11) + "   shift " +
               IntegerToString((int)MathRound((g_curPOC - g_sPOC[pn - 1]) / MathMax(Point, 1.0e-10))) + " pts\n";
     }
   else
      s = s + "  volume profile: off\n";

   if(g_note == "objects")
      s = s + "  ! object budget reached - lower Rows / Sessions\n";
   else if(g_note == "timeframe")
      s = s + "  ! timeframe too high for this anchor\n";
   else if(StringLen(g_note) > 0)
      s = s + "  ! " + g_note + "\n";
   if(g_objFail > 0)
      s = s + "  ! " + IntegerToString(g_objFail) + " object(s) failed to create\n";
   s = s + ln;
   Comment(s);
  }

string VVPModeName()
  {
   if(InpProfMode == VVP_MODE_VOL)
      return("volume");
   if(InpProfMode == VVP_MODE_TPO)
      return("TPO");
   return("vol+TPO");
  }

string VVPVolUnit()
  {
   if(InpVolSource == VVP_V_TIME)
      return("bars");
   if(InpVolSource == VVP_V_REAL)
      return("lots");
   return("ticks");
  }

string VVPAnchorText()
  {
   switch(InpAnchor)
     {
      case VVP_ANCHOR_DAILY:
         return("Daily " + VVP2(InpOffsetHour) + ":" + VVP2(InpOffsetMin));
      case VVP_ANCHOR_WEEKLY:
         return("Weekly " + VVPWeekday(InpWeekdayStart));
      case VVP_ANCHOR_MONTHLY:
         return("Monthly");
      case VVP_ANCHOR_FIXED:
         return("From " + TimeToString(VVPAnchorTime(), TIME_DATE));
     }
   return("Daily");
  }

string VVPWeekday(const int dow)
  {
   switch(dow % 7)
     {
      case 0: return("Sun");
      case 1: return("Mon");
      case 2: return("Tue");
      case 3: return("Wed");
      case 4: return("Thu");
      case 5: return("Fri");
     }
   return("Sat");
  }

string VVP2(const int v)
  {
   if(v < 10)
      return("0" + IntegerToString(v));
   return(IntegerToString(v));
  }

string VVPTFName()
  {
   switch(Period)
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
   return("M" + IntegerToString(Period));
  }

//--- where the market sits relative to the session VWAP
string VVPBias()
  {
   if(BufVWAP[0] == EMPTY_VALUE || MathAbs(BufVWAP[0]) < VVP_EPS)
      return("");
   double vw = BufVWAP[0];
   double d  = (Close[0] - vw) / vw * 100.0;
   double pt = (Close[0] - vw) / MathMax(Point, 1.0e-10);
   string ar = (Close[0] >= vw) ? "above" : "below";
   return("  " + ar + " " + DoubleToString(MathAbs(d), 3) + "% / " +
          IntegerToString((int)MathRound(MathAbs(pt))) + " pts");
  }

//--- distance of a level from the VWAP, in points
string VVPDist(const double p)
  {
   if(p <= VVP_EPS || BufVWAP[0] == EMPTY_VALUE)
      return("");
   double d = (p - BufVWAP[0]) / MathMax(Point, 1.0e-10);
   string sg = (d >= 0.0) ? "+" : "";
   return("  " + sg + IntegerToString((int)MathRound(d)) + " pts vs VWAP");
  }

string VVPFmt(const double p)
  {
   if(p == EMPTY_VALUE || p <= 0.0 || p > 1.0e299)
      return("--");
   return(DoubleToString(p, Digits));
  }

string VVPVol(const double v)
  {
   if(v >= 1000000.0)
      return(DoubleToString(v / 1000000.0, 2) + "M");
   if(v >= 1000.0)
      return(DoubleToString(v / 1000.0, 2) + "k");
   return(DoubleToString(v, 0));
  }

string VVPAd(const string s, const int w)
  {
   string r = s;
   while(StringLen(r) < w)
      r = r + " ";
   return(r);
  }

//--- lighten towards white as a row gets heavier
color VVPMix(const color base, const double ratio)
  {
   double k = MathMax(0.0, MathMin(1.0, ratio)) * 0.8;
   int    b  = (int)base;
   int    r  = b & 0xFF;
   int    g  = (b >> 8) & 0xFF;
   int    bl = (b >> 16) & 0xFF;
   r  = (int)MathMin(255.0, r  + (255 - r)  * k);
   g  = (int)MathMin(255.0, g  + (255 - g)  * k);
   bl = (int)MathMin(255.0, bl + (255 - bl) * k);
   return((color)(r | (g << 8) | (bl << 16)));
  }

int VVPClamp(const int v, const int lo, const int hi)
  {
   if(lo > hi)
      return(lo);
   if(v < lo)
      return(lo);
   if(v > hi)
      return(hi);
   return(v);
  }

//+------------------------------------------------------------------+
//| one alert per bar when the close crosses the session VWAP         |
//+------------------------------------------------------------------+
void VVPCheckAlert()
  {
   if(!InpAlertVWAP || Bars < 2)
      return;
   if(BufVWAP[0] == EMPTY_VALUE || BufVWAP[1] == EMPTY_VALUE)
      return;
   if(Time[0] == g_lastAlertBar)
      return;

   bool a0 = (Close[0] > BufVWAP[0]);
   bool a1 = (Close[1] > BufVWAP[1]);
   if(a0 == a1)
      return;

   g_lastAlertBar = Time[0];
   string dir = "crossed BELOW ";
   if(a0)
      dir = "crossed ABOVE ";
   Alert("VWAP+VP " + Symbol() + " " + VVPTFName() + ": " + dir + "VWAP " +
         DoubleToString(BufVWAP[0], Digits));
   if(StringLen(InpSound) > 0)
      PlaySound(InpSound);
  }
//+------------------------------------------------------------------+
