"""Development API. Python 3.10+, standard library only. See docs/DEPLOYMENT.md."""
import argparse
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
from core import reduce_events, plan

ROOT = Path(__file__).resolve().parents[1]
DB = Path(os.environ.get('DENTSTUDY_DB', str(ROOT / 'backend' / 'dentstudy.sqlite3')))
BANK = Path(os.environ.get('DENTSTUDY_BANK', str(ROOT / 'mobile' / 'assets' / 'questions.json')))


def connect():
    db = sqlite3.connect(DB, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys=ON')
    return db


def initialize():
    DB.parent.mkdir(parents=True, exist_ok=True)
    with connect() as db:
        db.executescript('''
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, email TEXT UNIQUE NOT NULL,
          salt TEXT NOT NULL, password TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, user_id TEXT NOT NULL
          REFERENCES users(id), expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS events(user_id TEXT NOT NULL REFERENCES users(id),
          id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(user_id,id));
        CREATE TABLE IF NOT EXISTS settings(user_id TEXT PRIMARY KEY REFERENCES users(id),
          daily_new_limit INTEGER NOT NULL DEFAULT 10,
          daily_review_target INTEGER,
          updated_at TEXT NOT NULL);
        ''')


def password_hash(password, salt):
    return hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 260000).hex()


def questions():
    return json.loads(BANK.read_text())['questions']


def validate_event(event, bank):
    if not isinstance(event, dict) or not re.fullmatch(r'[A-Za-z0-9_-]{16,100}', str(event.get('id', ''))):
        raise ValueError('无效事件 ID')
    if event.get('questionId') not in bank:
        raise ValueError('题目不存在')
    try:
        at = datetime.fromisoformat(event['at'].replace('Z', '+00:00'))
        if at.tzinfo is None or at.timestamp() > time.time() + 300:
            raise ValueError()
    except (ValueError, TypeError, KeyError):
        raise ValueError('事件时间必须带时区且不能位于未来')
    event['at'] = at.astimezone(timezone.utc).isoformat(timespec='microseconds').replace('+00:00', 'Z')
    kind, value = event.get('kind'), event.get('value')
    if kind == 'favorite' and isinstance(value, bool):
        return
    if kind == 'note' and isinstance(value, str) and len(value) <= 10000:
        return
    if kind == 'removeWrong' and value is None:
        return
    if kind == 'review' and isinstance(value, dict):
        q = bank[event['questionId']]
        if value.get('grade') not in ('wrong', 'guessed', 'mastered'):
            raise ValueError('无效掌握度')
        if q['answer'] is not None and value.get('answer') not in q['options']:
            raise ValueError('请选择有效答案')
        if q['answer'] is None and (not isinstance(value.get('answer'), str) or not value['answer'].strip() or len(value['answer']) > 20000):
            raise ValueError('请输入主观题作答')
        if value.get('mode', 'practice') not in ('practice', 'review', 'exam'):
            raise ValueError('无效答题模式')
        return
    raise ValueError('无效事件内容')


def validate_settings(value):
    if not isinstance(value, dict):
        raise ValueError('学习目标必须为 JSON 对象')
    new_limit = value.get('dailyNewLimit')
    review_target = value.get('dailyReviewTarget')
    if isinstance(new_limit, bool) or not isinstance(new_limit, int) or not 0 <= new_limit <= 100:
        raise ValueError('每日新题上限必须为 0–100')
    if review_target is not None and (
            isinstance(review_target, bool) or not isinstance(review_target, int)
            or not 0 <= review_target <= 200):
        raise ValueError('每日复习目标必须为无限制或 0–200')
    try:
        updated_at = datetime.fromisoformat(value['updatedAt'].replace('Z', '+00:00'))
        if updated_at.tzinfo is None or updated_at.timestamp() > time.time() + 300:
            raise ValueError()
    except (ValueError, TypeError, KeyError):
        raise ValueError('学习目标更新时间必须带时区且不能位于未来')
    return dict(
        dailyNewLimit=new_limit,
        dailyReviewTarget=review_target,
        updatedAt=updated_at.astimezone(timezone.utc).isoformat(
            timespec='microseconds').replace('+00:00', 'Z'))


