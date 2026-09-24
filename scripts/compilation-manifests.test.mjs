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
