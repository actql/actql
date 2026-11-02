import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {dirname, relative} from 'node:path';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {sequenceIdentityOracle} from './sequence-identity-oracle.mjs';
import {canonicalText, generateTests} from './check-canonical-json.mjs';
import {verifyInferenceBarrierSchema} from './inference-barrier-contract.mjs';
import {expectedCompilationManifests,
  verifyCompilationManifests} from './compilation-manifests.mjs';

const sha = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const read = path => JSON.parse(readFileSync(path, 'utf8'));

test('independent canonical manifest identity vectors', () => {
  // Preserve the historical pre-structural vector; it is no longer a current
  // schema-admissible manifest. Do not retarget its expected CID.
  const grammarPreimage = '{"expression_contract_cid":' +
    '"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",' +
    '"expression_text_grammar_sha256":' +
    '"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",' +
    '"expression_text_rules_sha256":' +
    '"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",' +
    '"operations":["filter","values"],"source_grammar_cid":' +
    '"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",' +
    '"version":"actql-grammar-manifest/0.1"}';
  const barrierPreimage = '{"contracts":[{"contract_cid":' +
    '"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",' +
    '"name":"artifact_barrier"}],"production_profile_registry_cid":' +
    '"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",' +
    '"version":"actql-barrier-contract-manifest/0.1"}';
  assert.equal(sha(grammarPreimage),
    'sha256:1610c0174e196a0d1173c9d11f0f6598e098e883468cea7bc035744edfc1f33a');
  assert.equal(sha(barrierPreimage),
    'sha256:4cf406b9a5e56f04a82aca30597cdb9d4f874242a590ea1e3873e7cb204c5bf9');
  assert.equal(machineCid(JSON.parse(grammarPreimage)), sha(grammarPreimage));
  assert.equal(machineCid(JSON.parse(barrierPreimage)), sha(barrierPreimage));
});

test('ContentRef barrier has a distinct current canonical identity', () => {
  // This literal vector is independently hashed, not emitted by the compiler.
  // The actual former Artifact vector above remains unchanged.
  const preimage = '{"contracts":[{"contract_cid":"sha256:' +
    'e'.repeat(64) + '","name":"content_barrier"}],' +
    '"production_profile_registry_cid":"sha256:' + 'f'.repeat(64) +
    '","version":"actql-barrier-contract-manifest/0.1"}';
  const expected = 'sha256:0ba05a35a4a0ee26eeb46c70294441d3a1a556afaaede0f012d5111863624e79';
  assert.equal(sha(preimage), expected);
  assert.equal(machineCid(JSON.parse(preimage)), expected);
  assert.notEqual(expected,
    'sha256:4cf406b9a5e56f04a82aca30597cdb9d4f874242a590ea1e3873e7cb204c5bf9');
});

test('structural grammar and rules have distinct bound identity inputs', () => {
  const preimage = '{"expression_contract_cid":"sha256:' + 'a'.repeat(64) +
    '","expression_text_grammar_sha256":"' + 'b'.repeat(64) +
    '","expression_text_rules_sha256":"' + 'c'.repeat(64) +
    '","operations":["filter","values"],"source_grammar_cid":"sha256:' +
    'd'.repeat(64) + '","structural_text_grammar_sha256":"' + 'e'.repeat(64) +
    '","structural_text_rules_sha256":"' + 'f'.repeat(64) +
    '","version":"actql-grammar-manifest/0.1"}';
  // Literal preimage independently hashed with Python hashlib, not generated
  // by the product compiler or the manifest writer.
  const expected = 'sha256:9668c7a7f243c5d1b894d656110dee14357ab81072b380dcaf072d29fc31812c';
  assert.equal(sha(preimage), expected);
  const body = JSON.parse(preimage);
  assert.equal(machineCid(body), expected);
  for (const key of ['structural_text_grammar_sha256', 'structural_text_rules_sha256']) {
    assert.notEqual(machineCid({...body, [key]: '0'.repeat(64)}), expected);
    const missing = {...body};
    delete missing[key];
    assert.notEqual(machineCid(missing), expected);
    const schema = expectedCompilationManifests().contract.schemas.grammar_manifest;
    assert.ok(schema.required.includes(key));
    assert.deepEqual(schema.properties[key], {type: 'string', pattern: '^[0-9a-f]{64}$'});
  }
});

