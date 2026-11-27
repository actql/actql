import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {test} from 'node:test';
import {canonicalText} from './check-canonical-json.mjs';
import {inspectNativeModelCustody, withMissingNativeModelFixtureCell} from './fixtures/native-model-custody-observation.mjs';

const knownCid = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const recordTable = 'CREATE TABLE actql_records (namespace TEXT, record_key TEXT, revision INTEGER, body BLOB,' +
  ' PRIMARY KEY(namespace,record_key))';

async function writeControlledRecords(t, {terminal = false, dependent = null, singleEffect = false} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'native-model-custody-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const journalPath = join(root, 'journal.sqlite3'), storePath = join(root, 'store.sqlite3');
  const runId = knownCid('public run');
  const definition = knownCid('run definition');
  const requestScope = knownCid('accepted request scope');
  const authority = knownCid('store authority');
  const namespace = 'fixture';
  const provider = 'models/http';
  const selected = (terminal || singleEffect) ? ['first'] : ['first', 'second'];
  const attempts = selected.map(name => knownCid(name + ' attempt'));
  const tasks = selected.map(name => knownCid(name + ' task'));
  const providerByTask = dependent ? new Map(tasks.map((task, i) => [task, provider + '-' + selected[i]])) : null;
  const submissionId = knownCid('original submission');
  const diagnostic = {code: 'ACTQL_E_MODEL_RATE_LIMIT', message: 'The Model provider rate-limited the request'};
  const policyBodies = ['accounts', 'usage'].map(name => {
    const source = {classification: 'internal', minimum_classification: null,
      source_data_policy_cid: knownCid(name + ' declared policy'), source_ref: 'connector://files/native-fixture/' + name + '#records',
      source_view_contract_cid: knownCid(name + ' view'), version: 'actql-source-response-policy/0.1'};
    return {body: JSON.stringify(source), source};
  });
  const expectedResponseViews = new Map(policyBodies.map(({body, source}) =>
    [knownCid(body), source.source_view_contract_cid]));
  const expectedPolicyWire = JSON.stringify({classification: 'unknown',
    source_data_policy_cids: policyBodies.map(({source}) => source.source_data_policy_cid).sort(),
    source_response_policy_cids: [...expectedResponseViews.keys()].sort(),
    unknown_provenance: true, version: 'actql-effective-data-policy/0.1'});
  const publicationContracts = (terminal || dependent === 'lost-reply' ? [] : ['run receipt', 'result manifest', 'result artifact']).map(role => ({
    identity: knownCid(role), wire: JSON.stringify({fixture: role}),
  }));
  const records = [];
  const store = new DatabaseSync(storePath);
  let rawKey;
  let storeBinding;
  let receiverDigest;
  try {
    store.exec(recordTable);
    const {dev, ino} = await stat(storePath, {bigint: true});
    storeBinding = JSON.stringify([namespace, authority, String(dev), String(ino)]);
    const putResult = store.prepare("INSERT INTO actql_records VALUES ('publication_contract', ?, 0, ?)");
    for (const {identity, wire} of publicationContracts) putResult.run(identity, Buffer.from(wire));
    const putCell = store.prepare("INSERT INTO actql_records VALUES ('model_evidence_custody', ?, 0, ?)");
    for (const [i, attempt] of attempts.entries()) {
      const slot = knownCid('slot ' + i), scope = knownCid('invocation scope ' + i);
      const fixed_request_cid = knownCid('request body ' + i);
      const authorityCid = knownCid('infer authorization ' + i);
      const model_task_cid = tasks[i];
      const originalProvider = providerByTask?.get(model_task_cid) ?? provider;
      const run_definition_cid = definition;
      const selected = {model_task_cid, fixed_request_cid, run_definition_cid};
      const receiver = dependent !== null && i === 1;
      const producer = dependent !== null && i === 0;
      const failure = terminal || (receiver && dependent === 'rate-limited');
      const body = canonicalText({
        version: receiver ? 'actql-native-dependent-model-call-original/0.1' : 'actql-native-model-call-original/0.1',
        slot: 0, run_definition_cid, request_scope_cid: requestScope,
        attempt: JSON.stringify({...selected, self_cid: attempt, slot_cid: slot, attempt: 1,
          provider_id: originalProvider, authority_evidence_cid: authorityCid}),
        authority: JSON.stringify({...selected, self_cid: authorityCid, operation: 'infer',
          model_invocation_scope_cid: scope, connection: originalProvider}),
        call: JSON.stringify({...selected, model_call_slot_cid: slot}),
        ...(receiver ? {dependency: {
          scope_cid: scope, ports: [{input: 0, stage: 1, step: 1, artifact_cid: knownCid('producer artifact'),
            manifest_cid: knownCid('producer manifest'), producer_scope_cid: knownCid('invocation scope 0')}],
          producers: [{scope_cid: knownCid('invocation scope 0'), slots: [{slot: 0, attempt_cid: attempts[0],
            raw_cid: knownCid('model_raw_response0'), bundle_cid: knownCid('model_capture_bundle0')}]}],
        }} : {}),
      });
      records.push(['client_model_call_originals', attempt, Buffer.from(body)]);
      if (receiver) {
        receiverDigest = knownCid(body);
        if (dependent === 'lost-reply') continue;
      }
      const evidence = [];
      for (const [phase, role] of [
        ['entered', 'model_raw_response'], ['settled', 'model_call_attempt'],
        ['settled', 'model_attempt_accounting'], ['settled', 'model_attempt_outcome'],
        ['settled', 'model_dispatch_authority'], ['settled', 'model_slot_capture'],
        ['settled', failure ? 'model_raw_response' : 'model_invocation_evidence'], ['settled', 'model_capture_bundle'],
        ...(producer ? [['settled', 'model_raw_response']] : []),
      ]) {
        const holding = knownCid(JSON.stringify({attempt: 1, attempt_cid: attempt, phase, role,
          run_definition_cid, scope_cid: scope, slot_cid: slot, store_authority_cid: authority,
          version: 'actql-model-scoped-private-holding/0.1'}));
        // Envelope-format samples only. Actual Native encryption/readback is
        // exercised by the installed scenario that uses this observer.
        putCell.run(holding, Buffer.from(JSON.stringify({version: 'actql-private-publication-evidence/0.1',
          nonce: Buffer.alloc(12).toString('base64'), tag: Buffer.alloc(16).toString('base64'),
          ciphertext: Buffer.from('fixture envelope for ' + role).toString('base64')})));
        if (phase === 'entered') {
          rawKey ??= holding;
          continue;
        }
        const cid = role === 'model_call_attempt' ? attempt :
          role === 'model_dispatch_authority' ? authorityCid : knownCid(role + i);
        evidence.push({role, cid, holding_cid: holding});
      }
      const settlement = Buffer.from(JSON.stringify({version: 'actql-native-model-call-settlement-original/0.1',
        attempt_cid: attempt, entry_digest: knownCid(body), slot: 0, run_definition_cid,
        request_scope_cid: requestScope, scope_cid: scope, store_binding: storeBinding, evidence}));
      records.push(['client_model_call_settlements', attempt, settlement]);
    }
  } finally { store.close(); }
  const journal = new DatabaseSync(journalPath);
  try {
    journal.exec(recordTable);
    records.push(['client_runs', knownCid('journal run'), Buffer.from(JSON.stringify({
      publication_binding: storeBinding, run_definition: JSON.stringify({run_id: runId, run_definition_cid: definition}),
      publication_policy_originals: JSON.stringify({
        bodies: [expectedPolicyWire, ...policyBodies.map(({body}) => body)]
          .map(body => ({body, cid: knownCid(body), kind: 'data_policy'})),
        root_policy_cid: knownCid(expectedPolicyWire),
      }),
    }))]);
    if (terminal || dependent === 'lost-reply') {
      const updatedAt = '2026-11-26T04:00:00.000Z';
      const facts = {version: 'actql-run-state/0.1', status: terminal ? 'failed' : 'needs_reconciliation', run_id: runId,
        result_available: false, result_availability: {answer: {state: 'unavailable', reason: 'not_published'}},
        ...(terminal ? {next_action: {kind: 'none'}, terminal_error: diagnostic} :
          {next_action: {kind: 'reconcile_run', reason: 'execution_unknown'}})};
      const state = {...facts, revision: 0, updated_at: updatedAt,
        result_availability: {answer: {...facts.result_availability.answer, observed_at: updatedAt}}};
      records.push(['client_submitted_intents', submissionId, Buffer.from(canonicalText({
        version: 'actql-native-client-submitted-intent-row/0.1',
        phase: 'ready',
        reference: canonicalText({nonce: 'original-controlled-reference'}),
        run_admission: canonicalText({run_definition_cid: definition}),
        run_state_revision: 0, run_state_key: canonicalText(facts),
        run_state_original: canonicalText({manifest: null, run_definition_cid: definition, state: canonicalText(state),
          ...(terminal ? {model_failure_attempt_cid: attempts[0], model_failure_raw_cid: knownCid('model_raw_response0')} :
            {model_unknown_attempt_cid: attempts[1], model_unknown_entry_digest: receiverDigest}),
        }),
      }))]);
    }
    const putRecord = journal.prepare('INSERT INTO actql_records VALUES (?, ?, 0, ?)');
    for (const record of records) putRecord.run(...record);
  } finally { journal.close(); }
  return {query: {journalPath, storePath, runId, attempts, tasks, authority, namespace, provider,
    expectedPolicyWire, expectedResponseViews, publicationContracts,
    ...(terminal ? {terminal: {submissionId, diagnostic}} : {}), ...(singleEffect ? {singleEffect} : {}),
    ...(dependent ? {dependent: {loss: dependent === 'lost-reply',
      receiverRateLimited: dependent === 'rate-limited', submissionId}, providerByTask} : {})}, rawKey};
}

