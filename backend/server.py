"""Development API. Python 3.10+, standard library only. See docs/DEPLOYMENT.md."""
import argparse
import base64
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
from urllib.parse import unquote, urlparse
from core import reduce_events, plan
from bank import validate as validate_bank

ROOT = Path(__file__).resolve().parents[1]
DB = Path(os.environ.get('DENTSTUDY_DB', str(ROOT / 'backend' / 'dentstudy.sqlite3')))
BANK = Path(os.environ.get('DENTSTUDY_BANK', str(ROOT / 'mobile' / 'assets' / 'all_questions.json')))
SUBMISSIONS = Path(os.environ.get(
    'DENTSTUDY_SUBMISSIONS', str(DB.parent / 'question-bank-submissions')))
ADMIN_EMAIL = os.environ.get('DENTSTUDY_ADMIN_EMAIL', '').strip().lower()
MAX_SUBMISSION_BYTES = 12 * 1024 * 1024
MAX_SUBMISSION_REQUEST_BYTES = 16 * 1024 * 1024
ALLOWED_ORIGINS = {
    origin.strip() for origin in os.environ.get('ALLOWED_ORIGINS', '*').split(',')
    if origin.strip()
}


def connect():
    db = sqlite3.connect(DB, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys=ON')
    return db


def initialize():
    DB.parent.mkdir(parents=True, exist_ok=True)
    SUBMISSIONS.mkdir(parents=True, exist_ok=True)
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
        CREATE TABLE IF NOT EXISTS question_bank_submissions(
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL REFERENCES users(id),
          filename TEXT NOT NULL,
          content_bytes INTEGER NOT NULL,
          question_count INTEGER NOT NULL,
          checksum TEXT NOT NULL,
          submitted_at TEXT NOT NULL,
          UNIQUE(user_id, checksum));
        CREATE TABLE IF NOT EXISTS profiles(
          user_id TEXT PRIMARY KEY REFERENCES users(id),
          nickname TEXT NOT NULL DEFAULT '齿间同学',
          avatar TEXT NOT NULL DEFAULT 'book',
          university TEXT NOT NULL DEFAULT '',
          updated_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS question_comments(
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL REFERENCES users(id),
          question_id TEXT NOT NULL,
          body TEXT NOT NULL,
          created_at TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS question_comments_question_created
          ON question_comments(question_id, created_at);
        CREATE TABLE IF NOT EXISTS comment_votes(
          comment_id TEXT NOT NULL REFERENCES question_comments(id),
          user_id TEXT NOT NULL REFERENCES users(id),
          value INTEGER NOT NULL CHECK(value IN (-1,1)),
          PRIMARY KEY(comment_id,user_id));
        ''')
        if 'parent_id' not in {row['name'] for row in db.execute('PRAGMA table_info(question_comments)')}:
            db.execute('ALTER TABLE question_comments ADD COLUMN parent_id TEXT REFERENCES question_comments(id)')


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
        if value.get('mode', 'practice') not in (
                'practice', 'review', 'exam', 'speed', 'speed-review'):
            raise ValueError('无效答题模式')
        return
    raise ValueError('无效事件内容')


def validate_settings(value):
    if not isinstance(value, dict):
        raise ValueError('学习目标必须为 JSON 对象')
    new_limit = value.get('dailyNewLimit')
    review_target = value.get('dailyReviewTarget')
    if isinstance(new_limit, bool) or not isinstance(new_limit, int) or not 0 <= new_limit <= 1_000_000:
        raise ValueError('每日新题上限必须为 0–1,000,000')
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

    def cors_origin(self):
        request_origin = self.headers.get('Origin', '')
        if '*' in ALLOWED_ORIGINS:
            return '*'
        return request_origin if request_origin in ALLOWED_ORIGINS else None

    def do_OPTIONS(self):
        self.send_response(204)
        origin = self.cors_origin()
        if origin:
            self.send_header('Access-Control-Allow-Origin', origin)
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.send_header('Access-Control-Max-Age', '86400')
        self.end_headers()

    def respond(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        origin = self.cors_origin()
        if origin:
            self.send_header('Access-Control-Allow-Origin', origin)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(data)

    def body(self, max_size=2_000_000):
        size = int(self.headers.get('Content-Length', '0'))
        if size < 1 or size > max_size:
            raise ValueError(f'请求为空或超过 {max_size // 1024 // 1024} MB')
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

    def is_admin(self, db, uid):
        if not ADMIN_EMAIL:
            return False
        row = db.execute('SELECT email FROM users WHERE id=?', (uid,)).fetchone()
        return row is not None and row['email'] == ADMIN_EMAIL

    def submissions(self, db, uid):
        admin = self.is_admin(db, uid)
        if admin:
            rows = db.execute('''SELECT s.id,s.filename,s.content_bytes,s.question_count,
                    s.submitted_at,u.email FROM question_bank_submissions s
                    JOIN users u ON u.id=s.user_id ORDER BY s.submitted_at DESC''')
        else:
            rows = db.execute('''SELECT id,filename,content_bytes,question_count,submitted_at
                    FROM question_bank_submissions WHERE user_id=?
                    ORDER BY submitted_at DESC''', (uid,))
        return {'isAdmin': admin, 'submissions': [dict(row) for row in rows]}

    def profile(self, db, uid):
        row = db.execute('''SELECT nickname,avatar,university,updated_at
                FROM profiles WHERE user_id=?''', (uid,)).fetchone()
        return dict(row) if row else {
            'nickname': '齿间同学', 'avatar': 'book', 'university': '',
            'updated_at': None}

    def update_profile(self, db, uid, payload):
        nickname = payload.get('nickname', '')
        avatar = payload.get('avatar', '')
        university = payload.get('university', '')
        if not all(isinstance(value, str)
                   for value in (nickname, avatar, university)):
            raise ValueError('个人资料格式错误')
        nickname, university = nickname.strip(), university.strip()
        if not 1 <= len(nickname) <= 24:
            raise ValueError('昵称长度为 1–24 个字')
        if len(university) > 60:
            raise ValueError('院校名称不能超过 60 个字')
        if avatar.startswith('data:image/png;base64,'):
            try:
                raw = base64.b64decode(avatar.split(',', 1)[1], validate=True)
                if len(raw) > 512 * 1024 or not raw.startswith(b'\x89PNG\r\n\x1a\n'):
                    raise ValueError()
                width, height = int.from_bytes(raw[16:20], 'big'), int.from_bytes(raw[20:24], 'big')
                if not 1 <= width <= 512 or not 1 <= height <= 512:
                    raise ValueError()
            except (ValueError, TypeError):
                raise ValueError('头像须为不超过 512 KB、512 像素的 PNG 图片')
        elif avatar not in ('book', 'tooth', 'science', 'leaf', 'star', 'smile'):
            raise ValueError('头像样式无效')
        updated_at = datetime.now(timezone.utc).isoformat(
            timespec='seconds').replace('+00:00', 'Z')
        db.execute('''INSERT INTO profiles(user_id,nickname,avatar,university,updated_at)
                VALUES(?,?,?,?,?)
                ON CONFLICT(user_id) DO UPDATE SET nickname=excluded.nickname,
                avatar=excluded.avatar, university=excluded.university,
                updated_at=excluded.updated_at''',
                   (uid, nickname, avatar, university, updated_at))
        db.commit()
        return self.profile(db, uid)

    def comments_question_id(self, path):
        prefix = '/v1/questions/'
        suffix = '/comments'
        if not path.startswith(prefix) or not path.endswith(suffix):
            return None
        question_id = unquote(path[len(prefix):-len(suffix)])
        if not question_id or '/' in question_id:
            return None
        return question_id

    def question_comments(self, db, question_id, uid=None):
        if question_id not in {question['id'] for question in questions()}:
            raise ValueError('题目不存在')
        rows = db.execute('''SELECT c.id,c.question_id AS questionId,c.body,c.parent_id AS parentId,
                    c.created_at AS createdAt,
                    COALESCE(v.likes,0) AS likes, COALESCE(v.dislikes,0) AS dislikes,
                    COALESCE(mine.value,0) AS myVote,
                    parent_profile.nickname AS replyTo,
                    COALESCE(p.nickname, '齿间同学') AS nickname,
                    COALESCE(p.avatar, 'book') AS avatar,
                    COALESCE(p.university, '') AS university
                FROM question_comments c
                LEFT JOIN profiles p ON p.user_id=c.user_id
                LEFT JOIN (SELECT comment_id,SUM(value=1) AS likes,SUM(value=-1) AS dislikes
                    FROM comment_votes GROUP BY comment_id) v ON v.comment_id=c.id
                LEFT JOIN comment_votes mine ON mine.comment_id=c.id AND mine.user_id=?
                LEFT JOIN question_comments parent ON parent.id=c.parent_id
                LEFT JOIN profiles parent_profile ON parent_profile.user_id=parent.user_id
                WHERE c.question_id=? ORDER BY c.created_at ASC LIMIT 100''',
                          (uid, question_id))
        count = db.execute('SELECT COUNT(DISTINCT user_id),COUNT(*) FROM question_comments WHERE question_id=?', (question_id,)).fetchone()
        return {'comments': [dict(row) for row in rows], 'participantCount': count[0], 'totalCount': count[1]}

    def vote_comment(self, db, uid, comment_id, payload):
        value = payload.get('value')
        if isinstance(value, bool) or not isinstance(value, int) or value not in (-1, 0, 1):
            raise ValueError('无效的评价')
        if not db.execute('SELECT 1 FROM question_comments WHERE id=?', (comment_id,)).fetchone():
            raise ValueError('评论不存在')
        if value == 0:
            db.execute('DELETE FROM comment_votes WHERE comment_id=? AND user_id=?', (comment_id, uid))
        else:
            db.execute('''INSERT INTO comment_votes VALUES(?,?,?) ON CONFLICT(comment_id,user_id)
                DO UPDATE SET value=excluded.value''', (comment_id, uid, value))
        db.commit()
        counts = db.execute('SELECT COALESCE(SUM(value=1),0),COALESCE(SUM(value=-1),0) FROM comment_votes WHERE comment_id=?', (comment_id,)).fetchone()
        return {'likes': counts[0], 'dislikes': counts[1], 'myVote': value}

    def post_question_comment(self, db, uid, question_id, payload):
        if question_id not in {question['id'] for question in questions()}:
            raise ValueError('题目不存在')
        body = payload.get('body', '')
        if not isinstance(body, str):
            raise ValueError('评论格式错误')
        body = body.strip()
        if not 1 <= len(body) <= 500:
            raise ValueError('评论长度为 1–500 个字')
        parent_id = payload.get('parentId')
        if parent_id is not None and (not isinstance(parent_id, str) or not db.execute(
                'SELECT 1 FROM question_comments WHERE id=? AND question_id=?',
                (parent_id, question_id)).fetchone()):
            raise ValueError('回复的评论不存在或不属于当前题目')
        previous = db.execute('''SELECT created_at FROM question_comments
                WHERE user_id=? ORDER BY created_at DESC LIMIT 1''',
                              (uid,)).fetchone()
        if previous:
            last = datetime.fromisoformat(
                previous['created_at'].replace('Z', '+00:00')).timestamp()
            if time.time() - last < 10:
                raise ValueError('评论发布过快，请稍后再试')
        created_at = datetime.now(timezone.utc).isoformat(
            timespec='seconds').replace('+00:00', 'Z')
        comment_id = secrets.token_urlsafe(12)
        db.execute('''INSERT INTO question_comments(id,user_id,question_id,body,created_at,parent_id)
                VALUES(?,?,?,?,?,?)''',
                   (comment_id, uid, question_id, body, created_at, parent_id))
        db.commit()
        return {'ok': True, 'comment': {
            'id': comment_id, 'questionId': question_id, 'body': body,
            'createdAt': created_at, **self.profile(db, uid)}}

    def admin_users(self, db, uid):
        if not self.is_admin(db, uid):
            raise PermissionError('仅作者账号可查看用户资料')
        rows = db.execute('''SELECT u.id,u.email,
                    COALESCE(p.nickname, '齿间同学') AS nickname,
                    COALESCE(p.avatar, 'book') AS avatar,
                    COALESCE(p.university, '') AS university,
                    p.updated_at AS updatedAt
                FROM users u LEFT JOIN profiles p ON p.user_id=u.id
                ORDER BY COALESCE(p.updated_at, '') DESC, u.email ASC
                LIMIT 1000''')
        return {'users': [dict(row) for row in rows],
                'totalCount': db.execute('SELECT COUNT(*) FROM users').fetchone()[0]}

    def submit_question_bank(self, db, uid, payload):
        filename, content = payload.get('filename'), payload.get('content')
        if (not isinstance(filename, str) or not filename.lower().endswith('.json')
                or len(filename) > 180):
            raise ValueError('仅支持 .json 格式的题库文件')
        if not isinstance(content, str):
            raise ValueError('题库内容必须为 UTF-8 JSON')
        raw = content.encode('utf-8')
        if not raw or len(raw) > MAX_SUBMISSION_BYTES:
            raise ValueError('题库文件不能为空且不能超过 12 MB')
        try:
            bank = json.loads(content)
        except json.JSONDecodeError:
            raise ValueError('题库文件不是有效 JSON')
        errors = validate_bank(bank)
        if errors:
            raise ValueError(f'题库格式不符合模板：{errors[0]}')
        checksum = hashlib.sha256(raw).hexdigest()
        duplicate = db.execute('''SELECT id,question_count,submitted_at
                FROM question_bank_submissions WHERE user_id=? AND checksum=?''',
                               (uid, checksum)).fetchone()
        if duplicate:
            return {'ok': True, 'duplicate': True, 'submission': dict(duplicate)}
        submission_id = secrets.token_urlsafe(18)
        path = SUBMISSIONS / f'{submission_id}.json'
        temporary = SUBMISSIONS / f'.{submission_id}.tmp'
        try:
            temporary.write_bytes(raw)
            os.replace(temporary, path)
            submitted_at = datetime.now(timezone.utc).isoformat(
                timespec='seconds').replace('+00:00', 'Z')
            db.execute('''INSERT INTO question_bank_submissions
                    (id,user_id,filename,content_bytes,question_count,checksum,submitted_at)
                    VALUES(?,?,?,?,?,?,?)''',
                       (submission_id, uid, filename, len(raw),
                        len(bank['questions']), checksum, submitted_at))
            db.commit()
        except Exception:
            temporary.unlink(missing_ok=True)
            path.unlink(missing_ok=True)
            raise
        return {'ok': True, 'duplicate': False, 'submission': {
            'id': submission_id, 'filename': filename, 'content_bytes': len(raw),
            'question_count': len(bank['questions']), 'submitted_at': submitted_at}}

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
            if path == '/v1/question-bank-submissions':
                with connect() as db:
                    uid = self.user(db)
                    return self.respond(200, self.submissions(db, uid))
            if path == '/v1/profile':
                with connect() as db:
                    uid = self.user(db)
                    return self.respond(200, self.profile(db, uid))
            if path == '/v1/admin/users':
                with connect() as db:
                    uid = self.user(db)
                    return self.respond(200, self.admin_users(db, uid))
            question_id = self.comments_question_id(path)
            if question_id is not None:
                with connect() as db:
                    uid = self.user(db) if self.headers.get('Authorization') else None
                    return self.respond(200, self.question_comments(db, question_id, uid))
            self.respond(404, {'error': '接口不存在'})
        except PermissionError as e:
            self.respond(401, {'error': str(e)})
        except (ValueError, TypeError, KeyError, sqlite3.IntegrityError) as e:
            self.respond(400, {'error': str(e)})

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
            path = urlparse(self.path).path
            data = self.body(
                MAX_SUBMISSION_REQUEST_BYTES if path == '/v1/question-bank-submissions'
                else 2_000_000)
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
                        db.execute('''INSERT INTO profiles(user_id,nickname,avatar,university,updated_at)
                                VALUES(?,?,?,?,?)''',
                                   (uid, '齿间同学', 'book', '',
                                    datetime.now(timezone.utc).isoformat(
                                        timespec='seconds').replace('+00:00', 'Z')))
                    else:
                        if not row or not hmac.compare_digest(row['password'], password_hash(password, row['salt'])):
                            raise PermissionError('邮箱或密码错误')
                        uid = row['id']
                    token = secrets.token_urlsafe(40)
                    db.execute('INSERT INTO sessions VALUES(?,?,?)', (hashlib.sha256(token.encode()).hexdigest(), uid, int(time.time()) + 30*86400))
                    db.commit()
                    return self.respond(200, dict(token=token, userId=uid, email=email))
                uid = self.user(db)
                if path.startswith('/v1/comments/') and path.endswith('/vote'):
                    comment_id = path[len('/v1/comments/'):-len('/vote')]
                    return self.respond(200, self.vote_comment(db, uid, comment_id, data))
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
                if path == '/v1/question-bank-submissions':
                    return self.respond(200, self.submit_question_bank(db, uid, data))
                if path == '/v1/profile':
                    return self.respond(200, self.update_profile(db, uid, data))
                question_id = self.comments_question_id(path)
                if question_id is not None:
                    return self.respond(200,
                                        self.post_question_comment(db, uid, question_id, data))
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
