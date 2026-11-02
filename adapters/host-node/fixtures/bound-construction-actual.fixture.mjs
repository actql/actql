// Real Common/Resource parent, generated installation selection and filesystem.
// No scope, declaration, RowSource, registration or cleanup owner is replaced.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {existsSync, readdirSync, readlinkSync} from 'node:fs';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {loadInstalledEffect, publishInstalledEffectProfile} from '../installed-effect.mjs';
import {withFixtureConnector} from '../../host-common/connector-manifest.fixture.mjs';
import {canonicalJson, contentCid, sourceReadAccountConfiguration} from '../local-account-config.mjs';
import {loadInstalledTableEffect} from '../../connectors/local/host/installed-local-table.mjs';
import {fixtureCertificates, openHttpsExchangeFixture} from '../../site-node/https-exchange-fixture.mjs';
import {openHostInitializationPreparation, closeHostInitializationPreparation}
  from '../../local-node/request-preparation-adapter.mjs';
import {createInstalledHostServices, retireInstalledSourceInitialization}
  from '../installed-host-services.mjs';
import {loadInstalledSource, publishInstalledSourceProfile, installedSourcePublicationFacts} from '../installed-source.mjs';
import {installedConnectors} from '../../connectors-builtin/installations.generated.mjs';
import {createInstalledConnectorTable, installedConnectorForTable, loadInstalledConnectorModule}
  from '../installed-connectors.mjs';
import {loadInstalledBigQuerySource} from '../../connectors/bigquery/host/installed-bigquery-source.mjs';

