"""Harness unit tests only: these fixtures are not installed product acceptance."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

ci = load('ci_python_wheels', SCRIPTS / 'ci-python-wheels.py')
audit = load('ci_python_audit', SCRIPTS / 'fixtures/ci-python-installed-audit.py')


class OrchestrationTests(unittest.TestCase):
    def test_linux_is_not_reported_as_local_acceptance(self):
        with patch.object(ci.sys, 'platform', 'linux'), self.assertRaisesRegex(ValueError, 'darwin-arm64'):
            ci.run_acceptance(Path('/unused'))

    def test_timeout_keeps_diagnostics_and_never_creates_acceptance(self):
        import subprocess
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / 'acceptance'
            def git(args, **kwargs):
                return b'' if 'status' in args else 'a' * 40 + '\n'
            with patch.object(ci.sys, 'platform', 'darwin'), patch.object(ci.platform, 'machine', return_value='arm64'), \
                    patch.object(ci.subprocess, 'check_output', side_effect=git), patch.object(
                        ci.subprocess, 'run', side_effect=subprocess.TimeoutExpired('builder', 600, output=b'partial', stderr=b'slow')):
                with self.assertRaisesRegex(RuntimeError, r'builder-venv failed \(timeout\)'):
                    ci.run_acceptance(destination)
            self.assertEqual((destination / 'builder-venv.stdout').read_bytes(), b'partial')
            self.assertEqual((destination / 'builder-venv.stderr').read_bytes(), b'slow')
            step = json.loads((destination / 'steps.json').read_text())[0]
            self.assertTrue(step['timed_out'])
            self.assertIsNone(step['exit_code'])
            self.assertFalse((destination / 'acceptance.json').exists())

    def test_consumer_environment_does_not_inherit_credentials_or_source_paths(self):
        with patch.dict('os.environ', {'PYTHONPATH': '/source', 'GH_TOKEN': 'not-for-consumer', 'NODE_PATH': '/node'}):
            env = ci.consumer_environment(Path('/consumer'), Path('/home'))
        self.assertEqual(env['PATH'], '/consumer/bin')
        self.assertEqual(env['PIP_CONFIG_FILE'], ci.os.devnull)
        self.assertNotIn('GH_TOKEN', env)
        self.assertNotIn('PYTHONPATH', env)
        self.assertNotIn('NODE_PATH', env)

    def test_reject_checkout_output(self):
        with self.assertRaisesRegex(ValueError, 'outside'):
            ci.external_destination(ci.ROOT / 'new-output')

    def test_reject_reused_destination(self):
        with tempfile.TemporaryDirectory() as tmp, self.assertRaisesRegex(ValueError, 'fresh'):
            ci.external_destination(Path(tmp))

    def test_fresh_external_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'new'
            self.assertEqual(ci.external_destination(path), path.resolve())

    def test_archive_tamper_is_refused_before_extraction(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / 'archive'
            archive.write_bytes(b'not pinned')
            with self.assertRaisesRegex(ValueError, 'pinned'):
                ci.extract_duckdb(archive, Path(tmp) / 'library')
            self.assertFalse((Path(tmp) / 'library').exists())

    def test_extracts_only_pinned_member(self):
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / 'archive'
            with zipfile.ZipFile(archive, 'w') as zipped:
                zipped.writestr('libduckdb.dylib', b'synthetic library')
                zipped.writestr('../not-extracted', b'unrelated')
            with patch.object(ci, 'DUCKDB_BYTES', archive.stat().st_size), patch.object(
                    ci, 'DUCKDB_SHA256', hashlib.sha256(archive.read_bytes()).hexdigest()):
                target = ci.extract_duckdb(archive, Path(tmp) / 'library')
            self.assertEqual(target.read_bytes(), b'synthetic library')
            self.assertEqual(sorted(p.name for p in Path(tmp).iterdir()), ['archive', 'library'])

    def test_duplicate_library_member_is_refused(self):
        import warnings
        with tempfile.TemporaryDirectory() as tmp:
            archive = Path(tmp) / 'archive'
            with zipfile.ZipFile(archive, 'w') as zipped, warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                zipped.writestr('libduckdb.dylib', b'one')
                zipped.writestr('libduckdb.dylib', b'two')
            with patch.object(ci, 'DUCKDB_BYTES', archive.stat().st_size), patch.object(
                    ci, 'DUCKDB_SHA256', hashlib.sha256(archive.read_bytes()).hexdigest()):
                with self.assertRaisesRegex(ValueError, 'unique'):
                    ci.extract_duckdb(archive, Path(tmp) / 'library')


class InstalledAuditTests(unittest.TestCase):
    def test_incomplete_cohort_cannot_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / 'cohort.json').write_text(json.dumps({'wheels': []}))
            (path / 'report.json').write_text(json.dumps({'install': []}))
            with self.assertRaisesRegex(AssertionError, 'complete normal cohort'):
                audit.audit(path, path / 'report.json')

    def test_changed_wheel_bytes_cannot_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / 'wheels').mkdir()
            records = []
            for name in ('actql', 'actql-sdk', 'actql-local-runtime'):
                (path / 'wheels' / (name + '.whl')).write_bytes(b'tampered')
                records.append({'distribution': name, 'file': name + '.whl', 'bytes': 8, 'sha256': '0' * 64})
            (path / 'cohort.json').write_text(json.dumps({'wheels': records}))
            (path / 'report.json').write_text(json.dumps({'install': []}))
            with self.assertRaisesRegex(AssertionError, 'Wheel bytes differ'):
                audit.audit(path, path / 'report.json')

    def test_public_registry_wheel_is_not_a_local_cohort_install(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            (path / 'wheels').mkdir()
            records = []
            installs = []
            for name in ('actql', 'actql-sdk', 'actql-local-runtime'):
                body = b'synthetic packaging fixture, not runtime acceptance'
                digest = hashlib.sha256(body).hexdigest()
                (path / 'wheels' / (name + '.whl')).write_bytes(body)
                records.append({'distribution': name, 'file': name + '.whl',
                                'bytes': len(body), 'sha256': digest})
                installs.append({'metadata': {'name': name}, 'is_direct': True,
                                 'download_info': {'url': 'https://example.invalid/' + name,
                                                   'archive_info': {'hashes': {'sha256': digest}}}})
            (path / 'cohort.json').write_text(json.dumps({'wheels': records}))
            (path / 'report.json').write_text(json.dumps({'install': installs}))
            with self.assertRaisesRegex(AssertionError, 'exact local wheel'):
                audit.audit(path, path / 'report.json')


if __name__ == '__main__':
    unittest.main()
