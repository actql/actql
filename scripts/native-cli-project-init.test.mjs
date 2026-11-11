import assert from 'node:assert/strict';
import {test} from 'node:test';
import {copyFile, mkdir, mkdtemp, readdir, realpath, rm, readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {projectInitArguments, projectInitialAdoptionArguments, requireProjectInitSupport, scaffoldProject} from '../packages/native-cli/lib/project-scaffold.mjs';
import {nativeCliPackageInputs} from './native-cli-package-inputs.mjs';
import {projectTemplateFiles} from '../packages/native-cli/lib/project-template.mjs';

test('init forwards one explicit operator Host path unchanged to the original Native adoption', () => {
  const selection = projectInitArguments(['init', '--template', 'deal-review-mock',
    '--host-config', './operator/host.json', 'project']);
  assert.deepEqual(selection, {directory: 'project', template: 'deal-review-mock',
    hostConfiguration: './operator/host.json'});
  assert.equal(projectInitArguments(['init', '--host-config=./selected.json']).hostConfiguration,
    './selected.json');
  assert.deepEqual(projectInitialAdoptionArguments({configuration: '/owned/project/actql.config.json',
    stateDirectory: '/owned/project/.actql'}, selection.hostConfiguration),
  ['--host-config', './operator/host.json', '--mode', 'local', '--config', '/owned/project/actql.config.json',
    '--state-dir', '/owned/project/.actql', 'adopt', '--initialize-signing']);
  for (const args of [['--host-config'], ['--host-config='], ['--host-config', '--force'],
    ['--host-config', 'a', '--host-config', 'b'], ['--host-config', 'nul\0file']]) {
    assert.throws(() => projectInitArguments(['init', ...args]), {code: 'ACTQL_E_INIT_ARGUMENTS'});
  }
});

test('deal-review fixture declares its three internal Source policies without a global Mock default', () => {
  const files = projectTemplateFiles('deal-review-mock');
  const catalogue = JSON.parse(files['mock/catalog.json']);
  const views = Object.values(catalogue.connections).flatMap(connection => connection.views);
  assert.deepEqual(views.map(view => [view.resource, view.data_classification]),
    [['Opportunity', 'internal'], ['files', 'internal'], ['contents', 'internal']]);
  const plain = JSON.parse(projectTemplateFiles()['actql.config.json']);
  assert.equal(Object.hasOwn(plain, 'mock'), false);
});

test('churn-risk fixture declares the classification of both original input Sources', () => {
  const files = projectTemplateFiles('churn-risk-mock');
  const catalogue = JSON.parse(files['mock/catalog.json']);
  const views = Object.values(catalogue.connections).flatMap(connection => connection.views);
  assert.deepEqual(views.map(view => [view.resource, view.data_classification]),
    [['Account', 'internal'], ['usage_30d', 'internal']]);
});

const repository = fileURLToPath(new URL('../', import.meta.url));
const launcher = fileURLToPath(new URL('../packages/native-cli/bin/actql.mjs', import.meta.url));
const installedPlatform = process.platform === 'darwin' && process.arch === 'arm64' ? 'darwin-arm64'
  : process.platform === 'linux' && process.arch === 'x64' && process.report.getReport().header.glibcVersionRuntime
    ? 'linux-x64-gnu' : undefined;
const installedTest = {skip: installedPlatform === undefined};
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const scratch = async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-project-init-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
};
const command = (cwd, args) => spawnSync(process.execPath, [launcher, ...args],
  {cwd, encoding: 'utf8', timeout: 10_000, maxBuffer: 8192});

