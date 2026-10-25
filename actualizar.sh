#!/bin/bash
# Actualiza esta copia del laboratorio a la última versión publicada y, si todavía
# contiene los commits retirados del historial público, los elimina de .git
# (ver "Historial del repositorio" en el README).
# Uso: ./actualizar.sh   (sin sudo)
# instalar.sh lo llama con --limpiar: solo limpia .git, sin cambiar los archivos.
# Con "sh actualizar.sh" se usaría dash, que no entiende la sintaxis de bash.
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi
set -euo pipefail

# Commits sustituidos el 25-10-2026 por otros con el mismo contenido y la autoría
# correcta. Se reconocen por su hash; ninguno de sus datos aparece en este repositorio.
readonly COMMITS_RETIRADOS=(6ad8803 f72bad2 0c6535c)
readonly CORREO_NOREPLY='@users.noreply.github.com'
readonly RAMA_OFICIAL=refs/remotes/origin/main
readonly AUTOR_LAB='173935975+BEMC-GTRX@users.noreply.github.com'

DIRECTORIO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DIRECTORIO
MODO=normal
if [[ "${1:-}" == --limpiar ]]; then
    MODO=limpiar
fi
retirados=()

info() {
    printf '\033[1;34m[INFO]\033[0m %s\n' "$*"
}

correcto() {
    printf '\033[1;32m[OK]\033[0m %s\n' "$*"
}

aviso() {
    printf '\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2
}

error() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
}

g() {
    git -C "$DIRECTORIO" "$@"
}

# Con --limpiar (desde instalar.sh) no se informa de lo que no se hace.
salir_sin_cambios() {
    if [[ $MODO == normal ]]; then
        info "$*"
    fi
    exit 0
}

es_retirado() {
    local sha
    for sha in "${retirados[@]}"; do
        [[ "$1" == "$sha" ]] && return 0
    done
    return 1
}

# Doble comprobación: un commit con uno de esos hashes cuyo autor y committer usan la
# dirección noreply de GitHub no es uno de los retirados y no se toca.
detectar_retirados() {
    local prefijo sha
    retirados=()
    for prefijo in "${COMMITS_RETIRADOS[@]}"; do
        sha=$(g rev-parse -q --verify "$prefijo^{commit}" 2>/dev/null) || continue
        if g log -1 --format='%ae%n%ce' "$sha" | grep -qv -- "$CORREO_NOREPLY\$"; then
            retirados+=("$sha")
        fi
    done
}

