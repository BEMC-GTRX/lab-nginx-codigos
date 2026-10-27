#!/bin/bash
# Provoca la avería del laboratorio: para la aplicación que está detrás de nginx, así
# que nginx responde 502 Bad Gateway. A propósito, no dice en pantalla qué ha hecho:
# averiguarlo es el ejercicio. La solución paso a paso: ./ayuda-autoguiada-reparar-502.sh
# Uso: sudo ./romper.sh
# Con "sh romper.sh" se usaría dash, que no entiende la sintaxis de bash.
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

ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ORIGEN
# shellcheck source=comun.sh
source "$ORIGEN/comun.sh"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: ejecuta este script con sudo: sudo ./romper.sh" >&2
    exit 1
fi

if ! laboratorio_instalado; then
    echo "ERROR: el laboratorio no está instalado. Ejecuta primero ./instalar.sh" >&2
    exit 1
fi

if ! systemctl is-active --quiet nginx; then
    echo "ERROR: nginx no está en marcha. Arráncalo con: sudo systemctl start nginx" >&2
    exit 1
fi

if ! systemctl is-active --quiet "$SERVICIO"; then
    echo "El laboratorio ya está averiado. Para arreglarlo paso a paso:"
    echo "  sudo ./ayuda-autoguiada-reparar-502.sh"
    exit 0
fi

systemctl stop "$SERVICIO"
esperar_puerto "$PUERTO_APP" cerrado

codigo=$(codigo_http)
if [[ $codigo != 502 ]]; then
    echo "ERROR: se esperaba un 502 y el laboratorio respondió $codigo." >&2
    exit 1
fi

cat <<EOF
Avería preparada.

Un usuario llama a soporte: «la web $URL/ no carga, me sale un error».
Tu trabajo: averiguar qué pasa y dejarla funcionando otra vez.

Para comprobar el estado en cualquier momento: ./verificar.sh
EOF
