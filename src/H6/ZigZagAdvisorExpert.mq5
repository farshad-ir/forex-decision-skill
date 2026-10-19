//+------------------------------------------------------------------+
//| ZigZagAdvisorExpert.mq5                                           |
//| Uses CZigZagAdvisor: zigzag (own window) + pluggable             |
//| interpretation rules + MA bifurcation.                            |
//|   BEST -> red, ALTERNATIVE -> yellow.                             |
//| Display only: this EA never opens or modifies any trade.          |
//+------------------------------------------------------------------+
#property copyright "forex-decision-skill (MIT)"
#property version   "1.00"

#include "ZigZagAdvisor.mqh"

enum WINDOW_MODE
{
   WINDOW_MANUAL = 0,   // Fixed shifts from inputs
   WINDOW_CUSTOM = 1    // Your own logic in FindWindow()
};

input WINDOW_MODE InpWindowMode   = WINDOW_MANUAL;
input int   InpManualOlderShift   = 53;
input int   InpManualNewerShift   = 3;

input int   InpMaxPoints          = 4;
input int   InpMaxCandidates      = 60;
input long  InpMaxPaths           = 500000;
input int   InpLevelTolPoints     = 2;        // "nearly level" tolerance for the swing rules (points)

input int   InpMAPeriod           = 30;       // demo MA only; replace GetMAPrice() with your own input
input bool  InpAlwaysShowAlt      = true;
input bool  InpShowLabels         = true;
input color InpBestColor          = clrRed;
input color InpAltColor           = clrYellow;

const string PFX = "ZZA_";

CZigZagAdvisor g_adv;
datetime       g_lastBar=0;
int            g_maHandle=INVALID_HANDLE;

//+------------------------------------------------------------------+
//| >>> YOUR OWN CODE: window (older shift, newer shift) <<<          |
//| Rule: olderShift > newerShift >= 1                                |
//+------------------------------------------------------------------+
bool FindWindow(int &olderShift,int &newerShift)
{
   olderShift=120;
   newerShift=80;
   return true;
}

//+------------------------------------------------------------------+
//| >>> YOUR OWN CODE: the MA input (one MA or an average) <<<        |
//| Return 0.0 when no value is available (the bar is then skipped).  |
//| The demo below reads one EMA on the last closed bar.              |
//+------------------------------------------------------------------+
double GetMAPrice()
{
   if(g_maHandle==INVALID_HANDLE) return 0.0;
   double buf[];
   ArraySetAsSeries(buf,true);
   if(CopyBuffer(g_maHandle,0,1,1,buf)!=1) return 0.0;
   
   
   return buf[0];
}

//+------------------------------------------------------------------+
//| Example of a NEW interpretation rule (uncomment to try):          |
//| "Last swing high is far above the first price -> bullish"          |
//|                                                                    |
//| bool MyRule_BigThrust(const ZZPoint &p[],const ZZInterpInfo &i,    |
//|                       ZZVerdict &v)                                |
//| {                                                                  |
//|    if(i.hi2<0) return false;                                       |
//|    if(p[i.hi2].price-i.startPrice > 300*i.point)                   |
//|    { v.direction=1; v.reason="Thrust above 300 points";            |
//|      return true; }                                                |
//|    return false;                                                   |
//| }                                                                  |
//| ... then in OnInit():                                              |
//|    g_adv.Interpreter().Register("BigThrust",MyRule_BigThrust,5);   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
bool GetWindow(int &olderShift,int &newerShift)
{
   bool ok=false;
   if(InpWindowMode==WINDOW_MANUAL)
   {
      olderShift=InpManualOlderShift;
      newerShift=InpManualNewerShift;
      ok=true;
   }
   else ok=FindWindow(olderShift,newerShift);

   if(!ok) return false;
   if(newerShift<1) newerShift=1;
   if(olderShift-newerShift<5) return false;
   if(olderShift+3>=Bars(_Symbol,_Period)) return false;
   return true;
}

void DrawPath(ZZResult &r,string tag,color clr,ENUM_LINE_STYLE style,int width)
{
   int n=ArraySize(r.points);
   for(int i=0;i<n-1;i++)
   {
      string name=PFX+tag+"_"+IntegerToString(i);
      if(!ObjectCreate(0,name,OBJ_TREND,0,
                       r.points[i].time,  r.points[i].price,
                       r.points[i+1].time,r.points[i+1].price))
         continue;
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_STYLE,style);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   }
}

void DrawLabel(string tag,int row,string text,color clr)
{
   string name=PFX+"LBL_"+tag;
   ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,20+row*16);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}

void Redraw(datetime barTime)
{
   ObjectsDeleteAll(0,PFX);
   int row=0;

   // 1) MA bifurcation: one point per closed bar
   double ma=GetMAPrice();
   if(ma!=0.0) g_adv.FeedMA(barTime,ma);

   // 2) zigzag on the window computed by this EA
   int older,newer;
   bool ran=false;
   if(GetWindow(older,newer))
      ran=g_adv.RunZigZag(older,newer,barTime);

   if(InpShowLabels)
   {
      DrawLabel("MA",row++,"MA bifurcation: "+ZADirText(g_adv.MADirection()),clrSilver);
      if(ran)
         DrawLabel("WIN",row++,StringFormat("Window: shift %d -> %d",older,newer),clrSilver);
      else
         DrawLabel("WIN",row++,"ZigZag: invalid window or no result",clrGray);
   }
   if(!ran) { ChartRedraw(); return; }

   // 3) draw results
   ZZResult r;
   int count=(InpAlwaysShowAlt ? g_adv.ZigZag().ResultCount() : g_adv.ZigZag().TraderResultCount());
   for(int i=0;i<count;i++)
   {
      bool ok=(InpAlwaysShowAlt ? g_adv.ZigZag().GetResult(i,r) : g_adv.ZigZag().GetTraderResult(i,r));
      if(!ok) continue;

      bool isBest=(r.label=="BEST");
      color clr=(isBest?InpBestColor:InpAltColor);
      DrawPath(r,r.label,clr,isBest?STYLE_SOLID:STYLE_DOT,isBest?2:1);

      if(InpShowLabels)
         DrawLabel(r.label,row++,r.label+": "+r.theory+" | "+r.reason+" ["+r.rule+"]",clr);
   }

   if(InpShowLabels)
   {
      string status=(g_adv.Contradiction() ? "CONTRADICTION (zigzag vs MA)"
                    : (g_adv.CombinedDirection()!=0 ? "AGREE: "+ZADirText(g_adv.CombinedDirection())
                                                    : "no combined direction"));
      DrawLabel("COMB",row++,status,g_adv.Contradiction()?clrTomato:clrLime);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_adv.Configure(_Symbol,(ENUM_TIMEFRAMES)_Period,
                   InpMaxPoints,InpMaxCandidates,3,InpMaxPaths,2,5);
   g_adv.Interpreter().SetLevelTolerancePoints(InpLevelTolPoints);

   // Add your own rules here, e.g.:
   // g_adv.Interpreter().Register("BigThrust",MyRule_BigThrust,5);

   g_maHandle=iMA(_Symbol,_Period,InpMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_lastBar=0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,PFX);
   if(g_maHandle!=INVALID_HANDLE) IndicatorRelease(g_maHandle);
}

void OnTick()
{
   datetime cur=iTime(_Symbol,_Period,0);
   if(cur==0 || cur==g_lastBar) return;
   g_lastBar=cur;
   Redraw(iTime(_Symbol,_Period,1));
   
   Print("b: ",g_adv.branch(), ", dir: ", g_adv.MADirection());
}
