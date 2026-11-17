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
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {observeOwnScopedStateFds} from './conformance.mjs';

const phase = process.argv[2];
assert(['warm', 'cold'].includes(phase));
const modules = resolve(realpathSync(process.cwd()), 'node_modules');
assert.equal(realpathSync(modules), modules, 'The fresh node_modules must not redirect to another installation');
const publicModules = new Map(['@actql/node', '@actql/provider-ai-sdk']
  .map(name => [name, import.meta.resolve(name)]));
for (const [name, url] of publicModules) {
  const member = realpathSync(fileURLToPath(url));
  const selected = relative(modules, member);
  assert(!isAbsolute(selected) && selected !== '..' && !selected.startsWith('../'),
    'The public entrance must resolve inside this fresh installation');
  assert.equal(member, resolve(modules, name, 'index.mjs'),
    'The public entrance must be the expected installed package entry');
}
// Resolve and validate BOTH entrances before either package can execute.
const {connect} = await import(publicModules.get('@actql/node'));
const {createOpenAIChatProvider} = await import(publicModules.get('@actql/provider-ai-sdk'));

if (phase === 'warm') {
  await assert.rejects(access('.state'), {code: 'ENOENT'});
  const put = (path, value, mode = 0o600) => writeFile(path, value, {flag: 'wx', mode});
  await put('actql.config.json', JSON.stringify({version: 'actql-config/0.1', model_tasks: './model-tasks.json'}));
  await put('model-tasks.json', JSON.stringify({version: 'actql-model-tasks/0.1',
    tasks: {'model-task:first': './first.json', 'model-task:second': './second.json'},
    providers: {'models/http': {type: 'openai'}}, default_provider: 'models/http'}));
  for (const [path, task] of [
    ['first.json', {task: 'model-task:first', instructions: 'Return the exact boolean.',
      input: {text: 'string'}, output: {answer: 'boolean'}, limits: {max_items: 2, max_output_tokens: 100}}],
    ['second.json', {task: 'model-task:second', instructions: 'Return the exact label.',
      input: {quantity: 'number'}, output: {label: 'string'}, limits: {max_items: 2, max_output_tokens: 100}}],
  ]) await put(path, JSON.stringify(task));
  await put('api-key.fixture', 'not-an-external-secret');
  const keys = generateKeyPairSync('ed25519');
  await put('operator-private.fixture', keys.privateKey.export({type: 'pkcs8', format: 'pem'}));
  await put('operator-public.fixture', keys.publicKey.export({type: 'spki', format: 'pem'}));
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'provider.key', '-out', 'provider.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {stdio: 'ignore'});
} else await access('.state');

const certificate = await readFile('provider.crt', 'utf8');
setDefaultCACertificates([...getCACertificates('default'), certificate]);
let calls = 0, egressChecks = 0;
const schemas = [];
const server = createServer({cert: certificate, key: await readFile('provider.key')}, async (request, response) => {
  calls++;
  assert.equal(phase, 'warm', 'A Saved read must never contact the provider');
  assert.equal(request.url, '/v1/chat/completions');
  assert.equal(request.headers.authorization, 'Bearer not-an-external-secret');
  let wire = '';
  for await (const chunk of request) {wire += chunk; assert(wire.length <= 32768);}
  const body = JSON.parse(wire);
  assert.equal(body.model, 'fixture-chat'); assert.notEqual(body.stream, true);
  schemas.push(body.response_format.json_schema.schema);
  const input = JSON.parse(body.messages[1].content);
  assert.deepEqual(input, calls === 1 ? {text: 'first'} : {quantity: 7});
  const value = calls === 1 ? {answer: true} : {label: 'exact-label'};
  response.setHeader('content-type', 'application/json');
  response.setHeader('x-request-id', 'installed-' + calls);
  response.end(JSON.stringify({id: 'installed-' + calls, object: 'chat.completion', created: 1,
    model: 'fixture-chat', choices: [{index: 0,
      message: {role: 'assistant', content: JSON.stringify(value)}, finish_reason: 'stop'}],
    usage: {prompt_tokens: 2, completion_tokens: 3, total_tokens: 5}}));
});
const port = phase === 'warm' ? 0 : Number(await readFile('endpoint.fixture', 'utf8'));
await new Promise(resolve => server.listen(port, '127.0.0.1', resolve));
if (phase === 'warm') await writeFile('endpoint.fixture', String(server.address().port), {flag: 'wx', mode: 0o600});
const authorization = {
  hostKey: {keyId: 'fixture-host', privateKey: await readFile('operator-private.fixture', 'utf8')},
  reviewers: [{keyId: 'fixture-reviewer', reviewerId: 'fixture-reviewer', principalId: userInfo().username,
    publicKey: await readFile('operator-public.fixture', 'utf8')}],
  accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1', account_id: 'installed-fixture',
    entries: [{entry_id: 'fixture-only', outcome: 'allow', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {all: true}, exclusions: []}]}),
};
const registerModelProviders = createOpenAIChatProvider({providerId: 'models/http', modelId: 'fixture-chat',
  apiKeyFile: 'api-key.fixture', baseURL: 'https://127.0.0.1:' + server.address().port + '/v1',
  generation: {temperature: 0, topP: 1, maxOutputTokens: 100},
  budget: {maxCalls: 2n, maxRows: 2, maxTokens: 1000n, maxCostUnits: 100000n, maxDurationMs: 1000n},
  observeEgress: () => {
    egressChecks++;
    return {classification: 'public', region: 'global', providerRetention: true, trainingUse: false};
  }});
