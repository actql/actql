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

test('the Quickstart template prepares eight inputs and leaves state creation to the installation Owner', async t => {
  const root = await scratch(t), project = join(root, 'churn-risk');
  const result = scaffoldProject(project, 'churn-risk-mock');
  assert.equal(result.files.length, 8);
  assert.deepEqual([...result.files].sort(), ['actql.config.json', 'churn-risk.aql', 'connectors.json',
    'mock/catalog.json', 'mock/churn-risk.v1.answers.yaml', 'mock/data.json', 'model-tasks.json', 'model-tasks/churn-risk.v1.yaml']);
  assert.deepEqual(await json(result.configuration), {
    version: 'actql-config/0.1', connectors: './connectors.json', model_tasks: './model-tasks.json',
    state_dir: './.actql', profile: 'mock', mock: {catalog: './mock/catalog.json', data: './mock/data.json',
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

test('root README deal-review template prepares its exact Program and typed Task without initializing state', async t => {
  const root = await scratch(t), result = scaffoldProject(join(root, 'deal-review'), 'deal-review-mock');
  assert.deepEqual([...result.files].sort(), ['actql.config.json', 'connectors.json', 'deal-review.aql',
    'mock/catalog.json', 'mock/data.json', 'mock/deal-review.v1.answers.yaml', 'model-tasks.json', 'model-tasks/deal-review.v1.yaml']);
  const readme = await readFile(new URL('../README.md', import.meta.url), 'utf8');
  assert.equal(await readFile(join(result.directory, 'deal-review.aql'), 'utf8'),
    readme.match(/```sql\n([\s\S]*?)```/u)[1]);
  assert.deepEqual(await json(result.configuration), {version: 'actql-config/0.1',
    connectors: './connectors.json', model_tasks: './model-tasks.json', state_dir: './.actql',
    profile: 'mock', mock: {catalog: './mock/catalog.json', data: './mock/data.json',
      answers: {'model-task:deal-review.v1': './mock/deal-review.v1.answers.yaml'}}});
  assert.deepEqual((await json(join(result.directory, 'connectors.json'))).connections,
    {salesforce: {connector: 'salesforce'}, drive: {connector: 'drive'}});
  assert.equal((await json(join(result.directory, 'model-tasks.json'))).tasks['model-task:deal-review.v1'],
    './model-tasks/deal-review.v1.yaml');
  const task = await readFile(join(result.directory, 'model-tasks/deal-review.v1.yaml'), 'utf8');
  assert.match(task, /^task: model-task:deal-review\.v1\n/u);
  assert.match(task, /  NextStep: \{type: string, nullable: true\}\n/u);
  assert.match(task, /  notes: \{type: content_ref, nullable: false\}\n/u);
  assert.doesNotMatch(task, /notes: string/u);
  await assert.rejects(stat(result.stateDirectory), {code: 'ENOENT'});
  assert.equal(Object.hasOwn(result, 'runnable'), false);
});

test('deal-review Mock DATA contains only original Opportunity rows and UTF8 Drive documents keyed by ID', async t => {
  const root = await scratch(t), result = scaffoldProject(join(root, 'deal-review'), 'deal-review-mock');
  const data = await json(join(result.directory, 'mock/data.json'));
  assert.deepEqual(Object.keys(data).sort(), ['drive', 'salesforce']);
  assert.deepEqual(Object.keys(data.salesforce), ['Opportunity']);
  assert.deepEqual(Object.keys(data.drive), ['files']);
  const opportunities = data.salesforce.Opportunity, files = data.drive.files;
  assert.deepEqual(opportunities.key, ['id']);
  assert.deepEqual(files.key, ['id']);
  assert.deepEqual(opportunities.rows, [
    {id: '006Acme', name: 'Acme Corp - Renewal', StageName: 'Proposal', NextStep: null},
    {id: '006Globex', name: 'Globex - Expansion', StageName: 'Negotiation', NextStep: 'Legal review'},
  ]);
  assert.equal(files.rows.length, 2);
  assert.equal(new Set(files.rows.map(row => row.id)).size, 2);
  for (const row of files.rows) {
    assert.deepEqual(Object.keys(row).sort(), ['content_utf8', 'id', 'media_type', 'name', 'version']);
    assert.equal(row.media_type, 'text/plain');
    assert.equal(typeof row.version, 'string');
    assert(row.version.length > 0);
    assert.equal(typeof row.content_utf8, 'string');
    assert(row.content_utf8.endsWith('\n'));
    assert(opportunities.rows.some(opportunity => opportunity.name === row.name));
  }
  // Names are join values, never declared keys or serialized physical subjects.
  assert.equal(Object.hasOwn(data.drive, 'contents'), false);
  assert.doesNotMatch(JSON.stringify(data), /"(?:resource|content_ref_cid|availability_evidence_cid|issuer_evidence|\$actql_ref)":/u);
  const answers = await readFile(join(result.directory, 'mock/deal-review.v1.answers.yaml'), 'utf8');
  assert.match(answers, /^task: model-task:deal-review\.v1\n/u);
  assert.match(answers, /"006Acme": \{changed: true, stage: Negotiation, next_step: "Send revised pricing by Friday"\}/u);
  assert.match(answers, /"006Globex": \{changed: true, stage: "Closed Lost", next_step: "Revisit next fiscal year"\}/u);
});


test('mock template catalogs declare existing typed rows keys aliases and write permissions', () => {
  for (const [template, resource, alias, writable] of [
    ['churn-risk-mock', 'Account', 'salesforce.accounts', ['Churn_Risk__c', 'Risk_Reason__c']],
    ['deal-review-mock', 'Opportunity', 'salesforce.opportunities', ['StageName', 'NextStep']],
  ]) {
    const files = projectTemplateFiles(template);
    const configuration = JSON.parse(files['actql.config.json']);
    const catalog = JSON.parse(files['mock/catalog.json']);
    const data = JSON.parse(files['mock/data.json']);
    assert.equal(configuration.profile, 'mock');
    assert.equal(configuration.mock.catalog, './mock/catalog.json');
    const declared = catalog.connections.salesforce;
    assert.deepEqual(declared.query_aliases, [{name: alias, resource}]);
    assert.deepEqual(declared.views[0].facts, {relation_keys: {candidate_keys: [['id']]}});
    assert.deepEqual(declared.views[0].schema.id, {type: 'string', nullable: false});
    assert.deepEqual(declared.data, [{resource, items_path: ['salesforce', resource, 'rows'],
      key_path: ['salesforce', resource, 'key'], primary_identity: 'id'}]);
    assert.deepEqual(declared.writes, [{resource, primary_identity: 'id', writable_fields: writable,
      permission: 'salesforce:record:update', observe_permission: 'salesforce:record:observe',
      approval: 'required', aliases: [`salesforce.${resource}`]}]);
    assert.deepEqual(data.salesforce[resource].key, ['id']);
    assert.doesNotMatch(files['mock/catalog.json'], /sha256:|schema_wire|schema_cid|scenario|template/u);
  }
  const catalog = JSON.parse(projectTemplateFiles('churn-risk-mock')['mock/catalog.json']);
  assert.deepEqual(catalog.connections.snowflake.views[0].schema.active_users,
    {type: 'int64', nullable: false});
  assert.deepEqual(catalog.connections.snowflake.views[0].facts,
    {relation_keys: {candidate_keys: [['account_id']]}});
  assert.equal(Object.hasOwn(catalog.connections.snowflake, 'writes'), false);
});

test('deal-review catalog separates physical UTF8 files from logical keyed Content views', () => {
  const catalog = JSON.parse(projectTemplateFiles('deal-review-mock')['mock/catalog.json']);
  const drive = catalog.connections.drive;
  const [listing, contents] = drive.views;
  assert.deepEqual(Object.keys(listing.schema).sort(),
    ['media_type', 'modified_at', 'name', 'path', 'resource', 'size_bytes', 'version']);
  assert.deepEqual(listing.acquisition, {kind: 'scan', authority: 'read_metadata'});
  assert.deepEqual(listing.schema.resource, {type: 'resource_ref', resource_kind: 'file', nullable: false});
  assert.deepEqual(Object.keys(contents.schema).sort(), ['content', 'resource', 'version']);
  assert.deepEqual(contents.schema.content, {type: 'content_ref', media_type: 'text/plain', nullable: false});
  assert.deepEqual(contents.request_schema, {type: 'object', nullable: false,
    additional_properties: false, fields: {
      resource: {type: 'resource_ref', resource_kind: 'file', nullable: false},
      version: {type: 'string', nullable: false},
    }});
  assert.deepEqual(contents.acquisition, {kind: 'fetch', authority: 'read_content', correlation: {
    request_fields: ['resource', 'version'], response_fields: ['resource', 'version'],
    identity: ['resource', 'version'], cardinality: 'one',
  }});
  for (const view of drive.views) {
    assert.equal(Object.hasOwn(view, 'facts'), false, 'the installed owner binds file profile identities');
    assert.equal(Object.hasOwn(view, 'resource_identity'), false);
  }
  assert.deepEqual(drive.query_aliases, [{name: 'drive.files', resource: 'files'},
    {name: 'drive.contents', resource: 'contents'}]);
  assert.deepEqual(drive.file_bindings, [{listing_resource: 'files', content_resource: 'contents',
    data_resource: 'files', identity_field: 'id', name_field: 'name', version_field: 'version',
    media_type_field: 'media_type', content_utf8_field: 'content_utf8'}]);
  assert.equal(drive.data.length, 1);
  assert.deepEqual(drive.data[0], {resource: 'files', items_path: ['drive', 'files', 'rows'],
    key_path: ['drive', 'files', 'key'], primary_identity: 'id', schema: {
      id: {type: 'string', nullable: false}, name: {type: 'string', nullable: false},
      version: {type: 'string', nullable: false}, media_type: {type: 'string', nullable: false},
      content_utf8: {type: 'string', nullable: false},
    }});
});
