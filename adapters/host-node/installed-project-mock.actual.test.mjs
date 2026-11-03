import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdir, mkdtemp, open, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {loadInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {selectInstalledProjectProfile} from './installed-project-profile.mjs';
import {prepareInstalledProjectMock} from '../local-node/installed-project-mock.mjs';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';

assert.ok(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME, 'Select the matching actual Common runtime');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));

// Real Common and metadata-file reader; the current callback is an explicit
// operational fixture, not the selected Source issuer or a physical grant.
async function fixture({connections, data = './original/data.json'} = {}) {
  await mkdir('_build', {recursive: true});
  const directory = await mkdtemp(join(process.cwd(), '_build/mock-profile-originals-'));
  await writeFile(join(directory, 'actql.config.json'), JSON.stringify({version: 'actql-config/0.1',
    connectors: './connections.json', profile: 'mock', mock: {catalog: './catalog.json', data, answers: {}}}));
  const connectionWire = JSON.stringify({version: 'actql-connectors/0.1', connections: connections ?? {
    salesforce: {connector: 'salesforce', credentials: {token: {env: 'NEVER_READ_MOCK_SECRET'}}},
    snowflake: {connector: 'snowflake'},
  }});
  const path = join(directory, 'connections.json');
  await writeFile(path, connectionWire);
  const catalogPath = join(directory, 'catalog.json');
  await writeFile(catalogPath, projectTemplateFiles('churn-risk-mock')['mock/catalog.json']);
  const project = await loadInstalledProjectConfiguration(moon, {directory});
  const profile = selectInstalledProjectProfile(moon, project, 'mock', 65536);
  return {directory, path, catalogPath, project, profile, connectionWire};
}

test('actual Mock preparation retains original Project/Profile/connections and both explicit Common declarations', async () => {
  const f = await fixture();
  const opened = [];
  let checks = 0;
  const view = await prepareInstalledProjectMock(moon, f.project, f.profile, {
    assertCurrent() {checks++;}, async openFile(path, flags) {
      assert.ok([f.path, f.catalogPath].includes(path)); opened.push(path); return open(path, flags);
    },
  });
  const value = view.originalsForRuntime(moon);
  assert.equal(value.project, f.project.originalsForRuntime(moon));
  assert.equal(value.configuration, value.project.configuration);
  assert.equal(value.selection, f.profile.originalsForRuntime(moon).selection);
  assert.equal(value.connections.project, value.project);
  assert.equal(value.connections.wire, f.connectionWire);
  assert.equal(value.dataFile, './original/data.json');
  assert.equal(value.dataPath, join(f.directory, 'original/data.json'));
  assert.equal(value.sources.length, 2);
  assert.deepEqual(value.sources.map(source => source.catalogue.connection), ['salesforce', 'snowflake']);
  for (const source of value.sources) {
    assert.equal(moon.clientProgramRowSourceDeclarationJson(source.declaration), source.wire);
    const declared = JSON.parse(source.wire);
    assert.equal(declared.connector_id, source.catalogue.connectorId);
    assert.equal(declared.views[0].resource, source.catalogue.views[0].resource);
  }
  assert.equal(typeof value.mappingWire, 'string');
  assert.equal(JSON.parse(value.mappingWire).target_ref, 'connector://salesforce/Account');
  assert.equal(view.originalsForRuntime(moon), value);
  assert.ok(checks > 3);
  assert.deepEqual(opened, [f.path, f.catalogPath], 'No data, answer, credential or provider acquisition');
  assert.equal(value.physicalKind, 'declared-json-document');
  assert.equal(value.writable.source, value.sources[0]);
  view.retire(moon);
});

test('actual Mock preparation refuses foreign original Profile before connection acquisition', async () => {
  const a = await fixture(), b = await fixture();
  let opened = 0;
  await assert.rejects(prepareInstalledProjectMock(moon, a.project, b.profile, {
    assertCurrent() {}, openFile() {opened++; assert.fail('No foreign metadata read');},
  }), {code: 'ForeignInstalledMockPreparation'});
  assert.equal(opened, 0);
});

test('actual Mock preparation does not infer a catalogue from the file name or another connector', async () => {
  for (const connections of [{salesforce: {connector: 'salesforce'}},
    {other: {connector: 'salesforce'}, snowflake: {connector: 'snowflake'}}]) {
    const f = await fixture({connections});
    await assert.rejects(prepareInstalledProjectMock(moon, f.project, f.profile,
      {assertCurrent() {}}), error => ['InstalledMockCatalogueUnavailable',
      'InvalidInstalledMockCatalog'].includes(error.code));
  }
});

test('actual Mock preparation preserves after-await current refusal and closes only its metadata FD', async () => {
  const f = await fixture();
  let current = true, opens = 0, closes = 0;
  const failure = Object.freeze(new Error('OriginalSourceGenerationChanged'));
  await assert.rejects(prepareInstalledProjectMock(moon, f.project, f.profile, {
    assertCurrent() {if (!current) throw failure;},
    async openFile(path, flags) {
      assert.equal(path, f.path); opens++;
      const handle = await open(path, flags);
      return {read: (...args) => handle.read(...args), async close() {
        closes++; await handle.close(); current = false;
      }};
    },
  }), error => error === failure);
  assert.equal(opens, 1); assert.equal(closes, 1);
});

test('actual Mock preparation keeps same-view/runtime retirement separate from Source cleanup', async () => {
  const f = await fixture();
  const view = await prepareInstalledProjectMock(moon, f.project, f.profile, {assertCurrent() {}});
  assert.throws(() => view.originalsForRuntime({...moon}), {code: 'ForeignInstalledMockPreparation'});
  assert.throws(() => ({...view}).originalsForRuntime(moon), {code: 'ForeignInstalledMockPreparation'});
  assert.throws(() => ({...view}).retire(moon), {code: 'ForeignInstalledMockPreparation'});
  assert.equal(view.originalsForRuntime(moon).sources.length, 2);
  view.retire(moon); view.retire(moon);
  assert.throws(() => view.originalsForRuntime(moon), {code: 'InstalledMockPreparationRetired'});
  // Retiring this private DATA view does not retire its original parent.
  assert.ok(f.project.originalsForRuntime(moon).configuration);
  assert.equal(f.profile.originalsForRuntime(moon).selected, 'mock');
});

// Connection labels are arbitrary declarations, not a provider-selection
// oracle. SourceRef uses the connection identity, not the provider identity.
test('actual Mock preparation keeps same-provider connection identities distinct', async () => {
  const f = await fixture({connections: {salesforce: {connector: 'snowflake'}, snowflake: {connector: 'snowflake'}}});
  const prepared = await prepareInstalledProjectMock(moon, f.project, f.profile, {assertCurrent() {}});
  const bundle = prepared.originalsForRuntime(moon);
  assert.equal(bundle.writable.source.catalogue.connectorId, 'salesforce');
  assert.equal(bundle.writable.source.catalogue.provider, 'snowflake');
  assert.deepEqual(bundle.sources.map(source => source.catalogue.connectorId), ['salesforce', 'snowflake']);
  assert.equal(JSON.parse(bundle.mappingWire).target_ref, 'connector://salesforce/Account');
  prepared.retire(moon);
});
