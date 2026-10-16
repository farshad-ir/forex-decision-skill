#ifndef __BOX_RED_CARPET_MQH__
#define __BOX_RED_CARPET_MQH__

#include "FractalGeometry.mqh"
#include "../MA_INERTIA/RainBowDynamics.mqh"

// ------------------------------------------------------------
// CRedCarpet
// - Independent zigzag and moving-average consultants.
// - Uses the same five Parade candidate rules and fit-driven
//   path selection used by src/Parade_ZigZag.
// - Stores theory/event records in arrays; no mandatory Print.
// ------------------------------------------------------------

enum RC_DIRECTION
{
   RC_DOWN    = -1,
   RC_UNKNOWN =  0,
   RC_UP      =  1
};

enum RC_EVENT_TYPE
{
   RC_EVENT_NONE = 0,
   RC_EVENT_ZIGZAG_THEORY,
   RC_EVENT_MA_THEORY,
   RC_EVENT_AM_REVERSAL,
   RC_EVENT_THEORY_CONTRADICTION,
   RC_EVENT_IMPORTANT_LEVEL_NEAR,
   RC_EVENT_OVERLAP_STARTED,
   RC_EVENT_OVERLAP_FINISHED,
   RC_EVENT_OVERLAP_EXTENDED
};

struct RCPathPoint
{
   int      shift;
   datetime time;
   double   price;
   int      type;       // +1 high, -1 low, 0 fixed endpoint
   int      sources;    // bitmask: fractal / Parade 1..5
};

struct RCZigZagResult
{
   string       label;      // BEST / ALTERNATIVE
   RCPathPoint  points[];
   double       sse;
   double       imbalance;
   datetime     box1Start;
   datetime     box1End;
   datetime     box0Start;
   datetime     box0End;
   string       theory;     // BULLISH / BEARISH / STUCK
   string       reason;
   double       highSlopeDeg;
   double       lowSlopeDeg;
};

struct RCEvent
{
   RC_EVENT_TYPE type;
   datetime      time;
   string        name;
   string        detail;
   double        price;
   int           direction;
};

struct RCBranch
{
   int    id;
   int    pointCount;
   double previousPrice;
   double lastPrice;
   int    direction;
   int    lastSeenStep;
};

struct RCBranchConfig
{
   int minWaitingPoints;
   int maxWaitingPoints;
};

struct RCTheory
{
   datetime time;
   string   source;
   string   view;
   string   reason;
   double   referenceHigh;
   double   referenceLow;
   double   fitError;
   double   imbalance;
};

#define RC_SRC_FRACTAL  1
#define RC_SRC_PARADE1  2
#define RC_SRC_PARADE2  4
#define RC_SRC_PARADE3  8
#define RC_SRC_PARADE4 16
#define RC_SRC_PARADE5 32

#define RC_MAX_CANDIDATES 80
#define RC_MAX_ZIGZAG_POINTS 4
#define RC_TRAILING_AFTER 3

class CRedCarpet
{
private:
   CFractalGeometry *m_fractal;
   CRainBowDynamics  *m_dyno;

   // Event / theory journal
   RCEvent   m_events[];
   RCTheory  m_theories[];
   RCZigZagResult m_results[];

   // Last processed inputs
   datetime m_lastCandle;
   datetime m_lastBoxStart;
   datetime m_lastBoxEnd;
   string   m_lastMAOpinion;
   int      m_lastMADirection;
   int      m_lastZigDirection;

   // Overlap-chain state
   bool     m_zoneReady;
   bool     m_zoneExtended;
   double   m_zoneHigh;
   double   m_zoneLow;
   datetime m_zoneStart;
   datetime m_zoneEnd;
   int      m_zoneBoxCount;

   // MA bifurcation state (member-owned; no global state)
   RCBranch       m_branches[];
   RCBranchConfig m_branchConfig;
   int            m_step;
   int            m_nextBranchId;

   // Current zigzag-engine working state
   MqlRates      m_rates[];
   RCPathPoint   m_fractals[];
   RCPathPoint   m_parade[];
   RCPathPoint   m_candidates[];
   RCPathPoint   m_workPoints[];
   RCPathPoint   m_bestA[];
   RCPathPoint   m_bestB[];
   int           m_startShift;
   int           m_endShift;
   int           m_candidateLimitHit;
   double        m_bestErrorA;
   double        m_bestErrorB;
   double        m_bestBalanceA;
   double        m_bestBalanceB;
   long          m_evaluatedPaths;