async function installedFixture(t, {runtime = false} = {}) {
  const root = await scratch(t), cwd = join(root, 'workspace');
  const cli = join(root, 'node_modules/actql');
  const packageName = `@actql/cli-${installedPlatform}`;
  const native = join(root, 'node_modules', packageName), executable = join(native, 'bin/actql-native-client');
  await mkdir(cwd); await mkdir(dirname(executable), {recursive: true});
  const inputs = nativeCliPackageInputs(repository);
  for (const {source, member} of inputs.copies) {
    await mkdir(dirname(join(cli, member)), {recursive: true});
    await copyFile(join(repository, source), join(cli, member));
  }
  await copyFile(join(repository, inputs.manifest), join(cli, 'package.json'));
  await writeFile(join(native, 'package.json'), JSON.stringify({name: packageName, version: '0.0.2'}));
  // An explicitly synthetic dispatch observer, never a Native implementation
  // or package acceptance result. Its exact bytes pass normal launcher checks.
  const binary = Buffer.from(`#!${process.execPath}\n` +
    'if (process.argv[2] === "project-init-support") {\n' +
    '  if (process.env.ACTQL_NATIVE_TIMINGS !== "0") process.stderr.write("query timing diagnostics must be suppressed");\n' +
    '  process.stdout.write(process.env.ACTQL_INIT_FIXTURE_SUPPORT ?? JSON.stringify({version:"actql-project-init-support/0.1",sourceFree:true,mock:false}));\n' +
    '  process.exit(0);\n' +
    '}\n' +
    'process.stdout.write(JSON.stringify({args:process.argv.slice(2),runtime:process.env.ACTQL_NATIVE_LOCAL_RUNTIME ?? null,...(process.env.ACTQL_INIT_FIXTURE_OBSERVE_TIMINGS === "1" ? {timings:process.env.ACTQL_NATIVE_TIMINGS} : {})}) + "\\n");\n' +
    'process.exitCode=Number(process.env.ACTQL_INIT_FIXTURE_EXIT ?? 0);\n');
  await writeFile(executable, binary, {mode: 0o755});
  const sourceSha = 'a'.repeat(40);
  const abi = installedPlatform === 'darwin-arm64' ? {minimumMacOS: '11.0'} : {minimumGlibc: '2.17'};
  const metadata = {version: 'actql-native-cli-artifact/0.1', platform: installedPlatform,
    sourceSha, binarySha256: digest(binary), binaryBytes: binary.length, abi};
  const expected = {package: packageName, sourceSha,
    binarySha256: metadata.binarySha256, binaryBytes: binary.length};
  if (runtime) {
    // Metadata selection alone cannot establish physical/runtime admission.
    // These bounded synthetic members only let the dispatch observer run.
    const member = async (path, bytes) => {
      await mkdir(dirname(join(native, path)), {recursive: true});
      await writeFile(join(native, path), bytes);
      return {path, bytes: bytes.length, sha256: digest(bytes)};
    };
    const license = await member('licenses/fixture.txt', Buffer.from('Synthetic fixture only.\n'));
    const libraries = await Promise.all(['sqlite', 'crypto'].map(async role => ({role,
      ...await member(`lib/${role}.fixture`, Buffer.alloc(64)), license: license.path, dependencies: [], abi})));
    const assets = await Promise.all(['environment', 'registry', 'values', 'fragment', 'result-policy'].map(async role => ({role,
      ...await member(`data/${role}.json`, Buffer.from('{}\n'))})));
    metadata.localRuntime = await member('local-runtime.json', Buffer.from(JSON.stringify({
      sourceSha, platform: installedPlatform, libraries, assets, licenses: [license],
    })));
    expected.localRuntimeSha256 = metadata.localRuntime.sha256;
  }
  const save = async () => {
    await writeFile(join(native, 'artifact.json'), JSON.stringify(metadata));
    await writeFile(join(cli, 'platforms.json'), JSON.stringify({[installedPlatform]: expected}));
  };
  await save();
  const invoke = (args, environment = {}) => spawnSync(process.execPath, [join(cli, 'bin/actql.mjs'), ...args], {
    cwd, env: {...process.env, ACTQL_NATIVE_TIMINGS: '0', ACTQL_INIT_FIXTURE_EXIT: '0', ...environment},
    encoding: 'utf8', timeout: 10_000, maxBuffer: 8192,
  });
  return {cwd, native, executable, binary, metadata, expected, save, invoke};
}

