#ifndef __RAINBOW_DYNAMICS_MQH__
#define __RAINBOW_DYNAMICS_MQH__

#include "../Common.mqh"
#include "../MovingAverages.mqh"
#include "../SimpleLogger.mqh"

#define MAX_RB_NODES_HISTORY 100

struct RainbowNodeRecord
{
   datetime StartTime;
   datetime EndTime;

   double High;
   double Low;

   int DurationCandles;
};



enum ENUM_RAINBOW_EVENT
{
   RB_EVENT_NONE = 0,

   RB_EVENT_NODE_BEGIN,
   RB_EVENT_NODE_UPDATE,
   RB_EVENT_NODE_END
};

enum ENUM_INERTIA_EVENT
{
   INERTIA_EVENT_NONE = 0,

   INERTIA_EVENT_HIGH_ADDED,
   INERTIA_EVENT_LOW_ADDED
};


class CRainBowDynamics
{

private:

   CMovingAverages *ma;
   CSimpleLogger   *gg;
   RainbowNodeRecord m_history[MAX_RB_NODES_HISTORY];
   int hCount;
   
public:
   ENUM_RAINBOW_EVENT last_RAINBOW_Event;   
   

private:   
   ENUM_INERTIA_EVENT last_INERTIA_Event;
   RainbowNode g_node;
   
   double prevInertia;
   double phigh_old, plow_old;
   datetime thigh_old, tlow_old;
   bool firstHigh, firstLow;
   string nameLOW, nameHIGH;
   

   
public:
  
   void Set(CMovingAverages &_ma, CSimpleLogger &_gg)
   {
      ma = &_ma;
      gg = &_gg;
      
      prevInertia = 0;
      firstHigh = true ;
      firstLow = true ;
      rb_nodesCount = 0;
      rb_cpointsCount = 0;
      last_RAINBOW_Event = RB_EVENT_NONE;
      last_INERTIA_Event = INERTIA_EVENT_NONE;
      hCount = 0;
      
   }
   

public:

   //------------------------
   // Getter
   //------------------------
   string GetSnapshot()
   {
      string s="RAINBOW: ";
   
      if(g_node.active)
      {
         s += "NODE ACTIVE ";
   
         s += "High=";
         s += DoubleToString(g_node.high,5);
   
         s += " Low=";
         s += DoubleToString(g_node.low,5);
      }
      else
      {
         s += "NONE";
      }
   
   
      return s;
   }


   int HistoryTotal() const
   {
      return hCount;
   }

   RainbowNodeRecord GetHistory(int index) const
   {
      return m_history[index];
   }


   bool GetLastHighLine(RiverLine &outLine)
   {
      return GetLastInertiaLine(true,0,outLine);
   }


   bool GetLastLowLine(RiverLine &outLine)
   {
      return GetLastInertiaLine(false,0,outLine);
   }
   
   ENUM_RAINBOW_EVENT GetLastRainbowEvent()
   {
      return last_RAINBOW_Event;
   }
   
   ENUM_INERTIA_EVENT GetLastInertiaEvent()
   {
      return last_INERTIA_Event;
   }
   
   void Inertia_Event_Consumed()
   {
      last_INERTIA_Event = INERTIA_EVENT_NONE;
   }
   
   
   bool IsNewHighPoint()
   {
      return
         last_INERTIA_Event
         ==
         INERTIA_EVENT_HIGH_ADDED;
   }

   bool IsNewLowPoint()
   {
      return
         last_INERTIA_Event
         ==
         INERTIA_EVENT_LOW_ADDED;
   }
   
   InertiaPoint Get_Last_Inertia_Point()
   {
      return rb_CanalPoints[0];
   }
   
   
   
private: 

   double Max4( double a , double b, double c, double d ){
      double max = MathMax(a,b);
             max = MathMax(max,c);
      return MathMax(max,d);    
   }
   
   double Min4( double a , double b, double c, double d ){
      double min = MathMin(a,b);
             min = MathMin(min,c);
      return MathMin(min,d);    
   }
   
   
   void AddNode( RainbowNode &n )
   {
   
      ShiftRight(rb_nodes, MAX_RB_NODES);
         
      rb_nodes[0].startTime   = n.startTime;   
      rb_nodes[0].endTime     = n.endTime;   
      rb_nodes[0].high        = n.high;   
      rb_nodes[0].low         = n.low;
      rb_nodes[0].active      = false;
      
      if(rb_nodesCount < MAX_RB_NODES)
         rb_nodesCount++;
   }
   
   void Add_CPoint( datetime t, double p, bool highPoint )
   {
   
   
      ShiftRight(rb_CanalPoints, MAX_INERTIA_POINTS);
   
      rb_CanalPoints[0].time = t;
      rb_CanalPoints[0].price = p;
      rb_CanalPoints[0].highPoint = highPoint;
   
      if(rb_cpointsCount < MAX_INERTIA_POINTS)
         rb_cpointsCount++;
   }

public:

