import assert from 'node:assert/strict';
import {test} from 'node:test';
import {copyFile, mkdir, mkdtemp, readFile, readdir, rm, stat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {nativeCliPackageInputs} from './native-cli-package-inputs.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

test('formal Native launcher copies include both private project helpers', () => {
  const selected = nativeCliPackageInputs(root);
  assert.equal(selected.manifest, 'packages/native-cli/package.json');
  assert.deepEqual(selected.copies, [
    'README.md', 'bin/actql.mjs', 'lib/local-runtime.mjs', 'lib/product-members.mjs',
    'lib/project-template.mjs', 'lib/project-scaffold.mjs',
  ].map(member => ({member, source: `packages/native-cli/${member}`})));
});

test('staged private project preparation runs from exact selected bytes without a source overlay', async t => {
  const scratch = await mkdtemp(join(tmpdir(), 'actql-cli-project-stage-'));
  t.after(() => rm(scratch, {recursive: true, force: true}));
  const stage = join(scratch, 'cli');
  await mkdir(stage);
  for (const {source, member} of nativeCliPackageInputs(root).copies) {
    const destination = join(stage, member);
    await mkdir(dirname(destination), {recursive: true});
    await copyFile(join(root, source), destination);
    assert.deepEqual(await readFile(destination), await readFile(join(root, source)));
    assert.equal((await stat(destination)).mode & 0o777, (await stat(join(root, source))).mode & 0o777);
  }
  await writeFile(join(stage, 'package.json'), '{"type":"module"}\n');
  const {scaffoldProject} = await import(pathToFileURL(join(stage, 'lib/project-scaffold.mjs')));
  const project = join(scratch, 'project');
  const result = scaffoldProject(project, 'churn-risk-mock');
  assert.deepEqual([...result.files].sort(), ['actql.config.json', 'churn-risk.aql', 'connectors.json',
    'mock/catalog.json', 'mock/churn-risk.v1.answers.yaml', 'mock/data.json', 'model-tasks.json', 'model-tasks/churn-risk.v1.yaml']);
  assert.equal(await readFile(join(project, 'churn-risk.aql'), 'utf8'),
    (await readFile(join(root, 'docs/getting-started/quickstart.md'), 'utf8')).match(/```sql\n([\s\S]*?)```/u)[1]);
  assert.deepEqual(await readdir(join(stage, 'lib')), [
    'local-runtime.mjs', 'product-members.mjs', 'project-scaffold.mjs', 'project-template.mjs',
  ]);
  await assert.rejects(stat(result.stateDirectory), {code: 'ENOENT'});
  assert.throws(() => scaffoldProject(project), {code: 'ACTQL_E_PROJECT_EXISTS'});
});
