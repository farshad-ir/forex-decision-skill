#ifndef __H6_TRADE_MANAGER_MQH__
#define __H6_TRADE_MANAGER_MQH__

#include <Trade/Trade.mqh>
#include "H6HorizontalChannels.mqh"

#define DIR_NONE    0
#define DIR_BUY     1
#define DIR_SELL   -1

#define EXIT_NONE   0
#define EXIT_STAGE1 1
#define EXIT_STAGE2 2

class CH6TradeManager
{
private:
   CH6HorizontalChannels ChannelDetector;
   CTrade trade;

   int  m_profitReversalMinPositions;
   bool m_basketWasProfitable;

   double m_lots;
   int    m_confirmGapBars;
   int    m_exitStageBars;
   int    m_profitPoints;

   datetime last_h6_bar_open;
   int confirmedDir;
   int pendingDir;
   H6HCSignal pendingSignal;

   int exitDir;
   int exitStage;
   int exitBars;

   string processedKeys[];
   
   double BasketLots(int direction){
   
      double Lots = 0.0;
   
      for(int i = PositionsTotal() - 1; i >= 0; --i)
      {
         ulong ticket = PositionGetTicket(i);
   
         if(ticket == 0 || !IsOurPosition(ticket, direction))
            continue;
   
         Lots += PositionGetDouble(POSITION_VOLUME);
      }
   
      return Lots;
   }

   //===========================================================
   // Price distance
   //===========================================================
   double RequiredProfitDistance()
   {
      return (double)m_profitPoints * _Point;
   }



   double BasketProfit(int direction)
   {
      double profit = 0.0;
   
      for(int i = PositionsTotal() - 1; i >= 0; --i)
      {
         ulong ticket = PositionGetTicket(i);
   
         if(ticket == 0 || !IsOurPosition(ticket, direction))
            continue;
   
         profit += PositionGetDouble(POSITION_PROFIT);
         profit += PositionGetDouble(POSITION_SWAP);
      }
   
      return profit;
   }
   
   // Alternative regime switch based on basket profit reversal.

   void CheckProfitReversalSwitch()
   {
      if(confirmedDir != DIR_BUY && confirmedDir != DIR_SELL)
         return;
   
      int positions = CountPositions(confirmedDir);
   
      if(positions < m_profitReversalMinPositions)
      {
         m_basketWasProfitable = false;
         return;
      }
   
      double profit = BasketProfit(confirmedDir) / BasketLots(confirmedDir);
   
      // Stage 1: Basket must reach 100 points per position.
      double targetProfit = positions * 100.0;
   
      if(!m_basketWasProfitable)
      {
         if(profit >= targetProfit)
            m_basketWasProfitable = true;
   
         return;
      }
   
      // Stage 2: Switch when profit falls below 20 points per position.
      double minProfit = positions * 20.0;
   
      if(profit >= minProfit)
         return;
   
      int oldDirection = confirmedDir;
      int newDirection = -oldDirection;
   
      Print("PROFIT REVERSAL SWITCH | positions=", positions,
            " | basketProfit=", DoubleToString(profit, 2),
            " | targetProfit=", DoubleToString(targetProfit, 2),
            " | minProfit=", DoubleToString(minProfit, 2),
            " | old=", oldDirection,
            " | new=", newDirection);
   
      StartSwitch(newDirection);
   }






   //===========================================================
   // Signal identity
   //===========================================================
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

   //===========================================================
   // Position ownership and direction
   // No Magic Number filtering
   //===========================================================
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

