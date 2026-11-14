import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {delimiter, join} from 'node:path';
import test from 'node:test';
import {prepareNativeHttpCompilerScope} from './native-http-compiler-scope.mjs';
import * as httpScope from './native-http-compiler-scope.mjs';
import {parse as parseYaml} from 'yaml';
import {parse} from 'acorn';

const groups = JSON.parse(readFileSync(new URL('./ci-native-background-groups.json', import.meta.url)));

test('Source coverage defaults to complete and only the closed Darwin package owner can redistribute it', () => {
  assert.equal(typeof httpScope.nativeHttpSourceCoverage, 'function');
  for (const platform of ['linux', 'darwin'])
    for (const focus of [undefined, 'http-packages', 'http-controls', 'core-source'])
      assert.deepEqual(httpScope.nativeHttpSourceCoverage(focus, {platform, owner: undefined}),
        {includeSource: true, effectTargets: {reads: 3, writes: 1}});
  const owner = 'linux-http+darwin-core-source';
  assert.deepEqual(httpScope.nativeHttpSourceCoverage('http-packages', {platform: 'darwin', owner}),
    {includeSource: false, effectTargets: {reads: 0, writes: 0}});
  for (const options of [{platform: 'linux', owner}, {platform: 'darwin', owner: ''},
    {platform: 'darwin', owner: 'other'}, {platform: 'darwin', owner: null}])
    assert.throws(() => httpScope.nativeHttpSourceCoverage('http-packages', options));
  for (const focus of [undefined, 'http-controls', 'core-source', 'core-http'])
    assert.throws(() => httpScope.nativeHttpSourceCoverage(focus, {platform: 'darwin', owner}));
});

test('Source coverage redistribution requires current Linux HTTP and complete Darwin Core outcomes', () => {
  const workflow = parseYaml(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const gate = workflow.jobs['native-http-macos'];
  assert.deepEqual(gate.needs, ['select-targets', 'native-macos-workloads', 'native-http', 'core']);
  assert.equal(gate['runs-on'], 'ubuntu-24.04');
  const step = gate.steps[0];
  assert.equal(step.env.LINUX_HTTP_RESULT, '${{ needs.native-http.result }}');
  assert.equal(step.env.DARWIN_CORE_RESULT, '${{ needs.core.result }}');
  assert.equal(step.env.CORE_TARGETS, '${{ needs.select-targets.outputs.targets }}');
  const selected = groups['native-macos'].flatMap(group => group.steps).filter(step => step.env?.ACTQL_TEST_NATIVE_HTTP_SOURCE_OWNER);
  assert.equal(selected.length, 1); assert.equal(selected[0].id, 'native-http');
  assert.equal(selected[0].env.ACTQL_TEST_NATIVE_HTTP_SOURCE_OWNER, 'linux-http+darwin-core-source');
  const keys = ['WORKLOAD_RESULT', 'HTTP_RESULT', 'LINUX_HTTP_RESULT', 'DARWIN_CORE_RESULT'];
  const success = {...Object.fromEntries(keys.map(key => [key, 'success'])), CORE_TARGETS: '["js","wasm","native"]'};
  const run = env => spawnSync('bash', ['-eo', 'pipefail', '-c', step.run], {
    encoding: 'utf8', timeout: 5000, env: {...process.env, ...env},
  });
  assert.equal(run(success).status, 0);
  for (const key of keys) for (const value of ['failure', 'cancelled', 'skipped', '']) {
    const result = run({...success, [key]: value});
    assert.equal(result.error, undefined); assert.equal(result.signal, null);
    assert.notEqual(result.status, 0, `${key}=${value || 'missing'} cannot certify coverage`);
  }
  for (const value of ['', '[]', '["js","wasm"]', 'null', 'invalid'])
    assert.notEqual(run({...success, CORE_TARGETS: value}).status, 0);
  assert(workflow.jobs['core-darwin'].strategy.matrix.partition.includes('source'));
  assert(!(workflow.jobs['core-darwin'].strategy.matrix.exclude ?? []).some(row => row.target === 'native' && row.partition === 'source'));
  const core = workflow.jobs['core-darwin'].steps.find(step => step.name === 'Test common core');
  assert(core.run.includes('MOONBIT_NEW_NATIVE=0 node scripts/test-native-core.mjs --deny-warn --release --strip -j 2 --no-parallelize --verbose'));
  const linux = workflow.jobs['native-http'];
  assert.equal(linux['runs-on'], 'ubuntu-24.04');
  assert(linux.steps.some(step => step.run?.includes('node scripts/test-native-http-client.mjs')));
});

test('Source coverage caller omits only the repeated complete package and keeps independent exact physical oracles', () => {
  const source = readFileSync(new URL('./test-native-http-client.mjs', import.meta.url), 'utf8');
  const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const found = [];
  function walk(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'ForOfStatement' && node.left.declarations?.[0]?.id.name === 'packagePath') found.push(node);
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) for (const value of child) walk(value);
      else if (child && typeof child === 'object') walk(child);
    }
  }
  walk(tree); assert.equal(found.length, 1);
  const loop = found[0];
  assert.equal(loop.right.alternate.elements.length, 15);
  const skip = loop.body.body[0];
  assert.equal(skip.type, 'IfStatement'); assert.equal(skip.consequent.type, 'ContinueStatement');
  assert.equal(source.slice(skip.test.start, skip.test.end),
    "packagePath === 'src/platform_native/remote_resident_source_compute_tests' && !sourceCoverage.includeSource");
  assert(source.includes('assert.deepEqual(bearerServers.effectTargets(), sourceCoverage.effectTargets)'));
  assert(source.includes('sourceCoverage.includeSource ? [{Id: \'001000000000001AAA\', Count__c: 3}] : []'));
  assert(source.includes('assert.deepEqual(bearerServers.effectTargets(), {reads: 3, writes: 1})'),
    'The complete original Core Source fixture keeps its independent 3/1 oracle');
});

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
