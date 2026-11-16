// Public packed Node capture/approval and cold SAME-Saved consumer. The only
// non-public observation is a read-only test oracle over this new app's Ledger.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {access, mkdir, readFile, readdir, stat, unlink, writeFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import {userInfo} from 'node:os';
import {types as nodeTypes} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import {open} from '@actql/node';
import {projectFileStoreRows101, projectFileStoreMembers17,
  projectFileStoreInventoryAcceptance} from './project-file-store-inventory-cases.mjs';
import {observeProjectFileStoreLedger, observeProjectFileStoreAttempts,
  observeProjectFileStoreSourceAcquisitions}
  from './project-file-store-ledger-observation.mjs';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';
import {workflowWorkObservation} from '../../adapters/host-node/fixtures/work-observation.fixture.mjs';
import {projectFileStoreProgressObservation} from './project-file-store-progress-observation.mjs';

const [phase, caseId, handoffPath] = process.argv.slice(2);
assert(['capture', 'approve', 'saved'].includes(phase)); assert(['rows101', 'members17'].includes(caseId));
assert.equal(typeof handoffPath, 'string');
const directory = process.cwd(), stateDir = join(directory, 'state');
const sourceRoot = join(directory, 'source-data'), destinationRoot = join(directory, 'destination-data');
const programPath = join(directory, 'program.actql');
const report = {case: caseId, phase, pid: process.pid, submits: 0, approvals: 0,
  firstClose: 'unobserved', firstCloseCalls: 0, complete: false, diagnostics: []};
