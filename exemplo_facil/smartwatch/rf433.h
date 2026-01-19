#ifndef RF433_H
#define RF433_H

#include "config.h"
#include <HardwareSerial.h>
// Protocolo RAW personalizado
#define PROTO_IR_RAW 200

// ==========================================
// MÓDULO DE COMUNICAÇÃO RF433 - ESP32 ↔ Arduino
// ==========================================

// Estrutura para códigos RF/IR salvos (suporta dados RAW no ESP)
struct SavedCode {
  unsigned long value;
  unsigned int bitlen;
  unsigned int delayUs;
  unsigned int proto;

  // Campos adicionais para sinais RAW (IR PulseDistance)
  uint16_t *rawBuf;   // alocado dinamicamente no ESP
  uint16_t rawLen;    // número de entradas no rawBuf
  uint16_t rawFreq;   // frequência em kHz
};

// Buffer para códigos recebidos do Arduino
#define MAX_RF_CODES 10
extern SavedCode rfCodes[MAX_RF_CODES];
extern int rfCodesCount;

// Estados do módulo RF433
enum RF433State {
  RF433_DISCONNECTED,
  RF433_CONNECTED,
  RF433_WAITING_RESPONSE,
  RF433_LEARNING
};
extern RF433State rf433State;

// Serial para comunicação com Arduino
extern HardwareSerial rfSerial;

// Buffer para respostas do Arduino
#define RF433_BUFFER_SIZE 256
extern char rfBuffer[RF433_BUFFER_SIZE];
extern int rfBufferIndex;
extern unsigned long lastRFCommand;

// Timeout para comandos (2 segundos)
#define RF433_COMMAND_TIMEOUT 2000

// Funções públicas
void initRF433();
void updateRF433();
bool sendRFCode(int index);
bool sendRFCodeRaw(unsigned long code, unsigned int bitlen, unsigned int delayUs, unsigned int proto);
bool listRFCodes();
bool clearRFCodes();
bool learnRFCode();
bool getRFStatus();
SavedCode* getRFCodes();
int getRFCodesCount();
bool isRF433Connected();

// Funções para IR (filtros sobre rfCodes)
int getIRCodesCount();
SavedCode* getIRCodes();
// Retorna índice global em rfCodes[] para o enésimo código IR (0-based), ou -1
int getIRGlobalIndex(int irIndex);

// Funções auxiliares
void sendRFCommand(const char* cmd);
void processRFResponse(const char* response);
void parseRFCodesList(const char* data);

// Callback para quando novo código é aprendido
typedef void (*RFCodeLearnedCallback)(SavedCode code);
extern RFCodeLearnedCallback rfCodeLearnedCallback;
void setRFCodeLearnedCallback(RFCodeLearnedCallback callback);

// ===== IMPLEMENTAÇÃO =====

// Variáveis globais
SavedCode rfCodes[MAX_RF_CODES];
int rfCodesCount = 0;
RF433State rf433State = RF433_DISCONNECTED;
HardwareSerial rfSerial(2); // Serial2
char rfBuffer[RF433_BUFFER_SIZE];
int rfBufferIndex = 0;
unsigned long lastRFCommand = 0;
RFCodeLearnedCallback rfCodeLearnedCallback = nullptr;
// Cache de códigos IR (subset de rfCodes com proto >= 100)
static SavedCode irCodesCache[MAX_RF_CODES];
static int irCodesCountCache = 0;
// Temporários para receber RAW via Serial (chunked by Arduino)
static uint16_t *currentRawBuf = NULL;
static uint16_t currentRawLen = 0;
static uint16_t currentRawCollected = 0;
static uint16_t currentRawFreq = 38;
static bool receivingRaw = false;
// Timestamps para gerenciamento / substituição de entradas (ms)
static unsigned long rfCodeTimestamp[MAX_RF_CODES];

// Atualiza cache de códigos IR
static void updateIRCache() {
  irCodesCountCache = 0;
  for (int i = 0; i < rfCodesCount && irCodesCountCache < MAX_RF_CODES; ++i) {
    if (rfCodes[i].proto >= 100) {
      irCodesCache[irCodesCountCache++] = rfCodes[i];
    }
  }
}

