// Connect the common byte/candidate owner to the existing physical Store and
// ReferenceIssuer. This adapter has no encoder, identity codec, journal or
// cleanup state machine; the caller retains its original holding responsibility.
import {preparePrivatePublicationHolding} from '../host-common/private-publication-holding.mjs';

// Persist the exact common-issued input/derivation/generation inventory through
// the existing encrypted publication holdings. Register custody before any I/O;
// an uncertain commit is reconciled by that same holding, never by generating
// bytes again or inventing a new evidence identity.
export async function retainGeneratedContentEvidence({store, publications,
  compiled, generation, retainHoldings, signal}) {
  if (typeof retainHoldings !== 'function') {
    throw new TypeError('Content evidence requires retained cleanup custody');
  }
  const bindings = publications.checkedClientSerializationRecoveryBindings(
    compiled, generation, store.storeAuthorityCid);
  const holdings = Object.freeze(bindings.map(binding =>
    preparePrivatePublicationHolding(store, binding)));
  // The existing Run composition keeps these same handles even if registration
  // or a later Store operation fails. This adapter does not retire committed
  // holdings or assume that cancellation proves no write occurred.
  const recheck = () => {
    const current = publications.checkedClientSerializationRecoveryBindings(
      compiled, generation, store.storeAuthorityCid);
    if (current.length !== bindings.length || current.some((binding, index) =>
      ['name', 'semanticCid', 'holdingCid', 'wire'].some(key =>
        binding[key] !== bindings[index][key]))) {
      throw new TypeError('Content recovery binding changed');
    }
  };
  // Retrying sequences the same existing holding handles. It does not create
  // another preparation or retain a second commit/cleanup state machine.
  const retained = Object.freeze({bindings, holdings,
    async retry({signal: retrySignal = signal} = {}) {
      for (const holding of holdings) {
        retrySignal?.throwIfAborted();
        recheck();
        await holding.retry();
        retrySignal?.throwIfAborted();
        recheck();
      }
      return retained;
    }});
  retainHoldings(holdings, retained);
  return retained.retry();
}

export async function issueStoredGeneratedContent({store, control, candidate,
  holdingCid, workspaceScopeCid, effectiveDataPolicyCid, available,
  authorize, limits, retainOriginal}) {
  return issueStoredContent({store, control, candidate, holdingCid,
    workspaceScopeCid, effectiveDataPolicyCid, available, authorize, limits, retainOriginal},
  'GeneratedContent');
}

// Both provenances use the exact same physical custody and ReferenceIssuer
// boundary. Neither variant treats a provider envelope as proof of stored bytes.
export async function issueStoredCapturedContent(options) {
  return issueStoredContent(options, 'CapturedContent');
}

// Borrow bytes only after the enclosing Run owner has selected its original
// issued Content. The reader collection belongs to that same owner; this is
// neither a CID lookup capability nor another holding/cleanup owner.
export async function consumeStoredContentOriginal({store, original, readers,
  assertCurrent, accept}) {
  if (typeof accept !== 'function' || typeof assertCurrent !== 'function' ||
      original?.storeAuthorityCid !== store.storeAuthorityCid ||
      original.holding?.namespace !== 'content' || original.holding.objects.length !== 1) {
    throw new TypeError('InvalidStoredContentConsumer');
  }
  const read = {pending: true, cleanup: undefined};
  readers.add(read); // Retain before authority callbacks or acquiring the FD.
  try {
    assertCurrent();
    const result = await store.consumePhysicalHolding(original.holding.holding_cid, 0,
      async bytes => {
        assertCurrent();
        await accept(bytes);
        assertCurrent();
      });
    // consumePhysicalHolding confirms the full hash, version and original FD
    // close before returning. A delivered prefix is not publication evidence.
    assertCurrent();
    return result;
  } catch (cause) {
    if (cause?.cleanupHandle !== undefined) read.cleanup = cause.cleanupHandle;
    throw cause;
  } finally {
    read.pending = false;
    if (read.cleanup === undefined) readers.delete(read);
  }
}

export async function closeStoredContentReaders(readers) {
  for (const read of readers) {
    if (read.pending) return false;
    if (read.cleanup.status().pending) await read.cleanup.retry();
    if (read.cleanup.status().pending) return false;
    readers.delete(read);
  }
  return true;
}

async function issueStoredContent({store, control, candidate,
  holdingCid, workspaceScopeCid, effectiveDataPolicyCid, available,
  authorize, limits, retainOriginal}, prefix) {
  if (typeof available !== 'function' || typeof authorize !== 'function') {
    throw new TypeError('Missing Content holding authority callbacks');
  }
  if (retainOriginal !== undefined && typeof retainOriginal !== 'function') {
    throw new TypeError('InvalidContentOriginalReceiver');
  }
  const value = control.inspect(candidate);
  const fail = code => { throw Object.assign(new Error(code), {code}); };
  if (value.storeCid !== store.storeAuthorityCid ||
      value.workspaceScopeCid !== workspaceScopeCid ||
      value.effectiveDataPolicyCid !== effectiveDataPolicyCid) {
    fail(`${prefix}BindingMismatch`);
  }
  const live = () => available() === true && store.status().closed === false;
  if (!live()) fail(`${prefix}HoldingUnavailable`);
  const holding = await store.inspectPhysicalHolding(holdingCid);
  if (holding?.namespace !== 'content' ||
      holding.manifest_cid !== value.identity ||
      holding.objects.length !== 1 ||
      holding.objects[0].cid !== value.contentCid ||
      holding.objects[0].byte_count !== value.sizeBytes) {
    fail(`${prefix}HoldingMismatch`);
  }
  // Inspection alone does not confirm directory durability after a lost
  // commit response. Reconcile the exact holding, never generate/upload again.
  await store.commitPhysicalHolding(holding, []);
  if (!live()) fail(`${prefix}HoldingUnavailable`);
  const issuer = control.issuer((mediaType, wire) => live() &&
    (mediaType === undefined || mediaType === value.mediaType) &&
    wire === value.wire,
  // ReferenceIssuer passes the exact canonical envelope, not its identity CID.
  // Keep that occurrence check before consulting current authority by identity.
  wire => wire === value.wire && live() &&
    authorize(value.identity) === true);
  // Failure deliberately leaves the existing Store holding untouched. Its
  // cleanup/recovery owner, not this issuance adapter, decides lawful retirement.
  const issued = control.issue(candidate, issuer, limits);
  // The original issuer invokes Host authority callbacks synchronously. A
  // callback can retire availability even while returning its prior decision;
  // do not hand off that issued value without the same holding's current fence.
  if (!live()) fail(`${prefix}HoldingUnavailable`);
  if (retainOriginal !== undefined) {
    // Borrow the exact observation confirmed above, not a holding reconstructed
    // later from a Ref/CID. This private DATA/original binding is not a byte
    // loan, a read grant or proof of a consumer phase's allocation.
    const original = Object.freeze({candidate, issued, holding,
      storeAuthorityCid: store.storeAuthorityCid,
      workspaceScopeCid, effectiveDataPolicyCid});
    if (retainOriginal(original) !== undefined) {
      throw new TypeError('InvalidContentOriginalReceiver');
    }
    // The existing Source/holding receiver may begin retirement synchronously.
    // Its prior successful issuance does not permit a late handoff.
    if (!live()) fail(`${prefix}HoldingUnavailable`);
  }
  return issued;
}
