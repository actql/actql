"""Measure the same public Result against completed, unrelated Run history."""
from collections import Counter
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys

import actql
import actql_sdk
from actql_sdk._local_distribution import installed_local_components
from actql_sdk._local_host_binding import OriginalHostBinding
from actql_sdk._local_storage_physical import _SQLiteByteDatabase, _TrackedSQLiteConnection


RUN_PREFIX = 'namespace:11:client_runs:'
SETTINGS_PREFIX = 'namespace:21:client_local_settings:'
LEVELS = (1, 10, 100, 1000)
TARGET_QUERY = 'SELECT 1 AS id'
RESULT_NAME = 'answer'
READ_CODE = _SQLiteByteDatabase.read_row.__code__
SCAN_CODE = _SQLiteByteDatabase.scan_range.__code__
EXECUTE_CODE = _TrackedSQLiteConnection.execute.__code__
SETTINGS_CODE = OriginalHostBinding._settings_inventory.__code__


def report(**value):
    print(json.dumps(value, separators=(',', ':')), flush=True)


def original_rows(connection, limit):
    keys = connection.execute('SELECT key FROM core_bytes WHERE key >= ? AND key < ? '
                              'ORDER BY key LIMIT ?', (RUN_PREFIX, RUN_PREFIX[:-1] + ';', limit + 1)).fetchall()
    assert len(keys) == limit and all(key.startswith(RUN_PREFIX) for key, in keys)
    return {key for key, in keys}


def target_snapshot(connection, target):
    generation, payload = connection.execute(
        'SELECT generation, CASE WHEN length(payload) <= 1048576 THEN payload END FROM core_bytes WHERE key = ?',
        (target,)).fetchone()
    assert type(generation) is int and type(payload) is bytes
    return dict(generation=str(generation), sha256=hashlib.sha256(payload).hexdigest()), json.loads(payload)


class PhysicalResultObservation:
    """Profile SQLite reads separately. Profiling excludes closed reconciliation."""
    def __init__(self, database, connection, binding, target):
        assert type(database) is _SQLiteByteDatabase and type(connection) is _TrackedSQLiteConnection
        assert type(binding) is OriginalHostBinding
        self.database, self.connection, self.target = database, connection, target
        self.binding = binding
        self.namespace_reads = Counter()
        self.reads = self.body_selects = self.body_read_ports = self.target_rows = self.unrelated_rows = 0
        self.settings = {'manifest': binding._fences[1].payload} | {
            'file:' + value.name: value.body for value in binding._selected}
        self.settings_rows = [(SETTINGS_PREFIX + name, 0, True) for name in sorted(self.settings)] + [None]
        originals = [(name, hashlib.sha256(self.settings[name]).hexdigest()) for name in sorted(self.settings)]
        self.settings_fact = hashlib.sha256(json.dumps(originals, separators=(',', ':')).encode()).hexdigest()
        self.settings_scans = None
        self.settings_complete = self.settings_unmatched = 0

    def settings_inventory(self):
        return dict(factSha256=self.settings_fact, sqliteGeneration='0', members=len(self.settings),
                    completeScans=self.settings_complete, unmatchedScopes=self.settings_unmatched,
                    comparedRows=self.settings_complete * len(self.settings), trailingChecks=self.settings_complete)

    def profile(self, frame, event, value):
        code = frame.f_code
        if code is SETTINGS_CODE and event in ('call', 'return') and frame.f_locals['self'] is self.binding:
            if event == 'call':
                self.settings_scans = []
            else:
                if self.settings_scans == self.settings_rows:
                    self.settings_complete += 1
                else:
                    self.settings_unmatched += 1
                self.settings_scans = None
            return
        if event != 'return':
            return
        if code not in (READ_CODE, SCAN_CODE, EXECUTE_CODE):
            return
        local = frame.f_locals
        if code is EXECUTE_CODE and local['self'] is self.connection:
            statement = local['sql'].lstrip().upper()
            if statement.startswith('SELECT') and isinstance(value, sqlite3.Cursor):
                self.reads += 1
                self.body_selects += 'FROM CORE_BYTES' in statement and 'THEN PAYLOAD' in statement
        if local.get('self') is not self.database:
            return
        self.body_read_ports += 1
        if (code is SCAN_CODE and self.settings_scans is not None and local['lower'].startswith(SETTINGS_PREFIX)
                and local['upper'] == SETTINGS_PREFIX[:-1] + ';' and not local['exact']):
            if value is None:
                self.settings_scans.append(None)
            else:
                key, generation, payload = value[:3]
                name = key[len(SETTINGS_PREFIX):] if type(key) is str else ''
                self.settings_scans.append((key, generation, name in self.settings and payload == self.settings[name]))
        if value is None:
            return
        if code is READ_CODE:
            key, payload = local['key'], value[1]
        elif code is SCAN_CODE:
            key, payload = value[0], value[2]
        else:
            return
        if type(key) is str and type(payload) is bytes:
            if key == self.target:
                self.target_rows += 1
            elif key.startswith(RUN_PREFIX):
                self.unrelated_rows += 1
            parts = key.split(':', 3)
            namespace = parts[2] if len(parts) == 4 and parts[0] == 'namespace' else 'bare'
            if re.fullmatch(r'[a-z_]{1,64}', namespace):
                self.namespace_reads[namespace] += 1

    @contextmanager
    def observe(self):
        assert sys.getprofile() is None and sys.gettrace() is None
        sys.setprofile(self.profile)
        try:
            yield
        finally:
            sys.setprofile(None)


