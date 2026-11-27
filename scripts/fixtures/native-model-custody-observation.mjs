// Read the retained Model rows of one controlled installed run. The Store
// payloads stay encrypted and the observation never reads the epoch key.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstatSync} from 'node:fs';
import {canonicalText} from '../check-canonical-json.mjs';

const cid = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const requireCid = value => assert.match(value, /^sha256:[0-9a-f]{64}$/u);
const journalRecordBytes = 8_388_608;
const evidenceEnvelopeBytes = 1_398_272;
const successRoles = [
  'model_attempt_accounting', 'model_attempt_outcome', 'model_call_attempt', 'model_capture_bundle',
  'model_dispatch_authority', 'model_invocation_evidence', 'model_slot_capture',
];

function holdingCid({definition, authority, scope, slot, attempt}, phase, role) {
  // The contract preimage uses canonical key order. Values here are CIDs and
  // fixed phase/role names from the Model private-holding contract.
  return cid(JSON.stringify({
    attempt: 1, attempt_cid: attempt, phase, role, run_definition_cid: definition,
    scope_cid: scope, slot_cid: slot, store_authority_cid: authority,
    version: 'actql-model-scoped-private-holding/0.1',
  }));
}

function readRecords(database, namespace, expectedCount, maximumBytes) {
  const rows = database.prepare(`
    SELECT record_key, revision,
      CASE WHEN typeof(body) = 'blob' AND length(body) BETWEEN 1 AND ? THEN body END AS body
    FROM actql_records WHERE namespace = ? ORDER BY record_key LIMIT ?
  `).all(maximumBytes, namespace, expectedCount + 1);
  assert.equal(rows.length, expectedCount, `Unexpected record count in ${namespace}`);
  for (const {record_key: key, body} of rows) {
    requireCid(key);
    assert(body instanceof Uint8Array, `Invalid record extent in ${namespace}`);
  }
  return new Map(rows.map(row => [row.record_key, row]));
}

function rowJson(row) {
  return JSON.parse(Buffer.from(row.body).toString('utf8'));
}

function inspectRetainedResultContracts(database, contracts) {
  const original = database.prepare(`
    SELECT revision, CASE WHEN typeof(body) = 'blob' AND length(body) = ? THEN body END AS body
    FROM actql_records WHERE namespace = 'publication_contract' AND record_key = ?
  `);
  return contracts.map(({identity, wire}) => {
    requireCid(identity);
    const record = original.get(Buffer.byteLength(wire), identity);
    assert(record?.body instanceof Uint8Array, 'Missing original Result publication contract');
    assert.equal(record.revision, 0);
    assert(Buffer.from(record.body).equals(Buffer.from(wire, 'utf8')), 'Changed original Result publication bytes');
    return {identity, bodyCid: cid(record.body)};
  });
}

function assertEncryptedEnvelope(row) {
  assert.equal(row.revision, 0);
  const envelope = rowJson(row);
  assert.deepEqual(Object.keys(envelope).sort(), ['ciphertext', 'nonce', 'tag', 'version']);
  assert.equal(envelope.version, 'actql-private-publication-evidence/0.1');
  for (const [name, exact] of [['nonce', 12], ['tag', 16], ['ciphertext', null]]) {
    const bytes = Buffer.from(envelope[name], 'base64');
    assert(bytes.length > 0 && (exact === null || bytes.length === exact), `Invalid encrypted ${name} extent`);
    assert(bytes.toString('base64') === envelope[name], `Invalid encrypted ${name} encoding`);
  }
}

function fileGeneration(path) {
  const info = lstatSync(path, {bigint: true});
  assert(info.isFile(), 'Native custody path must be the original file');
  return {device: String(info.dev), inode: String(info.ino), size: info.size, mtime: info.mtimeNs, ctime: info.ctimeNs};
}

