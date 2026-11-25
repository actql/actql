import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { canonicalText } from './check-canonical-json.mjs';
import { checkDependencies, loadDependencies } from './check-aoa-versions.mjs';

// Small independent oracles for explicit specification examples. These neither
// execute MoonBit nor demonstrate runtime profile conformance. Expected values
// are fixed in the corpus, never generated from a product evaluator.
type Example = {name: string; error?: string; expected?: unknown};
type Vector = {op: string; members?: {id: string; value: number[]}[]; a?: number[]; b?: number[]};
type Ranking = {op: string; scores: (number | null)[]; weights?: number[]};
type GraphId = string | number;
type GraphBounds = {nodes: GraphId[]; edges: [GraphId, GraphId][];
  bounds: {max_nodes?: number; max_edges?: number; max_degree?: number}};
type Window = {kind: string; size: number; step?: number; time: number; offset: number};
type Watermark = {times: number[]; max_skew: number; policy: string};
type GraphValue = null | number | string | string[];
type NumericStrategy = 'number_sum' | 'number_mean' | 'number_min' | 'number_max';
type Strategy = NumericStrategy | 'exact_equal' | 'set_union' | 'set_difference';
type Graph = {op: string; left: Record<string, Record<string, GraphValue>>;
  right: Record<string, Record<string, GraphValue>>; merge: Record<string, Strategy>};
type EndpointClosure = {remaining_edges: [GraphId, GraphId][]; retained_nodes: GraphId[]};
type Inputs = {vectors: Vector; rankings: Ranking; windows: Window; watermarks: Watermark;
  graphs: Graph; graph_bounds: GraphBounds; endpoint_closure: EndpointClosure};
type Examples = {[Key in keyof Inputs]: (Example & Inputs[Key])[]};
type Corpus = Examples & {version: string; status: string};
type MeanCorpus = {cases: {id: string; left: string; right: string; issue?: string; expected?: string}[]};

const read = <Value,>(path: string): Value => JSON.parse(readFileSync(new URL('../' + path, import.meta.url), 'utf8'));
const corpus = read<Corpus>('portability/corpus/pure-operation-laws.json');
const meanCorpus = read<MeanCorpus>('portability/corpus/structural-pairwise-mean.json');
test('event identity contract preserves typed equality and separates uniqueness and lowering', () => {
  assert.deepEqual(read<{event_identity_contract: unknown}>('spec/contracts/actql-aoa.json').event_identity_contract, {
    domain: 'complete_non_null_KeyComparable',
    representation: 'preserve_semantic_type_and_value',
    uniqueness: 'separate_data_validation',
    equal_time_order: {
      scalar: 'existing_type_specific_order',
      reference: 'existing_internal_identity_order',
    },
    authored_reference_order_keys: false,
    unsupported_lowering: 'reject',
    implicit_stringification: false,
    implicit_cid_substitution: false,
  });
});
const fail = (kind: string): never => { throw new Error(kind); };
const finite = (value: number) => Number.isFinite(value) ? value : fail('NonFinite');
const zero = (value: number) => value === 0 ? 0 : value;
const q = (value: number) => finite(Math.fround(finite(value)));
const fold = (xs: number[]) => xs.reduce((sum, value) => finite(sum + value), 0);
const square = (xs: number[]) => fold(xs.map(value => finite(value * value)));

function pairwiseMean(left: number, right: number) {
  finite(left);
  finite(right);
  const view = new DataView(new ArrayBuffer(8));
  const units = (value: number) => {
    view.setFloat64(0, value, false);
    const bits = view.getBigUint64(0, false);
    const exponent = Number((bits >> 52n) & 0x7ffn);
    const fraction = bits & 0x000fffffffffffffn;
    const magnitude = exponent === 0
      ? fraction : ((1n << 52n) | fraction) << BigInt(exponent - 1);
    return (bits & 0x8000000000000000n) === 0n
      ? magnitude : -magnitude;
  };
  const numerator = units(left) + units(right);
  if (numerator === 0n) return 0;
  const negative = numerator < 0n;
  const magnitude = negative ? -numerator : numerator;
  const roundEven = (value: bigint, shift: bigint) => {
    const divisor = 1n << shift;
    const quotient = value / divisor;
    const remainder = value % divisor;
    return quotient + (remainder * 2n > divisor ||
      (remainder * 2n === divisor && (quotient & 1n) !== 0n) ? 1n : 0n);
  };
  const highest = magnitude.toString(2).length - 1;
  let bits;
  if (highest < 53) {
    const fraction = roundEven(magnitude, 1n);
    bits = fraction;
  } else {
    let exponent = highest - 1075;
    let significand = roundEven(magnitude, BigInt(highest - 52));
    if (significand === (1n << 53n)) {
      significand >>= 1n;
      exponent++;
    }
    if (exponent > 1023) fail('NonFinite');
    bits = (BigInt(exponent + 1023) << 52n) |
      (significand - (1n << 52n));
  }
  if (negative) bits |= 0x8000000000000000n;
  view.setBigUint64(0, bits, false);
  return zero(view.getFloat64(0, false));
}

