//+------------------------------------------------------------------+
//|              3 Tier London Breakout V.3.3 BrokerTime.mq4         |
//+------------------------------------------------------------------+
#property copyright "by Squalou and mer071898 + broker-time auto-adjust"
#property link      "http://www.forexfactory.com/showthread.php?t=247220"
#property indicator_chart_window
#property version   "3.3"

#define VERSION "3 Tier London Breakout Indicator V.3.3b (broker time)"

/*+------------------------------------------------------------------+
 *
 * V.3.3b / V.3.3:
 *     - Session / box times are automatically converted to the broker
 *       server clock (TimeCurrent / chart time).
 *     - Input times can be specified in London, GMT, a fixed GMT+N
 *       calibration (original indicator assumed GMT+2), or raw Broker.
 *     - Broker GMT offset is auto-detected from the server.
 *     - EU / US / off DST policies are supported so historical days
 *       stay aligned when clocks change.
 *     - On-chart dashboard shows broker offset, DST, and the converted
 *       box + session times so you can verify alignment.
 *
 * V.3.2b:
 *     - added "StickBoxOusideSRlevels" input
 *
 * V.3.2a:
 *     - fixed "StickBoxToLatestExtreme"
 *
 * V.3.2: Added "StickBoxToLatestExtreme"
 *
 * V.3.1: setting TP5Factor to 0 will disable TP4 and TP5 levels
 *
 * V.3: added TP5Factor input
 *
 * V.2: original version by Squalou
 *
 *+------------------------------------------------------------------+
 */

extern string Info          = VERSION;
extern string TimeSettings  = "=== SESSION TIMES (auto-shifted to broker) ===";
extern string StartTime     = "06:00";    // start of price establishment window
extern string EndTime       = "09:14";    // end of price establishment window
extern string SessionEndTime= "04:30";    // end of daily session; tomorrow is another day!
extern string TimesAreSpecifiedIn = "London"; // London | GMT | GMT+2 | Broker
extern bool   AutoAdjustToBrokerTime = true;  // convert TimesAreSpecifiedIn -> broker chart time
extern int    BrokerGMTOffsetHours = 99;      // 99 = auto-detect from server (TimeCurrent-TimeGMT)
extern string BrokerDST     = "Auto";         // Auto | EET | EST | Off
extern bool   ShowTimeDashboard = true;

extern color  SessionColor  = Linen;
extern int    NumDays       = 200;
extern int    MinBoxSizeInPips = 15;
extern int    MaxBoxSizeInPips = 80;
extern bool   LimitBoxToMaxSize = true;
extern bool   StickBoxToLatestExtreme = false;
extern bool   StickBoxOusideSRlevels = false;
extern double TP1Factor     = 1.000;
       double TP2Factor;
extern double TP3Factor     = 2.618;
       double TP4Factor;
extern double TP5Factor     = 4.236;
extern string TP2_help      = "TP2 is half-way between TP1 and TP3";
extern string TP4_help      = "TP4 is half-way between TP3 and TP5";
       double SLFactor      = 1.000;
extern double LevelsResizeFactor = 1.0;
extern color  BoxColorOK    = LightBlue;
extern color  BoxColorNOK   = Red;
extern color  BoxColorMAX   = Orange;
extern color  LevelColor    = Black;
extern int    FibLength     = 14;
extern bool   showProfitZone = true;
extern color  ProfitColor   = LightGreen;

extern string objPrefix     = "LB2-";


//--------------------------------------------------------
// GLOBAL variables

double pip;
int digits;
int BarsBack;

double BuyEntry,BuyTP1,BuyTP2,BuyTP3,BuyTP4,BuyTP5,BuySL;
double SellEntry,SellTP1,SellTP2,SellTP3,SellTP4,SellTP5,SellSL;
int SL_pips,TP1_pips,TP2_pips,TP3_pips,TP4_pips,TP5_pips;
double TP1FactorInput,TP2FactorInput,TP3FactorInput,TP4FactorInput,TP5FactorInput,SLFactorInput;

datetime tBoxStart,tBoxEnd,tSessionStart,tSessionEnd,tLastComputedSessionStart,tLastComputedSessionEnd;
double boxHigh,boxLow,boxExtent,boxMedianPrice;

int StartShift;
int EndShift;
datetime alreadyDrawn;