# Commits que no están en la versión publicada, no son retirados y no son del autor del
# laboratorio (versiones anteriores del historial público): son trabajo del alumno y
# nunca se descartan. Sin argumentos revisa los que solo conserva el reflog.
commits_propios() {
    local sha correo
    local -a desde=("$@") excluir=("$RAMA_OFICIAL")
    if (( ${#desde[@]} == 0 )); then
        desde=(--reflog)
        excluir+=(--all)
        if g rev-parse -q --verify ORIG_HEAD >/dev/null; then
            desde+=(ORIG_HEAD)
        fi
    fi
    g rev-list --no-commit-header --format='%H %ae' "${desde[@]}" --not "${excluir[@]}" |
        while read -r sha correo; do
            es_retirado "$sha" || [[ "$correo" == "$AUTOR_LAB" ]] || printf '%s\n' "$sha"
        done
}

referencias_afectadas() {
    local sha
    for sha in "${retirados[@]}"; do
        g for-each-ref --contains "$sha" --format='%(refname)'
    done | sort -u
}

explicar_limpieza_manual() {
    error "Para obtener una copia limpia, guarda tus cambios y vuelve a clonar:"
    printf '  cd .. && mv lab-nginx-codigos lab-nginx-codigos.antiguo\n' >&2
    printf '  git clone https://github.com/BEMC-GTRX/lab-nginx-codigos.git\n' >&2
}

explicar_cambios_locales() {
    error "Tienes cambios sin confirmar en archivos que la actualización modifica."
    error "Guárdalos con 'git stash', ejecuta de nuevo ./actualizar.sh y recupéralos con 'git stash pop'."
}

# Antes de cambiar nada se comprueba que la limpieza no puede perder trabajo del alumno.
comprobar_limpieza() {
    local ref sha
    if ! g rev-parse -q --verify "$RAMA_OFICIAL" >/dev/null; then
        error "No se pudo obtener la versión publicada (¿sin conexión?)."
        return 1
    fi
    if ! g symbolic-ref -q HEAD >/dev/null; then
        for sha in "${retirados[@]}"; do
            if g merge-base --is-ancestor "$sha" HEAD; then
                error "HEAD está separado sobre un commit retirado. Vuelve a la rama main con 'git switch main' y repite."
                return 1
            fi
        done
    fi
    while read -r ref; do
        case $ref in
        refs/heads/*)
            if [[ -n "$(commits_propios "$ref")" ]]; then
                error "La rama ${ref#refs/heads/} tiene commits tuyos encima de los retirados. No se ha modificado nada."
                explicar_limpieza_manual
                return 1
            fi
            ;;
        refs/remotes/*) ;;
        *)
            error "La referencia $ref contiene un commit retirado. No se ha modificado nada."
            explicar_limpieza_manual
            return 1
            ;;
        esac
    done < <(referencias_afectadas)
    if [[ -n "$(commits_propios)" ]]; then
        error "El reflog conserva commits tuyos que no están en ninguna rama. No se ha modificado nada."
        explicar_limpieza_manual
        return 1
    fi
}

# Saca los commits retirados de ramas y referencias, caduca las entradas del reflog que
# los apuntan y elimina sus objetos de .git.
limpiar() {
    local ref sha rama_actual
    comprobar_limpieza || return 1
    rama_actual=$(g symbolic-ref -q HEAD || true)
    if [[ $MODO == limpiar && -n "$rama_actual" ]] && referencias_afectadas | grep -qxF -- "$rama_actual"; then
        # Cambiar los archivos mientras instalar.sh se ejecuta no es seguro.
        aviso "Al terminar la instalación, ejecuta ./actualizar.sh para completar la limpieza."
        return 1
    fi

    while read -r ref; do
        case $ref in
        "$rama_actual")
            if ! g reset -q --keep "$RAMA_OFICIAL"; then
                explicar_cambios_locales
                return 1
            fi
            ;;
        refs/heads/*)
            g update-ref "$ref" "$RAMA_OFICIAL"
            ;;
        refs/remotes/*)
            # git fetch las vuelve a crear con el historial publicado.
            g update-ref -d "$ref"
            ;;
        esac
    done < <(referencias_afectadas)

    if g rev-parse -q --verify ORIG_HEAD >/dev/null; then
        for sha in "${retirados[@]}"; do
            if g merge-base --is-ancestor "$sha" ORIG_HEAD; then
                g update-ref -d ORIG_HEAD
                break
            fi
        done
    fi

    # Caducan las entradas del reflog que apuntan a commits que ya no están en su rama;
    # comprobar_limpieza garantiza que ninguno es trabajo del alumno. Sin referencias,
    # repack -a -d no copia los retirados al nuevo paquete y prune borra los sueltos.
    g reflog expire --expire-unreachable=now --all
    g repack -a -d -q
    g prune --expire=now

    detectar_retirados
    if (( ${#retirados[@]} > 0 )); then
        error "No se pudieron eliminar de .git todos los commits retirados."
        explicar_limpieza_manual
        return 1
    fi
    correcto "Se eliminaron de esta copia los commits retirados del historial público."
}

actualizar_rama() {
    local rama
    if ! rama=$(g symbolic-ref -q --short HEAD) || [[ "$rama" != main ]]; then
        aviso "No estás en la rama main: no se actualizan los archivos. Usa 'git switch main' y repite."
        return 0
    fi
    if [[ "$(g rev-parse HEAD)" == "$(g rev-parse "$RAMA_OFICIAL")" ]]; then
        correcto "Ya tienes la última versión del laboratorio."
    elif [[ -n "$(commits_propios HEAD)" ]]; then
        aviso "Tu rama main tiene commits propios: no se actualiza automáticamente."
        aviso "Para incorporar la versión publicada: git rebase origin/main"
    elif ! g reset -q --keep "$RAMA_OFICIAL"; then
        # reset --keep también sustituye versiones anteriores del historial público.
        explicar_cambios_locales
        return 1
    else
        correcto "Laboratorio actualizado a la última versión."
        info "Si el laboratorio está instalado, ejecuta ./instalar.sh para aplicar los cambios."
    fi
}

main() {
    if [[ ! -e "$DIRECTORIO/.git" ]]; then
        salir_sin_cambios "Esta carpeta no es un clon de git (¿descarga en ZIP?): no hay historial que actualizar."
    fi
    if ! command -v git >/dev/null 2>&1; then
        salir_sin_cambios "git no está instalado: no se puede actualizar."
    fi

    # git nunca se ejecuta como root sobre la copia de otro usuario: la configuración de
    # su .git podría ejecutar programas con privilegios y root dejaría archivos suyos dentro.
    local propietario
    propietario=$(stat -c %U -- "$DIRECTORIO/.git")
    if [[ $EUID -eq 0 && "$propietario" != root ]]; then
        exec /usr/sbin/runuser -u "$propietario" -- \
            /bin/bash "$(readlink -f -- "${BASH_SOURCE[0]}")" "$@"
    fi
    HOME=$(getent passwd "$(id -u)" | cut -d: -f6)
    export HOME

    if [[ "$(g rev-parse --show-toplevel 2>/dev/null)" != "$DIRECTORIO" ]]; then
        salir_sin_cambios "Esta carpeta no es la raíz de un clon del laboratorio."
    fi
    case "$(g config --get remote.origin.url || true)" in
    *github.com[:/]BEMC-GTRX/lab-nginx-codigos | *github.com[:/]BEMC-GTRX/lab-nginx-codigos.git) ;;
    *) salir_sin_cambios "El remoto origin no es el repositorio oficial del laboratorio: no se modifica nada." ;;
    esac

    if [[ $MODO == normal ]]; then
        info "Descargando la última versión publicada..."
        if ! g fetch -q --prune origin; then
            error "No se pudo conectar con GitHub. Comprueba la conexión y repite."
            exit 1
        fi
    fi

    detectar_retirados
    if (( ${#retirados[@]} > 0 )); then
        aviso "Esta copia contiene commits retirados del historial público; se eliminan de .git."
        if [[ $MODO == limpiar ]] && ! g fetch -q --prune origin; then
            aviso "No se pudo conectar con GitHub; ejecuta ./actualizar.sh cuando tengas conexión."
            exit 1
        fi
        limpiar || exit 1
    fi

    if [[ $MODO == normal ]]; then
        actualizar_rama
    fi
}

# Todo se ejecuta desde main: bash ya ha leído el script completo y actualizarlo
# mientras se ejecuta no le afecta.
main "$@"; exit
