import {runEquivalentMatrix} from './equivalent-matrix-runner.mjs';

const [outputDirectory, caseId, ...extra] = process.argv.slice(2);
if (!outputDirectory || extra.length) {
  throw new TypeError('Usage: node run-equivalent-matrix.mjs <empty-output-directory> [registered-case-id]');
}
const result = await runEquivalentMatrix({checkout: new URL('../../', import.meta.url).pathname,
  outputDirectory, ...(caseId === undefined ? {} : {caseId})});
console.log(JSON.stringify({revision: result.revision,
  outputDirectory: result.outputDirectory,
  status: result.assessment.status,
  registeredCases: result.assessment.registeredCases,
  receivedRecords: result.assessment.receivedRecords}));
if (result.assessment.status !== 'pass') process.exitCode = 1;
