"""Source-recipe refusals; no Rust compiler, Engine or installed acceptance."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


CANDIDATE = Path(__file__).resolve().parents[1] / 'packages/python-local-runtime/native/pre-root'
SPEC = importlib.util.spec_from_file_location('verify_shared_provider', CANDIDATE / 'verify_workspace.py')
assert SPEC is not None and SPEC.loader is not None
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class SharedProviderRecipeTests(unittest.TestCase):
    def setUp(self):
        self.record = json.loads((CANDIDATE / 'workspace-build-inputs.json').read_text())
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.original = {'crates/c-api/build.rs': b'fn main() {}\n'}
        self.write('crates/c-api/build.rs', self.original['crates/c-api/build.rs'])
        for name, relay in [
            ('crates/c-api/Cargo.toml', '["wasmtime/actql-owned-capacity"]'),
            ('crates/c-api/artifact/Cargo.toml', '["wasmtime-c-api/actql-owned-capacity"]'),
            ('crates/wasmtime/Cargo.toml', '[]'),
        ]:
            source = '[package]\nname="original"\n[features]\ndefault=["cranelift"]\ncranelift=[]\n'
            self.original[name] = source.encode()
            if '/artifact/' in name:
                source = source.replace('[package]\n', '[package]\nbuild="actql_owned_build.rs"\n')
            self.write(name, (source + 'actql-owned-capacity=' + relay + '\n').encode())

    def write(self, name, source):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(source)

    def test_exact_external_provider_recipe_and_original_defaults(self):
        VERIFY.verify_provider_recipe(self.record, CANDIDATE)
        VERIFY.verify_linked_workspace(self.root, self.original)

    def test_second_c_provider_copy_and_duplicate_rust_copy_are_refused(self):
        self.record['copy_before_patch'].append({
            'source': 'owned_capacity.c', 'target': 'crates/c-api/owned_capacity.c', 'sha256': '0' * 64,
        })
        with self.assertRaisesRegex(ValueError, 'Only original Rust'):
            VERIFY.verify_provider_recipe(self.record, CANDIDATE)
        self.record['copy_before_patch'][-1] = copy.deepcopy(self.record['copy_before_patch'][0])
        with self.assertRaisesRegex(ValueError, 'Only original Rust'):
            VERIFY.verify_provider_recipe(self.record, CANDIDATE)

    def test_changed_provider_digest_and_foreign_runtime_lookup_are_refused(self):
        self.record['provider_source_inputs'][0]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'source digest mismatch'):
            VERIFY.verify_provider_recipe(self.record, CANDIDATE)
        self.record = json.loads((CANDIDATE / 'workspace-build-inputs.json').read_text())
        self.record['native_provider_link']['runtime_resolution'] = '/opt/homebrew/lib'
        with self.assertRaisesRegex(ValueError, 'original-provider link'):
            VERIFY.verify_provider_recipe(self.record, CANDIDATE)

    def test_c_api_recompiling_provider_is_refused(self):
        self.write('crates/c-api/build.rs', b'fn main() { cc::Build::new(); }\n')
        with self.assertRaisesRegex(ValueError, 'second provider'):
            VERIFY.verify_linked_workspace(self.root, self.original)

    def test_default_feature_change_is_refused(self):
        path = self.root / 'crates/c-api/artifact/Cargo.toml'
        path.write_text(path.read_text().replace('default=["cranelift"]', 'default=[]'))
        with self.assertRaisesRegex(ValueError, 'Unrelated original'):
            VERIFY.verify_linked_workspace(self.root, self.original)

    def test_wrong_feature_relay_and_build_entry_are_refused(self):
        path = self.root / 'crates/c-api/artifact/Cargo.toml'
        original = path.read_text()
        path.write_text(original.replace('wasmtime-c-api/actql-owned-capacity', 'foreign/provider'))
        with self.assertRaisesRegex(ValueError, 'feature relay'):
            VERIFY.verify_linked_workspace(self.root, self.original)
        path.write_text(original.replace('actql_owned_build.rs', 'foreign.rs'))
        with self.assertRaisesRegex(ValueError, 'artifact build entry'):
            VERIFY.verify_linked_workspace(self.root, self.original)


class ThreadPreparationTests(unittest.TestCase):
    """Independent small patch controls, separate from pinned source checks."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.candidate = Path(self.directory.name) / 'candidate'
        self.root = Path(self.directory.name) / 'workspace'
        self.candidate.mkdir()
        self.root.mkdir()
        paths = [item['path'] for item in json.loads((CANDIDATE / 'thread-source.json').read_bytes())['inputs']]
        self.originals = {name: b'original\n' for name in paths}
        patch = ''.join(f'diff --git a/{name} b/{name}\n--- a/{name}\n+++ b/{name}\n'
                        '@@ -1 +1 @@\n-original\n+derived\n' for name in paths).encode()
        (self.candidate / 'wasmtime-owned-thread-review.patch').write_bytes(patch)
        wrapper = b'original private wrapper\n'
        (self.candidate / 'owned_handler_thread.rs').write_bytes(wrapper)
        self.record = {
            'status': 'source-preparation-only', 'normal_profile': None,
            'Engine_executed': False, 'runtime_build_executed': False,
            'upstream_git_commit': 'original', 'target': 'aarch64-apple-darwin',
            'feature': 'actql-owned-capacity',
            'inputs': [dict(path=name, **self.digest(body)) for name, body in self.originals.items()],
            'outputs': {name: self.digest(b'derived\n') for name in paths},
            'copy': dict(source='owned_handler_thread.rs',
                         target=VERIFY.RUST_COPIES['owned_handler_thread.rs'], **self.digest(wrapper)),
            'patch': dict(path='wasmtime-owned-thread-review.patch', **self.digest(patch)),
        }
        for name, body in self.originals.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(body)
        path = self.root / self.record['copy']['target']
        path.write_bytes(wrapper)

    @staticmethod
    def digest(body):
        return dict(bytes=len(body), sha256=hashlib.sha256(body).hexdigest())

    def verify(self):
        raw = (json.dumps(self.record) + '\n').encode()
        (self.candidate / 'thread-source.json').write_bytes(raw)
        (self.candidate / 'workspace-build-inputs.json').write_text(json.dumps({
            'upstream_git_commit': 'original', 'target': 'aarch64-apple-darwin',
            'thread_preparation': dict(source='thread-source.json', sha256=hashlib.sha256(raw).hexdigest()),
        }))
        VERIFY.verify_thread_patch(self.root, self.originals, self.candidate)

    def test_exact_source_only_patch_and_copy(self):
        self.verify()
        for name in self.originals:
            self.assertEqual((self.root / name).read_bytes(), b'derived\n')

    def test_execution_claim_and_duplicate_input_refuse(self):
        self.record['Engine_executed'] = True
        with self.assertRaisesRegex(ValueError, 'source-only'):
            self.verify()
        self.record['Engine_executed'] = False
        self.record['inputs'].append(copy.deepcopy(self.record['inputs'][0]))
        with self.assertRaisesRegex(ValueError, 'source closure'):
            self.verify()

    def test_foreign_original_and_changed_wrapper_refuse(self):
        name = self.record['inputs'][0]['path']
        self.originals[name] = b'foreign\n'
        with self.assertRaisesRegex(ValueError, 'source digest'):
            self.verify()
        self.originals[name] = b'original\n'
        (self.root / self.record['copy']['target']).write_bytes(b'foreign\n')
        with self.assertRaisesRegex(ValueError, 'Changed original thread wrapper'):
            self.verify()

    def test_changed_patch_and_derived_output_refuse(self):
        self.record['patch']['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'patch digest'):
            self.verify()
        patch = (self.candidate / 'wasmtime-owned-thread-review.patch').read_bytes()
        self.record['patch'].update(self.digest(patch))
        self.record['outputs'][next(iter(self.originals))]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'Derived original thread digest'):
            self.verify()