test('query grammar and rules have independent manifest identity inputs', () => {
  const preimage = '{"expression_contract_cid":"sha256:' + 'a'.repeat(64) +
    '","expression_text_grammar_sha256":"' + 'b'.repeat(64) +
    '","expression_text_rules_sha256":"' + 'c'.repeat(64) +
    '","operations":["filter","values"],"query_text_grammar_sha256":"' +
    '1'.repeat(64) + '","query_text_rules_sha256":"' + '2'.repeat(64) +
    '","source_grammar_cid":"sha256:' + 'd'.repeat(64) +
    '","structural_text_grammar_sha256":"' + 'e'.repeat(64) +
    '","structural_text_rules_sha256":"' + 'f'.repeat(64) +
    '","version":"actql-grammar-manifest/0.1"}';
  // Independently hashed with Python hashlib and sorted compact JSON.
  const expected = 'sha256:3f07536156edbf1728e2fb8da2446ab420a551d100d75e07dae16bc3e2007b48';
  assert.equal(sha(preimage), expected);
  const body = JSON.parse(preimage);
  assert.equal(machineCid(body), expected);
  const schema = expectedCompilationManifests().contract.schemas.grammar_manifest;
  for (const key of ['query_text_grammar_sha256', 'query_text_rules_sha256']) {
    assert.notEqual(machineCid({...body, [key]: '0'.repeat(64)}), expected);
    const missing = {...body};
    delete missing[key];
    assert.notEqual(machineCid(missing), expected);
    assert.ok(schema.required.includes(key));
    assert.deepEqual(schema.properties[key], {type: 'string', pattern: '^[0-9a-f]{64}$'});
  }
});

test('current query rules bind the manifest while prior rules retain their identity', () => {
  // Independent Python SHA-256 of the normative bytes and sorted manifest
  // preimage. Preserve the complete earlier body, including its old grammar.
  const vector = read('scripts/fixtures/initial-from-join/independent-vector.json');
  const parent = read('reviews/2026-10-15-nearest-shorthand/preimages/grammar-manifest.json');
  const queryRules = readFileSync('docs/spec/query-text.md', 'utf8');
  assert.equal(parent.query_text_grammar_sha256,
    'db0eabfabb2001aae2b2354ea10ce117f0ec0e249fabf857b766dad293243279');
  assert.equal(parent.query_text_rules_sha256,
    '935fdeabfd1ae1f03ca42d21c012a66880081ce09d6bf4856bc3d66ee036a6a4');
  const {grammar_manifest_cid: current, ...body} =
    read('spec/manifests/actql-grammar-0.1.json');
  assert.equal(body.query_text_grammar_sha256, sha(readFileSync('spec/grammar/actql-query-0.1.ebnf')).slice(7));
  assert.equal(body.query_text_rules_sha256, sha(queryRules).slice(7));
  assert.equal(sha(canonicalText(body)), current);
  const integrated = read('scripts/fixtures/logical-update-target/main2874-manifest-identity.json');
  // The main 2874 manifest is a historical vector; the v0.1 Effect forms moved the grammar after it.
  const {grammar_manifest_cid: integratedCid, ...integratedBody} = integrated.after;
  assert.equal(sha(canonicalText(integratedBody)), integratedCid);
  assert.notEqual(integratedCid, current);
  // Preserve main's adopted NEAREST preimage after the combined grammar moves.
  const nearest = read('scripts/fixtures/nearest-shorthand/manifest-identity.json');
  assert.deepEqual(integrated.main_before, nearest.manifest);
  const {grammar_manifest_cid: nearestCid, ...nearestBody} = nearest.manifest;
  assert.equal(nearestCid, 'sha256:8a917f82be481357f130f80f78c53f039dbf306b785233c800f978528d99a798');
  assert.equal(sha(canonicalText(nearestBody)), nearestCid);
  assert.notEqual(nearestCid, current);
  const tableRules = read('scripts/fixtures/terminal-table-query-rules/manifest-identities.json');
  assert.deepEqual(nearest.manifest, tableRules.grammar);
  assert.notDeepEqual(tableRules.grammar, tableRules.current_grammar);
  const {grammar_manifest_cid: tableRulesCid, ...tableRulesBody} = tableRules.current_grammar;
  assert.equal(tableRulesCid, 'sha256:0d08abc8e9c5cb12a80d77e43b9bdc4e1bf3aed9967b1831b3b9d7fc4d341411');
  assert.equal(sha(canonicalText(tableRulesBody)), tableRulesCid);
  assert.notEqual(tableRulesCid, current);
  const update = read('scripts/fixtures/private-update-capture/manifest-identity.json');
  const {grammar_manifest_cid: priorUpdate, ...priorUpdateBody} = update.after;
  assert.equal(priorUpdate, 'sha256:913d9e69aa87096a497cbf163a2fb9bb019b13a765f28792b734fa5f1a367361');
  assert.equal(sha(canonicalText(priorUpdateBody)), priorUpdate);
  assert.notEqual(priorUpdate, current);
  assert.equal(parent.grammar_manifest_cid,
    'sha256:577baba6e0eeda68b93a01f4bb0744be2c01fe6108fd16d889d4f4caaca8233b');
  const {grammar_manifest_cid: adopted, ...adoptedBody} = parent;
  assert.equal(sha(canonicalText(adoptedBody)), adopted);
  const {grammar_manifest_cid: previous, ...before} = vector.before;
  assert.equal(previous,
    'sha256:27d3b7110464cb168591ceebd54340aaafde66e46fc4f7b576ee6df7aec143ca');
  assert.equal(before.query_text_rules_sha256,
    'd06e43b1b31cffcaef022d0568a81aab7c22ced4e25e7ae9c9e9aec9346b071a');
  assert.equal(sha(canonicalText(before)), previous);
  const prior = {...before,
    query_text_rules_sha256: '87b7d37c8bf5a739631dc7ecf187e8fe0c7a75564c58e26f8d11282b08a0b722'};
  assert.equal(sha(canonicalText(prior)),
    'sha256:2aa67a52bae3a27fec7397dfa40c0cdc63096cd988e7cfee480477386c53b2ec');
  assert.notEqual(previous, current);
});

