//+------------------------------------------------------------------+
//| H6HorizontalChannels.mqh                                         |
//| Horizontal channel detector, adapted from H6_HorizontalChannels  |
//+------------------------------------------------------------------+
#ifndef H6_HORIZONTAL_CHANNELS_MQH
#define H6_HORIZONTAL_CHANNELS_MQH

// Fixed internal parameters: intentionally not exposed as EA inputs.
#define H6HC_LOOKBACK_BARS            150
#define H6HC_TOLERANCE_PIPS           15.0
#define H6HC_MIN_FRACTAL_TOUCHES      2
#define H6HC_MIN_WIDTH_PIPS           30.0
#define H6HC_MAX_BOUNDARY_GAP_BARS    100
#define H6HC_BREAKOUT_BUFFER_PIPS     0.0

struct H6HCFractal
{
   datetime time;
   datetime confirmed_at;
   double   price;
   int      type;            // 1 = upper, -1 = lower
};

struct H6HCLevel
{
   int      type;
   double   anchor;
   double   level;
   datetime first_time;
   datetime confirm_time;
   int      count;
};

struct H6HCSignal
{
   int      direction;       // 1 = BUY, -1 = SELL
   datetime bar_time;        // time of the breakout H6 candle
   double   breakout_close;
   double   top;
   double   bottom;
   int      top_level_index;
   int      bottom_level_index;
};

class CH6HorizontalChannels
{
private:
   string m_symbol;
   double m_pip_size;

   double PipSize()
   {
      if(_Digits == 3 || _Digits == 5)
         return 10.0 * _Point;
      return _Point;
   }

   void AddFractal(H6HCFractal &fractals[],
                   datetime fractal_time,
                   datetime confirmed_at,
                   double price,
                   int type)
   {
      int n = ArraySize(fractals);
      ArrayResize(fractals, n + 1);
      fractals[n].time = fractal_time;
      fractals[n].confirmed_at = confirmed_at;
      fractals[n].price = price;
      fractals[n].type = type;
   }

   void BuildFractals(const MqlRates &rates[],
                      int bars,
                      datetime start_time,
                      datetime end_time,
                      H6HCFractal &fractals[])
   {
      ArrayResize(fractals, 0);

      // Series array: index 0 is newest; larger indices are older.
      // Two newer candles must exist for confirmation and neither may
      // be the currently forming candle (index 0).
      for(int i = bars - 3; i >= 3; --i)
      {
         datetime fractal_time = rates[i].time;
         if(fractal_time < start_time || fractal_time > end_time)
            continue;

         double h = rates[i].high;
         double l = rates[i].low;
         bool fh = true, fl = true, hs = false, ls = false;

         for(int j = 1; j <= 2; ++j)
         {
            if(h < rates[i-j].high || h < rates[i+j].high)
               fh = false;
            if(h > rates[i-j].high || h > rates[i+j].high)
               hs = true;

            if(l > rates[i-j].low || l > rates[i+j].low)
               fl = false;
            if(l < rates[i-j].low || l < rates[i+j].low)
               ls = true;
         }

         datetime confirmed_at = rates[i-2].time;
         if(confirmed_at > end_time)
            continue;

         if(fh && hs)
            AddFractal(fractals, fractal_time, confirmed_at, h, 1);
         if(fl && ls)
            AddFractal(fractals, fractal_time, confirmed_at, l, -1);
      }
   }

   void BuildLevels(const H6HCFractal &fractals[],
                    H6HCLevel &levels[])
   {
      ArrayResize(levels, 0);
      double tolerance = H6HC_TOLERANCE_PIPS * m_pip_size;
      int nf = ArraySize(fractals);

      // Fractals are chronological: oldest to newest.
      for(int i = 0; i < nf; ++i)
      {
         int matching = -1;
         int nl = ArraySize(levels);

         for(int k = 0; k < nl; ++k)
         {
            if(levels[k].type != fractals[i].type)
               continue;
            if(MathAbs(fractals[i].price - levels[k].anchor) <= tolerance)
            {
               matching = k;
               break;
            }
         }

         if(matching < 0)
         {
            int n = ArraySize(levels);
            ArrayResize(levels, n + 1);
            levels[n].type = fractals[i].type;
            levels[n].anchor = fractals[i].price;
            levels[n].level = fractals[i].price;
            levels[n].first_time = fractals[i].time;
            levels[n].confirm_time = 0;
            levels[n].count = 1;
            if(H6HC_MIN_FRACTAL_TOUCHES <= 1)
               levels[n].confirm_time = fractals[i].confirmed_at;
            continue;
         }

         int k = matching;
         levels[k].count++;

         if(levels[k].type == 1)
         {
            if(fractals[i].price > levels[k].level)
               levels[k].level = fractals[i].price;
         }
         else
         {
            if(fractals[i].price < levels[k].level)
               levels[k].level = fractals[i].price;
         }

         if(levels[k].count == H6HC_MIN_FRACTAL_TOUCHES)
            levels[k].confirm_time = fractals[i].confirmed_at;
      }
   }

