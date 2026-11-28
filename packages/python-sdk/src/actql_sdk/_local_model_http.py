"""Physical carrier for one original Local Model HTTP admission.

The caller retains this carrier until close acknowledges. Core owns the
entered Call, request projection, Raw sink, outcome and any retry decision.
"""
from __future__ import annotations

import asyncio
from collections.abc import Callable
from dataclasses import dataclass
import ssl
import sys
from threading import Lock, current_thread
from typing import TYPE_CHECKING, Literal, TypedDict, TypeVar, Unpack

import httpx

from ._local_work import OriginalLocalWork

if TYPE_CHECKING:
    from _typeshed import ReadableBuffer
    from ._local_core import LocalCore, _Input, _Output, _Task, _Workspace
    from ._local_files import _OriginalFileReader

_FailureKind = Literal['timeout', 'incomplete', 'extent', 'coding', 'cancelled', 'trust']
_HeaderSink = Callable[[int, list[tuple[bytes, bytes]]], None]
_FirstHeaderWrite = Callable[[Callable[[], int]], int]
_T = TypeVar('_T')
_MODEL_HTTP_CREDENTIAL_BYTES = 4096


class _ModelHttpRequestOptions(TypedDict):
    credential_for_entered_call: Callable[[], bytes]
    write_first_header: _FirstHeaderWrite
    timeout_ms: int
    request_limit: int
    header_limit: int
    body_limit: int
    chunk_limit: int
    chunks_limit: int


class _ModelHttpExchangeOptions(_ModelHttpRequestOptions):
    capture_headers: _HeaderSink
    append_raw: Callable[[bytes], None]


class _ModelHttpTransportFailure(RuntimeError):
    def __init__(self, kind: _FailureKind) -> None:
        self.kind = kind
        super().__init__('Original Model HTTP transport ' + kind)


@dataclass(frozen=True, slots=True)
class _CompleteModelHttpResponse:
    status: int
    body_bytes: int


class _OriginalModelTlsStream(ssl.SSLObject):
    _first_header_written = False

    def write(self, data: ReadableBuffer) -> int:
        if self._first_header_written:
            return super().write(data)
        context = self.context
        if not isinstance(context, _OriginalModelTlsContext) or context.first_header is None:
            raise ValueError('Original Model HTTP header write is unavailable')
        authorize = context.first_header
        context.first_header = None
        spent = False

        def enqueue() -> int:
            nonlocal spent
            if spent:
                raise ValueError('Original Model HTTP header write is already consumed')
            spent = True
            # AnyIO uses this object's MemoryBIO. Authorize only the local
            # enqueue. The inspected reader returns before AnyIO can flush it
            # into the socket. A failed first enqueue never rearms the Call.
            try:
                return ssl.SSLObject.write(self, data)
            except (ssl.SSLWantReadError, ssl.SSLWantWriteError):
                raise _ModelHttpTransportFailure('incomplete') from None

        written = authorize(enqueue)
        if not spent or type(written) is not int or written <= 0:
            raise _ModelHttpTransportFailure('incomplete')
        self._first_header_written = True
        return written


class _OriginalModelTlsContext(ssl.SSLContext):
    sslobject_class = _OriginalModelTlsStream
    first_header: _FirstHeaderWrite | None = None


