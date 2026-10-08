// A fresh process observes the persisted public Run without approving it or
// manufacturing a checkpoint. Packed tests resolve the installed product.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {tableTestModule} from './table-test-modules.mjs';

const local = await tableTestModule(
  new URL('../embedded-local.mjs', import.meta.url), '@actql/local-node');
const open = local.connectEmbeddedLocal ?? local.connect;
const {options, ref} = JSON.parse(await readFile(process.argv[2], 'utf8'));
const client = await open(options);
try {
  const run = await client.attach(ref);
  const state = await run.status();
  assert.equal(state.status, 'waiting_checkpoint');
  assert.deepEqual(state.result_availability, {});
  assert.equal((await client.checkpoints()).items.length, 1);
  process.stdout.write(JSON.stringify({status: state.status,
    result_availability: state.result_availability}) + '\n');
} finally {
  await client.close();
}
