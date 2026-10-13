// Trusted test-only installation. All execution, admission, capture and
// cleanup remain in the installed product's existing RowSource/Run owners.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {carrierContinuationRecordsRows, carrierContinuationRecordsSchema} from '../release-carrier-continuation-query-cases.mjs';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const connectorId = 'crm/main';
const registration = 'carrier_fixture';
const revision = 'carrier_fixture/0.1';
const version = 'actql-installed-carrier-fixture/0.1';
// Original records schema and trusted complete-extent id guarantee. The
// common bounded key owner validates every raw row before WHERE id=1.
export const carrierContinuationSchemaWire = '{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}}';
export const carrierContinuationSchemaCid = 'sha256:bfa97ad45a64359561649b04e9e23326736ce2c4eefa22d6ac95dc112984093c';
export const carrierContinuationFactsWire = '{"relation_keys":{"candidate_keys":[["id"]]}}';
export const carrierContinuationFactsCid = 'sha256:38ffc0cad6baa7699f2ed6b40426b522df5bc7dd9dc369024d278f70a1d29209';
const resources = ['r'];
export const carrierContinuationViewSpecification = Object.freeze({views: Object.freeze([Object.freeze({
  resource: 'r', resource_kind: 'table', schema_wire: carrierContinuationSchemaWire,
  schema_cid: carrierContinuationSchemaCid, facts_wire: carrierContinuationFactsWire,
})])});
export const carrierContinuationReadOperations = Object.freeze({r: 'carrier_fixture:r:read'});

export function createCarrierContinuationPageDriver(observations) {
  return async ({resource, columns, requestWire, operation: selectedOperation,
    signal, authorizationFor, chargePage, consumePage}) => {
    signal?.throwIfAborted();
    assert.ok(resources.includes(resource));
    assert.equal(selectedOperation, carrierContinuationReadOperations[resource]);
    assert.deepEqual(JSON.parse(requestWire), {});
    // The driver supplies all original rows, without applying the authored
    // WHERE. Common key validation and residual predicate own that boundary.
    assert.ok(Array.isArray(columns));
    assert.ok(columns.length > 0 && new Set(columns).size === columns.length);
    for (const name of columns) assert.ok(Object.hasOwn(carrierContinuationRecordsSchema, name));
    await authorizationFor(0);
    signal?.throwIfAborted();
    observations.sourceReadSessions++;
    observations.sourceReads++;
    observations.sourceIo++;
    observations.sourceReadCommands.push({resource, columns: [...columns], requestWire});
    const rows = carrierContinuationRecordsRows.map(row => Object.fromEntries(
      columns.map(name => [name, structuredClone(row[name])])));
    const charge = chargePage(Buffer.from(JSON.stringify(rows)));
    await consumePage(rows, {charge});
    observations.acceptedPages++;
  };
}

