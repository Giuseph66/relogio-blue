# Discrepâncias entre README.md e smartwatch.ino

## ❌ Comandos WebSocket Documentados no README mas NÃO Implementados no Código

### Comandos Faltando:
1. **`status`** - Documentado mas não implementado
2. **`info`** - Documentado mas não implementado  
3. **`audio`** - Documentado mas não implementado
4. **`mpu`** - Documentado mas não implementado
5. **`mensagem|texto`** - Documentado mas não implementado (embora mensagens genéricas funcionem via `addNotification`)
6. **`watchface|1/2/3`** - Documentado mas não implementado
7. **`screen|watchface/sensors/calc/notify/status`** - Documentado mas não implementado
8. **`hr_status`** - Documentado mas não implementado
9. **`hr_start`** - Documentado mas não implementado
10. **`hr_stop`** - Documentado mas não implementado
11. **`sensors`** - Documentado mas não implementado

## ✅ Comandos WebSocket Implementados no Código mas NÃO Documentados no README

### Comandos Faltando na Documentação:
1. **`ping`** - Implementado (responde com "pong")
2. **`rf_send:index`** - Implementado (envia código RF por índice)
3. **`rf_list`** - Implementado (lista códigos RF salvos)
4. **`rf_clear`** - Implementado (limpa lista de códigos RF)
5. **`rf_learn`** - Implementado (entra em modo aprendizado RF)
6. **`rf_status`** - Implementado (status da comunicação RF433)

## ✅ Funcionalidades Implementadas mas NÃO Documentadas

### Módulos:
1. **RF433** - Sistema completo de comunicação RF433/IR implementado:
   - `initRF433()` chamado no `setup()`
   - `updateRF433()` chamado no `loop()`
   - Telas `SCREEN_RF433` e `SCREEN_IR`
   - Comandos WebSocket para controle RF

2. **Tela Controle Remoto (SCREEN_REMOTE)** - Implementada mas documentação incompleta:
   - Existe no código
   - Funcionalidade de navegação entre páginas
   - Envio de comandos via WebSocket

3. **Tela Cubo 3D (SCREEN_CUBE3D)** - Implementada mas não mencionada na seção de telas

4. **Tela IR (SCREEN_IR)** - Implementada mas não mencionada na seção de telas

5. **Tela RF433 (SCREEN_RF433)** - Implementada mas não mencionada na seção de telas

## ⚠️ Informações Parcialmente Incorretas

1. **Limite do QR Code**: 
   - README não menciona limite de 154 caracteres
   - Código implementa verificação e erro se exceder 154 caracteres

2. **Comando `mensagem|texto`**:
   - README documenta formato específico
   - Código trata qualquer mensagem não-reconhecida como notificação (funciona, mas formato diferente)

## 📝 Estrutura de Arquivos

### Arquivos no Código mas NÃO Listados no README:
- `rf433.h` - Módulo completo de RF433/IR
- `screen_rf433.h` - Tela de códigos RF433
- `screen_ir.h` - Tela de códigos IR
- `screen_remote.h` - Tela de controle remoto
- `cubo3d.h` - Tela do cubo 3D

## 🔧 Setup e Loop

### No `setup()`:
- ✅ `initDisplay()` - Documentado
- ✅ `initAudio()` - Documentado
- ✅ `initSensors()` - Documentado
- ✅ `initButtons()` - Documentado
- ✅ `initNetwork()` - Documentado
- ❌ **`initRF433()`** - **NÃO documentado**

### No `loop()`:
- ✅ `updateNetwork()` - Documentado
- ✅ `updateSensors()` - Documentado
- ✅ `updateButtons()` - Documentado
- ✅ `updateAudio()` - Documentado
- ✅ `updateDisplay()` - Documentado
- ❌ **`updateRF433()`** - **NÃO documentado**

## 📋 Resumo

**Total de comandos WebSocket documentados mas não implementados: 11**
**Total de comandos WebSocket implementados mas não documentados: 6**
**Total de módulos/telas implementados mas não documentados: 5**

O README está **parcialmente desatualizado** em relação ao código atual. Recomenda-se atualizar a documentação para refletir:
1. Comandos RF433 implementados
2. Telas adicionais (RF433, IR, Cubo 3D)
3. Remover ou marcar como "planejado" os comandos não implementados
4. Adicionar informações sobre o módulo RF433

