import {lstat} from 'node:fs/promises';
import {resolve} from 'node:path';
import type {WireRunRef} from '../../packages/client-wire/index.js';
import type {createPublicationMetadataInventory} from './publication-metadata-inventory.mjs';
import type {createNativeMetadataMutationOwner} from './native-metadata-mutation-owner.mjs';
import {indexKey} from './publication-store-inputs.mjs';
import {fail, readBounded} from './publication-store-io.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type RequireInventory = ReturnType<typeof createPublicationMetadataInventory>['requireCommittedMetadataInventory'];
type PublicationIndexEntry = Parameters<RequireInventory>[0] & Readonly<{
  authority_scope_cid: string;
  run_definition_cid: string;
  public_index_entry_cid: string;
  durable_result_binding_cids: readonly string[];
}>;
type IndexContract = Readonly<{identity: string; wire: string}>;
type NativeIndexOriginal = Readonly<{
  metadata_key: string;
  namespace_id: string;
  authority_scope_cid: string;
  run_cid: string;
  body: Readonly<{semantic_cid: string; name: string; wire: string; byte_count: number}>;
  ack_revision: number;
}>;
type IndexOriginal<Contract> = Readonly<{
  entry: PublicationIndexEntry;
  bytes: Buffer;
  contract: Contract;
  native?: NativeIndexOriginal;
}>;
type IndexReadDemand<Contract> = NonNullable<Parameters<RequireInventory>[1]> & {
  retain(slot: number, value: Contract, fields: number): unknown;
};
type SelectedIndex<Contract> = Readonly<{entry: PublicationIndexEntry; index: Contract}>;
type IndexLookupAuthorization = (facts: Readonly<WireRunRef & {entry?: PublicationIndexEntry}>) => unknown;
type IndexPorts<Contract> = Readonly<{
  active(): unknown;
  currentDeliveryIndex(): Readonly<{
    nativePublicationIndex(key: string, readDemand?: IndexReadDemand<Contract>): NativeIndexOriginal | undefined;
    confirmNativePublicationIndex(original: NativeIndexOriginal): unknown;
  }> | undefined;
  admitContract(name: 'public_index_entry', wire: string): Contract;
  parseContract(contract: Contract): unknown;
  readSemanticBytes(cid: string, includeNative: false, readDemand?: IndexReadDemand<Contract>): Promise<Buffer>;
  exactUtf8WireMatches(bytes: Buffer, wire: string): boolean;
  readMetadataDeletion(key: string, readDemand?: IndexReadDemand<Contract>): Promise<unknown>;
  requireCommittedMetadataInventory: RequireInventory;
  syncDirectory(path: string): unknown;
  writeNativeIndexOriginal: ReturnType<typeof createNativeMetadataMutationOwner>['writeNativeIndexOriginal'];
}>;

