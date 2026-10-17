#property strict
#property version   "1.00"
#property description "Phase 1 test: reconstruct price visits to one band."

#include "PriceChessboardPhase1.mqh"

double InpBandLow = 1.0900;
double InpBandHigh = 1.0965;
int    InpLookbackClosedCandles = 300;

CPriceChessboardPhase1 g_chessboard;

int OnInit()
{
   if(!g_chessboard.AnalyzeBand(InpBandLow,
                                InpBandHigh,
                                InpLookbackClosedCandles))
   {
      Print("[PCB_PHASE1] ERROR: invalid band or insufficient H1 history.");
      return INIT_FAILED;
   }

   g_chessboard.PrintReport();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   // This is a one-shot historical test.
   // Re-run the test by starting a new Strategy Tester pass or reloading
   // the EA after changing its input parameters.
}
