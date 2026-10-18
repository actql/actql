// A whole Set keeps its original Preview while each installed Salesforce
// driver reconstructs only its own original global member positions.
import assert from 'node:assert/strict';
import {join} from 'node:path';
import test from 'node:test';
import {composeInstalledRowEffectOwners} from '../../../host-node/installed-row-effect.mjs';
import {composeInstalledCheckEnvironment} from '../../../host-node/installed-check-environment.mjs';
import {createLocalAuthorizationGate} from '../../../host-node/local-account-config.mjs';
import {accountConfiguration, effectHost, effectProgram, installedEffect,
  moon, recordEntry} from './installed-salesforce-effect.fixture.mjs';

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
