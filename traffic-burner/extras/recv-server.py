#!/usr/bin/env python3
"""极简上传接收端 — 配合 traffic-burner 的 upload 模式 (-m upload) 使用。

- 接收 POST/PUT (chunked 或 Content-Length), 内容直接丢弃
- 返回 200 + 实际收到的字节数
- 用法: python3 recv-server.py [端口]   (默认 18080)
- 然后:  traffic-burner -m upload -u "http://<本机IP>:18080/up"
"""
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass  # 用我们自己的输出来报告

    def _drain(self):
        te = (self.headers.get("Transfer-Encoding") or "").lower()
        if "chunked" in te:
            n = 0
            while True:
                line = self.rfile.readline().strip()
                if not line:
                    break
                if b";" in line:
                    line = line.split(b";", 1)[0]
                try:
                    size = int(line, 16)
                except ValueError:
                    break
                if size == 0:
                    self.rfile.readline()
                    break
                left = size
                while left > 0:
                    chunk = self.rfile.read(min(65536, left))
                    if not chunk:
                        break
                    n += len(chunk)
                    left -= len(chunk)
                self.rfile.read(2)  # 块尾 CRLF
            return n
        left = int(self.headers.get("Content-Length") or 0)
        n = 0
        while left > 0:
            chunk = self.rfile.read(min(65536, left))
            if not chunk:
                break
            n += len(chunk)
            left -= len(chunk)
        return n

    def _handle(self):
        n = self._drain()
        body = str(n).encode()
        try:
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            print(f"{self.command} {self.path} -> received {n} bytes", flush=True)
        except OSError:
            print(f"{self.command} {self.path} -> received {n} bytes (client gone)", flush=True)

    do_POST = _handle
    do_PUT = _handle


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"listening on 0.0.0.0:{port}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
