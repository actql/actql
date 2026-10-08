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
  assert.equal(outcomeCid, 'sha256:c7e11c497b3d0ab58adc69c1ec04e4a44e6420aed7f0981e8e9741d2c3af8b5f');
  assert.deepEqual(vectors.map(value => value.reference), [
    'ctx:e253dec29f7608a4d55b39a44e6604b971ca798b51b456ced639635a1301a1ac',
    'ctx:793e011aa5396fa63f71ccdad893ad6d1ec9e9185979ecea2cd570101e1a6999',
    'ctx:be19f688e387012ab6d19df30a39911ee94ba1b9c6f0f8b033d6f9404bff94a4',
    'ctx:940f9d88e8e4a16e9c4dd3bb8bd3e0a05783e473b0a38f425a41641e5d51997d',
  ]);
});
