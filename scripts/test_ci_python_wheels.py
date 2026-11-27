"""Harness unit tests only: these fixtures are not installed product acceptance."""
from base64 import b64encode
import hashlib
from http.client import IncompleteRead
import importlib.util
import io
import json
import sqlite3
import ssl
import subprocess
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch
from urllib.error import HTTPError
from urllib.request import HTTPSHandler, ProxyHandler, Request, build_opener
import zipfile

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

from python_model_installed_case import accept_installed_portable_model, wire

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

ci = load('ci_python_wheels', SCRIPTS / 'ci-python-wheels.py')
audit = load('ci_python_audit', SCRIPTS / 'fixtures/ci-python-installed-audit.py')


class OrdinaryRuntimeHandoffTests(unittest.TestCase):
    source = 'a' * 40
    platform = 'darwin-arm64'

    def original(self, home, platform=None, *, model=True):
        root = home / 'prepared'
        evidence = {'image/image-receipt.json': b'{"image":"fixture"}',
                    'module-receipt.json': b'{"module":"fixture"}',
                    'duckdb-physical.stdout': b'{"physical":"fixture"}'}
        artifact = {'source_sha': self.source, 'platform': platform or self.platform,
                    'compiled_image': {'runtime_allocation': 'platform'}}
        if model:
            artifact['model_crypto'] = {'file': 'fixture'}
            evidence['model-crypto/producer.json'] = b'{"crypto":"fixture"}'
        evidence['artifact/artifact.json'] = wire(artifact)
        producer = {'scope': 'ordinary_platform_components_only', 'source_sha': self.source,
                    'artifact': artifact, 'wheel_built': False, 'runtime_executed': False,
                    'public_local_accepted': False}
        for name, pin in {
            'artifact/artifact.json': 'artifact_sha256', 'image/image-receipt.json': 'image_receipt_sha256',
            'module-receipt.json': 'core_receipt_sha256', 'duckdb-physical.stdout': 'duckdb_receipt_sha256',
            'model-crypto/producer.json': 'model_crypto_receipt_sha256',
        }.items():
            if name in evidence:
                producer[pin] = hashlib.sha256(evidence[name]).hexdigest()
        evidence['artifact/producer.json'] = wire(producer)
        for name, raw in evidence.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        return root, evidence

    def test_selects_original_preparation_and_exact_receipts(self):
        with tempfile.TemporaryDirectory() as path:
            root, evidence = self.original(Path(path))
            self.assertEqual(ci.select_normal_runtime(root, self.source, self.platform),
                             (root.resolve() / 'artifact', evidence))
            for source, platform in (('b' * 40, self.platform), (self.source, 'linux-x64')):
                with self.assertRaisesRegex(ValueError, 'Foreign ordinary runtime'):
                    ci.select_normal_runtime(root, source, platform)
            (root / 'model-crypto/producer.json').write_bytes(b'{"crypto":"changed"}')
            with self.assertRaisesRegex(ValueError, 'differs from its producer'):
                ci.select_normal_runtime(root, self.source, self.platform)

    def test_rejects_duplicate_receipt_field_and_indirect_path(self):
        with tempfile.TemporaryDirectory() as path:
            root, evidence = self.original(Path(path))
            producer = root / 'artifact/producer.json'
            producer.write_bytes(b'{"source_sha":"injected",' + evidence['artifact/producer.json'][1:])
            with self.assertRaisesRegex(ValueError, 'Duplicate ordinary runtime'):
                ci.select_normal_runtime(root, self.source, self.platform)
            producer.write_bytes(evidence['artifact/producer.json'])
            image = root / 'image/image-receipt.json'
            other = image.with_name('other.json')
            image.rename(other)
            image.symlink_to(other)
            with self.assertRaisesRegex(ValueError, 'indirect path'):
                ci.select_normal_runtime(root, self.source, self.platform)

    def test_prepare_only_stops_before_either_wheel_or_consumer(self):
        with tempfile.TemporaryDirectory() as path:
            destination = Path(path) / 'prepared'
            def head(args, **kwargs):
                return '' if 'status' in args else self.source
            with patch.object(ci, 'normal_target', return_value=self.platform), \
                    patch.object(ci.subprocess, 'check_output', side_effect=head), \
                    patch.object(ci.subprocess, 'run', return_value=SimpleNamespace(stdout=b'', stderr=b'', returncode=0)) as steps, \
                    patch.object(ci, 'prepare_normal_runtime', return_value=destination / 'artifact') as prepare:
                ci.run_acceptance(destination, prepare_runtime_only=True)
            self.assertEqual(steps.call_count, 2)
            prepare.assert_called_once()
            self.assertEqual(prepare.call_args.args[2:5], (destination.resolve(), self.source, self.platform))
            self.assertFalse((destination / 'cohort').exists() or (destination / 'acceptance.json').exists())

    def test_pair_only_uses_same_pinned_builder_and_both_originals(self):
        with tempfile.TemporaryDirectory() as path:
            home = Path(path)
            darwin, _ = self.original(home / 'darwin')
            linux, _ = self.original(home / 'linux', 'linux-x64')
            preparations = {'linux-x64': linux, 'darwin-arm64': darwin}
            destination = home / 'pair'
            def head(args, **kwargs):
                return '' if 'status' in args else self.source
            with patch.object(ci, 'normal_target', return_value='linux-x64'), \
                    patch.object(ci.subprocess, 'check_output', side_effect=head), \
                    patch.object(ci.subprocess, 'run', return_value=SimpleNamespace(stdout=b'', stderr=b'', returncode=0)) as steps, \
                    patch.object(ci, 'prepare_normal_runtime') as prepare:
                for source, pair in (('b' * 40, preparations), (self.source, {'linux-x64': linux})):
                    with self.assertRaisesRegex(ValueError, 'source|preparations'):
                        ci.run_acceptance(destination, pair_runtime_preparations=pair, expected_source=source)
                steps.assert_not_called()
                ci.run_acceptance(destination, pair_runtime_preparations=preparations,
                                  expected_source=self.source)
            prepare.assert_not_called()
            venv, dependencies, shared = [call.args[0] for call in steps.call_args_list]
            self.assertEqual(venv[-1], str(destination.resolve() / 'builder'))
            self.assertEqual(tuple(dependencies[-len(ci.BUILD_REQUIREMENTS):]), ci.BUILD_REQUIREMENTS)
            self.assertEqual(shared[shared.index('--destination') + 1], str(destination.resolve() / 'shared'))
            self.assertEqual(shared[-6:], ['--paired-runtime-artifact', 'darwin-arm64',
                str(darwin.resolve() / 'artifact'), '--paired-runtime-artifact', 'linux-x64',
                str(linux.resolve() / 'artifact')])
            self.assertFalse((destination / 'acceptance.json').exists())

    def test_pair_only_refuses_inconsistent_model_variants_before_setup(self):
        with tempfile.TemporaryDirectory() as path:
            home = Path(path)
            darwin, _ = self.original(home / 'darwin')
            linux, _ = self.original(home / 'linux', 'linux-x64', model=False)
            def head(args, **kwargs):
                return '' if 'status' in args else self.source
            with patch.object(ci, 'normal_target', return_value='linux-x64'), \
                    patch.object(ci.subprocess, 'check_output', side_effect=head), \
                    patch.object(ci.subprocess, 'run') as steps, \
                    self.assertRaisesRegex(ValueError, 'different Model variants'):
                ci.run_acceptance(home / 'pair', expected_source=self.source,
                                  pair_runtime_preparations={'linux-x64': linux, 'darwin-arm64': darwin})
            steps.assert_not_called()

    def test_consumer_selects_both_inputs_before_any_wheel_build(self):
        with tempfile.TemporaryDirectory() as path:
            home = Path(path)
            root, evidence = self.original(home)
            shared = home / 'shared'
            shared.mkdir()
            destination = home / 'acceptance'
            def head(args, **kwargs):
                return '' if 'status' in args else self.source
            commands = []
            def stop_at_wheels(args, **kwargs):
                commands.append(args)
                return SimpleNamespace(stdout=b'', stderr=b'', returncode=int('--shared-wheels' in args))
            with patch.object(ci, 'normal_target', return_value=self.platform), \
                    patch.object(ci.subprocess, 'check_output', side_effect=head), \
                    patch.object(ci.subprocess, 'run', side_effect=stop_at_wheels), \
                    patch.object(ci, 'select_release_version', return_value={'pythonVersion': '0.0.3'}), \
                    patch.object(ci, 'prepare_normal_runtime') as prepare:
                with self.assertRaisesRegex(ValueError, 'paired shared wheels'):
                    ci.run_acceptance(destination, runtime_preparation=root)
                with self.assertRaisesRegex(RuntimeError, 'wheels failed'):
                    ci.run_acceptance(destination, runtime_preparation=root, shared_wheels=shared)
            prepare.assert_not_called()
            self.assertEqual(len(commands), 3)
            self.assertEqual(commands[-1][commands[-1].index('--artifact-directory') + 1],
                             str(root.resolve() / 'artifact'))
            self.assertEqual(commands[-1][-2:], ['--shared-wheels', str(shared.resolve())])
            self.assertFalse((destination / 'acceptance.json').exists())
            for name, raw in evidence.items():
                self.assertEqual((destination / name).read_bytes(), raw)


