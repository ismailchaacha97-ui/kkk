//+------------------------------------------------------------------+
//|                                     LiquiditySweep_Portfolio.mq4 |
//|          Liquidity-sweep / failed-breakout Expert Advisor (MT4)  |
//+------------------------------------------------------------------+
//|  CONCEPT
//|  -------
//|  Stops and breakout orders cluster at obvious levels: the previous
//|  day's extreme, the previous week's extreme, confirmed swing highs
//|  and lows.  Price is pushed through such a level, the breakout
//|  traders get filled, and the move fails.  When the raid happens on
//|  above-median tick volume and the bar closes back inside the old
//|  range, this EA trades the reversal:
//|
//|      raid ABOVE a resistance level + close back BELOW it  -> SHORT
//|      raid BELOW a support level    + close back ABOVE it  -> LONG
//|
//|  There is not a single moving average or oscillator in the signal
//|  path.  The EA only uses raw price geometry, market structure
//|  (the sequence of confirmed swing pivots) and tick volume relative
//|  to its own rolling median.  Nothing repaints: every decision is
//|  taken on the close of a finished H1 bar and filled immediately
//|  with a market order, so the entry price is the Open of bar 0.
//|
//|  RISK MODEL
//|  ----------
//|  * fixed-fractional sizing: every position risks InpRiskPercent of
//|    equity measured to its protective stop;
//|  * stop goes just beyond the sweep extreme (ATR buffer);
//|  * take profit at InpRR * risk, break-even at +InpBEatR, optional
//|    chandelier trail, time stop;
//|  * portfolio guards: maximum concurrent positions, one position per
//|    symbol, per-symbol daily signal cap, daily soft/hard loss stops,
//|    weekly loss stop, weekend flat, spread guard, margin guard.
//|
//|  USAGE
//|  -----
//|  This is a portfolio EA.  Attach it to ONE H1 chart (any symbol)
//|  and list the instruments to trade in InpSymbols.  All symbols must
//|  be available in Market Watch (the EA selects them itself) and H1
//|  history must be downloaded for each of them.
//|
//|  The behaviour is a literal translation of the reference Python
//|  engine in backtest/ of this repository.  See README.md and
//|  docs/VALIDATION.md before running it on a live account.
//+------------------------------------------------------------------+
#property copyright "Arena agent build"
#property version   "1.20"
#property strict
#property description "Liquidity-sweep reversal EA, H1, portfolio risk control."

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string InpSymbols              = "EURUSD,GBPUSD,AUDUSD,USDJPY,XAUUSD"; // Symbols (comma separated)
input int    InpMagicNumber          = 20251001;  // Magic number (unique per instance)
input int    InpSlippagePips         = 2;         // Max slippage (pips)

input string SEC_1                   = "--- Setup ---";           // SETUP
input int    InpPivotK               = 3;         // Swing pivot strength (bars each side)
input int    InpPivotLookback        = 400;       // Bars scanned for the last two swing pivots
input int    InpLevelCooldown        = 12;        // Level must be untouched for N bars
input bool   InpUsePrevDay           = true;      // Use previous day high/low
input bool   InpUsePrevWeek          = true;      // Use previous week high/low
input bool   InpUseSwing             = true;      // Use confirmed swing pivots
input int    InpLevelMode            = 1;         // 1=any level, 0=only the extreme level
input int    InpMinRangeATR          = 55;        // Min signal-bar range (percent of ATR)
input int    InpCloseFrac            = 55;        // Close must be in top/bottom x% of the bar
input bool   InpVolumeConfirm        = false;     // Require volume confirmation
input int    InpVolLookback          = 50;        // Volume median lookback (bars)
input int    InpVolMultPct           = 130;       // Volume must be >= x% of the median
input int    InpMaxPenetrationPct    = 25;        // Max raid depth beyond the level (% of ATR, 0 = off)
input bool   InpRequireStructure     = true;      // Only trade with structure direction
input int    InpATRPeriod            = 14;        // ATR period (mean true range)

input string SEC_2                   = "--- Exits ---";           // EXITS
input double InpRR                   = 1.8;       // Take profit (R multiple)
input double InpSlATRBuffer          = 0.35;      // Stop buffer beyond sweep extreme (ATR)
input double InpMinSlATR             = 0.55;      // Minimum stop distance (ATR)
input double InpMaxSlATR             = 3.20;      // Maximum stop distance (ATR)
input double InpBEatR                = 0.9;       // Break-even at +xR (0 = off)
input double InpTrailATR             = 0.0;       // Chandelier trail (ATR multiple, 0 = off)
input int    InpMaxHoldBars          = 48;        // Time stop (H1 bars, 0 = off)

input string SEC_3                   = "--- Risk ---";            // RISK
input double InpRiskPercent          = 0.25;      // Risk per trade (% of equity)
input int    InpMaxPositions         = 3;         // Max concurrent positions (portfolio)
input int    InpMaxSignalsPerDay     = 2;         // Max entries per symbol per day
input double InpDailyStopPct         = 1.5;       // Stop opening trades after -x% today
input double InpDailyHardStopPct     = 2.5;       // Flatten everything after -x% today (0=off)
input double InpWeeklyStopPct        = 0.0;       // Stop for the week after -x% (0=off)
input double InpMaxMarginUsePct      = 20.0;      // Max margin used per position (% of equity)
input bool   InpCompound             = true;      // Size from equity (false = from balance)

