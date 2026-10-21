
#property strict
#property version "2.00"

#include <Trade/Trade.mqh>
#include "H6HorizontalChannels.mqh"

CH6HorizontalChannels ChannelDetector;
CTrade trade;

//==============================================================
// Inputs
//==============================================================
input double InpLots             = 0.01;
input int    InpConfirmGapBars    = 2;
input int    InpExitStageBars     = 10;
input int    InpProfitPoints      = 20;

//==============================================================
// Directions and states
//==============================================================
#define DIR_NONE   0
#define DIR_BUY    1
#define DIR_SELL  -1

#define EXIT_NONE   0
#define EXIT_STAGE1 1
#define EXIT_STAGE2 2

//==============================================================
// State
//==============================================================
datetime last_h6_bar_open = 0;

int confirmedDir = DIR_NONE;

// Opposite signal waiting for confirmation.
// Only the latest valid candidate is retained.
int         pendingDir = DIR_NONE;
H6HCSignal  pendingSignal;

// Old direction being closed
int exitDir   = DIR_NONE;
int exitStage = EXIT_NONE;
int exitBars  = 0;

// Prevent the same signal from being processed repeatedly.
string processedKeys[];

//==============================================================
// Price distance
//==============================================================
double RequiredProfitDistance()
{
   return (double)InpProfitPoints * _Point;
}

//==============================================================
// Signal identity
//==============================================================
string SignalKey(const H6HCSignal &s)
{
   return IntegerToString(s.direction) + "|" +
          (string)(long)s.bar_time + "|" +
          IntegerToString(s.top_level_index) + "|" +
          IntegerToString(s.bottom_level_index) + "|" +
          DoubleToString(s.breakout_close, _Digits);
}

bool WasProcessed(const string key)
{
   for(int i = 0; i < ArraySize(processedKeys); ++i)
   {
      if(processedKeys[i] == key)
         return true;
   }

   return false;
}

void MarkProcessed(const string key)
{
   int n = ArraySize(processedKeys);
   ArrayResize(processedKeys, n + 1);
   processedKeys[n] = key;
}

//==============================================================
// Position ownership and direction
// No Magic Number filtering, as requested.
//==============================================================
bool IsOurPosition(ulong ticket, int direction)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;

   ENUM_POSITION_TYPE type =
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   if(direction == DIR_BUY)
      return type == POSITION_TYPE_BUY;

   if(direction == DIR_SELL)
      return type == POSITION_TYPE_SELL;

   return false;
}

int CountPositions(int direction)
{
   int total = 0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket != 0 && IsOurPosition(ticket, direction))
         total++;
   }

   return total;
}

//==============================================================
// Pending order direction
//==============================================================
bool IsPendingType(ENUM_ORDER_TYPE type)
{
   return type == ORDER_TYPE_BUY_LIMIT  ||
          type == ORDER_TYPE_BUY_STOP   ||
          type == ORDER_TYPE_BUY_STOP_LIMIT ||
          type == ORDER_TYPE_SELL_LIMIT ||
          type == ORDER_TYPE_SELL_STOP  ||
          type == ORDER_TYPE_SELL_STOP_LIMIT;
}

bool IsPendingDirection(ulong ticket, int direction)
{
   if(!OrderSelect(ticket))
      return false;

   if(OrderGetString(ORDER_SYMBOL) != _Symbol)
      return false;

   ENUM_ORDER_TYPE type =
      (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

   if(!IsPendingType(type))
      return false;

   if(direction == DIR_BUY)
   {
      return type == ORDER_TYPE_BUY_LIMIT ||
             type == ORDER_TYPE_BUY_STOP ||
             type == ORDER_TYPE_BUY_STOP_LIMIT;
   }

   if(direction == DIR_SELL)
   {
      return type == ORDER_TYPE_SELL_LIMIT ||
             type == ORDER_TYPE_SELL_STOP ||
             type == ORDER_TYPE_SELL_STOP_LIMIT;
   }

   return false;
}

int CountPendingOrders(int direction)
{
   int total = 0;

   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);

      if(ticket != 0 && IsPendingDirection(ticket, direction))
         total++;
   }

   return total;
}

//==============================================================
// Delete pending orders of one direction
//==============================================================
void DeletePendingOrders(int direction)
{
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);

      if(ticket == 0 || !IsPendingDirection(ticket, direction))
         continue;

      if(!trade.OrderDelete(ticket))
      {
         Print("Pending delete failed | ticket=", ticket,
               " | ", trade.ResultRetcodeDescription());
      }
   }
}

