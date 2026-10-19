#ifndef __ZIGZAG_ADVISOR_MQH__
#define __ZIGZAG_ADVISOR_MQH__

#include "ZigZagEngine.mqh"
#include "MABifurcation.mqh"

// ------------------------------------------------------------
// CZigZagAdvisor
//   - zigzag engine        (window is given by the caller)
//   - pluggable rules      (Interpreter().Register(...))
//   - MA bifurcation       (price is given by the caller via FeedMA)
// It keeps an event journal and flags a contradiction when the
// zigzag theory and the MA bifurcation disagree.
// Display / analysis only: it never trades.
// ------------------------------------------------------------

enum ZA_EVENT_TYPE
{
   ZA_EVENT_NONE = 0,
   ZA_EVENT_ZIGZAG_THEORY,
   ZA_EVENT_MA_REVERSAL,
   ZA_EVENT_CONTRADICTION
};

struct ZAEvent
{
   ZA_EVENT_TYPE type;
   datetime      time;
   string        name;
   string        detail;
   int           direction;
};

string ZADirText(const int d)
{
   if(d>0) return "UP";
   if(d<0) return "DOWN";
   return "UNKNOWN";
}

class CZigZagAdvisor
{
private:
   CZigZagEngine  m_zz;
   CMABifurcation m_ma;

   ZAEvent m_events[];
   int     m_maxEvents;
   int     m_zigDirection;     // last non-zero zigzag direction
   bool    m_contradiction;    // zigzag vs MA disagree (as of the last zigzag run)

   void AddEvent(ZA_EVENT_TYPE type,datetime when,string name,string detail,int direction)
   {
      int n=ArraySize(m_events);
      int idx;
      if(n>=m_maxEvents && n>0)
      {
         for(int i=0;i<n-1;i++) m_events[i]=m_events[i+1];   // drop the oldest
         idx=n-1;
      }
      else
      {
         if(ArrayResize(m_events,n+1)!=n+1) return;
         idx=n;
      }
      m_events[idx].type=type;
      m_events[idx].time=when;
      m_events[idx].name=name;
      m_events[idx].detail=detail;
      m_events[idx].direction=direction;
   }

   void AfterZigZagRun(datetime when)
   {
      ZZResult best;
      if(!m_zz.GetResult(0,best)) return;

      AddEvent(ZA_EVENT_ZIGZAG_THEORY,when,"ZIGZAG_"+best.label,
               best.theory+" | "+best.reason+" ["+best.rule+"]",best.direction);

      // The flag is recomputed on every run: a STUCK zigzag has no opinion,
      // so it cannot contradict the MA (the old flag used to stay stale).
      int ma=m_ma.LastKnownDirection();
      m_contradiction=(best.direction!=0 && ma!=0 && ma!=best.direction);
      if(best.direction!=0)
      {
         if(m_contradiction)
            AddEvent(ZA_EVENT_CONTRADICTION,when,"THEORY_CONTRADICTION",
                     "Zigzag "+ZADirText(best.direction)+" vs MA "+ZADirText(ma),best.direction);
         m_zigDirection=best.direction;
      }
   }

public:
   CZigZagAdvisor()
   {
      m_maxEvents=1000;
      m_zigDirection=0;
      m_contradiction=false;
      ArrayResize(m_events,0);
   }

   void Configure(string symbol,ENUM_TIMEFRAMES tf,
                  int maxPoints=4,int maxCandidates=80,int trailingAfter=3,long maxPaths=0,
                  int minWaiting=2,int maxWaiting=5)
   {
      m_zz.Configure(symbol,tf,maxPoints,maxCandidates,trailingAfter,maxPaths);
      m_ma.Configure(minWaiting,maxWaiting);
   }

   // Access to the parts
   CZigZagEngine  *ZigZag()      { return GetPointer(m_zz); }
   CZZInterpreter *Interpreter() { return m_zz.Interpreter(); }
   CMABifurcation *MA()          { return GetPointer(m_ma); }

   // ---- MA side: feed one point per bar; returns MA direction ----
   int FeedMA(datetime when,double price)
   {
      int dir=m_ma.AddPoint(price);
      if(m_ma.JustReversed())
         AddEvent(ZA_EVENT_MA_REVERSAL,when,"AVERAGE_REVERSAL","Bifurcation direction changed",dir);
      return dir;
   }

   // ---- Zigzag side: window supplied by the caller ----
   bool RunZigZag(int olderShift,int newerShift,datetime when)
   {
      if(!m_zz.RunByShift(olderShift,newerShift)) return false;
      AfterZigZagRun(when);
      return true;
   }

   bool RunZigZagByTime(datetime olderTime,datetime newerTime,datetime when)
   {
      if(!m_zz.RunByTime(olderTime,newerTime)) return false;
      AfterZigZagRun(when);
      return true;
   }

   // ---- Combined view ----
   int  MADirection()      { return m_ma.LastKnownDirection(); }
   int  ZigZagDirection()  { return m_zigDirection; }
   bool Contradiction()    { return m_contradiction; }
   // +1 / -1 only when both agree, otherwise 0
   int  CombinedDirection()
   {
      int ma=m_ma.LastKnownDirection();
      if(ma!=0 && ma==m_zigDirection) return ma;
      return 0;
   }

   // ---- Journal ----
   int  EventCount() { return ArraySize(m_events); }
   bool GetEvent(int index,ZAEvent &out)
   {
      if(index<0 || index>=ArraySize(m_events)) return false;
      out=m_events[index];
      return true;
   }
   void ClearEvents() { ArrayResize(m_events,0); }
};

#endif // __ZIGZAG_ADVISOR_MQH__
