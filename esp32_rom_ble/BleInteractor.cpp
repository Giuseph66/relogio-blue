#include "BleInteractor.h"

namespace {
size_t safeCopy(char* target, size_t targetSize, const uint8_t* data, size_t len) {
  if (target == nullptr || targetSize == 0 || data == nullptr || len == 0) {
    return 0;
  }
  const size_t maxLen = targetSize - 1;
  const size_t copyLen = len < maxLen ? len : maxLen;
  memcpy(target, data, copyLen);
  target[copyLen] = '\0';
  return copyLen;
}
}

BleInteractor::BleInteractor(
    const BleConfig& config,
    BleNotifier* notifier,
    BleLedController* ledController,
    BleUi* ui)
    : _config(config),
      _notifier(notifier),
      _ledController(ledController),
      _ui(ui),
      _connected(false),
      _lastNotifyAt(0),
      _tickCounter(0) {}

void BleInteractor::onWrite(const uint8_t* data, size_t len) {
  char buffer[96];
  const size_t copyLen = safeCopy(buffer, sizeof(buffer), data, len);
  if (copyLen == 0) {
    return;
  }

  Serial.print("RX: ");
  Serial.print(buffer);
  Serial.print(" (");
  Serial.print(copyLen);
  Serial.println(" bytes)");
  if (_ui != nullptr) {
    _ui->setLastRx(buffer);
  }

  if (strcmp(buffer, "PING") == 0) {
    enqueueText("PONG", true);
    return;
  }

  if (strcmp(buffer, "LED_ON") == 0) {
    if (_ledController != nullptr) {
      _ledController->setEnabled(true);
      Serial.println("LED ligado");
      enqueueText("LED:ON", true);
    } else {
      enqueueText("LED:UNAVAILABLE", true);
    }
    return;
  }

  if (strcmp(buffer, "LED_OFF") == 0) {
    if (_ledController != nullptr) {
      _ledController->setEnabled(false);
      Serial.println("LED desligado");
      enqueueText("LED:OFF", true);
    } else {
      enqueueText("LED:UNAVAILABLE", true);
    }
    return;
  }

  if (strcmp(buffer, "LED_STATUS") == 0) {
    if (_ledController != nullptr) {
      enqueueText(_ledController->isEnabled() ? "LED:ON" : "LED:OFF", true);
    } else {
      enqueueText("LED:UNAVAILABLE", true);
    }
    return;
  }

  char reply[128];
  snprintf(reply, sizeof(reply), "OK: %s", buffer);
  enqueueText(reply, true);
}

void BleInteractor::onConnectionChanged(bool connected) {
  _connected = connected;
  if (_ui != nullptr) {
    _ui->setConnected(connected);
  }
  if (connected) {
    Serial.println("BLE conectado");
    if (_ledController != nullptr) {
      enqueueText(_ledController->isEnabled() ? "LED:ON" : "LED:OFF", true);
    }
    enqueueText("ESP32 conectado", true);
  } else {
    Serial.println("BLE desconectado");
  }
}

void BleInteractor::tick() {
  if (_notifier == nullptr || !_notifier->isConnected()) {
    return;
  }

  if (_config.notifyIntervalMs > 0) {
    const uint32_t now = millis();
    if (now - _lastNotifyAt >= _config.notifyIntervalMs) {
      _lastNotifyAt = now;
      _tickCounter++;
      char message[32];
      snprintf(message, sizeof(message), "tick: %lu", static_cast<unsigned long>(_tickCounter));
      enqueueText(message, false);
    }
  }

  flushQueue();
}

void BleInteractor::enqueueText(const char* message, bool updateUi) {
  if (message == nullptr) {
    return;
  }

  if (_queue.push(message) && updateUi && _ui != nullptr) {
    _ui->setLastTx(message);
  }
}

void BleInteractor::flushQueue() {
  if (!_connected || _notifier == nullptr) {
    return;
  }

  BleMessage message;
  while (_queue.pop(message)) {
    Serial.print("TX: ");
    Serial.print(message.payload);
    Serial.print(" (");
    Serial.print(message.length);
    Serial.println(" bytes)");
    _notifier->notify(reinterpret_cast<const uint8_t*>(message.payload), message.length);
    delay(5);
  }
}

void BleInteractor::handleButtonEvent(const char* buttonName, bool longPress) {
  if (buttonName == nullptr) {
    return;
  }

  char message[32];
  if (longPress) {
    snprintf(message, sizeof(message), "BTN:%s_LONG", buttonName);
  } else {
    snprintf(message, sizeof(message), "BTN:%s", buttonName);
  }

  if (_ui != nullptr) {
    _ui->setLastButton(buttonName, longPress);
  }

  enqueueText(message, true);
}
