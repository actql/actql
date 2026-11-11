import {checked} from '../host-common/runtime-result.mjs';
// Real checked Program, physical Run, publication Store and Delivery custody.
// The injected fault loses only attempt admission's reply, never retries it.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createServer} from 'node:https';
import {types} from 'node:util';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {prepareClientHostRequest} from '../../packages/client-wire/index.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRunStateAuthority, installRunStateService,
  inspectAuthorizedRunState} from '../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {openFundedClientPreparation} from './funded-client-preparation.fixture.mjs';
import {installLocalPreparationRegistry} from './local-preparation-registry.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {runPublishedCapturedStrategy} from './entry.mjs';
import {localContractLimits, localOutputLimits, sourceFreeValuesPlan,
  sourceFreeValuesAdmissionEvidence, sourceFreePlanOriginal} from './local-values-plan.mjs';
import {installNodeResultAccessService, installResultAccessAuthority} from './result-access.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const now = () => '2026-10-07T00:00:00.000Z';
const scope = {namespaceId: 'opening-fixture', authorityScopeCid: cid('a')};
const control = runtimeCore(moon).publicationControl;
export const openingProgram = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'));
export const openingExpected = [{id: 1}, {id: 2}];

// The original registry invokes this light continuation after returning its
// actual handler/dispatch borrowers. Its lexical scope retains no Prepared.
function finishManagedReadRetirement(run, manager, liveManaged) {
  return () => {
    checked(moon.clientProgramInstalledManagedRunRetire(run.value));
    manager.retireSeveredPreparation(run.original);
    liveManaged.delete(run);
    for (const name of Object.keys(run)) run[name] = undefined;
    run.retired = true;
  };
}
export function traceReadRecovery(phase, facts = {}) {
  if (process.env.ACTQL_READ_RECOVERY_TRACE !== '1') return;
  console.error('ACTQL_READ_RECOVERY_TRACE ' + JSON.stringify({
    phase, pid: process.pid, at: Date.now(), ...facts}));
}
function traceReadRecoveryFailure(phase, cause) {
  if (process.env.ACTQL_READ_RECOVERY_TRACE !== '1') return;
  const fields = {};
  if (cause !== null && typeof cause === 'object' && !types.isProxy(cause)) {
    for (const name of ['name', 'message', 'code']) {
      const field = Object.getOwnPropertyDescriptor(cause, name);
      if (field !== undefined && Object.hasOwn(field, 'value') && typeof field.value === 'string') {
        fields[name] = field.value.slice(0, 1024);
      }
    }
  }
  traceReadRecovery(phase, {failure: fields});
}
export async function openReadOpeningFixture(directory, loss,
  {valuesMaxRows, expectedRowCount = 2, expressionFragment = false,
    observeSubmission = () => {}, reverseRereads = false, environment: selectedEnvironment} = {}) {
  assert.equal(typeof reverseRereads, 'boolean');
  if (reverseRereads) assert.equal(expectedRowCount, 2);
  traceReadRecovery('store-open:start', {expectedRowCount});
  const store = await openLocalPublicationStore({directory: join(directory, 'publication'),
    storeAuthorityCid: cid('7'), capacityBytes: 512 * 1024 * 1024,
    maxObjectBytes: localOutputLimits.maxWireBytes, maxObjects: 10000,
    maxContractNodes: 100000, maxContractDepth: 64}, control);
  traceReadRecovery('store-open:finished');
  const journal = openClientRequestJournal(join(directory, 'requests'));
  traceReadRecovery('journal-open:finished');
  const counts = {admissions: 0, readers: 0, computes: 0, definitions: 0};
  const deliveryOrders = [];
  let allowed = true, armed = loss, loseReply, beforeSuccessRecord, beforeRow,
    afterDeliveryLookup;
  const observed = {...store,
    async lookupDeliveryAttempt(request) {
      const found = await store.lookupDeliveryAttempt(request);
      await afterDeliveryLookup?.(found);
      return found;
    },
    async appendDeliveryRecord(wire) {
      const state = JSON.parse(wire).state;
      traceReadRecovery('delivery-record:start', {state});
      if (state === 'succeeded') await beforeSuccessRecord?.();
      const recording = store.appendDeliveryRecord(wire);
      if (process.env.ACTQL_READ_RECOVERY_TRACE !== '1') return recording;
      const recorded = await recording;
      traceReadRecovery('delivery-record:finished', {state});
      return recorded;
    },
    // Observe the actual installed START owner, preserving its opaque original
    // and atomic initial streaming record rather than the legacy wire adapter.
    async beginDeliveryAttempt(original, streaming) {
      counts.admissions++;
      const phase = armed; armed = undefined;
      traceReadRecovery('delivery-admission:start', {loss: phase ?? null});
      if (phase === 'before-commit') { loseReply?.(); throw new Error('InjectedOpeningReplyLoss'); }
      const committed = await store.beginDeliveryAttempt(original, streaming);
      traceReadRecovery('delivery-admission:committed', {loss: phase ?? null});
      if (phase === 'after-commit') { loseReply?.(); throw new Error('InjectedOpeningReplyLoss'); }
      return committed;
    },
    // The installed completion path commits the receipt and terminal record
    // together. Hold that same original operation, never a fabricated ACK.
    async appendDeliveryCompletion(attempt, receipt, contract) {
      traceReadRecovery('delivery-record:start', {state: 'succeeded'});
      await beforeSuccessRecord?.();
      const recorded = await store.appendDeliveryCompletion(attempt, receipt, contract);
      traceReadRecovery('delivery-record:finished', {state: 'succeeded'});
      return recorded;
    },
    async withCommittedResultRows(...args) {
      counts.readers++;
      const reverse = reverseRereads && counts.readers > 1;
      const use = args[4];
      args[4] = (metadata, readRows) => use(metadata, async accept => {
        const order = [];
        deliveryOrders.push(order);
        const emit = async (row, index) => {
          order.push(row); await beforeRow?.(index); return accept(row, index);
        };
        if (!reverse) return readRows(emit);
        // Only this bounded two-row fixture changes enumeration. The Store
        // verifies the original payload before the real Delivery Owner emits
        // the same rows in another order; no Result identity is fabricated.
        assert.equal(metadata.rowCount, 2);
        const rows = [];
        const summary = await readRows((row, index) => { rows.push({row, index}); });
        assert.equal(rows.length, 2);
        for (const {row, index} of rows.reverse()) await emit(row, index);
        return summary;
      });
      return store.withCommittedResultRows(...args);
    },
  };
  const authority = installResultAccessAuthority({
    authorizeResultReadRequest: () => allowed,
    admitResultRead: facts => ({authorizationContextCid: `sha256:${createHash('sha256').update(facts.attemptId).digest('hex')}`,
      dataCeilingCid: cid('9'), egressAdmissionCid: cid('a'),
      expiresAt: '2026-10-07T00:59:00.000Z', maxBytes: 65536, maxUses: 1}),
    authorizeResultRead: () => allowed,
    authorizeDeliveryAttemptLookup: () => allowed,
    authorizeResultDescription: () => allowed,
    admitResultDescription: facts => ({authorizationContextCid: `sha256:${createHash('sha256').update(facts.attemptId).digest('hex')}`,
      dataCeilingCid: cid('9'), egressAdmissionCid: cid('a'),
      expiresAt: '2026-10-07T00:59:00.000Z', maxBytes: 65536, maxUses: 1}),
  });
  const resultService = installNodeResultAccessService({store: observed, control, authority,
    now, limits: localContractLimits,
    frameLimits: {maxRowBytes: 4096, maxDepth: 32, maxFrameBytes: 4096}});
  const stateService = installRunStateService({store, control,
    authority: installRunStateAuthority({authorizeRunState: () => true, resultPolicyAvailable: () => true}), now, limits: localContractLimits});
  const environmentWire = await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8');
  const environment = selectedEnvironment ?? moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
    'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
    false, false, true, false, false, false, false);
  assert.ok(environment);
  const contracts = JSON.parse(await readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  const values = JSON.stringify(contracts.execution_contracts['REL.values']);
  const fragment = expressionFragment ? JSON.stringify(
    contracts.execution_contracts['ACTQL.expression_fragment/0.1']) : undefined;
  const funded = await openFundedClientPreparation({moon, environment, valuesMaxRows, http: true,
    sequenceContracts: {values, fragment, ordered: undefined}});
  const managed = new WeakMap(), liveManaged = new Set(), reservations = new WeakMap();
  // Use the ordinary registry's real Core siblings and dispatch retirement.
  // This private fixture supplies no Root, capacity packet or no-op borrower.
  const preparationCustody = installLocalPreparationRegistry(prepared =>
    funded.prepare.kindOf(prepared) === 'effect_free' &&
      moon.clientProgramAcquisitionCount(prepared) === 0 &&
      moon.clientProgramSerializationOccurrences(prepared).length === 0 &&
      checked(moon.clientProgramComposedInferOccurrences(prepared)).length === 0,
  prepared => {
    const run = managed.get(prepared);
    if (run === undefined) return;
    if (run.retired) return run.finish;
    try {checked(moon.clientProgramInstalledManagedRunRetire(run.value));}
    catch (cause) {
      if (moon.clientProgramInstalledPreparationPayloadSevered(run.value, run.request) !== true) throw cause;
    }
    run.plan = undefined;
    funded.retireOriginal(prepared);
    funded.manager.severPreparation(prepared, run.original);
    run.prepared = undefined;
    run.retired = true;
    run.finish = finishManagedReadRetirement(run, funded.manager, liveManaged);
    return run.finish;
  }, {runtime: moon, borrow: (prepared, request) =>
    funded.manager.borrowPreparation(prepared, funded.originalRequest(request))});
  const startRun = installNodeClientRunStart({journal, requestControl: moon, publicationControl: control,
    authorizeRunStart: () => true});
  const dispatch = installNodeClientDispatchOwner({moon, control, journal, store,
    registry: funded.installedContracts, values, fragment,
    namespaceId: scope.namespaceId, authorityScopeCid: scope.authorityScopeCid,
    storeAuthorityCid: cid('7'), now, hostConnection: () => true,
    startRun: async facts => {
      const started = await startRun(facts);
      reservations.set(facts.identity, started);
      return started;
    },
    preparationCustody, managedComputeRequired: true,
    beforePublication: prepared => funded.manager.reservePublication(prepared),
    observed: (phase, detail) => traceReadRecovery(phase, Object.fromEntries(
      ['code', 'primaryCode', 'issueTag', 'nestedIssueTag']
        .filter(name => typeof detail?.[name] === 'string')
        .map(name => [name, detail[name]]))),
    planFor: ({preparedProgram}, retainedWire) => {
      const run = managed.get(preparedProgram);
      assert.ok(run && !run.retired);
      assert.equal(run.plan.runDefinition.wire, retainedWire);
      return run.plan;
    },
    faultInjection: stage => {
      if (stage === 'dispatch_reserved') counts.computes++;
      if (stage === 'physical_start_reserved') observeSubmission('opened');
      if (stage === 'computed') observeSubmission('published');
    },
    runPublished: async (...args) => {
      let published;
      try {published = await runPublishedCapturedStrategy(...args);}
      catch (error) {observeSubmission('publication_failed', error); throw error;}
      assert.equal(published.status, 'published');
      assert.equal(published.execution.status, 'host-tasks-completed');
      assert.equal(published.execution.completed[0].outputRows, expectedRowCount);
      assert.equal(published.publication.publication.state, 'succeeded');
      return published;
    }});
  const services = {
    authenticate: () => 'principal', authorizeConnection: () => true,
    negotiate: async () => ({version: 'actql-client-host/0.1', mode: 'local', owner: 'local', durability: 'durable', scopeRef: 'principal', capabilities: ['result-jsonl'],
      submissionEpoch: journal.issueSubmissionEpoch({...scope, currentAuthorization: true}, moon),
      limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536, maxRows: 256, maxBatchRows: 16, maxBatchRetainedValueBytes: 8192}}),
    prepareSubmit: funded.prepareSubmit, prepareRequest: funded.prepareRequest,
    bindOwnedRequest: funded.submission.bindOwnedRequest,
    attach: installNodeClientRunAttach({journal, requestControl: moon, publicationControl: control, authorizedScope: () => scope, authorizeRun: () => true}),
    lookupRequest: installNodeClientRequestLookup({journal, control: moon,
      authorizedScope: () => allowed ? scope : undefined}),
    async submit(submission) {
      try {
      const {preparedProgram, requestId} = submission;
      observeSubmission('prepared');
      const identity = moon.clientProgramRequestIdentity(preparedProgram, cid('a'), requestId, cid('b'));
      const adopted = funded.manager.adoptPreparation(preparedProgram,
        funded.originalRequest(submission), identity);
      assert.ok(adopted);
      const run = {prepared: preparedProgram, request: identity, original: adopted.original,
        value: adopted.value, plan: undefined, retired: false};
      managed.set(preparedProgram, run);liveManaged.add(run);
      checked(moon.clientProgramInstalledManagedRunCheck(run.value, preparedProgram, identity));
      traceReadRecovery('managed-plan-original-check:start');
      const acquisitionResult = checked(moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication(
        run.value, preparedProgram, identity));
      traceReadRecovery('managed-plan-original-check:finished', {requiresAcquisitionResult: acquisitionResult});
      const admitted = await journal.admitOrLookupDefinition(identity, {...scope, submission: submission.submission,
        lookupExpiresAt: '2099-01-01T00:00:00.000Z', issueDefinition() {
        counts.definitions++;
        run.plan = sourceFreeValuesPlan({moon, control, preparedProgram,
          requestIdentity: identity, ...scope, storeAuthorityCid: cid('7'), now,
          compilationOriginal: funded.manager.compilationOriginal(preparedProgram),
          publicationOriginal: {kind: 'installed_run', value: run.value},
          publicationPreparation: funded.manager.publicationPreparation(preparedProgram)});
        const evidence = sourceFreeValuesAdmissionEvidence(run.plan);
        return evidence === undefined ? run.plan.runDefinition : {
          runDefinition: run.plan.runDefinition, runAdmissionEvidence: evidence,
          originalPlan: sourceFreePlanOriginal(run.plan)};
      }}, moon, control);
      observeSubmission('admitted');
      await dispatch.start(submission, identity, admitted, {plan: run.plan, managedRun: run.value});
      await dispatch.operation(admitted.ref);
      const started = reservations.get(identity);
      assert.ok(started);
      assert.deepEqual(started.ref, admitted.ref);
      return {ref: started.ref, durability: started.durability, revision: started.revision};
      } catch (cause) {traceReadRecoveryFailure('submit:failed', cause); throw cause;}
    },
    async observeRun({ref, principalId}) {
      // Match the ordinary Host: only the same original journal frame and
      // confirmed publication observation may issue a current Run state.
      for (let attempt = 0; attempt < 8; attempt++) {
        const retained = journal.lookupRunDefinition(ref, moon, control);
        const state = await inspectAuthorizedRunState(stateService, {
          indexKey: ref, principalId, purpose: 'inspect',
        });
        const after = journal.lookupRunDefinition(ref, moon, control);
        if (after?.revision !== retained?.revision) continue;
        assert.ok(retained, 'Observation requires the original accepted Run');
        try {
          return JSON.parse(journal.publishRunState(retained, state, moon, control));
        } catch (error) {
          if (error?.code === 'RunStateObservationChanged') continue;
          throw error;
        }
      }
      throw new Error('RunStateObservationUnstable');
    }, resultService, stateService, maxRowBytes: 1024,
  };
  const submission = installNodeClientSubmission({journal, moon,
    authorizedScope: () => allowed ? scope : undefined,
    prepareSubmit: services.prepareSubmit, submit: services.submit,
    lookupRequest: services.lookupRequest, preparationCustody, ...funded.submission});
  services.submitIntent = submission.submitAttempt;
  services.lookupSubmission = submission.lookupSubmission;
  return {services, counts, store, journal, deliveryOrders,
    retainedAdmission: ref => journal.lookupRunDefinition(ref, moon, control)?.runAdmissionEvidence,
    beforeSuccessRecord: callback => {beforeSuccessRecord = callback;},
    beforeRow: callback => {beforeRow = callback;},
    afterDeliveryLookup: callback => {afterDeliveryLookup = callback;},
    arm: phase => {armed = phase;}, authorize: value => {allowed = value;},
    loseReply: callback => {loseReply = callback;},
    async close() {
      await dispatch.drain();
      preparationCustody.retireQuiescentUndispatched();
      await funded.close();
      assert.equal(liveManaged.size, 0);
      journal.close(); await store.close();
    }};
}

