/*
  cubo3d.h
  Tela que desenha um cubo 3D wireframe rotacionado pelos ângulos do MPU6050.

  Regras seguidas:
  - Tudo em estilo C procedural (sem classes, sem .cpp).
  - Usa `extern TFT_eSPI tft;` para desenhar.
  - Consome variáveis de orientação: `mpuPitch`, `mpuRoll`, `mpuYaw` (em graus).
  - Controle de FPS leve (~30 FPS) usando millis().

  Integração:
  - Incluir este arquivo em `display_tft.h` (ou onde gerencia as telas).
  - Chamar `cube3d_init()` na inicialização do display.
  - No loop de telas:
      cube3d_update(millis());
      cube3d_draw();

  Observação: este arquivo não altera a lógica de leitura do MPU6050 — ele apenas consome
  os ângulos já processados expostos por `sensors.h`.
*/

#ifndef CUBO3D_H
#define CUBO3D_H

#ifdef __cplusplus
extern "C" {
#endif

#include <Arduino.h>
#include <math.h>
#include <TFT_eSPI.h> // só para o tipo TFT_eSPI e constantes de cores
// Consumir dados do sensor via API existente
#include "sensors.h" // fornece SensorData e getSensorData()

// Usar o objeto global do display (declarado em display_tft.h)
extern TFT_eSPI tft;

// Interface pública
void cube3d_init();
void cube3d_update(unsigned long nowMillis);
void cube3d_draw();

#ifdef __cplusplus
}
#endif

/* ===== Implementação interna (tudo neste arquivo, estilo C procedural) ===== */

