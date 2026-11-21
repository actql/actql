import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat, open} from 'node:fs/promises';
import type {FileHandle} from 'node:fs/promises';
import {fail, quantity} from './publication-store-io.mjs';
import type {PhysicalReadHandle, ReadCleanupStatus, ReadFailureCarrier, SemanticReader}
  from './publication-object-verifier.mjs';

type CodedCause = Readonly<{code?: unknown}> | null | undefined;
type SemanticReadHandle = Omit<FileHandle, 'close'> & Pick<PhysicalReadHandle, 'close'>;
type NativeSelection = boolean | 'publication';
type ReadDemand = (size: number) => unknown;
type NativeContractRow = Readonly<{name: string; wire: string; publication?: true}>;
export type SemanticContract = Readonly<{identity: string; name: string; wire: string}>;
type SemanticOriginal<Contract> = Readonly<{bytes: Buffer}> & (
  Readonly<{native: Contract; publication: boolean; physicalCid?: never; generation?: never}> |
  Readonly<{native?: never; publication?: never; physicalCid: string; generation?: Readonly<{device: string; inode: string}>}>
);
type SemanticIndex = Readonly<{
  publicationContract(cid: string, readDemand?: ReadDemand): NativeContractRow | undefined;
  contract(cid: string, readDemand?: ReadDemand): NativeContractRow | undefined;
}>;
type SemanticReadPorts<Contract> = Readonly<{
  contractPath(cid: string): string;
  objectPath(cid: string): string;
  active(): unknown;
  currentDeliveryIndex(): SemanticIndex | undefined;
  admitContract(name: string, wire: string): Contract;
  admitOriginalContract(name: string, wire: string, original: Contract): Contract;
  nativeContractRead(name: string): NativeSelection;
  parseContract(contract: Contract): unknown;
}>;

