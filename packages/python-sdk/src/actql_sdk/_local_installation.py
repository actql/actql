"""Trusted installed assembly; original Core metadata and physical Host custody."""
from collections.abc import Callable
import json
import os
from pathlib import Path
import secrets
import stat
from typing import Any, TypeVar

from ._local_core import LocalCore, _Input, _Output, _Workspace
from ._local_files import (
    LocalFileRoot, LocalFileAcquisitionError, LocalOriginalAcquisitionError,
    LocalFileInitializationError,
    _PayloadFile, _OriginalFileReader,
)
from ._local_host_binding import OriginalHostBinding, LocalHostBindingCleanupPending, _body
from ._local_host_files import LocalHostFiles, _HostFile
from ._local_storage import LocalByteStore, LocalStorageInitializationError, ByteWrite
from ._local_native_store import _OriginalNativeStoreSelection
from ._local_submission import LocalSubmissionAuthority

_T = TypeVar('_T')
_FILES = {
    'account': 'account.json', 'retention_dependencies': 'retention.json',
    'retention_policy': 'retention-policy.json', 'store': 'store.json',
    'result_policy': 'result-policy.json', 'environment': 'environment.json',
    'compute': 'compute.json',
}
_SDK_FILES = {'run_policy_profile': 'run-policy-profile.json', 'sdk_read': 'sdk-read.json'}


class LocalInstallationCleanupPending(RuntimeError):
    def __init__(self, installation: 'OriginalLocalInstallation') -> None:
        super().__init__('Original Local installation is incomplete; cleanup remains owned')
        self.cleanup_installation = installation


def _object(raw: bytes, maximum: int) -> dict[str, Any]:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate original Local physical metadata field')
            result[key] = value
        return result
    if type(raw) is not bytes or len(raw) > maximum:
        raise ValueError('Original Local physical metadata exceeds its bound')
    result = json.loads(raw, object_pairs_hook=pairs)
    if type(result) is not dict:
        raise ValueError('Original Local physical metadata is not an object')
    return result


