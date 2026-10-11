"""Actual installed publication loan; no Source I/O or accepted Run claim."""
import hashlib
import json
from pathlib import Path
import sys
from python_local_physical import PhysicalFixture

module = Path(sys.argv[1]).read_bytes()
fixture = PhysicalFixture(module, 707, capacity=262144, slots=32, fuel=100000000)
wire = Path(__file__).with_name('python-local-source-environment.json').read_text().strip()
publication = {
    'environmentCid': 'sha256:b734cc90c9bffcd4098a70223685a9d9489992f426e861af2232e58261dd7424',
    'aliases': [{'name': 'records', 'sourceRef': 'connector://crm/main/r#v',
                 'sourceViewContractCid': 'sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3',
                 'schemaContractCid': 'sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4'}],
    'tableWrites': [],
}
encode = lambda value: json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()
ticket = 0


def install(value):
    global ticket
    ticket += 1
    payload = encode(value)
    handle = fixture.copy(ticket, payload, sys.getsizeof(payload))
    result = fixture.exports['actql_program_install_source_environment'](
        fixture.store, fixture.nonce, handle)
    return handle, result


try:
    assert fixture.exports['actql_host_abi_version'](fixture.store) == 28
    for invalid in [
        {'publication': encode(publication).decode()},
        {'environment': None, 'publication': encode(publication).decode()},
        {'environment': wire, 'publication': None},
        {'environment': wire, 'publication': '{}', 'unknown': True},
        {'environment': wire, 'publication': encode({**publication, 'environmentCid': 'sha256:' + 'a' * 64}).decode()},
    ]:
        _, result = install(invalid)
        assert result == -20
    source, environment = install({'environment': wire, 'publication': encode(publication).decode()})
    assert environment > 0
    assert fixture.call('close', source) == -9
    allocated = fixture.call('allocated')
    assert fixture.exports['actql_program_close_environment'](
        fixture.store, fixture.nonce, environment) == -9
    assert fixture.call('allocated') == allocated
    fixture.stop_ready = True
    assert fixture.exports['actql_program_close_environment'](
        fixture.store, fixture.nonce, environment) == 0
    assert fixture.call('close_pool') == -9
    assert fixture.call('reserved') == 262144
    fixture.cleanup_ready = True
    assert fixture.call('close_pool') == 0
    assert fixture.call('reserved') == 0
finally:
    fixture.close()

print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module).hexdigest(),
                  'cases': ['closed_installed_configuration', 'missing_null_configuration',
                            'foreign_publication_generation', 'verified_source_publication',
                            'original_environment_loan', 'physical_stop_retry', 'final_settlement']}))