   //===========================================================
   // Pending orders
   //===========================================================
   bool IsPendingType(ENUM_ORDER_TYPE type)
   {
      return type == ORDER_TYPE_BUY_LIMIT ||
             type == ORDER_TYPE_BUY_STOP ||
             type == ORDER_TYPE_BUY_STOP_LIMIT ||
             type == ORDER_TYPE_SELL_LIMIT ||
             type == ORDER_TYPE_SELL_STOP ||
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

   void DeletePendingOrders(int direction)
   {
      for(int i = OrdersTotal() - 1; i >= 0; --i)
      {
         ulong ticket = OrderGetTicket(i);

         if(ticket == 0 ||
            !IsPendingDirection(ticket, direction))
            continue;

         if(!trade.OrderDelete(ticket))
         {
            Print("Pending delete failed | ticket=", ticket,
                  " | ", trade.ResultRetcodeDescription());
         }
      }
   }

   //===========================================================
   // Profit checks
   //===========================================================
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

   //===========================================================
   // Close positions
   //===========================================================
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

   //===========================================================
   // Submit signal order
   //===========================================================
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
      double eps = point * 0.1;

      bool sent = false;

      if(direction == DIR_BUY)
      {
         double distance = MathAbs(signalPrice - tick.ask);

         if(distance <= minDistance + eps)
         {
            sent = trade.Buy(m_lots, _Symbol, 0.0, 0.0, 0.0,
                             comment + " MARKET");
         }
         else if(signalPrice > tick.ask)
         {
            sent = trade.BuyStop(
               m_lots, signalPrice, _Symbol,
               0.0, 0.0, ORDER_TIME_GTC, 0,
               comment + " BUY STOP"
            );
         }
         else
         {
            sent = trade.BuyLimit(
               m_lots, signalPrice, _Symbol,
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
            sent = trade.Sell(m_lots, _Symbol, 0.0, 0.0, 0.0,
                              comment + " MARKET");
         }
         else if(signalPrice > tick.bid)
         {
            sent = trade.SellLimit(
               m_lots, signalPrice, _Symbol,
               0.0, 0.0, ORDER_TIME_GTC, 0,
               comment + " SELL LIMIT"
            );
         }
         else
         {
            sent = trade.SellStop(
               m_lots, signalPrice, _Symbol,
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

   //===========================================================
   // Confirmation candidate
   //===========================================================
   void ResetPendingSignal()
   {
      pendingDir = DIR_NONE;
      ZeroMemory(pendingSignal);
   }

   //===========================================================
   // Start direction switch
   //===========================================================
   void StartSwitch(int newDirection)
   {
      int oldDirection = confirmedDir;

      Print("DIRECTION SWITCH | old=", oldDirection,
            " new=", newDirection);

      confirmedDir = newDirection;
      ResetPendingSignal();
      m_basketWasProfitable = false;

      if(oldDirection == DIR_NONE ||
         oldDirection == newDirection)
         return;

      if(CountPositions(oldDirection) > 0)
      {
         exitDir   = oldDirection;
         exitStage = EXIT_STAGE1;
         exitBars  = 0;
      }
      else
      {
         DeletePendingOrders(oldDirection);

         exitDir   = DIR_NONE;
         exitStage = EXIT_NONE;
         exitBars  = 0;
      }
   }

   //===========================================================
   // Bars between two signals
   //===========================================================
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

   bool FavorableConfirmation(const H6HCSignal &first,
                             const H6HCSignal &second)
   {
      if(second.direction == DIR_BUY)
         return second.breakout_close > first.breakout_close;

      if(second.direction == DIR_SELL)
         return second.breakout_close < first.breakout_close;

      return false;
   }

   //===========================================================
   // Process one signal
   //===========================================================
   void ProcessOneSignal(const H6HCSignal &s)
   {
      if(s.direction != DIR_BUY && s.direction != DIR_SELL)
         return;

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
            pendingDir = s.direction;
            pendingSignal = s;

            Print("Initial candidate replaced | dir=", pendingDir);
            return;
         }

         int barsApart =
            SignalBarsApart(pendingSignal.bar_time, s.bar_time);

         if(barsApart < 0 || barsApart < m_confirmGapBars)
            return;

         if(!FavorableConfirmation(pendingSignal, s))
         {
            pendingSignal = s;

            Print("Initial confirmation reset | dir=", pendingDir);
            return;
         }

         int newDirection = s.direction;
         H6HCSignal first = pendingSignal;

         confirmedDir = newDirection;
         ResetPendingSignal();

         Print("INITIAL DIRECTION CONFIRMED | dir=", newDirection);

         OpenSignalOrder(newDirection, first.breakout_close,
                         "H6 initial confirmation 1");

         OpenSignalOrder(newDirection, s.breakout_close,
                         "H6 initial confirmation 2");

         return;
      }

      if(s.direction == confirmedDir)
      {
         OpenSignalOrder(s.direction, s.breakout_close,
                         "H6 confirmed direction");
         return;
      }

      if(pendingDir != s.direction)
      {
         pendingDir = s.direction;
         pendingSignal = s;

         Print("Opposite candidate | dir=", pendingDir,
               " | price=", DoubleToString(s.breakout_close, _Digits));
         return;
      }

      int barsApart =
         SignalBarsApart(pendingSignal.bar_time, s.bar_time);

      if(barsApart < 0 || barsApart < m_confirmGapBars)
         return;

      if(!FavorableConfirmation(pendingSignal, s))
      {
         pendingSignal = s;

         Print("Opposite confirmation reset | dir=", pendingDir,
               " | new baseline=",
               DoubleToString(s.breakout_close, _Digits));
         return;
      }

      H6HCSignal first = pendingSignal;
      int newDirection = s.direction;

      Print("REVERSAL CONFIRMED | dir=", newDirection,
            " | first=", DoubleToString(first.breakout_close, _Digits),
            " | second=", DoubleToString(s.breakout_close, _Digits),
            " | gap=", barsApart, " H6 bars");

      StartSwitch(newDirection);

      OpenSignalOrder(newDirection, first.breakout_close,
                      "H6 reversal confirmation 1");

      OpenSignalOrder(newDirection, s.breakout_close,
                      "H6 reversal confirmation 2");
   }

   //===========================================================
   // Manage exits on every tick
   //===========================================================
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

         if(exitBars >= m_exitStageBars)
         {
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

      if(exitStage == EXIT_STAGE2)
      {
         if(newH6Bar)
            exitBars++;

         if(exitBars >= m_exitStageBars)
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

   //===========================================================
   // Process detector signals chronologically
   //===========================================================
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

public:
   //===========================================================
   // Constructor
   //===========================================================
   CH6TradeManager()
   {
      m_lots = 0.01;
      m_confirmGapBars = 2;
      m_exitStageBars = 10;
      m_profitPoints = 20;

      last_h6_bar_open = 0;
      confirmedDir = DIR_NONE;
      pendingDir = DIR_NONE;
      ZeroMemory(pendingSignal);

      exitDir = DIR_NONE;
      exitStage = EXIT_NONE;
      exitBars = 0;

      ArrayResize(processedKeys, 0);
      
      m_profitReversalMinPositions = 4;
      m_basketWasProfitable = false;
   }

   //===========================================================
   // Called by the soldiers core during initialization
   //===========================================================
   int Init(double lots = 0.01,
            int confirmGapBars = 2,
            int exitStageBars = 10,
            int profitPoints = 20)
   {
      m_lots = lots;
      m_confirmGapBars = confirmGapBars;
      m_exitStageBars = exitStageBars;
      m_profitPoints = profitPoints;

      trade.SetTypeFillingBySymbol(_Symbol);

      m_profitReversalMinPositions = 4;
      m_basketWasProfitable = false;

      if(_Symbol != "EURUSD")
         Print("WARNING: EURUSD point/pip assumptions may differ.");

      last_h6_bar_open = iTime(_Symbol, PERIOD_H6, 0);

      Print("H6 EA initialized | symbol=", _Symbol);

      return INIT_SUCCEEDED;
   }

   //===========================================================
   // Called by the soldiers core on every tick
   //===========================================================
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

      CheckProfitReversalSwitch();
      ManageExits(newH6Bar);

      if(newH6Bar)
         ProcessH6Signals();
   }
};

#endif // __H6_TRADE_MANAGER_MQH__
