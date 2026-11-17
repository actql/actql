import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {assertRetainedRelationSnapshots} from './fixtures/retained-relation-snapshot.mjs';
import {windowGroupSourceSuccesses} from '../../scripts/fixtures/window-group-source-input.mjs';
import {configurePublicQueryEvidenceContracts} from '../../scripts/fixtures/public-query-cases.mjs';
const sourceRoot = fileURLToPath(new URL('../../', import.meta.url));
const {DuckDBInstance} = createRequire(join(sourceRoot, 'adapters/connectors/duckdb/node/package.json'))('@duckdb/node-api');

test('public window expression filter distinct fits the original budget and reclaims its snapshot',
  {timeout: 45_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-window-startup-'));
    let client;
    t.after(async () => {await client?.close(); await rm(directory, {recursive: true, force: true});});
    const fixture = windowGroupSourceSuccesses.find(item =>
      item.name === 'window-group-json-expression-filter-distinct');
    const database = join(directory, 'source.duckdb');
    const instance = await DuckDBInstance.create(database);
    const connection = await instance.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
      for (const row of fixture.sourceRows) await connection.run(
        'INSERT INTO records VALUES (?, ?)', [row.id, row.amount]);
    } finally {connection.closeSync(); instance.closeSync();}
    const environment = JSON.parse(await readFile(join(sourceRoot,
      'adapters/host-node/fixtures/query-amount-environment.json'), 'utf8'));
    const base = JSON.parse(await readFile(join(sourceRoot, 'spec/local-check-environment.json'), 'utf8'));
    const hostCapacityPolicy = base.host_policy_profile.capacity;
    environment.host_policy_profile = {...base.host_policy_profile, capacity: hostCapacityPolicy};
    configurePublicQueryEvidenceContracts(environment);
    delete environment.evidence_bundle_cid;
    environment.evidence_bundle_cid = 'sha256:' + createHash('sha256')
      .update(canonicalJson(environment)).digest('hex');
    const keys = generateKeyPairSync('ed25519');
    const observations = [];
    const authorization = {
      accountConfiguration: JSON.stringify({account_id: 'window-startup', entries: [{
        connection: {all: true}, entry_id: 'allow', exclusions: [], operation: {all: true},
        outcome: 'allow', principal: {all: true}, resource: {all: true}}],
      version: 'actql-execution-account-config/0.1'}),
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      observe(event, detail) {observations.push({event, detail});},
    };
    const sourceProfilePath = join(directory, 'source-profile.json');
    const view = environment.source_views[0];
    await writeFile(sourceProfilePath, canonicalJson({
      acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
      version: 'actql-installed-duckdb-source/0.1', database, schema: 'main', table: 'records',
      sourceRef: 'connector://crm/main/r#v', queryAliases: [{name: 'records',
        sourceRef: 'connector://crm/main/r#v', sourceViewContractCid: view.contract_cid,
        schemaContractCid: view.output.schema.cid}], checkEnvironmentWire: canonicalJson(environment),
      accountConfigurationWire: authorization.accountConfiguration,
    }));
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory: join(directory, 'state'), authorization,
        sourceProfilePath, hostCapacityPolicy}});
    const execution = await client.startSource(fixture.text,
      {format: fixture.format, submissionRef: client.newSubmission({nonce: 'original-window-expression'})});
    const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
    assert.equal(state.status, 'succeeded', JSON.stringify({state, observations}));
    assert.deepEqual(await execution.result('answer').all(), fixture.results.answer.rows);
    const captures = observations.filter(item => item.event === 'acquisition_completed');
    assert.equal(captures.length, 1);
    assert.equal(captures[0].detail.acquisition.observation.output.row_count, fixture.sourceRows.length);
    const computed = observations.filter(item => item.event === 'computed');
    assert.equal(computed.length, 1);
    assertRetainedRelationSnapshots(computed[0].detail.relationSnapshots, fixture.results.answer.rows);
    const cleanups = observations.filter(item => item.event === 'dispatch_cleanup_completed');
    assert.equal(cleanups.length, 1);
    for (const dimension of ['holdings', 'liveReservations', 'liveDelegations', 'heldBytes',
      'reservedRetentionBytes', 'reservedExecutionBytes']) {
      assert.equal(cleanups[0].detail.resourceUsage[dimension], '0');
    }
  });
