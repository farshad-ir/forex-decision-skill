#ifndef __H6_PRICE_LEVEL_BOOK_MQH__
#define __H6_PRICE_LEVEL_BOOK_MQH__

//==============================================================
// H6 Price Level Book
// Observation only: no trading and no stop-loss decisions.
//==============================================================

enum ENUM_H6_BOOK_PHASE
{
   H6_BOOK_BEARISH   = -1,
   H6_BOOK_ROTATION  =  0,
   H6_BOOK_BULLISH   =  1
};

enum ENUM_H6_LEVEL_KIND
{
   H6_LEVEL_FLOOR   = -1,
   H6_LEVEL_CEILING =  1
};

enum ENUM_H6_LEVEL_ROLE
{
   H6_ROLE_NONE     = -1,
   H6_ROLE_PREVIOUS =  0,
   H6_ROLE_ROTATION =  1,
   H6_ROLE_CURRENT  =  2
};

struct SH6PriceLevel
{
   int                  id;
   ENUM_H6_LEVEL_KIND   kind;
   ENUM_H6_LEVEL_ROLE   role;

   int                  phase;
   double               price;
   datetime             formedTime;

   int                  independentTests;
   int                  holds;
   int                  breaks;

   bool                 broken;
   bool                 touching;
   bool                 breakCounted;

   datetime             lastTestTime;
};

class CH6PriceLevelBook
{
private:
   SH6PriceLevel      m_levels[];
   int                m_nextId;
   int                m_currentPhase;
   bool               m_phaseInitialized;
   datetime           m_lastBarTime;

   string             m_symbol;
   ENUM_TIMEFRAMES    m_timeframe;

   // Preliminary detection tolerance: 20 symbol points.
   // This is a level-matching tolerance, not a trading rule.
   int                m_tolerancePoints;

