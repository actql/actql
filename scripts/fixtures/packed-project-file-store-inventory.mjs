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
import {observeProjectFileStoreLedger, observeProjectFileStoreAttempts}
  from './project-file-store-ledger-observation.mjs';
import {observeRecordApprovalDescriptors} from './record-approval/scoped-fds.fixture.mjs';

const [phase, caseId, handoffPath] = process.argv.slice(2);
assert(['capture', 'saved'].includes(phase)); assert(['rows101', 'members17'].includes(caseId));
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
  for (const key of ['code', 'primaryCode', 'issueTag', 'nestedIssueTag', 'phase',
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
const targets = async expected => {
  assert.deepEqual((await readdir(destinationRoot)).sort(), expected.map(file => file.path).sort());
  return Promise.all(expected.map(async file => {
    const path = join(destinationRoot, file.path), bytes = await readFile(path);
    assert.deepEqual(bytes, Buffer.from(file.body));
    return {path: file.path, contentCid: digest(bytes), generation: await generation(path)};
  }));
};
const validateRows = (rows, original) => {
  assert.equal(rows.length, original.expectedProjection.length);
  // Listing metadata does not declare a path candidate key or a total order.
  // Compare all literal rows by path without adding an authored sort or
  // changing the actual full Result sequence retained for cold Saved.
  const compared = caseId === 'rows101'
    ? rows.toSorted((left, right) => left.path.localeCompare(right.path)) : rows;
  for (let index = 0; index < compared.length; index++) {
    const {content, ...fields} = compared[index];
    const expected = original.expectedProjection[index];
    assert.deepEqual(fields, caseId === 'members17'
      ? {...expected, media_type: 'application/x-ndjson'} : expected);
    const file = original.expectedFiles[caseId === 'members17' ? 0 : index];
    assert.equal(content.metadata.content_cid, digest(Buffer.from(file.body)));
  }
};
const inputsAbsent = async original => {
  await absent(programPath);
  for (const path of original.inputPaths) await absent(join(sourceRoot, path));
  assert.deepEqual(await readdir(sourceRoot), []);
};
let original, client, primary;
const cleanup = [];
try {
  if (phase === 'capture') {
    const selected = caseId === 'rows101' ? projectFileStoreRows101() : projectFileStoreMembers17();
    await mkdir(sourceRoot); await mkdir(destinationRoot);
    for (const input of selected.inputs) await writeFile(join(sourceRoot, input.path), input.body, {flag: 'wx'});
    await writeFile(programPath, selected.source, {flag: 'wx'});
    await writeFile(join(directory, 'actql.config.json'), JSON.stringify({version: 'actql-config/0.1',
      connectors: 'connectors.json'}), {flag: 'wx'});
    await writeFile(join(directory, 'connectors.json'), JSON.stringify({version: 'actql-connectors/0.1',
      connections: {source: {connector: 'local', root: './source-data', tables: {}},
        destination: {connector: 'local', root: './destination-data', tables: {}}}}), {flag: 'wx'});
    const keys = generateKeyPairSync('ed25519');
    original = {case: caseId, complete: false, resultName: selected.resultName,
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
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}]}};
    await save(handoffPath, original);
  } else {
    original = JSON.parse(await readFile(handoffPath, 'utf8'));
    assert.equal(original.complete, true); assert.equal(original.case, caseId);
    await inputsAbsent(original);
    assert.deepEqual(await targets(original.expectedFiles), original.targets);
    assert.deepEqual(await observeProjectFileStoreLedger(stateDir, original.expectedFiles), original.ledger);
    assert.deepEqual(observeProjectFileStoreAttempts(stateDir, original.ref), original.attempts);
  }
  const budget = projectFileStoreInventoryAcceptance.budgetBytes;
  report.requestMemory = {retainedBytes: budget, executionBytes: budget};
  client = await open({stateDir, installation: {authorization: {...original.authorization,
    observe(name, detail) {
      if (['dispatch_failed', 'effect_preflight_failed', 'effect_start_failed', 'local_compute_failed'].includes(name)
          && report.diagnostics.length < 8) report.diagnostics.push({name, detail: diagnosticData(detail)});
    }},
    requestMemory: report.requestMemory,
    resultDataPolicy: {kind: 'data_policy', wire: policyWire, cid: digest(policyWire)}}});
  let run;
  if (phase === 'capture') {
    report.submits++;
    run = await client.startSource(await readFile(programPath, 'utf8'), {format: original.format});
    original.ref = run.ref; await save(handoffPath, original);
    const waiting = await run.wait({signal: AbortSignal.timeout(15_000)});
    report.captureState = snapshot(waiting);
    assert.equal(waiting.status, 'waiting_checkpoint');
    assert.deepEqual(await readdir(destinationRoot), []);
    await observeProjectFileStoreLedger(stateDir, original.expectedFiles, {beforeApproval: true});
    report.zeroWritesBeforeApproval = true;
    const page = await client.checkpoints();
    const checkpoints = page.items.filter(item => item.kind === 'effect_set');
    assert.equal(checkpoints.length, 1);
    const checkpoint = checkpoints[0];
    const review = await client.reviewCheckpoint(checkpoint, {maxBytes: 1024 * 1024});
    // The public method verifies the review's self-excluding contract CID.
    // Its physical byte digest is a separate observation, not that identity.
    assert.equal(review.checkpointCid, checkpoint.checkpointCid);
    await writeFile(join(directory, 'checkpoint-review.json'), review.bytes, {flag: 'wx', mode: 0o600});
    report.review = {checkpointCid: review.checkpointCid, artifactCid: review.artifactCid,
      bytes: review.bytes.byteLength, physicalDigest: digest(review.bytes)};
    report.approvals++;
    const resolution = await client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {
      signer: {keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
        sign: bytes => sign(null, bytes, original.authorization.hostKey.privateKey)}});
    await save(join(directory, 'approval.json'), resolution);
    assert.equal(resolution.results.length, 1); assert.equal(resolution.results[0].status, 'committed');
    const signal = AbortSignal.timeout(15_000);
    let state;
    do {
      state = await run.status({signal});
      if (!['waiting_checkpoint', 'resuming', 'running'].includes(state.status)) break;
      await delay(20, undefined, {signal});
    } while (true);
    assert.equal(state.status, 'succeeded');
  } else {
    run = await client.attach(original.ref); assert.deepEqual(run.ref, original.ref);
    assert.equal((await run.status()).status, 'succeeded');
  }
  const rows = await run.result(original.resultName).all();
  validateRows(rows, original); report.rows = snapshot(rows);
  if (phase === 'capture') {original.rows = report.rows; await save(handoffPath, original);}
  else assert.deepEqual(report.rows, original.rows);
  report.ref = run.ref; report.resultName = original.resultName;
} catch (error) {
  primary = error; report.primary = {name: error?.name, code: error?.code, message: error?.message};
} finally {
  report.firstClose = client === undefined ? 'not-attempted' : 'pending';
  try {await save(join(dirname(handoffPath), `${caseId}-${phase}.pending.json`), report);}
  catch (error) {cleanup.push(error);}
  if (client !== undefined) try {
    report.firstCloseCalls++; await client.close(); report.firstClose = 'returned';
  } catch (error) {report.firstClose = 'threw'; cleanup.push(error);}
  if (report.firstClose === 'returned') try {
    const roots = [stateDir, sourceRoot, destinationRoot];
    const before = await observeRecordApprovalDescriptors(roots); await delay(100);
    const after = await observeRecordApprovalDescriptors(roots);
    report.aliveScopedFD = {before: before.openPaths.length, after: after.openPaths.length};
    assert.deepEqual(report.aliveScopedFD, {before: 0, after: 0});
  } catch (error) {cleanup.push(error);}
  if (primary === undefined && cleanup.length === 0) try {
    report.targets = await targets(original.expectedFiles);
    const ledger = await observeProjectFileStoreLedger(stateDir, original.expectedFiles);
    const attempts = observeProjectFileStoreAttempts(stateDir, original.ref);
    report.sourceAttempts = attempts.sources.length; report.modelAttempts = attempts.model.resume_model_attempts;
    if (caseId === 'rows101') assert(report.sourceAttempts > 0,
      'The physical File Source must have actual recorded original attempt evidence');
    assert.equal(ledger.successfulStores, original.expectedWrites);
    assert.equal(ledger.memberPreviews, original.expectedDefinitions);
    report.successfulStores = ledger.successfulStores; report.memberPreviews = ledger.memberPreviews;
    if (phase === 'capture') {
      original.targets = report.targets; original.ledger = ledger; original.attempts = attempts;
      for (const path of original.inputPaths) await unlink(join(sourceRoot, path));
      await unlink(programPath);
    } else {
      assert.deepEqual(report.targets, original.targets);
      assert.deepEqual(ledger, original.ledger, 'Saved adds no Effect dispatch, receipt or commit');
      assert.deepEqual(attempts, original.attempts, 'Saved adds no Source or Model attempt');
      report.newEffectCommits = 0;
    }
    await inputsAbsent(original); report.originalInputsAndProgramAbsent = true;
    if (phase === 'capture') await save(handoffPath, {...original, complete: true});
    report.complete = true;
  } catch (error) {cleanup.push(error);}
  report.cleanup = cleanup.map(error => ({name: error?.name, code: error?.code, message: error?.message}));
  try {await save(join(dirname(handoffPath), `${caseId}-${phase}.observation.json`), report);}
  catch (error) {cleanup.push(error);}
}
if (primary !== undefined || cleanup.length) throw new AggregateError(
  [...(primary === undefined ? [] : [primary]), ...cleanup], 'ProjectFileStoreInventoryFailed', {cause: primary});
console.log(JSON.stringify(report));
