#ifndef BLE_UI_H
#define BLE_UI_H

#include <Arduino.h>

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
  virtual void setQuestionPrompt(const char* questionId,
                                 const char* question,
                                 const char* const* optionIds,
                                 const char* const* optionLabels,
                                 uint8_t optionCount) {
    (void)questionId;
    (void)question;
    (void)optionIds;
    (void)optionLabels;
    (void)optionCount;
  }
  virtual void setLedEnabled(bool enabled) { (void)enabled; }
};

#endif
