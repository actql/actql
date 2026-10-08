// Controlled edits to the actual Git tree test source invalidation, without
// qualifying a runtime, main origin or physical execution.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {readCatalog} from './actions.mjs';
import {gitTree, actionInputs, compareInputs, pipelineInventoryBoundary, hash} from './inputs.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
const original = gitTree(root, revision), catalog = readCatalog();
const runtime = {profile: 'controlled-source-observation', unresolved: ['no physical runtime qualification in this fixture']};
const changedTree = path => {
  assert(original.entries.has(path), 'Expected actual tracked input');
  return {entries: original.entries,
    read: input => input === path ? Buffer.concat([original.read(input), Buffer.from('\n// independently changed input\n')]) : original.read(input)};
};
const inputs = (action, tree = original) => actionInputs({tree, revision, action, runtime});

test('the real 30-action source catalog preserves every key for an unrelated Node Host edit', () => {
  assert.equal(catalog.actions.length, 30);
  const candidate = changedTree('adapters/host-node/client-http.mjs');
  for (const action of catalog.actions) {
    const before = inputs(action), after = inputs(action, candidate);
    assert.equal(after.key, before.key, action.id);
    assert.equal(compareInputs(before, after).equal, true, action.id);
    assert.equal(compareInputs(before, after).eligible, false, 'Equal sources do not qualify an unverified runtime');
  }
});

test('the actual Session catalog does not observe separate pipeline oracle edits', () => {
  const candidate = changedTree('proofs/relation-pipeline/execution-original.mjs');
  for (const action of catalog.actions) {
    const before = inputs(action), after = inputs(action, candidate);
    assert.equal(after.key, before.key, action.id);
    assert.equal(compareInputs(before, after).equal, true, action.id);
    assert.equal(compareInputs(before, after).eligible, false, 'Input equality cannot erase the unqualified runtime');
  }
});

test('a real Session implementation edit invalidates connected actions while model evidence stays independent', () => {
  const candidate = changedTree('src/bounded_execution/session.mbt');
  for (const id of ['model', 'events-model']) {
    const action = catalog.actions.find(value => value.id === id);
    assert.equal(inputs(action, candidate).key, inputs(action).key, id);
  }
  for (const id of ['session-js', 'session-wasm', 'session-native', 'mutations-js']) {
    const action = catalog.actions.find(value => value.id === id);
    assert.notEqual(inputs(action, candidate).key, inputs(action).key, id);
  }
});

test('a real Events theorem edit invalidates all Bridge obligations without invalidating the shared Session mechanism', () => {
  const candidate = changedTree('proofs/events-bridge/Composition.lean');
  for (const id of ['events-model', 'events-connection-js', 'events-connection-wasm', 'events-connection-native']) {
    const action = catalog.actions.find(value => value.id === id);
    assert.notEqual(inputs(action, candidate).key, inputs(action).key, id);
  }
  for (const id of ['model', 'session-js', 'mutations-js']) {
    const action = catalog.actions.find(value => value.id === id);
    assert.equal(inputs(action, candidate).key, inputs(action).key, id);
  }
});

test('reviewed inventory model admission changes no eager Session input read boundary', () => {
  const path = pipelineInventoryBoundary.path;
  const old = execFileSync('git', ['--no-replace-objects', 'show', `38f7801241a0a5ce32a2861a8603960016a29769^:${path}`], {cwd: root}).toString();
  const current = original.read(path).toString();
  assert.equal(hash(old), '9a7c1ffef354d2ba1cd60b70f7bbac7c68b49aac378a60cb5a0f66cb4b937e43');
  assert.equal(hash(current), pipelineInventoryBoundary.digest);
  // Only two Node builtin imports and the separately invoked checkBaseline
  // function changed. Snapshot/hash and all eager declarations are identical.
  const prefix = text => text.slice(0, text.indexOf('export function checkBaseline('));
  assert.deepEqual(prefix(current)
    .replace("import { spawnSync } from 'node:child_process';\n", '')
    .replace("import assert from 'node:assert/strict';\n", ''), prefix(old));
  const introduced = execFileSync('git', ['--no-replace-objects', 'show', `38f7801241a0a5ce32a2861a8603960016a29769:${path}`], {cwd: root});
  assert.equal(hash(introduced), hash(current), 'Unreviewed function or top-level change');
  assert.equal(readFileSync(new URL(`../../${path}`, import.meta.url)).toString(), current,
    'The executed module must match the actual Git input');
  // Execute the actual module with filesystem/child-process effects refused.
  // Preload its exact bytes so Node's own filesystem module loader is not
  // mistaken for an eager effect of the module. Its imports are Node builtins.
  const execute = source => {
    const url = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
    const input = `import fs from 'node:fs'; import child from 'node:child_process';
    import {syncBuiltinESMExports} from 'node:module';
    const refuse=()=>{throw new Error('Eager inventory effect');};
    for(const name of ['readFileSync','readdirSync','writeFileSync','statSync','lstatSync'])fs[name]=refuse;
    for(const name of ['spawnSync','execSync','execFileSync','spawn','exec','execFile','fork'])child[name]=refuse;
    syncBuiltinESMExports();
    await import(${JSON.stringify(url)}); console.log('PASS import without scientific I/O');`;
    return execFileSync(process.execPath, ['--input-type=module', '-e', input],
      {cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();
  };
  assert.equal(execute(current),
    'PASS import without scientific I/O');
  assert.throws(() => execute(`${current}\nreadFileSync('unlisted-scientific-input');\n`),
    error => error.status !== 0 && /Eager inventory effect/u.test(error.stderr),
    'The preload must still refuse an independently introduced eager read');
});
