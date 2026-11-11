// Actual same-source Common quantity/recipe constructors. No Resource reserve,
// Account/Credential, physical send, normal installation or cleanup is mocked
// into acceptance by these DATA/slot correspondence cases.
import assert from 'node:assert/strict';
import test from 'node:test';
import {captureKintoneEffectPlanRecipeBuilder} from '../host/kintone-effect-plan.mjs';
import {selectInstalledEffectCredentialOperation} from '../../../host-node/installed-effect-plan.mjs';
import {fixture as nativeFixture, policy} from './kintone-update.fixture.mjs';

function fixture() {
  const f = nativeFixture(), moon = f.moon;
  const prepare = captureKintoneEffectPlanRecipeBuilder({moon});
  const options = {mapping: f.options.mapping, fields: Object.freeze(['Computed', 'Subject', 'Tags']),
    formResource: 'inquiries-form', bindingUnits: 1000,
    credentialSite: {construction: {scope: {connectorRegistration: 'kintone', resourceOrigin: f.options.origin},
      issuer: {keyId: 'component'}, limits: {maxSecretBytes: 256}}}, limits: Object.freeze({...policy}),
    inputLimits: {body: {maxBytes: 2048, maxNodes: 8000, maxDepth: 32},
      preview: {maxWireBytes: 65536, maxNodes: 8000, maxDepth: 32}}, maxRecoveryBytes: 65536};
  return {f, prepare, options};
}

test('kintone recipe constructs thirteen distinct original physical slots in the existing Common owner', () => {
  const f = fixture(), plan = f.prepare(f.options);
  assert.equal(plan.credentialOperations.length, 13);
  assert.equal(plan.memberOperations.length, 5); assert.equal(plan.rowOperations.length, 12);
  const positions = new Set();
  for (const entry of plan.credentialOperations) {
    const location = (entry.perRow === false ? 'member:' : 'row:') + entry.operationIndex;
    assert(!positions.has(location)); positions.add(location);
  }
  for (const phase of ['capture', 'apply', 'resume']) {
    const describe = selectInstalledEffectCredentialOperation(plan, phase + '-describe', 'schema');
    assert.equal(describe.resource, 'inquiries-form'); assert.equal(describe.perRow, false);
    assert.equal(plan.memberOperations[describe.operationIndex].operation, 'kintone:form:read');
    for (const slot of ['schema-before', 'target', 'schema-after']) {
      const entry = selectInstalledEffectCredentialOperation(plan, phase + '-target', slot);
      assert.equal(entry.perRow, true);
      assert.equal(entry.resource, slot === 'target' ? undefined : 'inquiries-form');
      assert.equal(plan.rowOperations[entry.operationIndex].operation,
        slot === 'target' ? 'kintone:records:target-read' : 'kintone:form:read');
    }
  }
  const write = selectInstalledEffectCredentialOperation(plan, 'write', undefined);
  assert.equal(plan.rowOperations[write.operationIndex].operation, 'kintone:records:update');
  assert.notEqual(plan.requestConstruction.operationIndex, plan.requestFinalization.operationIndex);
  assert.equal(f.f.calls.clientProgramKintoneUpdateRecipeCapacities > 0, true);
});

test('kintone physical response extents keep same-slot actual byte and original bounds correspondence', () => {
  const f = fixture(), plan = f.prepare(f.options);
  for (const slot of ['schema-before', 'target', 'schema-after']) {
    const selected = selectInstalledEffectCredentialOperation(plan, 'apply-target', slot);
    assert(selected.responseExtent(0, Buffer.alloc(0)));
    assert(selected.responseExtent(97, Buffer.alloc(97)));
    assert.throws(() => selected.responseExtent(97, Buffer.alloc(96)), {code: 'KintoneEffectRecipeUnavailable'});
    assert.throws(() => selected.responseExtent(-1, Buffer.alloc(0)), {code: 'KintoneEffectRecipeUnavailable'});
    assert.throws(() => selected.responseExtent(policy.maxResponseBytes + 1, Buffer.alloc(0)),
      {code: 'KintoneEffectRecipeUnavailable'});
  }
});

test('kintone cold capture uses the original member wire without a new Target or a request submission', () => {
  const f = fixture(), plan = f.prepare(f.options), extent = plan.recoveryConstruction.inputExtent;
  assert(extent('{"original":"preview"}', [{memberIndex: 0, wire: '{"requests":[]}'}], 0));
  assert(extent('{"original":"preview"}', [{memberIndex: 1, wire: 'x'.repeat(65536)}], 0));
  assert.throws(() => extent('x'.repeat(65537), [], 0), {code: 'KintoneEffectRecipeUnavailable'});
  assert.throws(() => extent('{}', [{memberIndex: 0, wire: 'x'.repeat(65537)}], 0),
    {code: 'KintoneEffectRecipeUnavailable'});
  assert.throws(() => extent('{}', [], -1), {code: 'KintoneEffectRecipeUnavailable'});
  assert.equal(f.f.calls.clientProgramKintonePrepareUpdateProposal ?? 0, 0);
  assert.equal(f.f.calls.clientProgramKintonePrepareUpdatePreview ?? 0, 0);
  assert.equal(f.f.calls.clientProgramKintoneRestoreUpdateExecution ?? 0, 0);
});

test('kintone recipe captures actual Common methods before later export-table replacement', () => {
  const f = fixture();
  for (const name of Object.keys(f.f.moon)) if (typeof f.f.moon[name] === 'function') {
    f.f.moon[name] = () => assert.fail('replaced export table');
  }
  assert.equal(f.prepare(f.options).credentialOperations.length, 13);
  assert.throws(() => f.prepare({...f.options, limits: {...policy, maxRequestBytes: 0}}),
    {code: 'KintoneEffectRecipeUnavailable'});
});
