// Fresh-process diagnostic leg usable against an explicit clean checkout.
// This does not register a new acceptance threshold or calibrate selection.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {pathToFileURL} from 'node:url';

const [checkout, database, directory, workload, layout, rowText, nativeMilliseconds = '1', ...extra] = process.argv.slice(2);
if (!checkout || !database || !directory || !/^\d+$/.test(rowText ?? '') || extra.length) {
  throw new TypeError('InvalidRetainedDiagnosticArguments');
}
const root = resolve(checkout);
const git = async args => (await promisify(execFile)('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
if (await git(['status', '--porcelain'])) throw Error('DiagnosticCheckoutDirty');
const load = path => import(pathToFileURL(join(root, path)).href);
const {retainedCase} = await load('benchmarks/retained-results/fixtures.mjs');
const {runRetainedComparator} = await load('adapters/duckdb-node/bench/retained-comparator.mjs');
const fixture = retainedCase(workload, layout, Number(rowText));
const read = path => readFile(join(root, path), 'utf8');
const contracts = {
  adoptedText: await read('adapters/duckdb-node/contracts/adopted-relation.json'),
  query: await read('spec/contracts/actql-query-acquisition.json'),
  evidence: await read('spec/contracts/actql-query-process-evidence.json'),
  receipts: await read('spec/contracts/actql-query-two-receipt.json'),
};
try {
  const report = await runRetainedComparator(fixture, contracts, resolve(database), resolve(directory),
    {resident: true, nativeMilliseconds});
  if (revision !== await git(['rev-parse', 'HEAD']) || await git(['status', '--porcelain'])) {
    throw Error('DiagnosticSourcesChanged');
  }
  console.log(JSON.stringify({revision, acceptanceEligible: false,
    calibration: 'explicit diagnostic estimates; not calibrated ordinary selection',
    initialPlacement: 'fixture database; no preexisting resident copies', report}));
} catch (error) {
  console.log(JSON.stringify({revision, caseId: fixture.id, status: 'failed', acceptanceEligible: false,
    error: {name: error.name, message: error.message, code: error.code}}));
  process.exitCode = 1;
}