input string SEC_4                   = "--- Session ---";         // SESSION
input int    InpGMTOffsetHours       = 2;         // Broker server GMT offset (hours)
input int    InpSessionStartUTC      = 7;         // Session start, UTC hour (inclusive)
input int    InpSessionEndUTC        = 18;        // Session end, UTC hour (exclusive)
input bool   InpTradeMonday          = true;      // Allow Monday
input bool   InpTradeFriday          = true;      // Allow Friday
input int    InpFridayCloseHourUTC   = 20;        // Close EA positions after this UTC hour on Friday (99=off)

input string SEC_5                   = "--- Execution ---";       // EXECUTION
input double InpMaxSpreadPips        = 2.0;       // Max spread for FX pairs (pips)
input double InpMaxSpreadPipsGold    = 5.0;       // Max spread for gold / metals (pips)
input int    InpOrderRetries         = 3;         // Order send retries
input int    InpRetrySleepMs         = 500;       // Pause between retries (ms)
input bool   InpShowDashboard        = true;      // Show dashboard comment
input bool   InpVerboseLog           = false;     // Verbose journal logging

//+------------------------------------------------------------------+
//| Constants / globals                                              |
//+------------------------------------------------------------------+
#define MAX_SYMBOLS 16

string   g_sym[MAX_SYMBOLS];
double   g_pip[MAX_SYMBOLS];
double   g_lotSize[MAX_SYMBOLS];
bool     g_isGold[MAX_SYMBOLS];
int      g_nsym = 0;

datetime g_lastH1Bar[MAX_SYMBOLS];
int      g_dayCount[MAX_SYMBOLS];
datetime g_curDay = 0;
int      g_curWeek = -1;

double   g_dayStartEquity = 0.0;
double   g_weekStartEquity = 0.0;
double   g_startEquity = 0.0;
bool     g_haltedDay = false;
bool     g_haltedWeek = false;

// candidate buffer for cross-symbol ranking
int      g_cIdx[MAX_SYMBOLS];
int      g_cSide[MAX_SYMBOLS];
double   g_cSL[MAX_SYMBOLS];
double   g_cScore[MAX_SYMBOLS];
int      g_nCand = 0;

string   g_gvDay, g_gvWeek;
datetime g_lastClock = 0;
datetime g_lastDash = 0;

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool IsGoldSymbol(const string s)
{
   if(StringFind(s, "XAU") >= 0) return true;
   if(StringFind(s, "GOLD") >= 0) return true;
   if(StringFind(s, "XAG") >= 0) return true;
   if(StringFind(s, "XPT") >= 0) return true;
   return false;
}

double PointOf(const int i)
{
   return MarketInfo(g_sym[i], MODE_POINT);
}

double DigitsOf(const int i)
{
   return MarketInfo(g_sym[i], MODE_DIGITS);
}

// UTC hour of "now" on the broker server clock
int HourUTC()
{
   int h = TimeHour(TimeCurrent()) - InpGMTOffsetHours;
   while(h < 0)  h += 24;
   while(h > 23) h -= 24;
   return h;
}

int DayOfWeekUTC()
{
   return TimeDayOfWeek(TimeCurrent());
}

//+------------------------------------------------------------------+
//| Price-structure primitives                                       |
//+------------------------------------------------------------------+
// mean true range over 'period' finished bars, the bar 'shift' is the newest one
double MeanATR(const int i, const int shift, const int period)
{
   double sum = 0.0;
   for(int k = 0; k < period; k++)
   {
      int s = shift + k;
      double h = iHigh(g_sym[i], PERIOD_H1, s);
      double l = iLow(g_sym[i], PERIOD_H1, s);
      double pc = iClose(g_sym[i], PERIOD_H1, s + 1);
      double tr = MathMax(h - l, MathMax(MathAbs(h - pc), MathAbs(l - pc)));
      sum += tr;
   }
   return sum / (double)period;
}

// median of tick volume of the 'n' finished bars starting at 'shift'
double MedianVolume(const int i, const int shift, const int n)
{
   double v[];
   if(ArrayResize(v, n) != n) return 0.0;
   for(int k = 0; k < n; k++)
      v[k] = (double)iVolume(g_sym[i], PERIOD_H1, shift + k);
   ArraySort(v, WHOLE_ARRAY, 0, MODE_ASCENDING);
   if(n % 2 == 1) return v[(n - 1) / 2];
   return 0.5 * (v[n / 2 - 1] + v[n / 2]);
}

// True if one of the last 'n' finished bars (older than 'shift') already
// traded through 'level' - we only want the FIRST raid of a level.
bool TouchedRecently(const int i, const double level, const int shift, const int n, const bool above)
{
   for(int k = shift; k < shift + n; k++)
   {
      if(above)
      {
         if(iHigh(g_sym[i], PERIOD_H1, k) >= level) return true;
      }
      else
      {
         if(iLow(g_sym[i], PERIOD_H1, k) <= level) return true;
      }
   }
   return false;
}

