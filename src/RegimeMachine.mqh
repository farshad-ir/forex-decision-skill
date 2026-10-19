#ifndef __REGIME_MACHINE_MQH__
#define __REGIME_MACHINE_MQH__

// ------------------------------------------------------------
// CRegimeMachine  (with notebook)
//
// Regime (BUY / SELL) of the slow-average CENTER, with a pip threshold:
//  - A regime changes only when the center has moved AGAINST it by at
//    least `threshold` pips, measured from the regime's best extreme
//    (BUY: highest center, SELL: lowest center).
//  - A shorter counter-move is not a change. While the bifurcation
//    direction is against the regime we are "under pressure" (WARNING);
//    if it returns before the threshold: false alarm (RECOVERED).
//
// NOTEBOOK (learns from its own history):
//  1) Counter-move notes: every counter-move whose peak reached
//     `notePips` (default 60) is written down, with how it ended
//     (regime resumed / regime flipped). A live counter-move that crosses
//     `notePips` raises a WATCH alert with the historical flip risk.
//  2) Call notes: when a regime ends, the machine writes how far it
//     really ran after it was declared (follow-through), how far it ran
//     from its true origin (what an early entry would have made) and its
//     largest pullback. Calls with a follow-through below `weakCallPips`
//     are flagged WEAK. The history of calls is quoted on every new
//     regime declaration.
//
// Points are queued by Feed() and consumed by Process(), so the caller
// decides the cadence (every H6 candle, or every 3rd = 18 hours).
// ------------------------------------------------------------

enum REGIME_STATE
{
   REGIME_SELL    = -1,
   REGIME_UNKNOWN =  0,
   REGIME_BUY     =  1
};

enum REGIME_EVENT_TYPE
{
   REGIME_EVT_NONE = 0,
   REGIME_EVT_ESTABLISHED,   // first regime confirmed (from UNKNOWN)
   REGIME_EVT_WARNING,       // direction turned against the regime, below threshold
   REGIME_EVT_RECOVERED,     // false alarm: direction came back, regime unchanged
   REGIME_EVT_CHANGED,       // counter-move reached the threshold: regime flipped
   REGIME_EVT_WATCH,         // live counter-move reached the notable level (e.g. 60 pips)
   REGIME_EVT_NOTE           // something was written in the notebook
};

struct RegimeEvent
{
   REGIME_EVENT_TYPE type;
   datetime          time;
   int               fromState;
   int               toState;
   double            center;
   double            adversePips;   // adverse move (WARNING/CHANGED/WATCH) or peak (RECOVERED/NOTE)
   string            text;
};

struct RegimePoint
{
   datetime time;
   double   center;
   int      dir;      // bifurcation direction: +1 up, -1 down, 0 unknown
};

// A counter-move against the regime that was big enough to be noted.
struct RegimePullbackNote
{
   int      regime;      // regime at the time (+1 BUY / -1 SELL)
   datetime start;       // where the counter-move began (regime's extreme)
   datetime peakTime;    // when the counter-move peaked
   datetime end;         // when the episode closed
   double   peakPips;    // best a counter-trader could have made
   int      points;      // evaluated points inside the episode
   int      outcome;     // +1 regime resumed, -1 regime flipped
};

// How a declared regime really performed.
struct RegimeCallNote
{
   int      regime;
   datetime declared;
   datetime ended;
   double   declCenter;      // center when the regime was declared
   double   originCenter;    // center where the leg really began
   double   bestCenter;      // best center reached inside the regime
   double   followPips;      // declaration -> best  (what entering on the call made at best)
   double   legPips;         // origin -> best       (what entering at the very start made)
   double   maxPullbackPips; // largest counter-move inside the regime
   int      points;
   bool     weak;
};

class CRegimeMachine
{
private:
   double m_pip;
   double m_threshold;        // price units
   double m_thresholdPips;
   double m_notePips;         // counter-moves from this size are noted
   double m_weakCallPips;     // follow-through below this = weak call

