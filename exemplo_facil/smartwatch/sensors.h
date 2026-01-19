#ifndef SENSORS_H
#define SENSORS_H

#include "config.h"
#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include "MAX30105.h"
#include "spo2_algorithm.h"
#include <math.h>

// ==========================================
// MÓDULO DE SENSORES - MPU6050 + MAX30102
// ==========================================

// Objetos dos sensores
Adafruit_MPU6050 mpu;
MAX30105 hrSensor;

// Dados unificados
SensorData sensorData = {0};

// Buffers MAX30102
uint32_t irBuf[MAX30102_BUFFER_SIZE];
uint32_t redBuf[MAX30102_BUFFER_SIZE];

// Estados MAX30102
float bpmEMA = -1;
float spo2EMA = -1;
int absenceCount = 0;
static byte ledPresentCurrent = MAX30102_LED_BRIGHT_PRESENT;

// Controle de tempo
unsigned long lastMPURead = 0;

// Funções públicas
void initSensors();
void updateSensors();
SensorData getSensorData();
void toggleHRSensor(bool on);
String getSensorsJSON();

// Funções auxiliares MAX30102
struct Stats { uint32_t mean, pp; };
static inline Stats statsOf(const uint32_t *v, int n);
static inline bool fingerPresent(const uint32_t *ir, int n, uint32_t &meanOut, uint32_t &ppOut);
static inline bool qualityOK(const Stats& ir, const Stats& rd);
static int estimateHrFromIR(const uint32_t *ir, int n, float sampleRate, uint32_t mean, float rms);

// ===== IMPLEMENTAÇÃO =====

Stats statsOf(const uint32_t *v, int n) {
  uint32_t mn = UINT32_MAX, mx = 0, sum = 0;
  for (int i = 0; i < n; i++) {
    uint32_t x = v[i];
    if (x < mn) mn = x;
    if (x > mx) mx = x;
    sum += x;
  }
  Stats s; s.mean = sum / (float)n; s.pp = mx - mn;
  return s;
}

bool fingerPresent(const uint32_t *ir, int n, uint32_t &meanOut, uint32_t &ppOut) {
  Stats s = statsOf(ir, n);
  meanOut = s.mean;
  ppOut = s.pp;
  return (meanOut > MAX30102_IR_MEAN_MIN) && (ppOut > MAX30102_IR_PP_MIN);
}

bool qualityOK(const Stats& ir, const Stats& rd) {
  float rIR = (ir.mean > 0) ? (float)ir.pp / (float)ir.mean : 0.f;
  float rRD = (rd.mean > 0) ? (float)rd.pp / (float)rd.mean : 0.f;

  bool irOK = ir.mean >= MAX30102_IR_MEAN_MIN && ir.mean <= MAX30102_IR_MEAN_MAX &&
              ir.pp >= MAX30102_IR_PP_MIN && ir.pp <= MAX30102_IR_PP_MAX &&
              rIR >= MAX30102_IR_ACDC_MIN && rIR <= MAX30102_IR_ACDC_MAX;

  bool rdOK = rd.mean >= MAX30102_RED_MEAN_MIN && rd.mean <= MAX30102_RED_MEAN_MAX &&
              rd.pp >= MAX30102_RED_PP_MIN && rd.pp <= MAX30102_RED_PP_MAX &&
              rRD >= (MAX30102_IR_ACDC_MIN/3.0f) && rRD <= MAX30102_IR_ACDC_MAX;

  return irOK && rdOK;
}

void initSensors() {
  // Inicializa MPU6050
  Serial.println("Inicializando MPU6050...");
  if (mpu.begin(MPU_I2C_ADDRESS, &Wire)) {
    mpu.setAccelerometerRange(MPU6050_RANGE_8_G);
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
    sensorData.mpuAvailable = true;
    Serial.println("MPU6050 inicializado!");
  } else {
    sensorData.mpuAvailable = false;
    Serial.println("MPU6050 nao encontrado!");
  }

  // Inicializa MAX30102
  Serial.println("Inicializando MAX30102...");
  if (hrSensor.begin(Wire, I2C_SPEED_FAST)) {
    hrSensor.setup(MAX30102_LED_BRIGHT_PRESENT, MAX30102_SAMPLE_AVG, MAX30102_LED_MODE, 
                   MAX30102_SAMPLE_RATE, MAX30102_PULSE_WIDTH, MAX30102_ADC_RANGE);
    sensorData.hrActive = false; // Desligado por padrão (economia)
    Serial.println("MAX30102 inicializado!");
  } else {
    Serial.println("MAX30102 nao encontrado!");
  }
}

void updateSensors() {
  // Atualiza MPU6050
  if (sensorData.mpuAvailable && millis() - lastMPURead > MPU_READ_INTERVAL_MS) {
    sensors_event_t a, g, temp;
    mpu.getEvent(&a, &g, &temp);
    
    sensorData.accelX = a.acceleration.x;
    sensorData.accelY = a.acceleration.y;
    sensorData.accelZ = a.acceleration.z;
    sensorData.gyroX = g.gyro.x;
    sensorData.gyroY = g.gyro.y;
    sensorData.gyroZ = g.gyro.z;
    sensorData.tempMPU = temp.temperature;
    
    lastMPURead = millis();
  }

  // Atualiza MAX30102 (modo não-bloqueante)
  if (sensorData.hrActive) {
    // TODO: Implementar leitura não-bloqueante com janela deslizante
    // Por enquanto, apenas placeholder
  }
}

SensorData getSensorData() {
  return sensorData;
}

void toggleHRSensor(bool on) {
  sensorData.hrActive = on;
  if (on) {
    hrSensor.setPulseAmplitudeRed(MAX30102_LED_BRIGHT_PRESENT);
    hrSensor.setPulseAmplitudeIR(MAX30102_LED_BRIGHT_PRESENT);
    Serial.println("Sensor HR ativado");
  } else {
    hrSensor.setPulseAmplitudeRed(MAX30102_LED_BRIGHT_ABSENT);
    hrSensor.setPulseAmplitudeIR(MAX30102_LED_BRIGHT_ABSENT);
    Serial.println("Sensor HR desativado");
  }
}

String getSensorsJSON() {
  String json = "{";
  json += "\"mpu\":{";
  json += "\"available\":" + String(sensorData.mpuAvailable ? "true" : "false") + ",";
  json += "\"accel\":{\"x\":" + String(sensorData.accelX) + ",\"y\":" + String(sensorData.accelY) + ",\"z\":" + String(sensorData.accelZ) + "},";
  json += "\"gyro\":{\"x\":" + String(sensorData.gyroX) + ",\"y\":" + String(sensorData.gyroY) + ",\"z\":" + String(sensorData.gyroZ) + "},";
  json += "\"temp\":" + String(sensorData.tempMPU);
  json += "},";
  json += "\"hr\":{";
  json += "\"bpm\":" + String(sensorData.bpm) + ",";
  json += "\"spo2\":" + String(sensorData.spo2) + ",";
  json += "\"finger\":" + String(sensorData.fingerPresent ? "true" : "false");
  json += "}";
  json += "}";
  return json;
}

#endif // SENSORS_H

