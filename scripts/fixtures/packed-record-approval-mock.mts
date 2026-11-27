// Only the declared-data mock profile is selected here; no provider rights or
// installed connector acceptance are inferred from these ordinary public calls.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir, mkdtemp, readFile, writeFile, lstat, unlink} from 'node:fs/promises';
import {join, dirname, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {sharedRecordUpdateSelections, recordUpdateFixtureState} from './record-approval/cases.mjs';
import {readAuthoredCase} from './record-approval/command.mjs';
import {recordApprovalMockInventory, recordApprovalMockResource, recordApprovalOrderedMockProject} from './record-approval/mock-project.mjs';

type Connector = 'salesforce' | keyof typeof sharedRecordUpdateSelections;
type FailureView = {name?: unknown; code?: unknown; message?: unknown} | undefined;

const connector = process.env.ACTQL_RECORD_APPROVAL_MOCK_CONNECTOR as Connector;
const variant = process.env.ACTQL_RECORD_APPROVAL_MOCK_VARIANT || undefined;
const decision = process.env.ACTQL_RECORD_APPROVAL_DECISION ?? 'approved';
assert(decision === 'approved' || decision === 'rejected', 'Select one Mock decision');
const rejecting = decision === 'rejected';
assert(variant === undefined || ['whole-input', 'binary-source', 'three-source'].includes(variant) &&
  connector === 'hubspot', 'Select one declared mock variant');
assert(['salesforce', 'hubspot', 'kintone'].includes(connector), 'Select one original mock consumer');
const execute = promisify(execFile), privateFile = {mode: 0o600, flag: 'wx'};
const safe = (error: unknown) => ({name: (error as FailureView)?.name,
  code: (error as FailureView)?.code, message: (error as FailureView)?.message});

test(`ordinary installed ${connector} mock ${rejecting ? 'rejects and reopens' : 'approves and reads'} the original Run`,
  {timeout: 100000}, async t => {
  assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1');
  const removePrograms = process.env.ACTQL_RECORD_APPROVAL_REMOVE_PROGRAMS === '1';
  const input = process.env.ACTQL_RECORD_APPROVAL_MOCK_CASE;
  const supportsAuthored = variant === undefined && !removePrograms && (input !== undefined || connector !== 'salesforce');
  let authored: Awaited<ReturnType<typeof readAuthoredCase>> | undefined;
  if (input !== undefined) {
    assert(isAbsolute(input) && supportsAuthored, 'Select one supported authored mock case');
  }
  if (supportsAuthored) {
    const caseFile = input ?? fileURLToPath(new URL(`./${connector}-approval/case.json`, import.meta.url));
    authored = await readAuthoredCase(caseFile);
    assert(authored.collection !== undefined || (connector !== 'salesforce' && authored.fixture !== undefined),
      'An authored Mock case requires its original input and independent expected state');
  }
  assert(!rejecting || authored?.collection !== undefined, 'Select the original ordered Mock case for rejection');
  const selection = {...(connector === 'salesforce' || variant !== undefined
    ? {recordId: connector === 'salesforce' ? '001MockSelected' : '9007199254740993',
    previousName: 'Before shared mock approval', nextName: 'After shared mock approval'}
    : sharedRecordUpdateSelections[connector]),
    ...(variant === undefined ? {} : {variant})};
  async function prepareSingleRecord() {
    const fixture = variant === 'binary-source' ? 'binary-source-mock-project.mjs' : 'mock-project.mjs';
    const {mockProjectFiles, mockProjectFilesFromSeed} = await import(new URL(`./${connector}-approval/${fixture}`, import.meta.url) as unknown as string);
    const files: Record<string, string> = authored === undefined ? mockProjectFiles(selection) : mockProjectFilesFromSeed(authored.fixture!.seed);
    const original = recordApprovalMockResource(files, connector);
    const expected = authored?.fixture!.expected ?? (connector !== 'salesforce' && variant === undefined
      ? recordUpdateFixtureState(selection) : undefined);
    assert.equal(original.fields.length, 1, 'The existing single-field case has one declared write field');
    const [field] = original.fields;
    const key = expected?.before.target?.id ?? selection.recordId;
    const target = original.rows.find(row => row[original.identity] === key);
    const controls = original.rows.filter(row => row[original.identity] !== key);
    assert(target && controls.length === 1);
    const [control] = controls;
    const controlKey = control[original.identity];
    assert(typeof controlKey === 'string');
    if (expected !== undefined) {
      assert(expected.before.target && expected.after.target);
      assert.deepEqual(expected.after.control, expected.before.control);
      assert.equal(expected.after.target.id, key);
      assert.deepEqual(original.rows, [
        {[original.identity]: key, [field]: expected.before.target.name},
        {[original.identity]: expected.before.control.id, [field]: expected.before.control.name},
      ]);
    }
    const result = recordApprovalMockInventory(original, controlKey, [{
      key, operation: 'update', before: target, after: {
        ...target, [field]: expected?.after.target?.name ?? selection.nextName,
      },
    }]);
    return {files, ...result};
  }
  const {files, initial, changed, approvedWrites} = authored?.collection === undefined
    ? await prepareSingleRecord() : recordApprovalOrderedMockProject(authored, connector);
  const parent = join(process.cwd(), connector + '-mock-original-roots');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'approval-'));
  const project = join(root, 'project'), home = join(root, 'home'), state = join(project, '.actql');
  await mkdir(project); await mkdir(home);
  t.diagnostic(`Retained ${connector} mock original root: ${root}`);
  for (const [name, body] of Object.entries(files)) {
    const path = join(project, name); await mkdir(dirname(path), {recursive: true});
    await writeFile(path, body, privateFile);
  }
  const configuration = join(root, 'configuration.json'), prefix = join(root, 'receipt');
  const casePath = 'case.json';
  if (authored !== undefined) {
    // Copy the business case and leave HTTP protocol inputs with the provider.
    const fixture = authored.fixture;
    const caseWire = fixture === undefined ? authored : {...authored, fixture: {seed: fixture.seed, expected: fixture.expected}};
    await writeFile(join(root, casePath), JSON.stringify(caseWire), privateFile);
  }
  await writeFile(configuration, JSON.stringify({...(authored === undefined ? {selection} : {casePath}),
    ...(rejecting ? {decision} : {}),
    connect: {mode: 'local', profile: 'mock', installation: {directory: state}}}), privateFile);
  const env: NodeJS.ProcessEnv = {...process.env, HOME: home, NODE_OPTIONS: '', NODE_PATH: ''};
  for (const name of ['ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE']) delete env[name];
  delete env.ACTQL_RECORD_APPROVAL_REPLY_LOSS_EXPECTATION;
  delete env.ACTQL_RECORD_APPROVAL_SOURCE_SCHEMA;
  let failed = false, primary;
  const phases: Record<string, unknown>[] = [];
  const programs = removePrograms ? await Promise.all(['update', 'read'].map(async name => {
    const path = fileURLToPath(new URL(`./${connector}-approval/${name}.aql`, import.meta.url));
    const info = await lstat(path); assert(info.isFile() && info.nlink === 1);
    return {path, dev: info.dev, ino: info.ino, body: await readFile(path, 'utf8')};
  })) : [];
  try {
    const check = await execute(process.execPath,
      [fileURLToPath(new URL(`./${connector}-approval/run.mjs`, import.meta.url)), 'check', configuration, prefix],
      {cwd: project, env, encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 ** 2});
    assert.deepEqual(JSON.parse(check.stdout), {phase: 'check', status: 'ready', connected: false});
    await assert.rejects(lstat(state), {code: 'ENOENT'});
    await writeFile(join(root, 'check.stdout'), check.stdout, privateFile);
    for (const phase of ['capture', rejecting ? 'reject' : 'approve', 'recover']) {
      if (removePrograms && phase !== 'capture') {
        for (const original of programs) await assert.rejects(lstat(original.path), {code: 'ENOENT'});
      }
      const startedAt = new Date().toISOString();
      let result, childPid;
      try {
        const flight = execute(process.execPath,
          [fileURLToPath(new URL('./record-approval/installed-child.mjs', import.meta.url)),
            connector, phase, configuration, prefix, state],
          {cwd: project, env, encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 ** 2});
        childPid = flight.child.pid;
        result = await flight;
      } catch (error) {
        await writeFile(join(root, phase + '.stdout'), (error as {stdout?: string}).stdout ?? '', privateFile);
        await writeFile(join(root, phase + '.stderr'), (error as {stderr?: string}).stderr ?? '', privateFile);
        try {
          const close = JSON.parse(await readFile(`${prefix}.${phase}.close-started.json`, 'utf8'));
          assert.equal(close.phase, phase); assert.equal(close.pid, childPid);
          phases.push({startedAt, endedAt: new Date().toISOString(), childPid, partialClose: close});
          t.diagnostic('ORIGINAL_CLOSE_OBSERVATION ' + JSON.stringify(close));
        } catch { /* Missing/foreign diagnostics never replace the original command failure. */ }
        throw error;
      }
      await writeFile(join(root, phase + '.stdout'), result.stdout, privateFile);
      await writeFile(join(root, phase + '.stderr'), result.stderr, privateFile);
      const outcome = JSON.parse(result.stdout);
      assert.equal(outcome.phase, phase); assert.equal(outcome.status, 'passed');
      assert.equal(outcome.pid, childPid);
      assert.equal(outcome.publicClientClose, 'returned');
      assert.equal(outcome.workObservation.complete, true);
      assert.equal(outcome.workObservation.modelCallStarts, 0);
      if (phase !== 'capture') assert.equal(outcome.workObservation.sourceAcquisitionStarts, 0);
      assert.equal(outcome.workObservation.effectReplacementReturns, phase === 'approve' ? approvedWrites : 0);
      assert.deepEqual(outcome.descriptors.before.openPaths, []);
      assert.deepEqual(outcome.descriptors.after.openPaths, []);
      assert.deepEqual(JSON.parse(await readFile(join(project, 'mock/data.json'), 'utf8')),
        rejecting || phase === 'capture' ? initial : changed, 'Expected the original ordered Mock state');
      if (removePrograms && phase === 'capture') {
        for (const original of programs) {
          const info = await lstat(original.path);
          assert(info.isFile() && info.nlink === 1 && info.dev === original.dev && info.ino === original.ino);
          assert.equal(await readFile(original.path, 'utf8'), original.body);
        }
        for (const original of programs) await unlink(original.path);
      }
      phases.push({startedAt, endedAt: new Date().toISOString(), ...outcome});
    }
  } catch (error) {failed = true; primary = error;}
  finally {
    await writeFile(join(root, 'summary.json'), JSON.stringify({connector, decision, passed: !failed, phases,
      ...(authored === undefined ? {} : {authoredCase: authored.name}),
      qualification: 'Declared mock ordinary public consumer only; not provider authentication or installed Effect acceptance',
      publicFailure: failed ? safe(primary) : null}, null, 2) + '\n', privateFile);
  }
  if (failed) throw primary;
});
