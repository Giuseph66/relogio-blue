#ifndef BLE_UI_H
#define BLE_UI_H

enum class ScreenType {
  MAIN,
  QUESTION
};

class BleUi {
 public:
  virtual ~BleUi() {}
  virtual void setConnected(bool connected) = 0;
  virtual void setLastRx(const char* message) = 0;
  virtual void setLastTx(const char* message) = 0;
  virtual void setLastButton(const char* button, bool longPress) = 0;
  virtual void update() = 0;
  virtual void setScreen(ScreenType screen) { (void)screen; }
  virtual void setQuestion(const char* question) { (void)question; }
};

#endif
