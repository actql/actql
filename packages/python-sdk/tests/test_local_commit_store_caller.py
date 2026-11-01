"""Real Python facade/SQLite wiring with mock Core; actual Wasm is unverified."""
import asyncio
import copy
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import RLock
import unittest

from actql_sdk._local_commit_projection import OriginalCommitProjection
from actql_sdk._local_core import LocalCore, LocalCoreError, _Output
from actql_sdk._local_storage import (
    ByteFence, CapacityReservation, LocalByteStore, StoredBytes,
)
from local_abi_declaration_fixture import original_byte_fixture_port


class OriginalCommitStoreCallerTests(unittest.TestCase):
    def bridge(self):
        core = LocalCore.__new__(LocalCore)
        core._identity = object()
        core._lock = RLock()
        core._closing = False
        core._inputs = {}
        core._released = set()
        core._next_ticket = 8
        parent = _Output(core._identity, 7, 23, 1048576, 'publication')
        publisher = _Output(core._identity, 6, 17, 8192, 'publisher')
        core._loans = {7: parent, 6: publisher}
        calls, handles, outputs = [], {}, {}
        identities = {0: b'sha256:' + b'a' * 64,
                      1: b'sha256:' + b'b' * 64,
                      7: b'sha256:' + b'c' * 64}
        wires = {0: b'{"e\xcc\x81/~\xf0\x9f\x98\x80":null,"n":1}\r\n',
                 1: b'original-invocation', 7: b'original-index-body'}
        key = b'd' * 64
        state = {'cleanup': True, 'produce': 0, 'publisher': 0, 'count': 14,
                 'reserve_fail_at': None, 'identity_override': None, 'close_calls': [],
                 'schema_identity': b'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513',
                 'schema_wire': b'{"id":{"nullable":false,"type":"number"}}'}

        def call(family, name, *args):
            calls.append((family, name, args))
            if family == 'publisher':
                self.assertEqual((name, args), ('authorize', (17, 31, 1, 23)))
                return state['publisher']
            if family == 'buffer':
                self.assertEqual(name, 'byte')
                return outputs[args[0]][args[1]]
            self.assertEqual(family, 'publication_commit_export')
            if name == 'count':
                self.assertEqual(args, (23, 31))
                return state['count']
            if name in ('reserve', 'reserve_bounded'):
                self.assertEqual(args[0], 23)
                maximum, physical = ((1048576, args[2]) if name == 'reserve' else args[2:])
                self.assertGreaterEqual(physical, 2 * maximum)
                self.assertTrue(type(maximum) is int and 1 <= maximum <= 1048576)
                self.assertLessEqual(len(handles), 1)
                if args[1] == state['reserve_fail_at']:
                    return -4
                handle = 200 + args[1]
                handles[handle] = args[1]
                return handle
            if name == 'produce_schema':
                self.assertEqual(args[1], 31)
                if state['produce']:
                    return state['produce']
                index, field = args[2:]
                if index != 0:
                    return -3
                self.assertIn(field, (0, 1))
                outputs[args[0]] = state['schema_identity' if field == 0 else 'schema_wire']
                return 0
            if name in ('produce_material', 'produce_index_key'):
                self.assertEqual(args[1], 31)
                if state['produce']:
                    return state['produce']
                if name == 'produce_index_key':
                    outputs[args[0]] = key
                else:
                    ordinal, field = args[2:]
                    if ordinal not in identities:
                        return -32
                    self.assertIn(field, (0, 3))
                    outputs[args[0]] = ((identities[ordinal] if state['identity_override'] is None
                                        else state['identity_override'])
                                       if field == 3 else wires[ordinal])
                return 0
            if name == 'length':
                return len(outputs[args[0]])
            if name == 'close':
                handle = args[0]
                state['close_calls'].append(handle)
                if core._cleanup(handles[handle]) != 0:
                    return -9
                del handles[handle]
                outputs.pop(handle, None)
                return 0
            self.fail(f'Unexpected Core operation: {name}')

        core._call = original_byte_fixture_port(call)
        caller = OriginalCommitProjection(core, parent, 31, cleanup=lambda: state['cleanup'])
        return core, parent, publisher, caller, calls, state, identities, wires, key

    def test_original_identity_and_full_body_keep_pair_with_bounded_wire_overlap(self):
        core, parent, _, caller, _, state, identities, wires, _ = self.bridge()
        original_call = core._call
        capacities = {}
        limit = 6 * 1048576
        peak = 0

        def call(family, name, *args):
            nonlocal peak
            if family == 'publication_commit_export' and name in ('reserve', 'reserve_bounded'):
                if name == 'reserve':
                    selected_parent, ticket, physical_bytes = args
                    wire_limit = 1048576
                else:
                    selected_parent, ticket, wire_limit, physical_bytes = args
                self.assertEqual(selected_parent, parent.handle)
                charge = physical_bytes + 2 * wire_limit
                if sum(capacities.values()) + charge > limit:
                    return -4
                # This is an explicit physical buffer port, not an installed
                # Core/Store or a claim about E's unrecorded numeric usage.
                result = original_call(family, 'reserve', selected_parent, ticket,
                                       max(physical_bytes, 2 * 1048576))
                capacities[result] = charge
                peak = max(peak, sum(capacities.values()))
                return result
            result = original_call(family, name, *args)
            if family == 'publication_commit_export' and name == 'close' and result == 0:
                capacities.pop(args[0], None)
            return result

        core._call = original_byte_fixture_port(call)
        delivered = []
        def consume(write):
            self.assertEqual(len(caller.pending_outputs), 2)
            self.assertEqual([value.limit for value in caller.pending_outputs], [71, 1048576])
            self.assertEqual(write.key, 'namespace:20:publication_contract:' + identities[0].decode())
            self.assertEqual(write.payload, wires[0])
            self.assertEqual(state['close_calls'], [])
            delivered.append(True)
        caller.project_contract(0, consume)
        self.assertEqual(delivered, [True])
        self.assertLessEqual(peak, limit)
        self.assertEqual(capacities, {})
        self.assertEqual(caller.pending_outputs, ())
        self.assertIs(core._loans[parent.ticket], parent)

    def test_contract_consumes_original_identity_and_bytes_while_both_loans_are_live(self):
        core, parent, _, caller, calls, _, identities, wires, _ = self.bridge()
        writes = []

        def consume(write):
            self.assertEqual(len(caller.pending_outputs), 2)
            self.assertTrue(all(core._loans[v.ticket] is v for v in caller.pending_outputs))
            self.assertEqual(write.key, 'namespace:20:publication_contract:' + identities[0].decode())
            self.assertEqual(write.payload, wires[0])
            self.assertIsNone(write.expected_generation)
            writes.append(True)

        caller.project_contract(0, consume)
        self.assertEqual(len(writes), 1)
        self.assertEqual(caller.pending_outputs, ())
        self.assertEqual(set(core._loans), {6, 7})
        self.assertIs(core._loans[7], parent)
        self.assertIn(('publication_commit_export', 'produce_material', (208, 31, 0, 3)), calls)
        self.assertIn(('publication_commit_export', 'produce_material', (209, 31, 0, 0)), calls)
        self.assertFalse(any(f in ('run', 'source', 'task', 'model', 'effect', 'publication')
                             for f, _, _ in calls))

    def test_public_index_consumes_owner_key_and_original_cid_not_index_body(self):
        _, _, _, caller, calls, _, identities, wires, key = self.bridge()
        writes = []

        def consume(write):
            self.assertEqual(write.key, 'namespace:12:public_index:' + key.decode())
            self.assertEqual(write.payload, identities[7])
            self.assertNotEqual(write.payload, wires[7])
            self.assertEqual(write.expected_generation, 4)
            writes.append(True)

        caller.project_index_reference(consume, expected_generation=4)
        self.assertEqual(writes, [True])
        self.assertIn(('publication_commit_export', 'produce_index_key', (208, 31)), calls)
        self.assertIn(('publication_commit_export', 'produce_material', (209, 31, 7, 3)), calls)

    def test_copy_foreign_parent_wrong_family_and_configuration_refuse_before_io(self):
        core, parent, _, caller, calls, _, _, _, _ = self.bridge()
        foreign, _, _, _, _, _, _, _, _ = self.bridge()
        before = len(calls)
        for action in (
            lambda: OriginalCommitProjection(core, copy.copy(parent), 31, cleanup=lambda: True),
            lambda: OriginalCommitProjection(foreign, parent, 31, cleanup=lambda: True),
            lambda: OriginalCommitProjection(core, core._loans[6], 31, cleanup=lambda: True),
            lambda: OriginalCommitProjection(core, parent, True, cleanup=lambda: True),
            lambda: OriginalCommitProjection(core, parent, 0, cleanup=lambda: True),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)
        self.assertEqual(caller.pending_outputs, ())

    def test_invalid_ordinal_generation_and_consumer_controls_refuse_before_io(self):
        _, _, _, caller, calls, _, _, _, _ = self.bridge()
        before = len(calls)
        for action in (
            lambda: caller.project_contract(True, lambda _: None),
            lambda: caller.project_contract(-1, lambda _: None),
            lambda: caller.project_contract(2**31, lambda _: None),
            lambda: caller.project_contract(0, None),
            lambda: caller.project_contract(0, lambda _: None, expected_generation=True),
            lambda: caller.project_index_reference(lambda _: None, expected_generation=-1),
            lambda: caller.project_index_reference(lambda _: None, expected_generation=2**63 - 1),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(len(calls), before)

    def test_original_count_and_refusal_never_become_empty_success(self):
        _, _, _, caller, _, state, _, _, _ = self.bridge()
        self.assertEqual(caller.count(), 14)
        for count in (-32, -4, 7, True):
            state['count'] = count
            with self.assertRaises(LocalCoreError):
                caller.count()
        self.assertEqual(caller.pending_outputs, ())

    def test_current_production_refusal_keeps_original_loan_without_replacement(self):
        core, parent, _, caller, calls, state, _, _, _ = self.bridge()
        state['produce'] = -32
        with self.assertRaises(LocalCoreError) as issue:
            caller.project_contract(0, lambda _: self.fail('Refused production'))
        self.assertEqual(issue.exception.code, -32)
        pending = caller.pending_outputs
        self.assertEqual(len(pending), 1)
        before = len(calls)
        with self.assertRaises(RuntimeError):
            caller.project_contract(0, lambda _: None)
        self.assertEqual(len(calls), before)
        self.assertIs(core._loans[pending[0].ticket], pending[0])
        self.assertTrue(caller.close())
        self.assertIs(core._loans[7], parent)

    def test_second_reservation_refusal_preserves_first_exact_cleanup_handle(self):
        core, _, _, caller, calls, state, _, _, _ = self.bridge()
        state['reserve_fail_at'] = 9
        with self.assertRaises(LocalCoreError) as issue:
            caller.project_contract(0, lambda _: self.fail('Reservation refused'))
        self.assertEqual(issue.exception.code, -4)
        pending = caller.pending_outputs
        self.assertEqual(len(pending), 1)
        self.assertEqual((pending[0].ticket, pending[0].handle), (8, 208))
        self.assertNotIn(9, core._inputs)
        self.assertTrue(caller.close())
        self.assertEqual(len([c for c in calls if c[1] in ('reserve', 'reserve_bounded')]), 2)

    def test_consumer_error_and_cancel_propagate_with_original_pair_retained(self):
        for error in (OSError('Physical consumer failed'), asyncio.CancelledError()):
            with self.subTest(error=type(error)):
                core, parent, _, caller, calls, state, _, _, _ = self.bridge()

                def consume(_):
                    raise error

                with self.assertRaises(type(error)):
                    caller.project_contract(0, consume)
                pending = caller.pending_outputs
                self.assertEqual(len(pending), 2)
                self.assertEqual(state['close_calls'], [])
                self.assertTrue(all(core._loans[v.ticket] is v for v in pending))
                with self.assertRaises(RuntimeError):
                    caller.count()
                # The Host has finished/discarded the failed consumer before cleanup.
                error.__traceback__ = None
                self.assertTrue(caller.close())
                self.assertIs(core._loans[7], parent)
                self.assertFalse(any(f in ('run', 'source', 'task', 'model', 'effect')
                                     for f, _, _ in calls))

    def test_cleanup_failure_retries_original_pair_without_source_or_projection_replay(self):
        core, parent, _, caller, calls, state, _, _, _ = self.bridge()
        state['cleanup'] = False
        with self.assertRaises(LocalCoreError) as issue:
            caller.project_contract(0, lambda _: None)
        self.assertEqual(issue.exception.code, -9)
        pending = caller.pending_outputs
        self.assertEqual(len(pending), 2)
        original_handles = {v.handle for v in pending}
        before = len(calls)
        self.assertFalse(caller.close())
        self.assertEqual(set(v.handle for v in caller.pending_outputs), original_handles)
        state['cleanup'] = True
        self.assertTrue(caller.close())
        self.assertTrue(all(c[1] == 'close' and c[2][0] in original_handles for c in calls[before:]))
        self.assertTrue(caller.close())
        self.assertIs(core._loans[7], parent)
        with self.assertRaises(RuntimeError):
            caller.project_contract(0, lambda _: None)

    def test_malformed_identity_and_out_of_range_original_refuse_without_consumption(self):
        for malformed in (b'', b'x' * 71, b'sha256:' + b'g' * 64,
                          b'sha256:' + b'\xff' * 64):
            with self.subTest(malformed=malformed):
                _, _, _, caller, _, state, _, _, _ = self.bridge()
                state['identity_override'] = malformed
                with self.assertRaises(LocalCoreError) as issue:
                    caller.project_contract(0, lambda _: self.fail('Malformed address'))
                self.assertEqual(issue.exception.code, -33)
                self.assertEqual(len(caller.pending_outputs), 1)
                self.assertTrue(caller.close())
        _, _, _, caller, _, _, _, _, _ = self.bridge()
        with self.assertRaises(LocalCoreError) as issue:
            caller.project_contract(14, lambda _: self.fail('Missing original ordinal'))
        self.assertEqual(issue.exception.code, -32)
        self.assertTrue(caller.close())

    def test_close_while_consumer_is_live_refuses_and_retains_pair(self):
        _, _, _, caller, _, _, _, _, _ = self.bridge()
        with self.assertRaises(RuntimeError):
            caller.project_contract(0, lambda _: caller.close())
        self.assertEqual(len(caller.pending_outputs), 2)
        self.assertTrue(caller.close())

    def test_truthy_or_false_consumer_result_never_retires_a_successful_pair(self):
        for result in (True, False, 0, b'accepted'):
            with self.subTest(result=result):
                _, _, _, caller, _, state, _, _, _ = self.bridge()
                with self.assertRaises(ValueError):
                    caller.project_contract(0, lambda _: result)
                self.assertEqual(len(caller.pending_outputs), 2)
                self.assertEqual(state['close_calls'], [])
                self.assertTrue(caller.close())

    def test_serialized_scope_holds_core_before_store_lock_for_other_threads(self):
        core, _, _, caller, _, _, _, _, _ = self.bridge()

        def acquire():
            acquired = core._lock.acquire(blocking=False)
            if acquired:
                core._lock.release()
            return acquired

        with ThreadPoolExecutor(max_workers=1) as pool:
            with caller.serialized():
                self.assertFalse(pool.submit(acquire).result(timeout=5))
            self.assertTrue(pool.submit(acquire).result(timeout=5))

    def test_current_publisher_uses_original_port_stage_and_parent_not_bool(self):
        core, parent, publisher, caller, calls, state, _, _, _ = self.bridge()
        caller.authorize_commit(publisher)
        self.assertEqual(calls[-1], ('publisher', 'authorize', (17, 31, 1, 23)))
        for code in (-35, -36, -32):
            state['publisher'] = code
            with self.assertRaises(LocalCoreError) as issue:
                caller.authorize_commit(publisher)
            self.assertEqual(issue.exception.code, code)
        before = len(calls)
        for value in (True, parent, copy.copy(publisher)):
            with self.assertRaises(ValueError):
                caller.authorize_commit(value)
        self.assertEqual(len(calls), before)
        self.assertIs(core._loans[6], publisher)

    def test_partial_physical_batch_matches_original_contract_and_index_reference_layout(self):
        core, parent, publisher, caller, calls, _, identities, wires, key = self.bridge()
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=8,
                               max_record_bytes=256, max_payload_bytes=1024) as store:
                self.assertEqual(store.compare_exchange('payload', None, b'original'), 0)
                self.assertTrue(store.reserve_capacity('payload', 'payload', 64, 1, 64, 1))
                originals = ((ByteFence('payload', 0, b'original'),
                              CapacityReservation('payload', 'payload', 64, 1)),)

                def project(ordinal, consume):
                    if ordinal < 2:
                        caller.project_contract(ordinal, consume)
                    else:
                        caller.project_index_reference(consume)

                with caller.serialized():
                    self.assertEqual(store.compare_exchange_projected_attached(
                        3, project, originals, before_commit=lambda: caller.authorize_commit(publisher)),
                        (0, 0, 0))
                for ordinal in (0, 1):
                    address = 'namespace:20:publication_contract:' + identities[ordinal].decode()
                    self.assertEqual(store.read(address), StoredBytes(0, wires[ordinal]))
                self.assertEqual(store.read('namespace:12:public_index:' + key.decode()),
                                 StoredBytes(0, identities[7]))
                self.assertEqual(store.read('payload'), StoredBytes(0, b'original'))
                self.assertEqual(caller.pending_outputs, ())
                self.assertEqual(set(core._loans), {6, 7})
                self.assertIs(core._loans[7], parent)
                self.assertFalse(any(f in ('run', 'source', 'task', 'model', 'effect')
                                     for f, _, _ in calls))

    def test_current_publisher_refusal_rolls_back_physical_subset_without_second_projection(self):
        _, _, publisher, caller, calls, state, identities, _, _ = self.bridge()
        state['publisher'] = -35
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'core.sqlite', max_records=8,
                               max_record_bytes=256, max_payload_bytes=1024) as store:
                store.compare_exchange('payload', None, b'original')
                store.reserve_capacity('payload', 'payload', 64, 1, 64, 1)
                originals = ((ByteFence('payload', 0, b'original'),
                              CapacityReservation('payload', 'payload', 64, 1)),)
                with caller.serialized(), self.assertRaises(LocalCoreError) as issue:
                    store.compare_exchange_projected_attached(
                        1, lambda i, consume: caller.project_contract(i, consume), originals,
                        before_commit=lambda: caller.authorize_commit(publisher))
                self.assertEqual(issue.exception.code, -35)
                self.assertIsNone(store.read('namespace:20:publication_contract:' + identities[0].decode()))
                self.assertEqual(store.read('payload'), StoredBytes(0, b'original'))
                self.assertEqual(len([c for c in calls if c[1] in ('reserve', 'reserve_bounded')]), 2)
                self.assertEqual(caller.pending_outputs, ())

    def test_schema_uses_original_receipt_pair_and_separate_physical_namespace(self):
        core, parent, _, caller, calls, state, _, _, _ = self.bridge()
        observed = []
        def consume(write):
            self.assertEqual(len(caller.pending_outputs), 2)
            self.assertTrue(all(core._loans[v.ticket] is v for v in caller.pending_outputs))
            self.assertEqual(write.key, 'namespace:13:result_schema:' + state['schema_identity'].decode())
            self.assertEqual(write.payload, b'{"id":{"nullable":false,"type":"number"}}')
            self.assertEqual(write.expected_generation, 3)
            observed.append(True)
        caller.project_schema(0, consume, expected_generation=3)
        self.assertEqual(observed, [True])
        produced = [args[1:] for _, name, args in calls if name == 'produce_schema']
        self.assertEqual(produced, [(31, 0, 0), (31, 0, 1)])
        self.assertFalse(any(name in ('produce_material', 'produce_index_key', 'authorize')
                             for _, name, _ in calls))
        self.assertIs(core._loans[7], parent)
        self.assertEqual(caller.pending_outputs, ())

    def test_schema_current_refusal_and_unknown_result_preserve_original_loan(self):
        for code in (-5, -32, -33):
            with self.subTest(code=code):
                core, parent, _, caller, _, state, _, _, _ = self.bridge()
                state['produce'] = code
                with self.assertRaises(LocalCoreError) as issue:
                    caller.project_schema(0, lambda _: self.fail('Refused schema consumed'))
                self.assertEqual(issue.exception.code, code)
                self.assertEqual(len(caller.pending_outputs), 1)
                self.assertIs(core._loans[7], parent)
                self.assertTrue(caller.close())
        _, _, _, caller, _, _, _, _, _ = self.bridge()
        with self.assertRaises(LocalCoreError) as issue:
            caller.project_schema(1, lambda _: self.fail('Foreign Result consumed'))
        self.assertEqual(issue.exception.code, -3)
        self.assertEqual(len(caller.pending_outputs), 1)
        self.assertTrue(caller.close())

    def test_schema_invalid_identity_never_consumes_body(self):
        for raw in (b'', b'sha256:' + b'x' * 64, b'sha256:' + b'0' * 63):
            with self.subTest(raw=raw):
                _, _, _, caller, calls, state, _, _, _ = self.bridge()
                state['schema_identity'] = raw
                with self.assertRaises(LocalCoreError):
                    caller.project_schema(0, lambda _: self.fail('Invalid identity consumed'))
                self.assertEqual(sum(name == 'produce_schema' for _, name, _ in calls), 1)
                self.assertEqual(len(caller.pending_outputs), 1)
                self.assertTrue(caller.close())

    def test_schema_consumer_error_retains_pair_and_cleanup_retry_is_same_handles(self):
        core, parent, _, caller, calls, state, _, _, _ = self.bridge()
        def fail(_):
            raise OSError('Original physical schema write failed')
        with self.assertRaises(OSError):
            caller.project_schema(0, fail)
        pending = caller.pending_outputs
        self.assertEqual(len(pending), 2)
        state['cleanup'] = False
        self.assertFalse(caller.close())
        self.assertEqual(caller.pending_outputs, pending)
        state['cleanup'] = True
        self.assertTrue(caller.close())
        self.assertIs(core._loans[7], parent)
        self.assertEqual(sum(name == 'produce_schema' for _, name, _ in calls), 2)

    def test_schema_cleanup_failure_refuses_following_projection_without_reissue(self):
        _, _, _, caller, calls, state, _, _, _ = self.bridge()
        state['cleanup'] = False
        with self.assertRaises(LocalCoreError) as issue:
            caller.project_schema(0, lambda _: None)
        self.assertEqual(issue.exception.code, -9)
        self.assertEqual(len(caller.pending_outputs), 2)
        before = len(calls)
        with self.assertRaises(RuntimeError):
            caller.project_contract(0, lambda _: None)
        with self.assertRaises(RuntimeError):
            caller.project_schema(0, lambda _: None)
        self.assertEqual(len(calls), before)
        state['cleanup'] = True
        self.assertTrue(caller.close())

    def test_schema_real_sqlite_attachment_preserves_separate_identity_and_wire(self):
        _, _, _, caller, _, state, _, _, _ = self.bridge()
        with TemporaryDirectory() as directory:
            with LocalByteStore(Path(directory) / 'store.sqlite',
                    max_records=8, max_record_bytes=4096, max_payload_bytes=8192) as store:
                self.assertEqual(store.compare_exchange('payload', None, b'original'), 0)
                self.assertTrue(store.reserve_capacity('payload', 'payload', 64, 1, 64, 1))
                originals = ((ByteFence('payload', 0, b'original'),
                              CapacityReservation('payload', 'payload', 64, 1)),)
                key = 'namespace:13:result_schema:' + state['schema_identity'].decode()
                with caller.serialized():
                    result = store.compare_exchange_projected_attached(
                        1, lambda _, consume: caller.project_schema(0, consume), originals,
                        before_commit=lambda: None)
                self.assertEqual(result, (0,))
                self.assertEqual(store.read(key), StoredBytes(0, state['schema_wire']))
                self.assertEqual(store.read('payload'), StoredBytes(0, b'original'))
                self.assertEqual(store.read_capacity('payload', 'payload'), originals[0][1])
                self.assertEqual(caller.pending_outputs, ())
