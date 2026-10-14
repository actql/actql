// Trusted test-only installation. All execution, admission, capture and
// cleanup remain in the installed product's existing RowSource/Run owners.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {windowGroupSourceRows} from './window-group-source-input.mjs';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const connectorId = 'crm/main';
const registration = 'window_fixture';
const revision = 'window_fixture/0.1';
const version = 'actql-installed-window-fixture/0.1';
// The original Source has duplicate ids and nullable amounts. It has no
// candidate-key or score guarantee; window grouping owns the resulting keys.
export const windowGroupSchemaWire = '{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}}';
export const windowGroupSchemaCid = cid(JSON.parse(windowGroupSchemaWire));
export const windowGroupViewSpecification = Object.freeze({views: Object.freeze([Object.freeze({
  resource: 'r', resource_kind: 'table', schema_wire: windowGroupSchemaWire,
  schema_cid: windowGroupSchemaCid,
})])});
export const windowGroupReadOperations = Object.freeze({r: 'window_fixture:r:read'});

export function createWindowGroupRows() {
  let current = structuredClone(windowGroupSourceRows);
  return {
    read: () => structuredClone(current),
    prepare(rows = windowGroupSourceRows) {
      assert.ok(Array.isArray(rows));
      if (rows.length !== 0) assert.deepEqual(rows, windowGroupSourceRows);
      current = structuredClone(rows);
    },
  };
}

export function createWindowGroupPageDriver(observations, rows) {
  return async ({resource, columns, requestWire, operation: selectedOperation,
    signal, authorizationFor, chargePage, consumePage}) => {
    signal?.throwIfAborted();
    assert.equal(resource, 'r');
    assert.equal(selectedOperation, windowGroupReadOperations[resource]);
    assert.deepEqual(JSON.parse(requestWire), {});
    // Projection is transport-only. Predicate and aggregation remain in the
    // original common Program; the supplier never filters or deduplicates.
    assert.ok(Array.isArray(columns));
    assert.deepEqual([...columns].sort(), ['amount', 'id']);
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

export async function installWindowGroupFixture({moon, helpers,
  createInstalledConnectorTable, directory}) {
  const rows = createWindowGroupRows();
  await mkdir(directory, {recursive: true});
  const declaration = helpers.checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    connectorId, registration, revision, JSON.stringify(windowGroupViewSpecification), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const bodies = declared.view_bodies.map(wire => JSON.parse(wire));
  const selected = declared.views.find(view => view.resource === 'r');
  assert.ok(selected);
  const view = bodies.find(body => body.contract_cid === selected.view_cid);
  assert.ok(view);
  const queryAliases = [{name: 'records', sourceRef: selected.source_ref,
    sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid}];
  const accountConfigurationWire = canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'window-fixture',
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
    identityParts: profile => [profile, windowGroupViewSpecification],
    async load(profile, {root, principalId, moon: installedMoon,
      baseEnvironmentWire, runtimeBundleCid}) {
      check(profile);
      const restored = helpers.checked(installedMoon.clientProgramRowSourceRestoreRelationDeclaration(
        connectorId, registration, revision, JSON.stringify(windowGroupViewSpecification), declared.catalog_cid));
      const current = JSON.parse(installedMoon.clientProgramRowSourceDeclarationJson(restored));
      const environment = helpers.rowSourceCheckEnvironment(baseEnvironmentWire, current);
      const authorization = await helpers.installRowSourceAuthorization({
        accountConfiguration: accountConfigurationWire, principalId, root,
        connectorRegistration: registration});
      const siteDirectory = join(root, 'window-fixture-site');
      await mkdir(siteDirectory, {recursive: true});
      const credentialPrivateKeyPath = join(siteDirectory, 'credential.pem');
      const keys = generateKeyPairSync('ed25519');
      await writeFile(credentialPrivateKeyPath,
        keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {flag: 'wx', mode: 0o600});
      const site = await helpers.openRowSourceCredentialSite({
        profile: {resourceOrigin: 'https://window.fixture.invalid', namespaceId: 'windows',
          environment: 'fixture', siteKey: 'windows', siteGeneration: 1,
          credentialAuthorityId: 'window-fixture', credentialKeyId: 'fixture',
          credentialPrivateKeyPath, journalRoot: join(siteDirectory, 'journal')},
        principalId, authorization, connection: 'window_fixture:rows',
        connectorRegistration: registration, connectorRevision: revision,
        runtimeBundleCid, commonMoon: installedMoon,
        resolveSecret: async () => { throw new Error('WindowFixtureHasNoRemoteSecret'); },
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
          readOperation: windowGroupReadOperations,
          physicalTarget: (resource, fields) => ({resource, fields: [...fields], catalog_cid: current.catalog_cid}),
          bindingCid: cid({version: 'actql-window-fixture-binding/0.1',
            contextCid: authorization.context.contextCid, catalogCid: current.catalog_cid}),
          limits: {maxPages: 1, maxPageBytes: 4096, maxPageRows: 4, maxCaptureRows: 4},
          readPages: createWindowGroupPageDriver(observations, rows)});
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
