//+------------------------------------------------------------------+
//| VWAP_SSL_Flip_Pro.mq4                                           |
//| Anchored VWAP SSL flip with volatility bands and alerts          |
//|                                                                  |
//| Notes                                                            |
//|  - Arrays are series arrays: index 0 is the current bar.          |
//|  - VWAP is calculated from tick volume (or real volume when      |
//|    available), with a safe fallback for zero-volume symbols.     |
//|  - Alerts can be restricted to confirmed, closed-bar signals.    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   8
#property indicator_color1  clrLimeGreen
#property indicator_color2  clrTomato
#property indicator_color3  clrLimeGreen
#property indicator_color4  clrTomato
#property indicator_color5  clrDodgerBlue
#property indicator_color6  clrDodgerBlue
#property indicator_color7  clrSilver
#property indicator_color8  clrSilver

//--- anchor choices
enum ENUM_VWAP_PERIOD
  {
   VWAP_DAILY,
   VWAP_WEEKLY,
   VWAP_MONTHLY,
   VWAP_LONDON,
   VWAP_NEWYORK,
   VWAP_ASIA
  };

input ENUM_VWAP_PERIOD InpPeriod       = VWAP_DAILY;
input int              InpLondonH      = 8;
input int              InpLondonM      = 0;
input int              InpNYH          = 13;
input int              InpNYM          = 30;
input int              InpAsiaH        = 0;
input int              InpAsiaM         = 0;
input bool             InpUseRealVol   = false;       // Use real volume where supplied
input int              InpMinBars      = 1;           // Bars required in an anchor before a flip

input color            InpUpColor      = clrLimeGreen;
input color            InpDnColor      = clrTomato;
input int              InpLineWidth    = 2;
input bool             InpShowBands    = true;
input color            InpBand1Color   = clrDodgerBlue;
input color            InpBand2Color   = clrSilver;
input bool             InpShowArrows   = true;
input int              InpArrowSize    = 2;
input double           InpArrowATR     = 0.25;        // Arrow offset in ATRs
input int              InpATRPeriod    = 14;

input bool             InpAlertPopup   = false;
input bool             InpAlertSound   = false;
input bool             InpAlertEmail   = false;
input bool             InpAlertPush    = false;
input string           InpAlertWav     = "alert.wav";
input bool             InpAlertOnce    = true;
input bool             InpClosedAlerts = true;        // Never alert on a forming bar
input bool             InpShowHUD      = true;

//--- plotted buffers
double BufUp[],BufDn[],BufBuy[],BufSell[],BufUp1[],BufDn1[],BufUp2[],BufDn2[];
//--- cumulative weighted sums, calculated oldest to newest
double cHigh[],cLow[],cTypical[],cHigh2[],cLow2[],cTypical2[],cVol[];
int    state[], barsInAnchor[];
datetime lastAlertBar=0;
int      lastAlertState=-2;

string PeriodName()
  {
   switch(InpPeriod)
     {
      case VWAP_WEEKLY: return "Weekly";
      case VWAP_MONTHLY:return "Monthly";
      case VWAP_LONDON: return "London";
      case VWAP_NEWYORK:return "New York";
      case VWAP_ASIA:  return "Asia";
     }
   return "Daily";
  }

int ClampHour(int h) { return MathMax(0,MathMin(23,h)); }
int ClampMinute(int m) { return MathMax(0,MathMin(59,m)); }

// t is the newer bar and older is the bar immediately to its right.
bool NewAnchor(datetime t,datetime older)
  {
   if(t<=0 || older<=0) return true;
   if(InpPeriod==VWAP_DAILY)   return TimeYear(t)!=TimeYear(older) || TimeDayOfYear(t)!=TimeDayOfYear(older);
   if(InpPeriod==VWAP_MONTHLY) return TimeYear(t)!=TimeYear(older) || TimeMonth(t)!=TimeMonth(older);
   if(InpPeriod==VWAP_WEEKLY)
     {
      // ISO-like week key; this handles month/year changes and weekend gaps.
      datetime mondayT=t-((TimeDayOfWeek(t)+6)%7)*86400;
      datetime mondayO=older-((TimeDayOfWeek(older)+6)%7)*86400;
      return TimeYear(mondayT)!=TimeYear(mondayO) || TimeDayOfYear(mondayT)!=TimeDayOfYear(mondayO);
     }

   int h=InpAsiaH,m=InpAsiaM;
   if(InpPeriod==VWAP_LONDON) { h=InpLondonH; m=InpLondonM; }
   if(InpPeriod==VWAP_NEWYORK){ h=InpNYH; m=InpNYM; }
   int session=ClampHour(h)*60+ClampMinute(m);
   int cur=TimeHour(t)*60+TimeMinute(t), old=TimeHour(older)*60+TimeMinute(older);
   if(TimeYear(t)!=TimeYear(older) || TimeDayOfYear(t)!=TimeDayOfYear(older)) return cur>=session;
   return old<session && cur>=session;
  }

