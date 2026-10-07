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
import {installRunStateAuthority, installRunStateService} from '../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
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
export async function openReadOpeningFixture(directory, loss,
  {valuesMaxRows, expectedRowCount = 2, observeSubmission = () => {}} = {}) {
  const store = await openLocalPublicationStore({directory: join(directory, 'publication'),
    storeAuthorityCid: cid('7'), capacityBytes: 512 * 1024 * 1024,
    maxObjectBytes: localOutputLimits.maxWireBytes, maxObjects: 10000,
    maxContractNodes: 100000, maxContractDepth: 64}, control);
  const journal = openClientRequestJournal(join(directory, 'requests'));
  const counts = {admissions: 0, readers: 0, computes: 0, definitions: 0};
  let allowed = true, armed = loss, loseReply, beforeSuccessRecord, beforeRow;
  const observed = {...store,
    async appendDeliveryRecord(wire) {
      if (JSON.parse(wire).state === 'succeeded') await beforeSuccessRecord?.();
      return store.appendDeliveryRecord(wire);
    },
    async createDeliveryAttempt(wire, grantWire) {
      counts.admissions++;
      const phase = armed; armed = undefined;
      if (phase === 'before-commit') { loseReply?.(); throw new Error('InjectedOpeningReplyLoss'); }
      const committed = await store.createDeliveryAttempt(wire, grantWire);
      if (phase === 'after-commit') { loseReply?.(); throw new Error('InjectedOpeningReplyLoss'); }
      return committed;
    },
    async withCommittedResultRows(...args) {
      counts.readers++;
      const use = args[4];
      args[4] = (metadata, readRows) => use(metadata, accept =>
        readRows(async (row, index) => {await beforeRow?.(index); return accept(row, index);}));
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
  const startRun = installNodeClientRunStart({journal, requestControl: moon, publicationControl: control, authorizeRunStart: () => true});
  const services = {
    authenticate: () => 'principal', authorizeConnection: () => true,
    negotiate: () => ({version: 'actql-client-host/0.1', mode: 'local', owner: 'local', durability: 'durable', scopeRef: 'principal', capabilities: ['result-jsonl'],
      limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536, maxRows: 256, maxBatchRows: 16, maxBatchRetainedValueBytes: 8192}}),
    prepareSubmit: installNodeClientProgramPreparation({moon, environment, valuesMaxRows}),
    attach: installNodeClientRunAttach({journal, requestControl: moon, publicationControl: control, authorizedScope: () => scope, authorizeRun: () => true}),
    lookupRequest: installNodeClientRequestLookup({journal, control: moon,
      authorizedScope: () => allowed ? scope : undefined}),
    async submit({preparedProgram, requestId, principalId, connection}) {
      observeSubmission('prepared');
      const identity = moon.clientProgramRequestIdentity(preparedProgram, cid('a'), requestId, cid('b'));
      let plan;
      const admitted = await journal.admitOrLookupDefinition(identity, {...scope, lookupExpiresAt: '2099-01-01T00:00:00.000Z', issueDefinition() {
        counts.definitions++;
        plan = sourceFreeValuesPlan({moon, control, preparedProgram, ...scope, storeAuthorityCid: cid('7'), now});
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
      const setup = moon.clientProgramOpenSourceFreeLocalHost(preparedProgram, registry, values, 1n, 0n, 0n, 0n);
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
    }, resultService, stateService, maxRowBytes: 1024,
  };
  return {services, counts, store, journal,
    retainedAdmission: ref => journal.lookupRunDefinition(ref, moon, control)?.runAdmissionEvidence,
    beforeSuccessRecord: callback => {beforeSuccessRecord = callback;},
    beforeRow: callback => {beforeRow = callback;},
    arm: phase => {armed = phase;}, authorize: value => {allowed = value;},
    loseReply: callback => {loseReply = callback;},
    async close() {journal.close(); await store.close();}};
}

export async function connectOpeningHost(fixture, entrance, tlsDirectory) {
  if (entrance === 'local') {
    const client = await connectInProcess({mode: 'local', owner: 'local'},
      createNodeInProcessClientHost(fixture.services));
    return {client, settled: async () => {}, close: () => client.close()};
  }
  const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(tlsDirectory, name))));
  const originalCAs = getCACertificates('default');
  setDefaultCACertificates([...originalCAs, cert.toString('utf8')]);
  const negotiate = fixture.services.negotiate;
  const handler = createClientHttpHandler({...fixture.services,
    negotiate: () => ({...negotiate(), mode: 'remote', owner: 'remote'})});
  const pending = new Set();
  const server = createServer({key, cert}, (request, response) => {
    if (request.url.endsWith('/read')) fixture.loseReply(() => response.destroy());
    const operation = handler(request, response);
    pending.add(operation);
    operation.finally(() => pending.delete(operation));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const client = await connect({mode: 'remote', token: 'fixture-token',
    endpoint: `https://127.0.0.1:${server.address().port}/`});
  return {client, settled: () => Promise.all([...pending]), async close() {
    await client.close(); server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await Promise.all([...pending]);
    setDefaultCACertificates(originalCAs);
  }};
}
