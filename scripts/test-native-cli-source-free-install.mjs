// Actual fixed-cohort global installation and source-free Local execution.
// Mock bindings, live Connectors, approval and public-registry publication are
// separate acceptance subjects. No repository runtime or Node Host is loaded.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {lstat, mkdir, readFile, readdir, writeFile, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {platformKey} from '../packages/native-cli/bin/actql.mjs';
import {checkoutState} from './packed-client-packages.mjs';
import {verifyNativeCliRelease} from './native-cli-release.mjs';
import {createOwnedScratch} from './owned-scratch.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
// Registry close permits provisional observations only. The consumer must still
// exit and complete owned-scratch cleanup before the parent can publish success.
export async function finishSourceFreeObservations(receipt, primaryFailure,
  {close, saveObserved, saveFailed}) {
  let failure = primaryFailure;
  try { await close(); }
  catch (error) {
    failure = failure === undefined ? error
      : new AggregateError([failure, error], 'Source-free acceptance and registry cleanup failed');
  }
  if (failure !== undefined) {
    try { await saveFailed(failure); }
    catch (error) { throw new AggregateError([failure, error], 'Source-free failure evidence could not be saved'); }
    throw failure;
  }
  assert(receipt, 'Completed source-free observations required');
  await saveObserved({...receipt, status: 'observed', registryClosed: true});
}

const unsupportedBindings = 'actql: The installed Native runtime does not implement the selected project bindings; no project files were created.\n';

async function unchangedDirectory(path) {
  const state = await lstat(path, {bigint: true});
  assert(state.isDirectory() && !state.isSymbolicLink());
  return {entries: (await readdir(path)).sort(), ...Object.fromEntries(
    ['dev', 'ino', 'mode', 'mtimeNs', 'ctimeNs'].map(key => [key, String(state[key])]))};
}

async function requireAbsent(path) {
  try { await lstat(path); assert.fail(`Unexpected initialized target: ${path}`); }
  catch (error) {if (error.code !== 'ENOENT') throw error;}
}

// These are actual installed refusals, not execution evidence for Mock bindings.
export async function observeUnsupportedMockInitialization({root, cli}) {
  const queryParent = join(root, 'query-no-write');
  await mkdir(queryParent, {mode: 0o700});
  const queryBefore = await unchangedDirectory(queryParent);
  const configuration = join(queryParent, 'actql.config.json'), state = join(queryParent, 'state');
  await requireAbsent(configuration); await requireAbsent(state);
  const query = await cli(['--config', configuration, '--state-dir', state, 'project-init-support'], queryParent);
  assert.equal(query.code, 0); assert.equal(query.signal, null); assert.equal(query.stderr, '');
  await requireAbsent(configuration); await requireAbsent(state);
  const queryAfter = await unchangedDirectory(queryParent);
  assert.deepEqual(queryAfter, queryBefore);
  const support = JSON.parse(query.stdout);
  assert.deepEqual(support, {version: 'actql-project-init-support/0.1', sourceFree: true, mock: false});
  const cases = [];
  for (const template of ['deal-review-mock', 'churn-risk-mock']) {
    const parent = join(root, `refused-${template}`), empty = join(parent, 'empty');
    await mkdir(parent, {mode: 0o700}); await mkdir(empty, {mode: 0o700});
    const originalParent = await unchangedDirectory(parent), originalEmpty = await unchangedDirectory(empty);
    assert.deepEqual(originalParent.entries, ['empty']); assert.deepEqual(originalEmpty.entries, []);
    for (const targetState of ['new', 'empty']) for (let iteration = 1; iteration <= 2; iteration++) {
      const target = join(parent, targetState);
      if (targetState === 'new') await requireAbsent(target);
      const result = await cli(['init', '--template', template, targetState], parent, 69);
      assert.equal(result.code, 69); assert.equal(result.signal, null);
      assert.equal(result.stdout, ''); assert.equal(result.stderr, unsupportedBindings);
      if (targetState === 'new') await requireAbsent(target);
      const retainedParent = await unchangedDirectory(parent), retainedEmpty = await unchangedDirectory(empty);
      assert.deepEqual(retainedParent, originalParent); assert.deepEqual(retainedEmpty, originalEmpty);
      cases.push({template, targetState, iteration, target,
        parentBefore: originalParent, parentAfter: retainedParent,
        emptyBefore: originalEmpty, emptyAfter: retainedEmpty, newTargetAbsent: true});
    }
  }
  return {scope: 'unsupported-mock-initialization-refusal-only', support,
    query: {configuration, state, before: queryBefore, after: queryAfter}, cases};
}