test('private UPDATE capture retains historical identity and optional Result behavior', () => {
  // This fixed vector uses independent Python hashes, never compiler output.
  // The prior manifest remains historical, including its stale structural pin.
  const vector = read('scripts/fixtures/private-update-capture/manifest-identity.json');
  const {grammar_manifest_cid: previous, ...before} = vector.before;
  assert.equal(previous,
    'sha256:577baba6e0eeda68b93a01f4bb0744be2c01fe6108fd16d889d4f4caaca8233b');
  assert.equal(sha(canonicalText(before)), previous);
  assert.equal(before.query_text_grammar_sha256,
    'db0eabfabb2001aae2b2354ea10ce117f0ec0e249fabf857b766dad293243279');
  assert.equal(before.query_text_rules_sha256,
    '935fdeabfd1ae1f03ca42d21c012a66880081ce09d6bf4856bc3d66ee036a6a4');
  const grammar = readFileSync('spec/grammar/actql-query-0.1.ebnf', 'utf8');
  assert.match(grammar, /record_target = path, \[ "MAPPING", identifier \]\s+\| "TARGET", query_string, "MAPPING", identifier/u);
  assert.match(grammar, /terminal_update = effect_prefix, "UPDATE", record_target, \[ effect_result \]/u);
  const {grammar_manifest_cid: afterCid, ...after} = vector.after;
  assert.equal(afterCid,
    'sha256:913d9e69aa87096a497cbf163a2fb9bb019b13a765f28792b734fa5f1a367361');
  assert.equal(sha(canonicalText(after)), afterCid);
  assert.equal(sha(readFileSync('docs/spec/structural-text.md')),
    'sha256:' + vector.after.structural_text_rules_sha256);
  const unchanged = {...vector.after};
  for (const key of ['grammar_manifest_cid', 'query_text_grammar_sha256',
    'query_text_rules_sha256', 'structural_text_rules_sha256']) {
    unchanged[key] = vector.before[key];
  }
  assert.deepEqual(unchanged, vector.before);
  assert.equal(vector.actual_parser_or_runtime_execution, 0);
});

