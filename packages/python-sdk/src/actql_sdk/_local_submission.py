"""Physical epoch authentication; identity and validity remain in Core."""
from collections.abc import Callable
from dataclasses import dataclass
import hashlib
import hmac
import json
import secrets
from typing import Any

from . import _wire
from ._local_storage import ByteFence, ByteWrite, LocalByteStore, LocalStorageError

_KEY = 'submission-epoch-authority'
_MAX_TTL = 7 * 24 * 60 * 60 * 1000
_MAX_CLOCK = 2**53 - 1 - _MAX_TTL


class LocalSubmissionIdentityError(RuntimeError):
    """Invalid or unknown authentication custody, never permission to resubmit."""


@dataclass(frozen=True)
class LocalSubmissionIdentity:
    request_id: str
    epoch_cid: str
    validity: str


def _json(payload: bytes) -> dict[str, Any]:
    def object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate field')
            result[key] = value
        return result
    try:
        if type(payload) is not bytes or len(payload) > 4096:
            raise ValueError('Invalid physical record size')
        result = json.loads(payload, object_pairs_hook=object_pairs)
        if type(result) is not dict:
            raise ValueError('Invalid physical record')
        return result
    except (ValueError, UnicodeError) as original:
        raise LocalSubmissionIdentityError('Local Submission material is unverifiable') from original


def _hex(value: object) -> bool:
    return type(value) is str and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