test('Model custody joins both original attempts to their admitted tasks and retained Store cells', async t => {
  const {query} = await writeControlledRecords(t);
  const before = await inspectNativeModelCustody(query);
  assert.deepEqual(before.observed.map(item => item.task).sort(), [...query.tasks].sort());
  assert(before.observed.every(item => item.evidence.length === 7));
  assert.equal(new Set(before.observed.map(item => item.rawHolding)).size, 2);
  assert.deepEqual(await inspectNativeModelCustody(query), before);
  assert.equal(before.policy.policyCid, knownCid(query.expectedPolicyWire));
  assert.deepEqual(before.originalResultContracts, query.publicationContracts.map(({identity, wire}) =>
    ({identity, bodyCid: knownCid(wire)})));
  await assert.rejects(inspectNativeModelCustody({...query, expectedPolicyWire: query.expectedPolicyWire + ' '}),
    {code: 'ERR_ASSERTION'});
  const swapped = new Map([...query.expectedResponseViews].map(([key], i, views) => [key, views[1 - i][1]]));
  await assert.rejects(inspectNativeModelCustody({...query, expectedResponseViews: swapped}), {code: 'ERR_ASSERTION'});
  const foreign = knownCid('foreign');
  await assert.rejects(inspectNativeModelCustody({...query, runId: foreign}), {code: 'ERR_ASSERTION'});
  await assert.rejects(inspectNativeModelCustody({...query, attempts: [query.attempts[0], foreign]}),
    {message: 'Missing original Model entry or settlement'});
  await assert.rejects(inspectNativeModelCustody({...query, tasks: [query.tasks[0], foreign]}), {code: 'ERR_ASSERTION'});
});

