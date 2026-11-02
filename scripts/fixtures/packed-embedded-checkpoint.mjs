// Synthetic historical-format originals exercise current packed public recovery.
// This is not historical public-producer or cross-version acceptance evidence.
import assert from 'node:assert/strict';
import {sign, createPrivateKey} from 'node:crypto';
import {appendFileSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {connect} from '@actql/node';
import {getSubmissionOutcome} from '@actql/sdk';
import {writeSyntheticHistoricalHeldValues, syntheticHeldSnapshot, heldValuesExpected}
  from './synthetic-historical-held-values.mjs';

const step = process.argv[2];
const requestId = 'packed-embedded-values';
const authorization = JSON.parse(readFileSync('authorization.json', 'utf8'));
authorization.resumeAfterAnswer = step === 'resume' || step === 'recheck';
authorization.faultInjection = name => appendFileSync('embedded-events.log', `${name}\n`);
const directory = join(process.cwd(), step === 'unsupported' ? 'epoch-state' : 'state');
const open = () => connect({mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory, authorization}});
let client = await open();
const document = readFileSync('values.json', 'utf8');
const pause = () => new Promise(resolve => setTimeout(resolve, 25));
let original;
try {
  if (step === 'hold') {
    // Open alone retains lazy services. This existing public read activates
    // the same empty Checkpoint owner without submitting or approving a Run.
    assert.deepEqual((await client.checkpoints({limit: 1})).items, []);
    await client.close();
    original = await writeSyntheticHistoricalHeldValues({directory, document, requestId, authorization,
      runtimeRootUrl: new URL('.', import.meta.resolve('@actql/local-node')),
      expressionContractUrl: new URL('actql-expressions.json', import.meta.url)});
    writeFileSync('original.json', JSON.stringify(original), {flag: 'wx', mode: 0o600});
    client = await open();
  } else if (step !== 'unsupported') original = JSON.parse(readFileSync('original.json', 'utf8'));
  if (original) {
    assert.equal(original.kind, 'synthetic_historical_format');
    assert.equal(original.requestId, requestId);
  }
  if (step === 'hold') {
    const lookup = await client.lookupRequest(requestId);
    assert.equal(lookup.kind, 'held');
    assert.equal(lookup.state, 'waiting_checkpoint');
    assert.equal(lookup.prepareAttemptId, original.prepareAttemptId);
    assert.equal(lookup.checkpoint.checkpointCid, original.checkpointCid);
    assert.equal(Object.hasOwn(lookup, 'ref'), false);
    const snapshot = await syntheticHeldSnapshot(directory, original);
    assert.deepEqual({runs: snapshot.runs, accepted: snapshot.accepted, intents: snapshot.intents},
      {runs: [], accepted: [], intents: 0});
    console.log('held');
  } else if (step === 'approve') {
    const lookup = await client.lookupRequest(requestId);
    assert.equal(lookup.kind, 'held');
    assert.equal(lookup.state, 'waiting_checkpoint');
    assert.equal(lookup.checkpoint.checkpointCid, original.checkpointCid);
    const {items} = await client.checkpoints();
    const checkpoint = items.find(item => item.checkpointCid === original.checkpointCid);
    assert.ok(checkpoint);
    writeFileSync('checkpoint.json', JSON.stringify(checkpoint));
    const review = await client.reviewCheckpoint(checkpoint);
    assert.equal(new TextDecoder().decode(review.bytes), original.reviewWire);
    const key = createPrivateKey(readFileSync('reviewer.key', 'utf8'));
    const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer', sign: bytes => sign(null, bytes, key)};
    const answered = await client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {signer});
    assert.deepEqual(answered.results.map(item => item.status), ['committed']);
    assert.deepEqual((await client.resolveCheckpoints(answered.signed)).results.map(item => item.status), ['duplicate']);
    assert.equal((await client.lookupRequest(requestId)).state, 'resuming');
    const snapshot = await syntheticHeldSnapshot(directory, original);
    assert.deepEqual({runs: snapshot.runs, accepted: snapshot.accepted}, {runs: [], accepted: []});
    console.log('approved');
  } else if (step === 'resume' || step === 'recheck') {
    let lookup;
    for (let attempt = 0; attempt < 400; attempt++) {
      lookup = await client.lookupRequest(requestId);
      if (lookup.kind === 'found') break;
      await pause();
    }
    assert.equal(lookup.kind, 'found', JSON.stringify(lookup));
    assert.equal(lookup.ref.namespaceId, 'local');
    assert.equal(lookup.ref.authorityScopeCid, original.authorityScopeCid);
    const execution = await client.attach(lookup.ref);
    let state;
    for (let attempt = 0; attempt < 400; attempt++) {
      state = await execution.wait();
      if (state.status === 'succeeded') break;
      await pause();
    }
    assert.equal(state.status, 'succeeded');
    assert.equal((await execution.status()).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(), heldValuesExpected);
    const cancellation = await execution.cancel();
    assert.equal(cancellation.kind, 'already_satisfied');
    assert.equal(cancellation.cancellation.kind, 'already_terminal');
    assert.equal((await client.cancelRequest(requestId)).kind, 'already_terminal');
    let snapshot;
    for (let attempt = 0; attempt < 400; attempt++) {
      snapshot = await syntheticHeldSnapshot(directory, original);
      if (Object.entries(snapshot.holdings).every(([name, status]) =>
        status === (name === 'invocation_request' ? 'held' : 'retired')) &&
        Object.entries(snapshot.physicalHoldings).every(([name, present]) => present ===
          (name === 'invocation_request')) && snapshot.pendingPhysicalDeletions === 0) break;
      await pause();
    }
    assert.equal(snapshot.runs.length, 1);
    assert.equal(snapshot.accepted.length, 1);
    assert.equal(snapshot.intents, 0);
    assert.deepEqual(snapshot.accepted[0], {caller_request_id: requestId,
      logical_request_scope_cid: original.logicalRequestScopeCid,
      intent_fingerprint_cid: original.intentFingerprintCid,
      program_definition_cid: original.programDefinitionCid,
      parameter_values_cid: original.parameterValuesCid,
      caller_input_intent_cid: original.callerInputIntentCid,
      run_definition_cid: lookup.ref.runDefinitionCid, physical_start_reserved: 1});
    assert.deepEqual(snapshot.holdings, {captured_input: 'retired', invocation_request: 'held',
      prepared_invocation: 'retired', review_projection: 'retired', continuation_record: 'retired'});
    assert.deepEqual(snapshot.physicalHoldings, {captured_input: false, invocation_request: true,
      prepared_invocation: false, review_projection: false, continuation_record: false});
    assert.equal(snapshot.pendingPhysicalDeletions, 0);
    if (step === 'resume') writeFileSync('recovered-run.json', JSON.stringify({ref: lookup.ref, runId: state.run_id}));
    else assert.deepEqual(JSON.parse(readFileSync('recovered-run.json', 'utf8')), {ref: lookup.ref, runId: state.run_id});
    console.log('published');
  } else if (step === 'unsupported') {
    const submissionRef = client.newSubmission({nonce: 'packed-new-epoch-values'});
    let outcome;
    await assert.rejects(client.startSource(document, {format: 'json', submissionRef}), error => {
      assert.equal(error.code, 'SubmissionPreparationFailed');
      outcome = getSubmissionOutcome(error);
      assert.equal(outcome.kind, 'preparation_failed');
      assert.equal(outcome.problem.code, 'ACTQL_E_DELEGATION_UNAVAILABLE');
      assert.deepEqual(outcome.submissionRef, submissionRef);
      return true;
    });
    const database = new DatabaseSync(join(directory, 'checkpoints/journal/checkpoint-journal.sqlite3'), {readOnly: true});
    const requests = new DatabaseSync(join(directory, 'requests/client-requests.sqlite3'), {readOnly: true});
    try {
      for (const table of ['preparations', 'checkpoints', 'runs']) {
        assert.equal(database.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 0);
      }
      assert.equal(requests.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
      assert.deepEqual(requests.prepare('SELECT phase FROM client_submitted_intents').all().map(row => row.phase), ['preparation_failed']);
    } finally {database.close(); requests.close();}
    assert.deepEqual((await client.checkpoints()).items, []);
    await client.close(); client = await open();
    assert.deepEqual(await client.lookupSubmission(submissionRef), outcome);
    console.log('unsupported');
  } else assert.fail(`Unknown packed step: ${step}`);
} finally {await client.close();}
