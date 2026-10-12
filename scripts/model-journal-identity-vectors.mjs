// Independent authored inputs and canonical oracle, never product output.
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';

const pin = n => 'sha256:' + n.toString(16).padStart(64, '0');
const hash = value => 'sha256:' + createHash('sha256')
  .update(canonicalText(value), 'utf8').digest('hex');
const instant = '2026-10-12T00:00:00.000Z';
const later = '2026-10-12T01:00:00.000Z';
export const originalEntry = {
  version: 'actql-model-journal-entry/0.1', run_id: 'original-e\u0301\r\n',
  run_definition_cid: pin(1), prepared_invocation_cid: pin(2),
  scope_cid: pin(3), provider_binding_cid: pin(4), input_artifact_cid: pin(5),
  task_index: 0, strategy_revision: 2, ordinal: 0, slot_cid: pin(6),
  attempt_index: 1, attempt_cid: pin(7), dispatch_authority_cid: pin(8),
  admitted_at: instant, model_grant_expires_at: later,
  provenance: 'immediate', immediate: {run_valid_until: later,
    dispatch_valid_until: later, parent_resume_fence: null}, deferred: null,
};
const deferred = {...originalEntry, provenance: 'deferred', immediate: null,
  deferred: {checkpoint_cid: pin(9), intent_id: 'intent-original',
    claimant: 'claimant-original', generation: 1, resolution_cid: pin(10),
    verified_resolution_cid: pin(11), lease_expires_ms: 1791766800000,
    prepare_attempt_id: null, kind: 'model_invocation',
    required_artifact_cid: pin(3), decision_subject_cid: null,
    requested_claims: ['invocation_scope_approved'], configuration_cid: pin(12),
    observed_claims: ['invocation_scope_approved'], authority: 'reviewer-e\u0301\r\n',
    approval_expires_at: later}};
const reference = n => ({cid: pin(n), holding_cid: pin(n + 30)});
export const originalSettlement = {
  version: 'actql-model-journal-settlement/0.1', entry_identity_cid: hash(originalEntry),
  state: 'SavedSuccess', durable: true, retry_allowed: false, settled_at: instant,
  evidence: {model_call_attempt: reference(7), model_dispatch_authority: reference(8),
    model_attempt_accounting: reference(13), model_attempt_outcome: reference(14),
    model_slot_capture: reference(15), model_capture_bundle: reference(16),
    terminal_failure: null},
};

