// Read the retained Model rows of one controlled installed run. The Store
// payloads stay encrypted and the observation never reads the epoch key.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstatSync} from 'node:fs';

const cid = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const requireCid = value => assert.match(value, /^sha256:[0-9a-f]{64}$/u);
const journalRecordBytes = 8_388_608;
const evidenceEnvelopeBytes = 1_398_272;
const settledRoles = [
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

export async function inspectNativeModelCustody({
  journalPath, storePath, runId, attempts, tasks, authority, namespace, provider, expectedPolicyWire, expectedResponseViews,
  publicationContracts,
}) {
  requireCid(runId);
  requireCid(authority);
  assert.equal(attempts.length, 2);
  assert.equal(new Set(attempts).size, 2);
  assert(tasks.length > 0 && tasks.length <= attempts.length);
  for (const value of [...attempts, ...tasks]) requireCid(value);
  const originalJournal = fileGeneration(journalPath);
  const originalStore = fileGeneration(storePath);
  const binding = [namespace, authority, originalStore.device, originalStore.inode];
  const {DatabaseSync} = await import('node:sqlite');
  const journal = new DatabaseSync(journalPath, {readOnly: true});
  try {
    const [record] = readRecords(journal, 'client_runs', 1, journalRecordBytes).values();
    const run = rowJson(record);
    const definition = JSON.parse(run.run_definition);
    assert.equal(definition.run_id, runId);
    requireCid(definition.run_definition_cid);
    assert.deepEqual(JSON.parse(run.publication_binding), binding);
    const policy = inspectRetainedPolicy(run.publication_policy_originals, expectedPolicyWire, expectedResponseViews);
    const entries = readRecords(journal, 'client_model_call_originals', 2, journalRecordBytes);
    const settlements = readRecords(journal, 'client_model_call_settlements', 2, journalRecordBytes);
    const store = new DatabaseSync(storePath, {readOnly: true});
    try {
      const originalResultContracts = inspectRetainedResultContracts(store, publicationContracts);
      const cells = readRecords(store, 'model_evidence_custody', attempts.length * (settledRoles.length + 1),
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
      for (const attempt of [...attempts].sort()) {
        const original = entries.get(attempt);
        const settled = settlements.get(attempt);
        assert(original && settled, 'Missing original Model entry or settlement');
        assert.equal(original.revision, 0);
        assert.equal(settled.revision, 0);
        const entry = rowJson(original);
        const terminal = rowJson(settled);
        const declared = JSON.parse(entry.attempt);
        const call = JSON.parse(entry.call);
        const authorized = JSON.parse(entry.authority);
        assert.equal(entry.version, 'actql-native-model-call-original/0.1');
        assert.equal(terminal.version, 'actql-native-model-call-settlement-original/0.1');
        assert.equal(terminal.entry_digest, cid(original.body));
        assert.equal(terminal.attempt_cid, attempt);
        assert.equal(declared.self_cid, attempt);
        assert.equal(declared.attempt, 1);
        assert.equal(declared.provider_id, provider);
        assert.equal(authorized.connection, provider);
        assert.equal(authorized.operation, 'infer');
        for (const owner of [entry, terminal, declared, authorized]) {
          assert.equal(owner.run_definition_cid, definition.run_definition_cid);
        }
        assert.equal(entry.request_scope_cid, terminal.request_scope_cid);
        assert.equal(terminal.store_binding, run.publication_binding);
        assert.equal(entry.slot, 0);
        assert.equal(terminal.slot, 0);
        assert.equal(authorized.model_invocation_scope_cid, terminal.scope_cid);
        assert.equal(call.model_call_slot_cid, declared.slot_cid);
        assert.equal(authorized.fixed_request_cid, declared.fixed_request_cid);
        assert.equal(call.fixed_request_cid, declared.fixed_request_cid);
        assert.equal(authorized.self_cid, declared.authority_evidence_cid);
        assert.equal(call.model_task_cid, declared.model_task_cid);
        assert.equal(authorized.model_task_cid, declared.model_task_cid);
        scopes.add(terminal.scope_cid);
        slots.add(declared.slot_cid);
        claimedTasks.add(declared.model_task_cid);
        const scope = {definition: definition.run_definition_cid, authority, scope: terminal.scope_cid,
          slot: declared.slot_cid, attempt};
        requireCid(scope.scope);
        requireCid(scope.slot);
        assert.deepEqual(terminal.evidence.map(({role}) => role).sort(), settledRoles);
        const evidence = terminal.evidence.map(leaf => {
          requireCid(leaf.cid);
          if (leaf.role === 'model_call_attempt') assert.equal(leaf.cid, attempt);
          if (leaf.role === 'model_dispatch_authority') assert.equal(leaf.cid, authorized.self_cid);
          const holding = holdingCid(scope, 'settled', leaf.role);
          assert.equal(leaf.holding_cid, holding);
          return {role: leaf.role, evidenceCid: leaf.cid, holding, encryptedBodyCid: takeCell(holding)};
        });
        const rawHolding = holdingCid(scope, 'entered', 'model_raw_response');
        observed.push({attempt, task: declared.model_task_cid, slot: scope.slot, scope: scope.scope, entryBodyCid: cid(original.body),
          settlementBodyCid: cid(settled.body), rawHolding, encryptedRawCid: takeCell(rawHolding), evidence});
      }
      assert.deepEqual([...claimedTasks].sort(), [...tasks].sort());
      assert.equal(scopes.size, 2);
      assert.equal(slots.size, 2);
      assert.equal(cells.size, 0, 'Unexpected Model holdings in the fresh project');
      assert.deepEqual(fileGeneration(journalPath), originalJournal);
      assert.deepEqual(fileGeneration(storePath), originalStore);
      return {runId, definition: definition.run_definition_cid, authority, policy, observed, originalResultContracts};
    } finally { store.close(); }
  } finally { journal.close(); }
}
