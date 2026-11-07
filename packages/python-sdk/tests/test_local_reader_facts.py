"""Actual POSIX/SQLite fencing with mocked scalar Core, not public Wasm/Store ACK."""
import asyncio
import copy
import json
import os
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError, _Output
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_reader_facts import OriginalReaderFacts
from actql_sdk._local_storage import ByteFence, CapacityReservation, LocalByteStore, StoredBytes
import test_local_commit_store_caller as core_fixture
import test_local_file_reader as file_fixture


class ReaderFactsTests(unittest.TestCase):
    body = file_fixture.LocalFileReaderTests.body
    digest = file_fixture.LocalFileReaderTests.digest
    file = file_fixture.LocalFileReaderTests.file
    consume = file_fixture.LocalFileReaderTests.consume

    def bridge(self, root, reader, *, result=2, binding_index=7):
        core, parent, publisher, projection, calls, state, _, _, _ = core_fixture.OriginalCommitStoreCallerTests.bridge(self)
        record = _Output(core._identity, 10, 71, 65536, 'payload_record')
        core._loans[10] = record
        core._next_ticket = 11
        core._retired = False
        core._closed = False
        state.update(snapshot=0, binding=0, fill=0, meta_cleanup=True, reserve_trap=False)
        inputs, wires = {}, []
        original_call = core._call
        def call(family, name, *args):
            if family == 'buffer' and name in ('reserve', 'fill', 'seal', 'close'):
                calls.append((family, name, args))
                if name == 'reserve':
                    if state['reserve_trap']:
                        core._closing = True
                        raise OSError('Original metadata reserve outcome unknown')
                    ticket, size, physical_bytes = args
                    self.assertLessEqual(size, 512)
                    self.assertGreater(physical_bytes, size)
                    inputs[500 + ticket] = ticket
                    return 500 + ticket
                ticket = inputs[args[0]]
                if name == 'fill':
                    self.assertEqual(args[1:], (0, len(core._inputs[ticket].payload)))
                    wires.append(bytes(core._read(ticket, i) for i in range(args[2])))
                    return state['fill']
                if name == 'seal':
                    return 0
                if core._cleanup(ticket) != 0:
                    return -9
                del inputs[args[0]]
                return 0
            if family == 'payload_record':
                calls.append((family, name, args))
                self.assertEqual((name, args), ('validate_snapshot', (71, 511, 31)))
                return state['snapshot']
            if family == 'publication_commit_export' and name == 'validate_payload_binding':
                calls.append((family, name, args))
                self.assertEqual(args, (23, 71, 31, result, binding_index))
                return state['binding']
            return original_call(family, name, *args)
        core._call = call
        facts = OriginalReaderFacts(projection, record, root, reader, result, binding_index,
                                    'sha256:' + '1' * 64, 'sha256:' + '3' * 64,
                                    cleanup=lambda: state['meta_cleanup'], stopped=lambda _: True)
        return core, record, publisher, projection, facts, calls, state, wires

    def store(self, path):
        return LocalByteStore(path, max_records=8, max_record_bytes=256, max_payload_bytes=1024)

    def original(self, store):
        self.assertEqual(store.compare_exchange('original-record', None, b'original-sealed'), 0)
        self.assertTrue(store.reserve_capacity('publication_payload', 'original-record', 64, 1, 128, 2))
        return ((ByteFence('original-record', 0, b'original-sealed'),
                 CapacityReservation('publication_payload', 'original-record', 64, 1)),)

    def transfer_ready(self, root, final):
        reader = root.open_reader(final)
        self.consume(root, reader)
        return reader

    def test_one_bounded_original_input_keeps_reader_and_checks_full_decimal_facts(self):
        with self.file() as (_, root, _, final):
            reader = self.transfer_ready(root, final)
            core, record, _, _, facts, calls, _, wires = self.bridge(root, reader)
            facts.validate()
            first = facts.pending_input
            facts.validate()
            self.assertIs(facts.pending_input, first)
            self.assertEqual(len(wires), 1)
            self.assertEqual(json.loads(wires[0]), {
                'store_authority_cid': 'sha256:' + '1' * 64,
                'material_generation_cid': 'sha256:' + '3' * 64,
                'device': str(os.fstat(reader.descriptor).st_dev),
                'inode': str(os.fstat(reader.descriptor).st_ino),
                'size': '11', 'physical_digest': self.digest})
            self.assertIs(core._loans[10], record)
            self.assertIs(root._readers[id(reader)], reader)
            self.assertEqual(sum(f == 'buffer' and n == 'reserve' for f, n, _ in calls), 1)
            self.assertTrue(facts.close())
            self.assertIs(root._readers[id(reader)], reader)
            self.assertTrue(facts.close())
            with self.assertRaises(RuntimeError):
                facts.validate()

    def test_copied_reader_record_invalid_cids_and_indexes_refuse_before_io(self):
        with self.file() as (_, root, _, final):
            reader = self.transfer_ready(root, final)
            core, record, _, projection, facts, calls, _, _ = self.bridge(root, reader)
            before = len(calls)
            for value, candidate, result, binding, cid in (
                (record, copy.copy(reader), 2, 7, 'sha256:' + '1' * 64),
                (copy.copy(record), reader, 2, 7, 'sha256:' + '1' * 64),
                (record, reader, True, 7, 'sha256:' + '1' * 64),
                (record, reader, 2, -1, 'sha256:' + '1' * 64),
                (record, reader, 2, 7, '1' * 100000),
            ):
                with self.assertRaises(ValueError):
                    OriginalReaderFacts(projection, value, root, candidate, result, binding, cid,
                                        'sha256:' + '3' * 64, cleanup=lambda: True, stopped=lambda _: True)
            self.assertEqual(len(calls), before)
            self.assertTrue(facts.close())
            self.assertIs(core._loans[10], record)

    def test_incomplete_reader_cannot_create_metadata_or_call_core_binding(self):
        with self.file(b'') as (_, root, _, final):
            reader = root.open_reader(final)
            _, _, _, _, facts, calls, _, _ = self.bridge(root, reader)
            with self.assertRaisesRegex(LocalFileError, 'incomplete'):
                facts.validate()
            self.assertEqual(calls, [])
            self.assertIsNone(facts.pending_input)
            self.assertTrue(facts.close())

    def test_owner_refusal_keeps_same_metadata_and_no_retry_or_cleanup(self):
        with self.file() as (_, root, _, final):
            reader = self.transfer_ready(root, final)
            _, _, _, _, facts, calls, state, wires = self.bridge(root, reader)
            state['snapshot'] = -32
            with self.assertRaises(LocalCoreError):
                facts.validate()
            original = facts.pending_input
            self.assertIsNotNone(original)
            state['snapshot'] = 0
            facts.validate()
            self.assertIs(facts.pending_input, original)
            self.assertEqual(len(wires), 1)
            self.assertFalse(any(n == 'close' for _, n, _ in calls))
            self.assertTrue(facts.close())

    def test_failed_transfer_requires_same_input_cleanup_without_refill(self):
        with self.file() as (_, root, _, final):
            reader = self.transfer_ready(root, final)
            _, _, _, _, facts, calls, state, _ = self.bridge(root, reader)
            state['fill'] = -4
            with self.assertRaises(LocalCoreError):
                facts.validate()
            original = facts.pending_input
            state['fill'] = 0
            with self.assertRaisesRegex(RuntimeError, 'requires cleanup'):
                facts.validate()
            self.assertIs(facts.pending_input, original)
            self.assertEqual(sum(n == 'fill' for _, n, _ in calls), 1)
            self.assertTrue(facts.close())

    def test_failed_metadata_cleanup_retains_same_input_and_original_reader(self):
        with self.file() as (_, root, _, final):
            reader = self.transfer_ready(root, final)
            core, record, _, _, facts, _, state, _ = self.bridge(root, reader)
            facts.validate()
            original = facts.pending_input
            state['meta_cleanup'] = False
            self.assertFalse(facts.close())
            self.assertIs(facts.pending_input, original)
            self.assertIs(core._loans[original.ticket], original)
            self.assertIs(core._loans[10], record)
            self.assertIs(root._readers[id(reader)], reader)
            with self.assertRaises(RuntimeError):
                facts.validate()
            state['meta_cleanup'] = True
            self.assertTrue(facts.close())
            self.assertIs(root._readers[id(reader)], reader)

    def test_unknown_reserve_ticket_requires_original_core_retirement_not_callback_only(self):
        with self.file() as (_, root, _, final):
            reader = self.transfer_ready(root, final)
            core, _, _, _, facts, calls, state, _ = self.bridge(root, reader)
            state['reserve_trap'] = True
            with self.assertRaisesRegex(OSError, 'outcome unknown'):
                facts.validate()
            self.assertEqual(facts.uncertain_acquisition_ticket, 11)
            self.assertIsNone(facts.pending_input)
            self.assertFalse(facts.close())
            self.assertEqual(core._cleanup(11), 0)
            self.assertFalse(facts.close())
            self.assertEqual(sum(n == 'reserve' for _, n, _ in calls), 1)
            # This is a mocked original Core retirement fact, not a physical
            # Wasm close_pool receipt. The callback alone above was insufficient.
            core._retired = True
            self.assertTrue(facts.close())
            self.assertIs(root._readers[id(reader)], reader)

    def test_precommit_requires_serialized_original_context_and_keeps_loan_active(self):
        with self.file() as (_, root, _, final):
            reader = self.transfer_ready(root, final)
            _, _, publisher, _, facts, calls, _, _ = self.bridge(root, reader)
            with self.assertRaisesRegex(RuntimeError, 'serialized transaction'):
                facts.before_commit(publisher)
            self.assertEqual(calls, [])
            with facts.serialized():
                with self.assertRaises(RuntimeError):
                    facts.close()
                with self.assertRaises(RuntimeError):
                    with facts.serialized():
                        pass
                facts.before_commit(publisher)
                self.assertIsNotNone(facts.pending_input)
            self.assertTrue(facts.close())

    def test_actual_sqlite_prefix_commits_only_after_original_facts_and_publisher_checks(self):
        with self.file() as (_, root, _, final), TemporaryDirectory() as directory:
            reader = self.transfer_ready(root, final)
            _, _, publisher, projection, facts, calls, _, _ = self.bridge(root, reader)
            with self.store(Path(directory) / 'core.sqlite') as store:
                original = self.original(store)
                facts.validate()
                with facts.serialized():
                    self.assertEqual(store.compare_exchange_projected_attached(
                        2, lambda ordinal, consume: projection.project_contract(ordinal, consume),
                        original, before_commit=lambda: facts.before_commit(publisher)), (0, 0))
                self.assertEqual(store.read('namespace:20:publication_contract:sha256:' + 'a' * 64),
                                 StoredBytes(0, b'{"e\xcc\x81/~\xf0\x9f\x98\x80":null,"n":1}\r\n'))
                self.assertIsNotNone(facts.pending_input)
                self.assertEqual(sum(f == 'publisher' for f, _, _ in calls), 1)
                self.assertTrue(facts.close())

    def test_changed_final_name_before_commit_rolls_back_every_projected_write(self):
        with self.file() as (path, root, _, final), TemporaryDirectory() as directory:
            reader = self.transfer_ready(root, final)
            _, _, publisher, projection, facts, calls, _, _ = self.bridge(root, reader)
            with self.store(Path(directory) / 'core.sqlite') as store:
                original = self.original(store)
                facts.validate()
                def project(ordinal, consume):
                    projection.project_contract(ordinal, consume)
                    if ordinal == 1:
                        (path / final.name).rename(path / 'moved-original')
                        (path / final.name).write_bytes(self.body)
                        os.chmod(path / final.name, 0o600)
                with facts.serialized(), self.assertRaisesRegex(LocalFileError, 'generation changed'):
                    store.compare_exchange_projected_attached(2, project, original,
                                                              before_commit=lambda: facts.before_commit(publisher))
                self.assertIsNone(store.read('namespace:20:publication_contract:sha256:' + 'a' * 64))
                self.assertIsNone(store.read('namespace:20:publication_contract:sha256:' + 'b' * 64))
                self.assertEqual(store.read('original-record'), StoredBytes(0, b'original-sealed'))
                self.assertIsNotNone(facts.pending_input)
                self.assertFalse(any(f == 'publisher' for f, _, _ in calls))
                self.assertTrue(facts.close())

    def test_publisher_mutation_denial_unknown_and_coroutine_cancel_do_not_commit_prefix(self):
        for outcome in ('mutate', 'denied', 'unknown', 'cancel'):
            with self.subTest(outcome=outcome), self.file() as (path, root, _, final), TemporaryDirectory() as directory:
                reader = self.transfer_ready(root, final)
                core, _, publisher, projection, facts, _, state, _ = self.bridge(root, reader)
                old_call = core._call
                def call(family, name, *args):
                    code = old_call(family, name, *args)
                    if family == 'publisher':
                        if outcome == 'mutate':
                            (path / final.name).rename(path / 'moved-original')
                            (path / final.name).write_bytes(self.body)
                            os.chmod(path / final.name, 0o600)
                        elif outcome == 'cancel':
                            raise asyncio.CancelledError('Original publisher callback cancelled')
                        else:
                            return -35 if outcome == 'denied' else -36
                    return code
                core._call = call
                facts.validate()
                with self.store(Path(directory) / 'core.sqlite') as store:
                    original = self.original(store)
                    expected = LocalFileError if outcome == 'mutate' else (asyncio.CancelledError if outcome == 'cancel' else LocalCoreError)
                    with facts.serialized(), self.assertRaises(expected):
                        store.compare_exchange_projected_attached(1, lambda i, consume: projection.project_contract(i, consume),
                                                                  original, before_commit=lambda: facts.before_commit(publisher))
                    self.assertIsNone(store.read('namespace:20:publication_contract:sha256:' + 'a' * 64))
                    self.assertIsNotNone(facts.pending_input)
                    self.assertIs(root._readers[id(reader)], reader)
                    self.assertTrue(facts.close())

    def test_actual_commit_ack_loss_keeps_original_input_and_observes_without_reprojection(self):
        class LostAck(sqlite3.Connection):
            armed = False
            commits = 0
            def execute(self, sql, *args, **kwargs):
                result = super().execute(sql, *args, **kwargs)
                if sql == 'COMMIT' and self.armed:
                    self.commits += 1
                    self.armed = False
                    raise OSError('Original physical COMMIT ACK lost')
                return result
        physical = sqlite3.connect
        with self.file() as (_, root, _, final), TemporaryDirectory() as directory, patch(
                'actql_sdk._local_storage.sqlite3.connect', side_effect=lambda *a, **kw: physical(*a, **(kw | {'factory': LostAck}))):
            reader = self.transfer_ready(root, final)
            _, _, publisher, projection, facts, calls, _, _ = self.bridge(root, reader)
            with self.store(Path(directory) / 'core.sqlite') as store:
                original = self.original(store)
                facts.validate()
                store._connection.armed = True
                with facts.serialized(), self.assertRaisesRegex(OSError, 'ACK lost'):
                    store.compare_exchange_projected_attached(1, lambda i, consume: projection.project_contract(i, consume),
                                                              original, before_commit=lambda: facts.before_commit(publisher))
                first = facts.pending_input
                before = len(calls)
                self.assertEqual(store.read('namespace:20:publication_contract:sha256:' + 'a' * 64),
                                 StoredBytes(0, b'{"e\xcc\x81/~\xf0\x9f\x98\x80":null,"n":1}\r\n'))
                self.assertEqual(store._connection.commits, 1)
                self.assertEqual(len(calls), before)
                self.assertIs(facts.pending_input, first)
                self.assertTrue(facts.close())

    def test_original_core_pool_retirement_can_release_holder_after_pending_metadata_cleanup(self):
        with self.file() as (_, root, _, final):
            reader = self.transfer_ready(root, final)
            core, _, _, _, facts, _, state, _ = self.bridge(root, reader)
            facts.validate()
            original = facts.pending_input
            old_call = core._call
            def call(family, name, *args):
                if (family, name) == ('buffer', 'close_pool'):
                    return 0 if all(core._cleanup(ticket) == 0 for ticket in list(core._inputs)) else -9
                return old_call(family, name, *args)
            core._call = call
            for name in ('_store', '_linker', '_module', '_engine'):
                setattr(core, name, None)
            for name in ('_native_observers', '_native_loans', '_compute_loans', '_task_loans', '_result_loans'):
                setattr(core, name, {})
            state['meta_cleanup'] = False
            self.assertFalse(core.close())
            self.assertFalse(core._retired)
            self.assertFalse(facts.close())
            self.assertIs(facts.pending_input, original)
            state['meta_cleanup'] = True
            # Real Python retirement/disposal path, with mocked scalar close_pool;
            # no Wasm or physical Core pool cleanup receipt is claimed.
            self.assertTrue(core.close())
            self.assertTrue(core._retired)
            self.assertTrue(facts.close())
            self.assertIsNone(facts.pending_input)
            self.assertIs(root._readers[id(reader)], reader)
