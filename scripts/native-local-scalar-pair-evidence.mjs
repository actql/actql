// Build-time evidence for one reviewed predecessor pair. This never admits a
// runtime, grants authority, aliases contracts, evaluates a Program or reads
// installation custody. Full source bodies stay outside the bounded wire.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {gunzipSync} from 'node:zlib';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import {canonicalText, resolvePointer} from './check-canonical-json.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const predecessor = '109564ef9a4f8241096292843b875d4c81fbb6f3';
const fixtureDirectory = 'scripts/fixtures/native-local-scalar-predecessor';
const sha = value => createHash('sha256').update(value).digest('hex');
const cid = hash => 'sha256:' + hash;
// This is the reviewed side of a historical pair, not the installation's
// latest default assets. Keep the complete original bodies and bytes bound
// to their source; newer contracts require an independent compatibility proof.
function reviewedCurrentSide(sourceRoot) {
  const packed = readFileSync(resolve(sourceRoot,
    'scripts/fixtures/native-local-scalar-reviewed-current.json.gz'));
  assert.equal(sha(packed), '934bb2c194ff7c668fe91d6b30e8b5b2167a3cb542d38f7de751cba10cfa81d1');
  const bytes = gunzipSync(packed, {maxOutputLength: 773119});
  assert.equal(bytes.length, 773119);
  assert.equal(sha(bytes), '0cfad9f8abef5795b79b6be2e8078ffc06423cabef90027e0fb17b19ff41cc3b');
  const side = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
  assert.equal(side.version, 'actql-native-local-reviewed-scalar-pair-side/0.1');
  assert.equal(side.source, 'd062aa0f5992d3e2bf3fe4b9acac1f0ff34d26d0');
  return side;
}
function reviewedCurrentAssets(sourceRoot) {
  const {assets} = reviewedCurrentSide(sourceRoot);
  assert.deepEqual(Object.keys(assets).sort(), Object.keys(assetIdentities).sort());
  return new Map(Object.entries(assets).map(([role, wire]) => {
    assert.equal(typeof wire, 'string');
    return [role, Buffer.from(wire, 'utf8')];
  }));
}
// These complete identities are witnesses of the reviewed pair, not a
// registry of interchangeable CIDs. A different body requires another proof.
const identities = Object.freeze({
  registry: ['b79f24b0c777c4b9d533ef01289587e666caa7a6ba00159f6b45f3e57265f04e', 'a39ed49bed5ddd2dd6442a1dd92493a89fd47d563d36d255023e80ac10270041'],
  values: ['9b716536b27d313e93deadae776d9abf21c3d06dcd653d2eb3b74e0c276a182b', '6ba2e474f48d744fa3bd0c261af196467360fb8d8e3bb5e37751e32c06ade3e7'],
  fragment: ['9f0694ddd7c76d720024297fce02652bb15f5dad8b278d3db9ff58936a976b87', '1e327eb9f007372c835c82f8c2e17b3ad7feed8bf45ddee035340892d973cbeb'],
  ordered: ['2c5818e25cf54e21aadecd451414a295cb7d8398adf632ebd07c63943ddfdecb', '85595efff53323afd08f33d88559d3b988525613bd08c43125c85e6e74762a5e'],
  expression: ['a49aba23a30514b63c9f7bcd05663dcacf2e5646c56073e7d00a34d6abe402b7', 'e4b8431ae81884a1e198420dcbd08d6b12ef4dca4bd9b7b8ffa4cd45db887289'],
  'value-contract': ['02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551', '08c311d9a05b323ea6fde184981a965773ee71059c61bf3a830ab0e295c21947'],
  'text-time': ['2d41f38bd3bf8217d9bc394b1ca2ed9dfe6695b0088cd6a489328dabdee61dcc', 'ebae25fecbef6a2c79bdaa971f977d4bdcfb4c4c677b25bc9de6ec67354872e9'],
  'text-time-dependencies': ['246b8891c7aa07b6931d4a41c0d29aa00e8445390e6325c9885fe7c0a86048f8', '246b8891c7aa07b6931d4a41c0d29aa00e8445390e6325c9885fe7c0a86048f8'],
  'unicode-data': ['4a84a6d133b6282a5d50ba743ef8cab3fc87d4ccc91612663c5fc0d02f705dd4', '4a84a6d133b6282a5d50ba743ef8cab3fc87d4ccc91612663c5fc0d02f705dd4'],
  'derive-binding': ['d74bb697d91a2daf2c51e0d6c492f4bb35fdea5e542d606318683b1c9c5f06f9', 'd74bb697d91a2daf2c51e0d6c492f4bb35fdea5e542d606318683b1c9c5f06f9'],
  'rows-to-graph': ['b6c5006e94c3c865672ab2478f4b1897aa567314502e55eb50f784a50a94d210', 'd567ede4e421b6aaa6df39bf9fe03dfaaff129fb85ab9489faa6ffb61a8fa282'],
});

