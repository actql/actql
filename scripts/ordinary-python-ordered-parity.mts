import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {copyFile, lstat, mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runNativeInstallCommand} from './release-install-child.mjs';
import {validDeliveryAttemptLookup, validRunRef} from '@actql/client-wire';
import type {WireRunRef} from '@actql/client-wire';

type Scalar = string | number | boolean | null;
type Fixture = Readonly<{id: string; format: 'aql-text'; text: string;
  expected: {status: 'succeeded'; resultName: string; rows: readonly Record<string, Scalar>[];
    columns?: readonly unknown[]}}>;
type CorpusCase = Readonly<{id: string; originalId: number; group: string;
  input: {format: 'aql-text'; text: string; sha256: string};
  oracle: {kind: string; rowOrder?: string; schemaStatus?: string; rows?: Fixture['expected']['rows'];
    resultName?: string; columns?: readonly unknown[]}}>;
type OriginalCorpusCase = Readonly<{id: string; originalId: number; corpusSha256: string; sqlSha256: string}>;
type OrdinaryParityCase = Readonly<{bytes: Buffer; value: Fixture; digest: string; original?: OriginalCorpusCase}>;
export type OrderedPythonParityCase = Readonly<{
  originalId: number; text: string; sqlSha256: string; rows: Fixture['expected']['rows'];
}>;

const fixtureDirectory = new URL('./fixtures/', import.meta.url);
const corpusCaseId = /^compat-\d{2}$/u;
const sha256 = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

async function readFixtureBytes(name: string) {
  const bytes = await readFile(new URL(name, fixtureDirectory));
  assert(bytes.length <= 4 * 1024 ** 2, 'Release input exceeds bounded JSON');
  return bytes;
}

async function readCorpus() {
  const bytes = await readFixtureBytes('ordinary-parity-compatibility-corpus.json');
  const {cases} = JSON.parse(bytes.toString('utf8')) as {cases: readonly CorpusCase[]};
  return {cases, digest: sha256(bytes)};
}

export async function readOrderedPythonParityCorpus() {
  const corpus = await readCorpus();
  const cases: OrderedPythonParityCase[] = [];
  // This is the original same-Host regression sequence. Keep the standalone
  // #13, schema parity and any other corpus selections independent.
  for (let originalId = 1; originalId <= 13; originalId++) {
    const id = `compat-${String(originalId).padStart(2, '0')}`;
    const matches = corpus.cases.filter(item => item.id === id || item.originalId === originalId);
    const item = matches[0];
    assert(matches.length === 1 && item?.id === id && item.originalId === originalId &&
      item.group === 'retained' && item.oracle.kind === 'reported_rows' &&
      Array.isArray(item.oracle.rows), 'Missing or ambiguous original Python query oracle');
    assert.equal(item.input.format, 'aql-text');
    const {text, sha256: sqlSha256} = item.input;
    assert.equal(sha256(Buffer.from(text)), sqlSha256, 'Original corpus SQL bytes changed');
    cases.push({originalId, text, sqlSha256, rows: item.oracle.rows});
  }
  const lastResultName = originalCase('compat-13', corpus).value.expected.resultName;
  const bytes = Buffer.from(JSON.stringify({corpusSha256: corpus.digest, lastResultName, cases}) + '\n');
  return {bytes, digest: sha256(bytes), cases, lastResultName};
}

export function orderedPythonParityInvocation(root: string) {
  const state = join(root, 'python-ordered-original');
  const fixture = join(root, 'python-ordered-original.json');
  const original = join(root, 'python-ordered-original-run.json');
  const python = ['-I', '-B', join(root, 'ordinary-parity-python.py')];
  return {state, fixture, original, args: [...python, '--ordered', state, fixture, original],
    savedArgs: [...python, '--ordered-saved', state, fixture, original]};
}

