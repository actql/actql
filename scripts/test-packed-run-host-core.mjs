import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, readdir, writeFile} from
  'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const installation = await mkdtemp(join(build, 'packed-run-host-core-'));
const environment = {...process.env,
  npm_config_cache: join(installation, 'npm-cache')};

function run(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: 30000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

run('npm', ['pack', '--pack-destination', installation, '--json'],
  join(repository, 'packages/run-host-core'));
await writeFile(join(installation, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--offline', '--ignore-scripts', '--no-save',
  join(installation, 'actql-run-host-core-0.0.0-development.tgz')],
installation);
assert.deepEqual(await readdir(join(installation, 'node_modules/@actql')),
  ['run-host-core']);
for (const name of ['values.json', 'values.environment.json']) {
  await writeFile(join(installation, name),
    await readFile(join(repository, 'packages/sdk/fixtures', name)));
}
await writeFile(join(installation, 'smoke.mjs'), `
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
globalThis.fetch = async () => { throw new Error('NetworkOnHostImport'); };
const {admitEnvironment, prepare, compileValues, executionShape,
  resultDefinitions, resultSchema, prepareSourceFreeRequest,
  requestFields, issueAllowedRun, issueRunDefinition,
  issueSourceFreeInvocation, inspectCanonicalResultRows} =
  await import('@actql/run-host-core');
const environmentWire = readFileSync('values.environment.json', 'utf8')
  .trimEnd();
const environment = admitEnvironment(environmentWire,
  JSON.parse(environmentWire).evidence_bundle_cid, {rela: true});
const prepared = prepare(readFileSync('values.json', 'utf8'), 'json',
  environment);
const compilation = compileValues(prepared);
assert.deepEqual(executionShape(compilation), {
  planNodeId: 'values_0',
  outputContractCid:
    'sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c',
  resultNames: ['answer'],
});
assert.deepEqual(resultSchema(prepared, compilation), {
  cid: 'sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513',
  wire: '{"id":{"nullable":false,"type":"number"}}', fields: ['id'],
});
assert.deepEqual(resultDefinitions(prepared, compilation)
  .map(result => result.name), ['answer']);
const scope = 'sha256:' + 'a'.repeat(64);
const request = prepareSourceFreeRequest(prepared, compilation, scope,
  'packed-host-request');
assert.equal(requestFields(request).authorityScopeCid, scope);
const allowed = issueAllowedRun(prepared, compilation, {
  executionContextCid: 'sha256:' + 'b'.repeat(64),
  hostPolicyCid: 'sha256:' + 'c'.repeat(64),
  expiresAt: '2099-01-01T00:00:00.000Z',
});
const definition = issueRunDefinition(allowed.admission,
  'packed-scope', 'packed-run', 'sha256:' + 'd'.repeat(64),
  '2026-09-24T00:00:00.000Z', '2027-01-01T00:00:00.000Z');
const invocation = issueSourceFreeInvocation(prepared, compilation,
  allowed.admission, definition, 'sha256:' + 'e'.repeat(64),
  {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64});
assert.equal(JSON.parse(invocation.observation.wire).source_evidence_cids
  .length, 0);
assert.deepEqual(inspectCanonicalResultRows('[{"id":1},{"id":2}]',
  ['id'], {maxWireBytes: 4096, maxNodes: 100, maxDepth: 16}), {
  logicalRelationCid:
    'sha256:ffd3ea44b8fb5324bbdc17735e31f10e00f60e5debddd3be1957f712204f331f',
  rowCount: 2,
});
`);
run(process.execPath, ['smoke.mjs'], installation);
console.log('packed portable Run Host admission and row inspection passed');
