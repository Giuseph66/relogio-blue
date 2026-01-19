// CalcMinimal3ButtonsRoundBright.h
// ESP32 + GC9A01 (240x240) + TFT_eSPI
// Uma única linha de 3 botões, dentro da área circular, com cores vivas e texto ASCII + sombra

#ifndef CALC_MINIMAL_3BUTTONS_ROUND_BRIGHT_H
#define CALC_MINIMAL_3BUTTONS_ROUND_BRIGHT_H

#include <TFT_eSPI.h>
#include <math.h>

// Nota: RGB() já está definido em config.h

// Paleta moderna
static const uint16_t COL_BG     = RGB(8,12,20);
static const uint16_t COL_FRAME  = RGB(60,70,85);
static const uint16_t COL_PANEL  = RGB(25,30,40);
static const uint16_t COL_TEXT   = RGB(255,255,255);
static const uint16_t COL_SHADOW = RGB(0,0,0);
static const uint16_t COL_ACCENT = RGB(0,150,255);

// Cores dos botões (mais modernas)
static const uint16_t COL_BTN0 = RGB(255,100,50);   // laranja moderno
static const uint16_t COL_BTN1 = RGB(50,200,100);   // verde moderno
static const uint16_t COL_BTN2 = RGB(100,150,255);  // azul moderno

// ---------- Estado ----------
struct Calc3RoundBrightState {
  String currentExpr = "";   // expressão atual
  String currentResult = "0"; // resultado atual
  
  // Histórico de operações (como na imagem)
  String history[6] = {"", "", "", "", "", ""};  // últimas 6 operações
  int historyCount = 0;
  
  // Botões
  const char* b0 = "CLEAR";
  const char* b1 = "=";
  const char* b2 = "HIST";
  int highlight = -1;   // 0..2, -1 nenhum

  // Cores dos botões
  uint16_t c0 = COL_BTN0;
  uint16_t c1 = COL_BTN1;
  uint16_t c2 = COL_BTN2;
};

// ---------- Helpers ----------
static String sanitizeASCII(const String& in){
  // Converte alguns símbolos Unicode comuns para ASCII, pois font 1 não renderiza Unicode
  String s; s.reserve(in.length());
  for (uint16_t i=0;i<in.length();++i){
    char c = in[i];
    // substituições simples
    if ((uint8_t)c == 0xC3 && i+1<in.length()){ // possíveis bytes UTF-8 (sinais)
      // vamos mapear alguns padrões usados
      unsigned char c2 = (unsigned char)in[i+1];
      // exemplos: × (C3 97?), − etc... mas melhor mapear por codepoint prático:
    }
    // mapeia manualmente por comparação
    if (c=='\xC3'){ // pode ser começo de UTF-8, tenta sequências conhecidas
      // olhamos próxima posição só para descartar; deixamos vazio
      continue;
    }
    // fallback rápido: troca caracteres problemáticos por equivalentes
    if ((unsigned char)c > 126){
      // alguns mapeamentos diretos que costumam aparecer:
      // '×' -> 'x', '÷' -> '/', '−' -> '-', '•' -> '*'
      // como não temos o codepoint, mapeamos por conteúdo do label antes de passar aqui (veja uso abaixo).
      continue;
    }
    s += c;
  }
  // Substituições textuais frequentes se vierem na string original:
  String out = in;
  out.replace("×","x");
  out.replace("÷","/");
  out.replace("−","-");
  out.replace("•","*");
  out.replace("–","-");   // en dash
  out.replace("—","-");   // em dash
  out.replace("×","x");   // reforço
  // remove possíveis remanescentes não ASCII
  String ascii; ascii.reserve(out.length());
  for (uint16_t i=0;i<out.length();++i){
    char ch = out[i];
    if ((unsigned char)ch >= 32 && (unsigned char)ch <= 126) ascii += ch;
  }
  return ascii.length()? ascii : String("?");
}

