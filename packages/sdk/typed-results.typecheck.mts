import type {Client, DynamicRow, Reader, Result, StandardSchemaV1} from './index.js';
declare const client: Client;
declare const result: Result;
declare const transformed: StandardSchemaV1<{n: number}, {when: Date; count: bigint}>;
const values: {when: Date; count: bigint}[] = await result.all(transformed);
const rows: Reader<{when: Date; count: bigint}> = result.rows(transformed, {maxWireBytes: 1000});
const shortcut: {when: Date; count: bigint}[] = await client.sql('SELECT 1 AS n').all(transformed);
const callable = Object.assign((value: unknown) => value, {'~standard': {
  version: 1 as const, vendor: 'callable', validate: (value: unknown) => ({value: String(value)}),
  types: undefined as {input: unknown; output: string} | undefined,
}});
const strings: string[] = await result.all(callable);
const raw: DynamicRow[] = await result.all({maxRows: 2});
const primitive: StandardSchemaV1<unknown, number> = {'~standard': {
  version: 1, vendor: 'test', validate: async () => ({value: 42}),
}};
const numbers: number[] = await result.all(primitive);
declare const promises: StandardSchemaV1<unknown, Promise<Date>>;
const promised: Promise<Date>[] = await result.all(promises);
for await (const row of result.rows(transformed)) {
  const date: Date = row.when;
  // @ts-expect-error Output is inferred after transformation, not from schema Input.
  const input: number = row.n;
  void [date, input];
}
// @ts-expect-error An assertion-only generic is not a schema.
result.all<{n: number}>();
// @ts-expect-error Typed rows require a real validation schema argument.
result.rows<{n: number}>();
// @ts-expect-error The short query cannot assert an output row type.
client.sql('SELECT 1 AS n').all<{n: number}>();
// @ts-expect-error Output is not the raw schema Input type.
const wrong: {n: number}[] = await result.all(transformed);
// @ts-expect-error Standard Schema V2 is not supported.
result.rows({'~standard': {version: 2, vendor: 'test', validate: () => ({value: 1})}});
void [values, rows, shortcut, strings, raw, numbers, promised, wrong];