class _OriginalModelHttpTransport:
    """One HTTP connection under the existing Model Call's physical lifetime."""

    def __init__(self, trust: _OriginalModelTlsContext | None) -> None:
        if trust is not None and type(trust) is not _OriginalModelTlsContext:
            raise ValueError('Foreign original Model TLS context')
        self._original = self
        self._trust = trust
        self._trust_ready = True
        self._httpx_transport: httpx.AsyncHTTPTransport | None = None
        self._client: httpx.AsyncClient | None = None
        self._started = self._sending = self._close_attempted = self._closed = False
        self._worker_lock = Lock()
        self._worker_invoked = False
        self._stop_requested = False
        self._active_exchange: tuple[asyncio.AbstractEventLoop, asyncio.Task[object]] | None = None
        self._cleanup_failure: BaseException | None = None

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign original Model HTTP transport')

    def _prepare_selected_trust(self, read: Callable[[Callable[[str], None]], _T]) -> _T:
        self._nominal()
        if (self._trust is not None or not self._trust_ready or self._worker_invoked
                or self._started or self._close_attempted):
            raise ValueError('Original Model HTTP trust is unavailable')
        self._trust_ready = False
        loaded = False

        def load(pem: str) -> None:
            nonlocal loaded
            try:
                if self._trust is not None:
                    raise ValueError('Original Model HTTP trust has already been prepared')
                # The loader may fail after OpenSSL allocated native backing.
                self._trust = _OriginalModelTlsContext(ssl.PROTOCOL_TLS_CLIENT)
                self._trust.load_verify_locations(cadata=pem)
                loaded = True
            finally:
                del pem

        original = read(load)
        if not loaded:
            raise ValueError('Original Model HTTP trust was not loaded')
        self._trust_ready = True
        return original

    def _retire_before_exchange_or_confirm_close(self) -> bool:
        self._nominal()
        with self._worker_lock:
            if self._worker_invoked or self._started:
                return self._closed
            self._trust = None
            self._close_attempted = self._closed = True
            return True

    def run_on_original_work(
        self, work: OriginalLocalWork, endpoint: str, body: bytes,
        **options: Unpack[_ModelHttpExchangeOptions],
    ) -> _CompleteModelHttpResponse:
        """Drive only the existing worker's admitted exchange and retirement."""
        self._nominal()
        work._nominal()
        if current_thread() is not work._thread:
            raise ValueError('Foreign original Model HTTP worker')
        with self._worker_lock:
            if self._worker_invoked or self._started or self._close_attempted:
                raise ValueError('Original Model HTTP transport is already consumed')
            self._worker_invoked = True
        return asyncio.run(self._run_exchange(endpoint, body, options))

    def request_stop(self) -> None:
        """Deliver physical stop interest from the same admitted Call."""
        self._nominal()
        with self._worker_lock:
            if self._stop_requested:
                return
            self._stop_requested = True
            if self._active_exchange is not None:
                loop, task = self._active_exchange
                loop.call_soon_threadsafe(self._interrupt_exchange, task)

    def _interrupt_exchange(self, task: asyncio.Task[object]) -> None:
        with self._worker_lock:
            if self._active_exchange is not None and self._active_exchange[1] is task:
                task.cancel()

    async def _run_exchange(
        self, endpoint: str, body: bytes, options: _ModelHttpExchangeOptions,
    ) -> _CompleteModelHttpResponse:
        task = asyncio.current_task()
        assert task is not None
        with self._worker_lock:
            self._active_exchange = (asyncio.get_running_loop(), task)
            stop_requested = self._stop_requested
        try:
            try:
                if stop_requested:
                    raise _ModelHttpTransportFailure('cancelled')
                complete = await self.exchange(endpoint, body, **options)
            except asyncio.CancelledError:
                raise _ModelHttpTransportFailure('cancelled') from None
            finally:
                # An interrupt already queued to this event loop may arrive
                # during close. It cannot cancel the original retirement.
                with self._worker_lock:
                    self._active_exchange = None
        except BaseException:
            try:
                await self._close_worker_exchange()
            except BaseException:
                # Propagate the transport/Raw failure. Physical close remains
                # separately observable on this retained carrier.
                pass
            raise
        await self._close_worker_exchange()
        return complete

    async def _close_worker_exchange(self) -> None:
        try:
            if not await self.close():
                raise RuntimeError('Original Model HTTP transport cleanup is pending')
        except BaseException as failure:
            self._cleanup_failure = failure
            raise

    async def exchange(self, endpoint: str, body: bytes, *,
                       credential_for_entered_call: Callable[[], bytes],
                       write_first_header: _FirstHeaderWrite,
                       timeout_ms: int, request_limit: int, header_limit: int,
                       body_limit: int, chunk_limit: int, chunks_limit: int,
                       capture_headers: _HeaderSink,
                       append_raw: Callable[[bytes], None]) -> _CompleteModelHttpResponse:
        """Send the already projected body and stream bounded Raw to the Owner.

        The credential callback rechecks the same entered Call. No other
        credential lookup, request reconstruction or retry takes place here.
        """
        self._nominal()
        if self._started or self._close_attempted:
            raise ValueError('Original Model HTTP transport is already consumed')
        self._started = True
        try:
            url = httpx.URL(endpoint)
        except httpx.InvalidURL:
            raise ValueError('Invalid installed Model HTTP endpoint') from None
        if (url.scheme != 'https' or not url.host or url.userinfo or '#' in endpoint
                or str(url) != endpoint):
            raise ValueError('Invalid installed Model HTTP endpoint or TLS trust')
        if (any(type(value) is not int or value <= 0 for value in
                (timeout_ms, request_limit, header_limit, body_limit, chunk_limit, chunks_limit))
                or type(body) is not bytes or len(body) > request_limit or chunk_limit > body_limit):
            raise ValueError('Original Model HTTP request exceeds its admitted bounds')

        if not self._trust_ready:
            raise ValueError('Original Model HTTP trust is incomplete')
        if self._trust is None:
            # Use the same bundled roots as ordinary HTTPX. Construct the
            # context explicitly so SSL_CERT_* and SSLKEYLOGFILE cannot
            # replace the trust or open a TLS key log on the Model worker.
            from certifi import where
            self._trust = _OriginalModelTlsContext(ssl.PROTOCOL_TLS_CLIENT)
            self._trust.load_verify_locations(cafile=where())
        if (not self._trust.check_hostname or self._trust.verify_mode != ssl.CERT_REQUIRED
                or self._trust.keylog_filename is not None):
            raise ValueError('Invalid installed Model HTTP endpoint or TLS trust')
        credential = credential_for_entered_call()
        if (type(credential) is not bytes or not credential
                or any(value < 33 or value > 126 for value in credential)):
            raise ValueError('Invalid original Model HTTP credential')
        timeout = timeout_ms / 1000
        # Keep the constructed transport even if the client constructor fails.
        self._httpx_transport = httpx.AsyncHTTPTransport(verify=self._trust, trust_env=False, retries=0,
            limits=httpx.Limits(max_connections=1, max_keepalive_connections=0))
        self._client = httpx.AsyncClient(
            transport=self._httpx_transport, trust_env=False, follow_redirects=False,
            timeout=httpx.Timeout(timeout))
        certificate_refused = False

        async def observe_tls(event: str, detail: dict[str, object]) -> None:
            nonlocal certificate_refused
            if event == 'connection.start_tls.failed':
                # The selected backend passes the typed SSL cause at this
                # boundary. The connection pool clears it before HTTPX returns.
                failure = detail.get('exception')
                certificate_refused = (isinstance(failure, BaseException)
                                       and isinstance(failure.__cause__, ssl.SSLCertVerificationError))

        self._trust.first_header = write_first_header
        self._sending = True
        try:
            async with asyncio.timeout(timeout):
                async with self._client.stream('POST', url, content=body, headers={
                    b'authorization': b'Bearer ' + credential,
                    b'content-type': b'application/json',
                    b'accept': b'application/json',
                    b'accept-encoding': b'identity',
                }, extensions={'trace': observe_tls}) as response:
                    headers = response.headers.raw
                    if sum(len(name) + len(value) + 4 for name, value in headers) > header_limit:
                        raise _ModelHttpTransportFailure('extent')
                    encodings = [value.strip().lower() for name, value in headers
                                 if name.lower() == b'content-encoding']
                    if encodings not in ([], [b'identity']):
                        raise _ModelHttpTransportFailure('coding')
                    capture_headers(response.status_code, headers)
                    received = chunks = 0
                    async for chunk in response.aiter_raw(chunk_size=chunk_limit):
                        received += len(chunk)
                        chunks += 1
                        if received > body_limit or chunks > chunks_limit:
                            raise _ModelHttpTransportFailure('extent')
                        append_raw(chunk)
                    return _CompleteModelHttpResponse(response.status_code, received)
        except (TimeoutError, httpx.TimeoutException):
            raise _ModelHttpTransportFailure('timeout') from None
        except httpx.HTTPError as failure:
            kind: _FailureKind = ('trust' if isinstance(failure, httpx.ConnectError) and certificate_refused
                                  else 'incomplete')
            raise _ModelHttpTransportFailure(kind) from None
        finally:
            self._sending = False
            self._trust.first_header = None

    async def close(self) -> bool:
        """Accept actual close once. Interrupted aclose retains unknown custody."""
        self._nominal()
        if self._sending:
            return False
        if self._closed:
            return True
        if self._close_attempted:
            return False
        self._close_attempted = True
        if self._client is not None:
            # HTTPX marks a client closed before awaiting its connections.
            # A later no-op cannot prove an interrupted physical close.
            await self._client.aclose()
        elif self._httpx_transport is not None:
            await self._httpx_transport.aclose()
        self._client = None
        self._httpx_transport = None
        self._trust = None
        self._closed = True
        return True


