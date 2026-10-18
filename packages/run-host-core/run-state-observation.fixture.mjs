// Complete a portable candidate through the actual original Run journal.
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../../adapters/host-common/runtime-core.mjs';
import {openClientRequestJournal} from '../../adapters/host-node/client-request-journal.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {validRunState} from '../client-wire/index.mjs';
import {privateRunDefinition, requestFields} from './index.mjs';

export async function originalRunStateObservations(t, request, definition) {
  const scratch = await createOwnedScratch({parent: fileURLToPath(new URL(
    '../../_build/run-host-state-observations/', import.meta.url)),
  prefix: 'original-', label: 'Run Host original state observation'});
  const journal = openClientRequestJournal(scratch.path);
  let reader;
  t.after(() => {
    try { reader?.close(); } finally { journal.close(); }
    scratch.passed();
  });
  const control = runtimeCore(moon).publicationControl;
  const fields = requestFields(request);
  const identity = moon.clientRequestAdmitRecord(fields.authorityScopeCid,
    fields.requestId, fields.programDefinitionCid, fields.parameterValuesCid,
    fields.callerInputIntentCid, fields.logicalRequestScopeCid, fields.intentFingerprintCid);
  assert(identity);
  const original = privateRunDefinition(definition);
  const wire = JSON.parse(original.wire);
  const admitted = control.admit('run_definition', original.wire,
    {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64});
  const ref = journal.acceptDefinition(identity, {namespaceId: 'portable-state',
    runDefinition: admitted, resultNames: ['answer'], lookupExpiresAt: wire.valid_until},
  moon, control).ref;
  reader = new DatabaseSync(join(scratch.path, 'client-requests.sqlite3'), {readOnly: true});
  return Object.freeze({publish(candidateWire) {
    const candidate = JSON.parse(candidateWire);
    assert.equal(Object.hasOwn(candidate, 'revision'), false);
    assert.equal(validRunState(candidate), false, 'An unpublished candidate is not a public observation');
    const frame = journal.lookupRunDefinition(ref, moon, control);
    const completed = JSON.parse(journal.publishRunState(frame, candidate, moon, control));
    const saved = reader.prepare(`SELECT state_revision, state_observation_key FROM client_requests
      WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`)
      .get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
    assert.equal(completed.revision, saved.state_revision);
    assert.equal(typeof saved.state_observation_key, 'string');
    const facts = value => Object.fromEntries(Object.entries(value)
      .filter(([key]) => !['revision', 'control'].includes(key)));
    assert.deepEqual(facts(completed), facts(candidate), 'Keep the same original candidate facts');
    return completed;
  }});
}
