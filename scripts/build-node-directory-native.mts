// Normal Local package delivery of the selected private filesystem binding.
// Build facts are DATA, never operational module/loader or resource admission.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  realpathSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState} from './packed-client-packages.mjs';
import {admitCohort} from './package-release.mjs';

import type {BinaryLike} from 'node:crypto';

type FileFact = {path: string; bytes: number; mode: number; sha256: string};
type HeaderFact = Omit<FileFact, 'mode'>;
// Unchecked producer DATA. Exact shape, file and same-source checks stay below.
type OriginalNative = {platform: string; arch: string; node: string; moduleAbi: string;
  napi: number; source: {path: string; sha256: string}; compilerSha256: string;
  nodeSha256: string; sdkSettingsSha256?: string; headers: HeaderFact[]; binary: HeaderFact};
type Engine = {node: string; v8: string; openssl: string; platform: string; arch: string;
  libraries: NodeJS.ProcessVersions | Record<string, string>};
type NativeInput = {version: string; source: ReturnType<typeof sourceBinding>;
  engine: Engine; compatibilityEngine?: Engine; original: FileFact; binary: FileFact};
type Selection = {version: string; inputs: {path: string; sha256: string}[]};
type Target = {platform: string; arch: string; engine: Engine; compatibilityEngine?: Engine; original: OriginalNative;
  originalSource: string; originalSha256: string; inputSha256: string};
type BuildOptions = {root?: string; destination?: string; check?: boolean};
type ExportOptions = BuildOptions & {output?: string};
type AssemblyOptions = BuildOptions & {selection?: string; expectedSha256?: string};

const repository = fileURLToPath(new URL('../', import.meta.url));
const darwinSourcePath = 'adapters/host-node/native/directory-darwin.c';
const linuxSourcePath = 'adapters/host-node/native/local-files-linux.c';
const helperPath = 'adapters/host-node/native/napi-filesystem-helpers.inc';
const platformPath = 'adapters/connectors/local/site/root-filesystem-platform.inc';
const localFilesPath = 'adapters/connectors/local/site/root-filesystem.inc';
const localWriterPath = 'adapters/connectors/local/site/root-file-writer.inc';
export const directoryNativeDescriptor = '_build/native/directory-original.json';
const sha = (bytes: BinaryLike) => createHash('sha256').update(bytes).digest('hex');
const fail: (code: string) => never = code => { throw new Error(code); };
const inside = (root: string, file: string) => {
  const suffix = relative(root, file);
  return suffix === '' || !isAbsolute(suffix) && suffix !== '..' && !suffix.startsWith('..' + sep);
};
const regular = (file: string) => {
  if (!lstatSync(file).isFile()) fail('AliasedDirectoryNativeInput');
  return readFileSync(file);
};
const tool = (file: string, args: readonly string[]) => execFileSync(file, args,
  {encoding: 'utf8', timeout: 60000, maxBuffer: 4 * 1024 * 1024}).trim();
const optionalStat = (path: string) => {
  try { return lstatSync(path); }
  catch (cause) { if ((cause as NodeJS.ErrnoException).code !== 'ENOENT') throw cause; }
};

const inputManifest = 'native-input.json';
const hashPattern = /^[a-f0-9]{64}$/u;
const nativeTargets = new Map([['darwin-arm64', '_build/native/directory-darwin-arm64.node'],
  ['linux-x64', '_build/native/local-files-linux-x64.node']]);
export const ordinaryCompatibilityNode = '24.21.0';
const recipePaths = [darwinSourcePath, linuxSourcePath, helperPath, platformPath, localFilesPath,
  localWriterPath, 'scripts/build-node-directory-native.mjs', 'scripts/build-local-node-adapters.mjs',
  'scripts/initial-control-package-images.mjs', 'toolchain.json', 'release/client-cohort.json',
  'packages/local-node/package.json'];