const assetIdentities = Object.freeze({
  "environment": [
    "e79109d982ad96e84d19d3d91b71cbec6f38511f94e80e62b5ad4573b5d7173c",
    "e79109d982ad96e84d19d3d91b71cbec6f38511f94e80e62b5ad4573b5d7173c"
  ],
  "registry": [
    "a212a9ee1aa4d927591ffc15f25df3218548e9da2f9aa688c6b5733f7348a8aa",
    "6ae574874934fcda0f8b0d7bf5f26b085a6c25fad25f5be319f4430ba9e66633"
  ],
  "values": [
    "7f667a6f89689763a2cb8bf8db81318408bd6eb0b3ad399ed5fd218d79ffa529",
    "8ff4a4f20578297eff9f7c40df8d32f4dd1e6d5ccbc9a24156b6ab533c292b53"
  ],
  "fragment": [
    "9d361dde54e27332a350f3f1d2ebfaef8c991b69a935538b45a049a739f775ca",
    "3da36b6da829dce7db05c15bbe00baa8abe3884a8b33e348c31d6ff55a1abacd"
  ],
  "ordered": [
    "96f0783f537b1856116d818cc5f73c67c27977b48ec6f2f6e2d1eac5b0a04748",
    "dd5c69871006b36152fa87ffc5cbb21fb045d4ad29ef85e3a28e2b6508944343"
  ],
  "result-policy": [
    "470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    "470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  ]
});

const referenceSuffix = '/$defs/value_contract/oneOf/7/properties/type/const';
const referenceChanges = Object.freeze({
  registry: [], values: [], fragment: [],
  ordered: ['/schemas/context' + referenceSuffix, '/schemas/shape' + referenceSuffix],
  expression: [
    '/schemas/expression/$defs/value_contract/oneOf/6/properties/type/const',
    '/schemas/expression_node' + referenceSuffix,
    '/schemas/fragment/properties/row_kernel_evidence/properties/contexts/items' + referenceSuffix,
    '/schemas/fragment/properties/row_kernel_evidence/properties/shapes/items' + referenceSuffix,
    '/schemas/fragment' + referenceSuffix,
    '/schemas/fragment/$defs/author_value_contract/oneOf/6/properties/type/const',
    '/schemas/predicate_consumer' + referenceSuffix,
    '/schemas/predicate_consumer/$defs/author_value_contract/oneOf/6/properties/type/const',
  ],
  'value-contract': [referenceSuffix],
  'text-time': ['/barrier_schema' + referenceSuffix],
  'text-time-dependencies': [], 'unicode-data': [], 'derive-binding': [],
  'rows-to-graph': ['/params_schema' + referenceSuffix],
});

// Resolve every changed dependency from its actual before/after body, rather
// than masking CID fields or ignoring the inherited profile pin.
const changedEdges = Object.freeze({
  registry: [
    ['/REL.derive/execution_extensions/ordered_bindings/cid', 'ordered', ''],
    ['/BRIDGE.rows.to_graph/execution_contract/cid', 'rows-to-graph', ''],
    ['/REL.values/execution_contract/cid', 'values', ''],
    ['/ACTQL.expression_fragment~10.1/execution_contract/cid', 'fragment', ''],
  ],
  values: [['/dependencies/canonical_value_contract/cid', 'value-contract', '']],
  fragment: [
    ['/dependencies/expression_contract/cid', 'expression', ''],
    ['/dependencies/fragment_schema/cid', 'expression', '/schemas/fragment'],
  ],
  ordered: [
    ['/dependencies/expression_contract/cid', 'expression', ''],
    ['/dependencies/expression_node/cid', 'expression', '/schemas/expression_node'],
    ['/dependencies/source_expression/cid', 'expression', '/schemas/expression'],
    ['/dependencies/value_contract/cid', 'value-contract', ''],
  ],
  expression: [['/inherited_text_time_profile_cid', 'text-time', '']],
  'text-time': [['/barrier_schema_cid', 'text-time', '/barrier_schema']],
  'value-contract': [], 'text-time-dependencies': [], 'unicode-data': [], 'derive-binding': [],
  'rows-to-graph': [['/dependencies/canonical_value_contract/cid', 'value-contract', '']],
});

