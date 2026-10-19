#ifndef __ZIGZAG_INTERPRETER_MQH__
#define __ZIGZAG_INTERPRETER_MQH__

// ------------------------------------------------------------
// Pluggable zigzag interpretation.
//
// Every interpretation rule is ONE global function with this shape:
//
//   bool MyRule(const ZZPoint &p[], const ZZInterpInfo &info, ZZVerdict &out)
//   {
//      if(<rule not applicable>) return false;   // let the next rule try
//      out.direction = +1 / -1 / 0;              // bullish / bearish / stuck
//      out.reason    = "why";
//      return true;                              // rule decided
//   }
//
// Register it once:
//   interpreter.Register("MyRule", MyRule, priority);
//
// Rules run in ascending priority; the FIRST rule returning true wins.
//
// Default priorities
//    10..40   swing rules (need two highs and two lows)
//   100..120  short-path rules (fewer than 2 highs / 2 lows)
//   500       default priority for your own rules
//   900       "mixed swing geometry" catch-all (two highs + two lows)
//   990       "short path, no direction" catch-all
// Use a priority < 10 to run before everything, or between
// the numbers above to slot a rule in exactly where you want.
// ------------------------------------------------------------

struct ZZPoint
{
   int      shift;
   datetime time;
   double   price;
   int      type;      // +1 high, -1 low, 0 fixed endpoint
   int      sources;   // bitmask ZZ_SRC_*
};

struct ZZInterpInfo
{
   int    n;                    // number of points in the path
   int    hi1, hi2;             // indices of the last two highs (older, newer); -1 if missing
   int    lo1, lo2;             // indices of the last two lows  (older, newer); -1 if missing
   bool   hasTwoHighsTwoLows;
   bool   hasHigh, hasLow;      // any swing high / low between the fixed endpoints
   double startPrice;           // first (fixed) point
   double endPrice;             // last  (fixed) point
   double point;                // symbol point size
   double levelTolerance;       // "nearly level" tolerance, in price units
};

struct ZZVerdict
{
   int    direction;   // +1 bullish, -1 bearish, 0 stuck
   string reason;
   string rule;        // filled by the interpreter: which rule decided
};

typedef bool (*ZZRuleFunc)(const ZZPoint &p[],const ZZInterpInfo &info,ZZVerdict &out);

// ============================================================
// Default rules - one function each
// ============================================================

// --- swing rules: need two highs and two lows ------------------

bool ZZRule_HigherHighsHigherLows(const ZZPoint &p[],const ZZInterpInfo &i,ZZVerdict &v)
{
   if(!i.hasTwoHighsTwoLows) return false;
   if(p[i.hi2].price>p[i.hi1].price && p[i.lo2].price>p[i.lo1].price)
   {
      v.direction=1;
      v.reason="Higher highs and higher lows";
      return true;
   }
   return false;
}

bool ZZRule_LowerHighsLowerLows(const ZZPoint &p[],const ZZInterpInfo &i,ZZVerdict &v)
{
   if(!i.hasTwoHighsTwoLows) return false;
   if(p[i.hi2].price<p[i.hi1].price && p[i.lo2].price<p[i.lo1].price)
   {
      v.direction=-1;
      v.reason="Lower highs and lower lows";
      return true;
   }
   return false;
}

bool ZZRule_LevelPeaksLowerFloors(const ZZPoint &p[],const ZZInterpInfo &i,ZZVerdict &v)
{
   if(!i.hasTwoHighsTwoLows) return false;
   if(MathAbs(p[i.hi2].price-p[i.hi1].price)<=i.levelTolerance &&
      p[i.lo2].price<p[i.lo1].price)
   {
      v.direction=-1;
      v.reason="Peaks nearly level while floors are lower";
      return true;
   }
   return false;
}

