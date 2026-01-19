// screen_ir.h
#ifndef SCREEN_IR_H
#define SCREEN_IR_H

#include "config.h"
#include "rf433.h"
#include <TFT_eSPI.h>

extern TFT_eSPI tft;
extern int currentIRCodeIndex;

void renderIRScreen(bool firstRender) {
  if (firstRender) {
    tft.fillScreen(COLOR_BG);

    // Título
    tft.setTextColor(COLOR_TEXT, COLOR_BG);
    tft.setTextSize(2);
    tft.drawString("Codigos IR (Infravermelho)", 120, 15);

    // Status de conexão (usa mesma função)
    tft.setTextSize(1);
    String status = isRF433Connected() ? "Conectado" : "Desconectado";
    tft.drawString(status, 120, 40);

    // Botão de navegar/ações
    tft.setTextColor(COLOR_ACCENT, COLOR_BG);
    tft.drawString("S13: Anterior", 60, 210);
    tft.drawString("S14: Proximo", 180, 210);
    tft.drawString("S1: Enviar", 120, 225);
  }

  int codesCount = getIRCodesCount();
  SavedCode* codes = getIRCodes();

  // Garante que o índice está dentro dos limites
  if (currentIRCodeIndex >= codesCount && codesCount > 0) {
    currentIRCodeIndex = codesCount - 1;
  } else if (codesCount == 0) {
    currentIRCodeIndex = 0;
  }

  // Limpa área de conteúdo
  tft.fillRect(10, 55, 220, 150, COLOR_BG);

  if (codesCount == 0) {
    // Nenhum código salvo
    tft.setTextColor(COLOR_SUB, COLOR_BG);
    tft.setTextSize(2);
    tft.drawString("Nenhum codigo", 120, 80);
    tft.drawString("salvo", 120, 100);

    tft.setTextSize(1);
    tft.setTextColor(COLOR_ACCENT, COLOR_BG);
    tft.drawString("S2: Listar  S3: Aprender", 120, 130);
    tft.drawString("S4: Limpar   S1: Enviar", 120, 145);
  } else {
    // Exibe código atual
    SavedCode code = codes[currentIRCodeIndex];

    // Índice e contador
    tft.setTextColor(COLOR_ACCENT, COLOR_BG);
    tft.setTextSize(1);
    String counter = String(currentIRCodeIndex + 1) + "/" + String(codesCount);
    tft.drawString(counter, 120, 55);

    // Detalhes do código
    tft.setTextColor(COLOR_TEXT, COLOR_BG);
    tft.setTextSize(1);
    tft.drawString("Valor:", 20, 75);
    tft.drawString(String(code.value), 80, 75);

    tft.drawString("Bits:", 20, 90);
    tft.drawString(String(code.bitlen), 80, 90);

    tft.drawString("Delay(us):", 20, 105);
    tft.drawString(String(code.delayUs), 80, 105);

    tft.drawString("Protocolo:", 20, 120);
    tft.drawString(String(code.proto), 80, 120);

    // Área de instruções
    tft.setTextColor(COLOR_SUB, COLOR_BG);
    tft.setTextSize(1);
    tft.drawString("Pressione S1 para enviar", 120, 145);
    tft.drawString("este codigo via IR", 120, 160);
  }
}

#endif // SCREEN_IR_H


