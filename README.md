# Laboratorio de códigos de estado HTTP con nginx

Laboratorio local para aprender y practicar los códigos HTTP `200`, `206`, `301`,
`400`, `403`, `404`, `405` y `416` con **nginx** y **curl**. Está pensado para
Parrot OS, Debian y distribuciones derivadas.

## Qué cambia en el sistema

- Crea `index.html`, `carpeta/`, `privado/`, `secreto.txt` y el marcador
  `.lab-nginx-codigos` en `/var/www/html`. La primera vez conserva el
  `index.html` anterior como `/var/www/html/index.html.bak-apache`.
- Añade el sitio `/etc/nginx/sites-available/lab-nginx-codigos.conf` y su enlace
  en `/etc/nginx/sites-enabled/`, y recarga nginx (o lo arranca si estaba parado).
- Si nginx no estaba instalado, lo instala sin arrancarlo con el sitio `default`
  del paquete (usa `/usr/sbin/policy-rc.d` de forma temporal) y desactiva ese
  sitio, que publicaría `/var/www/html` en el puerto 80 de todas las interfaces.

El sitio del laboratorio usa el **puerto 8080** y solo escucha en `127.0.0.1`,
así que no choca con otros sitios del puerto 80 y no es accesible desde la red.
Si nginx ya estaba instalado con el sitio `default` activo, ese sitio sigue
publicando `/var/www/html` en el puerto 80: el instalador no lo toca, pero avisa
y te indica cómo desactivarlo.

Antes de instalar paquetes o modificar nada, el instalador se detiene si el
puerto 8080 ya lo usa otro programa (por ejemplo, el proxy de Burp Suite) o si
`carpeta/`, `privado/` o `secreto.txt` ya existen y no son del laboratorio.

Mientras el laboratorio esté instalado, nginx necesita el puerto 8080 libre para
arrancar: si otro programa lo ocupa durante un reinicio de nginx, nginx no
arrancará (tampoco sus otros sitios). Cuando termines de practicar, ejecuta
`./desinstalar.sh`.

## Instalación rápida

```bash
git clone https://github.com/BEMC-GTRX/lab-nginx-codigos.git
cd lab-nginx-codigos
./instalar.sh
```

El script solicita `sudo` cuando hace falta, instala `nginx`, `curl` e `iproute2`
si no están presentes, despliega el contenido, inicia el servicio y ejecuta una comprobación
inicial. Después abre <http://localhost:8080/> en el navegador.

## Actualizar a la última versión

Si ya habías descargado el laboratorio, actualízalo con:

```bash
cd lab-nginx-codigos
git pull
./instalar.sh
```

A partir de esta versión también puedes actualizar con `./actualizar.sh` en lugar
de `git pull`. Se ejecuta sin `sudo`, descarga la última versión y la aplica
siempre que no choque con cambios tuyos: nunca descarta commits ni archivos que
hayas modificado, y si los hay te indica qué hacer.

Si `git pull` muestra un error de ramas divergentes («divergent branches»),
descargaste el laboratorio durante la
corrección descrita en [Historial del repositorio](#historial-del-repositorio).
Ponlo al día así:

```bash
git fetch origin
git reset --keep origin/main
./actualizar.sh
```

`git reset --keep` se detiene sin cambiar nada si tienes archivos modificados que
la actualización sobrescribiría.

## ¿Qué hace cada comando?

- `git clone URL`: descarga una copia completa del repositorio.
- `cd lab-nginx-codigos`: entra en la carpeta descargada.
- `./instalar.sh`: ejecuta el instalador incluido en el proyecto.
- `sudo`: concede permisos administrativos solo para instalar paquetes, escribir
  en `/var/www/html`, publicar el sitio en `/etc/nginx` y controlar el servicio
  nginx.

No es recomendable trabajar habitualmente como `root`. El instalador puede
ejecutarse desde un usuario normal y solicitará la contraseña únicamente cuando
necesite esos permisos. Si prefieres hacerte root, usa `su -` (con guion) y no
`su`: sin el guion se hereda el entorno de tu usuario.

## Verificar el entorno

```bash
./verificar.sh
```

La salida debe mostrar `[OK]` para las nueve pruebas. Para consultar nginx:

```bash
systemctl status nginx --no-pager
```

`systemctl status` muestra el estado del servicio y `--no-pager` imprime el
resultado directamente, sin abrir el visor interactivo.

## Desinstalación

```bash
./desinstalar.sh
```

El script solo retira las rutas creadas por el laboratorio, el sitio del puerto
8080 y restaura la copia de seguridad del `index.html`. Si modificaste el
`index.html` después de instalar, lo conserva y te avisa. Puede ejecutarse varias
veces sin problema. Deja nginx instalado y en ejecución porque podría
estar sirviendo otros proyectos, y no vuelve a activar el sitio `default` si el
instalador lo desactivó.

## Archivos principales

| Archivo | Función |
|---|---|
| `instalar.sh` | Instala dependencias y despliega el laboratorio. |
| `preparar-lab.sh` | Crea las rutas y permisos necesarios. |
| `verificar.sh` | Comprueba automáticamente cada respuesta HTTP. |
| `actualizar.sh` | Actualiza tu copia y limpia el historial retirado. |
| `desinstalar.sh` | Retira el laboratorio y restaura el índice anterior. |
| `index.html` | Guía visual y ejercicios del laboratorio. |
| `nginx/lab-nginx-codigos.conf` | Sitio de nginx en `localhost:8080`. |
| `comun.sh` | Comprobaciones de seguridad compartidas por los scripts. |

## Historial del repositorio

El 25 de octubre de 2026, durante unos 26 minutos (12:14–12:40 UTC), el historial
público incluyó tres commits (`6ad8803`, `f72bad2` y `0c6535c`) con metadatos de
autor incorrectos. Ese mismo día se sustituyeron por commits con los mismos
cambios y la autoría correcta, y se retiraron de GitHub.

Si clonaste o actualizaste el repositorio en esa franja, `actualizar.sh` los
elimina de tu copia local, y `instalar.sh` también lo hace cada vez que se
ejecuta. Las copias descargadas antes o después de esa franja, y las descargas en
ZIP, no los contienen.

## Aviso

Úsalo solo en tu propio equipo o en un laboratorio autorizado. El archivo
`secreto.txt` con permisos restrictivos es intencionado: sirve para provocar una
respuesta `403 Forbidden`; no contiene información real.
