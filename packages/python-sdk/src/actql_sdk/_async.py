"""Host transports and shared handles for facts owned by the existing Owner."""
import asyncio
import base64
from datetime import datetime, timezone
import inspect
import re
import ssl
import uuid
from urllib.parse import urlsplit, urljoin
import weakref
import httpx
from . import _wire as wire
from ._errors import ClientError, RequestConflict
from ._connection import NO_TOKEN as _NO_TOKEN, remote_connection as _remote_connection, valid_dsn_credential as _valid_dsn_credential
from ._run_state import RunState
from ._values import Observation, content_cid, decode_json, freeze, snapshot, thaw, wire_bytes
from ._diagnostics import bind_check, retain_submission_check
from ._checkpoints import capture_signer, signed_answer, review_bytes_match_cid

_submission_inputs = weakref.WeakKeyDictionary()
_MISSING = object()


def _submission_context(body, original=None):
    context = {'submission_ref': freeze(snapshot(thaw(body['submissionRef'] if original is None else original))),
               'attempt_ref': freeze(snapshot(body['attemptRef']))}
    if 'requestName' in body:
        context['request_id'] = body['requestName']
    return context


def get_submission_input(result):
    from ._sync import Execution, Query
    from ._query import AsyncQuery
    if isinstance(result, Execution):
        result = result._execution
    if isinstance(result, Query):
        result = result._query
    return _submission_inputs.get(result) if isinstance(result, (ClientError, AsyncExecution, AsyncQuery)) else None


class _ExchangeFailure(ClientError):
    def __init__(self, code, sent):
        super().__init__(code)
        self.sent = sent


class _LocalCoreCleanupPort:
    """Forward only the same failed Core's physical cleanup; no operation port."""
    def __init__(self, core):
        self._core = core

    async def aclose(self):
        if not self._core.close():
            raise ClientError('LocalCoreCleanupPending')


