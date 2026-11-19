"""Harness unit tests only: these fixtures are not installed product acceptance."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import AsyncMock, patch
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

    def test_unselected_linux_architecture_is_not_reported_as_local_acceptance(self):
        with patch.object(ci.sys, 'platform', 'linux'), patch.object(ci.platform, 'machine', return_value='aarch64'), \
                self.assertRaisesRegex(ValueError, 'darwin-arm64'):
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


class LinuxOrchestrationTests(unittest.TestCase):
    def test_linux_release_keeps_its_original_url_digest_and_unique_member(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archive = root / 'original.zip'
            with zipfile.ZipFile(archive, 'w') as zipped:
                zipped.writestr('libduckdb.so', b'explicit inert Linux library port')
                zipped.writestr('libduckdb.dylib', b'foreign profile, never selected')
            with patch.object(ci, 'LINUX_DUCKDB_BYTES', archive.stat().st_size), patch.object(
                    ci, 'LINUX_DUCKDB_SHA256', hashlib.sha256(archive.read_bytes()).hexdigest()), patch.object(
                    ci.urllib.request, 'urlopen', return_value=io.BytesIO(archive.read_bytes())) as request:
                with ci.open_duckdb_release('linux-x64') as response:
                    self.assertEqual(response.read(), archive.read_bytes())
                request.assert_called_once_with(
                    'https://github.com/duckdb/duckdb/releases/download/v1.4.3/libduckdb-linux-amd64.zip',
                    timeout=120)
                library = ci.extract_duckdb(archive, root / 'selected.so', target_platform='linux-x64')
                self.assertEqual(library.read_bytes(), b'explicit inert Linux library port')
                archive.write_bytes(archive.read_bytes() + b'changed')
                with self.assertRaisesRegex(ValueError, 'pinned'):
                    ci.extract_duckdb(archive, root / 'changed.so', target_platform='linux-x64')
            self.assertFalse((root / 'changed.so').exists())

    def test_linux_recipe_reaches_same_cohort_after_one_original_core(self):
        import subprocess
        class ReachedOriginalCohort(RuntimeError):
            pass
        with tempfile.TemporaryDirectory() as tmp:
            destination = (Path(tmp) / 'acceptance').resolve()
            commands = []
            builds = []
            observed = []
            source = 'a' * 40
            def git(args, **options):
                return b'' if 'status' in args else source + '\n'
            def extract(archive, target, **options):
                self.assertEqual(options, {'target_platform': 'linux-x64'})
                self.assertEqual(target.name, 'libduckdb.so')
                target.write_bytes(b'explicit physical port; not a native library')
                return target
            def command(args, **options):
                commands.append(args)
                if args[0] == 'moon':
                    directory = Path(args[args.index('--target-dir') + 1])
                    module = directory / 'wasm/release/build/client_host_wasm/client_host_wasm.wasm'
                    module.parent.mkdir(parents=True)
                    module.write_bytes(b'explicit compiler port; not executable Wasm')
                    builds.append(module)
                if '--record-module-original' in args:
                    receipt = Path(args[args.index('--destination') + 1])
                    receipt.write_text(json.dumps({'module': str(builds[0]), 'source_sha': source,
                        'module_sha256': hashlib.sha256(builds[0].read_bytes()).hexdigest()}))
                return subprocess.CompletedProcess(args, 0, stdout=b'{}', stderr=b'')
            def component(run, python, module, receipt, selected):
                self.assertEqual(builds, [module])
                self.assertEqual(Path(json.loads(receipt.read_text())['module']), module)
                observed.append(module)
            with patch.object(ci.sys, 'platform', 'linux'), patch.object(ci.platform, 'machine', return_value='x86_64'), \
                    patch.dict(ci.os.environ, {'MOON_HOME': '/explicit/original/moon'}), \
                    patch.object(ci.subprocess, 'check_output', side_effect=git), \
                    patch.object(ci.subprocess, 'run', side_effect=command), \
                    patch.object(ci, 'open_duckdb_release', return_value=io.BytesIO(b'archive port')) as download, \
                    patch.object(ci, 'extract_duckdb', side_effect=extract), \
                    patch.object(ci, 'accept_submission_observation', side_effect=component), \
                    patch.object(ci, 'accept_public_lifecycle', side_effect=component), \
                    patch.object(ci, 'select_release_version', return_value={'pythonVersion': '0.0.0.dev0'}), \
                    patch.object(ci, 'verify_built_cohort', side_effect=ReachedOriginalCohort):
                with self.assertRaises(ReachedOriginalCohort):
                    ci.run_acceptance(destination)
            download.assert_called_once_with('linux-x64')
            self.assertEqual(len(builds), 1)
            self.assertEqual(observed, builds * 2)
            image = next(args for args in commands if '--compile-platform' in args)
            runtime = next(args for args in commands if '--platform-runtime' in args)
            wheel = next(args for args in commands if 'scripts/build-python-product-wheels.py' in args[1])
            self.assertEqual(image[image.index('--core-receipt') + 1],
                             runtime[runtime.index('--core-receipt') + 1])
            self.assertEqual(wheel[wheel.index('--target-platform') + 1], 'linux-x64')
            self.assertLess(commands.index(image), commands.index(runtime))
            self.assertLess(commands.index(runtime), commands.index(wheel))
            self.assertFalse((destination / 'acceptance.json').exists())

    def test_supported_python_refuses_foreign_wheels_before_creating_consumer(self):
        supported = load('ci_supported_python_linux_control', SCRIPTS / 'ci-supported-python.py')
        with tempfile.TemporaryDirectory() as tmp:
            cohort = Path(tmp) / 'cohort'
            cohort.mkdir()
            (cohort / 'cohort.json').write_text(json.dumps({'package_version': '0.0.0.dev0'}))
            destination = Path(tmp) / 'consumer'
            def git(args, **options):
                return b'' if 'status' in args else 'a' * 40 + '\n'
            with patch.object(supported.platform, 'python_version', return_value='3.11.0'), \
                    patch.object(supported.EXISTING, 'normal_target', return_value='linux-x64'), \
                    patch.object(supported.subprocess, 'check_output', side_effect=git), \
                    patch.object(supported, 'verify_built_cohort', return_value={'cohort': {'platform': 'darwin-arm64'}}), \
                    patch.object(supported.subprocess, 'run', side_effect=AssertionError('No foreign consumer')):
                with self.assertRaisesRegex(ValueError, 'same original wheel platform'):
                    supported.accept(cohort, destination, '3.11.0')
            self.assertFalse(destination.exists())


class SubmissionObservationTests(unittest.TestCase):
    def test_normal_recipe_reaches_public_lifecycle_after_same_original_component(self):
        import subprocess
        class ReachedOriginalComponent(RuntimeError):
            pass
        with tempfile.TemporaryDirectory() as tmp:
            destination = (Path(tmp) / 'acceptance').resolve()
            builds = []
            reached = []
            source = 'a' * 40
            def git(args, **options):
                return b'' if 'status' in args else source + '\n'
            def extract(archive, target, **options):
                target.write_bytes(b'explicit library transport port; not a library')
                return target
            def command(args, **options):
                if args[0] == 'moon':
                    target = Path(args[args.index('--target-dir') + 1])
                    module = target / 'wasm/release/build/client_host_wasm/client_host_wasm.wasm'
                    module.parent.mkdir(parents=True)
                    module.write_bytes(b'explicit build port; not executable Core')
                    builds.append(module)
                if '--record-module-original' in args:
                    receipt = Path(args[args.index('--destination') + 1])
                    receipt.write_text(json.dumps({'module': str(builds[0]), 'source_sha': source,
                        'module_sha256': hashlib.sha256(builds[0].read_bytes()).hexdigest()}))
                if '--compile-platform' in args:
                    self.fail('Image construction bypassed the original component')
                return subprocess.CompletedProcess(args, 0, stdout=b'{}', stderr=b'')
            def component(run, python, module, receipt, selected):
                self.assertEqual(builds, [module])
                self.assertEqual(Path(json.loads(receipt.read_text())['module']), module)
                self.assertEqual(python, destination / 'builder/bin/python')
                self.assertEqual(selected, destination)
                reached.append(module)
            def lifecycle(run, python, module, receipt, selected):
                self.assertEqual(reached, [module])
                component(run, python, module, receipt, selected)
                raise ReachedOriginalComponent()
            with patch.object(ci.sys, 'platform', 'darwin'), patch.object(ci.platform, 'machine', return_value='arm64'), \
                    patch.dict(ci.os.environ, {'MOON_HOME': '/explicit/moon-tool-port'}), \
                    patch.object(ci.subprocess, 'check_output', side_effect=git), \
                    patch.object(ci.subprocess, 'run', side_effect=command), \
                    patch.object(ci, 'open_duckdb_release', return_value=io.BytesIO(b'archive port')), \
                    patch.object(ci, 'extract_duckdb', side_effect=extract), \
                    patch.object(ci, 'accept_submission_observation', side_effect=component), \
                    patch.object(ci, 'accept_public_lifecycle', side_effect=lifecycle):
                with self.assertRaises(ReachedOriginalComponent):
                    ci.run_acceptance(destination)
            self.assertEqual(reached, builds * 2)
            self.assertFalse((destination / 'acceptance.json').exists())

    def original(self, path):
        module = path / 'original.wasm'
        module.write_bytes(b'independent artifact identity fixture; not executable Core')
        receipt = path / 'module-receipt.json'
        receipt.write_text(json.dumps({'module': str(module),
            'module_sha256': hashlib.sha256(module.read_bytes()).hexdigest(),
            'source_sha': 'a' * 40}))
        observed = {'success': True, 'module_sha256': hashlib.sha256(module.read_bytes()).hexdigest(),
            'cases': ['missing', 'retained', 'conflict', 'refusal', 'cleanup', 'fuel'],
            'initial_diagnostic_fuel': 32_000_000_000, 'fuel_refills': 0}
        return module, receipt, observed

    def test_consumes_same_original_once_without_second_build_or_normal_claim(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            module, receipt, observed = self.original(path)
            calls = []
            def run(name, args, **options):
                calls.append((name, args, options))
                return json.dumps(observed).encode()
            result = ci.accept_submission_observation(run, Path('/selected/python'), module, receipt, path)
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][0], 'submission-observation')
            self.assertEqual(calls[0][1][0], Path('/selected/python'))
            self.assertIn(module, calls[0][1])
            self.assertFalse(result['normal_image_acceptance'])
            self.assertFalse(result['public_run_acceptance'])
            self.assertEqual(json.loads((path / 'submission-observation.json').read_text()), result)
            self.assertFalse((path / 'acceptance.json').exists())

    def test_changed_original_refuses_before_any_consumer(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            module, receipt, _ = self.original(path)
            module.write_bytes(b'changed artifact')
            with self.assertRaisesRegex(ValueError, 'original Core'), patch.object(
                    ci.subprocess, 'run', side_effect=AssertionError('Unexpected consumer')):
                ci.accept_submission_observation(
                    lambda *args, **kwargs: self.fail('Consumer started'), Path('/python'), module, receipt, path)
            self.assertFalse((path / 'submission-observation.json').exists())

    def test_incomplete_or_foreign_result_never_issues_component_receipt(self):
        for fields in ({'success': False}, {'module_sha256': 'b' * 64}, {'cases': []},
                       {'cases': ['same'] * 6}, {'fuel_refills': 1}, {'fuel_refills': False},
                       {'initial_diagnostic_fuel': True}):
            with self.subTest(fields=fields), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp)
                module, receipt, observed = self.original(path)
                with self.assertRaisesRegex(ValueError, 'Incomplete original'):
                    ci.accept_submission_observation(
                        lambda *args, **kwargs: json.dumps({**observed, **fields}).encode(),
                        Path('/python'), module, receipt, path)
                self.assertFalse((path / 'submission-observation.json').exists())

    def test_original_consumer_failure_is_not_replaced_or_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            module, receipt, _ = self.original(path)
            original = RuntimeError('original fixture failure')
            def run(*args, **kwargs):
                raise original
            with self.assertRaises(RuntimeError) as caught:
                ci.accept_submission_observation(run, Path('/python'), module, receipt, path)
            self.assertIs(caught.exception, original)
            self.assertFalse((path / 'submission-observation.json').exists())


class MixedTaskDriveTraceTests(unittest.TestCase):
    def test_closed_flushed_markers_contain_only_phase_and_elapsed_time(self):
        trace_module = load('ci_mixed_task_trace', SCRIPTS / 'fixtures/python_local_task_drive_trace.py')
        class Stream(io.StringIO):
            flushes = 0
            def flush(self):
                self.flushes += 1
        stream = Stream()
        clock = iter([10.0, 10.125, 11.5])
        trace = trace_module.MixedTaskDriveTrace(stream=stream, clock=clock.__next__)
        trace.mark('fixture-start')
        trace.mark('first-core-begin')
        self.assertEqual([json.loads(line) for line in stream.getvalue().splitlines()], [
            {'stage': 'task-drive-phase', 'phase': 'fixture-start', 'elapsed_seconds': 0.125},
            {'stage': 'task-drive-phase', 'phase': 'first-core-begin', 'elapsed_seconds': 1.5}])
        self.assertEqual(stream.flushes, 2)
        for invalid in ('unknown-private-label', 'fixture-start'):
            with self.assertRaises(ValueError):
                trace.mark(invalid)
        self.assertEqual(stream.flushes, 2)

    def test_reporting_failure_does_not_replace_original_case_or_cleanup(self):
        trace_module = load('ci_mixed_task_reporting', SCRIPTS / 'fixtures/python_local_task_drive_trace.py')
        class ReportingFailure(OSError):
            def __str__(self):
                raise AssertionError('Reporting failure must not be formatted')
        class BrokenStream:
            def write(self, _wire):
                raise ReportingFailure()
        trace = trace_module.MixedTaskDriveTrace(stream=BrokenStream())
        trace.mark('first-cleanup-begin')
        trace.mark('first-cleanup-returned')


class PublicLifecycleTests(unittest.TestCase):
    def original(self, path):
        return SubmissionObservationTests().original(path)[:2]

    def observation(self, name, module):
        cases = {
            'cancellation-saved': 'public_default_cancel_separate_process_saved_without_reprepare',
            'cancellation-precommit': 'public_cancel_before_original_publication_commit_refuses_write_and_retires_same_work',
            'state-unknown': 'public_state_commit_reply_loss_original_readback_without_rewrite',
            'state-partial-close': 'public_state_partial_input_close_same_original_retirement',
            'succeeded-result-saved': 'public_succeeded_execute_typed_result_same_saved_and_close',
            'publication-unknown': 'public_commit_reply_loss_original_lookup_same_result_without_reexecution',
            'task-drive-mixed': 'public_core_derived_task_drive_mixed_quanta_joined_result_same_saved',
            'cancellation-drive-start': 'public_cancel_between_derived_drives_before_first_input_feed',
        }
        return {'success': True, 'actualCases': 1, 'case': cases[name],
                'module_sha256': hashlib.sha256(module.read_bytes()).hexdigest(),
                **({'atomic_precommit_writer_exclusion': True} if name in ('succeeded-result-saved', 'publication-unknown', 'task-drive-mixed') else {}),
                **({'core_owned_lifecycle': True, 'initial_quantum': 1, 'initial_drives_per_task': 8, 'continuation_quantum': 256, 'original_tasks': 2, 'actual_initial_quantum_drives': 16, 'observed_phase_transitions': 2, 'monotonic_progress': True} if name == 'task-drive-mixed' else {}),
                **({'commit_reply_loss_readback_without_reexecution': True} if name == 'publication-unknown' else {})}

    def test_same_original_controls_without_build_or_installed_claim(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            module, receipt = self.original(path)
            calls = []
            def run(name, args, **options):
                self.assertEqual(args[0], Path('/selected/python'))
                self.assertEqual(args[2], module)
                self.assertEqual(options, {'timeout': 120 if name == 'cancellation-drive-start' else 300})
                calls.append((name, args))
                return json.dumps(self.observation(name, module)).encode()
            result = ci.accept_public_lifecycle(run, Path('/selected/python'), module, receipt, path)
            self.assertEqual([name for name, _ in calls],
                ['cancellation-saved', 'cancellation-precommit', 'state-unknown', 'state-partial-close',
                 'succeeded-result-saved', 'publication-unknown', 'task-drive-mixed', 'cancellation-drive-start'])
            self.assertEqual([args[-1] for _, args in calls[:4]],
                ['process-state', 'precommit-state', 'fault-state', 'partial-state'])
            by_name = dict(calls)
            self.assertEqual(by_name['publication-unknown'][-1], 'commit-unknown')
            self.assertEqual(by_name['task-drive-mixed'][-1], 'task-drive-mixed')
            self.assertEqual(by_name['cancellation-drive-start'][-1], 'drive-start-state')
            self.assertEqual(len({args[3] for _, args in calls}), len(calls))
            self.assertFalse(result['installed_wheel_acceptance'])
            self.assertFalse(result['normal_image_acceptance'])
            self.assertEqual(json.loads((path / 'public-lifecycle.json').read_text()), result)
            self.assertFalse((path / 'acceptance.json').exists())

    def test_changed_or_missing_component_refuses_without_receipt_or_next_control(self):
        for change in ({'success': False}, {'actualCases': 0}, {'actualCases': True},
                       {'module_sha256': 'b' * 64}, {'case': 'unrelated'}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp)
                module, receipt = self.original(path)
                calls = []
                def run(name, args, **options):
                    calls.append(name)
                    return json.dumps({**self.observation(name, module), **change}).encode()
                with self.assertRaisesRegex(ValueError, 'Incomplete original'):
                    ci.accept_public_lifecycle(run, Path('/python'), module, receipt, path)
                self.assertEqual(calls, ['cancellation-saved'])
                self.assertFalse((path / 'public-lifecycle.json').exists())
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            module, receipt = self.original(path)
            def missing_atomic(name, args, **options):
                observed = self.observation(name, module)
                observed.pop('atomic_precommit_writer_exclusion', None)
                return json.dumps(observed).encode()
            with self.assertRaisesRegex(ValueError, 'Incomplete original atomic'):
                ci.accept_public_lifecycle(missing_atomic, Path('/python'), module, receipt, path)
            self.assertFalse((path / 'public-lifecycle.json').exists())
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            module, receipt = self.original(path)
            def missing_recovery(name, args, **options):
                observed = self.observation(name, module)
                observed.pop('commit_reply_loss_readback_without_reexecution', None)
                return json.dumps(observed).encode()
            with self.assertRaisesRegex(ValueError, 'Incomplete original publication recovery'):
                ci.accept_public_lifecycle(missing_recovery, Path('/python'), module, receipt, path)
            self.assertFalse((path / 'public-lifecycle.json').exists())

    def test_task_drive_requires_bounded_original_task_facts_before_next_control(self):
        for change in ({'core_owned_lifecycle': False}, {'initial_quantum': True}, {'initial_quantum': 2}, {'initial_drives_per_task': 7}, {'continuation_quantum': 128}, {'actual_initial_quantum_drives': 15}, {'observed_phase_transitions': 1}, {'monotonic_progress': False},
                       {'original_tasks': True}, {'original_tasks': 1}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp)
                module, receipt = self.original(path)
                calls = []
                def run(name, args, **options):
                    calls.append(name)
                    observed = self.observation(name, module)
                    return json.dumps({**observed, **change} if name == 'task-drive-mixed' else observed).encode()
                with self.assertRaisesRegex(ValueError, 'Incomplete original task-drive'):
                    ci.accept_public_lifecycle(run, Path('/python'), module, receipt, path)
                self.assertEqual(calls[-1], 'task-drive-mixed')
                self.assertNotIn('cancellation-drive-start', calls)
                self.assertFalse((path / 'public-lifecycle.json').exists())

    def test_original_module_and_failure_cannot_be_substituted(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            module, receipt = self.original(path)
            original = RuntimeError('original public lifecycle failure')
            def failed(*args, **kwargs):
                raise original
            with self.assertRaises(RuntimeError) as caught:
                ci.accept_public_lifecycle(failed, Path('/python'), module, receipt, path)
            self.assertIs(caught.exception, original)
            module.write_bytes(b'changed original')
            with self.assertRaisesRegex(ValueError, 'original Core'):
                ci.accept_public_lifecycle(
                    lambda *args, **kwargs: self.fail('Changed Core reached consumer'),
                    Path('/python'), module, receipt, path)
            self.assertFalse((path / 'public-lifecycle.json').exists())


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


class ClosedTaskDriveControlTests(unittest.TestCase):
    """Observer service ports only; real compiled-Core proof belongs to CI."""

    def configured_control(self):
        from types import SimpleNamespace
        sdk = SCRIPTS.parent / 'packages/python-sdk/src'
        sys.path.insert(0, str(sdk))
        try:
            from actql_sdk._local_host_binding import _InvocationObservation
        finally:
            sys.path.remove(str(sdk))
        module = load('closed_task_control', SCRIPTS / 'fixtures/python-product-installed.py')
        self.assertIsNone(module.sys.getprofile())
        self.assertIsNone(module.threading.getprofile())
        control = object.__new__(module._ClosedTaskDriveObservation)
        class FunctionPort:
            def __call__(self):
                return 1
        class CorePort:
            def drive_task(self):
                return function()
            def _call(self):
                raise AssertionError('Observer cannot call a Core entrance')
        function, core, run = FunctionPort(), CorePort(), object()
        function._func = object()
        work = SimpleNamespace(_owner=run)
        matches = []
        receipt = SimpleNamespace(_matches=lambda *a, **k: matches.append((a, k)) or True)
        core._closed_wasm_exports = receipt
        core._invocation_observation = object.__new__(_InvocationObservation)
        core._invocation_observation.wasm_export = (receipt, 'actql_task_drive', function, function._func)
        core._host_retained_work = (work, object(), 1)
        control.host = SimpleNamespace(_physical_work=[work], _run_rows=[(run, object())])
        control.core, control.receipt, control.export = core, receipt, function
        control.work_type = SimpleNamespace
        control.span_type = _InvocationObservation
        control.drive_method, control.call_method = CorePort.drive_task, CorePort._call
        control.drive_code, control.export_code = CorePort.drive_task.__code__, FunctionPort.__call__.__code__
        control.counts, control.valid, control.failure, control.restored = [0] * 5, True, None, False
        control.refusal_bits = 0
        control.span_refusal_bits = 0
        control.profile = control._profile
        control.previous = (None, None)
        return module, control, core, matches

    def test_worker_thread_calls_are_observed_without_replacing_methods_and_both_profiles_restore(self):
        module, control, core, matches = self.configured_control()
        original = type(core).drive_task
        with control:
            worker = module.threading.Thread(target=core.drive_task)
            worker.start()
            worker.join(2)
            self.assertFalse(worker.is_alive())
            # Runtime validation is forbidden inside the callback; it runs only
            # when this explicit control returns its observer custody.
            self.assertEqual(matches, [])
        self.assertEqual(control.counts, [1] * 5)
        self.assertIs(type(core).drive_task, original)
        self.assertEqual(len(matches), 1)
        self.assertIsNone(module.sys.getprofile())
        self.assertIsNone(module.threading.getprofile())
        self.assertIsNone(control.host)
        self.assertIsNone(control.core)
        self.assertIsNone(control.receipt)
        self.assertIsNone(control.export)
        result = control.result()
        ci.require_closed_task_drive({'closed_task_drive': result})

    def test_observer_refusal_preserves_primary_and_restores_both_profiles(self):
        module, control, core, _ = self.configured_control()
        class Primary(RuntimeError):
            def __str__(self):
                raise AssertionError('No primary formatting in observer cleanup')
        original = Primary()
        core._invocation_observation = object.__new__(control.span_type)
        with self.assertRaises(Primary) as caught:
            with control:
                core.drive_task()
                raise original
        self.assertIs(caught.exception, original)
        self.assertFalse(control.valid)
        self.assertIsNotNone(control.failure)
        self.assertIsNone(module.sys.getprofile())
        self.assertIsNone(module.threading.getprofile())
        with self.assertRaisesRegex(AssertionError, 'unqualified'):
            control.result()

    def test_unqualified_observer_reports_bounded_counts_and_missing_span_without_private_data(self):
        _, control, core, _ = self.configured_control()
        core._invocation_observation = None
        with control:
            core.drive_task()
        with self.assertRaises(AssertionError) as caught:
            control.result()
        prefix = 'Closed task drive observation is unqualified: '
        self.assertTrue(str(caught.exception).startswith(prefix))
        witness = json.loads(str(caught.exception)[len(prefix):])
        self.assertEqual(witness, {
            'stage': 'closed-task-drive-refusal', 'counts': [1, 1, 1, 1, 0],
            'valid': False, 'profilers_restored': True,
            'failure_present': False, 'refusal_bits': 3,
            'span_refusal_bits': 1,
        })
        self.assertLess(len(str(caught.exception)), 512)
        self.assertIsNone(control.host)
        self.assertIsNone(control.core)

    def test_unqualified_original_span_is_distinct_from_an_absent_span_and_still_refuses(self):
        _, control, core, _ = self.configured_control()
        core._invocation_observation.wasm_export = None
        with control:
            core.drive_task()
        with self.assertRaises(AssertionError) as caught:
            control.result()
        witness = json.loads(str(caught.exception).split(': ', 1)[1])
        self.assertEqual(witness['counts'], [1, 1, 1, 1, 0])
        self.assertEqual(witness['refusal_bits'], 3)
        self.assertEqual(witness['span_refusal_bits'], 2)
        self.assertFalse(witness['failure_present'])
        self.assertTrue(witness['profilers_restored'])

    def test_malformed_original_span_receipt_stays_a_closed_bounded_refusal(self):
        _, control, core, _ = self.configured_control()
        core._invocation_observation.wasm_export = ('not-a-complete-receipt',)
        with control:
            core.drive_task()
        with self.assertRaises(AssertionError) as caught:
            control.result()
        witness = json.loads(str(caught.exception).split(': ', 1)[1])
        self.assertEqual(witness['counts'], [1, 1, 1, 1, 0])
        self.assertEqual(witness['refusal_bits'], 3)
        self.assertEqual(witness['span_refusal_bits'], 4)
        self.assertLess(len(str(caught.exception)), 512)

    def test_unqualified_observer_never_formats_its_original_opaque_callback_failure(self):
        from types import SimpleNamespace
        _, control, core, _ = self.configured_control()
        class OpaqueFailure(RuntimeError):
            def __str__(self):
                raise AssertionError('No original diagnostic formatting')
        original = OpaqueFailure()
        class WorkPort:
            @property
            def _owner(self):
                raise original
        work = WorkPort()
        core._host_retained_work = (work, object(), 1)
        control.work_type = WorkPort
        control.host = SimpleNamespace(_physical_work=[work], _run_rows=[(object(), object())])
        with control:
            core.drive_task()
        self.assertIs(control.failure, original)
        with self.assertRaises(AssertionError) as caught:
            control.result()
        prefix = 'Closed task drive observation is unqualified: '
        self.assertTrue(str(caught.exception).startswith(prefix))
        witness = json.loads(str(caught.exception)[len(prefix):])
        self.assertEqual(witness['counts'], [1, 1, 1, 1, 0])
        self.assertTrue(witness['failure_present'])
        self.assertEqual(witness['refusal_bits'], 32)
        self.assertLess(len(str(caught.exception)), 512)
        self.assertNotIn('OpaqueFailure', str(caught.exception))
        self.assertIs(control.failure, original)

    def test_restore_failure_attempts_both_and_never_replaces_primary(self):
        module, control, _, _ = self.configured_control()
        original = RuntimeError('original operation failure')
        cleanup = OSError('profiler restore failed')
        with patch.object(module.sys, 'setprofile', side_effect=[None, cleanup]) as main, \
                patch.object(module.threading, 'setprofile') as threads:
            with self.assertRaises(RuntimeError) as caught:
                with control:
                    raise original
        self.assertIs(caught.exception, original)
        self.assertEqual(main.call_args_list, [unittest.mock.call(control.profile), unittest.mock.call(None)])
        self.assertEqual(threads.call_args_list, [unittest.mock.call(control.profile), unittest.mock.call(None)])
        self.assertIs(control.failure, cleanup)
        with self.assertRaisesRegex(AssertionError, 'unqualified'):
            control.result()

    def test_missing_holder_or_bounded_counter_overflow_cannot_qualify(self):
        for missing in (True, False):
            module, control, core, _ = self.configured_control()
            if missing:
                control.host._run_rows.clear()
            else:
                control.counts = [1024] * 5
            with control:
                core.drive_task()
            self.assertTrue(all(count <= 1025 for count in control.counts))
            self.assertIsNone(module.sys.getprofile())
            self.assertIsNone(module.threading.getprofile())
            with self.assertRaisesRegex(AssertionError, 'unqualified'):
                control.result()

    def test_parent_rejects_missing_mismatched_boolean_and_unobserved_claims(self):
        original = {'actual_closed_task_drive': True, 'drive_calls': 2, 'drive_returns': 2,
                    'wasm_entries': 2, 'wasm_returns': 2, 'retained_holder_checks': 2,
                    'methods_unchanged': True, 'profilers_restored': True,
                    'per_drive_fuel_observed': False, 'hash_count_observed': False}
        ci.require_closed_task_drive({'closed_task_drive': original})
        for witness in (None, {}, original | {'drive_calls': True}, original | {'drive_calls': 0},
                        original | {'drive_calls': 1025}, original | {'wasm_returns': 1},
                        original | {'retained_holder_checks': 1}, original | {'methods_unchanged': False},
                        original | {'profilers_restored': False}, original | {'hash_count_observed': True},
                        original | {'per_drive_fuel_observed': True}):
            with self.assertRaises(ValueError):
                ci.require_closed_task_drive({'closed_task_drive': witness})

    def test_preexisting_profiler_and_changed_method_identity_cannot_qualify(self):
        from types import MethodType
        module, control, _, _ = self.configured_control()
        existing = lambda *args: None
        control.previous = (existing, existing)
        with patch.object(module.sys, 'setprofile') as main, \
                patch.object(module.threading, 'setprofile') as threads:
            with self.assertRaisesRegex(AssertionError, 'another profiler'):
                control.__enter__()
        main.assert_not_called()
        threads.assert_not_called()
        module, control, core, _ = self.configured_control()
        control.counts = [1] * 5  # Independent already-complete observer DATA.
        def changed(self):
            raise AssertionError('Changed method must never be called')
        with control:
            core.drive_task = MethodType(changed, core)
        self.assertIsNone(module.sys.getprofile())
        self.assertIsNone(module.threading.getprofile())
        with self.assertRaisesRegex(AssertionError, 'unqualified'):
            control.result()


class FailureLocationTests(unittest.TestCase):
    def rejected_wait_fixture(self, *, completed=True, same_reference=True, task_drive_code=None):
        import asyncio
        (_, host, work, original, cleanup, exited,
         invoked) = self.local_work_fixture(completed=completed, task_drive_code=task_drive_code)
        from actql_sdk._async import AsyncClient, AsyncExecution, wire
        from actql_sdk import ClientError

        reference = {'namespaceId': 'private-reference-secret' if same_reference else 'foreign'}
        state = {'version': 'actql-run-state/0.1', 'run_id': 'original-run',
                 'revision': 7, 'status': 'running',
                 'updated_at': '2026-10-16T10:00:00.000Z',
                 'next_action': {'kind': 'none'}, 'result_available': False,
                 'result_availability': {},
                 'control': {'revision': 2, 'cancellation_requested': False,
                             'physical_stop': 'unknown'}}
        self.assertTrue(wire.valid(state, 'run_state'))
        self.assertFalse(wire.valid_run_wait(state, None))

        async def observe():
            client = AsyncClient._from_local_host(host)
            execution = AsyncExecution(client, {'ref': reference})
            # Only this Source/port control injects a response. The installed
            # diagnostic never replaces a Client, Host or runtime method.
            with patch.object(client, '_request', new=AsyncMock(return_value=state)) as request:
                try:
                    await execution.wait()
                except ClientError as failure:
                    self.assertEqual(failure.code, 'InvalidHostRunState')
                    request.assert_awaited_once_with('wait', {'ref': reference, 'until': None, 'since': None})
                    return failure, execution
            self.fail('A running state cannot satisfy the existing wait contract')

        failure, execution = asyncio.run(observe())
        return failure, host, work, original, cleanup, exited, invoked, execution

    def test_rejected_wait_reports_same_completed_original_without_private_values(self):
        diagnostics = load('ci_rejected_wait_original', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, host, work, original, cleanup, exited, invoked, _ = self.rejected_wait_fixture()
        future = work._future
        stream = io.StringIO()
        diagnostics.report_contexts(failure, stream)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        selected = next(record['local_work'] for record in records if 'local_work' in record)
        self.assertTrue(selected['selected'])
        self.assertTrue(selected['future_done'])
        self.assertTrue(selected['rejected_wait'])
        self.assertTrue(selected['wait_status_known'])
        self.assertFalse(selected['wait_status_stable'])
        self.assertEqual([record.get('failure_role') for record in records[1:]],
                         ['physical-original', 'physical-cleanup', 'physical-exit'])
        self.assertIs(work._future, future)
        self.assertIs(future.exception(timeout=0), original)
        self.assertIs(work._cleanup_error, cleanup)
        self.assertIs(work._exit_error, exited)
        self.assertIs(host._physical_work[0], work)
        self.assertEqual(invoked, [work._owner])
        self.assertNotIn('private-reference-secret', stream.getvalue())
        self.assertNotIn('original-run', stream.getvalue())

    def test_rejected_wait_pending_work_is_not_waited_or_invoked(self):
        diagnostics = load('ci_rejected_wait_pending', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, _, work, _, _, _, invoked, _ = self.rejected_wait_fixture(completed=False)
        selected, errors = diagnostics.selected_local_work(failure)
        self.assertTrue(selected['selected'])
        self.assertFalse(selected['future_done'])
        self.assertEqual(errors, [])
        self.assertEqual(invoked, [])
        self.assertFalse(work._future.done())

    def test_rejected_wait_foreign_run_does_not_reveal_physical_failure(self):
        diagnostics = load('ci_rejected_wait_foreign_run', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, _, work, original, _, _, invoked, _ = self.rejected_wait_fixture(same_reference=False)
        selected = diagnostics.selected_local_work(failure)
        if selected is not None:
            self.assertFalse(selected[0]['selected'])
            self.assertEqual(selected[1], [])
        self.assertIs(work._future.exception(timeout=0), original)
        self.assertEqual(invoked, [work._owner])

    def test_rejected_wait_foreign_client_cannot_invoke_callbacks(self):
        diagnostics = load('ci_rejected_wait_foreign_client', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, _, _, _, _, _, _, execution = self.rejected_wait_fixture()
        accessed = []
        class ForeignClient:
            def __getattribute__(self, name):
                accessed.append(name)
                raise AssertionError('A diagnostic cannot inspect a foreign Client')
        execution._client = ForeignClient()
        self.assertIsNone(diagnostics.selected_local_work(failure))
        self.assertEqual(accessed, [])

    def test_rejected_wait_reports_original_task_drive_status_without_outcome(self):
        diagnostics = load('ci_rejected_wait_drive_status', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, _, work, original, _, _, invoked, _ = self.rejected_wait_fixture(task_drive_code=-35)
        stream = io.StringIO()
        diagnostics.report_contexts(failure, stream)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        physical = next(record for record in records if record.get('failure_role') == 'physical-original')
        self.assertEqual(physical['exception_type'], 'LocalCoreError')
        self.assertEqual(physical['core_task_drive_code'], -35)
        self.assertNotIn('core_buffer_seal_code', physical)
        self.assertNotIn('outcome', physical)
        self.assertIs(work._future.exception(timeout=0), original)
        self.assertEqual((original.operation, original.code), ('task_drive', -35))
        self.assertEqual(invoked, [work._owner])
        self.assertNotIn('private-reference-secret', stream.getvalue())

    def local_work_fixture(self, *, completed=True, same_reference=True, operation='status', task_drive_code=None):
        import asyncio
        sdk = SCRIPTS.parent / 'packages/python-sdk/src'
        sys.path.insert(0, str(sdk))
        try:
            from actql_sdk._local_core import LocalCore, LocalCoreError, _Input, _PhysicalInput
            from actql_sdk._local_product import InstalledLocalHost, _OriginalRunReference
            from actql_sdk._local_work import OriginalLocalWork
        finally:
            sys.path.remove(str(sdk))

        class OpaqueOriginalError(RuntimeError):
            def __str__(self):
                raise AssertionError('Never format the retained physical cause')

        original = (OpaqueOriginalError() if task_drive_code is None
                    else LocalCoreError('task_drive', task_drive_code))
        cleanup, exited = OpaqueOriginalError(), OpaqueOriginalError()
        core = object.__new__(LocalCore)
        core._identity, core._closing = object(), True
        reference = {'namespaceId': 'private-reference-secret'}
        raw = json.dumps(reference).encode()
        source = _Input(core._identity, 1, 1, len(raw))
        core._inputs = {1: _PhysicalInput(raw, lambda: False, lambda _: False)}
        owner = object()
        invoked = []
        def invoke():
            invoked.append(owner)
            raise original
        work = OriginalLocalWork(invoke, owner=owner)
        if completed:
            work.start()
            work._thread.join(2)
            self.assertFalse(work._thread.is_alive())
            self.assertIs(work._future.exception(timeout=0), original)
        work._cleanup_error, work._exit_error = cleanup, exited
        host = object.__new__(InstalledLocalHost)
        host._original, host._core = host, core
        host._closing, host._installation = False, object()
        host._public_run_references = [_OriginalRunReference(owner, source)]
        host._physical_work = [work]
        payload = json.dumps({'ref': reference if same_reference else {'namespaceId': 'foreign'}}).encode()
        try:
            asyncio.run(host.open(operation, payload))
        except ValueError as failure:
            return failure, host, work, original, cleanup, exited, invoked
        self.fail('Expected the actual Host availability fence')

    def test_selected_completed_work_reports_same_opaque_original_and_separate_cleanup_exit(self):
        diagnostics = load('ci_selected_completed_work', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, host, work, original, cleanup, exited, invoked = self.local_work_fixture()
        before = work._future
        stream = io.StringIO()
        diagnostics.report_contexts(failure, stream)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        selected = next(record['local_work'] for record in records if 'local_work' in record)
        self.assertEqual(selected, {'observed_after_consumer_failure': True,
                                   'host_closing': False, 'core_closing': True,
                                   'installation_present': True, 'selected': True, 'future_done': True})
        self.assertEqual([record.get('failure_role') for record in records[1:]],
                         ['physical-original', 'physical-cleanup', 'physical-exit'])
        self.assertEqual(invoked, [work._owner])
        self.assertIs(work._future, before)
        self.assertIs(before.exception(timeout=0), original)
        self.assertIs(work._cleanup_error, cleanup)
        self.assertIs(work._exit_error, exited)
        self.assertIs(host._physical_work[0], work)
        self.assertNotIn('private-reference-secret', stream.getvalue())

    def test_pending_selected_work_is_not_waited_or_invoked(self):
        diagnostics = load('ci_selected_pending_work', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, _, work, _, _, _, invoked = self.local_work_fixture(completed=False)
        stream = io.StringIO()
        diagnostics.report_contexts(failure, stream)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]['local_work']['future_done'], False)
        self.assertEqual(invoked, [])
        self.assertFalse(work._future.done())
        self.assertFalse(work._invoked)

    def test_other_run_failure_is_not_reported_as_selected_work(self):
        diagnostics = load('ci_foreign_selected_work', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, _, _, _, _, _, _ = self.local_work_fixture(same_reference=False)
        stream = io.StringIO()
        diagnostics.report_contexts(failure, stream)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        self.assertEqual(len(records), 1)
        self.assertFalse(records[0]['local_work']['selected'])
        self.assertNotIn('failure_role', records[0])

    def test_diagnostic_history_bound_and_invalid_snapshot_keep_original_chain(self):
        diagnostics = load('ci_selected_work_bounds', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, host, work, _, _, _, invoked = self.local_work_fixture()
        for invalid in ([work] * (diagnostics.MAX_WORK_RECORDS + 1), object()):
            host._physical_work = invalid
            stream = io.StringIO()
            diagnostics.report_contexts(failure, stream)
            records = [json.loads(line) for line in stream.getvalue().splitlines()]
            self.assertEqual(len(records), 1)
            self.assertFalse(records[0]['local_work']['selected'])
            self.assertIsNone(failure.__cause__)
        self.assertEqual(len(invoked), 1)

    def test_foreign_operation_diagnostic_cannot_invoke_equality(self):
        diagnostics = load('ci_selected_work_foreign_operation', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        class ForeignOperation:
            def __eq__(self, other):
                raise AssertionError('Diagnostic cannot invoke foreign operation equality')
        failure, _, _, _, _, _, _ = self.local_work_fixture(operation=ForeignOperation())
        stream = io.StringIO()
        diagnostics.report_contexts(failure, stream)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        self.assertEqual(len(records), 1)
        self.assertNotIn('local_work', records[0])

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


class InstalledCancellationTests(unittest.TestCase):
    """Receipt and command harness checks, never installed runtime acceptance."""

    @classmethod
    def setUpClass(cls):
        cls.consumer = load('installed_cancellation_harness', SCRIPTS / 'fixtures/python-product-installed.py')

    def original(self):
        reference = {'namespaceId': 'harness', 'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'b' * 64}
        cancellation = {'ref': reference, 'kind': 'accepted', 'revision': 8,
                        'cancelRef': reference | {'cancelId': 'original-cancel', 'expectedRevision': 7}}
        terminal = {'version': 1, 'run_id': 'original-run', 'status': 'cancelled',
                    'result_available': False, 'control': {'revision': 8,
                    'cancellation_requested': True, 'physical_stop': 'unknown'}}
        return reference, cancellation, terminal

    def test_original_active_revision_cancel_and_lookup_remain_correlated(self):
        reference, cancellation, _ = self.original()
        self.assertEqual(self.consumer._active_revision({'status': 'running',
            'control': {'revision': 7, 'cancellation_requested': False}}), ('running', 7))
        accepted = self.consumer._accepted_cancellation({'kind': 'accepted',
            'cancellation': cancellation}, reference)
        self.assertEqual(accepted, cancellation)
        self.consumer._same_cancellation_lookup({'kind': 'found', 'cancellation': cancellation}, accepted)
        foreign = dict(cancellation['cancelRef'], cancelId='another-cancel')
        with self.assertRaises(AssertionError):
            self.consumer._same_cancellation_lookup({'kind': 'found',
                'cancellation': cancellation | {'cancelRef': foreign}}, accepted)

    def test_missed_active_window_or_foreign_control_cannot_count_as_coverage(self):
        reference, cancellation, _ = self.original()
        with self.assertRaises(self.consumer.ActiveCancellationCoverageUnavailable):
            self.consumer._active_revision({'status': 'succeeded'})
        with self.assertRaises(self.consumer.ActiveCancellationCoverageUnavailable):
            self.consumer._accepted_cancellation({'kind': 'already_satisfied',
                'cancellation': cancellation | {'kind': 'already_terminal'}}, reference)
        for revision in (True, -1, 2147483648):
            with self.subTest(revision=revision), self.assertRaises(AssertionError):
                self.consumer._active_revision({'status': 'running',
                    'control': {'revision': revision, 'cancellation_requested': False}})
        for changed in (cancellation | {'ref': reference | {'namespaceId': 'foreign'}},
                        cancellation | {'revision': 7},
                        cancellation | {'cancelRef': cancellation['cancelRef'] | {'expectedRevision': True}}):
            with self.subTest(changed=changed), self.assertRaises(AssertionError):
                self.consumer._cancellation_payload(changed, reference)

    def test_saved_status_preserves_original_control_without_inventing_physical_ack(self):
        _, _, terminal = self.original()
        saved = {'terminal': terminal}
        self.assertEqual(self.consumer._same_saved_cancelled(terminal, saved), terminal)
        confirmed = terminal | {'control': terminal['control'] | {'physical_stop': 'confirmed'}}
        self.assertEqual(self.consumer._same_saved_cancelled(confirmed, saved), confirmed)
        for changed in (terminal | {'status': 'succeeded'},
                        terminal | {'run_id': 'replacement'},
                        terminal | {'control': terminal['control'] | {'revision': 9}},
                        terminal | {'control': terminal['control'] | {'physical_stop': 'assumed'}}):
            with self.subTest(changed=changed), self.assertRaises(AssertionError):
                self.consumer._same_saved_cancelled(changed, saved)
        with self.assertRaises(AssertionError):
            self.consumer._same_saved_cancelled(terminal, {'terminal': confirmed})

    def test_private_cancel_receipt_is_read_by_an_actual_different_python_process(self):
        import subprocess
        reference, cancellation, terminal = self.original()
        body = {'version': '0.0.0.dev0', 'facade': 'sync', 'submission': {'harness': 'submission'},
                'run': reference, 'details': {'case': 'cancellation', 'initial_status': 'running',
                                            'cancellation': cancellation, 'terminal': terminal}}
        program = ('import importlib.util,json,sys; from pathlib import Path; '
                   's=importlib.util.spec_from_file_location("fixture",sys.argv[1]); '
                   'm=importlib.util.module_from_spec(s);s.loader.exec_module(m); '
                   'm._record(Path(sys.argv[2]),**json.loads(sys.argv[3]))')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'original.json'
            child = subprocess.run([sys.executable, '-I', '-B', '-c', program,
                str(SCRIPTS / 'fixtures/python-product-installed.py'), str(path), json.dumps(body)],
                capture_output=True, text=True, timeout=5)
            self.assertEqual(child.returncode, 0, child.stderr)
            captured = path.read_bytes()
            saved = self.consumer._cancel_saved(path, body['version'], 'sync')
            self.assertNotEqual(saved['producer_pid'], self.consumer.os.getpid())
            self.assertEqual(saved['run'], reference)
            self.assertEqual(saved['cancellation'], cancellation)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            for version, facade in (('different', 'sync'), (body['version'], 'async')):
                with self.subTest(version=version, facade=facade), self.assertRaises(AssertionError):
                    self.consumer._cancel_saved(path, version, facade)
            invalid = (saved | {'producer_pid': self.consumer.os.getpid()}, saved | {'extra': True})
            for changed in invalid:
                path.write_text(json.dumps(changed))
                with self.assertRaises(AssertionError):
                    self.consumer._cancel_saved(path, body['version'], 'sync')
            path.write_bytes(captured[:-2] + b',"version":"duplicate"}\n')
            with self.assertRaisesRegex(AssertionError, 'Duplicate'):
                self.consumer._cancel_saved(path, body['version'], 'sync')
            path.write_bytes(captured)
            path.chmod(0o644)
            with self.assertRaisesRegex(AssertionError, 'private'):
                self.consumer._cancel_saved(path, body['version'], 'sync')

    def test_receipt_writer_cannot_replace_originals_or_reuse_a_receipt(self):
        reference, _, _ = self.original()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'original.json'
            args = {'version': '0.0.0.dev0', 'facade': 'sync', 'submission': {}, 'run': reference}
            with self.assertRaises(AssertionError):
                self.consumer._record(path, **args, details={'run': {}})
            self.assertFalse(path.exists())
            self.consumer._record(path, **args)
            self.assertEqual(set(json.loads(path.read_text())), self.consumer._RECORD_FIELDS)
            with self.assertRaises(FileExistsError):
                self.consumer._record(path, **args)
            with self.assertRaises(AssertionError):
                self.consumer._saved(path, args['version'])

    def report(self, args, pid):
        facade = args[args.index('--facade') + 1]
        phase = args[args.index('--phase') + 1]
        return {'mode': 'local', 'version': '0.0.0.dev0', 'case': 'cancellation', 'actualCases': 1,
                'facade': facade, 'phase': phase, 'pid': pid, 'reported_physical_stop': 'unknown',
                'admitted_inflight': phase == 'initial', 'original_cancel_accepted': True,
                'cancel_lookup_same': True, 'original_run_reused': phase == 'resume',
                'same_host_healthy_after_cancel': phase == 'initial',
                'saved_read_only': phase == 'resume', 'first_close': True, 'closed': True}

    def test_same_installed_consumer_has_four_fresh_bounded_phase_commands(self):
        with tempfile.TemporaryDirectory() as tmp:
            destination, consumer, env = Path(tmp), Path('/installed/bin/python'), {'PATH': '/installed/bin'}
            calls = []
            def run(name, args, **options):
                calls.append((name, args, options))
                return json.dumps(self.report(args, 100 + len(calls)))
            ci.accept_installed_cancellation(run, consumer, destination, '0.0.0.dev0', env)
            self.assertEqual([name for name, _, _ in calls], [f'{facade}-cancellation-{phase}'
                for facade in ('sync', 'async') for phase in ('initial', 'resume')])
            for index, (_, args, options) in enumerate(calls):
                facade, phase = ('sync' if index < 2 else 'async'), ('initial' if index % 2 == 0 else 'resume')
                work = destination / (facade + '-cancellation')
                self.assertEqual(args[:5], [consumer, '-I', '-B',
                    destination / 'ci-python-installed-run.py', destination / 'python-product-installed.py'])
                self.assertEqual(args[args.index('--case') + 1], 'cancellation')
                self.assertEqual(args[args.index('--phase') + 1], phase)
                self.assertEqual(args[-2:], ['--receipt', work / 'original.json'])
                self.assertEqual(options, {'cwd': work, 'env': env, 'timeout': 180})
                self.assertIs(options['env'], env)

    def test_incomplete_control_close_or_process_report_stops_without_retry(self):
        for field, value in (('actualCases', True), ('admitted_inflight', False),
                             ('cancel_lookup_same', False), ('first_close', False),
                             ('closed', False), ('reported_physical_stop', 'assumed')):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as tmp:
                calls = []
                def run(name, args, **options):
                    calls.append(name)
                    return json.dumps(self.report(args, 100) | {field: value})
                with self.assertRaises(ValueError):
                    ci.accept_installed_cancellation(run, Path('/python'), Path(tmp), '0.0.0.dev0', {})
                self.assertEqual(calls, ['sync-cancellation-initial'])
        with tempfile.TemporaryDirectory() as tmp:
            calls = []
            def repeated_process(name, args, **options):
                calls.append(name)
                return json.dumps(self.report(args, 100))
            with self.assertRaises(ValueError):
                ci.accept_installed_cancellation(repeated_process, Path('/python'), Path(tmp), '0.0.0.dev0', {})
            self.assertEqual(calls, ['sync-cancellation-initial', 'sync-cancellation-resume'])

    def test_original_consumer_failure_stays_primary_and_is_not_retried(self):
        original = RuntimeError('explicit command-port failure')
        with tempfile.TemporaryDirectory() as tmp:
            calls = []
            def failed(name, args, **options):
                calls.append(name)
                raise original
            with self.assertRaises(RuntimeError) as observed:
                ci.accept_installed_cancellation(failed, Path('/python'), Path(tmp), '0.0.0.dev0', {})
            self.assertIs(observed.exception, original)
            self.assertEqual(calls, ['sync-cancellation-initial'])


if __name__ == '__main__':
    unittest.main()