test('installed init dispatcher forwards the original Host selector without reading or creating that file', installedTest, async t => {
  const f = await installedFixture(t, {runtime: true});
  const host = './operator/host.json';
  const result = f.invoke(['init', 'project', '--host-config', host]);
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0);
  assert.equal(result.stderr, '');
  const project = await realpath(join(f.cwd, 'project'));
  assert.deepEqual(JSON.parse(result.stdout).args,
    ['--host-config', host, '--mode', 'local', '--config', join(project, 'actql.config.json'),
      '--state-dir', join(project, '.actql'), 'adopt', '--initialize-signing']);
  assert.deepEqual(await readdir(f.cwd), ['project']);
  // This synthetic process observes dispatch only. Native still owns creation,
  // current/custody, Account admission, signer selection and all physical ACKs.
});

test('only init is intercepted while all protocol operations retain their original argv', () => {
  for (const args of [[], ['adopt'], ['run', 'program.aql'], ['--mode', 'local', 'connect'], ['initialize']]) {
    const before = structuredClone(args);
    assert.equal(projectInitArguments(args), undefined);
    assert.deepEqual(args, before);
  }
  assert.deepEqual(projectInitArguments(['init']), {directory: '.', template: undefined});
});

test('init admits exactly the documented template and optional directory in either order', () => {
  const expected = {directory: 'project', template: 'churn-risk-mock'};
  for (const args of [['init', '--template', 'churn-risk-mock', 'project'],
    ['init', 'project', '--template=churn-risk-mock']]) {
    assert.deepEqual(projectInitArguments(args), expected);
    assert(Object.isFrozen(projectInitArguments(args)));
  }
  assert.deepEqual(projectInitArguments(['init', 'project']), {directory: 'project', template: undefined});
});

test('init rejects unknown options, multiple targets and duplicate or incomplete template selection', () => {
  for (const tail of [['--runtime', 'replacement'], ['--approval', 'allow'], ['--initialize-signing'], ['--force'], ['a', 'b'],
    ['--template'], ['--template='], ['--template', '--'],
    ['--template=churn-risk-mock', '--template=churn-risk-mock'], ['--help', 'project']]) {
    assert.throws(() => projectInitArguments(['init', ...tail]), {code: 'ACTQL_E_INIT_ARGUMENTS'});
  }
  assert.throws(() => projectInitArguments(['init', '--template', 'other']), {code: 'ACTQL_E_TEMPLATE'});
});

test('prepared init requests the original Native initial-signing path without changing paths or supplying authority', () => {
  const project = Object.freeze({configuration: '/owned/project/actql.config.json',
    stateDirectory: '/owned/project/.actql'});
  const args = projectInitialAdoptionArguments(project);
  assert.deepEqual(args, ['--mode', 'local', '--config', '/owned/project/actql.config.json',
    '--state-dir', '/owned/project/.actql', 'adopt', '--initialize-signing']);
  assert(Object.isFrozen(args));
  assert.deepEqual(project, {configuration: '/owned/project/actql.config.json',
    stateDirectory: '/owned/project/.actql'});
});

test('the existing separator admits a dash-prefixed directory without treating it as a supplier option', () => {
  assert.deepEqual(projectInitArguments(['init', '--', '--directory']),
    {directory: '--directory', template: undefined});
});

test('public init help does not need a runtime or create project files', async t => {
  const root = await scratch(t);
  for (const help of ['--help', '-h']) {
    const result = command(root, ['init', help]);
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0);
    assert.equal(result.stderr, '');
    assert.equal(result.stdout, 'Usage: actql init [--template churn-risk-mock|deal-review-mock] [--host-config <file>] [<directory>]\n');
  }
  assert.deepEqual(await readdir(root), []);
});

test('actual launcher rejects invalid preparation before writes or Native package selection', async t => {
  const root = await scratch(t);
  for (const tail of [['--template', 'other', 'project'], ['--runtime', 'replacement'], ['project', 'second']]) {
    const result = command(root, ['init', ...tail]);
    assert.equal(result.error, undefined);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.doesNotMatch(result.stderr, /Native package|Missing @actql|Unsupported platform/u);
    assert.deepEqual(await readdir(root), []);
  }
});