#ifdef __cplusplus
extern "C" {
#endif

// --- Configuração e estado interno ---
// Parâmetros adaptados do código de referência para display 240x240
static const float CUBE3D_DEG_TO_RAD = 0.017453292519943295769236f;
static const float CUBE3D_RAD_TO_DEG = 57.295779513082320876798f;

// Constantes de desenho
static float HALF_SIDE = 40.0f; // Aresta do cubo (4x maior que referência)
static float FOCAL     = 150.0f; // Distância focal ajustada para tela maior
static float Z_OFFSET  = 160.0f; // Afastamento Z

// Cores
static const uint32_t CUBE_BG = TFT_BLACK;
static const uint32_t CUBE_LINE = TFT_GREEN; // Cubo verde solicitado
static const uint32_t CUBE_TEXT = TFT_GREEN;
static const uint32_t CUBE_ACCENT = TFT_CYAN;

// Estado do filtro e exibição
static float c_roll = 0.0f, c_pitch = 0.0f, c_yaw = 0.0f; // Estado real
static float roll_vis = 0.0f, pitch_vis = 0.0f, yaw_vis = 0.0f; // Suavizado
static const float ALPHA_FILTER = 0.97f; // Filtro complementar
static const float SMOOTH_VIS   = 0.90f; // Suavização visual

// Detecção de repouso
static bool stationary = false;
static int still_frames = 0;
static int move_frames = 0;
static const int STILL_FRAMES_TRG = 10;
static const int MOVE_FRAMES_TRG  = 2;
static const float GYRO_THRESH_DEG = 1.2f;
static const float ACC_NORM_THRESH = 0.08f;
static const float GRAVITY_G = 9.80665f;

// Bias do giroscópio (calibração)
static float gx_bias = 0.0f, gy_bias = 0.0f, gz_bias = 0.0f;

// Setas direcionais
static bool arrow_x_active = false, arrow_y_active = false, arrow_z_active = false;
static int arrow_x_timer = 0, arrow_y_timer = 0, arrow_z_timer = 0;
static const int ARROW_PERSISTENCE = 20;

// Tempo e Centro
// Declaração antecipada de variáveis de estado
static uint32_t c_lastMicros = 0;
static unsigned long c_lastUpdate = 0;
static const unsigned long UPDATE_MS = 33; // ~30 FPS
static bool cube_needsRedraw = false;

static int centerX = 120;
static int centerY = 120;

// Estrutura Vec3 para facilitar portabilidade
typedef struct { float x, y, z; } Vec3;

static const Vec3 CUBE_VERTS[8] = {
  {-1.0f, -1.0f, -1.0f}, { 1.0f, -1.0f, -1.0f},
  { 1.0f,  1.0f, -1.0f}, {-1.0f,  1.0f, -1.0f},
  {-1.0f, -1.0f,  1.0f}, { 1.0f, -1.0f,  1.0f},
  { 1.0f,  1.0f,  1.0f}, {-1.0f,  1.0f,  1.0f}
};

static const uint8_t CUBE_EDGES[12][2] = {
  {0,1},{1,2},{2,3},{3,0},
  {4,5},{5,6},{6,7},{7,4},
  {0,4},{1,5},{2,6},{3,7}
};

// --- Funções auxiliares matemáticas ---

static Vec3 rotateXYZ(Vec3 v, float rX, float rY, float rZ) {
  // Euler Z-Y-X (ordem do código referência)
  float cr = cosf(rX), sr = sinf(rX);
  float cp = cosf(rY), sp = sinf(rY);
  float cy = cosf(rZ), sy = sinf(rZ);

  // Rx
  float x1 = v.x;
  float y1 = cr*v.y - sr*v.z;
  float z1 = sr*v.y + cr*v.z;
  // Ry
  float x2 =  cp*x1 + sp*z1;
  float y2 =  y1;
  float z2 = -sp*x1 + cp*z1;
  // Rz
  Vec3 out;
  out.x = cy*x2 - sy*y2;
  out.y = sy*x2 + cy*y2;
  out.z = z2;
  return out;
}

static void projectTo2D(Vec3 v3, int *x2d, int *y2d) {
  // Aplica escala do cubo (HALF_SIDE) antes da projeção
  float x = v3.x * HALF_SIDE;
  float y = v3.y * HALF_SIDE;
  float z = (v3.z * HALF_SIDE) + Z_OFFSET;

  if (z < 1.0f) z = 1.0f; // evita divisão por zero/negativo
  
  float px = (x * FOCAL) / z;
  float py = (y * FOCAL) / z;
  
  *x2d = centerX + (int)px;
  *y2d = centerY - (int)py; // Y invertido na tela
}

// Desenha linha "grossa" (duplica pixels adjacentes)
static void drawThickLine(int x0, int y0, int x1, int y1, uint32_t color) {
  tft.drawLine(x0, y0, x1, y1, color);
  int dx = abs(x1 - x0);
  int dy = abs(y1 - y0);
  // Engrossa na direção perpendicular ao movimento principal
  if (dx >= dy) {
    tft.drawLine(x0, y0+1, x1, y1+1, color);
  } else {
    tft.drawLine(x0+1, y0, x1+1, y1, color);
  }
}

// --- API pública ---

void cube3d_init()
{
  Serial.println("cube3d_init: Resetando estado do cubo 3D");
  
  // Centraliza
  centerX = tft.width() / 2;
  centerY = tft.height() / 2;
  
  // Reinicia filtros e timers
  c_roll = c_pitch = c_yaw = 0.0f;
  roll_vis = pitch_vis = yaw_vis = 0.0f;
  c_lastUpdate = millis();
  c_lastMicros = micros();
  
  // Tenta estimar orientação inicial pelo acelerômetro imediatamente
  SensorData sd = getSensorData();
  float ax = sd.accelX;
  float ay = sd.accelY;
  float az = sd.accelZ;
  
  // Evita atan2(0,0)
  if (fabs(ax) > 0.1 || fabs(ay) > 0.1 || fabs(az) > 0.1) {
    c_roll  = atan2f(ay, az);
    c_pitch = atan2f(-ax, sqrtf(ay*ay + az*az));
    
    // Atualiza visualização imediatamente
    roll_vis = c_roll;
    pitch_vis = c_pitch;
  }
}

void cube3d_update(unsigned long nowMillis)
{
  // Controle de FPS (throttle)
  if (nowMillis - c_lastUpdate < UPDATE_MS) return;
  c_lastUpdate = nowMillis;
  cube_needsRedraw = true;

  // Cálculo de dt em segundos
  uint32_t mu = micros();
  float dt = (mu - c_lastMicros) / 1000000.0f;
  c_lastMicros = mu;
  if (dt <= 0.0f || dt > 0.5f) dt = UPDATE_MS / 1000.0f; // segurança

  SensorData sd = getSensorData();
  
  // Tira bias do gyro (bias assumido 0 ou calibrado externamente - por enquanto 0)
  float gx = sd.gyroX - gx_bias; // rad/s
  float gy = sd.gyroY - gy_bias; // rad/s
  float gz = sd.gyroZ - gz_bias; // rad/s

  // Aceleração em m/s^2
  float ax = sd.accelX;
  float ay = sd.accelY;
  float az = sd.accelZ;

  // Normas para detecção de repouso
  float acc_norm = sqrtf(ax*ax + ay*ay + az*az);

  // Verifica se está "quieto" (repouso)
  float gyro_abs_deg = fmaxf(fmaxf(fabsf(gx), fabsf(gy)), fabsf(gz)) * CUBE3D_RAD_TO_DEG;
  bool gyroQuiet  = (gyro_abs_deg < GYRO_THRESH_DEG);
  bool accelQuiet = (fabsf(acc_norm - GRAVITY_G) < (ACC_NORM_THRESH * GRAVITY_G));
  bool quiet      = gyroQuiet && accelQuiet;

  if (quiet) { still_frames++; move_frames = 0; }
  else       { move_frames++;  still_frames = 0; }

  if (!stationary && still_frames >= STILL_FRAMES_TRG) stationary = true;
  if ( stationary && move_frames  >= MOVE_FRAMES_TRG ) stationary = false;

  // Filtro complementar apenas quando em movimento
  if (!stationary) {
    float roll_acc  = atan2f(ay, az);
    float pitch_acc = atan2f(-ax, sqrtf(ay*ay + az*az));

    c_roll  = ALPHA_FILTER * (c_roll  + gx * dt) + (1.0f - ALPHA_FILTER) * roll_acc;
    c_pitch = ALPHA_FILTER * (c_pitch + gy * dt) + (1.0f - ALPHA_FILTER) * pitch_acc;
    c_yaw  += gz * dt; 
  } else {
    // Em repouso: zera yaw gradualmente (drift killer)
    c_yaw *= 0.95f; 
    
    // (Opcional) Calibração fina automática de bias poderia vir aqui
    // gx_bias = 0.999f*gx_bias + 0.001f*(sd.gyroX);
  }

  // Suavização para exibição (visual filter)
  float smooth_factor = stationary ? 0.98f : SMOOTH_VIS;
  roll_vis  = smooth_factor * roll_vis  + (1.0f - smooth_factor) * c_roll;
  pitch_vis = smooth_factor * pitch_vis + (1.0f - smooth_factor) * c_pitch;
  yaw_vis   = smooth_factor * yaw_vis   + (1.0f - smooth_factor) * c_yaw;
  
  // Atualiza lógica das setas direcionais
  float gx_deg = gx * CUBE3D_RAD_TO_DEG;
  float gy_deg = gy * CUBE3D_RAD_TO_DEG;
  float gz_deg = gz * CUBE3D_RAD_TO_DEG;
  const float ARROW_THR = 3.0f; // deg/s

  // Seta X (Roll)
  if (fabsf(gx_deg) > ARROW_THR) { arrow_x_active = true; arrow_x_timer = ARROW_PERSISTENCE; }
  else { if(arrow_x_timer > 0) arrow_x_timer--; else arrow_x_active = false; }
  
  // Seta Y (Pitch)
  if (fabsf(gy_deg) > ARROW_THR) { arrow_y_active = true; arrow_y_timer = ARROW_PERSISTENCE; }
  else { if(arrow_y_timer > 0) arrow_y_timer--; else arrow_y_active = false; }
  
  // Seta Z (Yaw)
  if (fabsf(gz_deg) > ARROW_THR) { arrow_z_active = true; arrow_z_timer = ARROW_PERSISTENCE; }
  else { if(arrow_z_timer > 0) arrow_z_timer--; else arrow_z_active = false; }
}

void cube3d_draw()
{
  if (!cube_needsRedraw) return;
  cube_needsRedraw = false;

  // Limpa tela
  tft.fillScreen(CUBE_BG);
  
  // --- 1. Desenhar Cubo ---
  int X[8], Y[8];
  for (int i = 0; i < 8; i++) {
    Vec3 vr = rotateXYZ(CUBE_VERTS[i], roll_vis, pitch_vis, yaw_vis);
    projectTo2D(vr, &X[i], &Y[i]);
  }
  for (int e = 0; e < 12; e++) {
    uint8_t a = CUBE_EDGES[e][0];
    uint8_t b = CUBE_EDGES[e][1];
    drawThickLine(X[a], Y[a], X[b], Y[b], CUBE_LINE);
  }

  // --- 2. Desenhar Setas Direcionais ---
  // Centro para setas: usar o mesmo centro da tela
  int ax = centerX;
  int ay = centerY;
  
  SensorData sd = getSensorData();
  float gx_deg = (sd.gyroX - gx_bias) * CUBE3D_RAD_TO_DEG;
  float gy_deg = (sd.gyroY - gy_bias) * CUBE3D_RAD_TO_DEG;
  float gz_deg = (sd.gyroZ - gz_bias) * CUBE3D_RAD_TO_DEG;

  tft.setTextColor(CUBE_ACCENT, CUBE_BG);
  
  // Seta X (Roll) - Direita/Esquerda
  if (arrow_x_active) {
    if (gx_deg > 0) { // Direita
      drawThickLine(ax+30, ay, ax+50, ay, CUBE_ACCENT);
      drawThickLine(ax+40, ay-5, ax+50, ay, CUBE_ACCENT);
      drawThickLine(ax+40, ay+5, ax+50, ay, CUBE_ACCENT);
    } else { // Esquerda
      drawThickLine(ax-30, ay, ax-50, ay, CUBE_ACCENT);
      drawThickLine(ax-40, ay-5, ax-50, ay, CUBE_ACCENT);
      drawThickLine(ax-40, ay+5, ax-50, ay, CUBE_ACCENT);
    }
  }

  // Seta Y (Pitch) - Cima/Baixo
  if (arrow_y_active) {
    if (gy_deg > 0) { // Baixo (ou cima dependendo do referencial, mantendo ref original)
      drawThickLine(ax, ay+30, ax, ay+50, CUBE_ACCENT);
      drawThickLine(ax-5, ay+40, ax, ay+50, CUBE_ACCENT);
      drawThickLine(ax+5, ay+40, ax, ay+50, CUBE_ACCENT);
    } else { // Cima
      drawThickLine(ax, ay-30, ax, ay-50, CUBE_ACCENT);
      drawThickLine(ax-5, ay-40, ax, ay-50, CUBE_ACCENT);
      drawThickLine(ax+5, ay-40, ax, ay-50, CUBE_ACCENT);
    }
  }

  // Seta Z (Yaw) - Rotação
  if (arrow_z_active) {
    tft.drawCircle(ax+60, ay-30, 8, CUBE_ACCENT);
    // Simplificado: apenas um indicador de rotação
    if (gz_deg > 0) tft.drawString(">", ax+72, ay-30);
    else            tft.drawString("<", ax+48, ay-30);
  }

  // --- 3. HUD (Status e Valores) ---
  tft.setTextSize(1);
  tft.setTextColor(CUBE_TEXT, CUBE_BG);
  
  // Topo: Status
  tft.setTextDatum(TC_DATUM); // Top Center
  tft.drawString(stationary ? "PARADO" : "MOVIMENTO", centerX, 15);
  
  if (arrow_x_active || arrow_y_active || arrow_z_active) {
    tft.setTextColor(CUBE_ACCENT, CUBE_BG);
    tft.drawString("SETAS ON", centerX, 25);
  }
  
  // Base: Ângulos
  tft.setTextDatum(BC_DATUM); // Bottom Center
  tft.setTextColor(CUBE_TEXT, CUBE_BG);
  char buf[64];
  snprintf(buf, sizeof(buf), "R:%3.0f P:%3.0f Y:%3.0f", 
           roll_vis * CUBE3D_RAD_TO_DEG, 
           pitch_vis * CUBE3D_RAD_TO_DEG, 
           yaw_vis * CUBE3D_RAD_TO_DEG);
  tft.drawString(buf, centerX, 220); // Y=220 (quase borda)

  // Laterais: ACC e GYR (simplificado para não poluir)
  tft.setTextColor(TFT_LIGHTGREY, CUBE_BG);
  tft.setTextDatum(ML_DATUM); // Middle Left
  tft.drawString("ACC", 10, centerY - 40);
  snprintf(buf, sizeof(buf), "X:%.1f", sd.accelX/GRAVITY_G); tft.drawString(buf, 10, centerY - 30);
  snprintf(buf, sizeof(buf), "Y:%.1f", sd.accelY/GRAVITY_G); tft.drawString(buf, 10, centerY - 20);
  snprintf(buf, sizeof(buf), "Z:%.1f", sd.accelZ/GRAVITY_G); tft.drawString(buf, 10, centerY - 10);

  tft.setTextDatum(MR_DATUM); // Middle Right
  tft.drawString("GYR", 230, centerY - 40);
  snprintf(buf, sizeof(buf), "X:%.0f", gx_deg); tft.drawString(buf, 230, centerY - 30);
  snprintf(buf, sizeof(buf), "Y:%.0f", gy_deg); tft.drawString(buf, 230, centerY - 20);
  snprintf(buf, sizeof(buf), "Z:%.0f", gz_deg); tft.drawString(buf, 230, centerY - 10);
}

/* ================= Comentários detalhados sobre a matemática =================

 - Definição dos vértices:
   Os 8 vértices estão definidos em `cubeBaseVerts` para um cubo centrado na origem
   com coordenadas em [-1, 1]. Isso facilita escalonamento uniforme por `cubeScale`.

 - Ordem das rotações:
   Aplicamos as rotações na ordem Rx -> Ry -> Rz (roll, pitch, yaw):
     1) Rx: rotação ao redor do eixo X (roll)
     2) Ry: rotação ao redor do eixo Y (pitch)
     3) Rz: rotação ao redor do eixo Z (yaw)
   Essa sequência determina como as rotações compostas afetam o ponto. Se desejar
   outra convenção (por ex. YXZ), ajuste a função `rotate_point`.

 - Projeção 3D -> 2D:
   Usamos uma projeção perspectiva simples:
     x' = (x * focalLength) / (z + cameraDistance)
     y' = (y * focalLength) / (z + cameraDistance)
   Em seguida, escalamos por `cubeScale` e transladamos para o centro da tela
   (`centerX`, `centerY`). `cameraDistance` evita divisão por zero e controla
   o quanto o cubo "entra" na câmera.

 - Segurança:
   Garantimos que `z + cameraDistance` não seja próximo de zero para evitar
   divisões por zero. Não implementamos clipping avançado; se o usuário vir
   artefatos quando partes do cubo estiverem atrás da câmera, incrementar
   `cameraDistance` ou usar clipping será necessário.

 ============================================================================*/

/* ===== Integração (exemplo a inserir em `display_tft.h`) =====

 // Enum de telas:
 typedef enum {
   SCREEN_WATCHFACE,
   SCREEN_SENSORS,
   SCREEN_QRCODE,
   SCREEN_CUBE3D   // nova tela
 } ScreenType;

 // Inicialização do display (chamar em setup/init)
 void initDisplay() {
   // ...
   cube3d_init();
 }

 // Atualização das telas (chamada no loop principal)
 void updateDisplay() {
   switch (currentScreen) {
     case SCREEN_CUBE3D:
       cube3d_update(millis());
       cube3d_draw();
       break;
     // demais telas...
   }
 }

 ============================================================================*/

/* ===== Reflexão sobre escalabilidade e manutenção (1-2 parágrafos) =====

 Este módulo foi implementado de forma isolada: todo o estado e funções ficam
 em `cubo3d.h` seguindo o padrão procedural do projeto. Para manter a
 legibilidade e facilitar testes, defino claramente as interfaces públicas
 (`cube3d_init`, `cube3d_update`, `cube3d_draw`) e mantive a lógica de leitura
 do MPU6050 completamente fora deste arquivo, como solicitado.

 Próximos passos sugeridos para escalabilidade/performace:
 - Separar a matemática (rotações/projeção) em um arquivo utilitário para reuso
   por outras telas 3D (ex.: `math3d.h`), caso o projeto passe a ter mais
   objetos 3D.
 - Implementar double buffering ou `tft.startWrite()`/`tft.endWrite()` para
   reduzir overhead de múltiplas chamadas de desenho e melhorar FPS.
 - Adicionar clipping e culling para evitar desenhar arestas com vértices
   atrás da câmera e reduzir overdraw em telas menores.

 ============================================================================*/

#ifdef __cplusplus
}
#endif

#endif // CUBO3D_H