export async function installCarrierContinuationFixture({moon, helpers,
  createInstalledConnectorTable, directory}) {
  assert.deepEqual(JSON.parse(carrierContinuationSchemaWire), carrierContinuationRecordsSchema);
  await mkdir(directory, {recursive: true});
  const declaration = helpers.checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    registration, connectorId, revision, JSON.stringify(carrierContinuationViewSpecification), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const bodies = declared.view_bodies.map(wire => JSON.parse(wire));
  const queryAliases = resources.map(resource => {
    const selected = declared.views.find(view => view.resource === resource);
    assert.ok(selected);
    const view = bodies.find(body => body.contract_cid === selected.view_cid);
    assert.ok(view);
    return {name: 'records', sourceRef: selected.source_ref,
      sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid};
  });
  const accountConfigurationWire = canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'carrier-fixture',
    entries: [{entry_id: 'read', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['read']}, exclusions: []}],
  });
  const sourceProfilePath = join(directory, 'source-profile.json');
  await writeFile(sourceProfilePath, canonical({version, connectorId,
    accountConfigurationWire, queryAliases}), {flag: 'wx'});
  const observations = {sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
    sourceReadCommands: [], acceptedPages: 0, issuedGrants: 0, closedSites: 0};
  const profileKeys = ['accountConfigurationWire', 'connectorId', 'version'];
  const check = profile => {
    assert.deepEqual(Object.keys(profile).sort(), profileKeys);
    assert.equal(profile.version, version);
    assert.equal(profile.connectorId, connectorId);
    assert.equal(profile.accountConfigurationWire, accountConfigurationWire);
    return profile;
  };
  const module = {
    check,
    identityParts: profile => [profile, carrierContinuationViewSpecification],
    async load(profile, {root, principalId, moon: installedMoon,
      baseEnvironmentWire, runtimeBundleCid}) {
      check(profile);
      const restored = helpers.checked(installedMoon.clientProgramRowSourceRestoreRelationDeclaration(
        registration, connectorId, revision, JSON.stringify(carrierContinuationViewSpecification), declared.catalog_cid));
      const current = JSON.parse(installedMoon.clientProgramRowSourceDeclarationJson(restored));
      const environment = helpers.rowSourceCheckEnvironment(baseEnvironmentWire, current);
      const authorization = await helpers.installRowSourceAuthorization({
        accountConfiguration: accountConfigurationWire, principalId, root,
        connectorRegistration: registration});
      const siteDirectory = join(root, 'carrier-fixture-site');
      await mkdir(siteDirectory, {recursive: true});
      const credentialPrivateKeyPath = join(siteDirectory, 'credential.pem');
      const keys = generateKeyPairSync('ed25519');
      await writeFile(credentialPrivateKeyPath,
        keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {flag: 'wx', mode: 0o600});
      const site = await helpers.openRowSourceCredentialSite({
        profile: {resourceOrigin: 'https://carrier.fixture.invalid', namespaceId: 'carrier',
          environment: 'fixture', siteKey: 'carrier', siteGeneration: 1,
          credentialAuthorityId: 'carrier-fixture', credentialKeyId: 'fixture',
          credentialPrivateKeyPath, journalRoot: join(siteDirectory, 'journal')},
        principalId, authorization, connection: 'carrier_fixture:records',
        connectorRegistration: registration, connectorRevision: revision,
        runtimeBundleCid, commonMoon: installedMoon,
        resolveSecret: async () => { throw new Error('CarrierFixtureHasNoRemoteSecret'); },
        admitsApprovalTarget: binding => binding?.catalog_cid === current.catalog_cid &&
          resources.includes(binding?.resource),
      });
      const observedSite = {...site,
        issueReadGrant(options) {
          const grant = site.issueReadGrant(options);
          observations.issuedGrants++;
          return grant;
        },
        close() { site.close(); observations.closedSites++; },
      };
      try {
        return await helpers.createInstalledRowSource({moon: installedMoon,
          declaration: restored, declared: current, environmentWire: environment.wire,
          connectorId, connectorRegistration: registration,
          connectorRevision: revision, site: observedSite, authorization,
          readOperation: carrierContinuationReadOperations,
          physicalTarget: (resource, fields) => ({resource, fields: [...fields], catalog_cid: current.catalog_cid}),
          bindingCid: cid({version: 'actql-carrier-fixture-binding/0.1',
            contextCid: authorization.context.contextCid, catalogCid: current.catalog_cid}),
          limits: {maxPages: 1, maxPageBytes: 4096, maxPageRows: 3, maxCaptureRows: 3},
          readPages: createCarrierContinuationPageDriver(observations)});
      } catch (cause) {
        throw await helpers.retainInstalledHostInitializationFailure(cause,
          {sourceProfile: observedSite});
      }
    },
  };
  const connectorTable = createInstalledConnectorTable([{name: registration,
    registration, revision, source: {profileVersion: version, load: async () => module}}]);
  return {connectorTable, sourceProfilePath, observations};
}