function inspectRetainedPolicy(wire, expectedWire, expectedResponseViews) {
  assert(typeof wire === 'string' && Buffer.byteLength(wire) <= 65_536,
    'Missing or out-of-bounds original Run policy packet');
  const packet = JSON.parse(wire);
  assert.deepEqual(Object.keys(packet), ['bodies', 'root_policy_cid']);
  assert(Array.isArray(packet.bodies) && packet.bodies.length <= 64);
  const policyCid = cid(expectedWire);
  assert.equal(packet.root_policy_cid, policyCid);
  assert.deepEqual(packet.bodies[0], {body: expectedWire, cid: policyCid, kind: 'data_policy'});
  const expected = JSON.parse(expectedWire);
  assert.deepEqual([...expectedResponseViews.keys()].sort(), expected.source_response_policy_cids);
  for (const [responseCid, viewCid] of expectedResponseViews) {
    const responses = packet.bodies.filter(row => row.cid === responseCid);
    assert.equal(responses.length, 1);
    const [response] = responses;
    assert.equal(response.kind, 'data_policy');
    assert.equal(cid(response.body), responseCid);
    const source = JSON.parse(response.body);
    assert.equal(source.version, 'actql-source-response-policy/0.1');
    assert.equal(source.source_view_contract_cid, viewCid);
    assert(expected.source_data_policy_cids.includes(source.source_data_policy_cid));
  }
  return {policyCid, packetCid: cid(wire)};
}

function inspectTerminalRun(journal, store, {submissionId, diagnostic, unknown}, {runId, definition, record, observed}) {
  const submissions = readRecords(journal, 'client_submitted_intents', 1, journalRecordBytes);
  const row = submissions.get(submissionId);
  assert(row, 'Missing the original terminal Submission');
  const submission = rowJson(row);
  assert.equal(submission.version, 'actql-native-client-submitted-intent-row/0.1');
  const wire = submission.run_state_original;
  assert(typeof wire === 'string' && Buffer.byteLength(wire) <= 131_072, 'Missing bounded original RunState');
  const saved = JSON.parse(wire);
  if (unknown) {
    assert.deepEqual(Object.keys(saved), ['manifest', 'model_unknown_attempt_cid', 'model_unknown_entry_digest',
      'run_definition_cid', 'state']);
    assert.equal(saved.model_unknown_attempt_cid, unknown.attempt);
    assert.equal(saved.model_unknown_entry_digest, unknown.entryBodyCid);
  } else {
    assert.deepEqual(Object.keys(saved), ['manifest', 'model_failure_attempt_cid', 'model_failure_raw_cid',
      'run_definition_cid', 'state']);
    assert.equal(saved.model_failure_attempt_cid, observed.attempt);
    assert.equal(saved.model_failure_raw_cid,
      observed.evidence.find(({role}) => role === 'model_raw_response').evidenceCid);
  }
  assert.equal(saved.manifest, null);
  assert.equal(saved.run_definition_cid, definition);
  const state = JSON.parse(saved.state);
  assert.equal(state.version, 'actql-run-state/0.1');
  assert.equal(state.run_id, runId);
  assert.equal(state.status, unknown ? 'needs_reconciliation' : 'failed');
  assert.equal(state.revision, 0);
  assert.equal(state.revision, submission.run_state_revision);
  assert.equal(state.result_available, false);
  assert.deepEqual(state.result_availability, {answer: {
    state: 'unavailable', observed_at: state.updated_at, reason: 'not_published',
  }});
  assert.deepEqual(state.next_action, unknown ?
    {kind: 'reconcile_run', reason: 'execution_unknown'} : {kind: 'none'});
  assert.deepEqual(state.terminal_error, diagnostic);
  const {revision, updated_at, ...originalFacts} = state;
  originalFacts.result_availability = {answer: {state: 'unavailable', reason: 'not_published'}};
  assert.equal(submission.run_state_key, canonicalText(originalFacts));
  readRecords(store, 'publication_payload', 0, 0);
  const contracts = store.prepare(`
    SELECT record_key, CASE WHEN typeof(body) = 'blob' AND length(body) BETWEEN 1 AND 65536 THEN body END AS body
    FROM actql_records WHERE namespace = 'publication_contract' ORDER BY record_key LIMIT 33
  `).all();
  assert(contracts.length <= 32, 'Unexpected publication inventory in terminal fixture');
  for (const contract of contracts) {
    assert(contract.body instanceof Uint8Array, 'Invalid retained publication extent');
    const {version} = rowJson(contract);
    assert.equal(typeof version, 'string');
    assert(!/^actql-(?:result-manifest|result-artifact|run-receipt)\//u.test(version),
      'Terminal failure published a Result or receipt');
  }
  return {state, controlRevision: String(record.revision), observationKey: submission.run_state_key,
    submissionBodyCid: cid(row.body), submissionRevision: row.revision, runBodyCid: cid(record.body)};
}

