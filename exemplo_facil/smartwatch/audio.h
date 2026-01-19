#ifndef AUDIO_H
#define AUDIO_H

#include "config.h"
#include <Arduino.h>

// ==========================================
// MÓDULO DE ÁUDIO - Gravação e Streaming
// ==========================================

// Estados
bool gravandoAudio = false;
bool streamingAudio = false;
unsigned long lastStreamSampleMicros = 0;
uint8_t streamChunkBuf[AUDIO_CHUNK_SIZE];
int streamPos = 0;
uint32_t streamChunkIdx = 0;

// Buffer de áudio
uint8_t audioBuffer[BUFFER_SIZE];
unsigned long inicioGravacao = 0;
int indiceBuffer = 0;

// Funções públicas
void initAudio();
void updateAudio();
void startStreaming();
void stopStreaming();
bool isAudioActive();
void enviarChunkStreaming();

// Função auxiliar para codificação base64
String encodeBase64(const String& input);

// ===== IMPLEMENTAÇÃO =====

String encodeBase64(const String& input) {
  const char base64_chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  String result;
  int i = 0;
  int j = 0;
  unsigned char char_array_3[3];
  unsigned char char_array_4[4];
  int in_len = input.length();
  const char* bytes_to_encode = input.c_str();

  while (in_len--) {
    char_array_3[i++] = *(bytes_to_encode++);
    if (i == 3) {
      char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
      char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
      char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
      char_array_4[3] = char_array_3[2] & 0x3f;

      for (i = 0; i < 4; i++)
        result += base64_chars[char_array_4[i]];
      i = 0;
    }
  }

  if (i) {
    for (j = i; j < 3; j++)
      char_array_3[j] = '\0';

    char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
    char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
    char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
    char_array_4[3] = char_array_3[2] & 0x3f;

    for (j = 0; j < i + 1; j++)
      result += base64_chars[char_array_4[j]];

    while ((i++ < 3))
      result += '=';
  }

  return result;
}

void initAudio() {
  pinMode(MIC_PIN, INPUT);
  Serial.println("Audio inicializado");
}

bool isAudioActive() {
  return gravandoAudio || streamingAudio;
}

void startStreaming() {
  streamingAudio = true;
  streamPos = 0;
  streamChunkIdx = 0;
  lastStreamSampleMicros = micros();
  Serial.println("Streaming iniciado");
}

void stopStreaming() {
  streamingAudio = false;
  Serial.println("Streaming parado");
}

void updateAudio() {
  if (!streamingAudio) return;

  unsigned long nowMicros = micros();
  unsigned long tempoDesdeUltimaAmostra;
  
  if (nowMicros >= lastStreamSampleMicros) {
    tempoDesdeUltimaAmostra = nowMicros - lastStreamSampleMicros;
  } else {
    tempoDesdeUltimaAmostra = (0xFFFFFFFF - lastStreamSampleMicros) + nowMicros;
  }
  
  unsigned long tempoEntreAmostras = 1000000UL / SAMPLE_RATE;
  
  if (tempoDesdeUltimaAmostra >= tempoEntreAmostras) {
    lastStreamSampleMicros = nowMicros;

    // Captura amostra de áudio
    int leitura = analogRead(MIC_PIN);
    uint8_t amostra = leitura >> 4; // Converte para 8 bits
    streamChunkBuf[streamPos++] = amostra;

    // Envia chunk quando estiver cheio
    if (streamPos >= AUDIO_CHUNK_SIZE) {
      enviarChunkStreaming();
    }
  }
}

void enviarChunkStreaming() {
  if (streamPos == 0) return;

  // Converte buffer em string e codifica base64
  String raw = "";
  for (int i = 0; i < streamPos; i++) {
    raw += (char)streamChunkBuf[i];
  }

  String encoded = encodeBase64(raw);
  String pacote = "audio|" + String(streamChunkIdx++) + "|-1|" + encoded;
  
  // Envia via WebSocket (precisa ser externo)
  // webSocket.sendTXT(pacote);
  
  Serial.printf("Chunk #%d enviado (%d bytes)\n", streamChunkIdx - 1, streamPos);
  streamPos = 0;
}

#endif // AUDIO_H

