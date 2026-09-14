import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { DuckDBInstance } from '@duckdb/node-api';

const root = fileURLToPath(new URL('../../..', import.meta.url));

test('MoonBit composite inner join SQL preserves mapped equality and original pair order', async () => {
  const { stdout } = await promisify(execFile)('moon', [
    'test', '--target', 'js', 'src/query_integration/duckdb_inner_join_wbtest.mbt',
  ], { cwd: root, maxBuffer: 2 * 1024 * 1024 });
  assert.match(stdout, /Total tests: 2, passed: 2, failed: 0/);
  const fixtures = stdout.split('\n').filter(x => x.startsWith('ACTQL_INNER_JOIN '))
    .map(x => JSON.parse(x.slice('ACTQL_INNER_JOIN '.length)));
  assert.deepEqual(fixtures.map(x => x.name), ['number', 'text', 'boolean', 'date', 'timestamp', 'decimal']);
  const cases = {
    number: { types: ['DOUBLE', 'DOUBLE'], left: ['9007199254740992', '-1.5'], right: ['9007199254740992', '-1.5'] },
    text: { types: ['VARCHAR', 'VARCHAR'], left: ["chr(65536)", "chr(57344)"], right: ["chr(65536)", "chr(57344)"] },
    boolean: { types: ['BOOLEAN', 'BOOLEAN'], left: ['false', 'true'], right: ['false', 'true'] },
    date: { types: ['DATE', 'DATE'], left: ["'0001-01-01 (BC)'", "'9999-12-31'"], right: ["'0001-01-01 (BC)'", "'9999-12-31'"] },
    timestamp: { types: ['TIMESTAMPTZ', 'TIMESTAMPTZ'], left: ["'1970-01-01 00:00:00+00'", "'9999-12-31 23:59:59.999+00'"], right: ["'1970-01-01 01:00:00+01'", "'9999-12-31 23:59:59.999+00'"] },
    decimal: { types: ['DECIMAL(38,0)', 'DECIMAL(38,2)'], left: ["'100000000000000000000000000000000000'", "'-10'"], right: ["'100000000000000000000000000000000000.00'", "'-10.00'"] },
  };
  const expected = [{ l: 10, r: 20 }, { l: 10, r: 22 }, { l: 11, r: 21 }, { l: 12, r: 20 }, { l: 12, r: 22 }];
  for (const fixture of fixtures) {
    const c = cases[fixture.name];
    const db = await DuckDBInstance.create(':memory:');
    const connection = await db.connect();
    try {
      await connection.run('SET preserve_insertion_order = true');
      await connection.run(`CREATE TABLE left_rows(__ordinal DOUBLE, k ${c.types[0]}, tag DOUBLE)`);
      await connection.run(`CREATE TABLE right_rows(__ordinal DOUBLE, k ${c.types[1]}, tag DOUBLE)`);
      await connection.run(`INSERT INTO left_rows VALUES (1,${c.left[0]},10),(1,${c.left[1]},11),(1,${c.left[0]},12),(1,NULL,13),(2,${c.left[0]},14)`);
      await connection.run(`INSERT INTO right_rows VALUES (1,${c.right[0]},20),(1,${c.right[1]},21),(1,${c.right[0]},22),(1,NULL,23)`);
      assert.deepEqual((await connection.runAndReadAll(fixture.sql)).getRowObjects(), expected);
      if (fixture.name === 'decimal') {
        // A common precision-38 cast cannot hold both extreme domains. Exact
        // unequal fractions must not round into the integral left key either.
        await connection.run("INSERT INTO left_rows VALUES (1,'99999999999999999999999999999999999999',30),(1,0,31)");
        await connection.run("INSERT INTO right_rows VALUES (1,'999999999999999999999999999999999999.99',40),(1,'-0.00',41),(1,'-10.01',42)");
        assert.deepEqual((await connection.runAndReadAll(fixture.sql)).getRowObjects(), [...expected, { l: 31, r: 41 }]);
      }
      if (fixture.name === 'text') {
        await connection.run("SET default_collation = 'nocase'");
        await connection.run("INSERT INTO left_rows VALUES (1,'a',30),(1,'é',31)");
        await connection.run("INSERT INTO right_rows VALUES (1,'A',40),(1,'e' || chr(769),41)");
        assert.deepEqual((await connection.runAndReadAll(fixture.sql)).getRowObjects(), expected);
      }
      await connection.run('DELETE FROM left_rows');
      assert.deepEqual((await connection.runAndReadAll(fixture.sql)).getRowObjects(), []);
      if (fixture.name === 'number') {
        await connection.run('DELETE FROM right_rows');
        await connection.run('INSERT INTO left_rows SELECT 1, i % 257, i FROM range(5001) t(i)');
        await connection.run('INSERT INTO right_rows SELECT 1, i, i FROM range(257) t(i)');
        await connection.run('INSERT INTO right_rows SELECT 1, i, i + 1000 FROM range(257) t(i)');
        const expectedLarge = [];
        for (let l = 0; l < 5001; l++) {
          expectedLarge.push({ l, r: l % 257 }, { l, r: l % 257 + 1000 });
        }
        assert.deepEqual((await connection.runAndReadAll(fixture.sql)).getRowObjects(), expectedLarge);
      }
    } finally {
      connection.closeSync();
      db.closeSync();
    }
  }
  // This checks generated SQL against an actual backend, not completion or
  // cardinality evidence. The trusted Compute path must discharge those too.
});
