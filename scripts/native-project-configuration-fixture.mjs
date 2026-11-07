// Only populate the invocation's existing owned namespace. These files are
// reader test inputs, never installed project configuration or Run authority.
import {mkdirSync, symlinkSync, writeFileSync} from 'node:fs';
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
  for (const name of ['deal-review', 'deal-review-missing', 'deal-review-wrong-task']) {
    const path = directory(name);
    for (const [relative, original] of Object.entries(projectTemplateFiles('deal-review-mock'))) {
      if (name === 'deal-review-missing' && relative === 'mock/data.json') continue;
      mkdirSync(dirname(join(path, relative)), {recursive: true, mode: 0o700});
      const body = name === 'deal-review-wrong-task' && relative === 'model-tasks/deal-review.v1.yaml'
        ? original.replace('task: model-task:deal-review.v1', 'task: model-task:foreign.v1') : original;
      write(path, relative, body);
    }
  }
  return {ACTQL_TEST_NATIVE_PROJECT_CONFIGURATION_ROOT: root};
}
