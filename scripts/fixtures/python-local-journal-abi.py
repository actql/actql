"""Fixed real-Wasm/same-SQLite observer consumer; not public admission/ACK."""
import hashlib
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory

from python_local_run_inputs import ENVIRONMENT, CONFIGURATION, encode

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'packages/python-sdk/src'))
from actql_sdk._local_core import LocalCore, LocalCoreError, LocalCoreResources
from actql_sdk._local_preparation import LocalPreparation
from actql_sdk._local_run import LocalRunCustody
from actql_sdk._local_storage import ByteWrite, ByteFence, LocalByteStore

module = Path(sys.argv[1]).read_bytes()
digest = hashlib.sha256(module).hexdigest()
# Independently fixed normative Source-free policy and authored SQL. Neither
# CID nor expected physical revisions are derived from a product response.
policy = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}'
policy_cid = 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563'
reference = '{"epoch":{"authenticator":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","authorityScopeCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","epochNonce":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","expiresAt":2000,"notBefore":1000,"version":"actql-submission-epoch/0.1"},"nonce":"original-submit"}'
request_id = 'sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267'
# This bounded private reader fixture does not assert HMAC authentication or
# the public Host supplier. It verifies exact saved bytes/loans through Core.
core = LocalCore(module, digest=digest, transfer_capacity=12 * 1024 * 1024, slots=64,
                 resources=LocalCoreResources(100000, 64, 64, 32000000, 200000000,
                                              16 * 1024 * 1024 + 12 * 1024 * 1024))
assert core._exports['actql_host_abi_version'](core._store) == 48
inputs = []
children = []
material = None
run = configuration = preparation = environment = None
cases = []
cleanup_ready = [True]


def copy(value):
    payload = value if type(value) is bytes else encode(value)
    loan = core.reserve_input(payload, cleanup=lambda: True, stopped=lambda _: True)
    inputs.append(loan)
    for start in range(0, len(payload), 16384):
        core.fill_input(loan, start, min(16384, len(payload) - start))
    core.seal_input(loan)
    return loan


