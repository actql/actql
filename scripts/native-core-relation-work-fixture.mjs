// Current-source setup for one strict Native Core relation case. Components
// come from the existing CI producer; the Common emitter only constructs data.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {closeSync, fstatSync, ftruncateSync, lstatSync, openSync, readdirSync, realpathSync} from 'node:fs';
import {mkdir, writeFile} from 'node:fs/promises';
import {basename, dirname, isAbsolute, join} from 'node:path';
import {localRuntimeHash} from '../packages/native-cli/lib/local-runtime.mjs';
import {inspectLocalLibrary} from './native-cli-local-runtime.mjs';
import {verifyOriginal} from './native-preparation-originals.mjs';
import {prepareNativeOriginalRelationFixture, prepareNativeRelationRefusalInputs,
  relationFixtureOriginal} from './native-original-relation-runtime-fixture.mjs';

const roles = ['environment', 'registry', 'values', 'fragment', 'ordered', 'result-policy'];
const platforms = {'linux-x64': 'linux-x64-gnu', 'darwin-arm64': 'darwin-arm64'};
const emitterKeys = ['ACTQL_TEST_NATIVE_RELATION_ENVIRONMENT_OUTPUT',
  'ACTQL_TEST_NATIVE_RELATION_BASELINE_ASSETS_OUTPUT', 'ACTQL_TEST_NATIVE_RELATION_CONFIGURATION_INPUTS'];
export const nativeRelationWorkBackingBytes = 768 * 1024 ** 2;
export const nativeRelationWorkModes = Object.freeze(['positive', 'run-only',
  'wrong-connection', 'wrong-resource', 'short-capacity', 'foreign-declaration', 'wrong-selection']);

// These last three refusals are made by the actual Native owner, not by
// malformed configuration. Preserve the ordinary canonical setup bytes.
export function nativeRelationWorkInputVariant(mode) {
  assert(nativeRelationWorkModes.includes(mode), 'Unknown Native relation Work mode');
  return ['run-only', 'wrong-connection', 'wrong-resource'].includes(mode) ? mode : 'positive';
}

export function verifyNativeRelationProducerInputs(receipt) {
  assert(receipt.inputs && Object.keys(receipt.inputs).length > 0);
  if (receipt.static_source) {
    assert.equal(receipt.static_source.source, receipt.source);
    assert.equal(receipt.static_source.target, receipt.target);
    // The existing source producer incorporates the upstream compiled census
    // into its original input inventory. Do not omit those nested inputs.
    for (const inventory of [receipt.static_source.inputs, receipt.static_source.compiled_inputs]) {
      assert(inventory && Object.keys(inventory).length > 0);
      for (const [path, identity] of Object.entries(inventory))
        assert.deepEqual(receipt.inputs[path], identity);
    }
  }
  for (const [path, identity] of Object.entries(receipt.inputs)) {
    if (identity.resolved_path !== undefined) assert.equal(realpathSync(path), identity.resolved_path);
    verifyOriginal({path: identity.resolved_path ?? path, bytes: identity.bytes, sha256: identity.sha256});
  }
}

// Closed metadata selection only; physical originals and ABI observations are
// still checked below and by the existing runtime producer.
export function selectNativeRelationBundle(bundle, components, source, target) {
  assert.match(source, /^[a-f0-9]{40}$/u);
  assert(platforms[target], 'Actual supported Core component target required');
  assert.equal(bundle.source, source, 'Relation fixture requires current component source');
  assert.equal(bundle.target, target, 'Relation fixture requires the actual component target');
  assert.equal(bundle.providers, 0); assert.equal(bundle.loaded, false); assert.equal(bundle.initialized, false);
  assert(isAbsolute(components.sqliteLibrary) && isAbsolute(components.cryptoLibrary));
  const directory = dirname(dirname(components.sqliteLibrary));
  for (const role of ['sqlite', 'crypto']) {
    const library = components[`${role}Library`], item = bundle[role];
    assert.equal(item.path, library);
    assert.equal(dirname(library), join(directory, role));
    assert.equal(basename(library), `libactql_${role}_component.${target === 'darwin-arm64' ? 'dylib' : 'so'}`);
    assert.equal(bundle.producer_receipts[role].path,
      join(directory, role, role === 'sqlite' ? 'process-producer.json' : 'producer.json'));
    assert(Number.isSafeInteger(item.bytes) && item.bytes > 0 && item.bytes <= 64 * 1024 ** 2);
    assert.match(item.sha256, /^[a-f0-9]{64}$/u);
  }
  return {directory, platform: platforms[target]};
}

