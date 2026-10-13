"""Type-only facade consumer; verification performs no I/O or execution."""
from actql import AsyncClient, Client, Execution, AsyncExecution, JSONValue
from actql_sdk import Client as SDKClient, AsyncClient as SDKAsyncClient


def same_sync_client(client: Client) -> SDKClient:
    return client


def same_async_client(client: AsyncClient) -> SDKAsyncClient:
    return client


def result_shape(run: Execution) -> list[dict[str, JSONValue]]:
    return run.result('answer').all(max_rows=1)


async def async_result_shape(run: AsyncExecution) -> list[dict[str, JSONValue]]:
    return await run.result('answer').all(max_rows=1)