class _OriginalModelHttpRawTransfer:
    """Hold the original worker's bounded response until Core returns its loan."""

    def __init__(self, core: LocalCore, work: OriginalLocalWork,
                 transport: _OriginalModelHttpTransport) -> None:
        self._original = self
        self._core = core
        self._work = work
        self._request_started = False
        self._transport = transport
        self._workspace: _Workspace | None = None
        self._trust_workspace: _Workspace | None = None
        self._trust_reader: _OriginalFileReader | None = None
        self._input: _Input | None = None
        self._uncertain_ticket: int | None = None
        self._buffer: bytearray | None = None
        self._written = 0
        self._invoked = self._active = self._closing = False

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Model HTTP Raw transfer')

    def _prepare_selected_trust(self, workspace_bytes: int,
                                read: Callable[[Callable[[str], None]], None]) -> None:
        self._nominal()
        if current_thread() is not self._work._thread:
            raise ValueError('Foreign original Model HTTP trust worker')
        core = self._core
        with core._borrow_work_operation(self._work) as retained:
            if (not retained or self._invoked or self._closing or self._trust_workspace is not None
                    or self._uncertain_ticket is not None):
                raise ValueError('Original Model HTTP trust is unavailable')
            # The caller provides the admitted profile peak before the CA
            # open. This workspace is separate from the worker's AEAD arena.
            self._trust_workspace = self._reserve(lambda: core.reserve_workspace(
                workspace_bytes, stopped=self._ready_to_retire, cleanup=self._retire_selected_trust))

            def read_original(load: Callable[[str], None]) -> None:
                read(load)
                if self._trust_reader is None:
                    raise ValueError('Original Model HTTP trust reader is unavailable')

            self._transport._prepare_selected_trust(read_original)

    def _reserve(self, acquire: Callable[[], _T]) -> _T:
        ticket = self._core._next_ticket
        try:
            return acquire()
        except BaseException:
            if ticket in self._core._inputs or ticket in self._core._released:
                self._uncertain_ticket = ticket
            raise

    def _append(self, chunk: bytes) -> None:
        buffer = self._buffer
        if (buffer is None or current_thread() is not self._work._thread
                or len(chunk) > len(buffer) - self._written):
            raise _ModelHttpTransportFailure('extent')
        end = self._written + len(chunk)
        buffer[self._written:end] = chunk
        self._written = end

    def run(
        self, endpoint: str, body: bytes, *, before_exchange: Callable[[], None],
        **options: Unpack[_ModelHttpRequestOptions],
    ) -> tuple[_CompleteModelHttpResponse, _Input]:
        """Send once and fill the existing binary input after complete EOF."""
        self._nominal()
        work = self._work
        core = self._core
        if current_thread() is not work._thread:
            raise ValueError('Foreign original Model HTTP Raw worker')
        limit = options['body_limit']
        if type(limit) is not int or limit <= 0 or limit > sys.maxsize:
            raise ValueError('Invalid original Model HTTP Raw bound')
        # The fixed receive backing and immutable handoff coexist until Core
        # owns the input. Transport workspace and the Wasm copy are separate.
        # The credential file read, returned value and authorization header
        # can overlap the receive backing. Use the bounded Model credential
        # allowance for those copies and the physical reader's controls.
        credential_bytes = 1024 + 8 * _MODEL_HTTP_CREDENTIAL_BYTES
        capture_bytes = (2 * limit + sys.getsizeof(bytearray()) + 1 + sys.getsizeof(b'')
                         + 2 * sys.getsizeof(memoryview(b'')) + credential_bytes)
        with core._borrow_work_operation(work) as retained:
            if not retained or self._invoked or self._closing:
                raise ValueError('Original Model HTTP Raw transfer is unavailable')
            self._invoked = self._active = True
        try:
            with core._borrow_work_operation(work) as retained:
                if not retained or self._closing:
                    raise ValueError('Original Model HTTP Raw transfer is unavailable')
                self._workspace = self._reserve(lambda: core.reserve_workspace(
                    capture_bytes, stopped=self._ready_to_retire, cleanup=self._discard_buffer))
                self._buffer = bytearray(limit)
            # The entered worker can claim only after its fixed Raw backing
            # has been funded. Its owner may yield during the original check.
            before_exchange()
            complete = self._transport.run_on_original_work(work, endpoint, body, **options,
                capture_headers=lambda _status, _headers: None, append_raw=self._append)
            with core._borrow_work_operation(work) as retained:
                if (not retained or self._closing or self._buffer is None
                        or complete.body_bytes != self._written):
                    raise ValueError('Original Model HTTP Raw completion changed')
                packet = bytes(memoryview(self._buffer)[:self._written])
                self._input = self._reserve(lambda: core.reserve_input(packet,
                    cleanup=self._ready_to_retire, stopped=lambda _: self._ready_to_retire()))
                for start in range(0, len(packet), 16384):
                    core.fill_input(self._input, start, min(16384, len(packet) - start))
                # Provider bytes can be invalid UTF-8 or JSON. The Wasm
                # consumer borrows this filled binary slot without sealing it.
                return complete, self._input
        finally:
            with core._lock:
                self._active = False

    def run_entered(
        self, task: _Task, material: _Output, *,
        observe: Callable[[Callable[[_Input], None]], None],
        credential_for_entered_call: Callable[[], bytes],
    ) -> tuple[_CompleteModelHttpResponse, _Input]:
        """Use the same copied request and this worker's one physical Call."""
        self._nominal()
        if current_thread() is not self._work._thread:
            raise ValueError('Foreign original Model HTTP Raw worker')
        core = self._core
        with core._borrow_work_operation(self._work) as retained:
            if not retained or self._invoked or self._closing:
                raise ValueError('Original Model HTTP Raw transfer is unavailable')
            frame = core.read_material(material).split(b'\n', 7)
            if len(frame) != 8:
                raise ValueError('Invalid original Model HTTP request framing')
            endpoint = frame[0].decode('utf-8')
            timeout, request, headers, response, chunk, chunks = (
                int(field) for field in frame[1:7])

        claimed = False

        def claim(clock: _Input) -> None:
            nonlocal claimed
            with core._borrow_work_operation(self._work) as retained:
                if not retained:
                    raise ValueError('Original Model HTTP Raw transfer is unavailable')
                core.claim_task_model_request(task, clock, material)
                claimed = True

        def credential() -> bytes:
            original: list[bytes] = []

            def acquire(clock: _Input) -> None:
                with core._borrow_work_operation(self._work) as retained:
                    if not retained:
                        raise ValueError('Original Model HTTP Raw transfer is unavailable')
                    core.check_task_model_request(task, clock, material)
                    original.append(credential_for_entered_call())

            observe(acquire)
            return original[0]

        def write_first_header(enqueue: Callable[[], int]) -> int:
            written: list[int] = []

            def authorize(clock: _Input) -> None:
                with core._borrow_work_operation(self._work) as retained:
                    if not retained or self._closing:
                        raise ValueError('Original Model HTTP Raw transfer is unavailable')
                    core.check_task_model_request(task, clock, material)
                    reader = self._trust_reader
                    if reader is not None:
                        reader.root.observe_original(reader)
                    count = enqueue()
                    if type(count) is int and count > 0:
                        self._request_started = True
                    written.append(count)

            observe(authorize)
            return written[0]

        def retire(response: _Input | None, status: int) -> None:
            if claimed and self._ready_to_retire():
                with core._borrow_work_operation(self._work) as retained:
                    if not retained:
                        raise RuntimeError('Original Model HTTP worker lost its custody')
                    core.finish_task_model_request(task, material, response=response, status=status)

        try:
            # The original read can yield to a control turn once its frame
            # closes. Do not hold the outer Core lock across that observation.
            result = self.run(endpoint, frame[7], before_exchange=lambda: observe(claim),
                credential_for_entered_call=credential, write_first_header=write_first_header,
                timeout_ms=timeout, request_limit=request,
                header_limit=headers, body_limit=response, chunk_limit=chunk, chunks_limit=chunks)
        except BaseException as primary:
            # A failed close stays in original custody. A failed preparation
            # that never invoked the exchange has no physical client to retire.
            try:
                retire(None, 0)
            except BaseException as retirement:
                raise primary from retirement
            raise
        retire(result[1], result[0].status)
        return result

    def _ready_to_retire(self) -> bool:
        return not self._active and (not self._transport._worker_invoked or self._transport._closed)

    def _retire_selected_trust(self) -> bool:
        if (not self._ready_to_retire()
                or not self._transport._retire_before_exchange_or_confirm_close()):
            return False
        reader = self._trust_reader
        if reader is None:
            return True
        if not reader.root.close_original(reader):
            return False
        self._trust_reader = None
        return True

    def _discard_buffer(self) -> bool:
        if not self._ready_to_retire():
            return False
        self._buffer = None
        return True

    def close(self) -> bool:
        """Return this same input and workspace after physical retirement."""
        self._nominal()
        core = self._core
        with core._lock:
            self._closing = True
            if (not self._ready_to_retire()
                    or not self._transport._retire_before_exchange_or_confirm_close()):
                return False
            if self._uncertain_ticket is not None:
                if not core._retired or self._uncertain_ticket in core._inputs:
                    return False
                self._uncertain_ticket = None
            if core._retired:
                if (self._trust_reader is not None or any(
                        loan is not None and loan.ticket in core._inputs
                        for loan in (self._input, self._workspace, self._trust_workspace))):
                    return False
                self._input = None
                self._workspace = None
                self._trust_workspace = None
                return True
            if self._input is None and self._workspace is None and self._trust_workspace is None:
                return True
            with core._host_cleanup():
                if self._input is not None:
                    if not core.close_input(self._input):
                        return False
                    self._input = None
                if self._workspace is not None:
                    if not core.close_workspace(self._workspace):
                        return False
                    self._workspace = None
                if self._trust_workspace is not None:
                    if not core.close_workspace(self._trust_workspace):
                        return False
                    self._trust_workspace = None
            return True
