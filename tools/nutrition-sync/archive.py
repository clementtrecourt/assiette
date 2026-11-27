#!/usr/bin/env python3
"""Local Assiette archive CLI. Reads and writes SNAPSHOT_DB directly; needs no network token.

Reading: `export` prints the latest full archive (same JSON as the app's backup export).
Writing: `set` / `clear` change one weekday calorie target; `replace FILE --revision N` makes
the iPhone replace all of its data with FILE (an edited export). The iPhone applies a
replacement only when nothing changed on it since revision N, otherwise the command ends
as `conflict` and nothing is touched: export again and redo the edit.
"""
import argparse
from contextlib import closing
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import sys

ARRAYS = ('entries', 'weights', 'water', 'customFoods', 'favorites', 'exceptions', 'checkIns', 'healthDays')
MAX_REPLACEMENT_BYTES = 31 * 1024 * 1024  # The response must stay under the app's archive budget.
KEEP_DAILY = 60
KEEP_BEFORE_REPLACE = 20
# The app decodes dates with ISO 8601 "internet date time": no fractional seconds.
SWIFT_DATE = re.compile(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})')
DATE_FIELDS = {'entries': ('day', 'createdAt'), 'weights': ('date',), 'water': ('day', 'createdAt'),
               'customFoods': ('createdAt',), 'favorites': ('createdAt',), 'exceptions': ('start', 'end'),
               'checkIns': ('date',), 'healthDays': ('day',)}
PROFILE_DATES = ('createdAt', 'lastCheckInDate', 'expenditureAnchorDate')
# ProgramPreferences has no defaults when decoded: a missing key would drop the whole object.
PROGRAM_KEYS = ('diet', 'floor', 'training', 'distribution', 'highDays', 'shiftPercent', 'protein')
STATUSES = ('applied', 'conflict', 'invalid')


def validate_backup(data):
    if (not isinstance(data, dict) or type(data.get('version')) is not int or data['version'] != 1
            or data.get('app') != 'Assiette' or not isinstance(data.get('exportedAt'), str)
            or not all(isinstance(data.get(key), list) for key in ARRAYS)
            or not isinstance(data.get('programPreferences'), dict)
            or (data.get('profile') is not None and not isinstance(data['profile'], dict))
            or not isinstance(data.get('settings', {}), dict)):
        raise ValueError('Invalid ProfileBackup')
    # Swift JSONEncoder.iso8601 includes the time and zone, optionally fractional seconds.
    stamp = data['exportedAt']
    iso = stamp[:-1] + '+00:00' if stamp.endswith('Z') else stamp
    if 'T' not in stamp or datetime.fromisoformat(iso).tzinfo is None:
        raise ValueError('Expected ISO timestamp with time zone')
    targets = data.get('weekdayCalorieTargets', {})
    if not isinstance(targets, dict) or any(
            day not in ('1', '2', '3', '4', '5', '6', '7') or type(kcal) is not int
            or not 800 <= kcal <= 10000 for day, kcal in targets.items()):
        raise ValueError('Invalid weekday calorie targets')


def validate_replacement(data):
    """Stricter than uploads: everything the app will have to decode."""
    validate_backup(data)
    problems = []
    for key, fields in DATE_FIELDS.items():
        for i, row in enumerate(data[key]):
            if not isinstance(row, dict):
                problems.append(f'{key}[{i}] is not an object')
                continue
            for field in fields:
                if not isinstance(row.get(field), str) or not SWIFT_DATE.fullmatch(row[field]):
                    problems.append(f'{key}[{i}].{field}')
    missing = [k for k in PROGRAM_KEYS if k not in data['programPreferences']]
    if missing:
        problems.append('programPreferences needs ' + ', '.join(missing))
    for field in PROFILE_DATES:
        value = (data.get('profile') or {}).get(field)
        if value is not None and (not isinstance(value, str) or not SWIFT_DATE.fullmatch(value)):
            problems.append(f'profile.{field}')
    if problems:
        raise ValueError('Dates must look like 2026-11-27T08:30:00Z (no fractional seconds). Fix: '
                         + ', '.join(problems[:10]))