void initRF433() {
  // Inicializa Serial2 para comunicação com Arduino
  rfSerial.begin(RF433_BAUD_RATE, SERIAL_8N1, RF433_SERIAL_RX, RF433_SERIAL_TX);
  rf433State = RF433_DISCONNECTED;

  Serial.println("RF433: Inicializando comunicação com Arduino...");

  // Limpa buffer
  memset(rfBuffer, 0, RF433_BUFFER_SIZE);
  rfBufferIndex = 0;

  // Inicializa rfCodes
  for (int i = 0; i < MAX_RF_CODES; ++i) {
    rfCodes[i].value = 0;
    rfCodes[i].bitlen = 0;
    rfCodes[i].delayUs = 0;
    rfCodes[i].proto = 0;
    rfCodes[i].rawBuf = NULL;
    rfCodes[i].rawLen = 0;
    rfCodes[i].rawFreq = 0;
    rfCodeTimestamp[i] = 0;
  }
  rfCodesCount = 0;

  // Testa conexão
  getRFStatus();
}

void updateRF433() {
  // Lê dados da Serial do Arduino
  while (rfSerial.available()) {
    char c = rfSerial.read();

    if (c == '\n' || rfBufferIndex >= RF433_BUFFER_SIZE - 1) {
      // Fim da linha ou buffer cheio
      rfBuffer[rfBufferIndex] = '\0';

      if (rfBufferIndex > 0) {
        Serial.printf("RF433: Recebido: %s\n", rfBuffer);
        processRFResponse(rfBuffer);
      }

      // Limpa buffer
      memset(rfBuffer, 0, RF433_BUFFER_SIZE);
      rfBufferIndex = 0;
    } else if (c != '\r') {
      // Adiciona ao buffer (ignora \r)
      rfBuffer[rfBufferIndex++] = c;
    }
  }

  // Verifica timeout de comandos
  if (rf433State == RF433_WAITING_RESPONSE &&
      millis() - lastRFCommand > RF433_COMMAND_TIMEOUT) {
    Serial.println("RF433: Timeout aguardando resposta do Arduino");
    rf433State = RF433_DISCONNECTED;
  }
}

void sendRFCommand(const char* cmd) {
  if (rf433State == RF433_DISCONNECTED) {
    Serial.println("RF433: Não conectado ao Arduino");
    return;
  }

  Serial.printf("RF433: Enviando comando: %s\n", cmd);
  rfSerial.printf("%s\n", cmd);
  lastRFCommand = millis();
  rf433State = RF433_WAITING_RESPONSE;
}

