#ifndef BUTTONS_H
#define BUTTONS_H

#include "config.h"
#include <Keypad.h>
#include "keypad_config.h"
#include "rf433.h"

// Forward declarations para evitar dependência circular
void setScreen(ScreenMode screen);
ScreenMode getCurrentScreen();
bool isAudioActive();
void startStreaming();
void stopStreaming();
void syncScreenIndex();
void processCalculatorInput(int buttonIndex, bool longPress);

// Funções de paginação da tela remota (definidas em screen_remote.h)
// Como screen_remote.h é incluído no display_tft.h e não aqui, precisamos declarar
// Mas para o linker achar, as funções não podem ser estáticas no header.
// O ideal é declarar extern.
extern void nextRemotePage();
extern void prevRemotePage();
extern int getRemotePage();

// Variáveis de notificações declaradas externamente
extern int notificationCount;
extern int currentNotificationIndex;

// Variável de navegação RF433
extern int currentRFCodeIndex;
// Variável de navegação IR
extern int currentIRCodeIndex;

// Declarações externas para funções RF433
extern int getRFCodesCount();
extern bool sendRFCode(int index);

// Declarações externas para QR Code
extern void setQrcodeWifiMode();
extern void setQrcodeIpMode();

// Declarações externas para Rede
extern String randomId;
extern String remoteSecret;
extern WebSocketsClient webSocket;

// ==========================================
// MÓDULO DE BOTÕES - Matriz 4x4
// ==========================================

// Mapeamento da matriz
const byte LINHAS = KEYPAD_ROWS;
const byte COLUNAS = KEYPAD_COLS;
char teclas[LINHAS][COLUNAS] = KEYPAD_KEYS;
byte pinosLinhas[LINHAS] = ROW_PINS;
byte pinosColunas[COLUNAS] = COL_PINS;

Keypad teclado = Keypad(makeKeymap(teclas), pinosLinhas, pinosColunas, LINHAS, COLUNAS);

const char* nomesTeclas[16] = BUTTON_NAMES;

// Funções públicas
void initButtons();
void updateButtons();
void processButtonAction(int index, bool longPress);

// ===== IMPLEMENTAÇÃO =====

void initButtons() {
  Serial.println("Botões inicializados");
}

int mapearTecla(char tecla) {
  for (int r = 0; r < LINHAS; r++) {
    for (int c = 0; c < COLUNAS; c++) {
      if (teclas[r][c] == tecla) {
        return r * COLUNAS + c;
      }
    }
  }
  return -1;
}

void updateButtons() {
  if (!teclado.getKeys()) return;

  static unsigned long pressStart[16] = {0};
  static bool isPressed[16] = {false};

  for (int i = 0; i < LIST_MAX; i++) {
    if (teclado.key[i].kchar == NO_KEY) continue;

    char keyChar = teclado.key[i].kchar;
    KeyState keyState = teclado.key[i].kstate;
    int index = mapearTecla(keyChar);
    if (index == -1 || index >= 16) continue;

    if (keyState == PRESSED) {
      isPressed[index] = true;
      pressStart[index] = millis();
      Serial.print("Botão ");
      Serial.print(nomesTeclas[index]);
      Serial.println(" pressionado");
    } else if (keyState == RELEASED) {
      unsigned long duracao = 0;
      if (isPressed[index]) {
        duracao = millis() - pressStart[index];
        isPressed[index] = false;
      }

      Serial.print("Botão ");
      Serial.print(nomesTeclas[index]);
      Serial.printf(" → Duração: %lums", duracao);

      if (duracao >= LONG_PRESS_THRESHOLD) {
        Serial.println(" → Clique LONGO");
        processButtonAction(index, true);
      } else {
        Serial.println(" → Clique normal");
        processButtonAction(index, false);
      }
    }
  }
}

// Array das telas disponíveis em ordem sequencial
const ScreenMode screenOrder[] = {
  SCREEN_WATCHFACE,
  SCREEN_CALCULATOR,
  SCREEN_NOTIFICATIONS,
  SCREEN_SENSORS,
  SCREEN_STATUS,
  SCREEN_REMOTE, // Nova tela
  SCREEN_RF433,
  SCREEN_IR,
  SCREEN_CUBE3D,
  SCREEN_QRCODE
};
const int screenOrderSize = sizeof(screenOrder) / sizeof(screenOrder[0]);

