#!/usr/bin/env bash
# Build di release di Lemani (iOS e/o Android) con configurazione verificata.
#
#   scripts/build_release.sh [ios|android|all] [--check] [--config <file>]
#
#   ios | android | all   cosa costruire (default: all)
#   --check               solo verifica della configurazione, nessuna build
#   --config <file>       default: config/release.json (modello:
#                         config/release.example.json, mai con valori veri
#                         nel repository)
#
# Si ferma (exit 1) con un messaggio se in config mancano o sono segnaposto
# (TODO_REPLACE, "example", raen.example): API_BASE_URL (https),
# REAL_PAYMENTS=true, IOS_UNLOCK_PRODUCT_ID, ANDROID_UNLOCK_PRODUCT_ID,
# GOOGLE_CLOUD_PROJECT_NUMBER. Una release senza queste cose si avvierebbe ma
# "Non disponibile" ai pagamenti e senza server: meglio non costruirla.
#
# Le build usano --obfuscate e --split-debug-info=symbols/<versione>+<build>/<piattaforma>:
# i simboli NON vanno in git (symbols/ è in .gitignore) ma vanno archiviati
# (es. caricati su Crashlytics/Play Console o conservati con la release).
set -euo pipefail

cd "$(dirname "$0")/.."

target="all"
check_only=0
config="config/release.json"
while [ $# -gt 0 ]; do
  case "$1" in
    ios|android|all) target="$1" ;;
    --check) check_only=1 ;;
    --config)
      shift
      [ $# -gt 0 ] || { echo "ERRORE: --config richiede un percorso." >&2; exit 1; }
      config="$1"
      ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "ERRORE: argomento sconosciuto: $1 (usa ios, android, all, --check, --config)" >&2; exit 1 ;;
  esac
  shift
done

if [ ! -f "$config" ]; then
  echo "ERRORE: manca $config. Copia config/release.example.json in config/release.json e compila i valori veri." >&2
  exit 1
fi

# Verifica della configurazione (python3 solo per leggere il JSON).
python3 - "$config" <<'PY'
import json, re, sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
except Exception as e:
    print(f"ERRORE: {path} non è un JSON valido: {e}", file=sys.stderr)
    sys.exit(1)
if not isinstance(cfg, dict):
    print(f"ERRORE: {path} deve essere un oggetto JSON.", file=sys.stderr)
    sys.exit(1)

PLACEHOLDER = re.compile(r"TODO_REPLACE|example|raen\.example", re.IGNORECASE)
errors = []

def text(key):
    value = cfg.get(key)
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{key}: manca o è vuoto")
        return None
    if PLACEHOLDER.search(value):
        errors.append(f"{key}: è ancora un segnaposto ({value!r})")
        return None
    return value.strip()

url = text("API_BASE_URL")
if url is not None and not url.lower().startswith("https://"):
    errors.append(f"API_BASE_URL: deve essere https:// ({url!r})")

payments = cfg.get("REAL_PAYMENTS")
if payments not in (True, "true"):
    errors.append(f"REAL_PAYMENTS: deve essere true (è {payments!r}): una release senza pagamenti veri non si può pubblicare")

text("IOS_UNLOCK_PRODUCT_ID")
text("ANDROID_UNLOCK_PRODUCT_ID")

number = cfg.get("GOOGLE_CLOUD_PROJECT_NUMBER")
if isinstance(number, str) and number.isdigit():
    number = int(number)
if isinstance(number, bool) or not isinstance(number, int) or number <= 0:
    errors.append(f"GOOGLE_CLOUD_PROJECT_NUMBER: deve essere il numero del progetto Google Cloud, > 0 (è {number!r})")

if errors:
    print(f"ERRORE: configurazione di release non valida ({path}):", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    print("Compila i valori veri (modello: config/release.example.json).", file=sys.stderr)
    sys.exit(1)
PY

version="$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p' pubspec.yaml | head -n1)"
[ -n "$version" ] || { echo "ERRORE: non trovo 'version:' in pubspec.yaml." >&2; exit 1; }

echo "Configurazione OK ($config), versione $version."
if [ "$check_only" -eq 1 ]; then
  exit 0
fi

common=(--release "--dart-define-from-file=$config" --obfuscate)

if [ "$target" = "ios" ] || [ "$target" = "all" ]; then
  mkdir -p "symbols/$version/ios"
  flutter build ipa "${common[@]}" "--split-debug-info=symbols/$version/ios"
fi
if [ "$target" = "android" ] || [ "$target" = "all" ]; then
  mkdir -p "symbols/$version/android"
  flutter build appbundle "${common[@]}" "--split-debug-info=symbols/$version/android"
fi

echo
echo "Fatto. Archivia symbols/$version (fuori da git): serve a leggere i crash di questa versione."
