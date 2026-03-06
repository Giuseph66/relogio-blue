# Fase 1: Preparação e Toggle (Legacy Code)

## Objetivo
Preparar a infraestrutura do projeto para suportar a nova interface visual sem quebrar o código funcional existente, isolando-o e criando o mecanismo que permitirá o usuário (ou desenvolvedor) transitar entre a UI Antiga e a Nova.

## Passos Detalhados

### 1. Renomeação de Arquivos e Classes (Arquitetura Legacy)
Isolar as telas atuais que não têm o padrão de design que desejamos, mas que possuem a mecânica e lógica de negócio funcionando perfeitamente.
*   **Ação:** Mover as telas do pacote `ble`, `dashboard` e demais para sub-pastas `/old` e adicionar o sufixo `_old`.
*   **Exemplos Reais:**
    *   `DashboardPage` ➡️ Mover para `old/dashboard_page_old.dart`. Renomear classe para `DashboardPageOld`.
    *   `MessagesPage` ➡️ Mover para `old/messages_page_old.dart`. Renomear classe para `MessagesPageOld`.
    *   `SettingsPage` ➡️ Mover para `old/settings_page_old.dart`. Renomear classe para `SettingsPageOld`.
    *   `ConnectDevicePage` ➡️ Mover para `old/connect_device_page_old.dart`. Renomear classe para `ConnectDevicePageOld`.
    *   `AppDrawer` ➡️ Mover para uma pasta `widgets/old/app_drawer_old.dart`. Renomear classe para `AppDrawerOld`.

### 2. Gerenciador de Estado do Toggle (UI Mode)
Para que o usuário possa escolher a interface desejada, precisamos salvar e ler esta escolha.
*   **Ação:** Criar um serviço ou utilitário (ex: `UiModeService` ou usar o `AppConfiguration`/`DependencyInjection` atual) que dependa do `SharedPreferences`.
*   **Estrutura do Dado:** Salvar uma chave booleana ou Enum: `use_modern_ui` (Padrão: `true`).
*   **Provedor (Provider/Notifier):** Usar o `ValueNotifier` do Flutter (ou Riverpod/Provider se o projeto usar) para que o `MaterialApp` saiba em tempo real quando o toggle é pressionado, reconstruindo a árvore de *Widgets*.

### 3. Ajuste do AppRoutes (Rotas Dinâmicas)
A rota inicial `/` e as demais devem respeitar o modo de UI selecionado.
*   **Ação:** O `AppRoutes` agora receberá (ou interrogará) o estado do modo UI.
*   **Lógica no `generateRoute`:**
    ```dart
    // Exemplo conceitual:
    if (routeName == dashboard) {
       return MaterialPageRoute(
         builder: (_) => useModernUi ? const DashboardPage() : const DashboardPageOld(),
       );
    }
    ```

### 4. Implementação do Botão na Interface Antiga
*   **Ação:** Na tela `SettingsPageOld`, adicionar um botão grande e claro: "Ir para Nova Interface".
*   Ao ser clicado, este botão deve atualizar o gerenciador de estado (mudando `use_modern_ui` para `true`) e forçar uma navegação para a home `/`.
