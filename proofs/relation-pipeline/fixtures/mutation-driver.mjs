// Instrumented dependencies for mutations.test.mjs; no product result is mocked
// in the actual pipeline gate. Keep this file out of the *.test.mjs glob.
import assert from 'node:assert/strict';
import { mock } from 'node:test';
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
const [mode, root, { required, fail }] = [process.argv[2], process.argv[3], JSON.parse(process.argv[4])];
const directory = join(root, '.artifacts/relation-pipeline');
mkdirSync(directory, { recursive: true });
mkdirSync(join(root, 'proofs/relation-pipeline'), { recursive: true });
writeFileSync(join(root, 'source.mbt'), 'healthy');
const source = () => readFileSync(join(root, 'source.mbt'), 'utf8');
const hash = value => createHash('sha256').update(value).digest('hex');
const snapshot = () => ({ digest: hash(source()), sources: { 'source.mbt': hash(source()) } });
const testCase = { id: 'case', rows: [{}], steps: [{}] };
const variants = ['first', 'second'].map(name => ({ name, path: 'source.mbt', eligible: () => true,
  anchor: () => ({ name }), preserves: (_case, actual, anchor) => actual.source === anchor.name }));
writeFileSync(join(root, 'proofs/relation-pipeline/regressions.json'), JSON.stringify(
  variants.map(({ name }) => ({ name, testCase, anchor: { name } }))));
const calls = [], executions = [];
const module = (path, namedExports) => mock.module(new URL(`../${path}`, import.meta.url).href, { namedExports });
module('sites.mjs', { applyMutation: (_source, variant) => variant.name });
module('mutation-registry.mjs', { variants });
module('corpus.mjs', { fixedCorpus: () => [testCase] });
module('obligations.mjs', { registrations: [] });
module('registry.mjs', { registry: [] });
module('inventory.mjs', { hash, snapshot, checkBaseline: () => {} });
module('exploration-impact.mjs', { decision: () => ({ required, reason: 'fixture', revision: 'a'.repeat(40) }) });
module('evidence.mjs', { compareSemantics: (_case, actual) => assert.equal(actual.source, 'healthy') });
module('engine.mjs', { shrink: async (original, _registry, execute, preserves) => {
  const observed = execute([original]);
  assert(preserves(original, observed[0]));
  return { original, minimal: original, localMinimal: true };
} });
module('execute.mjs', { root, toolchain: {}, executions,
  execute: (cases, _registry, target, correspondence, label) => {
    const variant = label.split('-')[0];
    calls.push({ variant, target, correspondence, label, source: source() });
    const occurrence = calls.filter(call => call.label === label && call.target === target).length;
    if (`${label}:${target}` === fail || `${label}:${target}:${occurrence}` === fail) {
      throw new Error('Injected execution failure');
    }
    const observations = cases.map(() => ({ source: source() }));
    executions.push({ path: `${calls.length}.json`, receipt: { target, cases: observations } });
    return observations;
  },
});
process.on('exit', () => {
  const reports = Object.fromEntries(readdirSync(directory).filter(name => name.endsWith('mutations.json'))
    .map(name => [name, JSON.parse(readFileSync(join(directory, name), 'utf8'))]));
  writeFileSync(join(root, 'state.json'), JSON.stringify({ source: source(), calls, reports }));
});
process.argv[2] = mode;
await import('../mutations.mjs');
