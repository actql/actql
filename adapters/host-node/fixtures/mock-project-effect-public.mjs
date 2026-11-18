// Public Mock lifecycle consumer. Each phase runs in a separate process from
// the same Project and ordinary installed @actql/node package namespace.
// No internal Host port, application signer or replacement submission is used.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile, stat} from 'node:fs/promises';
import {connect} from '@actql/node';
import {getSubmissionCheckObservation} from '@actql/sdk';
import {mockProjectWorkflowChecks, startMockProjectSource} from './mock-project-effect-protocol.fixture.mjs';
import {workflowWorkObservation, readWholeResults, checkJoinedSourceRows, readJoinedWholeResults} from './work-observation.fixture.mjs';

const [phase, handoffPath, template = 'churn-risk-mock', variant = 'readme', workPurpose = 'workflow'] = process.argv.slice(2);
assert.ok(['capture', 'approve', 'recover'].includes(phase));
assert.equal(typeof handoffPath, 'string');
assert.ok(['churn-risk-mock', 'deal-review-mock'].includes(template));
const dealReview = template === 'deal-review-mock';
const multipleTargets = variant === 'multiple-targets';
const {multipleTargetMockWriteCount} = multipleTargets
  ? await import('./mock-multiple-targets.fixture.mjs') : {};
