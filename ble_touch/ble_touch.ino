#include <Arduino.h>

#include "BleConfig.h"
#include "BleInteractor.h"
#include "BleLedController.h"
#include "BleServerAdapter.h"
#include "TouchUi.h"

BleConfig config = defaultBleConfig();
BleServerAdapter bleAdapter(config);
BleLedController ledController(config.ledPin, config.ledActiveHigh);
TouchUi ui;
BleInteractor bleInteractor(config, &bleAdapter, &ledController, &ui);

void setup() {
  Serial.begin(115200);
  delay(200);

  ledController.begin();
  ui.begin();
  ui.setLedEnabled(ledController.isEnabled());

  bleAdapter.setWriteHandler(&bleInteractor);
  bleAdapter.begin();

  Serial.println("BLE Touch pronto");
}

void loop() {
  ui.update();

  char action[48];
  if (ui.pollAction(action, sizeof(action))) {
    bleInteractor.handleLocalCommand(action);
  }

  bleInteractor.tick();
  delay(10);
}
