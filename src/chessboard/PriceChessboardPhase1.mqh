#ifndef __PRICE_CHESSBOARD_PHASE1_MQH__
#define __PRICE_CHESSBOARD_PHASE1_MQH__

// Phase 1: reconstruct visits to one price band from closed H1 candles.
// This module stores results in an array. Logging is handled separately.

struct PCBVisit
{
   datetime startTime;
   datetime endTime;
   int      candleCount;

   // Entry/exit side relative to the band:
   // -1 = below, +1 = above, 0 = unknown/window boundary.
   int      entrySide;
   int      exitSide;

   // Price extremes clipped to the requested band.
   double   lowestPriceInBand;
   double   highestPriceInBand;

   int      bodyIntersectCandles;
   int      wickOnlyCandles;

   bool     lowerBoundaryBodyTouched;
   bool     lowerBoundaryWickOnly;
   bool     upperBoundaryBodyTouched;
   bool     upperBoundaryWickOnly;
};

class CPriceChessboardPhase1
{
private:
   PCBVisit m_visits[];
   int      m_barsAnalyzed;
   double   m_bandLow;
   double   m_bandHigh;

   int SideOfPrice(const double price)
   {
      if(price < m_bandLow)
         return -1;
      if(price > m_bandHigh)
         return +1;
      return 0;
   }

   void StartVisit(const datetime candleTime,
                   const double openPrice,
                   const double highPrice,
                   const double lowPrice,
                   const double closePrice,
                   const double previousClose,
                   const bool havePreviousClose)
   {
      int n = ArraySize(m_visits);
      ArrayResize(m_visits, n + 1);

      m_visits[n].startTime = candleTime;
      m_visits[n].endTime   = candleTime;
      m_visits[n].candleCount = 1;

      m_visits[n].entrySide = 0;
      if(havePreviousClose)
         m_visits[n].entrySide = SideOfPrice(previousClose);

      m_visits[n].exitSide = 0;

      m_visits[n].lowestPriceInBand =
         MathMax(lowPrice, m_bandLow);
      m_visits[n].highestPriceInBand =
         MathMin(highPrice, m_bandHigh);

      m_visits[n].bodyIntersectCandles = 0;
      m_visits[n].wickOnlyCandles = 0;

      m_visits[n].lowerBoundaryBodyTouched = false;
      m_visits[n].lowerBoundaryWickOnly = false;
      m_visits[n].upperBoundaryBodyTouched = false;
      m_visits[n].upperBoundaryWickOnly = false;

      UpdateVisit(n, openPrice, highPrice, lowPrice, closePrice);
   }

   void UpdateVisit(const int index,
                    const double openPrice,
                    const double highPrice,
                    const double lowPrice,
                    const double closePrice)
   {
      double bodyHigh = MathMax(openPrice, closePrice);
      double bodyLow  = MathMin(openPrice, closePrice);

      // The caller sets endTime to the exact candle being processed.
      m_visits[index].lowestPriceInBand =
         MathMin(m_visits[index].lowestPriceInBand,
                 MathMax(lowPrice, m_bandLow));
      m_visits[index].highestPriceInBand =
         MathMax(m_visits[index].highestPriceInBand,
                 MathMin(highPrice, m_bandHigh));

      if(bodyHigh >= m_bandLow && bodyLow <= m_bandHigh)
         m_visits[index].bodyIntersectCandles++;
      else
         m_visits[index].wickOnlyCandles++;

      if(lowPrice <= m_bandLow)
      {
         if(bodyLow <= m_bandLow)
            m_visits[index].lowerBoundaryBodyTouched = true;
         else
            m_visits[index].lowerBoundaryWickOnly = true;
      }

      if(highPrice >= m_bandHigh)
      {
         if(bodyHigh >= m_bandHigh)
            m_visits[index].upperBoundaryBodyTouched = true;
         else
            m_visits[index].upperBoundaryWickOnly = true;
      }
   }

   string SideName(const int side)
   {
      if(side < 0)
         return "BELOW";
      if(side > 0)
         return "ABOVE";
      return "UNKNOWN";
   }

   string YesNo(const bool value)
   {
      return (value ? "YES" : "NO");
   }

public:
   CPriceChessboardPhase1()
   {
      m_barsAnalyzed = 0;
      m_bandLow = 0.0;
      m_bandHigh = 0.0;
      ArrayResize(m_visits, 0);
   }

