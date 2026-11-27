import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {normalProviderDiagnostics} from './fixtures/normal-provider-diagnostics.fixture.mjs';
import {workflowWorkObservation} from '../adapters/host-node/fixtures/work-observation.fixture.mjs';
import {createHostObservationConnection, installHostObservation} from '../adapters/host-common/observation.mjs';
import {createDiagnosticObserver} from '../adapters/host-common/diagnostic-observer.mjs';

test('normal provider existing authorization callback retains generic dispatch scalars without masking primary', async () => {
  const files = new Map();
  const diagnostic = normalProviderDiagnostics({phase: 'warm', work: {snapshot: () => ({complete: true})},
    write: async (path, wire) => {files.set(path, JSON.parse(wire));}});
  let delivered;
  const delivery = new Promise(resolve => {delivered = resolve;});
  let callbacks = 0, accessorCalls = 0;
  const observer = createDiagnosticObserver((event, detail) => {
    diagnostic.dispatchFailure(event, detail);
    if (++callbacks === 3) {delivered();throw Error('AuthoredOptionalCallbackFailure');}
  });
  const primary = {phase: 'dispatch', kind: 'code_site',
    message: 'do-not-copy-code-site-or-exception', body: 'do-not-copy-body'};
  Object.defineProperty(primary, 'cause', {get() {accessorCalls++;throw Error('UnexpectedGetter');}});
  const cleanup = {owner: 'managed_operations', phase: 'await_stop', continuation: 'blocked',
    message: 'do-not-copy-cleanup-message'};
  const detail = {primaryDiagnostic: primary, cleanupDiagnostic: cleanup,
    issueTag: 10, nestedIssueTag: 65535, leafIssueTag: 65536,
    code: 'do-not-copy-exception', message: 'do-not-copy-message',
    ref: {secret: 'do-not-copy-ref'}, headers: {authorization: 'do-not-copy-credential'}};
  const originalPrimary = Object.freeze({original: true});
  let caught;
  try {
    observer('dispatch_failed', detail);
    observer('dispatch_failed', {cleanupDiagnostic: cleanup, issueTag: -1});
    observer('dispatch_failed', {primaryDiagnostic: {phase: 'replacement', kind: 'replacement'}});
    await delivery;
    throw originalPrimary;
  } catch (cause) {caught = cause;}
  assert.strictEqual(caught, originalPrimary);
  primary.kind = 'later_mutation';cleanup.continuation = 'runnable';
  await diagnostic.terminal(0, {status: 'failed'});
  const result = await diagnostic.finish({attempted: true, returned: true, calls: 1}, undefined, []);
  const expected = [
    {primary: {phase: 'dispatch', kind: 'code_site'},
      cleanup: {owner: 'managed_operations', phase: 'await_stop', continuation: 'blocked'},
      issueTag: 10, nestedIssueTag: 65535},
    {cleanup: {owner: 'managed_operations', phase: 'await_stop', continuation: 'blocked'}},
  ];
  assert.deepEqual(result.value.dispatchFailures, expected);
  assert.deepEqual(files.get('normal-diagnostic-before-assert.json').dispatchFailures, expected);
  assert.equal(result.complete, false, 'An excess diagnostic remains incomplete, never a replaced primary');
  assert.equal(result.value.diagnosticFailures.length, 1);
  assert.equal(accessorCalls, 0);
  assert.equal(JSON.stringify(result.value).includes('do-not-copy'), false);
  observer.close();
});

test('normal provider diagnostics retain full original terminal, bounded dispatch and HTTP facts before assertion', async () => {
  const work = workflowWorkObservation({createObservation: createHostObservationConnection});
  const observer = installHostObservation(work.connection), files = new Map();
  const diagnostic = normalProviderDiagnostics({phase: 'warm', work,
    write: async (path, wire, options) => {files.set(path, {value: JSON.parse(wire), options});}});
  observer.diagnostic('dispatch_failed', {primaryDiagnostic: {
    code: 'MoonBitHostFailure', phase: 'original_infer_component', kind: 'call_scope.foreign_input', task: 0, unit: 0, step: 0},
    body: 'do-not-copy-body', headers: {authorization: 'do-not-copy-credential'}});
  diagnostic.request({method: 'POST', url: '/v1/chat/completions?secret=do-not-copy-query',
    headers: {authorization: 'do-not-copy-credential'}, body: 'do-not-copy-body'});
  const terminal = {status: 'failed', run_id: 'authored-public-id',
    control: {physical_stop: 'confirmed'}, failure: {code: 'OriginalPublicFailure'}};
  await diagnostic.terminal(0, terminal);
  assert.deepEqual(files.get('terminal-0.json').value, terminal);
  assert.equal(files.get('terminal-0.json').options.flag, 'wx');
  assert.equal(files.has('normal-diagnostic-before-assert.json'), true);
  await observer.close();
  const firstClose = {attempted: true, returned: true, calls: 1};
  const result = await diagnostic.finish(firstClose, {aliveAfterClose: true, scopedStateFd0: true}, []);
  assert.equal(result.complete, true);
  assert.deepEqual(result.value.http, {calls: 1, requests: [{method: 'POST', path: '/v1/chat/completions'}]});
  assert.deepEqual(result.value.work.primaryFailure, {available: true, code: 'MoonBitHostFailure',
    phase: 'original_infer_component', kind: 'call_scope.foreign_input', occurrence: {task: 0, unit: 0, step: 0}});
  assert.deepEqual(result.value.firstClose, firstClose);
  assert.equal(JSON.stringify(result.value).includes('do-not-copy'), false);
});

