#!/usr/bin/env bash
# Instala las dependencias y despliega el laboratorio de forma no interactiva.
set -euo pipefail

readonly DIRECTORIO_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

correcto() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$*"
}

error() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
}

# Reejecuta únicamente la parte privilegiada con sudo si el usuario no es root.
if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        error "La instalación necesita permisos administrativos y sudo no está instalado."
        exit 1
    fi
    info "Se solicitarán permisos de administrador para instalar y configurar nginx."
    exec sudo -- "$0" "$@"
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

paquetes=()
command -v nginx >/dev/null 2>&1 || paquetes+=(nginx)
command -v curl >/dev/null 2>&1 || paquetes+=(curl)

if (( ${#paquetes[@]} > 0 )); then
    info "Actualizando el índice de paquetes..."
    apt-get update
    info "Instalando: ${paquetes[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${paquetes[@]}"
else
    correcto "nginx y curl ya están instalados."
fi

info "Desplegando el laboratorio..."
bash "$DIRECTORIO_SCRIPT/preparar-lab.sh"

printf '\n'
correcto "Laboratorio listo en http://localhost/"
printf 'Para repetir la explicación guiada: %s\n' \
    "cd '$DIRECTORIO_SCRIPT' && sudo ./video2.sh"
