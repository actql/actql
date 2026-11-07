"""Project/profile intake through the existing Core configuration Owner.

Responsibility: project locators from the same admitted configuration, not a Host.
Inputs/outputs: one reserved original input and immutable locator DATA.
Identity: retain the same Core input and metadata output until retirement.
Ownership: the caller owns input/files; Core owns the output and typed selection.
Synchronization: use the original Core lock and nominal loans on every operation.
Failure: preserve failed preparation and output custody; never reprepare it.
Cancellation: caller cancellation neither closes the source nor supplies a Run stop.
Resources: existing bounded metadata reservation precedes parsing and copying.
Extension: selected profile installation remains the existing Host's responsibility.
Verification: original loan, immutable projection and failed cleanup cases.
"""
from dataclasses import dataclass
import hashlib
from typing import NoReturn

from ._local_core import LocalCore, _Input
from ._local_installation import _object


@dataclass(frozen=True, slots=True)
class ProjectLocations:
    connectors: str | None
    model_tasks: str | None
    lock: str | None
    state_dir: str
    profile: str | None
    mock_catalog: str | None
    mock_data: str | None
    mock_answers: tuple[tuple[str, str], ...]


class OriginalLocalProjectConfiguration:
    """An existing metadata child; this wrapper issues no permission or ACK."""

    def __init__(self, core: LocalCore, source: _Input) -> None:
        if type(core) is not LocalCore:
            raise ValueError('Original project Core is unavailable')
        self._original = self
        self._core, self._source = core, source
        self._attempted = self._closed = False
        self._locations: ProjectLocations | None = None
        # Return the wrapper before its fallible preparation; its caller can
        # retain this same child in the existing Host cleanup sequence.
        self._output = core.reserve_original_metadata(source, 5, cleanup=lambda: True)

    def __copy__(self) -> NoReturn:
        raise TypeError('Original project configuration cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original project configuration cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original project configuration cannot be serialized')

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign original project configuration')

    def _active(self) -> None:
        self._nominal()
        if self._closed or self._core._closing:
            raise ValueError('Original project configuration is retired or closing')
        self._core._owned_input(self._source)
        self._core._owned_output(self._output, 'original')

    def prepare(self) -> ProjectLocations:
        with self._core._lock:
            self._active()
            if self._locations is not None:
                return self._locations
            if self._attempted:
                raise ValueError('Original project preparation already failed')
            self._attempted = True
            self._core.produce_original_metadata(self._output)
            envelope = _object(self._core.read_original_metadata(self._output), 65536)
            if set(envelope) != {'body', 'cid'} or type(envelope['body']) is not str:
                raise ValueError('Invalid original project metadata envelope')
            raw = envelope['body'].encode('utf-8')
            if envelope['cid'] != 'sha256:' + hashlib.sha256(raw).hexdigest():
                raise ValueError('Changed original project metadata bytes')
            value = _object(raw, 65536)
            if set(value) != {'connectors', 'model_tasks', 'lock', 'state_dir',
                              'profile', 'mock_catalog', 'mock_data', 'mock_answers'}:
                raise ValueError('Invalid original project metadata fields')
            for name in ('connectors', 'model_tasks', 'lock', 'profile', 'mock_catalog', 'mock_data'):
                if value[name] is not None and type(value[name]) is not str:
                    raise ValueError('Invalid original project locator')
            answers = value['mock_answers']
            if (type(value['state_dir']) is not str or type(answers) is not list
                    or any(type(item) is not list or len(item) != 2
                           or any(type(part) is not str for part in item) for item in answers)):
                raise ValueError('Invalid original project locator collection')
            # Core already chose the profile. Python neither filters Mock
            # inputs nor infers identifiers, registrations or authority.
            self._locations = ProjectLocations(value['connectors'], value['model_tasks'],
                value['lock'], value['state_dir'], value['profile'],
                value['mock_catalog'], value['mock_data'],
                tuple((item[0], item[1]) for item in answers))
            return self._locations

    def close(self) -> bool:
        with self._core._lock:
            self._nominal()
            if self._closed:
                return True
            if not self._core.close_original_metadata(self._output):
                return False
            self._closed = True
            self._locations = None
            return True
