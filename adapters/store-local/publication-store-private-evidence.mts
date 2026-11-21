import {createCipheriv, createDecipheriv, randomBytes} from 'node:crypto';
import type {createPhysicalHoldingReaders, ReadPhysicalHolding, SelectedPhysicalHoldingRecord}
  from './physical-holding-record-reader.mjs';
import type {createObjectWriterOwner} from './object-writer-owner.mjs';
import {exactKeys, fail} from './publication-store-io.mjs';

type PrivateWriter = Pick<ReturnType<typeof createObjectWriterOwner>, 'cancel' | 'status'>;
type PrivateCleanup = Readonly<{
  status(): Readonly<{pending: boolean}>;
  release(): Promise<boolean>;
}>;

// The existing Store's synchronous encoding phase. Only its complete envelope
// crosses into writer/FD/ACK waits; crypto and Base64 segment temporaries do not
// belong to that async frame. This retires references, not capacity, physical
// GC, a pending writer or the original borrowed input's independent custody.
export function encodePrivateEvidenceEnvelope(
  input: string, isWire: true, key: Uint8Array, aad: Uint8Array, maximum: number,
): Buffer;
export function encodePrivateEvidenceEnvelope(
  input: Uint8Array, isWire: false, key: Uint8Array, aad: Uint8Array, maximum: number,
): Buffer;
export function encodePrivateEvidenceEnvelope(
  input: string | Uint8Array, isWire: boolean, key: Uint8Array, aad: Uint8Array, maximum: number,
) {
  // The caller already checked the complete encrypted extent. A short wire
  // must not borrow a larger shared pool backing for this encoding lifetime.
  // Keep its exact UTF-8 snapshot; the original String and codec controls are
  // still separate funded components, not released by this extent check.
  const bytes = isWire ? Buffer.allocUnsafeSlow(Buffer.byteLength(input as string, 'utf8')) : input as Uint8Array;
  if (isWire) (bytes as Buffer).write(input as string, 0, bytes.byteLength, 'utf8');
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(aad);
  const encrypted = cipher.update(bytes);
  const final = cipher.final();
  const ciphertext = final.byteLength === 0 ? encrypted
    : Buffer.concat([encrypted, final]);
  // Every variable segment is Base64 ASCII. Preserve the historical field
  // order and bytes without a second complete JSON String/envelope backing.
  const segments = [
    '{"version":"actql-private-publication-evidence/0.1","nonce":"',
    nonce.toString('base64'),
    '","tag":"',
    cipher.getAuthTag().toString('base64'),
    '","ciphertext":"',
    ciphertext.toString('base64'),
    '"}',
  ];
  const envelopeBytes = segments.reduce((total, segment) => total + segment.length, 0);
  if (!Number.isSafeInteger(envelopeBytes) || envelopeBytes > maximum) {
    fail('PublicationObjectLimit');
  }
  const envelope = Buffer.alloc(envelopeBytes);
  let envelopeOffset = 0;
  for (const segment of segments) {
    envelopeOffset += envelope.write(segment, envelopeOffset, 'ascii');
  }
  if (envelopeOffset !== envelopeBytes) fail('PublicationPrivateEvidenceCorrupt');
  return envelope;
}

// Exact extent of the SAME closed format, not memory funding or a lease.
// Its 128 fixed ASCII bytes include the nonce/tag; ciphertext uses Base64.
// Inverting before multiplication keeps the calculation safe at large limits.
export function privateEvidenceWireLimitForObject(maximum: number) {
  if (maximum < 128) fail('PublicationObjectLimit');
  return 3 * Math.floor((maximum - 128) / 4);
}

// Recovery facade of the SAME Store writer, not another cleanup/capacity
// owner. A failed private preparation has no prepared object to return yet.
// Keep its original reservation/FD/custody reachable, and expose only cleanup.
export function retainPrivateWriterCleanup(writer: PrivateWriter) {
  let original: PrivateWriter | undefined = writer;
  let flight: Promise<boolean> | undefined;
  const pending = () => {
    if (original === undefined) return false;
    const state = original.status();
    return state.reservationHeld || state.custodyPending || state.cleanupPending;
  };
  const release = () => {
    if (flight !== undefined) return flight;
    if (!pending()) {
      original = undefined;
      return Promise.resolve(false);
    }
    const actual = original!;
    flight = Promise.resolve().then(() => actual.cancel()).then(result => {
      if (pending()) fail('PublicationPrivateWriterCleanupPending');
      // An escaped retired facade must not keep the original writer/Store
      // graph after the actual same cleanup has settled its responsibilities.
      original = undefined;
      return result;
    }).finally(() => { flight = undefined; });
    return flight;
  };
  const cleanup = Object.freeze({
    status: () => Object.freeze({pending: pending()}),
    release,
    async retry() { await release(); return cleanup.status(); },
  });
  return cleanup;
}

