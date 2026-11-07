// Kill only this fresh fixture at the real write boundary. No old Store/Run.
import fs from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {createPublicationContractControlFixture} from '../../host-common/publication-contract-control.fixture.mjs';
const [directory, mode] = process.argv.slice(2);
const open = fs.open;
fs.open = async (...args) => {
  const handle = await open(...args), write = handle.write.bind(handle);
  handle.write = async (bytes, offset, length, position) => {
    const text = Buffer.isBuffer(bytes) ? bytes.toString() : '';
    if (text.includes('actql-local-publication-store-owner/0.1') &&
        (mode !== 'lease' || text.includes('leaseAnchor'))) {
      const count = mode === 'empty' ? 0 : mode === 'partial' ? 11 : bytes.length - 12;
      if (count) await write(bytes, offset, count, position);
      process.stdout.write(JSON.stringify({boundary: 'owner-write', path: String(args[0]), bytes: count}) + '\n',
        () => process.kill(process.pid, 'SIGKILL'));
      await new Promise(() => {});
    }
    return write(bytes, offset, length, position);
  };
  return handle;
};
syncBuiltinESMExports();
const {openLocalPublicationStore, prepareLocalPublicationStoreOwnership} = await import('../publication-store.mjs');
const original = mode === 'lease' ? await prepareLocalPublicationStoreOwnership(directory,
  {maxWireBytes: 16384, maxDirectoryEntries: 64}) : undefined;
await openLocalPublicationStore({directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
  capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
  maxContractNodes: 256, maxContractDepth: 32}, createPublicationContractControlFixture(),
undefined, undefined, original);
throw new Error('Owner interruption was not reached');
