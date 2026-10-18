// A whole Set keeps its original Preview while each installed Salesforce
// driver reconstructs only its own original global member positions.
import assert from 'node:assert/strict';
import {join} from 'node:path';
import test from 'node:test';
import {composeInstalledRowEffectOwners} from '../../../host-node/installed-row-effect.mjs';
import {composeInstalledCheckEnvironment} from '../../../host-node/installed-check-environment.mjs';
import {createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {accountConfiguration, effectHost, effectProgram, installedEffect,
  moon, recordEntry, salesforceMoon} from './installed-salesforce-effect.fixture.mjs';

import {recoverAdmittedEffectRun} from '../../../host-node/entry.mjs';
import {localContractLimits} from '../../../host-node/local-values-plan.mjs';
import {releaseCompletedRunPreparedPayloads} from '../../../host-common/completed-run-publication.mjs';
import {recoverCapturedSalesforceSingleRequests} from '../host/salesforce-effect-request-recovery.mjs';

const orgIds = ['00D000000000001EAA', '00D000000000002EAA'];
const write = {resource: 'Test_Record__c', kind: 'createFromResult', sources: [
  {target: 'External_Key__c', field: 'id', nullBehavior: 'reject'},
  {target: 'Name', field: 'id', nullBehavior: 'reject'},
]};
const writesOf = installation => installation.org.seen.filter(item => item.method === 'POST');

async function installations(t) {
  const accountConfigurationWire = accountConfiguration(orgIds.flatMap((id, index) =>
    ['read', 'effect'].map(operation => ({...recordEntry(id, operation),
      entry_id: `org-${index}-${operation}`}))));
  const values = [];
  for (const [index, orgId] of orgIds.entries()) {
    values.push(await installedEffect(t, {writes: [write], writeOperation: 'create',
      connectorId: `salesforce-${index}`, accountConfigurationWire,
      org: {orgId, statefulRecords: true}, siteProfile: {siteKey: `site-${index}`}}));
  }
  const gate = await createLocalAuthorizationGate({accountConfiguration: accountConfigurationWire,
    principal: 'principal-a'});
  const compose = async () => {
    const installed = [];
    for (const value of values) installed.push(await value.load({}, {ledgerRoot: values[0].ledgerRoot}));
    const descriptors = installed.map((value, index) => ({...value.mappings[0], effectId: `save_${index}`,
      kind: 'create'}));
    const environmentWire = composeInstalledCheckEnvironment(moon,
      values[0].baseEnvironmentWire, installed[0].environmentWire, installed[1].environmentWire);
    return {effect: composeInstalledRowEffectOwners(installed, descriptors, environmentWire),
      descriptors};
  };
  // This is the actual Host gate over the same original account configuration
  // admitted by both Sites, not either Site's default or a synthetic dispatch.
  const authorize = stage => ({...stage, apply: {...stage.apply,
    authorization: {gate, scopes: stage.scopes}}});
  return {values, compose, authorize};
}

test('two installed Sites resume only the unsent original member of the same Set',
  {timeout: 30_000}, async t => {
    const {values, compose, authorize} = await installations(t);
    const original = await compose();
    const state = join(values[0].root, 'composed-host');
    const first = await effectHost(t, values[0], state, {effect: original.effect,
      wrapStage(stage) {
        const authorized = authorize(stage);
        return {...authorized, apply: {...authorized.apply,
          bindDispatch(binding) {
            const send = stage.apply.bindDispatch(binding);
            let dispatched = 0;
            return row => {
              if (++dispatched === 2) throw Object.assign(new Error('StopAfterOriginalMember'),
                {code: 'StopAfterOriginalMember'});
              return send(row);
            };
          }}};
      }});
    const program = effectProgram(Object.fromEntries(original.descriptors.map(value =>
      [value.effectId, {create: {target: value.target, mapping: value.mappingRef,
        from: {result: 'rows'}}}])), [{id: 'original-row'}]);
    const stopped = await first.run(program, 'composed-original').then(() => undefined, error => error);
    assert.equal(stopped?.code, 'StopAfterOriginalMember', String(stopped?.stack));
    assert.deepEqual(values.map(value => writesOf(value).length), [1, 0]);
    const stage = first.outcomes[0].stage;
    const previewWire = first.control.effectComputationPreviewWire(stage.preview);
    const continuation = JSON.parse(stage.continuationWire);
    const runDefinitionCid = stopped.accepted.ref.runDefinitionCid;
    await first.close();
    const reopened = await compose();
    const second = await effectHost(t, values[0], state, {effect: reopened.effect,
      wrapRecoveredStage: authorize});
    const resumed = await second.resume('composed-original', runDefinitionCid, continuation);
    assert.equal(resumed.result.status, 'published');
    assert.equal(second.control.effectComputationPreviewWire(resumed.stage.preview), previewWire);
    assert.deepEqual(values.map(value => writesOf(value).length), [1, 1]);
    for (const value of values) {
      assert.equal(writesOf(value)[0].body,
        '{"External_Key__c":"original-row","Name":"original-row"}');
    }
  });

test('a foreign saved installation refuses composed recovery before either Site sends',
  {timeout: 30_000}, async t => {
    const {values, compose} = await installations(t);
    const original = await compose();
    const state = join(values[0].root, 'foreign-composed-host');
    const first = await effectHost(t, values[0], state, {effect: original.effect,
      stopBeforeApply: true});
    const program = effectProgram(Object.fromEntries(original.descriptors.map(value =>
      [value.effectId, {create: {target: value.target, mapping: value.mappingRef,
        from: {result: 'rows'}}}])), [{id: 'retained-original'}]);
    const captured = await first.run(program, 'foreign-composed');
    assert.equal(captured.started.value.status, 'captured');
    const continuation = JSON.parse(first.outcomes[0].stage.continuationWire);
    continuation.members[1].installation = {...continuation.members[0].installation};
    await first.close();
    const reopened = await compose();
    const second = await effectHost(t, values[0], state, {effect: reopened.effect});
    await assert.rejects(second.resume('foreign-composed',
      captured.accepted.ref.runDefinitionCid, continuation),
    {code: 'InstalledRowEffectInstallationChanged'});
    assert.deepEqual(values.map(value => writesOf(value).length), [0, 0]);
  });


test('absent member selection preserves the original valid recovery entry order',
  {timeout: 30_000}, async t => {
    const {values, compose} = await installations(t);
    const original = await compose();
    const state = join(values[0].root, 'ordered-recovery-host');
    const first = await effectHost(t, values[0], state, {effect: original.effect,
      stopBeforeApply: true});
    const program = effectProgram(Object.fromEntries(original.descriptors.map(value =>
      [value.effectId, {create: {target: value.target, mapping: value.mappingRef,
        from: {result: 'rows'}}}])), [{id: 'ordered-original'}]);
    const captured = await first.run(program, 'ordered-original');
    const stage = first.outcomes[0].stage;
    const recorded = {members: stage.apply.members};
    const previewWire = first.control.effectComputationPreviewWire(stage.preview);
    const body = JSON.parse(previewWire);
    await first.close();
    const reopened = await compose();
    const second = await effectHost(t, values[0], state, {effect: reopened.effect});
    const recovery = await recoverAdmittedEffectRun({requests: second.journal,
      store: second.store, key: {namespaceId: 'namespace-a', authorityScopeCid:
        `sha256:${'e'.repeat(64)}`, requestId: 'ordered-original',
      runDefinitionCid: captured.accepted.ref.runDefinitionCid}, principalId: 'principal-a',
      contractLimits: localContractLimits, authorizeEvidenceRead: async () => true});
    try {
      const options = {moon: salesforceMoon, recovered: recovery.computation, recorded,
        previewWire, runIdentityCid: body.run_identity_cid,
        authoringContextCid: body.authoring_context.authoring_context_cid,
        previewLimits: {maxWireBytes: 1_000_000, maxNodes: 100_000, maxDepth: 64},
        bodyLimits: {maxBytes: 100_000, maxNodes: 10_000, maxDepth: 16},
        requestLimits: {maxPathBytes: 2048, maxTargetBytes: 1024, maxBodyBytes: 100_000},
        maxMembers: 16, maxRows: 200, maxRetainedBytes: 16_000_000};
      assert.equal(recoverCapturedSalesforceSingleRequests(options).requests.length, 2);
      const reversed = {...recovery.computation,
        connectorRecovery: [...recovery.computation.connectorRecovery].reverse()};
      assert.deepEqual(reversed.connectorRecovery.map(entry => entry.memberIndex), [1, 0]);
      assert.throws(() => recoverCapturedSalesforceSingleRequests({...options,
        recovered: reversed}), {code: 'InvalidSalesforceCapturedRequestRecovery'});
      assert.deepEqual(values.map(value => writesOf(value).length), [0, 0]);
    } finally {
      await releaseCompletedRunPreparedPayloads(recovery.computation.storedResults, second.control);
    }
  });
