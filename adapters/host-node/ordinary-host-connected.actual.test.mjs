import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, writeFile, rename, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {prepareOrdinaryHostJournal} from './ordinary-host-journal.mjs';
import {initializeOrdinaryMockAccount} from './ordinary-mock-account.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';

// Actual Common/Host/SQLite/Store/crypto/FS, in a source checkout. This is not
// a packed public-facade qualification or a permission for a live provider.
test('ordinary actual Host SELECT all close reopen and independent instances without a preload', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-ordinary-host-'));
  const cwd = process.cwd(); let a, b;
  process.chdir(directory);
  try {
    a = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation: {directory: join(directory, 'a')}});
    b = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation: {directory: join(directory, 'b')}});
    assert.deepEqual(await a.sql('SELECT 1 AS id').all(), [{id: 1}]);
    assert.deepEqual(await a.sql('SELECT 2 AS id').all(), [{id: 2}]);
    await a.close(); a = undefined;
    assert.deepEqual(await b.sql('SELECT 3 AS id').all(), [{id: 3}]);
    a = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation: {directory: join(directory, 'a')}});
    assert.deepEqual(await a.sql('SELECT 4 AS id').all(), [{id: 4}]);
  } finally {try {await a?.close();} finally {try {await b?.close();} finally {process.chdir(cwd);}}}
});

async function accountFixture() {
  const root = await mkdtemp(join(tmpdir(), 'actql-ordinary-mock-account-'));
  const originals = {host: {}, installation: {root}, generation: {}, supplier() {}, moduleLifetime: import.meta};
  const journal = prepareOrdinaryHostJournal(originals);
  await journal.admitRootFormat(root);
  let store;
  return {root, journal, async adopt(binding) {
    await journal.openRequestJournal(join(root, 'requests'), {});
    store = await openLocalPublicationStore({directory: join(root, 'publication'),
      storeAuthorityCid: 'sha256:' + 'a'.repeat(64), capacityBytes: 536870912,
      maxObjectBytes: 10000000, maxObjects: 10000, maxContractNodes: 10000, maxContractDepth: 64,
      privateEvidenceKey: binding.evidenceKey.key}, runtimeCore(moon).publicationControl,
    undefined, undefined, journal.publicationOwnership());
    await binding.adoptStore(store);
  }, async close() {
    await journal.close(); await store?.close();
    assert.equal((await journal.close()).pending, false);
  }, options: {moon, root, principal: 'local-test',
    subject: {projectDirectory: root, backend: 'original-mock-test'},
    sources: [['salesforce', 'Account'], ['snowflake', 'usage_30d']], modelTasks: [],
    requestTarget: ['local-mock', 'installed-multi-acquired'], updateTarget: ['salesforce', 'Account'],
    explicitSelection: true, assertExclusiveCurrent: () => journal.assertInitializationCurrent()}};
}

