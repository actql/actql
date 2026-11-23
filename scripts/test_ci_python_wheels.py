"""Harness unit tests only: these fixtures are not installed product acceptance."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
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


class InstalledNumericReductionTests(unittest.TestCase):
    def test_same_cohort_numeric_saved_requires_a_distinct_process(self):
        source, module = 'a' * 40, 'b' * 64
        cases = ['pivot', 'sum', 'count']
        consumer = Path('/consumer/python')
        env = {'ACTUAL_INSTALLED': 'yes'}
        for saved_pid in (42, 41):
            calls = []

            def run(name, args, **options):
                phase = args[-3]
                calls.append((name, phase))
                self.assertEqual(args[:3], [consumer, '-I', '-B'])
                self.assertEqual(args[-2:], [source, module])
                self.assertEqual(args[-4].read_bytes(),
                                 (ci.ROOT / 'packages/python-sdk/tests/installed_numeric_reductions.py').read_bytes())
                self.assertEqual(options, {'cwd': Path(tmp) / 'numeric-reductions', 'env': env,
                                           'timeout': 180})
                return json.dumps({'phase': phase, 'pid': 41 if phase == 'initial' else saved_pid,
                                   'source': source, 'module': module, 'cases': cases, 'first_close': True})

            with self.subTest(saved_pid=saved_pid), tempfile.TemporaryDirectory() as tmp:
                if saved_pid == 41:
                    with self.assertRaisesRegex(ValueError, 'original Saved'):
                        ci.accept_installed_numeric_reductions(run, consumer, Path(tmp), source, module, env)
                else:
                    ci.accept_installed_numeric_reductions(run, consumer, Path(tmp), source, module, env)
            self.assertEqual(calls, [('installed-linux-numeric-initial', 'initial'),
                                     ('installed-linux-numeric-saved', 'saved')])


class InstalledFuelControlTests(unittest.TestCase):
    def initial(self):
        return {'phase': 'initial', 'pid': 41, 'firstClose': True, 'replayed': False,
                'intentionalFuel': 1_000, 'defaultFuel': 64_000_000_000,
                'actualAttempts': 1, 'outOfFuel': True, 'normalFenced': True, 'sameStore': True}

    def test_original_stop_and_distinct_process_saved_are_required(self):
        ci.require_installed_fuel_fault(self.initial(), 'initial', None)
        saved = {'phase': 'resume', 'pid': 42, 'firstClose': True, 'replayed': False,
                 'sameSaved': True, 'failedAdmissionAbsent': True}
        ci.require_installed_fuel_fault(saved, 'resume', 41)
        with self.assertRaises(ValueError):
            ci.require_installed_fuel_fault(saved | {'pid': 41}, 'resume', 41)

    def test_replay_and_pending_close_cannot_report_fuel_acceptance(self):
        for changed in ({'actualAttempts': 2}, {'firstClose': False}, {'replayed': True},
                        {'sameStore': False}, {'normalFenced': False}, {'outOfFuel': False}):
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                ci.require_installed_fuel_fault(self.initial() | changed, 'initial', None)

    def test_test_budget_cannot_be_reported_as_the_product_default(self):
        with self.assertRaises(ValueError):
            ci.require_installed_fuel_fault(self.initial() | {'defaultFuel': 1_000}, 'initial', None)

    def test_same_cohort_default_case_precedes_distinct_stop_and_saved_processes(self):
        cohort = {'module_sha256': 'b' * 64, 'image_sha256': 'c' * 64}
        history = {'taskQuantumMode': 'production-original',
                   'acceptedPendingHistory': 40, 'retiredPendingParentLoans': 40,
                   'firstCloseReturned': True, 'cleanupFailures': []}
        normal = {'fuelMode': {'sourceDeclaredLimit': 64_000_000_000},
                  'installedCohort': {'sourceSha': 'a' * 40, 'moduleSha256': 'b' * 64,
                                      'imageSha256': 'c' * 64}, 'histories': [history]}
        saved = {'phase': 'resume', 'pid': 42, 'firstClose': True, 'replayed': False,
                 'sameSaved': True, 'failedAdmissionAbsent': True}
        calls = []
        def run(name, args, **options):
            calls.append((name, args, options))
            value = (normal, self.initial(), saved)[len(calls) - 1]
            return json.dumps(value)
        with tempfile.TemporaryDirectory() as tmp:
            ci.accept_installed_fuel(run, Path('/consumer/python'), Path(tmp), 'a' * 40, cohort, {'ORIGINAL': 'env'})
        self.assertEqual([name for name, _, _ in calls], ['installed-default-fuel-admission',
                         'installed-fuel-stop-initial', 'installed-fuel-stop-resume'])
        self.assertTrue(all(args[0] == Path('/consumer/python') for _, args, _ in calls))
        self.assertTrue(all(options['env'] == {'ORIGINAL': 'env'} for _, _, options in calls))
        self.assertTrue(all('--expected-default-fuel' not in args for _, args, _ in calls))
        self.assertEqual(calls[0][1][-1], 'fuel-pending:40')
        for change in ({'taskQuantumMode': 'forced-one'}, {'acceptedPendingHistory': 39},
                       {'firstCloseReturned': False}, {'cleanupFailures': ['pending']}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as tmp:
                bad = normal | {'histories': [history | change]}
                with self.assertRaises(ValueError):
                    ci.accept_installed_fuel(lambda *a, **k: json.dumps(bad), Path('/consumer/python'),
                                             Path(tmp), 'a' * 40, cohort, {})


    def test_actual_installed_entry_admits_explicit_fuel_role_before_owning_factory(self):
        import asyncio
        from types import SimpleNamespace
        history = load('ci_actual_fuel_installed_entry',
                       SCRIPTS / 'fixtures/python-local-sdk-current-history.py')
        import actql_sdk._local_product as product
        original = RuntimeError('stop at original population boundary; no runtime')
        with tempfile.TemporaryDirectory() as tmp:
            for role in ('fuel-pending:40', 'pending:40'):
                args = SimpleNamespace(argv=['fixture', '--installed', 'a' * 40, tmp, role],
                                       flags=SimpleNamespace(isolated=True))
                population = AsyncMock(wraps=history.population)
                with self.subTest(role=role), patch.object(history, 'INSTALLED_IMAGE', True), \
                        patch.object(history, 'sys', args), patch.object(history, 'population', population), \
                        patch.object(product, 'installed_local_components') as resolver, \
                        patch.object(history.InstalledLocalHost, 'installed', side_effect=original) as factory:
                    with self.assertRaises(RuntimeError) as raised:
                        asyncio.run(history.main())
                    self.assertIs(raised.exception, original)
                    population.assert_awaited_once()
                    self.assertIs(population.call_args.kwargs['production_quantum'], role == 'fuel-pending:40')
                    resolver.assert_not_called()
                    factory.assert_called_once()
                    self.assertEqual(set(factory.call_args.kwargs), {'state_dir'})
                    self.assertEqual(factory.call_args.kwargs['state_dir'].parent, Path(tmp))
            for role in ('persisted:40', '40', 'fuel-pending:41', 'foreign:40', 'fault:unknown'):
                args = SimpleNamespace(argv=['fixture', '--installed', 'a' * 40, tmp, role],
                                       flags=SimpleNamespace(isolated=True))
                with self.subTest(refused=role), patch.object(history, 'INSTALLED_IMAGE', True), \
                        patch.object(history, 'sys', args), patch.object(history, 'population', AsyncMock()) as population, \
                        patch.object(product, 'installed_local_components') as resolver:
                    with self.assertRaises((ValueError, AssertionError)):
                        asyncio.run(history.main())
                    population.assert_not_awaited()
                    resolver.assert_not_called()

    def test_default_role_forwards_original_quantum_and_retains_independent_controls(self):
        history = load('ci_fuel_quantum_trace', SCRIPTS / 'fixtures/python-local-sdk-current-history.py')
        trace, task, result, calls = history.Trace(), object(), object(), []
        def original(actual_task, quantum):
            self.assertIs(actual_task, task)
            calls.append(quantum)
            return result
        self.assertIs(trace.drive(original, task, 19), result)
        self.assertIs(trace.drive(original, task, 19, production_quantum=True), result)
        self.assertIs(trace.drive(original, task, 257, production_quantum=True), result)
        self.assertEqual(calls, [1, 19, 257])
        failure = RuntimeError('original operation failure')
        def refused(actual_task, quantum):
            calls.append(quantum)
            raise failure
        with self.assertRaises(RuntimeError) as raised:
            trace.drive(refused, task, 19, production_quantum=True)
        self.assertIs(raised.exception, failure)
        self.assertEqual(calls, [1, 19, 257, 19])


class RepeatedHostAcceptanceTests(unittest.TestCase):
    def events(self, phase, pid):
        data = [{'phase': 'opened', 'mode': phase, 'pid': pid}]
        result = 'result-complete' if phase == 'warm' else 'saved-result-complete'
        data += [{'phase': result, 'ordinal': ordinal, 'pid': pid} for ordinal in range(1, 11)]
        if phase == 'warm':
            data += [{'phase': 'checkpoint-complete', 'ordinal': ordinal, 'pid': pid,
                      'retirement_checked': True}
                     for ordinal in (1, 3, 10)]
        return data + [{'phase': phase + '-complete', 'runs': 10, 'pid': pid,
                        'retirement_checked': phase == 'saved'},
                       {'phase': 'first-close-attempted', 'mode': phase, 'pid': pid},
                       {'phase': 'first-close-returned', 'mode': phase, 'pid': pid}]

    def test_same_original_fixture_and_isolated_normal_factory_phases(self):
        calls, events = [], []
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp)
            def run(name, args, **options):
                calls.append((name, args, options))
                phase = args[-1]
                self.assertEqual(args[:3], [Path('/consumer/python'), '-I', '-B'])
                fixture = args[3]
                self.assertEqual(fixture.read_bytes(),
                                 (ci.ROOT / 'scripts/fixtures/python-local-repeated-host.py').read_bytes())
                self.assertNotEqual(options['env']['HOME'], '/prior-home')
                self.assertEqual(options['env']['PATH'], '/consumer/bin')
                self.assertEqual(options['cwd'], destination / 'ordinary-repeated-host/workspace')
                events.extend(self.events(phase, 41 if phase == 'warm' else 42))
                fixture.with_name('events.jsonl').write_text(''.join(json.dumps(event) + '\n' for event in events))
                return b''
            result = ci.accept_installed_repeated_host(run, Path('/consumer/python'), destination,
                                                       {'HOME': '/prior-home', 'PATH': '/consumer/bin'})
        self.assertEqual([(name, args[-1], options['timeout']) for name, args, options in calls],
                         [('installed-ordinary-repeated-warm', 'warm', 900),
                          ('installed-ordinary-repeated-saved', 'saved', 180)])
        self.assertEqual(result, {'runs': 10, 'warm_pid': 41, 'saved_pid': 42,
                                  'successful_retirement_checkpoints': [1, 3, 10],
                                  'closed_saved_read_retirement_checked': True,
                                  'original_first_closes_returned': True})

    def test_missing_result_checkpoint_close_or_same_process_cannot_pass(self):
        warm = self.events('warm', 41)
        self.assertEqual(ci.require_installed_repeated_host(warm, 'warm', None), 41)
        for excluded in ('result-complete', 'checkpoint-complete', 'first-close-attempted',
                         'first-close-returned'):
            with self.subTest(excluded=excluded), self.assertRaises(ValueError):
                ci.require_installed_repeated_host(
                    [event for event in warm if event['phase'] != excluded], 'warm', None)
        for failure in ('primary-failure', 'first-close-failed'):
            with self.subTest(failure=failure), self.assertRaises(ValueError):
                ci.require_installed_repeated_host(warm + [{'phase': failure, 'pid': 41}], 'warm', None)
        with self.assertRaises(ValueError):
            ci.require_installed_repeated_host(warm + self.events('saved', 41), 'saved', 41)
        for phase, checkpoint in (('warm', 'checkpoint-complete'), ('saved', 'saved-complete')):
            with self.subTest(phase=phase), self.assertRaises(ValueError):
                ci.require_installed_repeated_host([
                    event | {'retirement_checked': False} if event['phase'] == checkpoint else event
                    for event in self.events(phase, 42)], phase, 41)

    def test_retirement_inventory_targets_execution_and_closed_readers_only(self):
        fixture = load('repeated_host_inventory', SCRIPTS / 'fixtures/python-local-repeated-host.py')
        snapshot = dict.fromkeys(fixture.SETTLED_COUNTS, 0) | {
            'core_retained_work': False, 'core_loans': 17, '_inputs': 2,
        }
        with patch.object(fixture, 'inventory', return_value=snapshot), patch.object(fixture, 'write_event') as emit:
            self.assertIs(fixture.settled_inventory(None, 'warm', 1), snapshot)
            emit.assert_not_called()
            for name in ('_physical_work', 'core_task_loans', '_result_exports', 'custody_runs',
                         'custody_preparations', '_saved_result_reads', 'core_retained_work'):
                with self.subTest(name=name):
                    snapshot[name] = 1
                    with self.assertRaises(AssertionError):
                        fixture.settled_inventory(None, 'warm', 3)
                    emit.assert_called_with('retirement-pending', mode='warm', ordinal=3,
                                            inventory=snapshot)
                    snapshot[name] = 0

    def test_reference_survives_failed_start_without_the_signed_input(self):
        fixture = load('repeated_host_reference', SCRIPTS / 'fixtures/python-local-repeated-host.py')
        original = {'epoch': {'authenticator': 'private'}, 'nonce': 'synthetic'}
        failure = RuntimeError('original start failure')
        def start(*args, **kwargs):
            self.assertIs(kwargs['submission_ref'], original)
            raise failure
        client = SimpleNamespace(new_submission=lambda: original, start_source=start, close=lambda: None)
        api = SimpleNamespace(Client=SimpleNamespace(open=lambda: client))
        with tempfile.TemporaryDirectory() as tmp, patch.object(fixture, 'ROOT', Path(tmp)), \
                patch.object(fixture, 'inventory', return_value={}), patch.dict(sys.modules, {'actql': api}):
            with self.assertRaises(RuntimeError) as raised:
                fixture.run_phase('warm')
            self.assertIs(raised.exception, failure)
            recorded = json.loads((Path(tmp) / 'original-reference.json').read_text())
            expected = hashlib.sha256(json.dumps(original, sort_keys=True, separators=(',', ':')).encode())
            self.assertEqual(recorded, {'producer_pid': fixture.os.getpid(),
                                        'runs': [{'ordinal': 1, 'submission_sha256': expected.hexdigest()}]})
            self.assertFalse((Path(tmp) / 'originals.json').exists())

    def test_first_actual_failure_stops_without_retry_or_saved_launch(self):
        failure, calls = RuntimeError('original ordinary failure'), []
        def run(name, args, **options):
            calls.append(name)
            raise failure
        with tempfile.TemporaryDirectory() as tmp, self.assertRaises(RuntimeError) as raised:
            ci.accept_installed_repeated_host(run, Path('/python'), Path(tmp), {})
        self.assertIs(raised.exception, failure)
        self.assertEqual(calls, ['installed-ordinary-repeated-warm'])


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


class CurrentHistoryTraceTests(unittest.TestCase):
    def trace_module(self):
        # Import the actual fixture; no Source slicing, Core construction or
        # installed-history operation is performed by these scalar controls.
        with patch.object(sys, 'path', list(sys.path)), \
                patch.object(sys, 'argv', ['current-history-trace-unit']):
            return load('current_history_trace_unit',
                        SCRIPTS / 'fixtures/python-local-sdk-current-history.py')

    def test_first_original_failure_and_phase_survive_rethrow_and_later_failure(self):
        module = self.trace_module()
        trace = module.Trace()
        trace.enabled, trace.target = True, 'unit-original'

        class OpaqueFailure(RuntimeError):
            def __str__(self):
                raise AssertionError('Never format the original failure')

        first, later = OpaqueFailure(), OpaqueFailure()
        for phase, original in [('select', first), ('drive', later)]:
            def invoke():
                raise original
            with patch('sys.stdout', io.StringIO()), \
                    self.assertRaises(OpaqueFailure) as raised:
                trace.call(phase, invoke)
            self.assertIs(raised.exception, original)
            self.assertIs(trace.refusal, first)
            self.assertEqual(trace.refusal_phase, 'select')
            self.assertIsNone(trace.active)
        self.assertEqual([step['phase'] for step in trace.steps], ['select', 'drive'])

    def test_same_scalar_core_refusal_and_success_result_are_preserved(self):
        module = self.trace_module()
        trace = module.Trace()
        trace.enabled, trace.target = True, 'unit-original'
        result = object()
        with patch('sys.stdout', io.StringIO()):
            self.assertIs(trace.call('select', lambda: result), result)
        self.assertIsNone(trace.refusal)
        original = module.LocalCoreError('reserve_next_sdk_task', -35)
        def invoke():
            raise original
        with patch('sys.stdout', io.StringIO()), \
                self.assertRaises(module.LocalCoreError) as raised:
            trace.call('select', invoke)
        self.assertIs(raised.exception, original)
        self.assertIs(trace.refusal, original)
        self.assertEqual((trace.refusal.operation, trace.refusal.code),
                         ('reserve_next_sdk_task', -35))
        self.assertEqual(trace.refusal_phase, 'select')

    def test_reporting_failure_cannot_replace_original_base_exception(self):
        module = self.trace_module()
        trace = module.Trace()
        trace.enabled, trace.target = True, 'unit-original'
        original = KeyboardInterrupt()
        def invoke():
            raise original
        with patch('builtins.print', side_effect=BrokenPipeError()), \
                self.assertRaises(KeyboardInterrupt) as raised:
            trace.call('select', invoke)
        self.assertIs(raised.exception, original)
        self.assertIs(trace.refusal, original)
        self.assertEqual(trace.refusal_phase, 'select')
        self.assertIsNone(trace.active)


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

    def test_unrelated_and_foreign_profile_events_never_read_counts(self):
        from types import SimpleNamespace
        _, control, core, _ = self.configured_control()
        class UnreadableCounts:
            def __iter__(self):
                raise AssertionError('An unrelated profile event read counters')
        def unrelated():
            return None
        counts = UnreadableCounts()
        control.counts = counts
        for code, receiver in ((unrelated.__code__, core),
                               (control.drive_code, object()),
                               (control.export_code, object())):
            for event in ('call', 'return'):
                with self.subTest(code=code.co_name, event=event):
                    frame = SimpleNamespace(f_code=code, f_locals={'self': receiver})
                    control._profile(frame, event, None)
                    self.assertIs(control.counts, counts)
                    self.assertTrue(control.valid)
                    self.assertIsNone(control.failure)
                    self.assertEqual(control.refusal_bits, 0)
                    self.assertEqual(control.span_refusal_bits, 0)

    def test_exact_drive_and_export_events_still_saturate_and_preserve_first_failure(self):
        from types import SimpleNamespace
        for target in ('drive', 'export'):
            with self.subTest(target=target):
                _, control, core, _ = self.configured_control()
                first = RuntimeError('Original observation failure')
                control.failure = first
                control.counts = [1024] * 5
                frame = SimpleNamespace(
                    f_code=control.drive_code if target == 'drive' else control.export_code,
                    f_locals={'self': core if target == 'drive' else control.export})
                for event in ('call', 'return'):
                    control._profile(frame, event, None)
                self.assertEqual(control.counts, ([1025, 1025, 1024, 1024, 1024]
                                                 if target == 'drive'
                                                 else [1024, 1024, 1025, 1025, 1025]))
                self.assertFalse(control.valid)
                self.assertIs(control.failure, first)
                self.assertEqual(control.refusal_bits, 16)
                self.assertEqual(control.span_refusal_bits, 0)

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


class OrdinaryOuterFuelObservationTests(unittest.TestCase):
    """Actual SDK scope owners with explicit non-VM fuel ports, not acceptance."""

    def fixture(self):
        import os
        import threading
        sdk = SCRIPTS.parent / 'packages/python-sdk/src'
        sys.path.insert(0, str(sdk))
        try:
            from actql_sdk._local_core import LocalCore
            from actql_sdk._local_product import InstalledLocalHost
            from actql_sdk._local_work import OriginalLocalWork
        finally:
            sys.path.remove(str(sdk))
        module = load('ordinary_outer_fuel', SCRIPTS / 'fixtures/python-local-repeated-host.py')
        core = object.__new__(LocalCore)
        core._identity, core._nonce, core._lock = object(), 41, threading.RLock()
        core._closed = core._retired = core._closing = core._invoking = False
        core._ordinary_host, core._host_initial_claimed = True, False
        core._host_fuel_phase = core._host_operation_scope = core._host_retained_work = None
        core._host_operation_id = core._host_operation_sequence = 0
        from types import SimpleNamespace
        core._instance, core._exports = object(), SimpleNamespace(_extern_map={'memory': object()})
        class OpaqueObservationFailure(BaseException):
            def __str__(self):
                raise AssertionError('Optional fuel failure must not be formatted')
        class FuelPort:
            def __init__(self, owner):
                self.core = owner
                self.remaining, self.sets, self.reads, self.fail = 123, 0, 0, False
            def set_fuel(self, value):
                self.sets += 1
                self.remaining = value
            def get_fuel(self):
                if not self.core._lock._is_owned() or self.core._invoking:
                    raise AssertionError('Fuel read outside its original serialized boundary')
                self.reads += 1
                if self.fail:
                    raise OpaqueObservationFailure()
                return self.remaining
        store = core._store = FuelPort(core)
        core._platform_vm_original = (core, core._identity, core._nonce, store,
            core._instance, core._exports, core._exports._extern_map['memory'], os.getpid())
        observer = module._OrdinaryFuelObservation(LocalCore, InstalledLocalHost, OriginalLocalWork)
        return module, core, store, observer, OriginalLocalWork

    def test_normal_scope_measures_actual_start_end_and_never_adds_a_refill(self):
        _, core, store, observer, _ = self.fixture()
        methods = (type(core)._host_operation, type(store).set_fuel, type(store).get_fuel)
        with observer:
            with core._host_operation():
                with core._lock:
                    store.remaining -= 7
        result = observer.summary()
        self.assertTrue(result['qualified'], result)
        self.assertEqual(len(result['operations']), 1)
        value = result['operations'][0]
        self.assertTrue(value['available'])
        self.assertEqual(value['ending'], 'normal-context')
        self.assertEqual((value['startRemaining'], value['endRemaining'], value['consumedFuel']),
                         (64_000_000_000, 63_999_999_993, 7))
        self.assertEqual((store.sets, store.reads), (1, 2))
        self.assertEqual(methods, (type(core)._host_operation, type(store).set_fuel, type(store).get_fuel))
        self.assertIsNone(core._host_operation_scope)

    def test_retained_scope_is_counted_only_at_the_same_actual_worker_return(self):
        _, core, store, observer, work_type = self.fixture()
        def invoke():
            with core._lock:
                store.remaining -= 13
        with observer:
            with core._host_operation():
                work = work_type(invoke, owner=object(), on_exit=core._finish_work_operation)
                core._retain_work_operation(work)
            self.assertFalse(observer.summary()['operations'][0]['available'])
            self.assertEqual(store.reads, 1)
            work.start()
            work._thread.join(2)
            self.assertFalse(work._thread.is_alive())
            self.assertIsNone(work._future.exception(timeout=0))
        result = observer.summary()
        self.assertTrue(result['qualified'], result)
        self.assertEqual(len(result['operations']), 1)
        self.assertEqual(result['operations'][0]['ending'], 'retained-worker')
        self.assertEqual(result['operations'][0]['consumedFuel'], 13)
        self.assertEqual((store.sets, store.reads), (1, 2))
        self.assertIsNone(core._host_retained_work)

    def test_foreign_or_invoking_boundary_never_reads_fuel(self):
        from types import SimpleNamespace
        _, core, store, observer, _ = self.fixture()
        with observer:
            with core._host_operation():
                frame = SimpleNamespace(f_code=type(core)._host_operation.__wrapped__.__code__,
                    f_locals={'self': core, 'scope': core._host_operation_scope, 'initial': False})
                with core._lock:
                    before = store.reads
                    core._invoking = True
                    observer._profile(frame, 'c_return', getattr)
                    core._invoking = False
                    frame.f_locals['self'] = object()
                    observer._profile(frame, 'c_return', getattr)
                    self.assertEqual(store.reads, before)
        self.assertTrue(observer.summary()['qualified'])

    def test_missing_negative_and_optional_error_are_unavailable_not_zero(self):
        _, core, store, observer, _ = self.fixture()
        with core._host_operation():
            observer.__enter__()  # Deliberately miss the real start; no reconstructed budget.
        observer.__exit__(None, None, None)
        self.assertFalse(observer.summary()['qualified'])
        self.assertEqual(store.reads, 0)
        for fault in ('negative', 'getter'):
            with self.subTest(fault=fault):
                _, core, store, observer, _ = self.fixture()
                with observer:
                    with core._host_operation():
                        if fault == 'negative':
                            store.remaining = -1
                        else:
                            store.fail = True
                result = observer.summary()
                self.assertFalse(result['qualified'])
                self.assertIsNone(result['operations'][0]['consumedFuel'])

    def test_failed_normal_body_preserves_primary_context_and_restores_profiles(self):
        import threading
        _, core, store, observer, _ = self.fixture()
        primary, cause = RuntimeError('original primary'), ValueError('original cause')
        try:
            with observer:
                with core._host_operation():
                    raise primary from cause
        except RuntimeError as caught:
            self.assertIs(caught, primary)
            self.assertIs(caught.__cause__, cause)
        else:
            self.fail('Original failure was hidden')
        result = observer.summary()
        self.assertFalse(result['qualified'])
        self.assertIsNone(result['operations'][0]['consumedFuel'])
        self.assertIsNone(sys.getprofile())
        self.assertIsNone(threading.getprofile())
        self.assertEqual(store.sets, 1)

    def test_bootstrap_cleanup_and_observation_overflow_cannot_be_normal_zeroes(self):
        _, core, store, observer, _ = self.fixture()
        with observer:
            with core._host_operation(initial=True):
                pass
            with core._host_cleanup():
                pass
            self.assertEqual(store.reads, 0)
            for _ in range(observer.MAX_OPERATIONS):
                with core._host_operation():
                    store.remaining -= 1
            before = store.reads
            with core._host_operation():
                store.remaining -= 1
            self.assertEqual(store.reads, before)
        result = observer.summary()
        self.assertTrue(result['overflow'])
        self.assertFalse(result['qualified'])
        self.assertEqual(len(result['operations']), observer.MAX_OPERATIONS)
        self.assertTrue(all(row['consumedFuel'] == 1 for row in result['operations']))

    def test_failed_retained_worker_keeps_original_error_and_has_no_normal_cost(self):
        _, core, store, observer, work_type = self.fixture()
        primary = RuntimeError('original physical invocation failure')
        def invoke():
            raise primary
        with observer:
            with core._host_operation():
                work = work_type(invoke, owner=object(), on_exit=core._finish_work_operation)
                core._retain_work_operation(work)
            work.start()
            work._thread.join(2)
            self.assertFalse(work._thread.is_alive())
            self.assertIs(work._future.exception(timeout=0), primary)
        result = observer.summary()
        self.assertFalse(result['qualified'])
        self.assertIsNone(result['operations'][0]['consumedFuel'])
        self.assertEqual(result['operations'][0]['reason'], 'worker-failed-or-unavailable')
        self.assertEqual((store.sets, store.reads), (1, 1))

    def test_changed_original_memory_and_incomplete_owner_are_unavailable(self):
        for fault in ('memory', 'pending'):
            with self.subTest(fault=fault):
                _, core, store, observer, work_type = self.fixture()
                with observer:
                    with core._host_operation():
                        if fault == 'memory':
                            core._exports._extern_map['memory'] = object()
                        else:
                            work = work_type(lambda: None, owner=object(),
                                             on_exit=core._finish_work_operation)
                            core._retain_work_operation(work)
                result = observer.summary()
                self.assertFalse(result['qualified'])
                self.assertIsNone(result['operations'][0]['consumedFuel'])
                self.assertEqual((store.sets, store.reads), (1, 1))
                if fault == 'pending':
                    # End the same actual worker after observation; no forced ACK or new operation.
                    work.start()
                    work._thread.join(2)
                    self.assertFalse(work._thread.is_alive())
                    self.assertIsNone(work._future.exception(timeout=0))

    def test_unrelated_actual_code_is_never_hashed_by_the_observer(self):
        from types import FunctionType
        _, core, store, observer, _ = self.fixture()
        # A real unrelated Python call whose constant is deliberately unhashable.
        # It must not enter stage classification or invalidate normal evidence.
        constant = []
        code = (lambda: None).__code__.replace(co_consts=(constant,))
        unrelated = FunctionType(code, {})
        with observer:
            with core._host_operation():
                self.assertIs(unrelated(), constant)
        result = observer.summary()
        self.assertFalse(result['observationFailed'], result)
        self.assertTrue(result['qualified'], result)
        self.assertEqual((store.sets, store.reads), (1, 2))

    def test_original_matched_stage_still_has_same_scope_entry_and_return(self):
        _, core, store, observer, _ = self.fixture()
        with observer:
            with core._host_operation():
                with core._lock, self.assertRaises(ValueError):
                    # Original method/receiver; its existing foreign-loan check
                    # refuses before any guest call or physical reader.
                    core.inspect_journal_observation(None, None)
        result = observer.summary()
        self.assertTrue(result['qualified'], result)
        self.assertEqual([(r['stage'], r['event']) for r in result['stages']],
                         [('journal-inspect', 'call'), ('journal-inspect', 'return')])
        original = result['operations'][0]
        for stage in result['stages']:
            self.assertEqual((stage['core'], stage['scope'], stage['operation']),
                             (original['core'], original['scope'], original['operation']))
        self.assertEqual((store.sets, store.reads), (1, 4))


class TaskRetirementSnapshotTests(unittest.TestCase):
    """Original Python worker/allowance timeline with explicit scalar FFI ports."""

    def fixture(self):
        import threading
        sdk = SCRIPTS.parent / 'packages/python-sdk/src'
        sys.path.insert(0, str(sdk))
        try:
            from actql_sdk._local_core import LocalCore, _Task, _Input
            from actql_sdk._local_product import (InstalledLocalHost, _OriginalExecution,
                _OriginalRunReference, _OriginalCancellationStop, LocalProductCleanupPending)
            from actql_sdk._local_work import OriginalLocalWork
        finally:
            sys.path.remove(str(sdk))
        module = load('ci_task_retirement_snapshot', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        core = object.__new__(LocalCore)
        core._identity, core._lock = object(), threading.RLock()
        core._closed = core._retired = core._closing = core._invoking = False
        core._ordinary_host, core._host_fuel_phase = True, 'operation'
        core._host_operation_scope, core._host_operation_id = object(), 1
        core._host_retained_work = None
        task = _Task(core._identity, 11)
        core._task_loans = {11: task}
        host = object.__new__(InstalledLocalHost)
        host._original, host._core = host, core
        owner = object()
        reference = _OriginalRunReference(owner, _Input(core._identity, 1, 1, 0))
        original = _OriginalExecution(host, owner, reference=reference, tasks=[task])
        work = OriginalLocalWork(original, owner=original.run, on_exit=core._finish_work_operation)
        host._physical_work = [work]
        core._retain_work_operation(work)
        return module, core, host, work, original, task, _OriginalCancellationStop, LocalProductCleanupPending

    def run_original(self, *, closes=1, outside_lock=False, observation_error=False, unsupported=False):
        from contextlib import nullcontext
        module, core, host, work, original, task, stop_type, pending_type = self.fixture()
        calls = []
        stop = stop_type(original)
        class OpaqueFailure(BaseException):
            def __str__(self):
                raise AssertionError('Never format the optional diagnostic cause')
        def ffi(self_core, family, operation, handle, *fields):
            self.assertIs(self_core, core)
            self.assertEqual(core._host_fuel_phase, 'operation')
            calls.append((family, operation, handle, fields))
            if operation == 'close':
                return -9
            if observation_error:
                raise OpaqueFailure()
            return (-3 if unsupported else 4) if fields == (6,) else 83 if fields == (7,) else 2
        def execute(self_host, run):
            self.assertIs(self_host, host)
            self.assertIs(run, original.run)
            with nullcontext() if outside_lock else core._lock:
                for _ in range(closes):
                    self.assertFalse(core.close_task(task))
            raise stop
        with patch.object(type(core), '_call', ffi), patch.object(
                type(host), '_execute_original_admitted_run', execute), module._TaskRetirementObservation() as observer:
            work.start()
            work._thread.join(2)
            self.assertFalse(work._thread.is_alive())
        primary = work._future.exception(timeout=0)
        self.assertIs(type(primary), pending_type)
        self.assertIs(primary.__context__, stop)
        self.assertIs(stop.original, original)
        self.assertIsNone(work._cleanup_error)
        self.assertIsNone(work._exit_error)
        self.assertIs(core._task_loans[11], task)
        self.assertIs(original.tasks[0], task)
        self.assertIsNone(core._host_fuel_phase)
        self.assertIsNone(core._host_retained_work)
        self.assertFalse(core._lock._is_owned())
        self.assertIsNone(module.sys.getprofile())
        self.assertIsNone(module.threading.getprofile())
        return module, core, work, observer, calls, primary

    def test_original_worker_samples_before_scope_exit_and_reports_after_without_entry(self):
        module, core, work, observer, calls, primary = self.run_original()
        self.assertEqual(calls, [('task', 'close', 11, ()), ('task', 'progress', 11, (6,)),
                                ('task', 'progress', 11, (7,)), ('task', 'issue', 11, ())])
        with patch.object(type(core), '_call', side_effect=AssertionError('No retired-scope entry')) as call:
            result = observer.snapshot(work)
        call.assert_not_called()
        self.assertEqual(result, {'scope': 'post-close-current-snapshot', 'available': True,
            'observation_failed': False, 'overflow': False, 'profilers_restored': True,
            'refusal_code': None, 'tasks': [
                {'stage_code': 4, 'execution_issue_code': 2, 'cleanup_issue_code': 83}]})
        self.assertIs(work._future.exception(timeout=0), primary)
        self.assertNotIn('private-', json.dumps(result))

    def test_observer_failure_keeps_original_cancel_pending_and_scope_return(self):
        _, _, work, observer, calls, primary = self.run_original(observation_error=True)
        result = observer.snapshot(work)
        self.assertFalse(result['available'])
        self.assertTrue(result['observation_failed'])
        self.assertEqual(result['tasks'], [])
        self.assertEqual(len(calls), 2)
        self.assertIs(work._future.exception(timeout=0), primary)

    def test_captured_retirement_survives_cleared_host_lists_without_core_entry(self):
        module, core, work, observer, _, primary = self.run_original()
        host = work._invoke.host
        host._physical_work, host._public_run_references = [], []
        host._closing, host._installation = True, None
        core._closing = core._closed = True
        core._task_loans.clear()
        trace, context = primary.__traceback__, primary.__context__
        output = io.StringIO()
        with patch.object(type(core), '_call', side_effect=AssertionError('No retired Core entry')) as call, \
                patch.object(type(work), 'wait', side_effect=AssertionError('No work wait')) as wait:
            module.report_contexts(primary, output, task_retirement=observer)
        call.assert_not_called()
        wait.assert_not_called()
        record = json.loads(output.getvalue().splitlines()[0])
        captured = record['captured_task_retirement']
        self.assertEqual(captured['association'], 'same-original-worker-traceback')
        self.assertEqual(captured['sample_timing'], 'original-task-close-return-before-worker-exit')
        self.assertFalse(captured['live_selection'])
        self.assertEqual(captured['snapshot'], observer.snapshot(work))
        self.assertTrue(captured['snapshot']['available'])
        self.assertNotIn('local_work', record)
        self.assertIs(primary.__traceback__, trace)
        self.assertIs(primary.__context__, context)
        self.assertIs(work._future.exception(timeout=0), primary)

    def test_captured_retirement_refuses_foreign_identity_and_preserves_unavailable_samples(self):
        for settings in ({}, {'outside_lock': True}, {'observation_error': True}, {'closes': 17}):
            with self.subTest(settings=settings):
                module, _, work, observer, _, primary = self.run_original(**settings)
                expected = observer.snapshot(work)
                captured = module.captured_task_retirement(primary, observer)
                self.assertEqual(captured['snapshot'], expected)
                self.assertEqual(captured['snapshot']['available'], not settings)
                owner = work._owner
                work._owner = object()
                self.assertIsNone(module.captured_task_retirement(primary, observer))
                work._owner = owner
                copied = type(primary)(work._invoke.host)
                copied.__traceback__, copied.__context__ = primary.__traceback__, primary.__context__
                self.assertIsNone(module.captured_task_retirement(copied, observer))
                self.assertIsNone(module.captured_task_retirement(primary, object()))
                self.assertIs(work._future.exception(timeout=0), primary)

    def test_captured_retirement_traceback_visits_are_bounded(self):
        module, _, _, observer, _, primary = self.run_original()
        def raise_with_prefix(depth):
            if depth:
                return raise_with_prefix(depth - 1)
            raise primary
        try:
            raise_with_prefix(module.MAX_FRAMES + 4)
        except type(primary):
            pass
        walk = module.traceback.walk_tb
        visited = []
        def bounded_walk(trace):
            for frame in walk(trace):
                visited.append(None)
                if len(visited) > module.MAX_FRAMES:
                    raise AssertionError('Unbounded diagnostic traceback traversal')
                yield frame
        with patch.object(module.traceback, 'walk_tb', bounded_walk):
            self.assertIsNone(module.captured_task_retirement(primary, observer))
        self.assertEqual(len(visited), module.MAX_FRAMES)

    def test_captured_retirement_observation_error_never_replaces_primary(self):
        module, _, work, observer, _, primary = self.run_original()
        class OpaqueFailure(BaseException):
            def __str__(self):
                raise AssertionError('No optional diagnostic formatting')
        trace, context = primary.__traceback__, primary.__context__
        output = io.StringIO()
        with patch.object(module, 'captured_task_retirement', side_effect=OpaqueFailure(), create=True):
            module.report_contexts(primary, output, task_retirement=observer)
        record = json.loads(output.getvalue().splitlines()[0])
        self.assertNotIn('captured_task_retirement', record)
        self.assertIs(primary.__traceback__, trace)
        self.assertIs(primary.__context__, context)
        self.assertIs(work._future.exception(timeout=0), primary)

    def test_absent_outer_retirement_lock_refuses_without_an_observer_entry(self):
        _, _, work, observer, calls, _ = self.run_original(outside_lock=True)
        self.assertEqual(calls, [('task', 'close', 11, ())])
        result = observer.snapshot(work)
        self.assertFalse(result['available'])
        self.assertEqual(result['tasks'], [])

    def test_slot_bound_precedes_any_additional_observer_guest_entry(self):
        _, _, work, observer, calls, _ = self.run_original(closes=17)
        result = observer.snapshot(work)
        self.assertFalse(result['available'])
        self.assertTrue(result['overflow'])
        self.assertEqual(len(result['tasks']), 16)
        self.assertEqual(len(calls), 17 + 3 * 16)

    def test_unsupported_snapshot_field_is_refusal_not_available_evidence(self):
        _, _, work, observer, _, primary = self.run_original(unsupported=True)
        result = observer.snapshot(work)
        self.assertFalse(result['available'])
        self.assertEqual(result['refusal_code'], -3)
        self.assertIs(work._future.exception(timeout=0), primary)

    def test_only_initial_local_cancellation_facades_select_optional_observer(self):
        module, *_ = self.fixture()
        primary = RuntimeError('same consumer failure')
        base = ['python-product-installed.py', '--mode', 'local', '--facade', 'sync',
                '--case', 'cancellation', '--phase', 'initial']
        for replacements, expected in [({}, True), ({'sync': 'async'}, True),
                                        ({'sync': 'unknown'}, False),
                                        ({'local': 'remote'}, False),
                                        ({'initial': 'resume'}, False),
                                        ({'cancellation': 'execution'}, False)]:
            args = [replacements.get(value, value) for value in base]
            with self.subTest(replacements=replacements), patch.object(module.sys, 'argv', args), patch.object(
                    module.runpy, 'run_path', side_effect=primary) as run, patch.object(
                    module, 'report_contexts') as report:
                with self.assertRaises(RuntimeError) as caught:
                    module.run_consumer(Path('/external/python-product-installed.py'))
            self.assertIs(caught.exception, primary)
            self.assertIs(report.call_args.args[0], primary)
            observed = report.call_args.kwargs['task_retirement']
            self.assertEqual(type(observed) is module._TaskRetirementObservation, expected)
            if observed is not None:
                self.assertTrue(observed.restored)
            run.assert_called_once()


class FailureLocationTests(unittest.TestCase):
    def rejected_wait_fixture(self, *, completed=True, same_reference=True, task_drive_code=None,
                              state_changes=None, expected_schema_valid=True):
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
        if state_changes is not None:
            state.update(state_changes)
        self.assertIs(wire.valid(state, 'run_state'), expected_schema_valid)
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
        self.assertEqual(selected['wait_status'], 'running')
        self.assertTrue(selected['wait_state_schema_valid'])
        self.assertTrue(selected['wait_since_none'])
        self.assertTrue(selected['wait_since_valid'])
        self.assertTrue(selected['wait_revision_after_since'])
        self.assertTrue(selected['wait_control_schema_valid'])
        self.assertFalse(selected['wait_cancellation_requested'])
        self.assertEqual(selected['wait_physical_stop'], 'unknown')
        self.assertFalse(selected['wait_result_available'])
        self.assertTrue(selected['wait_availability_schema_valid'])
        self.assertTrue(selected['wait_availability_bounded'])
        self.assertFalse(selected['wait_availability_nonempty'])
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

    def test_rejected_wait_schema_failure_is_distinct_from_a_stable_cancelled_status(self):
        diagnostics = load('ci_wait_schema_shape', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, *_ = self.rejected_wait_fixture(state_changes={
            'status': 'cancelled',
            'control': {'revision': 2, 'cancellation_requested': 'private-control-secret',
                        'physical_stop': 'private-stop-secret'},
            'result_availability': {'private-result-secret': {
                'state': 'unknown', 'observed_at': 'private-clock-secret',
                'reason': 'private-reason-secret'}}}, expected_schema_valid=False)
        stream = io.StringIO()
        diagnostics.report_contexts(failure, stream)
        selected = next(json.loads(line)['local_work'] for line in stream.getvalue().splitlines()
                        if 'local_work' in json.loads(line))
        self.assertFalse(selected['wait_state_schema_valid'])
        self.assertEqual(selected['wait_status'], 'cancelled')
        self.assertTrue(selected['wait_status_stable'])
        self.assertFalse(selected['wait_control_schema_valid'])
        self.assertIsNone(selected['wait_cancellation_requested'])
        self.assertIsNone(selected['wait_physical_stop'])
        self.assertFalse(selected['wait_availability_schema_valid'])
        self.assertTrue(selected['wait_availability_nonempty'])
        self.assertNotIn('private-', stream.getvalue())

    def test_rejected_wait_unknown_status_is_not_emitted_as_a_diagnostic_value(self):
        diagnostics = load('ci_wait_unknown_shape', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        failure, *_ = self.rejected_wait_fixture(
            state_changes={'status': 'private-status-secret'}, expected_schema_valid=False)
        stream = io.StringIO()
        diagnostics.report_contexts(failure, stream)
        selected = next(json.loads(line)['local_work'] for line in stream.getvalue().splitlines()
                        if 'local_work' in json.loads(line))
        self.assertFalse(selected['wait_state_schema_valid'])
        self.assertIsNone(selected['wait_status'])
        self.assertFalse(selected['wait_status_known'])
        self.assertFalse(selected['wait_status_stable'])
        self.assertNotIn('private-status-secret', stream.getvalue())

    def test_rejected_wait_shape_declines_foreign_callbacks_and_cyclic_data(self):
        diagnostics = load('ci_wait_foreign_shape', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        self.rejected_wait_fixture()  # Load the same original SDK/codec only.
        from actql_sdk._async import wire
        invoked = []

        class Foreign(dict):
            def get(self, *args):
                invoked.append('foreign-get')
                raise AssertionError('No foreign diagnostic callback')

        result = diagnostics.rejected_wait_shape(Foreign(), {'since': None}, vars(wire))
        self.assertIsNone(result['wait_state_schema_valid'])
        cyclic = {}; cyclic['cycle'] = cyclic
        self.assertIsNone(diagnostics.rejected_wait_shape(
            cyclic, {'since': None}, vars(wire))['wait_state_schema_valid'])
        self.assertIsNone(diagnostics.rejected_wait_shape(
            {'oversized': [0] * diagnostics.MAX_VALUE_NODES}, {'since': None},
            vars(wire))['wait_state_schema_valid'])
        replaced = dict(vars(wire))
        replaced['valid'] = lambda *args: invoked.append('replaced-validator')
        self.assertIsNone(diagnostics.rejected_wait_shape(
            {}, {'since': None}, replaced)['wait_state_schema_valid'])
        self.assertEqual(invoked, [])

    def test_rejected_wait_cancellation_label_requires_the_same_bounded_reference(self):
        import traceback
        diagnostics = load('ci_wait_cancel_shape', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        self.rejected_wait_fixture()
        from actql_sdk._async import wire
        reference = {'namespaceId': 'private-namespace-secret',
                     'authorityScopeCid': 'sha256:' + 'a' * 64,
                     'runDefinitionCid': 'sha256:' + 'b' * 64}
        original = {'ref': reference, 'cancelRef': dict(reference, cancelId='private-cancel-secret',
                    expectedRevision=2), 'kind': 'accepted', 'revision': 3}

        def same_frame(cancellation, requested):
            try:
                raise RuntimeError('private-cause-secret')
            except RuntimeError as failure:
                return diagnostics.same_frame_cancellation_kind(
                    list(traceback.walk_tb(failure.__traceback__)), requested, vars(wire))

        self.assertEqual(same_frame(original, reference), 'accepted')
        self.assertIsNone(same_frame(original, dict(reference, namespaceId='foreign')))
        self.assertIsNone(same_frame(dict(original, kind='private-kind-secret'), reference))

    def test_rejected_wait_declines_foreign_tables_forwarded_with_the_original_validator(self):
        diagnostics = load('ci_wait_foreign_tables', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        self.rejected_wait_fixture()
        from actql_sdk._async import wire
        original = vars(wire)
        foreign = dict(original)
        foreign['SCHEMAS'] = dict(original['SCHEMAS'])
        state = dict(foreign['SCHEMAS']['run_state'])
        properties = dict(state['properties'])
        properties['status'] = {'enum': ['private-status-secret']}
        state['properties'] = properties
        foreign['SCHEMAS']['run_state'] = state
        result = diagnostics.rejected_wait_shape(
            {'status': 'private-status-secret'}, {'since': None}, foreign)
        self.assertIsNone(result['wait_status'])
        self.assertIsNone(result['wait_state_schema_valid'])
        self.assertNotIn('private-status-secret', json.dumps(result))
        foreign = dict(original)
        foreign['CONTRACT'] = dict(original['CONTRACT'])
        self.assertIsNone(diagnostics.rejected_wait_shape(
            {}, {'since': None}, foreign)['wait_state_schema_valid'])

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

    def test_retained_cleanup_chain_keeps_primary_and_original_chains(self):
        diagnostics = load('ci_installed_cleanup_chain', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        errors = load('ci_installed_cleanup_errors',
                      SCRIPTS.parent / 'packages/python-sdk/src/actql_sdk/_errors.py')
        primary = errors.ClientError('private primary')
        cleanup = ValueError('private cleanup')
        earlier = errors.ClientError('private earlier cleanup')
        primary.cleanup_error = cleanup
        cleanup.cleanup_error = earlier
        earlier.original_error = primary  # Actual identity cycle, no copy.
        native = (primary.__context__, primary.__cause__, primary.__traceback__)
        stream = io.StringIO()
        diagnostics.report_contexts(primary, stream)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        self.assertEqual([record['exception_type'] for record in records],
                         ['ClientError', 'ValueError', 'ClientError'])
        self.assertIs(primary.cleanup_error, cleanup)
        self.assertIs(cleanup.cleanup_error, earlier)
        self.assertIs(earlier.original_error, primary)
        self.assertEqual((primary.__context__, primary.__cause__, primary.__traceback__), native)
        self.assertNotIn('private', stream.getvalue())

    def test_retained_cleanup_observation_refuses_foreign_values_and_is_bounded(self):
        diagnostics = load('ci_installed_cleanup_bounds', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        original = RuntimeError('private')
        original.cleanup_error = {'private': 'non-exception'}
        stream = io.StringIO()
        diagnostics.report_contexts(original, stream)
        self.assertEqual(len(stream.getvalue().splitlines()), 1)
        self.assertNotIn('private', stream.getvalue())
        current = original
        for _ in range(100):
            following = ValueError('private')
            current.cleanup_error = following
            current = following
        stream = io.StringIO()
        diagnostics.report_contexts(original, stream)
        self.assertEqual(len(stream.getvalue().splitlines()), diagnostics.MAX_CONTEXTS)
        self.assertLessEqual(len(stream.getvalue().encode()), diagnostics.MAX_OUTPUT_BYTES)

    def test_cycle_is_not_repeated(self):
        import io
        diagnostics = load('ci_installed_run_cycle', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        error = ValueError('private')
        error.__context__ = error
        stream = io.StringIO()
        diagnostics.report_contexts(error, stream)
        self.assertEqual(len(stream.getvalue().splitlines()), 1)


class InitialPhaseObservationTests(unittest.TestCase):
    """Imported public-caller doubles only; no installed runtime qualification."""

    def fixture(self):
        from types import ModuleType, SimpleNamespace
        from unittest.mock import MagicMock
        consumer = load('ci_initial_phase_observation', SCRIPTS / 'fixtures/python-product-installed.py')
        client = MagicMock()
        client.__enter__.return_value = client
        client.__exit__.return_value = False
        runs = [MagicMock(ref={'original': index}) for index in (1, 2)]
        for run in runs:
            run.wait.return_value = {'status': 'succeeded'}
            run.result.return_value.all.return_value = [{'n': 1}]
        client.new_submission.side_effect = [{'submission': 1}, {'submission': 2}]
        client.start_source.side_effect = runs
        client._client._local_host = object()
        control = MagicMock()
        control.__enter__.return_value = control
        control.__exit__.return_value = False
        control.result.return_value = {'caller_control': True}
        public = ModuleType('actql')
        public.Client = SimpleNamespace(open=MagicMock(return_value=client))
        return consumer, public, client, runs, control

    def test_success_records_only_closed_boundaries_without_changing_public_calls(self):
        consumer, public, client, runs, control = self.fixture()
        stream = io.StringIO()
        with tempfile.TemporaryDirectory() as tmp, patch.dict(sys.modules, {'actql': public}), \
                patch.object(consumer, '_ClosedTaskDriveObservation', return_value=control), \
                patch.object(consumer.sys, 'stderr', stream), \
                patch.object(consumer, 'monotonic_ns', create=True,
                             side_effect=[1000] + list(range(1000, 1200, 10))) as clock:
            observed = consumer._sync('private-version', 'initial', Path(tmp) / 'original.json')
        self.assertIs(observed, control.result.return_value)
        records = [json.loads(line) for line in stream.getvalue().splitlines()]
        self.assertEqual([record['phase'] for record in records], [
            'facade-import-enter', 'facade-import-return', 'factory-enter', 'factory-return',
            'first-start-enter', 'first-start-return', 'first-wait-enter', 'first-wait-return',
            'first-result-enter', 'first-result-return', 'first-reread-enter', 'first-reread-return',
            'second-start-enter', 'second-start-return', 'second-state-enter', 'second-state-return',
            'second-result-enter', 'second-result-return', 'first-close-enter', 'first-close-return'])
        self.assertTrue(all(set(record) == {'stage', 'phase', 'elapsed_ns'} and
                            record['stage'] == 'installed-sync-initial-phase' for record in records))
        self.assertEqual([record['elapsed_ns'] for record in records], list(range(0, 200, 10)))
        self.assertEqual(clock.call_count, 21)  # One origin and the same twenty boundaries.
        self.assertLess(len(stream.getvalue().encode()), 4096)
        self.assertNotIn('private-version', stream.getvalue())
        public.Client.open.assert_called_once_with()
        self.assertEqual(client.start_source.call_count, 2)
        for run in runs:
            run.wait.assert_called_once_with()
        self.assertEqual(runs[0].result.return_value.all.call_count, 2)
        self.assertEqual(runs[1].result.return_value.all.call_count, 1)
        client.__exit__.assert_called_once_with(None, None, None)

    def test_original_failure_and_first_close_remain_when_optional_output_fails(self):
        consumer, public, client, _, control = self.fixture()
        original = RuntimeError('original first-start failure')
        client.start_source.side_effect = original
        class BrokenStream:
            def write(self, value):
                raise KeyboardInterrupt('optional output refused')
        with tempfile.TemporaryDirectory() as tmp, patch.dict(sys.modules, {'actql': public}), \
                patch.object(consumer, '_ClosedTaskDriveObservation', return_value=control), \
                patch.object(consumer.sys, 'stderr', BrokenStream()):
            with self.assertRaises(RuntimeError) as raised:
                consumer._sync('fixture', 'initial', Path(tmp) / 'original.json')
        self.assertIs(raised.exception, original)
        client.start_source.assert_called_once()
        self.assertEqual(client.__exit__.call_count, 1)
        self.assertIs(client.__exit__.call_args.args[1], original)
        control.result.assert_not_called()

    def test_saved_route_has_no_initial_markers_or_new_physical_control(self):
        consumer, public, client, runs, control = self.fixture()
        saved = {'submission': {'same': 'original'}, 'run': runs[0].ref}
        client.lookup_submission.return_value = {'kind': 'ready', 'admission': {'ref': runs[0].ref}}
        client.attach.return_value = runs[0]
        stream = io.StringIO()
        with patch.dict(sys.modules, {'actql': public}), patch.object(consumer, '_saved', return_value=saved), \
                patch.object(consumer, '_ClosedTaskDriveObservation', return_value=control) as observation, \
                patch.object(consumer.sys, 'stderr', stream), \
                patch.object(consumer, 'monotonic_ns', create=True) as clock:
            self.assertIsNone(consumer._sync('fixture', 'resume', Path('/unused/receipt')))
        self.assertEqual(stream.getvalue(), '')
        clock.assert_not_called()
        observation.assert_not_called()
        client.start_source.assert_not_called()
        client.attach.assert_called_once_with(saved['run'])
        client.__exit__.assert_called_once_with(None, None, None)

    def test_unselected_or_foreign_marker_cannot_invoke_foreign_comparison_or_emit(self):
        consumer, _, _, _, _ = self.fixture()
        class Foreign:
            def __eq__(self, other):
                raise AssertionError('Do not compare a foreign diagnostic value')
        stream = io.StringIO()
        with patch.object(consumer.sys, 'stderr', stream):
            consumer._sync_initial_phase(False, 'factory-enter')
            consumer._sync_initial_phase(True, Foreign())
            consumer._sync_initial_phase(True, 'private-stage-not-selected')
        self.assertEqual(stream.getvalue(), '')

    def test_elapsed_refuses_foreign_negative_overflow_and_failed_clock_without_fabricating_time(self):
        consumer, _, _, _, _ = self.fixture()
        class Foreign:
            def __sub__(self, other):
                raise AssertionError('Do not subtract foreign diagnostic clocks')
            def __lt__(self, other):
                raise AssertionError('Do not compare foreign diagnostic clocks')
        maximum = (1 << 63) - 1
        cases = [(0, 0, 0), (0, maximum, maximum), (100, 125, 25),
                 (100, 99, None), (0, maximum + 1, None), (0, True, None),
                 (0, 1.5, None), (0, Foreign(), None), (None, 100, None),
                 (True, 100, None), (-1, 100, None), (maximum + 1, maximum + 2, None),
                 (Foreign(), 100, None)]
        for origin, now, expected in cases:
            stream = io.StringIO()
            with self.subTest(origin_type=type(origin).__name__, now_type=type(now).__name__), \
                    patch.object(consumer.sys, 'stderr', stream), \
                    patch.object(consumer, 'monotonic_ns', create=True, return_value=now):
                consumer._sync_initial_phase(True, 'factory-enter', origin)
            if expected is None:
                self.assertEqual(stream.getvalue(), '')
            else:
                self.assertEqual(json.loads(stream.getvalue())['elapsed_ns'], expected)
        stream = io.StringIO()
        with patch.object(consumer.sys, 'stderr', stream), \
                patch.object(consumer, 'monotonic_ns', create=True, side_effect=KeyboardInterrupt):
            consumer._sync_initial_phase(True, 'factory-enter', 0)
        self.assertEqual(stream.getvalue(), '')

    def test_failed_origin_preserves_original_failure_and_first_close_without_reorigin(self):
        consumer, public, client, _, control = self.fixture()
        original = RuntimeError('original first-start failure')
        client.start_source.side_effect = original
        stream = io.StringIO()
        with tempfile.TemporaryDirectory() as tmp, patch.dict(sys.modules, {'actql': public}), \
                patch.object(consumer, '_ClosedTaskDriveObservation', return_value=control), \
                patch.object(consumer.sys, 'stderr', stream), \
                patch.object(consumer, 'monotonic_ns', create=True, side_effect=KeyboardInterrupt) as clock:
            with self.assertRaises(RuntimeError) as raised:
                consumer._sync('fixture', 'initial', Path(tmp) / 'original.json')
        self.assertIs(raised.exception, original)
        clock.assert_called_once_with()
        self.assertEqual(stream.getvalue(), '')
        self.assertEqual(client.__exit__.call_count, 1)
        self.assertIs(client.__exit__.call_args.args[1], original)
        control.result.assert_not_called()


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
