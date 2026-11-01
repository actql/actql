"""Actual raw Wasmtime i64 transport; no installed Run or physical ACK."""
import hashlib
import json
from pathlib import Path
import sys

from python_local_physical import PhysicalFixture


module = Path(sys.argv[1]).read_bytes()
left = PhysicalFixture(module, 7101)
right = None
try:
    right = PhysicalFixture(module, 7102)
    # Independently authored valid JSON bytes include a non-BMP character,
    # a split UTF-8 code point and CRLF. The high packed lane exceeds 2**53.
    payload = b'"\xf0\x9f\x98\x80/\xc3\xa9"\r\n'
    handle = left.call('reserve', 41, len(payload), sys.getsizeof(payload))
    assert handle > 0
    left.inputs[41] = payload
    assert left.call('read_packed', handle, 0, 7) == -5
    assert left.call('fill', handle, 0, len(payload)) == 0
    assert left.call('seal', handle) == 0
    packed = (left.call('read_packed', handle, 0, 7),
              left.call('read_packed', handle, 7, 4))
    assert all(type(value) is int for value in packed)
    assert packed == (0xC32F80989FF022, 0x0A0D22A9)
    assert packed[0] > 2**53 and packed[0] < 2**56
    assert packed[0].to_bytes(7, 'little') + packed[1].to_bytes(4, 'little') == payload
    assert right.exports['actql_buffer_read_packed'](
        right.store, left.nonce, handle, 0, 7) == -1
    assert right.call('read_packed', handle, 0, 7) == -2
    for start, count in ((0, 0), (0, 8), (-1, 1), (2147483647, 1)):
        assert left.call('read_packed', handle, start, count) == -6
    assert left.call('read_packed', handle, 7, 7) == -5
    before = left.call('allocated')
    assert left.call('close', handle) == -9
    assert left.call('read_packed', handle, 0, 7) == -5
    assert left.call('allocated') == before
    left.cleanup_ready = True
    assert left.call('close', handle) == 0
    assert left.call('read_packed', handle, 0, 1) == -2
    assert left.call('allocated') == 0
    assert left.call('close_pool') == 0
    assert right.call('close_pool') == 0
finally:
    if right is not None:
        right.close()
    left.close()

print(json.dumps({'success': True, 'module_sha256': hashlib.sha256(module).hexdigest(),
    'cases': ['original_wasmtime_i64_packed_transport'],
    'scope': 'unmetered_raw_transport_only_not_Run_or_physical_ACK'}))