   // regime state
   int      m_state;
   double   m_ext;
   datetime m_extTime;
   bool     m_pressure;
   double   m_maxAdverse;

   // current regime leg (for the call note)
   double   m_origin;
   datetime m_declTime;
   double   m_declCenter;
   int      m_regimePoints;
   double   m_regimeMaxPullback;   // price units

   // open counter-move episode
   bool     m_epOpen;
   datetime m_epStart;
   datetime m_epPeakTime;
   double   m_epPeak;              // price units
   int      m_epPoints;
   bool     m_epWatched;

   // before the first regime is known
   bool     m_init;
   double   m_lo,m_hi;
   datetime m_loTime,m_hiTime;

   RegimePoint        m_pending[];
   RegimeEvent        m_events[];
   RegimePullbackNote m_pull[];
   RegimeCallNote     m_calls[];
   int                m_maxNotes;

   string   m_file;
   bool     m_fileCommon;

   string Name(const int s) { return s>0?"BUY":(s<0?"SELL":"UNKNOWN"); }
   string Pips(const double priceDiff) { return DoubleToString(priceDiff/m_pip,1); }
   string P1(const double pips) { return DoubleToString(pips,1); }

   void Emit(REGIME_EVENT_TYPE type,datetime when,int from,int to,double center,double adverse,string text)
   {
      int n=ArraySize(m_events);
      if(ArrayResize(m_events,n+1)!=n+1) return;
      m_events[n].type=type;
      m_events[n].time=when;
      m_events[n].fromState=from;
      m_events[n].toState=to;
      m_events[n].center=center;
      m_events[n].adversePips=adverse/m_pip;
      m_events[n].text=text;
   }

   // ------------------------------------------------------------
   // statistics from the notebook
   // ------------------------------------------------------------
   double Median(double &a[])
   {
      int n=ArraySize(a);
      if(n==0) return 0.0;
      ArraySort(a);
      if(n%2==1) return a[n/2];
      return (a[n/2-1]+a[n/2])/2.0;
   }

   string OddsText()
   {
      int n=0,f=0;
      for(int i=0;i<ArraySize(m_pull);i++)
      {
         if(m_pull[i].peakPips<m_notePips) continue;
         n++;
         if(m_pull[i].outcome<0) f++;
      }
      if(n<3) return "History: not enough samples ("+IntegerToString(n)+" similar counter-moves)";
      double pr=(f+1.0)/(n+2.0);
      string risk=(pr>=0.6?"HIGH":(pr>=0.3?"MEDIUM":"LOW"));
      return "History: "+IntegerToString(n)+" similar counter-moves, "+IntegerToString(f)+
             " flipped the regime, "+IntegerToString(n-f)+" resumed -> flip risk "+risk+
             " ("+DoubleToString(pr*100.0,0)+"%)";
   }

   string CallsText()
   {
      int n=ArraySize(m_calls);
      if(n<3) return "Calls history: not enough samples ("+IntegerToString(n)+")";
      int weak=0;
      double fol[],lag[];
      ArrayResize(fol,n); ArrayResize(lag,n);
      for(int i=0;i<n;i++)
      {
         if(m_calls[i].weak) weak++;
         fol[i]=m_calls[i].followPips;
         lag[i]=m_calls[i].legPips-m_calls[i].followPips;
      }
      double mf=Median(fol);
      double ml=Median(lag);
      return "Calls history: "+IntegerToString(n)+" calls, "+IntegerToString(weak)+" weak (< "+
             DoubleToString(m_weakCallPips,0)+" pips), median follow-through "+P1(mf)+
             " pips, median missed before confirmation "+P1(ml)+" pips";
   }

   // ------------------------------------------------------------
   // notebook file (optional)
   // ------------------------------------------------------------
   void AppendRow(const string k,const string f0,const string f1,const string f2,const string f3,
                  const string f4,const string f5,const string f6,const string f7,const string f8,const string f9)
   {
      if(m_file=="") return;
      int flags=FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI;
      if(m_fileCommon) flags|=FILE_COMMON;
      int h=FileOpen(m_file,flags,';');
      if(h==INVALID_HANDLE) return;
      FileSeek(h,0,SEEK_END);
      FileWrite(h,k,f0,f1,f2,f3,f4,f5,f6,f7,f8,f9);
      FileClose(h);
   }

