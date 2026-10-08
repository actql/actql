import assert from 'node:assert/strict';
import { clone, generate, oracle } from './engine.mjs';
import {corpusFoundations} from './registry.mjs';

const methods = ['enabled', 'admits', 'generate', 'contract', 'syntax', 'oracle', 'shrinks'];
export function checkRegistration(registry, registrations) {
  assert.equal(new Set(registry.map(d => d.name)).size, registry.length, 'Duplicate operation registration');
  for (const descriptor of registry) {
    for (const method of methods) assert.equal(typeof descriptor[method], 'function', `${descriptor.name}: missing ${method}`);
    const entry = registrations[descriptor.name];
    assert(entry?.variant && entry?.route && entry?.obligations?.length, `${descriptor.name}: missing variant, route or obligations`);
    const ids = new Set();
    for (const obligation of entry.obligations) {
      assert(obligation.id && typeof obligation.holds === 'function', `${descriptor.name}: invalid obligation`);
      assert(!ids.has(obligation.id), `${descriptor.name}: duplicate obligation`);
      ids.add(obligation.id);
    }
  }
}

export function coverage(cases, registry, registrations) {
  checkRegistration(registry, registrations);
  const traces = cases.map(testCase => ({ testCase, expected: oracle(testCase, registry) }));
  const result = {};
  for (const descriptor of registry) for (const obligation of registrations[descriptor.name].obligations) {
    const id = `${descriptor.name}:${obligation.id}`;
    const witnesses = traces.filter(trace => obligation.holds(trace)).map(trace => trace.testCase.id);
    assert(witnesses.length > 0, `Missing concrete semantic obligation ${id}`);
    result[id] = witnesses;
  }
  return result;
}

// Deterministic completion searches the same typed generator used for exploration.
// It adds only cases which discharge a missing predicate, never a labelled pair
// or a per-operation handwritten pipeline. Failure to find a witness is fatal.
function completeCorpus(registry, registrations) {
  checkRegistration(registry, registrations);
  const cases = generate(registry);
  const obligations = registry.flatMap(d => registrations[d.name].obligations);
  const traces = cases.map(testCase => ({ testCase, expected: oracle(testCase, registry) }));
  let pending = obligations.filter(o => !traces.some(trace => o.holds(trace)));
  for (let seed = 1; seed <= 256 && pending.length; seed++) {
    for (const candidate of generate(registry, seed, 24)) {
      const expected = oracle(candidate, registry);
      const trace = { testCase: candidate, expected };
      if (pending.some(o => o.holds(trace))) {
        const value = clone(candidate);
        value.id = `completion:${seed}:${candidate.id}`;
        cases.push(value);
        pending = pending.filter(o => !o.holds(trace));
      }
    }
  }
  coverage(cases, registry, registrations);
  return cases;
}

const extendsRegistry = (before, after) => before.length < after.length &&
  before.every((descriptor, index) => after[index] === descriptor);
export function fixedCorpus(registry, registrations, foundations = corpusFoundations) {
  assert(Array.isArray(foundations) && foundations.every((foundation, index) =>
    Array.isArray(foundation) && foundation.length > 0 &&
    (index === 0 || extendsRegistry(foundations[index - 1], foundation))),
  'Corpus foundations must be ordered strict registry prefixes');
  const prior = foundations.filter(foundation => extendsRegistry(foundation, registry));
  if (!prior.length) return completeCorpus(registry, registrations);
  let previous = prior[0];
  const retained = completeCorpus(previous, registrations);
  for (const next of [...prior.slice(1), registry]) {
    const current = completeCorpus(next, registrations);
    const previousNames = new Set(previous.map(descriptor => descriptor.name));
    const sameCase = value => JSON.stringify({rows: value.rows, steps: value.steps});
    const contents = new Set(retained.map(sameCase)), ids = new Set(retained.map(value => value.id));
    for (const candidate of current) {
      if (candidate.steps.every(step => previousNames.has(step.op))) continue;
      if (contents.has(sameCase(candidate))) continue;
      const value = clone(candidate);
      while (ids.has(value.id)) value.id = `extension:${value.id}`;
      retained.push(value); ids.add(value.id); contents.add(sameCase(value));
    }
    coverage(retained, next, registrations);
    previous = next;
  }
  return retained;
}
