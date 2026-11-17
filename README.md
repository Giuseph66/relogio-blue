# Relógio Bluetooth (Relogio-Blutu)

Este projeto consiste em um sistema completo de smartwatch DIY utilizando um ESP32 com display redondo (GC9A01) e um aplicativo móvel em Flutter para comunicação via Bluetooth Low Energy (BLE).

## 🖥️ Componentes do Projeto

1.  **Firmware (ESP32)**: Código em C++ para Arduino que gerencia o display, conexão BLE e interface do relógio.
2.  **Aplicativo Flutter**: app Android e cliente web/PWA para visitas, perguntas e comunicação BLE onde suportado. O projeto iOS nativo ainda precisa de homologação.
3.  **Servidor Node.js**: API Express, banco SQLite, painel administrativo, dashboard público e envio Web Push. Serve também os arquivos da PWA.

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

### 🗺️ Mapa (OpenStreetMap)

O app usa [`flutter_map`](https://pub.dev/packages/flutter_map) em vez do Google Maps — **não precisa de API key, conta Google nem faturamento**. Componente compartilhado em `lib/core/widgets/app_map.dart`.

*   **Tiles:** servidor oficial do OpenStreetMap (`tile.openstreetmap.org`), escurecido no app com `darkModeTileBuilder` para combinar com o tema. Precisa de internet para carregar.
    *   ⚠️ Não usar CARTO (`basemaps.cartocdn.com`): passou a exigir API key e devolve tiles com a marca "API KEY REQUIRED".
*   **Atribuição obrigatória:** o crédito `© OpenStreetMap contributors` deve ficar visível no mapa (licença do OSM). Não remover `AppMap.attribution()`.
*   **Identificação:** `userAgentPackageName` (`com.example.relogio`) identifica o app no servidor de tiles, como exige a política do OSM. Atualizar se o `applicationId` mudar.
*   **Marcadores:**
    *   🔵 ponto ciano: "você está aqui" (substitui o ponto azul do Google);
    *   🟠 alfinete laranja + círculo: locais cadastrados e o raio do geofence;
    *   🟢 alfinete verde: ponto escolhido ao tocar no mapa (modo seleção).

---

## 🐛 Solução de Problemas Comuns

*   **Display Branco/Preto:** Verifique se os pinos SPI (18 e 23) não estão invertidos e se a configuração `User_Setup.h` da biblioteca `TFT_eSPI` está correta para o driver GC9A01.
*   **Não encontra Bluetooth:** Verifique se o app tem permissão de "Dispositivos Próximos" e "Localização" no Android.

## Instalação como PWA

O mesmo projeto mantém o app Android e oferece a versão web em `/app/`.
No navegador, BLE usa Web Bluetooth, histórico/respostas usam IndexedDB e
perguntas podem ser respondidas dentro do aplicativo, mesmo sem relógio.

### Gerar e servir

```bash
python3 scripts/build_pwa.py
cd server
PWA_DIR="$(pwd)/../build/web" npm start
```

Abra `http://localhost:3001/app/` no computador. Para acesso pelo celular,
publique **servidor e PWA no mesmo domínio HTTPS**, com proxy reverso para Node.
`localhost` é uma exceção de desenvolvimento; um IP HTTP na rede local não
habilita Bluetooth nem todos os recursos de localização do navegador.
O painel existente continua em `/` e `/admin`; a PWA fica em `/app/`.

Em produção, copie **todo** `build/web/` para `server/public/app/`, ou defina
`PWA_DIR` para o diretório publicado. Faça a troca dos arquivos de forma atômica.
Não use apenas `flutter build web`: o script também prepara o cache offline
com hashes de todos os recursos, inclusive o renderer local do Flutter.
Arquivos ausentes retornam 404 e respostas da API não entram no cache HTTP da PWA.

Visitantes recebem uma sessão própria, sem acesso administrativo.
O login web usa `ADMIN_EMAIL` e `ADMIN_PASSWORD` do servidor e cookie HttpOnly.
Configure credenciais e `ADMIN_COOKIE_SECRET` próprios no ambiente de produção.
O token compartilhado do APK não é incluído no cliente web.
Para consulta de endereços, o servidor usa `NOMINATIM_BASE_URL`, cache e fila
de até uma requisição por segundo. O mapa continua exigindo internet para tiles.

### No celular

1. Abra `https://SEU-DOMINIO/app/` e faça login ou entre como visitante.
2. Use a sugestão temporária **Instalar**, **Ajustes → Neste dispositivo →
   Instalar no dispositivo**, ou **Adicionar à Tela de Início** no navegador.
3. Em **Ajustes → Neste dispositivo**, habilite **Detectar visitas** e
   **Permitir notificações**. Os locais próximos são atualizados sem abrir o mapa.
   O GPS retoma automaticamente quando a permissão já foi concedida e a opção
   continua habilitada; pausar essa opção é respeitado ao reabrir o aplicativo.
   No iPhone (iOS 16.4+), abra pelo ícone da Tela de Início para permitir avisos.
   Os testes ficam recolhidos em **Verificar notificações**, nessa mesma seção.
4. Em **Dispositivos**, toque em **Selecionar relógio**, escolha o BLE no seletor
   do navegador e depois **Conectar**. Use Chrome no Android para essa função.
5. Ao detectar uma visita, a pergunta aparece na PWA e gera um aviso do sistema
   se a permissão estiver concedida. Não precisa conectar relógio. Toque no aviso
   para abrir a pergunta e responder no celular. Respostas ficam locais
   quando offline e são sincronizadas ao recuperar a conexão ou voltar ao app.
   O aviso também lista as alternativas e inclui botões até o limite permitido
   pelo navegador (normalmente dois no Chrome/Android). Tocar em um botão abre
   a PWA e registra a opção escolhida. Para ver todas as opções ou em navegadores
   sem esses botões, toque no corpo do aviso. Expanda o aviso no Android se os
   botões estiverem recolhidos. Avisos anteriores à atualização devem ser reenviados.
6. Quando houver nova versão pronta, use **Atualizar** no aviso temporário ou
   **Atualizar aplicativo** em Ajustes. Não há barra permanente de controles PWA.

Após o primeiro carregamento online e a instalação do cache, a interface e os
dados já armazenados podem abrir offline. Um login anterior é necessário para
acesso offline; login novo exige servidor. Preserve os dados do site: removê-los
também remove respostas ainda não sincronizadas. Android e navegador têm bases
locais independentes; não existe importação automática dos dados do APK.

### Limites de plataforma

Instalar a PWA não concede serviço nativo de segundo plano. Monitoramento de
visitas e BLE precisam do app visível; o navegador pode interrompê-los ao bloquear
a tela ou fechar/minimizar o app. Ao retornar, o monitoramento ativado retoma.
Safari/iPhone não oferece Web Bluetooth; mapas, catálogo, histórico e respostas
no celular continuam disponíveis. Notificações web são opcionais e não mantêm
GPS/BLE em execução. Web Push enviado por um servidor pode chegar com a PWA
fechada, mas não fornece novas posições GPS nem descobre visitas sozinho.
O Web Push está implementado para avisos enviados pelo painel administrativo, quando as chaves VAPID estiverem configuradas. Ele abre a PWA; não cria uma visita nem uma nova pergunta automaticamente.
O Android nativo conserva seus serviços existentes.

Validação física necessária antes da distribuição: parear o relógio real,
enviar `QST`, receber `QANS`, testar reconexão, visita, perda de internet e
sincronização. Testes de navegador não comprovam compatibilidade de hardware.

## Guia de execução e publicação no servidor do professor

### O que é hospedado

| Parte | Código | Execução / endereço |
| --- | --- | --- |
| Back-end | `server/src`, `server/server.js` | Node.js persistente; API em `/api`, saúde em `/health` |
| Front-end público | `server/public` | Servido pelo próprio Node em `/`; sem build separado |
| Front-end administrativo | `server/src/views`, `server/public/admin` | Login em `/admin/login`, locais em `/admin/config`, respostas e avisos em `/admin/dashboard` |
| Aplicativo web / PWA | `lib`, adaptadores de `web` | Flutter compilado em `build/web`, publicado em `/app/` |
| Aplicativo Android | `lib`, `android` | Instalado no celular; acessa a mesma API por HTTPS |
| Projeto iOS nativo | `lib`, `ios` | Exige macOS/Xcode e adequações nativas; não está homologado para distribuição |
| Firmware do relógio | `esp32_rom_ble` | Carregado no ESP32; não é executado no servidor |

**A versão web e a PWA usam o mesmo build.** A instalação adiciona o ícone e
habilita a experiência de aplicativo; não exige outra aplicação nem outra API.
A implantação recomendada usa um único domínio, por exemplo
`https://geo.exemplo.edu.br`: Nginx termina o HTTPS e encaminha tudo ao Node.
Não publique apenas `build/web` em outro domínio: autenticação por cookie e API
foram preparadas para a mesma origem. Não é necessário Firebase para Web Push.

### Pré-requisitos

- Servidor Linux com acesso administrativo, domínio apontado para seu IP e portas
  80/443 acessíveis. Os exemplos abaixo usam Debian/Ubuntu, Nginx e systemd.
- Node.js **24 LTS** e npm; Git e Python 3. Use uma versão LTS suportada do Node.
  Consulte a [instalação oficial](https://nodejs.org/en/download) e as
  [versões suportadas](https://nodejs.org/en/about/previous-releases).
- Flutter com Dart compatível com `sdk: ^3.10.4` em `pubspec.yaml` para compilar
  a PWA ou o app. O servidor de produção **não precisa do Flutter** se receber o
  build pronto. Android SDK/JDK são necessários apenas para gerar Android;
  macOS/Xcode, para iOS.
- Saída HTTPS do servidor para os serviços de push dos navegadores e para os
  serviços de mapas/geocodificação. Um servidor restrito à rede interna, sem
  acesso a esses serviços, não entrega Web Push externo.

No Linux, instale também as ferramentas de compilação para dependências nativas
como SQLite, caso não exista binário pronto para a plataforma:

```bash
sudo apt update
sudo apt install git python3 build-essential nginx certbot python3-certbot-nginx sqlite3 rsync
node --version
npm --version
flutter --version   # somente na máquina que gera o build
```

### Desenvolvimento local: back-end e front-ends

Na raiz do repositório:

```bash
flutter pub get
python3 scripts/build_pwa.py
cd server
npm ci
cp .env.example .env
```

Edite `server/.env`. Para usar o build local sem copiá-lo, configure `PWA_DIR`
com o **caminho absoluto** para `build/web`. Depois, dentro de `server/`:

```bash
npm start
```

Abra `http://localhost:3001/` para o dashboard público,
`http://localhost:3001/admin/login` para administrar e
`http://localhost:3001/app/` para o aplicativo web. O back-end cria as tabelas
SQLite automaticamente; não há comando separado de migração nem necessidade de
instalar um servidor de banco de dados. `DB_PATH` relativo é resolvido a partir
do diretório em que o processo Node foi iniciado; prefira caminho absoluto.

Para validar login, instalação, offline e Web Push, use o build servido pelo
Node em `/app/`. Depois de alterar o código Flutter, gere novamente o build. O
comando isolado `flutter run -d chrome` serve em outra porta e não encaminha a
API automaticamente; só use esse modo se configurar um proxy de desenvolvimento
que mantenha `/api` na mesma origem. O aplicativo web usa a origem da página
como URL da API.

### Configuração de produção e Web Push

Copie `server/.env.example` para `server/.env` e configure os valores reais.
O arquivo `.env` é carregado automaticamente; variáveis já definidas no processo
prevalecem. `.env.local` só preenche variáveis ainda não definidas, portanto não
sobrescreve valores de `.env`. Use uma variável por linha, sem comentários no
fim da linha. Não envie os arquivos `.env` ao Git.

Gere o par VAPID **uma única vez por instalação**, dentro de `server/`:

```bash
npm run push:keys
```

Copie `publicKey` e `privateKey` para o `.env`. A chave pública é enviada aos
navegadores; a privada permanece no servidor. Não gere outro par a cada deploy:
inscrições existentes dependem dessas chaves. Use um e-mail de contato real em
`VAPID_SUBJECT`, no formato `mailto:professor@exemplo.edu.br`.

Exemplo de configuração — substitua **todos** os valores `SUBSTITUA_...`:

```dotenv
NODE_ENV=production
HOST=127.0.0.1
PORT=3001
DB_PATH=/var/lib/geonexo/app.db
PWA_DIR=/opt/geonexo/pwa-current
ADMIN_EMAIL=professor@exemplo.edu.br
ADMIN_PASSWORD=SUBSTITUA_POR_UMA_SENHA_FORTE
ADMIN_COOKIE_SECRET=SUBSTITUA_POR_UM_SEGREDO_ALEATORIO
ADMIN_SESSION_HOURS=12
APP_AUTH_TOKEN=SUBSTITUA_POR_UM_TOKEN_PARA_O_APP_ANDROID
INTERNAL_AUTH_TOKEN=SUBSTITUA_POR_OUTRO_TOKEN_PARA_TAREFAS
ENABLE_APP_AUTH=true
ALLOW_LEGACY_MESSAGE_POST_WITHOUT_AUTH=false
SEED_SAMPLE_DATA=false
VAPID_PUBLIC_KEY=SUBSTITUA_PELA_PUBLIC_KEY_GERADA
VAPID_PRIVATE_KEY=SUBSTITUA_PELA_PRIVATE_KEY_GERADA
VAPID_SUBJECT=mailto:professor@exemplo.edu.br
```

Para gerar cada segredo aleatório, execute `openssl rand -hex 32`. Os tokens
`APP_AUTH_TOKEN` e `INTERNAL_AUTH_TOKEN` têm finalidades diferentes; não exponha
nenhum deles no front-end web. O token do Android deve corresponder ao valor
passado no build mobile, explicado abaixo. Desabilitar a postagem legada sem
autenticação exige que eventuais clientes antigos também enviem o token.

| Variável | Finalidade |
| --- | --- |
| `HOST`, `PORT` | Interface e porta do processo Node; em produção fica atrás do Nginx |
| `DB_PATH` | Banco persistente: respostas, locais, perguntas, tarefas e inscrições Web Push |
| `PWA_DIR` | Pasta que contém `index.html`, `sw.js` e os demais arquivos compilados |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | Login do painel e login administrativo da PWA |
| `ADMIN_COOKIE_SECRET`, `ADMIN_SESSION_HOURS` | Assinatura e duração das sessões web |
| `APP_AUTH_TOKEN`, `ENABLE_APP_AUTH` | Autenticação dos clientes nativos; PWA usa cookies HttpOnly |
| `INTERNAL_AUTH_TOKEN` | Autenticação dos endpoints de processamento/manutenção |
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` | Web Push; deixe as três vazias para desabilitar sem afetar o restante do sistema |
| `SEED_SAMPLE_DATA` | Dados de exemplo; mantenha `false` em produção |
| `NOMINATIM_BASE_URL`, `OVERPASS_BASE_URL` | Geocodificação e descoberta de locais; padrões no `.env.example` |
| `JOB_BATCH_SIZE`, `STALE_JOB_MINUTES`, `JOB_HISTORY_RETENTION_DAYS`, `MESSAGE_RETENTION_LIMIT` | Ajustes de processamento e retenção; padrões no `.env.example` |

Configuração VAPID incompleta ou inválida impede a inicialização, para que um
servidor aparentemente saudável não anuncie push incorretamente configurado.
O banco guarda endpoints e chaves de inscrição de cada instalação. Proteja o
banco e seus backups com as mesmas permissões dos dados dos participantes.

### Instalar o projeto no servidor

Exemplo com usuário de serviço `geonexo` e Node instalado em `/usr/bin/node`.
Confira `command -v node` e ajuste os caminhos se sua instalação for diferente.
O serviço systemd não carrega automaticamente o ambiente do nvm do seu terminal.

```bash
sudo useradd --system --user-group --home-dir /opt/geonexo --create-home geonexo
sudo -u geonexo git clone https://github.com/Giuseph66/relogio-blue.git /opt/geonexo/relogio-blutu
sudo install -d -o geonexo -g geonexo -m 750 /var/lib/geonexo /opt/geonexo/pwa-releases
cd /opt/geonexo/relogio-blutu/server
sudo -u geonexo npm ci --omit=dev
sudo -u geonexo cp .env.example .env
```

Edite `/opt/geonexo/relogio-blutu/server/.env` com a configuração de produção
acima e execute `sudo chmod 600 /opt/geonexo/relogio-blutu/server/.env`.
Se o usuário ou os diretórios já existirem, reutilize-os em vez de recriá-los.
Mantenha apenas **um processo Node** para esta instalação; não use modo cluster
com vários workers compartilhando o SQLite e o estado de envios em memória.

### Compilar e publicar a versão web/PWA

Na máquina que tem o Flutter, na raiz do projeto:

```bash
flutter pub get
python3 scripts/build_pwa.py
```

O resultado está em `build/web/`. O script gera o service worker com a versão e
os hashes dos recursos offline. Copie a pasta **inteira**, incluindo `assets`,
`canvaskit`, ícones, JavaScript e `sw.js`; não copie apenas `index.html`.
O caminho público utilizado por esta aplicação é `/app/`.

Exemplo de envio para uma pasta temporária no servidor:

```bash
rsync -av --delete build/web/ SEU_USUARIO@SEU_SERVIDOR:/tmp/geonexo-pwa/
```

No servidor, publique uma versão nova e troque o link de forma atômica:

```bash
release_dir="/opt/geonexo/pwa-releases/$(date +%Y%m%d-%H%M%S)"
sudo install -d -o geonexo -g geonexo "$release_dir"
sudo rsync -a --chown=geonexo:geonexo /tmp/geonexo-pwa/ "$release_dir/"
sudo ln -s "$release_dir" /opt/geonexo/pwa-next
sudo mv -Tf /opt/geonexo/pwa-next /opt/geonexo/pwa-current
```

O `PWA_DIR` do `.env` deve apontar para `/opt/geonexo/pwa-current`. A troca do
front-end não exige reiniciar o Node; alterações de API ou `.env` exigem.
O build pode ser gerado diretamente no servidor se ele tiver Flutter instalado,
mas o serviço de produção executa somente Node.

### Manter o back-end ligado com systemd

Crie `/etc/systemd/system/geonexo.service`:

```ini
[Unit]
Description=GeoNexo API e front-ends
After=network.target

[Service]
Type=simple
User=geonexo
Group=geonexo
WorkingDirectory=/opt/geonexo/relogio-blutu/server
ExecStart=/usr/bin/node /opt/geonexo/relogio-blutu/server/server.js
Environment=NODE_ENV=production
Restart=on-failure
RestartSec=5
UMask=0077

[Install]
WantedBy=multi-user.target
```

O próprio Node carrega o `.env`; não é necessário copiá-lo para a unidade.
Ative e confira:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now geonexo
sudo systemctl status geonexo
curl --fail http://127.0.0.1:3001/health
sudo journalctl -u geonexo -n 100 --no-pager
```

### Nginx, domínio e HTTPS

Crie `/etc/nginx/sites-available/geonexo`, substituindo o domínio:

```nginx
server {
    listen 80;
    server_name geo.exemplo.edu.br;

    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Appengine-Cron "";
        proxy_buffering off;
        proxy_read_timeout 300s;
    }
}
```

Ative a configuração e emita o certificado:

```bash
sudo ln -s /etc/nginx/sites-available/geonexo /etc/nginx/sites-enabled/geonexo
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d geo.exemplo.edu.br --redirect
sudo certbot renew --dry-run
```

Certbot adiciona a configuração TLS e o redirecionamento para HTTPS. Se já houver
Nginx/proxy/certificados no servidor, adapte o virtual host existente. Não
publique a porta Node diretamente nem configure cache do proxy para `/api`,
`/admin`, `sw.js` ou os arquivos da PWA. Com Nginx, não é necessário servir uma
segunda cópia dos arquivos estáticos: todas as rotas continuam no Node.

Confira os endereços finais:

- `https://geo.exemplo.edu.br/`: dashboard público.
- `https://geo.exemplo.edu.br/admin/login`: acesso administrativo.
- `https://geo.exemplo.edu.br/admin/config`: cadastro de locais/perguntas.
- `https://geo.exemplo.edu.br/admin/dashboard`: respostas e envio de Web Push.
- `https://geo.exemplo.edu.br/app/`: aplicativo web instalável.
- `https://geo.exemplo.edu.br/health`: saúde da API.

### Processamento e manutenção no servidor próprio

As respostas recebidas entram na fila de tarefas do SQLite. O arquivo
`server/cron.yaml` atende ao Google App Engine; ele **não agenda nada em um Linux
próprio**. Configure cron no usuário `geonexo`:

```bash
sudo crontab -u geonexo -e
```

Adicione, ajustando o caminho do Node se necessário:

```cron
*/5 * * * * cd /opt/geonexo/relogio-blutu/server && /usr/bin/node scripts/run-jobs.js process-pending >> /var/lib/geonexo/jobs.log 2>&1
15 3 * * * cd /opt/geonexo/relogio-blutu/server && /usr/bin/node scripts/run-jobs.js maintenance >> /var/lib/geonexo/jobs.log 2>&1
```

O script carrega o `.env`, chama a API local e usa `INTERNAL_AUTH_TOKEN` sem
colocar o token no comando do cron. Configure rotação de `jobs.log` conforme a
política do servidor. Os avisos Web Push são enviados na requisição do painel e
**não dependem desse cron**. Não há agendamento ou fila de reenvio de push:
falhas temporárias aparecem no resultado e podem ser reenviadas pelo operador.

### Ativar e testar Web Push nos celulares

1. Abra `/app/` por HTTPS, entre como visitante ou administrador e instale a PWA.
2. No Android, use preferencialmente Chrome. No iPhone, use iOS 16.4 ou posterior,
   adicione à Tela de Início e **abra pelo ícone instalado**.
3. Em **Ajustes → Neste dispositivo**, toque em **Permitir notificações** e
   aceite a permissão. Ative **Avisos com o app fechado** para cadastrar o celular
   no servidor, caso essa opção ainda não esteja habilitada.
4. Abra **Verificar notificações** nessa seção. **Testar aviso local** verifica
   o navegador; **Testar aviso do servidor** verifica o Web Push ao celular atual.
   Aguarde 30 segundos entre testes remotos.
5. Para comprovar o funcionamento fechado, feche a PWA no celular e, **em outro
   navegador/computador**, entre em `/admin/dashboard`. Em **Avisos nos celulares**,
   escreva título/mensagem e toque em **Enviar aos celulares inscritos**.
6. Confira a Central de Notificações e toque no aviso para abrir a PWA. O aviso
   remoto é um comunicado; perguntas pendentes já salvas continuam no aplicativo.
7. Para parar os avisos remotos naquele aparelho, desligue **Avisos com o app fechado**.
   Sair da conta na PWA também remove a inscrição do navegador. Bloquear a
   permissão nos ajustes do sistema impede novas notificações.

A API aceita o envio administrativo em `POST /api/admin/push/send` com JSON
`{"title":"GeoNexo","body":"Abra o aplicativo para participar."}` e sessão
administrativa, ou token interno para automação autorizada. Participantes não
podem disparar mensagens para outros celulares. O resultado informa `total`,
`accepted`, `expired` e `failed`; **aceito pelo serviço não confirma entrega nem
leitura**. Endpoints expirados (HTTP 404/410) são removidos automaticamente;
outros erros preservam a inscrição. O aviso tem validade de uma hora no provedor.

As inscrições persistem no SQLite após reiniciar o Node, independentemente da
sessão web estar aberta. Ao reabrir o app, a inscrição existente é renovada no
servidor; se a sessão expirou, entre novamente. Preserve banco, dados do site e
chaves VAPID. Após trocar as chaves, desative/ative o Web Push novamente nos
aparelhos. Os provedores permitidos são Apple, FCM/Google, Mozilla e Windows;
para outro provedor, revise a validação em `push-service.js`.

**Web Push não é GPS em segundo plano.** O servidor entrega comunicados mesmo
sem página aberta, mas não recebe posições novas do iPhone/PWA fechada. Visitas
automáticas continuam exigindo GPS e PWA aberta. Para detectar novas chegadas com
a tela bloqueada no iPhone, é necessária implementação nativa específica.
Notificações dependem de internet, permissão, conectividade com o provedor e
ajustes de foco/economia de energia do sistema. O Web Push desta implementação
é da **versão web/PWA**; não configura notificações remotas do APK ou do app iOS nativo.

### Configurar e gerar o aplicativo Android

O APK usa a mesma API publicada, mas não é hospedado como uma página. Na raiz,
configure o domínio e o token no build:

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=https://geo.exemplo.edu.br --dart-define=APP_AUTH_TOKEN=SEU_TOKEN_DO_SERVIDOR
flutter build apk --release --dart-define=API_BASE_URL=https://geo.exemplo.edu.br --dart-define=APP_AUTH_TOKEN=SEU_TOKEN_DO_SERVIDOR
```

O APK estará em `build/app/outputs/flutter-apk/app-release.apk`. Para instalar em
um Android conectado por USB, use `adb install -r` com esse arquivo. O token deve
ser o mesmo `APP_AUTH_TOKEN` do `.env`. O token embutido em um aplicativo
compilado é recuperável; não equivale a uma credencial individual por usuário.
O login nativo ainda usa os valores de `lib/core/auth/auth_service.dart`,
independentes do login web configurado no servidor.

O projeto atualmente usa assinatura de **debug** também na configuração release.
Antes de distribuir oficialmente/Play Store, configure keystore/assinatura de
produção e identificador de pacote próprios conforme a
[documentação Flutter para Android](https://docs.flutter.dev/deployment/android).
Para a loja, gere `flutter build appbundle --release` com os mesmos
`--dart-define` após configurar a assinatura. Esta entrega não altera a assinatura.

No aparelho, conceda as permissões solicitadas de localização, notificações e
Bluetooth. O Android nativo conserva seu serviço de monitoramento existente;
teste o comportamento em segundo plano e as restrições de bateria do aparelho
real. Bancos do APK e da PWA são independentes; trocar a forma de instalação não
migra automaticamente respostas locais ainda não sincronizadas.

### Situação do iPhone nativo

A distribuição recomendada nesta entrega para iPhone é **a PWA instalada**.
A pasta `ios/` existe, mas isso não comprova paridade com Android: o projeto ainda
precisa de revisão de permissões Bluetooth, capabilities, serviços de localização,
notificações e execução em segundo plano. O `Info.plist` atual tem descrição de
localização durante uso; não configura sozinho monitoramento nativo contínuo.

Para evoluir o app nativo, use macOS, Xcode, CocoaPods, dispositivo real e uma
equipe de assinatura Apple. Depois das adequações e validação, os comandos-base
são `flutter run` em um iPhone conectado e `flutter build ipa --release`, com os
mesmos `--dart-define` de URL/token. A distribuição usa TestFlight/App Store ou
outro método permitido pela conta Apple; o servidor do professor hospeda a API,
não substitui assinatura e distribuição iOS. Nenhum build iOS foi homologado nesta entrega.

### Atualizações, backup e verificação

Na verificação desta entrega, `npm audit --omit=dev` apontou **13 alertas** nas
dependências do servidor (6 moderados, 5 altos e 2 críticos). `proxy-addr` e
`tar` foram os pacotes classificados como críticos; `web-push` não aparece na
lista de pacotes vulneráveis. Revise/corrija essas dependências e valide a
compatibilidade antes de expor a instalação em produção. Os testes funcionais
descritos abaixo não resolvem nem substituem essa revisão de segurança.

Para atualizar o back-end, atualize o código, execute `npm ci --omit=dev` dentro
de `server/` e reinicie `sudo systemctl restart geonexo`. Faça backup antes de
atualizações. A tabela de inscrições push é adicionada automaticamente e não
apaga as tabelas existentes. Para a PWA, gere um novo build e publique uma nova
pasta conforme o procedimento de troca atômica. Usuários com versão antiga
recebem o botão **Atualizar** quando o novo cache estiver pronto.

Faça backup do `.env` em local protegido e do SQLite usando a operação de backup,
por exemplo com `sqlite3 /var/lib/geonexo/app.db ".backup '/CAMINHO/backup.db'"`
com um usuário que tenha acesso. Não copie o banco enquanto ele está sendo escrito
como se fosse um arquivo estático. Para rollback da interface, aponte
`pwa-current` para a pasta anterior. Isso não reverte alterações de dados.

Na raiz do projeto, as verificações de desenvolvimento são:

```bash
node --test test/pwa_server_test.js test/pwa_notifications_test.js test/web_push_server_test.js
flutter test test/widget_test.dart
flutter analyze
python3 scripts/build_pwa.py
```

Os testes automatizados usam banco temporário e transporte push simulado, mas
exercitam a geração real de criptografia/VAPID. Não substituem o teste físico de
entrega com a PWA fechada. Antes da apresentação, valide nos dois aparelhos:
instalação, GPS com app aberto, visita, aviso local, aviso remoto fechado,
resposta offline, sincronização e, no Android, relógio BLE real se for usado.

| Problema | O que conferir |
| --- | --- |
| `/app/` retorna 404 | `PWA_DIR`, pasta completa, permissões do usuário `geonexo` e publicação do build |
| Login web não funciona | Domínio único, credenciais do `.env`, API acessível e cookies habilitados |
| GPS/avisos indisponíveis | HTTPS válido, permissões do site/sistema e instalação na Tela de Início do iPhone |
| Web Push não aparece | Três variáveis VAPID, reinício do serviço, inscrição ativa e saída HTTPS para o provedor |
| Aviso aceito, mas não recebido | Foco/Não Perturbe, rede do aparelho, permissão, inscrição expirada e logs do servidor |
| Respostas continuam pendentes | Cron de `process-pending`, token interno e logs em `/var/lib/geonexo/jobs.log` |
| Mapa/endereço não carrega | Internet e disponibilidade dos serviços OSM/Nominatim/Overpass; respeite suas políticas de uso |
| Versão antiga continua abrindo | Aguarde o cache novo, use **Atualizar** e confira se o proxy não está cacheando arquivos da PWA |

Referências: [biblioteca web-push](https://github.com/web-push-libs/web-push),
[Web Push no iPhone/iPad](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)
e [documentação Apple](https://developer.apple.com/documentation/usernotifications/sending-web-push-notifications-in-web-apps-and-browsers).