test('a source checkout without a staged Native cohort refuses init before template preparation', async t => {
  const root = await scratch(t);
  // The checkout has no staged platform mapping. This negative uses the actual
  // launcher and package resolver, not a fabricated Native success binary.
  const result = command(root, ['init', '--template', 'churn-risk-mock', 'project']);
  assert.equal(result.error, undefined);
  assert.notEqual(result.status, 0);
  if (['darwin', 'linux'].includes(process.platform)) {
    const mapping = fileURLToPath(new URL('../packages/native-cli/platforms.json', import.meta.url));
    assert.equal(result.stderr, `actql: ENOENT: no such file or directory, open '${mapping}'\n`);
  } else {
    assert.match(result.stderr, /Unsupported platform/u);
  }
  assert.equal(result.stdout, '');
  assert.deepEqual(await readdir(root), []);
});

test('an installed package without Local runtime refuses every init template before any project writes', installedTest, async t => {
  const f = await installedFixture(t);
  for (const template of [undefined, 'churn-risk-mock', 'deal-review-mock']) {
    for (const directory of [undefined, 'project']) {
      const args = ['init', ...(template ? ['--template', template] : []), ...(directory ? [directory] : [])];
      const result = f.invoke(args, {ACTQL_NATIVE_LOCAL_RUNTIME: 'untrusted ambient selector'});
      assert.ifError(result.error); assert.equal(result.signal, null); assert.equal(result.status, 69);
      assert.equal(result.stdout, '');
      assert.equal(result.stderr, `actql: Packaged Local runtime is unavailable for ${installedPlatform}; actql init requires it. No project files were created. Remote commands remain available.\n`);
      assert.deepEqual(await readdir(f.cwd), []);
    }
  }
});

test('init capability refusal preserves an existing destination and never overwrites its files', installedTest, async t => {
  const f = await installedFixture(t), project = join(f.cwd, 'project');
  await mkdir(project); await writeFile(join(project, 'keep.txt'), 'Original user content.\n');
  const result = f.invoke(['init', '--template', 'deal-review-mock', 'project']);
  assert.ifError(result.error); assert.equal(result.status, 69); assert.equal(result.stdout, '');
  assert.match(result.stderr, /Packaged Local runtime is unavailable/u);
  assert.deepEqual(await readdir(f.cwd), ['project']);
  assert.deepEqual(await readdir(project), ['keep.txt']);
  assert.equal(await readFile(join(project, 'keep.txt'), 'utf8'), 'Original user content.\n');
});

test('installed binary identity failures are not hidden by the missing Local runtime preflight', installedTest, async t => {
  const f = await installedFixture(t), original = structuredClone(f.metadata);
  for (const changed of [{sourceSha: 'b'.repeat(40)}, {platform: 'foreign-platform'},
    {binarySha256: 'c'.repeat(64)}, {binaryBytes: f.binary.length + 1}]) {
    Object.assign(f.metadata, original, changed); await f.save();
    const result = f.invoke(['init', 'project']);
    assert.ifError(result.error); assert.equal(result.status, 65); assert.equal(result.stdout, '');
    assert.match(result.stderr, /Native artifact identity mismatch/u);
    assert.deepEqual(await readdir(f.cwd), []);
  }
  Object.assign(f.metadata, original); await f.save();
  const changed = Buffer.from(f.binary); changed[changed.length - 1] ^= 1;
  await writeFile(f.executable, changed);
  const result = f.invoke(['init', 'project']);
  assert.ifError(result.error); assert.equal(result.status, 65); assert.equal(result.stdout, '');
  assert.match(result.stderr, /Native artifact identity mismatch/u);
  assert.deepEqual(await readdir(f.cwd), []);
});

