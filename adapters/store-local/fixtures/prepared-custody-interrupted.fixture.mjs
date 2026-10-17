// Fresh process/crash witness. Never open an existing product Run or replace
// Store recovery; stop at the actual original record FD write boundary.
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
    if (Buffer.isBuffer(bytes) && bytes.toString('utf8').startsWith(
      '{"version":"actql-local-prepared-custody/0.1"')) {
      if (mode === 'partial') await write(bytes, offset, 11, position);
      assert.ok(mode === 'empty' || mode === 'partial');
      process.stdout.write(JSON.stringify({boundary: 'original-custody-record-write',
        mode, path: String(args[0])}) + '\n', () => process.exit(77));
      await new Promise(() => {});
    }
    return write(bytes, offset, length, position);
  };
  return handle;
};
syncBuiltinESMExports();
const {openLocalPublicationStore} = await import('../publication-store.mjs');
const cid = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const store = await openLocalPublicationStore({directory,
  storeAuthorityCid: cid('prepared custody publication authority'), capacityBytes: 65536,
  maxObjectBytes: 4096, maxObjects: 8, maxContractNodes: 256, maxContractDepth: 32},
createPublicationContractControlFixture());
const bytes = Buffer.from('original prepared bytes\n');
const writer = store.createPreparedObjectWriter(bytes.length);
await writer.append(bytes);
await writer.seal(cid(bytes));
assert.fail('Original custody record interruption did not execute');