   void AddEvent(RC_EVENT_TYPE type, datetime when, string name,
                 string detail, double price=0.0, int direction=0)
   {
      int n=ArraySize(m_events);
      if(ArrayResize(m_events,n+1)!=n+1) return;
      m_events[n].type=type;
      m_events[n].time=when;
      m_events[n].name=name;
      m_events[n].detail=detail;
      m_events[n].price=price;
      m_events[n].direction=direction;
   }

   void AddTheory(datetime when,string source,string view,string reason,
                  double hi,double lo,double fit,double imbalance)
   {
      int n=ArraySize(m_theories);
      if(ArrayResize(m_theories,n+1)!=n+1) return;
      m_theories[n].time=when;
      m_theories[n].source=source;
      m_theories[n].view=view;
      m_theories[n].reason=reason;
      m_theories[n].referenceHigh=hi;
      m_theories[n].referenceLow=lo;
      m_theories[n].fitError=fit;
      m_theories[n].imbalance=imbalance;
      RC_EVENT_TYPE eventType=(StringFind(source,"MA_Advisor")==0 ? RC_EVENT_MA_THEORY : RC_EVENT_ZIGZAG_THEORY);
      AddEvent(eventType,when,source,
               view+" | "+reason,0.0,
               view=="BULLISH"?RC_UP:(view=="BEARISH"?RC_DOWN:RC_UNKNOWN));
   }

   int PriceDirection(double a,double b)
   {
      if(b>a) return 1;
      if(b<a) return -1;
      return 0;
   }

   int WaitingPeriod(int activeCount)
   {
      int waiting=activeCount-1;
      if(waiting<m_branchConfig.minWaitingPoints) waiting=m_branchConfig.minWaitingPoints;
      if(waiting>m_branchConfig.maxWaitingPoints) waiting=m_branchConfig.maxWaitingPoints;
      return waiting;
   }

   bool BranchAccepts(const RCBranch &b,double price)
   {
      if(b.pointCount<2 || b.direction==0) return true;
      if(b.direction>0) return price>=b.lastPrice;
      return price<=b.lastPrice;
   }

   void AppendBranch(RCBranch &b,double price,int step)
   {
      b.previousPrice=b.lastPrice;
      b.lastPrice=price;
      if(b.direction==0) b.direction=PriceDirection(b.previousPrice,b.lastPrice);
      b.pointCount++;
      b.lastSeenStep=step;
   }

   void RemoveBranch(int idx)
   {
      int n=ArraySize(m_branches);
      if(idx<0 || idx>=n) return;
      for(int i=idx;i<n-1;i++) m_branches[i]=m_branches[i+1];
      ArrayResize(m_branches,n-1);
   }

   void ExpireBranches()
   {
      int i=0;
      while(i<ArraySize(m_branches))
      {
         int wait=WaitingPeriod(ArraySize(m_branches));
         if(m_step-m_branches[i].lastSeenStep>=wait) RemoveBranch(i);
         else i++;
      }
   }

   int ProcessMApoint(double price)
   {
      m_step++;
      bool assigned=false;
      for(int i=0;i<ArraySize(m_branches);i++)
      {
         if(!BranchAccepts(m_branches[i],price)) continue;
         AppendBranch(m_branches[i],price,m_step);
         assigned=true;
         break;
      }
      if(!assigned)
      {
         int n=ArraySize(m_branches);
         if(ArrayResize(m_branches,n+1)!=n+1) return RC_UNKNOWN;
         m_branches[n].id=m_nextBranchId++;
         m_branches[n].pointCount=1;
         m_branches[n].previousPrice=price;
         m_branches[n].lastPrice=price;
         m_branches[n].direction=0;
         m_branches[n].lastSeenStep=m_step;
      }
      ExpireBranches();
      int up=0,down=0;
      for(int j=0;j<ArraySize(m_branches);j++)
      {
         if(m_branches[j].pointCount<2) continue;
         if(m_branches[j].direction>0) up++;
         if(m_branches[j].direction<0) down++;
      }
      if(up>down) return RC_UP;
      if(down>up) return RC_DOWN;
      return RC_UNKNOWN;
   }