test('incomplete or damaged installed runtime descriptors keep their identity refusal before init writes', installedTest, async t => {
  const f = await installedFixture(t, {runtime: true});
  const original = f.metadata.localRuntime, pinned = f.expected.localRuntimeSha256;
  for (const missing of ['metadata', 'pin', 'manifest']) {
    f.metadata.localRuntime = original; f.expected.localRuntimeSha256 = pinned;
    if (missing === 'metadata') delete f.metadata.localRuntime;
    if (missing === 'pin') delete f.expected.localRuntimeSha256;
    if (missing === 'manifest') await writeFile(join(f.native, 'local-runtime.json'), '{}\n');
    await f.save();
    const result = f.invoke(['init', 'project']);
    assert.ifError(result.error); assert.equal(result.status, 65); assert.equal(result.stdout, '');
    assert.match(result.stderr, /Native Local runtime identity or dependency mismatch/u);
    assert.deepEqual(await readdir(f.cwd), []);
  }
});

test('missing Local runtime does not block help, version or unchanged Remote argument dispatch', installedTest, async t => {
  const f = await installedFixture(t);
  for (const args of [['--help'], ['--version'], ['version'], ['--mode', 'remote', 'connect'],
    ['--mode', 'remote', 'run', 'program.aql']]) {
    const result = f.invoke(args, {ACTQL_NATIVE_LOCAL_RUNTIME: 'untrusted ambient selector'});
    assert.ifError(result.error); assert.equal(result.signal, null); assert.equal(result.status, 0);
    assert.equal(result.stderr, '');
    assert.deepEqual(JSON.parse(result.stdout), {args: args[0] === 'version' ? ['--version'] : args, runtime: null});
  }
  const help = f.invoke(['init', '--help']);
  assert.ifError(help.error); assert.equal(help.status, 0); assert.equal(help.stderr, '');
  assert.match(help.stdout, /^Usage: actql init /u);
  assert.deepEqual(await readdir(f.cwd), []);
});

test('available runtime metadata preserves Native adoption dispatch and retains files on child failure', installedTest, async t => {
  const f = await installedFixture(t, {runtime: true}), project = join(f.cwd, 'project');
  const result = f.invoke(['init', 'project'], {ACTQL_INIT_FIXTURE_EXIT: '71'});
  assert.ifError(result.error); assert.equal(result.signal, null); assert.equal(result.status, 71);
  assert.equal(result.stderr, '');
  const observed = JSON.parse(result.stdout);
  const canonicalProject = await realpath(project);
  assert.deepEqual(observed.args, ['--mode', 'local', '--config', join(canonicalProject, 'actql.config.json'),
    '--state-dir', join(canonicalProject, '.actql'), 'adopt', '--initialize-signing']);
  assert.deepEqual(JSON.parse(observed.runtime), {root: await realpath(f.native), sourceSha: f.expected.sourceSha,
    platform: installedPlatform, manifestSha256: f.expected.localRuntimeSha256});
  assert.deepEqual(await readdir(project), ['actql.config.json', 'connectors.json', 'model-tasks.json']);
  // Retained files are not adopted state or permission to overwrite on retry.
  const retry = f.invoke(['init', 'project']);
  assert.ifError(retry.error); assert.equal(retry.status, 69); assert.equal(retry.stdout, '');
  assert.match(retry.stderr, /project directory must be an empty owned directory/u);
  assert.deepEqual(await readdir(project), ['actql.config.json', 'connectors.json', 'model-tasks.json']);
});

// The root README and the churn Quickstart are distinct public examples.
// This checks the documented argv only: no Native runtime, Host or file write.
test('root README deal-review init selects its exact documented template and directory', async () => {
  const readme = await readFile(new URL('../README.md', import.meta.url), 'utf8');
  const line = readme.split(/\r?\n/u).find(value => value.startsWith('actql init --template '));
  assert.equal(line, 'actql init --template deal-review-mock deal-review && cd deal-review');
  const args = line.split(' && ')[0].split(' ').slice(1);
  assert.deepEqual(projectInitArguments(args), {directory: 'deal-review', template: 'deal-review-mock'});
});

const supportReply = value => ({status: 0, signal: null, stderr: '',
  stdout: JSON.stringify({version: 'actql-project-init-support/0.1', sourceFree: true, mock: false, ...value})});

