#include "User_Setup.h"
#include <TFT_eSPI.h>
#include "TftUi.h"
#include "UiConfig.h"

namespace {
TFT_eSPI tft;
}

TftUi::TftUi()
    : _connected(false),
      _lastRx("-"),
      _lastTx("-"),
      _lastButton("-"),
      _dirty(true),
      _lastDrawAt(0),
      _firstDraw(true) {}

void TftUi::begin() {
  tft.init();
  tft.setRotation(0);

#ifdef TFT_BL
  pinMode(TFT_BL, OUTPUT);
  digitalWrite(TFT_BL, HIGH);
#endif

  // Initial full screen draw
  tft.fillScreen(TFT_BLACK);
  drawStaticElements();
  draw(true);
}

void TftUi::setConnected(bool connected) {
  if (_connected == connected) {
    return;
  }
  _connected = connected;
  _dirty = true;
}

void TftUi::setLastRx(const char* message) {
  if (message == nullptr) {
    return;
  }
  _lastRx = message;
  _dirty = true;
}

void TftUi::setLastTx(const char* message) {
  if (message == nullptr) {
    return;
  }
  _lastTx = message;
  _dirty = true;
}

void TftUi::setLastButton(const char* button, bool longPress) {
  if (button == nullptr) {
    return;
  }
  _lastButton = String(button) + (longPress ? " (L)" : "");
  _dirty = true;
}

void TftUi::update() {
  draw(false);
}

void TftUi::drawStaticElements() {
  const int centerX = tft.width() / 2;
  
  // Draw title with modern styling - moved slightly down for more width
  tft.setTextDatum(MC_DATUM);
  tft.setTextFont(4);
  tft.setTextColor(TFT_CYAN, TFT_BLACK);
  tft.drawString(UI_TITLE, centerX, 35);
  
  // Draw decorative circle border - slightly smaller to be safer
  tft.drawCircle(centerX, 120, 108, TFT_DARKGREY);
  
  // Draw section labels (static)
  // Using Right Alignment (MR_DATUM) at x=110 to keep labels near center
  tft.setTextFont(2);
  tft.setTextDatum(MR_DATUM);
  tft.setTextColor(TFT_DARKGREY, TFT_BLACK);
  
  const int labelX = 110;
  tft.drawString("STATUS", labelX, 75);
  tft.drawString("RECEBIDO", labelX, 115);
  tft.drawString("ENVIADO", labelX, 155);
  tft.drawString("BOTAO", labelX, 195);
}

void TftUi::clearTextArea(int x, int y, int w, int h) {
  tft.fillRect(x, y, w, h, TFT_BLACK);
}

void TftUi::draw(bool force) {
  const uint32_t now = millis();
  if (!force && !_dirty && (now - _lastDrawAt < UI_UPDATE_INTERVAL_MS)) {
    return;
  }

  _lastDrawAt = now;
  _dirty = false;

  const int centerX = tft.width() / 2;
  // Values start at x=125 (Left Aligned)
  const int valueX = 125;
  
  // Only redraw static elements on first draw or force
  if (_firstDraw || force) {
    tft.fillScreen(TFT_BLACK);
    drawStaticElements();
    _firstDraw = false;
  }

  // Update connection status
  clearTextArea(valueX, 65, 80, 20);
  tft.setTextFont(2);
  tft.setTextDatum(ML_DATUM);
  tft.setTextColor(_connected ? TFT_GREEN : TFT_RED, TFT_BLACK);
  tft.drawString(_connected ? "OK" : "OFF", valueX, 75);
  
  // Draw connection indicator dot
  int dotX = valueX - 10;
  tft.fillCircle(dotX, 75, 4, _connected ? TFT_GREEN : TFT_RED);

  // Update RX message
  clearTextArea(valueX, 105, 85, 20);
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.drawString(limitText(_lastRx, 10), valueX, 115);

  // Update TX message
  clearTextArea(valueX, 145, 85, 20);
  tft.setTextColor(TFT_CYAN, TFT_BLACK);
  tft.drawString(limitText(_lastTx, 10), valueX, 155);

  // Update Button
  clearTextArea(valueX, 185, 85, 20);
  tft.setTextColor(TFT_ORANGE, TFT_BLACK);
  tft.drawString(limitText(_lastButton, 10), valueX, 195);
  
  // Footer indicator - moved up for safety
  clearTextArea(centerX - 40, 210, 80, 15);
  tft.setTextFont(1);
  tft.setTextDatum(MC_DATUM);
  tft.setTextColor(TFT_DARKGREY, TFT_BLACK);
  tft.drawString("BLE Ready", centerX, 215);
}

String TftUi::limitText(const String& text, size_t maxLen) const {
  if (text.length() <= maxLen) {
    return text;
  }

  if (maxLen <= 3) {
    return text.substring(0, maxLen);
  }

  return text.substring(0, maxLen - 3) + "...";
}
