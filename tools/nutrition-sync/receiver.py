"""Single-user snapshot receiver. Run behind HTTPS, or supply TLS_CERT and TLS_KEY."""
from contextlib import closing
import hmac
import json
import os
import re
import sqlite3
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import archive

PATH = "/api/nutrition/snapshot"  # Existing weekly summary; the only GET route.
ARCHIVE = "/api/nutrition/archive"
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024
DB = os.environ["SNAPSHOT_DB"]
READ, WRITE = (os.environ[key] for key in ("READ_TOKEN", "WRITE_TOKEN"))
if not READ or not WRITE or READ == WRITE:
    raise ValueError("Distinct nonempty credentials required")


def invalid_constant(_):
    raise ValueError('Expected JSON number')


class Handler(BaseHTTPRequestHandler):
    timeout = 30

    def authorized(self, token, paths):
        if self.path not in paths:
            self.send_error(404)
            return False
        if not hmac.compare_digest(self.headers.get("Authorization", "").encode(),
                                   ("Bearer " + token).encode()):
            self.send_error(401)
            return False
        return True

    def send_json(self, body):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        # Without a length the body is close-delimited, and curl rejects a TLS close without close_notify.
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.authorized(READ, (PATH,)):
            return
        with closing(archive.connect(DB, 'ro')) as db:
            row = db.execute("SELECT body FROM snapshot WHERE id=1").fetchone()
        if row is None:
            self.send_error(404)
            return
        self.send_json(row[0])

    def int_header(self, name, minimum):
        values = self.headers.get_all(name, [])
        if not values:
            return None
        if len(values) != 1 or not re.fullmatch(r'[0-9]{1,19}', values[0]):
            raise ValueError()
        value = int(values[0])
        if not minimum <= value < 2**63:
            raise ValueError()
        return value

    def do_PUT(self):
        if not self.authorized(WRITE, (PATH, ARCHIVE)):
            return
        full = self.path == ARCHIVE
        try:
            lengths = self.headers.get_all('Content-Length', [])
            if (self.headers.get('Transfer-Encoding') is not None or len(lengths) != 1
                    or not re.fullmatch(r'[0-9]+', lengths[0])):
                raise ValueError()
            length = int(lengths[0])
            if length > (MAX_ARCHIVE_BYTES if full else 131072):
                self.send_error(413 if full else 400)
                return
            body = self.rfile.read(length)
            if len(body) != length:
                raise ValueError()
            data = json.loads(body.decode('utf-8'), parse_constant=invalid_constant)
            if full:
                archive.validate_backup(data)
                revision = self.int_header('X-Assiette-Revision', 1)
                ack = self.int_header('X-Assiette-Ack', 0)
                statuses = self.headers.get_all('X-Assiette-Ack-Status', [])
                if len(statuses) > 1 or (statuses and statuses[0] not in archive.STATUSES):
                    raise ValueError()
                ack_status = statuses[0] if statuses else 'applied'
            else:
                rev = data["revision"]
                if (type(rev) is not int or not 0 < rev < 2**63 or data["version"] != 1
                        or not isinstance(data["days"], list) or len(data["days"]) != 28
                        or 'entries' in data):  # Never accept a backup on the weekly route.
                    raise ValueError()
        except (ValueError, KeyError, TypeError, RecursionError):
            self.send_error(400)
            return
        try:
            with closing(archive.connect(DB)) as db:
                if full:
                    command = archive.receive(db, body, data, revision, ack, ack_status)
                else:
                    with db:
                        changed = db.execute("""INSERT INTO snapshot VALUES(1,?,?)
                            ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,body=excluded.body
                            WHERE excluded.revision > snapshot.revision""", (rev, body)).rowcount
                        accepted = changed or db.execute("SELECT body FROM snapshot WHERE id=1").fetchone()[0] == body
        except archive.StaleArchive:
            self.send_error(409)
            return
        except (OSError, sqlite3.Error):
            self.send_error(503)
            return
        if full:
            self.send_json(json.dumps({'command': command}).encode())
        else:
            self.send_response(204 if accepted else 409)
            self.end_headers()


if __name__ == "__main__":
    os.umask(0o077)
    archive.initialize(DB)
    server = ThreadingHTTPServer((os.getenv("BIND", "127.0.0.1"), int(os.getenv("PORT", "8341"))), Handler)
    if os.getenv("TLS_CERT"):
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(os.environ["TLS_CERT"], os.environ["TLS_KEY"])
        server.socket = tls.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
