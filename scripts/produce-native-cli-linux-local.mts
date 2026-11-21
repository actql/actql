// Selected Linux Local production only. Run beneath the caller's existing
// bounded guard; this entrance does not authorize a build, install or release.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {accessSync, constants, lstatSync, mkdirSync, realpathSync, symlinkSync, writeFileSync} from 'node:fs';
import {delimiter, dirname, isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {nativeCliCompileBudget} from './native-cli-artifact.mjs';
import {admitNativeArtifact, requireNativePackageVersion} from './native-cli-artifact-reader.mjs';
import {nativePackageVersion} from './native-cli-version.mjs';
import {original, requireNativeLocalHeader} from './native-cli-original-input.mjs';

type Options = {sourceSha: string; packageVersion: string; outputDirectory: string; clang: string;
  sqliteArchive: string; opensslPackageArchives: string[]; systemHeaderRoots?: string[]; componentSeconds?: number; compileSeconds?: number};
type Plan = ReturnType<typeof planNativeLinuxLocalProduction>;
type Identity = ReturnType<typeof original>['identity'];
type Artifact = Awaited<ReturnType<typeof admitNativeArtifact>>;
type ComponentReceipt = {target?: unknown; compiler_target: string; loaded?: unknown; initialized?: unknown;
  inputs?: Record<string, unknown>};
type SqliteReceipt = ComponentReceipt & Parameters<typeof requireNativeLocalHeader>[1] & {source_sha?: unknown};
type CryptoReceipt = ComponentReceipt & {source?: unknown; package_archives?: (Identity & {path: string})[]};
type ProducerHost = Pick<NodeJS.Process, 'platform' | 'arch' | 'report'>;
type ProducerPorts = {execute?: typeof execFileSync; sourceRoot?: string; host?: ProducerHost};

const repository = fileURLToPath(new URL('../', import.meta.url));
const platform = 'linux-x64-gnu', target = 'x86_64-unknown-linux-gnu';
const usage = 'Required: --source SHA --package-version VERSION --output NEW_ABSOLUTE_DIRECTORY ' +
  '--clang REAL_ABSOLUTE_CLANG --sqlite-archive ORIGINAL_ZIP ' +
  '--openssl-package-archive DEV_DEB --openssl-package-archive COPYRIGHT_DEB ' +
  '[--component-seconds 1..1800] [--compile-seconds 1..86400] ' +
  '[--system-header-root /usr/lib/linux/uapi]';
const absolute = (path: unknown, label: string) => {
  assert(typeof path === 'string' && isAbsolute(path) && resolve(path) === path &&
    !/[\0\r\n:]/u.test(path), `${label} requires an explicit canonical absolute path`);
  return path;
};
const inside = (path: string, parent: string) => parent === '/' || path === parent || path.startsWith(parent + '/');

export function parseNativeLinuxLocalArguments(args: readonly string[]) {
  const flags = {'--source': 'sourceSha', '--package-version': 'packageVersion', '--output': 'outputDirectory',
    '--clang': 'clang', '--sqlite-archive': 'sqliteArchive', '--component-seconds': 'componentSeconds',
    '--compile-seconds': 'compileSeconds', '--openssl-package-archive': 'opensslPackageArchives',
    '--system-header-root': 'systemHeaderRoots'};
  assert(Array.isArray(args) && args.length % 2 === 0, usage);
  const options: Record<string, string | number | string[]> = {};
  for (let i = 0; i < args.length; i += 2) {
    const key = Object.hasOwn(flags, args[i]) ? flags[args[i] as keyof typeof flags] : undefined, value = args[i + 1];
    assert(key && typeof value === 'string' && value && !value.startsWith('--'), usage);
    if (key === 'opensslPackageArchives' || key === 'systemHeaderRoots') ((options[key] ??= []) as string[]).push(value);
    else {
      assert(!Object.hasOwn(options, key), `Duplicate argument: ${args[i]}`);
      if (key.endsWith('Seconds')) {
        assert.match(value, /^[1-9][0-9]*$/u, 'Budgets must be bounded positive integers');
        options[key] = Number(value);
      } else options[key] = value;
    }
  }
  // Planning validates required selections as well as the finite envelopes.
  planNativeLinuxLocalProduction(options as unknown as Options);
  return options as unknown as Options;
}

export function planNativeLinuxLocalProduction(options: Options, {sourceRoot = resolve(repository), node = process.execPath} = {}) {
  assert(options && typeof options === 'object' && !Array.isArray(options));
  const allowed = ['sourceSha', 'packageVersion', 'outputDirectory', 'clang', 'sqliteArchive',
    'opensslPackageArchives', 'systemHeaderRoots', 'componentSeconds', 'compileSeconds'];
  assert(Object.keys(options).every(key => allowed.includes(key)), 'Unknown Local production selection');
  const {sourceSha, clang, sqliteArchive, outputDirectory, opensslPackageArchives,
    componentSeconds = 600, compileSeconds = 900, systemHeaderRoots = []} = options;
  assert.match(sourceSha, /^[a-f0-9]{40}$/u, 'Exact full source SHA required');
  const packageVersion = nativePackageVersion(options.packageVersion);
  for (const [label, path] of Object.entries({sourceRoot, node, clang, sqliteArchive, outputDirectory})) absolute(path, label);
  assert(!inside(outputDirectory, sourceRoot) && !inside(sourceRoot, outputDirectory), 'Output must be outside the source checkout');
  assert(Array.isArray(opensslPackageArchives) && opensslPackageArchives.length === 2,
    'Both original Ubuntu Crypto package archives are required, development package first');
  for (const path of opensslPackageArchives) absolute(path, 'OpenSSL package archive');
  const inputs = [clang, sqliteArchive, ...opensslPackageArchives];
  assert.equal(new Set(inputs).size, inputs.length, 'Compiler and original archives must be distinct');
  assert(inputs.every(path => !inside(path, outputDirectory)), 'Original inputs cannot be inside fresh output');
  assert(Array.isArray(systemHeaderRoots) && (systemHeaderRoots.length === 0 ||
    (systemHeaderRoots.length === 1 && systemHeaderRoots[0] === '/usr/lib/linux/uapi')),
  'Only the explicit additional Linux UAPI header root is supported');
  assert(Number.isSafeInteger(componentSeconds) && componentSeconds > 0 && componentSeconds <= 1800,
    'componentSeconds must be an integer from 1 to 1800');
  const compileBudget = nativeCliCompileBudget(compileSeconds, true);
  const directories = Object.fromEntries(['sqlite', 'crypto', 'recipe', 'artifact', 'compiler-bin', 'include']
    .map(name => [name, join(outputDirectory, name)] as const));
  const extraHeaders = systemHeaderRoots.flatMap(path => ['--system-header-root', path]);
  const command = (phase: string, executable: string, args: string[], timeoutMs: number) => ({phase, command: executable, args, timeoutMs});
  return {sourceSha, packageVersion, sourceRoot, outputDirectory, clang, sqliteArchive,
    opensslPackageArchives: [...opensslPackageArchives], directories,
    commands: [
      command('sqlite', 'python3', [join(sourceRoot, 'scripts/produce-python-sqlite-component.py'),
        '--source', sourceSha, '--archive', sqliteArchive, '--process-provider', '--process-target', platform,
        '--clang', clang, '--destination', directories.sqlite, '--seconds', String(componentSeconds), ...extraHeaders],
      componentSeconds * 1000),
      command('crypto', 'python3', [join(sourceRoot, 'scripts/produce-native-crypto-component.py'),
        '--output', directories.crypto, '--target', 'linux-x64', '--clang', clang,
        ...opensslPackageArchives.flatMap(path => ['--openssl-package-archive', path]),
        '--seconds', String(componentSeconds), ...extraHeaders], componentSeconds * 1000),
      command('recipe', node, [join(sourceRoot, 'scripts/native-cli-linux-local-recipe.mjs'),
        '--source', sourceSha, '--sqlite-component', directories.sqlite, '--crypto-component', directories.crypto,
        '--output', directories.recipe], 120000),
      // The extra finite allowance covers the ordinary producer's preparation,
      // version observation and ABI inspection outside its compilation timeout.
      command('artifact', node, [join(sourceRoot, 'scripts/native-cli-artifact.mjs'), directories.artifact,
        '--local-runtime-recipe', join(directories.recipe, 'local-runtime-recipe.json'),
        '--package-version', packageVersion, '--compile-seconds', String(compileBudget.seconds)],
      compileBudget.timeoutMs + 120000),
    ]};
}


const readJson = <T,>(path: string): T => JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(original(path, 8 * 1024 * 1024, true).raw)) as T;

