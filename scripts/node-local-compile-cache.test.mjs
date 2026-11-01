// Actual public Node/Local entry and optional cache policy, with an explicit
// Host boundary double. This is module ordering/routing, not Host admission.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {copyFile, mkdir, readFile, symlink, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
async function fixture({missing = false, provider} = {}) {
  const scratch = await createOwnedScratch({parent: join(repository, '_build'),
    prefix: 'node-local-cache-', label: 'public Local optional cache boundary'});
  const packages = join(scratch.path, 'node_modules/@actql');
  const node = join(packages, 'node'), local = join(packages, 'local-node');
  await mkdir(node, {recursive: true});
  for (const file of ['index.mjs', 'package.json']) {
    await copyFile(join(repository, 'packages/node', file), join(node, file));
    assert.deepEqual(await readFile(join(node, file)),
      await readFile(join(repository, 'packages/node', file)));
  }
  await symlink(join(repository, 'packages/sdk'), join(packages, 'sdk'), 'dir');
  if (!missing) {
    const host = join(local, 'adapters/host-node');
    await mkdir(host, {recursive: true});
    for (const file of ['index.mjs', 'package.json']) {
      await copyFile(join(repository, 'packages/local-node', file), join(local, file));
      assert.deepEqual(await readFile(join(local, file)),
        await readFile(join(repository, 'packages/local-node', file)));
    }
    await copyFile(join(repository, 'adapters/host-node/compile-cache.mjs'),
      join(host, 'compile-cache.mjs'));
    assert.deepEqual(await readFile(join(host, 'compile-cache.mjs')),
      await readFile(join(repository, 'adapters/host-node/compile-cache.mjs')));
    // Its static dependency runs before this Host module body. The existing
    // Host's later cache call is retained, so it alone cannot satisfy ordering.
    await writeFile(join(host, 'cold-dependency.mjs'), 'globalThis.order.push("dependency");\n');
    await writeFile(join(host, 'embedded-local.mjs'), `
import './cold-dependency.mjs';
import {enableNodeCompileCache} from './compile-cache.mjs';
globalThis.order.push('host');
export function connectEmbeddedLocal(options) {
  enableNodeCompileCache();
  globalThis.order.push('connect');
  globalThis.originalOptions = options;
  return Promise.resolve(Object.freeze({originalClient: true}));
}
export const publishInstalledSource = () => {throw new Error('Unselected');};
export const publishInstalledEffect = () => {throw new Error('Unselected');};
`);
    await writeFile(join(host, 'installed-connectors.mjs'),
      'export const createInstalledConnectorTable = () => {throw new Error("Unselected");};\n');
    if (provider !== undefined) await writeFile(join(local, 'index.mjs'), provider);
  }
  return {scratch, local};
}

async function check(body, {mode = 'enabled', coverage = false, ...options} = {}) {
  const f = await fixture(options), entry = join(f.scratch.path, 'entry.mjs');
  await writeFile(entry, `
import assert from 'node:assert/strict';
import {createRequire, syncBuiltinESMExports} from 'node:module';
const require = createRequire(import.meta.url), module = require('node:module');
globalThis.order = [];
globalThis.primary = Object.freeze(new Error('OriginalProviderFailure'));
module.enableCompileCache = ${mode === 'unsupported' ? 'undefined' : `function() {
  globalThis.order.push('enable');
  return Object.freeze({status: ${JSON.stringify(mode)}});
}`};
syncBuiltinESMExports();
const node = await import('@actql/node');
const {ClientError} = await import('@actql/sdk/_internal/client-errors');
assert.strictEqual(node.ClientError, ClientError);
assert.deepEqual(order, [], 'importing the facade does not select Local');
${body}
`);
  const env = {...process.env, NODE_OPTIONS: ''};
  delete env.NODE_V8_COVERAGE;
  if (coverage) env.NODE_V8_COVERAGE = join(f.scratch.path, 'coverage');
  const result = spawnSync(process.execPath, [entry], {cwd: f.scratch.path,
    env, encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024});
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  f.scratch.passed();
}