test('Model custody observes one selected attempt and rejects a second physical Entry', async t => {
  const {query, rawKey} = await writeControlledRecords(t, {singleEffect: true});
  const before = await inspectNativeModelCustody(query);
  assert.equal(before.observed.length, 1);
  const [observed] = before.observed;
  assert.equal(observed.attempt, query.attempts[0]);
  assert.equal(observed.task, query.tasks[0]);
  assert.equal(observed.rawHolding, rawKey);
  assert.equal(observed.evidence.length, 7);
  assert.deepEqual(await inspectNativeModelCustody(query), before);
  await assert.rejects(inspectNativeModelCustody({...query, attempts: [knownCid('foreign attempt')]}),
    {message: 'Missing original Model entry or settlement'});

  const journal = new DatabaseSync(query.journalPath);
  try {
    const added = journal.prepare(`
      INSERT INTO actql_records SELECT namespace, ?, revision, body FROM actql_records
      WHERE namespace = 'client_model_call_originals' AND record_key = ?
    `).run(knownCid('second physical entry'), observed.attempt);
    assert.equal(added.changes, 1);
  } finally { journal.close(); }
  await assert.rejects(inspectNativeModelCustody(query), {
    code: 'ERR_ASSERTION', message: /^Unexpected record count in client_model_call_originals\b/u,
    actual: 2, expected: 1,
  });
});