   void SaveNodeRecord(RainbowNode &n)
   {

      //ShiftRight
      for(int i = MAX_RB_NODES_HISTORY-1 ; i > 0 ; i--)
         m_history[i] = m_history[i-1];
      
      m_history[0].StartTime = n.startTime;
      m_history[0].EndTime   = n.endTime;
   
      m_history[0].High      = n.high;
      m_history[0].Low       = n.low;
   
      m_history[0].DurationCandles = Bars(_Symbol,_Period,n.startTime,n.endTime);
      
      if(hCount < MAX_RB_NODES_HISTORY)
         hCount ++ ;
         
   }

   bool GetInertiaCanalPoint( bool highPoint, int shift, InertiaPoint &outPoint )
   {
      int found = 0;
   
      for(int i=0; i<rb_cpointsCount; i++)
      {
         if(rb_CanalPoints[i].highPoint == highPoint)
         {
            if(found == shift)
            {
               outPoint = rb_CanalPoints[i];
               return true;
            }
   
            found++;
         }
      }
   
      return false;
   }
   
   bool LevelFound(bool highPoint, int count, double maxSpreadPoints )
   {
      if(count < 2)
         return false;
   
      double center = 0;
   
      InertiaPoint p[];
   
      ArrayResize(p,count);
   
      for(int i=0;i<count;i++)
      {
         if(!GetInertiaCanalPoint(highPoint,i,p[i]))
            return false;
   
         center += p[i].price;
      }
   
      center /= count;
   
      double q = 0;
   
      for(int i=0;i<count;i++)
      {
         double d = p[i].price - center;
         q += d*d;
      }
   
      double spread =
         MathSqrt(q) / _Point / 10.0;
   
      return (spread < maxSpreadPoints);
   }
   


   bool GetLastInertiaLine( bool highLine, int shift, RiverLine &outLine )
   {
      InertiaPoint pts[2];
   
      int wanted1 = shift;
      int wanted2 = shift + 1;
   
      int counter = 0;
   
      bool got1 = false;
      bool got2 = false;
   
      for(int i=0; i<rb_cpointsCount; i++)
      {
         if(rb_CanalPoints[i].highPoint != highLine)
            continue;
   
         if(counter == wanted1)
         {
            pts[0] = rb_CanalPoints[i];
            got1 = true;
         }
   
         if(counter == wanted2)
         {
            pts[1] = rb_CanalPoints[i];
            got2 = true;
            break;
         }
   
         counter++;
      }
   
      if(!got1 || !got2)
         return false;
   
      outLine.t1 = pts[1].time;
      outLine.t2 = pts[0].time;
   
      outLine.p1 = pts[1].price;
      outLine.p2 = pts[0].price;
   
      outLine.nameTag =
         highLine
         ?
         "RB_HIGH"
         :
         "RB_LOW";
   
      return true;
   }
   
public:  
 
   void UpdateNode()
   {
   
      last_RAINBOW_Event = RB_EVENT_NONE;

      
      bool disorder = IsDisordered( ma.SMA7(), ma.EMA7(), ma.SMA14(), ma.EMA14() );
   
      //----------------------------------
      // شروع گره
      //----------------------------------
   
      if(disorder && !g_node.active)
      {
         g_node.active = true;
         g_node.startTime = iTime(_Symbol,_Period,1);
         g_node.high = Max4( ma.SMA7(), ma.SMA14(), ma.EMA14(), ma.EMA7() );
         g_node.low  = Min4( ma.SMA7(), ma.SMA14(), ma.EMA14(), ma.EMA7() );
         
         
         last_RAINBOW_Event = RB_EVENT_NODE_BEGIN;
      }
   
      //----------------------------------
      // ادامه گره
      //----------------------------------
   
      if(disorder && g_node.active)
      {
         double mx = Max4( ma.SMA7(), ma.SMA14(), ma.EMA14(), ma.EMA7() );
         double nx  = Min4( ma.SMA7(), ma.SMA14(), ma.EMA14(), ma.EMA7() );         
         g_node.high = MathMax( g_node.high, mx );
         g_node.low  = MathMin( g_node.low , nx );
         
         if(last_RAINBOW_Event == RB_EVENT_NONE)
            last_RAINBOW_Event = RB_EVENT_NODE_UPDATE;
      }
   
      //----------------------------------
      // پایان گره و رسم آن بر روی چارت
      //----------------------------------
   
      if(!disorder && g_node.active)
      {
         g_node.active = false;
         g_node.endTime = iTime(_Symbol,_Period,1); 
         AddNode(g_node);
         
         last_RAINBOW_Event = RB_EVENT_NODE_END;
         
         //Uncertainty
         SaveNodeRecord(g_node);
          
         if(DEBUG_RAIN_BOW_DYNAMICS) DrawNodeBox(g_node);
      }
   }

private:

   bool ghjk()
   {
   
      RiverLine Out;
      if( GetLastInertiaLine(true, 0, Out) )
      {
         double p  = PriceAt(Out, 1);
         double q  = Slope( Out.t1, Out.p1, Out.t2, Out.p2 );
         return true;
         
      }else
         return false;
      
   }
   
