import {publicationOriginalFixture} from './fixtures/local-publication-original.mjs';
import {checked} from '../host-common/runtime-result.mjs';
// Real checked Program, physical Run, publication Store and Delivery custody.
// The injected fault loses only attempt admission's reply, never retries it.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRunStateAuthority, installRunStateService,
  inspectAuthorizedRunState} from '../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientSubmission} from './client-submission.mjs';
import {runPublishedCapturedStrategy} from './entry.mjs';
import {localContractLimits, localOutputLimits, sourceFreeValuesPlan,
  sourceFreeValuesAdmissionEvidence} from './local-values-plan.mjs';
import {installNodeResultAccessService, installResultAccessAuthority} from './result-access.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const now = () => '2026-10-07T00:00:00.000Z';
const scope = {namespaceId: 'opening-fixture', authorityScopeCid: cid('a')};
const control = runtimeCore(moon).publicationControl;
export const openingProgram = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'));
export const openingExpected = [{id: 1}, {id: 2}];
export function traceReadRecovery(phase, facts = {}) {
  if (process.env.ACTQL_READ_RECOVERY_TRACE !== '1') return;
  console.error('ACTQL_READ_RECOVERY_TRACE ' + JSON.stringify({
    phase, pid: process.pid, at: Date.now(), ...facts}));
}
export async function openReadOpeningFixture(directory, loss,
  {valuesMaxRows, expectedRowCount = 2, expressionFragment = false,
    observeSubmission = () => {}, reverseRereads = false} = {}) {
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
  const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
    'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
    false, false, true, false, false, false, false);
  assert.ok(environment);
  const registry = await readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
  const contracts = JSON.parse(await readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  const values = JSON.stringify(contracts.execution_contracts['REL.values']);
  const fragment = expressionFragment ? JSON.stringify(
    contracts.execution_contracts['ACTQL.expression_fragment/0.1']) : undefined;
  const installedContracts = checked(moon.clientPrepareInstalledSequenceContracts(
    registry, values, fragment, undefined));
  const startRun = installNodeClientRunStart({journal, requestControl: moon, publicationControl: control, authorizeRunStart: () => true});
  const services = {
    authenticate: () => 'principal', authorizeConnection: () => true,
    negotiate: async () => ({version: 'actql-client-host/0.1', mode: 'local', owner: 'local', durability: 'durable', scopeRef: 'principal', capabilities: ['result-jsonl'],
      submissionEpoch: journal.issueSubmissionEpoch({...scope, currentAuthorization: true}, moon),
      limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536, maxRows: 256, maxBatchRows: 16, maxBatchRetainedValueBytes: 8192}}),
    prepareSubmit: installNodeClientProgramPreparation({moon, environment, valuesMaxRows}),
    attach: installNodeClientRunAttach({journal, requestControl: moon, publicationControl: control, authorizedScope: () => scope, authorizeRun: () => true}),
    lookupRequest: installNodeClientRequestLookup({journal, control: moon,
      authorizedScope: () => allowed ? scope : undefined}),
    async submit({preparedProgram, requestId, principalId, connection, submission}) {
      observeSubmission('prepared');
      const identity = moon.clientProgramRequestIdentity(preparedProgram, cid('a'), requestId, cid('b'));
      let plan;
      const admitted = await journal.admitOrLookupDefinition(identity, {...scope, submission, lookupExpiresAt: '2099-01-01T00:00:00.000Z', issueDefinition() {
        counts.definitions++;
        plan = sourceFreeValuesPlan({moon, control, preparedProgram, publicationOriginal: publicationOriginalFixture(moon, preparedProgram), ...scope, storeAuthorityCid: cid('7'), now});
        const evidence = sourceFreeValuesAdmissionEvidence(plan);
        return evidence === undefined ? plan.runDefinition : {
          runDefinition: plan.runDefinition, runAdmissionEvidence: evidence};
      }}, moon, control);
      observeSubmission('admitted');
      const started = await startRun({identity, namespaceId: scope.namespaceId, principalId, connection});
      assert.deepEqual(started.ref, admitted.ref);
      if (started.kind !== 'reserved') return {ref: started.ref,
        durability: started.durability, revision: started.revision};
      counts.computes++;
      const setup = moon.clientProgramOpenSourceFreeLocalHost(preparedProgram, installedContracts, values, 1n, 0n, 0n, 0n, fragment);
      assert.ok(setup);
      observeSubmission('opened');
      let published;
      try {published = await runPublishedCapturedStrategy(setup, {store, plan});}
      catch (error) {observeSubmission('publication_failed', error); throw error;}
      observeSubmission('published');
      assert.equal(published.status, 'published');
      assert.equal(published.execution.status, 'host-tasks-completed');
      assert.equal(published.execution.completed[0].outputRows, expectedRowCount);
      assert.equal(published.publication.publication.state, 'succeeded');
      await published.close(); assert.equal(published.cleanupPending(), false);
      return {ref: started.ref, durability: started.durability, revision: started.revision};
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
    prepareSubmit: request => services.prepareSubmit(request), submit: services.submit,
    lookupRequest: services.lookupRequest});
  services.submitIntent = submission.submitAttempt;
  services.lookupSubmission = submission.lookupSubmission;
  return {services, counts, store, journal, deliveryOrders,
    retainedAdmission: ref => journal.lookupRunDefinition(ref, moon, control)?.runAdmissionEvidence,
    beforeSuccessRecord: callback => {beforeSuccessRecord = callback;},
    beforeRow: callback => {beforeRow = callback;},
    afterDeliveryLookup: callback => {afterDeliveryLookup = callback;},
    arm: phase => {armed = phase;}, authorize: value => {allowed = value;},
    loseReply: callback => {loseReply = callback;},
    async close() {journal.close(); await store.close();}};
}

export async function connectOpeningHost(fixture, entrance, tlsDirectory,
  {loseReadTerminator = false, deliveryLookupReply, runObservationReply} = {}) {
  let armed = loseReadTerminator, terminatorLosses = 0;
  if (entrance === 'local') {
    const host = createNodeInProcessClientHost(fixture.services);
    const port = {async perform(operation, ...args) {
      const response = await host.perform(operation, ...args);
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
