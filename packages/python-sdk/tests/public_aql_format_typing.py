from actql_sdk import AsyncClient, Client

def sync_calls(client: Client) -> None:
    client.start_source('SELECT 1 AS id', format='aql', submission_ref={})
    client.check('SELECT 1 AS id', kind='text', scope='template_only', format='aql')
    client.check('SELECT @p AS id', kind='text', scope='bound_input', format='aql', parameters={'p': 1})

async def async_calls(client: AsyncClient) -> None:
    await client.start_source('SELECT 1 AS id', format='aql', submission_ref={})
    await client.check('SELECT 1 AS id', kind='text', scope='template_only', format='aql')
    await client.check('SELECT @p AS id', kind='text', scope='bound_input', format='aql', parameters={'p': 1})
