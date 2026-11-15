// Three distinct public processes: persist the complete private Effect input,
// cold-approve that SAME capture, then read the SAME Saved without replay.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {access, mkdir, readFile, readdir, stat, unlink, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {userInfo} from 'node:os';
import {isDeepStrictEqual} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import {open} from '@actql/node';
import {projectFileDependencyBoundary} from './project-file-dependency-boundary-cases.mjs';
import {observeProjectEffectDependencies, dependencyBoundaryFailureData as diagnostic} from './project-effect-dependency-observation.mjs';
import {observeProjectFileStoreLedger, observeProjectFileStoreAttempts}
  from './project-file-store-ledger-observation.mjs';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';
import {workflowWorkObservation} from '../../adapters/host-node/fixtures/work-observation.fixture.mjs';

const [phase, caseId, handoffPath] = process.argv.slice(2);
assert(['capture', 'approve', 'saved'].includes(phase));
assert(['small', 'count'].includes(caseId));
assert.equal(typeof handoffPath, 'string');
// The small case has two groups with two actual RRF peers each. It exercises
// the same operator and exact-score demand as the large case, with two writes.
const selection = caseId === 'small' ? {ports: 4, groups: 2} : {ports: 2050, groups: 8};
const selected = projectFileDependencyBoundary(selection);
const directory = process.cwd(), stateDir = join(directory, 'state');
const sourceRoot = join(directory, 'source-data'), destinationRoot = join(directory, 'destination-data');
const programPath = join(directory, 'program.actql');
const observationPath = join(dirname(handoffPath), `${caseId}-${phase}.observation.json`);
const pendingPath = join(dirname(handoffPath), `${caseId}-${phase}.pending.json`);
const censusPath = join(dirname(handoffPath), `${caseId}-dependencies.capture.json`);
const digest = value => 'sha256:' + createHash('sha256').update(value).digest('hex');
const save = (path, value) => writeFile(path, JSON.stringify(value, null, 2) + '\n', {mode: 0o600});
const clone = value => JSON.parse(JSON.stringify(value));
const report = {case: caseId, phase, pid: process.pid, submits: 0, approvals: 0,
  firstClose: 'unobserved', firstCloseCalls: 0, complete: false,
  diagnostics: [],
  requestMemory: {retainedBytes: 1073741824, executionBytes: 1073741824}, sourceFreeMaxWork: 30000000};
