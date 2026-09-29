import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

// The Coordinator owners a Cloud adopts are called through the packed
// @actql/coordinator-core, not the repository sources.
const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const installation = await mkdtemp(join(build, 'packed-coordinator-core-'));
const environment = {...process.env,
  npm_config_cache: join(installation, 'npm-cache')};

function run(command, args, cwd) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: command === 'npm' && args[0] === 'pack' ? 180000 : 30000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

run('npm', ['pack', '--pack-destination', installation, '--json'],
  join(repository, 'packages/coordinator-core'));
await writeFile(join(installation, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--offline', '--ignore-scripts', '--no-save',
  join(installation, 'actql-coordinator-core-0.0.0-development.tgz')],
installation);
assert.deepEqual(await readdir(join(installation, 'node_modules/@actql')),
  ['coordinator-core']);
await writeFile(join(installation, 'smoke.mjs'), `
import assert from 'node:assert/strict';
const {admitPollNotSeen, dispatchCid, pollQueryJson, pollReleaseJson,
  prepareDispatch} = await import('@actql/coordinator-core');
const cid = digit => 'sha256:' + digit.repeat(64);
const dispatch = dispatchId => prepareDispatch({
  coordinatorAuthority: 'coordinator-a', runDefinitionCid: cid('0'),
  taskKey: 'task-a', taskAttempt: 1, dispatchId, siteKey: 'site-a',
  siteGeneration: 1, runtimeBundleCid: cid('a'),
  connectorRegistration: 'local', connectorRevision: 'local/1',
  strategyRevision: 'strategy/1', inputBindingCid: cid('1'),
  obligationsCid: cid('2'), budgetCid: cid('3'),
  evidenceIssuerCapabilityCid: cid('b'), grantCid: cid('4')});
const request = dispatch('dispatch-a');
const requestCid = dispatchCid(request);
const release = JSON.parse(pollReleaseJson(request));
assert.equal(release.version, 'actql-remote-poll-release/0.1');
assert.equal(release.dispatch_request_cid, requestCid);
assert.equal(release.request_json, JSON.parse(pollQueryJson(request)).request_json);
const notSeen = value => JSON.stringify({dispatch_request_cid: value,
  version: 'actql-remote-dispatch-not-seen/0.1'});
assert.equal(admitPollNotSeen(notSeen(requestCid), request), true);
assert.throws(() => admitPollNotSeen(
  notSeen(dispatchCid(dispatch('dispatch-b'))), request),
{code: 'CoordinatorOwnerRejected'});
console.log('packed coordinator-core release and not-seen');
`);
process.stdout.write(run(process.execPath, ['smoke.mjs'], installation));
