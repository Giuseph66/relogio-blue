#include "KeypadController.h"

namespace {
char keymapKeys[4][4] = {
  {'1', '2', '3', '4'},
  {'5', '6', '7', '8'},
  {'9', 'A', 'B', 'C'},
  {'D', 'E', 'F', 'G'}
};

byte rowPins[4] = {27, 14, 12, 13};
byte colPins[4] = {25, 26, 32, 33};
}

KeypadController::KeypadController()
    : _keypad(makeKeymap(keymapKeys), rowPins, colPins, kKeypadRows, kKeypadCols) {
  for (int i = 0; i < 16; ++i) {
    _pressStart[i] = 0;
    _pressed[i] = false;
  }
}

void KeypadController::begin() {
  _keypad.setDebounceTime(50);
  _keypad.setHoldTime(kLongPressMs);
}

bool KeypadController::poll(ButtonEvent& event) {
  if (!_keypad.getKeys()) {
    return false;
  }

  for (int i = 0; i < LIST_MAX; ++i) {
    if (_keypad.key[i].kchar == NO_KEY) {
      continue;
    }

    char keyChar = _keypad.key[i].kchar;
    KeyState keyState = _keypad.key[i].kstate;
    const int index = mapKey(keyChar);
    if (index < 0 || index >= 16) {
      continue;
    }

    if (keyState == PRESSED) {
      _pressed[index] = true;
      _pressStart[index] = millis();
    } else if (keyState == RELEASED) {
      unsigned long duration = 0;
      if (_pressed[index]) {
        duration = millis() - _pressStart[index];
        _pressed[index] = false;
      }

      event.name = kButtonNames[index];
      event.key = keyChar;
      event.longPress = duration >= kLongPressMs;
      return true;
    }
  }

  return false;
}

int KeypadController::mapKey(char key) const {
  for (int r = 0; r < kKeypadRows; ++r) {
    for (int c = 0; c < kKeypadCols; ++c) {
      if (keymapKeys[r][c] == key) {
        return r * kKeypadCols + c;
      }
    }
  }
  return -1;
}