function loadReviewedScalarPairBodies(sourceRoot, requireCurrentImplementation) {
  const read = path => readFileSync(resolve(sourceRoot, path));
  const manifest = read(fixtureDirectory + '/manifest.json');
  assert.equal(sha(manifest), '75bee505552e9e6958be5a20bac877b2d69664ba70aad7f7970bc506bfbc992b', 'Changed predecessor fixture metadata');
  const index = JSON.parse(manifest);
  assert.equal(index.source, predecessor);
  assert.equal(index.receipt_sha256, '7442fb6637fef2b797116c6d87d89d25351cef5dd686b3120910e528af1ef0d1');
  assert.equal(index.runtime_sha256, '80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd');
  assert.deepEqual(index.records.map(row => row.role).sort(), Object.keys(identities).sort());
  const old = {}, current = reviewedCurrentSide(sourceRoot).bodies;
  const implementations = [];
  for (const row of index.implementation_records) {
    assert.match(row.fixture, /^scalar-code-[0-9]+\.mbt\.gz$/);
    const oldBytes = gunzipSync(read(fixtureDirectory + '/' + row.fixture));
    assert.equal(oldBytes.length, row.bytes);
    assert.equal(sha(oldBytes), row.sha256);
    if (requireCurrentImplementation) {
      const currentBytes = read(row.path);
      assert(oldBytes.equals(currentBytes), 'Unknown scalar implementation change: ' + row.path);
    }
    implementations.push({path: row.path, sha256: row.sha256});
  }
  for (const row of index.records) {
    assert.match(row.fixture, /^[a-z-]+\.json\.gz$/);
    const bytes = gunzipSync(read(fixtureDirectory + '/' + row.fixture));
    assert.equal(bytes.length, row.bytes);
    assert.equal(sha(bytes), row.sha256);
    old[row.role] = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
    assert(Object.hasOwn(current, row.role), 'Missing reviewed current body');
  }
  return {old, current, implementations};
}

function replaceExact(body, pointer, before, after) {
  assert.deepEqual(resolvePointer(body, pointer), before, 'Wrong original proof leaf ' + pointer);
  const parts = pointer.split('/').slice(1).map(x => x.replaceAll('~1', '/').replaceAll('~0', '~'));
  let parent = body;
  for (const part of parts.slice(0, -1)) parent = parent[part];
  parent[parts.at(-1)] = after;
}

// Frozen proof integrity has a different subject from operational eligibility.
// No caller can turn either metadata reader into an installed compatibility grant.
export function loadHistoricalScalarPairBodies(sourceRoot = repository) {
  return loadReviewedScalarPairBodies(sourceRoot, false);
}

export function loadScalarPairBodies(sourceRoot = repository) {
  return loadReviewedScalarPairBodies(sourceRoot, true);
}

