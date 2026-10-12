// Each phase is a fresh public Host process. Original generated Content and
// Model input are authenticated by the existing Store/continuation owners;
// fixture configuration supplies no substitute completion or call permission.
import assert from 'node:assert/strict';
import {createPrivateKey, createPublicKey, sign} from 'node:crypto';
import {open, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {inspect} from 'node:util';
import {createGeneratedContentFixture} from './generated-content.fixture.mjs';
import {reopenContentCommandCustody} from './content-command-custody.fixture.mjs';
import {openContentCommandHost} from './content-command-host.fixture.mjs';
import {generatedContentInferProgram, generatedContentModelProviders, mediaInstallation}
  from './generated-model-installation.fixture.mjs';
import {canonical} from './file-listing-source.fixture.mjs';

const [configPath, phase] = process.argv.slice(2);
assert.ok(['capture', 'approve', 'read'].includes(phase));
const config = JSON.parse(await readFile(configPath, 'utf8'));
const keys = {privateKey: createPrivateKey(config.privateKey), publicKey: createPublicKey(config.publicKey)};
const expected = Buffer.from('name\n"approved.csv"\n');
const expectedRows = [{name: 'out.csv', outcome: 'ok', value: {reason: null, risk: 'high'}}];
const closers = [];
let host;
const durableFixture = async (name, value) => {
  const file = await open(join(config.root, name), 'wx', 0o600);
  try { await file.writeFile(canonical(value)); await file.sync(); }
  finally { await file.close(); }
  const directory = await open(config.root, 'r');
  try { await directory.sync(); } finally { await directory.close(); }
};
try {
  let original;
  if (phase === 'capture') {
    original = await createGeneratedContentFixture({after: close => closers.push(close)}, {
      directory: join(config.root, 'content-store'), expiresAt: config.expiresAt});
    await original.store.commitPhysicalHolding(original.holding, [original.physical.prepared]);
    await original.issue();
    await durableFixture('original-source-custody.json', {configuration: original.configuration,
      description: original.description, binding: original.binding, holding: original.holding});
  } else {
    original = await reopenContentCommandCustody(
      JSON.parse(await readFile(join(config.root, 'original-source-custody.json'), 'utf8')));
    closers.push(() => original.store.close());
  }
  const {task, installation, hostCapacityPolicy} = await mediaInstallation({requestBytes: 4096, contentBytes: 32});
  let calls = 0, generations = 0, preparations = 0, physicalIssue;
  const registerModelProviders = generatedContentModelProviders({root: config.root,
    task, expected, sourceWire: original.description.wire,
    onPrepare: () => preparations++, onSend: () => calls++,
    onFailure: error => { physicalIssue = error; }});
  host = await openContentCommandHost({scratch: {path: config.root}, generated: original,
    keys, entrance: config.entrance, modelInstallation: installation,
    registerModelProviders, hostCapacityPolicy, modelApprovalRequired: true,
    allowSourceRead: phase === 'capture',
    faultInjection: step => { if (step === 'content_workspace_reserved') generations++; }});
  const {client} = host;
  let run, state;
  if (phase === 'capture') {
    run = await client.startSource(JSON.stringify(generatedContentInferProgram()), {
      format: 'json', submissionRef: client.newSubmission({nonce: 'generated-model-process'})});
    state = await run.wait({signal: AbortSignal.timeout(15000)});
    assert.equal(state.status, 'waiting_checkpoint', inspect({state, events: host.events}, {depth: 16}));
    assert.equal(host.reads(), 1);
    assert.equal(generations, 1);
    assert.equal(calls, 0);
    const checkpoints = (await client.checkpoints()).items;
    assert.equal(checkpoints.length, 1);
    await durableFixture('original-model-run.json', {ref: run.ref,
      checkpointCid: checkpoints[0].checkpointCid});
  } else {
    const saved = JSON.parse(await readFile(join(config.root, 'original-model-run.json'), 'utf8'));
    run = await client.attach(saved.ref);
    if (phase === 'approve') {
      state = await run.status();
      assert.equal(state.status, 'waiting_checkpoint', inspect({state, events: host.events}, {depth: 16}));
      const checkpoints = (await client.checkpoints()).items;
      assert.equal(checkpoints.length, 1);
      assert.equal(checkpoints[0].checkpointCid, saved.checkpointCid);
      const response = await client.resolveCheckpoints(
        [{checkpoint: checkpoints[0], decision: 'approved'}], {
          signer: {keyId: 'reviewer', reviewerId: 'reviewer',
            authorityScopeCid: saved.ref.authorityScopeCid,
            sign: bytes => sign(null, bytes, keys.privateKey)},
        });
      assert.equal(response.results[0].status, 'committed');
    }
    const signal = AbortSignal.timeout(15000);
    do {
      state = await run.status({signal});
      if (!['resuming', 'running', 'waiting_checkpoint'].includes(state.status)) break;
      await delay(20, undefined, {signal});
    } while (true);
    assert.equal(state.status, 'succeeded', inspect({state, events: host.events,
      physicalIssue, calls, generations, preparations}, {depth: 16}));
    assert.equal(host.reads(), 0, 'no original Source request in a restored process');
    assert.equal(generations, 0, 'no encoder replay in a restored process');
    assert.equal(calls, phase === 'approve' ? 1 : 0, 'no repeat send in the Result-reading process');
  }
  assert.equal(host.sends(), 0, 'a Model call does not authorize a COMMAND write');
  const rows = state.status === 'succeeded' ? await run.result('answer').all() : undefined;
  if (rows !== undefined) assert.deepEqual(rows, expectedRows);
  process.stdout.write(JSON.stringify({pid: process.pid, phase, ref: run.ref,
    status: state.status, reads: host.reads(), sends: host.sends(),
    calls, generations, preparations, rows}) + '\n');
} finally {
  await host?.close();
  for (const close of closers.reverse()) await close();
}
