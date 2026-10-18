#ifndef __BOX_RED_CARPET_MQH__
#define __BOX_RED_CARPET_MQH__

#include "FractalGeometry.mqh"
#include "../MA_INERTIA/RainBowDynamics.mqh"
#include "H6/ZigZagAdvisor.mqh"

// ------------------------------------------------------------
// CRedCarpet
// - H1 consultant: zigzag + MA bifurcation are computed by
//   CZigZagAdvisor (m_advH1). CRedCarpet keeps the same event /
//   theory journal and the same public API as before.
// - H6 consultant (new): zigzag on 50 H6 candles (shift 53 -> 3),
//   run once per closed H6 candle, published as ONE event
//   (RC_EVENT_H6_ZIGZAG) together with the slow averages.
// - Stores theory/event records in arrays; no mandatory Print.
// ------------------------------------------------------------

enum RC_THEORY_DIRECTION
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
   RC_EVENT_IMPORTANT_LEVEL_TOUCHED,
   RC_EVENT_OVERLAP_STARTED,
   RC_EVENT_OVERLAP_FINISHED,
   RC_EVENT_OVERLAP_EXTENDED,
   RC_EVENT_H6_ZIGZAG            // new: appended last, older values keep their numbers
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

#define RC_MAX_CANDIDATES    80
#define RC_MAX_ZIGZAG_POINTS 4
#define RC_TRAILING_AFTER    3

#define RC_H6_OLDER_SHIFT    53   // 53 -> 3 = 50 H6 candles
#define RC_H6_NEWER_SHIFT    3
#define RC_H6_MAX_PATHS      3000000   // safety cap for the H6 search

class CRedCarpet
{
private:
   CFractalGeometry *m_fractal;
   CRainBowDynamics *m_dyno;       // H1 averages (as before)
   CRainBowDynamics *m_slowDyno;   // optional slow averages for the H6 event

   // Consultants (zigzag engine + interpretation rules + MA bifurcation)
   CZigZagAdvisor m_advH1;
   CZigZagAdvisor m_advH6;

   // Event / theory journal
   RCEvent        m_events[];
   RCTheory       m_theories[];
   RCZigZagResult m_results[];         // H1 results (engine -> RC format)
   RCZigZagResult m_traderResults[];   // H1 results the trader should read

   // Last processed inputs
   datetime m_lastCandle;
   datetime m_lastBoxStart;
   datetime m_lastBoxEnd;

   // H6 state
   datetime m_lastH6Fed;
   datetime m_lastH6Run;
   int      m_h6OlderShift;
   int      m_h6NewerShift;

   // Important levels: only SmallBox(0)
   datetime m_levelBoxStart;
   datetime m_levelBoxEnd;
   bool     m_levelHighTouched;
   bool     m_levelLowTouched;

   // Overlap-chain state
   bool     m_zoneReady;
   bool     m_zoneExtended;
   double   m_zoneHigh;
   double   m_zoneLow;
   datetime m_zoneStart;
   datetime m_zoneEnd;
   int      m_zoneBoxCount;
   bool     closed_due_break;

   // ------------------------------------------------------------
   // Journal
   // ------------------------------------------------------------
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

   // ------------------------------------------------------------
   // Engine result (ZZResult) -> RedCarpet result (RCZigZagResult)
   // ------------------------------------------------------------
   void FillRCResult(RCZigZagResult &dst,ZZResult &src,
                     datetime b1s,datetime b1e,datetime b0s,datetime b0e)
   {
      dst.label=src.label;
      int n=ArraySize(src.points);
      ArrayResize(dst.points,n);
      for(int i=0;i<n;i++)
      {
         dst.points[i].shift  =src.points[i].shift;
         dst.points[i].time   =src.points[i].time;
         dst.points[i].price  =src.points[i].price;
         dst.points[i].type   =src.points[i].type;
         dst.points[i].sources=src.points[i].sources;
      }
      dst.sse=src.sse;
      dst.imbalance=src.imbalance;
      dst.box1Start=b1s;
      dst.box1End=b1e;
      dst.box0Start=b0s;
      dst.box0End=b0e;
      dst.theory=src.theory;
      dst.reason=src.reason;
      dst.highSlopeDeg=src.highSlopeDeg;
      dst.lowSlopeDeg=src.lowSlopeDeg;
   }