const program = (task, field, value, type) => ({version: 'actql/0.1', id: 'installed-' + field,
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: {type: 'string', nullable: false}, [field]: {type, nullable: false}},
      rows: [{id: 'original-' + field, [field]: value}]}, as: 'input'},
    {assert_rows: {unique_by: ['id']}, as: 'unique'},
    {infer: {contract: task, key: 'id', input: {[field]: {field}}}, as: 'inferred'}],
    results: {answer: {from: 'inferred', fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'answer'}}}});
let client, primary;
try {
  client = await connect({mode: 'local', owner: 'local', installation: {directory: '.state',
    registerModelProviders, authorization}});
  if (phase === 'warm') {
    for (const [index, args, expected] of [
      [0, ['model-task:first', 'text', 'first', 'string'], {id: 'original-text', outcome: 'ok', value: {answer: true}}],
      [1, ['model-task:second', 'quantity', 7, 'number'], {id: 'original-quantity', outcome: 'ok', value: {label: 'exact-label'}}],
    ]) {
      const submissionRef = client.newSubmission({nonce: 'installed-' + index});
      await writeFile('submission-' + index + '.json', JSON.stringify(submissionRef), {flag: 'wx', mode: 0o600});
      const run = await client.start(program(...args), {submissionRef});
      await writeFile('run-' + index + '.json', JSON.stringify(run.ref), {flag: 'wx', mode: 0o600});
      assert.equal((await run.wait()).status, 'succeeded');
      assert.deepEqual(await run.result('answer').all(), [expected]);
      const lookup = await client.lookupSubmission(submissionRef);
      assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, run.ref);
    }
    assert.equal(calls, 2); assert.notDeepEqual(schemas[0], schemas[1]);
  } else {
    const ref = JSON.parse(await readFile('run-0.json', 'utf8'));
    const run = await client.attach(ref);
    // The original Saved Result precedes this process's first status read.
    assert.deepEqual(await run.result('answer').all(), [{id: 'original-text', outcome: 'ok', value: {answer: true}}]);
    assert.equal((await run.status()).status, 'succeeded');
    const submissionRef = JSON.parse(await readFile('submission-0.json', 'utf8'));
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, ref);
    assert.equal(calls, 0); assert.equal(egressChecks, 0);
  }
} catch (cause) {primary = cause;}
finally {
  try {await client?.close();} catch (cause) {primary ??= cause;}
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
}
const close = observeOwnScopedStateFds([resolve('.state')]);
if (primary !== undefined) throw primary;
assert.equal(close.aliveAfterClose, true); assert.equal(close.scopedStateFd0, true);
await assert.rejects(access('.state/publication/owner/owner.json'), {code: 'ENOENT'});
console.log(JSON.stringify({phase, calls, firstCloseReturned: true, aliveScopedFD0: true,
  ...(phase === 'cold' ? {originalSavedFirst: true, egressChecks} : {tasks: 2, requests: 2}),
  node: process.versions.node, platform: process.platform, arch: process.arch}));
