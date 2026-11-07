// Installation DATA/callee correspondence only. Physical Site, original
// selection/approval owners and a matching normal cohort are separate checks.
import assert from 'node:assert/strict';
import test from 'node:test';
import {checkInstalledHubSpotEffectProfile, installedHubSpotEffectIdentityParts,
  installedHubSpotTargetReadInventory} from '../host/installed-hubspot-effect.mjs';
import {runtimeTupleFromFields} from '../../../host-common/compiler-binding.generated.mjs';
import {installedConnectors} from '../../../connectors-builtin/installations.generated.mjs';
const ok = value => ({$tag: 1, _0: value});

const cid = 'sha256:' + 'a'.repeat(64);
const profile = () => ({version: 'actql-installed-hubspot-effect/0.1', connectorId: 'fixture', sourceProfilePath: '/source.json',
  writes: [{resource: 'companies', fields: ['amount'], markerProperty: 'actql_request_id'}]});

test('HubSpot standard table selects its own original Effect module without loading a provider or executing a case', async () => {
  const installed = installedConnectors.find(entry => entry.name === 'hubspot');
  assert.equal(installed.effect.profileVersion, 'actql-installed-hubspot-effect/0.1');
  const module = await installed.effect.load();
  assert.strictEqual(module.check, checkInstalledHubSpotEffectProfile);
  assert.strictEqual(module.identityParts, installedHubSpotEffectIdentityParts);
  assert.equal(typeof module.load, 'function');
});

test('HubSpot Effect profile captures original write and marker DATA without requesting authorization', () => {
  const input = profile(), checked = checkInstalledHubSpotEffectProfile(input);
  input.writes[0].fields[0] = 'other'; input.writes[0].markerProperty = 'foreign';
  assert.deepEqual(checked.writes[0], {resource: 'companies', fields: ['amount'], markerProperty: 'actql_request_id'});
  assert(Object.isFrozen(checked.writes[0].fields)); assert(Object.isFrozen(checked.writes));
  for (const change of [value => value.writes.push(value.writes[0]),
    value => value.writes[0].fields.push('amount'), value => value.writes[0].fields.push('actql_request_id'),
    value => value.writes[0].markerProperty = 'id', value => value.sourceProfilePath = 'relative',
    value => value.extra = true]) {
    const value = profile(); change(value);
    assert.throws(() => checkInstalledHubSpotEffectProfile(value), {code: 'InvalidInstalledHubSpotEffectProfile'});
  }
  const inputWithGetter = profile();
  Object.defineProperty(inputWithGetter.writes[0], 'fields', {enumerable: true, get() {assert.fail('no getter');}});
  assert.throws(() => checkInstalledHubSpotEffectProfile(inputWithGetter), {code: 'InvalidInstalledHubSpotEffectProfile'});
});

test('HubSpot Effect target inventory binds every installed member and rejects foreign descriptors or copied selections', () => {
  const mapping = Object.freeze({resource: 'companies', mappingRef: 'hubspot.amount', mappingCid: cid,
    fields: Object.freeze(['amount'])});
  const state = {kind: 'update', mapping: cid, calls: [], current: 0};
  const moon = {clientProgramEffectMemberDescriptor(prepared, stage, effect, work) {
    state.calls.push({prepared, stage, effect, work});
    return ok(runtimeTupleFromFields([effect === 'second' ? 1 : 0, effect, state.kind, 'target',
      mapping.mappingRef, state.mapping, 'result']));
  }};
  const prepared = Object.freeze({original: 'component'});
  const unit = Object.freeze({programId: 'program', stageId: 'commit', stageIndex: 2,
    effectIds: Object.freeze(['second', 'first'])});
  const inventory = installedHubSpotTargetReadInventory({moon, mappings: [mapping],
    connection: 'hubspot:fixture', siteBindingCid: cid, generationCid: cid, rowEffect: {}});
  const entries = inventory({moon, prepared, unit});
  assert.deepEqual(entries.map(entry => entry.physicalBinding.effect_id), ['first', 'second']);
  assert.notStrictEqual(entries[0].physicalBinding, entries[1].physicalBinding);
  assert.deepEqual(entries.map(entry => entry.readTuple), [0, 1].map(() =>
    ({connection: 'hubspot:fixture', resource: 'companies', operation: 'read'})));
  assert.deepEqual(entries[0].physicalBinding, {version: 'actql-installed-hubspot-effect-target-read/0.1',
    site_binding_cid: cid, generation_cid: cid, program_id: 'program', stage_id: 'commit', stage_index: 2,
    effect_id: 'first', member_index: 0, mapping_cid: cid, mapping_ref: mapping.mappingRef,
    resource: 'companies', effect_kind: 'update', key: 'id', fields: ['amount']});
  assert(state.calls.every(call => call.prepared === prepared && call.stage === 2 && call.work === 10000));
  assert.throws(() => inventory({moon: {}, prepared, unit}), {code: 'ForeignHubSpotEffectRuntime'});
  state.kind = 'create'; assert.throws(() => inventory({moon, prepared, unit}), {code: 'HubSpotEffectMappingNotInstalled'});
  state.kind = 'update'; state.mapping = 'sha256:' + 'b'.repeat(64);
  assert.throws(() => inventory({moon, prepared, unit}), {code: 'HubSpotEffectMappingNotInstalled'});
  state.mapping = cid;
  assert.throws(() => inventory({moon, prepared, unit, updateTargetSelections: [],
    assertUpdateSelectionCurrent() {state.current++;}}));
  assert.equal(state.current, 0);
});

test('HubSpot Effect identity reobserves the full declared Source through existing configuration readers', async () => {
  // Invalid Source refuses before identity construction or provider access.
  const calls = [];
  await assert.rejects(installedHubSpotEffectIdentityParts(profile(), undefined, undefined,
    {configurationReader: {async readJson(path) {calls.push(path); return {version: 'foreign', connectorId: 'fixture'};},
      readText() {assert.fail('no text read');}}}),
  {code: 'InvalidInstalledHubSpotSourceProfile'});
  assert.deepEqual(calls, ['/source.json']);
});
