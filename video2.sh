#!/bin/bash
# Demo para grabar el vídeo 2: personalizar el index de nginx para el lab de códigos HTTP.
# Escribe cada comando "como si se tecleara", lo ejecuta y espera Enter antes de seguir.
# Uso: cd /root/lab-nginx-codigos && sudo ./video2.sh
# Con "sh video2.sh" se usaría dash, que no entiende la sintaxis de bash.
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

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=comun.sh
source "$LAB/comun.sh"
# Ruta escapada para los comandos que se ejecutan con eval: una carpeta con espacios
# o caracteres especiales no rompe el comando ni ejecuta nada inesperado.
LAB_Q=$(printf '%q' "$LAB")
URL="http://localhost:$PUERTO"
VELOCIDAD=0.04   # segundos entre letras; súbelo para teclear más despacio

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: ejecuta la demo con sudo: sudo ./video2.sh" >&2
    exit 1
fi

# Protección: si ya existe la copia, la demo ya se ejecutó y la sobrescribiríamos
# con el index del lab (perdiendo la página original). Hay que reiniciar primero.
if [[ -e "$WEB/index.html.bak-apache" ]]; then
    echo "ERROR: $WEB/index.html.bak-apache ya existe: la demo ya se ejecutó."
    echo "Restaura el estado con ./desinstalar.sh antes de grabar otra toma."
    exit 1
fi
# Si el laboratorio ya está instalado, la "copia de seguridad" sería la página del
# laboratorio y desinstalar.sh nunca podría restaurar la original.
if [[ -e "$MARCADOR" ]] || cmp -s "$WEB/index.html" "$LAB/index.html"; then
    echo "ERROR: el laboratorio ya está instalado. Ejecuta ./desinstalar.sh antes de grabar."
    exit 1
fi

# Comprobaciones previas, antes de enseñar nada en pantalla.
comprobar_puerto
for directorio in "$WEB" "$WEB/carpeta" "$WEB/privado"; do
    comprobar_directorio "$directorio"
done
comprobar_rutas_ajenas

# Si la demo se interrumpe después de la copia de seguridad, se deja el marcador para
# que ./desinstalar.sh pueda restaurar el estado (y se pueda grabar otra toma).
dejar_marcador() {
    if [[ -e "$WEB/index.html.bak-apache" ]] || cmp -s "$WEB/index.html" "$LAB/index.html"; then
        escribir_marcador || true
    fi
}
trap dejar_marcador EXIT

# --- Colores para que se lea bien en el vídeo ---
VERDE='\e[1;32m'; AMARILLO='\e[1;33m'; AZUL='\e[1;36m'; NORMAL='\e[0m'

# Muestra un título de sección
titulo() { clear 2>/dev/null || true; echo -e "${AZUL}==== $* ====${NORMAL}\n"; }

# Muestra una explicación (en amarillo, como comentario)
explica() { echo -e "${AMARILLO}# $*${NORMAL}"; }

