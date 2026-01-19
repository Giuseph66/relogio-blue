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

 private:
  void draw(bool force);
  void drawStaticElements();
  void clearTextArea(int x, int y, int w, int h);
  String limitText(const String& text, size_t maxLen) const;

  bool _connected;
  String _lastRx;
  String _lastTx;
  String _lastButton;
  bool _dirty;
  uint32_t _lastDrawAt;
  bool _firstDraw;
};

#endif
