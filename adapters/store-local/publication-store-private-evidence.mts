import {createCipheriv, randomBytes} from 'node:crypto';
import type {createObjectWriterOwner} from './object-writer-owner.mjs';
import {fail} from './publication-store-io.mjs';

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
