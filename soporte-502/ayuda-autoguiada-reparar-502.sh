#!/bin/bash
# Ayuda autoguiada para reparar el 502 del laboratorio como lo haría soporte técnico:
# el técnico solo conoce la URL que da el usuario. Primero hace un reconocimiento
# completo (sin cambiar nada) siguiendo el camino de la petición; cada dato que usa
# lo descubre en el paso anterior. Después diagnostica, repara, verifica y cierra.
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
# comun.sh solo se usa para las comprobaciones previas y para la URL del aviso del
# usuario. Los demás datos (archivo de nginx, registro, puerto y servicio de la
# aplicación) los descubre la propia ayuda, como haría el técnico.
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

# Espera Enter
pausa() { read -rp "↵ Enter para continuar..." _ || true; }

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
    pausa
    echo
}

# Si un descubrimiento falla, la ayuda no puede seguir el razonamiento: se detiene.
no_encontrado() {
    echo "ERROR: no se encontró $1. ¿Se ha modificado el laboratorio?" >&2
    exit 1
}

# ==================================================================
# FASE 1: RECONOCIMIENTO (solo se mira, no se cambia nada)
# ==================================================================
titulo "Fase 1 · Reconocimiento"
explica "Un usuario llama: «la web $URL/ no carga, me sale un error»."
explica "Es TODO lo que sabemos. No sabemos qué servidor hay, ni qué aplicación, ni dónde"
explica "están sus registros. Seguiremos el camino de la petición, paso a paso, y cada dato"
explica "que usemos lo sacaremos del paso anterior. En esta fase no cambiamos nada."
pausa

# ------------------------------------------------------------------
titulo "Paso 1: reproducir el problema"
explica "Lo primero es ver el error con nuestros propios ojos."
explica "curl -I muestra solo la respuesta del servidor (las cabeceras), sin la página."
explica "Fíjate en la primera línea (el código) y en la cabecera Server:"
ejecuta "curl -I $URL/"
explica "502 Bad Gateway: quien responde hace de intermediario (proxy) y no ha conseguido"
explica "respuesta de lo que tiene detrás. Server: nginx nos dice quién es el intermediario."
pausa

# ------------------------------------------------------------------
titulo "Paso 2: ¿qué programa atiende el puerto $PUERTO?"
explica "La cabecera Server se puede falsear: lo confirmamos en el sistema."
explica "ss -ltnp lista los programas que esperan conexiones (-l) TCP (-t) en cada puerto,"
explica "con números (-n) y el nombre del proceso (-p). Fíjate en la columna Process:"
ejecuta "ss -ltnp 'sport = :$PUERTO'"
explica "Confirmado: es nginx. Y está en marcha, porque es él quien nos devuelve el 502."
pausa

# ------------------------------------------------------------------
titulo "Paso 3: ¿qué configuración de nginx usa el puerto $PUERTO?"
explica "Los sitios ACTIVOS de nginx están en /etc/nginx/sites-enabled/ (son enlaces a"
explica "sites-available/). Buscamos cuál escucha (listen) en el $PUERTO."
explica "grep -R busca dentro de todos los archivos y, a diferencia de -r, sigue los enlaces;"
explica "-n muestra el número de línea:"
ejecuta "grep -Rn 'listen.*$PUERTO' /etc/nginx/sites-enabled/"
CONF=$(grep -Rl "listen.*$PUERTO" /etc/nginx/sites-enabled/ 2>/dev/null | head -n 1) || true
[[ -n "$CONF" ]] || no_encontrado "el sitio de nginx del puerto $PUERTO"
CONF_Q=$(printf '%q' "$CONF")
explica "Ya sabemos qué archivo leer: $CONF"
pausa

