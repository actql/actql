import test from 'node:test';
import assert from 'node:assert/strict';
import { registry, corpusFoundations } from './registry.mjs';
import {createHash} from 'node:crypto';
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
test('future registry additions retain every accepted corpus stage and obligation', () => {
  // This is a generator fixture, not a new product operation or runtime claim.
  const fixture = {...registry.find(value => value.name === 'take'), name: 'test-extension'};
  const next = [...registry, fixture];
  const entries = {...registrations, [fixture.name]: {variant: 'generator-only fixture', route: 'Take',
    obligations: [{id: 'actual stage does not expand rows', holds: trace => trace.expected.stages.some(stage =>
      stage.operation === fixture.name && stage.output.length <= stage.input.length)}]}};
  const extended = fixedCorpus(next, entries);
  assert.deepEqual(extended.slice(0, cases.length), cases);
  const firstFoundationOnly = fixedCorpus(next, entries, [corpusFoundations[0]]);
  const inputs = value => JSON.stringify({rows: value.rows, steps: value.steps});
  assert(cases.slice(86).some(value => !firstFoundationOnly.some(candidate => inputs(candidate) === inputs(value))),
    'The regression must expose a lost derive input under the former one-foundation rule');
  assert.equal(cases.length, 114);
  assert.equal(createHash('sha256').update(JSON.stringify(cases)).digest('hex'),
    '9420e65ec1e80d508c740c0bc2130588a8f1a21119aa026787f1d2070a269b8f');
  assert(extended.length > cases.length);
  assert(extended.slice(cases.length).every(value => value.steps.some(step => step.op === fixture.name)));
  assert.equal(new Set(extended.map(value => value.id)).size, extended.length);
  const obligations = coverage(extended, next, entries);
  assert(Object.keys(coverage(cases, registry, registrations)).every(id => obligations[id].length > 0));
  assert(obligations[`${fixture.name}:actual stage does not expand rows`].length > 0);
  const later = {...fixture, name: 'test-later-extension'};
  const laterEntries = {...entries, [later.name]: {variant: 'later generator-only fixture', route: 'Take',
    obligations: [{id: 'later stage actually executes', holds: trace => trace.expected.stages.some(stage =>
      stage.operation === later.name && stage.output.length <= stage.input.length)}]}};
  const laterCases = fixedCorpus([...next, later], laterEntries, [...corpusFoundations, next]);
  assert.deepEqual(laterCases.slice(0, extended.length), extended);
  assert(laterCases.slice(extended.length).every(value => value.steps.some(step => step.op === later.name)));
});
test('corpus stage registration rejects reversed, duplicate and nonprefix histories', () => {
  for (const foundations of [[...corpusFoundations].reverse(), [registry, registry],
    [corpusFoundations[0], [registry[1], ...registry.slice(1)]]]) {
    assert.throws(() => fixedCorpus(registry, registrations, foundations), /ordered strict registry prefixes/u);
  }
});
test('impact includes assumptions, unknown paths and diff failures', () => {
  for (const path of ['src/bounded_execution/session.mbt', 'src/relation_typing/check.mbt', 'package-lock.json',
    'toolchain.json', '.github/workflows/ci.yml', 'new-path', 'proofs/relation-pipeline/rename.mjs']) assert(classify([path]).required);
  assert(classify([], 'missing base').required);
  assert(classify([]).required);
  assert.equal(classify(['README.md']).required, false);
});
