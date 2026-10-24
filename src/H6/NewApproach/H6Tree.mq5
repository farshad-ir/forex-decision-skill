//
#include "H6TreeObserver.mqh"
#include "H6PriceLevelBook.mqh"

CH6PriceLevelBook PriceBook;
string          InpSymbol    = "EURUSD";
ENUM_TIMEFRAMES InpTimeframe = PERIOD_H6;
int InpChannelBars = 20;

CH6TreeObserver Observer;

int OnInit()
{
   if(!Observer.Init(InpSymbol, InpTimeframe))
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Observer.Deinit();
}


void OnTick__()
{
   // Keep the observer's normal update process.
   Observer.Update();

   // Refit and redraw only when a new H6 bar begins.
   static datetime lastChannelBar = 0;

   datetime currentBar = iTime(
      InpSymbol,
      InpTimeframe,
      0
   );

   if(currentBar == 0 || currentBar == lastChannelBar)
      return;

   lastChannelBar = currentBar;

   SParallelChannel channel;

   if(Observer.FitParallelChannel(InpChannelBars, channel))
   {
      DrawParallelChannel(
         channel,
         "H6Tree_Channel",
         clrDodgerBlue,
         clrOrangeRed,
         2
      );
   }
}

void OnTick()
{
   Observer.Update();

   static datetime lastChannelBar = 0;

   datetime currentBar = iTime(
      InpSymbol,
      InpTimeframe,
      0
   );

   if(currentBar == 0 || currentBar == lastChannelBar)
      return;

   lastChannelBar = currentBar;

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
   


   // Update the observer first.
   //Observer.Update();

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
   
   PriceBook.Update(
      InpSymbol,
      InpTimeframe,
      bookPhase
   );      
   

}
