// Trusted test-only installation. All execution, admission, capture and
// cleanup remain in the installed product's existing RowSource/Run owners.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {compositeVectorRows, compositeVectorSchema, compositeVectorFacts} from './composite-vector-source-input.mjs';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const registration = 'composite_fixture';
const revision = 'composite_fixture/0.1';
const version = 'actql-installed-composite-vector-fixture/0.1';
// The checked machine contract retains the authored fields and the normative
// fixed f32 member, as in the existing Vector scalar Source installation.
// This is declaration input, never an observed or product-generated schema.
const checkedSchema = {...compositeVectorSchema,
  embedding: {...compositeVectorSchema.embedding, element_type: 'f32'}};
export const compositeVectorSchemaWire = canonical(checkedSchema);
export const compositeVectorSchemaCid = cid(checkedSchema);
export const compositeVectorFactsWire = canonical(compositeVectorFacts);
export const compositeVectorFactsCid = cid(compositeVectorFacts);
const resources = ['queries', 'candidates'];
export const compositeVectorViewSpecification = Object.freeze({views: Object.freeze(resources.map(resource => Object.freeze({
  resource, resource_kind: 'table', schema_wire: compositeVectorSchemaWire,
  schema_cid: compositeVectorSchemaCid, facts_wire: compositeVectorFactsWire,
})))});
export const compositeVectorReadOperations = Object.freeze(Object.fromEntries(
  resources.map(resource => [resource, `composite_fixture:${resource}:read`])));

export function createCompositeVectorPageDriver(observations) {
  return async ({resource, columns, requestWire, operation: selectedOperation,
    signal, authorizationFor, chargePage, consumePage}) => {
    signal?.throwIfAborted();
    assert.ok(resources.includes(resource));
    assert.equal(selectedOperation, compositeVectorReadOperations[resource]);
    assert.deepEqual(JSON.parse(requestWire), {});
    // Send the original complete schema before filter or projection. The existing
    // Source key/Vector admission owners validate the declared values.
    assert.ok(Array.isArray(columns));
    assert.deepEqual([...columns].sort(), ['a', 'b', 'embedding']);
    await authorizationFor(0);
    signal?.throwIfAborted();
    observations.sourceReadSessions++;
    observations.sourceReads++;
    observations.sourceIo++;
    observations.sourceReadCommands.push({resource, columns: [...columns], requestWire});
    const rows = compositeVectorRows[resource].map(row => Object.fromEntries(
      columns.map(name => [name, structuredClone(row[name])])));
    const charge = chargePage(Buffer.from(JSON.stringify(rows)));
    await consumePage(rows, {charge});
    observations.acceptedPages++;
  };
}

export async function installCompositeVectorFixture({moon, helpers,
  createInstalledConnectorTable, directory}) {
  assert.deepEqual(JSON.parse(compositeVectorSchemaWire), checkedSchema);
  await mkdir(directory, {recursive: true});
  const declaration = helpers.checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    registration, registration, revision, JSON.stringify(compositeVectorViewSpecification), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const bodies = declared.view_bodies.map(wire => JSON.parse(wire));
  const queryAliases = resources.map((resource, index) => {
    const selected = declared.views.find(view => view.resource === resource);
    assert.ok(selected);
    const view = bodies.find(body => body.contract_cid === selected.view_cid);
    assert.ok(view);
    return {name: index === 0 ? 'queries' : 'candidates', sourceRef: selected.source_ref,
      sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid};
  });
  const accountConfigurationWire = canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'composite-vector-fixture',
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
    identityParts: profile => [profile, compositeVectorViewSpecification],
    async load(profile, {root, principalId, moon: installedMoon,
      baseEnvironmentWire, runtimeBundleCid}) {
      check(profile);
      const restored = helpers.checked(installedMoon.clientProgramRowSourceRestoreRelationDeclaration(
        registration, registration, revision, JSON.stringify(compositeVectorViewSpecification), declared.catalog_cid));
      const current = JSON.parse(installedMoon.clientProgramRowSourceDeclarationJson(restored));
      const environment = helpers.rowSourceCheckEnvironment(baseEnvironmentWire, current);
      const authorization = await helpers.installRowSourceAuthorization({
        accountConfiguration: accountConfigurationWire, principalId, root,
        connectorRegistration: registration});
      const siteDirectory = join(root, 'composite-vector-fixture-site');
      await mkdir(siteDirectory, {recursive: true});
      const credentialPrivateKeyPath = join(siteDirectory, 'credential.pem');
      const keys = generateKeyPairSync('ed25519');
      await writeFile(credentialPrivateKeyPath,
        keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {flag: 'wx', mode: 0o600});
      const site = await helpers.openRowSourceCredentialSite({
        profile: {resourceOrigin: 'https://composite.fixture.invalid', namespaceId: 'vectors',
          environment: 'fixture', siteKey: 'vectors', siteGeneration: 1,
          credentialAuthorityId: 'composite-vector-fixture', credentialKeyId: 'fixture',
          credentialPrivateKeyPath, journalRoot: join(siteDirectory, 'journal')},
        principalId, authorization, connection: 'composite_fixture:vectors',
        connectorRegistration: registration, connectorRevision: revision,
        runtimeBundleCid, commonMoon: installedMoon,
        resolveSecret: async () => { throw new Error('CompositeVectorFixtureHasNoRemoteSecret'); },
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
          readOperation: compositeVectorReadOperations,
          physicalTarget: (resource, fields) => ({resource, fields: [...fields], catalog_cid: current.catalog_cid}),
          bindingCid: cid({version: 'actql-composite-vector-fixture-binding/0.1',
            contextCid: authorization.context.contextCid, catalogCid: current.catalog_cid}),
          limits: {maxPages: 1, maxPageBytes: 4096, maxPageRows: 3, maxCaptureRows: 3},
          readPages: createCompositeVectorPageDriver(observations)});
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
