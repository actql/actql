// Physical Host composition for the shared Effect compiler and Run owner.
// The request journal applies MoonBit's atomic start decisions. This adapter
// never schedules Effect apply or interprets a provider's unknown outcome.
import {randomUUID} from 'node:crypto';
import {runtimeCore} from '../host-common/runtime-core.mjs';
export {openClientRequestJournal} from './client-request-journal.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';

const limits = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000,
  maxDepth: 100});
const denied = () => Object.assign(new Error('ClientEffectRunDenied'),
  {code: 'ClientEffectRunDenied'});

export function installNodeClientEffectRun({moon,
  publicationControl: control = runtimeCore(moon).publicationControl,
  journal, authorizeRequest, authorizeRunStart, execute}) {
  if (typeof authorizeRequest !== 'function' || typeof execute !== 'function' ||
      typeof journal?.reservePhysicalStart !== 'function') {
    throw new TypeError('InvalidClientEffectRunInstallation');
  }
  const startRun = installNodeClientRunStart({journal, requestControl: moon,
    publicationControl: control, authorizeRunStart});
  const handles = new WeakMap();
  const admitEvidence = (name, wire) => checked(
    moon.strategyRunEvidenceAdmit(name, wire, limits.maxWireBytes,
      limits.maxNodes, limits.maxDepth));
  const definitionToken = definition => checked(moon.strategyPublicationAdmit(
    'run_definition', definition.wire, limits.maxWireBytes,
    limits.maxNodes, limits.maxDepth));
  return Object.freeze({
    async accept({prepared, authorityScopeCid, requestId, tenantId,
      principalId, connection, lookupExpiresAt}) {
      // Authentication/current acceptance authority precedes even lookup, so
      // a caller cannot infer the presence of another caller's request.
      const policy = await authorizeRequest(Object.freeze({prepared,
        authorityScopeCid, requestId, tenantId, principalId, connection}));
      if (policy === null || typeof policy !== 'object') throw denied();
      const identity = moon.clientProgramEffectRequestIdentity(prepared,
        authorityScopeCid, requestId, moon.clientProgramSourceFreeInputIntentCid());
      if (identity === undefined) throw denied();
      let compilation;
      const compile = () => compilation ??= checked(
        moon.clientProgramCompileLocalEffects(prepared));
      const accepted = await journal.admitOrLookupDefinition(identity, {
        tenantId, lookupExpiresAt,
        issueDefinition() {
          const allowed = checked(moon.clientProgramIssueAllowedEffectRun(
            compile(), policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt));
          const definition = checked(moon.clientProgramIssueEffectRunDefinition(
            allowed, tenantId, randomUUID(), policy.createdAt, policy.expiresAt));
          return {
            resultNames: moon.clientProgramEffectCompilationResultNames(compile()),
            runDefinition: control.admit('run_definition',
              moon.strategyPublicationContractJson(definition), limits),
            runAdmissionEvidence: {
              prepared: moon.strategyRunEvidenceJson(
                moon.clientProgramAllowedEffectRunPrepared(allowed)),
              authorization: moon.strategyRunEvidenceJson(
                moon.clientProgramAllowedEffectRunAuthorization(allowed)),
            },
          };
        },
      }, moon, control);
      const handle = Object.freeze({ref: accepted.ref,
        durability: accepted.durability, revision: accepted.revision,
        lookupExpiresAt: accepted.lookupExpiresAt});
      handles.set(handle, {prepared, identity, tenantId, principalId,
        connection, compile});
      return handle;
    },
    async start(handle) {
      const owned = handles.get(handle);
      if (owned === undefined) throw denied();
      const {prepared, identity, tenantId, principalId, connection, compile} = owned;
      const start = await startRun({identity, tenantId, principalId, connection});
      const retained = journal.resolveDefinition(identity, {tenantId}, moon, control);
      const evidence = retained.runAdmissionEvidence;
      if (evidence === undefined) {
        throw Object.assign(new Error('ClientEffectRunEvidenceMissing'),
          {code: 'ClientEffectRunEvidenceMissing', ref: retained.ref});
      }
      const compilation = compile();
      const allowed = checked(moon.clientProgramAdmitAllowedEffectRun(compilation,
        admitEvidence('prepared_invocation', evidence.prepared),
        admitEvidence('run_authorization', evidence.authorization)));
      const definition = definitionToken(retained.runDefinition);
      const owner = checked(moon.clientProgramBindCompiledEffectRun(
        prepared, allowed, definition));
      // Recheck current start authority immediately before the atomic physical
      // claim. The original authorization remains bound to the saved Run.
      let authorized = false;
      try {
        authorized = await authorizeRunStart(Object.freeze({tenantId,
          principalId, connection, ref: retained.ref,
          runDefinition: retained.runDefinition}));
      } catch { /* A failed current authority observation fails closed. */ }
      if (!journal.reservePhysicalStart(identity, {tenantId, ref: start.ref,
        currentAuthorization: authorized === true}, moon, control)) {
        return Object.freeze({kind: 'reconcile', ref: start.ref});
      }
      // Only the claim winner receives the bound owner. The callback owns all
      // capture/apply/publication and cleanup, including after a thrown error.
      // No catch path resets the durable physical-start claim.
      const value = await execute(Object.freeze({ref: start.ref, identity,
        owner, prepared, compilation, allowed, definition,
        runDefinition: retained.runDefinition}));
      return Object.freeze({kind: 'started', ref: start.ref, value});
    },
  });
}
