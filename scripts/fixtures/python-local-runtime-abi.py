"""Consume the private Python physical bridge with a real fixed Wasm artifact."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import wasmtime

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'packages/python-sdk/src'))
from actql_sdk._local_core import LocalCore


module = Path(sys.argv[1]).read_bytes()
digest = hashlib.sha256(module).hexdigest()
payload = '{"e\u0301/~😀":"line\\r\\n😀","nullable":null}'.encode('utf-8')
core = LocalCore(module, digest=digest, transfer_capacity=65536)
other = LocalCore(module, digest=digest, transfer_capacity=65536)
ready = False
attempts = 0


def cleanup():
    global attempts
    attempts += 1
    if not ready:
        raise OSError('independent physical cleanup failure')
    return True


value = core.reserve_input(payload, cleanup=cleanup, stopped=lambda _: True)
assert core._call('buffer', 'allocated') == len(payload) * 2 + sys.getsizeof(payload)
for selected, loan in [(other, value), (core, copy.copy(value))]:
    try:
        selected.fill_input(loan, 0, len(payload))
    except ValueError:
        pass
    else:
        raise AssertionError('Foreign or copied input acquired custody')
core.fill_input(value, 0, len(payload))
core.seal_input(value)
assert bytes(core._call('buffer', 'byte', value.handle, index)
             for index in range(len(payload))) == payload
store = core._store
assert core.close_input(value) is False
assert core.close() is False
assert core._store is store
assert core._call('buffer', 'reserved') == 65536
ready = True
assert core.close() is True
assert core.close() is True
assert attempts == 3
assert other.close() is True

# A real trap during transfer retains the handle issued before allocation.
trapped = LocalCore(module, digest=digest, transfer_capacity=262144)
try:
    ready = False
    large = b'"' + b'x' * 65534 + b'"'
    loan = trapped.reserve_input(large, cleanup=lambda: ready, stopped=lambda _: True)
    retained = trapped._call('buffer', 'allocated')
    trapped._store.set_fuel(5000)
    try:
        trapped.fill_input(loan, 0, 16384)
    except wasmtime.Trap:
        pass
    else:
        raise AssertionError('Expected a physical interruption during transfer')
    assert trapped._closing and not trapped._retired
    registered = len(trapped._inputs)
    try:
        trapped.reserve_input(b'new', cleanup=lambda: True, stopped=lambda _: True)
    except ValueError:
        pass
    else:
        raise AssertionError('Trapped bridge accepted fresh physical custody')
    assert len(trapped._inputs) == registered
    assert trapped._loans[loan.ticket] is loan
    # Explicit fixture-only cleanup funding; the bridge never refills fuel.
    trapped._store.set_fuel(100000000)
    assert trapped._call('buffer', 'allocated') == retained
    assert trapped.close_input(loan) is False
    assert trapped.close() is False
    ready = True
    assert trapped.close() is True
finally:
    if not trapped._closed:
        ready = True
        assert trapped.close() is True

# The physical callback cannot recursively mutate the live Wasm instance.
reentrant = LocalCore(module, digest=digest, transfer_capacity=65536)
try:
    ready = False
    loan = reentrant.reserve_input(b'null',
        cleanup=lambda: True if ready else reentrant.close(), stopped=lambda _: True)
    assert reentrant.close_input(loan) is False
    assert reentrant._call('buffer', 'allocated') == 8 + sys.getsizeof(b'null')
    ready = True
    assert reentrant.close() is True
finally:
    if not reentrant._closed:
        ready = True
        assert reentrant.close() is True

# Stop the Wasm instruction stream after the physical callback succeeds.
# Retrying the exact close acknowledges that saved fact without double cleanup.
acknowledgement = LocalCore(module, digest=digest, transfer_capacity=65536)
try:
    physical_closes = 0
    def close_then_interrupt():
        global physical_closes
        physical_closes += 1
        acknowledgement._store.set_fuel(0)
        return True
    loan = acknowledgement.reserve_input(b'null', cleanup=close_then_interrupt,
                                         stopped=lambda _: True)
    try:
        acknowledgement.close_input(loan)
    except wasmtime.Trap:
        pass
    else:
        raise AssertionError('Expected interrupted Core cleanup acknowledgement')
    acknowledgement._store.set_fuel(100000000)
    assert loan.ticket in acknowledgement._released
    assert acknowledgement.close_input(loan) is True
    assert physical_closes == 1
    assert not acknowledgement._loans and not acknowledgement._released
    assert acknowledgement.close() is True
finally:
    if not acknowledgement._closed:
        acknowledgement._store.set_fuel(100000000)
        assert acknowledgement.close() is True

try:
    LocalCore(module, digest='0' * 64, transfer_capacity=65536)
except ValueError:
    pass
else:
    raise AssertionError('Modified artifact accepted')

print(json.dumps({'success': True, 'module_sha256': digest,
    'cases': ['artifact_binding', 'exact_raw_values', 'measured_copy_reservation',
              'foreign_instance_refusal', 'copied_handle_refusal',
              'cleanup_exception_retention', 'same_instance_retry',
              'idempotent_final_close', 'real_transfer_trap_custody',
              'trapped_bridge_refuses_fresh_custody',
              'callback_reentry_refusal', 'lost_cleanup_acknowledgement']}))