   void CopyRCResult(RCZigZagResult &src,RCZigZagResult &dst)
   {
      dst.label=src.label;
      ArrayResize(dst.points,ArraySize(src.points));
      for(int i=0;i<ArraySize(dst.points);i++) dst.points[i]=src.points[i];
      dst.sse=src.sse;
      dst.imbalance=src.imbalance;
      dst.box1Start=src.box1Start;
      dst.box1End=src.box1End;
      dst.box0Start=src.box0Start;
      dst.box0End=src.box0End;
      dst.theory=src.theory;
      dst.reason=src.reason;
      dst.highSlopeDeg=src.highSlopeDeg;
      dst.lowSlopeDeg=src.lowSlopeDeg;
   }

   void SyncH1Results(FlatZone &box0,FlatZone &box1)
   {
      CZigZagEngine *zz=m_advH1.ZigZag();

      ArrayResize(m_results,0);
      for(int i=0;i<zz.ResultCount();i++)
      {
         ZZResult z;
         if(!zz.GetResult(i,z)) continue;
         int k=ArraySize(m_results);
         if(ArrayResize(m_results,k+1)!=k+1) return;
         FillRCResult(m_results[k],z,box1.startTime,box1.endTime,box0.startTime,box0.endTime);
      }

      ArrayResize(m_traderResults,0);
      for(int i=0;i<zz.TraderResultCount();i++)
      {
         ZZResult z;
         if(!zz.GetTraderResult(i,z)) continue;
         int k=ArraySize(m_traderResults);
         if(ArrayResize(m_traderResults,k+1)!=k+1) return;
         FillRCResult(m_traderResults[k],z,box1.startTime,box1.endTime,box0.startTime,box0.endTime);
      }
   }

   // ------------------------------------------------------------
   // MA consultant (H1): bifurcation lives in the advisor
   // Exact existing source convention: RainbowCenter(1).
   // ------------------------------------------------------------
   void MA_Advisor(datetime candleTime)
   {
      if(m_dyno==NULL) return;
      double r1=m_dyno.RainbowCenter(1);

      if(r1!=0.0)
      {
         int dir=m_advH1.FeedMA(candleTime,r1);
         if(m_advH1.MA().JustReversed())
         {
            AddEvent(RC_EVENT_AM_REVERSAL,candleTime,
                     "AVERAGE_REVERSAL",
                     "Bifurcation direction changed",
                     r1,dir);
         }
      }
   }