   // Exact existing source convention: RainbowCenter(1/2/3).
   void MA_Advisor(datetime candleTime)
   {
      if(m_dyno==NULL) return;
      double r1=m_dyno.RainbowCenter(1);
      double r2=m_dyno.RainbowCenter(2);
      double r3=m_dyno.RainbowCenter(3);

      string opinion="RIVER_UNCLEAR";
      if(r1>r2 && r2>r3) opinion="RIVER_RISING";
      else if(r1<r2 && r2<r3) opinion="RIVER_FALLING";

      if(r1!=0.0)
      {
         int dir=ProcessMApoint(r1);
         if(dir!=RC_UNKNOWN && m_lastMADirection!=RC_UNKNOWN &&
            dir!=m_lastMADirection)
         {
            AddEvent(RC_EVENT_AM_REVERSAL,candleTime,
                     "AVERAGE_REVERSAL",
                     "Bifurcation direction changed",
                     r1,dir);
         }
         if(dir!=RC_UNKNOWN) m_lastMADirection=dir;
      }

      if(opinion!=m_lastMAOpinion)
      {
         // The direction is saved as a theory record only when it is clear.
         if(opinion=="RIVER_RISING")
            AddTheory(candleTime,"MA_Advisor","BULLISH",
                      "RainbowCenter(1)>RainbowCenter(2)>RainbowCenter(3)",
                      r1,r3,0.0,0.0);
         else if(opinion=="RIVER_FALLING")
            AddTheory(candleTime,"MA_Advisor","BEARISH",
                      "RainbowCenter(1)<RainbowCenter(2)<RainbowCenter(3)",
                      r1,r3,0.0,0.0);
         m_lastMAOpinion=opinion;
      }
   }

   void AddPathPoint(RCPathPoint &arr[],int shift,double price,int type,int source)
   {
      int n=ArraySize(arr);
      if(ArrayResize(arr,n+1)!=n+1) return;
      arr[n].shift=shift;
      arr[n].time=m_rates[shift].time;
      arr[n].price=price;
      arr[n].type=type;
      arr[n].sources=source;
   }

   int CandleDirection(int shift)
   {
      if(m_rates[shift].close>m_rates[shift].open) return 1;
      if(m_rates[shift].close<m_rates[shift].open) return -1;
      return 0;
   }

   void MergeCandidate(const RCPathPoint &p)
   {
      if(p.shift>=m_startShift || p.shift<=m_endShift) return;
      int n=ArraySize(m_candidates);
      for(int i=0;i<n;i++)
      {
         if(m_candidates[i].shift!=p.shift || m_candidates[i].type!=p.type) continue;
         m_candidates[i].sources|=p.sources;
         if(p.type==1 && p.price>m_candidates[i].price) m_candidates[i].price=p.price;
         if(p.type==-1 && p.price<m_candidates[i].price) m_candidates[i].price=p.price;
         return;
      }
      if(n>=RC_MAX_CANDIDATES) { m_candidateLimitHit=1; return; }
      if(ArrayResize(m_candidates,n+1)!=n+1) return;
      m_candidates[n]=p;
   }

   void MergeArray(RCPathPoint &arr[],int source)
   {
      for(int i=0;i<ArraySize(arr);i++)
      {
         RCPathPoint p=arr[i]; p.sources|=source; MergeCandidate(p);
      }
   }

   void BuildFractals()
   {
      ArrayResize(m_fractals,0);
      // Two bars on each side; only points fully inside the copied window.
      for(int i=m_startShift-2;i>=m_endShift+2;i--)
      {
         double h=m_rates[i].high,l=m_rates[i].low;
         bool fh=true,fl=true,hs=false,ls=false;
         for(int j=1;j<=2;j++)
         {
            if(h<m_rates[i-j].high || h<m_rates[i+j].high) fh=false;
            if(h>m_rates[i-j].high || h>m_rates[i+j].high) hs=true;
            if(l>m_rates[i-j].low || l>m_rates[i+j].low) fl=false;
            if(l<m_rates[i-j].low || l<m_rates[i+j].low) ls=true;
         }
         if(fh&&hs) AddPathPoint(m_fractals,i,h,1,RC_SRC_FRACTAL);
         if(fl&&ls) AddPathPoint(m_fractals,i,l,-1,RC_SRC_FRACTAL);
      }
   }

   int FindInitialDirection(int &start)
   {
      for(int i=m_startShift;i>=m_endShift;i--)
      {
         int d=CandleDirection(i);
         if(d!=0) { start=i; return d; }
      }
      return 0;
   }