int    g_brokerWinterGMT = 2;
bool   g_brokerUsesDST   = true;
int    g_brokerDSTType   = 0; // 0 = EU/EET, 1 = US
string g_timeBase        = "london";
string g_startHHMM, g_endHHMM, g_sessHHMM;
int    g_lastDetectedOffset = 99;

//+------------------------------------------------------------------+
int init()  {
//+------------------------------------------------------------------+
  RemoveObjects(objPrefix);
  getpip();
  DetectBrokerTimePolicy();

  BarsBack = NumDays*(PERIOD_D1/Period());
  alreadyDrawn = 0;
  tSessionStart = 0;
  tSessionEnd   = 0;

  TP1FactorInput = TP1Factor;
  TP3FactorInput = TP3Factor;
  TP5FactorInput = TP5Factor;
  SLFactorInput  = SLFactor;

  TP2Factor = (TP1Factor+TP3Factor)/2;
  TP4Factor = (TP3Factor+TP5Factor)/2;

  if (StickBoxOusideSRlevels==true) {
    LimitBoxToMaxSize = true;
    StickBoxToLatestExtreme = true;
  }

  g_timeBase = NormalizeTZ(TimesAreSpecifiedIn);

  Comment(DashboardText(TimeCurrent()));
  return(0);
}

//+------------------------------------------------------------------+
int deinit()  {
//+------------------------------------------------------------------+
  RemoveObjects(objPrefix);
  Comment("");
  return(0);
}

//+------------------------------------------------------------------+
void start()  {
//+------------------------------------------------------------------+
  int i, limit, counted_bars=IndicatorCounted();

  DetectBrokerTimePolicy();

  limit = MathMin(BarsBack,Bars-counted_bars-1);

  for (i=limit; i>=0; i--) {
    new_tick(i);
  }

  if (ShowTimeDashboard) {
    Comment(DashboardText(Time[0]));
    DrawDashboardLabel();
  }

  return(0);
}

//+------------------------------------------------------------------+
void new_tick(int i)
//+------------------------------------------------------------------+
{
  datetime now = Time[i];
  compute_LB_Indi_LEVELS(now);
  show_boxes(now);
}

//====================================================================
// BROKER TIME ENGINE
//====================================================================

string NormalizeTZ(string s)
{
  string r = s;
  StringTrimLeft(r);
  StringTrimRight(r);
  StringToLower(r);
  if (r=="utc" || r=="gmt+0" || r=="gmt-0" || r=="z") r = "gmt";
  if (r=="uk" || r=="gb" || r=="bst" || r=="europe/london" || r=="london time") r = "london";
  if (r=="server" || r=="broker time" || r=="chart" || r=="as-is") r = "broker";
  if (r=="original" || r=="eet-winter" || r=="gmt +2" || r=="utc+2") r = "gmt+2";
  if (r=="utc+3" || r=="gmt +3") r = "gmt+3";
  return(r);
}

string NormalizeDST(string s)
{
  string r = s;
  StringTrimLeft(r);
  StringTrimRight(r);
  StringToLower(r);
  if (r=="yes" || r=="on" || r=="eu" || r=="true") r = "eet";
  if (r=="no" || r=="none" || r=="fixed" || r=="false") r = "off";
  if (r=="us" || r=="america" || r=="edt" || r=="ny") r = "est";
  return(r);
}

datetime DateMidnight(datetime t)
{
  return(StrToTime(TimeToStr(t, TIME_DATE)));
}

datetime LastSundayOf(int year, int month)
{
  int nextM = month + 1;
  int nextY = year;
  if (nextM > 12) { nextM = 1; nextY++; }
  datetime firstNext = StrToTime(PadDate(nextY, nextM, 1) + " 00:00");
  datetime lastDay   = firstNext - 86400;
  int dow = TimeDayOfWeek(lastDay); // 0 = Sunday
  return(lastDay - dow * 86400);
}

datetime NthSundayOf(int year, int month, int n)
{
  datetime first = StrToTime(PadDate(year, month, 1) + " 00:00");
  int dow = TimeDayOfWeek(first);
  int add = (dow == 0) ? 0 : (7 - dow);
  return(first + (add + (n - 1) * 7) * 86400);
}

string Pad2(int v)
{
  if (v < 10) return("0" + IntegerToString(v));
  return(IntegerToString(v));
}

