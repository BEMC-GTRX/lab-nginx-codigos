#!/bin/bash
# Ayuda autoguiada para reparar el 502 del laboratorio como lo haría soporte técnico:
# reproducir el error, leer los registros, localizar la causa, arreglarla y comprobarlo.
# Escribe cada comando "como si se tecleara", lo ejecuta y espera Enter antes de seguir.
# Uso: cd lab-nginx-codigos/soporte-502 && sudo ./romper.sh && sudo ./ayuda-autoguiada-reparar-502.sh
# Con "sh ayuda-autoguiada-reparar-502.sh" se usaría dash, que no entiende la sintaxis de bash.
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
# Ruta escapada para los comandos que se ejecutan con eval: una carpeta con espacios
# o caracteres especiales no rompe el comando ni ejecuta nada inesperado.
ORIGEN_Q=$(printf '%q' "$ORIGEN")
VELOCIDAD=0.04   # segundos entre letras; súbelo para teclear más despacio

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: ejecuta la ayuda con sudo: sudo ./ayuda-autoguiada-reparar-502.sh" >&2
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
if systemctl is-active --quiet "$SERVICIO"; then
    echo "El laboratorio no está averiado. Provoca la avería con: sudo ./romper.sh" >&2
    exit 1
fi

# --- Colores para que se lea bien en pantalla ---
VERDE='\e[1;32m'; AMARILLO='\e[1;33m'; AZUL='\e[1;36m'; NORMAL='\e[0m'
PROMPT="$(id -un)@$(hostname -s 2>/dev/null || echo localhost)"

# Muestra un título de sección
titulo() { clear 2>/dev/null || true; echo -e "${AZUL}==== $* ====${NORMAL}\n"; }

# Muestra una explicación (en amarillo, como comentario)
explica() { echo -e "${AMARILLO}# $*${NORMAL}"; }

# Teclea el comando letra a letra, lo ejecuta y espera Enter
ejecuta() {
    local cmd="$1"
    echo -ne "${VERDE}${PROMPT}${NORMAL}:${AZUL}~${NORMAL}# "
    for (( i=0; i<${#cmd}; i++ )); do
        echo -n "${cmd:$i:1}"
        sleep "$VELOCIDAD"
    done
    echo
    eval "$cmd" || true    # || true: si un comando "falla" a propósito, la ayuda sigue
    echo
    read -rp "↵ Enter para continuar..." _ || true
    echo
}

# ------------------------------------------------------------------
titulo "Paso 1: reproducir el problema"
explica "Un usuario dice que la web no carga. Lo primero: ver el error con nuestros ojos."
explica "curl -I muestra solo la respuesta del servidor, sin la página:"
ejecuta "curl -I $URL/"
explica "502 Bad Gateway: nginx responde, pero no consigue hablar con la aplicación de detrás."
read -rp "↵ Enter para continuar..." _ || true

# ------------------------------------------------------------------
titulo "Paso 2: ¿funciona nginx?"
ejecuta "systemctl is-active nginx"
explica "nginx está en marcha: el 502 lo genera él. El problema está detrás de nginx."
read -rp "↵ Enter para continuar..." _ || true

# ------------------------------------------------------------------
titulo "Paso 3: leer el registro de errores de nginx"
explica "nginx anota en su registro de errores por qué no pudo responder:"
ejecuta "tail -n 3 $LOG_ERRORES"
explica "«connect() failed (111: Connection refused)»: nginx intentó conectar con"
explica "la aplicación (upstream) en 127.0.0.1:$PUERTO_APP y nadie contestó."
read -rp "↵ Enter para continuar..." _ || true

# ------------------------------------------------------------------
titulo "Paso 4: ¿a dónde envía nginx las peticiones?"
explica "proxy_pass indica a qué aplicación pasa nginx cada petición:"
ejecuta "grep -n proxy_pass $SITIO_ACTIVO"
explica "nginx -t comprueba que la configuración es válida:"
ejecuta "nginx -t"
explica "La configuración está bien y apunta a 127.0.0.1:$PUERTO_APP. ¿Hay algo escuchando ahí?"
read -rp "↵ Enter para continuar..." _ || true

# ------------------------------------------------------------------
titulo "Paso 5: ¿quién escucha en el puerto $PUERTO_APP?"
explica "ss -ltnp lista los programas que esperan conexiones en un puerto:"
ejecuta "ss -ltnp 'sport = :$PUERTO_APP'"
explica "Solo sale la cabecera: ningún programa escucha en el $PUERTO_APP. La aplicación está caída."
read -rp "↵ Enter para continuar..." _ || true

# ------------------------------------------------------------------
titulo "Paso 6: estado del servicio de la aplicación"
ejecuta "systemctl status $SERVICIO --no-pager"
explica "inactive (dead): el servicio está parado. Su diario muestra cuándo se paró:"
ejecuta "journalctl -u $SERVICIO -n 5 --no-pager"

# ------------------------------------------------------------------
titulo "Paso 7: arreglarlo, arrancar la aplicación"
ejecuta "systemctl start $SERVICIO"
# Se espera a que la aplicación abra el puerto antes de enseñarlo (no se muestra).
esperar_puerto "$PUERTO_APP" abierto || true
ejecuta "systemctl is-active $SERVICIO"
explica "Ahora sí hay alguien escuchando en el $PUERTO_APP:"
ejecuta "ss -ltnp 'sport = :$PUERTO_APP'"

# ------------------------------------------------------------------
titulo "Paso 8: comprobar que el usuario ya puede entrar"
ejecuta "curl -I $URL/"
ejecuta "$ORIGEN_Q/verificar.sh"

# ------------------------------------------------------------------
titulo "¡Listo! Resumen del diagnóstico"
explica "1. Reproducir el error:            curl -I  -> 502 Bad Gateway"
explica "2. ¿Funciona nginx?                systemctl is-active nginx -> active"
explica "3. Registro de errores:            Connection refused hacia 127.0.0.1:$PUERTO_APP"
explica "4. Configuración:                  proxy_pass correcto, nginx -t sin errores"
explica "5. Puerto de la aplicación:        nadie escucha en el $PUERTO_APP"
explica "6. Servicio de la aplicación:      inactive (dead)"
explica "7. Solución:                       systemctl start $SERVICIO"
explica "8. Comprobación:                   curl -I -> 200 OK"
echo
explica "En un caso real, antes de cerrar la incidencia averigua también por qué se paró"
explica "(journalctl) para que no vuelva a pasar."
