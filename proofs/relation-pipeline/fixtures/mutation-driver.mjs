// Instrumented dependencies for mutations.test.mjs; no product result is mocked
// in the actual pipeline gate. Keep this file out of the *.test.mjs glob.
import assert from 'node:assert/strict';
import { mock } from 'node:test';
import { copyFileSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
const [mode, root, { required, fail }] = [process.argv[2], process.argv[3], JSON.parse(process.argv[4])];
const directory = join(root, '.artifacts/relation-pipeline');
mkdirSync(directory, { recursive: true });
mkdirSync(join(root, 'proofs/relation-pipeline'), { recursive: true });
writeFileSync(join(root, 'source.mbt'), 'healthy');
const source = (directory = root) => readFileSync(join(directory, 'source.mbt'), 'utf8');
const hash = value => createHash('sha256').update(value).digest('hex');
const snapshot = (directory = root) => ({ digest: hash(source(directory)), sources: { 'source.mbt': hash(source(directory)) } });
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
  createExecutor: workspace => ({ close() {}, execute: (cases, _registry, target, correspondence, label) => {
    const variant = label.split('-')[0];
    calls.push({ variant, target, correspondence, label, source: source(workspace.root), workspace: workspace.role });
    const occurrence = calls.filter(call => call.label === label && call.target === target).length;
    if (`${label}:${target}` === fail || `${label}:${target}:${occurrence}` === fail) {
      throw new Error('Injected execution failure');
    }
    if (fail === 'source-restore' && label === 'first-minimal' && target === 'native') {
      writeFileSync(join(workspace.root, 'contamination'), 'unrestored source');
    }
    const observations = cases.map(() => ({ source: source(workspace.root) }));
    executions.push({ path: `${calls.length}.json`, receipt: { target, cases: observations } });
    return observations;
  } }),
});
module('workspaces.mjs', { mutationWorkspaces: async () => {
  const make = role => {
    const directory = join(root, role); mkdirSync(directory);
    copyFileSync(join(root, 'source.mbt'), join(directory, 'source.mbt'));
    return { root: directory, role, check: () => {
      assert(!readdirSync(directory).includes('contamination'), 'Source not restored exactly');
      return snapshot(directory);
    } };
  };
  const pristine = make('pristine'), mutable = make('mutable');
  return { pristine, mutable, evidence: { pristine: { id: 'healthy' }, mutable: { id: 'mutant' } },
    passed() { assert.equal(source(mutable.root), 'healthy'); assert.equal(source(pristine.root), 'healthy'); } };
} });
process.on('exit', () => {
  const reports = Object.fromEntries(readdirSync(directory).filter(name => name.endsWith('mutations.json'))
    .map(name => [name, JSON.parse(readFileSync(join(directory, name), 'utf8'))]));
  writeFileSync(join(root, 'state.json'), JSON.stringify({ source: source(), mutable: (() => { try { return source(join(root, 'mutable')); } catch { return null; } })(), calls, reports }));
});
process.argv[2] = mode;
await import('../mutations.mjs');
