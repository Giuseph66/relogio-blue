#ifndef KEYPAD_CONFIG_H
#define KEYPAD_CONFIG_H

#include <Arduino.h>

extern const byte kKeypadRows;
extern const byte kKeypadCols;
extern const byte kRowPins[4];
extern const byte kColPins[4];
extern const char* kButtonNames[16];
extern const uint32_t kLongPressMs;

#endif
