import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {createPrivateKey, createPublicKey} from 'node:crypto';
import {createRetainedGraphAuthorization, observeRetainedGraphDispatch}
  from './fixtures/retained-graph-observer.mjs';
import {graphRemainingOperationInputs, graphRemainingOperationCohortInputs}
  from './fixtures/graph-remaining-operation-inputs.mjs';
import {graphGraftSourceSuccesses, graphGraftSourceRefusals,
  graphGraftSourceExecutionFailures} from './fixtures/graph-graft-source-input.mjs';
import {graphReachSourceSuccesses, graphReachSourceRefusals}
  from './fixtures/graph-reach-source-input.mjs';
import {graphShortestSourceSuccesses, graphShortestSourceRefusals}
  from './fixtures/graph-shortest-source-input.mjs';
import {graphMeanSourceOracles, graphMeanSourceRefusals}
  from './fixtures/graph-mean-source-input.mjs';

test('combined Graph selection retains all original independent oracles exactly once', () => {
  for (const [kind, families, expectedCount] of [
    ['successes', [graphGraftSourceSuccesses, graphReachSourceSuccesses,
      graphShortestSourceSuccesses, graphMeanSourceOracles], 27],
    ['refusals', [graphGraftSourceRefusals, graphReachSourceRefusals,
      graphShortestSourceRefusals, graphMeanSourceRefusals], 16],
    ['executionFailures', [graphGraftSourceExecutionFailures], 1],
  ]) {
    const actual = graphRemainingOperationInputs[kind];
    assert.equal(actual.length, expectedCount);
    assert.equal(new Set(actual.map(item => item.name)).size, expectedCount);
    for (const [index, expected] of families.flat().entries()) {
      assert.equal(actual[index], expected, `${kind} retains the authored oracle`);
    }
  }
});

test('each Graph operation has independent JSON and AQL fresh-process boundaries', () => {
  const groups = graphRemainingOperationCohortInputs(graphRemainingOperationInputs);
  assert.deepEqual(groups.map(group => [group.successes.length,
    group.executionFailures.length, group.refusals.length]),
  [[5, 1, 4], [9, 0, 4], [7, 0, 5], [6, 0, 3]]);
  assert.deepEqual(groups.map(group => [group.successes[0].name,
    group.successes.at(-1).name]), [
    ['graph-graft-independent-json-two-consumers', 'graph-graft-terminal-query'],
    ['graph-reach-json-raw-identity-two-consumers', 'graph-reach-aql-connected-in'],
    ['graph-shortest-json-zero-hop-two-consumers', 'graph-shortest-aql-weighted-parallel-edges'],
    ['graph-mean-json-explicit-repeated-samples-two-consumers', 'graph-mean-aql-asymmetric-ordered-samples'],
  ]);
  for (const kind of ['successes', 'executionFailures', 'refusals']) {
    const flattened = groups.flatMap(group => group[kind]);
    for (const [index, expected] of graphRemainingOperationInputs[kind].entries()) {
      assert.equal(flattened[index], expected, 'cohort grouping retains oracle identity');
    }
  }
});

test('Graph operation cohorts cannot silently drop unknown fixtures or a family', () => {
  assert.throws(() => graphRemainingOperationCohortInputs({
    ...graphRemainingOperationInputs,
    refusals: [...graphRemainingOperationInputs.refusals, {name: 'unknown-operation'}],
  }), /preserve every refusals fixture/);
  assert.throws(() => graphRemainingOperationCohortInputs({
    ...graphRemainingOperationInputs,
    successes: graphRemainingOperationInputs.successes.filter(item =>
      !item.name.startsWith('graph-mean-')),
  }), /Every Graph operation/);
});