   void StorePull(RegimePullbackNote &n)
   {
      int c=ArraySize(m_pull);
      if(c>=m_maxNotes)
      {
         for(int i=0;i<c-1;i++) m_pull[i]=m_pull[i+1];
         m_pull[c-1]=n;
      }
      else
      {
         if(ArrayResize(m_pull,c+1)!=c+1) return;
         m_pull[c]=n;
      }
   }

   void StoreCall(RegimeCallNote &n)
   {
      int c=ArraySize(m_calls);
      if(c>=m_maxNotes)
      {
         for(int i=0;i<c-1;i++) m_calls[i]=m_calls[i+1];
         m_calls[c-1]=n;
      }
      else
      {
         if(ArrayResize(m_calls,c+1)!=c+1) return;
         m_calls[c]=n;
      }
   }

   // ------------------------------------------------------------
   // writing the notebook
   // ------------------------------------------------------------
   void AddPullbackNote(const int regime,datetime start,datetime peakTime,datetime end,
                        const double peakPrice,const int points,const int outcome)
   {
      RegimePullbackNote n;
      n.regime=regime; n.start=start; n.peakTime=peakTime; n.end=end;
      n.peakPips=peakPrice/m_pip; n.points=points; n.outcome=outcome;
      StorePull(n);

      AppendRow("P",IntegerToString(regime),IntegerToString((long)start),IntegerToString((long)peakTime),
                IntegerToString((long)end),DoubleToString(n.peakPips,2),IntegerToString(points),
                IntegerToString(outcome),"0","0","0");

      string how=(outcome>0 ? "regime resumed" : "regime FLIPPED");
      string extra=(n.peakPips>=m_thresholdPips
                    ? " (a counter-trader entering at its start would have made up to "+P1(n.peakPips)+" pips)"
                    : " (a counter-trader could have made up to "+P1(n.peakPips)+" pips)");
      Emit(REGIME_EVT_NOTE,end,regime,regime,0.0,peakPrice,
           "Noted: counter-move against "+Name(regime)+" peaked at "+P1(n.peakPips)+" pips over "+
           IntegerToString(points)+" points; "+how+extra);
   }

   void AddCallNote(const int regime,datetime endTime,const double bestCenter)
   {
      RegimeCallNote n;
      n.regime=regime; n.declared=m_declTime; n.ended=endTime;
      n.declCenter=m_declCenter; n.originCenter=m_origin; n.bestCenter=bestCenter;
      double follow=(regime>0 ? bestCenter-m_declCenter : m_declCenter-bestCenter)/m_pip;
      if(follow<0.0) follow=0.0;
      double leg=(regime>0 ? bestCenter-m_origin : m_origin-bestCenter)/m_pip;
      if(leg<0.0) leg=0.0;
      n.followPips=follow; n.legPips=leg;
      n.maxPullbackPips=m_regimeMaxPullback/m_pip;
      n.points=m_regimePoints;
      n.weak=(follow<m_weakCallPips);
      StoreCall(n);

      AppendRow("C",IntegerToString(regime),IntegerToString((long)n.declared),IntegerToString((long)endTime),
                DoubleToString(n.declCenter,6),DoubleToString(n.originCenter,6),DoubleToString(n.bestCenter,6),
                DoubleToString(follow,2),DoubleToString(leg,2),DoubleToString(n.maxPullbackPips,2),
                IntegerToString(n.points));

      string verdict=(n.weak ? " -> WEAK CALL" : "");
      Emit(REGIME_EVT_NOTE,endTime,regime,regime,bestCenter,0.0,
           "Noted: "+Name(regime)+" call ran "+P1(follow)+" pips after it was declared ("+P1(leg)+
           " pips from its origin, "+P1(leg-follow)+" missed before confirmation), largest pullback "+
           P1(n.maxPullbackPips)+" pips over "+IntegerToString(n.points)+" points"+verdict);
   }

