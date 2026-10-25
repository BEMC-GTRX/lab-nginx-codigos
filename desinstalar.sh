#!/usr/bin/env bash
# Retira únicamente los archivos identificados como parte del laboratorio.
set -euo pipefail

# nginx vive en /usr/sbin; con "su" (sin "-") o algunos sudo esa ruta no está en PATH.
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

readonly WEB=/var/www/html
readonly MARCADOR="$WEB/.lab-nginx-codigos"
readonly SITIO=lab-nginx-codigos.conf

if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: se necesitan permisos administrativos." >&2
        exit 1
    fi
    exec sudo -- "$0" "$@"
fi

if [[ ! -f "$MARCADOR" ]]; then
    echo "ERROR: no encuentro el marcador del laboratorio; no se borrará nada." >&2
    exit 1
fi

# Son rutas concretas creadas por preparar-lab.sh; nunca se borra /var/www/html.
rm -f -- "$WEB/secreto.txt" "$WEB/carpeta/index.html" "$MARCADOR"
rmdir -- "$WEB/carpeta" "$WEB/privado" 2>/dev/null || true

if [[ -f "$WEB/index.html.bak-apache" ]]; then
    mv -- "$WEB/index.html.bak-apache" "$WEB/index.html"
    echo "[OK] Se restauró la página que existía antes del laboratorio."
else
    rm -f -- "$WEB/index.html"
    echo "[OK] Se retiró la página del laboratorio."
fi

# Retira el sitio del puerto 8080 y recarga nginx solo si la configuración restante es válida.
rm -f -- "/etc/nginx/sites-enabled/$SITIO" "/etc/nginx/sites-available/$SITIO"
if systemctl is-active --quiet nginx && nginx -t -q; then
    systemctl reload nginx
fi
echo "[OK] Se retiró el sitio del laboratorio del puerto 8080."

echo "nginx se ha dejado instalado y en ejecución para no afectar otros sitios."
