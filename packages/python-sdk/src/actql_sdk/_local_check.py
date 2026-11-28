"""Audience-bound Local Check reporting through the existing Common checker.

Only invocation/transport custody lives here. A report is neither a prepared
Program nor an execution, Source disclosure or retry authority.
"""
from __future__ import annotations

from typing import TYPE_CHECKING, Any
import hashlib
import hmac
import json
import secrets

from ._wire_codec import check_outcome
from ._local_core import _Input, _Output
from ._local_installation import _object
from ._values import canonical_bytes, wire_bytes

if TYPE_CHECKING:
    from ._local_product import InstalledLocalHost


class OriginalLocalCheck:
    def __init__(self, host: InstalledLocalHost) -> None:
        self._original = self
        self._host = host
        self._key = secrets.token_bytes(32)
        self._inputs: list[_Input] = []
        self._outputs: list[_Output] = []
        self._project_environment: _Output | None = None
        self._project_environment_ready = False
        self._closing = False

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Local Check')
        self._host._nominal()

    def _mock_environment_original(self, project: _Output, configuration: int) -> _Output:
        return self._project_environment_original(project, configuration, local=False)

    def _project_environment_original(self, project: _Output, configuration: int, *,
                                      local: bool, portable: bool = False) -> _Output:
        host = self._host
        installation = host._active()
        observe = (host._required_local_project_input if local else
                   self._portable_project_original if portable else host._original_project_bootstrap)
        if observe() is not project:
            raise ValueError('Original Local Check project changed')
        if self._project_environment is None:
            base = host._base_check_environment()
            packet: dict[str, object] = {'project': project.handle, 'base': base.handle,
                                        'configuration': configuration}
            if not local and not portable and host._project_runtime_cid is not None:
                original, files = host._project_configuration, host._project_files
                if original is None or files is None:
                    raise ValueError('Original Mock Project installation is unavailable')
                packet['installation'] = {'runtime_bundle_cid': host._project_runtime_cid,
                                          'data_path': str(original.mock_data_path(files, project))}
            source = host._copy(wire_bytes(packet))  # type: ignore[no-untyped-call]
            self._inputs.append(source)
            output = host._reserve(lambda: host._core.reserve_original_metadata(
                source, 7, cleanup=lambda: True))
            self._project_environment = output

            def bind(current: _Output) -> None:
                host._core.produce_original_metadata(output, current=current)

            installation.binding.inspect(bind)
            if observe() is not project:
                raise ValueError('Original Local Check project changed')
            self._project_environment_ready = True
        if not self._project_environment_ready:
            raise ValueError('Original Local Check environment construction is retained')
        return self._project_environment

    def _portable_project_original(self) -> _Output:
        host = self._host
        installation = host._active()
        original = installation._portable_chat_output
        files = host._project_files
        if original is None or files is None:
            raise ValueError('Original Portable Chat Check installation is unavailable')
        host._core._owned_output(original, 'original')
        files.current()
        return original

    def _project(self, kind: int, packet: dict[str, Any]) -> bytes:
        self._nominal()
        if self._closing:
            raise ValueError('Original Local Check is closing')
        host = self._host
        installation = host._active()
        configuration = host._configuration
        if configuration is None:
            raise ValueError('Original Local Check configuration is unavailable')
        local = host._original_local_project_input()
        portable = installation._portable_chat_output is not None
        observe_project = (host._required_local_project_input if local is not None else
                           self._portable_project_original if portable else host._original_project_bootstrap)
        project = observe_project() if host._project_configuration is not None else None
        environment = (host._original_check_environment().handle if project is None else
                       self._project_environment_original(project, configuration.handle,
                           local=local is not None, portable=portable).handle)
        source = host._copy(wire_bytes(packet))  # type: ignore[no-untyped-call]
        self._inputs.append(source)
        output = host._reserve(lambda: host._core.reserve_client_check(
            environment, configuration.handle, source, kind,
            cleanup=lambda: True))
        self._outputs.append(output)
        captured: list[bytes] = []

        def observe(current: _Output) -> None:
            host._core.produce_client_check(output, current)
            captured.append(host._core.read_client_check(output, current))

        installation.binding.inspect(observe)
        if project is not None and observe_project() is not project:
            raise ValueError('Original Local Check project changed')
        if not host._core.close_client_check(output):
            raise RuntimeError('Original Local Check output cleanup is pending')
        self._outputs.remove(output)
        if not host._core.close_input(source):
            raise RuntimeError('Original Local Check input cleanup is pending')
        self._inputs.remove(source)
        host._inputs.remove(source)
        return captured[0]

    def _revision(self, role: str, raw: str) -> str:
        return 'rev:' + hmac.new(self._key,
            ('actql-check-input/0.1\0' + role + '\0' + raw).encode('utf-8'),
            hashlib.sha256).hexdigest()

    def report(self, body: dict[str, Any]) -> bytes:
        self._nominal()
        # The ingress already captured and validated the closed SDK request.
        # Core supplies actual compiler/schema/public profile selections; never
        # include the private Environment CID or hidden Source inventory here.
        metadata = _object(self._project(0, {}), 262144)
        fields = {'compiler', 'checking_context', 'reason_schema_cid',
                  'outcome_schema_cid', 'audience', 'connection'}
        if (set(metadata) not in (fields, fields | {'publication_context'})
                or any(type(value) is not str for value in metadata.values())):
            raise ValueError('Invalid original Local Check context metadata')
        bound = {**metadata, 'version': 'actql-check-context/0.1',
            'disclosure_policy': 'actql-check-disclosure/0.1',
            'projection': 'actql-check-outcome/0.1',
            'scope': body['scope'], 'kind': body['kind'], 'input': body['input'],
            'visible_aliases': [], 'parameters': body.get('parameters')}
        bound['compiler'] = json.loads(metadata['compiler'])
        bound['checking_context'] = json.loads(metadata['checking_context'])
        context = 'ctx:' + hmac.new(self._key,
            canonical_bytes(bound, data_keys=True), hashlib.sha256).hexdigest()  # type: ignore[no-untyped-call]
        kind = body['kind']
        document = (wire_bytes(body['input']).decode('utf-8')  # type: ignore[no-untyped-call]
                    if kind == 'program' else body['input']['text'])
        role = 'program' if kind == 'program' else 'source'
        packet = {'kind': kind, 'scope': body['scope'], 'document': document,
            'format': 'json' if kind == 'program' else body['input']['format'],
            'context': context, 'revision': self._revision(role, document),
            'correlation': 'corr:' + secrets.token_hex(16)}
        documents = [(role, 'structured' if kind == 'program' else 'text',
                      packet['revision'], len(document.encode('utf-8')))]
        declarations = (body['input'].get('parameterDeclarations') if kind == 'text' else None)
        for name, original, original_role in [
            ('declarations', declarations, 'parameter_declarations'),
            ('parameters', body.get('parameters'), 'parameters'),
        ]:
            if original is not None:
                raw = wire_bytes(original).decode('utf-8')  # type: ignore[no-untyped-call]
                packet[name] = raw
                packet[name + '_revision'] = self._revision(original_role, raw)
                documents.append((original_role, 'structured', packet[name + '_revision'],
                                  len(raw.encode('utf-8'))))
        raw = self._project(1, packet)
        value = _object(raw, 1048576)
        if not check_outcome(value):  # type: ignore[no-untyped-call]
            raise ValueError('Invalid original Local Check outcome')
        report = value.get('report', value.get('partial_report'))
        if report is not None:
            actual = [(item['document_id'], item['kind'], item['revision'], item['byte_length'])
                      for item in report['inputs']]
            if (report['context_ref'] != context or report['scope']['kind'] != body['scope']
                    or len(actual) != len(documents) or set(actual) != set(documents)):
                raise ValueError('Foreign original Local Check report')
        if ((value['outcome'] != 'completed'
                 and value.get('correlation_ref') != packet['correlation'])
                or value['reason_schema_cid'] != metadata['reason_schema_cid']
                or value['outcome_schema_cid'] != metadata['outcome_schema_cid']):
            raise ValueError('Foreign original Local Check outcome')
        return raw

    def close(self) -> bool:
        self._nominal()
        self._closing = True
        for output in tuple(reversed(self._outputs)):
            if not self._host._core.close_client_check(output):
                return False
            self._outputs.remove(output)
        if self._project_environment is not None:
            if not self._host._core.close_original_metadata(self._project_environment):
                return False
            self._project_environment = None
            self._project_environment_ready = False
        for source in tuple(reversed(self._inputs)):
            if not self._host._core.close_input(source):
                return False
            self._inputs.remove(source)
            self._host._inputs.remove(source)
        return True
