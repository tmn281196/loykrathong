"""Server cho trang Loy Krathong.

- Phục vụ index.html
- GET  /api/people  -> mọi người đã thả hoa, kèm tất cả lời chúc của từng người
- POST /api/people  -> {name, wish, color}
      * tên chưa có  -> tạo bông hoa mới (201)
      * tên đã có    -> không tạo trùng, chỉ thêm lời chúc vào người đó (200)
- Lưu vào SQLite: loy-krathong.db, khóa chính là tên (không phân biệt hoa/thường, gộp khoảng trắng)

Chạy:  python server.py            (mặc định cổng 8780, chỉ nghe trên 127.0.0.1)
"""
import json
import os
import re
import sqlite3
import threading
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
INDEX = os.path.join(ROOT, "index.html")
DB_PATH = os.path.join(ROOT, "loy-krathong.db")
HOST = os.environ.get("HOST", "127.0.0.1")
PORT = int(os.environ.get("PORT", "8780"))

MAX_PEOPLE = 300          # tối đa số người (số bông hoa)
MAX_WISHES_EACH = 30      # tối đa lời chúc mỗi người
MAX_NAME, MAX_WISH = 20, 60
N_COLORS = 8
RATE_LIMIT = 12           # tối đa số lần gửi / IP / phút

db_lock = threading.Lock()
recent_posts = defaultdict(deque)

conn = sqlite3.connect(DB_PATH, check_same_thread=False)
conn.row_factory = sqlite3.Row
with db_lock:
    conn.executescript("""
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS people (
        name_key TEXT PRIMARY KEY,          -- tên đã chuẩn hóa, dùng làm khóa
        name     TEXT NOT NULL,             -- tên hiển thị (lần đầu nhập)
        color    INTEGER NOT NULL DEFAULT 0,
        ts       REAL NOT NULL
    );
    CREATE TABLE IF NOT EXISTS wishes (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        name_key TEXT NOT NULL REFERENCES people(name_key) ON DELETE CASCADE,
        text     TEXT NOT NULL,
        ts       REAL NOT NULL
    );
    CREATE INDEX IF NOT EXISTS wishes_by_person ON wishes(name_key, ts);
    """)
    conn.commit()


def clean(value, limit):
    if not isinstance(value, str):
        return ""
    value = re.sub(r"[\x00-\x1f\x7f]", "", value)
    return re.sub(r"\s+", " ", value).strip()[:limit]


def key_of(name):
    return name.casefold()


def person_dict(row, wishes):
    return {"id": row["name_key"], "name": row["name"], "color": row["color"], "ts": row["ts"],
            "wishes": [{"text": w["text"], "ts": w["ts"]} for w in wishes]}


def list_people():
    with db_lock:
        people = conn.execute("SELECT * FROM people ORDER BY ts").fetchall()
        wishes = conn.execute("SELECT name_key, text, ts FROM wishes ORDER BY ts").fetchall()
    by_key = defaultdict(list)
    for w in wishes:
        by_key[w["name_key"]].append(w)
    return [person_dict(p, by_key[p["name_key"]]) for p in people]


def get_person(key):
    p = conn.execute("SELECT * FROM people WHERE name_key = ?", (key,)).fetchone()
    w = conn.execute("SELECT text, ts FROM wishes WHERE name_key = ? ORDER BY ts", (key,)).fetchall()
    return person_dict(p, w)


class Handler(BaseHTTPRequestHandler):
    server_version = "LoyKrathong/1.1"

    def log_message(self, fmt, *args):
        if self.command == "POST":
            print(f"[{time.strftime('%H:%M:%S')}] {self.client_ip()} {fmt % args}")

    def client_ip(self):
        return self.headers.get("CF-Connecting-IP") or self.client_address[0]

    def send(self, code, body=b"", ctype="application/json; charset=utf-8", cache="no-store"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def send_json(self, code, obj):
        self.send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"))

    def path_only(self):
        return self.path.split("?", 1)[0]

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = self.path_only()
        if path in ("/", "/index.html"):
            with open(INDEX, "rb") as f:
                self.send(200, f.read(), "text/html; charset=utf-8", "no-cache")
        elif path == "/api/people":
            self.send_json(200, list_people())
        elif path == "/favicon.ico":
            self.send(204)
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.path_only() != "/api/people":
            return self.send_json(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > 2048:
            return self.send_json(400, {"error": "bad request"})
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return self.send_json(400, {"error": "bad json"})
        if not isinstance(data, dict):
            return self.send_json(400, {"error": "bad json"})

        ip, now = self.client_ip(), time.time()
        q = recent_posts[ip]
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= RATE_LIMIT:
            return self.send_json(429, {"error": "too many requests"})

        name = clean(data.get("name"), MAX_NAME)
        wish = clean(data.get("wish"), MAX_WISH)
        try:
            color = min(max(int(data.get("color", 0)), 0), N_COLORS - 1)
        except (TypeError, ValueError):
            color = 0
        if not name:
            return self.send_json(400, {"error": "name required"})
        key = key_of(name)

        with db_lock:
            exists = conn.execute("SELECT 1 FROM people WHERE name_key = ?", (key,)).fetchone()
            if not exists:
                if conn.execute("SELECT COUNT(*) FROM people").fetchone()[0] >= MAX_PEOPLE:
                    return self.send_json(409, {"error": "full"})
                conn.execute("INSERT INTO people (name_key, name, color, ts) VALUES (?,?,?,?)", (key, name, color, now))
            if wish:
                count = conn.execute("SELECT COUNT(*) FROM wishes WHERE name_key = ?", (key,)).fetchone()[0]
                if count >= MAX_WISHES_EACH:   # giữ tối đa N lời chúc mới nhất
                    conn.execute("DELETE FROM wishes WHERE id = (SELECT id FROM wishes WHERE name_key = ? ORDER BY ts LIMIT 1)", (key,))
                conn.execute("INSERT INTO wishes (name_key, text, ts) VALUES (?,?,?)", (key, wish, now))
            conn.commit()
            person = get_person(key)
        q.append(now)
        print(f"  + {person['name']}: {wish}" if wish else f"  + {person['name']}")
        self.send_json(200 if exists else 201, person)


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Loy Krathong đang chạy tại http://{HOST}:{PORT}  (Ctrl+C để dừng)")
    print(f"Dữ liệu lời chúc: {DB_PATH}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nĐã dừng server.")
