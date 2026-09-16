// Separate fixture setup process: its native allocator must not contaminate
// control-Host memory observations. No ActQL execution or timing happens here.
import {DuckDBInstance} from '@duckdb/node-api';
import {retainedCase} from '../../../benchmarks/retained-results/fixtures.mjs';

const [database, workload, layout, rowText, ...extra] = process.argv.slice(2);
if (!database || database === ':memory:' || !/^\d+$/.test(rowText ?? '') || extra.length) {
  throw new TypeError('InvalidRetainedSourceArguments');
}
const fixture = retainedCase(workload, layout, Number(rowText));
const db = await DuckDBInstance.create(database, {threads: '1',
  memory_limit: String(fixture.limits.executionMemoryBytes) + 'B'});
let connection;
try {
  connection = await db.connect();
  await connection.run(fixture.createSourceSql);
} finally { connection?.closeSync(); db.closeSync(); }
