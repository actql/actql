// Argument/environment preparation only; no public HTTP, venv, product or build.
import assert from 'node:assert/strict';
import test from 'node:test';
import {spawn} from 'node:child_process';
import {mkdtemp, mkdir, rm, symlink, realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pythonReleaseInstallSelection, pythonPublicConsumerEnvironment, pythonInstallCommand, pythonConsumerDestination} from './release-public-install.mjs';
import {runPythonReleaseInstall, observeChildFds} from './test-python-release-install.mjs';

test('Python public consumer: fixed digest, target, absolute interpreter and new destination are explicit', () => {
  const value = pythonReleaseInstallSelection(['fixed', 'a'.repeat(64), 'python', '/selected/python', '/new/consumer']);
  assert.equal(value.kind, 'public-pypi'); assert.equal(value.python, '/selected/python');
  for (const args of [[], ['fixed'], ['fixed', 'HEAD', 'python', '/selected/python', '/new/consumer'],
    ['fixed', 'a'.repeat(64), 'python', 'python', '/new/consumer'],
    ['fixed', 'a'.repeat(64), 'python', '/selected/python', '/new/consumer', '--fallback']])
    assert.throws(() => pythonReleaseInstallSelection(args));
});

test('Python public consumer: fresh process environment has no Node path, source injection or publisher credentials', () => {
  const env = pythonPublicConsumerEnvironment({PATH: '/old/node:/usr/bin', HOME: '/old', PYTHONPATH: '/source',
    PYTHONHOME: '/old-python', PYTHONSTARTUP: '/old-startup', PIP_INDEX_URL: 'https://owner:secret@private',
    PIP_EXTRA_INDEX_URL: 'https://private', TWINE_PASSWORD: 'secret', HTTPS_PROXY: 'http://private',
    ACTQL_LOCAL_SOURCE_PROFILE: '/old-profile', NODE_OPTIONS: '--require old-code', LANG: 'C'}, '/new/consumer', '/new/consumer/venv/bin/python');
  assert.equal(env.PATH, '/new/consumer/venv/bin'); assert.equal(env.HOME, '/new/consumer/home');
  assert.equal(env.PIP_CONFIG_FILE, '/dev/null');
  assert.deepEqual(Object.keys(env).sort(), ['HOME', 'LANG', 'PATH', 'PIP_CONFIG_FILE', 'TEMP', 'TMP', 'TMPDIR'].sort());
});

test('Python public consumer: pip requests only the exact public entry using the shared version projection and no source builds', () => {
  const command = pythonInstallCommand('0.0.7-rc.1', 'actql', '/new/report.json');
  assert.deepEqual(command, ['-I', '-B', '-m', 'pip', '--isolated', 'install', '--index-url', 'https://pypi.org/simple',
    '--only-binary=:all:', '--no-cache-dir', '--no-compile', '--disable-pip-version-check', '--no-input',
    '--report', '/new/report.json', 'actql==0.0.7rc1']);
  assert.equal(pythonInstallCommand('0.0.7', 'actql-sdk', '/new/report.json').at(-1), 'actql-sdk==0.0.7');
  for (const version of ['patch', '0.0.7rc1', '0.0.7\n']) assert.throws(() => pythonInstallCommand(version, 'actql', '/report'));
  assert.throws(() => pythonInstallCommand('0.0.7', 'actql-local-runtime', '/report'));
});

test('Python public consumer: invalid launcher input stops before registry, installation or business execution', async () => {
  await assert.rejects(runPythonReleaseInstall([]), /usage:/u);
});

test('Python public consumer: actual own-child state descriptor observation distinguishes closed and still-held files', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-python-close-observer-')); t.after(() => rm(root, {recursive: true}));
  for (const held of [false, true]) {
    const child = spawn(process.execPath, ['-e',
      "const fs=require('node:fs');const fd=fs.openSync(process.argv[1],'w');if(process.argv[2]==='closed')fs.closeSync(fd);console.log('ready');process.stdin.once('data',()=>{if(process.argv[2]==='held')fs.closeSync(fd);process.stdin.destroy();});",
      join(root, 'state.db'), held ? 'held' : 'closed'], {stdio: ['pipe', 'pipe', 'pipe']});
    const terminal = new Promise((resolve, reject) => {child.once('error', reject); child.once('close', code => resolve(code));});
    t.after(() => child.stdin.end('done\n'));
    await new Promise((resolve, reject) => {child.stdout.once('data', resolve); child.once('error', reject);});
    if (held) await assert.rejects(observeChildFds(child, root));
    else assert.equal((await observeChildFds(child, root)).scopedStateFd0, true);
    child.stdin.end('done\n'); assert.equal(await terminal, 0);
  }
});

test('Python public consumer: physical destination refuses a source-parent alias or any existing state', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-python-consumer-path-')); t.after(() => rm(root, {recursive: true}));
  const source = join(root, 'source'), outside = join(root, 'outside'); await mkdir(source); await mkdir(outside);
  const alias = join(root, 'source-alias'); await symlink(source, alias);
  await assert.rejects(pythonConsumerDestination(join(alias, 'new-state'), [source]), /physically outside/u);
  await assert.rejects(pythonConsumerDestination(source, [source]), /physically outside/u);
  await assert.rejects(pythonConsumerDestination(outside, [source]), /already exists/u);
  assert.equal(await pythonConsumerDestination(join(outside, 'fresh'), [source]), join(await realpath(outside), 'fresh'));
});
