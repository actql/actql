// Independent schema and fixed context preimages. No product imports or output.
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash, createHmac} from 'node:crypto';
const root = fileURLToPath(new URL('../../', import.meta.url));
const sorted = value => value && typeof value === 'object'
  ? Array.isArray(value) ? '[' + value.map(sorted).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + sorted(value[key])).join(',') + '}'
  : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(sorted(value)).digest('hex');
const catalog = JSON.parse(readFileSync(root + 'spec/contracts/actql-check-reason-catalog.json'));
const registry = JSON.parse(readFileSync(root + 'spec/contracts/actql-protocol-schemas.json'));
const reason = structuredClone(catalog.reason_schema);
for (const variant of reason.properties.facts.oneOf) {
  if (variant.properties.admission) variant.properties.admission.properties.contract_schema_cid.const = cid(registry.schemas.canonical_value_contract);
}
const reasonCid = cid(reason), outcomeCid = cid(registry.artifact_schemas.check_outcome);
if (sorted(reason) !== sorted(registry.artifact_schemas.check_reason)) throw Error('RegisteredReasonBodyMismatch');
if (reasonCid !== registry.artifact_schema_cids.check_reason || outcomeCid !== registry.artifact_schema_cids.check_outcome) throw Error('IndependentSchemaPinMismatch');
const base = {version: 'actql-check-context/0.1', audience: 'owner',
  disclosure_policy: 'actql-check-disclosure/0.1', projection: 'actql-check-outcome/0.1', scope: 'bound_input',
  compiler: {compiler: 'fixture'}, reason_schema_cid: reasonCid, outcome_schema_cid: outcomeCid,
  checking_context: {host_policy_profile: {}, model_task_contract_cids: [], profiles: {}}, visible_aliases: []};
const vectors = [];
for (const declarations of [undefined, {'é': {type: 'string'}, 'e\u0301': {type: 'string'}}]) {
  for (const text of ["SELECT 'café' AS label", "SELECT 'cafe\u0301' AS label"]) {
    const input = {text, format: 'sql', ...(declarations === undefined ? {} : {parameterDeclarations: declarations})};
    const preimage = {...base, ...(declarations === undefined ? {source: {format: 'sql', text},
      parameter_declarations: null, parameters: null} : {received: JSON.stringify({input, parameters: null})})};
    vectors.push({preimage, reference: 'ctx:' + createHmac('sha256', new Uint8Array(32).fill(7)).update(sorted(preimage)).digest('hex')});
  }
}
test('independent structured Program schema and preserved Unicode context identities', () => {
  assert.equal(reasonCid, 'sha256:332a61df6738e4e21d916345f31f2ae28aec30cd779cd614dba2a24044f061e6');
  assert.equal(outcomeCid, 'sha256:b1062306669a530f532faa3b7fc5d24e34bd72aeae712c177cee7557216ea464');
  assert.deepEqual(vectors.map(value => value.reference), [
    'ctx:7e6a75a0778f44cdc06c629cdeb651fe9b8e55516aae902d7bf2aa415903b8f1',
    'ctx:4be39746e04fc14efed9d0d726175b4f9bb509e3a2ddc1c5b990580625222d25',
    'ctx:33cdbdb8b73e3bba97b0bd259e9985989e04b875a2dff2c1baeb0bbd9dd40e4e',
    'ctx:a76e0913e9d419539eede57aa85f6a63b34b94dee0585ada1fa6c881226c79db',
  ]);
});