test('logical UPDATE retains historical identity and target grammar', () => {
  // Independent fixed Python hashes; neither the compiler nor generator
  // supplies expectations. Historical manifests keep their original bodies.
  const vector = read('scripts/fixtures/logical-update-target/manifest-identity.json');
  const {grammar_manifest_cid: previous, ...before} = vector.before;
  assert.equal(vector.parent_source, '8cc9f5cfd158ea7517795b30268200b88da8dea6');
  assert.equal(previous,
    'sha256:577baba6e0eeda68b93a01f4bb0744be2c01fe6108fd16d889d4f4caaca8233b');
  assert.equal(sha(canonicalText(before)), previous);
  const {grammar_manifest_cid: afterCid, ...after} = vector.after;
  assert.equal(afterCid,
    'sha256:1faf0a5c244f339f741b505a9077ebe9029ad8c6d57726ae411d8221934a41b9');
  assert.equal(sha(canonicalText(after)), afterCid);
  assert.equal(before.query_text_grammar_sha256,
    'db0eabfabb2001aae2b2354ea10ce117f0ec0e249fabf857b766dad293243279');
  assert.equal(before.query_text_rules_sha256,
    '935fdeabfd1ae1f03ca42d21c012a66880081ce09d6bf4856bc3d66ee036a6a4');
  const grammar = readFileSync('spec/grammar/actql-query-0.1.ebnf', 'utf8');
  assert.match(grammar, /record_target = path, \[ "MAPPING", identifier \]\s+\| "TARGET", query_string, "MAPPING", identifier/u);
  assert.match(grammar, /terminal_update = effect_prefix, "UPDATE", record_target, \[ effect_result \]/u);
  assert.equal(sha(readFileSync('docs/spec/structural-text.md')),
    'sha256:' + vector.after.structural_text_rules_sha256);
  const unchanged = {...vector.after};
  for (const key of ['grammar_manifest_cid', 'query_text_grammar_sha256',
    'query_text_rules_sha256', 'structural_text_rules_sha256']) {
    unchanged[key] = vector.before[key];
  }
  assert.deepEqual(unchanged, vector.before);
  assert.equal(vector.actual_parser_or_runtime_execution, 0);
});

test('combined UPDATE target and capture identity preserves both predecessors', () => {
  const combined = read('scripts/fixtures/logical-update-target/combined-manifest-identity.json');
  const capture = read('scripts/fixtures/private-update-capture/manifest-identity.json');
  const logical = read('scripts/fixtures/logical-update-target/manifest-identity.json');
  assert.equal(combined.parent_source, '676eac9c8d9d79655c25e1f72dca7924fe5152b4');
  assert.deepEqual(combined.before, capture.after);
  assert.equal(combined.historical_logical_target_manifest_cid,
    logical.after.grammar_manifest_cid);
  for (const predecessor of [capture, logical, combined]) {
    for (const value of [predecessor.before, predecessor.after]) {
      const {grammar_manifest_cid: expected, ...body} = value;
      assert.equal(sha(canonicalText(body)), expected);
    }
  }
  const unchanged = {...combined.after};
  for (const key of ['grammar_manifest_cid', 'query_text_grammar_sha256',
    'query_text_rules_sha256']) unchanged[key] = combined.before[key];
  assert.deepEqual(unchanged, combined.before);
  const selection = read('scripts/fixtures/logical-update-target/selection-manifest-identity.json');
  assert.deepEqual(selection.before, combined.after);
  assert.equal(combined.actual_parser_or_runtime_execution, 0);
});

