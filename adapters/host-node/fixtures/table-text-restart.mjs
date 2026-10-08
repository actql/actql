// A fresh process uses the persisted public Run and original Checkpoint.
// Optional approval uses only synthetic fixture keys and the real signer API;
// it never manufactures a checkpoint or receipt. Packed tests load the product.
import assert from 'node:assert/strict';
import {sign} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {setTimeout as delay} from 'node:timers/promises';
import {tableTestModule} from './table-test-modules.mjs';

const local = await tableTestModule(
  new URL('../embedded-local.mjs', import.meta.url), '@actql/local-node');
const open = local.connectEmbeddedLocal ?? local.connect;
const {options, ref, approval} = JSON.parse(await readFile(process.argv[2], 'utf8'));
const client = await open(options);
try {
  const run = await client.attach(ref);
  let state = await run.status();
  assert.equal(state.status, 'waiting_checkpoint');
  assert.deepEqual(state.result_availability, {});
  const checkpoints = (await client.checkpoints()).items;
  assert.equal(checkpoints.length, 1);
  if (approval !== undefined) {
    assert.equal(checkpoints[0].checkpointCid, approval.checkpointCid);
    const answer = await client.resolveCheckpoints([
      {checkpoint: checkpoints[0], decision: 'approved'},
    ], {signer: {
      keyId: approval.keyId, reviewerId: approval.reviewerId,
      authorityScopeCid: ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, approval.privateKey),
    }});
    assert.deepEqual(answer.results.map(result => result.status), ['committed']);
    const signal = AbortSignal.timeout(30000);
    for (;;) {
      signal.throwIfAborted();
      state = await run.wait({signal});
      if (!['running', 'resuming'].includes(state.status)) break;
      await delay(20, undefined, {signal});
    }
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(state.result_availability, {});
  }
  process.stdout.write(JSON.stringify({status: state.status,
    result_availability: state.result_availability}) + '\n');
} finally {
  await client.close();
}