export async function observeTimingEnabledPlainInitialization({root, cli, environment}) {
  const original = environment.ACTQL_NATIVE_TIMINGS;
  let result;
  try {
    environment.ACTQL_NATIVE_TIMINGS = '1';
    result = await cli(['init', 'project'], root);
  } finally {
    if (original === undefined) delete environment.ACTQL_NATIVE_TIMINGS;
    else environment.ACTQL_NATIVE_TIMINGS = original;
  }
  assert.equal(result.code, 0); assert.equal(result.signal, null);
  assert.match(result.stdout, /^Local Host adopted; no Run has been admitted\.\nAccount: local-cli\nAdoption: sha256:[a-f0-9]{64}\n$/u);
  const diagnostics = result.stderr.trimEnd().split('\n').map(line => {
    const match = /^(ACTQL_NATIVE_(?:TIMINGS|PHASE|COUNTER|LAUNCHER_TIMINGS)) (\{.*\})$/u.exec(line);
    assert(match, `Unexpected timing-enabled initialization diagnostic: ${line}`);
    return {marker: match[1], value: JSON.parse(match[2])};
  });
  const native = diagnostics.filter(value => value.marker === 'ACTQL_NATIVE_TIMINGS');
  const launcher = diagnostics.filter(value => value.marker === 'ACTQL_NATIVE_LAUNCHER_TIMINGS');
  assert.equal(native.length, 1); assert.equal(launcher.length, 1);
  assert.equal(native[0].value.origin, 'first_hook');
  assert.equal(native[0].value.child_process_counters, false);
  assert(Number.isSafeInteger(native[0].value.pid) && native[0].value.pid > 0);
  assert.equal(launcher[0].value.units, 'nanoseconds');
  for (const key of ['preparation', 'child', 'total']) assert(Number.isSafeInteger(launcher[0].value[key]) && launcher[0].value[key] >= 0);
  return {scope: 'plain-initialization-with-diagnostics', diagnostics};
}

