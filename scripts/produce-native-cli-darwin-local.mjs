// Selected Darwin orchestration of the existing component and Native owners.
// This entry supplies no build/release authority; use the existing bounded guard.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {accessSync, constants, lstatSync, mkdirSync, realpathSync, writeFileSync} from 'node:fs';
import {dirname, isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeCliCompileBudget} from './native-cli-artifact.mjs';
import {admitNativeArtifact, requireNativePackageVersion} from './native-cli-artifact-reader.mjs';
import {nativePackageVersion} from './native-cli-version.mjs';
import {original, requireNativeLocalHeader} from './native-cli-original-input.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const absolute = (value, label) => {
  assert(typeof value === 'string' && isAbsolute(value) && resolve(value) === value && !/[\0\r\n:]/u.test(value),
    `${label} requires an explicit canonical absolute path`);
};
const inside = (value, parent) => parent === '/' || value === parent || value.startsWith(parent + '/');

export function parseNativeDarwinLocalArguments(args) {
  const flags = {'--source': 'sourceSha', '--package-version': 'packageVersion', '--output': 'outputDirectory',
    '--clang': 'clang', '--sdk': 'sdk', '--sqlite-archive': 'sqliteArchive', '--openssl-source-archive': 'opensslSourceArchive',
    '--component-seconds': 'componentSeconds', '--compile-seconds': 'compileSeconds',
    '--model-http-preparation': 'modelHttpPreparation'};
  assert(Array.isArray(args) && args.length % 2 === 0, 'Select source, version, compiler/SDK, both original archives and fresh output');
  const options = {};
  for (let index = 0; index < args.length; index += 2) {
    const key = flags[args[index]], value = args[index + 1];
    assert(key && typeof value === 'string' && value && !value.startsWith('--') && !Object.hasOwn(options, key),
      'Unknown, duplicate or incomplete Darwin producer selection');
    if (key.endsWith('Seconds')) {assert.match(value, /^[1-9][0-9]*$/u); options[key] = Number(value);}
    else options[key] = value;
  }
  planNativeDarwinLocalProduction(options);
  return options;
}

export function planNativeDarwinLocalProduction(options, {sourceRoot = resolve(repository), node = process.execPath} = {}) {
  assert(options && typeof options === 'object' && !Array.isArray(options));
  const allowed = ['sourceSha', 'packageVersion', 'outputDirectory', 'clang', 'sdk', 'sqliteArchive',
    'opensslSourceArchive', 'componentSeconds', 'compileSeconds', 'modelHttpPreparation'];
  assert(Object.keys(options).every(key => allowed.includes(key)), 'Unknown Darwin production selection');
  const {sourceSha, outputDirectory, clang, sdk, sqliteArchive, opensslSourceArchive,
    componentSeconds = 900, compileSeconds = 1800, modelHttpPreparation} = options;
  assert.match(sourceSha, /^[a-f0-9]{40}$/u);
  const packageVersion = nativePackageVersion(options.packageVersion);
  for (const [label, value] of Object.entries({sourceRoot, node, outputDirectory, clang, sdk, sqliteArchive, opensslSourceArchive})) absolute(value, label);
  assert(!inside(outputDirectory, sourceRoot) && !inside(sourceRoot, outputDirectory), 'Output must be outside the source checkout');
  const inputs = [clang, sdk, sqliteArchive, opensslSourceArchive];
  const modelSelection = [];
  if (modelHttpPreparation !== undefined) {
    absolute(modelHttpPreparation, 'Model HTTP preparation');
    inputs.push(modelHttpPreparation);
    modelSelection.push('--model-http-preparation', modelHttpPreparation);
  }
  assert.equal(new Set(inputs).size, inputs.length, 'Compiler, SDK and archives must be distinct');
  assert(inputs.every(value => !inside(value, outputDirectory)), 'Original inputs cannot be inside fresh output');
  assert(Number.isSafeInteger(componentSeconds) && componentSeconds > 0 && componentSeconds <= 1800,
    'componentSeconds must be an integer from 1 to 1800');
  const budget = nativeCliCompileBudget(compileSeconds, true);
  const directories = Object.fromEntries(['sqlite', 'crypto', 'recipe', 'artifact', 'include'].map(name => [name, join(outputDirectory, name)]));
  directories.cryptoSource = directories.crypto;
  directories.crypto = join(directories.cryptoSource, 'component');
  const step = (phase, command, args, timeoutMs) => ({phase, command, args, timeoutMs});
  return {sourceSha, packageVersion, outputDirectory, clang, sdk, sqliteArchive, opensslSourceArchive,
    modelHttpPreparation, sourceRoot, directories,
    commands: [
      step('sqlite', 'python3', [join(sourceRoot, 'scripts/produce-python-sqlite-component.py'),
        '--source', sourceSha, '--archive', sqliteArchive, '--process-provider', '--process-target', 'darwin-arm64',
        '--clang', clang, '--sdk', sdk, '--destination', directories.sqlite, '--seconds', String(componentSeconds)], componentSeconds * 1000),
      step('crypto', 'python3', [join(sourceRoot, 'scripts/produce-native-crypto-component.py'),
        '--output', directories.cryptoSource, '--target', 'darwin-arm64', '--clang', clang, '--sdk', sdk,
        '--static-profile', 'source-macos11', '--source-archive', opensslSourceArchive,
        '--seconds', String(componentSeconds)], componentSeconds * 1000),
      step('recipe', node, [join(sourceRoot, 'scripts/native-cli-local-recipe.mjs'),
        '--source', sourceSha, '--platform', 'darwin-arm64', '--sqlite-component', directories.sqlite,
        '--crypto-component', directories.crypto, '--output', directories.recipe, ...modelSelection], 120000),
      step('artifact', node, [join(sourceRoot, 'scripts/native-cli-artifact.mjs'), directories.artifact,
        '--local-runtime-recipe', join(directories.recipe, 'local-runtime-recipe.json'),
        '--package-version', packageVersion, '--compile-seconds', String(budget.seconds)], budget.timeoutMs + 120000),
    ]};
}

