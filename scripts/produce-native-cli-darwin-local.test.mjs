import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHash} from 'node:crypto';
import {parseNativeDarwinLocalArguments, planNativeDarwinLocalProduction, produceNativeCliDarwinLocal,
  requireNativeDarwinLocalComponentSelection, requireNativeDarwinLocalArtifact} from './produce-native-cli-darwin-local.mjs';

const sourceSha = 'a'.repeat(40);
const options = {sourceSha, packageVersion: '0.0.2', outputDirectory: '/output/new',
  clang: '/tools/clang', sdk: '/SDK', sqliteArchive: '/inputs/sqlite.zip', opensslSourceArchive: '/inputs/openssl.tar.gz'};
const context = {sourceRoot: '/source', node: '/tools/node'};
const args = ['--source', sourceSha, '--package-version', '0.0.2', '--output', '/output/new',
  '--clang', '/tools/clang', '--sdk', '/SDK', '--sqlite-archive', '/inputs/sqlite.zip',
  '--openssl-source-archive', '/inputs/openssl.tar.gz'];
const identity = text => ({bytes: Buffer.byteLength(text), sha256: createHash('sha256').update(text).digest('hex')});

test('Darwin producer passes a selected Remote HTTP receipt only to the existing recipe command', () => {
  const remoteHttpPreparation = '/inputs/remote-http/preparation.json';
  const selection = ['--remote-http-preparation', remoteHttpPreparation];
  const selected = parseNativeDarwinLocalArguments([...args, ...selection]);
  assert.equal(selected.remoteHttpPreparation, remoteHttpPreparation);
  const baseline = planNativeDarwinLocalProduction(options, context);
  const remote = planNativeDarwinLocalProduction(selected, context);
  assert.deepEqual(remote.commands.filter(step => step.phase !== 'recipe'),
    baseline.commands.filter(step => step.phase !== 'recipe'));
  assert.deepEqual(remote.commands.find(step => step.phase === 'recipe').args.slice(-2), selection);
  for (const invalid of ['relative/preparation.json', '/output/new/preparation.json', options.sqliteArchive]) {
    assert.throws(() => planNativeDarwinLocalProduction({...selected, remoteHttpPreparation: invalid}, context));
  }
});

test('Darwin producer selects existing same-process and source-built owners with an explicit final version', () => {
  const plan = planNativeDarwinLocalProduction(options, context);
  assert.equal(plan.sourceSha, sourceSha); assert.equal(plan.packageVersion, '0.0.2');
  assert.deepEqual(plan.commands.map(s => s.phase), ['sqlite', 'crypto', 'recipe', 'artifact']);
  const sqlite = plan.commands[0], crypto = plan.commands[1], recipe = plan.commands[2], artifact = plan.commands[3];
  assert.equal(sqlite.args[0], '/source/scripts/produce-python-sqlite-component.py');
  assert(sqlite.args.includes('--process-provider')); assert.equal(sqlite.args[sqlite.args.indexOf('--process-target') + 1], 'darwin-arm64');
  assert.equal(sqlite.args[sqlite.args.indexOf('--sdk') + 1], '/SDK');
  assert(!sqlite.args.includes('--provider-receipt'));
  assert.equal(crypto.args[0], '/source/scripts/produce-native-crypto-component.py');
  assert.equal(crypto.args[crypto.args.indexOf('--static-profile') + 1], 'source-macos11');
  assert.equal(crypto.args[crypto.args.indexOf('--source-archive') + 1], '/inputs/openssl.tar.gz');
  assert(!crypto.args.includes('--openssl-prefix')); assert(!crypto.args.includes('--openssl-package-archive'));
  assert.equal(plan.directories.cryptoSource, '/output/new/crypto');
  assert.equal(plan.directories.crypto, '/output/new/crypto/component');
  assert.equal(recipe.args[recipe.args.indexOf('--crypto-component') + 1], plan.directories.crypto);
  assert.equal(recipe.args[recipe.args.indexOf('--platform') + 1], 'darwin-arm64');
  assert.equal(artifact.args[artifact.args.indexOf('--package-version') + 1], '0.0.2');
  assert.equal(artifact.args[artifact.args.indexOf('--local-runtime-recipe') + 1], '/output/new/recipe/local-runtime-recipe.json');
  assert.equal(artifact.args[artifact.args.indexOf('--compile-seconds') + 1], '1800');
  assert.equal(artifact.timeoutMs, 1950000);
  assert.deepEqual(parseNativeDarwinLocalArguments(args), options);
});

