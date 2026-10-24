#ifndef __H6_TREE_OBSERVER_MQH__
#define __H6_TREE_OBSERVER_MQH__

//==============================================================
// H6 Tree Observer
// Symbol: EURUSD
// Timeframe: H6
// Trunk: EMA 50
// Regime reference: EMA 60
// Candle-by-candle expert logic
//==============================================================

struct SParallelChannel
{
   bool     valid;

   int      bars;

   datetime startTime;
   datetime endTime;

   // Price change per candle
   double   slope;

   // Both lines use:
   // price = intercept + slope * x
   // x = 0 at the oldest candle
   double   upperIntercept;
   double   lowerIntercept;

   // Vertical distance between parallel lines
   double   width;

   // Linear-regression R-squared: 0 to 1
   double   fitQuality;
};




enum ENUM_TREE_REGIME
{
   TREE_REGIME_UNKNOWN          = 0,
   TREE_REGIME_BULLISH          = 1,
   TREE_REGIME_BEARISH          = -1,
   TREE_REGIME_ROTATION_BULLISH = 2,
   TREE_REGIME_ROTATION_BEARISH = -2
};


//--------------------------------------------------------------
// CH6TreeObserver
//--------------------------------------------------------------
class CH6TreeObserver
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;

   int             m_ema50Handle;
   int             m_ema60Handle;

   datetime        m_lastBarTime;

   double          m_ema50;
   double          m_ema60;

   ENUM_TREE_REGIME m_regime;

private:
   bool IsNewBar();
   bool ReadMovingAverages();

   void UpdateRegime();
   void ProcessClosedBar();

















public:
   CH6TreeObserver();

   bool Init(const string symbol = "EURUSD",
             const ENUM_TIMEFRAMES timeframe = PERIOD_H6);

   bool FitParallelChannel(
      const int bars,
      SParallelChannel &channel
   );
   
   bool FitDirectionalChannel(
      const int bars,
      const int direction,
      SParallelChannel &channel
   );
  
   void Deinit();

   void Update();

   ENUM_TREE_REGIME Regime() const
   {
      return m_regime;
   }

   double EMA50() const
   {
      return m_ema50;
   }

   double EMA60() const
   {
      return m_ema60;
   }
};

//==============================================================
// Constructor
//==============================================================
CH6TreeObserver::CH6TreeObserver()
{
   m_symbol       = "";
   m_timeframe    = PERIOD_H6;

   m_ema50Handle  = INVALID_HANDLE;
   m_ema60Handle  = INVALID_HANDLE;

   m_lastBarTime  = 0;

   m_ema50        = 0.0;
   m_ema60        = 0.0;

   m_regime       = TREE_REGIME_UNKNOWN;

}

//==============================================================
// Initialization
//==============================================================
bool CH6TreeObserver::Init(const string symbol,
                           const ENUM_TIMEFRAMES timeframe)
{
   m_symbol    = symbol;
   m_timeframe = timeframe;

   if(!SymbolSelect(m_symbol, true))
   {
      Print("H6TreeObserver: SymbolSelect failed: ", m_symbol);
      return false;
   }

   m_ema50Handle = iMA(
      m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE
   );

   m_ema60Handle = iMA(
      m_symbol, m_timeframe, 60, 0, MODE_EMA, PRICE_CLOSE
   );

   if(m_ema50Handle == INVALID_HANDLE ||
      m_ema60Handle == INVALID_HANDLE)
   {
      Print("H6TreeObserver: EMA handle creation failed.");
      Deinit();
      return false;
   }

   return true;
}

//==============================================================
// Deinitialization
//==============================================================
void CH6TreeObserver::Deinit()
{
   if(m_ema50Handle != INVALID_HANDLE)
   {
      IndicatorRelease(m_ema50Handle);
      m_ema50Handle = INVALID_HANDLE;
   }

   if(m_ema60Handle != INVALID_HANDLE)
   {
      IndicatorRelease(m_ema60Handle);
      m_ema60Handle = INVALID_HANDLE;
   }
}

//==============================================================
// New candle detection
//==============================================================
bool CH6TreeObserver::IsNewBar()
{
   datetime barTime = iTime(m_symbol, m_timeframe, 0);

   if(barTime == 0)
      return false;

   if(barTime == m_lastBarTime)
      return false;

   m_lastBarTime = barTime;
   return true;
}

