//+------------------------------------------------------------------+
//|                                              TA_FA_Confluence.mq4 |
//|     Technical + Fundamental confluence for MetaTrader 4           |
//|     Classic analysis only. No SMC, ICT, order blocks, FVG, BOS.   |
//+------------------------------------------------------------------+
#property copyright "TA+FA Confluence"
#property link      ""
#property version   "1.00"
#property strict
#property description "Combines classic technical analysis with real fundamental drivers:"
#property description "policy-rate differential, currency strength, intermarket confirmation,"
#property description "session quality and a high-impact news blackout. No SMC/ICT."
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_color1 clrLime
#property indicator_color2 clrRed
#property indicator_color3 C'80,160,230'
#property indicator_color4 C'220,170,70'
#property indicator_color5 C'180,90,200'
#property indicator_width1 2
#property indicator_width2 2
#property indicator_width3 1
#property indicator_width4 1
#property indicator_width5 1

#define IND_PREFIX "TAFA_"

input string            S0 = "========== TECHNICAL =========="; // —
input int               InpEMAFast           = 21;
input int               InpEMAMid            = 50;
input int               InpEMASlow           = 200;
input int               InpMACDFast          = 12;
input int               InpMACDSlow          = 26;
input int               InpMACDSignal        = 9;
input int               InpRSIPeriod         = 14;
input int               InpStochK            = 14;
input int               InpStochD            = 3;
input int               InpStochSlow         = 3;
input int               InpADXPeriod         = 14;
input int               InpATRPeriod         = 14;
input int               InpADXMinTrend       = 18;      // below this = chop, no arrows
input ENUM_TIMEFRAMES   InpHTF1              = PERIOD_H4;
input ENUM_TIMEFRAMES   InpHTF2              = PERIOD_D1;
input bool              InpUseRSIDivergence  = true;
input int               InpSwingLookback     = 40;

input string            S1 = "========== FUNDAMENTAL: POLICY RATES =========="; // update after each CB meeting
input double            InpRateUSD           = 3.75;    // Fed funds (upper bound), Aug 2026
input double            InpRateEUR           = 2.15;    // ECB deposit
input double            InpRateGBP           = 3.75;    // BoE Bank Rate
input double            InpRateJPY           = 1.00;    // BoJ
input double            InpRateCHF           = 0.00;    // SNB
input double            InpRateAUD           = 4.35;    // RBA
input double            InpRateCAD           = 2.25;    // BoC
input double            InpRateNZD           = 2.25;    // RBNZ
input double            InpCarryWeight       = 0.35;    // 0..1 how much rate-diff moves FA

input string            S2 = "========== FUNDAMENTAL: STRENGTH / INTERMARKET =========="; // —
input int               InpStrengthTF        = PERIOD_H1;
input int               InpStrengthBars      = 14;      // ROC lookback for currency strength
input string            InpDollarIndex       = "USDX,DXY,DX";
input string            InpGoldSymbols       = "XAUUSD,GOLD";
input string            InpOilSymbols        = "USOIL,WTI,XTIUSD,UKOIL";
input string            InpRiskSymbols       = "AUDJPY";
input bool              InpUseIntermarket    = true;

input string            S3 = "========== FUNDAMENTAL: NEWS / SESSION =========="; // —
input int               InpBrokerGMTOffset   = 0;       // hours: broker time - GMT
input int               InpNewsBlackoutMin   = 30;      // minutes either side of high-impact
input string            InpCalendarFile      = "economic_calendar.csv";
input bool              InpAutoNFP           = true;    // first Friday of month ~12:30 GMT
input int               InpNFPHourGMT        = 12;
input int               InpNFPMinute         = 30;
input string            InpNextNewsTime      = "";      // optional: "2026.08.28 12:30"
input string            InpNextNewsCcy       = "USD";
input bool              InpSessionFilter     = true;    // arrows only in London/NY (or Tokyo for JPY)

input string            S4 = "========== SCORING / SIGNALS =========="; // —
input int               InpTAWeight          = 55;      // normalised with FA weight
input int               InpFAWeight          = 45;
input int               InpTAMin             = 55;      // min |TA| for an arrow
input int               InpFAMin             = 40;      // min |FA| for an arrow
input int               InpCombinedMin       = 55;
input bool              InpRequireAgreement  = true;    // TA and FA must share direction
input bool              InpRequireMTF        = true;
input int               InpHistoryBars       = 400;     // arrows on closed bars only

input string            S5 = "========== DISPLAY =========="; // —
input bool              InpShowPanel         = true;
input bool              InpShowPivots        = true;
input bool              InpShowEMAs          = true;
input bool              InpShowArrows        = true;
input int               InpPanelX            = 12;
input int               InpPanelY            = 22;
input int               InpPanelWidth        = 304;
input color             InpPanelBg           = C'16,20,28';
input color             InpPanelBorder       = C'42,50,64';
input color             InpBull              = C'46,196,132';
input color             InpBear              = C'232,93,93';
input color             InpMuted             = C'140,148,160';
input color             InpText              = C'228,232,238';
input color             InpAccent            = C'120,176,220';
input color             InpWarn              = C'232,184,72';
input int               InpArrowCodeBuy      = 233;
input int               InpArrowCodeSell     = 234;
input int               InpArrowShiftPts     = 12;

input string            S6 = "========== ALERTS =========="; // —
input bool              InpAlertPopup        = true;
input bool              InpAlertSound        = true;
input bool              InpAlertPush         = false;
input bool              InpAlertEmail        = false;
input string            InpSoundFile         = "alert.wav";

double BuyBuffer[];
double SellBuffer[];
double EmaFastBuf[];
double EmaMidBuf[];
double EmaSlowBuf[];
int    g_pairsFound = 0;

string   g_prefix;
string   g_suffix;
string   g_base;
string   g_quote;
bool     g_isForex;
bool     g_panelCollapsed = false;
string   g_newsEvent = "";
datetime g_newsTime = 0;
string   g_newsCcy = "";
string   g_foundDXY = "";
string   g_foundGold = "";
string   g_foundOil = "";
string   g_foundRisk = "";

