# Brief Para Gemini: Melhorar a Tela do `ble_touch`

Use este texto como instrução para o Gemini trabalhar no visual da interface do projeto `ble_touch` sem quebrar BLE, touch e a calibração opcional.

## Objetivo

Quero deixar a interface da tela ESP32-2432S028R/CYD mais bonita, moderna e organizada, mas sem perder estabilidade do touch e sem alterar a lógica principal do BLE.

## Contexto do projeto

- Projeto: `ble_touch`
- Pasta: `/home/jesus/faculdade/relogio-blutu/ble_touch`
- Hardware: ESP32-2432S028R / CYD
- Display: `320x240`
- Biblioteca gráfica: `TFT_eSPI`
- Touch: `XPT2046_Touchscreen`
- BLE já funcional e deve continuar compatível com o app

## Arquivos principais

- `/home/jesus/faculdade/relogio-blutu/ble_touch/TouchUi.h`
- `/home/jesus/faculdade/relogio-blutu/ble_touch/TouchUi.cpp`
- `/home/jesus/faculdade/relogio-blutu/ble_touch/UiConfig.h`
- `/home/jesus/faculdade/relogio-blutu/ble_touch/User_Setup.h`

## Referência importante

Se houver dúvida sobre touch, calibração opcional, rotação ou mapeamento, seguir o comportamento de:

- `/home/jesus/Progetos/Arduino/ESP/tela_touch/tela_touch.ino`

Ou seja:

- não reinventar a leitura do touch sem necessidade
- não trocar pinagem do touch
- não mudar a lógica básica de `getTouchPoint()`
- não quebrar a calibração opcional salva em `Preferences`

## O que pode melhorar

Melhore somente a interface visual e a organização do layout:

- tela principal de status
- tela de controles
- tela de pergunta BLE
- cabeçalho, botões, cores, espaçamento e tipografia
- barra/indicador de tempo da tela de pergunta
- aparência do canvas e da toolbar

## O que não pode quebrar

- BLE precisa continuar funcionando igual
- comandos `PING`, `LED_ON`, `LED_OFF`, `LED_STATUS` precisam continuar
- pergunta BLE terminada com `?` precisa continuar abrindo a tela de resposta
- respostas `SIM` e `NAO` precisam continuar funcionando
- touch precisa continuar preciso
- a calibração deve continuar opcional, nunca obrigatória no boot
- canvas de teste precisa continuar desenhando
- não pode haver piscadas agressivas na tela de pergunta
- não pode fazer redraw completo desnecessário em loop

## Direção visual desejada

Quero um visual mais bonito e intencional, não com cara de demo simples.

Sugestões:

- estilo mais “painel embarcado premium”
- paleta escura elegante com acentos vivos
- melhor hierarquia visual
- cards e áreas bem separadas
- botões mais legíveis e agradáveis ao toque
- mais equilíbrio entre informação e espaço vazio
- status BLE e LED mais claros visualmente
- tela de pergunta com foco, contraste e leitura imediata

## Restrições técnicas

- evitar animações pesadas
- evitar `fillScreen()` o tempo todo
- preferir redraw parcial quando possível
- manter código claro e organizado
- não adicionar dependências novas
- manter compatibilidade com Arduino IDE

## Sobre SVG

Pode usar SVG como referência visual para desenhar uma interface mais bonita, mas sem renderização SVG em tempo real no ESP32.

Ou seja:

- pode usar SVG como base de design para ícones, shapes e composição
- pode converter SVG para bitmap/C array se isso for realmente necessário
- pode redesenhar em código usando `TFT_eSPI`

Mas:

- não quero biblioteca pesada de SVG rodando na placa
- não quero comprometer desempenho ou memória
- o touch precisa continuar funcionando exatamente nas áreas corretas

Se redesenhar botões ou cards inspirados em SVG:

- mantenha as áreas clicáveis explícitas por coordenadas
- alinhe o visual desenhado com a área real de toque
- não altere a lógica de `getTouchPoint()`
- se mexer na calibração, ela deve continuar opcional

## Tarefa pedida ao Gemini

Analise `TouchUi.cpp` e `TouchUi.h` e refatore a interface para ficar visualmente melhor, sem alterar a lógica central do BLE.

Você pode:

- reorganizar layout
- renomear funções de desenho se fizer sentido
- criar helpers visuais
- melhorar paleta e composição
- redesenhar a tela de pergunta
- melhorar barra de progresso e botões

Mas:

- não mexa na pinagem
- não mude o protocolo BLE
- não complique a leitura do touch

## Entrega esperada

Quero que você:

1. explique a proposta visual em poucas linhas
2. altere os arquivos necessários
3. preserve funcionamento do touch e BLE
4. destaque qualquer risco técnico real

## Observação final

Se precisar escolher entre “mais bonito” e “mais estável”, priorize estabilidade.
