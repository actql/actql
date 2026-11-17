import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {sourceJsonWireGeometry, sourceEnvironmentConstructionGeometry, sourceEnvironmentRetainedGeometry,
  sourceAuthoredViewConstructionGeometry, sourceEnvironmentCompositionGeometry} from './installed-source-construction-geometry.mjs';
import {rowSourceCheckEnvironment} from './installed-row-source.mjs';
import {installedEnvironmentDataWriterConstructionGeometry,
  installedEnvironmentMemberSortConstructionGeometry, installedCanonicalTextConstructionShape,
  installedCheckpointBindingCanonicalConstructionGeometry} from './installed-check-environment-construction.mjs';
import {canonicalJson as localCanonicalJson} from './local-account-config.mjs';
import {sourceCheckpointInventoryConstructionGeometry} from './source-alias-construction.mjs';

const count = value => value !== null && typeof value === 'object'
  ? 1n + Object.values(value).reduce((n, child) => n + count(child), 0n) : 1n;
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};

test('Checkpoint canonical inventory observes immutable scalar spelling before its future binding body', () => {
  const cid = 'sha256:' + 'a'.repeat(64);
  for (const refs of [[], ['connector://table/rows_128#records'],
    ['connector://x/e\u0301日本語😀#records', 'connector://x/\\"\n#records'],
    Array.from({length:129}, (_,index) => `connector://table/rows_${index}#records`)]) {
    const text = {output:0n, normalized:0n};
    for (const ref of refs) {
      const shape = installedCanonicalTextConstructionShape(ref);
      assert.ok(shape.output >= BigInt(JSON.stringify(ref.normalize('NFC')).length));
      text.output += shape.output; text.normalized += shape.normalized;
    }
    // Independent complete future member shape. These are fixture CIDs, not
    // values issued or substituted by the production construction quote.
    const body = {source_authorization_bindings: refs.map(source_ref => ({source_ref,
      configuration_cid:cid, context_cid:cid}))};
    const wire = localCanonicalJson(body), n = BigInt(refs.length);
    const quote = installedCheckpointBindingCanonicalConstructionGeometry(n,text.output,text.normalized);
    assert.ok(quote.text >= 2n * BigInt(wire.length));
    assert.ok(quote.wire >= BigInt(Buffer.byteLength(wire)));
    assert.ok(quote.nodes >= count(body));
    const all = sourceCheckpointInventoryConstructionGeometry(n,
      refs.reduce((sum,ref)=>sum+BigInt(ref.length),0n),text);
    assert.equal(all.retained.text,quote.text,'future canonical/hash workspace stays charged through real close');
    assert.equal(all.workspace.text,0n,'this is not a premature scratch-release claim');
    assert.equal(all.bounds.sourceCount,n);
    if (refs.length === 129) {
      // Python standard json.dumps(sort_keys=True,separators=(',',':')),
      // independently authored ASCII vector, not a product-derived golden.
      assert.equal(Buffer.byteLength(wire),30111);
      assert.equal(quote.wire,90461n,'exact ASCII canonical output plus existing hash buffer allowance');
      assert.equal(createHash('sha256').update(wire).digest('hex'),
        '3887c06c2c1b450b29e9c150d199b6aa68e374f271e3c9c891c9cddf205f2992');
      const sorted = localCanonicalJson({source_authorization_bindings:
        [...body.source_authorization_bindings].sort((a,b)=>a.source_ref < b.source_ref ? -1 : 1)});
      assert.equal(Buffer.byteLength(sorted),30111);
      assert.equal(createHash('sha256').update(sorted).digest('hex'),
        'cab5fe0222844c56f254005406d71c2de67a00bedef1ccd16377364ff329966f');
    }
  }
  assert.throws(()=>installedCheckpointBindingCanonicalConstructionGeometry(1n,1n,0n));
});

