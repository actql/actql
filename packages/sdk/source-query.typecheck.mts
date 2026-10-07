import type {Client, DynamicRow, Execution, Result, ResultPromise} from './index.js';
import {open, type LocalSession} from '../node/index.js';
declare const client: Client;
const query: ResultPromise = client.sql('SELECT @id AS id', {id: 1}, {
  parameterDeclarations: {id: {type: 'number'}}, submissionRef: client.newSubmission({nonce: 'saved'}), result: 'answer',
});
const request: string = query.requestId;
const result: Result = await query;
const execution: Execution = result.execution;
const rows: DynamicRow[] = await query.all({maxRows: 100});
for await (const row of result.rows()) {const value: unknown = row.id; void value;}
const low: Execution = await client.startSource('{}', {format: 'json', submissionRef: client.newSubmission({nonce: request})});
const local: LocalSession = await open({stateDir: '.actql'});
const stateDir: string = local.info.stateDir;
await local.close();
// @ts-expect-error A short query resolves a Result, not the former Execution.
const old: Execution = await client.aql('SELECT 1');
// @ts-expect-error Raw SQL has no assertion-only row generic.
client.sql<{id: number}>('SELECT 1 AS id');
// @ts-expect-error Collection cannot assert a row type without a validator.
query.all<{id: number}>();
// @ts-expect-error Format belongs to startSource, not short SQL options.
client.sql('SELECT 1', undefined, {format: 'json'});
// @ts-expect-error No second state-directory spelling in an open installation.
open({stateDir: 'one', installation: {directory: 'two'}});
void [rows, execution, low, stateDir, old];

// @ts-expect-error Bare historical IDs cannot create a new query.
client.sql('SELECT 1', undefined, {requestId: 'saved'});
