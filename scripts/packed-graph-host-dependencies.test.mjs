import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {graphPublicHostCases, graphPublicHostPattern} from './fixtures/graph-host-cases.mjs';

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

test('packed Graph Host families have disjoint complete Local and HTTPS selections', () => {
  const profiles = ['graph','graph-projections','graph-definitions','graph-labels',
    'graph-traversal-modes','graph-traversal-selectors','presence-filter',
    'presence-selection','selector-derive','relation-subgraph','presence-keyed-distinct',
    'presence-whole-distinct','presence-group','delta-application',
    'delta-relation-composition','delta-diff','graph-union','graph-subtraction'];
  assert.equal(graphPublicHostCases.length, 36);
  assert.equal(new Set(graphPublicHostCases.map(item => item.name)).size, 36);
  for (const mode of ['local','remote']) {
    assert.deepEqual(graphPublicHostCases.filter(item => item.mode === mode)
      .map(item => item.profile).sort(), [...profiles].sort());
  }
  for (const {name} of graphPublicHostCases) {
    const pattern = new RegExp(graphPublicHostPattern(name), 'u');
    assert.deepEqual(graphPublicHostCases.filter(item => pattern.test(item.name))
      .map(item => item.name), [name]);
  }
  const punctuated = 'Graph (A+B) [key] $snapshot';
  assert.ok(new RegExp(graphPublicHostPattern(punctuated), 'u').test(punctuated));
});


test('fixed-hop node predicate source controls are copied and included in normal acceptance', async () => {
  const {graphHopNodePredicateSuccesses: successes, graphHopNodePredicateRefusals: refusals}
    = await import('./fixtures/graph-hop-node-predicate-source-input.mjs');
  assert.equal(successes.length, 13);
  assert.equal(refusals.length, 8);
  assert.equal(new Set([...successes, ...refusals].map(item => item.name)).size, 21);
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
