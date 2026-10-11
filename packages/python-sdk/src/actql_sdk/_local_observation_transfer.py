"""Bounded original Store bytes transported into existing Core input custody."""
from collections.abc import Callable

from ._local_commit_projection import OriginalCommitProjection
from ._local_core import _Input, _Output, _Workspace


class OriginalObservationTransfer:
    """Private physical transfer, not publication or recovery decision making.

    Reserve before the same Store snapshot copies any rows. The workspace covers
    this transfer's bounded source bytes, fixed byte buffer and immutable packet
    copy; Core separately charges the retained input and Wasm copy. The trusted
    Host must reserve SQLite/descriptor/other simultaneous loans separately and
    hold the original File/six facts/current publisher fences through inspection
    and adoption. This holder neither supplies those facts nor finishes a commit.

    The wrapper quotes raw contract bytes without parsing, normalizing or
    computing identities. Core still admits UTF-8/contracts, checks the original
    scope/index references and validates the complete stored chain. NotFound and
    QueryFailed come only from the trusted original Store query, never SDK input.

    A failure retains the same workspace/input. Discard retained row/encoding
    references and failure tracebacks after physical cleanup, then explicitly
    close. The original Core borrower must return its loan first; close does not
    retire another borrow, close parents, cancel a Run or replay a Store operation.
    """

    def __init__(self, projection: OriginalCommitProjection, publisher: _Output, *,
                 max_source_bytes: int, max_packet_bytes: int,
                 cleanup: Callable[[], bool], stopped: Callable[[int], bool],
                 workspace_cleanup: Callable[[], bool], workspace_stopped: Callable[[], bool]) -> None:
        if (type(projection) is not OriginalCommitProjection
                or not callable(cleanup) or not callable(stopped)
                or not callable(workspace_cleanup) or not callable(workspace_stopped)
                or any(type(n) is not int or not 0 < n <= 1_048_576
                       for n in (max_source_bytes, max_packet_bytes))):
            raise ValueError('Invalid original Store observation transfer')
        core = projection._core
        with core._lock:
            projection._ready()
            core._owned_output(publisher, 'publisher')
        self._original = self
        self._projection = projection
        self._publisher = publisher
        self._source_limit = max_source_bytes
        self._packet_limit = max_packet_bytes
        # No growing buffer or decoded Unicode strings. A fixed byte buffer and
        # its immutable bytes copy coexist with the bounded original raw rows.
        self._workspace_bytes = max_source_bytes + 2 * max_packet_bytes + 4096
        self._cleanup = cleanup
        self._stopped = stopped
        self._workspace_cleanup = workspace_cleanup
        self._workspace_stopped = workspace_stopped
        self._workspace: _Workspace | None = None
        self._input: _Input | None = None
        self._uncertain_ticket: int | None = None
        self._active = False
        self._closing = False
        self._failed = False

    @property
    def pending_input(self) -> _Input | None:
        with self._projection._core._lock:
            self._nominal()
            return self._input

    @property
    def pending_workspace(self) -> _Workspace | None:
        with self._projection._core._lock:
            self._nominal()
            return self._workspace

    @property
    def uncertain_acquisition_ticket(self) -> int | None:
        with self._projection._core._lock:
            self._nominal()
            return self._uncertain_ticket

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Store observation transfer')

    def _ready(self) -> None:
        self._nominal()
        if self._closing or self._active or self._failed or self._uncertain_ticket is not None:
            raise RuntimeError('Original Store observation transfer requires cleanup')
        self._projection._current()

    def reserve(self) -> None:
        """Charge the existing workspace Owner before physical row allocation."""
        core = self._projection._core
        with core._lock:
            self._ready()
            if self._workspace is not None:
                raise RuntimeError('Original Store observation workspace is already reserved')
            ticket = core._next_ticket
            try:
                self._workspace = core.reserve_workspace(
                    self._workspace_bytes, stopped=self._workspace_stopped,
                    cleanup=self._workspace_cleanup)
            except BaseException:
                self._failed = True
                if ticket in core._inputs:
                    self._uncertain_ticket = ticket
                raise

    def transfer_lookup(self, reference: bytes, index: bytes) -> None:
        """Forward the physically read index reference/body, not a candidate."""
        self._transfer(((b'identity', reference), (b'index', index)), lookup=True)

    def transfer_stored(self, request: bytes, attempt: bytes, index: bytes) -> None:
        """Forward actual stored contracts; Core decides full-chain validity."""
        self._transfer(((b'kind', b'stored'), (b'request', request),
                        (b'attempt', attempt), (b'index', index)), lookup=False)

    def transfer_not_found(self) -> None:
        """Transport confirmed original scoped-key absence, never replay permission."""
        self._transfer(((b'kind', b'not_found'),), lookup=False)

    def transfer_query_failure(self) -> None:
        """Transport a failed original query; durable Unknown remains separate."""
        self._transfer(((b'kind', b'query_failed'),), lookup=False)

    def _transfer(self, fields: tuple[tuple[bytes, bytes], ...], *, lookup: bool) -> None:
        core = self._projection._core
        with core._lock:
            self._ready()
            if self._workspace is None or self._input is not None:
                raise RuntimeError('Original Store observation requires its reserved workspace')
            self._active = True
            try:
                packet = self._packet(fields)
                ticket = core._next_ticket
                try:
                    self._input = core.reserve_input(
                        packet, cleanup=self._cleanup, stopped=self._stopped)
                except BaseException:
                    if ticket in core._inputs:
                        self._uncertain_ticket = ticket
                    raise
                core.fill_input(self._input, 0, len(packet))
                core.seal_input(self._input)
                if lookup:
                    core.prepare_publication_lookup(
                        self._projection._publication, self._input,
                        self._publisher, self._projection._configuration)
                else:
                    core.prepare_publication_observation(
                        self._projection._publication, self._input,
                        self._publisher, self._projection._configuration)
            except BaseException:
                self._failed = True
                raise
            finally:
                self._active = False

    def _packet(self, fields: tuple[tuple[bytes, bytes], ...]) -> bytes:
        if (any(type(raw) is not bytes for _, raw in fields)
                or sum(len(raw) for _, raw in fields) > self._source_limit):
            raise ValueError('Original Store observation source exceeds its bound')
        # Count before allocating. Only the envelope is JSON-escaped; original
        # contract bytes are never parsed or reserialized. Invalid UTF-8 remains
        # invalid and is rejected by the existing Core admission decoder.
        size = 1 + len(fields)
        for key, raw in fields:
            size += len(key) + 5 + sum(6 if b < 32 else 2 if b in (34, 92) else 1
                                     for b in raw)
        if size > self._packet_limit:
            raise ValueError('Original Store observation packet exceeds its bound')
        buffer = bytearray(size)
        position = 0
        def literal(raw: bytes) -> None:
            nonlocal position
            buffer[position:position + len(raw)] = raw
            position += len(raw)
        literal(b'{')
        for ordinal, (key, raw) in enumerate(fields):
            if ordinal:
                literal(b',')
            literal(b'"' + key + b'":"')
            for byte in raw:
                if byte < 32:
                    literal(b'\\u00' + bytes((b'0123456789abcdef'[byte >> 4],
                                               b'0123456789abcdef'[byte & 15])))
                elif byte in (34, 92):
                    literal(bytes((92, byte)))
                else:
                    buffer[position] = byte
                    position += 1
            literal(b'"')
        literal(b'}')
        assert position == size
        return bytes(buffer)

    def close(self) -> bool:
        """Return only this same physical input/workspace after original borrow cleanup."""
        core = self._projection._core
        with core._lock:
            self._nominal()
            if self._active:
                raise RuntimeError('Original Store observation transfer is still active')
            self._closing = True
            if self._uncertain_ticket is not None:
                if not core._retired or self._uncertain_ticket in core._inputs:
                    return False
                self._uncertain_ticket = None
            if self._input is not None:
                if core._retired:
                    if self._input.ticket in core._inputs:
                        return False
                elif not core.close_input(self._input):
                    return False
                self._input = None
            if self._workspace is not None:
                if core._retired:
                    if self._workspace.ticket in core._inputs:
                        return False
                elif not core.close_workspace(self._workspace):
                    return False
                self._workspace = None
            return True
