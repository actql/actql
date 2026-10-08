// This file is copied into the external packed installation before compilation.
// Imports must resolve there, without repository packages or NODE_PATH fallbacks.
import {open, type Result, type Reader, type RequestRecovery, type RequestLookupTarget} from '@actql/node';
import type {StandardSchemaV1, DynamicRow} from '@actql/sdk';
const client = await open({stateDir: 'typed-consumer'});
const schema: StandardSchemaV1<{id: number}, {label: string; at: Date}> = {
  '~standard': {version: 1, vendor: 'packed-consumer', validate(value) {
    if (value === null || typeof value !== 'object' || !('id' in value) ||
        typeof value.id !== 'number') return {issues: [{message: 'Expected numeric id', path: ['id']}]};
    return {value: {label: String(value.id), at: new Date(value.id)}};
  }},
};
const query = client.sql('SELECT 1 AS id');
const result: Result = await query;
const recovery: RequestRecovery = client.recoverRequest(result);
const savedTarget: RequestLookupTarget = recovery.target;
const restoredRecovery = client.recoverRequest(savedTarget);
const recoveredLookup = await restoredRecovery.lookup();
if (recoveredLookup.kind === 'found' || recoveredLookup.kind === 'ready') await restoredRecovery.attach(recoveredLookup);
else {
  // @ts-expect-error Unresolved/pre-Run branches cannot attach as a Run.
  restoredRecovery.attach(recoveredLookup);
}
// @ts-expect-error A recovery handle is not an Execution before Run lookup.
recovery.ref;
const output: {label: string; at: Date}[] = await query.all(schema, {maxRows: 2});
const rows: Reader<{label: string; at: Date}> = result.rows(schema);
const collected: {label: string; at: Date}[] = await result.all(schema);
const raw: DynamicRow[] = await result.all();
for await (const row of rows) {
  const when: Date = row.at;
  // @ts-expect-error The transformed output does not expose raw id.
  const id: number = row.id;
  void [when, id];
}
// @ts-expect-error No assertion-only generic on raw query submission.
client.sql<{id: number}>('SELECT 1 AS id');
// @ts-expect-error No assertion-only collection generic without a schema.
query.all<{id: number}>();
// @ts-expect-error No assertion-only row generic without a schema.
result.rows<{id: number}>();
// @ts-expect-error Output transformation is inferred, not schema Input.
const wrong: {id: number}[] = await result.all(schema);
// @ts-expect-error A parser-shaped object without Standard Schema is not a schema.
result.all({parse(value: unknown) {return value;}}, {maxRows: 1});
// @ts-expect-error Unsupported schema version cannot validate a typed result.
result.rows({'~standard': {version: 2, vendor: 'future', validate: () => ({value: 1})}});
await client.close();
void [output, collected, raw, wrong];
