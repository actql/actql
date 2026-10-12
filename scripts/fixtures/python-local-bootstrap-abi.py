"""Prepared real-Wasm bootstrap consumer; no public Host/adoption/ACK claim."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'packages/python-sdk/src'))
from actql_sdk._local_core import LocalCore

module = Path(sys.argv[1]).read_bytes()
digest = hashlib.sha256(module).hexdigest()
core = LocalCore(module, digest=digest)
assert core._exports['actql_host_abi_version'](core._store) == 54
source = output = None
stopped = [False]
cleanup_ready = [False]
cleanup = []
cases = []
try:
    # Independently authored raw UTF-8 path/clock and normative existing CID.
    wire = b'{"configuration_root":"/Users/e\xcc\x81/.actql-local","observed_at":"2026-10-12T00:00:00.000Z"}'
    source = core.reserve_input(wire, cleanup=lambda: True, stopped=lambda _: stopped[0])
    core.fill_input(source, 0, len(wire))
    core.seal_input(source)
    def close_output():
        cleanup.append(cleanup_ready[0])
        return cleanup_ready[0]
    output = core.reserve_bootstrap(source, cleanup=close_output)
    assert core._call('buffer', 'close', source.handle) == -9
    assert core._call('buffer', 'close', output.handle) == -9
    cases.append('original-input-and-raw-output-close-refused')
    core.produce_bootstrap(output)
    packet = json.loads(core.read_bootstrap(output))
    assert set(packet) == {'account', 'retention_dependencies', 'retention_policy',
                           'store', 'result_policy', 'environment', 'compute'}
    assert all(type(value) is str for value in packet.values())
    assert packet['store'] == ('{"version":"actql-local-store-owner/0.1",'
                               '"root":"/Users/e\u0301/.actql-local/results","principalId":"local-cli"}')
    assert hashlib.sha256(packet['store'].encode()).hexdigest() == (
        '76f202e5029b1252e537805c853e1185057b603c02fd742b4bd1095516264a05')
    assert hashlib.sha256(packet['result_policy'].encode()).hexdigest() == (
        '470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563')
    assert set(json.loads(packet['compute'])) == {'registry', 'values', 'fragment', 'ordered'}
    account = json.loads(packet['account'])
    assert account['account_id'] == 'local-cli'
    assert {entry['entry_id'] for entry in account['entries']} == {
        'local-result-read', 'local-run-control'}
    assert {resource for entry in account['entries']
            for resource in entry['resource']['any_of']} == {'run', 'result/answer'}
    cases.append('original-common-policy-store-and-source-free-assets')
    assert core.close() is False
    try:
        core.reserve_bootstrap(source, cleanup=lambda: True)
    except ValueError:
        pass
    else:
        raise AssertionError('Closing Root admitted another metadata child')
    cases.append('root-close-retains-child-and-refuses-new-reservation')
    assert core.close_bootstrap(output) is False
    assert core._loans[output.ticket] is output
    assert core._loans[source.ticket] is source
    assert cleanup == [False]
    cases.append('failed-cleanup-retains-original-output-and-parent')
    cleanup_ready[0] = True
    assert core.close_bootstrap(output) is False
    assert core._loans[output.ticket] is output
    assert cleanup == [False, True]
    try:
        core.read_bootstrap(output)
    except RuntimeError:
        pass
    else:
        raise AssertionError('Retired metadata output was readable')
    assert core._call('buffer', 'close', source.handle) == -9
    cases.append('successful-output-cleanup-keeps-unreturned-input-borrow')
    stopped[0] = True
    assert core.close_bootstrap(output) is True
    output = None
    assert cleanup == [False, True]
    assert core.close_input(source) is True
    source = None
    assert core.close() is True
    cases.append('same-input-borrow-return-and-formal-private-release')
finally:
    stopped[0] = cleanup_ready[0] = True
    if output is not None:
        assert core.close_bootstrap(output)
    if source is not None:
        assert core.close_input(source)
    assert core.close()
assert len(cases) == 6
print(json.dumps({'success': True, 'module_sha256': digest, 'cases': cases,
                  'default_fuel': 100_000_000, 'public_local': False,
                  'host_adopted': False, 'store_ack': False, 'wheel': False}))
