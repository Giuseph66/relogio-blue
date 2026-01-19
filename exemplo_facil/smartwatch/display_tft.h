#ifndef DISPLAY_TFT_H
#define DISPLAY_TFT_H

#include "config.h"
#include <TFT_eSPI.h>
#include "WatchFace.h"
#include "network.h"
#include "sensors.h"
#include "calculadora.h"
#include "rf433.h"
#include "qr_code.h"
#include "cubo3d.h"

// Declarações externas para QR Code
extern void setQrcodeText(String text);
extern void setQrcodeWifiMode();
extern void setQrcodeIpMode();
extern void forceQrcodeRedraw();

// Declarações externas
extern bool ntpSincronizado;

// ==========================================
// MÓDULO DE DISPLAY TFT 240x240
// ==========================================

// Objeto TFT
TFT_eSPI tft;

// Módulos de tela específicos
#include "screen_rf433.h"
#include "screen_ir.h"
#include "screen_remote.h" // Adicionado

// Estado
ScreenMode currentScreen = SCREEN_WATCHFACE;
ScreenMode lastScreen = SCREEN_NONE; // Para detectar mudança de tela
int currentWatchFace = 3; // Padrão: V3
bool firstRender = true; // Flag de primeira renderização

// Timestamps para throttling
unsigned long lastDisplayUpdate = 0;
unsigned long lastStaticUpdate = 0;

// Estado da calculadora (declarado externamente em calculadora.h)
extern Calc3RoundBrightState calculatorState;

// Estado RF433
int currentRFCodeIndex = 0; // Índice do código RF sendo visualizado
// Estado IR
int currentIRCodeIndex = 0; // Índice do código IR sendo visualizado

// Sistema de notificações
#define MAX_NOTIFICATIONS 10
struct Notification {
  String message;
  String timestamp;
  bool isRead;
};

Notification notifications[MAX_NOTIFICATIONS];
int notificationCount = 0;
int currentNotificationIndex = 0;
int lastDisplayedNotification = -1; // Para detectar mudanças na notificação atual

// Funções públicas
void initDisplay();
void updateDisplay();
void renderWatchface(bool firstRender, bool updateStatic);
void renderSensorsScreen(bool firstRender);
void renderCalculatorScreen(bool firstRender);
void renderNotificationScreen(bool firstRender);
void renderStatusScreen(bool firstRender);
void renderQrcodeScreen(bool firstRender);
void renderRF433Screen(bool firstRender);
void renderIRScreen(bool firstRender);
void renderRemoteScreen(bool firstRender); // Adicionado
void setScreen(ScreenMode screen);
ScreenMode getCurrentScreen();
void showMessage(String msg);

// Funções de notificações
void addNotification(String message);
void clearNotifications();
bool hasUnreadNotifications();

// ===== IMPLEMENTAÇÃO =====

void initDisplay() {
  Serial.println("Iniciando TFT...");

  // Pequena pausa antes da inicialização
  delay(100);

  tft.init();
  Serial.println("TFT.init() concluído");

  tft.setRotation(0); // Rotação normal
  Serial.println("Rotação definida");

  // Inicializar backlight
  pinMode(TFT_BL, OUTPUT);
  digitalWrite(TFT_BL, HIGH); // Liga o backlight
  Serial.println("Backlight ligado (GPIO" + String(TFT_BL) + ")");

  // Pequena pausa após ligar backlight
  delay(100);

  tft.fillScreen(COLOR_BG);
  Serial.println("Tela preenchida com cor de fundo");

  // Teste básico: desenhar um retângulo colorido para verificar se o display funciona
  tft.fillRect(50, 50, 100, 100, COLOR_ACCENT);
  Serial.println("Retângulo de teste desenhado");
  delay(500); // Pequena pausa para ver o teste

  // Inicializa QR Code
  initQrcode();
  Serial.println("QR Code inicializado");

  // Inicializa estado da calculadora
  calculatorState.currentExpr = "";
  calculatorState.currentResult = "0";
  calculatorState.historyCount = 0;
  calculatorState.highlight = -1;
  for (int i = 0; i < 6; i++) {
    calculatorState.history[i] = "";
  }

  // Inicializa a tela do cubo 3D (não desenha até ser selecionada)
  cube3d_init();
  Serial.println("Display TFT inicializado");
}

