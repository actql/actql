import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp, mkdir, readFile, readdir, rm, stat, symlink, writeFile, chmod} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {scaffoldProject} from '../packages/native-cli/lib/project-scaffold.mjs';
import {projectTemplateFiles} from '../packages/native-cli/lib/project-template.mjs';

const scratch = async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-project-scaffold-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
};
const json = async path => JSON.parse(await readFile(path, 'utf8'));

test('the Quickstart template prepares seven inputs and leaves state creation to the installation Owner', async t => {
  const root = await scratch(t), project = join(root, 'churn-risk');
  const result = scaffoldProject(project, 'churn-risk-mock');
  assert.equal(result.files.length, 7);
  assert.deepEqual([...result.files].sort(), ['actql.config.json', 'churn-risk.aql', 'connectors.json',
    'mock/churn-risk.v1.answers.yaml', 'mock/data.json', 'model-tasks.json', 'model-tasks/churn-risk.v1.yaml']);
  assert.deepEqual(await json(result.configuration), {
    version: 'actql-config/0.1', connectors: './connectors.json', model_tasks: './model-tasks.json',
    state_dir: './.actql', profile: 'mock', mock: {data: './mock/data.json',
      answers: {'model-task:churn-risk.v1': './mock/churn-risk.v1.answers.yaml'}},
  });
  await assert.rejects(stat(result.stateDirectory), {code: 'ENOENT'});
  assert.equal(Object.hasOwn(result, 'initialized'), false);
  assert.equal(Object.hasOwn(result, 'runnable'), false);
});

test('mock data retains both source keys, original field values and independent expected joins', async t => {
  const root = await scratch(t), result = scaffoldProject(join(root, 'project'), 'churn-risk-mock');
  const data = await json(join(result.directory, 'mock/data.json'));
  assert.deepEqual(data.salesforce.Account.key, ['id']);
  assert.deepEqual(data.snowflake.usage_30d.key, ['account_id']);
  const rows = data.salesforce.Account.rows.map(account => ({id: account.id,
    risk: account.Churn_Risk__c, users: data.snowflake.usage_30d.rows.find(x => x.account_id === account.id).active_users}));
  assert.deepEqual(rows, [{id: '001Acme', risk: 'low', users: 4}, {id: '001Globex', risk: 'medium', users: 12}]);
  assert(data.salesforce.Account.rows.every(x => x.Risk_Reason__c === null));
  const connections = await json(join(result.directory, 'connectors.json'));
  assert.deepEqual(connections.connections, {salesforce: {connector: 'salesforce'}, snowflake: {connector: 'snowflake'}});
  const model = await json(join(result.directory, 'model-tasks.json'));
  assert.equal(model.providers.openai.api_key_env, 'OPENAI_API_KEY');
  assert.equal(model.tasks['model-task:churn-risk.v1'], './model-tasks/churn-risk.v1.yaml');
  // No credential file or environment variable is read by template preparation.
  assert.equal(Object.hasOwn(connections.connections.salesforce, 'credentials'), false);
});

test('the SQL/AQL program and YAML instructions match the documented Quickstart rather than a simpler query', async t => {
  const root = await scratch(t), result = scaffoldProject(join(root, 'project'), 'churn-risk-mock');
  const docs = await readFile(new URL('../docs/getting-started/quickstart.md', import.meta.url), 'utf8');
  const program = await readFile(join(result.directory, 'churn-risk.aql'), 'utf8');
  assert.equal(program, docs.match(/```sql\n([\s\S]*?)```/u)[1]);
  const yaml = [...docs.matchAll(/```yaml\n([\s\S]*?)```/gu)].map(match => match[1]);
  assert.equal(await readFile(join(result.directory, 'model-tasks/churn-risk.v1.yaml'), 'utf8'), yaml[0]);
  assert.equal(await readFile(join(result.directory, 'mock/churn-risk.v1.answers.yaml'), 'utf8'), yaml[1]);
});

test('a plain project has empty registries and no implicitly selected mock profile', async t => {
  const root = await scratch(t), result = scaffoldProject(join(root, 'project'));
  assert.equal(result.files.length, 3);
  assert.equal(Object.hasOwn(await json(result.configuration), 'profile'), false);
  assert.deepEqual((await json(join(result.directory, 'connectors.json'))).connections, {});
  assert.deepEqual((await json(join(result.directory, 'model-tasks.json'))).providers, {});
  await assert.rejects(stat(result.stateDirectory), {code: 'ENOENT'});
});

test('an unknown template is rejected before creating a directory', async t => {
  const root = await scratch(t);
  assert.throws(() => scaffoldProject(join(root, 'project'), 'unknown'), {code: 'ACTQL_E_TEMPLATE'});
  assert.deepEqual(await readdir(root), []);
});

test('existing project files, state and partial preparations are preserved on retry', async t => {
  const root = await scratch(t), project = join(root, 'project');
  const result = scaffoldProject(project, 'churn-risk-mock');
  await mkdir(result.stateDirectory, {mode: 0o700});
  await writeFile(join(result.stateDirectory, 'retained-original'), 'do not replace');
  const before = await readFile(result.configuration);
  assert.throws(() => scaffoldProject(project, 'churn-risk-mock'), {code: 'ACTQL_E_PROJECT_EXISTS'});
  assert.deepEqual(await readFile(result.configuration), before);
  assert.equal(await readFile(join(result.stateDirectory, 'retained-original'), 'utf8'), 'do not replace');
  const partial = join(root, 'partial'); await mkdir(partial); await mkdir(join(partial, '.actql'), {mode: 0o700});
  assert.throws(() => scaffoldProject(partial), {code: 'ACTQL_E_PROJECT_EXISTS'});
  assert.deepEqual(await readdir(partial), ['.actql']);
});

test('an empty existing owned directory works while a linked destination is refused', async t => {
  const root = await scratch(t), empty = join(root, 'empty'), linked = join(root, 'linked');
  await mkdir(empty); await symlink(empty, linked);
  assert.throws(() => scaffoldProject(linked), {code: 'ACTQL_E_PROJECT_EXISTS'});
  assert.deepEqual(await readdir(empty), []);
  assert.equal(scaffoldProject(empty).files.length, 3);
});

test('a group-writable project directory is refused without chmod or file writes', async t => {
  const root = await scratch(t), project = join(root, 'project');
  await mkdir(project); await chmod(project, 0o770);
  assert.throws(() => scaffoldProject(project), {code: 'ACTQL_E_PROJECT_EXISTS'});
  assert.equal((await stat(project)).mode & 0o777, 0o770);
  assert.deepEqual(await readdir(project), []);
});

test('invalid paths fail without creating a project and returned template files cannot be replaced', async t => {
  await scratch(t);
  for (const path of ['', null, 'nul\0name', 'x'.repeat(4097)]) {
    assert.throws(() => scaffoldProject(path), {code: 'ACTQL_E_PROJECT_PATH'});
  }
  const files = projectTemplateFiles('churn-risk-mock');
  assert.throws(() => {files['churn-risk.aql'] = 'SELECT 1';}, TypeError);
  assert.match(projectTemplateFiles('churn-risk-mock')['churn-risk.aql'], /EFFECT UPDATE salesforce.Account/u);
});
