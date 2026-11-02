"""A private Runner facade over the same async handles and wire semantics."""
import asyncio
from ._async import AsyncClient, _MISSING
from ._errors import ClientError
from ._connection import NO_TOKEN as _NO_TOKEN
from ._query import _OriginalQueryHandle


def _outside_loop():
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return
    raise ClientError('SyncClientInRunningEventLoop')


class Client:
    def __init__(self, runner, client):
        self._runner, self._client = runner, client
        self._closed = False

    @classmethod
    def open(cls, *, state_dir=None, signer=None):
        """Use the same installed Local factory; never nest an application loop."""
        _outside_loop()
        runner = asyncio.Runner()
        try:
            options = {} if state_dir is None else {'state_dir': state_dir}
            client = runner.run(AsyncClient.open(signer=signer, **options))
        except BaseException as failure:
            cleanup_client = getattr(failure, 'cleanup_client', None)
            if isinstance(failure, ClientError) and isinstance(cleanup_client, AsyncClient):
                failure.cleanup_client = cls(runner, cleanup_client)
            else:
                runner.close()
            raise
        return cls(runner, client)

    @classmethod
    def connect(cls, endpoint=_MISSING, token=_NO_TOKEN, **options):
        _outside_loop()
        runner = asyncio.Runner()
        try:
            client = runner.run(AsyncClient.connect(endpoint, token, **options))
        except BaseException as failure:
            cleanup_client = getattr(failure, 'cleanup_client', None)
            if isinstance(failure, ClientError) and isinstance(cleanup_client, AsyncClient):
                # The unfinished async cleanup still needs its original loop.
                failure.cleanup_client = cls(runner, cleanup_client)
            else:
                runner.close()
            raise
        return cls(runner, client)

    @property
    def profile(self):
        return self._client.profile

    def _call(self, method, *args, **kwargs):
        _outside_loop()
        if self._closed:
            raise ClientError('ClientClosed')
        return self._runner.run(method(*args, **kwargs))

    def __enter__(self):
        _outside_loop()
        if self._closed:
            raise ClientError('ClientClosed')
        return self

    def __exit__(self, *exc):
        self.close()

    def close(self):
        _outside_loop()
        if self._closed:
            return
        self._runner.run(self._client.aclose())
        self._runner.close()
        self._closed = True

    def new_submission(self, **options):
        _outside_loop()
        if self._closed:
            raise ClientError('ClientClosed')
        return self._client.new_submission(**options)

    def start(self, program, **options):
        return Execution(self, self._call(self._client.start, program, **options))

    def start_source(self, text, **options):
        return Execution(self, self._call(self._client.start_source, text, **options))

    def sql(self, text, parameters=None, **options):
        _outside_loop()
        if self._closed:
            raise ClientError('ClientClosed')
        return Query(self, self._client.sql(text, parameters, **options))

    def aql(self, text, parameters=None, **options):
        _outside_loop()
        if self._closed:
            raise ClientError('ClientClosed')
        return Query(self, self._client.aql(text, parameters, **options))

    def check(self, input, **options):
        return self._call(self._client.check, input, **options)

    def lookup_submission(self, reference):
        return self._call(self._client.lookup_submission, reference)

    def attach(self, reference):
        return Execution(self, self._call(self._client.attach, reference))

    def checkpoints(self, **options):
        return self._call(self._client.checkpoints, **options)

    def review_checkpoint(self, checkpoint, **options):
        return self._call(self._client.review_checkpoint, checkpoint, **options)

    def resolve_checkpoints(self, items, **options):
        return self._call(self._client.resolve_checkpoints, items, **options)

    def approve(self, checkpoint_id):
        return self._call(self._client.approve, checkpoint_id)

    def reject(self, checkpoint_id):
        return self._call(self._client.reject, checkpoint_id)


class Query(_OriginalQueryHandle):
    """A synchronous view of the same lazy submission and Result readers."""
    def __init__(self, client, query):
        self._client, self._query = client, query

    @property
    def execution(self):
        original = self._query.execution
        return None if original is None else Execution(self._client, original)

    def all(self, **options):
        return self._client._call(self._query.all, **options)

    def rows(self, **options):
        _outside_loop()
        return QueryReader(self._client, self._query.rows(**options))


class Execution:
    def __init__(self, client, execution):
        self._client, self._execution = client, execution

    @property
    def ref(self):
        return self._execution.ref

    @property
    def submission(self):
        return self._execution.submission

    def status(self):
        return self._client._call(self._execution.status)

    def wait(self, **options):
        return self._client._call(self._execution.wait, **options)

    def reconcile(self):
        return self._client._call(self._execution.reconcile)

    def cancel(self, **options):
        return self._client._call(self._execution.cancel, **options)

    def lookup_cancellation(self, reference):
        return self._client._call(self._execution.lookup_cancellation, reference)

    def result(self, name):
        _outside_loop()
        return Result(self._client, self._execution.result(name))


class Result:
    def __init__(self, client, result):
        self._client, self._result = client, result

    def rows(self, **options):
        _outside_loop()
        return Reader(self._client, self._result.rows(**options))

    def all(self, **options):
        return self._client._call(self._result.all, **options)

    def delivery_attempt(self, attempt_id):
        return self._client._call(self._result.delivery_attempt, attempt_id)


class Reader:
    def __init__(self, client, reader):
        self._client, self._reader = client, reader

    @property
    def attempt_id(self):
        return self._reader.attempt_id

    @property
    def rows_yielded(self):
        return self._reader.rows_yielded

    def __enter__(self):
        self._client._call(self._reader.__aenter__)
        return self

    def __exit__(self, *exc):
        self.close()

    def __iter__(self):
        _outside_loop()
        return self

    def __next__(self):
        try:
            return self._client._call(self._reader.__anext__)
        except StopAsyncIteration:
            raise StopIteration from None

    def close(self):
        _outside_loop()
        if self._reader._closed and self._reader._response is None:
            return
        self._client._call(self._reader.aclose)

    def delivery_attempt(self):
        return self._client._call(self._reader.delivery_attempt)


class QueryReader(Reader, _OriginalQueryHandle):
    """Use the existing Runner for a deferred original Result reader."""
    def close(self):
        _outside_loop()
        if not self._client._closed:
            self._client._call(self._reader.aclose)
