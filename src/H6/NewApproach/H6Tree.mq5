
#include "H6TreeObserver.mqh"
#include "H6PriceLevelBook.mqh"

//==============================================================
// Inputs
//==============================================================
CH6PriceLevelBook PriceBook;
CH6TreeObserver   Observer;

string          InpSymbol    = "EURUSD";
ENUM_TIMEFRAMES InpTimeframe = PERIOD_H6;
int             InpChannelBars = 20;

// Maximum distance between corresponding channel boundaries.
input double InpChannelMergeTolerancePoints = 100.0;

// Minimum percentage of points where both boundaries are close.
input double InpChannelMergeMinPercent = 80.0;

//==============================================================
// Manual confirmation state
//==============================================================
string MERGE_BUTTON = "H6Tree_Merge_OK";
string MERGE_LABEL  = "H6Tree_Merge_Message";

bool g_waitingForOK       = false;
bool g_channelMergeWasMerged = false;
bool g_resumeAfterOK      = false;

//==============================================================
// Create a confirmation prompt on the chart
//==============================================================
void ShowChannelMergePrompt(const double matchedPercent)
{
   g_waitingForOK = true;

   ObjectDelete(0, MERGE_BUTTON);
   ObjectDelete(0, MERGE_LABEL);

   if(ObjectCreate(0, MERGE_LABEL, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, MERGE_LABEL, OBJPROP_CORNER,
                       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, MERGE_LABEL, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, MERGE_LABEL, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, MERGE_LABEL, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, MERGE_LABEL, OBJPROP_FONTSIZE, 12);
      ObjectSetString(0, MERGE_LABEL, OBJPROP_FONT, "Arial");

      ObjectSetString(
         0,
         MERGE_LABEL,
         OBJPROP_TEXT,
         "H6 channels nearly merged: " +
         DoubleToString(matchedPercent, 1) +
         "% - Expert paused"
      );
   }

   if(ObjectCreate(0, MERGE_BUTTON, OBJ_BUTTON, 0, 0, 0))
   {
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_CORNER,
                       CORNER_LEFT_UPPER);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_XDISTANCE, 20);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_YDISTANCE, 60);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_XSIZE, 100);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_YSIZE, 30);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_BGCOLOR, clrDarkGreen);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_BORDER_COLOR, clrWhite);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_FONTSIZE, 11);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_STATE, false);

      ObjectSetString(
         0,
         MERGE_BUTTON,
         OBJPROP_TEXT,
         "OK - Resume"
      );
   }

   ChartRedraw(0);
}

//==============================================================
// Compare the two fitted channels
//==============================================================
bool AreChannelsNearlySame(
   const SParallelChannel &bull,
   const SParallelChannel &bear,
   double &matchedPercent
)
{
   matchedPercent = 0.0;

   if(!bull.valid || !bear.valid)
      return false;

   if(bull.bars < 2 || bull.bars != bear.bars)
      return false;

   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);

   if(point <= 0.0)
      return false;

   int matched = 0;

   for(int x = 0; x < bull.bars; x++)
   {
      double bullUpper =
         bull.upperIntercept + bull.slope * x;

      double bearUpper =
         bear.upperIntercept + bear.slope * x;

      double bullLower =
         bull.lowerIntercept + bull.slope * x;

      double bearLower =
         bear.lowerIntercept + bear.slope * x;

      double upperGap = MathAbs(bullUpper - bearUpper) / point;
      double lowerGap = MathAbs(bullLower - bearLower) / point;

      if(upperGap <= InpChannelMergeTolerancePoints &&
         lowerGap <= InpChannelMergeTolerancePoints)
      {
         matched++;
      }
   }

   matchedPercent = 100.0 * matched / bull.bars;

   return (matchedPercent >= InpChannelMergeMinPercent);
}

//==============================================================
// Detect transition into merged state
//==============================================================
void CheckChannelMerge(
   const SParallelChannel &bull,
   const SParallelChannel &bear
)
{
   double matchedPercent = 0.0;

   if(!bull.valid || !bear.valid)
      return;

   bool merged = AreChannelsNearlySame(bull, bear, matchedPercent);

   if(!merged)
   {
      g_channelMergeWasMerged = false;
      return;
   }

   // Only pause on the transition into the merged state.
   if(!g_channelMergeWasMerged)
   {
      g_channelMergeWasMerged = true;
      ShowChannelMergePrompt(matchedPercent);
   }
}

