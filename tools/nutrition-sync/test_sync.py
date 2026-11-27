"""Loopback HTTP + local CLI integration tests; never use the deployed receiver or its DB."""
import datetime as dt
import http.client
import json
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import archive

HERE = Path(__file__).resolve().parent
WEEK = '/api/nutrition/snapshot'
FULL = '/api/nutrition/archive'
PROGRAM = {'diet': 'balanced', 'floor': 'standard', 'training': 'both', 'distribution': 'even',
           'highDays': [5, 6], 'shiftPercent': 20, 'protein': 'moderate'}


def backup(**changes):
    return dict({'version': 1, 'app': 'Assiette', 'exportedAt': '2026-01-08T14:00:00.123Z',
                 'entries': [], 'weights': [], 'water': [], 'customFoods': [], 'favorites': [],
                 'exceptions': [], 'checkIns': [], 'healthDays': [], 'programPreferences': {},
                 'weekdayCalorieTargets': {'1': 1500}, 'profile': {'name': 'private example'}}, **changes)


class Integration(unittest.TestCase):
    def setUp(self):
        folder = self.enter_tempdir()
        self.path = Path(folder) / 'report.sqlite'
        self.env = {'SNAPSHOT_DB': str(self.path), 'READ_TOKEN': 'reader', 'WRITE_TOKEN': 'writer'}
        # receiver reads its deployment environment at import time. Never inherit real credentials.
        with patch.dict(os.environ, self.env, clear=True):
            import receiver
        self.patch = patch.multiple(receiver, DB=str(self.path), READ='reader', WRITE='writer')
        self.patch.start()
        self.addCleanup(self.patch.stop)
        # Seed the original schema and an existing weekly row to exercise upgrade-in-place.
        self.week = json.dumps({'version': 1, 'revision': 20, 'days': [{}] * 28}).encode()
        self.path.touch(mode=0o600)
        with sqlite3.connect(self.path) as db:
            db.execute('CREATE TABLE snapshot(id INTEGER PRIMARY KEY, revision INTEGER, body BLOB)')
            db.execute('INSERT INTO snapshot VALUES(1,20,?)', (self.week,))
        db.close()
        archive.initialize(self.path)

        class QuietHandler(receiver.Handler):
            def log_message(self, *args):
                pass

        self.server = receiver.ThreadingHTTPServer(('127.0.0.1', 0), QuietHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': 0.01})
        self.thread.start()
        self.addCleanup(self.stop_server)

    def enter_tempdir(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        return tmp.name

    def stop_server(self):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()

    def request(self, method, path, token=None, body=None, headers=None):
        headers = dict(headers or {})
        if token:
            headers['Authorization'] = 'Bearer ' + token
        conn = http.client.HTTPConnection(*self.server.server_address, timeout=3)
        try:
            conn.request(method, path, body, headers)
            response = conn.getresponse()
            return response.status, response.read()
        finally:
            conn.close()

    def put(self, data, **headers):
        body = data if isinstance(data, bytes) else json.dumps(data).encode()
        return self.request('PUT', FULL, 'writer', body, headers)

    def cli(self, *args, success=True, env=None):
        proc = subprocess.run([sys.executable, '-B', HERE / 'archive.py', *map(str, args)],
                              env=self.env if env is None else env, capture_output=True, timeout=4)
        if success:
            self.assertEqual(proc.returncode, 0, proc.stderr)
        else:
            self.assertNotEqual(proc.returncode, 0)
        return proc.stdout

    def command(self, data, **headers):
        code, body = self.put(data, **headers)
        self.assertEqual(code, 200, body)
        result = json.loads(body)
        self.assertEqual(set(result), {'command'})
        return result['command']

    def test_archive_is_local_only_and_weekly_contract_survives(self):
        self.cli('export', success=False)
        raw = json.dumps(backup(), indent=2).encode()
        self.assertIsNone(self.command(raw))
        for token in ('reader', 'writer', None):
            self.assertEqual(self.request('GET', FULL, token)[0], 404)
        for path in (FULL, WEEK):
            for token in ('reader', None):
                self.assertEqual(self.request('PUT', path, token, raw)[0], 401)
        self.assertEqual(self.request('GET', WEEK, 'writer')[0], 401)
        self.assertEqual(self.request('GET', WEEK, 'reader'), (200, self.week))
        self.assertEqual(self.request('PUT', WEEK, 'writer', self.week)[0], 204)
        self.assertEqual(self.request('PUT', WEEK, 'writer', raw)[0], 400)
        self.assertEqual(self.request('PUT', WEEK, 'writer', json.dumps(backup(revision=21, days=[{}] * 28)))[0], 400)
        stale = self.week.replace(b'20', b'19')
        self.assertEqual(self.request('PUT', WEEK, 'writer', stale)[0], 409)
        days = [{'date': (dt.date(2026, 1, 1) + dt.timedelta(days=i)).isoformat(), 'status': 'missing'} for i in range(28)]
        newer = json.dumps(dict(version=1, revision=21, days=days, generatedAt='2026-01-28T00:00:00Z')).encode()
        self.assertEqual(self.request('PUT', WEEK, 'writer', newer)[0], 204)
        self.assertEqual(self.request('GET', WEEK, 'reader'), (200, newer))
        weekfile = self.path.with_suffix('.json')
        weekfile.write_bytes(newer)
        summary = subprocess.check_output([sys.executable, HERE / 'weekly_summary.py', '--file', weekfile,
                                           '--week-end', '2026-01-25', '--json'], env={}, timeout=4)
        self.assertEqual(json.loads(summary)['week']['days'], 7)
        self.assertEqual(self.cli('--db', self.path, 'export', env={}), raw)
        self.assertNotIn(b'private example', self.cli('status'))

    def test_fifo_ack_revision_and_atomicity(self):
        first = json.loads(self.cli('set', 1, 800))
        second = json.loads(self.cli('clear', 7))
        self.assertEqual(second['kcal'], None)
        rev = 'X-Assiette-Revision'
        ack = 'X-Assiette-Ack'
        before = backup()
        after = backup(profile=None, weights=[{'kg': 75}])
        self.assertEqual(self.command(before, **{rev: '12', ack: str(second['id'])}), first)
        self.assertEqual(self.command(before, **{rev: '12'}), first)  # lost response, same revision
        for headers in ({rev: '11'}, {rev: '12'}, {}):
            self.assertEqual(self.put(after, **headers, **{ack: str(first['id'])})[0], 409)
        self.assertEqual(json.loads(self.cli('export')), before)
        self.assertEqual([c['delivered'] for c in json.loads(self.cli('pending'))], [True, False])
        archive.initialize(self.path)  # startup is idempotent, even with a delivered command
        self.assertEqual(self.command(after, **{rev: '13', ack: str(first['id'])}), second)
        self.assertEqual(self.command(after, **{rev: '14', ack: str(first['id'])}), second)
        self.assertIsNone(self.command(after, **{rev: '15', ack: str(second['id'])}))
        self.assertEqual(json.loads(self.cli('pending')), [])
        new = json.loads(self.cli('set', 7, 10000))
        self.assertGreater(new['id'], second['id'])
        self.assertEqual(json.loads(self.cli('export')), after)
        self.assertEqual(json.loads(self.cli('status'))['archive']['revision'], 15)

    def test_invalid_uploads_do_not_store_or_ack(self):
        cmd = json.loads(self.cli('set', 2, 1750))
        good = backup()
        good.pop('profile')
        good.pop('weekdayCalorieTargets')
        self.assertEqual(self.command(good), cmd)
        ack = {'X-Assiette-Ack': str(cmd['id'])}
        for bad in [[], {'backup': good}, {k: v for k, v in good.items() if k != 'entries'}, b'{', b'\xff',
                    b'[' * 2000, backup(water={}), backup(app='other'), backup(version=True),
                    backup(healthDays=None), backup(programPreferences=[]), backup(exportedAt='yesterday'),
                    backup(exportedAt='2026-01-01'), backup(profile=[]), backup(weekdayCalorieTargets={'0': 1500})]:
            self.assertEqual(self.put(bad, **ack)[0], 400)
        for name, value in [('Content-Length', '-1'), ('Content-Length', 'q'), ('Transfer-Encoding', 'chunked'),
                            ('X-Assiette-Ack', '4.1'), ('X-Assiette-Ack', str(2**63)), ('X-Assiette-Revision', '0')]:
            self.assertEqual(self.put(good, **{name: value})[0], 400)
        self.assertEqual(self.put(b'', **{'Content-Length': str(32 * 1024**2 + 1)})[0], 413)
        self.assertEqual(self.command(good), cmd)
        self.assertEqual(json.loads(self.cli('export')), good)

    def test_archive_and_ack_roll_back_if_delivery_fails(self):
        first = json.loads(self.cli('set', 1, 1500))
        self.cli('clear', 1)
        before = backup()
        self.assertEqual(self.command(before), first)
        # Fail only the final SQL update, after archive replacement and ack deletion.
        with sqlite3.connect(self.path) as db:
            db.execute("""CREATE TRIGGER stop_delivery BEFORE UPDATE ON command
                       WHEN NEW.delivered = 1 AND OLD.delivered = 0
                       BEGIN SELECT RAISE(ABORT, 'simulated failure'); END""")
        db.close()
        code, _ = self.put(backup(water=[{'ml': 100}]), **{'X-Assiette-Ack': str(first['id'])})
        self.assertEqual(code, 503)
        self.assertEqual(json.loads(self.cli('export')), before)
        self.assertEqual([c['delivered'] for c in json.loads(self.cli('pending'))], [True, False])

    def test_private_db_and_cli_boundaries(self):
        new_db = self.path.with_suffix('.new')
        self.cli('--db', new_db, 'clear', 1, success=False)
        self.assertFalse(new_db.exists())
        archive.initialize(new_db)
        self.assertEqual(stat.S_IMODE(new_db.stat().st_mode), 0o600)
        new_db.chmod(0o644)
        self.cli('--db', new_db, 'status', success=False)
        for args in [('set', 1, 799), ('set', 7, 10001), ('set', 3, '801.5'), ('clear', 0), ('clear', 8)]:
            self.cli(*args, success=False)
        self.assertEqual(json.loads(self.cli('pending')), [])


    def write(self, data):
        path = self.path.with_name('edit.json')
        path.write_text(json.dumps(data))
        return path

    def test_full_replacement_applies_only_to_unchanged_phone_data(self):
        rev = 'X-Assiette-Revision'
        phone = backup(exportedAt='2026-01-08T14:00:00Z', entries=[{'id': 'a', 'day': '2026-01-08T00:00:00Z'}],
                       programPreferences=dict(PROGRAM, highDays=[5, 6]))
        self.assertIsNone(self.command(phone, **{rev: '30'}))
        edited = dict(phone, entries=[], weights=[{'date': '2026-01-08T07:00:00Z', 'kg': 74.2}])
        self.cli('replace', self.write(edited), '--revision', 29, success=False)  # edited from an old export
        self.cli('replace', self.write(phone), '--revision', 30, success=False)   # nothing to change
        bad = dict(edited, weights=[{'date': '2026-01-08T07:00:00.5Z', 'kg': 74.2}])
        self.cli('replace', self.write(bad), '--revision', 30, success=False)
        queued = json.loads(self.cli('replace', self.write(edited), '--revision', 30))

        # Same content, new export time, other row and Set order: still the base, so it is delivered.
        again = dict(phone, exportedAt='2026-01-08T15:00:00Z', programPreferences=dict(PROGRAM, highDays=[6, 5]))
        self.cli('replace', self.write(dict(edited, programPreferences={})), '--revision', 30, success=False)
        command = self.command(again, **{rev: '31'})
        self.assertEqual(command, {'id': queued['id'], 'type': 'replace', 'backup': edited})
        self.assertEqual(self.command(again, **{rev: '31'}), command)  # lost response: delivered again
        reasons = [h['reason'] for h in json.loads(self.cli('history'))]
        self.assertEqual(reasons.count(f"before-replace #{queued['id']}"), 1)

        applied = dict(edited, exportedAt='2026-01-08T15:01:00Z')
        self.assertIsNone(self.command(applied, **{rev: '32', 'X-Assiette-Ack': str(queued['id']),
                                                   'X-Assiette-Ack-Status': 'applied'}))
        self.assertEqual(json.loads(self.cli('log'))[0]['status'], 'applied')
        self.assertEqual(json.loads(self.cli('export')), applied)
        before = [h for h in json.loads(self.cli('history')) if h['reason'].startswith('before-replace')][0]
        self.assertEqual(json.loads(self.cli('export', '--history', before['id']))['entries'], phone['entries'])

        # The phone logged something after the export: the replacement is dropped, the phone wins.
        stale = json.loads(self.cli('replace', self.write(dict(applied, weights=[])), '--revision', 32))
        logged = dict(applied, water=[{'day': '2026-01-08T00:00:00Z', 'createdAt': '2026-01-08T16:00:00Z', 'ml': 250}])
        self.assertIsNone(self.command(logged, **{rev: '33'}))
        self.assertEqual(json.loads(self.cli('log'))[0], dict(json.loads(self.cli('log'))[0], id=stale['id'],
                                                               status='conflict'))
        self.assertEqual(json.loads(self.cli('export')), logged)
        self.assertEqual(self.put(logged, **{rev: '34', 'X-Assiette-Ack-Status': 'maybe'})[0], 400)

    def test_lost_ack_after_replacement_counts_as_applied(self):
        phone = backup(exportedAt='2026-01-08T14:00:00Z', programPreferences=PROGRAM)
        self.command(phone, **{'X-Assiette-Revision': '40'})
        edited = dict(phone, weights=[{'date': '2026-01-08T07:00:00Z', 'kg': 80}])
        queued = json.loads(self.cli('replace', self.write(edited), '--revision', 40))
        self.assertEqual(self.command(phone, **{'X-Assiette-Revision': '41'})['id'], queued['id'])
        weekday = json.loads(self.cli('set', 3, 1900))
        # The phone applied it but crashed before saving the acknowledgement.
        self.assertEqual(self.command(dict(edited, exportedAt='2026-01-08T14:05:00Z'),
                                      **{'X-Assiette-Revision': '42'}), weekday)
        self.assertEqual([c['status'] for c in json.loads(self.cli('log'))], ['pending', 'applied'])

    def test_first_release_queue_is_migrated(self):
        with sqlite3.connect(self.path) as db:
            db.execute('DROP TABLE command')
            db.execute('CREATE TABLE weekday_command(id INTEGER PRIMARY KEY AUTOINCREMENT, weekday INTEGER, '
                       'kcal INTEGER, delivered INTEGER NOT NULL DEFAULT 0)')
            db.execute('INSERT INTO weekday_command(weekday, kcal) VALUES(2, 1600)')
        db.close()
        archive.initialize(self.path)
        self.assertEqual([(c['weekday'], c['kcal'], c['status']) for c in json.loads(self.cli('pending'))],
                         [(2, 1600, 'pending')])
        self.assertEqual(json.loads(self.cli('cancel')), {'cancelled': 1})


if __name__ == '__main__':
    unittest.main()
