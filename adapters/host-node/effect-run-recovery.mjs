import {runtimeCore} from '../host-common/runtime-core.mjs';
import {recoverCompletedEffectfulComputation} from
  '../host-common/completed-run-publication.mjs';
import {PublicationStoreError} from '../store-local/publication-store.mjs';
import {runUpdateSelectionCid, originalUpdateTargetSelectionsCid} from './update-target-original-shape.mjs';

const captureRefusals = new WeakSet();
export const isEffectCaptureRecoveryRefusal = error =>
  error !== null && typeof error === 'object' && captureRefusals.has(error);

const cid = value => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/.test(value);
const text = value => typeof value === 'string' && value.length > 0 &&
  value.length <= 256 && !/[\u0000-\u001f\u007f]/u.test(value);
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Installed Host recovery only reopens an accepted request and its captured
// computation. It has no Compute, mutation credential, or physical send port.
// Current apply admission remains a separate step after evidence recovery.
export async function recoverAdmittedEffectRun({
  requests, store, key, principalId, authorizeEvidenceRead, contractLimits,
  signal, restoreOriginal, prepareRecoveryResources, retainRecoveryResources,
}, loadRuntime) {
  if (typeof requests?.lookupOwnedDefinition !== 'function' ||
      typeof store?.storeAuthorityCid !== 'string' ||
      !text(principalId) || !text(key?.namespaceId) ||
      !text(key?.requestId) || !cid(key?.authorityScopeCid) ||
      !cid(key?.runDefinitionCid) ||
      typeof authorizeEvidenceRead !== 'function' ||
      typeof loadRuntime !== 'function' ||
      (prepareRecoveryResources !== undefined && typeof prepareRecoveryResources !== 'function') ||
      (retainRecoveryResources !== undefined && typeof retainRecoveryResources !== 'function') ||
      (restoreOriginal !== undefined && typeof restoreOriginal !== 'function') ||
      !['maxWireBytes', 'maxNodes', 'maxDepth'].every(name =>
        Number.isSafeInteger(contractLimits?.[name]) &&
        contractLimits[name] > 0)) {
    fail('InvalidAdmittedEffectRecovery');
  }
  const lookup = requests.lookupOwnedDefinition.bind(requests);
  const ownedKey = Object.freeze({namespaceId: key.namespaceId,
    authorityScopeCid: key.authorityScopeCid, requestId: key.requestId,
    runDefinitionCid: key.runDefinitionCid});
  const limits = Object.freeze({maxWireBytes: contractLimits.maxWireBytes,
    maxNodes: contractLimits.maxNodes, maxDepth: contractLimits.maxDepth});
  const binding = Object.freeze({...ownedKey, principalId,
    storeAuthorityCid: store.storeAuthorityCid,
    purpose: 'recover-effect-evidence'});
  signal?.throwIfAborted();
  // Denial must not reveal whether the request or its private capture exists.
  if (await authorizeEvidenceRead(binding) !== true) {
    fail('EffectEvidenceAccessDenied');
  }
  signal?.throwIfAborted();
  const moon = await loadRuntime();
  signal?.throwIfAborted();
  const control = runtimeCore(moon).publicationControl;
  const retained = lookup(ownedKey, moon, control);
  if (retained === undefined ||
      retained.runDefinition?.identity !== ownedKey.runDefinitionCid) {
    fail('EffectRecoveryRequestMismatch');
  }
  const requestIdentity = retained.requestIdentity;
  if (moon.clientRequestAuthorityScopeCid(requestIdentity) !==
      ownedKey.authorityScopeCid ||
      moon.clientRequestCallerId(requestIdentity) !== ownedKey.requestId) {
    fail('EffectRecoveryRequestMismatch');
  }
  // Bind saved original materials to this independently selected journal Run
  // before any capture Store read or provider recovery. This never resolves a
  // logical name or creates a replacement Run.
  const original = restoreOriginal?.(retained, requestIdentity) ?? {};
  if (typeof original?.then === 'function') {
    void Promise.resolve(original).catch(() => {});
    fail('EffectRecoveryOriginalSelectionUnavailable');
  }
  const selectionCid = runUpdateSelectionCid(retained.runDefinition, moon);
  let originalMatches = false;
  try {
    originalMatches = selectionCid === undefined ? original.updateTargetSelections === undefined :
      Array.isArray(original.updateTargetSelections) &&
      typeof original.assertUpdateSelectionCurrent === 'function' &&
      originalUpdateTargetSelectionsCid(original.updateTargetSelections, moon) === selectionCid;
  } catch { /* An unowned DATA copy cannot become original custody. */ }
  if (!originalMatches) {
    fail('EffectRecoveryOriginalSelectionUnavailable');
  }
  const assertOriginalCurrent = () => {
    const current = original.assertUpdateSelectionCurrent?.();
    if (typeof current?.then === 'function') {
      void Promise.resolve(current).catch(() => {});
      fail('EffectRecoveryOriginalSelectionUnavailable');
    }
  };
  assertOriginalCurrent();
  let computation, recoveryResources;
  try {
    if (prepareRecoveryResources !== undefined) {
      const selected = prepareRecoveryResources({moon, control, requestIdentity,
        runDefinition: retained.runDefinition, contractLimits: limits,
        assertOriginalCurrent, retain(original) {
          if (recoveryResources !== undefined && recoveryResources !== original) {
            fail('EffectRecoveryResourcesUnavailable');
          }
          recoveryResources = original;
          retainRecoveryResources?.(original);
        }});
      if (typeof selected?.then === 'function') {
        void Promise.resolve(selected).catch(() => {});
        fail('EffectRecoveryResourcesUnavailable');
      }
      if (selected !== recoveryResources) fail('EffectRecoveryResourcesUnavailable');
      if (!['begin', 'reserve', 'finish', 'retainCleanup', 'close'].every(name =>
          typeof recoveryResources?.[name] === 'function')) fail('EffectRecoveryResourcesUnavailable');
    }
    signal?.throwIfAborted();
    computation = await recoverCompletedEffectfulComputation({
      store, control, runDefinition: retained.runDefinition,
      contractLimits: limits,
    }, recoveryResources);
    signal?.throwIfAborted();
    assertOriginalCurrent();
  } catch (error) {
    // The original resource frame is already in the Host bag. Dispose only
    // its actual constructed children; a pending/failed close stays there for
    // that same Host's existing retry without replacing the primary cause.
    try {await recoveryResources?.close();} catch { /* Same retained cleanup. */ }
    // Only a Store's confirmed missing/corrupt object, after exact request
    // and evidence-read admission, is a definitive custody refusal. EIO,
    // timeouts and caller-created code strings carry no such conclusion.
    if (error instanceof PublicationStoreError &&
        ['PublicationObjectMissing', 'PublicationObjectCorrupt']
          .includes(error.code)) captureRefusals.add(error);
    throw error;
  }
  return Object.freeze({requestIdentity,
    ...original,
    requestScope: moon.clientRequestLogicalScope(requestIdentity),
    runDefinition: retained.runDefinition, computation,
    ...(recoveryResources === undefined ? {} : {recoveryResources})});
}
