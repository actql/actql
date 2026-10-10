// Producers have exited. Each worker restores only its own transport's roots,
// serially, under the original one aggregate 120-second restart deadline.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {createTransportOwner, requireCompleteInventory, transportModes}
  from './packed-query-transport-owner.mjs';
import {decodeRetainedFixture} from './retained-fixture-values.mjs';

const cohorts = decodeRetainedFixture(await readFile('retained-cohort-results.json', 'utf8'));
const owner = createTransportOwner({deadline: Number(process.env.ACTQL_TEST_QUERY_RESTART_DEADLINE), timeoutMs: 120_000});
let primary;
const roots = [];
try {
  await owner.run(transportModes.map(mode => ({name: mode,
    args: [fileURLToPath(new URL('./packed-query-worker.mjs', import.meta.url)), 'restart'],
    cwd: process.cwd(), environment: {ACTQL_TEST_QUERY_TRANSPORT: mode}})));
  for (const mode of transportModes) {
    const expected = cohorts.filter(cohort => cohort.mode === mode).map(cohort => cohort.directory);
    const report = JSON.parse(await readFile(`transport-restart.${mode}.json`, 'utf8'));
    assert.equal(report.mode, mode);
    assert.equal(report.stringComplete, true);
    requireCompleteInventory(expected, report.completedRoots);
    roots.push({mode, expectedRoots: expected.length, completedRoots: report.completedRoots.length});
  }
  owner.check();
} catch (error) { primary = error; }
finally {
  owner.close();
  const report = {...owner.report(), roots, complete: primary === undefined,
    primaryError: primary?.message ?? owner.report().primaryError};
  try {
    await writeFile('transport-restart-processes.json', JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
  } catch (error) {
    if (primary === undefined) primary = error;
    else primary.evidenceError = error;
  }
  console.log('Packed query restart receipt: ' + JSON.stringify({...report,
    complete: primary === undefined, primaryError: primary?.message ?? report.primaryError}));
}
if (primary !== undefined) throw primary;
