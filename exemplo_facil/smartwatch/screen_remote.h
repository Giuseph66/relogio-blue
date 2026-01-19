#ifndef SCREEN_REMOTE_H
#define SCREEN_REMOTE_H

#include "config.h"
#include "network.h"
#include <TFT_eSPI.h>

extern TFT_eSPI tft;
extern String randomId;
extern String remoteSecret;

// Estado da página: 0=Info, 1=Setas, 2=Numeros
static int remotePage = 0;

void renderRemoteScreen(bool firstRender) {
  // Se for firstRender, limpa a tela toda
  if (firstRender) {
    tft.fillScreen(COLOR_BG);
  } else {
    // Se não for firstRender (mudança de página), limpa área de conteúdo
    tft.fillRect(0, 40, 240, 200, COLOR_BG);
  }

  // Título Comum
  if (firstRender) {
    tft.setTextColor(COLOR_TEXT, COLOR_BG);
    tft.setTextDatum(TC_DATUM);
    tft.setTextFont(2);
    tft.drawString("Controle Remoto", 120, 10);
    tft.drawLine(20, 32, 220, 32, COLOR_FRAME);
  }

  // Renderiza conteúdo baseado na página
  if (remotePage == 0) {
    // --- PÁGINA 0: INFO ---
    
    // ID
    tft.setTextDatum(MC_DATUM);
    tft.setTextFont(2);
    tft.setTextColor(COLOR_SUB, COLOR_BG);
    tft.drawString("ID do Dispositivo:", 120, 60);
    tft.setTextFont(4);
    tft.setTextColor(COLOR_ACCENT, COLOR_BG);
    tft.drawString(randomId, 120, 85);

    // Segredo
    tft.setTextFont(2);
    tft.setTextColor(COLOR_SUB, COLOR_BG);
    tft.drawString("Segredo:", 120, 115);
    tft.setTextFont(4);
    tft.setTextColor(COLOR_GREEN, COLOR_BG);
    tft.drawString(remoteSecret, 120, 140);

    // Rodapé de Navegação
    tft.setTextFont(1);
    tft.setTextColor(COLOR_TEXT, COLOR_BG);
    tft.drawString("<-: Proximo (Setas)", 120, 200);
    tft.setTextColor(COLOR_SUB, COLOR_BG);
    tft.drawString("Use com App Desktop", 120, 220);

  } else if (remotePage == 1) {
    // --- PÁGINA 1: SETAS ---
    
    tft.setTextDatum(MC_DATUM);
    tft.setTextFont(2);
    tft.setTextColor(COLOR_ACCENT, COLOR_BG);
    tft.drawString("Modo Navegacao", 120, 50);

    // Desenha layout de cruz
    int cx = 120;
    int cy = 130;
    int step = 40;

    // CIMA (S3)
    tft.drawRect(cx - 20, cy - step - 15, 40, 30, COLOR_FRAME);
    tft.drawString("2", cx, cy - step);
    tft.drawString("^", cx, cy - step - 25); // Símbolo visual acima

    // BAIXO (S11)
    tft.drawRect(cx - 20, cy + step - 15, 40, 30, COLOR_FRAME);
    tft.drawString("8", cx, cy + step);
    tft.drawString("v", cx, cy + step + 25);

    // ESQ (S6)
    tft.drawRect(cx - step - 20 - 10, cy - 15, 40, 30, COLOR_FRAME);
    tft.drawString("4", cx - step - 10, cy);
    tft.drawString("<", cx - step - 40, cy);

    // DIR (S8)
    tft.drawRect(cx + step - 20 + 10, cy - 15, 40, 30, COLOR_FRAME);
    tft.drawString("6", cx + step + 10, cy);
    tft.drawString(">", cx + step + 40, cy);

    // ENTER (S7) - Centro
    tft.setTextColor(COLOR_ORANGE, COLOR_BG);
    tft.drawRect(cx - 25, cy - 15, 50, 30, COLOR_ACCENT);
    tft.drawString("5", cx, cy);
    tft.drawString("OK", cx, cy + 25);

    // Rodapé
    tft.setTextFont(1);
    tft.setTextColor(COLOR_TEXT, COLOR_BG);
    tft.drawString("0 : Info   <-: Numeros", 120, 210);

  } else if (remotePage == 2) {
    // --- PÁGINA 2: NUMÉRICO ---
    
    tft.setTextDatum(MC_DATUM);
    tft.setTextFont(2);
    tft.setTextColor(COLOR_GREEN, COLOR_BG);
    tft.drawString("Teclado Numerico", 120, 50);

    tft.setTextFont(1);
    tft.setTextColor(COLOR_TEXT, COLOR_BG);
    
    // Layout Grid
    // 1(S1) 2(S2) 3(S3)
    // 4(S5) 5(S6) 6(S7)
    // 7(S9) 8(S10) 9(S11)
    // Bk(S8) 0(S12) Ent(S4)
    
    int yBase = 80;
    int yStep = 25;
    
    tft.drawString("1=1  2=2  3=3", 120, yBase);
    tft.drawString("4=4  5=5  6=6", 120, yBase + yStep);
    tft.drawString("7=7  8=8  9=9", 120, yBase + yStep*2);
    
    tft.setTextColor(COLOR_ORANGE, COLOR_BG);
    tft.drawString("x=0", 120, yBase + yStep*3);
    
    tft.setTextColor(COLOR_ACCENT, COLOR_BG);
    tft.drawString("+=ENTER  -=BACK", 120, yBase + yStep*4 + 5);

    // Rodapé
    tft.setTextColor(COLOR_TEXT, COLOR_BG);
    tft.drawString("0 : Setas   <-: Info", 120, 215);
  }
}

// Funções de controle de página
void nextRemotePage() {
  remotePage++;
  if (remotePage > 2) remotePage = 0;
  renderRemoteScreen(false); // Redesenha conteúdo
}

void prevRemotePage() {
  remotePage--;
  if (remotePage < 0) remotePage = 2;
  renderRemoteScreen(false); // Redesenha conteúdo
}

// Getter para o buttons.h saber qual página está ativa
int getRemotePage() {
  return remotePage;
}

#endif // SCREEN_REMOTE_H
