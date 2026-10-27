# shellcheck shell=bash
# Constantes y funciones compartidas por instalar.sh, preparar-lab.sh y desinstalar.sh.
# Se carga con "source"; no se ejecuta directamente.

readonly WEB=/var/www/html
readonly MARCADOR="$WEB/.lab-nginx-codigos"
readonly PUERTO=8080
readonly SITIO=lab-nginx-codigos.conf
readonly SITIO_DISPONIBLE="/etc/nginx/sites-available/$SITIO"
readonly SITIO_ACTIVO="/etc/nginx/sites-enabled/$SITIO"

# Aborta si el puerto lo usa otro programa (por ejemplo, el proxy de Burp Suite)
# o un sitio de nginx que no es el del laboratorio. nginx -t no detecta este caso.
comprobar_puerto() {
    local ocupado
    ocupado=$(ss -Hltnp "sport = :$PUERTO")
    if [[ -n "$ocupado" ]] && { [[ ! -L "$SITIO_ACTIVO" ]] || [[ "$ocupado" != *'"nginx"'* ]]; }; then
        echo "ERROR: el puerto $PUERTO ya está en uso por otro programa:" >&2
        echo "$ocupado" >&2
        return 1
    fi
}

# systemctl reload es asíncrono: espera a que nginx escuche en el puerto del laboratorio.
esperar_puerto() {
    for _ in {1..50}; do
        if [[ -n "$(ss -Hltn "sport = :$PUERTO")" ]]; then
            return 0
        fi
        sleep 0.1
    done
    echo "ERROR: nginx no llegó a escuchar en el puerto $PUERTO." >&2
    return 1
}

# Retira el sitio del laboratorio y recarga nginx solo si la configuración restante es válida.
# Devuelve 1 si no se pudo recargar (nginx seguiría sirviendo el puerto hasta corregirlo).
retirar_sitio() {
    rm -f -- "$SITIO_ACTIVO" "$SITIO_DISPONIBLE"
    if ! systemctl is-active --quiet nginx; then
        return 0
    fi
    if nginx -t -q 2>/dev/null; then
        systemctl reload nginx
        # La recarga es asíncrona: se espera a que nginx suelte el puerto para que
        # una reinstalación inmediata no lo encuentre ocupado.
        for _ in {1..50}; do
            [[ -z "$(ss -Hltn "sport = :$PUERTO")" ]] && return 0
            sleep 0.1
        done
    else
        echo "AVISO: la configuración de nginx tiene errores ajenos al laboratorio; no se recargó." >&2
        return 1
    fi
}

# Los scripts escriben como root en estas rutas: se rechazan enlaces simbólicos y
# directorios que no sean de root o en los que otros usuarios puedan escribir, porque
# podrían redirigir la escritura a archivos del sistema (secreto.txt -> /etc/passwd).
comprobar_directorio() {
    local directorio=$1
    if [[ ! -e "$directorio" && ! -L "$directorio" ]]; then
        return 0
    fi
    if [[ -L "$directorio" || ! -d "$directorio" || "$(stat -c %u -- "$directorio")" != 0 ]]; then
        echo "ERROR: $directorio no es un directorio de root (¿enlace simbólico?); no se modifica nada." >&2
        return 1
    fi
    if [[ -n "$(find "$directorio" -maxdepth 0 -perm /022)" ]]; then
        echo "ERROR: otros usuarios pueden escribir en $directorio; por seguridad no se modifica nada." >&2
        return 1
    fi
}

# Sin marcador, carpeta/, privado/ y secreto.txt no son del laboratorio: no se tocan
# para no cambiar sus permisos, sobrescribirlos ni borrarlos al desinstalar.
comprobar_rutas_ajenas() {
    local ruta
    [[ -f "$MARCADOR" ]] && return 0
    for ruta in "$WEB/carpeta" "$WEB/privado" "$WEB/secreto.txt"; do
        if [[ -e "$ruta" || -L "$ruta" ]]; then
            echo "ERROR: $ruta ya existe y no es del laboratorio; no se modifica nada." >&2
            return 1
        fi
    done
}

# El sitio "default" de nginx publica /var/www/html en el puerto 80 de todas las
# interfaces: las páginas del laboratorio también serían visibles desde la red.
avisar_sitio_default() {
    if [[ -e /etc/nginx/sites-enabled/default ]]; then
        echo "AVISO: el sitio 'default' de nginx está activo y publica $WEB en el puerto 80;" >&2
        echo "       el contenido del laboratorio también se verá ahí. Para desactivarlo:" >&2
        echo "       sudo rm /etc/nginx/sites-enabled/default && sudo systemctl reload nginx" >&2
    fi
}

# Guarda el hash del index instalado: desinstalar.sh solo lo retira si nadie lo ha modificado.
escribir_marcador() {
    local temporal
    temporal=$(mktemp)
    if ! (cd "$WEB" && sha256sum index.html) > "$temporal"; then
        rm -f -- "$temporal"
        return 1
    fi
    install -m 644 "$temporal" "$MARCADOR"
    rm -f -- "$temporal"
}
