"""Independent Common vectors and actual File/SQLite with scalar Core."""
import hashlib
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from actql_sdk import _wire
from actql_sdk._local_installation import OriginalLocalInstallation, LocalInstallationCleanupPending, _object
from actql_sdk._local_core import LocalCoreError
import test_local_installation as old
from local_abi_declaration_fixture import original_byte_fixture_port

ROOT = Path(__file__).resolve().parents[3]
VECTOR = json.loads((ROOT / 'scripts/fixtures/python-local-sdk-read-selection.json').read_text())
SCHEMA = json.loads((ROOT / 'spec/contracts/actql-local-sdk-result-read-selection.schema.json').read_text())
PROFILE = json.loads((ROOT / 'reviews/2026-10-12-d-native-local-expiry-1701/profile-vector.json').read_text())


class FiniteInstallationTests(unittest.TestCase):
    def core(self, *, refuse_workspace=False, oversized=False):
        core, calls = old.OriginalLocalInstallationTests().core()
        previous = core._call
        outputs = {}
        projections = {}
        workspaces = []
        packet = {name: '{"original":"e\u0301\\r\\n","null":null}' for name in (
            'account', 'retention_dependencies', 'retention_policy', 'store',
            'result_policy', 'environment', 'compute')}
        packet |= {'run_policy_profile': PROFILE['canonical'], 'sdk_read': VECTOR['body']}
        if oversized:
            packet['sdk_read'] = 'x' * 8193
        def call(family, name, *args):
            if family == 'original' and name == 'reserve':
                handle = previous(family, name, *args)
                projections[handle] = (args[0], args[1])
                return handle
            if family == 'original' and name == 'produce' and projections[args[0]][1] in (2, 3):
                # This scalar transport marker represents an observation only.
                # Real custody contains references, not recursively embedded
                # settings/body strings. Do not enlarge its original 8 KiB cap.
                calls.append((family, name, args))
                source, kind = projections[args[0]]
                observed = core._inputs[source - 100].payload
                body = old.encode({'kind': kind,
                    'opaque_observation_digest': hashlib.sha256(observed).hexdigest()})
                outputs[args[0]] = old.encode({'body': body.decode(),
                    'cid': 'sha256:' + hashlib.sha256(body).hexdigest()})
                return 0
            if family == 'workspace' and name == 'reserve':
                workspaces.append(args[1])
                if refuse_workspace and args[1] == 8 * 2 * 8192:
                    calls.append((family, name, args))
                    return -4
            if family == 'bootstrap' and name == 'produce_sdk':
                calls.append((family, name, args))
                self.assertIn(8 * 2 * 8192, workspaces)
                outputs[args[0]] = old.encode(packet)
                return 0
            if name == 'length' and args[0] in outputs:
                return len(outputs[args[0]])
            if family == 'buffer' and name == 'byte' and args[0] in outputs:
                return outputs[args[0]][args[1]]
            return previous(family, name, *args)
        core._call = original_byte_fixture_port(call)
        return core, calls, workspaces

    def create(self, core, path):
        value = OriginalLocalInstallation(core, path, observed_at='2026-10-12T00:00:00.000Z',
            now=lambda: 0, project_epoch=lambda *_: self.fail('Unexpected epoch issue'), sdk_finite=True)
        self.addCleanup(value.close)
        return value

    def test_independent_body_cid_closed_schema_and_existing_jsonl_format(self):
        body = _object(VECTOR['body'].encode(), 8192)
        self.assertTrue(_wire.valid(body, SCHEMA))
        self.assertEqual(VECTOR['cid'], 'sha256:13906dcd43b46a467520bf3ea87a8889fd9d04701106b814e85142703e751f27')
        self.assertEqual('sha256:' + hashlib.sha256(VECTOR['body'].encode()).hexdigest(), VECTOR['cid'])
        for field in SCHEMA['required']:
            changed = body.copy(); del changed[field]
            self.assertFalse(_wire.valid(changed, SCHEMA), field)
        for changed in (body | {'purpose': 'cli-read'}, body | {'sink': 'stdout'},
                        body | {'formats': ['sdk-rows']}, body | {'max_uses': 2},
                        body | {'max_bytes': 65537}, body | {'expires_at': '2099-01-01'},
                        body | {'extra': True}, body | {'data_policy_cids': []}):
            self.assertFalse(_wire.valid(changed, SCHEMA))
        with self.assertRaises(ValueError):
            _object(('{"principal":"local-cli",' + VECTOR['body'][1:]).encode(), 8192)

    def test_explicit_initial_install_precharges_and_adopts_eight_selected_originals(self):
        with TemporaryDirectory(prefix='actql-finite-install-') as directory:
            core, calls, workspaces = self.core()
            installation = self.create(core, Path(directory))
            selected = installation.binding._selected
            self.assertEqual(len(selected), 8)
            self.assertEqual([value.name for value in selected], sorted(value.name for value in selected))
            self.assertEqual((Path(directory) / 'source/sdk-read.json').read_text(), VECTOR['body'])
            self.assertEqual((Path(directory) / 'source/run-policy-profile.json').read_text(), PROFILE['canonical'])
            installation.binding.inspect(lambda _: None)
            self.assertIn(131072, workspaces)
            self.assertEqual(sum(family == 'bootstrap' and name == 'produce_sdk' for family, name, _ in calls), 1)
            self.assertFalse(any(family == 'bootstrap' and name == 'produce' for family, name, _ in calls))
            self.assertFalse(any(family in ('run', 'compute', 'publication') for family, _, _ in calls))
            self.assertTrue(installation.close())

    def test_restore_keeps_original_files_store_and_epoch_without_any_bootstrap(self):
        with TemporaryDirectory(prefix='actql-finite-install-') as directory:
            path = Path(directory)
            core, _, _ = self.core()
            first = self.create(core, path)
            original = {str(p.relative_to(path)): p.read_bytes() for p in path.rglob('*.json')}
            epoch = first._store.read('submission-epoch-authority')
            generation = first._store.observe_generation()
            self.assertTrue(first.close())
            other, calls, _ = self.core()
            second = self.create(other, path)
            self.assertEqual(second._store.observe_generation(), generation)
            self.assertEqual(second._store.read('submission-epoch-authority'), epoch)
            self.assertEqual({str(p.relative_to(path)): p.read_bytes() for p in path.rglob('*.json')}, original)
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in calls))

    def test_old_seven_original_installation_is_not_upgraded_or_rebootstrapped(self):
        with TemporaryDirectory(prefix='actql-finite-install-') as directory:
            path = Path(directory)
            core, _ = old.OriginalLocalInstallationTests().core()
            initial = old.OriginalLocalInstallationTests().create(core, path)
            self.assertTrue(initial.close())
            original = {str(p.relative_to(path)): p.read_bytes() for p in path.rglob('*.json')}
            other, calls, _ = self.core()
            with self.assertRaises(LocalInstallationCleanupPending) as raised:
                self.create(other, path)
            self.assertTrue(raised.exception.cleanup_installation.close())
            self.assertEqual({str(p.relative_to(path)): p.read_bytes() for p in path.rglob('*.json')}, original)
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in calls))

    def test_extra_reservation_refuses_before_producer_or_file_allocation(self):
        with TemporaryDirectory(prefix='actql-finite-install-') as directory:
            core, calls, _ = self.core(refuse_workspace=True)
            with self.assertRaises(LocalInstallationCleanupPending) as raised:
                self.create(core, Path(directory))
            self.assertIsInstance(raised.exception.__cause__, LocalCoreError)
            self.assertEqual(raised.exception.__cause__.code, -4)
            self.assertTrue(raised.exception.cleanup_installation.close())
            self.assertEqual(list(Path(directory).iterdir()), [])
            self.assertFalse(any(family == 'bootstrap' for family, _, _ in calls))

    def test_read_original_over_eight_kib_refuses_without_adoption(self):
        with TemporaryDirectory(prefix='actql-finite-install-') as directory:
            core, _, _ = self.core(oversized=True)
            with self.assertRaises(LocalInstallationCleanupPending) as raised:
                self.create(core, Path(directory))
            installation = raised.exception.cleanup_installation
            self.assertIsNone(installation._epoch)
            self.assertIsNone(installation._binding)
            self.assertTrue(installation.close())


if __name__ == '__main__':
    unittest.main()
