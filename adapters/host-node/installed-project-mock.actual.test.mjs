import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdir, mkdtemp, open, readFile, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {createAccountConstruction} from './account-construction.mjs';
import {prepareOrdinaryMockAccountSubjects} from './ordinary-mock-account.mjs';
import {createInstalledHostServices, installedAccountConstruction,
  closeInstalledAccountConstruction, retireInstalledSourceInitialization} from './installed-host-services.mjs';
import {createDeclaredFileInstallationInventory} from '../local-node/declared-file-installation.mjs';
import {multipleTargetMockProjectFiles} from './fixtures/mock-multiple-targets.fixture.mjs';
import {loadInstalledProjectConfiguration} from './installed-project-configuration.mjs';
import {selectInstalledProjectProfile} from './installed-project-profile.mjs';
import {inspectProjectMockDeclarations, prepareInstalledProjectMock,
  installPreparedProjectMockSources} from '../local-node/installed-project-mock.mjs';
import {installPreparedProjectMockEffects} from '../local-node/installed-mock-row-effect.mjs';
import {createMockFileRowCodec, mockFileRowFootprint, mockFileEffectPlanRecipe}
  from '../local-node/installed-mock-row-effect.mjs';
import {createMockFileTarget} from './mock-file-target.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {projectTemplateFiles} from '../../packages/native-cli/lib/project-template.mjs';

assert.ok(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME, 'Select the matching actual Common runtime');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));

