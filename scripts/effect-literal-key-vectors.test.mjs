import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {checkEffectLiteralKeyVectors, currentEffectLiteralKeyVectors,
  exactDataJson} from './effect-literal-key-vectors.mjs';

const readCorpus = () => JSON.parse(readFileSync(new URL(
  '../portability/corpus/effect-literal-key-identities.json', import.meta.url), 'utf8'));

test('fixed raw Effect literal Stage and Program preimages are independent and complete', () => {
  assert.equal(checkEffectLiteralKeyVectors(readCorpus()), 10);
});

test('current literal identities change only the reviewed expression dependency and its hashes', () => {
  const original = readCorpus();
  const saved = structuredClone(original);
  const current = currentEffectLiteralKeyVectors(original);
  assert.deepEqual(original, saved, 'historical envelopes and CIDs are not rewritten');
  assert.equal(current[0].expected_definition_cid,
    'sha256:f6c723002f7d4930a03b8017b74b9896d885526266e78ecf24641b7282adb129');
  for (const [i, vector] of current.entries()) {
    assert.deepEqual(vector.payload, original.cases[i].payload);
    assert.deepEqual(vector.stage_envelope.local_body, original.cases[i].stage_envelope.local_body);
    assert.equal(vector.payload_preimage, original.cases[i].payload_preimage);
    assert.notEqual(vector.expected_program_cid, original.cases[i].expected_program_cid);
  }
  assert.notEqual(current[1].expected_definition_cid, current[2].expected_definition_cid);
  assert.equal(current[6].expected_definition_cid, current[7].expected_definition_cid);
  const expression = JSON.parse(readFileSync(new URL(
    '../spec/contracts/actql-expressions.json', import.meta.url), 'utf8'));
  expression.version = 'unreviewed';
  assert.throws(() => currentEffectLiteralKeyVectors(original, expression),
    /review the current expression dependency/);
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

// The old dependency remains historical data, not permission to accept an old
// governing contract for current reference identities.
test('current literal references reject the pre-ContentRef text/time dependency', () => {
  const expression = JSON.parse(readFileSync(new URL(
    '../spec/contracts/actql-expressions.json', import.meta.url), 'utf8'));
  expression.inherited_text_time_profile_cid =
    'sha256:2d41f38bd3bf8217d9bc394b1ca2ed9dfe6695b0088cd6a489328dabdee61dcc';
  assert.throws(() => currentEffectLiteralKeyVectors(readCorpus(), expression),
    /review the current expression dependency/);
});

// The adopted general-array grammar changes the containing Expression identity,
// never these authored literal bytes. The prior reviewed body remains a
// historical preimage and cannot authorize current fixture references.
test('current literal references reject the preceding grammar while retaining its preimages', () => {
  const sha = value => 'sha256:' + createHash('sha256')
    .update(exactDataJson(value)).digest('hex');
  const retained = JSON.parse(readFileSync(new URL(
    '../portability/corpus/historical/pre-signed64-stage-identities.json',
    import.meta.url), 'utf8'));
  assert.equal(retained.expression_contract_cid,
    'sha256:e7645d18471d4436b7542302adce28303a8a634ce29e9f5fd849f5cee8d1159e');
  assert.equal(sha(retained.expression_contract), retained.expression_contract_cid);
  assert.throws(() => currentEffectLiteralKeyVectors(readCorpus(), retained.expression_contract),
    /review the current expression dependency/);
  // Reconstruct that historical grammar predecessor from its complete original
  // body, never by deleting only a pin from a newer expression contract.
  const previous = {...retained.expression_contract,
    grammar_sha256: '02ac66c34edc5114f0b919e8c5a9e7b147f2154268e29b8e3b9b1ba1b8ed6222'};
  const previousCID = 'sha256:e4b8431ae81884a1e198420dcbd08d6b12ef4dca4bd9b7b8ffa4cd45db887289';
  assert.equal(sha(previous), previousCID);
  assert.throws(() => currentEffectLiteralKeyVectors(readCorpus(), previous),
    /review the current expression dependency/);
  const original = readCorpus().cases[0];
  const stage = {...original.stage_envelope, expression_contract_cid: previousCID};
  const program = structuredClone(original.program_envelope);
  program.expression_contract_cid = previousCID;
  program.program_template.stages[0].stage_semantics_cid = sha(stage);
  assert.equal(sha({...original.definition_envelope, program_semantics_cid: sha(program)}),
    'sha256:8e6ed397c9bd75c7f617d3a2645e29bf944a7fa090d1a22a9b84541f1de96762');
});
