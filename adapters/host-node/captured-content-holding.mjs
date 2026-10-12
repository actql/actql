// Physical I/O for a common checked capture candidate. Byte identity and Ref
// construction remain common; Store and the caller's existing capture/holding
// owner retain reservations and retry handles. No second capture journal exists.
import {issueStoredCapturedContent} from './generated-content-holding.mjs';

export async function retainCapturedContent({store, control, candidate, bytes,
  holdingCid, workspaceScopeCid, effectiveDataPolicyCid, retainCustody,
  available, authorize, limits, signal}) {
  if (!(bytes instanceof Uint8Array) || typeof retainCustody !== 'function' ||
      typeof available !== 'function' || typeof authorize !== 'function') {
    throw new TypeError('Captured Content requires bytes and existing custody');
  }
  signal?.throwIfAborted();
  const description = control.inspect(candidate);
  if (description.storeCid !== store.storeAuthorityCid ||
      description.workspaceScopeCid !== workspaceScopeCid ||
      description.effectiveDataPolicyCid !== effectiveDataPolicyCid ||
      description.sizeBytes !== bytes.byteLength || available() !== true) {
    throw Object.assign(new Error('CapturedContentBindingMismatch'),
      {code: 'CapturedContentBindingMismatch'});
  }
  const writer = store.createPreparedObjectWriter(description.sizeBytes);
  // The caller takes each same Store handle before its next I/O, including if
  // its registration response is uncertain. It must retain that responsibility
  // on exceptions; this adapter never guesses that a failed commit wrote nothing.
  await retainCustody(Object.freeze({writer}));
  signal?.throwIfAborted();
  await writer.append(bytes);
  // Store verifies the actual received bytes against the common candidate's
  // digest. Caller/provider metadata alone cannot establish byte custody.
  const physical = await writer.seal(description.contentCid);
  await retainCustody(Object.freeze({prepared: physical.prepared}));
  signal?.throwIfAborted();
  const holding = Object.freeze({version: 'actql-local-physical-holding/0.1',
    namespace: 'content', holding_cid: holdingCid, manifest_cid: description.identity,
    objects: Object.freeze([Object.freeze({cid: physical.cid, byte_count: physical.bytes})])});
  await retainCustody(Object.freeze({holding}));
  signal?.throwIfAborted();
  await store.commitPhysicalHolding(holding, [physical.prepared]);
  signal?.throwIfAborted();
  const value = await issueStoredCapturedContent({store, control, candidate,
    holdingCid, workspaceScopeCid, effectiveDataPolicyCid, available, authorize, limits});
  signal?.throwIfAborted();
  return Object.freeze({value, wire: description.wire, holding});
}