bool ZZRule_LevelFloorsHigherPeaks(const ZZPoint &p[],const ZZInterpInfo &i,ZZVerdict &v)
{
   if(!i.hasTwoHighsTwoLows) return false;
   if(MathAbs(p[i.lo2].price-p[i.lo1].price)<=i.levelTolerance &&
      p[i.hi2].price>p[i.hi1].price)
   {
      v.direction=1;
      v.reason="Floors nearly level while peaks are higher";
      return true;
   }
   return false;
}

// --- short-path rules: used when two highs + two lows do not exist ---

bool ZZRule_ShortBothSides(const ZZPoint &p[],const ZZInterpInfo &i,ZZVerdict &v)
{
   if(i.hasTwoHighsTwoLows) return false;
   if(i.hasHigh && i.hasLow)
   {
      v.direction=0;
      v.reason="Price moved both upward and downward; directional continuation is not established";
      return true;
   }
   return false;
}

bool ZZRule_ShortRise(const ZZPoint &p[],const ZZInterpInfo &i,ZZVerdict &v)
{
   if(i.hasTwoHighsTwoLows) return false;
   if(i.endPrice>i.startPrice && !i.hasLow)
   {
      v.direction=1;
      v.reason=(i.hasHigh ? "Price reached a higher level and remains above its starting price"
                          : "Price endpoint is above its starting price");
      return true;
   }
   return false;
}

bool ZZRule_ShortFall(const ZZPoint &p[],const ZZInterpInfo &i,ZZVerdict &v)
{
   if(i.hasTwoHighsTwoLows) return false;
   if(i.endPrice<i.startPrice && !i.hasHigh)
   {
      v.direction=-1;
      v.reason=(i.hasLow ? "Price reached a lower level and remains below its starting price"
                         : "Price endpoint is below its starting price");
      return true;
   }
   return false;
}

// --- catch-alls ---------------------------------------------------

bool ZZRule_MixedSwings(const ZZPoint &p[],const ZZInterpInfo &i,ZZVerdict &v)
{
   if(!i.hasTwoHighsTwoLows) return false;
   v.direction=0;
   v.reason="Mixed swing geometry; no dominant direction";
   return true;
}

bool ZZRule_ShortFlat(const ZZPoint &p[],const ZZInterpInfo &i,ZZVerdict &v)
{
   if(i.hasTwoHighsTwoLows) return false;
   v.direction=0;
   v.reason="Price returned to its starting level or the movement does not establish a dominant direction";
   return true;
}

// ============================================================
// Rule registry / interpreter
// ============================================================
struct ZZRuleEntry
{
   string     name;
   int        priority;
   bool       enabled;
   ZZRuleFunc fn;
};

class CZZInterpreter
{
private:
   ZZRuleEntry m_rules[];
   double      m_levelTolPoints;   // "nearly level" tolerance in points

   int Find(const string name)
   {
      for(int i=0;i<ArraySize(m_rules);i++)
         if(m_rules[i].name==name) return i;
      return -1;
   }

   // stable insertion sort by priority (equal priority keeps registration order)
   void SortByPriority()
   {
      int n=ArraySize(m_rules);
      for(int a=1;a<n;a++)
      {
         ZZRuleEntry key=m_rules[a];
         int b=a-1;
         while(b>=0 && m_rules[b].priority>key.priority)
         {
            m_rules[b+1]=m_rules[b];
            b--;
         }
         m_rules[b+1]=key;
      }
   }

public:
   CZZInterpreter()
   {
      m_levelTolPoints=2.0;
      ArrayResize(m_rules,0);
      RegisterDefaults();
   }

