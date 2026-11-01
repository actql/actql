"""Actual SQLite original Intent caller with scalar Core; not physical Wasm."""
import json
import copy
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_storage import LocalStorageCommitUnknown, LocalStorageError
import test_local_sdk_results as result_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


RAW = b'{"original":"e\xcc\x81/~\\r\\n","null":null,"absent":{}}'


class ProductPayloadIntentTests(unittest.TestCase):
    def host(self, path, *, request_maximum='1024', foreign_request=False):
        fixture = result_fixture.SDKResultAssemblyTests()
        self.addCleanup(fixture.doCleanups)
        host, core, compute, preflight, publisher, calls, _ = fixture.host(path)
        results = host._execute_original_tasks(compute, preflight, publisher)
        publication = host._capture_original_results(compute, preflight, results)
        previous = core._call
        requests, request_wires, records, metadata, begun, confirmed = {}, {}, {}, {}, set(), set()
        faults = {}
        def input_bytes(handle):
            for value in core._loans.values():
                if value.handle == handle and value.ticket in core._inputs:
                    return core._inputs[value.ticket].payload
            self.fail('Missing original physical input')
        def call(family, name, *args):
            if family not in ('payload_request', 'payload_record'):
                if family == 'buffer' and name == 'byte' and args[0] in request_wires:
                    return request_wires[args[0]][args[1]]
                if family == 'buffer' and name == 'byte' and args[0] in records:
                    return RAW[args[1]]
                return previous(family, name, *args)
            calls.append((family, name, args))
            failure = faults.get((family, name))
            if failure is not None: return failure
            if name == 'reserve':
                if family == 'payload_request':
                    self.assertEqual(args[:2], (publication.handle, 0))
                    handle = 100 + args[3]
                    requests[handle] = args[3]
                    metadata[handle] = json.loads(input_bytes(args[2]))
                    return handle
                handle = 100 + args[1]
                records[handle] = (args[1], args[0])
                return handle
            if family == 'payload_request':
                if name == 'length': return len(request_wires[args[0]])
                if name == 'close':
                    self.assertFalse(any(request == args[0] for _, request in records.values()))
                    return core._cleanup(requests.pop(args[0]))
                self.assertEqual(name, 'produce')
                original = metadata[args[0]]
                request_wires[args[0]] = json.dumps({
                    'version': 'actql-publication-payload-request/0.1',
                    'store_authority_cid': ('sha256:' + 'f' * 64 if foreign_request
                                            else original['store_authority_cid']),
                    'material_generation_cid': original['material_generation_cid'],
                    'max_bytes': request_maximum, 'row_count': '1',
                    **{key: 'sha256:' + 'c' * 64 for key in (
                        'durable_codec_cid', 'logical_relation_cid', 'ordering_evidence_cid',
                        'publication_attempt_cid', 'result_definition_cid', 'result_schema_cid')},
                }).encode()
                return 0
            if name == 'length': return len(RAW)
            if name == 'begin':
                if args[0] in begun: return -33
                begun.add(args[0])
            if name == 'confirm':
                self.assertIn(args[0], begun)
                actual = json.loads(input_bytes(args[1]))
                original = metadata[records[args[0]][1]]
                self.assertEqual(actual['store_authority_cid'], original['store_authority_cid'])
                self.assertEqual(actual['material_generation_cid'], original['material_generation_cid'])
                if actual['physical_revision'] != 0 or actual['record_json'].encode() != RAW: return -32
                confirmed.add(args[0])
            if name == 'close':
                if args[0] in begun and args[0] not in confirmed: return -9
                ticket, _ = records.pop(args[0])
                return core._cleanup(ticket)
            return 0
        core._call = original_byte_fixture_port(call)
        return host, core, publication, calls, faults

    def test_exact_original_request_amount_is_distinct_from_physical_store_limit(self):
        with TemporaryDirectory(prefix='actql-payload-request-amount-') as directory:
            host, core, publication, calls, _ = self.host(Path(directory))
            held = host._prepare_original_payload(publication, 0)
            self.assertEqual(held.maximum, 1024)
            self.assertLess(held.maximum, host._installation._store._max_record_bytes)
            reserve = next(args for family, name, args in calls
                           if family == 'payload_request' and name == 'reserve')
            source = next(value for value in core._loans.values() if value.handle == reserve[2])
            self.assertEqual(json.loads(core._inputs[source.ticket].payload)['max_payload_bytes'],
                             host._installation._store._max_record_bytes)
            self.assertEqual(sum(family == 'payload_request' and name == 'produce'
                                 for family, name, _ in calls), 1)
            self.assertTrue(host.close())

    def test_foreign_or_over_limit_original_request_retains_loan_before_record_or_capacity(self):
        for options in ({'foreign_request': True}, {'request_maximum': '1048577'}):
            with self.subTest(options=options), TemporaryDirectory(prefix='actql-payload-request-refused-') as directory:
                host, core, publication, calls, _ = self.host(Path(directory), **options)
                with self.assertRaises(ValueError): host._prepare_original_payload(publication, 0)
                held = host._payloads[0]
                self.assertEqual(held.maximum, 0)
                self.assertIsNone(held.record)
                self.assertIs(core._loans[held.request.ticket], held.request)
                self.assertFalse(any(family == 'payload_record' for family, _, _ in calls))
                self.assertFalse(host._payload_capacity_attempts)
                self.assertTrue(host.close())

    def row(self, host, held):
        store = host._installation._store
        return store.read(store.namespaced_key('payload_record', held.generation))

    def test_original_result_intent_is_saved_and_confirmed_without_capacity_or_publication_ack(self):
        with TemporaryDirectory(prefix='actql-payload-intent-') as directory:
            host, core, publication, calls, _ = self.host(Path(directory))
            held = host._prepare_original_payload(publication, 0)
            before = len(calls)
            host._save_original_payload_intent(held)
            self.assertEqual(self.row(host, held).payload, RAW)
            self.assertEqual(self.row(host, held).generation, 0)
            self.assertIs(held.publication, publication)
            self.assertIs(core._loans[held.record.ticket], held.record)
            self.assertEqual(sum(f == 'payload_record' and n == 'begin' for f, n, _ in calls), 1)
            self.assertFalse(any(f in ('source', 'task', 'publication', 'payload_reservation') for f, _, _ in calls[before:]))
            self.assertEqual(host._installation._store.capacity_usage('publication_payload').reserved_bytes, 0)
            with self.assertRaisesRegex(LocalStorageError, 'lookup'):
                host._save_original_payload_intent(held)
            self.assertTrue(host.close())

    def test_commit_reply_loss_resolves_same_saved_key_even_after_pending_close_without_resend(self):
        with TemporaryDirectory(prefix='actql-payload-intent-') as directory:
            host, _, publication, calls, _ = self.host(Path(directory))
            held = host._prepare_original_payload(publication, 0)
            store = host._installation._store
            write = store.compare_exchange_many_inspected
            attempts = []
            def lose(*args, **kwargs):
                attempts.append(write(*args, **kwargs))
                raise LocalStorageCommitUnknown(store)
            with patch.object(store, 'compare_exchange_many_inspected', side_effect=lose):
                with self.assertRaises(LocalStorageCommitUnknown): host._save_original_payload_intent(held)
            self.assertEqual(self.row(host, held).payload, RAW)
            self.assertFalse(host.close())
            host._observe_original_payload_intent(held)
            self.assertEqual(len(attempts), 1)
            self.assertEqual(sum(f == 'payload_record' and n == 'begin' for f, n, _ in calls), 1)
            self.assertTrue(host.close())

    def test_query_failure_is_not_absence_and_retains_same_pending_core_record(self):
        with TemporaryDirectory(prefix='actql-payload-intent-') as directory:
            host, core, publication, _, _ = self.host(Path(directory))
            held = host._prepare_original_payload(publication, 0)
            host._save_original_payload_intent(held)
            store = host._installation._store
            with patch.object(store, 'inspect_bounded_record_inspected', side_effect=OSError('original query unavailable')):
                with self.assertRaisesRegex(OSError, 'query unavailable'):
                    host._observe_original_payload_intent(held)
            self.assertIs(core._loans[held.record.ticket], held.record)
            self.assertEqual(self.row(host, held).payload, RAW)
            self.assertTrue(host.close())

    def test_changed_saved_bytes_are_rejected_by_core_without_repair(self):
        with TemporaryDirectory(prefix='actql-payload-intent-') as directory:
            host, core, publication, _, _ = self.host(Path(directory))
            held = host._prepare_original_payload(publication, 0)
            host._save_original_payload_intent(held)
            store = host._installation._store
            key = store.namespaced_key('payload_record', held.generation)
            store.compare_exchange(key, 0, b'{"foreign":null}')
            with self.assertRaises(LocalCoreError): host._observe_original_payload_intent(held)
            self.assertEqual(store.read(key).payload, b'{"foreign":null}')
            self.assertIs(core._loans[held.record.ticket], held.record)
            self.assertTrue(host.close())

    def test_copied_custody_and_publication_or_boolean_index_refuse_before_new_io(self):
        with TemporaryDirectory(prefix='actql-payload-intent-') as directory:
            host, _, publication, calls, _ = self.host(Path(directory))
            held = host._prepare_original_payload(publication, 0)
            before = len(calls)
            for action in (
                lambda: host._save_original_payload_intent(copy.copy(held)),
                lambda: host._observe_original_payload_intent(copy.copy(held)),
                lambda: host._prepare_original_payload(copy.copy(publication), 0),
                lambda: host._prepare_original_payload(publication, True),
            ):
                with self.assertRaises(ValueError): action()
            self.assertEqual(before, len(calls))
            self.assertEqual(len(host._payloads), 1)
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