const exactKeys = (value: unknown, keys: readonly string[]) => {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      JSON.stringify(Object.keys(value).sort()) !== JSON.stringify([...keys].sort())) {
    fail('InvalidDirectoryNativeInput');
  }
};
const concrete = (path: unknown): path is string => typeof path === 'string' && path.length > 0 && path.length <= 4096 &&
  !isAbsolute(path) && !path.includes('\\') && !/[\u0000-\u001f\u007f]/u.test(path) &&
  path.split('/').every(part => part !== '' && part !== '.' && part !== '..');
function inputFile(root: string, path: string, maxBytes = 64 * 1024 * 1024) {
  if (!concrete(path) || !lstatSync(root).isDirectory()) fail('InvalidDirectoryNativeInput');
  const parts = path.split('/');
  for (let index = 0; index < parts.length; index++) {
    const stat = lstatSync(join(root, ...parts.slice(0, index + 1)));
    if (index === parts.length - 1 ? !stat.isFile() : !stat.isDirectory()) fail('AliasedDirectoryNativeInput');
    if (index === parts.length - 1 && (stat.size < 1 || stat.size > maxBytes)) fail('InvalidDirectoryNativeInput');
  }
  return readFileSync(join(root, path));
}
function sourceBinding(root: string) {
  const state = checkoutState(root);
  if (!state.clean) fail('DirtyDirectoryNativeSource');
  const cohort = admitCohort(JSON.parse(inputFile(root, 'release/client-cohort.json') as unknown as string));
  return {revision: state.revision, packageVersion: cohort.packageVersion,
    recipe: recipePaths.map(path => ({path, sha256: sha(inputFile(root, path))}))};
}
function fileFact(root: string, path: string) {
  const bytes = inputFile(root, path), stat = lstatSync(join(root, path));
  return {path, bytes: bytes.length, mode: stat.mode & 0o777, sha256: sha(bytes)};
}
function verifiedFile(root: string, fact: FileFact) {
  exactKeys(fact, ['path', 'bytes', 'mode', 'sha256']);
  if (!Number.isSafeInteger(fact.bytes) || fact.bytes < 1 || ![0o644, 0o755].includes(fact.mode) ||
      !hashPattern.test(fact.sha256)) fail('InvalidDirectoryNativeInput');
  const bytes = inputFile(root, fact.path);
  if (bytes.length !== fact.bytes || sha(bytes) !== fact.sha256 ||
      (lstatSync(join(root, fact.path)).mode & 0o777) !== fact.mode) fail('ChangedDirectoryNativeInput');
  return bytes;
}
function validateOriginal(original: OriginalNative, bytes: Buffer, target: string, root: string) {
  const path = nativeTargets.get(target), sourcePath = target === 'linux-x64' ? linuxSourcePath : darwinSourcePath;
  exactKeys(original, ['platform', 'arch', 'node', 'moduleAbi', 'napi', 'source', 'compilerSha256',
    'nodeSha256', ...(target === 'darwin-arm64' ? ['sdkSettingsSha256'] : []), 'headers', 'binary']);
  exactKeys(original.source, ['path', 'sha256']); exactKeys(original.binary, ['path', 'bytes', 'sha256']);
  if (path === undefined || `${original.platform}-${original.arch}` !== target || original.node !== '22.22.0' ||
      original.napi !== 8 || original.moduleAbi !== '127' || original.source.path !== sourcePath ||
      !hashPattern.test(original.source.sha256) || !hashPattern.test(original.compilerSha256) ||
      !hashPattern.test(original.nodeSha256) || target === 'darwin-arm64' && !hashPattern.test(original.sdkSettingsSha256!) ||
      original.binary.path !== path || original.binary.bytes !== bytes.length || original.binary.sha256 !== sha(bytes) ||
      !Array.isArray(original.headers) || original.headers.length < 1 || original.headers.length > 4096) {
    fail('InvalidDirectoryNativeOriginal');
  }
  // Compiler dependency output includes the selected C translation unit and
  // these exact shared Source includes as well as toolchain headers. Keep
  // their original paths and verify them against this same source checkout.
  const sourceFiles = new Set([sourcePath, helperPath, platformPath, localFilesPath, localWriterPath]);
  const names = new Set<string>();
  for (const fact of original.headers) {
    exactKeys(fact, ['path', 'bytes', 'sha256']);
    const source = sourceFiles.has(fact.path);
    if (!concrete(fact.path) || !source && !/^(?:node|compiler|system|sdk)\//u.test(fact.path) || names.has(fact.path) ||
        !Number.isSafeInteger(fact.bytes) || fact.bytes < 0 || !hashPattern.test(fact.sha256)) {
      fail('InvalidDirectoryNativeOriginal');
    }
    if (source) {
      const bytes = inputFile(root, fact.path);
      if (fact.bytes !== bytes.length || fact.sha256 !== sha(bytes)) fail('ChangedDirectoryNativeInput');
    }
    names.add(fact.path);
  }
}
function validateEngine(engine: Engine, original: Pick<OriginalNative, 'platform' | 'arch'> & {node?: string}, node = original.node) {
  exactKeys(engine, ['node', 'v8', 'openssl', 'platform', 'arch', 'libraries']);
  if (engine.node !== node || engine.platform !== original.platform || engine.arch !== original.arch ||
      engine.libraries === null || typeof engine.libraries !== 'object' || Array.isArray(engine.libraries) ||
      Object.keys(engine.libraries).length > 64 || Object.values(engine.libraries)
        .some(value => typeof value !== 'string' || value.length > 256) ||
      (['node', 'v8', 'openssl'] as const).some(name => typeof engine[name] !== 'string' || engine[name] !== engine.libraries[name])) {
    fail('InvalidDirectoryNativeEngine');
  }
}

