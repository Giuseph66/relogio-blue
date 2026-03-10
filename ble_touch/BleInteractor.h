#ifndef BLE_INTERACTOR_H
#define BLE_INTERACTOR_H

#include <Arduino.h>
#include "BleConfig.h"
#include "BleLedController.h"
#include "BleMessageQueue.h"
#include "BleNotifier.h"
#include "BleUi.h"
#include "BleWriteHandler.h"

class BleInteractor : public BleWriteHandler {
 public:
  BleInteractor(
      const BleConfig& config,
      BleNotifier* notifier,
      BleLedController* ledController,
      BleUi* ui);

  void onWrite(const uint8_t* data, size_t len) override;
  void onConnectionChanged(bool connected) override;
  void tick();
  void handleLocalCommand(const char* command);

 private:
  void processText(char* message, bool fromBle);
  bool handleAnswer(const char* message);
  bool handleStructuredQuestion(char* message);
  void clearActiveQuestion();
  void enqueueText(const char* message, bool updateUi);
  void flushQueue();

  BleConfig config_;
  BleNotifier* notifier_;
  BleLedController* ledController_;
  BleUi* ui_;
  BleMessageQueue queue_;
  bool connected_;
  uint32_t lastNotifyAt_;
  uint32_t tickCounter_;
  bool awaitingAnswer_;
  bool awaitingStructuredAnswer_;
  uint32_t questionStartTime_;
  char activeQuestionId_[24];
  char activeOptionIds_[4][20];
  char activeOptionLabels_[4][20];
  uint8_t activeOptionCount_;
};

#endif
