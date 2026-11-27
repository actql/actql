// Copy this authored consumer and external-rest/conformance.mjs into a fresh
// outside-checkout installation. Only installed public package entrances run.
import assert from 'node:assert/strict';
import {createHook} from 'node:async_hooks';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {createRequire, registerHooks} from 'node:module';
import {realpathSync} from 'node:fs';
import {access, lstat, mkdir, readdir, readFile, writeFile} from 'node:fs/promises';
import {setTimeout as waitFor} from 'node:timers/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {isAbsolute, relative, resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import tls, {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {observeOwnScopedStateFds} from './conformance.mjs';
import {closedModelRawEvidence, modelPlanFixtureDigest, normalProviderDiagnostics, omitFixtureModelPlanBinding,
  verifyFixtureModelPlanBindingStillAbsent} from './normal-provider-diagnostics.fixture.mjs';

const phase = process.argv[2];
assert(['warm', 'cold', 'missing-key', 'project-key', 'rate-limit', 'usage-reported', 'usage-zero', 'usage-absent',
  'timeout-headers', 'timeout-body', 'timeout-call', 'registered-project', 'registered-too-late', 'registered-invalid',
  'registered-credential-reference', 'registered-credential-header', 'registered-anthropic',
  'registered-foreign-model', 'registered-missing-routes',
  'registered-google', 'registered-mixed', 'registered-mistral', 'registered-openai-responses',
  'registered-openai-responses-over-limit', 'registered-external', 'registered-external-double', 'registered-length', 'registered-refusal',
  'registered-response-loss', 'registered-entered-cancel', 'registered-http-401', 'registered-http-503',
  'registered-openai-filter', 'registered-google-recitation', 'registered-google-blocklist', 'registered-capabilities',
  'changed-route', 'retained-unbound', 'direct-project', 'direct-response-loss', 'direct-partial-raw'].includes(phase));
const changedRoute = phase === 'changed-route';
const retainedUnbound = phase === 'retained-unbound';
const fresh = phase !== 'cold' && !changedRoute && !retainedUnbound;
const savedSelection = fresh ? undefined : JSON.parse(await readFile('case-profile.fixture.json', 'utf8'));
const directHttp = fresh ? phase.startsWith('direct-') : savedSelection.directHttp === true;
const directResponseLoss = fresh ? phase === 'direct-response-loss' : savedSelection.directResponseLoss === true;
const directPartialRaw = fresh ? phase === 'direct-partial-raw' : savedSelection.directPartialRaw === true;
const directUnknown = directResponseLoss || directPartialRaw;
assert(!directUnknown || directHttp);
assert(!directResponseLoss || !directPartialRaw);
const directPeerHost = directResponseLoss ? '127.0.0.1' : 'localhost';
const partialProviderBody = 'Controll';
const partialProviderResponse = 'Controlled provider unavailable';
const missingKey = phase === 'missing-key';
const credentialMismatch = phase.startsWith('registered-credential-');
const bindingRefusal = phase === 'registered-foreign-model' || phase === 'registered-missing-routes';
const responsesOverLimit = phase === 'registered-openai-responses-over-limit';
const modules = resolve(realpathSync(process.cwd()), 'node_modules');
assert.equal(realpathSync(modules), modules, 'The fresh node_modules must not redirect to another installation');
const providerPackage = directHttp ? '@actql/local-node' : '@actql/provider-ai-sdk';
const publicModules = new Map(['@actql/node', '@actql/sdk', providerPackage, '@actql/local-node/observation']
  .map(name => [name, import.meta.resolve(name)]));
const standaloneProviderPackages = ['@actql/provider-ai-sdk', '@actql/provider-http', 'ai', '@ai-sdk/openai'];
const isSdkDependency = name => name === 'ai' || name === '@actql/provider-ai-sdk' || name.startsWith('@ai-sdk/');

async function installedDirectDependencyClosure() {
  const installed = [];
  const pending = [modules];
  async function inspect(entry, directory, scope = '') {
    assert(entry.isDirectory(), 'Direct HTTP package ownership requires a real installed directory');
    const path = resolve(directory, entry.name);
    const manifest = JSON.parse(await readFile(resolve(path, 'package.json'), 'utf8'));
    assert.equal(typeof manifest.name, 'string');
    assert.equal(typeof manifest.version, 'string');
    const requested = scope + entry.name;
    assert(!isSdkDependency(requested) && !isSdkDependency(manifest.name),
      'SDK-free installation contains ' + relative(modules, path));
    const dependencies = ['dependencies', 'optionalDependencies', 'peerDependencies']
      .flatMap(field => Object.keys(manifest[field] ?? {})).sort();
    assert(!dependencies.some(isSdkDependency), 'SDK-free installation declares a dependency on AI SDK in ' + manifest.name);
    installed.push(JSON.stringify([relative(modules, path), manifest.name, manifest.version, dependencies]));
    pending.push(resolve(path, 'node_modules'));
  }
  for (const directory of pending) {
    const status = await lstat(directory).catch(error => {
      if (error.code === 'ENOENT') return undefined;
      throw error;
    });
    if (status === undefined) continue;
    assert(status.isDirectory(), 'Direct HTTP dependency tree must be a real installed directory');
    const entries = await readdir(directory, {withFileTypes: true});
    for (const entry of entries) {
      if (entry.name.startsWith('.')) continue;
      if (entry.name.startsWith('@')) {
        assert(entry.isDirectory(), 'Direct HTTP package scope must be a real installed directory');
        const scope = resolve(directory, entry.name);
        for (const child of await readdir(scope, {withFileTypes: true})) {
          await inspect(child, scope, entry.name + '/');
        }
      } else await inspect(entry, directory);
    }
  }
  assert(installed.length > 0);
  return {packages: installed.length, sha256: createHash('sha256').update(installed.sort().join('\n')).digest('hex')};
}

let directDependencyClosure;
if (directHttp) {
  // The installation must lack the optional SDK and standalone Provider package.
  for (const name of standaloneProviderPackages) {
    assert.throws(() => import.meta.resolve(name), {code: 'ERR_MODULE_NOT_FOUND'},
      'SDK-free installation resolved optional package ' + name);
  }
  directDependencyClosure = await installedDirectDependencyClosure();
}
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
const {getSubmissionAttempt} = await import(publicModules.get('@actql/sdk'));
const providerModule = publicModules.get(providerPackage);
const {createHostObservationConnection} = await import(publicModules.get('@actql/local-node/observation'));
const {workflowWorkObservation} = await import('./work-observation.fixture.mjs');

// Local authored fixture configuration only. A cold process must use the same
// selected physical inputs; absence is not a reason to guess another profile.
const alternative = {'registered-anthropic': 'anthropic', 'registered-google': 'google',
  'registered-mixed': 'mixed', 'registered-mistral': 'mistral', 'registered-external': 'external', 'registered-external-double': 'external',
  'registered-openai-responses': 'responses',
  'registered-openai-responses-over-limit': 'responses',
  'registered-google-recitation': 'google', 'registered-google-blocklist': 'google'}[phase];
const safetyFinish = {'registered-openai-filter': 'content_filter', 'registered-google-recitation': 'RECITATION',
  'registered-google-blocklist': 'BLOCKLIST'}[phase];
const terminalFailure = safetyFinish === undefined
  ? {'registered-length': 'truncated', 'registered-refusal': 'refusal'}[phase] : 'safety_rejected';
const httpResponse = {'rate-limit': 429, 'registered-http-401': 401, 'registered-http-503': 503}[phase];
const selection = fresh ? {
  usage: ['registered-mixed', 'registered-response-loss', 'registered-entered-cancel'].includes(phase) ||
      terminalFailure !== undefined || httpResponse !== undefined || directUnknown
    ? null : phase === 'project-key' || directHttp || phase.startsWith('registered-') ? 'reported'
    : phase.startsWith('usage-') ? phase.slice(6) : null,
  timeout: phase.startsWith('timeout-') ? phase.slice(8) : null,
  httpStatus: httpResponse ?? 200,
  ...(phase === 'registered-response-loss' ? {interruption: 'response-loss'} : {}),
  ...(phase === 'registered-entered-cancel' ? {interruption: 'entered-cancel'} : {}),
  ...(alternative === undefined ? {} : {provider: alternative}),
  ...(phase === 'registered-external-double' ? {externalDuplicate: true} : {}),
  ...(phase === 'registered-capabilities' ? {capabilities: true} : {}),
  ...(terminalFailure === undefined ? {} : {terminalFailure}),
  ...(safetyFinish === undefined ? {} : {safetyFinish}),
  ...(directHttp ? {directHttp, directResponseLoss, directPartialRaw} : {}),
} : savedSelection;
assert([undefined, 'anthropic', 'google', 'mixed', 'mistral', 'responses', 'external'].includes(selection.provider));
const mixed = selection.provider === 'mixed';
const capabilities = selection.capabilities === true;
if (changedRoute || retainedUnbound) assert(capabilities);
const external = selection.provider === 'external';
const externalDuplicate = selection.externalDuplicate === true;
if (externalDuplicate) assert(external);
const mistral = selection.provider === 'mistral';
const failedAnswer = selection.terminalFailure;
const selectedSafetyFinish = selection.safetyFinish;
const httpStatus = selection.httpStatus;
assert([200, 401, 429, 503].includes(httpStatus));
const httpFailure = httpStatus === 200 ? undefined : httpStatus === 429 ? 'rate_limit' : 'provider_error';
const outcomeFailure = failedAnswer ?? httpFailure;
assert([undefined, 'truncated', 'refusal', 'safety_rejected'].includes(failedAnswer));
if (failedAnswer === 'safety_rejected') {
  assert(selection.provider === 'google'
    ? ['RECITATION', 'BLOCKLIST'].includes(selectedSafetyFinish)
    : selection.provider === undefined && selectedSafetyFinish === 'content_filter');
} else assert.equal(selectedSafetyFinish, undefined);
const responses = selection.provider === 'responses';
const interruption = selection.interruption;
assert([undefined, 'response-loss', 'entered-cancel'].includes(interruption));
const trackOriginal = directHttp || capabilities || mixed || mistral || responses || external ||
  outcomeFailure !== undefined || interruption !== undefined;