string PadDate(int y, int m, int d)
{
  return(IntegerToString(y) + "." + Pad2(m) + "." + Pad2(d));
}

bool IsEUDST(datetime t)
{
  int y = TimeYear(t);
  datetime startDay = LastSundayOf(y, 3);
  datetime endDay   = LastSundayOf(y, 10);
  datetime day = DateMidnight(t);
  return(day >= startDay && day < endDay);
}

bool IsUSDST(datetime t)
{
  int y = TimeYear(t);
  datetime startDay = NthSundayOf(y, 3, 2);  // 2nd Sunday of March
  datetime endDay   = NthSundayOf(y, 11, 1); // 1st Sunday of November
  datetime day = DateMidnight(t);
  return(day >= startDay && day < endDay);
}

bool IsUKDST(datetime t)
{
  return(IsEUDST(t));
}

int CurrentBrokerGMTOffsetHours()
{
  datetime srv = TimeCurrent();
  datetime gmt = TimeGMT();
  if (srv <= 0 || gmt <= 0) return(2);
  return((int)MathRound((double)(srv - gmt) / 3600.0));
}

void DetectBrokerTimePolicy()
{
  int currentOffset = CurrentBrokerGMTOffsetHours();
  if (BrokerGMTOffsetHours != 99)
    currentOffset = BrokerGMTOffsetHours;

  g_lastDetectedOffset = currentOffset;

  string dst = NormalizeDST(BrokerDST);
  datetime now = TimeCurrent();

  if (dst == "off") {
    g_brokerUsesDST = false;
    g_brokerDSTType = 0;
    g_brokerWinterGMT = currentOffset;
    return;
  }

  if (dst == "est") {
    g_brokerUsesDST = true;
    g_brokerDSTType = 1;
    g_brokerWinterGMT = IsUSDST(now) ? currentOffset - 1 : currentOffset;
    return;
  }

  // Auto: infer EET / EST / fixed from the live server offset.
  if (dst == "auto") {
    if (currentOffset == 2 || currentOffset == 3) {
      if (IsEUDST(now) && currentOffset == 2) {
        g_brokerUsesDST = false;
        g_brokerWinterGMT = 2;
      } else if (!IsEUDST(now) && currentOffset == 3) {
        g_brokerUsesDST = false;
        g_brokerWinterGMT = 3;
      } else {
        g_brokerUsesDST = true;
        g_brokerDSTType = 0;
        g_brokerWinterGMT = 2;
      }
      return;
    }
    if (currentOffset == -5 || currentOffset == -4) {
      if (IsUSDST(now) && currentOffset == -5) {
        g_brokerUsesDST = false;
        g_brokerWinterGMT = -5;
      } else if (!IsUSDST(now) && currentOffset == -4) {
        g_brokerUsesDST = false;
        g_brokerWinterGMT = -4;
      } else {
        g_brokerUsesDST = true;
        g_brokerDSTType = 1;
        g_brokerWinterGMT = -5;
      }
      return;
    }
    g_brokerUsesDST = false;
    g_brokerWinterGMT = currentOffset;
    return;
  }

  // Explicit EET
  g_brokerUsesDST = true;
  g_brokerDSTType = 0;
  g_brokerWinterGMT = IsEUDST(now) ? currentOffset - 1 : currentOffset;
}

int GetBrokerOffsetAt(datetime t)
{
  if (!AutoAdjustToBrokerTime) return(0);
  if (!g_brokerUsesDST) return(g_brokerWinterGMT);
  if (g_brokerDSTType == 1) return(g_brokerWinterGMT + (IsUSDST(t) ? 1 : 0));
  return(g_brokerWinterGMT + (IsEUDST(t) ? 1 : 0));
}

int GetSourceOffsetAt(datetime t)
{
  string base = g_timeBase;
  if (base == "broker" || !AutoAdjustToBrokerTime) return(GetBrokerOffsetAt(t));
  if (base == "gmt")    return(0);
  if (base == "london") return(IsUKDST(t) ? 1 : 0);
  if (base == "gmt+1" || base == "utc+1") return(1);
  if (base == "gmt+2" || base == "utc+2") return(2);
  if (base == "gmt+3" || base == "utc+3") return(3);
  if (base == "gmt-5" || base == "est")   return(IsUSDST(t) ? -4 : -5);
  if (base == "gmt-4") return(-4);
  // fallback: try to parse "gmt+N" / "utc-N"
  int sign = 0;
  int p = StringFind(base, "gmt+");
  if (p == 0) sign = 1;
  p = StringFind(base, "utc+");
  if (p == 0) sign = 1;
  p = StringFind(base, "gmt-");
  if (p == 0) sign = -1;
  p = StringFind(base, "utc-");
  if (p == 0) sign = -1;
  if (sign != 0) {
    int hours = (int)StringToInteger(StringSubstr(base, 4));
    return(sign * hours);
  }
  return(GetBrokerOffsetAt(t));
}

