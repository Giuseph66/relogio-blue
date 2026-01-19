#ifndef QR_CODE_H
#define QR_CODE_H

#include "config.h"
#include <SPI.h>
#include <TFT_eSPI.h>
#include <qrcode_espi.h>

// ==========================================
// MÓDULO DE QR CODE PARA TFT_eSPI
// ==========================================

// Estado do QR Code
extern String qrCodeText;
extern TFT_eSPI *display;
extern QRcode_eSPI *qrcode;
extern bool showWifiCredentials; // true = credenciais Wi-Fi, false = IP de configuração

// Funções públicas
void initQrcode();
void renderQrcodeScreen(TFT_eSPI &tft, bool firstRender);
void setQrcodeText(String text);
void setQrcodeWifiMode(); // Define modo Wi-Fi
void setQrcodeIpMode();   // Define modo IP
void forceQrcodeRedraw(); // Força redesenho da tela QR Code

// ===== IMPLEMENTAÇÃO =====

// Modos do QR Code
enum QrCodeMode {
  QRCODE_CUSTOM,     // QR Code personalizado (via WebSocket)
  QRCODE_WIFI,       // QR Code para conectar ao Wi-Fi do ESP
  QRCODE_IP          // QR Code com IP do ESP
};

// Estado global
String qrCodeText = "https://neurelix.com.br"; // Texto inicial
TFT_eSPI *display = nullptr;
QRcode_eSPI *qrcode = nullptr;
QrCodeMode currentQrMode = QRCODE_CUSTOM; // Modo atual do QR Code
bool forceRedraw = false; // Flag para forçar redesenho da tela QR Code

void initQrcode() {
  // Inicializa display e QR code seguindo o exemplo do usuário
  if (display == nullptr) {
    display = new TFT_eSPI();
    display->begin();
    display->setRotation(0);
  }

  if (qrcode == nullptr) {
    qrcode = new QRcode_eSPI(display);
    qrcode->init();
  }

  Serial.println("QR Code module initialized");
}

void setQrcodeText(String text) {
  // Limita o tamanho do texto para evitar problemas de memória
  if (text.length() > 1024) {
    text = text.substring(0, 1024);
  }
  qrCodeText = text;
  currentQrMode = QRCODE_CUSTOM; // Volta para modo personalizado
  Serial.printf("[QR] Texto do QR Code atualizado (len=%d)\n", qrCodeText.length());

  // Força redesenho da tela QR Code quando atualizado via WebSocket
  forceQrcodeRedraw();
}

void setQrcodeWifiMode() {
  currentQrMode = QRCODE_WIFI;
  Serial.println("[QR] Modo Wi-Fi ativado - QR Code para conectar ao Wi-Fi do ESP");
  forceQrcodeRedraw();
}

void setQrcodeIpMode() {
  currentQrMode = QRCODE_IP;
  Serial.println("[QR] Modo IP ativado - QR Code com IP do ESP");
  forceQrcodeRedraw();
}

void forceQrcodeRedraw() {
  forceRedraw = true;
  Serial.println("[QR] Redesenho da tela QR Code forçado");
}

