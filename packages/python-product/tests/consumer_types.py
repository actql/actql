"""Type-only facade consumer; verification performs no I/O or execution."""
from actql import (AsyncClient, Client, Execution, AsyncExecution, JSONValue,
                   CheckObservation, CheckReport, CheckReason)
from actql_sdk import (Client as SDKClient, AsyncClient as SDKAsyncClient,
                       CheckObservation as SDKCheckObservation,
                       CheckReport as SDKCheckReport, CheckReason as SDKCheckReason)


def same_sync_client(client: Client) -> SDKClient:
    return client


def same_async_client(client: AsyncClient) -> SDKAsyncClient:
    return client


def result_shape(run: Execution) -> list[dict[str, JSONValue]]:
    return run.result('answer').all(max_rows=1)


async def async_result_shape(run: AsyncExecution) -> list[dict[str, JSONValue]]:
    return await run.result('answer').all(max_rows=1)


def same_check_observation(value: CheckObservation) -> SDKCheckObservation:
    return value


def same_check_report(value: CheckReport) -> SDKCheckReport:
    return value


def same_check_reason(value: CheckReason) -> SDKCheckReason:
    return value