bool ParseHHMM(string t, int &h, int &m)
{
  string s = t;
  StringTrimLeft(s);
  StringTrimRight(s);
  int pos = StringFind(s, ":");
  if (pos < 0) {
    h = (int)StringToInteger(s);
    m = 0;
    return(h>=0 && h<=23);
  }
  h = (int)StringToInteger(StringSubstr(s, 0, pos));
  m = (int)StringToInteger(StringSubstr(s, pos + 1, 2));
  return(h>=0 && h<=23 && m>=0 && m<=59);
}

string FormatHHMM(int h, int m)
{
  while (h < 0)  h += 24;
  while (h > 23) h -= 24;
  return(Pad2(h) + ":" + Pad2(m));
}

// Convert a wall-clock HH:MM specified in TimesAreSpecifiedIn into a
// datetime that lines up with the broker/chart clock for the date of `now`.
datetime WallClockToBroker(datetime now, string hhmm)
{
  int h, m;
  if (!ParseHHMM(hhmm, h, m))
    return(StrToTime(TimeToStr(now, TIME_DATE) + " " + hhmm));

  datetime midnight = DateMidnight(now);
  int shiftHours = 0;
  if (AutoAdjustToBrokerTime && g_timeBase != "broker") {
    shiftHours = GetBrokerOffsetAt(now) - GetSourceOffsetAt(now);
  }
  return(midnight + h * 3600 + m * 60 + shiftHours * 3600);
}

string BrokerHHMMOf(string hhmm, datetime now)
{
  datetime t = WallClockToBroker(now, hhmm);
  return(TimeToStr(t, TIME_MINUTES));
}

string OffsetLabel(int hours)
{
  if (hours >= 0) return("GMT+" + IntegerToString(hours));
  return("GMT" + IntegerToString(hours));
}

string DashboardText(datetime now)
{
  int bo = AutoAdjustToBrokerTime ? GetBrokerOffsetAt(now) : CurrentBrokerGMTOffsetHours();
  int so = GetSourceOffsetAt(now);
  string dstState = "off";
  if (g_brokerUsesDST) {
    if (g_brokerDSTType == 1) dstState = IsUSDST(now) ? "US on" : "US off";
    else dstState = IsEUDST(now) ? "EU on" : "EU off";
  }
  string boxB = BrokerHHMMOf(StartTime, now) + "-" + BrokerHHMMOf(EndTime, now);
  string sesB = BrokerHHMMOf(SessionEndTime, now);
  string mode = AutoAdjustToBrokerTime ? ("auto " + g_timeBase + " -> broker") : "raw broker times";

  return(
    VERSION + "\n" +
    "Broker now " + TimeToStr(now, TIME_DATE|TIME_MINUTES) + "  (" + OffsetLabel(bo) + ", DST " + dstState + ")\n" +
    "Times in " + TimesAreSpecifiedIn + "  (" + OffsetLabel(so) + ")   mode: " + mode + "\n" +
    "Box on chart  " + boxB + "     session ends  " + sesB + "\n" +
    "Input box [" + StartTime + "-" + EndTime + "]  session end " + SessionEndTime
  );
}

void DrawDashboardLabel()
{
  string name = objPrefix + "TimeDash";
  if (ObjectFind(name) < 0) ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
  ObjectSet(name, OBJPROP_CORNER, 0);
  ObjectSet(name, OBJPROP_XDISTANCE, 8);
  ObjectSet(name, OBJPROP_YDISTANCE, 16);
  ObjectSet(name, OBJPROP_BACK, false);
  int bo = AutoAdjustToBrokerTime ? GetBrokerOffsetAt(Time[0]) : CurrentBrokerGMTOffsetHours();
  string s = "LB 3.3  " + OffsetLabel(bo) + "  box " +
             BrokerHHMMOf(StartTime, Time[0]) + "-" + BrokerHHMMOf(EndTime, Time[0]) +
             "  end " + BrokerHHMMOf(SessionEndTime, Time[0]);
  ObjectSetText(name, s, 9, "Arial", LevelColor);
}

