# Estudo de Caso: Refatoração da Arquitetura Visual (App Relógio BLE)

Este documento detalha o planejamento para a refatoração do aplicativo "Relógio BLE", com foco exclusivo na usabilidade (UX) e interface de usuário (UI).

## 🎯 Objetivo Principal
Melhorar a experiência do usuário final através de uma interface limpa, atraente e funcional, mantendo a compatibilidade e acesso à interface antiga (legada) através de um _toggle_ (botão de alternância).

## 🏗️ Estratégia de Arquitetura de UI

A estratégia não é substituir imediatamente o código existente, mas sim criar uma nova camada de apresentação e permitir a coexistência de ambas as interfaces durante o período de transição.

### 1. Renomeação de Componentes Legados
*   **Regra:** Telas e componentes da interface atual deverão ser movidos ou renomeados para conter o sufixo/prefixo `_old` ou estar dentro de um diretório `old/`.
*   **Exemplo:**
    *   `dashboard_page.dart` ➡️ `old/dashboard_page_old.dart` ou `dashboard_page_old.dart`
    *   `AppDrawer` ➡️ `old/app_drawer_old.dart`

### 2. Nova Estrutura de Telas (Clean UI)
A nova interface será focada na experiência de um *Smartwatch Manager*.
*   **Tela de Início (Home/Splash):** Tela de abertura apresentando a logo/ícone do app, verificando o status do Bluetooth silenciosamente.
*   **Dashboard Moderno:**
    *   Foco rápido no status principal (Conectado/Desconectado).
    *   Cards modernos com _Glassmorphism_ ou estilo limpo (Material 3).
    *   Acesso rápido às métricas do relógio e status do serviço de background.
*   **Gestão de Dispositivos (Connect):**
    *   Lista visualmente agradável de dispositivos próximos.
    *   Indicadores claros de RSSI (força do sinal) com ícones dinâmicos.
*   **Navegação Principal:**
    *   Migrar do uso exclusivo de `Drawer` (menu lateral) para uma **Bottom Navigation Bar** moderna para as funções essenciais (Dashboard, Dispositivos, Mapa, Settings).
    *   O Drawer ou um botão na Dashboard servirá para funções secundárias (Demos, Sobre).

### 3. Mecanismo de Alternância (Toggle)
*   Na **nova interface (Configurações)**: Existirá uma opção / botão chamado "Acessar Interface Antiga" ou "Modo Clássico".
*   Na **interface antiga (Configurações_old)**: Existirá um botão correspondente chamado "Voltar para Nova Interface".
*   **Implementação:** Essa escolha será salva localmente (via `SharedPreferences`) para que o aplicativo abra na interface preferida do usuário nativamente no próximo uso.

---

## 📅 Planejamento por Sprints (Divisão de Tasks)

### Sprint 1: Preparação e Toggle
*   **Tarefa 1.1:** Mover os arquivos das telas atuais (`DashboardPage`, `MessagesPage`, `ConnectDevicePage`, `AppDrawer`, `SettingsPage`) para um diretório interno chamado `old` dentro de suas respectivas features. (ex: `lib/features/ble/presentation/pages/old/`). Renomear as Classes para conter `Old`.
*   **Tarefa 1.2:** Criar o gerenciador de estado (Provider ou ValueNotifier simples) para ler/salvar a preferência do usuário (Interface Nova vs Antiga) via `SharedPreferences`.
*   **Tarefa 1.3:** Atualizar o `AppRoutes` para que a Rota `/` (Home) decida qual interface carregar com base nessa preferência.
*   **Tarefa 1.4:** Adicionar o botão "Ir para Nova Interface" na tela `SettingsPageOld`.

### Sprint 2: Nova Tela Base e Dashboard
*   **Tarefa 2.1:** Criar a nova estrutura base de navegação (`MainScreen` com `BottomNavigationBar`).
*   **Tarefa 2.2:** Desenhar a nova tela `DashboardPage` focada em uma visualização "limpa": Cards minimalistas para Status do Bluetooth, Status da Conexão e Bateria (se aplicável).
*   **Tarefa 2.3:** Integrar os controladores existentes (`BleController`) à nova tela garantindo que a funcionalidade técnica não seja quebrada.

### Sprint 3: Telas de Busca e Mensagens
*   **Tarefa 3.1:** Desenhar o novo `ConnectDevicePage`. Melhorar a lista de radar/busca com animações sutis de escaneamento.
*   **Tarefa 3.2:** Desenhar a nova interface do `MessagesPage` (Terminal de comandos / Logs), tornando-o mais legível, semelhante a um chat moderno ou log profissional de desenvolvedor.

### Sprint 4: Refinamentos Finais
*   **Tarefa 4.1:** Desenhar a nova `SettingsPage` contendo o botão "Voltar para Interface Antiga" e as permissões de Background.
*   **Tarefa 4.2:** Revisar consistência de cores, fontes e espaçamentos (Tipografia e Tema).
*   **Tarefa 4.3:** Testes de navegação alternando ativamente entre a UI velha e a UI nova sem fechar o app.
