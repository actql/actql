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
const fixed = JSON.parse(readFileSync(root + 'portability/corpus/text-enumeration-identities.json'));
const current = JSON.parse(readFileSync(root + 'scripts/fixtures/check-consumer-condition-historical.json'));
const preceding = JSON.parse(readFileSync(root + 'portability/corpus/signed64-identities.json'));
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
  assert.equal(reasonCid, current.checkSchemas.reason.cid);
  assert.equal(outcomeCid, current.checkSchemas.outcome.cid);
  assert.deepEqual(vectors.map(value => value.preimage), current.currentStructuredCheckContexts.map(value => value.preimage));
  assert.deepEqual(vectors.map(value => value.reference), current.currentStructuredCheckContexts.map(value => value.reference));
});

// Preserve earlier fixed Unicode contexts under their original schema identity.
test('prior check contexts retain their original outcome schema binding', () => {
  const before = vectors.map(({preimage}) => 'ctx:' + createHmac('sha256',
    new Uint8Array(32).fill(7)).update(sorted({...preimage,
      reason_schema_cid: fixed.checkSchemas.previousOriginal.reasonCid,
      outcome_schema_cid: "sha256:8963bb2355a4bd563f01695dcc7fc2900b15a219d7afd56375e127322bf9e03a"})).digest('hex'));
  assert.deepEqual(before, [
  "ctx:80369faf12208149b9ed3992dafae8e72e955a4f31bf820a5f2a7c837ab14806",
  "ctx:91725373a39aca341824d174d6c621042c500ac52e132356e0a6027e9c0416cb",
  "ctx:d4ee8e62ba79da9fe692a90b3c65550511ac663c169cc263ad7beee77675d18b",
  "ctx:94b3109c0130863296f30c82d0f9ac03f00990973df6b4b36b6c5e1511c1a082"
]);
  assert.ok(before.every((value, index) => value !== vectors[index].reference));
});

// A new checked-grammar dependency changes current contexts, never the
// original schema pair or Unicode bytes of these retained predecessor inputs.
test('pre-enum structured contexts keep both original checked schema bindings', () => {
  const original = fixed.checkSchemas.previousOriginal;
  const retained = vectors.map(({preimage}) => ({...preimage,
    reason_schema_cid: original.reasonCid, outcome_schema_cid: original.outcomeCid}));
  assert.deepEqual(retained, fixed.previousStructuredCheckContexts.map(value => value.preimage));
  assert.deepEqual(retained.map(preimage => 'ctx:' + createHmac('sha256',
    new Uint8Array(32).fill(7)).update(sorted(preimage)).digest('hex')),
    fixed.previousStructuredCheckContexts.map(value => value.reference));
});

// New binding-condition contexts do not rewrite the complete Signed64 originals.
test('preceding Signed64 structured contexts retain their original schema pair and Unicode bytes', () => {
  assert.deepEqual(preceding.checkSchemas.reason.body, current.reason);
  assert.deepEqual(preceding.checkSchemas.outcome.body, current.outcome);
  const retained = vectors.map(({preimage}) => ({...preimage,
    reason_schema_cid: preceding.checkSchemas.reason.cid,
    outcome_schema_cid: preceding.checkSchemas.outcome.cid}));
  assert.deepEqual(retained, preceding.currentStructuredCheckContexts.map(value => value.preimage));
  assert.deepEqual(retained.map(preimage => 'ctx:' + createHmac('sha256',
    new Uint8Array(32).fill(7)).update(sorted(preimage)).digest('hex')),
  preceding.currentStructuredCheckContexts.map(value => value.reference));
});
