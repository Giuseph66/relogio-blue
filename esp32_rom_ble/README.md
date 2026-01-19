# ESP32 ROM BLE (Arduino IDE)

Este codigo fica nesta pasta `esp32_rom_ble/` e nao interfere no app Flutter.

## O que ele faz

- Cria um dispositivo BLE com nome `ESP32`.
- Usa o servico `0000ffe0-0000-1000-8000-00805f9b34fb`.
- Usa a caracteristica `0000ffe1-0000-1000-8000-00805f9b34fb` com WRITE/NOTIFY.
- Responde `PING` com `PONG`.
- Responde outras mensagens com `OK: <mensagem>`.
- Envia um "tick" periodico (a cada 2s). Para desativar, ajuste `notifyIntervalMs`.
- Comandos LED: `LED_ON`, `LED_OFF`, `LED_STATUS`.
- Mostra no display TFT o ultimo RX, TX e botao pressionado.
- Envia eventos da matriz de botoes via BLE (`BTN:S1`, `BTN:S1_LONG`).

## Requisitos

- Arduino IDE 2.x (ou 1.8.x)
- Placa ESP32 instalada no Board Manager
- Bibliotecas: `TFT_eSPI`, `Keypad`

## Instalacao da placa ESP32

1. Arduino IDE -> Preferences
2. Em "Additional Boards Manager URLs" adicione:
   `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
3. Tools -> Board -> Boards Manager -> instale "esp32" (Espressif)

## Como compilar e subir

1. Abra `esp32_rom_ble/esp32_rom_ble.ino` no Arduino IDE
2. Selecione a placa (ex: "ESP32 Dev Module")
3. Selecione a porta COM/USB
4. Clique em Upload

## Ajustes de configuracao

Edite `esp32_rom_ble/BleConfig.h`:

- `deviceName`: nome visivel no scan BLE
- `serviceUuid` e `characteristicUuid`: devem bater com o app Flutter
- `notifyIntervalMs`: use `0` para desativar o tick
- `ledPin`: GPIO do LED (padrao `2`)
- `ledActiveHigh`: `true` se HIGH liga o LED

Display e matriz de botoes:

- `esp32_rom_ble/User_Setup.h`: pinos do TFT GC9A01 (240x240) e frequencia SPI
- `esp32_rom_ble/KeypadConfig.cpp`: pinos e nomes da matriz 4x4
  - O `User_Setup.h` local ja e carregado pelo sketch (nao precisa editar a biblioteca).

Pinagem (referencia do seu projeto antigo):

- TFT GC9A01 (SPI): MOSI 23, SCK 18, CS 5, DC 19, RST 4, BL 15
- Matriz 4x4: linhas 27, 14, 12, 13 / colunas 25, 26, 32, 33

## Comandos rapidos

- Do app para o ESP:
  - `LED_ON`, `LED_OFF`, `LED_STATUS`
  - Qualquer mensagem aparece na linha RX do display
- Do ESP para o app:
  - `BTN:S1` (clique curto)
  - `BTN:S1_LONG` (clique longo)

## Dica para o app Flutter

Os UUIDs padrao do app estao em:
`lib/core/ble/ble_constants.dart`

Se voce alterar os UUIDs no ESP32, atualize a tela de configuracoes do app.
