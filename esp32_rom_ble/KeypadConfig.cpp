#include "KeypadConfig.h"

const byte kKeypadRows = 4;
const byte kKeypadCols = 4;

const byte kRowPins[4] = {27, 14, 12, 13};
const byte kColPins[4] = {25, 26, 32, 33};

const char* kButtonNames[16] = {
  "S1", "S2", "S3", "S4",
  "S5", "S6", "S7", "S8",
  "S9", "S10", "S11", "S12",
  "S13", "S14", "S15", "S16"
};

const uint32_t kLongPressMs = 2000;
