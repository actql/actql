"""Core-produced original records and codec readmission; no Run recovery claim."""
import hashlib
import json
from pathlib import Path
import sys

from python_local_run_inputs import ENVIRONMENT, PROGRAM, CONFIGURATION, REQUEST, encode

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'packages/python-sdk/src'))
from actql_sdk._local_core import LocalCore
from actql_sdk._local_storage import LocalByteStore
from tempfile import TemporaryDirectory


module = Path(sys.argv[1]).read_bytes()
digest = hashlib.sha256(module).hexdigest()
core = LocalCore(module, digest=digest, transfer_capacity=12 * 1024 * 1024, slots=64)
inputs = []
stopped = [False]
cleaned = [False]


def copy(payload):
    wire = payload if type(payload) is bytes else encode(payload)
    loan = core.reserve_input(wire, cleanup=lambda: cleaned[0], stopped=lambda _: stopped[0])
    inputs.append(loan)
    for start in range(0, len(wire), 16384):
        core.fill_input(loan, start, min(16384, len(wire) - start))
    core.seal_input(loan)
    return loan.handle


try:
    environment = core._call('program', 'install_environment', copy(ENVIRONMENT))
    assert environment > 0
    configuration = core._call('run', 'install_configuration', copy(CONFIGURATION))
    assert configuration > 0
    preparation = core._call('program', 'reserve_preparation', environment, copy(PROGRAM), 1)
    assert preparation > 0
    assert core._call('program', 'prepare', preparation) == 0
    run = core._call('run', 'reserve', configuration, preparation, copy(REQUEST))
    assert run > 0
    assert core._call('run', 'prepare', run) == 0
    assert core._call('run', 'prepared', run) == 0
    records = {}
    with TemporaryDirectory(prefix='actql-python-core-material-') as temporary:
        with LocalByteStore(Path(temporary) / 'core.sqlite', max_records=8,
                            max_record_bytes=1_048_576, max_payload_bytes=4 * 1_048_576) as store:
            for kind in (1, 2, 3, 4):
                loan = core.reserve_material(run, kind, cleanup=lambda: cleaned[0])
                assert core._call('run', 'close', run) == -9
                core.produce_material(loan)
                wire = core.read_material(loan)
                assert core.read_material(loan) is wire
                assert store.compare_exchange(str(kind), None, wire) == 0
                retained = store.read(str(kind))
                assert retained is not None and retained.payload == wire
                records[kind] = retained.payload
                assert not core.close_material(loan)
                cleaned[0] = True
                assert core.close_material(loan)
                cleaned[0] = False
        # Independent authored bytes, not a lowered JSON surrogate.
        assert records[4] == encode(PROGRAM)
        assert len(records[3]) == 71 and records[3].startswith(b'sha256:')
        materials = json.loads(records[1])
        assert materials['run_id'] == 'original-run'
        assert materials['scope_id'] == 'local'
        assert materials['parameters'] is None
        assert materials['program_format'] == 'json'
        request = json.loads(records[2])
        assert request['caller_request_id'] == 'original-submission'
        assert request['authority_scope_cid'] == 'sha256:' + 'b' * 64
        restored = core._call('material', 'reserve_restoration', copy({
            'materials': records[1].decode(), 'expected_run_definition_cid': records[3].decode()}))
        assert restored > 0
        assert core._call('material', 'restored', restored) == -33
        assert core._call('material', 'restore', restored) == 0
        assert core._call('material', 'restored', restored) == 0
        assert core._call('material', 'close_restoration', restored) == -9
        stopped[0] = True
        assert core._call('material', 'close_restoration', restored) == 0
        stopped[0] = False
        foreign = core._call('material', 'reserve_restoration', copy({
            'materials': records[1].decode(), 'expected_run_definition_cid': 'sha256:' + '0' * 64}))
        assert foreign > 0
        assert core._call('material', 'restore', foreign) == 0
        assert core._call('material', 'restored', foreign) == -32
        stopped[0] = True
        assert core._call('material', 'close_restoration', foreign) == 0
        assert core._call('run', 'close', run) == 0
        assert core._call('program', 'close_preparation', preparation) == 0
        assert core._call('program', 'close_environment', environment) == 0
        assert core._call('run', 'close_configuration', configuration) == 0
        cleaned[0] = True
        for loan in inputs:
            assert core.close_input(loan)
        assert core.close()
finally:
    # On a trap leave Core's failed-custody outcome intact. Native physical
    # teardown ends only this test process, never claims a successful release.
    if not core._closed:
        for name in ('_store', '_linker', '_module', '_engine'):
            resource = getattr(core, name)
            if resource is not None:
                resource.close()

print(json.dumps({'success': True, 'module_sha256': digest, 'material_cases': 8}))
