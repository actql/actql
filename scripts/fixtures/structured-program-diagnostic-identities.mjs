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
  assert.equal(reasonCid, 'sha256:3d0c78252f42ea8b2edc7a8bbea8d7ccf27ee4d2980b5889c9c191d5f0f3476a');
  assert.equal(outcomeCid, 'sha256:dbc59a5b3911315f28f04a4eb93808f56a85338cdb514c4a0546fedff0f1d6c9');
  assert.deepEqual(vectors.map(value => value.reference), [
    'ctx:e1fe2957876c91a71df6d68a36a15ce567ef29f55f18861b547c5b26c18b4b25',
    'ctx:854a2a2f8e1ed51917dc2e13048ce0ab51d2e2a16b37b1b943bf63b1c2743948',
    'ctx:a3adfdb67e02669c52f7d4fbce763f683151636a8482070b9b556e8e7fa30542',
    'ctx:16ca46d5b9547ae8a730f901d663c259cfffe0d47062b8cc79296edecc547c4c',
  ]);
});
