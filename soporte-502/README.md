# Laboratorio de soporte: reparar un 502 Bad Gateway con nginx

Laboratorio local para practicar, desde el lado de **soporte técnico**, cómo se
diagnostica y se repara un error de la familia **5xx**. nginx hace de proxy de una
pequeña aplicación; cuando la aplicación se cae, los usuarios reciben un
`502 Bad Gateway`. Tu trabajo es averiguar por qué y volver a levantar el servicio.

## Qué vas a aprender

- Reproducir el error que reporta un usuario con `curl`.
- Distinguir si el fallo está en nginx o en la aplicación que tiene detrás.
- Leer el registro de errores de nginx y entender sus mensajes.
- Comprobar qué programa escucha en un puerto con `ss`.
- Revisar y arrancar servicios con `systemctl` y consultar su historial con `journalctl`.
- Confirmar que la incidencia está resuelta antes de cerrarla.

## Requisitos

- **Parrot OS, Debian** o una distribución derivada.
- Un usuario con permisos de `sudo`.
- Los puertos **8081** y **8001** libres.
- Conexión a internet solo si te falta alguno de estos paquetes: `nginx`, `curl`,
  `iproute2` o `python3`. El instalador los añade automáticamente.

## Instalación

Este laboratorio está en la carpeta `soporte-502/` del repositorio
`lab-nginx-codigos`, junto al laboratorio de códigos HTTP:

```bash
git clone https://github.com/BEMC-GTRX/lab-nginx-codigos.git
cd lab-nginx-codigos/soporte-502
./instalar.sh
```

Si ya tenías descargado `lab-nginx-codigos`, no hace falta volver a clonarlo:
actualízalo y entra en la carpeta.

```bash
cd lab-nginx-codigos
git pull
cd soporte-502
./instalar.sh
```

Todos los comandos de esta guía se ejecutan dentro de la carpeta `soporte-502/`.

El script pide tu contraseña de `sudo` cuando la necesita. Al terminar debe mostrar:

```
[OK] Laboratorio listo en http://localhost:8081/ (responde 200 OK).
Para provocar la avería: sudo ./romper.sh
```

Abre <http://localhost:8081/> en el navegador: verás la página
«La aplicación funciona».

## Guía paso a paso

### 1. Comprueba que todo funciona

```bash
./verificar.sh
```

```
[OK] http://localhost:8081/ responde 200: la web funciona.
```

### 2. Provoca la avería

```bash
sudo ./romper.sh
```

```
Avería preparada.

Un usuario llama a soporte: «la web http://localhost:8081/ no carga, me sale un error».
Tu trabajo: averiguar qué pasa y dejarla funcionando otra vez.
```

`romper.sh` no dice qué ha roto: encontrarlo es el ejercicio. Si recargas el
navegador verás la página `502 Bad Gateway` de nginx, y `./verificar.sh` mostrará:

```
[AVERÍA] http://localhost:8081/ responde 502 Bad Gateway.
```

### 3. Diagnostica y repara

Investiga como lo haría soporte técnico. Estas preguntas y comandos te llevan a la
causa; intenta resolverlo antes de mirar la solución:

| Pregunta | Comando |
|---|---|
| ¿Qué ve el usuario? | `curl -I http://localhost:8081/` |
| ¿Funciona nginx? | `systemctl is-active nginx` |
| ¿Qué dice nginx del error? | `sudo tail -n 5 /var/log/nginx/lab-nginx-5xx.error.log` |
| ¿A dónde envía nginx las peticiones? | `grep proxy_pass /etc/nginx/sites-enabled/lab-nginx-5xx.conf` |
| ¿Es válida la configuración? | `sudo nginx -t` |
| ¿Quién escucha en ese puerto? | `sudo ss -ltnp 'sport = :8001'` |
| ¿En qué estado está el servicio? | `systemctl status lab-nginx-5xx-app --no-pager` |
| ¿Qué le pasó al servicio? | `sudo journalctl -u lab-nginx-5xx-app -n 20 --no-pager` |

Cuando creas que lo has arreglado, compruébalo con `./verificar.sh`: debe volver a
responder `200`.

### 4. Si te atascas: la ayuda autoguiada

```bash
sudo ./ayuda-autoguiada-reparar-502.sh
```

Resuelve la avería en 8 pasos. Escribe cada comando, explica qué buscas y espera a
que pulses Enter antes de seguir:

1. Reproducir el error con `curl -I`.
2. Comprobar si nginx funciona.
3. Leer el registro de errores de nginx.
4. Revisar a dónde envía nginx las peticiones y validar la configuración.
5. Ver si algún programa escucha en el puerto de la aplicación.
6. Revisar el estado y el historial del servicio de la aplicación.
7. Arreglar la causa.
8. Comprobar que la web vuelve a responder `200 OK`.

Al final muestra un resumen de todo el diagnóstico.

### 5. Repite

Puedes repetir los pasos 2 a 4 tantas veces como quieras: `romper.sh` vuelve a
provocar la avería cada vez que la web funciona.

