import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {contentCid} from './local-account-config.mjs';
import {createInstalledLoaderParent} from './fixtures/installed-loader-parent.fixture.mjs';
import {installedSourceIdentity, publishInstalledSourceProfile,
  loadInstalledSource, loadInstalledSources, installedSourcePublicationFacts} from './installed-source.mjs';
import {installedEffectIdentity, publishInstalledEffectProfile,
  loadInstalledEffect, loadInstalledEffects} from './installed-effect.mjs';

const runtimeUrl = new URL('../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const moon = await import(runtimeUrl.href);
const baseEnvironmentWire = (await readFile(new URL(
  '../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const runtimeBundleCid = 'sha256:' + createHash('sha256')
  .update(await readFile(runtimeUrl)).digest('hex');
const versions = {source: 'actql-installed-table-fixture-source/0.1',
  effect: 'actql-installed-table-fixture-effect/0.1'};
const operations = {
  source: {identity: installedSourceIdentity, publish: publishInstalledSourceProfile,
    load: loadInstalledSource, plural: loadInstalledSources},
  effect: {identity: installedEffectIdentity, publish: publishInstalledEffectProfile,
    load: loadInstalledEffect, plural: loadInstalledEffects},
};
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' +
      canonical(value[key])).join(',') + '}'
    : JSON.stringify(typeof value === 'string' ? value.normalize('NFC') : value);
function identity(parts) {
  const hash = createHash('sha256');
  for (const part of parts) {
    const wire = canonical(part);
    hash.update(String(Buffer.byteLength(wire)) + '\0' + wire);
  }
  return 'sha256:' + hash.digest('hex');
}

async function installation(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-connector-table-loading-'));
  const parent = createInstalledLoaderParent({root, principalId: 'table-fixture', moon});
  parent.open();
  t.after(async () => {await parent.close(); await rm(root, {recursive: true, force: true});});
  let sequence = 0;
  const path = async value => {
    const target = join(root, `profile-${sequence++}.json`);
    await writeFile(target, JSON.stringify(value));
    return target;
  };
  const unexpected = () => { throw new Error('UnexpectedProviderOrCredentialOperation'); };
  return {path, options: {root, principalId: 'table-fixture', moon, runtimeUrl,
    baseEnvironmentWire, installationServices: parent.services, resolveSecret: unexpected}};
}

// Trusted application code authors ordinary installation descriptors. The
// real row owners supply lifecycle and plural inventory metadata; no resolver
// replacement or production dependency-injection hook participates here.
function connector(registration, {providerBundle, providerMoon, profileVersions = versions} = {}) {
  const revision = `${registration}/0.1`;
  const events = [], entries = [], owners = new Map(), authoredProfiles = new WeakMap();
  const closeFailure = new Error('FixtureClosePending');
  const touch = () => { throw new Error('UnexpectedProviderOperation'); };
  const descriptor = role => ({profileVersion: profileVersions[role], load: async () => {
    events.push([role, 'select']);
    return {
      check(profile) {
        assert.equal(profile.version, profileVersions[role]);
        events.push([role, 'check', profile.name]);
        const checked = Object.freeze({...profile, connectorId: profile.name});
        authoredProfiles.set(checked, profile);
        return checked;
      },
      identityParts(profile, providerProfile, read) {
        events.push([role, 'identity', profile.name]);
        if (role === 'source') {
          assert.equal(providerProfile.queryAliases, undefined);
          assert.equal(typeof read, 'function');
        } else assert.equal(typeof providerProfile, 'function');
        return [authoredProfiles.get(profile) ?? profile, {registration, revision, role}];
      },
      publish(profile, options) {
        select(options);
        events.push([role, 'publish', profile.name]);
        return {registration, revision, role, name: profile.name};
      },
      async load(profile, options) {
        select(options);
        events.push([role, 'load', profile.name]);
        const owner = {blocked: profile.failClose === true, attempts: 0, completed: 0};
        const site = {connection: `${registration}:${profile.name}`,
          issueReadGrant: touch, issueEffectGrant: touch, close() {
            owner.attempts++;
            if (owner.blocked) throw closeFailure;
            owner.completed++;
          }};
        owners.set(`${role}:${profile.name}`, owner);
        const authorization = {authorize: touch, accountConfiguration: '{}',
          context: {contextCid: 'fixture-context'}};
        const construction = options.construction;
        assert.equal(typeof construction?.prepareAuthoredDeclaration, 'function');
        assert.equal(typeof construction.openSpecializedSite, 'function');
        const fields = role === 'source'
          ? [{name: 'id', type: 'number', nullable: false}]
          : [{name: 'Id', type: 'string', nullable: false}, {name: 'Name', type: 'string', nullable: true}];
        construction.prepareAuthoredDeclaration(JSON.stringify({views: [
          {resource: 'records', resource_kind: 'record', fields}]}));
        if (role === 'effect') {
          construction.prepareMappings(JSON.stringify({writes: [{resource: 'records',
            resource_kind: 'record', primary_identity: 'Id', fields,
            create: {fields: ['Name'], required: [], permission: 'scope:create', approval: 'required'}}]}),
          Object.freeze([Object.freeze({resource: 'records', sources: Object.freeze([
            Object.freeze({target: 'Name', field: 'name', null_behavior: 'reject'})])})]));
        }
        await construction.openSpecializedSite({
          authorizationConstructor: () => authorization,
          siteConstructor: () => site,
        });
        const common = {bindingCid: contentCid({registration, name: profile.name}), connection: site.connection};
        const adapter = role === 'source'
          ? await construction.createRowSource({...common,
            readOperation: 'read', physicalTarget: touch, readPages: touch,
            limits: {maxPages: 1, maxPageBytes: 1024, maxPageRows: 10, maxCaptureRows: 10}})
          : await construction.createRowEffect({...common,
            installation: options.installation, runtimeBundleCid: options.runtimeBundleCid, ledgerRoot: options.ledgerRoot,
            driver: {kinds: ['create'], prepareRequest: touch, requestFacts: touch,
              writeOperation: touch, send: touch, project: touch, footprint: touch}});
        owner.adapter = adapter;
        return profile.defect === undefined ? adapter : {...adapter,
          [profile.defect === 'registration' ? 'connectorRegistration' : 'connectorRevision']:
            'foreign/0.1'};
      },
    };
    function select(options) {
      entries.push(options.installation);
      assert.ok(Object.isFrozen(options.installation));
      assert.equal(options.installation.registration, registration);
      assert.equal(options.installation.revision, revision);
      assert.equal(options.providerMoon, providerMoon);
      assert.equal(options.runtimeBundleCid, runtimeBundleCid);
    }
  }});
  return {entry: {name: registration, registration, revision, providerBundle,
    source: descriptor('source'), effect: descriptor('effect')},
  events, entries, owners, closeFailure};
}

for (const role of ['source', 'effect']) {
  test(`explicit tables select the exact ${role} implementation in every phase`, async t => {
    const fixture = await installation(t);
    const first = connector('first', {providerBundle: 'connectors/github/host_node',
      providerMoon: await import('../../_build/js/release/build/connectors/github/host_node/host_node.js')});
    const second = connector('second', {providerBundle: 'connectors/salesforce/host_node',
      providerMoon: await import('../../_build/js/release/build/connectors/salesforce/host_node/host_node.js')});
    const profile = {version: versions[role], name: 'shared'};
    const path = await fixture.path(profile);
    const identities = [];
    for (const selected of [first, second]) {
      const connectorTable = createInstalledConnectorTable([selected.entry, {
        name: 'unselected', providerBundle: 'connectors/absent/host_node',
        [role]: {profileVersion: 'actql-installed-unselected/0.1',
          load: () => { throw new Error('UnselectedModuleLoaded'); }},
      }]);
      const options = {...fixture.options, connectorTable};
      const observed = await operations[role].identity(path, options);
      identities.push(observed);
      assert.equal(observed, identity([profile, {registration: selected.entry.registration,
        revision: selected.entry.revision, role}]));
      assert.deepEqual(await operations[role].publish(path, options), {
        registration: selected.entry.registration, revision: selected.entry.revision,
        role, name: profile.name});
      const adapter = await operations[role].load(path, options);
      await adapter.close();
      assert.equal(selected.entries.length, 2);
      assert.equal(selected.entries[0], selected.entries[1]);
      assert.equal(selected.owners.get(`${role}:shared`).completed, 1);
      if (role === 'source') {
        // Loading binds metadata before installation and verifies the same
        // generation afterward; neither read may acquire provider authority.
        assert.deepEqual(installedSourcePublicationFacts(adapter), {
          path, revision: observed, aliases: []});
      }
      assert.deepEqual(selected.events, [[role, 'select'],
        ...(role === 'effect' ? [[role, 'check', 'shared']] : []),
        [role, 'identity', 'shared'], [role, 'select'], [role, 'check', 'shared'],
        [role, 'publish', 'shared'], [role, 'select'], [role, 'check', 'shared'],
        // Source publication custody compares installation metadata before
        // loading and again afterward; neither observation performs a read.
        ...(role === 'source' ? [[role, 'identity', 'shared']] : []),
        [role, 'load', 'shared'],
        ...(role === 'source' ? [[role, 'select'], [role, 'identity', 'shared']] : [])]);
    }
    assert.notEqual(identities[0], identities[1]);
  });

  test(`plural ${role} loading forwards the explicit table to every member`, async t => {
    const fixture = await installation(t), selected = connector('plural');
    const connectorTable = createInstalledConnectorTable([selected.entry]);
    const names = ['first', 'second', 'third'];
    const paths = await Promise.all(names.map(name => fixture.path({version: versions[role], name})));
    const adapter = await operations[role].plural(paths, {...fixture.options, connectorTable});
    const members = role === 'source' ? adapter.sources : adapter.effects;
    assert.equal(members.length, names.length);
    assert.deepEqual(selected.events.filter(event => event[1] === 'load'),
      names.map(name => [role, 'load', name]));
    assert.equal(selected.entries.length, names.length);
    assert.ok(selected.entries.every(entry => entry === selected.entries[0]));
    assert.deepEqual(adapter.connectorBindings.map(binding => binding.connectorId), names);
    await adapter.close();
    await adapter.close();
    assert.ok([...selected.owners.values()].every(owner => owner.completed === 1));
  });

  test(`explicit ${role} tables refuse missing roles and versions before loading`, async t => {
    const fixture = await installation(t);
    let selections = 0;
    const otherRole = role === 'source' ? 'effect' : 'source';
    const makeEntry = (entryRole, version) => ({name: 'unselected',
      providerBundle: 'connectors/absent/host_node', [entryRole]: {profileVersion: version,
        load: () => { selections++; throw new Error('UnexpectedModuleSelection'); }}});
    const tables = [createInstalledConnectorTable([]),
      createInstalledConnectorTable([makeEntry(otherRole, versions[role])]),
      createInstalledConnectorTable([makeEntry(role, 'actql-installed-other/0.1')])];
    const defaultVersion = role === 'source' ? 'actql-installed-duckdb-source/0.1'
      : 'actql-installed-github-effect/0.1';
    for (const version of [versions[role], defaultVersion]) {
      const path = await fixture.path({version});
      for (const connectorTable of tables) {
        for (const action of ['identity', 'publish', 'load']) {
          await assert.rejects(operations[role][action](path,
            {...fixture.options, connectorTable}), {
            code: role === 'source' ? 'InvalidInstalledSourceProfile' : 'InvalidInstalledEffectProfile'});
        }
      }
    }
    const path = await fixture.path({version: defaultVersion});
    for (const connectorTable of [null, {}, new Map()]) {
      for (const action of ['identity', 'publish', 'load']) {
        await assert.rejects(operations[role][action](path,
          {...fixture.options, connectorTable}), {code: 'InvalidInstalledConnectorTable'});
      }
    }
    assert.equal(selections, 0);
  });

  for (const defect of ['registration', 'revision']) {
    for (const failClose of [false, true]) {
      test(`explicit ${role} ${defect} mismatch retains cleanup custody (${failClose})`, async t => {
        const fixture = await installation(t), selected = connector('cleanup');
        const connectorTable = createInstalledConnectorTable([selected.entry]);
        const path = await fixture.path({version: versions[role], name: 'broken', defect, failClose});
        let failure;
        await assert.rejects(operations[role].load(path, {...fixture.options, connectorTable}), error => {
          failure = error;
          assert.equal(error.code, 'InstalledHostInitializationFailed');
          assert.equal(error.primaryFailure.code, 'InstalledConnectorRegistrationMismatch');
          assert.equal(error.cleanupPending, failClose);
          return true;
        });
        const owner = selected.owners.get(`${role}:broken`);
        assert.equal(owner.attempts, 1);
        assert.equal(owner.completed, failClose ? 0 : 1);
        const primary = failure.primaryFailure;
        if (failClose) {
          // Both bound roles route their actual registered adapter through
          // retainBoundInstalledSourceFailure's sourceProfile custody field.
          assert.deepEqual(failure.cleanupHandle.status().owners, ['source-profile']);
          assert.ok(failure.cleanupErrors.some(item => item.error === selected.closeFailure));
          await Promise.all([failure.cleanupHandle.retry(), failure.cleanupHandle.retry()]);
          assert.equal(owner.attempts, 2);
          assert.equal(failure.cleanupPending, true);
          owner.blocked = false;
          await Promise.all([failure.cleanupHandle.retry(), failure.cleanupHandle.retry()]);
          assert.equal(owner.attempts, 3);
        }
        await failure.cleanupHandle.retry();
        assert.equal(failure.cleanupPending, false);
        assert.equal(owner.completed, 1);
        assert.equal(failure.primaryFailure, primary);
        assert.deepEqual(selected.events.filter(event => event[1] === 'select'), [[role, 'select']]);
        assert.deepEqual(selected.events.filter(event => event[1] === 'load'), [[role, 'load', 'broken']]);
      });
    }
  }
}

test('a JS-only source installation receives the exact Host runtime binding without a provider bundle', async t => {
  const fixture = await installation(t);
  const selected = connector('plain');
  const connectorTable = createInstalledConnectorTable([selected.entry]);
  const path = await fixture.path({version: versions.source, name: 'plain'});
  const options = {...fixture.options, connectorTable};
  await publishInstalledSourceProfile(path, options);
  const adapter = await loadInstalledSource(path, options);
  await adapter.close();
  assert.equal(selected.entry.providerBundle, undefined);
  assert.equal(selected.entries.length, 2);
  assert.equal(selected.owners.get('source:plain').completed, 1);
  assert.deepEqual(selected.events.filter(event => event[1] === 'load'),
    [['source', 'load', 'plain']]);
});

test('a JS-only source cannot replace an unavailable supplied Host runtime with an unbound installation', async t => {
  const fixture = await installation(t);
  const selected = connector('plain');
  const connectorTable = createInstalledConnectorTable([selected.entry]);
  const path = await fixture.path({version: versions.source, name: 'plain'});
  const options = {...fixture.options, connectorTable,
    runtimeUrl: new URL('file://' + join(fixture.options.root, 'absent-runtime.js'))};
  await assert.rejects(loadInstalledSource(path, options), {code: 'ENOENT'});
  await assert.rejects(publishInstalledSourceProfile(path, options), {code: 'ENOENT'});
  assert.equal(selected.events.some(event => ['load', 'publish'].includes(event[1])), false);
  assert.equal(selected.owners.size, 0);
});

test('an explicit source table owns even the built-in DuckDB schema version', async t => {
  const fixture = await installation(t);
  const sourceVersion = 'actql-installed-duckdb-source/0.1';
  const selected = connector('replacement', {profileVersions: {...versions, source: sourceVersion}});
  const connectorTable = createInstalledConnectorTable([selected.entry]);
  const profile = {version: sourceVersion, name: 'replacement'};
  const path = await fixture.path(profile);
  const options = {...fixture.options, connectorTable};
  assert.equal(await installedSourceIdentity(path, options), identity([profile,
    {registration: 'replacement', revision: 'replacement/0.1', role: 'source'}]));
  assert.equal((await publishInstalledSourceProfile(path, options)).registration, 'replacement');
  const source = await loadInstalledSource(path, options);
  assert.equal(source.connectorRegistration, 'replacement');
  assert.equal(source.realizationKey, 'row-source-acquired');
  await source.close();
  assert.equal(selected.owners.get('source:replacement').completed, 1);
});

test('omitted and undefined tables retain the default identity bytes and absent-profile behavior', async t => {
  const fixture = await installation(t);
  const source = {version: 'actql-installed-duckdb-source/0.1',
    database: '/unopened.duckdb', schema: 'main', table: 'cafe\u0301'};
  const sourcePath = await fixture.path(source);
  const sourceIdentity = identity([source, {
    version: 'actql-installed-duckdb-target/0.1', database: source.database,
    schema: source.schema, table: source.table,
    utf8_hex: {database: '2f756e6f70656e65642e6475636b6462',
      schema: '6d61696e', table: '63616665cc81'},
  }]);
  const site = {siteGeneration: 1}, publication = {generation: 'fixture'};
  const effect = {version: 'actql-installed-github-effect/0.1', connectorId: 'default',
    accountConfigurationWire: '{"account_id":"fixture"}',
    siteProfilePath: await fixture.path(site), publicationPath: await fixture.path(publication),
    writes: [{resource: 'issue_comments', sources: [{field: 'body', target: 'body',
      null_behavior: 'reject'}]}]};
  const effectPath = await fixture.path(effect);
  const effectIdentity = identity([{...effect, accountConfigurationWire: {account_id: 'fixture'}},
    site, publication]);
  for (const options of [undefined, {}, {connectorTable: undefined}]) {
    assert.equal(await installedSourceIdentity(sourcePath, options), sourceIdentity);
    assert.equal(await installedEffectIdentity(effectPath, options), effectIdentity);
  }
  for (const role of ['source', 'effect']) {
    for (const connectorTable of [undefined, createInstalledConnectorTable([])]) {
      const options = {...fixture.options, connectorTable};
      assert.equal(await operations[role].load(undefined, options), undefined);
      assert.equal(await operations[role].plural([], options), undefined);
    }
  }
});
