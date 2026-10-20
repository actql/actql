"""Original pre-task assembly on real SQLite/scalar Core, not Wasm authority."""
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import LocalCoreError, _PublisherFact
from actql_sdk._local_product import LocalProductCleanupPending
from actql_sdk._local_storage import LocalStorageError
import test_local_sdk_start as start_fixture


class SDKPreflightAssemblyTests(unittest.TestCase):
    def host(self, path):
        host, core, run, events, _ = start_fixture.SDKStartAssemblyTests().host(path)
        self.addCleanup(host.close)
        compute = host._configure_original_compute(run)
        previous = core._call
        outputs = {}
        failures = {}

        def input_bytes(handle):
            for value in core._loans.values():
                if value.handle == handle and value.ticket in core._inputs:
                    return core._inputs[value.ticket].payload
            self.fail('Missing original input loan')

        def call(family, name, *args):
            if family in ('run_invocation', 'publication_preflight', 'publisher'):
                events.append((family, name))
                if (family, name) in failures:
                    return failures[family, name]
                if name.startswith('reserve'):
                    ticket = args[2]
                    handle = 100 + ticket
                    outputs[handle] = (family, ticket)
                    if family == 'run_invocation':
                        self.assertEqual(args[0], compute.core.handle)
                        self.assertEqual(input_bytes(args[1]), b'{}')
                    elif family == 'publication_preflight':
                        physical = json.loads(input_bytes(args[1]))
                        self.assertEqual(set(physical), {'now', 'attempt_id', 'fence_cid'})
                        self.assertEqual(physical['now'], host._now())
                        self.assertEqual(len(physical['fence_cid']), 71)
                    else:
                        self.assertEqual(input_bytes(args[1]), b'{}')
                    return handle
                if family == 'publisher' and name in ('install', 'authorize'):
                    ticket = outputs[args[0]][1]
                    if core._publisher_current(ticket) != 0:
                        return -36
                    if name == 'authorize':
                        self.assertEqual(args[2:], (0, 0))
                        callback = core._publisher_callbacks(ticket)
                        fact = _PublisherFact('request', 'local', 'sha256:' + 'a' * 64,
                                              'sha256:' + 'b' * 64, 'sha256:' + 'c' * 64, None)
                        if not callback.authorize(fact):
                            return -35
                    return 0
                if name in ('close', 'close_source_free', 'retire_output'):
                    return core._cleanup(outputs[args[0]][1])
                if name in ('prepare_source_free', 'prepare'):
                    return 0
                self.fail('Unexpected preflight scalar operation ' + family + '/' + name)
            return previous(family, name, *args)
        core._call = call
        return host, core, compute, events, failures

    def test_formal_invocation_and_publisher_precede_tasks_without_new_store_writes(self):
        with TemporaryDirectory(prefix='actql-sdk-preflight-') as directory:
            host, core, compute, events, _ = self.host(Path(directory))
            before = start_fixture.SDKStartAssemblyTests().row(host)
            preflight, publisher = host._prepare_original_publication(compute)
            after = start_fixture.SDKStartAssemblyTests().row(host)
            self.assertEqual((after.payload, after.generation), (before.payload, before.generation))
            self.assertLess(events.index(('run_invocation', 'prepare_source_free')),
                            events.index(('publication_preflight', 'prepare')))
            self.assertLess(events.index(('publication_preflight', 'prepare')),
                            events.index(('publisher', 'authorize')))
            self.assertFalse(any(kind == 'task' for kind, _ in events))
            self.assertIs(core._loans[preflight.ticket], preflight)
            self.assertNotIn(preflight.ticket, core._inputs)
            self.assertIs(core._loans[publisher.ticket], publisher)
            self.assertTrue(host.close())

    def test_account_denial_retains_original_preflight_and_never_reissues(self):
        with TemporaryDirectory(prefix='actql-sdk-preflight-') as directory:
            host, core, compute, events, failures = self.host(Path(directory))
            failures['publisher', 'authorize'] = -35
            with self.assertRaises(LocalCoreError) as failure:
                host._prepare_original_publication(compute)
            self.assertEqual(failure.exception.code, -35)
            self.assertIs(core._loans[host._publishers[0].ticket], host._publishers[0])
            before = len(events)
            with self.assertRaises(LocalStorageError): host._prepare_original_publication(compute)
            self.assertEqual(len(events), before)
            self.assertFalse(any(kind == 'task' for kind, _ in events))

    def test_physical_publisher_unknown_does_not_become_denial_or_store_ack(self):
        with TemporaryDirectory(prefix='actql-sdk-preflight-') as directory:
            host, core, compute, events, failures = self.host(Path(directory))
            failures['publisher', 'authorize'] = -36
            with self.assertRaises(LocalCoreError) as failure:
                host._prepare_original_publication(compute)
            self.assertEqual(failure.exception.code, -36)
            self.assertIs(core._loans[host._publication_preflights[0].ticket], host._publication_preflights[0])
            self.assertFalse(any(kind == 'task' or name == 'finish_commit' for kind, name in events))

    def test_retirement_and_cleanup_failures_keep_same_invocation_and_publisher(self):
        with TemporaryDirectory(prefix='actql-sdk-preflight-') as directory:
            host, core, compute, _, failures = self.host(Path(directory))
            failures['publication_preflight', 'retire_output'] = -9
            with self.assertRaises(LocalProductCleanupPending): host._prepare_original_publication(compute)
            preflight = host._publication_preflights[0]
            publisher = host._publishers[0]
            failures['publisher', 'close'] = -9
            self.assertFalse(host.close())
            self.assertIs(core._loans[publisher.ticket], publisher)
            self.assertIs(core._loans[preflight.ticket], preflight)
            self.assertIs(host._source_free_invocations[0][0], compute)
            failures.pop(('publisher', 'close'))
            self.assertTrue(host.close())

    def test_copied_compute_is_rejected_before_new_invocation_or_current_io(self):
        with TemporaryDirectory(prefix='actql-sdk-preflight-') as directory:
            host, _, compute, events, _ = self.host(Path(directory))
            before = len(events)
            with self.assertRaises(ValueError): host._prepare_original_publication(copy.copy(compute))
            self.assertEqual(len(events), before)


if __name__ == '__main__':
    unittest.main()
