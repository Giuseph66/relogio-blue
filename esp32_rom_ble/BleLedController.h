#ifndef BLE_LED_CONTROLLER_H
#define BLE_LED_CONTROLLER_H

#include <Arduino.h>

class BleLedController {
 public:
  BleLedController(int pin, bool activeHigh);
  void begin();
  void setEnabled(bool enabled);
  bool isEnabled() const;

 private:
  int _pin;
  bool _activeHigh;
  bool _enabled;

  void writePin(bool enabled);
};

#endif
