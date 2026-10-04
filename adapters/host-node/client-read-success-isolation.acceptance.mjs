// Pending S8 acceptance: requires an admitted execution profile for 121 rows.
// Current fixed 100-row compilation rejects this before read; do not shrink
// the required 120-row prefix or fabricate successful Run/publication facts.
// Explicitly select this file with the bounded Node wrapper after connecting
// the existing execution owner's larger admitted profile. It is not included
// in automatic passing test selections while that owner dependency is open.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test, {after} from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {connect, connectInProcess} from '../../packages/sdk/index.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRunStateAuthority, installRunStateService} from '../host-common/run-state-access.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {runPublishedCapturedStrategy} from './entry.mjs';
import {localContractLimits, localOutputLimits, sourceFreeValuesPlan} from './local-values-plan.mjs';
import {installNodeResultAccessService, installResultAccessAuthority} from './result-access.mjs';

const scratch = new URL('../../_build/client-read-success-isolation/', import.meta.url).pathname;
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: tlsRoot, stdio: 'ignore'});
const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(tlsRoot, name))));
const originalCAs = getCACertificates('default');
setDefaultCACertificates([...originalCAs, cert.toString('utf8')]);
after(async () => {
  setDefaultCACertificates(originalCAs);
  await rm(tlsRoot, {recursive: true, force: true});
});
const cid = value => `sha256:${value.repeat(64)}`;
const now = () => '2026-10-04T00:00:00.000Z';
const control = runtimeCore(moon).publicationControl;
const environmentWire = await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8');
const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
  false, false, true, false, false, false, false);