//==============================================================
// Read EMA values from the last CLOSED candle
//==============================================================
bool CH6TreeObserver::ReadMovingAverages()
{
   double ema50Buffer[1];
   double ema60Buffer[1];

   if(CopyBuffer(m_ema50Handle, 0, 1, 1, ema50Buffer) != 1)
      return false;

   if(CopyBuffer(m_ema60Handle, 0, 1, 1, ema60Buffer) != 1)
      return false;

   m_ema50 = ema50Buffer[0];
   m_ema60 = ema60Buffer[0];

   return true;
}

//==============================================================
// Determine bullish/bearish regime
//==============================================================
void CH6TreeObserver::UpdateRegime()
{
   // Read the last CLOSED H6 candle.
   MqlRates candle[1];

   if(CopyRates(m_symbol, m_timeframe, 1, 1, candle) != 1)
      return;

   double low   = candle[0].low;
   double high  = candle[0].high;
   double close = candle[0].close;

   // Determine whether the candle touches or crosses either EMA.
   bool touchesEMA50 =
      (low <= m_ema50 && high >= m_ema50);

   bool touchesEMA60 =
      (low <= m_ema60 && high >= m_ema60);

   bool touchesMA = touchesEMA50 || touchesEMA60;

   // EMA50 >= EMA60: bullish direction or bullish rotation.
   if(m_ema50 >= m_ema60)
   {
      if(!touchesMA && low > m_ema50 && low > m_ema60)
         m_regime = TREE_REGIME_BULLISH;
      else
         m_regime = TREE_REGIME_ROTATION_BULLISH;
   }
   // EMA50 < EMA60: bearish direction or bearish rotation.
   else
   {
      if(!touchesMA && high < m_ema50 && high < m_ema60)
         m_regime = TREE_REGIME_BEARISH;
      else
         m_regime = TREE_REGIME_ROTATION_BEARISH;
   }
}
//==============================================================
// Process one closed H6 candle
// Branch calculations will be added here.
//==============================================================
void CH6TreeObserver::ProcessClosedBar()
{
   if(!ReadMovingAverages())
      return;

   UpdateRegime();

   // TODO:
   // 1. Detect price approaching EMA50 trunk.
   // 2. Detect escape from trunk.
   // 3. Create and track escape guide.
   // 4. Detect guide break.
   // 5. Create and track return guide.
   // 6. Detect return toward trunk.
}

//==============================================================
// Public update: call from the main EA's OnTick()
//==============================================================
void CH6TreeObserver::Update()
{
   if(!IsNewBar())
      return;

   ProcessClosedBar();
}


bool CH6TreeObserver::FitParallelChannel(
   const int bars,
   SParallelChannel &channel
)
{
   // Reset output
   channel.valid          = false;
   channel.bars           = 0;
   channel.startTime      = 0;
   channel.endTime        = 0;
   channel.slope          = 0.0;
   channel.upperIntercept = 0.0;
   channel.lowerIntercept = 0.0;
   channel.width          = 0.0;
   channel.fitQuality     = 0.0;

   if(bars < 2)
      return false;

   // Read only closed candles.
   // Shift 1 excludes the currently forming candle.
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   ResetLastError();

   int copied = CopyRates(
      m_symbol,
      m_timeframe,
      1,
      bars,
      rates
   );

   if(copied != bars)
      return false;

   // Regression uses candle-body midpoints.
   // x = 0: oldest candle
   // x = bars - 1: newest closed candle

   double sumX  = 0.0;
   double sumY  = 0.0;
   double sumXX = 0.0;
   double sumXY = 0.0;

   for(int i = 0; i < bars; i++)
   {
      int x = bars - 1 - i;

      double bodyHigh = MathMax(
         rates[i].open,
         rates[i].close
      );

      double bodyLow = MathMin(
         rates[i].open,
         rates[i].close
      );

      double bodyMid = (bodyHigh + bodyLow) / 2.0;

      sumX  += (double)x;
      sumY  += bodyMid;
      sumXX += (double)x * (double)x;
      sumXY += (double)x * bodyMid;
   }

   double n = (double)bars;

   double denominator = n * sumXX - sumX * sumX;

   if(MathAbs(denominator) < 1e-12)
      return false;

   // Least-squares linear regression:
   // y = intercept + slope * x

   double slope =
      (n * sumXY - sumX * sumY) / denominator;

   double intercept =
      (sumY - slope * sumX) / n;

   // Extend the regression line into a channel.
   // The upper line covers every candle-body high.
   // The lower line covers every candle-body low.

   double upperOffset = -DBL_MAX;
   double lowerOffset =  DBL_MAX;

   double meanY = sumY / n;
   double sse   = 0.0;
   double sst   = 0.0;

   for(int i = 0; i < bars; i++)
   {
      int x = bars - 1 - i;

      double bodyHigh = MathMax(
         rates[i].open,
         rates[i].close
      );

      double bodyLow = MathMin(
         rates[i].open,
         rates[i].close
      );

      double bodyMid = (bodyHigh + bodyLow) / 2.0;

      double fittedPrice = intercept + slope * (double)x;

      double upperResidual = bodyHigh - fittedPrice;
      double lowerResidual = bodyLow  - fittedPrice;

      if(upperResidual > upperOffset)
         upperOffset = upperResidual;

      if(lowerResidual < lowerOffset)
         lowerOffset = lowerResidual;

      double error = bodyMid - fittedPrice;
      double deviation = bodyMid - meanY;

      sse += error * error;
      sst += deviation * deviation;
   }

   double upperIntercept = intercept + upperOffset;
   double lowerIntercept = intercept + lowerOffset;

   double width = upperIntercept - lowerIntercept;

   if(width < 0.0)
      return false;

   // R-squared measures how well the regression line
   // follows the body midpoints, not channel profitability.

   double fitQuality = 0.0;

   if(sst > 1e-20)
   {
      fitQuality = 1.0 - sse / sst;

      if(fitQuality < 0.0)
         fitQuality = 0.0;

      if(fitQuality > 1.0)
         fitQuality = 1.0;
   }
   else
   {
      // All body midpoints are effectively identical.
      fitQuality = (sse < 1e-20) ? 1.0 : 0.0;
   }

   // Return the fitted channel.

   channel.valid          = true;
   channel.bars           = bars;

   channel.startTime      = rates[bars - 1].time;
   channel.endTime        = rates[0].time;

   channel.slope          = slope;
   channel.upperIntercept = upperIntercept;
   channel.lowerIntercept = lowerIntercept;

   channel.width          = width;
   channel.fitQuality     = fitQuality;

   return true;
}

