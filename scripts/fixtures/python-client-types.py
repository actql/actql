"""Type-check only; these examples must never dispatch during verification."""
from actql_sdk import AsyncClient, Client, ClientError, JSONValue
from actql_sdk._types import Cancellation, CancellationRef


def cancellation_dto_shapes() -> Cancellation:
    operation: CancellationRef = {'namespaceId': 'local', 'authorityScopeCid': 'scope',
        'runDefinitionCid': 'run', 'cancelId': 'cancel', 'expectedRevision': 1}
    missing_operation_identity: CancellationRef = {  # type: ignore[typeddict-item]
        'namespaceId': 'local', 'authorityScopeCid': 'scope', 'runDefinitionCid': 'run'}
    return {'kind': 'accepted', 'revision': 2, 'cancelRef': operation,
        'ref': {'namespaceId': 'local', 'authorityScopeCid': 'scope', 'runDefinitionCid': 'run'}}


async def original_operation_lookup(client: AsyncClient, error: ClientError) -> None:
    if error.code == 'SubmissionUnknown' and error.submission_ref is not None:
        await client.lookup_submission(error.submission_ref)
    if error.cleanup_client is not None:
        if isinstance(error.cleanup_client, AsyncClient):
            await error.cleanup_client.aclose()
        else:
            error.cleanup_client.close()


def rejected_check_call_shapes(client: Client) -> None:
    # Strict mypy also rejects an unused ignore, so broadening the public
    # overloads to accept these invalid requests fails this consumer check.
    client.check({}, kind='program')  # type: ignore[call-overload]
    client.check({}, kind='program', scope='template_only', parameters={})  # type: ignore[call-overload]
    client.check('SELECT 1 AS n', kind='text', scope='bound_input')  # type: ignore[call-overload]


async def async_example(endpoint: str, token: str) -> list[dict[str, JSONValue]]:
    async with await AsyncClient.connect(endpoint, token) as client:
        check = await client.check('SELECT 1 AS n', kind='text', scope='bound_input', format='sql')
        assert check.to_dict()['version'] == 'actql-check-outcome/0.1'
        await client.check({}, kind='program', scope='template_only')
        reference = client.new_submission()
        run = await client.start_source('SELECT 1 AS n', format='sql', submission_ref=reference)
        await run.wait()
        async with run.result('answer').rows() as reader:
            async for row in reader:
                assert isinstance(row, dict)
        return await run.result('answer').all(max_rows=10)


def sync_example(endpoint: str, token: str) -> list[dict[str, JSONValue]]:
    with Client.connect(endpoint, token) as client:
        client.check('SELECT 1 AS n', kind='text', scope='template_only', format='sql')
        client.check({}, kind='program', scope='bound_input', parameters={})
        run = client.start({}, submission_ref=client.new_submission())
        run.wait()
        with run.result('answer').rows() as reader:
            for row in reader:
                assert isinstance(row, dict)
        return run.result('answer').all(max_rows=10)
