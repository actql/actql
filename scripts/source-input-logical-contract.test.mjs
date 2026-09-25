import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {verifyIdentity} from './check-canonical-json.mjs';
import {admitSourceInputLogical, checkSourceInputLogicalSchema,
  sourceInputLogicalCid} from './source-input-logical-contract.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const other = value => `sha256:${value.repeat(64)}`;

test('source input logical identity has an independent canonical vector', () => {
  const corpus = read('portability/corpus/source-input-logical.json');
  assert.equal(corpus.version, 'actql-source-input-logical-vectors/0.1');
  assert.equal(corpus.cases.length, 1);
  const {body, expected_cid: expectedCid,
    expected_canonical_bytes: bytes} = corpus.cases[0];
  verifyIdentity(body, expectedCid, bytes);
  assert.equal(sourceInputLogicalCid(body), expectedCid);
  const envelope = {...body, input_logical_cid: expectedCid};
  const observed = {
    logicalRelationCid: body.logical_relation_cid,
    relationSchemaCid: body.relation_schema_cid,
    sourceContractCid: body.source_contract_cid,
    completeness: body.completeness,
    orderingEvidence: body.ordering_evidence,
  };
  assert.equal(admitSourceInputLogical(envelope, observed), expectedCid);
  for (const [field, value] of [
    ['logical_relation_cid', other('e')],
    ['source_contract_cid', other('e')],
    ['relation_schema_cid', other('e')],
    ['completeness', 'partial'],
    ['ordering_evidence', {stable: false, keys: []}],
  ]) {
    const changed = {...body, [field]: value};
    assert.notEqual(sourceInputLogicalCid(changed), expectedCid);
    assert.throws(() => admitSourceInputLogical(
      {...changed, input_logical_cid: sourceInputLogicalCid(changed)},
      observed));
  }
  assert.throws(() => admitSourceInputLogical({...envelope,
    input_logical_cid: other('0')}, observed));
  assert.throws(() => sourceInputLogicalCid({...body, physical_attempt: 'x'}));
});

test('source input logical schema and registry retain their pins', () => {
  checkSourceInputLogicalSchema(
    read('spec/contracts/actql-protocol-schemas.json'));
});
