import {runtimeCore} from '../host-common/runtime-core.mjs';
import {recoverCompletedEffectfulComputation} from
  '../host-common/completed-run-publication.mjs';

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
  signal,
}, loadRuntime) {
  if (typeof requests?.lookupOwnedDefinition !== 'function' ||
      typeof store?.storeAuthorityCid !== 'string' ||
      !text(principalId) || !text(key?.namespaceId) ||
      !text(key?.requestId) || !cid(key?.authorityScopeCid) ||
      !cid(key?.runDefinitionCid) ||
      typeof authorizeEvidenceRead !== 'function' ||
      typeof loadRuntime !== 'function' ||
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
  const computation = await recoverCompletedEffectfulComputation({
    store, control, runDefinition: retained.runDefinition,
    contractLimits: limits,
  });
  return Object.freeze({requestIdentity,
    requestScope: moon.clientRequestLogicalScope(requestIdentity),
    runDefinition: retained.runDefinition, computation});
}