struct ScorePack
  {
   double ta;          // -100 .. +100
   double fa;          // -100 .. +100
   double combined;
   double emaScore;
   double macdScore;
   double rsiScore;
   double stochScore;
   double adx;
   double adxPlus;
   double adxMinus;
   double rsi;
   double macdMain;
   double macdSig;
   double macdHist;
   double stochMain;
   double atr;
   double emaF;
   double emaM;
   double emaS;
   int    htf1Dir;     // +1 / -1 / 0
   int    htf2Dir;
   int    swingDiv;    // +1 bull div, -1 bear div, 0 none
   double baseStr;
   double quoteStr;
   double rateDiff;
   double carryScore;
   double strengthScore;
   double interScore;
   int    sessionQ;    // 0 dead, 1 ok, 2 prime
   int    minutesToNews;
   bool   newsBlock;
   bool   chop;
   int    signal;      // +1 buy, -1 sell, 0 none
   string taReason;
   string faReason;
   string blockReason;
  };

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuffer);
   SetIndexBuffer(1, SellBuffer);
   SetIndexBuffer(2, EmaFastBuf);
   SetIndexBuffer(3, EmaMidBuf);
   SetIndexBuffer(4, EmaSlowBuf);
   SetIndexStyle(0, DRAW_ARROW, EMPTY, 2, InpBull);
   SetIndexStyle(1, DRAW_ARROW, EMPTY, 2, InpBear);
   SetIndexStyle(2, InpShowEMAs ? DRAW_LINE : DRAW_NONE, STYLE_SOLID, 1, C'80,160,230');
   SetIndexStyle(3, InpShowEMAs ? DRAW_LINE : DRAW_NONE, STYLE_SOLID, 1, C'220,170,70');
   SetIndexStyle(4, InpShowEMAs ? DRAW_LINE : DRAW_NONE, STYLE_SOLID, 1, C'180,90,200');
   SetIndexArrow(0, InpArrowCodeBuy);
   SetIndexArrow(1, InpArrowCodeSell);
   SetIndexLabel(0, "Buy confluence");
   SetIndexLabel(1, "Sell confluence");
   SetIndexLabel(2, "EMA fast");
   SetIndexLabel(3, "EMA mid");
   SetIndexLabel(4, "EMA slow");
   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   IndicatorShortName("TA+FA Confluence");
   IndicatorDigits(Digits);

   ParseSymbol(Symbol());
   SelectMajors();
   ResolveRelatedSymbols();
   LoadNews();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, IND_PREFIX);
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
   if(rates_total < InpEMASlow + 30)
      return(0);

   if(prev_calculated == 0)
     {
      ArrayInitialize(BuyBuffer, EMPTY_VALUE);
      ArrayInitialize(SellBuffer, EMPTY_VALUE);
      LoadNews();
      ResolveRelatedSymbols();
     }

   int lookback = InpHistoryBars;
   if(lookback > rates_total - InpEMASlow - 5)
      lookback = rates_total - InpEMASlow - 5;

   int start;
   if(prev_calculated <= 0)
      start = rates_total - InpEMASlow - 2;
   else
      start = rates_total - prev_calculated + 1;
   if(start < 1)
      start = 1;

   int i;
   for(i = start; i >= 0; i--)
     {
      EmaFastBuf[i] = SafeMA(Symbol(), Period(), InpEMAFast, MODE_EMA, i);
      EmaMidBuf[i]  = SafeMA(Symbol(), Period(), InpEMAMid,  MODE_EMA, i);
      EmaSlowBuf[i] = SafeMA(Symbol(), Period(), InpEMASlow, MODE_EMA, i);
     }

   int sigStart;
   if(prev_calculated <= 0)
      sigStart = lookback;
   else
      sigStart = rates_total - prev_calculated + 1;
   if(sigStart < 1)
      sigStart = 1;
   if(sigStart > lookback)
      sigStart = lookback;

   for(i = sigStart; i >= 1; i--)
     {
      BuyBuffer[i]  = EMPTY_VALUE;
      SellBuffer[i] = EMPTY_VALUE;
      if(!InpShowArrows)
         continue;

      ScorePack s;
      ComputeScores(Symbol(), Period(), i, s);
      if(s.signal > 0)
         BuyBuffer[i] = low[i] - InpArrowShiftPts * Point;
      else if(s.signal < 0)
         SellBuffer[i] = high[i] + InpArrowShiftPts * Point;
     }

   BuyBuffer[0]  = EMPTY_VALUE;
   SellBuffer[0] = EMPTY_VALUE;

   ScorePack live;
   ComputeScores(Symbol(), Period(), 0, live);

   ScorePack confirmed;
   ComputeScores(Symbol(), Period(), 1, confirmed);

   if(InpShowPanel)
      DrawPanel(live, confirmed);

   if(InpShowPivots)
      DrawPivots();

   MaybeAlert(confirmed);

   return(rates_total);
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == IND_PREFIX + "hdr")
     {
      g_panelCollapsed = !g_panelCollapsed;
      ChartRedraw(0);
     }
  }

//+------------------------------------------------------------------+
//| Symbol helpers                                                    |
//+------------------------------------------------------------------+
void ParseSymbol(const string sym)
  {
   g_prefix = "";
   g_suffix = "";
   g_base = "";
   g_quote = "";
   g_isForex = false;

   string s = sym;
   StringToUpper(s);
   if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0)
     {
      g_base = "XAU";
      g_quote = "USD";
      g_isForex = false;
      return;
     }
   if(StringFind(s, "XAG") >= 0 || StringFind(s, "SILVER") >= 0)
     {
      g_base = "XAG";
      g_quote = "USD";
      g_isForex = false;
      return;
     }
   string ccys[8] = {"EUR","GBP","AUD","NZD","USD","CAD","CHF","JPY"};

   int pos = -1;
   string foundBase = "";
   for(int i = 0; i < 8; i++)
     {
      int p = StringFind(s, ccys[i]);
      if(p >= 0 && (pos < 0 || p < pos))
        {
         pos = p;
         foundBase = ccys[i];
        }
     }
   if(pos < 0)
      return;

   g_prefix = StringSubstr(sym, 0, pos);
   g_base = foundBase;
   string rest = StringSubstr(s, pos + 3);
   for(int j = 0; j < 8; j++)
     {
      if(StringFind(rest, ccys[j]) == 0)
        {
         g_quote = ccys[j];
         int suffixStart = pos + 6;
         if(suffixStart < StringLen(sym))
            g_suffix = StringSubstr(sym, suffixStart);
         g_isForex = true;
         return;
        }
     }

   // metals / others: XAUUSD, XAGUSD
   if(StringLen(rest) >= 3)
     {
      g_quote = StringSubstr(rest, 0, 3);
      if(pos + 6 <= StringLen(sym))
         g_suffix = StringSubstr(sym, pos + 6);
     }
  }

string Pair(const string base, const string quote)
  {
   return(g_prefix + base + quote + g_suffix);
  }

