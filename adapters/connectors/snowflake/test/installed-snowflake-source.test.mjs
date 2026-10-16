import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {gzipSync} from 'node:zlib';
import {loadInstalledSource, installedSourceIdentity} from '../../../host-node/installed-source.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {snowflakeFixture, metadataBody, pending, resultBody, decimal38,
  readLimits} from './snowflake-read.fixture.mjs';

const runtimeUrl = new URL('../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const baseEnvironmentWire = await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');

async function fixture(t) {
  const f = await snowflakeFixture(t);
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
  const sources = [], captures = [];
  t.after(async () => {
    for (const captured of captures) await captured.close();
    for (const source of sources) await source.close();
  });
  const load = async () => {
    const source = await loadInstalledSource(path, {root: f.root, principalId: 'operator',
      moon: f.moon, runtimeUrl, baseEnvironmentWire,
      resolveSecret: f.options.credential.resolveSecret});
    sources.push(source); return source;
  };
  const preparation = {preparedProgram: f.row.originals.program,
    ...Object.fromEntries(['registry', 'values', 'fragment', 'ordered'].map(k => [k, f.row.originals[k]]))};
  const prepare = source => source.prepare(preparation);
  return {...f, site, siteProfilePath, metadata, metadataPath, account, profile, path,
    load, prepare, preparation, captures};
}

test('standard Snowflake table selects its real installation without credential or Provider I/O', async t => {
  const f = await fixture(t), source = await f.load();
  assert.equal(source.connectorRegistration, 'snowflake');
  assert.equal(source.connectorRevision, 'snowflake/0.1');
  assert.equal(source.sourceReadAccesses[0].connection, 'snowflake:snowflake');
  const prepared = await f.prepare(source);
  assert.ok(prepared.checkedSource);
  assert.equal(f.state.resolutions, 0); assert.equal(f.state.requests.length, 0);
  assert.ok(JSON.stringify(JSON.parse(source.environmentWire).contract_registry).includes('decimal'));
});

test('standard installed Host drives the original 202, gzip status and partition through capture', async t => {
  const f = await fixture(t), source = await f.load();
  const handle = 'installed-original';
  const bodies = [pending(handle), gzipSync(resultBody({handle, parts: [1, 1],
    rows: [['a1', decimal38, 'down']]})), gzipSync(Buffer.from('{"data":[["a2","0",null]]}'))];
  f.state.onRequest = () => {
    const n = f.state.requests.length - 1;
    return {status: n === 0 ? 202 : 200, body: bodies[n],
      headers: n === 0 ? {} : {'content-encoding': 'gzip'}};
  };
  const ledger = checked(f.moon.clientProgramAcquisitionLedger(1, 1, 65536n, 100000000n, 100000000n, 0));
  const opened = await source.openCapture({...f.preparation,
    preparedSource: await f.prepare(source), ledger});
  f.captures.push(opened);
  const exported = checked(f.moon.clientProgramExportSourceCapture(opened.capture.source(),
    opened.requirement, 'installed-snowflake-read-test'));
  const rows = f.moon.clientProgramSourceCaptureExportRows(exported);
  assert.equal(rows.length, 2); assert.ok(rows[0].includes(decimal38)); assert.ok(rows[1].includes('null'));
  assert.deepEqual(f.state.requests.map(r => r.method), ['POST', 'GET', 'GET']);
  assert.match(f.state.requests[0].path, /^\/api\/v2\/statements\?requestId=[0-9a-f-]{36}$/u);
  assert.equal(f.state.requests[1].path, `/api/v2/statements/${handle}`);
  assert.equal(f.state.requests[2].path, `/api/v2/statements/${handle}?partition=1`);
  assert.equal(JSON.parse(f.state.requests[0].body).statement,
    'SELECT "ACCOUNT_ID","ACTIVE_USERS","TREND" FROM "PRODUCT"."USAGE"."USAGE_30D"');
  assert.equal(f.moon.clientProgramMultiCapturedLedgerUsage(ledger)[3],
    BigInt(bodies.reduce((n, b) => n + b.byteLength, 0)));
  await opened.close();
  assert.deepEqual(f.moon.clientProgramMultiCapturedLedgerUsage(ledger).slice(4, 8), [0n, 0n, 0n, 0n]);
});