// Observe the actual separately installed compatibility runtime on this
// producer. Only the pinned toolchain may supply its executable. The native
// addon itself is still built and attested by the primary Node toolchain.
export function observeOrdinaryCompatibilityEngine() {
  const executable = process.env.ACTQL_NODE_ORDINARY_COMPATIBILITY_EXECUTABLE;
  if (executable === undefined) return undefined;
  if (!isAbsolute(executable) || realpathSync(executable) !== executable ||
      !lstatSync(executable).isFile()) fail('InvalidDirectoryNativeEngine');
  const original = lstatSync(executable, {bigint: true});
  const engine = JSON.parse(execFileSync(executable, ['-e', `
    const {node, v8, openssl} = process.versions;
    process.stdout.write(JSON.stringify({node, v8, openssl, platform: process.platform,
      arch: process.arch, libraries: process.versions}));
  `], {env: {}, encoding: 'utf8', timeout: 5000, maxBuffer: 16384}));
  const observed = lstatSync(executable, {bigint: true});
  for (const key of ['dev', 'ino', 'size', 'mode', 'mtimeNs', 'ctimeNs'] as const) {
    if (original[key] !== observed[key]) fail('ChangedDirectoryNativeInput');
  }
  validateEngine(engine, process, ordinaryCompatibilityNode);
  return engine;
}