function verifyOrderedPythonChild(original: unknown, interpreter: string, state: string, platform: string, args: string[]) {
  assert(original !== null && typeof original === 'object', 'Missing original same-Host Python parity command');
  const command = original as Record<string, unknown>;
  assert.equal(command.command, interpreter, 'Foreign same-Host Python parity interpreter');
  assert.deepEqual(command.args, args, 'Foreign same-Host Python parity launch');
  const {pid, code, signal, stdout, close, startedAt, endedAt} = command;
  assert(typeof pid === 'number' && Number.isSafeInteger(pid) && pid > 0 && code === 0 && signal === null &&
    typeof stdout === 'string' && command.spawnFailure === undefined && command.terminationReason === undefined &&
    command.stdinFailure === undefined && command.closeObservationFailure === undefined,
  'Original same-Host Python parity command did not return successfully');
  assert(typeof startedAt === 'string' && typeof endedAt === 'string' && Date.parse(startedAt) <= Date.parse(endedAt),
    'Missing original same-Host Python parity wait clock');
  assert(command.closeObservationAcknowledged === true && close !== null && typeof close === 'object',
    'Missing original same-Host Python first close');
  const physical = close as Record<string, unknown>;
  assert.equal(physical.pid, pid);
  assert(physical.aliveAfterClose === true && physical.scopedStateFd0 === true,
    'Missing original same-Host Python descriptor observation');
  if (platform === 'darwin-arm64') {
    assert.deepEqual(physical.command, ['/usr/sbin/lsof', '-nP', '-a', '-p', String(pid), '+D', state, '-F', 'pfn']);
    assert(physical.exitCode === 1 && physical.stdout === '' && physical.stderr === '');
  } else {
    assert(platform === 'linux-x64' && typeof physical.descriptorCount === 'number' &&
      Number.isSafeInteger(physical.descriptorCount) && physical.descriptorCount >= 0 && physical.descriptorCount <= 4096);
  }
  const events = stdout.trimEnd().split('\n').map(line => JSON.parse(line) as Record<string, unknown>);
  assert.deepEqual(events.at(-2), {stage: 'closed', pid, clientCloseReturned: true, hostCloseReturned: true});
  assert.deepEqual(events.at(-1), {stage: 'close-observation-ack', pid});
  return {pid, startedAt: Date.parse(startedAt), endedAt: Date.parse(endedAt), events};
}

function orderedDelivery(value: unknown, ref: WireRunRef, resultName: string) {
  const attemptId = (value as {attempt?: {attempt_id?: unknown}} | null)?.attempt?.attempt_id;
  assert(typeof attemptId === 'string' &&
    validDeliveryAttemptLookup(value, {attemptId, resultName, runDefinitionCid: ref.runDefinitionCid}) &&
    value.kind === 'found' && value.record !== null, 'Missing original ordered Python delivery');
  return {...value, record: value.record};
}

