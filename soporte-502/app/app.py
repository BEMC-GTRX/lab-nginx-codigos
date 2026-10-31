"""Aplicación de ejemplo del laboratorio lab-nginx-5xx.

Hace de "aplicación de la empresa" detrás de nginx: nginx recibe las peticiones en
localhost:8081 y se las pasa a esta aplicación en 127.0.0.1:8001. Si la aplicación
no está en marcha, nginx no tiene a quién preguntar y responde 502 Bad Gateway.
Solo usa la biblioteca estándar de Python.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import sys

DIRECCION = "127.0.0.1"
PUERTO = 8001

PAGINA = """<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Aplicación del laboratorio 5xx</title>
  <style>
    body { font-family: sans-serif; max-width: 720px; margin: 40px auto; padding: 0 16px;
           background: #f5f6f8; color: #222; line-height: 1.5; }
    h1 { color: #0b6e4f; }
    code { background: #1e1e1e; color: #9cdcfe; border-radius: 4px; padding: 2px 6px; }
  </style>
</head>
<body>
  <h1>La aplicación funciona</h1>
  <p>nginx ha recibido tu petición y se la ha pasado a la aplicación, que ha respondido
  con <strong>200 OK</strong>.</p>
  <p>Ruta del navegador: <code>localhost:8081</code> &rarr; nginx &rarr;
  <code>127.0.0.1:8001</code> (aplicación).</p>
</body>
</html>
""".encode("utf-8")


class Manejador(BaseHTTPRequestHandler):
    server_version = "lab-nginx-5xx"
    sys_version = ""

    def _cabeceras(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(PAGINA)))
        self.end_headers()

    def do_GET(self):
        self._cabeceras()
        self.wfile.write(PAGINA)

    def do_HEAD(self):
        self._cabeceras()

    # Cada petición queda en el diario del servicio (journalctl -u lab-nginx-5xx-app).
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