class InstalledPortableModelHarness(unittest.TestCase):
    version = '0.0.3'
    image = 'ab' * 32

    @staticmethod
    def fixture_cid(raw):
        return 'sha256:' + hashlib.sha256(raw).hexdigest()

    def model_store_fixture(self, path, reference, task, *, reported_input=3, submission=None, fault=None):
        # Test-only row carriers. The ordinary case reads production-encrypted originals.
        cid = self.fixture_cid
        definition = reference['runDefinitionCid']
        store, scope, request, slot, fixed = (cid(role.encode()) for role in (
            'store', 'scope', 'request', 'slot', 'fixed-wire'))

        def sealed(body):
            return {**body, 'self_cid': cid(wire(body))}

        authority = sealed({'operation': 'infer', 'connection': 'operator', 'model_invocation_scope_cid': scope,
                            'run_definition_cid': definition, 'model_task_cid': task, 'fixed_request_cid': fixed})
        attempt = sealed({'version': 'actql-model-call-attempt/0.1', 'attempt': 1, 'provider_id': 'operator',
                          'run_definition_cid': definition, 'model_task_cid': task, 'fixed_request_cid': fixed,
                          'authority_evidence_cid': authority['self_cid'], 'slot_cid': slot})
        call = {'model_call_slot_cid': slot, 'model_task_cid': task, 'fixed_request_cid': fixed}
        common = {'run_definition_cid': definition, 'request_scope_cid': request, 'slot': 0}
        entry = wire({**common, 'version': 'actql-native-model-call-original/0.1',
                      **{key: wire(value).decode() for key, value in
                         [('attempt', attempt), ('authority', authority), ('call', call)]}})
        path.parent.mkdir(parents=True)
        db = sqlite3.connect(path)
        try:
            db.executescript('CREATE TABLE core_bytes(key TEXT PRIMARY KEY, generation INTEGER, payload BLOB);'
                             'CREATE TABLE actql_capacity(namespace TEXT, reservation_key TEXT, '
                             'reserved_bytes INTEGER, reserved_objects INTEGER);')
            def put(namespace, key, payload, generation=0):
                db.execute('INSERT INTO core_bytes VALUES(?,?,?)',
                           (f'namespace:{len(namespace)}:{namespace}:{key}', generation, payload))

            def hold(phase, role, namespace):
                holding = cid(wire({'attempt': 1, 'attempt_cid': attempt['self_cid'], 'phase': phase, 'role': role,
                    'run_definition_cid': definition, 'scope_cid': scope, 'slot_cid': slot,
                    'store_authority_cid': store, 'version': 'actql-model-scoped-private-holding/0.1'}))
                envelope = {'version': 'actql-private-publication-evidence/0.1',
                            'nonce': b64encode(bytes(12)).decode(), 'tag': b64encode(bytes(16)).decode(),
                            'ciphertext': b64encode(role.encode()).decode()}
                put(namespace, holding, wire(envelope))
                return holding

            actual = path.stat()
            run_id = 'controlled-ordinary-python-model'
            environment = {'host_policy_profile': {'capacity': {'max_model_request_bytes_per_item': 1000}}}
            environment_cid = cid(wire(environment))
            environment['evidence_bundle_cid'] = environment_cid
            material = wire({'run_id': run_id, 'check_environment_cid': environment_cid,
                             'check_environment': wire(environment).decode()})
            caller = cid(b'caller')
            request_wire = wire({'authority_scope_cid': reference['authorityScopeCid'],
                                 'logical_request_scope_cid': request, 'caller_request_id': caller}).decode()
            run = {'run_definition': wire({'run_definition_cid': definition, 'run_id': run_id}).decode(),
                   'request': request_wire,
                   'publication_binding': wire([reference['namespaceId'], store,
                                                str(actual.st_dev), str(actual.st_ino)]).decode(),
                   'task_materials_cid': cid(material)}
            put('client_runs', definition, wire(run), 3 if submission is not None else 0)
            put('client_task_run_materials', definition + ':0', material)
            put('client_model_call_originals', attempt['self_cid'], entry, int(fault == 'loss-entry-generation'))
            if submission is not None:
                key = {'version': 'actql-run-state/0.1', 'run_id': run_id, 'status': 'needs_reconciliation',
                       'control': {'cancellation_requested': False, 'physical_stop': 'confirmed', 'revision': 3},
                       'next_action': {'kind': 'reconcile_run', 'reason': 'execution_unknown'},
                       'result_available': False,
                       'result_availability': {'answer': {'reason': 'not_published', 'state': 'unavailable'}}}
                updated = '2026-11-25T15:13:03.950Z'
                state = {**key, 'revision': 0, 'updated_at': updated,
                         'result_availability': {'answer': {**key['result_availability']['answer'],
                                                            'observed_at': updated}}}
                retained = {'manifest': None, 'run_definition_cid': definition, 'state': wire(state).decode()}
                put('client_submitted_intents', caller, wire({'phase': 'ready', 'reference': wire(submission).decode(),
                    'run_admission': wire({'request': request_wire, 'run_definition_cid': definition}).decode(),
                    'run_state_revision': 0, 'run_state_key': wire(key).decode(),
                    'run_state_original': None if fault == 'loss-unsaved' else wire(retained).decode()}), 2)
                db.execute('INSERT INTO actql_capacity VALUES(?,?,?,1)',
                           ('client_model_call_originals', scope, len(entry)))
                if fault == 'loss-raw':
                    hold('entered', 'model_raw_response', 'client_model_raw_responses')
                db.commit()
                return state
            hold('entered', 'model_raw_response', 'client_model_raw_responses')
            accounting = {'version': 'actql-model-attempt-accounting/0.1',
                          'attempt_cid': attempt['self_cid'], 'slot_cid': slot, 'cumulative_work': 356,
                          'input_tokens': reported_input, 'output_tokens': 2,
                          'cost_units': None, 'duration_ms': None, 'uncertain_wire_bytes': 66536,
                          'reservation': {'tokens': 1024, 'cost_units': 0, 'duration_ms': 6000}}
            identities = {'model_call_attempt': attempt['self_cid'], 'model_dispatch_authority': authority['self_cid'],
                          'model_attempt_accounting': cid(wire(accounting))}
            evidence = [{'role': role, 'cid': identities.get(role, cid(role.encode())),
                         'holding_cid': hold('settled', role, 'client_model_evidence')}
                        for role in ('model_call_attempt', 'model_attempt_accounting', 'model_attempt_outcome',
                                     'model_dispatch_authority', 'model_slot_capture', 'model_invocation_evidence',
                                     'model_capture_bundle')]
            terminal = wire({**common, 'version': 'actql-native-model-call-settlement-original/0.1',
                'entry_digest': cid(entry), 'attempt_cid': attempt['self_cid'], 'scope_cid': scope,
                'store_binding': store, 'evidence': evidence})
            put('client_model_call_settlements', attempt['self_cid'], terminal)
            db.execute('INSERT INTO actql_capacity VALUES(?,?,?,2)',
                       ('client_model_call_originals', scope, len(entry) + len(terminal)))
            db.commit()
        finally:
            db.close()

    def observed_run(self, root: Path, child_fault=None, *, source=False):
        pids = iter((101, 102, 103, 104, 105, 106))
        seen = []
        saved_loss_state = {}
        consumer = root / 'consumer/bin/python'
        env = {'PATH': str(consumer.parent)}

        def run(name, args, *, cwd, env: dict, timeout):
            self.assertEqual(args[:5], [consumer, '-I', '-B', root / 'ci-python-installed-run.py',
                                        root / 'python-product-installed.py'])
            flags = dict(zip(args[5::2], args[6::2]))
            work = flags['--model-fixture']
            facade, phase = flags['--facade'], flags['--phase']
            cold = phase == 'resume'
            loss = flags['--case'] == 'portable-model-loss'
            self.assertEqual(name, f'{facade}-model-{"loss-" if loss else ""}{phase}')
            self.assertEqual((cwd, flags['--receipt']), (work / 'project', work / 'original.json'))
            self.assertIn(flags['--case'], ('portable-model', 'portable-model-loss'))
            self.assertEqual(timeout, 180)
            self.assertEqual(env, {'PATH': str(consumer.parent)})
            self.assertEqual((work / 'program.json').exists(), not cold)
            case = json.loads((work / 'case.json').read_bytes())
            deployment = work / 'deployment'
            provider = json.loads((deployment / 'provider.json').read_bytes())
            profile = json.loads((deployment / 'response-profile.json').read_bytes())
            selected = json.loads((deployment / 'selection.json').read_bytes())
            trust = deployment / selected['tls_ca']['file']
            credential = deployment / selected['credential_file']
            endpoint = provider['endpoint']
            self.assertEqual(endpoint, profile['operation']['endpoint'])
            self.assertEqual('sha256:' + self.image, profile['adapter']['build_artifact_cid'])
            seal = 'sha256:' + hashlib.sha256(wire({key: value for key, value in profile.items()
                                           if key != 'self_cid'})).hexdigest()
            self.assertEqual([profile['self_cid'], selected['profile_cid'], provider['response_profile_cid']],
                             [seal] * 3)
            self.assertEqual(selected['tls_ca']['sha256'], 'sha256:' + hashlib.sha256(trust.read_bytes()).hexdigest())
            self.assertEqual(credential.stat().st_mode & 0o777, 0o600)
            if source and not loss:
                self.assertEqual(case['source_file'], 'small.csv')
                self.assertEqual((cwd / 'data/small.csv').read_bytes(), b'id,name\noriginal,Example\n')
                descriptor = deployment / selected['source_catalog']['file']
                descriptor_bytes = descriptor.read_bytes()
                self.assertEqual(selected['source_catalog']['sha256'], self.fixture_cid(descriptor_bytes))
                declaration = json.loads(descriptor_bytes)
                self.assertEqual(declaration['root'], str(cwd / 'data'))
                self.assertEqual(declaration['data_classification'], 'internal')
                self.assertEqual(declaration['connectors_sha256'],
                                 self.fixture_cid((cwd / 'connectors.json').read_bytes()))
            if not cold or child_fault == ('loss-resend' if loss else 'resend'):
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
                context.load_verify_locations(cafile=trust)
                input_body = '{"name":"Example"}' if source and not loss else '{}'
                request = Request(endpoint, data=wire({'model': 'deployed-chat', 'stream': False, 'n': 1,
                    'messages': [{'role': 'system', 'content': ''}, {'role': 'user', 'content': input_body}]}),
                    headers={'Authorization': 'Bearer ' + credential.read_text()})
                try:
                    opener = build_opener(ProxyHandler({}), HTTPSHandler(context=context))
                    with opener.open(request, timeout=2) as response:
                        if loss:
                            with self.assertRaises(IncompleteRead):
                                response.read()
                        else:
                            self.assertEqual(json.load(response)['usage'], {'prompt_tokens': 3, 'completion_tokens': 2})
                except HTTPError as error:
                    self.assertEqual((child_fault, cold, error.code), ('loss-resend' if loss else 'resend', True, 400))
                    error.close()
            seen.append((facade, phase, endpoint))
            pid = next(pids)
            ref = {'runDefinitionCid': self.fixture_cid((facade + ('-loss' if loss else '')).encode()),
                   'authorityScopeCid': self.fixture_cid(b'authority'), 'namespaceId': 'local'}
            store = cwd / 'state/state/client.sqlite3'
            if loss:
                submission = {'nonce': 'response-loss-test'}
                if not cold:
                    saved_loss_state.update(self.model_store_fixture(
                        store, ref, profile['task']['contract_cid'], submission=submission, fault=child_fault))
                state = dict(saved_loss_state) if cold else None
                if cold and child_fault == 'loss-reprojected':
                    state['revision'] = 1
                return json.dumps({'mode': 'local', 'version': self.version, 'case': 'portable-model-loss',
                    'facade': facade, 'phase': phase, 'pid': pid, 'check_verdict': None if cold else 'verified',
                    'first_close': True, 'cold_original_lookup': cold, 'python_check_events': None if cold else [],
                    'python_cold_events': [] if cold else None, 'run': ref, 'state': state,
                    'submission_cid': self.fixture_cid(wire(submission)),
                    'worker_stopped_without_status': None if cold else child_fault != 'loss-subscriber'})
            if not cold:
                self.model_store_fixture(store, ref, profile['task']['contract_cid'],
                    reported_input={'usage-zero': 0, 'usage-absent': None}.get(child_fault, 3))
            elif child_fault in ('ciphertext', 'generation', 'missing-raw', 'capacity', 'foreign-material', 'material-gap'):
                db = sqlite3.connect(store)
                try:
                    raw = 'namespace:26:client_model_raw_responses:%'
                    match child_fault:
                        case 'ciphertext':
                            body, = db.execute('SELECT payload FROM core_bytes WHERE key LIKE ?', (raw,)).fetchone()
                            envelope = json.loads(body)
                            envelope['ciphertext'] = b64encode(b'changed after warm').decode()
                            db.execute('UPDATE core_bytes SET payload=? WHERE key LIKE ?', (wire(envelope), raw))
                        case 'generation':
                            db.execute('UPDATE core_bytes SET generation=1 WHERE key LIKE ?', (raw,))
                        case 'missing-raw':
                            db.execute('DELETE FROM core_bytes WHERE key LIKE ?', (raw,))
                        case 'capacity':
                            db.execute('UPDATE actql_capacity SET reserved_objects=1')
                        case 'foreign-material':
                            db.execute('UPDATE core_bytes SET payload=CAST(? AS BLOB) WHERE key LIKE ?',
                                       ('{}', 'namespace:25:client_task_run_materials:%'))
                        case 'material-gap':
                            db.execute('UPDATE core_bytes SET key=substr(key,1,length(key)-1)||1 WHERE key LIKE ?',
                                       ('namespace:25:client_task_run_materials:%',))
                    db.commit()
                finally:
                    db.close()
            record = {'mode': 'local', 'version': self.version, 'case': 'portable-model', 'facade': facade,
                      'phase': phase, 'pid': pid, 'check_verdict': None if cold else 'verified',
                      'first_close': True, 'original_saved_first': cold,
                      'python_check_events': None if cold else [],
                      'python_cold_events': [] if cold else None,
                      'rows_sha256': hashlib.sha256(wire(case['rows'])).hexdigest(),
                      'run': ref,
                      'delivery': {'attempt_id': f'attempt-{pid}', 'bytes': 12, 'sha256': 'e' * 64,
                                   'artifact_cid': 'sha256:' + 'a' * 64, 'manifest_cid': 'sha256:' + 'b' * 64,
                                   'receipt_cid': 'sha256:' + 'c' * 64}}
            if source and not loss:
                record.update(python_source_opens=0 if cold else 1, python_source_unchanged=True)
                if cold and child_fault == 'source_reopen':
                    record['python_source_opens'] = 1
                if cold and child_fault == 'source_modified':
                    (cwd / 'data/small.csv').write_bytes(b'id,name\noriginal,Changed\n')
            if not cold and child_fault == 'check-egress':
                record['python_check_events'] = ['socket.connect']
            if not cold and child_fault == 'missing-check':
                record.pop('python_check_events')
            if cold and child_fault == 'missing-cold-audit':
                record.pop('python_cold_events')
            if cold and child_fault == 'foreign':
                record['run']['runDefinitionCid'] = 'sha256:' + 'f' * 64
            if cold and child_fault == 'same-process':
                record['pid'] -= 1
            return json.dumps(record)

        return accept_installed_portable_model(
            run, consumer, root, self.version, env, self.image, source=source), seen

    def test_original_typed_source_in_both_warm_requests_and_no_cold_open(self):
        with tempfile.TemporaryDirectory() as scratch:
            result, seen = self.observed_run(Path(scratch), source=True)
            self.assertTrue(result['source_backed'])
            self.assertEqual(len(seen), 6)  # Two warm/cold facades and the separate loss case.
            for lane in result['facades']:
                self.assertEqual([phase['python_source_opens'] for phase in lane['phases']], [1, 0])
                self.assertEqual(lane['warm_peer']['posts'], 1)
                self.assertTrue(lane['cold_peer_unchanged'])
        for fault in ('source_reopen', 'source_modified'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as scratch:
                with self.assertRaisesRegex(ValueError, 'original Source'):
                    self.observed_run(Path(scratch), fault, source=True)

    def test_source_audit_observes_actual_posix_open_and_refuses_check_or_cold_open(self):
        command = r'''
import os
from pathlib import Path
import runpy
import sys
audit_type = runpy.run_path(sys.argv[1])['_ModelEgressAudit']
mode = sys.argv[2]
source = Path('small.csv').absolute()
audit = audit_type('provider.key', 'fixture.pem', mode == 'cold', source=source)
if mode == 'warm':
    audit.begin_run()
    os.close(os.open(source.name, os.O_RDONLY))
    assert audit.observation()['python_source_opens'] == 1
    try:
        os.open(source.name, os.O_RDONLY)
    except AssertionError:
        assert audit.source_opens == 2
    else:
        raise AssertionError('Second Source open was admitted')
else:
    try:
        os.open(source, os.O_RDONLY)
    except AssertionError:
        assert audit.source_opens == 1
    else:
        raise AssertionError('Source opened before dispatch or during Saved')
'''
        child = SCRIPTS / 'fixtures/python-product-installed.py'
        with tempfile.TemporaryDirectory() as scratch:
            (Path(scratch) / 'small.csv').write_bytes(b'id,name\noriginal,Example\n')
            for mode in ('warm', 'check', 'cold'):
                with self.subTest(mode=mode):
                    direct = subprocess.run(
                        [sys.executable, '-I', '-B', '-c', command, child, mode],
                        cwd=scratch, capture_output=True, text=True, timeout=5)
                    self.assertEqual(direct.returncode, 0, direct.stderr)

    def test_own_protected_roots_and_separate_warm_cold_process_receipts(self):
        with tempfile.TemporaryDirectory() as scratch:
            result, seen = self.observed_run(Path(scratch))
            self.assertEqual([values[:2] for values in seen], [
                ('sync', 'initial'), ('sync', 'resume'), ('async', 'initial'), ('async', 'resume'),
                ('async', 'initial'), ('async', 'resume')])
            loss = result['response_loss']
            self.assertEqual((loss['warm_peer']['posts'], loss['warm_peer']['partial_responses']), (1, 1))
            self.assertTrue(loss['cold_peer_unchanged'])
            self.assertTrue(loss['cold_original_unchanged'])
            self.assertEqual(loss['original_before_cold']['journal_charge']['objects'], 1)
            self.assertTrue(all('submission' not in phase for phase in loss['phases']))
            for facade in result['facades']:
                self.assertTrue(facade['cold_peer_unchanged'])
                self.assertEqual(facade['warm_peer']['posts'], 1)
                self.assertTrue(facade['cold_model_holdings_unchanged'])
                [attempt] = facade['model_holdings']['attempts']
                self.assertEqual(attempt['journal_charge']['objects'], 2)
                self.assertIn('model_attempt_accounting', attempt['evidence'])
                body = attempt['matched_accounting_preimage']
                self.assertEqual((body['input_tokens'], body['output_tokens']), (3, 2))
                self.assertEqual(attempt['evidence']['model_attempt_accounting']['evidence_cid'],
                                 self.fixture_cid(wire(body)))

    def test_loss_rejects_unsaved_or_reprojected_state_wrong_entry_and_cold_resend(self):
        for fault, reason in [('loss-unsaved', 'did not durably publish'),
                              ('loss-entry-generation', 'changed original Model Store record'),
                              ('loss-raw', 'inventory for client_model_raw_responses'),
                              ('loss-reprojected', 'differs from the durably stopped original'),
                              ('loss-subscriber', 'Incomplete installed Portable Model loss consumer'),
                              ('loss-resend', 'Cold reconciliation reached')]:
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as scratch:
                with self.assertRaisesRegex(ValueError, reason):
                    self.observed_run(Path(scratch), fault)

    def test_requires_distinct_check_and_cold_egress_observations(self):
        for fault in ('check-egress', 'missing-check', 'missing-cold-audit'):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as scratch:
                with self.assertRaisesRegex(ValueError, 'Incomplete installed Portable Model consumer'):
                    self.observed_run(Path(scratch), fault)

    def test_model_egress_audit_guards_startup_and_all_of_cold_saved(self):
        # Python audit hooks cannot be removed. Use one isolated process per
        # case, with actual file-open/DNS entry and no network exchange.
        run_audit = r'''
import os
from pathlib import Path
import runpy
import socket
import sys

audit_type = runpy.run_path(sys.argv[1])['_ModelEgressAudit']
mode, target = sys.argv[2:4]
audit = audit_type('provider.key', 'fixture.pem', mode == 'cold')
assert Path('selection.json').read_bytes() == b'policy'
if target == 'clean':
    if mode == 'warm':
        try:
            audit.observation()
        except AssertionError:
            pass
        else:
            raise AssertionError('Check reported complete before the Run cut')
        audit.begin_run()
        assert Path('provider.key').read_bytes() == b'fixture'
    else:
        try:
            audit.begin_run()
        except AssertionError:
            pass
        else:
            raise AssertionError('Cold observation opened a physical Run')
    expected = {'python_check_events': [] if mode == 'warm' else None,
                'python_cold_events': [] if mode == 'cold' else None}
    assert audit.observation() == expected
else:
    try:
        if target == 'dns':
            socket.getaddrinfo('127.0.0.1', 443, socket.AF_INET, socket.SOCK_STREAM)
        else:
            os.close(os.open({'credential': 'provider.key', 'trust': 'fixture.pem'}[target], os.O_RDONLY))
    except AssertionError:
        assert audit.events == ['socket.getaddrinfo' if target == 'dns' else target]
    else:
        raise AssertionError('Unapproved startup or Saved operation was admitted')
    try:
        if mode == 'warm':
            audit.begin_run()
        else:
            audit.observation()
    except AssertionError:
        pass
    else:
        raise AssertionError('Suppressed audit failure disappeared from the observation')
'''
        child = SCRIPTS / 'fixtures/python-product-installed.py'
        with tempfile.TemporaryDirectory() as scratch:
            for name, body in [('selection.json', b'policy'), ('provider.key', b'fixture'), ('fixture.pem', b'fixture')]:
                (Path(scratch) / name).write_bytes(body)
            for mode in ('warm', 'cold'):
                for target in ('clean', 'credential', 'trust', 'dns'):
                    with self.subTest(mode=mode, target=target):
                        direct = subprocess.run(
                            [sys.executable, '-I', '-B', '-c', run_audit, child, mode, target],
                            cwd=scratch, capture_output=True, text=True, timeout=5,
                        )
                        self.assertEqual(direct.returncode, 0, direct.stderr)

    def test_reject_foreign_identity_same_process_and_real_cold_resend(self):
        for injected, reason in [('foreign', 'reuse its original Run'),
                                 ('same-process', 'reuse its original Run'),
                                 ('resend', 'Cold Saved reached')]:
            with self.subTest(injected=injected), tempfile.TemporaryDirectory() as scratch:
                with self.assertRaisesRegex(ValueError, reason):
                    self.observed_run(Path(scratch), injected)


    def test_reject_cold_ciphertext_change_later_generation_missing_raw_and_wrong_charge(self):
        for injected, reason in [('ciphertext', 'changed the original Model Store holdings'),
                                 ('generation', 'changed original Model Store record'),
                                 ('missing-raw', 'inventory for client_model_raw_responses'),
                                 ('capacity', 'charge disagrees')]:
            with self.subTest(injected=injected), tempfile.TemporaryDirectory() as scratch:
                with self.assertRaisesRegex(ValueError, reason):
                    self.observed_run(Path(scratch), injected)


    def test_usage_values_and_exact_retained_check_material_are_required(self):
        for injected, reason in [('usage-zero', 'accounting CID does not match'),
                                 ('usage-absent', 'accounting CID does not match'),
                                 ('foreign-material', 'Changed original Run task material digest'),
                                 ('material-gap', 'foreign Run task material chunks')]:
            with self.subTest(injected=injected), tempfile.TemporaryDirectory() as scratch:
                with self.assertRaisesRegex(ValueError, reason):
                    self.observed_run(Path(scratch), injected)


class InstalledCsvProjectTests(unittest.TestCase):
    def exercise(self, destination, fault=None):
        source = '9' * 40
        cohort = destination / 'cohort'
        consumer = destination / 'consumer/bin/python'
        environment = {'PATH': str(consumer.parent)}
        calls = []

        def run(name, command, *, cwd, env, timeout):
            self.assertEqual(command[:4], [consumer, '-I', '-B', destination / 'ci-python-installed-run.py'])
            self.assertEqual(env, environment)
            self.assertEqual(timeout, 180)
            options = dict(zip(command[5::2], command[6::2], strict=True))
            original = cwd.parent / 'initial.json'
            selected = options.get('--command')
            phase = options['--phase']
            self.assertTrue((cwd / 'actql.config.json').is_file())
            self.assertEqual(options['--cohort'], cohort / 'cohort.json')
            observed = {'pid': len(calls) + 1, 'first_close': True, 'phase': phase,
                        'case': options['--case'], 'facade': options['--facade'], 'command': selected,
                        'source': {'source_sha': options['--source']}}
            if phase == 'saved':
                self.assertEqual(options['--prior'], original)
                prior = json.loads(original.read_bytes())
                self.assertEqual(prior['phase'], 'initial')
                self.assertEqual(prior['command'], selected)
                if fault == 'same-process':
                    observed['pid'] = prior['pid']
            else:
                self.assertFalse(original.exists())
            if fault == 'close':
                observed['first_close'] = False
            if fault == 'foreign-source':
                observed['source']['source_sha'] = '5' * 40
            calls.append((options['--facade'], options['--case'], selected, phase))
            return wire(observed)

        accepted = ci.accept_installed_csv_projects(run, consumer, destination, cohort, source, environment)
        return calls, accepted

    def test_each_facade_uses_original_csv_projects_and_distinct_saved_processes(self):
        with tempfile.TemporaryDirectory() as temporary:
            calls, accepted = self.exercise(Path(temporary))
        self.assertEqual(len(calls), 14)
        wanted = [('original-one-table', 'small.sql', 'initial'),
                  ('original-one-table', 'small.sql', 'saved'),
                  ('two-tables', 'small.sql', 'initial'), ('two-tables', 'small.sql', 'saved'),
                  ('two-tables', 'other.sql', 'initial'), ('two-tables', 'other.sql', 'saved'),
                  ('invalid-second-declaration', None, 'refuse')]
        self.assertEqual(calls, [(facade, *selection) for facade in ('sync', 'async') for selection in wanted])
        self.assertEqual(len(accepted['phases']), len(calls))

    def test_csv_harness_refuses_cleanup_loss_foreign_source_or_same_process(self):
        for fault, message in [('close', 'Missing first close'), ('foreign-source', 'Missing first close'),
                               ('same-process', 'distinct original processes')]:
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as temporary:
                with self.assertRaisesRegex(ValueError, message):
                    self.exercise(Path(temporary), fault)


class InstalledNamedResultTests(unittest.TestCase):
    def observed(self, facade, phase):
        return {'mode': 'local', 'version': '0.0.0.dev0', 'phase': phase, 'case': 'named-results',
                'facade': facade, 'named_submission': True, 'same_name_reused': phase == 'initial',
                'changed_intent_refused': phase == 'initial',
                'pid': 41 + 2 * int(facade == 'async') + int(phase == 'resume'), 'results': ['before_change', 'after_change'],
                'submitted': phase == 'initial', 'original_run_reused': phase == 'resume',
                'first_close': True}

    def test_named_results_use_the_shared_fixture_and_one_original_receipt(self):
        consumer = Path('/installed/bin/python')
        env = {'PATH': '/installed/bin'}
        calls = []
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp)
            def run(name, args, **options):
                flags = dict(zip(args[5::2], args[6::2]))
                calls.append((flags['--facade'], flags['--phase']))
                self.assertEqual(args[:3], [consumer, '-I', '-B'])
                self.assertEqual(args[3:5], [destination / 'ci-python-installed-run.py',
                                             destination / 'python-product-installed.py'])
                self.assertEqual((flags['--mode'], flags['--facade'], flags['--case']),
                                 ('local', flags['--facade'], 'named-results'))
                self.assertEqual(flags['--named-results-fixture'].read_bytes(),
                                 (ci.ROOT / 'scripts/fixtures/named-result-publication.json').read_bytes())
                self.assertEqual(flags['--receipt'], options['cwd'] / 'original.json')
                self.assertEqual(options['cwd'], destination / 'named-results' / flags['--facade'])
                self.assertIs(options['env'], env)
                return json.dumps(self.observed(flags['--facade'], flags['--phase']))
            ci.accept_installed_named_results(run, consumer, destination, '0.0.0.dev0', env)
        self.assertEqual(calls, [('sync', 'initial'), ('sync', 'resume'),
                                 ('async', 'initial'), ('async', 'resume')])

    def test_named_results_refuse_missing_outcomes_close_failure_or_resubmission(self):
        for changed in ({'results': ['before_change', 'before_change']},
                        {'first_close': False}, {'submitted': True},
                        {'original_run_reused': False}, {'pid': 41},
                        {'named_submission': False}, {'same_name_reused': True}, {'facade': 'async'}):
            calls = []
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as tmp:
                def run(name, args, **options):
                    phase = args[args.index('--phase') + 1]
                    calls.append(phase)
                    report = self.observed('sync', phase)
                    return json.dumps(report if phase == 'initial' else report | changed)
                with self.assertRaisesRegex(ValueError, 'original Saved'):
                    ci.accept_installed_named_results(run, Path('/python'), Path(tmp), '0.0.0.dev0', {})
            self.assertEqual(calls, ['initial', 'resume'])