test('staged Environment writer keeps legacy CID sorting and complete original bytes', () => {
  const base = JSON.stringify({version: 'actql-check-environment/0.1',
    evidence_bundle_cid: 'old', connector_catalogs: [], schema_snapshots: [],
    connector_capabilities: [], mapping_contracts: [], command_contracts: []});
  const values = [JSON.stringify({id: 'z', value: 'e\u0301日本語😀'}),
    JSON.stringify({id: 'a', value: ['\\"\n', 1.25, false]})];
  const declared = {evidence_schemas: values, evidence_capabilities: values,
    view_bodies: values, contracts: values, command_bodies: values,
    catalog: values[0], manifest_entry: values[1]};
  const legacy = rowSourceCheckEnvironment(base, declared, values), phases = [];
  const invoke = (name, quote, project) => {
    assert.ok(quote.retained.nodes >= 0n && quote.workspace.nodes >= 0n);
    phases.push(name);return project();
  };
  const staged = rowSourceCheckEnvironment(base, declared, values, undefined, {
    freeze,
    parse: project => invoke('parse', sourceEnvironmentConstructionGeometry(base, declared, values).parsed, project),
    sort: (members, project) => invoke('sort', installedEnvironmentMemberSortConstructionGeometry(members), project),
    seal: freeze,
    hash: (body, project) => invoke('hash', installedEnvironmentDataWriterConstructionGeometry(body, true), project),
    encode: (document, project) => invoke('encode', installedEnvironmentDataWriterConstructionGeometry(document), project),
  });
  assert.deepEqual(staged, legacy);
  assert.deepEqual(phases, ['parse', ...Array(6).fill('sort'), 'hash', 'encode']);
});

test('wire geometry bounds actual JSON value occurrences including escaped detached syntax', () => {
  const samples = ['null', '0', '-1.7976931348623157e+308', '5e-324', '9007199254740991', 'true', '""', '[]', '{}', '[0,{},[null,false]]',
    '{"日本語😀":"\\u005b\\u007b\\u003a\\u002c","x":"\\\"\\\\[]{}"}',
    '{"catalog":"\\u005bnull\\u002c{\\u0022x\\u0022:[1,2]}\\u005d"}'];
  for (const wire of samples) {
    const value = JSON.parse(wire), geometry = sourceJsonWireGeometry(wire);
    assert.ok(geometry.nodes >= count(value));
    assert.ok(geometry.units === BigInt(wire.length));
    if (value?.catalog) assert.ok(geometry.nodes >= count(JSON.parse(value.catalog)));
  }
  const longEscaped = JSON.stringify({catalog: JSON.stringify({value: '\\\"日本語😀{}[]'.repeat(1000)})});
  assert.ok(sourceJsonWireGeometry(longEscaped).nodes >= count(JSON.parse(JSON.parse(longEscaped).catalog)));
  for (let depth = 0; depth < 30; depth++) {
    let value = 'escaped \\ " {} [] 日本語😀';
    for (let index = 0; index < depth; index++) value = {left: value, right: [null, index]};
    const wire = JSON.stringify(value);
    assert.ok(sourceJsonWireGeometry(wire).nodes >= count(value));
  }
  // Quotes do not admit JSON. Malformed-prefix allocation is still bounded
  // by root/colon/array-introducer credits; the actual parser rejects it.
  for (const wire of ['', '[', '[null,', '{"a":', '{"a":[0,', '"\\u005']) {
    assert.throws(() => JSON.parse(wire));
    assert.ok(sourceJsonWireGeometry(wire).nodes >= 1n);
  }
});

