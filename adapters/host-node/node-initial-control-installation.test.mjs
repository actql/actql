import assert from 'node:assert/strict';
import test from 'node:test';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {beginInitialControlInstallation, assertInitialControlInstallationCurrent,
  readInitialControlInstallationAsset}
  from './node-initial-control-installation.mjs';

// Current selected preload has no complete initial-control operational issuer.
// These are actual absence/refusal cases, not a fixture issuing an admission or
// a positive Host, preparation, physical-capacity or business-Run qualification.
const unavailable = error => error.code === 'NodeInitialControlAdmissionUnavailable';

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

test('late ordinary import has no synthetic or reusable pending admission', () => {
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

// Exercise the actual CJS startup and ESM consumer Sources through Node's real
// synchronous namespace loader. Only the fixture's appended eager import is
// new: no operational original, scope, Common runtime or Host is supplied.
function eagerOriginalNamespace(t, body) {
  const root = mkdtempSync(join(tmpdir(), 'actql-initial-control-namespace-'));
  t.after(() => rmSync(root, {recursive: true}));
  for (const name of ['node-initial-control-installation.mjs',
    'initial-control-installation-owner.cjs', 'infer-trusted-runtime-view.mjs']) {
    writeFileSync(join(root, name), readFileSync(new URL(name, import.meta.url)));
  }
  writeFileSync(join(root, 'infer-trusted-node-preload.cjs'),
    readFileSync(new URL('infer-trusted-node-preload.cjs', import.meta.url), 'utf8') +
    '\nglobalThis.originalHostNamespace = require("./host.mjs");\n');
  writeFileSync(join(root, 'host.mjs'),
    'export {beginInitialControlInstallation, assertInitialControlInstallationCurrent,readInitialControlInstallationAsset}' +
    ' from "./node-initial-control-installation.mjs";\n' +
    'export * from "./infer-trusted-runtime-view.mjs";\n');
  // The intermediary deliberately does not match the selected public recipe.
  // Therefore the copied original startup must remain operationally absent.
  writeFileSync(join(root, 'preload.cjs'),
    'require("./infer-trusted-node-preload.cjs");\n');
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
    'assert.equal(reads, 0);',
  ].join('\n'));
});

test('eager consumer retains captured forwarders rather than a later cache export replacement', t => {
  eagerOriginalNamespace(t, [
    'import assert from "node:assert/strict";',
    'import {createRequire} from "node:module";',
    'const require = createRequire(import.meta.url);',
    'const filename = require.resolve("./infer-trusted-node-preload.cjs");',
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
