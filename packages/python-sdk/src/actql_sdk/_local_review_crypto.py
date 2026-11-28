"""The installed AEAD on the original Mock Review Store envelope."""

from base64 import b64decode, b64encode
from binascii import Error as Base64Error
from collections.abc import Callable
import re

from ._local_model_crypto import _OriginalModelEvidenceCrypto
from ._local_storage import LocalStorageError

_PREFIX = b'{"version":"actql-private-publication-evidence/0.1","nonce":"'
_TAG = b'","tag":"'
_CIPHERTEXT = b'","ciphertext":"'
_END = b'"}'
_NONCE_START = len(_PREFIX)
_NONCE_END = _NONCE_START + 16
_TAG_START = _NONCE_END + len(_TAG)
_TAG_END = _TAG_START + 24
_CIPHERTEXT_START = _TAG_END + len(_CIPHERTEXT)
_OVERHEAD = _CIPHERTEXT_START + len(_END)
_MAX_PLAINTEXT = 1_048_576
_ROLES = ('effect_capture', 'effect_preview', 'continuation_record', 'checkpoint', 'review_projection')


def _aad(key: bytes, role: str, cid: str, maximum: int) -> bytes:
    if (type(key) is not bytes or len(key) != 32 or type(role) is not str or role not in _ROLES
            or type(cid) is not str or re.fullmatch(r'sha256:[0-9a-f]{64}', cid) is None
            or type(maximum) is not int or maximum < _OVERHEAD):
        raise LocalStorageError('Invalid original Mock Review cipher coordinates')
    return b'actql-private-publication-evidence/0.1\0' + role.encode('ascii') + b'\0' + cid.encode('ascii')


def _canonical_base64(encoded: bytes) -> bytes:
    try:
        body = b64decode(encoded, validate=True)
    except Base64Error as primary:
        raise LocalStorageError('Invalid original Mock Review envelope encoding') from primary
    if b64encode(body) != encoded:
        raise LocalStorageError('Invalid original Mock Review envelope encoding')
    return body


def seal_review_evidence(crypto: _OriginalModelEvidenceCrypto, key: bytes, role: str,
                         cid: str, original: bytes, *, maximum: int,
                         reserve: Callable[[int], None]) -> bytes:
    """Translate the existing native nonce/body/tag packet into the Store wire."""
    aad = _aad(key, role, cid, maximum)
    count = len(original) if type(original) is bytes else 0
    if not 0 < count <= _MAX_PLAINTEXT:
        raise LocalStorageError('Invalid original Mock Review plaintext extent')
    encoded = 4 * ((count + 2) // 3)
    extent = _OVERHEAD + encoded
    if extent > maximum:
        raise LocalStorageError('Original Mock Review envelope exceeds Store extent')
    # The native child funds its packet. This Store operation owns the textual
    # segments and their joined immutable output until SQLite consumes it.
    reserve(encoded + extent + 4096)
    result: list[bytes] = []

    def encode(packet: bytes) -> None:
        if len(packet) != count + 28:
            raise LocalStorageError('Original Mock Review cipher returned an incomplete packet')
        view = memoryview(packet)
        result.append(b''.join((_PREFIX, b64encode(view[:12]), _TAG, b64encode(view[-16:]),
                                _CIPHERTEXT, b64encode(view[12:-16]), _END)))

    crypto.seal(key, aad, original, encode)
    return result[0]


def open_review_evidence(crypto: _OriginalModelEvidenceCrypto, key: bytes, role: str,
                         cid: str, envelope: bytes, *, maximum: int,
                         reserve: Callable[[int], None]) -> bytes:
    """Check the canonical original envelope before creating any plaintext."""
    aad = _aad(key, role, cid, maximum)
    if (type(envelope) is not bytes or not _OVERHEAD < len(envelope) <= maximum
            or not envelope.startswith(_PREFIX) or not envelope.endswith(_END)
            or envelope[_NONCE_END:_TAG_START] != _TAG
            or envelope[_TAG_END:_CIPHERTEXT_START] != _CIPHERTEXT):
        raise LocalStorageError('Invalid original Mock Review envelope')
    encoded = len(envelope) - _OVERHEAD
    padding = 2 if envelope.endswith(b'=="}') else 1 if envelope.endswith(b'="}') else 0
    count = 3 * (encoded // 4) - padding
    if encoded % 4 or not 0 < count <= _MAX_PLAINTEXT:
        raise LocalStorageError('Invalid original Mock Review ciphertext extent')
    # The Store still owns the envelope. Charge the Base64 slice/comparison,
    # reconstructed packet and the plaintext derived from the native output.
    reserve(2 * encoded + 3 * count + 4096)
    nonce = _canonical_base64(envelope[_NONCE_START:_NONCE_END])
    tag = _canonical_base64(envelope[_TAG_START:_TAG_END])
    ciphertext = _canonical_base64(envelope[_CIPHERTEXT_START:-len(_END)])
    if len(nonce) != 12 or len(tag) != 16 or len(ciphertext) != count:
        raise LocalStorageError('Invalid original Mock Review ciphertext extent')
    result: list[bytes] = []
    crypto.authenticate(key, aad, b''.join((nonce, ciphertext, tag)), result.append)
    return result[0]