   void BuildParade1()
   {
      ArrayResize(m_parade,0);
      int start; int dir=FindInitialDirection(start); if(dir==0) return;
      int exShift=start,oppCount=0,oppStart=-1;
      double exPrice=(dir==1?m_rates[start].high:m_rates[start].low);
      for(int i=start-1;i>=m_endShift;i--)
      {
         int cd=CandleDirection(i);
         if(dir==1 && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice) {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0) continue;
         if(cd==dir) {oppCount=0;oppStart=-1;continue;}
         if(oppCount==0) oppStart=i;
         oppCount++;
         if(oppCount>=3)
         {
            AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE1);
            dir=cd; exShift=oppStart;
            exPrice=(dir==1?m_rates[oppStart].high:m_rates[oppStart].low);
            oppCount=0;oppStart=-1;
         }
      }
      AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE1);
   }

   void BuildParade2()
   {
      ArrayResize(m_parade,0);
      int start; int dir=FindInitialDirection(start); if(dir==0) return;
      int exShift=start;
      double exPrice=(dir==1?m_rates[start].high:m_rates[start].low);
      double anchor=m_rates[start].open;
      for(int i=start-1;i>=m_endShift;i--)
      {
         int cd=CandleDirection(i);
         if(dir==1 && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice) {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0 || cd==dir) continue;
         bool broken=(dir==1?m_rates[i].low<anchor:m_rates[i].high>anchor);
         if(!broken) continue;
         AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE2);
         dir=-dir; anchor=m_rates[i].open; exShift=i;
         exPrice=(dir==1?m_rates[i].high:m_rates[i].low);
      }
      AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE2);
   }

   void BuildParade3()
   {
      ArrayResize(m_parade,0);
      int start; int dir=FindInitialDirection(start); if(dir==0) return;
      int exShift=start,anchorShift=start,favorable=0;
      double exPrice=(dir==1?m_rates[start].high:m_rates[start].low);
      double anchor=m_rates[start].open;
      for(int i=start-1;i>=m_endShift;i--)
      {
         int cd=CandleDirection(i);
         if(dir==1 && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice) {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0) continue;
         if(cd==dir)
         {
            favorable++;
            if(favorable>=RC_TRAILING_AFTER)
            {
               anchorShift=MathMax(m_endShift,anchorShift-1);
               anchor=m_rates[anchorShift].open;
               favorable=0;
            }
            continue;
         }
         bool broken=(dir==1?m_rates[i].low<anchor:m_rates[i].high>anchor);
         if(!broken) continue;
         AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE3);
         dir=-dir; anchorShift=i; anchor=m_rates[i].open; favorable=0; exShift=i;
         exPrice=(dir==1?m_rates[i].high:m_rates[i].low);
      }
      AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE3);
   }

   void BuildParade4()
   {
      ArrayResize(m_parade,0);
      int start; int dir=FindInitialDirection(start); if(dir==0) return;
      int exShift=start;
      double exPrice=(dir==1?m_rates[start].high:m_rates[start].low);
      double anchor=m_rates[start].open;
      for(int i=start-1;i>=m_endShift;i--)
      {
         int cd=CandleDirection(i);
         if(dir==1 && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice) {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0 || cd==dir) continue;
         bool broken=(dir==1?m_rates[i].close<anchor:m_rates[i].close>anchor);
         if(!broken) continue;
         AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE4);
         dir=-dir; anchor=m_rates[i].open; exShift=i;
         exPrice=(dir==1?m_rates[i].high:m_rates[i].low);
      }
      AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE4);
   }

   void BuildParade5()
   {
      ArrayResize(m_parade,0);
      int start; int dir=FindInitialDirection(start); if(dir==0) return;
      int exShift=start,anchorShift=start,favorableCount=0,nextAnchor=0;
      double exPrice=(dir==1?m_rates[start].high:m_rates[start].low);
      double anchor=m_rates[start].open;
      int favorableShifts[]; ArrayResize(favorableShifts,0);
      for(int i=start-1;i>=m_endShift;i--)
      {
         int cd=CandleDirection(i);
         if(dir==1 && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice) {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0) continue;
         if(cd==dir)
         {
            int n=ArraySize(favorableShifts);
            ArrayResize(favorableShifts,n+1); favorableShifts[n]=i;
            favorableCount++;
            if(favorableCount>=RC_TRAILING_AFTER)
            {
               while(nextAnchor<ArraySize(favorableShifts) && favorableShifts[nextAnchor]>=anchorShift) nextAnchor++;
               if(nextAnchor<ArraySize(favorableShifts))
               {
                  anchorShift=favorableShifts[nextAnchor];
                  anchor=m_rates[anchorShift].open;
                  nextAnchor++;
               }
               favorableCount=0;
            }
            continue;
         }
         bool broken=(dir==1?m_rates[i].low<anchor:m_rates[i].high>anchor);
         if(!broken) continue;
         AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE5);
         dir=-dir; anchorShift=i; anchor=m_rates[i].open; favorableCount=0;
         ArrayResize(favorableShifts,0); nextAnchor=0; exShift=i;
         exPrice=(dir==1?m_rates[i].high:m_rates[i].low);
      }
      AddPathPoint(m_parade,exShift,exPrice,dir,RC_SRC_PARADE5);
   }

   void SortCandidatesOldToNew()
   {
      int n=ArraySize(m_candidates);
      for(int i=0;i<n-1;i++)
         for(int j=i+1;j<n;j++)
            if(m_candidates[j].shift>m_candidates[i].shift)
            { RCPathPoint t=m_candidates[i];m_candidates[i]=m_candidates[j];m_candidates[j]=t; }
   }

   double ComputeFitError(RCPathPoint &v[])
   {
      int n=ArraySize(v); if(n<2) return DBL_MAX;
      double err=0.0; int seg=0;
      for(int sh=m_startShift;sh>=m_endShift;sh--)
      {
         while(seg<n-2 && sh<v[seg+1].shift) seg++;
         RCPathPoint a=v[seg],b=v[seg+1];
         int span=a.shift-b.shift;
         double predicted=b.price;
         if(span>0)
         {
            double f=(double)(a.shift-sh)/(double)span;
            predicted=a.price+f*(b.price-a.price);
         }
         double d=m_rates[sh].close-predicted; err+=d*d;
      }
      return err;
   }

   double ComputeImbalance(RCPathPoint &v[])
   {
      int n=ArraySize(v); if(n<4) return 0.0;
      double prev=MathAbs(v[2].price-v[1].price),sum=0.0; int count=0;
      for(int i=2;i<=n-3;i++)
      {
         double cur=MathAbs(v[i+1].price-v[i].price);
         sum+=MathAbs(cur-prev); prev=cur; count++;
      }
      return count>0?sum/count:0.0;
   }

   bool SamePath(RCPathPoint &a[],RCPathPoint &b[])
   {
      if(ArraySize(a)!=ArraySize(b)) return false;
      for(int i=0;i<ArraySize(a);i++)
         if(a[i].shift!=b[i].shift || a[i].type!=b[i].type) return false;
      return true;
   }

   void CopyPath(RCPathPoint &src[],RCPathPoint &dst[])
   {
      ArrayResize(dst,ArraySize(src));
      for(int i=0;i<ArraySize(src);i++) dst[i]=src[i];
   }

   void ConsiderCurrentPath()
   {
      int d=ArraySize(m_workPoints);
      RCPathPoint full[]; ArrayResize(full,d+2);
      full[0].shift=m_startShift;
      full[0].time=m_rates[m_startShift].time;
      full[0].price=m_rates[m_startShift].open;
      full[0].type=0; full[0].sources=0;
      for(int i=0;i<d;i++) full[i+1]=m_workPoints[i];
      full[d+1].shift=m_endShift;
      full[d+1].time=m_rates[m_endShift].time;
      full[d+1].price=m_rates[m_endShift].close;
      full[d+1].type=0; full[d+1].sources=0;

      double fit=ComputeFitError(full),bal=ComputeImbalance(full);
      m_evaluatedPaths++;
      if(fit<m_bestErrorA-1e-12 || (MathAbs(fit-m_bestErrorA)<=1e-12 && bal<m_bestBalanceA))
      {
         if(ArraySize(m_bestA)>0 && !SamePath(full,m_bestA))
         {
            CopyPath(m_bestA,m_bestB);
            m_bestErrorB=m_bestErrorA; m_bestBalanceB=m_bestBalanceA;
         }
         CopyPath(full,m_bestA); m_bestErrorA=fit; m_bestBalanceA=bal;
      }
      else if(!SamePath(full,m_bestA) &&
              (fit<m_bestErrorB-1e-12 || (MathAbs(fit-m_bestErrorB)<=1e-12 && bal<m_bestBalanceB)))
      {
         CopyPath(full,m_bestB); m_bestErrorB=fit; m_bestBalanceB=bal;
      }
   }

   void SearchSubsets(int startIndex)
   {
      ConsiderCurrentPath();
      int depth=ArraySize(m_workPoints);
      if(depth>=RC_MAX_ZIGZAG_POINTS) return;
      int n=ArraySize(m_candidates);
      for(int i=startIndex;i<n;i++)
      {
         RCPathPoint p=m_candidates[i];
         if(depth>0 && (m_workPoints[depth-1].type==p.type ||
                        m_workPoints[depth-1].shift==p.shift)) continue;
         ArrayResize(m_workPoints,depth+1);
         m_workPoints[depth]=p;
         SearchSubsets(i+1);
      }
      ArrayResize(m_workPoints,depth);
   }

   double SlopeDegrees(RCPathPoint &a,RCPathPoint &b)
   {
      double dx=(double)(b.time-a.time)/3600.0;
      if(dx==0.0) return 0.0;
      double dy=(b.price-a.price)/_Point;
      return MathArctan(dy/dx)*180.0/M_PI;
   }

   string InterpretPath(RCPathPoint &p[],string &reason,double &highSlope,double &lowSlope)
   {
      reason="Insufficient alternating swing points";
      highSlope=0.0; lowSlope=0.0;
      int n=ArraySize(p);
      if(n<4) return "STUCK";

      // Collect the latest two highs and latest two lows, in path order.
      int hi1=-1,hi2=-1,lo1=-1,lo2=-1;
      for(int i=1;i<n-1;i++)
      {
         if(p[i].type>0) {hi1=hi2;hi2=i;}
         if(p[i].type<0) {lo1=lo2;lo2=i;}
      }
      if(hi1<0 || hi2<0 || lo1<0 || lo2<0)
         return "STUCK";

      highSlope=SlopeDegrees(p[hi1],p[hi2]);
      lowSlope=SlopeDegrees(p[lo1],p[lo2]);
      bool higherHigh=(p[hi2].price>p[hi1].price);
      bool lowerHigh=(p[hi2].price<p[hi1].price);
      bool higherLow=(p[lo2].price>p[lo1].price);
      bool lowerLow=(p[lo2].price<p[lo1].price);

      if(higherHigh && higherLow)
      {
         reason="Higher highs and higher lows";
         return "BULLISH";
      }
      if(lowerHigh && lowerLow)
      {
         reason="Lower highs and lower lows";
         return "BEARISH";
      }
      if(MathAbs(p[hi2].price-p[hi1].price)<=_Point*2.0 && lowerLow)
      {
         reason="Peaks nearly level while floors are lower";
         return "BEARISH";
      }
      if(MathAbs(p[lo2].price-p[lo1].price)<=_Point*2.0 && higherHigh)
      {
         reason="Floors nearly level while peaks are higher";
         return "BULLISH";
      }
      reason="Mixed swing geometry; no dominant direction";
      return "STUCK";
   }

   void StoreResult(RCPathPoint &path[],string label,double fit,double bal,
                    FlatZone &box0,FlatZone &box1)
   {
      int n=ArraySize(m_results);
      if(ArrayResize(m_results,n+1)!=n+1) return;
      m_results[n].label=label;
      ArrayResize(m_results[n].points,ArraySize(path));
      for(int i=0;i<ArraySize(path);i++) m_results[n].points[i]=path[i];
      m_results[n].sse=fit;
      m_results[n].imbalance=bal;
      m_results[n].box1Start=box1.startTime;
      m_results[n].box1End=box1.endTime;
      m_results[n].box0Start=box0.startTime;
      m_results[n].box0End=box0.endTime;
      m_results[n].theory=InterpretPath(m_results[n].points,m_results[n].reason,
                                        m_results[n].highSlopeDeg,m_results[n].lowSlopeDeg);
   }

   bool RunZigZag(FlatZone &box0,FlatZone &box1)
   {
      int olderEnd=iBarShift(_Symbol,PERIOD_H1,box1.endTime,false);
      int newerStart=iBarShift(_Symbol,PERIOD_H1,box0.startTime,false);
      if(olderEnd<0 || newerStart<0 || olderEnd<=newerStart)
         return false;

      m_startShift=olderEnd;
      m_endShift=newerStart;

      int required=m_startShift+3;
      ArrayResize(m_rates,0);
      int copied=CopyRates(_Symbol,PERIOD_H1,0,required,m_rates);
      if(copied<required) return false;
      ArraySetAsSeries(m_rates,true);

      ArrayResize(m_candidates,0);
      m_candidateLimitHit=0;
      m_evaluatedPaths=0;

      BuildFractals(); MergeArray(m_fractals,RC_SRC_FRACTAL);
      BuildParade1(); MergeArray(m_parade,RC_SRC_PARADE1);
      BuildParade2(); MergeArray(m_parade,RC_SRC_PARADE2);
      BuildParade3(); MergeArray(m_parade,RC_SRC_PARADE3);
      BuildParade4(); MergeArray(m_parade,RC_SRC_PARADE4);
      BuildParade5(); MergeArray(m_parade,RC_SRC_PARADE5);
      SortCandidatesOldToNew();

      m_bestErrorA=DBL_MAX; m_bestErrorB=DBL_MAX;
      m_bestBalanceA=DBL_MAX; m_bestBalanceB=DBL_MAX;
      ArrayResize(m_bestA,0); ArrayResize(m_bestB,0); ArrayResize(m_workPoints,0);
      SearchSubsets(0);

      ArrayResize(m_results,0);
      if(ArraySize(m_bestA)>=2)
         StoreResult(m_bestA,"BEST",m_bestErrorA,m_bestBalanceA,box0,box1);
      if(ArraySize(m_bestB)>=2 && m_bestErrorB<DBL_MAX)
         StoreResult(m_bestB,"ALTERNATIVE",m_bestErrorB,m_bestBalanceB,box0,box1);

      if(ArraySize(m_results)>0)
      {
         string bestView=m_results[0].theory;
         string bestLabel=m_results[0].label;
         string bestReason=m_results[0].reason;
         double bestFit=m_results[0].sse;
         double bestImbalance=m_results[0].imbalance;
         AddTheory(box0.endTime,"ZIGZAG_"+bestLabel,bestView,bestReason,
                   box0.highPrice,box0.lowPrice,bestFit,bestImbalance);
         int dir=(bestView=="BULLISH"?RC_UP:(bestView=="BEARISH"?RC_DOWN:RC_UNKNOWN));
         if(dir!=RC_UNKNOWN && m_lastMADirection!=RC_UNKNOWN && dir!=m_lastMADirection)
            AddEvent(RC_EVENT_THEORY_CONTRADICTION,box0.endTime,
                     "THEORY_CONTRADICTION","Zigzag and MA bifurcation disagree",0.0,dir);
         if(dir!=RC_UNKNOWN) m_lastZigDirection=dir;
      }
      return ArraySize(m_results)>0;
   }

   bool BuildOverLapZone()
   {
      if(m_fractal==NULL) return false;
      int total=m_fractal.SmallBoxCount();
      if(total<=0) return false;
      FlatZone box;
      if(!m_fractal.GetSmallBox(0,box)) return false;

      double hi=box.highPrice,lo=box.lowPrice;
      datetime start=box.startTime,end=box.endTime,groupStart=box.startTime;
      int count=1;
      for(int i=1;i<total;i++)
      {
         if(!m_fractal.GetSmallBox(i,box)) break;
         if(box.endTime < groupStart-PeriodSeconds(PERIOD_H1)) break;
         groupStart=box.startTime;
         count++;
         if(box.startTime<start) start=box.startTime;
         if(box.endTime>end) end=box.endTime;
         if(box.highPrice>hi) hi=box.highPrice;
         if(box.lowPrice<lo) lo=box.lowPrice;
      }

      bool wasActive=(m_zoneReady && m_zoneBoxCount>=2);
      bool nowActive=(count>=2);
      if(!wasActive && nowActive)
         AddEvent(RC_EVENT_OVERLAP_STARTED,end,"OVERLAP_STARTED",
                  "Connected box chain started",0.0,RC_UNKNOWN);

      m_zoneHigh=hi; m_zoneLow=lo; m_zoneStart=start; m_zoneEnd=end;
      m_zoneBoxCount=count; m_zoneReady=true; m_zoneExtended=false;
      return true;
   }

   void ProcessNewBox(datetime candleTime)
   {
      if(m_fractal==NULL) return;
      FlatZone box0,box1;
      if(!m_fractal.GetSmallBox(0,box0)) return;
      if(box0.startTime==m_lastBoxStart && box0.endTime==m_lastBoxEnd) return;

      m_lastBoxStart=box0.startTime;
      m_lastBoxEnd=box0.endTime;

      if(!BuildOverLapZone()) return;
      if(m_fractal.SmallBoxCount()<2) return;
      if(!m_fractal.GetSmallBox(1,box1)) return;

      // If box 1 and box 0 touch/overlap in hourly time, defer zigzag.
      if(box1.endTime+PeriodSeconds(PERIOD_H1)>=box0.startTime)
         return;

      if(m_zoneBoxCount>=2) return; // zigzag consultant pauses in overlap
      RunZigZag(box0,box1);
   }