bool MarketHas(const string symbol)
  {
   if(symbol == "" || symbol == NULL)
      return(false);
   if(MarketInfo(symbol, MODE_BID) > 0)
      return(true);
   SymbolSelect(symbol, true);
   return(MarketInfo(symbol, MODE_BID) > 0);
  }

void SelectMajors()
  {
   string b[8] = {"EUR","GBP","AUD","NZD","USD","CAD","CHF","JPY"};
   for(int i = 0; i < 8; i++)
     {
      for(int j = 0; j < 8; j++)
        {
         if(i == j)
            continue;
         SymbolSelect(Pair(b[i], b[j]), true);
        }
     }
   string extra[12] = {"USDX","DXY","DX","XAUUSD","GOLD","USOIL","WTI","XTIUSD","UKOIL","AUDJPY","NAS100","US30"};
   for(int k = 0; k < 12; k++)
     {
      SymbolSelect(extra[k], true);
      SymbolSelect(g_prefix + extra[k] + g_suffix, true);
     }
  }

string FirstExisting(const string csv)
  {
   string parts[];
   int n = StringSplit(csv, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string t = parts[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      if(t == "")
         continue;
      if(MarketHas(t))
         return(t);
      string withAffix = g_prefix + t + g_suffix;
      if(MarketHas(withAffix))
         return(withAffix);
     }
   return("");
  }

void ResolveRelatedSymbols()
  {
   g_foundDXY  = FirstExisting(InpDollarIndex);
   g_foundGold = FirstExisting(InpGoldSymbols);
   g_foundOil  = FirstExisting(InpOilSymbols);
   g_foundRisk = FirstExisting(InpRiskSymbols);
   if(g_foundRisk == "" && MarketHas(Pair("AUD","JPY")))
      g_foundRisk = Pair("AUD","JPY");
  }

double PolicyRate(const string ccy)
  {
   if(ccy == "USD") return(InpRateUSD);
   if(ccy == "EUR") return(InpRateEUR);
   if(ccy == "GBP") return(InpRateGBP);
   if(ccy == "JPY") return(InpRateJPY);
   if(ccy == "CHF") return(InpRateCHF);
   if(ccy == "AUD") return(InpRateAUD);
   if(ccy == "CAD") return(InpRateCAD);
   if(ccy == "NZD") return(InpRateNZD);
   return(EMPTY_VALUE);
  }

//+------------------------------------------------------------------+
double Roc(const string symbol, const int tf, const int shift, const int bars)
  {
   if(symbol == "" || bars <= 0)
      return(0);
   double now = iClose(symbol, tf, shift);
   double then = iClose(symbol, tf, shift + bars);
   if(now <= 0 || then <= 0)
      return(0);
   return((now - then) / then * 100.0);
  }

double SafeMA(const string symbol, const int tf, const int period, const int method, const int shift)
  {
   return(iMA(symbol, tf, period, 0, method, PRICE_CLOSE, shift));
  }

int HtfDir(const string symbol, const int tf, const int shift)
  {
   if(shift < 0)
      return(0);
   double ema = SafeMA(symbol, tf, InpEMAMid, MODE_EMA, shift);
   double px  = iClose(symbol, tf, shift);
   double emaF = SafeMA(symbol, tf, InpEMAFast, MODE_EMA, shift);
   if(ema <= 0 || px <= 0)
      return(0);
   if(px > ema && emaF > ema)
      return(1);
   if(px < ema && emaF < ema)
      return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
//| Currency strength from a 28-pair ROC matrix (market-implied FA)   |
//+------------------------------------------------------------------+
void CurrencyStrength(const int shift, double &eur, double &gbp, double &aud, double &nzd,
                      double &usd, double &cad, double &chf, double &jpy)
  {
   eur = gbp = aud = nzd = usd = cad = chf = jpy = 0;
   int tf = InpStrengthTF;
   int n = InpStrengthBars;
   int cE = 0, cG = 0, cA = 0, cN = 0, cU = 0, cC = 0, cF = 0, cJ = 0;
   if(shift <= 1)
      g_pairsFound = 0;

   AddPairStr("EUR","USD", shift, tf, n, eur, usd, cE, cU);
   AddPairStr("EUR","GBP", shift, tf, n, eur, gbp, cE, cG);
   AddPairStr("EUR","JPY", shift, tf, n, eur, jpy, cE, cJ);
   AddPairStr("EUR","CHF", shift, tf, n, eur, chf, cE, cF);
   AddPairStr("EUR","AUD", shift, tf, n, eur, aud, cE, cA);
   AddPairStr("EUR","CAD", shift, tf, n, eur, cad, cE, cC);
   AddPairStr("EUR","NZD", shift, tf, n, eur, nzd, cE, cN);

   AddPairStr("GBP","USD", shift, tf, n, gbp, usd, cG, cU);
   AddPairStr("GBP","JPY", shift, tf, n, gbp, jpy, cG, cJ);
   AddPairStr("GBP","CHF", shift, tf, n, gbp, chf, cG, cF);
   AddPairStr("GBP","AUD", shift, tf, n, gbp, aud, cG, cA);
   AddPairStr("GBP","CAD", shift, tf, n, gbp, cad, cG, cC);
   AddPairStr("GBP","NZD", shift, tf, n, gbp, nzd, cG, cN);

   AddPairStr("AUD","USD", shift, tf, n, aud, usd, cA, cU);
   AddPairStr("AUD","JPY", shift, tf, n, aud, jpy, cA, cJ);
   AddPairStr("AUD","CHF", shift, tf, n, aud, chf, cA, cF);
   AddPairStr("AUD","CAD", shift, tf, n, aud, cad, cA, cC);
   AddPairStr("AUD","NZD", shift, tf, n, aud, nzd, cA, cN);

   AddPairStr("NZD","USD", shift, tf, n, nzd, usd, cN, cU);
   AddPairStr("NZD","JPY", shift, tf, n, nzd, jpy, cN, cJ);
   AddPairStr("NZD","CHF", shift, tf, n, nzd, chf, cN, cF);
   AddPairStr("NZD","CAD", shift, tf, n, nzd, cad, cN, cC);

   AddPairStr("USD","JPY", shift, tf, n, usd, jpy, cU, cJ);
   AddPairStr("USD","CHF", shift, tf, n, usd, chf, cU, cF);
   AddPairStr("USD","CAD", shift, tf, n, usd, cad, cU, cC);

   AddPairStr("CAD","JPY", shift, tf, n, cad, jpy, cC, cJ);
   AddPairStr("CAD","CHF", shift, tf, n, cad, chf, cC, cF);

   AddPairStr("CHF","JPY", shift, tf, n, chf, jpy, cF, cJ);

   if(cE > 0) eur /= cE;
   if(cG > 0) gbp /= cG;
   if(cA > 0) aud /= cA;
   if(cN > 0) nzd /= cN;
   if(cU > 0) usd /= cU;
   if(cC > 0) cad /= cC;
   if(cF > 0) chf /= cF;
   if(cJ > 0) jpy /= cJ;
  }

void AddPairStr(const string a, const string b, const int shift, const int tf, const int n,
                double &strA, double &strB, int &cntA, int &cntB)
  {
   string sym = Pair(a, b);
   if(!MarketHas(sym))
      return;
   double r = Roc(sym, tf, shift, n);
   strA += r;
   strB -= r;
   cntA++;
   cntB++;
   if(shift <= 1)
      g_pairsFound++;
  }

double StrengthOf(const string ccy, const double eur, const double gbp, const double aud, const double nzd,
                  const double usd, const double cad, const double chf, const double jpy)
  {
   if(ccy == "EUR") return(eur);
   if(ccy == "GBP") return(gbp);
   if(ccy == "AUD") return(aud);
   if(ccy == "NZD") return(nzd);
   if(ccy == "USD") return(usd);
   if(ccy == "CAD") return(cad);
   if(ccy == "CHF") return(chf);
   if(ccy == "JPY") return(jpy);
   return(0);
  }

//+------------------------------------------------------------------+
int RSIDivergence(const string symbol, const int tf, const int shift)
  {
   if(!InpUseRSIDivergence)
      return(0);
   int lb = InpSwingLookback;
   int pHigh1 = -1, pHigh2 = -1, pLow1 = -1, pLow2 = -1;

   for(int i = shift + 3; i < shift + lb - 3; i++)
     {
      if(IsSwingHigh(symbol, tf, i))
        {
         if(pHigh1 < 0) pHigh1 = i;
         else if(pHigh2 < 0) { pHigh2 = i; break; }
        }
     }
   for(int j = shift + 3; j < shift + lb - 3; j++)
     {
      if(IsSwingLow(symbol, tf, j))
        {
         if(pLow1 < 0) pLow1 = j;
         else if(pLow2 < 0) { pLow2 = j; break; }
        }
     }

   double rsi1, rsi2, px1, px2;
   if(pHigh1 > 0 && pHigh2 > 0)
     {
      px1  = iHigh(symbol, tf, pHigh1);
      px2  = iHigh(symbol, tf, pHigh2);
      rsi1 = iRSI(symbol, tf, InpRSIPeriod, PRICE_CLOSE, pHigh1);
      rsi2 = iRSI(symbol, tf, InpRSIPeriod, PRICE_CLOSE, pHigh2);
      if(px1 > px2 && rsi1 < rsi2 && rsi1 < 70)
         return(-1);
     }
   if(pLow1 > 0 && pLow2 > 0)
     {
      px1  = iLow(symbol, tf, pLow1);
      px2  = iLow(symbol, tf, pLow2);
      rsi1 = iRSI(symbol, tf, InpRSIPeriod, PRICE_CLOSE, pLow1);
      rsi2 = iRSI(symbol, tf, InpRSIPeriod, PRICE_CLOSE, pLow2);
      if(px1 < px2 && rsi1 > rsi2 && rsi1 > 30)
         return(1);
     }
   return(0);
  }

bool IsSwingHigh(const string symbol, const int tf, const int i)
  {
   double h = iHigh(symbol, tf, i);
   return(h > iHigh(symbol, tf, i-1) && h > iHigh(symbol, tf, i-2) &&
          h > iHigh(symbol, tf, i+1) && h > iHigh(symbol, tf, i+2));
  }

bool IsSwingLow(const string symbol, const int tf, const int i)
  {
   double l = iLow(symbol, tf, i);
   return(l < iLow(symbol, tf, i-1) && l < iLow(symbol, tf, i-2) &&
          l < iLow(symbol, tf, i+1) && l < iLow(symbol, tf, i+2));
  }

//+------------------------------------------------------------------+
int SessionQuality(const datetime t, const string base, const string quote)
  {
   datetime gmt = t - InpBrokerGMTOffset * 3600;
   MqlDateTime dt;
   TimeToStruct(gmt, dt);
   int h = dt.hour;
   int dow = dt.day_of_week; // 0 Sun
   if(dow == 0 || dow == 6)
      return(0);

   bool tokyo  = (h >= 0 && h < 9);
   bool london = (h >= 7 && h < 16);
   bool ny     = (h >= 12 && h < 21);
   bool overlap = (h >= 12 && h < 16);

   bool jpyPair = (base == "JPY" || quote == "JPY");
   bool audNzd  = (base == "AUD" || quote == "AUD" || base == "NZD" || quote == "NZD");

   if(overlap)
      return(2);
   if(london || ny)
      return(2);
   if((jpyPair || audNzd) && tokyo)
      return(1);
   return(0);
  }

//+------------------------------------------------------------------+
void LoadNews()
  {
   g_newsTime = 0;
   g_newsEvent = "";
   g_newsCcy = "";

   if(InpNextNewsTime != "")
     {
      datetime manual = StringToTime(InpNextNewsTime);
      if(manual > 0)
        {
         g_newsTime = manual;
         g_newsEvent = "manual";
         g_newsCcy = InpNextNewsCcy;
        }
     }

   int h = FileOpen(InpCalendarFile, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h != INVALID_HANDLE)
     {
      datetime now = TimeCurrent();
      datetime best = g_newsTime;
      string bestEv = g_newsEvent;
      string bestCcy = g_newsCcy;
      while(!FileIsEnding(h))
        {
         string tstr = FileReadString(h);
         string ccy  = FileReadString(h);
         string imp  = FileReadString(h);
         string ev   = FileReadString(h);
         if(tstr == "")
            continue;
         StringToLower(imp);
         if(imp != "high" && imp != "3" && imp != "red")
            continue;
         datetime tm = StringToTime(tstr);
         if(tm <= 0)
            continue;
         if(tm + InpNewsBlackoutMin * 60 < now)
            continue;
         if(best == 0 || tm < best)
           {
            best = tm;
            bestEv = ev;
            bestCcy = ccy;
           }
        }
      FileClose(h);
      g_newsTime = best;
      g_newsEvent = bestEv;
      g_newsCcy = bestCcy;
     }

   if(InpAutoNFP)
     {
      datetime nfp = NextNFP();
      if(nfp > 0 && (g_newsTime == 0 || nfp < g_newsTime))
        {
         if(nfp + InpNewsBlackoutMin * 60 >= TimeCurrent())
           {
            g_newsTime = nfp;
            g_newsEvent = "US Non-Farm Payrolls";
            g_newsCcy = "USD";
           }
        }
     }
  }

datetime NextNFP()
  {
   datetime now = TimeCurrent() - InpBrokerGMTOffset * 3600;
   MqlDateTime dt;
   TimeToStruct(now, dt);
   for(int add = 0; add <= 2; add++)
     {
      int y = dt.year;
      int m = dt.mon + add;
      if(m > 12) { m -= 12; y++; }
      datetime first = StringToTime(StringFormat("%04d.%02d.01 00:00", y, m));
      MqlDateTime d1;
      TimeToStruct(first, d1);
      int dow = d1.day_of_week; // 0 Sun .. 5 Fri
      int delta = (5 - dow + 7) % 7;
      datetime friday = first + delta * 86400 + InpNFPHourGMT * 3600 + InpNFPMinute * 60;
      friday += InpBrokerGMTOffset * 3600;
      if(friday + InpNewsBlackoutMin * 60 >= TimeCurrent())
         return(friday);
     }
   return(0);
  }

bool NewsTouchesPair(const string ccy, const string base, const string quote)
  {
   if(ccy == "")
      return(true);
   string u = ccy;
   StringToUpper(u);
   if(u == "ALL" || u == "USDOLLAR" || u == "USD")
     {
      // USD news moves almost every major
      if(base == "USD" || quote == "USD")
         return(true);
      return(true);
     }
   return(u == base || u == quote);
  }

void NewsState(const datetime barTime, const string base, const string quote, int &mins, bool &block)
  {
   mins = 99999;
   block = false;
   if(g_newsTime == 0)
      return;
   int diff = (int)MathAbs((long)(g_newsTime - barTime)) / 60;
   int signedMin = (int)((g_newsTime - barTime) / 60);
   mins = signedMin;
   if(NewsTouchesPair(g_newsCcy, base, quote) && diff <= InpNewsBlackoutMin)
      block = true;
  }

//+------------------------------------------------------------------+
double Clamp(const double v, const double lo, const double hi)
  {
   if(v < lo) return(lo);
   if(v > hi) return(hi);
   return(v);
  }

double ScaleRocToScore(const double roc, const double scale)
  {
   return(Clamp(roc / scale * 100.0, -100.0, 100.0));
  }

//+------------------------------------------------------------------+
void ComputeScores(const string symbol, const int tf, const int shift, ScorePack &s)
  {
   ZeroMemory(s);
   s.minutesToNews = 99999;
   s.taReason = "";
   s.faReason = "";
   s.blockReason = "";

   s.emaF = SafeMA(symbol, tf, InpEMAFast, MODE_EMA, shift);
   s.emaM = SafeMA(symbol, tf, InpEMAMid,  MODE_EMA, shift);
   s.emaS = SafeMA(symbol, tf, InpEMASlow, MODE_EMA, shift);
   double px = iClose(symbol, tf, shift);
   s.rsi = iRSI(symbol, tf, InpRSIPeriod, PRICE_CLOSE, shift);
   s.macdMain = iMACD(symbol, tf, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, shift);
   s.macdSig  = iMACD(symbol, tf, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, shift);
   s.macdHist = s.macdMain - s.macdSig;
   s.stochMain = iStochastic(symbol, tf, InpStochK, InpStochD, InpStochSlow, MODE_SMA, 0, MODE_MAIN, shift);
   s.adx = iADX(symbol, tf, InpADXPeriod, PRICE_CLOSE, MODE_MAIN, shift);
   s.adxPlus = iADX(symbol, tf, InpADXPeriod, PRICE_CLOSE, MODE_PLUSDI, shift);
   s.adxMinus = iADX(symbol, tf, InpADXPeriod, PRICE_CLOSE, MODE_MINUSDI, shift);
   s.atr = iATR(symbol, tf, InpATRPeriod, shift);
   datetime bt = iTime(symbol, tf, shift);
   s.htf1Dir = HtfDir(symbol, InpHTF1, iBarShift(symbol, InpHTF1, bt, false));
   s.htf2Dir = HtfDir(symbol, InpHTF2, iBarShift(symbol, InpHTF2, bt, false));
   s.swingDiv = RSIDivergence(symbol, tf, shift);
   s.chop = (s.adx < InpADXMinTrend);

   // --- Technical ---
   double stack = 0;
   if(s.emaF > s.emaM && s.emaM > s.emaS) stack = 100;
   else if(s.emaF < s.emaM && s.emaM < s.emaS) stack = -100;
   else if(s.emaF > s.emaM) stack = 40;
   else if(s.emaF < s.emaM) stack = -40;

   double pxEma = 0;
   if(px > s.emaF && px > s.emaM) pxEma = 80;
   else if(px < s.emaF && px < s.emaM) pxEma = -80;
   else if(px > s.emaM) pxEma = 25;
   else pxEma = -25;

   double emaPrev = SafeMA(symbol, tf, InpEMAMid, MODE_EMA, shift + 3);
   double slope = 0;
   if(emaPrev > 0)
      slope = Clamp((s.emaM - emaPrev) / emaPrev / 0.002 * 100.0, -100, 100);

   s.emaScore = Clamp(0.45 * stack + 0.35 * pxEma + 0.20 * slope, -100, 100);

   double macdZero = (s.macdMain > 0 ? 70 : -70);
   double macdHistS = (s.macdHist > 0 ? 40 : -40);
   double histPrev = iMACD(symbol, tf, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_MAIN, shift + 1)
                   - iMACD(symbol, tf, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE, MODE_SIGNAL, shift + 1);
   if(s.macdHist > histPrev) macdHistS += 20;
   else macdHistS -= 20;
   s.macdScore = Clamp(0.6 * macdZero + 0.4 * macdHistS, -100, 100);

   s.rsiScore = Clamp((s.rsi - 50.0) * 2.4, -100, 100);
   // fade extremes: RSI>75 in a long is stretched, not a fresh buy
   if(s.rsi > 75) s.rsiScore = 25;
   if(s.rsi < 25) s.rsiScore = -25;

   s.stochScore = Clamp((s.stochMain - 50.0) * 2.0, -100, 100);
   if(s.stochMain > 85) s.stochScore = 20;
   if(s.stochMain < 15) s.stochScore = -20;

   double di = 0;
   if(s.adxPlus > s.adxMinus) di = 50;
   else if(s.adxPlus < s.adxMinus) di = -50;

   s.ta = 0.34 * s.emaScore + 0.26 * s.macdScore + 0.16 * s.rsiScore + 0.10 * s.stochScore + 0.14 * di;
   if(s.swingDiv > 0) s.ta += 8;
   if(s.swingDiv < 0) s.ta -= 8;
   s.ta = Clamp(s.ta, -100, 100);

   s.taReason = "EMA stack " + (stack > 0 ? "bull" : (stack < 0 ? "bear" : "mixed"));
   if(s.chop)
      s.taReason = s.taReason + " | ADX chop";

   // --- Fundamental ---
   double eur,gbp,aud,nzd,usd,cad,chf,jpy;
   CurrencyStrength(shift, eur, gbp, aud, nzd, usd, cad, chf, jpy);
   s.baseStr  = StrengthOf(g_base,  eur,gbp,aud,nzd,usd,cad,chf,jpy);
   s.quoteStr = StrengthOf(g_quote, eur,gbp,aud,nzd,usd,cad,chf,jpy);

   if(g_isForex)
      s.strengthScore = Clamp((s.baseStr - s.quoteStr) / 0.35 * 100.0, -100, 100);
   else
      s.strengthScore = 0;

   double rb = PolicyRate(g_base);
   double rq = PolicyRate(g_quote);
   if(rb != EMPTY_VALUE && rq != EMPTY_VALUE)
     {
      s.rateDiff = rb - rq;
      // carry is a slow bias, not a trigger — cap its influence
      s.carryScore = Clamp(s.rateDiff / 3.0 * 100.0, -70, 70);
     }
   else
     {
      s.rateDiff = 0;
      s.carryScore = 0;
     }

   s.interScore = 0;
   if(InpUseIntermarket)
     {
      if(g_quote == "USD" && g_foundDXY != "")
         s.interScore += ScaleRocToScore(-Roc(g_foundDXY, InpStrengthTF, shift, InpStrengthBars), 1.2);
      if(g_base == "USD" && g_foundDXY != "")
         s.interScore += ScaleRocToScore(Roc(g_foundDXY, InpStrengthTF, shift, InpStrengthBars), 1.2);

      // commodity currencies
      if(g_foundOil != "" && (g_base == "CAD" || g_quote == "CAD"))
        {
         double oil = ScaleRocToScore(Roc(g_foundOil, InpStrengthTF, shift, InpStrengthBars), 4.0);
         if(g_quote == "CAD") s.interScore -= 0.7 * oil; // USDCAD falls when oil/CAD rises
         if(g_base == "CAD")  s.interScore += 0.7 * oil;
        }
      if(g_foundGold != "" && (g_base == "AUD" || g_quote == "AUD"))
        {
         double gld = ScaleRocToScore(Roc(g_foundGold, InpStrengthTF, shift, InpStrengthBars), 3.0);
         if(g_base == "AUD")  s.interScore += 0.5 * gld;
         if(g_quote == "AUD") s.interScore -= 0.5 * gld;
        }
      // gold chart itself: inverse dollar
      if(StringFind(Symbol(), "XAU") >= 0 || StringFind(Symbol(), "GOLD") >= 0)
        {
         if(g_foundDXY != "")
            s.interScore = ScaleRocToScore(-Roc(g_foundDXY, InpStrengthTF, shift, InpStrengthBars), 1.0);
        }
      s.interScore = Clamp(s.interScore, -100, 100);
     }

   double cw = Clamp(InpCarryWeight, 0, 1);
   if(g_isForex)
      s.fa = Clamp((1.0 - cw) * (0.70 * s.strengthScore + 0.30 * s.interScore) + cw * s.carryScore, -100, 100);
   else
      s.fa = Clamp(0.80 * s.interScore + 0.20 * s.carryScore, -100, 100);

   s.faReason = "str " + DoubleToString(s.baseStr - s.quoteStr, 2) +
                " | carry " + DoubleToString(s.rateDiff, 2) + "%";

   datetime t = iTime(symbol, tf, shift);
   s.sessionQ = SessionQuality(t, g_base, g_quote);
   NewsState(t, g_base, g_quote, s.minutesToNews, s.newsBlock);

   double tw = (double)InpTAWeight;
   double fw = (double)InpFAWeight;
   if(tw + fw <= 0) { tw = 55; fw = 45; }
   s.combined = Clamp((tw * s.ta + fw * s.fa) / (tw + fw), -100, 100);

   // --- Signal rules (closed-bar logic applied by caller via shift) ---
   s.signal = 0;
   s.blockReason = "";
   if(s.newsBlock)
      s.blockReason = "news blackout";
   else if(s.chop)
      s.blockReason = "ADX chop";
   else if(InpSessionFilter && s.sessionQ <= 0)
      s.blockReason = "dead session";
   else if(InpRequireMTF && (s.htf1Dir == 0 || s.htf2Dir == 0 || s.htf1Dir != s.htf2Dir))
      s.blockReason = "HTF not aligned";
   else
     {
      int dir = 0;
      if(s.ta >= InpTAMin && s.fa >= InpFAMin && s.combined >= InpCombinedMin)
         dir = 1;
      if(s.ta <= -InpTAMin && s.fa <= -InpFAMin && s.combined <= -InpCombinedMin)
         dir = -1;
      if(dir != 0 && InpRequireAgreement)
        {
         if((dir > 0 && (s.ta < 0 || s.fa < 0)) || (dir < 0 && (s.ta > 0 || s.fa > 0)))
            dir = 0;
        }
      if(dir != 0 && InpRequireMTF && s.htf1Dir != dir)
         dir = 0;
      if(dir != 0 && InpRequireMTF && s.htf2Dir != dir)
         dir = 0;
      // stretched RSI: do not fire a fresh with-trend arrow into exhaustion
      if(dir > 0 && s.rsi >= 78) dir = 0;
      if(dir < 0 && s.rsi <= 22) dir = 0;
      s.signal = dir;
      if(s.signal == 0)
         s.blockReason = "no confluence";
     }
  }

//+------------------------------------------------------------------+
void MaybeAlert(const ScorePack &s)
  {
   if(s.signal == 0)
      return;
   datetime t = iTime(Symbol(), Period(), 1);
   static datetime lastT = 0;
   if(t == lastT)
      return;
   lastT = t;

   string dir = (s.signal > 0 ? "BUY" : "SELL");
   string msg = "TA+FA " + dir + " " + Symbol() + " " + TFName(Period()) +
                " | TA " + DoubleToString(s.ta, 0) +
                " FA " + DoubleToString(s.fa, 0) +
                " combo " + DoubleToString(s.combined, 0);
   if(InpAlertPopup)
      Alert(msg);
   if(InpAlertSound)
      PlaySound(InpSoundFile);
   if(InpAlertPush)
      SendNotification(msg);
   if(InpAlertEmail)
      SendMail("TA+FA " + dir + " " + Symbol(), msg);
  }

string TFName(const int tf)
  {
   if(tf == PERIOD_M1) return("M1");
   if(tf == PERIOD_M5) return("M5");
   if(tf == PERIOD_M15) return("M15");
   if(tf == PERIOD_M30) return("M30");
   if(tf == PERIOD_H1) return("H1");
   if(tf == PERIOD_H4) return("H4");
   if(tf == PERIOD_D1) return("D1");
   if(tf == PERIOD_W1) return("W1");
   if(tf == PERIOD_MN1) return("MN");
   return(IntegerToString(tf));
  }

string DirWord(const double v, const double dead)
  {
   if(v >= dead) return("BULL");
   if(v <= -dead) return("BEAR");
   return("NEUT");
  }

color DirColor(const double v, const double dead)
  {
   if(v >= dead) return(InpBull);
   if(v <= -dead) return(InpBear);
   return(InpMuted);
  }

string Bar(const double v)
  {
   // v -100..100 -> 10 char meter
   int n = (int)MathRound((v + 100.0) / 20.0);
   if(n < 0) n = 0;
   if(n > 10) n = 10;
   string s = "";
   for(int i = 0; i < 10; i++)
      s += (i < n ? "|" : ".");
   return(s);
  }

//+------------------------------------------------------------------+
void DrawPanel(const ScorePack &live, const ScorePack &cnf)
  {
   int x = InpPanelX;
   int y = InpPanelY;
   int w = InpPanelWidth;
   int row = 16;
   int h = g_panelCollapsed ? 52 : 392;

   Rect(IND_PREFIX + "bg", x, y, w, h, InpPanelBg, InpPanelBorder);
   Label(IND_PREFIX + "hdr", x + 10, y + 6, "TA + FA  CONFLUENCE", InpAccent, 10);
   ObjectSetInteger(0, IND_PREFIX + "hdr", OBJPROP_SELECTABLE, true);
   Label(IND_PREFIX + "sub", x + 10, y + 24,
         Symbol() + "  " + TFName(Period()) + "   click title to fold",
         InpMuted, 8);

   if(g_panelCollapsed)
      return;

   int yy = y + 48;
   string bias = "NO TRADE";
   color bc = InpMuted;
   if(cnf.signal > 0) { bias = "BUY  (confirmed close)"; bc = InpBull; }
   else if(cnf.signal < 0) { bias = "SELL  (confirmed close)"; bc = InpBear; }
   else if(StringLen(cnf.blockReason) > 0) bias = "WAIT  — " + cnf.blockReason;

   Label(IND_PREFIX + "bias", x + 10, yy, "SIGNAL  " + bias, bc, 9);
   yy += 22;

   Label(IND_PREFIX + "taL", x + 10, yy, "TA  " + DoubleToString(live.ta, 0), DirColor(live.ta, 20), 9);
   Label(IND_PREFIX + "taB", x + 78, yy, Bar(live.ta), DirColor(live.ta, 20), 9);
   yy += row;
   Label(IND_PREFIX + "faL", x + 10, yy, "FA  " + DoubleToString(live.fa, 0), DirColor(live.fa, 20), 9);
   Label(IND_PREFIX + "faB", x + 78, yy, Bar(live.fa), DirColor(live.fa, 20), 9);
   yy += row;
   Label(IND_PREFIX + "coL", x + 10, yy, "SUM " + DoubleToString(live.combined, 0), DirColor(live.combined, 20), 9);
   Label(IND_PREFIX + "coB", x + 78, yy, Bar(live.combined), DirColor(live.combined, 20), 9);
   yy += row + 6;

   Label(IND_PREFIX + "secT", x + 10, yy, "TECHNICAL  (classic)", InpAccent, 8);
   yy += row;
   Label(IND_PREFIX + "ema", x + 10, yy,
         "EMA " + IntegerToString(InpEMAFast) + "/" + IntegerToString(InpEMAMid) + "/" + IntegerToString(InpEMASlow) +
         "   " + DirWord(live.emaScore, 25) +
         "   px " + DoubleToString(iClose(Symbol(), Period(), 0), Digits),
         DirColor(live.emaScore, 25), 8);
   yy += row;
   Label(IND_PREFIX + "macd", x + 10, yy,
         "MACD hist " + DoubleToString(live.macdHist / Point, 1) + " pt   " + DirWord(live.macdScore, 20),
         DirColor(live.macdScore, 20), 8);
   yy += row;
   Label(IND_PREFIX + "rsi", x + 10, yy,
         "RSI " + DoubleToString(live.rsi, 1) +
         "   Stoch " + DoubleToString(live.stochMain, 1) +
         (live.swingDiv > 0 ? "   bull div" : (live.swingDiv < 0 ? "   bear div" : "")),
         DirColor(live.rsiScore, 20), 8);
   yy += row;
   string adxState = live.chop ? "CHOP — no arrows" : (live.adxPlus > live.adxMinus ? "trend up" : "trend down");
   Label(IND_PREFIX + "adx", x + 10, yy,
         "ADX " + DoubleToString(live.adx, 1) +
         "  +DI " + DoubleToString(live.adxPlus, 1) +
         "  -DI " + DoubleToString(live.adxMinus, 1) + "  " + adxState,
         live.chop ? InpWarn : DirColor(live.adxPlus - live.adxMinus, 2), 8);
   yy += row;
   Label(IND_PREFIX + "htf", x + 10, yy,
         "HTF " + TFName(InpHTF1) + " " + DirTxt(live.htf1Dir) +
         "    " + TFName(InpHTF2) + " " + DirTxt(live.htf2Dir),
         (live.htf1Dir != 0 && live.htf1Dir == live.htf2Dir) ? InpBull : InpWarn, 8);
   yy += row + 6;

   Label(IND_PREFIX + "secF", x + 10, yy, "FUNDAMENTAL  (rates, strength, intermarket)", InpAccent, 8);
   yy += row;
   if(g_isForex)
     {
      Label(IND_PREFIX + "str", x + 10, yy,
            g_base + " str " + DoubleToString(live.baseStr, 2) +
            "    " + g_quote + " str " + DoubleToString(live.quoteStr, 2) +
            "    diff " + DoubleToString(live.baseStr - live.quoteStr, 2),
            DirColor(live.strengthScore, 20), 8);
      yy += row;
      Label(IND_PREFIX + "rate", x + 10, yy,
            "Policy " + g_base + " " + DoubleToString(PolicyRate(g_base), 2) +
            "%  -  " + g_quote + " " + DoubleToString(PolicyRate(g_quote), 2) +
            "%   carry " + (live.rateDiff >= 0 ? "+" : "") + DoubleToString(live.rateDiff, 2) + "%",
            DirColor(live.carryScore, 15), 8);
      yy += row;
     }
   else
     {
      Label(IND_PREFIX + "str", x + 10, yy, "Not a G8 FX pair — FA uses intermarket only", InpMuted, 8);
      yy += row;
      Label(IND_PREFIX + "rate", x + 10, yy, " ", InpMuted, 8);
      yy += row;
     }

   string im = "Intermarket  ";
   if(g_foundDXY != "") im += "DXY " + DoubleToString(Roc(g_foundDXY, InpStrengthTF, 0, InpStrengthBars), 2) + "%  ";
   else im += "DXY n/a  ";
   if(g_foundGold != "") im += "XAU " + DoubleToString(Roc(g_foundGold, InpStrengthTF, 0, InpStrengthBars), 2) + "%  ";
   if(g_foundOil != "") im += "OIL " + DoubleToString(Roc(g_foundOil, InpStrengthTF, 0, InpStrengthBars), 2) + "%";
   Label(IND_PREFIX + "im", x + 10, yy, im, DirColor(live.interScore, 15), 8);
   yy += row;

   string sess = (live.sessionQ >= 2 ? "London/NY  (good liquidity)" :
                 (live.sessionQ == 1 ? "Tokyo  (ok for JPY/AUD)" : "Thin session"));
   Label(IND_PREFIX + "sess", x + 10, yy, "Session  " + sess, live.sessionQ > 0 ? InpText : InpWarn, 8);
   yy += row;

   string news;
   if(g_newsTime == 0)
      news = "News  no high-impact loaded";
   else
     {
      int m = live.minutesToNews;
      string when = (m >= 0 ? ("in " + IntegerToString(m) + " min") : (IntegerToString(-m) + " min ago"));
      news = "News  " + g_newsCcy + "  " + g_newsEvent + "  " + when;
      if(live.newsBlock) news = "NEWS BLACKOUT  " + news;
     }
   Label(IND_PREFIX + "news", x + 10, yy, Cut(news, 44), live.newsBlock ? InpBear : InpText, 8);
   yy += row + 6;

   double sl = live.atr * 1.5;
   double tp = live.atr * 3.0;
   Label(IND_PREFIX + "risk", x + 10, yy,
         "ATR " + DoubleToString(live.atr / Point, 1) + " pt   SL~1.5 ATR " +
         DoubleToString(sl / Point, 1) + "   TP~2R " + DoubleToString(tp / Point, 1),
         InpMuted, 8);
   yy += row;
   Label(IND_PREFIX + "note", x + 10, yy,
         "Arrows = closed bar, TA+FA agree, HTF aligned. Not a holy grail.",
         InpMuted, 8);
   yy += row;
   Label(IND_PREFIX + "note2", x + 10, yy,
         "Rates: update after FOMC/ECB. Strength pairs in Market Watch: " +
         IntegerToString(g_pairsFound) + "/28",
         (g_pairsFound >= 20 ? InpMuted : InpWarn), 8);
  }

string DirTxt(const int d)
  {
   if(d > 0) return("BULL");
   if(d < 0) return("BEAR");
   return("FLAT");
  }

string Cut(const string s, const int n)
  {
   if(StringLen(s) <= n)
      return(s);
   return(StringSubstr(s, 0, n - 1) + ".");
  }

void Rect(const string name, const int x, const int y, const int w, const int h, const color bg, const color bd)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, bd);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
  }