# Teclea el comando letra a letra, lo ejecuta y espera Enter
ejecuta() {
    local cmd="$1"
    echo -ne "${VERDE}root@parrot${NORMAL}:${AZUL}~${NORMAL}# "
    for (( i=0; i<${#cmd}; i++ )); do
        echo -n "${cmd:$i:1}"
        sleep "$VELOCIDAD"
    done
    echo
    eval "$cmd" || true    # || true: si un comando "falla" a propósito, la demo sigue
    echo
    read -rp "↵ Enter para continuar..." _ || true
    echo
}

# ------------------------------------------------------------------
titulo "Parte 2: personalizar el index de nginx"
explica "En el vídeo anterior instalamos nginx. Comprobamos que sigue funcionando:"
ejecuta "systemctl is-active nginx"

# ------------------------------------------------------------------
titulo "Paso 1: publicar un sitio en el puerto 8080"
explica "Usamos el puerto 8080 para no chocar con otros sitios del puerto 80."
explica "Este es el sitio del laboratorio; solo escucha en localhost:"
ejecuta "cat $LAB_Q/nginx/$SITIO"
explica "Lo copiamos a sites-available y lo activamos con un enlace en sites-enabled:"
ejecuta "install -m 644 $LAB_Q/nginx/$SITIO $SITIO_DISPONIBLE"
ejecuta "ln -sfn $SITIO_DISPONIBLE $SITIO_ACTIVO"
explica "Antes de recargar, nginx -t comprueba que la configuración es válida:"
ejecuta "nginx -t && systemctl reload nginx"
# Si el sitio no quedó bien, se retira: una configuración rota impediría el próximo
# arranque de nginx y de todos sus sitios.
if ! nginx -t -q 2>/dev/null || ! esperar_puerto; then
    retirar_sitio || true
    echo "ERROR: el sitio no se pudo publicar; se retiró de nginx." >&2
    exit 1
fi
explica "¿Qué página nos está sirviendo ahora mismo? Miramos su título:"
ejecuta "curl -s $URL | grep -o '<title>.*</title>'"

# ------------------------------------------------------------------
titulo "Paso 2: ¿dónde están los archivos de la web?"
explica "nginx sirve los archivos de la carpeta indicada en 'root' de su configuración:"
ejecuta "grep -E '^\s*(root|index)' /etc/nginx/sites-enabled/$SITIO"
explica "Busca index.html primero. Veamos qué hay en /var/www/html:"
ejecuta "ls -l $WEB"
explica "Ese index.html es la página por defecto de Apache. ¡La vamos a sustituir!"
read -rp "↵ Enter para continuar..." _ || true

# ------------------------------------------------------------------
titulo "Paso 3: copia de seguridad (antes de cambiar nada)"
explica "cp -p copia el archivo conservando permisos y fechas."
ejecuta "cp -p $WEB/index.html $WEB/index.html.bak-apache"
ejecuta "ls -l $WEB"

# ------------------------------------------------------------------
titulo "Paso 4: instalar nuestro index.html del laboratorio"
explica "Este es el index que preparamos (vemos el principio):"
ejecuta "head -n 25 $LAB_Q/index.html"
explica "Lo copiamos con permisos 644: el dueño escribe, todos pueden leer (también nginx)."
ejecuta "install -m 644 $LAB_Q/index.html $WEB/index.html"
# Marcador (no se muestra en pantalla) para que ./desinstalar.sh pueda limpiar la demo.
escribir_marcador
ejecuta "curl -s $URL | grep -o '<title>.*</title>'"

# ------------------------------------------------------------------
titulo "Paso 5: preparar rutas para practicar códigos de estado"
explica "Una carpeta CON index: al pedirla sin '/' final, nginx responde 301."
ejecuta "mkdir -p $WEB/carpeta && echo '<h1>Has llegado a /carpeta/</h1>' > $WEB/carpeta/index.html"
explica "Una carpeta SIN index: nginx no lista su contenido y responde 403."
ejecuta "mkdir -p $WEB/privado"
explica "Un archivo que solo puede leer root (permisos 600): nginx (www-data) recibe 403."
ejecuta "echo 'secreto' > $WEB/secreto.txt && chmod 600 $WEB/secreto.txt"
ejecuta "ls -l $WEB"

# ------------------------------------------------------------------
titulo "Paso 6: comprobación rápida"
explica "Pedimos cada ruta y mostramos solo el código de estado:"
ejecuta "for r in / /no-existe.html /carpeta /privado/ /secreto.txt; do echo \"\$r -> \$(curl -s -o /dev/null -w '%{http_code}' $URL\$r)\"; done"

# ------------------------------------------------------------------
titulo "¡Listo!"
explica "Abre el navegador en $URL para ver la guía del laboratorio."
explica "En el próximo vídeo analizaremos cada código de estado con curl."
