#!/bin/bash
# Instala el laboratorio funcionando: nginx en localhost:8081 hace de proxy de una
# aplicación de ejemplo en 127.0.0.1:8001. Para provocar la avería: ./romper.sh
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

umask 022

ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ORIGEN

info() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

correcto() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$*"
}

error() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
}

# Reejecuta el script con sudo si el usuario no es root.
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
source "$ORIGEN/comun.sh"

# Comprobaciones previas: si algo no cuadra, se aborta antes de modificar nada.
if command -v ss >/dev/null 2>&1; then
    comprobar_puertos
fi
comprobar_rutas_ajenas

paquetes=()
nginx_nuevo=0
if ! command -v nginx >/dev/null 2>&1; then
    paquetes+=(nginx)
    nginx_nuevo=1
fi
command -v curl >/dev/null 2>&1 || paquetes+=(curl)
command -v ss >/dev/null 2>&1 || paquetes+=(iproute2)
[[ -x /usr/bin/python3 ]] || paquetes+=(python3)

if (( ${#paquetes[@]} > 0 )); then
    info "Actualizando el índice de paquetes..."
    apt-get update
    info "Instalando: ${paquetes[*]}"
    # El paquete nginx intenta arrancar con el sitio "default" (puerto 80 en todas las
    # interfaces). policy-rc.d lo impide: así no falla si Apache ocupa el puerto 80 y
    # nada queda expuesto a la red. Solo se crea si no existía ya.
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
        info "Se desactivó el sitio 'default' de nginx (puerto 80 abierto a la red)."
    fi
    # Con los paquetes ya instalados, se repite la comprobación de puertos.
    comprobar_puertos
else
    correcto "nginx, curl, ss y python3 ya están instalados."
fi

# Si algo falla o se interrumpe después de publicar el sitio, se retira para no dejar
# en nginx una configuración que podría impedir su próximo arranque.
sitio_publicado=0
completado=0
limpiar() {
    if (( ! completado && sitio_publicado )); then
        retirar_sitio || true
        error "La instalación falló; se retiró el sitio del laboratorio de nginx."
    fi
}
trap limpiar EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# 1. Aplicación de ejemplo y su servicio de systemd (no se habilita al arrancar el equipo).
info "Instalando la aplicación de ejemplo..."
install -d -m 755 "$DIRECTORIO_APP"
install -m 644 "$ORIGEN/app/app.py" "$DIRECTORIO_APP/app.py"
install -m 644 /dev/null "$MARCADOR"
install -m 644 "$ORIGEN/app/$SERVICIO.service" "$UNIDAD"
systemctl daemon-reload
systemctl restart "$SERVICIO"
esperar_puerto "$PUERTO_APP" abierto
correcto "Aplicación en marcha en 127.0.0.1:$PUERTO_APP (servicio $SERVICIO)."

# 2. Sitio de nginx que hace de proxy hacia la aplicación.
info "Publicando el sitio en nginx..."
sitio_publicado=1
install -m 644 "$ORIGEN/nginx/$SITIO" "$SITIO_DISPONIBLE"
ln -sfn "$SITIO_DISPONIBLE" "$SITIO_ACTIVO"
if ! nginx -t -q; then
    error "La configuración de nginx no es válida."
    exit 1
fi
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
else
    info "nginx estaba parado; se arranca (también arrancan sus otros sitios)."
    systemctl start nginx
fi
esperar_puerto "$PUERTO" abierto

# 3. Comprobación: el laboratorio recién instalado tiene que responder 200.
codigo=$(codigo_http)
if [[ $codigo != 200 ]]; then
    error "El laboratorio respondió $codigo en lugar de 200."
    exit 1
fi
completado=1

avisar_sitio_default
printf '\n'
correcto "Laboratorio listo en $URL/ (responde 200 OK)."
printf 'Para provocar la avería: %s\n' "sudo ./romper.sh"