static void drawTextWithShadow(TFT_eSPI &tft, const String& txt, int cx, int cy, uint16_t fg, uint16_t bg){
  tft.setTextDatum(MC_DATUM);
  tft.setTextFont(2);     // Fonte 2 (mais legível)
  // sombra suave
  tft.setTextColor(COL_SHADOW, bg);
  tft.drawString(txt, cx+1, cy+1);
  // texto principal
  tft.setTextColor(fg, bg);
  tft.drawString(txt, cx, cy);
}

// Declarações das funções
static void drawCalculatorView(TFT_eSPI &tft, const Calc3RoundBrightState &s);
static void drawHistoryView(TFT_eSPI &tft, const Calc3RoundBrightState &s);

static void drawTopDisplay(TFT_eSPI &tft, const Calc3RoundBrightState &s,
                           int x,int y,int w,int h){
  int r = 15; // Raio menor para display flutuante
  // Fundo com gradiente sutil
  tft.fillRoundRect(x,y,w,h,r,COL_PANEL);
  tft.drawRoundRect(x,y,w,h,r,COL_FRAME);

  // Linha decorativa no topo
  tft.drawLine(x+8, y+2, x+w-8, y+2, COL_ACCENT);

  // resultado (grande, centralizado) com sombra - foco principal do display flutuante
  String res = sanitizeASCII(s.currentResult.length()? s.currentResult : "0");
  tft.setTextDatum(MC_DATUM);
  tft.setTextFont(4);
  if (res.length() > 6) tft.setTextFont(2); // Ajuste para display menor
  drawTextWithShadow(tft, res, x+w/2, y+h/2+2, COL_TEXT, COL_PANEL);
}

static int chordWidthAtY(int cx,int cy,int R,int y){
  float dy = (float)y - (float)cy;
  float inside = (float)R*(float)R - dy*dy;
  if (inside <= 0) return 0;
  return (int)floorf(2.0f * sqrtf(inside));
}

static void drawRoundedButton(TFT_eSPI &tft, int x,int y,int w,int h,
                              const String& label, uint16_t fill, bool highlight){
  int r = 18;
  uint16_t bg = fill;
  uint16_t border = COL_FRAME;
  
  if (highlight){
    // Efeito de brilho mais sutil
    uint8_t R = min(255, (int)( (fill>>8)&0xF8 ) + 20);
    uint8_t G = min(255, (int)( (fill>>3)&0xFC ) + 20);
    uint8_t B = min(255, (int)( (fill<<3)&0xF8 ) + 20);
    bg = RGB(R,G,B);
    border = COL_ACCENT;
  }

  // Sombra do botão
  tft.fillRoundRect(x+2, y+2, w, h, r, RGB(0,0,0));
  // Botão principal
  tft.fillRoundRect(x,y,w,h,r,bg);
  tft.drawRoundRect(x,y,w,h,r,border);
  
  // Linha decorativa no topo do botão
  tft.drawLine(x+4, y+2, x+w-4, y+2, RGB(255,255,255));

  String safe = sanitizeASCII(label);
  drawTextWithShadow(tft, safe, x + w/2, y + h/2, COL_TEXT, bg);
}

// ---------- Função principal ----------
static void drawCalculator3ButtonsRoundBright(TFT_eSPI &tft, const Calc3RoundBrightState &s, bool clearScreen = true){
  const int CX=120, CY=120;
  const int R=110;

  if (clearScreen) {
    tft.fillScreen(COL_BG);
    tft.drawCircle(CX, CY, R, COL_FRAME);
  }

  // Sempre mostra a calculadora normal
  drawCalculatorView(tft, s);
}