def measure(state, expected_source, levels):
    identity = installed_local_components()
    assert identity.source_sha == expected_source
    prefix = Path(sys.prefix).resolve()
    assert all(Path(module.__file__).resolve().is_relative_to(prefix) for module in (actql, actql_sdk))
    report(phase='installed', source=identity.source_sha, module=identity.module_sha256,
           image=identity.image_sha256, pid=os.getpid(), levels=levels, query=TARGET_QUERY, resultName=RESULT_NAME)
    assert not state.exists()
    with actql.open(state_dir=state) as client:
        host = client._client._local_host
        store = host._installation._store
        connection = store._connection
        query = client.sql(TARGET_QUERY, result=RESULT_NAME)
        assert query.all() == [{'id': 1}]
        execution = query.execution
        reference = dict(execution.ref)
        target, = original_rows(connection, 1)
        before, body = target_snapshot(connection, target)
        assert json.loads(body['run_definition'])['run_definition_cid'] == reference['runDefinitionCid']
        used = {reference['runDefinitionCid']}
        completed = 0
        for size in levels:
            report(phase='populate', size=size, completed=completed)
            for ordinal in range(completed, size):
                other = client.start_source('SELECT 2 AS id', format='sql', submission_ref=client.new_submission())
                assert other.wait().status == 'succeeded'
                run = other.ref['runDefinitionCid']
                assert run not in used
                used.add(run)
                report(phase='populated', size=size, completed=ordinal + 1)
            completed = size
            assert target in original_rows(connection, size + 1) and len(used) == size + 1
            report(phase='read', size=size)
            observer = PhysicalResultObservation(store._physical, connection, host._installation.binding, target)
            with observer.observe():
                rows = execution.result(RESULT_NAME).all()
            assert rows == [{'id': 1}] and dict(execution.ref) == reference
            after, _ = target_snapshot(connection, target)
            assert before == after and target in original_rows(connection, size + 1)
            assert 0 < observer.body_read_ports == observer.body_selects <= observer.reads
            report(phase='observed', size=size, targetRun=reference['runDefinitionCid'],
                   targetRow=after, retainedRuns=len(used), rows=rows,
                   executedSelects=observer.reads, boundedBodySelects=observer.body_selects, bodyReadPorts=observer.body_read_ports,
                   targetRunBodyReads=observer.target_rows, unrelatedRunBodyReads=observer.unrelated_rows,
                   physicalNamespaces=observer.namespace_reads, settingsInventory=observer.settings_inventory())
    assert client._closed
    report(phase='closed', firstClose=client._closed)


if __name__ == '__main__':
    levels = tuple(int(value) for value in sys.argv[3:]) or LEVELS
    assert levels == LEVELS[:len(levels)]
    measure(Path(sys.argv[1]).resolve(), sys.argv[2], levels)
