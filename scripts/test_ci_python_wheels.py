"""Harness unit tests only: these fixtures are not installed product acceptance."""
import hashlib
import importlib.util
import io
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
    def test_transient_release_rejection_retries_same_pinned_get(self):
        error = ci.urllib.error.HTTPError(ci.DUCKDB_URL, 504, 'gateway', {}, None)
        response = io.BytesIO(b'bounded transport fixture')
        with patch.object(ci.urllib.request, 'urlopen', side_effect=[error, response]) as request, \
                patch.object(ci.time, 'sleep') as sleep:
            with ci.open_duckdb_release() as opened:
                self.assertEqual(opened.read(), b'bounded transport fixture')
        self.assertEqual(request.call_args_list,
                         [unittest.mock.call(ci.DUCKDB_URL, timeout=120)] * 2)
        sleep.assert_called_once_with(2)

    def test_permanent_release_rejection_keeps_original_failure(self):
        error = ci.urllib.error.HTTPError(ci.DUCKDB_URL, 404, 'missing', {}, None)
        with patch.object(ci.urllib.request, 'urlopen', side_effect=error) as request, \
                patch.object(ci.time, 'sleep') as sleep:
            with self.assertRaises(ci.urllib.error.HTTPError) as observed:
                ci.open_duckdb_release()
        self.assertIs(observed.exception, error)
        self.assertEqual(request.call_count, 1)
        sleep.assert_not_called()

    def test_repeated_transient_release_failure_stays_bounded(self):
        errors = [ci.urllib.error.HTTPError(ci.DUCKDB_URL, 504, 'gateway', {}, None)
                  for _ in range(3)]
        with patch.object(ci.urllib.request, 'urlopen', side_effect=errors) as request, \
                patch.object(ci.time, 'sleep') as sleep:
            with self.assertRaises(ci.urllib.error.HTTPError) as observed:
                ci.open_duckdb_release()
        self.assertIs(observed.exception, errors[-1])
        self.assertEqual(request.call_count, 3)
        self.assertEqual(sleep.call_args_list, [unittest.mock.call(2), unittest.mock.call(4)])

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


