// Trusted test-only installation. All execution, admission, capture and
// cleanup remain in the installed product's existing RowSource/Run owners.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {vectorScalarSourceRows, vectorScalarSourceSchema} from
  './vector-scalar-source-input.mjs';

const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
const registration = 'vector_fixture';
const revision = 'vector_fixture/0.1';
const operation = 'vector_fixture:vectors:read';
const version = 'actql-installed-vector-fixture/0.1';
// Checked Source schema, independently encoded from the original authored
// schema and its normative fixed f32 machine member (language.md, Value types).
// Neither an observed declaration nor a product-generated expected schema.
export const vectorScalarSchemaWire = '{"id":{"nullable":false,"type":"number"},"left_vector":{"dimensions":2,"element_type":"f32","nullable":false,"type":"vector"},"right_vector":{"dimensions":2,"element_type":"f32","nullable":true,"type":"vector"}}';
export const vectorScalarSchemaCid = 'sha256:6d31ea776fe51f6447312c10f7f575b97d3c5a3fe88c27d4c1fe105a1d564849';
// This trusted fixture owns the complete original three-row extent. Declare
// its real id guarantee in the SourceView facts, then let the common capture
// input validator check it; observed rows never grant key evidence themselves.
export const vectorScalarFactsWire = '{"relation_keys":{"candidate_keys":[["id"]]}}';
export const vectorScalarFactsCid = 'sha256:38ffc0cad6baa7699f2ed6b40426b522df5bc7dd9dc369024d278f70a1d29209';
export const vectorScalarViewSpecification = Object.freeze({views: [{
  resource: 'vectors', resource_kind: 'table',
  schema_wire: vectorScalarSchemaWire, schema_cid: vectorScalarSchemaCid,
  facts_wire: vectorScalarFactsWire,
}]});

export function createVectorScalarPageDriver(observations) {
  return async ({resource, columns, requestWire, operation: selectedOperation,
    signal, authorizationFor, chargePage, consumePage}) => {
    signal?.throwIfAborted();
    assert.equal(resource, 'vectors');
    assert.equal(selectedOperation, operation);
    // The declaration has an empty Request contract and projection-only
    // pushdown. Predicate/order/limit remain in the common residual Program.
    assert.deepEqual(JSON.parse(requestWire), {});
    assert.ok(Array.isArray(columns) && columns.length > 0);
    assert.equal(new Set(columns).size, columns.length);
    for (const name of columns) assert.ok(Object.hasOwn(vectorScalarSourceSchema, name));
    await authorizationFor(0);
    signal?.throwIfAborted();
    observations.sourceReadSessions++;
    observations.sourceReads++;
    observations.sourceIo++;
    observations.sourceReadCommands.push({resource, columns: [...columns], requestWire});
    // One physical page of the original three rows. Selecting declared
    // columns is transport projection, never a Vector cast or evaluation.
    const rows = vectorScalarSourceRows.map(row => Object.fromEntries(
      columns.map(name => [name, structuredClone(row[name])])));
    const bytes = Buffer.from(JSON.stringify(rows));
    const charge = chargePage(bytes);
    await consumePage(rows, {charge});
    observations.acceptedPages++;
  };
}

export async function installVectorScalarFixture({moon, helpers,
  createInstalledConnectorTable, directory}) {
  assert.deepEqual(JSON.parse(vectorScalarSchemaWire), {
    ...vectorScalarSourceSchema,
    left_vector: {...vectorScalarSourceSchema.left_vector, element_type: 'f32'},
    right_vector: {...vectorScalarSourceSchema.right_vector, element_type: 'f32'},
  });
  await mkdir(directory, {recursive: true});
  const declaration = helpers.checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    registration, registration, revision, JSON.stringify(vectorScalarViewSpecification), undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const view = JSON.parse(declared.view_bodies[0]);
  const accountConfigurationWire = canonical({
    version: 'actql-execution-account-config/0.1', account_id: 'vector-fixture',
    entries: [{entry_id: 'read', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true},
      operation: {any_of: ['read']}, exclusions: []}],
  });
  const sourceProfilePath = join(directory, 'source-profile.json');
  await writeFile(sourceProfilePath, canonical({version, connectorId: registration,
    accountConfigurationWire, queryAliases: [{name: 'vectors', sourceRef: declared.views[0].source_ref,
      sourceViewContractCid: view.contract_cid, schemaContractCid: view.output.schema.cid}]}), {flag: 'wx'});
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
    identityParts: profile => [profile, vectorScalarViewSpecification],
    async load(profile, {root, principalId, moon: installedMoon,
      baseEnvironmentWire, runtimeBundleCid}) {
      check(profile);
      const restored = helpers.checked(installedMoon.clientProgramRowSourceRestoreRelationDeclaration(
        registration, registration, revision, JSON.stringify(vectorScalarViewSpecification), declared.catalog_cid));
      const current = JSON.parse(installedMoon.clientProgramRowSourceDeclarationJson(restored));
      const environment = helpers.rowSourceCheckEnvironment(baseEnvironmentWire, current);
      const authorization = await helpers.installRowSourceAuthorization({
        accountConfiguration: accountConfigurationWire, principalId, root,
        connectorRegistration: registration});
      const siteDirectory = join(root, 'vector-fixture-site');
      await mkdir(siteDirectory, {recursive: true});
      const credentialPrivateKeyPath = join(siteDirectory, 'credential.pem');
      const keys = generateKeyPairSync('ed25519');
      await writeFile(credentialPrivateKeyPath,
        keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {flag: 'wx', mode: 0o600});
      const site = await helpers.openRowSourceCredentialSite({
        profile: {resourceOrigin: 'https://vector.fixture.invalid', namespaceId: 'vectors',
          environment: 'fixture', siteKey: 'vectors', siteGeneration: 1,
          credentialAuthorityId: 'vector-fixture', credentialKeyId: 'fixture',
          credentialPrivateKeyPath, journalRoot: join(siteDirectory, 'journal')},
        principalId, authorization, connection: 'vector_fixture:vectors',
        connectorRegistration: registration, connectorRevision: revision,
        runtimeBundleCid, commonMoon: installedMoon,
        resolveSecret: async () => { throw new Error('VectorFixtureHasNoRemoteSecret'); },
        admitsApprovalTarget: binding => binding?.catalog_cid === current.catalog_cid &&
          binding?.resource === 'vectors',
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
          readOperation: operation,
          physicalTarget: (resource, fields) => ({resource, fields: [...fields], catalog_cid: current.catalog_cid}),
          bindingCid: cid({version: 'actql-vector-fixture-binding/0.1',
            contextCid: authorization.context.contextCid, catalogCid: current.catalog_cid}),
          limits: {maxPages: 1, maxPageBytes: 4096, maxPageRows: 3, maxCaptureRows: 3},
          readPages: createVectorScalarPageDriver(observations)});
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
