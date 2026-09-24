import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {runEquivalentMatrix} from './equivalent-matrix-runner.mjs';

const [outputDirectory, caseId, ...extra] = process.argv.slice(2);
if (!outputDirectory || extra.length) {
  throw new TypeError('Usage: node run-equivalent-matrix.mjs <empty-output-directory> [registered-case-id]');
}
const checkout = new URL('../../', import.meta.url).pathname;
const pin = JSON.parse(readFileSync(join(checkout, 'toolchain.json'), 'utf8'));
const moonHome = join(checkout, '.toolchains', `moonbit-${pin.version}`);
// A clean source revision does not prove ignored _build modules are current.
// Rebuild before calibration so every measured child runs this revision's code.
execFileSync(join(moonHome, 'bin', 'moon'), ['build', '--target', 'js', '--release'],
  {cwd: checkout, stdio: 'inherit', env: {...process.env, MOON_HOME: moonHome,
    PATH: `${join(moonHome, 'bin')}:${process.env.PATH ?? ''}`}});
const result = await runEquivalentMatrix({checkout,
  outputDirectory, ...(caseId === undefined ? {} : {caseId})});
const status = caseId === undefined ? result.assessment.status :
  result.assessment.cases.find(value => value.caseId === caseId)?.status ?? 'incomplete';
console.log(JSON.stringify({revision: result.revision,
  outputDirectory: result.outputDirectory,
  status,
  registeredCases: result.assessment.registeredCases,
  receivedRecords: result.assessment.receivedRecords}));
if (status !== 'pass') process.exitCode = 1;
