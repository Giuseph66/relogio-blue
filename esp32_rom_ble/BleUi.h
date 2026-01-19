#ifndef BLE_UI_H
#define BLE_UI_H

class BleUi {
 public:
  virtual ~BleUi() {}
  virtual void setConnected(bool connected) = 0;
  virtual void setLastRx(const char* message) = 0;
  virtual void setLastTx(const char* message) = 0;
  virtual void setLastButton(const char* button, bool longPress) = 0;
  virtual void update() = 0;
};

#endif