void Label(const string name, const int x, const int y, const string text, const color clr, const int sz)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
  }

void DrawPivots()
  {
   // Classic floor-trader pivots from the previous daily bar. Institutional S/R, not ICT.
   double h = iHigh(Symbol(), PERIOD_D1, 1);
   double l = iLow(Symbol(), PERIOD_D1, 1);
   double c = iClose(Symbol(), PERIOD_D1, 1);
   if(h <= 0 || l <= 0 || c <= 0)
      return;
   double pp = (h + l + c) / 3.0;
   double r1 = 2.0 * pp - l;
   double s1 = 2.0 * pp - h;
   double r2 = pp + (h - l);
   double s2 = pp - (h - l);
   double r3 = h + 2.0 * (pp - l);
   double s3 = l - 2.0 * (h - pp);

   datetime t0 = iTime(Symbol(), PERIOD_D1, 0);
   datetime t1 = t0 + TfSeconds(PERIOD_D1);
   PivotLine("PP", pp, C'200,200,210', t0, t1);
   PivotLine("R1", r1, C'220,120,120', t0, t1);
   PivotLine("R2", r2, C'180,80,80', t0, t1);
   PivotLine("S1", s1, C'80,180,130', t0, t1);
   PivotLine("S2", s2, C'50,140,100', t0, t1);
   PivotLine("R3", r3, C'140,60,60', t0, t1);
   PivotLine("S3", s3, C'40,110,80', t0, t1);
  }