const work = workflowWorkObservation({createObservation: createHostObservationConnection, trackOriginal});
const diagnostic = normalProviderDiagnostics({phase, work, write: writeFile});
assert.deepEqual(Object.keys(selection).sort(),
  [...(capabilities ? ['capabilities'] : []),
    ...(directHttp ? ['directHttp', 'directResponseLoss', 'directPartialRaw'] : []), ...(externalDuplicate ? ['externalDuplicate'] : []), 'httpStatus',
    ...(interruption === undefined ? [] : ['interruption']),
    ...(selection.provider === undefined ? [] : ['provider']),
    ...(selectedSafetyFinish === undefined ? [] : ['safetyFinish']),
    ...(failedAnswer === undefined ? [] : ['terminalFailure']), 'timeout', 'usage']);
assert([null, 'reported', 'zero', 'absent'].includes(selection.usage));
assert([null, 'headers', 'body', 'call'].includes(selection.timeout));
assert(selection.usage === null || selection.timeout === null);
const usageMode = selection.usage ?? undefined, timeoutMode = selection.timeout ?? undefined;
const unknown = directUnknown || timeoutMode !== undefined || interruption !== undefined;
if (interruption !== undefined) assert.equal(usageMode, undefined);
const enteredCancel = interruption === 'entered-cancel';
if (failedAnswer !== undefined) assert(selectedSafetyFinish !== undefined || selection.provider === undefined);
if (directHttp) assert.deepEqual(selection, {directHttp: true, directResponseLoss, directPartialRaw,
  httpStatus: 200, timeout: null, usage: directUnknown ? null : 'reported'});
const providerName = mixed || external ? 'openai' : selection.provider ?? 'openai';
const routeFixtures = {
  openai: {officialHost: 'api.openai.com', credentialReference: 'OPENAI_API_KEY',
    credentialHeader: 'authorization', credentialPrefix: 'Bearer ', requestPath: '/v1/chat/completions',
    resolvedModelId: 'fixture-chat', path: '_internal/openai-chat.mjs', version: '4.0.91',
    exportName: 'createOpenAI', apiMode: 'chat_completions', options: {store: false, strictJsonSchema: true}},
  responses: {officialHost: 'api.openai.com', credentialReference: 'OPENAI_API_KEY',
    credentialHeader: 'authorization', credentialPrefix: 'Bearer ', requestPath: '/v1/responses',
    resolvedModelId: 'gpt-4.1-mini', path: '_internal/openai-responses.mjs', version: '4.0.91',
    exportName: 'createOpenAI', apiMode: 'responses', options: {store: false, strictJsonSchema: true}},
  anthropic: {officialHost: 'api.anthropic.com', credentialReference: 'ANTHROPIC_API_KEY',
    credentialHeader: 'x-api-key', credentialPrefix: '', requestPath: '/v1/messages',
    resolvedModelId: 'claude-sonnet-4-6', path: '_internal/anthropic-messages.mjs', version: '4.0.107',
    exportName: 'createAnthropic', apiMode: 'messages', options: {structuredOutputMode: 'outputFormat'}},
  google: {officialHost: 'generativelanguage.googleapis.com', credentialReference: 'GOOGLE_GENERATIVE_AI_API_KEY',
    credentialHeader: 'x-goog-api-key', credentialPrefix: '',
    requestPath: '/v1beta/models/gemini-2.5-flash:generateContent', resolvedModelId: 'gemini-2.5-flash',
    path: '_internal/google-generate-content.mjs', version: '4.0.124', exportName: 'createGoogle',
    apiMode: 'generate_content', options: {structuredOutputs: true}},
  mistral: {officialHost: 'api.mistral.ai', credentialReference: 'MISTRAL_API_KEY',
    credentialHeader: 'authorization', credentialPrefix: 'Bearer ', requestPath: '/v1/chat/completions',
    resolvedModelId: 'mistral-small-2603', path: '_internal/mistral-chat.mjs', version: '4.0.89',
    exportName: 'createMistral', apiMode: 'chat_completions', options: {strictJsonSchema: true}},
};
const route = (name, providerId, index) => ({...routeFixtures[name], name: name === 'responses' ? 'openai' : name, providerId, index,
  selector: name === 'anthropic' && mixed ? 'fixture-messages' : 'fixture-chat'});
const routes = [route(providerName, 'models/http', 0)];
if (mixed) routes.push(route('anthropic', 'models/messages', 1));
const selectedRoute = routes[0];
const deniedAlias = 'fixture-unsupported';
const {credentialReference} = selectedRoute;
const routesByHost = new Map(routes.map(original => [original.officialHost, original]));
const fixtureCredential = 'actql-synthetic-project-credential';
const credentialValue = original => mixed ? fixtureCredential + '-' + original.name : fixtureCredential;
const independentAdapter = '@actql-acceptance/external-openai-adapter';
let externalDuplicateSource;
function frozenPackageImages(value) {
  for (const member of Object.values(value)) {
    if (member !== null && typeof member === 'object') frozenPackageImages(member);
  }
  return Object.freeze(value);
}
const originals = [];
if (!directHttp) {
  const adapterModule = external ? import.meta.resolve(independentAdapter) : providerModule;
  if (external) assert.equal(realpathSync(fileURLToPath(adapterModule)), resolve(modules, independentAdapter, 'index.mjs'));
  const packageImages = external ? frozenPackageImages(JSON.parse(await readFile('external-package-images.fixture.json', 'utf8'))) : undefined;
  const adapterManifest = JSON.parse(await readFile(new URL('package.json', adapterModule), 'utf8'));
  assert.equal(adapterManifest.name, external ? independentAdapter : '@actql/provider-ai-sdk');
  const adapterPackage = {packageName: adapterManifest.name, version: adapterManifest.version};
  for (const original of routes) {
    const packageName = '@ai-sdk/' + original.name;
    const sdkEntry = createRequire(new URL(adapterModule)).resolve(packageName);
    assert.equal(sdkEntry, realpathSync(sdkEntry));
    assert(sdkEntry.startsWith(modules + '/') && sdkEntry.endsWith('/' + packageName + '/dist/index.js'));
    const image = async (path, file) => Object.freeze({path,
      cid: 'sha256:' + createHash('sha256').update(await readFile(file)).digest('hex')});
    const {version, exportName, apiMode, options} = original;
    const path = externalDuplicate ? 'second-fetch.mjs' : external ? 'index.mjs' : original.path;
    if (externalDuplicate) externalDuplicateSource = new URL(path, adapterModule);
    const exact = Object.freeze({modelId: changedRoute ? 'fixture-changed-model' : original.resolvedModelId,
      selector: original.selector, apiMode, endpoint: 'https://' + original.officialHost + original.requestPath,
      structuredCapability: Object.freeze({operation: 'structured_generate', adapter: 'supported', model: 'supported'}),
      providerOptions: Object.freeze(options),
      credential: Object.freeze({
        reference: phase === 'registered-credential-reference' ? 'ACTQL_TEST_UNAPPROVED_MODEL_KEY' : original.credentialReference,
        header: phase === 'registered-credential-header' ? 'x-api-key' : original.credentialHeader,
      }),
    });
    const unsupported = capabilities ? [Object.freeze({...exact, selector: deniedAlias, modelId: 'fixture-model-without-json',
      structuredCapability: Object.freeze({...exact.structuredCapability, model: 'unsupported'})})] : [];
    originals.push(Object.freeze({
      adapter: Object.freeze({...await image(path, new URL(path, adapterModule)), ...adapterPackage}),
      lock: Object.freeze({...await image('npm-shrinkwrap.json', new URL('npm-shrinkwrap.json', adapterModule)), ...adapterPackage}),
      ...(packageImages === undefined ? {} : {packageImages}),
      sdk: Object.freeze({...await image('dist/index.js', sdkEntry), packageName, version, exportName}),
      providerId: original.providerId, defaultSelector: original.selector,
      routes: Object.freeze([exact, ...unsupported]),
    }));
  }
}
const modelSdkRegistrations = Object.freeze(originals);
if (phase === 'registered-invalid') {
  const original = modelSdkRegistrations[0];
  const sdk = Object.freeze({...original.sdk, cid: 'sha256:' + '0'.repeat(64)});
  assert.notEqual(sdk.cid, original.sdk.cid);
  const invalid = Object.freeze([Object.freeze({...original, sdk})]);
  const initialRegisterHooks = registerHooks;
  let registrations = 0;
  await writeFile('actql.config.json', '{"version":"actql-config/0.1"}', {flag: 'wx', mode: 0o600});
  await assert.rejects(open({stateDir: '.rejected-state', installation: {modelSdkRegistrations: invalid,
    registerModelProviders() {registrations++; return [];}}}), {code: 'InvalidInstalledModelSdkInstallation'});
  assert.equal(registrations, 0);
  assert.equal(registerHooks, initialRegisterHooks);
  await assert.rejects(access('.rejected-state'), {code: 'ENOENT'});
  const client = await open({stateDir: '.state'});
  await client.close();
  assert.equal(observeOwnScopedStateFds([resolve('.state')]).scopedStateFd0, true);
  await assert.rejects(access('.state/publication/owner/owner.json'), {code: 'ENOENT'});
  console.log(JSON.stringify({phase, startupRefused: true, registrations, calls: 0,
    defaultOpened: true, firstCloseReturned: true, aliveScopedFD0: true}));
  process.exit(0);
}
if (phase === 'registered-too-late') {
  // The first ordinary Host makes the actual selection and closes the loader.
  // A distinct genuine file in the verified SDK graph is too late afterward.
  const initial = await open({stateDir: '.initial-state', installation: {modelSdkRegistrations}});
  await initial.close();
  const original = modelSdkRegistrations[0];
  const sdkEntry = createRequire(new URL(providerModule)).resolve('@ai-sdk/openai/internal');
  const sdk = Object.freeze({...original.sdk, path: 'dist/internal/index.js',
    cid: 'sha256:' + createHash('sha256').update(await readFile(sdkEntry)).digest('hex')});
  const late = Object.freeze([Object.freeze({...original, sdk})]);
  let registrations = 0;
  await assert.rejects(open({stateDir: '.state', installation: {modelSdkRegistrations: late,
    registerModelProviders() {registrations++; return [];}}}), {code: 'InitialControlSdkImageUnavailable'});
  assert.equal(registrations, 0);
  await assert.rejects(access('.state'), {code: 'ENOENT'});
  process.stdout.write(JSON.stringify({phase, startupRefused: true, registrations, calls: 0}) + '\n');
  process.exit(0);
}
const maxCalls = directHttp || usageMode === 'reported' || mixed || failedAnswer !== undefined || interruption !== undefined ? 1n : 2n;
const taskCount = capabilities ? 2 : !directHttp && !missingKey && usageMode === undefined && !unknown &&
  outcomeFailure === undefined ? 2 : 1;