test('ordinary actual Host serializes bounded CSV on its original Run and closes', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-ordinary-content-'));
  const cwd = process.cwd(); let client, primary;
  process.chdir(directory);
  try {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory: join(directory, 'host')}});
    const source = "SELECT 2 AS id, CAST(NULL AS FLOAT64) AS p\n" +
      "|> SERIALIZE FORMAT CSV PRESERVE ORDER OPTIONS (\n" +
      "     name = 'selected.csv', header = TRUE, null_marker = r'\\N',\n" +
      "     encoding = 'UTF-8', line_ending = 'CRLF', max_rows = 3, max_bytes = 128\n" +
      "   )\n|> RESULT file;";
    const execution = await client.startSource(source, {format: 'aql'});
    const state = await execution.wait();
    if (state.status !== 'succeeded') t.diagnostic(JSON.stringify({state}));
    assert.equal(state.status, 'succeeded');
    const rows = await execution.result('file').all();
    assert.equal(rows.length, 1);
    const row = rows[0];
    assert.deepEqual(Object.keys(row).sort(), ['content', 'media_type', 'name', 'row_count', 'size_bytes']);
    assert.equal(row.name, 'selected.csv');
    assert.equal(row.media_type, 'text/csv');
    assert.equal(row.row_count, 1);
    assert.equal(row.size_bytes, Buffer.byteLength('id,p\r\n2,\\N\r\n'));
    assert.equal(row.content.$actql_ref, 'content');
    assert.equal(row.content.media_type, 'text/csv');
    assert.equal(row.content.metadata.truncated, false);
    const expected = Buffer.from('id,p\r\n2,\\N\r\n');
    const contentHash = createHash('sha256').update(expected).digest('hex');
    assert.equal(row.content.metadata.content_cid, 'sha256:' + contentHash);
    assert.equal(row.content.metadata.issuer_evidence.issuer_kind, 'content_derivation');
    assert.equal(row.content.metadata.issuer_evidence.content_cid, 'sha256:' + contentHash);
    // Source-checkout physical observation, not a claim of a public Content
    // byte-reader API. The persisted original must match the promised bytes.
    assert.deepEqual(await readFile(join(directory, 'host', 'publication', 'objects', contentHash)), expected);
  } catch (error) {primary = error;}
  finally {
    try {await client?.close();}
    catch (error) {primary = primary === undefined ? error
      : new AggregateError([primary, error], 'Original Content execution and cleanup failed');}
    finally {process.chdir(cwd);}
  }
  if (primary !== undefined) throw primary;
});

test('ordinary actual Content reopens its saved Run and adopted key without generating again', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-ordinary-content-reopen-'));
  const cwd = process.cwd(), root = join(directory, 'host');
  let client, primary, savedKey;
  process.chdir(directory);
  try {
    const options = {mode: 'local', owner: 'local', installation: {directory: root}};
    client = await connectEmbeddedLocal(options);
    const keyPath = join(root, 'checkpoints', 'private-evidence.key');
    savedKey = await readFile(keyPath);
    assert.equal(savedKey.length, 32, 'ordinary initialization selects the real key before any query');
    await client.close(); client = undefined;
    client = await connectEmbeddedLocal(options);
    assert.deepEqual(await readFile(keyPath), savedKey, 'an unused Host reopen retains the same initial generation');
    const execution = await client.startSource("SELECT 2 AS id\n" +
      "|> SERIALIZE FORMAT CSV PRESERVE ORDER OPTIONS (name = 'saved.csv', " +
      "header = TRUE, null_marker = r'\\N', max_rows = 3, max_bytes = 128)\n|> RESULT file;", {format: 'aql'});
    const before = await execution.wait(); assert.equal(before.status, 'succeeded');
    const rows = await execution.result('file').all(), ref = structuredClone(execution.ref);
    assert.deepEqual(await readFile(keyPath), savedKey);
    const intent = await readFile(join(root, 'checkpoints', 'private-evidence-initialization.json'));
    const adopted = await readFile(join(root, 'checkpoints', 'private-evidence-adopted.json'));
    await client.close(); client = undefined;
    client = await connectEmbeddedLocal(options);
    const same = await client.attach(ref), after = await same.status();
    assert.equal(after.status, 'succeeded'); assert.equal(after.run_id, before.run_id);
    assert.deepEqual(await same.result('file').all(), rows);
    assert.deepEqual(await readFile(keyPath), savedKey);
    assert.deepEqual(await readFile(join(root, 'checkpoints', 'private-evidence-initialization.json')), intent);
    assert.deepEqual(await readFile(join(root, 'checkpoints', 'private-evidence-adopted.json')), adopted);
  } catch (error) {primary = error;}
  finally {
    savedKey?.fill(0);
    try {await client?.close();}
    catch (error) {primary = primary === undefined ? error
      : new AggregateError([primary, error], 'Saved Content read and cleanup failed');}
    finally {process.chdir(cwd);}
  }
  if (primary !== undefined) throw primary;
});

