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
  const context = {coordinatorAuthority: 'coordinator-a', siteKey: 'site-a',
    siteGeneration: 1, authorizationCurrent: true, cancellationRequested: false};
  // Query-before-send decisions come from the same packed owner. Terminal
  // evidence is never downgraded to Accepted/unstarted delivery eligibility.
  assert.equal(coordinator.redeliveryEligible(replayRecord, fixture.request, '', context), false);
  assert.throws(() => coordinator.redeliveryEligible(replayRecord, fixture.request, '',
    {...context, siteGeneration: 2}), {code: 'CoordinatorOwnerRejected'});
  const fresh = coordinator.restoreDurable(coordinator.createJournal('coordinator-a'),
    coordinator.admitDurableJson(coordinator.admissionDurableJson(
      coordinator.prepareIntent(coordinator.createJournal('coordinator-a'), request))));
  assert.equal(coordinator.redeliveryEligible(fresh, request, '', context), false);
  assert.equal(coordinator.redeliveryEligible(fresh, request, notSeen(requestCid), context), true);
  assert.equal(coordinator.redeliveryEligible(fresh, request, notSeen(requestCid),
    {...context, authorizationCurrent: false}), false);
  assert.equal(coordinator.redeliveryEligible(fresh, request, notSeen(requestCid),
    {...context, cancellationRequested: true}), false);
  const {createHash} = await import('node:crypto');
  const bindingCid = 'sha256:' + createHash('sha256').update('{}').digest('hex');
  const deliverable = coordinator.prepareDispatch({
    coordinatorAuthority: 'coordinator-a', runDefinitionCid: cid('0'), taskKey: 'task-a',
    taskAttempt: 1, dispatchId: 'packed-r2-envelope', siteKey: 'site-a', siteGeneration: 1,
    runtimeBundleCid: cid('a'), connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1', inputBindingCid: bindingCid, obligationsCid: cid('2'),
    budgetCid: cid('3'), evidenceIssuerCapabilityCid: cid('b'), grantCid: cid('4'),
  });
  const delivery = coordinator.pollDispatchMaterialsJson(deliverable, '{}', 16, '{}');
  assert.equal(coordinator.deliveryEnvelopeJson(deliverable, delivery), delivery);
  assert.throws(() => coordinator.deliveryEnvelopeJson(request, delivery),
    {code: 'CoordinatorOwnerRejected'});
  assert.throws(() => coordinator.deliveryEnvelopeJson(deliverable, delivery + ' '),
    {code: 'CoordinatorOwnerRejected'});
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
  // The packed ACK issuer uses its own public Output record, restored from
  // admitted durable bytes. A protocol receipt fixture is not native I/O.
  const transfer = fixture.transferControl;
  let transferRecord = transfer.open(fixture.transferRequest);
  for (const transition of [
    () => transfer.prepareStart(transferRecord),
    () => transfer.prepareSourceSettled(transferRecord, true, false),
    () => transfer.prepareDestinationCommit(transferRecord),
  ]) transferRecord = transfer.commitTransition(transition(), true);
  const report = coordinator.prepareOutputResultJson(fixture.outputDurable,
    transfer.replyJson(transferRecord), cid('f'));
  const outputJournal = coordinator.createJournal('coordinator-a');
  coordinator.restoreDurable(outputJournal, fixture.durable);
  let outputRecord = coordinator.restoreDurableOutput(outputJournal, fixture.outputDurable);
  assert.throws(() => coordinator.outputReportAckJson(outputRecord, report),
    {code: 'CoordinatorOwnerRejected'});
  const refusal = JSON.parse(coordinator.outputReportRefusalJson(outputRecord,
    report, 'authorization_denied'));
  assert.equal(refusal.outcome, 'refused');
  assert.equal(refusal.reason, 'authorization_denied');
  assert.equal(refusal.report_cid, 'sha256:' + createHash('sha256').update(report).digest('hex'));
  assert.throws(() => coordinator.outputReportRefusalJson(outputRecord, report,
    'private_diagnostic'), {code: 'CoordinatorOwnerRejected'});
  assert.throws(() => coordinator.outputReportRefusalJson(outputRecord,
    report.replace(fixture.requestCid, dispatchCid(dispatch('foreign-report'))),
    'report_conflict'), {code: 'CoordinatorOwnerRejected'});
  const success = coordinator.prepareOutputSuccessJson(outputRecord, report);
  const savedOutput = coordinator.outputTransitionDurableJson(fixture.outputDurable, success);
  outputRecord = coordinator.commitOutputTransition(success);
  const reportFields = JSON.parse(report);
  const expectedAck = JSON.stringify({dispatch_request_cid: fixture.requestCid,
    intent_cid: reportFields.intent_cid, outcome: 'accepted', reason: '',
    report_cid: 'sha256:' + createHash('sha256').update(report).digest('hex'),
    version: 'actql-remote-output-report-reply/0.1'});
  assert.equal(coordinator.outputReportAckJson(outputRecord, report), expectedAck);
  const status = coordinator.outputRecordStatus(outputRecord);
  assert.equal(coordinator.outputReportAckJson(outputRecord, report), expectedAck);
  assert.deepEqual(coordinator.outputRecordStatus(outputRecord), status);
  assert.throws(() => coordinator.outputReportAckJson(outputRecord,
    report.replace(fixture.requestCid, dispatchCid(dispatch('foreign-report')))),
  {code: 'CoordinatorOwnerRejected'});
  const reopenedJournal = coordinator.createJournal('coordinator-a');
  coordinator.restoreDurable(reopenedJournal, fixture.durable);
  const reopened = coordinator.restoreDurableOutput(reopenedJournal,
    coordinator.admitDurableOutputJson(savedOutput, fixture.durable, cid('7'),
      {maxChunks: 4, maxManifestBytes: 4096, maxReferencedBytes: 12n}));
  assert.equal(coordinator.outputReportAckJson(reopened, report), expectedAck);
  assert.deepEqual(coordinator.outputRecordStatus(reopened), status);
  console.log('packed coordinator-core release, not-seen, output request, durable replay and exact ACK');
  `);
  process.stdout.write(run(process.execPath, ['smoke.mjs'], installation));
} finally {
  if (process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1') {
    console.error(`packed coordinator-core scratch kept: ${installation}`);
  } else {
    await rm(installation, {recursive: true, force: true});
  }
}