export function verifyOrderedPythonParity(
  original: unknown, interpreter: string, root: string, platform: string,
  corpus: Awaited<ReturnType<typeof readOrderedPythonParityCorpus>>,
) {
  const {state, args} = orderedPythonParityInvocation(root);
  const {pid, endedAt, events} = verifyOrderedPythonChild(original, interpreter, state, platform, args);
  const identity = {pid, fixtureSha256: corpus.digest};
  assert.equal(events.length, 1 + 2 * corpus.cases.length + 3, 'Incomplete original same-Host Python case sequence');
  assert.deepEqual(events[0], {stage: 'ordered-opened', ...identity});
  let authorityScope: string | undefined;
  const runCids = new Set<string>();
  const cid = /^sha256:[0-9a-f]{64}$/u;
  for (const [offset, {originalId, sqlSha256, rows}] of corpus.cases.entries()) {
    const caseIdentity = {originalId, sqlSha256, ...identity};
    assert.deepEqual(events[1 + 2 * offset], {stage: 'ordered-query-start', ...caseIdentity});
    const result = events[2 + 2 * offset]!;
    const {ref, ...observed} = result;
    assert.deepEqual(observed, {stage: 'ordered-query-result', rows, ...caseIdentity},
      `Foreign original same-Host Python result ${originalId}`);
    assert.deepEqual((observed.rows as typeof rows).map(Object.keys), rows.map(Object.keys),
      `Foreign original same-Host Python column order ${originalId}`);
    assert(validRunRef(ref), 'Missing original same-Host Python Run identity');
    const {namespaceId, authorityScopeCid, runDefinitionCid} = ref;
    assert(namespaceId === 'local' && cid.test(authorityScopeCid) && cid.test(runDefinitionCid),
      'Missing original same-Host Python Run identity');
    authorityScope ??= authorityScopeCid;
    assert.equal(authorityScopeCid, authorityScope, 'Foreign same-Host Python authority scope');
    assert(!runCids.has(runDefinitionCid), 'Duplicate original same-Host Python Run identity');
    runCids.add(runDefinitionCid);
  }
  const last = corpus.cases.at(-1);
  const ref = events.at(-4)?.ref;
  assert(last?.originalId === 13 && last.rows.length >= 2 && validRunRef(ref), 'Missing original thirteenth Run');
  const early = events.at(-3);
  const material = early?.original;
  assert(typeof material === 'string' && material.endsWith('\n') && Buffer.byteLength(material) <= 64 * 1024,
    'Missing original unread Python close material');
  assert.deepEqual(early, {stage: 'ordered-early-close', first: last.rows[0], rowsYielded: 1, original: material, ...identity},
    'Foreign unread Python close observation');
  const retained = JSON.parse(material) as {delivery?: unknown};
  const observed = retained.delivery;
  const resultName = corpus.lastResultName;
  assert.deepEqual(retained, {ref, resultName, delivery: observed, ...identity}, 'Foreign original unread Python Run');
  const delivery = orderedDelivery(observed, ref, resultName);
  assert(delivery.record.state === 'cancelled' && delivery.record.sequence > 0 && delivery.hostReleaseReceipt === null,
    'Missing terminal ACK for original unread Python close');
  assert(delivery.record.confirmed_byte_count <= Buffer.byteLength(JSON.stringify(last.rows[0]) + '\n'),
    'Unread Python close claims delivery beyond the consumed prefix');
  return {pid, endedAt, ref, material, delivery, resultName, rows: last.rows, fixtureSha256: corpus.digest};
}

export function verifyOrderedPythonSaved(saved: unknown, interpreter: string, root: string, platform: string,
  original: ReturnType<typeof verifyOrderedPythonParity>) {
  const {state, savedArgs} = orderedPythonParityInvocation(root);
  const {pid, startedAt, events} = verifyOrderedPythonChild(saved, interpreter, state, platform, savedArgs);
  assert(pid !== original.pid && startedAt >= original.endedAt, 'Ordered Python Saved must follow first close in a different process');
  assert.equal(events.length, 3, 'Incomplete original ordered Python Saved evidence');
  const {delivery: observed, ...event} = events[0]!;
  const {ref, resultName, rows, fixtureSha256, material, delivery: early} = original;
  assert.deepEqual(event, {stage: 'ordered-saved-result', pid, originalPid: original.pid, fixtureSha256,
    originalSha256: sha256(Buffer.from(material)), ref, resultName, rows, earlyDelivery: early, submissionCalls: 0},
  'Ordered Python Saved selected different original evidence');
  assert.deepEqual((event.rows as typeof rows).map(Object.keys), rows.map(Object.keys), 'Ordered Python Saved column order changed');
  const delivery = orderedDelivery(observed, ref, resultName);
  const bytes = Buffer.from(rows.map(row => JSON.stringify(row) + '\n').join(''));
  assert(delivery.record.state === 'succeeded' && delivery.hostReleaseReceipt?.delivered_byte_count === bytes.length &&
    delivery.hostReleaseReceipt.delivered_sha256 === sha256(bytes), 'Missing original ordered Python Saved terminal ACK');
  assert.notEqual(delivery.attempt.attempt_id, early.attempt.attempt_id, 'Ordered Python Saved reused the unread delivery attempt');
  assert.notEqual(delivery.attempt.delivery_attempt_cid, early.attempt.delivery_attempt_cid);
  for (const field of ['result_artifact_cid', 'result_manifest_cid', 'serialization_contract_cid'] as const) {
    assert.equal(delivery.attempt[field], early.attempt[field], 'Ordered Python Saved selected different Result bytes');
  }
}