export function createPublicationIndexReader<Contract extends IndexContract>(
  configuration: Readonly<{maxObjectBytes: number}>,
  indexesDirectory: string,
  durablyConfirmedIndexes: Map<string, string>,
  selectedPublicationReads: WeakMap<SelectedIndex<Contract>, PublicationIndexEntry>,
  {active, currentDeliveryIndex, admitContract, parseContract, readSemanticBytes, exactUtf8WireMatches,
    readMetadataDeletion, requireCommittedMetadataInventory, syncDirectory, writeNativeIndexOriginal}: IndexPorts<Contract>,
) {
  const admitNativeIndexOriginal = (native: NativeIndexOriginal, expectedKey?: WireRunRef) => {
    const admitted = admitContract('public_index_entry',native.body.wire), entry = parseContract(admitted) as PublicationIndexEntry;
    const key = {namespaceId:entry.namespace_id,authorityScopeCid:entry.authority_scope_cid,runDefinitionCid:entry.run_definition_cid};
    if (native.body.semantic_cid !== admitted.identity || indexKey(key) !== native.metadata_key ||
        native.namespace_id !== key.namespaceId || native.authority_scope_cid !== key.authorityScopeCid ||
        native.run_cid !== key.runDefinitionCid || expectedKey !== undefined &&
        (['namespaceId','authorityScopeCid','runDefinitionCid'] as const).some(field => key[field] !== expectedKey[field])) {
      fail('PublicIndexBindingMismatch');
    }
    return {entry,bytes:Buffer.from(native.body.wire,'utf8'),contract:admitted,native};
  };

  const readCommittedIndexRaw = async (
    key: WireRunRef, original?: IndexOriginal<Contract>, readDemand?: IndexReadDemand<Contract>,
  ): Promise<IndexOriginal<Contract> | undefined> => {
    active();
    const keyHash = indexKey(key), path = resolve(indexesDirectory, `${keyHash}.json`);
    const native = currentDeliveryIndex()!.nativePublicationIndex(keyHash, readDemand);
    if (native !== undefined) {
      try {await lstat(path);}
      catch (error) {
        if ((error as CodedCause)?.code === 'ENOENT') return admitNativeIndexOriginal(native,key);
        throw error;
      }
      fail('PublicIndexBindingMismatch');
    }
    let bytes;
    try { bytes = await readBounded(path, configuration.maxObjectBytes, undefined, undefined, false, readDemand); }
    catch (error) {
      if ((error as CodedCause)?.code === 'ENOENT') return undefined;
      throw error;
    }
    if (original !== undefined && bytes.equals(original.bytes)) return original;
    const admitted = admitContract(
      'public_index_entry', bytes.toString('utf8'),
    );
    const entry = parseContract(admitted) as PublicationIndexEntry;
    if (entry.namespace_id !== key.namespaceId ||
        entry.authority_scope_cid !== key.authorityScopeCid ||
        entry.run_definition_cid !== key.runDefinitionCid) {
      fail('PublicIndexBindingMismatch');
    }
    const semantic = await readSemanticBytes(entry.public_index_entry_cid, false, readDemand);
    // The selected Index and its immutable contract alias describe the same
    // fact. Reuse its admission for identical bytes, without skipping the
    // alias's real FD/inode/digest checks or admitting a changed spelling as
    // though it were the original.
    if (!exactUtf8WireMatches(semantic, admitted.wire)) {
      parseContract(admitContract('public_index_entry', semantic.toString('utf8')));
    }
    return {entry, bytes, contract: admitted};
  };

  const inspectCommittedIndexRaw = async (key: WireRunRef) =>
    (await readCommittedIndexRaw(key))?.entry;

  const inspectCommittedIndex = async (key: WireRunRef) => {
    const keyHash = indexKey(key);
    if (await readMetadataDeletion(keyHash) !== undefined) return undefined;
    const entry = await inspectCommittedIndexRaw(key);
    if (entry !== undefined) await requireCommittedMetadataInventory(entry);
    return entry;
  };

  const confirmCommittedIndexOriginal = async (key: WireRunRef, readDemand?: IndexReadDemand<Contract>) => {
    active();
    const keyHash = indexKey(key);
    if (await readMetadataDeletion(keyHash, readDemand) !== undefined) return undefined;
    const original = await readCommittedIndexRaw(key, undefined, readDemand);
    if (original === undefined) return undefined;
    const {entry} = original;
    const durableCid = durablyConfirmedIndexes.get(keyHash);
    if (durableCid !== undefined &&
        durableCid !== entry.public_index_entry_cid) {
      fail('PublicIndexDurabilityMismatch');
    }
    if (durableCid === undefined) {
      if (original.native !== undefined) {
        writeNativeIndexOriginal(currentDeliveryIndex()!.confirmNativePublicationIndex,[original.native], () => {
          durablyConfirmedIndexes.set(keyHash,entry.public_index_entry_cid);
        });
        return original;
      }
      // Visibility is not durability. Synchronize the exact containing
      // directory and then ensure that the same immutable entry is still
      // installed before reporting a durable commit.
      await syncDirectory(indexesDirectory);
      const confirmed = await readMetadataDeletion(keyHash, readDemand) === undefined
        ? (await readCommittedIndexRaw(key, original, readDemand))?.entry : undefined;
      if (confirmed?.public_index_entry_cid !==
          entry.public_index_entry_cid) {
        fail('PublicIndexDurabilityMismatch');
      }
      durablyConfirmedIndexes.set(keyHash, entry.public_index_entry_cid);
    }
    return original;
  };

  const confirmCommittedIndex = async (key: WireRunRef, readDemand?: IndexReadDemand<Contract>, slot = 5) => {
    const original = await confirmCommittedIndexOriginal(key, readDemand);
    if (original === undefined) return undefined;
    readDemand?.retain(slot, original.contract, 0);
    readDemand?.finish();
    return original.entry;
  };

  const confirmSelectedCommittedIndex = async (key: WireRunRef, readDemand?: IndexReadDemand<Contract>) => {
    const entry = await confirmCommittedIndex(key, readDemand, 6);
    if (entry !== undefined) await requireCommittedMetadataInventory(entry, readDemand);
    return entry;
  };

  const readCommittedPublication = async (key: WireRunRef, readDemand?: IndexReadDemand<Contract>) => {
    // The selected body's nominal admission already belongs to this read.
    // Return that original, not another public raw-wire read/admission.
    const original = await confirmCommittedIndexOriginal(Object.freeze({...key}), readDemand);
    if (original === undefined) return undefined;
    readDemand?.retain(0, original.contract, 0);
    readDemand?.retain(1, original.contract, 1);
    readDemand?.finish();
    await requireCommittedMetadataInventory(original.entry, readDemand);
    Object.freeze(original.entry.durable_result_binding_cids);
    const selected = Object.freeze({entry: Object.freeze(original.entry), index: original.contract});
    // One nested metadata lookup may consume this same Store acquisition.
    // It is neither a reusable read cache nor an authorization/ACK issuer.
    selectedPublicationReads.set(selected, selected.entry);
    return selected;
  };

  const lookupCommittedIndex = async (key: WireRunRef, authorize?: IndexLookupAuthorization) => {
    active();
    if (typeof authorize !== 'function' || authorize(Object.freeze({...key})) !== true) {
      fail('PublicationLookupDenied');
    }
    const entry = await confirmSelectedCommittedIndex(key);
    if (entry === undefined || authorize(Object.freeze({...key, entry})) !== true) {
      // Missing and unauthorized entries deliberately share one external code.
      fail('PublicationLookupDenied');
    }
    return entry;
  };

  return {admitNativeIndexOriginal, inspectCommittedIndexRaw, inspectCommittedIndex, confirmCommittedIndex,
    confirmSelectedCommittedIndex, readCommittedPublication, lookupCommittedIndex};
}
