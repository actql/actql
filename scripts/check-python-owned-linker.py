"""Execute the selected Rust build script only; no C API library or VM loading."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'packages/python-local-runtime/native/pre-root/owned_build.rs'


class OwnedLinkerTests(unittest.TestCase):
    rustc: Path

    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='actql-owned-linker-')
        cls.directory = Path(cls.temporary.name)
        cls.binary = cls.directory / 'build-script'
        subprocess.run([str(cls.rustc), '--edition=2021', str(SOURCE), '-o', str(cls.binary)],
                       check=True, timeout=30)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def setUp(self):
        self.temporary_provider = tempfile.TemporaryDirectory(dir=self.directory)
        self.addCleanup(self.temporary_provider.cleanup)
        self.provider = Path(self.temporary_provider.name)
        # Metadata-only build input. The build script must never load it.
        self.library = self.provider / 'libactql_native_control.dylib'
        self.library.write_bytes(b'not a loadable library')

    def execute(self, **changes):
        environment = {
            **os.environ, 'CARGO_FEATURE_ACTQL_OWNED_CAPACITY': '1',
            'CARGO_CFG_TARGET_OS': 'macos', 'CARGO_CFG_TARGET_ARCH': 'aarch64',
            'ACTQL_OWNED_PROVIDER_DIR': str(self.provider),
        }
        for key, value in changes.items():
            if value is None:
                environment.pop(key, None)
            else:
                environment[key] = value
        return subprocess.run([str(self.binary)], env=environment,
                              capture_output=True, text=True, timeout=5)

    def test_installed_identity_and_local_provider_resolution(self):
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stderr)
        directives = result.stdout.splitlines()
        self.assertIn('cargo:rustc-link-arg-cdylib=-Wl,-install_name,@rpath/_libwasmtime.dylib',
                      directives)
        self.assertIn('cargo:rustc-link-arg=-Wl,-rpath,@loader_path', directives)
        self.assertIn('cargo:rustc-link-search=native=' + str(self.provider), directives)
        self.assertEqual(sum('-install_name,' in line for line in directives), 1)

    def test_disabled_feature_requires_no_provider_or_target(self):
        result = self.execute(CARGO_FEATURE_ACTQL_OWNED_CAPACITY=None,
                              ACTQL_OWNED_PROVIDER_DIR=None, CARGO_CFG_TARGET_OS=None,
                              CARGO_CFG_TARGET_ARCH=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('rustc-link-', result.stdout)

    def test_foreign_os_and_architecture_are_refused(self):
        for changes in ({'CARGO_CFG_TARGET_OS': 'linux'},
                        {'CARGO_CFG_TARGET_ARCH': 'x86_64'}):
            with self.subTest(changes=changes):
                result = self.execute(**changes)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('rustc-link-', result.stdout)

    def test_missing_relative_and_directive_injected_directory_are_refused(self):
        for path in (None, 'relative-provider', str(self.provider) + '\nforeign-directive'):
            with self.subTest(path=path):
                result = self.execute(ACTQL_OWNED_PROVIDER_DIR=path)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('rustc-link-', result.stdout)

    def test_empty_and_symlink_provider_are_refused(self):
        self.library.write_bytes(b'')
        self.assertNotEqual(self.execute().returncode, 0)
        self.library.unlink()
        original = self.provider / 'original.dylib'
        original.write_bytes(b'not loadable')
        self.library.symlink_to(original)
        self.assertNotEqual(self.execute().returncode, 0)

    def test_symlink_provider_directory_is_refused(self):
        alias = self.directory / ('alias-' + self.provider.name)
        alias.symlink_to(self.provider, target_is_directory=True)
        self.addCleanup(alias.unlink)
        result = self.execute(ACTQL_OWNED_PROVIDER_DIR=str(alias))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('rustc-link-', result.stdout)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rustc', type=Path, required=True)
    args = parser.parse_args()
    OwnedLinkerTests.rustc = args.rustc.resolve(strict=True)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(OwnedLinkerTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if result.testsRun != 6 or not result.wasSuccessful():
        raise SystemExit(1)
