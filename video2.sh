#!/usr/bin/env bash
# Demo para grabar el vídeo 2: personalizar el index de nginx para el lab de códigos HTTP.
# Escribe cada comando "como si se tecleara", lo ejecuta y espera Enter antes de seguir.
# Uso: cd /root/lab-nginx-codigos && sudo ./video2.sh
set -euo pipefail

WEB=/var/www/html
LAB="$(cd "$(dirname "$0")" && pwd)"
VELOCIDAD=0.04   # segundos entre letras; súbelo para teclear más despacio

# Protección: si ya existe la copia, la demo ya se ejecutó y la sobrescribiríamos
# con el index del lab (perdiendo la página original). Hay que reiniciar primero.
if [[ -e "$WEB/index.html.bak-apache" ]]; then
    echo "ERROR: $WEB/index.html.bak-apache ya existe: la demo ya se ejecutó."
    echo "Reinicia el estado antes de grabar otra toma (ver instrucciones)."
    exit 1
fi

# --- Colores para que se lea bien en el vídeo ---
VERDE='\e[1;32m'; AMARILLO='\e[1;33m'; AZUL='\e[1;36m'; NORMAL='\e[0m'

# Muestra un título de sección
titulo() { clear; echo -e "${AZUL}==== $* ====${NORMAL}\n"; }

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
    read -rp "↵ Enter para continuar..." _
    echo
}

# ------------------------------------------------------------------
titulo "Parte 2: personalizar el index de nginx"
explica "En el vídeo anterior instalamos nginx. Comprobamos que sigue funcionando:"
ejecuta "systemctl is-active nginx"

explica "¿Qué página nos está sirviendo ahora mismo? Miramos su título:"
ejecuta "curl -s http://localhost | grep -o '<title>.*</title>'"

# ------------------------------------------------------------------
titulo "Paso 1: ¿dónde están los archivos de la web?"
explica "nginx sirve los archivos de la carpeta indicada en 'root' de su configuración:"
ejecuta "grep -E '^\s*(root|index)' /etc/nginx/sites-enabled/default"
explica "Busca index.html primero. Veamos qué hay en /var/www/html:"
ejecuta "ls -l $WEB"
explica "Ese index.html es la página por defecto de Apache. ¡La vamos a sustituir!"
read -rp "↵ Enter para continuar..." _

# ------------------------------------------------------------------
titulo "Paso 2: copia de seguridad (antes de cambiar nada)"
explica "cp -p copia el archivo conservando permisos y fechas."
ejecuta "cp -p $WEB/index.html $WEB/index.html.bak-apache"
ejecuta "ls -l $WEB"

# ------------------------------------------------------------------
titulo "Paso 3: instalar nuestro index.html del laboratorio"
explica "Este es el index que preparamos (vemos el principio):"
ejecuta "head -n 25 $LAB/index.html"
explica "Lo copiamos con permisos 644: el dueño escribe, todos pueden leer (también nginx)."
ejecuta "install -m 644 $LAB/index.html $WEB/index.html"
ejecuta "curl -s http://localhost | grep -o '<title>.*</title>'"

# ------------------------------------------------------------------
titulo "Paso 4: preparar rutas para practicar códigos de estado"
explica "Una carpeta CON index: al pedirla sin '/' final, nginx responde 301."
ejecuta "mkdir -p $WEB/carpeta && echo '<h1>Has llegado a /carpeta/</h1>' > $WEB/carpeta/index.html"
explica "Una carpeta SIN index: nginx no lista su contenido y responde 403."
ejecuta "mkdir -p $WEB/privado"
explica "Un archivo que solo puede leer root (permisos 600): nginx (www-data) recibe 403."
ejecuta "echo 'secreto' > $WEB/secreto.txt && chmod 600 $WEB/secreto.txt"
ejecuta "ls -l $WEB"

# ------------------------------------------------------------------
titulo "Paso 5: comprobación rápida"
explica "Pedimos cada ruta y mostramos solo el código de estado:"
ejecuta "for r in / /no-existe.html /carpeta /privado/ /secreto.txt; do echo \"\$r -> \$(curl -s -o /dev/null -w '%{http_code}' http://localhost\$r)\"; done"

# ------------------------------------------------------------------
titulo "¡Listo!"
explica "Abre el navegador en http://localhost para ver la guía del laboratorio."
explica "En el próximo vídeo analizaremos cada código de estado con curl."
