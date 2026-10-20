"""Bounded original descriptor transport; Core owns read and sink meaning."""
from ._local_core import _Input, _Output
from ._local_files import (
    LocalReaderAcquisitionError, LocalOriginalAcquisitionError, PhysicalFileChunk,
    _FileReader, _OriginalFileReader,
)
from ._local_reader_facts import OriginalReaderFacts
from ._local_sdk_delivery_storage import OriginalSDKDeliveryStore


class SDKPayloadReaderCleanupPending(RuntimeError):
    def __init__(self, reader: 'OriginalSDKPayloadReader') -> None:
        super().__init__('Original SDK payload reader cleanup is pending')
        self.cleanup_reader = reader


class OriginalSDKPayloadReader:
    """Borrow original first workspace and one additional bounded descriptor.

    The Host must already fund its selected descriptor/hash/Python envelope.
    This does not retroactively fund bootstrap or assert a process/RSS bound.
    Original first workspace remains held until this borrower closes; Core
    independently reserves each raw transfer and encoded output. Existing File
    descriptor/chunk caps apply. EOF, input release and close are not a receipt,
    durable Store ACK, permission to replay or a Run cancellation.
    """
    def __init__(self, storage: OriginalSDKDeliveryStore, request: _Input,
                 clock: _Input, fact: OriginalReaderFacts) -> None:
        if type(storage) is not OriginalSDKDeliveryStore:
            raise ValueError('Invalid original SDK payload storage')
        core = storage._core
        with core._lock:
            storage._nominal()
            core._owned_input(request)
            core._owned_input(clock)
            storage.original_first_output(request)
            if (type(fact) is not OriginalReaderFacts
                    or not any(original is fact for original in storage._observation._facts)
                    or request.ticket in storage._payload_reader_borrows
                    or not 0 < fact._root._max_chunk_bytes <= 65536):
                raise ValueError('Invalid original SDK payload descriptor selection')
            workspace = storage._first_workspaces.get(request.ticket)
            if workspace is None:
                raise ValueError('Original SDK payload workspace is unavailable')
            core._owned(workspace)
            self._original = self
            self._storage, self._request, self._fact = storage, request, fact
            self._core, self._root = core, fact._root
            self._reader: _FileReader | _OriginalFileReader | None = None
            self._chunk: PhysicalFileChunk | None = None
            self._input: _Input | None = None
            self._uncertain_input: int | None = None
            self._output: _Output | None = None
            self._active = self._reading = self._closing = False
            self._closed = False
            self._confirmed: int | None = None
            storage._payload_reader_borrows[request.ticket] = self
            try:
                storage.bind_original_payload(request, clock, fact)
                storage.prepare_original_input(request, clock)
                with self._root._lock:
                    expected = fact._observe_reader()
                    try:
                        if isinstance(fact._reader, _OriginalFileReader):
                            self._reader = self._root.open_saved_payload(fact._reader.name, expected)
                        else:
                            self._reader = self._root.open_reader(fact._reader.finalization)
                    except (LocalReaderAcquisitionError, LocalOriginalAcquisitionError) as error:
                        self._reader = error.original_reader
                        raise
                storage.prepare_original_input(request, clock)
            except BaseException as error:
                raise SDKPayloadReaderCleanupPending(self) from error

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original SDK payload reader')
        self._storage._nominal()
        if self._storage._payload_reader_borrows.get(self._request.ticket) is not self:
            raise ValueError('Retired or foreign original SDK payload reader')

    def offer(self, clock: _Input) -> tuple[_Output, bytes]:
        """Offer one encoded chunk without advancing physical source or sink.

        Call accept() only after this exact output was physically accepted.
        A failure preserves the descriptor/chunk/input/output for explicit
        cleanup; it never rereads a source, retries a Store write or returns EOF.
        """
        with self._core._lock:
            self._nominal()
            if (self._active or self._closing or self._reader is None
                    or self._chunk is not None or self._input is not None
                    or self._uncertain_input is not None or self._output is not None):
                raise RuntimeError('Original SDK payload reader is unavailable or cleanup is pending')
            self._active = True
            try:
                self._storage.prepare_original_input(self._request, clock)
                self._reading = True
                try:
                    self._chunk = (self._root.read_original(self._reader)
                                   if isinstance(self._reader, _OriginalFileReader)
                                   else self._root.read_reader(self._reader))
                finally:
                    self._reading = False
                chunk = self._chunk
                self._uncertain_input = self._core._next_ticket
                try:
                    self._input = self._core.reserve_input(chunk.data,
                        cleanup=lambda: not self._reading,
                        stopped=lambda _: not self._reading)
                except BaseException:
                    if (self._uncertain_input not in self._core._inputs
                            and self._uncertain_input not in self._core._released):
                        self._uncertain_input = None
                    raise
                self._uncertain_input = None
                self._core.fill_input(self._input, 0, self._input.length)
                self._core.seal_input(self._input)
                self._output = self._storage.produce_original_chunk(
                    self._request, self._input, clock, eof=chunk.eof)
                payload = self._storage.read_original_chunk(
                    self._request, self._input, clock, self._output, eof=chunk.eof)
                if isinstance(self._reader, _OriginalFileReader):
                    self._root._validate_original(self._reader)
                else:
                    self._root._validate_reader(self._reader)
                if self._closing:
                    raise RuntimeError('Original SDK payload reader is closing')
                return self._output, payload
            finally:
                self._active = False

    def accept(self, output: _Output) -> int:
        """Record sink acceptance, return original Core loans, then advance FD.

        Physical acceptance remains recorded if later cleanup fails. Retry only
        the same output/input retirement; never confirm a different chunk.
        """
        with self._core._lock:
            self._nominal()
            if (self._active or self._closing or self._reader is None
                    or self._chunk is None or self._input is None
                    or self._output is not output):
                raise ValueError('Foreign or unavailable original SDK payload acceptance')
            self._active = True
            try:
                if self._confirmed is None:
                    self._confirmed = self._storage.confirm_original_chunk(self._request, output)
                count = self._confirmed
                if not self._storage.close_original_payload_output(self._request):
                    raise SDKPayloadReaderCleanupPending(self)
                if not self._core.close_input(self._input):
                    raise SDKPayloadReaderCleanupPending(self)
                self._input = None
                if isinstance(self._reader, _OriginalFileReader):
                    self._root.release_original_chunk(self._reader, self._chunk)
                else:
                    self._root.release_reader_chunk(self._reader, self._chunk)
                self._chunk = None
                self._output = None
                self._confirmed = None
                if self._reader.eof:
                    if isinstance(self._reader, _OriginalFileReader):
                        self._root.observe_original(self._reader)
                    else:
                        self._root.observe_completed_reader(self._reader)
                return count
            finally:
                self._active = False

    def close(self) -> bool:
        """Close transport children only; original Run/result/Store stay owned."""
        with self._core._lock:
            if self._original is not self:
                raise ValueError('Copied original SDK payload reader')
            if self._closed:
                return True
            self._nominal()
            self._closing = True
            if self._active or self._reading:
                return False
            if not self._storage.close_original_payload_output(self._request):
                return False
            self._output = None
            if self._uncertain_input is not None:
                if not self._core._closed:
                    return False
                self._uncertain_input = None
            if self._input is not None:
                if not self._core.close_input(self._input):
                    return False
                self._input = None
            if self._reader is not None:
                closed = (self._root.close_original(self._reader)
                          if isinstance(self._reader, _OriginalFileReader)
                          else self._root.close_reader(self._reader))
                if not closed:
                    return False
                self._reader = None
            self._chunk = None
            self._confirmed = None
            del self._storage._payload_reader_borrows[self._request.ticket]
            self._closed = True
            return True
