import test from 'node:test';
import assert from 'node:assert/strict';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {canonicalJson as dataJson} from '../../packages/sdk/host-port.mjs';
import {installedEnvironmentParseConstructionGeometry as parseGeometry,
  installedEnvironmentDocumentConstructionGeometry as documentGeometry,
  installedEnvironmentDocumentConstructionStages as documentStages,
  installedEnvironmentDataWriterConstructionGeometry as dataWriterGeometry,
  installedEnvironmentMemberSortConstructionGeometry as memberSortGeometry,
  installedEnvironmentCompositionConstructionGeometry as compositionGeometry}
  from './installed-check-environment-construction.mjs';
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const item of Object.values(value)) freeze(item);
    Object.freeze(value);
  }
  return value;
};
const base = () => ({version: 'actql-check-environment/0.1', host_policy_profile: {},
  command_contracts: [], connector_capabilities: [], connector_catalogs: [],
  contract_registry: [], mapping_contracts: [], model_task_contracts: [],
  schema_snapshots: [], source_views: []});
const additive = q => {
  for (const field of ['nodes', 'text', 'wire']) {
    assert.equal(q[field], q.retained[field] + q.workspace[field]);
    assert.ok(q[field] >= 0n);
  }
};

test('data-key Environment writer quotes actual recursive overlap without normalizing original text', () => {
  for (const value of [null, 12.5, Number.MAX_VALUE, 'e\u0301日本語😀\\"\n',
    {['e\u0301']: ['日本語😀', 1, {escaped: '\\"\n'}]},
    Array.from({length: 2000}, (_, index) => ({index, name: 'borrowed'}))]) {
    freeze(value);
    const wire = dataJson(value, {dataKeys: true}), quote = dataWriterGeometry(value, true);
    additive(quote);
    assert.ok(quote.workspace.wire >= BigInt(Buffer.byteLength(wire)) + 128n);
    assert.ok(quote.workspace.text >= 2n * BigInt(wire.length));
  }
  const rows = freeze(Array.from({length: 2000}, (_, index) => ({index})));
  const one = memberSortGeometry(rows.slice(0, 1)), many = memberSortGeometry(rows);
  assert.equal(many.workspace.nodes - one.workspace.nodes, 1999n,
    'only actual sort slots grow; each synchronous comparator has returned');
  assert.equal(many.workspace.text, one.workspace.text);
});

test('native Environment parse keeps opaque string punctuation in text demand rather than value nodes', () => {
  const small = parseGeometry('{"payload":"text"}');
  const large = parseGeometry(JSON.stringify({payload: '[{:,,]}\\"'.repeat(10000)}));
  assert.equal(large.bounds.inputNodes, small.bounds.inputNodes);
  assert.ok(large.retained.text > small.retained.text);
  assert.ok(large.workspace.text > small.workspace.text);
  assert.deepEqual(JSON.parse('{"payload":"text"}'), {payload: 'text'});
});

test('closed Environment verification stages retain shared children once and preserve original constructors', () => {
  const make = count => {
    const body = {...base(), notes: {value: 'e\u0301日本語😀'}, values: Array.from({length: count}, (_, index) => index)};
    return freeze({...body, evidence_bundle_cid: contentCid(body)});
  };
  const small = documentStages(make(1)), largeDocument = make(2000), large = documentStages(largeDocument);
  assert.equal(large.body.retained.nodes, small.body.retained.nodes,
    'the same parsed children remain with their existing parse owner');
  assert.ok(large.body.workspace.nodes > small.body.workspace.nodes);
  for (const stage of [large.comparison, large.body]) additive(stage);
  assert.equal(canonicalJson(largeDocument), canonicalJson(JSON.parse(canonicalJson(largeDocument))));
  const {evidence_bundle_cid: expected, ...body} = largeDocument;
  assert.equal(contentCid(body), expected);
});