// Índice atual da tela (persistido entre navegações)
static int currentScreenIndex = 0;

// Sincroniza currentScreenIndex com a tela atual
void syncScreenIndex() {
  ScreenMode currentScreen = getCurrentScreen();

  // Encontra o índice da tela atual
  for (int i = 0; i < screenOrderSize; i++) {
    if (screenOrder[i] == currentScreen) {
      currentScreenIndex = i;
      break;
    }
  }
}

void navigateToNextScreen() {
  // Garante que o índice esteja sincronizado
  syncScreenIndex();

  // Navega para a próxima (circular)
  currentScreenIndex = (currentScreenIndex + 1) % screenOrderSize;
  setScreen(screenOrder[currentScreenIndex]);

  Serial.printf("Navegando para próxima tela: %d\n", currentScreenIndex);
}

void navigateToPreviousScreen() {
  // Garante que o índice esteja sincronizado
  syncScreenIndex();

  // Navega para a anterior (circular)
  currentScreenIndex = (currentScreenIndex - 1 + screenOrderSize) % screenOrderSize;
  setScreen(screenOrder[currentScreenIndex]);

  Serial.printf("Navegando para tela anterior: %d\n", currentScreenIndex);
}

void processButtonAction(int index, bool longPress) {
  ScreenMode currentScreen = getCurrentScreen();

  // Navegação global (sempre funciona)
  if (index == 12) { // S13 - tela anterior (GLOBAL)
    navigateToPreviousScreen();
    return;
  } else if (index == 15) { // S16 - próxima tela (GLOBAL)
    navigateToNextScreen();
    return;
  }

  // Se estiver na calculadora, processa entrada da calculadora
  if (currentScreen == SCREEN_CALCULATOR) {
    processCalculatorInput(index, longPress);
    return;
  }
  
  // Controle Remoto PC (SCREEN_REMOTE)
  if (currentScreen == SCREEN_REMOTE) {
    if (longPress) return; 

    // Navegação interna da tela remota
    // S14 (idx 13) -> Anterior
    // S15 (idx 14) -> Próximo
    if (index == 13) { // S14
      prevRemotePage();
      return;
    }
    if (index == 14) { // S15
      nextRemotePage();
      return;
    }

    String cmd = "";
    int page = getRemotePage();

    if (page == 1) {
      // --- PÁGINA 1: SETAS ---
      // S2(1)=CIMA, S5(4)=ESQ, S6(5)=ENTER, S7(6)=DIR, S10(9)=BAIXO
      switch (index) {
        case 1: cmd = "CIMA"; break;      // S2
        case 4: cmd = "ESQ"; break;       // S5
        case 6: cmd = "DIR"; break;       // S7
        case 9: cmd = "BAIXO"; break;     // S10
        case 5: cmd = "ENTER"; break;     // S6
      }
    } else if (page == 2) {
      // --- PÁGINA 2: NUMÉRICO ---
      // S1..S3 (0..2) -> 1,2,3
      // S5..S7 (4..6) -> 4,5,6
      // S9..S11 (8..10) -> 7,8,9
      // S12 (11) -> 0
      // S4 (3) -> ENTER
      // S8 (7) -> BACKSPACE
      switch (index) {
        case 0: cmd = "NUM_1"; break;
        case 1: cmd = "NUM_2"; break;
        case 2: cmd = "NUM_3"; break;
        case 4: cmd = "NUM_4"; break;
        case 5: cmd = "NUM_5"; break;
        case 6: cmd = "NUM_6"; break;
        case 8: cmd = "NUM_7"; break;
        case 9: cmd = "NUM_8"; break;
        case 10: cmd = "NUM_9"; break;
        case 11: cmd = "NUM_0"; break; // S12
        case 3: cmd = "ENTER"; break;  // S4
        case 7: cmd = "BACKSPACE"; break; // S8
      }
    }
    if (cmd != "") {
      String payload = randomId + "|" + remoteSecret + "|" + cmd;
      webSocket.sendTXT(payload);
      Serial.println("Remote CMD enviado: " + payload);
    }
    return;
  }

  // Navegação em notificações
  if (currentScreen == SCREEN_NOTIFICATIONS && notificationCount > 1) {
    if (index == 13 && !longPress) { // S14 - anterior
      if (currentNotificationIndex > 0) {
        currentNotificationIndex--;
      } else {
        currentNotificationIndex = notificationCount - 1; // Volta para a última
      }
      return;
    } else if (index == 14 && !longPress) { // S15 - próxima
      if (currentNotificationIndex < notificationCount - 1) {
        currentNotificationIndex++;
      } else {
        currentNotificationIndex = 0; // Volta para a primeira
      }
      return;
    }
  }

  // Navegação em códigos RF433
  if (currentScreen == SCREEN_RF433) {
    int codesCount = getRFCodesCount();
    if (codesCount > 0) {
      if (index == 12 && !longPress) { // S13 - código anterior
        if (currentRFCodeIndex > 0) {
          currentRFCodeIndex--;
        } else {
          currentRFCodeIndex = codesCount - 1; // Volta para o último
        }
        return;
      } else if (index == 13 && !longPress) { // S14 - próximo código
        if (currentRFCodeIndex < codesCount - 1) {
          currentRFCodeIndex++;
        } else {
          currentRFCodeIndex = 0; // Volta para o primeiro
        }
        return;
      } else if (index == 0 && !longPress) { // S1 - enviar código atual
        sendRFCode(currentRFCodeIndex + 1); // Índices começam em 1
        return;
      }
    }
  }

  // Navegação em códigos IR
  if (currentScreen == SCREEN_IR) {
    int codesCount = getIRCodesCount();
    if (codesCount > 0) {
      if (index == 12 && !longPress) { // S13 - código anterior
        if (currentIRCodeIndex > 0) {
          currentIRCodeIndex--;
        } else {
          currentIRCodeIndex = codesCount - 1; // Volta para o último
        }
        return;
      } else if (index == 13 && !longPress) { // S14 - próximo código
        if (currentIRCodeIndex < codesCount - 1) {
          currentIRCodeIndex++;
        } else {
          currentIRCodeIndex = 0; // Volta para o primeiro
        }
        return;
      } else if (index == 1 && !longPress) { // S2 - listar códigos
        Serial.println("IR: Solicitando lista de codigos ao Arduino");
        listRFCodes();
        return;
      } else if (index == 2 && !longPress) { // S3 - aprender
        Serial.println("IR: Solicitando modo aprendizado ao Arduino");
        learnRFCode();
        return;
      } else if (index == 3 && !longPress) { // S4 - limpar lista
        Serial.println("IR: Solicitando limpeza de lista ao Arduino");
        clearRFCodes();
        return;
      } else if (index == 0 && !longPress) { // S1 - enviar código atual
        int globalIdx = getIRGlobalIndex(currentIRCodeIndex);
        if (globalIdx >= 0) sendRFCode(globalIdx + 1); // sendRFCode espera 1-based
        return;
      }
    }
  }

  // Controles específicos da tela QR Code
  if (currentScreen == SCREEN_QRCODE) {
    if (index == 6 && !longPress) { // S7 - modo Wi-Fi
      setQrcodeWifiMode();
      return;
    } else if (index == 7 && !longPress) { // S8 - modo IP
      setQrcodeIpMode();
      return;
    }
  }

  // Ações específicas por tela (quando não na calculadora)
  switch (index) {
    case 14: // S15 - toggle áudio streaming (apenas quando não em notificações)
      if (currentScreen != SCREEN_NOTIFICATIONS && !longPress) {
        if (isAudioActive()) {
          stopStreaming();
        } else {
          startStreaming();
        }
      }
      break;

    case 15: // S16 - já tratado acima (navegação)
      break;

    default:
      Serial.printf("Botão %s pressionado (tela %d)\n", nomesTeclas[index], currentScreen);
      break;
  }
}

#endif // BUTTONS_H
