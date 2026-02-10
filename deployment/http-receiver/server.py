"""Minimal HTTP server that receives pushed data and stores it for retrieval."""

import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

STORE_PATH = "/tmp/received-data.json"


def read_chunked(rfile):
    """Read a chunked transfer-encoded body."""
    data = b""
    while True:
        line = rfile.readline().strip()
        chunk_size = int(line, 16)
        if chunk_size == 0:
            rfile.readline()  # trailing CRLF
            break
        data += rfile.read(chunk_size)
        rfile.readline()  # trailing CRLF after chunk
    return data


class Handler(BaseHTTPRequestHandler):
    def _read_body(self):
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            return read_chunked(self.rfile)
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length else b""

    def do_POST(self):
        body = self._read_body()
        self.log_message("POST received: %d bytes", len(body))
        with open(STORE_PATH, "wb") as f:
            f.write(body)
        self.send_response(200)
        self.end_headers()

    def do_PUT(self):
        body = self._read_body()
        self.log_message("PUT received: %d bytes", len(body))
        with open(STORE_PATH, "wb") as f:
            f.write(body)
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        try:
            with open(STORE_PATH, "rb") as f:
                data = f.read()
        except FileNotFoundError:
            data = b""
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print(f"[http-receiver] {fmt % args}", flush=True)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 4000), Handler)
    print("[http-receiver] Listening on port 4000", flush=True)
    server.serve_forever()
