#ifndef __META_SLOPE_ANALYZER_MQH__
#define __META_SLOPE_ANALYZER_MQH__

#include "MaSlopeTraceObserver.mqh"


class CMetaSlopeAnalyzer
{

private:

   CMaSlopeTraceObserver *slopeTrace;


   bool m_hasSignal;

   bool m_bullSignal;

   bool m_bearSignal;



public:


   CMetaSlopeAnalyzer()
   {
      slopeTrace = NULL;

      ResetSignal();
   }



   void Set(CMaSlopeTraceObserver &_slopeTrace)
   {
      slopeTrace = &_slopeTrace;

      ResetSignal();
   }



   void Update()
   {

      if(slopeTrace == NULL)
         return;


      // سیگنال قبلی هنوز مصرف نشده
      if(m_hasSignal)
         return;


      if(slopeTrace.AllUp())
      {
         m_hasSignal  = true;
         m_bullSignal = true;
         m_bearSignal = false;

         Print("BUY SIGNAL");

         return;
      }



      if(slopeTrace.AllDown())
      {
         m_hasSignal  = true;
         m_bullSignal = false;
         m_bearSignal = true;

         Print("SELL SIGNAL");

         return;
      }

   }



   bool HasSignal()
   {
      return m_hasSignal;
   }



   bool IsBullSignal()
   {
      return m_hasSignal && m_bullSignal;
   }



   bool IsBearSignal()
   {
      return m_hasSignal && m_bearSignal;
   }




   void ResetSignal()
   {
      m_hasSignal  = false;
      m_bullSignal = false;
      m_bearSignal = false;
   }



   int Trigger()
   {

      if(!m_hasSignal)
         return 0;


      int act = 0;


      if(m_bullSignal)
         act = 1;


      if(m_bearSignal)
         act = -1;


      ResetSignal();


      return act;
   }


};


#endif