const phaseTimeoutMs = enteredCancel ? 8000 : timeoutMode === 'call' ? 2000 : 1000;
const transportTimeouts = {
  connectMs: phaseTimeoutMs, headersMs: timeoutMode === 'headers' ? 30 : phaseTimeoutMs,
  bodyMs: directPartialRaw ? 250 : timeoutMode === 'body' ? 30 : phaseTimeoutMs,
  callMs: timeoutMode === 'call' ? 500 : phaseTimeoutMs,
};

if (fresh) {
  await assert.rejects(access('.state'), {code: 'ENOENT'});
  const put = (path, value, mode = 0o600) => writeFile(path, value, {flag: 'wx', mode});
  await put('case-profile.fixture.json', JSON.stringify(selection));
  await put('actql.config.json', JSON.stringify({version: 'actql-config/0.1', model_tasks: './model-tasks.json'}));
  await put('model-tasks.json', JSON.stringify({version: 'actql-model-tasks/0.1',
    tasks: {'model-task:first': './first.json', 'model-task:second': './second.json'},
    providers: Object.fromEntries(routes.map(original => [original.providerId,
      {type: original.name, api_key_env: original.credentialReference}])),
    default_provider: 'models/http'}));
  for (const [path, task] of [
    ['first.json', {task: 'model-task:first', instructions: 'Return the exact boolean.',
      input: {text: 'string'}, output: {answer: 'boolean'}, limits: {
        max_items: 2, max_output_tokens: responsesOverLimit ? 101 : 100}}],
    ['second.json', {task: 'model-task:second', instructions: 'Return the exact label.',
      ...(mixed ? {model: {provider: routes[1].providerId, name: routes[1].selector}}
        : capabilities ? {model: {provider: selectedRoute.providerId, name: deniedAlias}} : {}),
      input: {quantity: 'number'}, output: {label: 'string'}, limits: {max_items: 2, max_output_tokens: 100}}],
  ]) await put(path, JSON.stringify(task));
  const keys = generateKeyPairSync('ed25519');
  await put('operator-private.fixture', keys.privateKey.export({type: 'pkcs8', format: 'pem'}));
  await put('operator-public.fixture', keys.publicKey.export({type: 'spki', format: 'pem'}));
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'provider.key', '-out', 'provider.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', directHttp ? 'subjectAltName=DNS:localhost,IP:127.0.0.1'
      : 'subjectAltName=' + routes.map(original => 'DNS:' + original.officialHost).join(',')],
  {stdio: 'ignore'});
} else await access('.state');
for (const original of routes) {
  assert.equal(process.env[original.credentialReference], undefined, 'Do not inherit an operator credential');
}

const certificate = await readFile('provider.crt', 'utf8');
setDefaultCACertificates([...getCACertificates('default'), certificate]);
let calls = 0, egressChecks = 0, projectTlsConnects = 0, unexpectedProjectConnection = false;
let peerTcpAccepts = 0, peerTlsHandshakes = 0, peerSocketCloses = 0, modelCredentialReads = 0;
let originalDirectResponseCid;
let directDnsStarted = 0, directDnsCompleted = 0, directDnsOriginal, peerServerName = null;
const directDnsObserver = directHttp ? createHook({
  init(id, type) {
    if (type !== 'GETADDRINFOREQWRAP') return;
    directDnsStarted++;
    if (directDnsStarted === 1) directDnsOriginal = id;
  },
  after(id) {
    if (id === directDnsOriginal) directDnsCompleted++;
  },
}).enable() : undefined;
let pulse, continuousWrites = 0, responseClosedBeforeFirstClose = false, finishContinuousResponse;
let completedHttpFailures = 0;
const continuousResponseClosed = fresh && timeoutMode === 'call'
  ? new Promise(resolve => {finishContinuousResponse = resolve;}) : undefined;
