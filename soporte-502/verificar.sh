#!/usr/bin/env bash
# Comprueba si la web del laboratorio funciona (200) o está averiada (5xx).
# No necesita sudo ni modifica nada. Termina con 0 solo si la web responde 200.
# Con "sh verificar.sh" se usaría dash, que no entiende la sintaxis de bash.
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi
set -euo pipefail

ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ORIGEN
# shellcheck source=comun.sh
source "$ORIGEN/comun.sh"

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl no está instalado." >&2
    exit 1
fi

codigo=$(codigo_http)
case $codigo in
200)
    printf '\033[1;32m[OK]\033[0m %s responde 200: la web funciona.\n' "$URL/"
    exit 0
    ;;
502)
    printf '\033[1;31m[AVERÍA]\033[0m %s responde 502 Bad Gateway.\n' "$URL/" >&2
    ;;
5??)
    printf '\033[1;31m[AVERÍA]\033[0m %s responde %s.\n' "$URL/" "$codigo" >&2
    ;;
000)
    printf '\033[1;31m[AVERÍA]\033[0m %s no responde: nginx no está escuchando.\n' "$URL/" >&2
    ;;
*)
    printf '\033[1;33m[AVISO]\033[0m %s responde %s.\n' "$URL/" "$codigo" >&2
    ;;
esac
exit 1
