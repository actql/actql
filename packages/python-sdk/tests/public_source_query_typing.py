"""Strict lazy-query public consumers; no execution or installed-product claim."""
from typing import assert_type
from pydantic import BaseModel
from actql_sdk import AsyncClient, Client, AsyncQuery, Query, AsyncQueryReader, QueryReader
from actql_sdk import JSONValue, get_submission_input


class Row(BaseModel):
    n: int


def sync(client: Client) -> None:
    query = client.sql('SELECT @n AS n', {'n': 1})
    assert_type(query, Query)
    assert_type(query.all(schema=Row, max_rows=10), list[Row])
    assert_type(query.all(), list[dict[str, JSONValue]])
    with query.rows(schema=Row) as reader:
        assert_type(reader, QueryReader[Row])
        assert_type(next(reader), Row)
        assert_type(reader.attempt_id, str | None)
    get_submission_input(query)
    client.aql('FROM source', request_id='original', result='answer')
    client.start_source('SELECT 1', format='sql', submission_ref=client.new_submission(), read_only=True)
    client.start_source('SELECT 1', format='sql', submission_ref=client.new_submission(), read_only=False)  # type: ignore[arg-type]
    client.sql('SELECT 1', stop_before='commit')  # type: ignore[call-arg]
    client.sql('SELECT 1', []).all()  # type: ignore[arg-type]
    query.all(schema=object())  # type: ignore[call-overload]


async def asynchronous(client: AsyncClient) -> None:
    query = client.aql('FROM source')
    assert_type(query, AsyncQuery)
    assert_type(await query.all(schema=Row), list[Row])
    assert_type(await query.all(), list[dict[str, JSONValue]])
    async with query.rows(schema=Row) as reader:
        assert_type(reader, AsyncQueryReader[Row])
        assert_type(await anext(reader), Row)
    get_submission_input(query)
    await client.start_source('SELECT 1', format='sql', submission_ref=client.new_submission(), read_only=True)
    await client.start_source('SELECT 1', format='sql', submission_ref=client.new_submission(), read_only=None)  # type: ignore[arg-type]
    query.rows(schema=object())  # type: ignore[call-overload]
