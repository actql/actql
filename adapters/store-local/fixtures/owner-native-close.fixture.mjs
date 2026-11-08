// Same actual native namespace; only this fresh child's returned close ACK is
// withheld. Process exit is not reported as physical cleanup acknowledgement.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile} from 'node:fs/promises';
import {readdirSync} from 'node:fs';
import {createHostJournalDirectoryInspector} from '../../host-node/host-journal-directory.mjs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createPublicationContractControlFixture} from '../../host-common/publication-contract-control.fixture.mjs';
const [directory] = process.argv.slice(2);
const native = createRequire(import.meta.url)(fileURLToPath(new URL(
  `../../../packages/local-node/_build/native/${process.platform === 'linux' ? 'local-files-linux-x64' : 'directory-darwin-' + process.arch}.node`, import.meta.url)));
const open = native.openFileDirectory, close = native.fileRootClose;
let child, closes = 0;
const selected = {...native,
  // Explicit bootstrap-directory ports; the Store-owner handles/commit/close
  // below all remain originals from the same actual native namespace.
  open(path) {return {names: readdirSync(path), index: 0};},
  next(value) {return value.index === value.names.length ? null : Buffer.from(value.names[value.index++]);},
  current() {}, close() {return {outcome: 'closed'};},
  openFileDirectory(...args) {child = open(...args); return child;},
  fileRootClose(value) {
  if (value !== child) return close(value);
  closes++;
  assert.equal(close(value).outcome, 'closed');
  return {outcome: 'unknown', errno: 5};
}};
const {openLocalPublicationStore, prepareLocalPublicationStoreOwnership,
  closePreparedLocalPublicationStoreOwnership} = await import('../publication-store.mjs');
const inspector = createHostJournalDirectoryInspector(selected,
  {maxEntries: 64, maxNameBytes: 1024, maxWork: 65536, maxInspections: 32}, () => {});
const original = await prepareLocalPublicationStoreOwnership(directory, {maxWireBytes: 16384, maxDirectoryEntries: 64},
  undefined, inspector);
const path = join(directory, 'owner', 'owner.json'), before = JSON.parse(await readFile(path));
await assert.rejects(openLocalPublicationStore({directory, storeAuthorityCid: 'sha256:' + 'a'.repeat(64),
  capacityBytes: 65536, maxObjectBytes: 4096, maxObjects: 8,
  maxContractNodes: 256, maxContractDepth: 32}, createPublicationContractControlFixture(),
undefined, undefined, original), {code: 'PublicationStoreLeaseCleanupPending'});
const committed = await readFile(path);
assert.equal(JSON.parse(committed).token, before.token);
assert.equal(typeof JSON.parse(committed).leaseAnchor.identity, 'string');
for (let index = 0; index < 2; index++) {
  await assert.rejects(closePreparedLocalPublicationStoreOwnership(original), {code: 'PublicationStoreLeaseCleanupPending'});
  assert.deepEqual(await readFile(path), committed);
  assert.equal(closes, 1, 'consumed uncertain descriptor is never closed again');
}
process.stdout.write('native-close-retained\n');
