"""Borrow original Core fields for a synchronous physical Store consumer."""
from collections.abc import Callable, Iterator
from contextlib import contextmanager

from ._local_core import LocalCore, LocalCoreError, _Output
from ._local_storage import ByteWrite, LocalByteStore


class OriginalCommitProjection:
    """Transport holder of at most two original Core output loans.

    This neither commits nor interprets a Run. The trusted Host uses this caller
    under its Core-to-Store lock order, with separately reserved SQLite/descriptor
    workspace, original payload fences, schema/facts validation, and the original
    current publisher port. Those responsibilities are not provided by this view.

    Success retires each pair only after synchronous consumption completes and
    temporary field references are gone. The physical consumer must not retain
    the borrowed write or its bytes after return. Any failure leaves the exact loans here
    and in Core. Finish physical transaction/consumer cleanup and discard retained
    failure tracebacks before close(); close releases only these original outputs,
    never the publication, its Source/Result parents, or the Run. No automatic
    replacement projection or physical write is attempted after failure.
    """

    def __init__(self, core: LocalCore, publication: _Output,
                 current_configuration: int, *, cleanup: Callable[[], bool]) -> None:
        if type(core) is not LocalCore or not callable(cleanup):
            raise ValueError('Invalid original Local commit projection')
        with core._lock:
            core._publication_configuration(publication, current_configuration)
        self._core = core
        self._publication = publication
        self._configuration = current_configuration
        self._cleanup = cleanup
        self._outputs: list[_Output] = []
        self._projecting = False
        self._closing = False

    @property
    def pending_outputs(self) -> tuple[_Output, ...]:
        """Exact cleanup handles, not serialized authority or replay permission."""
        with self._core._lock:
            return tuple(self._outputs)

    def count(self) -> int:
        with self._core._lock:
            self._ready()
            return self._core.publication_commit_material_count(
                self._publication, self._configuration)

    @contextmanager
    def serialized(self) -> Iterator[None]:
        """Hold Core before entering the physical Store transaction/lock.

        This changes no Owner fact. It prevents a Store-to-Core callback from
        competing with a Core-to-Store operation in another Host thread.
        """
        with self._core._lock:
            self._ready()
            yield

    def authorize_commit(self, publisher: _Output) -> None:
        """Call the original publisher stage; no grant, write or ACK is made."""
        with self._core._lock:
            self._ready()
            self._core.authorize_publisher(
                publisher, self._configuration, stage='commit',
                publication=self._publication)

    def project_contract(self, ordinal: int, consume: Callable[[ByteWrite], object], *,
                         expected_generation: int | None = None) -> None:
        """Consume original identity/body without recreating or parsing a contract."""
        self._project(ordinal, False, consume, expected_generation)

    def project_index_reference(self, consume: Callable[[ByteWrite], object], *,
                                expected_generation: int | None = None) -> None:
        """Consume the Owner's scoped key and original index CID, not JSON body."""
        self._project(7, True, consume, expected_generation)

    def project_schema(self, result: int, consume: Callable[[ByteWrite], object], *,
                       expected_generation: int | None = None) -> None:
        """Consume original receipt identity/wire into the schema namespace.

        This transports the schema. The original physical binding validation
        and current publisher/commit ACK remain separate Host/Owner obligations.
        """
        self._project(result, False, consume, expected_generation, schema=True)

    def _ready(self) -> None:
        if self._closing or self._projecting or self._outputs:
            raise RuntimeError('Local commit projection is closing or cleanup is pending')
        self._core._publication_configuration(self._publication, self._configuration)

    def _project(self, ordinal: int, index_reference: bool,
                 consume: Callable[[ByteWrite], object], generation: int | None, *,
                 schema: bool = False) -> None:
        if (type(ordinal) is not int or not 0 <= ordinal < 2**31
                or not callable(consume)
                or (generation is not None and (type(generation) is not int
                                                or not 0 <= generation < 2**63 - 1))):
            raise ValueError('Invalid original Local commit projection controls')
        with self._core._lock:
            self._ready()
            self._projecting = True
            try:
                # _consume returns without retaining field bytes or descriptors.
                # On failure its traceback can retain them; keep their reservations
                # until the Host resolves that physical failure and explicitly closes.
                self._consume(ordinal, index_reference, consume, generation, schema=schema)
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_commit_projection_cleanup', -9)
            finally:
                self._projecting = False

    def _output(self) -> _Output:
        value = self._core.reserve_publication_commit_export(
            self._publication, cleanup=self._cleanup)
        self._outputs.append(value)
        return value

    @staticmethod
    def _address(raw: bytes, *, index_key: bool) -> str:
        # Closed physical address fields only. Their identity/preimage comes
        # from the original Owner; Python does not compute or certify a CID.
        suffix = raw if index_key else raw[7:]
        if (len(raw) != (64 if index_key else 71)
                or (not index_key and raw[:7] != b'sha256:')
                or any(byte not in b'0123456789abcdef' for byte in suffix)):
            raise LocalCoreError('original_commit_projection_address', -33)
        return raw.decode('ascii')

    def _consume(self, ordinal: int, index_reference: bool,
                 consume: Callable[[ByteWrite], object], generation: int | None, *,
                 schema: bool = False) -> None:
        core = self._core
        address_output = self._output()
        if schema:
            core.produce_publication_commit_schema(
                address_output, self._configuration, ordinal, field='identity')
        elif index_reference:
            core.produce_publication_commit_index_key(address_output, self._configuration)
        else:
            core.produce_publication_commit_material(
                address_output, self._configuration, ordinal, field='identity')
        raw_address = core.read_publication_commit_material(address_output)
        address = self._address(raw_address, index_key=index_reference)
        key = LocalByteStore.namespaced_key(
            ('result_schema' if schema else
             'public_index' if index_reference else 'publication_contract'), address)
        payload_output = self._output()
        if schema:
            core.produce_publication_commit_schema(
                payload_output, self._configuration, ordinal, field='wire')
        else:
            core.produce_publication_commit_material(
                payload_output, self._configuration, ordinal,
                field='identity' if index_reference else 'wire')
        payload = core.read_publication_commit_material(payload_output)
        if index_reference:
            self._address(payload, index_key=False)
        if consume(ByteWrite(key, generation, payload)) is not None:
            raise ValueError('Invalid synchronous Local commit consumer result')

    def _retire_outputs(self) -> None:
        for value in tuple(reversed(self._outputs)):
            if self._core.close_publication_commit_export(value):
                self._outputs.remove(value)

    def close(self) -> bool:
        """Retry original output cleanup only; never cancel, submit or commit."""
        with self._core._lock:
            if self._projecting:
                raise RuntimeError('Local commit projection is still in use')
            self._closing = True
            self._retire_outputs()
            return not self._outputs
