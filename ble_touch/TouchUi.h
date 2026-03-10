#ifndef TOUCH_UI_H
#define TOUCH_UI_H

#include "User_Setup.h"
#include <Arduino.h>
#include <SPI.h>
#include <TFT_eSPI.h>
#include <XPT2046_Touchscreen.h>
#include "BleUi.h"

class TouchUi : public BleUi {
 public:
  TouchUi();

  void begin();
  void update() override;
  bool pollAction(char* target, size_t targetSize);

  void setConnected(bool connected) override;
  void setLastRx(const char* message) override;
  void setLastTx(const char* message) override;
  void setLastButton(const char* button, bool longPress) override;
  void setScreen(ScreenType screen) override;
  void setQuestion(const char* question) override;
  void setQuestionPrompt(const char* questionId,
                         const char* question,
                         const char* const* optionIds,
                         const char* const* optionLabels,
                         uint8_t optionCount) override;
  void setLedEnabled(bool enabled) override;

 private:
  enum class Page : uint8_t {
    STATUS = 0,
    CONTROL = 1,
    CANVAS = 2
  };

  TFT_eSPI tft_;
  SPIClass touchSpi_;
  XPT2046_Touchscreen touch_;

  uint16_t touchCal_[5];
  bool connected_;
  bool ledEnabled_;
  bool dirty_;
  bool touchReady_;
  bool touchLatched_;
  bool canvasInitialized_;
  bool questionScreenInitialized_;
  uint32_t lastDrawAt_;
  uint32_t questionStartTime_;
  int16_t lastQuestionBarWidth_;

  Page currentPage_;
  ScreenType currentScreen_;

  String lastRx_;
  String lastTx_;
  String lastAction_;
  String questionId_;
  String question_;
  String questionOptionIds_[4];
  String questionOptionLabels_[4];
  uint8_t questionOptionCount_;

  char pendingAction_[48];
  bool hasPendingAction_;

  uint16_t activeColor_;
  uint8_t brushSize_;
  int16_t lastDrawX_;
  int16_t lastDrawY_;

  bool setupTouch();
  bool recalibrateTouch();
  bool getTouchPoint(uint16_t* x, uint16_t* y);
  bool enqueueAction(const char* action);

  void handleTouch();
  bool handleTabTouch(uint16_t x, uint16_t y);
  void handleControlTouch(uint16_t x, uint16_t y);
  void handleCanvasTouch(uint16_t x, uint16_t y);
  bool handleQuestionTouch(uint16_t x, uint16_t y);
  bool getQuestionOptionRect(uint8_t index, int16_t* x, int16_t* y, int16_t* w, int16_t* h) const;

  void draw(bool force);
  void drawMainScreen(bool force);
  void drawQuestionScreen(bool force);
  void drawHeader();
  void drawStatusPage();
  void drawControlPage();
  void drawCanvasPage(bool force);
  void drawCanvasToolbar();
  void clearCanvas();
  void drawStroke(int16_t x0, int16_t y0, int16_t x1, int16_t y1);
  void drawButton(int16_t x, int16_t y, int16_t w, int16_t h,
                  const char* label, uint16_t fill, uint16_t border,
                  uint16_t textColor, bool isFlat = false, uint8_t icon = 0);
  
  // Icon drawing helpers inspired by SVG (centered at x,y)
  void drawIcon(uint8_t iconIdx, int16_t x, int16_t y, uint16_t color);
  void drawIconBluetooth(int16_t x, int16_t y, uint16_t color);
  void drawIconLed(int16_t x, int16_t y, bool on, uint16_t color);
  void drawIconPing(int16_t x, int16_t y, uint16_t color);
  void drawIconCheck(int16_t x, int16_t y, uint16_t color);
  void drawIconCross(int16_t x, int16_t y, uint16_t color);
  void drawIconClear(int16_t x, int16_t y, uint16_t color);
  void drawIconCalibrate(int16_t x, int16_t y, uint16_t color);

  String limitText(const String& text, size_t maxLen) const;
};

#endif
