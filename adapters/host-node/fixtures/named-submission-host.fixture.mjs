// Real fresh Host/Store/journals; only authentication and the lost response
// are controlled by this verification fixture. No external service is used.
import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import * as moon from '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openInstalledRemoteHttpHost} from '../embedded-local.mjs';
import {canonicalJson} from '../../../packages/sdk/host-port.mjs';
import {createResultFactory} from '../../../packages/sdk/internal/result-read.mjs';
import {validNamedSubmissionAttempt} from '../../../packages/client-wire/index.mjs';

const input = JSON.parse(await new Promise(resolve => {
  let text = ''; process.stdin.setEncoding('utf8');
  process.stdin.on('data', bytes => {text += bytes;});
  process.stdin.once('end', () => resolve(text));
}));
const {root, phase, loseReply} = input;
const keys = JSON.parse(await readFile(join(root, 'keys.json'), 'utf8'));
const principalId = userInfo().username;
let computes = 0, lost = false;
const host = await openInstalledRemoteHttpHost({directory: join(root, 'host'),
  authenticate: () => principalId, loopbackHttp: true,
  authorization: {
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'named-fixture', entries: [{entry_id: 'source-free-acceptance', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'fixture', reviewerId: 'fixture', principalId, publicKey: keys.publicKey}],
    reviewReaders: [principalId], hostKey: {keyId: 'fixture-host', privateKey: keys.privateKey},
    observe(name) {if (name === 'computed') computes++;},
  }});
const server = createServer((request, response) => {
  if (phase === 'first' && loseReply && !lost && request.url.endsWith('/submit-named-intent')) {
    lost = true;
    response.end = () => {response.destroy(); return response;};
  }
  return host.handler(request, response);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const endpoint = `http://127.0.0.1:${server.address().port}/actql/client/0.1/`;
const connection = {mode: 'remote', owner: 'remote', durability: 'durable', consentRefs: [], runners: []};
const post = async (operation, body, signal = AbortSignal.timeout(10000)) => {
  const response = await fetch(endpoint + operation, {method: 'POST',
    headers: {'content-type': 'application/json', authorization: 'Bearer fixture-owner'},
    body: JSON.stringify({connection, ...body}), signal});
  assert.equal(response.status, 200, `${operation}: ${await (response.status === 200
    ? Promise.resolve('') : response.text())}`);
  return response;
};
const poll = async read => {
  for (let step = 0; step < 100; step++) {
    const result = await read();
    if (result !== undefined) return result;
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  throw new Error('FixtureOriginalRunDidNotSettle');
};
try {
  const profile = await (await post('connect', {})).json();
  const program = {version: 'actql/0.1', id: 'named-source-free', stages: [{id: 's', inputs: {},
    steps: [{as: 'rows', values: {schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}]}}],
    results: {out: {from: 'rows', fields: ['id']}}}], results: {answer: {from: {stage: 's', result: 'out'}}}};
  const intent = {kind: 'program', input: program, parameters: null, readOnly: true};
  const intentCid = 'sha256:' + createHash('sha256').update(canonicalJson({
    version: 'actql-submitted-intent/0.1', intent}, {dataKeys: true})).digest('hex');
  const admitted = moon.clientSubmittedIntent(canonicalJson(intent, {dataKeys: true}), 1048576, 65536, 64);
  assert.ok(admitted); assert.equal(moon.clientSubmittedIntentCid(admitted), intentCid);
  const request = {...intent, connection, intentCid, requestName: 'persistent-public-name',
    submissionRef: {epoch: profile.submissionEpoch, nonce: randomUUID()},
    attemptRef: {operation: 'submit', attemptId: randomUUID()}};
  let answer, unknown = false;
  try {answer = await (await post('submit-named-intent', request)).json();}
  catch (error) {
    if (!(phase === 'first' && loseReply && lost && error instanceof TypeError)) throw error;
    unknown = true;
  }
  if (answer !== undefined) assert.equal(validNamedSubmissionAttempt(answer, connection, request.requestName,
    request.submissionRef, intentCid, request.attemptRef), true);
  const outcome = answer?.outcome ?? await poll(async () => {
    const value = await (await post('lookup-submission', {submissionRef: request.submissionRef})).json();
    return value.kind === 'ready' ? value : undefined;
  });
  assert.equal(outcome.kind, 'ready');
  const ref = outcome.admission.ref;
  const state = await poll(async () => {
    const value = await (await post('status', {ref})).json();
    return value.status === 'succeeded' ? value : undefined;
  });
  // Consume the existing SDK reader, including the payload-end marker and
  // confirmed EOF. A successful JSONL payload is not the whole HTTP body.
  const activeReaders = new Set(), readerCleanups = new Set();
  const result = createResultFactory({ref, limits: profile.limits}, {
    runRequest: (operation, body, signal) => post(operation, {ref, ...body}, signal),
    responseValue: response => response.json(),
  }, {activeReaders, readerCleanups}, () => undefined)('answer');
  const rows = await result.all();
  assert.deepEqual(rows, [{id: 1}]);
  assert.equal(activeReaders.size, 0);
  assert.equal(readerCleanups.size, 0);
  await writeFile(join(root, phase + '.json'), JSON.stringify({pid: process.pid, request,
    answer, outcome, state, rows, computes, unknown, lost}, null, 2) + '\n', {flag: 'wx'});
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
}