// This exports immutable build DATA, not a trusted artifact or a loading
// permission. CI must authenticate its producer/source and pin this manifest
// before a different platform's normal prepack can select it.
export function exportNodeDirectoryNativeInput({root = repository,
  destination = join(root, 'packages/local-node'), output}: ExportOptions = {}) {
  if (typeof output !== 'string' || !isAbsolute(output)) fail('InvalidDirectoryNativeExport');
  const source = sourceBinding(root), target = `${process.platform}-${process.arch}`;
  const path = nativeTargets.get(target);
  if (path === undefined) fail('UnsupportedDirectoryNativeExport');
  if (readdirSync(join(destination, '_build/native')).sort().join('\n') !==
      [path.split('/').at(-1), 'directory-original.json'].sort().join('\n')) fail('StaleDirectoryNativeOutput');
  const bytes = inputFile(destination, path), descriptor = inputFile(destination, directoryNativeDescriptor, 4 * 1024 * 1024);
  const original = JSON.parse(descriptor as unknown as string) as OriginalNative;
  validateOriginal(original, bytes, target, root);
  if (original.source.sha256 !== sha(inputFile(root, original.source.path)) ||
      original.nodeSha256 !== sha(regular(process.execPath))) fail('ChangedDirectoryNativeInput');
  const engine = {node: process.versions.node, v8: process.versions.v8, openssl: process.versions.openssl,
    platform: process.platform, arch: process.arch, libraries: {...process.versions}};
  validateEngine(engine, original);
  const compatibilityEngine = observeOrdinaryCompatibilityEngine();
  const binary = {...fileFact(destination, path), path: path.split('/').at(-1)!};
  const record = {...fileFact(destination, directoryNativeDescriptor), path: 'directory-original.json'};
  if (binary.sha256 !== sha(bytes) || record.sha256 !== sha(descriptor)) fail('ChangedDirectoryNativeInput');
  if (JSON.stringify(sourceBinding(root)) !== JSON.stringify(source)) fail('DirectoryNativeBuildInputChanged');
  mkdirSync(output);
  for (const [fact, value] of [[binary, bytes], [record, descriptor]] as const) {
    writeFileSync(join(output, fact.path), value, {flag: 'wx', mode: fact.mode});
    chmodSync(join(output, fact.path), fact.mode);
  }
  const manifest = {version: 'actql-node-directory-native-input/0.1', source, engine,
    ...(compatibilityEngine === undefined ? {} : {compatibilityEngine}), original: record, binary};
  const contents = Buffer.from(JSON.stringify(manifest, null, 2) + '\n');
  writeFileSync(join(output, inputManifest), contents, {flag: 'wx'});
  return {manifest: join(output, inputManifest), sha256: sha(contents)};
}