test('combined Graph selection stays narrow and rereads after both producers exit', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const flag = "'--graph-remaining-operations-only'";
  const narrow = driver.slice(driver.indexOf('const narrowPublicQuery ='),
    driver.indexOf('.includes(flag));', driver.indexOf('const narrowPublicQuery =')));
  assert.ok(narrow.includes(flag));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_REMAINING_OPERATIONS_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/graph-remaining-operation-inputs.mjs', 'graph-remaining-operation-inputs.mjs']"));
  const source = driver.indexOf("['packed-query-transports.mjs']");
  const restart = driver.indexOf('if (process.argv.includes(\'--graph-graft-only\')', source);
  const end = driver.indexOf("if (process.argv.includes('--source-graph-member-only'))", restart);
  assert.ok(source >= 0 && restart > source && end > restart);
  const branch = driver.slice(restart, end);
  assert.ok(branch.includes(flag));
  assert.ok(branch.includes("exerciseRetainedQueryRestart({ACTQL_TEST_RETAINED_COHORT_ONLY: '1'})"));
  assert.ok(branch.includes('return;'));
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(corpus.includes('graphRemainingOperationsOnly ? graphRemainingOperationInputs'));
  assert.ok(corpus.includes('graphRemainingOperationCohortInputs(scopeInputs).flatMap(publicQueryCohorts)'));
  assert.ok(corpus.includes('saved.expectedSampleNames = [...boundaryNames]'));
  assert.ok(corpus.includes('cohort.samples.map(sample => sample.source.name), cohort.expectedSampleNames'));
  const reader = await readFile(new URL('./fixtures/string-values-restart.mjs', import.meta.url), 'utf8');
  assert.ok(reader.includes('cohort.samples.map(sample => sample.source.name), cohort.expectedSampleNames'));
  assert.ok(reader.includes('cohort.samples.length >= 1 && cohort.samples.length <= 2'));
  assert.ok(reader.includes('observeRetainedGraphDispatch(cohort.authorization, physicalDispatches)'));
  assert.ok(corpus.includes('saved.authorization = authorization'));
  assert.ok(corpus.includes("physicalDispatches.includes('physical_start_reserved')"));
  assert.equal(reader.match(/authorization: replayAuthorization/g)?.length, 2,
    'both real Local and HTTPS Hosts observe the installed physical boundary');
  assert.ok(reader.includes('assert.equal(physicalDispatches.length, beforePhysical'));
});

test('retained Graph observer preserves complete scoped Site authorization', () => {
  const original = createRetainedGraphAuthorization();
  const saved = JSON.parse(JSON.stringify(original));
  assert.equal(saved.accountConfig, undefined);
  const account = JSON.parse(saved.accountConfiguration);
  assert.equal(account.entries.length, 2);
  assert.equal(account.entries[0].outcome, 'allow');
  assert.deepEqual(account.entries[0].connection, {any_of: ['actql-remote-host']});
  assert.deepEqual(account.entries[0].operation, {any_of: ['write']});
  assert.deepEqual(account.entries[1], {entry_id: 'synthetic-site-read', outcome: 'allow',
    principal: account.entries[0].principal, connection: account.entries[0].connection,
    resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}, exclusions: []});
  assert.equal(createPublicKey(createPrivateKey(saved.hostKey.privateKey)).asymmetricKeyType, 'ed25519');
  assert.equal(createPublicKey(saved.reviewers[0].publicKey).asymmetricKeyType, 'ed25519');
  const events = [];
  const observed = observeRetainedGraphDispatch(saved, events);
  assert.deepEqual(observed.hostKey, original.hostKey);
  assert.deepEqual(observed.reviewers, original.reviewers);
  assert.equal(observed.accountConfiguration, original.accountConfiguration);
  for (const name of ['physical_start_reserved', 'computed', 'local_compute_advanced', 'cleanup']) {
    observed.faultInjection(name);
  }
  assert.deepEqual(events, ['physical_start_reserved', 'computed', 'local_compute_advanced']);
  assert.throws(() => observeRetainedGraphDispatch(undefined, events), /MissingRetainedGraphAuthorization/);
});
