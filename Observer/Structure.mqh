#ifndef __STRUCTURE_MQH__
#define __STRUCTURE_MQH__

#include "Common.mqh"
//------------------------------------------------
// مسئول:
// 1- خواندن فراکتال ها
// 2- استخراج لوکال ماکس و مین
// 3- ساخت مسیر زیگزاگ
// 4- تشخیص Inside / Breakout
//------------------------------------------------

class CStructure
{
private:
   int    BarsBack;
   double ThresholdPoints;

   int fractalHandle;

   double upBuffer[];
   double downBuffer[];

   Pivot highs[], maxhighs[];
   Pivot lows[], minlows[];
   Pivot merged[], pured[], path[];

public:
   CStructure();
   ~CStructure();

   bool Init();
   void Deinit();

   int Update(int reqNumber);
   void GetPath(Pivot &out[]);
   
   double FractalUP(int shift);
   double FractalDOWN(int shift);
   int    FractalBars();
   
   void DetectInsideBreakout();
   string GetPattern();
   string Get_IB();

private:

   void ExtractPivots();
   void FindLocalMax();
   void FindLocalMin();
   void MergePivots();
   void PuredPivots();
   void BuildSwing();

   bool IsValidMove(double p1, double p2, int type);
};

double CStructure::FractalUP(int shift)
{

   if(shift < 0 || shift >= ArraySize(upBuffer))
      return EMPTY_VALUE;
      
   if(shift>=2) 
      return upBuffer[shift-2]; 
   else
      return 0.0;
   
}

double CStructure::FractalDOWN(int shift)
{

   if(shift < 0 || shift >= ArraySize(downBuffer))
      return EMPTY_VALUE;
      
      
   if(shift>=2) 
      return downBuffer[shift-2]; 
   else
      return 0.0;
   
}

int CStructure::FractalBars()
{
   return MathMin(ArraySize(upBuffer), ArraySize(downBuffer) );
}
// =========================
// constructor
// =========================
CStructure::CStructure()
{
   ThresholdPoints = 400;
   fractalHandle = INVALID_HANDLE;
}

// =========================
// destructor
// =========================
CStructure::~CStructure()
{
   Deinit();
}

// =========================
// init
// =========================
bool CStructure::Init()
{
   fractalHandle = iFractals(_Symbol, _Period);
   if(fractalHandle == INVALID_HANDLE)
   {
      Print("Fractal handle error");
      return false;
   }

   ArraySetAsSeries(upBuffer, true);
   ArraySetAsSeries(downBuffer, true);

   return true;
}

// =========================
// deinit
// =========================
void CStructure::Deinit()
{
   if(fractalHandle != INVALID_HANDLE)
   {
      IndicatorRelease(fractalHandle);
      fractalHandle = INVALID_HANDLE;
   }
}

// =========================
// update 
// =========================
int CStructure::Update(int reqNumber)
{

      int n = 0 ; 
      BarsBack = 0;

      do
      {
         BarsBack += 300;
         if(BarsBack > 60000) break;
         
         if(fractalHandle == INVALID_HANDLE) {Print("INVALID_HANDLE");return false;}
         if(CopyBuffer(fractalHandle, 0, 2, BarsBack, upBuffer) <= 0) {Print("Copy up ",BarsBack);return false;}
         if(CopyBuffer(fractalHandle, 1, 2, BarsBack, downBuffer) <= 0) {Print("Copy down ",BarsBack);return false;}
         
         

         ExtractPivots();
         FindLocalMax();
         FindLocalMin();
         MergePivots();
         PuredPivots();
         BuildSwing();

         n = ArraySize(path);
         

      } while(n < reqNumber );
      
      n = ArraySize(path);
      if( n > reqNumber )
         ArrayResize(path, reqNumber);
      
      
      
      //Print(reqNumber);
      return ArraySize(path);
}

// =========================
// get path (safe copy)
// =========================
void CStructure::GetPath(Pivot &out[])
{
   int n = ArraySize(path);
   if(n <= 0){
      ArrayResize(out, 0);
   }

   ArrayResize(out, n);

   for(int i=0; i<n; i++)
      out[i] = path[i];
}