test('Darwin selection refuses implicit versions, foreign platforms, ambiguous inputs and unbounded preparation', () => {
  for (const key of ['sourceSha', 'packageVersion', 'outputDirectory', 'clang', 'sdk', 'sqliteArchive', 'opensslSourceArchive']) {
    const selected = {...options}; delete selected[key];
    assert.throws(() => planNativeDarwinLocalProduction(selected, context));
  }
  for (const patch of [
    {sourceSha: 'a'.repeat(39)}, {packageVersion: 'latest'}, {packageVersion: '0.0.2+local'},
    {clang: 'clang'}, {sdk: '/tools/../SDK'}, {sdk: '/tools/clang'},
    {outputDirectory: '/source/child'}, {outputDirectory: '/'}, {outputDirectory: '/output/a:b'},
    {sqliteArchive: '/output/new/sqlite.zip'}, {opensslSourceArchive: '/inputs/sqlite.zip'},
    {opensslPrefix: '/opt/homebrew'}, {platform: 'linux-x64-gnu'}, {providerReceipt: '/old/provider'},
    {completedLocalProvider: true}, {componentSeconds: 1801}, {compileSeconds: 86401},
  ]) assert.throws(() => planNativeDarwinLocalProduction({...options, ...patch}, context));
  for (const key of ['componentSeconds', 'compileSeconds']) for (const value of [0, -1, false, null, '900', NaN, Infinity, 1.5])
    assert.throws(() => planNativeDarwinLocalProduction({...options, [key]: value}, context));
  for (const suffix of [['--source', sourceSha], ['--unknown', 'yes'], ['--component-seconds', '1e3'], ['--sdk']])
    assert.throws(() => parseNativeDarwinLocalArguments([...args, ...suffix]));
  const bounded = planNativeDarwinLocalProduction({...options, componentSeconds: 60, compileSeconds: 300}, context);
  assert.equal(bounded.commands[0].timeoutMs, 60000); assert.equal(bounded.commands[1].timeoutMs, 60000);
  assert.equal(bounded.commands[3].timeoutMs, 450000);
});

// These are closed selection DATA, not fabricated components or runtime proof.
function selectedInputs() {
  const inputs = Object.fromEntries(['/tools/clang', '/SDK/SDKSettings.json', '/inputs/sqlite.zip', '/inputs/openssl.tar.gz']
    .map(file => [file, identity(file)]));
  const shared = {'/tools/clang': inputs['/tools/clang'], '/SDK/SDKSettings.json': inputs['/SDK/SDKSettings.json']};
  return {inputs, sqlite: {source_sha: sourceSha, target: 'aarch64-apple-darwin', loaded: false, initialized: false,
    inputs: {...shared, '/inputs/sqlite.zip': inputs['/inputs/sqlite.zip']}},
  crypto: {source: sourceSha, target: 'aarch64-apple-darwin', inputs: shared,
    static_source: {source: sourceSha, target: 'aarch64-apple-darwin', inputs: {'/inputs/openssl.tar.gz': inputs['/inputs/openssl.tar.gz']}}}};
}

test('completed component selection binds both archives, compiler, SDK and the same immutable source', () => {
  const plan = planNativeDarwinLocalProduction(options, context), good = selectedInputs();
  requireNativeDarwinLocalComponentSelection(plan, good, good.inputs);
  for (const mutate of [
    f => {f.sqlite.source_sha = 'b'.repeat(40);}, f => {f.crypto.source = 'b'.repeat(40);},
    f => {f.sqlite.target = 'x86_64-unknown-linux-gnu';}, f => {f.crypto.target = 'x86_64-unknown-linux-gnu';},
    f => {f.sqlite.loaded = true;}, f => {f.sqlite.initialized = true;},
    f => {delete f.sqlite.inputs['/tools/clang'];}, f => {delete f.crypto.inputs['/SDK/SDKSettings.json'];},
    f => {f.sqlite.inputs['/inputs/sqlite.zip'] = identity('foreign archive');},
    f => {delete f.crypto.static_source;}, f => {f.crypto.static_source.source = 'b'.repeat(40);},
    f => {f.crypto.static_source.inputs['/inputs/openssl.tar.gz'] = identity('foreign OpenSSL');},
  ]) {
    const f = structuredClone(selectedInputs()); mutate(f);
    assert.throws(() => requireNativeDarwinLocalComponentSelection(plan, f, good.inputs));
  }
  assert.throws(() => requireNativeDarwinLocalComponentSelection(plan, good, {}));
});

test('only an admitted Local Darwin image with the exact compiled banner can complete the route', () => {
  const plan = planNativeDarwinLocalProduction(options, context);
  const record = {sourceSha, platform: 'darwin-arm64', localRuntime: {path: 'local-runtime.json'},
    abi: {format: 'Mach-O'}, packageVersion: '0.0.2', binarySha256: 'b'.repeat(64), binaryBytes: 1,
    packageVersionObservation: {argv: ['--version'], stdout: '0.0.2\n', code: 0, signal: null,
      binarySha256: 'b'.repeat(64), binaryBytes: 1, buildInputSha256: 'c'.repeat(64)}};
  assert.equal(requireNativeDarwinLocalArtifact(record, plan), record);
  for (const patch of [{sourceSha: 'b'.repeat(40)}, {platform: 'linux-x64-gnu'}, {localRuntime: null},
    {abi: {format: 'ELF'}}, {packageVersion: '0.0.2-rc.0'}, {packageVersionObservation: undefined}])
    assert.throws(() => requireNativeDarwinLocalArtifact({...record, ...patch}, plan));
});

test('the Darwin route refuses a foreign actual host before invoking any original owner', async () => {
  const calls = [];
  await assert.rejects(produceNativeCliDarwinLocal(options, {sourceRoot: '/source', host: {platform: 'linux', arch: 'x64'},
    execute(...values) {calls.push(values); throw Error('Owner must not be invoked');}}));
  assert.deepEqual(calls, []);
});
