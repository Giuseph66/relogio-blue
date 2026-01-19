#ifndef BLE_NOTIFIER_H
#define BLE_NOTIFIER_H

#include <Arduino.h>

class BleNotifier {
 public:
  virtual ~BleNotifier() {}
  virtual bool notify(const uint8_t* data, size_t len) = 0;
  virtual bool isConnected() const = 0;
};

#endif