test('Model custody detects changed Raw bytes and refuses foreign holdings', async t => {
  const {query, rawKey} = await writeControlledRecords(t);
  const before = await inspectNativeModelCustody(query);
  const store = new DatabaseSync(query.storePath);
  try {
    const statement = store.prepare("SELECT body FROM actql_records WHERE namespace='model_evidence_custody' AND record_key=?");
    const envelope = JSON.parse(Buffer.from(statement.get(rawKey).body).toString('utf8'));
    envelope.ciphertext = Buffer.from('other encrypted fixture bytes').toString('base64');
    assert.equal(store.prepare("UPDATE actql_records SET body=? WHERE namespace='model_evidence_custody' AND record_key=?")
      .run(Buffer.from(JSON.stringify(envelope)), rawKey).changes, 1);
  } finally { store.close(); }
  const changed = await inspectNativeModelCustody(query);
  const rawCid = snapshot => snapshot.observed.find(item => item.rawHolding === rawKey).encryptedRawCid;
  assert.notEqual(rawCid(changed), rawCid(before));

  const moved = new DatabaseSync(query.storePath);
  try {
    assert.equal(moved.prepare("UPDATE actql_records SET record_key=? WHERE namespace='model_evidence_custody' AND record_key=?")
      .run(knownCid('wrong raw holding'), rawKey).changes, 1);
  } finally { moved.close(); }
  await assert.rejects(inspectNativeModelCustody(query), {message: 'Missing or repeated original Model Store holding'});
});

test('Model custody rejects a foreign publication CID, body, or generation', async t => {
  const {query} = await writeControlledRecords(t);
  const [original, ...other] = query.publicationContracts;
  await assert.rejects(inspectNativeModelCustody({...query, publicationContracts:
    [{...original, identity: knownCid('other run receipt')}, ...other]}),
  {message: 'Missing original Result publication contract'});
  await assert.rejects(inspectNativeModelCustody({...query, publicationContracts:
    [{...original, wire: original.wire.replace('receipt', 'Receipt')}, ...other]}),
  {code: 'ERR_ASSERTION'});

  const store = new DatabaseSync(query.storePath);
  try {
    assert.equal(store.prepare("UPDATE actql_records SET revision=1 WHERE namespace='publication_contract' AND record_key=?")
      .run(original.identity).changes, 1);
  } finally { store.close(); }
  await assert.rejects(inspectNativeModelCustody(query), {code: 'ERR_ASSERTION'});
});


