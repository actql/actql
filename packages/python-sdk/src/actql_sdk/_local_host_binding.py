"""Original physical Host supplier for the existing Common current/scope Owner."""
from collections.abc import Callable, Iterator
from contextlib import contextmanager
import json
from threading import get_ident
from types import MethodType
from typing import Any, TypeVar

from ._local_core import (LocalCore, _Input, _Output, _Workspace, _PhysicalInput,
                          _PublisherCallbacks, _PublisherFact)
from ._local_host_files import LocalHostFiles, _HostFile
from ._local_storage import ByteFence, LocalByteStore, LocalStorageError, StoredBytes, _NamespaceReader
from ._local_submission import LocalSubmissionAuthority
from ._local_storage_physical import _TrackedSQLiteConnection

_T = TypeVar('_T')


class _OriginalPublisherPort:
    """The installed physical fence, never an Account decision or grant.

    Only these two original callbacks are closed: every call still observes
    the binding and authorize still compares the supplied namespace. Common
    separately checks all six facts, Account, Policy and the original target.
    """
    __slots__ = ('original', 'core', 'binding', 'installation', 'observer',
                 'current_callback', 'authorize_callback', 'output', 'physical',
                 'callbacks', 'failure')

    def __init__(self, binding: 'OriginalHostBinding') -> None:
        self.original = self
        self.core, self.binding = binding._core, binding
        self.installation = binding._source._installation
        self.observer = binding._current_observer
        self.current_callback, self.authorize_callback = self.current, self.authorize
        self.output: _Output | None = None
        self.physical: _PhysicalInput | None = None
        self.callbacks: _PublisherCallbacks | None = None
        self.failure: BaseException | None = None
        self._require_original()

    def _require_original(self) -> None:
        from ._local_installation import OriginalLocalInstallation
        binding, installation = self.binding, self.installation
        if self.failure is not None:
            raise self.failure
        if (self.original is not self or type(binding) is not OriginalHostBinding
                or binding._original is not binding or binding._core is not self.core
                or binding._closing or type(installation) is not OriginalLocalInstallation
                or installation._original is not installation or installation._closing
                or installation._core is not self.core or installation._binding is not binding
                or binding._source._installation is not installation
                or binding._state._installation is not installation
                or binding._current_observer is not self.observer
                or type(self.observer) is not MethodType
                or self.observer.__self__ is not binding
                or self.observer.__func__ is not OriginalHostBinding.current
                or type(binding.current) is not MethodType
                or binding.current.__self__ is not binding
                or binding.current.__func__ is not OriginalHostBinding.current
                or type(self.current_callback) is not MethodType
                or self.current_callback.__self__ is not self
                or self.current_callback.__func__ is not _OriginalPublisherPort.current
                or type(self.authorize_callback) is not MethodType
                or self.authorize_callback.__self__ is not self
                or self.authorize_callback.__func__ is not _OriginalPublisherPort.authorize):
            raise ValueError('Original Local physical publisher changed or retired')

    def _require_reservation(self, core: LocalCore, current: Callable[[], bool],
                             authorize: Callable[[_PublisherFact], bool]) -> None:
        self._require_original()
        if (core is not self.core or current is not self.current_callback
                or authorize is not self.authorize_callback or self.output is not None
                or self.physical is not None or self.callbacks is not None):
            raise ValueError('Original Local physical publisher is already bound or foreign')

    def _bind(self, output: _Output, physical: _PhysicalInput,
              callbacks: _PublisherCallbacks) -> None:
        # The Core has already retained the issued output and physical input.
        # Even a refused bind therefore leaves its original cleanup reachable.
        self.output, self.physical, self.callbacks = output, physical, callbacks
        self._require_live()

    def _require_live(self) -> None:
        self._require_original()
        output, physical, callbacks, core = self.output, self.physical, self.callbacks, self.core
        if (type(output) is not _Output or type(physical) is not _PhysicalInput
                or type(callbacks) is not _PublisherCallbacks
                or core._closing or core._closed or getattr(core, '_retired', False)
                or core._inputs.get(output.ticket) is not physical
                or physical.publisher is not callbacks or callbacks.original is not self
                or callbacks.current is not self.current_callback
                or callbacks.authorize is not self.authorize_callback
                or (callbacks.buffer is not None and type(callbacks.buffer) is not bytearray)
                or type(callbacks.received) is not int):
            raise ValueError('Original Local physical publisher loan changed or retired')
        core._owned_output(output, 'publisher')

    def _fail(self, error: BaseException) -> BaseException:
        if self.failure is None:
            self.failure = error
        span = getattr(self.core, '_invocation_observation', None)
        if type(span) is _InvocationObservation:
            span._fail(self.failure)
        return self.failure

    def current(self) -> bool:
        try:
            self._require_live()
            self.observer()
            return True
        except BaseException as error:
            raise self._fail(error)

    def authorize(self, fact: _PublisherFact) -> bool:
        try:
            self._require_live()
            self.observer()
            if type(fact) is not _PublisherFact or type(fact.namespace_id) is not str:
                raise ValueError('Original Local physical publisher facts changed')
            return fact.namespace_id == 'local'
        except BaseException as error:
            raise self._fail(error)