export function runNativeRelationInputEmitter(repository, targetDirectory, outputs, env, execute, seconds) {
  assert(Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 900);
  assert(isAbsolute(repository) && isAbsolute(targetDirectory));
  assert(Object.keys(outputs).length > 0 && Object.keys(outputs).every(key => emitterKeys.includes(key)));
  assert(Object.values(outputs).every(isAbsolute));
  const selectedEnv = {...env};
  for (const key of emitterKeys) delete selectedEnv[key];
  // Fresh setup must not silently select a separate diagnostic input root.
  delete selectedEnv.ACTQL_TEST_NATIVE_RELATION_AUDIT_ROOT;
  Object.assign(selectedEnv, outputs);
  const args = ['--target', 'js', '-j', '2', '--target-dir', targetDirectory,
    'src/native_relation_fixture_inputs'];
  execute(process.execPath, ['--input-type=module', '-e',
    "import {runFocusedTests} from './scripts/test-execution.mjs'; " +
    "process.exitCode = runFocusedTests('moon', " + JSON.stringify(args) +
    ', {timeout: ' + seconds * 1000 + ', expectedTests: 3});'],
  {cwd: repository, env: selectedEnv, encoding: 'utf8', timeout: (seconds + 10) * 1000,
    maxBuffer: 8 * 1024 ** 2});
}

export async function prepareNativeCoreRelationRuntime(repository, destination, components, {
  env = process.env, execute = execFileSync, seconds = 300,
  platform = process.platform, arch = process.arch,
} = {}) {
  assert(Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 900);
  assert(isAbsolute(destination));
  repository = realpathSync(repository);
  const target = platform === 'darwin' && arch === 'arm64' ? 'darwin-arm64'
    : platform === 'linux' && arch === 'x64' ? 'linux-x64' : undefined;
  assert(target, 'No current Core relation component producer for this platform');
  const git = args => execute('git', args, {cwd: repository, env, encoding: 'utf8',
    timeout: 15000, maxBuffer: 1024 * 1024});
  const source = git(['rev-parse', 'HEAD']).trim();
  assert.equal(git(['status', '--porcelain']), '', 'Current clean Core relation fixture source required');
  const bundlePath = join(dirname(dirname(components.sqliteLibrary)), 'bundle-components.json');
  const observedBundle = relationFixtureOriginal(bundlePath, 65536);
  const bundle = JSON.parse(observedBundle.body);
  const selected = selectNativeRelationBundle(bundle, components, source, target);
  const receipts = {};
  for (const role of ['sqlite', 'crypto']) {
    relationFixtureOriginal(bundle[role].path, 64 * 1024 ** 2, bundle[role]);
    const original = bundle.producer_receipts[role];
    receipts[role] = JSON.parse(relationFixtureOriginal(original.path, 32 * 1024 * 1024, original).body);
    assert.equal(role === 'sqlite' ? receipts[role].source_sha : receipts[role].source, source);
    assert.deepEqual(receipts[role].library, {bytes: bundle[role].bytes, sha256: bundle[role].sha256});
    verifyNativeRelationProducerInputs(receipts[role]);
  }
  await mkdir(destination, {mode: 0o700});
  assert.equal(lstatSync(destination).mode & 0o777, 0o700);
  const environmentPath = join(destination, 'source-environment.json');
  const baselinePath = join(destination, 'baseline-assets.json');
  const targetDirectory = join(destination, 'common-input-target');
  runNativeRelationInputEmitter(repository, targetDirectory, {
    ACTQL_TEST_NATIVE_RELATION_ENVIRONMENT_OUTPUT: environmentPath,
    ACTQL_TEST_NATIVE_RELATION_BASELINE_ASSETS_OUTPUT: baselinePath,
  }, env, execute, seconds);
  const baseline = JSON.parse(relationFixtureOriginal(baselinePath, 65536).body);
  assert(Array.isArray(baseline) && baseline.length === roles.length && baseline.every(item => typeof item === 'string'));
  const write = async (name, body) => {
    const path = join(destination, name);
    await writeFile(path, body, {flag: 'wx', mode: 0o600});
    return relationFixtureOriginal(path).original;
  };
  const assets = [];
  for (const [index, role] of roles.entries()) assets.push({role,
    original: await write(`${role}.json`, baseline[index])});
  const sqliteNotice = relationFixtureOriginal(join(selected.directory, 'sqlite/SQLITE-NOTICE'),
    1024 * 1024, receipts.sqlite.notice);
  const cryptoRecipePath = join(repository, 'packages/python-local-runtime/native/crypto-component/source.json');
  const cryptoRecipe = JSON.parse(relationFixtureOriginal(cryptoRecipePath, 65536, receipts.crypto.recipe).body);
  const copyright = target === 'darwin-arm64'
    ? relationFixtureOriginal(join(selected.directory, 'crypto/OPENSSL-LICENSE.txt'), 1024 * 1024, receipts.crypto.license)
    : relationFixtureOriginal(join(selected.directory, 'crypto/OPENSSL-COPYRIGHT'), 1024 * 1024,
      cryptoRecipe.source_targets['x86_64-unknown-linux-gnu'].license);
  const cryptoNotice = relationFixtureOriginal(join(selected.directory, 'crypto/CRYPTO-NOTICE'),
    1024 * 1024, cryptoRecipe.local.NOTICE);
  const licenses = [{name: 'sqlite.txt', original: await write('sqlite.txt', sqliteNotice.body)},
    {name: 'crypto.txt', original: await write('crypto.txt', Buffer.concat([cryptoNotice.body, Buffer.from('\n'), copyright.body]))}];
  const names = new Set(['sqlite', 'crypto'].map(role => basename(bundle[role].path)));
  const libraries = ['sqlite', 'crypto'].map(role => ({role, name: basename(bundle[role].path),
    original: {path: bundle[role].path, bytes: bundle[role].bytes, sha256: bundle[role].sha256},
    license: `${role}.txt`, dependencies: inspectLocalLibrary(bundle[role].path, selected.platform, names, execute).dependencies}));
  const recipe = {sourceSha: source, platform: selected.platform, libraries, assets, licenses};
  const recipeOriginal = await write('local-runtime-recipe.json', JSON.stringify(recipe, null, 2) + '\n');
  assert.equal(git(['rev-parse', 'HEAD']).trim(), source);
  assert.equal(git(['status', '--porcelain']), '');
  return {repository, source, platform: selected.platform, recipePath: recipeOriginal.path,
    sqliteReceiptPath: bundle.producer_receipts.sqlite.path, cryptoReceiptPath: bundle.producer_receipts.crypto.path,
    originalCheckoutRoot: repository, environmentPath, targetDirectory, env, execute, seconds};
}