   bool LevelsAreCompatible(const H6HCLevel &top,
                            const H6HCLevel &bottom)
   {
      if(top.confirm_time == 0 || bottom.confirm_time == 0)
         return false;
      if(top.level <= bottom.level)
         return false;

      double width_pips = (top.level - bottom.level) / m_pip_size;
      if(width_pips < H6HC_MIN_WIDTH_PIPS)
         return false;

      int top_shift = iBarShift(m_symbol, PERIOD_H6, top.confirm_time, false);
      int bottom_shift = iBarShift(m_symbol, PERIOD_H6, bottom.confirm_time, false);
      if(top_shift < 0 || bottom_shift < 0)
         return false;
      if(MathAbs(top_shift - bottom_shift) > H6HC_MAX_BOUNDARY_GAP_BARS)
         return false;

      return true;
   }

public:
   CH6HorizontalChannels()
   {
      m_symbol = "";
      m_pip_size = 0.0;
   }

   bool Init(string symbol = "")
   {
      m_symbol = (symbol == "" ? _Symbol : symbol);
      if(!SymbolSelect(m_symbol, true))
         return false;

      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      if(digits == 3 || digits == 5)
         m_pip_size = 10.0 * point;
      else
         m_pip_size = point;

      return true;
   }

   string Symbol()
   {
      return m_symbol;
   }

   // Returns all channels whose first confirmed breakout is on the
   // most recently closed H6 candle. No drawing and no trade filtering.
   int GetLatestSignals(H6HCSignal &signals[])
   {
      ArrayResize(signals, 0);

      if(m_symbol == "" && !Init())
         return 0;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);

      // Copy enough bars for the requested lookback plus fractal
      // confirmation context. The analysis window itself is 150 bars.
      int requested = H6HC_LOOKBACK_BARS + 5;
      int copied = CopyRates(m_symbol, PERIOD_H6, 0, requested, rates);
      if(copied < 10)
         return 0;

      // CopyRates puts the oldest copied element at physical start;
      // ArraySetAsSeries makes logical index 0 the newest.
      ArraySetAsSeries(rates, true);

      // Only completed bars: rates[0] is forming; rates[1] is latest closed.
      datetime latest_closed_time = rates[1].time;
      datetime start_time = rates[MathMin(H6HC_LOOKBACK_BARS, copied - 1)].time;
      datetime end_time = latest_closed_time;

      H6HCFractal fractals[];
      BuildFractals(rates, copied, start_time, end_time, fractals);

      H6HCLevel levels[];
      BuildLevels(fractals, levels);

      int nlevels = ArraySize(levels);
      double buffer = H6HC_BREAKOUT_BUFFER_PIPS * m_pip_size;

      // Every compatible top/bottom pair is independent, as requested.
      for(int t = 0; t < nlevels; ++t)
      {
         if(levels[t].type != 1 || levels[t].confirm_time == 0)
            continue;

         for(int b = 0; b < nlevels; ++b)
         {
            if(levels[b].type != -1 || levels[b].confirm_time == 0)
               continue;
            if(!LevelsAreCompatible(levels[t], levels[b]))
               continue;

            datetime channel_start =
               (levels[t].confirm_time > levels[b].confirm_time)
               ? levels[t].confirm_time : levels[b].confirm_time;

            if(channel_start >= latest_closed_time)
               continue;

            // Mirror script logic: first close outside after channel start.
            // Emit a signal only if that first breakout is the latest closed bar.
            for(int i = copied - 1; i >= 1; --i)
            {
               datetime bt = rates[i].time;
               if(bt <= channel_start)
                  continue;
               if(bt > latest_closed_time)
                  continue;

               int direction = 0;
               if(rates[i].close > levels[t].level + buffer)
                  direction = 1;
               else if(rates[i].close < levels[b].level - buffer)
                  direction = -1;

               if(direction == 0)
                  continue;

               if(bt == latest_closed_time)
               {
                  int n = ArraySize(signals);
                  ArrayResize(signals, n + 1);
                  signals[n].direction = direction;
                  signals[n].bar_time = bt;
                  signals[n].breakout_close = rates[i].close;
                  signals[n].top = levels[t].level;
                  signals[n].bottom = levels[b].level;
                  signals[n].top_level_index = t;
                  signals[n].bottom_level_index = b;
               }
               // This channel's first breakout was found; never look further.
               break;
            }
         }
      }

      return ArraySize(signals);
   }
};

#endif // H6_HORIZONTAL_CHANNELS_MQH