//+------------------------------------------------------------------+
void compute_LB_Indi_LEVELS(datetime now)
//+------------------------------------------------------------------+
{
  int boxStartShift,boxEndShift;

  if (now >= tSessionStart && now <= tSessionEnd) return;

  // Times are converted from the chosen base (London/GMT/GMT+2/...) onto
  // the broker/chart clock so the session is accurate on any server.
  tBoxStart = WallClockToBroker(now, StartTime);
  tBoxEnd   = WallClockToBroker(now, EndTime);
  if (tBoxStart > tBoxEnd) tBoxStart -= 86400; // midnight wrap fix
  if (now < tBoxEnd) {
    tBoxStart -= 86400;
    tBoxEnd   -= 86400;
    // Re-apply conversion on the previous calendar day (DST-safe)
    tBoxStart = WallClockToBroker(tBoxStart, StartTime);
    tBoxEnd   = WallClockToBroker(tBoxEnd, EndTime);
    if (tBoxStart > tBoxEnd) tBoxStart -= 86400;
    while ((TimeDayOfWeek(tBoxStart)==0 || TimeDayOfWeek(tBoxStart)==6)
        && (TimeDayOfWeek(tBoxEnd)==0 || TimeDayOfWeek(tBoxEnd)==6) ) {
      tBoxStart -= 86400;
      tBoxEnd   -= 86400;
      tBoxStart = WallClockToBroker(tBoxStart, StartTime);
      tBoxEnd   = WallClockToBroker(tBoxEnd, EndTime);
      if (tBoxStart > tBoxEnd) tBoxStart -= 86400;
    }
  }

  tSessionStart = tBoxEnd;
  tSessionEnd   = WallClockToBroker(tSessionStart, SessionEndTime);
  if (tSessionStart > tSessionEnd) tSessionEnd = tSessionEnd + 86400;
  // If the wrap pushed us onto the previous calendar date, rebuild from next day
  if (tSessionEnd <= tSessionStart) {
    tSessionEnd = WallClockToBroker(tSessionStart + 86400, SessionEndTime);
    if (tSessionEnd <= tSessionStart) tSessionEnd = tSessionStart + 86400;
  }
  if (TimeDayOfWeek(tSessionEnd)==6/*saturday*/) tSessionEnd += 2*86400;
  if (TimeDayOfWeek(tSessionEnd)==0/*sunday*/) tSessionEnd += 86400;

  tLastComputedSessionStart = tSessionStart;
  tLastComputedSessionEnd   = tSessionEnd;

  g_startHHMM = TimeToStr(tBoxStart, TIME_MINUTES);
  g_endHHMM   = TimeToStr(tBoxEnd, TIME_MINUTES);
  g_sessHHMM  = TimeToStr(tSessionEnd, TIME_MINUTES);

  boxStartShift = iBarShift(NULL,0,tBoxStart);
  boxEndShift   = iBarShift(NULL,0,tBoxEnd);
  int barsInBox = boxStartShift-boxEndShift+1;
  if (barsInBox < 1) barsInBox = 1;
  boxHigh = High[iHighest(NULL,0,MODE_HIGH,barsInBox,boxEndShift)];
  boxLow  = Low[iLowest(NULL,0,MODE_LOW,barsInBox,boxEndShift)];
  boxMedianPrice = (boxHigh+boxLow)/2;
  boxExtent = boxHigh - boxLow;

  if (boxExtent >= MaxBoxSizeInPips * pip && LimitBoxToMaxSize==true) {
    if (StickBoxToLatestExtreme==true) {
      int boxStartShiftM1 = iBarShift(NULL,PERIOD_M1,tBoxStart);
      int boxEndShiftM1   = iBarShift(NULL,PERIOD_M1,tBoxEnd);
      int boxHighShift    = iHighest(NULL,PERIOD_M1,MODE_HIGH,(boxStartShiftM1-boxEndShiftM1+1),boxEndShiftM1);
      int boxLowShift     = iLowest(NULL,PERIOD_M1,MODE_LOW,(boxStartShiftM1-boxEndShiftM1+1),boxEndShiftM1);
      boxExtent = MaxBoxSizeInPips * pip;
      if (boxHighShift <= boxLowShift) {
        if (StickBoxOusideSRlevels==true) {
          boxMedianPrice = boxHigh + boxExtent/2;
        } else {
          boxMedianPrice = boxHigh - boxExtent/2;
        }
      } else {
        if (StickBoxOusideSRlevels==true) {
          boxMedianPrice = boxLow - boxExtent/2;
        } else {
          boxMedianPrice = boxLow + boxExtent/2;
        }
      }
    } else {
      boxExtent      = MaxBoxSizeInPips * pip;
      boxMedianPrice = iMA(NULL,0,boxStartShift-boxEndShift,0,MODE_EMA,PRICE_MEDIAN,boxEndShift);
    }
  }

  boxExtent *= LevelsResizeFactor;
  boxHigh = NormalizeDouble(boxMedianPrice + boxExtent/2,Digits);
  boxLow  = NormalizeDouble(boxMedianPrice - boxExtent/2,Digits);

  TP1Factor = TP1FactorInput;
  TP3Factor = TP3FactorInput;
  TP5Factor = TP5FactorInput;
  SLFactor  = SLFactorInput;

  BuyEntry  = boxHigh;
  SellEntry = boxLow;

  if (TP1Factor < 10) TP1_pips = boxExtent*TP1Factor/pip;
  else { TP1_pips = TP1Factor; TP1Factor = TP1_pips*pip/boxExtent; }
  BuyTP1  = NormalizeDouble(BuyEntry  + TP1_pips*pip,Digits);
  SellTP1 = NormalizeDouble(SellEntry - TP1_pips*pip,Digits);

  if (TP3Factor < 10) TP3_pips = boxExtent*TP3Factor/pip;
  else { TP3_pips = TP3Factor; TP3Factor = TP3_pips*pip/boxExtent; }
  BuyTP3  = NormalizeDouble(BuyEntry  + TP3_pips*pip,Digits);
  SellTP3 = NormalizeDouble(SellEntry - TP3_pips*pip,Digits);

  TP2Factor = (TP1Factor+TP3Factor)/2;
  if (TP2Factor < 10) TP2_pips = boxExtent*TP2Factor/pip;
  else { TP2_pips = TP2Factor; TP2Factor = TP2_pips*pip/boxExtent; }
  BuyTP2  = NormalizeDouble(BuyEntry  + TP2_pips*pip,Digits);
  SellTP2 = NormalizeDouble(SellEntry - TP2_pips*pip,Digits);

  if (TP5Factor < 10) TP5_pips = boxExtent*TP5Factor/pip;
  else { TP5_pips = TP5Factor; TP5Factor = TP5_pips*pip/boxExtent; }
  BuyTP5  = NormalizeDouble(BuyEntry  + TP5_pips*pip,Digits);
  SellTP5 = NormalizeDouble(SellEntry - TP5_pips*pip,Digits);

  TP4Factor = (TP3Factor+TP5Factor)/2;
  if (TP4Factor < 10) TP4_pips = boxExtent*TP4Factor/pip;
  else { TP4_pips = TP4Factor; TP4Factor = TP4_pips*pip/boxExtent; }
  BuyTP4  = NormalizeDouble(BuyEntry  + TP4_pips*pip,Digits);
  SellTP4 = NormalizeDouble(SellEntry - TP4_pips*pip,Digits);

  if (SLFactor < 10) SL_pips = boxExtent*SLFactor/pip;
  else { SL_pips = SLFactor; SLFactor = SL_pips*pip/boxExtent; }
  BuySL  = NormalizeDouble(BuyEntry  - SL_pips*pip,Digits);
  SellSL = NormalizeDouble(SellEntry + SL_pips*pip,Digits);
}