class LocalSubmissionAuthority:
    """Authenticate existing Owner epochs using durable physical key/clock bytes.

    The installed projection calls the current Core configuration's epoch and
    account Owners. This adapter cannot grant authorization, accept a Run, or
    interpret absence as retry permission. It never retries a physical CAS.
    """

    def __init__(self, store: LocalByteStore, project: Callable[[int, bytes], bytes], *,
                 now: Callable[[], int], ttl_ms: int = _MAX_TTL,
                 _initial_rows: tuple[ByteWrite, ...] = ()) -> None:
        if (type(store) is not LocalByteStore or not callable(project) or not callable(now)
                or type(ttl_ms) is not int or not 1 <= ttl_ms <= _MAX_TTL):
            raise ValueError('Invalid Local Submission epoch interval')
        self._original = self
        self._retained_key: bytes | None = None
        self._observed_clock = 0
        self._custody_fence: ByteFence | None = None
        self._store = store
        self._project = project
        self._now = now
        self._ttl = ttl_ms
        row = store.read(_KEY)
        fresh = store.claim_creation()
        if (type(_initial_rows) is not tuple or any(type(write) is not ByteWrite
                or write.expected_generation is not None or write.key == _KEY for write in _initial_rows)
                or _initial_rows and (row is not None or not fresh)):
            raise LocalSubmissionIdentityError('Original Local initial custody cannot be replaced')
        if row is None:
            if not fresh:
                raise LocalSubmissionIdentityError('Local Submission authentication custody is missing')
            payload = json.dumps({'authentication_key': secrets.token_hex(32),
                                  'observed_at': 0}, separators=(',', ':')).encode()
            try:
                if _initial_rows:
                    writes = (ByteWrite(_KEY, None, payload), *_initial_rows)
                    created = store.compare_exchange_many(writes) == (0,) * len(writes)
                else:
                    created = store.compare_exchange(_KEY, None, payload) == 0
                if not created:
                    raise LocalSubmissionIdentityError('Local Submission authority creation is unknown')
            except LocalStorageError as original:
                raise LocalSubmissionIdentityError('Local Submission authority creation is unknown') from original
        # Validate retained custody before exposing any issued epoch.
        self._retained_key, self._observed_clock = self._clock(advance=False)

    def _clock(self, *, advance: bool = True) -> tuple[bytes, int]:
        if self._original is not self:
            raise LocalSubmissionIdentityError('Copied Local Submission authentication custody')
        # Serialize only physical read/CAS and its retained observation. Core
        # projection runs after this lock is released, keeping Core -> Store
        # order and avoiding a separate authority/Run state machine.
        with self._store._lock:
            return self._clock_locked(advance=advance)

    def _clock_locked(self, *, advance: bool) -> tuple[bytes, int]:
        if self._original is not self:
            raise LocalSubmissionIdentityError('Copied Local Submission authentication custody')
        row = self._store.read(_KEY)
        if row is None:
            raise LocalSubmissionIdentityError('Local Submission authentication custody is missing')
        body = _json(row.payload)
        if (set(body) != {'authentication_key', 'observed_at'} or
                not _hex(body['authentication_key']) or
                type(body['observed_at']) is not int or not 0 <= body['observed_at'] <= _MAX_CLOCK):
            raise LocalSubmissionIdentityError('Local Submission authentication custody is corrupt')
        clock = body['observed_at']
        key = bytes.fromhex(body['authentication_key'])
        if ((self._retained_key is not None and key != self._retained_key)
                or clock < self._observed_clock):
            raise LocalSubmissionIdentityError('Original Local Submission authentication custody changed')
        self._custody_fence = ByteFence(_KEY, row.generation, row.payload)
        if advance:
            now = self._now()
            if type(now) is not int or not 0 <= now <= _MAX_CLOCK:
                raise LocalSubmissionIdentityError('Local Submission clock is invalid')
            clock = max(now, clock)
            if clock != body['observed_at']:
                body['observed_at'] = clock
                payload = json.dumps(body, separators=(',', ':')).encode()
                try:
                    if self._store.compare_exchange(_KEY, row.generation, payload) is None:
                        raise LocalSubmissionIdentityError('Local Submission clock persistence is unknown')
                except LocalStorageError as original:
                    raise LocalSubmissionIdentityError('Local Submission clock persistence is unknown') from original
        self._observed_clock = clock
        return key, clock

    def observe_custody(self) -> None:
        """Observe the same key/clock without issuing, advancing or projecting.

        This physical observation is not an epoch's validity, an Account grant
        or permission to send an operation. It never repairs lost custody.
        """
        self._clock(advance=False)

    def custody_fence(self) -> ByteFence:
        """Pin the observed physical row for the same read-only Store snapshot.

        A later explicit epoch issuance can advance the clock; its next frame
        observes a new fence. This is not a reference-validity or Allow proof.
        """
        with self._store._lock:
            self.observe_custody()
            assert self._custody_fence is not None
            return self._custody_fence

    def _projection(self, kind: int, body: dict[str, Any]) -> dict[str, Any]:
        result = _json(self._project(kind, json.dumps(body, ensure_ascii=False,
                                                    separators=(',', ':')).encode('utf-8')))
        fields = {'epoch_wire', 'epoch_cid'} if kind == 1 else {
            'epoch_wire', 'epoch_cid', 'request_id', 'validity'}
        if (set(result) != fields or any(type(result[field]) is not str for field in fields)
                or not result['epoch_cid'].startswith('sha256:') or
                not _hex(result['epoch_cid'][7:])):
            raise LocalSubmissionIdentityError('Local Submission Core projection is invalid')
        # Only Core encodes/hash-binds the body. The physical authenticator
        # signs those exact bytes, never a Python reconstruction of its JSON.
        epoch_body = _json(result['epoch_wire'].encode('utf-8'))
        if epoch_body != {field: body[field] for field in (
                'authority_scope_cid', 'epoch_nonce', 'not_before', 'expires_at')} | {
                    'version': 'actql-submission-epoch/0.1'}:
            raise LocalSubmissionIdentityError('Local Submission Core epoch binding is invalid')
        if kind == 2 and (not result['request_id'].startswith('sha256:') or
                          not _hex(result['request_id'][7:]) or
                          result['validity'] not in ('admissible', 'not_yet_valid', 'expired')):
            raise LocalSubmissionIdentityError('Local Submission Core identity is invalid')
        return result

    def issue_epoch(self, authority_scope_cid: str) -> dict[str, Any]:
        key, now = self._clock()
        body = {'authority_scope_cid': authority_scope_cid, 'epoch_nonce': secrets.token_hex(32),
                'not_before': now, 'expires_at': now + self._ttl}
        projection = self._projection(1, body)
        epoch = {'version': 'actql-submission-epoch/0.1', 'authorityScopeCid': authority_scope_cid,
                 'epochNonce': body['epoch_nonce'], 'notBefore': now, 'expiresAt': now + self._ttl,
                 'authenticator': hmac.new(key, projection['epoch_wire'].encode('utf-8'),
                                           hashlib.sha256).hexdigest()}
        if not _wire.epoch(epoch):  # type: ignore[no-untyped-call]
            raise LocalSubmissionIdentityError('Local Submission Core epoch is invalid')
        return epoch

    def identity(self, reference: object) -> LocalSubmissionIdentity:
        if not _wire.submission_ref(reference):  # type: ignore[no-untyped-call]
            raise LocalSubmissionIdentityError('Local Submission reference is invalid')
        assert isinstance(reference, dict)
        # Snapshot before calling Core or observing mutable clock storage.
        epoch = dict(reference['epoch'])
        nonce = reference['nonce']
        key, now = self._clock()
        projection = self._projection(2, {
            'authority_scope_cid': epoch['authorityScopeCid'], 'epoch_nonce': epoch['epochNonce'],
            'not_before': epoch['notBefore'], 'expires_at': epoch['expiresAt'],
            'caller_nonce': nonce, 'now': now})
        expected = hmac.new(key, projection['epoch_wire'].encode('utf-8'), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, epoch['authenticator']):
            raise LocalSubmissionIdentityError('Local Submission epoch authentication failed')
        # Expired lookup can still identify an original retained operation.
        # The admission Owner separately decides whether a fresh intent is allowed.
        return LocalSubmissionIdentity(projection['request_id'], projection['epoch_cid'],
                                       projection['validity'])


# Definition-time provenance for the fixed original reconciliation driver.
from ._local_prepare_provenance import _capture_prepare_methods
_PREPARE_METHODS = (
    _capture_prepare_methods(LocalSubmissionAuthority, (
        '_clock', '_clock_locked', 'custody_fence',
        'observe_custody',
    )),
)
