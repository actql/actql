// Trusted test-only installation. All execution, admission, capture and
// cleanup remain in the installed product's existing RowSource/Run owners.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {nearestCarrierSourceRows, nearestCarrierSourceSchemas} from './nearest-carrier-source-data.mjs';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const registration = 'nearest_fixture';
const revision = 'nearest_fixture/0.1';
const version = 'actql-installed-nearest-fixture/0.1';
// Independently encoded checked schemas and declared complete-extent keys.
// The common Source owner validates these facts before residual operations.
export const nearestCarrierSchemaWires = Object.freeze({
  "queries": "{\"embedding\":{\"dimensions\":2,\"element_type\":\"f32\",\"nullable\":false,\"type\":\"vector\"},\"note\":{\"nullable\":true,\"type\":\"string\"},\"request_id\":{\"nullable\":false,\"type\":\"string\"}}",
  "candidates": "{\"embedding\":{\"dimensions\":2,\"element_type\":\"f32\",\"nullable\":false,\"type\":\"vector\"},\"item_id\":{\"nullable\":false,\"type\":\"string\"},\"label\":{\"nullable\":false,\"type\":\"string\"}}"
});
export const nearestCarrierSchemaCids = Object.freeze({
  "queries": "sha256:561dfd2407116f43ed07dbe940c571e4fea7779fa0e6dda1bf079d8f986c02a5",
  "candidates": "sha256:c58169521c543e83af21aed505d1f304fef1496c5e427295f905f797d69a349b"
});
export const nearestCarrierFactsWires = Object.freeze({
  "queries": "{\"relation_keys\":{\"candidate_keys\":[[\"request_id\"]]}}",
  "candidates": "{\"relation_keys\":{\"candidate_keys\":[[\"item_id\"]]}}"
});
export const nearestCarrierFactsCids = Object.freeze({
  "queries": "sha256:6d0c4e27a30459f74d55f662eb52b1135e895354ccc80572a737d019adbbfcd5",
  "candidates": "sha256:d34726c004dc29e71c56eef92c57a00a76e60e74b15d8c3fc8f59caba496cbba"
});
const resources = ['queries', 'candidates'];
export const nearestCarrierViewSpecification = Object.freeze({views: Object.freeze(resources.map(resource => Object.freeze({
  resource, resource_kind: 'table', schema_wire: nearestCarrierSchemaWires[resource],
  schema_cid: nearestCarrierSchemaCids[resource], facts_wire: nearestCarrierFactsWires[resource],
})))});
export const nearestCarrierReadOperations = Object.freeze(Object.fromEntries(
  resources.map(resource => [resource, `nearest_fixture:${resource}:read`])));

export function createNearestCarrierPageDriver(observations,
  readRows = resource => nearestCarrierSourceRows[resource]) {
  return async ({resource, columns, requestWire, operation: selectedOperation,
    signal, authorizationFor, chargePage, consumePage}) => {
    signal?.throwIfAborted();
    assert.ok(resources.includes(resource));
    assert.equal(selectedOperation, nearestCarrierReadOperations[resource]);
    assert.deepEqual(JSON.parse(requestWire), {});
    // Supply raw requested fields only. Common admission owns Vector f32,
    // key, nullable value and projection obligations.
    assert.ok(Array.isArray(columns));
    assert.ok(columns.length > 0 && new Set(columns).size === columns.length);
    for (const name of columns) assert.ok(Object.hasOwn(nearestCarrierSourceSchemas[resource], name));
    await authorizationFor(0);
    signal?.throwIfAborted();
    observations.sourceReadSessions++;
    observations.sourceReads++;
    observations.sourceIo++;
    observations.sourceReadCommands.push({resource, columns: [...columns], requestWire});
    const rows = readRows(resource).map(row => Object.fromEntries(
      columns.map(name => [name, structuredClone(row[name])])));
    const charge = chargePage(Buffer.from(JSON.stringify(rows)));
    await consumePage(rows, {charge});
    observations.acceptedPages++;
  };
}