export async function inspectNativeModelCustody({
  journalPath, storePath, runId, attempts, tasks, authority, namespace, provider, expectedPolicyWire, expectedResponseViews,
  publicationContracts, terminal = null, dependent = null, enteredRawAbsent = false, providerByTask = null, singleEffect = false,
}) {
  assert(!(terminal && dependent));
  assert(!singleEffect || (!terminal && !dependent));
  if (dependent) {
    assert.equal(providerByTask?.size, 2);
    assert.equal(new Set(providerByTask.values()).size, 2);
    assert(tasks.every(task => providerByTask.has(task)), 'Missing exact Provider selection for Task');
  }
  const beforeReply = dependent?.beforeReply === true;
  const receiverRateLimited = dependent?.receiverRateLimited === true;
  assert(!receiverRateLimited || !dependent.loss);
  const unpublished = terminal ?? (dependent?.loss ? {submissionId: dependent.submissionId} : null);
  if (beforeReply) {
    assert(dependent.loss && unpublished && publicationContracts.length === 0);
    assert(!enteredRawAbsent && attempts === undefined && runId === undefined);
    assert.equal(typeof dependent.submissionReferenceWire, 'string');
  } else if (unpublished === null) {
    requireCid(runId);
  } else {
    requireCid(unpublished.submissionId);
  }
  assert(!enteredRawAbsent || dependent?.loss);
  requireCid(authority);
  const count = terminal === null && !singleEffect ? 2 : 1;
  const settledCount = count - (dependent?.loss ? 1 : 0);
  const failureRoles = successRoles.map(role => role === 'model_invocation_evidence' ? 'model_raw_response' : role);
  const settledRoles = terminal === null ? successRoles : failureRoles;
  assert(tasks.length > 0 && tasks.length <= count);
  for (const task of tasks) requireCid(task);
  if (!beforeReply) {
    assert.equal(attempts.length, count);
    assert.equal(new Set(attempts).size, count);
    for (const attempt of attempts) requireCid(attempt);
  }
  const originalJournal = fileGeneration(journalPath);
  const originalStore = fileGeneration(storePath);
  const binding = [namespace, authority, originalStore.device, originalStore.inode];
  const {DatabaseSync} = await import('node:sqlite');
  const journal = new DatabaseSync(journalPath, {readOnly: true});
  try {
    const [record] = readRecords(journal, 'client_runs', 1, journalRecordBytes).values();
    const run = rowJson(record);
    const definition = JSON.parse(run.run_definition);
    if (unpublished !== null && runId === undefined) runId = definition.run_id;
    requireCid(runId);
    assert.equal(definition.run_id, runId);
    requireCid(definition.run_definition_cid);
    assert.deepEqual(JSON.parse(run.publication_binding), binding);
    const policy = inspectRetainedPolicy(run.publication_policy_originals, expectedPolicyWire, expectedResponseViews);
    const entries = readRecords(journal, 'client_model_call_originals', count, journalRecordBytes);
    const settlements = readRecords(journal, 'client_model_call_settlements', settledCount, journalRecordBytes);
    // At the peer's reply boundary the Native process still owns its exit
    // diagnostics. This fresh fixture has exactly two original Entry records.
    const selectedAttempts = beforeReply ? [...entries.keys()] : attempts;
    const store = new DatabaseSync(storePath, {readOnly: true});
    try {
      const originalResultContracts = inspectRetainedResultContracts(store, publicationContracts);
      const cells = readRecords(store, 'model_evidence_custody',
        settledCount * (settledRoles.length + 1) + (dependent ? 1 : 0) - Number(enteredRawAbsent),
        evidenceEnvelopeBytes);
      const claimedTasks = new Set();
      const scopes = new Set();
      const slots = new Set();
      const takeCell = key => {
        const row = cells.get(key);
        assert(row, 'Missing or repeated original Model Store holding');
        assertEncryptedEnvelope(row);
        cells.delete(key);
        return cid(row.body);
      };
      const observed = [];
      let receiver = null;
      for (const attempt of [...selectedAttempts].sort()) {
        const original = entries.get(attempt);
        assert(original, 'Missing original Model entry or settlement');
        assert.equal(original.revision, 0);
        const entry = rowJson(original);
        const declared = JSON.parse(entry.attempt);
        const call = JSON.parse(entry.call);
        const authorized = JSON.parse(entry.authority);
        const task = declared.model_task_cid;
        const receives = dependent !== null && task === tasks[1];
        assert.equal(entry.version, receives ?
          'actql-native-dependent-model-call-original/0.1' : 'actql-native-model-call-original/0.1');
        if (receives) {
          assert.equal(receiver, null);
          receiver = {attempt, task, provider: declared.provider_id,
            scope: authorized.model_invocation_scope_cid, entryBodyCid: cid(original.body),
            dependency: entry.dependency};
        }
        if (dependent) assert.equal(canonicalText(entry), Buffer.from(original.body).toString('utf8'));
        assert.equal(declared.self_cid, attempt);
        assert.equal(declared.attempt, 1);
        const originalProvider = providerByTask?.get(task) ?? provider;
        assert.equal(declared.provider_id, originalProvider);
        assert.equal(authorized.connection, originalProvider);
        assert.equal(authorized.operation, 'infer');
        for (const owner of [entry, declared, authorized]) {
          assert.equal(owner.run_definition_cid, definition.run_definition_cid);
        }
        assert.equal(entry.slot, 0);
        assert.equal(call.model_call_slot_cid, declared.slot_cid);
        assert.equal(authorized.fixed_request_cid, declared.fixed_request_cid);
        assert.equal(call.fixed_request_cid, declared.fixed_request_cid);
        assert.equal(authorized.self_cid, declared.authority_evidence_cid);
        assert.equal(call.model_task_cid, task);
        assert.equal(authorized.model_task_cid, task);
        const scope = {definition: definition.run_definition_cid, authority, scope: authorized.model_invocation_scope_cid,
          slot: declared.slot_cid, attempt};
        requireCid(scope.scope);
        requireCid(scope.slot);
        scopes.add(scope.scope);
        slots.add(scope.slot);
        claimedTasks.add(task);
        const settled = settlements.get(attempt);
        if (receives && dependent.loss) {
          assert.equal(settled, undefined, 'Lost receiver unexpectedly settled');
          assert(!cells.has(holdingCid(scope, 'entered', 'model_raw_response')), 'Lost receiver unexpectedly committed Raw');
          continue;
        }
        assert(settled, 'Missing original Model settlement');
        assert.equal(settled.revision, 0);
        const terminal = rowJson(settled);
        assert.equal(terminal.version, 'actql-native-model-call-settlement-original/0.1');
        assert.equal(terminal.entry_digest, cid(original.body));
        assert.equal(terminal.attempt_cid, attempt);
        assert.equal(terminal.run_definition_cid, definition.run_definition_cid);
        assert.equal(terminal.scope_cid, scope.scope);
        assert.equal(entry.request_scope_cid, terminal.request_scope_cid);
        assert.equal(terminal.store_binding, run.publication_binding);
        assert.equal(terminal.slot, 0);
        const producer = dependent !== null && task === tasks[0];
        const roles = producer ? [...settledRoles, 'model_raw_response'].sort() :
          receives && receiverRateLimited ? failureRoles : settledRoles;
        assert.deepEqual(terminal.evidence.map(({role}) => role).sort(), roles);
        const evidence = terminal.evidence.map(leaf => {
          requireCid(leaf.cid);
          if (leaf.role === 'model_call_attempt') assert.equal(leaf.cid, attempt);
          if (leaf.role === 'model_dispatch_authority') assert.equal(leaf.cid, authorized.self_cid);
          const holding = holdingCid(scope, 'settled', leaf.role);
          assert.equal(leaf.holding_cid, holding);
          return {role: leaf.role, evidenceCid: leaf.cid, holding, encryptedBodyCid: takeCell(holding)};
        });
        const rawHolding = holdingCid(scope, 'entered', 'model_raw_response');
        const encryptedRawCid = producer && enteredRawAbsent ? null : takeCell(rawHolding);
        observed.push({attempt, task, ...(dependent ? {provider: originalProvider} : {}),
          slot: scope.slot, scope: scope.scope, entryBodyCid: cid(original.body),
          settlementBodyCid: cid(settled.body), rawHolding, encryptedRawCid, evidence});
      }
      assert.deepEqual([...claimedTasks].sort(), [...tasks].sort());
      assert.equal(scopes.size, count);
      assert.equal(slots.size, count);
      assert.equal(cells.size, 0, 'Unexpected Model holdings in the fresh project');
      if (dependent) {
        assert(receiver);
        const producer = observed.find(({task}) => task === tasks[0]);
        assert(producer);
        const evidenceCid = role => producer.evidence.find(value => value.role === role).evidenceCid;
        const dependency = receiver.dependency;
        assert.deepEqual(Object.keys(dependency), ['ports', 'producers', 'scope_cid']);
        assert.equal(dependency.scope_cid, receiver.scope);
        assert.equal(dependency.ports.length, 1);
        const [port] = dependency.ports;
        for (const original of [port.artifact_cid, port.manifest_cid]) requireCid(original);
        assert.deepEqual(port, {artifact_cid: port.artifact_cid, input: 0, manifest_cid: port.manifest_cid,
          producer_scope_cid: producer.scope, stage: 1, step: 1});
        assert.deepEqual(dependency.producers, [{scope_cid: producer.scope, slots: [{
          attempt_cid: producer.attempt, bundle_cid: evidenceCid('model_capture_bundle'),
          raw_cid: evidenceCid('model_raw_response'), slot: 0,
        }]}]);
      }
      let submissionBeforeReply;
      if (beforeReply) {
        const [[id, row]] = readRecords(journal, 'client_submitted_intents', 1, journalRecordBytes);
        const submission = rowJson(row);
        assert.equal(submission.version, 'actql-native-client-submitted-intent-row/0.1');
        assert.equal(submission.reference, dependent.submissionReferenceWire);
        assert.equal(submission.phase, 'ready');
        assert.equal(JSON.parse(submission.run_admission).run_definition_cid, definition.run_definition_cid);
        assert.equal(submission.run_state_original, undefined, 'RunState was already published before the B reply');
        submissionBeforeReply = {id, revision: row.revision, bodyCid: cid(row.body)};
      }
      const terminalRun = beforeReply || unpublished === null ? null : inspectTerminalRun(journal, store, {
        ...unpublished, ...(dependent?.loss ? {unknown: receiver} : {}),
      }, {runId, definition: definition.run_definition_cid, record, observed: observed[0]});
      assert.deepEqual(fileGeneration(journalPath), originalJournal);
      assert.deepEqual(fileGeneration(storePath), originalStore);
      return {runId, definition: definition.run_definition_cid, authority, policy, observed, originalResultContracts,
        ...(receiver === null ? {} : {receiver}), ...(terminalRun === null ? {} : {terminalRun}),
        ...(beforeReply ? {submissionBeforeReply} : {})};
    } finally { store.close(); }
  } finally { journal.close(); }
}