void CStructure::DetectInsideBreakout()
{
   int n = ArraySize(path);
   
   if(n < 3)
      return;

   // پاک کردن مقادیر قبلی
   for(int i=0; i<n; i++)
      path[i].ib = IB_UNKNOWN;

   // دو رأس آخر مرجع هستند
   path[n-1].ib = IB_UNKNOWN;
   path[n-2].ib = IB_UNKNOWN;
   
   path[n-1].ib_distance = 0;
   path[n-2].ib_distance = 0;

   // از انتها به ابتدا
   for(int i=n-3; i>=0; i--)
   {
      int next = i + 2;
      
      //Print("i=",i," next=",next);

      if(next >= n)
         continue;


      double diff = 0;

      // ================= HIGH =================
      if(path[i].type > 0)
      {
         diff = path[next].price - path[i].price;

         if(diff >= 0)
         {
            path[i].ib = IB_INSIDE;
            path[i].ib_distance = diff / _Point;
         }
         else
         {
            path[i].ib = IB_BREAKOUT;
            path[i].ib_distance = diff / _Point;
         }
      }

      // ================= LOW =================
      else
      {
         diff = path[i].price - path[next].price;

         if(diff >= 0)
         {
            path[i].ib = IB_INSIDE;
            path[i].ib_distance = diff / _Point;
         }
         else
         {
            path[i].ib = IB_BREAKOUT;
            path[i].ib_distance = diff / _Point;
         }
      }

      //Print("assigned ",i,"->", (int)path[i].ib);
   }
}



void CStructure::ExtractPivots()
{
   ArrayResize(highs, 0);
   ArrayResize(lows, 0);

   for(int i = 0; i < BarsBack; i++)
   {
      int tt = i + 2 ;
      if(upBuffer[i] > 0.0 && upBuffer[i] < 22)
      {
         int s = ArraySize(highs);
         ArrayResize(highs, s + 1);

         highs[s].type = 1;
         highs[s].shift = i;
         highs[s].time  = iTime(_Symbol,_Period,tt);
         highs[s].price = upBuffer[i];
         highs[s].ib = IB_UNKNOWN;
      }

      if(downBuffer[i] > 0.0 && downBuffer[i] < 22)
      {
         int s = ArraySize(lows);
         ArrayResize(lows, s + 1);

         lows[s].type = -1;
         lows[s].shift = i;
         lows[s].time  = iTime(_Symbol,_Period,tt);
         lows[s].price = downBuffer[i];
         lows[s].ib = IB_UNKNOWN;
      }
   }
}

void CStructure::FindLocalMax()
{
   ArrayResize(maxhighs, 0);

   for(int j = 1; j < ArraySize(highs) - 1; j++)
   {
      if(highs[j].price > highs[j-1].price &&
         highs[j].price > highs[j+1].price)
      {
         int n = ArraySize(maxhighs);
         ArrayResize(maxhighs, n + 1);
         maxhighs[n] = highs[j];
      }
   }
}

void CStructure::FindLocalMin()
{
   ArrayResize(minlows, 0);

   for(int j = 1; j < ArraySize(lows) - 1; j++)
   {
      if(lows[j].price < lows[j-1].price &&
         lows[j].price < lows[j+1].price)
      {
         int n = ArraySize(minlows);
         ArrayResize(minlows, n + 1);
         minlows[n] = lows[j];
      }
   }
}

void CStructure::MergePivots()
{
   ArrayResize(merged, 0);

   for(int shift = 2; shift < BarsBack; shift++)
   {
      for(int i=0; i<ArraySize(maxhighs); i++)
      {
         if(shift == maxhighs[i].shift)
         {
            int k = ArraySize(merged);
            ArrayResize(merged, k+1);
            merged[k] = maxhighs[i];
            break;
         }
      }

      for(int i=0; i<ArraySize(minlows); i++)
      {
         if(shift == minlows[i].shift)
         {
            int k = ArraySize(merged);
            ArrayResize(merged, k+1);
            merged[k] = minlows[i];
            break;
         }
      }
   }
}