const enteredRequest = Promise.withResolvers(), interruptedResponse = Promise.withResolvers();
async function awaitPeer(pending, issue) {
  let deadline;
  try {
    await Promise.race([pending, new Promise((_, reject) => {
      deadline = setTimeout(() => reject(Error(issue)), 5000);
    })]);
  } finally {clearTimeout(deadline);}
}
const schemas = [], dispatchedProviders = new Set(), connectedHosts = new Set();
const server = createServer({cert: certificate, key: await readFile('provider.key')}, async (request, response) => {
  calls++;
  assert.equal(missingKey, false, 'Missing project credential must never use the fixture transport');
  diagnostic.request(request);
  assert.equal(fresh, true, 'A Saved read must never contact the provider');
  const original = mixed ? routesByHost.get(request.headers.host) : selectedRoute;
  assert(original !== undefined, 'The request must belong to one selected Provider');
  const {officialHost, credentialHeader, credentialPrefix, requestPath, resolvedModelId} = original;
  const anthropic = original.name === 'anthropic', google = original.name === 'google';
  const index = mixed ? original.index : calls - 1;
  if (mixed) assert.equal(dispatchedProviders.has(original.providerId), false, 'One dispatch per original Provider');
  dispatchedProviders.add(original.providerId);
  assert.equal(request.url, requestPath);
  if (directHttp) {
    assert.equal(request.method, 'POST');
    assert.equal(request.headers.host, directPeerHost + ':' + server.address().port);
    assert.equal(request.socket.remoteAddress, '127.0.0.1');
  }
  assert(request.headers[credentialHeader] === credentialPrefix + credentialValue(original),
    'Unexpected synthetic credential');
  if (!directHttp) assert.equal(request.headers.host, officialHost);
  assert.equal(request.socket.servername, officialHost);
  assert.equal(request.socket.remoteAddress, '127.0.0.1');
  let wire = '';
  for await (const chunk of request) {wire += chunk; assert(wire.length <= 32768);}
  const body = JSON.parse(wire);
  if (!google) assert.equal(body.model, resolvedModelId);
  assert.notEqual(body.stream, true);
  let schema, promptText;
  if (anthropic) {
    assert.equal(body.output_config.format.type, 'json_schema');
    assert.equal(body.output_config.format.schema.properties[index === 0 ? 'answer' : 'label'].type,
      index === 0 ? 'boolean' : 'string');
    assert.equal(body.tools, undefined);
    assert.deepEqual(body.system, [{type: 'text', text: index === 0 ? 'Return the exact boolean.' : 'Return the exact label.'}]);
    schema = body.output_config.format.schema;
    promptText = body.messages[0].content[0].text;
  } else if (google) {
    assert.equal(body.generationConfig.responseMimeType, 'application/json');
    assert.equal(body.generationConfig.responseJsonSchema.properties.answer.type, 'boolean');
    assert.equal(body.tools, undefined);
    assert.deepEqual(body.systemInstruction, {parts: [{text: 'Return the exact boolean.'}]});
    schema = body.generationConfig.responseJsonSchema;
    promptText = body.contents[0].parts[0].text;
  } else if (mistral) {
    assert.equal(body.response_format.type, 'json_schema');
    assert.equal(body.response_format.json_schema.strict, true);
    assert.equal(body.tools, undefined);
    assert.deepEqual(body.messages[0], {role: 'system', content: 'Return the exact boolean.'});
    schema = body.response_format.json_schema.schema;
    assert.equal(schema.properties.answer.type, 'boolean');
    assert.equal(body.messages[1].content.length, 1);
    assert.equal(body.messages[1].content[0].type, 'text');
    promptText = body.messages[1].content[0].text;
  } else if (responses) {
    assert.equal(body.store, false);
    assert.equal(body.temperature, 0.25);
    assert.equal(body.top_p, 0.5);
    assert.equal(body.max_output_tokens, 100);
    assert.equal(body.tools, undefined);
    assert.equal(body.previous_response_id, undefined);
    assert.equal(body.text.format.type, 'json_schema');
    assert.equal(body.text.format.strict, true);
    schema = body.text.format.schema;
    assert.equal(schema.properties.answer.type, 'boolean');
    promptText = body.input[1].content[0].text;
    assert.deepEqual(body.input, [{role: 'system', content: 'Return the exact boolean.'},
      {role: 'user', content: [{type: 'input_text', text: promptText}]}]);
  } else {
    assert.equal(body.store, false, 'The selected SDK options must reach the actual request');
    schema = body.response_format.json_schema.schema;
    promptText = body.messages[1].content;
  }
  schemas.push(schema);
  const input = JSON.parse(promptText);
  assert.deepEqual(input, index === 0 ? {text: 'first'} : {quantity: 7});
  const value = index === 0 ? {answer: true} : {label: 'exact-label'};
  if (interruption !== undefined) {
    response.once('close', interruptedResponse.resolve);
    enteredRequest.resolve();
    if (!enteredCancel) request.socket.destroy();
    return;
  }
  if (timeoutMode === 'headers') return; // Actual request received; no response headers.
  if (directResponseLoss) {
    response.destroy();
    return;
  }
  if (directPartialRaw) {
    response.writeHead(503, {'content-type': 'text/plain',
      'content-length': Buffer.byteLength(partialProviderResponse), 'x-request-id': 'installed-partial'});
    response.write(partialProviderBody);
    // The original transport's body timeout retires the stalled peer.
    return;
  }
  response.setHeader('content-type', 'application/json');
  response.setHeader('x-request-id', 'installed-' + calls);

  if (responses) {
    response.end(JSON.stringify({id: 'installed-' + calls, model: resolvedModelId, status: 'completed',
      output: [{type: 'message', id: 'message-' + calls, role: 'assistant',
        content: [{type: 'output_text', text: JSON.stringify(value), annotations: []}]}],
      usage: {input_tokens: 2, output_tokens: 3, total_tokens: 5}}));
    return;
  }
  if (httpFailure !== undefined) {
    response.once('finish', () => {completedHttpFailures++;});
    response.statusCode = httpStatus;
    response.end(httpFailure === 'rate_limit' ? '{"error":{"code":"rate_limit"}}'
      : '{"error":{"message":"authored provider refusal","type":"fixture_error","code":"fixture_error"}}');
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

  if (google && selectedSafetyFinish !== undefined) {
    const original = {modelVersion: 'fixture-google-reported-model', responseId: 'installed-' + calls};
    if (selectedSafetyFinish === 'BLOCKLIST') {
      response.end(JSON.stringify({...original, promptFeedback: {blockReason: selectedSafetyFinish}}));
    } else {
      response.end(JSON.stringify({...original, candidates: [{index: 0, finishReason: selectedSafetyFinish}],
        usageMetadata: {promptTokenCount: 0, candidatesTokenCount: 0, totalTokenCount: 0}}));
    }
    return;
  }
  if (google) {
    response.end(JSON.stringify({modelVersion: resolvedModelId, candidates: [{index: 0, finishReason: 'STOP',
      content: {role: 'model', parts: [{text: JSON.stringify(value)}]}}],
    usageMetadata: {promptTokenCount: 2, candidatesTokenCount: 2, thoughtsTokenCount: 1, totalTokenCount: 5}}));
    return;
  }
  if (failedAnswer !== undefined) {
    const message = failedAnswer === 'truncated' ? {role: 'assistant', content: JSON.stringify(value)}
      : {role: 'assistant', content: null, refusal: failedAnswer === 'refusal' ? 'Controlled refusal' : null};
    const finishReason = selectedSafetyFinish ?? (failedAnswer === 'truncated' ? 'length' : 'stop');
    const usage = failedAnswer === 'refusal' ? {prompt_tokens: 0} : {prompt_tokens: 5, completion_tokens: 7};
    response.end(JSON.stringify({id: 'installed-' + calls, model: 'fixture-reported-model',
      choices: [{index: 0, message, finish_reason: finishReason}], usage}));
    return;
  }
  const responseWire = JSON.stringify(anthropic ? {id: 'installed-' + calls, type: 'message', role: 'assistant',
    model: resolvedModelId, content: [{type: 'text', text: JSON.stringify(value)}], stop_reason: 'end_turn',
    usage: {input_tokens: 2, output_tokens: 3}} : {id: 'installed-' + calls, object: 'chat.completion', created: 1,
    model: resolvedModelId, choices: [{index: 0,
      message: {role: 'assistant', content: JSON.stringify(value)}, finish_reason: 'stop'}],
    ...(usageMode === 'absent' ? {} : {usage: usageMode === 'zero'
      ? {prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
      : {prompt_tokens: 2, completion_tokens: 3, total_tokens: 5}})});
  if (directHttp) originalDirectResponseCid = 'sha256:' + createHash('sha256').update(responseWire).digest('hex');
  response.end(responseWire);
});
let externalTcp = 0;
if (externalDuplicate) server.on('connection', () => {externalTcp++;});
if (directHttp) {
  server.on('connection', socket => {
    peerTcpAccepts++;
    socket.once('close', () => {peerSocketCloses++;});
  });
  server.on('secureConnection', socket => {
    peerTlsHandshakes++;
    peerServerName = socket.servername || null;
  });
}
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
const providerOptions = {
  generation: {temperature: 0, topP: 1, maxOutputTokens: 100},
  transportTimeouts,
  budget: {maxCalls, maxRows: 2, maxTokens: 1000n, maxCostUnits: 100000n,
    maxDurationMs: BigInt(phaseTimeoutMs)},
  observeEgress: () => {
    egressChecks++;
    return {classification: 'public', region: 'global', providerRetention: true, trainingUse: false};
  }};
const fixtureHandling = {schema: 'actql.contract/0.1', id: 'registered-sdk-fixture-policy',
  version: '1', kind: 'request_data_handling',
  body: {accepted_classifications: ['public'], allowed_regions: ['global'],
    retention: 'provider_contract', training_use: 'forbidden'},
  cid: 'sha256:45514e22d8ea4714fb2d6a4bfac3a963f51fd8ef0b5c5e12229f053b9f8955aa'};
function configureDirectProvider({createHttpChatProvider}) {
  const data = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
  const original = wire => Object.freeze({wire, cid: 'sha256:' + createHash('sha256').update(wire).digest('hex')});
  const rawPolicies = Object.fromEntries(['retention', 'metadata', 'clock'].map(role =>
    [role, original(JSON.stringify({name: 'direct-http-fixture-' + role, version: 'actql-installed-local-policy/0.1'}))]));
  return createHttpChatProvider({...providerOptions, providerId: 'models/http',
    modelId: 'fixture-chat', modelSelector: 'fixture-chat', credentialEnvironment: credentialReference,
    endpoint: 'https://' + directPeerHost + ':' + server.address().port + selectedRoute.requestPath,
    dataHandlingContractWire: JSON.stringify(fixtureHandling), rawPolicies: {...rawPolicies, data: original(data)}});
}
const dataHandlingContractWire = JSON.stringify(fixtureHandling);
let bindingProjections = 0;
async function registerSdkProviders(runtime, context) {
  for (const original of routes) assert.equal(context.registeredSdkSelected(original.providerId), true);
  const provider = await import(providerModule);
  assert.deepEqual(Object.keys(provider).sort(), ['createRegisteredSdkProvider', 'createRegisteredSdkProviders']);
  if (!mixed) {
    const register = provider.createRegisteredSdkProvider({...providerOptions, providerId: selectedRoute.providerId,
      ...(responses ? {modelGeneration: Object.freeze([Object.freeze({selector: selectedRoute.selector,
        temperature: 0.25, topP: 0.5, maxOutputTokens: 80, taskMaxOutputTokens: 100})])} : {}),
      dataHandlingContractWire});
    if (!bindingRefusal) return register(runtime, context);
    // Supply one invalid DATA projection to the ordinary funded constructor.
    // The selected, preloaded registration and capability stay untouched.
    return register(runtime, {...context, prepareBindingOriginals(project) {
      return context.prepareBindingOriginals(() => {
        const [revision, contract, wire] = project();
        const configuration = JSON.parse(wire);
        bindingProjections++;
        if (phase === 'registered-foreign-model') {
          const route = configuration.structured_routes[selectedRoute.selector];
          assert.equal(route.model_id, selectedRoute.resolvedModelId);
          route.model_id = 'foreign-fixture-model';
        } else {
          assert(Object.hasOwn(configuration, 'structured_routes'));
          delete configuration.structured_routes;
        }
        return [revision, contract, JSON.stringify(configuration)];
      });
    }});
  }
  const options = Object.freeze(routes.map(original => Object.freeze({...providerOptions, providerId: original.providerId,
    dataHandlingContractWire})));
  return provider.createRegisteredSdkProviders(options)(runtime, context);
}
const program = (task, field, value, type) => ({version: 'actql/0.1', id: 'installed-' + field,
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: {type: 'string', nullable: false}, [field]: {type, nullable: false}},
      rows: [{id: 'original-' + field, [field]: value}]}, as: 'input'},
    {assert_rows: {unique_by: ['id']}, as: 'unique'},
    {infer: {contract: task, key: 'id', input: {[field]: {field}}}, as: 'inferred'}],
    results: {answer: {from: 'inferred', fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'answer'}}}});
