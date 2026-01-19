# ESP32 Smartwatch - Projeto Integrado

## Visão Geral

Este é um **novo projeto modular** que integra as funcionalidades dos projetos existentes:
- Display TFT 240x240 colorido (do projeto `oled_240x240`)
- Sensor de batimentos cardíacos MAX30102 (do projeto `leitor_b_c`)
- Sistema de áudio e streaming (do projeto `relogio`)
- Sensores MPU6050 (acelerômetro/giroscópio)
- Matriz de botões 4x4
- WebSocket para comunicação remota

## Estrutura do Projeto

```
ESP/smartwatch/
├── smartwatch.ino      # Arquivo principal (~90 linhas)
├── config.h            # Configurações centralizadas
├── network.h           # WiFi, WebSocket, NTP, portal
├── audio.h             # Sistema de áudio e streaming
├── sensors.h           # MPU6050 + MAX30102
├── buttons.h           # Matriz de botões e navegação
├── display_tft.h       # Sistema de telas TFT 240x240
├── qr_code.h           # Módulo de QR Code dinâmico
├── WatchFace.h         # Watchfaces (3 versões)
├── calculadora.h       # Calculadora
├── notifyUI.h          # Interface de notificações
├── imageViewer.h       # Visualizador de imagens
├── text_screen.h       # Tela de texto
├── User_Setup.h        # Configuração TFT_eSPI
├── icons.h             # Ícones bitmap
└── keypad_config.h     # Configuração do keypad
```

## Hardware Necessário

- ESP32 DevKit
- Display TFT 240x240 GC9A01 (redondo) - SPI
- Sensor MAX30102 - I2C (endereço 0x57)
- Sensor MPU6050 - I2C (endereço 0x68)
- Matriz de botões 4x4 - Keypad
- Microfone MAX9814 - Analógico (GPIO35)

## Conexões

### Display TFT (SPI)
- MOSI: GPIO23
- MISO: GPIO19
- SCK: GPIO18
- CS: GPIO5
- DC: GPIO19
- RST: GPIO4
- BL: GPIO15 (opcional)

### I2C (MPU6050 + MAX30102)
- SDA: GPIO21
- SCL: GPIO22

### Outros
- Microfone: GPIO35
- LED onboard: GPIO2

### Keypad (Matriz 4x4)
- Linhas: GPIO27, GPIO14, GPIO12, GPIO13
- Colunas: GPIO25, GPIO26, GPIO33, GPIO32

## Bibliotecas Necessárias

Instale via Arduino IDE Library Manager:
- WiFi
- WebSockets
- WebServer
- Preferences
- DNSServer
- TFT_eSPI
- QRcode_eSPI
- Adafruit_MPU6050
- Adafruit_Sensor
- MAX30105
- Keypad

## Configuração

1. Abra o arquivo `User_Setup.h` e ajuste os pinos do TFT conforme sua conexão
2. Compile e envie para o ESP32
3. Na primeira execução, conecte-se à rede WiFi "Smartwatch Config"
4. Acesse http://192.168.10.1 para configurar WiFi e e-mail
5. Após configurar, o dispositivo reiniciará e conectará ao servidor WebSocket

## Funcionalidades

### Watchfaces
- **V1**: Relógio digital com arcos de progresso
- **V2**: Relógio analógico com barras laterais
- **V3**: Relógio analógico com barras curvas laterais (padrão)

### Sensores
- **MPU6050**: Aceleração, giroscópio, temperatura
- **MAX30102**: Batimentos cardíacos (BPM) e SpO2
- Leituras em tempo real exibidas no watchface

### Áudio
- Gravação em buffer (3 segundos)
- Streaming em tempo real via WebSocket
- Taxa de amostragem: 8kHz

### Botões
- S1: Navegação entre telas
- S2: Tela de sensores
- S7: Modo Wi-Fi QR Code (na tela QR Code)
- S8: Modo IP QR Code (na tela QR Code)
- S15: Toggle áudio streaming
- S16: Reiniciar (longo)

### Tela Controle Remoto
- Exibe ID e Segredo para parear com App Desktop
- Botões de navegação (S2, S5, S6, S10) funcionam como setas
- S1 funciona como ENTER
- Botões numéricos enviam teclas 0-9
- Comunicação via WebSocket segura (<ID>|<SEGREDO>|<COMANDO>)

### QR Code
- **Tela dedicada**: Exibe QR Codes dinâmicos
- **Modo configuração**: Quando desconectado, gera QR Code Wi-Fi automaticamente
- **Texto personalizado**: Via comando WebSocket `qrcode|texto`
- **Biblioteca**: QRcode_eSPI para geração otimizada
- **Tamanho**: Otimizado para display 240x240 redondo (180x180px)
- **Interface clara**: Indica modo configuração vs modo personalizado

### Comandos WebSocket

#### Mantidos do projeto original:
- `limpar` - Apaga credenciais e reinicia
- `status` - Exibe tela de status
- `info` - Info detalhada do sistema
- `audio` - Grava e envia áudio
- `stream_on` / `stream_off` - Controle de streaming
- `mpu` - Dados do MPU6050
- `mensagem|texto` - Exibe mensagem