class PinnedThreadPatchTests(unittest.TestCase):
    """Read the real pinned patch, not only a synthetic applicable patch."""

    def test_pinned_patch_parses_strictly_and_names_only_original_three_inputs(self):
        record = json.loads((CANDIDATE / 'thread-source.json').read_bytes())
        patch = (CANDIDATE / record['patch']['path']).read_bytes()
        self.assertEqual(ThreadPreparationTests.digest(patch), {
            'bytes': record['patch']['bytes'], 'sha256': record['patch']['sha256']})
        result = subprocess.run(['git', 'apply', '--no-index', '--numstat', '-'],
                                input=patch, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        rows = [line.split('\t') for line in result.stdout.decode().splitlines()]
        self.assertEqual({row[2] for row in rows}, {item['path'] for item in record['inputs']})
        self.assertEqual(len(rows), 3)

    def test_original_wrong_final_hunk_count_is_rejected_without_recount(self):
        patch = (CANDIDATE / 'wasmtime-owned-thread-review.patch').read_bytes()
        correct = b'@@ -34,6 +34,12 @@'
        self.assertEqual(patch.count(correct), 1)
        corrupt = patch.replace(correct, b'@@ -34,7 +34,13 @@')
        result = subprocess.run(['git', 'apply', '--no-index', '--numstat', '-'],
                                input=corrupt, capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
