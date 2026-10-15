"""Source-recipe refusals; no Rust compiler, Engine or installed acceptance."""
import copy
import importlib.util
import json
from pathlib import Path
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


if __name__ == '__main__':
    unittest.main()
