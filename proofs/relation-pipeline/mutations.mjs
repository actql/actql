import { sites, applyMutation } from './sites.mjs';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { generate, shrink } from './engine.mjs';
import { registry } from './registry.mjs';
import { execute, executions, root } from './execute.mjs';
import { hash, snapshot, checkBaseline } from './inventory.mjs';
import { connectionAnchor, connectionMismatch, orderAnchor, orderMismatch } from './mismatch.mjs';
import { compareSemantics } from './evidence.mjs';
const source = snapshot(root);
checkBaseline(root);
const cases = generate(registry);
const variants = sites.map(site => ({ ...site,
  anchor: site.name === 'handoff-wrong-port' ? c => connectionAnchor(c)
    : (c, actual) => orderAnchor(c, actual, registry),
  preserves: site.name === 'handoff-wrong-port' ? connectionMismatch
    : (c, actual, anchor) => orderMismatch(c, actual, anchor, registry),
}));
const results = [];
for (const variant of variants) {
  const path = join(root, variant.path);
  const original = readFileSync(path, 'utf8');
  const mutated = applyMutation(original, variant);
  const start = executions.length;
  let witness;
  try {
    writeFileSync(path, mutated);
    const observations = execute(cases, registry, 'js', false, `${variant.name}-search`);
    // Prefer a sizeable generated example so all reduction dimensions are exercised.
    const available = cases.map((testCase, i) => ({ testCase, observed: observations[i], anchor: variant.anchor(testCase, observations[i]) }))
      .filter(x => x.anchor && variant.preserves(x.testCase, x.observed, x.anchor))
      .sort((a, b) => (b.testCase.steps.length + b.testCase.rows.length) - (a.testCase.steps.length + a.testCase.rows.length));
    assert(available.length > 0, `No real detection of ${variant.name}`);
    const chosen = available[0];
    const minimized = await shrink(chosen.testCase, registry,
      values => execute(values, registry, 'js', false, `${variant.name}-shrink`),
      (testCase, actual) => variant.preserves(testCase, actual, chosen.anchor));
    // Exact shrunk cases are actually replayed on each target under this source.
    // This is finite reproduction, not transferring a JS mutation guarantee.
    const replay = {};
    for (const target of ['js', 'wasm', 'native']) {
      const actual = execute([minimized.minimal], registry, target, false, `${variant.name}-minimal`)[0];
      assert(variant.preserves(minimized.minimal, actual, chosen.anchor));
      replay[target] = actual;
    }
    witness = { name: variant.name, site: variant.path, originalDigest: hash(original), mutatedDigest: hash(mutated),
      source: snapshot(root), anchor: chosen.anchor, ...minimized, replay, killed: true,
      executions: executions.slice(start) };
  } finally {
    writeFileSync(path, original);
    assert.equal(snapshot(root).digest, source.digest, 'Source not restored exactly');
  }
  const healthy = {};
  const healthyStart = executions.length;
  for (const target of ['js', 'wasm', 'native']) {
    const actual = execute([witness.minimal], registry, target, true, `${variant.name}-restored`)[0];
    compareSemantics(witness.minimal, actual, registry);
    assert(!variant.preserves(witness.minimal, actual, witness.anchor));
    healthy[target] = actual;
  }
  results.push({ ...witness, healthy, healthyExecutions: executions.slice(healthyStart) });
  console.log(`${variant.name}: actual JS search detection; ${witness.original.steps.length}/${witness.original.rows.length} -> ${witness.minimal.steps.length}/${witness.minimal.rows.length} steps/rows; locally minimal; mutated/restored replay on 3 targets`);
}
writeFileSync(join(root, '.artifacts/relation-pipeline/mutations.json'), JSON.stringify({
  version: 'actql-relation-pipeline-mutations/0.1', source, seed: 105106,
  explorationTarget: 'js', meaning: 'known-site anchored mismatches; minimum only under enumerated reductions', results,
}, null, 2) + '\n');