//==============================================================
// Profit threshold based on actual prices
//==============================================================
bool HasMinimumPriceProfit(ulong ticket, int direction)
{
   if(!IsOurPosition(ticket, direction))
      return false;

   double openPrice =
      PositionGetDouble(POSITION_PRICE_OPEN);

   double currentPrice =
      PositionGetDouble(POSITION_PRICE_CURRENT);

   double distance = RequiredProfitDistance();

   if(direction == DIR_BUY)
      return currentPrice >= openPrice + distance;

   if(direction == DIR_SELL)
      return currentPrice <= openPrice - distance;

   return false;
}

bool AllPositionsProfitable(int direction)
{
   int total = 0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0 || !IsOurPosition(ticket, direction))
         continue;

      total++;

      if(!HasMinimumPriceProfit(ticket, direction))
         return false;
   }

   return total > 0;
}

//==============================================================
// Close positions
//==============================================================
void CloseAllPositions(int direction)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0 || !IsOurPosition(ticket, direction))
         continue;

      if(!trade.PositionClose(ticket))
      {
         Print("Close failed | ticket=", ticket,
               " | ", trade.ResultRetcodeDescription());
      }
   }
}

void CloseProfitablePositions(int direction)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0 || !IsOurPosition(ticket, direction))
         continue;

      if(!HasMinimumPriceProfit(ticket, direction))
         continue;

      if(!trade.PositionClose(ticket))
      {
         Print("Close profitable position failed | ticket=", ticket,
               " | ", trade.ResultRetcodeDescription());
      }
   }
}

//==============================================================
// Place an order at the historical signal price.
//
// BUY:
//   Historical price above Ask -> Buy Stop
//   Historical price below Ask -> Buy Limit
//
// SELL:
//   Historical price above Bid -> Sell Limit
//   Historical price below Bid -> Sell Stop
//
// If the pending price is too close to the market, use Market.
//==============================================================
bool OpenSignalOrder(int direction,
                     double signalPrice,
                     string comment)
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("Cannot obtain current tick.");
      return false;
   }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   int stopsLevel =
      (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   double minDistance = stopsLevel * point;

   // A small numerical margin for the minimum-distance check.
   double eps = point * 0.1;

   bool sent = false;

   if(direction == DIR_BUY)
   {
      double distance = MathAbs(signalPrice - tick.ask);

      if(distance <= minDistance + eps)
      {
         sent = trade.Buy(InpLots, _Symbol, 0.0, 0.0, 0.0,
                          comment + " MARKET");
      }
      else if(signalPrice > tick.ask)
      {
         sent = trade.BuyStop(
            InpLots, signalPrice, _Symbol,
            0.0, 0.0, ORDER_TIME_GTC, 0,
            comment + " BUY STOP"
         );
      }
      else
      {
         sent = trade.BuyLimit(
            InpLots, signalPrice, _Symbol,
            0.0, 0.0, ORDER_TIME_GTC, 0,
            comment + " BUY LIMIT"
         );
      }
   }
   else if(direction == DIR_SELL)
   {
      double distance = MathAbs(signalPrice - tick.bid);

      if(distance <= minDistance + eps)
      {
         sent = trade.Sell(InpLots, _Symbol, 0.0, 0.0, 0.0,
                           comment + " MARKET");
      }
      else if(signalPrice > tick.bid)
      {
         sent = trade.SellLimit(
            InpLots, signalPrice, _Symbol,
            0.0, 0.0, ORDER_TIME_GTC, 0,
            comment + " SELL LIMIT"
         );
      }
      else
      {
         sent = trade.SellStop(
            InpLots, signalPrice, _Symbol,
            0.0, 0.0, ORDER_TIME_GTC, 0,
            comment + " SELL STOP"
         );
      }
   }

   if(!sent)
   {
      Print("Signal order failed | direction=", direction,
            " | price=", DoubleToString(signalPrice, _Digits),
            " | ", trade.ResultRetcodeDescription());
   }
   else
   {
      Print("Signal order submitted | direction=", direction,
            " | signalPrice=", DoubleToString(signalPrice, _Digits),
            " | ", comment);
   }

   return sent;
}

//==============================================================
// Reset confirmation candidate
//==============================================================
void ResetPendingSignal()
{
   pendingDir = DIR_NONE;
   ZeroMemory(pendingSignal);
}

//==============================================================
// Start a confirmed direction switch
//==============================================================
void StartSwitch(int newDirection)
{
   int oldDirection = confirmedDir;

   Print("DIRECTION SWITCH | old=", oldDirection,
         " new=", newDirection);

   confirmedDir = newDirection;

   ResetPendingSignal();

   if(oldDirection == DIR_NONE || oldDirection == newDirection)
      return;

   if(CountPositions(oldDirection) > 0)
   {
      exitDir   = oldDirection;
      exitStage = EXIT_STAGE1;
      exitBars  = 0;
   }
   else
   {
      // No old positions to manage: remove old pending orders.
      DeletePendingOrders(oldDirection);

      exitDir   = DIR_NONE;
      exitStage = EXIT_NONE;
      exitBars  = 0;
   }
}

