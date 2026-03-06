# Fase 3: Telas de Busca e Mensagens

## Objetivo
Atacar os dois pontos mais técnicos do projeto visualmente: A experiência de pareamento (Connect) e o acompanhamento de mensagens (Logs/Comandos), transformando-as em telas amigáveis.

## Passos Detalhados

### 1. Refatorar a Busca de Dispositivo (`ConnectDevicePage`)
A tela antiga lista secamente os itens. A nova será mais viva e responsiva.
*   **Ação:** Criar a nova versão de `ConnectDevicePage` (ex: `features/ble/presentation/pages/connect_device_page.dart`).
*   **Visual Proposto:**
    *   Um radar ou animação central girando levemente ao procurar (indica "Escaneando").
    *   Resultados (_devices_) dispostos em _Tiles_ limpas com os ícones de sinal adequados à distância estimada (com base no RSSI). Se `RSSI > -60`, sinal Forte (cor Verde intensa); se `< -85`, sinal Fraco (Laranja/Amarelo).
    *   Destacar visualmente qual é o "Dispositivo Preferido" salvo.
    *   Barra de pesquisa no topo com cantos arredondados, levemente transparente.

### 2. Refatorar o Console de Mensagens (`MessagesPage`)
O painel de comunicação atual serve bem, mas pode ficar ainda melhor para leitura de comandos, semelhante a um chat ou terminal limpo.
*   **Ação:** Construir a nova interface para `MessagesPage` ou renomear para algo como `ConsolePage`/`ChatPage`.
*   **Visual Proposto:**
    *   Substituir a lista corrida com cores chapadas por "Bolhas de Mensagem" tipo Chat (se preferir um estilo conversacional) ou manter listagem técnica (Terminal) usando uma fonte Monospace clara.
    *   Isolar visualmente a linha superior de _"Tick Status"_ e do status Online/Offline. Exibi-las como uma barra de *Badge* flutuante acima da lista ou integrada à AppBar.
    *   A região dos botões rápidos (PING, STATUS, etc) pode ser agrupada em um painel responsivo colapsável (ou num carrossel horizontal de *Chips* acima do input de texto) para salvar espaço em telas menores.
