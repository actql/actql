import {submissionEpoch, originalSubmission, readySubmissionAttempt, heldSubmissionAttempt, submissionAttempt} from '../packages/sdk/submission-fixture.mjs';
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {createServer} from 'node:https';
import {chmod, copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {validHeldRequest} from '../packages/client-wire/index.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';

const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-client-', label: 'Native Client transport fixture'});
const root = scratch.path;
const openssl = (...args) => execFileSync('openssl', args,
  {cwd: root, stdio: 'ignore'});
openssl('genrsa', '-out', 'ca.key', '2048');
openssl('req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
  '-subj', '/CN=ActQL Client Test CA', '-days', '1');
await writeFile(join(root, 'server.ext'),
  'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n');
await writeFile(join(root, 'client.ext'), 'extendedKeyUsage=clientAuth\n');
for (const [name, extension] of [['server', 'server.ext'],
  ['client', 'client.ext']]) {
  openssl('genrsa', '-out', `${name}.key`, '2048');
  openssl('req', '-new', '-key', `${name}.key`, '-out', `${name}.csr`,
    '-subj', `/CN=${name}`);
  openssl('x509', '-req', '-in', `${name}.csr`, '-CA', 'ca.crt',
    '-CAkey', 'ca.key', '-CAcreateserial', '-out', `${name}.crt`,
    '-days', '1', '-extfile', extension);
}

const connection = {mode: 'remote', owner: 'remote',
  consentRefs: [], runners: []};
const ref = {namespaceId: 'namespace-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const deliveryTemplate = JSON.parse(await readFile(new URL(
  '../packages/client-wire/fixtures/delivery-attempt.found.json',
  import.meta.url), 'utf8'));
const canonical = value => Array.isArray(value)
  ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const seal = (body, identityField) => ({...body,
  [identityField]: `sha256:${createHash('sha256')
    .update(canonical(body)).digest('hex')}`});
