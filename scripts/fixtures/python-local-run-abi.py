"""Real Wasm Run compilation custody; not durable acceptance or Compute."""
import hashlib
import json
from pathlib import Path
import sys
import wasmtime
from python_local_physical import PhysicalFixture


from python_local_run_inputs import ENVIRONMENT, PROGRAM, AQL, CONFIGURATION, REQUEST, encode


module = Path(sys.argv[1]).read_bytes()
fixture = PhysicalFixture(module, 505, capacity=262144, slots=32, fuel=100000000)
ticket = 0


def copy(value):
    global ticket
    ticket += 1
    payload = value if isinstance(value, bytes) else encode(value)
    return fixture.copy(ticket, payload, sys.getsizeof(payload))


def call(family, name, *arguments):
    return fixture.exports['actql_' + family + '_' + name](
        fixture.store, fixture.nonce, *arguments)


try:
    environment = call('program', 'install_environment', copy(ENVIRONMENT))
    assert environment > 0
    config = call('run', 'install_configuration', copy(CONFIGURATION))
    assert config > 0
    prepared = []
    for original, kind in [(PROGRAM, 1), (AQL, 2)]:
        preparation = call('program', 'reserve_preparation', environment, copy(original), kind)
        assert preparation > 0
        assert call('program', 'prepare', preparation) == 0
        handle = call('run', 'reserve', config, preparation, copy(REQUEST))
        assert handle > 0
        assert call('run', 'prepared', handle) == -33
        reads = fixture.reads
        assert call('run', 'prepare', handle) == 0
        assert call('run', 'prepared', handle) == 0
        assert call('run', 'prepare', handle) == 0
        assert fixture.reads == reads
        assert call('program', 'close_preparation', preparation) == -9
        assert call('run', 'close_configuration', config) == -9
        assert call('run', 'close', handle) == -9
        fixture.stop_ready = True
        assert call('run', 'close', handle) == 0
        assert call('run', 'prepared', handle) == -2
        fixture.stop_ready = False
        prepared.append(preparation)

    # The Account Owner must evaluate the installed grant. An otherwise valid
    # policy/context identity is not a grant for a different principal.
    foreign = call('run', 'install_configuration', copy({**CONFIGURATION,
                                                        'principal': 'other-user'}))
    denied = call('run', 'reserve', foreign, prepared[0], copy(REQUEST))
    assert denied > 0
    assert call('run', 'prepare', denied) == 0
    assert call('run', 'prepared', denied) == -32
    assert call('run', 'install_configuration', copy({**CONFIGURATION,
                'account': encode({**ACCOUNT, 'unknown': True}).decode()})) == -30
    assert call('run', 'install_configuration', copy({**CONFIGURATION,
                                                     'unknown': True})) == -30
    assert call('run', 'reserve', config, 2147483647, copy(REQUEST)) == -2

    # Missing, NULL and unknown request fields remain malformed Host input;
    # they cannot become an empty or admitted Run, nor be implicitly retried.
    for request in [{key: value for key, value in REQUEST.items() if key != 'run_id'},
                    {**REQUEST, 'run_id': None}, {**REQUEST, 'unknown': True}]:
        handle = call('run', 'reserve', config, prepared[0], copy(request))
        assert handle > 0
        assert call('run', 'prepare', handle) == -31
        assert call('run', 'prepared', handle) == -33
        assert call('run', 'prepare', handle) == -33
        fixture.stop_ready = True
        assert call('run', 'close', handle) == 0
        fixture.stop_ready = False

    # Interrupt actual Wasm after the positive handle has reached the caller.
    # Missing outcome never implies unstarted work or permission to recompile.
    handle = call('run', 'reserve', config, prepared[0], copy(REQUEST))
    assert handle > 0
    held = fixture.call('allocated')
    fixture.store.set_fuel(5000)
    try:
        call('run', 'prepare', handle)
    except wasmtime.Trap:
        pass
    else:
        raise AssertionError('Expected an actual interrupted Run compilation')
    fixture.store.set_fuel(100000000)
    assert call('run', 'prepared', handle) == -33
    assert call('run', 'prepare', handle) == -33
    assert fixture.call('allocated') == held
    assert call('run', 'close', handle) == -9
    assert call('run', 'close_configuration', config) == -9
    assert call('program', 'close_preparation', prepared[0]) == -9
    assert fixture.call('close_pool') == -9
    assert fixture.call('reserved') == 262144
    fixture.stop_ready = True
    assert call('run', 'close', handle) == 0
    assert call('run', 'close', denied) == 0
    for preparation in prepared:
        assert call('program', 'close_preparation', preparation) == 0
    assert call('run', 'close_configuration', config) == 0
    assert call('run', 'close_configuration', foreign) == 0
    assert call('program', 'close_environment', environment) == 0
    assert fixture.call('close_pool') == -9
    assert fixture.call('reserved') == 262144
    fixture.cleanup_ready = True
    assert fixture.call('close_pool') == 0
    assert fixture.call('reserved') == 0
finally:
    fixture.close()

print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module).hexdigest(),
                  'cases': ['structured_run_compilation', 'aql_run_compilation',
                            'account_subject_denial', 'closed_account_configuration',
                            'closed_host_configuration', 'unprepared_input_rejection',
                            'missing_null_unknown_request', 'parent_handle_lifetime',
                            'actual_compilation_trap', 'no_implicit_compilation_retry',
                            'cleanup_pending_same_reservation', 'final_settlement']}))