async function observeInstalledSourceFree(input, observationPath) {
  const directory = resolve(input), manifest = await verifyNativeCliRelease(directory);
  const source = checkoutState(repository);
  assert(source.clean && source.revision === manifest.sourceSha, 'Exact clean fixed source required');
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
  const expected = manifest.artifacts.find(value => value.platform === platform);
  assert(expected?.localRuntime, 'Source-free installed acceptance requires a real Local runtime artifact');
  const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-source-free-install-',
    label: 'Native source-free Local external installation'});
  const root = scratch.path, prefix = join(root, 'global'), project = join(root, 'project'), records = [];
  const registry = await openReleaseTestRegistry([{directory, manifest}]);
  const env = {...process.env};
  for (const key of Object.keys(env)) if (/^npm_config_/iu.test(key) || /^(?:ACTQL_|DYLD_)/u.test(key) ||
    ['NODE_PATH', 'NODE_OPTIONS', 'LD_PRELOAD', 'LD_LIBRARY_PATH', 'MOON_HOME'].includes(key)) delete env[key];
  Object.assign(env, {HOME: join(root, 'home'), TMPDIR: join(root, 'tmp'),
    npm_config_registry: registry.url, npm_config_userconfig: join(root, 'npmrc'),
    npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_cache: join(root, 'cache'),
    npm_config_proxy: '', npm_config_https_proxy: '', npm_config_update_notifier: 'false',
    NO_PROXY: '127.0.0.1,localhost'});
  const execute = promisify(execFile);
  async function run(command, args, cwd = root, expectedCode = 0) {
    const started = Date.now();
    let result;
    try {
      result = {...await execute(command, args, {cwd, env, timeout: 180_000,
        killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024}), code: 0, signal: null};
    } catch (error) {
      result = {code: error.code ?? null, signal: error.signal ?? null,
        killed: error.killed ?? false, stdout: error.stdout ?? '', stderr: error.stderr ?? ''};
    }
    const record = {command, args, cwd, elapsedMs: Date.now() - started, ...result};
    records.push(record);
    await writeFile(join(root, 'commands.json'), `${JSON.stringify(records, null, 2)}\n`);
    assert.equal(record.code, expectedCode, `${command}: ${record.code}/${record.signal}\n${record.stdout}\n${record.stderr}`);
    assert.equal(record.signal, null);
    return record;
  }
  const rows = text => text.trim().split('\n').map(line => JSON.parse(line));
  let receipt, failure;
  try {
    for (const path of [prefix, env.HOME, env.TMPDIR, join(root, 'empty-path')]) await mkdir(path);
    await writeFile(join(root, 'npmrc'), `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
    await writeFile(join(root, 'npmrc-global'), '');
    await run('npm', ['install', '-g', '--prefix', prefix, '--ignore-scripts', '--no-audit', '--no-fund',
      `actql@${manifest.cohort.packageVersion}`]);
    const installed = join(prefix, 'lib/node_modules/actql'), launcher = join(prefix, 'bin/actql');
    assert.deepEqual((await readdir(join(installed, 'node_modules/@actql'))).sort(), [`cli-${platform}`]);
    const platformRoot = join(installed, 'node_modules/@actql', `cli-${platform}`);
    const artifact = JSON.parse(await readFile(join(platformRoot, 'artifact.json'), 'utf8'));
    assert.deepEqual(artifact, expected);
    const originalBinary = await readFile(join(platformRoot, 'bin/actql-native-client'));
    assert.equal(originalBinary.length, expected.binaryBytes);
    assert.equal(createHash('sha256').update(originalBinary).digest('hex'), expected.binarySha256);
    // Node launches only the installed npm entry. Neither it nor the Native child
    // can discover a compiler, a repository executable, a provider or a Node Host.
    env.PATH = join(root, 'empty-path');
    const cli = (args, cwd = project, code = 0) => run(process.execPath, [launcher, ...args], cwd, code);
    assert.equal((await cli(['--version'], root)).stdout, `${manifest.cohort.packageVersion}\n`);
    const mockInitialization = await observeUnsupportedMockInitialization({root, cli});
    const plainInitialization = await observeTimingEnabledPlainInitialization({root, cli, environment: env});
    assert.equal(env.ACTQL_NATIVE_TIMINGS, undefined);
    assert.equal(JSON.parse(await readFile(join(project, 'actql.config.json'))).profile, undefined);
    await writeFile(join(project, 'query.sql'), 'SELECT 1 AS id\n');
    const checked = JSON.parse((await cli(['check', 'query.sql', '--format', 'sql', '--json'])).stdout);
    assert.equal(checked.version, 'actql-check-outcome/0.1');
    assert.equal(checked.outcome, 'completed');
    assert.equal(checked.report.verdict, 'verified');
    assert.equal(checked.report.runnable.verdict, 'yes');
    const explained = JSON.parse((await cli(['explain', 'query.sql', '--format', 'sql', '--json'])).stdout);
    assert.equal(explained.version, 'actql-plan-view/0.1');
    assert.deepEqual(rows((await cli(['sql', 'SELECT 2 AS id', '--format', 'jsonl'])).stdout), [{id: 2}]);
    const state = JSON.parse((await cli(['run', 'query.sql', '--format', 'sql', '--json'])).stdout);
    assert.equal(state.version, 'actql-run-state/0.1');
    assert.equal(state.status, 'succeeded');
    assert.equal(typeof state.run_id, 'string'); assert(state.run_id.length > 0);
    // Subsequent processes must use retained Run/Result originals, not reexecute
    // the now-absent source file or manufacture a fresh successful Run.
    await unlink(join(project, 'query.sql'));
    for (let count = 0; count < 2; count++) {
      const saved = JSON.parse((await cli(['status', state.run_id, '--json'])).stdout);
      assert.equal(saved.run_id, state.run_id); assert.equal(saved.status, 'succeeded');
      assert.deepEqual(rows((await cli(['result', state.run_id, '--format', 'jsonl'])).stdout), [{id: 1}]);
    }
    await cli(['result', state.run_id, '--format', 'jsonl', '--output', 'saved.jsonl']);
    assert.deepEqual(rows(await readFile(join(project, 'saved.jsonl'), 'utf8')), [{id: 1}]);
    assert.deepEqual(await readFile(join(platformRoot, 'bin/actql-native-client')), originalBinary);
    assert.deepEqual(checkoutState(repository), source);
    receipt = {version: 'actql-native-cli-install-acceptance/0.1', scope: 'source-free-local',
      cliSourceSha: manifest.sourceSha, platform, node: process.version, glibc: glibc ?? null,
      artifact, scriptSha256: createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex'),
      cliPackages: manifest.packages.map(({name, version, sha256}) => ({name, version, sha256})),
      registry: 'private-loopback-fixed-RC', registryRequests: registry.requested,
      mockInitialization, plainInitialization,
      publicRegistryPublication: 'not-tested', records,
      unverified: ['Mock or live Connector bindings', 'Model inference', 'Effect approval', 'other platforms']};
  } catch (error) { failure = error; }
  await finishSourceFreeObservations(receipt, failure, {
    close: () => registry.close(),
    saveObserved: value => writeFile(observationPath,
      `${JSON.stringify({...value, consumer: root}, null, 2)}\n`, {flag: 'wx'}),
    saveFailed: error => writeFile(join(directory, `source-free-install-failed-${platform}-${Date.now()}.json`),
      `${JSON.stringify({version: 'actql-native-cli-install-acceptance/0.1', scope: 'source-free-local',
        cliSourceSha: manifest.sourceSha, platform, status: 'failed', error: error.message,
        failures: (error instanceof AggregateError ? error.errors : [error]).map(value => value.message),
        consumer: root, records}, null, 2)}\n`, {flag: 'wx'}),
  });
  scratch.passed();
}

// This parent has no owned-scratch exit handler. An observed receipt is not
// acceptance: the real child's exit status and original directory absence are
// both required. Tests exercise this same boundary with real child cleanup.
export async function runCleanupConditionedConsumer({command, args, observationPath,
  receiptPath, failurePath, expected, env = process.env, timeout = 600_000}) {
  let child, observation, failure;
  try {
    child = {...await promisify(execFile)(command, args, {env, timeout,
      killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024}), code: 0, signal: null};
  } catch (error) {
    failure = error;
    child = {code: error.code ?? null, signal: error.signal ?? null,
      stdout: error.stdout ?? '', stderr: error.stderr ?? ''};
  }
  try {
    observation = JSON.parse(await readFile(observationPath, 'utf8'));
    if (failure === undefined) {
      assert.equal(observation.status, 'observed');
      assert.equal(observation.registryClosed, true);
      for (const [key, value] of Object.entries(expected)) assert.deepEqual(observation[key], value);
      assert(isAbsolute(observation.consumer), 'Original consumer directory required');
      try {
        await lstat(observation.consumer);
        assert.fail('Consumer scratch remains after child exit');
      } catch (error) {if (error.code !== 'ENOENT') throw error;}
      // Remove provisional DATA before writing success, so no later cleanup
      // obligation can retroactively turn this receipt into a false pass.
      await unlink(observationPath);
    }
  } catch (error) {failure ??= error;}
  if (failure !== undefined) {
    await writeFile(failurePath, `${JSON.stringify({...expected, status: 'failed',
      error: failure.message, child, consumer: observation?.consumer,
      records: observation?.records}, null, 2)}\n`, {flag: 'wx'});
    throw failure;
  }
  const receipt = {...observation, status: 'passed', scratchRemoved: true, consumerProcess: child};
  await writeFile(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
  return receipt;
}

export async function acceptInstalledSourceFree(input) {
  const directory = resolve(input), manifest = await verifyNativeCliRelease(directory);
  const source = checkoutState(repository);
  assert(source.clean && source.revision === manifest.sourceSha, 'Exact clean fixed source required');
  const glibc = process.platform === 'linux' ? process.report.getReport().header.glibcVersionRuntime : undefined;
  const platform = platformKey({platform: process.platform, arch: process.arch, glibc});
  const artifact = manifest.artifacts.find(value => value.platform === platform);
  assert(artifact?.localRuntime, 'Source-free installed acceptance requires a real Local runtime artifact');
  const stamp = `${platform}-${Date.now()}-${randomUUID()}`;
  const observationPath = join(directory, `source-free-observed-${stamp}.json`);
  const receiptPath = join(directory, `source-free-install-${stamp}.json`);
  await runCleanupConditionedConsumer({command: process.execPath,
    args: [fileURLToPath(import.meta.url), '--consumer', directory, observationPath],
    observationPath, receiptPath, failurePath: join(directory, `source-free-install-failed-${stamp}.json`),
    expected: {version: 'actql-native-cli-install-acceptance/0.1', scope: 'source-free-local',
      cliSourceSha: manifest.sourceSha, platform, artifact,
      scriptSha256: createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex')}});
  console.log(`Installed Native source-free Local passed: ${receiptPath}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [first, ...rest] = process.argv.slice(2);
  if (first === '--consumer') {
    assert(rest.length === 2 && isAbsolute(rest[1]), 'Explicit private consumer observation path required');
    await observeInstalledSourceFree(rest[0], rest[1]);
  } else {
    assert(first && rest.length === 0, 'usage: test-native-cli-source-free-install.mjs <fixed-CLI-RC>');
    await acceptInstalledSourceFree(first);
  }
}
