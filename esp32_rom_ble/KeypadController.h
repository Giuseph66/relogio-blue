#ifndef KEYPAD_CONTROLLER_H
#define KEYPAD_CONTROLLER_H

#include <Arduino.h>
#include <Keypad.h>
#include "KeypadConfig.h"

struct ButtonEvent {
  const char* name;
  char key;
  bool longPress;
};

class KeypadController {
 public:
  KeypadController();
  void begin();
  bool poll(ButtonEvent& event);

 private:
  int mapKey(char key) const;

  Keypad _keypad;
  unsigned long _pressStart[16];
  bool _pressed[16];
};

#endif
