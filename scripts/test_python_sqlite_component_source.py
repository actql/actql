"""Mutation checks for the non-executing SQLite source closure."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'packages/python-local-runtime/native/sqlite-component'
SPEC = importlib.util.spec_from_file_location('sqlite_candidate', SOURCE / 'prepare.py')
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def identity(raw):
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


class SQLiteSourceTests(unittest.TestCase):
    def test_current_provider_source_identities_are_exact(self):
        recipe = json.loads((SOURCE / 'source.json').read_bytes())
        for path, expected in recipe['provider_inputs'].items():
            with self.subTest(path=path):
                self.assertEqual(identity((ROOT / path).read_bytes()), expected)

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.source = self.root / 'source'
        self.source.mkdir()
        self.archive = self.root / 'candidate.zip'
        with zipfile.ZipFile(self.archive, 'w') as output:
            output.writestr('candidate/sqlite3.c', b'pinned engine\n')
            output.writestr('candidate/sqlite3.h', b'pinned header\n')
        self.destination = self.root / 'stage'
        self.recipe = json.loads((SOURCE / 'source.json').read_bytes())
        self.recipe['upstream'].update(identity(self.archive.read_bytes()))
        self.recipe['upstream']['prefix'] = 'candidate/'
        for name, raw in [('sqlite3.c', b'pinned engine\n'), ('sqlite3.h', b'pinned header\n')]:
            self.recipe['upstream']['members'][name] = {
                **identity(raw), 'sha3_256': hashlib.sha3_256(raw).hexdigest()}
        for name in ('component.c', 'component.h', 'api.h', 'NOTICE'):
            (self.source / name).write_bytes((SOURCE / name).read_bytes())

    def stage(self, process_target=None):
        (self.source / 'source.json').write_text(json.dumps(self.recipe))
        return MODULE.prepare(self.archive, self.destination, source=self.source, process_target=process_target)

    def test_stage_preserves_originals_without_build_load_or_adoption(self):
        before = self.archive.read_bytes()
        record = self.stage()
        self.assertEqual(self.archive.read_bytes(), before)
        self.assertEqual((self.destination / 'sqlite3.c').read_bytes(), b'pinned engine\n')
        self.assertEqual((self.destination / 'component.c').read_bytes(), (SOURCE / 'component.c').read_bytes())
        self.assertEqual(record['compiled'], 0)
        self.assertEqual(record['loaded'], 0)
        self.assertIs(record['normal_profile'], None)
        self.assertIs(record['installed_supplier'], False)
        self.assertEqual(record['optimization'], '-O2')

    def test_release_optimization_is_required_before_stage_publication(self):
        for value in ('-O0', '-O3', '-Ofast', None):
            with self.subTest(value=value):
                self.recipe['optimization'] = value
                with self.assertRaisesRegex(ValueError, 'pinned release optimization'):
                    self.stage()
                self.assertFalse(self.destination.exists())

    def test_archive_tamper_is_rejected_before_publication(self):
        self.archive.write_bytes(self.archive.read_bytes() + b'x')
        with self.assertRaisesRegex(ValueError, 'size mismatch'):
            self.stage()
        self.assertFalse(self.destination.exists())

    def test_member_digest_and_sha3_are_independently_required(self):
        for key in ('sha256', 'sha3_256'):
            with self.subTest(key=key):
                old = self.recipe['upstream']['members']['sqlite3.c'][key]
                self.recipe['upstream']['members']['sqlite3.c'][key] = '0' * 64
                with self.assertRaisesRegex(ValueError, 'member digest mismatch'):
                    self.stage()
                self.assertFalse(self.destination.exists())
                self.recipe['upstream']['members']['sqlite3.c'][key] = old

    def test_wrapper_tamper_is_rejected(self):
        path = self.source / 'component.c'
        path.write_bytes(path.read_bytes().replace(b'SQLITE_API static', b'SQLITE_API       '))
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.stage()
        self.assertFalse(self.destination.exists())

    def test_missing_notice_is_rejected(self):
        (self.source / 'NOTICE').unlink()
        with self.assertRaises(FileNotFoundError):
            self.stage()
        self.assertFalse(self.destination.exists())

    def test_selected_provider_change_is_not_accepted_as_same_recipe(self):
        name = next(iter(self.recipe['provider_inputs']))
        self.recipe['provider_inputs'][name]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.stage()

    def test_symlink_archive_is_rejected(self):
        link = self.root / 'link.zip'
        link.symlink_to(self.archive)
        self.archive = link
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            self.stage()

    def test_source_and_existing_destination_are_not_overwritten(self):
        self.destination = self.source / 'nested'
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            self.stage()
        self.destination = self.root / 'stage'
        self.destination.mkdir()
        with self.assertRaisesRegex(ValueError, 'destination exists'):
            self.stage()

    def test_installed_supplier_or_profile_claim_is_rejected(self):
        self.recipe['installed_supplier'] = True
        with self.assertRaisesRegex(ValueError, 'review-only'):
            self.stage()
        self.recipe['installed_supplier'] = False
        self.recipe['normal_profile'] = 123
        with self.assertRaisesRegex(ValueError, 'review-only'):
            self.stage()





class LinuxProcessSQLiteSourceTests(unittest.TestCase):
    setUp = SQLiteSourceTests.setUp
    stage = SQLiteSourceTests.stage
    def test_x64_selection_derives_its_own_recipe_without_relabeling_arm(self):
        record = self.stage('linux-x64-gnu')
        selected = record['selected_process_recipe']
        self.assertEqual(selected['target'], 'x86_64-unknown-linux-gnu')
        self.assertEqual(selected['process_format'], 'ELF64-little-x86-64-shared')
        self.assertIsNone(selected['deployment_target'])
        original = (self.source / 'source.json').read_bytes()
        arm, arm_raw = MODULE.process_recipe(original, 'linux-arm64-gnu')
        self.assertEqual(arm['target'], 'aarch64-unknown-linux-gnu')
        self.assertNotEqual(record['recipe_sha256'], hashlib.sha256(arm_raw).hexdigest())
        self.assertEqual(record['original_recipe_sha256'], hashlib.sha256(original).hexdigest())
        for name in ('upstream', 'local', 'provider_inputs', 'defines', 'memory', 'optimization'):
            self.assertEqual(selected[name], self.recipe[name])
        self.assertEqual((record['compiled'], record['loaded']), (0, 0))
        self.assertFalse(record['installed_supplier'])
        self.assertIsNone(record['normal_profile'])

    def test_linux_selection_is_genuinely_derived_without_changing_source_or_heap(self):
        record = self.stage('linux-arm64-gnu')
        selected = record['selected_process_recipe']
        original = (self.source / 'source.json').read_bytes()
        self.assertEqual(record['original_recipe_sha256'], hashlib.sha256(original).hexdigest())
        self.assertEqual(selected['target'], 'aarch64-unknown-linux-gnu')
        self.assertIsNone(selected['deployment_target'])
        self.assertFalse(selected['automatic_initializers'])
        self.assertFalse(selected['component_tls'])
        for name in ('upstream', 'local', 'provider_inputs', 'defines', 'memory', 'optimization'):
            self.assertEqual(selected[name], self.recipe[name])
        expected = (json.dumps(selected, sort_keys=True, separators=(',', ':')) + '\n').encode()
        self.assertEqual(record['recipe_sha256'], hashlib.sha256(expected).hexdigest())
        self.assertNotEqual(record['recipe_sha256'], record['original_recipe_sha256'])
        self.assertEqual((self.destination / 'component.c').read_bytes(), (SOURCE / 'component.c').read_bytes())
        self.assertEqual((self.destination / 'sqlite3.c').read_bytes(), b'pinned engine\n')
        self.assertFalse(record['installed_supplier'])
        self.assertEqual((record['compiled'], record['loaded']), (0, 0))

    def test_default_darwin_recipe_identity_is_unchanged(self):
        record = self.stage()
        self.assertEqual(record['target'], 'aarch64-apple-darwin')
        self.assertEqual(record['recipe_sha256'], hashlib.sha256((self.source / 'source.json').read_bytes()).hexdigest())
        self.assertNotIn('selected_process_recipe', record)
        self.assertNotIn('original_recipe_sha256', record)

    def test_foreign_target_refuses_before_stage_publication(self):
        for target in ('linux-x64-musl', 'linux-arm64-musl', 'linux-riscv64-gnu', 'darwin-arm64', True):
            with self.subTest(target=target):
                with self.assertRaisesRegex(ValueError, 'target selection'):
                    self.stage(target)
                self.assertFalse(self.destination.exists())

    def test_x64_cannot_derive_from_foreign_recipe_or_provider_inputs(self):
        for target, deployment in (('x86_64-unknown-linux-gnu', '11.0'), ('aarch64-apple-darwin', '26.0')):
            with self.subTest(target=target, deployment=deployment):
                self.recipe['target'], self.recipe['deployment_target'] = target, deployment
                with self.assertRaisesRegex(ValueError, 'target selection'):
                    self.stage('linux-x64-gnu')
                self.assertFalse(self.destination.exists())
        self.recipe['target'], self.recipe['deployment_target'] = 'aarch64-apple-darwin', '11.0'
        name = next(iter(self.recipe['provider_inputs']))
        self.recipe['provider_inputs'][name]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.stage('linux-x64-gnu')
        self.assertFalse(self.destination.exists())


if __name__ == '__main__':
    unittest.main()
