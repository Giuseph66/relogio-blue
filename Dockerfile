# syntax=docker/dockerfile:1
# GeoNexo: servidor (API + painéis + PWA). Veja docker-compose.yml.

# ─── Flutter SDK, na mesma versão usada no desenvolvimento ───────────────────
FROM debian:bookworm-slim AS flutter-sdk
ARG FLUTTER_VERSION=3.47.5
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git python3 unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:$PATH" CI=true
RUN flutter config --no-analytics && flutter precache --web --no-android --no-ios

# ─── Aplicativo web (PWA) ────────────────────────────────────────────────────
FROM flutter-sdk AS pwa
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY analysis_options.yaml ./
COPY assets assets
COPY scripts scripts
COPY web web
COPY lib lib
RUN python3 scripts/build_pwa.py

# ─── APK (só com "docker compose run apk") ───────────────────────────────────
FROM ghcr.io/cirruslabs/android-sdk:36 AS apk
USER root
# Kept in the image so it is downloaded only once.
RUN yes | sdkmanager 'ndk;28.2.13676358' 'cmake;3.22.1' > /dev/null
COPY --from=flutter-sdk /opt/flutter /opt/flutter
ENV PATH="/opt/flutter/bin:$PATH" CI=true
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN git config --global --add safe.directory /opt/flutter \
 && flutter config --no-analytics && flutter pub get --enforce-lockfile
COPY . .
CMD ["sh", "docker/build-apk.sh"]

# ─── Dependências do servidor ────────────────────────────────────────────────
FROM node:24-trixie AS server-deps
WORKDIR /srv/server
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev

# ─── Imagem final ────────────────────────────────────────────────────────────
FROM node:24-trixie-slim AS server
ENV NODE_ENV=production HOST=0.0.0.0 PORT=3001 \
    DB_PATH=/data/app.db PWA_DIR=/srv/pwa TRUST_PROXY=uniquelocal
WORKDIR /srv/server
COPY --from=server-deps /srv/server/node_modules node_modules
COPY server .
COPY --from=pwa /src/build/web /srv/pwa
COPY docker/start.js docker/jobs.js /srv/docker/
RUN mkdir /data && chown node:node /data
USER node
VOLUME /data
EXPOSE 3001
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=6 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3001/health').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"]
CMD ["node", "/srv/docker/start.js"]
