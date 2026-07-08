//+------------------------------------------------------------------+
//|                                              BOS_M1_EA_v6_SMC.mq5|
//|                    M1 BOS SMC Strategy with True Swing Structure |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

CTrade trade;

//--- Input Parameters
input int    InpSwingLeftRight     = 3;      // SMC Strength: Bars required on left/right for a valid Swing Point
input int    InpStructureLookback = 30;     // Maximum bars back to look for a valid structural level
input int    InpTargetProfit       = 100;    // Profit threshold ($) to activate trailing protection
input int    InpTrailingStartPoints= 100;   // Profit points needed BEFORE trailing activates
input int    InpTrailingStopPoints = 100;   // Distance to follow behind price in Points
input int    InpMinBosPoints       = 30;     // Minimum points breakout confirmation over the swing line
input int    InpMaxSpreadPoints    = 50;     // Maximum allowed spread in points for entry
input int    InpMaxSlippage        = 3;      // Maximum allowed slippage in points
input bool   InpAllowHedging       = true;   // Enable simultaneous Buy and Sell positions
input int    InpMaxBuyPositions    = 1;      // Max concurrent Buy positions
input int    InpMaxSellPositions   = 1;      // Max concurrent Sell positions
input int    InpMinDistancePoints  = 200;    // Min distance in points between trades of same direction

//--- ACTIVE SYSTEM UPDATES
input uint   InpMagicNumber       = 88123;  // Magic Number to separate EA trades

//--- RISK MANAGEMENT / LOSS CONTROL
input double InpMaxEmergencyLoss  = 60.0;   // Fixed Allowed Loss ($) per trade before forced close
input int    InpMinStopLossPoints = 100;    // Absolute minimum fallback SL in points if candle structure is too tight

//--- SECURE LICENSE INPUT
input string InpActivationKey     = "1334098779969"; // TRIAL Key

datetime lastBarTime = 0;
bool     entryAllowed = true;
bool     isLicenseValid = false;
string   licenseStatusText = "Checking...";
datetime globalTrialStartTime = 0;
datetime licenseExpiryDate = 0;

//--- SECRET ENCRYPTION PIN
#define SECRET_PIN 2699

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(_Period != PERIOD_M1)
     {
      Print("Warning: This EA is optimized for the M1 Timeframe.");
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippage);
   long currentAccount = AccountInfoInteger(ACCOUNT_LOGIN);

   //--- DECRYPTION LOGIC
   if(InpActivationKey != "TRIAL" && StringLen(InpActivationKey) > 5)
     {
      double rolledKey = StringToDouble(InpActivationKey);
      double combinedData = rolledKey / SECRET_PIN;
      long extractedDate = (long)NormalizeDouble(combinedData - currentAccount, 0);
      string keyDateStr = IntegerToString(extractedDate);

      if(StringLen(keyDateStr) == 8)
        {
         int year  = (int)StringToInteger(StringSubstr(keyDateStr, 0, 4));
         int month = (int)StringToInteger(StringSubstr(keyDateStr, 4, 2));
         int day   = (int)StringToInteger(StringSubstr(keyDateStr, 6, 2));

         if(year >= 2026 && month >= 1 && month <= 12 && day >= 1 && day <= 31)
           {
            MqlDateTime mqlTime;
            mqlTime.year = year;
            mqlTime.mon  = month;
            mqlTime.day  = day;
            mqlTime.hour = 23;
            mqlTime.min  = 59;
            mqlTime.sec  = 59;

            licenseExpiryDate = StructToTime(mqlTime);
           }
        }
     }

   //--- INITIAL VALIDATION
   if(licenseExpiryDate > 0)
     {
      if(TimeCurrent() < licenseExpiryDate)
        {
         isLicenseValid = true;
         Print("Subscription Verified! Valid until: ", TimeToString(licenseExpiryDate, TIME_DATE));
        }
      else
        {
         isLicenseValid = false;
         licenseStatusText = "Sub Expired! Renew.";
         Alert("BOS EA Error: Your subscription has expired.");
         return(INIT_PARAMETERS_INCORRECT);
        }
     }
   else
     {
      string globalTrialVarName = "BOS_EA_TrialStart_" + IntegerToString(currentAccount);
      if(!GlobalVariableCheck(globalTrialVarName))
        {
         globalTrialStartTime = TimeCurrent();
         GlobalVariableSet(globalTrialVarName, (double)globalTrialStartTime);
        }
      else
        {
         globalTrialStartTime = (datetime)GlobalVariableGet(globalTrialVarName);
        }

      long elapsedSeconds = (long)TimeCurrent() - (long)globalTrialStartTime;
      long trialDurationSeconds = 3 * 24 * 60 * 60;

      if(elapsedSeconds < trialDurationSeconds)
        {
         isLicenseValid = true;
        }
      else
        {
         isLicenseValid = false;
         licenseStatusText = "Expired! Enter Key.";
         Alert("BOS EA Error: 3-Day Trial Expired!");
         return(INIT_PARAMETERS_INCORRECT);
        }
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "BOS_DB_");
  }

