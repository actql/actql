"""Project the two exact protected Ed25519 role keys on the local crypto port."""

from base64 import b64decode, b64encode
from binascii import Error as _B64Error
from collections.abc import Callable
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ._local_model_crypto import _OriginalEffectSignatureCrypto

_ED25519_SPKI = bytes.fromhex('302a300506032b6570032100')
_ED25519_PKCS8 = bytes.fromhex('302e020100300506032b657004220420')


def _canonical_pem_key(raw: bytes, purpose: bytes, prefix: bytes) -> bytes:
    begin, end = b'-----BEGIN ' + purpose + b'-----', b'-----END ' + purpose + b'-----'
    if not 0 < len(raw) <= 4096:
        raise ValueError('Original Local Ed25519 key extent is invalid')
    lines = raw.splitlines()
    if len(lines) < 3 or lines[0] != begin or lines[-1] != end:
        raise ValueError('Original Local Ed25519 key has a different role')
    encoded = b''.join(lines[1:-1])
    try:
        decoded = b64decode(encoded, validate=True)
    except _B64Error as cause:
        raise ValueError('Original Local Ed25519 PEM is invalid') from cause
    if (b64encode(decoded) != encoded or not decoded.startswith(prefix)
            or len(decoded) != len(prefix) + 32):
        raise ValueError('Original Local key is not an Ed25519 role key')
    return decoded[len(prefix):]


def _signature_bytes(wire: str) -> bytes:
    try:
        signature = b64decode(wire, validate=True)
    except _B64Error as cause:
        raise ValueError('Invalid original Local Effect proof encoding') from cause
    if len(signature) != 64 or b64encode(signature).decode('ascii') != wire:
        raise ValueError('Invalid original Local Effect proof extent')
    return signature


@dataclass(frozen=True, slots=True)
class _SelectedEffectApprovalKeys:
    """The Guest's exact two role selections, with independently decoded bytes."""

    reviewer_id: str
    reviewer_key_id: str
    reviewer: bytes
    host_key_id: str
    host: bytes

    @classmethod
    def admit(cls, *, reviewer_id: str, reviewer_key_id: str, reviewer_public: str,
              host_key_id: str, host_public: str) -> '_SelectedEffectApprovalKeys':
        reviewer = _canonical_pem_key(reviewer_public.encode('ascii'), b'PUBLIC KEY', _ED25519_SPKI)
        host = _canonical_pem_key(host_public.encode('ascii'), b'PUBLIC KEY', _ED25519_SPKI)
        if reviewer_key_id == host_key_id or reviewer == host:
            raise ValueError('Original Local Effect key roles alias')
        return cls(reviewer_id, reviewer_key_id, reviewer, host_key_id, host)

    def verify_reviewer(self, crypto: '_OriginalEffectSignatureCrypto',
                        actor: str, key: str, preimage: str, proof: str) -> bool:
        if actor != self.reviewer_id or key != self.reviewer_key_id:
            return False
        return crypto.verify_reviewer(self.reviewer, preimage.encode('ascii'), _signature_bytes(proof))

    def sign_host_attestation(self, crypto: '_OriginalEffectSignatureCrypto',
                              original: bytes, preimage: str,
                              require_current: Callable[[], None]) -> str:
        """Compare the actual signature against the distinct configured Host public key."""
        require_current()
        seed = _canonical_pem_key(original, b'PRIVATE KEY', _ED25519_PKCS8)
        cid = preimage.encode('ascii')
        candidate: list[bytes] = []
        crypto.sign_host_attestation(seed, cid, candidate.append)
        if len(candidate) != 1 or not crypto.verify_reviewer(self.host, cid, candidate[0]):
            raise ValueError('Original Local Host attestation key has changed')
        require_current()
        return b64encode(candidate[0]).decode('ascii')
