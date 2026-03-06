# Fase 4: Refinamentos e Tema

## Objetivo
Finalizar a implementação do *case study*, substituindo a última tela de importância (Configurações), definindo o esquema de cores e realizando testes globais de robustez.

## Passos Detalhados

### 1. Atualizar a Tela de Configurações (`SettingsPage`)
A página original possui as permissões e o salvamento do dispositivo preferido de forma agrupada.
*   **Ação:** Criar a nova versão do `SettingsPage` contendo o Switch para "Desligar Modo Moderno" (que aciona a alteração para a interface Legacy).
*   **Visual Proposto:**
    *   Separar em "Sessões": "Aparência", "Bluetooth", "Avançado".
    *   Na sessão "Aparência", adicionar a opção "Usar Interface Antiga (Legacy)". Ao ativar, salva a preferência e reconstrói o app na página Home antiga.
    *   Deixar os botões de requisição de serviço de segundo plano muito mais limpos (Switchs/Toggles no estilo iOS ou Material 3 moderno em vez de botões inteiros).

### 2. Consistência do Tema (Opcional, porém Recomendado)
Assegurar que as _novas_ telas estão usando o `AppTheme` corretamente.
*   **Ação:** Revisar `AppTheme` em `core/theme/`.
*   **Melhoria Visual:** Validar fontes (considerar `GoogleFonts.inter()` ou `poppins()`), paleta de cores (modo Dark premium com cinza profundo em vez de preto `#000000` absoluto). Cor base para os alertas e destaques em Azul Cyan ou Verde Neon, acentuando o apelo de _Smartwatch Dashboard_.

### 3. Testes Finais de Compatibilidade
*   Verificar se todas as dependências da interface nova e antiga importam seu devido Controller sem duplicar estado (Singleton / Injection configurados).
*   Testar exaustivamente a alternância do botão MODO ANTIGO -> MODO NOVO -> MODO ANTIGO em tempo de execução.