test('strict terminal custody binds the exact Run, settled Raw and no Result', async t => {
  const {query} = await writeControlledRecords(t, {terminal: true});
  const before = await inspectNativeModelCustody({...query, runId: undefined});
  assert.equal(before.runId, query.runId);
  assert.equal(before.terminalRun.state.status, 'failed');
  assert.equal(before.terminalRun.state.revision, 0);
  assert.deepEqual(before.terminalRun.state.terminal_error, query.terminal.diagnostic);
  assert.deepEqual(await inspectNativeModelCustody(query), before);
  await assert.rejects(inspectNativeModelCustody({...query,
    terminal: {...query.terminal, submissionId: knownCid('foreign submission')}}), /original terminal Submission/u);

  const store = new DatabaseSync(query.storePath);
  try {
    store.prepare("INSERT INTO actql_records VALUES ('publication_contract', ?, 0, ?)")
      .run(knownCid('foreign result'), Buffer.from(canonicalText({version: 'actql-result-artifact/0.1'})));
  } finally { store.close(); }
  await assert.rejects(inspectNativeModelCustody(query), /Terminal failure published a Result/u);
});

test('strict terminal custody refuses a different same-shape Raw locator', async t => {
  const {query} = await writeControlledRecords(t, {terminal: true});
  const db = new DatabaseSync(query.journalPath);
  try {
    const get = db.prepare("SELECT body FROM actql_records WHERE namespace='client_submitted_intents' AND record_key=?");
    const {body} = get.get(query.terminal.submissionId);
    const row = JSON.parse(Buffer.from(body).toString('utf8'));
    const saved = JSON.parse(row.run_state_original);
    row.run_state_original = canonicalText({...saved, model_failure_raw_cid: knownCid('foreign exact shape Raw')});
    db.prepare("UPDATE actql_records SET body=? WHERE namespace='client_submitted_intents' AND record_key=?")
      .run(Buffer.from(canonicalText(row)), query.terminal.submissionId);
  } finally { db.close(); }
  await assert.rejects(inspectNativeModelCustody(query), /Expected values to be strictly equal/u);
});


test('dependent custody binds the original confirmed producer to the receiving Entry', async t => {
  const {query} = await writeControlledRecords(t, {dependent: 'completed'});
  const snapshot = await inspectNativeModelCustody(query);
  assert.equal(snapshot.receiver.attempt, query.attempts[1]);
  assert.equal(snapshot.receiver.provider, query.providerByTask.get(query.tasks[1]));
  const swapped = new Map(query.tasks.map((task, i) => [task, query.providerByTask.get(query.tasks[1 - i])]));
  await assert.rejects(inspectNativeModelCustody({...query, providerByTask: swapped}), {code: 'ERR_ASSERTION'});
  await assert.rejects(inspectNativeModelCustody({...query,
    providerByTask: new Map(query.tasks.map(task => [task, query.provider]))}), {code: 'ERR_ASSERTION'});
  assert.equal(snapshot.receiver.dependency.producers[0].slots[0].attempt_cid, query.attempts[0]);
  assert.equal(snapshot.observed.length, 2);
  assert.equal(snapshot.terminalRun, undefined);
});

test('a complete dependent RateLimit retains both Attempts, but only A has a successful invocation', async t => {
  const {query} = await writeControlledRecords(t, {dependent: 'rate-limited'});
  const snapshot = await inspectNativeModelCustody(query);
  const producer = snapshot.observed.find(({task}) => task === query.tasks[0]);
  const receiver = snapshot.observed.find(({task}) => task === query.tasks[1]);
  assert.equal(producer.attempt, query.attempts[0]);
  assert.equal(receiver.attempt, query.attempts[1]);
  assert.equal(snapshot.terminalRun, undefined);
  assert(producer.evidence.some(({role}) => role === 'model_invocation_evidence'));
  assert(!receiver.evidence.some(({role}) => role === 'model_invocation_evidence'));
  assert.equal(receiver.evidence.filter(({role}) => role === 'model_raw_response').length, 1);
  await assert.rejects(inspectNativeModelCustody({...query, dependent: {...query.dependent,
    receiverRateLimited: false}}), {code: 'ERR_ASSERTION'});
});