// Bind the caller's selections to the completed component DATA. The existing
// recipe assembler remains responsible for full component and source admission.
export function requireNativeLinuxLocalComponentSelection(plan: Plan, {sqlite, crypto}: {sqlite: SqliteReceipt; crypto: CryptoReceipt}, inputs: Record<string, Identity>) {
  assert.equal(sqlite.source_sha, plan.sourceSha); assert.equal(crypto.source, plan.sourceSha);
  for (const receipt of [sqlite, crypto]) {
    assert.equal(receipt.target, target);
    assert.match(receipt.compiler_target, /^x86_64-(?:[A-Za-z0-9_.]+-)?linux-gnu$/u);
    assert.equal(receipt.loaded, false); assert.equal(receipt.initialized, false);
    assert(inputs[plan.clang]); assert.deepEqual(receipt.inputs?.[plan.clang], inputs[plan.clang], 'Selected compiler input mismatch');
  }
  assert(inputs[plan.sqliteArchive]);
  assert.deepEqual(sqlite.inputs?.[plan.sqliteArchive], inputs[plan.sqliteArchive], 'Selected SQLite archive input mismatch');
  assert.equal(crypto.package_archives?.length, 2, 'Original archive-input Crypto receipts required');
  for (const [index, path] of plan.opensslPackageArchives.entries()) {
    assert(inputs[path]); assert.deepEqual(crypto.inputs?.[path], inputs[path], 'Selected Crypto archive input mismatch');
    const recorded: NonNullable<CryptoReceipt['package_archives']>[number] = crypto.package_archives![index];
    assert.equal(recorded.path, path);
    assert.deepEqual({bytes: recorded.bytes, sha256: recorded.sha256}, inputs[path]);
  }
}

