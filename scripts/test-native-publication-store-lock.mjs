import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {once} from 'node:events';

const repositoryRoot = fileURLToPath(new URL('../', import.meta.url));
const scratchParent = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchParent !== 'string' || scratchParent.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
await mkdir(scratchParent, {recursive: true});
const root = await mkdtemp(join(scratchParent, 'publication-store-lock-'));
const moon = join(process.env.MOON_HOME ?? '', 'bin', 'moon');
const sqliteLibrary = process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
  (process.platform === 'darwin'
    ? '/usr/lib/libsqlite3.dylib'
    : 'libsqlite3.so.0');
const lockProgram = String.raw`
import fcntl
import os
import sys

path = os.path.join(sys.argv[1], '.actql-publication.lock')
descriptor = os.open(path, os.O_CREAT | os.O_RDWR, 0o600)
fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
print('ready', flush=True)
sys.stdin.buffer.read(1)
os.close(descriptor)
`;

const runProbe = (mode, filter = '*cross-process root ownership*',
  extraEnv = {}) => new Promise((resolve, reject) => {
  const child = spawn(moon, [
    'test', '--target', 'native',
    'src/platform_native/publication_store',
    '--filter', filter,
  ], {
    cwd: repositoryRoot,
    env: {
      ...process.env,
      ACTQL_TEST_NATIVE_SQLITE_LIBRARY: sqliteLibrary,
      ACTQL_TEST_NATIVE_STORE_ROOT: root,
      ACTQL_TEST_PUBLICATION_LOCK_MODE: mode,
      ...extraEnv,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const stdout = [];
  const stderr = [];
  child.stdout.on('data', chunk => stdout.push(chunk));
  child.stderr.on('data', chunk => stderr.push(chunk));
  child.on('error', reject);
  child.on('exit', (code, signal) => {
    if (code === 0 && signal === null) {
      resolve();
    } else {
      reject(new Error(
        `publication lock probe failed (${code ?? signal})\n` +
        Buffer.concat(stdout).toString() + Buffer.concat(stderr).toString(),
      ));
    }
  });
});

let holder;
try {
  holder = spawn('python3', ['-c', lockProgram, root], {
    stdio: ['pipe', 'pipe', 'inherit'],
  });
  holder.on('error', error => {
    throw error;
  });
  const [ready] = await once(holder.stdout, 'data');
  assert.equal(ready.toString().trim(), 'ready');
  await runProbe('held');
  holder.stdin.write(Buffer.from([0]));
  holder.stdin.end();
  const [code, signal] = await once(holder, 'exit');
  assert.equal(signal, null);
  assert.equal(code, 0);
  holder = undefined;
  await runProbe('released');
  const legacyRoot = await mkdtemp(join(scratchParent,
    'publication-store-legacy-'));
  const unknownRoot = await mkdtemp(join(scratchParent,
    'publication-store-unknown-'));
  try {
    const legacyBytes = Buffer.from('legacy Store bytes');
    const unknownBytes = Buffer.from('unidentified Store bytes');
    await writeFile(join(legacyRoot, '.actql-publication.sqlite3'),
      legacyBytes);
    await writeFile(join(unknownRoot, 'unidentified-record'), unknownBytes);
    await runProbe('released',
      '*refuses old and unidentified roots without writes*', {
        ACTQL_TEST_NATIVE_LEGACY_STORE_ROOT: legacyRoot,
        ACTQL_TEST_NATIVE_UNKNOWN_STORE_ROOT: unknownRoot,
      });
    assert.deepEqual(await readdir(legacyRoot),
      ['.actql-publication.sqlite3']);
    assert.deepEqual(await readdir(unknownRoot), ['unidentified-record']);
    assert.deepEqual(await readFile(join(legacyRoot,
      '.actql-publication.sqlite3')), legacyBytes);
    assert.deepEqual(await readFile(join(unknownRoot,
      'unidentified-record')), unknownBytes);
  } finally {
    await rm(legacyRoot, {recursive: true, force: true});
    await rm(unknownRoot, {recursive: true, force: true});
  }
  console.log('Native publication Store cross-process lock passed');
} finally {
  if (holder !== undefined && holder.exitCode === null) {
    holder.kill('SIGTERM');
    await once(holder, 'exit');
  }
  await rm(root, {recursive: true, force: true});
}
