"""Trusted installed assembly; original Core metadata and physical Host custody."""
from collections.abc import Callable
from hashlib import sha256
import json
import os
from pathlib import Path
import secrets
import stat
from typing import TYPE_CHECKING, Any, TypeVar

from ._local_core import LocalCore, _Input, _Output, _Workspace
from ._local_files import (
    LocalFileRoot, LocalFileAcquisitionError, LocalOriginalAcquisitionError,
    LocalFileInitializationError,
    _PayloadFile, _OriginalFileReader,
)
from ._local_host_binding import OriginalHostBinding, LocalHostBindingCleanupPending, _body
from ._local_host_files import LocalHostFiles, _HostFile
from ._local_storage import (
    ByteFence, ByteWrite, LocalByteStore, LocalStorageError, LocalStorageInitializationError, StoredBytes,
    _ModelRawFence,
)

if TYPE_CHECKING:
    from ._local_model_crypto import _OriginalModelEvidenceCrypto
    from ._local_model_http import _OriginalModelHttpRawTransfer
    from ._local_work import OriginalLocalWork
from ._local_native_store import _OriginalNativeStoreSelection
from ._local_effect_key_original import (
    _KEY as _EFFECT_HOST_KEY, _host_key_original_body, _observe_host_attestation_generation,
)
from ._local_submission import LocalSubmissionAuthority

_T = TypeVar('_T')
_FILES = {
    'account': 'account.json', 'retention_dependencies': 'retention.json',
    'retention_policy': 'retention-policy.json', 'store': 'store.json',
    'result_policy': 'result-policy.json', 'environment': 'environment.json',
    'compute': 'compute.json',
}
_SDK_FILES = {'run_policy_profile': 'run-policy-profile.json', 'sdk_read': 'sdk-read.json'}
_EFFECT_APPROVAL_FILES = {
    'effect_approval_operator': 'host.json',
    'effect_host_attestation': 'effect-host-attestation.json',
    'effect_reviewer': 'effect-reviewer.json',
}
_PORTABLE_CHAT_FILES = {
    'installation': 'installation.json',
    'contract': 'configuration-contract.json',
    'provider': 'provider.json',
    'response': 'response-profile.json',
}
_PORTABLE_CHAT_SELECTION = 'selection.json'
_PROTECTED_MODEL_ACCOUNT = 'account.json'


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


