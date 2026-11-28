"""Run the ordinary installed Portable Model case inside the existing wheel audit."""

from dataclasses import asdict
from hashlib import sha256
from pathlib import Path
import json
import os
import re
import secrets
import ssl
import subprocess

from python_model_loopback_peer import controlled_model_peer
from python_model_store_observation import observe_model_holdings, observe_model_loss


FIXTURES = Path(__file__).resolve().parent / 'fixtures'
PROFILE_ORIGINAL = FIXTURES.parents[1] / 'portability/corpus/model-response-profiles.json'
_CREDENTIAL = 'provider.key'
_TRUST = 'fixture.pem'


def wire(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, sort_keys=True,
                      separators=(',', ':')).encode('utf-8')


def write_fixture(path, body):
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as output:
        output.write(body)


def build_protected_case(root, fixture, profile, endpoint, runtime_image_sha256, secret, pem):
    """Materialize the original protected documents for one fresh state root."""
    if re.fullmatch('[0-9a-f]{64}', runtime_image_sha256) is None:
        raise ValueError('Portable Model fixture requires the verified image digest')
    root.mkdir(mode=0o700)
    project, deployment = root / 'project', root / 'deployment'
    project.mkdir(mode=0o700)
    deployment.mkdir(mode=0o700)
    program_wire = wire(fixture['program'])
    case = {'program_sha256': sha256(program_wire).hexdigest(),
            'result_name': 'answer', 'rows': fixture['expect'],
            'credential_file': _CREDENTIAL, 'ca_file': _TRUST}
    write_fixture(root / 'program.json', program_wire)
    for name, body in fixture['project'].items():
        write_fixture(project / name, wire(body))
    # Only the selected installed image and peer address are set at runtime.
    profile = json.loads(wire(profile))
    profile.pop('self_cid', None)
    profile['operation']['endpoint'] = endpoint
    profile['limits']['request_bytes'] = 1000
    artifact = 'sha256:' + runtime_image_sha256
    profile['adapter'].update(builder_id='actql/python-portable-chat',
                              codec_id='actql/openai-chat-envelope', build_artifact_cid=artifact)
    profile['completion'].update(validator_id='actql/openai-chat-envelope',
                                 validator_artifact_cid=artifact)
    profile['task'].update(fixture['task_binding'])
    profile['self_cid'] = 'sha256:' + sha256(wire(profile)).hexdigest()
    files = {**fixture['deployment'], 'response-profile.json': profile}
    files['provider.json'] = {**files['provider.json'], 'endpoint': endpoint,
                             'response_profile_cid': profile['self_cid']}
    files['selection.json'] = {**files['selection.json'], 'profile_cid': profile['self_cid'],
                              'tls_ca': {'file': _TRUST, 'sha256': 'sha256:' + sha256(pem).hexdigest()}}
    source = fixture.get('csv_source')
    if source is not None:
        connection, resource = source['connection'], source['resource']
        connector = fixture['project']['connectors.json']['connections'][connection]
        entry = connector['tables'][resource]
        data = project / 'data'
        data.mkdir(mode=0o700)
        write_fixture(data / entry['path'], source['wire'].encode('utf-8'))
        case['source_file'] = entry['path']
        declaration = wire({
            'version': 'actql-local-source-policy-binding/0.1',
            'connection': connection, 'resource': resource, 'root': str(data),
            'connectors_sha256': 'sha256:' + sha256((project / 'connectors.json').read_bytes()).hexdigest(),
            'data_classification': source['classification'],
        })
        name = 'source-catalog.json'
        write_fixture(deployment / name, declaration)
        files['selection.json']['source_catalog'] = {
            'file': name, 'sha256': 'sha256:' + sha256(declaration).hexdigest(),
        }
    write_fixture(root / 'case.json', wire(case))
    for name, body in files.items():
        write_fixture(deployment / name, wire(body))
    write_fixture(deployment / _CREDENTIAL, secret)
    write_fixture(deployment / _TRUST, pem)
    return case


def checked_request(request, source_value=None):
    messages = request.get('messages')
    if (request.get('model') != 'deployed-chat' or request.get('stream') is not False
            or request.get('n') != 1 or not isinstance(messages, list) or len(messages) != 2
            or [message.get('role') for message in messages] != ['system', 'user']
            or type(messages[0].get('content')) is not str
            or json.loads(messages[1].get('content')) != ({} if source_value is None else source_value)):
        raise ValueError('Unexpected controlled Portable Model request')


