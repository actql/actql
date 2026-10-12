import assert from 'node:assert/strict';
import {mkdtempSync, readFileSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runInNewContext} from 'node:vm';
import {transformSync} from 'esbuild';
import test from 'node:test';
import {deferredFunctionRuntime} from './deferred-function-runtime.mjs';

function fixture(t, source, options) {
  const directory = mkdtempSync(join(tmpdir(), 'deferred-function-runtime-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const input = join(directory, 'original.mjs');
  const output = join(directory, 'deferred.mjs');
  writeFileSync(input, source);
  writeFileSync(output, deferredFunctionRuntime(input, options));
  return {directory, input: pathToFileURL(input).href, output: pathToFileURL(output).href};
}

// An isolated module-evaluation boundary supplies its own restricted Crypto
// port. The process Crypto object and product entropy source are never patched.
function sandboxModule(url, crypto) {
  const bundled = transformSync(readFileSync(fileURLToPath(url), 'utf8'), {
    format: 'iife', globalName: '__testedModule', target: 'es2022',
  }).code;
  return runInNewContext(bundled + '\n__testedModule;', {crypto});
}

for (const minify of [false, true]) {
  test(`global import defers entropy and retains one original instance (minify=${minify})`, async t => {
    let inHandler = false, calls = 0, issuedSeed;
    const processCrypto = globalThis.crypto;
    const forbidden = new Error('Disallowed global entropy');
    const crypto = Object.freeze({getRandomValues: bytes => {
      calls++;
      if (!inHandler) throw forbidden;
      processCrypto.getRandomValues(bytes);
      issuedSeed = bytes[0];
      return bytes;
    }});
    const f = fixture(t, `
const seed = crypto.getRandomValues(new Uint32Array(1))[0];
const owner = new WeakMap();
export function retain(original) {
  const custody = Object.freeze({});
  owner.set(custody, original);
  return custody;
}
export function restore(custody) {
  if (!owner.has(custody)) throw new TypeError('Foreign custody');
  return owner.get(custody);
}
export function selectedSeed() { return seed; }
`, {minify});
    assert.throws(() => sandboxModule(f.input, crypto), error => error === forbidden);
    calls = 0;
    const runtime = sandboxModule(f.output, crypto);
    assert.deepEqual(Object.keys(runtime), ['restore', 'retain', 'selectedSeed']);
    assert.equal(calls, 0, 'Worker global import must not request entropy');
    inHandler = true;
    const original = Object.freeze({run: 'original-run', attempt: 1});
    const custody = runtime.retain(original);
    assert.equal(runtime.restore(custody), original);
    assert.equal(runtime.selectedSeed(), issuedSeed);
    assert.equal(globalThis.crypto, processCrypto);
    assert.equal(calls, 1, 'The original compiled state is initialized once');
    assert.throws(() => runtime.restore({}), /Foreign custody/u);
    assert.equal(runtime.restore(custody), original);
    assert.equal(calls, 1, 'A rejected call must not reconstruct the Owner');
  });
}

test('failed initialization retains the exact failure without another entropy attempt', async t => {
  let calls = 0;
  const originalFailure = new Error('Original entropy unavailable');
  const crypto = Object.freeze({getRandomValues: () => { calls++; throw originalFailure; }});
  const f = fixture(t, `
const seed = crypto.getRandomValues(new Uint32Array(1))[0];
export function selectedSeed() { return seed; }
`);
  const runtime = sandboxModule(f.output, crypto);
  assert.equal(calls, 0);
  assert.throws(() => runtime.selectedSeed(), error => error === originalFailure);
  assert.throws(() => runtime.selectedSeed(), error => error === originalFailure);
  assert.equal(calls, 1);
});

test('a retained instance and exact thrown operation outcome are not recreated', async t => {
  const f = fixture(t, `
const originalFailure = Object.freeze({unknown: true});
let attempts = 0;
export function perform() { attempts++; throw originalFailure; }
export function observedAttempts() { return attempts; }
`);
  const runtime = await import(f.output);
  let outcome;
  try { runtime.perform(); } catch (error) { outcome = error; }
  assert.deepEqual(outcome, {unknown: true});
  assert.equal(runtime.observedAttempts(), 1);
  assert.equal(runtime.observedAttempts(), 1, 'Observation performs no retry');
});

test('generation rejects external imports; non-function exports fail only after first initialization', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'deferred-function-runtime-invalid-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const input = join(directory, 'external.mjs');
  writeFileSync(input, `import {readFileSync} from 'node:fs'; export function read() { return readFileSync; }`);
  assert.throws(() => deferredFunctionRuntime(input), /Could not resolve|closed synchronous/u);
  let calls = 0;
  const processCrypto = globalThis.crypto;
  const crypto = Object.freeze({getRandomValues: bytes => { calls++; return processCrypto.getRandomValues(bytes); }});
  const f = fixture(t, `crypto.getRandomValues(new Uint32Array(1)); export const value = 7;`);
  const runtime = sandboxModule(f.output, crypto);
  assert.equal(calls, 0);
  assert.throws(() => runtime.value(), /synchronous function ABI/u);
  assert.equal(calls, 1, 'This is a post-initialization guard, not a compile-time proof');
  assert.throws(() => runtime.value(), /synchronous function ABI/u);
  assert.equal(calls, 1, 'A refused ABI cannot trigger another initializer');
});


test('named facade and raw imports share the exact exported functions and opaque custody', async t => {
  const f = fixture(t, `
const original = new WeakMap();
export function retain(value) { const token = Object.freeze({}); original.set(token, value); return token; }
export function restore(token) { if (!original.has(token)) throw new TypeError('Foreign custody'); return original.get(token); }
`);
  const facade = join(f.directory, 'facade.mjs');
  writeFileSync(facade, `export {retain, restore} from './deferred.mjs';`);
  const raw = await import(f.output);
  const named = await import(pathToFileURL(facade).href);
  const again = await import(f.output);
  assert.equal(named.retain, raw.retain);
  assert.equal(named.restore, raw.restore);
  assert.equal(again, raw);
  const original = Object.freeze({run: 'original-run', attempt: 1});
  const first = named.retain(original);
  assert.equal(raw.restore(first), original);
  const second = raw.retain(original);
  assert.equal(named.restore(second), original);
  assert.notEqual(first, second);
});
