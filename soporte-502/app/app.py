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
USUARIO_DEMO = "cliente.demo"
CLAVE_DEMO = "Nebula-Lab-2026"

# Nombre del banco FICTICIO del laboratorio. No existe y no imita a ningún banco real.
BANCO = "Banco Nébula"

# Un formulario de login es pequeño: se rechazan cuerpos mayores para no llenar la memoria.
MAXIMO_CUERPO = 4096

# Aspecto "bancario" cuidado (solo la cara bonita del ejemplo). El aviso superior
# deja claro en todo momento que es un banco ficticio de laboratorio, para que nadie
# lo confunda con una web real. Todo el CSS va embebido: sin recursos externos, así
# funciona sin internet y a través del proxy del laboratorio.
ESTILO = """
  <style>
    :root { --navy: #06234d; --navy2: #0a3a7a; --azul: #1e88e5; --cielo: #7fb2ff; }
    * { box-sizing: border-box; }
    body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; background: #eef1f5;
           color: #1a2330; }
    a { color: var(--azul); text-decoration: none; }
    .aviso { background: #334155; color: #cbd5e1; text-align: center; padding: 3px 12px;
             font-size: 11px; letter-spacing: .3px; }
    /* Cabecera corporativa */
    header { background: #fff; border-bottom: 1px solid #e2e8f0; }
    .nav { max-width: 1120px; margin: 0 auto; padding: 14px 24px; display: flex;
           align-items: center; gap: 28px; }
    .marca { display: flex; align-items: center; gap: 10px; font-size: 20px; font-weight: 700;
             color: var(--navy); }
    .marca b { color: var(--azul); font-weight: 700; }
    .nav .links { display: flex; gap: 22px; margin-left: auto; font-size: 14px; }
    .nav .links a { color: #334155; font-weight: 600; }
    /* Login a pantalla partida */
    .split { display: flex; flex-wrap: wrap; max-width: 1120px; margin: 28px auto;
             padding: 0 24px; gap: 32px; align-items: stretch; }
    .promo { flex: 1 1 420px; background: linear-gradient(135deg, var(--navy), var(--navy2));
             color: #fff; border-radius: 16px; padding: 40px; }
    .promo h1 { font-size: 30px; line-height: 1.25; margin: 18px 0 10px; }
    .promo p.sub { color: #c7dbff; font-size: 16px; margin: 0 0 26px; }
    .promo ul { list-style: none; padding: 0; margin: 0 0 30px; }
    .promo li { padding: 8px 0 8px 30px; position: relative; color: #e6efff; }
    .promo li::before { content: "✓"; position: absolute; left: 0; color: var(--cielo);
                        font-weight: 700; }
    .stats { display: flex; gap: 28px; border-top: 1px solid rgba(255,255,255,.18);
             padding-top: 22px; }
    .stats .n { font-size: 24px; font-weight: 700; color: #fff; }
    .stats .t { font-size: 12px; color: #9fc0f0; }
    /* Tarjeta de acceso */
    .acceso { flex: 1 1 340px; max-width: 420px; background: #fff; border-radius: 16px;
              padding: 36px; box-shadow: 0 10px 30px rgba(6, 35, 77, .12); align-self: center; }
    .acceso h2 { margin: 0 0 4px; color: var(--navy); font-size: 22px; }
    .acceso .hint { margin: 0 0 22px; color: #64748b; font-size: 14px; }
    label { display: block; margin-top: 16px; font-weight: 600; font-size: 13px; color: #334155; }
    input { width: 100%; padding: 12px; margin-top: 6px; font-size: 16px;
            border: 1px solid #cbd5e1; border-radius: 8px; }
    input:focus { outline: none; border-color: var(--azul); box-shadow: 0 0 0 3px #bfdbfe; }
    button { margin-top: 24px; padding: 13px; font-size: 16px; font-weight: 600; width: 100%;
             background: var(--azul); color: #fff; border: 0; border-radius: 8px; cursor: pointer; }
    button:hover { background: #1669bb; }
    .extra { margin-top: 18px; display: flex; justify-content: space-between; font-size: 13px; }
    .candado { font-size: 12px; color: #64748b; margin-top: 18px; text-align: center; }
    .error { background: #fde2e2; color: #b00020; font-weight: 600; padding: 10px 14px;
             border-radius: 8px; margin-bottom: 8px; font-size: 14px; }
    /* Pie */
    footer { max-width: 1120px; margin: 10px auto 30px; padding: 0 24px; color: #64748b;
             font-size: 12px; text-align: center; }
    /* Páginas internas (home / cuenta) */
    .contenido { max-width: 760px; margin: 28px auto; padding: 0 24px; }
    .contenido h1 { color: var(--navy); font-size: 22px; }
    code { background: #1e1e1e; color: #9cdcfe; border-radius: 4px; padding: 2px 6px; }
    .saldo { background: #fff; border-radius: 12px; padding: 26px; margin-top: 16px;
             box-shadow: 0 6px 20px rgba(6, 35, 77, .10); }
    .saldo .cifra { font-size: 32px; color: var(--navy); font-weight: 700; }
    .peligro { background: #fde2e2; border-left: 5px solid #b00020; padding: 16px 20px;
               border-radius: 8px; margin-top: 22px; }
  </style>"""

