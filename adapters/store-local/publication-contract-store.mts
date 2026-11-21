import {lstat} from 'node:fs/promises';
import type {ActivePhysicalRecordWriter} from './physical-holding-record-writer.mjs';
import type {createPublicationSemanticReader, SemanticContract} from './publication-semantic-reader.mjs';
import type {validateConfiguration} from './publication-store-inputs.mjs';
import {cidPattern, exactKeys, fail, PublicationStoreError} from './publication-store-io.mjs';

export type PublicationContract = SemanticContract & Readonly<{identityField: string}>;
type ContractLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type ContractControl<Contract> = Readonly<{
  admit(name: string, wire: string, limits: ContractLimits): Contract;
  admitOriginal?(original: unknown, limits: ContractLimits): Contract | undefined;
}>;
type Admitted<Contract> = Readonly<{contract: Contract; value: unknown}>;
type CodedCause = Readonly<{code?: unknown; outcome?: unknown}> | null | undefined;
type NativeContractEntry = Readonly<{semantic_cid: string; name: string; wire: string; byte_count: number}>;
type NativeStoreResult<Contract> = Admitted<Contract> & Readonly<{
  semanticCid: string; storage: 'file' | 'sqlite'; created?: boolean; progressCreated?: boolean;
}>;
type NativePublicationUsage = Readonly<{bytes: number; objects: number; progressCreated?: boolean}>;
type StoredFileContract = Readonly<{
  semanticCid: string;
  physical: Readonly<{cid: string; bytes: number; created: boolean}>;
  created: boolean;
  progressCreated?: never;
}>;
type Reservation = Readonly<{release(): unknown}>;
type Cleanup = NonNullable<ActivePhysicalRecordWriter['cleanup']>;
type CleanupStatus = ReturnType<Cleanup['status']>;
type PublicationCommitFailure = PublicationStoreError & {
  outcome: 'unknown';
  primaryFailure: unknown;
  cleanupPending: boolean;
  cleanupHandle: Cleanup;
};
type PublicationIndex = Readonly<{
  publicationContract(cid: string): NativeContractEntry | undefined;
  publicationContracts(cids: readonly string[]): readonly NativeContractEntry[];
  putPublicationContracts(
    originals: readonly NativeContractEntry[], allowance: Readonly<{bytes: number; objects: number}>,
    progress: unknown, selection: readonly NativeContractEntry[] | undefined,
  ): NativePublicationUsage;
}>;
type ContractStorePorts<Contract extends PublicationContract> = Readonly<{
  active(): unknown;
  currentDeliveryIndex(): PublicationIndex | undefined;
  nativePublicationContract(name: string): boolean;
  contractPath(cid: string): string;
  readSemanticOriginal: ReturnType<typeof createPublicationSemanticReader<Contract>>['readSemanticOriginal'];
  exactUtf8WireMatches(bytes: Buffer, wire: string): boolean;
  reserveObjectCapacity(bytes: number): Reservation;
  accountNativePublication(usage: NativePublicationUsage): void;
  putSemantic(wire: string, semanticCid: string): Promise<StoredFileContract>;
  putSemanticBatch(supplied: readonly Readonly<{wire: string; semanticCid: string}>[]): Promise<readonly StoredFileContract[]>;
}>;

