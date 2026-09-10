import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { canonicalText } from './check-canonical-json.mjs';
import { checkDependencies, loadDependencies } from './check-aoa-versions.mjs';

// Small independent oracles for explicit specification examples. These neither
// execute MoonBit nor demonstrate runtime profile conformance. Expected values
// are fixed in the corpus, never generated from a product evaluator.
const read = path => JSON.parse(readFileSync(new URL('../' + path, import.meta.url), 'utf8'));
const corpus = read('portability/corpus/pure-operation-laws.json');
const fail = kind => { throw new Error(kind); };
const finite = value => Number.isFinite(value) ? value : fail('NonFinite');
const zero = value => value === 0 ? 0 : value;
const q = value => finite(Math.fround(finite(value)));
const fold = xs => xs.reduce((sum, value) => finite(sum + value), 0);
const square = xs => fold(xs.map(value => finite(value * value)));

function vector(f) {
  if (f.op.startsWith('pool_')) {
    const members = [...f.members].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
    assert.ok(members.length > 0);
    assert.equal(new Set(members.map(m => m.id)).size, members.length);
    const values = members.map(m => m.value.map(q));
    assert.ok(values.every(v => v.length === values[0].length));
    return values[0].map((_, i) => {
      const column = values.map(v => v[i]);
      const result = f.op === 'pool_max' ? column.reduce((a, b) => Math.max(a, b))
        : f.op === 'pool_mean' ? finite(fold(column) / column.length) : fold(column);
      return zero(q(result));
    });
  }
  const a = f.a.map(q);
  assert.ok(a.length > 0);
  if (f.op === 'normalize') {
    const norm = finite(Math.sqrt(square(a)));
    if (norm === 0) fail('ZeroNorm');
    return a.map(value => zero(q(finite(value / norm))));
  }
  const b = f.b.map(q);
  assert.equal(a.length, b.length);
  if (f.op === 'l2') {
    return zero(-finite(Math.sqrt(square(a.map((value, i) => finite(value - b[i]))))));
  }
  const dot = fold(a.map((value, i) => finite(value * b[i])));
  if (f.op === 'dot') return zero(dot);
  assert.equal(f.op, 'cosine');
  const left = square(a), right = square(b);
  if (left === 0 || right === 0) return 0;
  return zero(finite(dot / finite(finite(Math.sqrt(left)) * finite(Math.sqrt(right)))));
}

function ranking(f) {
  if (f.op === 'max') return Math.max(...f.scores.filter(s => s !== null));
  assert.equal(f.op, 'weighted_sum');
  const [left, right] = f.scores.map((s, i) => finite((s ?? 0) * f.weights[i]));
  return zero(finite(left + right));
}

function windows(f) {
  const step = f.kind === 'fixed' ? f.size : f.step;
  const last = Math.floor((f.time - f.offset) / step);
  const first = Math.floor((f.time - f.offset - f.size) / step) + 1;
  const result = [];
  for (let n = first; n <= last; n++) {
    const start = f.offset + n * step;
    result.push([zero(start), zero(start + f.size)]);
  }
  return result;
}

function watermark(f) {
  let maximum;
  const result = [];
  for (const time of f.times) {
    maximum = maximum === undefined ? time : Math.max(maximum, time);
    const threshold = finite(maximum - f.max_skew);
    const late = time < threshold;
    if (late && f.policy === 'drop') continue;
    result.push([zero(threshold), late, late ? 'mark' : 'keep']);
  }
  return result;
}

function property(left, right, strategy) {
  if (strategy === 'exact_equal') {
    if (canonicalText(left) !== canonicalText(right)) fail('Conflict');
    return left;
  }
  if (left === null || right === null) fail('NullOperand');
  if (strategy.startsWith('number_')) {
    assert.equal(typeof left, 'number'); assert.equal(typeof right, 'number');
    const operations = {
      number_sum: () => left + right, number_mean: () => (left + right) / 2,
      number_min: () => Math.min(left, right), number_max: () => Math.max(left, right),
    };
    return zero(finite(operations[strategy]()));
  }
  assert.ok(Array.isArray(left) && Array.isArray(right));
  // This fixture subset uses only string members; it does not implement the
  // complete recursive typed-value ordering contract for production values.
  assert.ok([...left, ...right].every(value => typeof value === 'string'));
  const values = strategy === 'set_union' ? [...left, ...right]
    : left.filter(value => !right.includes(value));
  return [...new Set(values)].sort();
}

function graph(f) {
  const result = Object.create(null);
  const names = f.op === 'union' ? new Set([...Object.keys(f.left), ...Object.keys(f.right)]) : new Set(Object.keys(f.left));
  for (const id of names) {
    const l = Object.hasOwn(f.left, id), r = Object.hasOwn(f.right, id);
    if (!l || !r) { result[id] = l ? f.left[id] : f.right[id]; continue; }
    if (f.op === 'subtract' && Object.keys(f.merge).length === 0) {
      if (canonicalText(f.left[id]) !== canonicalText(f.right[id])) fail('Conflict');
      continue;
    }
    assert.deepEqual(Object.keys(f.left[id]).sort(), Object.keys(f.right[id]).sort());
    result[id] = Object.fromEntries(Object.keys(f.left[id]).map(key => [key,
      property(f.left[id][key], f.right[id][key], f.merge[key] ?? 'exact_equal')]));
  }
  return JSON.parse(JSON.stringify(result));
}

test('pure operation fixtures have the current version and distinct case identities', () => {
  assert.equal(corpus.version, 'actql-pure-operation-law-vectors/0.1');
  assert.equal(corpus.status, 'specification-only');
  const cases = ['vectors', 'rankings', 'windows', 'watermarks', 'graphs', 'endpoint_closure'].flatMap(k => {
    assert.ok(Array.isArray(corpus[k]) && corpus[k].length > 0);
    return corpus[k];
  });
  assert.equal(new Set(cases.map(c => c.name)).size, cases.length);
});

for (const [key, oracle] of Object.entries({vectors:vector, rankings:ranking, windows, watermarks:watermark, graphs:graph,
  endpoint_closure:f => f.remaining_edges.filter(([a, b]) => f.retained_nodes.includes(a) && f.retained_nodes.includes(b)),
})) for (const f of corpus[key]) {
  test(f.name, () => {
    if (f.error) assert.throws(() => oracle(f), error => error.message === f.error);
    else assert.deepEqual(oracle(f), f.expected);
  });
}

test('pinned laws and policy-dependent input contracts agree with the specification', () => {
  const dependencies = loadDependencies();
  checkDependencies(dependencies);
  const requirements = dependencies.contract.target_registry_requirements;
  const merge = requirements['VEC.merge_rankings'];
  assert.deepEqual(merge.policy_inputs, {
    max:{inputs:['relation','relation']}, weighted_sum:{inputs:['relation','relation']},
    rrf:{repeated_input:'relation',minimum_inputs:2},
  });
  assert.deepEqual(requirements['SGA.shortest_path'].input_alternatives, [
    ['graph'], ['graph','relation'], ['graph','relation','relation'],
  ]);
  assert.deepEqual(requirements['SGA.apply_delta'], {inputs:['graph','relation'],output:'graph'});
  assert.ok(!dependencies.contract.non_authoring_registry_operations.includes('SGA.apply_delta'));
});
