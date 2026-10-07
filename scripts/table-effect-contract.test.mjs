import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';
import {checkTableEffectContract, checkTableOperation, localTablePhysicalContract} from
  './table-effect-contract.mjs';
import {authoredTableVectors, tableMoonVectors, authoredLocalTableReceiptVectors,
  localTableMoonVectors} from './table-effect-vectors.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const corpus = read('portability/corpus/table-effect.json');
const request = corpus.cases.find(entry => entry.id === 'create').body;
const reseal = body => {
  const {request_cid: _, ...preimage} = body;
  return {...preimage, request_cid: machineCid(preimage)};
};

test('Table provider envelopes retain their exact narrow contract', () => {
  checkTableEffectContract(read('spec/contracts/actql-table-effect.json'));
  assert.deepEqual(read('spec/contracts/actql-local-table-iceberg.json'), localTablePhysicalContract());
  assert.equal(read('spec/contracts/actql-table-effect.json').schemas.receipt.properties.metadata_location, undefined);
  assert.equal(read('spec/contracts/actql-table-effect.json').schemas.receipt.properties.snapshot_id, undefined);
});

test('Local physical evidence and logical receipts have separate independently sealed identities', () => {
  assert.equal(readFileSync('src/connectors/local/table/receipt_vectors.generated_wbtest.mbt', 'utf8'),
    localTableMoonVectors());
  for (const {physical, logical} of authoredLocalTableReceiptVectors()) {
    for (const body of [physical, logical]) {
      const {receipt_cid, ...preimage} = body;
      verifyIdentity(preimage, receipt_cid);
    }
    assert.notEqual(physical.receipt_cid, logical.receipt_cid);
    assert.equal(logical.physical_receipt_cid, physical.receipt_cid);
  }
});

test('Table request/receipt vectors use independently authored preimages', () => {
  assert.deepEqual(corpus, authoredTableVectors());
  for (const entry of corpus.cases) {
    const field = Object.hasOwn(entry.body, 'receipt_cid')
      ? 'receipt_cid' : 'request_cid';
    const {[field]: expected, ...preimage} = entry.body;
    verifyIdentity(preimage, expected);
    assert.equal(expected, entry.expected_cid);
  }
  assert.equal(readFileSync(
    'src/effect_application/table_vectors.generated_wbtest.mbt', 'utf8'),
  tableMoonVectors(corpus));
});

test('create and guarded replace refuse changed binding and mixed preconditions', () => {
  checkTableOperation(request);
  const replace = corpus.cases.find(entry => entry.id === 'replace').body;
  checkTableOperation(replace);
  for (const key of ['effect_identity_cid', 'input_artifact_cid',
    'input_relation_cid', 'schema_cid', 'storage_mapping_cid', 'data_policy_cid']) {
    assert.throws(() => checkTableOperation({...request,
      [key]: `sha256:${'f'.repeat(64)}`}));
  }
  assert.throws(() => checkTableOperation(reseal({...request,
    expected_table: replace.expected_table})));
  assert.throws(() => checkTableOperation(reseal({...replace,
    expected_table: null})));
  assert.throws(() => checkTableOperation(reseal({...request,
    item_key: 'invented-row-key'})));
  assert.throws(() => checkTableOperation(reseal({...request, namespace: []})));
  assert.throws(() => checkTableOperation(reseal({...request,
    table_name: 'e\u0301'})));
});

test('original operation binding does not collapse into name or current head', () => {
  const changedEffect = reseal({...request,
    effect_identity_cid: `sha256:${'e'.repeat(64)}`});
  const changedRun = reseal({...request,
    logical_request_scope_cid: `sha256:${'e'.repeat(64)}`});
  checkTableOperation(changedEffect);
  checkTableOperation(changedRun);
  assert.notEqual(changedEffect.request_cid, request.request_cid);
  assert.notEqual(changedRun.request_cid, request.request_cid);
  const contract = read('spec/contracts/actql-table-effect.json');
  assert.equal(contract.semantics.unknown,
    'reconcile_original_operation_no_resend_no_potentially_published_file_cleanup');
});

// JSON Schema maxLength and common admission count Unicode scalar values.
test('Table name and namespace length preserve supplementary Unicode boundaries', () => {
  for (const field of ['table_name', 'namespace']) {
    const input = value => reseal({...request,
      [field]: field === 'namespace' ? [value] : value});
    checkTableOperation(input('😀'.repeat(256)));
    assert.throws(() => checkTableOperation(input('😀'.repeat(257))));
    assert.throws(() => checkTableOperation(input('\ud800')));
  }
});
