import test from 'node:test';
import assert from 'node:assert/strict';
import { registry } from './registry.mjs';
import { registrations } from './obligations.mjs';
import { fixedCorpus, coverage, checkRegistration } from './corpus.mjs';
import { classify } from './exploration-impact.mjs';
const cases = fixedCorpus(registry, registrations);
test('fixed corpus satisfies concrete predicates, including completion independent of random luck', () => {
  assert.deepEqual(fixedCorpus(registry, registrations), cases);
  assert(cases.some(c => c.id.startsWith('completion:')));
  assert(coverage(cases, registry, registrations)['rename:swap different values and nullability'].length > 0);
});
test('a tag, operation pair or empty fake witness cannot replace a concrete obligation', () => {
  const empty = cases.map(c => ({ ...c, rows: [], obligations: Object.keys(coverage(cases, registry, registrations)) }));
  assert.throws(() => coverage(empty, registry, registrations), /Missing concrete/);
  const complete = coverage(cases, registry, registrations);
  const witnesses = complete['rename:new name is referenced downstream'];
  assert.throws(() => coverage(cases.filter(c => !witnesses.includes(c.id)), registry, registrations), /new name/);
});
test('incomplete registration is rejected with the unsatisfied contract', () => {
  assert.throws(() => checkRegistration([{ ...registry[0], oracle: null }], registrations), /filter: missing oracle/);
  assert.throws(() => checkRegistration(registry, { ...registrations, rename: undefined }), /rename: missing/);
});
test('impact includes assumptions, unknown paths and diff failures', () => {
  for (const path of ['src/bounded_execution/session.mbt', 'src/relation_typing/check.mbt', 'package-lock.json',
    'toolchain.json', '.github/workflows/ci.yml', 'new-path', 'proofs/relation-pipeline/rename.mjs']) assert(classify([path]).required);
  assert(classify([], 'missing base').required);
  assert(classify([]).required);
  assert.equal(classify(['README.md']).required, false);
});
