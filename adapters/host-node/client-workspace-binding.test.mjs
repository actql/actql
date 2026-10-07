import test from 'node:test';
import assert from 'node:assert/strict';
import './loopback-http.test.mjs';
import {createServer} from 'node:http';
import {clientHostOperations, validClientBody} from '../../packages/client-wire/index.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';

const ref = {namespaceId: 'separate-namespace', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const connection = {mode: 'remote', owner: 'remote', consentRefs: [], runners: [],
  workspaceId: 'workspace-A'};
// Independent legitimate requests for every public operation. The fixture
// validates them before proving the assertion guard precedes their handlers.
const bodies = {
  connect: {},
  submit: {requestId: 'saved-request', kind: 'program', input: {}, parameters: null},
  check: {input: {text: 'SELECT 1 AS n', format: 'sql'}, parameters: null},
  attach: {ref}, 'lookup-request': {requestId: 'saved-request'}, status: {ref},
  wait: {ref, until: null},
  cancel: {ref, cancelId: 'saved-cancel', expectedRevision: 1},
  'lookup-cancellation': {ref, cancelId: 'saved-cancel', expectedRevision: 1},
  reconcile: {ref},
  read: {ref, resultName: 'answer', format: 'jsonl', attemptId: 'saved-read'},
  'result-describe': {ref, resultName: 'answer', format: 'jsonl', attemptId: 'description',
    maxWireBytes: 4096, maxNodes: 100, maxDepth: 10},
  'delivery-attempt': {ref, resultName: 'answer', attemptId: 'saved-read'},
  checkpoints: {after: '', limit: 10},
  'checkpoint-review': {checkpointCid: `sha256:${'c'.repeat(64)}`, maxBytes: 4096},
  resolve: {items: [{checkpointCid: `sha256:${'c'.repeat(64)}`,
    resolutionWire: '{}', approvalEvidenceWire: ''}]},
  'cancel-request': {requestId: 'saved-request'},
  resources: {resourceConnection: 'source', query: '', limit: 10},
  'resource-inspect': {resourceConnection: 'source', resource: 'orders', maxBytes: 4096},
  'resource-peek': {resourceConnection: 'source', resource: 'orders', fields: ['id'],
    maxRows: 2, maxBytes: 4096},
};

for (const transport of ['http', 'in-process']) {
  for (const mapping of ['absent', 'mismatched', 'failed']) {
    test(`${transport}: ${mapping} Workspace mapping rejects every operation before business access`, async t => {
      let authorizations = 0, handlers = 0;
      const forbidden = () => {handlers++; throw new Error('BusinessHandlerMustNotRun');};
      const options = {authenticate: () => 'authenticated-principal',
        authorizeConnection: () => {authorizations++; return true;},
        ...(mapping === 'absent' ? {} : {workspaceForPrincipal: principal => {
          assert.equal(principal, 'authenticated-principal');
          if (mapping === 'failed') throw new Error('private-binding-cause');
          return 'workspace-B';
        }}),
        maxRowBytes: 1024, negotiate: forbidden, prepareSubmit: forbidden,
        submit: forbidden, check: forbidden, attach: forbidden,
        lookupRequest: forbidden, observeRun: forbidden, wait: forbidden,
        cancel: forbidden, lookupCancellation: forbidden, reconcile: forbidden,
        deliveryAttempt: forbidden, checkpoints: forbidden,
        checkpointReview: forbidden, resolve: forbidden, cancelRequest: forbidden,
        resources: forbidden, inspectResource: forbidden, peekResource: forbidden,
      };
      let perform;
      if (transport === 'in-process') perform = createNodeInProcessClientHost(options).perform;
      else {
        const server = createServer(createClientHttpHandler(options));
        await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
        t.after(async () => {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));});
        perform = async (operation, body) => {
          const response = await fetch(`http://127.0.0.1:${server.address().port}/actql/client/0.1/${operation}`,
            {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify(body)});
          assert.equal(response.status, 403);
          const error = await response.json();
          throw Object.assign(new Error(error.code), error);
        };
      }
      assert.deepEqual(Object.keys(bodies).sort(), [...clientHostOperations].sort());
      for (const operation of clientHostOperations) {
        const body = {connection, ...bodies[operation]};
        assert.equal(validClientBody(operation, body), true, operation);
        await assert.rejects(perform(operation, body), {code: 'ClientConnectionDenied'});
      }
      assert.equal(authorizations, 0);
      assert.equal(handlers, 0);
    });
  }
}

test('a matching Workspace assertion still requires ordinary current authorization', async () => {
  let handlers = 0;
  const host = createNodeInProcessClientHost({authenticate: () => 'principal',
    workspaceForPrincipal: () => 'workspace-A', authorizeConnection: () => false,
    negotiate() {handlers++;}, maxRowBytes: 1024});
  await assert.rejects(host.perform('connect', {connection}), {code: 'ClientConnectionDenied'});
  assert.equal(handlers, 0);
});

for (const boundary of ['authenticate', 'workspace']) {
  test(`in-process owns its Workspace assertion across an awaited ${boundary} boundary`, async () => {
    let release, entered;
    const blocked = new Promise(resolve => {release = resolve;});
    const started = new Promise(resolve => {entered = resolve;});
    const connection = {mode: 'remote', owner: 'remote', consentRefs: [], runners: [],
      workspaceId: 'workspace-A'};
    let handlers = 0;
    const wait = async () => {entered(); await blocked;};
    const host = createNodeInProcessClientHost({
      authenticate: async () => {if (boundary === 'authenticate') await wait(); return 'principal';},
      workspaceForPrincipal: async () => {if (boundary === 'workspace') await wait(); return 'workspace-B';},
      authorizeConnection: () => true,
      negotiate() {handlers++;}, maxRowBytes: 1024,
    });
    const result = host.perform('connect', {connection});
    await started;
    delete connection.workspaceId;
    release();
    await assert.rejects(result, {code: 'ClientConnectionDenied'});
    assert.equal(handlers, 0);
  });
}