void SetLineStyle()
  {
   SetIndexStyle(0,DRAW_LINE,STYLE_SOLID,MathMax(1,MathMin(5,InpLineWidth)),InpUpColor);
   SetIndexStyle(1,DRAW_LINE,STYLE_SOLID,MathMax(1,MathMin(5,InpLineWidth)),InpDnColor);
   if(InpShowArrows)
     {
      SetIndexStyle(2,DRAW_ARROW,STYLE_SOLID,MathMax(1,MathMin(5,InpArrowSize)),InpUpColor);
      SetIndexStyle(3,DRAW_ARROW,STYLE_SOLID,MathMax(1,MathMin(5,InpArrowSize)),InpDnColor);
      SetIndexArrow(2,233); SetIndexArrow(3,234);
     }
   else { SetIndexStyle(2,DRAW_NONE); SetIndexStyle(3,DRAW_NONE); }
   if(InpShowBands)
     {
      SetIndexStyle(4,DRAW_LINE,STYLE_DOT,1,InpBand1Color); SetIndexStyle(5,DRAW_LINE,STYLE_DOT,1,InpBand1Color);
      SetIndexStyle(6,DRAW_LINE,STYLE_DOT,1,InpBand2Color); SetIndexStyle(7,DRAW_LINE,STYLE_DOT,1,InpBand2Color);
     }
   else { SetIndexStyle(4,DRAW_NONE); SetIndexStyle(5,DRAW_NONE); SetIndexStyle(6,DRAW_NONE); SetIndexStyle(7,DRAW_NONE); }
  }