function vector(f: Vector) {
  if (f.op.startsWith('pool_')) {
    const members = [...f.members!].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
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
  const a = f.a!.map(q);
  assert.ok(a.length > 0);
  if (f.op === 'normalize') {
    const norm = finite(Math.sqrt(square(a)));
    if (norm === 0) fail('ZeroNorm');
    return a.map(value => zero(q(finite(value / norm))));
  }
  const b = f.b!.map(q);
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

function ranking(f: Ranking) {
  if (f.op === 'max') return Math.max(...f.scores.filter(s => s !== null));
  assert.equal(f.op, 'weighted_sum');
  const [left, right] = f.scores.map((s, i) => finite((s ?? 0) * f.weights![i]));
  return zero(finite(left + right));
}

function graphBounds(f: GraphBounds) {
  const out: {kind: string; node_id: GraphId | null; actual: number; max: number}[] = [];
  const add = (kind: string, node_id: GraphId | null, actual: number, max?: number) => {
    if (max !== undefined && actual > max) out.push({kind, node_id, actual, max});
  };
  add('nodes', null, f.nodes.length, f.bounds.max_nodes);
  add('edges', null, f.edges.length, f.bounds.max_edges);
  // These fixtures use homogeneous number or string IDs, not a generic
  // implementation of every typed identity domain or graph admission law.
  for (const id of [...f.nodes].sort((a,b) => a < b ? -1 : a > b ? 1 : 0)) {
    const degree = f.edges.reduce((n,[a,b]) => n + Number(a === id) + Number(b === id), 0);
    add('degree', id, degree, f.bounds.max_degree);
  }
  return out;
}

function windows(f: Window) {
  const step = f.kind === 'fixed' ? f.size : f.step!;
  const last = Math.floor((f.time - f.offset) / step);
  const first = Math.floor((f.time - f.offset - f.size) / step) + 1;
  const result = [];
  for (let n = first; n <= last; n++) {
    const start = f.offset + n * step;
    result.push([zero(start), zero(start + f.size)]);
  }
  return result;
}

function watermark(f: Watermark) {
  let maximum: number | undefined;
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

function property(left: GraphValue, right: GraphValue, strategy: Strategy) {
  if (strategy === 'exact_equal') {
    if (canonicalText(left) !== canonicalText(right)) fail('Conflict');
    return left;
  }
  if (left === null || right === null) fail('NullOperand');
  if (strategy.startsWith('number_')) {
    assert.equal(typeof left, 'number'); assert.equal(typeof right, 'number');
    const operations = {
      number_sum: () => (left as number) + (right as number), number_mean: () => pairwiseMean(left as number, right as number),
      number_min: () => Math.min(left as number, right as number), number_max: () => Math.max(left as number, right as number),
    };
    return zero(finite(operations[strategy as NumericStrategy]()));
  }
  assert.ok(Array.isArray(left) && Array.isArray(right));
  // This fixture subset uses only string members; it does not implement the
  // complete recursive typed-value ordering contract for production values.
  assert.ok([...left, ...right].every(value => typeof value === 'string'));
  const values = strategy === 'set_union' ? [...left, ...right]
    : left.filter(value => !right.includes(value));
  return [...new Set(values)].sort();
}

function graph(f: Graph) {
  const result: Record<string, Record<string, GraphValue>> = Object.create(null);
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
  const cases = (['vectors', 'rankings', 'windows', 'watermarks', 'graphs', 'endpoint_closure', 'graph_bounds'] as const).flatMap<Example>(k => {
    assert.ok(Array.isArray(corpus[k]) && corpus[k].length > 0);
    return corpus[k];
  });
  assert.equal(new Set(cases.map(c => c.name)).size, cases.length);
});

test('pure operation mean oracle agrees with independent binary64 vectors', () => {
  const view = new DataView(new ArrayBuffer(8));
  const decode = (hex: string) => {
    view.setBigUint64(0, BigInt(`0x${hex}`), false);
    return view.getFloat64(0, false);
  };
  const encode = (value: number) => {
    view.setFloat64(0, value, false);
    return view.getBigUint64(0, false).toString(16).padStart(16, '0');
  };
  for (const vector of meanCorpus.cases) {
    const left = decode(vector.left);
    const right = decode(vector.right);
    if (vector.issue) {
      assert.throws(() => pairwiseMean(left, right), {
        message: vector.issue,
      }, vector.id);
    } else {
      assert.equal(encode(pairwiseMean(left, right)), vector.expected, vector.id);
    }
  }
});

// Each oracle and its input array are selected through the same corpus key.
for (const [key, oracle] of Object.entries({vectors:vector, rankings:ranking, windows, watermarks:watermark, graphs:graph, graph_bounds:graphBounds,
  endpoint_closure:f => f.remaining_edges.filter(([a, b]) => f.retained_nodes.includes(a) && f.retained_nodes.includes(b)),
} satisfies {[Key in keyof Inputs]: (fixture: Inputs[Key]) => unknown}) as
  [keyof Inputs, (fixture: Inputs[keyof Inputs]) => unknown][]) for (const f of corpus[key]) {
  test(f.name, () => {
    if (f.error) assert.throws(() => oracle(f), error => (error as Error).message === f.error);
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
