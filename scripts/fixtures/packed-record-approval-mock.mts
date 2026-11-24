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

type Connector = 'salesforce' | keyof typeof sharedRecordUpdateSelections;
type FailureView = {name?: unknown; code?: unknown; message?: unknown} | undefined;
type Rows = ReturnType<typeof recordUpdateFixtureState>['before'];
type MockInventory = Record<string, Record<string, {rows: Record<string, unknown>[]}>>;

const connector = process.env.ACTQL_RECORD_APPROVAL_MOCK_CONNECTOR as Connector;
const variant = process.env.ACTQL_RECORD_APPROVAL_MOCK_VARIANT || undefined;
assert(variant === undefined || ['whole-input', 'binary-source', 'three-source'].includes(variant) &&
  connector === 'hubspot', 'Select one declared mock variant');
assert(['salesforce', 'hubspot', 'kintone'].includes(connector), 'Select one original mock consumer');
const execute = promisify(execFile), privateFile = {mode: 0o600, flag: 'wx'};
const safe = (error: unknown) => ({name: (error as FailureView)?.name,
  code: (error as FailureView)?.code, message: (error as FailureView)?.message});

test(`ordinary installed ${connector} mock reviews, explicitly approves and reads original Saved first`,
  {timeout: 100000}, async t => {
  assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1');
  const removePrograms = process.env.ACTQL_RECORD_APPROVAL_REMOVE_PROGRAMS === '1';
  const input = process.env.ACTQL_RECORD_APPROVAL_MOCK_CASE;
  const supportsAuthored = connector !== 'salesforce' && variant === undefined && !removePrograms;
  let authored: Awaited<ReturnType<typeof readAuthoredCase>> | undefined;
  if (input !== undefined) {
    assert(isAbsolute(input) && supportsAuthored, 'Select one supported authored mock case');
  }
  if (supportsAuthored) {
    const caseFile = input ?? fileURLToPath(new URL(`./${connector}-approval/case.json`, import.meta.url));
    authored = await readAuthoredCase(caseFile);
    assert(authored.fixture !== undefined, 'An authored mock case requires a seed and state oracle');
  }
  const parent = join(process.cwd(), connector + '-mock-original-roots');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'approval-'));
  const project = join(root, 'project'), home = join(root, 'home'), state = join(project, '.actql');
  await mkdir(project); await mkdir(home);
  t.diagnostic(`Retained ${connector} mock original root: ${root}`);
  const selection = {...(connector === 'salesforce' || variant !== undefined
    ? {recordId: connector === 'salesforce' ? '001MockSelected' : '9007199254740993',
    previousName: 'Before shared mock approval', nextName: 'After shared mock approval'}
    : sharedRecordUpdateSelections[connector]),
    ...(variant === undefined ? {} : {variant})};
  const fixture = variant === 'binary-source' ? 'binary-source-mock-project.mjs' : 'mock-project.mjs';
  const {mockProjectFiles, mockProjectFilesFromSeed} = await import(new URL(`./${connector}-approval/${fixture}`, import.meta.url) as unknown as string);
  const files: Record<string, string> = authored === undefined ? mockProjectFiles(selection) : mockProjectFilesFromSeed(authored.fixture!.seed);
  for (const [name, body] of Object.entries(files)) {
    const path = join(project, name); await mkdir(dirname(path), {recursive: true});
    await writeFile(path, body, privateFile);
  }
  const initial = JSON.parse(files['mock/data.json']) as MockInventory, changed = structuredClone(initial);
  const [resource, idField, field] = {salesforce: ['Account', 'Id', 'Name'], hubspot: ['companies', 'id', 'name'],
    kintone: ['inquiries', '$id', 'Subject']}[connector];
  if (authored !== undefined || connector !== 'salesforce' && variant === undefined) {
    const expected = authored?.fixture!.expected ?? recordUpdateFixtureState(selection);
    const before = expected.before, after = expected.after;
    assert(before.target !== null && after.target !== null,
      'The installed Mock update fixture requires a target in both snapshots');
    const rows = (target: Rows['target'], control: Rows['control']) =>
      [target, control].map(value => ({[idField]: value.id, [field]: value.name}));
    assert.deepEqual(after.control, before.control, 'The mock control row remains unchanged');
    assert.equal(after.target.id, before.target.id);
    assert.deepEqual(initial[connector][resource].rows, rows(before.target, before.control));
    changed[connector][resource].rows = rows(after.target, after.control);
  } else changed[connector][resource].rows[0][field] = selection.nextName;
  const configuration = join(root, 'configuration.json'), prefix = join(root, 'receipt');
  const casePath = 'case.json';
  if (authored !== undefined) {
    // Copy the business case and leave HTTP protocol inputs with the provider.
    const {seed, expected} = authored.fixture!;
    await writeFile(join(root, casePath), JSON.stringify({...authored, fixture: {seed, expected}}), privateFile);
  }
  await writeFile(configuration, JSON.stringify({...(authored === undefined ? {selection} : {casePath}),
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
    for (const phase of ['capture', 'approve', 'recover']) {
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
      assert.equal(outcome.workObservation.effectReplacementReturns, phase === 'approve' ? 1 : 0);
      assert.deepEqual(outcome.descriptors.before.openPaths, []);
      assert.deepEqual(outcome.descriptors.after.openPaths, []);
      assert.deepEqual(JSON.parse(await readFile(join(project, 'mock/data.json'), 'utf8')),
        phase === 'capture' ? initial : changed, 'Only the selected original field changes after approval');
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
    await writeFile(join(root, 'summary.json'), JSON.stringify({connector, passed: !failed, phases,
      ...(authored === undefined ? {} : {authoredCase: authored.name}),
      qualification: 'Declared mock ordinary public consumer only; not provider authentication or installed Effect acceptance',
      publicFailure: failed ? safe(primary) : null}, null, 2) + '\n', privateFile);
  }
  if (failed) throw primary;
});