// Most recent two confirmed swing pivots of each kind, as observed from bar 'shift'.
bool GetPivots(const int i, const int shift, double &ph1, double &ph2, double &pl1, double &pl2)
{
   ph1 = 0.0; ph2 = 0.0; pl1 = 0.0; pl2 = 0.0;
   int foundH = 0, foundL = 0;
   int last = MathMin(InpPivotLookback, Bars(g_sym[i], PERIOD_H1) - InpPivotK - 2);
   // a pivot at bar j needs InpPivotK bars to its right, i.e. j >= shift + InpPivotK
   for(int j = shift + InpPivotK; j <= last; j++)
   {
      bool isHigh = true, isLow = true;
      for(int k = 1; k <= InpPivotK; k++)
      {
         if(iHigh(g_sym[i], PERIOD_H1, j) < iHigh(g_sym[i], PERIOD_H1, j - k)) isHigh = false;
         if(iHigh(g_sym[i], PERIOD_H1, j) < iHigh(g_sym[i], PERIOD_H1, j + k)) isHigh = false;
         if(iLow(g_sym[i], PERIOD_H1, j)  > iLow(g_sym[i], PERIOD_H1, j - k))  isLow  = false;
         if(iLow(g_sym[i], PERIOD_H1, j)  > iLow(g_sym[i], PERIOD_H1, j + k))  isLow  = false;
      }
      if(isHigh && foundH < 2)
      {
         if(foundH == 0) ph1 = iHigh(g_sym[i], PERIOD_H1, j);
         else            ph2 = iHigh(g_sym[i], PERIOD_H1, j);
         foundH++;
      }
      if(isLow && foundL < 2)
      {
         if(foundL == 0) pl1 = iLow(g_sym[i], PERIOD_H1, j);
         else            pl2 = iLow(g_sym[i], PERIOD_H1, j);
         foundL++;
      }
      if(foundH >= 2 && foundL >= 2) break;
   }
   return (foundH >= 2 && foundL >= 2);
}

// previous day / week extremes (broker server time based, like iHigh(PERIOD_D1,1))
bool PrevDayExtremes(const int i, double &pdh, double &pdl)
{
   pdh = iHigh(g_sym[i], PERIOD_D1, 1);
   pdl = iLow(g_sym[i], PERIOD_D1, 1);
   return (pdh > 0.0 && pdl > 0.0);
}

bool PrevWeekExtremes(const int i, double &pwh, double &pwl)
{
   pwh = iHigh(g_sym[i], PERIOD_W1, 1);
   pwl = iLow(g_sym[i], PERIOD_W1, 1);
   return (pwh > 0.0 && pwl > 0.0);
}

//+------------------------------------------------------------------+
//| Order bookkeeping                                                |
//+------------------------------------------------------------------+
int CountPositionsSymbol(const string sym)
{
   int n = 0;
   for(int k = OrdersTotal() - 1; k >= 0; k--)
   {
      if(!OrderSelect(k, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber)      continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderSymbol() == sym) n++;
   }
   return n;
}

