import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, writeFile, rename, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
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

test('ordinary actual Mock Host runs original Quickstart INFER without applying its Effect', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-ordinary-mock-infer-'));
  const project = scaffoldProject(join(directory, 'project'), 'churn-risk-mock');
  const cwd = process.cwd(); let client;
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
  } finally {try {await client?.close();} finally {process.chdir(cwd);}}
});
