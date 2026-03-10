#include "TouchUi.h"

#include <math.h>
#include <string.h>

#include "UiConfig.h"

namespace {

constexpr uint8_t kTouchCsPin = 33;
constexpr uint8_t kTouchMosiPin = 32;
constexpr uint8_t kTouchMisoPin = 39;
constexpr uint8_t kTouchClkPin = 25;
constexpr uint16_t kTouchThreshold = 450;
constexpr int16_t kTouchInset = 28;
constexpr uint16_t kDefaultTouchCal[5] = {200, 3600, 200, 3600, 0};

constexpr int16_t kHeaderH = 34;
constexpr int16_t kPageTop = kHeaderH + 4;
constexpr int16_t kCanvasToolbarH = 36;
constexpr int16_t kCanvasY = kPageTop + kCanvasToolbarH + 4;

constexpr uint16_t rgb565(uint8_t r, uint8_t g, uint8_t b) {
  return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

struct Theme {
  uint16_t bg;
  uint16_t panel;
  uint16_t panelAlt;
  uint16_t border;
  uint16_t text;
  uint16_t muted;
  uint16_t aqua;
  uint16_t green;
  uint16_t yellow;
  uint16_t orange;
  uint16_t red;
  uint16_t blue;
};

const Theme kTheme = {
    TFT_BLACK,              // bg -> Pure black 
    rgb565(0, 16, 32),      // panel -> Pure dark cool blue (No Red/Green mix to avoid brown)
    rgb565(0, 32, 56),      // panelAlt -> Pure cool blue
    rgb565(32, 64, 96),     // border -> Cool divider
    TFT_WHITE,              // text -> Maximum contrast white
    rgb565(128, 128, 128),  // muted -> Pure neural grey (no color wash)
    TFT_CYAN,               // aqua -> Pure cyan for perfect TN display
    TFT_GREEN,              // green -> Pure green
    TFT_YELLOW,             // yellow -> Pure yellow
    TFT_ORANGE,             // orange -> Hardware standard orange
    TFT_RED,                // red -> Hardware standard red
    rgb565(0, 128, 255),    // blue -> Vibrant action blue
};

struct Swatch {
  uint16_t color;
  int16_t x;
};

const Swatch kSwatches[] = {
    {TFT_WHITE, 8},
    {TFT_RED, 36},
    {TFT_YELLOW, 64},
    {TFT_GREEN, 92},
    {TFT_CYAN, 120},
    {TFT_BLUE, 148},
};

bool contains(int16_t x, int16_t y, int16_t rx, int16_t ry, int16_t rw, int16_t rh) {
  return x >= rx && x < (rx + rw) && y >= ry && y < (ry + rh);
}

void drawCalibrationTarget(TFT_eSPI& tft, int16_t x, int16_t y, uint16_t color) {
  const int16_t arm = 10;
  tft.drawFastHLine(x - arm, y, arm * 2 + 1, color);
  tft.drawFastVLine(x, y - arm, arm * 2 + 1, color);
  tft.drawCircle(x, y, 12, color);
  tft.drawCircle(x, y, 4, color);
}

bool waitForRelease(XPT2046_Touchscreen& touch, uint32_t timeoutMs) {
  const uint32_t start = millis();
  while ((millis() - start) < timeoutMs) {
    if (!touch.touched()) {
      return true;
    }
    delay(5);
  }
  return false;
}

bool sampleRawTouch(XPT2046_Touchscreen& touch, uint16_t* x, uint16_t* y, uint32_t timeoutMs) {
  const uint32_t start = millis();
  uint8_t pressCount = 0;
  uint32_t sx = 0;
  uint32_t sy = 0;
  uint8_t samples = 0;

  while ((millis() - start) < timeoutMs) {
    if (touch.touched()) {
      if (pressCount < 4) {
        ++pressCount;
        delay(12);
        continue;
      }

      const TS_Point p = touch.getPoint();
      if (p.z < kTouchThreshold) {
        delay(8);
        continue;
      }

      sx += static_cast<uint16_t>(p.x);
      sy += static_cast<uint16_t>(p.y);
      ++samples;
      if (samples >= 16) {
        *x = static_cast<uint16_t>(sx / samples);
        *y = static_cast<uint16_t>(sy / samples);
        waitForRelease(touch, 1200);
        return true;
      }
    } else if (pressCount > 0 && samples == 0) {
      pressCount = 0;
    }

    delay(8);
  }

  return false;
}

bool validateCalibrationSample(uint8_t index, const uint16_t* raw, uint16_t rx, uint16_t ry) {
  constexpr int32_t kNearAxisMax = 700;
  constexpr int32_t kFarAxisMin = 1200;

  if (index == 0) {
    return true;
  }

  const int32_t baseX = raw[0];
  const int32_t baseY = raw[1];
  const int32_t dx01 = static_cast<int32_t>(raw[2]) - baseX;
  const int32_t dy01 = static_cast<int32_t>(raw[3]) - baseY;

  if (index == 1) {
    const int32_t dx = static_cast<int32_t>(rx) - baseX;
    const int32_t dy = static_cast<int32_t>(ry) - baseY;
    return (abs(dx) <= kNearAxisMax && abs(dy) >= kFarAxisMin) ||
           (abs(dy) <= kNearAxisMax && abs(dx) >= kFarAxisMin);
  }

  const bool verticalIsX = abs(dx01) > abs(dy01);
  const int32_t verticalDelta = verticalIsX ? static_cast<int32_t>(rx) - baseX
                                            : static_cast<int32_t>(ry) - baseY;
  const int32_t horizontalDelta = verticalIsX ? static_cast<int32_t>(ry) - baseY
                                              : static_cast<int32_t>(rx) - baseX;

  if (index == 2) {
    return abs(verticalDelta) <= kNearAxisMax && abs(horizontalDelta) >= kFarAxisMin;
  }

  return abs(verticalDelta) >= kFarAxisMin && abs(horizontalDelta) >= kFarAxisMin;
}

void storeTouchCalibration(uint16_t* cal, uint16_t xl, uint16_t xr, uint16_t yt, uint16_t yb,
                           bool rotate, bool invertX, bool invertY,
                           int16_t width, int16_t height, int16_t inset) {
  const uint32_t usableW = width - (inset * 2);
  const uint32_t usableH = height - (inset * 2);
  uint32_t spanX = static_cast<uint32_t>(abs(static_cast<int32_t>(xr) - static_cast<int32_t>(xl)));
  uint32_t spanY = static_cast<uint32_t>(abs(static_cast<int32_t>(yb) - static_cast<int32_t>(yt)));

  if (usableW == 0 || usableH == 0 || spanX == 0 || spanY == 0) {
    return;
  }

  spanX = (spanX * width) / usableW;
  spanY = (spanY * height) / usableH;

  uint32_t x0 = xl;
  uint32_t y0 = yt;
  const uint32_t xPad = (spanX * inset) / width;
  const uint32_t yPad = (spanY * inset) / height;
  x0 = (x0 > xPad) ? (x0 - xPad) : 1;
  y0 = (y0 > yPad) ? (y0 - yPad) : 1;

  cal[0] = static_cast<uint16_t>(x0 == 0 ? 1 : x0);
  cal[1] = static_cast<uint16_t>(spanX == 0 ? 1 : spanX);
  cal[2] = static_cast<uint16_t>(y0 == 0 ? 1 : y0);
  cal[3] = static_cast<uint16_t>(spanY == 0 ? 1 : spanY);
  cal[4] = (rotate ? 1 : 0) | (invertX ? 2 : 0) | (invertY ? 4 : 0);
}

bool calibrateTouchInset(TFT_eSPI& tft, XPT2046_Touchscreen& touch, uint16_t* cal) {
  const int16_t w = tft.width();
  const int16_t h = tft.height();
  const int16_t ix = kTouchInset;
  const int16_t iy = kTouchInset;
  const int16_t tx[4] = {ix, ix, static_cast<int16_t>(w - 1 - ix), static_cast<int16_t>(w - 1 - ix)};
  const int16_t ty[4] = {iy, static_cast<int16_t>(h - 1 - iy), iy, static_cast<int16_t>(h - 1 - iy)};
  uint16_t raw[8] = {0, 0, 0, 0, 0, 0, 0, 0};

  tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextDatum(MC_DATUM);
  tft.drawString("Calibracao touch", w / 2, 20, 4);
  tft.drawString("Toque e segure cada alvo", w / 2, 48, 2);
  tft.drawString("Sem pressa: 4 pontos", w / 2, 66, 2);
  tft.setTextDatum(TL_DATUM);

  for (uint8_t i = 0; i < 4; ++i) {
    tft.fillRect(0, 86, w, h - 86, TFT_BLACK);
    tft.setTextColor(TFT_CYAN, TFT_BLACK);
    tft.drawString(String(i + 1) + "/4", 12, 92, 2);
    tft.drawString("Aguarde o circulo verde", 12, 112, 2);
    drawCalibrationTarget(tft, tx[i], ty[i], TFT_MAGENTA);

    bool accepted = false;
    while (!accepted) {
      if (!waitForRelease(touch, 600)) {
        delay(50);
      }

      uint16_t rx = 0;
      uint16_t ry = 0;
      if (!sampleRawTouch(touch, &rx, &ry, 8000)) {
        return false;
      }

      if (!validateCalibrationSample(i, raw, rx, ry)) {
        tft.setTextColor(TFT_RED, TFT_BLACK);
        tft.fillRect(12, 132, 240, 18, TFT_BLACK);
        tft.drawString("Toque no alvo destacado", 12, 132, 2);
        delay(700);
        tft.fillRect(12, 132, 240, 18, TFT_BLACK);
        tft.setTextColor(TFT_CYAN, TFT_BLACK);
        continue;
      }

      raw[i * 2] = rx;
      raw[i * 2 + 1] = ry;
      tft.fillCircle(tx[i], ty[i], 6, TFT_GREEN);
      delay(180);
      accepted = true;
    }
  }

  bool rotate = false;
  uint16_t x0 = 0;
  uint16_t x1 = 0;
  uint16_t y0 = 0;
  uint16_t y1 = 0;

  if (abs(static_cast<int32_t>(raw[0]) - static_cast<int32_t>(raw[4])) >
      abs(static_cast<int32_t>(raw[1]) - static_cast<int32_t>(raw[5]))) {
    rotate = true;
    x0 = (raw[1] + raw[3]) / 2;
    x1 = (raw[5] + raw[7]) / 2;
    y0 = (raw[0] + raw[4]) / 2;
    y1 = (raw[2] + raw[6]) / 2;
  } else {
    x0 = (raw[0] + raw[2]) / 2;
    x1 = (raw[4] + raw[6]) / 2;
    y0 = (raw[1] + raw[5]) / 2;
    y1 = (raw[3] + raw[7]) / 2;
  }

  bool invertX = false;
  if (x0 > x1) {
    const uint16_t tmp = x0;
    x0 = x1;
    x1 = tmp;
    invertX = true;
  }

  bool invertY = false;
  if (y0 > y1) {
    const uint16_t tmp = y0;
    y0 = y1;
    y1 = tmp;
    invertY = true;
  }

  storeTouchCalibration(cal, x0, x1, y0, y1, rotate, invertX, invertY, w, h, kTouchInset);
  return true;
}

}  // namespace

TouchUi::TouchUi()
    : tft_(320, 240),
      touchSpi_(HSPI),
      touch_(kTouchCsPin),
      touchCal_{200, 3600, 200, 3600, 0},
      connected_(false),
      ledEnabled_(false),
      dirty_(true),
      touchReady_(false),
      touchLatched_(false),
      canvasInitialized_(false),
      questionScreenInitialized_(false),
      lastDrawAt_(0),
      questionStartTime_(0),
      lastQuestionBarWidth_(-1),
      currentPage_(Page::STATUS),
      currentScreen_(ScreenType::MAIN),
      lastRx_("-"),
      lastTx_("-"),
      lastAction_("-"),
      questionId_("legacy"),
      question_("Deseja prosseguir?"),
      questionOptionIds_{},
      questionOptionLabels_{},
      questionOptionCount_(2),
      pendingAction_{0},
      hasPendingAction_(false),
      activeColor_(TFT_WHITE),
      brushSize_(4),
      lastDrawX_(-1),
      lastDrawY_(-1) {
  questionOptionIds_[0] = "SIM";
  questionOptionIds_[1] = "NAO";
  questionOptionLabels_[0] = "SIM";
  questionOptionLabels_[1] = "NAO";
}

void TouchUi::begin() {
  tft_.init();
  tft_.setRotation(2);

#ifdef TFT_BL
  pinMode(TFT_BL, OUTPUT);
  digitalWrite(TFT_BL, TFT_BACKLIGHT_ON);
#endif

  touchReady_ = setupTouch();
  dirty_ = true;
  draw(true);
}

void TouchUi::update() {
  handleTouch();
  draw(false);
}

bool TouchUi::pollAction(char* target, size_t targetSize) {
  if (!hasPendingAction_ || target == nullptr || targetSize == 0) {
    return false;
  }

  const size_t len = strlen(pendingAction_);
  const size_t copyLen = (len < (targetSize - 1)) ? len : (targetSize - 1);
  memcpy(target, pendingAction_, copyLen);
  target[copyLen] = '\0';
  pendingAction_[0] = '\0';
  hasPendingAction_ = false;
  return true;
}

void TouchUi::setConnected(bool connected) {
  if (connected_ == connected) {
    return;
  }

  connected_ = connected;
  if (currentScreen_ == ScreenType::MAIN && currentPage_ != Page::CANVAS) {
    dirty_ = true;
  }
}

void TouchUi::setLastRx(const char* message) {
  if (message == nullptr) {
    return;
  }

  lastRx_ = message;
  if (currentScreen_ == ScreenType::MAIN && currentPage_ != Page::CANVAS) {
    dirty_ = true;
  }
}

void TouchUi::setLastTx(const char* message) {
  if (message == nullptr) {
    return;
  }

  lastTx_ = message;
  if (currentScreen_ == ScreenType::MAIN && currentPage_ != Page::CANVAS) {
    dirty_ = true;
  }
}

void TouchUi::setLastButton(const char* button, bool longPress) {
  if (button == nullptr) {
    return;
  }

  lastAction_ = String(button) + (longPress ? " (L)" : "");
  if (currentScreen_ == ScreenType::MAIN && currentPage_ != Page::CANVAS) {
    dirty_ = true;
  }
}

void TouchUi::setScreen(ScreenType screen) {
  if (currentScreen_ == screen) {
    return;
  }

  currentScreen_ = screen;
  touchLatched_ = false;
  if (screen == ScreenType::QUESTION) {
    questionStartTime_ = millis();
    questionScreenInitialized_ = false;
    lastQuestionBarWidth_ = -1;
  } else if (currentPage_ == Page::CANVAS) {
    canvasInitialized_ = false;
  }
  dirty_ = true;
}

void TouchUi::setQuestion(const char* question) {
  if (question == nullptr) {
    return;
  }

  const char* optionIds[2] = {"SIM", "NAO"};
  const char* optionLabels[2] = {"SIM", "NAO"};
  setQuestionPrompt("legacy", question, optionIds, optionLabels, 2);
}

void TouchUi::setQuestionPrompt(const char* questionId,
                                const char* question,
                                const char* const* optionIds,
                                const char* const* optionLabels,
                                uint8_t optionCount) {
  if (question == nullptr || optionIds == nullptr || optionLabels == nullptr) {
    return;
  }

  questionId_ = (questionId == nullptr || questionId[0] == '\0') ? "legacy" : questionId;
  question_ = question;
  questionOptionCount_ = optionCount > 4 ? 4 : optionCount;

  for (uint8_t i = 0; i < 4; ++i) {
    questionOptionIds_[i] = "";
    questionOptionLabels_[i] = "";
  }

  for (uint8_t i = 0; i < questionOptionCount_; ++i) {
    questionOptionIds_[i] = optionIds[i] == nullptr ? "" : optionIds[i];
    questionOptionLabels_[i] = optionLabels[i] == nullptr ? "" : optionLabels[i];
  }

  if (currentScreen_ == ScreenType::QUESTION) {
    questionStartTime_ = millis();
    questionScreenInitialized_ = false;
    lastQuestionBarWidth_ = -1;
    dirty_ = true;
  }
}

void TouchUi::setLedEnabled(bool enabled) {
  if (ledEnabled_ == enabled) {
    return;
  }

  ledEnabled_ = enabled;
  if (currentScreen_ == ScreenType::MAIN && currentPage_ != Page::CANVAS) {
    dirty_ = true;
  }
}

bool TouchUi::setupTouch() {
  touchSpi_.begin(kTouchClkPin, kTouchMisoPin, kTouchMosiPin, kTouchCsPin);
  touch_.begin(touchSpi_);
  touch_.setRotation(1);

  memcpy(touchCal_, kDefaultTouchCal, sizeof(touchCal_));
  return true;
}

bool TouchUi::recalibrateTouch() {
  touchLatched_ = false;
  uint16_t previousCal[5];
  memcpy(previousCal, touchCal_, sizeof(previousCal));

  uint16_t trialCal[5];
  memcpy(trialCal, touchCal_, sizeof(trialCal));

  const bool ok = calibrateTouchInset(tft_, touch_, trialCal);
  if (ok) {
    memcpy(touchCal_, trialCal, sizeof(touchCal_));
  } else {
    memcpy(touchCal_, previousCal, sizeof(touchCal_));
  }

  dirty_ = true;
  canvasInitialized_ = false;
  return ok;
}

bool TouchUi::getTouchPoint(uint16_t* x, uint16_t* y) {
  if (!touch_.touched()) {
    return false;
  }

  const TS_Point p = touch_.getPoint();
  if (p.z < kTouchThreshold) {
    return false;
  }

  int32_t xx = 0;
  int32_t yy = 0;
  if (touchCal_[4] & 0x01) {
    xx = (static_cast<int32_t>(p.y) - touchCal_[0]) * tft_.width() / touchCal_[1];
    yy = (static_cast<int32_t>(p.x) - touchCal_[2]) * tft_.height() / touchCal_[3];
  } else {
    xx = (static_cast<int32_t>(p.x) - touchCal_[0]) * tft_.width() / touchCal_[1];
    yy = (static_cast<int32_t>(p.y) - touchCal_[2]) * tft_.height() / touchCal_[3];
  }

  if (touchCal_[4] & 0x02) {
    xx = (tft_.width() - 1) - xx;
  }
  if (touchCal_[4] & 0x04) {
    yy = (tft_.height() - 1) - yy;
  }

  if (xx < 0 || yy < 0 || xx >= tft_.width() || yy >= tft_.height()) {
    return false;
  }

  *x = static_cast<uint16_t>(xx);
  *y = static_cast<uint16_t>(yy);
  return true;
}

bool TouchUi::enqueueAction(const char* action) {
  if (action == nullptr || action[0] == '\0') {
    return false;
  }

  if (hasPendingAction_) {
    return false;
  }

  const size_t len = strlen(action);
  const size_t copyLen = (len < (sizeof(pendingAction_) - 1)) ? len : (sizeof(pendingAction_) - 1);
  memcpy(pendingAction_, action, copyLen);
  pendingAction_[copyLen] = '\0';
  hasPendingAction_ = true;
  return true;
}

void TouchUi::handleTouch() {
  if (!touchReady_) {
    return;
  }

  if (!touch_.touched()) {
    touchLatched_ = false;
    lastDrawX_ = -1;
    lastDrawY_ = -1;
    return;
  }

  uint16_t x = 0;
  uint16_t y = 0;
  if (!getTouchPoint(&x, &y)) {
    return;
  }

  if (currentScreen_ == ScreenType::QUESTION) {
    if (!touchLatched_ && handleQuestionTouch(x, y)) {
      touchLatched_ = true;
    }
    return;
  }

  if (handleTabTouch(x, y)) {
    touchLatched_ = true;
    lastDrawX_ = -1;
    lastDrawY_ = -1;
    return;
  }

  if (currentPage_ == Page::CONTROL) {
    if (!touchLatched_) {
      handleControlTouch(x, y);
      touchLatched_ = true;
    }
    return;
  }

  if (currentPage_ == Page::CANVAS) {
    handleCanvasTouch(x, y);
  }
}

bool TouchUi::handleTabTouch(uint16_t x, uint16_t y) {
  if (y > kHeaderH) {
    return false;
  }

  if (contains(x, y, 10, 8, 86, 20)) {
    currentPage_ = Page::STATUS;
    dirty_ = true;
    return true;
  }
  if (contains(x, y, 104, 8, 102, 20)) {
    currentPage_ = Page::CONTROL;
    dirty_ = true;
    return true;
  }
  if (contains(x, y, 214, 8, 96, 20)) {
    currentPage_ = Page::CANVAS;
    canvasInitialized_ = false;
    dirty_ = true;
    return true;
  }

  return false;
}

void TouchUi::handleControlTouch(uint16_t x, uint16_t y) {
  if (contains(x, y, 16, 88, 138, 48)) {
    setLastButton("PING", false);
    enqueueAction("PING");
    return;
  }
  if (contains(x, y, 166, 88, 138, 48)) {
    setLastButton("LED_ON", false);
    enqueueAction("LED_ON");
    return;
  }
  if (contains(x, y, 16, 146, 138, 48)) {
    setLastButton("LED_OFF", false);
    enqueueAction("LED_OFF");
    return;
  }
  if (contains(x, y, 166, 146, 138, 48)) {
    setLastButton("LED_STATUS", false);
    enqueueAction("LED_STATUS");
    return;
  }
  if (contains(x, y, 16, 206, 138, 26)) {
    lastRx_ = "-";
    lastTx_ = "-";
    lastAction_ = "LIMPO";
    dirty_ = true;
    return;
  }
  if (contains(x, y, 166, 206, 138, 26)) {
    lastAction_ = "REINICIAR";
    lastTx_ = "REBOOT";
    dirty_ = true;
    delay(120);
    ESP.restart();
  }
}

void TouchUi::handleCanvasTouch(uint16_t x, uint16_t y) {
  if (y < kCanvasY) {
    if (touchLatched_) {
      return;
    }

    for (uint8_t i = 0; i < (sizeof(kSwatches) / sizeof(kSwatches[0])); ++i) {
      if (contains(x, y, kSwatches[i].x, kPageTop + 6, 20, 20)) {
        activeColor_ = kSwatches[i].color;
        dirty_ = true;
        touchLatched_ = true;
        return;
      }
    }

    if (contains(x, y, 208, kPageTop + 6, 18, 20)) {
      brushSize_ = 2;
    } else if (contains(x, y, 232, kPageTop + 6, 18, 20)) {
      brushSize_ = 4;
    } else if (contains(x, y, 256, kPageTop + 6, 18, 20)) {
      brushSize_ = 7;
    } else if (contains(x, y, 282, kPageTop + 3, 28, 26)) {
      clearCanvas();
    }

    dirty_ = true;
    touchLatched_ = true;
    return;
  }

  drawStroke(lastDrawX_, lastDrawY_, x, y);
  lastDrawX_ = x;
  lastDrawY_ = y;
}

bool TouchUi::handleQuestionTouch(uint16_t x, uint16_t y) {
  for (uint8_t i = 0; i < questionOptionCount_; ++i) {
    int16_t rx = 0;
    int16_t ry = 0;
    int16_t rw = 0;
    int16_t rh = 0;
    if (!getQuestionOptionRect(i, &rx, &ry, &rw, &rh)) {
      continue;
    }
    if (!contains(x, y, rx, ry, rw, rh)) {
      continue;
    }

    setLastButton(questionOptionLabels_[i].c_str(), false);
    enqueueAction(questionOptionIds_[i].c_str());
    return true;
  }

  return false;
}

bool TouchUi::getQuestionOptionRect(uint8_t index,
                                    int16_t* x,
                                    int16_t* y,
                                    int16_t* w,
                                    int16_t* h) const {
  if (x == nullptr || y == nullptr || w == nullptr || h == nullptr) {
    return false;
  }

  if (questionOptionCount_ <= 2) {
    const int16_t xs[2] = {24, 176};
    if (index >= 2) {
      return false;
    }
    *x = xs[index];
    *y = 150;
    *w = 120;
    *h = 56;
    return true;
  }

  if (index >= 4) {
    return false;
  }

  const int16_t xs[4] = {24, 176, 24, 176};
  const int16_t ys[4] = {136, 136, 184, 184};
  *x = xs[index];
  *y = ys[index];
  *w = 120;
  *h = 40;
  return true;
}

void TouchUi::draw(bool force) {
  const uint32_t now = millis();
  const uint32_t interval =
      (currentScreen_ == ScreenType::QUESTION) ? UI_QUESTION_REDRAW_MS : UI_MAIN_REDRAW_MS;

  if (!force && !dirty_ && (now - lastDrawAt_ < interval)) {
    return;
  }

  if (!force && !dirty_ && currentScreen_ != ScreenType::QUESTION) {
    return;
  }

  lastDrawAt_ = now;

  if (currentScreen_ == ScreenType::QUESTION) {
    drawQuestionScreen(force);
    dirty_ = false;
    return;
  }

  drawMainScreen(force);
  dirty_ = false;
}

void TouchUi::drawMainScreen(bool force) {
  if (currentPage_ == Page::CANVAS) {
    if (!canvasInitialized_ || force) {
      tft_.fillScreen(kTheme.bg);
    }
    drawHeader();
    drawCanvasPage(force);
    return;
  }

  tft_.fillScreen(kTheme.bg);
  drawHeader();

  if (currentPage_ == Page::STATUS) {
    drawStatusPage();
  } else if (currentPage_ == Page::CONTROL) {
    drawControlPage();
  } else {
    drawCanvasPage(force);
  }
}

void TouchUi::drawQuestionScreen(bool force) {
  const uint32_t elapsed = millis() - questionStartTime_;
  float remaining = 1.0f - (static_cast<float>(elapsed) / UI_QUESTION_TIMEOUT_MS);
  if (remaining < 0.0f) {
    remaining = 0.0f;
  }

  if (!questionScreenInitialized_ || force || dirty_) {
    // Dimmed background effect
    tft_.fillRect(0, 0, tft_.width(), tft_.height(), TFT_BLACK);
    
    // Modal Box
    tft_.fillRoundRect(12, 16, 296, 208, 16, kTheme.panel);
    tft_.drawRoundRect(12, 16, 296, 208, 16, kTheme.aqua);
    tft_.drawRoundRect(13, 17, 294, 206, 15, kTheme.aqua);
    
    tft_.setTextColor(kTheme.aqua, kTheme.panel);
    tft_.setTextDatum(MC_DATUM);
    tft_.drawString("NOVA PERGUNTA", 160, 42, 4);

    tft_.setTextColor(kTheme.text, kTheme.panelAlt);
    tft_.fillRoundRect(24, 80, 272, 54, 8, kTheme.panelAlt);
    tft_.drawString(limitText(question_, 34), 160, 107, 2);

    const uint16_t optionColors[4] = {
      kTheme.green,
      kTheme.blue,
      kTheme.orange,
      kTheme.red,
    };
    for (uint8_t i = 0; i < questionOptionCount_; ++i) {
      int16_t rx = 0;
      int16_t ry = 0;
      int16_t rw = 0;
      int16_t rh = 0;
      if (!getQuestionOptionRect(i, &rx, &ry, &rw, &rh)) {
        continue;
      }
      const uint16_t fill = optionColors[i % 4];
      const String buttonLabel = limitText(questionOptionLabels_[i], 12);
      drawButton(rx, ry, rw, rh,
                 buttonLabel.c_str(),
                 fill, fill, i == 3 ? TFT_WHITE : kTheme.panel, false, 0);
    }
    
    tft_.setTextDatum(TL_DATUM);
    questionScreenInitialized_ = true;
    lastQuestionBarWidth_ = -1;
  }

  const int16_t barWidth = static_cast<int16_t>(272 * remaining);
  if (barWidth != lastQuestionBarWidth_) {
    tft_.fillRoundRect(24, 64, 272, 8, 4, kTheme.border);
    if (barWidth > 0) {
      tft_.fillRoundRect(24, 64, barWidth, 8, 4,
                         remaining > 0.45f ? kTheme.aqua
                                             : (remaining > 0.2f ? kTheme.yellow : kTheme.red));
    }
    lastQuestionBarWidth_ = barWidth;
  }
}

void TouchUi::drawHeader() {
  tft_.fillRect(0, 0, tft_.width(), kHeaderH, kTheme.panelAlt);
  tft_.drawFastHLine(0, kHeaderH, tft_.width(), kTheme.aqua);

  const bool statusSelected = currentPage_ == Page::STATUS;
  const bool controlSelected = currentPage_ == Page::CONTROL;
  const bool canvasSelected = currentPage_ == Page::CANVAS;

  drawButton(10, 8, 86, 20, "STATUS",
             statusSelected ? kTheme.aqua : kTheme.panelAlt,
             statusSelected ? kTheme.aqua : kTheme.panelAlt,
             statusSelected ? kTheme.panel : kTheme.muted, true);
  drawButton(104, 8, 102, 20, "CONTROLE",
             controlSelected ? kTheme.orange : kTheme.panelAlt,
             controlSelected ? kTheme.orange : kTheme.panelAlt,
             controlSelected ? kTheme.panel : kTheme.muted, true);
  drawButton(214, 8, 96, 20, "CANVAS",
             canvasSelected ? kTheme.blue : kTheme.panelAlt,
             canvasSelected ? kTheme.blue : kTheme.panelAlt,
             canvasSelected ? kTheme.panel : kTheme.muted, true);
}

void TouchUi::drawStatusPage() {
  tft_.setTextColor(kTheme.text, kTheme.bg);
  tft_.drawString(UI_TITLE, 16, 44, 4);

  tft_.fillRoundRect(16, 76, 288, 48, 10, kTheme.panel);
  tft_.drawRoundRect(16, 76, 288, 48, 10, connected_ ? kTheme.green : kTheme.border);
  if (connected_) {
    drawIconBluetooth(36, 100, kTheme.green);
    tft_.setTextColor(kTheme.green, kTheme.panel);
    tft_.drawString("Conectado ao App", 56, 92, 2);
  } else {
    drawIconBluetooth(36, 100, kTheme.muted);
    tft_.setTextColor(kTheme.muted, kTheme.panel);
    tft_.drawString("Aguardando Conexao", 56, 92, 2);
  }

  tft_.fillRoundRect(220, 84, 76, 32, 6, ledEnabled_ ? kTheme.yellow : kTheme.panelAlt);
  drawIconLed(236, 100, ledEnabled_, ledEnabled_ ? kTheme.panel : kTheme.muted);
  tft_.setTextColor(ledEnabled_ ? kTheme.panel : kTheme.muted, ledEnabled_ ? kTheme.yellow : kTheme.panelAlt);
  tft_.drawString(ledEnabled_ ? "ON" : "OFF", 252, 92, 2);

  tft_.fillRoundRect(16, 134, 288, 92, 10, kTheme.panel);
  
  tft_.setTextColor(kTheme.muted, kTheme.panel);
  tft_.drawString("RX", 28, 144, 2);
  tft_.setTextColor(kTheme.green, kTheme.panel);
  tft_.drawString(limitText(lastRx_, 26), 84, 144, 2);

  tft_.drawFastHLine(24, 164, 272, kTheme.border);
  tft_.setTextColor(kTheme.muted, kTheme.panel);
  tft_.drawString("TX", 28, 174, 2);
  tft_.setTextColor(kTheme.aqua, kTheme.panel);
  tft_.drawString(limitText(lastTx_, 26), 84, 174, 2);

  tft_.drawFastHLine(24, 194, 272, kTheme.border);
  tft_.setTextColor(kTheme.muted, kTheme.panel);
  tft_.drawString("TOQ", 28, 204, 2);
  tft_.setTextColor(kTheme.orange, kTheme.panel);
  tft_.drawString(limitText(lastAction_, 22), 84, 204, 2);
}

void TouchUi::drawControlPage() {
  tft_.setTextColor(kTheme.text, kTheme.bg);
  tft_.drawString("Sons & Acoes BLE", 16, 44, 4);

  drawButton(16, 88, 138, 48, "PING", kTheme.panel, kTheme.aqua, kTheme.text, false, 4);
  drawButton(166, 88, 138, 48, "LIGA", kTheme.panel, kTheme.green, kTheme.text, false, 2);
  drawButton(16, 146, 138, 48, "DESLIGA", kTheme.panel, kTheme.red, kTheme.text, false, 3);
  drawButton(166, 146, 138, 48, "LED?", kTheme.panel, kTheme.yellow, kTheme.text, false, 9);
  
  drawButton(16, 206, 138, 26, "Limpar log", kTheme.panelAlt, kTheme.border, kTheme.text, true, 7);
  drawButton(166, 206, 138, 26, "Reiniciar", kTheme.panelAlt, kTheme.orange, kTheme.text, true, 6);
}

void TouchUi::drawCanvasPage(bool force) {
  if (!canvasInitialized_ || force) {
    tft_.fillRect(0, kPageTop, tft_.width(), tft_.height() - kPageTop, kTheme.bg);
    drawCanvasToolbar();
    clearCanvas();
    canvasInitialized_ = true;
    return;
  }

  drawCanvasToolbar();
}

void TouchUi::drawCanvasToolbar() {
  tft_.fillRect(0, kPageTop, tft_.width(), kCanvasToolbarH, kTheme.panel);
  tft_.drawFastHLine(0, kPageTop + kCanvasToolbarH, tft_.width(), kTheme.blue);

  for (uint8_t i = 0; i < (sizeof(kSwatches) / sizeof(kSwatches[0])); ++i) {
    const bool selected = (kSwatches[i].color == activeColor_);
    tft_.fillRoundRect(kSwatches[i].x, kPageTop + 6, 20, 20, 5, kSwatches[i].color);
    tft_.drawRoundRect(kSwatches[i].x - 1, kPageTop + 5, 22, 22, 6,
                       selected ? TFT_WHITE : kTheme.border);
  }

  drawButton(208, kPageTop + 6, 18, 20, ".", kTheme.panelAlt,
             brushSize_ == 2 ? kTheme.yellow : kTheme.border, kTheme.text, true);
  drawButton(232, kPageTop + 6, 18, 20, "o", kTheme.panelAlt,
             brushSize_ == 4 ? kTheme.yellow : kTheme.border, kTheme.text, true);
  drawButton(256, kPageTop + 6, 18, 20, "O", kTheme.panelAlt,
             brushSize_ == 7 ? kTheme.yellow : kTheme.border, kTheme.text, true);
  drawButton(282, kPageTop + 3, 28, 26, "", kTheme.panelAlt, kTheme.red, kTheme.text, true, 7);

  tft_.fillRoundRect(174, kPageTop + 8, 24, 16, 6, TFT_BLACK);
  tft_.fillCircle(186, kPageTop + 16, brushSize_, activeColor_);
}

void TouchUi::clearCanvas() {
  tft_.fillRect(0, kCanvasY, tft_.width(), tft_.height() - kCanvasY, TFT_BLACK);
  tft_.drawRect(0, kCanvasY, tft_.width(), tft_.height() - kCanvasY, kTheme.border);
  lastDrawX_ = -1;
  lastDrawY_ = -1;
}

void TouchUi::drawStroke(int16_t x0, int16_t y0, int16_t x1, int16_t y1) {
  if (y1 < kCanvasY) {
    return;
  }

  if (x0 < 0 || y0 < 0) {
    tft_.fillCircle(x1, y1, brushSize_, activeColor_);
    return;
  }

  tft_.drawLine(x0, y0, x1, y1, activeColor_);
  tft_.fillCircle(x1, y1, brushSize_, activeColor_);
  tft_.fillCircle(x0, y0, brushSize_, activeColor_);
}

void TouchUi::drawButton(int16_t x, int16_t y, int16_t w, int16_t h,
                         const char* label, uint16_t fill, uint16_t border,
                         uint16_t textColor, bool isFlat, uint8_t icon) {
  if (isFlat) {
    tft_.fillRoundRect(x, y, w, h, 6, fill);
    if (border != fill) {
      tft_.drawRoundRect(x, y, w, h, 6, border);
    }
  } else {
    // Elegant shadow/glow approach for solid buttons
    tft_.fillRoundRect(x, y, w, h, 8, fill);
    tft_.drawRoundRect(x, y, w, h, 8, border);
    // Extra inset highlight
    tft_.drawRoundRect(x + 1, y + 1, w - 2, h - 2, 7, border);
  }
  
  int16_t textX = x + (w / 2);
  
  if (icon > 0) {
    if (label[0] != '\0') {
      textX += 8;
      drawIcon(icon, x + (w / 2) - 18, y + (h / 2), textColor);
    } else {
      drawIcon(icon, x + (w / 2), y + (h / 2), textColor);
    }
  }

  if (label[0] != '\0') {
    tft_.setTextColor(textColor, fill);
    tft_.setTextDatum(MC_DATUM);
    tft_.drawString(label, textX, y + (h / 2), 2);
    tft_.setTextDatum(TL_DATUM);
  }
}

void TouchUi::drawIcon(uint8_t iconIdx, int16_t x, int16_t y, uint16_t color) {
  switch (iconIdx) {
    case 1: drawIconBluetooth(x, y, color); break;
    case 2: drawIconLed(x, y, true, color); break;
    case 3: drawIconLed(x, y, false, color); break;
    case 4: drawIconPing(x, y, color); break;
    case 5: drawIconCheck(x, y, color); break;
    case 6: drawIconCross(x, y, color); break;
    case 7: drawIconClear(x, y, color); break;
    case 8: drawIconCalibrate(x, y, color); break;
    case 9: drawIconLed(x, y, true, color); break; 
  }
}

void TouchUi::drawIconBluetooth(int16_t x, int16_t y, uint16_t color) {
  // Symmetrical 1px base
  tft_.drawLine(x - 3, y - 3, x + 3, y + 3, color);
  tft_.drawLine(x + 3, y + 3, x, y + 6, color);
  tft_.drawLine(x, y + 6, x, y - 6, color);
  tft_.drawLine(x, y - 6, x + 3, y - 3, color);
  tft_.drawLine(x + 3, y - 3, x - 3, y + 3, color);

  // Offset X by +1 to make it 2px thick gracefully
  tft_.drawLine(x - 2, y - 3, x + 4, y + 3, color);
  tft_.drawLine(x + 4, y + 3, x + 1, y + 6, color);
  tft_.drawLine(x + 1, y + 6, x + 1, y - 6, color);
  tft_.drawLine(x + 1, y - 6, x + 4, y - 3, color);
  tft_.drawLine(x + 4, y - 3, x - 2, y + 3, color);
}

void TouchUi::drawIconLed(int16_t x, int16_t y, bool on, uint16_t color) {
  tft_.drawCircle(x, y - 2, 4, color);
  tft_.drawCircle(x, y - 2, 3, color);
  tft_.fillRect(x - 2, y + 2, 5, 4, color);
  tft_.drawLine(x - 1, y + 6, x + 1, y + 6, color);
  if (on) {
    tft_.drawLine(x, y - 9, x, y - 7, color);
    tft_.drawLine(x - 6, y - 5, x - 4, y - 4, color);
    tft_.drawLine(x + 6, y - 5, x + 4, y - 4, color);
  }
}

void TouchUi::drawIconPing(int16_t x, int16_t y, uint16_t color) {
  tft_.fillCircle(x, y + 4, 2, color);
  tft_.drawCircleHelper(x, y + 4, 6, 3, color);
  tft_.drawCircleHelper(x, y + 4, 7, 3, color);
  tft_.drawCircleHelper(x, y + 4, 10, 3, color);
  tft_.drawCircleHelper(x, y + 4, 11, 3, color);
}

void TouchUi::drawIconCheck(int16_t x, int16_t y, uint16_t color) {
  tft_.drawLine(x - 4, y, x - 1, y + 3, color);
  tft_.drawLine(x - 4, y + 1, x - 1, y + 4, color);
  tft_.drawLine(x - 4, y + 2, x - 1, y + 5, color);
  tft_.drawLine(x - 1, y + 3, x + 5, y - 3, color);
  tft_.drawLine(x - 1, y + 4, x + 5, y - 2, color);
  tft_.drawLine(x - 1, y + 5, x + 5, y - 1, color);
}

void TouchUi::drawIconCross(int16_t x, int16_t y, uint16_t color) {
  tft_.drawLine(x - 4, y - 4, x + 4, y + 4, color);
  tft_.drawLine(x - 4, y - 3, x + 3, y + 4, color);
  tft_.drawLine(x + 4, y - 4, x - 4, y + 4, color);
  tft_.drawLine(x + 4, y - 3, x - 3, y + 4, color);
}

void TouchUi::drawIconClear(int16_t x, int16_t y, uint16_t color) {
  tft_.drawRect(x - 3, y - 3, 7, 8, color);
  tft_.drawLine(x - 4, y - 3, x + 4, y - 3, color);
  tft_.drawLine(x - 1, y - 5, x + 1, y - 5, color);
  tft_.drawLine(x - 1, y - 1, x - 1, y + 3, color);
  tft_.drawLine(x + 1, y - 1, x + 1, y + 3, color);
}

void TouchUi::drawIconCalibrate(int16_t x, int16_t y, uint16_t color) {
  tft_.drawCircle(x, y, 3, color);
  tft_.drawCircle(x, y, 4, color);
  tft_.drawLine(x, y - 7, x, y - 2, color);
  tft_.drawLine(x, y + 7, x, y + 2, color);
  tft_.drawLine(x - 7, y, x - 2, y, color);
  tft_.drawLine(x + 7, y, x + 2, y, color);
}

String TouchUi::limitText(const String& text, size_t maxLen) const {
  if (text.length() <= maxLen) {
    return text;
  }

  if (maxLen <= 3) {
    return text.substring(0, maxLen);
  }

  return text.substring(0, maxLen - 3) + "...";
}