const progress = async name => {
  report.activePhase = name;
  report.phaseStartedAt = new Date().toISOString();
  await save(pendingPath, report);
  if (name === 'startSource') process.emit('actql-dependency-start-source-diagnostic');
};
const absent = path => assert.rejects(access(path), {code: 'ENOENT'});
const inputsAbsent = async () => {
  await absent(programPath);
  for (const input of selected.inputs) await absent(join(sourceRoot, input.path));
  assert.deepEqual(await readdir(sourceRoot), []);
};
const targetObservation = async () => {
  assert.deepEqual((await readdir(destinationRoot)).sort(), selected.expectedFiles.map(file => file.path).sort());
  return Promise.all(selected.expectedFiles.map(async file => {
    const path = join(destinationRoot, file.path), bytes = await readFile(path);
    assert.deepEqual(bytes, Buffer.from(file.body));
    const metadata = await stat(path, {bigint: true});
    return {path: file.path, contentCid: digest(bytes), generation: Object.fromEntries(
      ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].map(key => [key, String(metadata[key])]))};
  }));
};
const assertCensus = async original => {
  const observed = await observeProjectEffectDependencies(stateDir, original.ref,
    report.requestMemory.retainedBytes);
  if (caseId !== 'small') assert(observed.summary.uniqueData > 4096);
  if (phase === 'capture') {
    await save(censusPath, observed.snapshot);
    original.dependencies = observed.summary;
  } else {
    assert(isDeepStrictEqual(observed.snapshot, JSON.parse(await readFile(censusPath, 'utf8'))),
      'Every original dependency kind/CID/canonical body and CID-valued reference must survive');
    assert.deepEqual(observed.summary, original.dependencies);
  }
  report.dependencies = observed.summary;
};
const work = workflowWorkObservation({trackOriginal: true});
let original, client, primary, attemptsBefore, ledgerBefore;
const cleanup = [];
try {
  if (phase === 'capture') {
    await mkdir(sourceRoot); await mkdir(destinationRoot);
    for (const input of selected.inputs) await writeFile(join(sourceRoot, input.path), input.body, {flag: 'wx'});
    await writeFile(programPath, selected.source, {flag: 'wx'});
    await writeFile(join(directory, 'actql.config.json'), JSON.stringify({version: 'actql-config/0.1',
      connectors: 'connectors.json'}), {flag: 'wx'});
    await writeFile(join(directory, 'connectors.json'), JSON.stringify({version: 'actql-connectors/0.1',
      connections: {source: {connector: 'local', root: './source-data', tables: {}},
        destination: {connector: 'local', root: './destination-data', tables: {}}}}), {flag: 'wx'});
    const keys = generateKeyPairSync('ed25519');
    original = {case: caseId, captureComplete: false, approveComplete: false,
      authorization: {accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
        account_id: 'project-dependency-boundary', entries: [
          {entry_id: 'effect-review', outcome: 'delegate', principal: {all: true}, connection: {all: true},
            resource: {all: true}, operation: {any_of: ['effect']}, exclusions: []},
          {entry_id: 'read-write', outcome: 'allow', principal: {all: true}, connection: {all: true},
            resource: {all: true}, operation: {any_of: ['read', 'write']}, exclusions: []},
        ]}), hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}], reviewReaders: [userInfo().username]}};
    await save(handoffPath, original);
  } else {
    original = JSON.parse(await readFile(handoffPath, 'utf8'));
    assert.equal(original.case, caseId); assert.equal(original.captureComplete, true);
    assert.notEqual(process.pid, original.capturePid);
    assert.equal(original.approveComplete, phase === 'saved');
    if (phase === 'saved') assert.notEqual(process.pid, original.approvePid);
    await inputsAbsent();
    await assertCensus(original);
    attemptsBefore = observeProjectFileStoreAttempts(stateDir, original.ref);
    assert.deepEqual(attemptsBefore, original.attempts);
    ledgerBefore = await observeProjectFileStoreLedger(stateDir, selected.expectedFiles,
      {beforeApproval: phase === 'approve'});
    if (phase === 'saved') {
      assert.deepEqual(ledgerBefore, original.ledger);
      assert.deepEqual(await targetObservation(), original.targets);
    } else assert.deepEqual(await readdir(destinationRoot), []);
  }
  await progress('open');
  const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
  client = await open({stateDir, installation: {observation: work.connection,
    authorization: {...original.authorization, observe(name, detail) {
      if (report.diagnostics.length < 32) report.diagnostics.push({name, detail: diagnostic(detail)});
    }}, requestMemory: report.requestMemory,
    sourceFreeMaxWork: report.sourceFreeMaxWork,
    resultDataPolicy: {kind: 'data_policy', wire: policyWire, cid: digest(policyWire)}}});
  let run;
  if (phase === 'capture') {
    report.submits++;
    await progress('startSource');
    run = await client.startSource(await readFile(programPath, 'utf8'),
      {format: selected.format, signal: AbortSignal.timeout(120000)});
    original.ref = run.ref; await save(handoffPath, original);
    await progress('waitCheckpoint');
    const state = await run.wait({signal: AbortSignal.timeout(120000)});
    report.state = clone(state);
    assert.equal(state.status, 'waiting_checkpoint');
    const checkpoints = (await client.checkpoints()).items.filter(item => item.kind === 'effect_set');
    assert.equal(checkpoints.length, 1);
    original.checkpoint = clone(checkpoints[0]); original.checkpointId = state.checkpoint.id;
    original.runId = state.run_id;
    const review = await client.reviewCheckpoint(original.checkpoint, {maxBytes: 1024 * 1024});
    original.reviewBase64 = Buffer.from(review.bytes).toString('base64');
    assert.deepEqual(await readdir(destinationRoot), []);
    await observeProjectFileStoreLedger(stateDir, selected.expectedFiles, {beforeApproval: true});
    report.zeroWritesBeforeApproval = true;
    await assertCensus(original);
  } else {
    await progress('attach');
    run = await client.attach(original.ref); assert.deepEqual(run.ref, original.ref);
    let state = await run.status(); assert.equal(state.run_id, original.runId);
    if (phase === 'approve') {
      assert.equal(state.status, 'waiting_checkpoint'); assert.equal(state.checkpoint.id, original.checkpointId);
      const review = await client.reviewCheckpoint(original.checkpoint, {maxBytes: 1024 * 1024});
      assert.equal(Buffer.from(review.bytes).toString('base64'), original.reviewBase64);
      await progress('approve'); report.approvals++;
      const resolution = await client.resolveCheckpoints([{checkpoint: original.checkpoint, decision: 'approved'}], {
        signer: {keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
          sign: bytes => sign(null, bytes, original.authorization.hostKey.privateKey)}});
      assert.equal(resolution.results.length, 1); assert.equal(resolution.results[0].status, 'committed');
      const signal = AbortSignal.timeout(120000);
      do {
        state = await run.status({signal});
        if (!['waiting_checkpoint', 'resuming', 'running'].includes(state.status)) break;
        await delay(20, undefined, {signal});
      } while (true);
    }
    assert.equal(state.status, 'succeeded');
    await progress('allResults');
    report.results = {};
    for (const name of Object.keys(selected.program.results)) {
      const rows = await run.result(name).all();
      const expected = name === 'producer' ? selected.expectedProducer : name === 'serialized'
        ? selected.expectedSerialized : name.startsWith('group')
        ? [selected.expectedRows[Number(name.slice('group'.length))]] : selected.expectedRows;
      assert.equal(rows.length, expected.length);
      for (let index = 0; index < rows.length; index++) {
        const {content, ...metadata} = rows[index];
        assert.deepEqual(metadata, expected[index]);
        if (name !== 'producer') assert.equal(content.metadata.content_cid, digest(selected.expectedFiles[0].body));
      }
      report.results[name] = clone(rows);
    }
    if (phase === 'approve') original.results = report.results;
    else assert.deepEqual(report.results, original.results);
    await assertCensus(original);
  }
} catch (error) {
  primary = error;
  report.primary = {name: error?.name, code: error?.code, message: error?.message,
    ...(typeof error?.stack === 'string' ? {stack: error.stack.slice(0, 4096)} : {})};
} finally {
  report.ref = original?.ref;
  report.workObservation = original?.ref ? work.forOriginal(original.ref) : work.snapshot();
  report.firstClose = client ? 'pending' : 'not-attempted';
  try {await progress('firstClose');} catch (error) {cleanup.push(error);}
  if (client) try {
    report.firstCloseCalls++; await client.close(); report.firstClose = 'returned';
  } catch (error) {report.firstClose = 'threw'; cleanup.push(error);}
  if (report.firstClose === 'returned') try {
    const roots = [stateDir, sourceRoot, destinationRoot];
    const before = await observeRecordApprovalDescriptors(roots); await delay(100);
    const after = await observeRecordApprovalDescriptors(roots);
    report.aliveScopedFD = {before: before.openPaths.length, after: after.openPaths.length};
    assert.deepEqual(report.aliveScopedFD, {before: 0, after: 0});
  } catch (error) {cleanup.push(error);}
  if (!primary && cleanup.length === 0) try {
    report.workObservation = work.forOriginal(original.ref);
    assert.equal(report.workObservation.complete, true);
    assert.equal(report.workObservation.modelCallStarts, 0);
    assert.equal(report.workObservation.totals.modelCallStarts, 0);
    assert.equal(report.workObservation.sourceAcquisitionStarts, phase === 'capture' ? 1 : 0);
    assert.equal(report.workObservation.totals.sourceAcquisitionStarts,
      report.workObservation.sourceAcquisitionStarts);
    const attempts = observeProjectFileStoreAttempts(stateDir, original.ref);
    if (phase !== 'capture') assert.deepEqual(attempts, attemptsBefore);
    const ledger = await observeProjectFileStoreLedger(stateDir, selected.expectedFiles,
      {beforeApproval: phase === 'capture'});
    assert.equal(ledger.successfulStores - (ledgerBefore?.successfulStores ?? 0),
      phase === 'approve' ? selected.expectedWrites : 0);
    await assertCensus(original);
    if (phase === 'capture') {
      assert.deepEqual(await readdir(destinationRoot), []);
      original.capturePid = process.pid; original.attempts = attempts;
      for (const input of selected.inputs) await unlink(join(sourceRoot, input.path));
      await unlink(programPath); original.captureComplete = true;
    } else {
      assert.equal(ledger.successfulStores, selected.expectedWrites); assert.equal(ledger.memberPreviews, 1);
      report.targets = await targetObservation();
      if (phase === 'approve') {
        original.targets = report.targets; original.ledger = ledger;
        original.approvePid = process.pid; original.approveComplete = true;
      } else {assert.deepEqual(report.targets, original.targets); assert.deepEqual(ledger, ledgerBefore);}
    }
    await inputsAbsent(); report.originalInputsAndProgramAbsent = true;
    await save(handoffPath, original); report.complete = true;
  } catch (error) {cleanup.push(error);}
  report.cleanup = cleanup.map(error => ({name: error?.name, code: error?.code, message: error?.message}));
  try {await save(observationPath, report);} catch (error) {cleanup.push(error);}
}
if (primary || cleanup.length) throw Object.assign(new Error('ProjectEffectDependencyBoundaryFailed'),
  {code: 'ProjectEffectDependencyBoundaryFailed', primaryCode: primary?.code,
    cleanupCodes: cleanup.map(error => error?.code ?? error?.name)});
console.log(JSON.stringify(report));