void renderQrcodeScreen(TFT_eSPI &tft, bool firstRender) {
  Serial.printf("[QR] renderQrcodeScreen called - firstRender: %s, forceRedraw: %s\n",
                firstRender ? "true" : "false", forceRedraw ? "true" : "false");

  // Só renderiza quando a tela abre pela primeira vez OU quando forçado
  if (!firstRender && !forceRedraw) {
    return; // Não pisca - mantém o conteúdo atual
  }

  // Reseta a flag de força de redesenho
  forceRedraw = false;

  Serial.println("[QR] ===== RENDERIZANDO TELA QR CODE =====");

  // Limpa a tela apenas uma vez
  tft.fillScreen(COLOR_BG);

  // Título da tela
  tft.setTextColor(COLOR_TEXT, COLOR_BG);
  tft.setTextDatum(MC_DATUM);
  tft.setTextFont(1);
  tft.drawString("QR Code", 120, 10);

  String codeToDisplay;

  // Determina o conteúdo baseado no modo atual
  switch (currentQrMode) {
    case QRCODE_WIFI: {
      // MODO WIFI: QR Code para conectar ao Wi-Fi do ESP
      String apSSID = "Smartwatch Config";
      String apPassword = "";
      String apIP = WiFi.softAPIP().toString();

      if (apPassword.length() == 0) {
        codeToDisplay = "WIFI:S:" + apSSID + ";T:nopass;;";
      } else {
        codeToDisplay = "WIFI:S:" + apSSID + ";T:WPA;P:" + apPassword + ";;";
      }
      codeToDisplay += "\nRede: " + apSSID;
      codeToDisplay += "\nConfig: http://" + apIP;

      tft.setTextColor(COLOR_ACCENT, COLOR_BG);
      tft.setTextFont(1);
      tft.drawString("MODO WIFI", 120, 200);
      tft.drawString("S7=WiFi  S8=IP", 120, 215);

      Serial.println("[QR] Modo Wi-Fi ativo - QR Code para conectar ao Wi-Fi do ESP");
      break;
    }

    case QRCODE_IP: {
      // MODO IP: QR Code com o IP do ESP
      String apIP = WiFi.softAPIP().toString();
      codeToDisplay = "http://" + apIP;

      tft.setTextColor(COLOR_ACCENT, COLOR_BG);
      tft.setTextFont(1);
      tft.drawString("MODO IP", 120, 200);
      tft.drawString("S7=WiFi  S8=IP", 120, 215);

      Serial.println("[QR] Modo IP ativo - QR Code com IP do ESP");
      break;
    }

    case QRCODE_CUSTOM:
    default: {
      // MODO PERSONALIZADO: Usa o texto definido via WebSocket
      codeToDisplay = qrCodeText;

      if (codeToDisplay.length() == 0) {
        // Nenhum QR personalizado definido
        tft.setTextColor(COLOR_SUB);
        tft.setTextFont(1);
        tft.drawString("Nenhum QR Code definido", 120, 100);
        tft.drawString("Use: qrcode|seu_texto", 120, 120);
        tft.drawString("via WebSocket", 120, 135);
        tft.drawString("S7=WiFi  S8=IP", 120, 155);
        Serial.println("[QR] Modo personalizado - nenhum texto definido");
        return;
      }

      tft.setTextColor(COLOR_ACCENT, COLOR_BG);
      tft.setTextFont(1);
      tft.drawString("QR PERSONALIZADO", 120, 200);
      tft.drawString("S7=WiFi  S8=IP", 120, 215);

      Serial.println("[QR] Modo personalizado ativo");
      break;
    }
  }

  // Gera o QR Code usando a biblioteca
  if (qrcode == nullptr) {
    Serial.println("[QR] ERRO: QRcode não inicializado!");
    tft.setTextColor(TFT_RED);
    tft.drawString("ERRO: QR Code", 120, 100);
    tft.drawString("nao inicializado", 120, 120);
    return;
  }

  // Log comprimento do payload antes de gerar
  Serial.printf("[QR] payload length=%d\n", codeToDisplay.length());
  Serial.printf("[QR] QR Code (preview 0..30): %s\n", codeToDisplay.substring(0, 30).c_str());

  // Tenta gerar o QR Code (create() retorna void)
  qrcode->create(codeToDisplay.c_str());

  Serial.println("[QR] create() chamado para gerar o QR Code");

  // Verifica se o QR Code foi realmente criado (pode falhar silenciosamente)
  if (qrcode != nullptr) {
    Serial.println("[QR] QR Code criado com sucesso na tela");
  } else {
    Serial.println("[QR] ERRO: QRcode object é null");

    // Fallback visual simples
    tft.setTextColor(TFT_RED);
    tft.setTextFont(1);
    tft.drawString("ERRO QR Code", 120, 100);
    tft.drawRect(60, 60, 120, 120, TFT_RED);
    tft.fillRect(80, 80, 80, 80, TFT_BLACK);
  }
}


#endif // QR_CODE_H