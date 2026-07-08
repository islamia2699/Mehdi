//+------------------------------------------------------------------+
//+                                  LockProfitTrailingEA.mq5         |
//+                                  Copyright 2026, Trading Automator|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      ""
#property version   "1.50"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Input parameters
input group "--- Strategy Settings ---"
input double   InpInitialLot        = 0.1;       // Initial Position Lot Size
input int      InpHedgeDistance     = 300;       // Distance in points to trigger opposite trade
input double   InpHedgeLotMultiplier= 1.0;       // Multiplier for opposite trade lot size

input group "--- Trailing Stop Settings ---"
input int      InpTrailingStart     = 150;       // Trailing Start (Points mein - Jab itna profit ho tab active ho)
input int      InpTrailingStop      = 50;        // Trailing Distance (Points mein - Market price se peeche)

input group "--- Dollar Risk Management ---"
input double   InpMaxLossMoney      = 20.0;      // Emergency Stop Loss in USD ($20 total account protection)
input ulong    InpMagicNumber       = 123456;    // EA Magic Number

input group "--- Live Trading Robustness ---"
input int      InpMaxSpread         = 50;        // Maximum allowed spread in points for entry
input int      InpMaxSlippage       = 3;         // Maximum allowed slippage in points

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Alert("EA Error: This EA requires a HEDGING account. Current account is NETTING.");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpMaxSlippage);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static string lastReason = "None";
   MqlTick lastTick;
   if(!SymbolInfoTick(_Symbol, lastTick))
     {
      lastReason = "Failed to get Tick";
      UpdateStatusComment(lastReason, 0, 0, 0);
      return;
     }

   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   int totalBuyPositions = 0;
   int totalSellPositions = 0;
   double firstBuyPrice = 0;
   double firstSellPrice = 0;
   double totalProfit = 0;

   bool isBuyTrailingActive = false;
   bool isSellTrailingActive = false;

   // 1. Loop through open positions to manage Trailing Stop and check if active
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         totalProfit += PositionGetDouble(POSITION_PROFIT);
         ulong  ticket    = PositionGetInteger(POSITION_TICKET);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);

         // --- BUY POSITION ---
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         {
            totalBuyPositions++;
            if(firstBuyPrice == 0) firstBuyPrice = openPrice;

            if(lastTick.bid - openPrice > InpTrailingStart * _Point)
            {
               double newSL = NormalizeDouble(lastTick.bid - (InpTrailingStop * _Point), _Digits);

               // Respect broker SYMBOL_TRADE_STOPS_LEVEL
               int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
               double minDistance = (stopLevel + 2) * _Point;
               if(lastTick.bid - newSL < minDistance) newSL = NormalizeDouble(lastTick.bid - minDistance, _Digits);

               if(currentSL < newSL)
               {
                  if(!trade.PositionModify(ticket, newSL, 0))
                    Print("Error modifying Buy SL: ", trade.ResultRetcodeDescription());
                  else
                    currentSL = newSL;
               }
            }
            // Agar SL set ho chuka hai matlab trailing active hai
            if(currentSL > 0) isBuyTrailingActive = true;
         }

         // --- SELL POSITION ---
         else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         {
            totalSellPositions++;
            if(firstSellPrice == 0) firstSellPrice = openPrice;

            if(openPrice - lastTick.ask > InpTrailingStart * _Point)
            {
               double newSL = NormalizeDouble(lastTick.ask + (InpTrailingStop * _Point), _Digits);

               // Respect broker SYMBOL_TRADE_STOPS_LEVEL
               int stopLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
               double minDistance = (stopLevel + 2) * _Point;
               if(newSL - lastTick.ask < minDistance) newSL = NormalizeDouble(lastTick.ask + minDistance, _Digits);

               if(currentSL > newSL || currentSL == 0)
               {
                  if(!trade.PositionModify(ticket, newSL, 0))
                    Print("Error modifying Sell SL: ", trade.ResultRetcodeDescription());
                  else
                    currentSL = newSL;
               }
            }
            // Agar SL set ho chuka hai matlab trailing active hai
            if(currentSL > 0) isSellTrailingActive = true;
         }
      }
   }

   // ================= NEW KILL-SWITCH LOGIC (Aap ki requirement) =================

   // Agar BUY ka trailing stop active ho gaya hai, to SELL ko usi waqt close kar do
   if(isBuyTrailingActive && totalSellPositions > 0)
   {
      Print("Buy Trailing is active. Closing opposite Sell position to let profit run.");
      ClosePositionsByType(POSITION_TYPE_SELL);
      return; // Tick yahin rok dein taake agle tick par fresh calculation ho
   }

   // Agar SELL ka trailing stop active ho gaya hai, to BUY ko usi waqt close kar do
   if(isSellTrailingActive && totalBuyPositions > 0)
   {
      Print("Sell Trailing is active. Closing opposite Buy position to let profit run.");
      ClosePositionsByType(POSITION_TYPE_BUY);
      return;
   }

   // ==============================================================================

   // ================= EMERGENCY TOTAL ACCOUNT SL CHECK =================
   if((totalBuyPositions > 0 || totalSellPositions > 0) && totalProfit <= -InpMaxLossMoney)
   {
      Print("Emergency Dollar SL reached: $", totalProfit, ". Hard close triggered.");
      CloseAllEAPositions();
      lastReason = "Emergency SL hit";
      UpdateStatusComment(lastReason, currentSpread, totalBuyPositions, totalSellPositions);
      return;
   }

   // 4. Spread Filter for NEW entries
   if(currentSpread > InpMaxSpread)
     {
      lastReason = "Spread too high (" + IntegerToString(currentSpread) + ")";
      static datetime lastSpreadLog = 0;
      if(TimeCurrent() - lastSpreadLog > 60)
        {
         Print("New trade operations skipped: Current spread (", currentSpread, ") exceeds maximum (", InpMaxSpread, ")");
         lastSpreadLog = TimeCurrent();
        }
      UpdateStatusComment(lastReason, currentSpread, totalBuyPositions, totalSellPositions);
      return;
     }

   // 5. Entry Logic
   lastReason = "Searching for signal...";
   UpdateStatusComment(lastReason, currentSpread, totalBuyPositions, totalSellPositions);

   // CASE 1: Koi trade open nahi hai -> Start Fresh
   if(totalBuyPositions == 0 && totalSellPositions == 0)
   {
      double primaryLot = NormalizeVolume(InpInitialLot);
      if(primaryLot > 0)
        {
         if(!trade.Buy(primaryLot, _Symbol, lastTick.ask, 0, 0, "Primary Buy"))
           Print("Error opening primary Buy: ", trade.ResultRetcodeDescription());
        }
      else Print("Error: Primary volume normalized to 0");
      return;
   }

   // CASE 2: Sirf BUY open hai aur market drop hui -> Open Support SELL
   if(totalBuyPositions > 0 && totalSellPositions == 0 && !isBuyTrailingActive)
   {
      if(firstBuyPrice - lastTick.bid >= InpHedgeDistance * _Point)
      {
         double hedgeLot = NormalizeVolume(InpInitialLot * InpHedgeLotMultiplier);
         if(hedgeLot > 0)
           {
            if(!trade.Sell(hedgeLot, _Symbol, lastTick.bid, 0, 0, "Support Sell"))
              Print("Error opening support Sell: ", trade.ResultRetcodeDescription());
           }
         else Print("Error: Hedge Sell volume normalized to 0");
      }
   }

   // CASE 3: Sirf SELL open hai aur market rise hui -> Open Support BUY
   if(totalSellPositions > 0 && totalBuyPositions == 0 && !isSellTrailingActive)
   {
      if(lastTick.ask - firstSellPrice >= InpHedgeDistance * _Point)
      {
         double hedgeLot = NormalizeVolume(InpInitialLot * InpHedgeLotMultiplier);
         if(hedgeLot > 0)
           {
            if(!trade.Buy(hedgeLot, _Symbol, lastTick.ask, 0, 0, "Support Buy"))
              Print("Error opening support Buy: ", trade.ResultRetcodeDescription());
           }
         else Print("Error: Hedge Buy volume normalized to 0");
      }
   }
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
   if(normalized < minVol) normalized = 0; // Skip if less than minimum allowed
   if(normalized > maxVol) normalized = maxVol;

   return NormalizeDouble(normalized, digits);
}

//+------------------------------------------------------------------+
//| Specific Type (Buy or Sell) ko close karne ka function           |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         if(PositionGetInteger(POSITION_TYPE) == posType)
         {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            trade.PositionClose(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard Status Update                                          |
//+------------------------------------------------------------------+
void UpdateStatusComment(string reason, int spread, int buys, int sells)
{
   string marginMode = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) ? "HEDGING" : "NETTING";
   string text = "--- LockProfitTrailingEA Status ---\n" +
                 "Account Type: " + marginMode + "\n" +
                 "Current Spread: " + IntegerToString(spread) + " (Max: " + IntegerToString(InpMaxSpread) + ")\n" +
                 "Open Positions: Buy: " + IntegerToString(buys) + " / Sell: " + IntegerToString(sells) + "\n" +
                 "Last Activity: " + reason;
   Comment(text);
}

//+------------------------------------------------------------------+
//| Helper function to close all positions managed by this EA        |
//+------------------------------------------------------------------+
void CloseAllEAPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         trade.PositionClose(ticket);
      }
   }
}