   void RegisterDefaults()
   {
      Register("HigherHighsHigherLows", ZZRule_HigherHighsHigherLows,  10);
      Register("LowerHighsLowerLows",   ZZRule_LowerHighsLowerLows,    20);
      Register("LevelPeaksLowerFloors", ZZRule_LevelPeaksLowerFloors,  30);
      Register("LevelFloorsHigherPeaks",ZZRule_LevelFloorsHigherPeaks, 40);
      Register("ShortBothSides",        ZZRule_ShortBothSides,        100);
      Register("ShortRise",             ZZRule_ShortRise,             110);
      Register("ShortFall",             ZZRule_ShortFall,             120);
      Register("MixedSwings",           ZZRule_MixedSwings,           900);
      Register("ShortFlat",             ZZRule_ShortFlat,             990);
   }

   // Add (or replace, if the name already exists) a rule.
   bool Register(const string name,ZZRuleFunc fn,const int priority=500)
   {
      int idx=Find(name);
      if(idx<0)
      {
         idx=ArraySize(m_rules);
         if(ArrayResize(m_rules,idx+1)!=idx+1) return false;
      }
      m_rules[idx].name=name;
      m_rules[idx].priority=priority;
      m_rules[idx].enabled=true;
      m_rules[idx].fn=fn;
      SortByPriority();
      return true;
   }

   bool SetEnabled(const string name,const bool enabled)
   {
      int idx=Find(name);
      if(idx<0) return false;
      m_rules[idx].enabled=enabled;
      return true;
   }

   bool Remove(const string name)
   {
      int idx=Find(name);
      if(idx<0) return false;
      int n=ArraySize(m_rules);
      for(int i=idx;i<n-1;i++) m_rules[i]=m_rules[i+1];
      ArrayResize(m_rules,n-1);
      return true;
   }

   void ClearAll() { ArrayResize(m_rules,0); }

   int    RuleCount()               { return ArraySize(m_rules); }
   string RuleName(const int i)     { return (i>=0 && i<ArraySize(m_rules)) ? m_rules[i].name : ""; }
   int    RulePriority(const int i) { return (i>=0 && i<ArraySize(m_rules)) ? m_rules[i].priority : 0; }
   bool   RuleEnabled(const int i)  { return (i>=0 && i<ArraySize(m_rules)) ? m_rules[i].enabled : false; }

   void SetLevelTolerancePoints(const double pts) { m_levelTolPoints=MathMax(0.0,pts); }

   // Derive the facts every rule can use.
   void BuildInfo(const ZZPoint &p[],const double point,ZZInterpInfo &info)
   {
      int n=ArraySize(p);
      info.n=n;
      info.hi1=-1; info.hi2=-1; info.lo1=-1; info.lo2=-1;
      info.hasHigh=false; info.hasLow=false;
      info.startPrice=(n>0 ? p[0].price   : 0.0);
      info.endPrice  =(n>0 ? p[n-1].price : 0.0);
      info.point=point;
      info.levelTolerance=m_levelTolPoints*point;

      for(int i=1;i<n-1;i++)
      {
         if(p[i].type>0) { info.hi1=info.hi2; info.hi2=i; info.hasHigh=true; }
         if(p[i].type<0) { info.lo1=info.lo2; info.lo2=i; info.hasLow=true; }
      }
      info.hasTwoHighsTwoLows=(info.hi1>=0 && info.hi2>=0 && info.lo1>=0 && info.lo2>=0);
   }

   // Run the rules in priority order; first match wins.
   bool Evaluate(const ZZPoint &p[],const ZZInterpInfo &info,ZZVerdict &out)
   {
      out.direction=0;
      out.reason="No interpretation rule matched";
      out.rule="";

      if(info.n<2)
      {
         out.reason="No measurable price movement";
         out.rule="builtin";
         return true;
      }

      for(int i=0;i<ArraySize(m_rules);i++)
      {
         if(!m_rules[i].enabled) continue;
         ZZVerdict v;
         v.direction=0; v.reason=""; v.rule="";
         if(m_rules[i].fn(p,info,v))
         {
            out=v;
            out.rule=m_rules[i].name;
            return true;
         }
      }
      return false;
   }
};

#endif // __ZIGZAG_INTERPRETER_MQH__