void processRFResponse(const char* response) {
  rf433State = RF433_CONNECTED;

  if (strncmp(response, "OK:", 3) == 0) {
    // Respostas de sucesso
    if (strncmp(response + 3, "LIST:", 5) == 0) {
      // Pode ser:
      //  - OK:LIST:count|code1:...
      //  - OK:LIST:count   (somente contagem)
      //  - OK:LIST:value:bitlen:delay:proto  (uma linha por código)
      const char* payload = response + 8;
      if (strchr(payload, '|') != NULL) {
        // formato agregado
        parseRFCodesList(payload);
      } else if (strchr(payload, ':') != NULL) {
        // formato único: value:bitlen:delay:proto
        SavedCode code;
        if (sscanf(payload, "%lu:%u:%u:%u", &code.value, &code.bitlen, &code.delayUs, &code.proto) == 4) {
          if (rfCodesCount < MAX_RF_CODES) {
            rfCodes[rfCodesCount++] = code;
            Serial.printf("RF433: Código adicionado (linha única): %lu\n", code.value);
            if (rfCodeLearnedCallback) rfCodeLearnedCallback(code);
          }
        }
      } else {
        // apenas contagem - ignora
        int count = atoi(payload);
        Serial.printf("RF433: Lista contagem: %d\n", count);
      }
      // atualiza cache de IR sempre que houver mudança potencial
      updateIRCache();
    } else if (strncmp(response + 3, "SENT:", 5) == 0) {
      Serial.printf("RF433: Código enviado: %s\n", response + 8);
    } else if (strncmp(response + 3, "CLEARED", 7) == 0) {
      // libera buffers RAW alocados
      for (int i = 0; i < rfCodesCount; ++i) {
        if (rfCodes[i].proto == PROTO_IR_RAW && rfCodes[i].rawBuf != NULL) {
          delete[] rfCodes[i].rawBuf;
          rfCodes[i].rawBuf = NULL;
          rfCodes[i].rawLen = 0;
        }
      }
      rfCodesCount = 0;
      Serial.println("RF433: Lista de códigos limpa");
    } else if (strncmp(response + 3, "LEARNING", 8) == 0) {
      rf433State = RF433_LEARNING;
      Serial.println("RF433: Entrou em modo aprendizado");
    } else if (strncmp(response + 3, "STATUS:", 7) == 0) {
      Serial.printf("RF433: Status Arduino: %s\n", response + 10);
    }

  } else if (strncmp(response, "ERROR:", 6) == 0) {
    Serial.printf("RF433: Erro: %s\n", response + 6);

  } else if (strncmp(response, "LEARNED:RF:", 11) == 0) {
    // Novo código RF aprendido: LEARNED:RF:value:bitlen:delayUs:proto
    SavedCode code;
    if (sscanf(response + 11, "%lu:%u:%u:%u", &code.value, &code.bitlen, &code.delayUs, &code.proto) == 4) {
      if (rfCodesCount < MAX_RF_CODES) {
        rfCodes[rfCodesCount++] = code;
      } else {
        // substitui o mais antigo
        int oldestIdx = 0;
        unsigned long oldest = ULONG_MAX;
        for (int k = 0; k < MAX_RF_CODES; ++k) {
          if (rfCodeTimestamp[k] < oldest) { oldest = rfCodeTimestamp[k]; oldestIdx = k; }
        }
        rfCodes[oldestIdx] = code;
        Serial.printf("RF433: Substituiu RF na posição %d\n", oldestIdx+1);
      }
      Serial.printf("RF433: Novo código RF aprendido: %lu\n", code.value);
      rfCodeTimestamp[rfCodesCount-1] = millis();
      if (rfCodeLearnedCallback) rfCodeLearnedCallback(code);
      updateIRCache();
    }
    rf433State = RF433_CONNECTED;

  } else if (strncmp(response, "LEARNED:IR:", 11) == 0) {
    // Novo código IR aprendido: LEARNED:IR:command:bits:proto
    SavedCode code;
    unsigned long command = 0;
    unsigned int bits = 0;
    unsigned int proto = 0;
    if (sscanf(response + 11, "%lu:%u:%u", &command, &bits, &proto) >= 2) {
      code.value = command;
      code.bitlen = bits;
      code.delayUs = 0;
      code.proto = proto;
      if (rfCodesCount < MAX_RF_CODES) {
        rfCodes[rfCodesCount++] = code;
      } else {
        int oldestIdx = 0;
        unsigned long oldest = ULONG_MAX;
        for (int k = 0; k < MAX_RF_CODES; ++k) {
          if (rfCodeTimestamp[k] < oldest) { oldest = rfCodeTimestamp[k]; oldestIdx = k; }
        }
        rfCodes[oldestIdx] = code;
        Serial.printf("RF433: Substituiu IR na posição %d\n", oldestIdx+1);
      }
      Serial.printf("RF433: Novo código IR aprendido: cmd=%lu bits=%u proto=%u\n", command, bits, proto);
      updateIRCache();
    }
    rf433State = RF433_CONNECTED;

  } else if (strncmp(response, "LEARNED:RAW_SENT", 16) == 0) {
    // Indicação que Arduino enviou o RAW para o ESP previamente (log)
    Serial.println("RF433: Arduino indicou RAW enviado (RAW_SENT)");
    rf433State = RF433_CONNECTED;

  } else if (strncmp(response, "RAWSTART:", 9) == 0) {
    // Inicia recepção de RAW enviado pelo Arduino
    // Formato: RAWSTART:len:freq
    int len = 0;
    int freq = 38;
    if (sscanf(response + 9, "%d:%d", &len, &freq) >= 1) {
      Serial.printf("RF433: Iniciando recebimento RAW len=%d freq=%d\n", len, freq);
      if (len > 0) {
        // aloca buffer temporário
        if (currentRawBuf) { delete[] currentRawBuf; currentRawBuf = NULL; }
        currentRawBuf = new uint16_t[len];
        if (currentRawBuf == NULL) {
          Serial.println("RF433: Falha ao alocar buffer RAW temporario");
          receivingRaw = false;
          currentRawLen = 0;
          currentRawCollected = 0;
        } else {
          receivingRaw = true;
          currentRawLen = len;
          currentRawCollected = 0;
          currentRawFreq = (uint16_t)freq;
        }
      }
    }

  } else if (strncmp(response, "RAWEND", 6) == 0) {
    // Final da transmissão RAW - se completou, registra código
    if (receivingRaw && currentRawCollected == currentRawLen && currentRawBuf != NULL) {
      // Verifica se este RAW já existe (deduplicação)
      bool isDuplicate = false;
      for (int i = 0; i < rfCodesCount; ++i) {
        if (rfCodes[i].proto == PROTO_IR_RAW && rfCodes[i].rawLen == currentRawLen && rfCodes[i].rawFreq == currentRawFreq && rfCodes[i].rawBuf != NULL) {
          bool same = true;
          for (uint16_t j = 0; j < currentRawLen; ++j) {
            if (rfCodes[i].rawBuf[j] != currentRawBuf[j]) { same = false; break; }
          }
          if (same) {
            isDuplicate = true;
            // atualiza timestamp
            rfCodeTimestamp[i] = millis();
            Serial.printf("RF433: RAW duplicado detectado; não será salvo (dup index=%d)\n", i+1);
            break;
          }
        }
      }

      if (!isDuplicate) {
        int saveIndex = -1;
        if (rfCodesCount < MAX_RF_CODES) {
          saveIndex = rfCodesCount++;
        } else {
          // substitui a entrada mais antiga
          unsigned long oldest = ULONG_MAX;
          int oldestIdx = 0;
          for (int k = 0; k < MAX_RF_CODES; ++k) {
            if (rfCodeTimestamp[k] < oldest) {
              oldest = rfCodeTimestamp[k];
              oldestIdx = k;
            }
          }
          // libera buffer antigo se for RAW
          if (rfCodes[oldestIdx].proto == PROTO_IR_RAW && rfCodes[oldestIdx].rawBuf != NULL) {
            delete[] rfCodes[oldestIdx].rawBuf;
            rfCodes[oldestIdx].rawBuf = NULL;
          }
          saveIndex = oldestIdx;
          Serial.printf("RF433: Substituindo entrada mais antiga (index=%d)\n", saveIndex+1);
        }

        // Salva no índice escolhido
        SavedCode code;
        code.value = 0;
        code.bitlen = 0;
        code.delayUs = 0;
        code.proto = PROTO_IR_RAW;
        code.rawBuf = currentRawBuf;
        code.rawLen = currentRawLen;
        code.rawFreq = currentRawFreq;
        rfCodes[saveIndex] = code;
        rfCodeTimestamp[saveIndex] = millis();
        Serial.printf("RF433: Novo RAW aprendido e salvo como #%d (len=%d)\n", saveIndex+1, currentRawLen);
        if (rfCodeLearnedCallback) rfCodeLearnedCallback(code);
        updateIRCache();
      } else {
        // Se duplicado, libera o buffer temporário (não salvar)
        delete[] currentRawBuf;
      }
    } else {
      Serial.println("RF433: RAWEND recebido mas buffer incompleto ou não alocado");
      if (currentRawBuf) { delete[] currentRawBuf; currentRawBuf = NULL; }
    }
    // reseta estado
    receivingRaw = false;
    currentRawBuf = NULL;
    currentRawLen = 0;
    currentRawCollected = 0;

  } else if (strncmp(response, "RAW:", 4) == 0) {
    // Linha contendo valores CSV para complementar buffer RAW
    if (!receivingRaw || currentRawBuf == NULL) {
      Serial.println("RF433: Recebeu RAW data mas nao esperava; ignorando");
    } else {
      // parse csv numbers
      const char* p = response + 4;
      char numbuf[32];
      int ni = 0;
      while (*p && currentRawCollected < currentRawLen) {
        if (*p == ',' || *p == '\0' || *p == '\r' || *p == '\n') {
          if (ni > 0) {
            numbuf[ni] = '\0';
            unsigned long v = strtoul(numbuf, NULL, 10);
            currentRawBuf[currentRawCollected++] = (uint16_t)v;
            ni = 0;
          }
          if (*p == '\0') break;
          p++;
        } else {
          if (ni < (int)sizeof(numbuf)-1) numbuf[ni++] = *p;
          p++;
        }
      }
      // se linha terminou e ainda havia um número pendente
      if (ni > 0 && currentRawCollected < currentRawLen) {
        numbuf[ni] = '\0';
        unsigned long v = strtoul(numbuf, NULL, 10);
        currentRawBuf[currentRawCollected++] = (uint16_t)v;
      }
      Serial.printf("RF433: RAW chunk recebido, collected=%d/%d\n", currentRawCollected, currentRawLen);
    }
  }
}

