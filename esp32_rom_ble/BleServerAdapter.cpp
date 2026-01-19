#include "BleServerAdapter.h"

BleServerAdapter::BleServerAdapter(const BleConfig& config)
    : _config(config),
      _handler(nullptr),
      _server(nullptr),
      _service(nullptr),
      _characteristic(nullptr),
      _advertising(nullptr),
      _deviceConnected(false) {}

void BleServerAdapter::setWriteHandler(BleWriteHandler* handler) {
  _handler = handler;
}

void BleServerAdapter::begin() {
  BLEDevice::init(_config.deviceName);

  _server = BLEDevice::createServer();
  _server->setCallbacks(this);

  _service = _server->createService(_config.serviceUuid);
  _characteristic = _service->createCharacteristic(
      _config.characteristicUuid,
      BLECharacteristic::PROPERTY_READ |
          BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_WRITE_NR |
          BLECharacteristic::PROPERTY_NOTIFY);

  _characteristic->setCallbacks(this);
  _characteristic->addDescriptor(new BLE2902());
  _characteristic->setValue("ready");

  _service->start();

  _advertising = BLEDevice::getAdvertising();
  _advertising->addServiceUUID(_config.serviceUuid);
  _advertising->setScanResponse(true);
  _advertising->setMinPreferred(0x06);
  _advertising->setMinPreferred(0x12);

  BLEDevice::startAdvertising();
}

bool BleServerAdapter::notify(const uint8_t* data, size_t len) {
  if (!_deviceConnected || _characteristic == nullptr || data == nullptr || len == 0) {
    return false;
  }

  _characteristic->setValue(const_cast<uint8_t*>(data), len);
  _characteristic->notify();
  return true;
}

bool BleServerAdapter::isConnected() const {
  return _deviceConnected;
}

void BleServerAdapter::onConnect(BLEServer* server) {
  (void)server;
  _deviceConnected = true;
  if (_handler != nullptr) {
    _handler->onConnectionChanged(true);
  }
}

void BleServerAdapter::onDisconnect(BLEServer* server) {
  (void)server;
  _deviceConnected = false;
  if (_handler != nullptr) {
    _handler->onConnectionChanged(false);
  }
  delay(100);
  BLEDevice::startAdvertising();
}

void BleServerAdapter::onWrite(BLECharacteristic* characteristic) {
  if (_handler == nullptr || characteristic == nullptr) {
    return;
  }

  const String value = characteristic->getValue();
  if (value.length() == 0) {
    return;
  }

  _handler->onWrite(reinterpret_cast<const uint8_t*>(value.c_str()), value.length());
}
