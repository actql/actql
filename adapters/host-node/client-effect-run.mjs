// Physical Host composition for the shared Effect compiler and Run owner.
// The request journal applies MoonBit's atomic start decisions. This adapter
// never schedules Effect apply or interprets a provider's unknown outcome.
import {randomUUID} from 'node:crypto';
import {runtimeCore} from '../host-common/runtime-core.mjs';
export {openClientRequestJournal} from './client-request-journal.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {issuedEffectSetReceiptWires} from
  '../host-common/effect-receipt-custody.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';

const limits = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000,
  maxDepth: 100});
const denied = () => Object.assign(new Error('ClientEffectRunDenied'),
  {code: 'ClientEffectRunDenied'});
const expired = ref => Object.assign(new Error('ClientEffectRunExpired'),
  {code: 'ClientEffectRunExpired', ref});
const unsupported = () => Object.assign(new Error('ClientProgramUnsupported'),
  {code: 'ClientProgramUnsupported'});

export function installNodeClientEffectRun({moon,
  publicationControl: control = runtimeCore(moon).publicationControl,
  journal, authorizeRequest, authorizeRunStart, prepareExecution, execute,
  now = () => new Date().toISOString()}) {
  if (typeof moon?.clientProgramEffectCompilationIssueCode !== 'function' ||
      typeof authorizeRequest !== 'function' ||
      (prepareExecution !== undefined &&
        typeof prepareExecution !== 'function') ||
      typeof execute !== 'function' ||
      typeof journal?.reservePhysicalStart !== 'function' ||
      typeof now !== 'function' ||
      typeof moon?.clientProgramEffectRunStartCurrent !== 'function') {
    throw new TypeError('InvalidClientEffectRunInstallation');
  }
  const startRun = installNodeClientRunStart({journal, requestControl: moon,
    publicationControl: control, authorizeRunStart});
  const handles = new WeakMap();
  const compilations = new WeakMap();
  const compile = prepared => {
    if (prepared === null || typeof prepared !== 'object') throw denied();
    let compilation = compilations.get(prepared);
    if (compilation !== undefined) return compilation;
    const outcome = moon.clientProgramCompileLocalEffects(prepared);
    if (moon.clientProgramEffectCompilationIssueCode(outcome) ===
        'unsupported_program') throw unsupported();
    compilation = checked(outcome);
    compilations.set(prepared, compilation);
    return compilation;
  };
  const admitEvidence = (name, wire) => checked(
    moon.strategyRunEvidenceAdmit(name, wire, limits.maxWireBytes,
      limits.maxNodes, limits.maxDepth));
  const definitionToken = definition => checked(moon.strategyPublicationAdmit(
    'run_definition', definition.wire, limits.maxWireBytes,
    limits.maxNodes, limits.maxDepth));
  return Object.freeze({
    // A held Run-acceptance Checkpoint must never be opened for a Program
    // this installed Host cannot compile. The exact compiled owner is reused
    // by acceptance; this check neither issues a Run nor starts physical I/O.
    checkSupported(prepared) { compile(prepared); },
    // Record the public state of a started Run whose complete admitted Effect
    // Set has unknown outcomes. The owner names exactly those Effects; the
    // journal keeps the state for status and reconcile in any later process.
    // Nothing is resent, and no answer or Store write relabels the outcome.
    // `issuedSet` must be the exact Set the receipt owner issued for this
    // ledger and Preview, as for publication.
    recordReconciliation(ref, {issuedSet, ledger, preview,
      updatedAt = now()}) {
      const retained = journal.lookupRunDefinition(ref, moon, control);
      if (retained === undefined || retained.resultNames === undefined) {
        throw denied();
      }
      const runId = JSON.parse(retained.runDefinition.wire).run_id;
      const receipts = issuedEffectSetReceiptWires(issuedSet, ledger, preview);
      const wire = control.effectReconciliationRunState(preview, receipts,
        {runId, updatedAt, resultNames: retained.resultNames}, limits);
      journal.recordReconciliationState(ref, wire);
      return JSON.parse(wire);
    },
    // The recorded reconciliation state of a Run, or undefined. Reading it
    // performs no provider I/O and never starts or resends work.
    reconciliation(ref) {
      const wire = journal.lookupReconciliationState(ref);
      return wire === undefined ? undefined : Object.freeze(JSON.parse(wire));
    },
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
      const compiled = () => compile(prepared);
      const accepted = await journal.admitOrLookupDefinition(identity, {
        tenantId, lookupExpiresAt,
        issueDefinition() {
          const allowed = checked(moon.clientProgramIssueAllowedEffectRun(
            compiled(), policy.executionContextCid, policy.hostPolicyCid,
            policy.expiresAt));
          const definition = checked(moon.clientProgramIssueEffectRunDefinition(
            allowed, tenantId, randomUUID(), policy.createdAt, policy.expiresAt));
          if (!moon.clientProgramEffectRunStartCurrent(allowed,
            definition, now())) throw expired();
          return {
            resultNames: moon.clientProgramEffectCompilationResultNames(
              compiled()),
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
        connection, compile: compiled});
      return handle;
    },
    async start(handle, {beforePhysicalStart, started, signal} = {}) {
      const owned = handles.get(handle);
      if (owned === undefined ||
          beforePhysicalStart !== undefined &&
            typeof beforePhysicalStart !== 'function' ||
          started !== undefined && typeof started !== 'function') {
        throw denied();
      }
      const {prepared, identity, tenantId, principalId, connection, compile} = owned;
      const start = await startRun({identity, tenantId, principalId, connection});
      const retained = journal.resolveDefinition(identity, {tenantId}, moon, control);
      if (retained.physicalStartReserved !== false ||
          retained.preDispatchFailureConfirmed) {
        return Object.freeze({kind: 'reconcile', ref: start.ref});
      }
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
      if (authorized === true &&
          !moon.clientProgramEffectRunStartCurrent(allowed,
            definition, now())) {
        // This Run never crossed the physical boundary. A concurrent winner
        // may have claimed it, in which case its unknown outcome is retained.
        try { journal.markPreDispatchFailure(start.ref); }
        catch (cause) {
          const latest = journal.resolveDefinition(identity, {tenantId},
            moon, control);
          if (latest?.physicalStartReserved !== false) {
            return Object.freeze({kind: 'reconcile', ref: start.ref});
          }
          throw cause;
        }
        throw expired(start.ref);
      }
      signal?.throwIfAborted();
      let preparedExecution;
      if (prepareExecution !== undefined && authorized === true) {
        try {
          preparedExecution = prepareExecution(Object.freeze({ref: start.ref,
            identity, owner, prepared, compilation, allowed, definition,
            runDefinition: retained.runDefinition}));
          if (typeof preparedExecution?.then === 'function') {
            throw new TypeError('AsyncClientEffectPreparation');
          }
        } catch (error) {
          try { journal.markPreDispatchFailure(start.ref); }
          catch (observationFailure) {
            const latest = journal.resolveDefinition(identity, {tenantId},
              moon, control);
            if (latest?.physicalStartReserved !== false) {
              return Object.freeze({kind: 'reconcile', ref: start.ref});
            }
            throw Object.assign(new Error('ClientEffectPreparationUnknown',
              {cause: error}), {code: 'ClientEffectPreparationUnknown',
              primaryFailure: error, observationFailure, ref: start.ref});
          }
          throw error;
        }
      }
      // A resumed Checkpoint enters its current claim immediately before the
      // durable physical-start reservation. The answer alone is not a send
      // permit; no asynchronous work separates these two admissions.
      beforePhysicalStart?.();
      if (!journal.reservePhysicalStart(identity, {tenantId, ref: start.ref,
        currentAuthorization: authorized === true}, moon, control)) {
        return Object.freeze({kind: 'reconcile', ref: start.ref});
      }
      started?.();
      // Only the claim winner receives the bound owner. The callback owns all
      // capture/apply/publication and cleanup, including after a thrown error.
      // No catch path resets the durable physical-start claim.
      const value = await execute(Object.freeze({ref: start.ref, identity,
        owner, prepared, compilation, allowed, definition,
        runDefinition: retained.runDefinition, preparedExecution, signal}));
      return Object.freeze({kind: 'started', ref: start.ref, value});
    },
  });
}