assert.ok(variant === 'readme' || multipleTargets && !dealReview || ['two-models', 'two-models-whole', 'two-models-joined-whole', 'two-models-joined-inputs'].includes(variant) && dealReview);
assert.ok(workPurpose === 'workflow' || workPurpose === 'original-run-control' && phase === 'capture');
const twoModels = variant !== 'readme' && !multipleTargets, joinedWholeProducer = variant === 'two-models-joined-whole' || variant === 'two-models-joined-inputs';
const wholeProducer = variant === 'two-models-whole' || joinedWholeProducer;
const C = /^sha256:[0-9a-f]{64}$/u;
const {expected, checkRows, checkReview, expectedBytes} = await mockProjectWorkflowChecks({template, variant});
// A bounded typed-input consumer of the existing optional Evidence handoff. It neither
// invokes a Model nor reads the Journal. Raw input stays inside this fixture;
// only the completed comparison/count is reported after the first public close.
function joinedModelInputEvidence(selectedVariant) {
  assert(['two-models-joined-inputs', 'two-models-joined-whole'].includes(selectedVariant));
  // Independent literal-row SHA256 vectors for the opaque fixture-provider version.
  // See docs/guides/mock-models.md; the raw declared revision is not this version.
  const originals = {
    '006Acme': {StageName: 'Proposal', NextStep: null, fileVersion: 'sha256:3fdf0d901072bf1f3660dc0dfdbf5f6161cec18c459fdac7fed8b4c47d0fdd4e',
      notes: 'Acme renewal meeting: move the deal to Negotiation. Send revised pricing by Friday.\n',
      confirmation: {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'}},
    '006Globex': {StageName: 'Negotiation', NextStep: 'Legal review', fileVersion: 'sha256:ee260c4ffcd3129c8950438225a62d46fa6078f63464ba4aed6f0d034f7ebdb2',
      notes: 'Globex expansion meeting: the deal is Closed Lost for this year. Revisit next fiscal year.\n',
      confirmation: {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'}},
  };
  // These are fixture DATA assertions over the already admitted typed frame.
  // Known literal UTF8 bytes fix content CID/size. Dynamic original bindings
  // stay bound to this Run and scope; no bytes are read or reference issued.
  // All members below are closed ASCII metadata, so this fixed key order is
  // the canonical preimage without using a product CID/Content helper.
  const identityKeys = ['$actql_ref', 'authorityScopeCid', 'availability_evidence_cid',
    'capture_authority', 'capture_authority_cid', 'content_cid', 'content_store_cid', 'content_store_id',
    'data_classification', 'effective_data_policy_cid', 'evidence_cid', 'expiresAt', 'expires_at',
    'issuer_contract_cid', 'issuer_evidence', 'issuer_kind', 'media_type', 'metadata', 'name', 'reported_media_type',
    'retention_class', 'runDefinitionCid', 'size_bytes', 'storage_scope', 'storeAuthorityCid',
    'truncated', 'version', 'workspace_scope_cid'].sort();
  const identity = body => 'sha256:' + createHash('sha256')
    .update(JSON.stringify(body, identityKeys), 'utf8').digest('hex');
  let contentContext;
  const checkNotesReference = (actual, notes, subject) => {
    assert(actual !== null && typeof actual === 'object' && !Array.isArray(actual));
    const metadata = actual.metadata;
    assert(metadata !== null && typeof metadata === 'object' && !Array.isArray(metadata));
    const issuer = metadata.issuer_evidence;
    assert(issuer !== null && typeof issuer === 'object' && !Array.isArray(issuer));
    const storeAuthorityCid = issuer.content_store_cid, expiresAt = metadata.expires_at;
    assert(C.test(storeAuthorityCid) && C.test(issuer.capture_authority_cid) && C.test(metadata.effective_data_policy_cid));
    assert.equal(typeof expiresAt, 'string'); assert(Number.isFinite(Date.parse(expiresAt)));
    assert.equal(new Date(expiresAt).toISOString(), expiresAt); assert(Date.parse(expiresAt) > Date.now());
    const contentCid = 'sha256:' + createHash('sha256').update(notes, 'utf8').digest('hex');
    const issuerBody = {version: 'actql-content-issuer-evidence/0.1', issuer_kind: 'connector_capture',
      issuer_contract_cid: identity({version: 'actql-installed-local-policy/0.1', name: 'content-issuer',
        storeAuthorityCid, authorityScopeCid: subject.authorityScopeCid}),
      content_store_cid: storeAuthorityCid, workspace_scope_cid: subject.authorityScopeCid,
      content_cid: contentCid, effective_data_policy_cid: metadata.effective_data_policy_cid,
      capture_authority_cid: issuer.capture_authority_cid, reported_media_type: 'text/plain'};
    const body = {$actql_ref: 'content', version: 'actql-content-ref/0.1', media_type: 'text/plain', metadata: {
      content_store_id: 'local', content_cid: contentCid, media_type: 'text/plain', storage_scope: 'workspace',
      retention_class: 'local-content', capture_authority: 'read_content', data_classification: 'internal',
      effective_data_policy_cid: metadata.effective_data_policy_cid, expires_at: expiresAt,
      availability_evidence_cid: identity({version: 'actql-installed-local-policy/0.1', name: 'content-availability',
        storeAuthorityCid, runDefinitionCid: subject.runDefinitionCid, expiresAt}),
      size_bytes: Buffer.byteLength(notes), truncated: false,
      issuer_evidence: {...issuerBody, evidence_cid: identity(issuerBody)}}};
    assert.deepEqual(actual, {...body, content_ref_cid: identity(body)});
    const context = {storeAuthorityCid, expiresAt, policy: metadata.effective_data_policy_cid};
    if (contentContext === undefined) contentContext = context;
    else assert.deepEqual(context, contentContext, 'Both original notes share the same local Source context');
  };
  const destination = 'local:packed-joined-model-inputs';
  const inputs = new Map(), manifests = new Map();
  let failure;
  const checked = operation => {
    try {return operation();} catch (cause) {failure ??= cause; throw cause;}
  };
  const subjectMatches = (left, right) => left.runDefinitionCid === right.runDefinitionCid &&
    left.authorityScopeCid === right.authorityScopeCid;
  const configuration = {
    kind: 'typed-input', target: 'assessment', destination, maxBytes: 262144,
    authorize(binding) {
      return binding.kind === 'typed-input' && binding.destination === destination &&
        binding.target === 'assessment' && binding.purpose === 'capture' &&
        C.test(binding.subject?.runDefinitionCid) && C.test(binding.subject?.authorityScopeCid) &&
        JSON.parse(binding.policy.wire).unknown_provenance === true;
    },
    sink: {
      async capture({kind, subject, target, original, attemptCid, wires}) {
        return checked(() => {
          assert.equal(target, 'assessment');
          assert.equal(kind, 'typed-input'); assert.deepEqual(Object.keys(wires), ['typedInput']);
          assert(C.test(subject.runDefinitionCid) && C.test(subject.authorityScopeCid));
          assert(C.test(attemptCid));
          assert.equal(typeof wires.typedInput, 'string');
          assert(Buffer.byteLength(wires.typedInput) <= 65536);
          const input = JSON.parse(wires.typedInput);
          for (const [field, actual] of [['model_call_slot_cid', original.modelCallSlotCid],
            ['semantic_request_cid', original.semanticRequestCid], ['model_task_contract_cid', original.modelTaskCid]]) {
            assert(C.test(actual)); assert.equal(input[field], actual);
          }
          assert.equal(input.key.length, 1);
          const key = input.key[0]; assert(Object.hasOwn(originals, key));
          const expected = originals[key], role = Object.hasOwn(input.inputs, 'StageName') ? 'review' : 'confirm';
          if (role === 'confirm') assert.deepEqual(input.inputs, expected.confirmation);
          else if (selectedVariant === 'two-models-joined-inputs') assert.deepEqual(input.inputs, {
            StageName: expected.StageName, NextStep: expected.NextStep, fileVersion: expected.fileVersion,
          });
          else {
            const {notes, ...columns} = input.inputs;
            assert.deepEqual(columns, {StageName: expected.StageName, NextStep: expected.NextStep});
            checkNotesReference(notes, expected.notes, subject);
          }
          const identity = role + '/' + key;
          assert(!inputs.has(identity), 'One original input comparison per Model call');
          assert(inputs.size < 4);
          assert(![...inputs.values()].some(value => value.slot === original.modelCallSlotCid));
          inputs.set(identity, {subject, role, slot: original.modelCallSlotCid,
            task: original.modelTaskCid, attempt: attemptCid});
          return {status: 'complete'}; // Consumed here, no durable Evidence reference claimed.
        });
      },
      async record({subject, target, manifest}) {
        return checked(() => {
          assert.equal(target, 'assessment'); assert.equal(manifest.kind, 'typed-input');
          const code = value => typeof value === 'string' ? value.slice(0, 80) : undefined;
          assert.equal(manifest.status, 'complete', 'Incomplete typed-input Evidence: ' + JSON.stringify({
            kind: code(manifest.kind), status: code(manifest.status), reason: code(manifest.reason),
            items: Array.isArray(manifest.items) ? manifest.items.slice(0, 2).map(item =>
              ({status: code(item.status), reason: code(item.reason)})) : undefined,
            captures: inputs.size,
          }));
          assert(subjectMatches(subject, manifest.subject));
          assert(C.test(manifest.modelTaskCid));
          assert(!manifests.has(manifest.modelTaskCid));
          assert(manifests.size < 2); assert.equal(manifest.items.length, 2);
          const calls = [...inputs.values()].filter(value => value.task === manifest.modelTaskCid);
          assert.equal(calls.length, 2);
          assert.equal(new Set(manifest.items.map(value => value.modelCallSlotCid)).size, 2);
          for (const item of manifest.items) {
            assert.equal(item.status, 'complete');
            assert(calls.some(value => value.slot === item.modelCallSlotCid && value.attempt === item.attemptCid &&
              subjectMatches(value.subject, subject)));
          }
          manifests.set(manifest.modelTaskCid, subject);
        });
      },
    },
  };
  return {configuration,
    verify(ref) {
      if (failure !== undefined) throw failure;
      assert.equal(inputs.size, 4); assert.equal(manifests.size, 2);
      for (const role of ['review', 'confirm']) for (const key of Object.keys(originals)) {
        const value = inputs.get(role + '/' + key); assert(value);
        assert(subjectMatches(value.subject, ref));
        assert(subjectMatches(manifests.get(value.task), ref));
      }
      assert.notEqual(inputs.get('review/006Acme').task, inputs.get('confirm/006Acme').task);
      return {complete: true, modelCalls: 4, joinedInputs: 2, confirmationInputs: 2};
    }};
}
const modelInputs = phase === 'capture' && joinedWholeProducer ? joinedModelInputEvidence(variant) : undefined;
let client, firstFailedStep, activeStep, primary, checkDiagnostic, runObservation, failed = false;
function checkWorkflowWork(observed, selectedPhase, writes, modelTasks = 1) {
  assert.equal(observed.complete, true, 'Lost, pending or unavailable observation cannot prove zero work');
  if (selectedPhase === 'capture') {
    // Both authored Projects select two external Source occurrences. Their
    // two retained rows each enter one INFER, or both declared dependent Tasks.
    // A Whole Stage Result is reused, not a third external Source acquisition.
    assert.equal(observed.sourceAcquisitionStarts, 2);
    assert.equal(observed.modelCallStarts, writes * modelTasks);
    assert.equal(observed.effectReplacementReturns, 0);
  } else {
    assert.equal(observed.sourceAcquisitionStarts, 0, 'Completed Source must not be reacquired');
    assert.equal(observed.modelCallStarts, 0, 'Completed Model calls must not restart');
    assert.equal(observed.effectReplacementReturns, selectedPhase === 'approve' ? writes : 0);
  }
}
// The original acceptance binds the observation revision. A later control
// cannot acquire another revision while reopening that same captured Run.
const workObservation = workflowWorkObservation({trackOriginal: workPurpose === 'original-run-control'});
const stepDiagnosticFailures = [];
async function step(name, operation) {
  activeStep = name;
  const startedAt = new Date().toISOString(), started = process.hrtime.bigint(), cpu = process.cpuUsage();
  let status = 'failed';
  try {
    const result = await operation();
    status = 'passed';
    return result;
  } catch (cause) {
    firstFailedStep ??= name;
    throw cause;
  } finally {
    const used = process.cpuUsage(cpu);
    const timing = {startedAt, endedAt: new Date().toISOString(),
      wallNs: Number(process.hrtime.bigint() - started), cpuUserUs: used.user, cpuSystemUs: used.system,
      scope: 'Same workflow child, inclusive operation interval; observation overhead included'};
    try {console.log(JSON.stringify({phase, step: name, status, timing}));}
    catch (cause) {stepDiagnosticFailures.push({name: cause?.name, code: cause?.code});}
  }
}
// Read this exact call's retained SDK observation, never check or submit again.
// Facts, input bodies, context/revision IDs and submission references stay private.
function submissionCheckDiagnostic(error) {
  try {
    const original = getSubmissionCheckObservation(error);
    if (original === undefined) return {available: false};
    const report = original.report ?? original.partial_report;
    const token = value => typeof value === 'string' && /^[a-z][a-z0-9_.-]{0,127}$/u.test(value);
    const entries = [...(report?.reasons ?? []), ...(report?.requirements ?? []),
      ...(report?.coverage?.limits ?? []), ...(report?.coverage?.unresolved ?? [])];
    const reasons = entries.slice(0, 32).filter(entry => token(entry.code)).map(entry => {
      const result = {code: entry.code}, source = entry.location;
      if (!source || !['text', 'structured'].includes(source.kind)) return result;
      const location = {kind: source.kind};
      if (['program', 'source', 'parameters', 'parameter_declarations'].includes(source.document_id)) {
        location.document = source.document_id;
      }
      if (source.kind === 'text' && Number.isSafeInteger(source.start_byte) && source.start_byte >= 0 &&
          Number.isSafeInteger(source.end_byte) && source.end_byte >= source.start_byte) {
        location.start_byte = source.start_byte; location.end_byte = source.end_byte;
      }
      if (source.kind === 'structured' && typeof source.pointer === 'string' &&
          source.pointer.length <= 512 && /^(?:\/[A-Za-z0-9_~.-]*)*$/u.test(source.pointer)) {
        location.pointer = source.pointer;
      }
      result.location = location;
      return result;
    });
    return {available: true, ...(token(original.outcome) ? {outcome: original.outcome} : {}),
      ...(token(report?.verdict) ? {verdict: report.verdict} : {}), reasons, truncated: entries.length > 32};
  } catch {return {available: false};} // Diagnostics never replace the original refusal or close.
}
// Only the exact public response already returned to this call. Do not poll,
// reconstruct a cause from status, or print private Run/Checkpoint identities,
// messages, authored input, rows or Source material into the step report.
function publicRunObservation(state) {
  try {
    if (!['preparing', 'running', 'waiting_checkpoint', 'resuming',
      'needs_reconciliation', 'succeeded', 'failed', 'cancelled'].includes(state?.status)) {
      return {available: false};
    }
    const code = state.terminal_error?.code;
    const result = {available: true, status: state.status,
      ...(typeof code === 'string' && /^[A-Za-z][A-Za-z0-9_.-]{0,127}$/u.test(code)
        ? {terminalCode: code} : {})};
    if (['resolve_checkpoint', 'reconcile', 'read_result', 'refresh_availability',
      'none', 'reconcile_run'].includes(state.next_action?.kind)) {
      result.nextAction = state.next_action.kind;
    }
    if (['unknown', 'confirmed'].includes(state.control?.physical_stop)) {
      result.physicalStop = state.control.physical_stop;
    }
    if (typeof state.control?.cancellation_requested === 'boolean') {
      result.cancellationRequested = state.control.cancellation_requested;
    }
    return result;
  } catch {return {available: false};}
}
const snapshot = info => ({dev: String(info.dev), ino: String(info.ino),
  size: String(info.size), mtimeNs: String(info.mtimeNs)});
const dataPath = 'mock/data.json';
const targetState = async () => ({bytes: await readFile(dataPath, 'utf8'),
  file: snapshot(await stat(dataPath, {bigint: true}))});
const save = (path, value) => writeFile(path, JSON.stringify(value) + '\n',
  {encoding: 'utf8', mode: 0o600, flag: 'wx'});


try {
  client = await step('connect', () => connect({mode: 'local',
    installation: {directory: '.actql', observation: workObservation.connection,
      ...(modelInputs === undefined ? {} : {inferEvidence: modelInputs.configuration})}, profile: 'mock'}));
  if (phase === 'capture') {
    const before = await step('read authored target before submission', targetState);
    const execution = await startMockProjectSource({client, template, variant, handoffPath, step,
      readProgram: readFile, save});
    const state = await step('wait for original Checkpoint', async () => {
      const state = await execution.wait();
      runObservation = publicRunObservation(state);
      assert.equal(state.status, 'waiting_checkpoint');
      assert.ok(state.checkpoint);
      assert.equal(state.checkpoint.id, state.checkpoint.checkpoint_id);
      return state;
    });
    const summary = await step('exact Checkpoint lookup', async () => {
      const page = await client.checkpoints({checkpointId: state.checkpoint.id});
      assert.equal(page.items.length, 1);
      assert.equal(page.items[0].checkpointCid, state.checkpoint.checkpoint_cid);
      return page.items[0];
    });
    const review = await step('read original sealed review', async () => {
      const review = await client.reviewCheckpoint(summary);
      await writeFile(handoffPath + '.review', review.bytes, {mode: 0o600, flag: 'wx'});
      checkReview(JSON.parse(Buffer.from(review.bytes).toString('utf8')), summary, execution.ref);
      return review;
    });
    await step('no write before approval', async () => assert.deepEqual(await targetState(), before));
    await step('retain original recovery reference', () => save(handoffPath,
      {ref: execution.ref, runId: state.run_id,
      checkpointId: state.checkpoint.id, summary,
      reviewBase64: Buffer.from(review.bytes).toString('base64'), before,
      expectedBytes: expectedBytes(before.bytes), ...(dealReview ? {template} : {}), ...(twoModels || variant === 'multiple-targets' ? {variant} : {})}));
  } else {
    const captured = await step('read original public recovery reference', async () => {
      const captured = JSON.parse(await readFile(handoffPath, 'utf8'));
      assert.equal(captured.template ?? 'churn-risk-mock', template);
      assert.equal(captured.variant ?? 'readme', variant);
      return captured;
    });
    const execution = await step('attach same original Run', async () => {
      const execution = await client.attach(captured.ref);
      assert.deepEqual(execution.ref, captured.ref);
      return execution;
    });
    if (phase === 'approve') {
      await step('recover original Checkpoint', async () => {
        const state = await execution.status();
        assert.equal(state.run_id, captured.runId);
        assert.equal(state.status, 'waiting_checkpoint');
        assert.ok(state.checkpoint);
        assert.equal(state.checkpoint.id, captured.checkpointId);
      });
      await step('recover identical sealed review', async () => {
        const review = await client.reviewCheckpoint(captured.summary);
        assert.equal(Buffer.from(review.bytes).toString('base64'), captured.reviewBase64);
      });
      await step('still no write before approval', async () =>
        assert.deepEqual(await targetState(), captured.before));
      await step('explicit default-Local approval', async () => {
        const answer = await client.approve(captured.checkpointId);
        assert.equal(answer.results.length, 1);
        assert.equal(answer.results[0].status, 'committed');
        assert.equal(answer.signed.length, 1);
        const resolution = JSON.parse(answer.signed[0].resolutionWire);
        assert.equal(resolution.decision, 'approved');
        assert.equal(resolution.run_id, captured.runId);
        assert.equal(resolution.run_definition_cid, captured.ref.runDefinitionCid);
        assert.equal(resolution.checkpoint_cid, captured.summary.checkpointCid);
        assert.equal(resolution.review_projection_cid, captured.summary.reviewProjectionCid);
      });
      const terminal = await step('same Run explicit UPDATE completion', async () => {
        const state = await execution.wait();
        assert.equal(state.status, 'succeeded');
        assert.equal(state.run_id, captured.runId);
        return state;
      });
      let allResults;
      const rows = await step('original Named Result', async () => {
        const rows = await execution.result('updates').all();
        checkRows(rows);
        if (wholeProducer) allResults = await (joinedWholeProducer ? readJoinedWholeResults : readWholeResults)(execution, rows);
        return rows;
      });
      const after = await step('exact conditional target bytes', async () => {
        const after = await targetState();
        assert.equal(after.bytes, captured.expectedBytes); return after;
      });
      await step('retain approved recovery reference', () => save(handoffPath + '.approved.json',
        {ref: execution.ref, runId: terminal.run_id, rows, after,
          ...(wholeProducer ? {allResults} : {}),
          ...(dealReview ? {template} : {}), ...(twoModels || variant === 'multiple-targets' ? {variant} : {})}));
    } else {
      const approved = await step('read approved public recovery reference', async () => {
        const approved = JSON.parse(await readFile(handoffPath + '.approved.json', 'utf8'));
        assert.equal(approved.template ?? 'churn-risk-mock', template);
        assert.equal(approved.variant ?? 'readme', variant);
        assert.deepEqual(execution.ref, approved.ref);
        return approved;
      });
      // Saved Result must work before status can reopen a computation path.
      await step('recover original Named Result', async () => {
        const rows = await execution.result('updates').all();
        checkRows(rows); assert.deepEqual(rows, approved.rows);
        if (wholeProducer) assert.deepEqual(await (joinedWholeProducer ? readJoinedWholeResults : readWholeResults)(execution, rows), approved.allResults);
      });
      await step('recover completed same Run', async () => {
        const state = await execution.status();
        assert.equal(state.status, 'succeeded');
        assert.equal(state.run_id, approved.runId);
      });
      // Same bytes and physical inode/mtime show that completed recovery did
      // not replace this target again. This does not count Source acquisitions.
      await step('no repeated target replacement on recovery', async () =>
        assert.deepEqual(await targetState(), approved.after));
    }
  }
} catch (cause) {
  failed = true; primary = cause; firstFailedStep ??= activeStep;
  checkDiagnostic = submissionCheckDiagnostic(cause);
  try {
    if (runObservation === undefined && cause?.observation !== undefined) {
      runObservation = publicRunObservation(cause.observation);
    }
  } catch { /* Diagnostic getters cannot replace the original failure. */ }
}
let closeFailure, closeFailed = false, closeReturned = false;
const diagnosticFailures = [...stepDiagnosticFailures];
const pending = {phase, pid: process.pid, firstFailedStep: firstFailedStep ?? null,
  status: failed ? 'failed' : 'closing', code: primary?.code,
  workObservation: workObservation.snapshot(),
  firstClose: {attempted: client !== undefined, returned: false,
    state: client === undefined ? 'not-attempted' : 'pending'},
  ...(runObservation === undefined ? {} : {runObservation}),
  ...(checkDiagnostic === undefined ? {} : {checkObservation: checkDiagnostic})};
const persistCloseObservation = async () => {
  try {await writeFile(`${phase}.pending.json`, JSON.stringify(pending) + '\n', {mode: 0o600});}
  catch (cause) {diagnosticFailures.push({name: cause?.name, code: cause?.code});}
};
// This receipt precedes the FIRST close await. A pending receipt never proves
// cleanup or physical stop, even if its owning process later exits.
await persistCloseObservation();
if (client !== undefined) {
  try {await client.close(); closeReturned = true;}
  catch (cause) {closeFailure = cause; closeFailed = true; firstFailedStep ??= 'close';}
}
pending.firstClose = {attempted: client !== undefined, returned: closeReturned,
  state: closeReturned ? 'returned' : closeFailed ? 'threw' : 'not-attempted'};
pending.firstFailedStep = firstFailedStep ?? null;
pending.status = failed || closeFailed ? 'failed' : 'closed';
pending.cleanupCode = closeFailure?.code;
pending.workObservation = workObservation.snapshot();
let workFailure, modelInputObservation;
if (!failed && closeReturned) try {
  checkWorkflowWork(pending.workObservation, phase, multipleTargets ? multipleTargetMockWriteCount : Object.keys(expected).length,
    multipleTargets ? 0 : twoModels ? 2 : 1);
  if (modelInputs !== undefined) {
    const original = JSON.parse(await readFile(handoffPath + '.started', 'utf8'));
    modelInputObservation = modelInputs.verify(original.ref);
  }
} catch (cause) {workFailure = cause; firstFailedStep ??= 'observe actual Source Model and Effect work';}
await persistCloseObservation();
console.log(JSON.stringify({phase, firstFailedStep: firstFailedStep ?? null,
  status: failed || closeFailed || workFailure || diagnosticFailures.length ? 'failed' : 'passed',
  code: primary?.code, cleanupCode: closeFailure?.code,
  workObservation: pending.workObservation, workObservationCode: workFailure?.code,
  ...(modelInputObservation === undefined ? {} : {modelInputObservation}),
  ...(diagnosticFailures.length ? {diagnosticFailures} : {}),
  firstClose: {attempted: client !== undefined, returned: closeReturned},
  ...(runObservation === undefined ? {} : {runObservation}),
  ...(checkDiagnostic === undefined ? {} : {checkObservation: checkDiagnostic})}));
if (failed) throw primary;
if (closeFailed) throw closeFailure;
if (workFailure) throw workFailure;
if (diagnosticFailures.length) throw new Error('WorkflowDiagnosticsFailed');
