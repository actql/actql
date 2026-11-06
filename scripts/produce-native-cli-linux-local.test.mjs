import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {parseNativeLinuxLocalArguments, planNativeLinuxLocalProduction, produceNativeCliLinuxLocal,
  requireNativeLinuxLocalComponentSelection, requireNativeLinuxLocalHeader,
  requireNativeLinuxLocalArtifact} from './produce-native-cli-linux-local.mjs';

const sourceSha = 'a'.repeat(40), target = 'x86_64-unknown-linux-gnu';
const options = {sourceSha, packageVersion: '0.1.2-rc.3', outputDirectory: '/output/new',
  clang: '/tools/clang-19', sqliteArchive: '/inputs/sqlite.zip',
  opensslPackageArchives: ['/inputs/libssl-dev.deb', '/inputs/libssl3t64.deb']};
const context = {sourceRoot: '/source', node: '/tools/node'};
const identity = bytes => ({bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')});
const wire = value => JSON.stringify(value) + '\n';
const args = ['--source', sourceSha, '--package-version', '0.1.2-rc.3', '--output', '/output/new',
  '--clang', '/tools/clang-19', '--sqlite-archive', '/inputs/sqlite.zip',
  '--openssl-package-archive', '/inputs/libssl-dev.deb', '--openssl-package-archive', '/inputs/libssl3t64.deb'];

test('the independently expected command sequence always produces Linux Local with an explicit version', () => {
  const plan = planNativeLinuxLocalProduction(options, context);
  assert.deepEqual(plan.commands, [
    {phase: 'sqlite', command: 'python3', args: ['/source/scripts/produce-python-sqlite-component.py',
      '--source', sourceSha, '--archive', '/inputs/sqlite.zip', '--process-provider', '--process-target', 'linux-x64-gnu',
      '--clang', '/tools/clang-19', '--destination', '/output/new/sqlite', '--seconds', '600'], timeoutMs: 600000},
    {phase: 'crypto', command: 'python3', args: ['/source/scripts/produce-native-crypto-component.py',
      '--output', '/output/new/crypto', '--target', 'linux-x64', '--clang', '/tools/clang-19',
      '--openssl-package-archive', '/inputs/libssl-dev.deb', '--openssl-package-archive', '/inputs/libssl3t64.deb',
      '--seconds', '600'], timeoutMs: 600000},
    {phase: 'recipe', command: '/tools/node', args: ['/source/scripts/native-cli-linux-local-recipe.mjs',
      '--source', sourceSha, '--sqlite-component', '/output/new/sqlite', '--crypto-component', '/output/new/crypto',
      '--output', '/output/new/recipe'], timeoutMs: 120000},
    {phase: 'artifact', command: '/tools/node', args: ['/source/scripts/native-cli-artifact.mjs', '/output/new/artifact',
      '--local-runtime-recipe', '/output/new/recipe/local-runtime-recipe.json',
      '--package-version', '0.1.2-rc.3', '--compile-seconds', '900'], timeoutMs: 1050000},
  ]);
  assert.deepEqual(parseNativeLinuxLocalArguments(args), options);
});

test('explicit component and compiler limits stay separate and UAPI roots never become an automatic fallback', () => {
  const plan = planNativeLinuxLocalProduction({...options, componentSeconds: 70, compileSeconds: 7200,
    systemHeaderRoots: ['/usr/lib/linux/uapi']}, context);
  for (const step of plan.commands.slice(0, 2)) {
    assert.equal(step.timeoutMs, 70000);
    assert.deepEqual(step.args.slice(-4), ['--seconds', '70', '--system-header-root', '/usr/lib/linux/uapi']);
  }
  assert.deepEqual(plan.commands[3].args.slice(-2), ['--compile-seconds', '7200']);
  assert.equal(plan.commands[3].timeoutMs, 7350000);
  for (const step of plan.commands.slice(2)) assert(!step.args.includes('--system-header-root'));
  assert.deepEqual(parseNativeLinuxLocalArguments([...args, '--component-seconds', '70', '--compile-seconds', '7200',
    '--system-header-root', '/usr/lib/linux/uapi']), {...options, componentSeconds: 70, compileSeconds: 7200,
    systemHeaderRoots: ['/usr/lib/linux/uapi']});
  assert(!JSON.stringify(planNativeLinuxLocalProduction(options, context)).includes('/usr/lib/linux/uapi'));
});

test('missing, duplicate, implicit, unbounded and foreign selections fail rather than select Remote', () => {
  for (const key of ['sourceSha', 'packageVersion', 'outputDirectory', 'clang', 'sqliteArchive', 'opensslPackageArchives']) {
    const selected = {...options}; delete selected[key];
    assert.throws(() => planNativeLinuxLocalProduction(selected, context));
  }
  for (const selected of [
    {sourceSha: 'a'.repeat(39)}, {sourceSha: 'A'.repeat(40)}, {packageVersion: 'next'}, {packageVersion: '0.1.2+local'},
    {clang: 'clang'}, {clang: '/tools/../clang'}, {outputDirectory: '/source/output'}, {outputDirectory: '/source'},
    {outputDirectory: '/'}, {outputDirectory: '/output/a:b'}, {sqliteArchive: '/output/new/sqlite.zip'},
    {opensslPackageArchives: []}, {opensslPackageArchives: ['/inputs/one.deb']},
    {opensslPackageArchives: ['/inputs/one.deb', '/inputs/one.deb']},
    {opensslPackageArchives: ['relative.deb', '/inputs/two.deb']},
    {systemHeaderRoots: ['/usr/include']}, {systemHeaderRoots: ['/usr/lib/linux/uapi', '/usr/lib/linux/uapi']},
    {systemHeaderRoots: ['/tmp/headers']}, {platform: 'darwin-arm64'}, {sdk: '/SDK'},
    {localRuntime: undefined}, {allowHeavy: true}, {opensslPrefix: '/usr'}, {providerReceipt: '/old/receipt'},
  ]) assert.throws(() => planNativeLinuxLocalProduction({...options, ...selected}, context));
  for (const key of ['componentSeconds', 'compileSeconds']) for (const value of [null, false, '60', 0, -1, 1.5, NaN, Infinity, 86401])
    assert.throws(() => planNativeLinuxLocalProduction({...options, [key]: value}, context));
  assert.throws(() => planNativeLinuxLocalProduction({...options, componentSeconds: 1801}, context));
  assert.equal(planNativeLinuxLocalProduction({...options, componentSeconds: 1800, compileSeconds: 86400}, context).commands.length, 4);
  for (const suffix of [['--source', sourceSha], ['--unknown', 'yes'], ['--allow-heavy'], ['--compile-seconds', '1e3'],
    ['--component-seconds', '0'], ['--compile-seconds', '86401'], ['--compile-seconds', '--verbose']])
    assert.throws(() => parseNativeLinuxLocalArguments([...args, ...suffix]));
});

// Synthetic DATA below exercises selection and orchestration failures only.
// No component/compiler is executed and no runtime acceptance is claimed.
function receipts(plan) {
  const inputs = Object.fromEntries([plan.clang, plan.sqliteArchive, ...plan.opensslPackageArchives]
    .map(path => [path, identity(Buffer.from(path))]));
  const common = {target, compiler_target: 'x86_64-pc-linux-gnu', loaded: false, initialized: false, inputs};
  return {inputs, sqlite: {...common, source_sha: sourceSha}, crypto: {...common, source: sourceSha,
    package_archives: plan.opensslPackageArchives.map(path => ({path, ...inputs[path]}))}};
}

test('component receipts must bind the exact source, target, compiler and both original selected archives', () => {
  const plan = planNativeLinuxLocalProduction(options, context);
  const mutations = [
    f => {f.sqlite.source_sha = 'b'.repeat(40);}, f => {f.crypto.source = 'b'.repeat(40);},
    f => {f.sqlite.target = 'aarch64-unknown-linux-gnu';}, f => {f.crypto.target = 'aarch64-apple-darwin';},
    f => {f.sqlite.compiler_target = 'x86_64-windows';}, f => {f.crypto.compiler_target = 'aarch64-linux-gnu';},
    f => {f.sqlite.loaded = true;}, f => {f.crypto.initialized = true;},
    f => {delete f.sqlite.inputs[plan.clang];}, f => {f.crypto.inputs[plan.clang] = identity(Buffer.from('another compiler'));},
    f => {delete f.sqlite.inputs[plan.sqliteArchive];},
    f => {delete f.crypto.inputs[plan.opensslPackageArchives[1]];},
    f => {delete f.crypto.package_archives;}, f => {f.crypto.package_archives.reverse();},
    f => {f.crypto.package_archives[0].sha256 = 'b'.repeat(64);},
    f => {f.crypto.package_archives.pop();},
  ];
  const good = receipts(plan);
  requireNativeLinuxLocalComponentSelection(plan, good, good.inputs);
  for (const mutate of mutations) {
    const f = structuredClone(receipts(plan)), originals = structuredClone(f.inputs);
    mutate(f);
    assert.throws(() => requireNativeLinuxLocalComponentSelection(plan, f, originals));
  }
});

test('Native header selection requires the staged original and its checked-in source pin', () => {
  const bytes = Buffer.from('synthetic header DATA\n'), selected = identity(bytes);
  const sqlite = {stage: {outputs: {'sqlite3.h': selected}}};
  const sourceRecipe = {upstream: {members: {'sqlite3.h': {...selected, sha3_256: 'unused here'}}}};
  assert.deepEqual(requireNativeLinuxLocalHeader(bytes, sqlite, sourceRecipe), selected);
  for (const [header, receipt, recipe] of [
    [Buffer.from('changed header'), sqlite, sourceRecipe], [bytes, {}, sourceRecipe], [bytes, sqlite, {}],
    [bytes, {stage: {outputs: {'sqlite3.h': {...selected, bytes: 1}}}}, sourceRecipe],
    [bytes, sqlite, {upstream: {members: {'sqlite3.h': {...selected, sha256: 'b'.repeat(64)}}}}],
  ]) assert.throws(() => requireNativeLinuxLocalHeader(header, receipt, recipe));
});

test('final metadata selection refuses Remote, foreign source/target and missing explicit version evidence', () => {
  const plan = planNativeLinuxLocalProduction(options, context);
  const record = {sourceSha, platform: 'linux-x64-gnu', localRuntime: {path: 'local-runtime.json'},
    packageVersion: options.packageVersion, binarySha256: 'b'.repeat(64), binaryBytes: 1,
    packageVersionObservation: {argv: ['--version'], stdout: options.packageVersion + '\n', code: 0, signal: null,
      binarySha256: 'b'.repeat(64), binaryBytes: 1, buildInputSha256: 'c'.repeat(64)}};
  for (const patch of [{sourceSha: 'b'.repeat(40)}, {platform: 'darwin-arm64'}, {localRuntime: undefined},
    {localRuntime: null}, {packageVersion: '0.0.0'}, {packageVersionObservation: undefined}])
    assert.throws(() => requireNativeLinuxLocalArtifact({...record, ...patch}, plan));
});

function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-linux-local-entry-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const sourceRoot = join(root, 'source'); mkdirSync(sourceRoot);
  const put = (path, data, mode) => {mkdirSync(dirname(path), {recursive: true}); writeFileSync(path, data, {mode}); return identity(Buffer.from(data));};
  const selected = {...options, outputDirectory: join(root, 'output'), clang: join(root, 'clang-real'),
    sqliteArchive: join(root, 'sqlite.zip'), opensslPackageArchives: [join(root, 'dev.deb'), join(root, 'license.deb')]};
  const plan = planNativeLinuxLocalProduction(selected, {sourceRoot});
  const f = receipts(plan), header = Buffer.from('synthetic original header DATA\n');
  for (const path of Object.keys(f.inputs)) f.inputs[path] = put(path, 'synthetic original ' + path, 0o700);
  f.crypto.package_archives = selected.opensslPackageArchives.map(path => ({path, ...f.inputs[path]}));
  f.sqlite.stage = {outputs: {'sqlite3.h': identity(header)}};
  put(join(sourceRoot, 'packages/python-local-runtime/native/sqlite-component/source.json'),
    wire({upstream: {members: {'sqlite3.h': identity(header)}}}));
  const previousMoon = process.env.MOON_HOME;
  process.env.MOON_HOME = join(root, 'selected-moon');
  t.after(() => {if (previousMoon === undefined) delete process.env.MOON_HOME; else process.env.MOON_HOME = previousMoon;});
  const calls = [];
  let stop;
  const execute = (command, values, settings) => {
    if (command === 'git') return values[0] === 'rev-parse' ? sourceSha + '\n' : '';
    if (command === 'sh') {
      assert.deepEqual(values, ['-c', 'command -v clang']);
      return join(plan.directories['compiler-bin'], 'clang') + '\n';
    }
    const step = plan.commands.find(item => item.args[0] === values[0]);
    assert(step, 'No substitute or fallback command is permitted');
    assert.equal(command, step.command); assert.deepEqual(values, step.args);
    assert.equal(settings.timeout, step.timeoutMs); assert.equal(settings.cwd, sourceRoot);
    calls.push({phase: step.phase, settings});
    if (step.phase === stop) throw new Error('selected ' + stop + ' failed');
    if (step.phase === 'sqlite') {
      put(join(plan.directories.sqlite, 'process-producer.json'), wire(f.sqlite));
      put(join(plan.directories.sqlite, 'source/sqlite3.h'), header);
    } else if (step.phase === 'crypto') put(join(plan.directories.crypto, 'producer.json'), wire(f.crypto));
    return '';
  };
  return {root, sourceRoot, selected, plan, f, header, put, calls, execute, stopAt: phase => {stop = phase;}};
}

test('failed existing stages stop in order with no retries or Remote fallback', async t => {
  for (const phase of ['sqlite', 'crypto', 'recipe', 'artifact']) {
    const f = fixture(t); f.stopAt(phase);
    await assert.rejects(produceNativeCliLinuxLocal(f.selected, {sourceRoot: f.sourceRoot, execute: f.execute}),
      new RegExp('selected ' + phase + ' failed', 'u'));
    assert.deepEqual(f.calls.map(call => call.phase), ['sqlite', 'crypto', 'recipe', 'artifact'].slice(0,
      ['sqlite', 'crypto', 'recipe', 'artifact'].indexOf(phase) + 1));
    assert(!existsSync(join(f.plan.directories.artifact, 'artifact.json')));
  }
});

test('Native sees only the captured header and the exact original compiler; a missing final artifact cannot succeed', async t => {
  const f = fixture(t), previous = {};
  for (const key of ['CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH']) {
    previous[key] = process.env[key]; process.env[key] = '/ambient/unselected';
  }
  t.after(() => {for (const [key, value] of Object.entries(previous)) {
    if (value === undefined) delete process.env[key]; else process.env[key] = value;
  }});
  await assert.rejects(produceNativeCliLinuxLocal(f.selected, {sourceRoot: f.sourceRoot, execute: f.execute}), /ENOENT/u);
  assert.deepEqual(f.calls.map(call => call.phase), ['sqlite', 'crypto', 'recipe', 'artifact']);
  for (const {phase, settings: {env}} of f.calls) {
    assert.equal(env.C_INCLUDE_PATH, phase === 'artifact' ? f.plan.directories.include : undefined);
    for (const key of ['CPATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH']) assert.equal(env[key], undefined);
    assert.equal(env.PATH.split(':')[0], f.plan.directories['compiler-bin']);
  }
  assert.equal(realpathSync(join(f.plan.directories['compiler-bin'], 'clang')), f.selected.clang);
  assert.deepEqual(readFileSync(join(f.plan.directories.include, 'sqlite3.h')), f.header);
});

test('dirty or wrong source, existing output, aliases and receipt contradictions fail closed', async t => {
  for (const kind of ['dirty', 'source', 'output', 'compiler-alias', 'archive-alias', 'target', 'receipt', 'header']) {
    const f = fixture(t);
    if (kind === 'output') mkdirSync(f.selected.outputDirectory);
    if (kind === 'compiler-alias' || kind === 'archive-alias') {
      const field = kind === 'compiler-alias' ? 'clang' : 'sqliteArchive';
      const alias = join(f.root, 'alias'); symlinkSync(f.selected[field], alias); f.selected[field] = alias;
    }
    if (kind === 'target') f.f.crypto.target = 'aarch64-apple-darwin';
    if (kind === 'receipt') f.f.crypto.package_archives[1].sha256 = 'b'.repeat(64);
    if (kind === 'header') f.f.sqlite.stage.outputs['sqlite3.h'].sha256 = 'b'.repeat(64);
    const execute = (command, values, settings) => {
      if (command === 'git' && kind === 'dirty' && values[0] === 'status') return ' M changed\n';
      if (command === 'git' && kind === 'source' && values[0] === 'rev-parse') return 'b'.repeat(40) + '\n';
      return f.execute(command, values, settings);
    };
    await assert.rejects(produceNativeCliLinuxLocal(f.selected, {sourceRoot: f.sourceRoot, execute}));
    assert(!f.calls.some(call => call.phase === 'recipe' || call.phase === 'artifact'));
  }
});

test('changed original input between components stops before the next stage', async t => {
  const f = fixture(t);
  const execute = (command, values, settings) => {
    const result = f.execute(command, values, settings);
    if (command === 'python3' && values[0].endsWith('/produce-python-sqlite-component.py'))
      f.put(f.selected.opensslPackageArchives[0], 'changed original archive');
    return result;
  };
  await assert.rejects(produceNativeCliLinuxLocal(f.selected, {sourceRoot: f.sourceRoot, execute}), /Original input changed/u);
  assert.deepEqual(f.calls.map(call => call.phase), ['sqlite']);
});