class AsyncClient:
    """Use open() for installed Local or connect() for an existing HTTPS Host."""
    def __init__(self, endpoint, token=_NO_TOKEN, *, workspace_id=None, durability='durable',
                 verify=True, timeout=30.0, transport=None, signer=None):
        endpoint, token, workspace_id, self._dsn = _remote_connection(endpoint, token, workspace_id)
        try:
            parsed = urlsplit(endpoint)
        except (ValueError, TypeError, AttributeError):
            raise ClientError('InvalidConnectionEndpoint') from None
        if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None
                or parsed.password is not None or parsed.query or parsed.fragment):
            raise ClientError('InvalidConnectionEndpoint')
        if verify is False or not isinstance(verify, (bool, ssl.SSLContext)):
            raise ClientError('InvalidConnectionTrust')
        self._credential_valid = _valid_dsn_credential if self._dsn else self._valid_token
        if not callable(token) and not self._credential_valid(token):
            raise ClientError('InvalidConnectionToken')
        selected = {'mode': 'remote', 'owner': 'remote', 'durability': durability, 'consentRefs': [], 'runners': []}
        if workspace_id is not None:
            selected['workspaceId'] = workspace_id
        if not wire.valid(selected, 'connection'):
            raise ClientError('InvalidConnectionOptions')
        self._signer = None if signer is None else capture_signer(signer)
        self._endpoint = endpoint if endpoint.endswith('/') else endpoint + '/'
        self._token = token
        self._selected = freeze(snapshot(selected))
        self._transport = transport if transport is not None else httpx.AsyncHTTPTransport(verify=verify)
        self._http = httpx.AsyncClient(timeout=timeout, follow_redirects=False,
                                      trust_env=False, transport=self._transport)
        self._client_cleanup = self._http.aclose
        self._responses = {}
        self._cleanup_lock = asyncio.Lock()
        self._response_cleanup_lock = asyncio.Lock()
        self._profile = None
        self._closed = False
        self._readers = set()
        self._local_host = None

    @staticmethod
    def _valid_token(token):
        return type(token) is str and bool(token) and re.search(r'[\x00-\x20\x7f]', token) is None

    @classmethod
    async def open(cls, *, state_dir=None, signer=None):
        """Open the installed Local product with an optional Store directory.

        The installed runtime acquires its real Core and durable Store through
        the existing factory. Managed limits do not supply a worker, permission
        or a shared native holding. Partial cleanup retains the same Host.
        """
        return await cls._open_installed_local(state_dir=state_dir, signer=signer)

    @classmethod
    async def _open_installed_local(cls, *, state_dir=None, signer=None,
                                    discover_project=False, profile=None):
        selected_signer = None if signer is None else capture_signer(signer)
        from ._local_worker_funding import LocalWorkerFundingUnavailable
        try:
            from ._local_product import InstalledLocalHost, LocalProductCleanupPending
            from ._local_core import LocalCoreInitializationError
            from ._local_distribution import LocalInstallationError
        except Exception as failure:
            raise ClientError('LocalInstallationUnavailable', original_error=failure) from None
        try:
            options = {} if state_dir is None else {'state_dir': state_dir}
            if discover_project:
                options['_discover_project'] = True
                options['_project_profile'] = profile
            host = InstalledLocalHost.installed(**options)
        except LocalProductCleanupPending as failure:
            client = cls._from_local_host(failure.cleanup_host)
            client._closed = True
            raise ClientError('LocalClientInitializationCleanupPending',
                              original_error=failure, cleanup_client=client) from None
        except LocalCoreInitializationError as failure:
            # Core has not returned a Host. Preserve its exact synchronous
            # physical cleanup carrier; no new Host or reconnect is attempted.
            client = cls._from_local_host(_LocalCoreCleanupPort(failure.cleanup_core))
            client._closed = True
            raise ClientError('LocalCoreInitializationCleanupPending',
                              original_error=failure, cleanup_client=client) from None
        except LocalInstallationError as failure:
            raise ClientError('LocalInstallationUnavailable', original_error=failure) from None
        except LocalWorkerFundingUnavailable as failure:
            raise ClientError('LocalExecutionFundingUnavailable', original_error=failure) from None
        return await cls._connect_local(host, signer=selected_signer)

    @classmethod
    async def connect(cls, endpoint=_MISSING, token=_NO_TOKEN, *, mode='remote',
                      installation=_MISSING, **options):
        if mode == 'local':
            if endpoint is not _MISSING or token is not _NO_TOKEN:
                raise ClientError('InvalidConnectionOptions')
            signer = options.pop('signer', None)
            profile = options.pop('profile', None)
            if (options or profile is not None
                    and (type(profile) is not str or len(profile) > 65536)):
                raise ClientError('InvalidConnectionOptions')
            selected = {} if installation is _MISSING else {'state_dir': installation}
            return await cls._open_installed_local(signer=signer, profile=profile,
                                                   discover_project=True, **selected)
        if mode != 'remote' or installation is not _MISSING:
            raise ClientError('InvalidConnectionOptions')
        if endpoint is _MISSING:
            raise ClientError('InvalidConnectionEndpoint')
        client = cls(endpoint, token, **options)
        try:
            profile = await client._request('connect', {})
            if not wire.negotiated(profile, 'profile', thaw(client._selected)):
                raise ClientError('InvalidHostProfile')
            client._profile = freeze(profile)
            return client
        except BaseException as failure:
            try:
                await client.aclose()
            except BaseException as cleanup:
                # connect() has not returned its Client. Keep that same physical
                # cleanup owner reachable rather than orphaning it on failure.
                raise ClientError('ClientConnectionCleanupFailed',
                                  original_error=failure, cleanup_error=cleanup,
                                  cleanup_client=client) from None
            raise

    @classmethod
    def _from_local_host(cls, host, *, signer=None):
        client = cls.__new__(cls)
        client._signer = None if signer is None else capture_signer(signer)
        client._selected = freeze({'mode': 'local', 'owner': 'local',
                                   'durability': 'durable', 'consentRefs': [], 'runners': []})
        client._local_host = host
        client._transport = host
        client._client_cleanup = host.aclose
        client._responses = {}
        client._cleanup_lock = asyncio.Lock()
        client._response_cleanup_lock = asyncio.Lock()
        client._profile = None
        client._closed = False
        client._readers = set()
        return client

    @classmethod
    async def _connect_local(cls, host, *, signer=None):
        """Bind only the installed Host's existing in-process operation port.

        The public factory resolves its installed runtime and original Host
        custody. This private port does not grant execution or create an HTTP
        endpoint/token. All responses use the same closed wire validators.
        """
        client = cls._from_local_host(host, signer=signer)
        try:
            profile = await client._request('connect', {})
            if not wire.negotiated(profile, 'profile', thaw(client._selected)):
                raise ClientError('InvalidHostProfile')
            client._profile = freeze(profile)
            return client
        except BaseException as failure:
            try:
                await client.aclose()
            except BaseException as cleanup:
                raise ClientError('ClientConnectionCleanupFailed', original_error=failure,
                                  cleanup_error=cleanup, cleanup_client=client) from None
            raise

    @property
    def profile(self):
        return self._profile

    async def __aenter__(self):
        if self._closed or self._profile is None:
            raise ClientError('ClientClosed')
        return self

    async def __aexit__(self, *exc):
        await self.aclose()

    async def aclose(self):
        self._closed = True
        try:
            async with self._cleanup_lock:
                await self._release()
        except ClientError as failure:
            self._redact_connection_failure(failure)
            raise

    async def _release(self):
        # Failed resources remain owned for an explicit retry. This never cancels a Run.
        for reader in tuple(self._readers):
            await reader.aclose()
        for response in tuple(self._responses):
            await self._close_response(response)
        if self._client_cleanup is not None:
            try:
                await self._client_cleanup()
            except BaseException as failure:
                self._client_cleanup = self._transport.aclose
                if not isinstance(failure, Exception):
                    raise
                raise ClientError('ClientCleanupFailed') from None
            self._client_cleanup = None
        self._signer = None

    async def _close_response(self, response):
        async with self._response_cleanup_lock:
            await self._release_response(response)

    async def _release_response(self, response):
        close = self._responses.get(response)
        if close is None:
            return
        try:
            await close()
        except BaseException as failure:
            # HTTPX marks a response closed before the stream's close completes.
            # Keep the same physical stream callback for a later explicit retry.
            self._responses[response] = response.stream.aclose
            if not isinstance(failure, Exception):
                raise
            raise ClientError('ClientResponseCleanupFailed') from None
        del self._responses[response]

    @staticmethod
    async def _chunks(response, chunk_size=16384):
        # Request identity encoding so byte budgets account for the actual JSON.
        # Iterating the owned stream avoids an implicit close at EOF.
        if response.is_stream_consumed:
            for start in range(0, len(response.content), chunk_size):
                yield response.content[start:start + chunk_size]
        else:
            async for chunk in response.stream:
                for start in range(0, len(chunk), chunk_size):
                    yield chunk[start:start + chunk_size]

    def _body(self, operation, body):
        if self._closed:
            raise _ExchangeFailure('ClientClosed', False)
        if operation != 'connect' and self._profile is None:
            raise _ExchangeFailure('ClientNotConnected', False)
        captured = snapshot({'connection': thaw(self._selected)} | body)
        if not wire.valid_body(operation, captured):
            raise _ExchangeFailure('InvalidClientRequest', False)
        return captured

    async def _open(self, operation, body):
        captured = self._body(operation, body)
        payload = wire_bytes(captured)
        if self._local_host is not None:
            try:
                response = await self._local_host.open(operation, payload)
            except asyncio.CancelledError:
                raise
            except Exception:
                # The original operation may already be retained. Never infer
                # not-sent, rollback or retry from an in-process exception.
                raise _ExchangeFailure('ClientTransportUnknown', True) from None
            return await self._accept_response(response)
        try:
            credential = self._token() if callable(self._token) else self._token
            if inspect.isawaitable(credential):
                credential = await credential
        except asyncio.CancelledError:
            raise
        except Exception:
            raise _ExchangeFailure('ClientCredentialUnavailable', False) from None
        if not self._credential_valid(credential):
            raise _ExchangeFailure('InvalidConnectionToken', False)
        if self._closed:
            raise _ExchangeFailure('ClientClosed', False)
        request = self._http.build_request('POST', urljoin(self._endpoint, 'actql/client/0.1/' + operation),
            headers={'authorization': ('Bearer ' + credential).encode('latin-1') if self._dsn else 'Bearer ' + credential, 'content-type': 'application/json',
                     'accept-encoding': 'identity'}, content=payload)
        try:
            response = await self._http.send(request, stream=True)
        except asyncio.CancelledError:
            raise
        except Exception:
            raise _ExchangeFailure('ClientTransportUnknown', True) from None
        return await self._accept_response(response)

    async def _accept_response(self, response):
        self._responses[response] = response.aclose
        if self._closed:
            await self._close_response(response)
            raise _ExchangeFailure('ClientClosed', True)
        if response.headers.get('content-encoding', 'identity').lower() != 'identity':
            await self._close_response(response)
            raise _ExchangeFailure('UnsupportedHostContentEncoding', True)
        if not 200 <= response.status_code < 300:
            code = 'HostHTTP' + str(response.status_code)
            try:
                reply = await self._json(response)
                if type(reply) is dict and type(reply.get('code')) is str and re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,79}', reply['code']):
                    code = reply['code']
            except ClientError:
                pass
            finally:
                await self._close_response(response)
            raise _ExchangeFailure(code, True)
        return response

    async def _json(self, response, max_bytes=1048576):
        raw = bytearray()
        try:
            async for chunk in self._chunks(response):
                if len(raw) + len(chunk) > max_bytes:
                    raise ClientError('HostResponseTooLarge')
                raw.extend(chunk)
            return decode_json(bytes(raw))
        except ClientError:
            raise
        except Exception:
            raise ClientError('InvalidHostResponse') from None

    async def _request(self, operation, body, max_bytes=1048576):
        try:
            response = await self._open(operation, body)
            try:
                return await self._json(response, max_bytes)
            finally:
                await self._close_response(response)
        except ClientError as failure:
            self._redact_connection_failure(failure)
            raise

    def _redact_connection_failure(self, failure):
        if not getattr(self, '_dsn', False):
            return
        # Preserve owned outcome/identity/cleanup carriers. A borrowed HTTP,
        # credential or application exception is not safe DSN diagnostic data.
        pending, seen = [failure], set()
        while pending:
            error = pending.pop()
            if id(error) in seen:
                continue
            seen.add(id(error))
            error.__cause__ = error.__context__ = None
            for field in ('original_error', 'cleanup_error', 'validation_error'):
                cause = getattr(error, field, None)
                if cause is None:
                    continue
                if field != 'validation_error' and isinstance(cause, ClientError):
                    pending.append(cause)
                else:
                    setattr(error, field, ClientError('ConnectionDiagnosticUnavailable'))

    def new_submission(self, *, nonce=None):
        if self._closed:
            raise ClientError('ClientClosed')
        epoch = thaw(self._profile.get('submissionEpoch'))
        ref = {'epoch': epoch, 'nonce': str(uuid.uuid4()) if nonce is None else nonce}
        if not wire.submission_ref(ref):
            raise ClientError('SubmissionEpochUnavailable' if epoch is None else 'InvalidSubmissionReference')
        return freeze(ref)

    def check(self, input, *, kind, scope, format=_MISSING, parameter_declarations=_MISSING, **options):
        if set(options) - {'parameters'} or kind not in ('text', 'program') or scope not in ('template_only', 'bound_input'):
            raise ClientError('InvalidCheckRequest')
        if scope == 'template_only' and 'parameters' in options:
            raise ClientError('InvalidCheckRequest')
        if kind == 'program' and (format is not _MISSING or parameter_declarations is not _MISSING):
            raise ClientError('InvalidCheckRequest')
        if kind == 'text' and format is _MISSING:
            raise ClientError('InvalidCheckRequest')
        item = input if kind == 'program' else {'text': input, 'format': format}
        if kind == 'text' and parameter_declarations is not _MISSING:
            item['parameterDeclarations'] = parameter_declarations
        body = {'kind': kind, 'scope': scope, 'input': item}
        if scope == 'bound_input':
            body['parameters'] = options.get('parameters')
        captured = self._body('check', body)
        captured.pop('connection')
        return self._check(captured)

    async def _check(self, body):
        value = await self._request('check', body)
        return bind_check(value, body)

    def start(self, program, *, submission_ref=None, request_id=None, parameters=None, attempt_id=None, stop_before=_MISSING, read_only=_MISSING):
        reference = self._submission_candidate(submission_ref, request_id)
        return self._prepare_start('program', program, reference, parameters, attempt_id, stop_before, read_only,
                                   request_name=_MISSING if request_id is None else request_id)

    def start_source(self, text, *, format, submission_ref=None, request_id=None, parameters=None, parameter_declarations=_MISSING, attempt_id=None, stop_before=_MISSING, read_only=_MISSING):
        item = {'text': text, 'format': format}
        if parameter_declarations is not _MISSING:
            item['parameterDeclarations'] = parameter_declarations
        reference = self._submission_candidate(submission_ref, request_id)
        return self._prepare_start('aql', item, reference, parameters, attempt_id, stop_before, read_only,
                                   request_name=_MISSING if request_id is None else request_id)

    def _submission_candidate(self, reference, request_id):
        if reference is not None and request_id is not None:
            raise ClientError('ConflictingSubmissionIdentity')
        # A fresh candidate is only a proposal to the same Host. The scoped
        # Journal atomically selects an original; the name never becomes an
        # epoch nonce, client cache or permission to repeat preparation.
        return self.new_submission() if reference is None else reference

    def _prepare_start(self, kind, input, reference, parameters, attempt_id, stop_before, read_only=_MISSING, *, request_name=_MISSING):
        return self._start(self._capture_start(kind, input, reference, parameters, attempt_id, stop_before, read_only,
                                              request_name=request_name))

    def _capture_start(self, kind, input, reference, parameters, attempt_id, stop_before, read_only, *, request_name=_MISSING):
        body = snapshot({'kind': kind, 'input': input, 'submissionRef': thaw(reference), 'parameters': parameters,
                         'attemptRef': {'operation': 'submit', 'attemptId': str(uuid.uuid4()) if attempt_id is None else attempt_id}})
        intent = {key: body[key] for key in ('kind', 'input', 'parameters')}
        if stop_before is not _MISSING:
            body['stopBefore'] = intent['stopBefore'] = snapshot(stop_before)
        if read_only is not _MISSING:
            body['readOnly'] = intent['readOnly'] = snapshot(read_only)
        body['intentCid'] = content_cid({'version': 'actql-submitted-intent/0.1',
                                      'intent': intent}, data_keys=True)
        if request_name is not _MISSING:
            body['requestName'] = snapshot(request_name)
        self._body('submit-named-intent' if request_name is not _MISSING else 'submit-intent', body)
        return body

    def sql(self, text, parameters=None, **options):
        return self._source_query('sql', text, parameters, **options)

    def aql(self, text, parameters=None, **options):
        return self._source_query('aql-text', text, parameters, **options)

    def _source_query(self, format, text, parameters, *, submission_ref=None, request_id=None,
                      attempt_id=None, parameter_declarations=_MISSING, result=None):
        from ._query import AsyncQuery
        if result is not None and not wire.bounded_text(result):
            raise ClientError('InvalidResultName')
        if parameters is not None and type(parameters) is not dict:
            raise ClientError('InvalidQueryParameters')
        reference = self._submission_candidate(submission_ref, request_id)
        item = {'text': text, 'format': format}
        if parameter_declarations is not _MISSING:
            item['parameterDeclarations'] = parameter_declarations
        body = self._capture_start('aql', item, reference, parameters, attempt_id, _MISSING, True,
                                   request_name=_MISSING if request_id is None else request_id)
        query = AsyncQuery(self, body, result)
        _submission_inputs[query] = freeze(snapshot(body))
        return query

    async def _start(self, body):
        context = _submission_context(body)
        named = 'requestName' in body
        try:
            value = await self._request('submit-named-intent' if named else 'submit-intent', body)
            if not (wire.named_submission_attempt(value, thaw(self._selected), body) if named
                    else wire.submission_attempt(value, thaw(self._selected), body)):
                raise ClientError('InvalidHostSubmissionOutcome')
            if 'outcome' not in value:
                result = (RequestConflict(outcome=Observation(value), **context)
                          if named and value['kind'] == 'conflict' else
                          ClientError('SubmissionRefused' if value['kind'] == 'refused' else 'SubmissionConflict',
                                      outcome=Observation(value), **context))
            else:
                outcome = value['outcome']
                context = _submission_context(body, outcome['submissionRef'])
                if outcome['kind'] == 'ready':
                    result = AsyncExecution(self, outcome['admission'], Observation(outcome))
                else:
                    code = {'held': 'RequestHeld', 'not_accepted': 'SubmissionNotAccepted',
                            'preparation_failed': 'SubmissionPreparationFailed', 'preparing': 'SubmissionPreparing',
                            'unresolvable': 'SubmissionUnresolvable'}[outcome['kind']]
                    result = ClientError(code, outcome=Observation({key: child for key, child in outcome.items() if key != 'checkObservation'}), **context)
                    if 'checkObservation' in outcome:
                        retain_submission_check(result, outcome['checkObservation'], body)
        except asyncio.CancelledError as error:
            for key, value in context.items():
                setattr(error, key, value)
            raise
        except ClientError as failure:
            result = ClientError('SubmissionNotSent' if isinstance(failure, _ExchangeFailure) and not failure.sent else 'SubmissionUnknown', **context)
            if self._local_host is not None:
                # Retain the same Local failure for diagnosis, never as retry authority.
                result.original_error = failure
        _submission_inputs[result] = freeze(snapshot(body))
        if isinstance(result, ClientError):
            raise result from None
        return result

    def lookup_submission(self, reference):
        captured = snapshot(thaw(reference))
        if not wire.submission_ref(captured):
            raise ClientError('InvalidSubmissionReference')
        return self._lookup_submission(captured)

    async def _lookup_submission(self, reference):
        value = await self._request('lookup-submission', {'submissionRef': reference})
        if not wire.submission_outcome(value, thaw(self._selected), reference, lookup=True):
            raise ClientError('InvalidHostSubmissionLookup')
        return Observation(value)

    def attach(self, reference):
        captured = snapshot(thaw(reference))
        if not wire.valid(captured, 'run_ref'):
            raise ClientError('InvalidRunReference')
        return self._attach(captured)

    async def _attach(self, reference):
        admission = await self._request('attach', {'ref': reference})
        if not wire.negotiated(admission, 'admission', thaw(self._selected)) or admission['ref'] != reference:
            raise ClientError('InvalidHostAdmission')
        return AsyncExecution(self, admission)

    async def checkpoints(self, *, after='', limit=50):
        return await self._checkpoints({'after': after, 'limit': limit})

    async def _checkpoints(self, body):
        value = await self._request('checkpoints', body)
        if (type(value) is not dict or not {'items'} <= value.keys() <= {'items', 'next'}
                or type(value['items']) is not list or len(value['items']) > body['limit']
                or not all(wire.valid(item, 'checkpoint_summary') for item in value['items'])
                or len({item['checkpointCid'] for item in value['items']}) != len(value['items'])
                or 'next' in value and not wire.bounded_text(value['next'], 512)):
            raise ClientError('InvalidHostCheckpointPage')
        if 'checkpointId' in body and ('next' in value or len(value['items']) > 1
                or any(item['checkpointId'] != body['checkpointId'] for item in value['items'])):
            raise ClientError('InvalidHostCheckpointLookup')
        return Observation(value)

    def approve(self, checkpoint_id):
        return self._decide_checkpoint(checkpoint_id, 'approved')

    def reject(self, checkpoint_id):
        return self._decide_checkpoint(checkpoint_id, 'rejected')

    def _decide_checkpoint(self, checkpoint_id, decision):
        if self._closed:
            raise ClientError('ClientClosed')
        body = {'after': '', 'limit': 1, 'checkpointId': checkpoint_id}
        self._body('checkpoints', body)
        signer = capture_signer(self._signer)
        return self._answer_checkpoint(body, decision, signer)

    async def _answer_checkpoint(self, body, decision, signer):
        # The exact original summary comes from the Host/Journal, never an
        # independent Client cache, a fabricated Preview or a paging search.
        page = await self._checkpoints(body)
        if not page['items']:
            raise ClientError('CheckpointNotPending')
        return await self.resolve_checkpoints([{'checkpoint': page['items'][0],
                                                'decision': decision}], signer=signer)

    def review_checkpoint(self, checkpoint, *, max_bytes=65536):
        captured = snapshot(thaw(checkpoint))
        cid = captured if type(captured) is str else captured.get('checkpointCid') if type(captured) is dict else None
        body = {'checkpointCid': cid, 'maxBytes': max_bytes}
        self._body('checkpoint-review', body)
        return self._review_checkpoint(captured, body)

    async def _review_checkpoint(self, checkpoint, body):
        value = await self._request('checkpoint-review', body, 4 * ((body['maxBytes'] + 2) // 3) + 2048)
        if (not wire.valid(value, 'checkpoint_review') or value['checkpointCid'] != body['checkpointCid']
                or value['byteLength'] > body['maxBytes']):
            raise ClientError('InvalidHostCheckpointReview')
        try:
            raw = base64.b64decode(value['contentBase64'], validate=True)
        except ValueError:
            raise ClientError('ReviewIntegrityFailed') from None
        if (base64.b64encode(raw).decode('ascii') != value['contentBase64'] or len(raw) != value['byteLength']
                or not review_bytes_match_cid(raw, value['artifactCid'])
                or type(checkpoint) is dict and checkpoint.get('reviewProjectionCid', value['artifactCid']) != value['artifactCid']):
            raise ClientError('ReviewIntegrityFailed')
        return freeze({'checkpoint_cid': body['checkpointCid'], 'artifact_cid': value['artifactCid'], 'bytes': raw})

    def resolve_checkpoints(self, items, *, signer=None):
        captured = snapshot(thaw(items))
        if type(captured) is not list or not 1 <= len(captured) <= 16:
            raise ClientError('InvalidCheckpointAnswers')
        if any(not wire.valid(item, 'resolve_item') for item in captured):
            signer = capture_signer(self._signer if signer is None else signer)
        decided_at = datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
        return self._resolve_checkpoints(captured, signer, decided_at)

    async def _resolve_checkpoints(self, items, signer, decided_at):
        signed = []
        for item in items:
            if wire.valid(item, 'resolve_item'):
                signed.append(item)
            elif type(item) is dict and set(item) == {'checkpoint', 'decision'}:
                signed.append(await signed_answer(item['checkpoint'], item['decision'], signer, decided_at))
            else:
                raise ClientError('InvalidCheckpointAnswer')
        body = {'items': signed}
        self._body('resolve', body)
        try:
            value = await self._request('resolve', body)
            if (type(value) is not dict or set(value) != {'results'} or type(value['results']) is not list
                    or len(value['results']) != len(signed)
                    or any(not wire.valid(result, 'resolve_result') or result['checkpointCid'] != item['checkpointCid']
                           or (not {'decision', 'resolutionCid'} <= result.keys() if result['status'] in ('committed', 'duplicate')
                               else 'reason' not in result)
                           for result, item in zip(value['results'], signed))):
                raise ClientError('InvalidHostResolveReply')
        except asyncio.CancelledError as error:
            error.signed = freeze(signed)
            raise
        except ClientError as error:
            if isinstance(error, _ExchangeFailure) and not error.sent:
                raise ClientError(error.code, signed=freeze(signed)) from None
            raise ClientError('ResolutionUnknown', signed=freeze(signed)) from None
        return Observation(value | {'signed': signed})


class AsyncExecution:
    def __init__(self, client, admission, submission=None):
        self._client = client
        self._admission = freeze(snapshot(admission))
        self._submission = submission
        self._latest_control = None

    @property
    def ref(self):
        return self._admission['ref']

    @property
    def submission(self):
        return self._submission

    async def _observe(self, operation, **body):
        value = await self._client._request(operation, {'ref': thaw(self.ref)} | body)
        accepted = (wire.valid_run_wait(value, body['since']) if operation == 'wait'
                    else wire.valid(value, 'run_state'))
        if not accepted:
            raise ClientError('InvalidHostRunState')
        control = value.get('control')
        if control is not None:
            previous = self._latest_control
            if previous is not None and (control['revision'] < previous['revision'] or
                    control['revision'] == previous['revision'] and control != previous):
                raise ClientError('StaleHostRunObservation')
            self._latest_control = snapshot(control)
        return RunState(value)

    async def status(self):
        return await self._observe('status')

    async def wait(self, *, until=None, since=None):
        return await self._observe('wait', until=until, since=since)

    async def reconcile(self):
        return await self._observe('reconcile')

    def cancel(self, *, cancel_id=None, expected_revision=None, attempt_id=None):
        if expected_revision is not None and not wire.valid(expected_revision, {'type': 'integer', 'minimum': 0, 'maximum': 2147483647}):
            raise ClientError('InvalidCancellationReference')
        cancel_id = str(uuid.uuid4()) if cancel_id is None else cancel_id
        attempt_id = str(uuid.uuid4()) if attempt_id is None else attempt_id
        if not wire.bounded_text(cancel_id) or not wire.bounded_text(attempt_id):
            raise ClientError('InvalidCancellationReference')
        return self._cancel(cancel_id, expected_revision, attempt_id)

    async def _cancel(self, cancel_id, expected_revision, attempt_id):
        if expected_revision is None:
            state = await self.status()
            if 'control' not in state:
                raise ClientError('CancellationRevisionUnavailable')
            expected_revision = state['control']['revision']
        reference = thaw(self.ref) | {'cancelId': cancel_id, 'expectedRevision': expected_revision}
        attempt = {'operation': 'cancel', 'attemptId': attempt_id}
        try:
            value = await self._client._request('cancel', {'ref': thaw(self.ref), 'cancelId': cancel_id,
                                                 'expectedRevision': expected_revision, 'attemptRef': attempt})
            if not wire.cancellation_attempt(value, reference, attempt):
                raise ClientError('InvalidHostCancellation')
        except asyncio.CancelledError as error:
            error.cancel_ref, error.attempt_ref = freeze(reference), freeze(attempt)
            raise
        except ClientError as error:
            if isinstance(error, _ExchangeFailure) and not error.sent:
                raise ClientError(error.code, cancel_ref=freeze(reference), attempt_ref=freeze(attempt)) from None
            raise ClientError('CancellationUnknown', cancel_ref=freeze(reference), attempt_ref=freeze(attempt)) from None
        return Observation(value)

    def lookup_cancellation(self, reference):
        captured = snapshot(thaw(reference))
        if not wire.valid(captured, 'cancellation_ref') or any(captured[key] != value for key, value in self.ref.items()):
            raise ClientError('InvalidCancellationReference')
        return self._lookup_cancellation(captured)

    async def _lookup_cancellation(self, reference):
        value = await self._client._request('lookup-cancellation', {'ref': thaw(self.ref), 'cancelId': reference['cancelId'],
                                                                 'expectedRevision': reference['expectedRevision']})
        if not wire.cancellation_lookup(value, reference):
            raise ClientError('InvalidHostCancellationLookup')
        return Observation(value)

    def result(self, name):
        from ._reader import AsyncResult
        if not wire.bounded_text(name):
            raise ClientError('InvalidResultName')
        return AsyncResult(self, name)
