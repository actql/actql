import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const startup = fileURLToPath(new URL('./infer-trusted-node-preload.cjs', import.meta.url));
const host = fileURLToPath(new URL('./embedded-local.mjs', import.meta.url));
function actualNamespace(t, body) {
  const root = mkdtempSync(join(tmpdir(), 'actql-actual-host-namespace-'));
  t.after(() => rmSync(root, {recursive: true}));
  const preload = join(root, 'preload.cjs'), entry = join(root, 'entry.mjs');
  // This intermediary is intentionally NOT the selected public preload. Load
  // the actual complete Host namespace, not a synthetic pair of its consumers,
  // while preserving operational absence. Matching runtime prerequisites must
  // be prepared separately; do not replace missing owners with test stubs.
  writeFileSync(preload, 'require(' + JSON.stringify(startup) + ');\n' +
    'globalThis.actualInitialHostNamespace=require(' + JSON.stringify(host) + ');\n');
  writeFileSync(entry, body);
  const result = spawnSync(process.execPath, ['--require', preload, entry], {
    cwd: root, env: {...process.env, NODE_OPTIONS: undefined},
    encoding: 'utf8', timeout: 30000});
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr);
}

test('the complete actual Host namespace loads before entry without issuing an operational scope', t => {
  actualNamespace(t, [
    'import assert from "node:assert/strict";',
    'const host=actualInitialHostNamespace;',
    'assert.equal(typeof host.connectEmbeddedLocal,"function");',
    'assert.equal(typeof host.assertInitialControlHostPreparation,"function");',
    'let reads=0;',
    'const options=Object.defineProperty({},"installation",{get(){reads++;throw new Error("CallerRead");}});',
    'await assert.rejects(host.connectEmbeddedLocal(options),{code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.equal(reads,0);',
  ].join('\n'));
});

test('the actual Host retains original startup forwarders after a cache export substitution', t => {
  actualNamespace(t, [
    'import assert from "node:assert/strict";',
    'import {createRequire} from "node:module";',
    'const require=createRequire(import.meta.url);',
    'let calls=0;',
    'require.cache[' + JSON.stringify(startup) + '].exports={',
    ' beginInitialControlInstallation(){calls++;return {assertCurrent(){},close(){return {pending:false};}};},',
    ' assertInitialControlInstallationCurrent(){calls++;}};',
    'await assert.rejects(actualInitialHostNamespace.connectEmbeddedLocal({}),',
    ' {code:"NodeInitialControlAdmissionUnavailable"});',
    'assert.equal(calls,0);',
  ].join('\n'));
});