void PivotLine(const string tag, const double price, const color clr, const datetime t0, const datetime t1)
  {
   string name = IND_PREFIX + "PV_" + tag;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t1, price);
   ObjectMove(0, name, 0, t0, price);
   ObjectMove(0, name, 1, t1, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   string lb = IND_PREFIX + "PVL_" + tag;
   if(ObjectFind(0, lb) < 0)
      ObjectCreate(0, lb, OBJ_TEXT, 0, t1, price);
   ObjectMove(0, lb, 0, t1, price);
   ObjectSetString(0, lb, OBJPROP_TEXT, " " + tag + " " + DoubleToString(price, Digits));
   ObjectSetInteger(0, lb, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lb, OBJPROP_FONTSIZE, 7);
   ObjectSetString(0, lb, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, lb, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, lb, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, lb, OBJPROP_HIDDEN, true);
  }

int TfSeconds(const int tf)
  {
   if(tf == PERIOD_M1) return(60);
   if(tf == PERIOD_M5) return(300);
   if(tf == PERIOD_M15) return(900);
   if(tf == PERIOD_M30) return(1800);
   if(tf == PERIOD_H1) return(3600);
   if(tf == PERIOD_H4) return(14400);
   if(tf == PERIOD_D1) return(86400);
   if(tf == PERIOD_W1) return(604800);
   return(Period() * 60);
  }
//+------------------------------------------------------------------+
