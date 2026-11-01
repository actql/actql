// Normal Local package delivery of the selected private filesystem binding.
// Build facts are DATA, never operational module/loader or resource admission.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync,
  realpathSync, renameSync, rmSync, writeFileSync} from 'node:fs';
import {dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const darwinSourcePath = 'adapters/host-node/native/directory-darwin.c';
const linuxSourcePath = 'adapters/host-node/native/local-files-linux.c';
const helperPath = 'adapters/host-node/native/napi-filesystem-helpers.inc';
const platformPath = 'adapters/connectors/local/site/root-filesystem-platform.inc';
const localFilesPath = 'adapters/connectors/local/site/root-filesystem.inc';
const localWriterPath = 'adapters/connectors/local/site/root-file-writer.inc';
export const directoryNativeDescriptor = '_build/native/directory-original.json';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const fail = code => { throw new Error(code); };
const inside = (root, file) => {
  const suffix = relative(root, file);
  return suffix === '' || !isAbsolute(suffix) && suffix !== '..' && !suffix.startsWith('..' + sep);
};
const regular = file => {
  if (!lstatSync(file).isFile()) fail('AliasedDirectoryNativeInput');
  return readFileSync(file);
};
const tool = (file, args) => execFileSync(file, args,
  {encoding: 'utf8', timeout: 60000, maxBuffer: 4 * 1024 * 1024}).trim();
const optionalStat = path => {
  try { return lstatSync(path); }
  catch (cause) { if (cause.code !== 'ENOENT') throw cause; }
};

function dependencyFiles(text) {
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
  destination = join(root, 'packages/local-node'), check = false} = {}) {
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
  if (!supported) return new Map();
  const source = regular(join(root, sourcePath));
  const compiler = realpathSync(linux ? '/usr/bin/gcc' : tool('/usr/bin/xcrun', ['--find', 'clang']));
  const sdk = linux ? undefined : realpathSync(tool('/usr/bin/xcrun', ['--show-sdk-path']));
  const headers = realpathSync(resolve(dirname(process.execPath), '../include/node'));
  const resources = realpathSync(tool(compiler, [linux ? '-print-file-name=include' : '-print-resource-dir']));
  const compilerBytes = regular(compiler), nodeBytes = regular(process.execPath);
  const sdkSettings = linux ? undefined : regular(join(sdk, 'SDKSettings.json'));
  // Linux records actual system/compiler headers, not a fabricated Apple SDK.
  const headerRoots = [[headers, 'node'], ...(linux ? [[realpathSync('/usr/include'), 'system']]
    : [[sdk, 'sdk']]), [resources, 'compiler']];
  // Some Linux distributions ship the x86 asm headers as individual symlinks
  // into a separately installed kernel UAPI tree. GCC emits those canonical
  // names in dependencies. Admit only the exact installed include aliases,
  // not the whole external directory or arbitrary /usr/lib inputs.
  const systemAliases = new Map();
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
      ...(linux ? ['-fPIC'] : ['-isysroot', sdk, '-arch', process.arch === 'x64' ? 'x86_64' : 'arm64']),
      '-DNAPI_VERSION=8', '-DNODE_GYP_MODULE_NAME=actql_directory', '-I', headers];
    const linkArgs = linux ? ['-shared'] : ['-bundle', '-undefined', 'dynamic_lookup'];
    const execution = {timeout: 60000, maxBuffer: 4 * 1024 * 1024,
      env: {PATH: '/usr/bin:/bin', TMPDIR: scratch, ...(linux ? {} : {SDKROOT: sdk})}};
    // No caller flags or ambient include paths can replace this selected
    // module's inputs. The compiler/SDK and every used header are recorded.
    const readFacts = path => dependencyFiles(readFileSync(path, 'utf8')).map(file => {
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
        !linux && !regular(join(sdk, 'SDKSettings.json')).equals(sdkSettings)) {
      fail('DirectoryNativeBuildInputChanged');
    }
    const bytes = regular(binary);
    const original = {platform: process.platform, arch: process.arch, node: process.versions.node,
      moduleAbi: process.versions.modules, napi: 8, source: {path: sourcePath, sha256: sha(source)},
      compilerSha256: sha(compilerBytes), nodeSha256: sha(nodeBytes),
      ...(linux ? {} : {sdkSettingsSha256: sha(sdkSettings)}), headers: facts,
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
  buildNodeDirectoryNative({check: process.argv.includes('--check')});
}