//==============================================================
// Check bars between two signal observations
//==============================================================
int SignalBarsApart(datetime firstTime, datetime secondTime)
{
   int firstShift =
      iBarShift(_Symbol, PERIOD_H6, firstTime, false);

   int secondShift =
      iBarShift(_Symbol, PERIOD_H6, secondTime, false);

   if(firstShift < 0 || secondShift < 0)
      return -1;

   return firstShift - secondShift;
}

//==============================================================
// Confirm whether a second signal has a favorable price.
//
// BUY confirmation: second close > first close
// SELL confirmation: second close < first close
//==============================================================
bool FavorableConfirmation(const H6HCSignal &first,
                           const H6HCSignal &second)
{
   if(second.direction == DIR_BUY)
      return second.breakout_close > first.breakout_close;

   if(second.direction == DIR_SELL)
      return second.breakout_close < first.breakout_close;

   return false;
}

//==============================================================
// Process one unique signal
//==============================================================
void ProcessOneSignal(const H6HCSignal &s)
{
   if(s.direction != DIR_BUY && s.direction != DIR_SELL)
      return;

   // Initial direction: require two qualifying signals.
   if(confirmedDir == DIR_NONE)
   {
      if(pendingDir == DIR_NONE)
      {
         pendingDir = s.direction;
         pendingSignal = s;

         Print("Initial direction candidate | dir=", pendingDir);
         return;
      }

      if(s.direction != pendingDir)
      {
         // Opposite isolated signal replaces the candidate.
         pendingDir = s.direction;
         pendingSignal = s;

         Print("Initial candidate replaced | dir=", pendingDir);
         return;
      }

      int barsApart =
         SignalBarsApart(pendingSignal.bar_time, s.bar_time);

      if(barsApart < 0)
         return;

      if(barsApart < InpConfirmGapBars)
         return;

      if(!FavorableConfirmation(pendingSignal, s))
      {
         // The newer signal becomes the new baseline.
         pendingSignal = s;

         Print("Initial confirmation reset | dir=", pendingDir);
         return;
      }

      int newDirection = s.direction;

      H6HCSignal first = pendingSignal;

      confirmedDir = newDirection;
      ResetPendingSignal();

      Print("INITIAL DIRECTION CONFIRMED | dir=", newDirection);

      // Both signals that established the direction are traded.
      OpenSignalOrder(newDirection, first.breakout_close,
                      "H6 initial confirmation 1");

      OpenSignalOrder(newDirection, s.breakout_close,
                      "H6 initial confirmation 2");

      return;
   }

   // Same-direction signals are traded individually.
   // They do not cancel an opposite-direction candidate.
   if(s.direction == confirmedDir)
   {
      OpenSignalOrder(s.direction, s.breakout_close,
                      "H6 confirmed direction");

      return;
   }

   // Opposite signal: first observation only.
   if(pendingDir != s.direction)
   {
      pendingDir = s.direction;
      pendingSignal = s;

      Print("Opposite candidate | dir=", pendingDir,
            " | price=", DoubleToString(s.breakout_close, _Digits));

      return;
   }

   // A second opposite signal must be sufficiently separated.
   int barsApart =
      SignalBarsApart(pendingSignal.bar_time, s.bar_time);

   if(barsApart < 0)
      return;

   if(barsApart < InpConfirmGapBars)
      return;

   // If price does not confirm, discard the older baseline
   // and retain the newer signal as the new candidate.
   if(!FavorableConfirmation(pendingSignal, s))
   {
      pendingSignal = s;

      Print("Opposite confirmation reset | dir=", pendingDir,
            " | new baseline=",
            DoubleToString(s.breakout_close, _Digits));

      return;
   }

   // Direction reversal confirmed.
   H6HCSignal first = pendingSignal;
   int newDirection = s.direction;

   Print("REVERSAL CONFIRMED | dir=", newDirection,
         " | first=", DoubleToString(first.breakout_close, _Digits),
         " | second=", DoubleToString(s.breakout_close, _Digits),
         " | gap=", barsApart, " H6 bars");

   StartSwitch(newDirection);

   // Only the two signals forming the confirmation pair
   // are submitted. Older rejected candidates are forgotten.
   OpenSignalOrder(newDirection, first.breakout_close,
                   "H6 reversal confirmation 1");

   OpenSignalOrder(newDirection, s.breakout_close,
                   "H6 reversal confirmation 2");
}