const textContract = {type: 'string', nullable: false};
async function checkResult(run, expected, index, resultName = 'answer') {
  const result = await run.result(resultName);
  const rows = await result.all();
  assert.deepEqual(rows, [expected]);
  const description = await result.describe();
  assert.deepEqual(description.ref, run.ref);
  assert.equal(description.resultName, resultName);
  assert.deepEqual(description.columns, [
    {name: 'id', contract: textContract},
    {name: 'outcome', contract: textContract},
    {name: 'value', contract: {type: 'object', nullable: true, additional_properties: false,
      fields: index === 0 ? {answer: {type: 'boolean', nullable: false}} : {label: textContract}}},
  ]);
  return {ref: description.ref, resultName: description.resultName, columns: description.columns, rows};
}
const mixedCases = [
  {stage: 'first', input: ['model-task:first', 'text', 'first', 'string'],
    row: {id: 'original-text', outcome: 'ok', value: {answer: true}}},
  {stage: 'second', input: ['model-task:second', 'quantity', 7, 'number'],
    row: {id: 'original-quantity', outcome: 'ok', value: {label: 'exact-label'}}},
];
function mixedProgram() {
  return {version: 'actql/0.1', id: 'installed-two-providers', stages: mixedCases.map(({stage, input}) =>
    ({...program(...input).stages[0], id: stage})), results: Object.fromEntries(mixedCases.map(({stage}) =>
    [stage, {from: {stage, result: 'answer'}}]))};
}
async function checkMixedResults(run) {
  for (const [index, {stage, row}] of mixedCases.entries()) await checkResult(run, row, index, stage);
}
// New explicit usage-aware local callback contract. This small authored Sink
// persists only the bounded seven-field projection; it is not the old five-part
// evidence Sink, an independent Model issuer or physical-cleanup observation.
let originalRef, usageReceipt, originalRawArtifactCid, originalTerminalStatus;
let directResult, directResultRefusal, directPeerClosedBeforeFirstClose;
async function checkUnpublishedDirectResult(run, state) {
  assert.equal(state.result_available, false);
  await assert.rejects(async () => (await run.result('answer')).all(), error => {
    assert.equal(error.code, 'ResultAccessDenied');
    directResultRefusal = error.code;
    return true;
  });
}
let usageCaptures = 0, usageAuthorizations = 0, checkedWithoutPhysicalWork = false;
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
      if (directHttp) {
        assert.match(value.raw_response_artifact_cid, /^sha256:[0-9a-f]{64}$/u);
        originalRawArtifactCid = value.raw_response_artifact_cid;
      }
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
const registerModelProviders = directHttp ? configureDirectProvider(await import(providerModule)) : registerSdkProviders;
const openOptions = {stateDir: '.state', installation: {
  registerModelProviders, authorization, observation: work.connection,
  ...(directHttp ? {} : {modelSdkRegistrations}),
  ...(inferEvidence === undefined ? {} : {inferEvidence, resultDataPolicy: policy})}};
