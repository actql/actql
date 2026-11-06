// Own-process mechanism and inert selection tests, not Native/Host runtime or
// public installation. Full genuine supplier/Remote acceptance stays separate.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, realpath, rm, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {parse} from 'acorn';
import {nativeReleaseInstallSelection, nativeStandaloneEnvironment} from './release-native-install.mjs';
import {releaseConsumerDestination} from './release-public-install.mjs';
import {runNativeInstallCommand, runNativeStandaloneInstall} from './test-native-standalone-install.mjs';

test('Native public consumer: explicit fixed digest target and fresh Node-free child environment have no fallback or credential input', async () => {
  const selected = nativeReleaseInstallSelection(['fixed', 'a'.repeat(64), 'native', 'host', '/new/consumer']);
  assert.equal(selected.kind, 'public-native-standalone'); assert.equal(selected.targetId, 'native');
  for (const input of [[], ['fixed'], ['fixed', 'HEAD', 'native', 'host', '/new'],
    ['fixed', 'a'.repeat(64), 'same', 'same', '/new'], ['fixed', 'a'.repeat(64), 'native', 'host', '/new', '--fallback']])
    assert.throws(() => nativeReleaseInstallSelection(input));
  const env = nativeStandaloneEnvironment({PATH: '/old/node:/old/compiler', HOME: '/old', NODE_OPTIONS: '--require old',
    DYLD_INSERT_LIBRARIES: '/old', LD_PRELOAD: '/old', ACTQL_NATIVE_LOCAL_RUNTIME: '/old', NPM_TOKEN: 'secret', LANG: 'C'}, '/new');
  assert.deepEqual(env, {PATH: '', HOME: '/new/home', TMPDIR: '/new/tmp', LANG: 'C'});
  await assert.rejects(runNativeStandaloneInstall([]), /usage:/u);
});

test('Native public consumer: external destination refuses source aliases and an earlier installation', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-native-destination-')); t.after(() => rm(root, {recursive: true}));
  const source = join(root, 'source'), outside = join(root, 'outside'), alias = join(root, 'alias');
  await mkdir(source); await mkdir(outside); await symlink(source, alias);
  await assert.rejects(releaseConsumerDestination(join(alias, 'new'), [source]), /physically outside/u);
  await assert.rejects(releaseConsumerDestination(outside, [source]), /already exists/u);
  assert.equal(await releaseConsumerDestination(join(outside, 'new'), [source]), join(await realpath(outside), 'new'));
});

test('Native public consumer: SAME own child acknowledges an actual live closed descriptor observation; held reader stays failed', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-native-observer-')); t.after(() => rm(root, {recursive: true}));
  const state = join(root, 'state'); await mkdir(state);
  const script = "const fs=require('node:fs');const held=process.argv[2]==='held';const fd=fs.openSync(process.argv[1],'w');if(!held)fs.closeSync(fd);process.stdin.setEncoding('utf8');process.stdin.once('data',v=>{if(held)fs.closeSync(fd);if(v==='observed\\n')console.log(JSON.stringify({stage:'close-observation-ack',pid:process.pid}));else process.exitCode=2;process.stdin.destroy();});console.log(JSON.stringify({stage:'closed',pid:process.pid,clientCloseReturned:true,hostCloseReturned:true}));";
  const options = {cwd: root, env: {PATH: '', HOME: root}, state};
  const actual = await runNativeInstallCommand(process.execPath, ['-e', script, join(state, 'closed'), 'closed'], options);
  assert.equal(actual.close.aliveAfterClose, true); assert.equal(actual.close.scopedStateFd0, true);
  assert.equal(actual.closeObservationAcknowledged, true);
  await assert.rejects(runNativeInstallCommand(process.execPath, ['-e', script, join(state, 'held'), 'held'], options),
    failure => failure.commandRecord.closeObservationFailure && failure.commandRecord.code === 2);
  const missing = await runNativeInstallCommand(join(root, 'no-binary'), [], {cwd: root, env: {PATH: ''}, expectedError: 'ENOENT'});
  assert.equal(missing.spawnFailure, 'ENOENT');
});

