#include "BleLedController.h"

BleLedController::BleLedController(int pin, bool activeHigh)
    : _pin(pin), _activeHigh(activeHigh), _enabled(false) {}

void BleLedController::begin() {
  if (_pin < 0) {
    return;
  }

  pinMode(_pin, OUTPUT);
  writePin(false);
}

void BleLedController::setEnabled(bool enabled) {
  _enabled = enabled;
  writePin(enabled);
}

bool BleLedController::isEnabled() const {
  return _enabled;
}

void BleLedController::writePin(bool enabled) {
  if (_pin < 0) {
    return;
  }

  const bool level = _activeHigh ? enabled : !enabled;
  digitalWrite(_pin, level ? HIGH : LOW);
}
