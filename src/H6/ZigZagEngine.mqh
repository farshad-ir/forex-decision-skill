#ifndef __ZIGZAG_ENGINE_MQH__
#define __ZIGZAG_ENGINE_MQH__

// ------------------------------------------------------------
// CZigZagEngine
// Standalone version of the zigzag consultant inside CRedCarpet.
//  - Candidates = 2-bar fractals + five "Parade" rules.
//  - Every alternating subset (up to maxPoints swing points) is
//    scored by squared error against the close prices.
//  - Best two paths are kept: BEST and ALTERNATIVE.
//  - No dependency on FlatZone / CFractalGeometry / RainBow.
// ------------------------------------------------------------

#include "ZigZagInterpreter.mqh"

#define ZZ_SRC_FRACTAL  1
#define ZZ_SRC_PARADE1  2
#define ZZ_SRC_PARADE2  4
#define ZZ_SRC_PARADE3  8
#define ZZ_SRC_PARADE4 16
#define ZZ_SRC_PARADE5 32

struct ZZResult
{
   string   label;       // BEST / ALTERNATIVE
   ZZPoint  points[];    // oldest -> newest, includes 2 fixed endpoints
   double   sse;
   double   imbalance;
   datetime windowStart; // older end of analysed window
   datetime windowEnd;   // newer end of analysed window
   string   theory;      // BULLISH / BEARISH / STUCK
   int      direction;   // +1 / -1 / 0
   string   reason;
   string   rule;        // interpretation rule that decided
   double   highSlopeDeg;
   double   lowSlopeDeg;
};

