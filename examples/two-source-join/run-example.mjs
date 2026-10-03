// The public Client submits one Program; the Host acquires and joins both inputs.
import {readFile, writeFile} from 'node:fs/promises';
import {connect} from '@actql/node';

const options = JSON.parse(await readFile(process.argv[2] ??
  'two-source-example-data/connection.json', 'utf8'));
const client = await connect(options);
try {
  const program = await readFile(new URL('two-source-join.program.json', import.meta.url), 'utf8');
  const execution = await client.aql(program,
    {format: 'json', requestId: 'two-source-join-example'});
  const state = await execution.wait({signal: AbortSignal.timeout(60_000)});
  if (state.status !== 'succeeded') throw new Error(JSON.stringify(state));
  const result = execution.result('joined');
  const description = await result.describe();
  const reader = result.rows();
  const rows = await Array.fromAsync(reader);
  if (reader.state() !== 'complete') throw new Error('IncompleteNamedResult');
  await writeFile('joined.jsonl', rows.map(row => JSON.stringify(row)).join('\n') + '\n');
  await writeFile('joined.schema.json', JSON.stringify(description, null, 2) + '\n');
  await writeFile('joined.run.json', JSON.stringify(execution.ref) + '\n');
} finally { client.close(); }