# ------------------------------------------------------------------
titulo "Paso 4: ¿qué hace ese sitio?"
explica "Dos directivas nos interesan:"
explica "  error_log  -> dónde anota nginx los errores de este sitio."
explica "  proxy_pass -> a qué aplicación le pasa nginx cada petición."
ejecuta "grep -nE 'error_log|proxy_pass' $CONF_Q"
LOG=$(grep -oP '^\s*error_log\s+\K[^\s;]+' "$CONF" | head -n 1) || true
DESTINO=$(grep -oP '^\s*proxy_pass\s+https?://\K[^\s;/]+' "$CONF" | head -n 1) || true
[[ -n "$LOG" ]] || no_encontrado "la directiva error_log en $CONF"
[[ -n "$DESTINO" ]] || no_encontrado "la directiva proxy_pass en $CONF"
PUERTO_DESTINO=${DESTINO##*:}
LOG_Q=$(printf '%q' "$LOG")
explica "Dos datos nuevos: el registro está en $LOG"
explica "y nginx pasa las peticiones a $DESTINO (la aplicación, en el puerto $PUERTO_DESTINO)."
explica "Antes de culpar a la aplicación, nginx -t comprueba que la configuración es válida:"
ejecuta "nginx -t"
pausa

# ------------------------------------------------------------------
titulo "Paso 5: ¿qué dice el registro de errores?"
explica "Leemos las últimas líneas del registro que encontramos en el paso 4."
explica "Fíjate en el mensaje del error, en el upstream (a quién intentó conectar) y en la hora:"
ejecuta "tail -n 3 $LOG_Q"
explica "«connect() failed (111: Connection refused)»: nginx llamó a $DESTINO y nadie"
explica "contestó. Apunta la HORA del error: la usaremos en el paso 9."
pausa

# ------------------------------------------------------------------
titulo "Paso 6: ¿hay alguien escuchando en el puerto $PUERTO_DESTINO?"
explica "Mismo comando que en el paso 2, ahora con el puerto que descubrimos en el paso 4:"
ejecuta "ss -ltnp 'sport = :$PUERTO_DESTINO'"
explica "Si solo aparece la cabecera, ningún programa escucha en el $PUERTO_DESTINO:"
explica "la aplicación está caída. Pero ¿qué aplicación? Aún no sabemos ni cómo se llama."
pausa

# ------------------------------------------------------------------
titulo "Paso 7: ¿qué servicios propios tiene este servidor?"
explica "Como la aplicación está parada, ss no puede decirnos su nombre. Hay que buscarla."
explica "Buscar '$PUERTO_DESTINO' en todo el disco da muchos falsos positivos. Mejor: las"
explica "aplicaciones de la empresa suelen ser servicios de systemd instalados a mano, y esos"
explica "viven en /etc/systemd/system/ (los de los paquetes están en /usr/lib/systemd/system/)."
ejecuta "ls /etc/systemd/system/*.service"
# Se busca, entre esos servicios, cuál ejecuta un programa que usa el puerto descubierto.
# Es el mismo razonamiento que hará el técnico en los pasos 8 y 9.
UNIDAD_SOSPECHOSA=""
PROGRAMA=""
for unidad in /etc/systemd/system/*.service; do
    programa=$(grep -oP '^ExecStart=.*?\K/\S+\.(py|sh|js|rb|pl)\b' "$unidad" 2>/dev/null | head -n 1) || true
    if [[ -n "$programa" && -f "$programa" ]] && grep -qw -- "$PUERTO_DESTINO" "$programa"; then
        UNIDAD_SOSPECHOSA=$unidad
        PROGRAMA=$programa
        break
    fi
done
[[ -n "$UNIDAD_SOSPECHOSA" ]] || no_encontrado "un servicio cuyo programa use el puerto $PUERTO_DESTINO"
NOMBRE_SERVICIO=$(basename "$UNIDAD_SOSPECHOSA" .service)
UNIDAD_Q=$(printf '%q' "$UNIDAD_SOSPECHOSA")
PROGRAMA_Q=$(printf '%q' "$PROGRAMA")
explica "La mayoría son del propio sistema (red, hora, pantalla...). El nombre que destaca"
explica "por parecer una aplicación web es: $NOMBRE_SERVICIO. Es nuestro sospechoso."
pausa

# ------------------------------------------------------------------
titulo "Paso 8: ¿qué programa ejecuta el servicio sospechoso?"
explica "En una unidad de systemd, la línea ExecStart dice qué programa se arranca:"
ejecuta "grep ExecStart $UNIDAD_Q"
explica "El servicio $NOMBRE_SERVICIO ejecuta $PROGRAMA."
pausa

# ------------------------------------------------------------------
titulo "Paso 9: confirmar la sospecha"
explica "Una sospecha no es una prueba. ¿Ese programa usa el puerto $PUERTO_DESTINO?"
explica "grep -w busca la palabra exacta (así 8001 no coincide con 18001):"
ejecuta "grep -nw $PUERTO_DESTINO $PROGRAMA_Q"
explica "Confirmado: $NOMBRE_SERVICIO es la aplicación que nginx necesita. Miramos su estado"
explica "(systemctl status) y su historial (journalctl -u). Compara la hora del 'Stopped'"
explica "con la del error del paso 5:"
ejecuta "systemctl status $NOMBRE_SERVICIO --no-pager"
ejecuta "journalctl -u $NOMBRE_SERVICIO -n 5 --no-pager"
explica "inactive (dead) y un 'Stopped' limpio: el servicio no se estrelló, alguien o algo lo"
explica "paró. Y lo hizo justo cuando empezaron los errores: los dos hechos están relacionados."
pausa

# ==================================================================
# FASE 2: DIAGNÓSTICO
# ==================================================================
titulo "Fase 2 · Diagnóstico"
explica "Lo que hemos descubierto y con qué comando (cada dato salió del anterior):"
explica "  1. [curl -I, ss]           El usuario ve 502 y quien responde es nginx."
explica "  2. [grep -R]               Sitio activo del puerto $PUERTO: $CONF"
explica "  3. [proxy_pass]            nginx pasa las peticiones a $DESTINO"
explica "  4. [error_log + tail]      Connection refused hacia $DESTINO"
explica "  5. [ss]                    Nadie escucha en el puerto $PUERTO_DESTINO."
explica "  6. [ExecStart + grep -w]   El programa de ese puerto es $PROGRAMA"
explica "  7. [systemctl, journalctl] Lo arranca $NOMBRE_SERVICIO, que está parado."
echo
explica "Conclusión: nginx funciona bien. La causa del 502 es que el servicio"
explica "$NOMBRE_SERVICIO está parado."
pausa

# ==================================================================
# FASE 3: SOLUCIÓN (el primer y único cambio en el sistema)
# ==================================================================
titulo "Fase 3 · Solución"
explica "Ahora sí cambiamos algo, y solo lo necesario: arrancar el servicio."
ejecuta "systemctl start $NOMBRE_SERVICIO"
# Se espera a que la aplicación abra el puerto antes de enseñarlo (no se muestra).
esperar_puerto "$PUERTO_DESTINO" abierto || true
ejecuta "systemctl is-active $NOMBRE_SERVICIO"

# ==================================================================
# FASE 4: VERIFICACIÓN
# ==================================================================
titulo "Fase 4 · Verificación"
explica "Comprobamos cada eslabón, de dentro hacia fuera. ¿Escucha ya alguien en el $PUERTO_DESTINO?"
ejecuta "ss -ltnp 'sport = :$PUERTO_DESTINO'"
explica "¿Y qué ve ahora el usuario?"
ejecuta "curl -I $URL/"
ejecuta "$ORIGEN_Q/verificar.sh"

# ==================================================================
# FASE 5: CIERRE DE LA INCIDENCIA
# ==================================================================
titulo "Fase 5 · Cierre de la incidencia"
explica "Síntoma:   $URL/ respondía 502 Bad Gateway."
explica "Causa:     el servicio $NOMBRE_SERVICIO (puerto $PUERTO_DESTINO) estaba parado."
explica "Solución:  systemctl start $NOMBRE_SERVICIO"
explica "Prueba:    curl -I $URL/ -> 200 OK"
echo
explica "Antes de cerrar, un buen técnico deja recomendaciones para que no vuelva a pasar:"
ejecuta "systemctl is-enabled $NOMBRE_SERVICIO"
explica "«static»: la unidad no tiene sección [Install], así que no se arranca sola al"
explica "encender el equipo y «systemctl enable» no sirve con ella (en el laboratorio es a"
explica "propósito). En un servidor real, el informe recomendaría:"
explica "  - Averiguar quién o qué paró el servicio (journalctl, historial de comandos)."
explica "  - Añadir a la unidad una sección [Install] y habilitarla con systemctl enable."
explica "  - Vigilar el servicio para que avise si se vuelve a caer."