export async function connectOpeningHost(fixture, entrance, tlsDirectory,
  {loseReadTerminator = false, deliveryLookupReply, runObservationReply} = {}) {
  let armed = loseReadTerminator, terminatorLosses = 0;
  if (entrance === 'local') {
    const host = createNodeInProcessClientHost(fixture.services);
    const port = {async perform(operation, body, signal) {
      let original;
      let terminal = 'failed';
      try {
      // Match HTTP's already-captured immutable connection. This existing
      // connect-only wire check observes no Program or Parameters and must
      // precede the Request parent's own source snapshot.
      const connection = prepareClientHostRequest('connect', {connection: body.connection})?.connection;
      assert.ok(connection, 'Existing wire owner must admit the original connection');
      original = fixture.services.prepareRequest(operation, Object.freeze({...body, connection}));
      original.bindRequest(original.body);
      const response = await host.perform(operation, original.body, signal);
      original.beforeReply();
      terminal = 'returned';
      if (operation === 'status' && runObservationReply) {
        const replacement = runObservationReply(response);
        if (replacement === undefined) throw new Error('InjectedRunObservationLoss');
        return replacement;
      }
      if (operation === 'delivery-attempt' && deliveryLookupReply) {
        const replacement = deliveryLookupReply(response);
        if (replacement === undefined) throw new Error('InjectedDeliveryLookupLoss');
        return replacement;
      }
      if (operation !== 'read' || !armed) return response;
      armed = false;
      return {kind: 'rows', frames: {async *[Symbol.asyncIterator]() {
        yield* response.frames;
        // Lose only the final iterator acknowledgement, after the actual
        // delivery owner has committed success and its release receipt.
        terminatorLosses++;
        throw new Error('InjectedReadTerminatorLoss');
      }}};
      } catch (cause) {traceReadRecoveryFailure('local-request:failed', cause); throw cause;}
      finally {original?.finish(terminal);}
    }};
    const client = await connectInProcess({mode: 'local', owner: 'local'},
      port);
    return {client, endpoint: 'actql:embedded', settled: async () => {},
      terminatorLosses: () => terminatorLosses, close: () => client.close()};
  }
  const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(tlsDirectory, name))));
  const originalCAs = getCACertificates('default');
  setDefaultCACertificates([...originalCAs, cert.toString('utf8')]);
  const negotiate = fixture.services.negotiate;
  const handler = createClientHttpHandler({...fixture.services,
    negotiate: async () => ({...await negotiate(), mode: 'remote', owner: 'remote'})});
  const pending = new Set();
  const server = createServer({key, cert}, (request, response) => {
    if (request.url.endsWith('/status') && runObservationReply) {
      const end = response.end.bind(response);
      response.end = (bytes, ...args) => {
        const replacement = runObservationReply(JSON.parse(bytes));
        if (replacement === undefined) {response.destroy(); return response;}
        return end(JSON.stringify(replacement), ...args);
      };
    }
    if (request.url.endsWith('/delivery-attempt') && deliveryLookupReply) {
      const end = response.end.bind(response);
      response.end = (bytes, ...args) => {
        // Fault injection occurs after the real authorized Owner lookup.
        const replacement = deliveryLookupReply(JSON.parse(bytes));
        if (replacement === undefined) {response.destroy(); return response;}
        return end(typeof replacement === 'string' ? replacement : JSON.stringify(replacement), ...args);
      };
    }
    if (request.url.endsWith('/read')) {
      fixture.loseReply(() => response.destroy());
      if (armed) {
        armed = false;
        const write = response.write.bind(response);
        response.write = (bytes, ...args) => {
          if (bytes.byteLength === 1 && bytes[0] === 0x1e) {
            // EOF still arrives normally. Remove the payload terminator
            // downstream of the real owner without changing any row.
            terminatorLosses++;
            return write(Buffer.alloc(0), ...args);
          }
          return write(bytes, ...args);
        };
      }
    }
    const operation = handler(request, response);
    pending.add(operation);
    operation.finally(() => pending.delete(operation));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const endpoint = `https://127.0.0.1:${server.address().port}/`;
  const client = await connect({mode: 'remote', token: 'fixture-token', endpoint});
  return {client, endpoint, settled: () => Promise.all([...pending]),
    terminatorLosses: () => terminatorLosses, async close() {
    await client.close(); server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await Promise.all([...pending]);
    setDefaultCACertificates(originalCAs);
  }};
}