async function remoteFixture() {
  const source = await readFile(new URL('./fixtures/release-native-host.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const declarations = syntax.body.filter(node => node.type === 'VariableDeclaration')
    .flatMap(node => node.declarations);
  return {source, syntax, declarations};
}

function calls(node) {
  if (node === null || typeof node !== 'object') return [];
  return [...(node.type === 'CallExpression' ? [node] : []),
    ...Object.values(node).filter(value => value !== null && typeof value === 'object')
      .flatMap(value => Array.isArray(value) ? value.flatMap(calls) : calls(value))];
}

test('Native public consumer: Remote operator grants only current-principal pure submission and separate Run/main reads', async () => {
  const {source, declarations} = await remoteFixture();
  const original = declarations.find(node => node.id.name === 'authorization');
  assert(original);
  const authorization = Function('userInfo', `return (${source.slice(original.init.start, original.init.end)});`)(
    () => ({username: 'native-release-operator'}));
  assert.deepEqual(JSON.parse(authorization.accountConfiguration), {
    version: 'actql-execution-account-config/0.1', account_id: 'native-release-http',
    entries: [{entry_id: 'compute-write', outcome: 'allow',
      principal: {any_of: ['native-release-operator']}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['source-free-values']}, operation: {any_of: ['write']}, exclusions: []},
    {entry_id: 'result-main-read', outcome: 'allow',
      principal: {any_of: ['native-release-operator']}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/main']}, operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'run-read', outcome: 'allow',
      principal: {any_of: ['native-release-operator']}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['run']}, operation: {any_of: ['read']}, exclusions: []}],
  });
  const host = declarations.find(node => node.id.name === 'host').init.argument;
  assert.equal(host.callee.name, 'openInstalledRemoteHttpHost');
  const selected = host.arguments[0].properties.filter(node => node.key.name === 'authorization');
  assert.equal(selected.length, 1); assert.equal(selected[0].value.name, 'authorization');
});

test('Native public consumer: installed denial controls remove only the selected independent read permission', async () => {
  const {source, declarations} = await remoteFixture();
  const original = declarations.find(node => node.id.name === 'authorization');
  const principal = () => ({username: 'native-release-operator'});
  const positive = Function('userInfo', `return (${source.slice(original.init.start, original.init.end)});`)(principal);
  const negative = await readFile(new URL('./fixtures/release-native-host-authorization.mjs', import.meta.url), 'utf8');
  const syntax = parse(negative, {sourceType: 'module', ecmaVersion: 'latest'});
  const factory = syntax.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'fixtureAuthorization');
  assert(factory);
  const authorization = Function('userInfo', `return (${negative.slice(factory.start, factory.end)});`)(principal);
  assert.deepEqual(authorization(), positive);
  for (const omitted of ['run-read', 'result-main-read']) {
    const expected = JSON.parse(positive.accountConfiguration);
    expected.entries = expected.entries.filter(entry => entry.entry_id !== omitted);
    assert.deepEqual(JSON.parse(authorization(omitted).accountConfiguration), expected);
  }
});