test('dependent loss retains only the original producer settlement and a receiving Unknown locator', async t => {
  const {query, rawKey} = await writeControlledRecords(t, {dependent: 'lost-reply'});
  const before = await inspectNativeModelCustody(query);
  assert.equal(before.terminalRun.state.status, 'needs_reconciliation');
  assert.deepEqual(before.observed.map(({attempt}) => attempt), [query.attempts[0]]);
  assert.equal(before.receiver.attempt, query.attempts[1]);
  await withMissingNativeModelFixtureCell(query.storePath, rawKey, async () => {
    await assert.rejects(inspectNativeModelCustody(query), /Unexpected record count/u);
    const omitted = await inspectNativeModelCustody({...query, enteredRawAbsent: true});
    assert.deepEqual(omitted, {...before, observed: before.observed.map(row => ({...row, encryptedRawCid: null}))});
  });
  for (const role of ['model_invocation_evidence', 'model_capture_bundle', 'model_raw_response']) {
    const original = before.observed[0].evidence.find(leaf => leaf.role === role);
    assert(original);
    await withMissingNativeModelFixtureCell(query.storePath, original.holding, async () => {
      await assert.rejects(inspectNativeModelCustody(query), /Unexpected record count/u);
    });
  }
  assert.deepEqual(await inspectNativeModelCustody(query), before);
});

test('the live B reply boundary requires the already committed A originals and the still-unpublished Submission', async t => {
  const {query, rawKey} = await writeControlledRecords(t, {dependent: 'lost-reply'});
  const {attempts: _attempts, runId: _run, dependent, ...original} = query;
  const warmQuery = {...original, dependent: {
    loss: true, beforeReply: true, submissionReferenceWire: canonicalText({nonce: 'original-controlled-reference'}),
  }};
  const {terminalRun, ...confirmedCustody} = await inspectNativeModelCustody(query);
  await assert.rejects(inspectNativeModelCustody(warmQuery), /already published before the B reply/u);

  const db = new DatabaseSync(query.journalPath);
  let committed;
  try {
    const published = db.prepare("SELECT body FROM actql_records WHERE namespace = 'client_submitted_intents' AND record_key = ?")
      .get(dependent.submissionId);
    committed = published.body;
    const {run_state_original: _wire, run_state_revision: _revision, run_state_key: _key, ...pending} =
      JSON.parse(Buffer.from(committed).toString('utf8'));
    db.prepare("UPDATE actql_records SET body = ? WHERE namespace = 'client_submitted_intents' AND record_key = ?")
      .run(Buffer.from(canonicalText(pending)), dependent.submissionId);
  } finally { db.close(); }

  const {submissionBeforeReply, ...warmCustody} = await inspectNativeModelCustody(warmQuery);
  assert.equal(submissionBeforeReply.id, dependent.submissionId);
  assert.deepEqual(warmCustody, confirmedCustody);
  await assert.rejects(inspectNativeModelCustody({...warmQuery,
    dependent: {...warmQuery.dependent, submissionReferenceWire: '{"nonce":"foreign"}'}}), {code: 'ERR_ASSERTION'});
  await withMissingNativeModelFixtureCell(query.storePath, rawKey, async () => {
    await assert.rejects(inspectNativeModelCustody(warmQuery), /Unexpected record count/u);
  });

  const later = new DatabaseSync(query.journalPath);
  try {
    later.prepare("UPDATE actql_records SET body = ? WHERE namespace = 'client_submitted_intents' AND record_key = ?")
      .run(committed, dependent.submissionId);
  } finally { later.close(); }
  assert.deepEqual(await inspectNativeModelCustody(query), {...confirmedCustody, terminalRun});
});
