// Fresh-process diagnostic leg usable against an explicit clean checkout.
// This does not register a new acceptance threshold or calibrate selection.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {getCompileCacheDir} from 'node:module';

const [checkout, database, directory, workload, layout, rowText,
  nativeMilliseconds = '1', estimateProfileDirectory, ...extra] = process.argv.slice(2);
if (!checkout || !database || !directory || !/^\d+$/.test(rowText ?? '') || extra.length) {
  throw new TypeError('InvalidRetainedDiagnosticArguments');
}
const root = resolve(checkout);
const git = async args => (await promisify(execFile)('git', args, {cwd: root})).stdout.trim();
const revision = await git(['rev-parse', 'HEAD']);
if (await git(['status', '--porcelain'])) throw Error('DiagnosticCheckoutDirty');
const load = path => import(pathToFileURL(join(root, path)).href);
const {retainedCase} = await load('benchmarks/retained-results/fixtures.mjs');
const {runRetainedComparator} = await load('adapters/connectors/duckdb/node/bench/retained-comparator.mjs');
const {admitRetainedEstimateProfile} = await load('benchmarks/retained-results/estimate-profile.mjs');
const {admitRetainedProductSample} = await load(
  'benchmarks/retained-results/product-sample-admission.mjs');
const fixture = retainedCase(workload, layout, Number(rowText));
const fileHash = async path => {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
};
const read = path => readFile(join(root, path), 'utf8');
const contracts = {
  adoptedText: await read('adapters/connectors/duckdb/node/contracts/adopted-relation.json'),
  query: await read('spec/contracts/actql-query-acquisition.json'),
  evidence: await read('spec/contracts/actql-query-process-evidence.json'),
  receipts: await read('spec/contracts/actql-query-two-receipt.json'),
};
try {
  let estimates;
  let calibration;
  if (estimateProfileDirectory !== undefined) {
    const profileRoot = resolve(estimateProfileDirectory);
    const [profileText, trainingBytes, trainingSourceHash, targetSourceHash] =
      await Promise.all([
        readFile(join(profileRoot, 'profile.json'), 'utf8'),
        readFile(join(profileRoot, 'training.json'), 'utf8'),
        fileHash(join(profileRoot, 'source.duckdb')),
        fileHash(resolve(database)),
      ]);
    const profile = JSON.parse(profileText);
    const [trainingWorkload, trainingLayout, trainingRows, ...remaining] =
      String(profile.trainingCaseId).split('/');
    if (remaining.length || !/^(0|[1-9][0-9]*)$/.test(trainingRows ?? '')) {
      throw new Error('InvalidCalibrationTrainingCase');
    }
    const trainingFixture = retainedCase(trainingWorkload, trainingLayout,
      Number(trainingRows));
    estimates = admitRetainedEstimateProfile({profile, trainingBytes,
      trainingFixture, targetFixture: fixture, revision,
      targetSourceSha256: targetSourceHash});
    if (trainingSourceHash !== profile.trainingSourceSha256) {
      throw new Error('CalibrationTrainingSourceChanged');
    }
    calibration = {verified: true, trainingCaseId: estimates.trainingCaseId,
      targetCaseId: estimates.targetCaseId,
      estimateSource: estimates.estimateSource,
      targetSourceSha256: targetSourceHash};
  }
  const report = await runRetainedComparator(fixture, contracts, resolve(database), resolve(directory),
    {resident: true,
      nativeMilliseconds: estimates?.nativeTaskMilliseconds[0] ?? nativeMilliseconds,
      ...(estimates ? {localEligible: estimates.localEligible,
        ...(estimates.localEligible ? {
          localTaskMilliseconds: estimates.localTaskMilliseconds,
        } : {}),
        nativeTaskMilliseconds: estimates.nativeTaskMilliseconds,
        estimateSource: estimates.estimateSource} : {})});
  if (calibration && await fileHash(resolve(database)) !== calibration.targetSourceSha256) {
    throw new Error('CalibrationTargetSourceChanged');
  }
  if (revision !== await git(['rev-parse', 'HEAD']) || await git(['status', '--porcelain'])) {
    throw Error('DiagnosticSourcesChanged');
  }
  const productAdmission = estimates ? admitRetainedProductSample({fixture,
    estimates, calibration, report}) : undefined;
  console.log(JSON.stringify({revision,
    nodeCompileCacheDirectory: getCompileCacheDir?.(),
    acceptanceEligible: productAdmission?.accepted === true,
    productAdmission,
    calibration: calibration ?? 'explicit diagnostic estimates; not calibrated ordinary selection',
    initialPlacement: 'fixture database; no preexisting resident copies', report}));
} catch (error) {
  console.log(JSON.stringify({revision, caseId: fixture.id, status: 'failed', acceptanceEligible: false,
    error: {name: error.name, message: error.message, code: error.code}}));
  process.exitCode = 1;
}