void setScreen(ScreenMode screen) {
  if (currentScreen != screen) {
    lastScreen = currentScreen;
    currentScreen = screen;
    firstRender = true; // Indica que precisa limpar tela

    // Sincroniza o índice de navegação
    syncScreenIndex();
  }
}

ScreenMode getCurrentScreen() {
  return currentScreen;
}

void updateDisplay() {
  unsigned long now = millis();
  
  // Throttling: limita taxa de atualização
  if (now - lastDisplayUpdate < TFT_UPDATE_INTERVAL) {
    return; // Pula esta frame
  }
  lastDisplayUpdate = now;
  
  // Atualiza elemento que varia mais devagar
  bool updateStatic = (now - lastStaticUpdate >= TFT_STATIC_UPDATE_INTERVAL);
  if (updateStatic) {
    lastStaticUpdate = now;
  }
  
  // Verifica se precisa forçar redesenho da tela de notificações
  bool forceNotificationRedraw = (currentScreen == SCREEN_NOTIFICATIONS &&
                                  lastDisplayedNotification != currentNotificationIndex);

  // Renderiza tela atual
  if (firstRender) {
    Serial.printf("Renderizando tela: %d (firstRender=true)\n", currentScreen);
  }

  switch (currentScreen) {
    case SCREEN_WATCHFACE:
      renderWatchface(firstRender, updateStatic);
      break;
    case SCREEN_SENSORS:
      renderSensorsScreen(firstRender);
      break;
    case SCREEN_CALCULATOR:
      renderCalculatorScreen(firstRender);
      break;
    case SCREEN_NOTIFICATIONS:
      renderNotificationScreen(firstRender || forceNotificationRedraw);
      lastDisplayedNotification = currentNotificationIndex; // Atualiza o último exibido
      break;
    case SCREEN_STATUS:
      renderStatusScreen(firstRender);
      break;
    case SCREEN_REMOTE: // Adicionado
      renderRemoteScreen(firstRender);
      break;
    case SCREEN_CUBE3D:
      // Atualiza estado baseado nos sensores e desenha o cubo (throttle interno)
      cube3d_update(now);
      cube3d_draw();
      break;
    case SCREEN_QRCODE:
      renderQrcodeScreen(firstRender);
      break;
    case SCREEN_IR:
      renderIRScreen(firstRender);
      break;
    case SCREEN_RF433:
      renderRF433Screen(firstRender);
      break;
  }

  firstRender = false; // Já renderizou pela primeira vez
}

void renderWatchface(bool firstRender, bool updateStatic) {
  WatchFaceV3Data wfData;

  // Extrai hora/minuto/segundo da string de tempo
  String timeStr = getTimeString();
  wfData.hour = timeStr.substring(0, 2).toInt();
  wfData.minute = timeStr.substring(3, 5).toInt();
  wfData.second = timeStr.substring(6, 8).toInt();

  // Debug: mostrar valores extraídos
  //Serial.printf("DEBUG - timeStr: '%s', hour: %d, minute: %d, second: %d\n",
  //              timeStr.c_str(), wfData.hour, wfData.minute, wfData.second);

  // Verificar se NTP está sincronizado
  //Serial.printf("NTP sincronizado: %s\n", ntpSincronizado ? "SIM" : "NAO");
  
  // Dados dos sensores
  SensorData sd = getSensorData();
  wfData.heart = sd.bpm > 0 ? sd.bpm : 0;
  wfData.heartProgress = sd.bpm > 0 ? (float)sd.bpm / 200.0f : 0.0f;
  wfData.sys = 120; // Fixo por enquanto
  wfData.dia = 80;
  wfData.battery = 85;
  String dateStr = getDateString();
  wfData.date = dateStr.c_str();
  wfData.year = getCurrentYear();

  // Debug: mostrar data
  //Serial.printf("DEBUG - date: '%s', year: %d\n", dateStr.c_str(), wfData.year);
  
  // Desenha watchface
  // Static() apenas na primeira renderização
  if (firstRender) {
    drawWatchFaceV3Static(tft, wfData, true);
  }
  // Update() sempre (relógio, batimentos, etc)
  drawWatchFaceV3Update(tft, wfData);
}