test('original UPDATE selection custody preserves prior combined identity', () => {
  const selection = read('scripts/fixtures/logical-update-target/selection-manifest-identity.json');
  for (const value of [selection.before, selection.after]) {
    const {grammar_manifest_cid: expected, ...body} = value;
    assert.equal(sha(canonicalText(body)), expected);
  }
  assert.deepEqual({...selection.after,
    grammar_manifest_cid: selection.before.grammar_manifest_cid,
    query_text_rules_sha256: selection.before.query_text_rules_sha256},
  selection.before);
  const integrated = read('scripts/fixtures/logical-update-target/main2874-manifest-identity.json');
  assert.deepEqual(integrated.frozen_before, selection.after);
  // Effect forms and explicit composite roles moved the source/query grammar.
  // Signed64 additionally changes the inherited expression dependency. Validate
  // that complete original body before restoring the historical manifest edge.
  // The later division extension retains this entire accepted predecessor;
  // its own full-body/pin proof closes the new identity separately.
  const divisionPredecessor = JSON.parse(gunzipSync(readFileSync('scripts/fixtures/decimal-division-exact/predecessor.json.gz')));
  assert.equal(divisionPredecessor.source, '2d59f72f7ef3d288415e93db445146b1a2d48847');
  const currentManifest = divisionPredecessor.bodies['spec/manifests/actql-grammar-0.1.json'];
  const expression = JSON.parse(gunzipSync(readFileSync(
    'scripts/fixtures/composite-vector-bridge/signed64-identities.json.gz'))).expressionContract;
  const currentExpression = divisionPredecessor.bodies['spec/contracts/actql-expressions.json'];
  const comparisonHistory = JSON.parse(gunzipSync(readFileSync(
    'scripts/fixtures/pre-int64-comparison-literal-identities.json.gz')));
  const comparisonVectors = read('portability/corpus/int64-comparison-literals.json');
  const comparisonPrior = comparisonHistory.records['spec/contracts/actql-expressions.json'];
  assert.deepEqual(comparisonPrior, expression.body);
  const queryTimePrior = read('scripts/fixtures/query-time-source/predecessor.json')
    .contracts.find(record => record.id === 'expression_contract');
  assert.equal(machineCid(queryTimePrior.body), queryTimePrior.cid);
  assert.equal(queryTimePrior.cid, comparisonVectors.current_expression_contract_cid);
  const temporalNames = ['current_timestamp', 'timestamp_add', 'timestamp_sub'];
  const stripTime = value => {
    if (Array.isArray(value)) return value.map(stripTime);
    if (!value || typeof value !== 'object') return value;
    const result = Object.fromEntries(Object.entries(value).map(([key, child]) => [key, stripTime(child)]));
    if (result.oneOf) result.oneOf = result.oneOf.filter(shape =>
      !temporalNames.includes(shape.properties?.op?.const) &&
      !temporalNames.some(name => shape.required?.includes(name)));
    return result;
  };
  const withoutTime = stripTime(currentExpression);
  for (const name of temporalNames) delete withoutTime.laws[name];
  withoutTime.grammar_sha256 = queryTimePrior.body.grammar_sha256;
  assert.deepEqual(withoutTime, queryTimePrior.body);
  // The admitted comparison extension changes exactly these two law positions.
  // Keep the complete earlier body and its identity rather than retargeting it.
  const priorAligned = structuredClone(queryTimePrior.body);
  delete priorAligned.laws.signed64_comparison_context;
  priorAligned.laws.lowering = comparisonPrior.laws.lowering;
  assert.deepEqual(priorAligned, comparisonPrior);
  assert.equal(canonicalText(expression.body), expression.canonicalPreimage);
  assert.equal(machineCid(expression.body), expression.cid);
  assert.equal(currentManifest.expression_contract_cid, machineCid(currentExpression));
  assert.equal(currentManifest.expression_text_grammar_sha256, currentExpression.grammar_sha256);
  // This retained transition binds its own grammar bytes, not later live extensions.
  const historicalGrammar = readFileSync(
    'scripts/fixtures/decimal-division-exact/expression-predecessor.ebnf');
  assert.equal(sha(historicalGrammar).slice(7), currentExpression.grammar_sha256);
  const currentAligned = {...currentManifest};
  for (const key of ['grammar_manifest_cid', 'query_text_grammar_sha256',
    'query_text_rules_sha256', 'expression_text_rules_sha256',
    'source_grammar_cid', 'expression_contract_cid',
    'expression_text_grammar_sha256']) currentAligned[key] = integrated.after[key];
  assert.deepEqual(currentAligned, integrated.after);
  for (const value of [integrated.frozen_before, integrated.main_before, integrated.after]) {
    const {grammar_manifest_cid: expected, ...body} = value;
    assert.equal(sha(canonicalText(body)), expected);
  }
  // Only the two normative query inputs and their identity change.
  const unchanged = {...integrated.after};
  for (const key of ['grammar_manifest_cid', 'query_text_grammar_sha256',
    'query_text_rules_sha256']) unchanged[key] = selection.after[key];
  assert.deepEqual(unchanged, selection.after);
  assert.equal(integrated.actual_parser_or_runtime_execution, 0);
  assert.equal(selection.actual_parser_or_runtime_execution, 0);
});