   bool AnalyzeBand(const double bandLow,
                    const double bandHigh,
                    const int lookbackClosedCandles)
   {
      ArrayResize(m_visits, 0);
      m_barsAnalyzed = 0;

      if(bandLow >= bandHigh || lookbackClosedCandles < 1)
         return false;

      m_bandLow  = bandLow;
      m_bandHigh = bandHigh;

      int available = Bars(_Symbol, PERIOD_H1);
      if(available < lookbackClosedCandles + 1)
         return false;

      bool active = false;
      bool havePreviousClose = false;
      double previousClose = 0.0;

      // Iterate from oldest to newest, using only CLOSED candles:
      // shifts lookbackClosedCandles ... 1. Shift 0 is excluded.
      for(int shift = lookbackClosedCandles; shift >= 1; shift--)
      {
         datetime candleTime = iTime(_Symbol, PERIOD_H1, shift);
         double openPrice  = iOpen(_Symbol, PERIOD_H1, shift);
         double highPrice  = iHigh(_Symbol, PERIOD_H1, shift);
         double lowPrice   = iLow(_Symbol, PERIOD_H1, shift);
         double closePrice = iClose(_Symbol, PERIOD_H1, shift);

         if(candleTime == 0)
            return false;

         m_barsAnalyzed++;

         bool intersects = (highPrice >= m_bandLow &&
                            lowPrice <= m_bandHigh);

         if(intersects)
         {
            if(!active)
            {
               StartVisit(candleTime,
                          openPrice,
                          highPrice,
                          lowPrice,
                          closePrice,
                          previousClose,
                          havePreviousClose);
               active = true;
            }
            else
            {
               int n = ArraySize(m_visits) - 1;
               m_visits[n].endTime = candleTime;
               m_visits[n].candleCount++;
               UpdateVisit(n, openPrice, highPrice, lowPrice, closePrice);
            }
         }
         else if(active)
         {
            int n = ArraySize(m_visits) - 1;
            m_visits[n].exitSide = SideOfPrice(closePrice);
            active = false;
         }

         previousClose = closePrice;
         havePreviousClose = true;
      }

      // If the latest closed candle still intersects the band, the visit
      // has no confirmed exit inside this query window.
      return (m_barsAnalyzed == lookbackClosedCandles);
   }

   int VisitCount() const
   {
      return ArraySize(m_visits);
   }

   int BarsAnalyzed() const
   {
      return m_barsAnalyzed;
   }

   double BandLow() const
   {
      return m_bandLow;
   }

   double BandHigh() const
   {
      return m_bandHigh;
   }

   PCBVisit GetVisit(const int index) const
   {
      return m_visits[index];
   }

   void PrintReport()
   {
      PrintFormat("[PCB_PHASE1] BAND %.5f - %.5f | CLOSED_BARS=%d | VISITS=%d",
                  m_bandLow, m_bandHigh, m_barsAnalyzed, ArraySize(m_visits));

      for(int i = 0; i < ArraySize(m_visits); i++)
      {
         PCBVisit v = m_visits[i];

         PrintFormat("[PCB_VISIT %02d] START=%s | END=%s | CANDLES=%d | ENTRY=%s | EXIT=%s",
                     i + 1,
                     TimeToString(v.startTime, TIME_DATE | TIME_MINUTES),
                     TimeToString(v.endTime, TIME_DATE | TIME_MINUTES),
                     v.candleCount,
                     SideName(v.entrySide),
                     SideName(v.exitSide));

         PrintFormat("[PCB_VISIT %02d] LOW_IN_BAND=%.5f | HIGH_IN_BAND=%.5f | BODY_INTERSECTIONS=%d | WICK_ONLY_CANDLES=%d",
                     i + 1,
                     v.lowestPriceInBand,
                     v.highestPriceInBand,
                     v.bodyIntersectCandles,
                     v.wickOnlyCandles);

         PrintFormat("[PCB_VISIT %02d] LOWER_BOUNDARY_BODY=%s | LOWER_BOUNDARY_WICK_ONLY=%s | UPPER_BOUNDARY_BODY=%s | UPPER_BOUNDARY_WICK_ONLY=%s",
                     i + 1,
                     YesNo(v.lowerBoundaryBodyTouched),
                     YesNo(v.lowerBoundaryWickOnly),
                     YesNo(v.upperBoundaryBodyTouched),
                     YesNo(v.upperBoundaryWickOnly));
      }
   }
};

#endif // __PRICE_CHESSBOARD_PHASE1_MQH__