test('Environment parse quotes malformed and large prefixes before parse/freeze', () => {
  for (const original of ['', '{', '{"x":[', '[0,'.repeat(10000), '"' + 'x'.repeat(100000)]) {
    const q = parseGeometry(original);
    additive(q); assert.ok(q.nodes > 0n);
    assert.ok(q.text >= 12n * BigInt(original.length));
    assert.equal(q.bounds.inputUnits, BigInt(original.length));
  }
});

test('document verification funds NFC keys and values, escaping and numerical width', () => {
  for (const text of ['ascii', 'e\u0301', '\u0344', '\ud834\udd60', '\\"\n\u0001', '日本語😀']) {
    const body = {...base(), notes: {[text]: text}, number: Number.MAX_VALUE};
    const document = freeze({...body, evidence_bundle_cid: contentCid(body)});
    const q = documentGeometry(document);
    additive(q);
    assert.ok(q.bounds.canonicalWireUnits >= BigInt(canonicalJson(document).length));
    assert.ok(q.wire >= BigInt(Buffer.byteLength(canonicalJson(body))) + 128n);
    assert.equal(q.bounds.nativeAdmissionIncluded, false);
  }
});

test('immutable quotes never parse stringify normalize or hash original data', () => {
  const document = freeze({...base(), evidence_bundle_cid: 'cid'});
  const body = freeze(base());
  const parse = JSON.parse, stringify = JSON.stringify, normalize = String.prototype.normalize;
  JSON.parse = JSON.stringify = String.prototype.normalize = () => {throw new Error('constructor during quote');};
  try {
    parseGeometry('{"x":'); documentGeometry(document);
    compositionGeometry(body, body, body);
  } finally {JSON.parse = parse; JSON.stringify = stringify; String.prototype.normalize = normalize;}
});

test('composition co-counts repeated members before dedup and bounds merged output', () => {
  const b = freeze(base());
  const member = {source_ref: 'same', read_mode: 'rows', payload: 'x'.repeat(100)};
  const left = freeze({...base(), source_views: [member], connector_manifest: {version: 'v', connectors: [{connector_id: 'a'}]}});
  const right = freeze({...base(), source_views: [member], connector_manifest: {version: 'v', connectors: [{connector_id: 'a'}]}});
  const q = compositionGeometry(b, left, right);
  additive(q); assert.equal(q.bounds.members, 2n);
  assert.equal(q.bounds.merged, true);
  const actual = {...base(), source_views: [member], connector_manifest: left.connector_manifest};
  const wire = canonicalJson({...actual, evidence_bundle_cid: contentCid(actual)});
  assert.ok(q.bounds.mergedWireUnits >= BigInt(wire.length));
  assert.ok(q.retained.text >= 2n * BigInt(wire.length));
  assert.equal(q.bounds.nativeAdmissionIncluded, false);
  assert.ok(q.nodes > compositionGeometry(b, left).nodes);
});

test('zero or one publication borrows original output but still funds compatibility checks', () => {
  const b = freeze(base()), one = freeze({...base(), notes: 'x'});
  for (const q of [compositionGeometry(b), compositionGeometry(b, one), compositionGeometry(b, undefined, one)]) {
    additive(q); assert.equal(q.bounds.merged, false);
    assert.equal(q.retained.text, 0n); assert.ok(q.workspace.nodes > 0n);
  }
});

test('immutable geometry rejects mutable accessor proxy cycle hole and excessive depth', () => {
  let called = 0;
  assert.throws(() => documentGeometry(base()));
  const getter = Object.freeze({get payload() {called++; return 'x';}});
  assert.throws(() => documentGeometry(getter));
  const proxy = new Proxy(Object.freeze({}), {ownKeys() {called++; return [];}});
  assert.throws(() => documentGeometry(proxy));
  const cycle = {}; cycle.self = cycle; Object.freeze(cycle);
  assert.throws(() => documentGeometry(cycle));
  assert.throws(() => documentGeometry(Object.freeze(Array(2))));
  let deep = Object.freeze({});
  for (let i = 0; i < 258; i++) deep = Object.freeze({child: deep});
  assert.throws(() => documentGeometry(deep));
  assert.equal(called, 0);
});