function deliveryReply(attemptId, {runDefinitionCid = ref.runDefinitionCid,
  resultName = 'answer', state = 'succeeded'} = {}) {
  const {delivery_attempt_cid: _attemptCid, ...attemptBody} =
    deliveryTemplate.attempt;
  const attempt = seal({...attemptBody, attempt_id: attemptId,
    run_definition_cid: runDefinitionCid, result_name: resultName},
  'delivery_attempt_cid');
  const {result_delivery_receipt_cid: _receiptCid, ...receiptBody} =
    deliveryTemplate.hostReleaseReceipt;
  const hostReleaseReceipt = seal({...receiptBody,
    run_definition_cid: runDefinitionCid, result_name: resultName},
  'result_delivery_receipt_cid');
  const {delivery_record_cid: _recordCid, ...recordBody} =
    deliveryTemplate.record;
  const record = seal({...recordBody,
    delivery_attempt_cid: attempt.delivery_attempt_cid,
    result_delivery_receipt_cid:
      hostReleaseReceipt.result_delivery_receipt_cid,
    state}, 'delivery_record_cid');
  return {kind: 'found', attempt, record, hostReleaseReceipt};
}
const foundDelivery = deliveryReply('found-attempt');
const deliveryReplies = {
  'found-attempt': foundDelivery,
  'pending-attempt': (() => {
    const {attempt} = deliveryReply('pending-attempt');
    return {kind: 'found', attempt, record: null, hostReleaseReceipt: null};
  })(),
  'wrong-attempt': foundDelivery,
  'foreign-run': deliveryReply('foreign-run',
    {runDefinitionCid: `sha256:${'c'.repeat(64)}`}),
  'foreign-result': deliveryReply('foreign-result',
    {resultName: 'foreign'}),
  'empty-receipt': {...deliveryReply('empty-receipt'),
    hostReleaseReceipt: {}},
  'empty-record': {...deliveryReply('empty-record'), record: {}},
  'failed-with-receipt': deliveryReply('failed-with-receipt',
    {state: 'failed'}),
};
const profile = {submissionEpoch, version: 'actql-client-host/0.1',
  mode: 'remote', owner: 'remote', durability: 'durable',
  scopeRef: 'principal-a', capabilities: ['aql-document', 'result-jsonl'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
await writeFile(join(root, 'connection.json'), JSON.stringify(connection));
await writeFile(join(root, 'connection-durable.json'),
  JSON.stringify({...connection, durability: 'durable'}));
await writeFile(join(root, 'ref.json'), JSON.stringify(ref));
await writeFile(join(root, 'token.txt'), 'scoped-token\n');
await writeFile(join(root, 'parameters.json'), '{"minimum":1}');
await writeFile(join(root, 'query.sql'),
  'SELECT id FROM records WHERE id = @minimum');
await writeFile(join(root, 'parameter-declarations.json'),
  '{"minimum":{"type":"number"}}');
await writeFile(join(root, 'program.json'), await readFile(new URL(
  '../packages/sdk/fixtures/values.json', import.meta.url)));

const requests = [];
const preparationCodes = JSON.parse(await readFile(new URL(
  '../spec/contracts/actql-client-host.json', import.meta.url), 'utf8'))
  .schemas.submit_preparation_error.properties.code.enum;
const heldBase = {kind: 'held', requestId: 'held-waiting',
  prepareAttemptId: 'prepare-a', state: 'waiting_checkpoint',
  durability: 'durable', lookupExpiresAt: '2026-10-01T00:00:00Z',
  checkpoint: {checkpointId: 'checkpoint-a',
    checkpointCid: `sha256:${'d'.repeat(64)}`, kind: 'run_scope',
    expiresAt: '2026-10-01T00:00:00Z'}};
const heldReplies = {
  'held-waiting': heldBase,
  'held-resuming': {...heldBase, requestId: 'held-resuming',
    state: 'resuming', checkpoint: undefined},
  'held-ended': {...heldBase, requestId: 'held-ended',
    state: 'ended', endReason: 'cancelled'},
  'held-foreign': heldBase,
  'held-no-checkpoint': {...heldBase, requestId: 'held-no-checkpoint',
    checkpoint: undefined},
  'held-contradictory': {...heldBase, requestId: 'held-contradictory',
    endReason: 'cancelled'},
  'held-volatile': {...heldBase, requestId: 'held-volatile',
    durability: 'volatile'},
  'held-fabricated-run': {...heldBase, requestId: 'held-fabricated-run', ref},
};
let attachReplyRef = ref;
const cancelRef = {...ref, cancelId: 'original-cancel', expectedRevision: 6};
const originalCancellation = {ref, cancelRef, kind: 'accepted', revision: 7};
let cancelReply = originalCancellation;
let cancelAttemptReply;
let loseCancelReply = false;
let cancellationLookupReply = {kind: 'found', cancellation: originalCancellation};
const server = createServer({key: await readFile(join(root, 'server.key')),
  cert: await readFile(join(root, 'server.crt')),
  ca: await readFile(join(root, 'ca.crt')),
  requestCert: true, rejectUnauthorized: true}, async (request, response) => {
  const operation = request.url?.split('/').at(-1);
  let raw = '';
  for await (const chunk of request) raw += chunk;
  const body = JSON.parse(raw);
  const requestId = body.submissionRef?.nonce ?? body.requestId;
  requests.push({operation, body, authorization: request.headers.authorization});
  assert.equal(request.headers.authorization, 'Bearer scoped-token');
  assert.equal(request.method, 'POST');
  assert.deepEqual(body.connection, body.connection.durability === 'durable'
    ? {...connection, durability: 'durable'} : connection);
  if ((operation === 'submit-intent' || operation === 'lookup-request') &&
      heldReplies[requestId]) {
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify(operation === 'submit-intent' ? heldSubmissionAttempt(body, heldReplies[requestId]) : heldReplies[requestId]));
    return;
  }
  if (operation === 'submit-intent' && requestId.startsWith('input-refusal-')) {
    const code = requestId.slice('input-refusal-'.length);
    response.writeHead(preparationCodes.includes(code) ? 200 : 400, {'content-type': 'application/json'});
    response.end(JSON.stringify(preparationCodes.includes(code)
      ? submissionAttempt(body, {kind: 'not_accepted', submissionRef: body.submissionRef, intentCid: body.intentCid, problem: {code, classification: 'invalid_input'}}) : {code}));
    return;
  }
  if (operation === 'submit-intent' && requestId.startsWith('typed-attempt-')) {
    const reply = requestId === 'typed-attempt-authorization'
      ? {kind: 'refused', attemptRef: body.attemptRef, reason: 'authorization',
        guarantee: 'attempt_uncommitted_unconsumed'}
      : {kind: 'conflict', attemptRef: body.attemptRef, reason: 'intent',
        submissionRef: body.submissionRef, intentCid: body.intentCid};
    if (requestId === 'typed-attempt-foreign-invocation') {
      reply.attemptRef = {...body.attemptRef, attemptId: 'another-invocation'};
    }
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify(reply));
    return;
  }
  if (operation === 'submit-intent' && requestId === 'lost-ack') {
    response.destroy();
    return;
  }
  if (operation === 'submit-intent' && requestId === 'invalid-utf8-ack') {
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(Buffer.from([0xff]));
    return;
  }
  if (operation === 'submit-intent' && requestId === 'malformed-ack') {
    response.writeHead(200, {'content-type': 'application/json'});
    response.end('{"bad":true}');
    return;
  }
  if (operation === 'submit-intent' && requestId === 'redirect-ack') {
    response.writeHead(307, {location: `https://127.0.0.1:` +
      `${server.address().port}/actql/client/0.1/submit-redirect-target`});
    response.end();
    return;
  }
  response.writeHead(200, {'content-type': operation === 'read'
    ? 'application/x-ndjson' : 'application/json'});
  if (operation === 'connect') response.end(JSON.stringify(
    body.connection.durability === 'durable'
      ? {...profile, durability: 'volatile'} : profile));
  else if (operation === 'submit-intent' || operation === 'attach') {
    response.end(JSON.stringify(operation === 'attach' ? {ref: attachReplyRef, durability: 'durable', revision: 1}
      : readySubmissionAttempt(body, {ref, durability: 'durable', revision: 1})));
  } else if (operation === 'lookup-request') {
    response.end(JSON.stringify(requestId === 'bad-lookup'
      ? {kind: 'found', ref: {...ref, runDefinitionCid: 'bad'},
        durability: 'durable', lookupExpiresAt: 'tomorrow'}
      : requestId === 'found-request'
        ? {kind: 'found', requestId: requestId, ref,
          durability: 'durable',
          lookupExpiresAt: '2026-09-24T00:00:00Z'}
        : requestId === 'foreign-request'
          ? {kind: 'found', requestId: 'OTHER', ref,
            durability: 'durable',
            lookupExpiresAt: '2026-09-24T00:00:00Z'}
        : {kind: 'unknown', reason: 'query_failed'}));
  } else if (operation === 'cancel' || operation === 'lookup-cancellation') {
    assert.deepEqual(body.ref, ref);
    assert.equal(body.cancelId, 'original-cancel');
    assert.equal(body.expectedRevision, 6);
    if (operation === 'cancel' && loseCancelReply) {
      response.destroy();
      return;
    }
    if (operation === 'cancel') {
      assert.deepEqual(body.attemptRef, {operation: 'cancel', attemptId: 'native-invocation'});
    }
    response.end(JSON.stringify(operation === 'cancel'
      ? cancelAttemptReply ?? {kind: 'accepted', attemptRef: body.attemptRef, cancellation: cancelReply}
      : cancellationLookupReply));
  } else if (operation === 'status') {
    response.end(JSON.stringify({status: 'succeeded'}));
  } else if (operation === 'delivery-attempt') {
    response.end(JSON.stringify(body.attemptId === 'bad-attempt'
      ? {kind: 'found', attempt: null, record: null,
        hostReleaseReceipt: null}
      : deliveryReplies[body.attemptId] ?? {kind: 'not_found'}));
  } else if (operation === 'read') {
    response.end(body.attemptId === 'prefix' ? '{"value":7}\n'
      : '{"value":7}\n\x1e');
  } else {
    response.end('{}');
  }
});
const builtExecutable = process.env.ACTQL_TEST_NATIVE_CLIENT_BINARY ?? new URL(
  '../_build/native/release/build/cmd/native_client/native_client.exe',
  import.meta.url).pathname;
