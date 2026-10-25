# Laboratorio de códigos de estado HTTP con nginx

Laboratorio local para aprender y practicar los códigos HTTP `200`, `206`, `301`,
`400`, `403`, `404`, `405` y `416` con **nginx** y **curl**. Está pensado para
Parrot OS, Debian y distribuciones derivadas.

> Este proyecto modifica únicamente archivos concretos dentro de `/var/www/html`
> y añade el sitio `/etc/nginx/sites-available/lab-nginx-codigos.conf`.
> La primera vez conserva el `index.html` anterior como
> `/var/www/html/index.html.bak-apache`.

El laboratorio se publica en el **puerto 8080** y solo escucha en `localhost`,
así que no choca con otros sitios que nginx sirva en el puerto 80 y no es
accesible desde la red.

## Instalación rápida

```bash
git clone https://github.com/BEMC-GTRX/lab-nginx-codigos.git
cd lab-nginx-codigos
./instalar.sh
```

El script solicita `sudo` cuando hace falta, instala `nginx` y `curl` si no están
presentes, despliega el contenido, inicia el servicio y ejecuta una comprobación
inicial. Después abre <http://localhost:8080/> en el navegador.

## ¿Qué hace cada comando?

- `git clone URL`: descarga una copia completa del repositorio.
- `cd lab-nginx-codigos`: entra en la carpeta descargada.
- `./instalar.sh`: ejecuta el instalador incluido en el proyecto.
- `sudo`: concede permisos administrativos solo para instalar paquetes, escribir
  en `/var/www/html`, publicar el sitio en `/etc/nginx` y controlar el servicio
  nginx.

No es recomendable trabajar habitualmente como `root`. El instalador puede
ejecutarse desde un usuario normal y solicitará la contraseña únicamente cuando
necesite esos permisos.

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

## Tutorial interactivo de la parte 2

`video2.sh` reproduce paso a paso la explicación usada en el vídeo:

```bash
cd lab-nginx-codigos
sudo ./video2.sh
```

La demostración requiere que `/var/www/html/index.html.bak-apache` no exista. Si
antes utilizaste el instalador, restaura el estado inicial con `./desinstalar.sh`
y comprueba el contenido de `/var/www/html` antes de comenzar otra toma.

## Desinstalación

```bash
./desinstalar.sh
```

El script solo retira las rutas creadas por el laboratorio, el sitio del puerto
8080 y restaura la copia de seguridad del `index.html`. Deja nginx instalado y en ejecución porque podría
estar sirviendo otros proyectos.

## Archivos principales

| Archivo | Función |
|---|---|
| `instalar.sh` | Instala dependencias y despliega el laboratorio. |
| `preparar-lab.sh` | Crea las rutas y permisos necesarios. |
| `verificar.sh` | Comprueba automáticamente cada respuesta HTTP. |
| `desinstalar.sh` | Retira el laboratorio y restaura el índice anterior. |
| `video2.sh` | Guion interactivo para grabar la segunda parte. |
| `index.html` | Guía visual y ejercicios del laboratorio. |
| `nginx/lab-nginx-codigos.conf` | Sitio de nginx en `localhost:8080`. |

## Aviso

Úsalo solo en tu propio equipo o en un laboratorio autorizado. El archivo
`secreto.txt` con permisos restrictivos es intencionado: sirve para provocar una
respuesta `403 Forbidden`; no contiene información real.