test('public open enables the existing cache before the actual Local static Host graph', async () => {
  await check(`
const pending = node.open({stateDir: '.original'});
assert(pending instanceof Promise);
const client = await pending;
assert.equal(client.originalClient, true);
assert.deepEqual(order, ['enable', 'dependency', 'host', 'enable', 'connect']);
assert.equal(originalOptions.owner, 'local');
assert.equal(client.info.stateDir, originalOptions.installation.directory);
`);
});

test('Local acquisition preserves captured options and original callback and borrower identities', async () => {
  await check(`
const callback = () => 'original', borrower = Object.freeze({original: true});
let profiles = 0;
const input = {mode: 'local', get profile() {profiles++; return 'mock';},
  installation: {directory: '.original', resolveSourceSecret: callback, borrower}};
const pending = node.connect(input);
input.installation.directory = '.replacement';
input.installation.resolveSourceSecret = () => 'replacement';
input.installation.borrower = {};
await pending;
assert.equal(profiles, 1);
assert.equal(originalOptions.profile, 'mock');
assert.equal(originalOptions.installation.directory, '.original');
assert.strictEqual(originalOptions.installation.resolveSourceSecret, callback);
assert.strictEqual(originalOptions.installation.borrower, borrower);
`);
});

test('Remote selection never resolves Local or invokes its cache policy', async () => {
  await check(`
await assert.rejects(node.connect({mode: 'remote', endpoint: 'not-an-origin', token: 'fixture'}),
  error => error instanceof ClientError && error.code === 'InvalidConnectionEndpoint');
assert.deepEqual(order, []);
`, {missing: true});
});

test('missing Local retains its asynchronous original public refusal before cache acquisition', async () => {
  await check(`
const pending = node.connect({mode: 'local'});
assert(pending instanceof Promise);
await assert.rejects(pending, error => error instanceof ClientError &&
  error.code === 'LocalProviderNotInstalled' && error.cause.code === 'ERR_MODULE_NOT_FOUND');
assert.deepEqual(order, []);
`, {missing: true});
});

test('the resolved original provider namespace remains the connect receiver', async () => {
  await check(`
const original = await node.connect({mode: 'local'});
assert.equal(original.originalReceiver, true);
assert.deepEqual(order, ['enable']);
`, {provider: `
import assert from 'node:assert/strict';
import * as original from './index.mjs';
export function connect(options) {
  assert.strictEqual(this, original);
  assert.equal(options.mode, 'local');
  return Object.freeze({originalReceiver: true});
}
`});
});

test('invalid or failing original providers preserve validation and primary error identity', async () => {
  await check(`
await assert.rejects(node.connect({mode: 'local'}), error =>
  error instanceof ClientError && error.code === 'InvalidLocalProvider');
assert.deepEqual(order, ['enable']);
`, {provider: 'export const connect = 0;\n'});
  await check(`
await assert.rejects(node.connect({mode: 'local'}), error => error === primary);
assert.deepEqual(order, ['enable']);
`, {provider: 'throw globalThis.primary;\n'});
});

test('coverage exclusion uses the existing helper and does not prevent Local acquisition', async () => {
  await check(`
const client = await node.open();
assert.equal(client.originalClient, true);
assert.deepEqual(order, ['dependency', 'host', 'connect']);
`, {coverage: true});
});

test('an unavailable optional Node cache API does not prevent Local acquisition', async () => {
  await check(`
const client = await node.open();
assert.equal(client.originalClient, true);
assert.deepEqual(order, ['dependency', 'host', 'connect']);
`, {mode: 'unsupported'});
});

test('disabled or failed optional cache statuses never become a Local admission decision', async () => {
  for (const mode of ['disabled', 'failed']) await check(`
const client = await node.open();
assert.equal(client.originalClient, true);
assert.deepEqual(order, ['enable', 'dependency', 'host', 'enable', 'connect']);
`, {mode});
});
