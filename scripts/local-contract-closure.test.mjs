import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';

const read = path => JSON.parse(readFileSync(new URL('../' + path, import.meta.url), 'utf8'));
const corpus = read('portability/corpus/local-contract-closure.json');
const registry = read('spec/contracts/actql-stage-contracts.json');
const textTimeBase = read('spec/dependencies/actql-text-time-base.json');

test('the inherited text/time dependency resolves to its original pinned body', () => {
  const expected = 'sha256:2d41f38bd3bf8217d9bc394b1ca2ed9dfe6695b0088cd6a489328dabdee61dcc';
  assert.equal(read('spec/contracts/actql-expressions.json').inherited_text_time_profile_cid, expected);
  assert.equal(machineCid(textTimeBase), expected);
  assert.equal(Object.hasOwn(textTimeBase, 'contract_cid'), false);
  for (const key of ['source_schema', 'evaluation_envelope_schema', 'barrier_schema']) {
    assert.equal(machineCid(textTimeBase[key]), textTimeBase[key + '_cid']);
  }
  // A profile envelope including its own CID is not the inherited preimage.
  assert.notEqual(machineCid({...textTimeBase, contract_cid: expected}), expected);
  const changed = structuredClone(textTimeBase);
  changed.semantics.regex_flags.push('i');
  assert.notEqual(machineCid(changed), expected);
});
const schema = {
  type: 'object', properties: {
    version: {const: 'actql-local-contracts/0.1'},
    contracts: {type: 'array', items: {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'}, uniqueItems: true},
  }, required: ['version', 'contracts'], additionalProperties: false,
};

// Exact checks for this closed schema plus canonical set order, not a general
// JSON Schema interpreter and not proof of complete compiler root selection.
function admittedSet(value) {
  return value && !Array.isArray(value) && typeof value === 'object'
    && Object.keys(value).sort().join(',') === 'contracts,version'
    && value.version === schema.properties.version.const
    && Array.isArray(value.contracts)
    && value.contracts.every((cid, i, xs) => typeof cid === 'string'
      && /^sha256:[0-9a-f]{64}$/.test(cid) && (i === 0 || xs[i - 1] < cid));
}

test('local contract set schema and reference roles identify one registered preimage', () => {
  assert.deepEqual(registry.schemas.local_contracts, schema);
  assert.equal(registry.schema_cids.local_contracts, machineCid(schema));
  assert.deepEqual(registry.reference_roles.local_contracts, {'contracts/*': 'external:interpreted-contract'});
  assert.equal(registry.reference_roles.local_dependencies.local_contract_closure_cid, 'local_contracts');
  assert.equal(registry.reference_roles.local_computation.local_contracts_cid, 'local_contracts');
  for (const [source, slot] of [['local_dependencies', 'local_contract_closure_cid'], ['local_computation', 'local_contracts_cid']]) {
    assert.deepEqual(registry.reference_graph.filter(edge => edge.source === source && edge.slot === slot).map(edge => edge.target), ['local_contracts']);
  }
});

test('fixed contract set identities preserve version and canonical order without a self-CID', () => {
  assert.equal(corpus.version, 'actql-local-contract-closure-vectors/0.1');
  for (const c of corpus.cases) {
    assert.ok(admittedSet(c.envelope), c.id);
    verifyIdentity(c.envelope, c.expected_cid);
    verifyIdentity({contracts: c.envelope.contracts, version: c.envelope.version}, c.expected_cid);
  }
  for (const c of corpus.rejections) assert.ok(!admittedSet(c.value), c.id);
});

// Abstract oracle over already interpreted reference positions. It intentionally
// does not discover dependencies by recursively scanning arbitrary JSON data.
function closure(graph) {
  const reached = new Set();
  const active = new Set();
  const pins = new Map();
  const visit = name => {
    if (!Object.hasOwn(graph.edges, name) || !Object.hasOwn(corpus.handles, name)) throw new Error('missing');
    if (graph.required_kinds?.[name] && graph.required_kinds[name] !== graph.kinds?.[name]) throw new Error('kind');
    const identity = JSON.stringify(graph.identities?.[name] ?? [name, '0.1']);
    if (pins.has(identity) && pins.get(identity) !== corpus.handles[name]) throw new Error('conflict');
    pins.set(identity, corpus.handles[name]);
    if (active.has(name)) {
      if (graph.cycles !== 'allow') throw new Error('cycle');
      return;
    }
    if (reached.has(name)) return;
    active.add(name);
    for (const dependency of graph.edges[name]) visit(dependency);
    active.delete(name);
    reached.add(name);
  };
  for (const root of graph.roots) visit(root);
  return {version: 'actql-local-contracts/0.1', contracts: [...new Set([...reached].map(name => corpus.handles[name]))].sort()};
}

test('contract selection retains transitive dependencies and omits unrelated Catalog members', () => {
  for (const graph of corpus.graphs) {
    if (graph.error) assert.throws(() => closure(graph), new RegExp(graph.error), graph.id);
    else {
      const expected = corpus.cases.find(c => c.id === graph.expected);
      const actual = closure(graph);
      assert.equal(canonicalText(actual), canonicalText(expected.envelope), graph.id);
      verifyIdentity(actual, expected.expected_cid);
    }
  }
  assert.notEqual(corpus.cases[1].expected_cid, corpus.cases[2].expected_cid);
});
