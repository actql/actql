import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdirSync, readFileSync, renameSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createHostJournalDirectoryInspector} from './host-journal-directory.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const require = createRequire(import.meta.url);
const limits = Object.freeze({maxEntries: 4, maxNameBytes: 1024, maxWork: 8192, maxInspections: 256});
// One explicitly selected matching-target diagnostic; not a normal package
// build, selected startup, resource original or installed Host acceptance.
test('actual Darwin directory original bounds names/currentness and owns one-shot close', async () => {
  assert.equal(process.platform, 'darwin');
  assert.equal(process.versions.node, '22.22.0');
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'node-directory-native-', label: 'selected Darwin Node directory diagnostic',
    digests: () => ['original.node', 'fault.node']});
  const clang = spawnSync('xcrun', ['--find', 'clang'], {encoding: 'utf8', timeout: 10000});
  assert.equal(clang.status, 0, clang.stderr);
  const sdk = spawnSync('xcrun', ['--show-sdk-path'], {encoding: 'utf8', timeout: 10000});
  assert.equal(sdk.status, 0, sdk.stderr);
  const compiler = clang.stdout.trim();
  const build = source => {
    const output = join(scratch.path, source.includes('fault') ? 'fault.node' : 'original.node');
    const command = ['-std=c11', '-D_DARWIN_C_SOURCE', '-Wall', '-Wextra', '-Werror', '-O0', '-g',
      '-isysroot', sdk.stdout.trim(),
      '-DNAPI_VERSION=8', '-DNODE_GYP_MODULE_NAME=actql_directory',
      '-bundle', '-undefined', 'dynamic_lookup',
      '-I', resolve(dirname(process.execPath), '../include/node'),
      join(root, 'adapters/host-node/native', source), '-o', output];
    const result = spawnSync(compiler, command, {encoding: 'utf8', timeout: 60000});
    assert.equal(result.status, 0, JSON.stringify({command, stdout: result.stdout, stderr: result.stderr}));
    return require(output);
  };
  const native = build('directory-darwin.c');
  const directory = join(scratch.path, 'directory'); mkdirSync(directory);
  for (const name of ['b', 'a', '\uFEFForiginal']) writeFileSync(join(directory, name), name);
  const inspect = createHostJournalDirectoryInspector(native, limits, () => {});
  assert.deepEqual(inspect(directory), ['a', 'b', '\uFEFForiginal']);
  const original = native.open(directory, 4, 1024, 8192);
  assert.equal(native.current(original), undefined);
  for (const foreign of [{}, {...original}, Object.create(original)]) {
    assert.throws(() => native.current(foreign), {code: 'HostJournalDirectoryCurrentUnavailable'});
  }
  const moved = directory + '-moved'; renameSync(directory, moved); mkdirSync(directory);
  assert.throws(() => native.current(original), {code: 'HostJournalDirectoryCurrentUnavailable'});
  assert.deepEqual(native.close(original), {outcome: 'closed', errno: 0});
  assert.deepEqual(native.close(original), {outcome: 'closed', errno: 0});
  assert.throws(() => native.next(original), {code: 'HostJournalDirectoryCurrentUnavailable'});
  assert.throws(() => createHostJournalDirectoryInspector(native,
    {...limits, maxEntries: 1}, () => {})(moved), {code: 'HostJournalDirectoryUnavailable'});
  const missing = native.open(join(scratch.path, 'absent'), 4, 1024, 8192);
  assert.throws(() => native.current(missing), {code: 'HostJournalDirectoryCurrentUnavailable'});
  assert.deepEqual(native.close(missing), {outcome: 'closed', errno: 0});

  // The actual Journal constructor and its cold-copy/currentness path consume
  // this same private inspector; no stock Dir fallback on selected refusal.
  // This diagnostic supplies no operational Host/Run admission or funding.
  const requests = join(scratch.path, 'requests');
  const selectedLimits = {maxEntries: 64, maxNameBytes: 1024, maxWork: 65536, maxInspections: 256};
  const selected = createHostJournalDirectoryInspector(native, selectedLimits, () => {});
  const options = {maxInspectionEntries: 64, primaryDirectoryInspection: selected};
  let journal = openClientRequestJournal(requests, options);
  journal.close(); journal = undefined;
  const originalDatabase = readFileSync(join(requests, 'client-requests.sqlite3'));
  journal = openClientRequestJournal(requests, options);
  journal.close(); journal = undefined;
  assert.deepEqual(readFileSync(join(requests, 'client-requests.sqlite3')), originalDatabase);
  const untouched = join(scratch.path, 'untouched');
  assert.throws(() => openClientRequestJournal(untouched,
    {maxInspectionEntries: 64, primaryDirectoryInspection: () => []}),
  {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(existsSync(untouched), false);
  assert.throws(() => openClientRequestJournal(untouched,
    {...options, maxInspectionEntries: 63}), {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(existsSync(untouched), false);

  const fault = build('fixtures/directory-close-fault.c');
  const uncertain = createHostJournalDirectoryInspector(fault.operations, limits, () => {});
  let carrier;
  assert.throws(() => uncertain(moved), error => {
    carrier = error; return error.code === 'HostJournalDirectoryCleanupPending';
  });
  assert.equal(carrier.cleanupHandle.status().pending, true);
  assert.deepEqual(carrier.cleanupHandle.status().outcome, {outcome: 'unknown', errno: 5});
  for (let index = 0; index < 3; index++) assert.equal(carrier.cleanupHandle.retry().pending, true);
  assert.equal(fault.attempts(), 1);
  assert.equal(fault.physicallyClosed(), 1);
  assert.throws(() => uncertain(moved), {code: 'HostJournalDirectoryUnavailable'});
  assert.equal(fault.attempts(), 1);
  const journalUnknown = createHostJournalDirectoryInspector(fault.operations, selectedLimits, () => {});
  let journalFailure;
  assert.throws(() => openClientRequestJournal(requests,
    {...options, primaryDirectoryInspection: journalUnknown}), error => {
    journalFailure = error; return error.code === 'HostJournalDirectoryCleanupPending';
  });
  assert.equal(journalFailure.cleanupHandle.retry().pending, true);
  assert.equal(journalFailure.cleanupHandle.retry().pending, true);
  assert.equal(fault.attempts(), 2);
  assert.equal(fault.physicallyClosed(), 2);
  assert.deepEqual(readFileSync(join(requests, 'client-requests.sqlite3')), originalDatabase);
  // This injected fixture really closed its disposable FD; the consumer's
  // Unknown remains Unknown. Test teardown is not an operational close ACK.
  scratch.passed();
});