class FailureLocationTests(unittest.TestCase):
    def test_known_core_seal_status_is_observed_without_private_values_or_retry(self):
        import io
        diagnostics = load('ci_installed_seal_status', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        core_error = type('LocalCoreError', (RuntimeError,), {'__module__': 'actql_sdk._local_core'})
        original = core_error('private Core message')
        original.operation = 'seal'
        original.code = -123
        original.private_reference = 'private-reference-secret'
        outer = RuntimeError('public cleanup pending')
        outer.original_error = original
        stream = io.StringIO()
        diagnostics.report_contexts(outer, stream)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        self.assertNotIn('core_buffer_seal_code', records[0])
        self.assertEqual(records[1]['core_buffer_seal_code'], -123)
        self.assertIs(outer.original_error, original)
        self.assertEqual(original.code, -123)
        self.assertNotIn('private Core message', stream.getvalue())
        self.assertNotIn('private-reference-secret', stream.getvalue())

    def test_foreign_operations_and_nonplain_or_unbounded_statuses_are_not_reported(self):
        import io
        diagnostics = load('ci_installed_seal_status_refusals', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        class ForeignOperation:
            def __eq__(self, other):
                raise AssertionError('Do not inspect a foreign operation')
        for module, operation, code in [
                ('foreign', 'seal', -1),
                ('actql_sdk._local_core', 'private-operation-secret', -1),
                ('actql_sdk._local_core', ForeignOperation(), -1),
                ('actql_sdk._local_core', 'seal', True),
                ('actql_sdk._local_core', 'seal', 'private-code-secret'),
                ('actql_sdk._local_core', 'seal', 1 << 31),
                ('actql_sdk._local_core', 'seal', -(1 << 31) - 1),
                ('actql_sdk._local_core', 'seal', object())]:
            with self.subTest(module=module, operation=operation, code_type=type(code).__name__):
                core_error = type('LocalCoreError', (RuntimeError,), {'__module__': module})
                original = core_error('private message')
                original.operation, original.code = operation, code
                stream = io.StringIO()
                diagnostics.report_contexts(original, stream)
                record = json.loads(stream.getvalue())
                self.assertNotIn('core_buffer_seal_code', record)
                self.assertNotIn('private-', stream.getvalue())

    def test_suppressed_context_reports_locations_not_private_values(self):
        import io
        diagnostics = load('ci_installed_run', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        try:
            try:
                raise ValueError('private-reference-secret')
            except ValueError:
                raise RuntimeError('public-unknown') from None
        except RuntimeError as failure:
            original_context = failure.__context__
            stream = io.StringIO()
            diagnostics.report_contexts(failure, stream)
            self.assertIs(failure.__context__, original_context)
            self.assertTrue(failure.__suppress_context__)
            text = stream.getvalue()
        self.assertNotIn('private-reference-secret', text)
        self.assertNotIn('public-unknown', text)
        records = [json.loads(line) for line in text.splitlines()]
        self.assertEqual([record['exception_type'] for record in records], ['RuntimeError', 'ValueError'])
        for record in records:
            self.assertTrue(record['frames'])
            for frame in record['frames']:
                self.assertEqual(set(frame), {'file', 'line', 'function'})
                self.assertEqual(frame['file'], Path(__file__).name)
                self.assertGreater(frame['line'], 0)

    def test_same_failure_is_raised_once_even_if_diagnostics_fail(self):
        diagnostics = load('ci_installed_run_once', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        original = RuntimeError('public-unknown')
        with patch.object(diagnostics.runpy, 'run_path', side_effect=original) as execute, patch.object(
                diagnostics, 'report_contexts', side_effect=OSError('diagnostics unavailable')):
            with self.assertRaises(RuntimeError) as raised:
                diagnostics.run_consumer(Path('/external/fixture.py'))
        self.assertIs(raised.exception, original)
        execute.assert_called_once_with('/external/fixture.py', run_name='__main__')

    def test_chain_and_output_are_bounded(self):
        import io
        diagnostics = load('ci_installed_run_bounds', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        error = ValueError('private')
        for _ in range(100):
            next_error = ValueError('private')
            next_error.__context__ = error
            error = next_error
        stream = io.StringIO()
        diagnostics.report_contexts(error, stream)
        self.assertLessEqual(len(stream.getvalue().encode()), diagnostics.MAX_OUTPUT_BYTES)
        self.assertEqual(len(stream.getvalue().splitlines()), diagnostics.MAX_CONTEXTS)

    def test_retained_original_error_is_observed_without_values_or_mutation(self):
        import io
        diagnostics = load('ci_installed_retained_error', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        try:
            raise ValueError('private retained message')
        except ValueError as caught:
            original = caught
        outer = RuntimeError('public unknown')
        outer.original_error = original
        self.assertIsNone(outer.__context__)
        stream = io.StringIO()
        diagnostics.report_contexts(outer, stream)
        self.assertIs(outer.original_error, original)
        text = stream.getvalue()
        self.assertNotIn('private retained message', text)
        records = [json.loads(line) for line in text.splitlines()]
        self.assertEqual([record['exception_type'] for record in records], ['RuntimeError', 'ValueError'])
        self.assertTrue(records[1]['frames'])
        outer.original_error = {'credential': 'private non-exception value'}
        stream = io.StringIO()
        diagnostics.report_contexts(outer, stream)
        self.assertEqual(len(stream.getvalue().splitlines()), 1)
        self.assertNotIn('private non-exception value', stream.getvalue())
        outer.original_error = outer
        stream = io.StringIO()
        diagnostics.report_contexts(outer, stream)
        self.assertEqual(len(stream.getvalue().splitlines()), 1)

    def test_cycle_is_not_repeated(self):
        import io
        diagnostics = load('ci_installed_run_cycle', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        error = ValueError('private')
        error.__context__ = error
        stream = io.StringIO()
        diagnostics.report_contexts(error, stream)
        self.assertEqual(len(stream.getvalue().splitlines()), 1)


if __name__ == '__main__':
    unittest.main()