test('installed metadata is scope-bound and cannot silently select another original table', async t => {
  const f = await fixture(t);
  await writeFile(f.metadataPath, JSON.stringify({...f.metadata, table: 'OTHER'}));
  await assert.rejects(f.load(), {code: 'InvalidInstalledSnowflakeMetadata'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('unknown Site fields and ambient-origin substitutions refuse before secret resolution', async t => {
  const f = await fixture(t);
  for (const changed of [{...f.site, ignored: true}, {...f.site, apiOrigin: `${f.site.apiOrigin}/other`}]) {
    await writeFile(f.siteProfilePath, JSON.stringify(changed));
    await assert.rejects(f.load(), {code: 'InvalidInstalledSnowflakeSite'});
  }
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('installed authority denial is not repaired by a valid metadata snapshot', async t => {
  const f = await fixture(t);
  await writeFile(f.path, JSON.stringify({...f.profile, accountConfigurationWire: f.account('deny')}));
  const source = await f.load();
  await assert.rejects(f.prepare(source), {code: 'ACTQL_E_ACCOUNT_DENIED'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('standard installed status refusal after 202 retains Unknown and the original handle', async t => {
  const f = await fixture(t), source = await f.load();
  f.state.onRequest = () => f.state.requests.length === 1
    ? {status: 202, body: pending('installed-pending-original')}
    : {status: 403, body: '{"message":"denied status"}'};
  const ledger = checked(f.moon.clientProgramAcquisitionLedger(1, 1, 65536n, 100000000n, 100000000n, 0));
  await assert.rejects(source.openCapture({...f.preparation, ledger}), error => {
    assert.equal(error.outcome, 'unknown');
    assert.equal(error.originalStatement.statementHandle, 'installed-pending-original');
    assert.equal(new URL(f.state.requests[0].path, f.site.apiOrigin).searchParams.get('requestId'),
      error.originalStatement.requestId);
    return true;
  });
  assert.deepEqual(f.state.requests.map(r => r.method), ['POST', 'GET']);
  assert.equal(f.state.requests[1].path, '/api/v2/statements/installed-pending-original');
  // Confirmed local cleanup is independent of the remote job's Unknown.
  assert.deepEqual(f.moon.clientProgramMultiCapturedLedgerUsage(ledger).slice(4, 8), [0n, 0n, 0n, 0n]);
});

test('same-shaped metadata from a foreign table is rejected by the actual Common description Owner', async t => {
  const f = await fixture(t);
  const bytes = Buffer.from(metadataBody().toString().replaceAll('USAGE_30D', 'OTHER_TABLE'));
  await writeFile(f.metadataPath, JSON.stringify({...f.metadata, bodies: [bytes.toString('base64')]}));
  await assert.rejects(f.load(), {code: 'MoonBitHostFailure'});
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('noncanonical or oversized stored metadata refuses before any Site opens', async t => {
  const f = await fixture(t);
  for (const body of [`${f.metadata.bodies[0]}\n`, Buffer.alloc(4097).toString('base64')]) {
    await writeFile(f.metadataPath, JSON.stringify({...f.metadata, bodies: [body]}));
    await assert.rejects(f.load(), {code: 'InvalidInstalledSnowflakeMetadata'});
  }
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});

test('installed generation, metadata and target identity change without any Provider probe', async t => {
  const f = await fixture(t), original = await installedSourceIdentity(f.path);
  await writeFile(f.siteProfilePath, JSON.stringify({...f.site, siteGeneration: 2}));
  assert.notEqual(await installedSourceIdentity(f.path), original);
  await writeFile(f.siteProfilePath, JSON.stringify(f.site));
  assert.equal(await installedSourceIdentity(f.path), original);
  await writeFile(f.metadataPath, JSON.stringify({...f.metadata,
    bodies: [metadataBody().toString('base64'), metadataBody().toString('base64')]}));
  assert.notEqual(await installedSourceIdentity(f.path), original);
  assert.equal(f.state.requests.length, 0); assert.equal(f.state.resolutions, 0);
});