// The explicit digest pins caller-selected DATA; it is not producer
// authentication. No wildcard, directory scan or installed package supplies
// a second target. Both records must be supplied by the selected CI cohort.
export function assembleNodeDirectoryNative({root = repository,
  destination = join(root, 'packages/local-node'), selection, expectedSha256, check = false}: AssemblyOptions = {}) {
  if (typeof selection !== 'string' || !isAbsolute(selection) || !hashPattern.test(expectedSha256 as string)) {
    fail('InvalidDirectoryNativeSelection');
  }
  const base = dirname(selection), selectionBytes = inputFile(base, selection.split(sep).at(-1)!, 4 * 1024 * 1024);
  if (sha(selectionBytes) !== expectedSha256) fail('ChangedDirectoryNativeSelection');
  const chosen = JSON.parse(selectionBytes as unknown as string) as Selection;
  exactKeys(chosen, ['version', 'inputs']);
  if (chosen.version !== 'actql-node-directory-native-selection/0.1' || !Array.isArray(chosen.inputs) ||
      chosen.inputs.length !== 2) fail('InvalidDirectoryNativeSelection');
  const source = sourceBinding(root), targets: Target[] = [], outputs = new Map<string, Buffer>(), modes = new Map<string, number>(), seen = new Set<string>();
  for (const input of chosen.inputs) {
    exactKeys(input, ['path', 'sha256']);
    if (!hashPattern.test(input.sha256)) fail('InvalidDirectoryNativeSelection');
    const manifestBytes = inputFile(base, input.path, 4 * 1024 * 1024);
    if (sha(manifestBytes) !== input.sha256) fail('ChangedDirectoryNativeInput');
    const manifest = JSON.parse(manifestBytes as unknown as string) as NativeInput;
    const hasCompatibility = Object.hasOwn(manifest, 'compatibilityEngine');
    exactKeys(manifest, ['version', 'source', 'engine', 'original', 'binary',
      ...(hasCompatibility ? ['compatibilityEngine'] : [])]);
    if (manifest.version !== 'actql-node-directory-native-input/0.1' ||
        JSON.stringify(manifest.source) !== JSON.stringify(source)) fail('WrongDirectoryNativeSource');
    const selected = join(base, dirname(input.path));
    const descriptor = verifiedFile(selected, manifest.original), bytes = verifiedFile(selected, manifest.binary);
    if (!Buffer.from(descriptor.toString('utf8')).equals(descriptor)) fail('InvalidDirectoryNativeOriginal');
    const original = JSON.parse(descriptor as unknown as string) as OriginalNative, target = `${original.platform}-${original.arch}`;
    validateOriginal(original, bytes, target, root); validateEngine(manifest.engine, original);
    if (hasCompatibility) validateEngine(manifest.compatibilityEngine!, original, ordinaryCompatibilityNode);
    const path = nativeTargets.get(target);
    if (seen.has(target) || manifest.original.path !== 'directory-original.json' ||
        manifest.binary.path !== path?.split('/').at(-1) ||
        original.source.sha256 !== sha(inputFile(root, original.source.path)) ||
        readdirSync(selected).sort().join('\n') !== [inputManifest, manifest.original.path, manifest.binary.path].sort().join('\n')) {
      fail('InvalidDirectoryNativeInput');
    }
    seen.add(target); outputs.set(path!, bytes); modes.set(path!, manifest.binary.mode);
    targets.push({platform: original.platform, arch: original.arch, engine: manifest.engine,
      ...(hasCompatibility ? {compatibilityEngine: manifest.compatibilityEngine} : {}),
      original, originalSource: descriptor.toString('utf8'), originalSha256: manifest.original.sha256,
      inputSha256: input.sha256});
  }
  targets.sort((a, b) => `${a.platform}-${a.arch}` < `${b.platform}-${b.arch}` ? -1 : 1);
  outputs.set(directoryNativeDescriptor, Buffer.from(JSON.stringify({version: 'actql-node-directory-native-cohort/0.1',
    source, targets}, null, 2) + '\n'));
  modes.set(directoryNativeDescriptor, 0o644);
  for (const path of ['_build', '_build/native']) {
    const stat = optionalStat(join(destination, path));
    if (stat !== undefined && !stat.isDirectory()) fail('AliasedDirectoryNativeOutput');
  }
  const directory = join(destination, '_build/native');
  if (existsSync(directory)) for (const name of readdirSync(directory)) {
    if (![...outputs.keys()].some(path => path.split('/').at(-1) === name) ||
        !lstatSync(join(directory, name)).isFile()) fail('StaleDirectoryNativeOutput');
  }
  if (JSON.stringify(sourceBinding(root)) !== JSON.stringify(source) ||
      !inputFile(base, selection.split(sep).at(-1)!).equals(selectionBytes)) fail('DirectoryNativeBuildInputChanged');
  // Re-observe every selected file before the first output write. A refusal
  // leaves the old native output prefix intact.
  for (const input of chosen.inputs) {
    const manifestBytes = inputFile(base, input.path);
    if (sha(manifestBytes) !== input.sha256) fail('ChangedDirectoryNativeInput');
    const manifest = JSON.parse(manifestBytes as unknown as string) as NativeInput, selected = join(base, dirname(input.path));
    verifiedFile(selected, manifest.original); verifiedFile(selected, manifest.binary);
  }
  if (check) {
    for (const [path, bytes] of outputs) if (!inputFile(destination, path).equals(bytes) ||
        (lstatSync(join(destination, path)).mode & 0o777) !== modes.get(path)) fail('StaleDirectoryNativeArtifact');
  } else {
    mkdirSync(directory, {recursive: true});
    const scratch = mkdtempSync(join(directory, '.native-assembly-'));
    try {
      for (const [path, bytes] of outputs) {
        const staged = join(scratch, path.split('/').at(-1)!);
        writeFileSync(staged, bytes); chmodSync(staged, modes.get(path)!);
        renameSync(staged, join(destination, path));
      }
    } finally {rmSync(scratch, {recursive: true});}
  }
  return outputs;
}

function dependencyFiles(text: string) {
  const colon = text.indexOf(':');
  if (colon < 0) fail('InvalidDirectoryNativeDependencies');
  const files = []; let word = '';
  for (let index = colon + 1; index < text.length; index++) {
    const ch = text[index];
    if (ch === '\\') {
      if (++index === text.length) fail('InvalidDirectoryNativeDependencies');
      if (text[index] !== '\n') word += text[index];
    } else if (/\s/u.test(ch)) {
      if (word) { files.push(word); word = ''; }
    } else word += ch;
  }
  if (word) files.push(word);
  return [...new Set(files)];
}