class CZigZagEngine
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;
   double          m_point;
   int             m_maxPoints;
   int             m_maxCandidates;
   int             m_trailingAfter;
   long            m_maxPaths;      // 0 = unlimited

   MqlRates  m_rates[];
   ZZPoint   m_fractals[];
   ZZPoint   m_parade[];
   ZZPoint   m_candidates[];
   ZZPoint   m_workPoints[];
   ZZPoint   m_bestA[];
   ZZPoint   m_bestB[];
   int       m_startShift;
   int       m_endShift;
   bool      m_candidateLimitHit;
   double    m_bestErrorA, m_bestErrorB;
   double    m_bestBalanceA, m_bestBalanceB;
   long      m_evaluatedPaths;

   ZZResult  m_results[];
   int       m_traderIdx[];
   CZZInterpreter m_interp;   // pluggable interpretation rules

   // ---------------- helpers ----------------
   void AddPoint(ZZPoint &arr[],int shift,double price,int type,int source)
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

   void MergeCandidate(const ZZPoint &p)
   {
      if(p.shift>=m_startShift || p.shift<=m_endShift) return;
      int n=ArraySize(m_candidates);
      for(int i=0;i<n;i++)
      {
         if(m_candidates[i].shift!=p.shift || m_candidates[i].type!=p.type) continue;
         m_candidates[i].sources|=p.sources;
         if(p.type==1  && p.price>m_candidates[i].price) m_candidates[i].price=p.price;
         if(p.type==-1 && p.price<m_candidates[i].price) m_candidates[i].price=p.price;
         return;
      }
      if(n>=m_maxCandidates) { m_candidateLimitHit=true; return; }
      if(ArrayResize(m_candidates,n+1)!=n+1) return;
      m_candidates[n]=p;
   }

   void MergeArray(ZZPoint &arr[],int source)
   {
      for(int i=0;i<ArraySize(arr);i++)
      {
         ZZPoint p=arr[i];
         p.sources|=source;
         MergeCandidate(p);
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

   // ---------------- candidate builders ----------------
   void BuildFractals()
   {
      ArrayResize(m_fractals,0);
      for(int i=m_startShift-2;i>=m_endShift+2;i--)
      {
         double h=m_rates[i].high,l=m_rates[i].low;
         bool fh=true,fl=true,hs=false,ls=false;
         for(int j=1;j<=2;j++)
         {
            if(h<m_rates[i-j].high || h<m_rates[i+j].high) fh=false;
            if(h>m_rates[i-j].high || h>m_rates[i+j].high) hs=true;
            if(l>m_rates[i-j].low  || l>m_rates[i+j].low)  fl=false;
            if(l<m_rates[i-j].low  || l<m_rates[i+j].low)  ls=true;
         }
         if(fh&&hs) AddPoint(m_fractals,i,h,1,ZZ_SRC_FRACTAL);
         if(fl&&ls) AddPoint(m_fractals,i,l,-1,ZZ_SRC_FRACTAL);
      }
   }

   // 3 consecutive opposite candles -> reversal
   void BuildParade1()
   {
      ArrayResize(m_parade,0);
      int start; int dir=FindInitialDirection(start); if(dir==0) return;
      int exShift=start,oppCount=0,oppStart=-1;
      double exPrice=(dir==1?m_rates[start].high:m_rates[start].low);
      for(int i=start-1;i>=m_endShift;i--)
      {
         int cd=CandleDirection(i);
         if(dir==1  && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice)  {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0) continue;
         if(cd==dir) {oppCount=0;oppStart=-1;continue;}
         if(oppCount==0) oppStart=i;
         oppCount++;
         if(oppCount>=3)
         {
            AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE1);
            dir=cd; exShift=oppStart;
            exPrice=(dir==1?m_rates[oppStart].high:m_rates[oppStart].low);
            oppCount=0;oppStart=-1;
         }
      }
      AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE1);
   }

   // reversal when an opposite candle's extreme breaks the anchor open
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
         if(dir==1  && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice)  {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0 || cd==dir) continue;
         bool broken=(dir==1?m_rates[i].low<anchor:m_rates[i].high>anchor);
         if(!broken) continue;
         AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE2);
         dir=-dir; anchor=m_rates[i].open; exShift=i;
         exPrice=(dir==1?m_rates[i].high:m_rates[i].low);
      }
      AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE2);
   }

   // like Parade2, anchor trails one bar back after N favorable candles
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
         if(dir==1  && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice)  {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0) continue;
         if(cd==dir)
         {
            favorable++;
            if(favorable>=m_trailingAfter)
            {
               anchorShift=MathMax(m_endShift,anchorShift-1);
               anchor=m_rates[anchorShift].open;
               favorable=0;
            }
            continue;
         }
         bool broken=(dir==1?m_rates[i].low<anchor:m_rates[i].high>anchor);
         if(!broken) continue;
         AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE3);
         dir=-dir; anchorShift=i; anchor=m_rates[i].open; favorable=0; exShift=i;
         exPrice=(dir==1?m_rates[i].high:m_rates[i].low);
      }
      AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE3);
   }

   // like Parade2 but break is judged by CLOSE
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
         if(dir==1  && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice)  {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0 || cd==dir) continue;
         bool broken=(dir==1?m_rates[i].close<anchor:m_rates[i].close>anchor);
         if(!broken) continue;
         AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE4);
         dir=-dir; anchor=m_rates[i].open; exShift=i;
         exPrice=(dir==1?m_rates[i].high:m_rates[i].low);
      }
      AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE4);
   }

   // trailing anchor moves to the favorable candles themselves
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
         if(dir==1  && m_rates[i].high>exPrice) {exPrice=m_rates[i].high;exShift=i;}
         if(dir==-1 && m_rates[i].low<exPrice)  {exPrice=m_rates[i].low;exShift=i;}
         if(cd==0) continue;
         if(cd==dir)
         {
            int n=ArraySize(favorableShifts);
            ArrayResize(favorableShifts,n+1); favorableShifts[n]=i;
            favorableCount++;
            if(favorableCount>=m_trailingAfter)
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
         AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE5);
         dir=-dir; anchorShift=i; anchor=m_rates[i].open; favorableCount=0;
         ArrayResize(favorableShifts,0); nextAnchor=0; exShift=i;
         exPrice=(dir==1?m_rates[i].high:m_rates[i].low);
      }
      AddPoint(m_parade,exShift,exPrice,dir,ZZ_SRC_PARADE5);
   }

   void SortCandidatesOldToNew()
   {
      int n=ArraySize(m_candidates);
      for(int i=0;i<n-1;i++)
         for(int j=i+1;j<n;j++)
            if(m_candidates[j].shift>m_candidates[i].shift)
            { ZZPoint t=m_candidates[i];m_candidates[i]=m_candidates[j];m_candidates[j]=t; }
   }

   // ---------------- scoring ----------------
   double ComputeFitError(ZZPoint &v[])
   {
      int n=ArraySize(v); if(n<2) return DBL_MAX;
      double err=0.0; int seg=0;
      for(int sh=m_startShift;sh>=m_endShift;sh--)
      {
         while(seg<n-2 && sh<v[seg+1].shift) seg++;
         ZZPoint a=v[seg],b=v[seg+1];
         int span=a.shift-b.shift;
         double predicted=b.price;
         if(span>0)
         {
            double f=(double)(a.shift-sh)/(double)span;
            predicted=a.price+f*(b.price-a.price);
         }
         double d=m_rates[sh].close-predicted;
         err+=d*d;
      }
      return err;
   }

   double ComputeImbalance(ZZPoint &v[])
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

   bool SamePath(ZZPoint &a[],ZZPoint &b[])
   {
      if(ArraySize(a)!=ArraySize(b)) return false;
      for(int i=0;i<ArraySize(a);i++)
         if(a[i].shift!=b[i].shift || a[i].type!=b[i].type) return false;
      return true;
   }

   void CopyPath(ZZPoint &src[],ZZPoint &dst[])
   {
      ArrayResize(dst,ArraySize(src));
      for(int i=0;i<ArraySize(src);i++) dst[i]=src[i];
   }

   void ConsiderCurrentPath()
   {
      int d=ArraySize(m_workPoints);
      ZZPoint full[]; ArrayResize(full,d+2);
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
      if(m_maxPaths>0 && m_evaluatedPaths>=m_maxPaths) return;
      ConsiderCurrentPath();
      int depth=ArraySize(m_workPoints);
      if(depth>=m_maxPoints) return;
      int n=ArraySize(m_candidates);
      for(int i=startIndex;i<n;i++)
      {
         ZZPoint p=m_candidates[i];
         if(depth>0 && (m_workPoints[depth-1].type==p.type ||
                        m_workPoints[depth-1].shift==p.shift)) continue;
         ArrayResize(m_workPoints,depth+1);
         m_workPoints[depth]=p;
         SearchSubsets(i+1);
      }
      ArrayResize(m_workPoints,depth);
   }

   // slope in "degrees": x = bars (time/period seconds), y = points
   double SlopeDegrees(ZZPoint &a,ZZPoint &b)
   {
      double dx=(double)(b.time-a.time)/(double)PeriodSeconds(m_tf);
      if(dx==0.0 || m_point<=0.0) return 0.0;
      double dy=(b.price-a.price)/m_point;
      return MathArctan(dy/dx)*180.0/M_PI;
   }

   void StoreResult(ZZPoint &path[],string label,double fit,double bal)
   {
      int n=ArraySize(m_results);
      if(ArrayResize(m_results,n+1)!=n+1) return;
      m_results[n].label=label;
      ArrayResize(m_results[n].points,ArraySize(path));
      for(int i=0;i<ArraySize(path);i++) m_results[n].points[i]=path[i];
      m_results[n].sse=fit;
      m_results[n].imbalance=bal;
      m_results[n].windowStart=m_rates[m_startShift].time;
      m_results[n].windowEnd  =m_rates[m_endShift].time;
      ZZInterpInfo info;
      m_interp.BuildInfo(m_results[n].points,m_point,info);

      m_results[n].highSlopeDeg=0.0;
      m_results[n].lowSlopeDeg=0.0;
      if(info.hasTwoHighsTwoLows)
      {
         m_results[n].highSlopeDeg=SlopeDegrees(m_results[n].points[info.hi1],m_results[n].points[info.hi2]);
         m_results[n].lowSlopeDeg =SlopeDegrees(m_results[n].points[info.lo1],m_results[n].points[info.lo2]);
      }

      ZZVerdict verdict;
      m_interp.Evaluate(m_results[n].points,info,verdict);
      m_results[n].direction=verdict.direction;
      m_results[n].theory=(verdict.direction>0?"BULLISH":(verdict.direction<0?"BEARISH":"STUCK"));
      m_results[n].reason=verdict.reason;
      m_results[n].rule=verdict.rule;
   }

   void CountSwingTypes(ZZPoint &path[],int &highs,int &lows)
   {
      highs=0; lows=0;
      for(int i=1;i<ArraySize(path)-1;i++)
      {
         if(path[i].type>0) highs++;
         if(path[i].type<0) lows++;
      }
   }

   // Report both hypotheses only if swing counts or theories differ.
   void BuildTraderSelection()
   {
      ArrayResize(m_traderIdx,0);
      int cnt=ArraySize(m_results);
      if(cnt<=0) return;
      ArrayResize(m_traderIdx,1); m_traderIdx[0]=0;
      if(cnt<2) return;

      int bh,bl,ah,al;
      CountSwingTypes(m_results[0].points,bh,bl);
      CountSwingTypes(m_results[1].points,ah,al);
      bool sameCounts=(bh==ah && bl==al);
      bool sameTheory=(m_results[0].theory==m_results[1].theory);
      if(sameCounts && sameTheory) return;
      ArrayResize(m_traderIdx,2); m_traderIdx[0]=0; m_traderIdx[1]=1;
   }

   void CopyResult(ZZResult &src,ZZResult &dst)
   {
      dst.label=src.label;
      ArrayResize(dst.points,ArraySize(src.points));
      for(int i=0;i<ArraySize(src.points);i++) dst.points[i]=src.points[i];
      dst.sse=src.sse;
      dst.imbalance=src.imbalance;
      dst.windowStart=src.windowStart;
      dst.windowEnd=src.windowEnd;
      dst.theory=src.theory;
      dst.direction=src.direction;
      dst.reason=src.reason;
      dst.rule=src.rule;
      dst.highSlopeDeg=src.highSlopeDeg;
      dst.lowSlopeDeg=src.lowSlopeDeg;
   }