class Handler(BaseHTTPRequestHandler):
    server_version = 'DentStudy/0.1'

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.send_header('Access-Control-Max-Age', '86400')
        self.end_headers()

    def respond(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        size = int(self.headers.get('Content-Length', '0'))
        if size < 1 or size > 2_000_000:
            raise ValueError('请求为空或超过 2 MB')
        result = json.loads(self.rfile.read(size))
        if not isinstance(result, dict):
            raise ValueError('请求必须为 JSON 对象')
        return result

    def user(self, db):
        header = self.headers.get('Authorization', '')
        token = header.removeprefix('Bearer ')
        digest = hashlib.sha256(token.encode()).hexdigest()
        row = db.execute('SELECT user_id FROM sessions WHERE token=? AND expires>?', (digest, time.time())).fetchone()
        if row is None:
            raise PermissionError('请先登录，或登录已过期')
        return row['user_id']

    def do_GET(self):
        try:
            path = urlparse(self.path).path
            if path == '/health':
                return self.respond(200, {'status': 'ok', 'version': '0.1.0'})
            if path == '/v1/questions':
                return self.respond(200, json.loads(BANK.read_text()))
            if path == '/v1/state':
                with connect() as db:
                    uid = self.user(db)
                    return self.respond(200, self.snapshot(db, uid))
            self.respond(404, {'error': '接口不存在'})
        except PermissionError as e:
            self.respond(401, {'error': str(e)})

    def snapshot(self, db, uid):
        events = [json.loads(r['payload']) for r in db.execute('SELECT payload FROM events WHERE user_id=?', (uid,))]
        states, attempts = reduce_events(events, questions())
        row = db.execute('SELECT * FROM settings WHERE user_id=?', (uid,)).fetchone()
        settings = None if row is None else dict(
            dailyNewLimit=row['daily_new_limit'],
            dailyReviewTarget=row['daily_review_target'],
            updatedAt=row['updated_at'])
        return dict(events=events, states=states, attempts=attempts,
                    plan=plan(states, questions()), settings=settings)

    def do_POST(self):
        try:
            data = self.body()
            path = urlparse(self.path).path
            with connect() as db:
                if path in ('/v1/auth/register', '/v1/auth/login'):
                    email, password = data.get('email', ''), data.get('password', '')
                    if not isinstance(email, str) or not isinstance(password, str):
                        raise ValueError('账号格式错误')
                    email = email.strip().lower()
                    if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email) or len(email) > 254 or not 10 <= len(password) <= 200:
                        raise ValueError('请输入有效邮箱，密码长度为 10–200 位')
                    row = db.execute('SELECT * FROM users WHERE email=?', (email,)).fetchone()
                    if path.endswith('register'):
                        if row:
                            raise ValueError('该邮箱已注册')
                        uid, salt = secrets.token_hex(16), secrets.token_hex(16)
                        db.execute('INSERT INTO users VALUES(?,?,?,?)', (uid, email, salt, password_hash(password, salt)))
                    else:
                        if not row or not hmac.compare_digest(row['password'], password_hash(password, row['salt'])):
                            raise PermissionError('邮箱或密码错误')
                        uid = row['id']
                    token = secrets.token_urlsafe(40)
                    db.execute('INSERT INTO sessions VALUES(?,?,?)', (hashlib.sha256(token.encode()).hexdigest(), uid, int(time.time()) + 30*86400))
                    db.commit()
                    return self.respond(200, dict(token=token, userId=uid, email=email))
                uid = self.user(db)
                if path == '/v1/auth/logout':
                    token = self.headers.get('Authorization', '').removeprefix('Bearer ')
                    db.execute('DELETE FROM sessions WHERE token=?', (hashlib.sha256(token.encode()).hexdigest(),))
                    db.commit()
                    return self.respond(200, {'ok': True})
                if path == '/v1/sync':
                    incoming = data.get('events')
                    if not isinstance(incoming, list) or len(incoming) > 500:
                        raise ValueError('每次同步最多 500 条事件')
                    incoming_settings = data.get('settings')
                    if incoming_settings is not None:
                        incoming_settings = validate_settings(incoming_settings)
                    bank = {q['id']: q for q in questions()}
                    for event in incoming:
                        validate_event(event, bank)
                        payload = json.dumps(event, ensure_ascii=False, sort_keys=True)
                        existing = db.execute('SELECT payload FROM events WHERE user_id=? AND id=?', (uid, event['id'])).fetchone()
                        if existing and existing['payload'] != payload:
                            raise ValueError('事件 ID 冲突，请保留原始事件重试')
                        db.execute('INSERT OR IGNORE INTO events VALUES(?,?,?)', (uid, event['id'], payload))
                    if incoming_settings is not None:
                        existing = db.execute(
                            'SELECT updated_at FROM settings WHERE user_id=?', (uid,)).fetchone()
                        if existing is None or incoming_settings['updatedAt'] > existing['updated_at']:
                            db.execute('''INSERT INTO settings
                              (user_id,daily_new_limit,daily_review_target,updated_at)
                              VALUES(?,?,?,?)
                              ON CONFLICT(user_id) DO UPDATE SET
                                daily_new_limit=excluded.daily_new_limit,
                                daily_review_target=excluded.daily_review_target,
                                updated_at=excluded.updated_at''',
                              (uid, incoming_settings['dailyNewLimit'],
                               incoming_settings['dailyReviewTarget'],
                               incoming_settings['updatedAt']))
                    db.commit()
                    return self.respond(200, self.snapshot(db, uid))
                self.respond(404, {'error': '接口不存在'})
        except PermissionError as e:
            self.respond(401, {'error': str(e)})
        except (ValueError, TypeError, KeyError, sqlite3.IntegrityError) as e:
            self.respond(400, {'error': str(e)})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8787)
    args = parser.parse_args()
    initialize()
    print(f'DentStudy API http://{args.host}:{args.port}', flush=True)
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
