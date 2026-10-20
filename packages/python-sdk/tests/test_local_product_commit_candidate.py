"""Original Sealed inventory -> Core candidate; no Store/Run acknowledgement."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from actql_sdk._local_core import LocalCoreError
import test_local_product_payload_reader as reader_fixture


class ProductCommitCandidateTests(unittest.TestCase):
    def host(self, path):
        fixture = reader_fixture.ProductPayloadReaderTests()
        self.addCleanup(fixture.doCleanups)
        host, core, held, calls, _ = fixture.host(path)
        host._open_original_payload_reader(held)
        self.assertTrue(host._advance_original_payload_reader(held))
        preflight = host._publication_preflights[0]
        previous = core._call
        requests, advances, faults = [], [], {}
        def call(family, name, *args):
            if family == 'publication' and name in ('prepare_commit', 'advance_commit', 'commit_progress', 'finish_commit'):
                calls.append((family, name, args))
                if name in faults: return faults[name]
                if name == 'prepare_commit':
                    handle = args[1]
                    source = next(core._inputs[v.ticket] for v in core._loans.values() if v.handle == handle)
                    packet = json.loads(source.payload)
                    self.assertEqual(set(packet), {'bindings', 'committed_at'})
                    self.assertEqual(packet['bindings'], [reader_fixture.BINDING.decode()])
                    self.assertTrue(packet['committed_at'].endswith('Z'))
                    held.reader.root.observe_completed_reader(held.reader)
                    requests.append(handle)
                if name == 'advance_commit': advances.append(args[-1])
                if name == 'commit_progress': return int(len(advances) >= 2) if args[-1] == 0 else 16
                return 0
            if family == 'publication_commit_export' and name == 'count': return 8
            return previous(family, name, *args)
        core._call = call
        return host, core, held, preflight, calls, requests, advances, faults

    def test_original_request_time_and_budget_are_retained_and_done_is_readonly_without_store_ack(self):
        with TemporaryDirectory(prefix='actql-commit-candidate-') as directory:
            host, core, held, preflight, calls, requests, advances, _ = self.host(Path(directory))
            publication = held.publication
            before = len(calls)
            host._prepare_original_commit_candidate(publication, preflight)
            request = host._commit_requests[publication.ticket]
            original_bytes = core._inputs[request.ticket].payload
            with patch.object(host, '_now', side_effect=AssertionError('Original request time reissued')):
                host._prepare_original_commit_candidate(publication, preflight)
            self.assertEqual(requests, [request.handle, request.handle])
            self.assertEqual(core._inputs[request.ticket].payload, original_bytes)
            self.assertIsNone(host._advance_original_commit_candidate(publication))
            projection = host._advance_original_commit_candidate(publication)
            self.assertIs(projection._publication, publication)
            self.assertIs(host._advance_original_commit_candidate(publication), projection)
            self.assertEqual(advances, [256, 256])
            self.assertFalse(host._publication_write_attempts)
            self.assertIsNone(host._pending_publication_write)
            self.assertFalse(any(f == 'publication' and n in ('prepare_observation', 'finish_observation')
                                 for f, n, _ in calls[before:]))
            self.assertEqual(sum(f == 'publication' and n == 'finish_commit' for f, n, _ in calls), 1)
            self.assertIs(core._loans[request.ticket], request)
            self.assertTrue(host.close())

    def test_failed_core_preparation_keeps_same_input_and_never_reissues_time_or_bindings(self):
        with TemporaryDirectory(prefix='actql-commit-candidate-') as directory:
            host, core, held, preflight, calls, _, _, faults = self.host(Path(directory))
            faults['prepare_commit'] = -32
            with self.assertRaises(LocalCoreError): host._prepare_original_commit_candidate(held.publication, preflight)
            request = host._commit_requests[held.publication.ticket]
            with patch.object(host, '_now', side_effect=AssertionError('Failed attempt replaced')):
                with self.assertRaises(LocalCoreError): host._prepare_original_commit_candidate(held.publication, preflight)
            handles = [args[1] for family, name, args in calls if family == 'publication' and name == 'prepare_commit']
            self.assertEqual(handles, [request.handle, request.handle])
            self.assertIs(core._loans[request.ticket], request)
            self.assertFalse(host._publication_write_attempts)
            self.assertTrue(host.close())

    def test_missing_original_binding_inventory_refuses_before_input_or_core_preparation(self):
        with TemporaryDirectory(prefix='actql-commit-candidate-') as directory:
            host, _, held, preflight, calls, _, _, _ = self.host(Path(directory))
            before = len(calls)
            with patch.object(host, '_payloads', []):
                with self.assertRaisesRegex(ValueError, 'Incomplete original'):
                    host._prepare_original_commit_candidate(held.publication, preflight)
            self.assertFalse(host._commit_requests)
            self.assertFalse(any(f == 'publication' and n == 'prepare_commit' for f, n, _ in calls[before:]))
            self.assertTrue(host.close())


if __name__ == '__main__':
    unittest.main()
