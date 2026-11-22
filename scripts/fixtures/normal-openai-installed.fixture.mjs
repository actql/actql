// Copy this authored consumer and external-rest/conformance.mjs into a fresh
// outside-checkout installation. Only installed public package entrances run.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {realpathSync} from 'node:fs';
import {access, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {isAbsolute, relative, resolve} from 'node:path';
import tls, {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {observeOwnScopedStateFds} from './conformance.mjs';
import {normalProviderDiagnostics} from './normal-provider-diagnostics.fixture.mjs';

const phase = process.argv[2];
assert(['warm', 'cold', 'missing-key', 'project-key', 'rate-limit', 'usage-reported', 'usage-zero', 'usage-absent',
  'timeout-headers', 'timeout-body', 'timeout-call'].includes(phase));
const fresh = phase !== 'cold';
const missingKey = phase === 'missing-key';
const modules = resolve(realpathSync(process.cwd()), 'node_modules');
assert.equal(realpathSync(modules), modules, 'The fresh node_modules must not redirect to another installation');
const publicModules = new Map(['@actql/node', '@actql/provider-ai-sdk', '@actql/local-node/observation']
  .map(name => [name, import.meta.resolve(name)]));
for (const [name, url] of publicModules) {
  const member = realpathSync(fileURLToPath(url));
  const selected = relative(modules, member);
  assert(!isAbsolute(selected) && selected !== '..' && !selected.startsWith('../'),
    'The public entrance must resolve inside this fresh installation');
  assert.equal(member, name === '@actql/local-node/observation' ? resolve(modules, '@actql/local-node/observation.mjs')
    : resolve(modules, name, 'index.mjs'),
    'The public entrance must be the expected installed package entry');
}
// Resolve and validate all public entrances before any package can execute.
const {open} = await import(publicModules.get('@actql/node'));
const {createOpenAIChatProvider, createProjectOpenAIChatProvider} = await import(publicModules.get('@actql/provider-ai-sdk'));
const {createHostObservationConnection} = await import(publicModules.get('@actql/local-node/observation'));
const {workflowWorkObservation} = await import('./work-observation.fixture.mjs');
const work = workflowWorkObservation({createObservation: createHostObservationConnection});
const diagnostic = normalProviderDiagnostics({phase, work, write: writeFile});

// Local authored fixture configuration only. A cold process must use the same
// selected physical inputs; absence is not a reason to guess another profile.
const selection = fresh ? {
  usage: phase === 'project-key' ? 'reported' : phase.startsWith('usage-') ? phase.slice(6) : null,
  timeout: phase.startsWith('timeout-') ? phase.slice(8) : null,
  rateLimit: phase === 'rate-limit',
  project: phase === 'project-key',
} : JSON.parse(await readFile('case-profile.fixture.json', 'utf8'));
assert.deepEqual(Object.keys(selection).sort(), ['project', 'rateLimit', 'timeout', 'usage']);
assert([null, 'reported', 'zero', 'absent'].includes(selection.usage));
assert([null, 'headers', 'body', 'call'].includes(selection.timeout));
assert(selection.usage === null || selection.timeout === null);
const usageMode = selection.usage ?? undefined, timeoutMode = selection.timeout ?? undefined;
const project = selection.project === true;
if (project) assert.deepEqual(selection, {usage: 'reported', timeout: null, rateLimit: false, project: true});
const officialHost = 'api.openai.com';
const fixtureCredential = project ? 'actql-synthetic-project-credential' : 'not-an-external-secret';
const maxCalls = usageMode === 'reported' ? 1n : 2n;
const taskCount = !missingKey && usageMode === undefined && timeoutMode === undefined && !selection.rateLimit ? 2 : 1;
const phaseTimeoutMs = timeoutMode === 'call' ? 2000 : 1000;
const transportTimeouts = {
  connectMs: phaseTimeoutMs, headersMs: timeoutMode === 'headers' ? 30 : phaseTimeoutMs,
  bodyMs: timeoutMode === 'body' ? 30 : phaseTimeoutMs,
  callMs: timeoutMode === 'call' ? 500 : phaseTimeoutMs,
};

if (fresh) {
  await assert.rejects(access('.state'), {code: 'ENOENT'});
  const put = (path, value, mode = 0o600) => writeFile(path, value, {flag: 'wx', mode});
  if (!missingKey && !project) await put('provider-credential.fixture', fixtureCredential);
  await put('case-profile.fixture.json', JSON.stringify(selection));
  await put('actql.config.json', JSON.stringify({version: 'actql-config/0.1', model_tasks: './model-tasks.json'}));
  await put('model-tasks.json', JSON.stringify({version: 'actql-model-tasks/0.1',
    tasks: {'model-task:first': './first.json', 'model-task:second': './second.json'},
    providers: {'models/http': {type: 'openai', api_key_env: 'OPENAI_API_KEY'}}, default_provider: 'models/http'}));
  for (const [path, task] of [
    ['first.json', {task: 'model-task:first', instructions: 'Return the exact boolean.',
      input: {text: 'string'}, output: {answer: 'boolean'}, limits: {max_items: 2, max_output_tokens: 100}}],
    ['second.json', {task: 'model-task:second', instructions: 'Return the exact label.',
      input: {quantity: 'number'}, output: {label: 'string'}, limits: {max_items: 2, max_output_tokens: 100}}],
  ]) await put(path, JSON.stringify(task));
  const keys = generateKeyPairSync('ed25519');
  await put('operator-private.fixture', keys.privateKey.export({type: 'pkcs8', format: 'pem'}));
  await put('operator-public.fixture', keys.publicKey.export({type: 'spki', format: 'pem'}));
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'provider.key', '-out', 'provider.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', project ? 'subjectAltName=DNS:' + officialHost : 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {stdio: 'ignore'});
} else await access('.state');
if (project) {
  assert.equal(process.env.OPENAI_API_KEY, undefined, 'Do not inherit an operator credential');
  await assert.rejects(access('provider-credential.fixture'), {code: 'ENOENT'});
}

const certificate = await readFile('provider.crt', 'utf8');
setDefaultCACertificates([...getCACertificates('default'), certificate]);
let calls = 0, egressChecks = 0, projectTlsConnects = 0, unexpectedProjectConnection = false;
let pulse, continuousWrites = 0, responseClosedBeforeFirstClose = false, finishContinuousResponse;
const continuousResponseClosed = fresh && timeoutMode === 'call'
  ? new Promise(resolve => {finishContinuousResponse = resolve;}) : undefined;
const schemas = [];
const server = createServer({cert: certificate, key: await readFile('provider.key')}, async (request, response) => {
  calls++;
  assert.equal(missingKey, false, 'Missing project credential must never use the fixture transport');
  diagnostic.request(request);
  assert.equal(fresh, true, 'A Saved read must never contact the provider');
  assert.equal(request.url, '/v1/chat/completions');
  assert(request.headers.authorization === 'Bearer ' + fixtureCredential, 'Unexpected synthetic credential');
  if (project) {
    assert.equal(request.headers.host, officialHost);
    assert.equal(request.socket.servername, officialHost);
    assert.equal(request.socket.remoteAddress, '127.0.0.1');
  }
  let wire = '';
  for await (const chunk of request) {wire += chunk; assert(wire.length <= 32768);}
  const body = JSON.parse(wire);
  assert.equal(body.model, 'fixture-chat'); assert.notEqual(body.stream, true);
  schemas.push(body.response_format.json_schema.schema);
  const input = JSON.parse(body.messages[1].content);
  assert.deepEqual(input, calls === 1 ? {text: 'first'} : {quantity: 7});
  const value = calls === 1 ? {answer: true} : {label: 'exact-label'};
  if (timeoutMode === 'headers') return; // Actual request received; no response headers.
  response.setHeader('content-type', 'application/json');
  response.setHeader('x-request-id', 'installed-' + calls);
  if (selection.rateLimit) {
    response.statusCode = 429;
    response.end('{"error":{"code":"rate_limit"}}');
    return;
  }
  if (timeoutMode === 'body') {response.write('{'); return;} // Partial original, no EOF.
  if (timeoutMode === 'call') {
    // Stay far below the original 128-chunk/64KiB profile. Continuous data
    // prevents the 2000ms idle-body timeout from being this case's cause.
    response.write('{'); continuousWrites++;
    pulse = setInterval(() => {response.write(' '); continuousWrites++;}, 25);
    response.once('close', () => {clearInterval(pulse); finishContinuousResponse();});
    return;
  }

  response.end(JSON.stringify({id: 'installed-' + calls, object: 'chat.completion', created: 1,
    model: 'fixture-chat', choices: [{index: 0,
      message: {role: 'assistant', content: JSON.stringify(value)}, finish_reason: 'stop'}],
    ...(usageMode === 'absent' ? {} : {usage: usageMode === 'zero'
      ? {prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
      : {prompt_tokens: 2, completion_tokens: 3, total_tokens: 5}})}));
});
const port = fresh ? 0 : Number(await readFile('endpoint.fixture', 'utf8'));
await new Promise(resolve => server.listen(port, '127.0.0.1', resolve));
if (fresh) await writeFile('endpoint.fixture', String(server.address().port), {flag: 'wx', mode: 0o600});
const authorization = {
  observe: (event, detail) => diagnostic.dispatchFailure(event, detail),
  hostKey: {keyId: 'fixture-host', privateKey: await readFile('operator-private.fixture', 'utf8')},
  reviewers: [{keyId: 'fixture-reviewer', reviewerId: 'fixture-reviewer', principalId: userInfo().username,
    publicKey: await readFile('operator-public.fixture', 'utf8')}],
  accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1', account_id: 'installed-fixture',
    entries: [{entry_id: 'fixture-only', outcome: 'allow', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {all: true}, exclusions: []}]}),
};
const providerOptions = {modelId: 'fixture-chat',
  generation: {temperature: 0, topP: 1, maxOutputTokens: 100},
  transportTimeouts,
  budget: {maxCalls, maxRows: 2, maxTokens: 1000n, maxCostUnits: 100000n,
    maxDurationMs: BigInt(phaseTimeoutMs)},
  observeEgress: () => {
    egressChecks++;
    return {classification: 'public', region: 'global', providerRetention: true, trainingUse: false};
  }};
