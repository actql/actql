import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {checkEffectLiteralKeyVectors, exactDataJson} from './effect-literal-key-vectors.mjs';

const readCorpus = () => JSON.parse(readFileSync(new URL(
  '../portability/corpus/effect-literal-key-identities.json', import.meta.url), 'utf8'));

test('fixed raw Effect literal Stage and Program preimages are independent and complete', () => {
  assert.equal(checkEffectLiteralKeyVectors(readCorpus()), 10);
});

test('the fixture oracle sorts exact UTF-16 keys without JavaScript numeric-key reordering', () => {
  const input = JSON.parse(String.raw`{"2":2,"10":10,"\ue000":0,"\ud83d\ude00":1,
    "\u00e9":2,"e\u0301":3,"line\r\nkey":4,"line\nkey":5,"line\rkey":6,
    "__proto__":{"constructor":"data"},"":null}`);
  assert.equal(exactDataJson(input),
    '{"":null,"10":10,"2":2,"__proto__":{"constructor":"data"},' +
    '"e\u0301":3,"line\\nkey":5,"line\\r\\nkey":4,"line\\rkey":6,' +
    '"\u00e9":2,"\ud83d\ude00":1,"\ue000":0}');
});

test('the fixture oracle preserves nested String values and ordinary $json data', () => {
  const input = {nested: [{$json: {'\u00e9': 1, 'e\u0301': 2}}], text: 'e\u0301\r\n'};
  assert.equal(exactDataJson(input),
    '{"nested":[{"$json":{"e\u0301":2,"\u00e9":1}}],"text":"e\u0301\\r\\n"}');
  assert.equal(exactDataJson(null), 'null');
  assert.throws(() => exactDataJson(undefined));
  assert.throws(() => exactDataJson(Number.NaN));
});

test('fixture validation rejects payload normalization, synthetic defaults and stale pins', () => {
  const mutations = [
    ['normalized payload key', corpus => {
      corpus.cases.find(c => c.name === 'nfd-key').payload = {'\u00e9': 1};
    }],
    ['collapsed paired keys', corpus => {
      const c = corpus.cases.find(c => c.name === 'paired-keys');
      c.stage_envelope.local_body.effects.save.update.set.payload.literal = {'\u00e9': 2};
    }],
    ['synthesized Stage default', corpus => {
      corpus.cases[0].stage_envelope.local_body.from = 'selected';
    }],
    ['Stage preimage', corpus => { corpus.cases[0].stage_preimage += ' '; }],
    ['Program preimage', corpus => { corpus.cases[0].program_preimage += ' '; }],
    ['Definition preimage', corpus => { corpus.cases[0].definition_preimage += ' '; }],
    ['Stage CID', corpus => { corpus.cases[0].expected_stage_cid = `sha256:${'0'.repeat(64)}`; }],
    ['Program CID', corpus => { corpus.cases[0].expected_program_cid = `sha256:${'0'.repeat(64)}`; }],
    ['Definition CID', corpus => { corpus.cases[0].expected_definition_cid = `sha256:${'0'.repeat(64)}`; }],
  ];
  for (const [label, mutate] of mutations) {
    const corpus = readCorpus();
    mutate(corpus);
    assert.throws(() => checkEffectLiteralKeyVectors(corpus), {name: 'AssertionError'}, label);
  }
});
