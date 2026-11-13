// Temporary single-input diagnostic. The product is the unchanged failed-CI
// artifact; only its authored Program input selects the published records view.
// This is neither final-source acceptance nor a performance measurement.
import assert from 'node:assert/strict';
import {execFile, execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstat, mkdir, readFile, unlink, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {promisify} from 'node:util';

const [sourceArgument, releaseArgument, fixtureArgument, evidenceArgument, ...extra] = process.argv.slice(2);
assert(sourceArgument && releaseArgument && fixtureArgument && evidenceArgument && !extra.length,
  'Supply original Source, retained release, corrected input and fresh evidence directory');
const source = resolve(sourceArgument), release = resolve(releaseArgument);
const fixture = resolve(fixtureArgument), evidence = resolve(evidenceArgument);
const productSource = 'bda5c942c20472d34ff512477941106370e98298';
const fixtureSha256 = 'b51302160d745487db7a27ba8d17eb6a0e46eb70562838caaff13da583bdaa9b';
const hash = body => createHash('sha256').update(body).digest('hex');
const originalModule = name => import(pathToFileURL(join(source, name)).href);
const git = args => execFileSync('git', args, {cwd: source, encoding: 'utf8'}).trim();
const absent = pid => {
  assert(Number.isSafeInteger(pid) && pid > 0);
  try { process.kill(pid, 0); } catch (error) {
    assert.equal(error.code, 'ESRCH'); return true;
  }
  return false;
};
await mkdir(evidence, {recursive: false});
const root = join(evidence, 'private-consumer');
await mkdir(root, {mode: 0o700});
const receipt = {qualification: 'single corrected test-input diagnostic; not final acceptance or performance',
  productSource, diagnosticSource: process.env.ACTQL_DIAGNOSTIC_SOURCE ?? null,
  originalProducer: {run: 43405189585, artifact: 14028196384, status: 'FAILED',
    zipBytes: 15880275, zipSha256: '0f8d9acaa0d57bfc8a1c102c04aa5001b8ffe1cd7f8204869dd8f3e019d8bb07',
    originalFileCheck: 'completed / undetermined / unresolved_protected; unchanged failure retained'},
  fixtureSha256, status: 'running', commands: []};
const save = () => writeFile(join(evidence, 'diagnostic-result.json'), JSON.stringify(receipt, null, 2) + '\n');
await save();
let registry, verifyInstalled, primary;
try {
  assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
  assert(process.report.getReport().header.glibcVersionRuntime);
  assert.equal(git(['rev-parse', 'HEAD']), productSource);
  assert.equal(git(['status', '--porcelain']), '');
  const wire = await readFile(fixture);
  assert.equal(hash(wire), fixtureSha256);
  const document = JSON.parse(wire);
  assert.deepEqual(document.stages[0].inputs.records,
    {connector: 'snowflake', resource: 'usage_30d', view: 'records'});
  const {verifyNativeCliRelease} = await originalModule('scripts/native-cli-release.mjs');
  const manifest = await verifyNativeCliRelease(release);
  assert.equal(manifest.sourceSha, productSource);
  assert.deepEqual(Object.keys(manifest.platforms), ['linux-x64-gnu']);
  receipt.releaseManifestSha256 = hash(await readFile(join(release, 'release.json')));
  receipt.packages = manifest.packages.map(({name, file, bytes, sha256, integrity}) =>
    ({name, file, bytes, sha256, integrity}));
  const {openReleaseTestRegistry} = await originalModule('scripts/release-test-registry.mjs');
  const {nativeLauncherEnvelope} = await originalModule('scripts/native-cli-mock-scenario.mjs');
  const {nativeMockAcceptanceObservations} = await originalModule('packages/native-cli/lib/project-scaffold.mjs');
  registry = await openReleaseTestRegistry([{directory: release, manifest}]);
  const prefix = join(root, 'global'), project = join(root, 'project');
  const env = {...process.env};
  for (const key of Object.keys(env)) if (/^npm_config_/iu.test(key) || /^(ACTQL_|DYLD_)/u.test(key) ||
    ['NODE_PATH', 'NODE_OPTIONS', 'LD_PRELOAD', 'LD_LIBRARY_PATH', 'MOON_HOME'].includes(key)) delete env[key];
  Object.assign(env, {HOME: join(root, 'home'), TMPDIR: join(root, 'tmp'),
    npm_config_registry: registry.url, npm_config_userconfig: join(root, 'npmrc'),
    npm_config_globalconfig: join(root, 'npmrc-global'), npm_config_cache: join(root, 'cache'),
    npm_config_proxy: '', npm_config_https_proxy: '', npm_config_update_notifier: 'false',
    NO_PROXY: '127.0.0.1,localhost'});
  for (const path of [prefix, env.HOME, env.TMPDIR, join(root, 'empty-path')]) await mkdir(path);
  await writeFile(env.npm_config_userconfig, `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
  await writeFile(env.npm_config_globalconfig, '');
  const execute = promisify(execFile);
  const run = async (command, args, cwd) => {
    const ordinal = receipt.commands.length + 1;
    const record = {ordinal, command, args, cwd, status: 'running'};
    receipt.commands.push(record); await save();
    const pending = execute(command, args, {cwd, env, timeout: 180_000,
      killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024});
    record.launcherPid = pending.child.pid ?? null;
    let result;
    try { result = {...await pending, code: 0, signal: null}; }
    catch (error) { result = {code: error.code ?? null, signal: error.signal ?? null,
      stdout: error.stdout ?? '', stderr: error.stderr ?? ''}; }
    await writeFile(join(evidence, `${ordinal}.stdout.log`), result.stdout);
    await writeFile(join(evidence, `${ordinal}.stderr.log`), result.stderr);
    Object.assign(record, {code: result.code, signal: result.signal, status: 'observed'});
    await save();
    assert.equal(result.code, 0); assert.equal(result.signal, null);
    record.launcherAbsent = absent(record.launcherPid);
    assert(record.launcherAbsent, 'Original launcher remains live after its first exit');
    record.status = 'passed'; await save();
    return result;
  };
  await run('npm', ['install', '-g', '--prefix', prefix, '--ignore-scripts', '--no-audit', '--no-fund',
    `actql@${manifest.cohort.packageVersion}`], root);
  const installed = join(prefix, 'lib/node_modules/actql');
  const snapshot = async () => {
    const result = [];
    for (const item of manifest.packages) {
      const directory = item.name === 'actql' ? installed : join(installed, 'node_modules', item.name);
      for (const entry of item.files) {
        const path = join(directory, entry.path), stat = await lstat(path), body = await readFile(path);
        assert(stat.isFile()); assert.equal(body.length, entry.bytes);
        assert.equal(stat.mode & 0o777, entry.mode); assert.equal(hash(body), entry.sha256);
        result.push({package: item.name, ...entry, dev: stat.dev, ino: stat.ino});
      }
    }
    return result;
  };
  const before = await snapshot(); receipt.installedPayloadFiles = before.length;
  verifyInstalled = async () => {
    assert.deepEqual(await snapshot(), before);
    assert.equal(git(['rev-parse', 'HEAD']), productSource); assert.equal(git(['status', '--porcelain']), '');
    assert.deepEqual(await verifyNativeCliRelease(release), manifest);
    receipt.installedPayloadBeforeAfterExact = true;
  };
  env.PATH = join(root, 'empty-path');
  const launcher = join(prefix, 'bin/actql');
  const cli = (args, cwd = project) => run(process.execPath, [launcher, ...args], cwd);
  await cli(['init', '--template', 'churn-risk-mock', project], root);
  const filename = 'file-task-boundary.json';
  const file = join(project, filename), sourceFile = join(project, 'mock/data.json');
  const originalRows = await readFile(sourceFile);
  await writeFile(file, wire, {flag: 'wx', mode: 0o600});
  const checked = JSON.parse((await cli(['check', filename, '--format', 'json', '--json'])).stdout);
  receipt.check = checked; await save();
  assert.equal(checked.outcome, 'completed'); assert.equal(checked.report.verdict, 'verified');
  assert.deepEqual(checked.report.runnable, {reasons: [], verdict: 'yes'});
  const observed = async args => {
    env.ACTQL_NATIVE_TIMINGS = '1'; env.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS = '1';
    let result;
    try { result = await cli(args); }
    finally { delete env.ACTQL_NATIVE_TIMINGS; delete env.ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS; }
    const native = nativeLauncherEnvelope(result.stderr, 'required').native;
    const groups = nativeMockAcceptanceObservations(native);
    assert.equal(groups.length, 1); assert.equal(groups[0].events.length, 0);
    const lines = native.trimEnd().split('\n').map(line => {
      const split = line.indexOf(' '); return {marker: line.slice(0, split), value: JSON.parse(line.slice(split + 1))};
    });
    const meta = lines.find(line => line.marker === 'ACTQL_NATIVE_TIMINGS').value;
    for (const key of ['initializing_drops', 'invalid_tags', 'invalid_amounts', 'clock_failures', 'stack_overflows'])
      assert.equal(meta[key], 0);
    assert.equal(meta.overflow, false);
    const close = lines.find(line => line.marker === 'ACTQL_NATIVE_PHASE' && line.value.tag === 5).value;
    assert.equal(close.begins, 1); assert.equal(close.ends, 1);
    assert.equal(close.active, 0); assert.equal(close.unmatched_end, 0);
    const original = receipt.commands.at(-1);
    original.nativePid = groups[0].pid; original.nativeAbsent = absent(original.nativePid);
    original.firstCommandCleanup = close;
    await save(); assert(original.nativeAbsent, 'Original Native child remains live after first command exit');
    return {result, pid: original.nativePid};
  };
  const runResult = await observed(['run', filename, '--format', 'json', '--json']);
  const state = JSON.parse(runResult.result.stdout);
  assert.equal(state.version, 'actql-run-state/0.1'); assert.equal(state.status, 'succeeded');
  assert.equal(typeof state.run_id, 'string'); assert(state.run_id.length > 0);
  receipt.runId = state.run_id; await save();
  const rows = text => text.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
  const first = await observed(['result', state.run_id, '--result', 'answer', '--format', 'jsonl']);
  assert.deepEqual(rows(first.result.stdout), [{id: 2}]);
  assert.deepEqual(await readFile(sourceFile), originalRows);
  await unlink(file); await unlink(sourceFile);
  const cold = await observed(['result', state.run_id, '--result', 'answer', '--format', 'jsonl']);
  assert.notEqual(cold.pid, first.pid); assert.deepEqual(rows(cold.result.stdout), [{id: 2}]);
  receipt.rows = [{id: 2}]; receipt.sameSavedAfterProgramAndSourceRemoval = true;
  receipt.firstCommandCleanupObserved = true; receipt.independentPhysicalAck = false;
} catch (error) { primary = error; }
finally {
  for (const close of [verifyInstalled, registry && (() => registry.close())]) if (close) {
    try { await close(); }
    catch (error) { primary = primary ? new AggregateError([primary, error], 'Diagnostic and final correspondence/registry failures') : error; }
  }
  receipt.status = primary ? 'failed' : 'passed';
  if (primary) receipt.failure = {name: primary.name, message: primary.message, stack: primary.stack};
  await save();
}
if (primary) throw primary;
console.log(`One retained Native File diagnostic passed: ${join(evidence, 'diagnostic-result.json')}`);