// A bounded view of the two original private-preparation duties: descriptor
// writer cleanup and the already prepared content. The same child owners
// perform retirement; this facade cannot write, commit or return their loans.
export function retainPrivateRawCleanup(descriptor: PrivateCleanup, content: PrivateCleanup) {
  let originals: [PrivateCleanup, PrivateCleanup] | undefined = [descriptor, content];
  let flight: Promise<boolean> | undefined;
  const pending = () => originals?.some(handle => handle.status().pending) === true;
  const release = () => {
    if (flight !== undefined) return flight;
    if (originals === undefined) return Promise.resolve(false);
    flight = Promise.resolve().then(async () => {
      for (const handle of originals!) {
        if (handle.status().pending) await handle.release();
      }
      if (pending()) fail('PublicationPrivateWriterCleanupPending');
      // Clear both references after their actual retirement, including on an
      // escaped facade. A false or thrown child release keeps the same pair.
      originals = undefined;
      return true;
    }).finally(() => { flight = undefined; });
    return flight;
  };
  const cleanup = Object.freeze({
    status: () => Object.freeze({pending: pending()}),
    release,
    async retry() { await release(); return cleanup.status(); },
  });
  return cleanup;
}

type EvidenceReadFailure = {code?: unknown; cleanupHandle?: unknown} | null | undefined;
type PrivateEvidenceRead = Readonly<{
  releaseBytes(): string;
  confirm(binding: unknown): Promise<SelectedPhysicalHoldingRecord>;
}>;
type ConsumeEvidence<Value> = (plaintext: Buffer, read: PrivateEvidenceRead) => Value;
type BeforeEvidenceRead = ((bytes: number) => undefined) & Readonly<{
  reserveEnvelope?: (wire: string) => undefined;
}>;
type ReadPrivateEvidence = {
  (name: string, semanticCid: string, holdingCid: string): Promise<Buffer>;
  <Value>(name: string, semanticCid: string, holdingCid: string,
    consume: ConsumeEvidence<Value>, beforeRead?: BeforeEvidenceRead): Promise<Awaited<Value>>;
};
type PrivateEvidenceReaderPorts = Readonly<{
  active(): unknown;
  cidHex(value: unknown): string;
  readPhysicalHolding: ReadPhysicalHolding;
  readPhysicalHoldingDeletion: ReadPhysicalHolding;
  consumeSelectedPhysicalHolding: ReturnType<typeof createPhysicalHoldingReaders>['consumeSelectedPhysicalHolding'];
  retainPhysicalHoldingReader: ReturnType<typeof createPhysicalHoldingReaders>['retainPhysicalHoldingReader'];
  confirmPhysicalHoldingDirectory(record: SelectedPhysicalHoldingRecord): Promise<unknown>;
  materialRetentionCurrent(): Promise<unknown>;
  retainMaterialOperation(operation: Promise<unknown>): void;
}>;