#### Novos comandos:
- `watchface|1/2/3` - Troca watchface
- `screen|watchface/sensors/calc/notify/status` - Muda tela
- `hr_status` - Retorna JSON: `{"bpm":72,"spo2":98,"finger":true}`
- `hr_start` - Ativa sensor MAX30102
- `hr_stop` - Desativa sensor
- `sensors` - Retorna JSON com todos sensores

#### Comando QR Code:
- `qrcode|texto_aqui` - Define texto personalizado para gerar QR Code

##### Como Enviar Texto via WebSocket para QR Code

Para enviar um texto personalizado para o QR Code via WebSocket, use o seguinte formato:

```
qrcode|SEU_TEXTO_AQUI
```

**Exemplos práticos:**

1. **URL/Link:**
   ```
   qrcode|https://neurelix.com.br
   ```

2. **Texto simples:**
   ```
   qrcode|Olá, mundo!
   ```

3. **Configuração Wi-Fi:**
   ```
   qrcode|WIFI:S:MinhaRede;T:WPA;P:minha_senha;;
   ```

4. **PIX ou chave de pagamento:**
   ```
   qrcode|PIX: chave-pix@exemplo.com
   ```

5. **Texto longo (será truncado se > 200 caracteres):**
   ```
   qrcode|Este é um texto muito longo que será automaticamente limitado a 200 caracteres para evitar problemas de memória
   ```

**Comportamento:**
- O comando atualiza imediatamente o texto do QR Code
- Na próxima vez que a tela QR Code for acessada, o novo código será gerado
- **Quando desconectado (modo AP)**: Gera automaticamente QR Code Wi-Fi para configuração
- **Quando conectado**: Exibe mensagem de ajuda se nenhum QR Code personalizado foi definido

##### Comportamento Quando Não Há Wi-Fi Conectado

Quando o ESP32 não está conectado a nenhuma rede Wi-Fi (modo Access Point), a tela QR Code exibe automaticamente:

1. **QR Code Wi-Fi** no formato padrão: `WIFI:S:Smartwatch Config;T:nopass;;`
2. **Texto explicativo** na tela: "MODO CONFIGURACAO - Escaneie para conectar"
3. **Informações adicionais** no QR Code: Rede Wi-Fi e URL de configuração

**Objetivo**: Permitir que o usuário conecte seu smartphone/tablet à rede do ESP32 para acessar a página de configuração Wi-Fi em `http://192.168.10.1`.

**Fluxo típico:**
1. ESP32 inicia em modo AP (sem Wi-Fi salvo)
2. Usuário navega para tela QR Code
3. **Opção 1**: Escaneia QR Code Wi-Fi para conectar automaticamente
4. **Opção 2**: Pressiona **S1** para alternar para QR Code do IP
5. Escaneia o QR Code do IP para abrir diretamente a página de configuração
6. Acessa `http://192.168.10.1` para configurar Wi-Fi

**Controles na tela QR Code:**
- **S7**: Ativa modo Wi-Fi (QR Code para conectar ao Wi-Fi do ESP)
- **S8**: Ativa modo IP (QR Code com endereço IP do ESP)

## Próximos Passos

### Implementações Futuras:
1. **Integração completa MAX30102**: Adicionar leitura não-bloqueante com janela deslizante
2. **Calculadora funcional**: Entrada de expressões via botões
3. **Sistema de notificações**: Receber notificações via WebSocket
4. **HTTP Server**: Receber imagens do servidor Node.js
5. **Bateria**: Leitura do nível de bateria via ADC
6. **Bússola/Magnetômetro**: Adicionar sensor magnético

## Status dos Módulos

- ✅ config.h - Configurações centralizadas
- ✅ network.h - WiFi, WebSocket, NTP (estrutura básica)
- ✅ audio.h - Sistema de áudio básico
- ✅ sensors.h - MPU6050 básico + MAX30102 placeholder
- ✅ buttons.h - Matriz de botões e navegação
- ✅ display_tft.h - Sistema de telas com watchfaces
- ✅ qr_code.h - Módulo de QR Code dinâmico
- ✅ smartwatch.ino - Arquivo principal modular
- ⚠️ handleWebSocketEvent - Precisa implementar comandos completos
- ⚠️ MAX30102 - Precisa implementar leitura não-bloqueante completa

## Arquitetura Modular

```
smartwatch.ino (orquestração)
    ├── config.h (configurações)
    ├── network.h (comunicação)
    ├── audio.h (áudio)
    ├── sensors.h (sensores)
    ├── buttons.h (entrada)
    ├── qr_code.h (QR codes)
    └── display_tft.h (saída)
```

Cada módulo tem responsabilidade única e pode ser desenvolvido/testado independentemente.

## Compilação

```bash
# No diretório do projeto
arduino-cli compile --fqbn esp32:esp32:esp32 smartwatch.ino
```

## Licença

Este projeto utiliza código dos projetos existentes como referência, mantendo-os intactos.

