#ifndef __FRACTAL_GEOMETRY_MQH__
#define __FRACTAL_GEOMETRY_MQH__


#define  MAX_BOXES  1000

#include "../Common.mqh"
#include "../Structure.mqh"
#include "../MovingAverages.mqh"

int Event_sBOX = 0 ;
//=========================================================
// FLAT ZONE
//=========================================================
struct FlatZone
{
   datetime startTime;
   datetime endTime;

   double   highPrice;
   double   lowPrice;

   int      startShift;
   int      endShift;

   int      windowSize;
   double   maxDistance;

   bool     ema7Inside;
   bool     ema14Inside;

   bool     sma7Inside;
   bool     sma14Inside;
};

//=========================================================
// FRACTAL GEOMETRY
//=========================================================
class CFractalGeometry
{
private:

   CStructure *stc;
   CMovingAverages *ma;
   
   Pivot merged[];
   int   qm;

   FlatZone m_smallBoxes[];
   FlatZone m_largeBoxes[];
   
public:

   //------------------------------------------------------
   // Setup
   //------------------------------------------------------
   void Set(CStructure &_stc, CMovingAverages &_ma)
   {
      stc = &_stc;
      ma  = &_ma;
   }
private:

   //------------------------------------------------------
   // Collect Fractals
   //------------------------------------------------------
   void GetFractalWindow(int N)
   {
      ArrayResize(merged,0);
      int bars = stc.FractalBars();
      //Print("~~~~~~~~~~~~~~~Bars: ", bars);
      
      for(int i=N;i>=3;i--)
      {
      
         if(i > bars) continue;
         if(i > 300 ) continue;
         
         double fu = stc.FractalUP(i);
         double fd = stc.FractalDOWN(i);

         if(fu != EMPTY_VALUE && fu > 0.0 && fu < 22.0)
         {

            //Print("We are passing UP at: ", i);
            //Print(fu);
            
            int pos = ArraySize(merged);
            ArrayResize(merged,pos+1);
            
            merged[pos].price = fu;
            merged[pos].time  = iTime(_Symbol,_Period,i);
            merged[pos].shift = i;
            merged[pos].type  = 1;
         }

         if(fd != EMPTY_VALUE && fd > 0.0 && fd < 22.0)
         {
         
            //Print("We are passing DOWN at: ", i);
            //Print(fd);
            
            int pos = ArraySize(merged);
            ArrayResize(merged,pos+1);
            
            
            merged[pos].price = fd;
            merged[pos].time  = iTime(_Symbol,_Period,i);
            merged[pos].shift = i;
            merged[pos].type  = -1;
         }
      }

      qm = ArraySize(merged);
   }

   //------------------------------------------------------
   // Find Flat Zones
   //------------------------------------------------------
   void FindFlatZones(
      int window,
      double maxDistance,
      FlatZone &result[],
      int type
   )
   {
      
      
      if(qm < window)
         return;
      
      
      for(int s=0; s<=qm-window; s++)
      {
         double highest = merged[s].price;
         double lowest  = merged[s].price;

         for(int i=s+1; i<s+window; i++)
         {
            if(merged[i].price > highest)
               highest = merged[i].price;

            if(merged[i].price < lowest)
               lowest = merged[i].price;
         }

         double range = highest - lowest;

         if(range <= maxDistance)
         {
            FlatZone box;

            box.startTime  = merged[s].time;
            box.endTime    = merged[s+window-1].time;

            box.highPrice  = highest;
            box.lowPrice   = lowest;

            box.startShift = merged[s].shift;
            box.endShift   = merged[s+window-1].shift;

            box.windowSize = window;
            box.maxDistance = maxDistance;
            
            
            //Print("We are Passing EMA at ", s);
            box.ema7Inside  = (ma.EMA7 (box.endShift)<box.highPrice && ma.EMA7 (box.endShift)>box.lowPrice);
            box.ema14Inside = (ma.EMA14(box.endShift)<box.highPrice && ma.EMA14(box.endShift)>box.lowPrice);
            box.sma7Inside  = (ma.SMA7 (box.endShift)<box.highPrice && ma.SMA7 (box.endShift)>box.lowPrice);
            box.sma14Inside = (ma.SMA14(box.endShift)<box.highPrice && ma.SMA14(box.endShift)>box.lowPrice);


            AddBox(result, box, type);
         }
      }
   }



