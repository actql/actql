import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdir, mkdtemp, readdir, rm, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

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

// The installation directory holds the tarball, npm cache and smoke test.
// It is removed after every run, successful or not; set
// ACTQL_TEST_PRESERVE_SCRATCH=1 to keep it for inspection.
try {
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
  // The poll Output request for a retained Output Plan, from the packed
  // package, on a record built through its public owners.
  const coordinator = await import('@actql/coordinator-core');
  const {runtimeCore} = await import(${JSON.stringify(
    pathToFileURL(join(repository, 'adapters/host-common/runtime-core.mjs')).href)});
  const bridge = await import(${JSON.stringify(pathToFileURL(join(repository,
    '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js')).href)});
  const {durableOutputRecordFixture} = await import(${JSON.stringify(
    pathToFileURL(join(repository,
      'scripts/fixtures/remote-output-record-fixture.mjs')).href)});
  const fixture = durableOutputRecordFixture(coordinator, runtimeCore(bridge));
  // The installed package restores the admitted receipt, without transport
  // pending state. A replay's durable body/revision and start eligibility are
  // unchanged; this does not claim a native executor ran in this fixture.
  const replayRecord = coordinator.restoreDurable(
    coordinator.createJournal('coordinator-a'), fixture.durable);
  const replayResponse = coordinator.admitResponseJson(
    fixture.reply, fixture.request, true);
  const stateBeforeReplay = coordinator.recordStateCodes(replayRecord);
  const replay = coordinator.prepareResponseObservation(replayRecord, replayResponse);
  assert.equal(coordinator.transitionIsReplay(replay), true);
  assert.equal(coordinator.transitionExpectedRevision(replay), 1);
  const replayBody = coordinator.responseDurableJson(
    fixture.durable, replay, replayResponse);
  assert.equal(JSON.parse(replayBody).version,
    'actql-remote-coordinator-history-record/0.1');
  assert.equal(JSON.parse(replayBody).revision, 1);
  assert.equal(JSON.parse(JSON.parse(replayBody).observation_history_json).length, 1);
  coordinator.commitTransition(replay);
  assert.deepEqual(coordinator.recordStateCodes(replayRecord), stateBeforeReplay);
  assert.equal(coordinator.exactRetransmissionEligible(replayRecord, fixture.request), false);
  const replayAgain = coordinator.prepareResponseObservation(replayRecord, replayResponse);
  assert.equal(coordinator.responseDurableJson(
    fixture.durable, replayAgain, replayResponse), replayBody);
  const outputRequest = JSON.parse(
    coordinator.durableOutputRequestJson(fixture.outputDurable));
  assert.equal(outputRequest.version, 'actql-remote-poll-output/0.1');
  assert.equal(outputRequest.dispatch_request_cid, fixture.requestCid);
  assert.equal(outputRequest.intent_json,
    JSON.parse(coordinator.durableOutputPollJson(fixture.outputDurable))
      .intent_json);
  console.log('packed coordinator-core release, not-seen, output request and durable replay');
  `);
  process.stdout.write(run(process.execPath, ['smoke.mjs'], installation));
} finally {
  if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
    console.error(`packed coordinator-core scratch kept: ${installation}`);
  } else {
    await rm(installation, {recursive: true, force: true});
  }
}
