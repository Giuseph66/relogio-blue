#ifndef BLE_CONFIG_H
#define BLE_CONFIG_H

#include <Arduino.h>

struct BleConfig {
  const char* deviceName;
  const char* serviceUuid;
  const char* characteristicUuid;
  uint32_t notifyIntervalMs;
  int ledPin;
  bool ledActiveHigh;
};

inline BleConfig defaultBleConfig() {
  BleConfig config = {
    "ESP32",
    "0000ffe0-0000-1000-8000-00805f9b34fb",
    "0000ffe1-0000-1000-8000-00805f9b34fb",
    2000,
    2,
    true
  };
  return config;
}

#endif