class InstalledSavedControlTests(unittest.TestCase):
    source = 'a' * 40
    cohort = {'module_sha256': 'b' * 64, 'image_sha256': 'c' * 64}

    def run_controls(self, directory, *, change=None):
        identity = dict(source=self.source, module=self.cohort['module_sha256'],
                        image=self.cohort['image_sha256'])
        records = [
            dict(pid=41, first_close=True, rows=1, core_cancellation=[{'phase': 'core'}],
                 hash_cancellation=[{'phase': 'hash'}], successful_reads=[{'core_turns': 2}] * 2),
            dict(pid=42, phase='warm', first_close=True),
            dict(pid=43, passed=True, cases=1, originalTrapCode=11, outOfFuelTrapCode=11, firstClose=True,
                 normalFenced=True, sameStore=True, newSubmission=False, installedSourceOverlay=False,
                 injections=[{'before': 10, 'after': 0, 'actualCurrentResult': 5,
                              'ticket': 7, 'operation': 5}]),
            dict(pid=44, phase='recover', first_close=True, same_saved=True, replayed=False),
        ]
        calls = []
        if change is not None:
            index, fields = change
            records[index].update(fields)

        def run(name, args, **options):
            calls.append((name, args, options))
            return json.dumps(identity | records[len(calls) - 1]).encode()

        return calls, lambda: ci.accept_installed_saved(
            run, Path('/consumer/bin/python'), directory, self.source, self.cohort, {'ORIGINAL': 'env'})

    def test_same_installed_cohort_for_continuation_and_separate_stop_recovery(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            calls, agreement = self.run_controls(directory)
            report = agreement()
            self.assertEqual([name for name, _, _ in calls], [
                'installed-saved-continuation', 'installed-saved-fuel-warm',
                'installed-saved-fuel-interruption', 'installed-saved-fuel-recovery',
            ])
            for _, args, options in calls:
                self.assertEqual(args[:3], [Path('/consumer/bin/python'), '-I', '-B'])
                self.assertEqual(args[3].parent, directory / 'saved-read')
                self.assertTrue(args[3].is_file())
                self.assertEqual(options['env'], {'ORIGINAL': 'env'})
                self.assertEqual(options['timeout'], 180)
            self.assertEqual(calls[2][1][4:], [directory / 'saved-read' / 'fuel', self.source])
            self.assertEqual(report['fuel_recovery_pid'], 44)
            self.assertTrue(report['original_first_closes_returned'])

    def test_foreign_or_incomplete_controls_stop_before_later_process(self):
        for index, fields in [
                (0, {'module': '0' * 64}), (0, {'hash_cancellation': []}),
                (0, {'successful_reads': [{'core_turns': 2}]}),
                (1, {'pid': 41}), (1, {'first_close': False}),
                (2, {'originalTrapCode': 0}), (2, {'originalTrapCode': 12}), (2, {'outOfFuelTrapCode': None}),
                (2, {'outOfFuelTrapCode': 12}), (2, {'outOfFuelTrapCode': True}),
                (2, {'sameStore': False}),
                (2, {'injections': []}), (2, {'firstClose': False}),
                (2, {'injections': [{'before': 10, 'after': 0, 'actualCurrentResult': 0,
                                     'ticket': 7, 'operation': 5}]}),
                (2, {'injections': [{'before': 10, 'after': 0, 'actualCurrentResult': 6,
                                     'ticket': 7, 'operation': 5}]}),
                (3, {'replayed': True})]:
            with self.subTest(index=index, fields=fields), tempfile.TemporaryDirectory() as temp:
                calls, agreement = self.run_controls(Path(temp), change=(index, fields))
                with self.assertRaises(ValueError):
                    agreement()
                self.assertEqual(len(calls), index + 1)


class InstalledNumericReductionTests(unittest.TestCase):
    def test_same_cohort_numeric_saved_requires_a_distinct_process(self):
        source, module = 'a' * 40, 'b' * 64
        cases = ['pivot', 'sum', 'count', 'parse-timestamp']
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
            def component(run, python, module, receipt, selected, *, platform_artifact=None):
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
            compiled = []
            staged = []
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
                    self.assertEqual(reached, builds)
                    selected = Path(args[args.index('--core-receipt') + 1])
                    self.assertEqual(Path(json.loads(selected.read_text())['module']), builds[0])
                    compiled.append(Path(args[args.index('--destination') + 1]))
                if '--platform-runtime' in args:
                    self.assertEqual(len(compiled), 1)
                    self.assertEqual(Path(args[args.index('--image-receipt') + 1]),
                                     compiled[0] / 'image-receipt.json')
                    staged.append(Path(args[args.index('--destination') + 1]))
                return subprocess.CompletedProcess(args, 0, stdout=b'{}', stderr=b'')
            def component(run, python, module, receipt, selected, *, platform_artifact=None):
                self.assertEqual(builds, [module])
                self.assertEqual(Path(json.loads(receipt.read_text())['module']), module)
                self.assertEqual(python, destination / 'builder/bin/python')
                self.assertEqual(selected, destination)
                reached.append(module)
            def lifecycle(run, python, module, receipt, selected, *, platform_artifact):
                self.assertEqual(staged, [destination / 'artifact'])
                self.assertEqual(platform_artifact, staged[0])
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
    image_digest = 'c' * 64

    def original(self, path):
        module, receipt, _ = SubmissionObservationTests().original(path)
        artifact = path / 'artifact'
        artifact.mkdir()
        original = json.loads(receipt.read_bytes())
        (artifact / 'artifact.json').write_text(json.dumps({
            'source_sha': original['source_sha'],
            'module': {'sha256': original['module_sha256']},
            'compiled_image': {'runtime_allocation': 'platform', 'sha256': self.image_digest},
        }))
        return module, receipt

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
                **({'atomic_precommit_writer_exclusion': True,
                    'image_sha256': self.image_digest, 'first_core_closed': True,
                    'saved_first_core_closed': True} if name in ('succeeded-result-saved', 'publication-unknown', 'task-drive-mixed') else {}),
                **({'core_owned_lifecycle': True, 'initial_quantum': 1, 'initial_drives_per_task': 8, 'continuation_quantum': 256, 'original_tasks': 2, 'actual_initial_quantum_drives': 16, 'observed_phase_transitions': 2, 'monotonic_progress': True} if name == 'task-drive-mixed' else {}),
                **({'commit_reply_loss_readback_without_reexecution': True} if name == 'publication-unknown' else {})}

    def test_same_original_controls_without_build_or_installed_claim(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp).resolve()
            module, receipt = self.original(path)
            calls = []
            def run(name, args, **options):
                self.assertEqual(args[0], Path('/selected/python'))
                self.assertEqual(args[2], module)
                self.assertEqual(options, {'timeout': 120 if name == 'cancellation-drive-start' else 300})
                calls.append((name, args))
                return json.dumps(self.observation(name, module)).encode()
            result = ci.accept_public_lifecycle(run, Path('/selected/python'), module, receipt, path, platform_artifact=path / 'artifact')
            self.assertEqual([name for name, _ in calls],
                ['cancellation-saved', 'cancellation-precommit', 'state-unknown', 'state-partial-close',
                 'succeeded-result-saved', 'publication-unknown', 'task-drive-mixed', 'cancellation-drive-start'])
            self.assertEqual([args[-1] for _, args in calls[:4]],
                ['process-state', 'precommit-state', 'fault-state', 'partial-state'])
            by_name = dict(calls)
            self.assertEqual(by_name['publication-unknown'][4], 'commit-unknown')
            self.assertEqual(by_name['task-drive-mixed'][4], 'task-drive-mixed')
            self.assertEqual(by_name['cancellation-drive-start'][-1], 'drive-start-state')
            for name in ('succeeded-result-saved', 'publication-unknown', 'task-drive-mixed'):
                self.assertEqual(by_name[name][-2:], ['--platform-artifact', path / 'artifact'])
            self.assertEqual(result['image_sha256'], self.image_digest)
            self.assertEqual(len({args[3] for _, args in calls}), len(calls))
            self.assertFalse(result['installed_wheel_acceptance'])
            self.assertFalse(result['normal_image_acceptance'])
            self.assertEqual(json.loads((path / 'public-lifecycle.json').read_text()), result)
            self.assertFalse((path / 'acceptance.json').exists())

    def test_changed_or_missing_component_refuses_without_receipt_or_next_control(self):
        for change in ({'success': False}, {'actualCases': 0}, {'actualCases': True},
                       {'module_sha256': 'b' * 64}, {'case': 'unrelated'}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp).resolve()
                module, receipt = self.original(path)
                calls = []
                def run(name, args, **options):
                    calls.append(name)
                    return json.dumps({**self.observation(name, module), **change}).encode()
                with self.assertRaisesRegex(ValueError, 'Incomplete original'):
                    ci.accept_public_lifecycle(run, Path('/python'), module, receipt, path, platform_artifact=path / 'artifact')
                self.assertEqual(calls, ['cancellation-saved'])
                self.assertFalse((path / 'public-lifecycle.json').exists())
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp).resolve()
            module, receipt = self.original(path)
            def missing_atomic(name, args, **options):
                observed = self.observation(name, module)
                observed.pop('atomic_precommit_writer_exclusion', None)
                return json.dumps(observed).encode()
            with self.assertRaisesRegex(ValueError, 'Incomplete original atomic'):
                ci.accept_public_lifecycle(missing_atomic, Path('/python'), module, receipt, path, platform_artifact=path / 'artifact')
            self.assertFalse((path / 'public-lifecycle.json').exists())
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp).resolve()
            module, receipt = self.original(path)
            def missing_recovery(name, args, **options):
                observed = self.observation(name, module)
                observed.pop('commit_reply_loss_readback_without_reexecution', None)
                return json.dumps(observed).encode()
            with self.assertRaisesRegex(ValueError, 'Incomplete original publication recovery'):
                ci.accept_public_lifecycle(missing_recovery, Path('/python'), module, receipt, path, platform_artifact=path / 'artifact')
            self.assertFalse((path / 'public-lifecycle.json').exists())

    def test_succeeded_controls_require_same_platform_image_and_first_closes(self):
        for change in ({'image_sha256': 'd' * 64}, {'first_core_closed': False},
                       {'saved_first_core_closed': False}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp).resolve()
                module, receipt = self.original(path)
                calls = []
                def run(name, args, **options):
                    calls.append(name)
                    observed = self.observation(name, module)
                    if name == 'succeeded-result-saved':
                        observed.update(change)
                    return json.dumps(observed).encode()
                with self.assertRaisesRegex(ValueError, 'Incomplete original platform image'):
                    ci.accept_public_lifecycle(run, Path('/python'), module, receipt, path,
                        platform_artifact=path / 'artifact')
                self.assertEqual(calls[-1], 'succeeded-result-saved')
                self.assertNotIn('publication-unknown', calls)
                self.assertFalse((path / 'public-lifecycle.json').exists())

    def test_task_drive_requires_bounded_original_task_facts_before_next_control(self):
        for change in ({'core_owned_lifecycle': False}, {'initial_quantum': True}, {'initial_quantum': 2}, {'initial_drives_per_task': 7}, {'continuation_quantum': 128}, {'actual_initial_quantum_drives': 15}, {'observed_phase_transitions': 1}, {'monotonic_progress': False},
                       {'original_tasks': True}, {'original_tasks': 1}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp).resolve()
                module, receipt = self.original(path)
                calls = []
                def run(name, args, **options):
                    calls.append(name)
                    observed = self.observation(name, module)
                    return json.dumps({**observed, **change} if name == 'task-drive-mixed' else observed).encode()
                with self.assertRaisesRegex(ValueError, 'Incomplete original task-drive'):
                    ci.accept_public_lifecycle(run, Path('/python'), module, receipt, path, platform_artifact=path / 'artifact')
                self.assertEqual(calls[-1], 'task-drive-mixed')
                self.assertNotIn('cancellation-drive-start', calls)
                self.assertFalse((path / 'public-lifecycle.json').exists())

    def test_original_module_and_failure_cannot_be_substituted(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp).resolve()
            module, receipt = self.original(path)
            original = RuntimeError('original public lifecycle failure')
            def failed(*args, **kwargs):
                raise original
            with self.assertRaises(RuntimeError) as caught:
                ci.accept_public_lifecycle(failed, Path('/python'), module, receipt, path, platform_artifact=path / 'artifact')
            self.assertIs(caught.exception, original)
            module.write_bytes(b'changed original')
            with self.assertRaisesRegex(ValueError, 'original Core'):
                ci.accept_public_lifecycle(
                    lambda *args, **kwargs: self.fail('Changed Core reached consumer'),
                    Path('/python'), module, receipt, path, platform_artifact=path / 'artifact')
            self.assertFalse((path / 'public-lifecycle.json').exists())


