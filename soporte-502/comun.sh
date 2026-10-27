# shellcheck shell=bash
# Constantes y funciones compartidas por los scripts del laboratorio.
# Se carga con "source"; no se ejecuta directamente.

readonly PUERTO=8081
readonly PUERTO_APP=8001
readonly URL="http://localhost:$PUERTO"
readonly DIRECTORIO_APP=/opt/lab-nginx-5xx
readonly MARCADOR="$DIRECTORIO_APP/.lab-nginx-5xx"
readonly SERVICIO=lab-nginx-5xx-app
readonly UNIDAD="/etc/systemd/system/$SERVICIO.service"
readonly SITIO=lab-nginx-5xx.conf
readonly SITIO_DISPONIBLE="/etc/nginx/sites-available/$SITIO"
readonly SITIO_ACTIVO="/etc/nginx/sites-enabled/$SITIO"
# Registros del sitio: los usan la ayuda autoguiada y desinstalar.sh.
# shellcheck disable=SC2034
readonly LOG_ERRORES=/var/log/nginx/lab-nginx-5xx.error.log
# shellcheck disable=SC2034
readonly LOG_ACCESOS=/var/log/nginx/lab-nginx-5xx.access.log
# Primera línea de los archivos del laboratorio: sirve para no tocar archivos ajenos.
readonly FIRMA='lab-nginx-5xx (instalado por instalar.sh)'

# Código HTTP de la página principal del laboratorio (000 si no hay respuesta).
# --noproxy: un http_proxy configurado (por ejemplo, hacia Burp) desviaría la petición.
codigo_http() {
    curl --silent --noproxy '*' --max-time 5 --output /dev/null \
        --write-out '%{http_code}' "$URL/" 2>/dev/null || echo 000
}

puerto_en_uso() {
    [[ -n "$(ss -Hltn "sport = :$1")" ]]
}

# Aborta si los puertos los usa otro programa (por ejemplo, el proxy de Burp Suite).
comprobar_puertos() {
    local ocupado
    ocupado=$(ss -Hltnp "sport = :$PUERTO")
    if [[ -n "$ocupado" ]] && { [[ ! -L "$SITIO_ACTIVO" ]] || [[ "$ocupado" != *'"nginx"'* ]]; }; then
        echo "ERROR: el puerto $PUERTO ya está en uso por otro programa:" >&2
        echo "$ocupado" >&2
        return 1
    fi
    ocupado=$(ss -Hltnp "sport = :$PUERTO_APP")
    if [[ -n "$ocupado" ]] && ! systemctl is-active --quiet "$SERVICIO"; then
        echo "ERROR: el puerto $PUERTO_APP ya está en uso por otro programa:" >&2
        echo "$ocupado" >&2
        return 1
    fi
}

# Espera hasta 5 segundos a que el puerto se abra ("abierto") o se cierre ("cerrado").
esperar_puerto() {
    local puerto=$1 estado=$2
    for _ in {1..50}; do
        if [[ $estado == abierto ]] && puerto_en_uso "$puerto"; then return 0; fi
        if [[ $estado == cerrado ]] && ! puerto_en_uso "$puerto"; then return 0; fi
        sleep 0.1
    done
    echo "ERROR: el puerto $puerto no llegó a estar $estado." >&2
    return 1
}

# Los archivos que ya existen y no llevan la firma del laboratorio no se tocan.
comprobar_rutas_ajenas() {
    if [[ -e "$DIRECTORIO_APP" || -L "$DIRECTORIO_APP" ]] && [[ ! -f "$MARCADOR" || -L "$DIRECTORIO_APP" ]]; then
        echo "ERROR: $DIRECTORIO_APP ya existe y no es del laboratorio; no se modifica nada." >&2
        return 1
    fi
    local archivo
    for archivo in "$UNIDAD" "$SITIO_DISPONIBLE"; do
        if [[ -L "$archivo" ]] || { [[ -e "$archivo" ]] && ! grep -qF -- "$FIRMA" "$archivo"; }; then
            echo "ERROR: $archivo ya existe y no es del laboratorio; no se modifica nada." >&2
            return 1
        fi
    done
}

laboratorio_instalado() {
    [[ -f "$MARCADOR" && -f "$UNIDAD" && -L "$SITIO_ACTIVO" ]]
}

# Retira el sitio y recarga nginx solo si la configuración restante es válida.
retirar_sitio() {
    rm -f -- "$SITIO_ACTIVO" "$SITIO_DISPONIBLE"
    if ! systemctl is-active --quiet nginx; then
        return 0
    fi
    if nginx -t -q 2>/dev/null; then
        systemctl reload nginx
        esperar_puerto "$PUERTO" cerrado
    else
        echo "AVISO: la configuración de nginx tiene errores ajenos al laboratorio; no se recargó." >&2
        return 1
    fi
}

# El sitio "default" de nginx publica /var/www/html en el puerto 80 de todas las interfaces.
avisar_sitio_default() {
    if [[ -e /etc/nginx/sites-enabled/default ]]; then
        echo "AVISO: el sitio 'default' de nginx está activo y publica /var/www/html en el puerto 80" >&2
        echo "       de todas las interfaces. Para desactivarlo:" >&2
        echo "       sudo rm /etc/nginx/sites-enabled/default && sudo systemctl reload nginx" >&2
    fi
}
