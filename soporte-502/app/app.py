"""Aplicación de ejemplo del laboratorio lab-nginx-5xx.

Hace de "aplicación de la empresa" detrás de nginx: nginx recibe las peticiones en
localhost:8081 y se las pasa a esta aplicación en 127.0.0.1:8001. Si la aplicación
no está en marcha, nginx no tiene a quién preguntar y responde 502 Bad Gateway.

También tiene un login de demostración en /login (vídeo 4: Man-in-the-Middle).
Funciona por HTTP a propósito: usuario y contraseña viajan sin cifrar y cualquiera
que esté en medio (por ejemplo, mitmproxy) los puede leer. NUNCA hagas esto en un
sitio real: los logins reales van siempre por HTTPS.
Solo usa la biblioteca estándar de Python.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs
import hmac
import secrets
import sys

DIRECCION = "127.0.0.1"
PUERTO = 8001

# Credenciales FALSAS, solo para la demostración del laboratorio.
USUARIO_DEMO = "victima"
CLAVE_DEMO = "Lab-Http-2026"

# Un formulario de login es pequeño: se rechazan cuerpos mayores para no llenar la memoria.
MAXIMO_CUERPO = 4096

ESTILO = """
  <style>
    body { font-family: sans-serif; max-width: 720px; margin: 40px auto; padding: 0 16px;
           background: #f5f6f8; color: #222; line-height: 1.5; }
    h1 { color: #0b6e4f; }
    code { background: #1e1e1e; color: #9cdcfe; border-radius: 4px; padding: 2px 6px; }
    form { background: #fff; border-radius: 8px; padding: 24px; max-width: 360px;
           box-shadow: 0 2px 8px rgba(0, 0, 0, .1); }
    label { display: block; margin-top: 12px; font-weight: bold; }
    input { width: 100%; box-sizing: border-box; padding: 8px; margin-top: 4px; font-size: 16px; }
    button { margin-top: 20px; padding: 10px 20px; font-size: 16px; background: #0b6e4f;
             color: #fff; border: 0; border-radius: 4px; cursor: pointer; }
    .error { color: #b00020; font-weight: bold; }
  </style>"""


def pagina(titulo, cuerpo):
    return f"""<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{titulo}</title>{ESTILO}
</head>
<body>
{cuerpo}
</body>
</html>
""".encode("utf-8")


PAGINA = pagina("Aplicación del laboratorio 5xx", """  <h1>La aplicación funciona</h1>
  <p>nginx ha recibido tu petición y se la ha pasado a la aplicación, que ha respondido
  con <strong>200 OK</strong>.</p>
  <p>Ruta del navegador: <code>localhost:8081</code> &rarr; nginx &rarr;
  <code>127.0.0.1:8001</code> (aplicación).</p>""")


def pagina_login(mensaje=""):
    return pagina("Iniciar sesión", f"""  <h1>Iniciar sesión</h1>
  {mensaje}
  <form method="post" action="/login">
    <label for="usuario">Usuario</label>
    <input id="usuario" name="usuario" autocomplete="username">
    <label for="clave">Contraseña</label>
    <input id="clave" name="clave" type="password" autocomplete="current-password">
    <button type="submit">Entrar</button>
  </form>""")


PAGINA_BIENVENIDA = pagina("Panel", """  <h1>Bienvenido, victima</h1>
  <p>Has iniciado sesión correctamente.</p>
  <p>Pero esta página llegó por <strong>HTTP</strong>: tu usuario, tu contraseña y tu
  cookie de sesión viajaron sin cifrar.</p>""")


class Manejador(BaseHTTPRequestHandler):
    server_version = "lab-nginx-5xx"
    sys_version = ""

    def _responder(self, codigo, contenido, cabeceras=(), enviar_cuerpo=True):
        self.send_response(codigo)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(contenido)))
        for nombre, valor in cabeceras:
            self.send_header(nombre, valor)
        self.end_headers()
        if enviar_cuerpo:
            self.wfile.write(contenido)

    def _contenido_get(self):
        if self.path == "/login":
            return 200, pagina_login()
        return 200, PAGINA

    def do_GET(self):
        self._responder(*self._contenido_get())

    def do_HEAD(self):
        self._responder(*self._contenido_get(), enviar_cuerpo=False)

    def do_POST(self):
        if self.path != "/login":
            self._responder(404, pagina("No encontrado", "  <h1>404</h1>"))
            return
        try:
            longitud = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            longitud = -1
        if not 0 <= longitud <= MAXIMO_CUERPO:
            self._responder(400, pagina("Petición incorrecta", "  <h1>400</h1>"))
            return
        datos = parse_qs(self.rfile.read(longitud).decode("utf-8", "replace"))
        usuario = datos.get("usuario", [""])[0]
        clave = datos.get("clave", [""])[0]
        # compare_digest compara en tiempo constante (buena costumbre, aunque sea una demo).
        if (hmac.compare_digest(usuario.encode(), USUARIO_DEMO.encode())
                and hmac.compare_digest(clave.encode(), CLAVE_DEMO.encode())):
            sesion = secrets.token_hex(16)
            # Sin "Secure": la cookie viaja por HTTP y también se puede robar.
            cookie = ("Set-Cookie", f"sesion={sesion}; HttpOnly; Path=/; SameSite=Lax")
            self._responder(200, PAGINA_BIENVENIDA, cabeceras=[cookie])
        else:
            mensaje = '<p class="error">Usuario o contraseña incorrectos.</p>'
            self._responder(401, pagina_login(mensaje))

    # Cada petición queda en el diario del servicio (journalctl -u lab-nginx-5xx-app).
    # Solo se registra la línea de la petición, nunca el cuerpo con la contraseña.
    def log_message(self, formato, *args):
        print(f"{self.address_string()} {formato % args}", flush=True)


def main():
    servidor = ThreadingHTTPServer((DIRECCION, PUERTO), Manejador)
    print(f"Aplicación escuchando en {DIRECCION}:{PUERTO}", flush=True)
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        servidor.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