test('actual Common Mock profile creates real distinct purpose keys and respects current Deny on reopen', async () => {
  const f = await accountFixture();
  try {
    const first = await initializeOrdinaryMockAccount(f.options);
    await f.adopt(first);
    assert.equal(first.authorization.reviewers.length, 1);
    assert.notStrictEqual(first.reviewer.privateKey, first.authorization.hostKey.privateKey);
    assert.equal(first.evidenceKey.key.length, 32);
    const document = JSON.parse(await readFile(first.configurationPath, 'utf8'));
    assert.equal(document.entries.find(entry => entry.entry_id === 'mock-update').outcome, 'delegate');
    for (const entry of document.entries) entry.outcome = 'deny';
    await writeFile(first.configurationPath, canonicalJson(document));
    const reopened = await initializeOrdinaryMockAccount({...f.options, explicitSelection: false});
    assert.equal(reopened.reviewer.resource, first.reviewer.resource);
    assert.equal(reopened.configurationPath, first.configurationPath);
    assert.equal(JSON.parse(await readFile(first.configurationPath, 'utf8')).entries[0].outcome, 'deny');
    assert.equal((await stat(join(f.root, 'mock-account', 'reviewer.pem'))).mode & 0o777, 0o600);
    first.evidenceKey.key.fill(0); reopened.evidenceKey.key.fill(0);
  } finally {await f.close();}
});

test('actual Mock setup never treats absent consent or a missing adopted key as fresh authority', async () => {
  const f = await accountFixture();
  try {
    await assert.rejects(initializeOrdinaryMockAccount({...f.options, explicitSelection: false}),
      {code: 'LocalMockInitializationConsentRequired'});
    const first = await initializeOrdinaryMockAccount(f.options);
    await f.adopt(first);
    const path = join(f.root, 'mock-account', 'reviewer.pem');
    await rename(path, path + '.test-held');
    await assert.rejects(initializeOrdinaryMockAccount(f.options), {code: 'LocalMockAdoptedStateMissing'});
    await assert.rejects(stat(path), {code: 'ENOENT'});
    first.evidenceKey.key.fill(0);
  } finally {await f.close();}
});

test('actual Mock adopted Store cannot be recreated from surviving config or keys', async () => {
  const f = await accountFixture();
  try {
    const binding = await initializeOrdinaryMockAccount(f.options);
    await f.adopt(binding);
    const path = join(f.root, 'publication', 'store.json');
    await rename(path, path + '.test-held');
    await assert.rejects(initializeOrdinaryMockAccount(f.options), {code: 'LocalMockAdoptedStateMissing'});
    await assert.rejects(stat(path), {code: 'ENOENT'});
    binding.evidenceKey.key.fill(0);
  } finally {await f.close();}
});

test('ordinary actual Mock Host consumes the original Quickstart two-Source JOIN', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-ordinary-mock-join-'));
  const project = scaffoldProject(join(directory, 'project'), 'churn-risk-mock');
  const cwd = process.cwd(); let client;
  process.chdir(project.directory);
  try {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory: '.actql'}, profile: 'mock'});
    const source = await readFile('churn-risk.aql', 'utf8');
    const query = source.slice(0, source.indexOf('|> INFER')).trimEnd() + ';';
    // The original catalogue declares int64, whose schema-directed JSON wire
    // is canonical decimal String, not Number (language signed64-values).
    assert.deepEqual(await client.sql(query).all(), [
      {id: '001Acme', notes: 'Evaluating a competitor; usage down since June.', active_users: '4', trend: 'down'},
      {id: '001Globex', notes: 'Several support tickets about the new pricing.', active_users: '12', trend: 'flat'},
    ]);
  } finally {try {await client?.close();} finally {process.chdir(cwd);}}
});