test('Native public consumer: Result readiness polls only the original Result under one finite deadline', async () => {
  const source = await readFile(new URL('./fixtures/release-native-host-authorization.mjs', import.meta.url), 'utf8');
  const syntax = parse(source, {sourceType: 'module', ecmaVersion: 'latest'});
  const helper = syntax.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'readReadyResult');
  assert(helper);
  const abort = new Error('fixture deadline');
  let signal, deadlines, sleeps, reads, selected;
  const reset = () => {
    signal = {aborted: false, throwIfAborted() {if (this.aborted) throw abort;}};
    deadlines = 0; sleeps = 0; reads = 0; selected = 0;
  };
  const ready = Function('AbortSignal', 'sleep', `return (${source.slice(helper.start, helper.end)});`)(
    {timeout(ms) {assert.equal(ms, 30_000); deadlines++; return signal;}},
    async (ms, value, options) => {
      assert.equal(ms, 100); assert.equal(value, undefined); assert.equal(options.signal, signal); sleeps++;
    });
  const execution = read => Object.freeze({result(name) {
    assert.equal(name, 'main'); selected++;
    return Object.freeze({all(options) {assert.equal(options.signal, signal); reads++; return read();}});
  }});
  const pending = () => Object.assign(new Error('ResultAccessDenied'), {code: 'ResultAccessDenied', rowsYielded: 0});
  reset();
  const receipt = {denials: []}, rows = [{id: 1}, {id: 2}];
  assert.equal(await ready(execution(() => {if (reads < 3) throw pending(); return rows;}), receipt), rows);
  assert.deepEqual({deadlines, sleeps, reads, selected}, {deadlines: 1, sleeps: 2, reads: 3, selected: 1});
  assert.equal(receipt.resultReadAttempts, 3);
  assert.deepEqual(receipt.pendingResultReads, [1, 2].map(attempt =>
    ({attempt, code: 'ResultAccessDenied', rowsYielded: 0})));
  assert.deepEqual(receipt.denials, []);

  for (const error of [Object.assign(pending(), {code: 'ResultUnavailable'}),
    Object.assign(pending(), {rowsYielded: 1}), new Error('unexpected')]) {
    reset();
    await assert.rejects(ready(execution(() => {throw error;}), {}), actual => actual === error);
    assert.deepEqual({reads, sleeps}, {reads: 1, sleeps: 0});
  }
  reset();
  const failure = pending(), exhausted = {};
  await assert.rejects(ready(execution(() => {throw failure;}), exhausted), error => error === failure);
  assert.deepEqual({deadlines, sleeps, reads, selected}, {deadlines: 1, sleeps: 299, reads: 300, selected: 1});
  assert.equal(exhausted.resultReadAttempts, 300);
  reset();
  await assert.rejects(ready(execution(() => {signal.aborted = true; throw failure;}), {}), error => error === failure);
  assert.deepEqual({reads, sleeps}, {reads: 1, sleeps: 0});
  reset(); signal.aborted = true;
  await assert.rejects(ready(execution(() => assert.fail('expired deadline cannot read')), {}), error => error === abort);
  assert.deepEqual({reads, sleeps}, {reads: 0, sleeps: 0});
});

test('Native public consumer: implicit SQL Result is main; every other original Remote business assertion stays pinned', async () => {
  const {source, syntax} = await remoteFixture();
  const allCalls = calls(syntax);
  const query = allCalls.filter(node => node.callee.name === 'writeFile' && node.arguments[0]?.value === 'query.sql');
  assert.equal(query.length, 1);
  assert.equal(query[0].arguments[1].value, 'SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id');
  // docs/reference/syntax.md specifies main when a read-only Program has no
  // RESULT. Independently require all three original selectors to use it.
  const cli = allCalls.filter(node => node.callee.name === 'run' &&
    node.arguments.some(argument => argument.value === '--result-name'));
  assert.deepEqual(cli.map(node => node.arguments[0].value), ['read', 'delivery-attempt']);
  const sdk = allCalls.filter(node => node.callee.type === 'MemberExpression' &&
    node.callee.object.name === 'execution' && node.callee.property.name === 'result');
  assert.equal(sdk.length, 1);
  const selectors = [...cli.map(node => node.arguments[
    node.arguments.findIndex(argument => argument.value === '--result-name') + 1]), sdk[0].arguments[0]];
  for (const selector of selectors) {
    assert.equal(selector.type, 'Literal'); assert.equal(selector.value, 'main');
  }
  // Keep the independent BEFORE digest at ee50a50f56. Normalize ONLY the
  // three asserted Result-name literals to their historical spelling, never
  // regenerate a digest from current fixture or product output. This retains
  // every original command, row/schema oracle, no-recompute and close check.
  let historical = source;
  for (const selector of selectors.sort((left, right) => right.start - left.start)) {
    historical = historical.slice(0, selector.start) + "'answer'" + historical.slice(selector.end);
  }
  const body = historical.slice(historical.indexOf('let client;'),
    historical.indexOf('\nif (standaloneHome !== undefined)')).trim();
  assert.equal(createHash('sha256').update(body).digest('hex'), '0cf6e52f475cb3b3692f4a72f53e5007af7f83b64ad128b9f244f5fe4873254f');
});