export function requireNativeDarwinLocalComponentSelection(plan, {sqlite, crypto}, inputs) {
  assert.equal(sqlite.source_sha, plan.sourceSha); assert.equal(crypto.source, plan.sourceSha);
  for (const receipt of [sqlite, crypto]) {
    assert.equal(receipt.target, 'aarch64-apple-darwin');
    for (const selected of [plan.clang, join(plan.sdk, 'SDKSettings.json')]) {
      assert(inputs[selected], 'Original compiler/SDK identity required');
      assert.deepEqual(receipt.inputs?.[selected], inputs[selected], 'Selected original compiler/SDK mismatch');
    }
  }
  assert(inputs[plan.sqliteArchive] && inputs[plan.opensslSourceArchive], 'Original archives required');
  assert.deepEqual(sqlite.inputs?.[plan.sqliteArchive], inputs[plan.sqliteArchive], 'Selected SQLite archive mismatch');
  assert.equal(sqlite.loaded, false); assert.equal(sqlite.initialized, false);
  assert.equal(crypto.static_source?.source, plan.sourceSha, 'Original source-built Crypto required');
  assert.equal(crypto.static_source?.target, 'aarch64-apple-darwin');
  assert.deepEqual(crypto.static_source?.inputs?.[plan.opensslSourceArchive], inputs[plan.opensslSourceArchive],
    'Selected OpenSSL source archive mismatch');
}

export function requireNativeDarwinLocalArtifact(record, plan) {
  assert.equal(record.sourceSha, plan.sourceSha); assert.equal(record.platform, 'darwin-arm64');
  assert(record.localRuntime && typeof record.localRuntime === 'object', 'Darwin production requires original Local metadata');
  assert.equal(record.abi?.format, 'Mach-O');
  return requireNativePackageVersion(record, plan.packageVersion);
}