const registerModelProviders = missingKey || project ? createProjectOpenAIChatProvider(providerOptions)
  : createOpenAIChatProvider({...providerOptions, providerId: 'models/http',
    apiKeyFile: './provider-credential.fixture', baseURL: 'https://127.0.0.1:' + server.address().port + '/v1'});
const program = (task, field, value, type) => ({version: 'actql/0.1', id: 'installed-' + field,
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: {type: 'string', nullable: false}, [field]: {type, nullable: false}},
      rows: [{id: 'original-' + field, [field]: value}]}, as: 'input'},
    {assert_rows: {unique_by: ['id']}, as: 'unique'},
    {infer: {contract: task, key: 'id', input: {[field]: {field}}}, as: 'inferred'}],
    results: {answer: {from: 'inferred', fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'answer'}}}});
const textContract = {type: 'string', nullable: false};
async function checkResult(run, expected, index) {
  const result = await run.result('answer');
  assert.deepEqual(await result.all(), [expected]);
  const description = await result.describe();
  assert.deepEqual(description.ref, run.ref);
  assert.equal(description.resultName, 'answer');
  assert.deepEqual(description.columns, [
    {name: 'id', contract: textContract},
    {name: 'outcome', contract: textContract},
    {name: 'value', contract: {type: 'object', nullable: true, additional_properties: false,
      fields: index === 0 ? {answer: {type: 'boolean', nullable: false}} : {label: textContract}}},
  ]);
}
// New explicit usage-aware local callback contract. This small authored Sink
// persists only the bounded seven-field projection; it is not the old five-part
// evidence Sink, an independent Model issuer or physical-cleanup observation.
let originalRef, usageReceipt, usageCaptures = 0, usageAuthorizations = 0;
const policy = {kind: 'data_policy',
  wire: '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}',
  cid: 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563'};
const inferEvidence = usageMode === undefined ? undefined : {
  kind: 'usage', target: 'inferred', destination: 'local:installed-usage', maxBytes: 4096,
  authorize(binding) {
    usageAuthorizations++;
    assert.equal(binding.kind, 'usage'); assert.equal(binding.target, 'inferred');
    assert.equal(binding.destination, 'local:installed-usage');
    assert.deepEqual(binding.policy, policy);
    assert.deepEqual(binding.subject, {runDefinitionCid: originalRef.runDefinitionCid,
      authorityScopeCid: originalRef.authorityScopeCid});
    return true;
  },
  sink: {
    async capture(binding) {
      usageCaptures++;
      assert.deepEqual(Object.keys(binding.wires), ['usage']);
      const wire = binding.wires.usage;
      assert.equal(typeof wire, 'string'); assert(Buffer.byteLength(wire) <= 4096);
      const value = JSON.parse(wire);
      assert.deepEqual(Object.keys(value), ['input_tokens', 'invocation_evidence_cid', 'model_call_slot_cid',
        'model_task_contract_cid', 'observation_origin', 'output_tokens', 'raw_response_artifact_cid']);
      assert.equal(value.input_tokens, usageMode === 'absent' ? null : usageMode === 'zero' ? 0 : 2);
      assert.equal(value.output_tokens, usageMode === 'absent' ? null : usageMode === 'zero' ? 0 : 3);
      assert.equal(value.observation_origin, 'reported');
      assert.equal(value.model_call_slot_cid, binding.original.modelCallSlotCid);
      for (const cid of [value.invocation_evidence_cid, value.model_call_slot_cid,
        value.model_task_contract_cid, binding.original.captureBundleCid, binding.attemptCid]) {
        assert.match(cid, /^sha256:[0-9a-f]{64}$/);
      }
      assert(value.raw_response_artifact_cid === null || /^sha256:[0-9a-f]{64}$/.test(value.raw_response_artifact_cid));
      assert.equal(wire.includes(fixtureCredential), false);
      await writeFile('usage-original.json', wire, {flag: 'wx', mode: 0o600});
      return {status: 'complete'};
    },
    async record(receipt) {
      assert.equal(receipt.manifest.kind, 'usage'); assert.equal(receipt.manifest.status, 'complete');
      assert.equal(receipt.manifest.items.length, 1);
      assert.equal(receipt.manifest.items[0].status, 'complete');
      const wire = JSON.stringify(receipt);
      assert(Buffer.byteLength(wire) <= 4096);
      await writeFile('usage-receipt.json', wire, {flag: 'wx', mode: 0o600});
      usageReceipt = receipt;
    },
  },
};
let client, primary, failed = false;
const firstClose = {attempted: false, returned: false, calls: 0}, cleanup = [];
let close;
const connectTls = tls.connect;
try {
  if (project) {
    // Redirect only the socket in this fixture process. Keep its original
    // HTTPS host, SNI, certificate checks, request and installed transport.
    tls.connect = (options, ...args) => {
      if (!fresh || projectTlsConnects !== 0 || options?.host !== officialHost ||
          options.servername !== officialHost || Number(options.port) !== 443 ||
          options.socket !== undefined || options.rejectUnauthorized === false) {
        unexpectedProjectConnection = true;
        throw new Error('Unexpected project TLS connection');
      }
      projectTlsConnects++;
      return connectTls.call(tls, {...options, host: '127.0.0.1', port: server.address().port}, ...args);
    };
  }
  client = await open({stateDir: '.state', installation: {
    registerModelProviders, authorization, observation: work.connection,
    ...(inferEvidence === undefined ? {} : {inferEvidence, resultDataPolicy: policy})}});
  if (fresh) {
    if (project) process.env.OPENAI_API_KEY = fixtureCredential;
    const cases = [
      [0, ['model-task:first', 'text', 'first', 'string'], {id: 'original-text', outcome: 'ok', value: {answer: true}}],
      [1, ['model-task:second', 'quantity', 7, 'number'], {id: 'original-quantity', outcome: 'ok', value: {label: 'exact-label'}}],
    ];
    cases.length = taskCount;
    if (selection.rateLimit) cases[0][2] = {id: 'original-text', outcome: 'failed:provider_error', value: null};
    for (const [index, args, expected] of cases) {
      const submissionRef = client.newSubmission({nonce: 'installed-' + index});
      await writeFile('submission-' + index + '.json', JSON.stringify(submissionRef), {flag: 'wx', mode: 0o600});
      const run = await client.start(program(...args), {submissionRef});
      await writeFile('run-' + index + '.json', JSON.stringify(run.ref), {flag: 'wx', mode: 0o600});
      originalRef = run.ref;
      const waited = await run.wait();
      await diagnostic.terminal(index, waited);
      assert.equal(waited.status, missingKey ? 'failed'
        : timeoutMode === undefined ? 'succeeded' : 'needs_reconciliation');
      if (missingKey) {
        const recorded = JSON.parse(await readFile('normal-diagnostic-before-assert.json', 'utf8'));
        assert.equal(recorded.dispatchFailures.length, 1);
        assert.equal(recorded.dispatchFailures[0].credentialRefusal, 'OpenAIProjectCredentialUnavailable');
      } else if (timeoutMode === undefined) await checkResult(run, expected, index);
      else {
        const current = await run.status();
        assert.equal(current.status, 'needs_reconciliation');
        assert.equal(current.control.cancellation_requested, false, 'Physical timeout is not Run cancellation');
        if (timeoutMode === 'call') {
          let closeGuard;
          try {
            await Promise.race([continuousResponseClosed, new Promise((_, reject) => {
              closeGuard = setTimeout(() => reject(Error('WholeCallPeerCloseNotObserved')), 1000);
            })]);
          } finally {clearTimeout(closeGuard);}
          assert(continuousWrites >= 2 && continuousWrites < 128);
          // Observe the peer close before the fixture invokes public close or
          // closes its own server. This is not a native/remote operation ACK.
          responseClosedBeforeFirstClose = true;
        }
      }
      const lookup = await client.lookupSubmission(submissionRef);
      assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, run.ref);
    }
    assert.equal(calls, missingKey ? 0 : taskCount);
    if (taskCount === 2) assert.notDeepEqual(schemas[0], schemas[1]);
    if (usageMode !== undefined) {
      // The optional copy must have actually completed, not merely a successful
      // Model Run or a provider spy reporting authored usage.
      assert.equal(usageCaptures, 1); assert.equal(usageAuthorizations, 1);
      assert(usageReceipt !== undefined);
      assert.deepEqual(JSON.parse(await readFile('usage-receipt.json', 'utf8')), usageReceipt);
      assert.equal(JSON.parse(await readFile('usage-original.json', 'utf8')).observation_origin, 'reported');
    }
  } else {
    const ref = JSON.parse(await readFile('run-0.json', 'utf8'));
    const run = await client.attach(ref);
    if (timeoutMode === undefined) {
      // The original Saved Result precedes this process's first status read.
      const expected = selection.rateLimit ? {outcome: 'failed:provider_error', value: null}
        : {outcome: 'ok', value: {answer: true}};
      await checkResult(run, {id: 'original-text', ...expected}, 0);
      assert.equal((await run.status()).status, 'succeeded');
    } else {
      // This SAME entered original has no fabricated Saved success. Status and
      // original lookup only; never start, reconcile, cancel or resend a Call.
      const current = await run.status();
      assert.equal(current.status, 'needs_reconciliation');
      assert.equal(current.control.cancellation_requested, false);
    }
    const submissionRef = JSON.parse(await readFile('submission-0.json', 'utf8'));
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, ref);
    assert.equal(calls, 0); assert.equal(egressChecks, 0);
    assert.equal(usageCaptures, 0); assert.equal(usageAuthorizations, 0);
  }
} catch (cause) {failed = true;primary = cause;}
finally {
  if (client !== undefined) {
    firstClose.attempted = true;firstClose.calls++;
    try {await client.close();firstClose.returned = true;}
    catch (cause) {
      firstClose.error = {name: cause?.name, code: cause?.code};
      if (!failed) {failed = true;primary = cause;}
    }
  }
  if (project) {
    delete process.env.OPENAI_API_KEY;
    tls.connect = connectTls;
  }
  clearInterval(pulse);
  try {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
  catch (cause) {cleanup.push({name: cause?.name, code: cause?.code});if (!failed) {failed = true;primary = cause;}}
  try {close = observeOwnScopedStateFds([resolve('.state')]);}
  catch (cause) {cleanup.push({name: cause?.name, code: cause?.code});if (!failed) {failed = true;primary = cause;}}
  const recorded = await diagnostic.finish(firstClose, close, cleanup);
  if (!recorded.complete && !failed) {failed = true;primary = Error('NormalProviderDiagnosticIncomplete');}
  if (missingKey && !failed) assert.equal(recorded.value.work.modelCallStarts, 0);
}
if (failed) throw primary;
if (project) {
  assert.equal(unexpectedProjectConnection, false);
  assert.equal(projectTlsConnects, fresh ? 1 : 0);
}
assert.equal(close.aliveAfterClose, true); assert.equal(close.scopedStateFd0, true);
await assert.rejects(access('.state/publication/owner/owner.json'), {code: 'ENOENT'});
console.log(JSON.stringify({phase, calls, firstCloseReturned: true, aliveScopedFD0: true,
  ...(project ? {projectTlsConnects, projectCredential: true} : {}),
  ...(usageMode === 'reported' ? {maxCalls: Number(maxCalls)} : {}),
  ...(phase === 'cold' ? {egressChecks,
    ...(timeoutMode === undefined ? {originalSavedFirst: true} : {originalUnknown: true, zeroResend: true})}
    : {tasks: taskCount, requests: taskCount, ...(missingKey ? {credentialRefused: true} : {}),
      ...(usageMode === undefined ? {} : {usageMode, usageCaptures})}),
  ...(timeoutMode === undefined ? {} : {timeoutMode, preserveOriginalState: true}),
  ...(timeoutMode === 'call' && fresh ? {continuousWrites, responseClosedBeforeFirstClose} : {}),
  node: process.versions.node, platform: process.platform, arch: process.arch}));