   // ------------------------------------------------------------
   // Zigzag consultant (H1): window = box1.end -> box0.start
   // ------------------------------------------------------------
   bool RunZigZag(FlatZone &box0,FlatZone &box1)
   {
      int olderEnd=iBarShift(_Symbol,PERIOD_H1,box1.endTime,false);
      int newerStart=iBarShift(_Symbol,PERIOD_H1,box0.startTime,false);
      if(olderEnd<0 || newerStart<0 || olderEnd<=newerStart)
         return false;

      if(!m_advH1.RunZigZag(olderEnd,newerStart,box0.endTime))
         return false;

      SyncH1Results(box0,box1);

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
         if(dir!=RC_UNKNOWN && m_advH1.Contradiction())
            AddEvent(RC_EVENT_THEORY_CONTRADICTION,box0.endTime,
                     "THEORY_CONTRADICTION","Zigzag and MA bifurcation disagree",0.0,dir);
      }
      return ArraySize(m_results)>0;
   }

   // ------------------------------------------------------------
   // H6 consultant: zigzag on 50 H6 candles, once per closed H6 candle
   // ------------------------------------------------------------
   void ProcessH6Candle()
   {
      datetime t6=iTime(_Symbol,PERIOD_H6,1);          // last closed H6 candle
      if(t6<=0 || t6==m_lastH6Run) return;

      // slow averages: one bifurcation point per closed H6 candle (optional)
      if(t6!=m_lastH6Fed)
      {
         m_lastH6Fed=t6;
         if(m_slowDyno!=NULL)
         {
            double slow=m_slowDyno.RainbowCenter(1);
            if(slow!=0.0) m_advH6.FeedMA(t6,slow);
         }
      }

      // if H6 history is not ready the run fails and is retried on the next call
      if(!m_advH6.RunZigZag(m_h6OlderShift,m_h6NewerShift,t6)) return;
      m_lastH6Run=t6;

      CZigZagEngine *zz=m_advH6.ZigZag();
      ZZResult best;
      if(!zz.GetResult(0,best)) return;

      string detail="H6["+IntegerToString(m_h6OlderShift)+"->"+IntegerToString(m_h6NewerShift)+"] ";
      for(int i=0;i<zz.TraderResultCount();i++)
      {
         ZZResult z;
         if(!zz.GetTraderResult(i,z)) continue;
         if(i>0) detail+=" ; ";
         detail+=z.label+": "+z.theory+" ("+z.reason+")";
      }

      if(m_slowDyno!=NULL)
      {
         detail+=" | SLOW_MA: "+ZADirText(m_advH6.MADirection());
         if(m_advH6.Contradiction()) detail+=" | CONTRADICTION";
      }
      else
         detail+=" | SLOW_MA: N/A";

      AddEvent(RC_EVENT_H6_ZIGZAG,t6,"H6_ZIGZAG",detail,0.0,best.direction);
   }

   // ------------------------------------------------------------
   // Overlap chain (unchanged)
   // ------------------------------------------------------------
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

      if( count == 1) closed_due_break = false;

      bool wasActive=(m_zoneReady && m_zoneBoxCount>=2 && !closed_due_break);
      bool nowActive=(count>=2);

      if(!wasActive && nowActive && !closed_due_break)
         AddEvent(RC_EVENT_OVERLAP_STARTED,end,"OVERLAP_STARTED",
                  "Connected box chain started",0.0,RC_UNKNOWN);

      if(!closed_due_break){
         m_zoneHigh=hi; m_zoneLow=lo; m_zoneStart=start; m_zoneEnd=end;
         m_zoneBoxCount=count; m_zoneReady=true; m_zoneExtended=false;
         return true;
      }
      else{
         m_zoneReady=false;
         m_zoneExtended=false;
         return false;
      }
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

   void CheckImportantLevelTouch(datetime candleTime)
   {
      // Do not alert while an overlap chain is active.
      if(OverlapActive())
         return;

      if(m_fractal==NULL || candleTime<=0)
         return;

      // Only inspect the newest small box.
      FlatZone box;
      if(!m_fractal.GetSmallBox(0,box))
         return;

      // Reset touch flags when SmallBox(0) changes.
      if(box.startTime!=m_levelBoxStart ||
         box.endTime!=m_levelBoxEnd)
      {
         m_levelBoxStart=box.startTime;
         m_levelBoxEnd=box.endTime;

         m_levelHighTouched=false;
         m_levelLowTouched=false;
      }

      double candleHigh=iHigh(_Symbol,PERIOD_H1,1);
      double candleLow =iLow(_Symbol,PERIOD_H1,1);

      if(candleHigh==0.0 || candleLow==0.0)
         return;

      // The candle range must contain the important level.
      bool touchedHigh=
         (!m_levelHighTouched &&
          candleLow<=box.highPrice &&
          candleHigh>=box.highPrice);

      bool touchedLow=
         (!m_levelLowTouched &&
          candleLow<=box.lowPrice &&
          candleHigh>=box.lowPrice);

      if(touchedHigh)
      {
         m_levelHighTouched=true;

         AddEvent(
            RC_EVENT_IMPORTANT_LEVEL_TOUCHED,
            candleTime,
            "IMPORTANT_LEVEL_TOUCHED",
            "HIGH",
            box.highPrice,
            RC_UP
         );
      }

      if(touchedLow)
      {
         m_levelLowTouched=true;

         AddEvent(
            RC_EVENT_IMPORTANT_LEVEL_TOUCHED,
            candleTime,
            "IMPORTANT_LEVEL_TOUCHED",
            "LOW",
            box.lowPrice,
            RC_DOWN
         );
      }
   }