const checkpointPath = '.state/checkpoints/journal/checkpoint-journal.sqlite3';
async function startupModelJournalCounts() {
  const counts = {modelScopes: 0, modelAttempts: 0};
  try { await access(checkpointPath); }
  catch (error) {
    if (error?.code === 'ENOENT') return counts;
    throw error;
  }
  const journal = new DatabaseSync(checkpointPath, {readOnly: true});
  try {
    const tableExists = journal.prepare("SELECT 1 FROM sqlite_schema WHERE type = 'table' AND name = ?");
    if (tableExists.get('resume_model_scopes')) {
      counts.modelScopes = journal.prepare('SELECT count(*) AS n FROM resume_model_scopes').get().n;
    }
    if (tableExists.get('resume_model_attempts')) {
      counts.modelAttempts = journal.prepare('SELECT count(*) AS n FROM resume_model_attempts').get().n;
    }
    return counts;
  } finally {journal.close();}
}
if (credentialMismatch || responsesOverLimit || bindingRefusal) {
  const env = process.env, connect = tls.connect;
  let credentialReads = 0, tlsAttempts = 0, peerConnections = 0;
  const rejected = phase === 'registered-missing-routes' ? 'InvalidInstalledModelSdkInstallation'
    : credentialMismatch ? 'RegisteredSdkCredentialMismatch' : 'MoonBitHostFailure';
  let bindingIssue;
  if (!credentialMismatch) await mkdir('.state', {mode: 0o700});
  server.on('connection', () => {peerConnections++;});
  process.env = new Proxy(env, {get(target, name, receiver) {
    if (name === 'OPENAI_API_KEY' || name === 'ACTQL_TEST_UNAPPROVED_MODEL_KEY') credentialReads++;
    return Reflect.get(target, name, receiver);
  }});
  tls.connect = () => {
    tlsAttempts++;
    throw Error('ExpectedPreparationRefusalReachedTls');
  };
  try {
    const opening = await open(openOptions).then(client => ({client}), error => ({error}));
    if ('client' in opening) {
      await opening.client.close();
      assert.fail('Expected Host preparation to reject before returning a client');
    }
    assert.equal(opening.error?.code, rejected);
    if (phase === 'registered-foreign-model') {
      // StructuredModelCapabilityIssue::ForeignConfiguration from the pinned
      // Common JS runtime. The Host has no public client at this boundary.
      assert.equal(opening.error.cause?.$tag, 1);
      bindingIssue = 'ForeignConfiguration';
    }
    assert.equal(credentialReads, 0);
    assert.equal(tlsAttempts, 0);
    assert.equal(peerConnections, 0);
    assert.equal(calls, 0);
  } finally {
    process.env = env;
    tls.connect = connect;
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  if (!credentialMismatch) {
    const journal = await startupModelJournalCounts();
    assert.deepEqual(journal, {modelScopes: 0, modelAttempts: 0});
    const aliveScopedFD0 = observeOwnScopedStateFds([resolve('.state')]).scopedStateFd0;
    const modelStarts = work.snapshot().modelCallStarts;
    assert.equal(aliveScopedFD0, true);
    assert.equal(modelStarts, 0);
    assert.equal(usageCaptures, 0);
    if (bindingRefusal) {
      assert.equal(bindingProjections, 1);
      assert.equal(egressChecks, 0);
      assert.equal(usageAuthorizations, 0);
      await assert.rejects(access('.state/publication/owner/owner.json'), {code: 'ENOENT'});
    }
    console.log(JSON.stringify({phase, rejected, credentialReads, tlsAttempts, peerConnections, calls,
      modelStarts, ...journal, aliveScopedFD0, usageCaptures,
      ...(bindingRefusal ? {pid: process.pid, bindingProjections, egressChecks, usageAuthorizations,
        ...(bindingIssue === undefined ? {} : {bindingIssue})} : {})}));
  } else console.log(JSON.stringify({phase, rejected, credentialReads, tlsAttempts, calls}));
  process.exit(0);
}
let client, primary, failed = false;
const originalEnv = process.env;
let externalCredentialReads = 0, trackedCredentialReads = 0, duplicateObservation, externalTerminal;
let cancellation, unknownControl;
let deniedRef, capabilityIssue, changedIssue, changedReason, historicalSavedAfterChange;
function readDirectModelJournal(ref, expectedState) {
  const requests = new DatabaseSync('.state/requests/client-requests.sqlite3', {readOnly: true});
  let journal;
  try {
    const row = requests.prepare(
      `SELECT run_definition_wire FROM client_requests
        WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`
    ).get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
    assert(row, 'Missing the selected original Run');
    const definition = JSON.parse(row.run_definition_wire);
    assert.equal(definition.run_definition_cid, ref.runDefinitionCid);
    journal = new DatabaseSync(checkpointPath, {readOnly: true});
    const scopes = journal.prepare(
      `SELECT scope_cid, slot_count, inventory_json FROM resume_model_scopes WHERE run_id = ? LIMIT 2`
    ).all(definition.run_id);
    assert.equal(scopes.length, 1);
    const [scope] = scopes;
    assert.equal(scope.slot_count, 1);
    const inventory = JSON.parse(scope.inventory_json);
    assert.deepEqual([inventory.runId, inventory.runDefinitionCid, inventory.scopeCid],
      [definition.run_id, ref.runDefinitionCid, scope.scope_cid]);
    const slots = journal.prepare(
      `SELECT ordinal, slot_cid, state, attempt_index FROM resume_model_slots WHERE scope_cid = ? LIMIT 2`
    ).all(scope.scope_cid);
    const attempts = journal.prepare(
      `SELECT ordinal, attempt_index, attempt_cid, entry_json, state, settlement_json
        FROM resume_model_attempts WHERE scope_cid = ? LIMIT 2`
    ).all(scope.scope_cid);
    assert.deepEqual([slots.length, attempts.length], [1, 1]);
    const [slot] = slots;
    const [attempt] = attempts;
    assert.deepEqual([slot.ordinal, slot.attempt_index, slot.state, attempt.ordinal, attempt.attempt_index, attempt.state],
      [0, 1, expectedState, 0, 1, expectedState]);
    const entry = JSON.parse(attempt.entry_json);
    assert.deepEqual([entry.runId, entry.runDefinitionCid, entry.scopeCid, entry.slotCid, entry.attemptCid,
      entry.ordinal, entry.attemptIndex, entry.providerBindingCid],
    [definition.run_id, ref.runDefinitionCid, scope.scope_cid, slot.slot_cid, attempt.attempt_cid,
      0, 1, inventory.providerBindingCid]);
    if (expectedState === 'EnteredUnknown') assert.equal(attempt.settlement_json, '');
    else {
      const saved = JSON.parse(attempt.settlement_json);
      assert.equal(saved.state, expectedState);
      assert.equal(saved.entry.attemptCid, attempt.attempt_cid);
    }
    return {runId: definition.run_id, scopeCid: scope.scope_cid, slotCid: slot.slot_cid,
      attemptCid: attempt.attempt_cid, state: attempt.state};
  } finally {
    try {journal?.close();} finally {requests.close();}
  }
}
let missingBinding, savedAdmissionBefore, savedEgressChecks;
function readSelectedModelJournal(ref, expected, unboundMember) {
  const refused = expected === 'refused';
  const requests = new DatabaseSync('.state/requests/client-requests.sqlite3', {readOnly: true});
  try {
    const row = requests.prepare(
      `SELECT run_definition_wire, run_admission_evidence_json,
              dispatch_reserved, pre_dispatch_failure_confirmed, physical_start_reserved
         FROM client_requests WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`
    ).get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
    assert(row, 'The same original Run must own the selected Model outcome');
    assert.equal(row.dispatch_reserved, 1);
    assert.equal(row.pre_dispatch_failure_confirmed, refused ? 1 : 0);
    assert.equal(row.physical_start_reserved, refused ? 0 : 1);
    const definition = JSON.parse(row.run_definition_wire);
    const {modelPlanBindings} = JSON.parse(row.run_admission_evidence_json);
    assert.equal(definition.run_definition_cid, ref.runDefinitionCid);
    let member;
    if (unboundMember === undefined) {
      assert.equal(modelPlanBindings.runDefinitionCid, ref.runDefinitionCid);
      assert.match(modelPlanBindings.compiledPlanCid, /^sha256:[0-9a-f]{64}$/u);
      assert.equal(modelPlanBindings.compiledPlanCid, definition.compiled_plan_cid);
      assert.equal(modelPlanBindings.bindings.length, 1);
      [member] = modelPlanBindings.bindings;
    } else {
      assert.equal(modelPlanBindings, undefined);
      assert.equal(expected, 'saved');
      member = unboundMember;
    }
    assert.deepEqual([member.task, member.stage, member.step], [0, 0, 2]);
    assert.match(member.taskCid, /^sha256:[0-9a-f]{64}$/u);
    assert.match(member.providerBindingCid, /^sha256:[0-9a-f]{64}$/u);
    const checkpoints = new DatabaseSync(checkpointPath, {readOnly: true});
    try {
      const scopes = checkpoints.prepare(
        `SELECT scope_cid, inventory_json FROM resume_model_scopes WHERE run_id = ?`
      ).all(definition.run_id);
      if (refused) {
        assert.equal(scopes.length, 0, 'Refusal must precede Model preflight, Scope and Entry');
        return {preDispatchRefusal: true, scopes: 0};
      }
      assert.equal(scopes.length, 1);
      const [scope] = scopes;
      const inventory = JSON.parse(scope.inventory_json);
      assert.equal(inventory.runId, definition.run_id);
      assert.equal(inventory.runDefinitionCid, ref.runDefinitionCid);
      assert.equal(inventory.taskIndex, member.task);
      assert.equal(inventory.providerBindingCid, member.providerBindingCid);
      const attempts = checkpoints.prepare(
        `SELECT ordinal, attempt_index, attempt_cid, state, entry_json, settlement_json, settled_at
           FROM resume_model_attempts WHERE scope_cid = ? ORDER BY ordinal`
      ).all(scope.scope_cid);
      assert.equal(attempts.length, 1);
      const [attempt] = attempts;
      if (expected === 'saved') {
        assert.equal(attempt.state, 'SavedSuccess');
        const saved = {providerBindingCid: member.providerBindingCid, savedAttempts: 1};
        if (unboundMember === undefined) return saved;
        const entry = JSON.parse(attempt.entry_json);
        const settlement = JSON.parse(attempt.settlement_json);
        assert.equal(entry.attemptCid, attempt.attempt_cid);
        assert.equal(entry.runDefinitionCid, ref.runDefinitionCid);
        assert.equal(entry.providerBindingCid, member.providerBindingCid);
        assert.equal(entry.scopeCid, scope.scope_cid);
        for (const field of ['runId', 'runDefinitionCid', 'providerBindingCid', 'scopeCid', 'slotCid',
          'attemptCid', 'attemptIndex', 'authorityCid', 'inputArtifactCid']) {
          assert.equal(settlement.entry[field], entry[field]);
        }
        assert(Number.isFinite(Date.parse(attempt.settled_at)));
        assert.match(settlement.evidence.model_attempt_accounting.cid, /^sha256:[0-9a-f]{64}$/u);
        return {...saved, attemptCid: entry.attemptCid, entrySha256: modelPlanFixtureDigest(attempt.entry_json),
          settlementSha256: modelPlanFixtureDigest(attempt.settlement_json)};
      }
      const unknownAttempt = expected === 'unknown';
      assert(unknownAttempt || expected === 'failed');
      const state = unknownAttempt ? 'EnteredUnknown' : 'SavedFailure';
      assert.deepEqual([attempt.ordinal, attempt.attempt_index, attempt.state], [0, 1, state]);
      const slot = checkpoints.prepare(
        'SELECT slot_cid, state, attempt_index FROM resume_model_slots WHERE scope_cid = ? AND ordinal = ?'
      ).get(scope.scope_cid, attempt.ordinal);
      const entry = JSON.parse(attempt.entry_json);
      assert.equal(entry.runDefinitionCid, ref.runDefinitionCid);
      assert.equal(entry.runId, definition.run_id);
      assert.equal(entry.providerBindingCid, member.providerBindingCid);
      assert.equal(entry.attemptCid, attempt.attempt_cid);
      assert.deepEqual([entry.slotCid, slot.state, slot.attempt_index], [slot.slot_cid, state, 1]);
      for (const cid of [scope.scope_cid, entry.slotCid, entry.attemptCid]) assert.match(cid, /^sha256:[0-9a-f]{64}$/u);
      assert.equal(entry.scopeCid, scope.scope_cid);
      const identity = {scopeCid: entry.scopeCid, slotCid: entry.slotCid, attemptCid: entry.attemptCid,
        providerBindingCid: entry.providerBindingCid, state: attempt.state};
      if (unknownAttempt) {
        assert.deepEqual([attempt.settlement_json, attempt.settled_at], ['', '']);
        return {...identity, settled: false};
      }
      assert(Number.isFinite(Date.parse(attempt.settled_at)));
      const settlement = JSON.parse(attempt.settlement_json);
      assert.equal(settlement.entry.attemptCid, entry.attemptCid);
      assert.equal(settlement.entry.runDefinitionCid, ref.runDefinitionCid);
      assert.equal(settlement.entry.scopeCid, entry.scopeCid);
      assert.equal(settlement.entry.slotCid, entry.slotCid);
      const evidence = settlement.evidence;
      assert.deepEqual(Object.keys(evidence).sort(), ['model_attempt_accounting', 'model_attempt_outcome',
        'model_call_attempt', 'model_capture_bundle', 'model_dispatch_authority', 'model_slot_capture']);
      for (const {cid, holdingCid} of Object.values(evidence)) {
        assert.match(cid, /^sha256:[0-9a-f]{64}$/u);
        assert.match(holdingCid, /^sha256:[0-9a-f]{64}$/u);
      }
      return {...identity, settled: true, settledAt: attempt.settled_at, evidence};
    } finally {checkpoints.close();}
  } finally {requests.close();}
}
let deniedModel = false, capabilityCredentialReads = 0, deniedCredentialReads = 0;
let externalResultIssue;
async function checkExternalRejectedRun(run, status) {
  assert.equal(status.status, 'failed');
  externalTerminal = status.status;
  await assert.rejects(async () => (await run.result('answer')).all(), error => {
    externalResultIssue = error.code;
    return typeof externalResultIssue === 'string' && /^[A-Za-z0-9_]+$/.test(externalResultIssue);
  });
  const adapter = await import(externalDuplicateSource);
  duplicateObservation = adapter.observedFetches();
  assert.deepEqual(duplicateObservation, fresh
    ? {attempts: 2, additionalIssue: 'SdkAdditionalRequestRefused'}
    : {attempts: 0, additionalIssue: undefined});
}
const firstClose = {attempted: false, returned: false, calls: 0}, cleanup = [];
let close;
const connectTls = tls.connect;
const expectedSends = fresh && !missingKey && !externalDuplicate ? capabilities ? 1 : taskCount : 0;
try {
  if (externalDuplicate || capabilities || interruption !== undefined || httpFailure !== undefined) process.env = new Proxy(originalEnv, {get(target, name, receiver) {
    if (name === credentialReference) {
      if (externalDuplicate) externalCredentialReads++;
      if (capabilities) capabilityCredentialReads++;
      if (interruption !== undefined || httpFailure !== undefined) trackedCredentialReads++;
      if (deniedModel) deniedCredentialReads++;
    }
    return Reflect.get(target, name, receiver);
  }});
  if (directHttp) {
    process.env = new Proxy(originalEnv, {get(target, name, receiver) {
      if (name === credentialReference) modelCredentialReads++;
      return Reflect.get(target, name, receiver);
    }});
  }
  // Keep the original hostname, certificate verification and installed HTTPS
  // transport while routing the fixture's only physical connections locally.
  if (!directHttp) tls.connect = (options, ...args) => {
    const host = options?.host;
    if (projectTlsConnects >= expectedSends || !routesByHost.has(host) ||
        mixed && connectedHosts.has(host) || options.servername !== host || Number(options.port) !== 443 ||
        options.socket !== undefined || options.rejectUnauthorized === false) {
      unexpectedProjectConnection = true;
      throw new Error('Unexpected registered TLS connection');
    }
    connectedHosts.add(host);
    projectTlsConnects++;
    return connectTls.call(tls, {...options, host: '127.0.0.1', port: server.address().port}, ...args);
  };
  if (retainedUnbound) {
    originalRef = JSON.parse(await readFile('run-0.json', 'utf8'));
    await assert.rejects(access('.state/publication/owner/owner.json'), {code: 'ENOENT'});
    missingBinding = omitFixtureModelPlanBinding(originalRef);
    savedAdmissionBefore = readSelectedModelJournal(originalRef, 'saved', missingBinding.member);
  }
  client = await open(openOptions);
  if (fresh && !missingKey) {
    for (const original of routes) process.env[original.credentialReference] = credentialValue(original);
  }
  if (fresh && mixed) {
    const submissionRef = client.newSubmission({nonce: 'installed-two-providers'});
    await writeFile('submission-0.json', JSON.stringify(submissionRef), {flag: 'wx', mode: 0o600});
    const run = await client.start(mixedProgram(), {submissionRef});
    await writeFile('run-0.json', JSON.stringify(run.ref), {flag: 'wx', mode: 0o600});
    originalRef = run.ref;
    const waited = await run.wait();
    await diagnostic.terminal(0, waited);
    assert.equal(waited.status, 'succeeded');
    await checkMixedResults(run);
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, run.ref);
    assert.equal(calls, 2);
    assert.deepEqual([...dispatchedProviders].sort(), routes.map(original => original.providerId).sort());
    assert.notDeepEqual(schemas[0], schemas[1]);
  } else if (changedRoute || retainedUnbound) {
    const ref = JSON.parse(await readFile('run-0.json', 'utf8'));
    const submissionRef = JSON.parse(await readFile('submission-0.json', 'utf8'));
    originalRef = ref;
    const readOriginal = async () => {
      const lookup = await client.lookupSubmission(submissionRef);
      assert.equal(lookup.kind, 'ready');
      assert.deepEqual(lookup.admission.ref, ref);
      await checkResult(await client.attach(ref),
        {id: 'original-text', outcome: 'ok', value: {answer: true}}, 0);
    };
    if (retainedUnbound) {
      await readOriginal();
      savedEgressChecks = egressChecks;
      assert.equal(savedEgressChecks, 0);
    }
    const expectedReason = retainedUnbound ? 'model_provider_selection_unavailable' : 'model_provider_selection';
    const expectedCode = retainedUnbound ? 'SubmissionRefused' : 'SubmissionConflict';
    await assert.rejects(client.start(program('model-task:first', 'text', 'first', 'string'), {submissionRef}),
      error => {
        changedIssue = error.code;
        const attempt = getSubmissionAttempt(error);
        changedReason = attempt?.reason;
        if (retainedUnbound) {
          assert.deepEqual(attempt?.submissionRef, submissionRef);
          assert.equal(attempt.kind, 'refused');
          assert.equal(attempt.guarantee, 'attempt_uncommitted_unconsumed');
        }
        return changedIssue === expectedCode && changedReason === expectedReason;
      });
    if (changedRoute) await readOriginal();
    historicalSavedAfterChange = true;
    assert.equal(calls, 0);
  } else if (fresh) {
    const cases = [
      [0, ['model-task:first', 'text', 'first', 'string'], {id: 'original-text', outcome: 'ok', value: {answer: true}}],
      [1, ['model-task:second', 'quantity', 7, 'number'], {id: 'original-quantity', outcome: 'ok', value: {label: 'exact-label'}}],
    ];
    cases.length = taskCount;
    if (outcomeFailure !== undefined) cases[0][2] = {id: 'original-text', outcome: 'failed:' + outcomeFailure, value: null};
    for (const [index, args, expected] of cases) {
      const selectedProgram = program(...args);
      if (directHttp) {
        const checked = await client.check(selectedProgram, {kind: 'program', scope: 'bound_input'});
        assert.equal(checked.report.verdict, 'verified');
        assert.deepEqual([modelCredentialReads, directDnsStarted, directDnsCompleted, peerTcpAccepts, peerTlsHandshakes, calls],
          [0, 0, 0, 0, 0, 0]);
        checkedWithoutPhysicalWork = true;
      }
      const submissionRef = client.newSubmission({nonce: 'installed-' + index});
      await writeFile('submission-' + index + '.json', JSON.stringify(submissionRef), {flag: 'wx', mode: 0o600});
      const denied = capabilities && index === 1;
      deniedModel = denied;
      const run = await client.start(selectedProgram, {submissionRef});
      await writeFile('run-' + index + '.json', JSON.stringify(run.ref), {flag: 'wx', mode: 0o600});
      if (denied) deniedRef = run.ref;
      else originalRef = run.ref;
      const waiting = interruption === undefined ? run.wait() : run.wait({signal: AbortSignal.timeout(15000)});
      if (enteredCancel) {
        await awaitPeer(enteredRequest.promise, 'OriginalEnteredRequestUnavailable');
        const before = await run.status();
        const cancelRef = {...run.ref, cancelId: 'entered-fixture-cancel', expectedRevision: before.control.revision};
        const accepted = await run.cancel({cancelId: cancelRef.cancelId, expectedRevision: cancelRef.expectedRevision,
          attemptId: 'original-entered-fixture-cancel'});
        assert.equal(accepted.kind, 'accepted');
        cancellation = accepted.cancellation;
        assert.equal(cancellation.kind, 'accepted');
        assert.deepEqual(cancellation.cancelRef, cancelRef);
        assert.deepEqual(await run.lookupCancellation(cancelRef), {kind: 'found', cancellation});
        await writeFile('entered-cancellation.json', JSON.stringify(cancellation), {flag: 'wx', mode: 0o600});
      }
      const waited = await waiting;
      await diagnostic.terminal(index, waited);
      originalTerminalStatus = waited.status;
      assert.equal(waited.status, missingKey || externalDuplicate || denied ? 'failed'
        : unknown ? 'needs_reconciliation' : 'succeeded');
      if (externalDuplicate) await checkExternalRejectedRun(run, waited);
      else if (denied) {
        const recorded = JSON.parse(await readFile('normal-diagnostic-before-assert.json', 'utf8'));
        assert.equal(recorded.dispatchFailures.length, 1);
        capabilityIssue = recorded.dispatchFailures[0].capabilityRefusal;
        assert.equal(capabilityIssue, 'InstalledModelStructuredModelUnsupported');
        assert.equal(work.forOriginal(deniedRef).modelCallStarts, 0);
        assert.equal(deniedCredentialReads, 0);
        await assert.rejects(async () => (await run.result('answer')).all(), {code: 'ResultAccessDenied'});
      } else if (missingKey) {
        const recorded = JSON.parse(await readFile('normal-diagnostic-before-assert.json', 'utf8'));
        assert.equal(recorded.dispatchFailures.length, 1);
        assert.equal(recorded.dispatchFailures[0].credentialRefusal, 'ModelProjectCredentialUnavailable');
      } else if (!unknown) {
        const observed = await checkResult(run, expected, index);
        if (directHttp) directResult = observed;
      } else {
        const current = await run.status();
        assert.equal(current.status, 'needs_reconciliation');
        assert.equal(current.control.cancellation_requested, enteredCancel);
        if (directUnknown) {
          for (let attempt = 0; peerSocketCloses === 0 && attempt < 100; attempt++) await waitFor(10);
          assert.equal(peerSocketCloses, 1);
          directPeerClosedBeforeFirstClose = true;
          await checkUnpublishedDirectResult(run, current);
        }
        if (interruption !== undefined) {
          await awaitPeer(interruptedResponse.promise, 'OriginalInterruptedPeerCloseNotObserved');
          responseClosedBeforeFirstClose = true;
          unknownControl = current.control;
          assert(Object.values(current.result_availability).every(result => result.state !== 'available'));
        }
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
    assert.equal(calls, expectedSends);
    if (taskCount === 2 && !capabilities) assert.notDeepEqual(schemas[0], schemas[1]);
    if (usageMode !== undefined && !externalDuplicate) {
      // The optional copy must have actually completed, not merely a successful
      // Model Run or a provider spy reporting authored usage.
      assert.equal(usageCaptures, 1); assert.equal(usageAuthorizations, 1);
      assert(usageReceipt !== undefined);
      assert.deepEqual(JSON.parse(await readFile('usage-receipt.json', 'utf8')), usageReceipt);
      const captured = JSON.parse(await readFile('usage-original.json', 'utf8'));
      assert.equal(captured.observation_origin, 'reported');
      assert.match(captured.raw_response_artifact_cid, /^sha256:[0-9a-f]{64}$/u);
    }
  } else {
    const ref = JSON.parse(await readFile('run-0.json', 'utf8'));
    const run = await client.attach(ref);
    if (trackOriginal) originalRef = ref;
    if (externalDuplicate) await checkExternalRejectedRun(run, await run.status());
    else if (mixed) {
      await checkMixedResults(run);
      assert.equal((await run.status()).status, 'succeeded');
    } else if (!unknown) {
      // The original Saved Result precedes this process's first status read.
      const expected = outcomeFailure !== undefined ? {outcome: 'failed:' + outcomeFailure, value: null}
        : {outcome: 'ok', value: {answer: true}};
      const observed = await checkResult(run, {id: 'original-text', ...expected}, 0);
      if (directHttp) directResult = observed;
      originalTerminalStatus = (await run.status()).status;
      assert.equal(originalTerminalStatus, 'succeeded');
    } else {
      // Observe the same entered original without replaying its physical Call.
      const current = await run.status();
      originalTerminalStatus = current.status;
      assert.equal(current.status, 'needs_reconciliation');
      assert.equal(current.control.cancellation_requested, enteredCancel);
      if (directUnknown) await checkUnpublishedDirectResult(run, current);
      if (interruption !== undefined) {
        unknownControl = current.control;
        assert(Object.values(current.result_availability).every(result => result.state !== 'available'));
        if (enteredCancel) {
          cancellation = JSON.parse(await readFile('entered-cancellation.json', 'utf8'));
          assert.deepEqual(await run.lookupCancellation(cancellation.cancelRef), {kind: 'found', cancellation});
        }
      }
    }
    const submissionRef = JSON.parse(await readFile('submission-0.json', 'utf8'));
    const lookup = await client.lookupSubmission(submissionRef);
    assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, ref);
    if (capabilities) {
      deniedRef = JSON.parse(await readFile('run-1.json', 'utf8'));
      const denied = await client.attach(deniedRef);
      assert.equal((await denied.status()).status, 'failed');
      await assert.rejects(async () => (await denied.result('answer')).all(), {code: 'ResultAccessDenied'});
    }
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
  if (directHttp || externalDuplicate || capabilities || interruption !== undefined || httpFailure !== undefined) process.env = originalEnv;
  for (const original of routes) delete process.env[original.credentialReference];
  tls.connect = connectTls;
  if (directHttp && fresh && firstClose.returned && !failed) {
    for (let attempt = 0; peerSocketCloses === 0 && attempt < 100; attempt++) await waitFor(10);
    if (peerSocketCloses !== 1) {failed = true; primary = Error('DirectModelPeerRetirementNotObserved');}
  }
  clearInterval(pulse);
  try {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
  catch (cause) {cleanup.push({name: cause?.name, code: cause?.code});if (!failed) {failed = true;primary = cause;}}
  directDnsObserver?.disable();
  try {close = observeOwnScopedStateFds([resolve('.state')]);}
  catch (cause) {cleanup.push({name: cause?.name, code: cause?.code});if (!failed) {failed = true;primary = cause;}}
  const recorded = await diagnostic.finish(firstClose, close, cleanup);
  if (!recorded.complete && !failed) {failed = true;primary = Error('NormalProviderDiagnosticIncomplete');}
  if (missingKey && !failed) assert.equal(recorded.value.work.modelCallStarts, 0);
}
if (failed) throw primary;
assert.equal(unexpectedProjectConnection, false);
assert.equal(projectTlsConnects, directHttp ? 0 : expectedSends);
if (directHttp) {
  const resolved = fresh && !directResponseLoss ? 1 : 0;
  assert.deepEqual([directDnsStarted, directDnsCompleted, peerServerName],
    [resolved, resolved, resolved === 1 ? directPeerHost : null]);
}
if (trackOriginal) {
  const observed = work.forOriginal(originalRef);
  assert.equal(observed.complete, true);
  assert.equal(observed.modelCallStarts, fresh && !externalDuplicate ? routes.length : 0);
  assert.equal(observed.totals.modelCallStarts, observed.modelCallStarts);
  if (directHttp) {
    assert.equal(observed.sourceAcquisitionStarts, 0);
    assert.equal(observed.totals.sourceAcquisitionStarts, 0);
  }
}
if (externalDuplicate) {
  assert.equal(externalCredentialReads, 0);
  assert.equal(externalTcp, 0);
  assert.equal(usageCaptures, 0);
  assert.equal(usageAuthorizations, 0);
  await assert.rejects(access('usage-original.json'), {code: 'ENOENT'});
}
assert.equal(close.aliveAfterClose, true); assert.equal(close.scopedStateFd0, true);
await assert.rejects(access('.state/publication/owner/owner.json'), {code: 'ENOENT'});
const directJournal = directHttp ? readDirectModelJournal(originalRef, directUnknown ? 'EnteredUnknown' : 'SavedSuccess')
  : undefined;
let directRaw, directRawAbsent;
if (directJournal !== undefined) {
  const root = realpathSync('.state');
  const storeAuthorityCid = 'sha256:' + createHash('sha256').update(JSON.stringify({
    version: 'actql-local-store-owner/0.1', root, principalId: userInfo().username,
  })).digest('hex');
  directRaw = await closedModelRawEvidence({
    publication: resolve(root, 'publication'), keyPath: resolve(root, 'checkpoints/private-evidence.key'),
    storeAuthorityCid, definitionCid: originalRef.runDefinitionCid, ...directJournal, expectMissing: directResponseLoss,
  });
  if (directResponseLoss) {
    assert.equal(directRaw, undefined);
    directRawAbsent = true;
  } else {
    assert.equal(directRaw.transportEof, !directPartialRaw);
    assert.equal(directRaw.httpStatus, directPartialRaw ? 503 : 200);
    if (directPartialRaw) {
      assert.equal(directRaw.byteCount, Buffer.byteLength(partialProviderBody));
      assert.equal(directRaw.contentCid, 'sha256:' + createHash('sha256').update(partialProviderBody).digest('hex'));
    } else if (fresh) {
      assert.equal(directRaw.contentCid, originalDirectResponseCid);
      assert.equal(directRaw.descriptorCid, originalRawArtifactCid);
    }
  }
}
if (directJournal !== undefined) assert.equal(observeOwnScopedStateFds([resolve('.state')]).scopedStateFd0, true);
const capabilityJournal = capabilities ? {supported: readSelectedModelJournal(originalRef, 'saved', missingBinding?.member),
  ...(deniedRef === undefined ? {} : {refused: readSelectedModelJournal(deniedRef, 'refused')})} : undefined;
if (retainedUnbound) {
  assert.deepEqual(capabilityJournal.supported, savedAdmissionBefore);
  verifyFixtureModelPlanBindingStillAbsent(originalRef, missingBinding.evidence);
}
const unknownJournal = interruption === undefined ? undefined : readSelectedModelJournal(originalRef, 'unknown');
if (interruption !== undefined) {
  assert.equal(trackedCredentialReads, fresh ? 1 : 0);
  assert.equal(usageAuthorizations, 0);
  assert.equal(usageCaptures, 0);
}
const failureJournal = httpFailure === undefined ? undefined : readSelectedModelJournal(originalRef, 'failed');
if (httpFailure !== undefined) {
  assert.equal(trackedCredentialReads, fresh ? 1 : 0);
  assert.equal(completedHttpFailures, fresh ? 1 : 0);
}
console.log(JSON.stringify({phase, calls, firstCloseReturned: true, aliveScopedFD0: true,
  ...(directHttp ? {} : {registeredSdk: true, projectTlsConnects, projectCredential: true}),
  ...(capabilities ? {capabilityRoutes: [selectedRoute.selector, deniedAlias], capabilityCredentialReads,
    deniedCredentialReads, capabilityJournal,
    ...(capabilityIssue === undefined ? {} : {capabilityIssue}),
    ...(deniedRef === undefined ? {} : {deniedRunDefinitionCid: deniedRef.runDefinitionCid,
      deniedModelStarts: work.forOriginal(deniedRef).modelCallStarts}),
    ...(changedIssue === undefined ? {} : {changedIssue, changedReason, historicalSavedAfterChange})} : {}),
  ...(retainedUnbound ? {missingBindingEvidence: missingBinding.evidence, savedEgressChecks} : {}),
  ...(mixed ? {mixedProviders: routes.map(original => original.providerId),
    dispatchedProviders: [...dispatchedProviders].sort()} : {}),
  ...(trackOriginal ? {originalModelStarts: work.forOriginal(originalRef).modelCallStarts,
    originalRunDefinitionCid: originalRef.runDefinitionCid} : {}),
  ...(directHttp ? {directHttp, peerTcpAccepts, peerTlsHandshakes, peerSocketCloses, modelCredentialReads,
    directDnsStarted, directDnsCompleted, peerServerName, originalTerminalStatus, directJournal, directDependencyClosure,
    ...(directRaw === undefined ? {} : {directRaw}),
    ...(directRawAbsent === undefined ? {} : {directRawAbsent}),
    ...(directResult === undefined ? {} : {directResult}),
    ...(directResultRefusal === undefined ? {} : {directResultRefusal}),
    ...(directPeerClosedBeforeFirstClose === undefined ? {} : {directPeerClosedBeforeFirstClose}),
    originalAuthorityScopeCid: originalRef.authorityScopeCid,
    ...(fresh ? {checkedWithoutPhysicalWork} : {}),
    ...(originalRawArtifactCid === undefined ? {} : {originalRawArtifactCid})} : {}),
  ...(usageMode === 'reported' || failedAnswer !== undefined ? {maxCalls: Number(maxCalls)} : {}),
  ...(external ? {externalAdapterCid: modelSdkRegistrations[0].adapter.cid,
    externalLockCid: modelSdkRegistrations[0].lock.cid} : {}),
  ...(outcomeFailure === undefined ? {} : {terminalFailure: outcomeFailure}),
  ...(httpFailure === undefined ? {} : {pid: process.pid, httpStatus, failureJournal,
    completedHttpFailures, failureCredentialReads: trackedCredentialReads}),
  ...(externalDuplicate ? {externalTerminal, externalResultIssue, externalTcp, externalCredentialReads,
    interceptedFetches: duplicateObservation.attempts, additionalIssue: duplicateObservation.additionalIssue,
    usageCaptures, usageAuthorizations} : {}),
  ...(changedRoute || retainedUnbound ? {egressChecks} : phase === 'cold' ? {egressChecks,
    ...(externalDuplicate ? {originalFailureObserved: true}
      : !unknown ? {originalSavedFirst: true} : {originalUnknown: true, zeroResend: true})}
    : {tasks: taskCount, requests: externalDuplicate ? 0 : capabilities ? 1 : taskCount, ...(missingKey ? {credentialRefused: true} : {}),
      ...(usageMode === undefined ? {} : {usageMode, usageCaptures})}),
  ...(interruption === undefined ? {} : {pid: process.pid, interruption, interruptionCredentialReads: trackedCredentialReads, unknownJournal, unknownControl,
    ...(fresh ? {responseClosedBeforeFirstClose} : {}), ...(cancellation === undefined ? {} : {cancellation})}),
  ...(timeoutMode === undefined ? {} : {timeoutMode, preserveOriginalState: true}),
  ...(timeoutMode === 'call' && fresh ? {continuousWrites, responseClosedBeforeFirstClose} : {}),
  node: process.versions.node, platform: process.platform, arch: process.arch}));
