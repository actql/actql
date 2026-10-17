"""Strict public names and original explicit-epoch callers, without I/O."""
from typing import assert_type
from actql_sdk import AsyncClient, Client, ClientError, RequestConflict, AsyncExecution, Execution


def sync(client: Client) -> None:
    assert_type(client.start_source('SELECT 1', format='sql', request_id='original'), Execution)
    assert_type(client.start({}, request_id='original'), Execution)
    client.start_source('SELECT 1', format='sql', submission_ref=client.new_submission())
    client.start_source('SELECT 1', format='sql')
    client.start_source('SELECT 1', format='sql', request_id=1)  # type: ignore[arg-type]
    client.sql('SELECT 1', request_id='original')


async def asynchronous(client: AsyncClient) -> None:
    assert_type(await client.start_source('SELECT 1', format='sql', request_id='original'), AsyncExecution)
    assert_type(await client.start({}, request_id='original'), AsyncExecution)
    await client.start_source('SELECT 1', format='sql', submission_ref=client.new_submission())
    await client.start_source('SELECT 1', format='sql')


def conflict(error: RequestConflict) -> ClientError:
    assert_type(error.request_id, str | None)
    assert_type(error.code, str)
    return error