   // a new regime leg starts
   void BeginRegime(const int s,const double c,const double origin,datetime t)
   {
      m_state=s; m_ext=c; m_extTime=t;
      m_origin=origin; m_declTime=t; m_declCenter=c;
      m_regimePoints=0; m_regimeMaxPullback=0.0;
      m_pressure=false; m_maxAdverse=0.0;
      m_epOpen=false; m_epPeak=0.0; m_epPoints=0; m_epWatched=false;
   }

   void Step(const RegimePoint &p)
   {
      double c=p.center;

      // ---- no regime yet: wait for the first move of `threshold` ----
      if(m_state==0)
      {
         if(!m_init)
         {
            m_init=true;
            m_lo=c; m_hi=c; m_loTime=p.time; m_hiTime=p.time;
            return;
         }
         if(c<m_lo) { m_lo=c; m_loTime=p.time; }
         if(c>m_hi) { m_hi=c; m_hiTime=p.time; }

         bool up=(c-m_lo>=m_threshold);
         bool dn=(m_hi-c>=m_threshold);
         if(up && dn)
         {
            if(m_loTime>m_hiTime) dn=false;   // the latest leg decides
            else up=false;
         }
         if(up)
         {
            BeginRegime(1,c,m_lo,p.time);
            Emit(REGIME_EVT_ESTABLISHED,p.time,0,1,c,0.0,
                 "Regime established: BUY (center rose "+Pips(c-m_lo)+" pips from its low). "+CallsText());
         }
         else if(dn)
         {
            BeginRegime(-1,c,m_hi,p.time);
            Emit(REGIME_EVT_ESTABLISHED,p.time,0,-1,c,0.0,
                 "Regime established: SELL (center fell "+Pips(m_hi-c)+" pips from its high). "+CallsText());
         }
         return;
      }

      // ---- regime known ----
      int s=m_state;
      m_regimePoints++;

      if(s>0 && c>m_ext) { m_ext=c; m_extTime=p.time; }   // best extreme in the regime direction
      if(s<0 && c<m_ext) { m_ext=c; m_extTime=p.time; }

      double adverse=(s>0 ? m_ext-c : c-m_ext);   // always >= 0

      // ---- counter-move episode tracking ----
      if(adverse>0.0)
      {
         if(!m_epOpen)
         {
            m_epOpen=true;
            m_epStart=m_extTime;
            m_epPeak=adverse;
            m_epPeakTime=p.time;
            m_epPoints=1;
            m_epWatched=false;
         }
         else
         {
            m_epPoints++;
            if(adverse>m_epPeak) { m_epPeak=adverse; m_epPeakTime=p.time; }
         }
         if(adverse>m_regimeMaxPullback) m_regimeMaxPullback=adverse;
      }

      // ---- the counter-move reached the threshold: regime flips ----
      if(adverse>=m_threshold)
      {
         double oldExt=m_ext;
         Emit(REGIME_EVT_CHANGED,p.time,s,-s,c,adverse,
              "Regime changed: "+Name(s)+" -> "+Name(-s)+" (center moved "+Pips(adverse)+
              " pips against it, threshold "+DoubleToString(m_thresholdPips,1)+"). "+CallsText());

         if(m_epOpen)
            AddPullbackNote(s,m_epStart,m_epPeakTime,p.time,m_epPeak,m_epPoints,-1);
         AddCallNote(s,p.time,oldExt);

         BeginRegime(-s,c,oldExt,p.time);
         return;
      }

      bool adverseDir=(p.dir==-s);

      // ---- live counter-move became notable: WATCH with the odds from the notebook ----
      if(m_epOpen && !m_epWatched && m_epPeak>=m_notePips*m_pip)
      {
         m_epWatched=true;
         Emit(REGIME_EVT_WATCH,p.time,s,s,c,m_epPeak,
              "Counter-move against "+Name(s)+" reached "+Pips(m_epPeak)+" pips (notable level "+
              DoubleToString(m_notePips,0)+"). "+OddsText());
      }

      // ---- pressure / false alarm (bifurcation direction) ----
      if(!m_pressure)
      {
         if(adverse>0.0 && adverseDir)
         {
            m_pressure=true;
            m_maxAdverse=adverse;
            Emit(REGIME_EVT_WARNING,p.time,s,s,c,adverse,
                 Name(s)+" regime under pressure: center direction turned "+Name(-s)+
                 ", adverse move "+Pips(adverse)+" pips (threshold "+DoubleToString(m_thresholdPips,1)+")");
         }
      }
      else
      {
         if(adverse>m_maxAdverse) m_maxAdverse=adverse;
         if(p.dir==s || adverse==0.0)
         {
            Emit(REGIME_EVT_RECOVERED,p.time,s,s,c,m_maxAdverse,
                 "False alarm: center direction returned to "+Name(s)+", adverse peak "+Pips(m_maxAdverse)+
                 " pips < "+DoubleToString(m_thresholdPips,1)+"; regime stays "+Name(s));
            m_pressure=false;
            m_maxAdverse=0.0;
         }
      }

      // ---- the regime made a new extreme: the counter-move episode is over ----
      if(adverse==0.0 && m_epOpen)
      {
         if(m_epPeak>=m_notePips*m_pip)
            AddPullbackNote(s,m_epStart,m_epPeakTime,p.time,m_epPeak,m_epPoints,1);
         m_epOpen=false;
         m_epPeak=0.0;
         m_epPoints=0;
         m_epWatched=false;
      }
   }

public:
   CRegimeMachine()
   {
      m_pip=0.0001;
      m_thresholdPips=100.0;
      m_threshold=m_thresholdPips*m_pip;
      m_notePips=60.0;
      m_weakCallPips=30.0;
      m_maxNotes=2000;
      m_file="";
      m_fileCommon=false;
      Reset();
   }