test('Environment quote covers the actual detached parses and canonical output without byte-as-node inflation', () => {
  const base = JSON.stringify({version: 'actql-check-environment/0.1',
    evidence_bundle_cid: 'old', connector_catalogs: [], schema_snapshots: [],
    connector_capabilities: [], mapping_contracts: [], command_contracts: []});
  const nested = JSON.stringify({id: 'x', content: {value: ['日本語😀', '\\"{}[]', null, 12.5]}});
  const declared = Object.freeze({evidence_schemas: Object.freeze([nested]),
    evidence_capabilities: Object.freeze([nested]), view_bodies: Object.freeze([nested]),
    contracts: Object.freeze([nested]), catalog: nested, manifest_entry: nested,
    command_bodies: Object.freeze([nested])});
  const mappings = Object.freeze([nested]);
  const quote = sourceEnvironmentConstructionGeometry(base, declared, mappings);
  const environment = rowSourceCheckEnvironment(base, declared, mappings);
  assert.ok(quote.nodes >= count(JSON.parse(environment.wire)));
  const retained = sourceEnvironmentRetainedGeometry(environment);
  assert.equal(retained.nodes, 3n);
  assert.ok(retained.text <= quote.retained.text);
  assert.ok(retained.text < quote.workspace.text);
  assert.equal(retained.wire, 0n);
  assert.ok(quote.text >= 2n * BigInt(environment.wire.length));
  assert.ok(quote.wire >= BigInt(Buffer.byteLength(environment.wire)));
  // A long data value changes text backing, not the tree's value count.
  const longDeclared = {...declared, catalog: JSON.stringify({content: 'x'.repeat(100000)})};
  const shortDeclared = {...declared, catalog: JSON.stringify({content: 'x'})};
  const short = sourceEnvironmentConstructionGeometry(base, shortDeclared, mappings);
  const long = sourceEnvironmentConstructionGeometry(base, longDeclared, mappings);
  assert.equal(long.nodes, short.nodes);
  assert.ok(long.text > short.text);
});

test('authored-view snapshot prices fixed records and borrowed String fields separately', () => {
  const views = value => Object.freeze([Object.freeze({resource: 'rows', schema_wire: value, facts_wire: '{}'})]);
  const short = sourceAuthoredViewConstructionGeometry(views('{}'));
  const long = sourceAuthoredViewConstructionGeometry(views('x'.repeat(100000)));
  assert.equal(short.nodes, long.nodes);
  assert.ok(long.text >= 2n * BigInt(JSON.stringify({views: views('x'.repeat(100000))}).length));
  let calls = 0;
  const accessor = Object.freeze({get resource() {calls++; return 'rows';}});
  assert.throws(() => sourceAuthoredViewConstructionGeometry(Object.freeze([accessor])));
  assert.equal(calls, 0);
});

test('final Environment composition separates scalar text from actual tree occurrences', () => {
  const wire = text => JSON.stringify({version: 'v', source_views: [{name: text}]});
  const short = sourceEnvironmentCompositionGeometry([wire('x'), undefined]);
  const long = sourceEnvironmentCompositionGeometry([wire('x'.repeat(100000)), undefined]);
  assert.equal(long.nodes, short.nodes, 'A larger String is not another tree of Value nodes');
  assert.ok(long.text > short.text);
  assert.ok(long.wire >= BigInt(Buffer.byteLength(wire('x'.repeat(100000)))));
  const many = sourceEnvironmentCompositionGeometry([JSON.stringify(Array(1000).fill(null))]);
  assert.ok(many.nodes > short.nodes, 'Actual additional values still require tree capacity');
  let nested = 'x'.repeat(1000);
  for (let depth = 0; depth < 12; depth++) nested = {value: nested};
  const deep = sourceEnvironmentCompositionGeometry([JSON.stringify(nested)]);
  assert.ok(deep.text > sourceEnvironmentCompositionGeometry([JSON.stringify('x'.repeat(1000))]).text,
    'Canonical recursion retains intermediate text, not just the final wire');
  for (const invalid of [null, 1, {}, [null]]) {
    assert.throws(() => sourceEnvironmentCompositionGeometry(invalid));
  }
});

test('returned JSON geometry uses the same scan without detached String punctuation becoming nodes', () => {
  const payload = '[]{}:,\\"'.repeat(1000), wire = JSON.stringify(payload);
  const measured = sourceJsonWireGeometry(wire);
  assert(measured.nodes > 1000n, 'the full original preparse envelope remains conservative');
  assert.equal(measured.retained.nodes, 1n);
  assert(measured.retained.text >= BigInt(Buffer.byteLength(payload)));
  const value = {a: [null, 1, true, 'é😀'], b: {x: '[]{}:,\\"'}};
  const full = sourceJsonWireGeometry(JSON.stringify(value));
  assert(full.retained.nodes >= count(value));
  assert(full.retained.text >= BigInt(Buffer.byteLength('abxé😀[]{}:,\\"')));
  assert.equal(full.retained.wire, 0n);
});
