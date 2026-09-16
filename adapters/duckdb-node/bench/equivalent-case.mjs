// One fresh diagnostic process. Never an accepted equivalent-obligation sample.
import {retainedCase} from '../../../benchmarks/retained-results/fixtures.mjs';
import {runEquivalentObligations} from './equivalent-obligations.mjs';

const [database, directory, workload, layout, rows, ...extra] = process.argv.slice(2);
if (!database || !directory || extra.length || !/^\d+$/.test(rows ?? '')) {
  throw new TypeError('InvalidEquivalentCaseArguments');
}
const fixture = retainedCase(workload, layout, Number(rows));
const describe = error => ({name: error.name, message: error.message,
  cause: error.cause && describe(error.cause),
  errors: error.errors?.map(describe)});
try {
  const report = await runEquivalentObligations(fixture, database, directory);
  console.log(JSON.stringify(report));
} catch (error) {
  console.log(JSON.stringify({caseId: fixture.id, status: 'failed', acceptanceEligible: false,
    error: describe(error)}));
  process.exitCode = 1;
}