//+------------------------------------------------------------------+
//| Dynamic Lot Size Calculation Matrix                              |
//+------------------------------------------------------------------+
double CalculateDynamicLot()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(balance >= 200001.0)                      return 2.0;
   if(balance >= 10001.0 && balance <= 20000.0) return 1.09;
   if(balance >= 9001.0 && balance <= 10000.0) return 1.05;
   if(balance >= 8001.0 && balance <= 9000.0) return 1.00;
   if(balance >= 7001.0 && balance <= 8000.0) return 0.90;
   if(balance >= 6001.0 && balance <= 7000.0) return 0.80;
   if(balance >= 5001.0 && balance <= 6000.0) return 0.70;
   if(balance >= 3001.0 && balance <= 5000.0) return 0.60;
   if(balance >= 2501.0 && balance <= 3000.0) return 0.50;
   if(balance >= 2001.0 && balance <= 2500.0) return 0.40;
   if(balance >= 1501.0 && balance <= 2000.0) return 0.30;
   if(balance >= 1001.0 && balance <= 1500.0) return 0.20;
   if(balance >= 801.0 && balance <= 1000.0) return 0.15;
   if(balance >= 501.0  && balance <= 800.0) return 0.10;
   if(balance >= 451.0  && balance <= 500.0)  return 0.09;
   if(balance >= 401.0  && balance <= 450.0)  return 0.03;
   if(balance >= 301.0 && balance <= 400.0)  return 0.02;
   if(balance >= 1.0 && balance <= 300.0)  return 0.01;

   return 0.02;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!isLicenseValid)
     {
      UpdateDashboard(0, 0);
      return;
     }

   ManagePositions();

   int currentSpreadPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(currentSpreadPoints > InpMaxSpreadPoints)
     {
      static datetime lastSpreadMsg = 0;
      if(TimeCurrent() - lastSpreadMsg > 60)
        {
         Print("Trade skipped: Current spread (", currentSpreadPoints, ") exceeds maximum (", InpMaxSpreadPoints, ")");
         lastSpreadMsg = TimeCurrent();
        }
      return;
     }

   if(!IsNewBar()) return;

   int buyCount = 0, sellCount = 0;
   double lastBuyPrice = 0, lastSellPrice = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
              {
               buyCount++;
               lastBuyPrice = PositionGetDouble(POSITION_PRICE_OPEN);
              }
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
              {
               sellCount++;
               lastSellPrice = PositionGetDouble(POSITION_PRICE_OPEN);
              }
           }
        }
     }

   //--- SMC SWING STRUCTURE IDENTIFICATION ENGINE
   double structureHigh = 0;
   double structureLow = 0;
   datetime structureHighTime = 0;
   datetime structureLowTime = 0;

   for(int i = InpSwingLeftRight + 1; i < InpStructureLookback; i++)
     {
      bool isSwingHigh = true;
      double candidateHigh = iHigh(_Symbol, PERIOD_M1, i);

      for(int j = 1; j <= InpSwingLeftRight; j++)
        {
         if(iHigh(_Symbol, PERIOD_M1, i - j) >= candidateHigh || iHigh(_Symbol, PERIOD_M1, i + j) > candidateHigh)
           {
            isSwingHigh = false;
            break;
           }
        }
      if(isSwingHigh)
        {
         structureHigh = candidateHigh;
         structureHighTime = iTime(_Symbol, PERIOD_M1, i);
         break;
        }
     }

   for(int i = InpSwingLeftRight + 1; i < InpStructureLookback; i++)
     {
      bool isSwingLow = true;
      double candidateLow = iLow(_Symbol, PERIOD_M1, i);

      for(int j = 1; j <= InpSwingLeftRight; j++)
        {
         if(iLow(_Symbol, PERIOD_M1, i - j) <= candidateLow || iLow(_Symbol, PERIOD_M1, i + j) < candidateLow)
           {
            isSwingLow = false;
            break;
           }
        }
      if(isSwingLow)
        {
         structureLow = candidateLow;
         structureLowTime = iTime(_Symbol, PERIOD_M1, i);
         break;
        }
     }

   if(structureHigh == 0 || structureLow == 0) return;

   double lastClose = iClose(_Symbol, PERIOD_M1, 1);
   datetime currentCandleTime = iTime(_Symbol, PERIOD_M1, 1);

   if(lastClose <= structureHigh && lastClose >= structureLow)
     {
      entryAllowed = true;
     }

   int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = (stopLevel + 10) * _Point;
   double calculatedLot = CalculateDynamicLot();
   double askPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bidPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   //--- Dynamic Point Value Calculation based on Lot Size for $50 Fixed Loss
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   // Distance calculation in points for exactly $50 risk
   double fixedLossPoints = 0;
   if(tickValue > 0 && calculatedLot > 0)
     {
      fixedLossPoints = (InpMaxEmergencyLoss / (calculatedLot * tickValue)) * (tickSize / _Point);
     }
   else
     {
      fixedLossPoints = InpMinStopLossPoints; // Fallback
     }

   // Ensure SL is not too tight for live market conditions (spread + minimum buffer)
   if(fixedLossPoints < InpMinStopLossPoints + currentSpreadPoints)
     {
      fixedLossPoints = InpMinStopLossPoints + currentSpreadPoints;
     }

   //--- SMC Bullish Breakout Check (BUY)
   double bullishBreakoutDistance = lastClose - structureHigh;
   double minRequiredBullishDistance = (InpMinBosPoints + currentSpreadPoints) * _Point;

   bool buyLimitReached = (buyCount >= InpMaxBuyPositions);
   bool buyDistanceOk = (buyCount == 0 || (askPrice - lastBuyPrice >= InpMinDistancePoints * _Point));
   bool hedgeOkBuy = (sellCount == 0 || InpAllowHedging);

   if(lastClose > structureHigh && entryAllowed && !buyLimitReached && buyDistanceOk && hedgeOkBuy)
     {
      if(bullishBreakoutDistance < minRequiredBullishDistance)
        {
         static datetime lastBullishLog = 0;
         if(TimeCurrent() - lastBullishLog > 60)
           {
            Print("Bullish breakout insufficient for spread: ", DoubleToString(bullishBreakoutDistance / _Point, 0), " < Required: ", DoubleToString(minRequiredBullishDistance / _Point, 0));
            lastBullishLog = TimeCurrent();
           }
        }
      else
        {
      // Fixed $50 risk based SL
      double calculatedSL = askPrice - (fixedLossPoints * _Point);

      // Structure-based validation if you still want it to be tighter, otherwise keeps it fixed at $50
      double structureSL = iLow(_Symbol, PERIOD_M1, 1);
      if(askPrice - structureSL < fixedLossPoints * _Point && askPrice - structureSL > minDistance)
        {
         calculatedSL = structureSL; // Use candle structure if it risks LESS than $50
        }

      calculatedSL = NormalizeDouble(calculatedSL, _Digits);

         double finalLot = NormalizeVolume(calculatedLot);
         if(!trade.Buy(finalLot, _Symbol, 0, calculatedSL, 0, "SMC Bullish BOS"))
           {
            Print("Error opening SMC Bullish BOS: ", trade.ResultRetcodeDescription());
           }
         else
           {
            Print("True SMC Bullish BOS Confirmed. Lot: ", finalLot, " SL Set at: ", calculatedSL);
            DrawBOSLine("BOS_Bull_", currentCandleTime, structureHighTime, structureHigh);
            entryAllowed = false;
           }
        }
     }

   //--- SMC Bearish Breakout Check (SELL)
   double bearishBreakoutDistance = structureLow - lastClose;
   double minRequiredBearishDistance = (InpMinBosPoints + currentSpreadPoints) * _Point;

   bool sellLimitReached = (sellCount >= InpMaxSellPositions);
   bool sellDistanceOk = (sellCount == 0 || (lastSellPrice - bidPrice >= InpMinDistancePoints * _Point));
   bool hedgeOkSell = (buyCount == 0 || InpAllowHedging);

   if(lastClose < structureLow && entryAllowed && !sellLimitReached && sellDistanceOk && hedgeOkSell)
     {
      if(bearishBreakoutDistance < minRequiredBearishDistance)
        {
         static datetime lastBearishLog = 0;
         if(TimeCurrent() - lastBearishLog > 60)
           {
            Print("Bearish breakout insufficient for spread: ", DoubleToString(bearishBreakoutDistance / _Point, 0), " < Required: ", DoubleToString(minRequiredBearishDistance / _Point, 0));
            lastBearishLog = TimeCurrent();
           }
        }
      else
        {
      // Fixed $50 risk based SL
      double calculatedSL = bidPrice + (fixedLossPoints * _Point);

      // Structure check
      double structureSL = iHigh(_Symbol, PERIOD_M1, 1);
      if(structureSL - bidPrice < fixedLossPoints * _Point && structureSL - bidPrice > minDistance)
        {
         calculatedSL = structureSL; // Use candle structure if it risks LESS than $50
        }

      calculatedSL = NormalizeDouble(calculatedSL, _Digits);

         double finalLot = NormalizeVolume(calculatedLot);
         if(!trade.Sell(finalLot, _Symbol, 0, calculatedSL, 0, "SMC Bearish BOS"))
           {
            Print("Error opening SMC Bearish BOS: ", trade.ResultRetcodeDescription());
           }
         else
           {
            Print("True SMC Bearish BOS Confirmed. Lot: ", finalLot, " SL Set at: ", calculatedSL);
            DrawBOSLine("BOS_Bear_", currentCandleTime, structureLowTime, structureLow);
            entryAllowed = false;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check for a new candle arrival                                   |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
   if(lastBarTime != currentBarTime)
     {
      lastBarTime = currentBarTime;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Position Management with Dynamic Trailing & Loss Control          |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   double totalOpenSL = 0;
   double totalOpenTP = 0;
   int relevantPositions = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

         relevantPositions++;
         double current_profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         long type         = PositionGetInteger(POSITION_TYPE);
         double current_sl = PositionGetDouble(POSITION_SL);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         totalOpenTP      += PositionGetDouble(POSITION_TP);
         totalOpenSL      += current_sl;

         //--- EMERGENCY HARD LOSS PROTECTION (Account Equity Level Check)
         if(InpMaxEmergencyLoss > 0 && current_profit <= -InpMaxEmergencyLoss)
           {
            Print("Emergency Close Triggered! Trade #", ticket, " Loss reached: $", current_profit);
            trade.PositionClose(ticket);
            continue;
           }

         //--- TRAILING STOP LOSS LOGIC
         if(InpTrailingStopPoints > 0)
           {
            if(type == POSITION_TYPE_BUY)
              {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               if(bid >= open_price + (InpTrailingStartPoints * _Point) || current_profit >= InpTargetProfit)
                 {
                  double new_sl = NormalizeDouble(bid - InpTrailingStopPoints * _Point, _Digits);

                  // Respect broker SYMBOL_TRADE_STOPS_LEVEL
                  int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
                  double minDistance = (stopLevel + 2) * _Point;
                  if(bid - new_sl < minDistance) new_sl = NormalizeDouble(bid - minDistance, _Digits);

                  if(new_sl > current_sl || current_sl == 0)
                    {
                     if(!trade.PositionModify(ticket, new_sl, 0))
                       Print("Error modifying Buy SL: ", trade.ResultRetcodeDescription());
                    }
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               if(ask <= open_price - (InpTrailingStartPoints * _Point) || current_profit >= InpTargetProfit)
                 {
                  double new_sl = NormalizeDouble(ask + InpTrailingStopPoints * _Point, _Digits);

                  // Respect broker SYMBOL_TRADE_STOPS_LEVEL
                  int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
                  double minDistance = (stopLevel + 2) * _Point;
                  if(new_sl - ask < minDistance) new_sl = NormalizeDouble(ask + minDistance, _Digits);

                  if(new_sl < current_sl || current_sl == 0)
                    {
                     if(!trade.PositionModify(ticket, new_sl, 0))
                       Print("Error modifying Sell SL: ", trade.ResultRetcodeDescription());
                    }
                 }
              }
           }
        }
     }

   double avgSL = (relevantPositions > 0) ? totalOpenSL / relevantPositions : 0;
   double avgTP = (relevantPositions > 0) ? totalOpenTP / relevantPositions : 0;
   UpdateDashboard(avgSL, avgTP);
  }

//+------------------------------------------------------------------+
//| Helper function to handle chart visuals safely                   |
//+------------------------------------------------------------------+
void DrawBOSLine(string prefix, datetime currTime, datetime structTime, double price)
  {
   string lineName = prefix + TimeToString(currTime, TIME_DATE|TIME_MINUTES);
   if(ObjectCreate(0, lineName, OBJ_TREND, 0, structTime, price, currTime, price))
     {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
     }
  }

//+------------------------------------------------------------------+
//| Generates and Updates the Dashboard UI Panel on Chart            |
//+------------------------------------------------------------------+
void UpdateDashboard(double sl, double tp)
  {
   int totalOpenTrades = 0, buys = 0, sells = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         totalOpenTrades++;
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) buys++;
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) sells++;
        }
     }

   double totalProfit = 0;
   double totalLoss = 0;
   double initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(licenseExpiryDate > 0)
     {
      if(TimeCurrent() < licenseExpiryDate)
        {
         isLicenseValid = true;
         long remainingSec = licenseExpiryDate - TimeCurrent();
         long daysLeft = remainingSec / (24 * 60 * 60);
         long hoursLeft = (remainingSec % (24 * 60 * 60)) / (60 * 60);

         if(daysLeft > 0)
            licenseStatusText = "Paid Sub: " + IntegerToString(daysLeft) + "d " + IntegerToString(hoursLeft) + "h left";
         else
            licenseStatusText = "Paid Sub: " + IntegerToString(hoursLeft) + "h left";
        }
      else
        {
         isLicenseValid = false;
         licenseStatusText = "Sub Expired! Renew.";
        }
     }
   else
     {
      long elapsedSeconds = (long)TimeCurrent() - (long)globalTrialStartTime;
      long trialDurationSeconds = 3 * 24 * 60 * 60;

      if(elapsedSeconds < trialDurationSeconds)
        {
         isLicenseValid = true;
         long remainingSeconds = trialDurationSeconds - elapsedSeconds;
         long daysLeft = remainingSeconds / (24 * 60 * 60);
         long hoursLeft = (remainingSeconds % (24 * 60 * 60)) / (60 * 60);
         licenseStatusText = "Trial: " + IntegerToString(daysLeft) + "d " + IntegerToString(hoursLeft) + "h left";
        }
      else
        {
         isLicenseValid = false;
         licenseStatusText = "Expired! Enter Key.";
        }
     }

   if(HistorySelect(0, TimeCurrent()))
     {
      int deals = HistoryDealsTotal();
      bool firstDealFound = false;
      for(int i = 0; i < deals; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket > 0)
           {
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;

            long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
            if(!firstDealFound && dealType == DEAL_TYPE_BALANCE)
              {
               initialBalance = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               firstDealFound = true;
              }
            if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
            long entryMode = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entryMode == DEAL_ENTRY_OUT || entryMode == DEAL_ENTRY_INOUT)
              {
               double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
               if(profit >= 0) totalProfit += profit;
               else            totalLoss += profit;
              }
           }
        }
     }

   double netProfit = totalProfit + totalLoss;
   color netProfitColor = (netProfit >= 0) ? clrLime : clrRed;

   int startX = 15;
   int startY = 15;
   int rowHeight = 22;
   string font = "Arial";
   int fontSize = 10;
   color labelColor = clrWhite;

   CreateLabelObject("BOS_DB_BG", startX, startY, 220, 215, clrBlack, 10, font, true);
   CreateLabelObject("BOS_DB_Title", startX + 10, startY + 10, 0, 0, clrYellow, 11, font, false, "Mehdi BOT M1");

   color statusColor = (licenseStatusText == "Expired! Enter Key." || licenseStatusText == "Sub Expired! Renew.") ? clrRed : ((StringFind(licenseStatusText, "Paid") >= 0) ? clrCyan : clrOrange);
   CreateLabelObject("BOS_DB_License", startX + 10, startY + 10 + (rowHeight * 1), 0, 0, statusColor, fontSize, font, false, "Status: " + licenseStatusText);
   CreateLabelObject("BOS_DB_StartBal", startX + 10, startY + 10 + (rowHeight * 2), 0, 0, labelColor, fontSize, font, false, "Start Balance: $" + DoubleToString(initialBalance, 2));
   CreateLabelObject("BOS_DB_Open", startX + 10, startY + 10 + (rowHeight * 3), 0, 0, labelColor, fontSize, font, false, "Open (B/S): " + IntegerToString(buys) + " / " + IntegerToString(sells));
   CreateLabelObject("BOS_DB_TotalProfit", startX + 10, startY + 10 + (rowHeight * 4), 0, 0, clrLime, fontSize, font, false, "Total Profit: $" + DoubleToString(totalProfit, 2));
   CreateLabelObject("BOS_DB_TotalLoss", startX + 10, startY + 10 + (rowHeight * 5), 0, 0, clrRed, fontSize, font, false, "Total Loss: $" + DoubleToString(totalLoss, 2));
   CreateLabelObject("BOS_DB_NetProfit", startX + 10, startY + 10 + (rowHeight * 6), 0, 0, netProfitColor, fontSize, font, false, "Net Profit: $" + DoubleToString(netProfit, 2));

   string slText = (sl > 0) ? DoubleToString(sl, _Digits) : "Not Set";
   CreateLabelObject("BOS_DB_SL", startX + 10, startY + 10 + (rowHeight * 7), 0, 0, labelColor, fontSize, font, false, "Active SL: " + slText);

   string tpText = (totalOpenTrades > 0 && tp == 0) ? "Trailing Mode" : ((tp > 0) ? DoubleToString(tp, _Digits) : "None");
   CreateLabelObject("BOS_DB_TP", startX + 10, startY + 10 + (rowHeight * 8), 0, 0, labelColor, fontSize, font, false, "Active TP: " + tpText);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Volume normalization to comply with broker constraints           |
//+------------------------------------------------------------------+
double NormalizeVolume(double volume)
{
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   int digits = 0;
   if(volStep > 0) digits = (int)MathMax(0, -MathLog10(volStep));

   double normalized = MathRound(volume / volStep) * volStep;
   if(normalized < minVol) normalized = minVol;
   if(normalized > maxVol) normalized = maxVol;

   return NormalizeDouble(normalized, digits);
}

//+------------------------------------------------------------------+
//| Universal Dashboard object UI creator element                    |
//+------------------------------------------------------------------+
void CreateLabelObject(string name, int x, int y, int width, int height, color col, int size, string font, bool isBox, string text="")
  {
   if(isBox)
     {
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
         ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
         ObjectSetInteger(0, name, OBJPROP_BGCOLOR, col);
         ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_SUNKEN);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        }
     }
   else
     {
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(0, name, OBJPROP_COLOR, col);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
         ObjectSetString(0, name, OBJPROP_FONT, font);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        }
      ObjectSetString(0, name, OBJPROP_TEXT, text);
     }
  }