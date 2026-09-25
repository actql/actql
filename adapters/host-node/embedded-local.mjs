// One installed Local Host for the current OS user. The Client talks to the
// Host in process; the journal and publication Store own durable physical I/O.
import {createHash} from 'node:crypto';
import {mkdir, readFile} from 'node:fs/promises';
import {homedir, userInfo} from 'node:os';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {installNodeClientProgramPreparation} from
  './client-program-preparation.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {runPublishedCapturedStrategy} from './entry.mjs';
import {installNodeResultAccessService,
  installResultAccessAuthority} from './result-access.mjs';
import {installRunStateAuthority, installRunStateService,
  inspectAuthorizedRunState} from '../host-common/run-state-access.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {localContractLimits, localOutputLimits,
  sourceFreeValuesPlan} from './local-values-plan.mjs';

const packageRoot = fileURLToPath(new URL('../../', import.meta.url));
const runtimeUrl = new URL('../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const now = () => new Date().toISOString();
const cid = value => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
const plus = (date, milliseconds) => new Date(Date.parse(date) +
  milliseconds).toISOString();
const profiles = new Map();

function localStateRoot() {
  const supplied = process.env.ACTQL_LOCAL_STATE_DIR;
  if (supplied !== undefined && !supplied) {
    throw new TypeError('InvalidLocalStateDirectory');
  }
  return resolve(supplied ?? join(homedir(), '.local', 'share', 'actql'));
}

async function openInstalledHost(root, mode = 'local', beforeDispatch) {
  await mkdir(root, {recursive: true, mode: 0o700});
  const moon = await import(runtimeUrl.href);
  const control = runtimeCore(moon).publicationControl;
  const environmentWire = (await readFile(join(packageRoot,
    'spec/local-check-environment.json'), 'utf8')).trimEnd();
  const evidenceCid = JSON.parse(environmentWire).evidence_bundle_cid;
  const environment = moon.clientProgramCheckEnvironment(environmentWire,
    evidenceCid, false, false, true, false, false, false, false);
  if (environment === undefined) {
    throw new Error('InvalidInstalledLocalEnvironment');
  }
  const registry = await readFile(join(packageRoot,
    'spec/dependencies/aoa-pipeline-registry.json'), 'utf8');
  const aoa = JSON.parse(await readFile(join(packageRoot,
    'spec/contracts/actql-aoa.json'), 'utf8'));
  const values = JSON.stringify(aoa.execution_contracts['REL.values']);
  const fragment = JSON.stringify(
    aoa.execution_contracts['ACTQL.expression_fragment/0.1']);
  const ordered = JSON.stringify(
    aoa.execution_contracts['REL.derive.ordered']);
  const principalId = userInfo().username;
  const tenantId = 'local';
  const authorityScopeCid = cid({version: 'actql-local-owner-scope/0.1',
    root, principalId});
  const storeAuthorityCid = cid({version: 'actql-local-store-owner/0.1',
    root, principalId});
  const journalDirectory = join(root, 'requests');
  await mkdir(journalDirectory, {recursive: true, mode: 0o700});
  const journal = openClientRequestJournal(journalDirectory);
  let store;
  try {
    store = await openLocalPublicationStore({
      directory: join(root, 'publication'), storeAuthorityCid,
      capacityBytes: 512 * 1024 * 1024,
      maxObjectBytes: localOutputLimits.maxWireBytes,
      maxObjects: 10000, maxContractNodes: 10000,
      maxContractDepth: 64,
    }, control);
  } catch (error) {
    journal.close();
    throw error;
  }
  const hostConnection = ({principalId: actual, connection, ref}) =>
    actual === principalId &&
    connection.mode === mode && connection.owner === mode &&
    (ref === undefined || ref.tenantId === tenantId &&
      ref.authorityScopeCid === authorityScopeCid);
  const authorizedScope = ({principalId: actual}) =>
    actual === principalId ? {tenantId, authorityScopeCid} : undefined;
  const lookupRequest = installNodeClientRequestLookup({journal,
    control: moon, authorizedScope});
  const startRun = installNodeClientRunStart({journal,
    requestControl: moon, publicationControl: control,
    authorizeRunStart: ({principalId: actual, connection, ref}) =>
      hostConnection({principalId: actual, connection, ref})});
  const resultAuthority = installResultAccessAuthority({
    authorizeResultReadRequest: ({principalId: actual}) =>
      actual === principalId,
    admitResultRead: ({attemptId}) => ({
      authorizationContextCid: cid({version: 'actql-local-read/0.1',
        attemptId}),
      dataCeilingCid: cid({version: 'actql-local-read-ceiling/0.1'}),
      egressAdmissionCid: cid({version: 'actql-local-egress/0.1'}),
      expiresAt: plus(now(), 60 * 60 * 1000),
      maxBytes: localOutputLimits.maxWireBytes, maxUses: 1,
    }),
    authorizeResultRead: ({principalId: actual}) =>
      actual === principalId,
    authorizeDeliveryAttemptLookup: ({principalId: actual}) =>
      actual === principalId,
  });
  const resultService = installNodeResultAccessService({store, control,
    authority: resultAuthority, now, limits: localContractLimits,
    frameLimits: {maxRowBytes: 1024 * 1024, maxDepth: 64,
      maxFrameBytes: 1024 * 1024}});
  const stateService = installRunStateService({store, control,
    authority: installRunStateAuthority({
      authorizeRunState: ({principalId: actual}) => actual === principalId,
      resultPolicyAvailable: () => true,
    }), now, limits: localContractLimits});
  const attach = installNodeClientRunAttach({journal,
    requestControl: moon, publicationControl: control, authorizedScope,
    authorizeRun: ({ref, principalId: actual}) =>
      actual === principalId && ref.tenantId === tenantId &&
      ref.authorityScopeCid === authorityScopeCid});
  const prepareSubmit = installNodeClientProgramPreparation({moon,
    environment});
  const activeDispatches = new Map();
  const observeRun = async ({ref, principalId: actual}) => {
    if (actual !== principalId || ref.tenantId !== tenantId ||
        ref.authorityScopeCid !== authorityScopeCid) {
      throw new Error('RunStateAccessDenied');
    }
    const retained = journal.lookupRunDefinition(ref, moon, control);
    if (retained === undefined) throw new Error('RunStateAccessDenied');
    if (await store.confirmCommittedIndex(ref) !== undefined) {
      return inspectAuthorizedRunState(stateService, {
        indexKey: ref, principalId: actual, purpose: 'inspect',
      });
    }
    if (!Array.isArray(retained.resultNames)) {
      throw new Error('RunStateInventoryUnknown');
    }
    const wire = moon.clientProgramIssueUnpublishedRunState(
      control.runDefinitionRunId(retained.runDefinition), now(),
      retained.resultNames, retained.dispatchReserved,
      retained.preDispatchFailureConfirmed);
    if (wire === undefined) throw new Error('InvalidRunStateProjection');
    return JSON.parse(wire);
  };
  const wait = async ({ref, principalId: actual, until, signal}) => {
    if (until !== null && until !== 'terminal') {
      throw new Error('InvalidWaitCondition');
    }
    const current = await observeRun({ref, principalId: actual});
    if (['succeeded', 'failed', 'cancelled'].includes(current.status)) {
      return current;
    }
    const active = activeDispatches.get(ref.runDefinitionCid);
    if (active === undefined) return current;
    if (signal?.aborted) throw new Error('WaitAborted');
    let abort;
    const interrupted = new Promise((_, reject) => {
      abort = () => reject(new Error('WaitAborted'));
      signal?.addEventListener('abort', abort, {once: true});
    });
    try {
      await Promise.race([active.promise, interrupted]);
    } finally {
      signal?.removeEventListener('abort', abort);
    }
    return observeRun({ref, principalId: actual});
  };
  const submit = async ({preparedProgram, requestId, principalId: actual,
    connection, kind, input, parameters}) => {
    if (!hostConnection({principalId: actual, connection})) {
      throw new Error('ClientConnectionDenied');
    }
    const requested = moon.clientProgramRequestIdentity(preparedProgram,
      authorityScopeCid, requestId,
      moon.clientProgramSourceFreeInputIntentCid());
    if (requested === undefined) {
      throw new Error('ClientProgramNeedsInputs');
    }
    const resultNames = [];
    for (let index = 0;
      index < moon.clientProgramResultCount(preparedProgram); index++) {
      const name = moon.clientProgramResultName(preparedProgram, index);
      if (name === undefined) throw new Error('ClientProgramResultMissing');
      resultNames.push(name);
    }
    let plan;
    const accepted = await journal.admitOrLookupDefinition(requested, {
      tenantId, lookupExpiresAt: plus(now(), 7 * 24 * 60 * 60 * 1000),
      resultNames,
      issueDefinition: () => {
        plan = sourceFreeValuesPlan({moon, control, preparedProgram,
          document: kind === 'aql' ? input.text : JSON.stringify(input),
          format: kind === 'aql' ? input.format : 'json', parameters,
          environmentWire, environmentCid: evidenceCid,
          authorityScopeCid, tenantId, requestId, storeAuthorityCid, now});
        return plan.runDefinition;
      },
    }, moon, control);
    const unstarted = accepted.dispatchReserved !== true ||
      accepted.physicalStartReserved === false &&
      !accepted.preDispatchFailureConfirmed;
    if (!activeDispatches.has(accepted.ref.runDefinitionCid) && unstarted) {
      const active = {promise: undefined, reserved: false,
        physicalStarted: false, physicalStartClaimAttempted: false};
      activeDispatches.set(accepted.ref.runDefinitionCid, active);
      active.promise = Promise.resolve().then(async () => {
        const start = await startRun({identity: requested, tenantId,
          principalId: actual, connection});
        if (start.kind !== 'reserved' &&
            !(start.kind === 'reconcile' &&
              accepted.dispatchReserved === true &&
              accepted.physicalStartReserved === false &&
              !accepted.preDispatchFailureConfirmed)) return;
        active.reserved = true;
        if (beforeDispatch !== undefined) await beforeDispatch(start.ref);
        if (plan === undefined) {
          plan = sourceFreeValuesPlan({moon, control, preparedProgram,
            document: kind === 'aql' ? input.text : JSON.stringify(input),
            format: kind === 'aql' ? input.format : 'json', parameters,
            environmentWire, environmentCid: evidenceCid,
            authorityScopeCid, tenantId, requestId, storeAuthorityCid, now,
            retainedDefinitionWire: accepted.runDefinition.wire});
        }
        const setup = moon.clientProgramOpenSourceFreeLocalHost(
          preparedProgram, registry, values, 1n, 0n, 0n, 0n,
          fragment, ordered);
        if (setup === undefined) throw new Error('ClientProgramNeedsInputs');
        active.physicalStartClaimAttempted = true;
        if (!journal.reservePhysicalStart(requested, {
          tenantId, ref: accepted.ref,
          currentAuthorization: hostConnection({principalId: actual,
            connection, ref: accepted.ref}),
        }, moon, control)) return;
        active.physicalStarted = true;
        const published = await runPublishedCapturedStrategy(setup,
          {store, plan});
        await published.close();
        await published.cleanup();
      }).catch(async cause => {
        if (active.reserved && !active.physicalStartClaimAttempted) {
          try { journal.markPreDispatchFailure(accepted.ref); } catch {}
        }
        if (cause?.execution) {
          try { await cause.execution.close(); } catch {}
          try { await cause.execution.cleanup(); } catch {}
        }
      }).finally(() => {
        activeDispatches.delete(accepted.ref.runDefinitionCid);
      });
    }
    return {ref: accepted.ref, durability: accepted.durability,
      revision: accepted.revision};
  };
  const negotiate = () => ({version: 'actql-client-host/0.1',
    mode, owner: mode, durability: 'durable', scopeRef: principalId,
    capabilities: ['result-jsonl'], limits: {
      maxReadWireBytes: 10 * 1024 * 1024,
      maxRowWireBytes: 1024 * 1024,
      maxRowRetainedValueBytes: 1024 * 1024,
      maxRetainedValueBytes: 10 * 1024 * 1024,
      maxRows: 10000, maxBatchRows: 1000,
      maxBatchRetainedValueBytes: 10 * 1024 * 1024,
    }});
  const hostOperations = {
    authorizeConnection: hostConnection,
    negotiate, prepareSubmit, submit, attach, lookupRequest,
    stateService, resultService, observeRun, wait,
  };
  const port = createNodeInProcessClientHost({
    authenticate: () => principalId,
    ...hostOperations, maxRowBytes: 1024 * 1024,
  });
  return {port, store, journal, hostOperations};
}

// This HTTP ingress uses the installed Host's common owner and physical
// services. Embedded Local continues to use the in-process port above.
export async function openInstalledRemoteHttpHost({directory,
  authenticate, beforeDispatch}) {
  if (typeof directory !== 'string' || !directory ||
      typeof authenticate !== 'function' ||
      beforeDispatch !== undefined && typeof beforeDispatch !== 'function') {
    throw new TypeError('InvalidInstalledRemoteHost');
  }
  const host = await openInstalledHost(resolve(directory), 'remote',
    beforeDispatch);
  return Object.freeze({
    handler: createClientHttpHandler({
      ...host.hostOperations, authenticate, maxRequestBytes: 65536,
    }),
  });
}

export async function connectEmbeddedLocal(options) {
  const root = localStateRoot();
  let opened = profiles.get(root);
  if (opened === undefined) {
    opened = openInstalledHost(root);
    profiles.set(root, opened);
    opened.catch(() => profiles.delete(root));
  }
  const host = await opened;
  return connectInProcess(options, host.port);
}