export function createPrivateEvidenceReader(
  configuration: Readonly<{maxObjectBytes: number; privateEvidenceKey?: Uint8Array}>,
  localContinuationEvidenceNames: readonly string[],
  {active, cidHex, readPhysicalHolding, readPhysicalHoldingDeletion, consumeSelectedPhysicalHolding,
    retainPhysicalHoldingReader, confirmPhysicalHoldingDirectory, materialRetentionCurrent, retainMaterialOperation}:
    PrivateEvidenceReaderPorts,
) {
  // Private evidence uses the prepared-object and physical-holding custody
  // already used by Transfer. A semantic alias before a durable owner would
  // strand ciphertext on a crash, so this path never creates one.
  // The Local continuation namespace holds only Local continuation evidence.
  const privateEvidenceHolding = (holding: SelectedPhysicalHoldingRecord | undefined, name: string): holding is SelectedPhysicalHoldingRecord =>
    holding?.namespace === 'publication-private' ||
    (holding?.namespace === 'local-continuation-private' &&
      localContinuationEvidenceNames.includes(name));
  const privateEvidenceAad = (name: string, semanticCid: string) => {
    const text = `actql-private-publication-evidence/0.1\0${name}\0${semanticCid}`;
    // Preserve the exact historical preimage without borrowing a larger pool
    // slab through crypto/read/cleanup. String/control and crypto scratch are
    // still separate original-envelope costs; exact extent is not a grant.
    const bytes = Buffer.allocUnsafeSlow(Buffer.byteLength(text, 'utf8'));
    bytes.write(text, 0, bytes.byteLength, 'utf8');
    return bytes;
  };
  const privateEvidenceKey = () => {
    if (configuration.privateEvidenceKey === undefined) {
      fail('PublicationPrivateEvidenceKeyUnavailable');
    }
    return configuration.privateEvidenceKey;
  };
  const privateEvidenceField = (value: unknown, bytes?: number) => {
    if (typeof value !== 'string' || value.length % 4 !== 0) {
      fail('PublicationPrivateEvidenceCorrupt');
    }
    // The selected holding already bounds this field. A repeated-group
    // regexp can exhaust the engine stack on a valid large ciphertext;
    // scan the same alphabet/padding grammar with constant workspace.
    const end = value.length - (value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0);
    for (let index = 0; index < end; index++) {
      const code = value.charCodeAt(index);
      if (!(code >= 65 && code <= 90 || code >= 97 && code <= 122 ||
          code >= 48 && code <= 57 || code === 43 || code === 47)) {
        fail('PublicationPrivateEvidenceCorrupt');
      }
    }
    // The bounded envelope and strict alphabet above fix the decoded extent.
    // Noncanonical padding bits still fail the same round-trip check below.
    // Keep nonce/tag/ciphertext on dedicated backings, not shared pool slices.
    const length = value.length / 4 * 3 - (value.length - end);
    if (bytes !== undefined && length !== bytes) {
      fail('PublicationPrivateEvidenceCorrupt');
    }
    const decoded = Buffer.allocUnsafeSlow(length);
    if (decoded.write(value, 0, length, 'base64') !== length ||
        decoded.toString('base64') !== value) {
      fail('PublicationPrivateEvidenceCorrupt');
    }
    return decoded;
  };
  const readPrivateEvidenceObject = async (
    name: string, semanticCid: string, holdingCid: string, index = 0, objectCount = 1,
    originalHolding?: SelectedPhysicalHoldingRecord,
    retainOriginalRead?: (holding: SelectedPhysicalHoldingRecord) => undefined,
    beforeEnvelope?: (wire: string) => undefined,
  ) => {
    active();
    if (typeof name !== 'string' || !/^[a-z][a-z0-9_]*$/u.test(name)) {
      fail('InvalidPublicationPrivateEvidence');
    }
    cidHex(semanticCid);
    cidHex(holdingCid);
    // This private getter reads the same immutable Store configuration with
    // no await/caller callback between size validation and copying. Do not add
    // an original-key alias to the async reader frame; only its copy escapes.
    const key = Buffer.allocUnsafeSlow(privateEvidenceKey().byteLength);
    key.set(privateEvidenceKey());
    try {
      // No plaintext or application callback escapes this private acquisition.
      // Admit the selected holding once; consume/hash its ciphertext once on
      // the original FD below, then authenticate AEAD before returning bytes.
      let holding = originalHolding;
      if (holding === undefined) {
        if (await readPhysicalHoldingDeletion(holdingCid) !== undefined) {
          fail('PublicationPrivateEvidenceUnavailable');
        }
        holding = await readPhysicalHolding(holdingCid);
      }
      if (!privateEvidenceHolding(holding, name) ||
          holding.manifest_cid !== semanticCid ||
          holding.objects.length !== objectCount) {
        fail('PublicationPrivateEvidenceUnavailable');
      }
      const expectedBytes = holding.objects[index].byte_count;
      if (!Number.isSafeInteger(expectedBytes) || expectedBytes < 0 ||
          expectedBytes > configuration.maxObjectBytes) {
        fail('PublicationPrivateEvidenceCorrupt');
      }
      if (retainOriginalRead !== undefined) {
        retainOriginalRead(holding);
        active();
      }
      // The existing holding owns an exact bounded file. Receive directly
      // into one buffer instead of retaining copied chunks plus their concat.
      // No bytes escape before the same physical read/close and AEAD succeed.
      const bytes = Buffer.alloc(expectedBytes);
      let receivedBytes = 0;
      try {
        await consumeSelectedPhysicalHolding(holding, index, chunk => {
          if (chunk.byteLength > expectedBytes - receivedBytes) {
            fail('InvalidPublicationPhysicalHoldingStore');
          }
          bytes.set(chunk, receivedBytes);
          receivedBytes += chunk.byteLength;
        });
      } catch (error) {
        if ((error as EvidenceReadFailure)?.code === 'ENOENT' &&
          (error as NonNullable<EvidenceReadFailure>).cleanupHandle === undefined) {
          fail('PublicationObjectMissing', error);
        }
        throw error;
      }
      if (receivedBytes !== expectedBytes) {
        fail('InvalidPublicationPhysicalHoldingStore');
      }
      // Initial SAME-Read reservation already covers bytes and this String.
      // The closed numeric envelope census then precedes any generic parser;
      // its typed Resource refusal is the primary cause, outside AEAD wrapping.
      const envelopeWire = bytes.toString('utf8');
      if (beforeEnvelope !== undefined) {
        if (typeof beforeEnvelope !== 'function' || beforeEnvelope(envelopeWire) !== undefined) {
          fail('InvalidPublicationPrivateEvidence');
        }
      }
      let plaintext: Buffer | undefined;
      try {
        let envelope: unknown;
        try { envelope = JSON.parse(envelopeWire); }
        catch (error) { fail('PublicationPrivateEvidenceCorrupt', error); }
        if (!exactKeys(envelope, ['version', 'nonce', 'tag', 'ciphertext']) ||
            envelope.version !== 'actql-private-publication-evidence/0.1') {
          fail('PublicationPrivateEvidenceCorrupt');
        }
        const nonce = privateEvidenceField(envelope.nonce, 12);
        const tag = privateEvidenceField(envelope.tag, 16);
        const ciphertext = privateEvidenceField(envelope.ciphertext);
        const decipher = createDecipheriv('aes-256-gcm', key, nonce);
        decipher.setAAD(privateEvidenceAad(name, semanticCid));
        decipher.setAuthTag(tag);
        plaintext = decipher.update(ciphertext);
        // Authentication must complete before any plaintext escapes. Reuse
        // the owned block only after final succeeds with no additional bytes;
        // otherwise preserve the complete authenticated concatenation.
        const final = decipher.final();
        return final.byteLength === 0 ? plaintext
          : Buffer.concat([plaintext, final]);
      } catch (error) {
        // update() can materialize unauthenticated plaintext before final()
        // rejects. That failed child never reaches the outer consumer, so its
        // SAME backing must be retired here rather than at consumer cleanup.
        plaintext?.fill(0);
        if ((error as EvidenceReadFailure)?.code === 'PublicationPrivateEvidenceCorrupt') throw error;
        fail('PublicationPrivateEvidenceCorrupt', error);
      }
    } finally {
      key.fill(0);
    }
  };
  const readPrivateEvidence = async <Value,>(name: string, semanticCid: string, holdingCid: string,
    consume?: ConsumeEvidence<Value>, beforeRead?: BeforeEvidenceRead) => {
    if (consume === undefined) {
      if (beforeRead !== undefined) fail('InvalidPublicationPrivateEvidence');
      return readPrivateEvidenceObject(name, semanticCid, holdingCid);
    }
    active();
    if (typeof consume !== 'function') fail('InvalidPublicationPrivateEvidence');
    cidHex(holdingCid);
    // The existing reader census protects this SAME private holding until
    // its trusted consumer has completed decode/admission, including awaits.
    // It supplies no memory credit or semantic/physical cleanup ACK. The
    // caller's original Request/Run reservation must precede acquisition.
    const release = retainPhysicalHoldingReader(holdingCid);
    let plaintext: Buffer | undefined, wire: string | undefined,
      record: SelectedPhysicalHoldingRecord | undefined, reading = true;
    const releaseBytes = () => {
      if (!reading) fail('PublicationPrivateEvidenceUnavailable');
      if (wire === undefined) {
        wire = plaintext!.toString('utf8');
        plaintext!.fill(0);
        plaintext = undefined;
      }
      return wire;
    };
    const context = Object.freeze({releaseBytes,
      confirm(binding: unknown) {
        if (!reading) fail('PublicationPrivateEvidenceUnavailable');
        if (!exactKeys(binding, ['name', 'semanticCid', 'holdingCid', 'wire']) ||
            binding.name !== name || binding.semanticCid !== semanticCid ||
            binding.holdingCid !== holdingCid || binding.wire !== releaseBytes()) {
          fail('PublicationPrivateEvidenceConflict');
        }
        const operation = materialRetentionCurrent().then(async () => {
          active();
          if (!reading) fail('PublicationPrivateEvidenceUnavailable');
          // This reader has already consumed/hashed/authenticated the SAME
          // immutable holding. Its original reader census still excludes
          // retirement; confirm that record without a second decrypt/parse.
          await confirmPhysicalHoldingDirectory(record!);
          return record!;
        });
        retainMaterialOperation(operation.catch(() => {}));
        return operation;
      }});
    try {
      plaintext = await readPrivateEvidenceObject(name, semanticCid, holdingCid, 0, 1,
        undefined, original => {
          record = original;
          if (beforeRead !== undefined) {
            if (typeof beforeRead !== 'function' || beforeRead(original.objects[0].byte_count) !== undefined) {
              fail('InvalidPublicationPrivateEvidence');
            }
          }
        }, beforeRead?.reserveEnvelope);
      return await consume(plaintext, context);
    } finally {
      // This overload never hands byte custody to its caller. Typed values
      // may retain their own strings; the temporary decrypted backing stops
      // here even when decode or its original child rejects.
      plaintext?.fill(0);
      reading = false;
      plaintext = wire = record = undefined;
      release();
    }
  };

  return {privateEvidenceAad, privateEvidenceKey, readPrivateEvidenceObject,
    readPrivateEvidence: readPrivateEvidence as ReadPrivateEvidence};
}