   double Tolerance()
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return point * m_tolerancePoints;
   }

   bool IsDirectional(const int phase)
   {
      return (phase == H6_BOOK_BULLISH ||
              phase == H6_BOOK_BEARISH);
   }

   void ApplyPhaseTransition(const int newPhase)
   {
      if(!m_phaseInitialized)
      {
         m_currentPhase = newPhase;
         m_phaseInitialized = true;

         Print("H6 BOOK | Initial phase = ", newPhase);
         return;
      }

      if(newPhase == m_currentPhase)
         return;

      int oldPhase = m_currentPhase;

      // Directional phase -> rotation:
      // preserve the completed directional phase as previous.
      if(newPhase == H6_BOOK_ROTATION)
      {
         for(int i = 0; i < ArraySize(m_levels); i++)
         {
            if(m_levels[i].role == H6_ROLE_PREVIOUS)
               m_levels[i].role = H6_ROLE_NONE;

            else if(m_levels[i].role == H6_ROLE_CURRENT)
               m_levels[i].role = H6_ROLE_PREVIOUS;

            else if(m_levels[i].role == H6_ROLE_ROTATION)
               m_levels[i].role = H6_ROLE_NONE;
         }
      }
      // Rotation -> directional phase:
      // keep previous directional levels and rotation levels.
      else if(oldPhase == H6_BOOK_ROTATION)
      {
         for(int i = 0; i < ArraySize(m_levels); i++)
         {
            if(m_levels[i].role == H6_ROLE_CURRENT)
               m_levels[i].role = H6_ROLE_NONE;
         }
      }
      // Direct transition from one direction to the other.
      else
      {
         for(int i = 0; i < ArraySize(m_levels); i++)
         {
            if(m_levels[i].role == H6_ROLE_PREVIOUS ||
               m_levels[i].role == H6_ROLE_ROTATION)
            {
               m_levels[i].role = H6_ROLE_NONE;
            }
            else if(m_levels[i].role == H6_ROLE_CURRENT)
            {
               m_levels[i].role = H6_ROLE_PREVIOUS;
            }
         }
      }

      m_currentPhase = newPhase;

      Print("H6 BOOK | PHASE CHANGE | ",
            oldPhase, " -> ", newPhase);
   }

   ENUM_H6_LEVEL_ROLE RoleForPhase(const int phase)
   {
      if(phase == H6_BOOK_ROTATION)
         return H6_ROLE_ROTATION;

      return H6_ROLE_CURRENT;
   }

   bool AddLevel(const ENUM_H6_LEVEL_KIND kind,
                 const double price,
                 const datetime formedTime,
                 const int phase)
   {
      // Avoid recording the same kind of level at almost
      // the same price and time.
      double tol = Tolerance();

      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(m_levels[i].kind != kind)
            continue;

         if(m_levels[i].formedTime == formedTime)
            return false;

         if(MathAbs(m_levels[i].price - price) <= tol &&
            MathAbs((double)(m_levels[i].formedTime -
                             formedTime)) <=
                             PeriodSeconds(m_timeframe) * 2)
         {
            return false;
         }
      }

      int n = ArraySize(m_levels);

      // Keep memory bounded.
      if(n >= 300)
      {
         for(int j = 1; j < n; j++)
            m_levels[j-1] = m_levels[j];

         ArrayResize(m_levels, n-1);
         n = n-1;
      }

      if(ArrayResize(m_levels, n+1) != n+1)
         return false;

      m_levels[n].id               = m_nextId++;
      m_levels[n].kind             = kind;
      m_levels[n].role             = RoleForPhase(phase);
      m_levels[n].phase            = phase;
      m_levels[n].price            = price;
      m_levels[n].formedTime       = formedTime;

      m_levels[n].independentTests = 0;
      m_levels[n].holds            = 0;
      m_levels[n].breaks           = 0;

      m_levels[n].broken           = false;
      m_levels[n].touching         = false;
      m_levels[n].breakCounted     = false;
      m_levels[n].lastTestTime     = 0;

      Print("H6 BOOK | NEW ",
            (kind == H6_LEVEL_FLOOR ? "FLOOR" : "CEILING"),
            " | price=", DoubleToString(price, _Digits),
            " | time=", TimeToString(formedTime),
            " | phase=", phase,
            " | role=", (int)m_levels[n].role);

      return true;
   }

   bool IsTouching(const SH6PriceLevel &level,
                   const MqlRates &bar)
   {
      double tol = Tolerance();

      // A candle crosses the level or comes close to it.
      if(bar.low <= level.price && bar.high >= level.price)
         return true;

      if(MathAbs(bar.high - level.price) <= tol)
         return true;

      if(MathAbs(bar.low - level.price) <= tol)
         return true;

      return false;
   }

   bool IsBrokenByClose(const SH6PriceLevel &level,
                        const double closePrice)
   {
      double tol = Tolerance();

      if(level.kind == H6_LEVEL_FLOOR)
         return (closePrice < level.price - tol);

      return (closePrice > level.price + tol);
   }

   void UpdateTests(const MqlRates &bar)
   {
      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         bool touch = IsTouching(m_levels[i], bar);

         if(touch && !m_levels[i].touching)
         {
            m_levels[i].independentTests++;
            m_levels[i].touching     = true;
            m_levels[i].breakCounted = false;
            m_levels[i].lastTestTime = bar.time;

            Print("H6 BOOK | TEST ",
                  " | id=", m_levels[i].id,
                  " | price=",
                  DoubleToString(m_levels[i].price, _Digits),
                  " | count=", m_levels[i].independentTests);
         }

         if(m_levels[i].touching &&
            !m_levels[i].breakCounted &&
            IsBrokenByClose(m_levels[i], bar.close))
         {
            m_levels[i].breaks++;
            m_levels[i].broken       = true;
            m_levels[i].breakCounted = true;

            Print("H6 BOOK | BREAK ",
                  " | id=", m_levels[i].id,
                  " | close=", DoubleToString(bar.close, _Digits),
                  " | breaks=", m_levels[i].breaks);
         }

         // A new independent test can only start after price
         // has left the current contact cluster.
         if(!touch && m_levels[i].touching)
         {
            if(!m_levels[i].breakCounted)
            {
               m_levels[i].holds++;

               Print("H6 BOOK | HOLD ",
                     " | id=", m_levels[i].id,
                     " | holds=", m_levels[i].holds);
            }

            m_levels[i].touching = false;
         }
      }
   }

   void DetectConfirmedPivots(const MqlRates &bars[])
   {
      // Array is series-indexed:
      // bars[1] = latest closed candle
      // bars[3] = candidate pivot candle
      // bars[5] = older comparison candle
      //
      // Two candles on each side must confirm the pivot.

      bool isHigh =
         bars[3].high > bars[2].high &&
         bars[3].high > bars[1].high &&
         bars[3].high > bars[4].high &&
         bars[3].high > bars[5].high;

      bool isLow =
         bars[3].low < bars[2].low &&
         bars[3].low < bars[1].low &&
         bars[3].low < bars[4].low &&
         bars[3].low < bars[5].low;

      if(isHigh)
      {
         AddLevel(H6_LEVEL_CEILING,
                  bars[3].high,
                  bars[3].time,
                  m_currentPhase);
      }

      if(isLow)
      {
         AddLevel(H6_LEVEL_FLOOR,
                  bars[3].low,
                  bars[3].time,
                  m_currentPhase);
      }
   }

