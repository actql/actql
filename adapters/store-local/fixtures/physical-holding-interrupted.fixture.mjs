// Fresh Store crash witness only. No retained product Run or external service
// is opened. Intercept the actual fs boundary, not a replacement Store.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createHash} from 'node:crypto';
import {createPublicationContractControlFixture} from '../../host-common/publication-contract-control.fixture.mjs';
const [directory, mode] = process.argv.slice(2);
const originalOpen = fs.open;
fs.open = async (...args) => {
  const handle = await originalOpen(...args);
  const write = handle.write.bind(handle);
  handle.write = async (bytes, offset, length, position) => {
    if (Buffer.isBuffer(bytes) && bytes.toString('utf8').includes(
      '"version":"actql-local-physical-holding/0.1"')) {
      if (mode === 'partial') await write(bytes, offset, 11, position);
      if (mode === 'empty' || mode === 'partial') {
        process.stdout.write(JSON.stringify({boundary: 'holding-record-before-complete-write',
          mode, path: String(args[0])}) + '\n', () => process.exit(77));
        await new Promise(() => {});
      }
    }
    return write(bytes, offset, length, position);
  };
  return handle;
};
syncBuiltinESMExports();
const {openLocalPublicationStore} = await import('../publication-store.mjs');
const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const store = await openLocalPublicationStore({directory,
  storeAuthorityCid: cid('atomic holding authority'), capacityBytes: 65536,
  maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32},
createPublicationContractControlFixture());
const bytes = Buffer.from('original byte payload\n');
const writer = store.createPreparedObjectWriter(bytes.length);
await writer.append(bytes);
const physical = await writer.seal(cid(bytes));
const record = {version: 'actql-local-physical-holding/0.1', namespace: 'content',
  holding_cid: cid('atomic original holding'), manifest_cid: cid('atomic original manifest'),
  objects: [{cid: cid(bytes), byte_count: bytes.length}]};
await store.commitPhysicalHolding(record, [physical.prepared]);
assert.fail('The selected physical write interruption did not execute');