   // thresholdPips: 100 pips = 1000 points on a 5-digit symbol
   void Configure(const string symbol,const double thresholdPips=100.0)
   {
      int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      if(point<=0.0) point=0.00001;
      m_pip=((digits==3 || digits==5) ? point*10.0 : point);
      m_thresholdPips=thresholdPips;
      m_threshold=thresholdPips*m_pip;
   }

   // notePips: counter-moves from this size are written down (and raise WATCH)
   // weakCallPips: a regime that ran less than this after its declaration is a weak call
   void ConfigureNotebook(const double notePips=60.0,const double weakCallPips=30.0)
   {
      m_notePips=MathMax(1.0,notePips);
      m_weakCallPips=MathMax(0.0,weakCallPips);
   }

   // Optional persistence (CSV in MQL5/Files). Existing rows are loaded.
   // Leave it empty (default) to keep the notebook in memory only.
   void SetNotebookFile(const string fileName,const bool common=false,const bool load=true)
   {
      m_file=fileName;
      m_fileCommon=common;
      if(load) LoadNotebook();
   }

   bool LoadNotebook()
   {
      if(m_file=="") return false;
      int flags=FILE_READ|FILE_CSV|FILE_ANSI;
      if(m_fileCommon) flags|=FILE_COMMON;
      int h=FileOpen(m_file,flags,';');
      if(h==INVALID_HANDLE) return false;

      ArrayResize(m_pull,0);
      ArrayResize(m_calls,0);

      while(!FileIsEnding(h))
      {
         string k=FileReadString(h);
         if(k!="P" && k!="C")
         {
            while(!FileIsLineEnding(h) && !FileIsEnding(h)) FileReadString(h);
            continue;
         }
         string f[10];
         for(int i=0;i<10;i++) f[i]=FileReadString(h);

         if(k=="P")
         {
            RegimePullbackNote n;
            n.regime=(int)StringToInteger(f[0]);
            n.start=(datetime)StringToInteger(f[1]);
            n.peakTime=(datetime)StringToInteger(f[2]);
            n.end=(datetime)StringToInteger(f[3]);
            n.peakPips=StringToDouble(f[4]);
            n.points=(int)StringToInteger(f[5]);
            n.outcome=(int)StringToInteger(f[6]);
            StorePull(n);
         }
         else
         {
            RegimeCallNote n;
            n.regime=(int)StringToInteger(f[0]);
            n.declared=(datetime)StringToInteger(f[1]);
            n.ended=(datetime)StringToInteger(f[2]);
            n.declCenter=StringToDouble(f[3]);
            n.originCenter=StringToDouble(f[4]);
            n.bestCenter=StringToDouble(f[5]);
            n.followPips=StringToDouble(f[6]);
            n.legPips=StringToDouble(f[7]);
            n.maxPullbackPips=StringToDouble(f[8]);
            n.points=(int)StringToInteger(f[9]);
            n.weak=(n.followPips<m_weakCallPips);
            StoreCall(n);
         }
      }
      FileClose(h);
      return true;
   }