//+------------------------------------------------------------------+
//| Fit a channel using bullish or bearish candle bodies             |
//| direction: +1 = bullish, -1 = bearish                            |
//+------------------------------------------------------------------+
bool CH6TreeObserver::FitDirectionalChannel(
   const int bars,
   const int direction,
   SParallelChannel &channel
)
{
   channel.valid          = false;
   channel.bars           = 0;
   channel.startTime      = 0;
   channel.endTime        = 0;
   channel.slope          = 0.0;
   channel.upperIntercept = 0.0;
   channel.lowerIntercept = 0.0;
   channel.width          = 0.0;
   channel.fitQuality     = 0.0;

   if(bars < 3 || (direction != 1 && direction != -1))
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   if(CopyRates(m_symbol, m_timeframe, 1, bars, rates) != bars)
      return false;

   // Regression sums for selected candle bodies.
   double sumX  = 0.0;
   double sumY  = 0.0;
   double sumXX = 0.0;
   double sumXY = 0.0;
   int count = 0;

   for(int i = 0; i < bars; i++)
   {
      bool bullish = rates[i].close > rates[i].open;
      bool bearish = rates[i].close < rates[i].open;

      if(direction == 1 && !bullish)
         continue;

      if(direction == -1 && !bearish)
         continue;

      int x = bars - 1 - i;
      double bodyMid = (rates[i].open + rates[i].close) / 2.0;

      sumX  += x;
      sumY  += bodyMid;
      sumXX += (double)x * x;
      sumXY += (double)x * bodyMid;
      count++;
   }

   if(count < 3)
      return false;

   double n = (double)count;
   double denominator = n * sumXX - sumX * sumX;

   if(MathAbs(denominator) < 1e-12)
      return false;

   double slope =
      (n * sumXY - sumX * sumY) / denominator;

   double intercept = (sumY - slope * sumX) / n;
   double meanY = sumY / n;

   // Residuals are collected only from candles of the selected direction.
   double upperResiduals[];
   double lowerResiduals[];

   ArrayResize(upperResiduals, count);
   ArrayResize(lowerResiduals, count);

   double sse = 0.0;
   double sst = 0.0;
   int k = 0;

   for(int i = 0; i < bars; i++)
   {
      bool bullish = rates[i].close > rates[i].open;
      bool bearish = rates[i].close < rates[i].open;

      if(direction == 1 && !bullish)
         continue;

      if(direction == -1 && !bearish)
         continue;

      int x = bars - 1 - i;

      double bodyHigh = MathMax(rates[i].open, rates[i].close);
      double bodyLow  = MathMin(rates[i].open, rates[i].close);
      double bodyMid  = (bodyHigh + bodyLow) / 2.0;

      double fitted = intercept + slope * (double)x;

      upperResiduals[k] = bodyHigh - fitted;
      lowerResiduals[k] = bodyLow - fitted;

      double error = bodyMid - fitted;
      double deviation = bodyMid - meanY;

      sse += error * error;
      sst += deviation * deviation;

      k++;
   }

   // Sort residuals to reduce the effect of isolated outliers.
   ArraySort(upperResiduals);
   ArraySort(lowerResiduals);

   // Keep the central 70% of the residual distribution.
   // This is an initial visual setting, not a trading threshold.
   int upperIndex = (int)MathFloor((count - 1) * 0.85);
   int lowerIndex = (int)MathFloor((count - 1) * 0.15);

   double upperIntercept = intercept + upperResiduals[upperIndex];
   double lowerIntercept = intercept + lowerResiduals[lowerIndex];

   if(upperIntercept < lowerIntercept)
   {
      double mid = (upperIntercept + lowerIntercept) / 2.0;
      upperIntercept = mid;
      lowerIntercept = mid;
   }

   double width = upperIntercept - lowerIntercept;

   double fitQuality = 0.0;

   if(sst > 1e-20)
   {
      fitQuality = 1.0 - sse / sst;

      if(fitQuality < 0.0)
         fitQuality = 0.0;

      if(fitQuality > 1.0)
         fitQuality = 1.0;
   }
   else
   {
      fitQuality = (sse < 1e-20) ? 1.0 : 0.0;
   }

   channel.valid          = true;
   channel.bars           = bars;
   channel.startTime      = rates[bars - 1].time;
   channel.endTime        = rates[0].time;
   channel.slope          = slope;
   channel.upperIntercept = upperIntercept;
   channel.lowerIntercept = lowerIntercept;
   channel.width          = width;
   channel.fitQuality     = fitQuality;

   return true;
}


