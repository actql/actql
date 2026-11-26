import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {test} from 'node:test';
import {inspectNativeModelCustody} from './fixtures/native-model-custody-observation.mjs';

const knownCid = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const recordTable = 'CREATE TABLE actql_records (namespace TEXT, record_key TEXT, revision INTEGER, body BLOB,' +
  ' PRIMARY KEY(namespace,record_key))';

async function writeControlledRecords(t) {
  const root = await mkdtemp(join(tmpdir(), 'native-model-custody-test-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const journalPath = join(root, 'journal.sqlite3'), storePath = join(root, 'store.sqlite3');
  const runId = knownCid('public run');
  const definition = knownCid('run definition');
  const requestScope = knownCid('accepted request scope');
  const authority = knownCid('store authority');
  const namespace = 'fixture';
  const provider = 'models/http';
  const attempts = ['first', 'second'].map(name => knownCid(name + ' attempt'));
  const tasks = ['first', 'second'].map(name => knownCid(name + ' task'));
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
  const publicationContracts = ['run receipt', 'result manifest', 'result artifact'].map(role => ({
    identity: knownCid(role), wire: JSON.stringify({fixture: role}),
  }));
  const records = [];
  const store = new DatabaseSync(storePath);
  let rawKey;
  let storeBinding;
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
      const run_definition_cid = definition;
      const selected = {model_task_cid, fixed_request_cid, run_definition_cid};
      const body = JSON.stringify({
        version: 'actql-native-model-call-original/0.1', slot: 0, run_definition_cid, request_scope_cid: requestScope,
        attempt: JSON.stringify({...selected, self_cid: attempt, slot_cid: slot, attempt: 1,
          provider_id: provider, authority_evidence_cid: authorityCid}),
        authority: JSON.stringify({...selected, self_cid: authorityCid, operation: 'infer',
          model_invocation_scope_cid: scope, connection: provider}),
        call: JSON.stringify({...selected, model_call_slot_cid: slot}),
      });
      records.push(['client_model_call_originals', attempt, Buffer.from(body)]);
      const evidence = [];
      for (const [phase, role] of [
        ['entered', 'model_raw_response'], ['settled', 'model_call_attempt'],
        ['settled', 'model_attempt_accounting'], ['settled', 'model_attempt_outcome'],
        ['settled', 'model_dispatch_authority'], ['settled', 'model_slot_capture'],
        ['settled', 'model_invocation_evidence'], ['settled', 'model_capture_bundle'],
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
    const putRecord = journal.prepare('INSERT INTO actql_records VALUES (?, ?, 0, ?)');
    for (const record of records) putRecord.run(...record);
  } finally { journal.close(); }
  return {query: {journalPath, storePath, runId, attempts, tasks, authority, namespace, provider,
    expectedPolicyWire, expectedResponseViews, publicationContracts}, rawKey};
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