test('pinned manifests close over their source contracts and exact schemas', () => {
  const expected = expectedCompilationManifests();
  assert.deepEqual(verifyCompilationManifests(), expected);
  const {grammar_manifest_cid: _grammarSelf, ...grammarBody} = expected.grammar;
  const {barrier_contract_manifest_cid: _barrierSelf, ...barrierBody} =
    expected.barrier;
  assert.equal(expected.grammar.grammar_manifest_cid, machineCid(grammarBody));
  assert.equal(expected.barrier.barrier_contract_manifest_cid,
    machineCid(barrierBody));
  assert.deepEqual(read('spec/manifests/actql-grammar-0.1.json'),
    expected.grammar);
  assert.deepEqual(read('spec/manifests/actql-barrier-contracts-0.1.json'),
    expected.barrier);
  assert.deepEqual(read('spec/contracts/actql-compilation-manifests.json'),
    expected.contract);
});

test('current manifest metadata and canonical fixtures bind the complete document', () => {
  const family = read('spec/spec-family.json');
  const generated = readFileSync(
    'src/canonical_json/identity_vectors.generated_test.mbt', 'utf8');
  for (const path of ['spec/manifests/actql-grammar-0.1.json',
    'spec/manifests/actql-barrier-contracts-0.1.json']) {
    const document = read(path);
    // The registered machine import hashes the complete document, including
    // its self CID. It is not the manifest's self-field-free identity.
    const completeCid = sha(canonicalText(document));
    const selfCid = document.grammar_manifest_cid ??
      document.barrier_contract_manifest_cid;
    assert.notEqual(completeCid, selfCid);
    const owners = family.documents.flatMap(owner =>
      (owner.machine_contracts ?? []).filter(ref =>
        ref.path === path && ref.pointer === '').map(ref => ({owner, ref})));
    assert.equal(owners.length, 1, `one manifest owner: ${path}`);
    const [{owner, ref}] = owners;
    assert.equal(ref.cid, completeCid, `stale complete manifest pin: ${path}`);
    assert.ok(readFileSync(owner.path, 'utf8').includes(
      `<!-- machine-import: ${relative(dirname(owner.path), path)}# ${completeCid} -->`),
    `stale normative manifest import: ${path}`);
    const fixture = generateTests([{id: `contract ${path}#`,
      value: document, cid: completeCid}]);
    assert.ok(generated.includes(fixture.slice(fixture.indexOf('///|'))),
      `stale current canonical manifest fixture: ${path}`);
  }
});