//+------------------------------------------------------------------+
//| Draw or update the two parallel channel lines                   |
//+------------------------------------------------------------------+
bool DrawParallelChannel(
   const SParallelChannel &channel,
   const string prefix = "H6Tree_Channel",
   const color upperColor = clrDodgerBlue,
   const color lowerColor = clrOrangeRed,
   const int lineWidth = 2
)
{
   if(!channel.valid || channel.bars < 2)
      return false;

   if(lineWidth < 1 || lineWidth > 5)
      return false;

   string upperName = prefix + "_UPPER";
   string lowerName = prefix + "_LOWER";

   // Channel prices at the oldest and newest closed candles
   double upperStart = channel.upperIntercept;
   double upperEnd =
      channel.upperIntercept +
      channel.slope * (channel.bars - 1);

   double lowerStart = channel.lowerIntercept;
   double lowerEnd =
      channel.lowerIntercept +
      channel.slope * (channel.bars - 1);

   // Create the upper line if it does not exist
   if(ObjectFind(0, upperName) < 0)
   {
      if(!ObjectCreate(
         0, upperName, OBJ_TREND, 0,
         channel.startTime, upperStart,
         channel.endTime, upperEnd
      ))
         return false;
   }
   else
   {
      ObjectMove(
         0, upperName, 0,
         channel.startTime, upperStart
      );

      ObjectMove(
         0, upperName, 1,
         channel.endTime, upperEnd
      );
   }

   // Create the lower line if it does not exist
   if(ObjectFind(0, lowerName) < 0)
   {
      if(!ObjectCreate(
         0, lowerName, OBJ_TREND, 0,
         channel.startTime, lowerStart,
         channel.endTime, lowerEnd
      ))
         return false;
   }
   else
   {
      ObjectMove(
         0, lowerName, 0,
         channel.startTime, lowerStart
      );

      ObjectMove(
         0, lowerName, 1,
         channel.endTime, lowerEnd
      );
   }

   // Upper line properties
   ObjectSetInteger(0, upperName, OBJPROP_COLOR, upperColor);
   ObjectSetInteger(0, upperName, OBJPROP_WIDTH, lineWidth);
   ObjectSetInteger(0, upperName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, upperName, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, upperName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, upperName, OBJPROP_SELECTABLE, true);

   // Lower line properties
   ObjectSetInteger(0, lowerName, OBJPROP_COLOR, lowerColor);
   ObjectSetInteger(0, lowerName, OBJPROP_WIDTH, lineWidth);
   ObjectSetInteger(0, lowerName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, lowerName, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, lowerName, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lowerName, OBJPROP_SELECTABLE, true);

   ChartRedraw(0);

   return true;
}







#endif // __H6_TREE_OBSERVER_MQH__
