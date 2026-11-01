import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {readHistoricalJson} from './historical-json.mjs';

// Hash authored preimages independently; never derive expectations from evaluation.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const digest = value => createHash('sha256').update(value).digest('hex');
const cid = value => `sha256:${digest(canonical(value))}`;
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const history = readHistoricalJson('portability/corpus/historical/pre-general-array-membership-contract-identities.json');
const previous = Object.fromEntries(history.contracts.map(entry => [entry.id, entry.body]));

test('general ARRAY membership retains exact predecessor bodies and authored envelopes', () => {
  assert.equal(history.source_revision, 'd062aa0f5992d3e2bf3fe4b9acac1f0ff34d26d0');
  assert.equal(history.source_tree, 'b7f8612aaa0444b8c71e0594f7fbcf06e618bbf4');
  assert.equal(cid(history), 'sha256:e413d080f256e6123982af9aa864b300ba98eaf51e42a6e38f0a1e7a0a5162d3');
  assert.equal(history.contracts.length, 2);
  assert.equal(history.sources.length, 12);
  for (const entry of [...history.contracts, ...history.sources]) assert.equal(cid(entry.body), entry.cid);
  assert.equal(digest(history.expression_text_grammar), previous.expression_contract.grammar_sha256);
  assert.equal(digest(history.expression_text_rules), previous.grammar_manifest.expression_text_rules_sha256);
  const grammarBody = {...previous.grammar_manifest};
  delete grammarBody.grammar_manifest_cid;
  assert.equal(cid(grammarBody), previous.grammar_manifest.grammar_manifest_cid);
});

test('general ARRAY membership changes grammar identity without changing schemas or membership laws', () => {
  const expression = read('spec/contracts/actql-expressions.json');
  const grammar = readFileSync(expression.grammar, 'utf8');
  assert.match(grammar, /membership_rhs\s*=\s*"\(",\s*in_item,\s*\{\s*",",\s*in_item\s*\},\s*"\)"\s*\|\s*unary\s*;/u);
  assert.match(history.expression_text_grammar, /membership_rhs[^;]+\| parameter ;/u);
  assert.equal(expression.grammar_sha256, digest(grammar));
  assert.notEqual(expression.grammar_sha256, previous.expression_contract.grammar_sha256);
  // The signed64 predecessor retains the exact adopted general-array successor.
  // Later scalar and text/time changes are not part of this grammar transition.
  const successor = read('portability/corpus/historical/pre-signed64-stage-identities.json');
  assert.equal(successor.expression_contract_cid,
    'sha256:e7645d18471d4436b7542302adce28303a8a634ce29e9f5fd849f5cee8d1159e');
  assert.equal(cid(successor.expression_contract), successor.expression_contract_cid);
  assert.equal(successor.expression_contract.grammar_sha256,
    '3138560ad7c029b23bee2d7446f1ee8155520ead50281aae1493f0219db7bc5c');
  assert.deepEqual({...successor.expression_contract,
    grammar_sha256: previous.expression_contract.grammar_sha256}, previous.expression_contract);
  assert.notEqual(cid(expression), cid(previous.expression_contract));
  assert.equal(read('spec/manifests/actql-grammar-0.1.json').expression_contract_cid, cid(expression));
});
