import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {tmpdir, userInfo} from 'node:os';
import {test} from 'node:test';
import {connectEmbeddedLocal} from '../adapters/host-node/embedded-local.mjs';
import {typedJsonLiteralSuccesses} from './fixtures/typed-json-literal-input.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

test('typed JSON capture survives Store commit and fresh-process Host restart', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-typed-json-public-', label: 'Typed JSON installed Host'});
  const directory = scratch.path;
  const events = [];
  const keys = generateKeyPairSync('ed25519');
  const authorization = {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'typed-json-public', entries: [
        {entry_id: 'read-original', outcome: 'allow',
          principal: {all: true}, connection: {all: true},
          resource: {any_of: ['result/answer', 'run']},
          operation: {any_of: ['read']}, exclusions: []},
        {entry_id: 'write', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
      principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    observe: (name, detail) => events.push({name, code: detail?.code}),
  };
  // A fresh process performs execution, Captured Run publication and durable
  // Store commit. The reader cannot reuse its in-memory Result or Value owner.
  const child = `
    import assert from 'node:assert/strict';
    import {readFileSync, writeFileSync} from 'node:fs';
    import {join} from 'node:path';
    import {connectEmbeddedLocal} from ${JSON.stringify(new URL('../adapters/host-node/embedded-local.mjs', import.meta.url).href)};
    const {directory, authorization, inputs} = JSON.parse(readFileSync(0, 'utf8'));
    const events = [];
    authorization.observe = (name, detail) => events.push({name,
      code: detail?.code, ref: detail?.ref,
      carrierSnapshots: detail?.carrierSnapshots});
    const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, authorization}});
    const records = [];
    try {
      for (const input of inputs) {
        const submissionRef = client.newSubmission({nonce: input.name});
        const record = {submissionRef};
        records.push(record);
        writeFileSync(join(directory, 'original-submissions.json'), JSON.stringify(records));
        const run = await client.startSource(input.text, {format: input.format, submissionRef});
        const state = await run.wait({signal: AbortSignal.timeout(30_000)});
        assert.equal(state.status, 'succeeded',
          JSON.stringify({name: input.name, state, events}));
        const result = run.result('answer');
        assert.deepEqual(await result.all(), input.expected);
        if (input.graphSnapshots) {
          const snapshots = events.find(event => event.name === 'computed' &&
            event.ref?.runDefinitionCid === run.ref.runDefinitionCid).carrierSnapshots;
          assert.deepEqual(snapshots.map(snapshot => snapshot.cid), input.graphSnapshots);
          for (const snapshot of snapshots) {
            assert.equal(snapshot.sourceReleased, true);
            assert.equal(snapshot.restored, true);
            assert.equal(snapshot.temporaryBodyReclaimed, true);
            assert.ok(snapshot.bytes > 0);
            assert.equal(snapshot.verifiedReadBytes, snapshot.bytes);
          }
        }
        Object.assign(record, {ref: run.ref, description: await result.describe()});
        writeFileSync(join(directory, 'original-submissions.json'), JSON.stringify(records));
      }
    } finally { await client.close(); }
    process.stdout.write(JSON.stringify(records));
  `;
  const records = JSON.parse(execFileSync(process.execPath,
    ['--input-type=module', '-e', child], {encoding: 'utf8', timeout: 60_000,
      input: JSON.stringify({directory, authorization,
        inputs: typedJsonLiteralSuccesses})}));
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory, authorization}});
  try {
    for (const [index, input] of typedJsonLiteralSuccesses.entries()) {
      const execution = await client.attach(records[index].ref);
      const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
      assert.equal(state.status, 'succeeded', JSON.stringify({directory, events}));
      assert.deepEqual(await execution.result('answer').all(), input.expected);
      assert.deepEqual((await execution.result('answer').describe()).columns, input.columns);
      assert.deepEqual(await execution.result('answer').describe(),
        records[index].description);
      assert.deepEqual(execution.ref, records[index].ref);
      // Reusing the original request must recover the same durable Run.
      const repeated = await client.startSource(input.text, {format: input.format,
        submissionRef: records[index].submissionRef});
      assert.deepEqual(repeated.ref, execution.ref);
      assert.deepEqual(await repeated.result('answer').all(), input.expected);
    }
  } finally { await client.close(); }
  scratch.passed();
});
