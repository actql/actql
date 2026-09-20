// One alternating diagnostic pair. Source creation and builds are external.
import {resolve} from 'node:path';
import {retainedCase} from
  '../../../../../benchmarks/retained-results/fixtures.mjs';
import {runMatchedEquivalentPair} from './matched-equivalent-pair.mjs';

const [checkout, database, directory, workload, layout, rows, index, ...extra] =
  process.argv.slice(2);
if (!checkout || !database || !directory || !/^\d+$/.test(rows ?? '') ||
    !/^\d+$/.test(index ?? '') || extra.length) {
  throw new TypeError('InvalidMatchedPairCaseArguments');
}
const fixture = retainedCase(workload, layout, Number(rows));
try {
  const report = await runMatchedEquivalentPair({
    fixture,
    checkout: resolve(checkout),
    database: resolve(database),
    directory: resolve(directory),
    index: Number(index),
  });
  console.log(JSON.stringify(report));
  if (report.status !== 'diagnostic-completed') process.exitCode = 1;
} catch (error) {
  console.log(JSON.stringify({
    caseId: fixture.id,
    status: 'failed',
    acceptanceEligible: false,
    error: {
      name: error.name,
      message: error.message,
      code: error.code,
    },
  }));
  process.exitCode = 1;
}