   //====================================================
   // FlatZone Exists ?
   //====================================================
   bool ExistsInArray(FlatZone &arr[], const FlatZone &box)
   {
      int n = ArraySize(arr);
   
      for(int i=0; i<n; i++)
      {
         if(arr[i].startTime == box.startTime &&
            arr[i].endTime   == box.endTime   &&
            arr[i].windowSize == box.windowSize)
         {
            return true;
         }
      }
   
      return false;
   }
   
   
   //====================================================
   // Add Box to Result
   //====================================================

   
   void AddBox(FlatZone &result[], const FlatZone &box, int type)
   {
      if(ExistsInArray(result, box))
         return;
   
       
      if(type == 1) //if(m_smallBoxes)
         Event_sBOX = 1 ;
      
      int n = ArraySize(result);
   
      ArrayResize(result,n+1);
   
      for(int i=n; i>0; i--)
         result[i] = result[i-1];
   
      result[0] = box;
   
      Trim(result);
   }
   
   
   
   
   
   //====================================================
   // Trim
   //====================================================
   
   void Trim(FlatZone &result[])
   {
      int n = ArraySize(result);
   
      if(n > MAX_BOXES)
         ArrayResize(result,MAX_BOXES);
   }





public:

   //------------------------------------------------------
   // Getter
   //------------------------------------------------------
   void Consume_sEvent()
   {
      Event_sBOX = 0 ;
   }
   
   int get_sEvent()
   {
      return Event_sBOX ;
   }
   
   //------------------------------------------------------
   // Build
   //------------------------------------------------------
   void Build()
   {
      GetFractalWindow(300);

      FindFlatZones(4,0.0030,m_smallBoxes,1);
      FindFlatZones(6,0.0080,m_largeBoxes,2);
   }

   //------------------------------------------------------
   // Small Boxes
   //------------------------------------------------------
   int SmallBoxCount()
   {
      return ArraySize(m_smallBoxes);
   }

   bool GetSmallBox(int index, FlatZone &box)
   {
      if(index < 0 || index >= ArraySize(m_smallBoxes))
         return false;

      box = m_smallBoxes[index];
      return true;
   }

   //------------------------------------------------------
   // Large Boxes
   //------------------------------------------------------
   int LargeBoxCount()
   {
      return ArraySize(m_largeBoxes);
   }

   bool GetLargeBox(int index, FlatZone &box)
   {
      if(index < 0 || index >= ArraySize(m_largeBoxes))
         return false;

      box = m_largeBoxes[index];
      return true;
   }

   //------------------------------------------------------
   // Optional Debug Draw
   //------------------------------------------------------
   void DrawBoxes()
   {
      FlatZone box;

      //for(int i=0;i<ArraySize(m_smallBoxes);i++)
      {
         int i = 0;
         
         box = m_smallBoxes[i];

         string name =
            "SMALL_BOX_" +
            IntegerToString(iTime(_Symbol,PERIOD_H1,0) );

         ObjectDelete(0,name);

         ObjectCreate(
            0,
            name,
            OBJ_RECTANGLE,
            0,
            box.startTime,
            box.highPrice,
            box.endTime,
            box.lowPrice
         );

         ObjectSetInteger(
            0,
            name,
            OBJPROP_COLOR,
            clrWhiteSmoke
         );

         ObjectSetInteger(
            0,
            name,
            OBJPROP_WIDTH,
            10
         );

         ObjectSetInteger(
            0,
            name,
            OBJPROP_BACK,
            true
         );
      }
      /*
      for(int i=0;i<ArraySize(m_largeBoxes);i++)
      {
         box = m_largeBoxes[i];

         string name = "LARGE_BOX_"+ IntegerToString(i);

         ObjectDelete(0,name);

         ObjectCreate(
            0,
            name,
            OBJ_RECTANGLE,
            0,
            box.startTime,
            box.highPrice,
            box.endTime,
            box.lowPrice
         );

         ObjectSetInteger(
            0,
            name,
            OBJPROP_COLOR,
            clrTomato
         );

         ObjectSetInteger(
            0,
            name,
            OBJPROP_WIDTH,
            3
         );

         ObjectSetInteger(
            0,
            name,
            OBJPROP_BACK,
            true
         );
      }
   
   
   
   */
   }
};

#endif
