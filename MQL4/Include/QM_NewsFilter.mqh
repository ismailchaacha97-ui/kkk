//+------------------------------------------------------------------+
//|                                               QM_NewsFilter.mqh  |
//|  QuantumEdge News Blackout Filter for MT4                        |
//|  Blocks trading 45m before -> 30m after high-impact EUR/USD news|
//|  Source: CSV file in MQL4/Files/ + optional manual list          |
//|  Version: 1.0                                                    |
//+------------------------------------------------------------------+
#property copyright "QuantumEdge Quant Lab — MIT"
#property strict

//--- Global news storage (managed by EA, but helpers here)
datetime g_qmNewsTimes[];
string   g_qmNewsCurr[];
string   g_qmNewsImpact[];
string   g_qmNewsEvent[];
int      g_qmNewsCount = 0;

//+------------------------------------------------------------------+
//| Helper: trim string                                              |
//+------------------------------------------------------------------+
string QM_Trim(string s)
  {
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
  }

//+------------------------------------------------------------------+
//| Helper: check if currency is in filter list                      |
//| filter = "EUR,USD" or "ALL"                                      |
//+------------------------------------------------------------------+
bool QM_CurrencyPass(string cur, string filterList)
  {
   cur = QM_Trim(cur);
   filterList = QM_Trim(filterList);
   if(filterList == "" || filterList == "ALL" || filterList == "*") return true;
   // Uppercase both
   StringToUpper(cur);
   StringToUpper(filterList);
   // Simple contains — add commas padding to avoid substring false positives
   string padded = "," + filterList + ",";
   StringReplace(padded, " ", "");
   string key = "," + cur + ",";
   return StringFind(padded, key) >= 0;
  }

