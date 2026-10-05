// Actual preparation, checked Run issuance and SQLite acceptance, without
// physical dispatch. Reply loss never supplies evidence of nonacceptance.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test, {after} from 'node:test';
import * as sdk from '../../packages/sdk/index.mjs';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {sourceFreeValuesPlan} from './local-values-plan.mjs';

const scratch = new URL('../../_build/client-submission-input-tests/', import.meta.url).pathname;
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'remote.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'remote.crt'));
setDefaultCACertificates([...getCACertificates('default'), tlsCertificate.toString('utf8')]);
after(() => rm(tlsRoot, {recursive: true, force: true}));
const document = await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8');
const environmentWire = await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8');
const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
  false, false, true, false, false, false, false);
assert.ok(environment);
const control = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const scope = {namespaceId: 'namespace-a', authorityScopeCid: cid('a')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'principal-a', capabilities: ['aql-document'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};

async function fixture(t, entrance, loss) {
  const directory = await mkdtemp(join(scratch, 'request-'));
  const journal = openClientRequestJournal(directory);
  const observer = new DatabaseSync(join(directory, 'client-requests.sqlite3'), {readOnly: true});
  let client, server, authorized = true, submits = 0, issues = 0;
  const operations = [];
  t.after(async () => {
    client?.close();
    if (server) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    observer.close();
    journal.close();
    await rm(directory, {recursive: true, force: true});
  });
  const configuration = {
    authenticate: () => 'principal-a',
    authorizeConnection: () => authorized,
    negotiate: () => profile,
    prepareSubmit: installNodeClientProgramPreparation({moon, environment}),
    async submit({preparedProgram, requestId}) {
      submits++;
      const identity = moon.clientProgramRequestIdentity(preparedProgram,
        scope.authorityScopeCid, requestId, cid('b'));
      assert.ok(identity);
      const accepted = await journal.admitOrLookupDefinition(identity, {
        namespaceId: scope.namespaceId, lookupExpiresAt: '2099-01-01T00:00:00.000Z',
        issueDefinition: () => {
          issues++;
          return sourceFreeValuesPlan({moon, control, preparedProgram,
            ...scope, storeAuthorityCid: cid('7'),
            now: () => '2026-10-04T00:00:00.000Z'}).runDefinition;
        },
      }, moon, control);
      return {ref: accepted.ref, durability: 'durable', revision: accepted.revision};
    },
    lookupRequest: installNodeClientRequestLookup({journal, control: moon,
      authorizedScope: () => authorized ? scope : undefined}),
    maxRowBytes: 1024,
  };
  let pendingLoss = loss;
  if (entrance === 'local') {
    const port = createNodeInProcessClientHost(configuration);
    client = await sdk.connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation, body, signal) {
        operations.push(operation);
        const phase = operation === 'submit' ? pendingLoss : undefined;
        if (phase) pendingLoss = undefined;
        if (phase === 'before-dispatch') throw new Error('LostSubmitReply');
        const answer = await port.perform(operation, body, signal);
        if (phase === 'after-commit') throw new Error('LostSubmitReply');
        return answer;
      },
    });
  } else {
    const handler = createClientHttpHandler(configuration);
    server = createServer({key: tlsKey, cert: tlsCertificate}, (request, response) => {
      const operation = request.url.split('/').at(-1);
      operations.push(operation);
      const phase = operation === 'submit' ? pendingLoss : undefined;
      if (phase) pendingLoss = undefined;
      if (phase === 'before-dispatch') {
        request.resume(); response.destroy(); return;
      }
      if (phase === 'after-commit') {
        response.end = () => {
          assert.equal(response.statusCode, 200);
          response.destroy(); return response;
        };
      }
      void handler(request, response);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await sdk.connect({mode: 'local', owner: 'local',
      endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'private-token'});
  }
  return {client, operations, revoke: () => { authorized = false; },
    counts: () => ({submits, issues}),
    stored: () => observer.prepare(`SELECT caller_request_id, namespace_id,
      authority_scope_cid, program_definition_cid, run_definition_cid,
      dispatch_reserved, physical_start_reserved FROM client_requests`).all().map(row => ({...row}))};
}

for (const entrance of ['local', 'https']) {
  for (const kind of ['program', 'aql-json']) {
    for (const loss of ['before-dispatch', 'after-commit', undefined]) {
      test(`${entrance}: ${kind} submission inputs survive ${loss ?? 'acceptance'}`, async t => {
        const f = await fixture(t, entrance, loss);
        const program = JSON.parse(document), parameters = {};
        const options = {requestId: 'saved-request', parameters};
        const operation = kind === 'program' ? f.client.start(program, options)
          : f.client.aql(document, {...options, format: 'json'});
        program.stages[0].steps[0].values.rows[0].id = 9999;
        parameters.changed = 'private-edit';
        let result;
        try { result = await operation; }
        catch (cause) {
          assert.equal(cause.code, 'SubmissionUnknown');
          assert.equal(cause.requestId, 'saved-request');
          result = cause;
        }
        assert.equal(result instanceof sdk.ClientError, loss !== undefined);
        assert.equal(result.code, loss ? 'SubmissionUnknown' : undefined);
        const committed = loss !== 'before-dispatch';
        const stored = f.stored();
        assert.equal(stored.length, committed ? 1 : 0);
        assert.deepEqual(f.counts(), {submits: committed ? 1 : 0, issues: committed ? 1 : 0});
        if (committed) {
          assert.equal(stored[0].caller_request_id, 'saved-request');
          assert.equal(stored[0].program_definition_cid,
            'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c');
          assert.equal(stored[0].dispatch_reserved, 0);
          assert.equal(stored[0].physical_start_reserved, 0);
        }
        assert.deepEqual(f.operations, ['connect', 'submit']);
        const snapshot = sdk.getSubmissionInput?.(result);
        assert.deepEqual(snapshot?.input, kind === 'program' ? JSON.parse(document)
          : {text: document, format: 'json'}, '[check-mutation:submission-input]');
        assert.deepEqual(snapshot.parameters, {}, '[check-mutation:submission-input]');
        assert.equal(snapshot.requestId, 'saved-request');
        assert.equal(snapshot.lookupContext.scopeRef, 'principal-a');
        assert.equal(Object.isFrozen(snapshot), true);
        assert.equal(Object.isFrozen(snapshot.parameters), true);
        assert.ok(!JSON.stringify(snapshot).includes('private-token'));
        assert.ok(!JSON.stringify(result).includes('client-values'));
        assert.equal(sdk.getSubmissionInput({...result}), undefined);
        const found = await f.client.lookupRequest(snapshot.requestId);
        assert.equal(found.kind, committed ? 'found' : 'not_found');
        if (committed) assert.equal(found.ref.runDefinitionCid, stored[0].run_definition_cid);
        assert.deepEqual(f.stored(), stored);
        f.revoke();
        await assert.rejects(f.client.lookupRequest(snapshot.requestId), {code: 'ClientConnectionDenied'});
        assert.deepEqual(f.stored(), stored);
        assert.equal(f.operations.filter(value => value === 'submit').length, 1);
        assert.equal(sdk.getSubmissionInput(result), snapshot);
      });
    }
  }
}
