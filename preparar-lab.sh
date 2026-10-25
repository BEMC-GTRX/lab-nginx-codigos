#!/bin/bash
# Prepara el laboratorio de códigos de estado HTTP en nginx.
# Uso: sudo ./preparar-lab.sh
# Con "sh preparar-lab.sh" se usaría dash, que no entiende la sintaxis de bash.
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
# shellcheck source=comun.sh
source "$ORIGEN/comun.sh"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: ejecuta este script con sudo: sudo ./preparar-lab.sh" >&2
    exit 1
fi

for comando in nginx curl systemctl install ss sha256sum; do
    if ! command -v "$comando" >/dev/null 2>&1; then
        echo "ERROR: falta el comando '$comando'. Ejecuta primero ./instalar.sh" >&2
        exit 1
    fi
done

# Comprobaciones previas: si algo no cuadra, se aborta antes de modificar nada.
comprobar_puerto
for directorio in "$WEB" "$WEB/carpeta" "$WEB/privado"; do
    comprobar_directorio "$directorio"
done
comprobar_rutas_ajenas

# Si index.html fue personalizado y ya hay una copia distinta, sobrescribirlo lo perdería.
if [[ -f "$WEB/index.html" ]] && ! cmp -s "$WEB/index.html" "$ORIGEN/index.html" \
    && [[ -e "$WEB/index.html.bak-apache" ]] \
    && ! cmp -s "$WEB/index.html" "$WEB/index.html.bak-apache"; then
    echo "ERROR: $WEB/index.html fue modificado y ya existe una copia index.html.bak-apache distinta." >&2
    echo "Guarda tu página en otro sitio antes de instalar el laboratorio." >&2
    exit 1
fi

# Si algo falla o se interrumpe (Ctrl-C, cierre de la sesión SSH) después de publicar
# el sitio, se retira para no dejar en nginx una configuración sin verificar que podría
# impedir su próximo arranque (y el de los demás sitios). Con una señal, $? vale 0 en
# la trampa EXIT, por eso se usa la variable "completado" en lugar del código de salida.
sitio_publicado=0
completado=0
temporal=""
limpiar() {
    if [[ -n "$temporal" ]]; then
        rm -f -- "$temporal"
    fi
    if (( ! completado && sitio_publicado )); then
        retirar_sitio || true
        echo "ERROR: la instalación falló; se retiró el sitio del laboratorio de nginx." >&2
    fi
}
trap limpiar EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Crea un archivo con contenido y permisos dados. install no sigue enlaces simbólicos
# en el destino (lo reemplaza), a diferencia de "printf > archivo".
crear_archivo() {
    local permisos=$1 destino=$2 contenido=$3
    printf '%s\n' "$contenido" > "$temporal"
    install -m "$permisos" "$temporal" "$destino"
}
temporal=$(mktemp)

# Solo se crea si no existe: así no se cambian los permisos de un /var/www/html ajeno.
[[ -d "$WEB" ]] || install -d -m 755 "$WEB"

# 1. Copia de seguridad del index.html anterior (solo la primera vez, para no pisarla)
if [[ -f "$WEB/index.html" && ! -e "$WEB/index.html.bak-apache" ]] \
    && ! cmp -s "$WEB/index.html" "$ORIGEN/index.html"; then
    cp -p -- "$WEB/index.html" "$WEB/index.html.bak-apache"
    echo "[+] Copia de seguridad: $WEB/index.html.bak-apache"
fi

# 2. Instalar el nuevo index (644 = el dueño escribe, todos leen)
install -m 644 "$ORIGEN/index.html" "$WEB/index.html"
echo "[+] index.html del laboratorio instalado"

# 3. Carpeta CON index -> pedirla sin "/" final provoca un 301
install -d -m 755 "$WEB/carpeta"
crear_archivo 644 "$WEB/carpeta/index.html" "<h1>Has llegado a /carpeta/ tras la redireccion 301</h1>"

# 4. Carpeta SIN index -> 403 (nginx no lista carpetas por defecto)
install -d -m 755 "$WEB/privado"

# 5. Archivo que www-data no puede leer -> 403 (600 = solo root lee y escribe)
crear_archivo 600 "$WEB/secreto.txt" "Si lees esto, los permisos no estan bien puestos"
escribir_marcador
echo "[+] carpeta/, privado/ y secreto.txt creados"

# 6. Publicar el sitio del laboratorio en el puerto 8080
sitio_publicado=1
install -m 644 "$ORIGEN/nginx/$SITIO" "$SITIO_DISPONIBLE"
ln -sfn "$SITIO_DISPONIBLE" "$SITIO_ACTIVO"
if ! nginx -t -q; then
    echo "ERROR: la configuración de nginx no es válida." >&2
    exit 1
fi
echo "[+] Sitio publicado en $SITIO_ACTIVO"

# 7. Recargar nginx para aplicar el sitio nuevo (afecta a todos sus sitios, que no cambian),
#    o arrancarlo si está parado: el laboratorio necesita que nginx esté en marcha.
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
else
    echo "[!] nginx estaba parado; se arranca (también arrancan sus otros sitios)."
    systemctl start nginx
fi
esperar_puerto
echo "[+] nginx: $(systemctl is-active nginx)"

# 8. Verificación: si alguna ruta no responde con el código esperado, el script falla
echo
BASE_URL="http://localhost:$PUERTO" bash "$ORIGEN/verificar.sh"
completado=1

avisar_sitio_default
echo
echo "Laboratorio disponible en http://localhost:$PUERTO/"
