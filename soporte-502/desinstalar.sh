#!/bin/bash
# Retira únicamente lo que instaló el laboratorio: la aplicación, su servicio, el sitio
# de nginx y sus registros. Deja nginx instalado y en el estado en que esté.
# Con "sh desinstalar.sh" se usaría dash, que no entiende la sintaxis de bash.
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

if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: se necesitan permisos administrativos." >&2
        exit 1
    fi
    exec sudo -- /bin/bash "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
fi

ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ORIGEN
# shellcheck source=comun.sh
source "$ORIGEN/comun.sh"

estado=0
hubo_algo=0

# 1. Sitio de nginx (solo si lleva la firma del laboratorio).
if [[ -L "$SITIO_ACTIVO" || -e "$SITIO_DISPONIBLE" ]]; then
    if [[ -e "$SITIO_DISPONIBLE" ]] && ! grep -qF -- "$FIRMA" "$SITIO_DISPONIBLE"; then
        echo "AVISO: $SITIO_DISPONIBLE no es del laboratorio; no se toca." >&2
        estado=1
    else
        hubo_algo=1
        if retirar_sitio; then
            echo "[OK] Se retiró el sitio del laboratorio del puerto $PUERTO."
        else
            echo "AVISO: el sitio se borró, pero nginx seguirá usando el puerto $PUERTO hasta que se recargue." >&2
            estado=1
        fi
    fi
fi

# 2. Servicio de la aplicación (solo si lleva la firma del laboratorio).
if [[ -f "$UNIDAD" ]] && grep -qF -- "$FIRMA" "$UNIDAD"; then
    hubo_algo=1
    systemctl stop "$SERVICIO" 2>/dev/null || true
    rm -f -- "$UNIDAD"
    systemctl daemon-reload
    systemctl reset-failed "$SERVICIO" 2>/dev/null || true
    echo "[OK] Se retiró el servicio $SERVICIO."
fi

# 3. Aplicación (solo si el marcador confirma que la instaló el laboratorio).
if [[ -f "$MARCADOR" && ! -L "$DIRECTORIO_APP" ]]; then
    hubo_algo=1
    rm -f -- "$DIRECTORIO_APP/app.py" "$MARCADOR"
    rmdir -- "$DIRECTORIO_APP" 2>/dev/null \
        || echo "AVISO: $DIRECTORIO_APP contiene otros archivos; se conserva." >&2
    echo "[OK] Se retiró la aplicación de $DIRECTORIO_APP."
fi

# 4. Registros del laboratorio (incluidos los rotados por logrotate).
shopt -s nullglob
for registro in "$LOG_ERRORES"* "$LOG_ACCESOS"*; do
    if [[ -f "$registro" && ! -L "$registro" ]]; then
        rm -f -- "$registro"
        hubo_algo=1
    fi
done

if (( ! hubo_algo )); then
    echo "No hay nada del laboratorio que desinstalar."
fi

echo "nginx se ha dejado instalado y en el mismo estado para no afectar otros sitios."
exit "$estado"
