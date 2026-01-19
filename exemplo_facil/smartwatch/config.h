#ifndef CONFIG_H
#define CONFIG_H

// ==========================================
// CONFIGURAÇÕES CENTRALIZADAS - ESP32 Smartwatch
// ==========================================

// ===== PINOS I2C (compartilhado: OLED/MPU/MAX30102) =====
#define I2C_SDA 21
#define I2C_SCL 22

// ===== PINOS SPI (Display TFT 240x240 GC9A01) =====
#define TFT_MOSI 23 //SDA
#define TFT_SCK 18 //SCL
#define TFT_CS   5
#define TFT_DC   19  // Movido de GPIO16 para liberar UART2
#define TFT_RST  4
#define TFT_BL   15  // Backlight (opcional com PWM)

// ===== OUTROS PINOS =====
#define MIC_PIN  35  // Microfone MAX9814 (analógico)
#define LED_PIN  2   // LED onboard ESP32

// ===== RF433 (Comunicação Serial com Arduino) =====
// Nota: TFT_DC movido para GPIO19 para liberar GPIO16/GPIO17 para UART2
#define RF433_SERIAL_RX 16    // Pino RX para comunicação com Arduino (UART2 padrão)
#define RF433_SERIAL_TX 17    // Pino TX para comunicação com Arduino (UART2 padrão)
#define RF433_BAUD_RATE 115200 // Velocidade Serial

// ===== ÁUDIO =====
#define SAMPLE_RATE 8000              // Taxa de amostragem 8kHz
#define RECORD_SECONDS 3              // Duração da gravação em segundos
#define BUFFER_SIZE (SAMPLE_RATE * RECORD_SECONDS)
#define AUDIO_CHUNK_SIZE 512          // Tamanho dos blocos para envio

// ===== NTP (Network Time Protocol) =====
#define NTP_SERVER "pool.ntp.org"
#define GMT_OFFSET_SEC -4 * 3600      // GMT-4 (Brasil - horário padrão)
#define DAYLIGHT_OFFSET_SEC 0         // Sem horário de verão

// ===== WEBSOCKET =====
#define WS_HOST "esp-conecta.neurelix.com.br"
#define WS_PORT 443
#define WS_PATH "/"
#define WS_USER "esp"
#define WS_PASS "neurelix"

// ===== DNS SERVER (Portal de configuração) =====
#define DNS_PORT 53

// ===== SENSORES =====
// MPU6050
#define MPU_I2C_ADDRESS 0x68
#define MPU_READ_INTERVAL_MS 100      // Lê MPU a cada 100ms

// MAX30102 (Heart Rate & SpO2)
#define MAX30102_I2C_ADDRESS 0x57
#define MAX30102_SAMPLE_RATE 25       // 25Hz (fixo para algoritmo)
#define MAX30102_BUFFER_SIZE 100      // Amostras no buffer
#define MAX30102_STEP_SIZE 25         // Janela deslizante (25 amostras ~1s)
#define MAX30102_LED_BRIGHT_PRESENT 0x18
#define MAX30102_LED_BRIGHT_ABSENT  0x02
#define MAX30102_SAMPLE_AVG 8
#define MAX30102_LED_MODE 2           // RED + IR
#define MAX30102_PULSE_WIDTH 411
#define MAX30102_ADC_RANGE 8192

// Thresholds para detecção de dedo
#define MAX30102_IR_MEAN_MIN  15000UL
#define MAX30102_IR_MEAN_MAX  80000UL
#define MAX30102_RED_MEAN_MIN  5000UL
#define MAX30102_RED_MEAN_MAX 80000UL
#define MAX30102_IR_PP_MIN     1500UL
#define MAX30102_IR_PP_MAX    12000UL
#define MAX30102_RED_PP_MIN     600UL
#define MAX30102_RED_PP_MAX   10000UL

// Qualidade de sinal
#define MAX30102_IR_ACDC_MIN 0.06f    // 6%
#define MAX30102_IR_ACDC_MAX 0.60f    // 60%

// Heart Rate gating
#define HR_MIN 40
#define HR_MAX 180
#define HR_JUMP_MAX 25                // rejeita saltos > 25 bpm

#define ABSENCE_RESET_WINDOWS 3       // após ~3s sem dedo, zera buffers
#define READ_INTERVAL_MS 5000UL       // Intervalo entre leituras/report
#define STALE_MS 15000UL              // Expiração de valores suavizados

// ===== BOTÕES =====
#define LONG_PRESS_THRESHOLD 2000     // 2 segundos para clique longo

// ===== DISPLAY =====
#define TFT_UPDATE_INTERVAL 200       // Atualiza watchface a cada 200ms
#define TFT_STATIC_UPDATE_INTERVAL 1000  // Elementos estáticos a cada 1s

// ===== TEMPORIZAÇÕES =====
#define PING_INTERVAL_MS 50000        // Ping a cada 50s
#define DISPLAY_UPDATE_INTERVAL_MS 200 // Atualiza display a cada 200ms

// ===== MODOS DE TELA =====
enum ScreenMode {
  SCREEN_NONE,         // Estado inicial/nulo
  SCREEN_WATCHFACE,    // Watchface padrão com relógio e sensores
  SCREEN_SENSORS,      // Tela de sensores detalhada
  SCREEN_CALCULATOR,   // Calculadora
  SCREEN_NOTIFICATIONS,// Notificações
  SCREEN_STATUS,       // Status do sistema
  SCREEN_REMOTE,       // Controle Remoto do PC
  SCREEN_QRCODE,       // Tela de QR Code
  SCREEN_CUBE3D,       // Tela do cubo 3D (wireframe)
  SCREEN_IR,           // Códigos IR (infravermelho)
  SCREEN_RF433,        // Códigos RF 433MHz
  SCREEN_IMAGES        // Visualizador de imagens
};

// ===== CORES RGB565 (para TFT) =====
#define RGB(r, g, b) (((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3))

// Paleta padrão
#define COLOR_BG       RGB(12, 14, 18)
#define COLOR_FRAME    RGB(40, 45, 55)
#define COLOR_TEXT     RGB(235, 240, 245)
#define COLOR_SUB      RGB(160, 170, 185)
#define COLOR_ACCENT   RGB(0, 150, 255)

// Cores dos sensores
#define COLOR_HEART    RGB(255, 30, 60)
#define COLOR_PRESSURE RGB(255, 140, 20)
#define COLOR_CYAN     RGB(0, 255, 230)
#define COLOR_ORANGE   RGB(245, 100, 20)
#define COLOR_RED      RGB(230, 40, 60)
#define COLOR_GREEN    RGB(0, 255, 0)

// ===== WATCHFACE =====
#define CURRENT_WATCHFACE 3           // Versão padrão: 1, 2 ou 3

// ===== DADOS DE SENSORES (estrutura unificada) =====
struct SensorData {
  // MPU6050
  float accelX, accelY, accelZ;
  float gyroX, gyroY, gyroZ;
  float tempMPU;
  bool mpuAvailable;
  
  // MAX30102
  int bpm;              // -1 se inválido
  int spo2;             // -1 se inválido
  bool fingerPresent;
  bool hrActive;
  uint32_t irMean;
  uint32_t irPP;
  float acdc;
  int absenceCount;
};

#endif // CONFIG_H