public:
   CH6PriceLevelBook()
   {
      m_nextId           = 1;
      m_currentPhase     = H6_BOOK_ROTATION;
      m_phaseInitialized = false;
      m_lastBarTime      = 0;
      m_symbol           = "";
      m_timeframe        = PERIOD_H6;
      m_tolerancePoints  = 20;

      ArrayResize(m_levels, 0);
   }

   void SetTolerancePoints(const int points)
   {
      if(points > 0)
         m_tolerancePoints = points;
   }

   void Update(const string symbol,
               const ENUM_TIMEFRAMES timeframe,
               const int phase)
   {
      if(phase < H6_BOOK_BEARISH ||
         phase > H6_BOOK_BULLISH)
         return;

      m_symbol    = symbol;
      m_timeframe = timeframe;

      datetime currentBarTime = iTime(m_symbol, m_timeframe, 0);

      if(currentBarTime == 0 ||
         currentBarTime == m_lastBarTime)
         return;

      m_lastBarTime = currentBarTime;

      ApplyPhaseTransition(phase);

      MqlRates bars[];
      ArraySetAsSeries(bars, true);

      if(CopyRates(m_symbol, m_timeframe, 1, 6, bars) != 6)
      {
         Print("H6 BOOK | CopyRates failed.");
         return;
      }

      // Process each newly closed candle once.
      UpdateTests(bars[0]);

      // Confirm older pivot using two candles on either side.
      DetectConfirmedPivots(bars);
   }

   int CountLevels(const ENUM_H6_LEVEL_ROLE role,
                   const ENUM_H6_LEVEL_KIND kind)
   {
      int count = 0;

      for(int i = 0; i < ArraySize(m_levels); i++)
      {
         if(m_levels[i].role == role &&
            m_levels[i].kind == kind)
            count++;
      }

      return count;
   }

   void PrintSummary()
   {
      Print("========== H6 PRICE BOOK ==========");
      Print("Previous floors: ",
            CountLevels(H6_ROLE_PREVIOUS, H6_LEVEL_FLOOR));
      Print("Previous ceilings: ",
            CountLevels(H6_ROLE_PREVIOUS, H6_LEVEL_CEILING));

      Print("Rotation floors: ",
            CountLevels(H6_ROLE_ROTATION, H6_LEVEL_FLOOR));
      Print("Rotation ceilings: ",
            CountLevels(H6_ROLE_ROTATION, H6_LEVEL_CEILING));

      Print("Current floors: ",
            CountLevels(H6_ROLE_CURRENT, H6_LEVEL_FLOOR));
      Print("Current ceilings: ",
            CountLevels(H6_ROLE_CURRENT, H6_LEVEL_CEILING));

      Print("===================================");
   }

   int TotalLevels()
   {
      return ArraySize(m_levels);
   }

   bool GetLevel(const int index, SH6PriceLevel &level)
   {
      if(index < 0 || index >= ArraySize(m_levels))
         return false;

      level = m_levels[index];
      return true;
   }
};

#endif // __H6_PRICE_LEVEL_BOOK_MQH__