test('normal provider diagnostic recording refusal or missing delivery cannot mask original undefined failure', async () => {
  const diagnostic = normalProviderDiagnostics({phase: 'warm', work: {snapshot: () => ({complete: false})},
    write: async () => {throw Object.assign(Error('OriginalWriteRefusal'), {code: 'EEXIST'});}});
  let caught = false;
  try {
    try {await diagnostic.terminal(0, {status: 'failed'});throw undefined;}
    finally {
      const value = await diagnostic.finish({attempted: true, returned: false, calls: 1}, undefined,
        [{code: 'OriginalCloseRefusal'}]);
      assert.equal(value.complete, false);assert(value.value.diagnosticFailures.length > 0);
      assert.equal(value.value.firstClose.returned, false);
    }
  } catch (cause) {caught = true;assert.strictEqual(cause, undefined);}
  assert.equal(caught, true);
});

// Actual consumer entry execution with inert package sentinels. These cases
// prove that the actual consumer rejects each altered installation before import.
for (const variant of ['linked-provider', 'redirected-public-entry', 'linked-node-modules', 'optional-sdk-in-direct',
  'nested-sdk-in-direct', 'dependency-on-sdk-in-direct']) {
  test(`installed Model consumer refuses ${variant} before any public package executes`, t => {
    const root = mkdtempSync(join(tmpdir(), 'actql-model-package-origin-'));
    t.after(() => rmSync(root, {recursive: true, force: true}));
    const consumer = join(root, 'consumer'), outside = join(root, 'outside');
    mkdirSync(consumer); mkdirSync(outside);
    copyFileSync(new URL('./fixtures/normal-openai-installed.fixture.mjs', import.meta.url), join(consumer, 'case.mjs'));
    copyFileSync(new URL('./fixtures/external-rest/conformance.mjs', import.meta.url), join(consumer, 'conformance.mjs'));
    copyFileSync(new URL('./fixtures/normal-provider-diagnostics.fixture.mjs', import.meta.url), join(consumer, 'normal-provider-diagnostics.fixture.mjs'));
    const modules = variant === 'linked-node-modules' ? join(outside, 'node_modules') : join(consumer, 'node_modules');
    mkdirSync(join(modules, '@actql'), {recursive: true});
    if (variant === 'linked-node-modules') symlinkSync(modules, join(consumer, 'node_modules'));
    const packages = ['node', 'sdk', 'local-node'];
    if (!['nested-sdk-in-direct', 'dependency-on-sdk-in-direct'].includes(variant)) packages.push('provider-ai-sdk');
    for (const name of packages) {
      const directory = variant === 'linked-provider' && name === 'provider-ai-sdk'
        ? join(outside, name) : join(modules, '@actql', name);
      mkdirSync(directory);
      if (variant === 'linked-provider' && name === 'provider-ai-sdk') {
        symlinkSync(directory, join(modules, '@actql', name));
      }
      const entry = variant === 'redirected-public-entry' && name === 'provider-ai-sdk' ? 'other.mjs' : 'index.mjs';
      const exports = {'.': './' + entry};
      if (name === 'local-node') exports['./observation'] = './observation.mjs';
      writeFileSync(join(directory, 'package.json'), JSON.stringify({
        name: '@actql/' + name, type: 'module', version: '1.0.0', exports,
        ...(variant === 'dependency-on-sdk-in-direct' && name === 'local-node'
          ? {optionalDependencies: {'@ai-sdk/openai': '1.0.0'}} : {}),
      }));
      const sentinel = `import{writeFileSync}from'node:fs';
        writeFileSync(${JSON.stringify(join(root, name + '.executed'))},'unexpected');
        export function connect(){throw Error('No product execution selected');}
        export function createRegisteredSdkProvider(){throw Error('No product execution selected');}`;
      for (const target of Object.values(exports)) writeFileSync(join(directory, target), sentinel);
    }
    if (variant === 'nested-sdk-in-direct') {
      const nested = join(modules, '@actql/local-node/node_modules/model-implementation');
      mkdirSync(nested, {recursive: true});
      writeFileSync(join(nested, 'package.json'), JSON.stringify({name: 'ai', version: '1.0.0'}));
    }
    const phase = variant.endsWith('-in-direct') ? 'direct-project' : 'warm';
    const result = spawnSync(process.execPath, ['case.mjs', phase], {cwd: consumer,
      encoding: 'utf8', timeout: 10000, maxBuffer: 65536});
    assert.ifError(result.error); assert.equal(result.status, 1);
    const expected = {
      'optional-sdk-in-direct': /SDK-free installation resolved optional package @actql\/provider-ai-sdk/,
      'nested-sdk-in-direct': /SDK-free installation contains @actql\/local-node\/node_modules\/model-implementation/,
      'dependency-on-sdk-in-direct': /SDK-free installation declares a dependency on AI SDK in @actql\/local-node/,
    };
    assert.match(result.stderr, expected[variant] ?? /fresh installation|expected installed package entry|fresh node_modules/);
    for (const name of packages) assert.equal(existsSync(join(root, name + '.executed')), false);
    assert.equal(existsSync(join(consumer, '.state')), false);
    assert.equal(existsSync(join(consumer, 'actql.config.json')), false);
  });
}