public:
   CZigZagEngine()
   {
      Configure(_Symbol,(ENUM_TIMEFRAMES)_Period);
   }

   void Configure(string symbol,ENUM_TIMEFRAMES tf,
                  int maxPoints=4,int maxCandidates=80,
                  int trailingAfter=3,long maxPaths=0)
   {
      m_symbol=symbol;
      m_tf=(tf==PERIOD_CURRENT?(ENUM_TIMEFRAMES)_Period:tf);
      m_point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      m_maxPoints=MathMax(1,maxPoints);
      m_maxCandidates=MathMax(4,maxCandidates);
      m_trailingAfter=MathMax(1,trailingAfter);
      m_maxPaths=maxPaths;
      m_startShift=-1; m_endShift=-1;
      m_candidateLimitHit=false;
      m_evaluatedPaths=0;
      ArrayResize(m_results,0);
      ArrayResize(m_traderIdx,0);
   }

   // Window: olderShift (start, bigger shift) -> newerShift (end).
   // Shift 0 = forming bar, 1 = last closed bar.
   bool RunByShift(int olderShift,int newerShift)
   {
      ArrayResize(m_results,0);
      ArrayResize(m_traderIdx,0);
      if(newerShift<0 || olderShift<=newerShift) return false;

      m_startShift=olderShift;
      m_endShift=newerShift;

      int required=m_startShift+3;
      ArraySetAsSeries(m_rates,true);
      int copied=CopyRates(m_symbol,m_tf,0,required,m_rates);
      if(copied<required) return false;

      ArrayResize(m_candidates,0);
      m_candidateLimitHit=false;
      m_evaluatedPaths=0;

      BuildFractals(); MergeArray(m_fractals,ZZ_SRC_FRACTAL);
      BuildParade1();  MergeArray(m_parade,ZZ_SRC_PARADE1);
      BuildParade2();  MergeArray(m_parade,ZZ_SRC_PARADE2);
      BuildParade3();  MergeArray(m_parade,ZZ_SRC_PARADE3);
      BuildParade4();  MergeArray(m_parade,ZZ_SRC_PARADE4);
      BuildParade5();  MergeArray(m_parade,ZZ_SRC_PARADE5);
      SortCandidatesOldToNew();

      m_bestErrorA=DBL_MAX; m_bestErrorB=DBL_MAX;
      m_bestBalanceA=DBL_MAX; m_bestBalanceB=DBL_MAX;
      ArrayResize(m_bestA,0); ArrayResize(m_bestB,0); ArrayResize(m_workPoints,0);
      SearchSubsets(0);

      if(ArraySize(m_bestA)>=2)
         StoreResult(m_bestA,"BEST",m_bestErrorA,m_bestBalanceA);
      if(ArraySize(m_bestB)>=2 && m_bestErrorB<DBL_MAX)
         StoreResult(m_bestB,"ALTERNATIVE",m_bestErrorB,m_bestBalanceB);

      BuildTraderSelection();
      return ArraySize(m_results)>0;
   }

   // Window given by times (like the original box1.endTime -> box0.startTime).
   bool RunByTime(datetime olderTime,datetime newerTime)
   {
      int o=iBarShift(m_symbol,m_tf,olderTime,false);
      int n=iBarShift(m_symbol,m_tf,newerTime,false);
      if(o<0 || n<0) return false;
      return RunByShift(o,n);
   }

   CZZInterpreter *Interpreter() { return GetPointer(m_interp); }

   int  ResultCount()          { return ArraySize(m_results); }
   int  TraderResultCount()    { return ArraySize(m_traderIdx); }
   long EvaluatedPaths()       { return m_evaluatedPaths; }
   bool CandidateLimitHit()    { return m_candidateLimitHit; }
   int  CandidateCount()       { return ArraySize(m_candidates); }

   bool GetResult(int index,ZZResult &out)
   {
      if(index<0 || index>=ArraySize(m_results)) return false;
      CopyResult(m_results[index],out);
      return true;
   }

   bool GetTraderResult(int index,ZZResult &out)
   {
      if(index<0 || index>=ArraySize(m_traderIdx)) return false;
      int src=m_traderIdx[index];
      if(src<0 || src>=ArraySize(m_results)) return false;
      CopyResult(m_results[src],out);
      return true;
   }
};

#endif // __ZIGZAG_ENGINE_MQH__
