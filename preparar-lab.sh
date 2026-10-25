#!/usr/bin/env bash
# Prepara el laboratorio de códigos de estado HTTP en nginx.
# Uso: sudo ./preparar-lab.sh
set -euo pipefail

# nginx vive en /usr/sbin; con "su" (sin "-") o algunos sudo esa ruta no está en PATH.
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

readonly WEB=/var/www/html
readonly ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MARCADOR="$WEB/.lab-nginx-codigos"
readonly PUERTO=8080
readonly SITIO=lab-nginx-codigos.conf
readonly SITIO_DISPONIBLE="/etc/nginx/sites-available/$SITIO"
readonly SITIO_ACTIVO="/etc/nginx/sites-enabled/$SITIO"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: ejecuta este script con sudo: sudo ./preparar-lab.sh" >&2
    exit 1
fi

for comando in nginx curl systemctl install ss; do
    if ! command -v "$comando" >/dev/null 2>&1; then
        echo "ERROR: falta el comando '$comando'. Ejecuta primero ./instalar.sh" >&2
        exit 1
    fi
done

# Si otro programa ya usa el puerto, se aborta antes de modificar nada.
if [[ ! -L "$SITIO_ACTIVO" ]] && ss -Hltn "sport = :$PUERTO" | grep -q .; then
    echo "ERROR: el puerto $PUERTO ya está en uso por otro programa." >&2
    exit 1
fi

install -d -m 755 "$WEB"

# 1. Copia de seguridad del index.html anterior (solo la primera vez, para no pisarla)
if [[ -f "$WEB/index.html" && ! -f "$WEB/index.html.bak-apache" ]]; then
    cp -p "$WEB/index.html" "$WEB/index.html.bak-apache"
    echo "[+] Copia de seguridad: $WEB/index.html.bak-apache"
fi

# 2. Instalar el nuevo index (644 = el dueño escribe, todos leen)
install -m 644 "$ORIGEN/index.html" "$WEB/index.html"
echo "[+] index.html del laboratorio instalado"

# 3. Carpeta CON index -> pedirla sin "/" final provoca un 301
mkdir -p "$WEB/carpeta"
printf '%s\n' "<h1>Has llegado a /carpeta/ tras la redireccion 301</h1>" > "$WEB/carpeta/index.html"
chmod 644 "$WEB/carpeta/index.html"

# 4. Carpeta SIN index -> 403 (nginx no lista carpetas por defecto)
mkdir -p "$WEB/privado"

# 5. Archivo que www-data no puede leer -> 403 (600 = solo root lee y escribe)
printf '%s\n' "Si lees esto, los permisos no estan bien puestos" > "$WEB/secreto.txt"
chmod 600 "$WEB/secreto.txt"
printf 'Instalado por lab-nginx-codigos.\n' > "$MARCADOR"
chmod 644 "$MARCADOR"
echo "[+] carpeta/, privado/ y secreto.txt creados"

# 6. Publicar el sitio del laboratorio en el puerto 8080
install -m 644 "$ORIGEN/nginx/$SITIO" "$SITIO_DISPONIBLE"
ln -sfn "$SITIO_DISPONIBLE" "$SITIO_ACTIVO"
if ! nginx -t -q; then
    # Se retira el sitio para no dejar nginx con una configuración rota.
    rm -f -- "$SITIO_ACTIVO" "$SITIO_DISPONIBLE"
    echo "ERROR: la configuración de nginx no es válida; se retiró el sitio del laboratorio." >&2
    exit 1
fi
echo "[+] Sitio publicado en $SITIO_ACTIVO"

# 7. Arrancar nginx si está parado o recargarlo para aplicar el sitio nuevo
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
else
    systemctl start nginx
fi
echo "[+] nginx: $(systemctl is-active nginx)"

# 8. Verificación: si alguna ruta no responde con el código esperado, el script falla
echo
bash "$ORIGEN/verificar.sh"

echo
echo "Laboratorio disponible en http://localhost:$PUERTO/"
