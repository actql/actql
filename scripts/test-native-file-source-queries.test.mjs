// Actual installed Native CLI only. No repository runtime or Source substitute.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {after, test} from 'node:test';
import {createOwnedScratch} from './owned-scratch.mjs';
import {nativeInstalledSourceQueries, observeNativeFileSourceQuery,
  nativeFileSourceQueryEnvironment, retainNativeFileCapacityStderr} from './fixtures/native-file-source-queries.mjs';

const launcher = process.env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER;
const binary = process.env.ACTQL_TEST_NATIVE_CLIENT_BINARY;
assert(launcher && binary, 'Select the same actual installed Native launcher and binary');
const originalBinary = await readFile(binary);
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-file-queries-',
  label: 'Installed Native original File Source queries'});
const emptyPath = join(scratch.path, 'empty-path');
await mkdir(emptyPath);
console.log(`Native File query binary sha256:${createHash('sha256').update(originalBinary).digest('hex')}`);
after(async () => {
  assert.deepEqual(await readFile(binary), originalBinary);
  scratch.passed();
});

for (const fixture of nativeInstalledSourceQueries) test(`Native installed File Source ${fixture.name}`, async () => {
  const home = join(scratch.path, fixture.name + '-home');
  await mkdir(home, {mode: 0o700});
  let ordinal = 0;
  const cli = async (args, cwd) => {
    const startedAt = new Date().toISOString();
    const environment = nativeFileSourceQueryEnvironment({fixture, args, emptyPath, home, environment: process.env});
    const result = spawnSync(process.execPath, [launcher, ...args], {cwd, env: environment,
      timeout: 30_000, maxBuffer: 1024 * 1024, encoding: 'utf8'});
    const name = fixture.name + '-' + ordinal++;
    // Preserve the original result before any assertion, including timeouts,
    // closed typed refusals and Unknown. Never retry a failed command or Run.
    await writeFile(join(scratch.path, name + '.stdout'), result.stdout ?? '', {flag: 'wx'});
    await writeFile(join(scratch.path, name + '.stderr'), result.stderr ?? '', {flag: 'wx'});
    await writeFile(join(scratch.path, name + '.json'), JSON.stringify({args, cwd, startedAt,
      endedAt: new Date().toISOString(), status: result.status, signal: result.signal,
      error: result.error?.code}, null, 2) + '\n', {flag: 'wx'});
    retainNativeFileCapacityStderr(environment, result.stderr);
    return result;
  };
  const observed = await observeNativeFileSourceQuery({parent: scratch.path, fixture, cli});
  console.log('ACTQL_NATIVE_FILE_SOURCE_QUERY ' + JSON.stringify(observed));
});
