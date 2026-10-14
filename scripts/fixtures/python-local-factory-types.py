"""Type-only standard/SDK factory consumers; no construction or dispatch here."""
from actql import AsyncClient, Client, JSONValue
from actql_sdk import AsyncClient as SDKAsyncClient, Client as SDKClient


async def standard_async() -> list[dict[str, JSONValue]]:
    async with await AsyncClient.open() as client:
        run = await client.start_source('SELECT 1 AS n', format='sql',
                                        submission_ref=client.new_submission())
        await run.wait()
        return await run.result('answer').all(max_rows=1)


def standard_sync() -> list[dict[str, JSONValue]]:
    with Client.open() as client:
        run = client.start_source('SELECT 1 AS n', format='sql',
                                  submission_ref=client.new_submission())
        run.wait()
        return run.result('answer').all(max_rows=1)


def rejected_local_options() -> None:
    SDKClient.open(resources={})  # type: ignore[call-arg]
    SDKClient.open(token='remote-token')  # type: ignore[call-arg]
    SDKClient.open(module='/private/module.wasm')  # type: ignore[call-arg]


async def sdk_remote(endpoint: str, token: str) -> None:
    async with await SDKAsyncClient.connect(endpoint, token):
        pass
