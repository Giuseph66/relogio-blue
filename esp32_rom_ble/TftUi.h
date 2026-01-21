#ifndef TFT_UI_H
#define TFT_UI_H

#include <Arduino.h>
#include "BleUi.h"

class TftUi : public BleUi {
 public:
  TftUi();
  void begin();

  void setConnected(bool connected) override;
  void setLastRx(const char* message) override;
  void setLastTx(const char* message) override;
  void setLastButton(const char* button, bool longPress) override;
  void update() override;

  void setScreen(ScreenType screen) override;
  void setQuestion(const char* question) override;

 private:
  void draw(bool force);
  void drawMainScreen(bool force);
  void drawQuestionScreen(bool force);
  void drawStaticElements();
  void clearTextArea(int x, int y, int w, int h);
  void drawTimerArc(int centerX, int centerY, int radius, int thickness, float percentage);
  uint16_t interpolateColor(uint16_t color1, uint16_t color2, float factor);
  String limitText(const String& text, size_t maxLen) const;

  bool _connected;
  String _lastRx;
  String _lastTx;
  String _lastButton;
  bool _dirty;
  uint32_t _lastDrawAt;
  bool _firstDraw;

  ScreenType _currentScreen;
  String _currentQuestion;
  uint32_t _questionStartTime;
  uint32_t _questionDuration;
  int _lastActiveSegments;
};

#endif