test('init implementation query uses only the admitted executable and fixed bounded arguments', () => {
  const environment = Object.freeze({ACTQL_NATIVE_LOCAL_RUNTIME: 'admitted', ACTQL_NATIVE_TIMINGS: '1'});
  requireProjectInitSupport('/admitted/native', environment, undefined, (executable, args, options) => {
    assert.equal(executable, '/admitted/native');
    assert.deepEqual(args, ['project-init-support']);
    assert.notEqual(options.env, environment);
    assert.deepEqual(options.env, {...environment, ACTQL_NATIVE_TIMINGS: '0'});
    assert.equal(environment.ACTQL_NATIVE_TIMINGS, '1');
    assert.deepEqual(options.stdio, ['ignore', 'pipe', 'pipe']);
    assert.equal(options.timeout, 5000);
    assert.equal(options.killSignal, 'SIGKILL');
    assert.equal(options.maxBuffer, 4096);
    return supportReply();
  });
  // A parser fixture is not runtime acceptance: future Native support is not
  // prohibited by a JavaScript template ban.
  requireProjectInitSupport('/admitted/native', environment, 'churn-risk-mock', () => supportReply({mock: true}));
});

test('private support wire accepts the Native final LF but refuses duplicate keys and alternative encodings', async t => {
  const root = await scratch(t);
  const wire = supportReply().stdout;
  requireProjectInitSupport('/admitted/native', {}, undefined, () => ({...supportReply(), stdout: wire + '\n'}));
  const invalid = [
    wire.replace('"mock":false', '"mock":false,"mock":true'),
    wire.replace('"sourceFree":true', '"sourceFree":false,"sourceFree":true'),
    wire.replace('"version":', '"version":"unknown","version":'),
    wire + wire, wire + '\n{}', wire + ' trailing',
    wire.replace('"mock"', '"mo\\u0063k"'),
    JSON.stringify({mock: false, sourceFree: true, version: 'actql-project-init-support/0.1'}),
    JSON.stringify(JSON.parse(wire), null, 2), wire + '\n\n',
  ];
  for (const stdout of invalid) {
    assert.throws(() => {
      requireProjectInitSupport('/admitted/native', {}, undefined, () => ({...supportReply(), stdout}));
      scaffoldProject(join(root, 'absent'));
    }, e => e.exitCode === 69 && /initialization support is unavailable/.test(e.message));
    assert.deepEqual(await readdir(root), []);
  }
});

test('unavailable mock bindings preserve absent, empty and occupied project targets', async t => {
  const root = await scratch(t);
  await mkdir(join(root, 'empty'));
  await mkdir(join(root, 'occupied'));
  await writeFile(join(root, 'occupied/sentinel'), 'unchanged');
  for (const template of ['churn-risk-mock', 'deal-review-mock']) {
    for (const target of ['absent', 'empty', 'occupied']) {
      assert.throws(() => {
        requireProjectInitSupport('/admitted/native', {}, template, () => supportReply());
        scaffoldProject(join(root, target), template);
      }, e => e.exitCode === 69 && /does not implement/.test(e.message));
    }
  }
  assert.deepEqual((await readdir(root)).sort(), ['empty', 'occupied']);
  assert.deepEqual(await readdir(join(root, 'empty')), []);
  assert.deepEqual(await readdir(join(root, 'occupied')), ['sentinel']);
  assert.equal(await readFile(join(root, 'occupied/sentinel'), 'utf8'), 'unchanged');
});