//+------------------------------------------------------------------+
void show_boxes(datetime now)
//+------------------------------------------------------------------+
{
  static datetime alreadyDrawnS=0;

  drawBoxOnce (objPrefix+"Session-"+TimeToStr(tSessionStart,TIME_DATE | TIME_SECONDS),tSessionStart,0,tSessionEnd,BuyEntry*2,SessionColor,1, STYLE_SOLID, true);

  if (alreadyDrawnS != tBoxEnd) {
    alreadyDrawnS = tBoxEnd;

    string boxName = objPrefix+"Box-"+TimeToStr(tBoxStart,TIME_DATE)+"-"+g_startHHMM+"-"+g_endHHMM;
    if (boxExtent >= MaxBoxSizeInPips * pip) {
      if (LimitBoxToMaxSize==false) {
        drawBox (boxName,tBoxStart,boxLow,tBoxEnd,boxHigh,BoxColorNOK,1, STYLE_SOLID, true);
        DrawLbl(objPrefix+"Lbl-"+TimeToStr(tBoxStart,TIME_DATE)+"-box", "NO TRADE! ("+DoubleToStr(boxExtent/pip,0)+"p)", tBoxStart+(tBoxEnd-tBoxStart)/2,boxLow, 12, "Arial Black", LevelColor, 3);
      } else {
        drawBox (boxName,tBoxStart,boxLow,tBoxEnd,boxHigh,BoxColorMAX,1, STYLE_SOLID, true);
        DrawLbl(objPrefix+"Lbl-"+TimeToStr(tBoxStart,TIME_DATE)+"-box", "MAX LIMIT! ("+DoubleToStr(boxExtent/pip,0)+"p)", tBoxStart+(tBoxEnd-tBoxStart)/2,boxLow, 12, "Arial Black", LevelColor, 3);
      }
    } else if (boxExtent >= MinBoxSizeInPips * pip) {
      drawBox (boxName,tBoxStart,boxLow,tBoxEnd,boxHigh,BoxColorOK,1, STYLE_SOLID, true);
      DrawLbl(objPrefix+"Lbl-"+TimeToStr(tBoxStart,TIME_DATE)+"-box", DoubleToStr(boxExtent/pip,0)+"p", tBoxStart+(tBoxEnd-tBoxStart)/2,boxLow, 12, "Arial Black", LevelColor, 3);
    } else {
      drawBox (boxName,tBoxStart,boxLow,tBoxEnd,boxHigh,BoxColorNOK,1, STYLE_SOLID, true);
      DrawLbl(objPrefix+"Lbl-"+TimeToStr(tBoxStart,TIME_DATE)+"-box", "Caution! ("+DoubleToStr(boxExtent/pip,0)+"p)", tBoxStart+(tBoxEnd-tBoxStart)/2,boxLow, 12, "Arial Black", BoxColorNOK, 3);
    }
    DrawLbl(objPrefix+"Lbl2-"+TimeToStr(tBoxStart,TIME_DATE)+"-box","BO", tBoxStart+(tBoxEnd-tBoxStart)/2,boxLow-6*pip, 24, "Arial Black", LevelColor, 2);

    if (showProfitZone) {
      double UpperTP,LowerTP;
      if (TP5Factor>0) {
        UpperTP = BuyTP5;
        LowerTP = SellTP5;
      } else {
        UpperTP = BuyTP3;
        LowerTP = SellTP3;
      }
      drawBox (objPrefix+"BuyProfitZone-" +TimeToStr(tSessionStart,TIME_DATE),tSessionStart,BuyTP1,tSessionEnd,UpperTP,ProfitColor,1, STYLE_SOLID, true);
      drawBox (objPrefix+"SellProfitZone-"+TimeToStr(tSessionStart,TIME_DATE),tSessionStart,SellTP1,tSessionEnd,LowerTP,ProfitColor,1, STYLE_SOLID, true);
    }

    string objname = objPrefix+"Fibo-" + tBoxEnd;
    ObjectCreate(objname,OBJ_FIBO,0,tBoxStart,SellEntry,tBoxStart+FibLength*60*10,BuyEntry);
    ObjectSet(objname,OBJPROP_RAY,false);
    ObjectSet(objname,OBJPROP_LEVELCOLOR,LevelColor);
    ObjectSet(objname,OBJPROP_FIBOLEVELS,12);
    ObjectSet(objname,OBJPROP_LEVELSTYLE,STYLE_SOLID);
    _SetFibLevel(objname,0,0.0,"Entry Buy= %$");
    _SetFibLevel(objname,1,1.0,"Entry Sell= %$");
    _SetFibLevel(objname,2,-TP1Factor, "Buy Target 1= %$  (+"+DoubleToStr(TP1_pips,0)+"p)");
    _SetFibLevel(objname,3,1+TP1Factor,"Sell Target 1= %$  (+"+DoubleToStr(TP1_pips,0)+"p)");
    _SetFibLevel(objname,4,-TP2Factor, "Buy Target 2= %$  (+"+DoubleToStr(TP2_pips,0)+"p)");
    _SetFibLevel(objname,5,1+TP2Factor,"Sell Target 2= %$  (+"+DoubleToStr(TP2_pips,0)+"p)");
    _SetFibLevel(objname,6,-TP3Factor, "Buy Target 3= %$  (+"+DoubleToStr(TP3_pips,0)+"p)");
    _SetFibLevel(objname,7,1+TP3Factor,"Sell Target 3= %$  (+"+DoubleToStr(TP3_pips,0)+"p)");
    if (TP5Factor>0) {
      _SetFibLevel(objname,8,-TP4Factor, "Buy Target 4= %$  (+"+DoubleToStr(TP4_pips,0)+"p)");
      _SetFibLevel(objname,9,1+TP4Factor,"Sell Target 4= %$  (+"+DoubleToStr(TP4_pips,0)+"p)");
      _SetFibLevel(objname,10,-TP5Factor, "Buy Target 5= %$  (+"+DoubleToStr(TP5_pips,0)+"p)");
      _SetFibLevel(objname,11,1+TP5Factor,"Sell Target 5= %$  (+"+DoubleToStr(TP5_pips,0)+"p)");
    }
  }
}

