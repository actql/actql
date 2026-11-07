"""Original physical Host supplier for the existing Common current/scope Owner."""
from collections.abc import Callable, Iterator
from contextlib import contextmanager
import json
from typing import Any, TypeVar

from ._local_core import LocalCore, _Input, _Output, _Workspace
from ._local_host_files import LocalHostFiles, _HostFile
from ._local_storage import ByteFence, LocalByteStore, LocalStorageError, StoredBytes, _NamespaceReader
from ._local_submission import LocalSubmissionAuthority

_T = TypeVar('_T')


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
            self._nominal()
            if not self._active:
                raise ValueError('Original Local Host physical frame is unavailable')
            self._physical_current()

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
