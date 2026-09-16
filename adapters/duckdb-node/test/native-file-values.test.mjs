// Independent codec conformance probes for the finite read_json fast path.
// Passing does not itself authorize identity or value-validation reuse.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {withComputeDatabase} from '../session.mjs';

const limits = {maxRows: 10000, maxCells: 30000, maxTransportBytes: 2000000,
  maxSqlBytes: 10000, maxParameters: 1, maxColumns: 3,
  memoryBytes: 134217728, threads: 1, maxChunkRows: 128, maxChunkBytes: 65536};

async function readNative(text, columns, use) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-value-probe-'));
  const path = join(directory, 'input.json');
  try {
    await writeFile(path, text);
    await withComputeDatabase(limits, async session => {
      await session.command(`CREATE TEMP TABLE imported AS SELECT * FROM read_json(
        ?, format='array', records=true, auto_detect=false,
        columns=${columns}, maximum_object_size=1048576, ignore_errors=false)`,
      [{type: {id: 'VARCHAR'}, value: path}], () => {});
      const rows = [];
      await session.command('SELECT * FROM imported ORDER BY rowid', [], chunk => {
        for (let row = 0; row < chunk.rowCount; row++) {
          rows.push(Object.fromEntries(chunk.fields.map((field, column) =>
            [field.name, chunk.columns[column][row]])));
        }
      });
      await use(rows);
    }, undefined, undefined, [path]);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
}

test('native explicit DOUBLE import preserves independent binary64 boundary vectors', async () => {
  // Decimal source lexemes and independently fixed IEEE-754 encodings, not
  // expected results obtained from DuckDB or ActQL product serialization.
  const vectors = [
    ['0', '0000000000000000'],
    ['1', '3ff0000000000000'],
    ['-1', 'bff0000000000000'],
    ['0.1', '3fb999999999999a'],
    ['1.0000000000000002', '3ff0000000000001'],
    ['5e-324', '0000000000000001'],
    ['-5e-324', '8000000000000001'],
    ['2.225073858507201e-308', '000fffffffffffff'],
    ['2.2250738585072014e-308', '0010000000000000'],
    ['1.7976931348623157e308', '7fefffffffffffff'],
    ['-1.7976931348623157e308', 'ffefffffffffffff'],
    ['9007199254740992', '4340000000000000'],
    ['-9007199254740992', 'c340000000000000'],
  ];
  await readNative(`[${vectors.map(([text]) => `{"n":${text}}`).join(',')}]`,
    "{'n':'DOUBLE'}", rows => {
      assert.deepEqual(rows.map(row => row.n), vectors.map(([, expected]) => expected));
    });
});

test('native text boolean and NULL import preserves escapes order and duplicate occurrences', async () => {
  const text = '[{"s":"\\u0000\\n\\r\\t\\b\\f\\\"\\\\","b":true},' +
    '{"s":"é😀","b":false},{"s":null,"b":null},' +
    '{"s":"\\u00e9\\ud83d\\ude00","b":false},{"s":"","b":true}]';
  await readNative(text, "{'s':'VARCHAR','b':'BOOLEAN'}", rows => {
    assert.deepEqual(rows, [
      {s: '\0\n\r\t\b\f"\\', b: true},
      {s: 'é😀', b: false}, {s: null, b: null},
      {s: 'é😀', b: false}, {s: '', b: true},
    ]);
  });
});

test('native import preserves empty typed relations without inventing rows', async () => {
  await readNative('[]', "{'n':'DOUBLE','s':'VARCHAR','b':'BOOLEAN'}", rows => {
    assert.deepEqual(rows, []);
  });
});

test('native ordinal order survives multiple native vectors and bounded transport chunks', async () => {
  const expected = Array.from({length: 4097}, (_, index) => ({
    s: index % 3 === 0 ? 'duplicate' : `occurrence-${index}`, b: index % 2 === 0,
  }));
  await readNative(JSON.stringify(expected), "{'s':'VARCHAR','b':'BOOLEAN'}", rows => {
    assert.deepEqual(rows, expected);
  });
});

test('native JSON coercion is not a substitute for prior typed value admission', async () => {
  // This JSON string is not an admitted ActQL Number. DuckDB nevertheless
  // coerces it, so successful import is not evidence of typed input validity.
  await readNative('[{"n":"1"}]', "{'n':'DOUBLE'}", rows => {
    assert.deepEqual(rows, [{n: '3ff0000000000000'}]);
  });
});
