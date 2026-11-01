"""Original field-order transport with mocked Core; actual SQLite is not an ACK."""
import copy
import os
import sqlite3
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import LocalCoreError, _Output
from actql_sdk._local_storage import ByteFence, CapacityReservation, ByteWrite, LocalByteStore, LocalStorageError, StoredBytes
from actql_sdk._local_reader_facts import OriginalReaderFacts
from actql_sdk._local_files import LocalFileError
import test_local_commit_store_caller as fixture
import test_local_file_reader as file_fixture


class StoreInventoryTests(unittest.TestCase):
    body = file_fixture.LocalFileReaderTests.body

    def bridge(self):
        core, parent, publisher, projection, calls, state, identities, wires, key = fixture.OriginalCommitStoreCallerTests.bridge(self)
        for ordinal in range(14):
            if ordinal not in identities:
                identities[ordinal] = ('sha256:' + format(ordinal, '064x')).encode('ascii')
                wires[ordinal] = ('original-owner-field-' + str(ordinal)).encode('ascii')
        state['results'] = 1
        old_call = core._call
        def call(family, name, *args):
            if (family, name) == ('publication_commit_export', 'result_count'):
                calls.append((family, name, args))
                self.assertEqual(args, (23, 31))
                return state['results']
            if (family, name) == ('publication_commit_export', 'produce_schema') and args[2] == 1:
                # Two original Result occurrences can legitimately share a schema.
                return old_call(family, name, args[0], args[1], 0, args[3])
            return old_call(family, name, *args)
        core._call = call
        return core, parent, publisher, projection, calls, state, identities, wires, key

    def store(self, path):
        return LocalByteStore(path, max_records=32, max_record_bytes=256,
                              max_payload_bytes=8192)

    def original(self, store):
        self.assertEqual(store.compare_exchange('original-record', None, b'original-sealed'), 0)
        self.assertTrue(store.reserve_capacity('publication_payload', 'original-record', 64, 1, 128, 2))
        return ((ByteFence('original-record', 0, b'original-sealed'),
                 CapacityReservation('publication_payload', 'original-record', 64, 1)),)

    def test_result_count_forwards_original_parent_and_current_context_without_projection(self):
        core, parent, _, projection, calls, state, _, _, _ = self.bridge()
        self.assertEqual(core.publication_commit_result_count(parent, 31), 1)
        self.assertEqual(projection.storage_count(), 16)
        state['results'] = 0
        self.assertEqual(projection.storage_count(), 15)
        self.assertIs(core._loans[7], parent)
        self.assertFalse(any(n == 'reserve' for _, n, _ in calls))
        self.assertEqual(projection.pending_outputs, ())

    def test_result_count_rejects_copy_wrong_revision_controls_and_bad_scalars(self):
        core, parent, _, _, calls, state, _, _, _ = self.bridge()
        for value, current in ((copy.copy(parent), 31), (parent, True), (parent, 0)):
            with self.assertRaises(ValueError):
                core.publication_commit_result_count(value, current)
        self.assertEqual(calls, [])
        for value in (True, 1.5, None, 2**31, -32, -5):
            state['results'] = value
            with self.assertRaises(LocalCoreError):
                core.publication_commit_result_count(parent, 31)
        self.assertIs(core._loans[7], parent)

    def test_all_original_inventory_schema_and_scoped_index_reference_commit_in_one_sqlite_transaction(self):
        _, _, publisher, projection, calls, state, identities, wires, key = self.bridge()
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.original(store)
            ordinals = []
            def project(ordinal, consume):
                ordinals.append(ordinal)
                self.assertEqual(projection.pending_outputs, ())
                projection.project_storage_entry(ordinal, consume)
                self.assertEqual(projection.pending_outputs, ())
            with projection.serialized():
                count = projection.storage_count()
                self.assertEqual(count, 16)
                self.assertEqual(store.store_publication_projected_attached(
                    count, project, originals,
                    before_commit=lambda: projection.authorize_commit(publisher)), (0,) * 16)
            self.assertEqual(ordinals, list(range(16)))
            for ordinal in range(14):
                self.assertEqual(store.read('namespace:20:publication_contract:' + identities[ordinal].decode('ascii')),
                                 StoredBytes(0, wires[ordinal]))
            self.assertEqual(store.read('namespace:13:result_schema:' + state['schema_identity'].decode('ascii')),
                             StoredBytes(0, b'{"id":{"nullable":false,"type":"number"}}'))
            self.assertEqual(store.read('namespace:12:public_index:' + key.decode('ascii')),
                             StoredBytes(0, identities[7]))
            self.assertFalse(any(f in ('run', 'source', 'task', 'model', 'effect') for f, _, _ in calls))

    def test_shared_schema_occurrences_reuse_exact_bytes_without_generation_change(self):
        _, _, publisher, projection, _, state, _, _, _ = self.bridge()
        state['results'] = 2
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.original(store)
            for _ in range(2):
                with projection.serialized():
                    self.assertEqual(store.store_publication_projected_attached(
                        projection.storage_count(), projection.project_storage_entry,
                        originals, before_commit=lambda: projection.authorize_commit(publisher)),
                        (0,) * 17)
                self.assertEqual(projection.pending_outputs, ())
            self.assertEqual(store.read('namespace:13:result_schema:' + state['schema_identity'].decode('ascii')),
                             StoredBytes(0, b'{"id":{"nullable":false,"type":"number"}}'))
            self.assertEqual(store._connection.execute('SELECT count(*) FROM core_bytes').fetchone(), (17,))

    def test_different_stored_index_rolls_back_prefix_without_replacing_or_adopting_it(self):
        _, _, publisher, projection, _, _, identities, _, key = self.bridge()
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.original(store)
            index_key = 'namespace:12:public_index:' + key.decode('ascii')
            self.assertEqual(store.compare_exchange(index_key, None, b'saved-original-index'), 0)
            with projection.serialized():
                self.assertIsNone(store.store_publication_projected_attached(
                    projection.storage_count(), projection.project_storage_entry,
                    originals, before_commit=lambda: self.fail('Conflict cannot authorize publication')))
            self.assertEqual(store.read(index_key), StoredBytes(0, b'saved-original-index'))
            for identity in identities.values():
                self.assertIsNone(store.read('namespace:20:publication_contract:' + identity.decode('ascii')))
            self.assertEqual(len(projection.pending_outputs), 2)
            self.assertTrue(projection.close())

    def test_reused_schema_requires_exact_bytes_and_preserves_existing_generation(self):
        for raw in (b'{"id":{"nullable":false,"type":"string"}}',
                    b'{"id":{"nullable":false,"type":"number"}}'):
            with self.subTest(raw=raw), TemporaryDirectory() as directory:
                _, _, publisher, projection, _, state, identities, _, _ = self.bridge()
                with self.store(Path(directory) / 'core.sqlite') as store:
                    originals = self.original(store)
                    key = 'namespace:13:result_schema:' + state['schema_identity'].decode('ascii')
                    self.assertEqual(store.compare_exchange(key, None, b'old-bytes'), 0)
                    self.assertEqual(store.compare_exchange(key, 0, raw), 1)
                    with projection.serialized():
                        observed = store.store_publication_projected_attached(
                            projection.storage_count(), projection.project_storage_entry,
                            originals, before_commit=lambda: projection.authorize_commit(publisher))
                    if b'string' in raw:
                        self.assertIsNone(observed)
                        self.assertIsNone(store.read('namespace:20:publication_contract:' + identities[0].decode('ascii')))
                        self.assertTrue(projection.close())
                    else:
                        self.assertEqual(observed, (0,) * 14 + (1, 0))
                    self.assertEqual(store.read(key), StoredBytes(1, raw))

    def test_shared_schema_strict_store_collision_rolls_back_full_inventory_without_hiding_conflict(self):
        _, _, publisher, projection, _, state, identities, _, _ = self.bridge()
        state['results'] = 2
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.original(store)
            with projection.serialized(), self.assertRaisesRegex(ValueError, 'Duplicate'):
                store.compare_exchange_projected_attached(
                    projection.storage_count(),
                    lambda ordinal, consume: projection.project_storage_entry(ordinal, consume),
                    originals, before_commit=lambda: projection.authorize_commit(publisher))
            for identity in identities.values():
                self.assertIsNone(store.read('namespace:20:publication_contract:' + identity.decode('ascii')))
            self.assertIsNone(store.read('namespace:13:result_schema:' + state['schema_identity'].decode('ascii')))
            self.assertEqual(store.read('original-record'), StoredBytes(0, b'original-sealed'))
            self.assertEqual(len(projection.pending_outputs), 2)
            self.assertTrue(projection.close())

    def test_owner_denial_and_count_overflow_do_not_reserve_or_misclassify_as_empty_inventory(self):
        _, _, _, projection, calls, state, _, _, _ = self.bridge()
        for count in (-32, -5):
            state['results'] = count
            with self.assertRaises(LocalCoreError) as error:
                projection.storage_count()
            self.assertEqual(error.exception.code, count)
        state['results'] = 2**31 - 1
        with self.assertRaises(LocalCoreError):
            projection.storage_count()
        self.assertFalse(any(n == 'reserve' for _, n, _ in calls))
        self.assertEqual(projection.pending_outputs, ())

    def test_ordinal_boundaries_do_not_substitute_json_index_body_or_offset_schema_index(self):
        _, _, _, projection, calls, state, identities, _, key = self.bridge()
        consumed = []
        def schema(write):
            self.assertEqual(write.key, 'namespace:13:result_schema:' + state['schema_identity'].decode('ascii'))
            self.assertEqual(write.payload, b'{"id":{"nullable":false,"type":"number"}}')
            consumed.append('schema')
        def index(write):
            self.assertEqual(write.key, 'namespace:12:public_index:' + key.decode('ascii'))
            self.assertEqual(write.payload, identities[7])
            consumed.append('index')
        projection.project_storage_entry(14, schema)
        projection.project_storage_entry(15, index)
        self.assertEqual(consumed, ['schema', 'index'])
        self.assertIn(('publication_commit_export', 'produce_schema', (208, 31, 0, 0)), calls)
        with self.assertRaises(ValueError):
            projection.project_storage_entry(16, lambda _: None)
        with self.assertRaises(ValueError):
            projection.project_storage_entry(True, lambda _: None)

    def test_cleanup_failure_stops_projection_and_retains_original_pair_without_next_ordinal(self):
        _, _, _, projection, calls, state, _, _, _ = self.bridge()
        state['cleanup'] = False
        with self.assertRaises(LocalCoreError):
            projection.project_storage_entry(0, lambda _: None)
        original = projection.pending_outputs
        self.assertEqual(len(original), 2)
        with self.assertRaises(RuntimeError):
            projection.project_storage_entry(1, lambda _: None)
        self.assertFalse(projection.close())
        self.assertEqual(projection.pending_outputs, original)
        state['cleanup'] = True
        self.assertTrue(projection.close())
        self.assertFalse(any(n == 'produce_schema' for _, n, _ in calls))

    def test_publication_insert_only_rejects_cas_update_and_original_payload_address(self):
        with TemporaryDirectory() as directory, self.store(Path(directory) / 'core.sqlite') as store:
            originals = self.original(store)
            for write in (ByteWrite('schema', 0, b'original'),
                          ByteWrite('original-record', None, b'original-sealed')):
                with self.subTest(write=write), self.assertRaises(ValueError):
                    store.store_publication_projected_attached(
                        1, lambda _, consume: consume(write), originals,
                        before_commit=lambda: self.fail('Invalid write cannot commit'))
            self.assertEqual(store.read('original-record'), StoredBytes(0, b'original-sealed'))

    def test_stored_equality_read_is_bounded_before_fetch_and_never_normalizes_unicode(self):
        for existing in (b'e\xcc\x81', b'x' * 257):
            with self.subTest(existing=existing), TemporaryDirectory() as directory:
                with self.store(Path(directory) / 'core.sqlite') as store:
                    originals = self.original(store)
                    store._connection.execute('INSERT INTO core_bytes VALUES (?, ?, ?)',
                                              ('schema', 0, existing))
                    queries = []
                    store._connection.set_trace_callback(queries.append)
                    operation = lambda: store.store_publication_projected_attached(
                        1, lambda _, consume: consume(ByteWrite('schema', None, b'\xc3\xa9')),
                        originals, before_commit=lambda: self.fail('Different bytes cannot commit'))
                    if len(existing) > 256:
                        with self.assertRaisesRegex(LocalStorageError, 'capacity exceeded'):
                            operation()
                    else:
                        self.assertIsNone(operation())
                    self.assertFalse(any(q.startswith('SELECT payload FROM') for q in queries))
                    self.assertEqual(store.read('original-record'), StoredBytes(0, b'original-sealed'))

    def test_actual_file_sqlite_full_inventory_keeps_original_metadata_loan_and_current_fences(self):
        for outcome in ('success', 'mutate', 'denied', 'unknown', 'lost_ack'):
            with self.subTest(outcome=outcome), file_fixture.LocalFileReaderTests.file(self) as (path, root, _, final), TemporaryDirectory() as directory:
                reader = root.open_reader(final)
                file_fixture.LocalFileReaderTests.consume(self, root, reader)
                core, parent, publisher, projection, calls, state, _, _, _ = self.bridge()
                record = _Output(core._identity, 10, 71, 65536, 'payload_record')
                core._loans[10] = record
                core._next_ticket = 11
                core._retired = False
                core._closed = False
                state['meta_cleanup'] = True
                original_call = core._call
                inputs = {}
                def call(family, name, *args):
                    if family == 'buffer' and name in ('reserve', 'fill', 'seal', 'close'):
                        calls.append((family, name, args))
                        if name == 'reserve':
                            ticket, size, _ = args
                            self.assertLessEqual(size, 512)
                            inputs[500 + ticket] = ticket
                            return 500 + ticket
                        ticket = inputs[args[0]]
                        if name == 'close':
                            if core._cleanup(ticket) != 0:
                                return -9
                            del inputs[args[0]]
                        return 0
                    if family == 'payload_record' and name == 'validate_snapshot':
                        self.assertEqual(args, (71, 511, 31))
                        return 0
                    if family == 'publication_commit_export' and name == 'validate_payload_binding':
                        self.assertEqual(args, (23, 71, 31, 0, 0))
                        return 0
                    if family == 'publisher':
                        if outcome == 'mutate':
                            os.utime(path / 'payload-original', ns=(1, 1))
                        if outcome in ('denied', 'unknown'):
                            state['publisher'] = -35 if outcome == 'denied' else -36
                    return original_call(family, name, *args)
                core._call = call
                facts = OriginalReaderFacts(projection, record, root, reader, 0, 0,
                    'sha256:' + '1' * 64, 'sha256:' + '3' * 64,
                    cleanup=lambda: state['meta_cleanup'], stopped=lambda _: True)
                class LostAck(sqlite3.Connection):
                    def execute(connection, sql, *args):
                        result = super().execute(sql, *args)
                        if sql == 'COMMIT':
                            raise OSError('Physical COMMIT succeeded; response lost')
                        return result
                with self.store(Path(directory) / 'core.sqlite') as store:
                    originals = self.original(store)
                    if outcome == 'lost_ack':
                        store._connection.close()
                        store._connection = sqlite3.connect(Path(directory) / 'core.sqlite', isolation_level=None, factory=LostAck)
                        store._physical._connection = store._connection
                    facts.validate()
                    original_loan = facts.pending_input
                    count = projection.storage_count()
                    def transaction():
                        with facts.serialized():
                            return store.store_publication_projected_attached(
                                count, projection.project_storage_entry, originals,
                                before_commit=lambda: facts.before_commit(publisher))
                    if outcome == 'success':
                        self.assertEqual(transaction(), (0,) * 16)
                    else:
                        expected = LocalFileError if outcome == 'mutate' else OSError if outcome == 'lost_ack' else LocalCoreError
                        with self.assertRaises(expected):
                            transaction()
                    self.assertEqual(store._connection.execute('SELECT count(*) FROM core_bytes').fetchone(),
                                     (17 if outcome in ('success', 'lost_ack') else 1,))
                    self.assertIs(facts.pending_input, original_loan)
                    self.assertIs(core._loans[7], parent)
                    self.assertIs(root._readers[id(reader)], reader)
                    self.assertEqual(sum(n == 'reserve' and f == 'buffer' for f, n, _ in calls), 1)
                    state['meta_cleanup'] = False
                    self.assertFalse(facts.close())
                    self.assertIs(facts.pending_input, original_loan)
                    state['meta_cleanup'] = True
                    self.assertTrue(facts.close())
                    self.assertIs(root._readers[id(reader)], reader)
