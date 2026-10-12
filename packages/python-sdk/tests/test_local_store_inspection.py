"""Actual SQLite snapshots; mocked Core fields are not publication authority."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import sqlite3
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_storage import (
    ByteFence, CapacityReservation, LocalByteStore, LocalStorageError, StoredBytes,
)
from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_files import LocalFileError
import test_local_reader_facts as facts_fixture


class StoreInspectionTests(unittest.TestCase):
    def store(self, path):
        return LocalByteStore(path, max_records=8, max_record_bytes=256,
                              max_payload_bytes=1024)

    def original(self, store):
        store.compare_exchange('original', None, b'original-sealed')
        self.assertTrue(store.reserve_capacity('publication_payload', 'original', 64, 1, 128, 2))
        return ((ByteFence('original', 0, b'original-sealed'),
                 CapacityReservation('publication_payload', 'original', 64, 1)),)

    def test_original_keys_raw_saved_chain_and_missing_row_are_one_read_only_snapshot(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            original = self.original(store)
            # Independent physical expectations: no parsing or candidate equality.
            rows = [('scope-key', b'original-saved-index-cid'),
                    ('saved-index', b'{"attempt":"older","time":"earlier"}'),
                    ('saved-request', b'e\xcc\x81\r\n\x00NULL'),
                    ('saved-attempt', b'\xc3\xa9\nnull')]
            for key, raw in rows:
                store.compare_exchange(key, None, raw)
            events, sql = [], []
            store._connection.set_trace_callback(sql.append)

            def inspect(read):
                for key, raw in rows:
                    def consume(observed):
                        self.assertEqual(observed, StoredBytes(0, raw))
                        events.append(('row', key))
                    read(key, consume)
                read('absent-key', lambda observed: self.assertIsNone(observed))

            self.assertIsNone(store.inspect_publication_projected_attached(
                inspect, original, current=lambda: events.append(('current',))))
            self.assertEqual([event for event in events if event[0] == 'row'],
                             [('row', key) for key, _ in rows])
            self.assertEqual(sql.count('BEGIN'), 1)
            self.assertEqual(sql.count('ROLLBACK'), 1)
            self.assertFalse(any(q.startswith(('INSERT', 'UPDATE', 'DELETE', 'COMMIT')) for q in sql))
            self.assertEqual(store.read('original'), StoredBytes(0, b'original-sealed'))
            self.assertFalse(store._connection.in_transaction)

    def test_committed_write_lost_ack_is_observed_without_repeating_or_matching_candidate(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            original = self.original(store)
            def commit_then_lose_ack():
                self.assertEqual(store.compare_exchange('scope-key', None, b'saved-older-index'), 0)
                raise OSError('Physical COMMIT acknowledgement was lost')
            with self.assertRaisesRegex(OSError, 'acknowledgement was lost'):
                commit_then_lose_ack()
            observed = []
            store.inspect_publication_projected_attached(
                lambda read: read('scope-key', lambda row: observed.append(row)),
                original, current=lambda: None)
            self.assertEqual(observed, [StoredBytes(0, b'saved-older-index')])
            self.assertEqual(store.read('scope-key').generation, 0)
            # This method reports only physical bytes, not acceptance/committed.

    def test_snapshot_keeps_original_bytes_while_a_separate_connection_has_pending_changes(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            original = self.original(store)
            store.compare_exchange('index', None, b'old')
            writer = sqlite3.connect(Path(directory) / 'core.sqlite', isolation_level=None)
            try:
                observed = []
                def inspect(read):
                    read('index', lambda row: observed.append(row))
                    writer.execute('BEGIN IMMEDIATE')
                    writer.execute("UPDATE core_bytes SET payload = ?, generation = 1 WHERE key = 'index'",
                                   (b'new',))
                    read('index', lambda row: observed.append(row))
                store.inspect_publication_projected_attached(inspect, original, current=lambda: None)
                self.assertEqual(observed, [StoredBytes(0, b'old')] * 2)
                writer.execute('COMMIT')
                self.assertEqual(store.read('index'), StoredBytes(1, b'new'))
            finally:
                writer.close()

    def test_missing_original_or_changed_generation_bytes_capacity_refuses_before_lookup(self):
        for kind in ('absent', 'generation', 'bytes', 'capacity'):
            with self.subTest(kind=kind), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    original = self.original(store)
                    fence, capacity = original[0]
                    bad = ((ByteFence('absent' if kind == 'absent' else fence.key,
                                      1 if kind == 'generation' else 0,
                                      b'wrong' if kind == 'bytes' else fence.payload),
                            CapacityReservation(capacity.namespace,
                                                'absent' if kind == 'absent' else capacity.key,
                                                63 if kind == 'capacity' else 64, 1)),)
                    calls = []
                    with self.assertRaises(LocalStorageError):
                        store.inspect_publication_projected_attached(
                            lambda read: calls.append('lookup'), bad,
                            current=lambda: calls.append('current'))
                    self.assertEqual(calls, [])
                    self.assertFalse(store._connection.in_transaction)

    def test_current_publisher_refusal_unknown_and_revocation_are_not_not_found(self):
        for fail_at in (1, 2, 3, 4, 5):
            for error in (PermissionError('Current publisher denied'),
                          OSError('Current publisher is unknown')):
                with self.subTest(fail_at=fail_at, error=type(error)), TemporaryDirectory() as directory:
                    with self.store(Path(directory) / 'core.sqlite') as store:
                        original = self.original(store)
                        calls, received = [], []
                        def current():
                            calls.append('current')
                            if len(calls) == fail_at:
                                raise error
                        with self.assertRaises(type(error)):
                            store.inspect_publication_projected_attached(
                                lambda read: read('absent', lambda row: received.append(row)),
                                original, current=current)
                        self.assertEqual(received, [] if fail_at <= 3 else [None])
                        self.assertEqual(len(calls), fail_at)
                        self.assertFalse(store._connection.in_transaction)

    def test_query_failure_and_oversized_corrupt_row_never_invoke_missing_consumer(self):
        for kind in ('query_failure', 'oversized'):
            with self.subTest(kind=kind), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    original = self.original(store)
                    if kind == 'oversized':
                        store._connection.execute('INSERT INTO core_bytes VALUES (?, ?, ?)',
                                                  ('index', 0, b'x' * 257))
                    else:
                        store._connection.set_authorizer(
                            lambda action, *_: sqlite3.SQLITE_DENY
                            if action == sqlite3.SQLITE_FUNCTION else sqlite3.SQLITE_OK)
                    received = []
                    with self.assertRaises((sqlite3.DatabaseError, LocalStorageError)):
                        store.inspect_publication_projected_attached(
                            lambda read: read('index', lambda row: received.append(row)),
                            original, current=lambda: None)
                    self.assertEqual(received, [])
                    store._connection.set_authorizer(None)
                    self.assertFalse(store._connection.in_transaction)

    def test_swallowed_read_failure_and_nested_read_remain_failure(self):
        for kind in ('bad_key', 'bad_consumer', 'nested', 'second_read'):
            with self.subTest(kind=kind), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    original = self.original(store)
                    def inspect(read):
                        try:
                            if kind == 'bad_key':
                                read('', lambda _: None)
                            elif kind == 'bad_consumer':
                                read('index', lambda _: True)
                            elif kind == 'nested':
                                def consume(_):
                                    try:
                                        read('nested', lambda _: None)
                                    except ValueError:
                                        pass
                                read('index', consume)
                            else:
                                read('index', lambda _: True)
                        except ValueError:
                            pass
                        if kind == 'second_read':
                            with self.assertRaises(ValueError):
                                read('later', lambda _: self.fail('Cannot continue after failure'))
                    with self.assertRaises(ValueError):
                        store.inspect_publication_projected_attached(inspect, original, current=lambda: None)
                    self.assertFalse(store._connection.in_transaction)

    def test_captured_reader_wrong_thread_and_async_callback_cannot_escape_transaction(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            original = self.original(store)
            captured = []
            def inspect(read):
                captured.append(read)
                read('missing', lambda _: None)
            store.inspect_publication_projected_attached(inspect, original, current=lambda: None)
            with self.assertRaises(ValueError):
                captured[0]('missing', lambda _: self.fail('Reader escaped transaction'))
            with ThreadPoolExecutor(max_workers=1) as pool:
                def foreign(read):
                    with self.assertRaises(ValueError):
                        pool.submit(read, 'missing', lambda _: None).result(timeout=1)
                with self.assertRaises(ValueError):
                    store.inspect_publication_projected_attached(foreign, original, current=lambda: None)
            async def asynchronous(_):
                self.fail('Async physical inspector must not execute')
            coroutine = asynchronous(None)
            try:
                with self.assertRaises(ValueError):
                    store.inspect_publication_projected_attached(
                        lambda read: (read('missing', lambda _: None), coroutine)[1],
                        original, current=lambda: None)
            finally:
                coroutine.close()

    def test_incomplete_inspector_bool_current_and_reentry_are_rejected_without_writes(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            original = self.original(store)
            for inspect, current in ((lambda _: None, lambda: None),
                                     (lambda read: read('missing', lambda _: None), lambda: True),
                                     (lambda read: True, lambda: None),
                                     (lambda read: store.read('other'), lambda: None)):
                with self.assertRaises((ValueError, LocalStorageError)):
                    store.inspect_publication_projected_attached(inspect, original, current=current)
                self.assertFalse(store._connection.in_transaction)
            self.assertEqual(store._connection.execute('SELECT count(*) FROM core_bytes').fetchone(), (1,))

    def test_read_count_and_cumulative_copy_budget_bound_repeated_reads(self):
        for kind in ('count', 'bytes'):
            with self.subTest(kind=kind), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    original = self.original(store)
                    store.compare_exchange('index', None, b'x' * 256)
                    received = []
                    def inspect(read):
                        for _ in range(9 if kind == 'count' else 5):
                            read('missing' if kind == 'count' else 'index',
                                 lambda row: received.append(None if row is None else len(row.payload)))
                    with self.assertRaises(LocalStorageError):
                        store.inspect_publication_projected_attached(inspect, original, current=lambda: None)
                    self.assertEqual(received, [None] * 8 if kind == 'count' else [256] * 4)
                    self.assertFalse(store._connection.in_transaction)

    def test_same_consumer_cleanup_failure_keeps_original_loan_until_explicit_retry(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            original = self.original(store)
            loan = object()
            pending = [loan]
            def consume(_):
                raise OSError('Same response input cleanup pending')
            with self.assertRaisesRegex(OSError, 'cleanup pending'):
                store.inspect_publication_projected_attached(
                    lambda read: read('index', consume), original, current=lambda: None)
            self.assertIs(pending[0], loan)
            self.assertEqual(store.read('original'), StoredBytes(0, b'original-sealed'))
            self.assertEqual(store.read_capacity('publication_payload', 'original').reserved_bytes, 64)
            self.assertFalse(store._connection.in_transaction)
            pending.pop()  # Trusted Host explicit cleanup, never performed by Store.

    def test_transaction_cleanup_failure_keeps_same_connection_pending_and_reader_inactive(self):
        with TemporaryDirectory() as directory:
            store = self.store(Path(directory) / 'core.sqlite')
            original = self.original(store)
            database = store._connection
            captured = []
            class FailingCleanup:
                in_transaction = property(lambda _: database.in_transaction)
                def execute(self, sql, *args):
                    if sql == 'ROLLBACK':
                        raise sqlite3.OperationalError('Same snapshot cleanup pending')
                    return database.execute(sql, *args)
                def close(self):
                    raise sqlite3.OperationalError('Same connection close pending')
            store._connection = FailingCleanup()
            def inspect(read):
                captured.append(read)
                read('missing', lambda _: None)
            try:
                with self.assertRaisesRegex(sqlite3.OperationalError, 'snapshot cleanup pending'):
                    store.inspect_publication_projected_attached(inspect, original, current=lambda: None)
                self.assertTrue(database.in_transaction)
                with self.assertRaises(LocalStorageError):
                    store.read('missing')
                with self.assertRaises(ValueError):
                    captured[0]('missing', lambda _: self.fail('Reader cannot survive cleanup failure'))
                with self.assertRaisesRegex(sqlite3.OperationalError, 'close pending'):
                    store.close()
                self.assertFalse(store._closed)
            finally:
                store._connection = database
                store.close()

    def test_actual_file_core_store_lock_order_same_facts_loan_and_original_publisher_request(self):
        helper = facts_fixture.ReaderFactsTests()
        for outcome in ('success', 'mutate', 'denied', 'unknown'):
            with self.subTest(outcome=outcome), helper.file() as (path, root, _, final), TemporaryDirectory() as directory:
                reader = helper.transfer_ready(root, final)
                core, record, publisher, projection, facts, calls, state, _ = helper.bridge(root, reader)
                original_call = core._call
                def call(family, name, *args):
                    if family == 'publisher' and name == 'authorize':
                        calls.append((family, name, args))
                        self.assertEqual(args, (17, 31, 0, 0))
                        if outcome == 'mutate':
                            os.utime(path / 'payload-original', ns=(1, 1))
                        return -35 if outcome == 'denied' else -36 if outcome == 'unknown' else 0
                    return original_call(family, name, *args)
                core._call = call
                facts.validate()
                original_input = facts.pending_input
                with self.store(Path(directory) / 'core.sqlite') as store:
                    original = self.original(store)
                    received = []
                    def transaction():
                        with facts.serialized():
                            store.inspect_publication_projected_attached(
                                lambda read: read('absent', lambda row: received.append(row)),
                                original, current=lambda: facts.before_lookup(publisher))
                    with self.assertRaises(RuntimeError):
                        facts.before_lookup(publisher)
                    if outcome == 'success':
                        transaction()
                        self.assertEqual(received, [None])
                    else:
                        with self.assertRaises(LocalFileError if outcome == 'mutate' else LocalCoreError):
                            transaction()
                        self.assertEqual(received, [])
                    self.assertFalse(store._connection.in_transaction)
                    self.assertIs(facts.pending_input, original_input)
                    self.assertIs(root._readers[id(reader)], reader)
                    self.assertIs(core._loans[10], record)
                    self.assertEqual(sum(f == 'buffer' and n == 'reserve' for f, n, _ in calls), 1)
                    state['meta_cleanup'] = False
                    self.assertFalse(facts.close())
                    self.assertIs(facts.pending_input, original_input)
                    state['meta_cleanup'] = True
                    self.assertTrue(facts.close())
                    self.assertIs(root._readers[id(reader)], reader)
                    self.assertEqual(projection.pending_outputs, ())


if __name__ == '__main__':
    unittest.main()
