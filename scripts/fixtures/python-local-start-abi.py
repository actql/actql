"""Actual original Run start facts; not durable admission or public execution."""
import hashlib
import json
from pathlib import Path
import sys
from python_local_physical import PhysicalFixture
from python_local_run_inputs import ENVIRONMENT, PROGRAM, CONFIGURATION, REQUEST, ACCOUNT, encode

module = Path(sys.argv[1]).read_bytes()
fixture = PhysicalFixture(module, 909, capacity=8_388_608, slots=64, fuel=100_000_000)
ticket = 0


def copy(value):
    global ticket
    ticket += 1
    payload = value if isinstance(value, bytes) else encode(value)
    return fixture.copy(ticket, payload, sys.getsizeof(payload))


def call(family, name, *arguments):
    return fixture.exports['actql_' + family + '_' + name](
        fixture.store, fixture.nonce, *arguments)


def material(run, kind):
    global ticket
    ticket += 1
    output = call('material', 'reserve', run, kind, ticket, 2_097_200)
    assert output > 0
    assert call('material', 'produce', output) == 0
    length = call('material', 'length', output)
    assert 0 < length <= 1_048_576
    result = bytes(fixture.call('byte', output, i) for i in range(length))
    # There is no result input callback for this Core-produced output.
    fixture.inputs[ticket] = b''
    fixture.cleanup_ready = True
    assert call('material', 'close', output) == 0
    fixture.cleanup_ready = False
    return result.decode('utf8')


try:
    assert fixture.exports['actql_host_abi_version'](fixture.store) == 24
    assert call('run', 'reserve_physical_start', 1, 2, 3) == -2
    assert call('run', 'confirm_physical_start', 2147483647) == -2
    assert call('run', 'physical_start_ready', 2147483647) == -2
    environment = call('program', 'install_environment', copy(ENVIRONMENT))
    config = call('run', 'install_configuration', copy(CONFIGURATION))
    preparation = call('program', 'reserve_preparation', environment, copy(PROGRAM), 1)
    assert call('program', 'prepare', preparation) == 0
    # Each case has a distinct original Run/Submission. Owner-produced records
    # below are physical inputs, not independent expected values.
    for index, changes in enumerate([
        {}, {'reserved': False}, {'physically_unstarted': False},
        {'cancellation_requested': True}, {'pre_start_failure_confirmed': True},
        {'definition_cid': 'sha256:' + 'f' * 64},
        {'reserved': None}, {'unknown': True},
    ]):
        request = {**REQUEST, 'run_id': f'start-run-{index}',
                   'caller_request_id': f'start-submission-{index}'}
        run = call('run', 'reserve', config, preparation, copy(request))
        assert call('run', 'prepare', run) == 0
        assert call('run', 'prepared', run) == 0
        facts = {'request': material(run, 2), 'definition_cid': material(run, 3),
                 'reserved': True, 'physically_unstarted': True,
                 'cancellation_requested': False, 'pre_start_failure_confirmed': False,
                 **changes}
        input_handle = copy(facts)
        start = call('run', 'reserve_physical_start', run, config, input_handle)
        assert start > 0
        assert call('run', 'physical_start_ready', start) == -33
        assert call('run', 'reserve_physical_start', run, config, input_handle) == -3
        expected = -31 if index >= 6 else 0
        assert call('run', 'confirm_physical_start', start) == expected
        assert call('run', 'physical_start_ready', start) == (0 if index == 0 else -33 if index >= 6 else -32)
        # Repeating a known result performs no callback; malformed facts cannot
        # be repaired under this invocation or replaced with another handle.
        reads = fixture.reads
        assert call('run', 'confirm_physical_start', start) == (-33 if index >= 6 else 0)
        assert fixture.reads == reads
        assert call('run', 'close', run) == -9
        assert call('run', 'close_configuration', config) == -9
        assert call('run', 'close_physical_start', start) == -9
        fixture.stop_ready = True
        assert call('run', 'close_physical_start', start) == 0
        assert call('run', 'reserve_physical_start', run, config, input_handle) == -3
        assert call('run', 'close', run) == 0
        fixture.stop_ready = False
    fixture.stop_ready = fixture.cleanup_ready = True
    assert fixture.call('close_pool') == 0
    assert fixture.call('reserved') == 0
finally:
    fixture.close()
print(json.dumps({'module_sha256': hashlib.sha256(module).hexdigest(),
                  'success': True, 'public_local_acceptance': False,
                  'cases': ['positive', 'reservation', 'unstarted', 'cancel',
                            'pre_start_failure', 'definition', 'null', 'unknown',
                            'same_invocation', 'borrow_retirement']}))
