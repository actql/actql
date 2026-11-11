// Two independent fixture processes share one installed package cohort and the
// existing enclosing job's resources, deadline and command-output allowance.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {selectAcceptanceTimeout, createTransportOwner, requireCompleteInventory, transportModes}
  from './packed-query-transport-owner.mjs';
import {decodeRetainedFixture, encodeRetainedFixture} from './retained-fixture-values.mjs';
import {requireGraphArgumentCheckReport} from './graph-argument-check.mjs';

const deadline = Number(process.env.ACTQL_TEST_QUERY_DEADLINE);
const timeoutMs = selectAcceptanceTimeout(process.env);
const owner = createTransportOwner({deadline, timeoutMs});
const entry = fileURLToPath(new URL('./packed-query-worker.mjs', import.meta.url));
let primary;
let inventories = [];
try {
  if (process.env.ACTQL_TEST_TWO_SOURCE_ONLY === '1') {
    await import('./acceptance.mjs');
  } else {
    await owner.run(transportModes.map(mode => ({name: mode, args: [entry],
      cwd: process.cwd(), environment: {ACTQL_TEST_QUERY_TRANSPORT: mode}})));
    const reports = await Promise.all(transportModes.map(async mode => {
      const report = JSON.parse(await readFile(`transport-completion.${mode}.json`, 'utf8'));
      assert.equal(report.mode, mode);
      assert.equal(report.complete, true);
      requireCompleteInventory(report.expectedInventory, report.completedInventory);
      return report;
    }));
    assert.deepEqual(reports[0].expectedInventory, reports[1].expectedInventory,
      'both transports must execute the same complete authored corpus');
    assert.ok(reports[0].expectedInventory.length > 0, 'selected corpus must contain cases');
    if (process.env.ACTQL_TEST_DISTINCT_JOIN_ORDER_ONLY === '1') {
      const {requireDistinctJoinOrderReports} = await import('./distinct-join-order-inventory.mjs');
      requireDistinctJoinOrderReports(reports);
    }
    if (process.env.ACTQL_TEST_QUERY_EXPECT_FULL_CORPUS === '1') {
      const registered = JSON.parse(await readFile('public-query-inventory.json', 'utf8'));
      assert.equal(registered.version, 'actql-public-query-fixture-inventory/0.1');
      for (const report of reports) {
        assert.equal(report.completedInventory.length, registered.totalCases);
        assert.equal(createHash('sha256').update(JSON.stringify(report.completedInventory)).digest('hex'),
          registered.inventorySha256, 'full worker inventory must match the independent authored pin');
      }
    }
    if (process.env.ACTQL_TEST_GRAPH_DIAGNOSTICS_ONLY === '1' ||
        process.env.ACTQL_TEST_QUERY_EXPECT_FULL_CORPUS === '1') {
      const checks = await Promise.all(transportModes.map(async mode => {
        const report = JSON.parse(await readFile(`graph-argument-check.${mode}.json`, 'utf8'));
        requireGraphArgumentCheckReport(report, mode);
        return report;
      }));
      assert.deepEqual(checks[0].completedInventory, checks[1].completedInventory);
    }
    assert.equal(reports[0].needsTail, reports[1].needsTail);
    inventories = reports.map(report => ({mode: report.mode,
      expectedCases: report.expectedInventory.length,
      completedCases: report.completedInventory.length,
      retainedCohorts: report.expectedRetainedCohorts,
      expectedSha256: createHash('sha256').update(JSON.stringify(report.expectedInventory)).digest('hex'),
      completedSha256: createHash('sha256').update(JSON.stringify(report.completedInventory)).digest('hex'),
    }));
    const cohorts = (await Promise.all(transportModes.map(async mode => {
      const values = decodeRetainedFixture(await readFile(`retained-cohort-results.${mode}.json`, 'utf8'));
      assert.ok(values.every(value => value.mode === mode));
      assert.equal(values.length, reports.find(report => report.mode === mode).expectedRetainedCohorts,
        'every successful cohort retains its independent restart sample');
      return values;
    }))).flat();
    // Retain the original profile/transport order, independently of scheduling.
    const profiles = [...new Set(reports[0].expectedInventory.map(key => JSON.parse(key)[0]))];
    cohorts.sort((left, right) => profiles.indexOf(left.profileName) - profiles.indexOf(right.profileName) ||
      transportModes.indexOf(left.mode) - transportModes.indexOf(right.mode));
    assert.equal(new Set(cohorts.map(value => value.directory)).size, cohorts.length);
    await writeFile('retained-cohort-results.json', encodeRetainedFixture(cohorts), {flag: 'wx'});
    const stringCase = reports[0].expectedInventory.some(key => JSON.parse(key)[3] === 'exact-string-values');
    if (stringCase) {
      const strings = await Promise.all(transportModes.map(mode =>
        readFile(`retained-string-results.${mode}.json`, 'utf8').then(JSON.parse)));
      assert.deepEqual(strings[0].hostCapacityPolicy, strings[1].hostCapacityPolicy);
      assert.ok(strings[0].local && strings[1].remote);
      await writeFile('retained-string-results.json', JSON.stringify({
        local: strings[0].local, remote: strings[1].remote,
        hostCapacityPolicy: strings[0].hostCapacityPolicy,
        sourceProfilePaths: {...strings[0].sourceProfilePaths, ...strings[1].sourceProfilePaths},
      }) + '\n', {flag: 'wx'});
    }
    if (reports[0].needsTail) {
      assert.ok(Date.now() < deadline, 'same acceptance deadline includes the serial tail');
      // Both owned transports have exited. This original tail runs once, in
      // the same acceptance command; its nested commands keep existing limits.
      process.env.ACTQL_TEST_QUERY_TRANSPORT = 'tail';
      await import('./acceptance.mjs');
    }
  }
  owner.check();
} catch (error) {
  primary = error;
} finally {
  owner.close();
  const report = {...owner.report(), inventories,
    complete: primary === undefined, primaryError: primary?.message ?? owner.report().primaryError,
    enclosingCommand: {timeoutMs: owner.report().timeoutMs, outputLimitBytes: 8 * 1024 * 1024},
  };
  try {
    await writeFile('transport-processes.json', JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
  } catch (error) {
    if (primary === undefined) primary = error;
    else primary.evidenceError = error;
  }
  // The existing uploader admits numbered command stdout logs. Include only
  // bounded process receipts and inventory counts/digests, never fixture rows.
  console.log('Packed query transport receipt: ' + JSON.stringify({...report,
    complete: primary === undefined, primaryError: primary?.message ?? report.primaryError}));
}
if (primary !== undefined) throw primary;