//==============================================================
// Manage exits on every tick
// Timers advance only when a new H6 bar appears.
//==============================================================
void ManageExits(bool newH6Bar)
{
   if(exitStage == EXIT_NONE)
      return;

   int positions = CountPositions(exitDir);
   int pendingOrders = CountPendingOrders(exitDir);

   if(positions == 0 && pendingOrders == 0)
   {
      Print("Previous direction fully closed.");

      exitDir   = DIR_NONE;
      exitStage = EXIT_NONE;
      exitBars  = 0;
      return;
   }

   // Stage 1
   if(exitStage == EXIT_STAGE1)
   {
      if(positions > 0 && AllPositionsProfitable(exitDir))
      {
         CloseAllPositions(exitDir);
         DeletePendingOrders(exitDir);

         if(CountPositions(exitDir) == 0 &&
            CountPendingOrders(exitDir) == 0)
         {
            exitDir   = DIR_NONE;
            exitStage = EXIT_NONE;
            exitBars  = 0;

            Print("EXIT COMPLETE | all profitable positions closed");
         }

         return;
      }

      if(newH6Bar)
         exitBars++;

      if(exitBars >= InpExitStageBars)
      {
         // Close profitable positions and cancel unfilled orders
         // belonging to the old direction.
         CloseProfitablePositions(exitDir);
         DeletePendingOrders(exitDir);

         exitStage = EXIT_STAGE2;
         exitBars  = 0;

         Print("EXIT STAGE 2 | remaining positions=",
               CountPositions(exitDir));

         if(CountPositions(exitDir) == 0)
         {
            exitDir   = DIR_NONE;
            exitStage = EXIT_NONE;
            exitBars  = 0;
         }
      }

      return;
   }

   // Stage 2
   if(exitStage == EXIT_STAGE2)
   {
      if(newH6Bar)
         exitBars++;

      if(exitBars >= InpExitStageBars)
      {
         CloseAllPositions(exitDir);
         DeletePendingOrders(exitDir);

         if(CountPositions(exitDir) == 0 &&
            CountPendingOrders(exitDir) == 0)
         {
            Print("EXIT COMPLETE");

            exitDir   = DIR_NONE;
            exitStage = EXIT_NONE;
            exitBars  = 0;
         }
      }
   }
}

//==============================================================
// Process all signals returned by the detector
// Sort chronologically so confirmation uses signal-time order.
//==============================================================
void ProcessH6Signals()
{
   H6HCSignal signals[];
   int count = ChannelDetector.GetLatestSignals(signals);

   if(count <= 0)
      return;

   H6HCSignal sorted[];
   ArrayResize(sorted, count);

   for(int i = 0; i < count; ++i)
      sorted[i] = signals[i];

   // Oldest signal first.
   for(int i = 0; i < count - 1; ++i)
   {
      for(int j = 0; j < count - 1 - i; ++j)
      {
         if(sorted[j].bar_time > sorted[j + 1].bar_time)
         {
            H6HCSignal temp = sorted[j];
            sorted[j] = sorted[j + 1];
            sorted[j + 1] = temp;
         }
      }
   }

   Print("H6 update | returned signals=", count);

   for(int i = 0; i < count; ++i)
   {
      string key = SignalKey(sorted[i]);

      if(WasProcessed(key))
         continue;

      // Mark before processing to prevent duplicate execution
      // if the detector returns this signal again.
      MarkProcessed(key);

      Print("NEW SIGNAL | ",
            sorted[i].direction == DIR_BUY ? "BUY" : "SELL",
            " | bar=", TimeToString(sorted[i].bar_time),
            " | close=",
            DoubleToString(sorted[i].breakout_close, _Digits),
            " | top=", DoubleToString(sorted[i].top, _Digits),
            " | bottom=", DoubleToString(sorted[i].bottom, _Digits));

      ProcessOneSignal(sorted[i]);
   }
}

//==============================================================
// OnInit
//==============================================================
int OnInit()
{
   trade.SetTypeFillingBySymbol(_Symbol);

   if(_Symbol != "EURUSD")
      Print("WARNING: EURUSD point/pip assumptions may differ.");

   last_h6_bar_open = iTime(_Symbol, PERIOD_H6, 0);

   Print("H6 EA initialized | symbol=", _Symbol);

   return INIT_SUCCEEDED;
}

//==============================================================
// OnTick
//==============================================================
void OnTick()
{
   datetime currentH6Open = iTime(_Symbol, PERIOD_H6, 0);

   if(currentH6Open == 0)
      return;

   bool newH6Bar = false;

   if(last_h6_bar_open == 0)
   {
      last_h6_bar_open = currentH6Open;
      return;
   }

   if(currentH6Open != last_h6_bar_open)
   {
      last_h6_bar_open = currentH6Open;
      newH6Bar = true;
   }

   // Exit management runs on every tick.
   ManageExits(newH6Bar);

   // Signal detection runs once per new H6 candle.
   if(newH6Bar)
      ProcessH6Signals();
}