## Cómo funciona por dentro

```
navegador ──> nginx (localhost:8081) ──> aplicación (127.0.0.1:8001)
                     │                          │
                     └── si la aplicación no responde, nginx devuelve 502
```

- **nginx** recibe las peticiones en el puerto 8081 y, como proxy, se las pasa a
  la aplicación (directiva `proxy_pass`).
- **La aplicación** es un pequeño programa en Python (`app/app.py`) que responde
  con la página «La aplicación funciona». Se ejecuta como el servicio de systemd
  `lab-nginx-5xx-app`.
- Un **502 Bad Gateway** significa que nginx funciona, pero la aplicación que tiene
  detrás no le ha dado una respuesta válida.

Otros errores de la misma familia que te encontrarás en soporte:

| Código | Significado | Causa típica |
|---|---|---|
| `500 Internal Server Error` | La aplicación falló al procesar la petición. | Un error en el código de la aplicación. |
| `502 Bad Gateway` | El proxy no obtuvo una respuesta válida de la aplicación. | La aplicación está caída o nginx apunta a un puerto equivocado. |
| `503 Service Unavailable` | El servicio no puede atender peticiones ahora mismo. | Mantenimiento o sobrecarga. |
| `504 Gateway Timeout` | La aplicación tardó demasiado en responder. | Una aplicación lenta o bloqueada. |

## Qué cambia en el sistema

- Instala la aplicación en `/opt/lab-nginx-5xx/` y su servicio en
  `/etc/systemd/system/lab-nginx-5xx-app.service`.
- Añade el sitio `/etc/nginx/sites-available/lab-nginx-5xx.conf` y su enlace en
  `/etc/nginx/sites-enabled/`, y recarga nginx (o lo arranca si estaba parado).
- El sitio escribe sus registros en `/var/log/nginx/lab-nginx-5xx.error.log` y
  `/var/log/nginx/lab-nginx-5xx.access.log`.
- Si instala nginx, lo hace sin arrancarlo con el sitio `default` del paquete y
  desactiva ese sitio, que publicaría `/var/www/html` en el puerto 80 de todas las
  interfaces.

**Seguridad:**

- nginx solo escucha en `127.0.0.1:8081` y la aplicación en `127.0.0.1:8001`: el
  laboratorio no es accesible desde la red.
- La aplicación se ejecuta con un usuario temporal sin privilegios y sin permiso
  para escribir en el sistema.
- Antes de modificar nada, los scripts se detienen si los puertos ya los usa otro
  programa o si encuentran archivos con el mismo nombre que no son del laboratorio.
- Puede convivir con el [laboratorio de códigos HTTP](../README.md) de la
  carpeta principal, que usa el puerto 8080.

## Solución de problemas

**«ERROR: el puerto 8081 (u 8001) ya está en uso por otro programa»**
Otro programa, como el proxy de Burp Suite, usa ese puerto. El mensaje muestra cuál
es; ciérralo y vuelve a ejecutar `./instalar.sh`.

**Después de reiniciar el equipo, la web da 502 sin haber ejecutado `romper.sh`**
Es normal: el servicio de la aplicación no se activa al arrancar el equipo, para
que el laboratorio solo funcione mientras practicas. Arréglalo como en el ejercicio
o ejecuta `./instalar.sh` de nuevo.

**`./verificar.sh` dice que la web no responde**
nginx está parado. Arráncalo con `sudo systemctl start nginx`.

**«El laboratorio no está averiado»**
La ayuda autoguiada solo se ejecuta con la avería activa. Provócala antes con
`sudo ./romper.sh`.

**«ERROR: ejecuta este script con sudo»**
`romper.sh` y la ayuda autoguiada necesitan permisos de administrador. Ejecútalos
con `sudo` delante.

## Desinstalación

```bash
./desinstalar.sh
```

Retira la aplicación, su servicio, el sitio de nginx y sus registros. Solo borra
archivos que llevan la marca del laboratorio y puede ejecutarse varias veces sin
problema. Deja nginx instalado y en el estado en que esté, porque podría estar
sirviendo otros proyectos.

## Archivos

| Archivo | Función |
|---|---|
| `instalar.sh` | Instala dependencias y deja el laboratorio funcionando. |
| `romper.sh` | Provoca la avería (502). |
| `verificar.sh` | Dice si la web funciona o está averiada. No necesita `sudo`. |
| `ayuda-autoguiada-reparar-502.sh` | Ayuda autoguiada que repara la avería paso a paso. |
| `desinstalar.sh` | Retira todo lo que instaló el laboratorio. |
| `app/app.py` | Aplicación de ejemplo (solo biblioteca estándar de Python). |
| `app/lab-nginx-5xx-app.service` | Servicio de systemd de la aplicación. |
| `nginx/lab-nginx-5xx.conf` | Sitio de nginx en `localhost:8081` que hace de proxy. |
| `comun.sh` | Datos y comprobaciones de seguridad compartidas por los scripts. |

## Aviso

Úsalo solo en tu propio equipo o en un laboratorio autorizado.