test('signed-source-zero note preserves productions and the complete original identity transition', () => {
  // The retained corpus binds this complete transition without requiring
  // unavailable Git objects. Current selected inputs are checked separately.
  const transition = read('scripts/fixtures/signed-source-zero-grammar/identity-transition.json');
  assert.equal(transition.source_commit, 'dbe458ba94ffd4e4693592abf7540a9b2a1b88e6');
  assert.equal(transition.source_tree, '1debbdb7f02cdbcb0136b278328235d32bc4d246');
  const before = transition.before, after = transition.after;
  const previousGrammar = readFileSync('scripts/fixtures/signed-source-zero-grammar/expression-before.ebnf', 'utf8');
  const currentGrammar = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  assert.equal(sha(previousGrammar).slice(7), before.grammar_sha256);
  assert.equal(sha(currentGrammar).slice(7), after.grammar_sha256);
  assert.equal(before.grammar_sha256, '703dce737042c4b6e473b1618451f08d4f8fcc6391a6b2dd2e8f62e96722eaeb');
  assert.equal(after.grammar_sha256, '9e23a12f73ea54abb2ef855e26362d26a848c15b6bcb11003329f22168655816');
  const productions = source => source.replace(/\(\*[\s\S]*?\*\)/gu, '');
  assert.equal(productions(currentGrammar), productions(previousGrammar));
  const currentExpression = read('spec/contracts/actql-expressions.json');
  assert.deepEqual(currentExpression, {...before.expression_contract, grammar_sha256: after.grammar_sha256});
  assert.equal(machineCid(before.expression_contract), before.expression_contract_cid);
  assert.equal(machineCid(currentExpression), after.expression_contract_cid);
  assert.equal(before.expression_contract_cid, 'sha256:b5701b2178a3b2e624d0fbfbda877d0117c367e42a855161e26e0d2e133f1c2c');
  assert.equal(after.expression_contract_cid, 'sha256:2849a6667980fc51ed51a04879470a97068fd08e358d784262602a09b22dacda');
  for (const state of [before, after]) {
    const {grammar_manifest_cid, ...body} = state.grammar_manifest;
    assert.equal(machineCid(body), grammar_manifest_cid);
    assert.equal(machineCid(state.grammar_manifest), state.grammar_manifest_complete_cid);
    for (const [part, field] of [['template', 'bound_invocation_template_cid'], ['executable', 'executable_plan_cid'], ['compiled', 'compiled_plan_cid'], ['run', 'run_definition_cid']]) {
      const {[field]: expected, ...preimage} = state.sequence_values.run_preimages[part];
      assert.equal(machineCid(preimage), expected);
    }
  }
  const previous = Object.fromEntries(before.additional_contracts.map(record => {
    assert.equal(machineCid(record.body), record.cid);
    return [record.path, record.body];
  }));
  const next = Object.fromEntries(after.additional_contracts.map(record => {
    assert.equal(machineCid(record.body), record.cid);
    return [record.path, record.body];
  }));
  const operation = 'ACTQL.expression_fragment/0.1';
  const aoaPath = 'spec/contracts/actql-aoa.json';
  const registryPath = 'spec/dependencies/aoa-pipeline-registry.json';
  const environmentPath = 'spec/contracts/actql-check-environment.json';
  const expectedAoA = structuredClone(previous[aoaPath]);
  expectedAoA.expression_contract_cid = after.expression_contract_cid;
  for (const name of [operation, 'REL.derive.ordered']) {
    expectedAoA.execution_contracts[name].dependencies.expression_contract.cid = after.expression_contract_cid;
  }
  const fragmentCid = machineCid(expectedAoA.execution_contracts[operation]);
  const expectedRegistry = structuredClone(previous[registryPath]);
  expectedRegistry[operation].execution_contract.cid = fragmentCid;
  expectedAoA.target_registry_requirements[operation].execution_contract.cid = fragmentCid;
  const orderedCid = machineCid(expectedAoA.execution_contracts['REL.derive.ordered']);
  expectedRegistry['REL.derive'].execution_extensions.ordered_bindings.cid = orderedCid;
  expectedAoA.target_registry_requirements['REL.derive'].execution_extensions.ordered_bindings.cid = orderedCid;
  expectedAoA.pipeline_registry_cid = machineCid(expectedRegistry);
  assert.deepEqual(next[registryPath], expectedRegistry);
  assert.deepEqual(next[aoaPath], expectedAoA);
  const expectedEnvironment = structuredClone(previous[environmentPath]);
  expectedEnvironment.pushdown_contract_bodies.semantic_dependencies.expression_contract.cid = after.expression_contract_cid;
  assert.deepEqual(next[environmentPath], expectedEnvironment);
  assert.deepEqual(next[environmentPath], read(environmentPath));
  for (const [name, previousVectors] of Object.entries(before.stage_vectors)) {
    const currentVectors = after.stage_vectors[name];
    assert.deepEqual(currentVectors, read(`portability/corpus/${name}.json`));
    assert.equal(currentVectors.version, previousVectors.version);
    assert.equal(currentVectors.cases.length, previousVectors.cases.length);
    for (let i = 0; i < previousVectors.cases.length; i++) {
      const prior = previousVectors.cases[i], current = currentVectors.cases[i];
      const expected = structuredClone(prior);
      if (expected.envelope) {
        assert.equal(expected.envelope.expression_contract_cid, before.expression_contract_cid);
        assert.equal(machineCid(expected.envelope), expected.expected_cid);
        expected.envelope.expression_contract_cid = after.expression_contract_cid;
        assert.equal(machineCid(expected.envelope), current.expected_cid);
      }
      expected.expected_cid = current.expected_cid;
      assert.deepEqual(current, expected);
    }
  }
  const {grammar_manifest_cid: _beforeSelf, ...beforeBody} = before.grammar_manifest;
  const {grammar_manifest_cid: _afterSelf, ...afterBody} = after.grammar_manifest;
  assert.deepEqual(afterBody, {...beforeBody,
    expression_contract_cid: after.expression_contract_cid,
    expression_text_grammar_sha256: after.grammar_sha256});
  assert.deepEqual(after.grammar_manifest, read('spec/manifests/actql-grammar-0.1.json'));
  assert.deepEqual(after.sequence_values.grammar, after.grammar_manifest);
  assert.equal(after.sequence_values.aoa_contract_cid, machineCid(next[aoaPath]));
  // The prior authored current fixture lagged actual structural/Program inputs;
  // retain it as recorded, rather than relabel it as the actual parent manifest.
  assert.equal(before.sequence_fixture_equals_actual_manifest, false);
  assert.notDeepEqual(before.sequence_values.grammar, before.grammar_manifest);
  assert.notEqual(before.sequence_values.run_preimages.run.run_definition_cid,
    after.sequence_values.run_preimages.run.run_definition_cid);
  const current = sequenceIdentityOracle();
  assert.deepEqual(current, JSON.parse(readFileSync('scripts/fixtures/current-sequence-values-identities.json', 'utf8')));
  assert.deepEqual(current.grammar, JSON.parse(readFileSync('spec/manifests/actql-grammar-0.1.json', 'utf8')));
});

