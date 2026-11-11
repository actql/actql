// Only the declared-data mock profile is selected here; no provider rights or
// installed connector acceptance are inferred from these ordinary public calls.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdir, mkdtemp, readFile, writeFile, lstat, unlink} from 'node:fs/promises';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const connector = process.env.ACTQL_RECORD_APPROVAL_MOCK_CONNECTOR;
assert(['salesforce', 'hubspot', 'kintone'].includes(connector), 'Select one original mock consumer');
const execute = promisify(execFile), privateFile = {mode: 0o600, flag: 'wx'};
const safe = error => ({name: error?.name, code: error?.code, message: error?.message});

test(`ordinary installed ${connector} mock reviews, explicitly approves and reads original Saved first`,
  {timeout: 100000}, async t => {
  assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1');
  const parent = join(process.cwd(), connector + '-mock-original-roots');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'approval-'));
  const project = join(root, 'project'), home = join(root, 'home'), state = join(project, '.actql');
  await mkdir(project); await mkdir(home);
  t.diagnostic(`Retained ${connector} mock original root: ${root}`);
  const selection = {recordId: connector === 'salesforce' ? '001MockSelected' : '9007199254740993',
    previousName: 'Before shared mock approval', nextName: 'After shared mock approval'};
  const {mockProjectFiles} = await import(new URL(`./${connector}-approval/mock-project.mjs`, import.meta.url));
  const files = mockProjectFiles(selection);
  for (const [name, body] of Object.entries(files)) {
    const path = join(project, name); await mkdir(dirname(path), {recursive: true});
    await writeFile(path, body, privateFile);
  }
  const initial = JSON.parse(files['mock/data.json']), changed = structuredClone(initial);
  const [resource, field] = {salesforce: ['Account', 'Name'], hubspot: ['companies', 'name'],
    kintone: ['inquiries', 'Subject']}[connector];
  changed[connector][resource].rows[0][field] = selection.nextName;
  const configuration = join(root, 'configuration.json'), prefix = join(root, 'receipt');
  await writeFile(configuration, JSON.stringify({selection,
    connect: {mode: 'local', profile: 'mock', installation: {directory: state}}}), privateFile);
  const env = {...process.env, HOME: home, NODE_OPTIONS: '', NODE_PATH: ''};
  for (const name of ['ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE']) delete env[name];
  let failed = false, primary;
  const phases = [];
  const removePrograms = process.env.ACTQL_RECORD_APPROVAL_REMOVE_PROGRAMS === '1';
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
      let result;
      try {
        result = await execute(process.execPath,
          [fileURLToPath(new URL('./record-approval/installed-child.mjs', import.meta.url)),
            connector, phase, configuration, prefix, state],
          {cwd: project, env, encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 ** 2});
      } catch (error) {
        await writeFile(join(root, phase + '.stdout'), error.stdout ?? '', privateFile);
        await writeFile(join(root, phase + '.stderr'), error.stderr ?? '', privateFile);
        throw error;
      }
      await writeFile(join(root, phase + '.stdout'), result.stdout, privateFile);
      await writeFile(join(root, phase + '.stderr'), result.stderr, privateFile);
      const outcome = JSON.parse(result.stdout);
      assert.equal(outcome.phase, phase); assert.equal(outcome.status, 'passed');
      assert.equal(outcome.publicClientClose, 'returned');
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
      qualification: 'Declared mock ordinary public consumer only; not provider authentication or installed Effect acceptance',
      publicFailure: failed ? safe(primary) : null}, null, 2) + '\n', privateFile);
  }
  if (failed) throw primary;
});