static void drawCalculatorView(TFT_eSPI &tft, const Calc3RoundBrightState &s){
  const int CX=120, CY=120;

  // Display superior flutuante (resultado)
  int displayW = 160;
  int displayH = 40;
  int displayX = CX - displayW/2;
  int displayY = CY - 90; // Posição elevada (flutuante acima)

  drawTopDisplay(tft, s, displayX, displayY, displayW, displayH);

  // Área do histórico (expandida para ocupar o espaço dos botões removidos)
  int histW = 180;
  int histH = 120; // Altura aumentada para ocupar espaço dos botões
  int histX = CX - histW/2;
  int histY = CY - 20; // Ajustado para ocupar mais espaço vertical

  // Fundo do histórico
  tft.fillRoundRect(histX, histY, histW, histH, 8, COL_PANEL);
  tft.drawRoundRect(histX, histY, histW, histH, 8, COL_FRAME);

  // Linhas separadoras (5 linhas novamente)
  for (int i = 1; i < 5; i++) {
    int lineY = histY + 18 + i * 18; // Mais espaço entre linhas
    tft.drawLine(histX + 10, lineY, histX + histW - 10, lineY, RGB(80,80,90));
  }

  // Expressão atual sendo digitada (no topo do histórico) - suporta múltiplas linhas
  if (s.currentExpr.length() > 0) {
    tft.setTextDatum(TL_DATUM);
    tft.setTextFont(2);
    tft.setTextColor(COL_ACCENT, COL_PANEL);

    // Divide a expressão em linhas e exibe cada uma
    int lineY = histY + 8;
    int lastPos = 0;
    int newlinePos = s.currentExpr.indexOf('\n', lastPos);

    while (newlinePos != -1) {
      String line = s.currentExpr.substring(lastPos, newlinePos);
      tft.drawString(line, histX + 15, lineY);
      lineY += 16; // Próxima linha
      lastPos = newlinePos + 1;
      newlinePos = s.currentExpr.indexOf('\n', lastPos);
    }

    // Última linha (ou linha única se não há quebras)
    String lastLine = s.currentExpr.substring(lastPos);
    tft.drawString(lastLine, histX + 15, lineY);
  }

  // Mostra o histórico (últimas 4 operações, uma linha a menos para a expressão atual)
  for (int i = 0; i < 4; i++) {
    int idx = (s.historyCount - 1 - i + 6) % 6;
    if (s.history[idx].length() > 0) {
      tft.setTextDatum(TL_DATUM);
      tft.setTextFont(2);
      tft.setTextColor(COL_TEXT, COL_PANEL);
      tft.drawString(s.history[idx], histX + 15, histY + 8 + (i + 1) * 18);
    }
  }

  // Botões removidos conforme solicitado
}

static void drawHistoryView(TFT_eSPI &tft, const Calc3RoundBrightState &s){
  const int CX=120, CY=120;
  
  // Título
  tft.setTextDatum(MC_DATUM);
  tft.setTextFont(2);
  tft.setTextColor(COL_ACCENT, COL_BG);
  tft.drawString("HISTORICO", CX, CY - 80);
  
  // Lista do histórico
  int startY = CY - 50;
  int lineH = 20;
  
  for (int i = 0; i < 5; i++) {
    int idx = (s.historyCount - 1 - i + 5) % 5;
    if (s.history[idx].length() > 0) {
      tft.setTextDatum(TL_DATUM);
      tft.setTextFont(2);
      tft.setTextColor(COL_TEXT, COL_BG);
      tft.drawString(s.history[idx], 20, startY + i * lineH);
    }
  }
  
  // Botão voltar
  int btnW = 80;
  int btnH = 30;
  int btnX = CX - btnW/2;
  int btnY = CY + 60;
  
  tft.fillRoundRect(btnX, btnY, btnW, btnH, 6, COL_BTN1);
  tft.drawRoundRect(btnX, btnY, btnW, btnH, 6, COL_FRAME);
  
  tft.setTextDatum(MC_DATUM);
  tft.setTextFont(2);
  tft.setTextColor(COL_TEXT, COL_BTN1);
  tft.drawString("VOLTAR", CX, btnY + btnH/2);
}

// Função auxiliar para adicionar ao histórico
static void addToHistory(Calc3RoundBrightState &s, const String &entry) {
  // Move histórico para frente
  for (int i = 5; i > 0; i--) {
    s.history[i] = s.history[i-1];
  }
  s.history[0] = entry;
  s.historyCount = min(6, s.historyCount + 1);
}

