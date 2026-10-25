#!/bin/bash
# Retira únicamente los archivos identificados como parte del laboratorio.
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

# 1. El sitio tiene un nombre fijo del laboratorio: se retira siempre, aunque falte el marcador.
if [[ -e "$SITIO_ACTIVO" || -L "$SITIO_ACTIVO" || -e "$SITIO_DISPONIBLE" ]]; then
    hubo_algo=1
    if retirar_sitio; then
        echo "[OK] Se retiró el sitio del laboratorio del puerto $PUERTO."
    else
        echo "AVISO: el sitio se borró, pero nginx seguirá usando el puerto $PUERTO hasta que se recargue." >&2
        estado=1
    fi
fi

# 2. Archivos de /var/www/html: solo si el marcador confirma que los instaló el laboratorio.
if [[ -f "$MARCADOR" ]]; then
    hubo_algo=1
    for directorio in "$WEB" "$WEB/carpeta" "$WEB/privado"; do
        comprobar_directorio "$directorio"
    done
    rm -f -- "$WEB/secreto.txt" "$WEB/carpeta/index.html"
    rmdir -- "$WEB/carpeta" "$WEB/privado" 2>/dev/null || true

    # Solo se toca index.html si sigue siendo exactamente el que instaló el laboratorio.
    if (cd "$WEB" && sha256sum --status -c "$MARCADOR" 2>/dev/null); then
        # Si la copia es la propia página del laboratorio (no había página original),
        # restaurarla dejaría el laboratorio instalado: se borran ambas.
        if [[ -f "$WEB/index.html.bak-apache" ]] \
            && ! cmp -s "$WEB/index.html.bak-apache" "$ORIGEN/index.html"; then
            mv -- "$WEB/index.html.bak-apache" "$WEB/index.html"
            echo "[OK] Se restauró la página que existía antes del laboratorio."
        else
            rm -f -- "$WEB/index.html.bak-apache"
            rm -f -- "$WEB/index.html"
            echo "[OK] Se retiró la página del laboratorio."
        fi
    else
        echo "AVISO: $WEB/index.html se modificó después de instalar el laboratorio; se conserva." >&2
        if [[ -f "$WEB/index.html.bak-apache" ]]; then
            echo "AVISO: la página anterior sigue en $WEB/index.html.bak-apache." >&2
        fi
    fi

    # El marcador se borra al final: si algo falla antes, se puede repetir la desinstalación.
    rm -f -- "$MARCADOR"
    echo "[OK] Se retiraron carpeta/, privado/ y secreto.txt."
fi

if (( ! hubo_algo )); then
    echo "No hay nada del laboratorio que desinstalar."
fi

echo "nginx se ha dejado instalado y en ejecución para no afectar otros sitios."
exit "$estado"
