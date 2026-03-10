# BLE Touch

Sketch Arduino para a placa ESP32-2432S028R/CYD, combinando:

- BLE do projeto `esp32_rom_ble`
- display touch/calibracao/canvas do projeto `tela_touch`

## O que faz

- expõe BLE com nome `ESP32`
- usa o serviço `0000ffe0-0000-1000-8000-00805f9b34fb`
- usa a característica `0000ffe1-0000-1000-8000-00805f9b34fb`
- mostra status BLE, último RX/TX e última ação da tela
- permite acionar `PING`, `LED_ON`, `LED_OFF` e `LED_STATUS` pela tela touch
- abre uma tela de pergunta quando chega uma mensagem terminada em `?`
- responde `SIM` ou `NAO` pela própria tela
- aceita perguntas estruturadas por BLE no formato `QST|<id>|<pergunta>|<optId>:<texto>|...`
- mostra de 2 a 4 alternativas pequenas na tela touch
- responde com `QANS|<id>|<optId>` quando o usuário toca uma opção válida
- responde com `QERR|<id>|TIMEOUT` quando a pergunta expira sem resposta
- oferece uma página `CANVAS` local para teste do touch

## Bibliotecas

- `TFT_eSPI`
- `XPT2046_Touchscreen`
- pacote `ESP32` da Espressif

## Arquivos principais

- `ble_touch.ino`: bootstrap do sketch
- `TouchUi.*`: display touch, calibração e navegação
- `BleInteractor.*`: protocolo BLE e comandos locais
- `User_Setup.h`: pinagem da CYD

## Observação

- o sketch sempre inicia com os valores padrão
- não depende de calibração salva para iniciar
- a tela de controle oferece reinicialização rápida da placa