export function journalIdentityVectors() {
  const entries = [originalEntry, deferred, {...originalEntry,
    immediate: {...originalEntry.immediate, parent_resume_fence: {
      checkpoint_cid: pin(9), intent_id: 'parent', claimant: 'claimant', generation: 2}}}];
  const settlements = [originalSettlement, {...originalSettlement, state: 'SavedFailure',
    evidence: {...originalSettlement.evidence, model_capture_bundle: null,
      terminal_failure: true}}, {...originalSettlement, state: 'SavedFailure',
    retry_allowed: true, evidence: {...originalSettlement.evidence,
      model_slot_capture: null, model_capture_bundle: null, terminal_failure: false}}];
  const cases = [...entries.map(body => ['model_journal_entry', body]),
    ...settlements.map(body => ['model_journal_settlement', body])]
    .map(([kind, body]) => ({kind, body,
      expected_canonical_bytes: canonicalText(body), expected_cid: hash(body)}));
  const missing = {...originalEntry}; delete missing.scope_cid;
  const invalid = [
    ['model_journal_entry', missing],
    ['model_journal_entry', {...originalEntry, unexpected: 0}],
    ['model_journal_entry', {...originalEntry, provenance: 'deferred'}],
    ['model_journal_entry', {...deferred, immediate: originalEntry.immediate}],
    ['model_journal_entry', {...originalEntry, attempt_index: 0}],
    ['model_journal_entry', {...originalEntry, task_index: 0.5}],
    ['model_journal_entry', {...originalEntry, strategy_revision: -1}],
    ['model_journal_entry', {...deferred,
      deferred: {...deferred.deferred, generation: 0}}],
    ['model_journal_settlement', {...originalSettlement, state: 'EnteredUnknown'}],
    ['model_journal_settlement', {...originalSettlement, durable: false}],
    ['model_journal_settlement', {...originalSettlement, retry_allowed: true}],
    ['model_journal_settlement', {...originalSettlement,
      evidence: {...originalSettlement.evidence, model_call_attempt: null}}],
  ];
  const corpus = {version: 'actql-model-journal-identity-vectors/0.1', cases,
    invalid: invalid.map(([kind, body]) => ({kind, body}))};
  let moon = '// Generated independent original Model journal identity vectors.\n';
  for (const [i, f] of cases.entries()) {
    const complete = canonicalText({...f.body, self_cid: f.expected_cid});
    moon += `\n///|\ntest "original journal identity independent ${i}" {\n` +
      `  let value = seal_run_evidence_value(${JSON.stringify(f.kind)},\n` +
      `    ${JSON.stringify(f.expected_canonical_bytes)}, 16384, 512, 12).unwrap()\n` +
      `  assert_eq(run_evidence_value_identity(value), ${JSON.stringify(f.expected_cid)})\n` +
      `  assert_eq(run_evidence_value_json(value), ${JSON.stringify(complete)})\n` +
      `  let admitted = admit_run_evidence_value(${JSON.stringify(f.kind)},\n` +
      `    ${JSON.stringify(complete)}, 16384, 512, 12).unwrap()\n` +
      `  assert_eq(run_evidence_value_json(admitted), ${JSON.stringify(complete)})\n}\n`;
  }
  for (const [i, [kind, body]] of invalid.entries()) {
    moon += `\n///|\ntest "original journal identity invalid ${i}" {\n` +
      `  assert_true(seal_run_evidence_value(${JSON.stringify(kind)},\n` +
      `    ${JSON.stringify(canonicalText(body))}, 16384, 512, 12) is Err(RunEvidenceInvalidShape))\n}\n`;
  }
  const changes = [
    ['model_journal_entry', originalEntry, {...originalEntry, run_definition_cid: pin(99)}],
    ['model_journal_entry', originalEntry, {...originalEntry, attempt_cid: pin(99)}],
    ['model_journal_settlement', originalSettlement,
      {...originalSettlement, entry_identity_cid: pin(99)}],
    ['model_journal_settlement', originalSettlement, {...originalSettlement,
      evidence: {...originalSettlement.evidence, model_attempt_outcome: reference(99)}}],
  ];
  for (const [i, [kind, original, changed]] of changes.entries()) {
    const complete = canonicalText({...changed, self_cid: hash(original)});
    moon += `\n///|\ntest "original journal identity changed binding ${i}" {\n` +
      `  assert_true(admit_run_evidence_value(${JSON.stringify(kind)},\n` +
      `    ${JSON.stringify(complete)}, 16384, 512, 12) is Err(RunEvidenceIdentityMismatch))\n}\n`;
  }
  const complete = canonicalText({...originalEntry, self_cid: hash(originalEntry)});
  moon += '\n///|\ntest "original journal identity exact wire and limits" {\n' +
    `  assert_true(admit_run_evidence_value("model_journal_entry",\n` +
    `    ${JSON.stringify(' ' + complete)}, 16384, 512, 12) is Err(RunEvidenceInvalidWire))\n` +
    `  assert_true(seal_run_evidence_value("model_journal_entry",\n` +
    `    ${JSON.stringify(canonicalText(originalEntry))}, 8, 512, 12) is Err(RunEvidenceInvalidWire))\n}\n`;
  moon = execFileSync(process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin/moonfmt')
    : 'moonfmt', ['-'], {input: moon, encoding: 'utf8'});
  return {corpus, moon};
}

export function checkJournalIdentityVectors(write = false) {
  const {corpus, moon} = journalIdentityVectors();
  const outputs = [['portability/corpus/model-journal-identities.json',
    JSON.stringify(corpus, null, 2) + '\n'],
  ['src/run_publication/model_journal_identities.generated_test.mbt', moon]];
  for (const [path, output] of outputs) {
    if (write) writeFileSync(path, output);
    else if (readFileSync(path, 'utf8') !== output) throw new Error(`Stale journal vector: ${path}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  checkJournalIdentityVectors(process.argv.includes('--write'));
}