   // Clears the regime state and the queues. The notebook is kept.
   void Reset()
   {
      m_state=0; m_ext=0.0; m_extTime=0;
      m_pressure=false; m_maxAdverse=0.0;
      m_origin=0.0; m_declTime=0; m_declCenter=0.0;
      m_regimePoints=0; m_regimeMaxPullback=0.0;
      m_epOpen=false; m_epStart=0; m_epPeakTime=0; m_epPeak=0.0; m_epPoints=0; m_epWatched=false;
      m_init=false; m_lo=0.0; m_hi=0.0; m_loTime=0; m_hiTime=0;
      ArrayResize(m_pending,0);
      ArrayResize(m_events,0);
   }

   // Queue one point (e.g. one closed H6 candle).
   void Feed(const datetime when,const double center,const int dir)
   {
      int n=ArraySize(m_pending);
      if(ArrayResize(m_pending,n+1)!=n+1) return;
      m_pending[n].time=when;
      m_pending[n].center=center;
      m_pending[n].dir=dir;
   }

   // Consume the queued points, oldest first.
   void Process()
   {
      for(int i=0;i<ArraySize(m_pending);i++) Step(m_pending[i]);
      ArrayResize(m_pending,0);
   }

   // Oldest unread event (removed from the queue).
   bool PopEvent(RegimeEvent &out)
   {
      int n=ArraySize(m_events);
      if(n<=0) return false;
      out=m_events[0];
      for(int i=0;i<n-1;i++) m_events[i]=m_events[i+1];
      ArrayResize(m_events,n-1);
      return true;
   }

   // ---- state ----
   int    State()          { return m_state; }
   bool   UnderPressure()  { return m_pressure; }
   int    PendingCount()   { return ArraySize(m_pending); }
   double ThresholdPips()  { return m_thresholdPips; }
   double Extreme()        { return m_ext; }
   string StateText()
   {
      string t=Name(m_state);
      if(m_pressure) t+="(UNDER_PRESSURE)";
      return t;
   }

   // ---- notebook ----
   int  PullbackNoteCount() { return ArraySize(m_pull); }
   bool GetPullbackNote(const int i,RegimePullbackNote &out)
   {
      if(i<0 || i>=ArraySize(m_pull)) return false;
      out=m_pull[i];
      return true;
   }
   int  CallNoteCount() { return ArraySize(m_calls); }
   bool GetCallNote(const int i,RegimeCallNote &out)
   {
      if(i<0 || i>=ArraySize(m_calls)) return false;
      out=m_calls[i];
      return true;
   }
   string NotebookSummary()
   {
      return "Notebook: "+IntegerToString(ArraySize(m_pull))+" counter-moves, "+
             IntegerToString(ArraySize(m_calls))+" calls. "+OddsText()+". "+CallsText();
   }
};

#endif // __REGIME_MACHINE_MQH__
