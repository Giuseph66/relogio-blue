#!/bin/sh
# Gera dist/geonexo.apk apontando para o servidor deste Docker.
set -eu
: "${API_BASE_URL:?Defina API_BASE_URL no .env, por exemplo https://geo.exemplo.edu.br}"
token="${APP_AUTH_TOKEN:-}"
if [ -z "$token" ]; then
  token="$(sed -n 's/^APP_AUTH_TOKEN=//p' /data/config.env 2>/dev/null || true)"
fi
[ -n "$token" ] || { echo 'Suba o servidor antes: docker compose up -d' >&2; exit 1; }

# The signing key must never change: Android only updates an app signed with the
# same key, and the phone's identity (one answer per device) depends on it.
mkdir -p /root/.android /root/.gradle
if [ ! -f /root/.android/debug.keystore ]; then
  keytool -genkeypair -keystore /root/.android/debug.keystore -storepass android -keypass android \
    -alias androiddebugkey -dname 'CN=GeoNexo' -keyalg RSA -keysize 2048 -validity 10000
fi
printf 'org.gradle.jvmargs=-Xmx3g -XX:MaxMetaspaceSize=1g\norg.gradle.daemon=false\n' > /root/.gradle/gradle.properties

flutter build apk --release --dart-define="API_BASE_URL=$API_BASE_URL" --dart-define="APP_AUTH_TOKEN=$token"
install -m 644 build/app/outputs/flutter-apk/app-release.apk /out/geonexo.apk
chown "$(stat -c %u:%g /out)" /out/geonexo.apk
echo 'APK pronto: dist/geonexo.apk'
