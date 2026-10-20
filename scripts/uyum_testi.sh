#!/usr/bin/env bash
# Telefonun GERCEK Dart kodu ile GERCEK Python koprusunun birlikte calistigini dogrular.
#   ./scripts/uyum_testi.sh
# Gerekli: Flutter SDK, pip install -r kopru/requirements.txt
set -euo pipefail
kok="$(cd "$(dirname "$0")/.." && pwd)"
port=$((20000 + RANDOM % 20000))
log=$(mktemp)
(cd "$kok/kopru" && exec python3 -m mobile_bridge.deneme_sunucusu --host 127.0.0.1 --port "$port" \
   --token UYUM "$@") > "$log" 2>&1 &
sunucu=$!
trap 'kill $sunucu 2>/dev/null || true; rm -f "$log"' EXIT
for _ in $(seq 100); do grep -q "Deneme sunucusu" "$log" && break; sleep 0.1; done
cd "$kok/mobil"
TELSIZ_UYUM_URL="ws://127.0.0.1:$port/telsiz?token=UYUM" flutter test test/uyum_test.dart
echo "--- sunucu günlüğü ---"; grep '^  ' "$log" || true