export function verifyScalarPairBodies({old, current}) {
  assert.deepEqual(Object.keys(old).sort(), Object.keys(identities).sort());
  assert.deepEqual(Object.keys(current).sort(), Object.keys(identities).sort());
  for (const [role, [before, after]] of Object.entries(identities)) {
    assert.equal(machineCid(old[role]), cid(before), 'Unknown predecessor body: ' + role);
    assert.equal(machineCid(current[role]), cid(after), 'Unknown current body: ' + role);
  }
  const records = [];
  for (const [role, [before, after]] of Object.entries(identities)) {
    const comparison = structuredClone(old[role]);
    for (const pointer of referenceChanges[role]) {
      replaceExact(comparison, pointer, 'artifact_ref', 'content_ref');
      assert.equal(resolvePointer(current[role], pointer), 'content_ref');
    }
    for (const [pointer, target, targetPointer] of changedEdges[role]) {
      const oldCid = machineCid(resolvePointer(old[target], targetPointer));
      const currentCid = machineCid(resolvePointer(current[target], targetPointer));
      replaceExact(comparison, pointer, oldCid, currentCid);
      assert.equal(resolvePointer(current[role], pointer), currentCid);
    }
    assert.deepEqual(comparison, current[role], 'Unexplained complete-body difference: ' + role);
    records.push({role, original_cid: cid(before), current_cid: cid(after)});
  }
  for (const side of [old, current]) {
    assert.equal(side.ordered.dependencies.derive_binding.cid, machineCid(side['derive-binding']));
    assert.deepEqual(side.ordered.schemas.context.$defs, side['value-contract'].$defs);
    assert.deepEqual(side.ordered.schemas.shape.$defs, side['value-contract'].$defs);
    const dependencies = side['text-time-dependencies'];
    assert.equal(dependencies.unicode_semantics.data_cid, machineCid(side['unicode-data']));
    assert.deepEqual(dependencies.unicode_semantics.expansion, side['unicode-data'].expansion);
    for (const [pin, body] of [
      [side['text-time'].data_contract_cids.regex_grammar_cid, dependencies.regex_grammar],
      [side['text-time'].data_contract_cids.timestamp_pattern_grammar_cid, dependencies.timestamp_pattern_grammar],
      [side['text-time'].data_contract_cids.unicode_data_cid, dependencies.unicode_semantics],
      [dependencies.regex_grammar.ast_schema_cid, dependencies.regex_ast_schema],
      [dependencies.regex_grammar.replacement_ast_schema_cid, dependencies.regex_replacement_ast_schema],
      [dependencies.timestamp_pattern_grammar.ast_schema_cid, dependencies.timestamp_pattern_ast_schema],
    ]) assert.equal(pin, machineCid(body), 'External dependency closure');
    for (const operation of ['REL.values', 'REL.derive', 'REL.where', 'REL.select']) {
      assert(side.registry[operation], 'Missing reachable operation');
    }
  }
  return records;
}

export function scalarPairAudit(sourceRoot = repository) {
  const bodies = loadScalarPairBodies(sourceRoot);
  const pairs = verifyScalarPairBodies(bodies);
  return {predecessor_source_sha: predecessor, implementations: bodies.implementations,
    pairs: pairs.map(row => ({...row,
      original_canonical_sha256: sha(canonicalText(bodies.old[row.role])),
      current_canonical_sha256: sha(canonicalText(bodies.current[row.role])),
      exact_differences: [
        ...referenceChanges[row.role].map(path => ({path, original: 'artifact_ref', current: 'content_ref'})),
        ...changedEdges[row.role].map(([path, target, targetPointer]) => ({path,
          original: machineCid(resolvePointer(bodies.old[target], targetPointer)),
          current: machineCid(resolvePointer(bodies.current[target], targetPointer)),
        })),
      ],
    })),
  };
}