assert.ok(environment);
const registry = await readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8');
const contracts = JSON.parse(await readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
const values = JSON.stringify(contracts.execution_contracts['REL.values']);
const program = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'));
// Expected input and output are fixed independently of the executed product.
const expected = Array.from({length: 121}, (_, index) => ({id: index + 1}));
program.stages[0].steps[0].values.rows = expected;

async function installed(t, entrance, consumedPrefix) {
  const directory = await mkdtemp(join(scratch, 'store-'));
  const store = await openLocalPublicationStore({directory: join(directory, 'publication'),
    storeAuthorityCid: cid('7'), capacityBytes: 8 * 1024 * 1024,
    maxObjectBytes: localOutputLimits.maxWireBytes, maxObjects: 1000,
    maxContractNodes: 100000, maxContractDepth: 64}, control);
  const journal = openClientRequestJournal(join(directory, 'requests'));
  const scope = {namespaceId: 'namespace-a', authorityScopeCid: cid('a')};
  let published, plan, computes = 0, definitions = 0, rowReaders = 0, client, server, submitFailure;
  const operations = [], attempts = [], handlerSettlements = [];
  const faultStore = {...store,
    async createDeliveryAttempt(wire, grantWire) {
      const accepted = await store.createDeliveryAttempt(wire, grantWire);
      attempts.push(accepted);
      return accepted;
    },
    async withCommittedResultRows(index, definition, authorize, limits, use, frameControl) {
      const ordinal = ++rowReaders;
      return store.withCommittedResultRows(index, definition, authorize, limits,
        (metadata, readRows) => use(metadata, async accept => readRows(async (row, position) => {
          if (ordinal === 1 && position === 120) {
            await consumedPrefix;
            throw new Error('InjectedPublishedRowFailure');
          }
          return accept(row, position);
        })), frameControl);
    },
  };
  const authority = installResultAccessAuthority({
    authorizeResultReadRequest: () => true,
    admitResultRead: facts => ({authorizationContextCid: `sha256:${createHash('sha256')
      .update(facts.attemptId).digest('hex')}`, dataCeilingCid: cid('9'),
    egressAdmissionCid: cid('a'), expiresAt: '2026-10-04T00:59:00.000Z',
    maxBytes: 65536, maxUses: 1}),
    authorizeResultRead: () => true,
    authorizeDeliveryAttemptLookup: () => true,
  });
  const resultService = installNodeResultAccessService({store: faultStore, control, authority,
    now, limits: localContractLimits,
    frameLimits: {maxRowBytes: 4096, maxDepth: 32, maxFrameBytes: 4096}});
  const stateService = installRunStateService({store, control,
    authority: installRunStateAuthority({authorizeRunState: () => true, resultPolicyAvailable: () => true}),
    now, limits: localContractLimits});
  const startRun = installNodeClientRunStart({journal, requestControl: moon,
    publicationControl: control, authorizeRunStart: () => true});
  const services = {
    authenticate: () => 'principal',
    authorizeConnection: ({operation}) => { operations.push(operation); return true; },
    negotiate: () => ({version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
      durability: 'durable', scopeRef: 'principal', capabilities: ['result-jsonl'],
      limits: {maxReadWireBytes: 65536, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 65536,
        maxRows: 256, maxBatchRows: 16, maxBatchRetainedValueBytes: 8192}}),
    prepareSubmit: installNodeClientProgramPreparation({moon, environment}),
    async submit({preparedProgram, requestId, principalId, connection}) {
      const identity = moon.clientProgramRequestIdentity(preparedProgram, cid('a'), requestId, cid('b'));
      const admitted = await journal.admitOrLookupDefinition(identity, {...scope,
        lookupExpiresAt: '2099-01-01T00:00:00.000Z', issueDefinition: () => {
          definitions++;
          plan = sourceFreeValuesPlan({moon, control, preparedProgram, ...scope,
            storeAuthorityCid: cid('7'), now});
          return plan.runDefinition;
        }}, moon, control);
      const started = await startRun({identity, namespaceId: scope.namespaceId, principalId, connection});
      assert.deepEqual(started.ref, admitted.ref);
      assert.equal(started.kind, 'reserved');
      computes++;
      const setup = moon.clientProgramOpenSourceFreeLocalHost(preparedProgram, registry, values, 1n, 0n, 0n, 0n);
      assert.ok(setup);
      published = await runPublishedCapturedStrategy(setup, {store, plan});
      assert.equal(published.status, 'published');
      assert.equal(published.execution.status, 'host-tasks-completed');
      assert.equal(published.execution.completed[0].outputRows, 121);
      assert.equal(published.publication.publication.state, 'succeeded');
      await published.close();
      assert.equal(published.cleanupPending(), false);
      return {ref: started.ref, durability: started.durability, revision: started.revision};
    },
    resultService, stateService, maxRowBytes: 1024,
  };
  const submit = services.submit;
  services.submit = async input => {
    try { return await submit(input); }
    catch (cause) { submitFailure = cause; throw cause; }
  };
  t.after(async () => {
    client?.close();
    if (server) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    await published?.close();
    journal.close();
    await store.close();
    await rm(directory, {recursive: true, force: true});
  });
  if (entrance === 'local') {
    client = await connectInProcess({mode: 'local', owner: 'local'}, createNodeInProcessClientHost(services));
  } else {
    const handler = createClientHttpHandler(services);
    server = createServer({key, cert}, (request, response) => {
      const settled = handler(request, response);
      if (request.url.endsWith('/read')) handlerSettlements.push(settled);
      void settled;
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'local', owner: 'local',
      endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'scoped-token'});
  }
  let execution;
  try { execution = await client.start(program, {requestId: 'published-read-request'}); }
  catch (cause) { throw submitFailure ?? cause; }
  assert.equal(definitions, 1);
  assert.equal(computes, 1);
  assert.equal(execution.ref.runDefinitionCid, plan.runDefinition.identity);
  return {execution, store, operations, attempts,
    counts: () => ({definitions, computes, rowReaders}),
    settle: () => Promise.all(handlerSettlements)};
}

for (const entrance of ['local', 'https']) {
  for (const consumer of ['rows', 'all']) {
    test(`${entrance}: ${consumer} delivery failure preserves a successful published Run and fresh read`,
      {timeout: 15000}, async t => {
        let release;
        const prefixConsumed = consumer === 'rows' ? new Promise(resolve => { release = resolve; }) : Promise.resolve();
        const f = await installed(t, entrance, prefixConsumed);
        const execution = f.execution, result = execution.result('answer');
        const succeeded = await execution.status();
        assert.equal(succeeded.status, 'succeeded', '[check-mutation:read-run-isolation]');
        const reader = consumer === 'rows' ? result.rows() : undefined;
        const returned = [];
        let failure;
        try {
          if (reader) {
            for await (const row of reader) {
              returned.push(row);
              if (returned.length === 120) release();
            }
          } else returned.push(...await result.all());
        } catch (error) { failure = error; }
        finally { release?.(); }
        assert.ok(failure, '[check-mutation:read-failure]');
        assert.equal(failure.rowsYielded, reader ? 120 : 0, '[check-mutation:read-prefix]');
        assert.deepEqual(returned, reader ? expected.slice(0, 120) : []);
        if (reader) {
          assert.equal(failure.attemptId, reader.attemptId);
          assert.equal(reader.state(), 'prefix');
          assert.equal(reader.rowsYielded(), 120);
        }
        await f.settle();
        const failed = await result.deliveryAttempt(failure.attemptId);
        assert.equal(failed.kind, 'found');
        assert.equal(failed.record.state, 'failed');
        assert.equal(failed.hostReleaseReceipt, null);
        assert.equal(failed.attempt.run_definition_cid, execution.ref.runDefinitionCid);
        assert.deepEqual(await execution.status(), succeeded, '[check-mutation:read-run-isolation]');
        assert.deepEqual(f.counts(), {definitions: 1, computes: 1, rowReaders: 1});
        assert.equal(f.attempts.length, 1);
        const fresh = result.rows();
        assert.notEqual(fresh.attemptId, failure.attemptId);
        assert.equal(fresh.rowsYielded(), 0);
        assert.equal(f.counts().rowReaders, 1);
        assert.deepEqual(await Array.fromAsync(fresh), expected, '[check-mutation:fresh-read]');
        assert.equal(fresh.rowsYielded(), 121);
        await f.settle();
        const completed = await result.deliveryAttempt(fresh.attemptId);
        assert.equal(completed.record.state, 'succeeded');
        assert.ok(completed.hostReleaseReceipt);
        assert.notEqual(completed.attempt.result_read_grant_cid, failed.attempt.result_read_grant_cid);
        assert.equal(completed.hostReleaseReceipt.result_artifact_cid, failed.attempt.result_artifact_cid);
        assert.deepEqual(await execution.status(), succeeded, '[check-mutation:read-run-isolation]');
        assert.deepEqual(f.counts(), {definitions: 1, computes: 1, rowReaders: 2});
        assert.equal(f.operations.filter(operation => operation === 'submit').length, 1);
        assert.equal(f.operations.filter(operation => operation === 'read').length, 2);
        assert.equal(f.operations.filter(operation => operation === 'cancel').length, 0);
        assert.equal(f.attempts.length, 2);
      });
  }
}