void parseRFCodesList(const char* data) {
  // Formato: count|code1:value:bitlen:delay:proto|code2:...
  char temp[RF433_BUFFER_SIZE];
  strcpy(temp, data);

  char* token = strtok(temp, "|");
  if (!token) return;

  int count = atoi(token);
  rfCodesCount = 0;

  for (int i = 0; i < count && rfCodesCount < MAX_RF_CODES; i++) {
    token = strtok(NULL, "|");
    if (!token) break;

    SavedCode code;
    if (sscanf(token, "%lu:%u:%u:%u", &code.value, &code.bitlen, &code.delayUs, &code.proto) == 4) {
      rfCodes[rfCodesCount++] = code;
    }
  }

  Serial.printf("RF433: Recebidos %d códigos do Arduino\n", rfCodesCount);
  // Atualiza cache de códigos IR
  updateIRCache();
}

bool sendRFCode(int index) {
  if (index < 1 || index > rfCodesCount) {
    Serial.printf("RF433: Índice inválido: %d (máx: %d)\n", index, rfCodesCount);
    return false;
  }

  SavedCode &sc = rfCodes[index - 1];
  // Se é RAW, enviamos o buffer RAW chunked para o Arduino (ele transmitirá)
  if (sc.proto == PROTO_IR_RAW && sc.rawBuf != NULL && sc.rawLen > 0) {
    Serial.printf("RF433: Enviando RAW para Arduino (idx=%d len=%d)\n", index, sc.rawLen);
    // RAWSTART
    rfSerial.printf("RAWSTART:%u:%u\n", sc.rawLen, sc.rawFreq);
    // envia em chunks
    const uint16_t CHUNK = 50;
    for (uint16_t i = 0; i < sc.rawLen; ++i) {
      if (i % CHUNK == 0) rfSerial.print("RAW:");
      else rfSerial.print(',');
      rfSerial.print(sc.rawBuf[i]);
      if ((i % CHUNK == CHUNK - 1) || (i == sc.rawLen - 1)) rfSerial.print("\n");
    }
    rfSerial.print("RAWEND\n");
    lastRFCommand = millis();
    rf433State = RF433_WAITING_RESPONSE;
    return true;
  }

  // Caso normal: solicite ao Arduino que envie o código através de SEND:CODE:...
  return sendRFCodeRaw(sc.value, sc.bitlen, sc.delayUs, sc.proto);
}