export function scalarPairEvidence(sourceRoot = repository) {
  const bodies = loadHistoricalScalarPairBodies(sourceRoot);
  const records = verifyScalarPairBodies(bodies);
  const currentAssets = reviewedCurrentAssets(sourceRoot);
  const index = JSON.parse(readFileSync(resolve(sourceRoot, fixtureDirectory + '/manifest.json')));
  for (const [role, pair] of Object.entries(assetIdentities)) {
    assert.equal(sha(currentAssets.get(role)), pair[1], 'Unknown current asset bytes: ' + role);
    if (bodies.old[role]) assert.equal(index.records.find(row => row.role === role).sha256, pair[0]);
  }
  return {
    version: 'actql-native-local-scalar-pair-evidence/0.1',
    predecessor_source_sha: predecessor,
    predecessor_runtime_sha256: index.runtime_sha256,
    profile: 'primitive-scalar-values',
    reachable_operations: ['REL.values', 'REL.derive', 'REL.where', 'REL.select'],
    excluded: ['references', 'json', 'containers', 'graph', 'vector', 'event', 'infer', 'effect', 'serialization', 'unknown', 'unresolved-obligations'],
    body_pairs: records.map(row => ({...row,
      original_canonical_body_sha256: sha(canonicalText(bodies.old[row.role])),
      current_canonical_body_sha256: sha(canonicalText(bodies.current[row.role])),
    })),
    exact_difference_cid: machineCid(Object.keys(identities).sort().map(role => ({
      role,
      differences: [
        ...referenceChanges[role].map(path => ({path, original: 'artifact_ref', current: 'content_ref'})),
        ...changedEdges[role].map(([path, target, targetPointer]) => ({
          path,
          original: machineCid(resolvePointer(bodies.old[target], targetPointer)),
          current: machineCid(resolvePointer(bodies.current[target], targetPointer)),
        })),
      ].sort((a,b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0),
    }))),
    implementation_evidence_cid: machineCid(bodies.implementations),
    asset_pairs: Object.entries(assetIdentities).map(([role, pair]) => ({
      role, original_sha256: pair[0], current_sha256: pair[1],
    })),
  };
}

export function scalarPairSource(sourceRoot = repository) {
  const evidence = scalarPairEvidence(sourceRoot);
  const wire = canonicalText(evidence);
  assert(Buffer.byteLength(wire) <= 8192, 'Finite evidence metadata');
  return '// Generated by scripts/native-local-scalar-pair-evidence.mjs --write.\n' +
    '// Build-time body proof only; no physical custody or authority is issued.\n\n///|\n' +
    'fn native_local_scalar_pair_evidence_wire() -> String {\n  ' + JSON.stringify(wire) + '\n}\n\n///|\n' +
    'fn native_local_scalar_pair_evidence_cid() -> String {\n  ' + JSON.stringify(machineCid(evidence)) + '\n}\n' +
    ['original', 'current'].map(side => '\n///|\nfn native_local_scalar_pair_' + side + '_asset_hash(role : String) -> String? {\n  match role {\n' +
      evidence.asset_pairs.map(row => '    ' + JSON.stringify(row.role) + ' => Some(' + JSON.stringify(row[side + '_sha256']) + ')\n').join('') +
      '    _ => None\n  }\n}\n').join('');
}

// Retained inputs for metadata tests, never authenticated installation state.
export function scalarPairRuntimeFixture(sourceRoot = repository) {
  const read = name => gunzipSync(readFileSync(resolve(sourceRoot, fixtureDirectory + '/' + name + '.json.gz')));
  const originalRuntime = read('local-runtime');
  assert.equal(sha(originalRuntime), '80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd');
  const originalAssets = new Map(Object.keys(assetIdentities).map(role => [role, read(role)]));
  const currentAssets = reviewedCurrentAssets(sourceRoot);
  for (const [role, pair] of Object.entries(assetIdentities)) {
    assert.equal(sha(originalAssets.get(role)), pair[0]);
    assert.equal(sha(currentAssets.get(role)), pair[1]);
  }
  const candidate = JSON.parse(originalRuntime);
  // This source identity is deliberately synthetic. No current physical
  // package or installed compatibility success is claimed by these tests.
  candidate.sourceSha = 'b'.repeat(40);
  for (const asset of candidate.assets) {
    asset.bytes = currentAssets.get(asset.role).length;
    asset.sha256 = sha(currentAssets.get(asset.role));
  }
  const fields = ['environment', 'registry', 'values', 'fragment'];
  return '// Generated retained test inputs; not adoption originals or runtime authority.\n' +
    '\n///|\nfn scalar_pair_test_original_runtime_wire() -> String {\n  ' + JSON.stringify(originalRuntime.toString('utf8')) + '\n}\n' +
    '\n///|\nfn scalar_pair_test_current_runtime_wire() -> String {\n  ' + JSON.stringify(JSON.stringify(candidate)) + '\n}\n' +
    '\n///|\nfn scalar_pair_test_original_assets() -> ClientLocalProductAssets {\n  {\n' +
    fields.map(role => '    ' + role + ': ' + JSON.stringify(originalAssets.get(role).toString('utf8')) + ',\n').join('') +
    '    ordered: Some(' + JSON.stringify(originalAssets.get('ordered').toString('utf8')) + '),\n' +
    '    result_policy: ' + JSON.stringify(originalAssets.get('result-policy').toString('utf8')) + ',\n  }\n}\n' +
    '\n///|\nfn scalar_pair_test_reviewed_current_assets() -> ClientLocalProductAssets {\n  {\n' +
    fields.map(role => '    ' + role + ': ' + JSON.stringify(currentAssets.get(role).toString('utf8')) + ',\n').join('') +
    '    ordered: Some(' + JSON.stringify(currentAssets.get('ordered').toString('utf8')) + '),\n' +
    '    result_policy: ' + JSON.stringify(currentAssets.get('result-policy').toString('utf8')) + ',\n  }\n}\n';
}

// One independently retained installed a3b manifest, not latest defaults or
// another release selector. Runtime callers cannot supply a proof identifier.
const historicalSource = 'a3b1643fbedc5180db38b6e08459a188f05b1135';
const historicalManifestHash = '585e5959c972a801335103217d2dede6cb12f72333a58f6b88bf88c85075fd85';
const historicalEvidenceCid = 'sha256:8bdf483589d04809f0e2e198708adc8335b38179f332e58d25a8a09497633a22';

export function verifyHistoricalScalarPairManifests(originalBytes, historicalBytes, sourceRoot = repository) {
  // Revalidate all complete bodies, inherited/external dependencies, scalar
  // implementation inputs and every original/current asset byte before emit.
  const evidence = scalarPairEvidence(sourceRoot);
  scalarPairRuntimeFixture(sourceRoot);
  assert.equal(machineCid(evidence), historicalEvidenceCid);
  assert.equal(sha(originalBytes), evidence.predecessor_runtime_sha256);
  assert.equal(sha(historicalBytes), historicalManifestHash);
  const original = JSON.parse(originalBytes.toString('utf8'));
  const historical = JSON.parse(historicalBytes.toString('utf8'));
  assert.equal(original.sourceSha, predecessor);
  assert.equal(historical.sourceSha, historicalSource);
  const assets = reviewedCurrentAssets(sourceRoot);
  const expected = structuredClone(original);
  expected.sourceSha = historicalSource;
  assert.equal(expected.platform, 'darwin-arm64');
  assert.equal(expected.assets.length, 6);
  for (const asset of expected.assets) {
    assert(assets.has(asset.role));
    asset.bytes = assets.get(asset.role).length;
    asset.sha256 = sha(assets.get(asset.role));
  }
  // This also binds every original/current role/path/library/ABI/license and
  // dependency closure; extra entries and fields do not get masked away.
  assert.deepEqual(historical, expected);
  return {evidence, original, historical, assets};
}

export function historicalScalarPairInputs(sourceRoot = repository) {
  const originalBytes = gunzipSync(readFileSync(resolve(sourceRoot,
    fixtureDirectory + '/local-runtime.json.gz')));
  const historicalBytes = readFileSync(resolve(sourceRoot,
    'scripts/fixtures/native-local-scalar-historical-a3b-runtime.json'));
  return {originalBytes, historicalBytes,
    ...verifyHistoricalScalarPairManifests(originalBytes, historicalBytes, sourceRoot)};
}

export function scalarPairHistoricalSource(sourceRoot = repository) {
  const {evidence, assets} = historicalScalarPairInputs(sourceRoot);
  const index = JSON.parse(readFileSync(resolve(sourceRoot, fixtureDirectory + '/manifest.json')));
  const originalAssets = new Map(Object.keys(assetIdentities).map(role => {
    const bytes = gunzipSync(readFileSync(resolve(sourceRoot, fixtureDirectory + '/' + role + '.json.gz')));
    assert.equal(sha(bytes), assetIdentities[role][0]);
    return [role, bytes];
  }));
  assert.equal(index.runtime_sha256, evidence.predecessor_runtime_sha256);
  let source = '// Generated by scripts/native-local-scalar-pair-evidence.mjs --write.\n' +
    '// Historical pair metadata only; never custody or current compatibility.\n';
  for (const [name, value] of [['evidence_cid', historicalEvidenceCid],
    ['source', historicalSource], ['manifest_hash', historicalManifestHash]]) {
    source += '\n///|\nfn native_local_scalar_historical_' + name + '() -> String {\n  ' + JSON.stringify(value) + '\n}\n';
  }
  for (const [name, side] of [['original', originalAssets], ['current', assets]]) {
    source += '\n///|\nfn native_local_scalar_historical_' + name + '_asset_bytes(role : String) -> Int64? {\n  match role {\n' +
      [...side].map(([role, bytes]) => '    ' + JSON.stringify(role) + ' => Some(' + bytes.length + 'L)\n').join('') +
      '    _ => None\n  }\n}\n';
  }
  return source;
}

export function scalarPairHistoricalFixture(sourceRoot = repository) {
  const {historicalBytes, evidence, original} = historicalScalarPairInputs(sourceRoot);
  const vector = JSON.parse(readFileSync(resolve(sourceRoot,
    'scripts/fixtures/native-local-scalar-historical-pair-vector.json')));
  assert.deepEqual(Object.keys(vector).sort(), ['body', 'cid', 'sha256']);
  assert.equal(vector.sha256, '2b06a81d8266f98c954a76556c3312e3abba0acb8615f19c501ce3df920d367b');
  assert.equal(sha(vector.body), vector.sha256);
  assert.equal(vector.cid, cid(vector.sha256));
  assert.equal(vector.body, canonicalText({current_manifest_sha256: historicalManifestHash,
    current_source_sha: historicalSource, evidence_cid: machineCid(evidence),
    original_manifest_sha256: evidence.predecessor_runtime_sha256,
    original_source_sha: original.sourceSha, platform: 'darwin-arm64',
    profile: 'primitive-scalar-values', version: 'actql-native-local-scalar-runtime-pair/0.1'}));
  return '// Generated retained metadata vectors, not authenticated installation state.\n' +
    '\n///|\nfn historical_scalar_pair_test_runtime_wire() -> String {\n  ' + JSON.stringify(historicalBytes.toString('utf8')) + '\n}\n' +
    '\n///|\nfn historical_scalar_pair_test_saved_body() -> Bytes {\n  @utf8.encode(\n    ' + JSON.stringify(vector.body) + ',\n  )\n}\n';
}

// Integrity of the frozen descriptor/body proof, not permission to execute it.
// loadScalarPairBodies retains the independent current-implementation refusal.
export function assertScalarPairEvidenceFresh(sourceRoot = repository) {
  assert.equal(readFileSync(resolve(sourceRoot,
    'src/run_publication_host/client_native_local_scalar_pair_evidence.generated.mbt'), 'utf8'),
  scalarPairSource(sourceRoot), 'Stale scalar pair evidence');
  assert.equal(readFileSync(resolve(sourceRoot,
    'src/run_publication_host/client_native_local_scalar_pair_fixture.generated_wbtest.mbt'), 'utf8'),
  scalarPairRuntimeFixture(sourceRoot), 'Stale retained scalar pair test inputs');
  assert.equal(readFileSync(resolve(sourceRoot,
    'src/run_publication_host/client_native_local_scalar_historical_pair.generated.mbt'), 'utf8'),
  scalarPairHistoricalSource(sourceRoot), 'Stale historical pair manifest proof');
  assert.equal(readFileSync(resolve(sourceRoot,
    'src/run_publication_host/client_native_local_scalar_historical_pair_fixture.generated_wbtest.mbt'), 'utf8'),
  scalarPairHistoricalFixture(sourceRoot), 'Stale independent historical pair vectors');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert(process.argv.length === 3 && ['--check', '--write'].includes(process.argv[2]));
  if (process.argv[2] === '--write') {
    writeFileSync(resolve(repository, 'src/run_publication_host/client_native_local_scalar_pair_evidence.generated.mbt'), scalarPairSource());
    writeFileSync(resolve(repository, 'src/run_publication_host/client_native_local_scalar_pair_fixture.generated_wbtest.mbt'), scalarPairRuntimeFixture());
    writeFileSync(resolve(repository, 'src/run_publication_host/client_native_local_scalar_historical_pair.generated.mbt'), scalarPairHistoricalSource());
    writeFileSync(resolve(repository, 'src/run_publication_host/client_native_local_scalar_historical_pair_fixture.generated_wbtest.mbt'), scalarPairHistoricalFixture());
  }
  else assertScalarPairEvidenceFresh();
}
