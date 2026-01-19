#ifndef NETWORK_H
#define NETWORK_H

#include "config.h"
#include <WiFi.h>
#include <WebSocketsClient.h>
#include <WebServer.h>
#include <Preferences.h>
#include <DNSServer.h>
#include <time.h>
#include <SPI.h>
#include <Wire.h>
#include <HTTPClient.h>

// ==========================================
// MÓDULO DE REDE - WiFi, WebSocket, NTP
// ==========================================

// Variáveis globais
extern String ssid;
extern String password;
extern String emailLogin;
extern String randomId;
extern String remoteSecret; // Segredo para controle remoto
extern Preferences preferences;
extern WebServer server;
extern WebSocketsClient webSocket;
extern DNSServer dnsServer;

// Estados
bool ntpSincronizado = false;
unsigned long lastPing = 0;

// Funções públicas
void initNetwork();
void updateNetwork();
void handleWebSocketEvent(WStype_t type, uint8_t * payload, size_t length);
String getTimeString();
String getDateString();
int getCurrentYear();
bool isWiFiConnected();

// Função auxiliar para gerar ID aleatório
String gerarRandom(int len);

// Portal de configuração
void startConfigPortal();
void handleRoot();
void handleSave();

// NTP
void configurarNTP();

// ===== IMPLEMENTAÇÃO =====