export function createPublicationSemanticReader<Contract extends SemanticContract>(
  configuration: Readonly<{maxObjectBytes: number}>,
  activeSemanticReaders: Set<SemanticReader>,
  physicalContentReadWindowBytes: number,
  {contractPath, objectPath, active, currentDeliveryIndex, admitContract, admitOriginalContract,
    nativeContractRead, parseContract}: SemanticReadPorts<Contract>,
) {
  const admitNativeContract = (native: NativeContractRow | undefined, cid: string, name?: string, retained?: Contract) => {
    if (native === undefined) return undefined;
    if (name !== undefined && native.name !== name) fail('InvalidDeliveryAttemptIndex');
    const contract = retained?.identity === cid && retained.name === native.name && retained.wire === native.wire
      ? retained : admitContract(native.name,native.wire);
    if (contract.identity !== cid) fail('InvalidDeliveryAttemptIndex');
    return contract;
  };
  const nativeDeliveryContract = (cid: string, name?: string, retained?: Contract) =>
    admitNativeContract(currentDeliveryIndex()?.contract(cid), cid, name, retained);

  const readSemanticOriginal = async function readSemanticBytes(
    cid: string, includeNative: NativeSelection = true, retainGeneration = false,
    retained?: Contract, readDemand?: ReadDemand,
  ): Promise<SemanticOriginal<Contract>> {
    const path = contractPath(cid);
    active();
    // A typed publication read already selected its table. A missing row may
    // fall back to the original file, without probing unrelated deliveries.
    const nativeRecord = includeNative === 'publication'
      ? currentDeliveryIndex()?.publicationContract(cid, readDemand)
      : includeNative ? currentDeliveryIndex()?.contract(cid, readDemand) : undefined;
    // A commit may already hold this same immutable issued contract. Compare
    // the actual selected row before asking its original control to reuse it;
    // changed rows and unknown/copy/legacy originals keep full admission.
    const native = nativeRecord !== undefined && retained?.identity === cid &&
      retained.name === nativeRecord.name && retained.wire === nativeRecord.wire
      ? admitOriginalContract(nativeRecord.name, nativeRecord.wire, retained)
      : admitNativeContract(nativeRecord,cid);
    if (native !== undefined && native.identity !== cid) fail('InvalidDeliveryAttemptIndex');
    if (native !== undefined) return Object.freeze({bytes: Buffer.from(native.wire,'utf8'), native,
      publication: includeNative === 'publication' || nativeRecord!.publication === true});
    // This is the original read duty in the same Store lifetime. Keep its
    // private failure reachable even when a public ingress redacts the Error.
    const reader: SemanticReader = {cleanup: undefined, failure: undefined};
    activeSemanticReaders.add(reader);
    let handle: SemanticReadHandle;
    try { handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW); }
    catch (error) {
      activeSemanticReaders.delete(reader); // No original FD was acquired.
      if ((error as CodedCause)?.code === 'ENOENT') fail('PublicationContractMissing');
      throw error;
    }
    let readFailure: unknown;
    let readFailed = false;
    try {
      const before = await handle.stat();
      if (!before.isFile() || !quantity(before.size) ||
          before.size > configuration.maxObjectBytes) {
        fail('InvalidPublicationContractObject');
      }
      // The original FD extent bounds both acquisition and the private output
      // before copying. A small contract must not acquire a default64KiB
      // stream backing or return an unrelated pooled backing.
      if (readDemand !== undefined && (typeof readDemand !== 'function' ||
          readDemand(before.size) !== undefined)) fail('InvalidPublicationMetadataDemand');
      const bytes = Buffer.allocUnsafeSlow(before.size);
      const hash = createHash('sha256');
      let size = 0;
      if (before.size > 0) {
        const stream = handle.createReadStream({autoClose: false,
          end: before.size - 1, highWaterMark: Math.min(physicalContentReadWindowBytes, before.size)});
        for await (const chunk of stream as AsyncIterable<Buffer>) {
          if (chunk.byteLength > before.size - size ||
              chunk.byteLength > configuration.maxObjectBytes - size) {
            fail('PublicationContractCorrupt');
          }
          chunk.copy(bytes, size);
          hash.update(chunk);
          size += chunk.byteLength;
        }
      }
      const after = await handle.stat();
      const physicalCid = `sha256:${hash.digest('hex')}`;
      const physical = await lstat(objectPath(physicalCid));
      if (!after.isFile() || before.dev !== after.dev ||
          before.ino !== after.ino || before.size !== after.size ||
          before.mtimeMs !== after.mtimeMs || size !== after.size ||
          physical.dev !== after.dev || physical.ino !== after.ino ||
          physical.size !== after.size || physical.mtimeMs !== after.mtimeMs) {
        fail('PublicationContractCorrupt');
      }
      // This original FD already supplied every hashed byte, and the digest's
      // object path names the same unchanged hard-linked allocation. Reopening
      // that allocation to hash it again adds no independent fact. A later
      // read still acquires and validates its own original; no Store-wide
      // successful-digest cache substitutes for that observation.
      if (retainGeneration) return Object.freeze({bytes, physicalCid, generation: Object.freeze({
        device: String(after.dev), inode: String(after.ino),
      })});
      return Object.freeze({bytes, physicalCid});
    } catch (error) {
      readFailure = error;
      readFailed = true;
      throw error;
    } finally {
      try {
        if (await handle.close() === false) fail('PublicationSemanticReaderCleanupPending');
        activeSemanticReaders.delete(reader);
      } catch (closeFailure) {
        // Preserve this same original FD and primary failure. Cleanup retries
        // close only: never reopen, reread, or release the Store on rejection.
        let original: SemanticReadHandle | undefined = handle;
        let flight: Promise<ReadCleanupStatus> | undefined;
        const status = () => Object.freeze({pending: original !== undefined});
        const cleanup = Object.freeze({status, retry() {
          if (flight !== undefined) return flight;
          if (original === undefined) return Promise.resolve(status());
          flight = Promise.resolve().then(async () => {
            if (await original!.close() === false) fail('PublicationSemanticReaderCleanupPending');
            original = undefined;
            activeSemanticReaders.delete(reader);
            reader.cleanup = reader.failure = undefined;
            return status();
          }).finally(() => { flight = undefined; });
          return flight;
        }});
        const primary = readFailed ? readFailure : closeFailure;
        // Own the duty before inspecting/decorating the outward Error. An
        // ordinary extensible Error can already have a readonly cleanup field.
        reader.cleanup = cleanup;
        reader.failure = primary;
        let failure: ReadFailureCarrier;
        try {
          failure = (primary !== null && typeof primary === 'object' &&
            Object.isExtensible(primary) && (primary as ReadFailureCarrier).cleanupHandle === undefined &&
            ['cleanupHandle', 'cleanupPending', 'cleanupError'].every(name => {
              const field = Object.getOwnPropertyDescriptor(primary, name);
              return field === undefined || field.writable === true;
            })
            ? primary : new Error('PublicationSemanticReaderCleanupPending', {cause: primary})) as ReadFailureCarrier;
          failure.cleanupHandle = cleanup;
          failure.cleanupPending = true;
          failure.cleanupError = closeFailure;
        } catch {
          failure = new Error('PublicationSemanticReaderCleanupPending', {cause: primary}) as Error & ReadFailureCarrier;
          failure.cleanupHandle = cleanup;
          failure.cleanupPending = true;
          failure.cleanupError = closeFailure;
        }
        reader.failure = failure;
        throw failure;
      }
    }
  };

  // Public callers receive their own mutable bytes. The private observation
  // also retains the digest of this exact allocation after its real FD close.
  const readSemanticBytes = async (cid: string, includeNative: NativeSelection = true, readDemand?: ReadDemand) =>
    (await readSemanticOriginal(cid, includeNative, false, undefined, readDemand)).bytes;

  const readContract = async (
    cid: string, contractName?: string,
    readOriginal: (cid: string, includeNative: NativeSelection) => Promise<SemanticOriginal<Contract>> | SemanticOriginal<Contract> = readSemanticOriginal,
  ): Promise<Readonly<{wire: string; value: unknown; contract?: Contract}>> => {
    const includeNative = contractName === undefined || nativeContractRead(contractName);
    const original = await readOriginal(cid, includeNative);
    const native = original.native;
    if (native !== undefined) {
      if (contractName !== undefined && native.name !== contractName) fail('InvalidDeliveryAttemptIndex');
      return Object.freeze({wire:native.wire,value:parseContract(native),contract:native});
    }
    const bytes = original.bytes;
    const wire = bytes.toString('utf8');
    if (contractName === undefined) {
      let value: unknown;
      try { value = JSON.parse(wire); }
      catch (error) { fail('InvalidPublicationJsonObject', error); }
      return Object.freeze({wire, value});
    }
    const contract = admitContract(contractName, wire);
    return Object.freeze({wire: contract.wire,
      value: parseContract(contract), contract});
  };

  const readJsonObject = async (cid: string, contractName?: string) =>
    (await readContract(cid, contractName)).value;

  return {nativeDeliveryContract, readSemanticOriginal, readSemanticBytes, readContract, readJsonObject};
}