//+------------------------------------------------------------------+
//| Load news CSV from MQL4/Files/                                   |
//| Format per line: YYYY.MM.DD HH:MM, Currency, Impact, Event      |
//| Example: 2025.10.29 14:30,USD,High,NFP                          |
//| Returns count loaded, 0 if file missing (not an error)           |
//+------------------------------------------------------------------+
int QM_LoadNewsFile(string filename)
  {
   // Reset
   ArrayResize(g_qmNewsTimes, 0);
   ArrayResize(g_qmNewsCurr, 0);
   ArrayResize(g_qmNewsImpact, 0);
   ArrayResize(g_qmNewsEvent, 0);
   g_qmNewsCount = 0;

   int h = FileOpen(filename, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
     {
      // File not found is OK — user may use manual list or no news
      // Only warn once per load attempt
      Print("[NEWS] File not found: MQL4/Files/", filename, " — news filter inactive until you create it. See docs/NEWS_FILTER.md");
      return 0;
     }

   int cnt = 0;
   while(!FileIsEnding(h))
     {
      // Read fields: attempt 4 columns, but tolerate 2-3
      string timeStr = FileReadString(h);
      if(FileIsEnding(h) && timeStr == "") break;
      timeStr = QM_Trim(timeStr);
      if(timeStr == "" || StringGetCharacter(timeStr, 0) == '#' || StringGetCharacter(timeStr, 0) == '/')
        {
         // Comment line — skip rest of row if needed
         // Try to consume remainder to next line
         if(!FileIsLineEnding(h))
           {
            // consume up to end of line
            while(!FileIsEnding(h) && !FileIsLineEnding(h)) FileReadString(h);
           }
         continue;
        }

      string cur = "";
      string impact = "";
      string event = "";
      // cur may be next field if not end of line
      if(!FileIsLineEnding(h)) cur = QM_Trim(FileReadString(h));
      if(!FileIsLineEnding(h)) impact = QM_Trim(FileReadString(h));
      if(!FileIsLineEnding(h)) event = QM_Trim(FileReadString(h));
      // Consume any extra fields to line end
      while(!FileIsEnding(h) && !FileIsLineEnding(h)) FileReadString(h);

      // Validate time
      datetime t = StringToTime(timeStr);
      if(t == 0)
        {
         Print("[NEWS] Skipping invalid time: '", timeStr, "'  -> line ignored. Use YYYY.MM.DD HH:MM in broker time.");
         continue;
        }

      // Store
      int n = ArraySize(g_qmNewsTimes);
      ArrayResize(g_qmNewsTimes, n+1);
      ArrayResize(g_qmNewsCurr, n+1);
      ArrayResize(g_qmNewsImpact, n+1);
      ArrayResize(g_qmNewsEvent, n+1);
      g_qmNewsTimes[n] = t;
      g_qmNewsCurr[n] = cur == "" ? "ALL" : cur;
      g_qmNewsImpact[n] = impact == "" ? "High" : impact;
      g_qmNewsEvent[n] = event;
      cnt++;
     }

   FileClose(h);
   g_qmNewsCount = cnt;
   if(cnt > 0)
      Print("[NEWS] Loaded ", cnt, " events from ", filename, " (broker time). Example: ", TimeToString(g_qmNewsTimes[0]), " ", g_qmNewsCurr[0], " ", g_qmNewsImpact[0]);

   return cnt;
  }

//+------------------------------------------------------------------+
//| Parse manual news list string (fallback if file missing)         |
//| Format: "2025.10.29 14:30 USD High NFP; 2025.10.30 13:45 EUR"    |
//| Semicolon separated, each entry: TIME [CUR] [IMPACT]             |
//+------------------------------------------------------------------+
int QM_ParseManualList(string manualStr)
  {
   manualStr = QM_Trim(manualStr);
   if(manualStr == "") return 0;

   // Split by ';'
   string parts[];
   int num = StringSplit(manualStr, ';', parts);
   int cnt = 0;
   for(int i=0; i<num; i++)
     {
      string entry = QM_Trim(parts[i]);
      if(entry == "") continue;

      // Split entry by spaces/commas
      // First token(s) should be datetime — try to find time pattern
      // Simplest: entry starts with "YYYY.MM.DD HH:MM"
      string tokens[];
      // Normalize commas to spaces
      StringReplace(entry, ",", " ");
      int tnum = StringSplit(entry, ' ', tokens);
      // Clean empty tokens
      string clean[];
      int cidx=0;
      ArrayResize(clean, tnum);
      for(int k=0;k<tnum;k++) if(QM_Trim(tokens[k])!="") { clean[cidx]=QM_Trim(tokens[k]); cidx++; }
      ArrayResize(clean, cidx);
      if(cidx < 2) continue;

      string timeStr = clean[0] + " " + clean[1];
      datetime t = StringToTime(timeStr);
      if(t==0) { Print("[NEWS] Manual parse skip invalid time: '",timeStr,"'"); continue; }

      string cur = cidx >=3 ? clean[2] : "ALL";
      string impact = cidx >=4 ? clean[3] : "High";
      string event = "";
      if(cidx >=5) { for(int e=4;e<cidx;e++) event += clean[e]+" "; event=QM_Trim(event); }

      int n = ArraySize(g_qmNewsTimes);
      ArrayResize(g_qmNewsTimes, n+1);
      ArrayResize(g_qmNewsCurr, n+1);
      ArrayResize(g_qmNewsImpact, n+1);
      ArrayResize(g_qmNewsEvent, n+1);
      g_qmNewsTimes[n]=t;
      g_qmNewsCurr[n]=cur;
      g_qmNewsImpact[n]=impact;
      g_qmNewsEvent[n]=event;
      cnt++;
     }

   g_qmNewsCount += cnt;
   if(cnt>0) Print("[NEWS] Parsed ",cnt," manual entries. Total now ",ArraySize(g_qmNewsTimes));
   return cnt;
  }

//+------------------------------------------------------------------+
//| Check if current time is inside any blackout window              |
//| Returns true if blocked, and fills reason/outTime                |
//+------------------------------------------------------------------+
bool QM_IsNewsBlocked(datetime curTime, int beforeMin, int afterMin, string filterCurrencies,
                      string &outReason, datetime &outNewsTime, string &outCurrency)
  {
   outReason = "";
   outNewsTime = 0;
   outCurrency = "";

   if(ArraySize(g_qmNewsTimes)==0) return false;
   if(beforeMin <0) beforeMin=0;
   if(afterMin <0) afterMin=0;

   for(int i=0; i<ArraySize(g_qmNewsTimes); i++)
     {
      datetime newsT = g_qmNewsTimes[i];
      string cur = g_qmNewsCurr[i];
      string imp = g_qmNewsImpact[i];

      // Currency filter
      if(!QM_CurrencyPass(cur, filterCurrencies)) continue;

      // Optional: impact filter handled by caller (if needed)
      // Check window
      datetime winStart = newsT - beforeMin*60;
      datetime winEnd   = newsT + afterMin*60;

      if(curTime >= winStart && curTime <= winEnd)
        {
         outNewsTime = newsT;
         outCurrency = cur;
         string ev = g_qmNewsEvent[i];
         outReason = StringFormat("%s %s %s (%s) window %s -> %s | cur %s",
                     TimeToString(newsT), cur, imp, ev,
                     TimeToString(winStart), TimeToString(winEnd), TimeToString(curTime));
         return true;
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Utility to get next news time (for dashboard)                    |
//+------------------------------------------------------------------+
datetime QM_NextNewsTime(datetime curTime, string filterCurrencies)
  {
   datetime best=0;
   for(int i=0;i<ArraySize(g_qmNewsTimes);i++)
     {
      if(!QM_CurrencyPass(g_qmNewsCurr[i], filterCurrencies)) continue;
      datetime t=g_qmNewsTimes[i];
      if(t < curTime) continue;
      if(best==0 || t < best) best=t;
     }
   return best;
  }

//+------------------------------------------------------------------+
//| Impact check helper (e.g., only block High)                      |
//+------------------------------------------------------------------+
bool QM_ShouldBlockImpact(string impact, bool highOnly)
  {
   if(!highOnly) return true;
   impact = QM_Trim(impact);
   StringToUpper(impact);
   return (impact=="HIGH" || impact=="H" || impact=="RED");
  }
