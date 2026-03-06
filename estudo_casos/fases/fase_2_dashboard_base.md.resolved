# Fase 2: Nova Tela Base e Dashboard Moderno

## Objetivo
Criar a fundação da nova interface focada em usabilidade limpa, substituindo o conceito antigo de "Menu Lateral para tudo" por uma barra de navegação principal (Bottom Navigation Bar) e apresentar um novo Dashboard.

## Passos Detalhados

### 1. Criar a Navegação Principal (Main Layout)
A interface moderna pede acesso rápido às abas mais essenciais via barra inferior. O Drawer pode ser deixado para "Demos" ou configurações profundas, mas não como navegador principal do app.
*   **Ação:** Criar uma nova tela `MainScreen` (em `features/dashboard/presentation/pages/main_page.dart` ou similar).
*   **Estrutura Visual:**
    *   Um `Scaffold` com `body` condicional (baseado na aba selecionada).
    *   Um `BottomNavigationBar` com: [Home/Dashboard, Dispositivos, Logs/Mensagens, Configurações].

### 2. Desenhar a Nova `DashboardPage` (Clean UI)
A Dashboard deve informar ao usuário sobre o status do hardware em um piscar de olhos, usando o mínimo de "Poluição Visual".
*   **Ação:** Criar `DashboardPage` focado apenas na visualização (os dados já são providenciados pelos métodos e `BleController` legados).
*   **Estrutura Visual:**
    *   Cabeçalho minimalista.
    *   **Cards de Status:** Blocos com bordas arredondadas e cores calmas (Muted Colors) para exibir: Status do BLE (Online/Offline), Serviço em Background funcionando ou não.
    *   Informação em Destaque: Nome do dispositivo conectado (se houver). Se não houver, mostrar um botão proeminente "Procurar Dispositivo" que leva à aba de Dispositivos.

### 3. Integração com Controladores
*   A nova `DashboardPage` irá instanciar ou "receber injeção" do `BleController` antigo.
*   **Ação:** O novo design usará os `Streams` (como `.connectionState`, `.bluetoothEnabled`) existentes do projeto para atualizar os Cards sem re-escrever lógica BLE.