test('old, malformed, failed, timed out and oversized Native queries refuse before preparation', async t => {
  const root = await scratch(t);
  const invalid = [
    {...supportReply(), status: 2}, {...supportReply(), status: null, signal: 'SIGTERM'},
    {...supportReply(), error: Object.assign(Error('timeout'), {code: 'ETIMEDOUT'})},
    {...supportReply(), stdout: 'x'.repeat(4097)}, {...supportReply(), stdout: ''},
    {...supportReply(), stdout: '{} trailing'}, {...supportReply(), stdout: 'null'},
    {...supportReply(), stdout: '[]'}, {...supportReply(), stdout: '{}'},
    {...supportReply(), stderr: 'unexpected warning'},
    supportReply({version: 'unknown'}), supportReply({mock: 'true'}),
    supportReply({extra: true}), supportReply({sourceFree: false}),
  ];
  for (const reply of invalid) {
    assert.throws(() => {
      requireProjectInitSupport('/admitted/native', {}, undefined, () => reply);
      scaffoldProject(join(root, 'absent'));
    }, e => e.exitCode === 69);
    assert.deepEqual(await readdir(root), []);
  }
});


test('installed launcher refuses unavailable mock support before scaffolding or adoption', installedTest, async t => {
  const f = await installedFixture(t, {runtime: true});
  await mkdir(join(f.cwd, 'empty'));
  await mkdir(join(f.cwd, 'occupied'));
  await writeFile(join(f.cwd, 'occupied/sentinel'), 'unchanged');
  for (const template of ['churn-risk-mock', 'deal-review-mock']) {
    for (const target of ['absent', 'empty', 'occupied']) {
      const result = f.invoke(['init', '--template', template, target]);
      assert.ifError(result.error); assert.equal(result.status, 69);
      assert.equal(result.stdout, '');
      assert.match(result.stderr, /does not implement the selected project bindings/u);
      assert.deepEqual((await readdir(f.cwd)).sort(), ['empty', 'occupied']);
      assert.deepEqual(await readdir(join(f.cwd, 'empty')), []);
      assert.deepEqual(await readdir(join(f.cwd, 'occupied')), ['sentinel']);
      assert.equal(await readFile(join(f.cwd, 'occupied/sentinel'), 'utf8'), 'unchanged');
    }
  }
});

test('installed launcher rejects malformed and oversized support replies before scaffold', installedTest, async t => {
  const f = await installedFixture(t, {runtime: true});
  for (const reply of ['not JSON', '{}', 'x'.repeat(5000), JSON.stringify({version:'old',sourceFree:true,mock:true})]) {
    const result = f.invoke(['init', 'absent'], {ACTQL_INIT_FIXTURE_SUPPORT: reply});
    assert.ifError(result.error); assert.equal(result.status, 69);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /initialization support is unavailable/u);
    assert.deepEqual(await readdir(f.cwd), []);
  }
});


test('installed init silences only private query timings and preserves adoption diagnostics', installedTest, async t => {
  const f = await installedFixture(t, {runtime: true});
  const result = f.invoke(['init', 'project'], {
    ACTQL_NATIVE_TIMINGS: '1', ACTQL_INIT_FIXTURE_OBSERVE_TIMINGS: '1',
  });
  assert.ifError(result.error); assert.equal(result.status, 0);
  const observed = JSON.parse(result.stdout);
  assert.equal(observed.timings, '1');
  const canonicalProject = await realpath(join(f.cwd, 'project'));
  assert.deepEqual(observed.args, ['--mode', 'local', '--config', join(canonicalProject, 'actql.config.json'),
    '--state-dir', join(canonicalProject, '.actql'), 'adopt', '--initialize-signing']);
  assert.match(result.stderr, /^ACTQL_NATIVE_LAUNCHER_TIMINGS /u);
  assert.doesNotMatch(result.stderr, /query timing diagnostics/u);
  assert.deepEqual(await readdir(join(f.cwd, 'project')), ['actql.config.json', 'connectors.json', 'model-tasks.json']);
});