def require_model_child(record, facade, phase, version, rows_sha256, previous):
    cold = phase == 'resume'
    if (record.get('mode') != 'local' or record.get('case') != 'portable-model'
            or record.get('version') != version or record.get('facade') != facade
            or record.get('phase') != phase or type(record.get('pid')) is not int
            or record['pid'] <= 0 or record.get('first_close') is not True
            or record.get('original_saved_first') is not cold
            or record.get('rows_sha256') != rows_sha256
            or 'python_check_events' not in record
            or record['python_check_events'] != (None if cold else [])
            or 'python_cold_events' not in record
            or record.get('python_cold_events') != ([] if cold else None)
            or record.get('check_verdict') != (None if cold else 'verified')):
        raise ValueError('Incomplete installed Portable Model consumer')
    reference, delivery = record.get('run'), record.get('delivery')
    def digest(value, prefix=''):
        return type(value) is str and re.fullmatch(prefix + '[0-9a-f]{64}', value) is not None
    if (not isinstance(reference, dict) or not digest(reference.get('runDefinitionCid'), 'sha256:')
            or not isinstance(delivery, dict) or type(delivery.get('bytes')) is not int
            or delivery['bytes'] <= 0 or not digest(delivery.get('sha256'))
            or type(delivery.get('attempt_id')) is not str or not delivery['attempt_id']
            or not all(digest(delivery.get(key), 'sha256:')
                       for key in ('artifact_cid', 'manifest_cid', 'receipt_cid'))):
        raise ValueError('Missing original Model Result custody')
    if previous is not None:
        if (record['pid'] == previous['pid'] or reference != previous['run']
                or delivery['attempt_id'] == previous['delivery']['attempt_id']
                or any(delivery[key] != previous['delivery'][key]
                       for key in ('artifact_cid', 'manifest_cid', 'bytes', 'sha256'))):
            raise ValueError('Cold Portable Model did not reuse its original Run and Result')


def _accept_response_loss(run, consumer, destination, version, env, fixture_root, pids,
                          context, fixture, profile, image_sha256, reply, pem, *, facade):
    work = fixture_root / ('response-loss' if facade == 'async' else 'response-loss-sync')
    secret = secrets.token_urlsafe(24).encode('ascii')
    task = fixture['task_binding']['contract_cid']
    provider = fixture['deployment']['provider.json']['provider_id']
    store = work / 'project/state/state/client.sqlite3'
    record = work / 'original.json'
    with controlled_model_peer(context, checked_request, b'Bearer ' + secret, reply,
                               lose_response=True) as (endpoint, observe):
        case = build_protected_case(work, fixture, profile, endpoint, image_sha256, secret, pem)

        def child(phase):
            result = json.loads(run(f'{facade}-model-loss-{phase}',
                [consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
                 destination / 'python-product-installed.py', '--version', version, '--mode', 'local',
                 '--case', 'portable-model-loss', '--facade', facade, '--phase', phase,
                 '--receipt', record, '--model-fixture', work],
                cwd=work / 'project', env=env, timeout=180))
            cold = phase == 'resume'
            expected = {'mode': 'local', 'case': 'portable-model-loss', 'version': version, 'facade': facade,
                        'phase': phase, 'first_close': True, 'cold_original_lookup': cold,
                        'worker_stopped_without_status': None if cold else True,
                        'check_verdict': None if cold else 'verified',
                        'python_check_events': None if cold else [],
                        'python_cold_events': [] if cold else None}
            if (any(key not in result or result[key] != value for key, value in expected.items())
                    or result['first_close'] is not True or result['cold_original_lookup'] is not cold
                    or result['worker_stopped_without_status'] is not (None if cold else True)
                    or type(result.get('pid')) is not int or result['pid'] <= 0 or result['pid'] in pids
                    or type(result.get('run')) is not dict or type(result.get('submission_cid')) is not str
                    or re.fullmatch(r'sha256:[0-9a-f]{64}', result['submission_cid']) is None
                    or 'state' not in result
                    or (type(result['state']) is not dict if cold else result['state'] is not None)):
                raise ValueError('Incomplete installed Portable Model loss consumer')
            pids.add(result['pid'])
            return result

        warm = child('initial')
        warm_peer = observe()
        if ((warm_peer.tcp, warm_peer.tls, warm_peer.application_connections, warm_peer.posts,
             warm_peer.partial_responses) != (1, 1, 1, 1, 1)
                or len(warm_peer.request_hashes) != 1 or warm_peer.rejected
                or warm_peer.trust_alerts or warm_peer.ambiguous_handshake_failures):
            raise ValueError('Expected one original controlled HTTPS response loss')
        durable = observe_model_loss(store, warm['run'], warm['submission_cid'], task, provider)
        program = work / 'program.json'
        if sha256(program.read_bytes()).hexdigest() != case['program_sha256']:
            raise ValueError('Selected Portable Model Program changed during the response loss')
        program.unlink()
        cold = child('resume')
        if observe() != warm_peer:
            raise ValueError('Cold reconciliation reached the original controlled Model peer')
        if (cold['run'] != warm['run'] or cold['submission_cid'] != warm['submission_cid']
                or cold['state'] != durable['state']):
            raise ValueError('Cold reconciliation differs from the durably stopped original')
        if observe_model_loss(store, warm['run'], warm['submission_cid'], task, provider) != durable:
            raise ValueError('Cold reconciliation changed the original Model Store holdings')
    return {'phases': [warm, cold], 'warm_peer': asdict(warm_peer), 'cold_peer_unchanged': True,
            'original_before_cold': durable, 'cold_original_unchanged': True}


