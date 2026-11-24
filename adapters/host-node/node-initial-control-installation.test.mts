import assert from 'node:assert/strict';
import test from 'node:test';
import type {TestContext} from 'node:test';
import {spawnSync} from 'node:child_process';
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {localModuleGraphInputs} from '../../scripts/adapter-module-graph.mjs';

const selectedLabel = '@actql/node/selected-infer-startup';
async function loadLateSelectedConsumer() {
  const execArgv = process.execArgv;
  // Select the consumer route while loading the real preload after entry.
  // The label cannot supply the original early loader or an operational issuer.
  process.execArgv = [...execArgv, selectedLabel];
  try { return await import('./node-initial-control-installation.mjs'); }
  finally { process.execArgv = execArgv; }
}
const {beginInitialControlInstallation, assertInitialControlInstallationCurrent,
  readInitialControlInstallationAsset, readInitialControlInstallationInput} = await loadLateSelectedConsumer();

// Current selected preload has no complete initial-control operational issuer.
// These are actual absence/refusal cases, not a fixture issuing an admission or
// a positive Host, preparation, physical-capacity or business-Run qualification.
const unavailable = (error: unknown) => (error as {code?: unknown}).code === 'NodeInitialControlAdmissionUnavailable';

test('initial control refuses absent operational startup before observing caller fields', () => {
  let observed = 0;
  const originals = Object.defineProperty({}, 'host', {get() {
    observed++;
    throw new Error('CallerIsNotAStartupIssuer');
  }});
  assert.throws(() => beginInitialControlInstallation(originals), unavailable);
  assert.throws(() => readInitialControlInstallationAsset({}, originals, 'spec/control.json'), unavailable);
  assert.equal(observed, 0);
});

test('bounds runtime references and matching DATA cannot replace the startup issuer', () => {
  const originals = Object.freeze({host: {}, installation: {}, generation: {},
    supplier() {}, moduleLifetime: import.meta, runtime: process,
    maxBytes: 65536, ledger: {}, admitted: true, cid: `sha256:${'0'.repeat(64)}`});
  assert.throws(() => beginInitialControlInstallation(originals), unavailable);
  assert.throws(() => beginInitialControlInstallation({...originals}), unavailable);
});

test('late selected consumer import has no synthetic or reusable pending admission', () => {
  for (const originals of [undefined, null, false, {}, {}]) {
    assert.throws(() => beginInitialControlInstallation(originals), unavailable);
  }
});

test('a caller current method cannot authenticate an initial control scope', () => {
  let observed = 0;
  const scope = Object.freeze({assertCurrent() { observed++; }});
  assert.throws(() => assertInitialControlInstallationCurrent(scope, {}), unavailable);
  assert.equal(observed, 0);
});

test('the actual absent startup cannot acquire raw preparation input or project a supplied snapshot', () => {
  let observations = 0;
  const raw = new Proxy({}, {ownKeys() { observations++; throw new Error('RawOwnKeys'); },
    get() { observations++; throw new Error('RawGet'); },
    getOwnPropertyDescriptor() { observations++; throw new Error('RawDescriptor'); }});
  assert.throws(() => beginInitialControlInstallation({}, raw), unavailable);
  assert.throws(() => readInitialControlInstallationInput(raw, raw), unavailable);
  assert.equal(observations, 0);
});

// Exercise the actual CJS startup and ESM consumer Sources through Node's real
// synchronous namespace loader. Only the fixture's appended eager import is
// new: no operational original, scope, Common runtime or Host is supplied.
function eagerOriginalNamespace(t: TestContext, body: string) {
  const root = mkdtempSync(join(tmpdir(), 'actql-initial-control-namespace-'));
  t.after(() => rmSync(root, {recursive: true}));
  const checkout = fileURLToPath(new URL('../../', import.meta.url));
  const hostDirectory = 'adapters/host-node';
  const preload = join(hostDirectory, 'infer-trusted-node-preload.cjs');
  const sources = localModuleGraphInputs(checkout, [preload,
    join(hostDirectory, 'node-initial-control-installation.mjs'),
    join(hostDirectory, 'infer-trusted-runtime-view.mjs')], {
    // This source-only refusal fixture has no operational package inventory.
    external: ['./initial-control-package-original.cjs'],
  });
  for (const source of sources) {
    const destination = join(root, source);
    mkdirSync(dirname(destination), {recursive: true});
    copyFileSync(join(checkout, source), destination);
  }
  // The real preload evaluates its provenance before the appended fixture
  // selects the consumer's forwarding branch for the synchronous ESM handoff.
  writeFileSync(join(root, preload), readFileSync(join(root, preload), 'utf8') +
    '\nconst fixtureArgv = originalProcess.execArgv;\n' +
    'originalProcess.execArgv = [...fixtureArgv, ' + JSON.stringify(selectedLabel) + '];\n' +
    'try { globalThis.originalHostNamespace = require("./host.mjs"); }\n' +
    'finally { originalProcess.execArgv = fixtureArgv; }\n');
  writeFileSync(join(root, hostDirectory, 'host.mjs'),
    'export {beginInitialControlInstallation, assertInitialControlInstallationCurrent,readInitialControlInstallationAsset,readInitialControlInstallationInput}' +
    ' from "./node-initial-control-installation.mjs";\n' +
    'export * from "./infer-trusted-runtime-view.mjs";\n');
  // This intermediary does not match the selected public preload recipe.
  writeFileSync(join(root, 'preload.cjs'), 'require("./' + preload + '");\n');
  const entry = join(root, 'entry.mjs');
  writeFileSync(entry, body);
  const result = spawnSync(process.execPath,
    ['--require', join(root, 'preload.cjs'), entry],
    {cwd: root, env: {...process.env, NODE_OPTIONS: undefined},
      encoding: 'utf8', timeout: 20000});
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr);
}

test('eager original namespace captures the actual startup forwarders without a CJS ESM cycle', t => {
  eagerOriginalNamespace(t, [
    'import assert from "node:assert/strict";',
    'const original = globalThis.originalHostNamespace;',
    'let reads = 0;',
    'const packet = Object.defineProperty({}, "host", {get(){reads++;}});',
    'assert.throws(()=>original.beginInitialControlInstallation(packet),',
    '  {code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.throws(()=>original.assertInitialControlInstallationCurrent({}, packet),',
    '  {code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.throws(()=>original.readInitialControlInstallationAsset({},packet,"spec/control.json"),',
    '  {code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.throws(()=>original.readInitialControlInstallationInput({},packet),',
    '  {code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.equal(reads, 0);',
  ].join('\n'));
});

test('eager consumer retains captured forwarders rather than a later cache export replacement', t => {
  eagerOriginalNamespace(t, [
    'import assert from "node:assert/strict";',
    'import {createRequire} from "node:module";',
    'const require = createRequire(import.meta.url);',
    'const filename = require.resolve("./adapters/host-node/infer-trusted-node-preload.cjs");',
    'let replacementCalls = 0;',
    'require.cache[filename].exports = {beginInitialControlInstallation(){replacementCalls++;},',
    '  assertInitialControlInstallationCurrent(){replacementCalls++;}};',
    'assert.throws(()=>originalHostNamespace.beginInitialControlInstallation({}),',
    '  {code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.throws(()=>originalHostNamespace.assertInitialControlInstallationCurrent({}, {}),',
    '  {code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.equal(replacementCalls, 0);',
  ].join('\n'));
});
