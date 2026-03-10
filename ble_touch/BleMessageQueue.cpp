#include "BleMessageQueue.h"

namespace {
size_t safeLength(const char* data, size_t maxLen) {
  if (data == nullptr) {
    return 0;
  }
  size_t len = 0;
  while (len < maxLen && data[len] != '\0') {
    len++;
  }
  return len;
}
}

BleMessageQueue::BleMessageQueue()
    : _head(0), _tail(0), _count(0) {}

bool BleMessageQueue::push(const char* message) {
  if (isFull() || message == nullptr) {
    return false;
  }

  BleMessage& slot = _messages[_tail];
  const size_t maxLen = sizeof(slot.payload) - 1;
  const size_t len = safeLength(message, maxLen);

  memcpy(slot.payload, message, len);
  slot.payload[len] = '\0';
  slot.length = len;

  _tail = static_cast<uint8_t>((_tail + 1) % kMaxMessages);
  _count++;
  return true;
}

bool BleMessageQueue::pop(BleMessage& out) {
  if (isEmpty()) {
    return false;
  }

  const BleMessage& slot = _messages[_head];
  const size_t maxLen = sizeof(out.payload) - 1;
  const size_t len = slot.length < maxLen ? slot.length : maxLen;

  memcpy(out.payload, slot.payload, len);
  out.payload[len] = '\0';
  out.length = len;

  _head = static_cast<uint8_t>((_head + 1) % kMaxMessages);
  _count--;
  return true;
}

bool BleMessageQueue::isEmpty() const {
  return _count == 0;
}

bool BleMessageQueue::isFull() const {
  return _count >= kMaxMessages;
}