def fingerprint(data):
    """Content identity of an archive, independent of export time, key order and row order."""
    content = {k: v for k, v in data.items() if k != 'exportedAt'}
    for key in ARRAYS:
        if isinstance(content.get(key), list):
            content[key] = sorted(content[key], key=lambda row: json.dumps(row, sort_keys=True))
    prefs = content.get('programPreferences')
    if isinstance(prefs, dict) and isinstance(prefs.get('highDays'), list):
        content['programPreferences'] = dict(prefs, highDays=sorted(prefs['highDays']))
    canonical = json.dumps(content, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
    return hashlib.sha256(canonical.encode()).hexdigest()


def connect(path, mode='rw'):
    path = Path(path).absolute()
    if mode == 'rwc':
        # Create privately even when the shell's umask is permissive.
        fd = os.open(path, os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        os.close(fd)
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
        raise PermissionError('SNAPSHOT_DB must be a private regular file (chmod 600)')
    return sqlite3.connect(f'{path.as_uri()}?mode={mode}', uri=True)


def initialize(path):
    with closing(connect(path, 'rwc')) as db, db:
        db.executescript('''
            BEGIN;
            CREATE TABLE IF NOT EXISTS snapshot(id INTEGER PRIMARY KEY, revision INTEGER, body BLOB);
            CREATE TABLE IF NOT EXISTS archive(
                id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER, exported_at TEXT NOT NULL, body BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS command(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL CHECK(kind IN ('weekday', 'replace')),
                weekday INTEGER CHECK(weekday BETWEEN 1 AND 7),
                kcal INTEGER CHECK(kcal BETWEEN 800 AND 10000),
                body BLOB,
                base TEXT,
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
                delivered INTEGER NOT NULL DEFAULT 0,
                status TEXT CHECK(status IN ('applied', 'conflict', 'invalid')),
                done_at TEXT,
                CHECK((kind = 'weekday' AND weekday IS NOT NULL AND body IS NULL)
                      OR (kind = 'replace' AND body IS NOT NULL AND base IS NOT NULL)));
            CREATE TABLE IF NOT EXISTS history(
                id INTEGER PRIMARY KEY AUTOINCREMENT, reason TEXT NOT NULL, day TEXT NOT NULL,
                revision INTEGER, exported_at TEXT NOT NULL, body BLOB NOT NULL);
            COMMIT;
        ''')
        # First archive release queued weekday commands in their own table.
        if db.execute("SELECT 1 FROM sqlite_master WHERE name='weekday_command'").fetchone():
            db.execute('''INSERT INTO command(id, kind, weekday, kcal, delivered)
                          SELECT id, 'weekday', weekday, kcal, delivered FROM weekday_command''')
            db.execute('DROP TABLE weekday_command')


class StaleArchive(Exception):
    pass


def now():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def keep(db, reason, revision, exported_at, body):
    day = exported_at[:10]
    if reason == 'daily':
        db.execute("DELETE FROM history WHERE reason='daily' AND day=?", (day,))
    db.execute('INSERT INTO history(reason, day, revision, exported_at, body) VALUES(?,?,?,?,?)',
               (reason, day, revision, exported_at, body))
    for pattern, count in (('daily', KEEP_DAILY), ('before-replace%', KEEP_BEFORE_REPLACE)):
        db.execute('''DELETE FROM history WHERE reason LIKE ? AND id NOT IN
                      (SELECT id FROM history WHERE reason LIKE ? ORDER BY id DESC LIMIT ?)''',
                   (pattern, pattern, count))


def receive(db, body, data, revision, ack, ack_status='applied'):
    # Snapshot, acknowledgement and selection for the response commit together. Once
    # revision tracking starts, a delayed unversioned upload must not bypass it.
    with db:
        accepted = db.execute('''INSERT INTO archive VALUES(1,?,?,?) ON CONFLICT(id) DO UPDATE SET
            revision=excluded.revision, exported_at=excluded.exported_at, body=excluded.body
            WHERE archive.revision IS NULL OR excluded.revision > archive.revision
               OR (excluded.revision = archive.revision AND excluded.body = archive.body)''',
                              (revision, data['exportedAt'], body)).rowcount
        if not accepted:
            raise StaleArchive()
        keep(db, 'daily', revision, data['exportedAt'], body)
        if ack:
            db.execute('UPDATE command SET status=?, done_at=? WHERE id=? AND delivered=1 AND status IS NULL',
                       (ack_status, now(), ack))
        state = None
        while True:
            row = db.execute('''SELECT id, kind, weekday, kcal, body, base, delivered FROM command
                                WHERE status IS NULL ORDER BY id LIMIT 1''').fetchone()
            if not row:
                return None
            cid, kind, weekday, kcal, payload, base, delivered = row
            if kind == 'weekday':
                db.execute('UPDATE command SET delivered=1 WHERE id=?', (cid,))
                return {'id': cid, 'type': 'weekday', 'weekday': weekday, 'kcal': kcal}
            replacement = json.loads(payload)
            state = state or fingerprint(data)
            if state != base:
                # Already the replacement: applied, its acknowledgement was lost. Otherwise the phone
                # changed since the export, and its newer data wins.
                done = 'applied' if delivered and state == fingerprint(replacement) else 'conflict'
                db.execute('UPDATE command SET status=?, done_at=? WHERE id=?', (done, now(), cid))
                continue
            if not delivered:
                keep(db, f'before-replace #{cid}', revision, data['exportedAt'], body)
                db.execute('UPDATE command SET delivered=1 WHERE id=?', (cid,))
            return {'id': cid, 'type': 'replace', 'backup': replacement}


def describe(row):
    cid, kind, weekday, kcal, created, delivered, status, done = row
    item = dict(id=cid, type=kind, created=created, delivered=bool(delivered), status=status or 'pending')
    if kind == 'weekday':
        item.update(weekday=weekday, kcal=kcal)
    if done:
        item['done'] = done
    return item


COMMAND_COLUMNS = 'id, kind, weekday, kcal, created_at, delivered, status, done_at'


def cli():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--db', default=os.getenv('SNAPSHOT_DB'), help='receiver SQLite path (default: SNAPSHOT_DB)')
    subs = parser.add_subparsers(dest='action', required=True)
    export = subs.add_parser('export', help='write the latest full archive JSON to stdout (revision on stderr)')
    export.add_argument('--history', type=int, metavar='ID', help='export an older version listed by `history`')
    subs.add_parser('status', help='show archive metadata and pending command count')
    subs.add_parser('pending', help='list commands not yet applied by the iPhone, in delivery order')
    log = subs.add_parser('log', help='list recent commands with their outcome')
    log.add_argument('--limit', type=int, default=20)
    subs.add_parser('history', help='list stored archive versions (daily, and before each replacement)')
    for action, help_text in [('set', 'queue a weekday kcal target'), ('clear', 'queue removal of a weekday target')]:
        sub = subs.add_parser(action, help=help_text)
        sub.add_argument('weekday', type=int, choices=range(1, 8), help='ISO weekday, Monday=1')
        if action == 'set':
            sub.add_argument('kcal', type=int, help='800 to 10000 inclusive')
    replace = subs.add_parser('replace', help='queue a full replacement of the iPhone data with FILE')
    replace.add_argument('file', help='edited export, or - for stdin')
    replace.add_argument('--revision', type=int, required=True,
                         help='revision of the archive FILE was edited from (printed by export and status)')
    subs.add_parser('cancel', help='drop every command the iPhone has not received yet')
    args = parser.parse_args()
    if not args.db:
        parser.error('set SNAPSHOT_DB or supply --db PATH')
    if args.action == 'set' and not 800 <= args.kcal <= 10000:
        parser.error('kcal must be 800 to 10000 inclusive')
    replacement = None
    if args.action == 'replace':
        raw = sys.stdin.buffer.read() if args.file == '-' else Path(args.file).read_bytes()
        try:
            replacement = json.loads(raw.decode('utf-8'))
            validate_replacement(replacement)
        except (ValueError, UnicodeDecodeError) as exc:
            sys.exit(f'Invalid replacement: {exc}')
        payload = json.dumps(replacement, ensure_ascii=False, separators=(',', ':')).encode()
        if len(payload) > MAX_REPLACEMENT_BYTES:
            sys.exit('Replacement too large')
    editing = args.action in ('set', 'clear', 'replace', 'cancel')
    with closing(connect(args.db, 'rw' if editing else 'ro')) as db, db:
        if args.action == 'export':
            if args.history is None:
                row = db.execute('SELECT body, revision FROM archive WHERE id=1').fetchone()
            else:
                row = db.execute('SELECT body, revision FROM history WHERE id=?', (args.history,)).fetchone()
            if not row:
                sys.exit('No such archive' if args.history else 'No archive received yet')
            sys.stdout.buffer.write(row[0])
            sys.stdout.flush()
            print(f'revision {row[1]}', file=sys.stderr)
            return
        if args.action == 'status':
            row = db.execute('SELECT exported_at, length(body), revision FROM archive WHERE id=1').fetchone()
            result = {'archive': dict(zip(('exportedAt', 'bytes', 'revision'), row)) if row else None,
                      'pending': db.execute('SELECT count(*) FROM command WHERE status IS NULL').fetchone()[0]}
        elif args.action == 'pending':
            result = [describe(r) for r in db.execute(
                f'SELECT {COMMAND_COLUMNS} FROM command WHERE status IS NULL ORDER BY id')]
        elif args.action == 'log':
            result = [describe(r) for r in db.execute(
                f'SELECT {COMMAND_COLUMNS} FROM command ORDER BY id DESC LIMIT ?', (args.limit,))]
        elif args.action == 'history':
            result = [dict(id=i, reason=r, exportedAt=e, revision=v, bytes=n) for i, r, e, v, n in db.execute(
                'SELECT id, reason, exported_at, revision, length(body) FROM history ORDER BY id DESC')]
        elif args.action == 'cancel':
            cur = db.execute("DELETE FROM command WHERE status IS NULL AND delivered=0")
            result = {'cancelled': cur.rowcount}
        elif args.action == 'replace':
            row = db.execute('SELECT revision, body FROM archive WHERE id=1').fetchone()
            if not row:
                sys.exit('No archive received yet')
            if row[0] != args.revision:
                sys.exit(f'The iPhone sent newer data (revision {row[0]}): export again and redo the edit')
            base = fingerprint(json.loads(row[1]))
            if fingerprint(replacement) == base:
                sys.exit('Nothing to change: FILE has the same content as the archive')
            cur = db.execute("INSERT INTO command(kind, body, base) VALUES('replace', ?, ?)", (payload, base))
            result = dict(id=cur.lastrowid, type='replace', status='pending')
        else:
            kcal = getattr(args, 'kcal', None)
            cur = db.execute("INSERT INTO command(kind, weekday, kcal) VALUES('weekday', ?, ?)", (args.weekday, kcal))
            result = dict(id=cur.lastrowid, type='weekday', weekday=args.weekday, kcal=kcal)
    print(json.dumps(result))


if __name__ == '__main__':
    os.umask(0o077)
    try:
        cli()
    except (OSError, sqlite3.Error) as exc:
        sys.exit(f'Archive CLI: {exc}')
