#ifndef BLE_MESSAGE_QUEUE_H
#define BLE_MESSAGE_QUEUE_H

#include <Arduino.h>

struct BleMessage {
  char payload[128];
  size_t length;
};

class BleMessageQueue {
 public:
  BleMessageQueue();
  bool push(const char* message);
  bool pop(BleMessage& out);
  bool isEmpty() const;
  bool isFull() const;

 private:
  static const uint8_t kMaxMessages = 8;
  BleMessage _messages[kMaxMessages];
  uint8_t _head;
  uint8_t _tail;
  uint8_t _count;
};

#endif