# Marca con un pequeño logo SVG embebido (un orbe "Nébula"), sin imágenes externas.
LOGO = ('<svg width="30" height="30" viewBox="0 0 48 48" fill="none" '
        'xmlns="http://www.w3.org/2000/svg" aria-hidden="true">'
        '<circle cx="24" cy="24" r="22" fill="#0a3a7a"/>'
        '<circle cx="24" cy="24" r="8" fill="#7fb2ff"/>'
        '<ellipse cx="24" cy="24" rx="20" ry="8" stroke="#1e88e5" stroke-width="2.5" '
        'transform="rotate(-30 24 24)"/></svg>')
MARCA = f'<span class="marca">{LOGO} Banco <b>Nébula</b></span>'

BANNER = ('  <div class="aviso">Laboratorio local Tech Lab · banco ficticio · '
          'solo 127.0.0.1</div>\n')


def documento(titulo, cuerpo):
    return f"""<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{titulo}</title>{ESTILO}
</head>
<body>
{BANNER}{cuerpo}
</body>
</html>
""".encode("utf-8")


def _con_cabecera(titulo, interior):
    """Páginas internas: cabecera + contenido centrado."""
    cabecera = f"""  <header><div class="nav">{MARCA}
      <div class="links"><a href="#">Particulares</a><a href="#">Empresas</a>
      <a href="#">Ayuda</a></div></div></header>
"""
    return documento(titulo, cabecera + f'  <div class="contenido">\n{interior}\n  </div>')


PAGINA = _con_cabecera("Banco Nébula", """    <h1>La aplicación funciona</h1>
    <p>nginx ha recibido tu petición y se la ha pasado a la aplicación, que ha respondido
    con <strong>200 OK</strong>.</p>
    <p>Ruta del navegador: <code>localhost:8081</code> &rarr; nginx &rarr;
    <code>127.0.0.1:8001</code> (aplicación).</p>
    <p>Para entrar en la banca en línea de demostración: <code>/login</code>.</p>""")


def pagina_login(mensaje=""):
    aviso = f'    <div class="error">{mensaje}</div>\n' if mensaje else ""
    cuerpo = f"""  <header><div class="nav">{MARCA}
      <div class="links"><a href="#">Particulares</a><a href="#">Empresas</a>
      <a href="#">Ayuda</a></div></div></header>
  <div class="split">
    <section class="promo">
      {LOGO}
      <h1>Tu banca en línea,<br>siempre contigo</h1>
      <p class="sub">Opera con tus cuentas y tarjetas en cualquier momento y lugar.</p>
      <ul>
        <li>Transferencias inmediatas a toda la zona SEPA</li>
        <li>Control de tarjetas y alertas en tiempo real</li>
        <li>Red de cajeros y oficinas en todo el país</li>
        <li>Atención personal todos los días del año</li>
      </ul>
      <div class="stats">
        <div><div class="n">3,4 M</div><div class="t">clientes</div></div>
        <div><div class="n">1.280</div><div class="t">oficinas</div></div>
        <div><div class="n">24/7</div><div class="t">soporte</div></div>
      </div>
    </section>
    <section class="acceso">
      <h2>Acceso clientes</h2>
      <p class="hint">Introduce tus credenciales de banca en línea.</p>
{aviso}      <form method="post" action="/login">
        <label for="usuario">Usuario</label>
        <input id="usuario" name="usuario" autocomplete="username" placeholder="Tu usuario">
        <label for="clave">Contraseña</label>
        <input id="clave" name="clave" type="password" autocomplete="current-password"
               placeholder="Tu contraseña">
        <button type="submit">Acceder</button>
      </form>
      <div class="extra"><a href="#">¿Olvidaste tu clave?</a><a href="#">Hazte cliente</a></div>
      <p class="candado">🔒 Conexión segura · tus datos están protegidos</p>
    </section>
  </div>
  <footer>Banco Nébula S.A. (entidad ficticia) · Aviso legal · Privacidad · Seguridad —
    Laboratorio local Tech Lab, solo para demostración en 127.0.0.1</footer>"""
    return documento("Banca en línea · Banco Nébula", cuerpo)


PAGINA_BIENVENIDA = _con_cabecera("Mi cuenta · Banco Nébula", """    <h1>Hola, cliente.demo</h1>
    <div class="saldo">
      <p>Saldo disponible en tu cuenta</p>
      <p class="cifra">12.480,53 €</p>
      <p>Cuenta ficticia ES00 0000 0000 0000 0000 0000 · solo para la demostración.</p>
    </div>
    <div class="peligro">
      <p><strong>Pero esta página llegó por HTTP.</strong> Tu usuario, tu contraseña y tu
      cookie de sesión viajaron sin cifrar: cualquiera en medio (por ejemplo, mitmproxy)
      los acaba de ver en texto plano.</p>
      <p>Un banco real NUNCA funciona así: usa siempre HTTPS.</p>
    </div>""")


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
