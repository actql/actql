import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';
import {queryTimeAcquisitionVectors} from './query-time-acquisition-vectors.mjs';
import {generateQueryEvidenceVectors} from './query-evidence-vectors.mjs';

// New bound-owner examples remain independent data preimages, not product
// compiler outputs or issued capture evidence.
const queryTimeVectors = queryTimeAcquisitionVectors(
  JSON.parse(readFileSync('portability/corpus/query-acquisition-identities.json', 'utf8')),
);
assert.deepEqual(JSON.parse(readFileSync('portability/corpus/query-time-acquisition-identities.json', 'utf8')),
  queryTimeVectors);
assert.equal(readFileSync('src/canonical_json/query_time_acquisition.generated_test.mbt', 'utf8'),
  generateQueryEvidenceVectors('query_time_acquisition', queryTimeVectors));

// Fixture copies carry full shared bodies into filesystem-free target tests.
// Pins and record expectations are independently fixed, never generated here.
for (const path of ['src/query_planning/evidence_bodies_wbtest.mbt', 'src/query_integration/query_evidence_bodies_wbtest.mbt']) {
  const text = readFileSync(path, 'utf8');
  for (const [index, name] of ['actql-query-acquisition', 'actql-query-process-evidence'].entries()) {
    const match = text.match(new RegExp(`let body${index} = @json\\.parse\\(\\s*("(?:[^"\\\\]|\\\\.)*")\\s*,?\\s*\\)`));
    assert.ok(match, `Missing body${index} fixture in ${path}`);
    const fixture = JSON.parse(JSON.parse(match[1]));
    const current = JSON.parse(readFileSync(`spec/contracts/${name}.json`, 'utf8'));
    assert.deepEqual(fixture, current, `${name} fixture in ${path} must match the complete shared body`);
  }
}
{
  const path = 'src/client_local_host/original_row_contracts_wbtest.mbt';
  const text = readFileSync(path, 'utf8');
  for (const [field, name] of [
    ['original_row_query_contract_fixture', 'actql-query-acquisition'],
    ['original_row_evidence_contract_fixture', 'actql-query-process-evidence'],
  ]) {
    const match = text.match(new RegExp(`let ${field} : String =\\s*("(?:[^"\\\\]|\\\\.)*")`));
    assert.ok(match, `Missing ${field} fixture in ${path}`);
    assert.deepEqual(JSON.parse(JSON.parse(match[1])),
      JSON.parse(readFileSync(`spec/contracts/${name}.json`, 'utf8')),
      `${name} original row fixture must match the complete shared body`);
  }
}
{
  const path = 'src/query_integration/query_two_receipt_body_wbtest.mbt';
  const text = readFileSync(path, 'utf8');
  const match = text.match(/@json\.parse\(\s*("(?:[^"\\]|\\.)*")\s*,?\s*\)/);
  assert.ok(match, `Missing two-receipt body fixture in ${path}`);
  assert.deepEqual(JSON.parse(JSON.parse(match[1])),
    JSON.parse(readFileSync('spec/contracts/actql-query-two-receipt.json', 'utf8')));
}
console.log('Query evidence fixture bodies match the shared contracts.');

// Current verifier pins select the complete original bodies. A matching version
// or fixture alone must not leave the actual Owner interpreting an older body.
const contracts = new Map(['actql-query-acquisition', 'actql-query-process-evidence',
  'actql-query-two-receipt', 'actql-query-resource-scopes'].map(name =>
  [name, JSON.parse(readFileSync(`spec/contracts/${name}.json`, 'utf8'))]));
for (const [name, body] of contracts) for (const [key, dependency] of Object.entries(body.dependencies)) {
  const root = JSON.parse(readFileSync(dependency.path, 'utf8'));
  const original = dependency.pointer.split('/').slice(1).reduce((value, part) =>
    value?.[part.replace(/~1/g, '/').replace(/~0/g, '~')], root);
  assert.notEqual(original, undefined, `${name}: missing original dependency ${key}`);
  assert.equal(machineCid(original), dependency.cid, `${name}: stale original dependency ${key}`);
}
for (const [path, pattern, name] of [
  ['src/sourceview_resolution/query_acquisition.mbt', /pub fn query_acquisition_contract_cid\(\) -> String \{\s*"(sha256:[a-f0-9]{64})"\s*\}/u, 'actql-query-acquisition'],
  ['src/execution_relation/row_wire_identity.mbt', /pub fn ordered_rows_canonical_contract_cid\(\) -> String \{\s*"(sha256:[a-f0-9]{64})"\s*\}/u, 'actql-query-acquisition'],
  ['src/query_planning/evidence_contracts.mbt', /let query_evidence_contract_cid : String = "(sha256:[a-f0-9]{64})"/u, 'actql-query-process-evidence'],
  ['src/query_planning/two_receipt_contract.mbt', /let query_two_receipt_cid : String = "(sha256:[a-f0-9]{64})"/u, 'actql-query-two-receipt'],
]) {
  const match = readFileSync(path, 'utf8').match(pattern);
  assert.ok(match, `Missing original verifier pin: ${path}`);
  assert.equal(match[1], machineCid(contracts.get(name)), `Stale actual verifier pin: ${path}`);
}
console.log('Query verifier pins and original dependency bodies are current.');
