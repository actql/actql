// Own-process mechanism and inert selection tests, not Native/Host runtime or
// public installation. Full genuine supplier/Remote acceptance stays separate.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, realpath, rm, symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
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

test('Native public consumer: original Remote business body is unchanged and child-only environment does not replace its protocol', async () => {
  const path = 'scripts/fixtures/release-native-host.mjs';
  const current = await readFile(path, 'utf8');
  // Independent immutable BEFORE source at ee50a50f56, never generated from a
  // product/Host result or updated by a fixture generator.
  const body = current.slice(current.indexOf('let client;'), current.indexOf('\nif (standaloneHome !== undefined)')).trim();
  assert.equal(createHash('sha256').update(body).digest('hex'), '0cf6e52f475cb3b3692f4a72f53e5007af7f83b64ad128b9f244f5fe4873254f');
});
