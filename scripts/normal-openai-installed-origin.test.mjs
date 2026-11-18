import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFileSync, existsSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {normalProviderDiagnostics} from './fixtures/normal-provider-diagnostics.fixture.mjs';
import {workflowWorkObservation} from '../adapters/host-node/fixtures/work-observation.fixture.mjs';
import {createHostObservationConnection, installHostObservation} from '../adapters/host-common/observation.mjs';

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
// prove pre-import refusal, not package/runtime/normal Model acceptance.
for (const variant of ['linked-provider', 'redirected-public-entry', 'linked-node-modules']) {
  test(`installed Model consumer refuses ${variant} before either public package executes`, t => {
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
    for (const name of ['node', 'provider-ai-sdk', 'local-node']) {
      const directory = variant === 'linked-provider' && name === 'provider-ai-sdk'
        ? join(outside, name) : join(modules, '@actql', name);
      mkdirSync(directory);
      if (variant === 'linked-provider' && name === 'provider-ai-sdk') {
        symlinkSync(directory, join(modules, '@actql', name));
      }
      const entry = name === 'local-node' ? 'observation.mjs'
        : variant === 'redirected-public-entry' && name === 'provider-ai-sdk' ? 'other.mjs' : 'index.mjs';
      writeFileSync(join(directory, 'package.json'), JSON.stringify({name: '@actql/' + name,
        type: 'module', exports: {[name === 'local-node' ? './observation' : '.']: './' + entry}}));
      writeFileSync(join(directory, entry), `import{writeFileSync}from'node:fs';
        writeFileSync(${JSON.stringify(join(root, name + '.executed'))},'unexpected');
        export function connect(){throw Error('No product execution selected');}
        export function createOpenAIChatProvider(){throw Error('No product execution selected');}`);
    }
    const result = spawnSync(process.execPath, ['case.mjs', 'warm'], {cwd: consumer,
      encoding: 'utf8', timeout: 10000, maxBuffer: 65536});
    assert.ifError(result.error); assert.equal(result.status, 1);
    assert.match(result.stderr, /fresh installation|expected installed package entry|fresh node_modules/);
    for (const name of ['node', 'provider-ai-sdk', 'local-node']) assert.equal(existsSync(join(root, name + '.executed')), false);
    assert.equal(existsSync(join(consumer, '.state')), false);
    assert.equal(existsSync(join(consumer, 'actql.config.json')), false);
  });
}
