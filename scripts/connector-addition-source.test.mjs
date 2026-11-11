import assert from 'node:assert/strict';
import test from 'node:test';
import {chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  rmSync, symlinkSync, unlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {runInNewContext} from 'node:vm';
import {parse} from 'acorn';
import {assertTestExecution, nodeTestArguments} from './test-execution.mjs';
import {copyConnectorAdditionHostSource, assertConnectorAdditionHostSource} from './connector-addition-source.mjs';

const repository = fileURLToPath(new URL('../',import.meta.url));
const temporary = t => {
  const root = mkdtempSync(join(tmpdir(),'actql-connector-common-source-'));
  t.after(() => rmSync(root,{recursive:true,force:true}));
  return root;
};
function fixture(t) {
  const root = temporary(t);
  for (const path of ['src/connectors_builtin/local_carrier_dispatch.mbt',
    'src/connectors_builtin_node/local_carrier_bridge.mbt','src/connectors_builtin_node/authorization_bridge.mbt',
    'src/connectors_builtin_node/client-program-dependencies.json','src/connectors_builtin_node/client-execution-dependencies.json']) {
    mkdirSync(dirname(join(root,path)),{recursive:true});writeFileSync(join(root,path),path);
  }
  return root;
}

function originalRun(t, platform, execute) {
  const isolated = temporary(t), calls = [], records = [];
  const source = readFileSync(join(repository, 'scripts/check-connector-addition.mjs'), 'utf8');
  const node = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
    .find(row => row.type === 'FunctionDeclaration' && row.id.name === 'run');
  assert(node);
  const invoke = runInNewContext('(' + source.slice(node.start, node.end) + ')', {
    isolated, join, writeFileSync, assertTestExecution, nodeTestArguments,
    process: {platform, env: {...process.env}, stderr: {write() {}}},
    console: {log(value) { records.push(JSON.parse(value)); }},
    spawnSync(command, args, options) {
      calls.push({command, args: [...args], options});
      return execute ? execute(command, args, options) : {
        status: 0, stdout: 'Total tests: 2, passed: 2, failed: 0.\n', stderr: '',
      };
    },
  });
  return {invoke, isolated, calls, records};
}

test('connector Native child consumes the existing Linux compiler prerequisite only', t => {
  const args = ['test', '--target', 'native', 'src/query_integration/standard_subset_wbtest.mbt'];
  const selected = originalRun(t, 'linux');
  selected.invoke('third-native', args);
  const call = selected.calls[0];
  assert.equal(selected.calls.length, 1);
  assert.equal(call.command, 'bash');
  const existing = readFileSync(join(repository, '.github/workflows/ci.yml'), 'utf8')
    .match(/ulimit -S -s 65536/u)?.[0];
  assert(existing);
  assert.deepEqual(call.args, ['-e', '-c', existing + '\nexec "$@"',
    'actql-native-compiler', 'moon', ...args]);
  assert.deepEqual(selected.records[0].compilerProcess, [call.command, ...call.args]);
  assert.deepEqual(selected.records[0].command, ['moon', ...args]);
  for (const [platform, target] of [['linux', 'js'], ['linux', 'wasm'], ['darwin', 'native']]) {
    const unchanged = originalRun(t, platform);
    const original = ['test', '--target', target, args[3]];
    unchanged.invoke('third-' + target, original);
    assert.equal(unchanged.calls[0].command, 'moon');
    assert.deepEqual(unchanged.calls[0].args, original);
    assert.equal(unchanged.records[0].compilerProcess, undefined);
  }
  const counts = {tests: 1, passed: 1, failed: 0, cancelled: 0, skipped: 0, todo: 0};
  const stdout = 'ACTQL_TEST_SUMMARY ' + JSON.stringify({success: true, counts,
    file: 'node-control.mjs'}) + '\nACTQL_TEST_SUMMARY ' + JSON.stringify({success: true, counts}) + '\n';
  const node = originalRun(t, 'linux', () => ({status: 0, stdout, stderr: ''}));
  const original = ['--test', '--test-name-pattern=standard native and broad Node Hosts',
    'adapters/connectors/duckdb/node/test/standard-host.test.mjs'];
  node.invoke('standard-node', original, process.execPath);
  assert.equal(node.calls[0].command, process.execPath);
  assert.deepEqual(node.calls[0].args, nodeTestArguments(original));
  assert.equal(node.records[0].compilerProcess, undefined);
});

test('connector Native prerequisite failure never starts or retries the compiler', t => {
  const bin = temporary(t), marker = join(bin, 'compiler-started');
  writeFileSync(join(bin, 'bash'), '#!/bin/bash\n' +
    'ulimit -S -s 8192\nulimit -H -s 16384\nexec /bin/bash "$@"\n');
  writeFileSync(join(bin, 'moon'), '#!/bin/sh\nprintf started > "$ACTQL_NATIVE_PROBE_MARKER"\n' +
    'printf "Total tests: 2, passed: 2, failed: 0.\\n"\n');
  for (const name of ['bash', 'moon']) chmodSync(join(bin, name), 0o755);
  // Set a lower inherited hard ceiling only in this fresh negative child.
  // The original launch must preserve it and fail before exec, never raise it.
  const selected = originalRun(t, 'linux', (command, args, options) =>
    spawnSync(command, args, {...options, env: {...options.env,
      PATH: bin + ':' + options.env.PATH, ACTQL_NATIVE_PROBE_MARKER: marker}, timeout: 5000}));
  assert.throws(() => selected.invoke('third-native', ['test', '--target', 'native',
    'src/query_integration/standard_subset_wbtest.mbt']), /third-native failed: 1/u);
  assert.equal(selected.calls.length, 1);
  assert.equal(existsSync(marker), false);
  assert.match(readFileSync(join(selected.isolated, 'third-native.log'), 'utf8'), /ulimit/u);
});

test('connector isolation preserves the actual common Client declaration package and dependency manifests', t => {
  const destination = temporary(t);
  const inputs = copyConnectorAdditionHostSource(repository,destination);
  for (const path of ['src/connectors_builtin/local_carrier_dispatch.mbt',
    'src/connectors_builtin_node/local_carrier_bridge.mbt','src/connectors_builtin_node/authorization_bridge.mbt',
    'src/connectors_builtin_node/client_infer_bridge.mbt','src/connectors_builtin_node/client_model_generation_config.mbt',
    'src/connectors_builtin_node/client_infer_original_composed.mbt',
    'src/connectors_builtin_node/client_program_bridge.mbt',
    'src/connectors_builtin_node/client_installation_preparation_fields.generated.mbt',
    'src/connectors_builtin_node/client-program-dependencies.json','src/connectors_builtin_node/client-execution-dependencies.json']) {
    assert(inputs.some(input => input.path === path),'Missing retained original: '+path);
  }
  for (const {path} of inputs) {
    assert.deepEqual(readFileSync(join(destination,path)),readFileSync(join(repository,path)),path);
    assert.equal(lstatSync(join(destination,path)).mode & 0o777,lstatSync(join(repository,path)).mode & 0o777,path);
    assert.notEqual(lstatSync(join(destination,path)).ino,lstatSync(join(repository,path)).ino,path);
  }
  assert.equal(existsSync(join(destination,'_build')),false);
  assert.equal(existsSync(join(destination,'node_modules')),false);
  assert.equal(existsSync(join(destination,'src/connectors/reference_compute')),false);
  assert.equal(existsSync(join(destination,'src/connectors_builtin_node/bridge.generated.mbt')),false);
  assert.equal(existsSync(join(destination,'src/connectors_builtin_node/moon.pkg')),false);
  assert(readdirSync(join(destination,'src/connectors_builtin_node')).every(name => !/_(?:wb)?test\.mbt$/u.test(name)));
  assertConnectorAdditionHostSource(destination,inputs);
});

test('connector source copy retains other-owner generated production data but excludes tests and assembly outputs', t => {
  const root = fixture(t),destination = temporary(t),pkg = join(root,'src/connectors_builtin_node');
  for (const name of ['plain.mbt','fields.generated.mbt','bridge.generated.mbt','sample_test.mbt','sample_wbtest.mbt','moon.pkg','pkg.generated.mbti','unrelated.log']) {
    writeFileSync(join(pkg,name),Buffer.from([0,13,10,255]));
  }
  chmodSync(join(pkg,'plain.mbt'),0o640);
  const inputs = copyConnectorAdditionHostSource(root,destination);
  for (const name of ['plain.mbt','fields.generated.mbt']) assert(existsSync(join(destination,'src/connectors_builtin_node',name)));
  for (const name of ['bridge.generated.mbt','sample_test.mbt','sample_wbtest.mbt','moon.pkg','pkg.generated.mbti','unrelated.log']) {
    assert.equal(existsSync(join(destination,'src/connectors_builtin_node',name)),false,name);
  }
  assert.equal(lstatSync(join(destination,'src/connectors_builtin_node/plain.mbt')).mode & 0o777,0o640);
  assertConnectorAdditionHostSource(destination,inputs);
});

test('connector source preparation rejects a linked production member instead of following it', t => {
  const root = fixture(t),destination = temporary(t);
  writeFileSync(join(root,'foreign.mbt'),'foreign original');
  symlinkSync(join(root,'foreign.mbt'),join(root,'src/connectors_builtin_node/linked.mbt'));
  assert.throws(() => copyConnectorAdditionHostSource(root,destination),/Nonregular common Host source/u);
});

test('connector source preparation refuses a missing declared dependency manifest', t => {
  const root = fixture(t),destination = temporary(t);
  unlinkSync(join(root,'src/connectors_builtin_node/client-program-dependencies.json'));
  assert.throws(() => copyConnectorAdditionHostSource(root,destination),{code:'ENOENT'});
});

test('regeneration cannot alter retained common source bytes or original modes', t => {
  const root = fixture(t),destination = temporary(t);
  const inputs = copyConnectorAdditionHostSource(root,destination);
  const path = join(destination,'src/connectors_builtin_node/authorization_bridge.mbt');
  const bytes = readFileSync(path),mode = lstatSync(path).mode & 0o777;
  writeFileSync(path,'changed shared input');
  assert.throws(() => assertConnectorAdditionHostSource(destination,inputs),/Changed retained common Host source bytes/u);
  writeFileSync(path,bytes);chmodSync(path,mode ^ 0o100);
  assert.throws(() => assertConnectorAdditionHostSource(destination,inputs),/Changed retained common Host source mode/u);
  chmodSync(path,mode);
  assertConnectorAdditionHostSource(destination,inputs);
});
