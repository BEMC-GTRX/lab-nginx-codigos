#!/usr/bin/env bash
# Comprueba que el laboratorio responde con todos los códigos esperados.
# Con "sh verificar.sh" se usaría dash: no entiende [[ ]] ni (( )) y daría un falso éxito.
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi
set -euo pipefail

readonly BASE_URL="${BASE_URL:-http://localhost:8080}"
fallos=0

comprobar() {
    local descripcion=$1
    local esperado=$2
    shift 2

    local obtenido
    # --noproxy: un http_proxy configurado (por ejemplo, hacia Burp) desviaría las peticiones.
    # --max-time: sin límite, un proxy que intercepta dejaría la prueba colgada.
    if ! obtenido=$(curl --silent --noproxy '*' --max-time 5 --output /dev/null \
        --write-out '%{http_code}' "$@"); then
        obtenido=000
    fi

    if [[ "$obtenido" == "$esperado" ]]; then
        printf '\033[1;32m[OK]\033[0m %-28s esperado=%s obtenido=%s\n' \
            "$descripcion" "$esperado" "$obtenido"
    else
        printf '\033[1;31m[FALLO]\033[0m %-25s esperado=%s obtenido=%s\n' \
            "$descripcion" "$esperado" "$obtenido" >&2
        fallos=$((fallos + 1))
    fi
}

if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl no está instalado." >&2
    exit 1
fi

comprobar "Página principal" 200 "$BASE_URL/"
comprobar "Archivo inexistente" 404 "$BASE_URL/no-existe.html"
comprobar "Redirección de carpeta" 301 "$BASE_URL/carpeta"
comprobar "Directorio privado" 403 "$BASE_URL/privado/"
comprobar "Archivo sin permisos" 403 "$BASE_URL/secreto.txt"
comprobar "Método no permitido" 405 --request POST "$BASE_URL/"
comprobar "Contenido parcial" 206 --range 0-99 "$BASE_URL/"
comprobar "Rango imposible" 416 --range 999999- "$BASE_URL/"
comprobar "Petición sin Host" 400 --header 'Host:' "$BASE_URL/"

if (( fallos > 0 )); then
    printf '\n%s comprobación(es) fallaron.\n' "$fallos" >&2
    exit 1
fi

printf '\nTodas las comprobaciones pasaron correctamente.\n'
