import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {delimiter, join} from 'node:path';
import test from 'node:test';
import {prepareNativeHttpCompilerScope} from './native-http-compiler-scope.mjs';

const groups = JSON.parse(readFileSync(new URL('./ci-native-background-groups.json', import.meta.url)));

test('macOS HTTP packages and original CLI controls use the existing two workers', () => {
  const mac = groups['native-macos'];
  assert.equal(mac.length, 2);
  const packages = mac.flatMap(group => group.steps).find(step => step.id === 'native-http');
  const controls = mac.flatMap(group => group.steps).find(step => step.id === 'native-http-controls');
  assert(packages && controls);
  assert.equal(packages.env.ACTQL_TEST_NATIVE_HTTP_FOCUS, 'http-packages');
  assert.equal(controls.env.ACTQL_TEST_NATIVE_HTTP_FOCUS, 'http-controls');
  assert(mac.find(group => group.steps.includes(packages)) !== mac.find(group => group.steps.includes(controls)));
  assert.notEqual(packages.env.ACTQL_TEST_SCRATCH_ROOT, controls.env.ACTQL_TEST_SCRATCH_ROOT);
  assert.equal(packages.run, controls.run);
  assert.equal(packages.timeoutMinutes, controls.timeoutMinutes);
});

test('the original complete HTTP path remains and both closed phases retain its original cleanup', () => {
  const source = readFileSync(new URL('./test-native-http-client.mjs', import.meta.url), 'utf8');
  assert(source.includes("'http-packages', 'http-controls'"));
  assert(source.includes("focus === 'http-controls' ? []"));
  assert(source.includes("if (focus === 'http-packages') break verification;"));
  assert(source.includes('prepareNativeHttpCompilerScope'));
  assert(source.includes('await standardGateway.close()'));
  assert(source.includes('await effectCheckpointServer?.close()'));
});

test('HTTP phase compiler keeps original Native argv and environment in disjoint actual child roots', t => {
  const parent = realpathSync(mkdtempSync(join(tmpdir(), 'actql-http-phase-')));
  t.after(() => rmSync(parent, {recursive: true, force: true}));
  const scopes = [];
  const env = {MOON_HOME: '/original/installed/tool',
    ACTQL_TEST_NATIVE_PORTABLE_RUNTIME_PREPARATION: '/original/portable.json',
    ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION: '/original/native'};
  for (const phase of ['packages', 'controls']) {
    const root = join(parent, phase); mkdirSync(root);
    const scope = prepareNativeHttpCompilerScope(process.cwd(), root, {env,
      platform: 'darwin', arch: 'arm64', copyTools: (original, target, marker) => {
        assert.equal(original, env.MOON_HOME); assert.equal(JSON.parse(marker).platform, 'darwin-arm64');
        mkdirSync(join(target, 'bin'), {recursive: true});
        writeFileSync(join(target, 'bin/moon'), '#!' + process.execPath + '\n' +
          'console.log(JSON.stringify({args:process.argv.slice(2),home:process.env.MOON_HOME,path:process.env.PATH,original:process.env.ORIGINAL_MARKER}));' +
          'process.exitCode=Number(process.env.HTTP_FIXTURE_EXIT??0);\n', {mode: 0o700});
      }});
    scopes.push(scope);
    const args = ['test', 'src/original', '--target', 'native', '--build-only'];
    const childEnv = {...process.env, ORIGINAL_MARKER: 'same environment'};
    const value = JSON.parse(execFileSync(scope.moon, args, {env: childEnv, encoding: 'utf8', timeout: 5000}));
    assert.deepEqual(value.args, [...args, '--target-dir', scope.targetDirectory]);
    assert.equal(value.home, join(root, 'compiler-tool'));
    assert(value.path.startsWith(join(root, 'compiler-bin') + delimiter + value.home + '/bin' + delimiter));
    assert.equal(value.original, childEnv.ORIGINAL_MARKER);
    const reused = JSON.parse(execFileSync(scope.moon, [...args, '--target-dir', scope.targetDirectory],
      {env: childEnv, encoding: 'utf8', timeout: 5000}));
    assert.deepEqual(reused.args, value.args);
    const nested = JSON.parse(execFileSync('moon', args, {
      env: {...childEnv, ...scope.environment}, encoding: 'utf8', timeout: 5000}));
    assert.deepEqual(nested.args, value.args, 'Nested original test wrappers must keep the same private target');
    const failed = spawnSync(scope.moon, args, {env: {...childEnv, HTTP_FIXTURE_EXIT: '17'}, encoding: 'utf8', timeout: 5000});
    assert.equal(failed.status, 17);
    const foreign = spawnSync(scope.moon, [...args, '--target-dir', join(parent, 'foreign')],
      {env: childEnv, encoding: 'utf8', timeout: 5000});
    assert.notEqual(foreign.status, 0); assert.equal(foreign.stdout, '');
  }
  assert.notEqual(scopes[0].targetDirectory, scopes[1].targetDirectory);
  assert.notEqual(scopes[0].moon, scopes[1].moon);
  assert.equal(env.MOON_HOME, '/original/installed/tool');
});

test('HTTP phase compiler refuses unsupported hosts and missing completed preparation before copying tools', () => {
  let copied = false;
  for (const options of [{platform: 'linux', arch: 'x64', env: {}},
    {platform: 'darwin', arch: 'arm64', env: {MOON_HOME: '/original'}}]) {
    assert.throws(() => prepareNativeHttpCompilerScope(process.cwd(), process.cwd(), {
      ...options, copyTools() { copied = true; }}));
  }
  assert.equal(copied, false);
});
