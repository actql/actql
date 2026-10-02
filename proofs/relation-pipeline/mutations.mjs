import { applyMutation } from './sites.mjs';
import { variants } from './mutation-registry.mjs';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { shrink } from './engine.mjs';
import { fixedCorpus } from './corpus.mjs';
import { registrations } from './obligations.mjs';
import { registry } from './registry.mjs';
import { execute, executions, root, toolchain } from './execute.mjs';
import { hash, snapshot, checkBaseline } from './inventory.mjs';
import { compareSemantics } from './evidence.mjs';
import { decision } from './exploration-impact.mjs';
const mode = process.argv[2] ?? 'explore';
assert(['fixed', 'explore', 'auto', 'verify'].includes(mode));
const impact = decision(root);
writeFileSync(join(root, '.artifacts/relation-pipeline/exploration-decision.json'), JSON.stringify(impact, null, 2) + '\n');
if (mode === 'auto' && !impact.required) {
  console.log(`Fresh exploration skipped: ${impact.reason}`);
  process.exit(0);
}
// Keep both obligations distinct, but visit each mutated source only once.
// Every replay still invokes Moon and records fresh observations. Only the
// unchanged incremental build is reused; no receipt or passing log is reused.
const modes = mode === 'verify' ? (impact.required ? ['fixed', 'explore'] : ['fixed'])
  : [mode === 'fixed' ? 'fixed' : 'explore'];
const source = snapshot(root);
checkBaseline(root);
const cases = fixedCorpus(registry, registrations);
const regressions = JSON.parse(readFileSync(join(root, 'proofs/relation-pipeline/regressions.json')));
assert.deepEqual(regressions.map(r => r.name), variants.map(v => v.name));
const results = Object.fromEntries(modes.map(mode => [mode, []]));
for (const variant of variants) {
  const path = join(root, variant.path);
  const original = readFileSync(path, 'utf8');
  const mutated = applyMutation(original, variant);
  const witnesses = [];
  const preserves = (c, o, a) => variant.eligible(c) && variant.preserves(c, o, a, registry);
  try {
    writeFileSync(path, mutated);
    for (const selectedMode of modes) {
      const exploratory = selectedMode === 'explore';
      const start = executions.length;
      const timing = {};
      let chosen, minimized;
      if (exploratory) {
        const searchCases = cases.filter(variant.eligible);
        assert(searchCases.length, `Empty reviewed search domain ${variant.name}`);
        let began = performance.now();
        const observations = execute(searchCases, registry, 'js', false, `${variant.name}-search`);
        timing.searchMs = performance.now() - began;
        const available = searchCases.map((testCase, i) => ({ testCase, observed: observations[i], anchor: variant.anchor(testCase, observations[i], registry) }))
          .filter(x => x.anchor && preserves(x.testCase, x.observed, x.anchor))
          .sort((a, b) => (b.testCase.steps.length + b.testCase.rows.length) - (a.testCase.steps.length + a.testCase.rows.length));
        assert(available.length, `No real detection of ${variant.name}`);
        chosen = available[0];
        began = performance.now();
        minimized = await shrink(chosen.testCase, registry,
          values => execute(values, registry, 'js', false, `${variant.name}-shrink`),
          (c, o) => preserves(c, o, chosen.anchor));
        timing.shrinkMs = performance.now() - began;
      } else {
        const fixed = regressions.find(r => r.name === variant.name);
        chosen = { testCase: fixed.testCase, anchor: fixed.anchor };
        minimized = { original: fixed.testCase, minimal: fixed.testCase, localMinimal: false };
      }
      const replay = {};
      timing.mutatedReplayMs = {};
      for (const target of ['js', 'wasm', 'native']) {
        const began = performance.now();
        const actual = execute([minimized.minimal], registry, target, false, `${variant.name}-${exploratory ? 'minimal' : 'fixed'}`)[0];
        assert(preserves(minimized.minimal, actual, chosen.anchor), `${variant.name}: missing ${target} detection`);
        replay[target] = actual;
        timing.mutatedReplayMs[target] = performance.now() - began;
      }
      const witness = { name: variant.name, site: variant.path, originalDigest: hash(original), mutatedDigest: hash(mutated),
        source: snapshot(root), anchor: chosen.anchor, ...minimized, replay, killed: true,
        executions: executions.slice(start) };
      witnesses.push({ selectedMode, witness, timing });
    }
  } finally {
    writeFileSync(path, original);
    assert.equal(snapshot(root).digest, source.digest, 'Source not restored exactly');
  }
  for (const { selectedMode, witness, timing } of witnesses) {
    const exploratory = selectedMode === 'explore';
    const healthy = {};
    timing.restoredReplayMs = {};
    const healthyStart = executions.length;
    for (const target of ['js', 'wasm', 'native']) {
      const began = performance.now();
      const actual = execute([witness.minimal], registry, target, true, `${variant.name}-restored`)[0];
      compareSemantics(witness.minimal, actual, registry);
      assert(!preserves(witness.minimal, actual, witness.anchor));
      healthy[target] = actual;
      timing.restoredReplayMs[target] = performance.now() - began;
    }
    results[selectedMode].push({ ...witness, timing, healthy, healthyExecutions: executions.slice(healthyStart) });
    console.log(`${variant.name}: ${exploratory ? 'fresh JS search and local-minimum shrink' : 'fixed regression replay; no fresh search/minimality claim'}; actual mutated/restored replay on 3 targets`);
  }
}
for (const selectedMode of modes) {
  const exploratory = selectedMode === 'explore';
  writeFileSync(join(root, `.artifacts/relation-pipeline/${exploratory ? 'mutations' : 'fixed-mutations'}.json`), JSON.stringify({
    version: 'actql-relation-pipeline-mutations/0.1', source, revision: impact.revision, toolchain,
    mode: exploratory ? 'explore' : 'fixed', decision: impact, seed: exploratory ? 105106 : null,
    explorationTarget: exploratory ? 'js' : null, searchDomain: 'fixed typed corpus filtered by reviewed mutation eligibility',
    meaning: 'known-site anchored mismatches; local minimum only under enumerated reductions and same anchor', results: results[selectedMode],
  }, null, 2) + '\n');
}
