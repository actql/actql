"""Strict public configured-signer and exact-ID convenience callers; no I/O."""
from actql_sdk import AsyncClient, Client, Signer


def sync(endpoint: str, token: str, signer: Signer) -> None:
    with Client.connect(endpoint, token, signer=signer) as client:
        client.approve('original-id')
        client.reject('original-id')
        client.approve(None)  # type: ignore[arg-type]
        client.reject({})  # type: ignore[arg-type]
    Client.open(signer=signer)
    Client.connect(endpoint, token, signer=True)  # type: ignore[arg-type]


async def asynchronous(endpoint: str, token: str, signer: Signer) -> None:
    async with await AsyncClient.connect(endpoint, token, signer=signer) as client:
        await client.approve('original-id')
        await client.reject('original-id')
        await client.approve(None)  # type: ignore[arg-type]
        await client.reject({})  # type: ignore[arg-type]
    await AsyncClient.open(signer=signer)
    await AsyncClient.connect(endpoint, token, signer=True)  # type: ignore[arg-type]