function observation(pid, events = []) {
  return 'ACTQL_NATIVE_TIMINGS ' + JSON.stringify({pid, origin:'first_hook',elapsed_ns:1,clock_current:true,nested_inclusive:true,
    child_process_counters:false,phase_slots:39,counter_slots:66,initializing_drops:0,invalid_tags:0,invalid_amounts:0,clock_failures:0,overflow:false,stack_overflows:0,parallel_observed:false}) + '\n' +
    Array.from({length:39},(_,tag)=>'ACTQL_NATIVE_PHASE '+JSON.stringify({tag,name:['startup','config_auth','preparation','execution','save','close','saved_result','journal'][tag] ?? {32:'approval_material_complete',33:'approval_reviewer_sign',34:'approval_host_sign',35:'approval_resolution_commit',36:'approval_apply',37:'approval_publish',38:'approval_checkpoint_restore'}[tag] ?? 'private_phase',begins:0,ends:0,inclusive_ns:0,exclusive_ns:0,active:0,overlap:0,unmatched_end:0,sql_prepares:0,current_calls:0})+'\n').join('') +
    Array.from({length:66},(_,tag)=>'ACTQL_NATIVE_COUNTER '+JSON.stringify({tag,name:({0:'sqlite_open_calls',1:'sqlite_prepare_calls',2:'sqlite_step_calls',3:'sqlite_exec_calls',16:'member_hash_calls',17:'parse_check_calls',18:'current_calls',19:'account_auth_calls',20:'run_record_save_calls',22:'host_authorize_calls',23:'captured_read_authorize_calls',24:'publisher_authorize_calls',25:'run_record_read_calls',26:'adoption_digest_calls',46:'backing_allocated_bytes',47:'backing_explicit_zeroed_bytes',64:'signing_full_boundary_calls',65:'signing_helper_revalidation_calls'})[tag] ?? 'private_counter',count:0})+'\n').join('') +
    'ACTQL_NATIVE_ACCEPTANCE_BEGIN ' + JSON.stringify({pid, count: events.length, limit: 32, complete: true}) + '\n' +
    events.map((event, seq) => 'ACTQL_NATIVE_ACCEPTANCE_EVENT ' + JSON.stringify({pid, seq, ...event}) + '\n').join('') +
    'ACTQL_NATIVE_ACCEPTANCE_END ' + JSON.stringify({pid, count: events.length}) + '\n';
}

test('opt-in init observations forward only complete original child metadata with unchanged support contract', () => {
  const diagnostics = observation(123);
  const module = new URL('../packages/native-cli/lib/project-scaffold.mjs', import.meta.url).href;
  const program = `import assert from 'node:assert/strict';
    import {requireProjectInitSupport} from ${JSON.stringify(module)};
    const env = Object.freeze({ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS:'1',ACTQL_NATIVE_TIMINGS:'original'});
    requireProjectInitSupport('/original/native',env,undefined,(executable,args,options)=>{
      assert.equal(executable,'/original/native');assert.deepEqual(args,['project-init-support']);
      assert.equal(options.timeout,5000);assert.equal(options.maxBuffer,32768);
      assert.equal(options.env.ACTQL_NATIVE_TIMINGS,'1');assert.equal(env.ACTQL_NATIVE_TIMINGS,'original');
      return {status:0,signal:null,stdout:JSON.stringify({version:'actql-project-init-support/0.1',sourceFree:true,mock:false}),stderr:process.argv[1]};
    }); console.log('supported');`;
  const result = spawnSync(process.execPath,['--input-type=module','-e',program,diagnostics],{encoding:'utf8',timeout:5000,maxBuffer:65536});
  assert.ifError(result.error);assert.equal(result.signal,null);assert.equal(result.status,0,result.stderr);
  assert.equal(result.stdout,'supported\n');assert.equal(result.stderr,diagnostics);
});

test('opt-in init keeps unknown error malformed and partial diagnostics as refusal', () => {
  const good = observation(123);
  for (const stderr of [
    '', 'ACTQL_NATIVE_ERROR {"code":"PRIVATE"}\n', good+'plain error\n',
    good.replace(/ACTQL_NATIVE_ACCEPTANCE_END[^\n]*\n/u,''),
    good.replace('"complete":true','"complete":"true"'),
    good.replace('"tag":0,','"tag":0,"payload":"PRIVATE",'),
    good.replace('"count":0','"count":0,"count":0'),
  ]) {
    assert.throws(()=>requireProjectInitSupport('/original/native',{ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS:'1'},undefined,
      ()=>({...supportReply(),stderr})),{exitCode:69});
  }
});