function originalCase(id: string, corpus: Awaited<ReturnType<typeof readCorpus>>): OrdinaryParityCase {
  const matches = corpus.cases.filter(item => item.id === id);
  const item = matches[0];
  assert(matches.length === 1 && item, 'Unknown original parity case');
  assert(item.group === 'retained' && item.oracle.kind === 'reported_rows' && item.oracle.rowOrder === 'sequence' &&
    item.oracle.schemaStatus === 'independent_contract' && item.oracle.resultName && item.oracle.columns && item.oracle.rows,
  'Original parity case has no admitted ordered row and schema oracle');
  assert.equal(item.input.format, 'aql-text');
  assert.equal(sha256(Buffer.from(item.input.text)), item.input.sha256, 'Original corpus SQL bytes changed');
  const value: Fixture = {id, format: item.input.format, text: item.input.text,
    expected: {status: 'succeeded', resultName: item.oracle.resultName, columns: item.oracle.columns, rows: item.oracle.rows}};
  const bytes = Buffer.from(JSON.stringify(value) + '\n');
  return {bytes, value, digest: sha256(bytes),
    original: {id, originalId: item.originalId, corpusSha256: corpus.digest, sqlSha256: item.input.sha256}};
}

export async function acceptInstalledOrderedPython(
  interpreter: string, directory: string, platform: string,
) {
  const physicalPlatform = process.platform === 'linux' && process.arch === 'x64' ? 'linux-x64'
    : process.platform === 'darwin' && process.arch === 'arm64' ? 'darwin-arm64' : undefined;
  assert(physicalPlatform !== undefined && platform === physicalPlatform, 'Foreign normal Python platform');
  assert(isAbsolute(interpreter) && isAbsolute(directory), 'Expected absolute installed Python paths');
  const destination = await lstat(directory);
  assert(destination.isDirectory() && !destination.isSymbolicLink(), 'Expected owned Python parity directory');
  const root = await realpath(directory);
  const {state, fixture, original, args, savedArgs} = orderedPythonParityInvocation(root);
  const corpus = await readOrderedPythonParityCorpus();
  const home = join(root, 'home'), temporary = join(root, 'tmp');
  for (const owned of [home, temporary, state]) await mkdir(owned, {mode: 0o700});
  const env = {...process.env, HOME: home, TMPDIR: temporary};
  await copyFile(new URL('ordinary-parity-python.py', fixtureDirectory), join(root, 'ordinary-parity-python.py'),
    constants.COPYFILE_EXCL);
  await writeFile(fixture, corpus.bytes, {flag: 'wx', mode: 0o600});

  async function child(phase: 'ordered' | 'saved', argv: string[], timeoutMs: number) {
    try {
      const command = await runNativeInstallCommand(interpreter, argv, {cwd: root, env, state, timeoutMs});
      console.log(JSON.stringify({phase, command}));
      return command;
    } catch (error) {
      if (error instanceof Error && 'commandRecord' in error)
        console.log(JSON.stringify({phase, command: error.commandRecord}));
      throw error;
    }
  }
  // Keep one Host for the whole original sequence and the existing allowance
  // for observing it. The Saved child only starts after the first child exits.
  const ordered = await child('ordered', args, 600_000);
  const selected = verifyOrderedPythonParity(ordered, interpreter, root, platform, corpus);
  const expectedOriginal = Buffer.from(selected.material);
  assert.deepEqual(await readFile(original), expectedOriginal, 'Original ordered Python handoff changed before Saved');
  const saved = await child('saved', savedArgs, 180_000);
  verifyOrderedPythonSaved(saved, interpreter, root, platform, selected);
  assert.deepEqual(await readFile(original), expectedOriginal, 'Original ordered Python handoff changed during Saved');
  return {phase: 'accepted', platform, runs: corpus.cases.length, fixtureSha256: corpus.digest,
    orderedPid: ordered.pid, savedPid: saved.pid, ref: selected.ref, resultName: selected.resultName};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [interpreter, directory, platform, ...extra] = process.argv.slice(2);
  assert(interpreter && directory && platform && !extra.length,
    'Usage: ordinary-python-ordered-parity.mjs <installed-python> <directory> <platform>');
  console.log(JSON.stringify(await acceptInstalledOrderedPython(interpreter, directory, platform)));
}
