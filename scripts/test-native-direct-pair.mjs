import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {retainedCase} from '../benchmarks/retained-results/fixtures.mjs';
import {runNativeDirectPair} from '../benchmarks/retained-results/native-direct-pair.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const scratchRoot = join(process.env.ACTQL_TEST_SCRATCH_ROOT ?? tmpdir(),
  'actql-native-direct-pair');
await mkdir(scratchRoot, {recursive: true});
const directory = await mkdtemp(join(scratchRoot, 'run-'));
const fixture = retainedCase(
  'native-acquisition-full-validation-low-selectivity', 'narrow', 100);
const database = join(directory, 'source.duckdb');
try {
  await promisify(execFile)(process.execPath,
    [join(root, 'adapters/connectors/duckdb/node/bench/create-retained-source.mjs'),
      database, fixture.workload, fixture.layout, String(fixture.rows)],
    {cwd: root, timeout: fixture.limits.timeoutMs});
  const profilePath = process.env.ACTQL_NATIVE_CALIBRATION_PROFILE;
  const nativeEstimateProfile = profilePath
    ? JSON.parse(await readFile(profilePath, 'utf8')) : undefined;
  const pair = await runNativeDirectPair({checkout: root, fixture, database,
    directory, index: 0, nativeEstimateProfile});
  assert.equal(pair.status, 'diagnostic-completed');
  assert.equal(pair.identityEqual, true);
  assert.equal(pair.metadataEqual, true);
  assert.equal(pair.stageRowsEqual, true);
  assert.equal(pair.stageContentsEqual, true);
  assert.equal(pair.acceptanceEligible, Boolean(nativeEstimateProfile));
  if (nativeEstimateProfile) {
    assert.equal(pair.nativeObligationAdmission?.accepted, true);
    assert.equal(pair.selectionProfile.admitted, true);
  }
  // A calibrated profile may select a different admitted physical plan.
  // runNativeDirectPair already verifies its exact ordinary selection.
  if (!nativeEstimateProfile) {
    assert.deepEqual(pair.native.selected, ['local', 'local', 'local']);
  }
  console.log('Direct Native product and independent assembly agree');
} finally {
  await rm(directory, {recursive: true, force: true});
}
