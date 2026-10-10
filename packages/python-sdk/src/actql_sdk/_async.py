"""Remote HTTP transport and handles for facts owned by the existing Host."""
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
from ._errors import ClientError
from ._values import Observation, content_cid, decode_json, freeze, snapshot, thaw, wire_bytes
from ._diagnostics import bind_check, retain_submission_check
from ._checkpoints import capture_signer, signed_answer, review_bytes_match_cid

_submission_inputs = weakref.WeakKeyDictionary()
_MISSING = object()


def get_submission_input(result):
    from ._sync import Execution
    if isinstance(result, Execution):
        result = result._execution
    return _submission_inputs.get(result) if isinstance(result, (ClientError, AsyncExecution)) else None


class _ExchangeFailure(ClientError):
    def __init__(self, code, sent):
        super().__init__(code)
        self.sent = sent


class AsyncClient:
    """Use connect() to negotiate an existing HTTPS Host, then explicitly close."""
    def __init__(self, endpoint, token, *, workspace_id=None, durability='durable',
                 verify=True, timeout=30.0, transport=None):
        parsed = urlsplit(endpoint)
        if (parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None
                or parsed.password is not None or parsed.query or parsed.fragment):
            raise ClientError('InvalidConnectionEndpoint')
        if verify is False or not isinstance(verify, (bool, ssl.SSLContext)):
            raise ClientError('InvalidConnectionTrust')
        if not callable(token) and not self._valid_token(token):
            raise ClientError('InvalidConnectionToken')
        selected = {'mode': 'remote', 'owner': 'remote', 'durability': durability, 'consentRefs': [], 'runners': []}
        if workspace_id is not None:
            selected['workspaceId'] = workspace_id
        if not wire.valid(selected, 'connection'):
            raise ClientError('InvalidConnectionOptions')
        self._endpoint = endpoint if endpoint.endswith('/') else endpoint + '/'
        self._token = token
        self._selected = freeze(snapshot(selected))
        self._http = httpx.AsyncClient(verify=verify, timeout=timeout, follow_redirects=False,
                                      trust_env=False, transport=transport)
        self._profile = None
        self._closed = False
        self._readers = set()

    @staticmethod
    def _valid_token(token):
        return type(token) is str and bool(token) and re.search(r'[\x00-\x20\x7f]', token) is None

    @classmethod
    async def connect(cls, endpoint, token, **options):
        client = cls(endpoint, token, **options)
        try:
            profile = await client._request('connect', {})
            if not wire.negotiated(profile, 'profile', thaw(client._selected)):
                raise ClientError('InvalidHostProfile')
            client._profile = freeze(profile)
            return client
        except BaseException:
            await client.aclose()
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
        # Failed resources remain owned for an explicit retry. This never cancels a Run.
        for reader in tuple(self._readers):
            await reader.aclose()
        await self._http.aclose()

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
        try:
            credential = self._token() if callable(self._token) else self._token
            if inspect.isawaitable(credential):
                credential = await credential
        except asyncio.CancelledError:
            raise
        except Exception:
            raise _ExchangeFailure('ClientCredentialUnavailable', False) from None
        if not self._valid_token(credential):
            raise _ExchangeFailure('InvalidConnectionToken', False)
        request = self._http.build_request('POST', urljoin(self._endpoint, 'actql/client/0.1/' + operation),
            headers={'authorization': 'Bearer ' + credential, 'content-type': 'application/json'}, content=payload)
        try:
            response = await self._http.send(request, stream=True)
        except asyncio.CancelledError:
            raise
        except Exception:
            raise _ExchangeFailure('ClientTransportUnknown', True) from None
        if not 200 <= response.status_code < 300:
            code = 'HostHTTP' + str(response.status_code)
            try:
                reply = await self._json(response)
                if type(reply) is dict and type(reply.get('code')) is str and re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{0,79}', reply['code']):
                    code = reply['code']
            except ClientError:
                pass
            finally:
                await response.aclose()
            raise _ExchangeFailure(code, True)
        return response

    @staticmethod
    async def _json(response, max_bytes=1048576):
        raw = bytearray()
        try:
            async for chunk in response.aiter_bytes(chunk_size=16384):
                if len(raw) + len(chunk) > max_bytes:
                    raise ClientError('HostResponseTooLarge')
                raw.extend(chunk)
            return decode_json(bytes(raw))
        except ClientError:
            raise
        except Exception:
            raise ClientError('InvalidHostResponse') from None

    async def _request(self, operation, body, max_bytes=1048576):
        response = await self._open(operation, body)
        try:
            return await self._json(response, max_bytes)
        finally:
            await response.aclose()

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

    def start(self, program, *, submission_ref, parameters=None, attempt_id=None):
        return self._prepare_start('program', program, submission_ref, parameters, attempt_id)

    def start_source(self, text, *, format, submission_ref, parameters=None, parameter_declarations=_MISSING, attempt_id=None):
        item = {'text': text, 'format': format}
        if parameter_declarations is not _MISSING:
            item['parameterDeclarations'] = parameter_declarations
        return self._prepare_start('aql', item, submission_ref, parameters, attempt_id)

    def _prepare_start(self, kind, input, reference, parameters, attempt_id):
        body = snapshot({'kind': kind, 'input': input, 'submissionRef': thaw(reference), 'parameters': parameters,
                         'attemptRef': {'operation': 'submit', 'attemptId': str(uuid.uuid4()) if attempt_id is None else attempt_id}})
        body['intentCid'] = content_cid({'version': 'actql-submitted-intent/0.1',
                                      'intent': {key: body[key] for key in ('kind', 'input', 'parameters')}}, data_keys=True)
        self._body('submit-intent', body)
        return self._start(body)

    async def _start(self, body):
        context = {'submission_ref': freeze(body['submissionRef']), 'attempt_ref': freeze(body['attemptRef'])}
        try:
            value = await self._request('submit-intent', body)
            if not wire.submission_attempt(value, thaw(self._selected), body):
                raise ClientError('InvalidHostSubmissionOutcome')
            if 'outcome' not in value:
                result = ClientError('SubmissionRefused' if value['kind'] == 'refused' else 'SubmissionConflict',
                                     outcome=Observation(value), **context)
            else:
                outcome = value['outcome']
                if outcome['kind'] == 'ready':
                    result = AsyncExecution(self, outcome['admission'], Observation(outcome))
                else:
                    code = {'held': 'RequestHeld', 'not_accepted': 'SubmissionNotAccepted',
                            'preparation_failed': 'SubmissionPreparationFailed', 'preparing': 'SubmissionPreparing'}[outcome['kind']]
                    result = ClientError(code, outcome=Observation({key: child for key, child in outcome.items() if key != 'checkObservation'}), **context)
                    if 'checkObservation' in outcome:
                        retain_submission_check(result, outcome['checkObservation'], body)
        except asyncio.CancelledError as error:
            error.submission_ref, error.attempt_ref = context['submission_ref'], context['attempt_ref']
            raise
        except ClientError as failure:
            result = ClientError('SubmissionNotSent' if isinstance(failure, _ExchangeFailure) and not failure.sent else 'SubmissionUnknown', **context)
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
        value = await self._request('checkpoints', {'after': after, 'limit': limit})
        if (type(value) is not dict or not {'items'} <= value.keys() <= {'items', 'next'}
                or type(value['items']) is not list or len(value['items']) > limit
                or not all(wire.valid(item, 'checkpoint_summary') for item in value['items'])
                or len({item['checkpointCid'] for item in value['items']}) != len(value['items'])
                or 'next' in value and not wire.bounded_text(value['next'], 512)):
            raise ClientError('InvalidHostCheckpointPage')
        return Observation(value)

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
            signer = capture_signer(signer)
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
        if not wire.valid(value, 'run_state'):
            raise ClientError('InvalidHostRunState')
        control = value.get('control')
        if control is not None:
            previous = self._latest_control
            if previous is not None and (control['revision'] < previous['revision'] or
                    control['revision'] == previous['revision'] and control != previous):
                raise ClientError('StaleHostRunObservation')
            self._latest_control = snapshot(control)
        return Observation(value)

    async def status(self):
        return await self._observe('status')

    async def wait(self, *, until=None):
        return await self._observe('wait', until=until)

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
