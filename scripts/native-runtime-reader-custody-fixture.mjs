// Prepare only the failed-constructor custody cases in the existing Native
// filesystem Owner. Injection is confined to its child and two owned files.
import {execFileSync, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync, mkdirSync, readFileSync, realpathSync, writeFileSync} from 'node:fs';
import {isAbsolute, join} from 'node:path';

const sourcePath = root => join(root, 'scripts/fixtures/native-runtime-reader-custody.c');
const flags = () => ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
  ...(process.platform === 'darwin'
    ? ['-dynamiclib', '-arch', 'arm64', '-arch', 'arm64e'] : ['-shared', '-fPIC'])];
const hash = value => createHash('sha256').update(value).digest('hex');
const recipe = (root, compiler) => ({sourceSha256: hash(readFileSync(sourcePath(root))),
  compiler: realpathSync(compiler), compilerSha256: hash(readFileSync(compiler)), flags: flags()});
const physical = library => {
  const stat = lstatSync(library);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.uid !== process.getuid())
    throw new Error('Original Reader fixture library required');
  return {path: library, dev: stat.dev, ino: stat.ino, mode: stat.mode, size: stat.size,
    mtimeMs: stat.mtimeMs, ctimeMs: stat.ctimeMs, sha256: hash(readFileSync(library))};
};

// Compiler DATA only: keep this exec's actual library correspondence separate
// from the stable source/recipe key. A fresh dylib has a new UUID/install path;
// neither is a C object input. The two injected paths are outside compilation.
export function nativeRuntimeReaderCustodyCacheInput(root, compiler, env = process.env) {
  if (process.platform !== 'darwin' || !env.DYLD_INSERT_LIBRARIES || env.LD_PRELOAD) return;
  try {
    const scratch = env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT;
    if (!isAbsolute(scratch) || scratch !== realpathSync(scratch)) return;
    const library = join(scratch, 'runtime-reader-custody.dylib');
    if (env.DYLD_INSERT_LIBRARIES !== library) return;
    const actual = {recipe: recipe(root, compiler), library: physical(library)};
    if (JSON.stringify(actual) !== env.ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_CACHE_PROFILE) return;
    return {source: sourcePath(root), recipeSha256: hash(JSON.stringify(actual.recipe))};
  } catch { return; }
}

export function nativeRuntimeReaderCustodyFixture(root, scratch) {
  if (!['darwin', 'linux'].includes(process.platform)) {
    throw new Error('Native Reader custody injection is unavailable on this platform');
  }
  if (process.env.DYLD_INSERT_LIBRARIES || process.env.LD_PRELOAD) {
    throw new Error('Native Reader custody refuses an existing injection environment');
  }
  for (const name of ['runtime-constructor-pending', 'runtime-constructor-acked']) {
    mkdirSync(join(scratch, name), {mode: 0o700});
    // Seed the authored invalid manifest before injecting the child. The real
    // Writer also inspects committed files, so preparing it inside that child
    // would fail before the Reader constructor under test is reached.
    writeFileSync(join(scratch, name, 'local-runtime.json'), '{}', {flag: 'wx', mode: 0o600});
  }
  const library = join(scratch, process.platform === 'darwin'
    ? 'runtime-reader-custody.dylib' : 'runtime-reader-custody.so');
  // The injected test library also reaches Apple's arm64e compiler/launcher
  // helpers. Both slices serve the same existing Darwin arm64 test profile.
  const compiler = process.platform === 'darwin' && process.env.ACTQL_TEST_NATIVE_CORE_CCACHE !== undefined
    ? execFileSync('/bin/sh', ['-c', 'command -v cc'], {encoding: 'utf8', timeout: 5000}).trim() : undefined;
  const built = spawnSync('cc', [...flags(), sourcePath(root), '-o', library,
    ...(process.platform === 'linux' ? ['-ldl'] : [])], {stdio: 'inherit'});
  if (built.error || built.signal || built.status !== 0) {
    throw new Error(`Native Reader custody fixture compilation failed: ${
      built.error?.message ?? built.signal ?? built.status}`);
  }
  return {ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT: scratch,
    ...(compiler ? {ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_CACHE_PROFILE:
      JSON.stringify({recipe: recipe(root, compiler), library: physical(library)})} : {}),
    ...(process.platform === 'darwin'
      ? {DYLD_INSERT_LIBRARIES: library} : {LD_PRELOAD: library})};
}
