"""Real Core decisions across abrupt process exits; no public Run acceptance."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

from python_local_physical import PhysicalFixture
from python_local_run_inputs import (ENVIRONMENT, PROGRAM, AQL, CONFIGURATION,
                                     REQUEST, encode)

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'packages/python-sdk/src'))
from actql_sdk._local_dispatch import DispatchAction, reserve_dispatch
from actql_sdk._local_storage import LocalByteStore


def worker(module_path, path, kind, phase):
    # Explicit diagnostic profile. Default 100M fuel is not changed or claimed.
    fixture = PhysicalFixture(Path(module_path).read_bytes(), 1701 + phase,
                              capacity=32 * 1024 * 1024, slots=128)
    assert fixture.exports['actql_host_abi_version'](fixture.store) == 40
    ticket = 0
    def copy(value):
        nonlocal ticket
        ticket += 1
        raw = value if isinstance(value, bytes) else encode(value)
        return fixture.copy(ticket, raw, sys.getsizeof(raw))
    def call(family, name, *args):
        return fixture.exports['actql_' + family + '_' + name](
            fixture.store, fixture.nonce, *args)
    def material(run, kind):
        nonlocal ticket
        ticket += 1
        output = call('material', 'reserve', run, kind, ticket, 2_097_200)
        assert output > 0 and call('material', 'produce', output) == 0
        length = call('material', 'length', output)
        assert 0 < length <= 1_048_576
        raw = bytes(fixture.call('byte', output, i) for i in range(length))
        fixture.inputs[ticket] = b''
        fixture.cleanup_ready = True
        assert call('material', 'close', output) == 0
        fixture.cleanup_ready = False
        return raw

    with LocalByteStore(Path(path), max_records=8, max_record_bytes=1_048_576,
                        max_payload_bytes=8 * 1_048_576) as store:
        environment = call('program', 'install_environment', copy(ENVIRONMENT))
        config = call('run', 'install_configuration', copy(CONFIGURATION))
        original = (encode(PROGRAM) if kind == 1 else AQL.encode('utf-8')) if phase == 0 else store.read('input').payload
        # The transfer envelope is JSON; the retained authored text is UTF-8
        # bytes. Neither is a substitute for the other's revision/custody.
        input_wire = original if kind == 1 else encode(original.decode('utf-8'))
        preparation = call('program', 'reserve_preparation', environment, copy(input_wire), kind)
        assert preparation > 0 and call('program', 'prepare', preparation) == 0
        request = encode(REQUEST) if phase == 0 else store.read('request').payload
        run = call('run', 'reserve', config, preparation, copy(request))
        assert run > 0
        if phase == 0:
            assert call('run', 'prepare', run) == 0
            records = {name: material(run, index) for name, index in
                       [('materials', 1), ('request', 2), ('definition', 3), ('input', 4)]}
            assert records['input'] == original
            for name, raw in records.items():
                assert store.compare_exchange(name, None, raw) == 0
        else:
            records = {name: store.read(name).payload for name in
                       ['materials', 'request', 'definition', 'input']}
            restoration = call('material', 'reserve_restoration', copy({
                'materials': records['materials'].decode(),
                'expected_run_definition_cid': records['definition'].decode()}))
            assert restoration > 0 and call('material', 'restore', restoration) == 0
            assert call('run', 'restore', run, restoration) == 0
        assert call('run', 'prepared', run) == 0
        def decide(payload):
            return call('run', 'dispatch_action', run, config, copy(payload))
        observation = reserve_dispatch(store, 'dispatch', request=records['request'].decode(),
                                       definition_cid=records['definition'].decode(), decide=decide)
        assert observation.action is (DispatchAction.RESERVED if phase == 0 else DispatchAction.RECONCILE)
        assert observation.retained.generation == (1 if phase == 2 else 0)
        facts = json.loads(observation.retained.payload)
        assert facts['reserved'] is True
        assert facts['physically_unstarted'] is (phase != 2)
        assert facts['request'].encode() == records['request']
        if phase > 0:
            start = call('run', 'reserve_physical_start', run, config, copy(observation.retained.payload))
            assert start > 0 and call('run', 'confirm_physical_start', start) == 0
            assert call('run', 'physical_start_ready', start) == (0 if phase == 1 else -32)
            if phase == 1:
                # Persist the physical claim before any call that can do work.
                # Exit here: absence of later outcomes cannot erase that claim.
                facts['physically_unstarted'] = False
                assert store.compare_exchange('dispatch', 0, encode(facts)) == 1
            else:
                denied = call('run', 'install_configuration', copy({
                    **CONFIGURATION, 'principal': 'other-user'}))
                assert call('run', 'dispatch_action', run, denied, copy(facts)) == -32
                changed = call('run', 'install_configuration', copy({
                    **CONFIGURATION, 'context_cid': 'sha256:' + 'd' * 64}))
                assert call('run', 'dispatch_action', run, changed, copy(facts)) == -32
                for broken in ({**facts, 'reserved': None}, {**facts, 'unknown': True},
                               {key: value for key, value in facts.items() if key != 'request'}):
                    assert call('run', 'dispatch_action', run, config, copy(broken)) == -31
                assert call('run', 'dispatch_action', run, config, copy({
                    **facts, 'definition_cid': 'sha256:' + 'e' * 64})) == -32
                assert store.read('dispatch') == observation.retained
        print(json.dumps({'phase': phase, 'kind': kind, 'original_request': True,
                          'claim_blocks_restart': phase == 2}), flush=True)
    # Deliberately bypass kernel/handle teardown, as a process crash does.
    os._exit(0)


if len(sys.argv) > 2 and sys.argv[2] == '--worker':
    worker(sys.argv[1], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]))
else:
    module = Path(sys.argv[1]).resolve()
    outputs = []
    with TemporaryDirectory(prefix='actql-core-dispatch-reopen-') as directory:
        for kind in (1, 2):
            for phase in (0, 1, 2):
                child = subprocess.run([sys.executable, __file__, str(module), '--worker',
                                        str(Path(directory) / f'original-{kind}.sqlite'),
                                        str(kind), str(phase)], capture_output=True,
                                       text=True, timeout=40)
                assert child.returncode == 0, f'kind={kind}, phase={phase}: {child.stderr}'
                result = json.loads(child.stdout)
                assert result == {'phase': phase, 'kind': kind, 'original_request': True,
                                  'claim_blocks_restart': phase == 2}
                outputs.append(result)
    print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module.read_bytes()).hexdigest(),
                      'scope': 'private_unmetered_original_dispatch_reconciliation',
                      'processes': outputs, 'public_local_acceptance': False,
                      'durable_run_acceptance': False, 'default_fuel_acceptance': False,
                      'cases': ['structured_original_codec', 'aql_original_codec',
                                'abrupt_exit_reopen', 'exact_original_request',
                                'reserved_is_reconciliation', 'claim_is_not_unstarted',
                                'current_authority_denial', 'changed_context_denial',
                                'closed_physical_facts', 'foreign_run_refusal']}))