void renderSensorsScreen(bool firstRender) {
  // Limpa tela apenas na primeira renderização
  if (firstRender) {
    tft.fillScreen(COLOR_BG);

    // Título (estático) - centralizado no topo
    tft.setTextColor(COLOR_TEXT, COLOR_BG);
    tft.setTextDatum(MC_DATUM);
    tft.setTextFont(2);
    tft.drawString("Sensores", 120, 30);

    // Labels estáticos - centralizados
    tft.setTextColor(COLOR_CYAN);
    tft.setTextDatum(TC_DATUM); // Topo centralizado
    tft.drawString("MPU6050", 120, 60);

    tft.setTextColor(COLOR_HEART);
    tft.setTextDatum(TC_DATUM); // Topo centralizado
    tft.drawString("Heart Rate", 120, 130);
  }

  // Dados dinâmicos - centralizados
  SensorData sd = getSensorData();

  // MPU6050 - valores centralizados
  tft.setTextColor(COLOR_TEXT, COLOR_BG);
  tft.setTextDatum(MC_DATUM); // Centro completo
  tft.setTextFont(1);
  tft.drawString(String("Acc: ") + String(sd.accelX, 1) + ", " + String(sd.accelY, 1), 120, 85);
  tft.drawString(String("Temp: ") + String(sd.tempMPU, 1) + "C", 120, 105);

  // MAX30102 - valores centralizados
  tft.setTextDatum(MC_DATUM); // Centro completo
  if (sd.bpm > 0) {
    tft.drawString(String("BPM: ") + String(sd.bpm), 120, 155);
    tft.drawString(String("SpO2: ") + String(sd.spo2) + "%", 120, 175);
  } else {
    tft.drawString("Dedo nao detectado", 120, 155);
  }
}

void renderCalculatorScreen(bool firstRender) {
  // Renderiza calculadora usando as funções do calculadora.h
  // Sempre redesenha para atualizar mudanças de estado
  drawCalculator3ButtonsRoundBright(tft, calculatorState, firstRender);
}

void renderNotificationScreen(bool firstRender) {
  // Só limpa a tela na primeira renderização ou quando necessário
  if (firstRender) {
    tft.fillScreen(COLOR_BG);

    // Título sempre visível
    tft.setTextColor(COLOR_TEXT);
    tft.setTextDatum(MC_DATUM);
    tft.setTextFont(2);
    tft.drawString("Notificacoes", 120, 30);
  }

  // Limpa apenas a área de conteúdo dinâmico (evita piscar)
  // Área do timestamp e mensagem: Y=50-180, X=20-220
  if (!firstRender) {
    tft.fillRect(20, 45, 200, 140, COLOR_BG);
  }

  // Se não há notificações
  if (notificationCount == 0) {
    tft.setTextColor(COLOR_SUB);
    tft.setTextDatum(MC_DATUM);
    tft.setTextFont(1);
    tft.drawString("Nenhuma notificacao", 120, 120);
    return;
  }

  // Mostra a notificação atual
  if (notificationCount > 0 && currentNotificationIndex < notificationCount) {
    Notification &notif = notifications[currentNotificationIndex];

    // Timestamp centralizado
    tft.setTextColor(COLOR_SUB);
    tft.setTextDatum(MC_DATUM);
    tft.setTextFont(1);
    tft.drawString(notif.timestamp, 120, 55);

    // Mensagem centralizada (quebrada em linhas se necessário)
    tft.setTextColor(COLOR_TEXT);
    tft.setTextFont(2);

    String msg = notif.message;
    int maxCharsPerLine = 18; // Menos caracteres por linha para tela redonda
    int start = 0;
    int lineCount = 0;

    // Conta quantas linhas teremos para centralizar verticalmente
    int tempStart = 0;
    while (tempStart < msg.length()) {
      int tempEnd = tempStart + maxCharsPerLine;
      if (tempEnd > msg.length()) tempEnd = msg.length();

      if (tempEnd < msg.length() && msg.charAt(tempEnd) != ' ') {
        int spacePos = msg.lastIndexOf(' ', tempEnd);
        if (spacePos > tempStart) tempEnd = spacePos;
      }

      lineCount++;
      tempStart = tempEnd;
      while (tempStart < msg.length() && msg.charAt(tempStart) == ' ') tempStart++;
    }

    // Centraliza verticalmente as linhas de texto
    int totalTextHeight = lineCount * 20; // 20 pixels por linha
    int centerY = 120; // Centro vertical da tela
    int startY = centerY - (totalTextHeight / 2) + 10;

    // Agora desenha as linhas centralizadas
    start = 0;
    int currentLine = 0;

    while (start < msg.length() && currentLine < lineCount) {
      int end = start + maxCharsPerLine;
      if (end > msg.length()) end = msg.length();

      // Procura por quebra de palavra se possível
      if (end < msg.length() && msg.charAt(end) != ' ') {
        int spacePos = msg.lastIndexOf(' ', end);
        if (spacePos > start) end = spacePos;
      }

      String line = msg.substring(start, end);
      line.trim(); // Remove espaços extras

      // Centraliza horizontalmente cada linha
      tft.setTextDatum(MC_DATUM);
      tft.drawString(line, 120, startY + (currentLine * 20));

      currentLine++;
      start = end;

      // Pula espaços no início da próxima linha
      while (start < msg.length() && msg.charAt(start) == ' ') start++;
    }

    // Indicador de navegação se houver múltiplas notificações
    if (notificationCount > 1) {
      tft.setTextColor(COLOR_ACCENT);
      tft.setTextDatum(MC_DATUM);
      tft.setTextFont(1);
      tft.drawString(String(currentNotificationIndex + 1) + "/" + String(notificationCount), 120, 200);
    }

    // Marca como lida
    notif.isRead = true;
  }
}