def _original_file_control_connection(raw: bytes) -> str:
    """Borrow the exact control tuple in the already selected Account DATA."""
    account = _object(raw, 65536)
    profile = {'profile_id': 'actql-local-standard', 'profile_version': '0.1',
        'profile_cid': 'sha256:8c28b41c2fc824e43c77de4726337661b651287d2ac627770dc106e972afd60e'}
    entries = account.get('entries')
    if (account.get('account_id') != 'local-cli' or account.get('bootstrap') != profile
            or type(entries) is not list or any(type(entry) is not dict for entry in entries)):
        raise ValueError('Original Local File Account control is unavailable')
    originals = [entry for entry in entries if entry.get('entry_id') == 'local-result-original-read']
    if len(originals) != 1:
        raise ValueError('Original Local File Result control is unavailable')
    selector = originals[0].get('connection')
    connections = None if type(selector) is not dict or set(selector) != {'any_of'} else selector['any_of']
    if (type(connections) is not list or len(connections) != 1 or type(connections[0]) is not str):
        raise ValueError('Invalid original Local File control connection')
    control = connections[0]
    if control != 'local':
        prefix = 'actql-local-control-'
        ordinal = control[len(prefix):]
        if (not control.startswith(prefix) or not 1 <= len(ordinal) <= 10 or not ordinal.isascii()
                or not ordinal.isdecimal() or len(ordinal) > 1 and ordinal.startswith('0')):
            raise ValueError('Invalid original Local File control connection')
    scope = {'principal': {'any_of': ['local-cli']}, 'connection': selector,
        'outcome': 'allow', 'exclusions': []}
    if originals[0] != {**scope, 'entry_id': 'local-result-original-read',
            'resource': {'any_of': ['result']}, 'operation': {'any_of': ['read']}}:
        raise ValueError('Invalid original Local File Result control')
    run = [entry for entry in entries if entry.get('entry_id') == 'local-run']
    if run != [{**scope, 'entry_id': 'local-run', 'resource': {'any_of': ['run']},
                'operation': {'any_of': ['cancel', 'publish', 'read', 'resolve', 'submit']}}]:
        raise ValueError('Invalid original Local File Run control')
    return control


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
                 native_store: _OriginalNativeStoreSelection | None = None,
                 project_bootstrap: Callable[[], _Output | None] | None = None,
                 local_project_bootstrap: Callable[[], _Output] | None = None,
                 portable_model_directory: Path | None = None) -> None:
        if (type(core) is not LocalCore or not callable(now) or not callable(project_epoch)
                or type(sdk_finite) is not bool
                or project_bootstrap is not None and not callable(project_bootstrap)
                or local_project_bootstrap is not None and (
                    not callable(local_project_bootstrap) or not sdk_finite or project_bootstrap is not None)):
            raise ValueError('Invalid original Local installation supplier')
        if portable_model_directory is not None and (
                not sdk_finite or project_bootstrap is not None
                or not isinstance(portable_model_directory, Path)
                or not portable_model_directory.is_absolute()):
            raise ValueError('Invalid protected Portable Chat deployment selection')
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
        self._portable_chat_root: LocalFileRoot | None = None
        self._portable_chat_attempted = False
        self._portable_chat_output: _Output | None = None
        self._portable_chat_credential: tuple[_Output, str] | None = None
        self._portable_crypto: _OriginalModelEvidenceCrypto | None = None
        self._portable_crypto_policy: str | None = None
        self._portable_chat_ca: tuple[str, str] | None = None
        self._closing = False
        self._approval_provisioned = False
        self._source: LocalFileRoot | None = None
        self._state: LocalFileRoot | None = None
        self._results: LocalFileRoot | None = None
        files = _FILES | _SDK_FILES if sdk_finite else _FILES
        def file_limit(key: str) -> int:
            return 8192 if key in _SDK_FILES or key in _EFFECT_APPROVAL_FILES else 65536
        try:
            with core._lock:
                parent_root = self._root(self._path)
                names = set(os.listdir(parent_root._open()))
                approval_names = set(_EFFECT_APPROVAL_FILES.values())
                provisioned_source: LocalFileRoot | None = None
                existing_state: LocalFileRoot | None = None
                staged_key = False
                if sdk_finite and project_bootstrap is not None:
                    if names == {'source', 'state'}:
                        existing_state = self._root(self._path / 'state')
                        staged_key = set(os.listdir(existing_state._open())) == {_EFFECT_HOST_KEY}
                    if names == {'source'} or staged_key:
                        provisioned_source = self._root(self._path / 'source')
                        if set(os.listdir(provisioned_source._open())) != approval_names:
                            raise ValueError('Original Local approval provisioning is incomplete')
                fresh = not names or provisioned_source is not None
                if not fresh and not {'source', 'state'} <= set(names):
                    raise ValueError('Original Local installation custody is incomplete')
                mock = project_bootstrap() if fresh and project_bootstrap is not None else None
                local = None if local_project_bootstrap is None else local_project_bootstrap()
                def check_project() -> None:
                    if mock is not None and (project_bootstrap is None or project_bootstrap() is not mock):
                        raise ValueError('Original selected Mock project changed during adoption')
                    if local is not None and (local_project_bootstrap is None or local_project_bootstrap() is not local):
                        raise ValueError('Original selected Local project changed during adoption')

                if local is not None:
                    core._owned_output(local, 'original')

                if mock is not None:
                    if not sdk_finite:
                        raise ValueError('Original Mock project requires the finite SDK installation')
                    core._owned_output(mock, 'original')
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
                approval_originals: dict[str, bytes] = {}
                if provisioned_source is not None:
                    if mock is None or local is not None or portable_model_directory is not None:
                        raise ValueError('Original Local approval provisioning requires a selected Mock Project')
                    self._workspaces.append(self._reserve(lambda: core.reserve_workspace(
                        32 * 8192 + 16384, stopped=lambda: True, cleanup=lambda: True)))
                    for key, name in _EFFECT_APPROVAL_FILES.items():
                        approval_originals[key] = self._read(provisioned_source, name, file_limit(key))
                    originals = tuple(original.identity for root, original in
                                      self._readers[-len(approval_originals):] if root is provisioned_source)
                    if (len(originals) != len(approval_originals) or None in originals
                            or len(set(originals)) != len(originals)):
                        raise ValueError('Original Local public approval roles alias')
                selected_account = None
                if portable_model_directory is not None:
                    self._workspaces.append(self._reserve(lambda: core.reserve_workspace(
                        8 * 65536 + 65536, stopped=lambda: True, cleanup=lambda: True)))
                    self._portable_chat_root = self._root(portable_model_directory)
                    selected_account = self._read(self._portable_chat_root, _PROTECTED_MODEL_ACCOUNT, 65536)
                if fresh:
                    request: dict[str, object] = {'configuration_root': str(self._path / 'source'),
                                                  'observed_at': observed_at}
                    if mock is not None:
                        request['mock_project'] = mock.handle
                    if local is not None and selected_account is None:
                        request['local_project'] = local.handle
                    account_input = None
                    if approval_originals:
                        account_input = self._copy({
                            'operator': approval_originals['effect_approval_operator'].decode('utf-8'),
                            'host_attestation': approval_originals['effect_host_attestation'].decode('utf-8'),
                        })
                        request['mock_host_attestation'] = account_input.handle
                    if selected_account is not None:
                        account_input = self._fill(selected_account)
                        request['account_original'] = account_input.handle
                    packet_input = self._copy(request)
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
                    if selected_account is not None:
                        if packet['account'].encode('utf-8') != selected_account:
                            raise ValueError('Bootstrap returned a different protected Account original')
                        self._observe_roots()
                    check_project()
                    if provisioned_source is None:
                        os.mkdir('source', 0o700, dir_fd=parent_root._open())
                    if existing_state is None:
                        os.mkdir('state', 0o700, dir_fd=parent_root._open())
                    os.fsync(parent_root._open())
                    source = (self._root(self._path / 'source') if provisioned_source is None
                              else provisioned_source)
                    state = existing_state or self._root(self._path / 'state')
                    for key, name in files.items():
                        body = packet[key].encode('utf-8')
                        if len(body) > file_limit(key):
                            raise ValueError('Original Local product material exceeds its bound')
                        self._write(source, name, body)
                    if approval_originals:
                        files = files | _EFFECT_APPROVAL_FILES
                    os.mkdir('results', 0o700, dir_fd=source._open())
                    os.fsync(source._open())
                else:
                    source = self._root(self._path / 'source')
                    state = existing_state or self._root(self._path / 'state')
                if not fresh:
                    selected_approval = approval_names.intersection(os.listdir(source._open()))
                    if selected_approval:
                        if not sdk_finite or project_bootstrap is None or selected_approval != approval_names:
                            raise ValueError('Original Local adopted approval selection is incomplete')
                        files = files | _EFFECT_APPROVAL_FILES
                self._approval_provisioned = _EFFECT_APPROVAL_FILES.keys() <= files.keys()
                self._source, self._state = source, state
                results = self._root(self._path / 'source' / 'results')
                self._results = results
                assert results._identity is not None and parent_root._identity is not None
                assert source._identity is not None and state._identity is not None
                # Reopen reserves the same maximum raw source holding before
                # any source read; fresh bootstrap already owns this allowance.
                if not fresh:
                    approval_bytes = len(_EFFECT_APPROVAL_FILES) * 8192 if 'effect_reviewer' in files else 0
                    self._workspaces.append(self._reserve(lambda: core.reserve_workspace(
                        8 * (7 * 65536 + approval_bytes), stopped=lambda: True, cleanup=lambda: True)))
                raw_files = {key: (approval_originals[key] if key in approval_originals
                                   else self._read(source, name, file_limit(key)))
                             for key, name in files.items()}
                if selected_account is not None and raw_files['account'] != selected_account:
                    raise ValueError('Protected Account differs from the adopted original')
                selected = sorted((name, raw_files[key]) for key, name in files.items() if key != 'account')
                if len(selected) > 8 and (
                        len(selected) != 11 or not approval_names <= {name for name, _ in selected}):
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
                ordinary = sdk_finite and getattr(core, '_ordinary_host', False) is True
                if native_store is not None:
                    store = native_store.open(core, self._path / 'state' / 'client.sqlite3',
                        state, new_file=db_file, max_records=1024,
                        max_record_bytes=1048576, max_payload_bytes=8388608,
                        max_inspection_queries=16384, durable_limits=None)
                elif fresh:
                    assert db_file is not None
                    store = LocalByteStore.initialize_owned_file(self._path / 'state' / 'client.sqlite3',
                        state, db_file, max_records=1024, max_record_bytes=1048576,
                        max_payload_bytes=8388608, max_inspection_queries=16384, ordinary=ordinary)
                else:
                    store = LocalByteStore.reopen_owned_file(
                        self._path / 'state' / 'client.sqlite3', state,
                        max_records=1024, max_record_bytes=1048576,
                        max_payload_bytes=8388608, max_inspection_queries=16384, ordinary=ordinary)
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
                        'client_run_custody', 'client_submitted_intent_custody', 'client_cancel_custody',
                        'client_submission_name_custody'))
                    if sdk_finite:
                        rows.append(('client_submitted_intent_usage', 'retained', b'0:0'))
                    initial_rows = tuple(ByteWrite(store.namespaced_key(namespace, key),
                                                  None, body) for namespace, key, body in rows)
                # Original key/settings/adoption share one physical transaction.
                # A failed COMMIT stays unknown; reopened assembly only inspects.
                check_project()
                initial_host_key = None
                if fresh and staged_key:
                    if not approval_originals or state is not existing_state:
                        raise ValueError('Foreign original Local Host attestation initialization')
                    initial_host_key = _host_key_original_body(
                        journal, approval_originals['effect_host_attestation'],
                        _observe_host_attestation_generation(state))
                self._epoch = LocalSubmissionAuthority(store, project_epoch, now=now,
                        _initial_rows=initial_rows, _initial_effect_key=initial_host_key)
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
                        self._epoch, principal='local-cli', connection=(
                            'local' if local is None or selected_account is not None else
                            _original_file_control_connection(raw_files['account'])))
                except LocalHostBindingCleanupPending as failure:
                    self._binding = failure.cleanup_binding
                    raise
                self._binding.inspect(lambda _: None)
                check_project()
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
                    if account_input is not None:
                        if not core.close_input(account_input):
                            raise ValueError('Original protected Account transfer cleanup remains pending')
                        self._inputs.remove(account_input)
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
        loan = self._fill(payload)
        self._core.seal_input(loan)
        return loan

    def _fill(self, payload: bytes) -> _Input:
        loan = self._reserve(lambda: self._core.reserve_input(payload, cleanup=lambda: True, stopped=lambda _: True))
        self._inputs.append(loan)
        for start in range(0, len(payload), 16384):
            self._core.fill_input(loan, start, min(16384, len(payload) - start))
        return loan

    def _project(self, kind: int, fields: dict[str, object]) -> tuple[_Output, bytes]:
        loan = self._copy(fields)
        output = self._reserve(lambda: self._core.reserve_original_metadata(loan, kind, cleanup=lambda: True))
        self._outputs.append(('original', output))
        self._core.produce_original_metadata(output)
        body = _body(self._core.read_original_metadata(output))
        if not self._core.close_input(loan):
            raise ValueError('Original Local metadata input cleanup remains pending')
        self._inputs.remove(loan)
        return output, body

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

    def _require_current_host_files(self, source: LocalHostFiles,
                                    source_values: tuple[_HostFile, ...],
                                    state: LocalHostFiles,
                                    state_values: tuple[_HostFile, ...]) -> None:
        """Observe this closed installed pair, never cache physical evidence.

        Only these exact assembly-owned pins share the installation walk. No
        arbitrary observer runs in this group, and every original raw reader,
        pin FD/name, root and Store generation is still checked on every call.
        The original individual callback path remains separate.
        """
        if (type(self) is not OriginalLocalInstallation or self._original is not self
                or self._closing or type(source) is not LocalHostFiles
                or type(state) is not LocalHostFiles or len(self._pins) != 2
                or self._pins[0] is not source or self._pins[1] is not state
                or source._installation is not self or state._installation is not self
                or source._root is not self._source or state._root is not self._state
                or source._store is not self._store or state._store is not self._store
                or source._observe_roots is not None or state._observe_roots is not None):
            raise ValueError('Foreign or retired original Local installation file group')
        with source._lock, state._lock:
            source._require_original_members(source_values)
            source._require_current_lifetime()
            state._require_original_members(state_values)
            state._require_current_lifetime()
            self._observe_roots()
            source._observe_current_files()
            state._observe_current_files()

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

    def _read(self, root: LocalFileRoot, name: str, maximum: int, *,
              model_trust: _OriginalFileReader | None = None) -> bytes:
        try:
            reader = root.open_original(name, max_bytes=maximum)
        except LocalOriginalAcquisitionError as failure:
            self._readers.append((root, failure.original_reader))
            raise
        self._readers.append((root, reader))
        if model_trust is not None:
            root._require_distinct_model_trust_original(model_trust, reader)
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
                              _installation=self)
        self._pins.append(value)
        return value

    def _prepare_portable_chat_task(self, task: _Output) -> _Output:
        """Hold one kind-13 configuration from a trusted deployment selection."""
        with self._core._lock:
            binding = self.binding
            if self._portable_chat_attempted:
                raise ValueError('Original Portable Chat installation was already selected')
            self._core._owned_output(task, 'original')
            root = self._portable_chat_root
            if root is None:
                raise ValueError('Original Portable Chat deployment was not adopted')
            image_sha256 = self._core._installed_image_sha256
            if image_sha256 is None:
                raise ValueError('Original Portable Chat runtime image is unavailable')
            self._portable_chat_attempted = True
            # Retain each exact body and its transfer overlap, the bounded
            # selection parser and locator carriers before opening the root.
            maximum = 65536
            selection_maximum = 1024
            self._workspaces.append(self._reserve(lambda: self._core.reserve_workspace(
                8 * (len(_PORTABLE_CHAT_FILES) * maximum + selection_maximum) + 65536,
                stopped=lambda: True, cleanup=lambda: True)))
            selection = _object(self._read(root, _PORTABLE_CHAT_SELECTION, selection_maximum),
                                selection_maximum)
            required = {'profile_cid', 'credential_file'}
            selected_fields = set(selection) - {'raw_crypto_policy', 'tls_ca', 'source_catalog'}
            if selected_fields not in (required, required | {'execution_file', 'attempt', 'egress'}):
                raise ValueError('Invalid original Portable Chat deployment selection')
            crypto_policy = selection.get('raw_crypto_policy')
            if 'raw_crypto_policy' in selection and (
                    type(crypto_policy) is not str or crypto_policy != 'builtin-aes-256-gcm'):
                raise ValueError('Original Portable Chat Raw crypto policy is unsupported')
            self._portable_crypto_policy = crypto_policy

            credential_file = selection['credential_file']
            LocalFileRoot._name(credential_file)
            original_files = (_PROTECTED_MODEL_ACCOUNT, _PORTABLE_CHAT_SELECTION, *_PORTABLE_CHAT_FILES.values())
            if credential_file in original_files:
                raise ValueError('Original Portable Chat credential overlaps configuration')
            execution_file = selection.get('execution_file')
            if 'execution_file' in selection:
                if crypto_policy is None:
                    raise ValueError('Original Portable Chat execution requires a Raw crypto policy')
                LocalFileRoot._name(execution_file)
                if execution_file in (*original_files, credential_file):
                    raise ValueError('Original Portable Chat execution file overlaps configuration or credential')
                self._workspaces.append(self._reserve(lambda: self._core.reserve_workspace(
                    8 * maximum, stopped=lambda: True, cleanup=lambda: True)))
            tls_ca = selection.get('tls_ca')
            if 'tls_ca' in selection:
                if type(tls_ca) is not dict or set(tls_ca) != {'file', 'sha256'}:
                    raise ValueError('Invalid original Portable Chat TLS CA locator')
                name = tls_ca['file']
                LocalFileRoot._name(name)
                digest = tls_ca['sha256']
                if (name in (*original_files, credential_file, execution_file)
                        or type(digest) is not str or len(digest) != 71
                        or not digest.startswith('sha256:')
                        or any(c not in '0123456789abcdef' for c in digest[7:])):
                    raise ValueError('Invalid original Portable Chat TLS CA identity')
            profile_cid = selection['profile_cid']
            if type(profile_cid) is not str or len(profile_cid) != 71:
                raise ValueError('Invalid original Portable Chat profile reference')
            fields: dict[str, object] = {'task': task.handle, 'profile_cid': profile_cid,
                                         'credential_file': credential_file,
                                         'runtime_artifact_cid': 'sha256:' + image_sha256}
            if tls_ca is not None:
                fields['tls_ca'] = tls_ca
            for role, name in _PORTABLE_CHAT_FILES.items():
                fields[role] = self._fill(self._read(root, name, maximum)).handle
            if execution_file is not None:
                fields['execution'] = self._fill(self._read(root, execution_file, maximum)).handle
                fields['attempt'] = selection['attempt']
                fields['egress'] = selection['egress']
            if 'source_catalog' in selection:
                catalog = selection['source_catalog']
                if execution_file is None or type(catalog) is not dict or set(catalog) != {'file', 'sha256'}:
                    raise ValueError('Invalid protected Local Source catalog locator')
                name, digest = catalog['file'], catalog['sha256']
                LocalFileRoot._name(name)
                if (name in (*original_files, credential_file, execution_file,
                             None if tls_ca is None else tls_ca['file'])
                        or type(digest) is not str or len(digest) != 71 or not digest.startswith('sha256:')
                        or any(c not in '0123456789abcdef' for c in digest[7:])):
                    raise ValueError('Invalid protected Local Source catalog identity')
                policy_limit = 8192
                self._workspaces.append(self._reserve(lambda: self._core.reserve_workspace(
                    8 * policy_limit, stopped=lambda: True, cleanup=lambda: True)))
                policy = self._read(root, name, policy_limit)
                if 'sha256:' + sha256(policy).hexdigest() != digest:
                    raise ValueError('Protected Local Source catalog original changed')
                fields['source_catalog'] = {'input': self._fill(policy).handle, 'sha256': digest}
            def prepare(current: _Output) -> None:
                fields['current'] = current.handle
                descriptor = self._copy(fields)
                output = self._reserve(lambda: self._core.reserve_original_metadata(
                    descriptor, 13, cleanup=lambda: True))
                self._portable_chat_output = output
                self._core.produce_original_metadata(output, current=current)

            binding.inspect(prepare)
            assert self._portable_chat_output is not None
            # Core checked this exact name against the retained provider
            # configuration's credential_ref. No credential file was read.
            self._portable_chat_credential = (self._portable_chat_output, credential_file)
            if tls_ca is not None:
                self._portable_chat_ca = (tls_ca['file'], tls_ca['sha256'])
            return self._portable_chat_output

    def _read_portable_model_credential(
            self, work: 'OriginalLocalWork', *,
            model_trust: _OriginalFileReader | None = None) -> bytes:
        """Read the admitted file within the entered Call's current reader."""
        from ._local_model_http import _MODEL_HTTP_CREDENTIAL_BYTES
        with self._core._borrow_work_operation(work) as retained:
            selected = self._portable_chat_credential
            root = self._portable_chat_root
            child = self._portable_crypto
            binding = self.binding
            current = binding._current
            observed = binding._observed_reader
            if (not retained or selected is None or selected[0] is not self._portable_chat_output
                    or root is None or child is None or child._work is not work
                    or child._closing or not child._has_custody or current is None):
                raise ValueError('Original Portable Chat credential is unavailable')
            child._require_worker()
            self._core._owned_output(selected[0], 'original')
            binding._require_observation_frame(self._core, current, observed)
            first = len(self._readers)

            def retire() -> None:
                if len(self._readers) == first:
                    return
                reader_root, reader = self._readers[first]
                if (len(self._readers) != first + 1 or reader_root is not root
                        or reader.name != selected[1] or not root.close_original(reader)):
                    raise ValueError('Original Portable Chat credential reader cleanup remains pending')
                self._readers.pop()

            try:
                credential = self._read(root, selected[1], _MODEL_HTTP_CREDENTIAL_BYTES,
                                        model_trust=model_trust)
            except BaseException as primary:
                try:
                    retire()
                except BaseException as cleanup:
                    raise primary from cleanup
                raise
            retire()
            binding._require_observation_frame(self._core, current, observed)
            return credential

    def _with_portable_model_trust_body(
            self, work: 'OriginalLocalWork', configuration: _Output,
            transfer: '_OriginalModelHttpRawTransfer', name: str, expected_digest: str,
            maximum: int, use: Callable[[str], None]) -> None:
        """Borrow the selected bounded CA body on the same original worker.

        The caller supplies the same admitted staged-Entry trust selection
        and its already-funded bound. The CA filepath is never passed to SSL.
        """
        LocalFileRoot._name(name)
        if (type(expected_digest) is not str or len(expected_digest) != 71
                or not expected_digest.startswith('sha256:')
                or any(c not in '0123456789abcdef' for c in expected_digest[7:])
                or type(maximum) is not int or not 0 < maximum <= 65536
                or not callable(use)):
            raise ValueError('Invalid protected Model trust material')
        with self._core._borrow_work_operation(work) as retained:
            selected = self._portable_chat_credential
            root = self._portable_chat_root
            child = self._portable_crypto
            binding = self.binding
            current = binding._current
            observed = binding._observed_reader
            if (not retained or selected is None or selected[0] is not configuration
                    or configuration is not self._portable_chat_output or root is None
                    or self._portable_chat_ca != (name, expected_digest)
                    or child is None or child._work is not work or child._closing
                    or not child._has_custody or current is None
                    or transfer._core is not self._core or transfer._work is not work
                    or transfer._trust_workspace is None or transfer._trust_reader is not None
                    or transfer._invoked or transfer._closing):
                raise ValueError('Original Portable Chat trust is unavailable')
            transfer._nominal()
            child._require_worker()
            self._core._owned_output(configuration, 'original')
            binding._require_observation_frame(self._core, current, observed)

            try:
                reader = root.open_original(name, max_bytes=maximum)
            except LocalOriginalAcquisitionError as failure:
                transfer._trust_reader = failure.original_reader
                raise
            # The original transfer also owns a partial acquisition, before
            # any read, SSL load or later current check can throw.
            transfer._trust_reader = reader
            material = bytearray()
            try:
                root._require_distinct_model_trust_original(reader, selected[1])
                while True:
                    chunk = root.read_original(reader)
                    material.extend(chunk.data)
                    eof = chunk.eof
                    root.release_original_chunk(reader, chunk)
                    del chunk
                    if eof:
                        break
                snapshot = root.observe_original(reader)
                if snapshot.physical_digest != expected_digest or not material.isascii() or not material:
                    raise ValueError('Original Portable Chat trust bytes changed or were invalid')
                pem = material.decode('ascii')
                material.clear()
                try:
                    if use(pem) is not None:
                        raise ValueError('Invalid Portable Chat trust consumer')
                finally:
                    del pem
                root._require_distinct_model_trust_original(reader, selected[1])
                root.observe_original(reader)
                binding._require_observation_frame(self._core, current, observed)
            finally:
                material.clear()

    def _begin_model_evidence_crypto(self, work: 'OriginalLocalWork',
                                     plaintext_limit: int) -> '_OriginalModelEvidenceCrypto':
        """Acquire the selected physical child before enabling Model egress."""
        with self._core._borrow_work_operation(work) as retained:
            selected = self._portable_chat_output
            policy = self._portable_crypto_policy
            if (not retained or selected is None or policy is None
                    or self._portable_crypto is not None):
                raise ValueError('Original Portable Chat Raw crypto is unavailable')
            self.binding._physical_current()
            self._core._owned_output(selected, 'original')
            from ._local_model_crypto import _OriginalModelEvidenceCrypto
            child = _OriginalModelEvidenceCrypto(
                self._core, work, policy=policy, plaintext_limit=plaintext_limit)
            child._require_worker()
            # Preserve initial refusal/partial custody for the same worker's
            # retirement. No second component or environment fallback exists.
            self._portable_crypto = child
            child.begin()
            self.binding._physical_current()
            return child

    def _save_model_raw_capture(
            self, work: 'OriginalLocalWork', scope: str, holding: str, attempt: str,
            entry: ByteFence, envelope: bytes, *,
            inspect: Callable[[_Output], None],
            confirm: Callable[[_Output, StoredBytes], None]) -> _ModelRawFence:
        """Write this Call's opaque Core-encoded envelope in the original Store."""
        with self._core._borrow_work_operation(work) as retained:
            child = self._portable_crypto
            store = self._store
            if (not retained or store is None or child is None or child._work is not work
                    or child._closing or not child._has_custody):
                raise ValueError('Original Model Raw Store operation is unavailable')
            child._require_worker()
            binding = self.binding
            with binding.fenced() as fences:
                saved = store._save_model_raw_inspected(
                    scope, holding, attempt, entry, envelope, fences,
                    inspect=lambda reader: binding.inspect_reader(reader, inspect),
                    confirm=lambda reader, actual: binding.inspect_reader(
                        reader, lambda current: confirm(current, actual)),
                    current=binding._current_observer)
                if saved is None:
                    raise LocalStorageError('Original Local Model Raw write was not confirmed')
                return saved

    def _close_model_evidence_crypto(self, work: 'OriginalLocalWork') -> bool:
        with self._core._lock:
            child = self._portable_crypto
            if child is None:
                return True
            if child._work is not work or not child.close():
                return False
            self._portable_crypto = None
            return True

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
            if self._portable_crypto is not None:
                return False
            if self._portable_chat_output is not None:
                if not self._core._closed and not self._core.close_original_metadata(self._portable_chat_output):
                    return False
                self._portable_chat_output = None
                self._portable_chat_credential = None
                self._portable_chat_ca = None
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