export async function produceNativeCliDarwinLocal(options, {execute = execFileSync, sourceRoot = resolve(repository), host = process} = {}) {
  const plan = planNativeDarwinLocalProduction(options, {sourceRoot});
  assert.equal(host.platform, 'darwin'); assert.equal(host.arch, 'arm64');
  const environment = {...process.env};
  for (const name of ['CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET']) delete environment[name];
  assert(environment.MOON_HOME && isAbsolute(environment.MOON_HOME), 'Select the pinned Darwin toolchain');
  const query = (command, args) => execute(command, args, {cwd: sourceRoot, env: environment,
    encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024}).trim();
  const clean = () => {
    assert.equal(query('git', ['rev-parse', 'HEAD']), plan.sourceSha, 'Exact current source required');
    assert.equal(query('git', ['status', '--porcelain', '--untracked-files=all']), '', 'Clean committed source required');
  };
  clean();
  assert.equal(realpathSync(dirname(plan.outputDirectory)), dirname(plan.outputDirectory), 'Original output parent required');
  try {lstatSync(plan.outputDirectory); assert.fail('Fresh output required');} catch (error) {if (error.code !== 'ENOENT') throw error;}
  assert.equal(realpathSync(plan.clang), plan.clang); accessSync(plan.clang, constants.X_OK);
  assert.equal(realpathSync(plan.sdk), plan.sdk);
  const selections = [[plan.clang, 512 * 1024 * 1024], [join(plan.sdk, 'SDKSettings.json'), 1024 * 1024],
    [plan.sqliteArchive, 5 * 1024 * 1024], [plan.opensslSourceArchive, 128 * 1024 * 1024],
    [join(sourceRoot, 'packages/python-local-runtime/native/sqlite-component/source.json'), 65536]];
  if (plan.modelHttpPreparation !== undefined) selections.push([plan.modelHttpPreparation, 32 * 1024 * 1024]);
  const inputs = Object.fromEntries(selections.map(([file, maximum]) => [file, original(file, maximum).identity]));
  const checkInputs = () => {for (const [file, maximum] of selections) assert.deepEqual(original(file, maximum).identity, inputs[file]);};
  const checkTools = () => {
    assert.equal(realpathSync(query('xcrun', ['--find', 'clang'])), plan.clang, 'Native producer must select the original compiler');
    assert.equal(realpathSync(query('xcrun', ['--show-sdk-path'])), plan.sdk, 'Native producer must select the original SDK');
  };
  checkTools();
  mkdirSync(plan.outputDirectory, {mode: 0o700});
  const json = file => JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(original(file, 8 * 1024 * 1024, true).raw));
  let header;
  for (const step of plan.commands) {
    clean(); checkInputs(); checkTools();
    if (step.phase === 'recipe') {
      requireNativeDarwinLocalComponentSelection(plan, {sqlite: json(join(plan.directories.sqlite, 'process-producer.json')),
        crypto: json(join(plan.directories.crypto, 'producer.json'))}, inputs);
      const staged = original(join(plan.directories.sqlite, 'source/sqlite3.h'), 16 * 1024 * 1024, true);
      header = requireNativeLocalHeader(staged.raw, json(join(plan.directories.sqlite, 'process-producer.json')),
        json(join(sourceRoot, 'packages/python-local-runtime/native/sqlite-component/source.json')));
      mkdirSync(plan.directories.include);
      writeFileSync(join(plan.directories.include, 'sqlite3.h'), staged.raw, {flag: 'wx', mode: 0o444});
    }
    if (step.phase === 'artifact') {
      assert(header); assert.deepEqual(original(join(plan.directories.include, 'sqlite3.h'), 16 * 1024 * 1024).identity, header);
      assert.deepEqual(original(join(plan.directories.sqlite, 'source/sqlite3.h'), 16 * 1024 * 1024).identity, header);
    }
    execute(step.command, step.args, {cwd: sourceRoot, env: {...environment,
      ...(step.phase === 'artifact' ? {C_INCLUDE_PATH: plan.directories.include} : {})}, timeout: step.timeoutMs, stdio: 'inherit'});
  }
  clean(); checkInputs(); checkTools();
  assert.deepEqual(original(join(plan.directories.include, 'sqlite3.h'), 16 * 1024 * 1024).identity, header);
  const artifact = requireNativeDarwinLocalArtifact(await admitNativeArtifact(plan.directories.artifact, plan.sourceSha), plan);
  return {directory: plan.directories.artifact, artifact};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = await produceNativeCliDarwinLocal(parseNativeDarwinLocalArguments(process.argv.slice(2)));
    console.log(JSON.stringify({directory: result.directory, sourceSha: result.artifact.sourceSha,
      platform: result.artifact.platform, packageVersion: result.artifact.packageVersion, localRuntime: result.artifact.localRuntime}, null, 2));
  } catch (error) {console.error(error.message); process.exitCode = 1;}
}
