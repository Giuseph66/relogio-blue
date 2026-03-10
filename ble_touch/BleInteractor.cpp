#include "BleInteractor.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

#include "UiConfig.h"

namespace {
constexpr size_t kBleTextBufferSize = 256;
constexpr uint8_t kMaxQuestionOptions = 4;
constexpr size_t kQuestionIdSize = 24;
constexpr size_t kQuestionTextSize = 72;
constexpr size_t kOptionFieldSize = 20;

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

size_t trimWhitespace(char* text) {
  if (text == nullptr) {
    return 0;
  }

  size_t len = strlen(text);
  while (len > 0 && isspace(static_cast<unsigned char>(text[len - 1]))) {
    text[len - 1] = '\0';
    --len;
  }

  return len;
}

bool copyText(char* target, size_t targetSize, const char* source) {
  if (target == nullptr || targetSize == 0 || source == nullptr) {
    return false;
  }

  const size_t len = strlen(source);
  if (len >= targetSize) {
    return false;
  }

  memcpy(target, source, len);
  target[len] = '\0';
  return true;
}

bool parseStructuredQuestionMessage(char* message,
                                    char* questionId,
                                    size_t questionIdSize,
                                    char* questionText,
                                    size_t questionTextSize,
                                    char optionIds[][kOptionFieldSize],
                                    char optionLabels[][kOptionFieldSize],
                                    uint8_t* optionCount) {
  if (message == nullptr || strncmp(message, "QST|", 4) != 0) {
    return false;
  }

  char buffer[kBleTextBufferSize];
  if (!copyText(buffer, sizeof(buffer), message)) {
    return false;
  }

  char* savePtr = nullptr;
  char* token = strtok_r(buffer, "|", &savePtr);
  if (token == nullptr || strcmp(token, "QST") != 0) {
    return false;
  }

  char* idToken = strtok_r(nullptr, "|", &savePtr);
  char* questionToken = strtok_r(nullptr, "|", &savePtr);
  if (idToken == nullptr || questionToken == nullptr) {
    return false;
  }

  if (!copyText(questionId, questionIdSize, idToken) ||
      !copyText(questionText, questionTextSize, questionToken)) {
    return false;
  }

  uint8_t count = 0;
  while (count < kMaxQuestionOptions) {
    char* optionToken = strtok_r(nullptr, "|", &savePtr);
    if (optionToken == nullptr) {
      break;
    }

    char* separator = strchr(optionToken, ':');
    if (separator == nullptr) {
      return false;
    }

    *separator = '\0';
    const char* id = optionToken;
    const char* label = separator + 1;
    if (id[0] == '\0' || label[0] == '\0') {
      return false;
    }

    if (!copyText(optionIds[count], kOptionFieldSize, id) ||
        !copyText(optionLabels[count], kOptionFieldSize, label)) {
      return false;
    }
    ++count;
  }

  if (count < 2) {
    return false;
  }

  if (optionCount != nullptr) {
    *optionCount = count;
  }

  return true;
}

}  // namespace

BleInteractor::BleInteractor(
    const BleConfig& config,
    BleNotifier* notifier,
    BleLedController* ledController,
    BleUi* ui)
    : config_(config),
      notifier_(notifier),
      ledController_(ledController),
      ui_(ui),
      queue_(),
      connected_(false),
      lastNotifyAt_(0),
      tickCounter_(0),
      awaitingAnswer_(false),
      awaitingStructuredAnswer_(false),
      questionStartTime_(0),
      activeQuestionId_{0},
      activeOptionIds_{{0}},
      activeOptionLabels_{{0}},
      activeOptionCount_(0) {}

void BleInteractor::onWrite(const uint8_t* data, size_t len) {
  char buffer[kBleTextBufferSize];
  const size_t copyLen = safeCopy(buffer, sizeof(buffer), data, len);
  if (copyLen == 0) {
    return;
  }

  Serial.print("RX BLE: ");
  Serial.println(buffer);

  if (ui_ != nullptr) {
    ui_->setLastRx(buffer);
  }

  processText(buffer, true);
}