const runtimeUrl = new URL('../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const moon = await import(runtimeUrl.href);
const environment = (await readFile(new URL('../../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();
const limits = Object.freeze({maxBytes: 8192, maxNodes: 2000, maxDepth: 24,
  maxFields: 16, maxNameBytes: 512, maxSchemaBytes: 4096, maxRows: 2,
  maxTotalRows: 4, maxValueNodes: 2000, maxValueTextBytes: 8192,
  maxJobBytes: 256, maxPageTokenBytes: 256, maxPages: 4, maxResults: 2,
  timeoutMs: 0, maxRequests: 8, maxRequestBytes: 8192, maxSecretBytes: 2048,
  pollDelayMs: 0, maximumBytesBilled: '9223372036854775807',
  maxDeclarationBytes: 200000, maxDeclarationNodes: 20000, maxCaBytes: 8192});

const cid = digit => `sha256:${digit.repeat(64)}`;
const common = root => ({connectorId: 'table', connection: 'table-local',
  // Installation must not invoke this nonexistent Python executable.
  python: join(root, 'uninstalled-python'),
  catalog: {database: join(root, 'catalog.db'), warehouse: join(root, 'warehouse'),
    catalogCid: cid('3'), limits: {bytes: 16777216, files: 256, operations: 32}},
  accountConfigurationWire: sourceReadAccountConfiguration({connection: 'table-local', resource: 'rows'})});
function tableEffectValue(root, approval = 'required') {
  const body = JSON.parse(environment);
  const targetRef = 'connector://table/catalog', mappingRef = 'mapping:table.catalog.v1';
  const manifestCid = withFixtureConnector(body, targetRef);
  const schema = {additional_properties: false, fields: {
    Id: {nullable: false, type: 'number'}, Name: {nullable: true, type: 'number'}},
    nullable: false, type: 'object'};
  const mapping = {connector_manifest_cid: manifestCid, conversions: [], mapping_ref: mappingRef,
    minimum_approval: approval, permission_rules: [{effect_kind: 'store', permissions: ['scope:store'],
      selector_class: 'none', write_fields: ['Name']}], primary_identity: 'Id',
    required_fields: [], required_permissions: [], resource_identity_cid: cid('b'),
    row_mapping: {Name: {field: 'id', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1', target_ref: targetRef, target_schema: schema,
    target_schema_identity: contentCid(schema), version: 'reference-v1', writable_fields: ['Name']};
  mapping.mapping_contract_cid = contentCid(mapping);
  body.mapping_contracts = [mapping];
  delete body.evidence_bundle_cid;
  const environmentWire = canonicalJson({...body, evidence_bundle_cid: contentCid(body)});
  return {...common(root), version: 'actql-installed-local-table-effect/0.1', environmentWire,
    targets: [{effectId: 'save', resource: 'rows', targetRef, mappingRef,
      mappingCid: mapping.mapping_contract_cid, action: 'create', catalogCid: cid('3'),
      namespace: ['test'], tableName: 'rows', expectedTable: null,
      permissions: ['scope:store'], footprint: {version: 'fixture-only'}}], limits: {}};
}

export async function boundConstructionActualFixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-bound-construction-actual-'));
  const state = {}, sources = [], failures = [];
  let active = true, childrenPending = false, services, closed = false, secretReads = 0;
  let currentFault;
  const openJournalDescriptors = path => {
    if (process.platform !== 'linux') return undefined;
    return readdirSync('/proc/self/fd').filter(fd => {
      try {return readlinkSync(`/proc/self/fd/${fd}`) === path;}
      catch (error) {if (error.code === 'ENOENT') return false; throw error;}
    });
  };
  const current = () => {
    assert.equal(active, true, 'same initial parent remains current');
    if (currentFault !== undefined && currentFault.calls === 0 &&
        (currentFault.journal ? currentFault.siteReturned !== undefined : existsSync(currentFault.path))) {
      // The actual bound Site has returned to its original custody owner.
      // /proc descriptors remain an additional Linux assertion, not readiness.
      currentFault.descriptors = currentFault.journal ? openJournalDescriptors(currentFault.path) : undefined;
      currentFault.calls++;
      throw currentFault.failure;
    }
  };
  async function close() {
    if (closed) return;
    // A pending child is never converted into a parent acknowledgement.
    for (const failure of failures) {
      if (failure.cleanupHandle?.status().pending === true) {
        const observed = await failure.cleanupHandle.retry();
        assert.equal(observed.pending, false);
      }
    }
    for (const source of sources) await source.close();
    if (services !== undefined) assert.equal(retireInstalledSourceInitialization(services), true);
    childrenPending = false;
    closeHostInitializationPreparation(state);
    active = false; closed = true;
  }
  t.after(async () => {await close(); await rm(root, {recursive: true, force: true});});
  const parentInput = Object.freeze({root, purpose: 'installed connector component verification'});
  const parent = openHostInitializationPreparation(state, moon, parentInput, current, () => childrenPending);
  services = createInstalledHostServices({root, principalId: 'operator', moon,
    initialPreparation: parent, assertCurrent: current});
  childrenPending = true;
  const certificates = await fixtureCertificates(root);
  const privateKey = generateKeyPairSync('ed25519').privateKey.export({type: 'pkcs8', format: 'pem'});
  const keyPath = join(root, 'credential.key'); await writeFile(keyPath, privateKey, {mode: 0o600});
  let serial = 0;
  async function profile({missingKey = false} = {}) {
    const name = `bigquery${++serial}`, metadataPath = join(root, `${name}-metadata.json`),
      siteProfilePath = join(root, `${name}-site.json`), path = join(root, `${name}-profile.json`);
    const site = {version: 'actql-installed-bigquery-site/0.1', apiOrigin: 'https://bigquery.example',
      credentialAuthorityId: name, credentialKeyId: 'key',
      credentialPrivateKeyPath: missingKey ? join(root, 'missing-credential.key') : keyPath,
      environment: 'test', journalRoot: join(root, `${name}-journal`), namespaceId: name,
      siteGeneration: 1, siteKey: name, tokenEnvironment: 'UNUSED_BOUNDARY_TOKEN', caPath: certificates.caPath};
    const body = {kind: 'bigquery#table', etag: 'original-metadata', type: 'TABLE', tableReference: {projectId: 'acme-project', datasetId: 'product', tableId: 'usage'},
      schema: {fields: [{name: 'ACCOUNT_ID', type: 'STRING', mode: 'REQUIRED'}]}};
    const metadata = {version: 'actql-bigquery-read-metadata/0.1', connectorId: name,
      resource: 'usage', project: 'acme-project', dataset: 'product', table: 'usage',
      location: 'EU', apiOrigin: site.apiOrigin, body: Buffer.from(JSON.stringify(body)).toString('base64')};
    const value = {version: 'actql-installed-bigquery-source/0.1', connectorId: name,
      resource: 'usage', project: 'acme-project', dataset: 'product', table: 'usage', location: 'EU',
      metadataPath, siteProfilePath, accountConfigurationWire: JSON.stringify({
        version: 'actql-execution-account-config/0.1', account_id: name, entries: [{
          entry_id: 'read', outcome: 'allow', principal: {all: true}, connection: {all: true},
          resource: {all: true}, operation: {any_of: ['read']}, exclusions: []}]}), limits};
    await writeFile(metadataPath, JSON.stringify(metadata));
    await writeFile(siteProfilePath, JSON.stringify(site));
    await writeFile(path, JSON.stringify(value));
    // Verify the generated role really chooses this production provider. The
    // actual load below still uses the normal top-level table, not this lookup.
    const entry = installedConnectorForTable(createInstalledConnectorTable(installedConnectors), 'source', value);
    assert.equal(entry.registration, 'bigquery');
    assert.equal((await loadInstalledConnectorModule(entry)).load, loadInstalledBigQuerySource);
    return {path, value, journalPath: join(site.journalRoot, 'credential-journal.sqlite3')};
  }
  async function salesforceProfile(role = 'source') {
    assert.ok(['source', 'effect'].includes(role));
    const resource = 'Test_Record__c', prefix = '/services/data/v62.0/sobjects/';
    const description = {name: resource, queryable: true, createable: true, updateable: true,
      fields: [{name: 'Id', type: 'id', nillable: false, sortable: true},
        {name: 'Name', type: 'string', nillable: false, defaultedOnCreate: false,
          createable: true, updateable: true}]};
    const api = await openHttpsExchangeFixture(t, {routes: [
      {method: 'GET', pathname: prefix, handle: () => ({body: {sobjects: [
        {name: resource, queryable: true, createable: true, updateable: true}]}})},
      {method: 'GET', pathname: `${prefix}${resource}/describe`, handle: () => ({body: description})}]});
    const name = `salesforce${++serial}`, siteProfilePath = join(root, `${name}-site.json`);
    const path = join(root, `${name}-profile.json`), journalRoot = join(root, `${name}-journal`);
    await writeFile(siteProfilePath, JSON.stringify({version: 'actql-installed-salesforce-site/0.1',
      apiVersion: 'v62.0', cliAlias: 'unused-loopback', cliUsername: 'fixture@example.test',
      connectionRevision: 'original-connection', credentialAuthorityId: name, credentialKeyId: 'key',
      credentialPrivateKeyPath: keyPath, environment: 'test', instanceOrigin: api.origin,
      journalRoot, orgId: '00D000000000001EAA', siteGeneration: 1, siteKey: name,
      namespaceId: name, caPath: api.caPath}));
    const value = {version: `actql-installed-salesforce-${role}/0.1`, connectorId: name,
      siteProfilePath, publicationPath: join(root, `${name}-publication.json`),
      accountConfigurationWire: canonicalJson({version: 'actql-execution-account-config/0.1',
        account_id: name, entries: [{entry_id: 'records', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {any_of: ['effect', 'read']}, exclusions: []}]}),
      ...(role === 'source' ? {resources: [resource]} : {writes: [{resource, kind: 'update', fields: ['Name']}]})};
    await writeFile(path, JSON.stringify(value));
    const entry = installedConnectorForTable(createInstalledConnectorTable(installedConnectors), role, value);
    assert.equal(entry.registration, 'salesforce');
    const publish = role === 'source' ? publishInstalledSourceProfile : publishInstalledEffectProfile;
    let publicationSecretReads = 0;
    const publication = await publish(path, {root, principalId: 'operator', moon, runtimeUrl,
      baseEnvironmentWire: environment,
      resolveSecret() {publicationSecretReads++; return 'loopback-only-fixture-token';}});
    assert.ok(publicationSecretReads > 0);
    const journalPath = join(journalRoot, 'credential-journal.sqlite3');
    if (process.platform === 'linux') assert.deepEqual(openJournalDescriptors(journalPath), []);
    return {path, value, registration: 'salesforce', role, journalPath, publication,
      exchanges: () => api.seen().length};
  }
  async function gcsProfile() {
    const name = `gcs${++serial}`, siteProfilePath = join(root, `${name}-site.json`);
    const path = join(root, `${name}-profile.json`), journalRoot = join(root, `${name}-journal`);
    await writeFile(siteProfilePath, JSON.stringify({version: 'actql-installed-gcs-site/0.1',
      credentialAuthorityId: name, credentialKeyId: 'key', credentialPrivateKeyPath: keyPath,
      environment: 'test', journalRoot, namespaceId: name, siteGeneration: 1,
      siteKey: name, tokenEnvironment: 'UNUSED_BOUNDARY_TOKEN'}));
    const value = {version: 'actql-installed-gcs-source/0.1', connectorId: name,
      project: 'fixture-project', bucket: 'actql-fixture', prefix: 'test/', mediaType: 'application/pdf',
      siteProfilePath, accountConfigurationWire: canonicalJson({version: 'actql-execution-account-config/0.1',
        account_id: name, entries: [{entry_id: 'read', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {any_of: ['read']}, exclusions: []}]}),
      limits: {maxListingItems: 3, maxExaminedItems: 9, maxPages: 4, maxAttempts: 4,
        maxListingBytes: 32768, maxDurationMs: 10000, maxPathBytes: 1024,
        maxPageBytes: 8192, maxPageItems: 9, maxRequestBytes: 4096, maxContentBytes: 4096}};
    await writeFile(path, JSON.stringify(value));
    const entry = installedConnectorForTable(createInstalledConnectorTable(installedConnectors), 'source', value);
    assert.equal(entry.registration, 'gcs');
    return {path, value, registration: 'gcs', journalPath: join(journalRoot, 'credential-journal.sqlite3')};
  }
  async function githubProfile() {
    const {graphqlRoute} = await import('../../connectors/github/test/github-graphql.fixture.mjs');
    const world = {repositories: new Map([['R_original', {databaseId: 1296269,
      nameWithOwner: 'octo/hello', issues: [], pullRequests: []}]]),
      names: new Map([['octo/hello', 'R_original']])};
    const api = await openHttpsExchangeFixture(t, {routes: [graphqlRoute(() => world)]});
    const name = `github${++serial}`, siteProfilePath = join(root, `${name}-site.json`);
    const path = join(root, `${name}-profile.json`);
    const journalRoot = join(root, `${name}-journal`);
    await writeFile(siteProfilePath, JSON.stringify({version: 'actql-installed-github-site/0.1',
      apiOrigin: api.origin, owner: 'octo', repo: 'hello', namespaceId: name,
      environment: 'test', siteKey: name, siteGeneration: 1,
      credentialAuthorityId: name, credentialKeyId: 'key', credentialPrivateKeyPath: keyPath,
      journalRoot, tokenEnvironment: 'UNUSED_BOUNDARY_TOKEN', caPath: api.caPath}));
    const value = {version: 'actql-installed-github-source/0.1', connectorId: name,
      siteProfilePath, publicationPath: join(root, `${name}-publication.json`),
      accountConfigurationWire: canonicalJson({version: 'actql-execution-account-config/0.1',
        account_id: name, entries: [{entry_id: 'read', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true}, operation: {any_of: ['read']}, exclusions: []}]})};
    await writeFile(path, JSON.stringify(value));
    const entry = installedConnectorForTable(createInstalledConnectorTable(installedConnectors), 'source', value);
    assert.equal(entry.registration, 'github');
    // Real explicit publication owns and closes its actual Site. Only the
    // remote GraphQL service and token are fixtures, never publication facts.
    let publicationSecretReads = 0;
    const publication = await publishInstalledSourceProfile(path, {root, principalId: 'operator',
      moon, runtimeUrl, baseEnvironmentWire: environment,
      resolveSecret() {publicationSecretReads++; return 'loopback-only-fixture-token';}});
    assert.ok(publicationSecretReads > 0);
    assert.equal(publication.repository.node_id, 'R_original');
    const journalPath = join(journalRoot, 'credential-journal.sqlite3');
    if (process.platform === 'linux') assert.deepEqual(openJournalDescriptors(journalPath), []);
    return {path, value, registration: 'github', journalPath, publication,
      exchanges: () => api.seen().length};
  }
  async function metadataSourceProfile(provider) {
    assert.ok(['hubspot', 'kintone', 'snowflake'].includes(provider));
    const name = `${provider}${++serial}`;
    const siteProfilePath = join(root, `${name}-site.json`);
    const metadataPath = join(root, `${name}-metadata.json`);
    const path = join(root, `${name}-profile.json`);
    const site = {version: `actql-installed-${provider}-site/0.1`, apiOrigin: `https://${provider}.example`,
      credentialAuthorityId: name, credentialKeyId: 'key', credentialPrivateKeyPath: keyPath,
      environment: 'test', journalRoot: join(root, `${name}-journal`), namespaceId: name,
      siteGeneration: 1, siteKey: name, tokenEnvironment: 'UNUSED_BOUNDARY_TOKEN', caPath: certificates.caPath};
    const accountConfigurationWire = canonicalJson({version: 'actql-execution-account-config/0.1',
      account_id: name, entries: [{entry_id: 'read', outcome: 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true}, operation: {any_of: ['read']}, exclusions: []}]});
    const encode = value => Buffer.from(JSON.stringify(value)).toString('base64');
    let metadata, value;
    if (provider === 'hubspot') {
      metadata = {version: 'actql-hubspot-read-metadata/0.1', connectorId: name,
        portalId: '7', apiOrigin: site.apiOrigin,
        accountBody: encode({portalId: 7, accountType: 'STANDARD'}),
        objects: [{resource: 'companies', objectType: 'companies', propertiesBody: encode({results: [
          {name: 'amount', type: 'number', fieldType: 'number'}]})}]};
      value = {version: 'actql-installed-hubspot-source/0.1', connectorId: name, portalId: '7',
        resources: [{resource: 'companies', objectType: 'companies'}], metadataPath, siteProfilePath,
        metadataResources: {account: 'account', properties: 'properties'}, accountConfigurationWire,
        limits: {maxResponseBytes: 4096, maxNodes: 1000, maxDepth: 20, maxProperties: 10,
          maxNameUnits: 100, maxPages: 2, maxRows: 2, maxRequests: 5, perPage: 1,
          maxColumns: 3, maxCursorUnits: 64, maxValueNodes: 100, maxValueTextBytes: 4096,
          maxRowsWireBytes: 4096, maxRowsWireNodes: 100, maxRowsWireDepth: 10,
          maxObjects: 2, maxDeclarationBytes: 4096, maxDeclarationNodes: 1000, maxSecretBytes: 128}};
    } else if (provider === 'kintone') {
      metadata = {version: 'actql-kintone-record-metadata/0.1', connectorId: name,
        appId: '12', apiOrigin: site.apiOrigin, formBody: encode({revision: '7', properties: {
          Subject: {code: 'Subject', type: 'SINGLE_LINE_TEXT'}}})};
      value = {version: 'actql-installed-kintone-source/0.1', connectorId: name, appId: '12',
        resource: 'inquiries', formResource: 'form', fieldCodes: ['Subject'],
        metadataPath, siteProfilePath, accountConfigurationWire,
        limits: {maxResponseBytes: 8192, maxNodes: 2000, maxDepth: 20, maxFields: 16, maxNameUnits: 512,
          maxColumns: 8, maxCells: 64, maxTableRows: 16, maxValueNodes: 1000, maxValueDepth: 16,
          maxValueTextBytes: 8192, maxContractPairs: 100, maxRequestBytes: 4096, maxRequests: 6,
          maxPages: 2, perPage: 2, maxSecretBytes: 128, maxRows: 4,
          maxDeclarationBytes: 200000, maxDeclarationNodes: 20000}};
    }
    if (provider === 'snowflake') {
      const {metadataBody, readLimits} = await import('../../connectors/snowflake/test/snowflake-response.fixture.mjs');
      Object.assign(site, {warehouse: 'ANALYTICS', role: 'READER', authenticationType: 'OAUTH'});
      metadata = {version: 'actql-snowflake-read-metadata/0.1', connectorId: name,
        resource: 'usage_30d', database: 'PRODUCT', schema: 'USAGE', table: 'USAGE_30D',
        apiOrigin: site.apiOrigin, bodies: [metadataBody().toString('base64')]};
      value = {version: 'actql-installed-snowflake-source/0.1', connectorId: name,
        resource: 'usage_30d', database: 'PRODUCT', schema: 'USAGE', table: 'USAGE_30D',
        metadataPath, siteProfilePath, accountConfigurationWire,
        limits: {...readLimits, maxRows: 3, maxTotalRows: 3,
          maxDescriptionBytes: 4096, maxDeclarationBytes: 200000, maxDeclarationNodes: 20000}};
    }
    await writeFile(metadataPath, JSON.stringify(metadata));
    await writeFile(siteProfilePath, JSON.stringify(site));
    await writeFile(path, JSON.stringify(value));
    const entry = installedConnectorForTable(createInstalledConnectorTable(installedConnectors), 'source', value);
    assert.equal(entry.registration, provider);
    return {path, value, registration: provider, journalPath: join(site.journalRoot, 'credential-journal.sqlite3')};
  }
  async function tableSourceProfile({invalidAccount = false, invalidSelector = false} = {}) {
    const schemaWire = (await readFile(new URL('../../connectors/local/iceberg/fixtures/presence-schema.json', import.meta.url), 'utf8')).trimEnd();
    const value = {...common(root), version: 'actql-installed-local-table-source/0.1',
      targets: [{resource: 'rows', schemaWire, selector: {catalog_identity_cid: cid('3'),
        namespace: ['test'], table_name: 'rows',
        table_uuid: '00000000-0000-0000-0000-000000000001',
        schema_cid: 'sha256:8f5aaf81ac549e3e1b2724b949725bffe152abbae67451b31276b17f11c74e9a'}}],
      limits: {maxPages: 3, maxPageBytes: 65536, maxPageRows: 16, maxCaptureRows: 16}};
    if (invalidAccount) value.accountConfigurationWire = '{}';
    if (invalidSelector) value.targets[0].selector.catalog_identity_cid = cid('4');
    const path = join(root, `table-source-${++serial}.json`);
    await writeFile(path, JSON.stringify(value));
    const entry = installedConnectorForTable(createInstalledConnectorTable(installedConnectors), 'source', value);
    assert.equal(entry.registration, 'local');
    return {path, value, registration: 'local'};
  }
  async function tableEffectProfile({invalidCatalog = false, invalidTarget = false} = {}) {
    const value = tableEffectValue(root);
    if (invalidCatalog) value.catalog.catalogCid = 'not-a-cid';
    if (invalidTarget) value.targets[0].namespace = ['invalid.namespace'];
    const path = join(root, `table-effect-${++serial}.json`);
    await writeFile(path, JSON.stringify(value));
    const entry = installedConnectorForTable(createInstalledConnectorTable(installedConnectors), 'effect', value);
    assert.equal(entry.registration, 'local');
    // Generated role selection, not a hand-selected test loader.
    const {loadInstalledEffectModule} = await import('../installed-connectors.mjs');
    assert.equal((await loadInstalledEffectModule(entry)).load, loadInstalledTableEffect);
    return {path, value, role: 'effect', registration: 'local'};
  }
  async function load(selection, {connectorTable} = {}) {
    try {
      const role = selection.role === 'effect' ? 'effect' : 'source';
      if (currentFault?.selection === selection) {
        const fault = currentFault;
        const entry = installedConnectorForTable(connectorTable ??
          createInstalledConnectorTable(installedConnectors), role, selection.value);
        const originalRole = entry[role];
        connectorTable = createInstalledConnectorTable([{...entry, [role]: {...originalRole,
          async load() {
            const module = await Reflect.apply(originalRole.load, originalRole, []);
            return {...module, load(profile, options) {
              const original = options.construction;
              const observe = name => async (...args) => {
                const opened = await Reflect.apply(original[name], original, args);
                // The original bound method has retained this exact Site pair.
                // Do not infer acquisition from a closed publication file.
                fault.siteReturned = opened;
                current();
                return opened;
              };
              const construction = Object.freeze({...original,
                openRowSite: observe('openRowSite'),
                openSpecializedSite: observe('openSpecializedSite')});
              return Reflect.apply(module.load, module, [profile, {...options, construction}]);
            }};
          }}}]);
      }
      const loader = selection.role === 'effect' ? loadInstalledEffect : loadInstalledSource;
      const source = await loader(selection.path, {root, principalId: 'operator',
        moon, runtimeUrl, baseEnvironmentWire: environment, installationServices: services, connectorTable,
        resolveSecret() {secretReads++; assert.fail('Initialization must not resolve a provider token');}});
      sources.push(source);
      if (selection.role !== 'effect') {
        assert.equal(source.connectorRegistration, selection.registration ?? 'bigquery');
        assert.equal(installedSourcePublicationFacts(source)?.path, selection.path);
      }
      return source;
    } catch (failure) {
      failures.push(failure);
      // Bounded structural diagnostics only: no key, account, metadata bytes,
      // retained nominal objects or provider credentials are serialized.
      const pending = [failure], seen = new Set(), chain = [];
      while (pending.length && chain.length < 10) {
        const item = pending.shift();
        if (item === null || typeof item !== 'object' || seen.has(item)) continue;
        seen.add(item);
        chain.push({name: item.name, code: item.code,
          type: item.constructor?.name, tag: item.$tag,
          stack: typeof item.stack === 'string' ? item.stack.split('\n').slice(1, 7) : undefined});
        pending.push(item.cause, item.primaryFailure);
      }
      t.diagnostic(JSON.stringify({initializationFailureChain: chain}));
      throw failure;
    }
  }
  return {profile, salesforceProfile, gcsProfile, githubProfile, metadataSourceProfile, tableSourceProfile, tableEffectProfile, load, close, sources, services, moon, root, openJournalDescriptors,
    failCurrentAfterTableConstruction() {
      assert.equal(currentFault, undefined);
      currentFault = {path: join(root, 'state', 'effects', 'ledger'), calls: 0,
        failure: new Error('OriginalPostTableConstructionCurrentFailure')};
      return currentFault;
    },
    failCurrentAfterJournal(selection) {
      assert.equal(currentFault, undefined);
      currentFault = {selection, path: selection.journalPath, journal: true, calls: 0,
        failure: new Error('OriginalPostSiteCurrentFailure'), descriptors: undefined};
      return currentFault;
    },
    pending: () => !closed, secretReads: () => secretReads,
    retire: () => retireInstalledSourceInitialization(services)};
}