class _InvocationObservation:
    """One closed Wasm call, not a cached permission or a reader loan.

    Original Account decisions still run. Physical files are observed before
    entry, before/after effect imports and before return; closed read-only
    imports retain live identity and SQL checks rather than repeating the
    complete filesystem walk. Nothing survives the synchronous invocation.
    """
    __slots__ = ('binding', 'core', 'reader', 'connection', 'current', 'input',
                 'epoch', 'source', 'state', 'installation', 'selected', 'expected',
                 'fences', 'thread', 'operation', 'failure', 'suspended', 'active',
                 'admitted', 'disabled', 'checking_physical', 'platform', 'publisher',
                 'publisher_buffer', 'publisher_received')

    def __init__(self, binding: 'OriginalHostBinding', reader: _NamespaceReader,
                 connection: _TrackedSQLiteConnection) -> None:
        if binding._current is None or binding._input is None or binding._frame_epoch is None:
            raise ValueError('Original closed Local observation is unavailable')
        self.binding, self.core, self.reader, self.connection = binding, binding._core, reader, connection
        self.current, self.input, self.epoch = binding._current, binding._input, binding._frame_epoch
        self.source, self.state = binding._source, binding._state
        self.installation = self.source._installation
        self.selected, self.expected, self.fences = binding._selected, binding._expected, binding._fences
        self.thread = get_ident()
        self.operation = self.core._host_operation_id
        self.platform = getattr(self.core, '_platform_vm_original', None)
        self.publisher: _OriginalPublisherPort | None = None
        self.publisher_buffer: bytearray | None = None
        self.publisher_received = 0
        self.failure: BaseException | None = None
        self.suspended = False
        self.active = True
        self.admitted = False
        self.disabled = False
        self.checking_physical = False

    def _fail(self, error: BaseException) -> BaseException:
        if self.failure is None:
            self.failure = error
        return self.failure

    def _guard_sql(self) -> None:
        try:
            if self.failure is not None:
                raise self.failure
            if (not self.active or not self.admitted or get_ident() != self.thread
                    or self.core._invocation_observation is not self or not self.core._invoking
                    or self.core._closing or self.core._closed or self.core._retired
                    or self.connection._closed_invocation is not self
                    or self.binding._store._connection is not self.connection
                    or not self.connection._closed_eligible()):
                raise ValueError('Original closed SQLite invocation changed or retired')
        except BaseException as error:
            raise self._fail(error)

    def _guard_originals(self) -> None:
        try:
            self._guard_sql()
            if self.failure is not None:
                raise self.failure
            binding, core, installation = self.binding, self.core, self.installation
            if (not self.active or get_ident() != self.thread
                    or core._invocation_observation is not self or not core._invoking
                    or core._closing or core._closed or core._retired
                    or core._host_cleanup_depth or core._host_fuel_phase != 'operation'
                    or core._host_operation_id != self.operation
                    or getattr(core, '_platform_vm_original', None) is not self.platform
                    or core._host_current_binding is not binding
                    or binding._original is not binding or binding._closing or not binding._active
                    or binding._current is not self.current or binding._input is not self.input
                    or binding._observed_reader is not self.reader or binding._frame_epoch is not self.epoch
                    or binding._source is not self.source or binding._state is not self.state
                    or binding._selected is not self.selected or binding._expected is not self.expected
                    or binding._fences is not self.fences or installation is None
                    or installation._original is not installation or installation._closing
                    or len(installation._pins) != 2 or installation._pins[0] is not self.source
                    or installation._pins[1] is not self.state
                    or self.source._installation is not installation or self.state._installation is not installation
                    or self.source._root is not installation._source or self.state._root is not installation._state
                    or self.source._store is not installation._store or self.state._store is not installation._store
                    or self.source._observe_roots is not None or self.state._observe_roots is not None
                    or binding._store._connection is not self.connection
                    or self.connection._closed_invocation is not self
                    or not self.connection._closed_eligible()):
                raise ValueError('Original closed Local invocation changed or retired')
            self._guard_publisher()
            core._owned_output(self.current, 'current')
            core._owned_input(self.input)
            callbacks = core._journal_callbacks(self.current.ticket)
            if (callbacks is None or callbacks.reader is not self.reader
                    or callbacks.current is not binding._current_observer):
                raise ValueError('Original closed Local current callback changed')
            if callbacks.failure is not None:
                raise callbacks.failure
            self.source._require_original_members((binding._account, *self.selected))
            self.state._require_original_members((binding._staged_account, binding._initialization,
                                                  binding._configuration, binding._journal))
            for pins in (self.source, self.state):
                pins._require_current_lifetime()
                for value in pins._files.values():
                    pins._root._owned_original(value.reader)
                    if value.reader.closing or value.reader.invalid or value.reader.descriptor is None:
                        raise ValueError('Closed Local original file reader retired')
            for projection in self.expected:
                core._owned_output(projection, 'original')
        except BaseException as error:
            raise self._fail(error)

    def _guard_publisher(self) -> None:
        publisher = self.publisher
        if publisher is None:
            return
        publisher._require_live()
        callbacks = publisher.callbacks
        if (publisher.binding is not self.binding or publisher.installation is not self.installation
                or callbacks is None or callbacks.buffer is not self.publisher_buffer
                or callbacks.received != self.publisher_received):
            raise ValueError('Original closed Local publisher or collector changed')

    def _select_publisher(self, publisher: _OriginalPublisherPort) -> bool:
        if self.disabled:
            return False
        self._guard_publisher()
        publisher._require_live()
        if (publisher.binding is not self.binding or publisher.installation is not self.installation
                or (self.publisher is not None and self.publisher is not publisher)):
            return False
        if self.publisher is None:
            self.publisher = publisher
            assert publisher.callbacks is not None
            self.publisher_buffer = publisher.callbacks.buffer
            self.publisher_received = publisher.callbacks.received
        return True

    def _publisher_result(self, name: str, result: Any) -> None:
        # Unknown transport results cannot be swallowed by a scalar export and
        # turned back into a successful invocation. False remains denial.
        if type(result) is not int or result < 0 and not (
                name in ('publisher_current', 'publisher_finish') and result == -1):
            raise ValueError('Original closed Local publisher transport failed')
        assert self.publisher is not None and self.publisher.callbacks is not None
        callbacks = self.publisher.callbacks
        if name == 'publisher_begin':
            if (type(callbacks.buffer) is not bytearray or callbacks.received != 0
                    or self.publisher_buffer is not None):
                raise ValueError('Original closed Local publisher collector changed')
        elif name == 'publisher_copy':
            if (callbacks.buffer is not self.publisher_buffer
                    or callbacks.received != self.publisher_received + result):
                raise ValueError('Original closed Local publisher copy changed')
        elif name == 'publisher_finish':
            if callbacks.buffer is not None or callbacks.received != 0:
                raise ValueError('Original closed Local publisher collector survived finish')
        elif (callbacks.buffer is not self.publisher_buffer
                or callbacks.received != self.publisher_received):
            raise ValueError('Original closed Local publisher current changed collector')
        self.publisher_buffer, self.publisher_received = callbacks.buffer, callbacks.received
        self._guard_publisher()

    def check(self, *, physical: bool = False) -> None:
        try:
            if self.checking_physical:
                raise ValueError('Reentrant closed Local physical observation')
            self._guard_originals()
            self.checking_physical = physical
            observe = self.reader._invocation_check
            if observe is None:
                raise ValueError('Original closed Local reader port is unavailable')
            observe(self.reader, self.binding._current_observer, self)
            if physical:
                self.binding._physical_current()
                observe(self.reader, self.binding._current_observer, self)
        except BaseException as error:
            raise self._fail(error)
        finally:
            self.checking_physical = False

    def enter(self) -> None:
        # Admission is lazy: pure scalar/progress exports need no new graph
        # walk. Unsupported customization before the first observation keeps
        # the complete legacy path; an admitted span never falls back.
        if self.disabled or not self.connection._closed_eligible():
            self.disabled = True
            return
        if self.connection._closed_invocation is not None:
            raise ValueError('Original SQLite invocation already borrowed')
        candidate = self.reader._invocation_candidate
        if candidate is None or not candidate(self.reader, self.binding._current_observer, self):
            self.disabled = True
            return
        self.connection._closed_invocation = self
        self.admitted = True
        self.check(physical=True)

    def interrupt(self, callback: Callable[..., Any], *args: Any) -> Any:
        try:
            if self.failure is not None:
                raise self.failure
            if self.admitted:
                self.check(physical=True)
            self.suspended = True
            result = callback(*args)
            if self.admitted:
                self.check(physical=True)
            elif self.failure is not None:
                raise self.failure
            self.suspended = False
            return result
        except BaseException as error:
            raise self._fail(error)

    def leave(self) -> None:
        self.suspended = True
        self.active = False
        self.publisher = None
        self.publisher_buffer = None
        self.publisher_received = 0
        if self.connection._closed_invocation is self:
            self.connection._closed_invocation = None