const save = (path, body) => writeFile(path, JSON.stringify(body, null, 2) + '\n', {mode: 0o600});
const digest = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const snapshot = value => JSON.parse(JSON.stringify(value));
const diagnosticData = (value, depth = 12, budget = {nodes: 128}) => {
  if (budget.nodes-- <= 0) return undefined;
  if (typeof value === 'string') return value.slice(0, 2048);
  if (value == null || typeof value === 'number' || typeof value === 'boolean') return value;
  if (depth === 0 || typeof value !== 'object') return undefined;
  const result = {};
  if (nodeTypes.isNativeError(value) && typeof value.stack === 'string') result.stack = value.stack.slice(0, 4096);
  for (const key of ['name', 'code', 'primaryCode', 'issueTag', 'nestedIssueTag', 'phase',
    'kind', 'message', 'primaryDiagnostic', 'cause', '$tag', '_0', '_1']) {
    let property;
    for (let original = value, count = 0; original && count < 3; count++, original = Object.getPrototypeOf(original)) {
      property = Object.getOwnPropertyDescriptor(original, key);
      if (property) break;
    }
    if (property && Object.hasOwn(property, 'value')) result[key] = diagnosticData(property.value, depth - 1, budget);
  }
  return result;
};
const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
const absent = async path => assert.rejects(access(path), {code: 'ENOENT'});
const generation = async path => {
  const value = await stat(path, {bigint: true});
  return Object.fromEntries(['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].map(key => [key, String(value[key])]));
};
export async function assertProjectFileStoreTargets(expected, destinationRoot) {
  assert.deepEqual((await readdir(destinationRoot)).sort(), expected.map(file => file.path).sort());
  return Promise.all(expected.map(async file => {
    const path = join(destinationRoot, file.path), bytes = await readFile(path);
    assert.deepEqual(bytes, Buffer.from(file.body));
    return {path: file.path, contentCid: digest(bytes), generation: await generation(path)};
  }));
}
export function assertProjectFileStoreRows(rows, original, caseId) {
  assert.equal(rows.length, original.expectedProjection.length);
  // Listing metadata does not declare a path candidate key or a total order.
  // Compare all literal rows by path without adding an authored sort or
  // changing the actual full Result sequence retained for cold Saved.
  const compared = caseId === 'rows101'
    ? rows.toSorted((left, right) => left.path.localeCompare(right.path)) : rows;
  const filesByPath = new Map(original.expectedFiles.map(file => [file.path, file]));
  for (let index = 0; index < compared.length; index++) {
    const {content, ...fields} = compared[index];
    const expected = original.expectedProjection[index];
    assert.deepEqual(fields, caseId === 'members17'
      ? {...expected, media_type: 'application/x-ndjson'} : expected);
    const file = caseId === 'members17' ? original.expectedFiles[0] : filesByPath.get(fields.path);
    assert(file, 'Every completed Result key has its independent authored destination');
    assert.equal(content.metadata.content_cid, digest(Buffer.from(file.body)));
  }
}
const targets = expected => assertProjectFileStoreTargets(expected, destinationRoot);
const inputsAbsent = async original => {
  await absent(programPath);
  for (const path of original.inputPaths) await absent(join(sourceRoot, path));
  assert.deepEqual(await readdir(sourceRoot), []);
};
const selected = caseId === 'rows101' ? projectFileStoreRows101() : projectFileStoreMembers17();
const timing = projectFileStoreProgressObservation({stateDir, destinationRoot,
  expectedFiles: selected.expectedFiles, instrumented: process.env.ACTQL_TEST_FILE_PROGRESS === '1'});
report.phaseTiming = timing.data;
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
    original = {case: caseId, captureComplete: false, approveComplete: false, resultName: selected.resultName,
      expectedFiles: selected.expectedFiles, expectedProjection: selected.expectedProjection,
      expectedWrites: selected.expectedWrites, expectedDefinitions: selected.expectedDefinitions,
      inputPaths: selected.inputs.map(input => input.path), format: selected.format,
      authorization: {accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
        account_id: 'project-file-store-inventory', entries: [
          {entry_id: 'effect-review', outcome: 'delegate', principal: {all: true},
            connection: {all: true}, resource: {all: true}, operation: {any_of: ['effect']}, exclusions: []},
          {entry_id: 'read-write', outcome: 'allow', principal: {all: true},
            connection: {all: true}, resource: {all: true}, operation: {any_of: ['read', 'write']}, exclusions: []},
        ]}), hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
        reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
        reviewReaders: [userInfo().username]}};
    await save(handoffPath, original);
  } else {
    original = JSON.parse(await readFile(handoffPath, 'utf8'));
    assert.equal(original.case, caseId); assert.equal(original.captureComplete, true);
    assert.notEqual(process.pid, original.capturePid, 'Approval and Saved require a cold process');
    if (phase === 'saved') {
      assert.equal(original.approveComplete, true);
      assert.notEqual(process.pid, original.approvePid, 'Saved requires a third process');
    } else assert.equal(original.approveComplete, false, 'Approve the original Checkpoint only once');
    await inputsAbsent(original);
    if (phase === 'approve') {
      assert.deepEqual(await readdir(destinationRoot), []);
      ledgerBefore = await observeProjectFileStoreLedger(stateDir, selected.expectedFiles, {beforeApproval: true});
    } else {
      assert.deepEqual(await targets(selected.expectedFiles), original.targets);
      ledgerBefore = await observeProjectFileStoreLedger(stateDir, selected.expectedFiles);
      assert.deepEqual(ledgerBefore, original.ledger);
    }
    attemptsBefore = observeProjectFileStoreAttempts(stateDir, original.ref);
    assert.deepEqual(attemptsBefore, original.attempts);
  }
  // Each process reloads authored expectations, independently of the handoff or
  // any produced Result, file, receipt or previous observation.
  assert.deepEqual(original.expectedFiles, selected.expectedFiles);
  assert.deepEqual(original.expectedProjection, selected.expectedProjection);
  const budget = projectFileStoreInventoryAcceptance.budgetBytes;
  report.requestMemory = {retainedBytes: budget, executionBytes: budget};
  timing.stamp('open-begin');
  client = await open({stateDir, installation: {observation: work.connection, authorization: {...original.authorization,
    observe(name, detail) {
      if (['dispatch_failed', 'effect_preflight_failed', 'effect_start_failed', 'local_compute_failed'].includes(name)
          && report.diagnostics.length < 8) report.diagnostics.push({name, detail: diagnosticData(detail)});
    }},
    requestMemory: report.requestMemory,
    resultDataPolicy: {kind: 'data_policy', wire: policyWire, cid: digest(policyWire)}}});
  timing.stamp('open-end');
  let run;
  if (phase === 'capture') {
    report.submits++;
    run = await client.startSource(await readFile(programPath, 'utf8'), {format: original.format});
    original.ref = run.ref; await save(handoffPath, original);
    // Functional completion bound for acquisition plus Compute, not a latency
    // assertion. Cold approval and Saved keep their separate existing bounds.
    const waiting = await run.wait({signal: AbortSignal.timeout(45_000)});
    timing.stamp('terminal-or-abort');
    report.captureState = snapshot(waiting);
    assert.equal(waiting.status, 'waiting_checkpoint');
    assert.deepEqual(await readdir(destinationRoot), []);
    await observeProjectFileStoreLedger(stateDir, original.expectedFiles, {beforeApproval: true});
    report.zeroWritesBeforeApproval = true;
    const page = await client.checkpoints();
    const checkpoints = page.items.filter(item => item.kind === 'effect_set');
    assert.equal(checkpoints.length, 1);
    const checkpoint = checkpoints[0];
    timing.stamp('review-begin');
    const review = await client.reviewCheckpoint(checkpoint, {maxBytes: 1024 * 1024});
    timing.stamp('review-end');
    // The public method verifies the review's self-excluding contract CID.
    // Its physical byte digest is a separate observation, not that identity.
    assert.equal(review.checkpointCid, checkpoint.checkpointCid);
    await writeFile(join(directory, 'checkpoint-review.json'), review.bytes, {flag: 'wx', mode: 0o600});
    report.review = {checkpointCid: review.checkpointCid, artifactCid: review.artifactCid,
      bytes: review.bytes.byteLength, physicalDigest: digest(review.bytes)};
    original.checkpoint = snapshot(checkpoint); original.checkpointId = waiting.checkpoint.id;
    original.runId = waiting.run_id; original.reviewBase64 = Buffer.from(review.bytes).toString('base64');
    await save(handoffPath, original);
  } else {
    timing.stamp('attach-begin');
    run = await client.attach(original.ref); assert.deepEqual(run.ref, original.ref);
    timing.stamp('attach-end');
    const state = await run.status();
    assert.equal(state.run_id, original.runId);
    if (phase === 'approve') {
      assert.equal(state.status, 'waiting_checkpoint');
      assert.equal(state.checkpoint.id, original.checkpointId);
      timing.stamp('review-begin');
      const review = await client.reviewCheckpoint(original.checkpoint, {maxBytes: 1024 * 1024});
      timing.stamp('review-end');
      assert.equal(Buffer.from(review.bytes).toString('base64'), original.reviewBase64,
        'The cold process must recover the identical sealed original review');
      assert.deepEqual(await readdir(destinationRoot), []);
      await observeProjectFileStoreLedger(stateDir, selected.expectedFiles, {beforeApproval: true});
      report.zeroWritesBeforeApproval = true;
      report.approvals++;
      timing.stamp('resolve-begin');
      const resolution = await client.resolveCheckpoints([{checkpoint: original.checkpoint, decision: 'approved'}], {
        signer: {keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
          sign: bytes => sign(null, bytes, original.authorization.hostKey.privateKey)}});
      timing.stamp('resolve-end');
      await save(join(directory, 'approval.json'), resolution);
      assert.equal(resolution.results.length, 1); assert.equal(resolution.results[0].status, 'committed');
      timing.stamp('window-start');
      const signal = AbortSignal.timeout(15_000);
      let resumedState;
      do {
        resumedState = await run.status({signal});
        if (timing.instrumented) timing.poll();
        if (!['waiting_checkpoint', 'resuming', 'running'].includes(resumedState.status)) break;
        await delay(20, undefined, {signal});
      } while (true);
      timing.stamp('terminal-or-abort');
      assert.equal(resumedState.status, 'succeeded'); assert.equal(resumedState.run_id, original.runId);
    } else {timing.stamp('terminal-or-abort'); assert.equal(state.status, 'succeeded');}
  }
  if (phase !== 'capture') {
    const rows = await run.result(original.resultName).all();
    assertProjectFileStoreRows(rows, selected, caseId); report.rows = snapshot(rows);
    if (phase === 'approve') original.rows = report.rows;
    else assert.deepEqual(report.rows, original.rows);
  }
  report.ref = run.ref; report.resultName = original.resultName;
  report.runId = original.runId; report.checkpointId = original.checkpointId;
  report.checkpointCid = original.checkpoint.checkpointCid;
} catch (error) {
  primary = error; report.primary = diagnosticData(error);
  timing.stamp('terminal-or-abort');
  await timing.failure();
} finally {
  report.ref ??= original?.ref; report.workObservation = original?.ref ? work.forOriginal(original.ref) : work.snapshot();
  report.firstClose = client === undefined ? 'not-attempted' : 'pending';
  timing.stamp('close-pending');
  try {await save(join(dirname(handoffPath), `${caseId}-${phase}.pending.json`), report);}
  catch (error) {cleanup.push(error);}
  if (client !== undefined) try {
    timing.stamp('close-begin');
    report.firstCloseCalls++; await client.close(); report.firstClose = 'returned';
  } catch (error) {report.firstClose = 'threw'; cleanup.push(error);}
  finally {timing.stamp('close-end');}
  if (report.firstClose === 'returned') try {
    const roots = [stateDir, sourceRoot, destinationRoot];
    const before = await observeRecordApprovalDescriptors(roots); await delay(100);
    const after = await observeRecordApprovalDescriptors(roots);
    report.aliveScopedFD = {before: before.openPaths.length, after: after.openPaths.length};
    assert.deepEqual(report.aliveScopedFD, {before: 0, after: 0});
  } catch (error) {cleanup.push(error);}
  if (primary === undefined && cleanup.length === 0) try {
    report.workObservation = work.forOriginal(original.ref);
    assert.equal(report.workObservation.complete, true);
    assert.equal(report.workObservation.modelCallStarts, 0);
    assert.equal(report.workObservation.totals.modelCallStarts, 0);
    report.sourceStarts = report.workObservation.sourceAcquisitionStarts;
    assert.equal(report.workObservation.totals.sourceAcquisitionStarts, report.sourceStarts);
    if (phase === 'capture' && caseId === 'rows101') assert.equal(report.sourceStarts, 1);
    else assert.equal(report.sourceStarts, 0, 'Cold approval and Saved never reacquire completed Sources');
    const attempts = observeProjectFileStoreAttempts(stateDir, original.ref);
    // The optional request-Journal table records remote job originals. Local
    // File lookup attempts live in the authenticated captured dependency DAG.
    report.sourceOperationOriginals = attempts.sources.length;
    report.sourceAttempts = 0; report.newSourceAttempts = 0;
    report.modelAttempts = attempts.model.resume_model_attempts;
    if (phase !== 'capture') {
      assert.deepEqual(attempts, attemptsBefore, 'Cold phases preserve the SAME original acquisitions');
    }
    if (caseId === 'rows101') {
      const source = await observeProjectFileStoreSourceAcquisitions(stateDir, original.ref,
        projectFileStoreInventoryAcceptance.budgetBytes);
      assert.equal(source.summary.receipts, 1);
      assert.equal(source.summary.attempts, selected.inputs.length);
      report.sourceAcquisitionEvidence = source.summary;
      report.sourceAttempts = source.summary.attempts;
      report.newSourceAttempts = report.sourceAttempts -
        (phase === 'capture' ? 0 : original.sourceAcquisitionSummary.attempts);
      if (phase === 'capture') {
        original.sourceAcquisitionSummary = source.summary;
        original.sourceAcquisitionSnapshot = source.snapshot;
      } else {
        assert.deepEqual(source.summary, original.sourceAcquisitionSummary);
        assert.deepEqual(source.snapshot, original.sourceAcquisitionSnapshot,
          'Cold phases retain every original Source body and reference unchanged');
        assert.equal(report.newSourceAttempts, 0);
      }
    }
    const ledger = await observeProjectFileStoreLedger(stateDir, selected.expectedFiles,
      {beforeApproval: phase === 'capture'});
    report.successfulStores = ledger.successfulStores;
    report.memberPreviews = ledger.memberPreviews ?? 0;
    report.newEffectCommits = ledger.successfulStores - (ledgerBefore?.successfulStores ?? 0);
    assert.equal(report.newEffectCommits, phase === 'approve' ? selected.expectedWrites : 0);
    if (phase === 'capture') {
      assert.deepEqual(await readdir(destinationRoot), []);
      report.targets = []; report.rows = [];
      original.attempts = attempts; original.capturePid = process.pid;
      for (const path of original.inputPaths) await unlink(join(sourceRoot, path));
      await unlink(programPath);
      original.captureComplete = true;
    } else {
      assert.equal(ledger.successfulStores, selected.expectedWrites);
      assert.equal(ledger.memberPreviews, selected.expectedDefinitions);
      report.targets = await targets(selected.expectedFiles);
      if (phase === 'approve') {
        original.targets = report.targets; original.ledger = ledger;
        original.approvePid = process.pid; original.approveComplete = true;
      } else {
        assert.deepEqual(report.targets, original.targets);
        assert.deepEqual(ledger, ledgerBefore, 'Saved adds no dispatch, receipt or commit');
      }
    }
    await inputsAbsent(original); report.originalInputsAndProgramAbsent = true;
    await save(handoffPath, original);
    report.complete = true;
  } catch (error) {cleanup.push(error);}
  report.cleanup = cleanup.map(error => ({name: error?.name, code: error?.code, message: error?.message}));
  try {await save(join(dirname(handoffPath), `${caseId}-${phase}.observation.json`), report);}
  catch (error) {cleanup.push(error);}
}
if (primary !== undefined || cleanup.length) throw new AggregateError(
  [...(primary === undefined ? [] : [primary]), ...cleanup], 'ProjectFileStoreInventoryFailed', {cause: primary});
console.log(JSON.stringify(report));
