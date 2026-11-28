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
import json
from pathlib import Path
from struct import pack
from typing import Callable, NoReturn

from ._local_core import LocalCore, _Input, _Output
from ._local_installation import _object
from ._local_project_files import OriginalLocalProjectFiles, _ProjectFile
from ._values import wire_bytes


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
        self._mock_data: _ProjectFile | None = None
        self._mock_data_path: Path | None = None
        self._mock_seed_attempted = self._mock_seed_ready = False
        self._mock_seed: _Output | None = None
        self._mock_inputs: _Output | None = None
        self._mock_files: OriginalLocalProjectFiles | None = None
        self._model_registry: _Output | None = None
        self._model_registry_file: _ProjectFile | None = None
        self._model_files: OriginalLocalProjectFiles | None = None
        self._model_task_locators: tuple[tuple[str, str], ...] = ()
        self._model_tasks: list[_Output] = []
        self._local_inputs: _Output | None = None
        self._local_files: OriginalLocalProjectFiles | None = None
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

    def _task_locators(self, output: _Output, *, bound: int) -> tuple[tuple[str, str], ...]:
        tasks = json.loads(self._core.read_original_metadata(output))
        if (type(tasks) is not list or len(tasks) > bound
                or any(type(item) is not list or len(item) != 2
                       or any(type(part) is not str for part in item) for item in tasks)):
            raise ValueError('Invalid original Model task locators')
        return tuple((task, path) for task, path in tasks)

    def prepare_model_registry(self, files: OriginalLocalProjectFiles, *,
                               base: Path, registry: _ProjectFile,
                               copy: Callable[[bytes], _Input],
                               reserve: Callable[[Callable[[], _Output]], _Output]
                               ) -> tuple[tuple[str, str], ...]:
        """Borrow only the selected file and its original Project preparation."""
        with self._core._lock:
            self._active()
            locations = self._locations
            if (files._core is not self._core or self._model_registry is not None
                    or locations is None or locations.profile == 'mock'
                    or locations.model_tasks is None
                    or registry.path != files._path(base / locations.model_tasks)):
                raise ValueError('Original selected Model registry is unavailable')
            files.current()
            body = files.original_bytes(registry)
            if not body:
                raise ValueError('Original selected Model registry is empty')
            original_registry = copy(body)
            source = copy(b'{"project":%d,"registry":%d}' %
                          (self._output.handle, original_registry.handle))
            # A declaration consumes input bytes and three output tokens.
            # Reserve the decoder against both original finite bounds.
            task_bound = min(len(body), (8192 - 1) // 3)
            self._model_registry = reserve(lambda: self._core.reserve_original_metadata(
                source, 11, cleanup=lambda: True, task_locators=task_bound))
            self._core.produce_original_metadata(self._model_registry)
            tasks = self._task_locators(self._model_registry, bound=task_bound)
            files.current()
            self._model_files = files
            self._model_registry_file = registry
            self._model_task_locators = tasks
            return tasks

    def prepare_model_task(self, files: OriginalLocalProjectFiles, *,
                            index: int, task: _ProjectFile,
                            copy: Callable[[bytes], _Input],
                            copy_raw: Callable[[bytes], _Input],
                            reserve: Callable[[Callable[[], _Output]], _Output]) -> None:
        with self._core._lock:
            self._active()
            registry = self._model_registry
            original = self._model_registry_file
            if (files is not self._model_files or registry is None or original is None
                    or type(index) is not int or index != len(self._model_tasks)
                    or index >= len(self._model_task_locators)):
                raise ValueError('Original selected Model Task locator is unavailable')
            _, locator = self._model_task_locators[index]
            if task.path != files._path(original.path.parent / locator):
                raise ValueError('Original selected Model Task file is unavailable')
            files.original_bytes(original)
            loan = copy_raw(files.original_bytes(task))
            descriptor = copy(b'{"registry":%d,"index":%d,"task":%d}' %
                              (registry.handle, index, loan.handle))
            output = reserve(lambda: self._core.reserve_original_metadata(
                descriptor, 12, cleanup=lambda: True))
            self._model_tasks.append(output)
            self._core.produce_original_metadata(output)
            files.current()

    def prepare_mock_inputs(self, files: OriginalLocalProjectFiles, *,
                            base: Path, connectors: _ProjectFile, catalog: _ProjectFile,
                            registry: _ProjectFile | None, copy: Callable[[bytes], _Input],
                            reserve: Callable[[Callable[[], _Output]], _Output]) -> None:
        with self._core._lock:
            self._active()
            if (files._core is not self._core or self._mock_inputs is not None
                    or self._locations is None or self._locations.profile != 'mock'
                    or self._locations.mock_data is None
                    or (self._locations.model_tasks is None) != (registry is None)):
                raise ValueError('Original selected Mock declarations are unavailable')
            data_path = files._path(base / self._locations.mock_data)
            connections_input = copy(files.original_bytes(connectors))
            catalog_input = copy(files.original_bytes(catalog))
            registry_input = None if registry is None else copy(files.original_bytes(registry))
            source = copy(wire_bytes({  # type: ignore[no-untyped-call]
                'project': self._output.handle,
                'connectors': connections_input.handle,
                'catalog': catalog_input.handle,
                'registry': None if registry_input is None else registry_input.handle,
            }))
            self._mock_inputs = reserve(
                lambda: self._core.reserve_original_metadata(source, 6, cleanup=lambda: True))
            self._core.produce_original_metadata(self._mock_inputs)
            files.current()
            self._mock_data_path = data_path
            self._mock_files = files

    def prepare_local_inputs(
        self, files: OriginalLocalProjectFiles, *, connectors: _ProjectFile,
        registry: _ProjectFile | None, copy: Callable[[bytes], _Input],
        reserve: Callable[[Callable[[], _Output]], _Output], model_configuration: _Output | None = None,
    ) -> None:
        """Retain the selected declarations only, without starting a Source."""
        with self._core._lock:
            self._active()
            locations = self._locations
            if (files._core is not self._core or self._local_inputs is not None
                    or locations is None or locations.profile is not None
                    or locations.connectors is None or locations.lock is not None
                    or locations.mock_catalog is not None or locations.mock_data is not None
                    or locations.mock_answers
                    or (locations.model_tasks is None) != (registry is None)
                    or registry is connectors):
                raise ValueError('Original selected Local declarations are unavailable')
            connections_input = copy(files.original_bytes(connectors))
            registry_input = None
            model_registry = self._model_registry
            if model_registry is not None:
                if (registry is not self._model_registry_file or self._model_files is not files
                        or len(self._model_tasks) != 1 or model_configuration is None):
                    raise ValueError('Foreign original Model registry for Local declarations')
                self._core._owned_output(model_registry, 'original')
                self._core._owned_output(model_configuration, 'original')
            elif model_configuration is not None:
                raise ValueError('Original Model configuration has no Local registry')
            elif registry is not None:
                registry_input = copy(files.original_bytes(registry))
            packet = {
                'project': self._output.handle,
                'connectors': connections_input.handle,
                'registry': None if registry_input is None else registry_input.handle,
                'directory': str(connectors.path.parent),
            }
            if model_registry is not None:
                assert model_configuration is not None
                packet['model_registry'] = model_registry.handle
                packet['model_configuration'] = model_configuration.handle
            source = copy(wire_bytes(packet))  # type: ignore[no-untyped-call]
            self._local_inputs = reserve(
                lambda: self._core.reserve_original_metadata(source, 6, cleanup=lambda: True))
            self._core.produce_original_metadata(self._local_inputs)
            files.current()
            self._local_files = files

    def local_inputs_original(self, files: OriginalLocalProjectFiles) -> _Output:
        """Borrow the produced Local declarations from the same Project files."""
        with self._core._lock:
            self._active()
            prepared = self._local_inputs
            if prepared is None or self._local_files is not files:
                raise ValueError('Original selected Local Project inputs are unavailable')
            self._core._owned_output(prepared, 'original')
            files.current()
            return prepared

    def mock_bootstrap_input(self, files: OriginalLocalProjectFiles) -> _Output:
        """Borrow the same prepared project for fresh SDK bootstrap."""
        with self._core._lock:
            self._active()
            prepared = self._mock_inputs
            if (files is not self._mock_files or prepared is None or self._mock_data_path is None
                    or self._locations is None or self._locations.profile != 'mock'):
                raise ValueError('Original selected Mock bootstrap is unavailable')
            self._core._owned_output(prepared, 'original')
            files.current()
            return prepared

    def mock_data_path(self, files: OriginalLocalProjectFiles, project: _Output) -> Path:
        with self._core._lock:
            if self.mock_bootstrap_input(files) is not project or self._mock_data_path is None:
                raise ValueError('Foreign original Mock Project data')
            return self._mock_data_path

    def acquire_mock_data(self, files: OriginalLocalProjectFiles, project: _Output) -> _ProjectFile:
        with self._core._lock:
            path = self.mock_data_path(files, project)
            if self._mock_data is None:
                self._mock_data = files.read_original_mock_data(path, max_bytes=1048576)
            files.mock_data_bytes(self._mock_data)
            return self._mock_data

    def require_mock_seed(self, files: OriginalLocalProjectFiles) -> None:
        with self._core._lock:
            self.mock_bootstrap_input(files)
            if not self._mock_seed_ready or self._mock_data is None:
                raise ValueError('Original Mock Project seed is unavailable')
            files.mock_data_bytes(self._mock_data)

    def attach_mock_seed(
        self, files: OriginalLocalProjectFiles, project: _Output, configuration: int,
        current: _Output, *, fill: Callable[[bytes], _Input],
        reserve: Callable[[Callable[[], _Output]], _Output],
    ) -> None:
        with self._core._lock:
            if self.mock_bootstrap_input(files) is not project:
                raise ValueError('Foreign original Mock Project seed')
            if self._mock_seed_ready:
                self.require_mock_seed(files)
                return
            if self._mock_seed_attempted:
                raise ValueError('Original Mock Project seed attachment already attempted')
            self._mock_seed_attempted = True
            data = self.acquire_mock_data(files, project)
            raw = fill(files.mock_data_bytes(data))
            packet = fill(pack('<III', project.handle, configuration, raw.handle))
            self._mock_seed = reserve(lambda: self._core.reserve_original_metadata(
                packet, 8, cleanup=lambda: True))
            self._core.produce_original_metadata(self._mock_seed, current=current)
            files.mock_data_bytes(data)
            if not self._core.close_original_metadata(self._mock_seed):
                raise ValueError('Original Mock Project seed attachment cleanup is pending')
            self._mock_seed = None
            self._mock_seed_ready = True

    def close(self) -> bool:
        with self._core._lock:
            self._nominal()
            if self._closed:
                return True
            if self._mock_seed is not None:
                if not self._core.close_original_metadata(self._mock_seed):
                    return False
                self._mock_seed = None
            if self._mock_inputs is not None:
                if not self._core.close_original_metadata(self._mock_inputs):
                    return False
                self._mock_inputs = None
                self._mock_files = None
                self._mock_data = None
                self._mock_data_path = None
            if self._local_inputs is not None:
                if not self._core.close_original_metadata(self._local_inputs):
                    return False
                self._local_inputs = None
                self._local_files = None
            while self._model_tasks:
                if not self._core.close_original_metadata(self._model_tasks[-1]):
                    return False
                self._model_tasks.pop()
            if self._model_registry is not None:
                if not self._core.close_original_metadata(self._model_registry):
                    return False
                self._model_registry = None
                self._model_registry_file = None
                self._model_files = None
                self._model_task_locators = ()
            if not self._core.close_original_metadata(self._output):
                return False
            self._closed = True
            self._locations = None
            return True
