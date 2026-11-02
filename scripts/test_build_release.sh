#!/usr/bin/env bash
# Prova di scripts/build_release.sh: con configurazioni non valide deve
# fallire (exit 1) con un messaggio chiaro, con quella valida passare il
# controllo. Non costruisce nulla (usa --check).
#   scripts/test_build_release.sh
set -uo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

valid='{"API_BASE_URL":"https://api.raen.app","REAL_PAYMENTS":true,"IOS_UNLOCK_PRODUCT_ID":"app.raen.unlock2h","ANDROID_UNLOCK_PRODUCT_ID":"unlock_2h","GOOGLE_CLOUD_PROJECT_NUMBER":123456789}'

expect_fail() { # nome, json, testo atteso nel messaggio
  printf '%s' "$2" > "$tmp/c.json"
  out="$(scripts/build_release.sh all --check --config "$tmp/c.json" 2>&1)"; code=$?
  if [ "$code" -ne 1 ] || ! grep -q -- "$3" <<<"$out"; then
    echo "KO  $1 (exit $code, atteso 1 con '$3'):"; echo "$out" | sed 's/^/      /'; fail=1
  else
    echo "ok  $1"
  fi
}

expect_fail "JSON vuoto" "" "non è un JSON valido"
rm -f "$tmp/none.json"
out="$(scripts/build_release.sh all --check --config "$tmp/none.json" 2>&1)"; [ $? -eq 1 ] && grep -q "manca" <<<"$out" && echo "ok  config assente" || { echo "KO  config assente"; fail=1; }
expect_fail "esempio com'è" "$(cat config/release.example.json)" "segnaposto"
expect_fail "http" "${valid/https:/http:}" "deve essere https"
expect_fail "dominio example" "${valid/api.raen.app/raen.example}" "API_BASE_URL"
expect_fail "pagamenti spenti" "${valid/\"REAL_PAYMENTS\":true/\"REAL_PAYMENTS\":false}" "REAL_PAYMENTS"
expect_fail "product id TODO" "${valid/app.raen.unlock2h/TODO_REPLACE_x}" "IOS_UNLOCK_PRODUCT_ID"
expect_fail "product id mancante" "${valid/,\"ANDROID_UNLOCK_PRODUCT_ID\":\"unlock_2h\"/}" "ANDROID_UNLOCK_PRODUCT_ID"
expect_fail "progetto Google a 0" "${valid/123456789/0}" "GOOGLE_CLOUD_PROJECT_NUMBER"

printf '%s' "$valid" > "$tmp/c.json"
if scripts/build_release.sh all --check --config "$tmp/c.json" >/dev/null 2>&1; then
  echo "ok  configurazione valida"
else
  echo "KO  configurazione valida rifiutata"; fail=1
fi
exit "$fail"
