"""Strict public connection consumers; no network or installed runtime claim."""
from typing import assert_type
from actql_sdk import Client, AsyncClient


def sync() -> None:
    assert_type(Client.connect('actql://token:configured@host.example/workspace'), Client)
    assert_type(Client.connect('actql://host.example/workspace', lambda: 'configured'), Client)
    Client.connect('https://host.example/', 'configured', workspace_id='workspace')
    Client.connect('actql://host.example/workspace', None)  # type: ignore[arg-type]


async def asynchronous() -> None:
    async def token() -> str: return 'configured'
    assert_type(await AsyncClient.connect('actql://token:configured@host.example/workspace'), AsyncClient)
    assert_type(await AsyncClient.connect('actql://host.example/workspace', token), AsyncClient)
