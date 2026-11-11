#!/usr/bin/env bash
# Validation complète du dépôt : à lancer avant chaque livraison de paquet.
#   tool/validate.sh           analyse + tous les tests
#   tool/validate.sh --build   + APK Android et agent Windows (si Windows)
set -uo pipefail
cd "$(dirname "$0")/.."

BUILD=0
[ "${1:-}" = "--build" ] && BUILD=1

results=()
failed=0

step() {
  local name="$1"; shift
  echo
  echo "=== $name ==="
  if "$@"; then
    results+=("OK      $name")
  else
    results+=("ÉCHEC   $name")
    failed=1
  fi
}

step "Dépendances"              flutter pub get
step "Analyse statique"         flutter analyze
step "Tests pegasus_protocol"   bash -c "cd packages/pegasus_protocol && dart test"
step "Tests pegasus_link (e2e)" bash -c "cd packages/pegasus_link && dart test"
step "Tests pegasus_ui"         bash -c "cd packages/pegasus_ui && flutter test"
step "Tests agent"              bash -c "cd agent && flutter test"
step "Tests mobile"             bash -c "cd mobile && flutter test"

if [ "$BUILD" = 1 ]; then
  step "Build APK (debug)"      bash -c "cd mobile && flutter build apk --debug"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) step "Build agent Windows" bash -c "cd agent && flutter build windows --release" ;;
  esac
fi

echo
echo "=== Résumé ==="
printf '%s\n' "${results[@]}"
exit $failed