async function withMockCatalog(action) {
  const runtimeUrl = pathToFileURL(realpathSync(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));
  const {openHostInitializationPreparation, closeHostInitializationPreparation} = await import(new URL(
    '../../../../../adapters/local-node/request-preparation-adapter.mjs', runtimeUrl));
  await mkdir('_build', {recursive: true});
  const directory = await mkdtemp(join(process.cwd(), '_build/mock-footprint-originals-'));
  const files = multipleTargetMockProjectFiles();
  for (const [name, wire] of Object.entries(files)) {
    await mkdir(dirname(join(directory, name)), {recursive: true});
    await writeFile(join(directory, name), wire);
  }
  const project = await loadInstalledProjectConfiguration(moon, {directory});
  const profile = selectInstalledProjectProfile(moon, project, 'mock', 65536);
  const state = {}, input = Object.freeze({directory, purpose: 'Mock footprint and locked codec component'});
  let current = true, inventory, preparation;
  const assertCurrent = () => {assert.equal(current, true);};
  const parent = openHostInitializationPreparation(state, moon, input, assertCurrent, () => false);
  const services = createInstalledHostServices({root: directory, principalId: 'operator', moon,
    initialPreparation: parent, assertCurrent, accountCurrent: assertCurrent});
  try {
    inventory = createDeclaredFileInstallationInventory({moon, project, services, runtimeUrl, assertCurrent,
      baseEnvironmentWire: (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd()});
    preparation = await prepareInstalledProjectMock(moon, project, profile,
      {installationInventory: inventory, assertCurrent});
    return await action({directory, files, bundle: preparation.originalsForRuntime(moon), assertCurrent});
  } finally {
    assert.equal(await closeInstalledAccountConstruction(services), true);
    await inventory?.fail(new Error('MockFootprintComponentFinished'));
    assert.equal(retireInstalledSourceInitialization(services), true);
    preparation?.retire(moon);
    closeHostInitializationPreparation(state);
    current = false;
  }
}

test('plural Mock exact footprints retain one boundary and reject same-row aliases and duplicates', async () => {
  await withMockCatalog(async ({bundle}) => {
    const bindingCid = 'sha256:' + 'a'.repeat(64);
    const [account, contact] = bundle.writables;
    const make = (target, selectors = ['same']) => mockFileRowFootprint({bindingCid, target, selectors});
    const first = make(account), second = make(contact);
    const digest = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
    assert.equal(first.resource_identity_scheme_cid, digest(
      '{"identity_fields":["items_path","key_path","primary_identity","identity"],"kind":"mock-file-row-update"}'));
    assert.equal(first.provider_object_identity_cids[0], digest(
      '{"identity":"same","items_path":["salesforce","Account","rows"],"key_path":["salesforce","Account","key"],"primary_identity":"id"}'));
    assert.equal(first.provider_boundary_cid, second.provider_boundary_cid);
    assert.equal(first.resource_identity_scheme_cid, second.resource_identity_scheme_cid);
    assert.notEqual(first.provider_object_identity_cids[0], second.provider_object_identity_cids[0]);
    const check = values => runtimeCore(moon).effectApplicationControl.checkSetFootprintConflicts(
      values.map((_, index) => 'effect-' + index),
      values.map(value => value.kind === 'exact_targets' ? 0 : value.kind === 'collection' ? 1 : 2),
      values.map(value => value.provider_namespace), values.map(value => value.provider_boundary_cid),
      values.map(value => value.resource_identity_scheme_cid), values.map(value => value.resource_kind),
      values.map(value => [...value.provider_object_identity_cids]), 16, 100, 10000);
    assert.equal(check([first, second]), true);
    const alias = make({...account, write: {...account.write, resource: 'Alias'}});
    assert.equal(alias.provider_object_identity_cids[0], first.provider_object_identity_cids[0]);
    assert.throws(() => check([first, alias]), {code: 'MoonBitHostFailure'});
    assert.throws(() => check([make(account, ['same', 'same'])]), {code: 'MoonBitHostFailure'});
    assert.throws(() => check([{...first, kind: 'opaque', provider_object_identity_cids: []}, first]),
      {code: 'MoonBitHostFailure'});
  });
});

test('plural Mock actual codec merges latest locked document and refuses changed original row versions', async () => {
  await withMockCatalog(async ({directory, files, bundle, assertCurrent}) => {
    const original = bundle.sources[0], [account, contact] = bundle.writables;
    const methods = {admit: 'clientProgramRelationAdmitDocument', project: 'clientProgramRelationProjectTargetDocument',
      observe: 'clientProgramRelationObserveTarget', before: 'clientProgramRelationTargetBefore',
      version: 'clientProgramRelationTargetVersion', update: 'clientProgramRelationPrepareTargetUpdate'};
    const codec = createMockFileRowCodec({bundle, original,
      call: (name, ...args) => Reflect.apply(moon[methods[name]], moon, args)});
    const path = join(directory, 'mock/data.json'), bytes = await readFile(path);
    const record = (target, identity, value) => {
      const observed = codec.observe(codec.admit(bytes, target), identity);
      return {target: identity, value: {value}, version: observed.versionCid, before: observed.before};
    };
    const first = record(account, 'a1', 'A-new'), second = record(contact, 'c1', 'C-new');
    const runOriginal = Object.freeze({purpose: 'standalone physical codec component'});
    const file = createMockFileTarget({dataPath: path, maxBytes: 1048576, assertCurrent});
    const children = [];
    try {
      for (const [target, request] of [[account, first], [contact, second]]) {
        const charges = [];
        const child = file.updateChild({runOriginal, authorize() {},
          replace(latest) {
            const replacement = codec.update(latest, target, request, {chargeBytes(value) {charges.push(value);}});
            assert.deepEqual(charges, [BigInt(latest.length), BigInt(replacement.length)]);
            return replacement;
          }});
        children.push(child);
        await child.prepare();
        assert.equal((await child.release()).pending, false);
      }
      const expected = files['mock/data.json'].replace('A-old', 'A-new').replace('C-old', 'C-new');
      assert.equal(await readFile(path, 'utf8'), expected, 'both control records and all unrelated bytes remain exact');
      const stale = file.updateChild({runOriginal, authorize() {},
        replace(latest) {return codec.update(latest, account, first);}});
      children.push(stale);
      await assert.rejects(stale.prepare(), {code: 'MockTargetVersionConflict'});
      assert.equal(await readFile(path, 'utf8'), expected);
      assert.equal((await stale.release()).pending, false);
      const observed = codec.observe(codec.admit(await readFile(path), contact), 'c1');
      const fresh = {target: 'c1', value: {value: 'C-third'}, version: observed.versionCid, before: observed.before};
      const external = expected.replace('C-new', 'C-foreign');
      await writeFile(path, external);
      const changed = file.updateChild({runOriginal, authorize() {},
        replace(latest) {return codec.update(latest, contact, fresh);}});
      children.push(changed);
      await assert.rejects(changed.prepare(), {code: 'MockTargetVersionConflict'});
      assert.equal(await readFile(path, 'utf8'), external, 'external target change is not overwritten');
      assert.equal((await changed.release()).pending, false);
    } finally {
      for (const child of children) await child.release();
      assert.equal((await file.closeFor(runOriginal)).pending, false);
      assert.equal((await file.close()).pending, false);
    }
  });
});

test('plural Mock actual recipe adds only the same nonphysical footprint operation and preserves single-target slots', async () => {
  await withMockCatalog(async ({bundle}) => {
    const single = mockFileEffectPlanRecipe(moon, {...bundle, writables: bundle.writables.slice(0, 1)},
      'file.update', 'file.observe');
    const plural = mockFileEffectPlanRecipe(moon, bundle, 'file.update', 'file.observe');
    assert.equal(single.footprintConstruction, undefined);
    assert.equal(single.memberOperations.length, 2);
    assert.deepEqual(plural.footprintConstruction, {operationIndex: 2});
    assert.equal(plural.memberOperations.length, 3);
    assert.deepEqual(plural.memberOperations.slice(0, 2).map(value => value.operation),
      single.memberOperations.map(value => value.operation));
    assert.deepEqual(plural.rowOperations.map(value => value.operation), single.rowOperations.map(value => value.operation));
    assert.deepEqual(plural.ownedReadOperations, single.ownedReadOperations);
    assert.deepEqual(plural.physicalWrite, single.physicalWrite);
    assert.deepEqual(plural.captureConstruction, single.captureConstruction);
    assert.deepEqual(plural.recoveryConstruction.operationIndex, single.recoveryConstruction.operationIndex);
    const extent = plural.memberOperations[2].extent;
    assert.equal(moon.clientProgramInstalledEffectOperationExtentPhysical(extent), false);
    assert.equal(moon.clientProgramInstalledEffectOperationExtentTransfer(extent), 0n);
    assert.equal(plural.memberOperations[2].operation, 'file.update.footprint');
  });
});

test('actual Mock Source mappings retain exact resources through the same Account subject handoff', async () => {
  const runtimeUrl = pathToFileURL(realpathSync(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));
  const {openHostInitializationPreparation, closeHostInitializationPreparation} = await import(new URL(
    '../../../../../adapters/local-node/request-preparation-adapter.mjs', runtimeUrl));
  await mkdir('_build', {recursive: true});
  const directory = await mkdtemp(join(process.cwd(), '_build/mock-source-account-'));
  const files = multipleTargetMockProjectFiles();
  for (const [name, wire] of Object.entries(files)) {
    await mkdir(dirname(join(directory, name)), {recursive: true});
    await writeFile(join(directory, name), wire);
  }
  const project = await loadInstalledProjectConfiguration(moon, {directory});
  const profile = selectInstalledProjectProfile(moon, project, 'mock', 65536);
  const state = {}, input = Object.freeze({directory, purpose: 'Mock Source to Account component'});
  let current = true, inventory, preparation, frame;
  const assertCurrent = () => {assert.equal(current, true);};
  const parent = openHostInitializationPreparation(state, moon, input, assertCurrent, () => false);
  const services = createInstalledHostServices({root: directory, principalId: 'operator', moon,
    initialPreparation: parent, assertCurrent, accountCurrent: assertCurrent});
  try {
    inventory = createDeclaredFileInstallationInventory({moon, project, services, runtimeUrl, assertCurrent,
      baseEnvironmentWire: (await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd()});
    preparation = await prepareInstalledProjectMock(moon, project, profile,
      {installationInventory: inventory, assertCurrent});
    const bundle = preparation.originalsForRuntime(moon);
    frame = installedAccountConstruction(services).begin();
    // Consume the actual Source-context output, never a hand-built Mapping
    // descriptor. The exact Account lookup must not fall back to its position.
    const result = prepareOrdinaryMockAccountSubjects(frame, bundle, [], directory,
      project.originalsForRuntime(moon).configurationWire, 'original-request');
    assert.deepEqual(result.updateTargets, [['salesforce', 'Account'], ['salesforce', 'Contact']]);
    assert.deepEqual(result.subject.targets.map(({connection, resource, itemsPath, keyPath, primaryIdentity}) =>
      ({connection, resource, itemsPath, keyPath, primaryIdentity})), ['Account', 'Contact'].map(resource => ({
      connection: 'salesforce', resource, itemsPath: ['salesforce', resource, 'rows'],
      keyPath: ['salesforce', resource, 'key'], primaryIdentity: 'id'})));
    for (const target of result.subject.targets) {
      const mapping = bundle.sources[0].effectPrepared.mappings.find(value => value.resource === target.resource);
      assert.equal(target.mappingCid, mapping.mappingCid);
      assert.equal(mapping.target, 'connector://salesforce/' + target.resource);
      assert.equal(Object.isFrozen(mapping), true);
    }
    assert.notEqual(result.subject.targets[0].mappingCid, result.subject.targets[1].mappingCid);
    frame.hold();
  } finally {
    frame?.finish(true);
    assert.equal(await closeInstalledAccountConstruction(services), true);
    // No adapter or physical data reader was installed. Retire the actual
    // unfinished Source constructors through their existing failure cleanup.
    await inventory?.fail(new Error('MockSourceAccountComponentFinished'));
    assert.equal(retireInstalledSourceInitialization(services), true);
    preparation?.retire(moon);
    closeHostInitializationPreparation(state);
    current = false;
  }
});

test('Mock subject construction hashes borrowed wires on the same real Account Read for one and two targets', async () => {
  const {openHostInitializationPreparation, closeHostInitializationPreparation} = await import(new URL(
    '../../../../../adapters/local-node/request-preparation-adapter.mjs',
    pathToFileURL(realpathSync(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME))));
  const digest = value => 'sha256:' + createHash('sha256').update(value, 'utf8').digest('hex');
  // This is borrowed metadata DATA, not a declaration/Account admission or an
  // ordinary installation. The actual Core parent and Account child are real.
  const configurationWire = JSON.stringify({original: '日本語'.repeat(12000)});
  const wire = JSON.stringify({original: 'declaration'.repeat(12000)});
  for (const count of [1, 2]) {
    const state = {}, input = Object.freeze({purpose: 'Mock subject Read component'});
    let current = true;
    const parent = openHostInitializationPreparation(state, moon, input,
      () => assert.equal(current, true), () => false);
    const construction = createAccountConstruction({moon, current() {assert.equal(current, true);},
      prepareRead: () => moon.clientProgramPrepareHostAccountRead(parent)});
    const source = {wire, catalogue: {connection: 'mock', registration: 'fixture',
      views: [{resource: 'first'}, {resource: 'second'}]}, effectPrepared: {mappings: [
        {resource: 'first', mappingCid: 'sha256:' + '1'.repeat(64)},
        {resource: 'second', mappingCid: 'sha256:' + '2'.repeat(64)}]}};
    const bundle = {sources: [source], writables: ['first', 'second'].slice(0, count).map(resource => ({
      source, write: {resource}, physical: {itemsPath: [resource], keyPath: ['id'], primaryIdentity: 'id'}}))};
    const frame = construction.begin();
    let result = prepareOrdinaryMockAccountSubjects(frame, bundle, [], '/original/project',
      configurationWire, 'original-request');
    const expected = {projectDirectory: '/original/project', configurationCid: digest(configurationWire),
      sources: [{connection: 'mock', registration: 'fixture', declarationCid: digest(wire)}],
      modelTasks: [], requestRealization: 'original-request'};
    if (count === 2) expected.targets = [
      {connection: 'mock', resource: 'first', mappingCid: 'sha256:' + '1'.repeat(64),
        itemsPath: ['first'], keyPath: ['id'], primaryIdentity: 'id'},
      {connection: 'mock', resource: 'second', mappingCid: 'sha256:' + '2'.repeat(64),
        itemsPath: ['second'], keyPath: ['id'], primaryIdentity: 'id'}];
    assert.deepEqual(result.subject, expected);
    assert.deepEqual(result.updateTargets, ['first', 'second'].slice(0, count).map(value => ['mock', value]));
    frame.hold();frame.finish(true);
    assert.throws(() => closeHostInitializationPreparation(state), {code: 'MoonBitHostFailure'},
      'retained subject child cannot be replaced with a parent cleanup acknowledgement');
    result = undefined;
    assert.equal(await construction.close(), true);
    closeHostInitializationPreparation(state);current = false;
  }
});

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
  const view = await inspectProjectMockDeclarations(moon, f.project, f.profile, {
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
  await assert.rejects(inspectProjectMockDeclarations(moon, a.project, b.profile, {
    assertCurrent() {}, openFile() {opened++; assert.fail('No foreign metadata read');},
  }), {code: 'ForeignInstalledMockPreparation'});
  assert.equal(opened, 0);
});

test('actual Mock preparation does not infer a catalogue from the file name or another connector', async () => {
  for (const connections of [{salesforce: {connector: 'salesforce'}},
    {other: {connector: 'salesforce'}, snowflake: {connector: 'snowflake'}}]) {
    const f = await fixture({connections});
    await assert.rejects(inspectProjectMockDeclarations(moon, f.project, f.profile,
      {assertCurrent() {}}), error => ['InstalledMockCatalogueUnavailable',
      'InvalidInstalledMockCatalog'].includes(error.code));
  }
});

test('actual Mock preparation preserves after-await current refusal and closes only its metadata FD', async () => {
  const f = await fixture();
  let current = true, opens = 0, closes = 0;
  const failure = Object.freeze(new Error('OriginalSourceGenerationChanged'));
  await assert.rejects(inspectProjectMockDeclarations(moon, f.project, f.profile, {
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
  const view = await inspectProjectMockDeclarations(moon, f.project, f.profile, {assertCurrent() {}});
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
  const prepared = await inspectProjectMockDeclarations(moon, f.project, f.profile, {assertCurrent() {}});
  const bundle = prepared.originalsForRuntime(moon);
  assert.equal(bundle.writable.source.catalogue.connectorId, 'salesforce');
  assert.equal(bundle.writable.source.catalogue.provider, 'snowflake');
  assert.deepEqual(bundle.sources.map(source => source.catalogue.connectorId), ['salesforce', 'snowflake']);
  assert.equal(JSON.parse(bundle.mappingWire).target_ref, 'connector://salesforce/Account');
  prepared.retire(moon);
});


test('installed Mock preparation never falls back to unfunded declaration inspection', async () => {
  const f = await fixture();let reads = 0;
  for (const installationInventory of [undefined, {}, Object.freeze({})]) {
    await assert.rejects(prepareInstalledProjectMock(moon, f.project, f.profile,
      {installationInventory, assertCurrent() {}, openFile() {reads++;assert.fail('No read');}}),
      {code: 'ForeignDeclaredFileInstallation'});
  }
  assert.equal(reads, 0);
});

test('metadata-only Mock inspection cannot enter Source or Effect factories', async () => {
  const f = await fixture();
  const inspected = await inspectProjectMockDeclarations(moon, f.project, f.profile, {assertCurrent() {}});
  let calls = 0;const forbidden = () => {calls++;assert.fail('No authorization or physical callback');};
  await assert.rejects(installPreparedProjectMockSources({moon, mockPreparation: inspected,
    sourceManaged: {assertCurrent() {}, prepareRead: forbidden}, authorizationFor: forbidden,
    readAsset: forbidden, prepareManagedSourceRun: forbidden}), {code: 'DeclaredFileInstallationUnavailable'});
  await assert.rejects(installPreparedProjectMockEffects({moon, mockPreparation: inspected,
    authorizationFor: forbidden, assertCurrent() {}, principalId: 'diagnostic',
    runtimeBundleCid: 'sha256:' + '0'.repeat(64), bindingCid: 'sha256:' + '0'.repeat(64),
    effectResources: {bindRunOriginal: forbidden, assertCurrent: forbidden, limits: forbidden}}),
    // The funded writable-runtime boundary now refuses this metadata-only
    // view before a file owner, authorization callback or Effect factory exists.
    {code: 'InstalledMockImplementationConstructionUnavailable'});
  assert.equal(calls, 0);inspected.retire(moon);
});


test('installed and diagnostic Mock entrypoints never evaluate changing inventory getters', async () => {
  const f = await fixture();let gets = 0, reads = 0;
  for (const prepare of [prepareInstalledProjectMock, inspectProjectMockDeclarations]) {
    const options = {assertCurrent() {}, openFile() {reads++;assert.fail('No read');},
      get installationInventory() {gets++;return gets % 2 ? undefined : {};}};
    await assert.rejects(prepare(moon, f.project, f.profile, options), {code: 'ForeignDeclaredFileInstallation'});
  }
  assert.equal(gets, 0);assert.equal(reads, 0);
});
