#ifndef __MA_SLOPE_TRACE_OBSERVER_MQH__
#define __MA_SLOPE_TRACE_OBSERVER_MQH__

#include "../../MovingAverages.mqh"
#include "../RainBowDynamics.mqh"

#define TRACE_BARS 4

class CMaSlopeTraceObserver
{
private:

   CMovingAverages *m;
   CRainBowDynamics *m_rainbow;

   int m_postBars;

   string m_sma7;
   string m_ema7;
   string m_sma14;
   string m_ema14;


public:

   CMaSlopeTraceObserver()
   {
      m = NULL;
      m_rainbow = NULL;

      m_postBars = 0;

      ClearTrace();
   }

   void Set(
   
      CMovingAverages &ma,
      CRainBowDynamics &qrainbow
   )
   {
      m = &ma;
      m_rainbow = &qrainbow;

      m_postBars = 0;

      ClearTrace();
   }

private:

   void ClearTrace()
   {
      m_sma7  = "";
      m_ema7  = "";
      m_sma14 = "";
      m_ema14 = "";
   }

   string Dir(double slope)
   {
      if(slope > 0)
         return "U ";

      if(slope < 0)
         return "D ";

      return "F ";
   }

   void AddCurrentBar()
   {
      double slopeSma7 = m.SMA7(1) - m.SMA7(2);

      double slopeEma7 = m.EMA7(1) - m.EMA7(2);

      double slopeSma14 = m.SMA14(1) - m.SMA14(2);

      double slopeEma14 = m.EMA14(1) - m.EMA14(2);

      m_sma7  += Dir(slopeSma7);
      m_ema7  += Dir(slopeEma7);
      m_sma14 += Dir(slopeSma14);
      m_ema14 += Dir(slopeEma14);
   }

   void PrintTrace()
   {
      Print("--------------------------------");
      Print("RAINBOW NODE EXIT TRACE");
      Print("--------------------------------");

      Print("SMA7  : ", m_sma7);
      Print("EMA7  : ", m_ema7);
      Print("SMA14 : ", m_sma14);
      Print("EMA14 : ", m_ema14);

      Print("--------------------------------");
   }

   void ConsumeWindow()
   {
      m_postBars = 0;
   }
   
   
public:

   void Update()
   {
      if(m == NULL)
         return;
      
      //----------------------------------
      // فقط آخرین کندل گره
      //----------------------------------

      if(m_rainbow.last_RAINBOW_Event == RB_EVENT_NODE_END)
      {
         ClearTrace();

         AddCurrentBar();

         m_postBars = TRACE_BARS - 1;

         return;
      }

      //----------------------------------
      // کندل های بعد از گره
      //----------------------------------

      if(m_postBars > 0)
      {
         AddCurrentBar();

         m_postBars--;

         if(m_postBars == 0)
         {
            PrintTrace();

            ClearTrace();
         }
      }
   }


   bool WaitingWindowActive()
   {
      return (m_postBars > 0);
   }

   bool AllUp()
   {
      if(m == NULL)
         return false;
   
      if(!(m_postBars > 0))
         return false;
   
   
      double s1 = m.SMA7(1)  - m.SMA7(2);
      double s2 = m.EMA7(1)  - m.EMA7(2);
      double s3 = m.SMA14(1) - m.SMA14(2);
      double s4 = m.EMA14(1) - m.EMA14(2);
   
   
      bool trig =
         (s1 > 0)
         &&
         (s2 > 0)
         &&
         (s3 > 0)
         &&
         (s4 > 0);
   
   
      if(trig)
      {
         ConsumeWindow();
         return true;
      }
   
   
      return false;
   }

   bool AllDown()
   {
      if(m == NULL)
         return false;
         
      if(! (m_postBars > 0) )
         return false;         

      double s1 = m.SMA7(1)  - m.SMA7(2);
      double s2 = m.EMA7(1)  - m.EMA7(2);
      double s3 = m.SMA14(1) - m.SMA14(2);
      double s4 = m.EMA14(1) - m.EMA14(2);

      bool trig = 
         (s1 < 0)
         &&
         (s2 < 0)
         &&
         (s3 < 0)
         &&
         (s4 < 0);
         
      if(trig){
         ConsumeWindow();
         return true ;
      }
      else
         return false;
   }
   

   
};

#endif
