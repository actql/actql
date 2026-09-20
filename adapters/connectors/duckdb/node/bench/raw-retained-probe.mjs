// Diagnostic only. The formal runner must pair immutable source/configuration
// identities and the four comparators; this executable does not claim that gate.
import {DuckDBInstance} from '@duckdb/node-api';
import {retainedMatrix} from '../../../../../benchmarks/retained-results/fixtures.mjs';
import {selectReadinessCases} from '../../../../../benchmarks/retained-results/selection.mjs';
import {runRawRetainedComparator} from './raw-retained-comparator.mjs';

const {cases, scope} = selectReadinessCases(retainedMatrix(), process.env.ACTQL_RETAINED_CASE);
console.log(JSON.stringify({kind: 'raw-retained-diagnostic', scope, caseCount: cases.length,
  threads: 1, sourceSetupTimed: false, performanceAcceptance: false}));
for (const fixture of cases) {
  console.log(JSON.stringify({caseId: fixture.id, phase: 'starting'}));
  const db = await DuckDBInstance.create(':memory:', {
    threads: '1', memory_limit: String(fixture.limits.executionMemoryBytes) + 'B',
  });
  let connection;
  try {
    connection = await db.connect();
    await connection.run(fixture.createSourceSql);
    const report = await runRawRetainedComparator(connection, fixture.workload, fixture.layout, fixture.rows);
    console.log(JSON.stringify(report));
  } catch (error) {
    console.log(JSON.stringify({caseId: fixture.id, status: 'failed', message: error?.message ?? String(error)}));
    throw error;
  } finally { connection?.closeSync(); db.closeSync(); }
}
