"""Transport the five protected originals under the selected Resolve Read."""

from collections.abc import Callable
import re
from struct import Struct

_CID_BYTES = 71
_CID = re.compile(rb'sha256:[0-9a-f]{64}')
_MAX_PROJECTION = 65536
_MAX_PRIVATE = 1048576
_LENGTH = Struct('<I')
_LENGTHS = Struct('<IIII')


def _cid_fields(value: bytes, count: int) -> tuple[str, ...]:
    if len(value) != count * _CID_BYTES:
        raise ValueError('Invalid original Effect resolution holding coordinates')
    fields = tuple(value[start:start + _CID_BYTES] for start in range(0, len(value), _CID_BYTES))
    if any(_CID.fullmatch(field) is None for field in fields):
        raise ValueError('Invalid original Effect resolution holding coordinates')
    return tuple(field.decode('ascii') for field in fields)


def _require_extent(raw: bytes, maximum: int) -> int:
    if type(raw) is not bytes or not 0 < len(raw) <= maximum:
        raise ValueError('Invalid original Effect resolution holding extent')
    return len(raw)


def _with_original_effect_resolution_input(
        checkpoint: str, *,
        select_key: Callable[[], tuple[bytes, bytes]],
        select_holdings: Callable[[bytes], bytes],
        authenticate: Callable[[bytes, str, str, str, str, Callable[[bytes], None]], None],
        reserve: Callable[[int], None],
        consume: Callable[[bytes], None]) -> None:
    """Return the protected continuation only to its already-authorized Guest consumer.

    The first callback selects the original Checkpoint under run:resolve.
    The same Read and authenticated Store must own every subsequent callback.
    """
    _cid_fields(checkpoint.encode('ascii'), 1)
    original, key = select_key()
    if type(key) is not bytes or len(key) != 32 or len(original) <= 2 * _CID_BYTES:
        raise ValueError('Invalid original Effect resolution key projection')
    continuation_cid, review_cid = _cid_fields(original[:2 * _CID_BYTES], 2)
    retained = 4096

    def read(namespace: str, role: str, address: str, cid: str, maximum: int) -> bytes:
        observed: list[bytes] = []

        def retain(body: bytes) -> None:
            nonlocal retained
            if observed:
                raise ValueError('Repeated original Effect resolution holding')
            retained += _require_extent(body, maximum)
            reserve(retained)
            observed.append(body)

        authenticate(key, namespace, role, address, cid, retain)
        if len(observed) != 1:
            raise ValueError('Missing original Effect resolution holding')
        return observed[0]

    continuation = read('effect_continuation_custody', 'continuation_record',
                        checkpoint, continuation_cid, _MAX_PRIVATE)
    extent = len(continuation)
    retained += _LENGTH.size + extent
    reserve(retained)
    prefix = _LENGTH.pack(extent) + continuation
    original = select_holdings(prefix)
    capture_key, capture_cid, preview_key, preview_cid = _cid_fields(original, 4)

    checkpoint_wire = read('effect_checkpoint_custody', 'checkpoint',
                           checkpoint, checkpoint, _MAX_PROJECTION)
    preview = read('effect_preview_custody', 'effect_preview', preview_key, preview_cid, _MAX_PROJECTION)
    capture = read('effect_capture_custody', 'effect_capture', capture_key, capture_cid, _MAX_PRIVATE)
    review = read('effect_review_projection_custody', 'review_projection',
                  checkpoint, review_cid, _MAX_PROJECTION)
    sizes = len(checkpoint_wire), len(preview), len(capture), len(review)
    packet_bytes = len(prefix) + _LENGTHS.size + sum(sizes)
    reserve(retained + packet_bytes)
    packet = b''.join((prefix, _LENGTHS.pack(*sizes),
                       checkpoint_wire, preview, capture, review))
    if consume(packet) is not None:
        raise ValueError('Invalid original Effect resolution consumer')
