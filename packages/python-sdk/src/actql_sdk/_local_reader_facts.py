"""Original physical-reader facts for the existing Core/Store commit caller."""
from collections.abc import Callable, Iterator
from contextlib import contextmanager
import json

from ._local_commit_projection import OriginalCommitProjection
from ._local_core import _Input, _Output
from ._local_files import LocalFileRoot, PhysicalFileSnapshot, _FileReader, _OriginalFileReader


class OriginalReaderFacts:
    """Hold one bounded metadata loan and borrow the same completed reader.

    This is transport custody, not a Run/Recovery or authorization Owner. The
    trusted Host supplies authority/material from the original payload request;
    Core checks both against that request. It separately reserves this holder,
    encoding/hash/descriptor workspace and the existing physical transaction.
    The metadata cleanup callback retires metadata only, never the original
    reader, finalization, payload reservation, Source or Result.

    Call validate() before projecting metadata. Use serialized() around the
    existing Store transaction and before_commit() as its precommit callback.
    That callback checks the original binding/Sealed facts and independent
    publisher stage before COMMIT, with current physical checks on both sides.
    Success remains a current observation, not a guarantee against future file
    mutation or a durable ACK. No commit, publication or automatic retry occurs.

    Failed transfer keeps its exact loan; an uncertain reserve without a returned
    handle stays in the original Core until explicit instance retirement. A
    retained failure traceback may hold temporary encoding bytes; resolve the
    physical failure and discard those references before explicit close().
    """

    def __init__(self, projection: OriginalCommitProjection, record: _Output,
                 root: LocalFileRoot, reader: _FileReader | _OriginalFileReader, result: int,
                 binding_index: int, store_authority_cid: str,
                 material_generation_cid: str, *, cleanup: Callable[[], bool],
                 stopped: Callable[[int], bool]) -> None:
        if (type(projection) is not OriginalCommitProjection
                or type(root) is not LocalFileRoot
                or not callable(cleanup) or not callable(stopped)
                or any(type(value) is not int or not 0 <= value < 2**31
                       for value in (result, binding_index))):
            raise ValueError('Invalid original Local reader facts')
        for cid in (store_authority_cid, material_generation_cid):
            if (type(cid) is not str or len(cid) != 71 or not cid.startswith('sha256:')
                    or any(character not in '0123456789abcdef' for character in cid[7:])):
                raise ValueError('Invalid original Local physical identity field')
        with projection._core._lock:
            projection._ready()
            projection._core._owned_output(record, 'payload_record')
            with root._lock:
                if type(reader) is _OriginalFileReader and projection._saved:
                    root._owned_original(reader)
                elif type(reader) is _FileReader and not projection._saved:
                    root._owned_reader(reader)
                else:
                    raise ValueError('Foreign original saved/live Reader variant')
        self._projection = projection
        self._record = record
        self._root = root
        self._reader = reader
        self._result = result
        self._binding_index = binding_index
        self._store_authority = store_authority_cid
        self._material = material_generation_cid
        self._cleanup = cleanup
        self._stopped = stopped
        self._input: _Input | None = None
        self._original_material: tuple[tuple[object, ...], tuple[object, ...], _Input,
                                       PhysicalFileSnapshot] | None = None
        self._acquisition_ticket: int | None = None
        self._sealed = False
        self._active = False
        self._closing = False

    def _observe_reader(self) -> PhysicalFileSnapshot:
        if isinstance(self._reader, _OriginalFileReader):
            return self._root.observe_original(self._reader)
        return self._root.observe_completed_reader(self._reader)

    def _prepare_snapshot(self) -> PhysicalFileSnapshot:
        phase = getattr(self._projection._core, '_reconciliation_prepare', None)
        if phase is not None and not phase.suspended:
            return phase.snapshot(self)
        return self._observe_reader()

    def _material_originals(self) -> tuple[tuple[object, ...], tuple[object, ...]]:
        projection = self._projection
        return ((self, projection, projection._core, projection._publication,
                 self._record, self._root, self._reader),
                (projection._configuration, projection._saved, self._result,
                 self._binding_index, self._store_authority, self._material))

    def _same_material_originals(self, original: tuple[tuple[object, ...], tuple[object, ...]]) -> bool:
        owners, values = self._material_originals()
        return (all(left is right for left, right in zip(owners, original[0], strict=True))
                and values == original[1])

    def observe_original_material(self) -> None:
        """Reobserve admitted DATA for the existing bound Saved byte caller.

        The caller must still enter its actual Store frame and Core byte port,
        whose original Source/record/current checks remain mandatory. This
        supplies no Allow, fresh semantic validation or cleanup acknowledgement.
        Missing/changed originals take the complete original validator instead.
        """
        core = self._projection._core
        with core._lock:
            original = self._original_material
            self._original_material = None
            self._ready()
            with self._root._lock:
                if (not self._active or not self._projection._saved
                        or original is None
                        or not self._same_material_originals((original[0], original[1]))
                        or self._input is not original[2] or not self._sealed):
                    self.validate()
                    return
                core._owned_input(original[2])
                observed = self._observe_reader()
                self._ready()
                core._owned_input(original[2])
                if (self._same_material_originals((original[0], original[1]))
                        and self._input is original[2] and self._sealed
                        and observed == original[3]):
                    self._original_material = original
                else:
                    self.validate()

    @property
    def pending_input(self) -> _Input | None:
        """Exact cleanup loan, never a serialized grant or replay token."""
        with self._projection._core._lock:
            return self._input

    @property
    def uncertain_acquisition_ticket(self) -> int | None:
        """Original Core physical cleanup responsibility if reserve trapped."""
        with self._projection._core._lock:
            return self._acquisition_ticket

    def _ready(self) -> None:
        if self._closing or self._acquisition_ticket is not None:
            raise RuntimeError('Local reader facts are closing or acquisition is unresolved')
        if self._active:
            # A read snapshot may hold the original key output during its
            # synchronous lookup. Recheck facts without replacing that loan.
            self._projection._current()
        else:
            self._projection._ready()
        self._projection._core._owned_output(self._record, 'payload_record')

    @contextmanager
    def serialized(self) -> Iterator[None]:
        """Acquire Core, File, then the caller's existing Store transaction.

        Hold the original physical lock through precommit; no Store-to-File lock
        inversion or automatic close is introduced. Cleanup remains explicit.
        """
        with self._projection._core._lock:
            self._ready()
            with self._root._lock:
                if self._active:
                    raise RuntimeError('Local reader facts transaction is already active')
                self._observe_reader()
                self._active = True
                try:
                    yield
                finally:
                    self._active = False

    def validate(self) -> None:
        """Read-only original binding/facts validation, retaining the same loan."""
        core = self._projection._core
        with core._lock:
            self._original_material = None
            self._ready()
            originals = self._material_originals()
            with self._root._lock:
                observed = self._prepare_snapshot()
                if self._input is not None and self._sealed:
                    # No transfer or external IO separates the original binding
                    # and snapshot checks for this already sealed metadata loan.
                    loan = self._input
                    self._projection.validate_reader_facts(
                        self._record, loan, self._result, self._binding_index)
                    after = self._prepare_snapshot()
                    if (self._projection._saved and self._same_material_originals(originals)
                            and self._input is loan and observed == after):
                        core._owned_input(loan)
                        self._original_material = (*originals, loan, after)
                    return
                self._projection.validate_payload_binding(
                    self._record, self._result, self._binding_index)
                if self._input is None:
                    observation = observed.observation
                    # Fixed six-field metadata only. Decimal strings preserve the
                    # complete UInt64 identity and Int64 size without float loss.
                    wire = json.dumps({
                        'store_authority_cid': self._store_authority,
                        'material_generation_cid': self._material,
                        'device': str(observation.identity.device),
                        'inode': str(observation.identity.inode),
                        'size': str(observation.size),
                        'physical_digest': observed.physical_digest,
                    }, ensure_ascii=True, separators=(',', ':')).encode('ascii')
                    if len(wire) > 512:
                        raise ValueError('Local completed-reader metadata exceeds its bound')
                    ticket = core._next_ticket
                    try:
                        self._input = core.reserve_input(
                            wire, cleanup=self._cleanup, stopped=self._stopped)
                    except BaseException:
                        # An explicit refusal removes the ticket. A trap/scalar
                        # failure may leave it held without a returned ABI handle.
                        if ticket in core._inputs:
                            self._acquisition_ticket = ticket
                        raise
                    core.fill_input(self._input, 0, len(wire))
                    core.seal_input(self._input)
                    self._sealed = True
                if not self._sealed:
                    raise RuntimeError('Original Local reader fact transfer requires cleanup')
                loan = self._input
                core.validate_payload_snapshot(
                    self._record, loan, self._projection._configuration)
                after = self._prepare_snapshot()
                if (self._projection._saved and self._same_material_originals(originals)
                        and self._input is loan and observed == after):
                    core._owned_input(loan)
                    self._original_material = (*originals, loan, after)

    def before_lookup(self, publisher: _Output) -> None:
        """Recheck original physical facts around the current Request stage.

        This is neither Commit nor ReturnCommitted. Core validates/adopts the
        actually stored index and independently rechecks its publisher stage.
        """
        core = self._projection._core
        with core._lock:
            self._ready()
            with self._root._lock:
                if not self._active:
                    raise RuntimeError('Local reader facts require the original serialized transaction')
                self.validate()
                core.authorize_publisher(publisher, self._projection._configuration,
                                         stage='request')
                self.validate()

    def before_commit(self, publisher: _Output) -> None:
        """Recheck before physical COMMIT; neither write nor acknowledge it."""
        core = self._projection._core
        with core._lock:
            self._ready()
            with self._root._lock:
                if not self._active:
                    raise RuntimeError('Local reader facts require the original serialized transaction')
                self.validate()
                self._projection.authorize_commit(publisher)
                # The independent publisher callback may await external facts or
                # change the physical input. Never use its success as a file fence.
                self.validate()

    def close(self) -> bool:
        """Retire only this metadata loan after physical transaction cleanup."""
        core = self._projection._core
        with core._lock:
            self._original_material = None
            if self._active:
                raise RuntimeError('Local reader facts transaction still retains its input')
            self._closing = True
            if self._acquisition_ticket is not None:
                if not core._retired or self._acquisition_ticket in core._inputs:
                    return False
                self._acquisition_ticket = None
            if self._input is not None:
                if core._retired:
                    # Original close_pool success already retired this loan. A
                    # physical callback alone cannot establish that fact.
                    if self._input.ticket in core._inputs:
                        return False
                elif not core.close_input(self._input):
                    return False
                self._input = None
            return True


# Definition-time provenance for the fixed original reconciliation driver.
from ._local_prepare_provenance import _capture_prepare_methods
_PREPARE_METHODS = (
    _capture_prepare_methods(OriginalReaderFacts, (
        '_material_originals', '_observe_reader', '_prepare_snapshot',
        '_ready', '_same_material_originals', 'before_lookup',
        'serialized', 'validate',
    )),
)