void renderStatusScreen(bool firstRender) {
  // Limpa tela apenas na primeira renderização
  if (firstRender) {
    tft.fillScreen(COLOR_BG);

    // Título (estático) - centralizado no topo
    tft.setTextColor(COLOR_TEXT, COLOR_BG);
    tft.setTextDatum(MC_DATUM);
    tft.setTextFont(2);
    tft.drawString("Status Sistema", 120, 20);
  }

  // Valores dinâmicos - linhas centralizadas verticalmente
  tft.setTextDatum(MC_DATUM); // Centro completo para todas as linhas
  tft.setTextFont(1);
  tft.setTextColor(COLOR_TEXT, COLOR_BG);

  // Formatar e centralizar cada linha
  String idStr = String("ID: ") + randomId;
  tft.drawString(idStr, 120, 50);

  String ipStr = String("IP: ") + WiFi.localIP().toString();
  tft.drawString(ipStr, 120, 75);

  String uptimeStr = String("Uptime: ") + String(millis() / 1000) + "s";
  tft.drawString(uptimeStr, 120, 100);

  String memoriaStr = String("Memoria: ") + String(ESP.getFreeHeap()) + " bytes";
  tft.drawString(memoriaStr, 120, 125);

  String wifiStr = String("WiFi: ") + (isWiFiConnected() ? "Conectado" : "Desconectado");
  tft.drawString(wifiStr, 120, 150);
}

void showMessage(String msg) {
  // Exibe mensagem temporária
  tft.fillScreen(COLOR_BG);
  tft.setTextColor(COLOR_TEXT);
  tft.setTextDatum(MC_DATUM);
  tft.setTextFont(2);
  tft.drawString(msg, 120, 120);
}

// ===== FUNÇÕES DE NOTIFICAÇÕES =====

void addNotification(String message) {
  if (notificationCount < MAX_NOTIFICATIONS) {
    notifications[notificationCount].message = message;
    notifications[notificationCount].timestamp = getTimeString();
    notifications[notificationCount].isRead = false;
    notificationCount++;
  } else {
    // Remove a mais antiga e adiciona a nova
    for (int i = 0; i < MAX_NOTIFICATIONS - 1; i++) {
      notifications[i] = notifications[i + 1];
    }
    notifications[MAX_NOTIFICATIONS - 1].message = message;
    notifications[MAX_NOTIFICATIONS - 1].timestamp = getTimeString();
    notifications[MAX_NOTIFICATIONS - 1].isRead = false;
  }
}

void clearNotifications() {
  notificationCount = 0;
  currentNotificationIndex = 0;
}

bool hasUnreadNotifications() {
  for (int i = 0; i < notificationCount; i++) {
    if (!notifications[i].isRead) {
      return true;
    }
  }
  return false;
}

void renderQrcodeScreen(bool firstRender) {
  // Chama a função do módulo QR Code
  renderQrcodeScreen(tft, firstRender);
}

// renderRF433Screen is implemented in screen_rf433.h

// renderIRScreen is implemented in screen_ir.h

// renderRemoteScreen is implemented in screen_remote.h

#endif // DISPLAY_TFT_H