//==============================================================
// Initialization
//==============================================================
int OnInit()
{
   if(!Observer.Init(InpSymbol, InpTimeframe))
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

//==============================================================
// Deinitialization
//==============================================================
void OnDeinit(const int reason)
{
   ObjectDelete(0, MERGE_BUTTON);
   ObjectDelete(0, MERGE_LABEL);

   Observer.Deinit();
}

//==============================================================
// Chart events: wait for the user's OK click
//==============================================================
void OnChartEvent(
   const int id,
   const long &lparam,
   const double &dparam,
   const string &sparam
)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam != MERGE_BUTTON || !g_waitingForOK)
      return;

   ObjectSetInteger(0, MERGE_BUTTON, OBJPROP_STATE, false);

   ObjectDelete(0, MERGE_BUTTON);
   ObjectDelete(0, MERGE_LABEL);

   g_waitingForOK = false;
   g_resumeAfterOK = true;

   ChartRedraw(0);
}



input double InpSlopeProductMin = -1.1;
input double InpSlopeProductMax = -0.9;

bool AreChannelsNearRightAngle(
   const SParallelChannel &bull,
   const SParallelChannel &bear
)
{
   if(!bull.valid || !bear.valid)
      return false;

   double product = bull.slope * bear.slope;

   return (product >= InpSlopeProductMin &&
           product <= InpSlopeProductMax);
}


//==============================================================
// Main tick
//==============================================================
void OnTick()
{
   // Pause all EA processing until the user clicks OK.
   if(g_waitingForOK)
      return;

   Observer.Update();

   // Process channels only once per new H6 candle,
   // except when resuming after manual confirmation.
   static datetime lastChannelBar = 0;

   datetime currentBar = iTime(
      InpSymbol,
      InpTimeframe,
      0
   );

   if(currentBar == 0)
      return;

   if(currentBar == lastChannelBar && !g_resumeAfterOK)
      return;

   if(g_resumeAfterOK)
   {
      g_resumeAfterOK = false;
   }
   else
   {
      lastChannelBar = currentBar;
   }

   SParallelChannel bullishChannel;
   SParallelChannel bearishChannel;

   // Bullish candle bodies
   if(Observer.FitDirectionalChannel(
      InpChannelBars, 1, bullishChannel))
   {
      DrawParallelChannel(
         bullishChannel,
         "H6Tree_Bull",
         clrLimeGreen,
         clrLimeGreen,
         2
      );
   }
   else
   {
      ObjectDelete(0, "H6Tree_Bull_UPPER");
      ObjectDelete(0, "H6Tree_Bull_LOWER");
   }

   // Bearish candle bodies
   if(Observer.FitDirectionalChannel(
      InpChannelBars, -1, bearishChannel))
   {
      DrawParallelChannel(
         bearishChannel,
         "H6Tree_Bear",
         clrTomato,
         clrTomato,
         2
      );
   }
   else
   {
      ObjectDelete(0, "H6Tree_Bear_UPPER");
      ObjectDelete(0, "H6Tree_Bear_LOWER");
   }

   // Pause when the two channels become nearly identical.
   CheckChannelMerge(bullishChannel, bearishChannel);

   if(g_waitingForOK)
      return;

   // Map observer regime to price-book phase.
   int bookPhase = H6_BOOK_ROTATION;

   switch(Observer.Regime())
   {
      case TREE_REGIME_BULLISH:
         bookPhase = H6_BOOK_BULLISH;
         break;

      case TREE_REGIME_BEARISH:
         bookPhase = H6_BOOK_BEARISH;
         break;

      case TREE_REGIME_ROTATION_BULLISH:
      case TREE_REGIME_ROTATION_BEARISH:
      case TREE_REGIME_UNKNOWN:
      default:
         bookPhase = H6_BOOK_ROTATION;
         break;
   }



if(AreChannelsNearRightAngle(
      bullishChannel,
      bearishChannel))
{
   // اینجا سازوکار توقف و انتظار برای OK
}



   PriceBook.Update(
      InpSymbol,
      InpTimeframe,
      bookPhase
   );
}
