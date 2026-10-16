import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

test('actual Local Run state revision survives Host release and attach without another computation', async t => {
  const scratch = await createOwnedScratch({parent:tmpdir(), prefix:'actql-a-state-public-',
    label:'actual Local original Run state revision'});
  t.diagnostic(`Original disposable Host retained on failure: ${scratch.path}`);
  const keys = generateKeyPairSync('ed25519');
  let computations = 0;
  const installation = {directory:scratch.path, authorization:{
    accountConfiguration:JSON.stringify({version:'actql-execution-account-config/0.1',
      account_id:'state-revision', entries:[{entry_id:'write', outcome:'allow',
        principal:{all:true}, connection:{all:true}, resource:{all:true},
        operation:{any_of:['write']}, exclusions:[]}]}),
    reviewers:[{keyId:'reviewer', reviewerId:'reviewer', principalId:userInfo().username,
      publicKey:keys.publicKey.export({type:'spki',format:'pem'})}],
    hostKey:{keyId:'host', privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})},
    observe(name) { if (name === 'computed') computations++; },
  }};
  const options = {mode:'local', owner:'local', installation};
  const client = await connectEmbeddedLocal(options);
  let reopened;
  t.after(async () => {await client.close(); await reopened?.close();});
  const text = await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url),'utf8');
  const run = await client.startSource(text, {format:'json', submissionRef:client.newSubmission({nonce:'state-revision'})});
  const completed = await run.wait({signal:AbortSignal.timeout(15000)});
  assert.equal(completed.status, 'succeeded');
  assert.equal(Number.isSafeInteger(completed.revision), true);
  assert.ok(completed.revision >= 0);
  assert.deepEqual(await run.result('answer').all(), [{id:1},{id:2}]);
  await client.close();
  reopened = await connectEmbeddedLocal(options);
  const attached = await reopened.attach(run.ref);
  const after = await attached.status();
  assert.equal(after.run_id, completed.run_id);
  assert.equal(after.status, 'succeeded');
  assert.ok(after.revision >= completed.revision);
  assert.equal(after.control.physical_stop, 'confirmed');
  const reread = await attached.status();
  assert.equal(reread.revision, after.revision);
  const database = new DatabaseSync(join(scratch.path, 'requests/client-requests.sqlite3'), {readOnly:true});
  try {
    const saved = database.prepare(`SELECT state_revision, state_observation_key, revision
      FROM client_requests WHERE run_definition_cid = ?`).get(run.ref.runDefinitionCid);
    assert.equal(saved.state_revision, reread.revision);
    assert.equal(saved.revision, reread.control.revision);
    assert.equal(typeof saved.state_observation_key, 'string');
    assert.equal(saved.state_observation_key.includes('updated_at'), false);
  } finally { database.close(); }
  assert.equal(computations, 1);
  await reopened.close();
  scratch.passed();
});