// Redesenha a calculadora
static void redrawCalc3DisplayRoundBright(TFT_eSPI &tft, const Calc3RoundBrightState &s){
  drawCalculatorView(tft, s);
}

// ========== DECLARAÇÕES DE FUNÇÕES ==========

void processCalculatorInput(int buttonIndex, bool longPress);
void processNumber(char digit);
void processOperator(char op);
void evaluateExpression();
void clearCalculator();
void backspace();
void addToHistory(const String& entry);
double evaluateMathExpression(const String& expr);

// ========== FUNÇÕES PÚBLICAS ==========

// Estado global da calculadora
Calc3RoundBrightState calculatorState;

// Retorna referência ao estado da calculadora
Calc3RoundBrightState& getCalculatorState() {
  return calculatorState;
}

// Processa entrada da calculadora baseada no índice do botão
void processCalculatorInput(int buttonIndex, bool longPress) {
  if (buttonIndex < 0 || buttonIndex > 15) return;

  // Mapa de botões para números e operadores
  const char* numberMap[16] = {
     "1", "2", "3",nullptr,  "4", "5", "6",nullptr,
     "7", "8", "9",nullptr, nullptr,"0", nullptr,nullptr
  };

  const char* operatorMap[16] = {
     nullptr, nullptr, nullptr,"+",  nullptr, nullptr, nullptr,"-",
     nullptr, nullptr, nullptr,"*", nullptr, nullptr, nullptr, nullptr
  };

  // Tratamento especial para S14 - backspace (sempre)
  if (buttonIndex == 14) { // S15
    backspace();
    return;
  }

  // Clique longo em operadores
  if (longPress) {
    if (buttonIndex == 3 || buttonIndex == 7) { // S4 (+) ou S8 (-) com clique longo
      clearCalculator();
    } else if (buttonIndex == 11) { // S12 (*) com clique longo faz /
      processOperator('/');
    }
    return; 
  }

  // Processa números
  if (numberMap[buttonIndex]) {
    processNumber(numberMap[buttonIndex][0]);
  }
  // Processa operadores
  else if (operatorMap[buttonIndex]) {
    processOperator(operatorMap[buttonIndex][0]);
  }
}

// Adiciona dígito à expressão atual
void processNumber(char digit) {
  // Verifica se a última linha atingiu o limite (~10 caracteres)
  int lastLineStart = calculatorState.currentExpr.lastIndexOf('\n');
  if (lastLineStart == -1) lastLineStart = 0; // Se não há quebra de linha, começa do início
  else lastLineStart++; // Pula o \n

  String lastLine = calculatorState.currentExpr.substring(lastLineStart);
  if (lastLine.length() >= 19) { // Limite por linha
    calculatorState.currentExpr += '\n'; // Quebra de linha
  }

  calculatorState.currentExpr += digit;
  evaluateExpression();
}

// Adiciona operador à expressão
void processOperator(char op) {
  if (calculatorState.currentExpr.length() == 0) return; // Não permite operador no início

  // Verifica se último caractere da última linha já é operador (substitui)
  char last = calculatorState.currentExpr.charAt(calculatorState.currentExpr.length() - 1);

  // Se último caractere é quebra de linha, adiciona o operador na nova linha
  if (last == '\n') {
    calculatorState.currentExpr += op;
  }
  // Se já é operador, substitui
  else if (last == '+' || last == '-' || last == '*' || last == '/') {
    calculatorState.currentExpr.setCharAt(calculatorState.currentExpr.length() - 1, op);
  }
  // Caso normal: adiciona operador
  else {
    calculatorState.currentExpr += op;
  }
  evaluateExpression();
}

