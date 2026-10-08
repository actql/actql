import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {installedConnectors} from
  '../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable, installedConnectorForTable} from
  './installed-connectors.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';

const unused = () => { assert.fail('Provider work must remain unused'); };
const driver = {kinds: ['create'], prepareRequest: unused, requestFacts: unused,
  writeOperation: unused, send: unused, project: unused, footprint: unused};
const identityProfile = () => ({
  continuation: 'actql-installed-example-effect-continuation/0.1',
  continuationBinding: 'publication_generation_cid',
  dispatch: 'actql-installed-example-effect-dispatch/0.1',
  recovery: 'actql-installed-example-effect-recovery/0.1',
  source: 'actql-installed-example-effect-source/0.1',
  targetCheck: 'actql-installed-example-effect-check/0.1',
  unit: 'actql-installed-example-effect-unit/0.1',
});
const entry = () => ({name: 'example', registration: 'example',
  revision: 'example/0.1', effect: {
    profileVersion: 'actql-installed-example-effect/0.1',
    identityProfile: identityProfile(), load: unused}});
const selected = raw => installedConnectorForTable(
  createInstalledConnectorTable([raw]), 'effect',
  {version: raw.effect.profileVersion});

test('row Effects reject raw, frozen and copied entries even with valid identity profiles', async () => {
  const raw = entry();
  const admitted = selected(raw);
  const sourceOnly = installedConnectorForTable(createInstalledConnectorTable([
    {name: 'example', source: {
      profileVersion: 'actql-installed-example-source/0.1', load: unused}},
  ]), 'source', {version: 'actql-installed-example-source/0.1'});
  for (const installation of [raw, Object.freeze(entry()),
    Object.freeze({...admitted}), Object.create(admitted), sourceOnly]) {
    await assert.rejects(createInstalledRowEffect({driver, installation}),
      {code: 'InvalidInstalledRowEffectInstallation'});
  }
  // Admission passes this check; the remaining missing creation arguments
  // are rejected independently and cannot cause provider work.
  await assert.rejects(createInstalledRowEffect({driver, installation: admitted}),
    {code: 'InvalidInstalledRowEffect'});
});

test('admitted row Effects retain their snapshotted continuation profile semantics', async t => {
  const moon = await import(new URL('../../_build/js/release/build/' +
    'connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);
  const root = await mkdtemp(join(tmpdir(), 'actql-owned-effect-profile-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const raw = entry();
  const expected = {...raw.effect.identityProfile};
  const admitted = selected(raw);
  raw.effect.identityProfile.continuation = 'actql-installed-changed-continuation/0.1';
  raw.effect.identityProfile.continuationBinding = 'binding_cid';
  const legacy = installedConnectors.find(value => value.effect?.identityProfile);
  assert.ok(legacy, 'the generated table retains its registered profile');
  const defaultProfile = {
    continuation: 'actql-installed-row-effect-continuation/0.1',
    continuationBinding: 'binding_cid',
  };
  for (const [installation, profile] of [[admitted, expected],
    [legacy, legacy.effect.identityProfile], [undefined, defaultProfile]]) {
    const mappingCid = `sha256:${'a'.repeat(64)}`;
    const effect = await createInstalledRowEffect({moon, driver, installation,
      mappings: [{resource: 'records', mappingRef: 'mapping:example.records',
        mappingCid, body: JSON.stringify({mapping_contract_cid: mappingCid,
          target_ref: 'connector://example/records', minimum_approval: 'none'})}],
      environmentWire: '{}', connectorId: 'example',
      connectorRegistration: installation?.registration ?? 'example',
      connectorRevision: installation?.revision ?? 'example/0.1',
      connection: 'example', site: {issueEffectGrant: unused,
        issueReadGrant: unused, close() {}},
      authorization: {authorize: unused}, runtimeBundleCid: mappingCid,
      bindingCid: mappingCid, ledgerRoot: root});
    const stopped = new Error('StopAfterContinuationAdmission');
    const facts = {moon, recovered: {computation: {}}, control: {
      effectComputationPreviewWire() { throw stopped; }}};
    const continuation = {version: profile.continuation,
      [profile.continuationBinding]: 'installed-binding',
      members: [], program_id: 'program', stage_id: 'stage'};
    assert.throws(() => effect.prepareRecovered({...facts, continuation}),
      error => error === stopped);
    assert.throws(() => effect.prepareRecovered({...facts,
      continuation: {...continuation, version: 'actql-unregistered-continuation/0.1'}}),
    {code: 'InstalledEffectContinuationMismatch'});
    const wrongBinding = {...continuation,
      [profile.continuationBinding === 'binding_cid' ?
        'publication_generation_cid' : 'binding_cid']: 'installed-binding'};
    delete wrongBinding[profile.continuationBinding];
    assert.throws(() => effect.prepareRecovered({...facts,
      continuation: wrongBinding}), {code: 'InstalledEffectContinuationMismatch'});
    await effect.close();
  }
});