class OriginalLocalInstallation:
    """Wire existing Core issuers to durable originals and the same physical Store.

    This private factory is selected only by trusted product assembly. It is not
    an SDK configuration/permission callback. The parent must be a private owned
    installation directory. Default location discovery belongs to public Local
    assembly; no Program can select this path or supply its own Account/Policy.

    Missing or partial source/state material never triggers another bootstrap.
    Core emits every configuration/custody preimage; restoration compares the
    same originals and retains physical generations. Python provides physical
    directory/file/clock/key/SQLite IO only. This object stores resource loans,
    not Run, Scheduler, Recovery or publication state. No Source/Compute/Model/
    Effect starts here. Current scope/permission still comes from Common.
    """

    def __init__(self, core: LocalCore, parent: Path, *, observed_at: str,
                 now: Callable[[], int], project_epoch: Callable[[int, bytes], bytes],
                 sdk_finite: bool = False,
                 native_store: _OriginalNativeStoreSelection | None = None) -> None:
        if (type(core) is not LocalCore or not callable(now) or not callable(project_epoch)
                or type(sdk_finite) is not bool):
            raise ValueError('Invalid original Local installation supplier')
        if native_store is not None:
            if type(native_store) is not _OriginalNativeStoreSelection:
                raise ValueError('Invalid original Native installation Store')
            native_store.require_core(core)
        self._original = self
        self._core = core
        self._native_store = native_store
        self._path = parent.absolute()
        self._roots: list[LocalFileRoot] = []
        self._root_names: list[tuple[LocalFileRoot, Path]] = []
        self._writers: list[tuple[LocalFileRoot, _PayloadFile]] = []
        self._readers: list[tuple[LocalFileRoot, _OriginalFileReader]] = []
        self._inputs: list[_Input] = []
        self._outputs: list[tuple[str, _Output]] = []
        self._workspaces: list[_Workspace] = []
        self._uncertain_ticket: int | None = None
        self._pins: list[LocalHostFiles] = []
        self._store: LocalByteStore | None = None
        self._epoch: LocalSubmissionAuthority | None = None
        self._binding: OriginalHostBinding | None = None
        self._closing = False
        self._source: LocalFileRoot | None = None
        self._state: LocalFileRoot | None = None
        self._results: LocalFileRoot | None = None
        files = _FILES | _SDK_FILES if sdk_finite else _FILES
        file_limit: Callable[[str], int] = lambda key: 8192 if key in _SDK_FILES else 65536
        try:
            with core._lock:
                parent_root = self._root(self._path)
                names = os.listdir(parent_root._open())
                fresh = not names
                if not fresh and not {'source', 'state'} <= set(names):
                    raise ValueError('Original Local installation custody is incomplete')
                # Reserve setup/SQLite/encoding workspace before any physical
                # allocation. Exact source byte holding is separately reserved.
                self._workspaces.append(self._reserve(lambda: core.reserve_workspace(
                    655360, stopped=lambda: True, cleanup=lambda: True)))
                if sdk_finite:
                    # Two additional original file/decoded-body holdings, each
                    # bounded at 8 KiB, precharged before producer/acquisition.
                    # The existing bounded output/copy reservation is separate.
                    self._workspaces.append(self._reserve(lambda: core.reserve_workspace(
                        8 * 2 * 8192, stopped=lambda: True, cleanup=lambda: True)))
                if fresh:
                    packet_input = self._copy({'configuration_root': str(self._path / 'source'),
                                               'observed_at': observed_at})
                    bootstrap = self._reserve(lambda: (core.reserve_sdk_bootstrap(packet_input, cleanup=lambda: True)
                        if sdk_finite else core.reserve_bootstrap(packet_input, cleanup=lambda: True)))
                    self._outputs.append(('bootstrap_sdk' if sdk_finite else 'bootstrap', bootstrap))
                    if sdk_finite:
                        core.produce_sdk_bootstrap(bootstrap)
                        raw = core.read_sdk_bootstrap(bootstrap)
                    else:
                        core.produce_bootstrap(bootstrap)
                        raw = core.read_bootstrap(bootstrap)
                    self._workspaces.append(self._reserve(lambda: core.reserve_workspace(
                        8 * len(raw) + 8 * 65536, stopped=lambda: True, cleanup=lambda: True)))
                    packet = _object(raw, 1048576)
                    if set(packet) != set(files) or any(type(value) is not str for value in packet.values()):
                        raise ValueError('Invalid original Core bootstrap material')
                    for name in ('source', 'state'):
                        os.mkdir(name, 0o700, dir_fd=parent_root._open())
                    os.fsync(parent_root._open())
                    source = self._root(self._path / 'source')
                    state = self._root(self._path / 'state')
                    for key, name in files.items():
                        body = packet[key].encode('utf-8')
                        if len(body) > file_limit(key):
                            raise ValueError('Original Local product material exceeds its bound')
                        self._write(source, name, body)
                    os.mkdir('results', 0o700, dir_fd=source._open())
                    os.fsync(source._open())
                else:
                    source = self._root(self._path / 'source')
                    state = self._root(self._path / 'state')
                self._source, self._state = source, state
                results = self._root(self._path / 'source' / 'results')
                self._results = results
                assert results._identity is not None and parent_root._identity is not None
                assert source._identity is not None and state._identity is not None
                # Reopen reserves the same maximum raw source holding before
                # any source read; fresh bootstrap already owns this allowance.
                if not fresh:
                    self._workspaces.append(self._reserve(lambda: core.reserve_workspace(
                        8 * 7 * 65536, stopped=lambda: True, cleanup=lambda: True)))
                raw_files = {key: self._read(source, name, file_limit(key)) for key, name in files.items()}
                selected = sorted((name, raw_files[key]) for key, name in files.items() if key != 'account')
                if len(selected) > 8:
                    raise ValueError('Original Local selected file bound exceeded')
                setting_fields = []
                for name, body in selected:
                    info = os.stat(name, dir_fd=source._open(), follow_symlinks=False)
                    setting_fields.append({'name': name, 'body': body.decode('utf-8'),
                                           'device': str(info.st_dev), 'inode': str(info.st_ino),
                                           'size': str(info.st_size)})
                settings_output, settings = self._project(4, {'files': setting_fields,
                    'managed_root': {'device': str(results._identity.device),
                                     'inode': str(results._identity.inode),
                                     'path': str(self._path / 'source' / 'results')}})
                nonce = secrets.token_hex(32) if fresh else _object(
                    self._read(state, 'initialization.json', 8192), 8192).get('nonce')
                info = os.stat('account.json', dir_fd=source._open(), follow_symlinks=False)
                initialization_output, initialization = self._project(1, {
                    'account': raw_files['account'].decode('utf-8'), 'settings': settings.decode('utf-8'),
                    'nonce': nonce, 'parent_device': str(parent_root._identity.device),
                    'parent_inode': str(parent_root._identity.inode),
                    'root_device': str(state._identity.device), 'root_inode': str(state._identity.inode),
                    'source_root_device': str(source._identity.device),
                    'source_root_inode': str(source._identity.inode),
                    'source_device': str(info.st_dev), 'source_inode': str(info.st_ino),
                    'source_size': str(info.st_size), 'source_file': 'account.json',
                    'source_path': str(self._path / 'source'), 'state_name': 'state'})
                self._save_or_check(state, 'initialization.json', initialization, fresh)
                self._save_or_check(state, 'account.json', raw_files['account'], fresh)
                info = os.stat('account.json', dir_fd=state._open(), follow_symlinks=False)
                configuration_output, configuration = self._project(2, {
                    'initialization': initialization.decode('utf-8'), 'device': str(info.st_dev),
                    'inode': str(info.st_ino), 'size': str(info.st_size)})
                self._save_or_check(state, 'configuration-custody.json', configuration, fresh)
                db_file = None
                if fresh:
                    db_file = self._writer(state, 'client.sqlite3', 0)
                info = os.stat('client.sqlite3', dir_fd=state._open(), follow_symlinks=False)
                journal_output, journal = self._project(3, {
                    'initialization': initialization.decode('utf-8'),
                    'configuration_custody': configuration.decode('utf-8'),
                    'device': str(info.st_dev), 'inode': str(info.st_ino)})
                self._save_or_check(state, 'journal-custody.json', journal, fresh)
                self._save_or_check(state, 'journal-initializing.json', journal, fresh)
                if native_store is not None:
                    store = native_store.open(core, self._path / 'state' / 'client.sqlite3',
                        state, new_file=db_file, max_records=1024,
                        max_record_bytes=1048576, max_payload_bytes=8388608,
                        max_inspection_queries=16384)
                elif fresh:
                    assert db_file is not None
                    store = LocalByteStore.initialize_owned_file(self._path / 'state' / 'client.sqlite3',
                        state, db_file, max_records=1024, max_record_bytes=1048576,
                        max_payload_bytes=8388608, max_inspection_queries=16384)
                else:
                    store = LocalByteStore(self._path / 'state' / 'client.sqlite3',
                        max_records=1024, max_record_bytes=1048576,
                        max_payload_bytes=8388608, max_inspection_queries=16384)
                self._store = store
                self._observe_roots()
                initial_rows: tuple[ByteWrite, ...] = ()
                if fresh:
                    # Existing trusted first-adoption counter seeds. Their
                    # inventories and every later issuance remain Core-owned.
                    rows = [('client_local_adoption', 'adoption', journal),
                            ('client_local_settings', 'manifest', settings)]
                    rows.extend(('client_local_settings', 'file:' + name, body) for name, body in selected)
                    rows.extend((namespace, 'issued', b'0') for namespace in (
                        'client_run_custody', 'client_submitted_intent_custody', 'client_cancel_custody'))
                    initial_rows = tuple(ByteWrite(store.namespaced_key(namespace, key),
                                                  None, body) for namespace, key, body in rows)
                # Original key/settings/adoption share one physical transaction.
                # A failed COMMIT stays unknown; reopened assembly only inspects.
                self._epoch = LocalSubmissionAuthority(store, project_epoch, now=now,
                                                       _initial_rows=initial_rows)
                source_pins = self._pin(source, store, len(files))
                state_pins = self._pin(state, store, 4)
                account = source_pins.read_original('account.json', max_bytes=65536)
                limits_by_name = {name: file_limit(key) for key, name in files.items()}
                selected_pins = tuple(source_pins.read_original(name, max_bytes=limits_by_name[name]) for name, _ in selected)
                staged = state_pins.read_original('account.json', max_bytes=65536)
                original = tuple(state_pins.read_original(name, max_bytes=8192) for name in (
                    'initialization.json', 'configuration-custody.json', 'journal-custody.json'))
                try:
                    self._binding = OriginalHostBinding(core, source_pins, state_pins, account,
                        staged, original[0], original[1], original[2], selected_pins,
                        (initialization_output, configuration_output, journal_output, settings_output),
                        self._epoch, principal='local-cli', connection='local')
                except LocalHostBindingCleanupPending as failure:
                    self._binding = failure.cleanup_binding
                    raise
                self._binding.inspect(lambda _: None)
                self._retire_preparation_readers()
                if fresh:
                    # The same saved files and four original metadata outputs
                    # now own the installation. Retire only the consumed
                    # bootstrap transport before later Run transfers overlap it.
                    closed = (core.close_sdk_bootstrap(bootstrap) if sdk_finite
                              else core.close_bootstrap(bootstrap))
                    if not closed:
                        raise ValueError('Original bootstrap transfer cleanup remains pending')
                    self._outputs.remove(('bootstrap_sdk' if sdk_finite else 'bootstrap', bootstrap))
                    if not core.close_input(packet_input):
                        raise ValueError('Original bootstrap input cleanup remains pending')
                    self._inputs.remove(packet_input)
        except BaseException as failure:
            if isinstance(failure, LocalStorageInitializationError):
                self._store = failure.cleanup_store
            raise LocalInstallationCleanupPending(self) from failure

    def _retire_preparation_readers(self) -> None:
        """Retire consumed initial reads only after the original Host binds.

        The live Host pins already hold their own fully observed original
        descriptors. Match the complete original physical snapshot before
        retiring any preparation descriptor; unmatched originals remain owned.
        No currentness, Account decision or successful cleanup is cached.
        """
        if self._original is not self or self._closing or self._binding is None:
            raise ValueError('Original Local preparation reader retirement is unavailable')
        for root, reader in tuple(self._readers):
            selected = [(pins, member) for pins in self._pins if pins._root is root
                        for member in pins._files.values() if member.name == reader.name]
            if not selected:
                continue
            if len(selected) != 1:
                raise ValueError('Ambiguous original Local preparation reader pin')
            pins, member = selected[0]
            pins._nominal()
            pins._require_original(member)
            if pins._closing or pins._pending or member.reader is reader:
                raise ValueError('Original Local preparation reader has no independent live pin')
            if (root.observe_original(reader) != member.snapshot
                    or root.observe_original(member.reader) != member.snapshot):
                raise ValueError('Original Local preparation reader differs from its Host pin')
            if not root.close_original(reader):
                raise ValueError('Original Local preparation reader cleanup remains pending')
            self._readers.remove((root, reader))
            # A failed/changed observation after close keeps the remaining pin
            # and the same Installation cleanup; never reopen either original.
            pins.current()

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

    def _copy(self, value: object) -> _Input:
        payload = json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode('utf-8')
        loan = self._reserve(lambda: self._core.reserve_input(payload, cleanup=lambda: True, stopped=lambda _: True))
        self._inputs.append(loan)
        for start in range(0, len(payload), 16384):
            self._core.fill_input(loan, start, min(16384, len(payload) - start))
        self._core.seal_input(loan)
        return loan

    def _project(self, kind: int, fields: dict[str, object]) -> tuple[_Output, bytes]:
        loan = self._copy(fields)
        output = self._reserve(lambda: self._core.reserve_original_metadata(loan, kind, cleanup=lambda: True))
        self._outputs.append(('original', output))
        self._core.produce_original_metadata(output)
        return output, _body(self._core.read_original_metadata(output))

    def _root(self, path: Path) -> LocalFileRoot:
        try:
            root = LocalFileRoot(path, max_files=32, max_chunk_bytes=16384)
        except LocalFileInitializationError as failure:
            self._roots.append(failure.original_root)
            raise
        self._roots.append(root)
        self._root_names.append((root, path))
        return root

    def _observe_roots(self) -> None:
        for root, path in self._root_names:
            original = root._identity
            descriptor = os.fstat(root._open())
            named = path.lstat()
            for value in (descriptor, named):
                if (original is None or not stat.S_ISDIR(value.st_mode)
                        or value.st_uid != os.getuid() or value.st_mode & 0o077
                        or (value.st_dev, value.st_ino) != (original.device, original.inode)):
                    raise ValueError('Original Local installation directory changed')
        # Preserve original order; only consecutive members of the SAME root
        # share that directory's before/after physical observation. Every file
        # FD/name and every installation root pathname is still observed now.
        index = 0
        while index < len(self._readers):
            root = self._readers[index][0]
            readers = []
            while index < len(self._readers) and self._readers[index][0] is root:
                readers.append(self._readers[index][1])
                index += 1
            root._observe_originals(tuple(readers))

    def _writer(self, root: LocalFileRoot, name: str, length: int) -> _PayloadFile:
        try:
            value = root.create_writer(name, length)
        except LocalFileAcquisitionError as failure:
            self._writers.append((root, failure.original_file))
            raise
        self._writers.append((root, value))
        return value

    def _write(self, root: LocalFileRoot, name: str, body: bytes) -> None:
        value = self._writer(root, name, len(body))
        for offset in range(0, len(body), 16384):
            chunk = body[offset:offset + 16384]
            if root.append(value, offset, chunk) != len(chunk):
                raise ValueError('Original Local installation write is incomplete')
        root.sync(value)
        if not root.close_writer(value):
            raise ValueError('Original Local installation writer stop is unknown')
        self._writers.remove((root, value))

    def _read(self, root: LocalFileRoot, name: str, maximum: int) -> bytes:
        try:
            reader = root.open_original(name, max_bytes=maximum)
        except LocalOriginalAcquisitionError as failure:
            self._readers.append((root, failure.original_reader))
            raise
        self._readers.append((root, reader))
        result = bytearray()
        while True:
            chunk = root.read_original(reader)
            result.extend(chunk.data)
            root.release_original_chunk(reader, chunk)
            if chunk.eof:
                break
        root.observe_original(reader)
        return bytes(result)

    def _save_or_check(self, root: LocalFileRoot, name: str, body: bytes, fresh: bool) -> None:
        if fresh:
            self._write(root, name, body)
        elif self._read(root, name, len(body)) != body:
            raise ValueError('Original Local saved material changed; no repair is allowed')

    def _pin(self, root: LocalFileRoot, store: LocalByteStore, count: int) -> LocalHostFiles:
        value = LocalHostFiles(root, store, max_files=count, max_bytes=count * 65536,
                              observe_roots=self._observe_roots)
        self._pins.append(value)
        return value

    @property
    def binding(self) -> OriginalHostBinding:
        if self._original is not self or self._closing or self._binding is None:
            raise ValueError('Original Local installation binding is unavailable')
        return self._binding

    def close(self) -> bool:
        """Stop owned resources only; preserve saved files, Store bytes and Run."""
        with self._core._lock:
            if self._original is not self:
                raise ValueError('Copied original Local installation')
            self._closing = True
            if self._binding is not None:
                if not self._binding.close():
                    return False
                self._binding = None
            for pins in tuple(reversed(self._pins)):
                if not pins.close():
                    return False
                self._pins.remove(pins)
            for root, reader in tuple(reversed(self._readers)):
                if not root.close_original(reader):
                    return False
                self._readers.remove((root, reader))
            for root, writer in tuple(reversed(self._writers)):
                if not root.close_writer(writer):
                    return False
                self._writers.remove((root, writer))
            for family, output in tuple(reversed(self._outputs)):
                if not self._core._closed:
                    closed = (self._core.close_sdk_bootstrap(output) if family == 'bootstrap_sdk'
                              else self._core.close_bootstrap(output) if family == 'bootstrap'
                              else self._core.close_original_metadata(output))
                    if not closed:
                        return False
                self._outputs.remove((family, output))
            for loan in tuple(reversed(self._inputs)):
                if not self._core._closed and not self._core.close_input(loan):
                    return False
                self._inputs.remove(loan)
            if self._uncertain_ticket is not None and not self._core._closed:
                return False
            if self._store is not None:
                self._store.close()
                self._store = None
            for root in tuple(reversed(self._roots)):
                if not root.close():
                    return False
                self._roots.remove(root)
            for workspace in tuple(reversed(self._workspaces)):
                if not self._core._closed and not self._core.close_workspace(workspace):
                    return False
                self._workspaces.remove(workspace)
            return True