void _SetFibLevel(string objname, int level, double value, string description)
{
    ObjectSet(objname,OBJPROP_FIRSTLEVEL+level,value);
    ObjectSetFiboDescription(objname,level,description);
}

void getpip()
{
   if(Digits==2 || Digits==4) pip = Point;
   else if(Digits==3 || Digits==5) pip = 10*Point;
   else if(Digits==6) pip = 100*Point;

	if (Digits == 3 || Digits == 2) digits = 2;
	else digits = 4;
}

void RemoveObjects(string Pref)
{
   int i;
   string objname = "";

   for (i = ObjectsTotal(); i >= 0; i--) {
      objname = ObjectName(i);
      if (StringFind(objname, Pref, 0) > -1) ObjectDelete(objname);
   }
}

void drawBox (
  string objname,
  datetime tStart, double vStart,
  datetime tEnd,   double vEnd,
  color c, int width, int style, bool bg
)
{
  if (ObjectFind(objname) == -1) {
    ObjectCreate(objname, OBJ_RECTANGLE, 0, tStart,vStart,tEnd,vEnd);
  } else {
    ObjectSet(objname, OBJPROP_TIME1, tStart);
    ObjectSet(objname, OBJPROP_TIME2, tEnd);
    ObjectSet(objname, OBJPROP_PRICE1, vStart);
    ObjectSet(objname, OBJPROP_PRICE2, vEnd);
  }

  ObjectSet(objname,OBJPROP_COLOR, c);
  ObjectSet(objname, OBJPROP_BACK, bg);
  ObjectSet(objname, OBJPROP_WIDTH, width);
  ObjectSet(objname, OBJPROP_STYLE, style);
}

void drawBoxOnce (
  string objname,
  datetime tStart, double vStart,
  datetime tEnd,   double vEnd,
  color c, int width, int style, bool bg
)
{
  if (ObjectFind(objname) != -1) return;

  ObjectCreate(objname, OBJ_RECTANGLE, 0, tStart,vStart,tEnd,vEnd);
  ObjectSet(objname,OBJPROP_COLOR, c);
  ObjectSet(objname, OBJPROP_BACK, bg);
  ObjectSet(objname, OBJPROP_WIDTH, width);
  ObjectSet(objname, OBJPROP_STYLE, style);
}

void DrawLbl(string objname, string s, int LTime, double LPrice, int FSize, string Font, color c, int width)
{
  if (ObjectFind(objname) < 0) {
    ObjectCreate(objname, OBJ_TEXT, 0, LTime, LPrice);
  } else {
    if (ObjectType(objname) == OBJ_TEXT) {
      ObjectSet(objname, OBJPROP_TIME1, LTime);
      ObjectSet(objname, OBJPROP_PRICE1, LPrice);
    }
  }

  ObjectSet(objname, OBJPROP_FONTSIZE, FSize);
  ObjectSetText(objname, s, FSize, Font, c);
}
//end