export {requireNativeLocalHeader as requireNativeLinuxLocalHeader} from './native-cli-original-input.mjs';

export function requireNativeLinuxLocalArtifact(record: Artifact, plan: Plan) {
  assert.equal(record.sourceSha, plan.sourceSha); assert.equal(record.platform, platform);
  assert(record.localRuntime && typeof record.localRuntime === 'object', 'Selected Linux production requires Local runtime metadata');
  return requireNativePackageVersion(record, plan.packageVersion);
}

export async function produceNativeCliLinuxLocal(options: Options, {execute = execFileSync, sourceRoot = resolve(repository), host = process}: ProducerPorts = {}) {
  const plan = planNativeLinuxLocalProduction(options, {sourceRoot});
  assert.equal(host.platform, 'linux'); assert.equal(host.arch, 'x64');
  assert((host.report.getReport() as {header: {glibcVersionRuntime?: string}}).header.glibcVersionRuntime, 'Linux GNU producer required');
  const clean = () => {
    const git = (args: readonly string[]) => execute('git', args, {cwd: sourceRoot, encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024}).trim();
    assert.equal(git(['rev-parse', 'HEAD']), plan.sourceSha, 'Exact current source required');
    assert.equal(git(['status', '--porcelain', '--untracked-files=all']), '', 'Clean committed source required');
  };
  clean();
  assert.equal(realpathSync(dirname(plan.outputDirectory)), dirname(plan.outputDirectory), 'Original output parent required');
  try {lstatSync(plan.outputDirectory); assert.fail('Fresh output directory required');}
  catch (error) {if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;}
  assert.equal(realpathSync(plan.clang), plan.clang, 'Select the real compiler, not a compiler alias');
  accessSync(plan.clang, constants.X_OK);
  const selections: readonly (readonly [string, number])[] = [[plan.clang, 512 * 1024 * 1024], [plan.sqliteArchive, 5 * 1024 * 1024],
    ...plan.opensslPackageArchives.map(path => [path, 16 * 1024 * 1024] as const),
    [join(sourceRoot, 'packages/python-local-runtime/native/sqlite-component/source.json'), 65536]];
  const inputs = Object.fromEntries(selections.map(([path, maximum]) => [path, original(path, maximum).identity]));
  const verifyInputs = () => {
    for (const [path, maximum] of selections) assert.deepEqual(original(path, maximum).identity, inputs[path], `Original input changed: ${path}`);
  };
  const environment = {...process.env};
  // Never mix the explicitly captured header with ambient include overrides.
  for (const key of ['CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET']) delete environment[key];
  assert(environment.MOON_HOME && isAbsolute(environment.MOON_HOME), 'Set MOON_HOME to the selected pinned toolchain');
  mkdirSync(plan.outputDirectory, {mode: 0o700});
  mkdirSync(plan.directories['compiler-bin']);
  const compilerLink = join(plan.directories['compiler-bin'], 'clang');
  symlinkSync(plan.clang, compilerLink);
  environment.PATH = `${plan.directories['compiler-bin']}${delimiter}${environment.PATH ?? ''}`;
  let header;
  for (const step of plan.commands) {
    clean(); verifyInputs();
    assert.equal(realpathSync(compilerLink), plan.clang, 'Selected clang alias changed');
    if (step.phase === 'recipe') {
      const sqlite = readJson<SqliteReceipt>(join(plan.directories.sqlite, 'process-producer.json'));
      const crypto = readJson<CryptoReceipt>(join(plan.directories.crypto, 'producer.json'));
      requireNativeLinuxLocalComponentSelection(plan, {sqlite, crypto}, inputs);
      const staged = original(join(plan.directories.sqlite, 'source/sqlite3.h'), 16 * 1024 * 1024, true);
      const sourceRecipe = readJson<Parameters<typeof requireNativeLocalHeader>[2]>(selections.at(-1)![0]);
      header = requireNativeLocalHeader(staged.raw!, sqlite, sourceRecipe);
      mkdirSync(plan.directories.include);
      writeFileSync(join(plan.directories.include, 'sqlite3.h'), staged.raw!, {flag: 'wx', mode: 0o444});
    }
    if (step.phase === 'artifact') {
      assert(header, 'Original SQLite header selection required before Native compilation');
      assert.deepEqual(original(join(plan.directories.include, 'sqlite3.h'), 16 * 1024 * 1024).identity, header);
      assert.deepEqual(original(join(plan.directories.sqlite, 'source/sqlite3.h'), 16 * 1024 * 1024).identity, header);
      assert.equal(realpathSync(execute('sh', ['-c', 'command -v clang'], {cwd: sourceRoot, env: environment,
        encoding: 'utf8', timeout: 15000, maxBuffer: 65536}).trim()), plan.clang, 'Native must resolve the selected real clang');
    }
    execute(step.command, step.args, {cwd: sourceRoot, env: {...environment,
      ...(step.phase === 'artifact' ? {C_INCLUDE_PATH: plan.directories.include} : {})},
    timeout: step.timeoutMs, stdio: 'inherit'});
  }
  clean(); verifyInputs();
  assert.equal(realpathSync(compilerLink), plan.clang, 'Selected clang alias changed');
  assert.deepEqual(original(join(plan.directories.sqlite, 'source/sqlite3.h'), 16 * 1024 * 1024).identity, header);
  assert.deepEqual(original(join(plan.directories.include, 'sqlite3.h'), 16 * 1024 * 1024).identity, header);
  const artifact = requireNativeLinuxLocalArtifact(await admitNativeArtifact(plan.directories.artifact, plan.sourceSha), plan);
  return {directory: plan.directories.artifact, artifact};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const result = await produceNativeCliLinuxLocal(parseNativeLinuxLocalArguments(process.argv.slice(2)));
    console.log(JSON.stringify({directory: result.directory, sourceSha: result.artifact.sourceSha,
      platform: result.artifact.platform, packageVersion: result.artifact.packageVersion, localRuntime: result.artifact.localRuntime}, null, 2));
  } catch (error) {console.error((error as Error).message); process.exitCode = 1;}
}
