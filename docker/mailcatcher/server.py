"""
Minimal mailcatcher: an SMTP receiver + HTTP inbox for local development.

* SMTP (default 0.0.0.0:1025) accepts mail from any client. No relaying,
  messages are kept in process memory only.
* HTTP (default 0.0.0.0:8025) renders a simple inbox so OTPs can be read.
Dev-only: never used in production. Pure standard library, no dependencies.
"""

import asyncio
import os
import threading
from datetime import datetime, timezone
from email import message_from_bytes
from email.policy import default as default_policy
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SMTP_PORT = int(os.getenv("SMTP_PORT", "1025"))
HTTP_PORT = int(os.getenv("HTTP_PORT", "8025"))
HOST = os.getenv("BIND_HOST", "0.0.0.0")

_lock = threading.Lock()
MAILS = []
OUTBOX_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "outbox")
OUTBOX_FILE = os.path.join(OUTBOX_DIR, "inbox.jsonl")


def add_mail(data_bytes, env_from, recipients):
    os.makedirs(OUTBOX_DIR, exist_ok=True)
    msg = message_from_bytes(data_bytes, policy=default_policy)
    subject = str(msg.get("Subject", "(no subject)"))
    frm = str(msg.get("From", env_from or "(unknown)"))
    to = ", ".join(recipients) if recipients else str(msg.get("To", ""))
    record = {
        "id": len(MAILS),
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        "from": frm,
        "to": to,
        "subject": subject,
        "size": len(data_bytes),
        "raw": data_bytes.decode("utf-8", errors="replace"),
    }
    with _lock:
        MAILS.append(record)
        import json as _json
        with open(OUTBOX_FILE, "a", encoding="utf-8") as fh:
            fh.write(_json.dumps(record) + "\n")
            fh.flush()


async def handle_smtp(reader, writer):
    async def reply(code, text):
        writer.write(f"{code} {text}\r\n".encode("utf-8", "replace"))
        await writer.drain()

    async def reply_lines(lines):
        # Proper multi-line SMTP reply: continuation lines end with "-"
        # (e.g. "250-AUTH"), the final line uses a space (e.g. "250 OK").
        for i, (code, text) in enumerate(lines):
            sep = "-" if i < len(lines) - 1 else " "
            writer.write(f"{code}{sep}{text}\r\n".encode("utf-8", "replace"))
        await writer.drain()

    data_mode = False
    env_from = None
    recipients = []
    buf = []
    try:
        await reply(220, "mailcatcher dev SMTP ready")
        while True:
            raw = await reader.readline()
            if not raw:
                break
            line = raw.decode("utf-8", "replace").rstrip("\r\n")
            if data_mode:
                if line == ".":
                    data_mode = False
                    # buf lines already include their CRLF terminators.
                    payload = b"".join(buf)
                    add_mail(payload, env_from, recipients)
                    buf = []
                    await reply(250, "OK message accepted")
                else:
                    buf.append(raw)
                continue
            if not line:
                continue
            upper = line.upper()
            if upper.startswith("EHLO") or upper.startswith("HELO"):
                await reply_lines([
                    (250, "mailcatcher dev SMTP ready"),
                    (250, "AUTH PLAIN LOGIN"),
                    (250, "OK"),
                ])
            elif upper.startswith("AUTH"):
                await reply(235, "Authentication successful")
            elif upper.startswith("STARTTLS"):
                # STARTTLS not implemented; refuse cleanly rather than corrupt
                # the TLS handshake. Not used when MAIL_SMTP_STARTTLS=false.
                await reply(502, "5.5.2 STARTTLS not supported")
            elif upper.startswith("MAIL FROM"):
                env_from = line
                await reply(250, "OK")
            elif upper.startswith("RCPT TO"):
                recipients.append(line)
                await reply(250, "OK")
            elif upper.startswith("DATA"):
                data_mode = True
                await reply(354, "end data with <CR><LF>.<CR><LF>")
            elif upper.startswith("RSET") or upper.startswith("NOOP"):
                await reply(250, "OK")
            elif upper.startswith("QUIT"):
                await reply(221, "Bye")
                break
            else:
                await reply(250, "OK")
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def serve_smtp():
    server = await asyncio.start_server(handle_smtp, HOST, SMTP_PORT)
    print(f"mailcatcher: SMTP listening on {HOST}:{SMTP_PORT}")
    async with server:
        await server.serve_forever()


def _all_mails_snapshot():
    with _lock:
        return list(reversed(MAILS))


class InboxHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, body):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path
        if path in ("/", "/index.html"):
            self._send(200, self.render_index())
        elif path.startswith("/msg/"):
            try:
                mid = int(path[len("/msg/"):])
            except ValueError:
                mid = -1
            mail = next((m for m in _all_mails_snapshot() if m["id"] == mid), None)
            self._send(200, self.render_message(mail) if mail else "not found", )
        else:
            self._send(404, "not found")

    @staticmethod
    def _esc(value):
        import html as _h
        return _h.escape(str(value))

    def render_index(self):
        mails = _all_mails_snapshot()
        rows = "".join(
            f'<tr><td>{self._esc(m["ts"])}</td>'
            f'<td>{self._esc(m["from"])}</td>'
            f'<td>{self._esc(m["subject"])}</td>'
            f'<td><a href="/msg/{m["id"]}">view</a></td></tr>'
            for m in mails
        )
        return f"""<!doctype html><html><head><meta charset="utf-8">
<title>Synora Mailcatcher</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{{font-family:sans-serif;max-width:900px;margin:24px auto;padding:0 12px}}
table{{border-collapse:collapse;width:100%;font-size:14px}}
th,td{{border:1px solid #ddd;padding:6px 8px;text-align:left;vertical-align:top}}
th{{background:#f4f4f4}}td:nth-child(3){{word-break:break-word}}</style>
</head><body>
<h1>Synora Mailcatcher</h1>
<p>{len(mails)} message(s) received. Open this page after requesting a password reset.</p>
<table><thead><tr><th>Time</th><th>From</th><th>Subject</th><th></th></tr></thead>
<tbody>{rows or '<tr><td colspan="4">No messages yet.</td></tr>'}
</tbody></table>
<p style="font-size:12px;color:#777">Dev-only SMTP inbox on port {HTTP_PORT}.</p>
</body></html>"""

    def render_message(self, m):
        return f"""<!doctype html><html><head><meta charset="utf-8">
<title>{self._esc(m["subject"])}</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{{font-family:sans-serif;max-width:900px;margin:24px auto;padding:0 12px}}
pre{{background:#f7f7f7;border:1px solid #ddd;padding:12px;overflow:auto;font-size:13px;white-space:pre-wrap;word-break:break-word}}
.h{{color:#555;font-size:13px}}</style>
</head><body>
<h1>{self._esc(m["subject"])}</h1>
<p class="h">From: {self._esc(m["from"])}<br>To: {self._esc(m["to"])}<br>At: {self._esc(m["ts"])} ({m["size"]} bytes)</p>
<p><a href="/">&larr; Back to inbox</a></p>
<pre>{self._esc(m["raw"])}</pre>
</body></html>"""


def serve_http():
    InboxHandler.protocol_version = "HTTP/1.0"
    InboxHandler.timeout = 10
    httpd = ThreadingHTTPServer((HOST, HTTP_PORT), InboxHandler)
    httpd.daemon_threads = True
    httpd.serve_forever()


def main():
    http_thread = threading.Thread(target=serve_http, daemon=True)
    http_thread.start()
    print(f"mailcatcher: HTTP inbox listening on http://{HOST}:{HTTP_PORT}")
    try:
        asyncio.run(serve_smtp())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