public:
   CRedCarpet()
   {
      m_fractal=NULL; m_dyno=NULL;
      m_lastCandle=0; m_lastBoxStart=0; m_lastBoxEnd=0;
      m_lastMAOpinion=""; m_lastMADirection=RC_UNKNOWN; m_lastZigDirection=RC_UNKNOWN;
      m_zoneReady=false; m_zoneExtended=false;
      m_zoneHigh=0; m_zoneLow=0; m_zoneStart=0; m_zoneEnd=0; m_zoneBoxCount=0;
      m_step=0; m_nextBranchId=1;
      m_branchConfig.minWaitingPoints=2; m_branchConfig.maxWaitingPoints=5;
      m_startShift=-1; m_endShift=-1; m_candidateLimitHit=0;
      m_bestErrorA=DBL_MAX; m_bestErrorB=DBL_MAX;
      m_bestBalanceA=DBL_MAX; m_bestBalanceB=DBL_MAX; m_evaluatedPaths=0;
      ArrayResize(m_events,0); ArrayResize(m_theories,0); ArrayResize(m_results,0);
      ArrayResize(m_branches,0);
   }

   void Set(CFractalGeometry &fractal,CRainBowDynamics &dyno)
   {
      m_fractal=&fractal;
      m_dyno=&dyno;
   }

   // Call once after the observer's normal box/candle updates.
   // newCandle means a newly closed H1 candle; newBoxArrived means
   // the fractal observer has announced a newly available box.
   void Update(bool newCandle,bool newBoxArrived)
   {
      if(m_fractal==NULL || m_dyno==NULL) return;

      datetime t=0;
      if(newCandle)
      {
         t=iTime(_Symbol,PERIOD_H1,1);
         if(t>0 && t!=m_lastCandle)
         {
            m_lastCandle=t;
            MA_Advisor(t); // runs even while overlap is active

            double close=iClose(_Symbol,PERIOD_H1,1);
            if(m_zoneReady && m_zoneBoxCount>=2 && close!=0.0)
            {
               bool timeExpired=(t>m_zoneEnd);
               bool outside=(close>m_zoneHigh || close<m_zoneLow);
               if(timeExpired && outside)
               {
                  AddEvent(RC_EVENT_OVERLAP_FINISHED,t,"OVERLAP_FINISHED",
                           "Time passed chain end and close exited its price range",close,
                           close>m_zoneHigh?RC_UP:RC_DOWN);
                  m_zoneReady=false; m_zoneExtended=false; m_zoneBoxCount=0;
               }
               else if(timeExpired && !outside && !m_zoneExtended)
               {
                  m_zoneExtended=true;
                  AddEvent(RC_EVENT_OVERLAP_EXTENDED,t,"OVERLAP_EXTENDED",
                           "Time passed chain end but close remains inside range",close,RC_UNKNOWN);
               }
            }
            if(newBoxArrived) ProcessNewBox(t);
         }
      }
      else if(newBoxArrived)
      {
         ProcessNewBox(iTime(_Symbol,PERIOD_H1,1));
      }
   }

   int EventCount() { return ArraySize(m_events); }
   bool GetEvent(int index,RCEvent &out)
   {
      if(index<0 || index>=ArraySize(m_events)) return false;
      out=m_events[index]; return true;
   }

   int TheoryCount() { return ArraySize(m_theories); }
   bool GetTheory(int index,RCTheory &out)
   {
      if(index<0 || index>=ArraySize(m_theories)) return false;
      out=m_theories[index]; return true;
   }

   int ZigZagResultCount() { return ArraySize(m_results); }
   bool GetZigZagResult(int index,RCZigZagResult &out)
   {
      if(index<0 || index>=ArraySize(m_results)) return false;
      out.label=m_results[index].label;
      ArrayResize(out.points,ArraySize(m_results[index].points));
      for(int i=0;i<ArraySize(out.points);i++) out.points[i]=m_results[index].points[i];
      out.sse=m_results[index].sse;
      out.imbalance=m_results[index].imbalance;
      out.box1Start=m_results[index].box1Start;
      out.box1End=m_results[index].box1End;
      out.box0Start=m_results[index].box0Start;
      out.box0End=m_results[index].box0End;
      out.theory=m_results[index].theory;
      out.reason=m_results[index].reason;
      out.highSlopeDeg=m_results[index].highSlopeDeg;
      out.lowSlopeDeg=m_results[index].lowSlopeDeg;
      return true;
   }

   string MAOpinion() { return m_lastMAOpinion; }
   int MADirection() { return m_lastMADirection; }
   int ZigZagDirection() { return m_lastZigDirection; }
   bool OverlapActive() { return (m_zoneReady && m_zoneBoxCount>=2); }
   double OverlapHigh() { return m_zoneHigh; }
   double OverlapLow() { return m_zoneLow; }
   datetime OverlapStart() { return m_zoneStart; }
   datetime OverlapEnd() { return m_zoneEnd; }
};

#endif // __RED_CARPET_MQH__
