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
  const {parse} = await import('acorn');
  const syntax = parse(driver, {sourceType: 'module', ecmaVersion: 'latest'});
  const branches = [];
  const visit = node => {
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'IfStatement' && node.consequent.type === 'BlockStatement' &&
        driver.slice(node.test.start, node.test.end).includes(flag) &&
        driver.slice(node.consequent.start, node.consequent.end)
          .includes("exerciseRetainedQueryRestart({ACTQL_TEST_RETAINED_COHORT_ONLY: '1'})")) {
      branches.push(node);
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value !== null && typeof value === 'object') visit(value);
    }
  };
  visit(syntax);
  assert.equal(branches.length, 1, 'one combined branch owns the cold Graph reread');
  const [branch] = branches;
  const modes = [];
  const readModes = node => {
    if (node.type === 'LogicalExpression') {
      assert.equal(node.operator, '||', 'each selected narrow mode independently reaches restart');
      readModes(node.left); readModes(node.right);
      return;
    }
    assert.equal(node.type, 'CallExpression');
    assert.equal(driver.slice(node.callee.start, node.callee.end), 'process.argv.includes');
    assert.equal(node.arguments.length, 1);
    assert.equal(node.arguments[0].type, 'Literal');
    modes.push(node.arguments[0].value);
  };
  readModes(branch.test);
  assert.ok(modes.includes('--graph-graft-only'));
  assert.ok(modes.includes('--graph-remaining-operations-only'));
  const end = driver.indexOf("if (process.argv.includes('--source-graph-member-only'))", branch.end);
  assert.ok(source >= 0 && branch.start > source && end >= branch.end);
  const first = branch.consequent.body[0];
  assert.equal(first.type, 'ExpressionStatement');
  assert.equal(first.expression.type, 'AwaitExpression');
  assert.equal(driver.slice(first.expression.argument.start, first.expression.argument.end),
    "exerciseRetainedQueryRestart({ACTQL_TEST_RETAINED_COHORT_ONLY: '1'})");
  const last = branch.consequent.body.at(-1);
  assert.equal(last.type, 'ReturnStatement');
  assert.equal(last.argument, null, 'cold reread completes before returning from this narrow mode');
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(corpus.includes('graphRemainingOperationsOnly ? graphRemainingOperationInputs'));
  assert.ok(corpus.includes('graphRemainingOperationCohortInputs(profile.inputs).flatMap(publicQueryCohorts)'));
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
