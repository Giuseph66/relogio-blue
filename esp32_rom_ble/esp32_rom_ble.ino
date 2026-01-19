#include <Arduino.h>
#include "BleConfig.h"
#include "BleServerAdapter.h"
#include "BleInteractor.h"
#include "BleLedController.h"
#include "TftUi.h"
#include "KeypadController.h"

BleConfig config = defaultBleConfig();
BleServerAdapter bleAdapter(config);
BleLedController ledController(config.ledPin, config.ledActiveHigh);
TftUi ui;
KeypadController keypad;
BleInteractor bleInteractor(config, &bleAdapter, &ledController, &ui);

void setup() {
  Serial.begin(115200);
  delay(200);

  ledController.begin();
  ui.begin();
  keypad.begin();

  bleAdapter.setWriteHandler(&bleInteractor);
  bleAdapter.begin();

  Serial.println("ESP32 BLE pronto");
}

void loop() {
  ButtonEvent event;
  if (keypad.poll(event)) {
    bleInteractor.handleButtonEvent(event.name, event.longPress);
  }

  bleInteractor.tick();
  ui.update();
  delay(10);
}
