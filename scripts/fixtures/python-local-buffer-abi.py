"""Actual Python callbacks into the portable Core buffer owner, not a Run test."""
import hashlib
import json
from pathlib import Path
import sys
from python_local_physical import PhysicalFixture




module = Path(sys.argv[1]).read_bytes()
left, right = PhysicalFixture(module, 101), PhysicalFixture(module, 202)
try:
    # Independently authored exact bytes: a decomposed key, escaped pointer
    # characters, a non-BMP value, CRLF, NULL and an absent field.
    payload = '{"e\u0301/~😀":"e\u0301\\r\\n😀","nullable":null,"n":1}'.encode('utf-8')
    physical_bytes = sys.getsizeof(payload)
    handle = left.copy(1, payload, physical_bytes)
    assert json.loads(payload) == {'e\u0301/~😀': 'e\u0301\r\n😀', 'nullable': None, 'n': 1}
    # Allocation writes also require their original confirmed Writing parent.
    assert left.exports['actql_payload_allocation_reserve'](
        left.store, left.nonce, handle, 1, 65000, 131300) == -2
    assert left.exports['actql_payload_allocation_produce'](
        left.store, left.nonce, handle, handle, handle) == -2
    assert left.exports['actql_payload_allocation_validate'](
        left.store, left.nonce, handle, handle) == -2
    assert left.exports['actql_payload_allocation_begin'](
        left.store, left.nonce, handle, handle) == -2
    assert left.exports['actql_payload_allocation_confirm'](
        left.store, left.nonce, handle, handle, handle) == -2
    assert left.exports['actql_payload_allocation_close'](
        left.store, right.nonce, handle) == -2
    assert left.call('allocated') == 2 * len(payload) + physical_bytes
    assert left.call('reserved') == 256
    assert right.exports['actql_buffer_byte'](right.store, left.nonce, handle, 0) == -1
    assert right.reads == 0
    # Completion cannot be synthesized from arbitrary transport handles.
    assert left.exports['actql_compute_reserve'](left.store, left.nonce, handle, handle) == -2
    assert left.exports['actql_compute_configure'](left.store, left.nonce, handle) == -2
    assert left.exports['actql_compute_close'](left.store, left.nonce, handle) == -2
    assert left.exports['actql_task_reserve'](left.store, left.nonce, handle, handle) == -2
    assert left.exports['actql_task_start'](left.store, left.nonce, handle) == -2
    assert left.exports['actql_task_complete'](left.store, left.nonce, handle) == -2
    assert left.exports['actql_task_close'](left.store, left.nonce, handle) == -2
    assert left.exports['actql_result_reserve'](left.store, left.nonce, handle, 0) == -2
    assert left.exports['actql_result_reserve_chunk'](left.store, left.nonce, handle, 3, 128) == -2
    assert left.exports['actql_result_produce_chunk'](left.store, left.nonce, handle) == -2
    assert left.exports['actql_result_close_chunk'](left.store, left.nonce, handle) == -2
    assert left.exports['actql_result_close'](left.store, left.nonce, handle) == -2
    # Arbitrary transfer handles cannot claim original publication custody.
    assert left.exports['actql_publication_prepare_commit'](
        left.store, left.nonce, handle, handle, handle) == -2
    assert left.exports['actql_publication_advance_commit'](
        left.store, left.nonce, handle, handle, 1) == -2
    assert left.exports['actql_publication_commit_progress'](
        left.store, left.nonce, handle, 0) == -2
    assert left.exports['actql_publication_finish_commit'](
        left.store, left.nonce, handle, handle) == -2
    assert left.exports['actql_publication_commit_export_reserve'](
        left.store, left.nonce, handle, 2, 2097200) == -2
    assert left.exports['actql_publication_commit_export_produce'](
        left.store, left.nonce, handle, handle) == -2
    assert left.exports['actql_publication_commit_export_length'](
        left.store, left.nonce, handle) == -2
    assert left.exports['actql_publication_commit_export_close'](
        left.store, left.nonce, handle) == -2
    assert left.exports['actql_publication_commit_export_close'](
        left.store, right.nonce, handle) == -2
    assert left.exports['actql_result_binding_reserve'](
        left.store, left.nonce, handle, 0, handle, 2, 131300) == -2
    assert left.exports['actql_result_binding_produce'](
        left.store, left.nonce, handle, handle) == -2
    assert left.exports['actql_result_binding_length'](
        left.store, left.nonce, handle) == -2
    assert left.exports['actql_result_binding_close'](
        left.store, left.nonce, handle) == -2
    # Writing and physical ownership need the original confirmed Core record.
    assert left.exports['actql_payload_writing_reserve'](
        left.store, left.nonce, handle, 1, 65000, 131300) == -2
    assert left.exports['actql_payload_writing_produce'](
        left.store, left.nonce, handle, handle, handle) == -2
    assert left.exports['actql_payload_writing_begin'](
        left.store, left.nonce, handle, handle) == -2
    assert left.exports['actql_payload_writing_confirm'](
        left.store, left.nonce, handle, handle, handle) == -2
    assert left.exports['actql_payload_writing_close'](
        left.store, right.nonce, handle) == -2
    assert left.call('allocated') == 2 * len(payload) + physical_bytes
    # Individually valid reservations still exceed one aggregate allowance.
    assert left.call('reserve', 2, len(payload), 128) == -4
    assert left.call('fill', handle, 0, 1) == -5
    reader = left.call('borrow', handle)
    assert reader > handle
    assert left.call('close', reader) == -2, 'Reader handles cannot alias input handles'
    assert left.call('close', handle) == -9
    assert not left.cleanups
    assert left.call('return', reader) == -9
    assert left.call('allocated') == 2 * len(payload) + physical_bytes
    left.stop_ready = True
    assert left.call('return', reader) == 0
    assert left.call('close', handle) == -9
    assert left.call('allocated') == 2 * len(payload) + physical_bytes
    left.cleanup_ready = True
    assert left.call('close', handle) == 0
    assert left.cleanups[1] == 2
    assert left.call('byte', handle, 0) == -2
    assert left.call('allocated') == 0
    next_handle = left.copy(2, b'null', sys.getsizeof(b'null'))
    assert next_handle > reader
    assert left.call('close_pool') == 0
    assert left.call('close_pool') == 0
    assert left.call('reserved') == 0
    assert left.call('reserve', 3, 4, 4) == -5
    bad = right.call('reserve', 1, 4, sys.getsizeof(b'null'))
    right.inputs[1] = b'null'
    right.invalid_byte = True
    assert right.call('fill', bad, 0, 4) == -12
    assert right.call('seal', bad) == -7
    assert right.call('byte', bad, 0) == -5
    right.invalid_byte = False
    assert right.call('fill', bad, 0, 4) == 0
    assert right.call('seal', bad) == 0
    right.cleanup_ready = True
    assert right.call('close_pool') == 0
    assert right.call('reserved') == 0
finally:
    left.close()
    right.close()

print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module).hexdigest(),
    'cases': ['exact_values', 'instance_identity', 'aggregate_capacity',
              'borrow_retirement', 'uncompleted_source_compute_refusal', 'unconfigured_task_refusal', 'uncompleted_result_refusal', 'cleanup_retry', 'stale_handles', 'invalid_byte', 'pool_close']}))