class InstalledAuditTests(unittest.TestCase):
    def test_sdk_binding_receipt_comes_from_the_installed_wheel_member(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            wheels = directory / 'wheels'
            wheels.mkdir()
            prefix = directory / 'consumer'
            site = prefix / 'site-packages'
            member = 'actql_sdk/_local_release_binding.json'
            installed_binding = site / member
            installed_binding.parent.mkdir(parents=True)
            binding = b'{"fixture":"original SDK binding"}'
            installed_binding.write_bytes(binding)
            records = []
            installs = []
            for name in ('actql', 'actql-sdk', 'actql-local-runtime'):
                wheel = wheels / (name + '.whl')
                with zipfile.ZipFile(wheel, 'w') as archive:
                    if name == 'actql-sdk':
                        archive.writestr(member, binding)
                raw = wheel.read_bytes()
                digest = hashlib.sha256(raw).hexdigest()
                records.append({'distribution': name, 'file': wheel.name,
                                'bytes': len(raw), 'sha256': digest})
                installs.append({'metadata': {'name': name}, 'is_direct': True,
                                 'download_info': {'url': wheel.resolve().as_uri(),
                                                   'archive_info': {'hashes': {'sha256': digest}}}})
            (directory / 'cohort.json').write_text(json.dumps({'wheels': records, 'package_version': '0.0.3'}))
            report = directory / 'pip-report.json'
            report.write_text(json.dumps({'install': installs}))
            distribution = SimpleNamespace(version='0.0.3', locate_file=lambda _: site)
            with (patch.object(audit.metadata, 'distribution', return_value=distribution),
                  patch.object(audit.importlib.util, 'find_spec',
                               return_value=SimpleNamespace(origin=site / 'actql_sdk' / '__init__.py')),
                  patch.object(audit.sys, 'prefix', str(prefix))):
                result = audit.audit(directory, report)
                self.assertEqual(result['sdk_runtime_binding'], {
                    'member': member, 'bytes': len(binding), 'sha256': hashlib.sha256(binding).hexdigest(),
                    'wheel_sha256': records[1]['sha256'],
                })
                installed_binding.write_bytes(b'{"fixture":"changed SDK binding!"}')
                with self.assertRaisesRegex(AssertionError, 'Installed payload differs: ' + member):
                    audit.audit(directory, report)

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

    def test_initial_cancellation_runs_once_without_installing_profilers(self):
        import threading
        runner = load('ci_installed_unprofiled_cancel', SCRIPTS / 'fixtures/ci-python-installed-run.py')
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'python-product-installed.py'
            target.write_text(
                'import sys, threading\nfrom pathlib import Path\n'
                'assert sys.getprofile() is None and threading.getprofile() is None\n'
                'with Path(__file__).with_name("calls").open("a") as output:\n'
                '    output.write(sys.argv[sys.argv.index("--facade") + 1] + "\\n")\n')
            with patch.object(sys, 'setprofile') as process, \
                    patch.object(threading, 'setprofile') as worker:
                for facade in ('sync', 'async'):
                    args = [str(target), '--mode', 'local', '--facade', facade,
                            '--case', 'cancellation', '--phase', 'initial']
                    with patch.object(sys, 'argv', args):
                        runner.run_consumer(target)
            process.assert_not_called()
            worker.assert_not_called()
            self.assertEqual(target.with_name('calls').read_text(), 'sync\nasync\n')

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
        client = MagicMock(spec_set=['__enter__', '__exit__', 'new_submission', 'start_source',
                                     'lookup_submission', 'attach'])
        client.__enter__.return_value = client
        client.__exit__.return_value = False
        runs = [MagicMock(ref={'original': index}) for index in (1, 2)]
        for run in runs:
            run.wait.return_value = {'status': 'succeeded'}
            run.result.return_value.all.return_value = [{'n': 1}]
        client.new_submission.side_effect = [{'submission': 1}, {'submission': 2}]
        client.start_source.side_effect = runs
        public = ModuleType('actql')
        public.Client = SimpleNamespace(open=MagicMock(return_value=client))
        return consumer, public, client, runs

    def test_success_records_only_closed_boundaries_without_changing_public_calls(self):
        consumer, public, client, runs = self.fixture()
        stream = io.StringIO()
        with tempfile.TemporaryDirectory() as tmp, patch.dict(sys.modules, {'actql': public}), \
                patch.object(consumer.sys, 'stderr', stream), \
                patch.object(consumer, 'monotonic_ns', create=True,
                             side_effect=[1000] + list(range(1000, 1200, 10))) as clock:
            observed = consumer._sync('private-version', 'initial', Path(tmp) / 'original.json')
        self.assertIsNone(observed)
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
        consumer, public, client, _ = self.fixture()
        original = RuntimeError('original first-start failure')
        client.start_source.side_effect = original
        class BrokenStream:
            def write(self, value):
                raise KeyboardInterrupt('optional output refused')
        with tempfile.TemporaryDirectory() as tmp, patch.dict(sys.modules, {'actql': public}), \
                patch.object(consumer.sys, 'stderr', BrokenStream()):
            with self.assertRaises(RuntimeError) as raised:
                consumer._sync('fixture', 'initial', Path(tmp) / 'original.json')
        self.assertIs(raised.exception, original)
        client.start_source.assert_called_once()
        self.assertEqual(client.__exit__.call_count, 1)
        self.assertIs(client.__exit__.call_args.args[1], original)

    def test_saved_route_has_no_initial_markers_or_new_submission(self):
        consumer, public, client, runs = self.fixture()
        saved = {'submission': {'same': 'original'}, 'run': runs[0].ref}
        client.lookup_submission.return_value = {'kind': 'ready', 'admission': {'ref': runs[0].ref}}
        client.attach.return_value = runs[0]
        stream = io.StringIO()
        with patch.dict(sys.modules, {'actql': public}), patch.object(consumer, '_saved', return_value=saved), \
                patch.object(consumer.sys, 'stderr', stream), \
                patch.object(consumer, 'monotonic_ns', create=True) as clock:
            self.assertIsNone(consumer._sync('fixture', 'resume', Path('/unused/receipt')))
        self.assertEqual(stream.getvalue(), '')
        clock.assert_not_called()
        client.start_source.assert_not_called()
        client.attach.assert_called_once_with(saved['run'])
        client.__exit__.assert_called_once_with(None, None, None)

    def test_installed_operations_reject_existing_process_or_thread_instrumentation(self):
        consumer, public, client, _ = self.fixture()
        for scope, hook in ((consumer.sys, 'getprofile'), (consumer.sys, 'gettrace'),
                            (consumer.threading, 'getprofile'), (consumer.threading, 'gettrace')):
            for facade in ('sync', 'async'):
                for case, message in (('execution', 'uninstrumented installed execution'),
                                      ('cancellation', 'uninstrumented installed cancellation')):
                    with self.subTest(scope=scope.__name__, hook=hook, facade=facade, case=case), \
                            patch.object(scope, hook, return_value=object()), \
                            patch.dict(sys.modules, {'actql': public}), \
                            patch.object(consumer.metadata, 'version', return_value='fixture'):
                        with self.assertRaisesRegex(AssertionError, message):
                            consumer.installed('fixture', 'local', facade=facade, phase='initial',
                                               case=case, receipt=Path('/unused/receipt'))
        public.Client.open.assert_not_called()
        client.start_source.assert_not_called()

    def test_unselected_or_foreign_marker_cannot_invoke_foreign_comparison_or_emit(self):
        consumer, _, _, _ = self.fixture()
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
        consumer, _, _, _ = self.fixture()
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
        consumer, public, client, _ = self.fixture()
        original = RuntimeError('original first-start failure')
        client.start_source.side_effect = original
        stream = io.StringIO()
        with tempfile.TemporaryDirectory() as tmp, patch.dict(sys.modules, {'actql': public}), \
                patch.object(consumer.sys, 'stderr', stream), \
                patch.object(consumer, 'monotonic_ns', create=True, side_effect=KeyboardInterrupt) as clock:
            with self.assertRaises(RuntimeError) as raised:
                consumer._sync('fixture', 'initial', Path(tmp) / 'original.json')
        self.assertIs(raised.exception, original)
        clock.assert_called_once_with()
        self.assertEqual(stream.getvalue(), '')
        self.assertEqual(client.__exit__.call_count, 1)
        self.assertIs(client.__exit__.call_args.args[1], original)


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