export async function installNearestCarrierFixture({moon, helpers,
  createInstalledConnectorTable, directory,
  readRows = resource => nearestCarrierSourceRows[resource]}) {
  for (const resource of resources) assert.deepEqual(
    JSON.parse(nearestCarrierSchemaWires[resource]), nearestCarrierSourceSchemas[resource]);
  await mkdir(directory, {recursive: true});
  const declaration = helpers.checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    registration, registration, revision, JSON.stringify(nearestCarrierViewSpecification), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const bodies = declared.view_bodies.map(wire => JSON.parse(wire));
  const queryAliases = resources.map(resource => {
    const selected = declared.views.find(view => view.resource === resource);
    assert.ok(selected);
    const view = bodies.find(body => body.contract_cid === selected.view_cid);
    assert.ok(view);
    return {name: resource, sourceRef: selected.source_ref,
      sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid};
  });
  const accountConfigurationWire = canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'nearest-fixture',
    entries: [{entry_id: 'read', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['read']}, exclusions: []}],
  });
  const sourceProfilePath = join(directory, 'source-profile.json');
  await writeFile(sourceProfilePath, canonical({version, connectorId: registration,
    accountConfigurationWire, queryAliases}), {flag: 'wx'});
  const observations = {sourceIo: 0, sourceReads: 0, sourceReadSessions: 0,
    sourceReadCommands: [], acceptedPages: 0, issuedGrants: 0, closedSites: 0};
  const profileKeys = ['accountConfigurationWire', 'connectorId', 'version'];
  const check = profile => {
    assert.deepEqual(Object.keys(profile).sort(), profileKeys);
    assert.equal(profile.version, version);
    assert.equal(profile.connectorId, registration);
    assert.equal(profile.accountConfigurationWire, accountConfigurationWire);
    return profile;
  };
  const module = {
    check,
    identityParts: profile => [profile, nearestCarrierViewSpecification],
    async load(profile, {root, principalId, moon: installedMoon,
      baseEnvironmentWire, runtimeBundleCid}) {
      check(profile);
      const restored = helpers.checked(installedMoon.clientProgramRowSourceRestoreRelationDeclaration(
        registration, registration, revision, JSON.stringify(nearestCarrierViewSpecification), declared.catalog_cid));
      const current = JSON.parse(installedMoon.clientProgramRowSourceDeclarationJson(restored));
      const environment = helpers.rowSourceCheckEnvironment(baseEnvironmentWire, current);
      const authorization = await helpers.installRowSourceAuthorization({
        accountConfiguration: accountConfigurationWire, principalId, root,
        connectorRegistration: registration});
      const siteDirectory = join(root, 'nearest-fixture-site');
      await mkdir(siteDirectory, {recursive: true});
      const credentialPrivateKeyPath = join(siteDirectory, 'credential.pem');
      const keys = generateKeyPairSync('ed25519');
      await writeFile(credentialPrivateKeyPath,
        keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {flag: 'wx', mode: 0o600});
      const site = await helpers.openRowSourceCredentialSite({
        profile: {resourceOrigin: 'https://nearest.fixture.invalid', namespaceId: 'nearest',
          environment: 'fixture', siteKey: 'nearest', siteGeneration: 1,
          credentialAuthorityId: 'nearest-fixture', credentialKeyId: 'fixture',
          credentialPrivateKeyPath, journalRoot: join(siteDirectory, 'journal')},
        principalId, authorization, connection: 'nearest_fixture:nearest',
        connectorRegistration: registration, connectorRevision: revision,
        runtimeBundleCid, commonMoon: installedMoon,
        resolveSecret: async () => { throw new Error('NearestFixtureHasNoRemoteSecret'); },
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
          connectorId: registration, connectorRegistration: registration,
          connectorRevision: revision, site: observedSite, authorization,
          readOperation: nearestCarrierReadOperations,
          physicalTarget: (resource, fields) => ({resource, fields: [...fields], catalog_cid: current.catalog_cid}),
          bindingCid: cid({version: 'actql-nearest-fixture-binding/0.1',
            contextCid: authorization.context.contextCid, catalogCid: current.catalog_cid}),
          limits: {maxPages: 1, maxPageBytes: 4096, maxPageRows: 3, maxCaptureRows: 3},
          readPages: createNearestCarrierPageDriver(observations, readRows)});
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