export function createPublicationContractStore<Contract extends PublicationContract>(
  configuration: Pick<ReturnType<typeof validateConfiguration>, 'maxObjectBytes' | 'maxObjects' | 'capacityBytes'>,
  contractControl: ContractControl<Contract>,
  contractLimits: ContractLimits,
  activePhysicalRecordWriters: Set<ActivePhysicalRecordWriter>,
  {active, currentDeliveryIndex, nativePublicationContract, contractPath, readSemanticOriginal, exactUtf8WireMatches,
    reserveObjectCapacity, accountNativePublication, putSemantic, putSemanticBatch}: ContractStorePorts<Contract>,
) {
  const admitContract = (name: unknown, wire: unknown): Contract => {
    if (typeof name !== 'string' || typeof wire !== 'string' ||
        Buffer.byteLength(wire, 'utf8') > configuration.maxObjectBytes) {
      fail('InvalidPublicationContractWire');
    }
    let contract: Contract;
    try {
      // UTF-8 wire extent bounds JSON value-node count (including containers).
      // Preserve an explicitly narrower configured policy. This does not grant
      // parser memory: admission remains the selected Store service operation,
      // under its object limit and existing opaque runtime support envelope.
      const wireBytes = Buffer.byteLength(wire, 'utf8');
      contract = contractControl.admit(name, wire, Object.freeze({
        ...contractLimits, maxNodes: Math.min(contractLimits.maxNodes, wireBytes),
      }));
    }
    catch (error) { fail('InvalidPublicationContract', error); }
    if (!exactKeys(contract, ['name', 'identityField', 'identity', 'wire']) ||
        contract.name !== name || typeof contract.identityField !== 'string' ||
        !cidPattern.test(contract.identity) || typeof contract.wire !== 'string' ||
        Buffer.byteLength(contract.wire, 'utf8') >
          configuration.maxObjectBytes) {
      fail('InvalidPublicationContractControlResult');
    }
    return contract;
  };

  const parseContract = (contract: PublicationContract) => {
    let value: unknown;
    try { value = JSON.parse(contract.wire); }
    catch (error) { fail('InvalidPublicationContractControlResult', error); }
    if (value === null || typeof value !== 'object' || Array.isArray(value) ||
        (value as Record<string, unknown>)[contract.identityField] !== contract.identity) {
      fail('InvalidPublicationContractControlResult');
    }
    return value as Readonly<Record<string, unknown>>;
  };

  const admitOriginalContract = (name: unknown, wire: unknown, original: unknown): Contract => {
    let contract: Contract | undefined;
    if (original !== undefined && typeof contractControl.admitOriginal === 'function') {
      try { contract = contractControl.admitOriginal(original, contractLimits); }
      catch (error) { fail('InvalidPublicationContract', error); }
      if (contract !== undefined &&
          (contract !== original || !Object.isFrozen(contract) ||
            typeof contract.name !== 'string' || contract.name !== name ||
            typeof contract.identityField !== 'string' ||
            !cidPattern.test(contract.identity) || contract.wire !== wire ||
            typeof contract.wire !== 'string' ||
            Buffer.byteLength(contract.wire, 'utf8') > configuration.maxObjectBytes)) {
        fail('InvalidPublicationContractControlResult');
      }
    }
    // Unrecognized originals and legacy controls still use full admission.
    // An actual refusal or malformed nominal response never takes this path.
    return contract ?? admitContract(name, wire);
  };

  // Only this Store's private incoming-contract admission supplies these
  // facts. Physical persistence remains the same original operation.
  const putAdmittedPublicationContract = async (contract: Contract, value: unknown) => {
    const semanticCid = contract.identity;
    if (nativePublicationContract(contract.name) && currentDeliveryIndex()?.publicationContract(semanticCid) !== undefined) {
      return (await putNativePublicationContracts([Object.freeze({contract,value})]))[0];
    }
    return Object.freeze({
      value,
      contract,
      ...await putSemantic(contract.wire, semanticCid),
    });
  };

  const putPublicationContract = async (name: unknown, suppliedWire: unknown) => {
    const contract = admitContract(name, suppliedWire);
    return putAdmittedPublicationContract(contract, parseContract(contract));
  };

  const putNativePublicationContracts = async (admitted: readonly Admitted<Contract>[], progress?: unknown) => {
    active();
    for (const pending of activePhysicalRecordWriters) {
      if (pending.failed) fail('PublicationStoreCleanupPending');
    }
    const entries: NativeContractEntry[] = [];
    const results: NativeStoreResult<Contract>[] = [];
    const reservations: Reservation[] = [];
    let selection: readonly NativeContractEntry[] | undefined;
    let reservationBytes = 0;
    try {
      for (const original of admitted) {
        const {contract} = original;
        // Existing file originals remain files. Do not duplicate their charge
        // or silently replace an independently adopted physical representation.
        try {
          await lstat(contractPath(contract.identity));
          const retained = await readSemanticOriginal(contract.identity, false);
          if (!exactUtf8WireMatches(retained.bytes, contract.wire)) fail('PublicationSemanticIdentityConflict');
          results.push(Object.freeze({...original, semanticCid:contract.identity, storage:'file', created:false}));
          continue;
        } catch (error) { if ((error as CodedCause)?.code !== 'ENOENT') throw error; }
        const entry = Object.freeze({semantic_cid:contract.identity,name:contract.name,
          wire:contract.wire,byte_count:Buffer.byteLength(contract.wire,'utf8')});
        entries.push(entry);
        results.push(Object.freeze({...original, semanticCid:contract.identity, storage:'sqlite'}));
      }
      // Files retain their original representation. Select only the remaining
      // native keys together for quota preflight; mutation still owns its
      // actual selected-row conflict check and durable transaction.
      selection = entries.length === 0 ? undefined :
        currentDeliveryIndex()!.publicationContracts(entries.map(entry => entry.semantic_cid));
      const selected = new Map((selection ?? []).map(entry => [entry.semantic_cid, entry]));
      for (const entry of entries) {
        const existing = selected.get(entry.semantic_cid);
        if (existing !== undefined && (existing.name !== entry.name || existing.wire !== entry.wire)) {
          fail('PublicationSemanticIdentityConflict');
        }
        if (existing === undefined) {
          reservations.push(reserveObjectCapacity(entry.byte_count));
          reservationBytes += entry.byte_count;
        }
      }
      for (let index = 0; index < results.length; index++) {
        const result = results[index];
        if (result.storage === 'sqlite') results[index] = Object.freeze({...result,
          created:!selected.has(result.semanticCid)});
      }
    } catch (error) {
      for (const reservation of reservations) reservation.release();
      throw error;
    }
    if (entries.length === 0 && progress === undefined) return Object.freeze(results);
    const originalEntries = Object.freeze(entries);
    const allowance = Object.freeze({objects:reservations.length,bytes:reservationBytes});
    const writer: ActivePhysicalRecordWriter = {failed:false,cleanup:undefined};
    let pending = true;
    let flight: Promise<CleanupStatus> | undefined;
    let failure: PublicationCommitFailure | undefined;
    let progressCreated: boolean | undefined;
    const finish = () => {
      const usage = currentDeliveryIndex()!.putPublicationContracts(originalEntries,allowance,progress,selection);
      progressCreated = usage.progressCreated;
      accountNativePublication(usage);
      for (const reservation of reservations) reservation.release();
      pending = false;
      activePhysicalRecordWriters.delete(writer);
    };
    const status = () => Object.freeze({pending});
    writer.cleanup = Object.freeze({status,retry() {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(() => {
        if (pending) finish();
        if (failure !== undefined) failure.cleanupPending = pending;
        return status();
      })
        .finally(() => { flight = undefined; });
      return flight;
    }});
    activePhysicalRecordWriters.add(writer);
    try { finish(); }
    catch (error) {
      if ((error as CodedCause)?.outcome !== 'unknown') {
        for (const reservation of reservations) reservation.release();
        pending = false;
        activePhysicalRecordWriters.delete(writer);
        throw error;
      }
      writer.failed = true;
      // The same bodies and capacity reservation remain owned until an actual
      // same-database write confirms their outcome. Visibility is not an ACK.
      failure = new PublicationStoreError('PublicationMetadataCommitOutcomeUnknown',error) as PublicationCommitFailure;
      failure.outcome = 'unknown';
      failure.primaryFailure = error;
      failure.cleanupPending = true;
      failure.cleanupHandle = writer.cleanup;
      throw failure;
    }
    return Object.freeze(results.map(result => progress === undefined ? result :
      Object.freeze({...result,progressCreated})));
  };

  const admitPublicationContracts = (supplied: unknown, originals: boolean) => {
    active();
    if (!Array.isArray(supplied)) fail('InvalidPublicationContractWire');
    const count = supplied.length;
    if (!Number.isSafeInteger(count) || count < 0 || count > configuration.maxObjects) {
      fail('PublicationStoreObjectLimit');
    }
    // Own the finite input before an admission callback or physical await.
    const inputs = Array.from({length: count}, (_, index) => {
      const input: unknown = supplied[index];
      if (!exactKeys(input, originals
        ? ['name', 'identityField', 'identity', 'wire'] : ['name', 'wire'])) {
        fail('InvalidPublicationContractWire');
      }
      return Object.freeze({name: input.name, wire: input.wire,
        original: originals ? input : undefined});
    });
    const admitted: Admitted<Contract>[] = [];
    const identities = new Map<string, Admitted<Contract>>();
    const wires = new Map<unknown, Admitted<Contract>>();
    let bytes = 0n;
    for (const input of inputs) {
      const sameWire = wires.get(input.wire);
      if (sameWire !== undefined && sameWire.contract.name === input.name) continue;
      const contract = admitOriginalContract(input.name, input.wire, input.original);
      const value = parseContract(contract);
      const previous = identities.get(contract.identity);
      if (previous !== undefined) {
        if (previous.contract.name !== contract.name || previous.contract.wire !== contract.wire) {
          fail('PublicationSemanticIdentityConflict');
        }
        continue;
      }
      bytes += BigInt(Buffer.byteLength(contract.wire, 'utf8'));
      if (bytes > BigInt(configuration.capacityBytes)) fail('PublicationStoreCapacity');
      const original = Object.freeze({contract, value});
      admitted.push(original);
      identities.set(contract.identity, original);
      wires.set(input.wire, original);
    }
    return admitted;
  };

  const putAdmittedPublicationContracts = async (admitted: readonly Admitted<Contract>[], originals: boolean, progress?: unknown) => {
    const nativeOnly = admitted.every(({contract}) => nativePublicationContract(contract.name));
    if (originals && nativeOnly) {
      return putNativePublicationContracts(admitted, progress);
    }
    const existingNative = new Map<string, NativeStoreResult<Contract>>();
    for (const original of admitted) {
      const {contract} = original;
      if (!nativePublicationContract(contract.name)) continue;
      const retained = currentDeliveryIndex()!.publicationContract(contract.identity);
      if (retained === undefined) continue;
      if (retained.name !== contract.name || retained.wire !== contract.wire) {
        fail('PublicationSemanticIdentityConflict');
      }
      existingNative.set(contract.identity,Object.freeze({...original,
        semanticCid:contract.identity,storage:'sqlite',created:false}));
    }
    if (nativeOnly && existingNative.size !== 0) return putNativePublicationContracts(admitted, progress);
    // A legacy file member does not turn an already native sibling into a
    // second file allocation. Only the remaining original files enter the
    // unchanged physical batch and its actual capacity/ACK protocol.
    const stored = await putSemanticBatch(admitted.filter(({contract}) =>
      !existingNative.has(contract.identity)).map(({contract}) => ({
      wire: contract.wire, semanticCid: contract.identity,
    })));
    let physicalIndex = 0;
    return Object.freeze(admitted.map(original => existingNative.get(original.contract.identity) ??
      Object.freeze({...original,...stored[physicalIndex++]})));
  };

  const putPublicationContractBatch = async (supplied: unknown, originals: boolean) =>
    putAdmittedPublicationContracts(admitPublicationContracts(supplied, originals), originals);

  const putPublicationContracts = (supplied: unknown) => putPublicationContractBatch(supplied, false);
  const putOriginalPublicationContracts = (supplied: unknown) => putPublicationContractBatch(supplied, true);

  return {admitContract, parseContract, admitOriginalContract, putAdmittedPublicationContract, putPublicationContract,
    putNativePublicationContracts, admitPublicationContracts, putAdmittedPublicationContracts,
    putPublicationContracts, putOriginalPublicationContracts};
}
