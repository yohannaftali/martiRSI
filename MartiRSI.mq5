//+---------------------------------------------------------------------------+
//|                                                    BTC Long Martingle RSI |
//|                                             Copyright 2024, Yohan Naftali |
//+---------------------------------------------------------------------------+
#property copyright "Copyright 2024, Yohan Naftali"
#property link      "https://github.com/yohannaftali"
#property version   "240.309"

// CTrade
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade trade;
CDealInfo deal;
COrderInfo order;
CPositionInfo position;
CAccountInfo account;

// Input
input group "Risk Management";
input double baseVolume = 0.01;       // Base Volume Size (Lot)
input double multiplierVolume = 1.6;  // Size Multiplier
input int maximumStep = 15;           // Maximum Step

input group "Take Profit";
input double targetProfit = 50;     // Target Profit USD/lot

input group "Deal Start / Top Up Condition";
input double rsiOversold = 25;      // RSI M1 Oversold Threshold than
input double deviationStep = 0.01;  // Minimum Price Deviation Step (%)
input double multiplierStep = 1.2;  // Step Multipiler

// Variables
int rsiHandle;
const int MAX_TIME_DELAY = 300;
int currentStep = 0;
double minimumAskPrice = 0;
double nextOpenVolume = 0;
double takeProfitPrice = 0;
int historyLast = 0;
int positionLast = 0;
bool wait = false;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit() {
  datetime current = TimeCurrent();
  datetime server = TimeTradeServer();
  datetime gmt = TimeGMT();
  datetime local = TimeLocal();

  Print("# Time Info");
  Print("- Current Time: " + TimeToString(current));
  Print("- Server Time: " + TimeToString(server));
  Print("- GMT Time: " + TimeToString(gmt));
  Print("- Local Time: " + TimeToString(local));

  Print("# Risk Management Info");
  Print("- Base Order Size: " + DoubleToString(baseVolume, 2) + " lot");
  Print("- Order Size Multiplier: " + DoubleToString(multiplierVolume, 2));
  Print("- Maximum Step: " + IntegerToString(maximumStep));
  Print("- Maximum Volume:" + DoubleToString(maximumVolume(), 2) + " lot");

  calculatePosition();
  rsiHandle = iRSI(_Symbol, PERIOD_M1, 7, PRICE_CLOSE);
  if(rsiHandle == INVALID_HANDLE) {
    Print("Invalid RSI, error: ",_LastError);
  }
  return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick() {
  if(wait) return;
  // Exit if current step over than safety order count
  if(currentStep >= maximumStep) return;

  // If current step > 0
  if(currentStep > 0) {
    // Exit if current ask Price is greater than minimum ask Price
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    if(ask > minimumAskPrice) return;
  }

  // Exit if RSI is greater than lower RSI Oversold threshold
  double currentRsi = getRsiValue();
  if(currentRsi > rsiOversold) return;
  Print("* RSI oversold detected");

  // Open New trade
  string msg = "Buy step #" + IntegerToString(currentStep+1);
  bool buy = trade.Buy(nextOpenVolume, Symbol(), 0.0, 0.0, 0.0, msg);
  if(!buy) {
    Print(trade.ResultComment());
    return;
  }

  // Recalculate position
  calculatePosition();

  // Adjust Take Profit
  adjustTakeProfit();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade() {
  int pos = PositionsTotal();
  if(positionLast == pos) return;
  positionLast = pos;
  if(pos > 0) return;
  Print("# Recalculate Position");
  calculatePosition();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {

}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
  Comment("");
  if(rsiHandle != INVALID_HANDLE)
    IndicatorRelease(rsiHandle);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double getRsiValue() {
  double bufferRsi[];
  ArrayResize(bufferRsi, 1);
  CopyBuffer(rsiHandle, 0, 0, 1, bufferRsi);
  ArraySetAsSeries(bufferRsi, true);
  return bufferRsi[0];
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void calculatePosition() {
  wait = true;
  double sumVolume = 0;
  double sumProfit = 0;
  double sumVolumePrice = 0;

  Print("# Position Info");
  Print("- Total Position: " + IntegerToString(PositionsTotal()));
  // Reset Current Step
  currentStep = 0;
  for(int i = 0; i < PositionsTotal(); i++) {
    bool isSelected = position.SelectByIndex(i);
    if(!isSelected) continue;
    ulong ticket = position.Ticket();
    double currentStopLoss = position.StopLoss();
    double currentTakeProfit = position.TakeProfit();
    double volume = position.Volume();
    sumVolume += volume;
    double price = position.PriceOpen();
    double volumePrice = volume * price;
    sumVolumePrice += volumePrice;
    double profit = position.Profit();
    sumProfit += profit;
    currentStep++;
  }

  // Calculate Next open volume
  nextOpenVolume = currentStep < maximumStep ? NormalizeDouble( baseVolume + (baseVolume * currentStep * multiplierVolume), Digits()) : 0.0;

  if(sumVolume <= 0) {
    Print("- No Position");
    minimumAskPrice = 0.0;
    takeProfitPrice = 0.0;
    return;
  }

  double averagePrice = sumVolume > 0 ? sumVolumePrice/sumVolume : 0;
  double minimumDistancePercentage = (deviationStep + ((currentStep-1) * deviationStep * multiplierStep));
  double minimumDistancePrice = averagePrice * minimumDistancePercentage / 100;
  minimumAskPrice = NormalizeDouble(averagePrice - minimumDistancePrice, Digits());
  double profit = targetProfit*sumVolume;
  takeProfitPrice = averagePrice + profit;
  wait = false;
  Print("- Current Step: " + IntegerToString(currentStep));
  Print("- Sum Volume: " + DoubleToString(sumVolume, 2));
  Print("- Sum (Volume x Price): " + DoubleToString(sumVolumePrice, 2));
  Print("- Average Price: " + DoubleToString(averagePrice, 2));
  Print("- Sum Profit: " + DoubleToString(sumProfit, 2));
  Print("- Minimum Distance to Open New Trade: " + DoubleToString(minimumDistancePercentage, 2) + "% = " + DoubleToString(minimumDistancePrice, 2) );
  Print("- Minimum Ask Price to Open New Trade: " + DoubleToString(minimumAskPrice, 2));
  Print("- Next Open Volume: " + DoubleToString(nextOpenVolume, 2) + " lot");
  Print("- Take Profit Price: " + DoubleToString(takeProfitPrice, 2));
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void adjustTakeProfit() {
  wait = true;
  for(int i = 0; i < PositionsTotal(); i++) {
    bool isSelected = position.SelectByIndex(i);
    if(!isSelected) continue;
    ulong ticket = position.Ticket();
    trade.PositionModify(ticket, 0.0, takeProfitPrice);
  }
  wait = false;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double maximumVolume() {
  double totalVolume = 0;
  for(int i = 0; i < maximumStep; i++) {
    double volume = baseVolume * (i * multiplierVolume);
    totalVolume += volume;
  }
  return totalVolume;
}