void BleInteractor::onConnectionChanged(bool connected) {
  connected_ = connected;

  if (ui_ != nullptr) {
    ui_->setConnected(connected);
    if (!connected) {
      ui_->setScreen(ScreenType::MAIN);
    }
  }

  if (!connected) {
    clearActiveQuestion();
    Serial.println("BLE desconectado");
    return;
  }

  Serial.println("BLE conectado");
  if (ledController_ != nullptr) {
    if (ui_ != nullptr) {
      ui_->setLedEnabled(ledController_->isEnabled());
    }
    enqueueText(ledController_->isEnabled() ? "LED:ON" : "LED:OFF", true);
  }
  enqueueText("ESP32 conectado", true);
}

void BleInteractor::tick() {
  const uint32_t now = millis();

  if (awaitingAnswer_ && (now - questionStartTime_ >= UI_QUESTION_TIMEOUT_MS)) {
    if (awaitingStructuredAnswer_ && activeQuestionId_[0] != '\0') {
      char timeoutMessage[64];
      snprintf(timeoutMessage, sizeof(timeoutMessage), "QERR|%s|TIMEOUT", activeQuestionId_);
      enqueueText(timeoutMessage, true);
    } else {
      enqueueText("Vacoooo(504)", true);
    }
    clearActiveQuestion();
    if (ui_ != nullptr) {
      ui_->setScreen(ScreenType::MAIN);
    }
  }

  if (notifier_ != nullptr && notifier_->isConnected() && config_.notifyIntervalMs > 0 &&
      (now - lastNotifyAt_ >= config_.notifyIntervalMs)) {
    lastNotifyAt_ = now;
    ++tickCounter_;
    char message[32];
    snprintf(message, sizeof(message), "tick: %lu", static_cast<unsigned long>(tickCounter_));
    enqueueText(message, false);
  }

  flushQueue();
}

void BleInteractor::handleLocalCommand(const char* command) {
  if (command == nullptr) {
    return;
  }

  char buffer[kBleTextBufferSize];
  const size_t len = strlen(command);
  const size_t copyLen = (len < (sizeof(buffer) - 1)) ? len : (sizeof(buffer) - 1);
  memcpy(buffer, command, copyLen);
  buffer[copyLen] = '\0';

  if (ui_ != nullptr) {
    ui_->setLastButton(command, false);
  }

  processText(buffer, false);
}

void BleInteractor::processText(char* message, bool fromBle) {
  if (message == nullptr) {
    return;
  }

  const size_t trimmedLen = trimWhitespace(message);
  if (trimmedLen == 0) {
    return;
  }

  if (handleStructuredQuestion(message)) {
    return;
  }

  if (awaitingAnswer_ && handleAnswer(message)) {
    return;
  }

  if (message[trimmedLen - 1] == '?') {
    clearActiveQuestion();
    message[trimmedLen - 1] = '\0';
    trimWhitespace(message);
    if (ui_ != nullptr) {
      ui_->setQuestion(message);
      ui_->setScreen(ScreenType::QUESTION);
    }
    awaitingAnswer_ = true;
    awaitingStructuredAnswer_ = false;
    questionStartTime_ = millis();
    return;
  }

  if (strcmp(message, "PING") == 0) {
    enqueueText("PONG", true);
    return;
  }

  if (strcmp(message, "LED_ON") == 0) {
    if (ledController_ != nullptr) {
      ledController_->setEnabled(true);
      if (ui_ != nullptr) {
        ui_->setLedEnabled(true);
      }
      enqueueText("LED:ON", true);
    } else {
      enqueueText("LED:UNAVAILABLE", true);
    }
    return;
  }

  if (strcmp(message, "LED_OFF") == 0) {
    if (ledController_ != nullptr) {
      ledController_->setEnabled(false);
      if (ui_ != nullptr) {
        ui_->setLedEnabled(false);
      }
      enqueueText("LED:OFF", true);
    } else {
      enqueueText("LED:UNAVAILABLE", true);
    }
    return;
  }

  if (strcmp(message, "LED_STATUS") == 0) {
    if (ledController_ != nullptr) {
      if (ui_ != nullptr) {
        ui_->setLedEnabled(ledController_->isEnabled());
      }
      enqueueText(ledController_->isEnabled() ? "LED:ON" : "LED:OFF", true);
    } else {
      enqueueText("LED:UNAVAILABLE", true);
    }
    return;
  }

  char reply[256];
  snprintf(reply, sizeof(reply), fromBle ? "OK: %s" : "TOUCH: %s", message);
  enqueueText(reply, true);
}

