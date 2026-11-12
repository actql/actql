import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {parse} from 'yaml';
import {nodeTestArguments} from './test-execution.mjs';
import {sessionControlFiles, verifySessionControls} from './ci-session-controls.mjs';
import {gateJobs} from './ci-targets.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const {jobs} = parse(readFileSync(join(root, '.github/workflows/ci.yml'), 'utf8'));
const control = 'node --test proofs/ci-evidence/*.test.mjs';

test('Session split retains every original command once and the same collector artifact identity', () => {
  const original = JSON.parse(readFileSync(new URL('./fixtures/ci-session-obligations.json', import.meta.url)));
  const actual = ['session-evidence', 'session-controls'].flatMap(name => jobs[name].steps
    .filter(step => step.run && !step.name.startsWith('Install '))
    .map(({name, run, env}) => ({name, run: run === 'node scripts/ci-session-controls.mjs' ? control : run,
      ...env ? {env} : {}})));
  assert.deepEqual(actual.map(value => value.name).sort(), original.map(value => value.name).sort());
  for (const step of original) assert.deepEqual(actual.filter(value => value.name === step.name), [step]);
  const baselineFiles = JSON.parse(readFileSync(new URL('./fixtures/ci-session-test-files.json', import.meta.url)));
  const files = sessionControlFiles(root);
  for (const file of baselineFiles) assert(files.includes(file), 'Dropped original file: ' + file);
  assert.deepEqual(jobs['session-controls'].needs, ['select-targets', 'preflight']);
  assert.equal(jobs['session-controls'].if, jobs['session-evidence'].if);
  assert.equal(jobs['session-controls']['continue-on-error'], undefined);
  assert(jobs['session-controls'].steps.some(step => step.name === 'Install audited Lean pin'));
  assert.equal(jobs['session-controls'].steps[0].with['fetch-depth'], 0);
  assert(gateJobs.includes('session-controls')); assert(jobs.check.needs.includes('session-controls'));
  const family = jobs['session-evidence'];
  assert.equal(family.outputs['artifact-id'], '${{ steps.session-actions.outputs.artifact-id }}');
  assert.equal(family.outputs['artifact-digest'], '${{ steps.session-actions.outputs.artifact-digest }}');
  assert.equal(family.steps.find(step => step.id === 'session-actions').with.name,
    'session-actions-${{ github.run_id }}-${{ github.run_attempt }}-${{ github.sha }}');
});

test('complete local Session route retains the moved controls before the original collector', () => {
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'run', 'session-evidence', '--dry-run'],
    {cwd: root, encoding: 'utf8', timeout: 10_000});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.split('node scripts/ci-session-controls.mjs').length - 1, 1);
  assert(result.stdout.indexOf('node scripts/ci-session-controls.mjs') <
    result.stdout.indexOf('node proofs/ci-evidence/collect.mjs init'));
});

test('real Node summaries reject omitted, duplicate, empty, skipped and failed controls', t => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-session-counts-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  mkdirSync(join(directory, 'proofs/ci-evidence'), {recursive: true});
  const files = ['a', 'b'].map(name => 'proofs/ci-evidence/' + name + '.test.mjs');
  const write = (file, body) => writeFileSync(join(directory, file),
    "import test from 'node:test';\n" + body);
  for (const file of files) write(file, "test('original', () => {});\n");
  const env = {...process.env}; delete env.NODE_TEST_CONTEXT;
  const run = selection => spawnSync(process.execPath, nodeTestArguments(selection),
    {cwd: directory, env, encoding: 'utf8', timeout: 10_000});
  const result = run(files);
  assert.equal(verifySessionControls(directory, files, result).passed, 2);
  assert.throws(() => verifySessionControls(directory, files, run(files.slice(0, 1))), /summary/u);
  assert.throws(() => verifySessionControls(directory, [files[0], files[0]], result), /duplicate/u);
  const summary = result.stdout.split('\n').find(line => line.startsWith('ACTQL_TEST_SUMMARY ') && line.includes('"file"'));
  assert.throws(() => verifySessionControls(directory, files, {...result, stdout: result.stdout + summary + '\n'}));
  for (const body of ['', "test.skip('skipped', () => {});", "test.todo('todo');",
    "test('failed', () => { throw new Error('original failure'); });"]) {
    write(files[1], body);
    assert.throws(() => verifySessionControls(directory, files, run(files)), body);
  }
  assert.throws(() => verifySessionControls(directory, [], result), /Empty/u);
  assert.throws(() => verifySessionControls(directory, files, {...result, status: 1}));
  assert.throws(() => verifySessionControls(directory, files, {...result, signal: 'SIGTERM', status: null}));
});
