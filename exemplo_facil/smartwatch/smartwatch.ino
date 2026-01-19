#include "config.h"
#include "network.h"
#include "audio.h"
#include "sensors.h"
#include "buttons.h"
#include "display_tft.h"
#include "qr_code.h"

// Variáveis globais (definidas em network.h)
String ssid;
String password;
String emailLogin;
String randomId;
String remoteSecret; // Variável adicionada
Preferences preferences;
WebServer server(80);
WebSocketsClient webSocket;
DNSServer dnsServer;

void handleWebSocketEvent(WStype_t type, uint8_t * payload, size_t length) {
  switch (type) {
    case WStype_DISCONNECTED:
      Serial.println("Desconectado do servidor WebSocket");
      break;
    case WStype_CONNECTED:
      Serial.println("Conectado ao servidor WebSocket");
      {
        String identificador = ssid + "|" + password + "|" + emailLogin + "|" + randomId;
        webSocket.sendTXT(identificador);
      }
      break;
    case WStype_TEXT:
      Serial.printf("Comando WS recebido (bytes=%u)\n", (unsigned)length);
      // Cria String com tamanho conhecido para preservar qualquer byte (sem truncar em NULs)
      String cmd = String((char*)payload, length);
      Serial.printf("Cmd (len=%d): '%s'\n", cmd.length(), cmd.c_str());
      // Loga últimos bytes em hex para diagnosticar truncamento/bytes invisíveis
      {
        int startIdx = (int)length - 16;
        if (startIdx < 0) startIdx = 0;
        Serial.print("Últimos bytes (hex): ");
        for (size_t i = startIdx; i < length; ++i) {
          Serial.printf("%02X ", (unsigned)payload[i]);
        }
        Serial.println();
      }

      // Filtra comandos conhecidos vs mensagens
      if (cmd == "limpar") {
        webSocket.sendTXT("Credenciais Wi-Fi apagadas. Reiniciando...");
        preferences.remove("ssid");
        preferences.remove("password");
        preferences.remove("email");
        preferences.end();
        WiFi.disconnect(true, true);
        delay(1000);
        ESP.restart();
      } else if (cmd == "stream_on") {
        startStreaming();
        webSocket.sendTXT("streaming_on");
      } else if (cmd == "stream_off") {
        stopStreaming();
        webSocket.sendTXT("streaming_off");
      } else if (cmd == "ping") {
        // Comando de ping - apenas responde, não adiciona notificação
        webSocket.sendTXT("pong");
      } else if (cmd.startsWith("rf_send:")) {
        // rf_send:1 - envia código RF #1
        int index = cmd.substring(8).toInt();
        if (sendRFCode(index)) {
          webSocket.sendTXT("RF: Enviando código #" + String(index));
        } else {
          webSocket.sendTXT("RF: Código inválido #" + String(index));
        }
      } else if (cmd == "rf_list") {
        // Lista códigos RF salvos
        if (listRFCodes()) {
          String response = "RF: Listando códigos (";
          response += String(getRFCodesCount()) + ")";
          webSocket.sendTXT(response);
        } else {
          webSocket.sendTXT("RF: Erro ao listar códigos");
        }
      } else if (cmd == "rf_clear") {
        // Limpa lista de códigos RF
        if (clearRFCodes()) {
          webSocket.sendTXT("RF: Limpando lista de códigos");
        } else {
          webSocket.sendTXT("RF: Erro ao limpar lista");
        }
      } else if (cmd == "rf_learn") {
        // Entra em modo aprendizado
        if (learnRFCode()) {
          webSocket.sendTXT("RF: Entrando em modo aprendizado");
        } else {
          webSocket.sendTXT("RF: Erro ao iniciar aprendizado");
        }
      } else if (cmd == "rf_status") {
        // Status da comunicação RF433
        String status = "RF: ";
        if (isRF433Connected()) {
          status += "Conectado (" + String(getRFCodesCount()) + " códigos)";
        } else {
          status += "Desconectado";
        }
        webSocket.sendTXT(status);
      } else if (cmd.startsWith("qrcode|")) {
        // Comando para definir texto do QR Code: qrcode|texto_aqui
        String qrText = cmd.substring(7); // Remove "qrcode|"
        qrText.trim(); // remove CR/LF e espaços indesejados nas bordas
        Serial.printf("QR recebido após trim (len=%d): '%s'\n", qrText.length(), qrText.c_str());

        // Limite conhecido do renderer (testado): 154 caracteres
        const int QR_MAX_LEN = 154;
        if (qrText.length() > QR_MAX_LEN) {
          String err = "ERRO: QR Code muito longo (len=" + String(qrText.length()) + ", max=" + String(QR_MAX_LEN) + ") - não exibido";
          webSocket.sendTXT(err);
          Serial.println(err);
        } else {
          setQrcodeText(qrText);
          webSocket.sendTXT("QR Code atualizado: " + qrText);
          Serial.println("QR Code definido via WebSocket: " + qrText);
        }
      } else {
        // Se não é um comando conhecido, trata como mensagem/notificação
        addNotification(cmd);
        webSocket.sendTXT("Mensagem recebida: " + cmd);
        Serial.println("Mensagem adicionada às notificações: " + cmd);
      }
      break;
  }
}

void setup() {
  Serial.begin(115200);
  Serial.println("\n=== ESP32 Smartwatch ===");
  
  randomSeed(esp_random());
  
  // Inicia I2C
  Wire.begin(I2C_SDA, I2C_SCL);
  
  // Inicializa módulos
  initDisplay();
  showMessage("Inicializando...");
  
  initAudio();
  initSensors();
  initButtons();
  initNetwork();
  initRF433();
  
  showMessage("Sistema pronto!");
  delay(1000);
  
  Serial.println("Sistema inicializado!");
}

void loop() {
  updateNetwork();
  updateSensors();
  updateButtons();
  updateAudio();
  updateDisplay();
  updateRF433();

  delay(10);
}