class LocalHostBindingCleanupPending(RuntimeError):
    def __init__(self, binding: 'OriginalHostBinding') -> None:
        super().__init__('Original Local Host binding cleanup is pending')
        self.cleanup_binding = binding


def _body(raw: bytes) -> bytes:
    """Unwrap Core's closed transport; do not encode/hash an original contract."""
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate original Core metadata field')
            result[key] = value
        return result
    if type(raw) is not bytes or len(raw) > 65536:
        raise ValueError('Original Core metadata exceeds its reserved transfer')
    result = json.loads(raw, object_pairs_hook=pairs)
    if (type(result) is not dict or set(result) != {'body', 'cid'}
            or type(result['body']) is not str or type(result['cid']) is not str
            or len(result['cid']) != 71 or not result['cid'].startswith('sha256:')
            or any(character not in '0123456789abcdef' for character in result['cid'][7:])):
        raise ValueError('Invalid original Core metadata transport')
    body = result['body'].encode('utf-8')
    if len(body) > 8192:
        raise ValueError('Original Core custody exceeds its record bound')
    return body


class OriginalHostBinding:
    """Supply original physical facts under Core -> File -> Store locking.

    Only the trusted installed assembly constructs this from Core-issued
    initialization/configuration/journal/selection projections and the original
    pinned files. Those projections must use the same physical observations and
    source bytes; arbitrary public SDK data cannot install this supplier. It
    checks exact raw persisted bytes, original epoch custody and complete saved
    settings membership. Common still verifies actual singleton adoption,
    admits Account, derives scope and evaluates each operation independently.

    This owns transfer/current/workspace loans, never a Run/Recovery state.
    It performs no initialization, adoption, COMMIT, repair, dispatch, retry or
    permission decision. The caller separately accounts/pins the source files
    and retains its existing exclusive root and same Store throughout.
    """

    def __init__(self, core: LocalCore, source: LocalHostFiles, state: LocalHostFiles,
                 account: _HostFile, staged_account: _HostFile,
                 initialization: _HostFile, configuration: _HostFile,
                 journal: _HostFile, selected: tuple[_HostFile, ...],
                 expected: tuple[_Output, _Output, _Output, _Output],
                 epoch: LocalSubmissionAuthority, *, principal: str,
                 connection: str) -> None:
        if (type(core) is not LocalCore or type(source) is not LocalHostFiles
                or type(state) is not LocalHostFiles or source._store is not state._store
                or type(epoch) is not LocalSubmissionAuthority or epoch._store is not state._store
                or type(selected) is not tuple or len(selected) > 8
                or type(expected) is not tuple or len(expected) != 4
                or type(principal) is not str or type(connection) is not str
                or not 0 < len(principal.encode('utf-8')) <= 512
                or not 0 < len(connection.encode('utf-8')) <= 512):
            raise ValueError('Invalid original Local Host supplier')
        self._original = self
        self._core = core
        self._source = source
        self._state = state
        self._store = state._store
        self._epoch = epoch
        self._expected = expected
        self._account = account
        self._staged_account = staged_account
        self._initialization = initialization
        self._configuration = configuration
        self._journal = journal
        self._selected = selected
        self._workspace: _Workspace | None = None
        self._input: _Input | None = None
        self._current: _Output | None = None
        self._uncertain_ticket: int | None = None
        self._active = False
        self._frame_epoch: ByteFence | None = None
        self._bound_operation: tuple[int, _Output, _Input] | None = None
        self._observed_reader: _NamespaceReader | None = None
        self._closing = False
        self._fences: tuple[ByteFence, ...] = ()
        try:
            with core._lock, source._root._lock, state._root._lock:
                self._physical_current()
                if (tuple(value.name for value in selected)
                        != tuple(sorted(set(value.name for value in selected)))
                        or any(value.name == account.name for value in selected)):
                    raise ValueError('Invalid original Local selected file membership')
                for value in expected:
                    core._owned_output(value, 'original')
                # Bound the four simultaneous decoded metadata transports and
                # the current input encoder before making either copy. Source
                # pins and their original Core output loans remain separate.
                allowance = 16 * (4 * 65536 + len(account.body) + len(journal.body)) + 8192
                self._workspace = self._reserve(lambda: core.reserve_workspace(
                    allowance, stopped=lambda: not self._active, cleanup=lambda: True))
                bodies = tuple(_body(core.read_original_metadata(value)) for value in expected)
                for actual, wanted in zip((initialization, configuration, journal), bodies[:3]):
                    if state.original_bytes(actual) != wanted:
                        raise ValueError('Original Local saved custody does not match Core material')
                if source.original_bytes(account) != state.original_bytes(staged_account):
                    raise ValueError('Original Local staged Account changed')
                manifest = bodies[3]
                self._fences = tuple(ByteFence(LocalByteStore.namespaced_key(namespace, key), 0, body)
                    for namespace, key, body in (
                        ('client_local_adoption', 'adoption', state.original_bytes(journal)),
                        ('client_local_settings', 'manifest', manifest),
                        *((('client_local_settings', 'file:' + value.name,
                            source.original_bytes(value)) for value in selected)),
                    ))
                device, inode = self._store.observe_generation()
                wire = json.dumps({'account': source.original_bytes(account).decode('utf-8'),
                                   'adoption': state.original_bytes(journal).decode('utf-8'),
                                   'device': str(device), 'inode': str(inode),
                                   'principal': principal, 'connection': connection},
                                  ensure_ascii=False, separators=(',', ':')).encode('utf-8')
                self._input = self._reserve(lambda: core.reserve_input(
                    wire, cleanup=lambda: True, stopped=lambda _: True))
                assert self._input is not None
                original_input = self._input
                for start in range(0, len(wire), 16384):
                    core.fill_input(original_input, start, min(16384, len(wire) - start))
                core.seal_input(original_input)
                self._current_observer = self.current
                self._current = self._reserve(lambda: core.reserve_host_current(
                    original_input, store=self._store, current=self._current_observer,
                    cleanup=lambda: not self._active))
                self._physical_current()
        except BaseException as failure:
            # Keep the exact returned loans and original Core reachable even
            # when reserve traps before returning a scalar handle.
            raise LocalHostBindingCleanupPending(self) from failure

    def _reserve(self, acquire: Callable[[], _T]) -> _T:
        ticket = self._core._next_ticket
        self._uncertain_ticket = ticket
        try:
            result = acquire()
        except BaseException:
            if ticket not in self._core._inputs and ticket not in self._core._released:
                self._uncertain_ticket = None
            raise
        self._uncertain_ticket = None
        return result

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Local Host supplier')

    def _physical_current(self) -> None:
        self._nominal()
        if self._closing:
            raise ValueError('Original Local Host supplier is closing')
        if self._current is not None:
            if self._input is None:
                raise ValueError('Original Local current input is unavailable')
            self._core._owned_output(self._current, 'current')
            self._core._owned_input(self._input)
        source_values = (self._account, *self._selected)
        state_values = (self._staged_account, self._initialization,
                        self._configuration, self._journal)
        installation = self._source._installation
        if (installation is not None and installation is self._state._installation
                and self._source._observe_roots is None and self._state._observe_roots is None):
            installation._require_current_host_files(
                self._source, source_values, self._state, state_values)
        else:
            # Arbitrary observers retain their original calls and ordering,
            # even when both pins happen to hold the same callable.
            self._source.require_current_originals(source_values)
            self._state.require_current_originals(state_values)
        for projection in self._expected:
            self._core._owned_output(projection, 'original')
        if self._active:
            if self._frame_epoch is None:
                raise ValueError('Original Local epoch snapshot is unavailable')
            # The existing reader fences this exact physical row inside its
            # transaction. Do not open a second read or rewind/advance a clock.
        else:
            self._epoch.observe_custody()

    def _adoption_inventory(self, reader: _NamespaceReader) -> None:
        """Fence the complete original singleton in EACH actual SQL reader.

        This is physical original-byte correspondence, not adoption or Allow.
        A known-row fence alone cannot certify absence of another member after
        a different transaction. Core retains all original semantic decisions.
        """
        inventory = reader.check_inventory
        if inventory is not None:
            inventory(reader, 'client_local_adoption', (('adoption', self._fences[0].payload),),
                      self._current_observer)
            return
        query = reader.query_current
        if query is None:
            raise ValueError('Original Local owned inventory query is unavailable')
        found: tuple[str, StoredBytes] | None = query(
            reader, 0, 'client_local_adoption', '', self._current_observer)
        if (found is None or found[0] != 'adoption' or found[1].generation != 0
                or found[1].payload != self._fences[0].payload):
            raise LocalStorageError('Original Local adoption singleton changed')
        if query(reader, 0, 'client_local_adoption', 'adoption',
                 self._current_observer) is not None:
            raise LocalStorageError('Original Local adoption singleton is incomplete')

    def _require_observation_frame(self, core: LocalCore, current: _Output,
                                   reader: _NamespaceReader | None) -> None:
        """Require this original receiver's completely fenced live reader.

        No caller flag, equal tuple or operation number supplies this witness.
        It owns no transaction and cannot survive the enclosing callback.
        """
        self._nominal()
        if (core is not self._core or current is not self._current
                or reader is None or reader is not self._observed_reader
                or not self._active or self._frame_epoch is None or self._closing):
            raise ValueError('Foreign or retired original current observation frame')
        core._owned_output(current, 'current')
        if self._input is None:
            raise ValueError('Original current observation input is unavailable')
        core._owned_input(self._input)
        reader.check_fences(reader, (*self._fences, self._frame_epoch))

    def _settings_inventory(self, reader: _NamespaceReader) -> None:
        # This is the same bounded raw membership fence as Native's retained
        # settings port, not a scope or authorization decision. Core-issued
        # originals supply every expected name/body; nothing is discovered.
        # Use the literal original logical names, including colons in file keys.
        expected = {'manifest': self._fences[1].payload} | {
            'file:' + value.name: value.body for value in self._selected}
        inventory = reader.check_inventory
        if inventory is not None:
            inventory(reader, 'client_local_settings', tuple(sorted(expected.items())),
                      self._current_observer)
            return
        query = reader.query_current
        if query is None:
            raise ValueError('Original Local owned inventory query is unavailable')
        cursor = ''
        for _ in range(len(expected)):
            found = query(reader, 0, 'client_local_settings', cursor,
                          self._current_observer)
            if (found is None or found[0] not in expected
                    or found[1].payload != expected[found[0]] or found[1].generation != 0):
                raise LocalStorageError('Original Local settings inventory changed')
            cursor = found[0]
        if query(reader, 0, 'client_local_settings', cursor,
                 self._current_observer) is not None:
            raise LocalStorageError('Original Local settings inventory is incomplete')

    def inspect(self, consume: Callable[[_Output], object]) -> None:
        """Run protected Core work only within the same original read snapshot.

        The consumer must not begin a write transaction on this connection.
        Original pending-write confirmation uses its existing separate caller.
        No current reader, grant or successful result is returned as a token.
        """
        with self.fenced() as fences:
            self._store.inspect_namespaces(fences,
                inspect=lambda reader: self.inspect_reader(reader, consume),
                current=self._current_observer)

    @contextmanager
    def fenced(self) -> Iterator[tuple[ByteFence, ...]]:
        """Borrow original physical fences for the existing Store operation.

        The trusted assembly passes every returned fence to the same Store's
        existing inspected read/CAS port, and inspect_reader as its inspector.
        This starts no transaction and decides no action or retry. An attempted
        COMMIT failure remains the Store's original Unknown; this scope only
        releases its transient frame, never the original operation or loans.
        """
        with self._core._lock, self._source._root._lock, self._state._root._lock:
            self._nominal()
            if self._active or self._current is None or self._closing:
                raise ValueError('Original Local Host snapshot is unavailable')
            self._physical_current()
            self._frame_epoch = self._epoch.custody_fence()
            self._active = True
            try:
                yield (*self._fences, self._frame_epoch)
            finally:
                self._active = False
                self._frame_epoch = None

    def current(self) -> None:
        """Physical current callback inside the original fenced Store operation.

        It is neither Account Allow nor publication authorization. Common still
        rechecks current material at each protected stage; saved-row adoption and
        return_committed occur in their own fresh original read snapshot.
        """
        with self._core._lock:
            span = getattr(self._core, '_invocation_observation', None)
            try:
                self._nominal()
                if not self._active:
                    raise ValueError('Original Local Host physical frame is unavailable')
                if type(span) is _InvocationObservation and span.binding is self:
                    if not span.suspended:
                        if not span.admitted:
                            span.enter()
                        if span.admitted:
                            span.check()
                        else:
                            self._physical_current()
                    else:
                        self._physical_current()
                else:
                    self._physical_current()
            except BaseException as error:
                if type(span) is _InvocationObservation and span.binding is self:
                    raise span._fail(error)
                raise

    def _new_invocation_observation(self) -> _InvocationObservation | None:
        from ._local_installation import OriginalLocalInstallation
        core, reader, installation = self._core, self._observed_reader, self._source._installation
        connection = self._store._connection
        # Unsupported suppliers take the full legacy path. Once admitted, an
        # actual refusal is latched and can never select that fallback.
        if (not getattr(core, '_ordinary_host', False) or core._host_fuel_phase != 'operation'
                or getattr(core, '_host_cleanup_depth', 0) or core._closing
                or getattr(core, '_physical_holding', None) is not None
                or getattr(core, '_physical_child_control', None) is not None
                or getattr(core, '_physical_vm_observation', None) is not None
                or type(installation) is not OriginalLocalInstallation
                or installation is not self._state._installation
                or self._source._observe_roots is not None or self._state._observe_roots is not None
                or reader is None or reader._invocation_check is None
                or reader._invocation_candidate is None
                or type(connection) is not _TrackedSQLiteConnection
                or not connection._closed_eligible()):
            return None
        return _InvocationObservation(self, reader, connection)

    def inspect_reader(self, reader: _NamespaceReader, consume: Callable[[_Output], object]) -> None:
        """Use the same actual read/write transaction's borrowed namespace reader.

        This method cannot issue a write or acknowledge its success. The existing
        Store retains transaction/COMMIT/cleanup responsibility, and Core reads
        original inventory/admission/commit materials through this same reader.
        """
        if self._observed_reader is not None:
            raise ValueError('Original current observation reader is already borrowed')
        prior = self._bound_operation
        self._bound_operation = None
        self._nominal()
        if (not self._active or self._current is None or self._frame_epoch is None
                or self._input is None
                or type(reader) is not _NamespaceReader or reader.owner is not self._store
                or not callable(consume)):
            raise ValueError('Original Local Host transaction reader is unavailable')
        self._core._owned_output(self._current, 'current')
        self._core._owned_input(self._input)
        self._physical_current()
        required = (*self._fences, self._frame_epoch)
        reader.check_fences(reader, required)
        self._adoption_inventory(reader)
        self._settings_inventory(reader)
        operation = getattr(self._core, '_host_operation_id', 0)
        normal = (getattr(self._core, '_ordinary_host', False)
                  and self._core._host_fuel_phase == 'operation'
                  and getattr(self._core, '_host_cleanup_depth', 0) == 0
                  and not self._core._closing
                  and type(operation) is int and 0 < operation < 2**63
                  and operation == self._core._host_operation_sequence)
        same = (normal and prior is not None and prior[0] == operation
                and prior[1] is self._current and prior[2] is self._input)
        self._observed_reader = reader
        try:
            with self._core.host_current_frame(self._current, reader):
                # Only the same completed original binding within this existing
                # operation is reusable. Every actual reader/current/files/settings
                # fence still runs, and Core owns each protected Account decision.
                if not same:
                    self._core.bind_host_current(self._current)
                consume(self._current)
                self._physical_current()
                if not same:
                    self._core.validate_host_current(self._current)
                if normal and self._core._host_operation_id != operation:
                    raise ValueError('Original Host operation changed during current binding')
            self._settings_inventory(reader)
            self._adoption_inventory(reader)
            reader.check_fences(reader, required)
        finally:
            self._observed_reader = None
        if normal:
            self._bound_operation = (operation, self._current, self._input)

    def close(self) -> bool:
        """Release these loans only; preserve saved files, Store and original Run."""
        with self._core._lock:
            self._nominal()
            self._closing = True
            self._bound_operation = None
            if self._active:
                return False
            if self._core._closed:
                # Only actual original instance retirement resolves a reserve
                # that trapped without returning a handle. Never repeat it.
                self._current = None
                self._input = None
                self._workspace = None
                self._uncertain_ticket = None
                return True
            if self._uncertain_ticket is not None:
                return False
            if self._current is not None:
                if not self._core.close_host_current(self._current):
                    return False
                self._current = None
            if self._input is not None:
                if not self._core.close_input(self._input):
                    return False
                self._input = None
            if self._workspace is not None:
                if not self._core.close_workspace(self._workspace):
                    return False
                self._workspace = None
            return True