try:
    prepared = LocalPreparation(core)
    custody = LocalRunCustody(core, prepared)
    environment = prepared.install_environment(copy(ENVIRONMENT), profile='source-free')
    configuration = custody.install_configuration(copy({
        **CONFIGURATION, 'source_free_result_policy': {'cid': policy_cid, 'body': policy}}))
    original = {'kind': 'aql', 'input': {'format': 'sql', 'text': '/*😀*/\r\nSELECT 1 AS n'}, 'parameters': None}
    preparation = prepared.reserve(environment, copy(original), format='submitted')
    shape = prepared.prepare(preparation)
    assert shape.results == 1 and shape.tasks > 0
    run = custody.reserve(configuration, preparation, copy({
        'caller_request_id': request_id, 'run_id': 'original-saved-row',
        'created_at': '2026-10-12T00:00:00.000Z', 'valid_until': '2099-01-01T00:00:00.000Z'}))
    custody.prepare(run)
    before = json.dumps({'intent': json.dumps(original, ensure_ascii=False, sort_keys=True, separators=(',', ':')), 'phase': 'preparing',
                         'reference': reference, 'version': 'actql-native-client-submitted-intent-row/0.1'},
                        ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    material = custody.reserve_submitted_rows(run, configuration,
        copy({'reference': reference, 'preparing': before.decode(), 'now': 1000}), cleanup=lambda: True)
    core.produce_material(material)
    fields = json.loads(core.read_material(material))
    assert fields['submission_key'] == request_id
    assert json.loads(json.loads(fields['submitted'])['intent']) == original
    cases.append('original-nominal-preparation-and-row-projection')
    with TemporaryDirectory(prefix='actql-python-actual-journal-') as directory:
        with LocalByteStore(Path(directory) / 'original.sqlite', max_records=64,
                            max_record_bytes=1_048_576, max_payload_bytes=8 * 1_048_576) as store:
            # Explicit private fresh fixture custody, not automatic repair.
            for scope, body in [('client_run_custody', b'1'),
                                ('client_submitted_intent_custody', b'1'),
                                ('client_cancel_custody', b'0')]:
                assert store.compare_exchange(store.namespaced_key(scope, 'issued'), None, body) == 0
            run_key = store.namespaced_key('client_runs', fields['run_key'])
            submission_key = store.namespaced_key('client_submitted_intents', request_id)
            assert store.compare_exchange(run_key, None, fields['run'].encode()) == 0
            assert store.compare_exchange(submission_key, None, fields['submitted'].encode()) == 0
            assert store.compare_exchange('epoch', None, b'original-authentication-custody') == 0
            fences = (ByteFence('epoch', 0, b'original-authentication-custody'),)
            writes = (ByteWrite('observer-marker', None, b'original-physical-marker'),)
            child = core.reserve_journal_observation(material, configuration.handle,
                store=store, current=lambda: None, cleanup=lambda: cleanup_ready[0])
            children.append(child)
            assert core._call('material', 'close', material.handle) == -9
            assert core._call('run', 'close_configuration', configuration.handle) == -9
            assert core._call('buffer', 'close', child.handle) == -9
            assert core._call('buffer', 'close', material.handle) == -9
            cases.append('parent-material-configuration-and-raw-buffer-close-refused')
            revisions = []
            def observe(reader):
                core.inspect_journal_observation(child, reader)
                revisions.append(core.journal_observation_revisions(child, reader))
            assert store.compare_exchange_many_inspected(writes, fences,
                inspect=observe, current=lambda: None) == (0,)
            assert revisions == [(0, 0, 0)]
            cases.append('same-sqlite-complete-inventory-core-saved-observation')
            assert core._journal_callbacks(child.ticket).reader is None
            cases.append('snapshot-reader-expired-after-physical-transaction')
            # The earlier candidate and original actual rows are not changed by
            # inspection or by a failed cleanup of its transient observer child.
            assert store.read(run_key).payload == fields['run'].encode()
            assert store.read(submission_key).payload == fields['submitted'].encode()
            cleanup_ready[0] = False
            assert core.close_journal_observation(child) is False
            assert core._loans[child.ticket] is child
            assert core._call('material', 'close', material.handle) == -9
            cases.append('failed-cleanup-retains-original-ticket-and-parent')
            cleanup_ready[0] = True
            assert core.close_journal_observation(child) is True
            children.remove(child)
            cases.append('same-child-cleanup-retry-and-release')
            # Actual later Run CAS is independent of the immutable admission.
            assert store.compare_exchange(run_key, 0, fields['run'].encode()) == 1
            late = core.reserve_journal_observation(material, configuration.handle,
                store=store, current=lambda: None, cleanup=lambda: True)
            children.append(late)
            revisions.clear()
            def later(reader):
                core.inspect_journal_observation(late, reader)
                revisions.append(core.journal_observation_revisions(late, reader))
            assert store.compare_exchange_many_inspected(
                (ByteWrite('late-marker', None, b'late'),), fences,
                inspect=later, current=lambda: None) == (0,)
            assert revisions == [(0, 1, 0)]
            cases.append('later-run-revision-preserves-original-admission')
            assert core.close_journal_observation(late) is True
            children.remove(late)
            orphan = store.namespaced_key('client_effect_response_bytes', 'orphan')
            assert store.compare_exchange(orphan, None, b'unattached-original-response') == 0
            refused = core.reserve_journal_observation(material, configuration.handle,
                store=store, current=lambda: None, cleanup=lambda: True)
            children.append(refused)
            try:
                store.compare_exchange_many_inspected(
                    (ByteWrite('must-not-write', None, b'no'),), fences,
                    inspect=lambda reader: core.inspect_journal_observation(refused, reader),
                    current=lambda: None)
            except LocalCoreError as error:
                assert error.code == -31
            else:
                raise AssertionError('Unattached inventory was admitted')
            assert store.read('must-not-write') is None
            assert store.read(orphan).payload == b'unattached-original-response'
            cases.append('unattached-inventory-rejects-with-zero-target-write')
            assert core.close_journal_observation(refused) is True
            children.remove(refused)
finally:
    cleanup_ready[0] = True
    for child in reversed(children):
        assert core.close_journal_observation(child)
    if material is not None:
        assert core.close_material(material)
    if run is not None:
        assert custody.close_run(run)
    if preparation is not None:
        assert prepared.close_preparation(preparation)
    if configuration is not None:
        assert custody.close_configuration(configuration)
    if environment is not None:
        assert prepared.close_environment(environment)
    for loan in reversed(inputs):
        assert core.close_input(loan)
    assert core.close()
assert len(cases) == 8
print(json.dumps({'success': True, 'module_sha256': digest, 'cases': cases,
                  'default_fuel': 100_000_000, 'public_local': False,
                  'commit_ack': False, 'wheel': False}))