public:
   CRedCarpet()
   {
      m_fractal=NULL; m_dyno=NULL; m_slowDyno=NULL;
      m_lastCandle=0; m_lastBoxStart=0; m_lastBoxEnd=0;
      m_lastH6Fed=0; m_lastH6Run=0;
      m_h6OlderShift=RC_H6_OLDER_SHIFT;
      m_h6NewerShift=RC_H6_NEWER_SHIFT;
      m_zoneReady=false; m_zoneExtended=false;
      m_zoneHigh=0; m_zoneLow=0; m_zoneStart=0; m_zoneEnd=0; m_zoneBoxCount=0;
      ArrayResize(m_events,0); ArrayResize(m_theories,0);
      ArrayResize(m_results,0); ArrayResize(m_traderResults,0);

      m_levelBoxStart=0;
      m_levelBoxEnd=0;
      m_levelHighTouched=false;
      m_levelLowTouched=false;
      closed_due_break = false;
   }

   // The advisors are configured here (not in the constructor), because
   // Set() is called at runtime from Init, when the symbol is ready.
   void Set(CFractalGeometry &fractal,CRainBowDynamics &dyno)
   {
      m_fractal=&fractal;
      m_dyno=&dyno;

      // H1: identical limits to the former built-in engine
      m_advH1.Configure(_Symbol,PERIOD_H1,
                        RC_MAX_ZIGZAG_POINTS,RC_MAX_CANDIDATES,RC_TRAILING_AFTER,0,
                        2,5);
      // H6: same engine, safety cap on evaluated paths
      m_advH6.Configure(_Symbol,PERIOD_H6,
                        RC_MAX_ZIGZAG_POINTS,RC_MAX_CANDIDATES,RC_TRAILING_AFTER,RC_H6_MAX_PATHS,
                        2,5);
   }

   // Optional: slow averages (e.g. 10x periods) used by the H6 event.
   void SetSlow(CRainBowDynamics &slowDyno)
   {
      m_slowDyno=&slowDyno;
   }

   // Optional: change the H6 window (default 53 -> 3).
   void SetH6Window(int olderShift,int newerShift)
   {
      m_h6OlderShift=olderShift;
      m_h6NewerShift=newerShift;
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
            MA_Advisor(t);      // runs even while overlap is active
            ProcessH6Candle();  // runs once per closed H6 candle, even while overlap is active

            double close=iClose(_Symbol,PERIOD_H1,1);
            if(m_zoneReady && m_zoneBoxCount>=2 && !closed_due_break && close!=0.0)
            {
               bool timeExpired=(t>m_zoneEnd);
               bool outside=(close>m_zoneHigh || close<m_zoneLow);
               if(timeExpired && outside)
               {
                  AddEvent(RC_EVENT_OVERLAP_FINISHED,t,"OVERLAP_FINISHED",
                           "Time passed chain end and close exited its price range",close,
                           close>m_zoneHigh?RC_UP:RC_DOWN);
                  m_zoneReady=false; m_zoneExtended=false;
                  closed_due_break = true;
               }
               else if(timeExpired && !outside && !m_zoneExtended)
               {
                  m_zoneExtended=true;
                  AddEvent(RC_EVENT_OVERLAP_EXTENDED,t,"OVERLAP_EXTENDED",
                           "Time passed chain end but close remains inside range",close,RC_UNKNOWN);
               }
            }
            if(newBoxArrived) ProcessNewBox(t);
            CheckImportantLevelTouch(t);
         }
      }
      else if(newBoxArrived)
      {
         ProcessNewBox(iTime(_Symbol,PERIOD_H1,1));
      }
   }

   // ---- journal ----
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

   // ---- H1 zigzag results ----
   int ZigZagResultCount() { return ArraySize(m_results); }
   bool GetZigZagResult(int index,RCZigZagResult &out)
   {
      if(index<0 || index>=ArraySize(m_results)) return false;
      CopyRCResult(m_results[index],out);
      return true;
   }

   int TraderResultCount() { return ArraySize(m_traderResults); }
   bool GetTraderResult(int index,RCZigZagResult &out)
   {
      if(index<0 || index>=ArraySize(m_traderResults)) return false;
      CopyRCResult(m_traderResults[index],out);
      return true;
   }

   // ---- H6 zigzag results (engine format) ----
   int  H6ResultCount()       { return m_advH6.ZigZag().ResultCount(); }
   bool GetH6Result(int index,ZZResult &out) { return m_advH6.ZigZag().GetResult(index,out); }
   int  H6TraderResultCount() { return m_advH6.ZigZag().TraderResultCount(); }
   bool GetH6TraderResult(int index,ZZResult &out) { return m_advH6.ZigZag().GetTraderResult(index,out); }
   int  H6Direction()         { return m_advH6.ZigZagDirection(); }
   int  SlowMADirection()     { return m_advH6.MADirection(); }

   // ---- direct access to the advisors (e.g. to register new interpretation rules) ----
   CZigZagAdvisor *H1() { return GetPointer(m_advH1); }
   CZigZagAdvisor *H6() { return GetPointer(m_advH6); }

   // ---- state (same as before) ----
   int MADirection() { return m_advH1.MADirection(); }
   int ZigZagDirection() { return m_advH1.ZigZagDirection(); }
   bool OverlapActive() { return (m_zoneReady && m_zoneBoxCount>=2 && !closed_due_break); }
   double OverlapHigh() { return m_zoneHigh; }
   double OverlapLow() { return m_zoneLow; }
   datetime OverlapStart() { return m_zoneStart; }
   datetime OverlapEnd() { return m_zoneEnd; }
};

#endif // __BOX_RED_CARPET_MQH__