def accept_installed_portable_model(run, consumer: Path, destination: Path, version: str,
                                    env: dict[str, str], image_sha256: str, *,
                                    source: bool = False) -> dict:
    fixture_wire = (FIXTURES / 'python-portable-model-case.json').read_bytes()
    loss_fixture = json.loads(fixture_wire)
    if source:
        fixture_wire = (FIXTURES / 'python-portable-model-source-case.json').read_bytes()
    fixture = json.loads(fixture_wire)
    source_value = fixture['csv_source']['request_value'] if source else None
    profile = json.loads(PROFILE_ORIGINAL.read_bytes())['cases'][0]['body']
    reply = wire(fixture['reply'])
    reported_usage = fixture['reply']['usage']
    expected_usage = (reported_usage.get('prompt_tokens'), reported_usage.get('completion_tokens'))
    reservation = fixture['deployment']['selection.json']['attempt']
    fixture_root = destination / 'portable-model'
    fixture_root.mkdir(mode=0o700)
    cert, private = fixture_root / 'peer.pem', fixture_root / 'peer-key.pem'
    subprocess.run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-days', '1', '-subj', '/CN=127.0.0.1', '-addext',
                    'subjectAltName=IP:127.0.0.1', '-keyout', private, '-out', cert],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, private)
    private.unlink()
    pem = cert.read_bytes()
    results = []
    pids = set()
    for facade in ('sync', 'async'):
        work = fixture_root / facade
        # Each facade has its own installation, secret, endpoint and journal.
        secret = secrets.token_urlsafe(24).encode('ascii')
        with controlled_model_peer(context, lambda request: checked_request(request, source_value),
                                   b'Bearer ' + secret, reply) as (endpoint, observe):
            case = build_protected_case(work, fixture, profile, endpoint, image_sha256, secret, pem)
            expected_rows = sha256(wire(case['rows'])).hexdigest()
            records = []
            warm_peer = None
            warm_holdings = None
            for phase in ('initial', 'resume'):
                observed = json.loads(run(f'{facade}-model-{phase}',
                    [consumer, '-I', '-B', destination / 'ci-python-installed-run.py',
                     destination / 'python-product-installed.py', '--version', version, '--mode', 'local',
                     '--case', 'portable-model', '--facade', facade, '--phase', phase,
                     '--receipt', work / 'original.json', '--model-fixture', work],
                    cwd=work / 'project', env=env, timeout=180))
                require_model_child(observed, facade, phase, version, expected_rows, records[0] if records else None)
                if source:
                    expected_opens = 1 if phase == 'initial' else 0
                    if (type(observed.get('python_source_opens')) is not int
                            or observed['python_source_opens'] != expected_opens
                            or observed.get('python_source_unchanged') is not True):
                        raise ValueError('Installed Model did not preserve the original Source lifecycle')
                    original = work / 'project/data' / case['source_file']
                    if original.read_bytes() != fixture['csv_source']['wire'].encode('utf-8'):
                        raise ValueError('Installed Model changed the original Source bytes')
                if observed['pid'] in pids:
                    raise ValueError('Portable Model consumer reused a process')
                pids.add(observed['pid'])
                records.append(observed)
                peer = observe()
                if phase == 'initial':
                    if ((peer.tcp, peer.tls, peer.application_connections, peer.posts) != (1, 1, 1, 1)
                            or peer.rejected or peer.trust_alerts or peer.ambiguous_handshake_failures
                            or peer.partial_responses or len(peer.request_hashes) != 1):
                        raise ValueError('Expected exactly one controlled Portable Model HTTPS exchange')
                elif peer != warm_peer:
                    raise ValueError('Cold Saved reached the original controlled Model peer')
                holdings = observe_model_holdings(work / 'project/state/state/client.sqlite3', observed['run'],
                    fixture['task_binding']['contract_cid'], fixture['deployment']['provider.json']['provider_id'],
                    expected_usage=expected_usage, reservation=reservation)
                if phase == 'initial':
                    warm_peer = peer
                    warm_holdings = holdings
                    if sha256((work / 'program.json').read_bytes()).hexdigest() != case['program_sha256']:
                        raise ValueError('Selected Portable Model Program changed during the warm operation')
                    (work / 'program.json').unlink()
                elif holdings != warm_holdings:
                    raise ValueError('Cold Saved changed the original Model Store holdings')
            results.append({'facade': facade, 'phases': records,
                            'warm_peer': asdict(warm_peer), 'cold_peer_unchanged': True,
                            'model_holdings': warm_holdings, 'cold_model_holdings_unchanged': True})
    losses = {
        facade: _accept_response_loss(run, consumer, destination, version, env, fixture_root, pids,
            context, loss_fixture, profile, image_sha256, wire(loss_fixture['reply']), pem, facade=facade)
        for facade in ('async', 'sync')
    }
    return {'fixture_sha256': sha256(fixture_wire).hexdigest(), 'image_sha256': image_sha256,
            'peer_response_sha256': sha256(reply).hexdigest(), 'facades': results,
            **({'source_backed': True} if source else {}),
            'response_loss': losses['async'], 'sync_response_loss': losses['sync']}