double FloatingPL()
{
   double pl = 0.0;
   for(int k = OrdersTotal() - 1; k >= 0; k--)
   {
      if(!OrderSelect(k, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber)      continue;
      pl += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return pl;
}

void ClosePosition(const int ticket, const string why)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   double px = 0.0;
   int type = OrderType();
   if(type == OP_BUY)  px = MarketInfo(OrderSymbol(), MODE_BID);
   if(type == OP_SELL) px = MarketInfo(OrderSymbol(), MODE_ASK);
   if(px <= 0.0) return;
   bool ok = OrderClose(ticket, OrderLots(), px, (int)MathMax(1, InpSlippagePips * 10), clrWhite);
   if(!ok && InpVerboseLog)
      Print("ClosePosition failed ", OrderSymbol(), " ticket ", ticket, " err ", GetLastError());
   if(ok && InpVerboseLog) Print("closed #", ticket, " ", OrderSymbol(), " reason ", why);
}

void CloseAllEA(const string why)
{
   for(int k = OrdersTotal() - 1; k >= 0; k--)
   {
      if(!OrderSelect(k, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber)      continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      ClosePosition(OrderTicket(), why);
   }
}

//+------------------------------------------------------------------+
//| Day / week accounting                                            |
//+------------------------------------------------------------------+
void ResetDayCounters()
{
   for(int i = 0; i < g_nsym; i++) g_dayCount[i] = 0;
   g_dayStartEquity = AccountEquity();
   g_haltedDay = false;
}

void UpdatePeriods()
{
   datetime now = TimeCurrent();
   datetime today = StrToTime(TimeToStr(now, TIME_DATE));
   if(today != g_curDay)
   {
      g_curDay = today;
      ResetDayCounters();
      GlobalVariableSet(g_gvDay, g_dayStartEquity);
   }
   int w = (int)TimeYear(now) * 100 + (int)(TimeDayOfYear(now) / 7);
   if(w != g_curWeek)
   {
      g_curWeek = w;
      g_weekStartEquity = AccountEquity();
      g_haltedWeek = false;
      GlobalVariableSet(g_gvWeek, g_weekStartEquity);
   }
}

double DayPLPercent()
{
   double base = g_dayStartEquity;
   if(base <= 0.0) base = AccountBalance();
   double eq = AccountEquity();
   return 100.0 * (eq - base) / base;
}

double WeekPLPercent()
{
   double base = g_weekStartEquity;
   if(base <= 0.0) base = AccountBalance();
   return 100.0 * (AccountEquity() - base) / base;
}

//+------------------------------------------------------------------+
//| Session / spread guards                                          |
//+------------------------------------------------------------------+
bool SessionOK()
{
   int h = HourUTC();
   if(h < InpSessionStartUTC || h >= InpSessionEndUTC) return false;
   int dow = DayOfWeekUTC();
   if(dow == 1 && !InpTradeMonday) return false;
   if(dow == 5 && !InpTradeFriday) return false;
   if(dow == 0 || dow == 6) return false;
   return true;
}

bool SpreadOK(const int i)
{
   double spr = (MarketInfo(g_sym[i], MODE_ASK) - MarketInfo(g_sym[i], MODE_BID)) / g_pip[i];
   if(spr <= 0.0 || spr > 1000.0) return false;                 // no quote / frozen feed
   double limit = g_isGold[i] ? InpMaxSpreadPipsGold : InpMaxSpreadPips;
   return (spr <= limit);
}

//+------------------------------------------------------------------+
//| Position sizing                                                  |
//+------------------------------------------------------------------+
double NormalizeLots(const int i, double lots)
{
   double minLot = MarketInfo(g_sym[i], MODE_MINLOT);
   double maxLot = MarketInfo(g_sym[i], MODE_MAXLOT);
   double step   = MarketInfo(g_sym[i], MODE_LOTSTEP);
   if(step <= 0.0) step = 0.01;
   if(minLot <= 0.0) minLot = 0.01;
   if(maxLot <= 0.0) maxLot = 100.0;
   lots = MathFloor(lots / step + 0.0000001) * step;
   if(lots < minLot) lots = 0.0;              // never round risk up to the minimum lot
   if(lots > maxLot) lots = maxLot;
   // keep the decimal representation clean for the lot step
   int decimals = 2;
   if(step >= 0.1) decimals = 1;
   if(step >= 1.0) decimals = 0;
   lots = NormalizeDouble(lots, decimals);
   return lots;
}

double LotsForRisk(const int i, const double entry, const double sl)
{
   double dist = MathAbs(entry - sl);
   if(dist <= 0.0) return 0.0;
   double equity = InpCompound ? AccountEquity() : AccountBalance();
   double riskMoney = equity * InpRiskPercent / 100.0;
   double tickValue = MarketInfo(g_sym[i], MODE_TICKVALUE);
   double tickSize  = MarketInfo(g_sym[i], MODE_TICKSIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;
   double valuePerPricePerLot = tickValue / tickSize;
   if(valuePerPricePerLot <= 0.0) return 0.0;
   double lots = riskMoney / (dist * valuePerPricePerLot);
   lots = NormalizeLots(i, lots);
   if(lots <= 0.0) return 0.0;
   // margin guard
   double marginPerLot = MarketInfo(g_sym[i], MODE_MARGINREQUIRED);
   if(marginPerLot > 0.0)
   {
      double maxMargin = equity * InpMaxMarginUsePct / 100.0;
      double maxLotsByMargin = maxMargin / marginPerLot;
      if(lots > maxLotsByMargin) lots = NormalizeLots(i, maxLotsByMargin);
   }
   return lots;
}

//+------------------------------------------------------------------+
//| Order sending                                                    |
//+------------------------------------------------------------------+
int OpenMarketOrder(const int i, const int side, const double slPrice, const double lots, const string tag)
{
   if(lots <= 0.0) return -1;
   string sym = g_sym[i];
   double price = (side > 0) ? MarketInfo(sym, MODE_ASK) : MarketInfo(sym, MODE_BID);
   if(price <= 0.0) return -1;

   // normalise the stop to broker stop level / freeze level
   double stopLevel = MarketInfo(sym, MODE_STOPLEVEL) * PointOf(i);
   double sl = slPrice;
   if(side > 0 && price - sl < stopLevel) sl = price - stopLevel - PointOf(i);
   if(side < 0 && sl - price < stopLevel) sl = price + stopLevel + PointOf(i);

   double riskDist = MathAbs(price - sl);
   if(riskDist <= 0.0) return -1;
   double tp = (side > 0) ? price + InpRR * riskDist : price - InpRR * riskDist;

   int digits2 = (int)DigitsOf(i);
   sl = NormalizeDouble(sl, digits2);
   tp = NormalizeDouble(tp, digits2);

   int slip = (int)MathMax(1.0, InpSlippagePips * g_pip[i] / PointOf(i));
   int ticket = -1;
   int type = (side > 0) ? OP_BUY : OP_SELL;

   for(int attempt = 0; attempt < MathMax(1, InpOrderRetries); attempt++)
   {
      RefreshRates();
      price = (side > 0) ? MarketInfo(sym, MODE_ASK) : MarketInfo(sym, MODE_BID);
      int err = 0;
      ticket = OrderSend(sym, type, lots, price, slip, sl, tp, tag, InpMagicNumber, 0, clrDodgerBlue);
      if(ticket > 0) break;
      err = GetLastError();
      if(err == 130 || err == 129)          // invalid stops / invalid price -> send naked, then modify
      {
         RefreshRates();
         price = (side > 0) ? MarketInfo(sym, MODE_ASK) : MarketInfo(sym, MODE_BID);
         ticket = OrderSend(sym, type, lots, price, slip, 0, 0, tag, InpMagicNumber, 0, clrDodgerBlue);
         if(ticket > 0)
         {
            if(OrderSelect(ticket, SELECT_BY_TICKET))
            {
               double sl2 = sl, tp2 = tp;
               if(side > 0 && OrderOpenPrice() - sl2 < stopLevel) sl2 = OrderOpenPrice() - stopLevel - PointOf(i);
               if(side < 0 && sl2 - OrderOpenPrice() < stopLevel) sl2 = OrderOpenPrice() + stopLevel + PointOf(i);
               OrderModify(ticket, OrderOpenPrice(), NormalizeDouble(sl2, digits2),
                           NormalizeDouble(tp2, digits2), 0, clrDodgerBlue);
            }
            break;
         }
      }
      if(err == 134 || err == 133 || err == 136 || err == 146 || err == 138) break; // not enough money / no prices
      Sleep(MathMax(50, InpRetrySleepMs));
   }
   if(ticket > 0 && InpVerboseLog)
      Print("OPEN ", (side > 0 ? "BUY " : "SELL "), sym, " ", DoubleToStr(lots, 2), " lots @ ",
            DoubleToStr(price, (int)DigitsOf(i)), " sl ", DoubleToStr(sl, (int)DigitsOf(i)), " tp ",
            DoubleToStr(tp, (int)DigitsOf(i)), " [", tag, "]");
   return ticket;
}

//+------------------------------------------------------------------+
//| Signal detection, one symbol, evaluated on the closed bar 1      |
//+------------------------------------------------------------------+
// returns 0 = no signal, +1 = long, -1 = short
int DetectSignal(const int i, double &outSL, double &outScore)
{
   outSL = 0.0; outScore = 0.0;
   double atr = MeanATR(i, 1, InpATRPeriod);
   if(atr <= 0.0) return 0;

   double h = iHigh(g_sym[i], PERIOD_H1, 1);
   double l = iLow(g_sym[i], PERIOD_H1, 1);
   double c = iClose(g_sym[i], PERIOD_H1, 1);
   double rng = h - l;
   if(rng <= 0.0) return 0;
   if(rng < (InpMinRangeATR / 100.0) * atr) return 0;

   // volume confirmation against the rolling median (includes the signal bar)
   if(InpVolumeConfirm)
   {
      double med = MedianVolume(i, 1, InpVolLookback);
      if(med <= 0.0) return 0;
      if((double)iVolume(g_sym[i], PERIOD_H1, 1) < (InpVolMultPct / 100.0) * med) return 0;
   }

   // market structure from the last two confirmed pivots
   double ph1, ph2, pl1, pl2;
   int structure = 0;
   bool havePivots = GetPivots(i, 1, ph1, ph2, pl1, pl2);
   if(havePivots)
   {
      if(ph1 > ph2 && pl1 > pl2) structure = 1;
      if(ph1 < ph2 && pl1 < pl2) structure = -1;
   }

   // candidate levels
   double pdh = 0.0, pdl = 0.0, pwh = 0.0, pwl = 0.0;
   if(InpUsePrevDay)  PrevDayExtremes(i, pdh, pdl);
   if(InpUsePrevWeek) PrevWeekExtremes(i, pwh, pwl);

   double sup[6], res[6];
   int nSup = 0, nRes = 0;
   if(pdh > 0.0) { res[nRes] = pdh; nRes++; }
   if(pwh > 0.0) { res[nRes] = pwh; nRes++; }
   if(InpUseSwing && havePivots)
   {
      if(ph1 > 0.0) { res[nRes] = ph1; nRes++; }
      if(InpLevelMode == 1 && ph2 > 0.0) { res[nRes] = ph2; nRes++; }
   }
   if(pdl > 0.0) { sup[nSup] = pdl; nSup++; }
   if(pwl > 0.0) { sup[nSup] = pwl; nSup++; }
   if(InpUseSwing && havePivots)
   {
      if(pl1 > 0.0) { sup[nSup] = pl1; nSup++; }
      if(InpLevelMode == 1 && pl2 > 0.0) { sup[nSup] = pl2; nSup++; }
   }

   if(InpLevelMode == 0)
   {
      // only the single most extreme reference level is allowed to trigger
      double maxRes = 0.0, minSup = 0.0;
      for(int a = 0; a < nRes; a++) if(res[a] > maxRes) maxRes = res[a];
      for(int b = 0; b < nSup; b++) if(minSup == 0.0 || sup[b] < minSup) minSup = sup[b];
      nRes = 0; nSup = 0;
      if(maxRes > 0.0) { res[0] = maxRes; nRes = 1; }
      if(minSup > 0.0) { sup[0] = minSup; nSup = 1; }
   }

   // SHORT: raid above resistance, close back below
   double levelS = 0.0;
   for(int k = 0; k < nRes; k++)
   {
      double L = res[k];
      if(h > L && c < L)
      {
         if(!TouchedRecently(i, L, 2, InpLevelCooldown, true))
         {
            if(InpLevelMode == 0 || levelS == 0.0) { levelS = L; }
            else levelS = MathMax(levelS, L);
         }
      }
   }
   // LONG: raid below support, close back above
   double levelL = 0.0;
   bool haveLongLevel = false;
   for(int k2 = 0; k2 < nSup; k2++)
   {
      double L2 = sup[k2];
      if(l < L2 && c > L2)
      {
         if(!TouchedRecently(i, L2, 2, InpLevelCooldown, false))
         {
            if(!haveLongLevel) { levelL = L2; haveLongLevel = true; }
            else levelL = MathMin(levelL, L2);
         }
      }
   }
   double closeLimit = (InpCloseFrac / 100.0);
   double closePos = 0.0;
   int side = 0;
   double level = 0.0;
   double sweepExtreme = 0.0;
   double pen = 0.0;

   bool shortOK = (levelS != 0.0) && ((h - c) / rng >= closeLimit);
   bool longOK  = haveLongLevel      && ((c - l) / rng >= closeLimit);

   if(InpRequireStructure)
   {
      if(shortOK && structure > 0) shortOK = false;
      if(longOK  && structure < 0) longOK  = false;
   }
   if(shortOK && longOK)
   {
      // both fired on the same bar (outside bar): take neither, like the engine
      return 0;
   }
   if(longOK)  { side = 1;  level = levelL; sweepExtreme = l; pen = (levelL - l) / atr; closePos = (c - l) / rng; }
   if(shortOK) { side = -1; level = levelS; sweepExtreme = h; pen = (h - levelS) / atr; closePos = (h - c) / rng; }
   if(side == 0) return 0;

   // a raid that goes far beyond the level is a real breakout, not a stop hunt
   if(InpMaxPenetrationPct > 0 && InpMaxPenetrationPct < 90)
   {
      double penAtr = MathAbs(sweepExtreme - level) / atr;
      if(penAtr > (InpMaxPenetrationPct / 100.0)) return 0;
   }

   double sl = (side > 0) ? (sweepExtreme - InpSlATRBuffer * atr)
                          : (sweepExtreme + InpSlATRBuffer * atr);
   double dist = MathAbs(c - sl) / atr;
   if(dist < InpMinSlATR || dist > InpMaxSlATR) return 0;

   double volRatio = 1.0;
   double med2 = MedianVolume(i, 1, InpVolLookback);
   if(med2 > 0.0) volRatio = (double)iVolume(g_sym[i], PERIOD_H1, 1) / med2;

   outSL = sl;
   outScore = 1.0 * MathMin(pen, 3.0) + 0.35 * MathMin(volRatio, 4.0) + 0.5 * closePos;
   return side;
}

//+------------------------------------------------------------------+
//| Position management (bar close logic)                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int k = OrdersTotal() - 1; k >= 0; k--)
   {
      if(!OrderSelect(k, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber)      continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      string sym = OrderSymbol();
      int i = -1;
      for(int s = 0; s < g_nsym; s++) if(g_sym[s] == sym) { i = s; break; }
      if(i < 0) continue;

      int side = (OrderType() == OP_BUY) ? 1 : -1;
      double entry = OrderOpenPrice();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      if(sl <= 0.0) continue;
      double riskDist = MathAbs(entry - sl);
      if(riskDist <= 0.0) continue;

      int shift = iBarShift(sym, PERIOD_H1, OrderOpenTime(), false);
      if(shift < 0) shift = 0;

      // weekend flatten
      if(InpFridayCloseHourUTC < 90 && DayOfWeekUTC() == 5 && HourUTC() >= InpFridayCloseHourUTC)
      {
         ClosePosition(OrderTicket(), "weekend");
         continue;
      }

      // time stop
      if(InpMaxHoldBars > 0 && shift >= InpMaxHoldBars)
      {
         ClosePosition(OrderTicket(), "time");
         continue;
      }

      double c = iClose(sym, PERIOD_H1, 1);
      double h = iHigh(sym, PERIOD_H1, 1);
      double l = iLow(sym, PERIOD_H1, 1);
      double rNow = ((side > 0) ? (c - entry) : (entry - c)) / riskDist;

      double newSL = sl;
      bool changed = false;

      // break-even
      if(InpBEatR > 0.0 && rNow >= InpBEatR)
      {
         if(side > 0 && sl < entry - PointOf(i) * 0.5) { newSL = entry; changed = true; }
         if(side < 0 && (sl > entry + PointOf(i) * 0.5 || sl == 0.0)) { newSL = entry; changed = true; }
      }
      // chandelier trail
      if(InpTrailATR > 0.0)
      {
         double atr = MeanATR(i, 1, InpATRPeriod);
         if(atr > 0.0)
         {
            if(side > 0)
            {
               double cand = c - InpTrailATR * atr;
               if(cand > newSL) { newSL = cand; changed = true; }
            }
            else
            {
               double cand2 = c + InpTrailATR * atr;
               if(cand2 < newSL || newSL == 0.0) { newSL = cand2; changed = true; }
            }
         }
      }
      if(!changed) continue;

      double stopLevel = MarketInfo(sym, MODE_STOPLEVEL) * PointOf(i);
      if(side > 0 && c - newSL < stopLevel) continue;
      if(side < 0 && newSL - c < stopLevel) continue;
      newSL = NormalizeDouble(newSL, (int)DigitsOf(i));
      if(MathAbs(newSL - sl) < PointOf(i) * 0.5) continue;

      if(!OrderModify(OrderTicket(), entry, newSL, tp, 0, clrYellow))
      {
         if(InpVerboseLog) Print("modify failed ", sym, " ticket ", OrderTicket(), " err ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Risk gate                                                        |
//+------------------------------------------------------------------+
bool RiskAllowsNewTrades()
{
   if(g_haltedDay || g_haltedWeek) return false;
   if(!SessionOK()) return false;

   double dp = DayPLPercent();
   double wp = WeekPLPercent();

   if(InpDailyHardStopPct > 0.0 && dp <= -InpDailyHardStopPct)
   {
      g_haltedDay = true;
      CloseAllEA("daily hard stop");
      Print("DAILY HARD STOP: ", DoubleToStr(dp, 2), "% - flat until tomorrow");
      return false;
   }
   if(InpDailyStopPct > 0.0 && dp <= -InpDailyStopPct)
   {
      if(!g_haltedDay) Print("daily soft stop hit: ", DoubleToStr(dp, 2), "% - no new trades today");
      g_haltedDay = true;
      return false;
   }
   if(InpWeeklyStopPct > 0.0 && wp <= -InpWeeklyStopPct)
   {
      if(!g_haltedWeek) Print("weekly stop hit: ", DoubleToStr(wp, 2), "% - no new trades this week");
      g_haltedWeek = true;
      return false;
   }
   if(InpMaxPositions > 0 && CountPositionsSymbol("") >= InpMaxPositions) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Scan all symbols, rank candidates, open the best ones            |
//+------------------------------------------------------------------+
void ScanAndTrade()
{
   g_nCand = 0;
   for(int i = 0; i < g_nsym; i++)
   {
      if(CountPositionsSymbol(g_sym[i]) > 0) continue;
      if(g_dayCount[i] >= InpMaxSignalsPerDay) continue;
      if(!SpreadOK(i)) continue;
      if(Bars(g_sym[i], PERIOD_H1) < InpPivotLookback / 2) continue;
      datetime symBar = iTime(g_sym[i], PERIOD_H1, 1);
      if(symBar == 0) continue;
      // stale/holiday symbol: its last finished H1 bar is not the one we are evaluating
      if(symBar != iTime(Symbol(), PERIOD_H1, 1)) continue;

      double sl = 0.0, score = 0.0;
      int side = DetectSignal(i, sl, score);
      if(side == 0) continue;
      if(g_nCand >= MAX_SYMBOLS) break;
      g_cIdx[g_nCand]   = i;
      g_cSide[g_nCand]  = side;
      g_cSL[g_nCand]    = sl;
      g_cScore[g_nCand] = score;
      g_nCand++;
   }
   if(g_nCand == 0) return;

   // insertion sort by score, descending (deterministic, small N)
   for(int a = 1; a < g_nCand; a++)
   {
      int ia = g_cIdx[a], sa = g_cSide[a];
      double sla = g_cSL[a], sca = g_cScore[a];
      int b = a - 1;
      while(b >= 0 && g_cScore[b] < sca)
      {
         g_cIdx[b + 1] = g_cIdx[b];
         g_cSide[b + 1] = g_cSide[b];
         g_cSL[b + 1] = g_cSL[b];
         g_cScore[b + 1] = g_cScore[b];
         b--;
      }
      g_cIdx[b + 1] = ia; g_cSide[b + 1] = sa; g_cSL[b + 1] = sla; g_cScore[b + 1] = sca;
   }

   for(int c = 0; c < g_nCand; c++)
   {
      if(!RiskAllowsNewTrades()) break;
      int i = g_cIdx[c];
      int side = g_cSide[c];
      double sl = g_cSL[c];

      double entry = (side > 0) ? MarketInfo(g_sym[i], MODE_ASK) : MarketInfo(g_sym[i], MODE_BID);
      if(entry <= 0.0) continue;
      double lots = LotsForRisk(i, entry, sl);
      if(lots <= 0.0)
      {
         if(InpVerboseLog) Print("lot size below minimum for ", g_sym[i], " - skipped");
         continue;
      }
      int ticket = OpenMarketOrder(i, side, sl, lots, "LSweep");
      if(ticket > 0)
      {
         g_dayCount[i]++;
         if(InpVerboseLog)
            Print("signal ", g_sym[i], (side > 0 ? " LONG" : " SHORT"), " score ", DoubleToStr(g_cScore[c], 3));
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void ShowDashboard()
{
   if(!InpShowDashboard) return;
   if(TimeCurrent() - g_lastDash < 2) return;   // refresh at most every 2 seconds
   g_lastDash = TimeCurrent();
   string txt = "LiquiditySweep Portfolio EA  ·  magic " + IntegerToString(InpMagicNumber) + "\n";
   txt += "Equity " + DoubleToStr(AccountEquity(), 2) + "  Balance " + DoubleToStr(AccountBalance(), 2)
          + "  Floating " + DoubleToStr(FloatingPL(), 2) + "\n";
   txt += "Day " + DoubleToStr(DayPLPercent(), 2) + "%   Week " + DoubleToStr(WeekPLPercent(), 2)
          + "%   Risk/trade " + DoubleToStr(InpRiskPercent, 2) + "%\n";
   txt += "Positions " + IntegerToString(CountPositionsSymbol("")) + "/" + IntegerToString(InpMaxPositions)
          + "   Session " + (SessionOK() ? "OPEN" : "closed")
          + "   HaltedDay " + (g_haltedDay ? "YES" : "no")
          + "   HaltedWeek " + (g_haltedWeek ? "YES" : "no") + "\n";
   txt += "Symbols: ";
   for(int i = 0; i < g_nsym; i++)
   {
      txt += g_sym[i];
      if(CountPositionsSymbol(g_sym[i]) > 0) txt += "*";
      txt += " ";
   }
   Comment(txt);
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int ParseSymbols(const string list)
{
   string parts[];
   int n = StringSplit(list, ',', parts);
   g_nsym = 0;
   for(int k = 0; k < n && g_nsym < MAX_SYMBOLS; k++)
   {
      string s = parts[k];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      bool dup = false;
      for(int j = 0; j < g_nsym; j++) if(g_sym[j] == s) dup = true;
      if(dup) continue;
      if(!SymbolSelect(s, true))
      {
         Print("WARNING: symbol ", s, " not available at this broker - skipped");
         continue;
      }
      g_sym[g_nsym] = s;
      double point = MarketInfo(s, MODE_POINT);
      int digits = (int)MarketInfo(s, MODE_DIGITS);
      double pip = point;
      if(digits == 3 || digits == 5) pip = point * 10.0;
      if(pip <= 0.0) pip = point;
      g_pip[g_nsym] = pip;
      g_lotSize[g_nsym] = MarketInfo(s, MODE_LOTSIZE);
      g_isGold[g_nsym] = IsGoldSymbol(s);
      g_lastH1Bar[g_nsym] = 0;
      g_dayCount[g_nsym] = 0;
      g_nsym++;
   }
   return g_nsym;
}

int OnInit()
{
   if(Period() != PERIOD_H1)
      Print("WARNING: the strategy was validated on H1; current chart period is not H1.");

   if(ParseSymbols(InpSymbols) == 0)
   {
      Print("ERROR: no valid symbols configured in InpSymbols.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 5.0)
   {
      Print("ERROR: InpRiskPercent must be in (0, 5].");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpRR <= 0.0)
   {
      Print("ERROR: InpRR must be positive.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_lastClock = iTime(Symbol(), PERIOD_H1, 0);   // do not trade the bar we start in
   g_startEquity = AccountEquity();
   g_dayStartEquity = AccountEquity();
   g_weekStartEquity = AccountEquity();
   g_gvDay  = "LSWEEP_DAY_"  + IntegerToString(InpMagicNumber) + "_" + IntegerToString(AccountNumber());
   g_gvWeek = "LSWEEP_WEEK_" + IntegerToString(InpMagicNumber) + "_" + IntegerToString(AccountNumber());
   ResetDayCounters();

   Print("LiquiditySweep EA initialised. Symbols: ", InpSymbols,
         "  risk/trade ", DoubleToStr(InpRiskPercent, 2), "%  max positions ", InpMaxPositions);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdatePeriods();

   // act once per finished H1 bar, synchronised on the chart symbol clock
   datetime clockNow = iTime(Symbol(), PERIOD_H1, 0);
   if(clockNow == 0) return;
   if(clockNow == g_lastClock)
   {
      ShowDashboard();
      return;
   }
   g_lastClock = clockNow;

   // per-symbol bar sync (a symbol may be missing the newest bar, e.g. holidays)
   for(int i = 0; i < g_nsym; i++)
   {
      g_lastH1Bar[i] = iTime(g_sym[i], PERIOD_H1, 1);
      if(g_lastH1Bar[i] != iTime(Symbol(), PERIOD_H1, 1) && InpVerboseLog)
         Print("note: ", g_sym[i], " last H1 bar ", TimeToStr(g_lastH1Bar[i]), " is stale");
   }

   ManagePositions();

   if(!RiskAllowsNewTrades())
   {
      ShowDashboard();
      return;
   }
   ScanAndTrade();
   ShowDashboard();
}
//+------------------------------------------------------------------+
