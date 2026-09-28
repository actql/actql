import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
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