String gerarRandom(int len) {
  const char charset[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  String res;
  for (int i = 0; i < len; i++) {
    res += charset[random(sizeof(charset) - 1)];
  }
  return res;
}

void handleRoot() {
  // Faz scan de redes Wi-Fi disponíveis
  int n = WiFi.scanNetworks();
  String options = "";
  for (int i = 0; i < n; i++) {
    String ssidItem = WiFi.SSID(i);
    if (ssidItem.length() == 0) continue;
    if (options.indexOf("value='" + ssidItem + "'") >= 0) continue;
    int rssi = WiFi.RSSI(i);
    options += "<option value='" + ssidItem + "'>" + ssidItem + " (" + String(rssi) + " dBm)</option>";
  }
  if (options.length() == 0) {
    options = "<option>Nenhuma rede encontrada</option>";
  }

  String page = R"rawliteral(
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset='utf-8'>
      <meta name='viewport' content='width=device-width,initial-scale=1'>
      <title>Configuracao Smartwatch ESP32</title>
      <style>
        body{font-family:Arial,Helvetica,sans-serif;background:#FFFFFF;margin:0;padding:0;color:#11181C;}
        .container{max-width:400px;margin:40px auto;padding:24px;background:#F2F2F2;border-radius:12px;box-shadow:0 2px 8px rgba(0,0,0,0.1);}        
        h2{text-align:center;color:#FF7A00;margin-bottom:24px;}
        label{display:block;margin-bottom:6px;font-weight:600;}
        select,input{width:100%;padding:10px;margin-bottom:16px;border:1px solid #E0E0E0;border-radius:6px;box-sizing:border-box;}
        button{width:100%;background:#FF7A00;color:#fff;padding:12px 0;border:none;border-radius:6px;font-size:16px;font-weight:bold;cursor:pointer;}
        button:active{opacity:0.9;}
        .refresh{background:#006AFF;margin-top:-8px;margin-bottom:16px;}
      </style>
      <script>
        function copySSID(){var sel=document.getElementById('ssidSelect');document.getElementById('ssid').value=sel.value;}
        function refresh(){location.reload();}
      </script>
    </head>
    <body>
      <div class='container'>
        <h2>Configurar Wi-Fi & Email</h2>
        <form action='/save' method='POST'>
          <label for='ssidSelect'>Rede Wi-Fi</label>
          <select id='ssidSelect' onchange='copySSID()'>
            %OPTIONS%
          </select>
          <input type='hidden' id='ssid' name='ssid'>
          <button type='button' class='refresh' onclick='refresh()'>Atualizar lista</button>
          <label for='password'>Senha</label>
          <input type='text' id='password' name='password' placeholder='Senha do Wi-Fi' required>
          <label for='email'>E-mail</label>
          <input type='email' id='email' name='email' placeholder='Seu e-mail' required>
          <button type='submit'>Salvar</button>
        </form>
      </div>
      <script>copySSID();</script>
    </body>
    </html>
  )rawliteral";

  page.replace("%OPTIONS%", options);
  server.send(200, "text/html", page);
}

void handleSave() {
  if (server.hasArg("ssid") && server.hasArg("password") && server.hasArg("email")) {
    preferences.putString("ssid", server.arg("ssid"));
    preferences.putString("password", server.arg("password"));
    preferences.putString("email", server.arg("email"));
    server.send(200, "text/html", "<html><body><h2>Dados salvos! Reiniciando...</h2></body></html>");
    delay(2000);
    ESP.restart();
  } else {
    server.send(400, "text/plain", "Parametros ausentes");
  }
}

void startConfigPortal() {
  IPAddress local_ip(192, 168, 10, 1);
  IPAddress gateway(192, 168, 10, 1);
  IPAddress subnet(255, 255, 255, 0);

  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(local_ip, gateway, subnet);
  WiFi.softAP("Smartwatch Config");

  Serial.println("Portal de configuracao ativo. Conecte-se a rede: Smartwatch Config");
  Serial.print("Acesse: http://");
  Serial.println(local_ip);

  dnsServer.start(DNS_PORT, "*", local_ip);
  server.on("/", handleRoot);
  server.on("/save", HTTP_POST, handleSave);
  server.begin();
}

// Função alternativa usando API HTTP para sincronização de tempo
bool syncTimeFromAPI() {
  HTTPClient http;
  http.begin("http://worldtimeapi.org/api/timezone/America/Cuiaba");
  http.setTimeout(8000); // 8 segundos timeout (aumentado)

  Serial.println("Tentando sincronizar via API HTTP...");
  Serial.print("Fazendo requisição para: ");
  Serial.println("http://worldtimeapi.org/api/timezone/America/Cuiaba");

  int httpCode = http.GET();
  Serial.printf("Código HTTP: %d\n", httpCode);

  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    Serial.println("Resposta recebida:");
    Serial.println(payload);

    http.end();

    // Procurar pelo campo "unixtime" no JSON
    int unixtimeStart = payload.indexOf("\"unixtime\":");
    Serial.printf("Posição 'unixtime': %d\n", unixtimeStart);

    if (unixtimeStart != -1) {
      int valueStart = payload.indexOf(':', unixtimeStart) + 1;
      int valueEnd = payload.indexOf(',', valueStart);
      if (valueEnd == -1) valueEnd = payload.indexOf('}', valueStart);

      String unixtimeStr = payload.substring(valueStart, valueEnd);
      unixtimeStr.trim();

      Serial.printf("String unixtime extraída: '%s'\n", unixtimeStr.c_str());
      time_t unixTime = unixtimeStr.toInt();
      Serial.printf("Valor unixtime convertido: %ld\n", unixTime);

      if (unixTime > 0) {
        // A API já retorna o tempo local, então não precisamos ajustar
        struct timeval tv;
        tv.tv_sec = unixTime;
        tv.tv_usec = 0;
        settimeofday(&tv, NULL);

        Serial.println("Tempo sincronizado via API HTTP!");
        return true;
      } else {
        Serial.println("Valor unixtime inválido");
      }
    } else {
      Serial.println("Campo 'unixtime' não encontrado no JSON");
    }
  } else {
    Serial.printf("Erro HTTP: %d\n", httpCode);
    String errorMsg = http.errorToString(httpCode);
    Serial.println("Mensagem de erro: " + errorMsg);
  }

  http.end();
  Serial.println("Falha ao sincronizar via API HTTP");
  return false;
}

void configurarNTP() {
  // Primeiro tenta NTP tradicional
  configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, NTP_SERVER);

  Serial.println("Sincronizando com servidor NTP...");

  int tentativas = 0;
  while (time(nullptr) < 24 * 3600 && tentativas < 10) {
    Serial.print(".");
    delay(1000);
    tentativas++;
  }

  if (time(nullptr) > 24 * 3600) {
    ntpSincronizado = true;
    Serial.println("\nNTP sincronizado com sucesso!");
    return;
  }

  Serial.println("\nNTP tradicional falhou, tentando API HTTP...");

  // Fallback: tenta API HTTP
  if (syncTimeFromAPI()) {
    ntpSincronizado = true;
    Serial.println("Sincronização NTP concluída (via API HTTP)!");
  } else {
    Serial.println("Falha em todas as tentativas de sincronização NTP");
  }
}

String getTimeString() {
  if (!ntpSincronizado) {
    return "00:00:00";
  }

  time_t now = time(nullptr);
  struct tm *tmNow = localtime(&now);

  char buf[9];
  sprintf(buf, "%02d:%02d:%02d", tmNow->tm_hour, tmNow->tm_min, tmNow->tm_sec);
  return String(buf);
}

String getDateString() {
  if (!ntpSincronizado) {
    return "01/01";
  }

  time_t now = time(nullptr);
  struct tm *tmNow = localtime(&now);

  char buf[6];
  sprintf(buf, "%02d/%02d", tmNow->tm_mday, tmNow->tm_mon + 1);
  return String(buf);
}

int getCurrentYear() {
  if (!ntpSincronizado) {
    return 2025;
  }

  time_t now = time(nullptr);
  struct tm *tmNow = localtime(&now);

  return tmNow->tm_year + 1900;
}

bool isWiFiConnected() {
  return WiFi.status() == WL_CONNECTED;
}

void initNetwork() {
  preferences.begin("credenciais", false);
  ssid = preferences.getString("ssid", "");
  password = preferences.getString("password", "");
  emailLogin = preferences.getString("email", "");

  // Carrega ou gera identificador aleatório
  randomId = preferences.getString("rand", "");
  if (randomId.length() == 0) {
    randomId = gerarRandom(5);
    preferences.putString("rand", randomId);
  }

  // Carrega ou gera segredo aleatório para controle remoto
  remoteSecret = preferences.getString("rsecret", "");
  if (remoteSecret.length() == 0) {
    remoteSecret = gerarRandom(6); // 6 chars para segredo
    preferences.putString("rsecret", remoteSecret);
  }

  if (ssid.length() == 0) {
    Serial.println("Credenciais nao encontradas, iniciando portal...");
    startConfigPortal();
    return;
  }

  Serial.println("Conectando WiFi...");
  WiFi.begin(ssid.c_str(), password.c_str());
  unsigned long startAttemptTime = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startAttemptTime < 15000) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("\nFalha ao conectar, iniciando portal...");
    startConfigPortal();
    return;
  }

  Serial.println("\nWiFi conectado!");
  Serial.print("IP: ");
  Serial.println(WiFi.localIP());

  // Configura NTP
  configurarNTP();

  // Configura WebSocket
  webSocket.setReconnectInterval(5000);
  webSocket.setAuthorization(WS_USER, WS_PASS);
  webSocket.setExtraHeaders("Sec-WebSocket-Extensions:");
  webSocket.onEvent(handleWebSocketEvent);
  webSocket.beginSSL(WS_HOST, WS_PORT, WS_PATH);
}

void updateNetwork() {
  if (WiFi.status() == WL_CONNECTED) {
    webSocket.loop();

    // Ping periódico
    if (millis() - lastPing > PING_INTERVAL_MS) {
      webSocket.sendTXT("ping");
      Serial.println("ping");
      lastPing = millis();
    }
  } else {
    // No modo AP (portal de configuração)
    dnsServer.processNextRequest();
    server.handleClient();
  }
}

#endif // NETWORK_H
