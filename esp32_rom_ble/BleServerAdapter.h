#ifndef BLE_SERVER_ADAPTER_H
#define BLE_SERVER_ADAPTER_H

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#include "BleConfig.h"
#include "BleNotifier.h"
#include "BleWriteHandler.h"

class BleServerAdapter : public BLEServerCallbacks,
                         public BLECharacteristicCallbacks,
                         public BleNotifier {
 public:
  explicit BleServerAdapter(const BleConfig& config);

  void begin();
  void setWriteHandler(BleWriteHandler* handler);

  bool notify(const uint8_t* data, size_t len) override;
  bool isConnected() const override;

 protected:
  void onConnect(BLEServer* server) override;
  void onDisconnect(BLEServer* server) override;
  void onWrite(BLECharacteristic* characteristic) override;

 private:
  BleConfig _config;
  BleWriteHandler* _handler;
  BLEServer* _server;
  BLEService* _service;
  BLECharacteristic* _characteristic;
  BLEAdvertising* _advertising;
  bool _deviceConnected;
};

#endif