void CStructure::PuredPivots()
{
   ArrayResize(pured, 0);

   for(int j=0; j<ArraySize(merged); j++)
   {
      int t = merged[j].type;

      int i;
      for(i=j+1; i<ArraySize(merged); i++)
         if(t != merged[i].type) break;

      int n = ArraySize(pured);
      ArrayResize(pured, n+1);

      if(i == j+1)
      {
         pured[n] = merged[j];
         j = i-1;
         continue;
      }

      if(t > 0)
      {
         double maxp = merged[j].price;
         int sht = merged[j].shift;
         datetime tt = merged[j].time;

         for(int k=j+1; k<i; k++)
         {
            if(merged[k].price > maxp)
            {
               maxp = merged[k].price;
               sht  = merged[k].shift;
               tt   = merged[k].time;
            }
         }

         pured[n].type = t;
         pured[n].price = maxp;
         pured[n].shift = sht;
         pured[n].time  = tt;
         pured[n].ib    = IB_UNKNOWN;

         j = i-1;
      }
      else
      {
         double minp = merged[j].price;
         int sht = merged[j].shift;
         datetime tt = merged[j].time;

         for(int k=j+1; k<i; k++)
         {
            if(merged[k].price < minp)
            {
               minp = merged[k].price;
               sht = merged[k].shift;
               tt  = merged[k].time;
            }
         }

         pured[n].type = t;
         pured[n].price = minp;
         pured[n].shift = sht;
         pured[n].time  = tt;
         pured[n].ib    = IB_UNKNOWN;

         j = i-1;
      }
   }
}

bool CStructure::IsValidMove(double p1, double p2, int type)
{
   if((type > 0 && (p2 - p1) > ThresholdPoints * _Point) ||
      (type < 0 && (p1 - p2) > ThresholdPoints * _Point))
      return true;

   return false;
}

void CStructure::BuildSwing()
{
   ArrayResize(path, 0);

   int n = ArraySize(pured);
   if(n < 2) return;

   ArrayResize(path, 1);
   path[0] = pured[0];

   for(int i=1; i<n; i++)
   {
      Pivot current = pured[i];
      
      if(ArraySize(path) == 0){
         //Print("Reset to Zero");
         ArrayResize(path,1);
         path[0] = pured[0];
      }
      
      int lastIndex = ArraySize(path)-1;

      Pivot last = path[lastIndex];

      if(IsValidMove(last.price, current.price, current.type))
      {
         int s = ArraySize(path);
         ArrayResize(path, s+1);
         path[s] = current;
      }
      else
      {
         // اصلاح مسیر
         int s = ArraySize(path);
         if(s > 0)
            ArrayResize(path, s-1);
      }
   }


}

//new 
string CStructure::GetPattern()
{
   string s="";

   int n = ArraySize(path)-1;

   for(int i=n;i>=0;i--)
   {
      if(path[i].ib == IB_UNKNOWN)
         continue;

      string hl = (path[i].type > 0) ? "H" : "L";

      string ib = (path[i].ib == IB_INSIDE) ? "I" : "B";

      string movement = DoubleToString(path[i].ib_distance/10,1);
      
      string price = DoubleToString(path[i].price,4);
      
      string price_="";
      if(i+1<=n) price_ = DoubleToString(path[i+1].price,4);
      
      string sTime = TimeToString(path[i+1]  .time);
      string eTime = TimeToString(path[i].time);
      
      if(s!="")
         s += "\n";

      s += hl + ":" + ib + "(" + movement + ")("+ price +")("+price_+")("+sTime+")("+eTime+")";
   }

   return s;
}

string CStructure::Get_IB()
{
   string s="(";
   
   
   int n = ArraySize(path)-1;
   
   
   s += TimeToString(path[n].time);
   s += ", ";
   s += TimeToString(path[0].time);
   s += ") ";
   

   for(int i=n;i>=0;i--)
   {
      if(path[i].ib == IB_UNKNOWN)
         continue;
      
      string ib = (path[i].ib == IB_INSIDE) ? "I" : "B";

      s += ib;
   }

   return s;
}
#endif


