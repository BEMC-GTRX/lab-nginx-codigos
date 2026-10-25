#!/usr/bin/env bash
# Prepara el laboratorio de códigos de estado HTTP en nginx.
# Uso: sudo ./preparar-lab.sh
set -euo pipefail

# nginx vive en /usr/sbin; con "su" (sin "-") o algunos sudo esa ruta no está en PATH.
export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

readonly WEB=/var/www/html
readonly ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MARCADOR="$WEB/.lab-nginx-codigos"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: ejecuta este script con sudo: sudo ./preparar-lab.sh" >&2
    exit 1
fi

for comando in nginx curl systemctl install; do
    if ! command -v "$comando" >/dev/null 2>&1; then
        echo "ERROR: falta el comando '$comando'. Ejecuta primero ./instalar.sh" >&2
        exit 1
    fi
done

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

# 6. Arrancar nginx si está parado
systemctl start nginx
echo "[+] nginx: $(systemctl is-active nginx)"

# 7. Verificación: cada ruta con el código que esperamos
echo
echo "Ruta                               Esperado  Obtenido"
comprobar() {
    local esperado=$1; shift
    local obtenido
    obtenido=$(curl -s -o /dev/null -w '%{http_code}' "$@")
    printf '%-34s %-9s %s\n' "${*: -1}" "$esperado" "$obtenido"
}
comprobar 200 http://localhost/
comprobar 404 http://localhost/no-existe.html
comprobar 301 http://localhost/carpeta
comprobar 403 http://localhost/privado/
comprobar 403 http://localhost/secreto.txt
comprobar 405 -X POST http://localhost/
comprobar 206 -r 0-99 http://localhost/
comprobar 416 -r 999999- http://localhost/
comprobar 400 -H "Host:" http://localhost/

echo
echo "Laboratorio disponible en http://localhost/"
