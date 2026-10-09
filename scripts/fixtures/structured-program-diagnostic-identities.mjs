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
  assert.equal(reasonCid, 'sha256:4f1765448e0d74588ba004181c3db6e86b0c473c52f406b02c4323fb416e733f');
  assert.equal(outcomeCid, 'sha256:ab1bf953cb535e2236dde42121360f85ccbb42727e146675f9f979edd0b31216');
  assert.deepEqual(vectors.map(value => value.reference), [
    'ctx:1b4221ce201f43fbec6e5b3d4a097285cbab9abe9ffe49798ba17f4cda2cb1c8',
    'ctx:0f958c8e7ea0244d9373f9d81b3f45bada7ff79ee64de6b779f896dcc21e8afd',
    'ctx:fe3dd5255bb97b54efe28f070b2ed987c4f5cc22aafdeffc722a2089f6f8a1e5',
    'ctx:c3ae35f7c2b8a83b2ff4fd30d5537c1bdba13ef873858daab469b1b8632f4a2c',
  ]);
});