bool sendRFCodeRaw(unsigned long code, unsigned int bitlen, unsigned int delayUs, unsigned int proto) {
  char cmd[64];
  sprintf(cmd, "SEND:CODE:%lu:%u:%u:%u", code, bitlen, delayUs, proto);
  sendRFCommand(cmd);
  return true;
}

bool listRFCodes() {
  sendRFCommand("LIST");
  return true;
}

bool clearRFCodes() {
  sendRFCommand("CLEAR");
  return true;
}

bool learnRFCode() {
  sendRFCommand("LEARN");
  return true;
}

bool getRFStatus() {
  sendRFCommand("STATUS");
  return true;
}

SavedCode* getRFCodes() {
  return rfCodes;
}

int getRFCodesCount() {
  return rfCodesCount;
}

int getIRCodesCount() {
  return irCodesCountCache;
}

SavedCode* getIRCodes() {
  return irCodesCache;
}

int getIRGlobalIndex(int irIndex) {
  if (irIndex < 0) return -1;
  int cnt = 0;
  for (int i = 0; i < rfCodesCount; ++i) {
    if (rfCodes[i].proto >= 100) {
      if (cnt == irIndex) return i;
      cnt++;
    }
  }
  return -1;
}

bool isRF433Connected() {
  return rf433State != RF433_DISCONNECTED;
}

void setRFCodeLearnedCallback(RFCodeLearnedCallback callback) {
  rfCodeLearnedCallback = callback;
}

#endif // RF433_H
