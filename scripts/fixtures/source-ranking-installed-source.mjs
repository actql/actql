// Trusted test-only installation. All execution, admission, capture and
// cleanup remain in the installed product's existing RowSource/Run owners.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {sourceRankingRows, sourceRankingSchema} from './source-ranking-public-input.mjs';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const registration = 'score_fixture';
const revision = 'score_fixture/0.1';
const version = 'actql-installed-score-fixture/0.1';
// Independent authored Number schema and semantic facts; never output-derived.
export const sourceRankingSchemaWire = '{"id":{"nullable":false,"type":"number"},"s":{"nullable":false,"type":"number"}}';
export const sourceRankingSchemaCid = 'sha256:fdba6c82573c5300c291282e13cea75bfea308d5bb74da40b9caaae012ab06d7';
export const sourceRankingFactsWire = '{"relation_keys":{"candidate_keys":[["id"]]},"relation_scores":{"s":{"domain":"Relevance","normalization":"Identity","range":[0,1]}}}';
export const sourceRankingFactsCid = 'sha256:a261bd122e81c9c3e3f1bb638782d50c3f014b746ec64da74b2871e1110c89ce';
const resources = ['left', 'right'];
export const sourceRankingViewSpecification = Object.freeze({views: Object.freeze(resources.map(resource => Object.freeze({
  resource, resource_kind: 'table', schema_wire: sourceRankingSchemaWire,
  schema_cid: sourceRankingSchemaCid, facts_wire: sourceRankingFactsWire,
})))});
export const sourceRankingReadOperations = Object.freeze(Object.fromEntries(
  resources.map(resource => [resource, `score_fixture:${resource}:read`])));

export function createSourceRankingPageDriver(observations) {
  return async ({resource, columns, requestWire, operation: selectedOperation,
    signal, authorizationFor, chargePage, consumePage}) => {
    signal?.throwIfAborted();
    assert.ok(resources.includes(resource));
    assert.equal(selectedOperation, sourceRankingReadOperations[resource]);
    assert.deepEqual(JSON.parse(requestWire), {});
    // The original input schema is validated before filter/projection. Missing
    // declared scores cannot be rescued by a supplier changing the request.
    assert.ok(Array.isArray(columns));
    assert.deepEqual([...columns].sort(), ['id', 's']);
    await authorizationFor(0);
    signal?.throwIfAborted();
    observations.sourceReadSessions++;
    observations.sourceReads++;
    observations.sourceIo++;
    observations.sourceReadCommands.push({resource, columns: [...columns], requestWire});
    const rows = sourceRankingRows[resource].map(row => Object.fromEntries(
      columns.map(name => [name, row[name]])));
    const charge = chargePage(Buffer.from(JSON.stringify(rows)));
    await consumePage(rows, {charge});
    observations.acceptedPages++;
  };
}

export async function installSourceRankingFixture({moon, helpers,
  createInstalledConnectorTable, directory}) {
  assert.deepEqual(JSON.parse(sourceRankingSchemaWire), sourceRankingSchema);
  await mkdir(directory, {recursive: true});
  const declaration = helpers.checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    registration, registration, revision, JSON.stringify(sourceRankingViewSpecification), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const bodies = declared.view_bodies.map(wire => JSON.parse(wire));
  const queryAliases = resources.map((resource, index) => {
    const selected = declared.views.find(view => view.resource === resource);
    assert.ok(selected);
    const view = bodies.find(body => body.contract_cid === selected.view_cid);
    assert.ok(view);
    return {name: index === 0 ? 'l' : 'r', sourceRef: selected.source_ref,
      sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid};
  });
  const accountConfigurationWire = canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'score-fixture',
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
    identityParts: profile => [profile, sourceRankingViewSpecification],
    async load(profile, {root, principalId, moon: installedMoon,
      baseEnvironmentWire, runtimeBundleCid}) {
      check(profile);
      const restored = helpers.checked(installedMoon.clientProgramRowSourceRestoreRelationDeclaration(
        registration, registration, revision, JSON.stringify(sourceRankingViewSpecification), declared.catalog_cid));
      const current = JSON.parse(installedMoon.clientProgramRowSourceDeclarationJson(restored));
      const environment = helpers.rowSourceCheckEnvironment(baseEnvironmentWire, current);
      const authorization = await helpers.installRowSourceAuthorization({
        accountConfiguration: accountConfigurationWire, principalId, root,
        connectorRegistration: registration});
      const siteDirectory = join(root, 'score-fixture-site');
      await mkdir(siteDirectory, {recursive: true});
      const credentialPrivateKeyPath = join(siteDirectory, 'credential.pem');
      const keys = generateKeyPairSync('ed25519');
      await writeFile(credentialPrivateKeyPath,
        keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {flag: 'wx', mode: 0o600});
      const site = await helpers.openRowSourceCredentialSite({
        profile: {resourceOrigin: 'https://score.fixture.invalid', namespaceId: 'scores',
          environment: 'fixture', siteKey: 'scores', siteGeneration: 1,
          credentialAuthorityId: 'score-fixture', credentialKeyId: 'fixture',
          credentialPrivateKeyPath, journalRoot: join(siteDirectory, 'journal')},
        principalId, authorization, connection: 'score_fixture:scores',
        connectorRegistration: registration, connectorRevision: revision,
        runtimeBundleCid, commonMoon: installedMoon,
        resolveSecret: async () => { throw new Error('ScoreFixtureHasNoRemoteSecret'); },
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
          readOperation: sourceRankingReadOperations,
          physicalTarget: (resource, fields) => ({resource, fields: [...fields], catalog_cid: current.catalog_cid}),
          bindingCid: cid({version: 'actql-score-fixture-binding/0.1',
            contextCid: authorization.context.contextCid, catalogCid: current.catalog_cid}),
          limits: {maxPages: 1, maxPageBytes: 4096, maxPageRows: 3, maxCaptureRows: 3},
          readPages: createSourceRankingPageDriver(observations)});
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
