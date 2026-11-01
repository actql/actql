"""Real File/SQLite assembly with scalar Core, not installed/Wasm/E2E evidence."""
import copy
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from actql_sdk._local_core import LocalCoreError
from actql_sdk._local_files import LocalFileError
from actql_sdk._local_product import InstalledLocalHost, LocalProductCleanupPending
import test_local_installation as installation_fixture
from local_abi_declaration_fixture import original_byte_fixture_port


class LocalProductAssemblyTests(unittest.TestCase):
    def core(self):
        # Reuse the physical installation fixture without importing its test
        # class into this module's discovery namespace. These opaque responses
        # drive transport only; they do not prove actual Account admission.
        core, calls = installation_fixture.OriginalLocalInstallationTests().core()
        core._retired = False
        core._store = core._linker = core._module = core._engine = None
        core._native_observers = {}
        core._native_loans = {}
        core._compute_loans = {}
        core._task_loans = {}
        core._result_loans = {}
        original = core._call
        outputs = {}
        projections = {}
        codes = {}
        scope = ['sha256:' + 'a' * 64]

        def call(family, name, *args):
            selected = ((family == 'run' and name in ('install_current_configuration', 'close_configuration'))
                        or family == 'submission' or (family == 'current' and name == 'produce')
                        or (family == 'buffer' and name == 'close_pool'))
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            if name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if not selected:
                return original(family, name, *args)
            calls.append((family, name, args))
            if (family, name) in codes:
                return codes[family, name]
            if family == 'run' and name == 'install_current_configuration':
                callbacks = core._journal_callbacks(args[0] - 100)
                self.assertIsNotNone(callbacks.reader)
                self.assertEqual(callbacks.check_current(), 0)
                setup = json.loads(core._inputs[args[1] - 100].payload)
                self.assertEqual(set(setup), {'namespace', 'source_free_result_policy'})
                self.assertEqual(setup['namespace'], 'local')
                policy = setup['source_free_result_policy']
                self.assertEqual(policy['cid'], 'sha256:' + hashlib.sha256(policy['body'].encode()).hexdigest())
                return 1000000
            if family == 'current' and name == 'produce':
                self.assertEqual(core._journal_callbacks(args[0] - 100).check_current(), 0)
                outputs[args[0]] = installation_fixture.encode({
                    'account': '{"opaque":"not an Allow"}',
                    'account_configuration_cid': 'sha256:' + 'b' * 64,
                    'authority_scope_cid': scope[0]})
                return 0
            if family == 'submission' and name == 'reserve':
                self.assertEqual(args[0], 1000000)
                projections[100 + args[3]] = (args[1], args[2])
                return 100 + args[3]
            if family == 'submission' and name == 'produce':
                source, kind = projections[args[0]]
                self.assertEqual(kind, 1)
                fields = json.loads(core._inputs[source - 100].payload)
                body = installation_fixture.encode({'version': 'actql-submission-epoch/0.1', **fields})
                outputs[args[0]] = installation_fixture.encode({
                    'epoch_wire': body.decode(), 'epoch_cid': 'sha256:' + hashlib.sha256(body).hexdigest()})
                return 0
            if family == 'submission' and name == 'close':
                return 0 if core._cleanup(args[0] - 100) == 0 else -9
            if (family, name) in (('run', 'close_configuration'), ('buffer', 'close_pool')):
                return 0
            raise AssertionError('Unexpected execution or operation')

        core._call = original_byte_fixture_port(call)
        return core, calls, codes, scope

    def create(self, core, path):
        host = InstalledLocalHost(core, path, now=lambda: 0, observed_at='2026-10-12T00:00:00.000Z')
        self.addCleanup(host.close)
        return host

    def test_profile_uses_original_current_scope_and_same_store_epoch_without_work(self):
        with TemporaryDirectory(prefix='actql-product-') as directory:
            core, calls, _, scope = self.core()
            host = self.create(core, Path(directory))
            profile = host.profile()
            self.assertEqual(profile['scopeRef'], scope[0])
            self.assertEqual(profile['submissionEpoch']['authorityScopeCid'], scope[0])
            self.assertEqual(profile['capabilities'], [])
            self.assertEqual(profile['mode'], 'local')
            self.assertEqual(profile['durability'], 'durable')
            self.assertEqual(profile['limits']['maxRows'], 1000)
            original_epoch = host._installation._store.read('submission-epoch-authority')
            second = host.profile()
            self.assertEqual(host._installation._store.read('submission-epoch-authority'), original_epoch)
            self.assertNotEqual(second['submissionEpoch']['epochNonce'], profile['submissionEpoch']['epochNonce'])
            self.assertEqual(sum(family == 'run' and name == 'install_current_configuration'
                                 for family, name, _ in calls), 1)
            self.assertFalse(any(family in ('program', 'compute', 'source', 'publication') for family, _, _ in calls))
            self.assertTrue(host.close())

    def test_restore_preserves_policy_store_epoch_and_does_not_bootstrap_again(self):
        with TemporaryDirectory(prefix='actql-product-') as directory:
            path = Path(directory)
            core, _, _, _ = self.core()
            first = self.create(core, path)
            original_files = {str(p.relative_to(path)): p.read_bytes() for p in path.rglob('*.json')}
            original_key = first._installation._store.read('submission-epoch-authority')
            original_generation = first._installation._store.observe_generation()
            self.assertTrue(first.close())
            second_core, calls, _, _ = self.core()
            second = self.create(second_core, path)
            second.profile()
            self.assertEqual(second._installation._store.observe_generation(), original_generation)
            self.assertEqual(second._installation._store.read('submission-epoch-authority'), original_key)
            self.assertEqual({str(p.relative_to(path)): p.read_bytes() for p in path.rglob('*.json')}, original_files)
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in calls))
            self.assertTrue(second.close())

    def test_current_source_change_refuses_before_scope_or_epoch_projection(self):
        with TemporaryDirectory(prefix='actql-product-') as directory:
            path = Path(directory)
            core, calls, _, _ = self.core()
            host = self.create(core, path)
            before = len(calls)
            (path / 'source/account.json').write_bytes(b'{"replacement":true}')
            with self.assertRaisesRegex(LocalFileError, 'original generation changed'):
                host.profile()
            self.assertEqual(len(calls), before)
            self.assertTrue(host.close())

    def test_copied_and_closed_host_cannot_issue_scope_or_epoch(self):
        with TemporaryDirectory(prefix='actql-product-') as directory:
            core, calls, _, _ = self.core()
            host = self.create(core, Path(directory))
            before = len(calls)
            for operation in (lambda: copy.copy(host).profile(), lambda: copy.copy(host).close()):
                with self.assertRaises(ValueError):
                    operation()
            self.assertEqual(len(calls), before)
            self.assertTrue(host.close())
            before = len(calls)
            with self.assertRaises(ValueError):
                host.profile()
            self.assertEqual(len(calls), before)
            self.assertTrue(host.close())

    def test_typed_configuration_refusal_keeps_original_cleanup_without_raw_fallback(self):
        with TemporaryDirectory(prefix='actql-product-') as directory:
            core, calls, codes, _ = self.core()
            codes['run', 'install_current_configuration'] = -32
            with self.assertRaises(LocalProductCleanupPending) as raised:
                self.create(core, Path(directory))
            host = raised.exception.cleanup_host
            self.assertIs(host._core, core)
            self.assertIsInstance(raised.exception.__cause__, LocalCoreError)
            self.assertEqual(raised.exception.__cause__.code, -32)
            self.assertFalse(any(family == 'run' and name == 'install_configuration' for family, name, _ in calls))
            self.assertTrue(host.close())

    def test_configuration_cleanup_pending_keeps_same_handle_and_capacity_until_retry(self):
        with TemporaryDirectory(prefix='actql-product-') as directory:
            core, calls, codes, _ = self.core()
            host = self.create(core, Path(directory))
            original = host._configuration
            codes['run', 'close_configuration'] = -9
            self.assertFalse(host.close())
            self.assertIs(host._configuration, original)
            self.assertIsNotNone(host._installation)
            self.assertFalse(any(family == 'buffer' and name == 'close_pool' for family, name, _ in calls))
            codes['run', 'close_configuration'] = 0
            self.assertTrue(host.close())
            self.assertEqual([args for family, name, args in calls
                              if family == 'run' and name == 'close_configuration'], [(original.handle,)] * 2)
            self.assertEqual(calls[-1], ('buffer', 'close_pool', ()))

    def test_epoch_projection_failure_retains_original_loans_and_does_not_reissue(self):
        with TemporaryDirectory(prefix='actql-product-') as directory:
            core, calls, codes, _ = self.core()
            host = self.create(core, Path(directory))
            codes['submission', 'produce'] = -41
            with self.assertRaises(LocalCoreError) as raised:
                host.profile()
            self.assertEqual(raised.exception.code, -41)
            self.assertEqual(len(host._projections), 1)
            self.assertIs(core._loans[host._projections[0].ticket], host._projections[0])
            self.assertEqual(sum(family == 'submission' and name == 'produce' for family, name, _ in calls), 1)
            self.assertTrue(host.close())
            self.assertFalse(any(family == 'run' and name in ('cancel', 'reserve', 'prepare') for family, name, _ in calls))

    def test_physical_core_cleanup_pending_is_retried_without_recreating_installation(self):
        with TemporaryDirectory(prefix='actql-product-') as directory:
            core, calls, codes, _ = self.core()
            host = self.create(core, Path(directory))
            codes['buffer', 'close_pool'] = -9
            self.assertFalse(host.close())
            self.assertIsNone(host._installation)
            self.assertFalse(core._closed)
            codes['buffer', 'close_pool'] = 0
            self.assertTrue(host.close())
            self.assertTrue(core._closed)
            self.assertEqual(sum(family == 'bootstrap' and name == 'produce' for family, name, _ in calls), 1)
            self.assertEqual(sum(family == 'buffer' and name == 'close_pool' for family, name, _ in calls), 2)


if __name__ == '__main__':
    unittest.main()
