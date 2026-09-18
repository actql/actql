// Adopted in-process Transfer implementation for the initial Site milestone.
// It copies an exact managed row view into a destination-owned memory
// generation in bounded batches. It never manufactures common completion or a
// logical CID; the common Host supplies authorization and ledger accounting.
import {managedInputTransferEstimate, registerManagedMemoryInput,
  withManagedInputRows} from './managed-memory-representations.mjs';

const encoder = new TextEncoder();
const fail = code => { throw Object.assign(new Error(code), {code}); };
const positive = value => Number.isSafeInteger(value) && value > 0;

// Host-adopted trust boundary for the first Transfer codec. This assertion is
// backed by independent conformance fixtures, not by a per-transfer digest.
// A physical digest, when required by another boundary, remains distinct from
// the logical CID and from this value-preservation rule.
export const managedMemoryTransferContract = Object.freeze({
  version: 'actql-managed-transfer-provider/0.1',
  codec: 'actql-managed-row-wire-batches/0.1',
  preservationRule: 'actql-ordered-row-wire-value-preservation/0.1',
  trustBoundary: 'host-adopted-in-process-immutable-generation/0.1',
  integrityModel: 'typed-value-order-and-occurrence-preservation',
  contentDigest: 'not-established',
  logicalIdentity: 'unestablished',
});

export function createManagedMemoryTransferProvider({
  maxBatchRows = 256,
  maxBatchBytes = 1024 * 1024,
} = {}) {
  if (!positive(maxBatchRows) || !positive(maxBatchBytes)) {
    fail('InvalidManagedTransferConfiguration');
  }
  return Object.freeze({
    contract: managedMemoryTransferContract,
    estimate(material) {
      const estimate = managedInputTransferEstimate(material);
      if (!estimate || estimate.executionBytes < BigInt(maxBatchBytes)) {
        return undefined;
      }
      return estimate;
    },

    async copy({
      sourceMaterial,
      input,
      authorize,
      destinationAuthorize,
      charge,
      signal,
      estimate,
    } = {}) {
      if (!sourceMaterial || typeof sourceMaterial !== 'object' ||
          input == null || typeof authorize !== 'function' ||
          typeof destinationAuthorize !== 'function' ||
          typeof charge !== 'function' || !estimate ||
          ![estimate.transferBytes, estimate.retainedBytes,
            estimate.executionBytes].every(value =>
            typeof value === 'bigint' && value >= 0n)) {
        fail('InvalidManagedTransfer');
      }
      let current = [], currentBytes = 0;
      const chunks = [];
      let rows = 0, bytes = 0n, retainedBytes = 0n;
      const chargeBytes = value => {
        const charged = BigInt(value);
        if (bytes > estimate.transferBytes - charged) {
          fail('ManagedTransferByteLimit');
        }
        charge(charged);
        bytes += charged;
      };
      const flush = () => {
        if (current.length === 0) return;
        chunks.push(Object.freeze(current));
        current = [];
        currentBytes = 0;
        retainedBytes += 64n;
        if (retainedBytes > estimate.retainedBytes) {
          fail('ManagedTransferRetentionLimit');
        }
      };
      const append = async row => {
        signal?.throwIfAborted();
        if (typeof row !== 'string') fail('InvalidManagedTransferRow');
        const wireBytes = encoder.encode(row).byteLength;
        if (wireBytes > maxBatchBytes) fail('ManagedTransferBatchLimit');
        if (current.length >= maxBatchRows ||
            currentBytes > maxBatchBytes - wireBytes) flush();
        // Charge before retaining the corresponding destination value.
        chargeBytes(wireBytes);
        const ownedBytes = BigInt(row.length * 2 + 32);
        if (retainedBytes > estimate.retainedBytes - ownedBytes) {
          fail('ManagedTransferRetentionLimit');
        }
        retainedBytes += ownedBytes;
        rows++;
        currentBytes += wireBytes;
        current.push(row);
      };
      return withManagedInputRows(
        [{material: sourceMaterial, input, codecContractCid: undefined}],
        value => authorize(value) === true,
        (_index, row) => append(row),
        async () => {
          flush();
          return Object.freeze({
            chunks: Object.freeze([...chunks]), rows, bytes, retainedBytes,
          });
        },
        signal,
        (...values) => {
          const physicalBytes = values.at(-1);
          if (!Number.isSafeInteger(physicalBytes) || physicalBytes < 0) {
            fail('InvalidManagedTransferSourceBytes');
          }
          chargeBytes(physicalBytes);
        },
        provisional => {
          signal?.throwIfAborted();
          let open = true;
          let owned = provisional.chunks;
          const material = Object.freeze({});
          const destinationEstimate = Object.freeze({
            transferBytes: provisional.bytes,
            retainedBytes: provisional.retainedBytes,
            executionBytes: BigInt(maxBatchBytes),
          });
          const registered = registerManagedMemoryInput(
            material,
            value => destinationAuthorize(value) === true,
            () => open,
            Object.freeze({
              async read(_file, emit, readSignal) {
                for (const batch of owned) {
                  for (const row of batch) {
                    readSignal?.throwIfAborted();
                    await emit(row);
                  }
                }
              },
            }),
            () => { open = false; owned = Object.freeze([]); },
            destinationEstimate,
          );
          return Object.freeze({
            material,
            generation: Object.freeze({}),
            rows: provisional.rows,
            bytes: provisional.bytes,
            retainedBytes: provisional.retainedBytes,
            batches: provisional.chunks.length,
            maxBatchRows,
            maxBatchBytes,
            close: () => registered.close(),
            status: registered.status,
          });
        },
      );
    },
  });
}
