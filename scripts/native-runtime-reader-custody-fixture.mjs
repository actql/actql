// Prepare only the failed-constructor custody cases in the existing Native
// filesystem Owner. Injection is confined to its child and two owned files.
import {spawnSync} from 'node:child_process';
import {mkdirSync} from 'node:fs';
import {join} from 'node:path';

export function nativeRuntimeReaderCustodyFixture(root, scratch) {
  if (!['darwin', 'linux'].includes(process.platform)) {
    throw new Error('Native Reader custody injection is unavailable on this platform');
  }
  if (process.env.DYLD_INSERT_LIBRARIES || process.env.LD_PRELOAD) {
    throw new Error('Native Reader custody refuses an existing injection environment');
  }
  for (const name of ['runtime-constructor-pending', 'runtime-constructor-acked']) {
    mkdirSync(join(scratch, name), {mode: 0o700});
  }
  const library = join(scratch, process.platform === 'darwin'
    ? 'runtime-reader-custody.dylib' : 'runtime-reader-custody.so');
  // The injected test library also reaches Apple's arm64e compiler/launcher
  // helpers. Both slices serve the same existing Darwin arm64 test profile.
  const built = spawnSync('cc', ['-std=c11', '-O0', '-Wall', '-Wextra', '-Werror',
    ...(process.platform === 'darwin'
      ? ['-dynamiclib', '-arch', 'arm64', '-arch', 'arm64e'] : ['-shared', '-fPIC']),
    join(root, 'scripts/fixtures/native-runtime-reader-custody.c'), '-o', library,
    ...(process.platform === 'linux' ? ['-ldl'] : [])], {stdio: 'inherit'});
  if (built.error || built.signal || built.status !== 0) {
    throw new Error(`Native Reader custody fixture compilation failed: ${
      built.error?.message ?? built.signal ?? built.status}`);
  }
  return {ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT: scratch,
    ...(process.platform === 'darwin'
      ? {DYLD_INSERT_LIBRARIES: library} : {LD_PRELOAD: library})};
}
