// Only populate the invocation's existing owned namespace. These files are
// reader test inputs, never installed project configuration or Run authority.
import assert from 'node:assert/strict';
import {mkdirSync, readFileSync, symlinkSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {dirname, join} from 'node:path';
import {projectTemplateFiles} from '../packages/native-cli/lib/project-template.mjs';

export function nativeProjectConfigurationFixture(namespace) {
  const root = join(namespace, 'project-configuration');
  mkdirSync(root, {mode: 0o700});
  const directory = name => {
    const path = join(root, name);
    mkdirSync(path, {mode: 0o700});
    return path;
  };
  const write = (directory, name, body) => writeFileSync(join(directory, name), body,
    {mode: 0o600, flag: 'wx'});
  const configuration = state => JSON.stringify({version: 'actql-config/0.1',
    ...(state === undefined ? {} : {state_dir: state})});
  write(root, 'actql.config.json', configuration());
  for (const [name, state] of [['parent', '.parent-state'], ['nearer', '.nearer-state']]) {
    const path = directory(name);
    mkdirSync(join(path, 'child'), {mode: 0o700});
    write(path, 'actql.config.json', configuration(state));
  }
  for (const name of ['malformed', 'symlink', 'oversize', 'invalid-utf8', 'directory']) {
    const path = directory(name);
    mkdirSync(join(path, 'child'), {mode: 0o700});
    if (name === 'symlink') symlinkSync('../actql.config.json', join(path, 'actql.config.json'));
    else if (name === 'directory') mkdirSync(join(path, 'actql.config.json'), {mode: 0o700});
    else write(path, 'actql.config.json', name === 'malformed' ? '{' : name === 'oversize'
      ? Buffer.alloc(65537, 0x20) : Buffer.from([0xc3, 0x28]));
  }
  // Independent declaration wires match the existing Common source-free
  // project contract; nonempty and malformed files must remain refusals.
  const connectors = '{"version":"actql-connectors/0.1","connections":{}}';
  const models = '{"version":"actql-model-tasks/0.1","tasks":{},"providers":{}}';
  for (const name of ['plain', 'connector', 'model', 'provider', 'default-provider',
    'bad-connectors', 'bad-model', 'duplicate-connectors']) {
    const path = directory(name);
    if (name === 'plain') mkdirSync(join(path, 'nested'), {mode: 0o700});
    write(path, 'connectors.json', name === 'connector'
      ? '{"version":"actql-connectors/0.1","connections":{"salesforce":{"connector":"salesforce"}}}'
      : name === 'bad-connectors' ? '{}' : name === 'duplicate-connectors'
        ? '{"version":"actql-connectors/0.1","connections":{"x":{},"x":{}},"connections":{}}'
        : connectors);
    write(path, 'model-tasks.json', name === 'model'
      ? '{"version":"actql-model-tasks/0.1","tasks":{"t":"task.yaml"},"providers":{}}'
      : name === 'provider'
        ? '{"version":"actql-model-tasks/0.1","tasks":{},"providers":{"p":{"type":"openai"}}}'
        : name === 'default-provider'
          ? '{"version":"actql-model-tasks/0.1","tasks":{},"providers":{},"default_provider":"p"}'
          : name === 'bad-model' ? '{}' : models);
  }
  for (const name of ['missing-bindings', 'symlink-bindings', 'oversize-bindings',
    'invalid-utf8-bindings', 'directory-bindings']) {
    const path = directory(name);
    if (name === 'missing-bindings') continue;
    if (name === 'symlink-bindings') symlinkSync('../plain/connectors.json', join(path, 'connectors.json'));
    else if (name === 'directory-bindings') mkdirSync(join(path, 'connectors.json'), {mode: 0o700});
    else write(path, 'connectors.json', name === 'oversize-bindings'
      ? Buffer.alloc(65537, 0x20) : Buffer.from([0xc3, 0x28]));
  }
  // Exact public authored inputs, not an old business-state fixture.
  for (const name of ['deal-review', 'deal-review-missing', 'deal-review-wrong-task', 'deal-review-nested-registry', 'deal-review-wrong-answer', 'deal-review-missing-task']) {
    const path = directory(name);
    for (const [originalPath, original] of Object.entries(projectTemplateFiles('deal-review-mock'))) {
      if (name === 'deal-review-missing' && originalPath === 'mock/data.json') continue;
      if (name === 'deal-review-missing-task' && originalPath === 'model-tasks/deal-review.v1.yaml') {
        // Reach the actual missing-file Reader boundary, with its owned Root
        // present. An absent parent instead tests Root construction refusal.
        mkdirSync(dirname(join(path, originalPath)), {recursive: true, mode: 0o700});
        continue;
      }
      let relative = originalPath;
      let body = name === 'deal-review-wrong-task' && relative === 'model-tasks/deal-review.v1.yaml'
        ? original.replace('task: model-task:deal-review.v1', 'task: model-task:foreign.v1') : original;
      if (name === 'deal-review-wrong-answer' && relative === 'mock/deal-review.v1.answers.yaml') {
        body = original.replace('changed: true', 'changed: "not-a-boolean"');
      }
      if (name === 'deal-review-nested-registry') {
        // A distinct locator-only case, never retagged as the exact template.
        if (relative === 'actql.config.json') body = original.replace('./model-tasks.json', './registry/model-tasks.json');
        if (relative === 'model-tasks.json') {
          relative = 'registry/model-tasks.json';
          body = original.replace('./model-tasks/deal-review.v1.yaml', '../model-tasks/deal-review.v1.yaml');
        }
      }
      mkdirSync(dirname(join(path, relative)), {recursive: true, mode: 0o700});
      write(path, relative, body);
    }
  }
  // Independent oracle for the SAME public File-facts consumer. The missing
  // payload case still supplies only its original locator/catalogue metadata.
  const missing = join(root, 'deal-review-missing');
  const scope = JSON.stringify({catalog: readFileSync(join(missing, 'mock/catalog.json'), 'utf8'),
    connection: 'drive', connector: 'drive', dataPath: join(missing, 'mock/data.json')});
  const scopeCid = 'sha256:' + createHash('sha256').update(scope).digest('hex');
  // The issuer case projects this public document in memory. Keep the missing
  // payload locator absent, and derive its oracle from the independent ASCII
  // canonical identity preimage rather than the Native issuer's output.
  const resource = JSON.stringify({collection: 'files', identity: 'file-acme-notes', scope: scopeCid});
  const data = JSON.parse(projectTemplateFiles('deal-review-mock')['mock/data.json']);
  const contentDigests = Object.fromEntries(data.drive.files.rows.map(row => [row.id,
    'sha256:' + createHash('sha256').update(Buffer.from(row.content_utf8, 'utf8')).digest('hex')]));
  return {ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT: root,
    ACTQL_TEST_NATIVE_CONTENT_DIGESTS: JSON.stringify(contentDigests),
    ACTQL_TEST_NATIVE_QUERY_CONTRACT: readFileSync(new URL('../spec/contracts/actql-query-acquisition.json', import.meta.url), 'utf8'),
    ACTQL_TEST_NATIVE_EVIDENCE_CONTRACT: readFileSync(new URL('../spec/contracts/actql-query-process-evidence.json', import.meta.url), 'utf8'),
    ACTQL_TEST_NATIVE_MOCK_DRIVE_SCOPE_CID: scopeCid,
    ACTQL_TEST_NATIVE_MOCK_FILE_DATA: projectTemplateFiles('deal-review-mock')['mock/data.json'],
    ACTQL_TEST_NATIVE_MOCK_FIRST_RESOURCE_CID: 'sha256:' + createHash('sha256').update(resource).digest('hex')};
}

// All three authored cases retain distinct fresh Stores. The first two keep
// their original one/two lookups; only the third selects Source-closure proof.
// Neither an ambient count nor a closure flag can retarget another case.
export function nativeProjectContentCaseFixture(namespace, index) {
  assert(Number.isInteger(index) && index >= 0 && index <= 2,
    'An exact original Native Content case index is required');
  const store = join(namespace, 'content-store');
  mkdirSync(store, {mode: 0o700});
  return {ACTQL_TEST_NATIVE_CONTENT_LOOKUPS: index === 0 ? '1' : '2',
    ACTQL_TEST_NATIVE_MODEL_SOURCE_CLOSURE: index === 2 ? '1' : undefined,
    ACTQL_TEST_NATIVE_STORE_ROOT: store};
}