export function buildNodeDirectoryNative({root = repository,
  destination = join(root, 'packages/local-node'), check = false}: BuildOptions = {}) {
  const directory = join(destination, '_build/native');
  const darwin = process.platform === 'darwin' && ['arm64', 'x64'].includes(process.arch);
  const linux = process.platform === 'linux' && process.arch === 'x64';
  const supported = (darwin || linux) && process.versions.node === '22.22.0';
  const sourcePath = linux ? linuxSourcePath : darwinSourcePath;
  const binaryPath = linux ? '_build/native/local-files-linux-x64.node'
    : `_build/native/directory-darwin-${process.arch}.node`;
  const expected = supported ? [binaryPath.split('/').at(-1), 'directory-original.json'] : [];
  for (const path of ['_build', '_build/native']) {
    const selected = join(destination, path);
    const observed = optionalStat(selected);
    if (observed !== undefined && !observed.isDirectory()) fail('AliasedDirectoryNativeOutput');
  }
  if (existsSync(directory)) {
    if (!lstatSync(directory).isDirectory()) fail('AliasedDirectoryNativeOutput');
    for (const name of readdirSync(directory)) {
      if (!expected.includes(name) || !lstatSync(join(directory, name)).isFile()) {
        fail('StaleDirectoryNativeOutput');
      }
    }
  }
  // Unsupported producers do not create a pretend binary or a new public
  // platform restriction. The selected consumer remains unavailable there.
  if (!supported) return new Map<string, Buffer>();
  const source = regular(join(root, sourcePath));
  const compiler = realpathSync(linux ? '/usr/bin/gcc' : tool('/usr/bin/xcrun', ['--find', 'clang']));
  const sdk = linux ? undefined : realpathSync(tool('/usr/bin/xcrun', ['--show-sdk-path']));
  const headers = realpathSync(resolve(dirname(process.execPath), '../include/node'));
  const resources = realpathSync(tool(compiler, [linux ? '-print-file-name=include' : '-print-resource-dir']));
  const compilerBytes = regular(compiler), nodeBytes = regular(process.execPath);
  const sdkSettings = linux ? undefined : regular(join(sdk!, 'SDKSettings.json'));
  // Linux records actual system/compiler headers, not a fabricated Apple SDK.
  const headerRoots = [[headers, 'node'], ...(linux ? [[realpathSync('/usr/include'), 'system']]
    : [[sdk!, 'sdk']]), [resources, 'compiler']] as [string, string][];
  // Some Linux distributions ship the x86 asm headers as individual symlinks
  // into a separately installed kernel UAPI tree. GCC emits those canonical
  // names in dependencies. Admit only the exact installed include aliases,
  // not the whole external directory or arbitrary /usr/lib inputs.
  const systemAliases = new Map<string, string>();
  const asmHeaders = '/usr/include/x86_64-linux-gnu/asm';
  if (linux && existsSync(asmHeaders)) {
    for (const name of readdirSync(asmHeaders).sort()) {
      const file = join(asmHeaders, name);
      if (name.endsWith('.h') && lstatSync(file).isSymbolicLink()) {
        const canonical = realpathSync(file);
        regular(canonical);
        systemAliases.set(canonical, `system/x86_64-linux-gnu/asm/${name}`);
      }
    }
  }
  const sourceFiles = [sourcePath, helperPath, platformPath, localFilesPath, localWriterPath];
  const sourceNames = new Map(sourceFiles.map(path => [realpathSync(join(root, path)), path]));
  const parent = join(root, '_build'); mkdirSync(parent, {recursive: true});
  const scratch = mkdtempSync(join(parent, 'directory-native-build-'));
  let passed = false;
  try {
    const binary = join(scratch, 'directory.node'), dependencies = join(scratch, 'directory.d');
    const before = join(scratch, 'directory-before.d');
    const baseArgs = ['-std=c11', linux ? '-D_GNU_SOURCE' : '-D_DARWIN_C_SOURCE',
      '-Wall', '-Wextra', '-Werror', '-O2',
      ...(linux ? ['-fPIC'] : ['-isysroot', sdk!, '-arch', process.arch === 'x64' ? 'x86_64' : 'arm64']),
      '-DNAPI_VERSION=8', '-DNODE_GYP_MODULE_NAME=actql_directory', '-I', headers];
    const linkArgs = linux ? ['-shared'] : ['-bundle', '-undefined', 'dynamic_lookup'];
    const execution = {timeout: 60000, maxBuffer: 4 * 1024 * 1024,
      env: {PATH: '/usr/bin:/bin', TMPDIR: scratch, ...(linux ? {} : {SDKROOT: sdk})}};
    // No caller flags or ambient include paths can replace this selected
    // module's inputs. The compiler/SDK and every used header are recorded.
    const readFacts = (path: string) => dependencyFiles(readFileSync(path, 'utf8')).map(file => {
      const canonical = realpathSync(file);
      let path = sourceNames.get(canonical) ?? systemAliases.get(canonical);
      if (path === undefined) for (const [base, prefix] of headerRoots) {
        if (inside(base, canonical)) { path = `${prefix}/${relative(base, canonical).split(sep).join('/')}`; break; }
      }
      if (path === undefined) fail('UndeclaredDirectoryNativeHeader');
      const bytes = regular(canonical);
      return {path, bytes: bytes.length, sha256: sha(bytes)};
    }).sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
    execFileSync(compiler, [...baseArgs, '-M', '-MF', before, join(root, sourcePath)], execution);
    const facts = readFacts(before);
    execFileSync(compiler, [...baseArgs, ...linkArgs,
      '-MD', '-MF', dependencies, join(root, sourcePath), '-o', binary], execution);
    if (JSON.stringify(readFacts(dependencies)) !== JSON.stringify(facts)) {
      fail('DirectoryNativeBuildInputChanged');
    }
    if (!regular(join(root, sourcePath)).equals(source) || !regular(compiler).equals(compilerBytes) ||
        !regular(process.execPath).equals(nodeBytes) ||
        !linux && !regular(join(sdk!, 'SDKSettings.json')).equals(sdkSettings!)) {
      fail('DirectoryNativeBuildInputChanged');
    }
    const bytes = regular(binary);
    const original = {platform: process.platform, arch: process.arch, node: process.versions.node,
      moduleAbi: process.versions.modules, napi: 8, source: {path: sourcePath, sha256: sha(source)},
      compilerSha256: sha(compilerBytes), nodeSha256: sha(nodeBytes),
      ...(linux ? {} : {sdkSettingsSha256: sha(sdkSettings!)}), headers: facts,
      binary: {path: binaryPath, bytes: bytes.length, sha256: sha(bytes)}};
    const outputs = new Map([[binaryPath, bytes],
      [directoryNativeDescriptor, Buffer.from(JSON.stringify(original, null, 2) + '\n')]]);
    if (check) {
      for (const [path, expectedBytes] of outputs) {
        if (!regular(join(destination, path)).equals(expectedBytes)) fail('StaleDirectoryNativeArtifact');
      }
    } else {
      mkdirSync(directory, {recursive: true});
      for (const [path, output] of outputs) {
        const staged = join(scratch, path.endsWith('.node') ? 'staged.node' : 'staged.json');
        writeFileSync(staged, output);
        // Never overwrite the inode of an already loaded generated module.
        // Incomplete pair replacement is detectable, not a fresh admission.
        renameSync(staged, join(destination, path));
      }
    }
    passed = true;
    return outputs;
  } finally {
    // Keep a failed compiler's exact generated inputs/output for diagnosis.
    // No native module has been loaded by this build-only operation.
    if (passed) rmSync(scratch, {recursive: true});
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args[0] === '--export') {
    if (args.length !== 2) fail('InvalidDirectoryNativeExport');
    console.log(JSON.stringify(exportNodeDirectoryNativeInput({output: resolve(args[1])})));
  } else {
    if (args.length > 1 || args.length === 1 && args[0] !== '--check') fail('InvalidDirectoryNativeBuild');
    buildNodeDirectoryNative({check: args[0] === '--check'});
  }
}
