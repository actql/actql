import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

// Frozen normative Git input, not output from the new checker or catalog issuer.
// The original boundary had no legacy emitter or published catalog body.
const fixture = JSON.parse(readFileSync(
  'scripts/fixtures/pre-public-check-diagnostic-contract.json', 'utf8'));
const current = JSON.parse(readFileSync(fixture.source_path, 'utf8'));
const historical = JSON.parse(execFileSync('git',
  ['show', `${fixture.source_revision}:${fixture.source_path}`],
  {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024}));
// Independent accepted PlanResult original after the non-invalid planning arms
// gained their current contracts. The retained diagnostic branch stays frozen.
const currentPlanResult = Object.freeze({
  revision: 'e94313f3d5cf5238d14e867fb36267e772d953c3',
  registryBlob: '292a43c397d35a7010d4929fe4630fbd941628e7',
  specFamilyBlob: '25b41f7926896e2a2105002ef4bc0e545839357e',
  schemaCid: 'sha256:30b762e781c467c305110ca83ad9b724275422380eb060b3c6654d7d6807583b',
});
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const invalid = registry => registry.artifact_schemas.plan_result.oneOf.find(
  branch => branch.properties.status?.const === 'invalid');
const pin = family => family.documents.find(owner => owner.spec_id === fixture.machine_owner)
  .machine_contracts.find(reference => reference.pointer === fixture.machine_import.pointer);

test('legacy diagnostic payload retains the frozen schema and identity', () => {
  assert.equal(execFileSync('git', ['rev-parse',
    `${fixture.source_revision}:${fixture.source_path}`], {encoding: 'utf8'}).trim(), fixture.source_blob);
  assert.deepEqual(invalid(historical), fixture.invalid_branch);
  assert.equal(cid(fixture.invalid_branch), fixture.invalid_branch_cid);
  assert.deepEqual(invalid(current), fixture.invalid_branch,
    '[check-mutation:legacy-diagnostic-body]');
  assert.equal(cid(historical.artifact_schemas.plan_result), fixture.plan_result_schema_cid);
  const selectedRegistry = `${currentPlanResult.revision}:${fixture.source_path}`;
  assert.equal(execFileSync('git', ['rev-parse', selectedRegistry], {encoding: 'utf8'}).trim(),
    currentPlanResult.registryBlob);
  const selected = JSON.parse(execFileSync('git', ['show', selectedRegistry],
    {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024}));
  assert.equal(cid(selected.artifact_schemas.plan_result), currentPlanResult.schemaCid);
  assert.equal(selected.artifact_schema_cids.plan_result, currentPlanResult.schemaCid);
  assert.equal(cid(current.artifact_schemas.plan_result), currentPlanResult.schemaCid,
    '[check-mutation:legacy-diagnostic-identity]');
});

test('legacy planning registry and spec-family pin retain the historical identity', () => {
  const historicalFamily = JSON.parse(execFileSync('git',
    ['show', `${fixture.source_revision}:${fixture.spec_family_path}`], {encoding: 'utf8'}));
  assert.equal(execFileSync('git', ['rev-parse',
    `${fixture.source_revision}:${fixture.spec_family_path}`], {encoding: 'utf8'}).trim(), fixture.spec_family_blob);
  assert.deepEqual(pin(historicalFamily), fixture.machine_import);
  assert.equal(historical.artifact_schema_cids.plan_result, fixture.plan_result_schema_cid);
  const selectedFamily = `${currentPlanResult.revision}:${fixture.spec_family_path}`;
  assert.equal(execFileSync('git', ['rev-parse', selectedFamily], {encoding: 'utf8'}).trim(),
    currentPlanResult.specFamilyBlob);
  const expected = {...fixture.machine_import, cid: currentPlanResult.schemaCid};
  assert.deepEqual(pin(JSON.parse(execFileSync('git', ['show', selectedFamily], {encoding: 'utf8'}))), expected);
  assert.equal(current.artifact_schema_cids.plan_result, currentPlanResult.schemaCid,
    '[check-mutation:legacy-diagnostic-registry]');
  assert.deepEqual(pin(JSON.parse(readFileSync(fixture.spec_family_path, 'utf8'))), expected,
    '[check-mutation:legacy-diagnostic-pin]');
});

test('public check remains a distinct diagnostic contract', () => {
  for (const branch of current.artifact_schemas.check_outcome.oneOf) {
    assert.equal(branch.properties.version.const, 'actql-check-outcome/0.1');
  }
  assert.notEqual(current.artifact_schema_cids.check_outcome, fixture.plan_result_schema_cid);
  assert.equal(current.artifact_schema_cids.check_outcome, cid(current.artifact_schemas.check_outcome));
  assert.equal(JSON.parse(readFileSync('spec/contracts/actql-check-reason-catalog.json', 'utf8')).version,
    'actql-check-reason-catalog/0.1');
  assert.equal(invalid(current).properties.diagnostics.properties.version.const, 'actql-diagnostics/0.1');
});
