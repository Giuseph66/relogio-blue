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
      _firstDraw(true),
      _currentScreen(ScreenType::MAIN),
      _currentQuestion("Deseja prosseguir?"),
      _questionStartTime(0),
      _questionDuration(UI_QUESTION_TIMEOUT_MS),
      _lastActiveSegments(0) {}

void TftUi::begin() {
  tft.init();
  tft.setRotation(0);

#ifdef TFT_BL
  pinMode(TFT_BL, OUTPUT);
  digitalWrite(TFT_BL, HIGH);
#endif

  // Initial full screen draw
  tft.fillScreen(TFT_BLACK);
  draw(true);
}

void TftUi::setConnected(bool connected) {
  if (_connected == connected) {
    return;
  }
  _connected = connected;
  if (_currentScreen == ScreenType::MAIN) _dirty = true;
}

void TftUi::setLastRx(const char* message) {
  if (message == nullptr) {
    return;
  }
  _lastRx = message;
  if (_currentScreen == ScreenType::MAIN) _dirty = true;
}

void TftUi::setLastTx(const char* message) {
  if (message == nullptr) {
    return;
  }
  _lastTx = message;
  if (_currentScreen == ScreenType::MAIN) _dirty = true;
}

void TftUi::setLastButton(const char* button, bool longPress) {
  if (button == nullptr) {
    return;
  }
  _lastButton = String(button) + (longPress ? " (L)" : "");
  if (_currentScreen == ScreenType::MAIN) _dirty = true;
}

void TftUi::setScreen(ScreenType screen) {
  if (_currentScreen == screen) return;
  _currentScreen = screen;
  _dirty = true;
  _firstDraw = true; // Force full redraw when switching screens
  
  if (_currentScreen == ScreenType::QUESTION) {
    _questionStartTime = millis();
    _questionDuration = UI_QUESTION_TIMEOUT_MS;
    _lastActiveSegments = 360; // Start with full circle
  }
}

void TftUi::setQuestion(const char* question) {
  if (question == nullptr) return;
  _currentQuestion = question;
  if (_currentScreen == ScreenType::QUESTION) _dirty = true;
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
  
  // For the question screen, we want faster updates for smooth arc movement
  uint32_t interval = (_currentScreen == ScreenType::QUESTION) ? 30 : UI_UPDATE_INTERVAL_MS;

  if (!force && !_dirty && (now - _lastDrawAt < interval)) {
    return;
  }

  _lastDrawAt = now;
  _dirty = false;

  if (_currentScreen == ScreenType::MAIN) {
    drawMainScreen(force);
  } else if (_currentScreen == ScreenType::QUESTION) {
    drawQuestionScreen(force);
  }
}

void TftUi::drawMainScreen(bool force) {
  const int centerX = tft.width() / 2;
  const int valueX = 125;
  
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
  
  // Footer indicator
  clearTextArea(centerX - 40, 210, 80, 15);
  tft.setTextFont(1);
  tft.setTextDatum(MC_DATUM);
  tft.setTextColor(TFT_DARKGREY, TFT_BLACK);
  tft.drawString("BLE Ready", centerX, 215);
}

void TftUi::drawQuestionScreen(bool force) {
  const uint32_t now = millis();
  const uint32_t elapsed = now - _questionStartTime;
  
  const int centerX = tft.width() / 2;
  float percentageRemaining = 1.0f - ((float)elapsed / _questionDuration);
  if (percentageRemaining < 0) percentageRemaining = 0;
  
  if (_firstDraw || force) {
    tft.fillScreen(TFT_BLACK);
    // Draw subtle background ring for the timer
    tft.drawCircle(centerX, 120, 115, tft.color565(40, 40, 40));
    _firstDraw = false;
  }

  // Draw Title
  tft.setTextDatum(MC_DATUM);
  tft.setTextFont(4);
  tft.setTextColor(TFT_CYAN, TFT_BLACK);
  tft.drawString("PERGUNTA", centerX, 45);

  // Draw Timer Arc (Outer ring) - high resolution and optimized
  drawTimerArc(centerX, 120, 115, 4, percentageRemaining);

  // Draw Question
  tft.setTextFont(2);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  if (_currentQuestion.length() > 18) {
    String line1 = _currentQuestion.substring(0, 18);
    String line2 = _currentQuestion.substring(18);
    tft.drawString(line1, centerX, 100);
    tft.drawString(line2, centerX, 120);
  } else {
    tft.drawString(_currentQuestion, centerX, 110);
  }

  // Draw Buttons
  const int btnY = 180;
  tft.fillRoundRect(35, btnY - 20, 80, 40, 8, TFT_GREEN);
  tft.setTextColor(TFT_BLACK);
  tft.drawString("SIM", 75, btnY);
  tft.fillRoundRect(125, btnY - 20, 80, 40, 8, TFT_RED);
  tft.setTextColor(TFT_WHITE);
  tft.drawString("NAO", 165, btnY);
  
  _dirty = true; // Keep redrawing to update the arc smoothly
}

void TftUi::drawTimerArc(int centerX, int centerY, int radius, int thickness, float percentage) {
  if (percentage < 0) percentage = 0;
  
  int totalSegments = 360; // 1 degree per segment
  int activeSegments = (int)(totalSegments * percentage);
  
  // Gradient color based on percentage
  uint16_t arcColor = interpolateColor(TFT_RED, TFT_GREEN, percentage);
  
  // Optimization: Only clear the parts that are no longer part of the arc
  // instead of clearing the whole ring with drawCircle(..., BLACK)
  if (_lastActiveSegments > activeSegments) {
    for (int i = activeSegments; i < _lastActiveSegments; i++) {
        float angle = (i * 360.0f / totalSegments) - 90.0f;
        float rad = angle * PI / 180.0f;
        int x = centerX + cos(rad) * radius;
        int y = centerY + sin(rad) * radius;
        tft.fillCircle(x, y, thickness / 2 + 1, TFT_BLACK);
    }
  }

  // Draw active arc - we redraw it every time to update the gradient color
  // Since we draw over the old color, it won't flicker.
  for (int i = 0; i < activeSegments; i++) {
    float angle = (i * 360.0f / totalSegments) - 90.0f;
    float rad = angle * PI / 180.0f;
    int x = centerX + cos(rad) * radius;
    int y = centerY + sin(rad) * radius;
    tft.fillCircle(x, y, thickness / 2, arcColor);
  }
  
  _lastActiveSegments = activeSegments;
}

uint16_t TftUi::interpolateColor(uint16_t color1, uint16_t color2, float factor) {
  uint8_t r1 = (color1 >> 11) & 0x1F;
  uint8_t g1 = (color1 >> 5) & 0x3F;
  uint8_t b1 = color1 & 0x1F;

  uint8_t r2 = (color2 >> 11) & 0x1F;
  uint8_t g2 = (color2 >> 5) & 0x3F;
  uint8_t b2 = color2 & 0x1F;

  uint8_t r = (uint8_t)(r1 + (r2 - r1) * factor);
  uint8_t g = (uint8_t)(g1 + (g2 - g1) * factor);
  uint8_t b = (uint8_t)(b1 + (b2 - b1) * factor);

  return (uint16_t)((r << 11) | (g << 5) | b);
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
