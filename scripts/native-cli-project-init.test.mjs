import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp, readdir, rm, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {projectInitArguments, projectInitialAdoptionArguments} from '../packages/native-cli/lib/project-scaffold.mjs';

const launcher = fileURLToPath(new URL('../packages/native-cli/bin/actql.mjs', import.meta.url));
const scratch = async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-project-init-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
};
const command = (cwd, args) => spawnSync(process.execPath, [launcher, ...args],
  {cwd, encoding: 'utf8', timeout: 10_000, maxBuffer: 8192});

test('only init is intercepted while all protocol operations retain their original argv', () => {
  for (const args of [[], ['adopt'], ['run', 'program.aql'], ['--mode', 'local', 'connect'], ['initialize']]) {
    const before = structuredClone(args);
    assert.equal(projectInitArguments(args), undefined);
    assert.deepEqual(args, before);
  }
  assert.deepEqual(projectInitArguments(['init']), {directory: '.', template: undefined});
});

test('init admits exactly the documented template and optional directory in either order', () => {
  const expected = {directory: 'project', template: 'churn-risk-mock'};
  for (const args of [['init', '--template', 'churn-risk-mock', 'project'],
    ['init', 'project', '--template=churn-risk-mock']]) {
    assert.deepEqual(projectInitArguments(args), expected);
    assert(Object.isFrozen(projectInitArguments(args)));
  }
  assert.deepEqual(projectInitArguments(['init', 'project']), {directory: 'project', template: undefined});
});

test('init rejects unknown options, multiple targets and duplicate or incomplete template selection', () => {
  for (const tail of [['--runtime', 'replacement'], ['--approval', 'allow'], ['--initialize-signing'], ['--force'], ['a', 'b'],
    ['--template'], ['--template='], ['--template', '--'],
    ['--template=churn-risk-mock', '--template=churn-risk-mock'], ['--help', 'project']]) {
    assert.throws(() => projectInitArguments(['init', ...tail]), {code: 'ACTQL_E_INIT_ARGUMENTS'});
  }
  assert.throws(() => projectInitArguments(['init', '--template', 'other']), {code: 'ACTQL_E_TEMPLATE'});
});

test('prepared init requests the original Native initial-signing path without changing paths or supplying authority', () => {
  const project = Object.freeze({configuration: '/owned/project/actql.config.json',
    stateDirectory: '/owned/project/.actql'});
  const args = projectInitialAdoptionArguments(project);
  assert.deepEqual(args, ['--mode', 'local', '--config', '/owned/project/actql.config.json',
    '--state-dir', '/owned/project/.actql', 'adopt', '--initialize-signing']);
  assert(Object.isFrozen(args));
  assert.deepEqual(project, {configuration: '/owned/project/actql.config.json',
    stateDirectory: '/owned/project/.actql'});
});

test('the existing separator admits a dash-prefixed directory without treating it as a supplier option', () => {
  assert.deepEqual(projectInitArguments(['init', '--', '--directory']),
    {directory: '--directory', template: undefined});
});

test('public init help does not need a runtime or create project files', async t => {
  const root = await scratch(t);
  for (const help of ['--help', '-h']) {
    const result = command(root, ['init', help]);
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0);
    assert.equal(result.stderr, '');
    assert.equal(result.stdout, 'Usage: actql init [--template churn-risk-mock|deal-review-mock] [<directory>]\n');
  }
  assert.deepEqual(await readdir(root), []);
});

test('actual launcher rejects invalid preparation before writes or Native package selection', async t => {
  const root = await scratch(t);
  for (const tail of [['--template', 'other', 'project'], ['--runtime', 'replacement'], ['project', 'second']]) {
    const result = command(root, ['init', ...tail]);
    assert.equal(result.error, undefined);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.doesNotMatch(result.stderr, /Native package|Missing @actql|Unsupported platform/u);
    assert.deepEqual(await readdir(root), []);
  }
});

test('a real unavailable Native cohort refuses init before even template preparation', async t => {
  const root = await scratch(t);
  // The checkout has no staged platform mapping. This negative uses the actual
  // launcher and package resolver, not a fabricated Native success binary.
  const result = command(root, ['init', '--template', 'churn-risk-mock', 'project']);
  assert.equal(result.error, undefined);
  assert.notEqual(result.status, 0);
  if (['darwin', 'linux'].includes(process.platform)) {
    const mapping = fileURLToPath(new URL('../packages/native-cli/platforms.json', import.meta.url));
    assert.equal(result.stderr, `actql: ENOENT: no such file or directory, open '${mapping}'\n`);
  } else {
    assert.match(result.stderr, /Unsupported platform/u);
  }
  assert.equal(result.stdout, '');
  assert.deepEqual(await readdir(root), []);
});

// The root README and the churn Quickstart are distinct public examples.
// This checks the documented argv only: no Native runtime, Host or file write.
test('root README deal-review init selects its exact documented template and directory', async () => {
  const readme = await readFile(new URL('../README.md', import.meta.url), 'utf8');
  const line = readme.split(/\r?\n/u).find(value => value.startsWith('actql init --template '));
  assert.equal(line, 'actql init --template deal-review-mock deal-review && cd deal-review');
  const args = line.split(' && ')[0].split(' ').slice(1);
  assert.deepEqual(projectInitArguments(args), {directory: 'deal-review', template: 'deal-review-mock'});
});
