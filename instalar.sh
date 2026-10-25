#!/bin/bash
# Instala las dependencias y despliega el laboratorio de forma no interactiva.
# Con "sh instalar.sh" se usaría dash, que no entiende la sintaxis de bash.
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi
# Entorno limpio: con "su" (sin "-") se heredaría el del usuario (PATH sin /usr/sbin,
# funciones exportadas, TMPDIR...), que podría hacer que root ejecute código ajeno.
if [[ -z "${LAB_ENTORNO_LIMPIO:-}" ]]; then
    exec /usr/bin/env -i LAB_ENTORNO_LIMPIO=1 TERM="${TERM:-dumb}" LANG="${LANG:-C.UTF-8}" \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /bin/bash --norc --noprofile "$(/usr/bin/readlink -f -- "${BASH_SOURCE[0]}")" "$@"
fi
set -euo pipefail

DIRECTORIO_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DIRECTORIO_SCRIPT

info() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

correcto() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$*"
}

error() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
}

trap 'error "La instalación falló en la línea $LINENO. Revisa los mensajes anteriores."' ERR

# Reejecuta únicamente la parte privilegiada con sudo si el usuario no es root.
if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        error "La instalación necesita permisos administrativos y sudo no está instalado."
        exit 1
    fi
    info "Se solicitarán permisos de administrador para instalar y configurar nginx."
    exec sudo -- /bin/bash "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
fi

if [[ ! -r /etc/os-release ]]; then
    error "No se puede identificar el sistema operativo."
    exit 1
fi

# Parrot deriva de Debian y usa apt-get. Se evita modificar otros sistemas.
# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID:-}" != "debian" && "${ID_LIKE:-}" != *debian* ]]; then
    error "Este instalador está preparado para Debian, Parrot OS y derivados."
    exit 1
fi

# shellcheck source=comun.sh
source "$DIRECTORIO_SCRIPT/comun.sh"

# Si esta copia aún contiene los commits retirados del historial público, se eliminan
# de .git sin tocar los archivos del laboratorio (ver "Historial del repositorio" en el README).
if [[ -f "$DIRECTORIO_SCRIPT/actualizar.sh" ]]; then
    /bin/bash "$DIRECTORIO_SCRIPT/actualizar.sh" --limpiar || true
fi

# Comprobaciones previas: si algo no cuadra, se aborta antes de instalar paquetes
# o de modificar nada. preparar-lab.sh las repite por si se ejecuta por separado.
if command -v ss >/dev/null 2>&1; then
    comprobar_puerto
fi
for directorio in "$WEB" "$WEB/carpeta" "$WEB/privado"; do
    comprobar_directorio "$directorio"
done
comprobar_rutas_ajenas

paquetes=()
nginx_nuevo=0
if ! command -v nginx >/dev/null 2>&1; then
    paquetes+=(nginx)
    nginx_nuevo=1
fi
command -v curl >/dev/null 2>&1 || paquetes+=(curl)
command -v ss >/dev/null 2>&1 || paquetes+=(iproute2)

if (( ${#paquetes[@]} > 0 )); then
    info "Actualizando el índice de paquetes..."
    apt-get update
    info "Instalando: ${paquetes[*]}"
    # El paquete nginx intenta arrancar con el sitio "default" (puerto 80 en todas las
    # interfaces). policy-rc.d lo impide: así no falla si Apache ocupa el puerto 80 y el
    # laboratorio no queda expuesto a la red. Solo se crea si no existía ya.
    policy_creado=0
    if (( nginx_nuevo )) && [[ ! -e /usr/sbin/policy-rc.d && ! -L /usr/sbin/policy-rc.d ]]; then
        printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
        chmod 755 /usr/sbin/policy-rc.d
        policy_creado=1
        trap 'rm -f /usr/sbin/policy-rc.d' EXIT
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${paquetes[@]}"
    if (( policy_creado )); then
        rm -f /usr/sbin/policy-rc.d
        trap - EXIT
    fi
    if (( nginx_nuevo )) && [[ -L /etc/nginx/sites-enabled/default ]]; then
        rm -f /etc/nginx/sites-enabled/default
        info "Se desactivó el sitio 'default' de nginx (puerto 80 abierto a la red); el laboratorio usa localhost:8080."
    fi
else
    correcto "nginx, curl y ss ya están instalados."
fi

info "Desplegando el laboratorio..."
/bin/bash "$DIRECTORIO_SCRIPT/preparar-lab.sh"

printf '\n'
correcto "Laboratorio listo en http://localhost:8080/"
printf 'Para repetir la explicación guiada: %s\n' \
    "cd '$DIRECTORIO_SCRIPT' && sudo ./video2.sh"