int OnInit()
  {
   SetIndexBuffer(0,BufUp); SetIndexBuffer(1,BufDn); SetIndexBuffer(2,BufBuy); SetIndexBuffer(3,BufSell);
   SetIndexBuffer(4,BufUp1); SetIndexBuffer(5,BufDn1); SetIndexBuffer(6,BufUp2); SetIndexBuffer(7,BufDn2);
   for(int i=0;i<8;i++) SetIndexEmptyValue(i,EMPTY_VALUE);
   SetIndexLabel(0,"VWAP SSL Up"); SetIndexLabel(1,"VWAP SSL Down");
   SetIndexLabel(2,"Confirmed Buy Flip"); SetIndexLabel(3,"Confirmed Sell Flip");
   SetIndexLabel(4,"VWAP +1 SD"); SetIndexLabel(5,"VWAP -1 SD"); SetIndexLabel(6,"VWAP +2 SD"); SetIndexLabel(7,"VWAP -2 SD");
   SetLineStyle();
   IndicatorShortName("VWAP SSL Flip Pro ("+PeriodName()+")");
   IndicatorDigits(Digits);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { Comment(""); }

void AlertFlip(int s,int bar,const double price,const datetime &time[])
  {
   if(!InpAlertPopup&&!InpAlertSound&&!InpAlertEmail&&!InpAlertPush) return;
   if(InpClosedAlerts && bar==0) return;
   if(InpAlertOnce && lastAlertBar==time[bar] && lastAlertState==s) return;
   string side=(s==0?"BUY":"SELL");
   string msg=StringFormat("VWAP SSL Flip Pro | %s %s | %s | %s | price %s",Symbol(),PeriodName(),side,EnumToString((ENUM_TIMEFRAMES)Period()),DoubleToString(price,Digits));
   if(InpAlertPopup) Alert(msg);
   if(InpAlertSound) PlaySound(InpAlertWav);
   if(InpAlertEmail) SendMail("VWAP SSL Flip Pro",msg);
   if(InpAlertPush) SendNotification(msg);
   lastAlertBar=time[bar]; lastAlertState=s;
  }

int OnCalculate(const int total,const int prev,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(total<3) return 0;
   if(ArraySize(cVol)!=total)
     {
      ArrayResize(cHigh,total); ArrayResize(cLow,total); ArrayResize(cTypical,total); ArrayResize(cHigh2,total); ArrayResize(cLow2,total); ArrayResize(cTypical2,total); ArrayResize(cVol,total);
      ArrayResize(state,total); ArrayResize(barsInAnchor,total);
     }
   // Pass 1: cumulative VWAP and weighted variance. Rebuilding this pass is
   // intentional: an anchor can change on the live bar and remains O(n).
   double sh=0,sl=0,st=0,sh2=0,sl2=0,st2=0,sv=0; int n=0;
   for(int i=total-1;i>=0;i--)
     {
      if(i==total-1 || NewAnchor(time[i],time[i+1])) { sh=sl=st=sh2=sl2=st2=sv=0; n=0; }
      double v=(InpUseRealVol && volume[i]>0)?(double)volume[i]:(double)tick_volume[i]; if(v<=0) v=1;
      double tp=(high[i]+low[i]+close[i])/3.0;
      sh+=high[i]*v; sl+=low[i]*v; st+=tp*v; sh2+=high[i]*high[i]*v; sl2+=low[i]*low[i]*v; st2+=tp*tp*v; sv+=v; n++;
      cHigh[i]=sh; cLow[i]=sl; cTypical[i]=st; cHigh2[i]=sh2; cLow2[i]=sl2; cTypical2[i]=st2; cVol[i]=sv; barsInAnchor[i]=n;
     }

   ArrayInitialize(state,-1);
   // Pass 2 is also rebuilt to guarantee deterministic historical arrows after
   // a newly completed anchor or a history refresh.
   for(int p=total-1;p>=0;p--)
     {
      BufUp[p]=BufDn[p]=BufBuy[p]=BufSell[p]=BufUp1[p]=BufDn1[p]=BufUp2[p]=BufDn2[p]=EMPTY_VALUE;
      double vh=cHigh[p]/cVol[p], vl=cLow[p]/cVol[p], vt=cTypical[p]/cVol[p];
      double var=cTypical2[p]/cVol[p]-vt*vt; double sd=MathSqrt(MathMax(0.0,var));
      int prior=(p<total-1?state[p+1]:-1), cur=prior;
      if(prior<0) cur=(close[p]>=vh?0:1);
      else if(prior==0 && close[p]<vl) cur=1;
      else if(prior==1 && close[p]>vh) cur=0;
      state[p]=cur;
      bool flip=(prior>=0 && cur!=prior && barsInAnchor[p]>=MathMax(1,InpMinBars));
      if(cur==0) { BufUp[p]=vl; if(flip) { BufDn[p]=vh; if(InpShowArrows) BufBuy[p]=low[p]-MathMax(Point,InpArrowATR*iATR(NULL,0,MathMax(1,InpATRPeriod),p)); if((InpClosedAlerts && p==1)||(!InpClosedAlerts && p==0)) AlertFlip(0,p,close[p],time); } }
      else       { BufDn[p]=vh; if(flip) { BufUp[p]=vl; if(InpShowArrows) BufSell[p]=high[p]+MathMax(Point,InpArrowATR*iATR(NULL,0,MathMax(1,InpATRPeriod),p)); if((InpClosedAlerts && p==1)||(!InpClosedAlerts && p==0)) AlertFlip(1,p,close[p],time); } }
      if(InpShowBands) { BufUp1[p]=vt+sd; BufDn1[p]=vt-sd; BufUp2[p]=vt+2.0*sd; BufDn2[p]=vt-2.0*sd; }
     }
   if(InpShowHUD)
     {
      double vh=cHigh[0]/cVol[0],vl=cLow[0]/cVol[0],vt=cTypical[0]/cVol[0]; double sd=MathSqrt(MathMax(0.0,cTypical2[0]/cVol[0]-vt*vt));
      double mid=(vh+vl)*0.5; double dev=(mid!=0?100.0*(close[0]-mid)/mid:0);
      Comment(StringFormat("VWAP SSL FLIP PRO\nAnchor: %s | Bars: %d\nTrend: %s\nHigh VWAP: %s\nLow VWAP:  %s\nTypical:   %s\nStd dev:   %s\nPrice dev: %+.2f%%",PeriodName(),barsInAnchor[0],state[0]==0?"UP":"DOWN",DoubleToString(vh,Digits),DoubleToString(vl,Digits),DoubleToString(vt,Digits),DoubleToString(sd,Digits),dev));
     }
   return total;
  }
//+------------------------------------------------------------------+
