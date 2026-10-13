// Trusted test-only installation. All execution, admission, capture and
// cleanup remain in the installed product's existing RowSource/Run owners.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {sourceRows as identifierSourceRows} from './public-query-input.mjs';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const connectorId = 'crm/main';
const registration = 'identifier_fixture';
const revision = 'identifier_fixture/0.1';
const version = 'actql-installed-identifier-fixture/0.1';
// The original Source has duplicate ids and nullable amounts. It has no
// candidate-key or score guarantee; ordinary query operators retain NULLs and duplicate rows.
export const identifierSchemaWire = '{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}}';
export const identifierSchemaCid = cid(JSON.parse(identifierSchemaWire));
export const identifierViewSpecification = Object.freeze({views: Object.freeze([Object.freeze({
  resource: 'r', resource_kind: 'table', schema_wire: identifierSchemaWire,
  schema_cid: identifierSchemaCid,
})])});
export const identifierReadOperations = Object.freeze({r: 'identifier_fixture:r:read'});

export function createIdentifierRows() {
  let current = structuredClone(identifierSourceRows);
  return {
    read: () => structuredClone(current),
    prepare(rows = identifierSourceRows) {
      assert.ok(Array.isArray(rows));
      if (rows.length !== 0) assert.deepEqual(rows, identifierSourceRows);
      current = structuredClone(rows);
    },
  };
}

export function createIdentifierPageDriver(observations, rows) {
  return async ({resource, columns, requestWire, operation: selectedOperation,
    signal, authorizationFor, chargePage, consumePage}) => {
    signal?.throwIfAborted();
    assert.equal(resource, 'r');
    assert.equal(selectedOperation, identifierReadOperations[resource]);
    assert.deepEqual(JSON.parse(requestWire), {});
    // Projection is transport-only. Predicate and aggregation remain in the
    // original common Program; the supplier never filters or deduplicates.
    assert.ok(Array.isArray(columns));
    assert.ok(columns.length > 0 && new Set(columns).size === columns.length);
    for (const name of columns) assert.ok(['amount', 'id'].includes(name));
    await authorizationFor(0);
    signal?.throwIfAborted();
    observations.sourceReadSessions++;
    observations.sourceReads++;
    observations.sourceIo++;
    observations.sourceReadCommands.push({resource, columns: [...columns], requestWire});
    const pageRows = rows.read().map(row => Object.fromEntries(
      columns.map(name => [name, row[name]])));
    const charge = chargePage(Buffer.from(JSON.stringify(pageRows)));
    await consumePage(pageRows, {charge});
    observations.acceptedPages++;
  };
}

export async function installIdentifierFixture({moon, helpers,
  createInstalledConnectorTable, directory}) {
  const rows = createIdentifierRows();
  await mkdir(directory, {recursive: true});
  const declaration = helpers.checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    connectorId, registration, revision, JSON.stringify(identifierViewSpecification), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const bodies = declared.view_bodies.map(wire => JSON.parse(wire));
  const selected = declared.views.find(view => view.resource === 'r');
  assert.ok(selected);
  const view = bodies.find(body => body.contract_cid === selected.view_cid);
  assert.ok(view);
  const queryAliases = [{name: 'records', sourceRef: selected.source_ref,
    sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid}];
  const accountConfigurationWire = canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'identifier-fixture',
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
    identityParts: profile => [profile, identifierViewSpecification],
    async load(profile, {root, principalId, moon: installedMoon,
      baseEnvironmentWire, runtimeBundleCid}) {
      check(profile);
      const restored = helpers.checked(installedMoon.clientProgramRowSourceRestoreRelationDeclaration(
        connectorId, registration, revision, JSON.stringify(identifierViewSpecification), declared.catalog_cid));
      const current = JSON.parse(installedMoon.clientProgramRowSourceDeclarationJson(restored));
      const environment = helpers.rowSourceCheckEnvironment(baseEnvironmentWire, current);
      const authorization = await helpers.installRowSourceAuthorization({
        accountConfiguration: accountConfigurationWire, principalId, root,
        connectorRegistration: registration});
      const siteDirectory = join(root, 'identifier-fixture-site');
      await mkdir(siteDirectory, {recursive: true});
      const credentialPrivateKeyPath = join(siteDirectory, 'credential.pem');
      const keys = generateKeyPairSync('ed25519');
      await writeFile(credentialPrivateKeyPath,
        keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {flag: 'wx', mode: 0o600});
      const site = await helpers.openRowSourceCredentialSite({
        profile: {resourceOrigin: 'https://identifier.fixture.invalid', namespaceId: 'identifiers',
          environment: 'fixture', siteKey: 'identifiers', siteGeneration: 1,
          credentialAuthorityId: 'identifier-fixture', credentialKeyId: 'fixture',
          credentialPrivateKeyPath, journalRoot: join(siteDirectory, 'journal')},
        principalId, authorization, connection: 'identifier_fixture:rows',
        connectorRegistration: registration, connectorRevision: revision,
        runtimeBundleCid, commonMoon: installedMoon,
        resolveSecret: async () => { throw new Error('IdentifierFixtureHasNoRemoteSecret'); },
        admitsApprovalTarget: binding => binding?.catalog_cid === current.catalog_cid &&
          binding?.resource === 'r',
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
          readOperation: identifierReadOperations,
          physicalTarget: (resource, fields) => ({resource, fields: [...fields], catalog_cid: current.catalog_cid}),
          bindingCid: cid({version: 'actql-identifier-fixture-binding/0.1',
            contextCid: authorization.context.contextCid, catalogCid: current.catalog_cid}),
          limits: {maxPages: 1, maxPageBytes: 4096, maxPageRows: 4, maxCaptureRows: 4},
          readPages: createIdentifierPageDriver(observations, rows)});
      } catch (cause) {
        throw await helpers.retainInstalledHostInitializationFailure(cause,
          {sourceProfile: observedSite});
      }
    },
  };
  const connectorTable = createInstalledConnectorTable([{name: registration,
    registration, revision, source: {profileVersion: version, load: async () => module}}]);
  return {connectorTable, sourceProfilePath, observations, prepareCase: value => rows.prepare(value)};
}
