// Shared private setup only. Actual providers and all original Owners remain real.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {loadInstalledSource} from '../../../host-node/installed-source.mjs';
import {createInstalledLoaderParent} from '../../../host-node/fixtures/installed-loader-parent.fixture.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {snowflakeFixture, metadataBody, readLimits} from './snowflake-read.fixture.mjs';
const runtimeUrl = new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const baseEnvironmentWire = (await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8')).trimEnd();

export async function installedSnowflakeFixture(t) {
  let transportClose, parent;
  const captures = [];
  t.after(async () => {
    const failures = [];
    try {
      for (const captured of captures) await captured.close();
      await parent?.close();
    } catch (error) {failures.push(error);}
    try {await transportClose?.();} catch (error) {failures.push(error);}
    if (failures.length) throw new AggregateError(failures, 'InstalledSnowflakeFixtureCleanupPending');
  });
  const f = await snowflakeFixture({diagnostic: (...args) => t.diagnostic(...args),
    after(close) {assert.equal(transportClose, undefined); transportClose = close;}});
  parent = createInstalledLoaderParent({root: f.root, principalId: 'operator', moon: f.moon});
  parent.open();
  const keys = generateKeyPairSync('ed25519');
  const keyPath = join(f.root, 'installed-credential.key');
  await writeFile(keyPath, keys.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
  const site = {version: 'actql-installed-snowflake-site/0.1',
    apiOrigin: f.scope.resourceOrigin, warehouse: 'ANALYTICS', role: 'READER',
    authenticationType: 'OAUTH', credentialAuthorityId: 'installed-fixture',
    credentialKeyId: 'key', credentialPrivateKeyPath: keyPath, environment: 'test',
    journalRoot: join(f.root, 'installed-journal'), namespaceId: 'installed-fixture',
    siteGeneration: 1, siteKey: 'installed-site', tokenEnvironment: 'ACTQL_SNOWFLAKE_TEST_TOKEN',
    caPath: join(f.root, 'server.crt')};
  const siteProfilePath = join(f.root, 'installed-site.json');
  await writeFile(siteProfilePath, JSON.stringify(site));
  const metadata = {version: 'actql-snowflake-read-metadata/0.1', connectorId: 'snowflake',
    resource: 'usage_30d', database: 'PRODUCT', schema: 'USAGE', table: 'USAGE_30D',
    apiOrigin: site.apiOrigin, bodies: [metadataBody().toString('base64')]};
  const metadataPath = join(f.root, 'installed-metadata.json');
  await writeFile(metadataPath, JSON.stringify(metadata));
  const account = outcome => canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'installed-fixture', entries: [{entry_id: 'table-read', outcome,
      principal: {all: true}, connection: {any_of: ['snowflake:snowflake']},
      resource: {any_of: ['usage_30d']}, operation: {any_of: ['read']}, exclusions: []}]});
  // Explicit private units. They select this fixture's original Host ledger;
  // they are not normal product funding or an increase of the driver limits.
  const profile = {version: 'actql-installed-snowflake-source/0.1', connectorId: 'snowflake',
    resource: 'usage_30d', database: 'PRODUCT', schema: 'USAGE', table: 'USAGE_30D',
    metadataPath, siteProfilePath, accountConfigurationWire: account('allow'),
    limits: {...readLimits, maxRows: 3, maxTotalRows: 3,
      maxDescriptionBytes: 4096, maxDeclarationBytes: 200000, maxDeclarationNodes: 20000}};
  const path = join(f.root, 'installed-source.json');
  await writeFile(path, JSON.stringify(profile));
  const load = (overrides = {}) => parent.load(loadInstalledSource, path,
    {root: f.root, principalId: 'operator', moon: f.moon, runtimeUrl, baseEnvironmentWire,
      resolveSecret: f.options.credential.resolveSecret, ...overrides});
  const preparation = {preparedProgram: f.row.originals.program,
    ...Object.fromEntries(['registry', 'values', 'fragment', 'ordered'].map(k => [k, f.row.originals[k]]))};
  const prepare = source => source.prepare(preparation);
  return {...f, site, siteProfilePath, metadata, metadataPath, account, profile, path,
    load, prepare, preparation, captures, installationServices: parent.services};
}