test('inference barrier binds the existing model Plan and adjacent fragment', () => {
  const {schema, cid} = verifyInferenceBarrierSchema();
  const modelPlan = read('spec/contracts/actql-stage-contracts.json').schemas.inference_plan;
  assert.equal(cid,
    'sha256:34f1a37cbaea973964f4cf84ca3806b2492df545b718042ad8057604c95cb6dd');
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(new Set(schema.required), new Set([
    ...modelPlan.required.filter(key => key !== 'self_cid'),
    'input_fragment_cid', 'barrier_cid',
  ]));
  assert.ok(!Object.hasOwn(schema.properties, 'self_cid'));
  for (const [name, property] of Object.entries(modelPlan.properties)) {
    if (name !== 'version' && name !== 'self_cid') {
      assert.deepEqual(schema.properties[name], property);
    }
  }
  assert.deepEqual(schema.properties.version,
    {const: 'actql-inference-barrier/0.1'});
  const barrier = expectedCompilationManifests().barrier;
  assert.deepEqual(barrier.contracts.find(entry => entry.name === 'inference_barrier'),
    {name: 'inference_barrier', contract_cid: cid});
});

test('published STORE retains the complete Program schema and grammar identity transition', () => {
  const vector = read('scripts/fixtures/published-store-grammar/manifest-identities.json');
  const prior = read(vector.prior_program_schema_file);
  // These complete schemas and manifests retain the STORE transition;
  // later COMMAND and current contracts remain independent.
  const after = read('portability/fixtures/program-grammar-before-published-command.json');
  assert.equal(machineCid(prior), vector.prior_program_schema_cid);
  assert.equal(machineCid(after), vector.current_program_schema_cid);
  for (const manifest of [vector.before, vector.after]) {
    const {grammar_manifest_cid, ...body} = manifest;
    assert.equal(sha(canonicalText(body)), grammar_manifest_cid);
  }
  const {grammar_manifest_cid: _before, source_grammar_cid: oldSource, ...oldBody} = vector.before;
  const {grammar_manifest_cid: _after, source_grammar_cid: newSource, ...newBody} = vector.after;
  assert.deepEqual(oldBody, newBody);
  assert.equal(oldSource, vector.prior_program_schema_cid);
  assert.equal(newSource, vector.current_program_schema_cid);
  assert.notEqual(oldSource, newSource);
  assert.deepEqual(read('portability/fixtures/grammar-before-published-command.json'), vector.after);

  // The approved selector is the sole schema delta. The old field branch is
  // retained exactly, rather than reconstructed from an old CID or a new name.
  assert.deepEqual(vector.program_schema_change_pointers,
    ['/properties/effects/additionalProperties/oneOf/4/properties/command/properties/target']);
  const restored = structuredClone(after);
  const target = restored.properties.effects.additionalProperties.oneOf[4]
    .properties.command.properties;
  assert.equal(target.target.oneOf.length, 2);
  const published = target.target.oneOf[1];
  assert.deepEqual(published.required, ['published_store']);
  assert.equal(published.additionalProperties, false);
  assert.deepEqual(published.properties.published_store.required, ['target_ref', 'mapping_ref']);
  assert.equal(published.properties.published_store.additionalProperties, false);
  target.target = target.target.oneOf[0];
  assert.deepEqual(restored, prior);
});