   bool IsDisordered( double sma7, double ema7, double sma14, double ema14 )
   {
      double fastMax = MathMax(sma7,ema7);
   
      double fastMin = MathMin(sma7,ema7);
   
      double slowMax = MathMax(sma14,ema14);
   
      double slowMin = MathMin(sma14,ema14);
   
      //
      // اگر یک 14 وارد قلمرو 7 ها شد
      // یا برعکس
      //
   
      if(slowMax > fastMax)
      {   
         if(slowMin > fastMax)
            return false;
         else
            return true;
      }      
      else
      if(slowMax < fastMax)
      {
         if(slowMax < fastMin)
            return false;
         else
            return true;
      }  
      else 
         return true;
   } 

   void DrawNodeBox( RainbowNode &n )
   {
      string name = "NODE_" + IntegerToString( (int)n.startTime );   
      ObjectCreate    (0, name, OBJ_RECTANGLE, 0, n.startTime, n.high, n.endTime, n.low );
      ObjectSetInteger(0, name, OBJPROP_COLOR,clrYellow);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,2);
      ObjectSetInteger(0, name, OBJPROP_FILL,true); 
      ObjectSetInteger(0, name, OBJPROP_BACK, true );
   }
  


   double RainbowCenter(int s)
   {
      double sum = 0.0;
      
      sum += ma.EMA14(s);
      sum += ma.SMA14(s);
      sum += ma.EMA7(s);
      sum += ma.SMA7(s);
      
      return sum / 4.0 ;
      
   }
   
   double RainbowInertia(int s)
   {
      double center  = RainbowCenter(s);
      
      double inertia = 0;
      
      double d = (ma.EMA14(s)-center) / _Point / 10.0 ;
      inertia += d*d;
             d = (ma.EMA7(s)-center) / _Point / 10.0 ;
      inertia += d*d;
             d = (ma.SMA14(s)-center) / _Point / 10.0 ;
      inertia += d*d;      
             d = (ma.SMA7(s)-center) / _Point / 10.0 ;
      inertia += d*d;  
      
      return inertia;    
   }
   
public: 

   

   void PreView()
   {
      
      double d1 = RainbowInertia(1) - RainbowInertia(2);   
      double d2 = RainbowInertia(2) - RainbowInertia(3);
      
      last_INERTIA_Event = INERTIA_EVENT_NONE;
   
      if(d1 * d2 < 0)
      {
         datetime t = iTime(_Symbol,_Period,2);
   
         double p;
         string name;
   
         if(d1 > 0.0)
         {
            p = iHigh(_Symbol,_Period,2)
                +
                150 * _Point;
            
            Add_CPoint( t, p, true ); //High point
            
            name = "RB_HIGH_" + IntegerToString((int)t);
            last_INERTIA_Event = INERTIA_EVENT_HIGH_ADDED; 
            gg.Log("RB_LINE",name);
            
               
            if(firstHigh){
            
               thigh_old = t;
               phigh_old = p;            
               nameHIGH = name ;
               firstHigh = false ;
            }
            else{
               if(DEBUG_RAIN_BOW_DYNAMICS) {
                  ObjectCreate( 0, name+"_2", OBJ_ELLIPSE ,0, thigh_old, phigh_old, t, p );
                  ObjectSetInteger(0,name+"_2",OBJPROP_COLOR,clrGreen);
                  ObjectSetInteger(0,name+"_2",OBJPROP_WIDTH,2);
                  ObjectCreate( 0, name, OBJ_TREND, 0, thigh_old, phigh_old, t, p );
                  ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhiteSmoke);
                  ObjectSetInteger(0,name,OBJPROP_WIDTH,2); 
                  ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true);
                  ObjectSetInteger(0,nameHIGH,OBJPROP_RAY_RIGHT,false);
               }  
               
                     
               thigh_old = t;
               phigh_old = p;
               nameHIGH = name ;
            }
         }
         else
         if(d1 < 0.0)
         {
            p = iLow(_Symbol,_Period,2)
                -
                150 * _Point;
   
            Add_CPoint( t, p, false ); //low point
            
            name = "RB_LOW_" + IntegerToString((int)t);
            last_INERTIA_Event = INERTIA_EVENT_LOW_ADDED; 
            gg.Log("RB_LINE",name);   
              
            if(firstLow){
            
               tlow_old = t;
               plow_old = p;  
               nameLOW  = name;          
               
               firstLow = false ;
            }               
            else
            {
               if(DEBUG_RAIN_BOW_DYNAMICS) {
                  ObjectCreate( 0, name+"_1", OBJ_ELLIPSE,0,tlow_old, plow_old,t,p);
                  ObjectSetInteger(0,name+"_1",OBJPROP_COLOR,clrRed);
                  ObjectSetInteger(0,name+"_1",OBJPROP_WIDTH,2);
                  ObjectCreate( 0, name, OBJ_TREND, 0, tlow_old, plow_old, t, p );
                  ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhiteSmoke);
                  ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
                  ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,true);  
                  ObjectSetInteger(0,nameLOW ,OBJPROP_RAY_RIGHT,false);   
               }
               tlow_old = t;
               plow_old = p;  
               nameLOW = name ;           
            
            }
         }
      }
      //else
      //gg.Log("=====No New====");
   } 
   

   
   
};

#endif 