export async function nativeRelationOriginalWorkFixture(namespace, prepared, {mode = 'positive'} = {}) {
  const inputVariant = nativeRelationWorkInputVariant(mode);
  assert(isAbsolute(namespace));
  const original = lstatSync(namespace);
  assert(original.isDirectory() && !original.isSymbolicLink() && (original.mode & 0o777) === 0o700);
  assert.deepEqual(readdirSync(namespace), [], 'The external case namespace must be fresh');
  const directory = join(realpathSync(namespace), 'relation-original');
  const receipt = await prepareNativeOriginalRelationFixture({...prepared, directory, checkoutRoot: prepared.repository});
  assert.equal(receipt.sourceSha, prepared.source);
  assert.equal(receipt.platform, prepared.platform);
  runNativeRelationInputEmitter(prepared.repository, prepared.targetDirectory, {
    ACTQL_TEST_NATIVE_RELATION_CONFIGURATION_INPUTS: join(directory, 'configuration-inputs.json'),
  }, prepared.env, prepared.execute, prepared.seconds);
  const refusals = inputVariant === 'positive' ? null : await prepareNativeRelationRefusalInputs(directory);
  const inputRoot = inputVariant === 'positive' ? receipt.inputRoot : refusals[inputVariant];
  provisionNativeRelationBacking(inputRoot);
  const result = {
    ACTQL_TEST_RELATION_ORIGINAL_ROOT: inputRoot,
    ACTQL_TEST_RELATION_RUNTIME_ROOT: receipt.runtime.root,
    ACTQL_TEST_RELATION_RUNTIME_SOURCE: receipt.sourceSha,
    ACTQL_TEST_RELATION_RUNTIME_PLATFORM: receipt.platform,
    ACTQL_TEST_RELATION_RUNTIME_DIGEST: receipt.runtime.metadata.sha256,
    ACTQL_TEST_RELATION_ORIGINAL_MODE: mode,
  };
  await writeFile(join(directory, 'core-input-receipt.json'), JSON.stringify({
    scope: 'test setup only; no Native execution or installed product claim',
    runtime: receipt.runtime, sourceSha: prepared.source, environment: result,
    backingBytes: nativeRelationWorkBackingBytes,
    runtimeManifestSha256: localRuntimeHash(relationFixtureOriginal(join(receipt.runtime.root, 'local-runtime.json')).body),
  }, null, 2) + '\n', {flag: 'wx', mode: 0o600});
  return result;
}

export function provisionNativeRelationBacking(inputRoot) {
  assert(isAbsolute(inputRoot));
  const selected = lstatSync(inputRoot);
  assert(selected.isDirectory() && !selected.isSymbolicLink() && (selected.mode & 0o777) === 0o700);
  assert.deepEqual(readdirSync(inputRoot).sort(), ['account.json', 'environment.json',
    'records.json', 'row-declaration.json', 'run.json', 'runtime.json']);
  const fd = openSync(join(inputRoot, 'backing'), 'wx', 0o600);
  try {
    ftruncateSync(fd, nativeRelationWorkBackingBytes);
    const observed = fstatSync(fd);
    assert(observed.isFile() && observed.nlink === 1);
    assert.equal(observed.mode & 0o777, 0o600);
    assert.equal(observed.size, nativeRelationWorkBackingBytes);
  } finally { closeSync(fd); }
}