bool BleInteractor::handleAnswer(const char* message) {
  if (message == nullptr || !awaitingAnswer_) {
    return false;
  }

  if (awaitingStructuredAnswer_) {
    for (uint8_t i = 0; i < activeOptionCount_; ++i) {
      if (strcmp(message, activeOptionIds_[i]) != 0) {
        continue;
      }

      char response[64];
      snprintf(response, sizeof(response), "QANS|%s|%s", activeQuestionId_, activeOptionIds_[i]);
      enqueueText(response, true);
      clearActiveQuestion();
      if (ui_ != nullptr) {
        ui_->setScreen(ScreenType::MAIN);
      }
      return true;
    }
    return false;
  }

  if (strcmp(message, "SIM") != 0 && strcmp(message, "NAO") != 0) {
    return false;
  }

  clearActiveQuestion();
  enqueueText(message, true);
  if (ui_ != nullptr) {
    ui_->setScreen(ScreenType::MAIN);
  }
  return true;
}

bool BleInteractor::handleStructuredQuestion(char* message) {
  if (message == nullptr) {
    return false;
  }

  if (strncmp(message, "QST|", 4) != 0) {
    return false;
  }

  char questionId[kQuestionIdSize];
  char questionText[kQuestionTextSize];
  char optionIds[kMaxQuestionOptions][kOptionFieldSize] = {{0}};
  char optionLabels[kMaxQuestionOptions][kOptionFieldSize] = {{0}};
  uint8_t optionCount = 0;

  if (!parseStructuredQuestionMessage(message,
                                      questionId,
                                      sizeof(questionId),
                                      questionText,
                                      sizeof(questionText),
                                      optionIds,
                                      optionLabels,
                                      &optionCount)) {
    enqueueText("QERR|unknown|INVALID_FORMAT", true);
    return true;
  }

  clearActiveQuestion();
  copyText(activeQuestionId_, sizeof(activeQuestionId_), questionId);
  activeOptionCount_ = optionCount;
  for (uint8_t i = 0; i < optionCount; ++i) {
    copyText(activeOptionIds_[i], sizeof(activeOptionIds_[i]), optionIds[i]);
    copyText(activeOptionLabels_[i], sizeof(activeOptionLabels_[i]), optionLabels[i]);
  }

  if (ui_ != nullptr) {
    const char* uiOptionIds[kMaxQuestionOptions] = {nullptr, nullptr, nullptr, nullptr};
    const char* uiOptionLabels[kMaxQuestionOptions] = {nullptr, nullptr, nullptr, nullptr};
    for (uint8_t i = 0; i < optionCount; ++i) {
      uiOptionIds[i] = activeOptionIds_[i];
      uiOptionLabels[i] = activeOptionLabels_[i];
    }
    ui_->setQuestionPrompt(activeQuestionId_, questionText, uiOptionIds, uiOptionLabels, optionCount);
    ui_->setScreen(ScreenType::QUESTION);
  }

  awaitingAnswer_ = true;
  awaitingStructuredAnswer_ = true;
  questionStartTime_ = millis();
  return true;
}

void BleInteractor::clearActiveQuestion() {
  awaitingAnswer_ = false;
  awaitingStructuredAnswer_ = false;
  activeQuestionId_[0] = '\0';
  activeOptionCount_ = 0;
  for (uint8_t i = 0; i < kMaxQuestionOptions; ++i) {
    activeOptionIds_[i][0] = '\0';
    activeOptionLabels_[i][0] = '\0';
  }
}

void BleInteractor::enqueueText(const char* message, bool updateUi) {
  if (message == nullptr) {
    return;
  }

  if (queue_.push(message) && updateUi && ui_ != nullptr) {
    ui_->setLastTx(message);
  }
}

void BleInteractor::flushQueue() {
  if (!connected_ || notifier_ == nullptr) {
    return;
  }

  BleMessage message;
  while (queue_.pop(message)) {
    Serial.print("TX BLE: ");
    Serial.println(message.payload);
    notifier_->notify(reinterpret_cast<const uint8_t*>(message.payload), message.length);
    delay(5);
  }
}