// Control an isolated qualification fixture after the verified first close.
// The selected original is restored byte for byte even if the probe fails.
export async function withMissingNativeModelFixtureCell(storePath, holding, inspect) {
  requireCid(holding);
  const {DatabaseSync} = await import('node:sqlite');
  const owner = fileGeneration(storePath);
  const namespace = 'model_evidence_custody';
  const omit = new DatabaseSync(storePath);
  let original;
  try {
    original = omit.prepare(`SELECT revision, body FROM actql_records
      WHERE namespace = ? AND record_key = ? AND typeof(body) = 'blob' AND length(body) BETWEEN 1 AND ?`)
      .get(namespace, holding, evidenceEnvelopeBytes);
    assert(original, 'Missing originally selected fixture cell');
    assertEncryptedEnvelope(original);
    assert.equal(omit.prepare('DELETE FROM actql_records WHERE namespace = ? AND record_key = ? AND revision = 0')
      .run(namespace, holding).changes, 1);
  } finally { omit.close(); }
  try {
    return await inspect();
  } finally {
    const current = fileGeneration(storePath);
    assert.deepEqual([current.device, current.inode], [owner.device, owner.inode]);
    const restore = new DatabaseSync(storePath);
    try {
      assert.equal(restore.prepare('INSERT INTO actql_records (namespace, record_key, revision, body) VALUES (?, ?, 0, ?)')
        .run(namespace, holding, original.body).changes, 1);
    } finally { restore.close(); }
  }
}
