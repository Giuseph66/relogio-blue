#ifndef BLE_WRITE_HANDLER_H
#define BLE_WRITE_HANDLER_H

#include <Arduino.h>

class BleWriteHandler {
 public:
  virtual ~BleWriteHandler() {}
  virtual void onWrite(const uint8_t* data, size_t len) = 0;
  virtual void onConnectionChanged(bool connected) = 0;
};

#endif