const executable = join(root, 'actql-native-client');
await copyFile(builtExecutable, executable);
await chmod(executable, 0o755);
const emptyPath = join(root, 'empty-path');
await mkdir(emptyPath);
const binaryDigest = createHash('sha256')
  .update(await readFile(executable)).digest('hex');
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const endpoint = `https://127.0.0.1:${server.address().port}/`;
const library = process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY ??
  (process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4');
const common = ['--endpoint', endpoint,
  '--connection-root', root, '--connection-file', 'connection.json',
  '--token-root', root, '--token-file', 'token.txt',
  '--http-library', library, '--ca', join(root, 'ca.crt'),
  '--cert', join(root, 'client.crt'), '--key', join(root, 'client.key')];

function runProcess(command, commandArgs) {
  return new Promise((resolve, reject) => {
    // The installed binary must not rely on a repository cwd or find Node,
    // MoonBit, curl's CLI, or another build tool through PATH.
    const launcher = command === executable ? process.env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER : undefined;
    const child = spawn(launcher ? process.execPath : command,
      launcher ? [launcher, ...commandArgs] : commandArgs, {cwd: root,
      env: {...process.env, PATH: emptyPath}});
    let stdout = '', stderr = '';
    child.stdout.setEncoding('utf8').on('data', data => { stdout += data; });
    child.stderr.setEncoding('utf8').on('data', data => { stderr += data; });
    child.once('error', reject);
    child.once('close', code => resolve({code, stdout, stderr}));
  });
}
const runWith = async (commonArgs, ...args) => {
  if (['aql', 'start'].includes(args[0])) {
    const nonce = args[args.indexOf('--request-id') + 1];
    const filename = `submission-${nonce}.json`;
    await writeFile(join(root, filename), JSON.stringify(originalSubmission(nonce)));
    args.push('--submission-ref-file', filename, '--operation-attempt-id', `native-submit-${nonce}`);
  }
  return runProcess(executable, [...commonArgs, ...args]);
};
const run = (...args) => runWith(common, ...args);

try {
  const connected = await run('connect');
  assert.equal(connected.code, 0, connected.stderr);
  assert.deepEqual(JSON.parse(connected.stdout), profile);
  if (process.platform === 'darwin' &&
      process.env.ACTQL_MEASURE_NATIVE_CLIENT === '1') {
    const timed = await runProcess('/usr/bin/time',
      ['-l', executable, ...common, 'connect']);
    assert.equal(timed.code, 0, timed.stderr);
    assert.deepEqual(JSON.parse(timed.stdout), profile);
    assert.match(timed.stderr, /maximum resident set size/);
    console.log(timed.stderr.trim());
  }
  const durableArgs = [...common];
  durableArgs[durableArgs.indexOf('--connection-file') + 1] =
    'connection-durable.json';
  const downgraded = await runWith(durableArgs, 'connect');
  assert.notEqual(downgraded.code, 0);
  assert.match(downgraded.stderr, /requested durable profile is unavailable/);
  const submitted = await run('aql', '--program-file', 'program.json',
    '--parameters-file', 'parameters.json', '--format', 'json',
    '--request-id', 'saved-id');
  assert.equal(submitted.code, 0, submitted.stderr);
  assert.deepEqual(JSON.parse(submitted.stdout),
    {ref, durability: 'durable', revision: 1});
  const sent = requests.find(item => item.operation === 'submit-intent');
  assert.equal(sent.body.submissionRef.nonce, 'saved-id');
  assert.equal(sent.body.kind, 'aql');
  assert.equal(sent.body.input.format, 'json');
  assert.deepEqual(sent.body.parameters, {minimum: 1});
  assert.deepEqual(JSON.parse(sent.body.input.text),
    JSON.parse(await readFile(join(root, 'program.json'), 'utf8')));
  const query = await run('aql', '--program-file', 'query.sql',
    '--parameter-declarations-file', 'parameter-declarations.json',
    '--parameters-file', 'parameters.json', '--format', 'sql',
    '--request-id', 'saved-query-id');
  assert.equal(query.code, 0, query.stderr);
  const querySubmit = requests.find(item => item.operation === 'submit-intent' &&
    item.body.submissionRef.nonce === 'saved-query-id');
  assert.deepEqual(querySubmit.body.input, {
    text: 'SELECT id FROM records WHERE id = @minimum', format: 'sql',
    parameterDeclarations: {minimum: {type: 'number'}},
  });
  assert.deepEqual(querySubmit.body.parameters, {minimum: 1});
  await writeFile(join(root, 'budget-numbers.json'),
    JSON.stringify({numbers: Array(8192).fill(1)}));
  await writeFile(join(root, 'budget-depth.json'),
    '{"nested":' + '['.repeat(32) + '1' + ']'.repeat(32) + '}');
  const budgetRefusals = [];
  for (const [nonce, parameters] of [
    ['parameter-node-limit', 'budget-numbers.json'],
    ['parameter-depth-limit', 'budget-depth.json'],
  ]) {
    const before = requests.length;
    const rejected = await run('aql', '--program-file', 'query.sql', '--format', 'sql',
      '--request-id', nonce, '--parameters-file', parameters);
    assert.notEqual(rejected.code, 0, nonce);
    assert.equal(requests.length, before, `${nonce}: no connection or submission before refusal`);
    budgetRefusals.push({nonce, stderr: rejected.stderr});
  }
  console.log('NATIVE_SUBMISSION_BUDGET_EVIDENCE', JSON.stringify(budgetRefusals));
  for (const {nonce, stderr} of budgetRefusals) {
    assert.match(stderr, /JSON file exceeds configured bounds/u, nonce);
  }
  const beforeInvalid = requests.filter(item =>
    item.operation === 'submit-intent').length;
  const invalid = await run('aql', '--program-file', 'program.json',
    '--parameter-declarations-file', 'parameter-declarations.json',
    '--format', 'json', '--request-id', 'invalid-query-id');
  assert.notEqual(invalid.code, 0);
  assert.match(invalid.stderr, /external declarations require/);
  assert.equal(requests.filter(item =>
    item.operation === 'submit-intent').length, beforeInvalid);
  for (const code of [...preparationCodes, 'UnregisteredInputFailure']) {
    const requestId = 'input-refusal-' + code;
    const rejected = await run('aql', '--program-file', 'query.sql',
      '--format', 'sql', '--request-id', requestId);
    assert.notEqual(rejected.code, 0);
    if (preparationCodes.includes(code)) {
      assert.ok(rejected.stderr.includes(code), rejected.stderr);
      assert.doesNotMatch(rejected.stderr, /SubmissionUnknown/);
    } else {
      assert.ok(rejected.stderr.includes(
        'SubmissionUnknown submission-ref-file=submission-' + requestId), rejected.stderr);
    }
  }
  for (const [requestId, kind] of [
    ['typed-attempt-authorization', 'refused'],
    ['typed-attempt-conflict', 'conflict'],
    ['typed-attempt-foreign-invocation', undefined],
  ]) {
    const result = await run('aql', '--program-file', 'query.sql',
      '--format', 'sql', '--request-id', requestId);
    if (kind === undefined) {
      assert.notEqual(result.code, 0);
      assert.match(result.stderr, /SubmissionUnknown/);
    } else {
      assert.equal(result.code, 0, result.stderr);
      const fact = JSON.parse(result.stdout);
      assert.equal(fact.kind, kind);
      assert.deepEqual(fact.attemptRef,
        {operation: 'submit', attemptId: `native-submit-${requestId}`});
      assert.equal(fact.guarantee, kind === 'refused' ? 'attempt_uncommitted_unconsumed' : undefined);
      assert.equal(fact.outcome, undefined);
    }
    assert.equal(requests.filter(item => item.operation === 'submit-intent' &&
      item.body.submissionRef.nonce === requestId).length, 1);
  }
  for (const [requestId, reply] of Object.entries(heldReplies)) {
    const accepted = ['held-waiting', 'held-resuming', 'held-ended']
      .includes(requestId);
    // Compare native transport validation with the shared wire contract.
    assert.equal(validHeldRequest(JSON.parse(JSON.stringify(reply)),
      requestId), accepted, requestId);
    for (const operation of ['aql', 'lookup-request']) {
      const result = await run(operation, '--request-id', requestId,
        ...(operation === 'aql'
          ? ['--program-file', 'query.sql', '--format', 'sql'] : []));
      if (accepted) {
        assert.equal(result.code, 0, result.stderr);
        assert.deepEqual(JSON.parse(result.stdout),
          JSON.parse(JSON.stringify(reply)));
        assert.equal(JSON.parse(result.stdout).ref, undefined);
      } else {
        assert.notEqual(result.code, 0);
        assert.ok(result.stderr.includes(operation === 'aql'
          ? 'SubmissionUnknown submission-ref-file=submission-' + requestId
          : 'InvalidHostRequestLookup'), result.stderr);
      }
    }
    assert.equal(requests.filter(item => item.operation === 'submit-intent' &&
      item.body.submissionRef.nonce === requestId).length, 1);
  }
  const status = await run('status', '--ref-file', 'ref.json');
  assert.equal(status.code, 0, status.stderr);
  assert.deepEqual(JSON.parse(status.stdout), {status: 'succeeded'});
  const attached = await run('attach', '--ref-file', 'ref.json');
  assert.equal(attached.code, 0, attached.stderr);
  assert.deepEqual(JSON.parse(attached.stdout),
    {ref, durability: 'durable', revision: 1});
  for (const field of ['namespaceId', 'authorityScopeCid',
    'runDefinitionCid']) {
    attachReplyRef = {...ref, [field]: field === 'namespaceId' ? 'namespace-b' :
      `sha256:${'c'.repeat(64)}`};
    const foreign = await run('attach', '--ref-file', 'ref.json');
    assert.notEqual(foreign.code, 0);
    assert.match(foreign.stderr, /ForeignHostAdmission/);
  }
  attachReplyRef = ref;
  const cancelArgs = ['--ref-file', 'ref.json', '--cancel-id', 'original-cancel',
    '--expected-revision', '6'];
  const invocationArgs = ['--operation-attempt-id', 'native-invocation'];
  const cancelled = await run('cancel', ...cancelArgs, ...invocationArgs);
  assert.equal(cancelled.code, 0, cancelled.stderr);
  assert.deepEqual(JSON.parse(cancelled.stdout), {kind: 'accepted',
    attemptRef: {operation: 'cancel', attemptId: 'native-invocation'},
    cancellation: originalCancellation});
  const attemptRef = {operation: 'cancel', attemptId: 'native-invocation'};
  for (const outcome of [
    {kind: 'refused', attemptRef, reason: 'authorization', guarantee: 'attempt_uncommitted_unconsumed'},
    {kind: 'conflict', attemptRef, reason: 'control_revision', cancelRef},
    {kind: 'already_satisfied', attemptRef, cancellation: {...originalCancellation, kind: 'already_requested'}},
  ]) {
    cancelAttemptReply = outcome;
    const observed = await run('cancel', ...cancelArgs, ...invocationArgs);
    assert.equal(observed.code, 0, observed.stderr);
    assert.deepEqual(JSON.parse(observed.stdout), outcome);
  }
  for (const outcome of [
    {kind: 'refused', attemptRef: {...attemptRef, attemptId: 'another-invocation'},
      reason: 'authorization', guarantee: 'attempt_uncommitted_unconsumed'},
    {kind: 'refused', attemptRef, reason: 'authorization', guarantee: 'operation_never_executed'},
    {kind: 'already_satisfied', attemptRef, cancellation: originalCancellation},
  ]) {
    cancelAttemptReply = outcome;
    const rejected = await run('cancel', ...cancelArgs, ...invocationArgs);
    assert.notEqual(rejected.code, 0);
    assert.match(rejected.stderr, /InvalidHostCancellation/);
  }
  cancelAttemptReply = undefined;
  const cancellation = await run('lookup-cancellation', ...cancelArgs);
  assert.equal(cancellation.code, 0, cancellation.stderr);
  assert.deepEqual(JSON.parse(cancellation.stdout), {kind: 'found', cancellation: originalCancellation});
  for (const bad of [
    {...originalCancellation, cancelRef: {...cancelRef, cancelId: 'foreign-cancel'}},
    {...originalCancellation, cancelRef: {...cancelRef, expectedRevision: 7}},
    {...originalCancellation, ref: {...ref, runDefinitionCid: `sha256:${'f'.repeat(64)}`}},
    {...originalCancellation, revision: 6},
  ]) {
    cancelReply = bad;
    cancellationLookupReply = {kind: 'found', cancellation: bad};
    for (const operation of ['cancel', 'lookup-cancellation']) {
      const rejected = await run(operation, ...cancelArgs,
        ...(operation === 'cancel' ? invocationArgs : []));
      assert.notEqual(rejected.code, 0);
      assert.match(rejected.stderr, /InvalidHostCancellation/);
    }
  }
  cancelReply = originalCancellation;
  cancellationLookupReply = {kind: 'unknown', cancelRef};
  const unknownCancellation = await run('lookup-cancellation', ...cancelArgs);
  assert.equal(unknownCancellation.code, 0, unknownCancellation.stderr);
  assert.deepEqual(JSON.parse(unknownCancellation.stdout), {kind: 'unknown', cancelRef});
  for (const bad of [{kind: 'unknown', cancelRef: {...cancelRef, cancelId: 'foreign-cancel'}},
    {kind: 'unknown', cancelRef: {...cancelRef, expectedRevision: 7}},
    {kind: 'unknown'}, {kind: 'found', cancellation: {}}]) {
    cancellationLookupReply = bad;
    const rejected = await run('lookup-cancellation', ...cancelArgs);
    assert.notEqual(rejected.code, 0);
    assert.match(rejected.stderr, /InvalidHostCancellation/);
  }
  loseCancelReply = true;
  const lostCancellation = await run('cancel', ...cancelArgs, ...invocationArgs);
  loseCancelReply = false;
  assert.notEqual(lostCancellation.code, 0);
  assert.match(lostCancellation.stderr, /CancellationUnknown/);
  const retained = lostCancellation.stderr.match(/cancel-ref=(\{[^\n]+\}) lookup=lookup-cancellation/);
  assert.ok(retained, 'the failed command retains its complete original operation reference');
  assert.deepEqual(JSON.parse(retained[1]), cancelRef);
  cancellationLookupReply = {kind: 'found', cancellation: originalCancellation};
  const recovered = await run('lookup-cancellation', ...cancelArgs);
  assert.equal(recovered.code, 0, recovered.stderr);
  assert.deepEqual(JSON.parse(recovered.stdout), {kind: 'found', cancellation: originalCancellation});
  const writesBeforeLookup = requests.filter(item => item.operation === 'cancel').length;
  await run('lookup-cancellation', ...cancelArgs);
  assert.equal(requests.filter(item => item.operation === 'cancel').length, writesBeforeLookup);
  for (const revision of ['-1', '2147483648']) {
    const invalid = await run('cancel', '--ref-file', 'ref.json', '--cancel-id', 'original-cancel',
      '--expected-revision', revision, ...invocationArgs);
    assert.notEqual(invalid.code, 0);
    assert.equal(requests.filter(item => item.operation === 'cancel').length, writesBeforeLookup);
  }
  const read = await run('read', '--ref-file', 'ref.json',
    '--result-name', 'answer', '--attempt-id', 'attempt-a');
  assert.equal(read.code, 0, read.stderr);
  assert.equal(read.stdout, '{"value":7}\n');
  const attempt = await run('delivery-attempt', '--ref-file', 'ref.json',
    '--result-name', 'answer', '--attempt-id', 'attempt-a');
  assert.equal(attempt.code, 0, attempt.stderr);
  assert.deepEqual(JSON.parse(attempt.stdout), {kind: 'not_found'});
  const foundAttempt = await run('delivery-attempt', '--ref-file', 'ref.json',
    '--result-name', 'answer', '--attempt-id', 'found-attempt');
  assert.equal(foundAttempt.code, 0, foundAttempt.stderr);
  assert.deepEqual(JSON.parse(foundAttempt.stdout), foundDelivery);
  const pendingAttempt = await run('delivery-attempt',
    '--ref-file', 'ref.json', '--result-name', 'answer',
    '--attempt-id', 'pending-attempt');
  assert.equal(pendingAttempt.code, 0, pendingAttempt.stderr);
  assert.deepEqual(JSON.parse(pendingAttempt.stdout),
    deliveryReplies['pending-attempt']);
  for (const attemptId of ['wrong-attempt', 'foreign-run',
    'foreign-result', 'empty-receipt', 'empty-record',
    'failed-with-receipt']) {
    const rejected = await run('delivery-attempt', '--ref-file', 'ref.json',
      '--result-name', 'answer', '--attempt-id', attemptId);
    assert.notEqual(rejected.code, 0);
    assert.match(rejected.stderr, /InvalidHostAttemptLookup/);
  }
  const badAttempt = await run('delivery-attempt', '--ref-file', 'ref.json',
    '--result-name', 'answer', '--attempt-id', 'bad-attempt');
  assert.notEqual(badAttempt.code, 0);
  assert.match(badAttempt.stderr, /InvalidHostAttemptLookup/);
  const prefix = await run('read', '--ref-file', 'ref.json',
    '--result-name', 'answer', '--attempt-id', 'prefix');
  assert.notEqual(prefix.code, 0);
  assert.match(prefix.stderr, /IncompleteResultStream attempt-id=prefix/);
  assert.doesNotMatch(prefix.stdout, /"value"/);
  const started = await run('start', '--program-file', 'program.json',
    '--request-id', 'program-id');
  assert.equal(started.code, 0, started.stderr);
  assert.deepEqual(JSON.parse(started.stdout),
    {ref, durability: 'durable', revision: 1});
  assert.equal(requests.find(item => item.operation === 'submit-intent' &&
    item.body.submissionRef.nonce === 'program-id').body.kind, 'program');
  const malformed = await run('aql', '--program-file', 'program.json',
    '--format', 'json', '--request-id', 'malformed-ack');
  assert.notEqual(malformed.code, 0);
  assert.match(malformed.stderr,
    /SubmissionUnknown submission-ref-file=submission-malformed-ack/);
  const invalidUtf8 = await run('aql', '--program-file', 'query.sql',
    '--format', 'sql', '--request-id', 'invalid-utf8-ack');
  assert.notEqual(invalidUtf8.code, 0);
  assert.match(invalidUtf8.stderr,
    /SubmissionUnknown submission-ref-file=submission-invalid-utf8-ack/);
  assert.equal(requests.filter(item => item.operation === 'submit-intent' &&
    item.body.submissionRef.nonce === 'invalid-utf8-ack').length, 1);
  const uncertain = await run('aql', '--program-file', 'program.json',
    '--format', 'json', '--request-id', 'lost-ack');
  assert.notEqual(uncertain.code, 0);
  assert.match(uncertain.stderr, /SubmissionUnknown submission-ref-file=submission-lost-ack/);
  const redirected = await run('start', '--program-file', 'program.json',
    '--request-id', 'redirect-ack');
  assert.notEqual(redirected.code, 0);
  assert.match(redirected.stderr,
    /SubmissionUnknown submission-ref-file=submission-redirect-ack/);
  assert.equal(requests.filter(item =>
    item.operation === 'submit-redirect-target').length, 0);
  const lookedUp = await run('lookup-request', '--request-id', 'lost-ack');
  assert.equal(lookedUp.code, 0, lookedUp.stderr);
  assert.deepEqual(JSON.parse(lookedUp.stdout),
    {kind: 'unknown', reason: 'query_failed'});
  const foundRequest = await run('lookup-request',
    '--request-id', 'found-request');
  assert.equal(foundRequest.code, 0, foundRequest.stderr);
  assert.deepEqual(JSON.parse(foundRequest.stdout), {
    kind: 'found', requestId: 'found-request', ref, durability: 'durable',
    lookupExpiresAt: '2026-09-24T00:00:00Z',
  });
  const foreignRequest = await run('lookup-request',
    '--request-id', 'foreign-request');
  assert.notEqual(foreignRequest.code, 0);
  assert.match(foreignRequest.stderr, /InvalidHostRequestLookup/);
  const badLookup = await run('lookup-request', '--request-id', 'bad-lookup');
  assert.notEqual(badLookup.code, 0);
  assert.match(badLookup.stderr, /InvalidHostRequestLookup/);
  assert.equal(requests.filter(item => item.operation === 'submit-intent' &&
    item.body.submissionRef.nonce === 'lost-ack').length, 1);
  for (const [index, item] of requests.entries()) {
    if (item.operation !== 'connect') {
      assert.equal(requests[index - 1]?.operation, 'connect');
    }
  }
  console.log('native Client mTLS tests passed; binary sha256=' + binaryDigest);
} finally {
  await new Promise(resolve => server.close(resolve));
}

// Keep the independent shared-contract corpus on the normal Native CI entry.
await import('./test-native-client-wire.test.mjs');
// Local ingress runs in the mandatory installed Local consumer, which owns
// an actual packaged runtime. This transport artifact has no Local provider.
scratch.passed();