test('ordinary actual Mock Host runs original Quickstart INFER without applying its Effect', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-ordinary-mock-infer-'));
  const project = scaffoldProject(join(directory, 'project'), 'churn-risk-mock');
  const cwd = process.cwd(); let client, primaryFailure;
  process.chdir(project.directory);
  try {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory: '.actql'}, profile: 'mock'});
    const source = await readFile('churn-risk.aql', 'utf8');
    const query = source.slice(0, source.indexOf('|> EFFECT')).trimEnd() + ';';
    assert.deepEqual(await client.sql(query).all(), [
      {id: '001Acme', notes: 'Evaluating a competitor; usage down since June.', active_users: '4', trend: 'down',
        risk: {input_key: {id: '001Acme'}, outcome: 'ok',
          value: {level: 'high', reason: 'falling usage and a competitor evaluation'}}},
      {id: '001Globex', notes: 'Several support tickets about the new pricing.', active_users: '12', trend: 'flat',
        risk: {input_key: {id: '001Globex'}, outcome: 'ok',
          value: {level: 'high', reason: 'support tickets about pricing'}}},
    ]);
    const original = JSON.parse(await readFile('mock/data.json', 'utf8'));
    assert.deepEqual(original.salesforce.Account.rows.map(row => row.Churn_Risk__c), ['low', 'medium']);
  } catch (error) {
    primaryFailure = error;
    throw error;
  } finally {
    try {await client?.close();}
    catch (cleanupFailure) {
      if (primaryFailure !== undefined) {
        // Both failures remain failures. Do not hide the first public
        // operation behind its independently pending physical cleanup.
        t.diagnostic(JSON.stringify({primaryCode: primaryFailure.code,
          primaryMessage: primaryFailure.message, cleanupCode: cleanupFailure.code,
          cleanupMessage: cleanupFailure.message}));
        throw new AggregateError([primaryFailure, cleanupFailure],
          'Original INFER failed and Host cleanup remains pending', {cause: primaryFailure});
      }
      throw cleanupFailure;
    } finally {process.chdir(cwd);}
  }
});

test('ordinary actual Mock Host captures the original Quickstart Effect without writing before approval', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-ordinary-mock-effect-'));
  const project = scaffoldProject(join(directory, 'project'), 'churn-risk-mock');
  const cwd = process.cwd(); let client, primaryFailure;
  t.diagnostic(JSON.stringify({project: project.directory}));
  process.chdir(project.directory);
  try {
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory: '.actql'}, profile: 'mock'});
    const before = await readFile('mock/data.json', 'utf8');
    const source = await readFile('churn-risk.aql', 'utf8');
    const execution = await client.startSource(source, {format: 'aql', stopBefore: 'commit'});
    const state = await execution.wait();
    t.diagnostic(JSON.stringify({ref: execution.ref, state}));
    assert.equal(state.status, 'waiting_checkpoint');
    assert.equal(typeof state.checkpoint?.id, 'string');
    assert.equal(await readFile('mock/data.json', 'utf8'), before);
    const page = await client.checkpoints({checkpointId: state.checkpoint.id});
    assert.equal(page.items.length, 1);
    assert.equal(page.items[0].checkpointCid, state.checkpoint.checkpoint_cid);
    const review = await client.reviewCheckpoint(page.items[0]);
    const body = JSON.parse(Buffer.from(review.bytes).toString('utf8'));
    assert.equal(body.version, 'actql-review-projection/0.1');
    assert.equal(body.displayed_rows.length, 2);
    assert.equal(body.encryption_required, true);
    assert.deepEqual(body.displayed_rows.map(row => row.target_row_identity).sort(), ['001Acme', '001Globex']);
    assert.equal(await readFile('mock/data.json', 'utf8'), before);
  } catch (error) {primaryFailure = error; throw error;}
  finally {
    try {await client?.close();}
    catch (cleanupFailure) {
      if (primaryFailure !== undefined) {
        t.diagnostic(JSON.stringify({primaryCode: primaryFailure.code, primaryMessage: primaryFailure.message,
          cleanupCode: cleanupFailure.code, cleanupMessage: cleanupFailure.message}));
        throw new AggregateError([primaryFailure, cleanupFailure],
          'Original Effect failed and Host cleanup remains pending', {cause: primaryFailure});
      }
      throw cleanupFailure;
    } finally {process.chdir(cwd);}
  }
});
