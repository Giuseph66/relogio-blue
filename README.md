# Relógio Bluetooth (Relogio-Blutu)

Este projeto consiste em um sistema completo de smartwatch DIY utilizando um ESP32 com display redondo (GC9A01) e um aplicativo móvel em Flutter para comunicação via Bluetooth Low Energy (BLE).

## 🖥️ Componentes do Projeto

1.  **Firmware (ESP32)**: Código em C++ para Arduino que gerencia o display, conexão BLE e interface do relógio.
2.  **App Mobile (Flutter)**: Aplicativo Android/iOS para enviar notificações e interagir com o relógio.

---

## 🛠️ Hardware Necessário

*   **Microcontrolador**: ESP32 (DevKit V1 ou similar)
*   **Display**: LCD Redondo 1.28" GC9A01 (240x240 px)
*   **Cabos**: Jumpers para conexão

### 🔌 Esquema de Ligação (Pinagem)

| Display GC9A01 | ESP32 | Descrição |
| :--- | :--- | :--- |
| **VCC** | 3V3 | Alimentação |
| **GND** | GND | Terra |
| **SCL/CLK** | GPIO 18 | Clock SPI |
| **SDA/MOSI** | GPIO 23 | Dados SPI |
| **RES/RST** | GPIO 4 | Reset |
| **DC** | GPIO 19 | Data/Command |
| **CS** | GPIO 5 | Chip Select |
| **BLK/BL** | GPIO 15 | Backlight (Opcional) |

---

## 🤖 Parte 1: Firmware (Arduino/ESP32)

### Pré-requisitos
*   [Arduino IDE](https://www.arduino.cc/en/software) instalado.
*   Suporte a placas ESP32 instalado na IDE (Boards Manager).

### Instalação das Bibliotecas
No Arduino IDE, vá em **Sketch > Include Library > Manage Libraries** e instale:
1.  **TFT_eSPI** (por Bodmer) - Para controlar o display.
2.  **NimBLE-Arduino** (por h2zero) - Para comunicação BLE eficiente (se estiver usando, caso contrário o padrão BLEDevice do ESP32 serve, mas este projeto parece usar a stack padrão modificada ou bibliotecas específicas, verifique os imports).

*Nota: Este projeto usa a livraria nativa BLE do ESP32.*

### Configuração do Display (Importante!)
Para que o display GC9A01 funcione corretamente com a biblioteca `TFT_eSPI`, você precisa editar o arquivo de configuração da biblioteca ou garantir que os defines no código estão sendo usados.

Neste projeto, as configurações já estão definidas em `User_Setup.h` no diretório do firmware, mas a biblioteca `TFT_eSPI` geralmente requer que você edite o arquivo `User_Setup.h` **dentro da pasta da biblioteca** em `Documents/Arduino/libraries/TFT_eSPI/User_Setup.h`.

Recomendamos substituir o conteúdo do arquivo de setup da biblioteca pelo conteúdo que está em `esp32_rom_ble/User_Setup.h` deste repositório, ou garantir que o driver `GC9A01_DRIVER` esteja descomentado e os pinos coincidam.

### Como Carregar o Código
1.  Abra o arquivo `esp32_rom_ble/esp32_rom_ble.ino` na Arduino IDE.
2.  Selecione sua placa ESP32 em **Tools > Board**.
3.  Selecione a porta COM correta.
4.  Clique em **Upload** (Seta para direita).
5.  Após carregar, o display deve ligar e mostrar a interface "RELOGIO".

---

## 📱 Parte 2: Aplicativo Mobile (Flutter)

### Pré-requisitos
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) instalado e configurado.
*   Android Studio ou VS Code configurados com plugins Flutter/Dart.
*   Dispositivo físico Android (Emuladores não suportam Bluetooth).

### Instalação e Execução

1.  **Clone o repositório:**
    ```bash
    git clone https://github.com/Giuseph66/relogio-blue.git
    cd relogio-blue
    ```

2.  **Instale as dependências:**
    ```bash
    flutter pub get
    ```

3.  **Permissões (Android):**
    O projeto já deve ter as permissões necessárias configuradas em `android/app/src/main/AndroidManifest.xml` (Bluetooth, Location, etc). Certifique-se de que o **Localização** e **Bluetooth** estejam ativados no seu celular.

4.  **Rodar o App:**
    Conecte seu celular via USB (modo depuração ativado) e execute:
    ```bash
    flutter run
    ```

### Como Usar
1.  Abra o app no celular.
2.  Na tela inicial, procure por dispositivos BLE.
3.  O ESP32 deve aparecer (geralmente como "ESP32" ou o nome definido no código).
4.  Toque para conectar.
5.  Uma vez conectado, o ícone de status no relógio ficará verde ("OK").
6.  Use as abas do app para enviar mensagens ou comandos para o relógio.

---

## 🐛 Solução de Problemas Comuns

*   **Display Branco/Preto:** Verifique se os pinos SPI (18 e 23) não estão invertidos e se a configuração `User_Setup.h` da biblioteca `TFT_eSPI` está correta para o driver GC9A01.
*   **Não encontra Bluetooth:** Verifique se o app tem permissão de "Dispositivos Próximos" e "Localização" no Android.
