"""Pre-write reader boundaries with actual SQLite/files and scalar Core doubles.

These are Python Host/Store protocol checks, not installed Wasm authorization
or end-to-end performance evidence. Intended owner writes happen after the
inspector and its synchronous Core invocation have both retired.
"""
import copy
import sqlite3
from threading import Thread
import unittest
from unittest.mock import patch

import test_local_closed_invocation as closed
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_host_binding import OriginalHostBinding
from actql_sdk._local_storage import (
    ByteFence, ByteWrite, CapacityReservation, LocalStorageCommitUnknown,
    LocalStorageError, StoredBytes,
)
from actql_sdk._local_storage_physical import _SQLiteByteDatabase


class PrewriteInvocationTests(unittest.TestCase):
    fixture = closed.ClosedInvocationTests.fixture

    def perform(self, core, binding, store, action, *, mode='cas', before=None, readers=None):
        key = store.namespaced_key('probe', 'output')
        write = ByteWrite(key, None, b'original output')
        capacity = CapacityReservation('probe', key, 32, 1)
        if mode == 'attached':
            original_key = store.namespaced_key('probe', 'retained')
            store.compare_exchange(original_key, None, b'retained')
            capacity = CapacityReservation('probe', original_key, 32, 1)
            original = ByteFence(original_key, 0, b'retained')
        if mode in ('reserved', 'attached'):
            store.reserve_capacity(capacity.namespace, capacity.key, 32, 1, 4096, 128)
        core._exports['actql_probe_run'] = lambda *_: action()
        def inspect(reader):
            if readers is not None:
                readers.append(reader)
            if before is not None:
                before(reader)
            binding.inspect_reader(reader, lambda _: self.assertEqual(core._call('probe', 'run'), 7))
        with binding.fenced() as fences:
            if mode == 'capacity':
                return store.reserve_capacity_inspected('probe', key, 32, 1, 4096, 128,
                    fences, inspect=inspect, current=binding._current_observer)
            if mode == 'reserved':
                return store.compare_exchange_reserved_inspected(write, capacity, fences,
                    inspect=inspect, current=binding._current_observer)
            if mode == 'attached':
                return store.compare_exchange_attached_inspected(write, original, capacity, fences,
                    inspect=inspect, current=binding._current_observer)
            return store.compare_exchange_many_inspected((write,), fences,
                inspect=inspect, current=binding._current_observer)

    def test_all_audited_prewrite_phases_group_current_and_retire_before_owner_write(self):
        for mode in ('cas', 'reserved', 'attached', 'capacity'):
            with self.subTest(mode=mode):
                core, binding, store, _, current = self.fixture()
                graphs, readers, spans, writes = [], [], [], []
                physical = OriginalHostBinding._physical_current
                write = _SQLiteByteDatabase.write_record
                reserve = _SQLiteByteDatabase.reserve_capacity_in_transaction
                def graph(receiver):
                    graphs.append(receiver)
                    return physical(receiver)
                def check_retired(database):
                    if not readers:
                        return
                    self.assertIsNone(database._connection._closed_invocation)
                    self.assertIsNone(core._invocation_observation)
                    self.assertIsNone(binding._observed_reader)
                    self.assertFalse(spans[-1].active)
                    with self.assertRaises(ValueError):
                        readers[-1].check_frame(readers[-1])
                    writes.append(True)
                def write_record(database, *args):
                    check_retired(database)
                    return write(database, *args)
                def reserve_capacity(database, *args):
                    check_retired(database)
                    return reserve(database, *args)
                def action():
                    before = len(graphs)
                    for _ in range(20):
                        self.assertEqual(current(), 0)
                    spans.append(core._invocation_observation)
                    self.assertTrue(spans[-1].admitted)
                    self.assertEqual(len(graphs) - before, 1)
                    return 7
                with patch.object(OriginalHostBinding, '_physical_current', graph), \
                        patch.object(_SQLiteByteDatabase, 'write_record', write_record), \
                        patch.object(_SQLiteByteDatabase, 'reserve_capacity_in_transaction', reserve_capacity):
                    result = self.perform(core, binding, store, action, mode=mode, readers=readers)
                self.assertEqual(result, True if mode == 'capacity' else (0,) if mode == 'cas' else 0)
                self.assertEqual(writes, [True])
                self.assertFalse(store._connection.in_transaction)

    def test_prior_unrelated_writes_and_savepoints_keep_legacy_without_rebasing(self):
        for mode in ('cas', 'capacity', 'readonly'):
            for mutation in ('row', 'control'):
                with self.subTest(mode=mode, mutation=mutation):
                    core, binding, store, _, current = self.fixture()
                    spans = []
                    def before(reader):
                        self.assertIsNotNone(reader._invocation_candidate)
                        if mutation == 'row':
                            store._connection.execute("INSERT INTO core_bytes VALUES ('unrelated', 0, X'01')")
                        else:
                            for sql in ('SAVEPOINT held', 'ROLLBACK TO held', 'RELEASE held'):
                                store._connection.execute(sql)
                    def action():
                        for _ in range(3):
                            self.assertEqual(current(), 0)
                        span = core._invocation_observation
                        self.assertIsNotNone(span)
                        self.assertTrue(span.disabled)
                        self.assertFalse(span.admitted)
                        self.assertIsNone(store._connection._closed_invocation)
                        spans.append(span)
                        return 7
                    if mode == 'readonly':
                        core._exports['actql_probe_run'] = lambda *_: action()
                        with binding.fenced() as fences:
                            def inspect(reader):
                                before(reader)
                                binding.inspect_reader(reader, lambda _: self.assertEqual(core._call('probe', 'run'), 7))
                            store.inspect_namespaces(fences, inspect=inspect, current=binding._current_observer)
                    else:
                        self.perform(core, binding, store, action, mode=mode, before=before)
                    # A later reader has its own baseline; this call's fallback
                    # neither poisons the Store nor installs reusable permission.
                    def fresh():
                        self.assertEqual(current(), 0)
                        self.assertTrue(core._invocation_observation.admitted)
                        self.assertIsNot(core._invocation_observation, spans[0])
                        return 7
                    self.assertEqual(closed.ClosedInvocationTests.run_export(self, core, binding, fresh), [7])

    def test_mutation_after_admission_refuses_before_any_owner_write(self):
        for mode in ('cas', 'capacity'):
            for mutation in ('row', 'schema', 'control', 'file', 'root', 'callback', 'refusal'):
                with self.subTest(mode=mode, mutation=mutation):
                    core, binding, store, path, current = self.fixture()
                    writes, failures = [], []
                    def action():
                        self.assertEqual(current(), 0)
                        self.assertTrue(core._invocation_observation.admitted)
                        if mutation == 'row':
                            store._connection.execute("INSERT INTO core_bytes VALUES ('unrelated', 0, X'01')")
                        elif mutation == 'schema':
                            store._connection.execute('CREATE TEMP TABLE unexpected (value INTEGER)')
                        elif mutation == 'control':
                            for sql in ('SAVEPOINT held', 'ROLLBACK TO held', 'RELEASE held'):
                                store._connection.execute(sql)
                        elif mutation == 'file':
                            (path / 'source' / binding._account.name).write_bytes(b'changed')
                        elif mutation == 'root':
                            (path / 'source').rename(path / 'source-original')
                            (path / 'source').mkdir(mode=0o700)
                        elif mutation == 'callback':
                            try:
                                store._connection.set_trace_callback(lambda _: None)
                            except RuntimeError as error:
                                failures.append(error)
                        else:
                            original = PermissionError('original current refused')
                            def refuse():
                                raise original
                            try:
                                core._observation_import('future_unknown_import', refuse)()
                            except PermissionError as error:
                                failures.append(error)
                        return 7
                    def unexpected_write(*_):
                        writes.append(True)
                        self.fail('Owner wrote after a failed pre-write invocation')
                    with patch.object(_SQLiteByteDatabase, 'write_record', unexpected_write), \
                            patch.object(_SQLiteByteDatabase, 'reserve_capacity_in_transaction', unexpected_write):
                        with self.assertRaises((LocalStorageError, LocalFileError, ValueError, RuntimeError, PermissionError)) as raised:
                            self.perform(core, binding, store, action, mode=mode)
                    if failures:
                        self.assertIs(raised.exception, failures[0])
                    self.assertFalse(writes)
                    self.assertFalse(store._connection.in_transaction)
                    self.assertIsNone(store._connection._closed_invocation)
                    self.assertIsNone(store.read(store.namespaced_key('probe', 'output')))

    def test_probe_checks_real_snapshot_even_when_prior_mutation_would_select_legacy(self):
        for mutation in ('schema', 'transaction', 'connection'):
            with self.subTest(mutation=mutation):
                core, binding, store, _, current = self.fixture()
                database, connection = store._physical, store._connection
                foreign = sqlite3.connect(':memory:', isolation_level=None)
                self.addCleanup(foreign.close)
                failures = []
                def action():
                    # Before first current, so this is candidate rather than
                    # admitted-span failure. A stale row count cannot hide it.
                    connection.execute("INSERT INTO core_bytes VALUES ('unrelated', 0, X'01')")
                    if mutation == 'schema':
                        connection.execute('CREATE TEMP TABLE unexpected (value INTEGER)')
                    elif mutation == 'transaction':
                        connection.execute('ROLLBACK')
                        connection.execute('BEGIN IMMEDIATE')
                    else:
                        store._connection = foreign
                    try:
                        current()
                    except (ValueError, LocalStorageError) as error:
                        failures.append(error)
                    finally:
                        store._connection = connection
                    return 7
                with self.assertRaises((ValueError, LocalStorageError)) as raised:
                    self.perform(core, binding, store, action)
                self.assertIs(raised.exception, failures[0])
                self.assertIsNone(store.read(store.namespaced_key('probe', 'output')))
                self.assertIs(store._physical, database)

    def test_customization_during_candidate_selects_legacy_before_any_reduced_check(self):
        core, binding, store, _, current = self.fixture()
        original = _SQLiteByteDatabase._snapshot_identity
        customized = []
        def snapshot(database):
            value = original(database)
            span = core._invocation_observation
            if span is not None and not span.admitted and not customized:
                self.assertIsNone(store._connection._closed_invocation)
                customized.append(True)
                store._connection.set_trace_callback(lambda _: None)
            return value
        def action():
            with patch.object(_SQLiteByteDatabase, '_snapshot_identity', snapshot):
                self.assertEqual(current(), 0)
            self.assertTrue(core._invocation_observation.disabled)
            self.assertFalse(core._invocation_observation.admitted)
            return 7
        self.assertEqual(self.perform(core, binding, store, action), (0,))
        self.assertEqual(customized, [True])

    def test_foreign_candidate_access_and_swallowed_reentry_are_sticky(self):
        for mode in ('copy', 'thread', 'reentry'):
            with self.subTest(mode=mode):
                core, binding, store, _, current = self.fixture()
                failures = []
                snapshot = _SQLiteByteDatabase._snapshot_identity
                def action():
                    reader, span = binding._observed_reader, core._invocation_observation
                    def invalid():
                        try:
                            reader._invocation_candidate(copy.copy(reader) if mode == 'copy' else reader,
                                binding._current_observer, span)
                        except ValueError as error:
                            failures.append(error)
                    if mode == 'thread':
                        thread = Thread(target=invalid)
                        thread.start()
                        thread.join()
                    elif mode == 'reentry':
                        def reentrant(database):
                            try:
                                reader.check_unchanged(reader)
                            except ValueError as error:
                                failures.append(error)
                            return snapshot(database)
                        with patch.object(_SQLiteByteDatabase, '_snapshot_identity', reentrant):
                            try:
                                current()
                            except ValueError:
                                pass
                    else:
                        invalid()
                    return 7
                with self.assertRaises(ValueError) as raised:
                    self.perform(core, binding, store, action)
                self.assertIs(raised.exception, failures[0])
                self.assertIsNone(store.read(store.namespaced_key('probe', 'output')))

    def test_swallowed_candidate_failure_blocks_effect_dispatch_before_admission(self):
        for mode in ('unknown_import', 'publisher_import', 'direct_interrupt'):
            with self.subTest(mode=mode):
                core, binding, store, _, _ = self.fixture()
                effects, failures = [], []
                def effect():
                    effects.append(True)
                    return 0
                def action():
                    reader, span = binding._observed_reader, core._invocation_observation
                    self.assertFalse(span.admitted)
                    try:
                        reader._invocation_candidate(copy.copy(reader), binding._current_observer, span)
                    except ValueError as error:
                        failures.append(error)
                    self.assertIs(span.failure, failures[0])
                    try:
                        if mode == 'direct_interrupt':
                            span.interrupt(effect)
                        else:
                            name = ('future_unknown_import' if mode == 'unknown_import'
                                    else 'publisher_finish')
                            core._observation_import(name, effect)()
                    except ValueError as error:
                        failures.append(error)
                    self.assertEqual(len(failures), 2)
                    self.assertIs(failures[1], failures[0])
                    self.assertFalse(effects)
                    return 7
                with self.assertRaises(ValueError) as raised:
                    self.perform(core, binding, store, action)
                self.assertIs(raised.exception, failures[0])
                self.assertFalse(effects)
                self.assertIsNone(store.read(store.namespaced_key('probe', 'output')))

    def test_projected_multiwrite_readers_remain_ineligible_before_and_after_writes(self):
        for publication in (False, True):
            with self.subTest(publication=publication):
                core, binding, store, _, current = self.fixture()
                retained_key = store.namespaced_key('probe', 'retained')
                self.assertEqual(store.compare_exchange(retained_key, None, b'retained'), 0)
                capacity = CapacityReservation('probe', retained_key, 32, 1)
                self.assertTrue(store.reserve_capacity('probe', retained_key, 32, 1, 4096, 128))
                originals = ((ByteFence(retained_key, 0, b'retained'), capacity),)
                states = []
                def action():
                    self.assertIsNone(core._invocation_observation)
                    self.assertIsNone(binding._observed_reader._invocation_check)
                    self.assertIsNone(binding._observed_reader._invocation_candidate)
                    self.assertEqual(current(), 0)
                    states.append(True)
                    return 7
                core._exports['actql_probe_run'] = lambda *_: action()
                def project(ordinal, consume):
                    self.assertEqual(core._call('probe', 'run'), 7)
                    consume(ByteWrite(store.namespaced_key('probe', str(ordinal)), None, b'original'))
                    self.assertEqual(core._call('probe', 'run'), 7)
                def inspect(reader, consume):
                    binding.inspect_reader(reader, lambda _: consume())
                with binding.fenced() as fences:
                    operation = (store.store_publication_projected_inspected if publication
                                 else store.compare_exchange_projected_inspected)
                    result = operation(2, project, originals, fences, inspect=inspect,
                        current=binding._current_observer, before_commit=lambda: None)
                self.assertEqual(result, (0, 0))
                self.assertEqual(states, [True] * 4)
                for ordinal in range(2):
                    self.assertEqual(store.read(store.namespaced_key('probe', str(ordinal))),
                        StoredBytes(0, b'original'))
                self.assertEqual(store.read(retained_key), StoredBytes(0, b'retained'))
                self.assertEqual(store._physical.read_capacity('probe', retained_key), (32, 1))

    def test_default_write_reader_has_no_closed_ports(self):
        core, binding, store, _, current = self.fixture()
        def action():
            self.assertIsNone(core._invocation_observation)
            self.assertIsNone(binding._observed_reader._invocation_check)
            self.assertIsNone(binding._observed_reader._invocation_candidate)
            self.assertEqual(current(), 0)
            return 7
        core._exports['actql_probe_run'] = lambda *_: action()
        with binding.fenced() as fences:
            store._physical.begin_immediate()
            try:
                store._inspect_namespace_locked(lambda reader: binding.inspect_reader(reader,
                    lambda _: self.assertEqual(core._call('probe', 'run'), 7)),
                    fences, binding._current_observer)
            finally:
                store._physical.rollback()

    def test_count_successor_fence_is_checked_after_inspector_retirement(self):
        for corrupt in (False, True):
            with self.subTest(corrupt=corrupt):
                core, binding, store, _, current = self.fixture()
                count = store.namespaced_key('probe', 'count')
                output = store.namespaced_key('probe', 'output')
                store.compare_exchange(count, None, b'0')
                writes = (ByteWrite(count, 0, b'1'), ByteWrite(output, None, b'original'))
                original = _SQLiteByteDatabase.write_record
                def write_record(database, key, generation, payload):
                    self.assertIsNone(database._connection._closed_invocation)
                    result = original(database, key, generation, payload)
                    if corrupt and key == output:
                        database._connection.execute(
                            'UPDATE core_bytes SET payload = ? WHERE key = ?', (b'wrong', count))
                    return result
                def action():
                    self.assertEqual(current(), 0)
                    self.assertTrue(core._invocation_observation.admitted)
                    return 7
                core._exports['actql_probe_run'] = lambda *_: action()
                with binding.fenced() as fences, patch.object(_SQLiteByteDatabase, 'write_record', write_record):
                    result = store.compare_exchange_many_inspected(writes,
                        (*fences, ByteFence(count, 0, b'0')),
                        inspect=lambda reader: binding.inspect_reader(reader,
                            lambda _: self.assertEqual(core._call('probe', 'run'), 7)),
                        current=binding._current_observer)
                self.assertEqual(result, None if corrupt else (1, 0))
                self.assertEqual(store.read(count), StoredBytes(0, b'0') if corrupt else StoredBytes(1, b'1'))
                self.assertEqual(store.read(output), None if corrupt else StoredBytes(0, b'original'))

    def test_lost_commit_reply_keeps_unknown_and_never_replays_owner_write(self):
        for mode in ('cas', 'capacity'):
            with self.subTest(mode=mode):
                core, binding, store, _, current = self.fixture()
                commits, writes = [], []
                commit = _SQLiteByteDatabase.commit
                write = _SQLiteByteDatabase.write_record
                reserve = _SQLiteByteDatabase.reserve_capacity_in_transaction
                def lose(database):
                    commits.append(True)
                    commit(database)
                    raise OSError('original COMMIT reply lost')
                def record_write(database, *args):
                    writes.append(True)
                    return write(database, *args)
                def record_reserve(database, *args):
                    writes.append(True)
                    return reserve(database, *args)
                def action():
                    self.assertEqual(current(), 0)
                    self.assertTrue(core._invocation_observation.admitted)
                    return 7
                with patch.object(_SQLiteByteDatabase, 'commit', lose), \
                        patch.object(_SQLiteByteDatabase, 'write_record', record_write), \
                        patch.object(_SQLiteByteDatabase, 'reserve_capacity_in_transaction', record_reserve):
                    with self.assertRaises(LocalStorageCommitUnknown) as raised:
                        self.perform(core, binding, store, action, mode=mode)
                self.assertIs(raised.exception.cleanup_store, store)
                self.assertIsInstance(raised.exception.__cause__, OSError)
                self.assertEqual(commits, [True])
                self.assertEqual(writes, [True])
                self.assertFalse(store._connection.in_transaction)
                key = store.namespaced_key('probe', 'output')
                for _ in range(2):
                    if mode == 'capacity':
                        self.assertEqual(store._physical.read_capacity('probe', key), (32, 1))
                    else:
                        self.assertEqual(store.read(key), StoredBytes(0, b'original output'))
                self.assertEqual(writes, [True])


if __name__ == '__main__':
    unittest.main()
