#ifndef BLE_INTERACTOR_H
#define BLE_INTERACTOR_H

#include <Arduino.h>
#include "BleConfig.h"
#include "BleNotifier.h"
#include "BleWriteHandler.h"
#include "BleMessageQueue.h"
#include "BleLedController.h"
#include "BleUi.h"

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
  void handleButtonEvent(const char* buttonName, bool longPress);

 private:
  void enqueueText(const char* message, bool updateUi);
  void flushQueue();

  BleConfig _config;
  BleNotifier* _notifier;
  BleLedController* _ledController;
  BleUi* _ui;
  BleMessageQueue _queue;
  bool _connected;
  uint32_t _lastNotifyAt;
  uint32_t _tickCounter;
};

#endif
