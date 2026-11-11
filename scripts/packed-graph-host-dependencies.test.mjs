import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {basename, dirname, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {graphPublicHostCases, graphPublicHostPattern} from './fixtures/graph-host-cases.mjs';

test('packed Graph failure consumer retains its finite transitive fixtures', async () => {
  const scripts = fileURLToPath(new URL('./', import.meta.url));
  const driver = await readFile(resolve(scripts, 'test-packed-graph.mjs'), 'utf8');
  const pending = ['graph-public-failure.test.mjs'];
  const visited = new Set();
  while (pending.length) {
    const name = pending.pop();
    if (visited.has(name)) continue;
    visited.add(name);
    assert.ok(driver.includes(`'${name}'`), `Packed failure dependency is not copied: ${name}`);
    const body = await readFile(resolve(scripts,name), 'utf8');
    for (const match of body.matchAll(/\bfrom\s+['"]([^'"]+)['"]/gu)) {
      if (!match[1].startsWith('.')) continue;
      const dependency = relative(scripts,resolve(scripts,dirname(name),match[1]));
      assert.ok(!dependency.startsWith('..'),'Static fixture imports must stay within scripts');
      pending.push(dependency);
    }
  }
  assert.ok(driver.includes("process.argv.includes('--remaining-failures-only')"));
  assert.ok(driver.includes("remainingFailuresOnly ? 'graph-public-failure.test.mjs'"));
  const fixture = await readFile(resolve(scripts,'fixtures/graph-snapshot-failure-store.mjs'),'utf8');
  assert.ok(fixture.includes('status: () => physical.status()'), 'retain real Store accounting');
  assert.ok(fixture.includes('await writer.seal(identity)'), 'lose acknowledgement after actual seal');
});

test('packed Graph Host consumers retain their transitive local module imports', async () => {
  const scripts = fileURLToPath(new URL('./', import.meta.url));
  const driver = await readFile(resolve(scripts, 'test-packed-public-query.mjs'), 'utf8');
  const pending = ['graph-public-host.test.mjs', 'graph-source-snapshot.test.mjs'];
  const visited = new Set();
  while (pending.length) {
    const name = pending.pop();
    if (visited.has(name)) continue;
    visited.add(name);
    assert.ok(driver.includes(`'${name}'`), `Packed consumer dependency is not copied: ${name}`);
    const body = await readFile(resolve(scripts, name), 'utf8');
    for (const match of body.matchAll(/\bfrom\s+['"]([^'"]+)['"]/gu)) {
      if (!match[1].startsWith('.')) continue;
      const dependency = relative(scripts, resolve(scripts, dirname(name), match[1]));
      assert.ok(!dependency.startsWith('..'), 'Static test imports must stay within scripts');
      pending.push(dependency);
    }
  }
});

test('packed Graph predicate source fixtures retain their flattened transitive imports', async () => {
  const scripts = fileURLToPath(new URL('./', import.meta.url));
  const driver = await readFile(resolve(scripts, 'test-packed-public-query.mjs'), 'utf8');
  const pending = ['fixtures/graph-property-predicate-source-input.mjs'];
  const visited = new Set();
  while (pending.length) {
    const name = pending.pop();
    if (visited.has(name)) continue;
    visited.add(name);
    assert.ok(driver.includes(`['scripts/${name}', '${basename(name)}']`),
      `Packed source fixture dependency is not staged: ${name}`);
    const body = await readFile(resolve(scripts, name), 'utf8');
    for (const match of body.matchAll(/\bfrom\s+['"]([^'"]+)['"]/gu)) {
      if (!match[1].startsWith('.')) continue;
      const dependency = relative(scripts, resolve(scripts, dirname(name), match[1]));
      assert.equal(dirname(dependency), 'fixtures', 'Flattened fixture imports stay in one directory');
      pending.push(dependency);
    }
  }
});

test('packed Graph Host families have disjoint complete Local and HTTPS selections', () => {
  const profiles = ['graph','graph-projections','graph-definitions','graph-labels',
    'graph-traversal-modes','graph-traversal-selectors','presence-filter',
    'presence-selection','selector-derive','relation-subgraph','presence-keyed-distinct',
    'presence-whole-distinct','presence-group','delta-application',
    'delta-relation-composition','delta-diff','graph-union','graph-graft','graph-reach',
    'graph-shortest','graph-mean','graph-subtraction'];
  assert.equal(graphPublicHostCases.length, 46);
  assert.equal(new Set(graphPublicHostCases.map(item => item.name)).size, 46);
  for (const mode of ['local','remote']) {
    assert.deepEqual(graphPublicHostCases.filter(item => item.mode === mode)
      .map(item => item.profile).sort(), [...profiles, 'graph-mean'].sort());
    assert.deepEqual(graphPublicHostCases.filter(item => item.mode === mode && item.profile === 'graph-mean')
      .map(item => item.partition), ['basic', 'asymmetric']);
  }
  for (const {name} of graphPublicHostCases) {
    const pattern = new RegExp(graphPublicHostPattern(name), 'u');
    assert.deepEqual(graphPublicHostCases.filter(item => pattern.test(item.name))
      .map(item => item.name), [name]);
  }
  const punctuated = 'Graph (A+B) [key] $snapshot';
  assert.ok(new RegExp(graphPublicHostPattern(punctuated), 'u').test(punctuated));
});

test('finite Mean partitions retain every authored normal oracle once', async () => {
  const {graphMeanSourceOracles} = await import('./fixtures/graph-mean-source-input.mjs');
  assert.equal(graphMeanSourceOracles.length, 6);
  const groups = [graphMeanSourceOracles.slice(0, 4), graphMeanSourceOracles.slice(4)];
  assert.deepEqual(groups.map(group => group.length), [4, 2]);
  assert.deepEqual(groups.flat().map(sample => sample.name),
    graphMeanSourceOracles.map(sample => sample.name));
  const body = await readFile(new URL('./graph-public-host.test.mjs', import.meta.url), 'utf8');
  assert.ok(body.includes("test(name, {timeout:60_000}"));
  assert.ok(body.includes("partition === 'basic' ? graphMeanSourceOracles.slice(0, 4)"));
  assert.ok(body.includes('graphMeanSourceOracles.slice(4)'));
  for (const sample of ['graph-reach-json-connected-out', 'graph-shortest-json-weighted-parallel-edges']) {
    assert.ok(body.includes(sample), 'cancellation uses a positive-work operation, not the constructor');
  }
});


test('fixed-hop node predicate source controls are copied and included in normal acceptance', async () => {
  const {graphHopNodePredicateSuccesses: successes, graphHopNodePredicateRefusals: refusals}
    = await import('./fixtures/graph-hop-node-predicate-source-input.mjs');
  assert.equal(successes.length, 14);
  assert.equal(refusals.length, 8);
  assert.equal(new Set([...successes, ...refusals].map(item => item.name)).size, 22);
  const scripts = fileURLToPath(new URL('./', import.meta.url));
  const driver = await readFile(resolve(scripts, 'test-packed-public-query.mjs'), 'utf8');
  assert.ok(driver.includes("'graph-hop-node-predicate-source-input.mjs'"));
  const consumer = await readFile(resolve(scripts, 'fixtures/packed-public-query.mjs'), 'utf8');
  assert.ok(consumer.includes('scopeInputs.successes.push(...graphPropertyPredicateSuccesses, ...graphHopNodePredicateSuccesses)'));
  assert.ok(consumer.includes('scopeInputs.refusals.push(...graphPropertyPredicateRefusals, ...graphHopNodePredicateRefusals)'));
  const controls = successes.filter(item => item.format === 'json').map(item => JSON.parse(item.text));
  assert.equal(controls.length, 2);
  assert.equal(controls[0].stages[0].steps[4].traverse.hops[0].node_where.gt[1].literal, 10);
  assert.equal(controls[1].stages[0].steps[4].traverse.hops[1].node_where.eq[1].literal, 2);
});

test('any-direction Graph controls are staged and exercised in normal and focused acceptance', async () => {
  const {graphAnyDirectionSuccesses: successes, graphAnyDirectionRefusals: refusals,
    graphAnyDirectionExecutionFailures: failures, graphAnyDirectionCompleteWalk: completeWalk}
    = await import('./fixtures/graph-any-direction-source-input.mjs');
  assert.equal(successes.length, 13);
  assert.equal(refusals.length, 7);
  assert.equal(failures.length, 0);
  assert.equal(new Set([...successes, ...refusals, ...failures].map(item => item.name)).size, 20);
  assert.ok(successes.includes(completeWalk));
  assert.deepEqual(completeWalk.results.matched.rows,
    [0, ...Array(6).fill(1), ...Array(13).fill(2)].map(depth => ({depth})));
  // A lower bound from the declared JSON identity fields alone: domain CID,
  // element definition, object keys and number key type. No product meter.
  const identityText = 71 + 1 + 'definitiondomainkeykey_typeskindnumber'.length;
  const identityOccurrences = 3 + 6 * 5 + 13 * 7;
  assert.ok(identityText * identityOccurrences > 10000);
  // This storage-sized number is not a selected cumulative traversal budget.
  // The consumer law scopes max_value_bytes to each top-level value. The
  // ordinary case verifies every complete Result row; explicit output limits
  // are covered through the existing Core traversal limit argument.
  const capacity = JSON.parse(await readFile(new URL('../spec/contracts/actql-consumer-capacity.json', import.meta.url), 'utf8'));
  assert.ok(capacity.laws.value_scope.includes('each top-level value'));
  for (const [mode, depths] of [
    ['walk', [0, 1, 1, 2, 2, 2, 2]], ['trail', [0, 1, 1, 2, 2]], ['acyclic', [0]],
  ]) {
    const bounded = successes.find(item => item.name === 'graph-any-direction-bounded-' + mode);
    assert.deepEqual(bounded.results.matched.rows, depths.map(depth => ({depth})));
    assert.deepEqual(bounded.parameters.edges,
      [{key: 10, src: 1, dst: 1}, {key: 11, src: 1, dst: 1}]);
  }
  const scripts = fileURLToPath(new URL('./', import.meta.url));
  const driver = await readFile(resolve(scripts, 'test-packed-public-query.mjs'), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/graph-any-direction-source-input.mjs', 'graph-any-direction-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_ANY_DIRECTION_ONLY = '1'"));
  const consumer = await readFile(resolve(scripts, 'fixtures/packed-public-query.mjs'), 'utf8');
  assert.ok(consumer.includes('scopeInputs.successes.push(...graphAnyDirectionSuccesses)'));
  assert.ok(consumer.includes('scopeInputs.refusals.push(...graphAnyDirectionRefusals)'));
  assert.ok(consumer.includes('scopeInputs.executionFailures.push(...graphAnyDirectionExecutionFailures)'));
  const scopeOnly = /const scopeOnly = ([^\n]+);/u.exec(consumer)?.[1];
  assert.ok(scopeOnly?.split(/\s+\|\|\s+/u).includes('graphAnyDirectionOnly'));
  const controls = successes.filter(item => item.format === 'json').map(item => JSON.parse(item.text));
  assert.equal(controls[0].stages[0].steps[4].traverse.hops[0].direction, 'both');
  assert.equal(controls[1].stages[0].steps[4].traverse.direction, 'both');
  assert.equal(controls[1].stages[0].steps[4].traverse.path_mode, 'trail');
});

test('abbreviated edge controls preserve unfiltered keyed multiplicity and normal acceptance', async () => {
  const {graphAbbreviatedSuccesses: successes, graphAbbreviatedRefusals: refusals}
    = await import('./fixtures/graph-abbreviated-edge-source-input.mjs');
  assert.equal(successes.length, 17);
  assert.equal(refusals.length, 8);
  assert.equal(new Set([...successes, ...refusals].map(item => item.name)).size, 25);
  for (const [direction, count] of [['out', 4], ['in', 2], ['both', 5]]) {
    const control = successes.find(item => item.name === 'graph-abbreviated-json-' + direction);
    const program = JSON.parse(control.text);
    const hop = program.stages[0].steps[5].traverse.hops[0];
    assert.deepEqual(hop, {direction});
    assert.deepEqual(program.stages[0].steps[3].graph.edges.map(edge => edge.labels[0].name), ['R', 'S']);
    assert.deepEqual(control.results.matched.rows, Array.from({length: count}, () => ({depth: 1})));
    for (const form of [direction, 'full-' + direction]) {
      assert.deepEqual(successes.find(item => item.name === 'graph-abbreviated-' + form).results,
        control.results);
    }
  }
  const scripts = fileURLToPath(new URL('./', import.meta.url));
  const driver = await readFile(resolve(scripts, 'test-packed-public-query.mjs'), 'utf8');
  assert.ok(driver.includes("['scripts/fixtures/graph-abbreviated-edge-source-input.mjs', 'graph-abbreviated-edge-source-input.mjs']"));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_ABBREVIATED_ONLY = '1'"));
  const consumer = await readFile(resolve(scripts, 'fixtures/packed-public-query.mjs'), 'utf8');
  assert.ok(consumer.includes('scopeInputs.successes.push(...graphAbbreviatedSuccesses)'));
  assert.ok(consumer.includes('scopeInputs.refusals.push(...graphAbbreviatedRefusals)'));
  assert.ok(consumer.includes('graphAbbreviatedOnly ? {successes: graphAbbreviatedSuccesses, refusals: graphAbbreviatedRefusals}'));
});

test('finite quantifier source and JSON controls retain exact bounds and transitive staging', async () => {
  const {graphQuantifierFormsSuccesses: successes, graphQuantifierFormsRefusals: refusals}
    = await import('./fixtures/graph-quantifier-forms-source-input.mjs');
  assert.equal(successes.length, 11);
  assert.equal(refusals.length, 9);
  assert.equal(new Set([...successes, ...refusals].map(item => item.name)).size, 20);
  const controls = successes.filter(item => item.format === 'json').map(item => JSON.parse(item.text));
  assert.deepEqual(controls.map(item => {
    const t = item.stages[0].steps[5].traverse;
    return [t.min_hops, t.max_hops, t.path_mode];
  }), [[2, 2, 'walk'], [0, 2, 'walk']]);
  assert.deepEqual(successes.find(item => item.name === 'graph-quantifier-fixed-trail').results.matched.rows,
    [{depth: 2}, {depth: 2}]);
  assert.deepEqual(successes.find(item => item.name === 'graph-quantifier-fixed-acyclic-empty').results.matched,
    {rows: [], columns: [{name: 'depth', contract: {type: 'number', nullable: false}}]});
  assert.deepEqual(successes.find(item => item.name === 'graph-quantifier-full-label-fixed').results.matched.rows,
    [{depth: 2}]);
  const scripts = fileURLToPath(new URL('./', import.meta.url));
  const driver = await readFile(resolve(scripts, 'test-packed-public-query.mjs'), 'utf8');
  for (const name of ['graph-quantifier-forms-source-input.mjs', 'graph-abbreviated-edge-source-input.mjs']) {
    assert.ok(driver.includes(`['scripts/fixtures/${name}', '${name}']`));
  }
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_QUANTIFIER_FORMS_ONLY = '1'"));
  const consumer = await readFile(resolve(scripts, 'fixtures/packed-public-query.mjs'), 'utf8');
  assert.ok(consumer.includes('scopeInputs.successes.push(...graphQuantifierFormsSuccesses)'));
  assert.ok(consumer.includes('scopeInputs.refusals.push(...graphQuantifierFormsRefusals)'));
  assert.ok(consumer.includes('graphQuantifierFormsOnly ? {successes: graphQuantifierFormsSuccesses, refusals: graphQuantifierFormsRefusals}'));
});