// Avalia a expressão matemática atual
void evaluateExpression() {
  if (calculatorState.currentExpr.length() == 0) {
    calculatorState.currentResult = "0";
    return;
  }

  // Para expressões com múltiplas linhas, avalia apenas a última linha
  String exprToEvaluate = calculatorState.currentExpr;
  int lastNewline = calculatorState.currentExpr.lastIndexOf('\n');
  if (lastNewline != -1) {
    exprToEvaluate = calculatorState.currentExpr.substring(lastNewline + 1);
  }

  // Remove espaços em branco da expressão a ser avaliada
  exprToEvaluate.trim();

  if (exprToEvaluate.length() == 0) {
    calculatorState.currentResult = "0";
    return;
  }

  // Só calcula se a expressão termina com um dígito (não com operador)
  char lastChar = exprToEvaluate.charAt(exprToEvaluate.length() - 1);
  if (lastChar == '+' || lastChar == '-' || lastChar == '*' || lastChar == '/') {
    calculatorState.currentResult = "..."; // Indica que está aguardando mais entrada
    return;
  }

  double result = evaluateMathExpression(exprToEvaluate);
  if (isnan(result) || isinf(result)) {
    calculatorState.currentResult = "ERRO";
  } else {
    // Formata resultado (remove .0 se for inteiro)
    calculatorState.currentResult = String(result);
    if (calculatorState.currentResult.indexOf('.') != -1) {
      // Remove zeros à direita e ponto se necessário
      while (calculatorState.currentResult.endsWith("0")) {
        calculatorState.currentResult.remove(calculatorState.currentResult.length() - 1);
      }
      if (calculatorState.currentResult.endsWith(".")) {
        calculatorState.currentResult.remove(calculatorState.currentResult.length() - 1);
      }
    }
  }
}

// Limpa expressão e resultado
void clearCalculator() {
  calculatorState.currentExpr = "";
  calculatorState.currentResult = "0";
}

// Remove último caractere da expressão (backspace)
void backspace() {
  if (calculatorState.currentExpr.length() > 0) {
    // Remove o último caractere
    calculatorState.currentExpr.remove(calculatorState.currentExpr.length() - 1);

    // Se o último caractere removido era uma quebra de linha, remove também
    // (para evitar linhas vazias no final)
    if (calculatorState.currentExpr.endsWith("\n")) {
      calculatorState.currentExpr.remove(calculatorState.currentExpr.length() - 1);
    }

    evaluateExpression();
  }
}

// Adiciona entrada ao histórico
void addToHistory(const String& entry) {
  // Move histórico para frente
  for (int i = 5; i > 0; i--) {
    calculatorState.history[i] = calculatorState.history[i-1];
  }
  calculatorState.history[0] = entry;
  calculatorState.historyCount = min(6, calculatorState.historyCount + 1);
}

// Avalia expressão matemática simples (suporta +, -, *, / com precedência)
double evaluateMathExpression(const String& expr) {
  String expression = expr;
  expression.trim();

  // Parser simples para expressões com precedência
  // Primeiro processa * e /, depois + e -

  // Arrays para armazenar números e operadores
  double numbers[10];
  char operators[9];
  int numCount = 0;
  int opCount = 0;

  // Parsing básico
  String currentNumber = "";
  for (unsigned int i = 0; i < expression.length(); i++) {
    char c = expression.charAt(i);

    if (c >= '0' && c <= '9') {
      currentNumber += c;
    } else {
      // Adiciona número se houver
      if (currentNumber.length() > 0) {
        numbers[numCount++] = currentNumber.toDouble();
        currentNumber = "";
      }

      // Adiciona operador
      if (c == '+' || c == '-' || c == '*' || c == '/') {
        if (opCount < 9) {
          operators[opCount++] = c;
        }
      }
    }
  }

  // Último número
  if (currentNumber.length() > 0) {
    numbers[numCount++] = currentNumber.toDouble();
  }

  if (numCount == 0) return 0;

  // Avaliação com precedência: primeiro * e /
  double result = numbers[0];
  for (int i = 0; i < opCount; i++) {
    char op = operators[i];
    double nextNum = numbers[i + 1];

    if (op == '*') {
      result *= nextNum;
    } else if (op == '/') {
      if (nextNum == 0) return NAN; // Divisão por zero
      result /= nextNum;
    } else if (op == '+') {
      result += nextNum;
    } else if (op == '-') {
      result -= nextNum;
    }
  }

  return result;
}

#endif // CALC_MINIMAL_3BUTTONS_ROUND_BRIGHT_H
